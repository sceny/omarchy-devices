"""Four classes of fault, held at the sink and not at the case that was reported.
Each lint fails the build naming file:line, and each shows it fails on a
planted case (a fixture the lint is run on) as well as passing on the tree.

L1, private text in a log. A log, a `print` to stderr, a bridge `say` and a
QML `console.*` write somewhere a person or a log collector reads. No argument
of one names a private field (a message's body, a contact, a number, the
clipboard's text); only its length may be written. A name a reviewer has read
and found not private is in LOG_ALLOWED with the reason.

L2, an image the shell decodes from a path the device chose. A QML `Image`'s
`source` is only a handle the bridge wrote after decoding in a sandbox
(IMAGE_SOURCES), and the bridge writes those handles only in the functions it
names (IMAGE_DECODERS).

L3, root. `pkexec` is in one bridge function (`as_root`) and nowhere else;
only `root_plan` builds a command with it; only `run_root` runs the plan, after
the --confirm hash equals the plan's own.

L4, listeners and shells. The bridge binds, listens and serves nothing, and
starts no shell on a script it built from anything but literals, except the
functions in SHELL_ALLOWED (with why)."""

import ast
import glob
import importlib.machinery
import importlib.util
import os
import re
import sys
import tempfile
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.join(HERE, "..")
BRIDGE = os.path.join(ROOT, "bin", "kdeconnect-bridge")
sys.path.insert(0, HERE)

from test_qml import call_args, code_only  # noqa: E402


def load_bridge():
    loader = importlib.machinery.SourceFileLoader("kdeconnect_bridge_lints", BRIDGE)
    spec = importlib.util.spec_from_loader("kdeconnect_bridge_lints", loader)
    module = importlib.util.module_from_spec(spec)
    loader.exec_module(module)
    return module


def qml_files():
    return sorted(glob.glob(os.path.join(ROOT, "*.qml")))


def read(path):
    with open(path) as f:
        return f.read()


def line_of(text, index):
    return text.count("\n", 0, index) + 1


class Planted:
    """A file with the given text, removed afterwards."""

    def __init__(self, text, suffix=".qml"):
        self.text, self.suffix = text, suffix

    def __enter__(self):
        f = tempfile.NamedTemporaryFile("w", suffix=self.suffix, delete=False)
        f.write(self.text)
        f.close()
        self.path = f.name
        return f.name

    def __exit__(self, *exc):
        os.remove(self.path)


def functions_of(tree):
    """{node: name of the function it is in ("" at module level)}."""
    where = {}

    def visit(node, name):
        for child in ast.iter_child_nodes(node):
            inner = child.name if isinstance(child, (ast.FunctionDef, ast.AsyncFunctionDef)) else name
            where[child] = inner
            visit(child, inner)
    visit(tree, "")
    return where


def parse(path):
    with open(path) as f:
        return ast.parse(f.read()), os.path.basename(path)


# ---- L1: logs -----------------------------------------------------------------

PRIVATE_TOKENS = {"body", "text", "clipboard", "contact", "contacts", "number", "numbers", "phone",
                  "digits", "sender", "subject", "draft", "snippet", "caption", "addresses",
                  "content", "query", "recipient"}
LOG_LEVELS = {"debug", "info", "warning", "warn", "error", "exception", "critical", "log"}

# (file, function, field) -> why that field is not private text there.
LOG_ALLOWED = {}


def tokens(name):
    return {t.lower() for t in re.findall(r"[A-Z]?[a-z0-9]+|[A-Z]+(?![a-z])", name)}


def private(name):
    return bool(tokens(name) & PRIVATE_TOKENS)


def named_fields(node):
    """The names a Python expression reads, its calls' own names left out and
    `len(...)` not looked into (only a length is written)."""
    out = []

    def visit(n):
        if isinstance(n, ast.Call):
            f = n.func
            if isinstance(f, ast.Name) and f.id == "len":
                return
            if isinstance(f, ast.Attribute):
                visit(f.value)
                if f.attr == "get" and n.args and isinstance(n.args[0], ast.Constant) and isinstance(n.args[0].value, str):
                    out.append(n.args[0].value)
            elif not isinstance(f, ast.Name):
                visit(f)
            for a in n.args:
                visit(a)
            for k in n.keywords:
                visit(k.value)
            return
        if isinstance(n, ast.Name):
            out.append(n.id)
        elif isinstance(n, ast.Attribute):
            out.append(n.attr)
        elif isinstance(n, ast.Subscript):
            s = n.slice
            if isinstance(s, ast.Constant) and isinstance(s.value, str):
                out.append(s.value)
        for c in ast.iter_child_nodes(n):
            visit(c)
    visit(node)
    return out


