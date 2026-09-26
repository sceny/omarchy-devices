.pragma library

// Pure functions from a kdeconnect-bridge snapshot to what the bar and panel draw.
// No QML here, so `node` can check them (see README).

var GLYPH = {
  phone: "\u{F011C}",        // cellphone
  devices: "\u{F0FB0}",      // devices: nothing paired, or a type we do not know
  ring: "\u{F0815}",         // cellphone-wireless
  sendFile: "\u{F0A4D}",     // file-upload
  clipboard: "\u{F0192}",    // content-paste
  text: "\u{F060E}",         // form-textbox
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
  wifi: "\u{F05A9}",
  wifiOff: "\u{F05AA}",
  bluetooth: "\u{F00AF}",
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
  { key: "text", glyph: GLYPH.text, label: "Send text", hint: "Type text or a link to send to it", needs: "share" },
  { key: "messages", glyph: GLYPH.messages, label: "Messages", hint: "Open text messages", needs: "sms" },
  { key: "ping", glyph: GLYPH.wave, label: "Ping", hint: "Pop a notification up on it", needs: "ping" },
  { key: "playPause", glyph: GLYPH.playPause, label: "Play/Pause", hint: "Play or pause what it is playing", needs: "media" },
  { key: "kdeconnect", glyph: GLYPH.phoneCog, label: "KDE Connect", hint: "Open the KDE Connect app", needs: "" }
]

var DEFAULT_SHORTCUTS = ["ring", "share", "clipboard", "messages"]

// The send-text composer: a lone web address goes as a link, which opens on
// the device; anything else as text, which KDE Connect puts on the device's
// clipboard. A bare "www." address gets its https:// so the phone can open it.
function linkFor(text) {
  var t = String(text || "").trim()
  if (/^https?:\/\/\S+$/i.test(t)) return t
  if (/^www\.[^\s.]+\.\S+$/i.test(t)) return "https://" + t
  return ""
}

// The line under the composer: what Enter will do with what is typed, and
// Ctrl+Enter when the device takes pings. On Android a link arrives as a
// notification to tap, so "offers to open it", not "opens it".
function composerHint(text, device, canPing) {
  var name = deviceLabel(device)
  var t = String(text || "").trim()
  var line = t === "" ? "Text lands on " + name + "'s clipboard; a link arrives ready to open"
    : linkFor(t) !== "" ? "Enter sends this link; " + name + " offers to open it"
    : "Enter puts this on " + name + "'s clipboard"
  return canPing ? line + " · Ctrl+Enter pings it instead" : line
}

// The sections below the header that the Layout settings switch and order.
// `section` is the section's key on the main page (fold, cursor).
var LAYOUT = [
  { key: "showDevices", section: "devices", label: "Devices", hint: "Switch, pair and unpair devices" },
  { key: "showShortcuts", section: "actions", label: "Shortcuts", hint: "The row of quick action buttons" },
  { key: "showMedia", section: "media", label: "Now playing", hint: "What the device is playing" },
  { key: "showNotifications", section: "notifications", label: "Notifications", hint: "The device's notifications, with reply" }
]

var DEFAULT_SECTIONS = ["devices", "actions", "media", "notifications"]

function layoutBySection(section) {
  for (var i = 0; i < LAYOUT.length; i++) if (LAYOUT[i].section === section) return LAYOUT[i]
  return null
}

