"""dev/loaded-code: the functions the files declare against the functions the
running shell lists. The shell's `ipc show` is replaced by a file."""

import importlib.machinery
import importlib.util
import json
import os
import subprocess
import tempfile
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
SCRIPT = os.path.join(HERE, "..", "dev", "loaded-code")

QML = """Item {
  IpcHandler {
    target: root.ipcTarget
    function open(): void { root.go() }
    function status(): string { return JSON.stringify({a: 1}) }
    function newOne(): string { return "x" }
  }
  function notIpc(): void {}
}
"""

SHOW = """target other
  function open(): void
target sceny.test
  function open(): void
  function status(): string
"""


def run(qml, show):
    with tempfile.TemporaryDirectory() as d:
        open(os.path.join(d, "manifest.json"), "w").write(json.dumps({"id": "sceny.test"}))
        open(os.path.join(d, "Panel.qml"), "w").write(qml)
        shown = os.path.join(d, "show.txt")
        open(shown, "w").write(show)
        env = dict(os.environ, LOADED_CODE_SHOW_CMD=f"cat {shown}")
        return subprocess.run(["python3", SCRIPT, d], env=env, capture_output=True, text=True)


class LoadedCode(unittest.TestCase):
    def test_older_running_code_is_reported(self):
        done = run(QML, SHOW)
        self.assertEqual(done.returncode, 1)
        self.assertIn("newOne", done.stdout)
        self.assertNotIn("notIpc", done.stdout)

    def test_matching_code(self):
        done = run(QML.replace("    function newOne(): string { return \"x\" }\n", ""), SHOW)
        self.assertEqual(done.returncode, 0, done.stdout)

    def test_removed_function_is_reported(self):
        done = run(QML.replace("newOne", "status"), SHOW)
        self.assertEqual(done.returncode, 0, done.stdout)
        done = run(QML.replace("    function status(): string { return JSON.stringify({a: 1}) }\n", "")
                   .replace("    function newOne(): string { return \"x\" }\n", ""), SHOW)
        self.assertEqual(done.returncode, 1)
        self.assertIn("no longer have: status", done.stdout)

    def test_missing_target(self):
        done = run(QML, "target other\n  function open(): void\n")
        self.assertEqual(done.returncode, 2)


if __name__ == "__main__":
    unittest.main()
