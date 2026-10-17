"""The QML files load: what has taken the whole widget off the bar before,
caught before the shell sees it. A handler written twice in one object
(`onOpenedChanged` twice), or one id used twice in a file. Syntax itself
is CI's qmlformat run."""

import glob
import os
import re
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.join(HERE, "..")


def code_only(text):
    """The text with strings and comments blanked (their length kept)."""
    out, i, n = [], 0, len(text)
    while i < n:
        c = text[i]
        if text.startswith("//", i):
            j = text.find("\n", i)
            j = n if j < 0 else j
            out.append(" " * (j - i)); i = j
        elif text.startswith("/*", i):
            j = text.find("*/", i + 2)
            j = n if j < 0 else j + 2
            out.append(re.sub(r"[^\n]", " ", text[i:j])); i = j
        elif c in "\"'`":
            j = i + 1
            while j < n and text[j] != c:
                j += 2 if text[j] == "\\" else 1
            out.append(c + " " * (min(j, n) - i - 1) + (c if j < n else "")); i = j + 1
        else:
            out.append(c); i += 1
    return "".join(out)


def problems(path):
    """Handlers named twice in one object; ids used twice in one id scope
    (the file, or an inline `component`, which has its own)."""
    with open(path) as f:
        text = code_only(f.read())
    found, stack = [], [{"handlers": {}, "ids": {}, "scope": True}]
    component_next = False
    name = os.path.basename(path)

    def ids():
        for frame in reversed(stack):
            if frame["scope"]:
                return frame["ids"]

    for number, line in enumerate(text.splitlines(), 1):
        m = re.match(r"^\s*(on[A-Z]\w*)\s*:", line)
        if m:
            if m.group(1) in stack[-1]["handlers"]:
                found.append("%s:%d: %s also at line %d" % (name, number, m.group(1), stack[-1]["handlers"][m.group(1)]))
            stack[-1]["handlers"][m.group(1)] = number
        if re.match(r"^\s*component\s+\w+\s*:", line):
            component_next = True
        pos = 0
        for m in re.finditer(r"[{}]|(?:^|(?<=[{;\s]))id\s*:\s*(\w+)\s*(?=$|[;}])", line):
            if m.group(0) == "{":
                stack.append({"handlers": {}, "ids": {}, "scope": component_next})
                component_next = False
            elif m.group(0) == "}":
                if len(stack) > 1:
                    stack.pop()
            else:
                seen = ids()
                if m.group(1) in seen:
                    found.append("%s:%d: id %s also at line %d" % (name, number, m.group(1), seen[m.group(1)]))
                seen[m.group(1)] = number
    return found


class Qml(unittest.TestCase):
    def test_no_handler_twice_and_no_id_twice(self):
        files = sorted(glob.glob(os.path.join(ROOT, "*.qml")))
        self.assertTrue(files)
        found = [p for f in files for p in problems(f)]
        self.assertEqual(found, [], "\n".join(found))

    def test_a_demo_never_writes_the_settings(self):
        text = code_only(open(os.path.join(ROOT, "Panel.qml")).read())
        body = text[text.index("function persistSettings("):]
        body = body[:body.index("\n  }\n")]
        self.assertIn("phone.demo", body[:body.index("updateEntryInline")], "persistSettings writes in a demo")

    def test_the_check_finds_them(self):
        import tempfile
        with tempfile.NamedTemporaryFile("w", suffix=".qml", delete=False) as f:
            f.write("Item {\n  onOpenedChanged: x = 1\n  // onOpenedChanged: in a comment\n  Item { onOpenedChanged: y }\n  onOpenedChanged: z = \"{\"\n  Item { id: a }\n  Item { id: a }\n"
                    "  component One: Item { id: b }\n  component Two: Item { id: b }\n}\n")
        try:
            self.assertEqual(len(problems(f.name)), 2, problems(f.name))
        finally:
            os.remove(f.name)


