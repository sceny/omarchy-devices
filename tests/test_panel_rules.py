"""Panel rules a reviewer would check by reading, each failing with file:line.

Esc, motion pace and header height are below the scripted-focus rule; each
lint takes the files it reads, so a planted file shows it fails (PlantedCases)
and the shipped QML shows it passes.

Nothing scripted focuses a text field (AGENTS.md): keystrokes meant for
another window would land in it, and Enter would send or commit it. The IPC
target's functions are followed through every function they call; one that
reaches a focus on a text field without the `typeHere` gate fails, naming the
path. The user's own click or Enter passes `typeHere`; the IPC target never
does.
"""

import glob
import os
import re
import tempfile
import unittest

from test_panelfield import line_of, shipped_qml
from test_qml import call_args, code_only

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.join(HERE, "..")

FOCUS = re.compile(r"\b(\w+)\.forceActiveFocus\(")
# The key catcher is not a text field: giving it focus hands the keyboard back.
NOT_A_FIELD = ("keyCatcher",)


def match_close(text, start):
    """The index of the brace closing the one at `start`."""
    depth = 0
    for i in range(start, len(text)):
        if text[i] == "{":
            depth += 1
        elif text[i] == "}":
            depth -= 1
            if depth == 0:
                return i
    return len(text) - 1


def functions(path):
    """Every `function name(params) {` in a file: its parameters, its body
    (comments and strings blanked), the line it starts on and whether it sits
    inside an IpcHandler."""
    with open(path) as f:
        text = code_only(f.read())
    ipc = []
    for m in re.finditer(r"\bIpcHandler\s*\{", text):
        ipc.append((m.end() - 1, match_close(text, m.end() - 1)))
    found = []
    for m in re.finditer(r"\bfunction\s+(\w+)\s*\(([^)]*)\)[^{;]*\{", text):
        end = match_close(text, m.end() - 1)
        params = [p.split(":")[0].strip() for p in m.group(2).split(",") if p.strip()]
        found.append({
            "name": m.group(1), "params": params, "body": text[m.end():end],
            "file": os.path.basename(path), "line": text.count("\n", 0, m.start()) + 1,
            "ipc": any(a < m.start() < b for a, b in ipc),
        })
    return found


def ungated_focus(fn):
    """The text fields a function focuses without `typeHere` on the statement
    or on the `if` in front of it."""
    found = []
    for m in FOCUS.finditer(fn["body"]):
        if m.group(1) in NOT_A_FIELD:
            continue
        start = fn["body"].rfind("\n", 0, m.start()) + 1
        context = fn["body"][max(0, fn["body"].rfind("\n", 0, start - 1) + 1):m.end()]
        if "typeHere" not in context or "typeHere" not in fn["params"]:
            found.append(m.group(1))
    return found


def scripted_focus(paths):
    """Paths from an IPC function to a focus on a text field with no gate, or
    to a call that hands `true` to a `typeHere` parameter."""
    funcs = {}
    for p in paths:
        for fn in functions(p):
            funcs.setdefault(fn["name"], []).append(fn)
    found, seen = [], set()

    def walk(fn, chain):
        key = (fn["file"], fn["line"])
        if key in seen:
            return
        seen.add(key)
        here = chain + ["%s (%s:%d)" % (fn["name"], fn["file"], fn["line"])]
        for field in ungated_focus(fn):
            found.append("%s focuses %s: %s" % (here[0], field, " -> ".join(here)))
        for m in re.finditer(r"(?<![\w.])(?:root\.)?(\w+)\s*\(", fn["body"]):
            for callee in funcs.get(m.group(1), []):
                if callee is fn or m.group(1) == fn["name"]:
                    continue
                if "typeHere" in callee["params"]:
                    args = call_args(fn["body"], m.end() - 1)
                    i = callee["params"].index("typeHere")
                    if i < len(args) and args[i] == "true":
                        found.append("%s hands typeHere=true to %s: %s"
                                     % (here[0], callee["name"], " -> ".join(here)))
                walk(callee, here)

    roots = [fn for name in sorted(funcs) for fn in funcs[name] if fn["ipc"]]
    for fn in roots:
        seen.clear()
        walk(fn, [])
    return sorted(set(found))


class NothingScriptedFocusesAField(unittest.TestCase):
    def test_no_ipc_function_reaches_an_ungated_focus(self):
        files = sorted(glob.glob(os.path.join(ROOT, "*.qml")))
        self.assertTrue(files)
        found = scripted_focus(files)
        self.assertEqual(found, [], "\n".join(found))

    def test_the_check_finds_a_missing_gate_and_a_true(self):
        src = (
            "Item {\n"
            "  function openIt(typeHere) { if (typeHere === true) field.forceActiveFocus() }\n"
            "  function openBare() { field.forceActiveFocus() }\n"
            "  function viaOpen() { openBare() }\n"
            "  function gateOnOtherLine(typeHere) {\n    other.forceActiveFocus()\n  }\n"
            "  function back() { keyCatcher.forceActiveFocus() }\n"
            "  IpcHandler {\n"
            "    function ok(): string { root.openIt(); return \"\" }\n"
            "    function ok2(): string { root.openIt(false); root.back(); return \"\" }\n"
            "    function bad(): string { root.viaOpen(); return \"\" }\n"
            "    function worse(): string { root.openIt(true); return \"\" }\n"
            "    function ungated(): string { root.gateOnOtherLine(); return \"\" }\n"
            "  }\n}\n")
        with tempfile.NamedTemporaryFile("w", suffix=".qml", delete=False) as f:
            f.write(src)
        try:
            found = scripted_focus([f.name])
            names = sorted(m.split(" ")[0] for m in found)
            self.assertEqual(names, ["bad", "ungated", "worse"], found)
        finally:
            os.remove(f.name)