def is_log_sink(call):
    f = ast.unparse(call.func)
    if f == "say" or f.endswith("stderr.write"):
        return True
    if f == "print":
        return any(k.arg == "file" and "stderr" in ast.unparse(k.value) for k in call.keywords)
    parts = f.split(".")
    return len(parts) == 2 and parts[0] in ("logging", "logger", "log", "LOG") and parts[1] in LOG_LEVELS


def python_log_leaks(path, allowed=None, used=None):
    tree, name = parse(path)
    allowed = LOG_ALLOWED if allowed is None else allowed
    where = functions_of(tree)
    found = []
    for node in ast.walk(tree):
        if isinstance(node, ast.Call) and is_log_sink(node):
            for arg in list(node.args) + [k.value for k in node.keywords]:
                for field in named_fields(arg):
                    if not private(field):
                        continue
                    key = (name, where.get(node, ""), field)
                    if key in allowed:
                        if used is not None:
                            used.add(key)
                        continue
                    found.append("%s:%d: %s writes %r, a private field" % (name, node.lineno, ast.unparse(node.func), field))
    return found


QML_LOG = re.compile(r"\b(?:console\s*\.\s*(?:log|info|warn|error|debug|trace)|print)\s*\(")
LENGTH = re.compile(r"(?:String\(\s*[\w.]+\s*\)|[\w.]+)\.length\b")


def qml_log_leaks(path):
    raw = read(path)
    text = code_only(raw)
    name = os.path.basename(path)
    found = []
    for m in QML_LOG.finditer(text):
        args = LENGTH.sub("", " ".join(call_args(text, m.end() - 1)))
        for ident in re.findall(r"[A-Za-z_]\w*", args):
            if private(ident):
                found.append("%s:%d: %s writes %r, a private field" % (name, line_of(raw, m.start()), m.group(0).rstrip("( "), ident))
    return found


class LogsCarryNoPrivateText(unittest.TestCase):
    def test_the_bridge_logs_no_private_field(self):
        found = python_log_leaks(BRIDGE)
        self.assertEqual(found, [], "\n".join(found))

    def test_qml_logs_no_private_field(self):
        found = [p for f in qml_files() for p in qml_log_leaks(f)]
        self.assertEqual(found, [], "\n".join(found))

    def test_every_allowed_field_is_still_used(self):
        used = set()
        python_log_leaks(BRIDGE, used=used)
        self.assertEqual(sorted(set(LOG_ALLOWED) - used), [], "remove the entries nothing uses")

    def test_an_allowed_field_passes_and_a_stale_one_is_found(self):
        with Planted('def f(body):\n    say(body)\n', ".py") as path:
            name = os.path.basename(path)
            used = set()
            self.assertEqual(python_log_leaks(path, allowed={(name, "f", "body"): "reviewed: a length"}, used=used), [])
            self.assertEqual(used, {(name, "f", "body")})

    def test_every_allowed_field_says_why(self):
        self.assertTrue(all(len(why) > 10 for why in LOG_ALLOWED.values()))

    def test_the_check_finds_a_planted_leak_in_the_bridge(self):
        cases = ['say("sent %s" % body)\n',
                 'import sys\nprint(number, file=sys.stderr)\n',
                 'import sys\nsys.stderr.write(msg["text"])\n',
                 'import logging\nlogging.warning("x %s", contact_name)\n',
                 'say(f"to {thread.sender}")\n',
                 'say(clipboard.strip())\n',
                 'import sys\nprint(item.get("addresses"), file=sys.stderr)\n']
        for src in cases:
            with Planted(src, ".py") as path:
                self.assertEqual(len(python_log_leaks(path, allowed={})), 1, src)

    def test_the_check_passes_what_is_not_a_leak(self):
        cases = ['say("Done")\n', 'say("n %d" % len(body))\n', 'print(json.dumps({"body": body}))\n',
                 'say(error.message, 1)\n', 'say(cap_text(x))\n']
        for src in cases:
            with Planted(src, ".py") as path:
                self.assertEqual(python_log_leaks(path, allowed={}), [], src)

    def test_the_check_finds_a_planted_leak_in_qml(self):
        cases = ['Item { Component.onCompleted: console.warn("x " + msg.body) }\n',
                 'Item { function f() { console.log(contact.name, contactName) } }\n',
                 'Item { function f(text) { console.info("t: " + text) } }\n',
                 'Item { function f() { print(Clipboard.last) ; print(draft) } }\n']
        expected = [1, 2, 1, 2]
        for src, n in zip(cases, expected):
            with Planted(src) as path:
                self.assertEqual(len(qml_log_leaks(path)), n, src)

    def test_the_check_passes_a_length_and_a_string(self):
        src = 'Item { function f(text) { console.warn("unreadable, " + String(text).length + " characters, body skipped") } }\n'
        with Planted(src) as path:
            self.assertEqual(qml_log_leaks(path), [])

    def test_a_planted_leak_in_the_real_bridge_fails(self):
        with open(BRIDGE) as f:
            src = f.read() + '\n\ndef planted(body):\n    say("x %s" % body)\n'
        with Planted(src, ".py") as path:
            found = python_log_leaks(path)
        self.assertEqual(len(found), 1, found)
        self.assertRegex(found[0], r"^[\w.-]+:\d+: ")


