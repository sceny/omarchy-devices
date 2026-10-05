"""What a device can do (kdeconnect-bridge features) and the fixes that act on
one device. The device and adb are replaced; every dump here is made up."""

import importlib.machinery
import importlib.util
import os
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
BRIDGE = os.path.join(HERE, "..", "bin", "kdeconnect-bridge")
loader = importlib.machinery.SourceFileLoader("kdeconnect_bridge_features", BRIDGE)
spec = importlib.util.spec_from_loader("kdeconnect_bridge_features", loader)
bridge = importlib.util.module_from_spec(spec)
loader.exec_module(bridge)

DUMP = """Packages:
  Package [org.kde.kdeconnect_tp] (abc):
    install permissions:
      android.permission.INTERNET: granted=true
    User 0: ceDataInode=1 installed=true
      runtime permissions:
        android.permission.READ_SMS: granted=true, flags=[ USER_SET ]
        android.permission.SEND_SMS: granted=true, flags=[ USER_SET ]
        android.permission.READ_CONTACTS: granted=false, flags=[ ]
        android.permission.READ_PHONE_STATE: granted=true, flags=[ USER_SET ]
        android.permission.READ_CALL_LOG: granted=true, flags=[ USER_SET ]
      disabledComponents:
    User 150: ceDataInode=0 installed=false
      runtime permissions:
        android.permission.READ_CONTACTS: granted=true, flags=[ ]
"""


class FakePhone:
    """adb shell answers from a made-up phone; records what was run."""
    def __init__(self, listener=True, files=True, dump=DUMP):
        self.ran, self.listener, self.files, self.dump = [], listener, files, dump

    def __call__(self, args, timeout=10):
        self.ran.append(args)
        if args[:1] == ["am"]:
            return 0, "0\n"
        if args[:2] == ["dumpsys", "package"]:
            return 0, self.dump
        if args[:1] == ["settings"]:
            return 0, ("other/x.Listener:" + bridge.LISTENER) if self.listener else "other/x.Listener"
        if args[:2] == ["appops", "get"]:
            return 0, "MANAGE_EXTERNAL_STORAGE: %s; time=+1h ago" % ("allow" if self.files else "default")
        if args[:3] == ["cmd", "notification", "allow_listener"]:
            self.listener = True
        if args[:2] == ["appops", "set"]:
            self.files = True
        if args[:2] == ["pm", "grant"]:
            self.dump = self.dump.replace("android.permission.READ_CONTACTS: granted=false", "android.permission.READ_CONTACTS: granted=true", 1)
        return 0, ""


class Permissions(unittest.TestCase):
    def test_one_user_of_several(self):
        self.assertEqual(bridge.parse_runtime_permissions(DUMP, 0)["android.permission.READ_CONTACTS"], False)
        self.assertEqual(bridge.parse_runtime_permissions(DUMP, 150)["android.permission.READ_CONTACTS"], True, "the work profile apart")
        self.assertNotIn("android.permission.INTERNET", bridge.parse_runtime_permissions(DUMP, 0), "install permissions are not runtime ones")

    def test_read_exactly_over_adb(self):
        self.assertEqual(bridge.device_permissions("SERIAL", FakePhone(listener=False, files=False)),
                         {"notifications": False, "sms": True, "contacts": False, "phone": True, "storage": False})
        self.assertIsNone(bridge.device_permissions("SERIAL", lambda args, timeout=10: (1, "error")), "adb cannot tell")

    def test_granted_on_a_click(self):
        phone = FakePhone(listener=False, files=False)
        self.assertTrue(bridge.grant_permission("SERIAL", "notifications", phone))
        self.assertIn(["cmd", "notification", "allow_listener", bridge.LISTENER, "0"], phone.ran)
        self.assertTrue(bridge.grant_permission("SERIAL", "storage", phone))
        self.assertTrue(bridge.grant_permission("SERIAL", "contacts", phone))
        self.assertIn(["pm", "grant", "--user", "0", bridge.KDECONNECT_ANDROID, "android.permission.READ_CONTACTS"], phone.ran)
        self.assertFalse(bridge.grant_permission("SERIAL", "unknown", phone))


class FakePacman:
    """pacman answers: installed packages, and what -Sp would install."""
    def __init__(self, installed, deps):
        self.installed, self.deps, self.ran = set(installed), deps, []

    def __call__(self, cmd, **kw):
        self.ran.append(cmd)
        class Out:
            pass
        out = Out()
        out.stdout, out.stderr = "", ""
        if cmd[:2] == ["pacman", "-Q"]:
            out.returncode = 0 if cmd[2] in self.installed else 1
        elif cmd[:2] == ["pacman", "-Sp"]:
            out.returncode = 0
            out.stdout = "\n".join("%s 1.0" % p for name in cmd[5:] for p in self.deps.get(name, [name]))
        else:
            out.returncode = 1
        return out


