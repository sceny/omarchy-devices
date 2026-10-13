"""The clipboard leaves only on the user's act: KDE Connect's clipboard plugin
has auto-share and passwords off for every device unless the user chose
otherwise. The daemon is replaced; the files are made up in a temp folder."""

import importlib.machinery
import importlib.util
import os
import tempfile
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
BRIDGE = os.path.join(HERE, "..", "bin", "kdeconnect-bridge")
loader = importlib.machinery.SourceFileLoader("kdeconnect_bridge_clipboard", BRIDGE)
spec = importlib.util.spec_from_loader("kdeconnect_bridge_clipboard", loader)
bridge = importlib.util.module_from_spec(spec)
loader.exec_module(bridge)


class FakeDaemon:
    """Answers the three calls the fix makes and records every call."""
    def __init__(self, plugins_file, auto_share_off=None):
        self.plugins_file, self.auto_share_off, self.calls = plugins_file, auto_share_off, []

    def __call__(self, conn, path, iface, method, args=None, sig=None):
        self.calls.append((method, args))
        if method == "pluginsConfigFile":
            return (self.plugins_file,)
        if method == "Get":
            if self.auto_share_off is None:
                raise bridge.GLib.Error("not loaded")
            return (self.auto_share_off,)
        return ()


class IniTests(unittest.TestCase):
    def test_get_reads_general_and_top_level_only(self):
        text = "x=1\n[General]\nautoShare=true\n[Other]\nsendPassword=true\n"
        self.assertEqual(bridge.ini_get(text, "x"), "1")
        self.assertEqual(bridge.ini_get(text, "autoShare"), "true")
        self.assertIsNone(bridge.ini_get(text, "sendPassword"))

    def test_fill_adds_only_what_is_missing(self):
        text, changed = bridge.ini_fill("[General]\nmaxClipboardFileSizeMB=20\n", bridge.CLIPBOARD_HERE)
        self.assertTrue(changed)
        self.assertEqual(text, "[General]\nmaxClipboardFileSizeMB=20\nautoShare=false\nsendPassword=false\n")

    def test_fill_keeps_a_choice_the_user_made(self):
        text, changed = bridge.ini_fill("[General]\nsendPassword=true\n", bridge.CLIPBOARD_HERE)
        self.assertEqual(text, "[General]\nsendPassword=true\nautoShare=false\n")
        self.assertTrue(changed)
        same, changed = bridge.ini_fill(text, bridge.CLIPBOARD_HERE)
        self.assertEqual((same, changed), (text, False))

    def test_fill_goes_before_the_next_section_and_makes_a_general_one(self):
        text, _ = bridge.ini_fill("[General]\na=1\n\n[Other]\nb=2\n", bridge.CLIPBOARD_HERE)
        self.assertEqual(text.splitlines()[:5], ["[General]", "a=1", "autoShare=false", "sendPassword=false", ""])
        text, _ = bridge.ini_fill("", bridge.CLIPBOARD_HERE)
        self.assertEqual(text, "[General]\nautoShare=false\nsendPassword=false\n")


class KeepHereTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.config = os.path.join(self.tmp.name, "dev1", "config")
        self.path = os.path.join(self.tmp.name, "dev1", bridge.CLIPBOARD_PLUGIN, "config")
        self.fake = FakeDaemon(self.config)
        real = bridge.call
        bridge.call = self.fake
        self.addCleanup(lambda: setattr(bridge, "call", real))

    def read(self):
        with open(self.path) as f:
            return f.read()

    def test_a_device_without_a_choice_gets_both_off(self):
        self.assertEqual(bridge.keep_clipboard_here("dev1", object()), "changed")
        self.assertEqual(self.read(), "[General]\nautoShare=false\nsendPassword=false\n")
        self.assertEqual(oct(os.stat(self.path).st_mode & 0o777), "0o600")

    def test_a_loaded_plugin_starts_again_to_read_it(self):
        self.fake.auto_share_off = False
        self.assertEqual(bridge.keep_clipboard_here("dev1", object()), "changed")
        sets = [a for m, a in self.fake.calls if m == "setPluginEnabled"]
        self.assertEqual(sets, [(bridge.CLIPBOARD_PLUGIN, False), (bridge.CLIPBOARD_PLUGIN, True)])

    def test_a_plugin_the_user_turned_off_stays_off(self):
        self.assertEqual(bridge.keep_clipboard_here("dev1", object()), "changed")
        self.assertFalse([m for m, _ in self.fake.calls if m == "setPluginEnabled"])

    def test_already_private_changes_nothing(self):
        bridge.keep_clipboard_here("dev1", object())
        self.fake.calls.clear()
        self.fake.auto_share_off = True
        self.assertEqual(bridge.keep_clipboard_here("dev1", object()), "here")
        self.assertFalse([m for m, _ in self.fake.calls if m == "setPluginEnabled"])

    def test_the_users_own_auto_share_stays(self):
        os.makedirs(os.path.dirname(self.path))
        with open(self.path, "w") as f:
            f.write("[General]\nautoShare=true\n")
        self.fake.auto_share_off = False
        self.assertEqual(bridge.keep_clipboard_here("dev1", object()), "shared")
        self.assertEqual(self.read(), "[General]\nautoShare=true\n")
        self.assertFalse([m for m, _ in self.fake.calls if m == "setPluginEnabled"])

    def test_turning_the_plugin_on_sets_it_first(self):
        seen = []
        real = self.fake.__call__

        def spy(conn, path, iface, method, args=None, sig=None):
            if method == "setPluginEnabled":
                seen.append((os.path.exists(self.path) and self.read(), args))
            return real(conn, path, iface, method, args, sig)
        bridge.call = spy
        bridge.set_plugin("dev1", "clipboard", True, conn=object())
        self.assertEqual(seen, [("[General]\nautoShare=false\nsendPassword=false\n", (bridge.CLIPBOARD_PLUGIN, True))])


class KeepForTests(unittest.TestCase):
    def test_a_failed_device_is_tried_again_and_a_done_one_is_not(self):
        calls = []
        real = bridge.keep_clipboard_here

        def fake(device_id, conn):
            calls.append(device_id)
            if device_id == "bad" and calls.count("bad") == 1:
                raise OSError("read-only")
            return "changed"
        bridge.keep_clipboard_here = fake
        self.addCleanup(lambda: setattr(bridge, "keep_clipboard_here", real))
        devices = [{"id": "good", "paired": True}, {"id": "bad", "paired": True}, {"id": "gone", "paired": False}]
        done = set()
        bridge.keep_clipboard_for(devices, done, object())
        bridge.keep_clipboard_for(devices, done, object())
        self.assertEqual(calls, ["good", "bad", "bad"])


if __name__ == "__main__":
    unittest.main()
