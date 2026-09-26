.pragma library

// Pure functions from a kdeconnect-bridge snapshot to what the bar and panel draw.
// No QML here, so `node` can check them (see README).

var GLYPH = {
  phone: "\u{F011C}",        // cellphone
  devices: "\u{F0FB0}",      // devices: nothing paired, or a type we do not know
  ring: "\u{F0815}",         // cellphone-wireless
  sendFile: "\u{F0A4D}",     // file-upload
  clipboard: "\u{F0192}",    // content-paste
  messages: "\u{F0369}",     // message-text
  settings: "\u{F0493}",     // cog
  bolt: "\u{F140B}",         // lightning-bolt
  bell: "\u{F009A}",
  bellOff: "\u{F009B}",
  music: "\u{F075A}",
  play: "\u{F040A}",
  pause: "\u{F03E4}",
  next: "\u{F04AD}",
  previous: "\u{F04AE}",
  reply: "\u{F17AD}",        // arrow-u-left-top
  send: "\u{F048A}",
  close: "\u{F0156}",
  back: "\u{F004D}",         // arrow-left
  wave: "\u{F1821}",         // hand-wave
  playPause: "\u{F040E}",
  phoneCog: "\u{F0951}",     // cellphone-cog
  up: "\u{F0143}",           // chevron-up
  down: "\u{F0140}",         // chevron-down
  checked: "\u{F0132}",      // checkbox-marked
  unchecked: "\u{F0131}",    // checkbox-blank-outline
  reset: "\u{F099B}",        // restore
  group: "\u{F0849}",        // account-group
  newMessage: "\u{F0653}",   // message-plus
  picture: "\u{F0976}",      // image
  video: "\u{F0567}",        // video
  file: "\u{F021F}",         // file-image
  left: "\u{F0141}",         // chevron-left
  right: "\u{F0142}",        // chevron-right
  check: "\u{F012C}",
  alert: "\u{F0026}",
  chevronRight: "\u{F0142}",
  chevronDown: "\u{F0140}",
  volume: "\u{F057E}",       // volume-high
  volumeOff: "\u{F0581}"     // volume-off
}

// One pace for every motion in the plugin: things leave quickly and arrive
// over a shared, slightly longer beat, all on the same curve (OutCubic in
// QML). Page changes, the media carousel, its dots and height, and the
// conversation reveal all use these, so nothing moves on its own clock.
var MOTION = { outMs: 90, inMs: 220 }

// A device's glyph and the word for it, from KDE Connect's device type.
var DEVICE_KINDS = {
  phone: { glyph: 0xF011C, noun: "phone" },
  tablet: { glyph: 0xF04F6, noun: "tablet" },
  laptop: { glyph: 0xF0322, noun: "laptop" },
  desktop: { glyph: 0xF0AAB, noun: "computer" },
  tv: { glyph: 0xF0502, noun: "TV" }
}

function deviceGlyph(device) {
  var kind = device ? DEVICE_KINDS[String(device.type || "")] : null
  return kind ? String.fromCodePoint(kind.glyph) : GLYPH.devices
}

function deviceNoun(device) {
  var kind = device ? DEVICE_KINDS[String(device.type || "")] : null
  return kind ? kind.noun : "device"
}

// What to call the device in a sentence: its name, else "the device".
function deviceLabel(device) {
  return device && device.name ? String(device.name) : "the device"
}

