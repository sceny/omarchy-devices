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
  optional: "\u{F0766}",     // circle-outline: a check only one feature needs
  tip: "\u{F0336}",          // lightbulb-outline: a tip while the screen connects
  dockTop: "\u{F1513}",      // dock-top: the screen opens under the bar
  window: "\u{F05B2}",       // window-restore: the screen opens as a window
  pin: "\u{F0403}",          // pin: an app kept in the Apps section
  pinOff: "\u{F0404}",       // pin-off
  search: "\u{F0349}",       // magnify
  contacts: "\u{F05D2}",     // card-account-details: the device's contacts
  openIn: "\u{F03CC}",       // open-in-new: a tool of this computer's opens
  place: "\u{F034E}",        // map-marker: a contact's address
  web: "\u{F059F}",          // web: a contact's website
  copy: "\u{F018F}",         // content-copy
  // Demo apps (no real icons in demo mode)
  clock: "\u{F0150}", calendar: "\u{F00ED}", camera: "\u{F0100}", map: "\u{F034D}", music: "\u{F075A}",
  notes: "\u{F082E}", weather: "\u{F0599}", chat: "\u{F0B79}", mail: "\u{F01EE}", image: "\u{F02E9}",
  calculator: "\u{F00EC}", cog: "\u{F0493}", cart: "\u{F0110}", bank: "\u{F0070}", fitness: "\u{F0E8E}"
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
  { key: "contacts", glyph: GLYPH.contacts, label: "Contacts", hint: "Its contacts, with every detail", needs: "contacts" },
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
  { key: "showApps", section: "apps", label: "Apps", hint: "Its apps, each in a window here, once its screen is set up" },
  { key: "showMedia", section: "media", label: "Now playing", hint: "What the device is playing" },
  { key: "showNotifications", section: "notifications", label: "Notifications", hint: "The device's notifications, with reply" },
  { key: "showReceived", section: "received", label: "Received", hint: "Files it sent you, while there are any" },
  { key: "showPhotos", section: "photos", label: "Gallery", hint: "Its newest photos and videos" }
]

// A section added in a release joins a saved order at its default place
// (normalizeSections), so Received and Photos come last for everyone who had
// an order.
var DEFAULT_SECTIONS = ["devices", "actions", "apps", "media", "notifications", "received", "photos"]

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
  for (var j = 0; j < DEFAULT_SECTIONS.length; j++) {
    var k = DEFAULT_SECTIONS[j]
    if (out.indexOf(k) >= 0) continue
    var after = SECTION_JOINS_AFTER[k] ? out.indexOf(SECTION_JOINS_AFTER[k]) : -1
    out.splice(after >= 0 ? after + 1 : Math.min(j, out.length), 0, k)
  }
  return out
}

// A section added later joins a saved order beside its neighbour, wherever
// the user put it (Apps after Shortcuts).
var SECTION_JOINS_AFTER = { apps: "actions" }

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
// (the same way), then Reset shortcuts.
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

// Where a window's sound plays (#129): here (scrcpy's default source, the
// device's whole output, the device quiet meanwhile), on the device (no
// sound forwarded), or both (what apps play, captured while it keeps
// playing there; an app may keep its sound to itself). Both needs Android
// 13 (scrcpy's playback source and its dup); any sound here, Android 11.
var SOUND_PLACES = ["here", "phone", "both"]
// The key the screen's own window is remembered under, beside its apps.
var SCREEN_SOUND = "@screen"

function soundPlace(v) {
  return SOUND_PLACES.indexOf(v) >= 0 ? v : "here"
}

// Where an app window's sound goes when it opens. `chosen`: the device's
// setting (here, phone or both); `playing`: the apps playing on it now
// (players' names); `remembered`: this app's last choice, made on its own
// window (kept in the cache). scrcpy takes the device's sound (not the
// app's alone): with something else playing there (music in its headset),
// a new app's sound stays on the device, unless the user chose otherwise
// for that app; the app that is playing keeps its sound here.
function appSound(chosen, playing, appName, remembered) {
  if (SOUND_PLACES.indexOf(remembered) >= 0) return { sound: remembered, kept: false, remembered: true }
  if (chosen === "phone") return { sound: "phone", kept: false }
  var name = String(appName || "").toLowerCase()
  var others = (playing || []).filter(function(p) {
    var n = String(p || "").toLowerCase()
    return !(n && name && (n === name || n.indexOf(name) >= 0 || name.indexOf(n) >= 0))
  })
  return others.length > 0 ? { sound: "phone", kept: true, playing: others[0] } : { sound: soundPlace(chosen), kept: false }
}

// The screen's own window: its last choice, else here, as it always was.
function screenSound(remembered) {
  return SOUND_PLACES.indexOf(remembered) >= 0 ? remembered : "here"
}

// What a device can do with a window's sound, from its screen status
// (`sdk`: Android's API level, 0 when not read): the reason a place cannot
// be offered, "" when it can.
function soundLimits(status) {
  var sdk = Number((status || {}).sdk) || 0
  return {
    here: sdk > 0 && sdk < 30 ? "Needs Android 11" : "",
    phone: "",
    both: sdk > 0 && sdk < 33 ? "Needs Android 13" : ""
  }
}

// The card a window's sound is chosen on, while that window is open.
// `target`: { label: the app's name, "" for the screen }; `sound`: where
// it plays now; `stream`: its sound here, as read ({ found, volume, muted,
// output }), or null while read; `status`: the device's screen status.
function windowSoundCard(target, sound, stream, deviceName, status) {
  var device = String(deviceName || "the device")
  var label = target && target.label ? String(target.label) : ""
  var limits = soundLimits(status)
  var place = soundPlace(sound)
  var hints = {
    here: "Here only: " + device + " goes quiet while it plays here",
    phone: "Its sound stays on " + device,
    both: "Here and on " + device + " (an app can keep its sound to itself)"
  }
  var labels = { here: "Here", phone: "On " + device, both: "Both" }
  var glyphs = { here: GLYPH.volume, phone: GLYPH.phone, both: GLYPH.devices }
  var options = SOUND_PLACES.map(function(k) {
    return { key: k, label: labels[k], glyph: glyphs[k], selected: k === place, enabled: limits[k] === "",
             hint: limits[k] || hints[k] }
  })
  var s = stream || null
  var playsHere = place !== "phone"
  var found = !!s && s.found === true
  return {
    title: label ? label + "'s sound" : device + "'s screen: its sound",
    options: options,
    line: hints[place],
    note: "Changing it opens the window again, in its place",
    // Its volume here, while its sound plays here and the stream is found.
    volume: playsHere && found,
    level: found ? Math.max(0, Math.min(1, Number(s.volume) || 0)) : 0,
    muted: found && s.muted === true,
    output: !playsHere ? "" : found ? (s.output ? "Plays on " + s.output : "") : (s ? "Its sound is not playing here yet" : "")
  }
}

// A window's title: the screen's (`Pixel 8 · Screen`), or an app's
// (`Maps · Pixel 8`), as the bridge names them (screen_title).
function windowTitle(name, label) {
  return label ? String(label) + " · " + String(name || "Device") : screenTitle(name)
}

