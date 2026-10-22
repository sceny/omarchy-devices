"""The threat model's assets are mapped to the tests that hold them
(docs/internals/security-assets.md), and the map is checked by a script, not
re-read each release. Each row has at least one test in *Held by* or a
`manual:` line with a reason; every file, class, test and JS title a row
names exists; a gap links an issue or says `pending: tracked privately`. The
check runs on planted rows as well as on the shipped table (`PlantedRows`)."""

import os
import re
import unittest

from test_review_list import class_exists

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, ".."))
DOC = "docs/internals/security-assets.md"
MIN_REASON_WORDS = 5
PENDING = "pending: tracked privately"
ISSUE = re.compile(r"/issues/\d+\b")
FILE = re.compile(r"tests/[\w./-]+\.(?:py|js|mjs)")


def rows(text):
    """[(line, asset, held, manual, gap)] of the table's rows."""
    out = []
    for number, line in enumerate(text.split("\n"), 1):
        if not line.startswith("|") or line.startswith("|---") or line.startswith("| Asset"):
            continue
        cells = [c.strip() for c in line.strip().strip("|").split("|")]
        cells += [""] * (4 - len(cells))
        out.append((number, cells[0], cells[1], cells[2], cells[3]))
    return out


def problems(text, root=ROOT):
    found = []
    table = rows(text)
    if not table:
        return ["%s:1: the assets table has no rows" % DOC]
    for number, asset, held, manual, gap in table:
        name = re.sub(r"\*|\s*\(.*", "", asset)[:40]
        where = "%s:%d: %s" % (DOC, number, name)
        titles = re.findall(r"(?<![\w*])\*([^*]+)\*(?![\w*])", held)
        tokens = re.findall(r"`([^`]+)`", held)
        if not tokens and not titles:
            if not manual.startswith("manual:"):
                found.append("%s: has no test and no `manual:` line" % where)
        if manual and not manual.startswith("manual:"):
            found.append("%s: the Manual cell must start with `manual:`" % where)
        if manual.startswith("manual:") and len(manual[len("manual:"):].split()) < MIN_REASON_WORDS:
            found.append("%s: `manual:` with no reason a script cannot hold it" % where)
        if gap and PENDING not in gap and not ISSUE.search(gap):
            found.append("%s: a gap with no issue and not marked pending" % where)
        current = None
        for item in re.finditer(r"`([^`]+)`|(?<![\w*])\*([^*]+)\*(?![\w*])", held):
            token, title = item.group(1), item.group(2)
            if token and FILE.fullmatch(token):
                current = os.path.join(root, token)
                if not os.path.isfile(current):
                    found.append("%s: names %s, which does not exist" % (where, token))
                    current = None
            elif current and token and re.fullmatch(r"test_\w+", token):
                with open(current) as f:
                    if not re.search(r"def %s\(" % token, f.read()):
                        found.append("%s: %s has no test %s" % (where, os.path.relpath(current, root), token))
            elif current and token and re.fullmatch(r"[A-Z]\w+", token):
                if not class_exists(current, token):
                    found.append("%s: %s has no class %s" % (where, os.path.relpath(current, root), token))
            elif current and title:
                with open(current) as f:
                    body = f.read()
                if title not in body and title.replace("'", "\\'") not in body:
                    found.append("%s: %s has no test titled %r" % (where, os.path.relpath(current, root), title))
    return sorted(set(found))


class EveryAssetNamesItsTests(unittest.TestCase):
    def doc(self):
        with open(os.path.join(ROOT, DOC)) as f:
            return f.read()

    def test_every_row_names_tests_that_exist_or_why_none(self):
        found = problems(self.doc())
        self.assertEqual(found, [], "\n".join(found))

    def test_the_table_holds_the_threat_models_assets(self):
        assets = " ".join(r[1] for r in rows(self.doc()))
        for needed in ("Message text", "Contact names", "Notifications", "files and pictures", "clipboard",
                       "screen and input", "adb access", "account", "pkexec", "shared shell"):
            self.assertIn(needed, assets)


class PlantedRows(unittest.TestCase):
    HEAD = "| Asset | Held by | Manual | Gap |\n|---|---|---|---|\n"

    def check(self, row):
        return problems(self.HEAD + row + "\n")

    def test_a_row_with_no_test_and_no_manual_line_fails(self):
        found = self.check("| **Planted** | | | |")
        self.assertEqual(len(found), 1, found)
        self.assertIn("no test and no `manual:`", found[0])
        self.assertTrue(found[0].startswith(DOC + ":3:"), found)

    def test_a_manual_line_needs_a_reason(self):
        self.assertEqual(self.check("| **Planted** | | manual: a person reads it in review | |"), [])
        found = self.check("| **Planted** | | manual: judgement | |")
        self.assertIn("no reason", found[0])

    def test_a_missing_file_class_test_or_title_fails(self):
        for held, why in (("`tests/test_nowhere.py` `Whatever`", "does not exist"),
                          ("`tests/test_argv.py` `NoSuchClass`", "no class NoSuchClass"),
                          ("`tests/test_bridge.py` `Sends` (`test_no_such_test`)", "no test test_no_such_test"),
                          ("`tests/model.test.js` *a title nobody wrote*", "no test titled")):
            found = self.check("| **Planted** | %s | | |" % held)
            self.assertEqual(len(found), 1, (held, found))
            self.assertIn(why, found[0])

    def test_existing_tests_pass(self):
        for held in ("`tests/test_argv.py` `ClipboardOnlyOnPaste`, `OsdLines`",
                     "`tests/test_bridge.py` `Sends` (`test_text_in_argv_is_never_sent`)"):
            self.assertEqual(self.check("| **Planted** | %s | | |" % held), [], held)

    def test_a_gap_needs_an_issue_or_the_pending_mark(self):
        row = "| **Planted** | `tests/test_argv.py` `OsdLines` | | %s |"
        self.assertEqual(len(self.check(row % "it leaks")), 1)
        self.assertEqual(self.check(row % "[#1](https://github.com/o/r/issues/1)"), [])
        self.assertEqual(self.check(row % PENDING), [])


if __name__ == "__main__":
    unittest.main()
