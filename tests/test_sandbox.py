"""dev/sandbox: what it refuses, and the isolation it must keep.

The sandbox runs a contributor's commit, so two things are held at the source
and not at the case that was reported:

1. Input. Only a full 40-hex sha of a commit of an allowed repository runs; a
   branch, a short sha, another repository or an unknown option is refused
   before anything is fetched or started.
2. The podman invocation. The flags that isolate the run are all present, and
   nothing that would open it is: no privilege, no host network, no host
   mount but the commit's read-only tar and the QA script, no environment
   passed through.

The hostile test (`dev/sandbox hostile-test`) proves the same from inside a
real container; this one runs in CI, where there is no podman.
"""

import importlib.util
import io
import json
import os
import re
import shlex
import shutil
import signal
import stat
import struct
import subprocess
import tarfile
import tempfile
import time
import unittest
from unittest import mock
import zlib

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SANDBOX = os.path.join(ROOT, "dev", "sandbox")
GOOD_SHA = "a" * 40
REPO = "sceny/omarchy-devices"


def sandbox(*args):
    return subprocess.run(
        ["bash", SANDBOX, *args],
        capture_output=True,
        text=True,
        timeout=60,
        env={"PATH": os.environ.get("PATH", "/usr/bin:/bin"), "HOME": os.environ.get("HOME", "/nonexistent")},
    )


class Refusals(unittest.TestCase):
    def refused(self, *args, message):
        r = sandbox("run", *args)
        self.assertEqual(r.returncode, 2, r.stdout + r.stderr)
        self.assertIn(message, r.stderr)
        self.assertNotIn("starting the container", r.stderr)

    def test_a_repository_that_is_not_listed(self):
        self.refused("someone/else", GOOD_SHA, message="is not a repository this sandbox runs")

    def test_a_repository_that_only_looks_listed(self):
        self.refused("sceny/omarchy-devices-evil", GOOD_SHA, message="is not a repository this sandbox runs")
        self.refused("evil/sceny/omarchy-devices", GOOD_SHA, message="is not a repository this sandbox runs")

    def test_only_a_full_lowercase_sha(self):
        for ref in ("develop", "main", "HEAD", "a" * 7, "a" * 39, "a" * 41, "A" * 40, "g" * 40, "a" * 40 + "\n", "--help"):
            with self.subTest(ref=ref):
                r = sandbox("run", REPO, ref)
                self.assertEqual(r.returncode, 2, r.stdout + r.stderr)
                self.assertNotIn("starting the container", r.stderr)

    def test_unknown_option(self):
        self.refused(REPO, GOOD_SHA, "--privileged", message="unknown option")

    def test_a_third_argument(self):
        self.refused(REPO, GOOD_SHA, "extra", message="unexpected argument")

    def test_steps_are_a_known_list(self):
        for steps in ("shell", "tests,", "tests;rig", "tests rig", "$(id)", "Tests"):
            with self.subTest(steps=steps):
                r = sandbox("run", REPO, GOOD_SHA, "--steps", steps)
                self.assertEqual(r.returncode, 2, r.stdout + r.stderr)

    def test_build_takes_no_other_paperclip_branch(self):
        r = sandbox("build", "--paperclip-ref", "feature")
        self.assertEqual(r.returncode, 2, r.stdout + r.stderr)
        self.assertIn("unknown option", r.stderr)

    def test_harness_is_develop_or_pr(self):
        self.refused(REPO, GOOD_SHA, "--harness", "host", message="--harness is develop or pr")

    def test_timeout_is_whole_seconds(self):
        self.refused(REPO, GOOD_SHA, "--timeout", "5", message="at least 30")
        self.refused(REPO, GOOD_SHA, "--timeout", "1h", message="whole seconds")

    def test_the_script_step_needs_a_script(self):
        self.refused(REPO, GOOD_SHA, "--steps", "script", message="needs --script")
        self.refused(REPO, GOOD_SHA, "--script", "/nonexistent/qa.sh", message="not a readable file")

    def test_unknown_command(self):
        r = sandbox("shell")
        self.assertEqual(r.returncode, 2)
        self.assertIn("unknown command", r.stderr)


