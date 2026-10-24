"""Every workflow in .github/workflows/ is read, not left to review: `release`
holds write access to the repository, and a run line that takes text from the
event runs as shell on a runner with that access.

Fails, naming file:line, on:
- a `pull_request_target` or `workflow_run` trigger (a run with the base
  repository's token on code or text from elsewhere);
- no top-level `permissions`, or one that is not read-only;
- a job's write permission that is not on WRITE_ALLOWED, with its reason;
- a `${{ }}` expression in a `run:` line (or a `script:` input) that is not on
  SAFE_IN_RUN: values the event or a branch name carries go through `env:`;
- an action not pinned by a full commit id (a branch moves, and so does a tag
  its owner re-points).

The files are read by a small reader of the YAML they use, since the system
Python has no YAML module; a construct it does not know raises, so a
workflow that leaves it fails the build instead of passing unread."""

import glob
import json
import os
import re
import subprocess
import sys
import tempfile
import unittest

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
WORKFLOWS = os.path.join(ROOT, ".github", "workflows")
CHECKER = os.path.join(ROOT, "dev", "public-text-check")

FORBIDDEN_TRIGGERS = {"pull_request_target", "workflow_run"}

# (workflow file, job) -> {scope: reason}
WRITE_ALLOWED = {
    ("release.yml", "publish"): {
        "contents": "tags the merge commit, publishes the release and brings develop level with main; the only job that writes",
        "statuses": "marks the release commit's status after it publishes",
    },
    ("develop-notice.yml", "notice"): {
        "issues": "opens an issue, assigned to the pusher, when the public-text check fails on a push to develop",
    },
}

# An expression in a run line is shell the author of its value writes, unless
# the value is one GitHub makes (a commit id, a run number) or the runner's.
SAFE_IN_RUN = re.compile(
    r"^(github\.(sha|run_id|run_number|run_attempt|repository|repository_owner|event_name|workspace|server_url)"
    r"|runner\.(temp|os|arch|name))$"
)

PINNED = re.compile(r"^[^@\s]+@[0-9a-f]{40}$")


class Unreadable(ValueError):
    pass


def _scalar(text, where):
    text = text.strip()
    if text[:1] in "\"'":
        end = text.find(text[0], 1)
        if end < 0:
            raise Unreadable("%s: an unclosed quote" % where)
        return text[1:end]
    if text[:1] in "{&*!%@`":
        raise Unreadable("%s: %r is not in the YAML this reader knows" % (where, text[:1]))
    if text.startswith("["):
        if not text.endswith("]"):
            raise Unreadable("%s: a flow list over several lines" % where)
        return [_scalar(part, where) for part in text[1:-1].split(",") if part.strip()]
    return re.sub(r"\s+#.*$", "", text)


def load(text, name="workflow"):
    """The tree of a workflow: dicts (with `__lines__`, each key's line), lists,
    strings and, for a `|` block, ("block", first line, text)."""
    raw = text.split("\n")
    lines = []
    for number, line in enumerate(raw, 1):
        if "\t" in line[: len(line) - len(line.lstrip())]:
            raise Unreadable("%s:%d: a tab in the indentation" % (name, number))
        lines.append(line)

    def indent_of(line):
        return len(line) - len(line.lstrip(" "))

    def skip(i):
        while i < len(lines) and (not lines[i].strip() or lines[i].lstrip().startswith("#")):
            i += 1
        return i

    def block(i, indent):
        i = skip(i)
        if i >= len(lines) or indent_of(lines[i]) < indent:
            return None, i
        indent = indent_of(lines[i])
        if lines[i].lstrip().startswith("- ") or lines[i].strip() == "-":
            return sequence(i, indent)
        return mapping(i, indent)

    def sequence(i, indent):
        out = []
        while True:
            i = skip(i)
            if i >= len(lines) or indent_of(lines[i]) != indent or not (lines[i].lstrip().startswith("- ") or lines[i].strip() == "-"):
                return out, i
            rest = lines[i].lstrip()[1:]
            if not rest.strip():
                value, i = block(i + 1, indent + 1)
                out.append(value)
                continue
            pad = indent + 1 + (len(rest) - len(rest.lstrip(" ")))
            body = rest.lstrip(" ")
            if re.match(r"^[\w.-]+\s*:(\s|$)", body):
                lines[i] = " " * pad + body
                value, i = mapping(i, pad)
                out.append(value)
            else:
                out.append(_scalar(body, "%s:%d" % (name, i + 1)))
                i += 1

    def mapping(i, indent):
        out = {}
        lines_of = out.setdefault("__lines__", {})
        while True:
            i = skip(i)
            if i >= len(lines) or indent_of(lines[i]) != indent:
                return out, i
            here = "%s:%d" % (name, i + 1)
            m = re.match(r"^\s*([\w.-]+|\"[^\"]*\"|'[^']*')\s*:(?:\s+(.*))?$", lines[i])
            if not m:
                raise Unreadable("%s: not a key: %r" % (here, lines[i].strip()))
            key, rest = m.group(1).strip("\"'"), (m.group(2) or "").strip()
            lines_of[key] = i + 1
            if re.sub(r"\s+#.*$", "", rest) in ("|", ">", "|-", ">-", "|+", ">+"):
                j, body = i + 1, []
                while j < len(lines) and (not lines[j].strip() or indent_of(lines[j]) > indent):
                    body.append(lines[j])
                    j += 1
                out[key] = ("block", i + 2, "\n".join(body))
                i = j
            elif not rest or rest.startswith("#"):
                nxt = skip(i + 1)
                if nxt < len(lines) and (indent_of(lines[nxt]) > indent or (indent_of(lines[nxt]) == indent and lines[nxt].lstrip().startswith("- "))):
                    out[key], i = block(i + 1, indent)
                else:
                    out[key], i = None, i + 1
            else:
                out[key] = _scalar(rest, here)
                i += 1

    tree, end = block(0, 0)
    end = skip(end)
    if end < len(lines):
        raise Unreadable("%s:%d: not read: %r" % (name, end + 1, lines[end].strip()))
    return tree if tree is not None else {}