// Every shortcut the bar row can hold. `needs` names the device capability
// (snapshot `can`) it depends on; "" means it works without the phone.
var SHORTCUTS = [
  { key: "ring", glyph: GLYPH.ring, label: "Ring", hint: "Ring it, even on silent", needs: "ring" },
  { key: "share", glyph: GLYPH.sendFile, label: "Send files", hint: "Pick files to send to it", needs: "share" },
  { key: "clipboard", glyph: GLYPH.clipboard, label: "Clipboard", hint: "Send your clipboard to it", needs: "clipboard" },
  { key: "messages", glyph: GLYPH.messages, label: "Messages", hint: "Open text messages", needs: "sms" },
  { key: "ping", glyph: GLYPH.wave, label: "Ping", hint: "Pop a notification up on it", needs: "ping" },
  { key: "playPause", glyph: GLYPH.playPause, label: "Play/Pause", hint: "Play or pause what it is playing", needs: "media" },
  { key: "kdeconnect", glyph: GLYPH.phoneCog, label: "KDE Connect", hint: "Open the KDE Connect app", needs: "" }
]

var DEFAULT_SHORTCUTS = ["ring", "share", "clipboard", "messages"]

// The three sections below the header that the Layout settings switch.
var LAYOUT = [
  { key: "showShortcuts", label: "Shortcuts", hint: "The row of quick action buttons" },
  { key: "showMedia", label: "Now playing", hint: "What the device is playing, while something plays" },
  { key: "showNotifications", label: "Notifications", hint: "The device's notifications, with reply and dismiss" }
]

function shortcutByKey(key) {
  for (var i = 0; i < SHORTCUTS.length; i++) if (SHORTCUTS[i].key === key) return SHORTCUTS[i]
  return null
}

// The stored order, cleaned: known keys only, each once. Anything that is not
// a list (missing, or hand-edited into a string) means the default. An empty
// list is a real choice: no shortcuts.
function normalizeShortcuts(value) {
  if (typeof value === "string") {
    try { value = JSON.parse(value) } catch (e) { value = null }
  }
  if (!value || typeof value === "string" || typeof value.length !== "number") return DEFAULT_SHORTCUTS.slice()
  var out = []
  for (var i = 0; i < value.length; i++) {
    var key = String(value[i])
    if (shortcutByKey(key) && out.indexOf(key) < 0) out.push(key)
  }
  return out
}

// Layout flags are on unless stored as false.
function layoutFlag(value) {
  return value !== false && value !== "false"
}

// The tiles to draw, in order, each marked usable or not for this phone.
function shortcutTiles(order, can) {
  var caps = can || {}
  var out = []
  for (var i = 0; i < order.length; i++) {
    var s = shortcutByKey(order[i])
    if (!s) continue
    out.push({ key: s.key, glyph: s.glyph, label: s.label, hint: s.hint,
               enabled: s.needs === "" || caps[s.needs] === true })
  }
  return out
}

function toggleShortcut(order, key) {
  var next = order.slice()
  var at = next.indexOf(key)
  if (at >= 0) next.splice(at, 1)
  else if (shortcutByKey(key)) next.push(key)
  return next
}

function moveShortcut(order, key, delta) {
  var next = order.slice()
  var at = next.indexOf(key)
  var to = at + delta
  if (at < 0 || to < 0 || to >= next.length) return next
  next.splice(at, 1)
  next.splice(to, 0, key)
  return next
}

// The settings page as one flat list, so keyboard and mouse share a cursor:
// the layout switches, then the shortcuts (chosen ones in their order, then
// the rest), then reset and the KDE Connect link.
function settingsRows(flags, order, can) {
  var rows = []
  for (var i = 0; i < LAYOUT.length; i++)
    rows.push({ kind: "layout", key: LAYOUT[i].key, label: LAYOUT[i].label, hint: LAYOUT[i].hint, on: layoutFlag(flags[LAYOUT[i].key]) })
  var rest = []
  for (var j = 0; j < SHORTCUTS.length; j++) if (order.indexOf(SHORTCUTS[j].key) < 0) rest.push(SHORTCUTS[j].key)
  var keys = order.concat(rest)
  for (var k = 0; k < keys.length; k++) {
    var s = shortcutByKey(keys[k])
    var pos = order.indexOf(s.key)
    rows.push({ kind: "shortcut", key: s.key, label: s.label, hint: s.hint, glyph: s.glyph, on: pos >= 0,
                first: pos === 0, last: pos === order.length - 1,
                available: !can || s.needs === "" || can[s.needs] === true })
  }
  rows.push({ kind: "reset", key: "reset", label: "Reset shortcuts" })
  rows.push({ kind: "kdeconnect", key: "kdeconnect", label: "KDE Connect settings" })
  return rows
}

