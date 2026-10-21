"""dev/sandbox.d/hostile.sh and judge.py: how the hostile test stops and what it judges.

The hostile test itself runs in a real container (`dev/sandbox hostile-test`),
where CI has no podman. These cases run its functions with the sandbox's
helpers stubbed, and the judge as the test runs it, so each fault fails here:
an interrupt that let the run go on, a step that ran with its work directory
gone, a canary check that passed on nothing, a judge that passed without
evidence, and a final check that counted another run's leftovers as its own.
"""

import json
import os
import re
import signal
import subprocess
import tempfile
import unittest

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
HOSTILE = os.path.join(ROOT, "dev", "sandbox.d", "hostile.sh")
JUDGE = os.path.join(ROOT, "dev", "sandbox.d", "hostile", "judge.py")

STUBS = """
say() { :; }
step() { :; }
ok() { :; }
warn() { :; }
fail() { printf 'FAIL %s\\n' "$*"; }
die() { fail "$*"; exit 2; }
"""


def bash(body):
    # The script goes in on stdin: its text must not show in this shell's command
    # line, where a pgrep for the test's names would find it. Its own session
    # lets a timeout stop what it started in the background too.
    script = STUBS + f'source "{HOSTILE}"\n' + body
    proc = subprocess.Popen(
        ["bash"],
        stdin=subprocess.PIPE,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        start_new_session=True,
        env={"PATH": os.environ.get("PATH", "/usr/bin:/bin"), "HOME": "/nonexistent"},
    )
    try:
        out, err = proc.communicate(script, timeout=60)
    except subprocess.TimeoutExpired:
        os.killpg(proc.pid, signal.SIGKILL)
        proc.communicate()
        raise
    return subprocess.CompletedProcess(proc.args, proc.returncode, out, err)


def hostile_source():
    with open(HOSTILE) as f:
        return f.read()


class Interrupt(unittest.TestCase):
    def test_an_interrupt_stops_the_run_after_its_cleanup(self):
        src = hostile_source()
        interrupt = re.search(r"^\s*(trap '[^']*' INT TERM HUP)\s*$", src, re.M)
        exit_trap = re.search(r"^\s*(trap '[^']*' EXIT)\s*$", src, re.M)
        self.assertTrue(interrupt and exit_trap, "cmd_hostile_test sets no EXIT trap and no INT TERM HUP trap")
        with tempfile.TemporaryDirectory() as state:
            work = os.path.join(state, "hostile", "sceny-hostile.test")
            os.makedirs(work)
            r = bash(
                f'SB_STATE="{state}"\nHOSTILE_WORK="{work}"\n'
                f"{exit_trap.group(1)}\n{interrupt.group(1)}\n"
                "kill -INT $$\necho CONTINUED\n"
            )
            self.assertNotIn("CONTINUED", r.stdout)
            self.assertEqual(r.returncode, 130, r.stdout + r.stderr)
            self.assertFalse(os.path.exists(work))


class WorkDirectory(unittest.TestCase):
    def test_a_step_stops_when_its_work_directory_is_gone(self):
        calls = [
            "hostile_listeners",
            "hostile_commit /nowhere probe",
            "hostile_run probe probe --steps tests",
            "hostile_sample_start",
            "hostile_out_dir",
            "hostile_dev devices",
        ]
        for call in calls:
            with self.subTest(step=call):
                r = bash(f'HOSTILE_WORK=""\n{call}\necho CONTINUED\n')
                self.assertNotIn("CONTINUED", r.stdout)
                self.assertNotEqual(r.returncode, 0)


class Canaries(unittest.TestCase):
    def intact(self, paths):
        arr = " ".join(f'"{p}"' for p in paths)
        r = bash(f"HOSTILE_CANARIES=({arr})\nhostile_canaries_intact abc123\necho RC=$?\n")
        return r.stdout.strip().splitlines()[-1]

    def test_three_canaries_with_their_text_are_intact(self):
        with tempfile.TemporaryDirectory() as d:
            paths = [os.path.join(d, n) for n in "abc"]
            for p in paths:
                with open(p, "w") as f:
                    f.write("SANDBOX-CANARY-abc123\n")
            self.assertEqual(self.intact(paths), "RC=0")

    def test_no_canary_planted_is_not_intact(self):
        self.assertEqual(self.intact([]), "RC=1")

    def test_a_missing_canary_is_not_intact(self):
        with tempfile.TemporaryDirectory() as d:
            paths = [os.path.join(d, n) for n in "ab"]
            for p in paths:
                with open(p, "w") as f:
                    f.write("SANDBOX-CANARY-abc123\n")
            self.assertEqual(self.intact(paths), "RC=1")

    def test_a_changed_canary_is_not_intact(self):
        with tempfile.TemporaryDirectory() as d:
            paths = [os.path.join(d, n) for n in "abc"]
            for p in paths:
                with open(p, "w") as f:
                    f.write("SANDBOX-CANARY-abc123\n")
            with open(paths[1], "w") as f:
                f.write("changed\n")
            self.assertEqual(self.intact(paths), "RC=1")


