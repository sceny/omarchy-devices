"""dev/sandbox: what it refuses, and the isolation it must keep.

The sandbox runs a contributor's commit, so two things are held at the source
and not at the case that was reported:

1. Input. Only a full 40-hex sha of a commit of an allowed repository runs; a
   branch, a short sha, another repository or an unknown option is refused
   before anything is fetched or started.
2. The podman invocation. The flags that isolate the run are all present, and
   nothing that would open it is: no privilege, no host network, no host
   mount but the commit's read-only tar and the QA script, no environment
   passed through.

The hostile test (`dev/sandbox hostile-test`) proves the same from inside a
real container; this one runs in CI, where there is no podman.
"""

import importlib.util
import io
import json
import os
import re
import stat
import struct
import subprocess
import tarfile
import tempfile
import unittest
import zlib

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SANDBOX = os.path.join(ROOT, "dev", "sandbox")
GOOD_SHA = "a" * 40
REPO = "sceny/omarchy-devices"


def sandbox(*args):
    return subprocess.run(
        ["bash", SANDBOX, *args],
        capture_output=True,
        text=True,
        timeout=60,
        env={"PATH": os.environ.get("PATH", "/usr/bin:/bin"), "HOME": os.environ.get("HOME", "/nonexistent")},
    )


class Refusals(unittest.TestCase):
    def refused(self, *args, message):
        r = sandbox("run", *args)
        self.assertEqual(r.returncode, 2, r.stdout + r.stderr)
        self.assertIn(message, r.stderr)
        self.assertNotIn("starting the container", r.stderr)

    def test_a_repository_that_is_not_listed(self):
        self.refused("someone/else", GOOD_SHA, message="is not a repository this sandbox runs")

    def test_a_repository_that_only_looks_listed(self):
        self.refused("sceny/omarchy-devices-evil", GOOD_SHA, message="is not a repository this sandbox runs")
        self.refused("evil/sceny/omarchy-devices", GOOD_SHA, message="is not a repository this sandbox runs")

    def test_only_a_full_lowercase_sha(self):
        for ref in ("develop", "main", "HEAD", "a" * 7, "a" * 39, "a" * 41, "A" * 40, "g" * 40, "a" * 40 + "\n", "--help"):
            with self.subTest(ref=ref):
                r = sandbox("run", REPO, ref)
                self.assertEqual(r.returncode, 2, r.stdout + r.stderr)
                self.assertNotIn("starting the container", r.stderr)

    def test_unknown_option(self):
        self.refused(REPO, GOOD_SHA, "--privileged", message="unknown option")

    def test_a_third_argument(self):
        self.refused(REPO, GOOD_SHA, "extra", message="unexpected argument")

    def test_steps_are_a_known_list(self):
        for steps in ("shell", "tests,", "tests;rig", "tests rig", "$(id)", "Tests"):
            with self.subTest(steps=steps):
                r = sandbox("run", REPO, GOOD_SHA, "--steps", steps)
                self.assertEqual(r.returncode, 2, r.stdout + r.stderr)

    def test_harness_is_develop_or_pr(self):
        self.refused(REPO, GOOD_SHA, "--harness", "host", message="--harness is develop or pr")

    def test_timeout_is_whole_seconds(self):
        self.refused(REPO, GOOD_SHA, "--timeout", "5", message="at least 30")
        self.refused(REPO, GOOD_SHA, "--timeout", "1h", message="whole seconds")

    def test_the_script_step_needs_a_script(self):
        self.refused(REPO, GOOD_SHA, "--steps", "script", message="needs --script")
        self.refused(REPO, GOOD_SHA, "--script", "/nonexistent/qa.sh", message="not a readable file")

    def test_unknown_command(self):
        r = sandbox("shell")
        self.assertEqual(r.returncode, 2)
        self.assertIn("unknown command", r.stderr)


