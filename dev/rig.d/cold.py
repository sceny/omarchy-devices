#!/usr/bin/env python3
"""A cold computer inside the rig: the packages a plugin needs are not on the
shell's PATH until a recorded install puts them there. Generic: the package
list, the firewall ports and the log come from the caller.

  cold.py build   --dir D --path PATH --log L --rules R --packages p1,p2 [--ports 1714:1764]
  cold.py pacman  -- <pacman arguments>        (the stub bin/pacman runs this)
  cold.py pkexec  -- <pkexec arguments>        (the stub bin/pkexec runs this)
  cold.py status  --dir D

Nothing here touches the real package database or the real firewall: a
package "installed" is a symlink put back in a private directory, and a
firewall rule is a line in a private copy of ufw's user.rules (bind-mounted
over the real one inside the rig's own mount namespace).
"""
import json
import os
import shlex
import subprocess
import sys

STATE = "state.json"


def load(d):
    with open(os.path.join(d, STATE)) as f:
        return json.load(f)


def save(d, st):
    tmp = os.path.join(d, STATE + ".tmp")
    with open(tmp, "w") as f:
        json.dump(st, f, indent=1)
    os.replace(tmp, os.path.join(d, STATE))


def log(st, line):
    with open(st["log"], "a") as f:
        f.write("cold: " + line + "\n")


def real(name):
    """The real tool, found past the cold directory."""
    for d in os.environ.get("COLD_REAL_PATH", "/usr/bin").split(":"):
        p = os.path.join(d, name)
        if os.access(p, os.X_OK) and not p.startswith(os.environ.get("COLD_DIR", "\0")):
            return p
    return "/usr/bin/" + name


def build(a):
    d = a["dir"]
    os.makedirs(os.path.join(d, "bin"), exist_ok=True)
    path_dirs = [p for p in a["path"].split(":") if p]
    packages = a["packages"].split(",")
    owned = {}
    for pkg in packages:
        out = subprocess.run(["pacman", "-Ql", pkg], capture_output=True, text=True).stdout
        names = set()
        for line in out.splitlines():
            parts = line.split(None, 1)
            if len(parts) == 2 and os.path.dirname(parts[1].rstrip("/")) in ("/usr/bin", "/bin"):
                names.add(os.path.basename(parts[1].rstrip("/")))
        ver = subprocess.run(["pacman", "-Q", pkg], capture_output=True, text=True).stdout.split()
        owned[pkg] = {"version": ver[1] if len(ver) > 1 else "1", "names": sorted(names), "installed": False, "restore": []}
    hidden = {n for p in owned.values() for n in p["names"]}
    cold_path, n = [], 0
    for src in path_dirs:
        try:
            entries = [e.name for e in os.scandir(src)]
        except OSError:
            continue
        hit = hidden & set(entries)
        if not hit:
            cold_path.append(src)
            continue
        n += 1
        mirror = os.path.join(d, "bin", str(n))
        os.makedirs(mirror, exist_ok=True)
        for name in entries:
            dest = os.path.join(mirror, name)
            if name in hidden or os.path.lexists(dest):
                continue
            os.symlink(os.path.join(src, name), dest)
        for pkg, info in owned.items():
            for name in info["names"]:
                if name in hit:
                    info["restore"].append([mirror, name, os.path.join(src, name)])
        cold_path.append(mirror)
    stubs = os.path.join(d, "stubs")
    os.makedirs(stubs, exist_ok=True)
    for tool in ("pacman", "pkexec"):
        with open(os.path.join(stubs, tool), "w") as f:
            f.write('#!/bin/sh\nexport COLD_DIR=%s COLD_REAL_PATH=%s\nexec python3 %s %s "$@"\n'
                    % (shlex.quote(d), shlex.quote(":".join(path_dirs)), shlex.quote(os.path.abspath(__file__)), tool))
        os.chmod(os.path.join(stubs, tool), 0o755)
    rules = a["rules"]
    base = open(a["host_rules"]).read() if os.path.exists(a["host_rules"]) else ""
    ports = a["ports"]
    kept, skip = [], False
    for line in base.splitlines():
        if ports in line:
            continue
        kept.append(line)
    open(rules, "w").write("\n".join(kept) + "\n")
    st = {"packages": owned, "log": a["log"], "rules": rules, "ports": ports, "pkexec_calls": 0}
    save(d, st)
    with open(os.path.join(d, "path"), "w") as f:
        f.write(":".join([stubs] + cold_path))
    print(":".join([stubs] + cold_path))


def install(st, pkg):
    info = st["packages"].get(pkg)
    if info is None:
        log(st, "install %s: not in the cold set; nothing to change" % pkg)
        return
    if info["installed"]:
        log(st, "ASKED-AGAIN %s: already installed by an earlier prompt" % pkg)
        return
    for mirror, name, target in info["restore"]:
        dest = os.path.join(mirror, name)
        if not os.path.lexists(dest):
            os.symlink(target, dest)
    info["installed"] = True
    log(st, "installed %s %s (%d binaries back on PATH)" % (pkg, info["version"], len(info["restore"])))


