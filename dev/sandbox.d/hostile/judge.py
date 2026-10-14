#!/usr/bin/env python3
"""Judge the evidence a hostile commit wrote out. Run by `dev/sandbox hostile-test`.

usage: judge.py <work dir> <kind> <out dir>
kinds: probe (tests step, no device), probe-rig (inside the rig step's script),
       memory, processes, disk, hang, stdout-flood, stderr-escape, stderr-flood,
       many-dirs, rewrite

Prints one line per check: PASS<TAB>what, FAIL<TAB>what<TAB>evidence,
INFO<TAB>text. The out dir is the sandbox's own result directory: data only.
"""
import json
import os
import re
import sys
import unicodedata

work, kind, out = sys.argv[1:4]
T = json.load(open(os.path.join(work, "targets.json")))
lines = []


def check(name, ok, detail=""):
    if ok:
        lines.append(f"PASS\t{name}")
    else:
        lines.append(f"FAIL\t{name}\t{json.dumps(detail, default=str)[:600]}")


def info(text):
    lines.append(f"INFO\t{text}")


def load(name):
    path = os.path.join(out, name)
    return json.load(open(path)) if os.path.exists(path) else None


summary = load("summary.json") or {}

if kind in ("probe", "probe-rig"):
    p = load("probe.json")
    check("the hostile commit ran and wrote its evidence", p is not None)
    if p is None:
        print("\n".join(lines))
        sys.exit(0)
    usual = {"core", "fd", "full", "mqueue", "null", "ptmx", "pts", "random", "shm", "stderr", "stdin", "stdout", "tty", "urandom", "zero"}
    extra = set(p["dev"]) - usual
    check("a canary file in the owner's home (and two more, in the runtime dir and /tmp) is not readable",
          all(v == "NO" for v in p["canary_paths"].values()), p["canary_paths"])
    check("the canary is not found anywhere in the container, by name or by content (the search finds a canary planted inside as a control)",
          p["canary_found_anywhere"] == [] and p["canary_search_control"] is True, (p["canary_found_anywhere"], p["canary_search_control"]))
    check("the owner's home directory does not exist inside", p["home_listing"] == "NO SUCH DIRECTORY", p["home_listing"])
    check("an unprivileged uid, with the owner's uid not mapped at all", p["uid"] == 1000 and p["uid_map"][:3] == ["0", "1", "65536"], p["uid_map"])
    check("no capability, no_new_privs, a seccomp filter",
          int(p["cap_eff"], 16) == 0 and int(p["cap_bnd"], 16) == 0 and p["no_new_privs"] == "1" and p["seccomp"] == "2",
          (p["cap_eff"], p["cap_bnd"], p["no_new_privs"], p["seccomp"]))
    check("no PAPERCLIP_*, token, session or bus variable, and not the secret this test exported on the host",
          p["env_leaks"] == [] and p["process_env_leaks"] == [], (p["env_leaks"], p["process_env_leaks"]))
    check("only a loopback interface", p["interfaces"] == ["lo"], p["interfaces"])
    bad = {k: v for k, v in p["network"].items() if v in ("CONNECTED", "RESOLVED")}
    check("no connection opens: internet (tcp, udp, ipv6), DNS, LAN gateway, the host's LAN address, host loopback, unix and abstract sockets, adb and KDE Connect ports",
          bad == {}, p["network"])
    info("attempts: " + ", ".join(f"{k}={v}" for k, v in sorted(p["network"].items())))
    conn = os.path.join(work, "connections.log")
    seen = [l for l in (open(conn).read().split("\n") if os.path.exists(conn) else []) if l]
    check("the listeners this test opened on the host saw no connection", seen == [], seen)
    leaked = {k: v for k, v in p["host_paths"].items() if not k.startswith("listing") and v != "ABSENT"}
    check("no host session bus, Wayland, PipeWire, Hyprland, podman or docker socket, no ssh, config, gh, android or paperclip directory, no shadow file",
          leaked == {}, leaked)
    check("/run/user has nothing in it", p["host_paths"].get("listing /run/user", []) == [], p["host_paths"].get("listing /run/user"))
    if kind == "probe":
        check("no device at all (the tests step gets none)", extra == set(), sorted(extra))
    else:
        ok = "kvm" in extra and "dri" in extra and not (extra - {"kvm", "dri"})
        check("only /dev/kvm and one render node among the devices", ok, sorted(extra))
    check("in the container's own namespace, mount, setuid(0), ptrace of init and reboot are refused",
          all(p[k] != "OK" for k in ("mount_tmpfs", "setuid_0", "ptrace_init", "reboot")),
          {k: p[k] for k in ("mount_tmpfs", "setuid_0", "ptrace_init", "reboot")})
    check("no new user namespace: unshare(2), clone(2), `unshare -Ur`, `unshare -Urm` and bwrap are refused (nothing is mounted in a namespace of its own)",
          all(v == "REFUSED" for v in p["userns"].values()), p["userns"])
    check("writes to /etc, /usr, /opt, the commit's tar, /sys, /proc/sys and /boot fail",
          all(v != "WROTE" for v in p["write_outside"].values()), p["write_outside"])
    check("only the scratch trees are writable (/tmp, /out, /work, the home)", all(v == "WROTE" for v in p["write_allowed"].values()), p["write_allowed"])
    check("the commit's own dev/rig is replaced by develop's", p["harness_replaced_by_commit"] is False, p["harness_replaced_by_commit"])
    skipped = [s for s in open(os.path.join(out, "SKIPPED.txt")).read().split("\n") if s] if os.path.exists(os.path.join(out, "SKIPPED.txt")) else []
    left = [n for n in ("evil-symlink", "evil-fifo", "evil-hardlink", "huge-sparse", "has space", "n" * 200)
            if os.path.lexists(os.path.join(out, "probe", n))]
    check("what leaves is read as data: a symlink, a fifo, a hard link, a 200-character name, a space in a name and a 210 MB file are not materialised",
          left == [] and len(skipped) >= 5, {"materialised": left, "skipped": [s[:70] for s in skipped]})
    check("an ordinary result file does arrive",
          os.path.exists(os.path.join(out, "probe", "fine.txt")) and open(os.path.join(out, "probe", "fine.txt")).read() == "an ordinary result\n")
    check("nothing the commit wrote reached outside the output directory",
          not os.path.lexists(os.path.join(work, "evil")) and not os.path.lexists(os.path.join(os.path.dirname(out), "evil")))
    if kind == "probe-rig":
        results = {r["step"]: r["exit"] for r in summary.get("results", [])}
        check("the rig was up while the hostile script ran (the script unit exits 0 only then)", results.get("script") == 0, results)

