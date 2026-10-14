"""No text field in the shell reads the clipboard until the user pastes.

QQuickTextInput (TextField, TextInput) reads the clipboard's whole text in
q_canPasteChanged: when it stops being read-only and on every clipboard change
while it is editable, with no bound on size. QQuickTextEdit only asks which
formats are offered and reads the text on an explicit paste. Every field is a
PanelField, which is built on a TextEdit; nothing else is an editable input.

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
import subprocess
import tempfile
import time
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

    def test_other_text_edits_are_read_only(self):
        for path in sorted(glob.glob(os.path.join(ROOT, "*.qml"))):
            name = os.path.basename(path)
            if name == "PanelField.qml":
                continue
            text = code(path)
            for m in re.finditer(r"\bTextEdit\s*\{", text):
                self.assertRegex(body(text, m.end()), r"\breadOnly:\s*true\b",
                                 f"{name}: a TextEdit outside PanelField must be read-only")

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

    def run_paste(self, mode):
        script = self.paste_script()
        with tempfile.TemporaryDirectory(dir=ROOT) as d:
            fake = os.path.join(d, "wl-paste")
            with open(fake, "w") as f:
                f.write("#!/bin/sh\ncase \"$MODE\" in\n"
                        " text) printf 'h\\303\\251llo\\nworld' ;;\n"
                        " endless) exec yes 'x' ;;\n"
                        " euro) yes \"$(printf '\\342\\202\\254')\" | tr -d '\\n' ;;\n"
                        " stall) printf partial; exec sleep 30 ;;\n"
                        " fail) printf partial; exit 1 ;;\n"
                        "esac\n")
            os.chmod(fake, 0o755)
            return subprocess.run(["bash", "-c", "export PATH=%s:$PATH; %s" % (d, script)],
                                  env={**os.environ, "MODE": mode}, capture_output=True,
                                  timeout=20)

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
        started = time.monotonic()
        stalled = self.run_paste("stall")
        self.assertEqual(stalled.stdout, b"")
        self.assertLess(time.monotonic() - started, 5)

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


def clipboard_door_problems(path, text=None):
    """file:line of every way a QML file takes part in a clipboard transfer."""
    name = os.path.relpath(path, ROOT)
    text = code(path) if text is None else text
    rules = [
        (r"\bselectByMouse:\s*true\b", "selectByMouse: true makes Qt own the primary selection"),
        (r"\bselectByKeyboard:\s*true\b", "selectByKeyboard: true makes Qt own the primary selection"),
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
        inner = body(text, m.end())
        if not re.search(r"\bselectByMouse:\s*false\b", inner):
            found.append("%s:%d: a TextEdit says selectByMouse: false (Qt 6 may default it on)" % (name, line_of(text, m.start())))
        if re.search(r"\breadOnly:\s*true\b", inner) and not re.search(r"\bactiveFocusOnPress:\s*false\b", inner):
            found.append("%s:%d: a read-only TextEdit takes no focus (activeFocusOnPress: false): "
                         "Qt's copy and Select-All keys check no flag" % (name, line_of(text, m.start())))
    return found


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
                        "  TextEdit { readOnly: true; selectByMouse: false; activeFocusOnPress: false }\n}\n")
            found = clipboard_door_problems(path)
            for line in (2, 3, 4, 5, 6, 8, 9, 10):
                self.assertTrue(any(":%d:" % line in one for one in found), (line, found))
            self.assertFalse(any(":7:" in one or ":11:" in one for one in found), found)


if __name__ == "__main__":
    unittest.main()
