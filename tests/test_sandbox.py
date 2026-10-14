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

import os
import re
import subprocess
import unittest

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
                self.assertTrue(m.startswith("type=bind,src=$SB_RUN_DIR/"), m)
                self.assertTrue(m.endswith(",ro"), m)
        self.assertNotIn("--mount", self.run_cmd.replace('"${mounts[@]}"', ""))

    def test_devices_are_only_what_the_rig_needs(self):
        self.assertEqual(self.script.count("--device"), 2)
        self.assertIn('devices=(--device /dev/kvm --device "$node")', self.script)
        self.assertIn('[[ $step_name == tests ]] || unit_devices=("${devices[@]}")', self.script)
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
        self.assertIn("O_NOFOLLOW", self.script)
        self.assertIn("isreg()", self.script)
        self.assertNotIn("tar -x", self.script.split("read_result() {")[1].split("PY\n}")[0])

    def test_a_unit_runs_with_the_seccomp_profile_without_user_namespaces(self):
        self.assertIn('--security-opt "seccomp=$SB_RUN_DIR/seccomp.json"', self.run_cmd)
        self.assertIn("seccomp.py", self.script.split("make_seccomp() {")[1].split("}")[0])


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
        body = self.script.split("read_result() {")[1].split("PY\n}")[0]
        for name in ("results.tsv", "summary.json", "SKIPPED.txt"):
            self.assertIn(name, body)

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


class ReadResult(unittest.TestCase):
    def test_the_member_cap_counts_directories(self):
        with open(SANDBOX) as f:
            body = f.read().split("read_result() {")[1].split("PY\n}")[0]
        self.assertIn("members", body)


if __name__ == "__main__":
    unittest.main()
