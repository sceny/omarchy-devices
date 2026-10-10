"""Calls through Bluetooth (#59): BlueZ's and PipeWire's objects as the
panel reads them, the time each call lasts, the call's audio here, and the
D-Bus calls each click makes (with the bus replaced: nothing reaches a
device, and no call is made). All data is made up."""

import importlib.machinery
import importlib.util
import os
import tempfile
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
BRIDGE = os.path.join(HERE, "..", "bin", "kdeconnect-bridge")
loader = importlib.machinery.SourceFileLoader("kdeconnect_bridge_calls", BRIDGE)
spec = importlib.util.spec_from_loader("kdeconnect_bridge_calls", loader)
bridge = importlib.util.module_from_spec(spec)
loader.exec_module(bridge)

PHONE = "00:11:22:33:44:55"
AG = "/org/pipewire/Telephony/ag0"


def bluez(powered=True, phones=()):
    objects = {"/org/bluez/hci0": {"org.bluez.Adapter1": {"Powered": powered, "UUIDs": [bridge.UUID_HANDSFREE.upper()]}}}
    for i, (address, name, paired, connected, uuids, icon) in enumerate(phones):
        objects["/org/bluez/hci0/dev_%d" % i] = {"org.bluez.Device1": {
            "Address": address, "Alias": name, "Paired": paired, "Connected": connected, "UUIDs": uuids, "Icon": icon}}
    return objects


class BluezObjects(unittest.TestCase):
    def test_phones_only_with_what_calls_need(self):
        b = bridge.parse_bluez(bluez(phones=[
            (PHONE.lower(), "Pixel 8", True, True, [bridge.UUID_GATEWAY], "phone"),
            ("AA:AA:AA:AA:AA:AA", "Headphones", True, True, ["0000110b-0000-1000-8000-00805f9b34fb"], "audio-headset")]))
        self.assertEqual(b["adapter"], {"present": True, "powered": True, "handsfree": True})
        self.assertEqual(b["phones"], [{"address": PHONE, "name": "Pixel 8", "paired": True, "connected": True, "gateway": True}])

    def test_no_adapter(self):
        self.assertEqual(bridge.parse_bluez({})["adapter"], {"present": False, "powered": False, "handsfree": False})


def gateway(calls=(), audio="idle", reject=True):
    ifaces = {bridge.TEL_AG: {"Address": PHONE, "SpeakerVolume": 9, "MicrophoneVolume": 12},
              bridge.TEL_TRANSPORT: {"State": audio, "Codec": 2, "RejectSCO": reject}}
    objects = {}
    for i, (state, number, name) in enumerate(calls):
        objects["%s/call%d" % (AG, i)] = {bridge.TEL_CALL: {"State": state, "LineIdentification": number, "Name": name, "Multiparty": False}}
    return bridge.parse_gateway(AG, ifaces, objects)


class Gateways(unittest.TestCase):
    def test_calls_under_their_gateway(self):
        g = gateway([("active", "+15145550123", "Alex Rivera"), ("waiting", "+15145550142", "")], audio="active", reject=False)
        self.assertEqual([g["address"], g["audio"], g["codec"], g["keepOnPhone"], g["speaker"]], [PHONE, "active", "mSBC", False, 9])
        self.assertEqual([(c["id"], c["state"], c["number"]) for c in g["calls"]],
                         [("call0", "active", "+15145550123"), ("call1", "waiting", "+15145550142")])

    def test_a_call_counts_from_its_answer_and_says_it_ended(self):
        times = bridge.CallTimes()
        ringing = {PHONE: gateway([("incoming", "+15145550123", "")])}
        times.note(ringing, 1000)
        self.assertEqual(times.since(), {})
        times.note({PHONE: gateway([("active", "+15145550123", "")])}, 4000)
        self.assertEqual(times.since(), {AG + "/call0": 4000})
        self.assertEqual(times.seen(), {AG + "/call0": 1000})
        times.note({PHONE: gateway()}, 64000)
        self.assertEqual(times.ended[PHONE], {"at": 64000, "number": "+15145550123", "name": "", "answered": True, "duration": 60000})
        # Declined, never answered: ended, not answered.
        times.note({PHONE: gateway([("incoming", "+15145550142", "")])}, 70000)
        times.note({}, 72000)
        self.assertFalse(times.ended[PHONE]["answered"])

    def test_the_snapshot_says_each_device_s_calls(self):
        bt = {"bluez": True, "present": True, "powered": True, "handsfree": True, "service": True,
              "phones": [{"address": PHONE, "name": "Pixel 8", "paired": True, "connected": True, "gateway": True}],
              "gateways": {PHONE: gateway([("incoming", "+15145550123", "")])}}
        snap = {"devices": [{"id": "d1", "paired": True}, {"id": "d2", "paired": True}]}
        bridge.with_bluetooth(snap, bt, {"d1": {"address": PHONE.lower(), "name": "Pixel 8"}})
        hf = snap["devices"][0]["handsfree"]
        self.assertEqual([hf["connected"], hf["paired"], hf["calls"][0]["state"]], [True, True, "incoming"])
        self.assertIsNone(snap["devices"][1]["handsfree"], "not matched: nothing")
        self.assertNotIn("gateways", snap["bluetooth"])


