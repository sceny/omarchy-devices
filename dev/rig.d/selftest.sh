#!/bin/bash
# Self-test of the rig's lease, keeper, ps, reap and `cold end`. Sourced by
# dev/rig (`dev/rig selftest`, or `dev/rig selftest cold` for the cold end's
# part alone). Needs no compositor, no emulator and no desktop, so it runs
# anywhere, CI included.
#
# It builds stand-in rigs: a session dir, a state file, a lease, a keeper and a
# few tagged `sleep` processes, one of them detached into its own session the
# way a daemon is. Then it ends owners the hard ways and checks the rig is gone.
# Everything happens under a private registry and a private runtime dir; the
# real registry and the owner's runtime dir are never read or written.
#
# shellcheck shell=bash

st_pass=0
st_fail=0

st_check() {
  # st_check <name> <command...>
  local name=$1
  shift
  if "$@" >/dev/null 2>&1; then
    rig_ok "$name"
    st_pass=$((st_pass + 1))
  else
    rig_fail "$name"
    st_fail=$((st_fail + 1))
  fi
}

st_wait() {
  # st_wait <seconds> <command...> — until the command succeeds.
  local deadline=$((SECONDS + $1))
  shift
  while ((SECONDS < deadline)); do
    "$@" >/dev/null 2>&1 && return 0
    sleep 0.5
  done
  return 1
}

st_fake_rig() {
  # st_fake_rig <owner pid|none> <ttl> — prints the rig id. Two tagged
  # sleeps: one plain child, one in a session of its own.
  (
    session=$(rig_new_session_dir)
    rig_define_paths "$session"
    RIG_TTL=$2 RIG_OWNER_DESC=selftest
    rig_create_sandbox
    rig_state_set plugin_id "$RIG_PLUGIN_ID"
    rig_lease_init "$1" "$2"
    export OPR_RIG_ID=$RIG_ID
    rig_keeper_start >/dev/null 2>&1
    # Their stdout must not be the $(...) pipe, or the caller waits for them.
    sleep 600 >/dev/null 2>&1 &
    setsid sleep 600 >/dev/null 2>&1 &
    printf '%s\n' "$RIG_ID"
  )
}

st_cold_end() {
  # st_cold_end <registry> <warm|cold> <daemon: up|up-nopid|down> <umount: ok|fails> —
  # runs `cold end` on a stand-in rig whose namespace, daemon start and shell
  # restart are recorders. Prints the session dir: `calls` holds what they
  # recorded, `out` the verb's output, `status` its exit.
  (
    RIG_TMP_ROOT=$1
    mkdir -p -m 700 "$RIG_TMP_ROOT"
    rig_define_paths "$(rig_new_session_dir)"
    mkdir -p "$RIG_SESSION" "$RIG_LOGS"
    calls="$RIG_SESSION/calls"
    : >"$calls"
    if [[ $2 == cold ]]; then
      mkdir -p "$(rig_cold_dir)/bin"
      printf 'cold: stand-in\n' >"$(rig_cold_dir)/cold.log"
      rig_state_set cold_path "$(rig_cold_dir)/bin:/usr/bin"
    fi
    st_ns() {
      printf 'ns %s\n' "$*" >>"$calls"
      [[ $umount == ok ]]
    }
    umount=$4 daemon=$3
    RIG_IN_NS=(st_ns)
    rig_cold_daemon_up() { [[ $daemon == up* ]]; }
    rig_cold_daemon_pid() { [[ $daemon == up ]] && printf '4242\n'; }
    rig_kdcd_start() { printf 'daemon start\n' >>"$calls"; }
    cmd_restart_shell() { printf 'shell on [%s]\n' "$(rig_cold_path)" >>"$calls"; }
    (rig_cold_end) >"$RIG_SESSION/out" 2>&1
    printf '%s\n' "$?" >"$RIG_SESSION/status"
    printf '%s\n' "$RIG_SESSION"
  )
}

