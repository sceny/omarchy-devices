"""Two classes of fault, held at the sink and not at the case that was reported.

C1, private text on a command line. Any local user reads /proc/<pid>/cmdline,
so no value a person, a device or the API wrote may be an argument of a process
the plugin starts. Every place QML starts a process is found (`command:`,
`.command =`, `execDetached(`, `Quickshell.exec(`, `openUrlExternally(`, and
the two helpers that pass an argv on: `run(` and `launch(`), the argv is
followed through the variables, `.concat(`, `.push(` and ternaries that build
it, and every element that is not a string literal must be in ARGV_ALLOWED
with the reason it is not private text. A new expression fails the build until
a reviewer reads it and adds it. (tests/test_qml.py keeps the checks on the
verbs that carry text.)

C2, the clipboard read without a paste by the user. QQuickTextInput reads the
clipboard on focus and on every change, so no type built on it may be used:
TextInput, TextField, TextArea, and every type of Omarchy's `qs.Ui` that
contains one (NumberField, MultiSelect, SearchableDropdown, TextField).
`Quickshell.clipboardText` is read once, in PanelField.qml, at the paste key.
No `wl-paste` or `cliphist` anywhere the plugin runs code. (tests/test_panelfield.py
keeps the checks on PanelField itself.)"""

import glob
import os
import re
import shutil
import tempfile
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.join(HERE, "..")
OMARCHY_UI = "/usr/share/omarchy/shell/Ui"


