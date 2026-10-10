#!/bin/bash
# The rig's phone: a network namespace, a private session bus, a private
# kdeconnectd and a headless Android emulator paired to it. Sourced by dev/rig,
# never run directly.
#
# Isolation, in one paragraph. Everything that talks to a phone runs in a user
# and network namespace of its own ("the holder"): the session bus, the daemon,
# adb, the emulator, scrcpy, the nested compositor and the shell. The namespace
# has one interface (dummy0, 10.255.0.2) and no route to anything real, so the
# owner's kdeconnectd, adb server and phone cannot hear it and it cannot hear
# them. Unix sockets cross namespaces, which is what lets the host side
# (`dev/rig exec`, hyprctl, grim) reach the rig. The PID namespace is NOT
# separate: never kill by name. Kill by recorded pid, by the OPR_RIG_ID tag, or
# by comparing /proc/<pid>/ns/net with the holder's.
#
# shellcheck shell=bash

RIG_NS_ADDR=10.255.0.2
RIG_NS_GATEWAY=10.255.0.1
RIG_NS_FORWARDS="1739 1764"
RIG_ADB_PORT=5037
RIG_EMU_PORT=5554
RIG_AVD_NAME=rig
RIG_PHONE_BOOT_TIMEOUT=240

RIG_IN_NS=()
RIG_NETNS_PID=""
RIG_BUS_PID=""
RIG_ADB_PID=""
RIG_EMU_PID=""
RIG_KDCD_PID=""

# ---------------------------------------------------------------- location ----

rig_ns_define() {
  # RIG_IN_NS is the prefix that puts a command into the rig's namespaces as
  # the same uid (nsexec.py keeps CAP_SYS_ADMIN, which sshfs needs to mount the
  # phone's storage). Empty while there is no holder (or with --no-phone): then
  # commands simply run on the host, with the rig's sandbox environment.
  RIG_IN_NS=()
  [[ -n ${RIG_NETNS_PID:-} ]] && kill -0 "$RIG_NETNS_PID" 2>/dev/null || return 0
  RIG_IN_NS=(python3 "$RIG_DIR/rig.d/nsexec.py" "$RIG_NETNS_PID" --)
}

rig_android_sdk() {
  # The SDK that has both the emulator and platform-tools; printed, or failure.
  local home candidate
  home=$(getent passwd "$(id -u)" | cut -d: -f6)
  for candidate in "${RIG_ANDROID_SDK:-}" "${ANDROID_SDK_ROOT:-}" "${ANDROID_HOME:-}" \
    "$RIG_HOST_HOME/Android/Sdk" "$home/Android/Sdk" /opt/android-sdk; do
    [[ -n $candidate && -x $candidate/emulator/emulator && -x $candidate/platform-tools/adb ]] || continue
    printf '%s\n' "$candidate"
    return 0
  done
  return 1
}

rig_phone_export_env() {
  # The rig's session bus once it exists, and the Android tools' homes inside
  # the sandbox (the adb key, the AVD, the emulator's console token), never the
  # owner's ~/.android.
  if [[ -n ${RIG_RUNTIME_DIR:-} && -S $RIG_RUNTIME_DIR/bus ]]; then
    export DBUS_SESSION_BUS_ADDRESS="unix:path=$RIG_RUNTIME_DIR/bus"
  fi
  local sdk
  sdk=$(rig_android_sdk) || return 0
  RIG_ANDROID_SDK=$sdk
  export ANDROID_SDK_ROOT="$sdk" ANDROID_HOME="$sdk"
  export ANDROID_USER_HOME="$HOME/.android"
  export ANDROID_AVD_HOME="$HOME/.android/avd"
  export ANDROID_EMULATOR_HOME="$HOME/.android"
  case ":$PATH:" in
  *":$sdk/platform-tools:"*) ;;
  *) export PATH="$sdk/platform-tools:$sdk/emulator:$PATH" ;;
  esac
}

# ------------------------------------------------------------- prerequisites ----

