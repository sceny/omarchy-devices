#!/bin/bash
# The checks the rig runs. Sourced by dev/rig, never run directly.
#
# Every check captures its command, exit code and output into
# $RIG_EVIDENCE/<name>.log so a failure can be pasted into an issue without
# re-running anything. A check that cannot prove its thing fails; it never
# lowers its bar to pass.
#
# shellcheck shell=bash

RIG_CHECK_PASS=0
RIG_CHECK_FAIL=0
RIG_CHECK_NAMES=()
RIG_CHECK_RESULTS=()

rig_record() {
  # rig_record <name> <expected-exit> <command...>
  # Runs the command, writes the evidence, returns the command's exit code.
  local name=$1 expected=$2
  shift 2
  local log="$RIG_EVIDENCE/$name.log" status=0

  {
    printf '$ %s\n' "$*"
    printf -- '---\n'
  } >"$log"
  "$@" >>"$log" 2>&1 || status=$?
  printf -- '---\nexit=%s (expected %s)\n' "$status" "$expected" >>"$log"

  if [[ $status == "$expected" ]]; then
    rig_ok "$name (exit $status)"
    RIG_CHECK_PASS=$((RIG_CHECK_PASS + 1))
    RIG_CHECK_NAMES+=("$name")
    RIG_CHECK_RESULTS+=("pass exit=$status")
    return 0
  fi
  rig_fail "$name (exit $status, expected $expected) — see $log"
  tail -15 "$log" >&2
  RIG_CHECK_FAIL=$((RIG_CHECK_FAIL + 1))
  RIG_CHECK_NAMES+=("$name")
  RIG_CHECK_RESULTS+=("FAIL exit=$status expected=$expected")
  return 1
}

rig_record_settled() {
  # rig_record_settled <name> <expected-exit> <command...>
  # Like rig_record, for commands that talk to the shell right after an add or
  # remove. Omarchy's add/remove return once the shell has been asked to rescan
  # and reload the plugin, and for a moment after that the shell either does
  # not answer IPC ("not responding") or has not yet seen the plugin ("not
  # known"). Only those two answers are retried, for at most 30 seconds, and
  # every attempt stays in the evidence. Any other failure fails at once.
  local name=$1 expected=$2
  shift 2
  local log="$RIG_EVIDENCE/$name.log" status=0 attempt=1
  local deadline=$((SECONDS + 30))

  printf '$ %s\n---\n' "$*" >"$log"
  while :; do
    status=0
    local out
    out=$("$@" 2>&1) || status=$?
    printf '[attempt %s] exit=%s\n%s\n' "$attempt" "$status" "$out" >>"$log"
    [[ $status == "$expected" ]] && break
    [[ $out == *"omarchy-shell is not responding"* || $out == *"is not known"* ]] || break
    ((SECONDS < deadline)) || break
    attempt=$((attempt + 1))
    sleep 1
  done
  printf -- '---\nexit=%s (expected %s) after %s attempt(s)\n' "$status" "$expected" "$attempt" >>"$log"

  if [[ $status == "$expected" ]]; then
    rig_ok "$name (exit $status, $attempt attempt(s))"
    RIG_CHECK_PASS=$((RIG_CHECK_PASS + 1))
    RIG_CHECK_NAMES+=("$name")
    RIG_CHECK_RESULTS+=("pass exit=$status attempts=$attempt")
    return 0
  fi
  rig_fail "$name (exit $status, expected $expected) — see $log"
  tail -15 "$log" >&2
  RIG_CHECK_FAIL=$((RIG_CHECK_FAIL + 1))
  RIG_CHECK_NAMES+=("$name")
  RIG_CHECK_RESULTS+=("FAIL exit=$status expected=$expected")
  return 1
}

rig_assert() {
  # rig_assert <name> <message> <command...> — a condition, not a captured run.
  local name=$1 message=$2
  shift 2
  if "$@" >/dev/null 2>&1; then
    rig_ok "$name"
    RIG_CHECK_PASS=$((RIG_CHECK_PASS + 1))
    RIG_CHECK_NAMES+=("$name")
    RIG_CHECK_RESULTS+=("pass")
    return 0
  fi
  rig_fail "$name — $message"
  RIG_CHECK_FAIL=$((RIG_CHECK_FAIL + 1))
  RIG_CHECK_NAMES+=("$name")
  RIG_CHECK_RESULTS+=("FAIL $message")
  return 1
}