// The stored section order, cleaned: known sections once each, and any it
// leaves out put back at their default position (an order saved before
// Devices could move gets Devices first). Every section always has a place;
// whether it shows is its Layout switch.
function normalizeSections(value) {
  if (typeof value === "string") {
    try { value = JSON.parse(value) } catch (e) { value = null }
  }
  var out = []
  if (value && typeof value !== "string" && typeof value.length === "number") {
    for (var i = 0; i < value.length; i++) {
      var key = String(value[i])
      if (DEFAULT_SECTIONS.indexOf(key) >= 0 && out.indexOf(key) < 0) out.push(key)
    }
  }
  for (var j = 0; j < DEFAULT_SECTIONS.length; j++)
    if (out.indexOf(DEFAULT_SECTIONS[j]) < 0) out.splice(Math.min(j, out.length), 0, DEFAULT_SECTIONS[j])
  return out
}

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
// the layout switches in the sections' order, the bar indicators (chosen ones
// in their order, then the rest) and the only-when-low option, the shortcuts
// (the same way), then reset and the KDE Connect link.
function settingsRows(flags, order, can, sections, bar, lowOnly) {
  var rows = []
  var sectionOrder = normalizeSections(sections)
  for (var i = 0; i < sectionOrder.length; i++) {
    var l = layoutBySection(sectionOrder[i])
    rows.push({ kind: "layout", key: l.key, section: l.section, label: l.label, hint: l.hint, on: layoutFlag(flags[l.key]),
                first: i === 0, last: i === sectionOrder.length - 1 })
  }
  var chosen = bar ? normalizeBarIndicators(bar) : DEFAULT_BAR.slice()
  var others = []
  for (var b = 0; b < BAR_INDICATORS.length; b++) if (chosen.indexOf(BAR_INDICATORS[b].key) < 0) others.push(BAR_INDICATORS[b].key)
  var barKeys = chosen.concat(others)
  for (var n = 0; n < barKeys.length; n++) {
    var ind = barIndicatorByKey(barKeys[n])
    var at = chosen.indexOf(ind.key)
    rows.push({ kind: "bar", key: ind.key, label: ind.label, hint: ind.hint, glyph: ind.glyph, on: at >= 0,
                first: at === 0, last: at === chosen.length - 1 })
  }
  // A switch, not a place in the pill: it decides when battery and % show.
  rows.push({ kind: "barFlag", key: "batteryLowOnly", label: "Battery only when low",
              hint: "Off, the battery and % always show", on: lowOnly !== false })
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
// ---- The bar pill: the device glyph, then the indicators chosen, in order ----

// What the pill can show beside the glyph. "bubble" is not text: a count
// drawn on the glyph itself (BarWidget), so it costs no width.
var BAR_INDICATORS = [
  { key: "connection", glyph: GLYPH.wifi, label: "Connection", hint: "Wi-Fi or Bluetooth; crossed out while away" },
  { key: "battery", glyph: "\u{F007E}", label: "Battery", hint: "A glyph that fills with the charge" },
  { key: "percent", glyph: "%", label: "Battery %", hint: "The charge as a number" },
  { key: "notifications", glyph: GLYPH.bell, label: "Notifications", hint: "How many, beside a bell; nothing at 0" },
  { key: "messages", glyph: GLYPH.messages, label: "Unread messages", hint: "How many, beside a bubble; nothing at 0" },
  { key: "playing", glyph: GLYPH.play, label: "Now playing", hint: "A play mark while something plays" },
  { key: "bubble", glyph: "\u{F0CA0}", label: "Notification bubble", hint: "A count on the device glyph; nothing at 0" }
]

function barIndicatorByKey(key) {
  for (var i = 0; i < BAR_INDICATORS.length; i++) if (BAR_INDICATORS[i].key === key) return BAR_INDICATORS[i]
  return null
}

// The owner's default: the battery (only when low: batteryLowOnly, on by
// default) and the notification bubble, so a healthy phone with nothing new
// is the glyph alone.
var DEFAULT_BAR = ["battery", "bubble"]

// The stored choice, cleaned like the shortcuts: known keys once each, and
// an empty list is a real choice (the glyph alone).
function normalizeBarIndicators(value) {
  if (typeof value === "string") {
    try { value = JSON.parse(value) } catch (e) { value = null }
  }
  if (!value || typeof value === "string" || typeof value.length !== "number") return DEFAULT_BAR.slice()
  var out = []
  for (var i = 0; i < value.length; i++) {
    var key = String(value[i])
    if (barIndicatorByKey(key) && out.indexOf(key) < 0) out.push(key)
  }
  return out
}

// The pill's text. `state` carries what is not in the device snapshot:
// { lowPercent, lowOnly (battery and % only when low), notifications,
// messages, playing }. Away, only the glyph and a crossed-out connection: a
// charge or a count from a device that is not there would be stale. The bolt
// follows the percent only when the battery glyph (which has its own) is not
// shown.
function barText(device, indicators, state) {
  var st = state || {}
  var text = deviceGlyph(device)
  var reachable = !!device && device.reachable === true
  var c = batteryCharge(device)
  var low = lowBattery(device, st.lowPercent === undefined ? 15 : st.lowPercent)
  var showBattery = c >= 0 && (!st.lowOnly || low)
  var parts = []
  for (var i = 0; i < indicators.length; i++) {
    var key = indicators[i]
    if (key === "connection") {
      if (!device) continue
      if (!reachable) parts.push(GLYPH.wifiOff)
      else parts.push(device.links && device.links[0] === "Bluetooth" ? GLYPH.bluetooth : GLYPH.wifi)
      continue
    }
    if (!reachable) continue
    if (key === "battery" && showBattery) parts.push(batteryGlyph(device, st.lowPercent))
    else if (key === "percent" && showBattery)
      parts.push(c + "%" + (charging(device) && indicators.indexOf("battery") < 0 ? GLYPH.bolt : ""))
    else if (key === "notifications" && st.notifications > 0) parts.push(GLYPH.bell + " " + st.notifications)
    else if (key === "messages" && st.messages > 0) parts.push(GLYPH.messages + " " + st.messages)
    else if (key === "playing" && st.playing) parts.push(GLYPH.play)
  }
  return parts.length ? text + " " + parts.join(" ") : text
}

// The number on the glyph, or 0 for none.
function barBubble(device, indicators, notifications) {
  if (!device || device.reachable !== true || indicators.indexOf("bubble") < 0) return 0
  return Math.max(0, notifications || 0)
}

function toggleBarIndicator(order, key) {
  var next = order.slice()
  var at = next.indexOf(key)
  if (at >= 0) next.splice(at, 1)
  else if (barIndicatorByKey(key)) next.push(key)
  return next
}

function barSummary(indicators, lowOnly) {
  var labels = []
  for (var i = 0; i < indicators.length; i++) {
    var b = barIndicatorByKey(indicators[i])
    if (b) labels.push(b.label)
  }
  var line = labels.length ? labels.join(", ") : "The glyph alone"
  return lowOnly && (indicators.indexOf("battery") >= 0 || indicators.indexOf("percent") >= 0) ? line + " · battery when low" : line
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

// Cellular signal as a text-sized glyph: KDE Connect reports 0-4 bars, and
// the triangle set has an empty one and one to four (checked by rendering).
// Nothing when the device reports no cellular network or no strength.
var SIGNAL_GLYPHS = [0xF08FE, 0xF08F4, 0xF08F6, 0xF08F8, 0xF08FA]

function signalGlyph(device) {
  var s = device && device.network ? Number(device.network.strength) : -1
  if (!(s >= 0)) return ""
  return String.fromCodePoint(SIGNAL_GLYPHS[Math.min(4, Math.round(s))])
}

// The cellular part of the meta line: "󰣸 LTE", or the bars alone when the
// phone has a signal but no network type to name.
function networkText(device) {
  var net = device && device.network ? String(device.network.type || "").trim() : ""
  // Android says "Unknown" when it has no cellular type; that is not news.
  if (/^unknown$/i.test(net)) net = ""
  return [signalGlyph(device), net].filter(function (p) { return p !== "" }).join(" ")
}

// Hero meta line: "󰁹 91% · WI-FI · 󰣸 LTE". The battery leads, as a glyph the
// size of the text, since the bolt in it says charging. With no charge known
// it says "CONNECTED". Away or down, just the status.
function metaLine(snapshot, device, lowPercent) {
  if (!device || !device.reachable) return statusWord(snapshot, device)
  var parts = []
  var c = batteryCharge(device)
  parts.push(c >= 0 ? batteryGlyph(device, lowPercent) + " " + c + "%" : "Connected")
  if (device.links && device.links.length) parts.push(device.links[0] === "LAN" ? "Wi-Fi" : device.links[0])
  var net = networkText(device)
  if (net) parts.push(net)
  return parts.join(" · ")
}

function batteryText(device) {
  var c = batteryCharge(device)
  return c >= 0 ? c + "%" : ""
}

// `nowPlaying` is the playing phone player's line (Service.nowPlaying), since
// media comes from MPRIS in the shell rather than from the snapshot.
function tooltip(snapshot, device, nowPlaying, unreadMessages) {
  if (!device) return statusWord(snapshot, device)
  var lines = [device.name + " — " + statusWord(snapshot, device)]
  var c = batteryCharge(device)
  if (c >= 0) lines.push("Battery " + c + "%" + (charging(device) ? ", charging" : ""))
  var n = device.notifications ? device.notifications.length : 0
  if (n > 0) lines.push(n + (n === 1 ? " notification" : " notifications"))
  if (unreadMessages > 0) lines.push(unreadMessages + (unreadMessages === 1 ? " unread message" : " unread messages"))
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
    { id: "demo-4", key: "k4", app: "Messages", title: "Alex Rivera", text: "Running ten minutes late, traffic on the bridge is terrible. Start without me if everyone is there, and save me a slice! Also, could you put the folding chairs by the door so I can grab them on the way in?", ticker: "", dismissable: true, replyId: "r4", actions: ["Mark as read", "Reply"], icon: "", silent: false },
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
  return /^(messages|message|sms|mms|google messages|samsung messages|messaging|message\+|textra|pulse sms|chomp sms|qksms|fossify sms messenger|simple sms messenger|signal)$/i.test(String(app || "").trim())
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

// Folded Layout: what shows, in its order; "Everything shown" only when
// that is also the default order, so a new order is never hidden.
function layoutSummary(flags, sections) {
  var sectionOrder = normalizeSections(sections)
  var on = []
  for (var i = 0; i < sectionOrder.length; i++) {
    var l = layoutBySection(sectionOrder[i])
    if (layoutFlag(flags[l.key])) on.push(l.label)
  }
  if (on.length === 0) return "Everything hidden"
  if (on.length === LAYOUT.length && sectionOrder.join() === DEFAULT_SECTIONS.join()) return "Everything shown"
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

// ---- Demo messages: made-up conversations for screenshots and checks ----
// Fictional names and 555 numbers only; demo mode never sends anything. The
// clock is today at 18:40, so a screenshot reads like an evening at any hour.

function demoNow() {
  var d = new Date()
  return new Date(d.getFullYear(), d.getMonth(), d.getDate(), 18, 40).getTime()
}

function demoThreads(nowMs) {
  var now = nowMs === undefined ? demoNow() : nowMs
  var min = 60000, hour = 60 * min, day = 24 * hour
  function t(id, names, addresses, ago, snippet, sent, read, group) {
    return { id: id, names: names, addresses: addresses, date: now - ago, snippet: snippet,
             sent: !!sent, read: read !== false, attachments: 0, group: !!group }
  }
  return [
    t(9001, ["Alex Rivera"], ["+15145550123"], 4 * min, "Perfect, see you at six! Bring the board game 🎲", false, false),
    t(9002, ["Book club", "Priya", "Sam"], ["+15145550140", "+15145550141", "+15145550142"], 50 * min, "Priya: Chapter 7 was wild, no spoilers please", false, false, true),
    t(9003, [""], ["55555"], 2 * hour, "Your verification code is 482 913. It expires in 10 minutes.", false, true),
    t(9004, ["Sam Chen"], ["+15145550142"], 1 * day, "Sounds good, thanks!", true),
    t(9005, ["Dr. Moreau's office"], ["+15145550177"], 3 * day, "Reminder: your appointment is on Tuesday at 9:30.", false, true),
    t(9006, ["Jordan"], ["+15145550188"], 9 * day, "Picture", false, true)
  ]
}

// The conversation shown for thread 9001, oldest first. `picture` is a local
// image for the picture message (MMS); without one it shows as a chip.
function demoConversation(nowMs, picture) {
  var now = nowMs === undefined ? demoNow() : nowMs
  var min = 60000, hour = 60 * min
  function m(uid, ago, body, sent, attachments) {
    return { uid: uid, thread: 9001, body: body, date: now - ago, type: sent ? 2 : 1, sent: !!sent,
             read: true, event: 1, addresses: ["+15145550123"], attachments: attachments || [] }
  }
  return [
    m(1, 26 * hour, "Are you still up for games night this weekend?"),
    m(2, 25 * hour, "Yes! Saturday works best for me", true),
    m(3, 25 * hour - 5 * min, "Great. Mine, around six?"),
    m(4, 20 * min, "Just left work, picking up snacks on the way", true),
    m(41, 16 * min, "Look what just parked outside 😮", false,
      [{ part: 1, mime: "image/jpeg", id: "demo-picture", thumb: picture || "" }]),
    m(5, 12 * min, "Do we have enough chairs? Priya is bringing two friends"),
    m(6, 8 * min, "I'll grab the folding ones from the car", true),
    m(7, 4 * min, "Perfect, see you at six! Bring the board game 🎲")
  ]
}