def pacman(argv):
    d = os.environ["COLD_DIR"]
    st = load(d)
    pk = st["packages"]
    if argv[:1] == ["-Q"] and len(argv) == 2 and argv[1] in pk:
        if pk[argv[1]]["installed"]:
            print("%s %s" % (argv[1], pk[argv[1]]["version"]))
            return 0
        sys.stderr.write("error: package '%s' was not found\n" % argv[1])
        return 1
    if argv[:1] == ["-Sp"]:
        names = [x for x in argv[1:] if not x.startswith("-") and x != "%n %v"]
        if names and all(n in pk for n in names):
            todo = [n for n in names if not pk[n]["installed"]]
            log(st, "pacman -Sp --needed %s -> %s" % (" ".join(names), " ".join(todo) or "nothing"))
            if not todo:
                sys.stderr.write(" there is nothing to do\n")
                return 1
            for n in todo:
                print("%s %s" % (n, pk[n]["version"]))
            return 0
    os.execv(real("pacman"), ["pacman"] + argv)


def ufw_tuple(tokens):
    """`ufw allow from SRC to any port P proto X comment 'C'` or
    `ufw allow in on IFACE to any port P proto X comment 'C'` as the
    `### tuple ###` line ufw keeps."""
    if tokens[:2] != ["allow", "from"] and tokens[:3] != ["allow", "in", "on"]:
        return None
    proto = tokens[tokens.index("proto") + 1]
    port = tokens[tokens.index("port") + 1]
    comment = tokens[tokens.index("comment") + 1] if "comment" in tokens else ""
    if tokens[1] == "from":
        src, iface = tokens[2], "in"
    else:
        src, iface = "0.0.0.0/0", "in_" + tokens[3]
    return "### tuple ### allow %s %s 0.0.0.0/0 any %s %s comment=%s" % (proto, port, src, iface, comment.encode().hex())


def run_segment(st, seg):
    tokens = shlex.split(seg)
    for i, t in enumerate(tokens):
        if t.endswith("omarchy-pkg-add"):
            for pkg in tokens[i + 1:]:
                install(st, pkg)
            return True
    if tokens and tokens[0].endswith("/ufw"):
        line = ufw_tuple(tokens[1:])
        if not line:
            log(st, "REFUSED ufw %s" % " ".join(tokens[1:]))
            return False
        if line.split()[8:10] == ["0.0.0.0/0", "in"]:
            log(st, "REFUSED a rule open to everyone: %s" % line)
            return False
        with open(st["rules"], "a") as f:
            f.write(line + "\n")
        log(st, "ufw rule written: %s" % " ".join(tokens[1:]))
        return True
    if tokens[:2] == ["/usr/bin/systemctl", "enable"] or tokens[:1] == ["systemctl"]:
        log(st, "recorded, not run (the rig has no system bus): %s" % seg)
        return True
    log(st, "REFUSED %s" % seg)
    return False


def pkexec(argv):
    d = os.environ["COLD_DIR"]
    st = load(d)
    st["pkexec_calls"] += 1
    save(d, st)
    log(st, "PASSWORD #%d pkexec %s" % (st["pkexec_calls"], " ".join(shlex.quote(x) for x in argv)))
    inner = argv
    if inner[:1] == ["/usr/bin/env"]:
        inner = [x for x in inner[1:]]
        while inner and "=" in inner[0] and not inner[0].startswith("/"):
            inner = inner[1:]
    if inner[:2] == ["/bin/sh", "-c"]:
        segments = [s.strip() for s in inner[2].split(" && ")]
    else:
        segments = [" ".join(shlex.quote(x) for x in argv)]
    for seg in segments:
        st = load(d)
        ok = run_segment(st, seg)
        save(d, st)
        if not ok:
            return 1
    return 0


def status(a):
    st = load(a["dir"])
    print(json.dumps({"pkexec_calls": st["pkexec_calls"],
                      "installed": sorted(k for k, v in st["packages"].items() if v["installed"]),
                      "not_installed": sorted(k for k, v in st["packages"].items() if not v["installed"])}))


def main():
    cmd, rest = sys.argv[1], sys.argv[2:]
    if cmd == "pacman":
        sys.exit(pacman(rest))
    if cmd == "pkexec":
        sys.exit(pkexec(rest))
    a, it = {"ports": "1714:1764", "host_rules": "/etc/ufw/user.rules"}, iter(rest)
    for k in it:
        a[k.lstrip("-").replace("-", "_")] = next(it)
    {"build": build, "status": status}[cmd](a)


main()
