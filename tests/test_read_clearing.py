"""Reading a conversation clears its notification (the panel's two ways): the
D-Bus calls the bridge makes for a dismiss and for the app's own Mark as read,
with the bus replaced so nothing reaches a device. All data is made up."""

import contextlib
import importlib.machinery
import importlib.util
import io
import os
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
BRIDGE = os.path.join(HERE, "..", "bin", "kdeconnect-bridge")
loader = importlib.machinery.SourceFileLoader("kdeconnect_bridge_read", BRIDGE)
spec = importlib.util.spec_from_loader("kdeconnect_bridge_read", loader)
bridge = importlib.util.module_from_spec(spec)
loader.exec_module(bridge)

NOTE = "0|com.example.messages|7|null|10007"


class FakeConn:
    def __init__(self):
        self.sent = []

    def call_sync(self, name, path, iface, method, params, *rest):
        self.sent.append((path.split("/devices/", 1)[-1], iface.rsplit(".", 1)[-1], method,
                          params.unpack() if params is not None else None))
        if method == "GetAll":
            return bridge.GLib.Variant("(a{sv})", ({"internalId": bridge.GLib.Variant("s", "key-7")},))
        return None


class ReadClearing(unittest.TestCase):
    def setUp(self):
        self.conn = FakeConn()
        self.saved = bridge.bus
        bridge.bus = lambda: self.conn

    def tearDown(self):
        bridge.bus = self.saved

    def run_bridge(self, *argv):
        with contextlib.redirect_stdout(io.StringIO()), contextlib.redirect_stderr(io.StringIO()):
            return bridge.act(list(argv))

    def test_a_dismiss_asks_the_notification_to_go(self):
        self.assertEqual(self.run_bridge("dismiss", "d1", NOTE), bridge.EXIT_OK)
        self.assertEqual(self.conn.sent, [("d1/notifications/" + NOTE, "notification", "dismiss", None)])

    def test_the_apps_mark_as_read_is_sent_with_the_notification_s_own_key(self):
        self.assertEqual(self.run_bridge("action", "d1", NOTE, "Mark as read"), bridge.EXIT_OK)
        self.assertEqual(self.conn.sent[-1], ("d1/notifications", "notifications", "sendAction", ("key-7", "Mark as read")))


if __name__ == "__main__":
    unittest.main()
