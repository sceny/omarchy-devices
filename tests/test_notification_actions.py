"""A notification's buttons on a KDE Connect that does not list them on D-Bus
(#436): the daemon's own Notify call carries them, the bridge reads that call
from a monitor and matches it to the notification by its text. All data is
made up (Pixel 8, 555 numbers)."""

import importlib.machinery
import importlib.util
import json
import os
import shutil
import subprocess
import tempfile
import time
import unittest
from unittest import mock

HERE = os.path.dirname(os.path.abspath(__file__))
BRIDGE = os.path.join(HERE, "..", "bin", "kdeconnect-bridge")
loader = importlib.machinery.SourceFileLoader("kdeconnect_bridge", BRIDGE)
spec = importlib.util.spec_from_loader("kdeconnect_bridge", loader)
bridge = importlib.util.module_from_spec(spec)
loader.exec_module(bridge)

from gi.repository import GLib, Gio  # noqa: E402


def notify(summary, body, actions, device="Pixel 8", extra=None):
    hints = {"x-kdeconnect-source-device": device}
    hints.update(extra or {})
    return ("kdeconnect", 0, "", summary, body, actions, hints, -1)


class Record(unittest.TestCase):
    def test_labels_without_the_daemons_own_actions(self):
        record = bridge.notify_record(notify(
            "Chat", "Sam: Lunch?", ["inline-reply", "Reply", "1", "Mark as read", "default", "Open"]))
        self.assertEqual(record["device"], "Pixel 8")
        self.assertEqual(record["actions"], ["Mark as read"])

    def test_other_notifications_are_not_the_devices(self):
        self.assertIsNone(bridge.notify_record(notify("A", "b", [], device="")))
        self.assertIsNone(bridge.notify_record(
            ("app", 0, "", "A", "b", [], {}, -1)))
        self.assertIsNone(bridge.notify_record(("short",)))

    def test_match_key_ignores_markup_case_and_spacing(self):
        self.assertEqual(bridge.match_key("<b>Sam</b>: Lunch &amp; coffee?"),
                         bridge.match_key("sam:  lunch & COFFEE?"))


