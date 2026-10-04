"""App icons read from an app's installed package (kdeconnect-bridge, Apps).

The packages here are built in the test: a made-up app (`com.example.app`)
with a manifest, a resource table and its icon files, in Android's binary
formats. Nothing comes from a real device.
"""

import importlib.machinery
import importlib.util
import io
import os
import struct
import tempfile
import unittest
import zipfile

HERE = os.path.dirname(os.path.abspath(__file__))
BRIDGE = os.path.join(HERE, "..", "bin", "kdeconnect-bridge")
loader = importlib.machinery.SourceFileLoader("kdeconnect_bridge_icons", BRIDGE)
spec = importlib.util.spec_from_loader("kdeconnect_bridge_icons", loader)
bridge = importlib.util.module_from_spec(spec)
loader.exec_module(bridge)

A = bridge.ATTR
PNG = (b"\x89PNG\r\n\x1a\n\x00\x00\x00\rIHDR\x00\x00\x00\x01\x00\x00\x00\x01\x08\x06\x00\x00\x00\x1f\x15\xc4\x89"
       b"\x00\x00\x00\rIDATx\x9cc\xf8\xcf\xc0\xf0\x1f\x00\x05\x00\x01\xff\x89\x99=\x1d\x00\x00\x00\x00IEND\xaeB`\x82")


# ---- Writing Android's binary formats (only what the reader reads) ---------

def pool(strings):
    """A UTF-8 ResStringPool."""
    offsets, data = [], b""
    for s in strings:
        b = s.encode()
        assert len(b) < 128
        offsets.append(len(data))
        data += bytes([len(s), len(b)]) + b + b"\0"
    data += b"\0" * (-len(data) % 4)
    header = 28
    start = header + 4 * len(strings)
    body = b"".join(struct.pack("<I", o) for o in offsets) + data
    return struct.pack("<HHIIIIII", 0x0001, header, header + len(body), len(strings), 0, 0x100, start, 0) + body


def axml(root):
    """Binary XML from (name, [(attr name, framework id or None, type, data, raw)], [children])."""
    strings, ids = [], []

    def idx(s):
        if s not in strings:
            strings.append(s)
        return strings.index(s)

    # Attribute names with a framework id first: the resource map covers them.
    def names(el):
        for a in el[1]:
            if a[1] is not None and a[0] not in strings:
                strings.append(a[0])
                ids.append(a[1])
        for c in el[2]:
            names(c)
    names(root)
    nodes = b""

    def emit(el):
        nonlocal nodes
        name, attrs, children = el
        body = struct.pack("<IIHHHHHH", 0xFFFFFFFF, idx(name), 20, 20, len(attrs), 0, 0, 0)
        for a, _rid, t, d, raw in attrs:
            body += struct.pack("<IIIHBBI", 0xFFFFFFFF, idx(a), idx(raw) if raw is not None else 0xFFFFFFFF, 8, 0, t, d)
        nodes += struct.pack("<HHIII", 0x0102, 16, 16 + len(body), 1, 0xFFFFFFFF) + body
        for c in children:
            emit(c)
        nodes += struct.pack("<HHIIIII", 0x0103, 16, 24, 1, 0xFFFFFFFF, 0xFFFFFFFF, idx(name))
    emit(root)
    sp = pool(strings)
    rm = struct.pack("<HHI", 0x0180, 8, 8 + 4 * len(ids)) + b"".join(struct.pack("<I", i) for i in ids)
    body = sp + rm + nodes
    return struct.pack("<HHI", 0x0003, 8, 8 + len(body)) + body


def config(density=0, night=False, language=b""):
    c = bytearray(64)
    struct.pack_into("<I", c, 0, 64)
    c[8:10] = (language + b"\0\0")[:2]
    struct.pack_into("<H", c, 14, density)
    c[29] = 0x20 if night else 0
    return bytes(c)


