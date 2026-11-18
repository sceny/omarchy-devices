"""Wireless debugging turned on again from here (#590): over a USB cable, a
TCP connection adb already has, or adb's TCP port at the address the bridge
holds for the device, connected for it and disconnected after; else the USB
step. adb is replaced; nothing reaches a device."""

import importlib.machinery
import importlib.util
import os
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
BRIDGE = os.path.join(HERE, "..", "bin", "kdeconnect-bridge")
loader = importlib.machinery.SourceFileLoader("kdeconnect_bridge_wireless", BRIDGE)
spec = importlib.util.spec_from_loader("kdeconnect_bridge_wireless", loader)
bridge = importlib.util.module_from_spec(spec)
loader.exec_module(bridge)

TURN_ON = ["shell", "settings", "put", "global", "adb_wifi_enabled", "1"]


class FakeAdb:
    """adb's server as the fix sees it: `devices` its connections
    ({serial: (state, usb)}); `answers` what `adb connect` reaches
    ({serial: state}); `serials` each connection's own ro.serialno; `kept`:
    whether the setting stays on (the network allowed before)."""

    def __init__(self, devices=None, answers=None, serials=None, put=0, kept=True):
        self.devices = dict(devices or {})
        self.answers = dict(answers or {})
        self.serials = dict(serials or {})
        self.put = put
        self.kept = kept
        self.calls = []

    def __call__(self, args, timeout=10):
        self.calls.append(list(args))
        if args[:2] == ["devices", "-l"]:
            lines = ["List of devices attached"]
            for serial, (state, usb) in self.devices.items():
                lines.append("%s %s %s model:Pixel_8" % (serial, state, "usb:1-1" if usb else ""))
            return 0, "\n".join(lines) + "\n"
        if args[0] == "connect":
            if args[1] in self.answers:
                self.devices[args[1]] = (self.answers[args[1]], False)
                return 0, "connected to %s" % args[1]
            return 1, "failed to connect to %s" % args[1]
        if args[0] == "disconnect":
            self.devices.pop(args[1], None)
            return 0, "disconnected %s" % args[1]
        if args[0] == "-s" and args[2:] == ["shell", "getprop", "ro.serialno"]:
            return 0, self.serials.get(args[1], args[1]) + "\n"
        if args[0] == "-s" and args[2:] == TURN_ON:
            return self.put, "" if self.put == 0 else "Security exception"
        if args[0] == "-s" and args[2:] == ["shell", "settings", "get", "global", "adb_wifi_enabled"]:
            return 0, "1\n" if self.put == 0 and self.kept else "0\n"
        return 1, "unexpected"

    def turned_on(self):
        return [c[1] for c in self.calls if c[:1] == ["-s"] and c[2:] == TURN_ON]

    def connected(self):
        return [c[1] for c in self.calls if c[:1] == ["connect"]]

    def disconnected(self):
        return [c[1] for c in self.calls if c[:1] == ["disconnect"]]


def turn_on(fake, addresses, known="S1", announced=None):
    return bridge.wireless_on(addresses, known, run=fake, announced=announced, sleep=lambda s: None)


