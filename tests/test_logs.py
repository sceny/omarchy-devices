"""Private text stays out of logs (docs/internals/releasing.md, the review
list): what a person or a device wrote (a message, a contact's name, a number,
the clipboard) never reaches the shell's journal or the bridge's stderr.

- QML: every argument of a `console.*` call (and `print`) in the shipped files
  is built only from literals, numbers, a `.length`, an error caught by the
  enclosing `catch`, or a term on LOGGED_TERMS with its reason. Fails naming
  file:line.
- Bridge: `sms`, `contacts`, `call` and the text verbs run on input that holds
  a marker in every text field, and the marker is on neither Python's stderr
  nor file descriptor 2. All data is made up."""

import contextlib
import glob
import importlib.machinery
import importlib.util
import io
import os
import re
import sys
import tempfile
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.join(HERE, "..")
sys.path.insert(0, HERE)

from test_qml import code_only  # noqa: E402

loader = importlib.machinery.SourceFileLoader("kdeconnect_bridge_logs", os.path.join(ROOT, "bin", "kdeconnect-bridge"))
spec = importlib.util.spec_from_loader("kdeconnect_bridge_logs", loader)
bridge = importlib.util.module_from_spec(spec)
loader.exec_module(bridge)

# (file, term) -> why it is not private text
LOGGED_TERMS = {
    ("SmsService.qml", "ev.ev"): "the bridge's own name for an event (threads, message, sent...), never its content",
    ("Service.qml", "ev.picture_ms"): "milliseconds the bridge measured between a turn and its picture",
    ("Service.qml", "ev.shown_ms"): "milliseconds the bridge measured between a turn and its reveal",
}

LOG_CALL = re.compile(r"(?<![\w.])(?:console\s*\.\s*(\w+)|print)\s*\(")
LOG_REFERENCE = re.compile(r"(?<![\w.])console\b(?!\s*\.\s*\w+\s*\()")
LITERAL = re.compile(r"\"[^\"\\]*\"|'[^'\\]*'")
NUMBER = re.compile(r"\d+(?:\.\d+)?")
LENGTH = re.compile(r"(?:String\(\s*[\w.]+\s*\)|[\w.]+)\.length")
CATCH = re.compile(r"\bcatch\s*\(\s*(\w+)\s*\)\s*\{")


def split_top(raw, clean, lo, hi, sep):
    """[(start, end)] of the pieces of raw[lo:hi] between top-level `sep`."""
    depth, start, parts = 0, lo, []
    for i in range(lo, hi):
        c = clean[i]
        if c in "([{":
            depth += 1
        elif c in ")]}":
            depth -= 1
        elif c == sep and depth == 0:
            parts.append((start, i))
            start = i + 1
    parts.append((start, hi))
    return parts


def caught_names(clean, at):
    """The names of the errors caught by the `catch` blocks that hold `at`."""
    names = set()
    for m in CATCH.finditer(clean):
        depth, i = 1, m.end()
        while i < len(clean) and depth:
            depth += {"{": 1, "}": -1}.get(clean[i], 0)
            i += 1
        if m.end() <= at < i:
            names.add(m.group(1))
    return names


def read(path):
    with open(path) as handle:
        return handle.read()


