"""No real personal data in the tree (AGENTS.md), held by a test that names
file:line instead of by a reviewer reading every diff.

Every tracked text file is read for the shapes a person's data takes:

  phone numbers   a number that is not in the 555 exchange
  email           an address outside EMAIL_ALLOWED
  device ids      KDE Connect's 32 hex digits or its uuid shape, and a
                  Bluetooth address, that look random
  adb serials     a literal given to `serial` that is not a fixture's

A made-up value passes: a 555 number, an `example.invalid` address, an id of
at most four distinct digits, the serials in SERIAL_FIXTURES. A name or a
message cannot be told from a made-up one by a script; the reviewer reads those
(docs/internals/releasing.md). The lint is run on planted text as well as on
the tree (`PlantedCases`)."""

import os
import re
import subprocess
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, ".."))

BINARY = re.compile(r"\.(png|jpe?g|gif|webp|ico|svg|ttf|otf|woff2?|pdf|zip|gz)$", re.I)
SKIP_DIRS = {".git", ".claude", ".paperclip", "node_modules", "__pycache__"}
# Resolved package versions and hashes are not people's data.
LOCKFILES = {"package-lock.json"}

# Addresses that are not a person's: reserved example domains, and the
# addresses a tool writes for itself.
EMAIL_ALLOWED_DOMAINS = {"example.invalid", "example.com", "example.org", "example.net"}
EMAIL_ALLOWED = {"noreply@anthropic.com", "noreply@github.com"}
# `name@autostart.service` is a systemd unit, not a mailbox.
NOT_A_TLD = {"service", "socket", "target", "timer", "path", "mount", "slice", "scope"}

# This file plants real-looking values to prove the lint fails on them.
SELF = "tests/test_personal_data.py"

SERIAL_FIXTURES = {"0A1B2C3D", "SERIAL"}
MAC_FIXTURES = {"00:11:22:33:44:55"}

EMAIL = re.compile(r"(?<![\w.%+-])[\w.%+-]+@([A-Za-z0-9-]+(?:\.[A-Za-z0-9-]+)*\.([A-Za-z]{2,}))\b")
E164 = re.compile(r"(?<![\w.+])\+\d[\d ()\-.]{6,16}\d(?![\w.])")
NANP = re.compile(r"(?<![\d.])\(?\d{3}\)?[ .-]\d{3}[ .-]\d{4}(?![\d.])")
HEX32 = re.compile(r"(?<![0-9A-Za-z])[0-9A-Fa-f]{32}(?![0-9A-Za-z])")
UUID = re.compile(r"(?<![0-9A-Za-z])[0-9A-Fa-f]{8}[-_][0-9A-Fa-f]{4}[-_][0-9A-Fa-f]{4}[-_][0-9A-Fa-f]{4}[-_][0-9A-Fa-f]{12}(?![0-9A-Za-z])")
MAC = re.compile(r"(?<![0-9A-Fa-f:])(?:[0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}(?![0-9A-Fa-f:])")
SERIAL = re.compile(r"""\bserial["']?\s*[:=]\s*["']([A-Za-z0-9]{6,})["']""", re.I)
# The Bluetooth base uuid every service uuid is built on.
BLUETOOTH_BASE = re.compile(r"^[0-9a-f]{8}-0000-1000-8000-00805f9b34fb$", re.I)


def made_up_id(value):
    """An id of at most four distinct digits is a fixture's (`aaaa…`, `0000…1`)."""
    return len(set(re.sub(r"[^0-9A-Fa-f]", "", value).lower())) <= 4


def fictional(digits):
    """A 555 exchange is the North American range kept for made-up numbers."""
    return digits[-7:-4] == "555"


def line_problems(line):
    """Why a line holds personal data, one reason per hit."""
    found = []
    numbered = []
    for m in E164.finditer(line):
        digits = re.sub(r"\D", "", m.group(0))
        if 8 <= len(digits) <= 15:
            numbered.append(m.span())
            if not fictional(digits):
                found.append("phone number %s: use a 555 number" % m.group(0))
    for m in NANP.finditer(line):
        inside = any(a <= m.start() and m.end() <= b for a, b in numbered)
        if not inside and not fictional(re.sub(r"\D", "", m.group(0))):
            found.append("phone number %s: use a 555 number" % m.group(0))
    for m in EMAIL.finditer(line):
        address, domain, tld = m.group(0), m.group(1).lower(), m.group(2).lower()
        if tld in NOT_A_TLD or address.lower() in EMAIL_ALLOWED or domain in EMAIL_ALLOWED_DOMAINS:
            continue
        found.append("email address %s: use an example.invalid address" % address)
    for m in HEX32.finditer(line):
        if not made_up_id(m.group(0)):
            found.append("device id %s: use a made-up id" % m.group(0))
    for m in UUID.finditer(line):
        if not BLUETOOTH_BASE.match(m.group(0)) and not made_up_id(m.group(0)):
            found.append("device id %s: use a made-up id" % m.group(0))
    for m in MAC.finditer(line):
        if not made_up_id(m.group(0)) and m.group(0) not in MAC_FIXTURES:
            found.append("Bluetooth address %s: use a made-up address" % m.group(0))
    for m in SERIAL.finditer(line):
        value = m.group(1)
        if value not in SERIAL_FIXTURES and not value.startswith("emulator-"):
            found.append("adb serial %s: use a fixture's serial" % value)
    return found


