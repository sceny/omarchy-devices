"""What a device, a local process or a bystander can make the plugin keep or
send: scrcpy's log holds no input, device text is capped at the bridge, the
cache is private. All data is made up (`python3 -m unittest discover -s tests`).
"""

import importlib.machinery
import importlib.util
import os
import stat
import subprocess
import sys
import tempfile
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
loader = importlib.machinery.SourceFileLoader("kdeconnect_bridge", os.path.join(HERE, "..", "bin", "kdeconnect-bridge"))
spec = importlib.util.spec_from_loader("kdeconnect_bridge", loader)
bridge = importlib.util.module_from_spec(spec)
loader.exec_module(bridge)

FAKE_SCRCPY = """#!/bin/sh
echo "INFO: scrcpy 4.1"
echo "[server] VERBOSE: DisplayMonitor: 1080x2316 [rotation=0] -> 2316x1080 [rotation=1]"
echo 'VERBOSE: input: text "hunter2"'
echo 'VERBOSE: input: key down code=40 mod=0'
echo 'VERBOSE: input: clipboard 1 paste "my secret clipboard"' >&2
echo 'VERBOSE: input: clipboard 2 paste "first line
INFO: Texture: 9x9 and more words"'
echo 'VERBOSE: HID input: [1] 00 00 04'
echo "INFO: Texture: 2316x1080"
"""


class ScreenLog(unittest.TestCase):
    """F1: scrcpy at verbose level logs every key, text and clipboard it
    sends; none of that may reach a file."""

    def setUp(self):
        self.tmp = tempfile.mkdtemp()
        self.saved = dict(os.environ)
        os.environ["XDG_RUNTIME_DIR"] = os.path.join(self.tmp, "run")
        os.makedirs(os.environ["XDG_RUNTIME_DIR"], mode=0o700)
        os.environ["XDG_CACHE_HOME"] = os.path.join(self.tmp, "cache")
        os.makedirs(os.environ["XDG_CACHE_HOME"])
        bin_dir = os.path.join(self.tmp, "bin")
        os.makedirs(bin_dir)
        with open(os.path.join(bin_dir, "scrcpy"), "w") as f:
            f.write(FAKE_SCRCPY)
        os.chmod(os.path.join(bin_dir, "scrcpy"), 0o755)
        os.environ["PATH"] = bin_dir + os.pathsep + os.environ["PATH"]

    def tearDown(self):
        os.environ.clear()
        os.environ.update(self.saved)
        subprocess.run(["rm", "-rf", self.tmp])

    def run_screen(self, log):
        cmd = bridge.screen_command("S1", "Pixel 8 · Screen", log=log)
        subprocess.run(cmd[2:], check=True, timeout=20)   # without uwsm-app
        return open(log).read()

    def test_the_log_holds_only_the_watchers_lines(self):
        log = bridge.screen_log("Pixel 8 · Screen")
        text = self.run_screen(log)
        self.assertEqual(text.splitlines(), [
            "[server] VERBOSE: DisplayMonitor: 1080x2316 [rotation=0] -> 2316x1080 [rotation=1]",
            "INFO: Texture: 2316x1080",
        ])
        for private in ("hunter2", "secret", "input:", "HID", "first line", "9x9"):
            self.assertNotIn(private, text)

    def test_the_watcher_still_reads_what_is_kept(self):
        log = bridge.screen_log("Pixel 8 · Screen")
        lines = self.run_screen(log).splitlines()
        self.assertEqual(bridge.parse_display_change(lines[0]), ((1080, 2316, 0), (2316, 1080, 1)))
        self.assertEqual(bridge.parse_texture(lines[1]), (2316, 1080))

    def test_the_log_is_in_memory_and_private(self):
        log = bridge.screen_log("Pixel 8 · Screen")
        self.assertTrue(log.startswith(os.path.join(os.environ["XDG_RUNTIME_DIR"], "sceny.devices")), log)
        self.assertEqual(stat.S_IMODE(os.stat(os.path.dirname(log)).st_mode), 0o700)

    def test_no_runtime_folder_no_log_and_no_fallback_to_tmp(self):
        del os.environ["XDG_RUNTIME_DIR"]
        self.assertEqual(bridge.screen_log("Pixel 8 · Screen"), "")
        self.assertEqual(bridge.runtime_dir(), "")
        self.assertEqual(bridge.turn_still({}, "Pixel 8 · Screen", "old"), "")
        self.assertEqual(bridge.screen_command("S1", "x")[2], "scrcpy", "no log: plain scrcpy, not verbose")
        self.assertNotIn("--verbosity=verbose", bridge.screen_command("S1", "x"))

    def test_old_logs_in_the_cache_are_removed(self):
        os.makedirs(os.path.join(os.environ["XDG_CACHE_HOME"], "sceny.devices"))
        old = os.path.join(os.environ["XDG_CACHE_HOME"], "sceny.devices", "screen-0123456789ab.log")
        open(old, "w").write('input: text "hunter2"\n')
        bridge._state_dirs_closed.clear()
        bridge.state_dir()
        self.assertFalse(os.path.exists(old))