class Isolation(unittest.TestCase):
    """The text of the podman invocation in cmd_run."""

    @classmethod
    def setUpClass(cls):
        with open(SANDBOX) as f:
            text = f.read()
        start = text.index('--runroot "$SB_RUNTIME" run')
        end = text.index('"$SB_IMAGE" bash -c')
        cls.run_cmd = text[start:end]
        cls.script = text

    def test_flags_that_isolate_are_present(self):
        for flag in (
            "--network none",
            "--cap-drop all",
            "--security-opt no-new-privileges",
            "--read-only",
            "--uidmap 0:1:65536",
            "--gidmap 0:1:65536",
            "--user 1000:1000",
            "--pull never",
            "--memory",
            "--pids-limit",
            "--cpus",
            "--timeout",
            "--no-hosts",
        ):
            with self.subTest(flag=flag):
                self.assertIn(flag, self.run_cmd)

    def test_nothing_that_opens_the_container(self):
        for flag in (
            "--privileged",
            "--network host",
            "--network=host",
            "--pid host",
            "--pid=host",
            "--ipc host",
            "--userns host",
            "--userns=host",
            "--userns keep-id",
            "--cap-add",
            "seccomp=unconfined",
            "apparmor=unconfined",
            "--env-host",
            "--env-file",
            "--volume",
            " -v ",
            "--group-add",
            "--security-opt unmask",
        ):
            with self.subTest(flag=flag):
                self.assertNotIn(flag, self.run_cmd)

    def test_the_only_host_mounts_are_read_only(self):
        mounts = re.findall(r'--mount "([^"]+)"', self.script)
        self.assertTrue(mounts)
        for m in mounts:
            with self.subTest(mount=m):
                self.assertTrue(m.startswith(("type=bind,src=$SB_RUN_DIR/", "type=bind,src=$png,", "type=bind,src=$SB_DIR/sandbox.d/reencode.py,")), m)
                self.assertTrue(m.endswith(",ro"), m)
        self.assertNotIn("--mount", self.run_cmd.replace('"${mounts[@]}"', ""))

    def test_devices_are_only_what_the_rig_needs(self):
        self.assertEqual(self.script.count("--device"), 2)
        self.assertIn('devices=(--device /dev/kvm --device "$node")', self.script)
        self.assertIn('[[ $step_name == tests ]] || { unit_devices=("${devices[@]}")', self.script)
        self.assertIn('$node == /dev/dri/renderD*', self.script)
        self.assertNotIn("--device /dev/dri/card", self.script)

    def test_podman_runs_in_an_empty_environment(self):
        self.assertIn("env -i", self.script[self.script.index("timeout --signal=KILL $((timeout"):].split("podman")[0])
        self.assertIn("env -i PATH=/usr/bin:/usr/local/bin HOME", self.script.split("pm() {")[1].split("}")[0])

    def test_the_container_is_given_only_its_own_variables(self):
        env = re.findall(r'--env "?([A-Z_]+)=', self.run_cmd)
        self.assertEqual(sorted(env), ["HOME", "LANG", "SANDBOX_HARNESS", "SANDBOX_SHA", "SANDBOX_UNIT", "TERM"])

    def test_the_commit_enters_as_an_archive(self):
        self.assertIn("archive --format=tar", self.script)
        self.assertNotIn("git clone", self.script)
        self.assertNotIn("git checkout", self.script)

    def test_results_are_read_as_data(self):
        with open(READ_RESULT) as f:
            reader = f.read()
        self.assertIn("O_NOFOLLOW", reader)
        self.assertIn("isreg()", reader)
        self.assertNotIn("extractall", reader)
        self.assertIn("read_result.py", self.script.split("read_result() {")[1].split("\n}")[0])
        self.assertNotIn("tar -x", self.script.split("read_result() {")[1].split("\n}")[0])

    def test_the_picture_container_has_what_the_unit_container_has_and_less(self):
        text = self.script
        start = text.index("reencode_pngs() {")
        body = text[start : text.index("\n}\n", start)]
        for flag in ("--network none", "--cap-drop all", "--security-opt no-new-privileges", "--read-only", "--uidmap 0:1:65536",
                     "--user 1000:1000", "--pull never", "--memory", "--pids-limit", "--timeout", "--no-hosts", "env -i"):
            with self.subTest(flag=flag):
                self.assertIn(flag, body)
        for flag in ("--device", "--privileged", "--cap-add", "--env SANDBOX", "src.tar", "script.sh", "--network host"):
            with self.subTest(flag=flag):
                self.assertNotIn(flag, body)

    def test_the_results_go_where_git_and_shells_do_not_look(self):
        self.assertIn('out="$SB_STATE/results/', self.script)
        self.assertNotIn("sandbox-out", self.script.replace("# ", ""))
        self.assertIn("out_in_git", self.script.split("cmd_run() {")[1])

    def test_each_unit_has_a_directory_of_its_own_made_by_the_host(self):
        self.assertIn('mkdir -p -m 755 "$out/$unit"', self.script)
        self.assertIn('read_result "$tarfile" "$out/$unit" "$out" "$unit"', self.script)

    def test_the_tests_step_runs_with_the_seccomp_profile_without_user_namespaces(self):
        self.assertIn('seccomp=(--security-opt "seccomp=$SB_RUN_DIR/seccomp.json")', self.script)
        self.assertIn('"${seccomp[@]}"', self.run_cmd)
        self.assertIn("UNIT_NO_USERNS=1", self.script)
        self.assertNotIn("seccomp=unconfined", self.script)
        self.assertIn("seccomp.py", self.script.split("make_seccomp() {")[1].split("}")[0])