def arsc(types, values, globals_):
    """A resource table: package 0x7f, `types` names, `values` as
    {(type id, entry): [(config, type, data)]}, strings in `globals_`."""
    tpool = pool(types)
    kpool = pool(["k"])
    chunks = b""
    for tid in range(1, len(types) + 1):
        count = 1 + max([e for (t, e) in values if t == tid] or [0])
        chunks += struct.pack("<HHIBBHI", 0x0202, 16, 16 + 4 * count, tid, 0, 0, count) + b"\0" * 4 * count
        configs = []
        for (t, e), vals in values.items():
            for cfg, _vt, _vd in vals:
                if t == tid and cfg not in configs:
                    configs.append(cfg)
        for cfg in configs:
            offs, entries = [], b""
            for e in range(count):
                v = next(((vt, vd) for c, vt, vd in values.get((tid, e), []) if c == cfg), None)
                if v is None:
                    offs.append(0xFFFFFFFF)
                    continue
                offs.append(len(entries))
                entries += struct.pack("<HHI", 8, 0, 0) + struct.pack("<HBBI", 8, 0, v[0], v[1])
            header = 20 + 64
            estart = header + 4 * count
            body = b"".join(struct.pack("<I", o) for o in offs) + entries
            chunks += struct.pack("<HHIBBHII", 0x0201, header, header + len(body), tid, 0, 0, count, estart) + cfg + body
    name = "com.example.app".encode("utf-16-le").ljust(256, b"\0")
    ph = 288
    pkg_body = tpool + kpool + chunks
    pkg = struct.pack("<HHII", 0x0200, ph, ph + len(pkg_body), 0x7F) + name + struct.pack(
        "<IIIII", ph, len(types), ph + len(tpool), 1, 0) + pkg_body
    gp = pool(globals_)
    return struct.pack("<HHII", 0x0002, 12, 12 + len(gp) + len(pkg), 1) + gp + pkg


def ref(rid):
    return (bridge.T_REF, rid)


def apk(files, stored_table=True):
    buf = io.BytesIO()
    with zipfile.ZipFile(buf, "w") as z:
        for name, data in files.items():
            z.writestr(name, data, zipfile.ZIP_STORED if name == "resources.arsc" and stored_table else zipfile.ZIP_DEFLATED)
    return buf.getvalue()


def manifest(icon, launcher_icon=None, alias_icon=None):
    app_attrs = [("icon", A["icon"], bridge.T_REF, icon, None)]
    launcher = ("intent-filter", [], [("category", [("name", A["name"], 3, 0, "android.intent.category.LAUNCHER")], [])])
    acts = [("activity", [("name", A["name"], 3, 0, ".Main")] +
             ([("icon", A["icon"], bridge.T_REF, launcher_icon, None)] if launcher_icon else []), [launcher])]
    if alias_icon:
        acts.append(("activity-alias", [("name", A["name"], 3, 0, ".Other"), ("icon", A["icon"], bridge.T_REF, alias_icon, None)], [launcher]))
    return axml(("manifest", [("package", None, 3, 0, "com.example.app")], [("application", app_attrs, acts)]))


class FakeReader:
    """Ranged reads of files held in memory, as PhoneReader answers them."""
    def __init__(self, files):
        self.files, self.reads = files, 0

    def read(self, path, off, n):
        self.reads += 1
        return self.files[path][off:off + n]

    def size(self, path):
        return len(self.files[path])

    def paths(self, package):
        return sorted(self.files)

    def close(self):
        pass


# Resource ids: type 1 mipmap, 2 color, 3 drawable.
ICON, BG, FG, COLOR, ALT = 0x7F010000, 0x7F010001, 0x7F030000, 0x7F020000, 0x7F010002


class Formats(unittest.TestCase):
    def test_binary_xml(self):
        root = bridge.parse_axml(axml(("vector", [("pathData", A["pathData"], 3, 0, "M0 0h24v24z")], [("path", [], [])])))
        self.assertEqual((root.name, root.get("pathData")[2], [c.name for c in root.children]), ("vector", "M0 0h24v24z", ["path"]))
        self.assertIsNone(bridge.parse_axml(b"not xml at all"))

    def test_table_values_per_configuration(self):
        table = bridge.Arsc(bridge.BytesAt(arsc(["mipmap"], {(1, 0): [(config(160), 3, 0), (config(640), 3, 1), (config(0, night=True), 3, 2)]},
                                                ["res/a.png", "res/b.png", "res/c.png"])))
        found = {bridge._u16(c, 14): table.strings.get(d) for c, t, d in table.values(ICON)}
        self.assertEqual(found, {160: "res/a.png", 640: "res/b.png", 0: "res/c.png"})
        self.assertEqual(table.values(0x01010002), [], "another package's id")

    def test_configuration_ranks(self):
        self.assertGreater(bridge.config_rank(config(0xFFFE)), bridge.config_rank(config(640)))
        self.assertGreater(bridge.config_rank(config(640)), bridge.config_rank(config(160)))
        self.assertIsNone(bridge.config_rank(config(640, night=True)))
        self.assertIsNone(bridge.config_rank(config(640, language=b"fr")))

    def test_sniff_by_content(self):
        self.assertEqual([bridge.sniff(PNG), bridge.sniff(b"RIFF\0\0\0\0WEBPVP8 "), bridge.sniff(axml(("a", [], []))), bridge.sniff(b"plain text here")],
                         ["image/png", "image/webp", "xml", None])

    def test_lists_from_the_device(self):
        self.assertEqual(bridge.parse_launcher_activities("3 activities found:\n  Activity #0:\n    priority=0\n    com.example.app/.Main\n    com.example.two/com.example.two.Start\n"),
                         {"com.example.app": "com.example.app.Main", "com.example.two": "com.example.two.Start"})
        self.assertEqual(bridge.parse_versions("package:com.example.app versionCode:42\npackage:com.example.two versionCode:7\n"),
                         {"com.example.app": "42", "com.example.two": "7"})


