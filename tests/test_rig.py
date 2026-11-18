"""The rig's gaps from the regressions (#281, #535), on its shell functions.

Each test sources dev/rig's files into a bash of its own with the parts that
reach a compositor, an emulator or a namespace replaced by recorders, so
nothing here starts a rig. `dev/rig selftest cold` runs the cold end's part
of the selftest the same way."""

import hashlib
import os
import shutil
import subprocess
import tempfile
import textwrap
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.normpath(os.path.join(HERE, ".."))
DEV = os.path.join(ROOT, "dev")

SOURCE = textwrap.dedent(f"""\
    set -uo pipefail
    RIG_DIR={DEV}
    source "$RIG_DIR/rig.conf"
    RIG_PLUGIN_SRC_ABS={ROOT}
    for f in lib lease display selftest phone checks cold; do source "$RIG_DIR/rig.d/$f.sh"; done
    rig_no_cores() {{ :; }}
    rig_phone_export_env() {{ :; }}
    """)

GOOD = "a" * 64
BAD = "b" * 64


class Bash:
    def setUp(self):
        self.tmp = tempfile.mkdtemp(prefix="rig-test.")
        self.addCleanup(shutil.rmtree, self.tmp, True)
        self.env = {
            "HOME": os.path.join(self.tmp, "home"),
            "PATH": os.environ.get("PATH", "/usr/bin:/bin"),
            "TMPDIR": self.tmp,
            "PAPERCLIP_SCRATCH_DIR": self.tmp,
            "RIG_TMP_ROOT": os.path.join(self.tmp, "registry"),
            "RIG_RUNTIME_ROOT": self.tmp,
            "LANG": "C.UTF-8",
        }
        os.makedirs(self.env["HOME"])

    def session(self):
        """A stand-in rig: its paths defined and its folders made."""
        return textwrap.dedent("""\
            mkdir -p "$RIG_TMP_ROOT"
            rig_define_paths "$(rig_new_session_dir)"
            mkdir -p "$RIG_SESSION" "$RIG_LOGS" "$RIG_STUB_BIN" "$RIG_HOME" "$RIG_RUNTIME_DIR"
            """)

    def bash(self, body, env=None):
        script = os.path.join(self.tmp, "t.sh")
        with open(script, "w") as f:
            f.write(SOURCE + body)
        return subprocess.run(["bash", script], capture_output=True, text=True, timeout=60,
                              env=dict(self.env, **(env or {})))

    def tool(self, folder, name, text):
        os.makedirs(folder, exist_ok=True)
        path = os.path.join(folder, name)
        with open(path, "w") as f:
            f.write(text)
        os.chmod(path, 0o755)
        return path


class ScreenChecksWithoutSound(Bash, unittest.TestCase):
    """scrcpy finds no sound device in the rig, so the rig gives SDL its dummy driver."""

    def test_the_rig_environment_has_the_dummy_audio_driver(self):
        out = self.bash(self.session() + 'rig_export_env; printf "%s\\n" "${SDL_AUDIODRIVER-unset}"')
        self.assertEqual(out.returncode, 0, out.stderr)
        self.assertEqual(out.stdout.strip(), "dummy")

    def test_a_child_the_rig_starts_inherits_it(self):
        out = self.bash(self.session() + "rig_export_env; env | grep '^SDL_AUDIODRIVER='")
        self.assertEqual(out.stdout.strip(), "SDL_AUDIODRIVER=dummy")