// The device the plugin follows: the configured one when it is paired, else
// the first paired phone that is reachable, else the first paired one at all
// (so an away phone still shows, dimmed, rather than vanishing).
function pickDevice(snapshot, preferredId) {
  var list = snapshot && snapshot.devices ? snapshot.devices : []
  var paired = []
  for (var i = 0; i < list.length; i++) if (list[i] && list[i].paired) paired.push(list[i])
  if (preferredId) {
    for (var j = 0; j < paired.length; j++) if (paired[j].id === preferredId) return paired[j]
  }
  for (var k = 0; k < paired.length; k++) if (paired[k].reachable) return paired[k]
  return paired.length > 0 ? paired[0] : null
}

function batteryCharge(device) {
  if (!device || !device.reachable || !device.battery) return -1
  var c = Number(device.battery.charge)
  return isFinite(c) && c >= 0 ? Math.min(100, Math.round(c)) : -1
}

function charging(device) {
  return !!(device && device.reachable && device.battery && device.battery.charging)
}

function lowBattery(device, threshold) {
  var c = batteryCharge(device)
  return c >= 0 && c <= threshold && !charging(device)
}

// "󰄜 55%", "󰄜 63%󱐋" while charging, bare "󰄜" when away or unknown. The
// glyph follows the device type: a tablet shows a tablet.
function barText(device, showPercent) {
  var text = deviceGlyph(device)
  var c = batteryCharge(device)
  if (showPercent && c >= 0) text += " " + c + "%"
  if (charging(device)) text += GLYPH.bolt
  return text
}

function statusWord(snapshot, device) {
  if (!snapshot) return "Starting"
  if (!snapshot.daemon) return "KDE Connect is not running"
  if (!device) return "No paired device"
  if (!device.reachable) return "Away"
  return "Connected"
}

// A battery glyph sized like the text around it, filled to the nearest 10%,
// with the charging bolt when charging and the alert mark when low. Codes are
// Material Design Icons as the Nerd Font carries them (checked by rendering).
var BATTERY_GLYPHS = [0xF007A, 0xF007A, 0xF007B, 0xF007C, 0xF007D, 0xF007E, 0xF007F, 0xF0080, 0xF0081, 0xF0082, 0xF0079]
var CHARGING_GLYPHS = [0xF089F, 0xF089C, 0xF0086, 0xF0087, 0xF0088, 0xF089D, 0xF0089, 0xF089E, 0xF008A, 0xF008B, 0xF0085]

function batteryGlyph(device, lowPercent) {
  var c = batteryCharge(device)
  if (c < 0) return ""
  var step = Math.max(0, Math.min(10, Math.round(c / 10)))
  if (charging(device)) return String.fromCodePoint(CHARGING_GLYPHS[step])
  if (lowBattery(device, lowPercent === undefined ? 15 : lowPercent)) return String.fromCodePoint(0xF0083)
  return String.fromCodePoint(BATTERY_GLYPHS[step])
}

// Hero meta line: "󰁹 91% · WI-FI · LTE". The battery leads, as a glyph the
// size of the text, since the bolt in it says charging. With no charge known
// it says "CONNECTED". Away or down, just the status.
function metaLine(snapshot, device, lowPercent) {
  if (!device || !device.reachable) return statusWord(snapshot, device)
  var parts = []
  var c = batteryCharge(device)
  parts.push(c >= 0 ? batteryGlyph(device, lowPercent) + " " + c + "%" : "Connected")
  if (device.links && device.links.length) parts.push(device.links[0] === "LAN" ? "Wi-Fi" : device.links[0])
  var net = device.network ? String(device.network.type || "").trim() : ""
  // Android says "Unknown" when it has no cellular type; that is not news.
  if (net && !/^unknown$/i.test(net)) parts.push(net)
  return parts.join(" · ")
}

