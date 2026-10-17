"""No text field in the shell reads the clipboard until the user pastes.

QQuickTextInput (TextField, TextInput) reads the clipboard's whole text in
q_canPasteChanged: when it stops being read-only and on every clipboard change
while it is editable, with no bound on size. QQuickTextEdit only asks which
formats are offered and reads the text on an explicit paste. Every field is a
PanelField, which is built on the one TextEdit; read-only text is a Text, which
has no selection, copy or keys in Qt.

A TextEdit inserts a paste whole, and a few megabytes stall the shell for
seconds, so PanelField cuts the clipboard's text itself at Ctrl+V; the mouse
never reaches its TextEdit, so a middle click pastes nothing, and a TextEdit
takes no drops.

The read is out of the shell: `Quickshell.clipboardText` reads the whole
clipboard in the shell's process, waiting for the program that offers it, with
no byte limit and no deadline. `Clipboard.qml` (the one door, docs/architecture/
001) runs `wl-paste` in a Process instead, cut at a byte limit, stopped at a
deadline, collected without blocking the shell. The script is run here against
a fake `wl-paste`.

Nothing in the shell is a party to a Wayland data transfer: no text item owns
the primary selection or the clipboard (Qt does on its own selection, by mouse
or by key, and on its own copy), reads it (paste, middle click, a drop), or
starts a drag out. `ShippedQml` lints every shipped QML file for it and names
file:line; `dev/clip-check` shows it in a running rig."""

import glob
import os
import re
import shutil
import signal
import subprocess
import tempfile
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.join(HERE, "..")


def code(path):
    with open(path) as f:
        text = f.read()
    text = re.sub(r"/\*.*?\*/", "", text, flags=re.S)
    return re.sub(r"//[^\n]*", "", text)


def body(text, start):
    depth, i = 1, start
    while depth:
        depth += {"{": 1, "}": -1}.get(text[i], 0)
        i += 1
    return text[start:i]