# ---- C1: the allowlist ------------------------------------------------------
# (file, verb, expression) -> why the expression is not private text. `verb` is
# the first string literal of the argv it is in ("" when there is none); "*"
# stands for any verb in that file. Add a line only after reading what the
# expression holds at every place it is built.
ARGV_ALLOWED = {
    # the bridge and the ids of devices: no text a person wrote
    ("Service.qml", "*", "bridge"): "the bridge's path, in this plugin's folder",
    ("Service.qml", "*", "root.bridge"): "the bridge's path, in this plugin's folder",
    ("ContactsService.qml", "*", "bridge"): "the bridge's path, in this plugin's folder",
    ("SmsService.qml", "*", "sms.bridge"): "the bridge's path, in this plugin's folder",
    ("Service.qml", "*", "id"): "a device's id (KDE Connect's), the `id` of every function that takes one",
    ("Service.qml", "*", "String(id)"): "a device's id (KDE Connect's), made a string",
    ("Service.qml", "*", "device.id"): "the followed device's id",
    ("Service.qml", "*", "deviceId"): "a device's id (KDE Connect's)",
    ("Service.qml", "*", "String(device.id)"): "the followed device's id, made a string",
    ("ContactsService.qml", "*", "deviceId"): "a device's id (KDE Connect's)",
    ("SmsService.qml", "*", "sms.deviceId"): "a device's id (KDE Connect's)",
    # calls: the number and the digits go over stdin
    ("Service.qml", "call", "v[0]"): "a verb from callAction's table of literals",
    ("Service.qml", "call", "v[1]"): "a call's id from the telephony service, on/off, or the volume as a number; never a number dialled",
    ("Service.qml", "dial", "c.device"): "a device's id; the number goes over stdin",
    ("Service.qml", "call-audio", "root.callAudioDevice"): "a device's id",
    # notifications: ids and the name of a button; the reply goes over stdin
    ("Service.qml", "dismiss", "n.id"): "a notification's key (KDE Connect's), not its text",
    ("Service.qml", "action", "n.id"): "a notification's key (KDE Connect's), not its text",
    ("Service.qml", "action", "action"): "the name of a button the app gave the notification (Reply, Archive), not message text",
    ("Service.qml", "reply", "n.replyId"): "KDE Connect's id for the reply (a uuid); the reply text goes over stdin",
    # the setup steps: Model.deviceSetup's table of fixes
    ("Service.qml", "device-fix", "s.fix.what"): "a literal from Model.deviceSetup's steps",
    ("Service.qml", "device-fix", "s.fix.arg"): "a step's argument from Model.deviceSetup: a plugin name, a permission, a Bluetooth address; never text or a number from a message or a contact",
    ("Service.qml", "fix", "what"): "a fix's name, a literal from Model",
    ("Service.qml", "fix", 'String(what).split(" ")'): "a fix's name (and its argument), a literal from Model",
    ("Service.qml", "fix", 'String(plan.what).split(" ")'): "the fix the card described, a literal from Model",
    ("Service.qml", "fix", "plan.hash"): "the hash of the plan the card described",
    ("Service.qml", "omarchy", "prompt"): "the Fix with AI prompt, as Omarchy's `omarchy agent prompt` takes it; Model.aiPrompt quotes and caps what a device sent and names a device by its kind (tests/model.test.js)",
    # the screen and apps
    ("Service.qml", "screen-open", "pkg || \"\""): "an Android package name from the device's app list",
    ("Service.qml", "screen-open", "label || \"\""): "an app's display name (Camera), by which its window is found; not message text, contacts or numbers",
    ("Service.qml", "screen-open", "sound"): "here, phone or both (Model.soundPlace)",
    ("Service.qml", "screen-open", "placeArgs(place)"): "--at and --ctx: window geometry and the monitor's numbers and name",
    ("Service.qml", "screen-dock", "placeArgs(place)"): "--at and --ctx: window geometry and the monitor's numbers and name",
    ("Service.qml", "screen-sound", "pkg || \"\""): "an Android package name from the device's app list",
    ("Service.qml", "screen-sound", "label || \"\""): "an app's display name, by which its window is found; not message text, contacts or numbers",
    ("Service.qml", "screen-sound", "sound"): "here, phone or both (Model.soundPlace)",
    ("Service.qml", "screen-volume", "pkg || \"\""): "an Android package name from the device's app list",
    ("Service.qml", "screen-volume", "label || \"\""): "an app's display name, by which its window is found; not message text, contacts or numbers",
    ("Service.qml", "screen-volume", "Number(extra.level).toFixed(2)"): "a volume as a number",
    ("Service.qml", "screen-volume", "extra.mute"): "on, off or toggle",
    ("Service.qml", "screen-watch", "JSON.stringify(ctx)"): "the window's geometry and the monitor (Panel.dockCtx): numbers and the monitor's name",
    ("Service.qml", "screen-watch", "String(st.serial)"): "the device's adb serial",
    ("Service.qml", "app-forget", "pkg"): "an Android package name from the device's app list",
    # files: the plugin's own paths in its cache or in Downloads
    ("Service.qml", "open-file", "String(path)"): "a file's path in the cache or in Downloads; a received file's name is the device's, and names a file, not message text",
    ("Service.qml", "copy-file", "path"): "a file's path in the cache or in Downloads",
    ("Service.qml", "save-file", "path"): "a file's path in the cache",
    ("Service.qml", "save-file", "Model.deviceLabel(device)"): "the device's name, as the user called it",
    ("Service.qml", "safe-art", "path"): "a path in the plugin's art cache",
    ("Service.qml", "received-dismiss", "entry.path"): "a received file's path in Downloads",
    ("Service.qml", "uwsm-app", "Model.fileUri(path)"): "a file's path in the cache or in Downloads, as a URI",
    ("SmsService.qml", "open-file", "ev.path"): "a picture's path in the plugin's sandboxed-preview cache",
    ("SmsService.qml", "open-file", "files[j].thumb"): "a picture's path in the plugin's sandboxed-preview cache",
    # contacts and the app's store pages
    ("ContactsService.qml", "contact-open", "kind"): "mail, map or web",
    ("SetupChecks.qml", "qrencode", "modelData.url"): "an app's store page (Model.APP_LINKS)",
    ("SetupChecks.qml", "", "parent.modelData.url"): "an app's store page (Model.APP_LINKS)",
    # the on-screen display
    ("Service.qml", "omarchy-osd", "Model.deviceGlyph(device)"): "a glyph, the device's icon or an alert",
    ("Service.qml", "omarchy-osd", "text"): "the toast's text, which can carry a device-sent name (a received file's, an app's); to be cut by SCE-617",
}


