.pragma library

// Pure functions from a kdeconnect-bridge snapshot to what the bar and panel draw.
// No QML here, so `node` can check them (see docs/internals/development.md).

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
  refresh: "\u{F0450}",      // refresh: look again (Reconnect)
  group: "\u{F0849}",        // account-group
  newMessage: "\u{F0653}",   // message-plus
  picture: "\u{F0976}",      // image
  video: "\u{F0567}",        // video
  folderOpen: "\u{F0770}",   // folder-open: shown in Files
  googlePlay: "\u{F02BC}",   // google-play: the Android app's store
  apple: "\u{F0035}",        // apple: the iPhone app (the font has no App Store mark)
  file: "\u{F021F}",         // file-image
  document: "\u{F0219}",     // file-document: a received file that is not a picture
  download: "\u{F01DA}",     // download: save a copy of a photo here
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
  volumeOff: "\u{F0581}",    // volume-off
  grip: "\u{F01DD}",         // drag-vertical: drag a row to move it
  edit: "\u{F03EB}",         // pencil: edit the page in place
  add: "\u{F0419}",          // plus-circle-outline: add a shortcut while editing
  remove: "\u{F0376}",       // minus-circle: take one away while editing
  callRing: "\u{F03F6}",     // phone-in-talk: a phone with waves (checked by rendering)
  callMissed: "\u{F03FA}",   // phone-missed
  callBack: "\u{F03F2}",     // phone
  callText: "\u{F0369}",     // message-text
  screen: "\u{F0989}",       // monitor-cellphone: the device's screen in a window here
  apps: "\u{F003B}",         // apps: its apps, each in a window
  optional: "\u{F0766}"      // circle-outline: a check only one feature needs
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
  // scrcpy over adb, not KDE Connect: set up on its own page the first time.
  { key: "screen", glyph: GLYPH.screen, label: "Screen", hint: "Its screen in a window here, with your mouse and keyboard", needs: "" },
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
  { key: "showNotifications", section: "notifications", label: "Notifications", hint: "The device's notifications, with reply" },
  { key: "showReceived", section: "received", label: "Received", hint: "Files it sent you, while there are any" },
  { key: "showPhotos", section: "photos", label: "Gallery", hint: "Its newest photos and videos" }
]

// A section added in a release joins a saved order at its default place
// (normalizeSections), so Received and Photos come last for everyone who had
// an order.
var DEFAULT_SECTIONS = ["devices", "actions", "media", "notifications", "received", "photos"]

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

// The sections the page can show, in order: the Devices section is gone
// from the page (tabs and Settings do its work), so it is never moved past.
function visibleSections(value) {
  return normalizeSections(value).filter(function(k) { return k !== "devices" })
}