class SliceUnit(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.bin = os.path.join(self.tmp.name, "bin")
        self.state = os.path.join(self.tmp.name, "state")
        os.mkdir(self.bin)
        self.stub("podman", "exit 0")
        self.env = {
            "PATH": self.bin + os.pathsep + os.environ.get("PATH", "/usr/bin:/bin"),
            "HOME": self.tmp.name,
            "SANDBOX_STATE": self.state,
        }

    def tearDown(self):
        self.tmp.cleanup()

    def stub(self, name, body):
        path = os.path.join(self.bin, name)
        with open(path, "w") as f:
            f.write("#!/bin/sh\n" + body + "\n")
        os.chmod(path, 0o755)

    def refused_by_systemctl(self, output, status, *args):
        self.stub("systemctl", f"printf '%s\\n' '{output}'\nexit {status}")
        return subprocess.run(["bash", SANDBOX, *args], capture_output=True, text=True, timeout=60, env=self.env)

    def test_run_and_dev_start_refuse_unless_the_unit_is_loaded(self):
        for output, status in (("not-found", 1), ("masked", 0), ("", 1)):
            for verb, args in (("run", (REPO, GOOD_SHA)), ("dev start", ("--repo", REPO))):
                with self.subTest(verb=verb, output=output):
                    r = self.refused_by_systemctl(output, status, *verb.split(), *args)
                    self.assertEqual(r.returncode, 2, r.stdout + r.stderr)
                    self.assertIn("sandbox.slice is not loaded", r.stderr)
                    self.assertFalse(os.path.exists(os.path.join(self.state, ".lock")))


class Isolation(unittest.TestCase):
    """The text of the podman invocation in cmd_run."""

    @classmethod
    def setUpClass(cls):
        with open(SANDBOX) as f:
            text = f.read()
        start = text.index('--runroot "$SB_RUNTIME" run')
        end = text.index('"$SB_RUN_IMAGE" bash -c')
        cls.run_cmd = text[start:end]
        cls.script = text

    def test_flags_that_isolate_are_present(self):
        for flag in (
            "--network none",
            "--cap-drop all",
            "--security-opt no-new-privileges",
            "--read-only",
            "--uidmap 0:1:65536",
            "--gidmap 0:1:65536",
            "--user 1000:1000",
            "--pull never",
            "--memory",
            "--pids-limit",
            "--cpus",
            "--timeout",
            "--no-hosts",
        ):
            with self.subTest(flag=flag):
                self.assertIn(flag, self.run_cmd)

    def test_nothing_that_opens_the_container(self):
        for flag in (
            "--privileged",
            "--network host",
            "--network=host",
            "--pid host",
            "--pid=host",
            "--ipc host",
            "--userns host",
            "--userns=host",
            "--userns keep-id",
            "--cap-add",
            "seccomp=unconfined",
            "apparmor=unconfined",
            "--env-host",
            "--env-file",
            "--volume",
            " -v ",
            "--group-add",
            "--security-opt unmask",
        ):
            with self.subTest(flag=flag):
                self.assertNotIn(flag, self.run_cmd)

    def test_the_only_host_mounts_are_read_only(self):
        mounts = re.findall(r'--mount "([^"]+)"', self.script)
        self.assertTrue(mounts)
        for m in mounts:
            with self.subTest(mount=m):
                self.assertTrue(m.startswith(("type=bind,src=$SB_RUN_DIR/", "type=bind,src=$png,", "type=bind,src=$SB_DIR/sandbox.d/reencode.py,",
                                         "type=bind,src=$SB_DIR/sandbox.d/devside.sh,", "type=bind,src=$frames,dst=/in/frames,")), m)
                self.assertTrue(m.endswith(",ro"), m)
        self.assertNotIn("--mount", self.run_cmd.replace('"${mounts[@]}"', ""))

    def test_devices_are_only_what_the_rig_needs(self):
        self.assertEqual(re.findall(r'--device (?:/dev/kvm|"\$node")', self.script).__len__(), 5)  # a run's three, the session's two
        self.assertIn('devices=(--device /dev/kvm --device "$node")', self.script)
        self.assertIn('devices=(--device "$node")', self.script)
        self.assertIn('[[ $step_name == tests ]] || { unit_devices=("${devices[@]}")', self.script)
        self.assertIn('$node == /dev/dri/renderD*', self.script)
        self.assertNotIn("--device /dev/dri/card", self.script)

    def test_podman_runs_in_an_empty_environment(self):
        self.assertIn("env -i", self.script[self.script.index("timeout --signal=KILL $((timeout"):].split("podman")[0])
        self.assertIn("env -i PATH=/usr/bin:/usr/local/bin HOME", self.script.split("pm() {")[1].split("}")[0])

    def test_the_container_is_given_only_its_own_variables(self):
        env = re.findall(r'--env "?([A-Z_]+)=', self.run_cmd)
        self.assertEqual(sorted(env), ["HOME", "LANG", "SANDBOX_HARNESS", "SANDBOX_REPO", "SANDBOX_SHA", "SANDBOX_UNIT", "TERM"])

    def test_the_commit_enters_as_an_archive(self):
        self.assertIn("archive --format=tar", self.script)
        self.assertNotIn("git clone", self.script)
        self.assertNotIn("git checkout", self.script)

    def test_results_are_read_as_data(self):
        with open(READ_RESULT) as f:
            reader = f.read()
        self.assertIn("O_NOFOLLOW", reader)
        self.assertIn("isreg()", reader)
        self.assertNotIn("extractall", reader)
        self.assertIn("read_result.py", self.script.split("read_result() {")[1].split("\n}")[0])
        self.assertNotIn("tar -x", self.script.split("read_result() {")[1].split("\n}")[0])

    def test_the_picture_container_has_what_the_unit_container_has_and_less(self):
        text = self.script
        start = text.index("reencode_pngs() {")
        body = text[start : text.index("\n}\n", start)]
        for flag in ("--network none", "--cap-drop all", "--security-opt no-new-privileges", "--read-only", "--uidmap 0:1:65536",
                     "--user 1000:1000", "--pull never", "--memory", "--pids-limit", "--timeout", "--no-hosts", "env -i"):
            with self.subTest(flag=flag):
                self.assertIn(flag, body)
        for flag in ("--device", "--privileged", "--cap-add", "--env SANDBOX", "src.tar", "script.sh", "--network host"):
            with self.subTest(flag=flag):
                self.assertNotIn(flag, body)

    def test_the_results_go_where_git_and_shells_do_not_look(self):
        self.assertIn('out="$SB_STATE/results/', self.script)
        self.assertNotIn("sandbox-out", self.script.replace("# ", ""))
        self.assertIn("out_in_git", self.script.split("cmd_run() {")[1])

    def test_each_unit_has_a_directory_of_its_own_made_by_the_host(self):
        self.assertIn('mkdir -p -m 755 "$out/$unit"', self.script)
        self.assertIn('read_result "$tarfile" "$out/$unit" "$out" "$unit"', self.script)

    def test_each_step_and_unit_gets_a_share_of_the_limit_not_all_of_it(self):
        loop = self.script.split("local steps_left=")[1].split("write_verdict ")[0]
        self.assertIn("step_end=$((SECONDS + (timeout - (SECONDS - started)) / steps_left))", loop)
        self.assertIn("left=$(((step_end - SECONDS) / (${#step_units[@]} - i)))", loop)
        self.assertNotIn("left=$((timeout - (SECONDS - started)))", self.script)

    def test_the_tests_step_runs_with_the_seccomp_profile_without_user_namespaces(self):
        self.assertIn('seccomp=(--security-opt "seccomp=$SB_RUN_DIR/seccomp.json")', self.script)
        self.assertIn('"${seccomp[@]}"', self.run_cmd)
        self.assertIn("UNIT_NO_USERNS=1", self.script)
        self.assertNotIn("seccomp=unconfined", self.script)
        self.assertIn("seccomp.py", self.script.split("make_seccomp() {")[1].split("}")[0])


class DevSession(unittest.TestCase):
    """`dev/sandbox dev`: a session for Sceny's own tree, held to what a run is held to."""

    @classmethod
    def setUpClass(cls):
        with open(SANDBOX) as f:
            cls.script = f.read()
        start = cls.script.index("dev_start() {")
        cls.start = cls.script[start : cls.script.index("\n}\n", start)]

    def test_the_session_has_every_flag_a_run_has(self):
        for flag in ("--network none", "--no-hosts", "--uidmap 0:1:65536", "--gidmap 0:1:65536", "--user 1000:1000", "--read-only",
                     "--cap-drop all", "--security-opt no-new-privileges", "--pull never", "--memory", "--pids-limit", "--cpus",
                     "--timeout", "--rm", "--ulimit core=0"):
            with self.subTest(flag=flag):
                self.assertIn(flag, self.start)

    def test_nothing_in_the_session_opens_it(self):
        for flag in ("--privileged", "--network host", "--network=host", "--pid host", "--ipc host", "--userns host", "--userns keep-id",
                     "--cap-add", "unconfined", "--env-host", "--env-file", "--volume", " -v ", "--group-add", "--publish", " -p ",
                     "--security-opt unmask"):
            with self.subTest(flag=flag):
                self.assertNotIn(flag, self.start)

    def test_the_only_host_path_is_the_session_script_read_only(self):
        mounts = re.findall(r'--mount "([^"]+)"', self.start)
        self.assertEqual(mounts, ["type=bind,src=$SB_DIR/sandbox.d/devside.sh,dst=/opt/devside.sh,ro"])

    def test_the_session_has_the_two_devices_the_rig_needs(self):
        self.assertEqual(re.findall(r'--device (?:/dev/kvm|"\$node")', self.start), ["--device /dev/kvm", '--device "$node"'])
        self.assertIn("devices=(--device /dev/kvm)", self.start)
        self.assertIn("if [[ $profile == devices ]]", self.start)
        self.assertIn("$node == /dev/dri/renderD*", self.start)
        self.assertNotIn("/dev/dri/card", self.start)

    def test_the_session_is_given_only_its_own_variables(self):
        env = re.findall(r"--env ([A-Z_]+)=", self.start)
        self.assertEqual(sorted(env), ["HOME", "LANG", "TERM"])

    def test_the_session_ends_by_itself_and_the_ttl_is_bounded(self):
        self.assertIn('--timeout "$ttl"', self.start)
        self.assertIn("SB_DEV_TTL_MAX=14400", self.script)
        self.assertIn("ttl >= 60 && ttl <= SB_DEV_TTL_MAX", self.start)

    def test_the_image_must_not_be_behind_this_machine(self):
        self.assertIn("pins_check \"$profile\" ||", self.start)
        body = self.script[self.script.index("pins_check() {") : self.script.index("cmd_pins() {")]
        for name in ("omarchy", "hyprland", "quickshell"):
            self.assertIn(name, body)
        self.assertIn("vercmp", body)
        self.assertIn("--network none", body)

    def test_the_tree_goes_in_as_tracked_files_and_not_as_a_mount(self):
        sync = self.script[self.script.index("dev_sync() {") : self.script.index("# Pictures and recordings out")]
        self.assertIn("ls-files -z", sync)
        self.assertIn("tree_tar.py", sync)
        self.assertNotIn("--mount", sync)
        self.assertNotIn("--volume", sync)
        self.assertIn("GIT_CONFIG_GLOBAL=/dev/null", sync)

    def test_what_comes_out_is_read_as_data_and_pictures_are_decoded_again(self):
        pull = self.script[self.script.index("dev_pull() {") : self.script.index("dev_assemble() {")]
        self.assertIn("read_result ", pull)
        self.assertIn("reencode_pngs", pull)
        self.assertNotIn("tar -x", pull)
        self.assertIn("head -c $((SB_MAX_RESULT + 1))", pull)
        self.assertIn("out_in_git", pull)

    def test_the_video_is_built_in_a_container_with_only_the_decoded_frames(self):
        body = self.script[self.script.index("dev_assemble() {") : self.script.index("dev_status() {")]
        for flag in ("--network none", "--cap-drop all", "--security-opt no-new-privileges", "--read-only", "--uidmap 0:1:65536",
                     "--user 1000:1000", "--pull never", "--memory", "--pids-limit", "--timeout", "--no-hosts", "env -i"):
            with self.subTest(flag=flag):
                self.assertIn(flag, body)
        for flag in ("--device", "--privileged", "--cap-add", "--network host"):
            with self.subTest(flag=flag):
                self.assertNotIn(flag, body)
        self.assertEqual(re.findall(r'--mount "([^"]+)"', body), ["type=bind,src=$frames,dst=/in/frames,ro"])
        self.assertIn("--only-video", body)
        guard = body.index("A-Za-z0-9._-")
        self.assertLess(guard, body.index("podman"))
        self.assertIn("SKIPPED.txt", body[guard : body.index("podman")])
        self.assertNotIn("mv -n", body)

    def test_the_verbs_refuse_what_is_not_a_session(self):
        r = sandbox("dev", "--timeout", "5m", "status")
        self.assertEqual(r.returncode, 2, r.stdout + r.stderr)
        self.assertIn("whole seconds", r.stderr)


CONTAINERFILE = os.path.join(ROOT, "dev", "sandbox.d", "Containerfile")


class Profiles(unittest.TestCase):
    """One image per repository: each holds only its own tools."""

    @classmethod
    def setUpClass(cls):
        with open(SANDBOX) as f:
            cls.script = f.read()
        with open(CONTAINERFILE) as f:
            text = f.read()
        parts = re.split(r"(?m)^FROM .* AS (\w+)$", text)
        cls.stages = {k: re.sub(r"(?m)^#.*$", "", v) for k, v in zip(parts[1::2], parts[2::2])}

    def test_each_repository_has_its_own_image(self):
        self.assertIn("SB_PROFILES=(devices paperclipai)", self.script)
        self.assertIn("sceny/omarchy-devices) echo devices", self.script)
        self.assertIn("sceny/omarchy-paperclipai) echo paperclipai", self.script)
        self.assertEqual(set(self.stages), {"base", "devices", "paperclipai"})

    def test_devices_image_has_no_paperclip(self):
        for word in ("paperclip", "postgresql", "npm"):
            with self.subTest(word=word):
                self.assertNotIn(word, self.stages["base"].lower())
                self.assertNotIn(word, self.stages["devices"].lower())

    def test_paperclip_image_has_no_android(self):
        for word in ("android", "kdeconnect", "scrcpy", "sshfs", "/dev/kvm", "jdk"):
            with self.subTest(word=word):
                self.assertNotIn(word, self.stages["base"].lower())
                self.assertNotIn(word, self.stages["paperclipai"].lower())

    def test_the_paperclip_cli_comes_from_the_lockfile_only(self):
        body = self.stages["paperclipai"]
        self.assertIn("npm ci --omit=dev", body)
        self.assertNotIn("npm install", body.replace("npm install --package-lock-only", ""))

    def test_no_install_script_runs_but_the_embedded_postgres_one_by_name(self):
        body = self.stages["paperclipai"]
        self.assertIn("npm ci --omit=dev --ignore-scripts", body)
        self.assertIn("npm rebuild @embedded-postgres/linux-x64", body)
        self.assertLess(body.index("npm ci"), body.index("npm rebuild"))

    def test_the_paperclip_mirror_is_built_from_its_develop_only(self):
        build = self.script[self.script.index("cmd_build() {") : self.script.index("valid_repo() {")]
        self.assertIn("refs/heads/develop^{commit}", build)
        self.assertNotIn("--paperclip-ref", self.script)

    def test_a_session_is_made_for_one_repository_and_kept_to_it(self):
        start = self.script[self.script.index("dev_start() {") :]
        self.assertIn('--label "$SB_PROFILE_LABEL=$profile"', start)
        sync = self.script[self.script.index("dev_sync() {") : self.script.index("# Pictures and recordings out")]
        self.assertIn("SB_PROFILE_LABEL", self.script[self.script.index("dev_profile() {") :])
        self.assertIn("manifest", sync)

    def test_dev_sync_refuses_a_linked_manifest_before_it_reads_one(self):
        sync = self.script[self.script.index("dev_sync() {") : self.script.index("# Pictures and recordings out")]
        self.assertIn('! -L $tree/manifest.json', sync)
        self.assertLess(sync.index('! -L $tree/manifest.json'), sync.index("id_found=$(python3"))

    def test_a_repository_that_is_not_allowed_has_no_session(self):
        r = sandbox("dev", "start", "--repo", "someone/else")
        self.assertEqual(r.returncode, 2, r.stdout + r.stderr)
        self.assertIn("not a repository", r.stderr)

    def test_no_profile_runs_the_network(self):
        for flag in ("--network none",):
            self.assertGreaterEqual(self.script.count(flag), 3)
        self.assertNotIn("--network host", self.script)
        self.assertNotIn("--network=host", self.script)


DEVSIDE = os.path.join(ROOT, "dev", "sandbox.d", "devside.sh")
TREE_TAR = os.path.join(ROOT, "dev", "sandbox.d", "tree_tar.py")


class DevSide(unittest.TestCase):
    """The script the session runs for the host: it takes names, not paths."""

    def run_verb(self, *args):
        return subprocess.run(["bash", DEVSIDE, *args], capture_output=True, text=True, timeout=30,
                              env={"PATH": os.environ.get("PATH", "/usr/bin:/bin")})

    def test_a_name_is_lower_case_words(self):
        for name in ("../x", "A", "a b", "a/b", "-x", "", "x" * 62, "a;b", "$(id)"):
            for verb in (("shot", name), ("record", name, "5", "5")):
                with self.subTest(verb=verb):
                    r = self.run_verb(*verb)
                    self.assertEqual(r.returncode, 2, r.stdout + r.stderr)
                    self.assertIn("lower-case", r.stderr)

    def test_an_unknown_verb(self):
        r = self.run_verb("bash")
        self.assertEqual(r.returncode, 2)
        self.assertIn("unknown verb", r.stderr)

    def test_the_tree_is_not_replaced_by_what_it_carries(self):
        with open(DEVSIDE) as f:
            text = f.read()
        self.assertNotIn("/work/src/dev/sandbox.d", text)


class TreeTar(unittest.TestCase):
    """What leaves this machine when the tree goes into a session."""

    def tree(self):
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        root = os.path.realpath(tmp.name)
        env = {"PATH": os.environ.get("PATH", "/usr/bin:/bin"), "HOME": root, "GIT_CONFIG_GLOBAL": "/dev/null", "GIT_CONFIG_SYSTEM": "/dev/null"}
        self.env = env
        subprocess.run(["git", "init", "-q", root], check=True, env=env)
        return root

    def sync(self, root, limit=1 << 30):
        names = subprocess.run(["git", "-C", root, "ls-files", "-z"], capture_output=True, check=True, env=self.env).stdout
        r = subprocess.run(["python3", TREE_TAR, root, str(limit)], input=names, capture_output=True, timeout=60)
        members = []
        if r.stdout:
            with tarfile.open(fileobj=io.BytesIO(r.stdout)) as t:
                members = {m.name: (m, t.extractfile(m).read() if m.isreg() else None) for m in t.getmembers()}
        return r, members

    def add(self, root, *paths):
        subprocess.run(["git", "-C", root, "add", "-f", *paths], check=True, env=self.env)

    def test_only_tracked_files_leave(self):
        root = self.tree()
        for name, data in (("a.txt", b"a"), ("sub/b.txt", b"b"), (".env", b"SECRET"), ("untracked.txt", b"u")):
            os.makedirs(os.path.dirname(os.path.join(root, name)), exist_ok=True)
            with open(os.path.join(root, name), "wb") as f:
                f.write(data)
        self.add(root, "a.txt", "sub/b.txt")
        r, members = self.sync(root)
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertEqual(sorted(members), ["a.txt", "sub/b.txt"])

    def test_the_working_tree_bytes_go_not_the_index(self):
        root = self.tree()
        path = os.path.join(root, "a.txt")
        with open(path, "wb") as f:
            f.write(b"one")
        self.add(root, "a.txt")
        with open(path, "wb") as f:
            f.write(b"two")
        r, members = self.sync(root)
        self.assertEqual(members["a.txt"][1], b"two")

    def test_a_link_to_the_outside_is_left_out_and_never_followed(self):
        root = self.tree()
        outside = tempfile.NamedTemporaryFile(delete=False)
        self.addCleanup(os.unlink, outside.name)
        outside.write(b"PRIVATE")
        outside.close()
        os.symlink(outside.name, os.path.join(root, "link"))
        os.symlink("/etc", os.path.join(root, "dirlink"))
        with open(os.path.join(root, "ok.txt"), "wb") as f:
            f.write(b"ok")
        self.add(root, "link", "dirlink", "ok.txt")
        r, members = self.sync(root)
        self.assertEqual(sorted(members), ["ok.txt"])
        self.assertNotIn(b"PRIVATE", r.stdout)

    def test_a_file_behind_a_linked_directory_is_left_out(self):
        root = self.tree()
        outer = tempfile.mkdtemp()
        self.addCleanup(subprocess.run, ["rm", "-rf", outer])
        with open(os.path.join(outer, "x.txt"), "wb") as f:
            f.write(b"PRIVATE")
        os.symlink(outer, os.path.join(root, "d"))
        self.add(root, "d")
        names = b"d/x.txt\0"
        r = subprocess.run(["python3", TREE_TAR, root, "1000000"], input=names, capture_output=True, timeout=60)
        self.assertNotIn(b"PRIVATE", r.stdout)

    def test_git_dirs_and_paths_that_leave_the_tree_are_left_out(self):
        root = self.tree()
        with open(os.path.join(root, "ok.txt"), "wb") as f:
            f.write(b"ok")
        names = b"ok.txt\0.git/config\0sub/.git/hooks/x\0../x\0/etc/passwd\0a/../../b\0"
        r = subprocess.run(["python3", TREE_TAR, root, "1000000"], input=names, capture_output=True, timeout=60)
        self.assertEqual(r.returncode, 0, r.stderr)
        with tarfile.open(fileobj=io.BytesIO(r.stdout)) as t:
            self.assertEqual(t.getnames(), ["ok.txt"])

    def test_nothing_arrives_owned_or_privileged(self):
        root = self.tree()
        path = os.path.join(root, "run.sh")
        with open(path, "wb") as f:
            f.write(b"#!/bin/sh\n")
        os.chmod(path, 0o4755)
        self.add(root, "run.sh")
        r, members = self.sync(root)
        info = members["run.sh"][0]
        self.assertEqual((info.uid, info.gid, info.mode), (0, 0, 0o755))

    def test_a_tree_over_the_limit_fails(self):
        root = self.tree()
        with open(os.path.join(root, "big"), "wb") as f:
            f.write(b"x" * 5000)
        self.add(root, "big")
        r, _ = self.sync(root, limit=1000)
        self.assertEqual(r.returncode, 1)
        self.assertIn("larger than", r.stderr.decode())


class XSockets(unittest.TestCase):
    """The rig step's compositor parent opens an X socket in the container's /tmp; a host's is never told from it by name."""

    HOSTILE = os.path.join(ROOT, "dev", "sandbox.d", "hostile")

    @classmethod
    def setUpClass(cls):
        with open(os.path.join(cls.HOSTILE, "test_hostile.py")) as f:
            src = f.read()
        funcs = [m.group(0) for m in re.finditer(r"^def (?:own_listening_sockets|x_socket_state)\(.*?(?=^def |\Z)", src, re.S | re.M)]
        cls.ns = {"os": os, "stat": stat}
        exec("\n\n".join(funcs), cls.ns)

    def test_a_listener_made_here_by_this_uid_is_the_rigs_own(self):
        import socket
        with tempfile.TemporaryDirectory(dir="/tmp") as d:
            path = os.path.join(d, "X0")
            srv = socket.socket(socket.AF_UNIX)
            srv.bind(path)
            srv.listen(1)
            try:
                self.assertEqual(self.ns["x_socket_state"](path, self.ns["own_listening_sockets"]()), "OWN-LISTENER")
            finally:
                srv.close()

    def test_a_file_or_a_dead_socket_at_the_path_is_not(self):
        import socket
        with tempfile.TemporaryDirectory(dir="/tmp") as d:
            plain = os.path.join(d, "X0")
            open(plain, "w").close()
            dead = os.path.join(d, "X1")
            srv = socket.socket(socket.AF_UNIX)
            srv.bind(dead)
            srv.close()
            listening = self.ns["own_listening_sockets"]()
            self.assertEqual(self.ns["x_socket_state"](plain, listening), "EXISTS")
            self.assertEqual(self.ns["x_socket_state"](dead, listening), "EXISTS")
            self.assertEqual(self.ns["x_socket_state"](os.path.join(d, "X2"), listening), "ABSENT")

    def test_a_listener_owned_by_another_uid_is_not(self):
        import types
        fake_os = types.SimpleNamespace(
            lstat=lambda p: types.SimpleNamespace(st_mode=stat.S_IFSOCK | 0o755, st_uid=65534),
            getuid=lambda: 1000)
        listening = {"/tmp/.X11-unix/X0"}
        with mock.patch.dict(self.ns, {"os": fake_os}):
            self.assertEqual(self.ns["x_socket_state"]("/tmp/.X11-unix/X0", listening), "EXISTS")
            fake_os.getuid = lambda: 65534
            self.assertEqual(self.ns["x_socket_state"]("/tmp/.X11-unix/X0", listening), "OWN-LISTENER")

    def test_a_socket_of_this_uid_with_no_listener_here_is_not(self):
        import types
        fake_os = types.SimpleNamespace(
            lstat=lambda p: types.SimpleNamespace(st_mode=stat.S_IFSOCK | 0o755, st_uid=1000),
            getuid=lambda: 1000)
        with mock.patch.dict(self.ns, {"os": fake_os}):
            self.assertEqual(self.ns["x_socket_state"]("/tmp/.X11-unix/X0", set()), "EXISTS")

    def test_an_abstract_entry_is_not_the_listener_of_the_path(self):
        header = "Num       RefCount Protocol Flags    Type St Inode Path\n"
        table = (header
                 + "0000: 00000002 00000000 00010000 0001 01 1 @/tmp/.X11-unix/X0\n"
                 + "0000: 00000002 00000000 00010000 0001 01 2 /tmp/.X11-unix/X1\n"
                 + "0000: 00000003 00000000 00000000 0001 03 3 /tmp/.X11-unix/X2\n")
        with mock.patch.dict(self.ns, {"open": lambda p: io.StringIO(table)}):
            listening = self.ns["own_listening_sockets"]()
        self.assertEqual(listening, {"@/tmp/.X11-unix/X0", "/tmp/.X11-unix/X1"})
        self.assertNotIn("/tmp/.X11-unix/X0", listening)
        self.assertNotIn("/tmp/.X11-unix/X2", listening)

    def judge(self, kind, host_paths, x_sockets):
        probe = {
            "canary_paths": {}, "canary_found_anywhere": [], "canary_search_control": True,
            "home_listing": "NO SUCH DIRECTORY", "uid": 1000, "uid_map": ["0", "1", "65536"],
            "cap_eff": "0", "cap_bnd": "0", "no_new_privs": "1", "seccomp": "2", "env_leaks": [],
            "process_env_leaks": [], "interfaces": ["lo"], "network": {},
            "host_paths": host_paths, "x_sockets": x_sockets, "dev": [], "mount_tmpfs": "EPERM",
            "setuid_0": "EPERM", "ptrace_init": "EPERM", "reboot": "EPERM", "userns": {},
            "write_outside": {}, "write_allowed": {}, "harness_replaced_by_commit": False,
        }
        with tempfile.TemporaryDirectory() as work:
            out = os.path.join(work, "out")
            unit = os.path.join(out, "script" if kind == "probe-rig" else "unit-bridge")
            os.makedirs(unit)
            for path, data in ((os.path.join(unit, "probe.json"), probe), (os.path.join(out, "summary.json"), {}),
                               (os.path.join(work, "targets.json"), {})):
                with open(path, "w") as f:
                    json.dump(data, f)
            r = subprocess.run(["python3", os.path.join(self.HOSTILE, "judge.py"), work, kind, out],
                               capture_output=True, text=True, timeout=30)
        self.assertEqual(r.returncode, 0, r.stderr)
        verdicts = {}
        for line in r.stdout.splitlines():
            f = line.split("\t")
            if f[0] in ("PASS", "FAIL") and ("X socket" in f[1] or "session bus" in f[1]):
                verdicts[f[1][:24]] = f[0]
        return verdicts

    def test_the_rig_step_passes_with_its_own_x_socket_only(self):
        v = self.judge("probe-rig", {"/tmp/.X11-unix/X0": "OWN-LISTENER", "listing /tmp/.X11-unix": ["X0"]},
                       {"X0": "OWN-LISTENER"})
        self.assertEqual(set(v.values()), {"PASS"}, v)
        self.assertEqual(len(v), 2, v)

    def test_the_rig_step_fails_on_an_x_socket_that_is_not_its_own(self):
        v = self.judge("probe-rig", {"/tmp/.X11-unix/X0": "OWN-LISTENER", "/tmp/.X11-unix/X1": "EXISTS"},
                       {"X0": "OWN-LISTENER", "X1": "EXISTS"})
        self.assertEqual(set(v.values()), {"FAIL"}, v)
        v = self.judge("probe-rig", {"/tmp/.X11-unix/X0": "EXISTS"}, {"X0": "EXISTS"})
        self.assertIn("FAIL", v.values())

    def test_the_tests_step_fails_on_any_x_socket(self):
        v = self.judge("probe", {"/tmp/.X11-unix/X0": "OWN-LISTENER"}, {"X0": "OWN-LISTENER"})
        self.assertEqual(set(v.values()), {"FAIL"}, v)
        self.assertEqual(len(v), 2, v)


class Verdict(unittest.TestCase):
    """The host takes the verdict; the container's streams are capped on the way."""

    @classmethod
    def setUpClass(cls):
        with open(SANDBOX) as f:
            cls.script = f.read()

    def test_stdout_is_cut_by_head_at_the_cap(self):
        self.assertIn("head -c $((SB_MAX_RESULT + 1))", self.script)

    def test_stderr_goes_through_the_filter(self):
        self.assertIn("2>&1 1>&4 | python3 \"$SB_DIR/sandbox.d/filter-stderr.py\" >&2", self.script)

    def test_the_exit_code_is_podmans_and_not_a_file_from_the_container(self):
        self.assertIn('PIPESTATUS[0]', self.script)
        self.assertIn("{{.State.ExitCode}}", self.script)
        with open(os.path.join(ROOT, "dev", "sandbox.d", "inside.sh")) as f:
            inside = f.read()
        self.assertNotIn("results.tsv", inside.replace("# ", ""))
        self.assertNotIn("summary.json", inside.replace("# ", ""))

    def test_the_host_writes_the_verdict_files(self):
        body = self.script.split("write_verdict() {")[1].split("PY\n}")[0]
        self.assertIn("results.tsv", body)
        self.assertIn("summary.json", body)

    def test_a_result_cannot_replace_the_verdict_files(self):
        # the verdict files are in the run's directory; a unit's files go one level down
        body = self.script.split("write_verdict() {")[1].split("PY\n}")[0]
        self.assertIn("os.path.join(out, 'results.tsv')", body)
        self.assertIn('"$out/$unit"', self.script)

    def test_the_member_count_is_capped(self):
        self.assertIn("SB_MAX_MEMBERS=20000", self.script)

    def test_the_result_cap_must_be_a_number(self):
        r = subprocess.run(
            ["bash", SANDBOX, "build"],
            capture_output=True,
            text=True,
            timeout=60,
            env={"PATH": os.environ.get("PATH", "/usr/bin:/bin"), "HOME": os.environ.get("HOME", "/nonexistent"), "SANDBOX_MAX_RESULT": "$(id)"},
        )
        self.assertNotEqual(r.returncode, 0)


FILTER = os.path.join(ROOT, "dev", "sandbox.d", "filter-stderr.py")
SECCOMP = os.path.join(ROOT, "dev", "sandbox.d", "seccomp.py")


def filtered(data):
    return subprocess.run(["python3", FILTER], input=data, capture_output=True, timeout=60).stdout


class StderrFilter(unittest.TestCase):
    def test_control_bytes_are_dropped_and_text_stays(self):
        out = filtered("\x1b]0;title\x07\x1b[2Jtext\roverwrite\u009b\u202e\x00\nnext\tline\n".encode())
        text = out.decode()
        for c in ("\x1b", "\x07", "\r", "\u009b", "\u202e", "\x00"):
            self.assertNotIn(c, text)
        self.assertIn("text", text)
        self.assertIn("next\tline", text)

    def test_a_long_line_is_cut(self):
        out = filtered(b"A" * 100000 + b"\nshort\n")
        longest = max(len(l) for l in out.split(b"\n"))
        self.assertLess(longest, 4200)
        self.assertIn(b"short", out)

    def test_a_flood_is_cut_at_the_total(self):
        data = (b"A" * 99 + b"\n") * (200 * 1024) + b"AFTER\n"
        out = filtered(data)
        self.assertLessEqual(len(out), 16 * 1024 * 1024 + 100)
        self.assertIn(b"[further output dropped]", out)
        self.assertNotIn(b"AFTER", out)

    def test_a_flood_without_a_newline_is_one_short_line(self):
        out = filtered(b"A" * (20 * 1024 * 1024) + b"\nAFTER\n")
        self.assertLess(len(out), 5000)
        self.assertIn(b"AFTER", out)

    def test_a_multibyte_character_split_across_reads_survives(self):
        out = filtered(("é" * 70000 + "\n").encode())
        self.assertNotIn("\ufffd", out.decode())


class Seccomp(unittest.TestCase):
    def profile(self, *rules):
        import importlib.util

        spec = importlib.util.spec_from_file_location("seccomp", SECCOMP)
        mod = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(mod)
        base = {"defaultAction": "SCMP_ACT_ERRNO", "syscalls": list(rules)}
        return mod, mod.without_new_user_namespaces(base)

    def names(self, profile, action):
        return [n for r in profile["syscalls"] if r["action"] == action and "args" not in r for n in r["names"]]

    def test_clone_and_unshare_are_allowed_only_without_the_user_namespace_flag(self):
        import platform

        if platform.machine() != "x86_64":
            self.skipTest("written for x86_64")
        _, p = self.profile({"names": ["read", "clone", "clone3", "unshare"], "action": "SCMP_ACT_ALLOW"})
        self.assertEqual(self.names(p, "SCMP_ACT_ALLOW"), ["read"])
        conditional = [r for r in p["syscalls"] if "args" in r]
        self.assertEqual(len(conditional), 1)
        self.assertEqual(sorted(conditional[0]["names"]), ["clone", "unshare"])
        arg = conditional[0]["args"][0]
        self.assertEqual((arg["index"], arg["value"], arg["valueTwo"], arg["op"]), (0, 0x10000000, 0, "SCMP_CMP_MASKED_EQ"))
        self.assertEqual([r for r in p["syscalls"] if r["names"] == ["clone3"]][0]["errnoRet"], 38)

    def test_the_real_default_profile_keeps_no_unconditional_clone(self):
        import platform

        path = "/usr/share/containers/seccomp.json"
        if platform.machine() != "x86_64" or not os.path.exists(path):
            self.skipTest("no default profile here")
        import json

        mod, _ = self.profile()
        with open(path) as f:
            p = mod.without_new_user_namespaces(json.load(f))
        for r in p["syscalls"]:
            if r["action"] == "SCMP_ACT_ALLOW" and "args" not in r:
                self.assertFalse(set(r["names"]) & {"clone", "clone3", "unshare"}, r["names"])


READ_RESULT = os.path.join(ROOT, "dev", "sandbox.d", "read_result.py")
REENCODE = os.path.join(ROOT, "dev", "sandbox.d", "reencode.py")


def tar_of(members):
    """members: name -> bytes (a file), None (a directory), ("link", target), or ("fifo",)."""
    buf = io.BytesIO()
    with tarfile.open(fileobj=buf, mode="w") as t:
        for name, what in members.items():
            info = tarfile.TarInfo(name)
            if what is None:
                info.type = tarfile.DIRTYPE
                info.mode = 0o755
                t.addfile(info)
            elif isinstance(what, tuple) and what[0] == "link":
                info.type = tarfile.SYMTYPE
                info.linkname = what[1]
                t.addfile(info)
            elif isinstance(what, tuple) and what[0] == "fifo":
                info.type = tarfile.FIFOTYPE
                t.addfile(info)
            else:
                info.size = len(what)
                t.addfile(info, io.BytesIO(what))
    return buf.getvalue()


def png(width, height, text=None):
    def chunk(kind, body):
        return struct.pack(">I", len(body)) + kind + body + struct.pack(">I", zlib.crc32(kind + body) & 0xFFFFFFFF)

    row = b"\x00" + b"\x10\x20\x30" * width
    deflate = zlib.compressobj()
    raw = b"".join([deflate.compress(row) for _ in range(height)] + [deflate.flush()])
    out = b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 2, 0, 0, 0))
    if text:
        out += chunk(b"tEXt", text)
    return out + chunk(b"IDAT", raw) + chunk(b"IEND", b"")