class XSockets(unittest.TestCase):
    """The rig step's compositor parent opens an X socket in the container's /tmp; a host's is never told from it by name."""

    HOSTILE = os.path.join(ROOT, "dev", "sandbox.d", "hostile")

    @classmethod
    def setUpClass(cls):
        with open(os.path.join(cls.HOSTILE, "test_hostile.py")) as f:
            src = f.read()
        funcs = [m.group(0) for m in re.finditer(r"^def (?:own_listening_sockets|x_socket_state)\(.*?(?=^def |\Z)", src, re.S | re.M)]
        cls.ns = {"os": os, "stat": stat}
        exec("\n\n".join(funcs), cls.ns)

    def test_a_listener_made_here_by_this_uid_is_the_rigs_own(self):
        import socket
        with tempfile.TemporaryDirectory(dir="/tmp") as d:
            path = os.path.join(d, "X0")
            srv = socket.socket(socket.AF_UNIX)
            srv.bind(path)
            srv.listen(1)
            try:
                self.assertEqual(self.ns["x_socket_state"](path, self.ns["own_listening_sockets"]()), "OWN-LISTENER")
            finally:
                srv.close()

    def test_a_file_or_a_dead_socket_at_the_path_is_not(self):
        import socket
        with tempfile.TemporaryDirectory(dir="/tmp") as d:
            plain = os.path.join(d, "X0")
            open(plain, "w").close()
            dead = os.path.join(d, "X1")
            srv = socket.socket(socket.AF_UNIX)
            srv.bind(dead)
            srv.close()
            listening = self.ns["own_listening_sockets"]()
            self.assertEqual(self.ns["x_socket_state"](plain, listening), "EXISTS")
            self.assertEqual(self.ns["x_socket_state"](dead, listening), "EXISTS")
            self.assertEqual(self.ns["x_socket_state"](os.path.join(d, "X2"), listening), "ABSENT")

    def judge(self, kind, host_paths, x_sockets):
        probe = {
            "canary_paths": {}, "canary_found_anywhere": [], "canary_search_control": True,
            "home_listing": "NO SUCH DIRECTORY", "uid": 1000, "uid_map": ["0", "1", "65536"],
            "cap_eff": "0", "cap_bnd": "0", "no_new_privs": "1", "seccomp": "2", "env_leaks": [],
            "process_env_leaks": [], "interfaces": ["lo"], "network": {},
            "host_paths": host_paths, "x_sockets": x_sockets, "dev": [], "mount_tmpfs": "EPERM",
            "setuid_0": "EPERM", "ptrace_init": "EPERM", "reboot": "EPERM", "userns": {},
            "write_outside": {}, "write_allowed": {}, "harness_replaced_by_commit": False,
        }
        with tempfile.TemporaryDirectory() as work:
            out = os.path.join(work, "out")
            unit = os.path.join(out, "script" if kind == "probe-rig" else "unit-bridge")
            os.makedirs(unit)
            for path, data in ((os.path.join(unit, "probe.json"), probe), (os.path.join(out, "summary.json"), {}),
                               (os.path.join(work, "targets.json"), {})):
                with open(path, "w") as f:
                    json.dump(data, f)
            r = subprocess.run(["python3", os.path.join(self.HOSTILE, "judge.py"), work, kind, out],
                               capture_output=True, text=True, timeout=30)
        self.assertEqual(r.returncode, 0, r.stderr)
        verdicts = {}
        for line in r.stdout.splitlines():
            f = line.split("\t")
            if f[0] in ("PASS", "FAIL") and ("X socket" in f[1] or "session bus" in f[1]):
                verdicts[f[1][:24]] = f[0]
        return verdicts

    def test_the_rig_step_passes_with_its_own_x_socket_only(self):
        v = self.judge("probe-rig", {"/tmp/.X11-unix/X0": "OWN-LISTENER", "listing /tmp/.X11-unix": ["X0"]},
                       {"X0": "OWN-LISTENER"})
        self.assertEqual(set(v.values()), {"PASS"}, v)
        self.assertEqual(len(v), 2, v)

    def test_the_rig_step_fails_on_an_x_socket_that_is_not_its_own(self):
        v = self.judge("probe-rig", {"/tmp/.X11-unix/X0": "OWN-LISTENER", "/tmp/.X11-unix/X1": "EXISTS"},
                       {"X0": "OWN-LISTENER", "X1": "EXISTS"})
        self.assertEqual(set(v.values()), {"FAIL"}, v)
        v = self.judge("probe-rig", {"/tmp/.X11-unix/X0": "EXISTS"}, {"X0": "EXISTS"})
        self.assertIn("FAIL", v.values())

    def test_the_tests_step_fails_on_any_x_socket(self):
        v = self.judge("probe", {"/tmp/.X11-unix/X0": "OWN-LISTENER"}, {"X0": "OWN-LISTENER"})
        self.assertEqual(set(v.values()), {"FAIL"}, v)
        self.assertEqual(len(v), 2, v)