class ApkSigner(Bash, unittest.TestCase):
    """The pinned APK's signer check: BASH_ENV cannot change the java it runs, and no JDK says so."""

    def setUp(self):
        super().setUp()
        self.sdk = os.path.join(self.tmp, "sdk")
        # apksigner is a shell script that runs java, as the SDK's is.
        self.tool(os.path.join(self.sdk, "build-tools", "34.0.0"), "apksigner",
                  '#!/bin/bash\nexec java -jar apksigner.jar "$@"\n')
        self.good = os.path.join(self.tmp, "good")
        self.tool(self.good, "java", f'#!/bin/sh\necho "Signer #1 certificate SHA-256 digest: {GOOD}"\n')
        self.bad = os.path.join(self.tmp, "bad")
        self.tool(self.bad, "java", f'#!/bin/sh\necho "Signer #1 certificate SHA-256 digest: {BAD}"\n')
        self.bash_env = os.path.join(self.tmp, "bash_env")
        with open(self.bash_env, "w") as f:
            f.write(f'PATH="{self.bad}:$PATH"\n')
        cache = os.path.join(self.env["RIG_TMP_ROOT"], "cache")
        os.makedirs(cache)
        self.apk = os.path.join(cache, "org.kde.kdeconnect_tp_13517.apk")
        with open(self.apk, "wb") as f:
            f.write(b"not an apk")
        self.sha = hashlib.sha256(b"not an apk").hexdigest()

    def check(self, before="", path=None, env=None):
        path = path or f"{self.good}:$PATH"
        return self.bash(self.session() + before + textwrap.dedent(f"""\
            RIG_ANDROID_SDK={self.sdk}
            RIG_KDC_APK_SHA256={self.sha}
            RIG_KDC_APK_SIGNER_SHA256={GOOD}
            PATH="{path}"
            unset JAVA_HOME
            rig_kdc_apk
            """), env=env)

    def test_bash_env_does_not_reach_the_signer_check(self):
        out = self.check(before="rig_export_env\n", env={"BASH_ENV": self.bash_env, "ENV": self.bash_env})
        self.assertEqual(out.returncode, 0, out.stderr)
        self.assertEqual(out.stdout.strip(), self.apk)

    def test_without_the_rig_environment_bash_env_would_change_the_java(self):
        # The control: the same check with BASH_ENV left in place fails, so the test above bites.
        out = self.check(env={"BASH_ENV": self.bash_env})
        self.assertNotEqual(out.returncode, 0)
        self.assertIn("is not the pinned one", out.stderr)

    def test_no_jdk_says_so_and_checks_the_hash(self):
        tools = os.path.join(self.tmp, "tools")
        os.makedirs(tools)
        for name in ("bash", "sha256sum", "cut", "ls", "tail", "sed", "head", "mkdir", "env"):
            found = shutil.which(name)
            self.assertTrue(found, name)
            os.symlink(found, os.path.join(tools, name))
        out = self.check(path=tools)
        self.assertEqual(out.returncode, 0, out.stderr)
        self.assertEqual(out.stdout.strip(), self.apk)
        self.assertIn("no JDK", out.stderr)
        self.assertNotIn("not the pinned one", out.stderr)

    def test_an_apksigner_that_reads_no_signer_says_what_it_printed(self):
        self.tool(self.good, "java", '#!/bin/sh\necho "ERROR: not a ZIP archive" >&2; exit 1\n')
        out = self.check()
        self.assertNotEqual(out.returncode, 0)
        self.assertIn("read no signer", out.stderr)
        self.assertIn("not a ZIP archive", out.stderr)

    def test_a_wrong_signer_fails(self):
        self.tool(self.good, "java", f'#!/bin/sh\necho "Signer #1 certificate SHA-256 digest: {BAD}"\n')
        out = self.check()
        self.assertNotEqual(out.returncode, 0)
        self.assertIn(f"signer {BAD} is not the pinned one", out.stderr)