class CacheFolder(unittest.TestCase):
    """F4: the cache folder is the user's alone, whatever the home's mode."""

    def test_new_and_old_folders_are_0700(self):
        with tempfile.TemporaryDirectory() as tmp:
            saved = os.environ.get("XDG_CACHE_HOME")
            os.environ["XDG_CACHE_HOME"] = tmp
            try:
                old = os.path.join(tmp, "sceny.devices")
                os.mkdir(old, 0o755)
                os.chmod(old, 0o755)
                bridge._state_dirs_closed.clear()
                self.assertEqual(bridge.state_dir(), old)
                self.assertEqual(stat.S_IMODE(os.stat(old).st_mode), 0o700)
            finally:
                if saved is None:
                    del os.environ["XDG_CACHE_HOME"]
                else:
                    os.environ["XDG_CACHE_HOME"] = saved

    def test_a_runtime_folder_of_someone_else_is_not_used(self):
        with tempfile.TemporaryDirectory() as tmp:
            saved = os.environ.get("XDG_RUNTIME_DIR")
            os.environ["XDG_RUNTIME_DIR"] = tmp
            real_stat = os.stat
            try:
                def other(path, *a, **kw):
                    st = real_stat(path, *a, **kw)
                    return os.stat_result((st.st_mode, st.st_ino, st.st_dev, st.st_nlink, st.st_uid + 1,
                                           st.st_gid, st.st_size, 0, 0, 0))
                os.stat = other
                self.assertEqual(bridge.runtime_dir(), "")
            finally:
                os.stat = real_stat
                if saved is None:
                    del os.environ["XDG_RUNTIME_DIR"]
                else:
                    os.environ["XDG_RUNTIME_DIR"] = saved