class Verdict(unittest.TestCase):
    """The host takes the verdict; the container's streams are capped on the way."""

    @classmethod
    def setUpClass(cls):
        with open(SANDBOX) as f:
            cls.script = f.read()

    def test_stdout_is_cut_by_head_at_the_cap(self):
        self.assertIn("head -c $((SB_MAX_RESULT + 1))", self.script)

    def test_stderr_goes_through_the_filter(self):
        self.assertIn("2>&1 1>&4 | python3 \"$SB_DIR/sandbox.d/filter-stderr.py\" >&2", self.script)

    def test_the_exit_code_is_podmans_and_not_a_file_from_the_container(self):
        self.assertIn('PIPESTATUS[0]', self.script)
        self.assertIn("{{.State.ExitCode}}", self.script)
        with open(os.path.join(ROOT, "dev", "sandbox.d", "inside.sh")) as f:
            inside = f.read()
        self.assertNotIn("results.tsv", inside.replace("# ", ""))
        self.assertNotIn("summary.json", inside.replace("# ", ""))

    def test_the_host_writes_the_verdict_files(self):
        body = self.script.split("write_verdict() {")[1].split("PY\n}")[0]
        self.assertIn("results.tsv", body)
        self.assertIn("summary.json", body)

    def test_a_result_cannot_replace_the_verdict_files(self):
        # the verdict files are in the run's directory; a unit's files go one level down
        body = self.script.split("write_verdict() {")[1].split("PY\n}")[0]
        self.assertIn("os.path.join(out, 'results.tsv')", body)
        self.assertIn('"$out/$unit"', self.script)

    def test_the_member_count_is_capped(self):
        self.assertIn("SB_MAX_MEMBERS=20000", self.script)

    def test_the_result_cap_must_be_a_number(self):
        r = subprocess.run(
            ["bash", SANDBOX, "build"],
            capture_output=True,
            text=True,
            timeout=60,
            env={"PATH": os.environ.get("PATH", "/usr/bin:/bin"), "HOME": os.environ.get("HOME", "/nonexistent"), "SANDBOX_MAX_RESULT": "$(id)"},
        )
        self.assertNotEqual(r.returncode, 0)


