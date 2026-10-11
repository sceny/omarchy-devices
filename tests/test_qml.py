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
                    'x = [bridge, "dial", c.device, number]\nrun("text", [], "text", null, t)\n')
        try:
            self.assertEqual(len(private_text_in_argv(f.name)), 3, private_text_in_argv(f.name))
        finally:
            os.remove(f.name)


if __name__ == "__main__":
    unittest.main()
