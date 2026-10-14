#!/bin/bash
# The sandbox's acceptance test: `dev/sandbox hostile-test [--quick]`.
#
# Builds hostile commits in a throwaway repository (dev/sandbox.d/hostile/
# test_hostile.py, written here and run as a contributor's test would be),
# plants canaries in this machine's real home, opens listeners on the host
# (loopback, LAN address, a unix socket, an abstract socket), runs the commits
# in the sandbox, and judges the evidence they wrote out (judge.py). Then it
# proves nothing is left. Sourced by dev/sandbox. Never runs a contributor's
# code: the commits are this file's own.
#
# shellcheck shell=bash

HOSTILE_PASS=0
HOSTILE_FAIL=0
HOSTILE_WORK=""
HOSTILE_LISTENER_PID=""
HOSTILE_CANARIES=()

hostile_cleanup() {
  [[ -n $HOSTILE_LISTENER_PID ]] && kill "$HOSTILE_LISTENER_PID" 2>/dev/null
  HOSTILE_LISTENER_PID=""
  local f
  for f in "${HOSTILE_CANARIES[@]}"; do rm -f -- "$f"; done
  HOSTILE_CANARIES=()
  if [[ -n $HOSTILE_WORK && $HOSTILE_WORK == "${TMPDIR:-/tmp}"/sceny-hostile.* ]]; then rm -rf -- "$HOSTILE_WORK"; fi
  HOSTILE_WORK=""
}

# Listeners on the host that must never see a connection from the sandbox.
hostile_listeners() {
  python3 - "$HOSTILE_WORK" <<'PY' &
import json, os, selectors, socket, sys, time
work = sys.argv[1]
sel = selectors.DefaultSelector()
def listen(name, s):
    s.listen(8)
    s.setblocking(False)
    sel.register(s, selectors.EVENT_READ, name)
lo = socket.socket(); lo.bind(('127.0.0.1', 0)); listen('loopback', lo)
anyip = socket.socket(); anyip.bind(('0.0.0.0', 0)); listen('lan', anyip)
path = os.path.join(os.environ.get('XDG_RUNTIME_DIR', work), f'sceny-hostile-{os.getpid()}.sock')
us = socket.socket(socket.AF_UNIX); us.bind(path); listen('unix', us)
ab = socket.socket(socket.AF_UNIX); ab.bind('\0sceny-hostile-%d' % os.getpid()); listen('abstract', ab)
with open(os.path.join(work, 'listeners.json'), 'w') as f:
    json.dump({'loopback_port': lo.getsockname()[1], 'lan_port': anyip.getsockname()[1], 'unix_path': path,
               'abstract_name': 'sceny-hostile-%d' % os.getpid()}, f)
try:
    while True:
        for key, _ in sel.select(timeout=1):
            conn, _ = key.fileobj.accept()
            with open(os.path.join(work, 'connections.log'), 'a') as log:
                log.write(f'{key.data} {time.time()}\n')
            conn.close()
finally:
    try:
        os.unlink(path)
    except OSError:
        pass
PY
  HOSTILE_LISTENER_PID=$!
  local i
  for ((i = 0; i < 50; i++)); do
    [[ -s $HOSTILE_WORK/listeners.json ]] && return 0
    sleep 0.1
  done
  return 1
}

# One commit per mode in the throwaway repository; prints the sha.
hostile_commit() { # <repo> <mode>
  local repo=$1 mode=$2
  (
    cd "$repo" || exit 1
    mkdir -p tests dev
    cp "$SB_DIR/sandbox.d/hostile/test_hostile.py" tests/test_hostile.py
    python3 - "$HOSTILE_WORK/targets.json" "$mode" >hostile_targets.json <<'PY'
import json, sys
t = json.load(open(sys.argv[1]))
t['mode'] = sys.argv[2]
json.dump(t, sys.stdout)
PY
    # the plugin's own files (not its tests or docs), so the rig can package the commit
    git -C "$SB_DIR/.." archive HEAD -- . ':(exclude)tests' ':(exclude)dev' ':(exclude)docs' | tar -x
    printf '#!/bin/bash\n# HARNESS-FROM-THE-HOSTILE-COMMIT\nexit 0\n' >dev/rig
    chmod +x dev/rig
    # the rig's package step refuses a tracked symlink, so only the tests-step commit has one
    [[ $mode == rigprobe ]] || ln -sf /etc/passwd link-out-of-the-tree
    git add -f -A >/dev/null
    git -c user.name=hostile -c user.email=hostile@invalid commit -q -m "hostile: $mode"
    git rev-parse HEAD
  )
}

