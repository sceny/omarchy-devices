"""The network (#119, #8): every path to a device, at home and away. The
firewall's rules and the plan that widens them, the meshes (Tailscale,
NordVPN Meshnet) and how a device is matched among their peers, the address
given to KDE Connect, the order adb paths are used in, and the watch that
asks KDE Connect to announce itself after a network change. The bus, adb
and every command are replaced; all addresses and names are made up."""

import importlib.machinery
import importlib.util
import json
import os
import shutil
import tempfile
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
BRIDGE = os.path.join(HERE, "..", "bin", "kdeconnect-bridge")
loader = importlib.machinery.SourceFileLoader("kdeconnect_bridge_network", BRIDGE)
spec = importlib.util.spec_from_loader("kdeconnect_bridge_network", loader)
bridge = importlib.util.module_from_spec(spec)
loader.exec_module(bridge)

RULES = """### tuple ### allow tcp 1714:1764 0.0.0.0/0 any 192.168.1.0/24 in comment=4b4445
### tuple ### allow udp 1714:1764 0.0.0.0/0 any 192.168.1.0/24 in comment=4b4445
### tuple ### allow tcp 22 0.0.0.0/0 any 0.0.0.0/0 in
### tuple ### allow any 1714:1764 0.0.0.0/0 any 0.0.0.0/0 in_tailscale0
### tuple ### deny tcp 1714:1764 0.0.0.0/0 any 10.0.0.0/8 in
"""

TAILSCALE = json.dumps({
    "BackendState": "Running",
    "Self": {"HostName": "laptop", "TailscaleIPs": ["100.64.0.1", "fd7a::1"]},
    "Peer": {
        "k1": {"HostName": "pixel-8", "DNSName": "pixel-8.tail0000.ts.net.", "OS": "android",
               "TailscaleIPs": ["100.101.102.103", "fd7a::2"], "Online": True},
        "k2": {"HostName": "desk", "DNSName": "desk.tail0000.ts.net.", "OS": "linux",
               "TailscaleIPs": ["100.101.102.110"], "Online": False},
    },
})

MESHNET = """This device:
Nickname: -
Hostname: laptop.nord
IP: 100.70.0.1
Public Key: abc
OS: linux
Distribution: Omarchy

Local Peers:
Nickname: work-phone
Hostname: work-phone.nord
Status: connected
IP: 100.70.0.5
Public Key: def
OS: android
Distribution: 34

Nickname: -
Hostname: office-pc.nord
Status: disconnected
IP: 100.70.0.9
OS: windows

External Peers:
"""


