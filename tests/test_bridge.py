"""kdeconnect-bridge checks: `python3 -m unittest discover -s tests`.

Only the pieces that need no D-Bus: contacts from vCards, number keys, the
naming of fetched attachments, and which D-Bus call each send makes (with the
bus replaced, so nothing reaches a device). All data is made up.
"""

import contextlib
import importlib.machinery
import importlib.util
import os
import subprocess
import shutil
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


class Received(unittest.TestCase):
    """Files the device sends: newest first, once each, gone when their
    file is gone; text and links are not files."""

    def test_a_file_arrives_and_leaves(self):
        with tempfile.TemporaryDirectory() as d:
            a = os.path.join(d, "report one.pdf")
            open(a, "w").write("x" * 10)
            entries = []
            self.assertTrue(bridge.note_received(entries, "file://" + a.replace(" ", "%20"), 5))
            self.assertEqual(entries[0], {"path": a, "name": "report one.pdf", "size": 10, "at": 5})
            self.assertFalse(bridge.note_received(entries, "https://example.org", 6), "a link is not a file")
            self.assertFalse(bridge.note_received(entries, "file:///nowhere/at/all.txt", 6), "nothing there")
            self.assertTrue(bridge.note_received(entries, "file://" + a, 7))
            self.assertEqual(len(entries), 1, "the same file once")
            self.assertEqual(entries[0]["at"], 7)
            os.remove(a)
            self.assertTrue(bridge.prune_received(entries))
            self.assertEqual(entries, [])

    def test_the_list_is_capped(self):
        with tempfile.TemporaryDirectory() as d:
            entries = []
            for i in range(bridge.RECEIVED_MAX + 3):
                p = os.path.join(d, "f%d" % i)
                open(p, "w").close()
                bridge.note_received(entries, "file://" + p, i)
            self.assertEqual(len(entries), bridge.RECEIVED_MAX)
            self.assertEqual(entries[0]["name"], "f%d" % (bridge.RECEIVED_MAX + 2), "newest first")

    def test_the_file_round_trips(self):
        with tempfile.TemporaryDirectory() as d:
            path = os.path.join(d, "received.json")
            bridge.save_received(path, [{"path": "/x", "name": "x", "size": 1, "at": 2}])
            self.assertEqual(bridge.load_received(path)[0]["name"], "x")
            self.assertEqual(bridge.load_received(os.path.join(d, "none.json")), [])