def repeater_delegates_that_reparent(path):
    """A Repeater's delegate that sets its own `parent:`. The Repeater stacks
    each new item after the last, which must be a sibling; one moved away
    makes Qt log `QQuickItem::stackAfter: Cannot stack` with no source."""
    text = code_only(open(path).read())
    found = []
    for m in re.finditer(r"\bRepeater\s*\{", text):
        depth, i = 1, m.end()
        while i < len(text) and depth:
            depth += {"{": 1, "}": -1}.get(text[i], 0)
            i += 1
        body = text[m.end():i - 1]
        level = 0
        for line in body.splitlines():
            if level == 1 and re.match(r"\s*parent\s*:", line):
                found.append("%s:%d: a Repeater's delegate sets parent:" % (
                    os.path.basename(path), text.count("\n", 0, m.end()) + body[:body.index(line)].count("\n") + 1))
            level += line.count("{") - line.count("}")
    return found


class RepeaterDelegates(unittest.TestCase):
    def test_no_delegate_moves_itself_away(self):
        found = [p for f in sorted(glob.glob(os.path.join(ROOT, "*.qml"))) for p in repeater_delegates_that_reparent(f)]
        self.assertEqual(found, [], "\n".join(found))

    def test_the_check_finds_one(self):
        import tempfile
        with tempfile.NamedTemporaryFile("w", suffix=".qml", delete=False) as f:
            f.write("Item {\n  Repeater {\n    model: 2\n    Rectangle {\n      parent: other\n      Item { parent: x }\n    }\n  }\n}\n")
        try:
            self.assertEqual(len(repeater_delegates_that_reparent(f.name)), 1)
        finally:
            os.remove(f.name)


# Every bridge verb QML starts is classified here, so a new verb is covered
# by default: until someone lists it, the build fails. Any local process can
# read a command line from /proc, so text a person wrote goes over stdin
# (`run`'s input) and the arguments after the device are ids only.
#   ID_ONLY_VERBS: argv holds the device's id (and literal flags), nothing else.
#   TEXT_VERBS: the verb carries text a person wrote; the text goes over stdin.
#   REVIEWED_VERBS: argv holds more than ids (a package, a path, a fix name);
#     each such element is read one by one in tests/test_argv.py's ARGV_ALLOWED.
ID_ONLY_VERBS = {
    "ring", "share", "clipboard", "pair", "accept", "reject", "unpair", "watch", "doctor",
    "screen", "screen-close", "screen-focus", "screen-pair", "photos", "photos-cached",
    "app-icons", "apps", "features", "sms", "contacts", "call-audio", "dismiss",
}
TEXT_VERBS = {"ping", "text", "url", "dial", "reply"}
REVIEWED_VERBS = {
    "fix", "device-fix", "call", "action", "screen-open", "screen-dock", "screen-sound",
    "screen-volume", "screen-watch", "app-forget", "open-file", "copy-file", "save-file",
    "safe-art", "received-dismiss", "contact-open", "contacts-app",
}
ID_EXPRESSIONS = {
    "id", "String(id)", "device.id", "String(device.id)", "deviceId", "sms.deviceId",
    "root.callAudioDevice", "c.device", "n.id",
}
ALLOWED_ARGS = {"reply": ["n.replyId"], "dial": ["c.device"]}


def top_args(raw, clean, open_at):
    """The top-level elements, as written, of the brackets opening at open_at."""
    depth, parts, start = 0, [], open_at + 1
    for i in range(open_at, len(clean)):
        c = clean[i]
        if c in "([{":
            depth += 1
        elif c in ")]}":
            depth -= 1
            if depth == 0:
                parts.append(raw[start:i].strip())
                return [a for a in parts if a != ""]
        elif c == "," and depth == 1:
            parts.append(raw[start:i].strip())
            start = i + 1
    return [a for a in parts if a != ""]