function batteryText(device) {
  var c = batteryCharge(device)
  return c >= 0 ? c + "%" : ""
}

// `nowPlaying` is the playing phone player's line (Service.nowPlaying), since
// media comes from MPRIS in the shell rather than from the snapshot.
function tooltip(snapshot, device, nowPlaying) {
  if (!device) return statusWord(snapshot, device)
  var lines = [device.name + " — " + statusWord(snapshot, device)]
  var c = batteryCharge(device)
  if (c >= 0) lines.push("Battery " + c + "%" + (charging(device) ? ", charging" : ""))
  var n = device.notifications ? device.notifications.length : 0
  if (n > 0) lines.push(n + (n === 1 ? " notification" : " notifications"))
  if (nowPlaying) lines.push("Playing " + nowPlaying)
  return lines.join("\n")
}

// ---- Phone media, from the MPRIS players KDE Connect exports ----

// KDE Connect names each exported player "<App> - <Device>". The app half is
// what the card shows; the device half says which phone it belongs to.
function playerApp(identity, deviceName) {
  var id = String(identity || "")
  var suffix = " - " + String(deviceName || "")
  if (deviceName && id.length > suffix.length && id.slice(-suffix.length) === suffix) return id.slice(0, -suffix.length)
  var dash = id.lastIndexOf(" - ")
  return dash > 0 ? id.slice(0, dash) : id
}

// A player belongs to this phone when KDE Connect exported it and its
// identity ends with the phone's name. With no name to match, any KDE Connect
// player counts.
function isPhonePlayer(dbusName, identity, deviceName) {
  if (String(dbusName || "").indexOf("kdeconnect") < 0) return false
  if (!deviceName) return true
  var id = String(identity || "")
  var suffix = " - " + deviceName
  return id.length >= suffix.length && id.slice(-suffix.length) === suffix
}

function trackLine(title, artist) {
  var t = String(title || "").trim()
  var a = String(artist || "").trim()
  if (t && a && t !== a) return t + " · " + a
  return t || a
}

// 75 -> "1:15", 3725 -> "1:02:05".
function formatTime(seconds) {
  var s = Math.max(0, Math.floor(Number(seconds) || 0))
  var h = Math.floor(s / 3600)
  var m = Math.floor((s % 3600) / 60)
  var r = s % 60
  var ss = (r < 10 ? "0" : "") + r
  if (h > 0) return h + ":" + (m < 10 ? "0" : "") + m + ":" + ss
  return m + ":" + ss
}

// Notification body without repeating the title: some apps put the same text
// in both, and the ticker is "App: title: text", which would say it twice.
function notificationBody(n) {
  if (!n) return ""
  var title = String(n.title || "").trim()
  var text = String(n.text || "").trim()
  if (text && text !== title) return text
  if (!title && n.ticker) return String(n.ticker).trim()
  return ""
}

function notificationTitle(n) {
  if (!n) return ""
  return String(n.title || n.app || "Notification").trim()
}