class Matching(unittest.TestCase):
    props = {"appName": "Chat", "title": "Sam", "text": "Lunch?", "ticker": "Sam: Lunch?"}

    def registry(self):
        registry = bridge.NotificationActions({})
        registry.note(bridge.notify_record(notify("Chat", "Sam: Lunch?", ["1", "Mark as read"])))
        return registry

    def test_a_call_gives_its_notification_the_actions(self):
        registry = self.registry()
        self.assertEqual(registry.actions_for("d1", "Pixel 8", "k1", self.props), ["Mark as read"])
        self.assertTrue(registry.changed)

    def test_title_and_text_as_the_summary_and_body(self):
        registry = bridge.NotificationActions({})
        registry.note(bridge.notify_record(notify("Sam", "Lunch?", ["1", "Archive"])))
        self.assertEqual(registry.actions_for("d1", "Pixel 8", "k1", self.props), ["Archive"])

    def test_another_device_or_text_gets_none(self):
        registry = self.registry()
        self.assertEqual(registry.actions_for("d2", "Pad", "k1", self.props), [])
        other = dict(self.props, text="Dinner?", ticker="Sam: Dinner?")
        self.assertEqual(registry.actions_for("d1", "Pixel 8", "k2", other), [])

    def test_the_newest_call_wins(self):
        registry = self.registry()
        registry.note(bridge.notify_record(notify("Chat", "Sam: Lunch?", ["1", "Archive"])))
        self.assertEqual(registry.actions_for("d1", "Pixel 8", "k1", self.props), ["Archive"])

    def test_a_match_outlives_the_call(self):
        registry = self.registry()
        registry.actions_for("d1", "Pixel 8", "k1", self.props)
        later = bridge.NotificationActions(registry.bound)   # a restart: no calls, the cache
        self.assertEqual(later.actions_for("d1", "Pixel 8", "k1", self.props), ["Mark as read"])

    def test_gone_notifications_are_forgotten_after_a_while(self):
        registry = self.registry()
        registry.actions_for("d1", "Pixel 8", "k1", self.props)
        registry.changed = False
        registry.keep("d1", ["k9"], now=0)
        registry.keep("d1", ["k9"], now=registry.FORGET_AFTER_S - 1)
        self.assertEqual(registry.actions_for("d1", "Pixel 8", "k1", self.props), ["Mark as read"])
        registry.keep("d1", ["k9"], now=registry.FORGET_AFTER_S)
        self.assertEqual(registry.bound, {})
        self.assertTrue(registry.changed)

    def test_a_partial_list_after_a_restart_forgets_nothing(self):
        registry = self.registry()
        registry.actions_for("d1", "Pixel 8", "k1", self.props)
        later = bridge.NotificationActions(registry.bound)   # a restart: the cache only
        later.keep("d1", [], now=0)
        later.keep("d1", ["k2"], now=5)
        later.keep("d1", ["k1", "k2"], now=10)               # k1 is listed after all
        later.keep("d1", ["k2"], now=10 + later.FORGET_AFTER_S - 1)
        self.assertEqual(later.actions_for("d1", "Pixel 8", "k1", self.props), ["Mark as read"])

    def test_a_notification_without_buttons_is_not_kept(self):
        registry = bridge.NotificationActions({})
        registry.note(bridge.notify_record(notify("Chat", "Sam: Lunch?", ["inline-reply", "Reply"])))
        self.assertEqual(registry.actions_for("d1", "Pixel 8", "k1", self.props), [])
        self.assertEqual(registry.bound, {})
        self.assertFalse(registry.changed)

    def test_buttons_that_went_away_are_dropped(self):
        registry = self.registry()
        registry.actions_for("d1", "Pixel 8", "k1", self.props)
        registry.note(bridge.notify_record(notify("Chat", "Sam: Lunch?", [])))
        self.assertEqual(registry.actions_for("d1", "Pixel 8", "k1", self.props), [])
        self.assertEqual(registry.bound, {})

    def test_the_file_holds_no_key_text(self):
        key = "0|com.example.chat|7|conversation-with-sam-555-0100|10042"
        registry = self.registry()
        registry.actions_for("d1", "Pixel 8", key, self.props)
        with tempfile.TemporaryDirectory() as tmp:
            path = os.path.join(tmp, "a.json")
            bridge.save_actions(path, registry.bound)
            with open(path) as f:
                text = f.read()
        for part in ("com.example.chat", "conversation-with-sam", "555-0100", "10042"):
            self.assertNotIn(part, text)
        self.assertIn("Mark as read", text)

    def test_records_are_bounded(self):
        registry = bridge.NotificationActions({})
        for n in range(bridge.CAP_NOTIFY_RECORDS + 20):
            registry.note(bridge.notify_record(notify("Chat", "m%d" % n, [])))
        self.assertEqual(len(registry.records["Pixel 8"]), bridge.CAP_NOTIFY_RECORDS)


class Reading(unittest.TestCase):
    def read(self, props, registry):
        with mock.patch.object(bridge, "call", lambda conn, path, iface, name, *a, **k: (["1"],)), \
                mock.patch.object(bridge, "props", lambda conn, path, iface: dict(props)):
            return bridge.read_notifications(None, "/d", registry, "d1", "Pixel 8")

    base = {"internalId": "k1", "appName": "Chat", "title": "Sam", "text": "Lunch?",
            "ticker": "Sam: Lunch?"}

    def test_actions_from_the_registry(self):
        registry = bridge.NotificationActions({})
        registry.note(bridge.notify_record(notify("Chat", "Sam: Lunch?", ["1", "Mark as read"])))
        self.assertEqual(self.read(self.base, registry)[0]["actions"], ["Mark as read"])

    def test_actions_on_dbus_are_kept(self):
        registry = bridge.NotificationActions({})
        registry.note(bridge.notify_record(notify("Chat", "Sam: Lunch?", ["1", "Other"])))
        got = self.read(dict(self.base, actions=["Archive"]), registry)
        self.assertEqual(got[0]["actions"], ["Archive"])

    def test_without_a_registry_nothing_changes(self):
        self.assertEqual(self.read(self.base, None)[0]["actions"], [])