class PanelFieldClipboard(unittest.TestCase):
    def test_no_text_input_type_anywhere(self):
        for path in sorted(glob.glob(os.path.join(ROOT, "*.qml"))):
            name = os.path.basename(path)
            self.assertIsNone(re.search(r"\b(TextField|TextInput|TextArea)\s*\{", code(path)),
                              f"{name}: use PanelField, which is not built on QQuickTextInput")

    def test_panelfield_is_one_plain_text_edit_that_never_toggles_read_only(self):
        text = code(os.path.join(ROOT, "PanelField.qml"))
        edits = list(re.finditer(r"\bTextEdit\s*\{", text))
        self.assertEqual(len(edits), 1)
        inner = body(text, edits[0].end())
        self.assertRegex(inner, r"textFormat:\s*TextEdit\.PlainText")
        self.assertNotRegex(text, r"\breadOnly\b")
        self.assertNotRegex(text, r"\bcanPaste\b")

    def test_a_field_is_capped_before_anything_reads_its_text(self):
        text = code(os.path.join(ROOT, "PanelField.qml"))
        self.assertRegex(text, r"property int maximumLength:\s*32767")
        handler = text[text.index("onTextChanged:"):]
        cap = handler.index("maximumLength")
        scan = handler.index("breaks.test")
        self.assertLess(cap, scan, "the cap must run before the line-break scan")
        self.assertRegex(handler[cap:scan], r"remove\(")

    def test_text_is_cut_before_qt_inserts_it(self):
        text = code(os.path.join(ROOT, "PanelField.qml"))
        key = text[text.index("Keys.onPressed:"):]
        key = key[:key.index("Keys.forwardTo")]
        self.assertIn("StandardKey.Paste", key)
        self.assertIn("event.accepted = true", key)
        self.assertIn("Clipboard.readInto(", key)
        self.assertNotIn("clipboardText", key)
        fn = text[text.index("function _insert"):]
        fn = fn[:fn.index("readonly property var _borderSpec")]
        self.assertLess(fn.index(".slice("), fn.index(".replace("),
                        "the cut must run before the line-break scan")
        self.assertIn("maximumLength", fn)
        self.assertRegex(fn, r"0xD800")

    def test_the_clipboard_is_read_out_of_the_shell_at_the_paste_key(self):
        field = code(os.path.join(ROOT, "PanelField.qml"))
        self.assertNotIn("clipboardText", field)
        self.assertNotRegex(field, r"\bwl-(paste|copy)\b")
        self.assertIn("StandardKey.Paste", field[:field.index("Clipboard.readInto(")][-300:])
        text = code(os.path.join(ROOT, "Clipboard.qml"))
        self.assertEqual(len(re.findall(r"\bwl-paste\b", text)), 1)
        self.assertEqual(len(re.findall(r"_read\.running = true", text)), 1)
        proc = body(text, re.search(r"\bid:\s*_read\b", text).end())
        self.assertIn("StdioCollector", proc)
        self.assertRegex(proc, r"timeout -k \d+ \d+ wl-paste")
        self.assertRegex(proc, r"head -c \d+")
        self.assertRegex(proc, r"iconv -f UTF-8 -t UTF-8 -c")

    def test_no_qml_file_reads_quickshell_clipboard_text(self):
        for path in sorted(glob.glob(os.path.join(ROOT, "*.qml"))):
            self.assertNotRegex(code(path), r"\bclipboardText\b",
                                f"{os.path.basename(path)}: Quickshell.clipboardText reads the clipboard in the shell, unbounded")

    def test_the_paste_waits_for_nothing_in_the_shell_and_only_into_a_focused_field(self):
        text = code(os.path.join(ROOT, "PanelField.qml"))
        self.assertRegex(text, r"Clipboard\.readInto\(function\(incoming\) \{ if \(edit\.activeFocus\) field\._insert\(incoming\) \}\)")
        door = code(os.path.join(ROOT, "Clipboard.qml"))
        self.assertRegex(door, r"if \(_read\.running\) return false")
        self.assertRegex(door, r"readWatchdog\.restart\(\)")
        self.assertRegex(door, r'_read\.running = false; clipboard\._readEnded\(""\)')

    def paste_script(self):
        text = code(os.path.join(ROOT, "Clipboard.qml"))
        m = re.search(r'command:\s*\["bash",\s*"-c",\s*"((?:[^"\\]|\\.)*)"\]', text)
        self.assertIsNotNone(m)
        return re.sub(r"\\(.)", r"\1", m.group(1))

    def run_paste(self, mode, limit=20):
        script = self.paste_script()
        with tempfile.TemporaryDirectory(dir=ROOT) as d:
            fake = os.path.join(d, "wl-paste")
            with open(fake, "w") as f:
                f.write("#!/bin/sh\ncase \"$MODE\" in\n"
                        " text) printf 'h\\303\\251llo\\nworld' ;;\n"
                        " endless) exec yes 'x' ;;\n"
                        " euro) yes \"$(printf '\\342\\202\\254')\" | tr -d '\\n' ;;\n"
                        " stall) printf partial; echo $$ > \"$PIDFILE\"; exec sleep 600 ;;\n"
                        " fail) printf partial; exit 1 ;;\n"
                        "esac\n")
            os.chmod(fake, 0o755)
            proc = subprocess.Popen(["bash", "-c", "export PATH=%s:$PATH; %s" % (d, script)],
                                    env={**os.environ, "MODE": mode, "PIDFILE": os.path.join(d, "pid")},
                                    stdout=subprocess.PIPE, stderr=subprocess.PIPE, start_new_session=True)
            try:
                out, err = proc.communicate(timeout=limit)
            except subprocess.TimeoutExpired:
                os.killpg(proc.pid, signal.SIGKILL)
                proc.communicate()
                raise
            return subprocess.CompletedProcess(proc.args, proc.returncode, out, err)

    @unittest.skipUnless(shutil.which("timeout") and shutil.which("iconv"), "needs coreutils and iconv")
    def test_the_read_script_against_a_fake_clipboard(self):
        ok = self.run_paste("text")
        self.assertEqual(ok.stdout.decode(), "h\u00e9llo\nworld")
        self.assertEqual(ok.stderr, b"")
        endless = self.run_paste("endless")
        self.assertIn(len(endless.stdout), (131071, 131072))
        euro = self.run_paste("euro").stdout
        self.assertLessEqual(len(euro), 131072)
        euro.decode("utf-8")
        self.assertEqual(len(euro), 131070)
        self.assertTrue(euro.endswith("\u20ac".encode()))
        self.assertEqual(self.run_paste("fail").stdout, b"")

    @unittest.skipUnless(shutil.which("timeout") and shutil.which("iconv"), "needs coreutils and iconv")
    def test_a_stalled_provider_inserts_nothing_after_the_deadline(self):
        # The provider holds for 600 s and the run is given 120: the script
        # returns only because its own deadline (2 s, a kill at 3 s) stopped
        # the provider, whatever the machine's load. No wall-clock bound
        # tighter than that is asserted, since load stretches it.
        stalled = self.run_paste("stall", limit=120)
        self.assertEqual(stalled.stdout, b"")

    def test_the_text_edit_takes_no_selection_from_qt(self):
        text = code(os.path.join(ROOT, "PanelField.qml"))
        edit = body(text, re.search(r"\bTextEdit\s*\{", text).end())
        self.assertRegex(edit, r"selectByMouse:\s*false")
        key = edit[edit.index("Keys.onPressed:"):edit.index("Keys.forwardTo")]
        for name in ("Paste", "Copy", "Cut", "SelectAll"):
            self.assertIn("StandardKey.%s" % name, key)
        # Every selection key Qt would act on is the field's: Qt's handling of
        # it ends at `accept:`, which makes the shell the primary selection's
        # owner (qquicktextcontrol.cpp, setClipboardSelection).
        target = text[text.index("function _selectTarget"):text.index("function _low")]
        for name in SELECT_KEYS:
            self.assertIn("StandardKey.%s" % name, target, name)
        self.assertIn("field._selectTarget(event)", key)
        self.assertIn("moveCursorSelection(", key)
        self.assertRegex(key, r"Qt\.Key_Direction_L \|\| event\.key === Qt\.Key_Direction_R\) \{\s*event\.accepted = true")
        # While a selection stands, any other key finds it gone.
        rest = key[key.index("!field._keepsSelection(event)"):]
        self.assertIn("else deselect()", rest)

    def test_only_keys_that_remove_a_selection_reach_qt_with_one(self):
        text = code(os.path.join(ROOT, "PanelField.qml"))
        keeps = text[text.index("function _keepsSelection"):text.index("function _anchor")]
        for name in ("Delete", "DeleteStartOfWord", "DeleteEndOfWord", "DeleteEndOfLine"):
            self.assertIn("StandardKey.%s" % name, keeps)
        self.assertIn("Qt.Key_Backspace && !(event.modifiers & ~Qt.ShiftModifier)", keeps)
        self.assertNotRegex(keeps, r"Undo|Redo|Key_Home|Key_End|Key_Up|Key_Down")

    def test_the_mouse_never_reaches_the_text_edit(self):
        text = code(os.path.join(ROOT, "PanelField.qml"))
        area = body(text, re.search(r"\bMouseArea\s*\{", text).end())
        self.assertIn("anchors.fill: parent", area)
        self.assertIn("Qt.LeftButton | Qt.MiddleButton", area)
        self.assertRegex(area, r"if \(m\.button !== Qt\.LeftButton\) return")
        self.assertIn("field._selectWord(", area)
        self.assertIn("edit.selectAll()", area)
        self.assertGreater(text.index("MouseArea"), text.index("TextEdit {"), "the MouseArea is over the TextEdit")
        self.assertNotIn("DropArea", text)


