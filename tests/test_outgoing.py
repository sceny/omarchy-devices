"""A picture sent from the composer: what the bridge makes of the file the
user chose, which files a send may hand the daemon, and the D-Bus arguments
of the send (with the bus replaced: nothing reaches a device, no message is
sent). All data is made up."""

import importlib.machinery
import importlib.util
import os
import tempfile
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
BRIDGE = os.path.join(HERE, "..", "bin", "kdeconnect-bridge")
loader = importlib.machinery.SourceFileLoader("kdeconnect_bridge_outgoing", BRIDGE)
spec = importlib.util.spec_from_loader("kdeconnect_bridge_outgoing", loader)
bridge = importlib.util.module_from_spec(spec)
loader.exec_module(bridge)


def make_picture(path, width=3000, height=2000, fmt="png"):
    import gi
    gi.require_version("GdkPixbuf", "2.0")
    from gi.repository import GdkPixbuf
    pix = GdkPixbuf.Pixbuf.new(GdkPixbuf.Colorspace.RGB, False, 8, width, height)
    pix.fill(0x336699ff)
    pix.savev(path, fmt, [], [])


def can_decode():
    try:
        with tempfile.TemporaryDirectory() as d:
            make_picture(os.path.join(d, "a.png"), 8, 8)
            return bridge.fit_image(os.path.join(d, "a.png"), os.path.join(d, "b.jpg"), 8, "jpeg")
    except Exception:
        return False


DECODES = can_decode()