class Firewall(unittest.TestCase):
    def test_kde_rules_only_allows_for_its_ports(self):
        rules = bridge.kde_rules(RULES)
        self.assertEqual(rules, [{"proto": "tcp", "src": "192.168.1.0/24", "iface": ""},
                                 {"proto": "udp", "src": "192.168.1.0/24", "iface": ""},
                                 {"proto": "any", "src": "0.0.0.0/0", "iface": "tailscale0"}])

    def test_what_a_rule_covers(self):
        rules = bridge.kde_rules(RULES)
        self.assertEqual(bridge.covered(rules, "192.168.1.0/24"), {"tcp", "udp"})
        self.assertEqual(bridge.covered(rules, "192.168.1.23"), {"tcp", "udp"}, "one address inside it")
        self.assertEqual(bridge.covered(rules, "192.168.0.0/16"), set(), "a wider network is not")
        self.assertEqual(bridge.covered(rules, iface="tailscale0"), {"tcp", "udp"}, "any: both")
        self.assertEqual(bridge.covered(rules, iface="nordlynx"), set())

    def test_a_mesh_open_by_interface_or_by_its_addresses(self):
        self.assertTrue(bridge.mesh_open(bridge.kde_rules(RULES), "tailscale0"))
        self.assertFalse(bridge.mesh_open(bridge.kde_rules(RULES), "nordlynx"))
        one = [{"proto": "tcp", "src": "100.70.0.5", "iface": ""}]
        self.assertTrue(bridge.mesh_open(one, "nordlynx"), "a hand-made rule for one phone's mesh address counts")

    def test_the_plan_opens_private_networks_and_meshes_only_where_closed(self):
        rules = bridge.kde_rules(RULES)
        out = bridge.firewall_rules(rules, "192.168.1.0/24", ["tailscale0", "nordlynx"])
        self.assertTrue(all("0.0.0.0/0" not in r and " any port " in r for r in out), "never to everyone")
        self.assertEqual(sum("from 192.168.0.0/16" in r for r in out), 2, "the private range around this network, both protocols")
        self.assertEqual(sum("from 10.0.0.0/8" in r for r in out), 2, "a deny rule does not count as open")
        self.assertFalse(any("tailscale0" in r for r in out), "open already")
        self.assertEqual(sum("in on nordlynx" in r for r in out), 2)

    def test_a_network_outside_the_private_ranges_is_added_as_itself(self):
        out = bridge.firewall_rules([], "100.64.5.0/24", [])
        self.assertEqual(sum("from 100.64.5.0/24" in r for r in out), 2)

    def test_the_firewall_rules_as_written(self):
        plan = bridge.root_plan("firewall", lan="192.168.5.0/24", rules=[], ifaces=["tailscale0"])
        self.assertEqual(len(plan["actions"]), 8, "three private ranges and Tailscale, each TCP and UDP")
        self.assertIn("from private networks (home, office) and from Tailscale, never from everyone", plan["why"])
        self.assertTrue(all(a.startswith("Add the firewall rule: ufw allow ") for a in plan["actions"]))
        self.assertIn("in on tailscale0", plan["commands"][0][-1])

    def test_nothing_to_open_runs_nothing(self):
        everything = [{"proto": "any", "src": c, "iface": ""} for c in bridge.PRIVATE_LANS]
        plan = bridge.root_plan("firewall", lan="192.168.5.0/24", rules=everything, ifaces=[])
        self.assertEqual(plan["commands"], [])
        self.assertIn("Nothing to change", plan["actions"][0])


class Tailscale(unittest.TestCase):
    def test_omarchys_installer_in_its_terminal(self):
        plan = bridge.root_plan("tailscale")
        self.assertEqual([os.path.basename(c) for c in plan["commands"][0]],
                         ["omarchy-launch-floating-terminal-with-presentation", "omarchy-install-service-tailscale"])
        self.assertIn("asks for your password there", plan["actions"][0])
        self.assertTrue(plan["hash"])
        self.assertEqual(bridge.run_root("tailscale", ""), bridge.EXIT_FAILED, "only the plan shown")


class Meshes(unittest.TestCase):
    def test_tailscale_status(self):
        m = bridge.parse_tailscale(TAILSCALE)
        self.assertEqual((m["on"], m["address"]), (True, "100.64.0.1"))
        self.assertEqual(m["peers"][0], {"name": "pixel-8", "host": "pixel-8", "os": "android", "address": "100.101.102.103", "online": True})
        self.assertIsNone(bridge.parse_tailscale("failed to connect to local tailscaled"))
        self.assertFalse(bridge.parse_tailscale(json.dumps({"BackendState": "NeedsLogin"}))["on"])

    def test_meshnet_peer_list(self):
        m = bridge.parse_meshnet(MESHNET)
        self.assertEqual((m["on"], m["address"]), (True, "100.70.0.1"))
        self.assertEqual([(p["name"], p["host"], p["os"], p["online"]) for p in m["peers"]],
                         [("work-phone", "work-phone", "android", True), ("-", "office-pc", "windows", False)])
        self.assertFalse(bridge.parse_meshnet("Meshnet is not enabled.")["on"])

    def test_only_the_meshes_installed(self):
        class Out:
            def __init__(self, stdout, code=0):
                self.stdout, self.returncode = stdout, code
        answers = {"tailscale": Out(TAILSCALE), "nordvpn": Out(MESHNET)}
        run = lambda cmd, **kw: answers[cmd[0]]
        both = bridge.mesh_status(run, have=lambda name: True)
        self.assertEqual([(m["mesh"], m["on"], m["installed"]) for m in both], [("tailscale", True, True), ("meshnet", True, True)])
        self.assertEqual(bridge.mesh_status(run, have=lambda name: name == "nordvpn")[0]["mesh"], "meshnet")
        stopped = bridge.mesh_status(lambda cmd, **kw: Out("not running", 1), have=lambda name: name == "tailscale")
        self.assertEqual((stopped[0]["on"], stopped[0]["installed"]), (False, True))

    def test_the_check_offers_tailscale_then_the_firewall(self):
        fw = {"active": True, "rules": []}
        none = bridge.mesh_check([], fw, [])
        self.assertEqual((none["ok"], none["optional"], none["fix"], none["status"]), (False, True, "tailscale", "Not set up"))
        ts = dict(bridge.parse_tailscale(TAILSCALE), installed=True)
        closed = bridge.mesh_check([ts], fw, ["tailscale0"])
        self.assertEqual((closed["ok"], closed["fix"]), (False, "firewall"))
        self.assertIn("The firewall keeps Tailscale out", closed["detail"])
        self.assertTrue(bridge.mesh_check([ts], {"active": False, "rules": []}, ["tailscale0"])["ok"], "no firewall: nothing to open")
        out = dict(ts, on=False, state="NeedsLogin")
        self.assertEqual(bridge.mesh_check([out], fw, [])["status"], "Signed out")