# Every selection key of QKeySequence::StandardKey.
SELECT_KEYS = ("SelectNextChar", "SelectPreviousChar", "SelectNextWord", "SelectPreviousWord",
               "SelectStartOfLine", "SelectEndOfLine", "SelectStartOfBlock", "SelectEndOfBlock",
               "SelectStartOfDocument", "SelectEndOfDocument", "SelectNextLine", "SelectPreviousLine",
               "SelectNextPage", "SelectPreviousPage")


SKIP_DIRS = {"dev", "tests", ".git", ".claude", ".paperclip", "docs", "node_modules"}


def shipped_qml():
    out = []
    for folder, dirs, files in os.walk(ROOT):
        dirs[:] = [d for d in dirs if d not in SKIP_DIRS and not d.startswith(".")]
        out += [os.path.join(folder, f) for f in files if f.endswith(".qml")]
    return sorted(out)


def line_of(text, index):
    return text.count("\n", 0, index) + 1


def top_level(inner):
    """An object's body with its children's bodies blanked, offsets kept."""
    while re.search(r"\{[^{}]*\}", inner):
        inner = re.sub(r"\{[^{}]*\}", lambda m: re.sub(r"[^\n]", " ", m.group(0)), inner)
    return inner


# A property written as this literal and nothing more.
def literal(prop, value):
    return r"\b%s\s*:\s*%s(?=\s*(?:[;}]|\n|$))" % (prop, value)


