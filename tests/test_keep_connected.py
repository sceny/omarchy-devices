"""A paired device that drops is looked for in the background (#438): after a
short grace, then with a growing delay, never faster than the back-off, and
starting over when it is back. The daemon is replaced by a counter. All data
is made up."""

import importlib.machinery
import importlib.util
import os
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
BRIDGE = os.path.join(HERE, "..", "bin", "kdeconnect-bridge")
loader = importlib.machinery.SourceFileLoader("kdeconnect_bridge_keep", BRIDGE)
spec = importlib.util.spec_from_loader("kdeconnect_bridge_keep", loader)
bridge = importlib.util.module_from_spec(spec)
loader.exec_module(bridge)

UP = {"id": "aaaa", "paired": True, "reachable": True}
DOWN = {"id": "aaaa", "paired": True, "reachable": False}
OTHER_DOWN = {"id": "bbbb", "paired": True, "reachable": False}
UNPAIRED = {"id": "cccc", "paired": False, "reachable": False}


class KeepConnected(unittest.TestCase):
    def setUp(self):
        self.searches = []
        self.keep = bridge.KeepConnected(lambda: self.searches.append(1))

    def run_for(self, devices, seconds, start=0, network_up=True):
        """One step a second; returns the seconds at which it searched."""
        return [t for t in range(start, start + seconds) if self.keep.step(devices, t, network_up)]

    def test_a_device_that_is_up_is_never_searched_for(self):
        self.assertEqual(self.run_for([UP], 3600), [])

    def test_a_short_drop_is_left_to_the_daemon(self):
        self.assertEqual(self.run_for([DOWN], bridge.KeepConnected.GRACE_SEC), [])
        self.assertEqual(self.run_for([UP], 600, start=bridge.KeepConnected.GRACE_SEC), [])
        self.assertEqual(self.searches, [])

    def test_the_first_search_comes_after_the_grace_then_the_delays_grow(self):
        grace, delays = bridge.KeepConnected.GRACE_SEC, bridge.KeepConnected.BACKOFF_SEC
        times = self.run_for([DOWN], 3000)
        expected = [grace]
        for delay in delays:
            expected.append(expected[-1] + delay)
        while expected[-1] + delays[-1] < 3000:
            expected.append(expected[-1] + delays[-1])
        self.assertEqual(times, expected)
        self.assertEqual(len(self.searches), len(times))

    def test_the_delay_stops_growing_at_the_last_one(self):
        times = self.run_for([DOWN], 7200)
        gaps = [b - a for a, b in zip(times, times[1:])]
        self.assertEqual(max(gaps), bridge.KeepConnected.BACKOFF_SEC[-1])
        self.assertGreaterEqual(min(gaps[:len(bridge.KeepConnected.BACKOFF_SEC)]), bridge.KeepConnected.BACKOFF_SEC[0])

    def test_a_device_back_starts_the_next_drop_over(self):
        self.run_for([DOWN], 200)
        self.assertGreater(len(self.searches), 2)
        self.run_for([UP], 5, start=200)
        self.searches.clear()
        times = self.run_for([DOWN], 100, start=1000)
        self.assertEqual(times, [1000 + bridge.KeepConnected.GRACE_SEC, 1000 + bridge.KeepConnected.GRACE_SEC + 30])

    def test_no_network_no_search_and_one_when_it_returns(self):
        self.assertEqual(self.run_for([DOWN], 100, network_up=False), [])
        self.assertEqual(self.run_for([DOWN], 1, start=100), [100])

    def test_an_unpaired_device_is_not_looked_for(self):
        self.assertEqual(self.run_for([UNPAIRED], 3600), [])

    def test_two_devices_share_one_search(self):
        a = DOWN
        times = self.run_for([a, OTHER_DOWN], 25)
        self.assertEqual(times, [bridge.KeepConnected.GRACE_SEC])
        self.assertEqual(len(self.searches), 1)

    def test_a_second_device_has_its_own_grace(self):
        self.run_for([DOWN], 100)
        self.searches.clear()
        times = self.run_for([DOWN, OTHER_DOWN], 60, start=100)
        self.assertIn(120, times)


if __name__ == "__main__":
    unittest.main()