class Transport(unittest.TestCase):

    def test_usb_first(self):
        fake = FakeAdb({"S1": ("device", True), "192.0.2.7:5555": ("device", False)})
        self.assertEqual(turn_on(fake, ["192.0.2.7"]), (True, "Wireless debugging is on"))
        self.assertEqual(fake.turned_on(), ["S1"])
        self.assertEqual(fake.connected(), [], "nothing connected while a connection works")

    def test_usb_of_another_device_is_not_used(self):
        fake = FakeAdb({"S2": ("device", True)})
        self.assertEqual(turn_on(fake, []), (False, bridge.WIRELESS_USB))
        self.assertEqual(fake.turned_on(), [])

    def test_a_tcp_connection_already_open_is_used_and_kept(self):
        fake = FakeAdb({"192.0.2.7:5555": ("device", False)}, serials={"192.0.2.7:5555": "S1"})
        self.assertEqual(turn_on(fake, ["192.0.2.7"])[0], True)
        self.assertEqual(fake.turned_on(), ["192.0.2.7:5555"])
        self.assertEqual(fake.disconnected(), [], "not this fix's connection: left open")

    def test_an_ipv6_connection_matches_however_it_is_written(self):
        fake = FakeAdb({"[2001:db8::7]:5555": ("device", False)}, serials={"[2001:db8::7]:5555": "S1"})
        self.assertEqual(turn_on(fake, ["2001:0db8::0007"])[0], True)
        self.assertEqual(fake.connected(), [])

    def test_a_tcp_connection_at_another_address_is_not_used(self):
        fake = FakeAdb({"198.51.100.4:5555": ("device", False)})
        self.assertEqual(turn_on(fake, ["192.0.2.7"])[0], False)
        self.assertEqual(fake.turned_on(), [])

    def test_its_tcp_port_is_connected_for_it_and_disconnected_after(self):
        fake = FakeAdb(answers={"192.0.2.7:5555": "device"}, serials={"192.0.2.7:5555": "S1"})
        self.assertEqual(turn_on(fake, ["192.0.2.7"]), (True, "Wireless debugging is on"))
        self.assertEqual(fake.connected(), ["192.0.2.7:5555"])
        self.assertEqual(fake.turned_on(), ["192.0.2.7:5555"])
        self.assertEqual(fake.disconnected(), ["192.0.2.7:5555"])
        self.assertNotIn("192.0.2.7:5555", fake.devices)

    def test_disconnected_even_when_turning_it_on_fails(self):
        fake = FakeAdb(answers={"192.0.2.7:5555": "device"}, serials={"192.0.2.7:5555": "S1"}, put=1)
        self.assertEqual(turn_on(fake, ["192.0.2.7"]), (False, "Security exception"))
        self.assertEqual(fake.disconnected(), ["192.0.2.7:5555"])

    def test_a_network_never_allowed_asks_on_the_device(self):
        fake = FakeAdb(answers={"192.0.2.7:5555": "device"}, serials={"192.0.2.7:5555": "S1"}, kept=False)
        self.assertEqual(turn_on(fake, ["192.0.2.7"]), (False, bridge.WIRELESS_ALLOW))
        self.assertEqual(fake.disconnected(), ["192.0.2.7:5555"], "read back before it is disconnected")
        self.assertLess(fake.calls.index(["-s", "192.0.2.7:5555", "shell", "settings", "get", "global", "adb_wifi_enabled"]),
                        fake.calls.index(["disconnect", "192.0.2.7:5555"]))

    def test_a_device_that_does_not_trust_this_computer_is_left(self):
        fake = FakeAdb(answers={"192.0.2.7:5555": "unauthorized"})
        self.assertEqual(turn_on(fake, ["192.0.2.7"]), (False, bridge.WIRELESS_USB))
        self.assertEqual(fake.turned_on(), [], "adb's key check is the gate")
        self.assertEqual(fake.disconnected(), ["192.0.2.7:5555"])

    def test_another_device_at_its_address_is_left(self):
        fake = FakeAdb(answers={"192.0.2.7:5555": "device"}, serials={"192.0.2.7:5555": "S9"})
        self.assertEqual(turn_on(fake, ["192.0.2.7"])[0], False)
        self.assertEqual(fake.turned_on(), [])
        self.assertEqual(fake.disconnected(), ["192.0.2.7:5555"])

    def test_nothing_reaches_it_the_usb_step(self):
        fake = FakeAdb()
        self.assertEqual(turn_on(fake, ["192.0.2.7"]), (False, bridge.WIRELESS_USB))
        self.assertEqual(fake.connected(), ["192.0.2.7:5555"])
        self.assertIn("USB cable", bridge.WIRELESS_USB)

    def test_each_address_is_tried_in_order(self):
        fake = FakeAdb(answers={"100.101.102.103:5555": "device"}, serials={"100.101.102.103:5555": "S1"})
        self.assertEqual(turn_on(fake, ["192.0.2.7", "100.101.102.103"])[0], True)
        self.assertEqual(fake.connected(), ["192.0.2.7:5555", "100.101.102.103:5555"])

    def test_no_serial_remembered_takes_the_connection_found(self):
        fake = FakeAdb(answers={"192.0.2.7:5555": "device"})
        self.assertEqual(turn_on(fake, ["192.0.2.7"], known="")[0], True)

    def test_waits_for_the_announce_then_returns(self):
        seen = iter([False, False, True])
        fake = FakeAdb({"S1": ("device", True)})
        self.assertEqual(turn_on(fake, [], announced=lambda: next(seen))[0], True)
        self.assertEqual(next(seen, "done"), "done", "asked until it announced")

    def test_the_wait_is_bounded(self):
        now = [0.0]

        def sleep(s):
            now[0] += s
        fake = FakeAdb({"S1": ("device", True)})
        ok, _ = bridge.wireless_on([], "S1", run=fake, announced=lambda: False, sleep=sleep, clock=lambda: now[0], wait=3)
        self.assertTrue(ok)
        self.assertEqual(now[0], bridge.WIRELESS_SETTLE_SEC + 3, "the read-back, then at most the wait")


class Address(unittest.TestCase):

    def test_an_ip_literal_on_adb_tcp_port(self):
        self.assertEqual(bridge.tcp_serial("192.0.2.7"), "192.0.2.7:5555")
        self.assertEqual(bridge.tcp_serial("2001:db8::7"), "[2001:db8::7]:5555")

    def test_anything_else_is_refused(self):
        for bad in ["", "phone.local", "192.0.2.7:5555", "192.0.2.7; reboot", "-s", "--help", " 192.0.2.7",
                    "0.0.0.0", "224.0.0.251", "fe80::1%wlan0", "::", None, 3232235777, ["192.0.2.7"]]:
            self.assertEqual(bridge.tcp_serial(bad), "", repr(bad))

    def test_only_addresses_it_holds_are_connected(self):
        fake = FakeAdb()
        turn_on(fake, ["phone.local", "192.0.2.7; reboot", "192.0.2.7"])
        self.assertEqual(fake.connected(), ["192.0.2.7:5555"])

    def test_tcp_host(self):
        self.assertEqual(bridge.tcp_host("192.0.2.7:5555"), "192.0.2.7")
        self.assertEqual(bridge.tcp_host("[2001:db8::7]:5555"), "2001:db8::7")
        self.assertEqual(bridge.tcp_host("[2001:0db8:0:0::7]:5555"), "2001:db8::7", "as tcp_serial writes it")
        self.assertEqual(bridge.tcp_host("999.1.1.1:5555"), "")
        self.assertEqual(bridge.tcp_host("adb-S1-abc._adb-tls-connect._tcp"), "")
        self.assertEqual(bridge.tcp_host("S1"), "")


if __name__ == "__main__":
    unittest.main()