def _items(node):
    if isinstance(node, dict):
        return [(k, v) for k, v in node.items() if k != "__lines__"]
    return []


def _line(node, key, default):
    return node.get("__lines__", {}).get(key, default)


def triggers(tree):
    on = tree.get("on")
    if isinstance(on, dict):
        return {k for k, _ in _items(on)}
    if isinstance(on, list):
        return set(on)
    return {on} if on else set()


def _write_scopes(perms):
    """[(scope, value)] of a `permissions` value that grants more than read."""
    if perms is None:
        return []
    if isinstance(perms, str):
        return [("*", perms)] if perms not in ("read-all", "{}") else []
    return [(k, v) for k, v in _items(perms) if v not in ("read", "none")]


def walk(node, path=()):
    """(path, key, value) of every key in the tree, to find run lines and uses."""
    if isinstance(node, dict):
        for key, value in _items(node):
            yield path, key, value, node
            yield from walk(value, path + (key,))
    elif isinstance(node, list):
        for item in node:
            yield from walk(item, path)


def problems(name, text, write_allowed=WRITE_ALLOWED):
    """[(file:line, why)] for one workflow file."""
    try:
        tree = load(text, name)
    except Unreadable as error:
        return [(str(error).split(": ")[0], "unreadable: " + str(error))]
    found = []
    where = lambda line: "%s:%s" % (name, line)

    for trigger in sorted(triggers(tree) & FORBIDDEN_TRIGGERS):
        on = tree["on"]
        found.append((where(_line(on, trigger, 1) if isinstance(on, dict) else _line(tree, "on", 1)),
                      "the %s trigger runs with the base repository's token" % trigger))

    if "permissions" not in tree:
        found.append((where(1), "no top-level permissions: the token takes the repository's default"))
    for scope, value in _write_scopes(tree.get("permissions")):
        found.append((where(_line(tree, "permissions", 1)), "top-level permissions grant %s: %s" % (scope, value)))

    base = os.path.basename(name)
    for job, body in _items(tree.get("jobs") or {}):
        if not isinstance(body, dict):
            continue
        allowed = write_allowed.get((base, job), {})
        for scope, value in _write_scopes(body.get("permissions")):
            if scope == "*" or scope not in allowed or value != "write":
                found.append((where(_line(body, "permissions", _line(tree.get("jobs"), job, 1))),
                              "job %s grants %s: %s, which is not on the reviewed list" % (job, scope, value)))

    for path, key, value, parent in walk(tree):
        if key == "uses" and isinstance(value, str):
            if value.startswith("./") or value.startswith("docker://"):
                continue
            if not PINNED.match(value):
                found.append((where(_line(parent, "uses", 1)), "%s is not pinned by a full commit id" % value))
        if key in ("run", "script") and (key == "run" or path[-1:] == ("with",)):
            line, code = (value[1], value[2]) if isinstance(value, tuple) else (_line(parent, key, 1), value)
            if not isinstance(code, str):
                continue
            for number, row in enumerate(code.split("\n")):
                for expression in re.findall(r"\$\{\{(.*?)\}\}", row):
                    if not SAFE_IN_RUN.match(expression.strip()):
                        found.append((where(line + number if isinstance(value, tuple) else line),
                                      "${{ %s }} in a %s line: pass it through env:" % (expression.strip(), key)))
    return found


