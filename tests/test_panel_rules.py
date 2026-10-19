"""Panel rules a reviewer would check by reading.

Nothing scripted focuses a text field (AGENTS.md): keystrokes meant for
another window would land in it, and Enter would send or commit it. The IPC
target's functions are followed through every function they call; one that
reaches a focus on a text field without the `typeHere` gate fails, naming the
path. The user's own click or Enter passes `typeHere`; the IPC target never
does.
"""

import glob
import os
import re
import tempfile
import unittest

from test_qml import call_args, code_only

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.join(HERE, "..")

FOCUS = re.compile(r"\b(\w+)\.forceActiveFocus\(")
# The key catcher is not a text field: giving it focus hands the keyboard back.
NOT_A_FIELD = ("keyCatcher",)


def match_close(text, start):
    """The index of the brace closing the one at `start`."""
    depth = 0
    for i in range(start, len(text)):
        if text[i] == "{":
            depth += 1
        elif text[i] == "}":
            depth -= 1
            if depth == 0:
                return i
    return len(text) - 1


def functions(path):
    """Every `function name(params) {` in a file: its parameters, its body
    (comments and strings blanked), the line it starts on and whether it sits
    inside an IpcHandler."""
    with open(path) as f:
        text = code_only(f.read())
    ipc = []
    for m in re.finditer(r"\bIpcHandler\s*\{", text):
        ipc.append((m.end() - 1, match_close(text, m.end() - 1)))
    found = []
    for m in re.finditer(r"\bfunction\s+(\w+)\s*\(([^)]*)\)[^{;]*\{", text):
        end = match_close(text, m.end() - 1)
        params = [p.split(":")[0].strip() for p in m.group(2).split(",") if p.strip()]
        found.append({
            "name": m.group(1), "params": params, "body": text[m.end():end],
            "file": os.path.basename(path), "line": text.count("\n", 0, m.start()) + 1,
            "ipc": any(a < m.start() < b for a, b in ipc),
        })
    return found


def ungated_focus(fn):
    """The text fields a function focuses without `typeHere` on the statement
    or on the `if` in front of it."""
    found = []
    for m in FOCUS.finditer(fn["body"]):
        if m.group(1) in NOT_A_FIELD:
            continue
        start = fn["body"].rfind("\n", 0, m.start()) + 1
        context = fn["body"][max(0, fn["body"].rfind("\n", 0, start - 1) + 1):m.end()]
        if "typeHere" not in context or "typeHere" not in fn["params"]:
            found.append(m.group(1))
    return found


def scripted_focus(paths):
    """Paths from an IPC function to a focus on a text field with no gate, or
    to a call that hands `true` to a `typeHere` parameter."""
    funcs = {}
    for p in paths:
        for fn in functions(p):
            funcs.setdefault(fn["name"], []).append(fn)
    found, seen = [], set()

    def walk(fn, chain):
        key = (fn["file"], fn["line"])
        if key in seen:
            return
        seen.add(key)
        here = chain + ["%s (%s:%d)" % (fn["name"], fn["file"], fn["line"])]
        for field in ungated_focus(fn):
            found.append("%s focuses %s: %s" % (here[0], field, " -> ".join(here)))
        for m in re.finditer(r"(?<![\w.])(?:root\.)?(\w+)\s*\(", fn["body"]):
            for callee in funcs.get(m.group(1), []):
                if callee is fn or m.group(1) == fn["name"]:
                    continue
                if "typeHere" in callee["params"]:
                    args = call_args(fn["body"], m.end() - 1)
                    i = callee["params"].index("typeHere")
                    if i < len(args) and args[i] == "true":
                        found.append("%s hands typeHere=true to %s: %s"
                                     % (here[0], callee["name"], " -> ".join(here)))
                walk(callee, here)

    roots = [fn for name in sorted(funcs) for fn in funcs[name] if fn["ipc"]]
    for fn in roots:
        seen.clear()
        walk(fn, [])
    return sorted(set(found))


class NothingScriptedFocusesAField(unittest.TestCase):
    def test_no_ipc_function_reaches_an_ungated_focus(self):
        files = sorted(glob.glob(os.path.join(ROOT, "*.qml")))
        self.assertTrue(files)
        found = scripted_focus(files)
        self.assertEqual(found, [], "\n".join(found))

    def test_the_check_finds_a_missing_gate_and_a_true(self):
        src = (
            "Item {\n"
            "  function openIt(typeHere) { if (typeHere === true) field.forceActiveFocus() }\n"
            "  function openBare() { field.forceActiveFocus() }\n"
            "  function viaOpen() { openBare() }\n"
            "  function gateOnOtherLine(typeHere) {\n    other.forceActiveFocus()\n  }\n"
            "  function back() { keyCatcher.forceActiveFocus() }\n"
            "  IpcHandler {\n"
            "    function ok(): string { root.openIt(); return \"\" }\n"
            "    function ok2(): string { root.openIt(false); root.back(); return \"\" }\n"
            "    function bad(): string { root.viaOpen(); return \"\" }\n"
            "    function worse(): string { root.openIt(true); return \"\" }\n"
            "    function ungated(): string { root.gateOnOtherLine(); return \"\" }\n"
            "  }\n}\n")
        with tempfile.NamedTemporaryFile("w", suffix=".qml", delete=False) as f:
            f.write(src)
        try:
            found = scripted_focus([f.name])
            names = sorted(m.split(" ")[0] for m in found)
            self.assertEqual(names, ["bad", "ungated", "worse"], found)
        finally:
            os.remove(f.name)


if __name__ == "__main__":
    unittest.main()


class ClosingHandsTheKeyboardBack(unittest.TestCase):
    def test_the_close_branch_focuses_the_key_catcher(self):
        with open(os.path.join(ROOT, "Panel.qml")) as f:
            text = code_only(f.read())
        m = re.search(r"\bonOpenedChanged\s*:\s*\{", text)
        self.assertTrue(m, "Panel.qml has no onOpenedChanged")
        body = text[m.end() - 1:match_close(text, m.end() - 1) + 1]
        close = re.search(r"\belse\s*\{", body)
        self.assertTrue(close, "onOpenedChanged has no close branch")
        branch = body[close.end() - 1:match_close(body, close.end() - 1) + 1]
        self.assertIn("keyCatcher.forceActiveFocus()", branch,
                      "a field that held the keyboard at close keeps it at the next open")