class Photos(unittest.TestCase):
    """The newest photos and videos as the phone's gallery finds them
    (Android's media index): all of shared storage but hidden folders,
    .nomedia folders and apps' private ones; the album is the folder that
    holds the file. A made-up tree here."""

    def tree(self, root, files):
        for i, rel in enumerate(files):
            p = os.path.join(root, rel)
            os.makedirs(os.path.dirname(p), exist_ok=True)
            open(p, "w").close()
            os.utime(p, (1000 + i, 1000 + i))

    def test_the_gallery_newest_first_album_by_folder(self):
        with tempfile.TemporaryDirectory() as root:
            wa = "Android/media/com.whatsapp/WhatsApp/Media/"
            self.tree(root, ["DCIM/Camera/a.jpg", "Pictures/Screenshots/b.png", "DCIM/Camera/clip.MP4",
                             wa + "WhatsApp Video/v.mp4", wa + "WhatsApp Video/Sent/s.mp4", "Download/d.jpg",
                             "DCIM/Camera/notes.txt", "DCIM/Camera/.hidden.jpg", "DCIM/.thumbnails/t.jpg",
                             wa + "WhatsApp Images/Private/.nomedia", wa + "WhatsApp Images/Private/p.jpg",
                             "Android/data/app/x.jpg", "Android/obb/app/y.jpg"])
            found, albums, _, complete = bridge.scan_media([root])
            self.assertTrue(complete)
            self.assertEqual([(p["name"], p["album"]) for p in found],
                             [("d.jpg", "Download"), ("s.mp4", "Sent"), ("v.mp4", "WhatsApp Video"), ("clip.MP4", "Camera"),
                              ("b.png", "Screenshots"), ("a.jpg", "Camera")],
                             "newest first; media only; hidden, .nomedia and Android/data, obb left out")
            self.assertEqual([p["video"] for p in found], [False, True, True, True, False, False])
            links = bridge.album_links(albums, 3)
            self.assertEqual([(l["name"], l["count"]) for l in links], [("Camera", 2), ("Download", 1), ("Screenshots", 1)],
                             "the biggest first, then by name")
            self.assertEqual(os.path.relpath(links[0]["path"], root), "DCIM/Camera")

    def test_a_folder_whose_date_did_not_change_is_not_listed_again(self):
        with tempfile.TemporaryDirectory() as root:
            self.tree(root, ["DCIM/Camera/a.jpg", "Pictures/b.jpg"])
            _, _, folders, _ = bridge.scan_media([root])
            listed = []
            saved = bridge.os.scandir
            bridge.os.scandir = lambda path: (listed.append(os.path.relpath(path, root)), saved(path))[1]
            try:
                self.tree(root, ["Pictures/c.jpg"])
                os.utime(os.path.join(root, "Pictures"), ns=(10**18, 10**18))
                found, _, _, _ = bridge.scan_media([root], folders)
            finally:
                bridge.os.scandir = saved
            self.assertEqual(listed, ["Pictures"], "only the folder that changed")
            self.assertEqual(sorted(p["name"] for p in found), ["a.jpg", "b.jpg", "c.jpg"])

    def test_out_of_time_known_folders_count_and_new_ones_wait(self):
        with tempfile.TemporaryDirectory() as root:
            self.tree(root, ["DCIM/Camera/a.jpg"])
            _, _, folders, _ = bridge.scan_media([root])
            self.tree(root, ["Movies/m.mp4"])
            late = iter([0] + [100] * 50)
            found, _, _, complete = bridge.scan_media([root], folders, clock=lambda: next(late), seconds=1)
            self.assertEqual([p["name"] for p in found], ["a.jpg"], "what was known stays")
            self.assertFalse(complete)
            found, _, _, complete = bridge.scan_media([root], folders)
            self.assertEqual(sorted(p["name"] for p in found), ["a.jpg", "m.mp4"])
            self.assertTrue(complete)

    def test_a_root_inside_another_is_read_once(self):
        with tempfile.TemporaryDirectory() as root:
            self.tree(root, ["DCIM/Camera/a.jpg"])
            found, _, _, _ = bridge.scan_media([os.path.join(root, "DCIM", "Camera"), root])
            self.assertEqual([(p["name"], p["album"]) for p in found], [("a.jpg", "Camera")])

    def test_without_sshfs_it_says_so(self):
        saved = bridge.shutil.which
        bridge.shutil.which = lambda name: None
        try:
            self.assertEqual(bridge.photos("p1"), {"ok": False, "missing": "sshfs"})
        finally:
            bridge.shutil.which = saved
