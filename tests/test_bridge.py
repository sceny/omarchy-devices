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

    def test_dial_shares_a_tel_link(self):
        self.assertEqual(self.run_quiet(["dial", "d1", "+1 (514) 555-0123"]), bridge.EXIT_OK)
        self.assertEqual(self.calls, [("share", "share", "shareUrl", ("tel:+15145550123",), "(s)")])

    def test_dial_without_a_number_sends_nothing(self):
        self.assertEqual(self.run_quiet(["dial", "d1", " - "]), bridge.EXIT_CANCELLED)
        self.assertEqual(self.calls, [])

    def test_ping_with_and_without_a_message(self):
        self.run_quiet(["ping", "d1"])
        self.run_quiet(["ping", "d1", "Leaving now"])
        self.assertEqual(self.calls, [("ping", "ping", "sendPing", None, None),
                                      ("ping", "ping", "sendPing", ("Leaving now",), "(s)")])

    def test_nothing_to_send_sends_nothing(self):
        self.assertEqual(self.run_quiet(["text", "d1", "  "]), bridge.EXIT_CANCELLED)
        self.assertEqual(self.calls, [])


class Resync(unittest.TestCase):
    """The sms bridge asks the phone again when the daemon comes back after
    a restart, retrying while the device reconnects."""

    def make(self):
        sms = bridge.Sms.__new__(bridge.Sms)   # no D-Bus: calls are recorded
        sms.calls = []
        sms.fail = 0

        def call(method, args=None, sig=None, timeout=10000):
            if sms.fail > 0:
                sms.fail -= 1
                raise bridge.GLib.Error("not yet")
            sms.calls.append(method)
        sms.call = call
        sms.out = lambda obj: None
        return sms

    def test_daemon_back_triggers_a_request_with_retries(self):
        sms = self.make()
        timers = []
        saved = bridge.GLib.timeout_add_seconds
        bridge.GLib.timeout_add_seconds = lambda sec, fn: timers.append(fn)
        try:
            gone = bridge.GLib.Variant("(sss)", (bridge.BUS_NAME, ":1.5", ""))
            sms.on_owner_changed(None, None, None, None, None, gone)
            self.assertEqual(timers, [], "the daemon going away asks nothing")
            back = bridge.GLib.Variant("(sss)", (bridge.BUS_NAME, "", ":1.9"))
            sms.on_owner_changed(None, None, None, None, None, back)
            sms.fail = 2
            attempt = timers[0]
            self.assertTrue(attempt(), "retry while the device reconnects")
            self.assertTrue(attempt())
            self.assertFalse(attempt(), "stop once the call went through")
            self.assertEqual(sms.calls, ["requestAllConversationThreads"])
        finally:
            bridge.GLib.timeout_add_seconds = saved


class History(unittest.TestCase):
    """How far a conversation goes is learnt only from the answer to a page
    asked for: the daemon's count after any other batch (every thread's
    latest message) is what it holds, not the conversation's length."""

    def make(self):
        sms = bridge.Sms.__new__(bridge.Sms)   # no D-Bus: calls are recorded
        sms.path = "/dev"
        sms.cache, sms.latest, sms.pending, sms.loaded, sms.settle = {}, {}, {}, {}, {}
        sms.calls, sms.sent = [], []
        sms.call = lambda method, args=None, sig=None, timeout=10000: sms.calls.append((method, args))
        sms.out = sms.sent.append
        sms.remember({"thread": 7, "uid": 1, "date": 100})
        return sms

    def loaded(self, sms, tid, count):
        params = bridge.GLib.Variant("(xt)", (tid, count))
        sms.on_signal(None, None, "/dev", None, "conversationLoaded", params)

    def test_a_count_nobody_asked_for_does_not_end_the_history(self):
        sms = self.make()
        self.loaded(sms, 7, 1)          # every thread's latest message
        self.assertEqual(sms.loaded, {})
        saved = bridge.GLib.timeout_add_seconds
        bridge.GLib.timeout_add_seconds = lambda sec, fn: 1
        try:
            sms.load(7, 0, 30)
        finally:
            bridge.GLib.timeout_add_seconds = saved
        self.assertEqual(sms.calls, [("requestConversation", (7, 0, 30))], "the phone is asked for the page")
        self.assertEqual(sms.sent, [], "no answer yet: one message is not the conversation")

    def test_the_answer_to_a_page_says_how_far_it_goes(self):
        sms = self.make()
        sms.pending[7] = [(0, 30, 1)]
        saved = bridge.GLib.source_remove
        bridge.GLib.source_remove = lambda source: True
        try:
            for uid in range(2, 26):
                sms.remember({"thread": 7, "uid": uid, "date": 100 + uid})
            self.loaded(sms, 7, 25)
        finally:
            bridge.GLib.source_remove = saved
        self.assertEqual(sms.loaded, {7: 25})
        [page] = [e for e in sms.sent if e.get("ev") == "messages"]
        self.assertEqual(len(page["messages"]), 25)
        self.assertFalse(page["hasMore"], "all 25 are here")


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


