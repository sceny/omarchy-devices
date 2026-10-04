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


if __name__ == "__main__":
    unittest.main()