# ---- L2: images ---------------------------------------------------------------

# (file, source expression) -> the safe place it reads from. The bridge decodes
# in a sandbox and writes the handle; the shell never points at a device's file.
IMAGE_SOURCES = {
    ("FoldToggle.qml", "fold.thumb"): "the section's cover: Panel passes a track's art through the bridge's safe copy (safe-art)",
    ("ContactsView.qml", 'face.photo !== "" ? "file://" + encodeURI(face.photo) : ""'): "a contact's photo: the bridge's decoded copy in the contacts cache (contact_photo)",
    ("ContactsView.qml", 'rowFace.photo !== "" ? "file://" + encodeURI(rowFace.photo) : ""'): "a contact's photo: the bridge's decoded copy in the contacts cache (contact_photo)",
    ("AppTile.qml", 'tile.hasIcon ? "file://" + tile.app.icon : ""'): "an app's icon: drawn and decoded by the bridge into apps-<device>/",
    ("MessagesView.qml", 'file.hasPreview ? "file://" + file.modelData.thumb : ""'): "a picture message's preview: the bridge's sms/preview_* file",
    ("ScreenTurn.qml", 'turn.turning ? "" : turn.oldStill'): "a still of this computer's own screen, in $XDG_RUNTIME_DIR/sceny.devices/",
    ("ScreenTurn.qml", "turn.oldStill"): "a still of this computer's own screen, in $XDG_RUNTIME_DIR/sceny.devices/",
    ("ScreenTurn.qml", 'turn.turning ? "" : turn.newStill'): "a still of this computer's own screen, in $XDG_RUNTIME_DIR/sceny.devices/",
    ("ScreenTurn.qml", "turn.newStill"): "a still of this computer's own screen, in $XDG_RUNTIME_DIR/sceny.devices/",
    ("Panel.qml", 'tile.photo.thumb ? "file://" + encodeURI(tile.photo.thumb) : ""'): "a gallery thumbnail: the bridge's sandboxed copy in safe/",
    ("Panel.qml", 'rrow.entry.preview ? "file://" + encodeURI(rrow.entry.preview) : ""'): "a received picture's preview: the bridge's sandboxed copy",
    ("Panel.qml", 'root.phone ? root.phone.artFor(card.artUrl) : ""'): "a track's art: only the bridge's safe copy (artFor)",
    ("Panel.qml", 'row.note.icon ? "file://" + row.note.icon : ""'): "a notification's icon: safe_image's decoded copy",
    ("Panel.qml", '""'): "no picture at all: the source is cleared",
    ("Panel.qml", "result.url"): "a still of this computer's own screen (grim), in $XDG_RUNTIME_DIR/sceny.devices/",
}

RAW_ENDINGS = ("path", "uri", "file", "filename", "name", "attachment", "raw", "src")

# The bridge functions that write a handle QML draws, and the decoder each
# calls. Decoders end in fit_image (GdkPixbuf through glycin: bubblewrap and a
# syscall filter per decode) or make_thumb (ffmpegthumbnailer in our own
# bubblewrap).
IMAGE_DECODERS = {
    "read_notifications": "safe_image",
    "watch": "safe_image",
    "photos": "make_thumb",
    "attachment": "fit_image",
    "read_app_icon": "fit_image",
    "contacts_list": "contact_photo",
    "contact_photo": "fit_image",
    "safe_image": "fit_image",
    "safe_art": "safe_image",
    "prepare_outgoing": "fit_image",
}

IMAGE_TYPE = re.compile(r"\b(?:Image|AnimatedImage|BorderImage|IconImage)\s*\{")


def object_at(text, brace):
    depth = 0
    for i in range(brace, len(text)):
        if text[i] == "{":
            depth += 1
        elif text[i] == "}":
            depth -= 1
            if depth == 0:
                return i
    return len(text)


def expression_after(raw, start):
    """The binding's expression from `start`: to the end of its line, further
    while a bracket is open or the line ends in an operator."""
    i, depth = start, 0
    while i < len(raw):
        c = raw[i]
        if c in "([{":
            depth += 1
        elif c in ")]}":
            depth -= 1
        elif c == "\n" and depth <= 0:
            line_end = raw[start:i].rstrip()
            if not re.search(r"[?:+\-*/&|,]$", line_end):
                return " ".join(raw[start:i].split())
        i += 1
    return " ".join(raw[start:].split())