class ReadResult(unittest.TestCase):
    """read_result.py on tars a hostile unit could send."""

    def read(self, members, *extra, label="unit-bridge", limit=1 << 30, max_members=20000):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        root = os.path.join(self.tmp.name, "out")
        dest = os.path.join(root, label)
        os.makedirs(dest)
        archive = os.path.join(self.tmp.name, "r.tar")
        with open(archive, "wb") as f:
            f.write(tar_of(members) if isinstance(members, dict) else members)
        r = subprocess.run(["python3", READ_RESULT, archive, dest, root, label, str(limit), str(max_members), *extra],
                           capture_output=True, text=True, timeout=60)
        skipped = os.path.join(root, "SKIPPED.txt")
        self.skipped = ""
        if os.path.exists(skipped):
            with open(skipped) as f:
                self.skipped = f.read()
        self.root, self.dest = root, dest
        return r

    def on_disk(self):
        found = []
        for r, dirs, files in os.walk(self.dest):
            found += [os.path.relpath(os.path.join(r, n), self.dest) for n in dirs + files]
        return sorted(found)

    def test_an_ordinary_tree_arrives(self):
        r = self.read({"./": None, "./logs": None, "./logs/unit.log": b"ok\n", "./notes/a.txt": b"x"})
        self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
        with open(os.path.join(self.dest, "logs", "unit.log"), "rb") as f:
            self.assertEqual(f.read(), b"ok\n")
        self.assertTrue(os.path.isfile(os.path.join(self.dest, "notes", "a.txt")))
        self.assertEqual(self.skipped, "")

    def test_a_refused_name_ending_in_a_newline_is_listed_as_its_repr_without_the_dot_slash(self):
        self.read({"./x\n": b"x", "./CLAUDE.md\n": b"x", "./fine/ok.txt": b"ok"})
        self.assertEqual(self.on_disk(), ["fine", "fine/ok.txt"])
        self.assertIn("unit-bridge: 'x\\n': name\n", self.skipped)
        self.assertIn("unit-bridge: 'CLAUDE.md\\n': name\n", self.skipped)

    def test_a_result_tree_never_holds_what_git_a_shell_or_an_agent_acts_on(self):
        hostile = {
            ".git/config": b"[core]\n\tfsmonitor = touch /tmp/x\n", ".git/HEAD": b"ref: refs/heads/main\n", ".git": None,
            ".envrc": b"x", "CLAUDE.md": b"x", "claude.MD": b"x", "Agents.md": b"x", "GEMINI.md": b"x", ".claude/settings.json": b"{}",
            "mise.toml": b"x", ".tool-versions": b"x", "conftest.py": b"x", "HEAD": b"ref: refs/heads/main\n", "objects/x": b"x",
            "refs/x": b"x", "sub/.hidden": b"x", "-rf": b"x", "_underscore": b"x", "fine/ok.txt": b"ok",
            "x\n": b"x", "CLAUDE.md\n": b"x", "mise.local.toml\n": b"x", "ok\n/inner": b"x",
        }
        self.read(hostile)
        self.assertEqual(self.on_disk(), ["fine", "fine/ok.txt"])
        for name in (".git/config", ".envrc", "CLAUDE.md", "claude.MD", "Agents.md", "GEMINI.md", ".claude/settings.json", "mise.toml",
                     ".tool-versions", "conftest.py", "refs/x", "objects/x", "sub/.hidden", "-rf", "'x\\n'", "'CLAUDE.md\\n'", "'mise.local.toml\\n'"):
            self.assertIn(name, self.skipped)
        env = {"PATH": os.environ.get("PATH", "/usr/bin"), "GIT_CEILING_DIRECTORIES": self.tmp.name}
        for d in (self.root, self.dest):
            self.assertNotEqual(subprocess.run(["git", "-C", d, "rev-parse", "--git-dir"], capture_output=True, env=env).returncode, 0)

    def test_no_name_starts_with_anything_but_a_letter_or_digit(self):
        self.read({"-a": b"x", ".a": b"x", "_a": b"x", "@a": b"x", "a/-b": b"x", "a1": b"x"})
        self.assertEqual(self.on_disk(), ["a1"])

    def test_skipped_lists_a_names_as_escaped_text(self):
        self.read({"evil\x1b]0;OSC-TITLE\x07name": b"x", "bell\x07": b"x", "bidi\u202e": b"x", "carriage\rreturn": b"x"})
        self.assertNotRegex(self.skipped, "[\x00-\x08\x0b-\x1f\x7f\u202e]")
        self.assertIn("\\x1b]0;OSC-TITLE\\x07name", self.skipped)
        self.assertIn("unit-bridge: ", self.skipped)

    def test_only_regular_files_and_directories(self):
        self.read({"link": ("link", "/etc/passwd"), "fifo": ("fifo",), "dir/": None, "dir/file": b"x"})
        self.assertEqual(self.on_disk(), ["dir", "dir/file"])
        self.assertIn("'link'", self.skipped)
        self.assertIn("'fifo'", self.skipped)

    def test_the_member_cap_counts_directories_and_stops_the_read(self):
        r = self.read({f"d{i}/": None for i in range(50)}, max_members=20)
        self.assertEqual(r.returncode, 4)
        self.assertLessEqual(len(self.on_disk()), 20)
        self.assertIn("more than 20 members", self.skipped)

    def test_a_file_over_the_limit_is_not_written(self):
        self.read({"big": b"x" * 1000, "small": b"x"}, limit=500)
        self.assertEqual(self.on_disk(), ["small"])
        self.assertIn("too large", self.skipped)

    def test_a_cut_archive_is_reported(self):
        data = tar_of({"a": b"x" * 4000, "b": b"y" * 4000})
        r = self.read(data[:6500])
        self.assertEqual(r.returncode, 3)
        self.assertIn("stops early", self.skipped)

    def test_nothing_that_is_not_a_tar_is_read(self):
        r = self.read(b"not a tar at all")
        self.assertEqual(r.returncode, 3)
        self.assertEqual(self.on_disk(), [])

    def test_a_png_goes_to_the_quarantine_and_other_images_are_refused(self):
        quarantine = tempfile.mkdtemp()
        self.addCleanup(subprocess.run, ["rm", "-rf", quarantine])
        self.read({"shots/a.png": png(2, 2), "shots/b.JPG": b"\xff\xd8", "shots/c.svg": b"<svg/>", "shots/d.gif": b"GIF89a", "e.txt": b"x"},
                  "--png-dir", quarantine)
        self.assertEqual(self.on_disk(), ["e.txt"])
        self.assertTrue(os.path.isfile(os.path.join(quarantine, "shots", "a.png")))
        for name in ("b.JPG", "c.svg", "d.gif"):
            self.assertIn(name, self.skipped)

    def test_a_png_with_nowhere_to_be_re_encoded_is_dropped(self):
        self.read({"a.png": png(2, 2)})
        self.assertEqual(self.on_disk(), [])
        self.assertIn("nowhere to be re-encoded", self.skipped)

    def test_a_picture_that_does_not_come_back_from_the_re_encode_is_listed(self):
        sent = os.path.join(tempfile.mkdtemp(), "sent")
        os.makedirs(os.path.join(sent, "shots"))
        for n in ("good.png", "bad.png"):
            with open(os.path.join(sent, "shots", n), "wb") as f:
                f.write(b"x")
        self.read({"shots/good.png": png(2, 2), "shots/notes.txt": b"x", "shots/ghost.jpg": b"x"}, "--only-png", "--expect", sent)
        self.assertEqual(self.on_disk(), ["shots", "shots/good.png"])
        self.assertIn("'shots/bad.png'", self.skipped)
        self.assertNotIn("good.png", self.skipped)

    def test_a_re_encoded_picture_is_checked_again_and_keeps_image_chunks_only(self):
        good = png(2, 2, b"Comment\x00HOSTILE-TEXT")
        bad_crc = good[:-5] + b"\x01" + good[-4:]
        bomb = png(30000, 30000)
        trailing = png(2, 2) + b"extra"
        self.read({"ok.png": good, "crc.png": bad_crc, "bomb.png": bomb, "trail.png": trailing, "nothing.png": b"\x89PNG\r\n\x1a\n"},
                  "--only-png")
        self.assertEqual(self.on_disk(), ["ok.png"])
        with open(os.path.join(self.dest, "ok.png"), "rb") as f:
            data = f.read()
        self.assertNotIn(b"HOSTILE-TEXT", data)
        self.assertTrue(data.startswith(b"\x89PNG") and data.endswith(b"IEND\xaeB`\x82"))
        for name in ("crc.png", "bomb.png", "trail.png", "nothing.png"):
            self.assertIn(name, self.skipped)

    def test_a_video_is_refused_unless_it_is_the_assembled_one(self):
        webm = b"\x1a\x45\xdf\xa3" + b"\x00" * 64
        self.read({"a.webm": webm, "b.mp4": b"\x00\x00\x00\x18ftypmp42", "c.mkv": webm, "d.mp3": b"ID3", "e.txt": b"x"})
        self.assertEqual(self.on_disk(), ["e.txt"])
        for name in ("a.webm", "b.mp4", "c.mkv", "d.mp3"):
            self.assertIn(name, self.skipped)

    def test_only_a_webm_that_starts_as_one_comes_out_of_the_video_container(self):
        webm = b"\x1a\x45\xdf\xa3" + b"\x00" * 64
        self.read({"recording.webm": webm, "fake.webm": b"MZ not a video", "a.png": png(2, 2), "x.txt": b"x", "o.mp4": webm}, "--only-video")
        self.assertEqual(self.on_disk(), ["recording.webm"])
        for name in ("fake.webm", "a.png", "x.txt", "o.mp4"):
            self.assertIn(name, self.skipped)

    def test_mise_and_codex_instruction_names_are_refused(self):
        self.read({"mise/config.toml": b"x", "AGENTS.override.md": b"x", "mise.dev.toml": b"x", "fine/ok.txt": b"ok"})
        self.assertEqual(self.on_disk(), ["fine", "fine/ok.txt"])


