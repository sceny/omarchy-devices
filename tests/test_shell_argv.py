"""C3, a shell in a script's own subprocess argv.

`shell=True`, `os.system`, `os.popen`, `bash -c`, `sh -c` (and the other
shells, `bash -lc`, the argv `["sh", "-c", ...]`) in `bin/`, `lib/`, `dev/` and
`tools/` hand a string to a shell, which reads every value in it as code. A
value from a device, a message or the API that reaches such a string is a
command run on this computer. A line that uses one is listed in SHELL_ALLOWED
with the reason the string holds no such value, or the build fails naming
file:line. Comment lines are not read."""

import os
import re
import shutil
import tempfile
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.join(HERE, "..")
FOLDERS = ("bin", "lib", "dev", "tools")

SHELL_USES = [re.compile(p) for p in (
    r"\bshell\s*=\s*True\b",
    r"\bos\.(?:system|popen)\s*\(",
    r"\b(?:ba|da|z)?sh\s+-[A-Za-z]*c\b",
    r"""["'](?:ba|da|z)?sh["']\s*,\s*["']-[A-Za-z]*c["']""",
)]

# (file, the line, spaces collapsed) -> why the string it hands to a shell holds
# no value from a device, a message or the API. A changed line is read again.
SHELL_ALLOWED = {
    ('bin/kdeconnect-bridge', 'run = ["scrcpy"] if not log else ["sh", "-c", \'stdbuf -oL -eL "$0" "$@" 2>&1 | grep --line-buffered -E %s >>%s\''): 'scrcpy\'s log filter: the pattern and the log path go through shlex.quote, the serial and the title are "$@" arguments',
    ('dev/clip-check', "mark() { ex sh -c 'printf MARK-P | wl-copy --primary; printf MARK-C | wl-copy'; sleep 0.4; }"): "the clipboard check: a literal command run in the check's own rig, no value from a device",
    ('dev/clip-check', "primary() { ex sh -c 'timeout 2 wl-paste --primary --no-newline 2>/dev/null'; }"): "the clipboard check: a literal command run in the check's own rig, no value from a device",
    ('dev/clip-check', "clipboard() { ex sh -c 'timeout 2 wl-paste --no-newline 2>/dev/null'; }"): "the clipboard check: a literal command run in the check's own rig, no value from a device",
    ('dev/clip-check', 'ex sh -c \'head -c 6000 /dev/zero | tr "\\0" x | wl-copy\''): "the clipboard check: a literal command run in the check's own rig, no value from a device",
    ('dev/clip-check', 'ex sh -c "printf \'%s\' \'$WORDS\' | wl-copy"'): "the clipboard check: a literal command run in the check's own rig, no value from a device",
    ('dev/loaded-code', 'done = subprocess.run(cmd, shell=True, capture_output=True, text=True, timeout=10)'): "the command is this tool's own default or the LOADED_CODE_SHOW_CMD its user sets, never a device's value",
    ('dev/sandbox', '"$SB_RUN_IMAGE" bash -c \'/opt/harness/dev/sandbox.d/inside.sh >&2; status=$?; tar -C /out -cf - .; exit $status\' \\'): "a literal command run inside the sandbox's container; the only value in it is the tool's own frame rate",
    ('dev/sandbox', '"$SB_RUN_IMAGE" bash -c \'python3 /opt/reencode.py /in/png /out >&2; status=$?; tar -C /out -cf - .; exit $status\' \\'): "a literal command run inside the sandbox's container; the only value in it is the tool's own frame rate",
    ('dev/sandbox', '"$image" bash -c \'pacman -Q hyprland quickshell; printf "omarchy %s\\n" "$(sed -n "s/^ARG OMARCHY_VERSION=//p" /opt/harness/dev/sandbox.d/Containerfile | head -1)"\' 2>/dev/null'): "a literal command run inside the sandbox's container; the only value in it is the tool's own frame rate",
    ('dev/sandbox', '"$(image_of "$DEV_PROFILE")" bash -c \'ffmpeg -nostdin -loglevel error -framerate "$FPS" -pattern_type glob -i "/in/frames/frame-*.png" \\'): "a literal command run inside the sandbox's container; the only value in it is the tool's own frame rate",
    ('dev/rig.d/checks.sh', 'rig_record manifest-id 0 bash -c \\'): "a rig check: the string holds only the rig's own variables (plugin id, folders, pids), no value from a device",
    ('dev/rig.d/checks.sh', 'bash -c "! test -e \'$RIG_PLUGINS_DIR/$RIG_PLUGIN_ID\'"'): "a rig check: the string holds only the rig's own variables (plugin id, folders, pids), no value from a device",
    ('dev/rig.d/checks.sh', 'bash -c "omarchy plugin list --json | jq -e --arg id \'$RIG_PLUGIN_ID\' \'any(.[]; .id == \\$id)\'"'): "a rig check: the string holds only the rig's own variables (plugin id, folders, pids), no value from a device",
    ('dev/rig.d/checks.sh', 'bash -c "! compgen -G \'$RIG_PLUGINS_DIR/.add.tmp.*\' > /dev/null"'): "a rig check: the string holds only the rig's own variables (plugin id, folders, pids), no value from a device",
    ('dev/rig.d/checks.sh', 'bash -c "omarchy plugin list --json | jq -e --arg id \'$RIG_PLUGIN_ID\' \'any(.[]; .id == \\$id and .enabled == true)\'"'): "a rig check: the string holds only the rig's own variables (plugin id, folders, pids), no value from a device",
    ('dev/rig.d/checks.sh', 'bash -c "jq -e --arg id \'$RIG_PLUGIN_ID\' \'[.bar.layout[]?[]?] | any(. == \\$id or (type == \\"object\\" and .id == \\$id))\' \'$RIG_HOME/.config/omarchy/shell.json\'"'): "a rig check: the string holds only the rig's own variables (plugin id, folders, pids), no value from a device",
    ('dev/rig.d/checks.sh', 'bash -c "! grep -iE \'pluginLoadFailed|Plugin .*failed to load|$RIG_PLUGIN_ID.*(error|Error)\' \'$RIG_LOGS/shell.log\'"'): "a rig check: the string holds only the rig's own variables (plugin id, folders, pids), no value from a device",
    ('dev/rig.d/checks.sh', 'bash -c "omarchy plugin list --json | jq -e --arg id \'$RIG_PLUGIN_ID\' \'any(.[]; .id == \\$id and .enabled == false)\'"'): "a rig check: the string holds only the rig's own variables (plugin id, folders, pids), no value from a device",
    ('dev/rig.d/checks.sh', 'bash -c "! test -e \'$RIG_PLUGINS_DIR/$RIG_PLUGIN_ID\'"'): "a rig check: the string holds only the rig's own variables (plugin id, folders, pids), no value from a device",
    ('dev/rig.d/checks.sh', 'bash -c "! omarchy plugin list --json | jq -e --arg id \'$RIG_PLUGIN_ID\' \'any(.[]; .id == \\$id)\'"'): "a rig check: the string holds only the rig's own variables (plugin id, folders, pids), no value from a device",
    ('dev/rig.d/checks.sh', 'bash -c "test -s \'$out\'"'): "a rig check: the string holds only the rig's own variables (plugin id, folders, pids), no value from a device",
    ('dev/rig.d/checks.sh', 'bash -c "! test -e \'$RIG_HOST_CONFIG_HOME/omarchy/plugins/$RIG_PLUGIN_ID\'"'): "a rig check: the string holds only the rig's own variables (plugin id, folders, pids), no value from a device",
    ('dev/rig.d/checks.sh', 'bash -c "pgrep -u \\"\\$(id -u)\\" -f \'quickshell.*-p \' | grep -qv \'^$RIG_SHELL_PID\\$\'"'): "a rig check: the string holds only the rig's own variables (plugin id, folders, pids), no value from a device",
    ('dev/rig.d/checks.sh', 'bash -c "! systemctl --user list-units >/dev/null 2>&1"'): "a rig check: the string holds only the rig's own variables (plugin id, folders, pids), no value from a device",
    ('dev/rig.d/checks.sh', 'rig_record "service-off-$id" 0 bash -c \\'): "a rig check: the string holds only the rig's own variables (plugin id, folders, pids), no value from a device",
    ('dev/rig.d/checks.sh', 'bash -c "[[ -n \'$keeper\' ]] && kill -0 \'$keeper\'"'): "a rig check: the string holds only the rig's own variables (plugin id, folders, pids), no value from a device",
    ('dev/rig.d/checks.sh', 'bash -c "[[ \'$RIG_RUNTIME_DIR\' == \'$RIG_RUNTIME_ROOT\'/opr.* ]]"'): "a rig check: the string holds only the rig's own variables (plugin id, folders, pids), no value from a device",
    ('dev/rig.d/checks.sh', 'bash -c "[[ \\"\\$DBUS_SESSION_BUS_ADDRESS\\" == \'unix:path=$RIG_RUNTIME_DIR/\'* ]]"'): "a rig check: the string holds only the rig's own variables (plugin id, folders, pids), no value from a device",
    ('dev/rig.d/lib.sh', "resolved=$(bash -c 'command -v omarchy-launch-terminal' 2>/dev/null)"): "a literal command that resolves Omarchy's terminal launcher",
    ('dev/rig.d/phone.sh', 'setsid unshare -U "--map-user=$(id -u)" "--map-group=$(id -g)" --keep-caps -nm bash -c "'): "the namespace's start: the string holds only the rig's own addresses",
    ('dev/sandbox.d/hostile.sh', 'dev_exec "$DEV_NAME" 60 bash -c \'test -f a.txt && test ! -e .env && test ! -e ignored.txt && test ! -L link-to-canary && test ! -e link-to-home && test ! -e linked/ssh && ! grep -rq SANDBOX-CANARY /work\' \\'): 'a literal check run inside the hostile-input sandbox, no value in it',
    ('dev/sandbox.d/hostile.sh', 'dev_exec "$DEV_NAME" 60 bash -c \'test -d .git && test "$(git log --format=%an | head -1)" = sandbox && test "$(git rev-list --count HEAD)" = 1\' >/dev/null 2>&1'): 'a literal check run inside the hostile-input sandbox, no value in it',
    ('dev/sandbox.d/hostile.sh', 'dev_exec "$DEV_NAME" 30 bash -c \'! command -v paperclipai && ! command -v psql\' >/dev/null 2>&1'): 'a literal check run inside the hostile-input sandbox, no value in it',
    ('dev/sandbox.d/hostile.sh', 'dev_exec "$DEV_NAME" 30 bash -c \'! command -v adb && ! test -e /opt/android-sdk && ! command -v scrcpy && ! command -v kdeconnect-cli\' >/dev/null 2>&1'): 'a literal check run inside the hostile-input sandbox, no value in it',
    ('dev/sandbox.d/hostile.sh', 'dev_exec "$DEV_NAME" 30 bash -c \'test -z "$(ls -A /out)"\' >/dev/null 2>&1'): 'a literal check run inside the hostile-input sandbox, no value in it',
    ('dev/sandbox.d/inside.sh', "unit-model) unit unit-model bash -c 'node --test tests/*.test.js' || status=$? ;;"): 'a literal test command run inside the sandbox, no value in it',
    ('dev/sandbox.d/inside.sh', "unit-bridge) unit unit-bridge bash -c 'python3 -m unittest discover -s tests -v' || status=$? ;;"): 'a literal test command run inside the sandbox, no value in it',
    ('dev/sandbox.d/inside.sh', 'unit qml-parse bash -c \'fmt=/usr/lib/qt6/bin/qmlformat; for f in *.qml; do "$fmt" "$f" >/dev/null || { echo "$f does not parse"; exit 1; }; done\' || status=$?'): 'a literal test command run inside the sandbox, no value in it',
}