# ---- reading QML ------------------------------------------------------------

def read(path):
    with open(path) as f:
        return f.read()


def strip_comments(text):
    """The text without comments; strings kept."""
    out, i, n = [], 0, len(text)
    while i < n:
        c = text[i]
        if text.startswith("//", i):
            j = text.find("\n", i)
            i = n if j < 0 else j
        elif text.startswith("/*", i):
            j = text.find("*/", i + 2)
            i = n if j < 0 else j + 2
            out.append(" ")
        elif c in "\"'`":
            j = i + 1
            while j < n and text[j] != c:
                j += 2 if text[j] == "\\" else 1
            out.append(text[i:j + 1]); i = j + 1
        else:
            out.append(c); i += 1
    return "".join(out)


OPEN, CLOSE = "([{", ")]}"


def scan(text, start=0):
    """Yield (index, char, depth) for every character outside a string, where
    depth is the nesting of ([{ before the character."""
    depth, i, n = 0, start, len(text)
    while i < n:
        c = text[i]
        if c in "\"'`":
            j = i + 1
            while j < n and text[j] != c:
                j += 2 if text[j] == "\\" else 1
            i = j + 1
            continue
        if c in CLOSE:
            depth -= 1
        yield i, c, depth
        if c in OPEN:
            depth += 1
        i += 1


def close_of(text, open_at):
    """The index of the bracket closing the one at open_at."""
    for i, c, depth in scan(text, open_at):
        if depth == 0 and c in CLOSE and i > open_at:
            return i
    return len(text)


def split_top(text, sep=","):
    """Split at separators outside every bracket and string."""
    parts, last = [], 0
    for i, c, depth in scan(text):
        if depth == 0 and text.startswith(sep, i):
            parts.append(text[last:i]); last = i + len(sep)
    parts.append(text[last:])
    return [p.strip() for p in parts]


CONTINUES = re.compile(r"(?:[?:,+\-*/&|=(\[{.])\s*$")


def expression_at(text, start):
    """The expression beginning at start: up to a `;`, a `,` or a closing
    bracket outside brackets, or a line end the next line does not continue."""
    for i, c, depth in scan(text, start):
        if depth < 0:
            return text[start:i]
        if depth == 0 and c in ";,":
            return text[start:i]
        if depth == 0 and c == "\n":
            rest = text[i + 1:].lstrip()
            if not CONTINUES.search(text[start:i]) and not re.match(r"[?:.]|&&|\|\||\+", rest):
                return text[start:i]
    return text[start:]


def line_of(text, index):
    return text.count("\n", 0, index) + 1


def is_literal(element):
    return bool(re.fullmatch(r"\"(?:[^\"\\]|\\.)*\"|'(?:[^'\\]|\\.)*'|-?\d+(?:\.\d+)?", element))


def literal_text(element):
    return element[1:-1] if element[:1] in "\"'" else element


def top_level(text, ch):
    """Index of the first `ch` outside brackets and strings, or -1."""
    for i, c, depth in scan(text):
        if depth == 0 and c == ch:
            return i
    return -1


def ternary(text):
    """(condition, yes, no) of a top-level `c ? a : b`, else None."""
    q = top_level(text, "?")
    if q < 0:
        return None
    nest = 0
    for i, c, depth in scan(text, q + 1):
        if depth != 0:
            continue
        if c == "?":
            nest += 1
        elif c == ":":
            if nest == 0:
                return text[:q], text[q + 1:i], text[i + 1:]
            nest -= 1
    return None


