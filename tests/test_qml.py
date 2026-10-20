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

# What a hover handler assigns when it takes a keyboard cursor: the row's
# place (`...Index`, `...Cursor`) or the section holding it. `cursorActive`
# alone shows the cursor where it already is: it is not a place.
CURSOR_WORDS = re.compile(r"\bfocusSection\s*=(?!=)|\b\w*(?:[iI]ndex|[cC]ursor)\s*=(?!=)")
HOVER_HANDLER = re.compile(r"\bon(?:Entered|Hovered)\s*:")
HOVER_ASKS = re.compile(r"\b(?:hoverTake|pointerMoved|pointerAt)\(")


def handler_body(text, start):
    """The handler's text from `start` (just after its colon): a statement to
    the end of its line, or all the lines of a block, a `function(...) {...}`,
    or an `if (...)` whose statement is on the next line."""
    depth, i, n = 0, start, len(text)
    while i < n:
        c = text[i]
        if c in "([{":
            depth += 1
        elif c in ")]}":
            depth -= 1
        elif depth <= 0 and (c == ";" or c == "\n"):
            so_far = text[start:i].strip()
            after = text[i + 1:].lstrip()
            open_ended = (so_far == "" or re.fullmatch(r"(?:if\s*\(.*\)|function\s*\(.*\)|else)", so_far, re.S)
                          or (after.startswith("{") and c == "\n"))
            if c == ";" or not open_ended:
                return text[start:i]
        i += 1
    return text[start:]


def hover_that_takes_the_cursor_unasked(path):
    """A hover handler that moves a keyboard cursor without asking whether
    the pointer moved. Content that scrolls or folds under a resting pointer
    sends the row now beneath it an enter, and that took the cursor back from
    the keys (#254). The handler hands its action to `hoverTake()` or asks
    `pointerMoved()` (PointerGate), or calls `pointerAt`; a flag spent when
    asked (`hoverMoved()`) is not an ask, since a move that nothing asked
    about stays unspent and the next row to ask takes the cursor (#330). A
    handler that only passes the row on (`root.hovered(i)`) moves nothing.
    The handler is read whole, on one line or across several. A cursor moved
    through a function the handler calls is not seen: ask in the handler."""
    text = code_only(open(path).read())
    found = []
    for m in HOVER_HANDLER.finditer(text):
        body = handler_body(text, m.end())
        if CURSOR_WORDS.search(body) and not HOVER_ASKS.search(body):
            number = text.count("\n", 0, m.start()) + 1
            found.append("%s:%d: a hover moves the cursor without asking if the pointer moved" % (os.path.basename(path), number))
    return found


QML_FILES = sorted(glob.glob(os.path.join(ROOT, "*.qml")))


class HoverNeedsAPointerMove(unittest.TestCase):
    def test_every_hover_that_moves_a_cursor_asks(self):
        found = [p for f in QML_FILES for p in hover_that_takes_the_cursor_unasked(f)]
        self.assertEqual(found, [], "\n".join(found))

    def test_every_qml_file_is_read(self):
        names = {os.path.basename(f) for f in QML_FILES}
        self.assertTrue({"Panel.qml", "AppsView.qml", "MessagesView.qml", "ContactsView.qml", "SettingsView.qml"} <= names)

    def found_in(self, source):
        import tempfile
        with tempfile.NamedTemporaryFile("w", suffix=".qml", delete=False) as f:
            f.write(source)
        try:
            return hover_that_takes_the_cursor_unasked(f.name)
        finally:
            os.remove(f.name)

    def test_the_check_finds_one(self):
        self.assertEqual(len(self.found_in(
            "Item {\n  onEntered: { root.cursorActive = true; root.rowIndex = 1 }\n"
            "  onHovered: root.hoverTake(function() { root.cursorActive = true; root.rowIndex = 2 })\n"
            "  onHovered: function(i) { view.cursor = i }\n  onEntered: root.hovered(idx)\n"
            "  onEntered: view.pointerAt(row.index)\n"
            "  onHovered: if (root.hoverMoved()) { root.cursorActive = true; root.rowIndex = 2 }\n}\n")), 3)

    def test_the_check_reads_a_handler_across_lines(self):
        unasked = [
            "Item {\n  MouseArea {\n    onEntered: {\n      view.suggestionCursor = idx\n    }\n  }\n}\n",
            "Item {\n  onHovered: function(on) {\n    if (on) {\n      root.focusSection = \"a\"\n    }\n  }\n}\n",
            "Item {\n  onEntered: if (ready)\n    root.settingsIndex = 2\n}\n",
            "Item {\n  onEntered: if (root.hoverMoved()) {\n    root.settingsIndex = 2\n  }\n}\n",
            "Item {\n  onEntered:\n  {\n    root.photoIndex = 2\n  }\n}\n",
        ]
        for source in unasked:
            self.assertEqual(len(self.found_in(source)), 1, source)
        asked = [
            "Item {\n  onEntered: {\n    view.hoverTake(function() { view.suggestionCursor = idx })\n  }\n}\n",
            "Item {\n  onEntered: {\n    root.cursorActive = true\n    root.hovered(idx)\n  }\n}\n",
            "Item {\n  onEntered: {\n    view.pointerAt(row.index)\n  }\n  property int n: index\n  x: cursor == 1 ? 1 : 2\n}\n",
        ]
        for source in asked:
            self.assertEqual(self.found_in(source), [], source)


