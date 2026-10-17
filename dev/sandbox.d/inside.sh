#!/bin/bash
# The inside of one sandbox container: unpack the commit, run ONE unit, leave
# its logs and evidence in /out, and exit with the unit's own status. `dev/
# sandbox` starts a fresh container per unit, so nothing a unit's code changes
# (its tree, develop's dev/, /out) reaches the next unit, and the host takes
# the verdict from the container's exit code, never from a file written here.
# Runs as the unprivileged `sandbox` user with no network and every writable
# path a size-limited tmpfs. It is Sceny's own code (the image holds develop's
# copy); the commit under test never replaces it.
#
# Inputs (read-only): /in/src.tar = `git archive` of the exact commit;
#                     /in/script.sh = an optional QA script (--script).
# Environment: SANDBOX_UNIT (unit-model, unit-bridge, pc-tests, pc-selftest,
#              qml-parse, manifest, rig-ci, script), SANDBOX_REPO (the
#              repository's owner/name), SANDBOX_HARNESS (develop | pr),
#              SANDBOX_SHA.
#
# shellcheck shell=bash

set -uo pipefail

OUT=/out
SRC=/work/src
UNIT=${SANDBOX_UNIT:-}
HARNESS=${SANDBOX_HARNESS:-develop}
REPO=${SANDBOX_REPO:-sceny/omarchy-devices}

# The plugin id the repository's manifest.json must carry, and the dev/ of the
# repository's own develop that the image holds.
case $REPO in
sceny/omarchy-devices)
  PLUGIN_ID=sceny.devices
  HARNESS_DEV=/opt/harness/dev
  ;;
sceny/omarchy-paperclipai)
  PLUGIN_ID=sceny.paperclipai
  HARNESS_DEV=/opt/harness/paperclipai/dev
  ;;
*)
  printf '[sandbox] unknown repository %s\n' "$REPO" >&2
  exit 70
  ;;
esac

# Exit codes of the harness itself, apart from the unit's.
E_PREPARE=70
E_UNIT=71

mkdir -p "$OUT/logs" "$OUT/screenshots" "$SRC"

log() { printf '[sandbox %s] %s\n' "$(date -u +%H:%M:%S)" "$*" >&2; }

# unit <name> <command...>: run it in the tree, keep its output, return its status.
unit() {
  local name=$1 status
  shift
  log "unit $name: $*"
  (cd "$SRC" && "$@") >"$OUT/logs/$name.log" 2>&1
  status=$?
  log "unit $name: exit $status"
  return "$status"
}

# ----------------------------------------------------------------- prepare ----

if ! tar -x --no-same-owner --no-same-permissions -f /in/src.tar -C "$SRC" 2>"$OUT/logs/$UNIT.unpack.log"; then
  log "the archive did not unpack"
  exit "$E_PREPARE"
fi

# The checks come from Sceny's develop (the repository's own), so a commit
# cannot loosen the checks it is judged by. `--harness pr` keeps the commit's
# own dev/ (for a change to dev/ itself).
if [[ $HARNESS == develop ]]; then
  rm -rf "$SRC/dev"
  cp -a "$HARNESS_DEV" "$SRC/dev"
fi

# dev/rig packages the tracked tree of a git checkout, so the rig units make
# one (the archive is files only), as does pc-tests; -f because the commit's own .gitignore would
# otherwise drop files the commit tracks.
git_tree() {
  export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null
  export GIT_AUTHOR_NAME=sandbox GIT_AUTHOR_EMAIL=sandbox@invalid GIT_COMMITTER_NAME=sandbox GIT_COMMITTER_EMAIL=sandbox@invalid
  (
    cd "$SRC" || exit 1
    git init -q -b sandbox . &&
      git add -f -A . &&
      git commit -q -m "sandbox: ${SANDBOX_SHA:-unknown}"
  ) >"$OUT/logs/$UNIT.git.log" 2>&1
}

# The rig's phone cache holds the pinned KDE Connect APK; the run has no
# network to fetch it.
seed_rig() {
  [[ -d /opt/sandbox/cache ]] || return 0 # only Devices' image has a phone
  local cache=/tmp/omarchy-plugin-rig-$(id -u)/cache
  mkdir -p "$cache" && cp /opt/sandbox/cache/* "$cache"/
}

collect_rig() {
  [[ -d $OUT/rig ]] || return 0
  find "$OUT/rig" -type f -name '*.png' -exec cp -n {} "$OUT/screenshots/" \; 2>/dev/null
  return 0
}

# ------------------------------------------------------------------- units ----

status=0
case $UNIT in
unit-model) unit unit-model bash -c 'node --test tests/*.test.js' || status=$? ;;
unit-bridge) unit unit-bridge bash -c 'python3 -m unittest discover -s tests -v' || status=$? ;;
qml-parse)
  unit qml-parse bash -c 'fmt=/usr/lib/qt6/bin/qmlformat; for f in *.qml; do "$fmt" "$f" >/dev/null || { echo "$f does not parse"; exit 1; }; done' || status=$?
  ;;
pc-tests)
  # its security rules read the tracked files (`git ls-files`)
  git_tree || exit "$E_PREPARE"
  unit pc-tests bash test/run_all.sh || status=$?
  ;;
pc-selftest) unit pc-selftest dev/rig selftest || status=$? ;;
manifest) unit manifest jq -e --arg id "$PLUGIN_ID" '.id == $id and .schemaVersion == 1' manifest.json || status=$? ;;
rig-ci | script)
  # These two units keep podman's default seccomp profile, which allows a new
  # user namespace: the rig's phone side runs in one (`unshare -Urn`,
  # dev/rig.d/phone.sh:94) and glycin's loaders start bwrap in one. A filter that
  # refuses it cannot tell those from hostile code, so the tests units get
  # the stricter profile (dev/sandbox.d/seccomp.py) and these do not. What
  # holds instead: no capability, no network, no host path, limits.
  ;;&
rig-ci)
  git_tree || exit "$E_PREPARE"
  seed_rig
  # the rig's compositor start-up race is lost more often in a container
  RIG_COMPOSITOR_OUTSIDE_NS=1 RIG_COMPOSITOR_ATTEMPTS=60 unit rig-ci env dev/rig ci --evidence "$OUT/rig" || status=$?
  collect_rig
  ;;
script)
  # Exits 0 only when the rig came up and the QA script exited 0.
  [[ -r /in/script.sh ]] || exit "$E_PREPARE"
  git_tree || exit "$E_PREPARE"
  seed_rig
  if RIG_COMPOSITOR_OUTSIDE_NS=1 RIG_COMPOSITOR_ATTEMPTS=60 unit script-up env dev/rig up --owner none --ttl 3000; then
    unit script env SANDBOX_OUT="$OUT" bash /in/script.sh || status=$?
  else
    status=$E_UNIT
    cp -r "/tmp/omarchy-plugin-rig-$(id -u)/last-failed-up" "$OUT/rig-up-failed" 2>/dev/null
  fi
  unit script-down dev/rig down || true
  collect_rig
  ;;
*)
  log "unknown unit '$UNIT'"
  exit "$E_UNIT"
  ;;
esac

log "done"
exit "$status"