// A snapshot for looking at the panel without waiting for real traffic: the
// live device (or a stand-in) with three notifications covering reply,
// dismiss, actions and a long body. Used by the `demo` IPC. Media is not
// faked: it comes from the phone's real MPRIS players.
// kind "away", "down" (daemon not running) and "none" (nothing paired) show
// the other states the panel has to draw.
function demoSnapshot(live, kind) {
  if (kind === "down") return { daemon: false, demo: true, devices: [] }
  if (kind === "devices") {
    var withOthers = demoSnapshot(live, "")
    withOthers.devices.push(
      { id: "demo-tab", name: "Galaxy Tab", type: "tablet", paired: true, reachable: false, links: [], can: {}, notifications: [] },
      { id: "demo-laptop", name: "Work laptop", type: "laptop", paired: false, reachable: true, links: ["LAN"], can: {}, notifications: [] },
      { id: "demo-new", name: "Pixel Tablet", type: "tablet", paired: false, reachable: true, pairRequestedByPeer: true, verificationKey: "4E5A 3506", links: ["LAN"], can: {}, notifications: [] })
    return withOthers
  }
  if (kind === "none") return { daemon: true, demo: true, devices: [] }
  var base = pickDevice(live, "")
  var dev = JSON.parse(JSON.stringify(base || {
    id: "demo", name: "Pixel 8", type: "phone", paired: true, reachable: true, links: ["LAN"],
    can: { ring: true, clipboard: true, share: true, sms: true, media: true, notifications: true },
    battery: { charge: 55, charging: false }
  }))
  // A neutral name, so a screenshot of demo mode shows no real device.
  dev.name = "Pixel 8"
  dev.reachable = kind !== "away"
  dev.network = { type: "5G", strength: 3 }
  dev.notifications = [
    { id: "demo-1", key: "k1", app: "WhatsApp", title: "Alex", text: "Are you still coming on Sunday? We are starting around six, bring the board game if you can find it.", ticker: "", dismissable: true, replyId: "r1", actions: ["Mark as read"], icon: "", silent: false },
    { id: "demo-2", key: "k2", app: "Gmail", title: "Your invoice from Acme", text: "Invoice #4821 is ready to view.", ticker: "", dismissable: true, replyId: "", actions: ["Archive", "Reply"], icon: "", silent: false },
    { id: "demo-3", key: "k3", app: "Calendar", title: "Team sync at 14:00", text: "Starts in 15 minutes", ticker: "", dismissable: false, replyId: "", actions: [], icon: "", silent: false }
  ]
  return { daemon: true, demo: true, devices: [dev] }
}

// Hide what only adds noise: silent entries with no text ("USB debugging
// connected" and the like) say nothing.
//
// `media` is [{app, title}] for the phone's players: an app's media-session
// notification ("YouTube: <the video title>") repeats the media card, and the
// phone itself keeps it in its media area rather than the notification list.
function visibleNotifications(device, media) {
  var list = device && device.notifications ? device.notifications : []
  var players = media || []
  var out = []
  for (var i = 0; i < list.length; i++) {
    var n = list[i]
    if (!n) continue
    if (n.silent && !String(n.text || "").trim() && !String(n.title || "").trim()) continue
    if (isMediaNotification(n, players)) continue
    out.push(n)
  }
  return out
}

// A playback notification comes from an app that has a media player right
// now, and either names its track or cannot be dismissed (it lives as long as
// the session). Matching the title alone let a stale one through: the
// notification still named the previous episode after the player moved on.
// An ordinary notification from the same app ("new upload") is dismissable,
// so it still shows.
function isMediaNotification(n, players) {
  var app = String(n.app || "").trim().toLowerCase()
  if (!app) return false
  var title = String(n.title || "").trim()
  for (var i = 0; i < players.length; i++) {
    var p = players[i]
    if (String(p.app || "").trim().toLowerCase() !== app) continue
    if (title !== "" && String(p.title || "").trim() === title) return true
    if (n.dismissable === false) return true
  }
  return false
}

// ---- Text messages ----

// "+15145550123" -> "+1 514-555-0123"; short codes and anything unusual stay
// as they are.
function formatNumber(address) {
  var a = String(address || "").trim()
  var d = a.replace(/[^\d+]/g, "")
  var m = /^\+?1?(\d{3})(\d{3})(\d{4})$/.exec(d)
  if (m && (d.length === 10 || d.indexOf("1") === (d[0] === "+" ? 1 : 0))) return "+1 " + m[1] + "-" + m[2] + "-" + m[3]
  return a
}