class Leftovers(unittest.TestCase):
    """The final check judges only the runs and sessions this test started."""

    def left(self, ids, devs, listing, runs=(), work_exists=False):
        with tempfile.TemporaryDirectory() as state:
            for run in runs:
                os.makedirs(os.path.join(state, "runs", run))
            work = os.path.join(state, "work")
            if work_exists:
                os.makedirs(work)
            body = (
                f'SB_STATE="{state}"\nSB_UID="{os.getuid()}"\n'
                f"FAKE_PS='{listing}'\n"
                "pm() { printf '%s\\n' \"$FAKE_PS\"; }\n"
                f"HOSTILE_RUN_IDS=({' '.join(ids)})\n"
                f"HOSTILE_DEV_NAMES=({' '.join(devs)})\n"
                f'hostile_left "{work}"\necho RC=$?\n'
            )
            return bash(body).stdout.strip().splitlines()[-1]

    def test_a_live_session_of_another_run_is_not_this_tests_leftover(self):
        self.assertEqual(
            self.left(["aaaaaaaa"], ["sceny-sandbox-dev-cccccccc"], "sceny-sandbox-dev-bbbbbbbb"),
            "RC=0",
        )

    def test_another_runs_directory_is_not_this_tests_leftover(self):
        self.assertEqual(self.left(["aaaaaaaa"], [], "", runs=["bbbbbbbb"]), "RC=0")

    def test_nothing_left_passes(self):
        self.assertEqual(self.left(["aaaaaaaa"], ["sceny-sandbox-dev-cccccccc"], ""), "RC=0")

    def test_its_own_container_is_a_leftover(self):
        self.assertEqual(self.left(["aaaaaaaa"], [], "sceny-sandbox-aaaaaaaa"), "RC=1")

    def test_its_own_run_directory_is_a_leftover(self):
        self.assertEqual(self.left(["aaaaaaaa"], [], "", runs=["aaaaaaaa"]), "RC=1")

    def test_its_own_dev_session_is_a_leftover(self):
        self.assertEqual(
            self.left([], ["sceny-sandbox-dev-cccccccc"], "sceny-sandbox-dev-cccccccc"), "RC=1"
        )

    def test_its_own_work_directory_is_a_leftover(self):
        self.assertEqual(self.left([], [], "", work_exists=True), "RC=1")


class RunVerdicts(unittest.TestCase):
    def run_with_judge(self, judge_lines):
        with tempfile.TemporaryDirectory() as sbdir, tempfile.TemporaryDirectory() as work:
            os.makedirs(os.path.join(sbdir, "sandbox.d", "hostile"))
            with open(os.path.join(sbdir, "sandbox.d", "hostile", "judge.py"), "w") as f:
                f.write(f"import sys\nsys.stdout.write({judge_lines!r})\n")
            with open(os.path.join(work, "sha-probe"), "w") as f:
                f.write("deadbeef" * 5 + "\n")
            body = (
                f'SB_DIR="{sbdir}"\nHOSTILE_WORK="{work}"\n'
                "cmd_run() { echo '==> sandbox run abcdef12: repo'; }\n"
                "hostile_run probe probe --steps tests\n"
                'echo "FAILS=$HOSTILE_FAIL IDS=${HOSTILE_RUN_IDS[*]}"\n'
            )
            return bash(body).stdout.strip().splitlines()[-1]

    def test_a_judge_that_writes_no_verdict_fails_the_step(self):
        self.assertEqual(self.run_with_judge(""), "FAILS=1 IDS=abcdef12")

    def test_a_judge_that_passes_fails_nothing_and_the_run_is_kept(self):
        self.assertEqual(self.run_with_judge("PASS\tsomething held\n"), "FAILS=0 IDS=abcdef12")


class Judge(unittest.TestCase):
    def judge(self, kind, summary, extra=None):
        with tempfile.TemporaryDirectory() as work:
            out = os.path.join(work, "out")
            os.makedirs(os.path.join(out, "unit-bridge"))
            with open(os.path.join(work, "targets.json"), "w") as f:
                json.dump({}, f)
            with open(os.path.join(out, "summary.json"), "w") as f:
                json.dump(summary, f)
            for name, text in (extra or {}).items():
                with open(os.path.join(out, "unit-bridge", name), "w") as f:
                    f.write(text)
            r = subprocess.run(["python3", JUDGE, work, kind, out], capture_output=True, text=True, timeout=60)
            return r.stdout.splitlines()

    def verdict(self, lines, prefix):
        return [l for l in lines if l.startswith(prefix)]

    def test_memory_with_no_progress_written_fails(self):
        lines = self.judge("memory", {"oom_killed": False})
        self.assertTrue(self.verdict(lines, "FAIL"), lines)

    def test_memory_allocated_past_the_limit_fails(self):
        lines = self.judge("memory", {"oom_killed": False}, {"mem-progress": "5000"})
        self.assertTrue(self.verdict(lines, "FAIL"), lines)

    def test_memory_stopped_at_the_limit_passes(self):
        lines = self.judge("memory", {"oom_killed": False}, {"mem-progress": "900"})
        self.assertFalse(self.verdict(lines, "FAIL"), lines)

    def test_memory_oom_killed_passes(self):
        lines = self.judge("memory", {"oom_killed": True})
        self.assertFalse(self.verdict(lines, "FAIL"), lines)

    def test_hang_that_was_not_timed_out_fails(self):
        lines = self.judge("hang", {"timed_out": False, "seconds": 3, "timeout": 40})
        self.assertTrue(self.verdict(lines, "FAIL"), lines)

    def test_hang_killed_at_the_timeout_passes(self):
        lines = self.judge("hang", {"timed_out": True, "seconds": 40, "timeout": 40})
        self.assertFalse(self.verdict(lines, "FAIL"), lines)


class FinalCheck(unittest.TestCase):
    def test_the_final_check_does_not_read_the_whole_store(self):
        self.assertNotIn("cmd_verify_clean", hostile_source())


if __name__ == "__main__":
    unittest.main()
