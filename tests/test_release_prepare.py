"""dev/release-prepare in a throwaway repository with its own origin, and the
release workflow's notes extraction run on what it wrote."""

import json
import os
import stat
import subprocess
import tempfile
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
SCRIPT = os.path.join(HERE, "..", "dev", "release-prepare")
RELEASE_NOTES = os.path.join(HERE, "..", "dev", "release-notes")

MANIFEST = '{\n  "id": "sceny.test",\n  "version": "%s",\n  "schemaVersion": 1\n}\n'
HEAD = "# What's new\n\nIntro.\n\n"
OLD = "## 0.8.2 — 2026-10-11\n\n### Highlights\n\n- Old.\n"
UNRELEASED = "## Unreleased\n\n### Highlights\n\n- New thing.\n\n"
ENV = dict(os.environ, GIT_AUTHOR_NAME="t", GIT_AUTHOR_EMAIL="t@example.com",
           GIT_COMMITTER_NAME="t", GIT_COMMITTER_EMAIL="t@example.com", GIT_CONFIG_GLOBAL="/dev/null")


# A gh that answers from a file: {"ours": [{"number": 7, "body": "..."}], "theirs": {"12": "OPEN"}},
# or {"error": "..."} for a GitHub that cannot be reached.
FAKE_GH = """#!/usr/bin/env python3
import json, os, sys
state = json.load(open(os.environ["FAKE_GH_STATE"]))
if "error" in state:
    sys.exit(state["error"])
args = sys.argv[1:]
if args[:2] == ["issue", "list"]:
    print(json.dumps(state["ours"]))
elif args[:2] == ["issue", "view"]:
    print(json.dumps({"state": state["theirs"][args[2]]}))
else:
    sys.exit("unexpected gh call: %s" % args)
"""


def git(cwd, *args):
    return subprocess.run(["git", *args], cwd=cwd, env=ENV, capture_output=True, text=True, check=True).stdout


def notes_of(work):
    """The release workflow's own extraction (dev/release-notes) on the repository."""
    with tempfile.TemporaryDirectory() as out:
        notes = os.path.join(out, "notes.md")
        subprocess.run([RELEASE_NOTES, notes], cwd=work, env=ENV, capture_output=True, text=True, check=True)
        with open(notes) as handle:
            return handle.read().strip()