// A thread's title: contact names where known, else formatted numbers; a
// group lists up to three and counts the rest.
function threadTitle(names, addresses) {
  var parts = []
  var list = addresses || []
  for (var i = 0; i < list.length; i++) {
    var n = names && names[i] ? String(names[i]) : ""
    parts.push(n || formatNumber(list[i]))
  }
  if (parts.length === 0) return "Unknown"
  if (parts.length > 3) return parts.slice(0, 3).join(", ") + " +" + (parts.length - 3)
  return parts.join(", ")
}

// The letter in a thread's avatar: a name's first letter, "#" for numbers.
function avatarInitial(title) {
  var t = String(title || "").trim()
  var c = t.charAt(0)
  return /[A-Za-zÀ-ÿ]/.test(c) ? c.toUpperCase() : "#"
}

function pad2(n) { return (n < 10 ? "0" : "") + n }
var DAYS = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]
var MONTHS = ["January", "February", "March", "April", "May", "June", "July", "August", "September", "October", "November", "December"]

function clockTime(ms) {
  var d = new Date(ms)
  return pad2(d.getHours()) + ":" + pad2(d.getMinutes())
}

function startOfDay(d) { return new Date(d.getFullYear(), d.getMonth(), d.getDate()).getTime() }

// Thread list stamp: "14:05" today, "Yesterday", "Mon" this week,
// "Sep 3" this year, "2024-05-02" before.
function threadTime(ms, nowMs) {
  var d = new Date(ms)
  var now = new Date(nowMs === undefined ? Date.now() : nowMs)
  var days = Math.round((startOfDay(now) - startOfDay(d)) / 86400000)
  if (days <= 0) return clockTime(ms)
  if (days === 1) return "Yesterday"
  if (days < 7) return DAYS[d.getDay()].slice(0, 3)
  if (d.getFullYear() === now.getFullYear()) return MONTHS[d.getMonth()].slice(0, 3) + " " + d.getDate()
  return d.getFullYear() + "-" + pad2(d.getMonth() + 1) + "-" + pad2(d.getDate())
}

// Day header in a conversation: "Today", "Yesterday", "Monday, September 22",
// "September 3, 2024".
function dayLabel(ms, nowMs) {
  var d = new Date(ms)
  var now = new Date(nowMs === undefined ? Date.now() : nowMs)
  var days = Math.round((startOfDay(now) - startOfDay(d)) / 86400000)
  if (days <= 0) return "Today"
  if (days === 1) return "Yesterday"
  if (d.getFullYear() === now.getFullYear()) return DAYS[d.getDay()] + ", " + MONTHS[d.getMonth()] + " " + d.getDate()
  return MONTHS[d.getMonth()] + " " + d.getDate() + ", " + d.getFullYear()
}

function sameDay(a, b) { return startOfDay(new Date(a)) === startOfDay(new Date(b)) }

// Phone apps whose notifications are text messages, so the panel can open
// the thread instead of just showing the notification.
function isMessagingApp(app) {
  return /^(messages|google messages|samsung messages|message\+|textra|pulse sms|signal)$/i.test(String(app || "").trim())
}

// The thread a message notification belongs to: its title is the sender's
// name or number. Returns the thread id, or -1.
function threadForNotification(n, threads) {
  if (!n || !isMessagingApp(n.app)) return -1
  var title = String(n.title || "").trim()
  if (!title) return -1
  var digits = title.replace(/\D/g, "")
  var key = digits.length >= 10 ? digits.slice(-10) : digits
  for (var i = 0; i < threads.length; i++) {
    var t = threads[i]
    if (t.title === title) return t.tid
    if (key.length >= 5 && String(t.addressKeys || "").indexOf(key) >= 0) return t.tid
  }
  return -1
}


// ---- Devices ----