class LastSeen(unittest.TestCase):
    """Where a paired device was last connected, kept for its away page."""

    def dev(self, reachable, address="192.168.1.20"):
        return {"id": "p1", "paired": True, "reachable": reachable, "links": ["LAN"], "addresses": [address]}

    def test_connected_then_away(self):
        seen = {}
        self.assertTrue(bridge.note_seen(seen, [self.dev(True)], 1000), "first sight is written")
        self.assertFalse(bridge.note_seen(seen, [self.dev(True)], 2000), "the same place a second later is not")
        self.assertEqual(seen["p1"]["at"], 2000, "but its time moves on in memory")
        self.assertTrue(bridge.note_seen(seen, [self.dev(False)], 3000), "leaving is written")
        snap = bridge.with_seen({"devices": [self.dev(False)]}, seen)
        self.assertEqual(snap["devices"][0]["lastSeen"], {"link": "LAN", "address": "192.168.1.20", "at": 2000})

    def test_a_connected_device_is_written_every_few_minutes(self):
        seen = {}
        bridge.note_seen(seen, [self.dev(True)], 0)
        self.assertFalse(bridge.note_seen(seen, [self.dev(True)], bridge.SEEN_SAVE_MS - 1))
        self.assertTrue(bridge.note_seen(seen, [self.dev(True)], bridge.SEEN_SAVE_MS))

    def test_a_new_address_is_written(self):
        seen = {}
        bridge.note_seen(seen, [self.dev(True)], 0)
        self.assertTrue(bridge.note_seen(seen, [self.dev(True, "10.0.0.5")], 10))

    def test_connected_or_unknown_carries_nothing(self):
        seen = {}
        bridge.note_seen(seen, [self.dev(True)], 0)
        self.assertIsNone(bridge.with_seen({"devices": [self.dev(True)]}, seen)["devices"][0]["lastSeen"])
        self.assertIsNone(bridge.with_seen({"devices": [dict(self.dev(False), id="other")]}, seen)["devices"][0]["lastSeen"])

    def test_the_file_round_trips(self):
        with tempfile.TemporaryDirectory() as d:
            path = os.path.join(d, "last-seen.json")
            bridge.save_seen(path, {"p1": {"link": "LAN", "address": "192.168.1.20", "at": 5}})
            self.assertEqual(bridge.load_seen(path)["p1"]["at"], 5)
            self.assertEqual(bridge.load_seen(os.path.join(d, "missing.json")), {})


class Search(unittest.TestCase):
    """Look again: the daemon's discovery broadcast, and nothing else."""

    def test_search_asks_the_daemon_to_announce_itself(self):
        calls = []
        saved = (bridge.bus, bridge.call)
        bridge.bus = lambda: object()
        bridge.call = lambda conn, path, iface, method, *rest: calls.append((path, iface, method, rest))
        try:
            with contextlib.redirect_stdout(open(os.devnull, "w")):
                self.assertEqual(bridge.fix("search"), bridge.EXIT_OK)
        finally:
            bridge.bus, bridge.call = saved
        self.assertEqual(calls, [(bridge.ROOT, bridge.IFACE + ".daemon", "forceOnNetworkChange", ())])


class PhotoCacheAndSave(unittest.TestCase):
    """The last photo list shown at once, and a photo saved in Pictures."""

    def test_the_cached_list_keeps_photos_whose_thumbnail_is_here(self):
        with tempfile.TemporaryDirectory() as d:
            saved = bridge.state_dir
            bridge.state_dir = lambda: d
            try:
                cache = bridge.photos_cache("p1")
                thumb = os.path.join(cache, "t1.jpg")
                open(thumb, "w").close()
                bridge.save_received(os.path.join(cache, bridge.PHOTO_LIST),
                                     [{"name": "a.jpg", "thumb": thumb}, {"name": "b.jpg", "thumb": os.path.join(cache, "gone.jpg")}])
                got = bridge.cached_photos("p1")
                self.assertEqual([p["name"] for p in got["photos"]], ["a.jpg"])
                self.assertTrue(got["cached"])
                self.assertEqual(bridge.cached_photos("p2"), {"ok": False, "none": True})
            finally:
                bridge.state_dir = saved

    def test_a_saved_photo_keeps_its_date_and_is_saved_once(self):
        with tempfile.TemporaryDirectory() as d:
            saved = bridge.pictures_dir
            bridge.pictures_dir = lambda: os.path.join(d, "Pictures")
            try:
                src = os.path.join(d, "IMG_1.jpg")
                open(src, "w").write("x")
                os.utime(src, (1000, 1000))
                with contextlib.redirect_stdout(open(os.devnull, "w")):
                    self.assertEqual(bridge.save_file(src, "Pixel 8"), bridge.EXIT_OK)
                    self.assertEqual(bridge.save_file(src, "Pixel 8"), bridge.EXIT_OK)
                folder = os.path.join(d, "Pictures", "Pixel 8")
                self.assertEqual(os.listdir(folder), ["IMG_1.jpg"], "the same file is not saved twice")
                self.assertEqual(os.path.getmtime(os.path.join(folder, "IMG_1.jpg")), 1000, "with its own date")
                open(src, "w").write("another")
                with contextlib.redirect_stdout(open(os.devnull, "w")):
                    bridge.save_file(src, "Pixel 8")
                self.assertEqual(sorted(os.listdir(folder)), ["IMG_1 (2).jpg", "IMG_1.jpg"], "another file beside it")
            finally:
                bridge.pictures_dir = saved


