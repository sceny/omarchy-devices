"""No text field in the shell reads the clipboard until the user pastes.

QQuickTextInput (TextField, TextInput) reads the clipboard's whole text in
q_canPasteChanged: when it stops being read-only and on every clipboard change
while it is editable, with no bound on size. QQuickTextEdit only asks which
formats are offered and reads the text on an explicit paste. Every field is a
PanelField, which is built on a TextEdit; nothing else is an editable input.

A TextEdit inserts a paste, a middle click's selection or a drop whole, and a
few megabytes stall the shell for seconds, so PanelField cuts the clipboard's
text itself at Ctrl+V, takes the middle button and refuses drops.

The read is out of the shell: `Quickshell.clipboardText` reads the whole
clipboard in the shell's process, waiting for the program that offers it, with
no byte limit and no deadline. PanelField runs `wl-paste` in a Process instead,
cut at a byte limit, stopped at a deadline, collected without blocking the
shell. The script is run here against a fake `wl-paste`."""

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
        self.assertIn("pasteRead.running = true", key)
        self.assertNotIn("clipboardText", key)
        fn = text[text.index("function _insert"):]
        fn = fn[:fn.index("readonly property var _borderSpec")]
        self.assertLess(fn.index(".slice("), fn.index(".replace("),
                        "the cut must run before the line-break scan")
        self.assertIn("maximumLength", fn)
        self.assertRegex(fn, r"0xD800")

    def test_the_clipboard_is_read_out_of_the_shell_at_the_paste_key(self):
        text = code(os.path.join(ROOT, "PanelField.qml"))
        self.assertNotIn("clipboardText", text)
        self.assertEqual(len(re.findall(r"\bwl-paste\b", text)), 1)
        self.assertEqual(len(re.findall(r"pasteRead\.running = true", text)), 1)
        self.assertIn("StandardKey.Paste", text[:text.index("pasteRead.running = true")][-300:])
        proc = body(text, re.search(r"\bProcess\s*\{", text).end())
        self.assertIn("StdioCollector", proc)
        self.assertRegex(proc, r"timeout -k \d+ \d+ wl-paste")
        self.assertRegex(proc, r"head -c \d+")
        self.assertRegex(proc, r"iconv -f UTF-8 -t UTF-8 -c")

    def test_the_paste_waits_for_nothing_in_the_shell_and_only_into_a_focused_field(self):
        text = code(os.path.join(ROOT, "PanelField.qml"))
        self.assertRegex(text, r"if \(!pasteRead\.running\) pasteRead\.running = true")
        self.assertRegex(text, r"onStreamFinished:\s*if \(edit\.activeFocus\) field\._insert\(text\)")

    def paste_script(self):
        text = code(os.path.join(ROOT, "PanelField.qml"))
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