class Persistence(unittest.TestCase):
    def test_round_trip_and_garbage(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = os.path.join(tmp, "a.json")
            self.assertEqual(bridge.load_actions(path), {})
            bridge.save_actions(path, {"d1": {"a1b2": ["Archive"]}})
            self.assertEqual(bridge.load_actions(path), {"d1": {"a1b2": ["Archive"]}})
            with open(path, "w") as f:
                f.write(json.dumps({"d1": ["x"], "d2": {"k": "no", "j": ["a", 3]}}))
            self.assertEqual(bridge.load_actions(path), {"d2": {"j": ["a"]}})
            with open(path, "w") as f:
                f.write("{")
            self.assertEqual(bridge.load_actions(path), {})


@unittest.skipUnless(shutil.which("dbus-daemon"), "needs dbus-daemon")
class OnABus(unittest.TestCase):
    """The monitor on a private bus: it receives the daemon's Notify call and
    nothing else, and the call still reaches its server."""

    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        daemon = subprocess.Popen(
            ["dbus-daemon", "--session", "--nofork", "--print-address=1"],
            stdout=subprocess.PIPE, text=True, cwd=self.tmp.name)
        self.addCleanup(daemon.terminate)
        self.address = daemon.stdout.readline().strip()
        patcher = mock.patch.dict(os.environ, {"DBUS_SESSION_BUS_ADDRESS": self.address})
        patcher.start()
        self.addCleanup(patcher.stop)

    def connect(self):
        return Gio.DBusConnection.new_for_address_sync(
            self.address, Gio.DBusConnectionFlags.AUTHENTICATION_CLIENT
            | Gio.DBusConnectionFlags.MESSAGE_BUS_CONNECTION, None, None)

    def own(self, conn, name):
        conn.call_sync("org.freedesktop.DBus", "/org/freedesktop/DBus", "org.freedesktop.DBus",
                       "RequestName", GLib.Variant("(su)", (name, 0)), None,
                       Gio.DBusCallFlags.NONE, 2000, None)

    def test_the_daemons_notify_arrives_and_others_do_not(self):
        got = []
        monitor = bridge.NotifyMonitor(got.append)
        self.assertTrue(monitor.start())
        server = self.connect()
        self.own(server, "org.freedesktop.Notifications")
        served = []
        server.register_object(
            "/org/freedesktop/Notifications",
            Gio.DBusNodeInfo.new_for_xml(
                '<node><interface name="org.freedesktop.Notifications">'
                '<method name="Notify"><arg type="s" direction="in"/><arg type="u" direction="in"/>'
                '<arg type="s" direction="in"/><arg type="s" direction="in"/><arg type="s" direction="in"/>'
                '<arg type="as" direction="in"/><arg type="a{sv}" direction="in"/><arg type="i" direction="in"/>'
                '<arg type="u" direction="out"/></method></interface></node>').interfaces[0],
            lambda c, s, p, i, m, params, inv: (served.append(params.unpack()[3]),
                                                inv.return_value(GLib.Variant("(u)", (7,)))),
            None, None)
        daemon = self.connect()
        self.own(daemon, "org.kde.kdeconnect")
        other = self.connect()

        replies = []

        def send(conn, summary, hints):
            conn.call(
                "org.freedesktop.Notifications", "/org/freedesktop/Notifications",
                "org.freedesktop.Notifications", "Notify",
                GLib.Variant("(susssasa{sv}i)", ("kdeconnect", 0, "", summary, "Sam: Lunch?",
                                                 ["1", "Mark as read"], hints, -1)),
                None, Gio.DBusCallFlags.NONE, 2000, None,
                lambda c, result: replies.append(c.call_finish(result).unpack()))

        def settle(done):
            context = GLib.MainContext.default()
            deadline = time.time() + 3
            while not done() and time.time() < deadline:
                context.iteration(False)
                time.sleep(0.01)

        # a call from a sender other than the daemon is not what the match covers
        send(other, "Other", {"x-kdeconnect-source-device": GLib.Variant("s", "Pixel 8")})
        send(daemon, "Chat", {"x-kdeconnect-source-device": GLib.Variant("s", "Pixel 8")})
        settle(lambda: len(replies) == 2 and got)
        self.assertEqual(replies, [(7,), (7,)])
        self.assertEqual([r["actions"] for r in got], [["Mark as read"]])
        self.assertEqual(sorted(served), ["Chat", "Other"])
        self.assertEqual(got[0]["summary"], bridge.match_key("Chat"))


if __name__ == "__main__":
    unittest.main()