rig_assert_eventually() {
  # rig_assert_eventually <name> <seconds> <message> <command...>
  # For conditions the shell reaches asynchronously. `omarchy plugin add`
  # returns as soon as it has asked the shell to rescan, so "the shell lists
  # it" is true a moment later, not immediately.
  local name=$1 budget=$2 message=$3
  shift 3
  local deadline=$((SECONDS + budget))
  while ((SECONDS < deadline)); do
    if "$@" >/dev/null 2>&1; then
      rig_ok "$name"
      RIG_CHECK_PASS=$((RIG_CHECK_PASS + 1))
      RIG_CHECK_NAMES+=("$name")
      RIG_CHECK_RESULTS+=("pass")
      return 0
    fi
    sleep 0.5
  done
  rig_fail "$name — $message (still false after ${budget}s)"
  RIG_CHECK_FAIL=$((RIG_CHECK_FAIL + 1))
  RIG_CHECK_NAMES+=("$name")
  RIG_CHECK_RESULTS+=("FAIL $message")
  return 1
}

# ------------------------------------------------------------- the checks ----

rig_check_manifest() {
  rig_say "Manifest"
  rig_record manifest-validate 0 omarchy plugin validate "$RIG_PKG_REPO"
  rig_record manifest-id 0 bash -c \
    "jq -e --arg id '$RIG_PLUGIN_ID' '.id == \$id' '$RIG_PKG_REPO/manifest.json'"
}

rig_check_cold_install() {
  # Cold-start truth: nothing installed, nothing enabled, fresh config.
  rig_say "Cold install"
  rig_assert cold-start-empty "the plugin was already installed before the cold install" \
    bash -c "! test -e '$RIG_PLUGINS_DIR/$RIG_PLUGIN_ID'"

  rig_record cold-install 0 omarchy plugin add "file://$RIG_PKG_REPO" --yes
  rig_assert cold-install-landed "plugin directory missing after add" \
    test -d "$RIG_PLUGINS_DIR/$RIG_PLUGIN_ID"
  rig_assert_eventually cold-install-discovered 15 "the nested shell does not list the plugin" \
    bash -c "omarchy plugin list --json | jq -e --arg id '$RIG_PLUGIN_ID' 'any(.[]; .id == \$id)'"
  rig_record cold-install-list 0 omarchy plugin list
}

rig_check_repeat_install() {
  # Idempotent install: the second add must refuse, clearly, without damaging
  # the first one. Omarchy's own contract is "already installed; update it",
  # so a non-zero exit here is the correct behaviour.
  rig_say "Repeat install"
  rig_record repeat-install-refused 1 omarchy plugin add "file://$RIG_PKG_REPO" --yes
  rig_assert repeat-install-intact "the repeat add damaged the installed plugin" \
    test -f "$RIG_PLUGINS_DIR/$RIG_PLUGIN_ID/manifest.json"
  rig_assert repeat-install-no-staging "a staging directory leaked into the plugins dir" \
    bash -c "! compgen -G '$RIG_PLUGINS_DIR/.add.tmp.*' > /dev/null"
}

rig_check_enable() {
  rig_say "Enable"
  # The bar before the plugin is on it, kept for a human to compare against the
  # screenshot afterwards. Not asserted: the clock and toasts change on their own.
  rig_guard_nested_display
  RIG_GRIM_TIMEOUT=5 rig_grim "$RIG_EVIDENCE/nested-shell-before-enable.png" 2>/dev/null || true
  rig_record_settled enable 0 omarchy plugin enable "$RIG_PLUGIN_ID" "$RIG_BAR_SECTION"
  rig_assert enable-reported "the shell does not report the plugin as enabled" \
    bash -c "omarchy plugin list --json | jq -e --arg id '$RIG_PLUGIN_ID' 'any(.[]; .id == \$id and .enabled == true)'"
  rig_assert enable-in-config "shell.json does not place the plugin in the bar" \
    bash -c "jq -e --arg id '$RIG_PLUGIN_ID' '[.bar.layout[]?[]?] | any(. == \$id or (type == \"object\" and .id == \$id))' '$RIG_HOME/.config/omarchy/shell.json'"

  # A panel that will not load is the failure this rig exists to catch, and the
  # shell reports it on stderr rather than in the plugin list.
  rig_assert enable-no-load-failure "the shell logged a plugin load failure" \
    bash -c "! grep -iE 'pluginLoadFailed|Plugin .*failed to load|$RIG_PLUGIN_ID.*(error|Error)' '$RIG_LOGS/shell.log'"
  cp "$RIG_LOGS/shell.log" "$RIG_EVIDENCE/shell-after-enable.log" 2>/dev/null || true
}

rig_check_disable() {
  rig_say "Disable"
  rig_record disable 0 omarchy plugin disable "$RIG_PLUGIN_ID"
  rig_assert disable-reported "the shell still reports the plugin as enabled" \
    bash -c "omarchy plugin list --json | jq -e --arg id '$RIG_PLUGIN_ID' 'any(.[]; .id == \$id and .enabled == false)'"
  # Idempotent disable.
  rig_record disable-twice 0 omarchy plugin disable "$RIG_PLUGIN_ID"
  rig_assert disable-kept-files "disable removed the installed files" \
    test -f "$RIG_PLUGINS_DIR/$RIG_PLUGIN_ID/manifest.json"
  # And back on, so remove is exercised from the enabled state a user is in.
  rig_record_settled re-enable 0 omarchy plugin enable "$RIG_PLUGIN_ID" "$RIG_BAR_SECTION"
}

