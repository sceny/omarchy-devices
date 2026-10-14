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
        text = open(SANDBOX).read()
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
        self.assertIn('$node == /dev/dri/renderD*', self.script)
        self.assertNotIn("--device /dev/dri/card", self.script)

    def test_podman_runs_in_an_empty_environment(self):
        self.assertIn("env -i", self.script[self.script.index("timeout --signal=KILL"):].split("podman")[0])
        self.assertIn("env -i PATH=/usr/bin:/usr/local/bin HOME", self.script.split("pm() {")[1].split("}")[0])

    def test_the_container_is_given_only_its_own_variables(self):
        env = re.findall(r'--env "?([A-Z_]+)=', self.run_cmd)
        self.assertEqual(
            sorted(env), ["HOME", "LANG", "SANDBOX_HARNESS", "SANDBOX_SHA", "SANDBOX_STEPS", "TERM"]
        )

    def test_the_commit_enters_as_an_archive(self):
        self.assertIn("archive --format=tar", self.script)
        self.assertNotIn("git clone", self.script)
        self.assertNotIn("git checkout", self.script)

    def test_results_are_read_as_data(self):
        self.assertIn("O_NOFOLLOW", self.script)
        self.assertIn("isreg()", self.script)
        self.assertNotIn("tar -x", self.script.split("read_result() {")[1].split("PY\n}")[0])


if __name__ == "__main__":
    unittest.main()