class Conversations(unittest.TestCase):
    """A conversation notification's markup from the daemon becomes plain
    {sender, text} pairs; nothing in it is ever interpreted."""

    def test_senders_and_messages(self):
        markup = ("Running late<br/><b>~Alex Rivera</b>\nSee you at six<br/>Bring chairs"
                  "<br/><b>Sam</b>\nOK &amp; thanks \U0001F389")
        self.assertEqual(bridge.parse_conversation(markup), [
            {"sender": "", "text": "Running late"},
            {"sender": "~Alex Rivera", "text": "See you at six"},
            {"sender": "", "text": "Bring chairs"},
            {"sender": "Sam", "text": "OK & thanks \U0001F389"},
        ])

    def test_line_breaks_inside_a_message_stay(self):
        self.assertEqual(bridge.parse_conversation("<b>Sam</b>\nOne\n\nTwo")[0]["text"], "One\n\nTwo")

    def test_markup_in_a_message_stays_text(self):
        # The daemon escapes content, so tags someone typed arrive as entities:
        # they come out as the characters typed, for plain-text display.
        escaped = "&lt;script&gt;alert(1)&lt;/script&gt; &lt;b&gt;x&lt;/b&gt;&lt;br/&gt; &lt;img src=x onerror=y&gt;"
        [m] = bridge.parse_conversation("<b>Eve &lt;/b&gt;</b>\n" + escaped)
        self.assertEqual(m["sender"], "Eve </b>")
        self.assertEqual(m["text"], "<script>alert(1)</script> <b>x</b><br/> <img src=x onerror=y>")

    def test_an_escaped_marker_does_not_split(self):
        self.assertEqual(len(bridge.parse_conversation("a &lt;br/&gt; b")), 1)

    def test_anything_else_is_one_message_as_it_came(self):
        self.assertEqual(bridge.parse_conversation("<b>no close"), [{"sender": "", "text": "<b>no close"}])
        self.assertEqual(bridge.parse_conversation(""), [])

    def test_plain_text_for_one_string(self):
        messages = [{"sender": "Sam", "text": "Hi"}, {"sender": "", "text": "Again"}]
        self.assertEqual(bridge.conversation_text(messages), "Sam: Hi\nAgain")


class Calls(unittest.TestCase):
    """What KDE Connect's callReceived(event, number, contactName) becomes."""

    def test_ringing_and_missed(self):
        self.assertEqual(bridge.call_event("callReceived", "+15145550123", "Alex Rivera", 1000),
                         {"event": "ringing", "number": "+15145550123", "name": "Alex Rivera", "at": 1000})
        self.assertEqual(bridge.call_event("missedCall", "+15145550123", "Alex Rivera", 2000)["event"], "missed")

    def test_a_name_that_is_the_number_is_no_name(self):
        # KDE Connect fills contactName with the number when it knows no name.
        self.assertEqual(bridge.call_event("callReceived", "5550123", "5550123", 0)["name"], "")

    def test_other_events_are_ignored(self):
        self.assertIsNone(bridge.call_event("talking", "5550123", "", 0))
        self.assertIsNone(bridge.call_event("sms", "5550123", "", 0))
