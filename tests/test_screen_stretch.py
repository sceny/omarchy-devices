"""The screen's picture filling its window (scrcpy's --render-fit=stretched):
the command, what this scrcpy offers, the opening that asks for it and the
open window opened again with it. Windows and the device are made up;
nothing opens."""

import importlib.machinery
import importlib.util
import os
import shutil
import subprocess
import tempfile
import unittest
from unittest import mock

HERE = os.path.dirname(os.path.abspath(__file__))
BRIDGE = os.path.join(HERE, "..", "bin", "kdeconnect-bridge")
loader = importlib.machinery.SourceFileLoader("kdeconnect_bridge_stretch", BRIDGE)
spec = importlib.util.spec_from_loader("kdeconnect_bridge_stretch", loader)
bridge = importlib.util.module_from_spec(spec)
loader.exec_module(bridge)

STRETCH = "--render-fit=stretched"


class Runtime(unittest.TestCase):
    def setUp(self):
        run = tempfile.mkdtemp()
        patch = mock.patch.dict(os.environ, {"XDG_RUNTIME_DIR": run})
        patch.start()
        self.addCleanup(patch.stop)
        self.addCleanup(shutil.rmtree, run, True)


class Command(Runtime):

    def test_the_screen_asks_when_chosen_and_this_scrcpy_has_it(self):
        self.assertIn(STRETCH, bridge.screen_command("S1", "Pixel 8 · Screen", tools={"stretch": True}, stretch=True))
        self.assertNotIn(STRETCH, bridge.screen_command("S1", "Pixel 8 · Screen", tools={"stretch": True}))
        self.assertNotIn(STRETCH, bridge.screen_command("S1", "Pixel 8 · Screen", tools={"stretch": False}, stretch=True),
                         "a scrcpy without the option is not asked for it")
        self.assertNotIn(STRETCH, bridge.screen_command("S1", "Pixel 8 · Screen", stretch=True))

    def test_an_apps_window_follows_its_size_and_is_never_stretched(self):
        cmd = bridge.screen_command("S1", "Maps · Pixel 8", "com.example.maps", {"flex": True, "stretch": True}, stretch=True)
        self.assertNotIn(STRETCH, cmd)

    def test_the_tools_say_whether_scrcpy_has_it(self):
        def run(has):
            def go(cmd, **kw):
                text = "scrcpy 3.3.1 <https://example.invalid>" if "--version" in cmd else ("    --render-fit=mode\n" if has else "    --no-audio\n")
                return subprocess.CompletedProcess(cmd, 0, stdout=text)
            return go
        with mock.patch.object(bridge.shutil, "which", lambda name: "/usr/bin/" + name):
            self.assertTrue(bridge.screen_tools(run(True))["stretch"])
            self.assertFalse(bridge.screen_tools(run(False))["stretch"])


class Opening(Runtime):
    def open(self, stretch):
        launched = []
        names = ["screen_status", "find_window", "hypr_json", "border_size", "screen_device", "say", "screen_log"]
        saved = {n: getattr(bridge, n) for n in names}
        saved_run = bridge.subprocess.run
        windows = iter([None, {"address": "0x1"}])
        try:
            bridge.screen_status = lambda d: {"state": "ready", "apps": True, "serial": "s", "display": [1080, 2340],
                                              "tools": {"flex": True, "stretch": True}}
            bridge.find_window = lambda title: next(windows, {"address": "0x1"})
            bridge.hypr_json = lambda what: [{"focused": True, "reserved": [0, 30, 0, 0]}]
            bridge.border_size = lambda: 2
            bridge.screen_device = lambda d: {"name": "Pixel 8"}
            bridge.say = lambda message, code=0, osd=None: code
            bridge.screen_log = lambda title: ""
            bridge.subprocess.run = lambda cmd, **kw: None
            code = bridge.screen_open("dev", docked=False, launch=launched.append, sleep=lambda s: None, stretch=stretch)
        finally:
            for n, v in saved.items():
                setattr(bridge, n, v)
            bridge.subprocess.run = saved_run
        return code, launched[0]

    def test_the_opening_carries_the_choice(self):
        self.assertIn(STRETCH, self.open(True)[1])
        self.assertNotIn(STRETCH, self.open(False)[1])


class Reopen(Runtime):
    def reopen(self, window, stretch, state="ready", has=True):
        got = {}
        names = ["screen_device", "find_window", "screen_status", "reopen_open_window", "window_sounds", "say"]
        saved = {n: getattr(bridge, n) for n in names}
        try:
            bridge.screen_device = lambda d: {"name": "Pixel 8"}
            bridge.find_window = lambda title: window
            bridge.screen_status = lambda d: {"state": state, "serial": "s", "tools": {"stretch": has}}
            bridge.window_sounds = lambda d: {"@screen": "phone"}

            def again(device, package, title, win, status, command, launch=None, sleep=None):
                got["cmd"] = command("")
                return True
            bridge.reopen_open_window = again
            bridge.say = lambda message, code=0, osd=None: code
            got["code"] = bridge.screen_stretch("dev", stretch)
        finally:
            for n, v in saved.items():
                setattr(bridge, n, v)
        return got

    def test_an_open_screen_opens_again_with_the_choice_and_its_sound(self):
        got = self.reopen({"address": "0x1"}, True)
        self.assertEqual(got["code"], bridge.EXIT_OK)
        self.assertIn(STRETCH, got["cmd"])
        self.assertIn("--no-audio", got["cmd"], "the screen's sound stays where it was put")
        self.assertNotIn(STRETCH, self.reopen({"address": "0x1"}, False)["cmd"])

    def test_nothing_open_nothing_to_do(self):
        got = self.reopen(None, True)
        self.assertEqual(got, {"code": bridge.EXIT_OK})

    def test_out_of_reach_or_without_the_option_it_says_so(self):
        self.assertEqual(self.reopen({"address": "0x1"}, True, state="away")["code"], bridge.EXIT_FAILED)
        self.assertEqual(self.reopen({"address": "0x1"}, True, has=False)["code"], bridge.EXIT_FAILED)


if __name__ == "__main__":
    unittest.main()