class Icons(unittest.TestCase):
    def table(self, extra=None):
        values = {(1, 0): [(config(160), 3, 0), (config(0xFFFE), 3, 1)],   # icon: a picture, an adaptive icon
                  (1, 1): [(config(0), 0x1D, 0x3366CC)],                    # background colour
                  (2, 0): [(config(0), 0x1C, 0xFF112233)],                  # a colour
                  (3, 0): [(config(640), 3, 2)]}                            # foreground: an extension-less picture
        values.update(extra or {})
        return arsc(["mipmap", "color", "drawable"], values, ["res/a.png", "res/ic.xml", "res/Zq", "res/vec.xml", "res/alt.png"])

    def adaptive(self):
        return axml(("adaptive-icon", [], [("background", [("drawable", A["drawable"], bridge.T_REF, BG, None)], []),
                                           ("foreground", [("drawable", A["drawable"], bridge.T_REF, FG, None)], [])]))

    def apks(self, files, stored=True, reader=None):
        data = apk(files, stored)
        if reader is None:
            return [bridge.Apk(io.BytesIO(data))]
        reader.files["/data/app/base.apk"] = data
        return [bridge.Apk(bridge.RemoteFile(reader, "/data/app/base.apk", len(data)))]

    def test_adaptive_icon_in_a_circle(self):
        files = {"AndroidManifest.xml": manifest(ICON), "resources.arsc": self.table(), "res/a.png": PNG,
                 "res/ic.xml": self.adaptive(), "res/Zq": PNG}
        kind, svg = bridge.icon_document(self.apks(files))
        self.assertEqual(kind, "svg")
        self.assertIn('viewBox="18 18 72 72"', svg)
        self.assertIn('<circle cx="54" cy="54" r="36"/>', svg)
        self.assertIn('fill="#3366cc"', svg, "the background colour")
        self.assertIn("data:image/png;base64,", svg, "the foreground picture, found by its content")
        self.assertLess(svg.index("#3366cc"), svg.index("data:image/png"), "background under foreground")

    def test_read_in_ranges_without_the_whole_package(self):
        big = os.urandom(600 << 10)   # an unrelated large file in the package
        files = {"AndroidManifest.xml": manifest(ICON), "resources.arsc": self.table(), "res/a.png": PNG,
                 "res/ic.xml": self.adaptive(), "res/Zq": PNG, "assets/big.bin": big}
        reader = FakeReader({})
        kind, _svg = bridge.icon_document(self.apks(files, reader=reader))
        self.assertEqual(kind, "svg")
        self.assertLess(reader.reads, 4, "the big file is never read")

    def test_vector_with_tint_and_gradient_colour(self):
        vec = axml(("vector", [("viewportWidth", A["viewportWidth"], bridge.T_FLOAT, struct.unpack("<I", struct.pack("<f", 24))[0], None),
                               ("viewportHeight", A["viewportHeight"], bridge.T_FLOAT, struct.unpack("<I", struct.pack("<f", 24))[0], None),
                               ("tint", A["tint"], bridge.T_REF, COLOR, None)],
                    [("group", [("translateX", A["translateX"], bridge.T_FLOAT, struct.unpack("<I", struct.pack("<f", 2))[0], None)],
                      [("path", [("pathData", A["pathData"], 3, 0, "M0,0L24,24"), ("fillColor", A["fillColor"], 0x1C, 0xFF00FF00, None),
                                 ("fillType", A["fillType"], bridge.T_INT_DEC, 1, None)], [])])]))
        files = {"AndroidManifest.xml": manifest(ICON), "resources.arsc": self.table({(1, 0): [(config(0xFFFE), 3, 3)]}),
                 "res/vec.xml": vec}
        kind, svg = bridge.icon_document(self.apks(files))
        self.assertEqual(kind, "svg")
        self.assertIn('viewBox="0 0 24 24"', svg)
        self.assertIn('d="M0,0L24,24"', svg)
        self.assertIn('fill="#00ff00"', svg)
        self.assertIn('fill-rule="evenodd"', svg)
        self.assertIn("translate(2 0)", svg)
        self.assertIn('flood-color="#112233"', svg, "tinted with the colour resource")

    def test_plain_picture_and_aliases(self):
        files = {"AndroidManifest.xml": manifest(ICON), "resources.arsc": self.table({(1, 0): [(config(0), bridge.T_REF, FG)]}),
                 "res/Zq": PNG}
        self.assertEqual(bridge.icon_document(self.apks(files)), ("bitmap", PNG), "@mipmap/icon is @drawable/fg")

    def test_the_enabled_launcher_entry(self):
        files = {"AndroidManifest.xml": manifest(ICON, alias_icon=ALT), "resources.arsc": self.table({(1, 2): [(config(0), 3, 4)]}),
                 "res/a.png": PNG, "res/ic.xml": self.adaptive(), "res/Zq": PNG, "res/alt.png": PNG + b"alt"}
        self.assertEqual(bridge.icon_document(self.apks(files), "com.example.app.Other"), ("bitmap", PNG + b"alt"))

    def test_compressed_table_and_nothing_to_draw(self):
        files = {"AndroidManifest.xml": manifest(ICON), "resources.arsc": self.table(), "res/a.png": PNG,
                 "res/ic.xml": self.adaptive(), "res/Zq": PNG}
        self.assertEqual(bridge.icon_document(self.apks(files, stored=False))[0], "svg")
        self.assertIsNone(bridge.icon_document(self.apks({"AndroidManifest.xml": manifest(ICON)})), "no resource table")
        self.assertIsNone(bridge.icon_document(self.apks({"classes.dex": b"dex"})), "no manifest")