st_selftest_cold() {
  # `dev/rig cold end`, on stand-in rigs in a registry of their own.
  local registry=$1 s
  rig_say "Cold end: a cold rig goes back to warm"
  s=$(st_cold_end "$registry" cold down ok)
  st_check "it succeeds" st_expr "[[ \$(<'$s/status') == 0 ]]"
  st_check "it unbinds the private firewall rules in the rig's namespace" \
    grep -qx 'ns umount /etc/ufw/user.rules' "$s/calls"
  st_check "the shell restarts on the warm PATH" grep -qx 'shell on \[\]' "$s/calls"
  st_check "the rig's state says warm" st_expr "[[ -z \$(rig_state_read '$s/rig.state' cold_path) ]]"
  st_check "a daemon starts when none is on the bus" grep -qx 'daemon start' "$s/calls"
  st_check "the cold run's log is kept aside" st_expr "compgen -G '$s/cold-ended-*/cold.log'"
  st_check "a new begin finds no cold directory" st_expr "[[ ! -e '$s/cold' ]]"
  st_check "its output says the phone is still new" grep -q 'phone is still new' "$s/out"

  s=$(st_cold_end "$registry" cold up ok)
  st_check "a daemon already on the bus is kept" st_expr "! grep -q 'daemon start' '$s/calls'"
  st_check "and recorded as the rig's, so the next begin stops it" \
    st_expr "[[ \$(rig_state_read '$s/rig.state' kdeconnectd_pid) == 4242 ]]"
  s=$(st_cold_end "$registry" cold up-nopid ok)
  st_check "a daemon the bus names no pid for fails" st_expr "[[ \$(<'$s/status') != 0 ]]"
  st_check "and the rig stays cold" st_expr "[[ -n \$(rig_state_read '$s/rig.state' cold_path) && -d '$s/cold' ]]"
  st_check "with its private firewall rules still bound" st_expr "! grep -q '^ns umount' '$s/calls'"
  st_check "and the shell is not restarted" st_expr "! grep -q '^shell' '$s/calls'"

  rig_say "Cold end: refusals"
  s=$(st_cold_end "$registry" warm down ok)
  st_check "a warm rig refuses" st_expr "[[ \$(<'$s/status') != 0 ]]"
  st_check "it says the rig is warm" grep -q 'warm already' "$s/out"
  st_check "it changes nothing" st_expr "[[ ! -s '$s/calls' ]]"
  s=$(st_cold_end "$registry" cold down fails)
  st_check "a failed unbind fails" st_expr "[[ \$(<'$s/status') != 0 ]]"
  st_check "and the rig stays cold" st_expr "[[ -n \$(rig_state_read '$s/rig.state' cold_path) && -d '$s/cold' ]]"
  st_check "and the shell is not restarted" st_expr "! grep -q '^shell' '$s/calls'"
}