class ClosingHandsTheKeyboardBack(unittest.TestCase):
    def test_the_close_branch_focuses_the_key_catcher(self):
        with open(os.path.join(ROOT, "Panel.qml")) as f:
            text = code_only(f.read())
        m = re.search(r"\bonOpenedChanged\s*:\s*\{", text)
        self.assertTrue(m, "Panel.qml has no onOpenedChanged")
        body = text[m.end() - 1:match_close(text, m.end() - 1) + 1]
        close = re.search(r"\belse\s*\{", body)
        self.assertTrue(close, "onOpenedChanged has no close branch")
        branch = body[close.end() - 1:match_close(body, close.end() - 1) + 1]
        self.assertIn("keyCatcher.forceActiveFocus()", branch,
                      "a field that held the keyboard at close keeps it at the next open")


class AppTilesGlideOnlyOnTheUsersOwnChange(unittest.TestCase):
    def test_every_position_behavior_in_the_pinned_row_is_gated(self):
        with open(os.path.join(ROOT, "AppPinRow.qml")) as f:
            text = code_only(f.read())
        behaviors = re.findall(r"Behavior on (?:x|y)\s*\{[^\n]*", text)
        self.assertTrue(behaviors, "AppPinRow.qml has no position behavior")
        for b in behaviors:
            self.assertRegex(b, r"\{\s*enabled:", "a tile moves to its place with no glide until the user changes the row: %s" % b)

    def test_the_all_apps_tile_waits_for_pins_that_arrived(self):
        with open(os.path.join(ROOT, "AppPinRow.qml")) as f:
            text = code_only(f.read())
        self.assertRegex(text, r"glides:\s*row\.animate\s*&&\s*row\.pinsKnown")


def rel(path):
    return os.path.relpath(path, ROOT)


def blanked(path):
    with open(path) as f:
        return code_only(f.read())


def escape_problems(paths):
    """Esc steps back through PanelField's escapeStep: no other file sets a
    Keys.onEscapePressed."""
    found = []
    for path in paths:
        if os.path.basename(path) == "PanelField.qml":
            continue
        text = blanked(path)
        for m in re.finditer(r"\bKeys\.onEscapePressed\b", text):
            found.append("%s:%d: Keys.onEscapePressed: Esc steps back through PanelField's escapeStep"
                         % (rel(path), line_of(text, m.start())))
    return found


# Model.js constants that are timings; a duration reading one reads the pace.
PACE = r"Model\.(?:MOTION|RING_BEAT|PLACE_FLASH_HOLD_MS)\b"


def motion_problems(paths):
    """A `duration:` whose value reads neither Model's pace nor a property of
    the same file that does (a named constant derived from it)."""
    found = []
    for path in paths:
        text = blanked(path)
        derived = set()
        for m in re.finditer(r"\b(?:readonly\s+)?property\s+\w+\s+(\w+)\s*:\s*([^\n]*)", text):
            if re.search(PACE, m.group(2)):
                derived.add(m.group(1))
        for m in re.finditer(r"(?<![\w.])duration\s*:\s*([^;\n}]*)", text):
            value = m.group(1)
            if re.search(PACE, value) or set(re.findall(r"\b([A-Za-z_]\w*)\b", value)) & derived:
                continue
            found.append("%s:%d: duration: %s does not read Model.MOTION (one pace for all motion)"
                         % (rel(path), line_of(text, m.start()), value.strip()))
    return found


SIZE_PROPS = r"(?:size|height|implicitHeight|iconSize|Layout\.preferredHeight|Layout\.maximumHeight)"
TOGGLE = os.path.join(ROOT, "FoldToggle.qml")


def one_number(path, pattern, what):
    m = re.search(pattern, blanked(path))
    assert m, "%s no longer says %s" % (rel(path), what)
    return int(m.group(1))


def too_tall(value, limit):
    """None when the value is at most the limit; else why it is not known to be."""
    value = value.strip().rstrip(",")
    m = re.fullmatch(r"Style\.space\((\d+)\)", value)
    if m:
        return None if int(m.group(1)) <= limit else "Style.space(%s) is taller than the header allows (%d)" % (m.group(1), limit)
    if re.fullmatch(r"(?:\w+\.)*headerHeight|Style\.font\.\w+|implicitHeight|(?:\w+\.)*width|(?:parent\.)?height", value):
        return None
    return "bind it to the header's height or write Style.space(N) with N at most %d" % limit


