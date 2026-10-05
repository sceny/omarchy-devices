"""A window's sound (#129): where it plays, scrcpy's arguments for it, the
choice kept per app, the window opened again in its place, and its stream
here (kdeconnect-bridge). Windows and PipeWire objects are made up; nothing
comes from a real device and nothing opens."""

import importlib.machinery
import importlib.util
import json
import os
import tempfile
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
BRIDGE = os.path.join(HERE, "..", "bin", "kdeconnect-bridge")
loader = importlib.machinery.SourceFileLoader("kdeconnect_bridge_sound", BRIDGE)
spec = importlib.util.spec_from_loader("kdeconnect_bridge_sound", loader)
bridge = importlib.util.module_from_spec(spec)
loader.exec_module(bridge)


class Arguments(unittest.TestCase):
    def test_each_place_is_scrcpys_own_flags(self):
        app = lambda sound: bridge.screen_command("S1", "Maps · Pixel 8", "com.example.maps", {"flex": True}, sound=sound)
        self.assertIn("--no-audio", app("phone"), "on the phone: none forwarded")
        self.assertFalse([a for a in app("here") if "audio" in a], "here: scrcpy's default, the whole output")
        both = app("both")
        self.assertIn("--audio-source=playback", both)
        self.assertIn("--audio-dup", both, "the device keeps playing it")
        self.assertNotIn("--no-audio", both)

    def test_the_screen_too_with_here_as_it_always_was(self):
        self.assertFalse([a for a in bridge.screen_command("S1", "Pixel 8 · Screen") if "audio" in a])
        self.assertIn("--no-audio", bridge.screen_command("S1", "Pixel 8 · Screen", sound="phone"))
        self.assertIn("--audio-dup", bridge.screen_command("S1", "Pixel 8 · Screen", log="/tmp/x.log", sound="both"))


class Kept(unittest.TestCase):
    def setUp(self):
        self.home = tempfile.TemporaryDirectory()
        self.old = os.environ.get("XDG_CACHE_HOME")
        os.environ["XDG_CACHE_HOME"] = self.home.name

    def tearDown(self):
        if self.old is None:
            os.environ.pop("XDG_CACHE_HOME", None)
        else:
            os.environ["XDG_CACHE_HOME"] = self.old
        self.home.cleanup()

    def test_each_window_keeps_its_last_choice_in_the_cache(self):
        self.assertEqual(bridge.window_sounds("dev"), {})
        bridge.window_sounds("dev", "com.example.maps", "both")
        bridge.window_sounds("dev", bridge.SCREEN_SOUND, "phone")
        bridge.window_sounds("dev", "com.example.maps", "nonsense")
        self.assertEqual(bridge.window_sounds("dev"), {"com.example.maps": "both", "@screen": "phone"})
        path = os.path.join(bridge.apps_dir("dev"), "sound.json")
        self.assertTrue(path.startswith(self.home.name), "usage, in the cache, not shell.json")
        with open(path, "w") as f:
            f.write('{"com.example.a": "loud", "com.example.b": "here"}')
        self.assertEqual(bridge.window_sounds("dev"), {"com.example.b": "here"}, "what it cannot read is dropped")

    def test_the_apps_list_carries_them(self):
        bridge.window_sounds("dev", "com.example.maps", "phone")
        apps = [{"package": "com.example.maps", "name": "Maps", "system": False, "version": "1", "activity": ""}]
        out = bridge.apps_list("dev", status={"state": "ready", "serial": "S"}, read=lambda s: apps, clock=lambda: 1000)
        self.assertEqual(out["sounds"], {"com.example.maps": "phone"})


def window(address, at, size, floating=False, pinned=False, ws=1, tags=()):
    return {"address": address, "title": "Maps · Pixel 8", "at": list(at), "size": list(size), "floating": floating,
            "pinned": pinned, "workspace": {"id": ws}, "tags": list(tags), "monitor": 0}