FILTER = os.path.join(ROOT, "dev", "sandbox.d", "filter-stderr.py")
SECCOMP = os.path.join(ROOT, "dev", "sandbox.d", "seccomp.py")


def filtered(data):
    return subprocess.run(["python3", FILTER], input=data, capture_output=True, timeout=60).stdout


class StderrFilter(unittest.TestCase):
    def test_control_bytes_are_dropped_and_text_stays(self):
        out = filtered("\x1b]0;title\x07\x1b[2Jtext\roverwrite\u009b\u202e\x00\nnext\tline\n".encode())
        text = out.decode()
        for c in ("\x1b", "\x07", "\r", "\u009b", "\u202e", "\x00"):
            self.assertNotIn(c, text)
        self.assertIn("text", text)
        self.assertIn("next\tline", text)

    def test_a_long_line_is_cut(self):
        out = filtered(b"A" * 100000 + b"\nshort\n")
        longest = max(len(l) for l in out.split(b"\n"))
        self.assertLess(longest, 4200)
        self.assertIn(b"short", out)

    def test_a_flood_is_cut_at_the_total(self):
        data = (b"A" * 99 + b"\n") * (200 * 1024) + b"AFTER\n"
        out = filtered(data)
        self.assertLessEqual(len(out), 16 * 1024 * 1024 + 100)
        self.assertIn(b"[further output dropped]", out)
        self.assertNotIn(b"AFTER", out)

    def test_a_flood_without_a_newline_is_one_short_line(self):
        out = filtered(b"A" * (20 * 1024 * 1024) + b"\nAFTER\n")
        self.assertLess(len(out), 5000)
        self.assertIn(b"AFTER", out)

    def test_a_multibyte_character_split_across_reads_survives(self):
        out = filtered(("é" * 70000 + "\n").encode())
        self.assertNotIn("\ufffd", out.decode())


class Seccomp(unittest.TestCase):
    def profile(self, *rules):
        import importlib.util

        spec = importlib.util.spec_from_file_location("seccomp", SECCOMP)
        mod = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(mod)
        base = {"defaultAction": "SCMP_ACT_ERRNO", "syscalls": list(rules)}
        return mod, mod.without_new_user_namespaces(base)

    def names(self, profile, action):
        return [n for r in profile["syscalls"] if r["action"] == action and "args" not in r for n in r["names"]]

    def test_clone_and_unshare_are_allowed_only_without_the_user_namespace_flag(self):
        import platform

        if platform.machine() != "x86_64":
            self.skipTest("written for x86_64")
        _, p = self.profile({"names": ["read", "clone", "clone3", "unshare"], "action": "SCMP_ACT_ALLOW"})
        self.assertEqual(self.names(p, "SCMP_ACT_ALLOW"), ["read"])
        conditional = [r for r in p["syscalls"] if "args" in r]
        self.assertEqual(len(conditional), 1)
        self.assertEqual(sorted(conditional[0]["names"]), ["clone", "unshare"])
        arg = conditional[0]["args"][0]
        self.assertEqual((arg["index"], arg["value"], arg["valueTwo"], arg["op"]), (0, 0x10000000, 0, "SCMP_CMP_MASKED_EQ"))
        self.assertEqual([r for r in p["syscalls"] if r["names"] == ["clone3"]][0]["errnoRet"], 38)

    def test_the_real_default_profile_keeps_no_unconditional_clone(self):
        import platform

        path = "/usr/share/containers/seccomp.json"
        if platform.machine() != "x86_64" or not os.path.exists(path):
            self.skipTest("no default profile here")
        import json

        mod, _ = self.profile()
        with open(path) as f:
            p = mod.without_new_user_namespaces(json.load(f))
        for r in p["syscalls"]:
            if r["action"] == "SCMP_ACT_ALLOW" and "args" not in r:
                self.assertFalse(set(r["names"]) & {"clone", "clone3", "unshare"}, r["names"])


READ_RESULT = os.path.join(ROOT, "dev", "sandbox.d", "read_result.py")
REENCODE = os.path.join(ROOT, "dev", "sandbox.d", "reencode.py")