@unittest.skipUnless(DECODES, "no GdkPixbuf decoder here")
class Prepare(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.folder = os.path.join(self.tmp.name, "outgoing")
        os.makedirs(self.folder)

    def test_a_picture_becomes_a_jpeg_that_fits_with_a_preview(self):
        src = os.path.join(self.tmp.name, "holiday.png")
        make_picture(src)
        out = bridge.prepare_outgoing(src, self.folder)
        self.assertTrue(out["ok"], out)
        self.assertTrue(out["path"].endswith(".jpg"))
        self.assertEqual(os.path.dirname(out["path"]), self.folder)
        self.assertLessEqual(os.path.getsize(out["path"]), bridge.OUTGOING_MAX_BYTES)
        self.assertEqual(out["name"], "holiday.png")
        self.assertTrue(os.path.isfile(out["preview"]))
        with open(out["path"], "rb") as f:
            self.assertEqual(f.read(3), b"\xff\xd8\xff", "a JPEG of ours, not the file as it came")
        self.assertTrue(os.path.isfile(src), "the user's file is left alone")

    def test_a_file_that_is_not_a_picture_is_refused(self):
        src = os.path.join(self.tmp.name, "notes.txt")
        with open(src, "w") as f:
            f.write("plain text")
        self.assertEqual(bridge.prepare_outgoing(src, self.folder), {"ok": False, "error": "That is not a picture"})
        self.assertEqual(os.listdir(self.folder), [])

    def test_a_picture_that_does_not_decode_is_refused_and_leaves_nothing(self):
        src = os.path.join(self.tmp.name, "broken.png")
        with open(src, "wb") as f:
            f.write(bridge.PICTURE_MAGIC[0] + b"not really")
        out = bridge.prepare_outgoing(src, self.folder)
        self.assertFalse(out["ok"])
        self.assertEqual(os.listdir(self.folder), [])

    def test_a_missing_file_is_refused(self):
        self.assertFalse(bridge.prepare_outgoing(os.path.join(self.tmp.name, "gone.png"), self.folder)["ok"])

    def test_copies_older_than_a_day_go_on_the_next_picture(self):
        old = os.path.join(self.folder, "old.jpg")
        fresh = os.path.join(self.folder, "fresh.jpg")
        for p in (old, fresh):
            open(p, "w").close()
        past = os.path.getmtime(old) - bridge.OUTGOING_KEEP_SEC - 60
        os.utime(old, (past, past))
        src = os.path.join(self.tmp.name, "a.png")
        make_picture(src, 64, 64)
        self.assertTrue(bridge.prepare_outgoing(src, self.folder)["ok"])
        self.assertFalse(os.path.exists(old))
        self.assertTrue(os.path.exists(fresh))


class Chosen(unittest.TestCase):
    def test_cancelling_the_chooser_attaches_nothing(self):
        self.assertEqual(bridge.outgoing_picture("pick", pick=lambda title: ([], "")), {"ok": False, "cancelled": True})

    def test_a_chooser_that_failed_says_so(self):
        self.assertEqual(bridge.outgoing_picture("pick", pick=lambda title: (None, "no chooser")),
                         {"ok": False, "error": "no chooser"})

    def test_the_chooser_is_asked_for_pictures_only(self):
        ran = []

        class Done:
            returncode, stdout, stderr = 1, "", ""

        saved = bridge.subprocess.run
        bridge.subprocess.run = lambda argv, **kw: ran.append(argv) or Done()
        try:
            bridge.pick_pictures("Attach a picture")
        finally:
            bridge.subprocess.run = saved
        self.assertEqual(ran[0][:1], ["omarchy-file-select"])
        self.assertNotIn("--multiple", ran[0])
        self.assertIn("--extensions", ran[0])

    def test_a_pasted_file_outside_the_runtime_folder_is_refused_and_kept(self):
        with tempfile.TemporaryDirectory() as run, tempfile.TemporaryDirectory() as other:
            saved = os.environ.get("XDG_RUNTIME_DIR")
            os.environ["XDG_RUNTIME_DIR"] = run
            try:
                src = os.path.join(other, "secret.png")
                open(src, "w").close()
                out = bridge.outgoing_picture("pasted", src)
                self.assertFalse(out["ok"])
                self.assertTrue(os.path.exists(src), "a file that is not ours is never removed")
            finally:
                if saved is None:
                    os.environ.pop("XDG_RUNTIME_DIR")
                else:
                    os.environ["XDG_RUNTIME_DIR"] = saved

    @unittest.skipUnless(DECODES, "no GdkPixbuf decoder here")
    def test_a_pasted_file_is_removed_once_prepared(self):
        with tempfile.TemporaryDirectory() as run, tempfile.TemporaryDirectory() as folder:
            saved = os.environ.get("XDG_RUNTIME_DIR")
            os.environ["XDG_RUNTIME_DIR"] = run
            try:
                os.makedirs(os.path.join(run, "sceny.devices"))
                src = os.path.join(run, "sceny.devices", "paste-1")
                make_picture(src, 64, 64)
                out = bridge.outgoing_picture("pasted", src, folder=folder)
                self.assertTrue(out["ok"], out)
                self.assertFalse(os.path.exists(src))
            finally:
                if saved is None:
                    os.environ.pop("XDG_RUNTIME_DIR")
                else:
                    os.environ["XDG_RUNTIME_DIR"] = saved


class Gate(unittest.TestCase):
    """The daemon reads whatever path it is given: a send hands it only what
    this module prepared."""

    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.folder = os.path.join(self.tmp.name, "outgoing")
        os.makedirs(self.folder)

    def test_a_prepared_file_passes(self):
        path = os.path.join(self.folder, "ab.jpg")
        open(path, "w").close()
        self.assertEqual(bridge.outgoing_files([path], self.folder), [os.path.realpath(path)])

    def test_any_other_file_is_refused(self):
        other = os.path.join(self.tmp.name, "other.jpg")
        open(other, "w").close()
        for path in (other, os.path.join(self.folder, "gone.jpg"), self.folder + "/../other.jpg", "/etc/passwd"):
            with self.assertRaises(ValueError):
                bridge.outgoing_files([path], self.folder)

    def test_a_link_out_of_the_folder_is_refused(self):
        target = os.path.join(self.tmp.name, "private.jpg")
        open(target, "w").close()
        link = os.path.join(self.folder, "link.jpg")
        os.symlink(target, link)
        with self.assertRaises(ValueError):
            bridge.outgoing_files([link], self.folder)


class SendCalls(unittest.TestCase):
    """What the daemon is called with (the bus replaced)."""

    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.folder = os.path.join(self.tmp.name, "outgoing")
        os.makedirs(self.folder)
        self.saved_dir = bridge.outgoing_dir
        bridge.outgoing_dir = lambda: self.folder
        self.addCleanup(setattr, bridge, "outgoing_dir", self.saved_dir)
        self.picture = os.path.join(self.folder, "ab.jpg")
        open(self.picture, "w").close()
        sms = bridge.Sms.__new__(bridge.Sms)
        sms.calls, sms.events = [], []
        sms.call = lambda method, args=None, sig=None, timeout=10000: sms.calls.append((method, args, sig))
        sms.out = sms.events.append
        self.sms = sms

    def test_a_reply_with_a_picture_passes_its_path_as_a_string_variant(self):
        self.sms.command({"cmd": "reply", "thread": 7, "text": "", "attachments": [self.picture]})
        (method, args, sig), = self.sms.calls
        self.assertEqual((method, sig), ("replyToConversation", "(xsav)"))
        tid, text, files = args
        self.assertEqual((tid, text), (7, ""))
        self.assertEqual([f.get_type_string() for f in files], ["s"])
        self.assertEqual([f.get_string() for f in files], [os.path.realpath(self.picture)])
        self.assertEqual(self.sms.events, [{"ev": "sent", "thread": 7}])
        bridge.GLib.Variant(sig, args)   # the arguments build the signature the daemon declares

    def test_a_new_conversation_with_a_picture(self):
        self.sms.command({"cmd": "send", "addresses": ["5550100"], "text": "hi", "attachments": [self.picture]})
        (method, args, sig), = self.sms.calls
        self.assertEqual((method, sig), ("sendWithoutConversation", "(avsav)"))
        addresses, text, files = args
        self.assertEqual(text, "hi")
        self.assertEqual([f.get_string() for f in files], [os.path.realpath(self.picture)])
        bridge.GLib.Variant(sig, args)

    def test_text_alone_passes_no_files(self):
        self.sms.command({"cmd": "reply", "thread": 7, "text": "hi"})
        self.assertEqual(self.sms.calls[0][1], (7, "hi", []))

    def test_nothing_to_send_calls_nothing(self):
        self.sms.command({"cmd": "reply", "thread": 7, "text": "  "})
        self.assertEqual(self.sms.calls, [])

    def test_a_file_that_is_not_ours_is_never_sent(self):
        self.sms.command({"cmd": "reply", "thread": 7, "text": "x", "attachments": ["/etc/passwd"]})
        self.assertEqual(self.sms.calls, [])
        self.assertEqual(self.sms.events[0]["ev"], "error")


if __name__ == "__main__":
    unittest.main()
