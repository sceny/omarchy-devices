"""No editable text field exists while it is not in use.

Qt reads the whole clipboard text on every clipboard change in each editable
TextField, shown or hidden (QQuickTextInput::q_canPasteChanged), so a hidden
field lets another process make the shell read its payload. A read-only field
skips it. Every field is a PanelField, which is read-only unless it has the
keyboard."""

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


class PanelFieldClipboard(unittest.TestCase):
    def test_only_panelfield_makes_an_editable_input(self):
        for path in sorted(glob.glob(os.path.join(ROOT, "*.qml"))):
            name = os.path.basename(path)
            if name == "PanelField.qml":
                continue
            text = code(path)
            self.assertIsNone(re.search(r"\b(TextField|TextInput|TextArea)\s*\{", text),
                              f"{name}: use PanelField")
            for m in re.finditer(r"\bTextEdit\s*\{", text):
                depth, i = 1, m.end()
                while depth:
                    depth += {"{": 1, "}": -1}.get(text[i], 0)
                    i += 1
                self.assertRegex(text[m.end():i], r"\breadOnly:\s*true\b",
                                 f"{name}: a TextEdit must be read-only")

    def test_panelfield_is_read_only_until_focused(self):
        text = code(os.path.join(ROOT, "PanelField.qml"))
        self.assertRegex(text, r"(?m)^\s*readOnly:\s*true\s*$")
        self.assertRegex(text, r"onActiveFocusChanged:[^}]*readOnly\s*=\s*!activeFocus")
        self.assertRegex(text, r"Component\.onCompleted:\s*readOnly\s*=\s*!activeFocus")


if __name__ == "__main__":
    unittest.main()
