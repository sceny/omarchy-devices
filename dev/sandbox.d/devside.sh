#!/bin/bash
# The inside of a `dev/sandbox dev` session: what the host asks of the long-lived
# container, one verb at a time. The host mounts this file read-only at
# /opt/devside.sh, so a tree that is synced in never replaces it.
#
#   unpack [src|live] a tar of the tree on stdin becomes /work/src (a git checkout, for dev/rig),
#                     or /work/live, a second tree (the tag an upgrade starts from)
#   up [TTL]          seed the rig's phone cache and bring the rig up (no owner, TTL seconds)
#   rig ARGS...       dev/rig on the session's one rig
#   shot NAME         a screenshot of the rig into /out/screenshots/NAME.png
#   record NAME SECONDS FPS [-- COMMAND...]
#                     frames into /out/rec/NAME/ while COMMAND runs
#   clear             empty /out (after a pull)
#
# shellcheck shell=bash

set -uo pipefail

SRC=/work/src
OUT=/out
export RIG_COMPOSITOR_OUTSIDE_NS=1 RIG_COMPOSITOR_ATTEMPTS=60

die() {
  printf 'devside: %s\n' "$*" >&2
  exit 2
}

name_ok() { [[ ${1:-} =~ ^[a-z0-9][a-z0-9_-]{0,60}$ ]] || die "a name is lower-case letters, digits, - and _ (at most 61)"; }

rig_id() {
  (cd "$SRC" && dev/rig ps --json 2>/dev/null | jq -r '.rigs[0].id // empty')
}

# dev/rig on the session's rig; --owner none rigs are named by --rig.
rig() {
  local id
  cd "$SRC" || die "no tree is synced yet (dev/sandbox dev sync)"
  id=$(rig_id)
  if [[ -n $id ]]; then exec dev/rig --rig "$id" "$@"; fi
  exec dev/rig "$@"
}

verb=${1:-}
shift || true
case $verb in
unpack)
  case ${1:-src} in
  src) dest=$SRC ;;
  live) dest=/work/live ;;
  *) die "unpack: src or live" ;;
  esac
  export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null
  export GIT_AUTHOR_NAME=sandbox GIT_AUTHOR_EMAIL=sandbox@invalid GIT_COMMITTER_NAME=sandbox GIT_COMMITTER_EMAIL=sandbox@invalid
  rm -rf /work/incoming && mkdir -p /work/incoming || die "no room in /work"
  tar -x --no-same-owner --no-same-permissions -f - -C /work/incoming || die "the tree did not unpack"
  (
    cd /work/incoming &&
      git init -q -b sandbox . &&
      git add -f -A . &&
      git commit -q -m "sandbox dev tree"
  ) >/dev/null 2>&1 || die "the tree is not a git checkout"
  rm -rf "$dest"
  mv /work/incoming "$dest" || die "could not put the tree in place"
  ;;
up)
  ttl=${1:-7200}
  [[ $ttl =~ ^[0-9]+$ ]] || die "up: TTL is whole seconds"
  cache=/tmp/omarchy-plugin-rig-$(id -u)/cache
  mkdir -p "$cache" && cp /opt/sandbox/cache/* "$cache"/ || die "no phone cache in the image"
  cd "$SRC" || die "no tree is synced yet (dev/sandbox dev sync)"
  exec dev/rig up --owner none --ttl "$ttl"
  ;;
rig) rig "$@" ;;
shot)
  name_ok "${1:-}"
  mkdir -p "$OUT/screenshots" || die "no room in /out"
  [[ ! -e $OUT/screenshots/$1.png ]] || die "screenshot $1 exists"
  rig screenshot "$OUT/screenshots/$1.png"
  ;;
record)
  name_ok "${1:-}"
  name=$1 seconds=${2:-} fps=${3:-}
  shift 3 || die "record: NAME SECONDS FPS [-- COMMAND...]"
  [[ ${1:-} == -- ]] && shift
  mkdir -p "$OUT/rec" || die "no room in /out"
  [[ ! -e $OUT/rec/$name ]] || die "recording $name exists"
  if (($#)); then
    rig record --seconds "$seconds" --fps "$fps" --tail 2 --out "$OUT/rec/$name" -- "$@"
  else
    rig record --seconds "$seconds" --fps "$fps" --tail 2 --out "$OUT/rec/$name"
  fi
  ;;
clear) find /out -mindepth 1 -delete ;;
*) die "unknown verb '$verb'" ;;
esac
