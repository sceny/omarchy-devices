"""The plugin's adb is its own server on a socket in a private folder, never
the TCP port on 127.0.0.1 that every user of the computer can connect to.
Every adb and scrcpy the bridge starts runs with ADB_SERVER_SOCKET set,
`start-server` carries -L, and without the private folder nothing starts.
adb, scrcpy and the processes are replaced; nothing reaches a device."""

import ast
import glob
import importlib.machinery
import importlib.util
import os
import shutil
import stat
import subprocess
import tempfile
import unittest
from unittest import mock

HERE = os.path.dirname(os.path.abspath(__file__))
BRIDGE = os.path.join(HERE, "..", "bin", "kdeconnect-bridge")
loader = importlib.machinery.SourceFileLoader("kdeconnect_bridge_adb_socket", BRIDGE)
spec = importlib.util.spec_from_loader("kdeconnect_bridge_adb_socket", loader)
bridge = importlib.util.module_from_spec(spec)
loader.exec_module(bridge)

PROGRAMS = ("adb", "scrcpy")


def starts_a_program(node):
    """A list literal whose first item is "adb" or "scrcpy": an argv."""
    return (isinstance(node, ast.List) and node.elts and isinstance(node.elts[0], ast.Constant)
            and node.elts[0].value in PROGRAMS)


class Private(unittest.TestCase):
    def setUp(self):
        self.run_dir = tempfile.mkdtemp()
        patch = mock.patch.dict(os.environ, {"XDG_RUNTIME_DIR": self.run_dir, "ADB_SERVER_SOCKET": "tcp:localhost:5037"})
        patch.start()
        self.addCleanup(patch.stop)
        self.addCleanup(shutil.rmtree, self.run_dir, True)
        self.spec = "localfilesystem:" + os.path.join(self.run_dir, "sceny.devices", "adb.sock")

    def test_the_server_is_a_socket_in_a_folder_only_this_user_enters(self):
        self.assertEqual(bridge.adb_server(), self.spec)
        folder = os.path.dirname(self.spec.split(":", 1)[1])
        self.assertEqual(stat.S_IMODE(os.stat(folder).st_mode), 0o700)
        self.assertLess(len(self.spec.split(":", 1)[1]), 100, "a socket path is limited to 107 bytes")

    def test_every_adb_call_names_it_whatever_the_environment_says(self):
        seen = []

        def fake(argv, **kw):
            seen.append((argv, kw.get("env")))
            return subprocess.CompletedProcess(argv, 0, "ok", "")

        with mock.patch.object(bridge.subprocess, "run", fake):
            bridge.adb(["devices", "-l"])
            bridge.adb(["-s", "S1", "shell", "id"])
            bridge.adb(["pair", "192.0.2.20:37099"], stdin="pw\n")
            bridge.adb(["connect", "192.0.2.20:5555"])
            bridge.adb(["start-server"])
        self.assertEqual(len(seen), 5)
        for argv, env in seen:
            self.assertEqual(argv[0], "adb")
            self.assertEqual(env["ADB_SERVER_SOCKET"], self.spec, "the user's own setting does not win: %r" % argv)

    def test_start_server_is_never_without_the_socket(self):
        seen = []
        with mock.patch.object(bridge.subprocess, "run", lambda argv, **kw: seen.append(argv)
                               or subprocess.CompletedProcess(argv, 0, "", "")):
            bridge.adb(["start-server"], timeout=15)
        self.assertEqual(seen, [["adb", "-L", self.spec, "start-server"]])

    def test_the_apps_list_and_the_phone_reader_use_it(self):
        envs = []

        def fake(argv, **kw):
            envs.append((argv[0], kw.get("env")))
            return subprocess.CompletedProcess(argv, 0, "", "")

        bridge.read_apps("S1", run=fake)
        self.assertEqual([p for p, _ in envs], ["scrcpy", "adb"])
        for program, env in envs:
            self.assertEqual(env["ADB_SERVER_SOCKET"], self.spec, program)
        opened = []
        bridge.PhoneReader("S1", popen=lambda argv, **kw: opened.append((argv, kw)) or mock.MagicMock())
        self.assertEqual(opened[0][1]["env"]["ADB_SERVER_SOCKET"], self.spec)

    def test_the_window_is_started_with_it_on_its_line(self):
        # uwsm-app starts the command from its own daemon, not from here.
        for log in ("", "/tmp/screen.log"):
            for package in ("", "com.example.app"):
                cmd = bridge.screen_command("S1", "Pixel 8 · Screen", package, {"flex": True}, log)
                self.assertEqual(cmd[:4], ["uwsm-app", "--", "env", "ADB_SERVER_SOCKET=" + self.spec], cmd)

    def test_no_private_folder_nothing_starts(self):
        for variable in ("", "relative/path"):
            with mock.patch.dict(os.environ, {"XDG_RUNTIME_DIR": variable}):
                self.assertEqual(bridge.adb_server(), "")
                self.assertIsNone(bridge.adb_env())
                with mock.patch.object(bridge.subprocess, "run", side_effect=AssertionError("adb was started")):
                    self.assertEqual(bridge.adb(["start-server"]), (1, bridge.ADB_NO_PLACE))
                    self.assertEqual(bridge.read_apps("S1"), [])
                with self.assertRaises(OSError):
                    bridge.screen_command("S1", "x")
                started = []
                with self.assertRaises(OSError):
                    bridge.PhoneReader("S1", popen=lambda *a, **k: started.append(a))
                self.assertEqual(started, [])


