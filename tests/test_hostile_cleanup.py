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
SANDBOX = os.path.join(ROOT, "dev", "sandbox")

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


def new_id_source():
    with open(SANDBOX) as f:
        m = re.search(r"^new_id\(\) \{\n.*?^\}\n", f.read(), re.M | re.S)
    assert m, "dev/sandbox has no new_id"
    return m.group(0)


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

    def left(self, ids, listing, runs=(), work_exists=False):
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
                f"HOSTILE_IDS=({' '.join(ids)})\n"
                f'hostile_left "{work}"\necho RC=$?\n'
            )
            return bash(body).stdout.strip().splitlines()[-1]

    def test_a_live_session_of_another_run_is_not_this_tests_leftover(self):
        self.assertEqual(self.left(["aaaaaaaa"], "sceny-sandbox-dev-bbbbbbbb"), "RC=0")

    def test_another_runs_directory_is_not_this_tests_leftover(self):
        self.assertEqual(self.left(["aaaaaaaa"], "", runs=["bbbbbbbb"]), "RC=0")

    def test_nothing_left_passes(self):
        self.assertEqual(self.left(["aaaaaaaa", "cccccccc"], ""), "RC=0")

    def test_its_own_container_is_a_leftover(self):
        self.assertEqual(self.left(["aaaaaaaa"], "sceny-sandbox-aaaaaaaa"), "RC=1")

    def test_its_own_run_directory_is_a_leftover(self):
        self.assertEqual(self.left(["aaaaaaaa"], "", runs=["aaaaaaaa"]), "RC=1")

    def test_its_own_dev_session_is_a_leftover(self):
        self.assertEqual(self.left(["cccccccc"], "sceny-sandbox-dev-cccccccc"), "RC=1")

    def test_its_own_work_directory_is_a_leftover(self):
        self.assertEqual(self.left([], "", work_exists=True), "RC=1")

    def test_a_process_that_names_the_work_directory_is_a_leftover(self):
        with tempfile.TemporaryDirectory() as state:
            work = os.path.join(state, "gone")
            body = (
                f'SB_STATE="{state}"\nSB_UID="{os.getuid()}"\nHOSTILE_IDS=()\n'
                f'python3 -c "import time; time.sleep(60)" "{work}" &\nchild=$!\n'
                f'hostile_left "{work}"\necho RC=$?\n'
                'kill "$child"; wait "$child" 2>/dev/null\n'
                f'hostile_left "{work}"\necho RC=$?\n'
            )
            lines = [l for l in bash(body).stdout.splitlines() if l.startswith("RC=")]
            self.assertEqual(lines, ["RC=1", "RC=0"])

    def test_a_child_of_this_test_still_running_is_a_leftover(self):
        with tempfile.TemporaryDirectory() as state:
            body = (
                f'SB_STATE="{state}"\nSB_UID="{os.getuid()}"\nHOSTILE_IDS=()\n'
                "sleep 60 &\nchild=$!\n"
                f'hostile_left "{state}/nowork"\necho RC=$?\n'
                'kill "$child"; wait "$child" 2>/dev/null\n'
            )
            self.assertEqual(bash(body).stdout.strip().splitlines()[-1], "RC=1")

    def test_a_container_of_a_dev_pull_is_a_leftover(self):
        # the pull's re-encode and video containers and its run directory have ids of their own
        self.assertEqual(self.left(["cccccccc", "dddddddd"], "sceny-sandbox-dddddddd"), "RC=1")
        self.assertEqual(self.left(["cccccccc", "dddddddd"], "", runs=["dddddddd"]), "RC=1")