def has_gdkpixbuf():
    try:
        import gi
        gi.require_version("GdkPixbuf", "2.0")
        from gi.repository import GdkPixbuf  # noqa: F401
        return True
    except (ImportError, ValueError):
        return False


def sandbox_works():
    if not (shutil.which("bwrap") and shutil.which("ffmpeg") and shutil.which("ffmpegthumbnailer")):
        return False
    return subprocess.run(["bwrap", "--unshare-all", "--ro-bind", "/usr", "/usr", "--symlink", "usr/lib", "/lib",
                           "--symlink", "usr/lib64", "/lib64", "--", "/usr/bin/true"], capture_output=True).returncode == 0


class SandboxedThumbs(unittest.TestCase):
    """A file from the device is decoded only in a sandbox; what the shell
    loads is a JPEG written here from its pixels."""

    def test_the_sandbox_shows_only_the_one_file(self):
        args = bridge.sandbox_args(["/usr/bin/ffmpegthumbnailer"], {"/run/user/1/dev/v.mp4": "/in/video"}, "/c/work")
        self.assertEqual(args[0], "bwrap")
        for flag in ("--unshare-all", "--die-with-parent", "--new-session", "--clearenv"):
            self.assertIn(flag, args)
        binds = [args[i + 1] for i, a in enumerate(args) if a in ("--bind", "--ro-bind", "--ro-bind-try")]
        self.assertEqual(sorted(binds), sorted(["/usr", "/etc/ld.so.cache", "/run/user/1/dev/v.mp4", "/c/work"]),
                         "nothing of the user's but the file and the work folder")
        i = args.index("/run/user/1/dev/v.mp4")
        self.assertEqual(args[i - 1], "--ro-bind", "the file is read-only")

    def test_a_video_without_the_sandbox_gets_no_thumbnail(self):
        with tempfile.TemporaryDirectory() as d:
            src = os.path.join(d, "v.mp4")
            open(src, "w").write("x")
            saved = bridge.shutil.which
            bridge.shutil.which = lambda name: None
            try:
                self.assertFalse(bridge.make_thumb(src, os.path.join(d, "t.jpg"), video=True))
            finally:
                bridge.shutil.which = saved
            self.assertEqual(sorted(os.listdir(d)), ["v.mp4"], "nothing left behind")

    def test_a_photo_too_big_gets_none(self):
        with tempfile.TemporaryDirectory() as d:
            src = os.path.join(d, "big.jpg")
            open(src, "w").write("x" * 100)
            saved = bridge.THUMB_MAX_BYTES
            bridge.THUMB_MAX_BYTES = 10
            try:
                self.assertFalse(bridge.make_thumb(src, os.path.join(d, "t.jpg")))
            finally:
                bridge.THUMB_MAX_BYTES = saved

    @unittest.skipUnless(has_gdkpixbuf(), "GdkPixbuf")
    def test_a_photo_becomes_a_new_square_jpeg(self):
        from gi.repository import GdkPixbuf
        with tempfile.TemporaryDirectory() as d:
            src, dst = os.path.join(d, "IMG.png"), os.path.join(d, "t.jpg")
            for alpha in (False, True):  # a PNG screenshot has alpha; JPEG has none
                pix = GdkPixbuf.Pixbuf.new(GdkPixbuf.Colorspace.RGB, alpha, 8, 600, 300)
                pix.fill(0x3366ccff)
                pix.savev(src, "png", [], [])
                self.assertTrue(bridge.make_thumb(src, dst), "alpha %s" % alpha)
                self.assertEqual(open(dst, "rb").read(2), b"\xff\xd8", "a JPEG of ours")
                out = GdkPixbuf.Pixbuf.new_from_file(dst)
                self.assertEqual((out.get_width(), out.get_height()), (256, 256))

    @unittest.skipUnless(has_gdkpixbuf(), "GdkPixbuf")
    def test_something_that_is_not_an_image_gets_none(self):
        with tempfile.TemporaryDirectory() as d:
            src = os.path.join(d, "IMG.jpg")
            open(src, "wb").write(b"\xff\xd8not really")
            self.assertFalse(bridge.make_thumb(src, os.path.join(d, "t.jpg")))
            self.assertFalse(os.path.exists(os.path.join(d, "t.jpg.part")))

    @unittest.skipUnless(has_gdkpixbuf() and sandbox_works(), "bwrap, ffmpeg, ffmpegthumbnailer")
    def test_a_video_frame_comes_out_of_the_sandbox(self):
        with tempfile.TemporaryDirectory() as d:
            src, dst = os.path.join(d, "VID.mp4"), os.path.join(d, "t.jpg")
            subprocess.run(["ffmpeg", "-v", "error", "-f", "lavfi", "-i", "testsrc=duration=2:size=320x240:rate=10",
                            "-pix_fmt", "yuv420p", src], check=True)
            self.assertTrue(bridge.make_thumb(src, dst, video=True))
            self.assertEqual(open(dst, "rb").read(2), b"\xff\xd8")
            self.assertEqual(sorted(os.listdir(d)), ["VID.mp4", "t.jpg"], "the work folder is gone")