class Cache(unittest.TestCase):
    def setUp(self):
        self.home = tempfile.TemporaryDirectory()
        self.old = os.environ.get("XDG_CACHE_HOME")
        os.environ["XDG_CACHE_HOME"] = self.home.name

    def tearDown(self):
        if self.old is None:
            os.environ.pop("XDG_CACHE_HOME", None)
        else:
            os.environ["XDG_CACHE_HOME"] = self.old
        self.home.cleanup()

    def test_kept_a_day_then_read_again(self):
        reads = []
        apps = [{"package": "com.example.b", "name": "Bee", "system": False, "version": "1", "activity": ""},
                {"package": "com.example.sys", "name": "Aardvark", "system": True, "version": "1", "activity": ""},
                {"package": "com.example.a", "name": "ant", "system": False, "version": "3", "activity": ""}]
        read = lambda serial: reads.append(serial) or apps
        ready = {"state": "ready", "serial": "SERIAL"}
        first = bridge.apps_list("dev", status=ready, read=read, clock=lambda: 1000)
        self.assertEqual([a["name"] for a in first["apps"]], ["ant", "Bee", "Aardvark"], "user apps first, A to Z")
        self.assertEqual(first["apps"][0]["icon"], "")
        bridge.apps_list("dev", status=ready, read=read, clock=lambda: 1000 + 3600)
        self.assertEqual(len(reads), 1, "within the day: the cache")
        bridge.apps_list("dev", status=ready, read=read, clock=lambda: 1000 + 25 * 3600)
        self.assertEqual(len(reads), 2, "a day later: read again")
        away = bridge.apps_list("dev", refresh=True, status={"state": "off"}, read=read, clock=lambda: 1000 + 26 * 3600)
        self.assertEqual((away["state"], len(away["apps"])), ("ready", 3), "out of reach: still the list it had")
        bridge.apps_opened("dev", "com.example.b", clock=lambda: 5000)
        self.assertEqual([a["opened"] for a in bridge.apps_list("dev", status=ready, read=read, clock=lambda: 1000)["apps"]],
                         [0, 5000 * 1000, 0], "when it was opened here, in ms")
        open(bridge.app_icon_path("dev", apps[2], "none"), "w").close()
        self.assertEqual(bridge.apps_list("dev", status=ready, read=read, clock=lambda: 1000)["apps"][0]["icon"], "none")


class Opens(unittest.TestCase):
    def test_an_app_is_tiled_without_an_on_screen_keyboard(self):
        cmd = bridge.screen_command("SERIAL", "Clock · Pixel 8", "com.example.app", {"flex": True}, sound="phone")
        self.assertIn("--start-app=com.example.app", cmd)
        self.assertIn("--flex-display", cmd)
        self.assertIn("--display-ime-policy=hide", cmd, "typing is this computer's keyboard")
        self.assertIn("--no-audio", cmd, "its sound stays on the device")
        self.assertNotIn("--no-audio", bridge.screen_command("SERIAL", "Clock · Pixel 8", "com.example.app", {"flex": True}))


if __name__ == "__main__":
    unittest.main()
