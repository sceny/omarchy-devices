// Model.js checks: `node --test tests/*.test.js`. Model.js is a QML JS library
// (.pragma library), so it is loaded as source with the pragma stripped.
// All data here is made up; never paste anything read from a real device.
const test = require("node:test")
const assert = require("node:assert/strict")
const fs = require("node:fs")
const path = require("node:path")

const src = fs.readFileSync(path.join(__dirname, "..", "Model.js"), "utf8").replace(/^\.pragma library\s*$/m, "")
const names = [...src.matchAll(/^(?:function|var)\s+([A-Za-z_]\w*)/gm)].map(m => m[1])
const M = new Function(src + "; return {" + names.join(",") + "}")()

const device = (over = {}) => ({
  id: "d1", name: "Pixel 8", type: "phone", paired: true, reachable: true, links: ["LAN"],
  battery: { charge: 63, charging: false }, network: { type: "LTE", strength: 3 },
  can: { ring: true, clipboard: true, share: true, sms: true, media: true, notifications: true, ping: true },
  notifications: [], ...over
})
const snap = (...devices) => ({ daemon: true, devices })

test("picks the configured device, else the first reachable, else the first paired", () => {
  const s = snap(device({ id: "a", reachable: false }), device({ id: "b" }), device({ id: "c", paired: false }))
  assert.equal(M.pickDevice(s, "").id, "b")
  assert.equal(M.pickDevice(s, "a").id, "a")
  assert.equal(M.pickDevice(s, "c").id, "b", "an unpaired device is never picked")
  assert.equal(M.pickDevice(null, ""), null)
})

test("bar text: glyph, percent, bolt while charging; bare glyph when away", () => {
  assert.equal(M.barText(device(), true), M.GLYPH.phone + " 63%")
  assert.equal(M.barText(device({ battery: { charge: 63, charging: true } }), true), M.GLYPH.phone + " 63%" + M.GLYPH.bolt)
  assert.equal(M.barText(device(), false), M.GLYPH.phone)
  assert.equal(M.barText(device({ reachable: false }), true), M.GLYPH.phone)
})

test("low battery only when not charging", () => {
  assert.equal(M.lowBattery(device({ battery: { charge: 12, charging: false } }), 15), true)
  assert.equal(M.lowBattery(device({ battery: { charge: 12, charging: true } }), 15), false)
  assert.equal(M.lowBattery(device({ battery: { charge: 40, charging: false } }), 15), false)
})

test("meta line leads with a text-sized battery glyph and never says charging or Unknown", () => {
  const line = M.metaLine(snap(device()), device({ battery: { charge: 63, charging: true }, network: { type: "Unknown" } }), 15)
  assert.match(line, /^.\s?63% · Wi-Fi$/u)
  assert.doesNotMatch(line, /charging|unknown/i)
  assert.equal(M.metaLine(snap(), device({ reachable: false })), "Away")
  assert.equal(M.metaLine({ daemon: false, devices: [] }, null), "KDE Connect is not running")
})

test("the glyph and the word follow the device type", () => {
  assert.equal(M.deviceGlyph(device()).codePointAt(0), 0xF011C)
  assert.equal(M.deviceGlyph(device({ type: "tablet" })).codePointAt(0), 0xF04F6)
  assert.equal(M.deviceGlyph(device({ type: "desktop" })).codePointAt(0), 0xF0AAB)
  assert.equal(M.deviceGlyph(device({ type: "smartwatch" })), M.GLYPH.devices)
  assert.equal(M.deviceGlyph(null), M.GLYPH.devices)
  assert.equal(M.barText(device({ type: "tablet" }), true), String.fromCodePoint(0xF04F6) + " 63%")
  assert.equal(M.deviceNoun(device({ type: "desktop" })), "computer")
  assert.equal(M.deviceLabel(device()), "Pixel 8")
  assert.equal(M.deviceLabel(null), "the device")
})

test("battery glyph follows the level, the bolt and the low mark", () => {
  const g = (c, ch) => M.batteryGlyph(device({ battery: { charge: c, charging: ch } }), 15).codePointAt(0)
  assert.equal(g(100, false), 0xF0079)
  assert.equal(g(47, false), 0xF007E)
  assert.equal(g(12, false), 0xF0083)
  assert.equal(g(12, true), 0xF089C)
  assert.equal(g(3, true), 0xF089F)
})

test("shortcuts: stored order is cleaned, toggled, moved; empty stays empty", () => {
  assert.deepEqual(M.normalizeShortcuts(undefined), M.DEFAULT_SHORTCUTS)
  assert.deepEqual(M.normalizeShortcuts("not json"), M.DEFAULT_SHORTCUTS)
  assert.deepEqual(M.normalizeShortcuts(["ring", "bogus", "ring", "ping"]), ["ring", "ping"])
  assert.deepEqual(M.normalizeShortcuts([]), [])
  assert.deepEqual(M.toggleShortcut(["ring"], "ping"), ["ring", "ping"])
  assert.deepEqual(M.toggleShortcut(["ring", "ping"], "ring"), ["ping"])
  assert.deepEqual(M.moveShortcut(["ring", "share", "clipboard"], "share", -1), ["share", "ring", "clipboard"])
  assert.deepEqual(M.moveShortcut(["ring", "share"], "share", 1), ["ring", "share"])
})