def definitions(text, name):
    """Every expression assigned to `name` or pushed or concatenated onto it
    in the file (the scope is the file: more than the real one, never fewer)."""
    found = []
    word = re.escape(name)
    for m in re.finditer(r"(?<![\w.])(?:(?:var|let|const)\s+)?%s\s*=(?!=)\s*" % word, text):
        found.append(("set", expression_at(text, m.end()).strip()))
    for m in re.finditer(r"(?<![\w.])%s\.push\(" % word, text):
        inner = text[m.end():close_of(text, m.end() - 1)]
        found.extend(("push", e) for e in split_top(inner) if e)
    for m in re.finditer(r"(?<![\w.])%s\.concat\(" % word, text):
        inner = text[m.end():close_of(text, m.end() - 1)]
        found.append(("set", inner.strip()))
    return found


# Function parameters that carry argv built by the function's callers; the callers are
# sinks of their own (`launch(` and `run(` in sinks()), so the parameter is not an element.
PARAMETERS = {("ContactsService.qml", "launch", "args"), ("Service.qml", "run", "args"),
              ("Service.qml", "run", "verb"), ("Service.qml", "runOn", "verb")}


def elements(text, expr, path, seen=None, fn=""):
    """The elements of the argv an expression builds, as normalized strings."""
    seen = set() if seen is None else seen
    expr = expr.strip()
    while expr.startswith("(") and close_of(expr, 0) == len(expr) - 1:
        expr = expr[1:-1].strip()
    if not expr:
        return []
    t = ternary(expr)
    if t:
        return elements(text, t[1], path, seen, fn) + elements(text, t[2], path, seen, fn)
    for op in ("||", "&&"):
        if len(split_top(expr, op)) > 1:
            return [e for part in split_top(expr, op) for e in elements(text, part, path, seen, fn)]
    m = re.fullmatch(r"(.*)\.concat\((.*)\)", expr, flags=re.S)
    if m and close_of(expr, expr.rindex(".concat(") + 7) == len(expr) - 1:
        return elements(text, m.group(1), path, seen, fn) + elements(text, m.group(2), path, seen, fn)
    if expr.startswith("[") and close_of(expr, 0) == len(expr) - 1:
        out = []
        for e in split_top(expr[1:-1]):
            if e:
                out.extend(element(text, e, path, seen, fn))
        return out
    if re.fullmatch(r"[A-Za-z_]\w*", expr):
        if (os.path.basename(path), fn, expr) in PARAMETERS:
            return []
        if expr in seen:
            return []
        seen.add(expr)
        found = definitions(text, expr)
        if not found:
            return [expr]
        out = []
        for kind, e in found:
            out.extend(elements(text, e, path, seen, fn) if kind == "set" else element(text, e, path, seen, fn))
        return out
    return [normal(expr)]


def element(text, e, path, seen, fn=""):
    """One element of an array: a literal, or through a ternary its branches."""
    e = e.strip()
    t = ternary(e)
    if t:
        return element(text, t[1], path, seen, fn) + element(text, t[2], path, seen, fn)
    if is_literal(e):
        return [e]
    if (os.path.basename(path), fn, e) in PARAMETERS:
        return []
    if e.startswith("[") and close_of(e, 0) == len(e) - 1:
        return elements(text, e, path, seen, fn)
    return [normal(e)]


def normal(expr):
    return re.sub(r"\s+", " ", expr).strip()


def function_bodies(text):
    """(start, end) of every function that is not inside another: the scope a
    variable of an argv is looked up in (the file, outside any function)."""
    bodies = []
    for m in re.finditer(r"\bfunction\b([^{;]*)\{", text):
        name = re.match(r"\s*(\w+)", m.group(1))
        bodies.append((m.end(), close_of(text, m.end() - 1), name.group(1) if name else ""))
    return [(a, b, n) for a, b, n in bodies if not any(c < a and b <= d for c, d, _ in bodies)]