st_expr() { eval "$1"; }
st_none_of() { st_wait 5 st_no_tagged "$1"; }
st_no_tagged() { [[ -z $(rig_tagged_pids "$1") ]]; }
st_some_of() { [[ -n $(rig_tagged_pids "$1") ]]; }
st_gone() { [[ ! -e $RIG_TMP_ROOT/$1 && ! -e $RIG_RUNTIME_ROOT/opr.${1##*.} ]]; }
# ps's whole output, then the match. Piped into grep -q under pipefail, ps
# fails when grep quits before ps has written its last line (SIGPIPE).
st_ps_says() { [[ $(cmd_ps) == *"$1"* ]]; }
st_listed() { st_ps_says "$1"; }
st_lease() { [[ $(rig_lease_state "$RIG_TMP_ROOT/$1") == "$2" ]]; }

cmd_selftest() {
  local scratch
  scratch=$(mktemp -d "${PAPERCLIP_SCRATCH_DIR:-${TMPDIR:-/tmp}}/rig-selftest.XXXXXX")
  chmod 700 "$scratch"
  RIG_TMP_ROOT="$scratch/registry"
  RIG_RUNTIME_ROOT="$scratch/run"
  mkdir -p -m 700 "$RIG_RUNTIME_ROOT"
  rig_ensure_root
  RIG_KEEPER_INTERVAL=1
  export RIG_TMP_ROOT RIG_RUNTIME_ROOT RIG_KEEPER_INTERVAL

  if [[ ${1:-} == cold ]]; then
    st_selftest_cold "$scratch/cold-rigs"
    rm -rf "$scratch"
    st_summary
    return
  fi

  local owner_a owner_b owner_c a b c d
  rig_say "Selftest: lease, keeper, ps and reap (private registry $RIG_TMP_ROOT)"

  sleep 600 &
  owner_a=$!
  sleep 600 &
  owner_b=$!

  a=$(st_fake_rig "$owner_a" 600)
  b=$(st_fake_rig "$owner_b" 600)
  st_check "two rigs get different ids and runtime dirs" \
    st_expr '[[ $a != "$b" && ${a##*.} != "${b##*.}" ]]'
  st_check "rig A has tagged processes" st_some_of "$a"
  st_check "rig B has tagged processes" st_some_of "$b"
  st_check "the two rigs' process sets do not overlap" \
    st_expr '! comm -12 <(rig_tagged_pids "$a" | sort) <(rig_tagged_pids "$b" | sort) | grep -q .'
  st_check "ps shows rig A" st_listed "$a"
  st_check "ps shows rig B" st_listed "$b"
  st_check "rig A lease is live" st_lease "$a" live
  st_check "reap leaves live rigs alone" \
    st_expr 'cmd_reap >/dev/null 2>&1; [[ -d $RIG_TMP_ROOT/$a && -d $RIG_TMP_ROOT/$b ]]'

  rig_say "Owner of A is killed with SIGKILL"
  kill -9 "$owner_a"
  wait "$owner_a" 2>/dev/null || true
  st_check "the keeper tears rig A down on its own" st_wait 20 st_gone "$a"
  st_check "no process of rig A is left (plain or detached)" st_none_of "$a"
  st_check "rig B is untouched" st_expr '[[ -d $RIG_TMP_ROOT/$b ]]'
  st_check "rig B processes still run" st_some_of "$b"
  st_check "ps no longer lists rig A" st_expr '! st_ps_says "$a"'

  rig_say "TTL runs out"
  owner_c=$owner_b
  c=$(st_fake_rig "$owner_c" 3)
  st_check "a 3 second TTL is reaped by the keeper" st_wait 20 st_gone "$c"
  st_check "its processes are gone too" st_none_of "$c"

  rig_say "Keeper and owner both die (a reboot, an OOM kill)"
  sleep 600 &
  owner_a=$!
  d=$(st_fake_rig "$owner_a" 600)
  kill -9 "$(<"$RIG_TMP_ROOT/$d/keeper.pid")"
  kill -9 "$owner_a"
  wait "$owner_a" 2>/dev/null || true
  st_check "ps calls the rig orphaned" st_wait 5 st_ps_says orphaned
  st_check "reap runs" st_expr 'cmd_reap >/dev/null 2>&1'
  st_check "its directories are gone" st_gone "$d"
  st_check "its processes are gone" st_none_of "$d"

  rig_say "A tagged process whose rig directory is gone"
  (
    export OPR_RIG_ID=leaked.20000101-000000.abcdef
    setsid sleep 600 &
  )
  st_check "ps reports it as leaked" st_wait 5 st_ps_says "leaked processes"
  st_check "verify-clean fails while it exists" st_expr '! cmd_verify_clean'
  st_check "reap ends it" \
    st_expr 'cmd_reap >/dev/null 2>&1; [[ -z $(rig_tagged_pids leaked.20000101-000000.abcdef) ]]'

  rig_say "Down of a live rig leaves nothing"
  (
    RIG_SELECT=$b
    rig_select && rig_teardown >/dev/null 2>&1
  )
  st_check "rig B is gone after teardown" st_gone "$b"
  st_check "rig B's processes are gone" st_none_of "$b"
  st_check "verify-clean passes with no rigs" cmd_verify_clean

  st_selftest_cold "$scratch/cold-rigs"

  # The stand-in owners and anything else this test started.
  kill "$owner_a" "$owner_b" 2>/dev/null || true
  cmd_reap --all >/dev/null 2>&1
  rm -rf "$scratch"
  st_check "the test registry is removed" st_expr '[[ ! -e $scratch ]]'
  st_summary
}

st_summary() {
  if ((st_fail)); then
    rig_fail "selftest: $st_pass passed, $st_fail failed"
    return 1
  fi
  rig_ok "selftest: $st_pass passed, 0 failed"
}