PANELFIELD = os.path.abspath(os.path.join(ROOT, "PanelField.qml"))


def clipboard_door_problems(path, text=None):
    """file:line of every way a QML file takes part in a clipboard transfer."""
    name = os.path.relpath(path, ROOT)
    text = code(path) if text is None else text
    rules = [
        (r"\bselectByMouse\s*[:=]\s*true\b", "selectByMouse: true makes Qt own the primary selection"),
        (r"\bselectByKeyboard\s*[:=]\s*true\b", "selectByKeyboard: true makes Qt own the primary selection"),
        (r"\bDrag\.(?:Automatic|dragType|mimeData)\b|\bstartDrag\(", "a system drag makes the shell its source"),
        (r"\bDropArea\b", "a DropArea makes the shell a drop target (a TextEdit takes no drops)"),
        (r"\.(?:copy|cut|paste)\(\s*\)", "a text item's own copy, cut or paste: the shell serves or reads it"),
        (r"\bclipboardText\b", "Quickshell.clipboardText reads the clipboard in the shell, unbounded"),
    ]
    if os.path.basename(path) != "Clipboard.qml":
        rules.append((r"\bwl-(?:copy|paste)\b", "wl-copy / wl-paste belong in Clipboard.qml, the one door"))
    found = []
    for pattern, why in rules:
        found += ["%s:%d: %s" % (name, line_of(text, m.start()), why) for m in re.finditer(pattern, text)]
    for m in re.finditer(r"\bTextEdit\s*\{", text):
        at = line_of(text, m.start())
        # The one TextEdit is PanelField's, which owns its selection, keys and
        # mouse. Anywhere else, Qt's own copy and Select-All keys (they check
        # no flag) or its mouse selection would make the shell the owner;
        # read-only text is a Text, which has no selection, copy or keys.
        if os.path.abspath(path) != PANELFIELD:
            found.append("%s:%d: a TextEdit outside PanelField: read-only text is a Text "
                         "(no selection, copy or keys in Qt)" % (name, at))
        elif not re.search(literal("selectByMouse", "false"), top_level(body(text, m.end()))):
            found.append("%s:%d: a TextEdit says selectByMouse: false (Qt 6 may default it on)" % (name, at))
    return found


QML_TESTS = os.path.join(HERE, "qml")
QMLTESTRUNNER = next((p for p in ("/usr/lib/qt6/bin/qmltestrunner", "/usr/lib/x86_64-linux-gnu/qt6/bin/qmltestrunner")
                      if os.path.exists(p)), shutil.which("qmltestrunner"))


def run_qml_tests(mutation=None):
    """PanelField (optionally with one text replaced) under qmltestrunner,
    offscreen, next to a stub Clipboard; the shell's own modules are stubs
    in tests/qml/stubs. Returns the failing test names and the output."""
    with tempfile.TemporaryDirectory() as work:
        with open(os.path.join(ROOT, "PanelField.qml")) as f:
            source = f.read()
        if mutation:
            old, new = mutation
            assert old in source, old
            source = source.replace(old, new, 1)
        with open(os.path.join(work, "PanelField.qml"), "w") as f:
            f.write(source)
        for name in ("Clipboard.qml", "tst_panelfield.qml"):
            shutil.copy(os.path.join(QML_TESTS, name), work)
        with open(os.path.join(work, "qmldir"), "w") as f:
            f.write("singleton Clipboard 1.0 Clipboard.qml\nPanelField 1.0 PanelField.qml\n")
        env = dict(os.environ, QT_QPA_PLATFORM="offscreen")
        out = subprocess.run([QMLTESTRUNNER, "-import", os.path.join(QML_TESTS, "stubs"), "-input", work],
                             env=env, capture_output=True, text=True, timeout=120)
    text = out.stdout + out.stderr
    return re.findall(r"^FAIL!\s*:\s*\S+::(\w+)\(\)", text, flags=re.M), text, out.returncode