class SafeImages(unittest.TestCase):
    """Every other image from the device (icons, art, previews, received
    pictures) is shown only as a copy decoded in the sandbox."""

    def png(self, path, w, h, alpha=False):
        from gi.repository import GdkPixbuf
        pix = GdkPixbuf.Pixbuf.new(GdkPixbuf.Colorspace.RGB, alpha, 8, w, h)
        pix.fill(0x3366cc80 if alpha else 0x3366ccff)
        pix.savev(path, "png", [], [])

    @unittest.skipUnless(has_gdkpixbuf(), "GdkPixbuf")
    def test_a_copy_fits_its_box_and_keeps_alpha(self):
        from gi.repository import GdkPixbuf
        with tempfile.TemporaryDirectory() as d:
            src, dst = os.path.join(d, "icon.png"), os.path.join(d, "out.png")
            self.png(src, 400, 200, alpha=True)
            self.assertTrue(bridge.fit_image(src, dst, 96))
            out = GdkPixbuf.Pixbuf.new_from_file(dst)
            self.assertEqual((out.get_width(), out.get_height(), out.get_has_alpha()), (96, 48, True))

    @unittest.skipUnless(has_gdkpixbuf(), "GdkPixbuf")
    def test_made_once_while_the_source_is_the_same(self):
        with tempfile.TemporaryDirectory() as d:
            src, folder = os.path.join(d, "art.png"), os.path.join(d, "safe")
            os.makedirs(folder)
            self.png(src, 300, 300)
            made = []
            saved = bridge.fit_image
            bridge.fit_image = lambda s_, dst, box: (made.append(dst), saved(s_, dst, box))[1]
            try:
                first = bridge.safe_image(src, 128, folder)
                self.assertEqual(bridge.safe_image(src, 128, folder), first)
            finally:
                bridge.fit_image = saved
            self.assertEqual(len(made), 1)
            self.assertTrue(first.startswith(folder) and first.endswith(".png"))

    def test_nothing_for_what_is_missing_too_big_or_not_an_image(self):
        with tempfile.TemporaryDirectory() as d:
            self.assertEqual(bridge.safe_image(os.path.join(d, "none.png"), 96, d), "")
            big = os.path.join(d, "big.png")
            open(big, "w").write("x" * 100)
            saved = bridge.SAFE_SOURCE_MAX
            bridge.SAFE_SOURCE_MAX = 10
            try:
                self.assertEqual(bridge.safe_image(big, 96, d), "")
            finally:
                bridge.SAFE_SOURCE_MAX = saved
            if has_gdkpixbuf():
                bad = os.path.join(d, "bad.png")
                open(bad, "wb").write(b"\x89PNG not really")
                self.assertEqual(bridge.safe_image(bad, 96, d), "")

    def test_the_cache_drops_the_least_recently_used(self):
        with tempfile.TemporaryDirectory() as d:
            for i, name in enumerate(["a.png", "b.png", "c.png"]):
                p = os.path.join(d, name)
                open(p, "w").write("x" * 10)
                os.utime(p, (1000 + i, 1000 + i))
            bridge.trim_files(d, 25)
            self.assertEqual(sorted(os.listdir(d)), ["b.png", "c.png"])

    @unittest.skipUnless(has_gdkpixbuf(), "GdkPixbuf")
    def test_a_picture_messages_preview_is_a_copy_not_the_bytes(self):
        import base64
        with tempfile.TemporaryDirectory() as d:
            src = os.path.join(d, "p.png")
            self.png(src, 640, 480)
            reader = bridge.Sms.__new__(bridge.Sms)
            reader.thumbs = d
            entry = reader.attachment((7, "image/jpeg", base64.b64encode(open(src, "rb").read()).decode(), "u1"))
            self.assertTrue(entry["thumb"].startswith(os.path.join(d, "preview_")))
            self.assertNotEqual(open(entry["thumb"], "rb").read(), open(src, "rb").read(), "written here, not as it came")
            self.assertFalse([n for n in os.listdir(d) if n.endswith(".raw")], "the phone's bytes are gone")
            junk = reader.attachment((8, "image/jpeg", base64.b64encode(b"not an image").decode(), "u2"))
            self.assertEqual(junk["thumb"], "", "no preview: the view shows the attachment's kind")


