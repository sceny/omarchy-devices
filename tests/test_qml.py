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

    def test_the_check_finds_them(self):
        import tempfile
        with tempfile.NamedTemporaryFile("w", suffix=".qml", delete=False) as f:
            f.write("Item {\n  onOpenedChanged: x = 1\n  // onOpenedChanged: in a comment\n  Item { onOpenedChanged: y }\n  onOpenedChanged: z = \"{\"\n  Item { id: a }\n  Item { id: a }\n"
                    "  component One: Item { id: b }\n  component Two: Item { id: b }\n}\n")
        try:
            self.assertEqual(len(problems(f.name)), 2, problems(f.name))
        finally:
            os.remove(f.name)


# Verbs that carry text a person wrote. Any local process can read a command
# line from /proc, so the text goes over stdin (`run`'s input), and the
# arguments after the device are ids only.
PRIVATE_VERBS = ("ping", "text", "url", "dial", "reply")
ALLOWED_ARGS = {"reply": ["n.replyId"]}


def private_text_in_argv(path):
    """Lines where a private verb's argument list holds anything but its ids."""
    text = open(path).read()
    found = []
    for verb in PRIVATE_VERBS:
        for m in re.finditer(r'\brun\(\s*"%s"\s*,\s*\[([^\]]*)\]' % verb, text):
            args = [a.strip() for a in m.group(1).split(",") if a.strip()]
            if args != ALLOWED_ARGS.get(verb, []):
                found.append("%s:%d: run(\"%s\") argv %s" % (os.path.basename(path), text.count("\n", 0, m.start()) + 1, verb, args))
        for m in re.finditer(r'\brun\(\s*"%s"\s*,\s*(?![\s\[])' % verb, text):
            found.append("%s:%d: run(\"%s\") argv is not a literal list" % (os.path.basename(path), text.count("\n", 0, m.start()) + 1, verb))
        for m in re.finditer(r'\[\s*(?:root\.)?bridge\s*,\s*"%s"\s*([^\]]*)\]' % verb, text):
            args = [a.strip() for a in m.group(1).split(",") if a.strip()]
            if len(args) > 1:
                found.append("%s:%d: [bridge, \"%s\"] argv %s" % (os.path.basename(path), text.count("\n", 0, m.start()) + 1, verb, args))
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
                    'run("ping", m !== "" ? [m] : [], "ping")\n')
        try:
            self.assertEqual(len(private_text_in_argv(f.name)), 4, private_text_in_argv(f.name))
        finally:
            os.remove(f.name)


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


if __name__ == "__main__":
    unittest.main()