def sinks(path):
    """(line, argv elements) for every process the file starts."""
    text = strip_comments(read(path))
    found = []

    ranges = function_bodies(text)

    def add(index, expr):
        a, b, fn = next(((a, b, n) for a, b, n in ranges if a <= index < b), (0, len(text), ""))
        found.append((line_of(text, index), elements(text[a:b], expr, path, fn=fn)))

    for m in re.finditer(r"(?<![\w.])command\s*:\s*|\.command\s*=(?!=)\s*", text):
        add(m.start(), expression_at(text, m.end()))
    for m in re.finditer(r"\b(?:execDetached|Quickshell\.exec)\(", text):
        inner = text[m.end():close_of(text, m.end() - 1)]
        first = split_top(inner)[0]
        if first.startswith("{"):
            c = re.search(r"\bcommand\s*:\s*", first)
            if c:
                first = expression_at(first, c.end())
        add(m.start(), first)
    for m in re.finditer(r"\bopenUrlExternally\(", text):
        add(m.start(), "[" + text[m.end():close_of(text, m.end() - 1)] + "]")
    # the helpers that pass an argv on
    for m in re.finditer(r"(?<![\w.])launch\(", text):
        if text[:m.start()].rstrip().endswith("function"):
            continue
        add(m.start(), split_top(text[m.end():close_of(text, m.end() - 1)])[0])
    for m in re.finditer(r"(?<![\w.])runOn\(", text):
        if text[:m.start()].rstrip().endswith("function"):
            continue
        args = split_top(text[m.end():close_of(text, m.end() - 1)])
        if len(args) >= 2:
            add(m.start(), "[%s]" % args[1])
    for m in re.finditer(r"(?<![\w])(?:\w+\.)?run\(", text):
        if text[:m.start()].rstrip().endswith("function"):
            continue
        args = split_top(text[m.end():close_of(text, m.end() - 1)])
        if len(args) >= 2 and (args[0][:1] in "\"'" or args[1].startswith("[")):
            add(m.start(), "[%s].concat(%s)" % (args[0], args[1]))
    return found


def violations(path, allowed=None):
    allowed = ARGV_ALLOWED if allowed is None else allowed
    name = os.path.basename(path)
    out = []
    for line, els in sinks(path):
        verb = next((literal_text(e) for e in els if is_literal(e) and not e.startswith("-")), "")
        for e in els:
            if is_literal(e):
                continue
            if (name, verb, e) in allowed or (name, "*", e) in allowed:
                continue
            out.append("%s:%d: `%s` is on a command line (verb \"%s\") and is not in ARGV_ALLOWED" % (name, line, e, verb))
    return out


def qml_files():
    return sorted(glob.glob(os.path.join(ROOT, "*.qml")))