def squash(line):
    return re.sub(r"\s+", " ", line.strip())


def shell_uses(root=ROOT, allowed=None):
    """(the uses of a shell not in `allowed`, the allowed entries that were met)."""
    allowed = SHELL_ALLOWED if allowed is None else allowed
    found, met = [], set()
    for top in FOLDERS:
        for folder, _, names in os.walk(os.path.join(root, top)):
            for name in sorted(names):
                path = os.path.join(folder, name)
                try:
                    with open(path) as f:
                        lines = f.read().splitlines()
                except (UnicodeDecodeError, OSError):
                    continue
                rel = os.path.relpath(path, root)
                for number, line in enumerate(lines, 1):
                    if line.lstrip().startswith(("#", "//")) or not any(r.search(line) for r in SHELL_USES):
                        continue
                    key = (rel, squash(line))
                    if key in allowed:
                        met.add(key)
                    else:
                        found.append("%s:%d: a shell is handed a string (`%s`) and the line is not in SHELL_ALLOWED"
                                     % (rel, number, key[1][:80]))
    return found, met


class NoShellInScripts(unittest.TestCase):
    def test_no_script_hands_a_string_to_a_shell(self):
        found, _ = shell_uses()
        self.assertEqual(found, [], "\n" + "\n".join(found))

    def test_every_allowed_line_is_still_there(self):
        _, met = shell_uses()
        stale = sorted(k for k in SHELL_ALLOWED if k not in met)
        self.assertEqual(stale, [], "taken out of the code, take out of SHELL_ALLOWED")

    def test_every_allowed_line_says_why(self):
        for key, why in SHELL_ALLOWED.items():
            self.assertGreater(len(why.split()), 3, key)
            self.assertNotIn("\n", why, key)

    def test_each_kind_of_shell_use_fails(self):
        planted = {
            "shell=True": 'subprocess.run(cmd, shell=True)',
            "os.system": 'os.system("ls " + name)',
            "os.popen": 'os.popen("ls " + name)',
            "bash -c": 'bash -c "echo $name"',
            "sh -c": "ex sh -c 'echo hi'",
            "bash -lc": "bash -lc 'echo hi'",
            "argv list": 'run(["sh", "-c", script])',
        }
        for what, line in planted.items():
            with tempfile.TemporaryDirectory() as d:
                os.makedirs(os.path.join(d, "dev"))
                with open(os.path.join(d, "dev", "tool"), "w") as f:
                    f.write("echo start\n%s\n" % line)
                found, _ = shell_uses(d, allowed={})
                self.assertEqual(len(found), 1, what)
                self.assertIn("dev/tool:2:", found[0], what)

    def test_a_listed_line_passes_and_a_changed_one_fails(self):
        with tempfile.TemporaryDirectory() as d:
            os.makedirs(os.path.join(d, "bin"))
            with open(os.path.join(d, "bin", "tool"), "w") as f:
                f.write("  bash   -c 'true'\n")
            allowed = {("bin/tool", "bash -c 'true'"): "a literal that is true"}
            self.assertEqual(shell_uses(d, allowed=allowed)[0], [])
            with open(os.path.join(d, "bin", "tool"), "w") as f:
                f.write("bash -c 'true' $name\n")
            self.assertEqual(len(shell_uses(d, allowed=allowed)[0]), 1)

    def test_comments_are_not_read(self):
        with tempfile.TemporaryDirectory() as d:
            os.makedirs(os.path.join(d, "lib"))
            with open(os.path.join(d, "lib", "tool.py"), "w") as f:
                f.write("# shell=True is what this does not do\n")
            self.assertEqual(shell_uses(d, allowed={})[0], [])

    def test_a_planted_shell_in_the_real_tree_fails(self):
        with tempfile.TemporaryDirectory() as d:
            for top in FOLDERS:
                if os.path.isdir(os.path.join(ROOT, top)):
                    shutil.copytree(os.path.join(ROOT, top), os.path.join(d, top))
            self.assertEqual(shell_uses(d)[0], [])
            with open(os.path.join(d, "bin", "kdeconnect-bridge"), "a") as f:
                f.write('\nsubprocess.run("ring " + name, shell=True)\n')
            found = shell_uses(d)[0]
            self.assertEqual(len(found), 1)
            self.assertIn("bin/kdeconnect-bridge:", found[0])


if __name__ == "__main__":
    unittest.main()