class OutputPlace(unittest.TestCase):
    def test_a_git_directory_is_found_from_the_nearest_existing_ancestor(self):
        with open(SANDBOX) as f:
            text = f.read()
        func = "out_in_git() {" + text.split("out_in_git() {")[1].split("\n}\n")[0] + "\n}\n"
        with tempfile.TemporaryDirectory() as tmp:
            work = os.path.join(tmp, "work")
            bare = os.path.join(tmp, "bare")
            plain = os.path.join(tmp, "plain")
            for d in (work, bare, plain):
                os.makedirs(d)
            env = {"PATH": os.environ.get("PATH", "/usr/bin"), "GIT_CEILING_DIRECTORIES": tmp, "HOME": tmp}
            subprocess.run(["git", "init", "-q", work], check=True, env=env)
            os.makedirs(os.path.join(bare, "objects"))
            os.makedirs(os.path.join(bare, "refs"))
            with open(os.path.join(bare, "HEAD"), "w") as f:
                f.write("ref: refs/heads/main\n")

            def inside(path):
                r = subprocess.run(["bash", "-c", func + f'SB_HOME={tmp}; out_in_git "$1"', "x", path], env=env, capture_output=True)
                return r.returncode == 0

            self.assertTrue(inside(os.path.join(work, "results", "run")))
            self.assertTrue(inside(os.path.join(work, ".git")))
            self.assertTrue(inside(os.path.join(bare, "sub", "run")))
            self.assertFalse(inside(os.path.join(plain, "results", "run")))