def verbs_started(path):
    """(line, verb, arguments after the verb, how) for every bridge verb the
    file starts: `run("verb", [...])`, `runOn(id, "verb")`, `[bridge, "verb", ...]`
    and `launch(["verb", ...])`."""
    raw = open(path).read()
    clean = code_only(raw)
    line = lambda i: raw.count("\n", 0, i) + 1
    literal = lambda e: e[1:-1] if re.fullmatch(r'"[^"]*"', e) else None
    found = []
    for m in re.finditer(r"(?<!\w)run\(", clean):
        if clean[:m.start()].rstrip().endswith("function"):
            continue
        args = top_args(raw, clean, m.end() - 1)
        if args and literal(args[0]):
            argv = args[1] if len(args) > 1 else "[]"
            if argv.startswith("["):
                found.append((line(m.start()), literal(args[0]), top_args(argv, code_only(argv), 0), "run"))
            else:
                found.append((line(m.start()), literal(args[0]), None, "run"))
    for m in re.finditer(r"(?<!\w)runOn\(", clean):
        if clean[:m.start()].rstrip().endswith("function"):
            continue
        args = top_args(raw, clean, m.end() - 1)
        if len(args) > 1 and literal(args[1]):
            found.append((line(m.start()), literal(args[1]), [], "runOn"))
    for m in re.finditer(r"\[\s*(?:root\.|sms\.)?bridge\s*,", clean):
        args = top_args(raw, clean, m.start())
        if len(args) > 1 and literal(args[1]):
            found.append((line(m.start()), literal(args[1]), args[2:], "bridge"))
    for m in re.finditer(r"(?<![\w.])launch\(\s*\[", clean):
        if clean[:m.start()].rstrip().endswith("function"):
            continue
        args = top_args(raw, clean, clean.index("[", m.start()))
        if args and literal(args[0]):
            found.append((line(m.start()), literal(args[0]), args[1:], "launch"))
    return found

CURSOR_WORDS = re.compile(r"focusSection\s*=|[iI]ndex\s*=|[cC]ursor\s*=")
PAGES_WITH_A_CURSOR = ("Panel.qml", "AppsView.qml")
HOVER_HANDLER = re.compile(r"^\s*(?:onEntered|onHovered)\s*:(.*)$")


def hover_that_takes_the_cursor_unasked(path):
    """A hover handler that moves a keyboard cursor without asking whether
    the pointer moved. Content that scrolls or folds under a resting pointer
    sends the row now beneath it an enter, and that took the cursor back from
    the keys (#254). The handler asks `hoverMoved()` / `pointerMoved()`
    (PointerGate); a handler that only passes the row on (`root.hovered(i)`)
    moves nothing, and a list that tracks the position itself calls
    `pointerAt`. Messages and Contacts keep their own lists and do that."""
    text = code_only(open(path).read())
    found = []
    for number, line in enumerate(text.splitlines(), 1):
        m = HOVER_HANDLER.match(line)
        if not m or not CURSOR_WORDS.search(m.group(1)):
            continue
        if not re.search(r"\b(?:hoverMoved|pointerMoved|pointerAt)\(", m.group(1)):
            found.append("%s:%d: a hover moves the cursor without asking if the pointer moved" % (os.path.basename(path), number))
    return found


class HoverNeedsAPointerMove(unittest.TestCase):
    def test_every_hover_that_moves_a_cursor_asks(self):
        found = [p for f in PAGES_WITH_A_CURSOR for p in hover_that_takes_the_cursor_unasked(os.path.join(ROOT, f))]
        self.assertEqual(found, [], "\n".join(found))

    def test_the_check_finds_one(self):
        import tempfile
        with tempfile.NamedTemporaryFile("w", suffix=".qml", delete=False) as f:
            f.write("Item {\n  onEntered: { root.cursorActive = true; root.rowIndex = 1 }\n"
                    "  onHovered: if (root.hoverMoved()) { root.cursorActive = true }\n"
                    "  onHovered: function(i) { view.cursor = i }\n  onEntered: root.hovered(idx)\n"
                    "  onEntered: view.pointerAt(this, row.index)\n}\n")
        try:
            self.assertEqual(len(hover_that_takes_the_cursor_unasked(f.name)), 2, hover_that_takes_the_cursor_unasked(f.name))
        finally:
            os.remove(f.name)


