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

test("bar text: the glyph, then the chosen indicators in order; away, the glyph alone", () => {
  const P = M.GLYPH.phone, bars = ["percent"]
  assert.equal(M.barText(device(), bars), P + " 63%")
  assert.equal(M.barText(device({ battery: { charge: 63, charging: true } }), bars), P + " 63%" + M.GLYPH.bolt)
  assert.equal(M.barText(device(), []), P)
  assert.equal(M.barText(device({ reachable: false }), bars), P)
  const all = ["connection", "battery", "percent", "notifications", "messages", "playing", "bubble"]
  const st = { lowPercent: 15, notifications: 3, messages: 2, playing: true }
  assert.equal(M.barText(device(), all, st),
    [P, M.GLYPH.wifi, M.batteryGlyph(device(), 15) + "\u2009" + "63%", M.GLYPH.bell + " 3", M.GLYPH.messages + " 2", M.GLYPH.play].join(" "), "the % is part of the battery beside it")
  assert.equal(M.barText(device({ battery: { charge: 63, charging: true } }), ["battery", "percent"], st),
    [P, M.batteryGlyph(device({ battery: { charge: 63, charging: true } }), 15) + "\u2009" + "63%"].join(" "), "one bolt: the battery glyph has it")
  assert.equal(M.barText(device(), ["messages", "notifications"], { notifications: 0, messages: 0 }), P, "counts hide at 0")
  assert.equal(M.barText(device({ links: ["Bluetooth"] }), ["connection"]), P + " " + M.GLYPH.bluetooth)
  assert.equal(M.barText(device({ reachable: false }), all, st), P + " " + M.GLYPH.wifiOff, "away: a crossed-out link, nothing stale")
})

