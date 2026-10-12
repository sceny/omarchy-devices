#!/bin/bash
# A cold computer for the rig: the packages the plugin installs are hidden from
# the shell's PATH, `pacman` and `pkexec` are recording stubs that apply only
# the plan they are given, ufw's rules are a private copy with none of the
# plugin's, no daemon runs and the phone has granted nothing. Sourced by
# dev/rig, never run directly. Nothing here changes the host: the hiding is a
# PATH of symlinks, the rules a bind mount inside the rig's mount namespace.
#
# What it cannot prove (a real machine's list): pacman's real dependency
# resolution and download, polkit's own prompt, ufw's real rule engine, a
# system systemd and BlueZ, a real Bluetooth radio.

# nordvpn-bin is hidden, never installed: the host's mesh peers are not the rig's.
RIG_COLD_PACKAGES="kdeconnect,sshfs,scrcpy,android-tools,android-udev,bluez,bluez-utils,nordvpn-bin"

rig_cold_dir() { printf '%s/cold' "$RIG_SESSION"; }

rig_cold_path() { rig_state_get cold_path 2>/dev/null || true; }

rig_cold_phone_reset() {
  # The phone as a new one: the app's data cleared (nothing paired, nothing
  # granted), notification access and all-files access taken away.
  local pkg=org.kde.kdeconnect_tp
  rig_adb_shell cmd notification disallow_listener \
    "$pkg/org.kde.kdeconnect.plugins.notifications.NotificationReceiver" >/dev/null 2>&1
  rig_adb_shell pm clear "$pkg" >/dev/null 2>&1
  rig_adb_shell appops set "$pkg" MANAGE_EXTERNAL_STORAGE deny >/dev/null 2>&1
  rig_ok "the phone's KDE Connect is new: nothing paired, nothing granted"
}

cmd_cold() {
  rig_select || rig_die "no rig for this owner; run 'dev/rig up' first"
  rig_export_env
  rig_guard_sandbox
  rig_guard_nested_display
  [[ -n ${RIG_NETNS_PID:-} ]] || rig_die "cold: this rig has no phone and no namespace"
  local sub=${1:-status} dir
  shift || true
  dir=$(rig_cold_dir)
  case $sub in
  begin)
    [[ -z $(rig_cold_path) ]] || rig_die "cold: this rig is cold already"
    mkdir -p "$dir"
    local path
    path=$(python3 "$RIG_DIR/rig.d/cold.py" build --dir "$dir" --path "$PATH" \
      --log "$dir/cold.log" --rules "$dir/user.rules" --packages "$RIG_COLD_PACKAGES") ||
      rig_die "cold: could not build the cold PATH"
    rig_ok "cold PATH built ($dir): the plugin's packages are not on it"
    "${RIG_IN_NS[@]}" mount --bind "$dir/user.rules" /etc/ufw/user.rules ||
      rig_die "cold: could not bind the private firewall rules"
    rig_ok "ufw's rules are a private copy with none of KDE Connect's"
    RIG_KDCD_PID=$(rig_state_get kdeconnectd_pid 2>/dev/null || echo "")
    rig_stop_pid "kdeconnectd" "$RIG_KDCD_PID" 10
    rig_state_set kdeconnectd_pid ""
    rm -rf "$XDG_CONFIG_HOME/kdeconnect" "$XDG_DATA_HOME"/kdeconnect* "$XDG_CACHE_HOME/sceny.devices"
    rig_kdcd_config
    rig_cold_phone_reset
    rig_state_set cold_path "$path"
    cmd_restart_shell
    rig_ok "cold: restarted the shell on the cold PATH"
    ;;
  path) rig_cold_path ;;
  daemon)
    # Starts the rig's daemon for a step the plugin cannot take itself (the
    # run records why); the phone's redirects and forwards are redone.
    rig_kdcd_start
    ;;
  status)
    [[ -n $(rig_cold_path) ]] || rig_die "cold: this rig is warm"
    python3 "$RIG_DIR/rig.d/cold.py" status --dir "$dir"
    cat "$dir/cold.log" 2>/dev/null || true
    ;;
  exec)
    # A command as the shell sees this computer.
    [[ ${1:-} == -- ]] && shift
    (($#)) || rig_die "cold exec: nothing to run"
    [[ -n $(rig_cold_path) ]] || rig_die "cold: this rig is warm"
    cd "$RIG_PLUGIN_SRC_ABS" || exit 1
    exec "${RIG_IN_NS[@]}" env "PATH=$(rig_cold_path)" "$@"
    ;;
  *) rig_die "cold: begin | status | path | daemon | exec -- <command>" ;;
  esac
}
