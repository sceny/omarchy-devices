#!/bin/bash
# The inside of a sandbox run: unpack the commit, run the checks, write results
# to /out. Runs in the container as the unprivileged `sandbox` user, with no
# network and every writable path a size-limited tmpfs. It is Sceny's own code
# (the image holds develop's copy); the commit under test never replaces it.
#
# Inputs (read-only): /in/src.tar = `git archive` of the exact commit;
#                     /in/script.sh = an optional QA script (--script).
# Environment: SANDBOX_STEPS (comma list: tests, rig, script), SANDBOX_HARNESS
#              (develop | pr), SANDBOX_SHA.
#
# shellcheck shell=bash

set -uo pipefail

OUT=/out
SRC=/work/src
STEPS=${SANDBOX_STEPS:-tests,rig}
HARNESS=${SANDBOX_HARNESS:-develop}
RESULTS=$OUT/results.tsv

mkdir -p "$OUT/logs" "$OUT/screenshots" "$SRC"
: >"$RESULTS"

log() { printf '[sandbox %s] %s\n' "$(date -u +%H:%M:%S)" "$*" >&2; }

# step <name> <command...>: run it, keep its output, record the exit code.
step() {
  local name=$1 status started=$SECONDS
  shift
  log "step $name: $*"
  (cd "$SRC" && "$@") >"$OUT/logs/$name.log" 2>&1
  status=$?
  printf '%s\t%s\t%s\n' "$name" "$status" "$((SECONDS - started))" >>"$RESULTS"
  log "step $name: exit $status ($((SECONDS - started)) s)"
  return 0
}

# ------------------------------------------------------------------ unpack ----

if ! tar -x --no-same-owner --no-same-permissions -f /in/src.tar -C "$SRC" 2>"$OUT/logs/unpack.log"; then
  printf 'unpack\t1\t0\n' >>"$RESULTS"
  log "the archive did not unpack"
  exit 0
fi
# The archive is files only. dev/rig packages the tracked tree of a git
# checkout, so make one; -f because the commit's own .gitignore would otherwise
# drop files the commit tracks.
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null
export GIT_AUTHOR_NAME=sandbox GIT_AUTHOR_EMAIL=sandbox@invalid GIT_COMMITTER_NAME=sandbox GIT_COMMITTER_EMAIL=sandbox@invalid
(
  cd "$SRC" || exit 1
  git init -q -b sandbox . &&
    git add -f -A . &&
    git commit -q -m "sandbox: ${SANDBOX_SHA:-unknown}"
) >"$OUT/logs/git.log" 2>&1 || {
  printf 'git\t1\t0\n' >>"$RESULTS"
  exit 0
}

# The checks come from Sceny's develop, so a commit cannot loosen the checks it
# is judged by. `--harness pr` keeps the commit's own dev/ (for a change to dev/
# itself).
if [[ $HARNESS == develop ]]; then
  rm -rf "$SRC/dev"
  cp -a /opt/harness/dev "$SRC/dev"
  git -C "$SRC" add -f -A dev >/dev/null 2>&1
  git -C "$SRC" commit -q -m "sandbox: develop's dev/" >/dev/null 2>&1
fi
printf 'harness\t%s\n' "$HARNESS" >"$OUT/harness.txt"

# ------------------------------------------------------------------- tests ----

run_tests() {
  step unit-model bash -c 'node --test tests/*.test.js'
  step unit-bridge bash -c 'python3 -m unittest discover -s tests -v'
  step qml-parse bash -c 'fmt=/usr/lib/qt6/bin/qmlformat; for f in *.qml; do "$fmt" "$f" >/dev/null || { echo "$f does not parse"; exit 1; }; done'
  step manifest bash -c 'jq -e ".id == \"sceny.devices\" and .schemaVersion == 1" manifest.json'
}

# --------------------------------------------------------------------- rig ----

# The rig's phone cache holds the pinned KDE Connect APK; the run has no
# network to fetch it.
seed_rig() {
  local cache=/tmp/omarchy-plugin-rig-$(id -u)/cache
  mkdir -p "$cache" && cp /opt/sandbox/cache/* "$cache"/
}

collect_rig() {
  local dir
  for dir in "$SRC"/.rig-evidence; do
    [[ -d $dir ]] && cp -r "$dir" "$OUT/rig" 2>/dev/null
  done
  find "$OUT/rig" "$OUT/logs" -type f -name '*.png' -exec cp -n {} "$OUT/screenshots/" \; 2>/dev/null
  return 0
}

run_rig() {
  seed_rig
  step rig-ci env dev/rig ci --evidence "$OUT/rig"
  collect_rig
}

run_script() {
  [[ -r /in/script.sh ]] || return 0
  seed_rig
  step script-up env dev/rig up --owner none --ttl 3000
  cp -r /tmp/omarchy-plugin-rig-"$(id -u)"/last-failed-up "$OUT/rig-up-failed" 2>/dev/null
  step script env SANDBOX_OUT="$OUT" bash /in/script.sh
  step script-down dev/rig down
}

IFS=, read -ra WANT <<<"$STEPS"
for s in "${WANT[@]}"; do
  case $s in
  tests) run_tests ;;
  rig) run_rig ;;
  script) run_script ;;
  *) log "unknown step $s" ;;
  esac
done

log "done"
exit 0