class RootPlans(unittest.TestCase):
    def test_only_what_is_missing_and_everything_it_brings(self):
        pacman = FakePacman(installed=["android-tools"], deps={"scrcpy": ["scrcpy", "ffmpeg", "sdl2"]})
        plan = bridge.root_plan("screen", run=pacman)
        self.assertIn("scrcpy 1.0, ffmpeg 1.0, sdl2 1.0, android-udev 1.0", plan["actions"][0])
        self.assertEqual(plan["commands"][0][-2:], ["scrcpy", "android-udev"], "android-tools is installed: never passed to pacman")
        self.assertIn("what scrcpy, android-udev need", plan["actions"][1])

    def test_installed_at_any_version_runs_nothing(self):
        plan = bridge.root_plan("install", run=FakePacman(installed=["kdeconnect"], deps={}))
        self.assertEqual((plan["commands"], plan["actions"][0]), ([], "Nothing to install: kdeconnect already here"))

    def test_the_firewall_rules_as_written(self):
        plan = bridge.root_plan("firewall", lan="192.168.5.0/24")
        self.assertEqual(len(plan["actions"]), 2)
        self.assertTrue(all("from 192.168.5.0/24" in a for a in plan["actions"]))
        self.assertIn("192.168.5.0/24", plan["commands"][0][-1])

    def test_runs_only_the_plan_shown(self):
        self.assertEqual(bridge.run_root("sshfs", ""), bridge.EXIT_FAILED, "no hash: nothing runs")
        self.assertEqual(bridge.run_root("sshfs", "0123456789abcdef"), bridge.EXIT_FAILED, "another plan's hash: nothing runs")
        self.assertIsNone(bridge.root_plan("search"), "a fix without root has no plan")


class NotificationCounts(unittest.TestCase):
    def test_other_apps_only(self):
        dump = ("NotificationRecord(0x1: pkg=com.example.chat user=UserHandle{0} id=1 tag=null)\n"
                "NotificationRecord(0x2: pkg=com.example.mail user=UserHandle{0} id=2 tag=null)\n"
                "NotificationRecord(0x3: pkg=org.kde.kdeconnect_tp user=UserHandle{0} id=3 tag=null)\n"
                "NotificationRecord(0x4: pkg=com.android.systemui user=UserHandle{0} id=4 tag=null)\n")
        self.assertEqual(bridge.device_notification_count("S", lambda args, timeout=15: (0, dump)), 2)
        self.assertIsNone(bridge.device_notification_count("S", lambda args, timeout=15: (1, "")))


class PinEvents(unittest.TestCase):
    def test_our_window_pinned(self):
        lines = ["activewindow>>foot,x", "pin>>55d0c1a2b3c4,1", "pin>>aaaa,0"]
        self.assertTrue(bridge.pinned_event(lines, "0x55d0c1a2b3c4"))
        self.assertFalse(bridge.pinned_event(lines, "0xbbbb"))
        self.assertFalse(bridge.pinned_event(["openwindow>>55d0c1a2b3c4,1,x,y"], "0x55d0c1a2b3c4"))


class Mounts(unittest.TestCase):
    def test_a_dead_mount_is_asked_in_a_child_with_a_limit(self):
        ran = []
        class Out:
            returncode = 1
        self.assertFalse(bridge.mount_alive("/run/user/1/x", run=lambda cmd, **kw: ran.append(cmd) or Out()))
        self.assertEqual(ran[0][:2], ["timeout", "3"])
        self.assertFalse(bridge.mount_alive(""), "no mount point")


class Renotify(unittest.TestCase):
    def test_a_plugin_turned_off_stays_off(self):
        set_calls = []
        saved = (bridge.plugin_on, bridge.set_plugin, bridge.say, bridge.time.sleep)
        try:
            bridge.plugin_on = lambda device, plugin, conn=None: False
            bridge.set_plugin = lambda *a, **kw: set_calls.append(a)
            bridge.say = lambda message, code=0: code
            self.assertEqual(bridge.device_fix("renotify", "dev"), 0)
            self.assertEqual(set_calls, [], "turned off for this device: never turned on by a fix nobody clicked")
            bridge.plugin_on = lambda device, plugin, conn=None: True
            bridge.time.sleep = lambda s: None
            bridge.device_fix("renotify", "dev")
            self.assertEqual([c[2] for c in set_calls], [False, True], "on: off, then on again")
        finally:
            bridge.plugin_on, bridge.set_plugin, bridge.say, bridge.time.sleep = saved


class Reconnect(unittest.TestCase):
    def test_the_address_from_the_serial_or_the_device(self):
        self.assertEqual(bridge.device_address("192.168.1.23:37011"), "192.168.1.23")
        out = "3: wlan0    inet 192.168.1.40/24 brd 192.168.1.255 scope global wlan0"
        self.assertEqual(bridge.device_address("R5CT1234", run=lambda args: (0, out)), "192.168.1.40")
        self.assertEqual(bridge.device_address("R5CT1234", run=lambda args: (1, "")), "", "USB only: no address")

    def test_the_users_own_custom_devices_stay(self):
        self.assertEqual(bridge.with_address(["10.0.0.5"], "", "192.168.1.23"), ["10.0.0.5", "192.168.1.23"])
        self.assertEqual(bridge.with_address(["10.0.0.5", "192.168.1.20"], "192.168.1.20", "192.168.1.23"), ["10.0.0.5", "192.168.1.23"],
                         "the address it added before goes when it changed")
        self.assertEqual(bridge.with_address(["192.168.1.23"], "192.168.1.23", "192.168.1.23"), ["192.168.1.23"], "nothing to change")


if __name__ == "__main__":
    unittest.main()