rig_phone_require() {
  local missing=() tool sdk
  for tool in ip unshare socat dbus-daemon kdeconnectd kdeconnect-cli busctl \
    python3 sha256sum curl getent; do
    command -v "$tool" >/dev/null 2>&1 || missing+=("$tool")
  done
  ((${#missing[@]} == 0)) || rig_die "the phone side needs: ${missing[*]}"

  sdk=$(rig_android_sdk) ||
    rig_die "no Android SDK with emulator and platform-tools (set ANDROID_SDK_ROOT, or run with --no-phone)"
  [[ -r /dev/kvm && -w /dev/kvm ]] ||
    rig_die "the emulator needs /dev/kvm. Owner, once: sudo usermod -aG kvm $USER  (then log in again), or run with --no-phone"
  [[ -d $sdk/${RIG_ANDROID_IMAGE//;/\/} ]] ||
    rig_die "system image missing. Owner, once: $sdk/cmdline-tools/latest/bin/sdkmanager '$RIG_ANDROID_IMAGE'"
  unshare -Urn true 2>/dev/null ||
    rig_die "unprivileged user+network namespaces are off (kernel.unprivileged_userns_clone); the phone side needs them"
}

# ------------------------------------------------------------------- holder ----

rig_netns_start() {
  # A user, network and mount namespace (the mount one keeps the phone's
  # storage mount out of the owner's mount table). Its own loopback and one dummy interface. The
  # emulator needs a non-loopback address and a default route to resolve its
  # host-side names; nothing in here has a path out.
  local pidfile="$RIG_SESSION/netns.pid" i
  rm -f "$pidfile"
  setsid unshare -U "--map-user=$(id -u)" "--map-group=$(id -g)" --keep-caps -nm bash -c "
    ip link set lo up &&
    ip link add dummy0 type dummy &&
    ip addr add $RIG_NS_ADDR/24 dev dummy0 &&
    ip link set dummy0 multicast on up &&
    ip route add default via $RIG_NS_GATEWAY dev dummy0 &&
    echo \$\$ >'$pidfile' &&
    exec sleep infinity" >>"$RIG_LOGS/netns.log" 2>&1 </dev/null &
  for i in $(seq 1 50); do
    [[ -s $pidfile ]] && break
    sleep 0.1
  done
  [[ -s $pidfile ]] || rig_die "the network namespace did not come up (see $RIG_LOGS/netns.log)"
  RIG_NETNS_PID=$(<"$pidfile")
  [[ $(readlink "/proc/$RIG_NETNS_PID/ns/net") != "$(readlink /proc/$$/ns/net)" ]] ||
    rig_die "guard: the holder shares the owner's network namespace"
  rig_state_set netns_pid "$RIG_NETNS_PID"
  rig_ns_define
  rig_ok "network namespace (holder pid $RIG_NETNS_PID, $RIG_NS_ADDR, no route out)"
}

# ---------------------------------------------------------------------- bus ----

rig_bus_start() {
  # A session bus with no activation and no policy: nothing is started on
  # demand (no keyring, no portals), only what the rig starts by hand.
  local conf="$RIG_SESSION/bus.conf" i
  cat >"$conf" <<CONF
<!DOCTYPE busconfig PUBLIC "-//freedesktop//DTD D-Bus Bus Configuration 1.0//EN" "http://www.freedesktop.org/standards/dbus/1.0/busconfig.dtd">
<busconfig>
  <type>session</type>
  <keep_umask/>
  <listen>unix:path=$RIG_RUNTIME_DIR/bus</listen>
  <auth>EXTERNAL</auth>
  <policy context="default">
    <allow send_destination="*" eavesdrop="true"/>
    <allow eavesdrop="true"/>
    <allow own="*"/>
  </policy>
</busconfig>
CONF
  "${RIG_IN_NS[@]}" dbus-daemon --config-file="$conf" --nofork >>"$RIG_LOGS/bus.log" 2>&1 &
  RIG_BUS_PID=$!
  for i in $(seq 1 50); do
    [[ -S $RIG_RUNTIME_DIR/bus ]] && break
    sleep 0.1
  done
  [[ -S $RIG_RUNTIME_DIR/bus ]] || rig_die "the rig session bus did not start (see $RIG_LOGS/bus.log)"
  rig_state_set bus_pid "$RIG_BUS_PID"
  rig_phone_export_env
  rig_guard_bus
  rig_ok "session bus $DBUS_SESSION_BUS_ADDRESS (pid $RIG_BUS_PID)"
}

rig_guard_bus() {
  # Prove the bus in DBUS_SESSION_BUS_ADDRESS is the rig's, and that the owner's
  # kdeconnectd is not on it.
  [[ ${DBUS_SESSION_BUS_ADDRESS:-} == "unix:path=$RIG_RUNTIME_DIR/bus" ]] ||
    rig_die "guard: session bus is ${DBUS_SESSION_BUS_ADDRESS:-unset}, not the rig's"
  if busctl --user list --no-pager 2>/dev/null | grep -q 'org.kde.kdeconnect'; then
    [[ -n ${RIG_KDCD_PID:-} ]] || rig_die "guard: a KDE Connect daemon is on the rig bus before the rig started one"
  fi
}

# ----------------------------------------------------------------------- adb ----

rig_adb() { "${RIG_IN_NS[@]}" adb "$@"; }

rig_adb_start() {
  # `-a` so the server listens on the namespace's address too: the phone's
  # payload connections to the daemon (ports 1739-1764) land on that address
  # and are carried to the phone by `adb forward`.
  "${RIG_IN_NS[@]}" adb -a -P "$RIG_ADB_PORT" nodaemon server >>"$RIG_LOGS/adb.log" 2>&1 &
  RIG_ADB_PID=$!
  rig_state_set adb_pid "$RIG_ADB_PID"
  local i
  for i in $(seq 1 50); do
    rig_adb devices >/dev/null 2>&1 && break
    sleep 0.2
  done
  rig_adb devices >/dev/null 2>&1 || rig_die "adb server did not start (see $RIG_LOGS/adb.log)"
  rig_ok "adb server (pid $RIG_ADB_PID, in the namespace)"
}

rig_adb_shell() { rig_adb -s "emulator-$RIG_EMU_PORT" shell "$@"; }

# ------------------------------------------------------------------ emulator ----

rig_avd_create() {
  # The AVD is written by hand: avdmanager needs Java and a lot of ceremony
  # for a file this small.
  local avd="$ANDROID_AVD_HOME/$RIG_AVD_NAME.avd" image=${RIG_ANDROID_IMAGE//;/\/}
  mkdir -p "$avd" "$ANDROID_AVD_HOME"
  cat >"$ANDROID_AVD_HOME/$RIG_AVD_NAME.ini" <<INI
avd.ini.encoding=UTF-8
path=$avd
path.rel=avd/$RIG_AVD_NAME.avd
target=android-$RIG_ANDROID_API
INI
  cat >"$avd/config.ini" <<INI
AvdId = $RIG_AVD_NAME
avd.ini.displayname = $RIG_AVD_NAME
PlayStore.enabled = no
abi.type = x86_64
disk.dataPartition.size = ${RIG_EMU_DATA_GB}G
hw.arc = false
hw.battery = yes
hw.cpu.arch = x86_64
hw.cpu.ncore = $RIG_EMU_CORES
hw.device.manufacturer = Google
hw.device.name = pixel_6
hw.gps = no
hw.gpu.enabled = yes
hw.gpu.mode = swiftshader_indirect
hw.gsmModem = yes
hw.initialOrientation = portrait
hw.lcd.density = $RIG_EMU_DENSITY
hw.lcd.height = $RIG_EMU_HEIGHT
hw.lcd.width = $RIG_EMU_WIDTH
hw.keyboard = yes
hw.mainKeys = no
hw.ramSize = $RIG_EMU_RAM_MB
hw.sdCard = no
hw.camera.back = none
hw.camera.front = none
hw.audioInput = no
hw.audioOutput = no
image.sysdir.1 = $image/
tag.display = Google APIs
tag.id = google_apis
target = android-$RIG_ANDROID_API
INI
}

rig_emulator_start() {
  rig_avd_create
  # The emulator keeps its crash dumps and temp files in $TMPDIR, so it gets
  # the rig's own and nothing lands in /tmp/android-<user>.
  TMPDIR="$RIG_TMPDIR" "${RIG_IN_NS[@]}" "$RIG_ANDROID_SDK/emulator/emulator" -avd "$RIG_AVD_NAME" \
    -no-window -no-audio -no-snapshot -no-boot-anim -no-metrics \
    -gpu swiftshader_indirect -port "$RIG_EMU_PORT" -no-passive-gps -wipe-data \
    >>"$RIG_LOGS/emulator.log" 2>&1 &
  RIG_EMU_PID=$!
  rig_state_set emulator_pid "$RIG_EMU_PID"
  rig_step "emulator starting (pid $RIG_EMU_PID, ${RIG_EMU_RAM_MB} MB, ${RIG_EMU_WIDTH}x${RIG_EMU_HEIGHT})"
}

rig_emulator_wait_boot() {
  local deadline=$((SECONDS + RIG_PHONE_BOOT_TIMEOUT)) booted=""
  while ((SECONDS < deadline)); do
    kill -0 "$RIG_EMU_PID" 2>/dev/null || rig_die "the emulator died while booting (see $RIG_LOGS/emulator.log)"
    booted=$(rig_adb_shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')
    [[ $booted == 1 ]] && break
    sleep 2
  done
  [[ $booted == 1 ]] || rig_die "the emulator did not finish booting in ${RIG_PHONE_BOOT_TIMEOUT}s"
  rig_adb_shell settings put global stay_on_while_plugged_in 7 >/dev/null 2>&1
  rig_adb_shell settings put system screen_off_timeout 2147483647 >/dev/null 2>&1
  rig_adb_shell wm dismiss-keyguard >/dev/null 2>&1
  rig_ok "emulator booted ($(rig_adb_shell getprop ro.product.model | tr -d '\r'), Android $(rig_adb_shell getprop ro.build.version.release | tr -d '\r'))"
}

# ------------------------------------------------------------ KDE Connect app ----

rig_kdc_apk() {
  # The pinned APK, fetched once, checked every time. Printed path, or failure.
  local dir="$RIG_TMP_ROOT/cache" apk got signer
  apk="$dir/$RIG_KDC_APK_NAME"
  mkdir -p "$dir"
  if [[ ! -s $apk ]]; then
    rig_step "downloading $RIG_KDC_APK_NAME (once)"
    curl -fsSL --max-time 300 -o "$apk.part" "$RIG_KDC_APK_URL" || {
      rm -f "$apk.part"
      return 1
    }
    mv "$apk.part" "$apk"
  fi
  got=$(sha256sum "$apk" | cut -d' ' -f1)
  [[ $got == "$RIG_KDC_APK_SHA256" ]] || {
    rig_fail "KDE Connect APK hash $got is not the pinned $RIG_KDC_APK_SHA256"
    rm -f "$apk"
    return 1
  }
  local apksigner
  apksigner=$(ls "$RIG_ANDROID_SDK"/build-tools/*/apksigner 2>/dev/null | tail -n1)
  if [[ -n $apksigner ]]; then
    signer=$("$apksigner" verify --print-certs "$apk" 2>/dev/null | sed -n 's/^Signer #1 certificate SHA-256 digest: //p')
    [[ $signer == "$RIG_KDC_APK_SIGNER_SHA256" ]] || {
      rig_fail "KDE Connect APK signer ${signer:-unknown} is not the pinned one"
      return 1
    }
  else
    rig_warn "no apksigner in the SDK build-tools; the APK is checked by hash only"
  fi
  printf '%s\n' "$apk"
}

rig_kdc_app_setup() {
  local apk pkg=org.kde.kdeconnect_tp perm
  apk=$(rig_kdc_apk) || rig_die "could not get the pinned KDE Connect APK"
  rig_adb -s "emulator-$RIG_EMU_PORT" install -g "$apk" >>"$RIG_LOGS/adb.log" 2>&1 ||
    rig_die "installing KDE Connect on the emulator failed (see $RIG_LOGS/adb.log)"
  for perm in READ_SMS SEND_SMS RECEIVE_SMS RECEIVE_MMS READ_CONTACTS READ_PHONE_STATE \
    READ_CALL_LOG POST_NOTIFICATIONS; do
    rig_adb_shell pm grant "$pkg" "android.permission.$perm" >/dev/null 2>&1
  done
  # A busy host makes the emulator's system UI miss its deadline; its "isn't
  # responding" dialog would cover the pairing prompt.
  rig_adb_shell settings put global hide_error_dialogs 1 >/dev/null 2>&1
  rig_adb_shell appops set "$pkg" MANAGE_EXTERNAL_STORAGE allow >/dev/null 2>&1
  rig_adb_shell appops set "$pkg" SYSTEM_ALERT_WINDOW allow >/dev/null 2>&1
  # Notification access has to be granted before the app first links, or the
  # notifications plugin stays at "No permission" for that link.
  rig_adb_shell cmd notification allow_listener \
    "$pkg/org.kde.kdeconnect.plugins.notifications.NotificationReceiver" >/dev/null 2>&1
  # `cmd notification post` runs as the shell uid and needs to be allowed to post.
  rig_adb_shell pm grant com.android.shell android.permission.POST_NOTIFICATIONS >/dev/null 2>&1
  rig_adb_shell am start -n "$pkg/org.kde.kdeconnect.ui.MainActivity" >/dev/null 2>&1
  rig_ok "KDE Connect for Android $RIG_KDC_APK_NAME installed and permitted"
}

# ------------------------------------------------------------------- daemon ----

rig_kdcd_config() {
  local dir="$XDG_CONFIG_HOME/kdeconnect"
  mkdir -p "$dir"
  # The daemon drops identity packets that come from a local address, and the
  # emulator's host loopback looks local. So discovery runs the other way: the
  # daemon sends its identity to 127.0.0.1:1716, which the emulator redirects
  # into the phone, and the phone connects back to its host (10.0.2.2:1716).
  cat >"$dir/config" <<CONF
[General]
customDevices=127.0.0.1
keyAlgorithm=EC
name=$RIG_KDC_NAME
CONF
}

rig_kdcd_start() {
  local forward i
  rig_adb -s "emulator-$RIG_EMU_PORT" emu redir add udp:1716:1716 >/dev/null 2>&1 ||
    rig_die "could not redirect UDP 1716 into the emulator"
  # The payload ports must reach the phone before the daemon links, or the
  # first notification icon download hangs for good and every later
  # notification with that icon is silently lost.
  for i in $(seq "${RIG_NS_FORWARDS% *}" "${RIG_NS_FORWARDS#* }"); do
    rig_adb -s "emulator-$RIG_EMU_PORT" forward "tcp:$i" "tcp:$i" >/dev/null 2>&1 ||
      rig_die "adb forward tcp:$i failed"
  done
  rig_kdcd_config
  TMPDIR="$RIG_TMPDIR" QT_QPA_PLATFORM=offscreen QT_FORCE_STDERR_LOGGING=1 \
    QT_LOGGING_RULES="kdeconnect*=true" \
    "${RIG_IN_NS[@]}" kdeconnectd >>"$RIG_LOGS/kdeconnectd.log" 2>&1 &
  RIG_KDCD_PID=$!
  rig_state_set kdeconnectd_pid "$RIG_KDCD_PID"
  for i in $(seq 1 100); do
    busctl --user list --no-pager 2>/dev/null | grep -q 'org.kde.kdeconnect ' && break
    kill -0 "$RIG_KDCD_PID" 2>/dev/null || rig_die "kdeconnectd died (see $RIG_LOGS/kdeconnectd.log)"
    sleep 0.2
  done
  rig_ok "kdeconnectd on the rig bus (pid $RIG_KDCD_PID), announcing as \"$RIG_KDC_NAME\""
}

rig_kdc_devices() {
  # rig_kdc_devices <flag> — device ids from kdeconnect-cli (-a reachable,
  # --list-devices all known), one per line.
  kdeconnect-cli "$1" --id-only 2>/dev/null
}

# A tap target on the phone's current screen: the centre of the first node whose
# text is one of the given words. Reads uiautomator's XML on stdin.
RIG_UI_FIND='
import re, sys, xml.etree.ElementTree as ET
raw = sys.stdin.read()
end = raw.find("</hierarchy>")
if end < 0:
    sys.exit(1)
root = ET.fromstring(raw[raw.find("<?xml"):end + len("</hierarchy>")])
for want in sys.argv[1:]:
    for node in root.iter("node"):
        if node.get("text", "").strip().lower() == want.lower():
            m = re.match(r"\[(\d+),(\d+)\]\[(\d+),(\d+)\]", node.get("bounds", ""))
            if m:
                x1, y1, x2, y2 = map(int, m.groups())
                print((x1 + x2) // 2, (y1 + y2) // 2)
                sys.exit(0)
sys.exit(1)
'

rig_phone_tap_text() {
  # rig_phone_tap_text <text>... — tap the first of these words on screen.
  local xy
  xy=$(rig_adb -s "emulator-$RIG_EMU_PORT" exec-out uiautomator dump /dev/tty 2>/dev/null |
    python3 -c "$RIG_UI_FIND" "$@") || return 1
  # shellcheck disable=SC2086 # "x y"
  rig_adb_shell input tap $xy >/dev/null 2>&1
}

rig_kdc_pair() {
  # Pair the rig's daemon with the emulator's app and accept on the phone. The
  # phone side is driven through its own screen, as a person would.
  local id="" deadline=$((SECONDS + 90))
  while ((SECONDS < deadline)); do
    id=$(rig_kdc_devices --list-devices | head -n1)
    [[ -n $id ]] && break
    # The app may not listen yet when the daemon first sends its identity.
    kdeconnect-cli --refresh >/dev/null 2>&1
    sleep 3
  done
  [[ -n $id ]] || rig_die "the emulator's KDE Connect never showed up (see $RIG_LOGS/kdeconnectd.log)"
  rig_state_set phone_device_id "$id"
  if kdeconnect-cli --list-devices 2>/dev/null | grep -q "$id.*paired and reachable"; then
    rig_ok "already paired with the emulator ($id)"
    return 0
  fi
  # A pairing request lapses after 30 s on either side, so it is asked again.
  local asked=-100
  deadline=$((SECONDS + 120))
  while ((SECONDS < deadline)); do
    if ((SECONDS - asked >= 20)); then
      kdeconnect-cli -d "$id" --pair >>"$RIG_LOGS/kdeconnect-cli.log" 2>&1
      asked=$SECONDS
    fi
    if kdeconnect-cli --list-devices 2>/dev/null | grep -q "$id.*paired and reachable"; then
      rig_ok "paired with the emulator ($id)"
      return 0
    fi
    rig_adb_shell am start -n org.kde.kdeconnect_tp/org.kde.kdeconnect.ui.MainActivity >/dev/null 2>&1
    sleep 1
    rig_phone_tap_text "Wait" "Accept" "$RIG_KDC_NAME"
    sleep 2
  done
  rig_adb -s "emulator-$RIG_EMU_PORT" exec-out screencap -p >"$RIG_LOGS/pairing-failed.png" 2>/dev/null
  rig_die "pairing with the emulator did not complete (the phone's screen: $RIG_LOGS/pairing-failed.png)"
}

# -------------------------------------------------------------------- up/down ----

rig_phone_start() {
  # Before the display: the compositor and the shell run inside the namespace.
  rig_netns_start
  rig_bus_start
  rig_adb_start
  rig_emulator_start
}

rig_adb_wifi_start() {
  # The panel's screen link finds a phone by KDE Connect's address for it, as
  # adb over Wi-Fi. The emulator's adb port listens on loopback only, so a relay
  # on the namespace's address stands in for the phone's Wi-Fi adb.
  local port=$((RIG_EMU_PORT + 1)) i
  "${RIG_IN_NS[@]}" socat "TCP-LISTEN:$port,bind=$RIG_NS_ADDR,fork,reuseaddr" "TCP:127.0.0.1:$port" \
    >>"$RIG_LOGS/adb-wifi.log" 2>&1 </dev/null &
  rig_state_set adbwifi_pid "$!"
  for i in $(seq 1 30); do
    rig_adb connect "$RIG_NS_ADDR:$port" 2>/dev/null | grep -q "connected to" && return 0
    sleep 0.3
  done
  rig_warn "adb over Wi-Fi to the emulator did not connect (the screen link will not find it)"
}

rig_phone_finish() {
  # After the display: boot is the slow part, and the display starts while it runs.
  rig_emulator_wait_boot
  rig_kdc_app_setup
  rig_kdcd_start
  rig_kdc_pair
  rig_adb_wifi_start
  rig_phone_host_snapshot "$RIG_EVIDENCE/host-phone-after-up.txt"
}

rig_stop_pid() {
  # rig_stop_pid <what> <pid> [seconds] — TERM then KILL, by pid only.
  local what=$1 pid=${2:-} wait=${3:-10}
  [[ -n $pid ]] && kill -0 "$pid" 2>/dev/null || return 0
  rig_step "stopping $what (pid $pid)"
  rig_kill_tree "$pid" TERM
  rig_wait_gone "$pid" "$wait" || rig_kill_tree "$pid" KILL
  rig_wait_gone "$pid" 5 || rig_warn "$what (pid $pid) will not die"
}

rig_stop_phone() {
  RIG_KDCD_PID=$(rig_state_get kdeconnectd_pid 2>/dev/null || echo "")
  RIG_ADB_PID=$(rig_state_get adb_pid 2>/dev/null || echo "")
  RIG_EMU_PID=${RIG_EMU_PID:-$(rig_state_get emulator_pid 2>/dev/null || echo "")}
  RIG_BUS_PID=${RIG_BUS_PID:-$(rig_state_get bus_pid 2>/dev/null || echo "")}
  rig_stop_pid "kdeconnectd" "$RIG_KDCD_PID" 10
  rig_stop_pid "the adb Wi-Fi relay" "$(rig_state_get adbwifi_pid 2>/dev/null || echo "")" 5
  if [[ -n ${RIG_EMU_PID:-} ]] && kill -0 "$RIG_EMU_PID" 2>/dev/null; then
    # A clean power-off first: the emulator then removes its own lock files.
    rig_adb -s "emulator-$RIG_EMU_PORT" emu kill >/dev/null 2>&1
    rig_wait_gone "$RIG_EMU_PID" 20 || true
  fi
  rig_stop_pid "the emulator" "$RIG_EMU_PID" 10
  rig_stop_pid "adb" "$RIG_ADB_PID" 5
  rig_stop_pid "the session bus" "$RIG_BUS_PID" 5
}

rig_stop_netns_holder() {
  rig_stop_pid "the network namespace holder" "${RIG_NETNS_PID:-}" 5
}

# ------------------------------------------------------- the owner's own phone ----
#
# What the rig must not disturb: the owner's kdeconnectd, adb server and any
# emulator. Taken from /proc, read-only, and told apart from the rig's by
# network namespace, never by name alone.

rig_host_phone_pids() {
  local pid comm host_ns
  host_ns=$(readlink /proc/$$/ns/net)
  for pid in $(pgrep -x -u "$(id -u)" 'kdeconnectd|adb|qemu-system-x86|emulator' 2>/dev/null); do
    [[ $(readlink "/proc/$pid/ns/net" 2>/dev/null) == "$host_ns" ]] || continue
    comm=$(<"/proc/$pid/comm")
    # Only the adb server counts: the owner's own panel runs short-lived adb clients.
    if [[ $comm == adb ]]; then
      tr '\0' ' ' <"/proc/$pid/cmdline" 2>/dev/null | grep -q ' server' || continue
    fi
    printf '%s %s\n' "$pid" "$comm"
  done | sort -n
}

rig_phone_host_snapshot() {
  rig_host_phone_pids >"$1"
}

rig_phone_host_unchanged() {
  # rig_phone_host_unchanged <before-file> — failure and a diff when the owner's
  # kdeconnectd/adb/emulator set differs from before the rig. A process the
  # owner started meanwhile shows up as an addition; the report says so.
  local before=$1 now diff_out
  [[ -f $before ]] || return 2
  now=$(rig_host_phone_pids)
  diff_out=$(diff <(cat "$before") <(printf '%s\n' "$now") | grep '^[<>]' || true)
  [[ -z $diff_out ]] && return 0
  printf '%s\n' "$diff_out"
  return 1
}

# ------------------------------------------------------- what the checks ask ----

rig_ipc() { timeout 8 qs -p "$RIG_OMARCHY_PATH/shell" ipc call "$RIG_PLUGIN_ID" "$@"; }

rig_bridge_snapshot() { timeout 20 "$RIG_PLUGIN_SRC_ABS/bin/kdeconnect-bridge" snapshot; }

rig_phone_is_paired() {
  rig_bridge_snapshot | jq -e '[.devices[] | select(.paired and .reachable)] | length == 1' >/dev/null
}

rig_bridge_sees_battery() {
  rig_bridge_snapshot | jq -e '.devices[0].battery.charge >= 0' >/dev/null
}

rig_bridge_battery_is() {
  rig_bridge_snapshot | jq -e --argjson n "$1" '.devices[0].battery.charge == $n' >/dev/null
}

rig_bridge_has_notification() {
  rig_bridge_snapshot | jq -e --arg t "$1" '[.devices[0].notifications[] | tostring | contains($t)] | any' >/dev/null
}

rig_ipc_status_ok() {
  rig_ipc status | jq -e '.daemon == true and .reachable == true' >/dev/null
}

rig_bridge_ns() { timeout 90 "${RIG_IN_NS[@]}" "$RIG_PLUGIN_SRC_ABS/bin/kdeconnect-bridge" "$@"; }

rig_phone_id() { rig_bridge_snapshot | jq -r '.devices[0].id'; }

rig_phone_call_start() { rig_adb -s "emulator-$RIG_EMU_PORT" emu gsm call "$1" >/dev/null; }

rig_phone_call_end() { rig_adb -s "emulator-$RIG_EMU_PORT" emu gsm cancel "$1" >/dev/null; }

rig_ipc_call_is() { rig_ipc status | jq -e --arg s "$1" '(.call.state // "") == $s' >/dev/null; }

rig_ipc_call_is_not() { ! rig_ipc_call_is "$1"; }

rig_screen_ready() { rig_bridge_ns screen "$(rig_phone_id)" | jq -e '.state == "ready"' >/dev/null; }

rig_screen_open() { rig_bridge_ns screen-open "$(rig_phone_id)" --tiled --sound phone >/dev/null; }

rig_screen_window_open() { hyprctl clients -j | jq -e '[.[] | select(.class == "scrcpy")] | length >= 1' >/dev/null; }

rig_screen_window_gone() { ! rig_screen_window_open; }

rig_phone_battery_set() { rig_adb_shell dumpsys battery set level "$1" >/dev/null; }

rig_phone_notify() { rig_adb_shell "cmd notification post -t '$1' rig-$RANDOM '$2'" >/dev/null; }

# ----------------------------------------------------------------- operations ----

rig_phone_id() { rig_state_get phone_device_id; }

cmd_phone() {
  rig_select || rig_die "no rig for this owner; run 'dev/rig up' first"
  rig_export_env
  rig_guard_sandbox
  [[ -n ${RIG_NETNS_PID:-} ]] || rig_die "this rig has no phone (it was started with --no-phone)"
  local sub=${1:-status}
  shift || true
  case $sub in
  status)
    local id level
    id=$(rig_phone_id || true)
    level=$(rig_adb_shell dumpsys battery 2>/dev/null | sed -n 's/^ *level: //p' | tr -d '\r')
    printf '  emulator    pid %s, battery %s%%\n' "${RIG_EMU_PID:-?}" "${level:-?}"
    printf '  daemon      pid %s on %s\n' "$(rig_state_get kdeconnectd_pid || echo '?')" "$DBUS_SESSION_BUS_ADDRESS"
    printf '  device      %s\n' "${id:-?}"
    kdeconnect-cli --list-devices 2>&1 | sed 's/^/  /'
    ;;
  battery)
    case ${1:-} in
    unplug) rig_adb_shell dumpsys battery unplug >/dev/null ;;
    reset) rig_adb_shell dumpsys battery reset >/dev/null ;;
    '' | *[!0-9]*) rig_die "phone battery <0-100|unplug|reset>" ;;
    *) rig_adb_shell dumpsys battery set level "$1" >/dev/null ;;
    esac
    ;;
  notify)
    # A notification from the phone's own shell uid: title, then one text.
    local title=${1:?phone notify <title> <text>} text=${2:?phone notify <title> <text>}
    rig_adb_shell "cmd notification post -t '$title' rig-$RANDOM '$text'" >/dev/null
    ;;
  sms)
    # An incoming text, delivered by the emulator's modem. Never a send.
    local from=${1:?phone sms <555 number> <text>} text=${2:?phone sms <555 number> <text>}
    [[ $from == 555* || $from == +1555* ]] || rig_die "phone sms: use a 555 number"
    rig_adb -s "emulator-$RIG_EMU_PORT" emu sms send "$from" "$text"
    ;;
  call)
    # An incoming call from a 555 number; `phone hangup <number>` ends it.
    local from=${1:?phone call <555 number>}
    [[ $from == 555* ]] || rig_die "phone call: use a 555 number"
    rig_phone_call_start "$from"
    ;;
  hangup) rig_phone_call_end "${1:?phone hangup <number>}" ;;
  shot)
    local out=${1:-$RIG_EVIDENCE/phone.png}
    rig_adb -s "emulator-$RIG_EMU_PORT" exec-out screencap -p >"$out"
    [[ -s $out ]] || rig_die "screencap wrote nothing"
    rig_ok "wrote $out"
    ;;
  pair)
    RIG_EMU_PID=$(rig_state_get emulator_pid || echo "")
    rig_kdc_pair
    ;;
  refresh)
    kdeconnect-cli --refresh
    ;;
  *) rig_die "phone: unknown subcommand $sub (status, battery, notify, sms, call, hangup, shot, pair, refresh)" ;;
  esac
}
