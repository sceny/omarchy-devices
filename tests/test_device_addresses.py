"""No real device address in the tree (AGENTS.md, #316): an adb endpoint is an
address and a port (`192.168.1.20:37099`), and a real one names a person's
home network. Every tracked text file is read; an address with a port must be
one of the reviewed values below, each with the reason it is not real. Phone
numbers, emails, device ids and adb serials are `test_personal_data.py`."""

import ipaddress
import os
import re
import sys
import unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import test_personal_data as personal_data  # noqa: E402

ROOT = personal_data.ROOT
SELF = "tests/test_device_addresses.py"

ENDPOINT = re.compile(r"(?<![\d.])((?:\d{1,3}\.){3}\d{1,3}):(\d{2,5})(?![\d.])")

# Ranges no network uses on its own: RFC 5737 documentation addresses and the
# loopback.
RESERVED = [ipaddress.ip_network(n) for n in ("192.0.2.0/24", "198.51.100.0/24", "203.0.113.0/24", "127.0.0.0/8")]

# Reviewed values, each with why it is not a real device.
REVIEWED = {
    "192.168.1.20": "the fixtures' phone on a made-up home network",
    "192.168.1.23": "a second made-up phone on the same made-up network",
    "192.168.1.30": "a made-up other device on the same made-up network",
    "100.101.102.103": "the fixtures' phone on a made-up mesh; a sequence, not an assigned one",
    "8.8.8.8": "a public DNS resolver, the same for everyone",
    "1.1.1.1": "a public DNS resolver, the same for everyone",
    "10.0.2.2": "the Android emulator's alias for its host, the same on every machine",
}


def endpoint_problems(line):
    found = []
    for m in ENDPOINT.finditer(line):
        address = m.group(1)
        try:
            ip = ipaddress.ip_address(address)
        except ValueError:
            continue
        if address in REVIEWED or any(ip in net for net in RESERVED):
            continue
        found.append("device address %s: use a documentation address (192.0.2.x) or add it to REVIEWED with why" % m.group(0))
    return found


def text_problems(name, text):
    return ["%s:%d: %s" % (name, number, why)
            for number, line in enumerate(text.split("\n"), 1) for why in endpoint_problems(line)]


def tracked_files():
    return [n for n in personal_data.tracked_files() if n != SELF]


def read(name):
    with open(os.path.join(ROOT, name), encoding="utf-8") as f:
        return f.read()


class NoRealDeviceAddress(unittest.TestCase):
    def test_every_endpoint_in_the_tree_is_reviewed(self):
        found = []
        for name in tracked_files():
            try:
                found += text_problems(name, read(name))
            except UnicodeDecodeError:
                continue
        self.assertEqual(found, [], "\n".join(found))

    def test_the_tree_is_read(self):
        names = tracked_files()
        for expected in ("Model.js", "bin/kdeconnect-bridge", "tests/test_bridge.py"):
            self.assertIn(expected, names)

    def test_every_reviewed_address_says_why_and_is_still_used(self):
        used = set()
        for name in tracked_files():
            try:
                used.update(m.group(1) for m in ENDPOINT.finditer(read(name)))
            except UnicodeDecodeError:
                continue
        self.assertTrue(all(len(why) > 10 for why in REVIEWED.values()))
        self.assertEqual(sorted(set(REVIEWED) - used), [], "remove the entries nothing uses")


class PlantedCases(unittest.TestCase):
    def test_a_real_looking_endpoint_fails_naming_file_and_line(self):
        for line in ("adb connect 192.168.1.77:5555", "serial 10.20.30.40:37099", "pair 100.64.12.9:41000",
                     "pair 172.16.5.9:41000", "pair 84.12.5.9:41000"):
            self.assertEqual(len(endpoint_problems(line)), 1, line)
        found = text_problems("docs/x.md", "fine\nadb connect 192.168.1.77:5555\n")
        self.assertEqual(len(found), 1)
        self.assertTrue(found[0].startswith("docs/x.md:2: device address 192.168.1.77:5555"), found)

    def test_reviewed_reserved_and_bare_addresses_pass(self):
        for line in ("adb connect 192.168.1.20:5555", "pair 192.0.2.20:37099", "127.0.0.1:1716", "10.0.2.2:1716",
                     "host 192.168.1.77", "version 2026.1012.0:5", "ip 192.168.1.256:5555 is not one"):
            self.assertEqual(endpoint_problems(line), [], line)


if __name__ == "__main__":
    unittest.main()