class Matching(unittest.TestCase):
    meshes = [dict(bridge.parse_tailscale(TAILSCALE), installed=True), dict(bridge.parse_meshnet(MESHNET), installed=True)]

    def test_an_address_it_is_reached_at_is_certain(self):
        peer, how = bridge.match_peer({"name": "Anything"}, self.meshes, sure=["100.70.0.5"])
        self.assertEqual((peer["name"], peer["mesh"], how), ("work-phone", "meshnet", "address"))

    def test_remembered_then_by_name(self):
        peer, how = bridge.match_peer({"name": "Phone"}, self.meshes, {"mesh": "tailscale", "peer": "pixel-8"})
        self.assertEqual((peer["address"], how), ("100.101.102.103", "remembered"))
        peer, how = bridge.match_peer({"name": "Pixel 8"}, self.meshes)
        self.assertEqual((peer["address"], how), ("100.101.102.103", "name"), "case and punctuation aside")
        self.assertEqual(bridge.match_peer({"name": "Galaxy"}, self.meshes), (None, ""))

    def test_two_peers_with_its_name_is_no_match(self):
        twins = [{"mesh": "tailscale", "label": "Tailscale", "on": True,
                  "peers": [{"name": "pixel-8", "host": "pixel-8", "os": "android", "address": "100.64.0.2", "online": True},
                            {"name": "Pixel 8", "host": "p8", "os": "android", "address": "100.64.0.3", "online": True}]}]
        self.assertEqual(bridge.match_peer({"name": "Pixel 8"}, twins), (None, ""))

    def test_the_report(self):
        device = {"name": "Galaxy", "addresses": ["192.168.1.23"], "links": ["LAN"], "reachable": True}
        r = bridge.reach_report(device, ["100.70.0.5"], self.meshes, {})
        self.assertIsNone(r["peer"])
        self.assertEqual([c["address"] for c in r["candidates"]], ["100.101.102.103", "100.70.0.5"], "phones only, to pick from")
        self.assertEqual(r["links"], [{"kind": "lan", "address": "192.168.1.23"}])
        mine = bridge.reach_report(dict(device, name="Pixel 8"), ["100.101.102.103"], self.meshes,
                                   {"address": "100.101.102.103", "typed": "10.8.0.4"})
        self.assertEqual((mine["peer"]["address"], mine["added"], mine["candidates"]), ("100.101.102.103", True, []))
        self.assertEqual((mine["given"], mine["givenKept"], mine["typed"], mine["typedKept"]), ("100.101.102.103", True, "10.8.0.4", False))
        over = bridge.reach_report(dict(device, addresses=["100.70.0.5"]), [], self.meshes, {})
        self.assertEqual(over["links"][0]["kind"], "meshnet", "KDE Connect's LAN link over a mesh is the mesh")

    def test_a_wifi_that_keeps_devices_apart(self):
        away = {"name": "Pixel 8", "addresses": [], "links": [], "reachable": False}
        silent = lambda address: False
        r = bridge.reach_report(away, [], self.meshes, {}, wifi=["192.168.1.23"], lan="192.168.1.0/24", answers=silent)
        self.assertTrue(r["isolated"])
        self.assertFalse(bridge.reach_report(away, [], self.meshes, {}, wifi=["192.168.1.23"], lan="192.168.1.0/24",
                                             answers=lambda a: True)["isolated"], "it answers: not apart")
        self.assertFalse(bridge.reach_report(away, [], self.meshes, {}, wifi=["10.1.1.5"], lan="192.168.1.0/24",
                                             answers=silent)["isolated"], "another network: nothing to say")