def image_sources(path):
    """[(line, expression)] of every `source:` of an Image and every
    `<id>.source = ...` in a QML file."""
    raw = read(path)
    text = code_only(raw)
    found = []
    for m in IMAGE_TYPE.finditer(text):
        end = object_at(text, m.end() - 1)
        body = text[m.end():end]
        depth = 0
        ids = re.findall(r"\bid\s*:\s*(\w+)", body)
        for s in re.finditer(r"[{}]|\bsource\s*:", body):
            if s.group(0) == "{":
                depth += 1
            elif s.group(0) == "}":
                depth -= 1
            elif depth == 0:
                at = m.end() + s.end()
                found.append((line_of(raw, at), expression_after(raw, at).strip()))
        for ident in ids:
            for a in re.finditer(r"\b%s\s*\.\s*source\s*=(?!=)\s*" % re.escape(ident), text):
                found.append((line_of(raw, a.end()), expression_after(raw, a.end()).rstrip(";").strip()))
    return sorted(set(found))


def pageStill_assignments(path):
    """`<id>.source = ...` for an Image declared in another object of the file
    (ids are file-wide in QML): found through the ids of every Image."""
    raw = read(path)
    text = code_only(raw)
    ids = set()
    for m in IMAGE_TYPE.finditer(text):
        end = object_at(text, m.end() - 1)
        ids |= set(re.findall(r"\bid\s*:\s*(\w+)", text[m.end():end]))
    found = []
    for ident in ids:
        for a in re.finditer(r"\b%s\s*\.\s*source\s*=(?!=)\s*" % re.escape(ident), text):
            found.append((line_of(raw, a.end()), expression_after(raw, a.end()).rstrip(";").strip()))
    return found


def all_image_sources(path):
    inline = {(l, e) for l, e in image_sources(path)}
    return sorted(inline | set(pageStill_assignments(path)))


def image_violations(path, allowed=None, used=None):
    allowed = IMAGE_SOURCES if allowed is None else allowed
    name = os.path.basename(path)
    found = []
    for line, expr in all_image_sources(path):
        if (name, expr) in allowed:
            if used is not None:
                used.add((name, expr))
            continue
        found.append("%s:%d: Image source %r is not a reviewed safe handle" % (name, line, expr))
    return found


def function_calls(tree, fname):
    """The names called inside every function called fname (a method too)."""
    out, seen = set(), False
    for node in ast.walk(tree):
        if isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef)) and node.name == fname:
            seen = True
            for c in ast.walk(node):
                if isinstance(c, ast.Call):
                    f = c.func
                    out.add(f.id if isinstance(f, ast.Name) else f.attr if isinstance(f, ast.Attribute) else "")
    return out if seen else None


def decoder_problems(source, decoders=None, name="kdeconnect-bridge"):
    tree = ast.parse(source)
    decoders = IMAGE_DECODERS if decoders is None else decoders
    found = []
    for fn, decoder in sorted(decoders.items()):
        calls = function_calls(tree, fn)
        if calls is None:
            found.append("%s:1: %s writes a picture handle and is gone: update IMAGE_DECODERS" % (name, fn))
        elif decoder not in calls:
            found.append("%s:1: %s does not call %s: a picture handle that skips the sandboxed decoder" % (name, fn, decoder))
    glycin = [n for n in ast.walk(tree) if isinstance(n, ast.FunctionDef) and n.name == "fit_image"]
    if not glycin or "glycin" not in ast.get_source_segment(source, glycin[0]):
        found.append("%s:1: fit_image no longer decodes through glycin" % name)
    return found