class OnePointerForThePanel(unittest.TestCase):
    """Whether a hover is the pointer's move comes from the panel's one
    PointerGate (#327). A view that kept the pointer's last position from its
    own areas counted a pointer that last moved elsewhere, then rested, as
    moved on the first enter beneath it."""

    def read(self, name):
        return code_only(open(os.path.join(ROOT, name)).read())

    def test_no_view_keeps_a_pointer_position_of_its_own(self):
        for name in ("MessagesView.qml", "ContactsView.qml", "AppsView.qml", "SettingsView.qml"):
            text = self.read(name)
            self.assertNotIn("lastPointer", text, name)
            self.assertNotIn("mapToGlobal", text, name)

    def test_the_panel_gives_each_list_view_the_gate(self):
        panel = self.read("Panel.qml")
        for view in ("MessagesView", "ContactsView"):
            body = panel[panel.index(view + " {"):]
            body = body[:body.index("\n              }\n")]
            self.assertRegex(body, r"\bhoverMovedTo:\s*root\.hoverMovedTo\b", view)
            text = self.read(view + ".qml")
            self.assertRegex(text, r"property var hoverMovedTo:", view)
            self.assertRegex(text, r"function pointerMoved\(area\)\s*\{\s*return hoverMovedTo\(area\.mapToItem\(null, area\.mouseX, area\.mouseY\)\)", view)

    def test_no_flag_carries_a_move_from_one_hover_to_the_next(self):
        gate = self.read("PointerGate.qml")
        for word in ("seen", "settle"):
            self.assertNotRegex(gate, r"\b%s\b" % word)
        self.assertNotRegex(gate, r"function moved\(\)")
        for name in sorted(glob.glob(os.path.join(ROOT, "*.qml"))):
            self.assertNotRegex(self.read(os.path.basename(name)), r"\bhoverMoved\(\)|\bpointerGate\.(?:moved|settle)\(", os.path.basename(name))

    def test_a_hover_is_answered_by_the_event_that_brought_it(self):
        gate = self.read("PointerGate.qml")
        self.assertRegex(gate, r"function take\(action\)")
        self.assertRegex(gate, r"Qt\.callLater\(drop\)")
        panel = self.read("Panel.qml")
        self.assertRegex(panel, r"HoverHandler\s*\{\s*onPointChanged:\s*pointerGate\.heard\(point\.scenePosition\)")
        self.assertRegex(panel, r"\bhoverTake:\s*root\.hoverTake\b")
        self.assertRegex(self.read("AppsView.qml"), r"property var hoverTake:")

    def test_the_gate_judges_a_hover_by_where_the_pointer_rests(self):
        gate = self.read("PointerGate.qml")
        self.assertRegex(gate, r"function movedTo\(p\)\s*\{\s*return moved\(p\)\s*\}")
        self.assertRegex(gate, r"function moved\(p\)\s*\{\s*return Math\.abs\(p\.x - at\.x\) > 0\.5 \|\| Math\.abs\(p\.y - at\.y\) > 0\.5")