elif kind == "memory":
    progress = open(os.path.join(out, "mem-progress")).read() if os.path.exists(os.path.join(out, "mem-progress")) else "0"
    limit_mb = 1024
    check("a memory bomb is stopped at the memory limit (the host did not swap or stall)",
          summary.get("oom_killed") is True or int(progress or 0) <= limit_mb + 256, {"allocated_mb": progress, "oom": summary.get("oom_killed")})
    info(f"allocated {progress} MB before it was stopped, limit {limit_mb} MB, oom killed {summary.get('oom_killed')}")

elif kind == "processes":
    p = load("probe.json") or {}
    check("a fork bomb is stopped by the process limit", p.get("stopped_by") == "EAGAIN" and 0 < p.get("forked", 0) < 2048, p)
    info(f"forked {p.get('forked')} before {p.get('stopped_by')}")

elif kind == "disk":
    p = load("probe.json") or {}
    caps = {"out": 768, "work": 1024, "home": 1024, "var_tmp": 256}
    ok = all(k in p and p[k]["stopped_by"] == "ENOSPC" and p[k]["mb"] <= caps[k] for k in caps)
    check("filling /out, /work, the home and /var/tmp stops each at its size limit (ENOSPC)", ok, p)
    info(", ".join(f"{k} {v['mb']} MB" for k, v in p.items()))