class ImagesOnlyFromSafePaths(unittest.TestCase):
    def test_every_image_source_is_a_reviewed_safe_handle(self):
        found = [p for f in qml_files() for p in image_violations(f)]
        self.assertEqual(found, [], "\n".join(found))

    def test_every_allowed_source_is_still_used(self):
        used = set()
        for f in qml_files():
            image_violations(f, used=used)
        self.assertEqual(sorted(set(IMAGE_SOURCES) - used), [], "remove the entries nothing uses")

    def test_every_allowed_source_says_where_it_reads_from(self):
        self.assertTrue(all(len(why) > 10 for why in IMAGE_SOURCES.values()))

    def test_no_allowed_source_is_a_raw_device_field(self):
        for (name, expr) in IMAGE_SOURCES:
            for chain in re.findall(r"[A-Za-z_][\w.]*", re.sub(r'"[^"]*"', "", expr)):
                last = chain.split(".")[-1]
                if chain in ("encodeURI", "Qt.resolvedUrl"):
                    continue
                self.assertNotIn(last.lower(), RAW_ENDINGS, "%s: %s reads a raw path or url" % (name, expr))

    def test_every_handle_is_written_through_a_sandboxed_decoder(self):
        with open(BRIDGE) as f:
            found = decoder_problems(f.read())
        self.assertEqual(found, [], "\n".join(found))

    def test_the_check_finds_a_raw_source(self):
        cases = ['Item { Image { source: "file://" + attachment.path } }\n',
                 'Item { Image { id: pic\n source: root.deviceFile } }\n',
                 'Item { AnimatedImage { source: msg.url } }\n',
                 'Item { Image { id: pic }\n function f(p) { pic.source = "file://" + p } }\n',
                 'Item { Image { source: ok\n ? "file://" + a.thumb\n : "" } }\n']
        for src in cases:
            with Planted(src) as path:
                self.assertEqual(len(image_violations(path, allowed={})), 1, (src, image_violations(path, allowed={})))

    def test_the_check_passes_what_is_reviewed(self):
        src = 'Item { Image {\n source: tile.photo.thumb ? "file://" + encodeURI(tile.photo.thumb) : ""\n sourceSize.width: 4 } }\n'
        with Planted(src) as path:
            name = os.path.basename(path)
            self.assertEqual(image_violations(path, allowed={(name, 'tile.photo.thumb ? "file://" + encodeURI(tile.photo.thumb) : ""'): "x"}), [])

    def test_a_planted_raw_source_in_the_real_files_fails(self):
        with open(os.path.join(ROOT, "AppTile.qml")) as f:
            src = f.read().replace('source: tile.hasIcon ? "file://" + tile.app.icon : ""', 'source: "file://" + tile.app.path')
        with Planted(src) as path:
            reviewed = {(os.path.basename(path), k[1]): v for k, v in IMAGE_SOURCES.items() if k[0] == "AppTile.qml"}
            found = image_violations(path, allowed=reviewed)
        self.assertEqual(len(found), 1, found)
        self.assertIn("tile.app.path", found[0])

    def test_a_producer_that_skips_its_decoder_is_found(self):
        with open(BRIDGE) as f:
            src = f.read()
        skipped = src.replace("        ok = fit_image(src, dst, APP_ICON_BOX)", "        ok = shutil.copy(src, dst)", 1)
        self.assertNotEqual(skipped, src)
        found = decoder_problems(skipped)
        self.assertEqual(len(found), 1, found)
        self.assertIn("read_app_icon does not call fit_image", found[0])

    def test_a_producer_that_is_gone_is_found(self):
        self.assertEqual(len(decoder_problems("def other():\n    pass\n", {"x": "fit_image"})), 2)


# ---- L3: root -----------------------------------------------------------------

ROOT_PLANNERS = {"pkg_add", "root_plan"}
ROOT_RUNNER = "run_root"
SUBPROCESS_RUNNERS = {"run", "Popen", "call", "check_call", "check_output", "getoutput", "system", "popen", "execv", "execvp", "execve"}


def calls_of(tree):
    """[(callee name, enclosing function, node)] for every call by name."""
    where = functions_of(tree)
    out = []
    for node in ast.walk(tree):
        if isinstance(node, ast.Call):
            f = node.func
            callee = f.id if isinstance(f, ast.Name) else f.attr if isinstance(f, ast.Attribute) else ""
            out.append((callee, where.get(node, ""), node))
    return out


def is_pkexec(value):
    return isinstance(value, str) and os.path.basename(value) == "pkexec"