class SandboxLock(unittest.TestCase):
    def test_verify_clean_waits_for_the_store_lock(self):
        r = subprocess.run(
            ["bash", os.path.join(ROOT, "dev", "sandbox-lock-test.sh")],
            capture_output=True,
            text=True,
            timeout=120,
        )
        self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
        self.assertIn("verify-clean waits for the lock and says so", r.stdout)
        self.assertIn("exit 0 after the release", r.stdout)

    def test_process_check_finds_this_stores_processes_and_no_others(self):
        with open(SANDBOX) as f:
            text = f.read()
        func = "store_processes_left() {" + text.split("store_processes_left() {")[1].split("\n}\n")[0] + "\n}\n"
        with tempfile.TemporaryDirectory() as tmp:
            store = os.path.join(tmp, "store")
            other = os.path.join(tmp, "other")

            def start(argv0):
                proc = subprocess.Popen(["bash", "-c", 'exec -a "$0" sleep 60', argv0])
                self.addCleanup(lambda: (proc.kill(), proc.wait()))
                deadline = time.time() + 5
                while time.time() < deadline:
                    with open(f"/proc/{proc.pid}/cmdline", "rb") as f:
                        if argv0.encode() in f.read():
                            return
                    time.sleep(0.02)
                self.fail(f"stand-in process did not start: {argv0}")

            def left(names, state, dev=()):
                script = (
                    f"SB_UID=$(id -u)\nSB_STATE=\"$STATE\"\npm() {{ printf '%s\\n' \"$PM_NAMES\"; }}\n"
                    f"dev_names() {{ printf '%s' \"$DEV_NAMES\"; }}\n{func}store_processes_left\n"
                )
                env = {**os.environ, "STATE": state, "PM_NAMES": "\n".join(names), "DEV_NAMES": "\n".join(dev)}
                r = subprocess.run(["bash"], input=script, capture_output=True, text=True, timeout=20, env=env)
                return r.stdout

            self.assertEqual(left([], store), "")
            start("conmon --name sceny-sandbox-deadbeef")
            self.assertIn("sceny-sandbox-deadbeef", left(["sceny-sandbox-deadbeef"], store))
            start("conmon --name sceny-sandbox-cafe0001")
            self.assertIn("sceny-sandbox-cafe0001", left(["sceny-sandbox-deadbeef", "sceny-sandbox-cafe0001"], store))
            start(f"podman --root {store}/storage run leaked")
            self.assertIn(f"{store}/storage run leaked", left([], store))
            start(f"podman --root {other}/storage run --name sceny-sandbox-0badf00d")
            self.assertNotIn("0badf00d", left(["sceny-sandbox-deadbeef"], store))
            self.assertNotIn(f"{other}/storage", left([], store))
            start(f"podman --root {store}-other/storage run sibling-leak")
            self.assertNotIn("sibling-leak", left([], store))
            start(f"holder {store}")
            self.assertIn(f"holder {store}", left([], store))
            start(f"conmon --name sceny-sandbox-feedbeef --root {store}/storage")
            self.assertEqual(left(["sceny-sandbox-feedbeef"], store).count("conmon --name sceny-sandbox-feedbeef"), 1)
            start(f"conmon --name sceny-sandbox-dev-0123abcd --root {store}/storage")
            self.assertIn("0123abcd", left([], store))
            self.assertNotIn("0123abcd", left([], store, dev=["sceny-sandbox-dev-0123abcd"]))
            for i, odd in enumerate(("c++ (x) {1} y?", "pipe|store")):
                root = os.path.join(tmp, odd)
                start(f"podman --root {root}/storage run odd-leak-{i}")
                self.assertIn(f"odd-leak-{i}", left([], root))


