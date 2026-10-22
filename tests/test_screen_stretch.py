"""The screen's picture filling its window (--render-fit=stretched): the
tools that offer it, scrcpy's arguments, and the open window opened again
in its place with it (kdeconnect-bridge). Windows and the device are made
up; nothing opens and nothing reaches a device."""

import importlib.machinery
import importlib.util
import os
import shutil
import tempfile
import unittest
from unittest import mock

HERE = os.path.dirname(os.path.abspath(__file__))
BRIDGE = os.path.join(HERE, "..", "bin", "kdeconnect-bridge")
loader = importlib.machinery.SourceFileLoader("kdeconnect_bridge_stretch", BRIDGE)
spec = importlib.util.spec_from_loader("kdeconnect_bridge_stretch", loader)
bridge = importlib.util.module_from_spec(spec)
loader.exec_module(bridge)

TOOLS = {"flex": True, "renderFit": True}


class Arguments(unittest.TestCase):
    def setUp(self):
        run = tempfile.mkdtemp()
        patch = mock.patch.dict(os.environ, {"XDG_RUNTIME_DIR": run})
        patch.start()
        self.addCleanup(patch.stop)
        self.addCleanup(shutil.rmtree, run, True)

    def test_the_screen_fills_its_window_when_asked_and_offered(self):
        cmd = bridge.screen_command("S1", "Pixel 8 · Screen", tools=TOOLS, stretch=True)
        self.assertIn("--render-fit=stretched", cmd)
        self.assertNotIn("--render-fit=stretched", bridge.screen_command("S1", "Pixel 8 · Screen", tools=TOOLS), "off unless asked")
        self.assertNotIn("--render-fit=stretched", bridge.screen_command("S1", "Pixel 8 · Screen", tools={"flex": True}, stretch=True),
                         "a scrcpy without the option: never an unknown flag")
        self.assertNotIn("--render-fit=stretched", bridge.screen_command("S1", "Pixel 8 · Screen", stretch=True))

    def test_an_app_follows_its_own_window(self):
        cmd = bridge.screen_command("S1", "Maps · Pixel 8", "com.example.maps", TOOLS, stretch=True)
        self.assertFalse([a for a in cmd if "render-fit" in a])

    def test_it_goes_with_the_sound(self):
        cmd = bridge.screen_command("S1", "Pixel 8 · Screen", tools=TOOLS, log="/tmp/x.log", sound="phone", stretch=True)
        self.assertIn("--render-fit=stretched", cmd)
        self.assertIn("--no-audio", cmd)

    def test_the_tools_say_whether_scrcpy_offers_it(self):
        def run(has):
            def fake(argv, **kw):
                text = "scrcpy 5.0.1" if "--version" in argv else ("    --render-fit=mode\n" if has else "    --crop\n")
                return mock.Mock(stdout=text)
            return fake
        with mock.patch.object(bridge.shutil, "which", lambda n: "/usr/bin/" + n):
            self.assertTrue(bridge.screen_tools(run(True))["renderFit"])
            self.assertFalse(bridge.screen_tools(run(False))["renderFit"])
        with mock.patch.object(bridge.shutil, "which", lambda n: None):
            self.assertFalse(bridge.screen_tools(run(True))["renderFit"])


class Reopen(unittest.TestCase):
    def setUp(self):
        self.cache = tempfile.TemporaryDirectory()
        self.addCleanup(self.cache.cleanup)
        env = mock.patch.dict(os.environ, {"XDG_CACHE_HOME": self.cache.name, "XDG_RUNTIME_DIR": self.cache.name})
        env.start()
        self.addCleanup(env.stop)
        self.win = {"address": "0x1", "title": "Pixel 8 · Screen", "at": [100, 40], "size": [400, 860], "floating": True, "pinned": True,
                    "workspace": {"id": 1}, "tags": ["pop*"], "monitor": 0}
        self.window = self.win
        self.launched, self.ran = [], []
        patches = [
            mock.patch.object(bridge, "screen_device", lambda d: {"name": "Pixel 8"}),
            mock.patch.object(bridge, "find_window", lambda title: self.window),
            mock.patch.object(bridge, "screen_status", lambda d: {"state": "ready", "serial": "S1", "tools": TOOLS, "display": [1080, 2400]}),
            mock.patch.object(bridge, "border_size", lambda: 0),
            mock.patch.object(bridge, "hypr_json", lambda what: []),
            mock.patch.object(bridge, "screen_log", lambda title: ""),
            mock.patch.object(bridge, "reopen_window", self.reopen),
            mock.patch.object(bridge.subprocess, "run", lambda *a, **k: self.ran.append(a) or mock.Mock(stdout="", returncode=0)),
        ]
        for p in patches:
            p.start()
            self.addCleanup(p.stop)

    def reopen(self, win, launch, look, **kw):
        launch()
        return True

    def test_closed_it_applies_next_time_and_opens_nothing(self):
        self.window = None
        self.assertEqual(bridge.screen_stretch("dev", True, launch=self.launched.append, sleep=lambda s: None), bridge.EXIT_OK)
        self.assertEqual(self.launched, [])

    def test_open_it_opens_again_in_its_place_with_the_sound_it_had(self):
        bridge.window_sounds("dev", bridge.SCREEN_SOUND, "phone")
        self.assertEqual(bridge.screen_stretch("dev", True, launch=self.launched.append, sleep=lambda s: None), bridge.EXIT_OK)
        self.assertEqual(len(self.launched), 1)
        cmd = self.launched[0]
        self.assertIn("--render-fit=stretched", cmd)
        self.assertIn("--no-audio", cmd, "the sound it had")

    def test_off_opens_again_without_it(self):
        self.assertEqual(bridge.screen_stretch("dev", False, launch=self.launched.append, sleep=lambda s: None), bridge.EXIT_OK)
        self.assertEqual(len(self.launched), 1)
        self.assertFalse([a for a in self.launched[0] if "render-fit" in a])

    def test_a_sound_change_keeps_the_choice(self):
        bridge.screen_sound("dev", "both", launch=self.launched.append, sleep=lambda s: None, stretch=True)
        self.assertIn("--render-fit=stretched", self.launched[0])
        self.assertIn("--audio-dup", self.launched[0])
        self.launched.clear()
        bridge.screen_sound("dev", "here", launch=self.launched.append, sleep=lambda s: None)
        self.assertFalse([a for a in self.launched[0] if "render-fit" in a])

    def test_out_of_reach_it_is_left_open(self):
        with mock.patch.object(bridge, "screen_status", lambda d: {"state": "away", "tools": TOOLS}):
            self.assertEqual(bridge.screen_stretch("dev", True, launch=self.launched.append, sleep=lambda s: None), bridge.EXIT_FAILED)
        self.assertEqual(self.launched, [])


if __name__ == "__main__":
    unittest.main()