# hostile_run <kind> <mode> [cmd_run options...]: run the commit of <mode>
# and print the judge's lines for <kind>.
hostile_run() {
  local kind=$1 mode=$2 out
  shift 2
  out="$HOSTILE_WORK/out-$kind"
  # cmd_run exits through die on a refusal; a subshell keeps this test going.
  (cmd_run sceny/omarchy-devices "$(cat "$HOSTILE_WORK/sha-$mode")" --from "$HOSTILE_WORK/repo" --out "$out" "$@") \
    >"$HOSTILE_WORK/run-$kind.log" 2>&1
  sed 's/^/    /' "$HOSTILE_WORK/run-$kind.log" >&2
  local line what status detail
  while IFS=$'\t' read -r status what detail; do
    case $status in
    PASS)
      ok "$what"
      HOSTILE_PASS=$((HOSTILE_PASS + 1))
      ;;
    FAIL)
      fail "$what"
      printf '      evidence: %s\n' "$detail" >&2
      HOSTILE_FAIL=$((HOSTILE_FAIL + 1))
      ;;
    INFO) step "$what" ;;
    esac
  done < <(python3 "$SB_DIR/sandbox.d/hostile/judge.py" "$HOSTILE_WORK" "$kind" "$out")
}

cmd_hostile_test() {
  local quick=0 only="" keep=0
  while (($#)); do
    case $1 in
    --quick) quick=1 ;;
    --keep) keep=1 ;;
    --only) only=${2:?--only needs a list (probe,probe-rig,memory,processes,disk,hang)}; shift ;;
    *) die "hostile-test: unknown option '$1'" ;;
    esac
    shift
  done
  want() { [[ -z $only || ,$only, == *",$1,"* ]]; }
  require_tools
  pm image exists "$SB_IMAGE" || die "hostile-test: no image; run 'dev/sandbox build' first"
  HOSTILE_WORK=$(mktemp -d "${TMPDIR:-/tmp}/sceny-hostile.XXXXXX")
  trap 'hostile_cleanup' EXIT INT TERM
  local rand
  rand=$(od -An -N8 -tx1 /dev/urandom | tr -d ' \n')

  say "hostile test: planting canaries and listeners on this machine"
  local canary_home="$SB_HOME/.sceny-sandbox-canary-$rand"
  local canary_run="/run/user/$SB_UID/sceny-sandbox-canary-$rand"
  local canary_tmp="/tmp/sceny-sandbox-canary-$rand"
  local f
  for f in "$canary_home" "$canary_run" "$canary_tmp"; do
    (umask 077 && printf 'SANDBOX-CANARY-%s\n' "$rand" >"$f") && HOSTILE_CANARIES+=("$f")
  done
  local secret_name="SANDBOX_HOSTILE_SECRET_$rand" secret_value="secret-$rand"
  hostile_listeners || die "could not start the host listeners"
  local lan_ip lan_gateway
  lan_ip=$(ip -4 -o addr show scope global 2>/dev/null | awk '{print $4}' | cut -d/ -f1 | head -1)
  lan_gateway=$(ip -4 route show default 2>/dev/null | awk '{print $3}' | head -1)
  step "canaries: the home ($(basename "$canary_home")), the runtime dir and /tmp"
  step "host listeners: loopback, ${lan_ip:-no LAN address}, a unix socket, an abstract socket; LAN gateway ${lan_gateway:-none}"

  python3 - "$HOSTILE_WORK" "$secret_name" "$secret_value" "$lan_ip" "$lan_gateway" "$canary_home" "$canary_run" "$canary_tmp" "$SB_UID" "$SB_HOME" <<'PY'