class PrivateTextOnArgv(unittest.TestCase):
    def test_every_argv_element_is_a_literal_or_reviewed(self):
        found = [v for f in qml_files() for v in violations(f)]
        self.assertEqual(found, [], "\n" + "\n".join(found))

    def test_every_allowed_expression_is_still_used(self):
        used = set()
        for f in qml_files():
            name = os.path.basename(f)
            for _, els in sinks(f):
                verb = next((literal_text(e) for e in els if is_literal(e) and not e.startswith("-")), "")
                used.update((name, verb, e) for e in els if not is_literal(e))
                used.update((name, "*", e) for e in els if not is_literal(e))
        stale = sorted(k for k in ARGV_ALLOWED if k not in used)
        self.assertEqual(stale, [], "taken out of the code, take out of ARGV_ALLOWED")

    def test_every_allowed_expression_says_why(self):
        for key, why in ARGV_ALLOWED.items():
            self.assertGreater(len(why.split()), 2, key)

    def test_the_sinks_are_found(self):
        total = sum(len(sinks(f)) for f in qml_files())
        self.assertGreater(total, 60, "the scan reads too few places that start a process")

    def test_the_check_finds_them(self):
        demo = (
            'Item {\n'
            '  function a(m) { run("share-text", [device, m], "x") }\n'
            '  function b(t) { Quickshell.execDetached(["notify-send", t.title, t.body]) }\n'
            '  Process { command: ["tool", label] }\n'
            '  function c(note) { var cmd = [bridge, "fix"]; cmd.push("--note", note); proc.command = cmd }\n'
            '  function d(q) { launch(["contacts-app"].concat(q !== "" ? ["--find", q] : []), q) }\n'
            '  function e(p) { actionComponent.createObject(root, { key: "k", command: [bridge, "open-file", String(p)] }) }\n'
            '  function f(u) { Qt.openUrlExternally(u) }\n'
            '  function g(s) { Quickshell.execDetached({ command: ["tool", s] }) }\n'
            '  function h(s) { var cmd = flag ? [bridge, "x"] : [bridge, "y", s]; proc.command = cmd }\n'
            '  function i(v) { run(v, [], "k") }\n'
            '  property var ok: ["fixed", "literal", 3]\n'
            '  Process { command: ["wl-copy"] }\n'
            '}\n')
        with tempfile.NamedTemporaryFile("w", suffix=".qml", delete=False) as f:
            f.write(demo)
        try:
            found = " ".join(violations(f.name, allowed={}))
            for text in ("`device`", "`m`", "`t.title`", "`t.body`", "`label`", "`note`", "`q`",
                         "`String(p)`", "`u`", "`s`", "`bridge`", "`v`"):
                self.assertIn(text, found, text)
            self.assertNotIn("wl-copy", found)
            # an allowed expression passes, and only for its own verb
            ok = violations(f.name, allowed={(os.path.basename(f.name), "tool", "label"): "a fixed title"})
            self.assertNotIn("`label`", " ".join(ok))
            self.assertIn("`s`", " ".join(ok))
            other = violations(f.name, allowed={(os.path.basename(f.name), "other", "label"): "a fixed title"})
            self.assertIn("`label`", " ".join(other))
        finally:
            os.remove(f.name)

    def test_a_new_expression_in_the_real_files_fails(self):
        # The two cases that escaped the five-verb check: a new verb carrying
        # text, and a process that is not the bridge.
        with tempfile.TemporaryDirectory() as d:
            for name in ("Service.qml", "SmsService.qml"):
                shutil.copy(os.path.join(ROOT, name), os.path.join(d, name))
            self.assertEqual(violations(os.path.join(d, "Service.qml")), [])
            with open(os.path.join(d, "Service.qml"), "a") as f:
                f.write('\nItem {\n  function a(m) { run("share-text", [device, m], "x") }\n'
                        '  function b(t) { Quickshell.execDetached(["notify-send", t.title, t.body]) }\n}\n')
            found = " ".join(violations(os.path.join(d, "Service.qml")))
            for text in ("`device`", "`m`", "`t.title`", "`t.body`"):
                self.assertIn(text, found, text)


# ---- C2 ---------------------------------------------------------------------

# Types that read the clipboard by themselves. The Omarchy ones are also found
# by reading its Ui folder when it exists, so a new wrapper is caught on this
# computer; CI has no Omarchy, so the known ones are named here.
TEXT_INPUT_BASES = ("TextInput", "TextField", "TextArea")
KNOWN_WRAPPERS = ("NumberField", "MultiSelect", "SearchableDropdown", "TextField")


def omarchy_text_types(folder=OMARCHY_UI):
    """Types of Omarchy's Ui folder that contain a text input, or another such
    type, in code (not in a comment)."""
    if not os.path.isdir(folder):
        return set()
    bodies = {os.path.basename(p)[:-4]: strip_comments(read(p))
              for p in glob.glob(os.path.join(folder, "*.qml"))}
    bad = set(TEXT_INPUT_BASES)
    changed = True
    while changed:
        changed = False
        for name, text in bodies.items():
            if name not in bad and any(re.search(r"\b%s\s*\{" % b, text) for b in bad):
                bad.add(name); changed = True
    return {n for n in bodies if n in bad}


def forbidden_types():
    return set(TEXT_INPUT_BASES) | set(KNOWN_WRAPPERS) | omarchy_text_types()


def text_input_uses(path, types=None):
    types = forbidden_types() if types is None else types
    text = strip_comments(read(path))
    return ["%s:%d: %s reads the clipboard by itself; use PanelField" % (
        os.path.basename(path), line_of(text, m.start()), m.group(1))
        for m in re.finditer(r"(?<![\w.])(%s)\s*\{" % "|".join(sorted(types)), text)]