class PhonePairAfterColdBegin(Bash, unittest.TestCase):
    """`phone pair` on a cleared app: the daemon must be there, the dialog answered, the app opened."""

    def pair(self, daemon=True):
        calls = os.path.join(self.tmp, "calls")
        out = self.bash(self.session() + textwrap.dedent(f"""\
            rig_select() {{ :; }}
            rig_export_env() {{ :; }}
            rig_guard_sandbox() {{ :; }}
            RIG_NETNS_PID=1
            rig_kdcd_up() {{ {"true" if daemon else "false"}; }}
            rig_adb_shell() {{ printf 'adb shell %s\\n' "$*" >>{calls}; }}
            rig_kdc_pair() {{ printf 'pair\\n' >>{calls}; }}
            : >{calls}
            cmd_phone pair
            """))
        with open(calls) as f:
            return out, f.read().splitlines()

    def test_pair_allows_notifications_and_opens_the_app_first(self):
        out, calls = self.pair()
        self.assertEqual(out.returncode, 0, out.stderr)
        self.assertEqual(calls, [
            "adb shell pm grant org.kde.kdeconnect_tp android.permission.POST_NOTIFICATIONS",
            "adb shell am start -n org.kde.kdeconnect_tp/org.kde.kdeconnect.ui.MainActivity",
            "pair",
        ])

    def test_pair_with_no_daemon_says_how_to_start_one(self):
        out, calls = self.pair(daemon=False)
        self.assertNotEqual(out.returncode, 0)
        self.assertIn("no kdeconnectd on the rig bus", out.stderr)
        self.assertIn("dev/rig cold daemon", out.stderr)
        self.assertEqual(calls, [])

    def test_pair_grants_nothing_the_plugin_grants_itself(self):
        with open(os.path.join(DEV, "rig.d", "phone.sh")) as f:
            text = f.read()
        body = text[text.index("rig_kdc_app_ready() {"):]
        body = body[:body.index("\n}\n")]
        for grant in ("allow_listener", "READ_SMS", "READ_CONTACTS", "MANAGE_EXTERNAL_STORAGE"):
            self.assertNotIn(grant, body)


class ColdStatus(Bash, unittest.TestCase):
    """`cold status` reports a warm rig; it is not a failure."""

    def test_a_warm_rig_is_reported_and_succeeds(self):
        out = self.bash(self.session() + textwrap.dedent("""\
            rig_select() { :; }
            rig_export_env() { :; }
            rig_guard_sandbox() { :; }
            rig_guard_nested_display() { :; }
            RIG_NETNS_PID=1
            cmd_cold status
            """))
        self.assertEqual(out.returncode, 0, out.stderr)
        self.assertIn("warm", out.stderr)
        self.assertNotIn("✗", out.stderr)


class SelftestReadsAllOfPs(Bash, unittest.TestCase):
    """The selftest's ps checks read ps's whole output: grep -q quitting early is no failure."""

    def test_a_rig_listed_before_a_long_tail_is_found(self):
        # More than a pipe holds after the match, so `cmd_ps | grep -q` meets SIGPIPE.
        out = self.bash(textwrap.dedent("""\
            cmd_ps() { echo "rig-a live"; head -c 300000 /dev/zero | tr '\\0' x; echo; }
            st_listed rig-a && echo listed
            ! st_ps_says rig-z && echo absent
            """))
        self.assertEqual(out.stdout.split(), ["listed", "absent"], out.stderr)

    def test_the_selftest_never_pipes_ps_into_grep_q(self):
        with open(os.path.join(DEV, "rig.d", "selftest.sh")) as f:
            self.assertNotIn("cmd_ps | grep -q", f.read())


class SelftestLeavesRealRigsAlone(Bash, unittest.TestCase):
    """The selftest's reap sees only its own scope: a real rig beside it keeps its keeper and compositor."""

    def test_a_scoped_scan_skips_a_tagged_process_out_of_its_scope(self):
        tag = "bystander.20000101-000000.%s" % os.urandom(3).hex()
        env = dict(self.env, OPR_RIG_ID=tag)
        proc = subprocess.Popen(["sleep", "60"], env=env)
        self.addCleanup(proc.wait)
        self.addCleanup(proc.kill)
        out = self.bash(textwrap.dedent(f"""\
            [[ -n $(rig_tagged_pids {tag}) ]] && echo seen
            [[ -z $(OPR_RIG_SCOPE=/a/selftest rig_tagged_pids {tag}) ]] && echo skipped
            """))
        self.assertEqual(out.stdout.split(), ["seen", "skipped"], out.stderr)

    def test_the_selftest_scopes_its_processes(self):
        with open(os.path.join(DEV, "rig.d", "selftest.sh")) as f:
            text = f.read()
        self.assertIn("export RIG_TMP_ROOT RIG_RUNTIME_ROOT RIG_KEEPER_INTERVAL OPR_RIG_SCOPE", text)
        self.assertIn("a real rig's process outside the test's scope is left alone", text)

    def test_a_lost_keeper_is_named_before_the_missing_socket(self):
        out = self.bash(self.session() + textwrap.dedent("""\
            sleep 0 & dead=$!; wait $dead
            printf '%s\\n' "$dead" >"$RIG_SESSION/keeper.pid"
            XDG_RUNTIME_DIR=$RIG_RUNTIME_DIR WAYLAND_DISPLAY=wayland-1
            rig_guard_nested_display
            """))
        self.assertNotEqual(out.returncode, 0)
        self.assertIn("keeper", out.stderr)
        self.assertNotIn("is not a socket", out.stderr)