import hashlib, json, os, sys
work, sname, svalue, lan_ip, gateway, c1, c2, c3, uid, home = sys.argv[1:]
l = json.load(open(os.path.join(work, 'listeners.json')))
host_paths = [f'/run/user/{uid}/bus', f'/run/user/{uid}/wayland-0', f'/run/user/{uid}/wayland-1',
              f'/run/user/{uid}/pipewire-0', f'/run/user/{uid}/pulse/native', f'/run/user/{uid}/hypr',
              f'/run/user/{uid}/podman/podman.sock', '/run/dbus/system_bus_socket', '/var/run/docker.sock',
              '/tmp/.X11-unix/X0', home, home + '/.ssh', home + '/.config', home + '/.cache',
              home + '/.local/share/sceny-sandbox', home + '/.paperclip', home + '/.config/gh',
              home + '/.gitconfig', home + '/.android', '/etc/shadow']
json.dump({
    'canary_paths': [c1, c2, c3], 'canary_prefix': 'SANDBOX-CANARY-', 'canary_name_prefix': 'sandbox-canary-',
    'secret_name': sname, 'secret_sha256': hashlib.sha256(svalue.encode()).hexdigest(),
    'lan_ip': lan_ip, 'lan_gateway': gateway, 'lan_port': l['lan_port'], 'loopback_port': l['loopback_port'],
    'unix_path': l['unix_path'], 'abstract_name': l['abstract_name'], 'host_paths': host_paths,
}, open(os.path.join(work, 'targets.json'), 'w'))
PY

  git init -q -b main "$HOSTILE_WORK/repo"
  local mode
  for mode in probe rigprobe memory processes disk hang; do
    hostile_commit "$HOSTILE_WORK/repo" "$mode" >"$HOSTILE_WORK/sha-$mode" || die "could not build the hostile commit ($mode)"
  done
  step "hostile commits built in a throwaway repository ($(cut -c1-12 "$HOSTILE_WORK/sha-probe") and five more)"

  export "$secret_name=$secret_value"

  if want probe; then
    say "1. the hostile commit's probes, in the tests step (no device passed in)"
    hostile_run probe probe --steps tests
  fi

  if want probe-rig; then
    say "2. the same probes, run by a script while the rig and its emulator are up (kvm and a render node passed in)"
    if ((quick)); then
      warn "skipped (--quick)"
    else
      printf '#!/bin/bash\ncd /work/src && python3 -m unittest discover -s tests\nexit 0\n' >"$HOSTILE_WORK/probe-script.sh"
      hostile_run probe-rig rigprobe --steps script --script "$HOSTILE_WORK/probe-script.sh"
    fi
  fi

  if want memory; then
    say "3. a memory bomb (limit 1 GB)"
    local saved_memory=$SB_MEMORY
    SB_MEMORY=1g
    hostile_run memory memory --steps tests
    SB_MEMORY=$saved_memory
  fi
  if want processes; then
    say "4. a fork bomb (limit $SB_PIDS processes)"
    hostile_run processes processes --steps tests
  fi
  if want disk; then
    say "5. filling every writable tree"
    hostile_run disk disk --steps tests
  fi
  if want hang; then
    say "6. a commit that never ends (timeout 40 s)"
    hostile_run hang hang --steps tests --timeout 40
  fi

  unset "$secret_name"
  say "7. nothing is left"
  local clean=0
  cmd_verify_clean || clean=1
  if ((clean == 0)); then
    ok "verify-clean"
    HOSTILE_PASS=$((HOSTILE_PASS + 1))
  else
    fail "verify-clean"
    HOSTILE_FAIL=$((HOSTILE_FAIL + 1))
  fi
  local still=0
  for f in "${HOSTILE_CANARIES[@]}"; do
    [[ $(cat "$f" 2>/dev/null) == "SANDBOX-CANARY-$rand" ]] || still=1
  done
  if ((still == 0)); then
    ok "the canaries on this machine are intact and were never modified"
    HOSTILE_PASS=$((HOSTILE_PASS + 1))
  else
    fail "a canary changed"
    HOSTILE_FAIL=$((HOSTILE_FAIL + 1))
  fi
  say "hostile test: $HOSTILE_PASS passed, $HOSTILE_FAIL failed"
  if ((keep)); then
    step "kept for reading: $HOSTILE_WORK"
    HOSTILE_WORK=""
  fi
  hostile_cleanup
  ((HOSTILE_FAIL == 0))
}