# Verbs that carry text a person wrote. Any local process can read a command
# line from /proc, so the text goes over stdin (`run`'s input), and the
# arguments after the device are ids only.
PRIVATE_VERBS = ("ping", "text", "url", "dial", "reply")
ALLOWED_ARGS = {"reply": ["n.replyId"]}


def private_text_in_argv(path):
    """Lines where a verb is not classified, or carries more in its argument
    list than its class allows."""
    text = open(path).read()
    found = []
    here = os.path.basename(path)
    for number, verb, args, how in verbs_started(path):
        where = "%s:%d: " % (here, number)
        if verb not in ID_ONLY_VERBS | TEXT_VERBS | REVIEWED_VERBS:
            found.append(where + "\"%s\" is not in ID_ONLY_VERBS, TEXT_VERBS or REVIEWED_VERBS" % verb)
        elif verb in ID_ONLY_VERBS and args is not None:
            for a in args:
                if not re.fullmatch(r'"[^"]*"', a) and a not in ID_EXPRESSIONS:
                    found.append(where + "\"%s\" carries %s, which is not a device id" % (verb, a))
        elif verb in TEXT_VERBS:
            if args is None:
                found.append(where + "run(\"%s\") argv is not a literal list" % verb)
            elif how == "run" and args != ALLOWED_ARGS.get(verb, []):
                found.append(where + "run(\"%s\") argv %s" % (verb, args))
            elif how == "bridge" and len(args) > 1:
                found.append(where + "[bridge, \"%s\"] argv %s" % (verb, args))
    name = os.path.basename(path)
    line = lambda m: text.count("\n", 0, m.start()) + 1
    # `call dial|tones <device>` and `contact-open <kind>` carry a number,
    # digits or a contact's value; `contacts-app --find` carries a search.
    for m in re.finditer(r'\[\s*(?:root\.)?bridge\s*,\s*"call"\s*,\s*"(?:dial|tones)"\s*([^\]]*)\]', text):
        if len([a for a in m.group(1).split(",") if a.strip()]) > 1:
            found.append("%s:%d: call dial/tones argv holds more than the device" % (name, line(m)))
    for m in re.finditer(r'\btones\s*:\s*\[\s*"tones"\s*,', text):
        found.append("%s:%d: tones carries its digits in argv" % (name, line(m)))
    for m in re.finditer(r'\[\s*(?:root\.)?bridge\s*,\s*"contact-open"\s*([^\]]*)\]', text):
        found.append("%s:%d: contact-open is run by a bare bridge list" % (name, line(m)))
    for m in re.finditer(r'\[\s*"contact-open"\s*,([^\]]*)\]', text):
        if len([a for a in m.group(1).split(",") if a.strip()]) > 1:
            found.append("%s:%d: contact-open argv holds more than its kind" % (name, line(m)))
    for m in re.finditer(r'"--find"\s*,', text):
        found.append("%s:%d: --find carries its text in argv" % (name, line(m)))
    return found


