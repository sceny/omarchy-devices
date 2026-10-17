"""The pull-request review list (docs/internals/releasing.md, *Every pull
request: review with a security check*) is checked by scripts, not re-read by
an agent each time. Each bullet ends with `Tests:` and the test files that fail
the build for it (a class in brackets), or with `manual:` and a line on why a
script cannot check it. This test fails on a bullet with neither, on a file or
class that does not exist, and on a `manual:` with no reason."""

import os
import re
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.join(HERE, "..")
DOC = os.path.join(ROOT, "docs", "internals", "releasing.md")
HEADING = "## Every pull request: review with a security check"
MIN_REASON_WORDS = 5

TESTS = re.compile(r"(?<![\w`])Tests:")
MANUAL = re.compile(r"(?<![\w`])manual:")
FILE_REF = re.compile(r"`(tests/[\w./-]+)`(\s*\(([^)]*)\))?")
NAME = re.compile(r"`(\w+)`")


def bullets(text):
    """[(line, text)] of each top-level bullet in the review-list section."""
    lines = text.split("\n")
    try:
        start = next(i for i, l in enumerate(lines) if l.strip() == HEADING)
    except StopIteration:
        return None
    out, current = [], None
    for i in range(start + 1, len(lines)):
        line = lines[i]
        if line.startswith("## "):
            break
        if line.startswith("- "):
            current = [i + 1, line]
            out.append(current)
        elif current is not None and (line.startswith("  ") or line == ""):
            current[1] += "\n" + line
        elif line.strip():
            current = None
    return [(n, t.rstrip()) for n, t in out]


def class_exists(path, name):
    with open(path) as f:
        body = f.read()
    if path.endswith(".py"):
        return re.search(r"^class %s\b" % re.escape(name), body, re.M) is not None
    return name in body


def problems(text, root=ROOT):
    found = []
    items = bullets(text)
    if items is None:
        return ["docs/internals/releasing.md:1: the section %r is gone" % HEADING]
    if not items:
        return ["docs/internals/releasing.md:1: the review list has no bullets"]
    for line, bullet in items:
        head = bullet.split("\n")[0][:60]
        where = "docs/internals/releasing.md:%d" % line
        tests, manual = TESTS.search(bullet), MANUAL.search(bullet)
        if not tests and not manual:
            found.append("%s: %r ends with neither `Tests:` nor `manual:`" % (where, head))
            continue
        if tests:
            clause = bullet[tests.end():]
            if manual and manual.start() > tests.start():
                clause = bullet[tests.end():manual.start()]
            refs = FILE_REF.findall(clause)
            if not refs:
                found.append("%s: %r has `Tests:` and names no `tests/...` file" % (where, head))
            for path, _, names in refs:
                full = os.path.join(root, path)
                if not os.path.isfile(full):
                    found.append("%s: %r names %s, which does not exist" % (where, head, path))
                    continue
                for name in NAME.findall(names or ""):
                    if not class_exists(full, name):
                        found.append("%s: %r names %s in %s, which does not exist" % (where, head, name, path))
        if manual:
            reason = re.sub(r"\s+", " ", bullet[manual.end():]).strip()
            if len(reason.split()) < MIN_REASON_WORDS:
                found.append("%s: %r has `manual:` with no reason a script cannot check it" % (where, head))
        for path in re.findall(r"`(tests/[\w./-]+)`", bullet):
            if not os.path.isfile(os.path.join(root, path)):
                found.append("%s: %r names %s, which does not exist" % (where, head, path))
    return sorted(set(found))


class ReviewListNamesItsTests(unittest.TestCase):
    def doc(self):
        with open(DOC) as f:
            return f.read()

    def test_every_bullet_names_its_tests_or_why_none(self):
        found = problems(self.doc())
        self.assertEqual(found, [], "\n".join(found))

    def test_the_list_is_found_and_holds_the_four_lints(self):
        items = bullets(self.doc())
        self.assertGreaterEqual(len(items), 15)
        body = "\n".join(t for _, t in items)
        for cls in ("LogsCarryNoPrivateText", "ImagesOnlyFromSafePaths", "RootOnlyAsConfirmed", "ListenersAndShells"):
            self.assertIn(cls, body)

    def test_a_bullet_with_neither_is_found(self):
        text = "%s\n\n- A rule nobody checks.\n- Another.\n  Tests: `tests/test_argv.py` (`PrivateTextOnArgv`).\n" % HEADING
        found = problems(text)
        self.assertEqual(len(found), 1, found)
        self.assertIn("neither", found[0])

    def test_a_file_that_does_not_exist_is_found(self):
        text = "%s\n\n- A rule.\n  Tests: `tests/test_nowhere.py` (`Anything`).\n" % HEADING
        found = problems(text)
        self.assertEqual(len(found), 1, found)
        self.assertIn("tests/test_nowhere.py", found[0])

    def test_a_class_that_does_not_exist_is_found(self):
        text = "%s\n\n- A rule.\n  Tests: `tests/test_argv.py` (`DeviceFilesOpenThroughTheGate`).\n" % HEADING
        found = problems(text)
        self.assertEqual(len(found), 1, found)
        self.assertIn("DeviceFilesOpenThroughTheGate", found[0])

    def test_tests_with_no_file_is_found(self):
        found = problems("%s\n\n- A rule.\n  Tests: the argv test.\n" % HEADING)
        self.assertEqual(len(found), 1, found)

    def test_a_manual_line_needs_a_reason(self):
        for tail in ("manual:", "manual: judgement", "manual:\n"):
            found = problems("%s\n\n- A rule.\n  %s\n" % (HEADING, tail))
            self.assertEqual(len(found), 1, (tail, found))
            self.assertIn("no reason", found[0])
        ok = "%s\n\n- A rule.\n  manual: a script cannot tell which value a person typed.\n" % HEADING
        self.assertEqual(problems(ok), [])

    def test_a_test_named_in_prose_of_a_bullet_must_exist_too(self):
        text = "%s\n\n- A rule that mentions `tests/test_gone.py` in passing.\n  Tests: `tests/test_argv.py`.\n" % HEADING
        found = problems(text)
        self.assertEqual(len(found), 1, found)

    def test_a_missing_section_is_found(self):
        self.assertEqual(len(problems("# Releasing\n\nNothing here.\n")), 1)

    def test_a_node_test_file_needs_no_class(self):
        text = "%s\n\n- A rule.\n  Tests: `tests/model.test.js`.\n" % HEADING
        self.assertEqual(problems(text), [])

    def test_a_planted_bullet_in_the_real_doc_fails(self):
        planted = self.doc().replace(
            "- The shell is never a party to a Wayland data transfer",
            "- A new rule with no test and no reason.\n- The shell is never a party to a Wayland data transfer", 1)
        self.assertNotEqual(planted, self.doc())
        found = problems(planted)
        self.assertEqual(len(found), 1, found)
        self.assertIn("neither", found[0])


if __name__ == "__main__":
    unittest.main()