class Reopen(unittest.TestCase):
    """The window closes and opens again in its place: Hyprland is a list
    of windows changed by the dispatches the bridge sends."""

    def hypr(self, first, opens_as):
        state = {"win": first, "ran": [], "launched": 0}

        def run(lua):
            state["ran"].append(lua)
            if "window.close" in lua:
                state["win"] = None
            elif "window.swap" in lua and state["win"]:
                state["win"] = dict(state["win"], at=list(first["at"]))   # the layout swaps it back
            elif "window.move" in lua and "workspace" in lua and state["win"]:
                state["win"] = dict(state["win"], workspace={"id": first["workspace"]["id"]})

        def launch():
            state["launched"] += 1
            state["win"] = opens_as

        return state, run, launch, (lambda: state["win"])

    def test_a_popped_out_window_comes_back_pinned_and_tagged(self):
        old = window("0x1", (1500, 40), (400, 860), floating=True, pinned=True, tags=["pop*"])
        new = window("0x2", (1500, 40), (400, 860), floating=True, pinned=True)
        state, run, launch, look = self.hypr(old, new)
        self.assertTrue(bridge.reopen_window(old, launch, look, run, sleep=lambda s: None, mons=[{"id": 0, "x": 0, "y": 0}]))
        self.assertEqual(state["launched"], 1)
        self.assertTrue(any('tag = "+pop"' in l and "0x2" in l for l in state["ran"]), "Omarchy's pop-out look again")
        self.assertFalse(any("window.pin" in l for l in state["ran"]), "pinned already by the rule")

    def test_a_tiled_window_goes_back_to_its_side(self):
        old = window("0x1", (10, 40), (940, 1000))
        new = window("0x2", (970, 40), (940, 1000))   # the layout put it on the right
        state, run, launch, look = self.hypr(old, new)
        self.assertTrue(bridge.reopen_window(old, launch, look, run, sleep=lambda s: None, mons=[]))
        swaps = [l for l in state["ran"] if "window.swap" in l]
        self.assertEqual(len(swaps), 1)
        self.assertIn('direction = "l"', swaps[0])
        self.assertIn("0x2", swaps[0], "the new window, by its address")

    def test_a_tiled_window_already_in_its_place_stays(self):
        old = window("0x1", (970, 40), (940, 1000))
        state, run, launch, look = self.hypr(old, window("0x2", (970, 40), (940, 1000)))
        self.assertTrue(bridge.reopen_window(old, launch, look, run, sleep=lambda s: None, mons=[]))
        self.assertFalse([l for l in state["ran"] if "swap" in l or "workspace" in l])

    def test_back_to_its_workspace(self):
        old = window("0x1", (10, 40), (940, 1000), ws=3)
        state, run, launch, look = self.hypr(old, window("0x2", (10, 40), (940, 1000), ws=1))
        self.assertTrue(bridge.reopen_window(old, launch, look, run, sleep=lambda s: None, mons=[]))
        self.assertTrue(any('workspace = "3"' in l and "follow = false" in l for l in state["ran"]))

    def test_a_window_that_will_not_close_is_left_alone(self):
        old = window("0x1", (10, 40), (940, 1000))
        launched = []
        ok = bridge.reopen_window(old, lambda: launched.append(1), lambda: old, lambda lua: None, sleep=lambda s: None, mons=[])
        self.assertFalse(ok)
        self.assertEqual(launched, [], "never a second window beside it")

    def test_which_side(self):
        place = {"at": [10, 40], "size": [940, 1000]}
        self.assertIsNone(bridge.side_of({"at": [12, 40], "size": [930, 1000]}, place))
        self.assertEqual(bridge.side_of({"at": [970, 40], "size": [940, 1000]}, place), "l")
        self.assertEqual(bridge.side_of({"at": [10, 560], "size": [940, 480]}, {"at": [10, 40], "size": [940, 480]}), "u")


PW = [
    {"id": 31, "type": "PipeWire:Interface:Node", "info": {"props": {"media.class": "Audio/Sink", "node.name": "alsa_output.speakers",
                                                                     "node.description": "Speakers"}}},
    {"id": 77, "type": "PipeWire:Interface:Node", "info": {"props": {"media.class": "Stream/Output/Audio",
                                                                     "application.process.id": 4242,
                                                                     "application.process.binary": "scrcpy"}}},
    {"id": 78, "type": "PipeWire:Interface:Node", "info": {"props": {"media.class": "Stream/Output/Audio",
                                                                     "application.process.id": 999, "application.name": "Firefox"}}},
    {"id": 40, "type": "PipeWire:Interface:Metadata", "props": {"metadata.name": "default"},
     "metadata": [{"key": "default.audio.sink", "value": {"name": "alsa_output.speakers"}}]},
]


class Stream(unittest.TestCase):
    def test_the_windows_own_stream_and_the_output_it_plays_on(self):
        self.assertEqual(bridge.window_stream(4242, PW), (77, "Speakers"))
        self.assertEqual(bridge.window_stream(1, PW), (77, "Speakers"), "a lone scrcpy stream, by its program")
        two = PW + [dict(PW[1], id=79, info={"props": dict(PW[1]["info"]["props"], **{"application.process.id": 5})})]
        self.assertEqual(bridge.window_stream(1, two)[0], None, "two scrcpy streams: not a guess")
        self.assertEqual(bridge.window_stream(4242, [PW[1]]), (77, ""))

    def test_wpctls_answer(self):
        self.assertEqual(bridge.parse_wpctl_volume("Volume: 0.40\n"), (0.4, False))
        self.assertEqual(bridge.parse_wpctl_volume("Volume: 0.40 [MUTED]\n"), (0.4, True))
        self.assertEqual(bridge.parse_wpctl_volume(""), (0.0, False))

    def test_volume_and_mute_go_to_its_stream_only(self):
        ran = []
        old_find, old_dev = bridge.find_window, bridge.screen_device
        bridge.find_window = lambda title: {"pid": 4242, "title": title} if title == "Maps · Pixel 8" else None
        bridge.screen_device = lambda d: {"name": "Pixel 8"}
        try:
            run = lambda args: ran.append(args) or ("Volume: 0.55" if args[1] == "get-volume" else "")
            out = bridge.screen_volume("dev", "com.example.maps", "Maps", level=0.55, mute="off", run=run, dump=PW)
            self.assertEqual(out, {"found": True, "volume": 0.55, "muted": False, "output": "Speakers"})
            self.assertEqual(ran[0], ["wpctl", "set-volume", "77", "0.55"])
            self.assertEqual(ran[1], ["wpctl", "set-mute", "77", "0"])
            self.assertFalse([a for a in ran if "@DEFAULT" in " ".join(a)], "never this computer's whole output")
            self.assertEqual(bridge.screen_volume("dev", "x", "Notes", run=run, dump=PW)["found"], False, "no window")
            self.assertEqual(bridge.screen_volume("dev", "", "", level=2, run=run, dump=PW)["found"], False)
        finally:
            bridge.find_window, bridge.screen_device = old_find, old_dev


if __name__ == "__main__":
    unittest.main()
