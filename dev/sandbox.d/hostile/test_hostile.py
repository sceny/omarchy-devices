"""A hostile commit's test, written here for the sandbox's acceptance test.

It runs as a contributor's test would (python3 -m unittest discover -s tests),
tries to reach everything the sandbox promises to keep it from, and writes what
happened to /out/probe.json. `dev/sandbox hostile-test` reads that file as data.
It always passes: the host judges the evidence, not the commit.
"""
import ctypes
import errno
import hashlib
import json
import os
import socket
import stat
import sys
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
T = json.load(open(os.path.join(HERE, "..", "hostile_targets.json")))
OUT = "/out"
MODE = T.get("mode", "probe")


def try_connect(family, kind, addr, timeout=2.0):
    s = socket.socket(family, kind)
    s.settimeout(timeout)
    try:
        s.connect(addr)
        s.send(b"hostile\n")
        return "CONNECTED"
    except OSError as e:
        return errno.errorcode.get(e.errno, str(e)) if e.errno else type(e).__name__
    finally:
        s.close()


def status_field(name):
    for line in open("/proc/self/status"):
        if line.startswith(name + ":"):
            return line.split(":", 1)[1].strip()
    return ""


def write_fail(path):
    try:
        with open(path, "w") as f:
            f.write("x")
        os.unlink(path)
        return "WROTE"
    except OSError as e:
        return errno.errorcode.get(e.errno, str(e))


def probe():
    r = {}
    r["uid"] = os.getuid()
    r["uid_map"] = open("/proc/self/uid_map").read().split()
    r["gid_map"] = open("/proc/self/gid_map").read().split()
    r["cap_eff"] = status_field("CapEff")
    r["cap_bnd"] = status_field("CapBnd")
    r["no_new_privs"] = status_field("NoNewPrivs")
    r["seccomp"] = status_field("Seccomp")

    # The owner's files: by path, by name and by content, over the whole tree.
    r["canary_paths"] = {p: ("READABLE" if os.access(p, os.R_OK) else "NO") for p in T["canary_paths"]}
    r["home_listing"] = sorted(os.listdir(os.path.dirname(T["canary_paths"][0]))) if os.path.isdir(os.path.dirname(T["canary_paths"][0])) else "NO SUCH DIRECTORY"
    found = []
    skip = ("/proc", "/sys", "/dev", "/work", "/in")
    prefix = T["canary_prefix"].encode()
    name_prefix = T["canary_name_prefix"]
    content_roots = ("/home", "/tmp", "/var", "/run", "/etc", "/root", "/mnt", "/srv", "/media", "/out")
    for root, dirs, files in os.walk("/", followlinks=False):
        if root.startswith(skip):
            dirs[:] = []
            continue
        for f in files:
            p = os.path.join(root, f)
            if name_prefix in f:
                found.append(p)
                continue
            if not p.startswith(content_roots):
                continue
            try:
                if os.path.islink(p) or os.path.getsize(p) > 2_000_000:
                    continue
                with open(p, "rb") as fh:
                    if prefix in fh.read():
                        found.append(p)
            except OSError:
                pass
    r["canary_found_anywhere"] = found

    # The environment, this process's and every visible process's.
    bad = []
    for k, v in os.environ.items():
        if any(w in k.upper() for w in ("PAPERCLIP", "TOKEN", "SECRET", "GH_", "GITHUB", "SSH_", "DBUS", "WAYLAND", "HYPRLAND", "XDG_RUNTIME")):
            bad.append(k)
        if hashlib.sha256(v.encode()).hexdigest() == T["secret_sha256"]:
            bad.append("VALUE OF " + T["secret_name"])
    r["env_names"] = sorted(os.environ)
    r["env_leaks"] = bad
    leaks = []
    for pid in filter(str.isdigit, os.listdir("/proc")):
        try:
            data = open(f"/proc/{pid}/environ", "rb").read().split(b"\0")
        except OSError:
            continue
        for item in data:
            if b"PAPERCLIP" in item or T["secret_name"].encode() in item:
                leaks.append((pid, item.split(b"=")[0].decode(errors="replace")))
    r["process_env_leaks"] = leaks
    r["pids_visible"] = len([p for p in os.listdir("/proc") if p.isdigit()])

    # Network: nothing but a loopback of its own.
    r["interfaces"] = [l.split(":")[0].strip() for l in open("/proc/net/dev").read().splitlines()[2:]]
    net = {}
    net["internet_tcp_1.1.1.1:443"] = try_connect(socket.AF_INET, socket.SOCK_STREAM, ("1.1.1.1", 443))
    net["internet_tcp_8.8.8.8:53"] = try_connect(socket.AF_INET, socket.SOCK_STREAM, ("8.8.8.8", 53))
    net["internet_udp_8.8.8.8:53"] = try_connect(socket.AF_INET, socket.SOCK_DGRAM, ("8.8.8.8", 53))
    net["internet_tcp_ipv6"] = try_connect(socket.AF_INET6, socket.SOCK_STREAM, ("2606:4700:4700::1111", 443))
    try:
        socket.getaddrinfo("example.com", 443)
        net["dns_example.com"] = "RESOLVED"
    except OSError as e:
        net["dns_example.com"] = type(e).__name__
    if T.get("lan_gateway"):
        net["lan_gateway_tcp_80"] = try_connect(socket.AF_INET, socket.SOCK_STREAM, (T["lan_gateway"], 80))
    if T.get("lan_ip"):
        net["host_lan_listener"] = try_connect(socket.AF_INET, socket.SOCK_STREAM, (T["lan_ip"], T["lan_port"]))
    net["host_loopback_listener"] = try_connect(socket.AF_INET, socket.SOCK_STREAM, ("127.0.0.1", T["loopback_port"]))
    net["host_unix_listener"] = try_connect(socket.AF_UNIX, socket.SOCK_STREAM, T["unix_path"])
    net["host_abstract_listener"] = try_connect(socket.AF_UNIX, socket.SOCK_STREAM, "\0" + T["abstract_name"])
    for port in (5037, 1716, 1714, 22):
        net[f"loopback_{port}"] = try_connect(socket.AF_INET, socket.SOCK_STREAM, ("127.0.0.1", port))
    r["network"] = net

    # The owner's session: sockets and services that a process on the desktop reaches.
    paths = {}
    for p in T["host_paths"]:
        paths[p] = "EXISTS" if os.path.lexists(p) else "ABSENT"
    for base in ("/run/user", "/tmp/.X11-unix", "/tmp/hypr", "/var/run"):
        if os.path.isdir(base):
            paths["listing " + base] = sorted(os.listdir(base))
    r["host_paths"] = paths
    r["dev"] = sorted(os.listdir("/dev"))

    # Privilege: what a hostile process might try.
    libc = ctypes.CDLL(None, use_errno=True)
    mount = libc.mount(b"none", b"/mnt", b"tmpfs", 0, None)
    r["mount_tmpfs"] = "OK" if mount == 0 else errno.errorcode.get(ctypes.get_errno())
    r["setuid_0"] = "OK" if libc.setuid(0) == 0 else errno.errorcode.get(ctypes.get_errno())
    r["ptrace_init"] = "OK" if libc.ptrace(16, 1, 0, 0) == 0 else errno.errorcode.get(ctypes.get_errno())
    r["reboot"] = "OK" if libc.reboot(0x01234567) == 0 else errno.errorcode.get(ctypes.get_errno())
    r["write_outside"] = {p: write_fail(p) for p in ("/etc/sandbox-hostile", "/usr/bin/sandbox-hostile", "/opt/harness/dev/rig", "/in/src.tar", "/sys/kernel/sandbox-hostile", "/proc/sys/kernel/hostname", "/boot/x")}
    r["write_allowed"] = {p: write_fail(p + "/.hostile-write") for p in ("/tmp", "/out", "/work", "/home/sandbox")}
    r["mount_table_writable_roots"] = [
        l.split()[1] for l in open("/proc/self/mountinfo") if "rw," in l.split(" - ")[0] and l.split()[4].startswith("/") and l.split()[4] in ("/",)
    ]

    # The harness is develop's, not this commit's.
    rig = os.path.join(HERE, "..", "dev", "rig")
    r["harness_replaced_by_commit"] = os.path.exists(rig) and "HARNESS-FROM-THE-HOSTILE-COMMIT" in open(rig, errors="replace").read()

    # The output directory: what leaves is read as data.
    os.makedirs(OUT + "/probe", exist_ok=True)
    os.symlink("/etc/shadow", OUT + "/probe/evil-symlink")
    try:
        os.link("/work/src/hostile_targets.json", OUT + "/probe/evil-hardlink")
    except OSError:
        pass
    os.mkfifo(OUT + "/probe/evil-fifo")
    open(OUT + "/probe/" + "n" * 200, "w").write("long name")
    open(OUT + "/probe/has space", "w").write("space in the name")
    os.makedirs(OUT + "/probe/a/b/c/d/e/f/g/h/i/j/k/l/m/n", exist_ok=True)
    with open(OUT + "/probe/huge-sparse", "wb") as f:
        f.truncate(210 * 1024 * 1024)
    with open(OUT + "/probe/fine.txt", "w") as f:
        f.write("an ordinary result\n")
    r["tar_traversal_names"] = "see SKIPPED.txt"
    return r