rig_check_remove() {
  rig_say "Remove"
  rig_record remove 0 omarchy plugin remove "$RIG_PLUGIN_ID" --yes
  rig_assert remove-gone "the plugin directory survived remove" \
    bash -c "! test -e '$RIG_PLUGINS_DIR/$RIG_PLUGIN_ID'"
  rig_assert_eventually remove-unlisted 15 "the shell still lists the removed plugin" \
    bash -c "! omarchy plugin list --json | jq -e --arg id '$RIG_PLUGIN_ID' 'any(.[]; .id == \$id)'"
  # Idempotent remove: a second one must refuse, not crash or delete something
  # else.
  rig_record remove-twice-refused 1 omarchy plugin remove "$RIG_PLUGIN_ID" --yes
  # And reinstall after remove, because an upgrade is a remove plus an add.
  rig_record reinstall-after-remove 0 omarchy plugin add "file://$RIG_PKG_REPO" --yes
  rig_record_settled reinstall-enable 0 omarchy plugin enable "$RIG_PLUGIN_ID" "$RIG_BAR_SECTION"
}

rig_check_screenshot() {
  rig_say "Screenshot"
  rig_guard_nested_display
  local out="$RIG_EVIDENCE/nested-shell.png"
  # Let the bar settle: the widget's first poll is what puts content in it.
  sleep 6
  # rig_grim_wait retries the "no wl_output" start-up answer, and gives up with
  # an explanation when grim gets no frame at all.
  if rig_record screenshot 0 rig_grim_wait "$out"; then
    rig_assert screenshot-not-empty "grim produced an empty file" \
      bash -c "test -s '$out'"
    rig_step "screenshot: $out"
  fi
}

rig_check_host_untouched() {
  # The hard rules, as a check rather than a promise. Each of these would be a
  # defect in the rig, not in the plugin.
  rig_say "Host isolation"
  rig_assert host-config-untouched "the rig wrote into the owner's plugin directory" \
    bash -c "! test -e '$RIG_HOST_CONFIG_HOME/omarchy/plugins/$RIG_PLUGIN_ID'"
  rig_assert host-shell-alive "the owner's Omarchy shell is no longer running" \
    bash -c "pgrep -u \"\$(id -u)\" -f 'quickshell.*-p ' | grep -qv '^$RIG_SHELL_PID\$'"
  rig_assert host-systemd-unreachable "the sandbox can still reach the owner's user units" \
    bash -c "! systemctl --user list-units >/dev/null 2>&1"
  if [[ -s $RIG_EVIDENCE/host-phone-before.txt ]]; then
    rig_assert host-phone-untouched "the owner's kdeconnectd, adb or emulator changed" \
      rig_phone_host_unchanged "$RIG_EVIDENCE/host-phone-before.txt"
  fi
}

rig_no_rig_client_on_host() { [[ -z $(rig_host_rig_clients) ]]; }

rig_check_hidden() {
  # The default view must leave no trace on the owner's desktop. The hard part
  # is asserted; whether the desktop is byte-for-byte the same is reported,
  # because the owner may be using it while the rig runs.
  rig_say "Hidden view"
  if [[ $RIG_VIEW == hidden ]]; then
    rig_assert hidden-no-host-window "a window of the rig is on the owner's desktop" \
      rig_no_rig_client_on_host
  else
    rig_warn "the rig is visible on request; the hidden checks do not apply"
  fi

  local before="$RIG_EVIDENCE/host-before.json" after="$RIG_EVIDENCE/host-after-check.json" diff_out
  if [[ ! -s $before ]] || ! jq -e '.available' "$before" >/dev/null 2>&1; then
    rig_warn "no desktop session to compare against (CI or SSH login); host snapshot skipped"
    return 0
  fi
  rig_host_snapshot "$after" || true
  if diff_out=$(rig_host_compare "$before" "$after"); then
    rig_ok "the owner's windows, workspaces and focus are as they were"
  else
    rig_warn "the owner's desktop differs from before the rig came up (the owner may have been using it):"
    printf '%s\n' "$diff_out" >&2
    printf '%s\n' "$diff_out" >"$RIG_EVIDENCE/host-diff.txt"
  fi
}

