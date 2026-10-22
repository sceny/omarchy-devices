"""Device events at rest are coalesced (#315): a paired device can send events
at any rate, and `watch` writes the shell one snapshot per burst, not one per
event. The daemon is replaced by a bus that fires a burst of signals, one per
main-loop turn, into the real `watch`. All data is made up."""

import contextlib
import importlib.machinery
import importlib.util
import io
import json
import os
import sys
import tempfile
import unittest
from unittest import mock

HERE = os.path.dirname(os.path.abspath(__file__))
BRIDGE = os.path.join(HERE, "..", "bin", "kdeconnect-bridge")
loader = importlib.machinery.SourceFileLoader("kdeconnect_bridge_burst", BRIDGE)
spec = importlib.util.spec_from_loader("kdeconnect_bridge_burst", loader)
bridge = importlib.util.module_from_spec(spec)
loader.exec_module(bridge)
GLib = bridge.GLib

BURST = 500
DEBOUNCE_MS = max(bridge.DEBOUNCE_MS, 1)   # the shipped value, whatever a test patches
DEVICE = "0123456789abcdef"
PATH = bridge.ROOT + "/devices/" + DEVICE


class FakeBus:
    """What `watch` asks of a connection: subscriptions. `fire` delivers a
    signal to the ones whose filters match, as the bus would."""

    def __init__(self):
        self.subscriptions = []

    def signal_subscribe(self, sender, iface, member, path, arg0, flags, callback, *_rest):
        self.subscriptions.append((sender, iface, member, path, callback))
        return len(self.subscriptions)

    def fire(self, sender, path, iface, member, params):
        for want_sender, want_iface, want_member, want_path, callback in list(self.subscriptions):
            if ((want_sender is None or want_sender == sender) and (want_iface is None or want_iface == iface)
                    and (want_member is None or want_member == member) and (want_path is None or want_path == path)):
                callback(self, sender, path, iface, member, params)


class GLibThatKeepsItsLoops:
    """The bridge's GLib, with `MainLoop` keeping what it makes so a test can
    stop `watch`."""

    def __init__(self, loops):
        self.loops = loops

    def __getattr__(self, name):
        return getattr(GLib, name)

    def MainLoop(self, *args):
        loop = GLib.MainLoop(*args)
        self.loops.append(loop)
        return loop


class NoNetwork:
    proc = None

    def __init__(self, on_change, *_args, **_kwargs):
        pass

    def check(self):
        pass

    def stop(self):
        pass


def signal(name, iface, params=None):
    return (bridge.BUS_NAME, PATH + "/" + name, bridge.IFACE + "." + iface, name, params or GLib.Variant("()", ()))