class FakeDaemon:
    """KDE Connect's daemon on a fake bus: its custom devices and the calls."""
    def __init__(self, custom, paired=True, reachable=True, name="Pixel 8", addresses=()):
        self.custom, self.calls = list(custom), []
        self.device = {"isPaired": paired, "isReachable": reachable, "name": name, "reachableAddresses": list(addresses)}

    def props(self, conn, path, iface):
        return {"customDevices": list(self.custom)} if iface.endswith(".daemon") else dict(self.device)

    def call(self, conn, path, iface, method, args=None, sig=None):
        if sig:
            bridge.GLib.Variant(sig, args)   # the types must hold
        if method == "Set":
            self.custom = list(args[2].unpack())
        self.calls.append(method)
        return ()


class Reach(unittest.TestCase):
    meshes = [dict(bridge.parse_tailscale(TAILSCALE), installed=True)]

    def setUp(self):
        self.dir = tempfile.mkdtemp()
        self.saved = (bridge.state_dir, bridge.props, bridge.call, bridge.wait_reachable)
        bridge.state_dir = lambda: self.dir
        bridge.wait_reachable = lambda device_id, conn: False

    def tearDown(self):
        bridge.state_dir, bridge.props, bridge.call, bridge.wait_reachable = self.saved
        shutil.rmtree(self.dir)

    def use(self, daemon):
        bridge.props, bridge.call = daemon.props, daemon.call
        return daemon

    def test_its_mesh_address_given_to_kde_connect(self):
        d = self.use(FakeDaemon(["10.0.0.5"]))
        self.assertEqual(bridge.reach("p1", conn=object(), meshes=self.meshes), bridge.EXIT_OK)
        self.assertEqual(d.custom, ["10.0.0.5", "100.101.102.103"], "the user's own stays")
        self.assertIn("forceOnNetworkChange", d.calls)
        self.assertEqual(bridge.network_record("p1"), {"address": "100.101.102.103", "mesh": "tailscale", "peer": "pixel-8"})

    def test_an_address_that_changed_replaces_the_one_given_before(self):
        d = self.use(FakeDaemon(["10.0.0.5", "100.101.102.99"]))
        bridge.network_record("p1", {"address": "100.101.102.99", "mesh": "tailscale", "peer": "pixel-8"})
        bridge.reach("p1", conn=object(), meshes=self.meshes)
        self.assertEqual(d.custom, ["10.0.0.5", "100.101.102.103"])

    def test_a_typed_address_and_a_picked_peer(self):
        d = self.use(FakeDaemon([], name="Galaxy"))
        self.assertEqual(bridge.reach("p1", "10.8.0.4", conn=object(), meshes=self.meshes), bridge.EXIT_OK)
        self.assertEqual(bridge.network_record("p1"), {"typed": "10.8.0.4"})
        bridge.reach("p1", "100.101.102.103", conn=object(), meshes=self.meshes)
        self.assertEqual(bridge.network_record("p1")["peer"], "pixel-8", "a picked peer is remembered as the device's")
        self.assertEqual(d.custom, ["10.8.0.4", "100.101.102.103"])
        self.assertEqual(bridge.unreach("p1", "typed", conn=object()), bridge.EXIT_OK)
        self.assertEqual(d.custom, ["100.101.102.103"])
        self.assertNotIn("typed", bridge.network_record("p1"))

    def test_nothing_changes_for_a_bad_address_or_a_device_not_paired(self):
        d = self.use(FakeDaemon(["10.0.0.5"]))
        self.assertEqual(bridge.reach("p1", "not-an-address", conn=object(), meshes=self.meshes), bridge.EXIT_FAILED)
        d.device["isPaired"] = False
        self.assertEqual(bridge.reach("p1", "10.8.0.4", conn=object(), meshes=self.meshes), bridge.EXIT_FAILED)
        self.assertEqual(bridge.unreach("p1", conn=object()), bridge.EXIT_FAILED)
        self.assertEqual(d.custom, ["10.0.0.5"])
        self.assertNotIn("Set", d.calls)

    def test_not_on_the_mesh_yet(self):
        self.use(FakeDaemon([], name="Galaxy"))
        self.assertEqual(bridge.reach("p1", conn=object(), meshes=self.meshes), bridge.EXIT_FAILED)