def pw(nodes, links=()):
    out = []
    for nid, cls, name, internal in nodes:
        out.append({"id": nid, "type": "PipeWire:Interface:Node", "info": {"props": {
            "api.bluez5.address": PHONE, "media.class": cls, "node.name": name, "api.bluez5.internal": internal}}})
    for i, (o, n) in enumerate(links):
        out.append({"id": 900 + i, "type": "PipeWire:Interface:Link", "info": {"output-node-id": o, "input-node-id": n}})
    return out


class CallAudio(unittest.TestCase):
    def test_both_halves_when_nothing_plays_them(self):
        nodes = bridge.call_nodes(pw([(51, "Audio/Source", "bluez_input.x", False), (52, "Audio/Sink", "bluez_output.x", False),
                                      (53, "Audio/Source", "bluez_capture_internal.x", True)]), PHONE)
        self.assertEqual([nodes["source"]["id"], nodes["sink"]["id"]], [51, 52])
        cmds = bridge.loopback_commands(nodes, "Call (Pixel 8)")
        self.assertEqual(len(cmds), 2)
        self.assertIn("target.object=bluez_input.x node.dont-reconnect=true stream.dont-remix=true", cmds[0])
        self.assertIn("target.object=bluez_output.x node.dont-reconnect=true", cmds[1])
        self.assertTrue(all("media.role=Communication" in " ".join(c) for c in cmds))

    def test_a_half_already_played_is_left_alone(self):
        nodes = bridge.call_nodes(pw([(51, "Audio/Source", "bluez_input.x", False), (52, "Audio/Sink", "bluez_output.x", False)],
                                     links=[(51, 70)]), PHONE)
        self.assertEqual([c[2] for c in bridge.loopback_commands(nodes, "Call")], ["sceny-devices-call-out"])
        self.assertEqual(bridge.mute_target(pw([(52, "Audio/Sink", "bluez_output.x", False)]), PHONE), 52)


class FakeConn:
    def __init__(self):
        self.sent = []

    def call_sync(self, name, path, iface, method, params, *rest):
        self.sent.append((name, path.rsplit("/", 1)[-1], iface.rsplit(".", 1)[-1], method,
                          params.unpack() if params is not None else None))