def text_problems(name, text):
    found = []
    for number, line in enumerate(text.split("\n"), 1):
        for why in line_problems(line):
            found.append("%s:%d: %s" % (name, number, why))
    return found


def tracked_files():
    """The files a clone holds: git's list, else a walk (a copy without .git)."""
    try:
        out = subprocess.run(["git", "-C", ROOT, "ls-files", "-z"], capture_output=True, check=True).stdout
        names = [n for n in out.decode().split("\0") if n]
    except (OSError, subprocess.CalledProcessError):
        names = []
        for folder, dirs, files in os.walk(ROOT):
            dirs[:] = [d for d in dirs if d not in SKIP_DIRS]
            names += [os.path.relpath(os.path.join(folder, f), ROOT) for f in files]
    return sorted(n for n in names if not BINARY.search(n) and os.path.basename(n) not in LOCKFILES and n != SELF
                  and os.path.isfile(os.path.join(ROOT, n)))


def tree_problems():
    found = []
    for name in tracked_files():
        try:
            with open(os.path.join(ROOT, name), encoding="utf-8") as f:
                text = f.read()
        except UnicodeDecodeError:
            continue
        found += text_problems(name, text)
    return found


class NoPersonalDataInTheTree(unittest.TestCase):
    def test_the_tree_holds_only_made_up_values(self):
        found = tree_problems()
        self.assertEqual(found, [], "\n".join(found))

    def test_the_tree_is_read(self):
        names = tracked_files()
        for expected in ("Model.js", "bin/kdeconnect-bridge", "tests/test_bridge.py"):
            self.assertIn(expected, names)


class PlantedCases(unittest.TestCase):
    def reasons(self, line):
        return [w.split(":")[0] for w in line_problems(line)]

    def test_a_real_looking_number_fails_and_a_555_number_passes(self):
        self.assertEqual(self.reasons("call +14165550123 or +1 (416) 555-0123 or 514-555-0100 or +1 555 0100"), [])
        for line in ("call +14162345678", "call +1 416 234 5678", "call (416) 234-5678", "call 416-234-5678",
                     "tel +44 20 7946 0958"):
            self.assertEqual(len(self.reasons(line)), 1, line)

    def test_an_address_or_a_version_is_not_a_number(self):
        for line in ("host 192.168.1.20", "gateway 100.101.102.103", "version 2026.1012.0",
                     "Bluetooth 0000-1000-8000", "range 2560 - 1152 - 5"):
            self.assertEqual(self.reasons(line), [], line)

    def test_an_email_outside_the_allowlist_fails(self):
        self.assertEqual(self.reasons("a@example.invalid b@example.com noreply@anthropic.com"), [])
        self.assertEqual(self.reasons("app-org.kde.kdeconnect.daemon@autostart.service"), [])
        self.assertEqual(len(self.reasons("write to jo.doe@gmail.com")), 1)
        self.assertEqual(len(self.reasons("write to someone@example.invalid.net")), 1)

    def test_a_random_device_id_fails_and_a_made_up_one_passes(self):
        self.assertEqual(self.reasons("id 00000000000000000000000001000000"), [])
        self.assertEqual(self.reasons("id aaaaaaaaaaaaaaaa0000000000000000"), [])
        self.assertEqual(self.reasons("uuid 0000110b-0000-1000-8000-00805f9b34fb"), [])
        self.assertEqual(self.reasons("mac 00:00:00:00:00:01"), [])
        for line in ("id 4d1e2b9a7c3f45a08b6d19e0f2a7c354", "id 4d1e2b9a_7c3f_45a0_8b6d_19e0f2a7c354",
                     "id 4d1e2b9a-7c3f-45a0-8b6d-19e0f2a7c354", "mac 3C:5A:B4:1E:77:9D"):
            self.assertEqual(len(self.reasons(line)), 1, line)

    def test_a_real_serial_fails_and_a_fixture_passes(self):
        self.assertEqual(self.reasons('serial="0A1B2C3D"'), [])
        self.assertEqual(self.reasons('"serial": "emulator-5554"'), [])
        self.assertEqual(len(self.reasons('"serial": "R58M30ABCDE"')), 1)
        self.assertEqual(len(self.reasons("serial='9C4E1F7A22B8'")), 1)

    def test_a_problem_names_file_and_line(self):
        found = text_problems("docs/x.md", "fine\ncall +14162345678\n")
        self.assertEqual(len(found), 1)
        self.assertTrue(found[0].startswith("docs/x.md:2: phone number"), found)


if __name__ == "__main__":
    unittest.main()