test("settings rows: layout switches, chosen shortcuts in order, then the rest", () => {
  const rows = M.settingsRows({ showMedia: false }, ["messages", "ring"], { ring: true, sms: true })
  assert.deepEqual(rows.filter(r => r.kind === "layout").map(r => r.on), [true, false, true])
  const s = rows.filter(r => r.kind === "shortcut")
  assert.deepEqual(s.slice(0, 2).map(r => r.key), ["messages", "ring"])
  assert.equal(s[0].first, true)
  assert.equal(s[1].last, true)
  assert.equal(s.find(r => r.key === "ping").available, false)
  assert.deepEqual(rows.slice(-2).map(r => r.kind), ["reset", "kdeconnect"])
})

test("notifications: silent empties and media-session duplicates are hidden", () => {
  const d = device({ notifications: [
    { app: "Videos", title: "A talk", text: "Channel", silent: false },
    { app: "Chat", title: "Alex", text: "See you at six", silent: false },
    { app: "System", title: "", text: "", silent: true }
  ] })
  const shown = M.visibleNotifications(d, [{ app: "Videos", title: "A talk" }])
  assert.deepEqual(shown.map(n => n.title), ["Alex"])
})

test("media: player app from identity, phone players only, track line, times", () => {
  assert.equal(M.playerApp("Podcasts - Pixel 8", "Pixel 8"), "Podcasts")
  assert.equal(M.isPhonePlayer("org.mpris.MediaPlayer2.kdeconnect.mpris_1", "Podcasts - Pixel 8", "Pixel 8"), true)
  assert.equal(M.isPhonePlayer("org.mpris.MediaPlayer2.kdeconnect.mpris_2", "Podcasts - Tablet", "Pixel 8"), false)
  assert.equal(M.isPhonePlayer("org.mpris.MediaPlayer2.spotify", "Spotify", "Pixel 8"), false)
  assert.equal(M.trackLine("Ep 1", "Ep 1"), "Ep 1")
  assert.equal(M.trackLine("Song", "Band"), "Song · Band")
  assert.deepEqual([0, 75, 3725].map(M.formatTime), ["0:00", "1:15", "1:02:05"])
})

test("messages: numbers, titles, avatars", () => {
  assert.equal(M.formatNumber("+15145550123"), "+1 514-555-0123")
  assert.equal(M.formatNumber("5145550123"), "+1 514-555-0123")
  assert.equal(M.formatNumber("55555"), "55555")
  assert.equal(M.threadTitle(["Alex", ""], ["+15145550123", "+15145550199"]), "Alex, +1 514-555-0199")
  assert.equal(M.threadTitle([], ["1", "2", "3", "4", "5"]), "1, 2, 3 +2")
  assert.equal(M.avatarInitial("alex"), "A")
  assert.equal(M.avatarInitial("+1 514"), "#")
})

test("messages: thread times and day headers", () => {
  const now = new Date(2026, 8, 26, 10, 0).getTime()
  const at = (y, m, d, h = 9) => new Date(y, m, d, h).getTime()
  assert.deepEqual([at(2026, 8, 26, 8), at(2026, 8, 25), at(2026, 8, 22), at(2026, 5, 3), at(2024, 4, 2)].map(t => M.threadTime(t, now)),
    ["08:00", "Yesterday", "Tue", "Jun 3", "2024-05-02"])
  assert.deepEqual([at(2026, 8, 26), at(2026, 8, 25), at(2024, 4, 2)].map(t => M.dayLabel(t, now)),
    ["Today", "Yesterday", "May 2, 2024"])
})

test("a text-message notification finds its thread by name or number", () => {
  const threads = [{ tid: 1, title: "Alex", addressKeys: "5145550123" }, { tid: 2, title: "55555", addressKeys: "55555" }]
  assert.equal(M.threadForNotification({ app: "Messages", title: "Alex" }, threads), 1)
  assert.equal(M.threadForNotification({ app: "Messages", title: "+1 514-555-0123" }, threads), 1)
  assert.equal(M.threadForNotification({ app: "Chat", title: "Alex" }, threads), -1)
})

test("demo snapshots cover every state the panel draws", () => {
  assert.equal(M.metaLine(M.demoSnapshot(null, "down"), null), "KDE Connect is not running")
  assert.equal(M.metaLine(M.demoSnapshot(null, "none"), null), "No paired device")
  assert.equal(M.pickDevice(M.demoSnapshot(null, "away"), "").reachable, false)
  assert.equal(M.demoSnapshot(null, "").devices[0].notifications.length, 3)
  assert.equal(M.demoSnapshot(snap(device({ name: "Real Name" })), "").devices[0].name, "Pixel 8", "demo never shows the real device name")
})

test("one pace for motion", () => {
  assert.deepEqual(M.MOTION, { outMs: 90, inMs: 220 })
})