// Every device KDE Connect knows, as rows for the Devices section: what it
// is, where it stands, and what can be done with it. Anything that needs a
// decision (a device asking to pair) comes first, then the one followed,
// then the rest by how usable they are.
function deviceRows(snapshot, currentId) {
  var list = snapshot && snapshot.devices ? snapshot.devices : []
  var rows = []
  for (var i = 0; i < list.length; i++) {
    var d = list[i]
    if (!d) continue
    var incoming = d.pairRequestedByPeer === true
    var outgoing = d.pairRequested === true && !d.paired
    var status
    if (incoming) status = "Wants to pair"
    else if (outgoing) status = "Waiting for it to accept"
    else if (!d.paired) status = "Available to pair"
    else if (d.reachable) status = "Connected" + (d.links && d.links.length ? " · " + (d.links[0] === "LAN" ? "Wi-Fi" : d.links[0]) : "")
    else status = "Away"
    var charge = batteryCharge(d)
    rows.push({
      id: d.id, name: d.name || "Unnamed device", type: d.type || "", glyph: deviceGlyph(d),
      status: status + (charge >= 0 ? " · " + charge + "%" : ""),
      current: !!currentId && d.id === currentId,
      paired: d.paired === true, reachable: d.reachable === true,
      incoming: incoming, outgoing: outgoing, key: d.verificationKey || ""
    })
  }
  function rank(r) {
    if (r.incoming) return 0
    if (r.current) return 1
    if (r.paired && r.reachable) return 2
    if (r.paired) return 3
    if (r.outgoing) return 4
    return 5
  }
  rows.sort(function(a, b) { return rank(a) - rank(b) || a.name.localeCompare(b.name) })
  return rows
}

// The section earns its place only when there is something to choose or
// decide: a second paired device, one to pair with, or a request.
function showDevicesSection(rows) {
  var paired = 0
  for (var i = 0; i < rows.length; i++) {
    if (!rows[i].paired || rows[i].incoming) return true
    paired++
  }
  return paired > 1
}

// ---- Collapsed sections: the one line shown in place of the content ----

function devicesSummary(rows) {
  var n = 0
  for (var i = 0; i < rows.length; i++) if (rows[i].incoming) n++
  if (n > 0) return n === 1 ? rows[0].name + " wants to pair" : n + " devices want to pair"
  for (var j = 0; j < rows.length; j++) if (rows[j].current) return rows[j].name + " · " + rows[j].status
  return rows.length + " devices"
}

function mediaSummary(title, artist, app) {
  var line = trackLine(title, artist)
  return line && app ? line + " · " + app : (line || app || "")
}

function notificationsSummary(list) {
  if (!list || list.length === 0) return "Nothing new"
  var n = list[0]
  var who = notificationTitle(n)
  var body = notificationBody(n)
  return (body ? who + ": " + body : who).replace(/\s+/g, " ")
}

// Which sections are folded, from the widget's settings; a stored non-object
// (hand edits) means none.
function collapsedState(value) {
  return value && typeof value === "object" && !Array.isArray(value) ? value : ({})
}

// ---- Folded settings sections: the one line in place of the content ----

function layoutSummary(flags) {
  var on = []
  for (var i = 0; i < LAYOUT.length; i++) if (layoutFlag(flags[LAYOUT[i].key])) on.push(LAYOUT[i].label)
  if (on.length === LAYOUT.length) return "Everything shown"
  if (on.length === 0) return "Everything hidden"
  return on.join(", ")
}

function shortcutsSummary(order) {
  var labels = []
  for (var i = 0; i < order.length; i++) {
    var s = shortcutByKey(order[i])
    if (s) labels.push(s.label)
  }
  return labels.length ? labels.join(", ") : "None"
}

function setupSummary(checks) {
  var list = checks || []
  if (list.length === 0) return "Checking…"
  var bad = 0
  for (var i = 0; i < list.length; i++) if (!list[i].ok) bad++
  return bad === 0 ? "All good" : (bad === 1 ? "1 thing to fix" : bad + " things to fix")
}