def root_problems(source, name="kdeconnect-bridge"):
    tree = ast.parse(source)
    where = functions_of(tree)
    found = []
    pk = sorted({(where.get(n, ""), n.lineno) for n in ast.walk(tree) if isinstance(n, ast.Constant) and is_pkexec(n.value)})
    homes = sorted({fn for fn, _ in pk})
    if len(homes) != 1 or homes[0] != "as_root":
        for fn, line in pk:
            if fn != "as_root":
                found.append("%s:%d: pkexec in %s, not only in as_root" % (name, line, fn or "the module"))
        if not homes:
            found.append("%s:1: no function holds pkexec: as_root is gone" % name)
    calls = calls_of(tree)
    for callee, fn, node in calls:
        if callee == "as_root" and fn not in ROOT_PLANNERS:
            found.append("%s:%d: as_root is called from %s; only %s build a root command" % (name, node.lineno, fn or "the module", "/".join(sorted(ROOT_PLANNERS))))
        if callee == "pkg_add" and fn != "root_plan":
            found.append("%s:%d: pkg_add is called from %s; only root_plan builds a root plan" % (name, node.lineno, fn or "the module"))
        if callee == "root_plan" and fn not in (ROOT_RUNNER, "main"):
            found.append("%s:%d: root_plan is called from %s; only run_root runs a plan (main describes one)" % (name, node.lineno, fn or "the module"))
        if callee == ROOT_RUNNER and fn != "fix":
            found.append("%s:%d: run_root is called from %s; only fix reaches it" % (name, node.lineno, fn or "the module"))
        if callee == "fix" and fn != "fix":
            if len(node.args) + len(node.keywords) < 2:
                found.append("%s:%d: fix is called without --confirm's value" % (name, node.lineno))
    for callee, fn, node in calls:
        if callee == ROOT_RUNNER and fn == "fix" and len(node.args) + len(node.keywords) < 2:
            found.append("%s:%d: fix reaches run_root without the confirm value" % (name, node.lineno))
    runner = next((n for n in ast.walk(tree) if isinstance(n, ast.FunctionDef) and n.name == ROOT_RUNNER), None)
    if runner is None:
        found.append("%s:1: run_root is gone" % name)
    else:
        gate = None
        for stmt in ast.walk(runner):
            if isinstance(stmt, ast.If):
                test = ast.unparse(stmt.test)
                if "confirm" in test and "hash" in test and any(isinstance(s, ast.Return) for s in stmt.body):
                    gate = stmt.lineno if gate is None else min(gate, stmt.lineno)
        runs = [n.lineno for n in ast.walk(runner) if isinstance(n, ast.Call)
                and (isinstance(n.func, ast.Attribute) and n.func.attr in SUBPROCESS_RUNNERS or isinstance(n.func, ast.Name) and n.func.id in SUBPROCESS_RUNNERS)]
        if gate is None:
            found.append("%s:%d: run_root does not return unless confirm equals the plan's hash" % (name, runner.lineno))
        for line in runs:
            if gate is None or line < gate:
                found.append("%s:%d: run_root starts a process before it checks the --confirm hash" % (name, line))
    return found


def root_text_problems(paths):
    found = []
    for path in paths:
        raw = read(path)
        for m in re.finditer(r"""["'][^"'\n]*pkexec[^"'\n]*["']""", raw):
            found.append("%s:%d: pkexec outside the bridge's as_root" % (os.path.basename(path), line_of(raw, m.start())))
    return found


class RootOnlyAsConfirmed(unittest.TestCase):
    def source(self):
        with open(BRIDGE) as f:
            return f.read()

    def test_the_bridge_reaches_root_only_through_the_confirmed_plan(self):
        found = root_problems(self.source())
        self.assertEqual(found, [], "\n".join(found))

    def test_nothing_else_names_pkexec(self):
        others = qml_files() + sorted(glob.glob(os.path.join(ROOT, "*.js"))) + sorted(glob.glob(os.path.join(ROOT, "dev", "*")))
        found = root_text_problems([p for p in others if os.path.isfile(p) and not p.endswith((".md", ".json"))
                                    and "sandbox" not in p])
        self.assertEqual(found, [], "\n".join(found))

    def test_the_gate_is_in_the_real_run_root(self):
        text = self.source()
        self.assertEqual(root_problems(text), [])
        loose = text.replace('if not confirm or confirm != plan["hash"]:', 'if False:')
        self.assertNotEqual(loose, text)
        self.assertTrue(any("does not return unless confirm" in p for p in root_problems(loose)))

    def test_a_wrong_or_missing_hash_starts_nothing_and_the_right_one_starts_pkexec(self):
        bridge = load_bridge()
        started = []

        class Done:
            returncode, stdout, stderr = 0, "", ""

        real = bridge.subprocess.run
        real_state, real_meshes = bridge.firewall_state, bridge.mesh_interfaces
        bridge.subprocess.run = lambda cmd, *a, **k: started.append(cmd) or Done() if cmd[0] == "pkexec" else real(cmd, *a, **k)
        bridge.firewall_state = lambda *a, **k: {"rules": []}
        bridge.mesh_interfaces = lambda *a, **k: []
        try:
            plan = bridge.root_plan("firewall")
            for confirm in ("", None, "0" * len(plan["hash"]), plan["hash"][:-1]):
                self.assertEqual(bridge.run_root("firewall", confirm), bridge.EXIT_FAILED, confirm)
            self.assertEqual(started, [])
            bridge.run_root("firewall", plan["hash"])
        finally:
            bridge.subprocess.run = real
            bridge.firewall_state, bridge.mesh_interfaces = real_state, real_meshes
        self.assertTrue(started and all(cmd[0] == "pkexec" for cmd in started), started)

    def test_the_check_finds_a_second_pkexec(self):
        text = self.source() + '\n\ndef planted():\n    return ["pkexec", "/bin/true"]\n'
        found = root_problems(text)
        self.assertEqual(len(found), 1, found)
        self.assertIn("pkexec in planted", found[0])

    def test_the_check_finds_a_new_caller_of_as_root(self):
        text = self.source() + '\n\ndef planted():\n    return as_root(["/bin/true"])\n'
        found = root_problems(text)
        self.assertEqual(len(found), 1, found)
        self.assertIn("as_root is called from planted", found[0])

    def test_the_check_finds_a_new_runner_of_a_plan(self):
        text = self.source() + '\n\ndef planted(what):\n    return root_plan(what)\n'
        self.assertEqual(len(root_problems(text)), 1)

    def test_the_check_finds_a_run_before_the_hash(self):
        text = self.source()
        early = text.replace('    plan = root_plan(what)\n    if not plan:',
                             '    plan = root_plan(what)\n    subprocess.run(plan["commands"][0])\n    if not plan:', 1)
        self.assertNotEqual(early, text)
        found = root_problems(early)
        self.assertEqual(len(found), 1, found)
        self.assertIn("before it checks the --confirm hash", found[0])

    def test_the_check_finds_a_fix_that_drops_confirm(self):
        text = self.source()
        dropped = text.replace("        return run_root(what, confirm)", "        return run_root(what)", 1)
        self.assertNotEqual(dropped, text)
        self.assertTrue(root_problems(dropped))

    def test_the_check_finds_pkexec_in_qml(self):
        with Planted('Item { property var c: ["pkexec", "true"] }\n') as path:
            self.assertEqual(len(root_text_problems([path])), 1)