def tar_of(members):
    """members: name -> bytes (a file), None (a directory), ("link", target), or ("fifo",)."""
    buf = io.BytesIO()
    with tarfile.open(fileobj=buf, mode="w") as t:
        for name, what in members.items():
            info = tarfile.TarInfo(name)
            if what is None:
                info.type = tarfile.DIRTYPE
                info.mode = 0o755
                t.addfile(info)
            elif isinstance(what, tuple) and what[0] == "link":
                info.type = tarfile.SYMTYPE
                info.linkname = what[1]
                t.addfile(info)
            elif isinstance(what, tuple) and what[0] == "fifo":
                info.type = tarfile.FIFOTYPE
                t.addfile(info)
            else:
                info.size = len(what)
                t.addfile(info, io.BytesIO(what))
    return buf.getvalue()


def png(width, height, text=None):
    def chunk(kind, body):
        return struct.pack(">I", len(body)) + kind + body + struct.pack(">I", zlib.crc32(kind + body) & 0xFFFFFFFF)

    raw = zlib.compress(b"".join(b"\x00" + b"\x10\x20\x30" * width for _ in range(height)))
    out = b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 2, 0, 0, 0))
    if text:
        out += chunk(b"tEXt", text)
    return out + chunk(b"IDAT", raw) + chunk(b"IEND", b"")