class ShippedCode(unittest.TestCase):
    """Fails the build naming file:line, for code added later."""

    @classmethod
    def setUpClass(cls):
        with open(BRIDGE) as f:
            cls.tree = ast.parse(f.read(), BRIDGE)

    def enclosing(self, target):
        last = None
        for fn in ast.walk(self.tree):
            if isinstance(fn, (ast.FunctionDef, ast.AsyncFunctionDef)) and any(n is target for n in ast.walk(fn)):
                last = fn
        return last.name if last else None

    def test_only_the_four_places_name_adb_or_scrcpy_to_run(self):
        places = {}
        for node in ast.walk(self.tree):
            # Outside a function it is a list of package names, not an argv.
            if starts_a_program(node) and self.enclosing(node):
                places.setdefault(self.enclosing(node), []).append(node.lineno)
        self.assertEqual(sorted(places), sorted(["adb", "read_apps", "__init__", "screen_command"]),
                         "a new place that runs adb or scrcpy: give it adb_env() and add it here: %r" % places)

    def test_each_call_that_runs_one_passes_the_environment(self):
        # adb() runs its argv from a variable; the other three have the list in the call.
        checked = 0
        for node in ast.walk(self.tree):
            if isinstance(node, ast.Call) and node.args and starts_a_program(node.args[0]):
                self.assertTrue(any(k.arg == "env" for k in node.keywords),
                                "kdeconnect-bridge:%d runs %s without env=" % (node.lineno, node.args[0].elts[0].value))
                checked += 1
        self.assertEqual(checked, 3)

    def test_start_server_is_only_asked_of_adb_which_adds_the_socket(self):
        asked = 0
        for call in ast.walk(self.tree):
            if isinstance(call, ast.Call) and any(
                    isinstance(a, ast.List) and any(isinstance(e, ast.Constant) and e.value == "start-server" for e in a.elts)
                    for a in call.args):
                asked += 1
                self.assertTrue(isinstance(call.func, ast.Name) and call.func.id == "adb",
                                "kdeconnect-bridge:%d: start-server goes through adb()" % call.lineno)
        self.assertEqual(asked, 2)

    def test_the_qml_never_starts_adb_or_scrcpy(self):
        for path in glob.glob(os.path.join(HERE, "..", "*.qml")):
            with open(path) as f:
                for number, line in enumerate(f, 1):
                    for program in PROGRAMS:
                        self.assertNotIn('"%s"' % program, line, "%s:%d starts %s outside the bridge" % (os.path.basename(path), number, program))


if __name__ == "__main__":
    unittest.main()