# ---- L4: listeners and shells ---------------------------------------------------

SERVER_MODULES = {"http.server", "socketserver", "xmlrpc.server", "wsgiref.simple_server", "asyncio.start_server"}
SERVER_CALLS = {"bind", "listen", "accept", "serve_forever", "start_server", "create_server", "bus_own_name",
                "SocketService", "SocketListener", "DBusServer", "HTTPServer", "ThreadingHTTPServer", "TCPServer",
                "UDPServer", "UnixStreamServer", "ThreadingTCPServer", "own_name"}
SHELLS = {"sh", "bash", "zsh", "dash", "ash", "fish", "ksh"}
SHELL_CALLS = {"system", "popen", "getoutput", "getstatusoutput"}

# Functions that may use the socket module, and for what.
SOCKET_ALLOWED = {
    ("kdeconnect-bridge", "hypr_events"): "connects to Hyprland's own event socket as a client; binds nothing",
}
# Functions that start `sh -c` on a script they build, and why that is safe.
SHELL_ALLOWED = {
    ("kdeconnect-bridge", "root_plan"): "the root plan: a join of ufw commands built from PRIVATE_LANS and the mesh interface names, and shlex-quoted package names; shown on the card, bound by the --confirm hash",
    ("kdeconnect-bridge", "screen_command"): "scrcpy's log filter: shlex.quote of a constant pattern and of the plugin's own log path; the window's arguments follow as $@",
}


def basename_of(value):
    return os.path.basename(value) if isinstance(value, str) else ""


def listener_and_shell_problems(source, name="kdeconnect-bridge", used=None):
    tree = ast.parse(source)
    where = functions_of(tree)
    found = []

    def allowed(table, fn):
        key = (name, fn)
        if key in table:
            if used is not None:
                used.add((table is SOCKET_ALLOWED, key))
            return True
        return False

    for node in ast.walk(tree):
        fn = where.get(node, "")
        if isinstance(node, ast.Import):
            for a in node.names:
                if a.name in SERVER_MODULES:
                    found.append("%s:%d: imports %s, a server" % (name, node.lineno, a.name))
                if a.name == "socket" and not allowed(SOCKET_ALLOWED, fn):
                    found.append("%s:%d: imports socket in %s; only a reviewed client may" % (name, node.lineno, fn or "the module"))
        elif isinstance(node, ast.ImportFrom):
            if node.module in SERVER_MODULES or node.module == "socket" and not allowed(SOCKET_ALLOWED, fn):
                found.append("%s:%d: imports from %s" % (name, node.lineno, node.module))
        elif isinstance(node, ast.Call):
            f = node.func
            callee = f.id if isinstance(f, ast.Name) else f.attr if isinstance(f, ast.Attribute) else ""
            if callee in SERVER_CALLS:
                found.append("%s:%d: %s() listens or serves" % (name, node.lineno, callee))
            if callee in SHELL_CALLS and (isinstance(f, ast.Attribute) and ast.unparse(f.value) in ("os", "subprocess", "commands")):
                found.append("%s:%d: %s() runs a shell" % (name, node.lineno, ast.unparse(f)))
            for k in node.keywords:
                if k.arg == "shell" and not (isinstance(k.value, ast.Constant) and k.value.value is False):
                    found.append("%s:%d: shell=%s" % (name, node.lineno, ast.unparse(k.value)))
        elif isinstance(node, (ast.List, ast.Tuple)):
            items = node.elts
            for i, item in enumerate(items[:-2]):
                if isinstance(item, ast.Constant) and basename_of(item.value) in SHELLS \
                        and isinstance(items[i + 1], ast.Constant) and re.fullmatch(r"-l?c", str(items[i + 1].value)):
                    script = items[i + 2]
                    literal = isinstance(script, ast.Constant) and isinstance(script.value, str)
                    if not literal and not allowed(SHELL_ALLOWED, fn):
                        found.append("%s:%d: %s -c on a script that is not a literal, in %s" % (name, node.lineno, item.value, fn or "the module"))
    return found