class ReadResult(unittest.TestCase):
    """read_result.py on tars a hostile unit could send."""

    def read(self, members, *extra, label="unit-bridge", limit=1 << 30, max_members=20000):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        root = os.path.join(self.tmp.name, "out")
        dest = os.path.join(root, label)
        os.makedirs(dest)
        archive = os.path.join(self.tmp.name, "r.tar")
        with open(archive, "wb") as f:
            f.write(tar_of(members) if isinstance(members, dict) else members)
        r = subprocess.run(["python3", READ_RESULT, archive, dest, root, label, str(limit), str(max_members), *extra],
                           capture_output=True, text=True, timeout=60)
        skipped = os.path.join(root, "SKIPPED.txt")
        self.skipped = ""
        if os.path.exists(skipped):
            with open(skipped) as f:
                self.skipped = f.read()
        self.root, self.dest = root, dest
        return r

    def on_disk(self):
        found = []
        for r, dirs, files in os.walk(self.dest):
            found += [os.path.relpath(os.path.join(r, n), self.dest) for n in dirs + files]
        return sorted(found)

    def test_an_ordinary_tree_arrives(self):
        r = self.read({"./": None, "./logs": None, "./logs/unit.log": b"ok\n", "./notes/a.txt": b"x"})
        self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
        with open(os.path.join(self.dest, "logs", "unit.log"), "rb") as f:
            self.assertEqual(f.read(), b"ok\n")
        self.assertTrue(os.path.isfile(os.path.join(self.dest, "notes", "a.txt")))
        self.assertEqual(self.skipped, "")

    def test_a_result_tree_never_holds_what_git_a_shell_or_an_agent_acts_on(self):
        hostile = {
            ".git/config": b"[core]\n\tfsmonitor = touch /tmp/x\n", ".git/HEAD": b"ref: refs/heads/main\n", ".git": None,
            ".envrc": b"x", "CLAUDE.md": b"x", "claude.MD": b"x", "Agents.md": b"x", "GEMINI.md": b"x", ".claude/settings.json": b"{}",
            "mise.toml": b"x", ".tool-versions": b"x", "conftest.py": b"x", "HEAD": b"ref: refs/heads/main\n", "objects/x": b"x",
            "refs/x": b"x", "sub/.hidden": b"x", "-rf": b"x", "_underscore": b"x", "fine/ok.txt": b"ok",
        }
        self.read(hostile)
        self.assertEqual(self.on_disk(), ["fine", "fine/ok.txt"])
        for name in (".git/config", ".envrc", "CLAUDE.md", "claude.MD", "Agents.md", "GEMINI.md", ".claude/settings.json", "mise.toml",
                     ".tool-versions", "conftest.py", "refs/x", "objects/x", "sub/.hidden", "-rf"):
            self.assertIn(name, self.skipped)
        env = {"PATH": os.environ.get("PATH", "/usr/bin"), "GIT_CEILING_DIRECTORIES": self.tmp.name}
        for d in (self.root, self.dest):
            self.assertNotEqual(subprocess.run(["git", "-C", d, "rev-parse", "--git-dir"], capture_output=True, env=env).returncode, 0)

    def test_no_name_starts_with_anything_but_a_letter_or_digit(self):
        self.read({"-a": b"x", ".a": b"x", "_a": b"x", "@a": b"x", "a/-b": b"x", "a1": b"x"})
        self.assertEqual(self.on_disk(), ["a1"])

    def test_skipped_lists_a_names_as_escaped_text(self):
        self.read({"evil\x1b]0;OSC-TITLE\x07name": b"x", "bell\x07": b"x", "bidi\u202e": b"x", "carriage\rreturn": b"x"})
        self.assertNotRegex(self.skipped, "[\x00-\x08\x0b-\x1f\x7f\u202e]")
        self.assertIn("\\x1b]0;OSC-TITLE\\x07name", self.skipped)
        self.assertIn("unit-bridge: ", self.skipped)

    def test_only_regular_files_and_directories(self):
        self.read({"link": ("link", "/etc/passwd"), "fifo": ("fifo",), "dir/": None, "dir/file": b"x"})
        self.assertEqual(self.on_disk(), ["dir", "dir/file"])
        self.assertIn("'link'", self.skipped)
        self.assertIn("'fifo'", self.skipped)

    def test_the_member_cap_counts_directories_and_stops_the_read(self):
        r = self.read({f"d{i}/": None for i in range(50)}, max_members=20)
        self.assertEqual(r.returncode, 4)
        self.assertLessEqual(len(self.on_disk()), 20)
        self.assertIn("more than 20 members", self.skipped)

    def test_a_file_over_the_limit_is_not_written(self):
        self.read({"big": b"x" * 1000, "small": b"x"}, limit=500)
        self.assertEqual(self.on_disk(), ["small"])
        self.assertIn("too large", self.skipped)

    def test_a_cut_archive_is_reported(self):
        data = tar_of({"a": b"x" * 4000, "b": b"y" * 4000})
        r = self.read(data[:6500])
        self.assertEqual(r.returncode, 3)
        self.assertIn("stops early", self.skipped)

    def test_nothing_that_is_not_a_tar_is_read(self):
        r = self.read(b"not a tar at all")
        self.assertEqual(r.returncode, 3)
        self.assertEqual(self.on_disk(), [])

    def test_a_png_goes_to_the_quarantine_and_other_images_are_refused(self):
        quarantine = tempfile.mkdtemp()
        self.addCleanup(subprocess.run, ["rm", "-rf", quarantine])
        self.read({"shots/a.png": png(2, 2), "shots/b.JPG": b"\xff\xd8", "shots/c.svg": b"<svg/>", "shots/d.gif": b"GIF89a", "e.txt": b"x"},
                  "--png-dir", quarantine)
        self.assertEqual(self.on_disk(), ["e.txt"])
        self.assertTrue(os.path.isfile(os.path.join(quarantine, "shots", "a.png")))
        for name in ("b.JPG", "c.svg", "d.gif"):
            self.assertIn(name, self.skipped)

    def test_a_png_with_nowhere_to_be_re_encoded_is_dropped(self):
        self.read({"a.png": png(2, 2)})
        self.assertEqual(self.on_disk(), [])
        self.assertIn("nowhere to be re-encoded", self.skipped)

    def test_a_picture_that_does_not_come_back_from_the_re_encode_is_listed(self):
        sent = os.path.join(tempfile.mkdtemp(), "sent")
        os.makedirs(os.path.join(sent, "shots"))
        for n in ("good.png", "bad.png"):
            with open(os.path.join(sent, "shots", n), "wb") as f:
                f.write(b"x")
        self.read({"shots/good.png": png(2, 2), "shots/notes.txt": b"x", "shots/ghost.jpg": b"x"}, "--only-png", "--expect", sent)
        self.assertEqual(self.on_disk(), ["shots", "shots/good.png"])
        self.assertIn("'shots/bad.png'", self.skipped)
        self.assertNotIn("good.png", self.skipped)

    def test_a_re_encoded_picture_is_checked_again_and_keeps_image_chunks_only(self):
        good = png(2, 2, b"Comment\x00HOSTILE-TEXT")
        bad_crc = good[:-5] + b"\x01" + good[-4:]
        bomb = png(30000, 30000)
        trailing = png(2, 2) + b"extra"
        self.read({"ok.png": good, "crc.png": bad_crc, "bomb.png": bomb, "trail.png": trailing, "nothing.png": b"\x89PNG\r\n\x1a\n"},
                  "--only-png")
        self.assertEqual(self.on_disk(), ["ok.png"])
        with open(os.path.join(self.dest, "ok.png"), "rb") as f:
            data = f.read()
        self.assertNotIn(b"HOSTILE-TEXT", data)
        self.assertTrue(data.startswith(b"\x89PNG") and data.endswith(b"IEND\xaeB`\x82"))
        for name in ("crc.png", "bomb.png", "trail.png", "nothing.png"):
            self.assertIn(name, self.skipped)

    def test_mise_and_codex_instruction_names_are_refused(self):
        self.read({"mise/config.toml": b"x", "AGENTS.override.md": b"x", "mise.dev.toml": b"x", "fine/ok.txt": b"ok"})
        self.assertEqual(self.on_disk(), ["fine", "fine/ok.txt"])