def clipboard_reads(path):
    text = strip_comments(read(path))
    return [line_of(text, m.start()) for m in re.finditer(r"\bclipboardText\b", text)]


NO_PASTE_TOOLS = re.compile(r"\b(?:wl-paste|cliphist)\b")


def paste_tools(path):
    text = strip_comments(read(path))
    if not path.endswith(".qml") and not path.endswith(".js"):
        text = re.sub(r"(?m)^\s*#.*$", "", text)
    return [line_of(text, m.start()) for m in NO_PASTE_TOOLS.finditer(text)]


class ClipboardOnlyOnPaste(unittest.TestCase):
    def test_no_type_that_reads_the_clipboard_by_itself(self):
        found = [u for f in qml_files() for u in text_input_uses(f)]
        self.assertEqual(found, [], "\n" + "\n".join(found))

    def test_the_text_inputs_of_the_installed_omarchy_are_known(self):
        # Every Ui type with a text input in it is forbidden whether or not
        # this list knows it; the list is what CI, without Omarchy, checks.
        missing = omarchy_text_types() - set(TEXT_INPUT_BASES) - set(KNOWN_WRAPPERS)
        used = [f for f in qml_files() for t in missing if re.search(r"(?<![\w.])%s\s*\{" % t, strip_comments(read(f)))]
        self.assertEqual(used, [], "a text input of Omarchy's Ui is used")
        self.assertEqual(sorted(missing), [], "add to KNOWN_WRAPPERS so CI knows them too")

    def test_clipboard_text_is_read_once_in_panelfield(self):
        reads = {os.path.basename(f): clipboard_reads(f) for f in qml_files()}
        reads = {k: v for k, v in reads.items() if v}
        self.assertEqual(list(reads), ["PanelField.qml"], reads)
        self.assertEqual(len(reads["PanelField.qml"]), 1)

    def test_no_paste_tool_where_the_plugin_runs_code(self):
        files = qml_files() + [os.path.join(ROOT, "Model.js")] + [
            p for p in glob.glob(os.path.join(ROOT, "bin", "*")) if os.path.isfile(p)]
        found = ["%s:%d" % (os.path.basename(f), n) for f in files for n in paste_tools(f)]
        self.assertEqual(found, [], "wl-paste / cliphist read the clipboard without a paste")

    def test_the_check_finds_them(self):
        with tempfile.TemporaryDirectory() as d:
            def write(name, text):
                p = os.path.join(d, name)
                with open(p, "w") as f:
                    f.write(text)
                return p
            numbers = write("A.qml", "Item {\n  NumberField { }\n  SearchableDropdown { }\n  MultiSelect {}\n  TextField {}\n"
                                     "  TextInput {}\n  TextArea {}\n  // TextField { in a comment }\n  PanelField { }\n}\n")
            self.assertEqual(len(text_input_uses(numbers)), 6, text_input_uses(numbers))
            self.assertEqual(clipboard_reads(write("B.qml", "Item { onX: y = Quickshell.clipboardText }\n")), [1])
            self.assertEqual(clipboard_reads(write("C.qml", "Item { // clipboardText\n }\n")), [])
            self.assertEqual(paste_tools(write("D.qml", 'Process { command: ["wl-paste"] }\n// cliphist\n')), [1])
            self.assertEqual(paste_tools(write("tool", "subprocess.run(['cliphist', 'list'])\n# wl-paste\n")), [1])
            # a wrapper of Omarchy's found by reading its folder, one level through another
            ui = os.path.join(d, "Ui"); os.mkdir(ui)
            write("Ui/Plain.qml", "Item { }\n")
            write("Ui/Edit.qml", "Item { TextInput { } }\n")
            write("Ui/Wrapped.qml", "Item { Edit { } }\n")
            write("Ui/Comment.qml", "Item { // TextField {\n }\n")
            self.assertEqual(omarchy_text_types(ui), {"Edit", "Wrapped"} | set(), omarchy_text_types(ui))


if __name__ == "__main__":
    unittest.main()