// A list with `key` moved to `target`'s place: before it when moving up, after
// it when moving down (a drop on another row). Unknown keys: unchanged.
function moveTo(list, key, target) {
  var from = list.indexOf(key), to = list.indexOf(target)
  if (from < 0 || to < 0 || from === to) return list.slice()
  var next = list.slice()
  next.splice(from, 1)
  next.splice(to, 0, key)
  return next
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
// Each row of an order carries `pos` (its place) and `count` (how many share
// the order), for its arrows and for dragging it.
function settingsRows(flags, order, can, sections, bar, lowOnly, calls) {
  var rows = []
  var sectionOrder = visibleSections(sections)
  for (var i = 0; i < sectionOrder.length; i++) {
    var l = layoutBySection(sectionOrder[i])
    rows.push({ kind: "layout", key: l.key, section: l.section, label: l.label, hint: l.hint, on: layoutFlag(flags[l.key]),
                first: i === 0, last: i === sectionOrder.length - 1, pos: i, count: sectionOrder.length })
  }
  var chosen = bar ? normalizeBarIndicators(bar) : DEFAULT_BAR.slice()
  var others = []
  for (var b = 0; b < BAR_INDICATORS.length; b++) if (chosen.indexOf(BAR_INDICATORS[b].key) < 0) others.push(BAR_INDICATORS[b].key)
  var barKeys = chosen.concat(others)
  for (var n = 0; n < barKeys.length; n++) {
    var ind = barIndicatorByKey(barKeys[n])
    var at = chosen.indexOf(ind.key)
    rows.push({ kind: "bar", key: ind.key, label: ind.label, hint: ind.hint, glyph: ind.glyph, on: at >= 0,
                first: at === 0, last: at === chosen.length - 1, pos: at, count: chosen.length })
  }
  // Switches, not places in the pill: when battery and % show, and whether
  // calls show at all (in the pill and over the panel).
  rows.push({ kind: "barFlag", key: "batteryLowOnly", label: "Battery only when low",
              hint: "Off, the battery and % always show", on: lowOnly !== false })
  rows.push({ kind: "barFlag", key: "showCalls", label: "Calls",
              hint: "Who is calling, and a call missed until you close it", on: calls !== false })
  var rest = []
  for (var j = 0; j < SHORTCUTS.length; j++) if (order.indexOf(SHORTCUTS[j].key) < 0) rest.push(SHORTCUTS[j].key)
  var keys = order.concat(rest)
  for (var k = 0; k < keys.length; k++) {
    var s = shortcutByKey(keys[k])
    var pos = order.indexOf(s.key)
    rows.push({ kind: "shortcut", key: s.key, label: s.label, hint: s.hint, glyph: s.glyph, on: pos >= 0,
                first: pos === 0, last: pos === order.length - 1, pos: pos, count: order.length,
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

// ---- Waiting on the device ----
// A click is done when its effect shows in the snapshot, not when the D-Bus
// call returns: the phone answers a moment later. `kind` says what to look
// for; `before` is the notification as it was at the click (JSON), for the
// kinds that wait for it to change. A device gone from the snapshot ends
// every wait: there is nothing left to answer.
function findNotification(device, id) {
  var list = device && device.notifications ? device.notifications : []
  for (var i = 0; i < list.length; i++) if (list[i] && String(list[i].id) === String(id)) return list[i]
  return null
}

function answered(kind, snapshot, deviceId, noteId, before) {
  var list = snapshot && snapshot.devices ? snapshot.devices : []
  var d = null
  for (var i = 0; i < list.length; i++) if (list[i] && list[i].id === deviceId) d = list[i]
  if (!d) return true
  if (kind === "dismiss") return !findNotification(d, noteId)
  if (kind === "note") {
    var n = findNotification(d, noteId)
    return !n || JSON.stringify(n) !== before
  }
  if (kind === "pair") return d.paired === true || d.pairRequested === true
  if (kind === "accept") return d.paired === true
  if (kind === "reject") return d.pairRequested !== true && d.pairRequestedByPeer !== true
  if (kind === "unpair") return d.paired !== true
  return true
}

// The snapshot with one notification gone: demo mode's stand-in for the
// phone answering a dismiss.
function withoutNotification(snapshot, id) {
  var copy = JSON.parse(JSON.stringify(snapshot || {}))
  var list = copy.devices || []
  for (var i = 0; i < list.length; i++)
    if (list[i] && list[i].notifications)
      list[i].notifications = list[i].notifications.filter(function(n) { return String(n.id) !== String(id) })
  return copy
}

// How long to wait for the answer, and what to say when it never comes.
// A notification action or a reply may leave the notification as it was,
// and a skip may land on a track with the same title, so those end quietly; the rest report that the device did not answer.
// KDE Connect cancels a pairing the other side has not accepted in this
// long, on both sides: a constant compiled into it, not a setting and not on
// D-Bus (kdeconnect-kde core/backends/pairinghandler.h, pairingTimeoutMsec =
// 30 * 1000, at 97d6289). Change it here if KDE Connect ever changes it.
var PAIR_TIMEOUT_S = 30

// Seconds left for a pairing asked at `sinceMs`, never below 0.
function pairSecondsLeft(sinceMs, nowMs) {
  return Math.max(0, Math.min(PAIR_TIMEOUT_S, PAIR_TIMEOUT_S - Math.floor((nowMs - sinceMs) / 1000)))
}

// Actions whose result shows where they were clicked, with no toast: a
// pairing card appears (Pair), becomes the device (Accept), goes (Reject,
// Cancel). A failure still says so.
var SHOWN_IN_PLACE = ["pair", "accept", "reject"]
function shownInPlace(kind) { return SHOWN_IN_PLACE.indexOf(String(kind)) >= 0 }

function waitLimit(kind, deviceName) {
  var name = String(deviceName || "The device")
  if (kind === "note") return { ms: 4000, fail: "" }
  if (kind === "track") return { ms: 3000, fail: "" }
  if (kind === "dismiss") return { ms: 10000, fail: name + " did not dismiss it" }
  return { ms: 15000, fail: name + " did not answer" }
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
  { key: "connection", tile: "Link", sample: GLYPH.wifi, glyph: GLYPH.wifi, label: "Connection", hint: "Wi-Fi or Bluetooth; crossed out while away" },
  { key: "battery", tile: "Battery", sample: "\u{F007E}", glyph: "\u{F007E}", label: "Battery", hint: "A glyph that fills with the charge" },
  { key: "percent", tile: "Percent", sample: "80%", glyph: "%", label: "Battery %", hint: "The charge as a number" },
  { key: "notifications", tile: "Alerts", sample: GLYPH.bell + " 3", glyph: GLYPH.bell, label: "Notifications", hint: "How many, beside a bell; nothing at 0" },
  { key: "messages", tile: "Texts", sample: GLYPH.messages + " 2", glyph: GLYPH.messages, label: "Unread messages", hint: "How many, beside a bubble; nothing at 0" },
  { key: "playing", tile: "Playing", sample: GLYPH.play, glyph: GLYPH.play, label: "Now playing", hint: "A play mark while something plays" },
  { key: "bubble", tile: "Bubble", sample: "3", glyph: "\u{F0CA0}", label: "Notification bubble", hint: "A count on the device glyph; nothing at 0" }
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
  return barParts(device, indicators, state).map(function(p) { return p.text }).join(" ")
}

// The pill's text in parts, each drawn on its own so that only what is
// urgent turns red: a low battery's glyph and percent, not the whole chip.
// [{ text, urgent }], the device's glyph first.
// Every part a chip can have, by key: a part keeps its key as the order
// changes, so the bar slides it to its new place instead of redrawing.
var BAR_PART_KEYS = ["glyph", "call", "connection", "battery", "percent", "notifications", "messages", "playing"]

function barParts(device, indicators, state) {
  var st = state || {}
  // `glyph`: the device's own icon when its user picked one (deviceIcon).
  var parts = [{ key: "glyph", text: st.glyph || deviceGlyph(device), urgent: false }]
  var reachable = !!device && device.reachable === true
  var c = batteryCharge(device)
  var low = lowBattery(device, st.lowPercent === undefined ? 15 : st.lowPercent)
  var showBattery = c >= 0 && (!st.lowOnly || low)
  function add(key, text, urgent) { parts.push({ key: key, text: text, urgent: !!urgent }) }
  // A call is news, not an indicator: it leads whatever else is chosen.
  if (st.call && reachable) parts.push({ key: "call", text: st.call.state === "ringing" ? GLYPH.callRing : GLYPH.callMissed, urgent: false, call: st.call.state })
  for (var i = 0; i < indicators.length; i++) {
    var key = indicators[i]
    if (key === "connection") {
      if (!device) continue
      if (!reachable) add(key, GLYPH.wifiOff)
      else add(key, device.links && device.links[0] === "Bluetooth" ? GLYPH.bluetooth : GLYPH.wifi)
      continue
    }
    if (!reachable) continue
    if (key === "battery" && showBattery) { add(key, batteryGlyph(device, st.lowPercent), low); parts[parts.length - 1].battery = true }
    else if (key === "percent" && showBattery) {
      var pct = c + "%" + (charging(device) && indicators.indexOf("battery") < 0 ? GLYPH.bolt : "")
      // Right after the battery glyph, the % is part of it: one piece, a
      // thin space apart, not an indicator of its own. `glyph` and `suffix`
      // draw it: a glyph's ink can run past its advance (the charging bolt),
      // so the bar spaces the % from the ink, not from a character.
      var prev = parts[parts.length - 1]
      if (prev.battery) { prev.glyph = prev.text; prev.suffix = pct; prev.text += "\u2009" + pct }
      else add(key, pct, low)
    }
    else if (key === "notifications" && st.notifications > 0) add(key, GLYPH.bell + " " + st.notifications)
    else if (key === "messages" && st.messages > 0) add(key, GLYPH.messages + " " + st.messages)
    else if (key === "playing" && st.playing) add(key, GLYPH.play)
  }
  return parts
}

// The number on the glyph, or 0 for none.
function barBubble(device, indicators, notifications) {
  if (!device || device.reachable !== true || indicators.indexOf("bubble") < 0) return 0
  return Math.max(0, notifications || 0)
}

// Ticking an indicator puts it at its natural place among the chosen ones
// (the catalogue's order: connection, battery, %, counts, playing, bubble),
// so % lands right after the battery. The order the user dragged is kept.
function toggleBarIndicator(order, key) {
  var next = order.slice()
  var at = next.indexOf(key)
  if (at >= 0) { next.splice(at, 1); return next }
  if (!barIndicatorByKey(key)) return next
  var rank = function(k) { for (var i = 0; i < BAR_INDICATORS.length; i++) if (BAR_INDICATORS[i].key === k) return i; return 99 }
  var place = next.length
  for (var j = next.length - 1; j >= 0; j--) {
    if (rank(next[j]) < rank(key)) { place = j + 1; break }
    place = j
  }
  next.splice(place, 0, key)
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

// ---- Calls, from KDE Connect's telephony plugin ----
// The bridge keeps the device's last call event: { event: "ringing" |
// "missed", number, name, at (ms) }. KDE Connect says when a call rings and
// when one is missed (a declined call counts as missed), never when it is
// answered or ends (#60, #61). So a ringing call counts as ringing for
// RING_MS at most, which is about as long as a phone rings before voicemail
// takes it. A missed call shows until the user closes it (`closedAt`: the
// `at` of the last call closed), for MISSED_MS at most.
var RING_MS = 45000
var MISSED_MS = 30 * 60000

// A ringing phone's beat, on the plugin's pace, like a ringtone: two rings,
// a short gap between them, then a rest. In one ring the three sound waves
// light from the inside out, one every MOTION.outMs, then fade together over
// MOTION.inMs, while the handset rocks. The pill glows for each ring
// (ringPhases), so the bar and the card ring together.
var RING_BEAT = { angle: 10, waveMs: MOTION.outMs, fadeMs: MOTION.inMs, rings: 2, gapMs: 160, restMs: 1000, restWave: 0.3 }

function ringMs() { return 3 * RING_BEAT.waveMs + RING_BEAT.fadeMs }

// The beat as lit and dark spans, for the pill: [{ lit, ms }], looping.
function ringPhases() {
  var out = []
  for (var i = 0; i < RING_BEAT.rings; i++) {
    out.push({ lit: true, ms: ringMs() })
    out.push({ lit: false, ms: i < RING_BEAT.rings - 1 ? RING_BEAT.gapMs : RING_BEAT.restMs })
  }
  return out
}

function callState(device, nowMs, closedAt) {
  var c = device && device.reachable === true ? device.call : null
  if (!c || (c.event !== "ringing" && c.event !== "missed")) return null
  var at = Number(c.at) || 0
  if (closedAt && at <= closedAt) return null
  var age = nowMs - at
  var hold = c.hold === true
  // A demo call (`hold`) rings until closed, so the ring can be watched.
  if (c.event === "ringing" && age > RING_MS && !hold) return null
  if (c.event === "missed" && age > MISSED_MS) return null
  var number = String(c.number || "").trim()
  var name = String(c.name || "").trim()
  return {
    state: c.event, at: at, number: number, hold: hold, device: device ? String(device.id) : "",
    who: name || (number ? formatNumber(number) : "Unknown number"),
    // The number under the name, when there is a name to put it under.
    detail: name && number ? formatNumber(number) : ""
  }
}

// The call the card shows, from every device's (`calls`, by id; `order`,
// the devices' ids in order): a ringing one first, else the latest missed.
function shownCall(calls, order) {
  var best = null
  for (var i = 0; i < order.length; i++) {
    var c = calls[order[i]]
    if (!c) continue
    if (c.state === "ringing") return c
    if (!best || c.at > best.at) best = c
  }
  return best
}

// The card's small caps line: "INCOMING CALL", "MISSED CALL · 14:05".
function callHeading(call) {
  if (!call) return ""
  return call.state === "ringing" ? "INCOMING CALL" : "MISSED CALL · " + clockTime(call.at)
}

// How long until the call's state can change on its own (ringing runs out,
// missed expires), for the timer that re-reads it; -1 when nothing will.
function callExpiresIn(call, nowMs) {
  if (!call || (call.hold && call.state === "ringing")) return -1
  return Math.max(0, call.at + (call.state === "ringing" ? RING_MS : MISSED_MS) - nowMs)
}

// A made-up call for demo mode: a fictional name and a 555 number. It rings
// until closed (`hold`), so the ring can be watched at its own speed.
function demoCall(kind, nowMs) {
  if (kind !== "ringing" && kind !== "missed") return null
  return { event: kind, number: "+15145550123", name: "Alex Rivera", at: nowMs - (kind === "missed" ? 4 * 60000 : 0), hold: true }
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
// media comes from MPRIS in the shell rather than from the snapshot. `call`
// is Model.callState's, or null.
function tooltip(snapshot, device, nowPlaying, unreadMessages, call) {
  if (!device) return statusWord(snapshot, device)
  var lines = [device.name + " — " + statusWord(snapshot, device)]
  if (call) lines.push((call.state === "ringing" ? "Call from " : "Missed call from ") + call.who)
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

// A conversation notification (bridge `conversation`: plain {sender, text}
// pairs) grouped the way the phone draws it: a sender's name once, then what
// they sent. A message with no sender continues the one before; at the start
// it is from whoever the title names (a one-to-one chat), so no name shows.
function conversationGroups(n) {
  var list = n && n.conversation ? n.conversation : []
  var groups = []
  for (var i = 0; i < list.length; i++) {
    var sender = String(list[i] && list[i].sender || "").trim()
    var text = String(list[i] && list[i].text || "").trim()
    if (text === "") continue
    var last = groups.length ? groups[groups.length - 1] : null
    if (last && (sender === "" || sender === last.sender)) last.text += "\n" + text
    else groups.push({ sender: sender, text: text })
  }
  return groups
}

// A folded chat shows what the phone's folded one does: who sent the last
// message, and that message alone.
function latestMessage(n) {
  var list = n && n.conversation ? n.conversation : []
  var text = ""
  for (var i = list.length - 1; i >= 0; i--) {
    var t = String(list[i] && list[i].text || "").trim()
    var sender = String(list[i] && list[i].sender || "").trim()
    if (text === "" && t !== "") text = t
    if (text !== "" && sender !== "") return { sender: sender, text: text }
  }
  return text !== "" ? { sender: "", text: text } : null
}

// A group chat's title can end in the app's unread count, "Book club
// (8 messages)" (KDE Connect passes WhatsApp's title on as it is, #38). The
// panel shows the count apart from the name, in the app's own words (they
// are localised). Only a chat's title, and only a count in brackets at the
// very end, is taken apart; anything else is the title as it came.
function chatTitle(n) {
  var title = notificationTitle(n)
  if (!n || !n.conversation || n.conversation.length === 0) return { title: title, count: "" }
  var m = /^(.*\S)\s+\((\d+\s+[^()]+)\)$/.exec(title)
  return m ? { title: m[1], count: m[2].trim() } : { title: title, count: "" }
}

function notificationTitle(n) {
  if (!n) return ""
  return String(n.title || n.app || "Notification").trim()
}

// A snapshot for looking at the panel without waiting for real traffic: the
// live device (or a stand-in) with notifications covering reply,
// dismiss, actions, a long body and a group chat. Used by the `demo` IPC. Media is not
// faked: it comes from the phone's real MPRIS players.
// kind "away", "down" (daemon not running) and "none" (nothing paired) show
// the other states the panel has to draw.
function demoSnapshot(live, kind) {
  if (kind === "down") return { daemon: false, demo: true, devices: [] }
  // Several paired devices: the demo phone, a tablet with news, a laptop
  // that is away. "many-pair" adds a device asking to pair.
  if (kind === "many" || kind === "many-pair") {
    var many = demoSnapshot(live, "")
    // Made-up ids only, so nothing changed in this demo lands on a real
    // device's settings (they are cleared on leaving demo).
    many.devices[0].id = "demo"
    many.devices.push(
      { id: "demo-tab", name: "Galaxy Tab S9", type: "tablet", paired: true, reachable: true, links: ["LAN"],
        can: { share: true, clipboard: true, media: true, notifications: true, ping: true, ring: true },
        battery: { charge: 12, charging: false }, network: null,
        notifications: [
          { id: "demo-t1", key: "t1", app: "YouTube", title: "New from a channel you follow", text: "Ten minute bread, no knead", ticker: "", dismissable: true, replyId: "", actions: [], icon: "", silent: false },
          { id: "demo-t2", key: "t2", app: "Calendar", title: "Piano lesson", text: "Tomorrow at 17:00", ticker: "", dismissable: true, replyId: "", actions: [], icon: "", silent: false }
        ] },
      { id: "demo-laptop", name: "Work laptop", type: "laptop", paired: true, reachable: false, links: [], can: {}, notifications: [] })
    if (kind === "many-pair")
      many.devices.push({ id: "demo-new", name: "Pixel Tablet", type: "tablet", paired: false, reachable: true, pairRequestedByPeer: true, verificationKey: "4E5A3506", links: ["LAN"], can: {}, notifications: [] })
    return many
  }
  if (kind === "devices") {
    var withOthers = demoSnapshot(live, "")
    withOthers.devices.push(
      { id: "demo-tab", name: "Galaxy Tab", type: "tablet", paired: true, reachable: false, links: [], can: {}, notifications: [] },
      { id: "demo-laptop", name: "Work laptop", type: "laptop", paired: false, reachable: true, links: ["LAN"], can: {}, notifications: [] },
      { id: "demo-new", name: "Pixel Tablet", type: "tablet", paired: false, reachable: true, pairRequestedByPeer: true, verificationKey: "4E5A3506", links: ["LAN"], can: {}, notifications: [] })
    return withOthers
  }
  if (kind === "none") return { daemon: true, demo: true, devices: [] }
  var base = pickDevice(live, "")
  var dev = JSON.parse(JSON.stringify(base || {
    id: "demo", name: "Pixel 8", type: "phone", paired: true, reachable: true, links: ["LAN"],
    can: { ring: true, clipboard: true, share: true, sms: true, media: true, notifications: true },
    battery: { charge: 55, charging: false }
  }))
  // A neutral name and an id of its own, so a screenshot of demo mode shows
  // no real device: the real one's nickname, icon and place in the bar are
  // kept under its id, and do not apply here (#108).
  dev.name = "Pixel 8"
  dev.id = "demo"
  dev.reachable = kind !== "away"
  // Away: where it was, as the bridge's cache would say it.
  dev.lastSeen = kind === "away" ? { link: "LAN", address: "192.168.1.50", at: Date.now() - 12 * 60000 } : null
  // "charging": the battery filling, for its glyph and % in the bar.
  if (kind === "charging") dev.battery = { charge: 64, charging: true }
  // Every feature, whatever the real device offers or whether it is here.
  dev.can = { ring: true, clipboard: true, share: true, sms: true, media: true, notifications: true, ping: true }
  dev.network = { type: "5G", strength: 3 }
  // Two, so the panel's other sections have room: a text message (reply,
  // its own buttons, a long text) and a group chat (who said what).
  dev.notifications = [
    { id: "demo-4", key: "k4", app: "Messages", title: "Alex Rivera", text: "Running ten minutes late, traffic on the bridge is terrible. Start without me if everyone is there, and save me a slice! Also, could you put the folding chairs by the door so I can grab them on the way in?", ticker: "", dismissable: true, replyId: "r4", actions: ["Mark as read", "Reply"], icon: "", silent: false },
    { id: "demo-5", key: "k5", app: "WhatsApp", title: "Book club (3 messages)", text: "Sam Park: Chapter nine is a lot\nMaya Chen: No spoilers!\nMaya Chen: Thursday at 7 still works?", ticker: "", dismissable: true, replyId: "r5", actions: ["Mark as read", "Mute"], icon: "", silent: false,
      conversation: [{ sender: "Sam Park", text: "Chapter nine is a lot" }, { sender: "Maya Chen", text: "No spoilers!" }, { sender: "", text: "Thursday at 7 still works?" }] },
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


// ---- Collapsed sections: the one line shown in place of the content ----

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
  // The Devices section is gone from the main page (tabs and Settings do
  // its work), so it is not counted.
  var shown = visibleSections(sectionOrder)
  for (var i = 0; i < shown.length; i++) {
    var l = layoutBySection(shown[i])
    if (layoutFlag(flags[l.key])) on.push(l.label)
  }
  if (on.length === 0) return "Everything hidden"
  if (on.length === shown.length && shown.join() === DEFAULT_SECTIONS.filter(function(k) { return k !== "devices" }).join()) return "Everything shown"
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

// ---- Connection: this computer, pairing, adding a device ----

// The doctor's checks that are about this computer (the Connection page);
// its paired and connected checks are the devices' own pages' business.
var COMPUTER_CHECKS = ["installed", "running", "firewall", "network", "screen"]
// Short names: the status beside each says the rest ("Running", "Closed").
// One row per thing on this computer, named after it: a service's checks
// (KDE Connect: installed, running) become one row that says which state it
// is in, so other services (Bluetooth, scrcpy) can each have theirs.
var CHECK_NAMES = { kdeconnect: "KDE Connect", firewall: "Firewall", network: "Network", screen: "Screen and apps" }

function computerChecks(checks) {
  var list = (checks || []).filter(function(c) { return c && COMPUTER_CHECKS.indexOf(c.key) >= 0 })
  var installed = null, running = null, rest = []
  list.forEach(function(c) {
    if (c.key === "installed") installed = c
    else if (c.key === "running") running = c
    else rest.push(c)
  })
  if (!installed && !running) return rest
  // Not installed says so first; installed and stopped says Stopped.
  var failing = installed && !installed.ok ? installed : (running && !running.ok ? running : null)
  var kde = failing ? Object.assign({}, failing, { key: "kdeconnect" })
    : { key: "kdeconnect", ok: true, label: "KDE Connect", status: running ? running.status || "Running" : installed.status, detail: "", fix: "", fixLabel: "" }
  return [kde].concat(rest)
}

// Failing checks on this computer the user has not ignored: the gear's dot.
// An optional one (Screen and apps: only one feature needs it) never counts.
function connectionIssues(checks, ignored) {
  var skip = ignored || []
  return computerChecks(checks).filter(function(c) { return !c.ok && !c.optional && skip.indexOf(c.key) < 0 }).length
}

// The Connection row's pills: what this computer can do, one per thing.
// "on" works; "off" is an optional feature not set up yet (more can be
// done, nothing is wrong); "fail" is a required check failing, the only
// state that lights the gear's dot (an ignored one reads "off"). The
// Screen is on only once the viewed device's is ready, not when scrcpy is
// merely installed. `screenReady`: that device's state is "ready".
var PILL_LABELS = { kdeconnect: "KDE Connect", firewall: "Firewall", network: "Network", screen: "Screen" }
function connectionPills(checks, ignored, screenReady) {
  var skip = ignored || []
  return computerChecks(checks).map(function(c) {
    var state = c.ok ? "on" : (c.optional || skip.indexOf(c.key) >= 0 ? "off" : "fail")
    if (c.key === "screen" && c.ok && screenReady !== true) state = "off"
    return { key: c.key, label: PILL_LABELS[c.key] || CHECK_NAMES[c.key] || c.label, state: state }
  })
}

// One line under the pills, or in their place in a tooltip: what is to fix,
// else how much more can be set up, else that everything is on.
function connectionSummary(checks, ignored, screenReady) {
  var list = computerChecks(checks)
  if (list.length === 0) return "Checking…"
  var n = connectionIssues(checks, ignored)
  if (n > 0) return n === 1 ? "1 to fix" : n + " to fix"
  var off = connectionPills(checks, ignored, screenReady).filter(function(p) { return p.state === "off" }).length
  return off === 0 ? "Everything on" : (off === 1 ? "1 more to set up" : off + " more to set up")
}

// The Connection page's rows, in one list for the keyboard: this computer's
// checks (status icon, name, short status, one action; a failing one can be
// ignored). It checks what exists; Add a device (addDeviceRows) makes a new
// pairing.
function connectionRows(checks, ignored, screenReady) {
  var skip = ignored || []
  var rows = computerChecks(checks).map(function(c) {
    var row = { kind: "check", key: c.key, ok: !!c.ok, optional: !!c.optional, ignored: !c.ok && !c.optional && skip.indexOf(c.key) >= 0,
             label: CHECK_NAMES[c.key] || c.label, status: c.status || (c.ok ? "OK" : ""), detail: c.ok ? "" : String(c.detail || ""),
             fix: String(c.fix || ""), fixLabel: String(c.fixLabel || "Fix") }
    // Installed is half of it: on once the device's own steps are done.
    if (c.key === "screen" && c.ok)
      Object.assign(row, screenReady === true ? { status: "On", fix: "" } : { ok: false, status: "Not set up on the device" })
    return row
  })
  return rows
}

// The Add a device page's rows: devices asking to pair, then devices in
// reach to pair with (`devices`: devicesListRows).
function addDeviceRows(devices) {
  var rows = []
  ;(devices || []).forEach(function(r) { if (r.kind === "request") rows.push(r) })
  ;(devices || []).forEach(function(r) { if (r.kind === "available") rows.push(r) })
  return rows
}

// ---- Screen and apps: scrcpy over adb (kdeconnect-bridge screen) ----

// The Screen and apps page for one device: a line on where it stands, the
// steps (each done or not; the first not done is the current one), and the
// page's actions, which are also its keyboard rows. `status`: the bridge's
// (`screen <device>`), null while it is read; `pairing`: the QR pairing on
// this page ({ phase, qr, message }), or null.
function screenSetup(status, device, pairing, docked) {
  var name = deviceLabel(device)
  var s = status || { state: "checking", tools: {} }
  var tools = s.tools || {}
  var state = String(s.state || "checking")
  var ready = state === "ready"
  var trusted = ready || state === "off" || state === "unauthorized"
  // Wireless debugging seen on this Wi-Fi (the device announces it): the
  // steps before the code are done, whatever adb knows yet.
  var seen = s.seen === true
  var samsung = isSamsung(device)
  var phase = pairing ? String(pairing.phase || "") : ""
  var steps = [
    { key: "tools", text: "scrcpy and adb on this computer", done: tools.ok === true },
    { key: "developer", done: trusted || seen,
      text: "On " + name + ", turn on Developer options: " + (samsung ? "Settings › About phone › Software information" : "Settings › About phone")
        + " › tap Build number seven times (it asks for your PIN)" },
    { key: "wireless", done: ready || seen,
      text: "Turn on Wireless debugging: Settings › " + (samsung ? "Developer options (at the bottom)" : "System › Developer options")
        + " › Wireless debugging, and Allow on this network. This page ticks it when it sees it" },
    { key: "pair", done: trusted, qr: true,
      text: "Tap the words Wireless debugging to open it, then Pair device with QR code, and scan the code here" }
  ]
  // A code on show: the steps before it are done on the device by now,
  // so scanning it is the step.
  var current = -1
  if (phase !== "" && phase !== "error" && !trusted) current = steps.length - 1
  else for (var i = 0; i < steps.length; i++) if (!steps[i].done) { current = i; break }
  steps.forEach(function(st, i) { st.current = i === current })

  var line = {
    checking: "Checking…",
    tools: "Install scrcpy and adb to see " + name + "'s screen, and open its apps in windows, here",
    pair: seen ? "Wireless debugging is on: scan the code with " + name
      : "Once, " + name + " trusts this computer: then its screen opens from the Screen shortcut",
    off: seen ? "Wireless debugging is on, but " + name + " does not know this computer any more: scan the code again"
      : "Wireless debugging is off on " + name + ". Turn it on: Developer options › Wireless debugging",
    unauthorized: "On " + name + ", allow USB debugging (tick Always allow from this computer)",
    away: name + " is away: on this Wi-Fi with Wireless debugging on, or on a USB cable",
    ready: "Ready over " + (s.via === "usb" ? "USB" : "Wi-Fi") + (s.android ? " · Android " + s.android : "")
  }[state] || "Checking…"
  if (ready && s.apps !== true) line += ". Apps in windows need Android 10"

  var pairingNote = phase === "starting" ? "Making a code…"
    : phase === "qr" ? "Waiting for " + name + " to scan it…"
    : phase === "found" ? "Found " + name + ": pairing…"
    : phase === "paired" ? "Paired: connecting…"
    : phase === "error" ? String(pairing.message || "That did not work")
    : ""

  var actions = []
  if (state === "tools") actions.push({ key: "install", label: "Install", hint: "Asks for your password" })
  if (state === "pair" || state === "off" || state === "away") {
    if (phase === "" || phase === "error") actions.push({ key: "pair", label: state === "pair" ? "Show the code" : "Pair again", hint: "A QR code for " + name + " to scan" })
    else actions.push({ key: "stopPair", label: "Stop", hint: "" })
  }
  if (state !== "ready" && state !== "tools" && state !== "checking") actions.push({ key: "check", label: "Check again", hint: "" })
  if (ready) {
    actions.push({ key: "open", label: "Show the screen", hint: "Use it with your mouse: right-click is Back" })
    // Where it opens: one of two, like a choice in Settings.
    actions.push({ key: "dockOn", label: "Opens under the bar", on: docked !== false,
                   hint: "Under its icon, on top, on every workspace" })
    actions.push({ key: "dockOff", label: "Opens as a window", on: docked === false,
                   hint: "Tiles, moves and resizes like any other window" })
  }
  return {
    state: state, line: line, steps: steps, pairingNote: pairingNote,
    showQr: !!(pairing && pairing.qr && (phase === "qr" || phase === "found")),
    usbNote: state === "pair" || state === "away" ? "No Wi-Fi debugging (Android 10 and older)? Turn on USB debugging in Developer options and plug it in." : "",
    actions: actions
  }
}

// ---- The screen opening: the panel's card becomes the docked window ----

// The docked window's box (DOCK_* in the bridge): of the screen's height,
// and of its width, which a tablet in landscape meets first.
var DOCK_SHARE = { height: 0.7, width: 0.45 }

// The device's display (its current width and height, rotation and a
// foldable's screen included) fitted to the box: a phone meets its height,
// a tablet in landscape its width. Unknown: a phone's shape.
function fitDisplay(display, boxW, boxH) {
  var w = display && display[0] > 0 && display[1] > 0 ? display[0] : 9
  var h = display && display[0] > 0 && display[1] > 0 ? display[1] : 19.5
  var k = Math.min(boxW / w, boxH / h)
  return { w: Math.round(w * k), h: Math.round(h * k) }
}

// Where the card ends when it becomes the device's docked window: its
// size, the display fitted to the box (never past the room under the
// bar), placed as Omarchy's KeyboardPanel places a card (cardOrigin), so
// the card only grows into it and the window then takes its exact place.
// ctx: { display, barPos, screenW, screenH, barW, barH, gap, margin,
// anchorX, anchorY, anchorW, anchorH }, in the monitor's coordinates.
function dockRect(ctx) {
  var side = ctx.barPos === "left" || ctx.barPos === "right"
  var roomW = ctx.screenW - (side ? ctx.barW + ctx.gap + ctx.margin : 2 * ctx.margin)
  var roomH = ctx.screenH - (side ? 2 * ctx.margin : ctx.barH + ctx.gap + ctx.margin)
  var size = fitDisplay(ctx.display, Math.min(roomW, ctx.screenW * DOCK_SHARE.width), Math.min(roomH, ctx.screenH * DOCK_SHARE.height))
  var x, y
  if (ctx.barPos === "bottom") { x = ctx.anchorX + ctx.anchorW / 2 - size.w / 2; y = ctx.screenH - ctx.barH - size.h - ctx.gap }
  else if (ctx.barPos === "left") { x = ctx.barW + ctx.gap; y = ctx.anchorY + ctx.anchorH / 2 - size.h / 2 }
  else if (ctx.barPos === "right") { x = ctx.screenW - ctx.barW - size.w - ctx.gap; y = ctx.anchorY + ctx.anchorH / 2 - size.h / 2 }
  else { x = ctx.anchorX + ctx.anchorW / 2 - size.w / 2; y = ctx.barH + ctx.gap }
  x = Math.max(ctx.margin, Math.min(x, ctx.screenW - size.w - ctx.margin))
  y = Math.max(ctx.margin, Math.min(y, ctx.screenH - size.h - ctx.margin))
  return { x: Math.round(x), y: Math.round(y), w: size.w, h: size.h }
}

// The page's keyboard rows: one per action, in order.
function screenRows(setup) {
  return (setup ? setup.actions : []).map(function(a) {
    var row = { kind: "screenAction", key: a.key, label: a.label, hint: a.hint }
    if (a.on !== undefined) row.on = a.on
    return row
  })
}

// Made-up states for the demo phone (screenshots and checks): nothing in a
// demo reaches adb or a device.
function demoScreen(kind) {
  var tools = { scrcpy: true, adb: true, ok: true, version: "4.1", apps: true, flex: true }
  if (kind === "tools") return { state: "tools", tools: { ok: false } }
  if (kind === "ready" || kind === "opens") return { state: "ready", tools: tools, via: "wifi", android: "16", sdk: 36, apps: true, wireless: true, display: [1080, 2400] }
  // Wireless debugging just turned on, not paired yet.
  if (kind === "seen") return { state: "pair", seen: true, tools: tools, via: "", android: "", sdk: 0, apps: false, wireless: true }
  return { state: kind || "pair", tools: tools, via: "", android: "", sdk: 0, apps: false, wireless: true }
}

// ---- A paired device that is away: where it was, and what to try ----

// Whether an IPv4 address is inside a network written "192.168.1.0/24";
// null when either cannot be read.
function inNetwork(address, network) {
  var m = /^(\d+)\.(\d+)\.(\d+)\.(\d+)\/(\d+)$/.exec(String(network || ""))
  var a = /^(\d+)\.(\d+)\.(\d+)\.(\d+)$/.exec(String(address || ""))
  if (!m || !a) return null
  function num(x) { return ((Number(x[1]) * 256 + Number(x[2])) * 256 + Number(x[3])) * 256 + Number(x[4]) }
  var size = Math.pow(2, 32 - Number(m[5]))
  return Math.floor(num(a) / size) === Math.floor(num(m) / size)
}

// "just now", "5 min ago", "2 h ago", "3 days ago".
function agoText(ms, nowMs) {
  var s = Math.max(0, Math.round((nowMs - ms) / 1000))
  if (s < 60) return "just now"
  if (s < 3600) return Math.round(s / 60) + " min ago"
  if (s < 86400) return Math.round(s / 3600) + " h ago"
  var d = Math.round(s / 86400)
  return d === 1 ? "a day ago" : d + " days ago"
}

// How long Reconnect waits for the device before saying it was not found.
var SEARCH_MS = 8000

// Samsung's advice (battery use Unrestricted) is for Samsung devices only.
function isSamsung(device) { return /galaxy|samsung|^sm-/i.test(String(device && device.name || "")) }

// What an away device's page says, as short lines: where it was last seen
// (device.lastSeen, from the bridge's cache), whether that was another
// network, and after a search that found nothing, what to try on it.
// Causes are likely, never certain. `searchedAt`: when Reconnect last
// started, 0 for never.
function awayState(device, network, searchedAt, nowMs) {
  var seen = device && device.lastSeen
  var lines = []
  if (seen && seen.at) {
    var how = seen.link === "Bluetooth" ? "Bluetooth" : (seen.link === "LAN" ? "Wi-Fi" : "the network")
    lines.push("Last seen on " + how + (seen.address ? " at " + seen.address : "") + ", " + agoText(seen.at, nowMs))
    if (inNetwork(seen.address, network) === false)
      lines.push("Likely on another network: this computer is on " + network)
  } else {
    lines.push("Not seen by this computer yet")
  }
  var searching = searchedAt > 0 && nowMs - searchedAt < SEARCH_MS
  if (searchedAt > 0 && !searching)
    lines.push("Not found. On " + deviceLabel(device) + ": open KDE Connect, and join the same Wi-Fi"
      + (isSamsung(device) ? "; set the app's battery use to Unrestricted" : ""))
  return { lines: lines, searching: searching }
}

// ---- Installing the app: its store pages, and a QR code for the phone ----

var APP_LINKS = {
  play: "https://play.google.com/store/apps/details?id=org.kde.kdeconnect_tp",
  fdroid: "https://f-droid.org/packages/org.kde.kdeconnect_tp/",
  appStore: "https://apps.apple.com/app/kde-connect/id1580245991"
}

// qrencode's text output (`qrencode -t ASCII -m 0 <url>`: a line per row,
// two characters per module, "#" dark) as { size, dark: [row][col] }, or
// null when it is not a square grid.
function qrGrid(text) {
  var lines = String(text || "").split("\n").filter(function(l) { return l.length > 0 })
  var size = lines.length
  if (size < 21) return null
  var dark = []
  for (var r = 0; r < size; r++) {
    if (lines[r].length !== size * 2) return null
    var row = []
    for (var c = 0; c < size; c++) row.push(lines[r].charAt(2 * c) === "#")
    dark.push(row)
  }
  return { size: size, dark: dark }
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

// ---- Many devices: profiles, order, attention, the pill's chips ----
// (docs/design/multi-device.md). A device's profile is how the plugin shows
// it; nothing about the device itself is stored.
//
// Storage, in this widget's shell.json entry: today's flat keys are the
// defaults every device uses; `devices` maps a device id to what that device
// changed, plus its identity; `deviceOrder` orders them. Nothing is written
// on upgrade: old entries are read as they are (readSettings), and the new
// keys appear only when the user changes something.

// Settings a device can change away from the defaults, and how each is
// cleaned. A device's change of a list is merged like the defaults are, so a
// section or shortcut added in a later release still reaches it.
var PROFILE_SETTINGS = {
  barIndicators: function(v) { return normalizeBarIndicators(v) },
  batteryLowOnly: function(v) { return layoutFlag(v) },
  sectionOrder: function(v) { return normalizeSections(v) },
  shortcuts: function(v) { return normalizeShortcuts(v) },
  showShortcuts: function(v) { return layoutFlag(v) },
  showMedia: function(v) { return layoutFlag(v) },
  showNotifications: function(v) { return layoutFlag(v) },
  showPhotos: function(v) { return layoutFlag(v) },
  showReceived: function(v) { return layoutFlag(v) },
  showCalls: function(v) { return layoutFlag(v) },
  // The screen's window: docked by the bar (Omarchy's pop-out), or tiled.
  screenDocked: function(v) { return layoutFlag(v) },
  collapsed: function(v) { return collapsedState(v) }
}

// Identity: the device's own, never taken from the defaults.
// bar: "always" | "attention" | "never" | "own" (own pills come later;
// until then an own pill shows as "always").
var BAR_PLACES = ["always", "attention", "never", "own"]

function plainObject(v) { return !!v && typeof v === "object" && !Array.isArray(v) }

// The widget's entry as the rest of the plugin reads it: { defaults,
// devices, order, raw }. `defaults` holds every profile setting, cleaned;
// `devices` maps an id to its stored profile (identity and changes);
// `order` is the stored order, else the old `deviceId` alone.
function readSettings(entry) {
  var e = plainObject(entry) ? entry : {}
  var defaults = {}
  for (var key in PROFILE_SETTINGS) defaults[key] = PROFILE_SETTINGS[key](e[key])
  var devices = plainObject(e.devices) ? e.devices : {}
  var order = []
  if (Array.isArray(e.deviceOrder)) {
    for (var i = 0; i < e.deviceOrder.length; i++) {
      var id = String(e.deviceOrder[i] || "")
      if (id && order.indexOf(id) < 0) order.push(id)
    }
  } else if (e.deviceId) {
    order.push(String(e.deviceId))
  }
  return { defaults: defaults, devices: devices, order: order, raw: e }
}

// Paired devices in the user's order: the stored order first (those still
// paired), then the rest as KDE Connect lists them, the reachable ones
// before the away ones. The first is where the panel opens when it is
// connected, and the one that shows "always" by default.
function orderedDevices(snapshot, settings) {
  var list = snapshot && snapshot.devices ? snapshot.devices : []
  var paired = list.filter(function(d) { return d && d.paired === true })
  var byId = {}
  paired.forEach(function(d) { byId[d.id] = d })
  var out = []
  settings.order.forEach(function(id) { if (byId[id]) { out.push(byId[id]); delete byId[id] } })
  var rest = paired.filter(function(d) { return byId[d.id] })
  // Connected first, otherwise as KDE Connect lists them. The engine's sort
  // is not stable, so the list position breaks ties: a device joining the
  // list must never swap two others (the first shows always, opens first).
  var at = {}
  rest.forEach(function(d, i) { at[d.id] = i })
  rest.sort(function(a, b) { return ((b.reachable === true) - (a.reachable === true)) || (at[a.id] - at[b.id]) })
  return out.concat(rest)
}

// One device's effective profile: identity from its own stored profile
// (with defaults of its own: the first device shows always, the others with
// attention), every other setting its change or the default. `custom` says
// which settings the device changed.
function resolveProfile(settings, device, isFirst) {
  var stored = device && plainObject(settings.devices[device.id]) ? settings.devices[device.id] : {}
  var bar = BAR_PLACES.indexOf(String(stored.bar)) >= 0 ? String(stored.bar) : (isFirst ? "always" : "attention")
  var p = {
    id: device ? String(device.id) : "",
    nickname: String(stored.nickname || "").replace(/\s+/g, " ").trim(),
    icon: /^[0-9A-Fa-f]{4,6}$/.test(String(stored.icon || "")) ? String(stored.icon).toUpperCase() : "",
    bar: bar,
    showInPanel: stored.showInPanel !== false,
    // The Screen shortcut was added when its screen was set up: once, so a
    // removal stays removed (screenShortcutChanges).
    screenShortcut: stored.screenShortcut === "added",
    custom: {}
  }
  for (var key in PROFILE_SETTINGS) {
    if (stored[key] !== undefined && stored[key] !== null) {
      p[key] = PROFILE_SETTINGS[key](stored[key])
      p.custom[key] = true
    } else {
      p[key] = settings.defaults[key]
    }
  }
  return p
}

// The name to show: the nickname, else the name KDE Connect reports.
function deviceTitle(device, profile) {
  return profile && profile.nickname ? profile.nickname : deviceLabel(device)
}

// The icon to show: the one picked, else the one for the device's kind.
function deviceIcon(device, profile) {
  if (profile && profile.icon) return String.fromCodePoint(parseInt(profile.icon, 16))
  return deviceGlyph(device)
}

// What a device wants the user to see (the attention table). `st` is what
// the snapshot does not carry: { notifications, messages, call: { state },
// lowPercent }. Away is not attention; nothing from an away device is.
function attention(device, profile, st) {
  var s = st || {}
  var here = !!device && device.reachable === true
  var countsMessages = !!profile && (profile.barIndicators || []).indexOf("messages") >= 0
  var a = {
    notifications: here ? Math.max(0, s.notifications || 0) : 0,
    messages: here && countsMessages ? Math.max(0, s.messages || 0) : 0,
    ringing: here && !!s.call && s.call.state === "ringing",
    missed: here && !!s.call && s.call.state === "missed",
    lowBattery: here && lowBattery(device, s.lowPercent === undefined ? 15 : s.lowPercent)
  }
  a.any = a.notifications > 0 || a.messages > 0 || a.ringing || a.missed || a.lowBattery
  return a
}

// The pill: one chip per device that shows, in order, and a resting glyph
// when none does, so the pill never disappears (principle 4).
//
// `states` maps a device id to its attention inputs (see `attention`) plus
// `playing`. A ringing device always gets a chip while it rings, whatever
// its choice: a call is the one thing that overrides it. `pairing`: a device
// is asking to pair (shown as a mark on the first chip or the resting glyph).
//
// Returns { chips: [{ id, glyph, text, bubble, dimmed, ringing, marks }],
//           resting: null | { glyph, dimmed, ringing }, pairing }.
function chips(snapshot, settings, states, pairing) {
  var daemon = !!(snapshot && snapshot.daemon)
  var devices = orderedDevices(snapshot, settings)
  var out = []
  for (var i = 0; i < devices.length; i++) {
    var d = devices[i]
    var p = resolveProfile(settings, d, i === 0)
    var st = (states && states[d.id]) || {}
    var a = attention(d, p, st)
    var place = p.bar === "own" ? "always" : p.bar
    var shows = a.ringing || place === "always" || (place === "attention" && a.any)
    if (!shows) continue
    var glyph = deviceIcon(d, p)
    out.push({
      id: String(d.id),
      glyph: glyph,
      // The chip's text: its icon and its indicators, as today's pill.
      text: barText(d, p.barIndicators, { glyph: glyph, lowPercent: st.lowPercent, lowOnly: p.batteryLowOnly,
        notifications: a.notifications, messages: a.messages, playing: !!st.playing , call: st.call }),
      parts: barParts(d, p.barIndicators, { glyph: glyph, lowPercent: st.lowPercent, lowOnly: p.batteryLowOnly,
        notifications: a.notifications, messages: a.messages, playing: !!st.playing , call: st.call }),
      bubble: barBubble(d, p.barIndicators, a.notifications),
      dimmed: d.reachable !== true,
      ringing: a.ringing,
      marks: { missed: a.missed, lowBattery: a.lowBattery }
    })
  }
  var resting = null
  if (out.length === 0) {
    if (!daemon || devices.length === 0) resting = { glyph: GLYPH.devices, dimmed: !daemon, ringing: false }
    else resting = { glyph: deviceIcon(devices[0], resolveProfile(settings, devices[0], true)), dimmed: true, ringing: false }
  }
  return { chips: out, resting: resting, pairing: !!pairing }
}

// The device the panel opens on: the ringing one, else the first connected
// one shown in the panel, else the first shown in the panel. `states` as
// for chips. Returns the device, or null when nothing is paired.
function openingDevice(snapshot, settings, states) {
  var devices = orderedDevices(snapshot, settings)
  var shown = devices.filter(function(d, i) { return resolveProfile(settings, d, i === 0).showInPanel })
  for (var i = 0; i < devices.length; i++) {
    var st = (states && states[devices[i].id]) || {}
    if (devices[i].reachable === true && st.call && st.call.state === "ringing") return devices[i]
  }
  for (var j = 0; j < shown.length; j++) if (shown[j].reachable === true) return shown[j]
  return shown.length > 0 ? shown[0] : (devices.length > 0 ? devices[0] : null)
}

// The entry with one device's profile changed: `changes` merges into its
// stored profile (null removes a key: back to the default). The first
// device's "always" is written down on its first change, so that reordering
// later never changes how it shows. Other keys of the entry are untouched.
function withProfile(entry, deviceId, changes, isFirst) {
  var e = Object.assign({}, plainObject(entry) ? entry : {})
  var devices = Object.assign({}, plainObject(e.devices) ? e.devices : {})
  var p = Object.assign({}, plainObject(devices[deviceId]) ? devices[deviceId] : {})
  if (isFirst && p.bar === undefined) p.bar = "always"
  for (var key in changes) {
    if (changes[key] === null || changes[key] === undefined) delete p[key]
    else p[key] = changes[key]
  }
  devices[deviceId] = p
  e.devices = devices
  return e
}

// What setting up a device's screen writes, once: the Screen shortcut
// joins its shortcuts (where they live: the flat keys with one device, its
// profile with several) and its profile notes that it did. null when it
// was done before; the user may have taken the shortcut away since.
function screenShortcutChanges(entry, deviceId, profile, single, isFirst) {
  if (!profile || profile.screenShortcut) return null
  var next = profile.shortcuts.indexOf("screen") >= 0 ? null : profile.shortcuts.concat(["screen"])
  if (single) {
    var changes = { devices: withProfile(entry, deviceId, { screenShortcut: "added" }, isFirst).devices }
    if (next) changes.shortcuts = next
    return changes
  }
  var own = { screenShortcut: "added" }
  if (next) own.shortcuts = next
  return { devices: withProfile(entry, deviceId, own, isFirst).devices }
}

// The entry with a new device order (ids). The old `deviceId` stays as it
// was, for a downgrade.
function withOrder(entry, ids) {
  var e = Object.assign({}, plainObject(entry) ? entry : {})
  e.deviceOrder = ids.map(String)
  return e
}

// ---- Settings for devices (step 3) ----

// Icons a device can take, all checked by rendering in the bar's Nerd Font.
// `code` is what a profile stores (hex, no prefix).
var ICON_CHOICES = [
  { code: "F011C", label: "Phone" }, { code: "F011F", label: "Phone, older" },
  { code: "F04F6", label: "Tablet" }, { code: "F0322", label: "Laptop" },
  { code: "F0379", label: "Monitor" }, { code: "F0AAB", label: "Desktop" },
  { code: "F0502", label: "TV" }, { code: "F02CB", label: "Headphones" },
  { code: "F02DC", label: "Home" }, { code: "F00D6", label: "Work" },
  { code: "F0A5E", label: "Family" }, { code: "F04CE", label: "Star" },
  { code: "F02D1", label: "Heart" }, { code: "F0384", label: "Music" },
  { code: "F06A9", label: "Robot" }
]

var BAR_PLACE_LABELS = { always: "Always", attention: "With news", never: "Never" }

// Which profile settings each settings group holds, for its Custom mark and
// its "Use the defaults".
var SETTING_GROUPS = {
  layout: ["showShortcuts", "showMedia", "showNotifications", "showReceived", "showPhotos", "sectionOrder"],
  bar: ["barIndicators", "batteryLowOnly", "showCalls"],
  shortcuts: ["shortcuts"]
}

function groupCustom(custom, group) {
  var keys = SETTING_GROUPS[group] || []
  for (var i = 0; i < keys.length; i++) if (custom && custom[keys[i]]) return true
  return false
}

// The Devices list at the top of Settings: every paired device in order,
// then devices asking to pair, then devices in reach that could be paired.
function devicesListRows(snapshot, settings, lowPercent) {
  var ordered = orderedDevices(snapshot, settings)
  var rows = []
  for (var i = 0; i < ordered.length; i++) {
    var d = ordered[i]
    var p = resolveProfile(settings, d, i === 0)
    rows.push({ kind: "device", id: String(d.id), glyph: deviceIcon(d, p), title: deviceTitle(d, p), name: String(d.name || ""),
                status: d.reachable === true ? metaLine(snapshot, d, lowPercent) : "Away",
                away: d.reachable !== true, first: i === 0, last: i === ordered.length - 1, pos: i, count: ordered.length })
  }
  // Asking to pair first (they wait on the user), then those in reach.
  var list = snapshot && snapshot.devices ? snapshot.devices : []
  list.forEach(function(o) {
    if (o && o.paired !== true && o.pairRequestedByPeer === true)
      rows.push({ kind: "request", id: String(o.id), glyph: deviceGlyph(o), title: String(o.name || "A device"), name: String(o.name || ""),
                  status: "Wants to pair", pairKey: String(o.verificationKey || "") })
  })
  list.forEach(function(o) {
    if (o && o.paired !== true && o.pairRequestedByPeer !== true && o.reachable === true)
      rows.push({ kind: "available", id: String(o.id), glyph: deviceGlyph(o), title: String(o.name || "A device"), name: String(o.name || ""),
                  status: o.pairRequested === true ? "Waiting for it to accept" : "Available to pair",
                  pairKey: o.pairRequested === true ? String(o.verificationKey || "") : "", waiting: o.pairRequested === true })
  })
  return rows
}

// Every row of the settings page, in one list so keyboard and mouse share a
// cursor. `ctx`:
//   scope: "root" | "defaults" | "device"
//   single: one paired device or none (Settings is one flat page)
//   devices: devicesListRows(...)            (root)
//   identity: { nickname, icon, glyph, bar, showInPanel } (single root, device)
//   edit: the profile being edited (defaults, or the device's), with custom
//   can: the device's capabilities, for shortcuts it cannot do
function settingsPageRows(ctx) {
  var rows = []
  var scope = ctx.scope || "root"
  if (scope === "root") {
    if (!ctx.single) (ctx.devices || []).forEach(function(r) { rows.push(r) })
    else (ctx.devices || []).forEach(function(r) { if (r.kind !== "device") rows.push(r) })
  }
  var identity = ctx.identity && (scope === "device" || (scope === "root" && ctx.single))
  if (identity) {
    rows.push({ kind: "nickname", key: "nickname", label: "Nickname", hint: "In the bar and the tabs; short is best", value: ctx.identity.nickname })
    rows.push({ kind: "icon", key: "icon", label: "Icon", hint: "Its glyph in the bar and the tabs", glyph: ctx.identity.glyph, value: ctx.identity.icon })
    if (scope === "device") {
      rows.push({ kind: "barPlace", key: "bar", label: "In the bar", hint: "Its chip: always, only with news, or never", value: ctx.identity.bar === "own" ? "always" : ctx.identity.bar })
      rows.push({ kind: "showInPanel", key: "showInPanel", label: "Show in panel", hint: "A tab for it in the panel", on: ctx.identity.showInPanel !== false })
    }
  }
  if (scope === "root" && !ctx.single) {
    rows.push({ kind: "defaults", key: "defaults", label: "Defaults for all devices", hint: "Sections, bar and shortcuts for devices that did not change them, and for new ones" })
  } else {
    // A panel torn down mid-reload can ask with nothing to edit.
    var e = ctx.edit || resolveProfile(readSettings({}), null, true)
    var base = settingsRows({ showShortcuts: e.showShortcuts, showMedia: e.showMedia, showNotifications: e.showNotifications, showReceived: e.showReceived, showPhotos: e.showPhotos },
                            e.shortcuts, ctx.can || null, e.sectionOrder, e.barIndicators, e.batteryLowOnly, e.showCalls)
    // A device's page (and the one-device page) edits its sections,
    // shortcuts and bar on the page itself (edit in place): here, a row
    // that opens that. The defaults, with no page of their own, keep them.
    var onPage = scope === "device" || (scope === "root" && ctx.single)
    if (onPage) rows.push({ kind: "editPage", key: "editPage", label: "Sections, shortcuts and bar",
                            hint: "Edited on the page itself (✎, or right-click its chip in the bar)" })
    if (onPage) rows.push({ kind: "screen", key: "screen", label: "Screen and apps",
                            hint: "Its screen, and its apps each in a window, here (scrcpy)" })
    base.forEach(function(r) {
      // The Devices section is gone from the main page (tabs, the pairing
      // card and this list do its work); the kdeconnect row stays at root.
      if (r.kind === "layout" && r.section === "devices") return
      if (r.kind === "kdeconnect" || r.kind === "reset") return
      if (onPage && (r.kind === "layout" || r.kind === "shortcut" || r.kind === "bar" || r.kind === "barFlag")) return
      rows.push(r)
    })
    if (scope === "device") {
      ["layout", "bar", "shortcuts"].forEach(function(g) {
        if (groupCustom(e.custom, g))
          rows.push({ kind: "resetGroup", key: g, label: { layout: "Layout", bar: "Bar", shortcuts: "Shortcuts" }[g] + ": use the defaults",
                      hint: "This device changed it; the defaults apply again" })
      })
      rows.push({ kind: "unpair", key: "unpair", label: "Unpair" })
    } else if (!onPage) {
      rows.push({ kind: "reset", key: "reset", label: "Reset shortcuts" })
    }
  }
  if (scope === "root") {
    rows.push({ kind: "connection", key: "connection", label: "Connection", hint: ctx.connection || "KDE Connect, the firewall, the network",
                pills: ctx.connectionPills || [] })
    rows.push({ kind: "addDevice", key: "addDevice", label: "Add a device", hint: "The steps on it, requests to pair, devices in reach" })
    rows.push({ kind: "kdeconnect", key: "kdeconnect", label: "KDE Connect settings" })
  }
  return rows
}

// The entry with a new device order. A device whose place in the bar only
// followed from its position (the first shows always, the others with news)
// gets that place written down first, so moving devices never changes how
// they show.
function withDeviceOrder(entry, snapshot, ids) {
  var before = readSettings(entry)
  var ordered = orderedDevices(snapshot, before)
  var e = plainObject(entry) ? entry : {}
  var stored = plainObject(e.devices) ? e.devices : {}
  var next = Object.assign({}, e)
  for (var i = 0; i < ordered.length; i++) {
    var id = String(ordered[i].id)
    var nowFirst = ids.length > 0 && String(ids[0]) === id
    var s = plainObject(stored[id]) ? stored[id] : {}
    if (s.bar === undefined && (i === 0) !== nowFirst)
      next = withProfile(next, id, { bar: i === 0 ? "always" : "attention" }, false)
  }
  return withOrder(next, ids)
}

// The order moved by one step for `id` (Shift+K / Shift+J, the arrows).
function movedOrder(snapshot, settings, id, delta) {
  var ids = orderedDevices(snapshot, settings).map(function(d) { return String(d.id) })
  return moveShortcut(ids, String(id), delta)
}

// ---- Moving an item in an order (Reorder.qml) ----
// `extent(i)` is item i's size along the axis; `gap` the space between two.

// Where an item dragged by `off` from its place `from` would land: past an
// item once it is past that item's middle.
function reorderTarget(from, off, count, extent, gap) {
  var t = from, edge = 0
  if (off > 0) {
    for (var i = from + 1; i < count; i++) {
      edge += extent(i) + gap
      if (off > edge - (extent(i) + gap) / 2) t = i; else break
    }
  } else if (off < 0) {
    for (var j = from - 1; j >= 0; j--) {
      edge -= extent(j) + gap
      if (off < edge + (extent(j) + gap) / 2) t = j; else break
    }
  }
  return t
}

// How far the moving item travels from `a` to land at `b`: the sizes of the
// items it passes.
function reorderOffset(a, b, extent, gap) {
  var x = 0
  for (var i = a + 1; i <= b; i++) x += extent(i) + gap
  for (var j = b; j < a; j++) x -= extent(j) + gap
  return x
}

// How far item `i` slides aside while the one at `from` would land at `to`:
// by the moving item's size (`step`, its size plus the gap).
function reorderShift(i, from, to, step) {
  if (from < 0 || i === from) return 0
  if (to > from && i > from && i <= to) return -step
  if (to < from && i < from && i >= to) return step
  return 0
}

// ---- Moving an item in a grid (the shortcut tiles while editing) ----

// Where item `i` sits while the one at `from` would land at `to`: the
// items between them step one place towards `from`.
function reorderSlot(i, from, to) {
  if (from < 0 || to < 0 || i === from) return i === from ? to : i
  if (to > from && i > from && i <= to) return i - 1
  if (to < from && i < from && i >= to) return i + 1
  return i
}

// A grid slot's top left, for `columns` cells of `cw` by `ch`, `gap` apart.
function gridSlot(k, columns, cw, ch, gap) {
  var c = Math.max(1, columns)
  return { x: (k % c) * (cw + gap), y: Math.floor(k / c) * (ch + gap) }
}

// The slot nearest to where a dragged item's middle is (it started in slot
// `from` and moved by dx, dy), among `count` slots.
function gridTarget(from, dx, dy, count, columns, cw, ch, gap) {
  var start = gridSlot(from, columns, cw, ch, gap)
  var mx = start.x + cw / 2 + dx, my = start.y + ch / 2 + dy
  var best = from, bestD = Infinity
  for (var k = 0; k < count; k++) {
    var s = gridSlot(k, columns, cw, ch, gap)
    var ddx = s.x + cw / 2 - mx, ddy = s.y + ch / 2 - my
    var d = ddx * ddx + ddy * ddy
    if (d < bestD) { bestD = d; best = k }
  }
  return best
}

// ---- Editing the page in place ----

// The shortcut tiles while editing: the chosen ones in their order (`pos`,
// they move), then every other one dimmed, to be added (`pos` -1).
function editShortcutTiles(order, can) {
  var chosen = shortcutTiles(order, can).map(function(t, i) { return Object.assign({ chosen: true, pos: i }, t) })
  var rest = []
  for (var i = 0; i < SHORTCUTS.length; i++)
    if (order.indexOf(SHORTCUTS[i].key) < 0)
      rest.push(Object.assign({ chosen: false, pos: -1 }, shortcutTiles([SHORTCUTS[i].key], can)[0]))
  return chosen.concat(rest)
}

// Editing: every bar indicator as it looks in the bar (a sample), the
// chosen ones in their order (with their place, for moving), then the rest.
function editBarTiles(order) {
  var chosen = normalizeBarIndicators(order)
  var out = chosen.map(function(k, i) {
    var ind = barIndicatorByKey(k)
    return { key: k, glyph: ind.glyph, sample: ind.sample, label: ind.tile, hint: ind.label, chosen: true, pos: i }
  })
  for (var i = 0; i < BAR_INDICATORS.length; i++)
    if (chosen.indexOf(BAR_INDICATORS[i].key) < 0)
      out.push({ key: BAR_INDICATORS[i].key, glyph: BAR_INDICATORS[i].glyph, sample: BAR_INDICATORS[i].sample, label: BAR_INDICATORS[i].tile,
                 hint: BAR_INDICATORS[i].label, chosen: false, pos: -1 })
  return out
}

// What a section says while editing when it has nothing to show now.
var SECTION_EMPTY = {
  actions: "No shortcuts: add some below",
  media: "Shows while the device plays something",
  notifications: "Shows while there are notifications",
  photos: "Shows its newest photos and videos",
  received: "Shows the files it sends you"
}

// ---- Files: the device's newest photos (#65) and files it sent (#37) ----

// "12 KB", "3.4 MB".
function sizeText(bytes) {
  var b = Number(bytes) || 0
  if (b < 1024) return b + " B"
  if (b < 1024 * 1024) return Math.round(b / 1024) + " KB"
  var mb = b / (1024 * 1024)
  return (mb < 10 ? mb.toFixed(1) : Math.round(mb)) + " MB"
}

var IMAGE_EXTENSIONS = ["jpg", "jpeg", "png", "webp", "gif", "heic"]
function isImage(name) {
  var m = /\.([A-Za-z0-9]+)$/.exec(String(name || ""))
  return !!m && IMAGE_EXTENSIONS.indexOf(m[1].toLowerCase()) >= 0
}

// A path as a file:// address, each part encoded apart (a name with # or ?
// stays whole), as Omarchy's own panels build one.
function fileUri(path) {
  return "file://" + String(path || "").split("/").map(function(p) { return encodeURIComponent(p) }).join("/")
}

function photosSummary(photos) {
  var list = photos || []
  if (list.length === 0) return "Nothing new"
  var videos = list.filter(function(p) { return p.video === true }).length
  var parts = []
  if (list.length > videos) parts.push(list.length - videos === 1 ? "1 photo" : (list.length - videos) + " photos")
  if (videos > 0) parts.push(videos === 1 ? "1 video" : videos + " videos")
  return parts.join(", ")
}

// Where the panel was when it closed, kept for a while: opened again within
// KEEP_PLACE_MS it goes back there (a glance at a picture, then back to the
// conversation), else it starts on its main page. Not when it must open
// elsewhere: setup (`openingScope`) or another device asked for (a chip).
var KEEP_PLACE_MS = 5 * 60 * 1000
function placeToResume(left, nowMs, ctx) {
  if (!left || !(nowMs - left.at >= 0 && nowMs - left.at < KEEP_PLACE_MS)) return null
  if (ctx && ctx.openingScope) return null
  if (ctx && ctx.requested && ctx.requested !== left.device) return null
  if (!left.settingsOpen && !left.messagesOpen && !(left.y > 0)) return null
  return left
}

// A photo's identity: the same file is the same tile, wherever it moves.
function photoIdentity(p) {
  return String(p.path) + "|" + String(p.name)
}

// The steps that turn one list of keys into another, for a model whose
// items should glide rather than be rebuilt: removals (from the end), then,
// place by place, a move of an item already there or an insert.
function listOps(oldKeys, newKeys) {
  var ops = [], cur = oldKeys.slice()
  for (var i = cur.length - 1; i >= 0; i--) {
    if (newKeys.indexOf(cur[i]) < 0) { ops.push({ op: "remove", at: i }); cur.splice(i, 1) }
  }
  for (var j = 0; j < newKeys.length; j++) {
    if (cur[j] === newKeys[j]) continue
    var from = cur.indexOf(newKeys[j])
    if (from > j) {
      ops.push({ op: "move", from: from, to: j })
      cur.splice(j, 0, cur.splice(from, 1)[0])
    } else {
      ops.push({ op: "insert", at: j, key: newKeys[j] })
      cur.splice(j, 0, newKeys[j])
    }
  }
  return ops
}

// What makes the tiles: a list with the same key is the same tiles, so a
// state change (a read starting or ending) does not rebuild them.
function photosKey(photos) {
  return (photos || []).map(function(p) { return [p.path, p.at, p.thumb, p.video === true].join("|") }).join("\n")
}

// The newest file's name, and how many more.
function receivedSummary(received) {
  var list = received || []
  if (list.length === 0) return "Nothing new"
  return list.length === 1 ? String(list[0].name) : list[0].name + " and " + (list.length - 1) + " more"
}

// Demo: photos from the one local demo picture, each a different part of it
// (`clip`: x, y, w, h as fractions), so a screenshot shows four of them;
// and two received files that exist nowhere (demo only opens nothing).
function demoPhotos(picture, nowMs, gallery) {
  var now = nowMs === undefined ? Date.now() : nowMs
  // Pictures put in the demo's gallery folder (not in the repository): up
  // to eight, two rows, the second one shown as a video.
  if (gallery && gallery.length > 0) {
    return gallery.slice(0, 8).map(function(path, i) {
      return { name: "PXL_2026092" + i + (i === 1 ? ".mp4" : ".jpg"), path: path, thumb: path, at: now - (i * 7 + 2) * 60000,
               album: i % 4 === 2 ? "Screenshots" : "Camera", video: i === 1, demo: true }
    })
  }
  var clips = [[0, 0, 1, 1], [0.1, 0.35, 0.5, 0.5], [0.45, 0.05, 0.5, 0.5], [0.2, 0.5, 0.45, 0.45]]
  return clips.map(function(c, i) {
    return { name: "PXL_2026092" + i + (i === 1 ? ".mp4" : ".jpg"), path: picture || "", thumb: picture || "", at: now - (i * 7 + 2) * 60000,
             album: i === 2 ? "Screenshots" : "Camera", video: i === 1, clip: c, demo: true }
  })
}
function demoReceived(nowMs) {
  var now = nowMs === undefined ? Date.now() : nowMs
  return [
    { path: "/demo/Boarding pass.pdf", name: "Boarding pass.pdf", size: 184320, at: now - 25 * 60000 },
    { path: "/demo/Recipe notes.txt", name: "Recipe notes.txt", size: 2150, at: now - 26 * 3600000 }
  ]
}