class WatchBurst(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.bus = FakeBus()
        self.level = 0
        self.snapshots = 0
        self.previews = []
        self.loops = []

        def snapshot(conn, calls=None):
            self.snapshots += 1
            return {"daemon": True, "devices": [{"id": DEVICE, "paired": True, "level": self.level}]}

        def preview(src, box, *_rest):
            self.previews.append(src)
            return ""

        for patcher in (
                mock.patch.dict(os.environ, {"XDG_CACHE_HOME": self.tmp.name}),
                mock.patch.object(bridge, "bus", lambda: self.bus),
                mock.patch.object(bridge, "system_bus", mock.Mock(side_effect=GLib.Error("no system bus"))),
                mock.patch.object(bridge, "snapshot", snapshot),
                mock.patch.object(bridge, "NetWatch", NoNetwork),
                mock.patch.object(bridge, "keep_clipboard_for", lambda *a, **k: None),
                mock.patch.object(bridge, "safe_image", preview),
                mock.patch.object(bridge, "GLib", GLibThatKeepsItsLoops(self.loops))):
            patcher.start()
            self.addCleanup(patcher.stop)

    def burst(self, make_signal, count=BURST):
        """Runs `watch` while one signal arrives per main-loop turn, the next
        one a millisecond after the last; returns the snapshot lines it wrote
        and how long the burst lasted."""
        out = io.StringIO()
        sent = {"n": 0, "start": 0, "end": 0}

        def send():
            if not sent["n"]:
                sent["start"] = GLib.get_monotonic_time()
            self.level = sent["n"] + 1
            self.bus.fire(*make_signal(sent["n"]))
            sent["n"] += 1
            if sent["n"] < count:
                return True
            sent["end"] = GLib.get_monotonic_time()
            # One debounce after the last signal, plus room, then stop watching.
            GLib.timeout_add(DEBOUNCE_MS * 3, lambda: self.loops[0].quit() or False)
            return False

        GLib.timeout_add(100, lambda: GLib.timeout_add(1, send) and False)
        # A burst that dies on an error must fail the test, not hang it.
        watchdog = GLib.timeout_add(20000, lambda: self.loops[0].quit() or False)
        with contextlib.redirect_stdout(out):
            bridge.watch()
        stale = GLib.MainContext.default().find_source_by_id(watchdog)
        if stale is not None:
            stale.destroy()
        self.assertEqual(sent["n"], count, "the burst did not finish")
        lines = [json.loads(line) for line in out.getvalue().splitlines()]
        return lines, (sent["end"] - sent["start"]) / 1000.0

    def allowed(self, burst_ms):
        """The first snapshot at start, one for each debounce the burst spans
        (a debounce that restarted on every signal needs none), the one after
        it settles, and one for slack."""
        return 1 + int(burst_ms // DEBOUNCE_MS) + 1 + 1

    def assert_coalesced(self, lines, burst_ms):
        self.assertGreater(len(lines), 1, "no snapshot followed the burst")
        self.assertLessEqual(len(lines), self.allowed(burst_ms),
                             "%d snapshot lines for %d signals in %d ms" % (len(lines), BURST, burst_ms))
        self.assertLessEqual(self.snapshots, self.allowed(burst_ms))
        self.assertEqual(lines[-1]["devices"][0]["level"], BURST, "the last snapshot is not the last state")

    def test_notification_changes_make_one_snapshot_after_the_burst(self):
        lines, ms = self.burst(lambda i: signal("notification", "device.notifications.notification"))
        self.assert_coalesced(lines, ms)

    def test_player_changes_make_one_snapshot_after_the_burst(self):
        def player(i):
            params = GLib.Variant("(sa{sv}as)", ("org.mpris.MediaPlayer2.Player", {}, []))
            return (bridge.BUS_NAME, PATH + "/mprisremote", "org.freedesktop.DBus.Properties", "PropertiesChanged", params)
        lines, ms = self.burst(player)
        self.assert_coalesced(lines, ms)

    def test_received_files_make_one_snapshot_and_no_picture_work_per_event(self):
        files = []
        for i in range(10):
            path = os.path.join(self.tmp.name, "picture%d.png" % i)
            with open(path, "wb") as f:
                f.write(b"x")
            files.append(path)

        def share(i):
            params = GLib.Variant("(s)", ("file://" + files[i % len(files)],))
            return (bridge.BUS_NAME, PATH + "/share", bridge.IFACE + ".device.share", "shareReceived", params)
        lines, ms = self.burst(share)
        self.assert_coalesced(lines, ms)
        self.assertLessEqual(len(self.previews), self.snapshots * len(files),
                             "%d picture previews for %d snapshots" % (len(self.previews), self.snapshots))
        self.assertGreater(len(self.previews), 0, "the received pictures were never prepared: the test sees nothing")

    def test_the_wait_is_not_tuned_away(self):
        self.assertGreaterEqual(bridge.DEBOUNCE_MS, 100)

    def test_the_burst_is_long_enough_to_tell_a_debounce_from_none(self):
        # Without it, each signal (a millisecond apart) would write its own line.
        self.assertGreater(BURST, 10 * self.allowed(BURST))


class Unbounded(unittest.TestCase):
    """The test above fails when the debounce goes: a `watch` that writes a
    snapshot for each signal is caught."""

    def test_a_watch_without_the_debounce_is_found(self):
        probe = WatchBurst("test_notification_changes_make_one_snapshot_after_the_burst")
        probe.setUp()
        try:
            with mock.patch.object(bridge, "DEBOUNCE_MS", 0):
                with self.assertRaises(AssertionError):
                    lines, ms = probe.burst(lambda i: signal("notification", "device.notifications.notification"))
                    probe.assert_coalesced(lines, ms)
        finally:
            probe.doCleanups()


if __name__ == "__main__":
    unittest.main()