elif kind == "hang":
    check("a commit that never ends is killed at the timeout (no results leave)",
          summary.get("timed_out") is True or not os.path.exists(os.path.join(out, "results.tsv")), summary)
    info(f"run lasted {summary.get('seconds')} s with a {summary.get('timeout')} s timeout")

elif kind == "stdout-flood":
    row = {r["step"]: r for r in summary.get("results", [])}.get("unit-bridge", {})
    cap = T["max_result"]
    check("a flood into the results pipe is cut at the cap on the host: the unit fails, and the run with it",
          row.get("exit", 0) != 0 and "over the limit" in row.get("note", "") and summary.get("passed") is False, row)
    check("no more than the cap (plus one byte, to see the overflow) was kept from the pipe",
          row.get("stdout_bytes") == cap + 1, {"stdout_bytes": row.get("stdout_bytes"), "cap": cap})

elif kind == "stderr-escape":
    text = open(os.path.join(work, f"run-{kind}.log"), "rb").read().decode("utf-8", "replace")
    own = re.sub(r"\x1b\[(?:1|36|32|33|31|0)m", "", text)
    bad = sorted({hex(ord(c)) for c in own if c not in "\n\t" and unicodedata.category(c) in ("Cc", "Cf")})
    check("escape sequences, bell, carriage return, C1 and bidirectional controls from the container's stderr never reach the terminal",
          bad == [], bad)
    check("the text around them does arrive (the control bytes are dropped, not the line)",
          "HOSTILE-VISIBLE-LINE" in text and "HOSTILE-OSC-TITLE" in text, text[-400:])

elif kind == "stderr-flood":
    path = os.path.join(work, f"run-{kind}.log")
    raw = open(path, "rb").read()
    text = raw.decode("utf-8", "replace")
    longest = max((len(l) for l in raw.split(b"\n")), default=0)
    check("a 96 MB stderr flood (48 MB without a newline, 48 MB of lines) is cut at 16 MB, and the writer is drained, not blocked",
          len(raw) < 17 * 1024 * 1024 and "[further output dropped]" in text, {"log_bytes": len(raw)})
    check("no line on the terminal is longer than about 4 KB", longest < 4300, {"longest": longest})
    check("what was written after the flood does not arrive", "HOSTILE-AFTER-THE-FLOOD" not in text)
    info(f"log {len(raw) >> 20} MB, longest line {longest} bytes")

elif kind == "many-dirs":
    row = {r["step"]: r for r in summary.get("results", [])}.get("unit-bridge", {})
    many = os.path.join(out, "many")
    made = len(os.listdir(many)) if os.path.isdir(many) else 0
    skipped_path = os.path.join(out, "SKIPPED.txt")
    skipped = open(skipped_path).read() if os.path.exists(skipped_path) else ""
    check("a tar of 100,000 empty directories is read up to 20,000 members and then refused: the unit and the run fail",
          0 < made <= 20000 and row.get("exit", 0) != 0 and summary.get("passed") is False, {"dirs_on_host": made, "row": row})
    check("the refusal is written down", "more than 20000 members" in skipped, skipped[:200])

elif kind == "rewrite":
    p = load("probe.json")
    rows = {r["step"]: r for r in summary.get("results", [])}
    check("the test did rewrite dev/rig, results.tsv and summary.json in its container (the attack is real here)",
          p == {"rig_rewritten": True, "results_written": True, "summary_written": True}, p)
    check("the rig step fails: it ran develop's own dev/rig from a fresh unpack, not the one the test rewrote",
          rows.get("rig-ci", {}).get("exit", 0) != 0, rows.get("rig-ci"))
    tsv_path = os.path.join(out, "results.tsv")
    tsv = open(tsv_path).read() if os.path.exists(tsv_path) else ""
    check("results.tsv and summary.json are the host's: nothing the test planted is in them, and the run fails",
          tsv != "" and "planted" not in tsv and "planted" not in json.dumps(summary) and summary.get("passed") is False,
          {"tsv": tsv[:200], "passed": summary.get("passed")})

print("\n".join(lines))