test("bar: battery only when low; the default; the bubble", () => {
  const P = M.GLYPH.phone
  const low = device({ battery: { charge: 9, charging: false } })
  assert.equal(M.barText(device(), ["battery", "percent"], { lowOnly: true, lowPercent: 15 }), P)
  assert.equal(M.barText(low, ["percent"], { lowOnly: true, lowPercent: 15 }), P + " 9%")
  assert.equal(M.barText(device(), ["battery", "percent"], { lowOnly: false, lowPercent: 15 }), P + " " + M.batteryGlyph(device(), 15) + "\u2009" + "63%", "unticked: always shown")
  assert.deepEqual(M.normalizeBarIndicators(undefined), ["battery", "bubble"], "the default: battery when low, the bubble")
  assert.deepEqual(M.normalizeBarIndicators("not json"), ["battery", "bubble"])
  assert.deepEqual(M.normalizeBarIndicators([]), [], "an empty choice stays empty")
  assert.equal(M.barText(device(), M.DEFAULT_BAR, { lowOnly: true, lowPercent: 15 }), P, "default, healthy: the glyph alone")
  assert.equal(M.barText(low, M.DEFAULT_BAR, { lowOnly: true, lowPercent: 15 }), P + " " + String.fromCodePoint(0xF0083), "default, low: the battery-alert glyph")
  assert.deepEqual(M.normalizeBarIndicators(["playing", "bogus", "playing", "battery"]), ["playing", "battery"])
  assert.equal(M.barBubble(device(), ["bubble"], 4), 4)
  assert.equal(M.barBubble(device(), ["bubble"], 0), 0)
  assert.equal(M.barBubble(device(), ["percent"], 4), 0, "not chosen")
  assert.equal(M.barBubble(device({ reachable: false }), ["bubble"], 4), 0)
  assert.equal(M.barSummary(["percent", "bubble"], true), "Battery %, Notification bubble · battery when low")
  assert.equal(M.barSummary([], false), "The glyph alone")
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

test("cellular signal: 0-4 bars beside the network type, nothing without a network", () => {
  const bars = n => String.fromCodePoint(M.SIGNAL_GLYPHS[n])
  assert.equal(M.networkText(device()), bars(3) + " LTE")
  assert.equal(M.networkText(device({ network: { type: "5G", strength: 0 } })), bars(0) + " 5G", "no service still shows empty bars")
  assert.equal(M.networkText(device({ network: { type: "Unknown", strength: 1 } })), bars(1), "bars alone when the type is unknown")
  assert.equal(M.networkText(device({ network: { type: "LTE", strength: -1 } })), "LTE", "no strength reported: the type alone")
  assert.equal(M.networkText(device({ network: undefined })), "", "a Wi-Fi-only tablet reports no network")
  assert.equal(M.networkText(device({ network: { type: "LTE", strength: 7 } })), bars(4) + " LTE")
  assert.match(M.metaLine(snap(device()), device(), 15), new RegExp(" · Wi-Fi · " + bars(3) + " LTE$", "u"))
  assert.equal(new Set(M.SIGNAL_GLYPHS).size, 5)
})

test("send text: a lone web address is a link, anything else is text", () => {
  assert.equal(M.linkFor(" https://example.com/a?b=1 "), "https://example.com/a?b=1")
  assert.equal(M.linkFor("www.example.com/x"), "https://www.example.com/x")
  assert.equal(M.linkFor("see https://example.com"), "", "a sentence with a link is text")
  assert.equal(M.linkFor("example.com"), "", "no scheme and no www: text")
  assert.equal(M.linkFor("javascript:alert(1)"), "")
  assert.equal(M.linkFor(""), "")
  assert.match(M.composerHint("https://example.com", device(), true), /link; Pixel 8 offers to open it · Ctrl\+Enter pings/)
  assert.equal(M.composerHint("Door code 5555", device(), false), "Enter puts this on Pixel 8's clipboard")
  assert.equal(M.shortcutByKey("text").needs, "share")
  assert.ok(M.DEFAULT_SHORTCUTS.indexOf("text") < 0, "not in the default row; picked in settings")
})

test("section order: known sections once, the missing ones back at their default position", () => {
  const all = ["devices", "actions", "media", "notifications", "received", "photos"]
  assert.deepEqual(M.normalizeSections(undefined), all)
  assert.deepEqual(M.normalizeSections([]), all, "an empty list is not a choice: sections hide by their switch")
  assert.deepEqual(M.normalizeSections(["actions", "media", "notifications"]), all, "an order saved before Devices moved: Devices first")
  assert.deepEqual(M.normalizeSections(["notifications", "devices", "actions", "media"]), ["notifications", "devices", "actions", "media", "received", "photos"], "a saved order gains Received and Photos at the end")
  assert.deepEqual(M.normalizeSections(["media", "bogus", "media", "devices"]), ["media", "actions", "devices", "notifications", "received", "photos"])
  assert.deepEqual(M.normalizeSections('["notifications"]'), ["devices", "actions", "media", "notifications", "received", "photos"], "a hand-edited string; the rest back at their default position")
  const rows = M.settingsRows({ showMedia: false }, [], {}, ["notifications", "media", "devices", "actions"]).filter(r => r.kind === "layout")
  assert.deepEqual(rows.map(r => r.section), ["notifications", "media", "actions", "received", "photos"], "the Devices section is not on the page")
  assert.deepEqual(rows.map(r => [r.first, r.last]), [[true, false], [false, false], [false, false], [false, false], [false, true]])
  assert.deepEqual(rows.map(r => r.on), [true, false, true, true, true])
})

test("settings rows: bar indicators chosen first in order, the rest after, then the low-only switch", () => {
  const rows = M.settingsRows({}, [], {}, null, ["bubble", "percent"], false)
  const bar = rows.filter(r => r.kind === "bar")
  assert.deepEqual(bar.map(r => r.key).slice(0, 3), ["bubble", "percent", "connection"])
  assert.deepEqual(bar.slice(0, 3).map(r => [r.on, r.first, r.last]), [[true, true, false], [true, false, true], [false, false, false]])
  const flag = rows.find(r => r.kind === "barFlag")
  assert.equal(flag.on, false)
  assert.ok(rows.indexOf(flag) > rows.indexOf(bar[bar.length - 1]) && rows.indexOf(flag) < rows.findIndex(r => r.kind === "shortcut"))
  assert.deepEqual(M.toggleBarIndicator(["battery"], "playing"), ["battery", "playing"])
  assert.deepEqual(M.toggleBarIndicator(["battery", "playing"], "battery"), ["playing"])
  assert.deepEqual(M.toggleBarIndicator([], "bogus"), [])
})

test("the glyph and the word follow the device type", () => {
  assert.equal(M.deviceGlyph(device()).codePointAt(0), 0xF011C)
  assert.equal(M.deviceGlyph(device({ type: "tablet" })).codePointAt(0), 0xF04F6)
  assert.equal(M.deviceGlyph(device({ type: "desktop" })).codePointAt(0), 0xF0AAB)
  assert.equal(M.deviceGlyph(device({ type: "smartwatch" })), M.GLYPH.devices)
  assert.equal(M.deviceGlyph(null), M.GLYPH.devices)
  assert.equal(M.barText(device({ type: "tablet" }), ["percent"]), String.fromCodePoint(0xF04F6) + " 63%")
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
  assert.deepEqual(rows.filter(r => r.kind === "layout").map(r => r.on), [true, false, true, true, true])
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

test("a playback notification is hidden even when it names an older track", () => {
  const players = [{ app: "Podcasts", title: "Ep 2" }]
  const d = device({ notifications: [
    { app: "Podcasts", title: "Ep 1", text: "", dismissable: false },
    { app: "Podcasts", title: "New episode out", text: "Ep 3", dismissable: true },
    { app: "Chat", title: "Alex", text: "hi", dismissable: false }
  ] })
  assert.deepEqual(M.visibleNotifications(d, players).map(n => n.title), ["New episode out", "Alex"])
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
  for (const app of ["Messages", "Samsung Messages", "Google Messages", "QKSMS", "Signal", "SMS"]) assert.equal(M.isMessagingApp(app), true, app)
  for (const app of ["WhatsApp", "Gmail", "YouTube"]) assert.equal(M.isMessagingApp(app), false, app)
})

test("demo snapshots cover every state the panel draws", () => {
  assert.equal(M.metaLine(M.demoSnapshot(null, "down"), null), "KDE Connect is not running")
  assert.equal(M.metaLine(M.demoSnapshot(null, "none"), null), "No paired device")
  assert.equal(M.pickDevice(M.demoSnapshot(null, "away"), "").reachable, false)
  // The real device's identity stays with it: its nickname and icon do not
  // show on the demo (#108).
  const live = { daemon: true, devices: [{ id: "real1", name: "Galaxy", type: "phone", paired: true, reachable: true }] }
  const settings = M.readSettings({ devices: { real1: { nickname: "My phone", icon: "F04CE" } } })
  assert.equal(M.deviceTitle(live.devices[0], M.resolveProfile(settings, live.devices[0], true)), "My phone", "the real one keeps it")
  const demoDev = M.pickDevice(M.demoSnapshot(live, "one"), "")
  assert.equal(demoDev.id, "demo")
  assert.equal(M.deviceTitle(demoDev, M.resolveProfile(settings, demoDev, true)), "Pixel 8")
  assert.equal(M.deviceIcon(demoDev, M.resolveProfile(settings, demoDev, true)), M.deviceIcon(demoDev, null))
  assert.equal(M.demoSnapshot(null, "").devices[0].notifications.length, 2, "a text message (reply, actions, a long text) and a group chat")
  assert.equal(M.demoSnapshot(snap(device({ name: "Real Name" })), "").devices[0].name, "Pixel 8", "demo never shows the real device name")
  const away = M.demoSnapshot(snap(device({ reachable: false, can: { sms: false, ring: false } })), "").devices[0]
  assert.equal(away.reachable, true, "the demo device is here even when the real one is away")
  assert.equal(away.can.sms && away.can.ring && away.can.media && away.can.ping, true, "and offers every feature")
})

test("one pace for motion", () => {
  assert.deepEqual(M.MOTION, { outMs: 90, inMs: 220 })
})


test("collapsed sections: one-line summaries and a safe folded state", () => {
  assert.equal(M.mediaSummary("Ep 2", "Ep 2", "Podcasts"), "Ep 2 · Podcasts")
  assert.equal(M.mediaSummary("Song", "Band", "Music"), "Song · Band · Music")
  assert.equal(M.notificationsSummary([]), "Nothing new")
  assert.equal(M.notificationsSummary([{ title: "Alex", text: "See you\n at six" }]), "Alex: See you at six")
  assert.deepEqual(M.collapsedState({ media: true }), { media: true })
  assert.deepEqual(M.collapsedState("media"), {})
  assert.deepEqual(M.collapsedState(null), {})
})

test("demo devices cover requests, away and available", () => {
  const rows = M.devicesListRows(M.demoSnapshot(null, "devices"), M.readSettings({}), 15)
  assert.deepEqual(rows.map(r => [r.kind, r.title]),
    [["device", "Pixel 8"], ["device", "Galaxy Tab"], ["request", "Pixel Tablet"], ["available", "Work laptop"]], "asking to pair before in reach")
  assert.equal(rows[1].status, "Away")
})

test("folded settings sections say what is in them", () => {
  assert.equal(M.layoutSummary({}), "Everything shown")
  assert.equal(M.layoutSummary({ showMedia: false }), "Shortcuts, Notifications, Received, Gallery", "the Devices section is gone from the page")
  assert.equal(M.layoutSummary({ showDevices: false, showShortcuts: false, showMedia: false, showNotifications: false, showReceived: false, showPhotos: false }), "Everything hidden")
  assert.equal(M.layoutSummary({}, ["notifications", "devices", "actions", "media"]), "Notifications, Shortcuts, Now playing, Received, Gallery", "a new order is never hidden")
  assert.equal(M.layoutSummary({ showMedia: false, showDevices: false }, ["media", "notifications"]), "Shortcuts, Notifications, Received, Gallery")
  assert.equal(M.shortcutsSummary(["messages", "ring"]), "Messages, Ring")
  assert.equal(M.shortcutsSummary([]), "None")
})

test("demo messages are made up: fictional names, 555 numbers, one open conversation", () => {
  const now = new Date(2026, 8, 26, 18, 0).getTime()
  const threads = M.demoThreads(now)
  assert.equal(threads.length, 6)
  for (const t of threads) for (const a of t.addresses) assert.match(a, /555/)
  assert.equal(threads.filter(t => !t.read && !t.sent).length, 2)
  const convo = M.demoConversation(now)
  assert.ok(convo.every(m => m.thread === 9001))
  assert.deepEqual(convo.map(m => m.date), [...convo.map(m => m.date)].sort((a, b) => a - b), "oldest first")
  const mms = M.demoConversation(now, "/tmp/pic.jpg").find(m => m.attachments.length)
  assert.equal(mms.attachments[0].thumb, "/tmp/pic.jpg")
  assert.equal(M.demoConversation(now).find(m => m.attachments.length).attachments[0].thumb, "", "no picture: a chip")
})

test("a click is answered when its effect shows in the snapshot", () => {
  const note = { id: "n1", app: "Mail", title: "Hi", text: "One", actions: ["Archive"] }
  const before = JSON.stringify(note)
  const withNote = snap(device({ notifications: [note] }))
  const without = snap(device())
  assert.equal(M.answered("dismiss", withNote, "d1", "n1"), false, "still there: still waiting")
  assert.equal(M.answered("dismiss", without, "d1", "n1"), true)
  assert.equal(M.answered("note", withNote, "d1", "n1", before), false)
  assert.equal(M.answered("note", snap(device({ notifications: [{ ...note, text: "Two" }] })), "d1", "n1", before), true, "changed")
  assert.equal(M.answered("note", without, "d1", "n1", before), true, "gone")
  assert.equal(M.answered("dismiss", snap(), "d1", "n1"), true, "device gone: nothing to wait for")
  assert.equal(M.answered("pair", snap(device({ paired: false })), "d1"), false)
  assert.equal(M.answered("pair", snap(device({ paired: false, pairRequested: true })), "d1"), true)
  assert.equal(M.answered("accept", snap(device({ paired: false, pairRequestedByPeer: true })), "d1"), false)
  assert.equal(M.answered("accept", snap(device()), "d1"), true)
  assert.equal(M.answered("reject", snap(device({ paired: false, pairRequestedByPeer: true })), "d1"), false)
  assert.equal(M.answered("reject", snap(device({ paired: false })), "d1"), true)
  assert.equal(M.answered("unpair", snap(device()), "d1"), false)
  assert.equal(M.answered("unpair", snap(device({ paired: false })), "d1"), true)
  assert.equal(M.waitLimit("note", "Pixel 8").fail, "", "an action may leave the notification as it was")
  assert.equal(M.waitLimit("dismiss", "Pixel 8").fail, "Pixel 8 did not dismiss it")
  assert.equal(M.waitLimit("unpair", "Pixel 8").fail, "Pixel 8 did not answer")
})

test("demo mode drops a notification from its own snapshot only", () => {
  const s = snap(device({ notifications: [{ id: "n1" }, { id: "n2" }] }))
  const after = M.withoutNotification(s, "n1")
  assert.deepEqual(after.devices[0].notifications.map(n => n.id), ["n2"])
  assert.equal(s.devices[0].notifications.length, 2, "the original is left alone")
})

test("a conversation notification groups messages by sender, like the phone", () => {
  const n = { conversation: [
    { sender: "", text: "First, from the title's person" },
    { sender: "Sam", text: "One" }, { sender: "", text: "Two" }, { sender: "Sam", text: "Three" },
    { sender: "Maya", text: "<b>typed</b>" }, { sender: "Maya", text: "  " }
  ] }
  assert.deepEqual(M.conversationGroups(n), [
    { sender: "", text: "First, from the title's person" },
    { sender: "Sam", text: "One\nTwo\nThree" },
    { sender: "Maya", text: "<b>typed</b>" }
  ])
  assert.deepEqual(M.conversationGroups({ text: "plain" }), [], "not a conversation")
})

test("a folded chat shows the latest message and its sender, like the phone", () => {
  const n = { conversation: [{ sender: "Sam", text: "One" }, { sender: "Maya", text: "Two" }, { sender: "", text: "Three" }] }
  assert.deepEqual(M.latestMessage(n), { sender: "Maya", text: "Three" })
  assert.deepEqual(M.latestMessage({ conversation: [{ sender: "", text: "Only" }] }), { sender: "", text: "Only" })
  assert.equal(M.latestMessage({}), null)
})

test("a group chat's unread count is taken apart from its name", () => {
  const chat = (title) => ({ title, conversation: [{ sender: "Sam", text: "Hi" }] })
  assert.deepEqual(M.chatTitle(chat("Book club (8 messages)")), { title: "Book club", count: "8 messages" })
  assert.deepEqual(M.chatTitle(chat("Clube do livro (12 mensagens)")), { title: "Clube do livro", count: "12 mensagens" }, "the app's words, any language")
  assert.deepEqual(M.chatTitle(chat("Book club")), { title: "Book club", count: "" })
  assert.deepEqual(M.chatTitle(chat("Grade (1) class")), { title: "Grade (1) class", count: "" }, "only a count at the very end")
  assert.deepEqual(M.chatTitle(chat("Team (B)")), { title: "Team (B)", count: "" }, "brackets without a number are part of the name")
  assert.deepEqual(M.chatTitle({ title: "Invoice (2 pages)" }), { title: "Invoice (2 pages)", count: "" }, "not a chat: left alone")
})

// ---- Many devices (docs/design/multi-device.md) ----

const phone = (over = {}) => device({ id: "p1", name: "Pixel 8", ...over })
const tablet = (over = {}) => device({ id: "t1", name: "Galaxy Tab", type: "tablet", battery: { charge: 80, charging: false }, ...over })

test("today's settings are read as the defaults, and nothing new is invented", () => {
  const old = { id: "sceny.devices", deviceId: "t1", barIndicators: ["percent"], batteryLowOnly: false, shortcuts: ["ring"], sectionOrder: ["media", "actions"] }
  const s = M.readSettings(old)
  assert.deepEqual(s.defaults.barIndicators, ["percent"])
  assert.equal(s.defaults.batteryLowOnly, false)
  assert.deepEqual(s.defaults.shortcuts, ["ring"])
  assert.deepEqual(s.defaults.sectionOrder.slice(0, 2), ["devices", "media"], "lists merge as today")
  assert.deepEqual(s.order, ["t1"], "the old followed device comes first")
  assert.deepEqual(s.devices, {})
  assert.deepEqual(M.readSettings(undefined).defaults.barIndicators, ["battery", "bubble"])
  assert.deepEqual(M.readSettings({ deviceOrder: ["a", "a", "", "b"], deviceId: "z" }).order, ["a", "b"], "a stored order wins over deviceId")
})

test("device order: stored first, then the rest with the connected ones first", () => {
  const s = M.readSettings({ deviceOrder: ["gone", "t1"] })
  const snapshot = snap(device({ id: "x", reachable: false }), phone(), tablet(), device({ id: "u", paired: false }))
  assert.deepEqual(M.orderedDevices(snapshot, s).map(d => d.id), ["t1", "p1", "x"])
})

test("a profile: identity is the device's own, the rest is its change or the default", () => {
  const s = M.readSettings({ shortcuts: ["ring", "share"], devices: { t1: { nickname: "  Tab \n ", icon: "f04f6", bar: "never", shortcuts: ["share"], showInPanel: false } } })
  const t = M.resolveProfile(s, tablet(), false)
  assert.equal(t.nickname, "Tab", "spaces and line breaks folded")
  assert.equal(t.icon, "F04F6")
  assert.equal(t.bar, "never")
  assert.equal(t.showInPanel, false)
  assert.deepEqual(t.shortcuts, ["share"])
  assert.deepEqual(t.custom, { shortcuts: true })
  const p = M.resolveProfile(s, phone(), true)
  assert.deepEqual([p.nickname, p.icon, p.bar, p.showInPanel], ["", "", "always", true], "first device: always")
  assert.equal(M.resolveProfile(s, phone(), false).bar, "attention", "the others: with attention")
  assert.deepEqual(p.shortcuts, ["ring", "share"])
  assert.equal(M.resolveProfile(M.readSettings({ devices: { p1: { bar: "sideways", icon: "zz" } } }), phone(), true).bar, "always", "unknown values are ignored")
  assert.equal(M.deviceTitle(tablet(), t), "Tab")
  assert.equal(M.deviceTitle(phone(), p), "Pixel 8")
  assert.equal(M.deviceIcon(tablet(), t), String.fromCodePoint(0xF04F6))
  assert.equal(M.deviceIcon(phone(), p), M.GLYPH.phone)
})

test("attention: news, calls, low battery; away is never attention", () => {
  const prof = { barIndicators: ["messages"] }
  assert.equal(M.attention(phone(), prof, {}).any, false)
  assert.equal(M.attention(phone(), prof, { notifications: 2 }).notifications, 2)
  assert.equal(M.attention(phone(), { barIndicators: [] }, { messages: 3 }).messages, 0, "messages count only when the device counts them")
  assert.equal(M.attention(phone(), prof, { messages: 3 }).any, true)
  assert.equal(M.attention(phone(), prof, { call: { state: "ringing" } }).ringing, true)
  assert.equal(M.attention(phone({ battery: { charge: 5, charging: false } }), prof, {}).lowBattery, true)
  assert.equal(M.attention(phone({ reachable: false }), prof, { notifications: 4, call: { state: "ringing" } }).any, false)
})

test("the pill: a chip per device that shows, in order, each with its own icon and bubble", () => {
  const s = M.readSettings({ deviceOrder: ["p1", "t1"], barIndicators: ["bubble"], devices: { t1: { nickname: "Tab" } } })
  const snapshot = snap(phone(), tablet())
  let r = M.chips(snapshot, s, {})
  assert.deepEqual(r.chips.map(c => c.id), ["p1"], "the first: always; the tablet: only with attention")
  assert.equal(r.resting, null)
  r = M.chips(snapshot, s, { t1: { notifications: 2 } })
  assert.deepEqual(r.chips.map(c => [c.id, c.bubble]), [["p1", 0], ["t1", 2]], "a count stays on its own device")
  assert.equal(r.chips[1].text.startsWith(String.fromCodePoint(0xF04F6)), true, "the tablet's own icon")
  const custom = M.readSettings({ deviceOrder: ["p1", "t1"], devices: { t1: { icon: "F0322" } } })
  assert.equal(M.chips(snapshot, custom, { t1: { notifications: 1 } }).chips[1].glyph, String.fromCodePoint(0xF0322))
})

test("the pill never disappears", () => {
  const never = M.readSettings({ deviceOrder: ["p1"], devices: { p1: { bar: "never" } } })
  const one = snap(phone())
  let r = M.chips(one, never, {})
  assert.deepEqual(r.chips, [])
  assert.deepEqual(r.resting, { glyph: M.GLYPH.phone, dimmed: true, ringing: false }, "the first device's icon, dimmed")
  r = M.chips(snap(), M.readSettings({}), {})
  assert.deepEqual(r.resting, { glyph: M.GLYPH.devices, dimmed: false, ringing: false }, "nothing paired: the generic glyph")
  r = M.chips({ daemon: false, devices: [] }, M.readSettings({}), {})
  assert.equal(r.resting.dimmed, true, "KDE Connect stopped: dimmed")
  const attn = M.readSettings({ devices: { p1: { bar: "attention" } } })
  r = M.chips(snap(phone({ reachable: false })), attn, { p1: { notifications: 3 } })
  assert.deepEqual([r.chips.length, r.resting.dimmed], [0, true], "an away device with attention settings: resting, not news")
  assert.equal(M.chips(snap(phone({ reachable: false })), M.readSettings({}), {}).chips[0].dimmed, true, "always: dimmed while away")
})

test("a ringing device always shows, whatever its choice; pairing marks the pill", () => {
  const s = M.readSettings({ deviceOrder: ["p1", "t1"], devices: { t1: { bar: "never" } } })
  const r = M.chips(snap(phone(), tablet()), s, { t1: { call: { state: "ringing" } } }, true)
  assert.deepEqual(r.chips.map(c => [c.id, c.ringing]), [["p1", false], ["t1", true]])
  assert.equal(r.pairing, true)
  assert.equal(M.chips(snap(phone(), tablet()), s, { t1: { call: { state: "missed" } } }).chips.length, 1, "a missed call does not override Never")
})

test("the panel opens on the ringing device, else the first connected one shown in the panel", () => {
  const s = M.readSettings({ deviceOrder: ["p1", "t1", "w1"], devices: { t1: { showInPanel: false } } })
  const w = device({ id: "w1", name: "Work" })
  assert.equal(M.openingDevice(snap(phone({ reachable: false }), tablet(), w), s, {}).id, "w1", "the away first and the hidden tablet are skipped")
  assert.equal(M.openingDevice(snap(phone(), tablet(), w), s, {}).id, "p1")
  assert.equal(M.openingDevice(snap(phone(), tablet(), w), s, { t1: { call: { state: "ringing" } } }).id, "t1", "a call wins, even hidden")
  assert.equal(M.openingDevice(snap(phone({ reachable: false })), M.readSettings({}), {}).id, "p1", "none connected: the first")
  assert.equal(M.openingDevice(snap(), M.readSettings({}), {}), null)
})

test("writing a profile: only what changed, the first device's always written down, the rest untouched", () => {
  const entry = { id: "sceny.devices", shortcuts: ["ring"], deviceId: "p1" }
  const e = M.withProfile(entry, "p1", { nickname: "S23" }, true)
  assert.deepEqual(e.devices, { p1: { bar: "always", nickname: "S23" } })
  assert.equal(e.deviceId, "p1", "kept for a downgrade")
  assert.deepEqual(entry, { id: "sceny.devices", shortcuts: ["ring"], deviceId: "p1" }, "the entry given is not changed")
  const back = M.withProfile(e, "p1", { nickname: null }, true)
  assert.deepEqual(back.devices.p1, { bar: "always" }, "null goes back to the default")
  assert.deepEqual(M.withProfile({}, "t1", { bar: "never" }, false).devices, { t1: { bar: "never" } })
  assert.deepEqual(M.withOrder(e, ["t1", "p1"]).deviceOrder, ["t1", "p1"])
  // Reordering after the first change keeps the old first device "always".
  const reordered = M.readSettings(M.withOrder(e, ["t1", "p1"]))
  assert.equal(M.resolveProfile(reordered, phone(), false).bar, "always")
})

test("demo: several devices, and one asking to pair", () => {
  const many = M.demoSnapshot(null, "many")
  assert.deepEqual(many.devices.map(d => [d.name, d.paired, d.reachable]),
    [["Pixel 8", true, true], ["Galaxy Tab S9", true, true], ["Work laptop", true, false]])
  const withRequest = M.demoSnapshot(null, "many-pair")
  assert.equal(withRequest.devices.filter(d => d.pairRequestedByPeer).length, 1)
  const s = M.readSettings({})
  const pill = M.chips(many, s, { "demo-tab": { notifications: 2, lowPercent: 15 } })
  assert.deepEqual(pill.chips.map(c => c.id), ["demo", "demo-tab"], "the tablet shows: news and a low battery; the away laptop does not")
})

test("settings rows: one device is one flat page with its nickname and icon; several get a device list", () => {
  const s = M.readSettings({})
  const one = snap(phone())
  const edit = M.resolveProfile(s, phone(), true)
  const ctx = (over) => ({ scope: "root", single: true, devices: M.devicesListRows(one, s, 15),
    identity: { nickname: "", icon: "", glyph: M.GLYPH.phone, bar: "always", showInPanel: true }, edit, ...over })
  const flat = M.settingsPageRows(ctx({}))
  const kinds = flat.map(r => r.kind)
  assert.deepEqual(kinds.slice(0, 2), ["nickname", "icon"])
  assert.ok(kinds.includes("editPage") && kinds.includes("kdeconnect"))
  assert.ok(!["layout", "shortcut", "bar", "barFlag", "reset"].some(k => kinds.includes(k)), "sections, shortcuts and the bar are edited on the page")
  assert.ok(!kinds.includes("device") && !kinds.includes("barPlace"), "one device: no list, no bar place")
  assert.ok(!flat.some(r => r.kind === "layout" && r.section === "devices"), "the Devices section is gone")
  const two = snap(phone(), tablet(), device({ id: "n", name: "New", paired: false, pairRequestedByPeer: true, verificationKey: "4E5A3506" }), device({ id: "a", name: "Near", paired: false }))
  const list = M.devicesListRows(two, s, 15)
  assert.deepEqual(list.map(r => [r.kind, r.id]), [["device", "p1"], ["device", "t1"], ["request", "n"], ["available", "a"]])
  assert.equal(list[2].status, "Wants to pair")
  assert.equal(list[2].pairKey, "4E5A3506", "the key is drawn apart (PairingKey)")
  assert.ok(M.settingsPageRows({ scope: "root", single: false, devices: list, edit: M.resolveProfile(M.readSettings({}), null, true) })
    .filter(r => r.kind !== "request" && r.kind !== "available").every(r => !r.pairKey), "only pairing rows carry a key")
  const root = M.settingsPageRows({ scope: "root", single: false, devices: list, edit })
  assert.deepEqual(root.map(r => r.kind), ["device", "device", "request", "available", "defaults", "connection", "addDevice", "kdeconnect"])
})

test("settings rows: a device's page has identity, its groups, a reset per changed group, and Unpair", () => {
  const s = M.readSettings({ devices: { t1: { shortcuts: ["share"], bar: "never" } } })
  const edit = M.resolveProfile(s, tablet(), false)
  const rows = M.settingsPageRows({ scope: "device", single: false, identity: { nickname: "", icon: "", glyph: "x", bar: edit.bar, showInPanel: true }, edit, can: tablet().can })
  const kinds = rows.map(r => r.kind)
  assert.deepEqual(kinds.slice(0, 4), ["nickname", "icon", "barPlace", "showInPanel"])
  assert.ok(kinds.includes("editPage") && !["layout", "shortcut", "bar", "barFlag"].some(k => kinds.includes(k)))
  assert.equal(rows.find(r => r.kind === "barPlace").value, "never")
  assert.deepEqual(rows.filter(r => r.kind === "resetGroup").map(r => r.key), ["shortcuts"])
  assert.equal(kinds[kinds.length - 1], "unpair")
  assert.ok(!kinds.includes("kdeconnect") && !kinds.includes("reset"))
  const defaults = M.settingsPageRows({ scope: "defaults", single: false, edit: M.resolveProfile(s, null, true) })
  assert.ok(!defaults.some(r => ["nickname", "device", "unpair", "resetGroup"].includes(r.kind)))
  assert.ok(defaults.some(r => r.kind === "bar") && defaults.some(r => r.key === "showCalls"), "the defaults keep the bar: they have no page")
  assert.equal(defaults[defaults.length - 1].kind, "reset")
})

test("moving devices never changes how they show in the bar", () => {
  const entry = { deviceOrder: ["p1", "t1"] }
  const two = snap(phone(), tablet())
  const ids = M.movedOrder(two, M.readSettings(entry), "t1", -1)
  assert.deepEqual(ids, ["t1", "p1"])
  const e = M.withDeviceOrder(entry, two, ids)
  assert.deepEqual(e.deviceOrder, ["t1", "p1"])
  assert.deepEqual(e.devices, { p1: { bar: "always" }, t1: { bar: "attention" } }, "both places written down")
  const s = M.readSettings(e)
  assert.equal(M.resolveProfile(s, phone(), false).bar, "always")
  assert.equal(M.resolveProfile(s, tablet(), true).bar, "attention")
  const chosen = M.withDeviceOrder({ deviceOrder: ["p1", "t1"], devices: { t1: { bar: "never" } } }, two, ["t1", "p1"])
  assert.equal(chosen.devices.t1.bar, "never", "a place the user chose is kept")
  assert.equal(M.ICON_CHOICES.every(c => /^[0-9A-F]{5}$/.test(c.code)), true)
  assert.equal(M.groupCustom({ shortcuts: true }, "shortcuts"), true)
  assert.equal(M.groupCustom({ shortcuts: true }, "bar"), false)
})

test("orders: the shown order only, a place and a count per row, and a move onto another row", () => {
  const rows = M.settingsRows({}, ["ring", "share"], null, ["devices", "actions", "media", "notifications"], ["bubble"], true)
  const layout = rows.filter(r => r.kind === "layout")
  assert.deepEqual(layout.map(r => [r.section, r.pos, r.count, r.first]), [["actions", 0, 5, true], ["media", 1, 5, false], ["notifications", 2, 5, false], ["received", 3, 5, false], ["photos", 4, 5, false]],
    "the hidden Devices section takes no place")
  assert.deepEqual(rows.filter(r => r.kind === "shortcut" && r.on).map(r => [r.key, r.pos, r.count]), [["ring", 0, 2], ["share", 1, 2]])
  assert.deepEqual(M.moveTo(["a", "b", "c", "d"], "d", "b"), ["a", "d", "b", "c"], "up: before the target")
  assert.deepEqual(M.moveTo(["a", "b", "c", "d"], "a", "c"), ["b", "c", "a", "d"], "down: after the target")
  assert.deepEqual(M.moveTo(["a", "b"], "a", "z"), ["a", "b"])
  assert.deepEqual(M.moveShortcut(M.visibleSections(["devices", "actions", "media"]), "media", -1), ["media", "actions", "notifications", "received", "photos"])
})

test("moving an item: where it lands, how far the others slide, how far it glides", () => {
  const rows = () => 50, gap = 6            // three rows of 50, 6 apart: 56 each
  assert.equal(M.reorderTarget(1, 0, 3, rows, gap), 1)
  assert.equal(M.reorderTarget(1, 27, 3, rows, gap), 1, "not past the next row's middle")
  assert.equal(M.reorderTarget(1, 29, 3, rows, gap), 2, "past it: its place")
  assert.equal(M.reorderTarget(1, 500, 3, rows, gap), 2, "never past the end")
  assert.equal(M.reorderTarget(1, -29, 3, rows, gap), 0)
  assert.equal(M.reorderTarget(0, -500, 3, rows, gap), 0)
  // The middle one of three, down one: the bottom one slides up, the top stays.
  assert.deepEqual([0, 1, 2].map(i => M.reorderShift(i, 1, 2, 56)), [0, 0, -56])
  assert.deepEqual([0, 1, 2].map(i => M.reorderShift(i, 2, 0, 56)), [56, 56, 0], "the last to the top: both slide down")
  assert.deepEqual([0, 1, 2].map(i => M.reorderShift(i, -1, -1, 56)), [0, 0, 0], "nothing moving")
  assert.equal(M.reorderOffset(1, 2, rows, gap), 56)
  assert.equal(M.reorderOffset(2, 0, rows, gap), -112)
  // Tabs of different widths: the glide covers the widths it passes.
  const tabs = i => [80, 140, 100][i]
  assert.equal(M.reorderOffset(0, 2, tabs, 4), 140 + 4 + 100 + 4)
  assert.equal(M.reorderTarget(0, 80, 3, tabs, 4), 1, "past the middle of the 140 wide tab")
})

test("the pill in parts: only a low battery is urgent; a ticked indicator goes to its natural place", () => {
  const low = device({ battery: { charge: 9, charging: false } })
  const parts = M.barParts(low, ["bubble", "battery", "percent", "notifications"], { lowPercent: 15, notifications: 2 })
  assert.deepEqual(parts.map(p => p.urgent), [false, true, false], "glyph, battery with its %, bell")
  assert.equal(parts[1].text, M.batteryGlyph(low, 15) + "\u2009" + "9%")
  assert.deepEqual([parts[1].glyph, parts[1].suffix], [M.batteryGlyph(low, 15), "9%"], "drawn apart, spaced by the glyph's ink")
  assert.deepEqual(parts.map(p => p.key), ["glyph", "battery", "notifications"], "each part keeps its key, so the bar can slide it")
  assert.ok(M.barParts(low, ["battery"], {}).every(p => M.BAR_PART_KEYS.includes(p.key)))
  assert.deepEqual(M.barParts(low, ["percent", "battery"], { lowPercent: 15 }).map(p => p.text), [M.GLYPH.phone, "9%", M.batteryGlyph(low, 15)], "not beside it: apart")
  assert.equal(M.barText(low, ["percent"], { lowPercent: 15 }), parts[0].text + " 9%")
  assert.ok(M.barParts(device(), ["battery", "percent"], { lowPercent: 15 }).every(p => !p.urgent), "not low: nothing red")
  assert.deepEqual(M.toggleBarIndicator(["battery", "bubble"], "percent"), ["battery", "percent", "bubble"], "% right after the battery")
  assert.deepEqual(M.toggleBarIndicator(["bubble"], "connection"), ["connection", "bubble"])
  assert.deepEqual(M.toggleBarIndicator(["bubble", "percent"], "battery"), ["battery", "bubble", "percent"], "before the first that comes after it")
  assert.deepEqual(M.toggleBarIndicator([], "playing"), ["playing"])
  const chip = M.chips(snap(low), M.readSettings({ barIndicators: ["battery", "percent"], batteryLowOnly: false }), {}).chips[0]
  assert.deepEqual(chip.parts.map(p => p.urgent), [false, true])
})

test("editing in place: the grid moves, and every shortcut shows", () => {
  // Four tiles in two columns: the first to the last place, the others step back.
  assert.deepEqual([0, 1, 2, 3].map(i => M.reorderSlot(i, 0, 3)), [3, 0, 1, 2])
  assert.deepEqual([0, 1, 2, 3].map(i => M.reorderSlot(i, 3, 1)), [0, 2, 3, 1])
  assert.deepEqual([0, 1, 2].map(i => M.reorderSlot(i, -1, -1)), [0, 1, 2])
  assert.deepEqual(M.gridSlot(5, 4, 90, 70, 8), { x: 98, y: 78 })
  assert.equal(M.gridTarget(0, 0, 0, 5, 4, 90, 70, 8), 0)
  assert.equal(M.gridTarget(0, 100, 0, 5, 4, 90, 70, 8), 1, "one cell right")
  assert.equal(M.gridTarget(0, 0, 80, 5, 4, 90, 70, 8), 4, "one row down")
  assert.equal(M.gridTarget(0, -100, 500, 5, 4, 90, 70, 8), 4, "far below: the last slot, never past it")
  const tiles = M.editShortcutTiles(["ring", "share"], { ring: true, share: true })
  assert.deepEqual(tiles.slice(0, 2).map(t => [t.key, t.chosen, t.pos]), [["ring", true, 0], ["share", true, 1]])
  assert.equal(tiles.length, M.SHORTCUTS.length, "every shortcut, the rest to add")
  assert.ok(tiles.slice(2).every(t => !t.chosen && t.pos === -1))
})

test("calls: ringing for RING_MS at most, missed until closed or MISSED_MS", () => {
  const at = 1_000_000
  const ringing = device({ call: { event: "ringing", number: "+15145550123", name: "Alex Rivera", at } })
  const c = M.callState(ringing, at + 1000, 0)
  assert.deepEqual([c.state, c.who, c.detail], ["ringing", "Alex Rivera", "+1 514-555-0123"])
  assert.equal(M.callState(ringing, at + M.RING_MS + 1, 0), null, "no end signal: ringing runs out")
  assert.equal(M.callState(ringing, at + 1000, at), null, "closed")
  assert.equal(M.callState(device({ reachable: false, call: ringing.call }), at, 0), null, "away: nothing stale")
  const missed = device({ call: { event: "missed", number: "+15145550123", name: "", at } })
  const m = M.callState(missed, at + M.RING_MS + 1, 0)
  assert.deepEqual([m.state, m.who, m.detail], ["missed", "+1 514-555-0123", ""])
  assert.equal(M.callState(missed, at + M.MISSED_MS + 1, 0), null)
  assert.equal(M.callState(device({ call: { event: "talking", at } }), at, 0), null)
  assert.equal(M.callState(device({ call: { event: "ringing", number: "", name: "", at } }), at, 0).who, "Unknown number")
  assert.equal(M.callExpiresIn(c, at + 1000), M.RING_MS - 1000)
  assert.equal(M.callExpiresIn(null, at), -1)
  const demo = device({ call: M.demoCall("ringing", at) })
  assert.equal(M.callState(demo, at + M.RING_MS * 10, 0).state, "ringing", "a demo call rings until closed")
  assert.equal(M.callExpiresIn(M.callState(demo, at, 0), at), -1)
  assert.equal(M.callState(demo, at, at), null)
  assert.equal(M.callHeading(c), "INCOMING CALL")
  assert.equal(M.RING_BEAT.waveMs, M.MOTION.outMs, "the waves light on the plugin's pace")
  assert.equal(M.ringMs(), 3 * M.MOTION.outMs + M.MOTION.inMs)
  assert.deepEqual(M.ringPhases().map(p => [p.lit, p.ms]),
    [[true, M.ringMs()], [false, M.RING_BEAT.gapMs], [true, M.ringMs()], [false, M.RING_BEAT.restMs]])
  assert.match(M.callHeading(m), /^MISSED CALL · \d\d:\d\d$/)
})

test("calls lead the bar text and the tooltip", () => {
  const P = M.GLYPH.phone
  const c = { state: "ringing", who: "Alex Rivera" }
  assert.equal(M.barText(device(), ["percent"], { call: c }), [P, M.GLYPH.callRing, "63%"].join(" "))
  assert.equal(M.barText(device(), [], { call: { state: "missed" } }), P + " " + M.GLYPH.callMissed)
  assert.equal(M.barText(device({ reachable: false }), [], { call: c }), P)
  assert.match(M.tooltip(snap(device()), device(), "", 0, c), /\nCall from Alex Rivera/)
})

test("calls with several devices: the card shows a ringing one first, else the latest missed; a call leads its chip", () => {
  const ringing = { state: "ringing", at: 5, device: "t1" }, missed = { state: "missed", at: 9, device: "p1" }
  assert.equal(M.shownCall({ p1: missed, t1: ringing }, ["p1", "t1"]), ringing)
  assert.equal(M.shownCall({ p1: missed, t1: { state: "missed", at: 3 } }, ["p1", "t1"]), missed)
  assert.equal(M.shownCall({}, ["p1"]), null)
  const s = M.readSettings({ deviceOrder: ["p1", "t1"], devices: { t1: { bar: "never" } } })
  const pill = M.chips(snap(phone(), tablet()), s, { t1: { call: { state: "ringing" } } })
  assert.deepEqual(pill.chips.map(c => [c.id, c.ringing]), [["p1", false], ["t1", true]], "a ringing device shows, even set Never")
  assert.equal(pill.chips[1].parts[1].text, M.GLYPH.callRing, "the call leads, after the device's icon")
  const flags = M.settingsRows({}, [], {}, null, [], true, false).filter(r => r.kind === "barFlag")
  assert.deepEqual(flags.map(r => [r.key, r.on]), [["batteryLowOnly", true], ["showCalls", false]])
})

test("editing the bar: the chosen indicators in order with their place, then the rest; Calls is in the bar group", () => {
  const tiles = M.editBarTiles(["bubble", "battery"])
  assert.deepEqual(tiles.slice(0, 2).map(t => [t.key, t.chosen, t.pos]), [["bubble", true, 0], ["battery", true, 1]])
  assert.equal(tiles.length, 7)
  assert.ok(tiles.slice(2).every(t => !t.chosen && t.pos === -1))
  assert.deepEqual(tiles.slice(2).map(t => t.key), ["connection", "percent", "notifications", "messages", "playing"])
  const s = M.readSettings({ devices: { t1: { showCalls: false } } })
  assert.ok(M.groupCustom(M.resolveProfile(s, tablet(), false).custom, "bar"), "a device's Calls switch marks its bar custom")
})

test("the app's QR code: qrencode's text read as a square grid", () => {
  // A made-up 21 x 21 grid: a finder pattern's top row, dark and light.
  const row = (n) => Array.from({ length: 21 }, (_, c) => (c + n) % 2 === 0 ? "##" : "  ").join("")
  const text = Array.from({ length: 21 }, (_, r) => row(r)).join("\n") + "\n"
  const grid = M.qrGrid(text)
  assert.equal(grid.size, 21)
  assert.equal(grid.dark[0][0], true)
  assert.equal(grid.dark[0][1], false)
  assert.equal(grid.dark[1][0], false)
  assert.equal(M.qrGrid(""), null, "nothing: no code")
  assert.equal(M.qrGrid(text.replace("##", "#")), null, "a ragged row: no code")
  assert.match(M.APP_LINKS.play, /^https:\/\/play\.google\.com\/.*org\.kde\.kdeconnect_tp$/)
  assert.match(M.APP_LINKS.appStore, /^https:\/\/apps\.apple\.com\/app\/kde-connect\/id1580245991$/)
})

test("files: a section of its own, joining saved orders at the end; sizes, images, summaries, demo", () => {
  assert.deepEqual(M.normalizeSections(["devices", "notifications", "actions", "media"]), ["devices", "notifications", "actions", "media", "received", "photos"], "a saved order: Received and Photos last")
  assert.deepEqual(M.visibleSections(["devices", "photos", "actions", "received", "media", "notifications"]), ["photos", "actions", "received", "media", "notifications"])
  assert.equal(M.layoutBySection("photos").key, "showPhotos")
  assert.equal(M.layoutBySection("received").key, "showReceived")
  assert.equal(M.sizeText(900), "900 B")
  assert.equal(M.sizeText(2150), "2 KB")
  assert.equal(M.sizeText(3.4 * 1024 * 1024), "3.4 MB")
  assert.ok(M.isImage("IMG_1.JPG") && !M.isImage("notes.txt"))
  assert.equal(M.fileUri("/home/u/Downloads/a b#1?.pdf"), "file:///home/u/Downloads/a%20b%231%3F.pdf", "each part encoded apart")
  assert.equal(M.photosSummary([{}, {}]), "2 photos")
  assert.equal(M.photosSummary([{}, { video: true }]), "1 photo, 1 video")
  assert.equal(M.photosSummary([{ video: true }, { video: true }]), "2 videos")
  const apply = (keys, ops) => {
    const cur = keys.slice()
    ops.forEach(o => {
      if (o.op === "remove") cur.splice(o.at, 1)
      else if (o.op === "move") cur.splice(o.to, 0, cur.splice(o.from, 1)[0])
      else cur.splice(o.at, 0, o.key)
    })
    return cur
  }
  for (const [from, to] of [[["a", "b", "c", "d"], ["a", "c", "d", "e"]], [["a", "b"], ["c", "a", "b"]],
                            [["a", "b", "c"], ["c", "b", "a"]], [[], ["a", "b"]], [["a", "b"], []]]) {
    assert.deepEqual(apply(from, M.listOps(from, to)), to, from.join("") + " -> " + to.join(""))
  }
  assert.deepEqual(M.listOps(["a", "b", "c", "d"], ["a", "c", "d", "e"]), [{ op: "remove", at: 1 }, { op: "insert", at: 3, key: "e" }],
    "one gone: the rest stay (they glide), one new at the end")
  const a = [{ path: "/p/1.jpg", at: 1, thumb: "/t/1.jpg" }]
  assert.equal(M.photosKey(a), M.photosKey(JSON.parse(JSON.stringify(a))), "the same photos in a new list: the same tiles")
  assert.notEqual(M.photosKey(a), M.photosKey([{ path: "/p/1.jpg", at: 1, thumb: "" }]), "a thumbnail arriving redraws")
  assert.equal(M.photosSummary([]), "Nothing new")
  assert.equal(M.receivedSummary([{ name: "a.pdf" }, { name: "b.txt" }]), "a.pdf and 1 more")
  assert.equal(M.receivedSummary([{ name: "a.pdf" }]), "a.pdf")
  const own = M.demoPhotos("/x/picture.jpg", 0, Array.from({ length: 10 }, (_, i) => "/g/" + i + ".jpg"))
  assert.equal(own.length, 8, "the demo's own pictures: two rows at most")
  assert.ok(own.every(p => p.demo && !p.clip && p.thumb === p.path))
  const photos = M.demoPhotos("/x/picture.jpg", 0)
  assert.equal(photos.length, 4)
  assert.ok(photos.every(p => p.demo && p.clip.length === 4 && p.album))
  assert.equal(photos.filter(p => p.video).length, 1, "one video, for its badge")
  assert.ok(M.demoReceived(0).every(r => r.path.startsWith("/demo/")), "made up: nothing real")
})

test("connection: this computer's checks, ignored ones, requests and devices to pair; the gear's count", () => {
  const checks = [
    { key: "installed", ok: true, label: "KDE Connect installed", status: "Installed" },
    { key: "running", ok: true, label: "KDE Connect running", status: "Running" },
    { key: "firewall", ok: false, label: "Firewall lets devices in", status: "Closed", detail: "Ports closed", fix: "firewall", fixLabel: "Allow" },
    { key: "network", ok: true, label: "On a network", status: "192.168.1.0/24" },
    { key: "paired", ok: true, label: "A device is paired" }
  ]
  const devices = [{ kind: "device", id: "p1" }, { kind: "available", id: "a" }, { kind: "request", id: "n" }]
  const rows = M.connectionRows(checks, [])
  assert.deepEqual(rows.map(r => r.kind + ":" + r.key), ["check:kdeconnect", "check:firewall", "check:network"], "this computer only, one row per thing")
  assert.deepEqual([rows[0].label, rows[0].status, rows[0].ok], ["KDE Connect", "Running", true])
  const stopped = M.connectionRows([{ key: "installed", ok: true, status: "Installed" }, { key: "running", ok: false, status: "Stopped", fix: "start", fixLabel: "Start" }], [])
  assert.deepEqual([stopped[0].label, stopped[0].status, stopped[0].fix], ["KDE Connect", "Stopped", "start"], "stopped: the one row says so, with Start")
  const missing = M.connectionRows([{ key: "installed", ok: false, status: "Not installed", fix: "install", fixLabel: "Install" }, { key: "running", ok: false, status: "Stopped" }], [])
  assert.deepEqual([missing[0].status, missing[0].fix, M.connectionIssues([{ key: "installed", ok: false }, { key: "running", ok: false }], [])], ["Not installed", "install", 1], "not installed: one issue, not two")
  assert.deepEqual(M.addDeviceRows(devices).map(r => r.kind + ":" + r.id), ["request:n", "available:a"], "adding: requests first, then devices in reach")
  assert.equal(rows[1].fix, "firewall")
  assert.equal(M.connectionIssues(checks, []), 1)
  assert.equal(M.connectionSummary(checks, []), "1 to fix")
  assert.equal(M.connectionIssues(checks, ["firewall"]), 0, "ignored: no dot")
  assert.ok(M.connectionRows(checks, ["firewall"])[1].ignored)
  assert.equal(M.connectionSummary([], []), "Checking…")
})

test("reconnect: where it was last seen, another network, and what to try after a search", () => {
  const now = 10 * 3600 * 1000
  const away = device({ reachable: false, name: "Galaxy S23", lastSeen: { link: "LAN", address: "192.168.1.20", at: now - 12 * 60000 } })
  assert.deepEqual(M.awayState(away, "192.168.1.0/24", 0, now), { lines: ["Last seen on Wi-Fi at 192.168.1.20, 12 min ago"], searching: false })
  assert.match(M.awayState(away, "10.0.0.0/24", 0, now).lines[1], /Likely on another network/)
  assert.equal(M.awayState(away, "192.168.1.0/24", now - 1000, now).searching, true, "looking for SEARCH_MS")
  const after = M.awayState(away, "192.168.1.0/24", now - M.SEARCH_MS, now)
  assert.match(after.lines[1], /^Not found\. On Galaxy S23: open KDE Connect, and join the same Wi-Fi; set the app's battery use to Unrestricted$/)
  assert.doesNotMatch(M.awayState(device({ reachable: false, name: "Pixel 8" }), "", 1, now).lines[1], /Unrestricted/, "Samsung advice only for Samsung")
  assert.equal(M.awayState(device({ reachable: false }), "", 0, now).lines[0], "Not seen by this computer yet")
  assert.equal(M.inNetwork("192.168.1.20", "192.168.1.0/24"), true)
  assert.equal(M.inNetwork("192.168.2.20", "192.168.1.0/24"), false)
  assert.equal(M.inNetwork("", "192.168.1.0/24"), null)
})

test("with no saved order, connected devices keep KDE Connect's order, whatever joins", () => {
  const dev = (id, reachable) => ({ id, name: id, paired: true, reachable })
  const list = []
  for (let i = 0; i < 12; i++) list.push(dev("d" + i, i % 3 !== 1))
  const ids = M.orderedDevices({ devices: list }, M.readSettings({})).map(d => d.id)
  assert.deepEqual(ids.filter(id => Number(id.slice(1)) % 3 !== 1), ["d0", "d2", "d3", "d5", "d6", "d8", "d9", "d11"], "connected, in their order")
  assert.deepEqual(ids.slice(-4), ["d1", "d4", "d7", "d10"], "then away ones, in their order")
})

test("pairing actions show their result in place: no toast unless they fail", () => {
  assert.ok(["pair", "accept", "reject"].every(k => M.shownInPlace(k)))
  assert.ok(!M.shownInPlace("ring") && !M.shownInPlace("unpair"))
})

test("the panel goes back where it was for five minutes, unless it must open elsewhere", () => {
  const left = { at: 1000, settingsOpen: false, messagesOpen: true, scope: "root", device: "p1", y: 0 }
  assert.equal(M.placeToResume(left, 1000 + 60000, {}), left, "a minute later: back to messages")
  assert.equal(M.placeToResume(left, 1000 + M.KEEP_PLACE_MS, {}), null, "five minutes later: the main page")
  assert.equal(M.placeToResume(left, 500, {}), null, "a clock that went back: fresh")
  assert.equal(M.placeToResume(left, 2000, { openingScope: "connection" }), null, "setup comes first")
  assert.equal(M.placeToResume(left, 2000, { requested: "p2" }), null, "another device's chip: that device")
  assert.equal(M.placeToResume(left, 2000, { requested: "p1" }), left, "the same device's chip: back where it was")
  assert.equal(M.placeToResume(Object.assign({}, left, { messagesOpen: false }), 2000, {}), null, "the main page at its top: nothing to go back to")
  assert.equal(M.placeToResume(null, 2000, {}), null)
})

test("a pairing asked here counts down KDE Connect's 30 seconds", () => {
  assert.equal(M.pairSecondsLeft(0, 0), 30)
  assert.equal(M.pairSecondsLeft(0, 7400), 23)
  assert.equal(M.pairSecondsLeft(0, 45000), 0, "never below 0")
  assert.equal(M.pairSecondsLeft(5000, 4000), 30, "a clock read before the start: never above 30")
})

test("screen and apps: an optional check never lights the gear's dot", () => {
  const checks = [{ key: "installed", ok: true, status: "Installed" }, { key: "running", ok: true, status: "Running" },
    { key: "screen", ok: false, optional: true, status: "Not installed", detail: "scrcpy and adb", fix: "screen", fixLabel: "Install" }]
  const rows = M.connectionRows(checks, [])
  const screen = rows.find(r => r.key === "screen")
  assert.deepEqual([screen.label, screen.optional, screen.fix, screen.ignored], ["Screen and apps", true, "screen", false])
  assert.equal(M.connectionIssues(checks, []), 0)
  assert.equal(M.connectionSummary(checks, []), "1 more to set up", "optional and off: more can be done, nothing to fix")
})

test("connection pills: on, off (more can be set up) and failing", () => {
  const base = [{ key: "installed", ok: true, status: "Installed" }, { key: "running", ok: true, status: "Running" },
    { key: "firewall", ok: false, status: "Closed", fix: "firewall" }, { key: "network", ok: true }]
  const installed = base.concat([{ key: "screen", ok: true, optional: true, status: "scrcpy 4.1", fix: "setup" }])
  const states = (checks, ignored, ready) => M.connectionPills(checks, ignored, ready).map(p => p.label + ":" + p.state)
  assert.deepEqual(states(installed, [], false), ["KDE Connect:on", "Firewall:fail", "Network:on", "Screen:off"],
    "installed, not set up on the device: off, not on")
  assert.deepEqual(states(installed, ["firewall"], true), ["KDE Connect:on", "Firewall:off", "Network:on", "Screen:on"], "ignored reads off")
  assert.equal(M.connectionSummary(installed, [], false), "1 to fix", "a fix comes first")
  assert.equal(M.connectionSummary(installed, ["firewall"], false), "2 more to set up")
  assert.equal(M.connectionSummary(installed, ["firewall"], true), "1 more to set up")
  const allOn = base.map(c => c.key === "firewall" ? Object.assign({}, c, { ok: true }) : c).concat([installed[4]])
  assert.equal(M.connectionSummary(allOn, [], true), "Everything on")
  const row = M.connectionRows(installed, [], false).find(r => r.key === "screen")
  assert.deepEqual([row.ok, row.status, row.fix], [false, "Not set up on the device", "setup"])
  const on = M.connectionRows(installed, [], true).find(r => r.key === "screen")
  assert.deepEqual([on.ok, on.status, on.fix], [true, "On", ""])
  const pills = M.settingsPageRows({ scope: "root", single: true, devices: [], connectionPills: M.connectionPills(installed, [], false) })
    .find(r => r.kind === "connection").pills
  assert.equal(pills.length, 4)
})

test("screen and apps: each state's line, current step and actions", () => {
  const phone = { name: "Pixel 8" }
  const step = s => s.steps.filter(x => x.current).map(x => x.key)[0] || ""
  const acts = s => s.actions.map(a => a.key)
  const checking = M.screenSetup(null, phone, null)
  assert.deepEqual([checking.line, acts(checking)], ["Checking…", []])
  const tools = M.screenSetup(M.demoScreen("tools"), phone, null)
  assert.deepEqual([step(tools), acts(tools)], ["tools", ["install"]])
  const pair = M.screenSetup(M.demoScreen("pair"), phone, null)
  assert.deepEqual([step(pair), acts(pair), pair.showQr], ["developer", ["pair", "check"], false])
  assert.ok(pair.usbNote !== "", "older phones: the cable")
  const waiting = M.screenSetup(M.demoScreen("pair"), phone, { phase: "qr", qr: { size: 21, dark: [] } })
  assert.deepEqual([acts(waiting), waiting.showQr, waiting.pairingNote], [["stopPair", "check"], true, "Waiting for Pixel 8 to scan it…"])
  assert.equal(step(waiting), "pair", "a code on show: scanning it is the step")
  const failed = M.screenSetup(M.demoScreen("pair"), phone, { phase: "error", message: "The code was not scanned in time" })
  assert.deepEqual([acts(failed)[0], failed.showQr, failed.pairingNote], ["pair", false, "The code was not scanned in time"])
  const seen = M.screenSetup(M.demoScreen("seen"), phone, null)
  assert.deepEqual([seen.steps.map(x => x.done), step(seen)], [[true, true, true, false], "pair"], "Wireless debugging seen: ticked, the code is next")
  assert.equal(seen.line, "Wireless debugging is on: scan the code with Pixel 8")
  const off = M.screenSetup(M.demoScreen("off"), phone, null)
  assert.deepEqual([step(off), acts(off)[0]], ["wireless", "pair"], "off: trusted before; Wireless debugging is the step")
  assert.match(off.line, /Wireless debugging is off on Pixel 8/)
  const ready = M.screenSetup(M.demoScreen("ready"), phone, null)
  assert.deepEqual([ready.line, acts(ready)], ["Ready over Wi-Fi · Android 16", ["open", "dockOn", "dockOff"]])
  assert.equal(M.screenRows(ready)[0].label, "Show the screen")
  assert.deepEqual(M.screenRows(ready).slice(1).map(r => r.on), [true, false], "opens under the bar unless chosen otherwise")
  assert.deepEqual(M.screenRows(M.screenSetup(M.demoScreen("ready"), phone, null, false)).slice(1).map(r => r.on), [false, true])
  assert.equal(M.readSettings({}).defaults.screenDocked, true)
  const usb = M.screenSetup({ state: "ready", tools: { ok: true }, via: "usb", android: "9", apps: false }, phone, null)
  assert.equal(usb.line, "Ready over USB · Android 9. Apps in windows need Android 10")
  assert.match(M.screenSetup(M.demoScreen("pair"), { name: "Galaxy S24" }, null).steps[1].text, /Software information/, "Samsung's own path")
})

test("screen and apps: set up adds the Screen shortcut once, where the device's shortcuts live", () => {
  const dev = { id: "p1", paired: true }
  const one = M.readSettings({ shortcuts: ["ring", "messages"] })
  const changes = M.screenShortcutChanges({ shortcuts: ["ring", "messages"] }, "p1", M.resolveProfile(one, dev, true), true, true)
  assert.deepEqual(changes.shortcuts, ["ring", "messages", "screen"], "one device: the flat keys")
  assert.equal(changes.devices.p1.screenShortcut, "added")
  const after = M.readSettings(Object.assign({ shortcuts: ["ring", "messages"] }, changes, { shortcuts: ["ring"] }))
  assert.equal(M.screenShortcutChanges({}, "p1", M.resolveProfile(after, dev, true), true, true), null, "taken away later: stays away")
  const many = M.readSettings({})
  const own = M.screenShortcutChanges({}, "p1", M.resolveProfile(many, dev, false), false, false)
  assert.ok(!("shortcuts" in own), "several devices: not the defaults")
  assert.deepEqual(own.devices.p1.shortcuts.slice(-1), ["screen"])
  const has = M.readSettings({ shortcuts: ["screen"] })
  assert.ok(!("shortcuts" in M.screenShortcutChanges({}, "p1", M.resolveProfile(has, dev, true), true, true)), "already there: only the note")
})

test("screen opening: any device's shape, where the card is", () => {
  const top = { barPos: "top", screenW: 2560, screenH: 1440, barW: 2560, barH: 35, gap: 5, margin: 5, anchorX: 2200, anchorY: 0, anchorW: 40, anchorH: 35 }
  const phone = M.dockRect(Object.assign({ display: [1080, 2316] }, top))
  assert.deepEqual([phone.w, phone.h, phone.y], [470, 1008, 40], "a phone meets the height, under the bar")
  assert.equal(phone.x, 2220 - 235, "centred on the chip, as Omarchy's cards are")
  const tablet = M.dockRect(Object.assign({ display: [2560, 1600] }, top))
  assert.deepEqual([tablet.w, tablet.h], [1152, 720], "a tablet in landscape meets the width")
  assert.equal(tablet.x, 2560 - 1152 - 5, "kept on the screen")
  const fold = M.dockRect(Object.assign({ display: [2176, 1812] }, top))
  assert.ok(Math.abs(fold.w / fold.h - 2176 / 1812) < 0.01, "an open foldable keeps its shape")
  const unknown = M.dockRect(Object.assign({ display: null }, top))
  assert.equal(unknown.h, 1008, "unknown: a phone's shape")
  const low = M.dockRect(Object.assign({ display: [1080, 2316] }, top, { barPos: "bottom" }))
  assert.equal(low.y, 1440 - 35 - 1008 - 5)
})

test("screen and apps: a row on the device's page, and a Screen shortcut", () => {
  const rows = M.settingsPageRows({ scope: "root", single: true, devices: [], identity: { nickname: "", icon: "", glyph: "" } })
  assert.ok(rows.some(r => r.kind === "screen"), "the one-device page")
  assert.ok(!M.settingsPageRows({ scope: "defaults", single: false, devices: [] }).some(r => r.kind === "screen"), "not the defaults: it is a device's")
  assert.equal(M.shortcutByKey("screen").needs, "", "scrcpy, not KDE Connect: shown whatever the device offers")
})

test("screen tips: one each opening, all of them in turn", () => {
  const seen = new Set()
  for (let n = 0; n < M.SCREEN_TIPS.length; n++) seen.add(M.screenTip(1000 + n))
  assert.equal(seen.size, M.SCREEN_TIPS.length)
  assert.equal(M.screenTip(-1), M.SCREEN_TIPS[M.SCREEN_TIPS.length - 1])
  assert.ok(M.SCREEN_TIPS.every(t => t.length <= 60), "short enough for the card")
})

test("screen tips: up long enough to be read, never long", () => {
  assert.equal(M.tipReadMs(""), 1000)
  assert.equal(M.tipReadMs("Right-click is Back, middle-click is Home"), 1000 + 20 * 41)
  assert.ok(M.SCREEN_TIPS.every(t => M.tipReadMs(t) <= 2200))
  assert.equal(M.tipReadMs("x".repeat(500)), 2200)
})