class FetchedAttachments(unittest.TestCase):
    """A picture message's picture opens from a copy made in the sandbox,
    never as the phone's bytes; anything else opens as itself."""

    def reader(self, d):
        r = bridge.Sms.__new__(bridge.Sms)
        r.thumbs, r.file_mimes = d, {}
        return r

    @unittest.skipUnless(has_gdkpixbuf(), "GdkPixbuf")
    def test_a_picture_opens_as_a_copy_made_in_the_sandbox(self):
        from gi.repository import GdkPixbuf
        with tempfile.TemporaryDirectory() as d:
            saved = bridge.state_dir
            bridge.state_dir = lambda: os.path.join(d, "state")
            try:
                src = os.path.join(d, "PART_1_image")  # the daemon saves without an extension
                pix = GdkPixbuf.Pixbuf.new(GdkPixbuf.Colorspace.RGB, True, 8, 300, 200)
                pix.fill(0x3366cc80)
                pix.savev(src, "png", [], [])
                r = self.reader(d)
                r.file_mimes["PART_1_image"] = "image/heic"
                ev = r.arrived(src, "PART_1_image")
                self.assertEqual(ev["ev"], "attachment")
                self.assertTrue(ev["path"].startswith(os.path.join(d, "state", "open")) and ev["path"].endswith(".jpg"))
                self.assertEqual(open(ev["path"], "rb").read(2), b"\xff\xd8", "a JPEG written here")
                out = GdkPixbuf.Pixbuf.new_from_file(ev["path"])
                self.assertEqual((out.get_width(), out.get_height()), (300, 200), "full size, never enlarged")
                self.assertEqual(r.arrived(src, "PART_1_image")["path"], ev["path"], "made once")
                open(src, "wb").write(b"\x89PNG not really")
                os.utime(src, (5000, 5000))
                bad = r.arrived(src, "PART_1_image")
                self.assertEqual(bad["ev"], "error", "not readable: not opened at all")
            finally:
                bridge.state_dir = saved

    def test_anything_else_opens_as_itself(self):
        with tempfile.TemporaryDirectory() as d:
            src = os.path.join(d, "PART_2_video")
            open(src, "w").write("x")
            r = self.reader(d)
            r.file_mimes["PART_2_video"] = "video/mp4"
            ev = r.arrived(src, "PART_2_video")
            self.assertEqual(ev["ev"], "attachment")
            self.assertTrue(ev["path"].endswith(".mp4"), "under a name with its type")