@unittest.skipUnless(QMLTESTRUNNER or os.environ.get("CI"), "qmltestrunner (Qt 6 declarative tools) is not installed")
class PanelFieldBehaviour(unittest.TestCase):
    """The field run headless: a selection never stands where Qt could make
    the shell its owner, and the mouse is the field's own. The text lints in
    ShippedQml cannot tell a guard from a guard that no longer runs; each
    mutation below removes one guard and must fail a test."""

    def test_the_field_behaves(self):
        failed, text, code_ = run_qml_tests()
        self.assertEqual((failed, code_), ([], 0), text)

    def test_each_removed_guard_fails_a_test(self):
        mutations = {
            "a selection never lets a key past": (
                "function _keepsSelection(event) {", "function _keepsSelection(event) { return true"),
            "the control and meta keys count as text": (" && !ctrl", ""),
            "the mouse area is under the text": (
                "  MouseArea {\n    anchors.fill: parent", "  MouseArea {\n    z: -1\n    anchors.fill: parent"),
            "the mouse area is off": (
                "acceptedButtons: Qt.LeftButton | Qt.MiddleButton",
                "enabled: false\n    acceptedButtons: Qt.LeftButton | Qt.MiddleButton"),
        }
        for name, mutation in mutations.items():
            with self.subTest(name):
                failed, text, _ = run_qml_tests(mutation)
                self.assertTrue(failed, "no test noticed: " + name + "\n" + text)


class ShippedQml(unittest.TestCase):
    def test_no_shipped_file_takes_part_in_a_clipboard_transfer(self):
        found = [p for path in shipped_qml() for p in clipboard_door_problems(path)]
        self.assertEqual(found, [], "\n" + "\n".join(found))

    def test_clipboard_is_the_one_singleton_door(self):
        with open(os.path.join(ROOT, "qmldir")) as f:
            self.assertRegex(f.read(), r"singleton\s+Clipboard\s+\S+\s+Clipboard\.qml")
        self.assertTrue(code(os.path.join(ROOT, "Clipboard.qml")).lstrip().startswith("pragma Singleton"))

    def test_the_lint_finds_each_way_in_and_names_the_line(self):
        with tempfile.TemporaryDirectory() as d:
            path = os.path.join(d, "Bad.qml")
            with open(path, "w") as f:
                f.write("Item {\n  TextEdit { selectByMouse: true }\n  Item { Drag.dragType: Drag.Automatic }\n"
                        "  onX: y = Quickshell.clipboardText\n  Process { command: [\"wl-copy\", note] }\n"
                        "  TextEdit { readOnly: true; selectByMouse: false }\n  // selectByMouse: true in a comment\n"
                        "  DropArea { }\n  function f() { edit.copy(); edit.paste() }\n"
                        "  TextEdit { selectByMouse: false; selectByKeyboard: true }\n"
                        "  Text { textFormat: Text.PlainText; wrapMode: TextEdit.Wrap }\n"
                        "  TextEdit { selectByMouse : true }\n  function g() { edit.selectByMouse = true }\n"
                        "  Item { function h() { Drag.startDrag() } }\n}\n")
            found = clipboard_door_problems(path)
            for line in (2, 3, 4, 5, 6, 8, 9, 10, 12, 13, 14):
                self.assertTrue(any(":%d:" % line in one for one in found), (line, found))
            self.assertFalse(any(":7:" in one or ":11:" in one for one in found), found)

    def test_the_one_text_edit_is_panelfields(self):
        # Read-only text outside PanelField is a Text: a TextEdit there, however
        # it is written, fails at its line, so no rule about its focus is needed.
        cases = [
            "TextEdit { readOnly: true; selectByMouse: false; activeFocusOnPress: false; focus: false }",
            "TextEdit { id: shown; readOnly: true; selectByMouse: false }",
            "Item { TextEdit { } }",
            "Component { TextEdit { readOnly: true } }",
            "TextEdit{ }",
        ]
        quiet = [
            "Text { textFormat: Text.PlainText; wrapMode: TextEdit.Wrap }",
            "PanelField { }",
            "// TextEdit { in a comment }",
        ]
        with tempfile.TemporaryDirectory() as d:
            path = os.path.join(d, "PanelField.qml")
            for source in cases:
                with open(path, "w") as f:
                    f.write("Item {\n  %s\n}\n" % source)
                found = clipboard_door_problems(path)
                self.assertTrue(any(":2: a TextEdit outside PanelField" in one for one in found), (source, found))
            for source in quiet:
                with open(path, "w") as f:
                    f.write("Item {\n  %s\n}\n" % source)
                self.assertEqual(clipboard_door_problems(path), [], source)


if __name__ == "__main__":
    unittest.main()