class OutputPlace(unittest.TestCase):
    def test_a_git_directory_is_found_from_the_nearest_existing_ancestor(self):
        with open(SANDBOX) as f:
            text = f.read()
        func = "out_in_git() {" + text.split("out_in_git() {")[1].split("\n}\n")[0] + "\n}\n"
        with tempfile.TemporaryDirectory() as tmp:
            work = os.path.join(tmp, "work")
            bare = os.path.join(tmp, "bare")
            plain = os.path.join(tmp, "plain")
            for d in (work, bare, plain):
                os.makedirs(d)
            env = {"PATH": os.environ.get("PATH", "/usr/bin"), "GIT_CEILING_DIRECTORIES": tmp, "HOME": tmp}
            subprocess.run(["git", "init", "-q", work], check=True, env=env)
            os.makedirs(os.path.join(bare, "objects"))
            os.makedirs(os.path.join(bare, "refs"))
            with open(os.path.join(bare, "HEAD"), "w") as f:
                f.write("ref: refs/heads/main\n")

            def inside(path):
                r = subprocess.run(["bash", "-c", func + f'SB_HOME={tmp}; out_in_git "$1"', "x", path], env=env, capture_output=True)
                return r.returncode == 0

            self.assertTrue(inside(os.path.join(work, "results", "run")))
            self.assertTrue(inside(os.path.join(work, ".git")))
            self.assertTrue(inside(os.path.join(bare, "sub", "run")))
            self.assertFalse(inside(os.path.join(plain, "results", "run")))


class Reencode(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        spec = importlib.util.spec_from_file_location("reencode", REENCODE)
        try:
            cls.mod = importlib.util.module_from_spec(spec)
            spec.loader.exec_module(cls.mod)
        except (ImportError, ValueError) as e:
            raise unittest.SkipTest(f"no GdkPixbuf here: {e}")

    def write(self, data):
        d = tempfile.mkdtemp()
        path = os.path.join(d, "a.png")
        with open(path, "wb") as f:
            f.write(data)
        return path

    def test_the_header_limits_come_before_any_decoding(self):
        self.assertEqual(self.mod.decode(self.write(png(30000, 1)[:60]), "/nonexistent/x.png"), "picture too large (30000x1)")
        self.assertEqual(self.mod.decode(self.write(b"GIF89a" + b"\0" * 40), "/nonexistent/x.png"), "not a PNG")
        self.assertEqual(self.mod.decode(self.write(png(8000, 8000)[:60]), "/nonexistent/x.png"), "picture too large (8000x8000)")

    def test_a_good_picture_comes_back_without_its_text(self):
        out = os.path.join(tempfile.mkdtemp(), "b.png")
        self.assertIsNone(self.mod.decode(self.write(png(4, 4, b"Comment\x00HOSTILE-TEXT")), out))
        with open(out, "rb") as f:
            data = f.read()
        self.assertTrue(data.startswith(b"\x89PNG"))
        self.assertNotIn(b"HOSTILE-TEXT", data)


if __name__ == "__main__":
    unittest.main()