class Clicks(unittest.TestCase):
    """What each click sends; the bus is replaced, so no call is made."""

    def setUp(self):
        self.conn = FakeConn()
        self.saved = bridge.gateway_of
        self.g = gateway([("incoming", "+15145550123", "")])
        bridge.gateway_of = lambda device_id, conn=None: (self.conn, self.g)

    def tearDown(self):
        bridge.gateway_of = self.saved

    def test_answer_here_lets_the_audio_come(self):
        self.assertEqual(bridge.call_verb("answer", "d1"), bridge.EXIT_OK)
        self.assertEqual(self.conn.sent, [
            (bridge.TELEPHONY, "ag0", "Properties", "Set", (bridge.TEL_TRANSPORT, "RejectSCO", False)),
            (bridge.TELEPHONY, "call0", "Call1", "Answer", None)])

    def test_answer_on_the_device_keeps_it_there(self):
        bridge.call_verb("answer-phone", "d1")
        self.assertEqual(self.conn.sent[0][4], (bridge.TEL_TRANSPORT, "RejectSCO", True))

    def test_a_waiting_call_holds_the_first(self):
        self.g = gateway([("active", "+15145550123", ""), ("waiting", "+15145550142", "")])
        bridge.call_verb("answer", "d1")
        self.assertEqual(self.conn.sent[-1][2:4], ("AudioGateway1", "HoldAndAnswer"))

    def test_dial_takes_only_what_the_keypad_has(self):
        bridge.call_verb("dial", "d1", "+1 (514) 555-0123")
        self.assertEqual(self.conn.sent[-1][3:], ("Dial", ("+15145550123",)))
        self.assertEqual(bridge.call_verb("dial", "d1", "call me"), bridge.EXIT_FAILED)

    def test_volume_is_a_byte(self):
        bridge.call_verb("volume", "d1", "40")
        self.assertEqual(self.conn.sent[-1][4], (bridge.TEL_AG, "SpeakerVolume", 15))

    def test_not_connected_says_so(self):
        bridge.gateway_of = lambda device_id, conn=None: (self.conn, None)
        self.assertEqual(bridge.call_verb("answer", "d1"), bridge.EXIT_FAILED)
        self.assertEqual(self.conn.sent, [])


class Checks(unittest.TestCase):
    def state(self, **over):
        s = {"bluez": True, "present": True, "powered": True, "handsfree": True, "service": True, "phones": [], "gateways": {}}
        s.update(over)
        return s

    def test_optional_and_one_fix_each(self):
        ok = bridge.bluetooth_checks(self.state())
        self.assertTrue(all(c["ok"] and c["optional"] for c in ok))
        off = bridge.bluetooth_checks(self.state(powered=False))
        self.assertEqual([(c["key"], c["fix"]) for c in off], [("bluetooth", "bluetooth-on"), ("handsfree", "")])
        quiet = bridge.bluetooth_checks(self.state(service=False))
        self.assertEqual(quiet[1]["fix"], "audio")
        none = bridge.bluetooth_checks(self.state(present=False))
        self.assertEqual([none[0]["status"], none[0]["fix"]], ["No adapter", ""])

    def test_the_match_is_kept_in_the_cache(self):
        with tempfile.TemporaryDirectory() as tmp:
            saved = os.environ.get("XDG_CACHE_HOME")
            os.environ["XDG_CACHE_HOME"] = tmp
            try:
                bridge.bluetooth_record(update={"d1": {"address": PHONE, "name": "Pixel 8"}})
                self.assertEqual(bridge.bluetooth_record()["d1"]["address"], PHONE)
                bridge.bluetooth_record(drop="d1")
                self.assertEqual(bridge.bluetooth_record(), {})
            finally:
                if saved is None:
                    del os.environ["XDG_CACHE_HOME"]
                else:
                    os.environ["XDG_CACHE_HOME"] = saved


class RootPlan(unittest.TestCase):
    def test_bluetooth_installed_and_started_in_one_prompt(self):
        def run(cmd, **kw):
            class R:
                returncode, stdout, stderr = 1, "", ""
            r = R()
            if cmd[:2] == ["pacman", "-Sp"]:
                r.returncode, r.stdout = 0, "bluez 5.87-2\nbluez-utils 5.87-2\n"
            return r
        plan = bridge.root_plan("bluetooth", run=run)
        self.assertEqual(len(plan["commands"]), 1, "one password")
        self.assertIn("omarchy-pkg-add bluez bluez-utils && /usr/bin/systemctl enable --now bluetooth.service", plan["commands"][0][-1])
        self.assertTrue(any("enable --now" in a for a in plan["actions"]))


if __name__ == "__main__":
    unittest.main()