class EveryIdIsJudged(unittest.TestCase):
    """The runs and containers the test starts without its own record (the out-dir
    runs, a dev pull's containers) are judged because every id comes from new_id."""

    def test_no_id_is_made_but_by_new_id(self):
        with open(SANDBOX) as f:
            made = re.findall(r"^.*\$\(od .*urandom.*$", f.read(), re.M)
        self.assertEqual(len(made), 1, f"an id made outside new_id: {made}")
        self.assertIn("urandom", new_id_source())

    def test_new_id_writes_the_log_from_a_subshell_and_prints_the_id(self):
        with tempfile.TemporaryDirectory() as d:
            log = os.path.join(d, "ids")
            r = bash(
                new_id_source()
                + f'SB_ID_LOG="{log}"\n: >"$SB_ID_LOG"\n'
                'a=$(new_id)\n(b=$(new_id); echo "B=$b")\necho "A=$a"\n'
            )
            lines = dict(l.split("=") for l in r.stdout.split())
            with open(log) as f:
                logged = f.read().split()
            self.assertEqual(sorted(logged), sorted([lines["A"], lines["B"]]))
            self.assertTrue(all(re.fullmatch(r"[0-9a-f]{8}", i) for i in logged), logged)

    def test_new_id_prints_an_id_with_no_log(self):
        r = bash(new_id_source() + 'SB_ID_LOG=""\nnew_id\n')
        self.assertRegex(r.stdout.strip(), r"^[0-9a-f]{8}$")

    def test_a_leak_of_a_run_the_test_never_recorded_by_hand_fails_the_final_check(self):
        with tempfile.TemporaryDirectory() as state:
            log = os.path.join(state, "ids")
            body = (
                new_id_source()
                + f'SB_STATE="{state}"\nSB_UID="{os.getuid()}"\nSB_ID_LOG="{log}"\n: >"$SB_ID_LOG"\n'
                # a run started by the test's out-dir step: its id is made in a subshell
                '(id=$(new_id); mkdir -p "$SB_STATE/runs/$id"; echo "RUN=$id")\n'
                "pm() { :; }\n"
                'hostile_ids_read "$SB_ID_LOG"\n'
                f'hostile_left "{state}/nowork"\necho RC=$?\n'
            )
            r = bash(body)
            self.assertEqual(r.stdout.strip().splitlines()[-1], "RC=1", r.stdout)

    def out_dir_step(self, leave):
        # the real hostile_out_dir, its cmd_run replaced by one that makes an id and refuses
        with tempfile.TemporaryDirectory() as state:
            work = os.path.join(state, "hostile", "w")
            os.makedirs(work)
            with open(os.path.join(work, "sha-probe"), "w") as f:
                f.write("deadbeef" * 5 + "\n")
            body = (
                new_id_source()
                + f'SB_STATE="{state}"\nSB_UID="{os.getuid()}"\nSB_DIR="{state}"\nHOSTILE_WORK="{work}"\n'
                + f'SB_ID_LOG="{work}/ids"\n: >"$SB_ID_LOG"\n'
                "cmd_run() { local id; id=$(new_id); "
                + ('mkdir -p "$SB_STATE/runs/$id"; ' if leave else "")
                + "echo 'run: refused: inside a git repository'; return 1; }\n"
                "hostile_out_dir >/dev/null 2>&1\n"
                'hostile_ids_read "$SB_ID_LOG"\n'
                'echo "IDS=${#HOSTILE_IDS[@]}"\n'
                f'rm -rf "{work}"\nhostile_left "{work}"\necho RC=$?\n'
            )
            return bash(body).stdout.strip().splitlines()[-2:]

    def test_a_run_left_by_the_out_dir_step_fails_the_final_check(self):
        self.assertEqual(self.out_dir_step(leave=True), ["IDS=2", "RC=1"])

    def test_clean_out_dir_runs_pass_the_final_check(self):
        self.assertEqual(self.out_dir_step(leave=False), ["IDS=2", "RC=0"])

    def test_a_clean_run_of_the_recorded_ids_passes(self):
        with tempfile.TemporaryDirectory() as state:
            log = os.path.join(state, "ids")
            body = (
                new_id_source()
                + f'SB_STATE="{state}"\nSB_UID="{os.getuid()}"\nSB_ID_LOG="{log}"\n: >"$SB_ID_LOG"\n'
                '(new_id >/dev/null)\n(new_id >/dev/null)\npm() { :; }\n'
                'hostile_ids_read "$SB_ID_LOG"\n'
                f'hostile_left "{state}/nowork"\necho RC=$?\n'
            )
            self.assertEqual(bash(body).stdout.strip().splitlines()[-1], "RC=0")

    def test_the_test_records_every_id_and_reads_them_before_its_work_directory_goes(self):
        src = hostile_source()
        self.assertIn('SB_ID_LOG="$HOSTILE_WORK/ids"', src)
        self.assertLess(src.index('hostile_ids_read "$SB_ID_LOG"'), src.index('say "16.'))
        self.assertNotIn("HOSTILE_RUN_IDS", src)
        self.assertNotIn("HOSTILE_DEV_NAMES", src)


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
                + new_id_source()
                + "cmd_run() { echo '==> sandbox run abcdef12: repo'; }\n"
                "hostile_run probe probe --steps tests\n"
                'echo "FAILS=$HOSTILE_FAIL"\n'
            )
            return bash(body).stdout.strip().splitlines()[-1]

    def test_a_judge_that_writes_no_verdict_fails_the_step(self):
        self.assertEqual(self.run_with_judge(""), "FAILS=1")

    def test_a_judge_that_passes_fails_nothing_and_the_run_is_kept(self):
        self.assertEqual(self.run_with_judge("PASS\tsomething held\n"), "FAILS=0")


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

    def test_the_listener_and_sampler_stop_before_the_final_check(self):
        src = hostile_source()
        before_16 = src[src.index('unset "$secret_name"') : src.index('say "16.')]
        self.assertIn("hostile_stop_listeners", before_16)
        self.assertIn("hostile_sample_stop", before_16)


class ListenerStop(unittest.TestCase):
    def test_a_stopped_listener_is_gone_and_removes_its_socket(self):
        with tempfile.TemporaryDirectory() as work:
            body = (
                f'HOSTILE_WORK="{work}"\nhostile_listeners || exit 3\n'
                'pid=$HOSTILE_LISTENER_PID\n'
                f'unix=$(python3 -c "import json; print(json.load(open(\'{work}/listeners.json\'))[\'unix_path\'])")\n'
                '[[ -S $unix ]] && echo SOCKET_UP\n'
                "hostile_stop_listeners\n"
                'kill -0 "$pid" 2>/dev/null && echo ALIVE || echo GONE\n'
                '[[ -e $unix ]] && echo SOCKET_LEFT || echo SOCKET_REMOVED\n'
            )
            r = bash(body)
            self.assertEqual(r.stdout.split(), ["SOCKET_UP", "GONE", "SOCKET_REMOVED"], r.stdout + r.stderr)


if __name__ == "__main__":
    unittest.main()