def memory_bomb():
    chunks = []
    n = 0
    while True:
        chunks.append(bytearray(256 * 1024 * 1024))
        for i in range(0, len(chunks[-1]), 4096):
            chunks[-1][i] = 1
        n += 256
        open(OUT + "/mem-progress", "w").write(str(n))


def fork_bomb():
    count = 0
    pids = []
    try:
        while count < 20000:
            pid = os.fork()
            if pid == 0:
                import time
                time.sleep(30)
                os._exit(0)
            pids.append(pid)
            count += 1
    except OSError as e:
        res = {"forked": count, "stopped_by": errno.errorcode.get(e.errno, str(e))}
    else:
        res = {"forked": count, "stopped_by": "nothing"}
    for pid in pids:
        try:
            os.kill(pid, 9)
        except OSError:
            pass
    return res


def fill(path, limit_mb):
    n = 0
    stopped = "nothing"
    with open(path, "wb") as f:
        try:
            while n < limit_mb:
                f.write(b"\0" * (1 << 20))
                f.flush()
                n += 1
        except OSError as e:
            stopped = errno.errorcode.get(e.errno, str(e))
    os.unlink(path)
    return {"mb": n, "stopped_by": stopped}


class Hostile(unittest.TestCase):
    def test_hostile(self):
        if MODE == "probe":
            result = probe()
        elif MODE == "memory":
            memory_bomb()
            result = {}
        elif MODE == "processes":
            result = fork_bomb()
        elif MODE == "disk":
            result = {"out": fill(OUT + "/fill", 4000), "work": fill("/work/fill", 4000), "home": fill("/home/sandbox/fill", 4000), "var_tmp": fill("/var/tmp/fill", 4000)}
        elif MODE == "hang":
            import time
            open(OUT + "/hang-started", "w").write("1")
            time.sleep(100000)
            result = {}
        else:
            result = {"error": "unknown mode"}
        with open(OUT + "/probe.json", "w") as f:
            json.dump(result, f, indent=1, default=str)


if __name__ == "__main__":
    unittest.main()