class PrivateText(unittest.TestCase):
    def test_private_text_never_reaches_a_command_line(self):
        found = [p for f in sorted(glob.glob(os.path.join(ROOT, "*.qml"))) for p in private_text_in_argv(f)]
        self.assertEqual(found, [], "\n".join(found))

    def test_the_check_finds_text_in_argv(self):
        import tempfile
        with tempfile.NamedTemporaryFile("w", suffix=".qml", delete=False) as f:
            f.write('run("reply", [n.replyId, message], k)\nrun("ping", [m], "ping")\n'
                    'x = [bridge, "dial", c.device, number]\nrun("text", [], "text", null, t)\n'
                    'run("ping", m !== "" ? [m] : [], "ping")\n'
                    'c = [bridge, "call", "dial", String(id), n]\nv = { tones: ["tones", digits] }\n'
                    'Quickshell.execDetached([bridge, "contact-open", kind, String(value)])\n'
                    'Quickshell.execDetached([bridge, "contacts-app"].concat(["--find", find]))\n'
                    'ok = [bridge, "call", "dial", String(id)]\nlaunch(["contact-open", kind], value)\nlaunch(["contacts-app", "--find"], find)\n')
        try:
            self.assertEqual(len(private_text_in_argv(f.name)), 8, private_text_in_argv(f.name))
        finally:
            os.remove(f.name)

    def test_a_verb_nobody_listed_fails(self):
        import tempfile
        planted = ['run("memo", [], "memo", null, t)', 'x = [bridge, "memo", id, text]', 'runOn(id, "memo")',
                   'launch(["memo", kind], value)', 'x = [root.bridge, "ring", id, note]', 'x = [bridge, "ring", id, "--flag"]']
        for source, expected in zip(planted, (1, 1, 1, 1, 1, 0)):
            with tempfile.NamedTemporaryFile("w", suffix=".qml", delete=False) as f:
                f.write(source + "\n")
            try:
                self.assertEqual(len(private_text_in_argv(f.name)), expected, source)
            finally:
                os.remove(f.name)

    def test_every_listed_verb_is_still_started_and_listed_once(self):
        started = {v for f in glob.glob(os.path.join(ROOT, "*.qml")) for _, v, _, _ in verbs_started(f)}
        listed = ID_ONLY_VERBS | TEXT_VERBS | REVIEWED_VERBS
        self.assertEqual(sorted(listed - started), [])
        self.assertEqual(len(ID_ONLY_VERBS) + len(TEXT_VERBS) + len(REVIEWED_VERBS), len(listed))


class ArtDecodeSlotFreesOnExit(unittest.TestCase):
    """A decode's slot (`artActive`, the player's `artRunning`) frees once, when
    its process ends. A process that never starts has no output to finish, so
    the slot cannot wait for the output."""

    def art_process(self, text):
        clean = code_only(text)
        start = clean.index("id: artProc")
        depth, i = 1, clean.rindex("{", 0, start) + 1
        while depth:
            depth += {"{": 1, "}": -1}.get(clean[i], 0)
            i += 1
        return clean[clean.rindex("{", 0, start):i]

    def check(self, text):
        proc = self.art_process(text)
        problems = []
        if len(re.findall(r"artActive\s*-=\s*1", proc)) != 1:
            problems.append("artActive is released in one place")
        exited = re.search(r"onExited:\s*\{(.*?)\n      \}", proc, flags=re.S)
        if not exited or "release()" not in exited.group(1):
            problems.append("onExited releases the slot")
        stream = proc[proc.index("onStreamFinished"):]
        if "artActive" in stream or "release()" in stream or "nextArt" in stream:
            problems.append("the output's end does not release the slot")
        if not re.search(r"if\s*\(\s*released\s*\)\s*return", proc):
            problems.append("a second release does nothing")
        return problems

    def test_the_slot_frees_on_exit_once(self):
        with open(os.path.join(ROOT, "Service.qml")) as f:
            self.assertEqual(self.check(f.read()), [])

    def test_the_check_finds_a_release_waiting_for_the_output(self):
        with open(os.path.join(ROOT, "Service.qml")) as f:
            text = f.read()
        late = text.replace("        release()\n        if (streamed)", "        if (streamed)", 1).replace(
            "          artProc.streamed = true\n", "          artProc.streamed = true\n          root.artActive -= 1\n", 1)
        self.assertNotEqual(self.check(late), [])