rig_check_shell_services_off() {
  # The nested shell must not run its own idle/lock services: a lock inside the
  # rig covers the window and ends the run.
  rig_say "Shell services"
  local id
  for id in "${RIG_SHELL_DISABLED_PLUGINS[@]}"; do
    rig_record "service-off-$id" 0 bash -c \
      "omarchy plugin list --json | jq -e --arg id '$id' 'any(.[]; .id == \$id and .enabled == false)'"
  done
}

rig_check_lease() {
  rig_say "Lease"
  local keeper
  keeper=$(<"$RIG_SESSION/keeper.pid") 2>/dev/null || keeper=""
  rig_assert lease-keeper-alive "no live lease keeper for this rig" \
    bash -c "[[ -n '$keeper' ]] && kill -0 '$keeper'"
  rig_assert lease-state-live "the rig's own lease is not live" \
    rig_lease_is_live
  rig_assert lease-runtime-dir-own "the runtime dir is shared with another rig" \
    bash -c "[[ '$RIG_RUNTIME_DIR' == '$RIG_RUNTIME_ROOT'/opr.* ]]"
}

rig_lease_is_live() { [[ $(rig_lease_state "$RIG_SESSION") == live ]]; }

rig_check_devices() {
  # The plugin against the rig's phone. Active only when the rig has one.
  [[ -n ${RIG_NETNS_PID:-} ]] || {
    rig_warn "no phone in this rig (--no-phone); the Devices checks are skipped"
    return 0
  }
  rig_say "Devices"
  rig_assert devices-bus-is-rigs "the session bus is not the rig's own" \
    bash -c "[[ \"\$DBUS_SESSION_BUS_ADDRESS\" == 'unix:path=$RIG_RUNTIME_DIR/'* ]]"
  rig_assert devices-paired "the emulator is not paired to the rig's KDE Connect" \
    rig_phone_is_paired
  rig_assert_eventually devices-bridge-battery 60 "the bridge does not see the emulator's battery" \
    rig_bridge_sees_battery
  rig_assert_eventually devices-ipc-status 30 "the panel does not answer over IPC" \
    rig_ipc_status_ok
  rig_phone_battery_set 63
  rig_assert_eventually devices-battery-follows 40 "the bridge does not follow a battery change" \
    rig_bridge_battery_is 63
  rig_phone_notify "Rig check" "Hello from the emulator"
  rig_assert_eventually devices-notification 40 "the posted notification does not reach the bridge" \
    rig_bridge_has_notification "Rig check"
  rig_phone_call_start 5550123
  rig_assert_eventually devices-call-ringing 30 "an incoming call does not reach the panel" \
    rig_ipc_call_is ringing
  rig_phone_call_end 5550123
  rig_assert_eventually devices-call-ended 30 "the call is still shown after it ended" \
    rig_ipc_call_is_not ringing
  rig_assert_eventually devices-screen-ready 30 "the screen link does not find the emulator" \
    rig_screen_ready
  rig_assert devices-screen-opens "scrcpy does not open the emulator's screen in the hidden session" \
    rig_screen_open
  rig_assert_eventually devices-screen-window 30 "no scrcpy window in the rig's compositor" \
    rig_screen_window_open
  rig_bridge_ns screen-close "$(rig_phone_id)" >/dev/null 2>&1
  rig_assert_eventually devices-screen-closed 30 "the scrcpy window is still open after close" \
    rig_screen_window_gone
  rig_assert devices-host-phone-untouched "the owner's kdeconnectd, adb or emulator changed" \
    rig_phone_host_unchanged "$RIG_EVIDENCE/host-phone-before.txt"
}

rig_check_summary() {
  local index=0
  rig_say "Results"
  for index in "${!RIG_CHECK_NAMES[@]}"; do
    printf '  %-34s %s\n' "${RIG_CHECK_NAMES[$index]}" "${RIG_CHECK_RESULTS[$index]}" >&2
  done
  printf '\n' >&2
  if ((RIG_CHECK_FAIL)); then
    rig_fail "$RIG_CHECK_PASS passed, $RIG_CHECK_FAIL failed"
    return 1
  fi
  rig_ok "$RIG_CHECK_PASS passed, 0 failed"
  return 0
}

rig_write_summary_file() {
  local out="$RIG_EVIDENCE/summary.txt" index
  {
    printf 'rig summary for %s\n' "$RIG_PLUGIN_ID"
    printf 'view=%s phone=%s\n' "$RIG_VIEW" "${RIG_NETNS_PID:+emulator}"
    printf 'omarchy=%s\n\n' "$RIG_OMARCHY_PATH"
    for index in "${!RIG_CHECK_NAMES[@]}"; do
      printf '%-34s %s\n' "${RIG_CHECK_NAMES[$index]}" "${RIG_CHECK_RESULTS[$index]}"
    done
    printf '\n%s passed, %s failed\n' "$RIG_CHECK_PASS" "$RIG_CHECK_FAIL"
  } >"$out"
}