def header_problems(paths):
    """FoldToggle's height is never less than the header's, and what a file
    places between a FoldToggle and its FoldBody (icons, a play button,
    arrows beside the title) is at most that tall."""
    limit = one_number(TOGGLE, r"readonly property real headerHeight:\s*Style\.space\((\d+)\)",
                       "headerHeight: Style.space(N)")
    margin = one_number(os.path.join(ROOT, "AppTile.qml"),
                        r"readonly property int margin:\s*Math\.round\(Style\.space\((\d+)\)\)",
                        "margin: Math.round(Style.space(N))")
    found = []
    toggle = blanked(TOGGLE)
    if not re.search(r"implicitHeight:\s*Math\.max\(\s*foldRow\.implicitHeight\s*,\s*headerHeight\s*\)", toggle):
        found.append("%s:1: implicitHeight is not Math.max(foldRow.implicitHeight, headerHeight): "
                     "a header would change height with what it shows" % rel(TOGGLE))
    for path in paths:
        text = blanked(path)
        regions = []
        if os.path.abspath(path) == TOGGLE:
            regions.append((0, len(text)))
        else:
            for m in re.finditer(r"\bFoldToggle\s*\{", text):
                end = text.find("FoldBody {", m.end())
                regions.append((m.start(), end if end >= 0 else len(text)))
        for start, end in regions:
            for m in re.finditer(r"(?<![\w.])(%s)\s*:\s*([^;\n}]*)" % SIZE_PROPS, text[start:end]):
                if m.group(1) == "implicitHeight" and os.path.abspath(path) == TOGGLE:
                    continue
                room = limit - 2 * margin if m.group(1) == "iconSize" else limit
                why = too_tall(m.group(2), room)
                if why:
                    found.append("%s:%d: %s: %s" % (rel(path), line_of(text, start + m.start()), m.group(0).strip(), why))
    return found


class ShippedQml(unittest.TestCase):
    def test_no_field_sets_its_own_escape(self):
        found = escape_problems(shipped_qml())
        self.assertEqual(found, [], "\n".join(found))

    def test_every_duration_reads_the_one_pace(self):
        found = motion_problems(shipped_qml())
        self.assertEqual(found, [], "\n".join(found))

    def test_nothing_beside_a_title_is_taller_than_the_header(self):
        found = header_problems(shipped_qml())
        self.assertEqual(found, [], "\n".join(found))


class PlantedCases(unittest.TestCase):
    def plant(self, name, source):
        folder = tempfile.mkdtemp()
        self.addCleanup(lambda: (os.remove(os.path.join(folder, name)), os.rmdir(folder)))
        path = os.path.join(folder, name)
        with open(path, "w") as f:
            f.write(source)
        return path

    def test_escape_fails_outside_panelfield_only(self):
        bad = self.plant("Row.qml", "Item {\n  TextEdit { Keys.onEscapePressed: x() }\n  // Keys.onEscapePressed in a comment\n}\n")
        ok = self.plant("PanelField.qml", "Item {\n  Keys.onEscapePressed: x()\n}\n")
        found = escape_problems([bad, ok])
        self.assertEqual(len(found), 1, found)
        self.assertIn("Row.qml:2", found[0])

    def test_motion_fails_on_a_number_and_passes_what_reads_the_pace(self):
        bad = self.plant("Bad.qml", "Item {\n  readonly property int step: Model.MOTION.inMs * 2\n"
                         "  Behavior on x { NumberAnimation { duration: 160 } }\n"
                         "  Behavior on y { NumberAnimation { duration: Model.MOTION.inMs * motion } }\n"
                         "  NumberAnimation { duration: step }\n"
                         "  NumberAnimation { duration: step / 2 }\n"
                         "  RotationAnimator { duration: 1000; loops: Animation.Infinite }\n"
                         "  // duration: 5\n}\n")
        found = motion_problems([bad])
        self.assertEqual([m.split(": duration")[0].rsplit(":", 1)[1] for m in found], ["3", "7"], found)

    def test_header_fails_on_something_taller_than_the_header(self):
        limit = one_number(TOGGLE, r"readonly property real headerHeight:\s*Style\.space\((\d+)\)", "headerHeight")
        ok = self.plant("Ok.qml", "Item {\n  FoldToggle {\n    Text { font.pixelSize: Style.font.icon }\n"
                        "    Item { height: Style.space(%d) }\n  }\n  FoldBody { Item { height: Style.space(%d) } }\n}\n"
                        % (limit, limit + 40))
        bad = self.plant("Bad.qml", "Item {\n  FoldToggle {\n    Item { height: Style.space(%d) }\n"
                         "    Item { height: 30 }\n  }\n  FoldBody { }\n}\n" % (limit + 1))
        self.assertEqual(header_problems([ok]), [])
        self.assertEqual(len(header_problems([bad])), 2, header_problems([bad]))


if __name__ == "__main__":
    unittest.main()
