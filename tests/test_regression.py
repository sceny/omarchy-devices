import json
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
REGRESSION = ROOT / "dev" / "regression"

FEATURES_HEADER = "feature\trule\thow\tresult\tevidence\n"
CONFIG = {
    "script": "dev/regression.sh",
    "steps": "tests,rig,script",
    "marketplace": False,
    "owner_only": [{"what": "Bluetooth audio", "why": "No Bluetooth stack", "owner": "Checks it on a phone"}],
}


def git(cwd, *args):
    return subprocess.run(
        ["git", "-c", "user.name=t", "-c", "user.email=t@example.invalid", *args],
        cwd=cwd, capture_output=True, text=True, check=True,
    ).stdout.strip()


class RegressionTest(unittest.TestCase):
    def setUp(self):
        self.tmp = Path(tempfile.mkdtemp())
        self.repo = self.tmp / "repo"
        self.repo.mkdir()
        git(self.repo, "init", "-q")
        (self.repo / "README").write_text("x\n")
        (self.repo / "dev").mkdir()
        (self.repo / "dev" / "regression.json").write_text(json.dumps(CONFIG))
        git(self.repo, "add", "README", "dev/regression.json")
        git(self.repo, "commit", "-q", "-m", "init")
        self.sha = git(self.repo, "rev-parse", "HEAD")
        self.output = self.tmp / "output"
        self.out = self.tmp / "record"
        self.issues = self.tmp / "issues.json"
        self.issues.write_text("[]")
        self.output.mkdir()
        self.write_sandbox()
        self.write_rig()
        self.write_features([
            ("Panel answers over IPC", "answers", "dev/rig ipc status", "pass", "ipc-status.log"),
            ("Upgrade", "keeps settings", "live tag", "not yet", "not automated"),
        ])

    def write_sandbox(self, exit_code=0, results=True):
        rows = [{"step": "unit-model", "exit": exit_code, "seconds": 3, "oom_killed": False,
                 "timed_out": False, "stdout_bytes": 10, "note": ""}] if results else []
        summary = {"repo": "sceny/omarchy-devices", "sha": self.sha, "steps": ["tests"],
                   "harness": "develop", "oom_killed": False, "seconds": 3, "timeout": 3000,
                   "timed_out": False, "results": rows,
                   "passed": bool(rows) and exit_code == 0}
        (self.output / "summary.json").write_text(json.dumps(summary))

    def write_rig(self, rig_result="pass", recap=False):
        rig = self.output / "rig-ci" / "rig"
        rig.mkdir(parents=True, exist_ok=True)
        lines = f"rig summary for test-rig\nmanifest  pass\ncold-install  {rig_result}\n"
        if recap:
            lines += f"cold-install  {rig_result}\n"
        (rig / "summary.txt").write_text(lines + "1 passed, 0 failed\n")

    def write_features(self, rows):
        text = FEATURES_HEADER + "".join("\t".join(row) + "\n" for row in rows)
        script = self.output / "script"
        script.mkdir(exist_ok=True)
        (script / "features.tsv").write_text(text)

    def run_regression(self, *extra, sha=None):
        return subprocess.run(
            ["python3", str(REGRESSION), sha or self.sha, "--from-output", str(self.output),
             "--out", str(self.out), "--owner-issues", str(self.issues), *extra],
            cwd=self.repo, capture_output=True, text=True,
        )

    def record(self):
        return (self.out / "regression-record.md").read_text()

    def test_all_pass_and_nothing_not_yet_exits_zero(self):
        self.write_features([("Panel answers over IPC", "answers", "dev/rig ipc status", "pass", "ipc-status.log")])
        done = self.run_regression()
        self.assertEqual(done.returncode, 0, done.stderr)
        self.assertIn("**PASS**", self.record())

    def test_not_yet_row_exits_two(self):
        done = self.run_regression()
        self.assertEqual(done.returncode, 2, done.stderr)
        self.assertIn("NOT PASS", self.record())

    def test_planted_fail_row_exits_one(self):
        self.write_features([
            ("Panel answers over IPC", "answers", "dev/rig ipc status", "fail", "ipc-status.log"),
            ("Upgrade", "keeps settings", "live tag", "not yet", "not automated"),
        ])
        done = self.run_regression()
        self.assertEqual(done.returncode, 1, done.stderr)
        self.assertIn("1 fail", self.record())

    def test_the_record_shows_the_planted_failure_caught(self):
        done = self.run_regression()
        self.assertEqual(done.returncode, 2, done.stderr)
        row = next(line for line in self.record().splitlines() if line.startswith("| Planted failure |"))
        self.assertIn("| pass |", row)

    def test_a_planted_fixture_that_is_not_caught_exits_one(self):
        harness = self.tmp / "harness" / "dev"
        (harness / "fixtures" / "regression").mkdir(parents=True)
        shutil.copy(REGRESSION, harness / "regression")
        (harness / "fixtures" / "regression" / "planted-features.tsv").write_text(
            FEATURES_HEADER + "Planted\trule\thow\tpass\tplanted-features.tsv\n")
        done = subprocess.run(
            ["python3", str(harness / "regression"), self.sha, "--from-output", str(self.output),
             "--out", str(self.out), "--owner-issues", str(self.issues)],
            cwd=self.repo, capture_output=True, text=True,
        )
        self.assertEqual(done.returncode, 1, done.stderr)
        self.assertIn("| Planted failure |", self.record())
        self.assertIn("| fail |", self.record())

    def test_look_row_does_not_change_the_exit_status(self):
        self.write_features([
            ("Panel answers over IPC", "answers", "dev/rig ipc status", "pass", "ipc-status.log"),
            ("Section headers", "one height", "dev/rig screenshot", "look", "headers-open.png"),
        ])
        done = self.run_regression()
        self.assertEqual(done.returncode, 0, done.stderr)
        self.assertIn("1 to look at", self.record())

    def test_unknown_result_value_counts_as_fail(self):
        self.write_features([("Panel answers over IPC", "answers", "dev/rig ipc status", "ok", "ipc-status.log")])
        done = self.run_regression()
        self.assertEqual(done.returncode, 1, done.stderr)

    def test_failing_sandbox_unit_exits_one(self):
        self.write_sandbox(exit_code=1)
        done = self.run_regression()
        self.assertEqual(done.returncode, 1, done.stderr)

    def test_failing_rig_check_exits_one(self):
        self.write_rig(rig_result="FAIL")
        done = self.run_regression()
        self.assertEqual(done.returncode, 1, done.stderr)

    def test_missing_sandbox_summary_exits_one(self):
        (self.output / "summary.json").unlink()
        done = self.run_regression()
        self.assertEqual(done.returncode, 1, done.stderr)
        self.assertIn("no summary.json", self.record())

    def test_missing_script_features_exits_one(self):
        (self.output / "script" / "features.tsv").unlink()
        done = self.run_regression()
        self.assertEqual(done.returncode, 1, done.stderr)

    def test_a_rig_recap_repeats_a_check_once(self):
        self.write_rig(recap=True)
        done = self.run_regression()
        self.assertEqual(done.returncode, 2, done.stderr)
        self.assertEqual(self.record().count("| Rig: cold-install |"), 1)

    def test_a_failing_rig_recap_line_fails_the_check(self):
        rig = self.output / "rig-ci" / "rig" / "summary.txt"
        rig.write_text(rig.read_text() + "cold-install  FAIL exit=1\n")
        done = self.run_regression()
        self.assertEqual(done.returncode, 1, done.stderr)

    def test_a_commit_without_config_exits_one(self):
        git(self.repo, "rm", "-q", "dev/regression.json")
        git(self.repo, "commit", "-q", "-m", "drop config")
        done = self.run_regression(sha=git(self.repo, "rev-parse", "HEAD"))
        self.assertEqual(done.returncode, 1)
        self.assertIn("has no dev/regression.json", done.stderr)

    def test_a_config_with_a_wrong_type_exits_one(self):
        (self.repo / "dev" / "regression.json").write_text(json.dumps({**CONFIG, "marketplace": "no"}))
        git(self.repo, "commit", "-q", "-am", "bad type")
        done = self.run_regression(sha=git(self.repo, "rev-parse", "HEAD"))
        self.assertEqual(done.returncode, 1)
        self.assertIn("needs marketplace, a bool", done.stderr)

    def test_an_owner_issue_is_listed_without_changing_the_status(self):
        self.write_features([("Panel answers over IPC", "answers", "dev/rig ipc status", "pass", "ipc-status.log")])
        self.issues.write_text(json.dumps([
            {"number": 7, "title": "Check the bar", "url": "https://github.com/sceny/omarchy-devices/issues/7"}]))
        done = self.run_regression()
        self.assertEqual(done.returncode, 0, done.stderr)
        self.assertIn("[#7 Check the bar](https://github.com/sceny/omarchy-devices/issues/7)", self.record())
        self.assertIn("| Bluetooth audio | No Bluetooth stack | Checks it on a phone |", self.record())

    def test_bad_sha_exits_one(self):
        done = subprocess.run(
            ["python3", str(REGRESSION), "not-a-sha", "--from-output", str(self.output),
             "--out", str(self.out)],
            cwd=self.repo, capture_output=True, text=True,
        )
        self.assertEqual(done.returncode, 1)
        self.assertIn("40 lowercase hex", done.stderr)


if __name__ == "__main__":
    unittest.main()