class DeviceTextCaps(unittest.TestCase):
    """F2: text from a device is capped once, at the bridge."""

    def test_cap_text(self):
        self.assertEqual(bridge.cap_text("abc", 3), "abc")
        self.assertEqual(bridge.cap_text("abcd", 3), "ab…")
        self.assertEqual(bridge.cap_text(None, 3), "")

    def test_an_oversized_notification_is_cut(self):
        big = "x" * (5 << 20)
        props = {"appName": big, "title": big, "text": big, "ticker": big, "internalId": big, "replyId": big,
                 "actions": [big] * 40, "isConversation": False, "dismissable": True}
        saved = bridge.call, bridge.props
        ids = ["n%d" % i for i in range(300)]
        bridge.call = lambda *a, **k: (ids,)
        bridge.props = lambda conn, path, iface: dict(props, title=path.rsplit("/", 1)[-1] + big)
        try:
            out = bridge.read_notifications(None, "/d")
        finally:
            bridge.call, bridge.props = saved
        self.assertEqual(len(out), bridge.CAP_NOTIFICATIONS)
        self.assertEqual(out[0]["id"], "n299", "the newest are kept")
        n = out[0]
        for field in ("app", "title", "ticker", "replyId"):
            self.assertLessEqual(len(n[field]), bridge.CAP_SHORT, field)
        self.assertLessEqual(len(n["key"]), bridge.CAP_KEY)
        self.assertLessEqual(len(n["text"]), bridge.CAP_TEXT)
        self.assertEqual(len(n["actions"]), bridge.CAP_ACTIONS)
        self.assertTrue(all(len(a) <= bridge.CAP_SHORT for a in n["actions"]))
        self.assertLess(len(str(out)), 100 * 40 * 6000)

    def test_an_oversized_conversation_is_cut(self):
        big = "y" * (1 << 20)
        markup = "<br/>".join("<b>%s</b>\n%s" % ("s" * 5000, big) for _ in range(500))
        saved = bridge.call, bridge.props
        bridge.call = lambda *a, **k: (["c1"],)
        bridge.props = lambda *a: {"text": markup, "isConversation": True}
        try:
            n = bridge.read_notifications(None, "/d")[0]
        finally:
            bridge.call, bridge.props = saved
        self.assertEqual(len(n["conversation"]), bridge.CAP_CONVERSATION)
        self.assertTrue(all(len(m["sender"]) <= bridge.CAP_SHORT and len(m["text"]) <= bridge.CAP_TEXT for m in n["conversation"]))
        self.assertLessEqual(len(n["text"]), bridge.CAP_TEXT)

    def test_a_text_message_is_cut(self):
        sms = bridge.Sms.__new__(bridge.Sms)
        big = "z" * (5 << 20)
        m = sms.message(("conversationCreated", big, [(big,)] * 500, 1, 1, 1, 7, 9, 0, []))
        self.assertLessEqual(len(m["body"]), bridge.CAP_SMS_BODY)
        self.assertEqual(len(m["addresses"]), bridge.CAP_ADDRESSES)
        self.assertTrue(all(len(a) <= bridge.CAP_SHORT for a in m["addresses"]))
        self.assertEqual(sms.message(("e", "hi", [("+1 555 0100",)], 1, 1, 1, 7, 9, 0, []))["body"], "hi")

    def test_app_names_and_the_number_of_apps_are_cut(self):
        text = "\n".join(" - %s com.example.a%d" % ("n" * 5000, i) for i in range(bridge.CAP_APPS + 50))
        apps = bridge.parse_scrcpy_apps(text)
        self.assertEqual(len(apps), bridge.CAP_APPS)
        self.assertTrue(all(len(a["name"]) <= bridge.CAP_SHORT for a in apps))

    def test_a_contact_file_is_read_to_a_limit(self):
        with tempfile.TemporaryDirectory() as home:
            saved = os.environ.get("HOME")
            os.environ["HOME"] = home
            folder = os.path.join(home, ".local/share/kpeoplevcard/kdeconnect-dev1")
            os.makedirs(folder)
            try:
                with open(os.path.join(folder, "a.vcf"), "w") as f:
                    f.write("BEGIN:VCARD\nFN:%s\nTEL:+1 555 0100\nEND:VCARD\n" % ("N" * (3 << 20)))
                names, entries = bridge.read_contacts("dev1")
                self.assertEqual(entries, [], "the name ran past the limit: the card is not read")
                with open(os.path.join(folder, "a.vcf"), "w") as f:
                    f.write("BEGIN:VCARD\nFN:%s\nTEL:+1 555 0100\nEND:VCARD\n" % ("N" * 5000))
                names, entries = bridge.read_contacts("dev1")
                self.assertEqual(len(entries[0]["name"]), bridge.CAP_SHORT)
            finally:
                if saved is None:
                    del os.environ["HOME"]
                else:
                    os.environ["HOME"] = saved


    def test_many_numbers_and_many_contacts_are_cut(self):
        with tempfile.TemporaryDirectory() as home:
            saved = os.environ.get("HOME")
            os.environ["HOME"] = home
            folder = os.path.join(home, ".local/share/kpeoplevcard/kdeconnect-dev1")
            os.makedirs(folder)
            try:
                with open(os.path.join(folder, "a.vcf"), "w") as f:
                    f.write("BEGIN:VCARD\nFN:%s\n%sEND:VCARD\n" % ("N" * 300, "TEL:5\n" * 100000))
                names, entries = bridge.read_contacts("dev1")
                self.assertLessEqual(len(entries), bridge.CAP_TELS)
                for i in range(bridge.CAP_CONTACTS // bridge.CAP_TELS + 50):
                    with open(os.path.join(folder, "c%d.vcf" % i), "w") as f:
                        f.write("BEGIN:VCARD\nFN:Name %d\n%sEND:VCARD\n" % (
                            i, "".join("TEL:+1 555 %04d %02d\n" % (i, j) for j in range(bridge.CAP_TELS))))
                names, entries = bridge.read_contacts("dev1")
                self.assertEqual(len(entries), bridge.CAP_CONTACTS)
                self.assertLessEqual(len(names), bridge.CAP_CONTACTS)
            finally:
                if saved is None:
                    del os.environ["HOME"]
                else:
                    os.environ["HOME"] = saved

    def test_too_many_threads_are_cut_to_the_newest(self):
        sms = bridge.Sms.__new__(bridge.Sms)
        sms.cache, sms.latest = {}, {}
        n = bridge.CAP_THREADS + 100
        sms.active = lambda: [{"thread": t, "uid": t, "date": t} for t in range(n)]
        sms.summary = lambda m: {"thread": m["thread"], "date": m["date"]}
        sms.contacts, sms.contact_list = {}, []
        sent = []
        sms.out = sent.append
        sms.emit_threads()
        threads = sent[0]["threads"]
        self.assertEqual(len(threads), bridge.CAP_THREADS)
        self.assertEqual(threads[0]["date"], n - 1, "the newest are kept")


class ArtOnlyFromTheArtCache(unittest.TestCase):
    """F3: a track's art is decoded only from a real file in KDE Connect's art cache."""

    def test_paths(self):
        with tempfile.TemporaryDirectory() as tmp:
            saved = os.environ.get("XDG_CACHE_HOME"), bridge.safe_image
            os.environ["XDG_CACHE_HOME"] = tmp
            seen = []
            bridge.safe_image = lambda src, box, *a, **k: seen.append(src) or "/safe/x.png"
            try:
                art = os.path.join(tmp, "kdeconnect.daemon", "kdeconnect", "albumart")
                os.makedirs(art)
                inside = os.path.join(art, "cover")
                open(inside, "w").write("x")
                outside = os.path.join(tmp, "private.jpg")
                open(outside, "w").write("x")
                os.symlink(outside, os.path.join(art, "link"))
                self.assertEqual(bridge.safe_art(inside, 512), "/safe/x.png")
                self.assertEqual(seen, [os.path.realpath(inside)])
                for refused in (outside, os.path.join(art, "link"), os.path.join(art, "..", "private.jpg"),
                                art, "", "/etc/passwd"):
                    self.assertEqual(bridge.safe_art(refused, 512), "", refused)
                self.assertEqual(len(seen), 1, "nothing else reached the decoder")
            finally:
                bridge.safe_image = saved[1]
                if saved[0] is None:
                    del os.environ["XDG_CACHE_HOME"]
                else:
                    os.environ["XDG_CACHE_HOME"] = saved[0]


if __name__ == "__main__":
    unittest.main()