def private_text_in_logs(path, allowed=LOGGED_TERMS):
    """file:line for every log call that could carry text a person or a device
    wrote, and every use of `console` that is not a call this reads."""
    raw = read(path)
    clean = code_only(raw)
    name = os.path.basename(path)
    line = lambda i: raw.count("\n", 0, i) + 1
    found = []
    for m in LOG_REFERENCE.finditer(clean):
        found.append("%s:%d: console is used other than as a call" % (name, line(m.start())))
    for m in LOG_CALL.finditer(clean):
        open_at = m.end() - 1
        depth, close = 0, None
        for i in range(open_at, len(clean)):
            depth += {"(": 1, "[": 1, "{": 1, ")": -1, "]": -1, "}": -1}.get(clean[i], 0)
            if depth == 0:
                close = i
                break
        if close is None:
            found.append("%s:%d: a log call this cannot read" % (name, line(m.start())))
            continue
        errors = caught_names(clean, m.start())
        for a_lo, a_hi in split_top(raw, clean, open_at + 1, close, ","):
            for t_lo, t_hi in split_top(raw, clean, a_lo, a_hi, "+"):
                term = raw[t_lo:t_hi].strip()
                if not term:
                    continue
                ok = (LITERAL.fullmatch(term) or NUMBER.fullmatch(term) or LENGTH.fullmatch(term)
                      or term in errors or (name, term) in allowed)
                if not ok:
                    found.append("%s:%d: %s logs %s, which could be private text: log a length, a literal or a caught error"
                                 % (name, line(t_lo), m.group(0).rstrip("( "), term))
    return found


def shipped_qml():
    return sorted(glob.glob(os.path.join(ROOT, "*.qml")))


class QmlLogsHoldNoPrivateText(unittest.TestCase):
    def test_the_shipped_files(self):
        found = [p for f in shipped_qml() for p in private_text_in_logs(f)]
        self.assertEqual(found, [], "\n".join(found))

    def test_it_reads_the_logs_there_are(self):
        calls = sum(len(LOG_CALL.findall(code_only(read(f)))) for f in shipped_qml())
        self.assertGreaterEqual(calls, 5)

    def test_the_reviewed_terms_are_still_logged(self):
        used = set()
        for f in shipped_qml():
            text = read(f)
            used |= {key for key in LOGGED_TERMS if key[0] == os.path.basename(f) and key[1] in text}
        self.assertEqual(used, set(LOGGED_TERMS))

    def planted(self, source):
        with tempfile.NamedTemporaryFile("w", suffix=".qml", delete=False) as f:
            f.write(source)
        try:
            return private_text_in_logs(f.name)
        finally:
            os.remove(f.name)

    def test_what_is_allowed(self):
        for source in (
            'console.log("started")\n',
            'console.warn("sms: " + String(line).length + " characters")\n',
            'console.info("took " + 12 + " ms")\n',
            'try { f() } catch (e) { console.warn("failed: " + e) }\n',
            'try { f() } catch (err) { console.error("failed", err) }\n',
            'x = "console.log(text)" // console.log(body)\n',
        ):
            self.assertEqual(self.planted(source), [], source)

    def test_message_text_in_a_log_fails_naming_the_line(self):
        for source in (
            'console.log(text)\n',
            'console.log("sent " + text)\n',
            'console.warn("sms: " + line)\n',
            'console.info(message.body)\n',
            'console.debug(JSON.stringify(ev))\n',
            'console.error("failed: " + contact.name)\n',
            'console.log(`got ${text}`)\n',
            'print(number)\n',
            'try { f() } catch (e) { console.warn(text) }\n',
            'console.log(e)\n',
            'try { f() } catch (e) { x = 1 }\nconsole.log(e)\n',
            'console.trace(body.length ? body : "")\n',
        ):
            found = self.planted("Item {\n" + source + "}\n")
            self.assertTrue(found and found[0].split(":")[1].isdigit(), (source, found))

    def test_console_kept_in_a_variable_fails(self):
        for source in ("var log = console.log\nlog(text)\n", "var c = console\nc.log(text)\n"):
            self.assertTrue(self.planted(source), source)


# ---- The bridge -----------------------------------------------------------

MARK = "ZXQMARK-7731"