class ThreadListHasOneWriter(unittest.TestCase):
    """SmsService keeps an id -> row index beside the thread ListModel
    (Model.threadRows*); a change to the list outside the five functions that
    also change the index would leave it wrong."""

    WRITERS = ("clearThreads", "setThreads", "insertThread", "moveThread", "removeThreadAt")

    def offenders(self, text):
        clean = code_only(text)
        found = []
        for m in re.finditer(r"\bthreadModel\.(clear|append|insert|remove|move)\s*\(", clean):
            fn = re.findall(r"function\s+(\w+)\s*\(", clean[:m.start()])
            if not fn or fn[-1] not in self.WRITERS:
                found.append(clean.count("\n", 0, m.start()) + 1)
        return found

    def test_only_the_five_writers_change_the_thread_list(self):
        with open(os.path.join(ROOT, "SmsService.qml")) as f:
            text = f.read()
        self.assertEqual(self.offenders(text), [])
        for writer in self.WRITERS:
            self.assertRegex(text, r"function\s+%s\s*\(" % writer)

    def test_the_check_finds_a_write_outside_them(self):
        planted = "Item {\n  function upsert(t) {\n    threadModel.insert(0, t)\n  }\n}\n"
        self.assertEqual(self.offenders(planted), [3])


class FetchedAttachmentsOpenOnlyWhenAsked(unittest.TestCase):
    """An attachment arriving opens only when its own id was asked for: no
    "anything is pending" fallback, and the bridge's file gate is told it
    came from the device unless the bridge says it made the copy."""

    def test_only_the_exact_id_opens(self):
        text = code_only(open(os.path.join(ROOT, "SmsService.qml")).read())
        self.assertNotIn("Object.keys(pendingFiles)", text)
        self.assertIn("pendingFiles[ev.name] === true", text)
        self.assertIn('cmd.push("--from-device")', open(os.path.join(ROOT, "SmsService.qml")).read())


def call_args(text, open_paren):
    """The top-level arguments of the call whose "(" is at open_paren."""
    depth, args, start = 0, [], open_paren + 1
    for i in range(open_paren, len(text)):
        c = text[i]
        if c in "([{":
            depth += 1
        elif c in ")]}":
            depth -= 1
            if depth == 0:
                args.append(text[start:i].strip())
                return [a for a in args if a != ""]
        elif c == "," and depth == 1:
            args.append(text[start:i].strip())
            start = i + 1
    return args


def enclosing_function(text, at):
    m = None
    for m in re.finditer(r"function\s+(\w+)", text[:at]):
        pass
    return m.group(1) if m else ""


