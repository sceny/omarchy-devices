#!/usr/bin/env python3
"""Run inside a `dev/sandbox dev` session by `dev/sandbox hostile-test` (phase dev).

usage: dev_probe.py TARGETS_JSON
Prints one line per check: `PASS what` or `FAIL what: evidence`. TARGETS_JSON is
the argument text (the host's listeners, canaries and the secret's name), never
a file from this machine.
"""
import glob
import json
import os
import socket
import subprocess
import sys

T = json.loads(sys.argv[1])
out = []


def check(name, ok, detail=""):
    out.append(("PASS " + name) if ok else ("FAIL " + name + ": " + str(detail)[:300]))


def connect(family, addr):
    s = socket.socket(family, socket.SOCK_STREAM)
    s.settimeout(2)
    try:
        s.connect(addr)
        return True
    except OSError:
        return False
    finally:
        s.close()


reach = {
    "loopback": connect(socket.AF_INET, ("127.0.0.1", T["loopback_port"])),
    "unix": connect(socket.AF_UNIX, T["unix_path"]),
    "abstract": connect(socket.AF_UNIX, "\0" + T["abstract_name"]),
}
if T.get("lan_ip"):
    reach["lan"] = connect(socket.AF_INET, (T["lan_ip"], T["lan_port"]))
if T.get("lan_gateway"):
    reach["gateway"] = connect(socket.AF_INET, (T["lan_gateway"], 53))
check("no host listener is reachable: loopback, LAN, gateway, a unix and an abstract socket", not any(reach.values()), reach)

links = [n for n in os.listdir("/sys/class/net")]
check("the only network interface is loopback", links == ["lo"], links)

check("the owner's secret is not in the environment", T["secret_name"] not in os.environ and not any("SANDBOX_HOSTILE" in k for k in os.environ),
      [k for k in os.environ if "SANDBOX_HOSTILE" in k])
check("HOME is the session's own tmpfs", os.environ.get("HOME") == "/home/sandbox", os.environ.get("HOME"))
owner = [p for p in T["host_paths"] if p != "/etc/shadow"]
check("the owner's home, its credentials and sockets are not here", not any(os.path.exists(p) for p in owner), [p for p in owner if os.path.exists(p)])
check("the canaries are not here", not any(os.path.exists(p) for p in T["canary_paths"]), T["canary_paths"])

hits = []
for root in ("/work", "/tmp", "/out", "/home", "/run", "/var/tmp"):
    for r, _, files in os.walk(root):
        for n in files:
            p = os.path.join(r, n)
            try:
                if os.path.getsize(p) < 1 << 20 and T["canary_prefix"].encode() in open(p, "rb").read():
                    hits.append(p)
            except OSError:
                pass
check("no file in the session's writable places holds a canary", not hits, hits)

status = dict(line.split(":\t", 1) for line in open("/proc/self/status").read().splitlines() if ":\t" in line)
check("no capability and no new privileges", status["CapEff"].strip("0") == "" and status["CapBnd"].strip("0") == "" and status["NoNewPrivs"].strip() == "1", status)
check("the sandbox user, not root", os.getuid() == 1000 and os.getgid() == 1000, (os.getuid(), os.getgid()))

try:
    open("/usr/sceny-probe", "w").close()
    ro = False
except OSError:
    ro = True
check("the root filesystem is read-only", ro)

socks = [p for p in glob.glob("/run/**", recursive=True) + glob.glob("/tmp/.X11-unix/*") if p.endswith((".sock", "bus", "native")) or "wayland" in p]
check("no host socket (bus, Wayland, PipeWire, X, podman) under /run or /tmp", not socks, socks)

extra = set(os.listdir("/dev")) - {"core", "fd", "full", "mqueue", "null", "ptmx", "pts", "random", "shm", "stderr", "stdin", "stdout", "tty",
                                   "urandom", "zero", "kvm", "dri", "console", "stdout"}
check("the devices are the standard set, /dev/kvm and a render node only", not extra and not glob.glob("/dev/dri/card*"), sorted(extra) + glob.glob("/dev/dri/card*"))

src = [l.split()[3] for l in open("/proc/self/mountinfo")]
check("no mount's source is a path of the owner's home", not any(s.startswith(T["home"]) for s in src), [s for s in src if s.startswith(T["home"])])

print("\n".join(out))