def shipped():
    paths = sorted(glob.glob(os.path.join(WORKFLOWS, "*.yml")) + glob.glob(os.path.join(WORKFLOWS, "*.yaml")))
    return paths


class ShippedWorkflows(unittest.TestCase):
    def test_every_workflow_is_read(self):
        names = {os.path.basename(p) for p in shipped()}
        self.assertTrue({"test.yml", "release.yml", "public-text.yml", "marketplace-check.yml"} <= names, names)

    def test_none_breaks_a_rule(self):
        found = []
        for path in shipped():
            with open(path) as handle:
                text = handle.read()
            found += ["%s: %s" % (where, why) for where, why in problems(os.path.relpath(path, ROOT), text)]
        self.assertEqual(found, [], "\n".join(found))

    def test_the_reader_finds_what_the_rules_judge(self):
        keys = {"uses": 0, "run": 0}
        for path in shipped():
            with open(path) as handle:
                tree = load(handle.read(), path)
            for _, key, _, _ in walk(tree):
                if key in keys:
                    keys[key] += 1
        self.assertGreaterEqual(keys["uses"], 6, keys)
        self.assertGreaterEqual(keys["run"], 8, keys)

    def test_the_write_list_names_jobs_that_exist(self):
        for (name, job), scopes in WRITE_ALLOWED.items():
            with open(os.path.join(WORKFLOWS, name)) as handle:
                tree = load(handle.read(), name)
            self.assertIn(job, dict(_items(tree["jobs"])), name)
            granted = {k for k, v in _items(tree["jobs"][job].get("permissions") or {}) if v == "write"}
            self.assertEqual(granted, set(scopes), "%s: the list and the file differ" % job)
            for scope, reason in scopes.items():
                self.assertGreater(len(reason.split()), 4, "%s %s: say why" % (job, scope))


class DevelopNotice(unittest.TestCase):
    """The notice's issue names each failing rule and where it is, never the text
    it matched: the checker's output in CI does not print the match, and the
    notice passes that output on as it is."""

    PLANTED = "/home/alice/.paperclip/instances/default/workspaces/aaaaaaaa-0000-0000-0000-000000000001"
    SECRETS = ("/home/alice", "alice", "aaaaaaaa-0000", "SCE-999")

    def body(self, check_output):
        with open(os.path.join(WORKFLOWS, "develop-notice.yml")) as handle:
            tree = load(handle.read(), "develop-notice.yml")
        run = next(step["run"][2] for step in tree["jobs"]["notice"]["steps"]
                   if step.get("name", "").startswith("Tell a person"))
        with tempfile.TemporaryDirectory() as tmp:
            bin_dir = os.path.join(tmp, "bin")
            os.mkdir(bin_dir)
            gh = os.path.join(bin_dir, "gh")
            with open(gh, "w") as handle:
                handle.write("#!/bin/sh\nexit 0\n")
            os.chmod(gh, 0o755)
            script = os.path.join(tmp, "step.sh")
            with open(script, "w") as handle:
                handle.write(run)
            with open(os.path.join(tmp, "public-text.txt"), "w") as handle:
                handle.write(check_output)
            env = dict(
                os.environ,
                PATH=bin_dir + os.pathsep + os.environ["PATH"],
                RUNNER_TEMP=tmp,
                GH_TOKEN="x",
                ACTOR="someone",
                GITHUB_REPOSITORY="sceny/omarchy-devices",
                COMMIT_URL="https://github.com/sceny/omarchy-devices/commit/0000000",
                RUN_URL="https://github.com/sceny/omarchy-devices/actions/runs/1",
            )
            result = subprocess.run(["bash", "-e", "-o", "pipefail", script], env=env, capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stderr)
            with open(os.path.join(tmp, "public-text-notice.md")) as handle:
                return handle.read()

    def test_the_issue_names_the_rule_and_its_place_never_the_matched_text(self):
        doc = {"changed_files": [], "texts": [
            {"url": "https://example.test/c/1", "body": "Ran in %s for SCE-999." % self.PLANTED}]}
        with tempfile.TemporaryDirectory() as tmp:
            fixture = os.path.join(tmp, "doc.json")
            with open(fixture, "w") as handle:
                json.dump(doc, handle)
            checked = subprocess.run([sys.executable, CHECKER, "--fixture", fixture], capture_output=True, text=True,
                                     env=dict(os.environ, GITHUB_ACTIONS="true"))
        self.assertEqual(checked.returncode, 1, checked.stdout)
        body = self.body(checked.stdout)
        for secret in self.SECRETS:
            self.assertNotIn(secret, body)
        self.assertIn("FAIL public-text-environment [home-path] https://example.test/c/1", body)
        self.assertIn("problem(s) in the public text", body)