@contextlib.contextmanager
def stderr_of(stdin=""):
    """What reaches Python's stderr and file descriptor 2 inside the block, and
    what reaches stdout: {"err": ..., "out": ...} filled in on exit."""
    got = {"err": "", "out": ""}
    saved_in = sys.stdin
    sys.stdin = io.StringIO(stdin)
    err, out = io.StringIO(), io.StringIO()
    with tempfile.TemporaryFile("w+") as fd_two:
        saved_fd = os.dup(2)
        os.dup2(fd_two.fileno(), 2)
        try:
            with contextlib.redirect_stderr(err), contextlib.redirect_stdout(out):
                yield got
        finally:
            sys.stderr.flush()
            os.dup2(saved_fd, 2)
            os.close(saved_fd)
            sys.stdin = saved_in
            fd_two.seek(0)
            got["err"] = err.getvalue() + fd_two.read()
            got["out"] = out.getvalue()


class StderrIsHonestAboutIt(unittest.TestCase):
    def test_the_capture_sees_both_ways_of_writing(self):
        with stderr_of() as got:
            print("from python", file=sys.stderr)
            os.write(2, b"from the descriptor\n")
        self.assertIn("from python", got["err"])
        self.assertIn("from the descriptor", got["err"])


class NoPrivateTextOnStderr(unittest.TestCase):
    def silent(self, got, expect_on_stdout=None):
        self.assertNotIn(MARK, got["err"], "the marker reached stderr:\n" + got["err"])
        if expect_on_stdout:
            self.assertIn(MARK, got["out"], "the verb did not read the marker, so the test proves nothing")

    # -- contacts --
    def test_contacts_over_cards_that_hold_the_marker_in_every_field(self):
        card = ("BEGIN:VCARD\r\nVERSION:3.0\r\nN:%(m)sLast;%(m)sFirst;;;\r\nFN:%(m)s Name\r\nNICKNAME:%(m)s\r\n"
                "ORG:%(m)s;%(m)s\r\nTITLE:%(m)s\r\nTEL;TYPE=CELL:%(m)s+15145550123\r\nEMAIL;TYPE=HOME:%(m)s@example.invalid\r\n"
                "ADR;TYPE=HOME:;;%(m)s;%(m)s;%(m)s;%(m)s;%(m)s\r\nURL:https://example.invalid/%(m)s\r\nBDAY:%(m)s\r\n"
                "NOTE:%(m)s\\n%(m)s\r\nEND:VCARD\r\n") % {"m": MARK}
        broken = ["BEGIN:VCARD\r\nFN;ENCODING=QUOTED-PRINTABLE;CHARSET=%s:=C3=%s\r\nEND:VCARD\r\n" % (MARK, MARK),
                  "BEGIN:VCARD\r\nFN:%s\r\n" % MARK, "%s\r\n" % MARK,
                  "BEGIN:VCARD\r\nPHOTO;ENCODING=b:%s\r\nFN:%s\r\nEND:VCARD\r\n" % (MARK, MARK)]
        with tempfile.TemporaryDirectory() as folder:
            for i, text in enumerate([card] + broken):
                with open(os.path.join(folder, "%d.vcf" % i), "w") as f:
                    f.write(text)
            saved = bridge.vcard_folder, bridge.omarchy_contacts_app
            bridge.vcard_folder = lambda device_id: folder
            bridge.omarchy_contacts_app = lambda: None
            try:
                with stderr_of() as got:
                    self.assertEqual(bridge.main(["contacts", "d1"]), bridge.EXIT_OK)
            finally:
                bridge.vcard_folder, bridge.omarchy_contacts_app = saved
        self.silent(got, expect_on_stdout=True)

    def test_a_contact_search_and_a_detail_come_from_stdin(self):
        saved = (bridge.launch_detached, bridge.omarchy_contacts_app, bridge.omarchy_maps_app, bridge.hypr_json)
        bridge.launch_detached = lambda argv: None
        bridge.hypr_json = lambda what: []
        bridge.omarchy_contacts_app = lambda: {"name": "Contacts", "url": "https://contacts.invalid/", "find": "https://contacts.invalid/search/{}"}
        bridge.omarchy_maps_app = lambda: None
        try:
            for argv in (["contacts-app", "--find"], ["contact-open", "mail"], ["contact-open", "web"], ["contact-open", "map"], ["contact-open", MARK]):
                with stderr_of(MARK) as got:
                    bridge.main(argv)
                self.silent(got)
            with stderr_of() as got:
                bridge.main(["contact-open", "mail", MARK])
            self.silent(got)
        finally:
            bridge.launch_detached, bridge.omarchy_contacts_app, bridge.omarchy_maps_app, bridge.hypr_json = saved

    # -- sms --
    def sms(self):
        sms = bridge.Sms.__new__(bridge.Sms)
        sms.device_id, sms.path = "d1", "/dev"
        sms.cache, sms.latest, sms.pending, sms.loaded, sms.settle = {}, {}, {}, {}, {}
        sms.contacts, sms.contact_list = {bridge.digits_key("+15145550123"): MARK + " Contact"}, []
        sms.file_mimes, sms.requested = {}, set()
        sms.thumbs = tempfile.mkdtemp()
        sms.sent = []
        sms.calls = []
        sms.fail = False

        def call(method, args=None, sig=None, timeout=10000):
            if sms.fail:
                raise bridge.GLib.Error("the daemon said no")
            if sig:
                bridge.GLib.Variant(sig, args)
            sms.calls.append(method)
            return bridge.GLib.Variant("(av)", ([],))
        sms.call = call
        sms.out = lambda obj: sys.stdout.write(bridge.json.dumps(obj, ensure_ascii=False) + "\n")
        sms.loop = type("Loop", (), {"quit": lambda self: None})()
        return sms

    def test_sms_commands_that_carry_the_marker_in_every_field(self):
        commands = [
            {"cmd": "reply", "thread": 7, "text": MARK},
            {"cmd": "reply", "thread": MARK, "text": MARK},
            {"cmd": "send", "addresses": [MARK, "+15145550123"], "text": MARK},
            {"cmd": "send", "addresses": MARK, "text": MARK},
            {"cmd": "load", "thread": MARK, "start": MARK, "count": MARK},
            {"cmd": "attachment", "part": MARK, "id": MARK, "mime": MARK},
            {"cmd": "attachment", "part": 3, "id": MARK, "mime": "image/png"},
            {"cmd": MARK, "text": MARK},
            {"cmd": "refresh"},
            {"text": MARK},
        ]
        for fail in (False, True):
            sms = self.sms()
            sms.fail = fail
            saved = bridge.read_contacts
            bridge.read_contacts = lambda device_id: ({}, [])
            try:
                with stderr_of() as got:
                    for cmd in commands:
                        sms.command(cmd)
            finally:
                bridge.read_contacts = saved
            self.silent(got)

    def test_sms_lines_that_are_not_commands(self):
        for line in (MARK + "\n", '{"cmd": "' + MARK + '", "text": "\n', "[" + MARK + "]\n", '"' + MARK + '"\n', "{" + MARK + "}\n"):
            sms = self.sms()
            with stderr_of(line) as got:
                try:
                    sms.on_stdin(0, 0)
                except (AttributeError, TypeError):
                    pass
            self.silent(got)

    def test_sms_messages_that_carry_the_marker_in_every_field(self):
        class Params:
            def __init__(self, m):
                self.m = m
            def get_child_value(self, i):
                return self
            def get_variant(self):
                return self
            def unpack(self):
                return self.m

        sms = self.sms()
        attachments = [(MARK, MARK, "", MARK), (MARK, "image/png", "!!" + MARK, MARK)]
        with stderr_of() as got:
            for signal in ("conversationCreated", "conversationUpdated"):
                sms.on_signal(None, None, "/dev", None, signal,
                              Params((signal, MARK, [(MARK,), ("+15145550123",)], 1000, 1, 0, 7, 9, 0, attachments)))
                sms.on_signal(None, None, "/dev", None, signal, Params((signal, MARK)))
                sms.on_signal(None, None, "/dev", None, signal, Params(MARK))
            sms.emit_threads = lambda: None
            sms.on_signal(None, None, "/dev", None, "attachmentReceived", bridge.GLib.Variant("(ss)", (MARK, MARK)))
            sms.on_signal(None, None, "/dev", None, "conversationRemoved", bridge.GLib.Variant("(x)", (7,)))
        self.silent(got, expect_on_stdout=True)

    # -- calls and the verbs that carry text --
    def call_world(self):
        class Conn:
            def call_sync(self, *args):
                return None
        calls = [("incoming", MARK + "+15145550123", MARK), ("waiting", MARK, MARK)]
        ifaces = {bridge.TEL_AG: {"Address": "00:11:22:33:44:55", "SpeakerVolume": 9, "MicrophoneVolume": 12},
                  bridge.TEL_TRANSPORT: {"State": "idle", "Codec": 2, "RejectSCO": True}}
        objects = {"/org/pipewire/Telephony/ag0/call%d" % i: {bridge.TEL_CALL: {
            "State": s, "LineIdentification": n, "Name": name, "Multiparty": False}} for i, (s, n, name) in enumerate(calls)}
        gateway = bridge.parse_gateway("/org/pipewire/Telephony/ag0", ifaces, objects)
        return Conn(), gateway

    def test_call_verbs_that_carry_the_marker(self):
        conn, gateway = self.call_world()
        saved = bridge.gateway_of
        bridge.gateway_of = lambda device_id, c=None: (conn, gateway)
        verbs = ["answer", "answer-phone", "decline", "hangup", "end-answer", "hangup-all", "dial", "tones",
                 "swap", "merge", "audio-here", "keep-on-phone"]
        try:
            for verb in verbs:
                with stderr_of(MARK + "+15145550123") as got:
                    bridge.main(["call", verb, "d1"])
                self.silent(got)
                with stderr_of() as got:
                    bridge.main(["call", verb, "d1", MARK])
                self.silent(got)
            bridge.gateway_of = lambda device_id, c=None: (conn, None)
            for verb in verbs:
                with stderr_of(MARK) as got:
                    bridge.main(["call", verb, "d1"])
                self.silent(got)
        finally:
            bridge.gateway_of = saved

    def test_the_text_verbs_that_carry_the_marker(self):
        saved = (bridge.bus, bridge.call, bridge.device_name)
        bridge.bus = lambda: None
        bridge.call = lambda conn, path, iface, method, args=None, sig=None: ()
        bridge.device_name = lambda conn, device_id: "Pixel 8"
        try:
            for verb in ("text", "url", "dial", "ping", "reply"):
                for extra in ([], ["reply-1"], [MARK]):
                    with stderr_of(MARK) as got:
                        bridge.act([verb, "d1"] + extra)
                    self.silent(got)
        finally:
            bridge.bus, bridge.call, bridge.device_name = saved


class TheTestCatchesAPlantedLog(unittest.TestCase):
    def test_a_marker_written_to_stderr_is_found(self):
        for write in (lambda: print(MARK, file=sys.stderr), lambda: os.write(2, MARK.encode()),
                      lambda: sys.stderr.write(MARK)):
            with stderr_of() as got:
                write()
            self.assertIn(MARK, got["err"])
        probe = NoPrivateTextOnStderr()
        with stderr_of() as got:
            print(MARK, file=sys.stderr)
        with self.assertRaises(AssertionError):
            probe.silent(got)

    def test_a_verb_that_logs_what_it_was_given_fails(self):
        saved = bridge.contact_open
        bridge.contact_open = lambda kind, value: print("opening " + value, file=sys.stderr) or bridge.EXIT_OK
        try:
            with stderr_of(MARK) as got:
                bridge.main(["contact-open", "mail"])
        finally:
            bridge.contact_open = saved
        with self.assertRaises(AssertionError):
            NoPrivateTextOnStderr().silent(got)


if __name__ == "__main__":
    unittest.main()