ROW_HOVERED = re.compile(r"\broot\.(?:hovered|activated)\(\s*(?:(\w+)\.)?rowIndex\s*\)")
ROW_STOP = re.compile(r"CursorStop\s*\{\s*here:\s*root\.cursorIndex\s*===\s*(?:(\w+)\.)?rowIndex\b")
ROW_OWN_CURSOR = re.compile(r"\bhasCursor\s*:\s*root\.cursorIndex\b")


def settings_rows_without_a_cursor_stop(path):
    """A Settings row the keys reach that is not a CursorStop. The page's
    CursorGlide draws the cursor on its target and the page follows it
    (`followCursor`), so a row that draws its own cursor shows none and the
    page never scrolls to it (#324). Each row the page hovers or activates
    by its `rowIndex` has a CursorStop on the same index, and none sets
    `hasCursor` from `cursorIndex`."""
    text = code_only(open(path).read())
    name = os.path.basename(path)
    reached = {m.group(1) or "" for m in ROW_HOVERED.finditer(text)}
    stopped = set()
    for m in ROW_STOP.finditer(text):
        if m.group(1):
            stopped.add(m.group(1))
            continue
        # A bare `rowIndex` is the row's own: the stop sits directly in a
        # `component` whose root holds it (a child object's scope does not
        # see its parent's properties), and the component's id names it.
        start = text.rfind("component ", 0, m.start())
        if start < 0:
            continue
        before = text[start:m.start()]
        if before.count("{") - before.count("}") != 1:
            continue
        own = re.compile(r"\bid:\s*(\w+)").search(text, start, m.start())
        stopped.add(own.group(1) if own else "")
    found = ["%s: a row reached by %s.rowIndex has no CursorStop" % (name, who) for who in sorted(reached - stopped - {""})]
    if "" in reached:
        found.append("%s: a handler names its row by a bare rowIndex; name it by the row's id so its stop can be matched" % name)
    for m in ROW_OWN_CURSOR.finditer(text):
        found.append("%s:%d: a row draws its own cursor (hasCursor from cursorIndex); use a CursorStop"
                     % (name, text.count("\n", 0, m.start()) + 1))
    return found


class SettingsRowsHaveACursorStop(unittest.TestCase):
    def test_every_row_the_keys_reach_has_one(self):
        found = settings_rows_without_a_cursor_stop(os.path.join(ROOT, "SettingsView.qml"))
        self.assertEqual(found, [], "\n".join(found))

    def test_the_check_finds_one(self):
        import tempfile
        with tempfile.NamedTemporaryFile("w", suffix=".qml", delete=False) as f:
            f.write("Item {\n  Button {\n    readonly property int rowIndex: 3\n"
                    "    hasCursor: root.cursorIndex === rowIndex\n"
                    "    onClicked: root.activated(rowIndex)\n  }\n"
                    "  Button {\n    CursorStop { here: root.cursorIndex === rowIndex; glide: g }\n"
                    "    onHovered: root.hovered(rowIndex)\n  }\n"
                    "  component Row2: Item {\n    id: row2\n    CursorStop { here: root.cursorIndex === rowIndex; glide: g }\n"
                    "    onHovered: root.hovered(row2.rowIndex)\n  }\n"
                    "  Rectangle {\n    onEntered: root.hovered(other.rowIndex)\n  }\n}\n")
        try:
            found = settings_rows_without_a_cursor_stop(f.name)
            self.assertEqual(len(found), 3, found)
        finally:
            os.remove(f.name)


def settings_repeaters_over_every_row(path):
    """Lines of a Repeater over every row of the page whose delegate hides
    itself by the row's kind: each such Repeater builds a delegate for every
    row it does not draw, and opening Settings froze for about a second."""
    import re
    text = open(path).read()
    found = []
    for m in re.finditer(r"Repeater \{\s*model: (?:[^\n?]*\? )?root\.rows\b[^\n]*\n(.*?)\n\s*\}\n", text, re.S):
        if re.search(r"visible: [^\n]*modelData\.kind", m.group(1)):
            found.append("%s:%d: a Repeater over root.rows hides rows by kind; use root.rowsWhere"
                         % (os.path.basename(path), text.count("\n", 0, m.start()) + 1))
    return found