class ColdEnd(Bash, unittest.TestCase):
    """`dev/rig cold end` takes a cold rig back to warm (#535): the selftest's part for it."""

    def test_the_selftest_passes(self):
        out = subprocess.run([os.path.join(DEV, "rig"), "selftest", "cold"], capture_output=True,
                             text=True, timeout=120, env=self.env)
        self.assertEqual(out.returncode, 0, out.stderr)
        self.assertIn("passed, 0 failed", out.stderr)
        self.assertNotIn("✗", out.stderr)

    def test_the_usage_names_end(self):
        with open(os.path.join(DEV, "rig.d", "cold.sh")) as f:
            self.assertIn("begin | end | status", f.read())


class Upgrade(Bash, unittest.TestCase):
    """`dev/rig upgrade`: the checkout is the package repo's next commit, so the installed clone fast-forwards."""

    def git(self, *args, cwd):
        return subprocess.run(["git", *args], cwd=cwd, capture_output=True, text=True, check=True,
                              env=dict(self.env, GIT_CONFIG_NOSYSTEM="1")).stdout.strip()

    def test_an_installed_clone_fast_forwards_to_the_new_tree(self):
        src = os.path.join(self.tmp, "src")
        os.makedirs(src)
        self.git("init", "-q", "-b", "main", cwd=src)
        for name, text in (("manifest.json", '{"id": "sceny.devices"}\n'), ("old.qml", "old\n"), ("a.qml", "1\n")):
            with open(os.path.join(src, name), "w") as f:
                f.write(text)
        self.git("add", "-A", cwd=src)
        plugins = os.path.join(self.tmp, "plugins")
        build = self.bash(self.session() + f"RIG_PLUGIN_SRC_ABS={src}\nrig_build_package_repo\n"
                          "printf '%s\\n' \"$RIG_PKG_REPO\"\n")
        self.assertEqual(build.returncode, 0, build.stderr)
        repo = build.stdout.strip()
        clone = os.path.join(plugins, "sceny.devices")
        subprocess.run(["git", "clone", "-q", "file://" + repo, clone], check=True, env=self.env)

        os.remove(os.path.join(src, "old.qml"))
        with open(os.path.join(src, "a.qml"), "w") as f:
            f.write("2\n")
        self.git("add", "-A", cwd=src)
        commit = self.bash(textwrap.dedent(f"""\
            rig_define_paths {os.path.dirname(repo)}
            RIG_PLUGIN_SRC_ABS={src}
            rig_package_commit
            """))
        self.assertEqual(commit.returncode, 0, commit.stderr)

        # What `omarchy plugin update` does to the installed clone.
        self.git("fetch", "-q", "origin", "HEAD", cwd=clone)
        self.git("merge", "-q", "--ff-only", "FETCH_HEAD", cwd=clone)
        with open(os.path.join(clone, "a.qml")) as f:
            self.assertEqual(f.read(), "2\n")
        self.assertFalse(os.path.exists(os.path.join(clone, "old.qml")))
        self.assertEqual(self.git("rev-parse", "HEAD", cwd=clone), self.git("rev-parse", "HEAD", cwd=repo))

    def test_upgrade_is_a_verb(self):
        with open(os.path.join(DEV, "rig")) as f:
            text = f.read()
        self.assertIn("upgrade) cmd_upgrade", text)
        self.assertIn("omarchy plugin update \"$RIG_PLUGIN_ID\" --yes", text)


if __name__ == "__main__":
    unittest.main()