class OpenFromDevice(unittest.TestCase):
    """A file from the device opens from a local copy, kept while unchanged;
    the cache drops the oldest copies past its limit."""

    def test_copied_once_and_again_when_changed(self):
        with tempfile.TemporaryDirectory() as d:
            src = os.path.join(d, "VID_1.mp4")
            open(src, "w").write("abc")
            os.utime(src, (1000, 1000))
            cache = os.path.join(d, "cache")
            os.makedirs(cache)
            first = bridge.local_copy(src, cache)
            self.assertEqual(os.path.basename(first), "VID_1.mp4", "under its own name")
            self.assertEqual(open(first).read(), "abc")
            self.assertEqual(os.path.getmtime(first), 1000)
            os.utime(first, (1000, 1000))
            open(first, "w").write("xyz")  # same size: taken as the same file
            os.utime(first, (1000, 1000))
            self.assertEqual(open(bridge.local_copy(src, cache)).read(), "xyz", "not copied again")
            open(src, "w").write("abcd")
            os.utime(src, (2000, 2000))
            self.assertEqual(open(bridge.local_copy(src, cache)).read(), "abcd", "copied again once it changed")

    def test_the_cache_drops_the_oldest(self):
        with tempfile.TemporaryDirectory() as d:
            cache = os.path.join(d, "cache")
            os.makedirs(cache)
            for i, name in enumerate(["a.mp4", "b.mp4", "c.mp4"]):
                src = os.path.join(d, name)
                open(src, "w").write("x" * 10)
                bridge.local_copy(src, cache, limit=25)
                folder = os.path.dirname(bridge.local_copy(src, cache, limit=25))
                os.utime(folder, (1000 + i, 1000 + i))
            bridge.trim_cache(cache, 25)
            left = sorted(f for folder in os.listdir(cache) for f in os.listdir(os.path.join(cache, folder)))
            self.assertEqual(left, ["b.mp4", "c.mp4"])

    def test_opening_with_local_opens_the_copy(self):
        with tempfile.TemporaryDirectory() as d:
            src = os.path.join(d, "IMG_1.jpg")
            open(src, "w").write("x")
            saved = (bridge.state_dir, bridge.default_app)
            bridge.state_dir = lambda: os.path.join(d, "state")
            bridge.default_app = lambda path: object()
            ran = []
            try:
                self.assertEqual(bridge.open_file(src, launch=ran.append, local=True), bridge.EXIT_OK)
            finally:
                bridge.state_dir, bridge.default_app = saved
            self.assertEqual(ran[0][:4], ["uwsm-app", "--", "gio", "open"])
            self.assertTrue(ran[0][4].startswith(os.path.join(d, "state", "open")), "the copy, not the device's file")