// The apps with their window, when it is open here: `open` and where its
// sound plays (`sound`), for the tile's badge. `openLabels`: the open
// windows' labels (app names, label -> true); `sounds`: where each open one
// plays (package -> place), else `fallback`.
function withWindows(apps, openLabels, sounds, fallback) {
  var open = openLabels || {}
  return (apps || []).map(function(a) {
    if (open[a.name] !== true) return a
    var out = Object.assign({}, a)
    out.open = true
    out.sound = soundPlace((sounds || {})[a.package] || fallback)
    return out
  })
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
  dev.can = { ring: true, clipboard: true, share: true, sms: true, contacts: true, media: true, notifications: true, ping: true }
  dev.network = { type: "5G", strength: 3 }
  // Two, so the panel's other sections have room: a text message (reply,
  // its own buttons, a long text) and a group chat (who said what).
  dev.notifications = [
    { id: "demo-4", key: "k4", app: "Messages", title: "Alex Rivera", text: "Running ten minutes late, traffic on the bridge is terrible. Start without me if everyone is there, and save me a slice! Also, could you put the folding chairs by the door so I can grab them on the way in?", ticker: "", dismissable: true, replyId: "r4", actions: ["Mark as read", "Reply"], icon: "", silent: false },
    { id: "demo-5", key: "0|com.example.whatsapp|5|null|10005", app: "WhatsApp", title: "Book club (3 messages)", text: "Sam Park: Chapter nine is a lot\nMaya Chen: No spoilers!\nMaya Chen: Thursday at 7 still works?", ticker: "", dismissable: true, replyId: "r5", actions: ["Mark as read", "Mute"], icon: "", silent: false,
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
    if (isHiddenSummary(n)) continue
    out.push(n)
  }
  return out
}

// Android hides a player left paused this long (AOSP's MediaTimeoutListener):
// so does the panel (KDE Connect #35, our #33).
var PLAYER_HIDE_MS = 10 * 60 * 1000
function playerHidden(pausedSinceMs, nowMs) {
  return !!pausedSinceMs && nowMs - pausedSinceMs >= PLAYER_HIDE_MS
}

// One UI's own "1 more notification" (KDE Connect #51, our #52): a System
// UI summary the phone's shade never shows. Nothing marks it but its shape:
// from System UI, no text, no action, no reply, a count in its title.
function isHiddenSummary(n) {
  var app = String(n.app || "").trim().toLowerCase()
  var fromSystemUi = app === "system ui" || notificationPackage(n) === "com.android.systemui"
  if (!fromSystemUi) return false
  if (String(n.text || "").trim() !== "" || (n.actions || []).length > 0 || n.replyId) return false
  return /\d/.test(String(n.title || n.ticker || ""))
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


// ---- Contacts: the device's own, as KDE Connect syncs them ----------------
//
// The cards come from the bridge (`kdeconnect-bridge contacts`), which reads
// the vCards KDE Connect writes. Nothing is stored here and nothing is
// edited: the device is the truth, and a change is made on the device or in
// Omarchy's own contacts app.

// The device is asked for its contacts again at most this often (a panel
// opening on the page), and the cards on disk are read again this often
// while the page is open.
var CONTACTS_SYNC_MS = 5 * 60000
var CONTACTS_READ_MS = 10000

function contactTitle(contact) {
  var name = contact ? String(contact.name || "").trim() : ""
  return name !== "" ? name : "No name"
}

// The line under a contact's name in the list: what else says who they are,
// shortest first: their first number, else an email, else where they work.
function contactLine(contact) {
  var c = contact || {}
  var phones = c.phones || [], emails = c.emails || []
  if (phones.length > 0) return formatNumber(phones[0].value)
  if (emails.length > 0) return String(emails[0].value || "")
  return [c.title, c.org].filter(function(t) { return !!t }).join(" · ")
}

// What a search matches: every word of a name, a nickname, where they work,
// an email, and a number by its digits (as typed, anywhere in the number).
function contactMatches(contact, query, digits) {
  var c = contact || {}
  var q = String(query || "").trim().toLowerCase()
  if (q === "") return true
  var text = [c.name, c.nickname, c.org, c.title, c.note].concat(
    (c.emails || []).map(function(e) { return e.value }),
    (c.addresses || []).map(function(a) { return a.value })).join(" ").toLowerCase()
  if (text.indexOf(q) >= 0) return true
  var d = digits === undefined ? q.replace(/\D/g, "") : String(digits)
  if (d.length >= 2) {
    var numbers = (c.phones || []).map(function(p) { return String(p.value || "").replace(/\D/g, "") }).join(" ")
    if (numbers.indexOf(d) >= 0) return true
  }
  return false
}

// The list as the page draws it: the contacts a search leaves, in the order
// they came (the bridge sorts by name), each row knowing the letter it falls
// under and whether it is the first of that letter.
function contactRows(contacts, query) {
  var q = String(query || "").trim().toLowerCase()
  var digits = q.replace(/\D/g, "")
  var list = contacts || []
  var out = []
  for (var i = 0; i < list.length; i++) {
    var c = list[i]
    if (!contactMatches(c, q, digits)) continue
    var title = contactTitle(c)
    // A card with no name falls under "#", with the numbers, not under "N".
    var letter = avatarInitial(String(c.name || "").trim())
    out.push({ id: String(c.id), name: title, line: contactLine(c), initial: letter,
               photo: String(c.photo || ""), letter: letter,
               first: out.length === 0 || out[out.length - 1].letter !== letter })
  }
  return out
}

function contactById(contacts, id) {
  var list = contacts || []
  for (var i = 0; i < list.length; i++) if (String(list[i].id) === String(id)) return list[i]
  return null
}

// "1990-05-02", "19900502" and "--05-02" (no year) as a date to read.
function birthdayText(value) {
  var v = String(value || "").trim()
  var m = /^(\d{4}|-{2})-?(\d{2})-?(\d{2})$/.exec(v)
  if (!m) return v
  var month = MONTHS[Number(m[2]) - 1]
  if (!month) return v
  var day = Number(m[3])
  return month + " " + day + (m[1] === "--" ? "" : ", " + m[1])
}

// A contact's card, one row per detail, in the order the page shows them:
// where they work, then every number, email, address and website the device
// has, then a birthday and a note. `actions` are what a row offers, the first
// being what Enter does: a detail opens where it belongs (a text, the mail
// app, the map, the browser) and anything else is copied.
function contactDetails(contact) {
  var c = contact || {}
  var rows = []
  var work = [c.title, c.org].filter(function(t) { return !!t }).join(" · ")
  if (work !== "") rows.push({ kind: "org", glyph: GLYPH.bank, label: "Work", value: work, raw: work, actions: ["copy"] })
  ;(c.phones || []).forEach(function(p) {
    rows.push({ kind: "phone", glyph: GLYPH.callBack, label: p.label || "Phone",
                value: formatNumber(p.value), raw: String(p.value || ""), actions: ["message", "call", "copy"] })
  })
  ;(c.emails || []).forEach(function(e) {
    rows.push({ kind: "email", glyph: GLYPH.mail, label: e.label || "Email",
                value: String(e.value || ""), raw: String(e.value || ""), actions: ["mail", "copy"] })
  })
  ;(c.addresses || []).forEach(function(a) {
    rows.push({ kind: "address", glyph: GLYPH.place, label: a.label || "Address",
                value: String(a.value || ""), raw: String(a.value || ""), actions: ["map", "copy"] })
  })
  ;(c.websites || []).forEach(function(w) {
    rows.push({ kind: "website", glyph: GLYPH.web, label: w.label || "Website",
                value: String(w.value || "").replace(/^https?:\/\//i, "").replace(/\/$/, ""),
                raw: String(w.value || ""), actions: ["web", "copy"] })
  })
  if (c.birthday) rows.push({ kind: "birthday", glyph: GLYPH.calendar, label: "Birthday",
                              value: birthdayText(c.birthday), raw: birthdayText(c.birthday), actions: ["copy"] })
  if (c.note) rows.push({ kind: "note", glyph: GLYPH.notes, label: "Note",
                          value: String(c.note), raw: String(c.note), actions: ["copy"] })
  return rows
}

// This computer's contacts app (Omarchy's web app, `{ name, url, find }`)
// holds the contacts of the one account it belongs to: Google Contacts has
// those the phone syncs with Google, never those kept on the phone only
// (`stored` "phone", from Android's lookup key) or in another account. The
// cards tell only which ones are on the phone only, so that is what is said.
function contactsAppHint(app, contacts) {
  var name = app && app.name ? String(app.name) : ""
  if (name === "") return ""
  var list = contacts || []
  var phoneOnly = 0
  for (var i = 0; i < list.length; i++) if (list[i] && list[i].stored === "phone") phoneOnly++
  if (phoneOnly > 0 && phoneOnly === list.length) return "Open " + name + ": these contacts are on the phone only, not there"
  if (phoneOnly > 0) return "Open " + name + ": its account's contacts, not the " + phoneOnly + " on the phone only"
  return "Open " + name + ": its account's contacts"
}

// One person in that app: its search for the name, where the app has one
// known and the card is synced with an account. A card on the phone only
// cannot be there, so it says that instead.
function contactFind(app, contact) {
  var name = contact ? String(contact.name || "").trim() : ""
  if (!contact) return { label: "", note: "" }
  if (contact.stored === "phone") return { label: "", note: "On the phone only" }
  if (name === "" || !app || !app.find) return { label: "", note: "" }
  return { label: "Find in " + String(app.name), note: "" }
}

// What the page says when it has nothing to show: the device decides whether
// contacts leave it at all, so an empty page points at that, never at a
// fault here.
function contactsEmpty(state, query, device) {
  if (String(query || "").trim() !== "") return "No contact matches."
  if (state === "away") return deviceLabel(device) + " is away. Its contacts show when it comes back."
  return "No contacts yet. Allow contacts in KDE Connect on " + deviceLabel(device) + " and they appear here."
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

// ---- This computer: its checks (the page of that name, scope "connection") ----

// The doctor's checks that are about this computer (the This computer
// page); its paired and connected checks are the devices' own pages'
// business, and so is anything a device must do (Wireless debugging, a
// permission): a problem shows once, where its cause is.
var COMPUTER_CHECKS = ["installed", "running", "firewall", "network", "screen", "sshfs"]
// Short names: the status beside each says the rest ("Running", "Closed").
// One row per thing on this computer, named after it: a service's checks
// (KDE Connect: installed, running) become one row that says which state it
// is in, so other services (Bluetooth, scrcpy) can each have theirs.
var CHECK_NAMES = { kdeconnect: "KDE Connect", firewall: "Firewall", network: "Network", screen: "Screen tools", sshfs: "Gallery tools" }

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

// The This computer row's pills: what this computer has, one per thing.
// "on" works; "off" is an optional package not installed (more can be
// done, nothing is wrong); "fail" is a required check failing, the only
// state that lights the gear's dot (an ignored one reads "off"). Whether
// a device's screen is set up is that device's business, not a pill here.
function connectionPills(checks, ignored) {
  var skip = ignored || []
  return computerChecks(checks).map(function(c) {
    var state = c.ok ? "on" : (c.optional || skip.indexOf(c.key) >= 0 ? "off" : "fail")
    return { key: c.key, label: CHECK_NAMES[c.key] || c.label, state: state }
  })
}

// One line under the pills, or in their place in a tooltip: what is to fix,
// else how much more can be set up, else that everything is on.
function connectionSummary(checks, ignored) {
  var list = computerChecks(checks)
  if (list.length === 0) return "Checking…"
  var n = connectionIssues(checks, ignored)
  if (n > 0) return n === 1 ? "1 to fix" : n + " to fix"
  var off = connectionPills(checks, ignored).filter(function(p) { return p.state === "off" }).length
  return off === 0 ? "Everything on" : (off === 1 ? "1 more to set up" : off + " more to set up")
}

// The This computer page's rows, in one list for the keyboard: this computer's
// checks (status icon, name, short status, one action; a failing one can be
// ignored). It checks what exists; Add a device (addDeviceRows) makes a new
// pairing.
function connectionRows(checks, ignored) {
  var skip = ignored || []
  return computerChecks(checks).map(function(c) {
    var row = { kind: "check", key: c.key, ok: !!c.ok, optional: !!c.optional, ignored: !c.ok && !c.optional && skip.indexOf(c.key) >= 0,
             label: CHECK_NAMES[c.key] || c.label, status: c.status || (c.ok ? "OK" : ""), detail: c.ok ? "" : String(c.detail || ""),
             fix: String(c.fix || ""), fixLabel: String(c.fixLabel || "Fix") }
    // Installed is all this computer does for it: a device's own steps are
    // on that device's page.
    if (c.ok && (c.key === "screen" || c.key === "sshfs")) Object.assign(row, { status: "Installed", fix: "" })
    return row
  })
}

// The Add a device page's rows: devices asking to pair, then devices in
// reach to pair with (`devices`: devicesListRows).
function addDeviceRows(devices) {
  var rows = []
  ;(devices || []).forEach(function(r) { if (r.kind === "request") rows.push(r) })
  ;(devices || []).forEach(function(r) { if (r.kind === "available") rows.push(r) })
  return rows
}

// ---- What a device can do (docs/design/setup.md, #128) ----
// Three layers, read from the bridge's reports and never set by hand:
//  - gateways: how the plugin gets something from a device (KDE Connect,
//    Android's permissions, the storage link, the screen link);
//  - setup items: what a gateway needs, each checked once, where it lives
//    (this computer or the device), with its remedies;
//  - features: what the user gets, from the items they need. One item can
//    serve several features (notification access); one feature can need
//    several gateways (Gallery: KDE Connect and the storage link).
// Everything reads them: the device page's rows, the status, the gear dot,
// the main page's line, Fix all.

var GATEWAYS = [
  { key: "kdeconnect", label: "KDE Connect", hint: "Its link to this computer, and KDE Connect's parts for it" },
  { key: "android", label: "Android permissions", hint: "What KDE Connect may do on the device" },
  { key: "storage", label: "Storage link", hint: "Its storage, mounted here (KDE Connect's sftp, sshfs)" },
  { key: "screen", label: "Screen link", hint: "adb to the device, and scrcpy here" },
  { key: "bluetooth", label: "Bluetooth", planned: true, hint: "For calls with their audio here (#59)" }
]

var PERMISSION_NAMES = { notifications: "notification access", sms: "SMS", contacts: "contacts", phone: "phone and call log", storage: "all files access" }

// needs: the setup items it uses; switch: the items its switch turns off,
// only its own (a shared one, such as notification access, never).
var FEATURES = [
  { key: "notifications", label: "Notifications", glyph: GLYPH.bell, hint: "Its notifications here, with reply",
    needs: ["link", "plugin:notifications", "permission:notifications", "health:notifications"], switch: ["plugin:notifications"] },
  { key: "messages", label: "Messages", glyph: GLYPH.messages, hint: "Every conversation, read and send",
    needs: ["link", "plugin:sms", "permission:sms"], switch: ["plugin:sms"] },
  { key: "names", label: "Contacts", glyph: GLYPH.contacts, hint: "Its contacts here, and names for numbers",
    needs: ["link", "plugin:contacts", "permission:contacts"], switch: ["plugin:contacts"] },
  { key: "media", label: "Now playing", glyph: GLYPH.music, hint: "What it plays, with controls",
    needs: ["link", "plugin:mprisremote", "permission:notifications"], switch: ["plugin:mprisremote"] },
  { key: "calls", label: "Calls", glyph: GLYPH.callRing, hint: "Who is calling, and missed calls",
    needs: ["link", "plugin:telephony", "permission:phone"], switch: ["plugin:telephony"] },
  { key: "gallery", label: "Gallery", glyph: GLYPH.picture, hint: "Its newest photos and videos",
    needs: ["link", "plugin:sftp", "package:sshfs", "permission:storage", "health:mount"], switch: ["plugin:sftp"] },
  { key: "share", label: "Files", glyph: GLYPH.sendFile, hint: "Send files both ways", needs: ["link", "plugin:share"], switch: ["plugin:share"] },
  { key: "clipboard", label: "Clipboard", glyph: GLYPH.clipboard, hint: "Shared clipboard", needs: ["link", "plugin:clipboard"], switch: ["plugin:clipboard"] },
  { key: "ring", label: "Ring", glyph: GLYPH.ring, hint: "Ring it, even on silent", needs: ["link", "plugin:findmyphone"], switch: ["plugin:findmyphone"] },
  { key: "battery", label: "Battery", glyph: GLYPH.bolt, hint: "Its battery in the bar", needs: ["link", "plugin:battery"], switch: ["plugin:battery"] },
  { key: "screen", label: "Screen and apps", glyph: GLYPH.screen, hint: "Its screen and apps in windows here",
    needs: ["own:screen", "package:screen", "screen"], switch: ["own:screen"] }
]

// One word for each state, everywhere.
var FEATURE_STATES = { on: "On", setup: "Set up", attention: "Needs attention", off: "Turned off", unavailable: "Not on this device", away: "Away" }

// A setup item: { key, gateway, scope: "computer" | "device", label, state,
// detail, steps }. state: "ok", "missing" (to set up), "broken" (it worked
// and stopped: a problem), "off" (a switch turned it off), "unavailable"
// (the device does not offer it), "unknown" (being read), "away".
// A step: { kind, label, fix, orAsk, fallback, page }. kind: "auto" (the
// plugin does it: fix is { verb, what, arg } for the service, `fix <what>`
// or `device-fix <what> <device> <arg>`; a package's asks for the password
// after its card) or "ask" (only the user can; `page` is where: "screen",
// its Screen and apps page). `fallback`: runs only when the step before it
// failed. `item`: the item it is for.
//
// `ctx`: { report: the bridge's `features <device>` (null while read),
// screen: { state, line } from `screen <device>` (null while read), checks:
// this computer's (`doctor`), name: the device's, own: { screenFeature } }.
function setupItem(key, ctx) {
  var report = ctx.report, name = ctx.name || "the device"
  var parts = key.split(":"), kind = parts[0], what = parts[1] || ""
  var item = { key: key, scope: "device", label: "", state: "ok", detail: "", steps: [] }
  function is(state, detail) { item.state = state; item.detail = detail || ""; return item }
  // The screen link is Android's (adb): another device never offers it, so
  // nothing about it shows there.
  if ((key === "own:screen" || key === "screen" || key === "package:screen") && !isAndroid(report)) {
    item.gateway = "screen"; item.label = "the screen link"
    return is("unavailable", name + " is not Android")
  }
  function check(k) { return (ctx.checks || []).filter(function(c) { return c.key === k })[0] || null }
  // The screen link reaches the device now (adb), whatever KDE Connect says.
  var adbHere = !!ctx.screen && ctx.screen.state === "ready"
  // KDE Connect's link: everything it carries waits on it. Lost while the
  // screen link still reaches the device, it is not away: KDE Connect is.
  function linked() {
    if (!report) return is("unknown", "Looking…")
    if (!report.reachable) return is(adbHere ? "unknown" : "away", "When " + name + " connects")
    return null
  }
  if (kind === "link") {
    item.gateway = "kdeconnect"; item.label = "the link to " + name
    if (report && !report.reachable && adbHere) {
      // adb knows where it is: KDE Connect pointed there; else KDE Connect
      // on the device let run in the background and opened.
      item.steps.push({ kind: "auto", label: "Point KDE Connect at " + name + "'s address on this network", fix: { verb: "device", what: "reconnect" } })
      item.steps.push({ kind: "auto", label: "Let KDE Connect run on " + name + " and open it", fix: { verb: "device", what: "wake" }, fallback: true })
      return is("broken", "KDE Connect lost " + name + "; its screen link still reaches it")
    }
    return linked() || is("ok", (report.links || []).join(", "))
  }
  if (kind === "plugin") {
    item.gateway = "kdeconnect"; item.label = "KDE Connect's " + what + " part"
    if (!report || !report.reachable) return linked()
    var p = (report.plugins || {})[what]
    if (!p || p.offered === false) return is("unavailable", name + " does not offer it")
    if (p.on === false) {
      item.steps.push({ kind: "auto", label: "Turn it on for " + name, fix: { verb: "device", what: "plugin", arg: what + "=on" } })
      return is("off", "")
    }
    return is("ok")
  }
  if (kind === "permission") {
    item.gateway = "android"; item.label = PERMISSION_NAMES[what]
    if (!report || !report.reachable) return linked()
    // Read over adb: unknown without it, and nothing to say then.
    if (!report.permissions || report.permissions[what] !== false) return is("ok")
    // Granted over adb on a click; else the switch to turn on, on the device.
    item.steps.push({ kind: "auto", label: "Allow " + PERMISSION_NAMES[what] + " for KDE Connect on " + name, fix: { verb: "device", what: "grant", arg: what },
                      orAsk: "On " + name + ": KDE Connect › Permissions › " + PERMISSION_NAMES[what] })
    return is("missing", "Needs " + PERMISSION_NAMES[what])
  }
  if (key === "health:notifications") {
    // None here while the device holds several (read over adb): KDE
    // Connect's listener went quiet (#94, our #95). Read again, then its
    // listener bound again on the device; else the device's restart.
    item.gateway = "kdeconnect"; item.label = "notifications arriving"
    if (!report || !report.reachable) return linked()
    var counts = report.notifications
    if (!(counts && counts.here === 0 && counts.device !== null && counts.device >= 3)) return is("ok")
    item.steps.push({ kind: "auto", label: "Read its notifications again", fix: { verb: "device", what: "renotify" } })
    item.steps.push({ kind: "auto", label: "Make KDE Connect listen again on " + name, fix: { verb: "device", what: "relisten" },
                      orAsk: "Restart " + name + ": KDE Connect stopped sending its notifications" })
    return is("broken", name + " has " + counts.device + " notifications; none arrive here")
  }
  if (key === "health:mount") {
    item.gateway = "storage"; item.label = "its storage mounted"
    if (!report || !report.reachable) return linked()
    if (!(report.files && report.files.mounted === false && report.files.error)) return is("ok")
    item.steps.push({ kind: "auto", label: "Mount its storage again", fix: { verb: "device", what: "remount" } })
    item.steps.push({ kind: "auto", label: "Restart KDE Connect", fix: { verb: "fix", what: "restart" }, fallback: true })
    return is("broken", "Its storage did not mount: " + report.files.error)
  }
  if (kind === "package") {
    // This computer's: it shows there, with its fix; here, where it is.
    item.scope = "computer"
    item.gateway = what === "sshfs" ? "storage" : "screen"
    item.label = (what === "sshfs" ? "sshfs" : "scrcpy and adb") + " on this computer"
    var c = check(what)
    var missing = c ? !c.ok : (what === "sshfs" ? !!(report && report.files && report.files.sshfs === false) : !!(ctx.screen && ctx.screen.state === "tools"))
    if (!missing) return is("ok")
    // Installed from wherever it is asked (the feature's own click, or This
    // computer): its card says what for first; it is the same item either way.
    item.steps.push({ kind: "auto", label: "Install " + item.label + " (asks for your password)", fix: { verb: "fix", what: what } })
    return is("missing", "Needs " + item.label)
  }
  if (key === "own:screen") {
    item.gateway = "screen"; item.label = "Screen and apps turned on"
    return ctx.own && ctx.own.screenFeature === false ? is("off", "") : is("ok")
  }
  if (key === "screen") {
    item.gateway = "screen"; item.label = "the screen link"
    var st = ctx.screen ? ctx.screen.state : "checking"
    var line = ctx.screen ? ctx.screen.line || "" : ""
    if (st === "checking") return is("unknown", "Looking…")
    if (st === "ready") return is("ok", line)
    if (st === "tools") return is("ok")   // package:screen says it
    item.steps.push({ kind: "ask", label: line || "Set up on its page", page: "screen" })
    // Set up once and lost (Wireless debugging off after a restart, adb not
    // reaching it): a problem. Never set up: to set up.
    return is(st === "off" || st === "away" ? "broken" : "missing", line)
  }
  return is("unknown", "")
}

// Android, or another kind (an iPhone, a computer): KDE Connect on Android
// offers its texts, calls or storage; nothing else does. Not read yet:
// Android, the common case, until the report says otherwise.
function isAndroid(report) {
  if (!report || !report.plugins || Object.keys(report.plugins).length === 0) return true
  return ["sms", "telephony", "sftp"].some(function(k) { return !!report.plugins[k] && report.plugins[k].offered !== false })
}

// Every item a device's features need, once each.
function setupItems(ctx) {
  var keys = []
  FEATURES.forEach(function(f) { f.needs.forEach(function(k) { if (keys.indexOf(k) < 0) keys.push(k) }) })
  // Each step knows its item: a wait on the user's step ends when that item
  // is done, and the rest then runs by itself.
  return keys.map(function(k) {
    var it = setupItem(k, ctx)
    it.steps.forEach(function(st) { st.item = k })
    return it
  })
}

// A feature's row, from its items: { key, label, glyph, hint, state,
// stateLabel, detail, steps, switchable, on, gateways, needs }. Worked
// out the same way for every feature: away > being read > not on this
// device > turned off > needs attention > to set up > on.
function featureState(f, items, ctx) {
  var by = {}
  items.forEach(function(it) { by[it.key] = it })
  var mine = f.needs.map(function(k) { return by[k] })
  var row = { key: f.key, label: f.label, glyph: f.glyph, hint: f.hint, steps: [], detail: "", on: true,
              switchable: f.switch.length > 0, needs: f.needs.slice(),
              gateways: mine.map(function(it) { return it.gateway }).filter(function(g, i, a) { return g && a.indexOf(g) === i }) }
  function done(state, detail) { row.state = state; row.stateLabel = FEATURE_STATES[state]; row.detail = detail || ""; return row }
  function first(state) { return mine.filter(function(it) { return it.state === state }) }
  var away = first("away")
  if (away.length > 0) return done("away", away[0].detail)
  // Being read: the link (or the screen's) only; an item not read yet
  // elsewhere says nothing.
  var reading = first("unknown").filter(function(it) { return it.key === "link" || it.key === "screen" })
  var off = mine.filter(function(it) { return it.state === "off" && f.switch.indexOf(it.key) >= 0 })
  if (off.length > 0) {
    row.on = false
    off.forEach(function(it) { row.steps = row.steps.concat(it.steps) })
    return done("off", "")
  }
  if (reading.length > 0) return done("setup", "Looking…")
  var unavailable = first("unavailable")
  if (unavailable.length > 0) { row.switchable = false; return done("unavailable", unavailable[0].detail) }
  // This computer's first (one password for its packages), then the
  // device's; a broken item after what it needs (sshfs before a remount).
  var missing = first("missing").sort(function(a, b) { return (a.scope === "computer" ? 0 : 1) - (b.scope === "computer" ? 0 : 1) })
  var broken = first("broken")
  if (broken.length > 0) {
    missing.concat(broken).forEach(function(it) { row.steps = row.steps.concat(it.steps) })
    return done("attention", broken[0].detail)
  }
  if (missing.length > 0) {
    missing.forEach(function(it) { row.steps = row.steps.concat(it.steps) })
    var screen = missing.filter(function(it) { return it.key === "screen" })[0]
    return done("setup", screen ? screen.detail : "Needs " + missing.map(function(it) { return it.label }).join(" and "))
  }
  return done("on", f.key === "screen" && by.screen ? by.screen.detail : "")
}

// A device's setup: its items, its features from them, and its gateways
// (each with its items and the features that use it).
function deviceSetup(ctx) {
  var items = setupItems(ctx)
  var features = FEATURES.map(function(f) { return featureState(f, items, ctx) })
  var gateways = GATEWAYS.map(function(g) {
    var its = items.filter(function(it) { return it.gateway === g.key })
    return { key: g.key, label: g.label, hint: g.hint, planned: !!g.planned, items: its,
             usedBy: FEATURES.filter(function(f) { return f.needs.some(function(k) { return its.some(function(it) { return it.key === k }) }) })
               .map(function(f) { return f.key }) }
  })
  return { items: items, features: features, gateways: gateways }
}

function featureRows(report, screen, deviceName, checks, own) {
  return deviceSetup({ report: report, screen: screen, name: deviceName, checks: checks || [], own: own || {} }).features
}

// The steps one click runs for a feature (Turn on, Fix): every one the
// plugin can do, in order, up to the first only the user can do.
function featurePlan(row) {
  var out = []
  for (var i = 0; i < (row.steps || []).length; i++) {
    var s = row.steps[i]
    if (s.kind !== "auto") break
    out.push(s)
  }
  return out
}

// Fix all on a device: every feature's automatic steps, each once, this
// computer's installs first (one password card for them all). A feature
// turned off stays off: its own switch turns it on.
function fixAllPlan(rows) {
  var seen = {}, installs = [], rest = []
  ;(rows || []).forEach(function(r) {
    if (r.state === "on" || r.state === "unavailable" || r.state === "away" || r.state === "off") return
    featurePlan(r).forEach(function(s) {
      var id = s.fix.verb + ":" + s.fix.what + ":" + (s.fix.arg || "")
      if (seen[id]) return
      seen[id] = true
      ;(s.fix.verb === "fix" && s.fix.what !== "restart" ? installs : rest).push(s)
    })
  })
  return installs.concat(rest)
}

// What it shares, folded: everything, or what is off.
function sharesSummary(rows) {
  var off = (rows || []).filter(function(r) { return r.on === false }).map(function(r) { return r.label })
  if (off.length === 0) return "Everything"
  return off.length > 2 ? "All but " + off.length : "All but " + off.join(" and ")
}

// One line for a device's features: what is on, and what is left.
function featuresSummary(rows) {
  var on = (rows || []).filter(function(r) { return r.state === "on" }).length
  var attention = (rows || []).filter(function(r) { return r.state === "attention" }).length
  var setup = (rows || []).filter(function(r) { return r.state === "setup" }).length
  var parts = [on + " on"]
  if (attention > 0) parts.push(attention + " " + (attention === 1 ? "needs" : "need") + " attention")
  if (setup > 0) parts.push(setup + " to set up")
  return parts.join(" · ")
}

// Demo: a made-up device's report, with one feature to set up and one off;
// `kind` "ask" leaves notification access to allow, "stopped" its
// notifications stopped arriving.
function demoFeatures(kind) {
  var plugins = {}
  ;["notifications", "sms", "contacts", "mprisremote", "telephony", "sftp", "share", "clipboard", "findmyphone", "battery", "ping"].forEach(function(k) {
    plugins[k] = { on: k !== "clipboard", offered: true, loaded: k !== "clipboard" }
  })
  return { reachable: true, paired: true, links: ["LAN"], plugins: plugins,
           permissions: { notifications: kind !== "ask", sms: true, contacts: false, phone: true, storage: true },
           files: { sshfs: true, mounted: true, error: "" },
           notifications: kind === "stopped" ? { here: 0, device: 5 } : { here: null, device: null } }
}

// ---- Screen and apps: scrcpy over adb (kdeconnect-bridge screen) ----

// The Screen and apps page for one device: a line on where it stands, the
// steps (each done or not; the first not done is the current one), and the
// page's actions, which are also its keyboard rows. `status`: the bridge's
// (`screen <device>`), null while it is read; `pairing`: the QR pairing on
// this page ({ phase, qr, message }), or null.
function screenSetup(status, device, pairing, docked, fitTile, waiting, appSound) {
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
      : "Wireless debugging is off on " + name + ": it turns off when " + name + " restarts",
    unauthorized: "On " + name + ", allow USB debugging (tick Always allow from this computer)",
    away: name + " is away: on this Wi-Fi with Wireless debugging on, or on a USB cable"
      + (waiting ? "; the screen opens as soon as it is back" : ""),
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
  // Only off again (a restart): set up already, one step missing, so the
  // page shows that step alone (`only`), and pairing again is not offered.
  var onlyStep = state === "off" && !seen
  if (state === "pair" || (state === "off" && !onlyStep) || state === "away") {
    if (phase === "" || phase === "error") actions.push({ key: "pair", label: state === "pair" ? "Show the code" : "Pair again", hint: "A QR code for " + name + " to scan" })
    else actions.push({ key: "stopPair", label: "Stop", hint: "" })
  }
  if (state !== "ready" && state !== "tools" && state !== "checking") actions.push({ key: "check", label: "Check again", hint: "" })
  if (ready) {
    // Three kinds of control, each drawn as what it is: the screen itself
    // (a tile, as its shortcut), where it opens (one of two), and a switch.
    actions.push({ key: "open", label: "Screen", hint: "Use it with your mouse: right-click is Back" })
    actions.push({ key: "place", label: "Opens", docked: docked !== false,
                   hint: docked !== false ? "Under its icon, on top, on every workspace" : "Tiles, moves and resizes like any other window",
                   keys: screenKeyLines(s.keys, docked !== false) })
    if (docked === false)
      actions.push({ key: "fitTile", label: "Fit its tile to it (experimental)", on: fitTile === true,
                     hint: "Beside another window, its tile takes " + name + "'s width" })
    // Its apps (a window each, #116): where their sound plays when they
    // open; an open window changes its own (#129), and an app keeps its
    // last choice.
    if (s.apps) {
      var sound = soundPlace(appSound)
      var limits = soundLimits(s)
      actions.push({ key: "appSound", label: "An app's sound", sound: sound, device: name, limits: limits,
                     hint: { here: "Its sound plays here, and " + name + " goes quiet meanwhile",
                             phone: "Its sound stays on " + name,
                             both: "Its sound plays here and on " + name }[sound]
                       + ". An open app's tile changes its own, and the app keeps it." })
    }
  }
  return {
    state: state, line: line, steps: onlyStep ? [] : steps, pairingNote: pairingNote,
    only: onlyStep ? "Turn it on: Developer options › Wireless debugging" : "",
    waitingNote: waiting && (state === "off" || state === "away") ? "Opens as soon as it is on" : "",
    showQr: !!(pairing && pairing.qr && (phase === "qr" || phase === "found")),
    usbNote: state === "pair" || state === "away" ? "No Wi-Fi debugging (Android 10 and older)? Turn on USB debugging in Developer options and plug it in." : "",
    // Off again after a restart: one tap next time.
    quickTip: state === "off" && !seen ? "Next time in one tap: Developer options › Quick settings developer tiles › Wireless debugging, then pull down Quick settings" : "",
    waiting: !!waiting && (state === "off" || state === "away"),
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

// The screen's window title (the bridge's screen_title): how the panel
// knows the window is open, from Hyprland's own list of windows.
function screenTitle(name) {
  return String(name || "Device") + " · Screen"
}

// One tip while the screen connects (the card waits a second or two each
// time): a different one each opening, so they teach a little at a time.
// All true of scrcpy as it opens here (its Alt shortcuts: Super belongs to
// Hyprland) and of the docked window.
var SCREEN_TIPS = [
  "Right-click is Back, middle-click is Home",
  "Free it ({pop}), then full screen ({fullscreen})",
  "Turn your phone: the window turns with it",
  "Drop a file on it to copy it to the phone's Downloads",
  "Copy on the phone, paste here: the clipboard comes across",
  "Alt+O turns the phone's own screen off; this one stays on",
  "Move it anywhere: it stays where you put it, even turned",
  "Alt+N opens the phone's notifications",
  "Rather a window like any other? Settings › Screen and apps"
]
// How long a tip stays up at least, so it can be read: about a second and
// a little more per letter, never more than 2.2 s (a phone that takes longer
// to connect adds nothing).
function tipReadMs(text) {
  return Math.min(2200, 1000 + 20 * String(text || "").length)
}
// The n-th tip, with this machine's own keys ({pop}, {fullscreen}): an
// action with no key here reads "no shortcut", as on the page.
function screenTip(n, keys) {
  var k = keys || {}
  var i = ((Math.floor(n) % SCREEN_TIPS.length) + SCREEN_TIPS.length) % SCREEN_TIPS.length
  return SCREEN_TIPS[i].replace("{pop}", keyText(k.pop)).replace("{fullscreen}", keyText(k.fullscreen))
}

// How to free the docked screen and dock it back, and full screen, with
// this machine's own keys (the bridge reads them from Hyprland: Omarchy's
// pop-out toggle, Super+O by default, and its full screen, Super+F). An
// action with no key here says so (keys null: "no shortcut"), never a key
// that does nothing.
var NO_SHORTCUT = "no shortcut"
function screenKeyLines(keys, docked) {
  var k = keys || {}
  if (!docked) return [{ keys: k.fullscreen || null, text: "Full screen" }]
  return [{ keys: k.pop || null, text: "Frees it from the bar" },
          { keys: k.fullscreen || null, text: "Full screen, once freed" },
          { keys: k.pop || null, text: "Again: back under the bar" }]
}
// A key as a tip tells it: "Super+O", else "no shortcut".
function keyText(keys) {
  return keys && keys.length ? keys.join("+") : NO_SHORTCUT
}

// The page's keyboard rows: one per action, in order.
function screenRows(setup) {
  return (setup ? setup.actions : []).map(function(a) {
    var row = { kind: "screenAction", key: a.key, label: a.label, hint: a.hint }
    if (a.on !== undefined) row.on = a.on
    if (a.docked !== undefined) row.docked = a.docked
    if (a.keys !== undefined) row.keys = a.keys
    if (a.sound !== undefined) row.sound = a.sound
    if (a.device !== undefined) row.device = a.device
    if (a.limits !== undefined) row.limits = a.limits
    return row
  })
}

// Made-up states for the demo phone (screenshots and checks): nothing in a
// demo reaches adb or a device.
function demoScreen(kind) {
  var tools = { scrcpy: true, adb: true, ok: true, version: "4.1", apps: true, flex: true }
  if (kind === "tools") return { state: "tools", tools: { ok: false } }
  // The demo's keys are Omarchy's defaults; a real device's come from this
  // machine (the bridge).
  if (kind === "ready" || kind === "opens") return { state: "ready", tools: tools, via: "wifi", android: "16", sdk: 36, apps: true, wireless: true, display: [1080, 2400],
                                                   keys: { pop: ["Super", "O"], fullscreen: ["Super", "F"] } }
  // Ready on a machine with no key for Omarchy's pop-out or full screen.
  if (kind === "nokeys") return { state: "ready", tools: tools, via: "wifi", android: "16", sdk: 36, apps: true, wireless: true, display: [1080, 2400], keys: {} }
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
// `lines`: what shows; `why`: the likely causes, behind Why? (the plugin
// keeps looking meanwhile).
function awayState(device, network, searchedAt, nowMs) {
  var seen = device && device.lastSeen
  var lines = [], why = []
  if (seen && seen.at) {
    var how = seen.link === "Bluetooth" ? "Bluetooth" : (seen.link === "LAN" ? "Wi-Fi" : "the network")
    lines.push("Last seen " + agoText(seen.at, nowMs))
    why.push("Last seen on " + how + (seen.address ? " at " + seen.address : ""))
    if (inNetwork(seen.address, network) === false)
      why.push("Likely on another network: this computer is on " + network)
  } else {
    lines.push("Not seen by this computer yet")
  }
  var searching = searchedAt > 0 && nowMs - searchedAt < SEARCH_MS
  if (searchedAt > 0 && !searching)
    why.push("Not found. On " + deviceLabel(device) + ": open KDE Connect, and join the same Wi-Fi"
      + (isSamsung(device) ? "; set the app's battery use to Unrestricted" : ""))
  return { lines: lines, why: why, searching: searching }
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

// Made-up contacts, the people the demo conversations are with, for
// screenshots and checks: a real phone's contacts never go in a picture.
// `picture` is a local image for Alex's photo; without one Alex shows the
// initial, as the others do.
function demoContacts(picture) {
  function c(id, name, line) {
    return Object.assign({ id: id, name: name, nickname: "", org: "", title: "", phones: [], emails: [],
                           addresses: [], websites: [], birthday: "", note: "", photo: "", stored: "account" }, line)
  }
  return [
    c("demo-1", "Alex Rivera", { nickname: "Al", org: "Northwind Press", title: "Editor",
      phones: [{ label: "Mobile", value: "+15145550123" }, { label: "Work", value: "+15145550144" }],
      emails: [{ label: "Home", value: "alex@example.invalid" }],
      addresses: [{ label: "Home", value: "12 Rue Example, Montreal, QC" }],
      websites: [{ label: "Website", value: "https://example.com/alex" }],
      birthday: "1990-05-02", note: "Brings the board game", photo: picture || "" }),
    c("demo-2", "Dr. Moreau's office", { stored: "phone", phones: [{ label: "Work", value: "+15145550177" }],
      addresses: [{ label: "Work", value: "480 Avenue Example, Montreal, QC" }] }),
    c("demo-3", "Jordan Lee", { phones: [{ label: "Mobile", value: "+15145550188" }],
      emails: [{ label: "Work", value: "jordan@example.invalid" }] }),
    c("demo-4", "Priya Anand", { org: "Riverside Clinic", title: "Nurse",
      phones: [{ label: "Mobile", value: "+15145550141" }] }),
    c("demo-5", "Sam Chen", { phones: [{ label: "Mobile", value: "+15145550142" }, { label: "Home", value: "+15145550143" }],
      emails: [{ label: "Home", value: "sam@example.invalid" }], birthday: "--11-19" }),
    c("demo-6", "Taylor Brooks", { org: "Corner Bakery",
      phones: [{ label: "Work", value: "+15145550166" }], note: "Orders by Thursday" })
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
  showApps: function(v) { return layoutFlag(v) },
  // The apps kept in the Apps section, in their order (packages).
  pinnedApps: function(v) { return normalizePinned(v) },
  // Where an app's sound plays when it opens: here, left on the device, or
  // both (Android 13). An open window changes its own (#129).
  appSound: function(v) { return soundPlace(v) },
  showReceived: function(v) { return layoutFlag(v) },
  showCalls: function(v) { return layoutFlag(v) },
  // The screen's window: docked by the bar (Omarchy's pop-out), or tiled.
  screenDocked: function(v) { return layoutFlag(v) },
  // Screen and apps as a feature: off, no screen, no apps, nothing read
  // over adb, and nothing about it to fix.
  screenFeature: function(v) { return layoutFlag(v) },
  // Experimental, off unless chosen: a tiled screen's tile takes the
  // device's width (Hyprland has no such thing; the plugin moves the edge).
  screenFitTile: function(v) { return v === true || v === "true" },
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
  layout: ["showShortcuts", "showApps", "showMedia", "showNotifications", "showReceived", "showPhotos", "sectionOrder"],
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
// `screenOnly`: ids the screen link reaches while KDE Connect does not.
function devicesListRows(snapshot, settings, lowPercent, screenOnly) {
  var ordered = orderedDevices(snapshot, settings)
  var rows = []
  for (var i = 0; i < ordered.length; i++) {
    var d = ordered[i]
    var p = resolveProfile(settings, d, i === 0)
    rows.push({ kind: "device", id: String(d.id), glyph: deviceIcon(d, p), title: deviceTitle(d, p), name: String(d.name || ""),
                status: d.reachable === true ? metaLine(snapshot, d, lowPercent) : (screenOnly && screenOnly[String(d.id)] ? "Screen and apps only" : "Away"),
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
//   single: one paired device or none (no For all devices, no bar place or
//   tab; Settings is that device's page, with the status and Add a device)
//   problems: settingsProblems(...)          (the status: root, or the one device's page)
//   devices: devicesListRows(...)            (root)
//   identity: { nickname, icon, glyph, bar, showInPanel } (device)
//   features: the device's feature rows      (device: what it shares)
//   edit: the profile being edited (defaults, or the device's), with custom
//   can: the device's capabilities, for shortcuts it cannot do
function settingsPageRows(ctx) {
  var rows = []
  var scope = ctx.scope || "root"
  var problems = ctx.problems || []
  if (scope === "root") {
    // Several devices: the status (only while something needs the user),
    // My devices (every device, the one in view too; asking to pair; Add a
    // device), For all devices. This computer is not here: its checks are
    // reached from a problem they cause (docs/design/setup.md).
    problems.forEach(function(p) { rows.push(Object.assign({ kind: "problem" }, p)) })
    ;(ctx.devices || []).forEach(function(r) {
      if (r.kind === "available") return   // Add a device lists those
      if (r.kind !== "device") { rows.push(r); return }
      var n = problems.filter(function(p) { return p.where === r.id }).length
      rows.push(Object.assign({}, r, { issues: n, status: n > 0 ? r.status + " · " + n + (n === 1 ? " needs attention" : " need attention") : r.status }))
    })
    rows.push({ kind: "addDevice", key: "addDevice", glyph: GLYPH.add, label: "Add a device", hint: "Pair another phone or tablet" })
    if (!ctx.single)
      rows.push({ kind: "defaults", key: "defaults", label: "For all devices", hint: "Sections, shortcuts and bar, for a device that did not change them and for new ones" })
    return rows
  }
  // A panel torn down mid-reload can ask with nothing to edit.
  var e = ctx.edit || resolveProfile(readSettings({}), null, true)
  if (scope === "device") {
    // One device: Settings is its page, so the status leads it.
    if (ctx.single) problems.forEach(function(p) { rows.push(Object.assign({ kind: "problem" }, p)) })
    if (ctx.identity) {
      rows.push({ kind: "nickname", key: "nickname", label: "Nickname", hint: "In the bar and the tabs; short is best", value: ctx.identity.nickname })
      rows.push({ kind: "icon", key: "icon", label: "Icon", hint: "Its glyph in the bar and the tabs", glyph: ctx.identity.glyph, value: ctx.identity.icon })
      // Where it shows among others: nothing to choose with one device.
      if (!ctx.single) {
        rows.push({ kind: "barPlace", key: "bar", label: "In the bar", hint: "Its chip: always, only with news, or never", value: ctx.identity.bar === "own" ? "always" : ctx.identity.bar })
        rows.push({ kind: "showInPanel", key: "showInPanel", label: "Show in panel", hint: "A tab for it in the panel", on: ctx.identity.showInPanel !== false })
      }
    }
    // What it shares with this computer: a switch per feature it can do,
    // no state (docs/design/setup.md). What one needs shows where it is
    // used, the main page's section, or in the status when it stopped.
    ;(ctx.features || []).forEach(function(f) { if (f.state !== "unavailable") rows.push(Object.assign({ kind: "feature" }, f)) })
    // Its sections, shortcuts and bar are edited on the page itself (edit
    // in place); here, whether they are the defaults, and the way there.
    var own = !ctx.single && ["layout", "bar", "shortcuts"].some(function(g) { return groupCustom(e.custom, g) })
    rows.push({ kind: "editPage", key: "editPage", label: "Sections, shortcuts and bar",
                hint: (ctx.single ? "Edited" : own ? "Its own · edited" : "The defaults for all devices · edited") + " on its page (✎, or right-click its chip in the bar)" })
    if (!ctx.single) ["layout", "bar", "shortcuts"].forEach(function(g) {
      if (groupCustom(e.custom, g))
        rows.push({ kind: "resetGroup", key: g, label: { layout: "Layout", bar: "Bar", shortcuts: "Shortcuts" }[g] + ": use the defaults",
                    hint: "This device changed it; the defaults apply again" })
    })
    if (ctx.single) rows.push({ kind: "addDevice", key: "addDevice", glyph: GLYPH.add, label: "Add a device", hint: "Pair another phone or tablet" })
    rows.push({ kind: "unpair", key: "unpair", label: "Unpair" })
    return rows
  }
  // For all devices: the groups as settings rows (the defaults have no page
  // of their own to edit them on).
  var base = settingsRows({ showShortcuts: e.showShortcuts, showMedia: e.showMedia, showNotifications: e.showNotifications, showReceived: e.showReceived, showPhotos: e.showPhotos },
                          e.shortcuts, ctx.can || null, e.sectionOrder, e.barIndicators, e.batteryLowOnly, e.showCalls)
  base.forEach(function(r) {
    if (r.kind === "layout" && r.section === "devices") return
    rows.push(r)
  })
  return rows
}

// What needs the user, each problem once, where its cause is: this
// computer's failing checks (not ignored, not optional), then each
// connected device's broken setup items (it worked and stopped), each once
// with the features it affects (none turned off), and fixes that did not
// work on a feature none of whose items is listed. `devices`: [{ id,
// title, setup: deviceSetup(...), rows: its feature rows with `pending` }].
// The status at the top of Settings, the gear's dot and the main page's
// line all count these.
function settingsProblems(checks, ignored, devices) {
  var out = []
  connectionRows(checks, ignored).forEach(function(c) {
    if (!c.ok && !c.optional && !c.ignored)
      out.push({ where: "computer", whereLabel: "This computer", key: c.key, label: c.label, detail: c.status + (c.detail ? ": " + c.detail : ""), steps: [] })
  })
  ;(devices || []).forEach(function(d) {
    var rows = d.rows || [], setup = d.setup || { items: [] }
    var shown = {}
    setup.items.forEach(function(it) {
      if (it.state !== "broken") return
      var affects = rows.filter(function(r) { return r.needs.indexOf(it.key) >= 0 && r.state !== "off" && r.state !== "unavailable" })
      if (affects.length === 0) return
      affects.forEach(function(r) { shown[r.key] = true })
      var gateway = GATEWAYS.filter(function(g) { return g.key === it.gateway })[0]
      var tried = affects.map(function(r) { return r.pending && r.pending.tried ? r.pending.tried : "" }).filter(function(t) { return t })[0] || ""
      // Many features behind one item (KDE Connect's link): the gateway's name.
      out.push({ where: String(d.id), whereLabel: d.title, key: it.key,
                 label: affects.length > 2 && gateway ? gateway.label : affects.map(function(r) { return r.label }).join(", "),
                 gateway: gateway ? gateway.label : "", detail: it.detail, steps: it.steps, tried: tried,
                 affects: affects.map(function(r) { return r.key }) })
    })
    rows.forEach(function(r) {
      if (shown[r.key] || !(r.pending && r.pending.failed)) return
      out.push({ where: String(d.id), whereLabel: d.title, key: "feature:" + r.key, label: r.label, detail: r.pending.text,
                 steps: r.steps || [], tried: r.pending.tried || "", affects: [r.key] })
    })
  })
  return out
}

// Fix all on Settings' status: what it lists, each step once.
function problemsPlan(problems) {
  var seen = {}, out = []
  ;(problems || []).forEach(function(p) {
    featurePlan(p).forEach(function(s) {
      var id = s.fix.verb + ":" + s.fix.what + ":" + (s.fix.arg || "")
      if (seen[id]) return
      seen[id] = true
      out.push(s)
    })
  })
  return out
}

// The status's one line: all well, or how many need the user.
function problemsLine(problems) {
  var n = (problems || []).length
  return n === 0 ? "Everything works" : n === 1 ? "1 thing needs you" : n + " things need you"
}

// ---- Where a feature shows: an ask or a problem in its own section ----
// The main page says what a feature needs where that feature shows
// (docs/design/setup.md): the one step only the user can do, or that it
// stopped. A feature with no section of its own shows in the line at the top.
// (Now playing's one need, notification access, is the Notifications
// section's ask; the gallery says its own in its section. Messages and the
// names in it: the Messages page.)
var FEATURE_SECTIONS = { notifications: "notifications", gallery: "photos", screen: "apps", messages: "messages", names: "messages" }

// What a section says about its features, or null. `rows`: the device's
// feature rows (with `problem` and `pending`). A problem: it worked and
// stopped (Fix runs the plugin's steps, when it has any). An ask: something
// it needs that one click here does (a permission over adb), or the step
// left on the device, waited for.
function sectionNote(rows, section) {
  var mine = (rows || []).filter(function(r) { return FEATURE_SECTIONS[r.key] === section && r.on !== false })
  for (var i = 0; i < mine.length; i++) {
    var r = mine[i]
    if (r.problem) return { kind: "problem", key: r.key, label: r.label, text: r.pending && r.pending.failed ? r.pending.text : (r.detail || "It stopped working"),
                            fix: featurePlan(r).length > 0, row: r }
  }
  for (var j = 0; j < mine.length; j++) {
    var a = mine[j]
    if (a.state !== "setup") continue
    if (a.pending && !a.pending.failed) return { kind: "ask", key: a.key, label: a.label, text: a.pending.text, waiting: a.pending.wait === true, fix: false, row: a }
    // Only an ask the plugin knows of (read over adb): never a guess.
    var step = (a.steps || [])[0]
    if (step && step.orAsk && step.fix && step.fix.what === "grant")
      return { kind: "ask", key: a.key, label: a.label, text: a.detail, waiting: false, fix: true, row: a }
  }
  return null
}

// The problems the line at the top of the main page shows: those with no
// section drawn to say them (this computer's, a link, a feature without a
// section of its own).
function bannerProblems(problems, drawn) {
  return (problems || []).filter(function(p) {
    return !(p.affects || []).some(function(k) { return !!FEATURE_SECTIONS[k] && (drawn || []).indexOf(FEATURE_SECTIONS[k]) >= 0 })
  })
}

// ---- The first run: this computer made ready in one step ----
// KDE Connect missing or stopped: one card, one password for everything any
// feature needs here (bridge `fix ready`), then KDE Connect started.
function readyRows(checks) {
  var c = {}
  ;(checks || []).forEach(function(x) { c[x.key] = x })
  var waiting = !(checks || []).length
  return [{ kind: "ready", key: "ready", checking: waiting,
            installed: !!(c.installed && c.installed.ok), running: !!(c.running && c.running.ok) }]
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
  apps: "Shows its apps once its screen is set up",
  received: "Shows the files it sends you"
}

// ---- Apps: the device's apps, each in a window of its own (#116) ----
// The list comes from the bridge (`apps`): {package, name, system, icon,
// opened}. icon: a safe PNG's path, "" not read yet, "none" none to read.

var APPS_RECENT = 7       // recently opened, first on the All apps page

function normalizePinned(v) {
  if (typeof v === "string") {
    try { v = JSON.parse(v) } catch (e) { v = null }
  }
  var out = []
  if (v && typeof v !== "string" && typeof v.length === "number")
    for (var i = 0; i < v.length; i++) {
      var p = String(v[i] || "")
      if (/^[A-Za-z][\w]*(\.[\w]+)+$/.test(p) && out.indexOf(p) < 0) out.push(p)
    }
  return out
}

function appByPackage(apps, pkg) {
  for (var i = 0; i < (apps || []).length; i++) if (apps[i].package === pkg) return apps[i]
  return null
}

// The pinned apps that are on the device, in their order.
function pinnedAppsOf(apps, pinned) {
  return normalizePinned(pinned).map(function(p) { return appByPackage(apps, p) }).filter(function(a) { return !!a })
}

// The section's two rows: { pinned, recent }. Every pinned app (the row
// wraps), All apps at its right end; the recently opened ones that are not
// pinned, one row (All apps last when nothing is pinned).
function appSectionRows(apps, pinned, columns) {
  var keep = normalizePinned(pinned)
  var shown = pinnedAppsOf(apps, keep)
  return {
    pinned: shown,
    recent: recentApps(apps, true).filter(function(a) { return keep.indexOf(a.package) < 0 })
      .slice(0, Math.max(0, shown.length > 0 ? columns : columns - 1))
  }
}

// The All apps tile's slot in the pinned row: the row's last column, or
// after the pins once they fill it (`extra`: an app coming in).
function allAppsSlot(count, columns, extra) {
  return Math.max(columns - 1, count + (extra ? 1 : 0))
}

// Pinned at a place among the ones shown (a drop, a move), or moved there
// when it already is. `shown`: the pinned packages the row draws, in order
// (the list also keeps apps this device does not have, which stay where
// they are); without it, every pinned one is shown.
function pinAppAt(pinned, pkg, at, shown) {
  var keep = normalizePinned(pinned).filter(function(p) { return p !== pkg })
  var drawn = (shown || keep).filter(function(p) { return p !== pkg && keep.indexOf(p) >= 0 })
  var k = Math.max(0, Math.min(drawn.length, at))
  // Before the one it lands in front of, else just after the last one drawn.
  var place = k < drawn.length ? keep.indexOf(drawn[k]) : (drawn.length > 0 ? keep.indexOf(drawn[drawn.length - 1]) + 1 : keep.length)
  keep.splice(place, 0, pkg)
  return keep
}

// Where the keys go among tiles laid out in groups (pinned, recent, all),
// each group a grid of `columns`: the rows, each a list of flat indexes.
function cursorRows(groups, columns) {
  var rows = [], base = 0, c = Math.max(1, columns)
  for (var g = 0; g < groups.length; g++) {
    for (var i = 0; i < groups[g]; i += c) {
      var row = []
      for (var j = i; j < Math.min(groups[g], i + c); j++) row.push(base + j)
      rows.push(row)
    }
    base += groups[g]
  }
  return rows
}

// One key: the index it goes to, or -1 when it leaves the tiles (up from
// the first row, down from the last). Sideways it stays in its row. A row
// may repeat an index over empty columns (a tile at the row's end), so up
// and down land under the column: sideways skips the repeats.
function cursorStep(rows, index, dx, dy) {
  var r = -1, col = 0
  for (var i = 0; i < rows.length; i++) {
    var at = rows[i].indexOf(index)
    if (at >= 0) { r = i; col = at; break }
  }
  if (r < 0) return rows.length > 0 && rows[0].length > 0 ? rows[0][0] : -1
  if (dx !== 0) {
    var k = col
    while (k + dx >= 0 && k + dx < rows[r].length) {
      k += dx
      if (rows[r][k] !== index) return rows[r][k]
    }
    return index
  }
  var t = r + (dy > 0 ? 1 : -1)
  if (t < 0 || t >= rows.length) return -1
  return rows[t][Math.min(col, rows[t].length - 1)]
}

function recentApps(apps, withSystem) {
  return (apps || []).filter(function(a) { return (a.opened || 0) > 0 && (withSystem || !a.system) })
    .sort(function(a, b) { return b.opened - a.opened })
}

// Accents and case do not matter to a search.
function foldText(s) {
  return String(s || "").toLowerCase().normalize("NFD").replace(/[\u0300-\u036f]/g, "")
}

function byName(a, b) {
  var x = foldText(a.name), y = foldText(b.name)
  return x < y ? -1 : x > y ? 1 : 0
}

// The All apps page: { recent, all }, every app, the system's own too.
// Without a search, the recently opened ones lead (also in the list, as on
// a phone); with one, the matches, those whose name starts with it first.
function appsForPage(apps, query) {
  var shown = apps || []
  var q = foldText(query).trim()
  if (q === "")
    return { recent: recentApps(shown, true).slice(0, APPS_RECENT), all: shown.slice().sort(byName) }
  // The name; a package only when the search looks like one (a dot).
  var hits = shown.filter(function(a) { return foldText(a.name).indexOf(q) >= 0 || (q.indexOf(".") >= 0 && a.package.toLowerCase().indexOf(q) >= 0) })
  hits.sort(function(a, b) {
    var pa = foldText(a.name).indexOf(q) === 0 ? 0 : 1, pb = foldText(b.name).indexOf(q) === 0 ? 0 : 1
    return pa !== pb ? pa - pb : byName(a, b)
  })
  return { recent: [], all: hits }
}

function appsSummary(apps, pinned) {
  var count = (apps || []).length
  var kept = normalizePinned(pinned).filter(function(p) { return !!appByPackage(apps, p) }).length
  var all = count === 1 ? "1 app" : count + " apps"
  return kept > 0 ? kept + " pinned · " + all : all
}

// A tile without an icon: the name's first letter.
function appLetter(name) {
  // A letter (it has a case) or a digit; the shell's JavaScript has no
  // Unicode classes in its expressions.
  var s = String(name || "")
  for (var i = 0; i < s.length; i++) {
    var c = s.charAt(i)
    if (c.toLowerCase() !== c.toUpperCase() || (c >= "0" && c <= "9")) return c.toUpperCase()
  }
  return "?"
}

// KDE Connect's id of a notification is Android's key,
// "user|package|id|tag|uid": the app it came from.
function notificationPackage(n) {
  var parts = String(n && (n.key || n.id) || "").split("|")
  return parts.length >= 3 && /^[A-Za-z][\w]*(\.[\w]+)+$/.test(parts[1]) ? parts[1] : ""
}

// The app a notification can open in a window, or null (not a launchable
// app on the device).
function appForNotification(n, apps) {
  var pkg = notificationPackage(n)
  return pkg ? appByPackage(apps, pkg) : null
}

function pinApp(pinned, pkg, on) {
  var keep = normalizePinned(pinned).filter(function(p) { return p !== pkg })
  if (on) keep.push(pkg)
  return keep
}

// Demo: made-up apps, drawn with glyphs (no icon files), some recently opened.
function demoApps(nowMs) {
  var now = nowMs || Date.now()
  var list = [
    ["Clock", "clock", false, 3], ["Calendar", "calendar", false, 1], ["Camera", "camera", false, 0],
    ["Maps", "map", false, 2], ["Music", "music", false, 4], ["Notes", "notes", false, 0],
    ["Weather", "weather", false, 0], ["WhatsApp", "chat", false, 5], ["Mail", "mail", false, 0],
    ["Photos", "image", false, 0], ["Shop", "cart", false, 0], ["Bank", "bank", false, 0],
    ["Fitness", "fitness", false, 0], ["Calculator", "calculator", true, 0], ["Settings", "cog", true, 0]
  ]
  return list.map(function(e) {
    return { package: "com.example." + e[0].toLowerCase(), name: e[0], system: e[2], icon: "", glyph: GLYPH[e[1]],
             opened: e[3] > 0 ? now - e[3] * 3600000 : 0 }
  })
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
  if (!left.settingsOpen && !left.messagesOpen && !left.contactsOpen && !left.appsOpen && !(left.y > 0)) return null
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
