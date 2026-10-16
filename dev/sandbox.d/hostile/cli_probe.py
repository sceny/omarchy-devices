#!/usr/bin/env python3
"""Run inside a `dev/sandbox dev` session by `dev/sandbox hostile-test` (phase dev).

usage: cli_probe.py TARGETS_JSON
Starts the Paperclip server the image carries (`paperclipai run`, what the
paperclipai rig starts), with the loopback config the rig seeds, and prints one
line per check while it runs: `PASS what` or `FAIL what: evidence`. The server
is stopped before the script ends.
"""
import json
import os
import signal
import socket
import subprocess
import sys
import time
import urllib.request

T = json.loads(sys.argv[1])
out = []
HTTP, PG = 31999, 54399


def check(name, ok, detail=""):
    out.append(("PASS " + name) if ok else ("FAIL " + name + ": " + str(detail)[:300]))


def connect(addr, timeout=3):
    s = socket.socket()
    s.settimeout(timeout)
    try:
        s.connect(addr)
        return True
    except OSError:
        return False
    finally:
        s.close()


data = "/tmp/pc-cli-probe"
inst = f"{data}/instances/probe"
os.makedirs(inst, exist_ok=True)
config = {
    "$meta": {"version": 1, "updatedAt": "2026-01-01T00:00:00.000Z", "source": "onboard"},
    "database": {"mode": "embedded-postgres", "embeddedPostgresDataDir": inst + "/db", "embeddedPostgresPort": PG,
                 "backup": {"enabled": False, "intervalMinutes": 60, "retentionDays": 1, "dir": inst + "/data/backups"}},
    "logging": {"mode": "file", "logDir": inst + "/logs"},
    "server": {"deploymentMode": "local_trusted", "exposure": "private", "bind": "loopback", "host": "127.0.0.1",
               "port": HTTP, "allowedHostnames": [], "serveUi": False},
    "telemetry": {"enabled": False},
    "updates": {"checkEnabled": False},
    "auth": {"baseUrlMode": "auto", "disableSignUp": False},
    "storage": {"provider": "local_disk", "localDisk": {"baseDir": inst + "/data/storage"},
                "s3": {"bucket": "paperclip", "region": "us-east-1", "prefix": "", "forcePathStyle": False}},
    "secrets": {"provider": "local_encrypted", "strictMode": False, "localEncrypted": {"keyFilePath": inst + "/secrets/master.key"}},
}
json.dump(config, open(inst + "/config.json", "w"))

log = open(data + "/server.log", "wb")
proc = subprocess.Popen(["paperclipai", "run", "-d", data, "-i", "probe"], stdout=log, stderr=subprocess.STDOUT,
                        env=dict(os.environ, PORT=str(HTTP)), start_new_session=True)
healthy = False
try:
    deadline = time.time() + 150
    while time.time() < deadline and proc.poll() is None:
        try:
            with urllib.request.urlopen(f"http://127.0.0.1:{HTTP}/api/health", timeout=3) as r:
                healthy = json.load(r).get("status") == "ok"
        except Exception:
            pass
        if healthy:
            break
        time.sleep(3)
    check("the Paperclip server in the image starts and answers on the session's own loopback", healthy,
          open(data + "/server.log", "rb").read()[-400:].decode("utf-8", "replace"))

    if healthy:
        wild = []
        for fam, path in (("4", "/proc/net/tcp"), ("6", "/proc/net/tcp6")):
            for line in open(path).read().splitlines()[1:]:
                f = line.split()
                if f[3] != "0A":
                    continue
                host = f[1].split(":")[0]
                if host not in ("0100007F", "00000000000000000000000001000000", "0000000000000000FFFF00000100007F"):
                    wild.append((fam, f[1]))
        check("every port the server listens on is bound to loopback, none to a wildcard or LAN address", not wild, wild)

    routes = open("/proc/net/route").read().splitlines()[1:]
    check("the only network interface is loopback and there is no route", os.listdir("/sys/class/net") == ["lo"] and not routes,
          (os.listdir("/sys/class/net"), routes))

    reach = {"internet": connect(("1.1.1.1", 443)), "dns": connect(("8.8.8.8", 53))}
    try:
        socket.getaddrinfo("registry.npmjs.org", 443)
        reach["resolves names"] = True
    except OSError:
        reach["resolves names"] = False
    if T.get("loopback_port"):
        reach["host loopback listener"] = connect(("127.0.0.1", T["loopback_port"]))
    if T.get("lan_ip"):
        reach["host LAN listener"] = connect((T["lan_ip"], T["lan_port"]))
    check("with the server running, nothing outside the session is reachable: no internet, no DNS, no host listener", not any(reach.values()), reach)

    pc_env = [k for k in os.environ if "PAPERCLIP" in k.upper() or "TOKEN" in k.upper() or "API_KEY" in k.upper()]
    check("the server was started with no Paperclip variable, token or API key", not pc_env, pc_env)
    check("the server has no Paperclip home of the owner's: its only instance is the probe's own", not os.path.exists(os.path.expanduser("~/.paperclip")) and not os.path.exists("/root/.paperclip"))
    check("its telemetry and update checks are off in the config the rig seeds", not config["telemetry"]["enabled"] and not config["updates"]["checkEnabled"])
finally:
    try:
        os.killpg(proc.pid, signal.SIGTERM)
        proc.wait(timeout=30)
    except Exception:
        try:
            os.killpg(proc.pid, signal.SIGKILL)
        except Exception:
            pass
    time.sleep(1)
    check("the server stopped with the probe", not connect(("127.0.0.1", HTTP), 2))

print("\n".join(out))