class AdbPaths(unittest.TestCase):
    def test_usb_then_wifi_then_the_mesh(self):
        devices = [{"serial": "100.101.102.103:37000", "state": "device", "usb": False, "model": ""},
                   {"serial": "192.168.1.23:37000", "state": "device", "usb": False, "model": ""}]
        ids = {d["serial"]: "R5CX" for d in devices}
        self.assertEqual(bridge.match_adb({}, devices, [], serial="R5CX", identities=ids), ("192.168.1.23:37000", "wifi", "device"))
        self.assertEqual(bridge.match_adb({}, devices[:1], [], serial="R5CX", identities=ids), ("100.101.102.103:37000", "mesh", "device"))
        usb = devices + [{"serial": "R5CX", "state": "device", "usb": True, "model": ""}]
        self.assertEqual(bridge.match_adb({}, usb, [], serial="R5CX", identities=ids)[1], "usb")

    def test_a_mesh_serial_is_not_its_wifi_address(self):
        ran = []
        run = lambda args: (ran.append(args), (0, "3: wlan0    inet 192.168.1.23/24 brd 192.168.1.255"))[1]
        self.assertEqual(bridge.device_address("100.101.102.103:37000", run), "192.168.1.23")
        self.assertEqual(bridge.device_address("192.168.1.30:37000", run), "192.168.1.30")
        self.assertEqual(len(ran), 1)

    def test_its_addresses_by_interface(self):
        out = "1: lo    inet 127.0.0.1/8 scope host lo\n3: wlan0    inet 192.168.1.23/24 brd x\n9: tun0    inet 100.101.102.103/32 scope global tun0\n"
        self.assertEqual(bridge.device_addresses("S", lambda args: (0, out)),
                         [("lo", "127.0.0.1"), ("wlan0", "192.168.1.23"), ("tun0", "100.101.102.103")])


class NetworkChanges(unittest.TestCase):
    def test_the_signature_leaves_containers_out(self):
        class Out:
            stdout = json.dumps([{"ifname": "lo", "addr_info": [{"local": "127.0.0.1", "prefixlen": 8}]},
                                 {"ifname": "wlan0", "addr_info": [{"local": "192.168.1.5", "prefixlen": 24}]},
                                 {"ifname": "docker0", "addr_info": [{"local": "172.17.0.1", "prefixlen": 16}]}])
        self.assertEqual(bridge.network_signature(lambda cmd, **kw: Out()), "wlan0 192.168.1.5/24")

    def test_announced_again_once_per_change(self):
        sigs = iter(["wlan0 192.168.1.5/24", "wlan0 192.168.1.5/24", "wlan0 10.0.0.7/24", "wlan0 10.0.0.7/24"])
        changes = []
        watch = bridge.NetWatch.__new__(bridge.NetWatch)
        watch.on_change, watch.signature, watch.pending, watch.proc = (lambda: changes.append(1)), (lambda: next(sigs)), 0, None
        watch.last = watch.signature()
        self.assertFalse(watch.check())
        self.assertTrue(watch.check())
        self.assertFalse(watch.check())
        self.assertEqual(len(changes), 1)


if __name__ == "__main__":
    unittest.main()