class SignalHandlingMechanism(unittest.TestCase):
    """Signal handling in dev/sandbox: pipelines backgrounded, traps include HUP."""

    @classmethod
    def setUpClass(cls):
        with open(SANDBOX) as f:
            cls.script = f.read()

    def test_each_head_pipeline_is_backgrounded_and_waited(self):
        """Every `| head -c ... >"$tarfile"` pipeline is backgrounded and waited for, except the git-archive read outside any container."""
        lines = self.script.splitlines()
        pipes = [i for i, line in enumerate(lines) if re.search(r'\| head -c .*>\s*"?\$tarfile"?', line)]
        self.assertGreaterEqual(len(pipes), 5, f"found {len(pipes)} tarfile pipelines, expected at least 5")
        foreground = [lines[i] for i in pipes if not lines[i].rstrip().endswith("&")]
        self.assertEqual(len(foreground), 1, f"foreground tarfile pipelines: {foreground}")
        self.assertIn("archive", foreground[0])
        for i in pipes:
            if lines[i].rstrip().endswith("&"):
                self.assertTrue(any(l.strip().startswith("wait ") for l in lines[i + 1:i + 4]), f"no wait after line {i + 1}: {lines[i]}")

    def test_trap_lines_include_hup(self):
        """Every `trap '... INT TERM'` line must also include HUP."""
        # Match trap lines that have INT TERM in the signal list
        lines_with_hup = re.findall(r"trap '[^']+' INT TERM HUP", self.script)
        self.assertGreaterEqual(len(lines_with_hup), 2, f"found {len(lines_with_hup)} trap lines with INT TERM HUP, expected at least 2")
        # Verify that all trap lines with INT TERM also have HUP
        all_trap_lines = re.findall(r"trap '[^']+'.*INT TERM(?!.*HUP)", self.script, re.MULTILINE)
        self.assertEqual(len(all_trap_lines), 0, f"trap lines missing HUP")

    def test_trap_resets_include_all_signals(self):
        """Every trap reset with multiple signals must include EXIT INT TERM HUP."""
        # Match all trap - lines that reset multiple signals
        resets = re.findall(r"^\s*trap - (.+)$", self.script, re.MULTILINE)
        self.assertGreaterEqual(len(resets), 2, f"found {len(resets)} trap resets, expected at least 2")
        for names in resets:
            self.assertEqual(set(names.split()), {"EXIT", "INT", "TERM", "HUP"}, f"trap reset is not EXIT INT TERM HUP: {names}")

    def test_dev_pull_takes_the_store_lock(self):
        body = re.search(r"^dev_pull\(\) \{\n(.*?)^\}", self.script, re.MULTILINE | re.DOTALL)
        self.assertIsNotNone(body)
        self.assertIn("store_lock_acquire", body.group(1))


