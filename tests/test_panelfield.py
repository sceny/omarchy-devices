"""No text field in the shell reads the clipboard until the user pastes.

QQuickTextInput (TextField, TextInput) reads the clipboard's whole text in
q_canPasteChanged: when it stops being read-only and on every clipboard change
while it is editable, with no bound on size. QQuickTextEdit only asks which
formats are offered and reads the text on an explicit paste. Every field is a
PanelField, which is built on a TextEdit; nothing else is an editable input.

A TextEdit inserts a paste, a middle click's selection or a drop whole, and a
few megabytes stall the shell for seconds, so PanelField cuts the clipboard's
text itself at Ctrl+V, takes the middle button and refuses drops."""

import glob
import os
import re
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
        self.assertIn("Quickshell.clipboardText", key)
        fn = text[text.index("function _insert"):]
        fn = fn[:fn.index("readonly property var _borderSpec")]
        self.assertLess(fn.index(".slice("), fn.index(".replace("),
                        "the cut must run before the line-break scan")
        self.assertIn("maximumLength", fn)
        self.assertRegex(fn, r"0xD800")

    def test_clipboard_text_is_read_only_at_the_paste_key(self):
        text = code(os.path.join(ROOT, "PanelField.qml"))
        reads = [m.start() for m in re.finditer(r"clipboardText", text)]
        self.assertEqual(len(reads), 1)
        self.assertIn("StandardKey.Paste", text[:reads[0]][-300:])

    def test_middle_click_and_drops_do_not_reach_the_text_edit(self):
        text = code(os.path.join(ROOT, "PanelField.qml"))
        area = re.search(r"MouseArea\s*\{([^}]*)\}", text)
        self.assertIsNotNone(area)
        self.assertIn("acceptedButtons: Qt.MiddleButton", area.group(1))
        self.assertIn("anchors.fill: edit", area.group(1))
        drop = re.search(r"DropArea\s*\{(.*?)\n    \}", text, flags=re.S)
        self.assertIsNotNone(drop)
        self.assertIn("anchors.fill: edit", drop.group(1))
        self.assertRegex(drop.group(1), r"drop\.accepted = false")


if __name__ == "__main__":
    unittest.main()