def qml_shell_problems(path):
    raw = read(path)
    name = os.path.basename(path)
    found = []
    for m in re.finditer(r"""["'](?:/[\w/.]*/)?(sh|bash|zsh|dash|ash|fish|ksh)["']\s*,\s*["']-l?c["']\s*,\s*([^\n]*)""", raw):
        if not re.match(r"""^(?:"(?:[^"\\]|\\.)*"|'(?:[^'\\]|\\.)*')\s*[,\]]""", m.group(2).strip()):
            found.append("%s:%d: %s -c on a script that is not a literal" % (name, line_of(raw, m.start()), m.group(1)))
    return found


class ListenersAndShells(unittest.TestCase):
    def source(self):
        with open(BRIDGE) as f:
            return f.read()

    def test_the_bridge_listens_to_nothing_and_runs_no_built_shell(self):
        found = listener_and_shell_problems(self.source())
        self.assertEqual(found, [], "\n".join(found))

    def test_qml_runs_no_built_shell_script(self):
        found = [p for f in qml_files() for p in qml_shell_problems(f)]
        self.assertEqual(found, [], "\n".join(found))

    def test_every_allowed_function_is_still_used(self):
        used = set()
        listener_and_shell_problems(self.source(), used=used)
        want = {(True, k) for k in SOCKET_ALLOWED} | {(False, k) for k in SHELL_ALLOWED}
        self.assertEqual(sorted(want - used, key=str), [], "remove the entries nothing uses")

    def test_every_allowed_function_says_why(self):
        self.assertTrue(all(len(why) > 10 for why in list(SOCKET_ALLOWED.values()) + list(SHELL_ALLOWED.values())))

    def test_the_socket_in_the_bridge_connects_and_does_not_bind(self):
        tree = ast.parse(self.source())
        where = functions_of(tree)
        for node in ast.walk(tree):
            if isinstance(node, ast.Call) and isinstance(node.func, ast.Attribute) and where.get(node) == "hypr_events":
                self.assertNotIn(node.func.attr, SERVER_CALLS)

    def test_the_check_finds_a_planted_listener(self):
        cases = ['import socket\ndef serve():\n    s = socket.socket()\n    s.bind(("", 1))\n    s.listen()\n',
                 'from http.server import HTTPServer\n',
                 'import socketserver\n',
                 'def f():\n    from gi.repository import Gio\n    Gio.bus_own_name(1, "x", 0)\n',
                 'import http.server\n']
        for src in cases:
            self.assertTrue(listener_and_shell_problems(src, name="planted"), src)

    def test_the_check_finds_a_planted_shell(self):
        cases = ['import subprocess\ndef f(x):\n    subprocess.run("echo " + x, shell=True)\n',
                 'import subprocess\ndef f(x):\n    subprocess.run(["sh", "-c", "echo " + x])\n',
                 'import subprocess\ndef f(x):\n    subprocess.run(["/bin/bash", "-c", f"echo {x}"])\n',
                 'import os\ndef f(x):\n    os.system("echo")\n',
                 'import subprocess\ndef f(x):\n    subprocess.run(["uwsm-app", "--", "sh", "-c", x])\n']
        for src in cases:
            self.assertTrue(listener_and_shell_problems(src, name="planted"), src)

    def test_the_check_passes_a_literal_script_and_a_client(self):
        cases = ['import subprocess\ndef f(x):\n    subprocess.run(["sh", "-c", "echo hello"], shell=False)\n',
                 'import subprocess\ndef f(x):\n    subprocess.run(["ffmpegthumbnailer", "-c", "png"])\n']
        for src in cases:
            self.assertEqual(listener_and_shell_problems(src, name="planted"), [], src)

    def test_the_check_finds_a_planted_shell_in_qml(self):
        cases = ['Item { Process { command: ["sh", "-c", "echo " + text] } }\n',
                 'Item { Process { command: ["bash", "-c", script] } }\n']
        for src in cases:
            with Planted(src) as path:
                self.assertEqual(len(qml_shell_problems(path)), 1, src)
        with Planted('Item { Process { command: ["sh", "-c", "echo hello"] } }\n') as path:
            self.assertEqual(qml_shell_problems(path), [])

    def test_a_planted_listener_in_the_real_bridge_fails(self):
        found = listener_and_shell_problems(self.source() + '\n\ndef planted():\n    import socket\n    socket.socket().listen()\n')
        self.assertEqual(len(found), 2, found)


if __name__ == "__main__":
    unittest.main()
