#!/bin/bash
# verify-clean waits for the store lock another command holds, says so, and
# finishes once it is released. One temporary store is shared by the holder and
# verify-clean; it is removed on exit. Exits 1 on the first failed assertion.

set -uo pipefail

SB_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
SANDBOX_STATE=$(mktemp -d)
export SANDBOX_STATE
work=$(mktemp -d)
holder_pid="" vc_pid=""
cleanup() {
  [[ -z $vc_pid ]] || kill "$vc_pid" 2>/dev/null
  [[ -z $holder_pid ]] || kill "$holder_pid" 2>/dev/null
  touch "$work/release"
  wait 2>/dev/null
  rm -rf -- "$SANDBOX_STATE" "$work"
}
trap cleanup EXIT

# verify-clean needs a podman on the PATH to start; with no containers in the
# fresh store, what it asks podman for comes back empty.
mkdir "$work/bin"
printf '#!/bin/sh\nexit 0\n' >"$work/bin/podman"
chmod +x "$work/bin/podman"
export PATH="$work/bin:$PATH"

fail() {
  echo "FAIL: $*" >&2
  [[ ! -f $work/out ]] || sed 's/^/  | /' "$work/out" >&2
  exit 1
}
await() { # <seconds> <test command...>
  local n=$(($1 * 10))
  shift
  while ((n-- > 0)); do
    "$@" && return 0
    sleep 0.1
  done
  return 1
}

# The holder takes the lock the way dev/sandbox does and keeps it until told.
timeout 60 flock -x "$SANDBOX_STATE/.lock" bash -c \
  'touch "$1"; while [ ! -e "$2" ]; do sleep 0.1; done' _ "$work/held" "$work/release" &
holder_pid=$!
await 10 test -e "$work/held" || fail "the lock holder did not take the lock"

bash "$SB_DIR/sandbox" verify-clean >"$work/out" 2>&1 &
vc_pid=$!

await 10 grep -qF 'waiting for the store lock…' "$work/out" || fail "verify-clean did not say it was waiting for the store lock"
kill -0 "$vc_pid" 2>/dev/null || fail "verify-clean finished while the lock was held"
echo "ok: verify-clean waits for the lock and says so"

touch "$work/release"
wait "$holder_pid"
holder_pid=""
await 20 bash -c "! kill -0 $vc_pid 2>/dev/null" || fail "verify-clean did not finish after the lock was released"
wait "$vc_pid"
rc=$?
vc_pid=""
((rc == 0)) || fail "verify-clean exited $rc after the lock was released, not 0"
echo "ok: verify-clean finished with exit 0 after the release"