class DeviceFilesGoThroughTheGate(unittest.TestCase):
    """A QML start of the bridge's `open-file` or `copy-file` that can carry
    a file the device sent passes `--from-device` or `--local`, so the
    bridge's gate (what the file holds decides; a picture opens or is copied
    only as the sandbox's copy) applies. Each caller of the QML functions
    that start them is checked too: `openPath` builds its flag from its
    second argument, so a caller that leaves it out skips the gate while the
    function's own text still names the flag. A file the plugin made itself
    is on these lists."""

    OWN_FILES = {("SmsService.qml", "files[j].thumb"): "the demo's picture, a local file"}
    OWN_PATHS = {("Panel.qml", "openPhotoFolder"): "an album's folder, never a file"}

    def gaps(self, paths):
        found = []
        for path in paths:
            raw = open(path).read()
            text = code_only(raw)
            name = os.path.basename(path)
            for m in re.finditer(r'"(?:open|copy)-file"', raw):
                start = max(text.rfind("function ", 0, m.start()), 0)
                end = text.find("function ", m.end())
                scope = raw[start:len(raw) if end < 0 else end]
                line = raw[raw.rfind("\n", 0, m.start()) + 1:raw.find("\n", m.end())]
                own = any(f == name and k in line for (f, k) in self.OWN_FILES)
                if not own and "--from-device" not in scope and "--local" not in scope:
                    found.append("%s:%d %s without --from-device or --local" % (name, raw.count("\n", 0, m.start()) + 1, m.group(0)))
            for m in re.finditer(r"\b(openPath|openFromDevice|copyFile)\s*\(", text):
                if text[:m.start()].rstrip().endswith("function"):
                    continue
                args = call_args(text, m.end() - 1)
                where = (name, enclosing_function(text, m.start()))
                ok = (m.group(1) == "openPath" and len(args) > 1 and args[1] == "true") or m.group(1) != "openPath"
                if not ok and where not in self.OWN_PATHS:
                    found.append("%s:%d openPath(%s) without true: the gate is not named" % (name, raw.count("\n", 0, m.start()) + 1, ", ".join(args)))
        return found

    def test_every_start_and_caller_names_the_gate(self):
        self.assertEqual(self.gaps(sorted(glob.glob(os.path.join(ROOT, "*.qml")))), [])

    def test_the_check_sees_a_start_or_caller_without_the_gate(self):
        import tempfile
        cases = ('function a() { run([bridge, "copy-file", path]) }\n',
                 'function a() { run([bridge, "open-file", String(path)]) }\n',
                 'function f(p) { phone.openPath(p) }\n',
                 'function f(p) { phone.openPath(p, fromDevice) }\n')
        for body in cases:
            with tempfile.NamedTemporaryFile("w", suffix=".qml", delete=False) as f:
                f.write(body)
            try:
                self.assertEqual(len(self.gaps([f.name])), 1, body)
            finally:
                os.remove(f.name)
        with tempfile.NamedTemporaryFile("w", suffix=".qml", delete=False) as f:
            f.write('function a() { run([bridge, "copy-file", path, "--local"]) }\nfunction f(p) { phone.openPath(p, true) }\n')
        try:
            self.assertEqual(self.gaps([f.name]), [])
        finally:
            os.remove(f.name)

    def callers(self, name, fn):
        raw = open(os.path.join(ROOT, name)).read()
        text = code_only(raw)
        return [m for m in re.finditer(r"\b%s\s*\(" % fn, text) if not text[:m.start()].rstrip().endswith("function")]

    def test_each_real_caller_is_one_the_check_reads(self):
        found = {fn: sum(len(self.callers(os.path.basename(p), fn)) for p in glob.glob(os.path.join(ROOT, "*.qml")))
                 for fn in ("openPath", "openFromDevice", "copyFile")}
        self.assertTrue(all(found.values()), "a caller the check should read is gone or renamed: %r" % found)

    def test_every_exempt_caller_still_exists(self):
        for (name, fn) in self.OWN_PATHS:
            text = code_only(open(os.path.join(ROOT, name)).read())
            self.assertIn("function %s(" % fn, text, "%s: %s is exempt and gone" % (name, fn))

    def test_the_real_caller_that_names_the_gate_fails_without_it(self):
        import tempfile
        with open(os.path.join(ROOT, "Panel.qml")) as f:
            src = f.read()
        planted = src.replace("phone.openPath(entry.path, true)", "phone.openPath(entry.path)", 1)
        self.assertNotEqual(planted, src, "openReceived no longer calls openPath(entry.path, true)")
        with tempfile.TemporaryDirectory() as folder:
            path = os.path.join(folder, "Panel.qml")
            with open(path, "w") as f:
                f.write(planted)
            found = self.gaps([path])
        self.assertEqual(len(found), 1, found)
        self.assertRegex(found[0], r"Panel\.qml:\d+ openPath\(entry\.path\) without true")

    def test_a_definition_that_loses_its_flag_fails(self):
        import tempfile
        with open(os.path.join(ROOT, "Service.qml")) as f:
            src = f.read()
        for flag in ("--from-device", "--local"):
            planted = src.replace('"%s"' % flag, '"--other"')
            self.assertNotEqual(planted, src)
            with tempfile.NamedTemporaryFile("w", suffix=".qml", delete=False) as f:
                f.write(planted)
            try:
                self.assertTrue(self.gaps([f.name]), flag)
            finally:
                os.remove(f.name)


if __name__ == "__main__":
    unittest.main()