class ReceivedFolderWatch(unittest.TestCase):
    """The folders of received files are watched: a rename is followed, a
    delete or move-away goes at once; a watch the system refuses changes
    nothing (the 30 s existence check still works)."""

    def test_a_rename_is_followed(self):
        entries = [{"path": "/d/a.pdf", "name": "a.pdf"}, {"path": "/d/b.txt", "name": "b.txt"}]
        self.assertTrue(bridge.rename_received(entries, "/d/a.pdf", "/d/report.pdf"))
        self.assertEqual(entries[0], {"path": "/d/report.pdf", "name": "report.pdf"})
        self.assertFalse(bridge.rename_received(entries, "/d/none", "/d/x"))
        self.assertFalse(bridge.rename_received(entries, "/d/b.txt", ""), "no new name: not a rename")

    def test_a_refused_watch_is_skipped_silently(self):
        def refuse(folder, callback):
            raise bridge.GLib.Error("Too many open files")
        watch = bridge.FolderWatch(lambda *a: None, make_monitor=refuse)
        with contextlib.redirect_stderr(open(os.devnull, "w")) as err:
            watch.sync({"/d"})
        self.assertEqual(watch.monitors, {})

    def test_watches_follow_the_folders_that_hold_listed_files(self):
        made, cancelled = [], []

        class Fake:
            def __init__(self, folder):
                self.folder = folder

            def cancel(self):
                cancelled.append(self.folder)

        def make(folder, callback):
            made.append(folder)
            return Fake(folder)

        watch = bridge.FolderWatch(lambda *a: None, make_monitor=make)
        watch.sync({"/a", "/b", ""})
        self.assertEqual(sorted(made), ["/a", "/b"], "one watch per folder; none for an empty path")
        watch.sync({"/b"})
        self.assertEqual(cancelled, ["/a"], "a folder no longer holding a listed file is let go")
        watch.sync({"/b"})
        self.assertEqual(sorted(made), ["/a", "/b"], "an existing watch is kept, not made again")

    def test_a_real_folder_reports_a_rename_and_a_delete(self):
        with tempfile.TemporaryDirectory() as d:
            src = os.path.join(d, "a.pdf")
            open(src, "w").close()
            events = []
            watch = bridge.FolderWatch(lambda kind, path, new: events.append((kind, os.path.basename(path), os.path.basename(new))))
            watch.sync({d})
            ctx = bridge.GLib.MainContext.default()

            def pump(until):
                deadline = bridge.GLib.get_monotonic_time() + 2000000
                while not until() and bridge.GLib.get_monotonic_time() < deadline:
                    ctx.iteration(False)

            os.rename(src, os.path.join(d, "report.pdf"))
            pump(lambda: any(e[0] == "renamed" for e in events))
            self.assertIn(("renamed", "a.pdf", "report.pdf"), events)
            os.remove(os.path.join(d, "report.pdf"))
            pump(lambda: any(e[0] == "gone" for e in events))
            self.assertIn(("gone", "report.pdf", ""), events)
            watch.sync(set())
            self.assertEqual(watch.monitors, {})


class OpenFile(unittest.TestCase):
    """A file opens in its app as the desktop sees it (GIO, following a
    type's parents), through uwsm-app; with no app, it is shown in Files."""

    def run_open(self, path, app):
        launched = []
        saved = bridge.default_app
        bridge.default_app = lambda p: app
        try:
            with contextlib.redirect_stdout(open(os.devnull, "w")), contextlib.redirect_stderr(open(os.devnull, "w")):
                code = bridge.open_file(path, launch=launched.append)
        finally:
            bridge.default_app = saved
        return code, launched

    def test_with_an_app_it_opens_through_uwsm(self):
        with tempfile.TemporaryDirectory() as d:
            f = os.path.join(d, "a b#1.json")
            open(f, "w").close()
            code, launched = self.run_open(f, object())
            self.assertEqual(code, bridge.EXIT_OK)
            self.assertEqual(launched, [["uwsm-app", "--", "gio", "open", f]])

    def test_without_an_app_it_is_shown_in_files(self):
        with tempfile.TemporaryDirectory() as d:
            f = os.path.join(d, "a b#1.xyz")
            open(f, "w").close()
            code, launched = self.run_open(f, None)
            self.assertEqual(code, bridge.EXIT_CANCELLED)
            self.assertEqual(launched[0][:4], ["uwsm-app", "--", "nautilus", "--select"])
            self.assertTrue(launched[0][4].endswith("/a%20b%231.xyz"), "each part encoded apart")

    def test_a_gone_file_opens_nothing(self):
        code, launched = self.run_open("/nowhere/at/all.pdf", object())
        self.assertEqual((code, launched), (bridge.EXIT_FAILED, []))

    def test_json_is_text_to_gio(self):
        self.assertTrue(bridge.Gio.content_type_is_a("application/json", "text/plain"),
                        "why GIO finds a text editor for JSON where xdg-open finds nothing")
