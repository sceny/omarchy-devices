"""kdeconnect-bridge checks: `python3 -m unittest discover -s tests`.

Only the pieces that need no D-Bus: contacts from vCards, number keys, the
naming of fetched attachments, and which D-Bus call each send makes (with the
bus replaced, so nothing reaches a device). All data is made up.
"""

import contextlib
import importlib.machinery
import importlib.util
import os
import tempfile
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
BRIDGE = os.path.join(HERE, "..", "bin", "kdeconnect-bridge")
loader = importlib.machinery.SourceFileLoader("kdeconnect_bridge", BRIDGE)
spec = importlib.util.spec_from_loader("kdeconnect_bridge", loader)
bridge = importlib.util.module_from_spec(spec)
loader.exec_module(bridge)


class Sends(unittest.TestCase):
    """Text, links and ping messages: the method and argument types the
    daemon's interfaces declare (shareText(s), shareUrl(s), sendPing(s))."""

    def setUp(self):
        self.calls = []
        self.saved = (bridge.bus, bridge.call, bridge.device_name)

        def fake_call(conn, path, iface, method, args=None, sig=None):
            if sig:
                bridge.GLib.Variant(sig, args)   # the types must hold
            self.calls.append((path.rsplit("/", 1)[-1], iface.rsplit(".", 1)[-1], method, args, sig))
            return ()
        bridge.bus = lambda: None
        bridge.call = fake_call
        bridge.device_name = lambda conn, device_id: "Pixel 8"

    def tearDown(self):
        bridge.bus, bridge.call, bridge.device_name = self.saved

    def run_quiet(self, argv):
        with open(os.devnull, "w") as null:
            with contextlib.redirect_stdout(null), contextlib.redirect_stderr(null):
                return bridge.act(argv)

    def test_text_goes_whole_to_share_text(self):
        self.assertEqual(self.run_quiet(["text", "d1", "two  spaces\nand a line"]), bridge.EXIT_OK)
        self.assertEqual(self.calls, [("share", "share", "shareText", ("two  spaces\nand a line",), "(s)")])

    def test_link_goes_to_share_url(self):
        self.assertEqual(self.run_quiet(["url", "d1", " https://example.com/a?b=1 "]), bridge.EXIT_OK)
        self.assertEqual(self.calls, [("share", "share", "shareUrl", ("https://example.com/a?b=1",), "(s)")])

    def test_ping_with_and_without_a_message(self):
        self.run_quiet(["ping", "d1"])
        self.run_quiet(["ping", "d1", "Leaving now"])
        self.assertEqual(self.calls, [("ping", "ping", "sendPing", None, None),
                                      ("ping", "ping", "sendPing", ("Leaving now",), "(s)")])

    def test_nothing_to_send_sends_nothing(self):
        self.assertEqual(self.run_quiet(["text", "d1", "  "]), bridge.EXIT_CANCELLED)
        self.assertEqual(self.calls, [])


class DigitsKey(unittest.TestCase):
    def test_last_ten_digits(self):
        self.assertEqual(bridge.digits_key("+1 (514) 555-0123"), "5145550123")
        self.assertEqual(bridge.digits_key("15145550123"), "5145550123")

    def test_short_codes_stay_whole(self):
        self.assertEqual(bridge.digits_key("55555"), "55555")
        self.assertEqual(bridge.digits_key(""), "")


class Contacts(unittest.TestCase):
    def test_names_by_number_from_vcards(self):
        with tempfile.TemporaryDirectory() as home:
            folder = os.path.join(home, ".local/share/kpeoplevcard/kdeconnect-dev1")
            os.makedirs(folder)
            with open(os.path.join(folder, "a.vcf"), "w") as f:
                f.write("BEGIN:VCARD\r\nVERSION:2.1\r\nFN:Alex Example\r\n"
                        "TEL;CELL:+1 514-555-0123\r\nTEL;HOME:5145550199\r\nEND:VCARD\r\n")
            with open(os.path.join(folder, "b.vcf"), "w") as f:
                # A folded line: the continuation starts with a space.
                f.write("BEGIN:VCARD\r\nFN:Sam\r\n  Example\r\nTEL:+15145550150\r\nEND:VCARD\r\n")
            old = os.environ.get("HOME")
            os.environ["HOME"] = home
            try:
                names, entries = bridge.read_contacts("dev1")
            finally:
                if old is not None:
                    os.environ["HOME"] = old
        self.assertEqual(names["5145550123"], "Alex Example")
        self.assertEqual(names["5145550199"], "Alex Example")
        self.assertEqual(names["5145550150"], "Sam Example")
        self.assertEqual(len(entries), 3)

    def test_no_folder_means_no_contacts(self):
        with tempfile.TemporaryDirectory() as home:
            old = os.environ.get("HOME")
            os.environ["HOME"] = home
            try:
                self.assertEqual(bridge.read_contacts("missing"), ({}, []))
            finally:
                if old is not None:
                    os.environ["HOME"] = old


class AttachmentNames(unittest.TestCase):
    """The daemon saves fetched files without an extension; the bridge links
    them under a typed name so a viewer will open them."""

    def make(self, folder):
        sms = bridge.Sms.__new__(bridge.Sms)   # no D-Bus: only the naming state
        sms.thumbs = folder
        sms.file_mimes = {}
        return sms

    def test_links_under_a_typed_name(self):
        with tempfile.TemporaryDirectory() as tmp:
            target = os.path.join(tmp, "PART_1_image_1")
            open(target, "wb").close()
            sms = self.make(tmp)
            sms.file_mimes["PART_1_image_1"] = "image/jpeg"
            link = sms.named(target, "PART_1_image_1")
            self.assertTrue(link.endswith(".jpg"))
            self.assertEqual(os.path.realpath(link), os.path.realpath(target))

    def test_unknown_type_keeps_the_path(self):
        with tempfile.TemporaryDirectory() as tmp:
            sms = self.make(tmp)
            self.assertEqual(sms.named("/x/file", "file"), "/x/file")


if __name__ == "__main__":
    unittest.main()