class Reencode(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        spec = importlib.util.spec_from_file_location("reencode", REENCODE)
        try:
            cls.mod = importlib.util.module_from_spec(spec)
            spec.loader.exec_module(cls.mod)
        except (ImportError, ValueError) as e:
            raise unittest.SkipTest(f"no GdkPixbuf here: {e}")

    def write(self, data):
        d = tempfile.mkdtemp()
        path = os.path.join(d, "a.png")
        with open(path, "wb") as f:
            f.write(data)
        return path

    def test_the_header_limits_come_before_any_decoding(self):
        self.assertEqual(self.mod.decode(self.write(png(30000, 1)[:60]), "/nonexistent/x.png"), "picture too large (30000x1)")
        self.assertEqual(self.mod.decode(self.write(b"GIF89a" + b"\0" * 40), "/nonexistent/x.png"), "not a PNG")
        self.assertEqual(self.mod.decode(self.write(png(8000, 8000)[:60]), "/nonexistent/x.png"), "picture too large (8000x8000)")

    def test_a_good_picture_comes_back_without_its_text(self):
        out = os.path.join(tempfile.mkdtemp(), "b.png")
        self.assertIsNone(self.mod.decode(self.write(png(4, 4, b"Comment\x00HOSTILE-TEXT")), out))
        with open(out, "rb") as f:
            data = f.read()
        self.assertTrue(data.startswith(b"\x89PNG"))
        self.assertNotIn(b"HOSTILE-TEXT", data)


class BuildContext(unittest.TestCase):
    def test_a_failed_build_removes_its_context(self):
        with tempfile.TemporaryDirectory() as tmp:
            state = os.path.join(tmp, "state")
            repo = os.path.join(tmp, "repo")
            os.makedirs(os.path.join(repo, "dev", "sandbox.d"))
            shutil.copy(SANDBOX, os.path.join(repo, "dev", "sandbox"))
            shutil.copy(
                os.path.join(ROOT, "dev", "sandbox.d", "Containerfile"),
                os.path.join(repo, "dev", "sandbox.d", "Containerfile"),
            )
            git_env = {"PATH": os.environ.get("PATH", "/usr/bin:/bin"), "HOME": tmp, "GIT_CONFIG_GLOBAL": "/dev/null", "GIT_CONFIG_SYSTEM": "/dev/null"}
            subprocess.run(["git", "-C", repo, "init", "-q"], check=True, env=git_env)
            subprocess.run(["git", "-C", repo, "add", "dev"], check=True, env=git_env)
            subprocess.run(
                ["git", "-C", repo, "-c", "user.name=test", "-c", "user.email=test@example.invalid", "commit", "-q", "-m", "build context"],
                check=True,
                env=git_env,
            )
            script = (
                f'source "{os.path.join(repo, "dev", "sandbox")}"\n'
                "require_tools() { :; }\n"
                "pm() { return 1; }\n"
                "cmd_build --ref HEAD --profile devices\n"
            )
            r = subprocess.run(
                ["bash", "-c", script],
                capture_output=True,
                text=True,
                timeout=60,
                env={"PATH": os.environ.get("PATH", "/usr/bin:/bin"), "HOME": tmp, "SANDBOX_STATE": state},
            )
            self.assertEqual(r.returncode, 2, r.stdout + r.stderr)
            self.assertIn("the base image did not build", r.stderr)
            left = [n for n in os.listdir(os.path.join(state, "builds")) if n.startswith("sceny-sandbox-build.")]
            self.assertEqual(left, [], "a failed build leaves its context behind")


class StaleRuns(unittest.TestCase):
    def script(self, make_archive):
        return (
            f'source "{SANDBOX}"\n'
            "require_tools() { :; }\n"
            "pm() { return 0; }\n"
            f"make_archive() {{ {make_archive}; }}\n"
            f"cmd_run {REPO} {GOOD_SHA} --steps tests --harness pr\n"
        )

    def test_a_run_killed_by_sigkill_is_cleared_by_the_next_run(self):
        with tempfile.TemporaryDirectory() as tmp:
            state = os.path.join(tmp, "state")
            runs = os.path.join(state, "runs")
            env = {"PATH": os.environ.get("PATH", "/usr/bin:/bin"), "HOME": tmp, "SANDBOX_STATE": state}
            killed = subprocess.Popen(
                ["bash", "-c", self.script("sleep 60")],
                env=env,
                start_new_session=True,
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
            )

            def reap():
                try:
                    os.killpg(killed.pid, signal.SIGKILL)
                except ProcessLookupError:
                    pass
                killed.wait()

            self.addCleanup(reap)
            deadline = time.time() + 20
            while not (os.path.isdir(runs) and os.listdir(runs)):
                self.assertLess(time.time(), deadline, "the run did not make its directory")
                time.sleep(0.05)
            os.killpg(killed.pid, signal.SIGKILL)
            killed.wait()
            left = os.listdir(runs)
            self.assertEqual(len(left), 1, "a run killed by SIGKILL leaves its directory")

            r = subprocess.run(
                ["bash", "-c", self.script("exit 3")],
                capture_output=True,
                text=True,
                timeout=60,
                env=env,
            )
            self.assertEqual(r.returncode, 3, r.stdout + r.stderr)
            self.assertIn("removed the directory of a run that did not finish", r.stderr)
            self.assertEqual(os.listdir(runs), [], "the next run leaves no directory of the killed run")

    def test_every_run_clears_killed_runs_under_the_store_lock(self):
        with open(SANDBOX) as f:
            script = f.read()
        for name in ("cmd_run", "dev_pull"):
            body = re.search(r"^" + name + r"\(\) \{\n(.*?)^\}", script, re.MULTILINE | re.DOTALL)
            self.assertIsNotNone(body, name)
            self.assertIn("store_lock_acquire\n  clear_stale_runs\n", body.group(1), name)


def sandbox_runroot(state=None):
    env = {"PATH": os.environ.get("PATH", "/usr/bin:/bin"), "HOME": tempfile.gettempdir()}
    if state is not None:
        env["SANDBOX_STATE"] = state
    r = subprocess.run(
        ["bash", "-c", f'source "{SANDBOX}"\necho "RUNROOT=$SB_RUNTIME"\n'],
        capture_output=True,
        text=True,
        timeout=60,
        env=env,
    )
    assert r.returncode == 0, r.stderr
    return re.search(r"^RUNROOT=(\S+)$", r.stdout, re.MULTILINE).group(1)


class ThrowawayRunroot(unittest.TestCase):
    def test_a_throwaway_store_keeps_its_runroot_inside_itself(self):
        self.assertEqual(sandbox_runroot(), f"/run/user/{os.getuid()}/sceny-sandbox", "the owner's runroot is unchanged")
        self.assertEqual(sandbox_runroot("/tmp/throwaway-store-a"), "/tmp/throwaway-store-a/runroot")


@unittest.skipUnless(shutil.which("podman"), "verify-clean on a real podman needs podman")
class ThrowawayStoreVerifyClean(unittest.TestCase):
    def test_verify_clean_passes_on_a_throwaway_store(self):
        state = tempfile.mkdtemp(prefix="sceny-sandbox-verify-")
        self.addCleanup(shutil.rmtree, state, True)
        r = subprocess.run(
            ["bash", SANDBOX, "verify-clean"],
            capture_output=True,
            text=True,
            timeout=300,
            env={"PATH": os.environ.get("PATH", "/usr/bin:/bin"), "HOME": tempfile.gettempdir(), "SANDBOX_STATE": state},
        )
        self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
        self.assertIn("no container (running or stopped)", r.stdout + r.stderr)


class DevelopRunsNeedACurrentImage(unittest.TestCase):
    def run_cmd(self, built=None, harness="develop"):
        tmp = tempfile.mkdtemp(prefix="sceny-sandbox-harness-")
        self.addCleanup(shutil.rmtree, tmp, True)
        repo = os.path.join(tmp, "repo")
        os.makedirs(repo)
        env = {
            "PATH": os.environ.get("PATH", "/usr/bin:/bin"),
            "HOME": tmp,
            "SANDBOX_STATE": os.path.join(tmp, "state"),
            "GIT_AUTHOR_NAME": "t",
            "GIT_AUTHOR_EMAIL": "t@example.invalid",
            "GIT_COMMITTER_NAME": "t",
            "GIT_COMMITTER_EMAIL": "t@example.invalid",
        }
        subprocess.run(["git", "init", "-q", repo], check=True, env=env)
        subprocess.run(["git", "-C", repo, "-c", "user.name=t", "-c", "user.email=t@example.invalid",
                        "commit", "-q", "--allow-empty", "-m", "develop"], check=True, env=env)
        develop = subprocess.run(
            ["git", "-C", repo, "rev-parse", "HEAD"], capture_output=True, text=True, check=True, env=env
        ).stdout.strip()
        subprocess.run(["git", "-C", repo, "update-ref", "refs/remotes/origin/develop", develop], check=True, env=env)
        script = (
            f'source "{SANDBOX}"\n'
            f'SB_REPO_ROOT="{repo}"\n'
            "require_tools() { :; }\n"
            f"pm() {{ case \"$1 $2\" in 'image inspect') printf '%s' '{built or develop}' ;; esac; }}\n"
            "make_archive() { echo reached >&2; exit 5; }\n"
            f"cmd_run {REPO} {GOOD_SHA} --steps tests --harness {harness}\n"
        )
        return subprocess.run(["bash", "-c", script], capture_output=True, text=True, timeout=60, env=env)

    def test_a_develop_run_on_an_image_of_an_older_develop_is_refused(self):
        r = self.run_cmd(built="b" * 40)
        self.assertEqual(r.returncode, 2, r.stdout + r.stderr)
        self.assertIn("run 'dev/sandbox build --profile devices'", r.stderr)
        self.assertNotIn("reached", r.stderr)

    def test_a_develop_run_on_the_image_of_develop_goes_on(self):
        r = self.run_cmd()
        self.assertEqual(r.returncode, 5, r.stdout + r.stderr)
        self.assertIn("reached", r.stderr)

    def test_a_pr_run_does_not_depend_on_the_image_harness(self):
        r = self.run_cmd(built="b" * 40, harness="pr")
        self.assertEqual(r.returncode, 5, r.stdout + r.stderr)
        self.assertIn("reached", r.stderr)


class LiveDevSessionsAreNotLeftovers(unittest.TestCase):
    def verify_clean(self, all_names, dev_names):
        state = tempfile.mkdtemp(prefix="sceny-sandbox-devs-")
        self.addCleanup(shutil.rmtree, state, True)
        script = (
            f'source "{SANDBOX}"\n'
            "require_tools() { :; }\n"
            "pm() {\n"
            '  case "$1 $2 $3" in\n'
            '  "ps --filter "*) printf \'%s\' "$DEV_NAMES" ;;\n'
            '  "ps -a --format"*) printf \'%s\' "$ALL_NAMES" ;;\n'
            '  "image exists"*) return 1 ;;\n'
            "  *) ;;\n"
            "  esac\n"
            "}\n"
            "cmd_verify_clean\n"
        )
        env = {
            "PATH": os.environ.get("PATH", "/usr/bin:/bin"),
            "HOME": tempfile.gettempdir(),
            "SANDBOX_STATE": state,
            "ALL_NAMES": all_names,
            "DEV_NAMES": dev_names,
        }
        return subprocess.run(["bash", "-c", script], capture_output=True, text=True, timeout=120, env=env)

    def test_a_live_dev_session_is_kept_and_not_counted(self):
        dev = "sceny-sandbox-dev-98cb55db"
        r = self.verify_clean(dev, dev)
        self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
        self.assertIn(f"not counted, live dev sessions of their owners: {dev}", r.stderr)

    def test_a_run_left_beside_a_live_dev_session_is_still_counted(self):
        dev = "sceny-sandbox-dev-98cb55db"
        r = self.verify_clean(f"{dev}\nsceny-sandbox-1f2e3d4c", dev)
        self.assertEqual(r.returncode, 1, r.stdout + r.stderr)
        self.assertIn("containers left: sceny-sandbox-1f2e3d4c ", r.stderr)
        self.assertNotIn("containers left: sceny-sandbox-dev", r.stderr)

    def test_a_stopped_dev_session_is_still_counted(self):
        r = self.verify_clean("sceny-sandbox-dev-aaaaaaaa", "")
        self.assertEqual(r.returncode, 1, r.stdout + r.stderr)
        self.assertIn("containers left: sceny-sandbox-dev-aaaaaaaa ", r.stderr)


class StoreLockIsNotInherited(unittest.TestCase):
    def probe(self, pm_text):
        with tempfile.TemporaryDirectory() as state:
            script = (
                "SB_UID=$(id -u)\nSB_HOME=$HOME\nSB_RUNTIME=$HOME/runtime\n"
                f'SB_STATE="{state}"\n'
                'env() { while [[ $1 != podman ]]; do shift; done; shift; podman "$@"; }\n'
                'podman() { if [[ -e /proc/$BASHPID/fd/9 ]]; then echo open; else echo closed; fi; }\n'
                'exec 9>>"$SB_STATE/.lock"\n'
                f"{pm_text}pm run\n"
            )
            r = subprocess.run(["bash", "-c", script], capture_output=True, text=True, timeout=30)
            return r.stdout.strip(), r.stderr

    def test_podman_gets_no_store_lock_descriptor(self):
        with open(SANDBOX) as f:
            text = f.read()
        pm = "pm() {" + text.split("\npm() {")[1].split("\n}\n")[0] + "\n}\n"
        self.assertEqual(self.probe(pm.replace(" 9>&-", ""))[0], "open")
        self.assertEqual(self.probe(pm)[0], "closed")


class DevStopEndsOnlyTheNamedSession(unittest.TestCase):
    """`dev stop` ends the one session it names: another agent's session is its work in progress."""

    ONE = "sceny-sandbox-dev-0123abcd"
    TWO = "sceny-sandbox-dev-98cb55db"

    def stop(self, names, *args):
        state = tempfile.mkdtemp(prefix="sceny-sandbox-stop-")
        self.addCleanup(shutil.rmtree, state, True)
        log = os.path.join(state, "pm.log")
        script = (
            f'source "{SANDBOX}"\n'
            "require_tools() { :; }\n"
            "pm() {\n"
            '  case "$1" in\n'
            "  ps) printf '%s' \"$DEV_NAMES\" ;;\n"
            '  *) echo "$*" >>"$PM_LOG" ;;\n'
            "  esac\n"
            "}\n"
            f"cmd_dev {shlex.join(args)}\n"
        )
        env = {
            "PATH": os.environ.get("PATH", "/usr/bin:/bin"),
            "HOME": tempfile.gettempdir(),
            "SANDBOX_STATE": state,
            "DEV_NAMES": "\n".join(names),
            "PM_LOG": log,
        }
        r = subprocess.run(["bash", "-c", script], capture_output=True, text=True, timeout=60, env=env)
        removed = []
        if os.path.exists(log):
            with open(log) as f:
                removed = f.read().splitlines()
        return r, removed

    def test_a_bare_stop_refuses_even_with_one_session(self):
        r, removed = self.stop([self.ONE], "stop")
        self.assertEqual(r.returncode, 2, r.stdout + r.stderr)
        self.assertIn("dev status", r.stderr)
        self.assertEqual(removed, [])

    def test_stop_all_is_refused_and_stops_nothing(self):
        r, removed = self.stop([self.ONE, self.TWO], "--session", "0123abcd", "stop", "--all")
        self.assertEqual(r.returncode, 2, r.stdout + r.stderr)
        self.assertIn("dev status", r.stderr)
        self.assertEqual(removed, [])

    def test_stop_ends_its_own_session_and_no_other(self):
        r, removed = self.stop([self.ONE, self.TWO], "--session", "0123abcd", "stop")
        self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
        self.assertEqual(removed, [f"rm -f -v -t 0 {self.ONE}"])

    def test_a_session_already_gone_is_not_an_error(self):
        r, removed = self.stop([self.TWO], "--session", "0123abcd", "stop")
        self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
        self.assertIn("no session 0123abcd", r.stdout + r.stderr)
        self.assertEqual(removed, [])

    def test_the_id_is_eight_hex_digits(self):
        for bad in ("0123abc", "0123ABCD", "0123abcd-x", "../0123"):
            with self.subTest(session=bad):
                r, removed = self.stop([self.ONE], "--session", bad, "stop")
                self.assertEqual(r.returncode, 2, r.stdout + r.stderr)
                self.assertEqual(removed, [])


if __name__ == "__main__":
    unittest.main()