class SettingsRepeatersDrawOnlyTheirRows(unittest.TestCase):
    def test_no_repeater_builds_a_delegate_for_every_row(self):
        found = settings_repeaters_over_every_row(os.path.join(ROOT, "SettingsView.qml"))
        self.assertEqual(found, [], "\n".join(found))

    def test_the_check_finds_one(self):
        import tempfile
        with tempfile.NamedTemporaryFile("w", suffix=".qml", delete=False) as f:
            f.write("Item {\n  Repeater {\n    model: root.rows\n    ListRow {\n"
                    "      required property var modelData\n      visible: modelData.kind === \"keys\"\n    }\n  }\n"
                    "  Repeater {\n    model: root.rowsWhere(function(r) { return r.kind === \"keys\" })\n"
                    "    ListRow { required property var modelData }\n  }\n}\n")
        try:
            self.assertEqual(len(settings_repeaters_over_every_row(f.name)), 1)
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


class PagesFitTheCard(unittest.TestCase):
    """Messages and Contacts are never taller than the card can be (#332,
    #339): a fixed 600 px under the header and a note pushed the key hints
    below the fold on a 720 px screen."""

    PAGES = (("MessagesView", "messagesView", "sms:"), ("ContactsView", "contactsView", "contacts:"))

    def height_line(self, text, view, after):
        body = text[text.index(view + " {"):]
        body = body[:body.index("\n              }\n")]
        return body[body.index("height:"):body.index(after)]

    def test_each_height_is_bounded_by_what_the_card_has_left(self):
        text = code_only(open(os.path.join(ROOT, "Panel.qml")).read())
        for view, ident, after in self.PAGES:
            found = self.height_line(text, view, after)
            for word in ("availableCardHeight", "verticalContentInset", ident + ".y"):
                self.assertIn(word, found, view)

    def test_the_check_finds_a_fixed_height(self):
        planted = "MessagesView {\n  height: visible ? Style.space(600) : 0\n  sms: x\n              }\n"
        with self.assertRaises(AssertionError):
            found = self.height_line(planted, "MessagesView", "sms:")
            self.assertIn("availableCardHeight", found)


class QmldirListsEveryComponent(unittest.TestCase):
    """With Qt 6.12 a folder that has a `qmldir` shows a file only the types
    that file lists, so a component used by name and not listed is "not a
    type" and the widget leaves the bar (#365). The entry points are loaded
    by path, never by name."""

    BY_PATH = {"BarWidget", "Panel", "Service"}

    def listed(self, text):
        return {m.group(1) for m in re.finditer(r"^(?:singleton\s+)?(\w+)\s+\d+\.\d+\s+\1\.qml\s*$", text, re.M)}

    def used_by_name(self, sources, listed):
        """(file, component) for each component another file instantiates
        or reaches as a singleton by its name and the qmldir does not list."""
        files = {os.path.basename(p)[:-4]: code_only(t) for p, t in sources.items()}
        return sorted(
            (user, name) for user, code in files.items() for name in files
            if name != user and name not in self.BY_PATH and name not in listed
            and re.search(r"(?<![\w.])" + name + r"\s*[{.]", code))

    def shipped(self):
        out = {}
        for path in glob.glob(os.path.join(ROOT, "*.qml")):
            with open(path) as f:
                out[path] = f.read()
        return out

    def test_every_component_used_by_name_is_listed(self):
        with open(os.path.join(ROOT, "qmldir")) as f:
            listed = self.listed(f.read())
        self.assertEqual(self.used_by_name(self.shipped(), listed), [])

    def test_every_listed_name_is_a_file_here(self):
        with open(os.path.join(ROOT, "qmldir")) as f:
            listed = self.listed(f.read())
        names = {os.path.basename(p)[:-4] for p in self.shipped()}
        self.assertEqual(sorted(listed - names), [])
        self.assertEqual(sorted(names - listed - self.BY_PATH), [])

    def test_the_check_finds_a_component_missing_from_qmldir(self):
        sources = {"/x/Uses.qml": "Item { Gone { } }", "/x/Gone.qml": "Item { }",
                   "/x/Single.qml": "Item { onX: Gone2.go() }", "/x/Gone2.qml": "pragma Singleton\nItem { }",
                   "/x/Quiet.qml": "Item { // Gone { }\n }"}
        listed = self.listed("singleton Clipboard 1.0 Clipboard.qml\nUses 1.0 Uses.qml\n")
        self.assertEqual(listed, {"Clipboard", "Uses"})
        self.assertEqual(self.used_by_name(sources, listed), [("Single", "Gone2"), ("Uses", "Gone")])


if __name__ == "__main__":
    unittest.main()