class ReleasePrepare(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        root = self.tmp.name
        self.origin = os.path.join(root, "origin.git")
        self.work = os.path.join(root, "work")
        git(root, "init", "--bare", "-b", "main", self.origin)
        git(root, "clone", "-q", self.origin, self.work)
        git(self.work, "switch", "-c", "main")
        self.commit("main", MANIFEST % "0.8.2", HEAD + OLD)
        git(self.work, "tag", "-a", "v0.8.2", "-m", "0.8.2")
        git(self.work, "push", "-q", "origin", "main", "v0.8.2")
        git(self.work, "switch", "-q", "-c", "develop")
        self.commit("develop", MANIFEST % "0.8.2", HEAD + UNRELEASED + OLD)
        git(self.work, "push", "-q", "origin", "develop")
        git(self.work, "switch", "-q", "main")
        self.bin = os.path.join(root, "bin")
        os.mkdir(self.bin)
        gh = os.path.join(self.bin, "gh")
        with open(gh, "w") as handle:
            handle.write(FAKE_GH)
        os.chmod(gh, os.stat(gh).st_mode | stat.S_IXUSR)
        self.gh_state = os.path.join(root, "gh.json")
        self.freeze(clear=True)

    def freeze(self, clear=False, **state):
        """What the fake gh reports: nothing under review, or the given state."""
        with open(self.gh_state, "w") as handle:
            json.dump({"ours": [], "theirs": {}} if clear else state, handle)

    def under_review(self, state="OPEN"):
        self.freeze(ours=[{"number": 7, "body": "Marketplace: omacom/omarchy-plugin-marketplace#12\nCommit under review: abc"}],
                    theirs={"12": state})

    def tearDown(self):
        self.tmp.cleanup()

    def commit(self, name, manifest, changelog):
        for file, text in (("manifest.json", manifest), ("CHANGELOG.md", changelog)):
            with open(os.path.join(self.work, file), "w") as handle:
                handle.write(text)
        git(self.work, "add", ".")
        git(self.work, "commit", "-q", "-m", name)

    def run_script(self, *args):
        env = dict(ENV, PATH=self.bin + os.pathsep + ENV["PATH"], FAKE_GH_STATE=self.gh_state)
        return subprocess.run(["python3", SCRIPT, *args], cwd=self.work, env=env, capture_output=True, text=True)

    def read(self, file):
        with open(os.path.join(self.work, file)) as handle:
            return handle.read()

    def test_release_from_develop(self):
        done = self.run_script("0.9.0", "--date", "2026-10-20")
        self.assertEqual(done.returncode, 0, done.stderr)
        self.assertEqual(git(self.work, "branch", "--show-current").strip(), "release-0.9.0")
        self.assertIn('"version": "0.9.0"', self.read("manifest.json"))
        changelog = self.read("CHANGELOG.md")
        self.assertIn("## 0.9.0 — 2026-10-20", changelog)
        self.assertNotIn("Unreleased", changelog)
        self.assertEqual(notes_of(self.work), "### Highlights\n\n- New thing.")
        self.assertEqual(git(self.work, "status", "--porcelain").strip(), "")
        self.assertEqual(git(self.work, "log", "-1", "--format=%s").strip(), "Release 0.9.0: CHANGELOG and manifest version")
        self.assertEqual(git(self.work, "rev-parse", "HEAD~1"), git(self.work, "rev-parse", "origin/develop"))

    def test_fix_from_main(self):
        done = self.run_script("0.8.3", "--from", "main", "--note", "One.", "--note", "Two.", "--date", "2026-10-20")
        self.assertEqual(done.returncode, 0, done.stderr)
        self.assertEqual(git(self.work, "branch", "--show-current").strip(), "fix-0.8.3")
        self.assertIn('"version": "0.8.3"', self.read("manifest.json"))
        changelog = self.read("CHANGELOG.md")
        self.assertEqual(notes_of(self.work), "### Fixes\n\n- One.\n- Two.")
        self.assertLess(changelog.index("## 0.8.3 "), changelog.index("## 0.8.2 "))
        self.assertTrue(changelog.startswith(HEAD))

    def test_no_commit_leaves_the_edits_staged(self):
        done = self.run_script("0.9.0", "--no-commit")
        self.assertEqual(done.returncode, 0, done.stderr)
        self.assertEqual(git(self.work, "log", "-1", "--format=%s").strip(), "develop")
        self.assertIn("M  manifest.json", git(self.work, "status", "--porcelain"))

    def test_refuses(self):
        cases = {
            "tagged": (["0.8.2", "--from", "main", "--note", "x"], "already tagged"),
            "not above": (["0.8.1"], "not above"),
            "not a version": (["0.9"], "not X.Y.Z"),
            "unicode digits": (["\u0660.\u0669.\u0661"], "not X.Y.Z"),
            "fix without a note": (["0.8.3", "--from", "main"], "--note"),
            "note from develop": (["0.9.0", "--note", "x"], "--note is for a fix"),
            "bad date": (["0.9.0", "--date", "yesterday"], "YYYY-MM-DD"),
        }
        for name, (args, message) in cases.items():
            with self.subTest(name):
                done = self.run_script(*args)
                self.assertNotEqual(done.returncode, 0)
                self.assertIn(message, done.stderr)
                self.assertEqual(git(self.work, "branch", "--show-current").strip(), "main")

    def test_tag_only_on_origin_is_refused(self):
        other = os.path.join(self.tmp.name, "other")
        git(self.tmp.name, "clone", "-q", self.origin, other)
        git(other, "tag", "-a", "v0.8.3", "-m", "x")
        git(other, "push", "-q", "origin", "v0.8.3")
        done = self.run_script("0.8.3", "--from", "main", "--note", "x")
        self.assertNotEqual(done.returncode, 0)
        self.assertIn("already tagged", done.stderr)

    def test_empty_unreleased_is_refused(self):
        git(self.work, "switch", "-q", "develop")
        self.commit("empty", MANIFEST % "0.8.2", HEAD + "## Unreleased\n\n" + OLD)
        git(self.work, "push", "-q", "origin", "develop")
        done = self.run_script("0.9.0")
        self.assertNotEqual(done.returncode, 0)
        self.assertIn("no entries", done.stderr)

    def test_unreleased_with_only_headings_is_refused(self):
        git(self.work, "switch", "-q", "develop")
        self.commit("headings", MANIFEST % "0.8.2", HEAD + "## Unreleased\n\n### Highlights\n\n" + OLD)
        git(self.work, "push", "-q", "origin", "develop")
        done = self.run_script("0.9.0")
        self.assertNotEqual(done.returncode, 0)
        self.assertIn("no entries", done.stderr)

    def test_existing_branch_and_dirty_tree_are_refused(self):
        git(self.work, "branch", "release-0.9.0", "main")
        done = self.run_script("0.9.0")
        self.assertIn("already exists", done.stderr)
        git(self.work, "branch", "-q", "-D", "release-0.9.0")
        with open(os.path.join(self.work, "manifest.json"), "a") as handle:
            handle.write("\n")
        done = self.run_script("0.9.0")
        self.assertIn("tracked changes", done.stderr)

    def test_frozen_main_refuses_a_release_from_develop(self):
        self.under_review("OPEN")
        done = self.run_script("0.9.0")
        self.assertNotEqual(done.returncode, 0)
        self.assertIn("main is frozen", done.stderr)
        self.assertIn("omacom/omarchy-plugin-marketplace#12 OPEN", done.stderr)
        self.assertIn("#7", done.stderr)
        self.assertEqual(git(self.work, "branch", "--show-current").strip(), "main")
        self.assertEqual(git(self.work, "branch", "--list", "release-0.9.0").strip(), "")

    def test_frozen_main_does_not_refuse_an_urgent_fix(self):
        self.under_review("OPEN")
        done = self.run_script("0.8.3", "--from", "main", "--note", "x")
        self.assertEqual(done.returncode, 0, done.stderr)
        self.assertIn("main is frozen", done.stderr)
        self.assertEqual(git(self.work, "branch", "--show-current").strip(), "fix-0.8.3")

    def test_a_closed_marketplace_issue_does_not_refuse_but_is_named(self):
        self.under_review("CLOSED")
        done = self.run_script("0.9.0")
        self.assertEqual(done.returncode, 0, done.stderr)
        done = self.run_script("--check-freeze")
        self.assertEqual(done.returncode, 0)
        self.assertIn("CLOSED: out of sync", done.stdout)
        self.assertIn("main is not frozen", done.stdout)

    def test_unreadable_github_or_unreadable_issue_refuses(self):
        self.freeze(error="gh: HTTP 502")
        done = self.run_script("0.9.0")
        self.assertNotEqual(done.returncode, 0)
        self.assertIn("could not read GitHub", done.stderr)
        self.freeze(ours=[{"number": 7, "body": "no link here"}], theirs={})
        done = self.run_script("0.9.0")
        self.assertNotEqual(done.returncode, 0)
        self.assertIn("treated as frozen", done.stderr)

    def test_check_freeze_prints_frozen_and_clear(self):
        done = self.run_script("--check-freeze")
        self.assertEqual(done.returncode, 0, done.stderr)
        self.assertIn("main is not frozen: nothing is under review", done.stdout)
        self.under_review("OPEN")
        done = self.run_script("--check-freeze")
        self.assertEqual(done.returncode, 1)
        self.assertIn("omacom/omarchy-plugin-marketplace#12 OPEN", done.stdout)
        self.assertIn("main is frozen", done.stdout)
        self.assertEqual(git(self.work, "branch", "--show-current").strip(), "main")

    def test_check_freeze_takes_no_version(self):
        done = self.run_script("0.9.0", "--check-freeze")
        self.assertNotEqual(done.returncode, 0)
        self.assertIn("takes no version", done.stderr)


if __name__ == "__main__":
    unittest.main()