GOOD = """\
name: x
on:
  pull_request:
  push:
    branches: [main]
permissions:
  contents: read
jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@11d5960a326750d5838078e36cf38b85af677262 # v4.4.0
        with:
          persist-credentials: false
      - name: Run
        env:
          TITLE: ${{ github.event.pull_request.title }}
        run: |
          echo "$TITLE" "${{ github.sha }}"
          echo ${{ runner.temp }}
"""


def planted(old, new):
    assert old in GOOD, old
    return GOOD.replace(old, new)


class Planted(unittest.TestCase):
    """Each rule fails on a planted workflow, naming the line."""

    def whys(self, text, **kw):
        return [(where, why) for where, why in problems("w.yml", text, **kw)]

    def test_the_good_workflow_passes(self):
        self.assertEqual(self.whys(GOOD), [])

    def test_a_trigger_that_runs_with_the_base_token(self):
        for trigger in ("pull_request_target", "workflow_run"):
            found = self.whys(planted("  pull_request:\n", "  %s:\n" % trigger))
            self.assertEqual([w for w, _ in found], ["w.yml:3"], found)
            self.assertIn(trigger, found[0][1])
        found = self.whys(planted("on:\n  pull_request:\n  push:\n    branches: [main]\n", "on: [push, pull_request_target]\n"))
        self.assertEqual(len(found), 1, found)

    def test_permissions_at_the_top(self):
        self.assertEqual(len(self.whys(planted("permissions:\n  contents: read\n", ""))), 1)
        found = self.whys(planted("  contents: read\n", "  contents: write\n"))
        self.assertEqual([w for w, _ in found], ["w.yml:6"], found)
        self.assertEqual(len(self.whys(planted("permissions:\n  contents: read\n", "permissions: write-all\n"))), 1)
        self.assertEqual(self.whys(planted("permissions:\n  contents: read\n", "permissions: read-all\n")), [])

    def test_a_job_writes_only_what_is_listed(self):
        text = planted("    runs-on: ubuntu-latest\n", "    runs-on: ubuntu-latest\n    permissions:\n      contents: write\n")
        found = self.whys(text)
        self.assertEqual([w for w, _ in found], ["w.yml:11"], found)
        self.assertEqual(self.whys(text, write_allowed={("w.yml", "test"): {"contents": "reviewed"}}), [])
        other = self.whys(text, write_allowed={("w.yml", "test"): {"statuses": "reviewed"}})
        self.assertEqual(len(other), 1, other)

    def test_event_text_in_a_run_line(self):
        for expression in ("github.event.pull_request.title", "github.head_ref", "inputs.commit", "github.ref_name", "steps.x.outputs.y"):
            inline = planted('          echo ${{ runner.temp }}\n', "          echo ${{ %s }}\n" % expression)
            found = self.whys(inline)
            self.assertEqual([w for w, _ in found], ["w.yml:20"], (expression, found))
            one_line = planted("        run: |\n          echo \"$TITLE\" \"${{ github.sha }}\"\n          echo ${{ runner.temp }}\n",
                               "        run: echo ${{ %s }}\n" % expression)
            self.assertEqual([w for w, _ in self.whys(one_line)], ["w.yml:18"], (expression, self.whys(one_line)))

    def test_event_text_in_a_script_input(self):
        text = planted("      - name: Run\n", "      - uses: actions/github-script@11d5960a326750d5838078e36cf38b85af677262\n        with:\n          script: |\n            core.info('${{ github.head_ref }}')\n      - name: Run\n")
        found = self.whys(text)
        self.assertEqual(len(found), 1, found)
        self.assertIn("script", found[0][1])

    def test_an_action_pinned_by_a_branch_or_a_tag(self):
        for ref in ("main", "master", "v4", "v4.4.0", "11d5960"):
            found = self.whys(planted("actions/checkout@11d5960a326750d5838078e36cf38b85af677262", "actions/checkout@" + ref))
            self.assertEqual([w for w, _ in found], ["w.yml:12"], (ref, found))
        self.assertEqual(len(self.whys(planted("actions/checkout@11d5960a326750d5838078e36cf38b85af677262", "actions/checkout"))), 1)

    def test_what_the_reader_does_not_know_fails(self):
        found = self.whys(planted("  contents: read\n", "  contents: {read: 1}\n"))
        self.assertTrue(found and "unreadable" in found[0][1], found)


if __name__ == "__main__":
    unittest.main()
