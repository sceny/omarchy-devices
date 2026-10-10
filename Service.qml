import QtQuick
import Qt.labs.folderlistmodel
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import Quickshell.Services.Mpris
import "Model.js" as Model

// One watcher for the whole shell, however many bars there are: the bar
// widget on each monitor and the panel all read this service.
//
// State comes from `bin/kdeconnect-bridge watch`, which prints a JSON snapshot of
// the KDE Connect devices whenever the daemon signals a change. Actions run
// the same bridge once per click and report one line back.
Item {
  id: root

  property var settings: ({})

  function setting(name, fallback) {
    var value = settings ? settings[name] : undefined
    return value === undefined || value === null ? fallback : value
  }

  readonly property string bridge: {
    var url = Qt.resolvedUrl("bin/kdeconnect-bridge").toString()
    return url.indexOf("file://") === 0 ? decodeURIComponent(url.substring(7)) : url
  }

  property var snapshot: null
  property string watchError: ""

  // Demo mode shows Model.demoSnapshot instead of the phone, for looking at
  // the notification layouts without real traffic. Clicks still go
  // to the real phone, so demo rows are inert: `run` refuses while it is on.
  property bool demo: false
  property var liveSnapshot: null
  // The widget's settings as they were when the demo began (Panel.enterDemo),
  // put back on leaving it; null outside a demo.
  property var settingsBeforeDemo: null

  function showDemo(kind) {
    demo = true
    snapshot = Model.demoSnapshot(liveSnapshot || snapshot, kind || "")
    smsService.showDemo()
    contactsService.showDemo()
  }

  // A demo the user started from the panel, before any device is set up
  // (Preview with a demo phone): the panel says it is one, and a real
  // device connecting ends it.
  property bool preview: false

  function showLiveFiles() { dismissedFiles = ({}) }
  function showLive() {
    preview = false
    showLiveFiles()
    demo = false
    snapshot = liveSnapshot
    smsService.showLive()
    contactsService.showLive()
    searchedAt = 0
    demoChecks = false
    demoNetworkKind = ""
    demoFeature = ""
    runDoctor()
  }
  // ---- Many devices (docs/design/multi-device.md) ----
  // The settings read as defaults plus per-device profiles (Model.readSettings),
  // and every paired device in the user's order.
  readonly property var profiles: Model.readSettings(settings)
  readonly property var ordered: Model.orderedDevices(snapshot, profiles)

  // The device the panel shows and clicks act on. Chosen with a tab, a chip
  // or IPC; empty means the one the panel opens on (Model.openingDevice).
  // Shared by every monitor's panel.
  property string viewedId: ""
  // A chip or IPC asks for a device before the panel opens; opening uses it
  // once instead of the usual choice.
  property string requestedId: ""

  readonly property var device: {
    for (var i = 0; i < ordered.length; i++) if (ordered[i].id === viewedId) return ordered[i]
    return Model.openingDevice(snapshot, profiles, callStates)
  }
  // Each device's call, for the opening rule (a ringing device opens first).
  // Kept apart from deviceStates, which reads the messages service that
  // itself follows `device`.
  readonly property var callStates: {
    var out = {}
    for (var id in calls) out[id] = { call: { state: calls[id].state } }
    return out
  }

  // ---- Calls (Model.callState): a device ringing, or a call missed ----
  // Per device, for devices whose profile shows calls. KDE Connect never
  // says a call ended, so time decides when ringing stops counting; `clock`
  // is re-read when a call's state can next change.
  property real clock: Date.now()
  // Per device, the `at` of the last call the user closed. Memory only: after
  // a restart the bridge has forgotten the calls too.
  property var callClosed: ({})
  readonly property var calls: {
    var out = {}
    for (var i = 0; i < ordered.length; i++) {
      var d = ordered[i]
      if (!Model.resolveProfile(profiles, d, i === 0).showCalls) continue
      var c = Model.callState(d, clock, callClosed[d.id] || 0)
      if (c) out[d.id] = c
    }
    return out
  }
  // The call the card shows: a ringing one first, else the latest missed.
  readonly property var call: Model.shownCall(calls, ordered.map(function(d) { return String(d.id) }))
  // A new call event from any device re-reads the clock.
  readonly property string callEvents: JSON.stringify(ordered.map(function(d) { return d.call || null }))
  onCallEventsChanged: clock = Date.now()

  function closeCall() {
    if (!call) return
    var next = Object.assign({}, callClosed)
    next[call.device] = call.at
    callClosed = next
  }

  // On for each ring of the beat (Model.ringPhases): the ringing device's
  // chip glows ring, ring, rest, in step with the card's waves.
  readonly property bool ringing: !!call && call.state === "ringing"
  readonly property var ringPhases: Model.ringPhases()
  property int ringPhase: 0
  readonly property bool ringLit: ringing && ringPhases[ringPhase].lit
  // A device asking to pair glows on the same beat (the first chip's glyph).
  readonly property bool pairLit: !!pairingRequest && ringPhases[ringPhase].lit
  Timer {
    running: root.ringing || !!root.pairingRequest
    repeat: true
    interval: root.ringPhases[root.ringPhase].ms
    onRunningChanged: root.ringPhase = 0
    onTriggered: root.ringPhase = (root.ringPhase + 1) % root.ringPhases.length
  }
  Timer {
    // Wakes when the soonest call runs out (plus a beat), not every second.
    readonly property real due: {
      var soonest = -1
      for (var id in root.calls) {
        var t = Model.callExpiresIn(root.calls[id], root.clock)
        if (t >= 0 && (soonest < 0 || t < soonest)) soonest = t
      }
      return soonest
    }
    interval: Math.max(250, due + 250)
    running: due >= 0
    onTriggered: root.clock = Date.now()
  }

  // The phone's dialer on the number (a tel: link through KDE Connect's
  // share), on the device the call came to: the call itself is the user's
  // tap on the phone.
  function callBack(c) {
    var n = c ? String(c.number || "").trim() : ""
    if (n === "" || !c.device) return
    if (demo) { demoRun("dial", [n], "dial"); return }
    if (isBusy("dial")) return
    setBusy("dial", true)
    var proc = actionComponent.createObject(root, { key: "dial", command: [bridge, "dial", c.device, n] })
    proc.running = true
  }

  // Demo mode rings (or misses) a made-up caller on the viewed device (or
  // the first), over the demo snapshot. It replaces any other demo call.
  function showDemoCall(kind) {
    if (!demo) return
    var copy = JSON.parse(JSON.stringify(snapshot || {}))
    var id = device ? String(device.id) : ""
    var list = copy.devices || []
    var d = null
    for (var i = 0; i < list.length; i++) {
      delete list[i].call
      if (String(list[i].id) === id) d = list[i]
    }
    if (!d) d = Model.pickDevice(copy, "")
    if (!d) return
    d.call = Model.demoCall(kind, Date.now())
    callClosed = ({})
    snapshot = copy
  }
  readonly property int deviceIndex: {
    for (var i = 0; i < ordered.length; i++) if (device && ordered[i].id === device.id) return i
    return -1
  }
  // The viewed device's profile: its sections, shortcuts and folds.
  readonly property var profile: Model.resolveProfile(profiles, device, deviceIndex <= 0)
  // Devices with a tab (Show in panel), in order.
  readonly property var panelDevices: {
    var out = []
    for (var i = 0; i < ordered.length; i++)
      if (Model.resolveProfile(profiles, ordered[i], i === 0).showInPanel || (device && ordered[i].id === device.id)) out.push(ordered[i])
    return out
  }

  function view(id) { viewedId = String(id || "") }
  function requestView(id) { requestedId = String(id || "") }
  // On opening: the device asked for (a chip, IPC), else the opening rule.
  function viewOnOpen() {
    if (requestedId !== "") { viewedId = requestedId; requestedId = ""; return }
    var d = Model.openingDevice(snapshot, profiles, callStates)
    viewedId = d ? String(d.id) : ""
  }

  // Finds a device by id, nickname or name (IPC takes any of them).
  function findDevice(key) {
    var k = String(key || "").trim().toLowerCase()
    if (k === "") return null
    for (var i = 0; i < ordered.length; i++) {
      var d = ordered[i]
      var p = Model.resolveProfile(profiles, d, i === 0)
      if (String(d.id).toLowerCase() === k || p.nickname.toLowerCase() === k || String(d.name || "").toLowerCase() === k) return d
    }
    return null
  }

  // What each device has for the pill (Model.attention): its visible
  // notifications (its playback ones left out, as on its page), unread
  // messages while this service reads its messages, whether it plays.
  readonly property int lowPercent: {
    var n = parseInt(String(setting("lowBatteryPercent", 15)), 10)
    return isFinite(n) ? n : 15
  }
  readonly property var deviceStates: {
    var all = Mpris.players ? Mpris.players.values : []
    var out = {}
    for (var i = 0; i < ordered.length; i++) {
      var d = ordered[i]
      var media = [], playing = false, playingApps = []
      for (var j = 0; j < all.length; j++) {
        var p = all[j]
        if (!p || !Model.isPhonePlayer(p.dbusName, p.identity, String(d.name || ""))) continue
        media.push({ app: Model.playerApp(p.identity, d.name), title: p.trackTitle })
        if (p.isPlaying) { playing = true; playingApps.push(Model.playerApp(p.identity, d.name)) }
      }
      out[d.id] = {
        notifications: Model.visibleNotifications(d, media).length,
        messages: smsService.deviceId === String(d.id) ? smsService.unreadCount : 0,
        playing: playing,
        playingApps: playingApps,
        lowPercent: lowPercent,
        call: calls[d.id] ? { state: calls[d.id].state } : null
      }
    }
    return out
  }

  // A device asking to pair: the first one, or null.
  readonly property var pairingRequest: {
    var list = snapshot && snapshot.devices ? snapshot.devices : []
    for (var i = 0; i < list.length; i++) if (list[i] && list[i].pairRequestedByPeer === true) return list[i]
    return null
  }

  // The pill: a chip per device that shows, and a resting glyph when none
  // does (Model.chips).
  readonly property var pill: Model.chips(snapshot, profiles, deviceStates, !!pairingRequest)

  readonly property bool daemon: !!(snapshot && snapshot.daemon)
  readonly property bool reachable: !!(device && device.reachable)
  readonly property var notifications: {
    var media = []
    for (var i = 0; i < players.length; i++)
      media.push({ app: Model.playerApp(players[i].identity, deviceName), title: players[i].trackTitle })
    return Model.visibleNotifications(device, media)
  }

  // The phone's media, straight from the MPRIS players KDE Connect exports
  // (one per phone app). The shell tracks these itself, so a player that
  // starts, stops or changes track shows at once, and each carries position,
  // length and volume.
  //
  // The list is replaced only when a player appears or goes, never on a play
  // state change, and it is kept in a fixed order (by name). A seek makes the
  // phone report "paused" for a moment; a list that re-sorted or rebuilt on
  // that tore the cards down and put them back, a visible blink.
  readonly property string deviceName: device ? String(device.name || "") : ""
  property var players: []

  function updatePlayers() {
    var all = Mpris.players ? Mpris.players.values : []
    var out = []
    if (reachable) {
      for (var i = 0; i < all.length; i++) {
        var p = all[i]
        if (p && Model.isPhonePlayer(p.dbusName, p.identity, deviceName) && !Model.playerHidden(pausedSince[String(p.dbusName)], Date.now())) out.push(p)
      }
      out.sort(function(a, b) { return String(a.identity || "").localeCompare(String(b.identity || "")) })
    }
    var same = out.length === players.length
    for (var j = 0; same && j < out.length; j++) same = out[j] === players[j]
    if (!same) players = out
  }

  // A player paused this long Android hides itself (its media controls
  // go), while KDE Connect still reports it (#35, our #33): hidden here too,
  // back as soon as it plays. Far longer than a seek's pause, so nothing
  // blinks (the list changes only when that time is crossed).
  property var pausedSince: ({})
  Timer {
    interval: 5000
    repeat: true
    running: root.reachable
    onTriggered: {
      var all = Mpris.players ? Mpris.players.values : []
      var next = {}, now = Date.now()
      for (var i = 0; i < all.length; i++) {
        var p = all[i]
        if (!p || !Model.isPhonePlayer(p.dbusName, p.identity, root.deviceName)) continue
        var name = String(p.dbusName)
        if (!p.isPlaying) next[name] = root.pausedSince[name] || now
      }
      root.pausedSince = next
      root.updatePlayers()
    }
  }

  onDeviceNameChanged: updatePlayers()
  onReachableChanged: updatePlayers()
  Component.onCompleted: { updatePlayers(); followSms() }

  Connections {
    target: Mpris.players
    function onValuesChanged() { root.updatePlayers() }
  }

  // The active player is the phone's: the one playing, else the one that
  // played last, else the first. Remembering the last one keeps a paused
  // podcast "active" instead of jumping to whatever sorts first.
  property string lastPlayingName: ""
  readonly property var playingPlayer: {
    for (var i = 0; i < players.length; i++) if (players[i].isPlaying) return players[i]
    return null
  }
  onPlayingPlayerChanged: if (playingPlayer) lastPlayingName = String(playingPlayer.dbusName || "")

  // MPRIS does not push position while playing; it has to be re-read. This
  // runs whether or not the panel is open, so opening it never shows a stale
  // seek bar gliding to the right place. Only while something plays, and one
  // property re-read per player per second.
  function refreshPositions() {
    for (var i = 0; i < players.length; i++)
      if (players[i] && players[i].positionSupported) players[i].positionChanged()
  }

  Timer {
    interval: 1000
    repeat: true
    running: !!root.playingPlayer
    onTriggered: {
      for (var i = 0; i < root.players.length; i++) {
        var p = root.players[i]
        if (p && p.isPlaying && p.positionSupported) p.positionChanged()
      }
    }
  }

  readonly property var activePlayer: {
    if (playingPlayer) return playingPlayer
    for (var i = 0; i < players.length; i++) if (players[i].dbusName === lastPlayingName) return players[i]
    return players.length > 0 ? players[0] : null
  }
  readonly property string nowPlaying: activePlayer && activePlayer.isPlaying
    ? Model.trackLine(activePlayer.trackTitle, activePlayer.trackArtist) : ""

  // A short line about the last click: "Ringing Pixel 8",
  // "Sending 2 files", or the reason it failed. Clears itself.
  property string actionStatus: ""
  property bool actionFailed: false

  // verb (or verb:notification) -> true while that action runs, so a second
  // click on the same thing waits instead of stacking up.
  property var busy: ({})

  function isBusy(key) { return busy[key] === true || waits[key] !== undefined }

  function setBusy(key, on) {
    var next = Object.assign({}, busy)
    if (on) next[key] = true
    else delete next[key]
    busy = next
  }

  // Panels open right now (one per monitor can be); kept by the panels.
  property int openPanels: 0

  function report(text, failed) {
    actionStatus = text
    actionFailed = failed
    statusTimer.restart()
    // Nobody is looking at a panel: say it with Omarchy's on-screen display.
    // The OSD takes any glyph as its icon: the device's own, or an alert.
    if (text !== "" && openPanels === 0)
      Quickshell.execDetached(["omarchy-osd", "-i", failed ? "\u{F0026}" : Model.deviceGlyph(device), "-m", text, "-d", failed ? "3000" : "1800"])
  }

  // `wait` keeps the click waiting past the bridge, until the device's
  // answer shows in the snapshot: { kind, note, before } (Model.answered).
  function run(verb, args, key, wait) {
    if (!device || !device.reachable) return
    key = key || verb
    if (isBusy(key)) return
    if (demo) { demoRun(verb, args, key); return }
    setBusy(key, true)
    var proc = actionComponent.createObject(root, {
      key: key,
      wait: wait ? Object.assign({ device: String(device.id) }, wait) : null,
      command: [bridge, verb, device.id].concat(args || [])
    })
    proc.running = true
  }

  // ---- Waiting on the device ----
  // key -> { kind, device, note, before, until, fail, said }: clicks the bridge has
  // passed on and the device has not answered yet. The clicked control shows
  // the waiting ring meanwhile (isBusy); a wait that runs out says so.
  property var waits: ({})

  function startWait(key, wait) {
    var limit = Model.waitLimit(wait.kind, device ? device.name : "")
    var next = Object.assign({}, waits)
    next[key] = Object.assign({ until: Date.now() + limit.ms, fail: limit.fail }, wait)
    waits = next
    checkWaits()
  }

  function checkWaits() {
    var now = Date.now()
    var next = {}
    var changed = false
    for (var key in waits) {
      var w = waits[key]
      var done = w.kind === "track" ? !w.player || String(w.player.trackTitle || "") !== w.title
        : Model.answered(w.kind, snapshot, w.device, w.note, w.before)
      if (done) {
        changed = true
        if (w.said && !Model.shownInPlace(w.kind)) report(w.said, false)
        continue
      }
      if (now > w.until) {
        changed = true
        if (w.fail !== "") report(w.fail, true)
        else if (w.said && !Model.shownInPlace(w.kind)) report(w.said, false)
        continue
      }
      next[key] = w
    }
    if (changed) waits = next
  }

  onSnapshotChanged: {
    if (Object.keys(waits).length > 0) checkWaits()
    // A device back (a phone restarted, back on the Wi-Fi): a gallery that
    // failed reads again at once, not after its 10 minutes, and its
    // features are read again.
    var list = snapshot && snapshot.devices ? snapshot.devices : []
    var next = {}
    for (var i = 0; i < list.length; i++) {
      var d = list[i], id = String(d.id)
      next[id] = d.reachable === true
      if (d.reachable === true && wasReachable[id] === false) {
        // Back: its notifications read again while no panel shows them, so
        // one dismissed there while the cancel was lost goes (#4).
        if (openPanels === 0 && !demo) {
          var renotify = silentComponent.createObject(root, { command: [bridge, "device-fix", "renotify", id] })
          renotify.running = true
        }
        var st = photoState[id]
        if (st && !st.ok) setPhotoState(id, Object.assign({}, st, { at: 0, error: "" }))
        if (openPanels > 0) { readFeatures(id); if (device && String(device.id) === id) Qt.callLater(function() { root.refreshPhotos(true) }) }
      }
    }
    wasReachable = next
  }
  property var wasReachable: ({})
  // Fix with AI (#101): the person's default coding agent, launched as
  // Omarchy launches it (`omarchy agent prompt`, its own mode), with the
  // facts and the plugin's skill by path, as `omarchy agent crash` does.
  readonly property string pluginFolder: bridge.replace(/\/bin\/kdeconnect-bridge$/, "")
  // Read again on each panel opening and before each launch: one picked
  // meanwhile (`omarchy agent --pick`) is the one used.
  property string agentName: ""
  Process {
    id: agentRead
    running: true
    command: ["omarchy-default-agent"]
    property var then: null
    stdout: StdioCollector {
      onStreamFinished: {
        root.agentName = text.trim()
        var t = agentRead.then
        agentRead.then = null
        if (t) t()
      }
    }
  }
  function readAgent(then) {
    if (agentRead.running) { if (then) agentRead.then = then; return }
    agentRead.then = then || null
    agentRead.running = true
  }
  onOpenPanelsChanged: if (openPanels > 0) readAgent()
  // `problems`: [{ label, detail, tried }] (tried: what the plugin's own fix
  // did, "" when none ran).
  function fixWithAi(problems) {
    if (demo) { report("Demo: your coding agent would open on it", false); return }
    readAgent(function() { launchAgent(problems) })
  }
  function launchAgent(problems) {
    // No default agent yet: Omarchy's own choice of one, first.
    if (agentName === "") { silentComponent.createObject(root, { command: ["omarchy", "agent", "--pick"] }).running = true; return }
    var lines = (problems || []).map(function(p) {
      return "  - " + p.label + (p.detail ? ": " + p.detail : "") + (p.tried ? " (the plugin's own fix was tried: " + p.tried + ")" : "")
    }).join("\n")
    var prompt = "Devices, the Omarchy shell plugin sceny.devices, shows a problem on this machine and I want it fixed.\n\n"
      + "What it shows:\n" + lines + "\n\n"
      + "Use the setup-help skill: it covers how to investigate, how to fix it, and when it is worth reporting "
      + "(never with personal data). If your harness has no skill mechanism, read the skill files directly and follow them instead:\n\n"
      + "  " + pluginFolder + "/.claude/skills/setup-help/SKILL.md"
    silentComponent.createObject(root, { command: ["omarchy", "agent", "prompt", prompt] }).running = true
  }

  // A fix that stopped at a step only the user can do, or did not work: per
  // device and feature ("id:key"). { text, wait (it can be seen when done:
  // read again on its own), failed, tried }.
  property var featurePending: ({})
  function setPending(id, key, value) {
    var next = Object.assign({}, featurePending)
    if (value) next[String(id) + ":" + key] = value
    else delete next[String(id) + ":" + key]
    featurePending = next
  }
  function pendingFor(id, key) { return featurePending[String(id) + ":" + key] || null }
  // Waiting for a step that can be seen when done: read again every few
  // seconds, for two minutes at most.
  Timer {
    interval: 4000
    repeat: true
    running: root.openPanels > 0 && Object.keys(root.featurePending).some(function(k) { return root.featurePending[k].wait })
    onTriggered: {
      var now = Date.now(), ids = {}
      Object.keys(root.featurePending).forEach(function(k) {
        var p = root.featurePending[k]
        if (!p.wait) return
        if (now - p.at > 120000) { var n = Object.assign({}, p, { wait: false }); var all = Object.assign({}, root.featurePending); all[k] = n; root.featurePending = all; return }
        ids[k.split(":")[0]] = true
      })
      Object.keys(ids).forEach(function(id) { root.readFeatures(id, true) })
    }
  }

  // A fix run on its own (no click): nothing said, done or not.
  Component {
    id: silentComponent
    Process { onExited: destroy() }
  }

  // The phone may never answer (it went away mid-click): the limit still ends it.
  Timer {
    interval: 500
    repeat: true
    running: Object.keys(root.waits).length > 0
    onTriggered: root.checkWaits()
  }

  // Demo mode sends nothing: a click waits as long as a phone about takes,
  // then says so; a dismissed or acted-on demo notification goes away.
  function demoRun(verb, args, key) {
    setBusy(key, true)
    demoComponent.createObject(root, { key: key, verb: verb, note: args && args.length ? String(args[0]) : "" })
  }

  Component {
    id: demoComponent
    Timer {
      id: demoClick
      property string key: ""
      property string verb: ""
      property string note: ""
      // A demo device "accepts" a pairing asked here a few seconds after its
      // key shows, as a real one would once the user taps Accept on it.
      interval: verb === "paired" ? 3000 : 900
      running: true
      onTriggered: {
        if ((verb === "dismiss" || verb === "action") && root.demo && root.snapshot)
          root.snapshot = Model.withoutNotification(root.snapshot, note)
        // Demo Pair: the device waits to accept, showing a made-up key.
        if (verb === "pair" && root.demo && root.snapshot) {
          var pid = key.split(":")[1]
          var pcopy = JSON.parse(JSON.stringify(root.snapshot))
          ;(pcopy.devices || []).forEach(function(d) { if (d.id === pid) { d.pairRequested = true; d.verificationKey = "7C192B4D" } })
          root.snapshot = pcopy
          demoComponent.createObject(root, { key: key, verb: "paired", note: "" })
        }
        if (verb === "paired" && root.demo && root.snapshot) {
          var aid = key.split(":")[1]
          var acopy = JSON.parse(JSON.stringify(root.snapshot))
          ;(acopy.devices || []).forEach(function(d) {
            if (d.id === aid && d.pairRequested === true) { d.pairRequested = false; d.paired = true; d.verificationKey = "" }
          })
          root.snapshot = acopy
          demoClick.destroy()
          return
        }
        // A demo pairing request answered: accepted, the device is paired;
        // rejected (or a pairing asked here, cancelled), it goes back.
        if ((verb === "accept" || verb === "reject") && root.demo && root.snapshot) {
          var id = key.split(":")[1]
          var copy = JSON.parse(JSON.stringify(root.snapshot))
          copy.devices = (copy.devices || []).filter(function(d) { return verb === "accept" || d.id !== id || d.pairRequested === true })
          copy.devices.forEach(function(d) {
            if (d.id !== id) return
            if (verb === "accept") { d.pairRequestedByPeer = false; d.paired = true }
            else { d.pairRequested = false; d.verificationKey = "" }
          })
          root.snapshot = copy
        }
        root.setBusy(key, false)
        if (!Model.shownInPlace(verb)) root.report("Demo mode: nothing was sent to the device", false)
        demoClick.destroy()
      }
    }
  }

  // ---- Setup checks (kdeconnect-bridge doctor) ----
  // Run while a panel shows them (nothing connected, or the settings page),
  // and again after every fix.
  property var setupChecks: []
  property int setupWanted: 0          // panels showing the checks right now
  property var setupFixing: ({})
  // This computer's network ("192.168.1.0/24"), from the doctor.
  property string setupNetwork: ""

  // ---- Reconnect: look for devices again (Model.awayState) ----
  // When the last search started (Reconnect, the panel opening on an away
  // device, Add a device), and a clock for "12 min ago" and for
  // when the search has run out.
  property real searchedAt: 0
  property real awayClock: Date.now()

  // `quiet`: a search the panel makes by itself, with no toast.
  function searchDevices(quiet) {
    if (!daemon) return
    searchedAt = Date.now()
    awayClock = searchedAt
    searchRecheck.restart()
    // Demo: the page goes through looking and not found; nothing is sent.
    if (demo) return
    if (quiet) Quickshell.execDetached([bridge, "fix", "search"])
    else fixSetup("search")
  }

  // Opening a panel on a paired device that is away looks for it once, at
  // most once a minute: a lost link is usually found again this way.
  function searchIfAway() {
    if (device && device.paired && device.reachable !== true && Date.now() - searchedAt > 60000) searchDevices(true)
  }

  Timer {
    id: searchRecheck
    interval: Model.SEARCH_MS + 100
    onTriggered: { root.awayClock = Date.now(); root.runDoctor() }
  }
  // "12 min ago" stays right while a panel is open.
  Timer {
    interval: 30000
    repeat: true
    running: root.setupWanted > 0
    onTriggered: root.awayClock = Date.now()
  }

  // Sample checks from a demo (demoSetup) stay until live again; otherwise a
  // demo shows this computer's real checks (they hold no device data).
  property bool demoChecks: false
  function runDoctor() {
    if (doctorProc.running || demoChecks) return
    doctorProc.running = true
  }

  // ---- What a device can do (docs/design/setup.md): its report
  //      (kdeconnect-bridge features), and the steps one click runs ----
  property var featureReports: ({})        // device id -> the bridge's features report
  // Demo: the made-up network From anywhere shows (Model.demoNetwork).
  property string demoNetworkKind: ""
  // Read at most once in 3 s per device (an opening, Settings, a device's
  // page all ask), unless `force` (after a fix, a check again, the screen
  // turning ready, a wait).
  property var featuresReadAt: ({})
  function readFeatures(id, force) {
    if (!id) return
    var now = Date.now()
    if (force !== true && now - (featuresReadAt[String(id)] || 0) < 3000) return
    var at = Object.assign({}, featuresReadAt)
    at[String(id)] = now
    featuresReadAt = at
    // A demo's report follows its device (away in the away demo).
    if (demo) { var d = Object.assign({}, featureReports); var dev = findDevice(id); d[String(id)] = Object.assign(Model.demoFeatures(demoFeature), { reachable: !!dev && dev.reachable === true, network: Model.demoNetwork(demoNetworkKind) }); featureReports = d; return }
    var st = screenOf(String(id))
    var proc = featuresComponent.createObject(root, { device: String(id),
      command: [bridge, "features", String(id)].concat(st && st.state === "ready" ? ["--adb"] : []) })
    proc.running = true
  }
  Component {
    id: featuresComponent
    Process {
      id: featuresProc
      property string device: ""
      stdout: StdioCollector {
        onStreamFinished: {
          var r = null
          try { r = JSON.parse(text) } catch (e) {}
          if (r) { var next = Object.assign({}, root.featureReports); next[featuresProc.device] = r; root.featureReports = next }
          featuresProc.destroy()
        }
      }
    }
  }

  // Root, only for what was shown: a fix that needs the password is
  // described first (rootAsk, the panel's card: why and every action), and
  // runs only on Continue, only that plan (its hash).
  property var rootAsk: null               // { what, why, actions, hash }
  // Demo: the made-up device's features in a state to look at ("ask":
  // notification access missing; "stopped": its notifications stopped
  // arriving), else as set up (Model.demoFeatures).
  property string demoFeature: ""
  property var rootThen: null
  readonly property var rootFixes: ["install", "sshfs", "screen", "firewall", "ready", "tailscale"]
  function isRootFix(what) { return rootFixes.indexOf(what) >= 0 || String(what).indexOf("packages") === 0 }
  // A demo shows the card too (describing changes nothing); Continue there
  // runs nothing.
  function askRoot(what, then) {
    var proc = describeComponent.createObject(root, { what: what, then: then || null,
      command: [bridge, "fix"].concat(String(what).split(" ")).concat(["--describe"]) })
    proc.running = true
  }
  Component {
    id: describeComponent
    Process {
      id: describeProc
      property string what: ""
      property var then: null
      stdout: StdioCollector {
        onStreamFinished: {
          var plan = null
          try { plan = JSON.parse(text) } catch (e) {}
          var then = describeProc.then
          if (!plan || !plan.hash) { root.report(plan && plan.error ? plan.error : "Could not tell what it would do", true); if (then) then(2) }
          // Nothing that needs root (all installed): no password, no card.
          else if ((plan.commands || []).length === 0) root.runRoot(plan, then)
          // Every panel closed while it was described: nothing asked later.
          else if (root.openPanels === 0) { if (then) then(1) }
          else {
            // One card at a time: one still up is answered as cancelled.
            var before = root.rootThen
            root.rootThen = then
            root.rootAsk = plan
            if (before) before(1)
          }
          describeProc.destroy()
        }
      }
    }
  }
  function confirmRoot() {
    var plan = rootAsk, then = rootThen
    rootAsk = null
    rootThen = null
    if (plan) runRoot(plan, then)
  }
  function cancelRoot() {
    var then = rootThen
    rootAsk = null
    rootThen = null
    if (then) then(1)
  }
  function runRoot(plan, then) {
    if (demo) { report("Demo: nothing is changed", false); if (then) then(1); return }
    var key = "fix:" + plan.what
    var next = Object.assign({}, setupFixing)
    next[plan.what] = true
    setupFixing = next
    var proc = actionComponent.createObject(root, { key: key,
      command: [bridge, "fix"].concat(String(plan.what).split(" ")).concat(["--confirm", plan.hash]) })
    proc.exited.connect(function(code) {
      var done = Object.assign({}, root.setupFixing)
      delete done[plan.what]
      root.setupFixing = done
      Qt.callLater(root.runDoctor)
      if (then) then(code)
    })
    proc.running = true
  }

  // One click's steps for a device (Model.featurePlan, Model.fixAllPlan):
  // this computer's installs first, together and after the card; then each
  // step for the device in order. A permission that cannot be granted from
  // here says the switch to turn on, on the device. `key`: busy meanwhile.
  // `left`: the step after them only the user can do ({ text, wait }), shown
  // as pending once they are done.
  // `then(ok)`: called when it is done, ok when every step ran (Fix all
  // chains its devices so).
  // A step marked `fallback` runs only when the one before it failed.
  function runSteps(id, steps, key, left, then) {
    if (!id || !steps || steps.length === 0 || isBusy(key)) { if (then) then(); return }
    // A demo device is made up: nothing reaches the system or a device.
    if (demo) { report("Demo: nothing is changed", false); if (then) then(true); return }
    var feature = String(key).indexOf("feature:") === 0 ? key.slice(8) : ""
    if (feature) setPending(id, feature, null)
    setBusy(key, true)
    var installs = steps.filter(function(s) { return s.fix.verb === "fix" && root.isRootFix(s.fix.what) })
    var rest = steps.filter(function(s) { return installs.indexOf(s) < 0 })
    // Packages in one prompt; the firewall, and Tailscale (Omarchy's
    // installer, in its terminal), each a card of their own.
    var own = ["firewall", "tailscale"]
    var packages = installs.filter(function(s) { return own.indexOf(s.fix.what) < 0 }).map(function(s) { return s.fix.what })
    var queue = []
    if (packages.length > 0) queue.push({ root: packages.length === 1 ? packages[0] : "packages " + packages.join(",") })
    own.forEach(function(w) { if (installs.some(function(s) { return s.fix.what === w })) queue.push({ root: w }) })
    rest.forEach(function(s) { queue.push({ step: s }) })
    var stoppedAt = null, cancelled = false
    function finish() {
      setBusy(key, false)
      if (feature) {
        if (stoppedAt) setPending(id, feature, stoppedAt)
        else if (left) setPending(id, feature, Object.assign({ at: Date.now(), failed: false, tried: "it did what it could; one step is left" }, left))
      }
      if (findDevice(id)) readFeatures(id, true)
      runDoctor()
      if (then) then(!stoppedAt && !cancelled)
    }
    function next(i) {
      if (i >= queue.length) { finish(); return }
      var q = queue[i]
      if (q.root) {
        askRoot(q.root, function(code) {
          if (code === 0) next(i + 1)
          else { if (code !== 1) stoppedAt = { text: "Did not install", wait: false, failed: true, at: Date.now(), tried: "its install did not work" }; else cancelled = true; finish() }
        })
        return
      }
      var s = q.step
      var cmd = s.fix.verb === "device" ? [bridge, "device-fix", s.fix.what, String(id)].concat(s.fix.arg ? [s.fix.arg] : [])
                                        : [bridge, "fix", s.fix.what]
      var proc = actionComponent.createObject(root, { key: key + ":" + i, command: cmd, quietSuccess: i < queue.length - 1 })
      proc.exited.connect(function(code) {
        var after = i + 1
        // Failed with a fallback after it: that one next. Done: past them.
        if (code !== 0 && after < queue.length && queue[after].step && queue[after].step.fallback) { next(after); return }
        if (code === 0) while (after < queue.length && queue[after].step && queue[after].step.fallback) after++
        // A step for the user (a permission adb could not grant): said in
        // the row, and seen when done where it can be.
        if (code !== 0 && s.orAsk) { stoppedAt = { text: s.orAsk, wait: s.fix.what === "grant", waitFor: s.item || "", failed: false, at: Date.now(), tried: "it could not " + s.label.toLowerCase() }; finish(); return }
        if (code !== 0) { stoppedAt = { text: "Did not work: " + s.label, wait: false, failed: true, at: Date.now(), tried: "it did not work at: " + s.label }; finish(); return }
        next(after)
      })
      proc.running = true
    }
    next(0)
  }

  function fixSetup(what) {
    if (!what || setupFixing[what]) return
    // A password: what it is for, shown first (rootAsk).
    if (isRootFix(what)) {
      askRoot(what, function(code) {
        if (what === "screen" && code === 0 && root.device) root.screenSetupNeeded(String(root.device.id))
      })
      return
    }
    var next = Object.assign({}, setupFixing)
    next[what] = true
    setupFixing = next
    var proc = actionComponent.createObject(root, { key: "fix:" + what, command: [bridge, "fix", what] })
    proc.exited.connect(function(code) {
      var done = Object.assign({}, root.setupFixing)
      delete done[what]
      root.setupFixing = done
      Qt.callLater(root.runDoctor)
      // Installed for the screen: the next steps are on the device.
      if (what === "screen" && code === 0 && root.device) root.screenSetupNeeded(String(root.device.id))
    })
    proc.running = true
  }

  Process {
    id: doctorProc
    command: [root.bridge, "doctor"]
    stdout: StdioCollector {
      id: doctorOut
      onStreamFinished: {
        try {
          var report = JSON.parse(text)
          root.setupChecks = report.checks || []
          root.setupNetwork = String(report.network || "")
        } catch (e) {}
      }
    }
  }

  Timer {
    interval: 10000
    repeat: true
    running: root.setupWanted > 0
    triggeredOnStart: true
    onTriggered: root.runDoctor()
  }

  // ---- Screen and apps (kdeconnect-bridge screen*): scrcpy over adb ----
  // Where each device stands, read while its Screen and apps page shows and
  // when the Screen shortcut is pressed; the QR pairing runs while the page
  // shows its code. A demo reads nothing: its states are made up.
  property var screenStates: ({})          // device id -> the bridge's status
  property var screenPairing: null         // { device, phase, qr, message }
  property string screenThen: ""           // a device to open once read (Screen shortcut)
  property bool screenThenDocked: true
  property var screenThenPlace: null       // where the docked window goes: a function, read at launch
  property bool screenThenFit: false       // tiled: its tile takes the device's width (experimental)
  property var screenThenApp: null         // an app to open once read, instead of the screen ({ package, name, sound, pop })
  property string demoScreenKind: "pair"
  signal screenSetupNeeded(string id, var app)
  // Its window is there (a place: the panel closes), or it did not open.
  signal screenOpened(string id)
  signal screenOpenFailed(string id)

  function screenOf(id) { return screenStates[String(id)] || null }
  // Devices whose screen window is open, docked or not: Hyprland's own list
  // of windows (Quickshell keeps it from Hyprland's events, for the shell
  // already: no polling), by the window's title. The Screen shortcut is on
  // meanwhile. Worked out only while a panel shows the shortcut.
  readonly property var screenOpen: {
    if (openPanels === 0) return ({})
    var titles = {}
    var list = Hyprland.toplevels ? Hyprland.toplevels.values : []
    for (var i = 0; i < list.length; i++) titles[String(list[i].title || "")] = true
    var out = {}
    var devs = snapshot && snapshot.devices ? snapshot.devices : []
    for (var j = 0; j < devs.length; j++)
      if (titles[Model.screenTitle(devs[j].name)]) out[String(devs[j].id)] = true
    return out
  }
  function screenIsOpen(id) { return !!id && screenOpen[String(id)] === true }
  function closeScreen(id) {
    if (demo || !id) return
    Quickshell.execDetached([bridge, "screen-close", String(id)])
  }
  // The device's display shape, for the card that becomes its window: the
  // status read now, else the one the bridge kept (screen.json), so the card
  // takes the right shape from the first frame of an opening.
  function screenDisplay(id) {
    var st = screenOf(id)
    if (st && st.display && st.display[0] > 0) return st.display
    var kept = screenKept[String(id)]
    return kept && kept.display && kept.display[0] > 0 ? kept.display : null
  }
  property var screenKept: ({})
  FileView {
    path: (Quickshell.env("XDG_CACHE_HOME") || (Quickshell.env("HOME") + "/.cache")) + "/sceny.devices/screen.json"
    watchChanges: true
    onFileChanged: reload()
    onLoaded: { try { root.screenKept = JSON.parse(text()) || {} } catch (e) {} }
  }
  function setScreen(id, status) {
    // Ready now: its features again, with adb (permissions, notifications).
    var was = screenStates[String(id)]
    if (status && status.state === "ready" && !(was && was.state === "ready") && openPanels > 0) Qt.callLater(function() { root.readFeatures(String(id), true) })
    var next = Object.assign({}, screenStates)
    next[String(id)] = status
    screenStates = next
    if (screenThen !== "" && screenThen === String(id)) {
      screenThen = ""
      var app = screenThenApp
      screenThenApp = null
      if (app) {
        var key = "screen:" + id + ":" + app.package
        if (status && status.state === "ready" && !demo) {
          // Locked: the bridge wakes it and opens the app once it is unlocked.
          if (status.locked) report("Unlock " + Model.deviceLabel(findDevice(id)) + " to open " + app.name + ": it opens as soon as you do", false)
          launchScreen(id, app.package, app.name, false, null, false, app.sound, app.pop)
          return
        }
        if (status && status.state === "ready") { setBusy(key, false); report("Demo: " + app.name + " would open " + (app.pop ? "popped out" : "in a window") + " here", false); return }
        setBusy(key, false)
        screenSetupNeeded(String(id), app)
        return
      }
      if (status && status.state === "ready" && !demo) {
        // Read now: the card has grown to the display's real shape.
        launchScreen(id, "", "", screenThenDocked, screenThenPlace ? screenThenPlace() : null, screenThenFit)
        return
      }
      if (status && status.state === "ready") { demoOpening.device = String(id); demoOpening.restart(); return }
      setBusy("screen", false)
      screenSetupNeeded(String(id))
    }
  }
  function readScreen(id) {
    if (!id) return
    if (demo) { setScreen(id, Model.demoScreen(demoScreenKind)); return }
    if (screenProc.running) return   // its exit reads a device still waiting
    screenProc.device = String(id)
    screenProc.command = [bridge, "screen", String(id)]
    screenProc.running = true
  }
  // The Screen shortcut: its window when the device is ready, else its
  // setup page. The state is read first, so it never acts on a stale one;
  // the tile waits (its ring) from the click until the window is there.
  // `place`: a function giving where the docked window goes ({ rect: the
  // panel's card as it becomes the window, ctx: the chip's place }), read
  // once the state is.
  function pressScreen(id, docked, place, fit) {
    if (!id || isBusy("screen")) return
    setBusy("screen", true)
    screenThen = String(id)
    screenThenDocked = docked !== false
    screenThenPlace = place || null
    screenThenFit = fit === true
    readScreen(id)
  }
  // An app's tile: its window, tiled, once the state is read (as the
  // Screen shortcut), else the screen's setup page. `sound`: "phone" leaves
  // its sound on the device.
  // `pop`: as Omarchy's pop-out (Shift+Enter, Shift+click), else tiled.
  function pressApp(id, app, sound, pop) {
    if (!id || !app) return
    var key = "screen:" + id + ":" + app.package
    if (isBusy(key) || isBusy("screen")) return
    setBusy(key, true)
    screenThen = String(id)
    screenThenApp = { package: app.package, name: app.name, sound: sound || "here", pop: pop === true }
    readScreen(id)
  }
  function openScreen(id, pkg, label, docked) {
    if (demo) { report("Demo: no window opens", false); return }
    var key = pkg ? "screen:" + id + ":" + pkg : "screen"
    if (isBusy(key)) return
    setBusy(key, true)
    launchScreen(id, pkg, label, docked)
  }
  // Busy is already set: the bridge returns once the window is there.
  // `place` ({ rect: { x, y, w, h } on the monitor, ctx }): exactly where
  // it opens, and the chip it stays under when the device turns.
  function placeArgs(place) {
    var out = []
    if (place && place.rect) out.push("--at", [place.rect.x, place.rect.y, place.rect.w, place.rect.h].join(","))
    if (place && place.ctx) out.push("--ctx", JSON.stringify(place.ctx))
    return out
  }
  function launchScreen(id, pkg, label, docked, place, fit, sound, pop) {
    var key = pkg ? "screen:" + id + ":" + pkg : "screen"
    var cmd = [bridge, "screen-open", String(id), pkg || "", label || ""]
    var wasOpen = pkg ? appWindowsOf(id)[label || ""] === true : screenIsOpen(id)
    // The screen: its own last choice, else here, as it always was.
    if (!pkg) sound = Model.screenSound(rememberedSound(id, Model.SCREEN_SOUND))
    sound = Model.soundPlace(sound)
    if (pkg) cmd.push(pop ? "--pop" : "--tiled")
    else if (docked === false) { cmd.push("--tiled"); if (fit) cmd.push("--fit") }
    else cmd = cmd.concat(placeArgs(place))
    if (sound !== "here") cmd.push("--sound", sound)
    if (!pkg) {
      var places = Object.assign({}, screenPlaces)
      places[String(id)] = { ctx: place && place.ctx ? place.ctx : ({}), fit: fit === true }
      screenPlaces = places
    }
    var proc = actionComponent.createObject(root, { key: key, command: cmd, quietSuccess: true })
    // Connecting takes a moment: said by the card or the tile in a panel;
    // with none open (a key), by Omarchy's on-screen display.
    if (openPanels === 0) report("Connecting to " + Model.deviceLabel(findDevice(id)) + "…", false)
    proc.exited.connect(function(code) {
      if (code === 0) {
        // Open already: brought forward, playing where it did.
        if (!wasOpen) root.noteWindowSound(String(id), pkg || Model.SCREEN_SOUND, sound)
        if (pkg) root.appOpened(String(id), pkg)
        root.screenOpened(String(id))
        // Docked, it follows turns under the chip; tiled, its tile takes the
        // device's width as it turns.
        if (!pkg) root.watchScreen(id, place && place.ctx ? place.ctx : ({}), fit === true)
      }
      else root.screenOpenFailed(String(id))
    })
    proc.running = true
  }
  // ---- Apps (#116): each device's apps (kdeconnect-bridge apps, kept a day
  //      in the cache), and their icons as they are read (app-icons) ----
  property var appLists: ({})              // device id -> { state, at, apps: [{ package, name, system, icon, opened }] }
  property var demoAppList: ({ state: "ready", at: 0, apps: Model.demoApps(Date.now()) })
  function appsOf(id) {
    if (demo) return demoAppList
    return id ? (appLists[String(id)] || null) : null
  }
  // The list from the cache at once; read from the device when asked or a
  // day old (and it can be reached). Then the icons not read yet.
  function readApps(id, refresh) {
    if (!id || demo) return
    if (appsProc.running) { if (appsProc.device !== String(id) || refresh) appsAgain = { id: String(id), refresh: refresh === true }; return }
    appsProc.device = String(id)
    appsProc.command = [bridge, "apps", String(id)].concat(refresh ? ["--refresh"] : [])
    appsProc.running = true
  }
  property var appsAgain: null
  // The viewed device's list from the cache as soon as it is known, so the
  // first opening has its Apps section at once (set up here only).
  function warmApps() {
    if (demo || !device || appLists[String(device.id)]) return
    var kept = screenKept[String(device.id)]
    if (kept && kept.paired) readApps(String(device.id))
  }
  onScreenKeptChanged: warmApps()
  // A device's list or its icons being read now (the All apps page's ring).
  function appsReading(id) {
    return !!id && ((appsProc.running && appsProc.device === String(id)) || (iconsProc.running && iconsProc.device === String(id)))
  }
  function setApps(id, list) {
    var next = Object.assign({}, appLists)
    next[String(id)] = list
    appLists = next
  }
  function readIcons(id) {
    var list = appLists[String(id)]
    if (!list || iconsProc.running) return
    var missing = (list.apps || []).filter(function(a) { return a.icon === "" })
    if (missing.length === 0) return
    iconsProc.device = String(id)
    iconsProc.command = [bridge, "app-icons", String(id)]
    iconsProc.running = true
  }
  // Icons come one by one: drawn a few at a time, not a new list per icon.
  property var iconsPending: ({})
  function applyIcons() {
    var id = iconsProc.device
    var list = appLists[id]
    if (!list || Object.keys(iconsPending).length === 0) return
    var pending = iconsPending
    iconsPending = ({})
    setApps(id, Object.assign({}, list, { apps: list.apps.map(function(a) {
      return pending[a.package] !== undefined ? Object.assign({}, a, { icon: pending[a.package] }) : a
    }) }))
  }
  Timer { id: iconsBatch; interval: 400; onTriggered: root.applyIcons() }
  // Out of the recent ones (the ✕ on a recent app, or x): at once here, and
  // in the cache's list of when each was opened, until it opens again.
  function forgetApp(id, pkg) {
    var list = appLists[String(id)]
    if (demo) list = demoAppList
    if (!list || !pkg) return
    var next = Object.assign({}, list, { apps: list.apps.map(function(a) {
      return a.package === pkg ? Object.assign({}, a, { opened: 0 }) : a
    }) })
    if (demo) { demoAppList = next; return }
    setApps(id, next)
    var proc = actionComponent.createObject(root, { key: "forget:" + pkg, command: [bridge, "app-forget", String(id), pkg], quietSuccess: true })
    proc.running = true
  }
  signal appOpened(string id, string pkg)
  onAppOpened: function(id, pkg) {
    var list = appLists[id]
    if (!list) return
    setApps(id, Object.assign({}, list, { apps: list.apps.map(function(a) {
      return a.package === pkg ? Object.assign({}, a, { opened: Date.now() }) : a
    }) }))
  }

  // ---- A window's sound (#129): where each open window's sound plays, and
  //      its volume here. Changed on the window's tile, it opens again in
  //      its place (kdeconnect-bridge screen-sound); the choice is kept per
  //      app in the cache (`sounds` in the apps list), the screen's under
  //      Model.SCREEN_SOUND ----
  property var windowSounds: ({})          // device id -> { package or SCREEN_SOUND: where it plays now }
  property var demoWindows: ({})           // demo: app names whose window is "open"
  property var screenPlaces: ({})          // device id -> { ctx, fit } of its screen's opening (its watcher again)
  // The windows of a device's apps open here (their labels): Hyprland's
  // own list, by title, as screenOpen; worked out only while a panel shows.
  readonly property var appWindowsOpen: {
    if (openPanels === 0) return ({})
    var out = {}
    var devs = snapshot && snapshot.devices ? snapshot.devices : []
    var list = Hyprland.toplevels ? Hyprland.toplevels.values : []
    for (var i = 0; i < list.length; i++) {
      var title = String(list[i].title || "")
      for (var j = 0; j < devs.length; j++) {
        var suffix = " · " + String(devs[j].name || "Device")
        if (title.length > suffix.length && title.slice(-suffix.length) === suffix) {
          var id = String(devs[j].id)
          out[id] = out[id] || {}
          out[id][title.slice(0, -suffix.length)] = true
        }
      }
    }
    return out
  }
  function appWindowsOf(id) {
    if (demo) return demoWindows
    return id ? (appWindowsOpen[String(id)] || ({})) : ({})
  }
  // An app's (or the screen's) own last choice, if it made one.
  function rememberedSound(id, key) {
    var list = demo ? demoAppList : appLists[String(id)]
    var s = list && list.sounds ? list.sounds[key] : undefined
    return Model.SOUND_PLACES.indexOf(s) >= 0 ? s : ""
  }
  function windowSoundOf(id, key) {
    var now = windowSounds[String(id)]
    return now && now[key] ? now[key] : ""
  }
  function noteWindowSound(id, key, sound) {
    var next = Object.assign({}, windowSounds)
    next[String(id)] = Object.assign({}, next[String(id)] || {})
    next[String(id)][key] = sound
    windowSounds = next
  }
  function rememberSound(id, key, sound) {
    var list = demo ? demoAppList : appLists[String(id)]
    var sounds = Object.assign({}, (list && list.sounds) || {})
    sounds[key] = sound
    if (demo) demoAppList = Object.assign({}, demoAppList, { sounds: sounds })
    else if (list) setApps(String(id), Object.assign({}, list, { sounds: sounds }))
  }
  // Demo: an app's window "open" here, to see its tile's badge and card.
  function setDemoWindow(name, open) {
    var next = Object.assign({}, demoWindows)
    if (open) next[name] = true
    else delete next[name]
    demoWindows = next
  }
  // The choice from the window's tile: kept, and the window opened again in
  // its place with it. `pkg` "" is the screen.
  function setWindowSound(id, pkg, label, sound) {
    if (!id || Model.SOUND_PLACES.indexOf(sound) < 0) return
    var key = pkg || Model.SCREEN_SOUND
    var busyKey = "sound:" + id + ":" + key
    if (isBusy(busyKey)) return
    rememberSound(id, key, sound)
    if (demo) {
      noteWindowSound(id, key, sound)
      report("Demo: " + (label || "the screen") + " would open again with its sound " + ({ here: "here", phone: "on the phone", both: "here and on the phone" })[sound], false)
      return
    }
    setBusy(busyKey, true)
    var proc = actionComponent.createObject(root, { key: busyKey, command: [bridge, "screen-sound", String(id), sound, pkg || "", label || ""] })
    proc.exited.connect(function(code) {
      if (code !== 0) return
      root.noteWindowSound(String(id), key, sound)
      root.windowStream = null
      // The screen's watcher goes with its old window: a new one for the new.
      if (!pkg) { rewatch.device = String(id); rewatch.restart() }
    })
    proc.running = true
  }
  Timer {
    id: rewatch
    property string device: ""
    interval: 600
    onTriggered: {
      var p = root.screenPlaces[device]
      if (root.screenIsOpen(device)) root.watchScreen(device, p ? p.ctx : ({}), p ? p.fit === true : false)
    }
  }
  // Its sound here, for the card: { key, found, volume, muted, output }, null
  // while read. Never the device's own volume (that is Now playing's).
  property var windowStream: null
  function readWindowStream(id, pkg, label, extra) {
    var key = String(id) + ":" + (pkg || Model.SCREEN_SOUND)
    if (demo) {
      var was = windowStream && windowStream.key === key ? windowStream : { key: key, found: true, volume: 0.7, muted: false, output: "Speakers" }
      var lvl = extra && extra.level !== undefined ? extra.level : was.volume
      var muted = extra && extra.mute ? (extra.mute === "toggle" ? !was.muted : extra.mute === "on") : was.muted
      windowStream = { key: key, found: true, volume: lvl, muted: muted, output: "Speakers" }
      return
    }
    var cmd = [bridge, "screen-volume", String(id), pkg || "", label || ""]
    if (extra && extra.level !== undefined) cmd.push("--set", Number(extra.level).toFixed(2))
    if (extra && extra.mute) cmd.push("--mute", extra.mute)
    if (streamProc.running) { streamAgain = { id: id, pkg: pkg, label: label, extra: extra }; return }
    streamProc.key = key
    streamProc.command = cmd
    streamProc.running = true
  }
  property var streamAgain: null
  Process {
    id: streamProc
    property string key: ""
    stdout: StdioCollector {
      onStreamFinished: {
        var s = null
        try { s = JSON.parse(text) } catch (e) {}
        if (s) root.windowStream = Object.assign({ key: streamProc.key }, s)
      }
    }
    onExited: if (root.streamAgain) { var a = root.streamAgain; root.streamAgain = null; Qt.callLater(function() { root.readWindowStream(a.id, a.pkg, a.label, a.extra) }) }
  }

  Process {
    id: appsProc
    property string device: ""
    stdout: StdioCollector {
      onStreamFinished: {
        var list = null
        try { list = JSON.parse(text) } catch (e) {}
        if (list && list.apps) {
          root.setApps(appsProc.device, list)
          root.readIcons(appsProc.device)
        }
      }
    }
    onExited: if (root.appsAgain) { var again = root.appsAgain; root.appsAgain = null; Qt.callLater(function() { root.readApps(again.id, again.refresh) }) }
  }
  Process {
    id: iconsProc
    property string device: ""
    stdout: SplitParser {
      onRead: function(line) {
        var e = null
        try { e = JSON.parse(line) } catch (err) {}
        if (!e || !e.package) return
        var next = Object.assign({}, root.iconsPending)
        next[e.package] = e.icon || "none"
        root.iconsPending = next
        if (!iconsBatch.running) iconsBatch.start()
      }
    }
    onExited: root.applyIcons()
  }

  // ---- Re-fit (kdeconnect-bridge screen-watch): the docked window follows
  //      the device's shape; each change comes here for ScreenTurn ----
  property var screenTurn: null            // { kind, angle, from, to, monitor, device, still, at }
  property real turnMotion: 1              // ScreenTurn's pace (slowMotion, for checks)
  property var screenWatchers: ({})        // device id -> its watcher
  // The window shows again under the card (the watcher, once the new
  // picture is there): the card fades then.
  signal screenRevealed(string id)
  // The device's new picture, a still of it, while the card turns.
  signal screenPicture(string id, string path)
  function watchScreen(id, ctx, fit) {
    var st = screenOf(id)
    if (demo || !id || !ctx || !st || !st.serial || screenWatchers[String(id)]) return
    // (ctx is {} for a tiled screen: only a docked one goes under the chip)
    var proc = watchComponent.createObject(root, { device: String(id),
      command: [bridge, "screen-watch", String(id), String(st.serial), "--ctx", JSON.stringify(ctx)].concat(fit ? ["--fit"] : []) })
    var next = Object.assign({}, screenWatchers)
    next[String(id)] = proc
    screenWatchers = next
    proc.running = true
  }
  Component {
    id: watchComponent
    Process {
      id: watchProc
      property string device: ""
      stdout: SplitParser {
        onRead: function(line) {
          try {
            var ev = JSON.parse(line)
            if (ev.ev === "refit") root.screenTurn = Object.assign({ at: Date.now() }, ev)
            else if (ev.ev === "picture") root.screenPicture(String(ev.device || ""), String(ev.still || ""))
            else if (ev.ev === "revealed") {
              // The turn's timing, for diagnosing (no device data).
              console.info("sceny.devices screen turn: new picture after " + ev.picture_ms + " ms, shown after " + ev.shown_ms + " ms")
              root.screenRevealed(String(ev.device || ""))
            }
          } catch (e) {}
        }
      }
      onExited: {
        var next = Object.assign({}, root.screenWatchers)
        delete next[watchProc.device]
        root.screenWatchers = next
        watchProc.destroy()
      }
    }
  }

  // The keyboard to its window, once the panel has let go of it.
  function focusScreen(id) {
    if (demo || !id) return
    Quickshell.execDetached([bridge, "screen-focus", String(id)])
  }
  // Under the bar (docked) or as a window: the open window moves now, the next opens so.
  // `place`: where it docks ({ rect, ctx }, Panel.dockRectFor/dockCtx).
  function dockScreen(id, docked, place) {
    if (demo || !id) return
    var cmd = [bridge, "screen-dock", String(id), docked ? "on" : "off"]
    if (docked) cmd = cmd.concat(placeArgs(place))
    Quickshell.execDetached(cmd)
    if (docked && place) watchScreen(id, place.ctx)
  }
  function startScreenPair(id) {
    if (pairProc.running || demoPairQr.running) return
    screenPairing = { device: String(id), phase: "starting", qr: null, message: "" }
    if (demo) { demoPairQr.running = true; return }
    pairProc.command = [bridge, "screen-pair", String(id)]
    pairProc.running = true
  }
  function stopScreenPair() {
    screenPairing = null
    if (pairProc.running) pairProc.running = false
  }
  function pairingEvent(ev) {
    if (!screenPairing) return
    var p = Object.assign({}, screenPairing)
    if (ev.ev === "qr") { p.phase = "qr"; p.qr = Model.qrGrid(String(ev.ascii || "")) }
    else if (ev.ev === "error") { p.phase = "error"; p.message = String(ev.message || "") }
    else p.phase = String(ev.ev || "")
    screenPairing = p
    if (p.phase === "connected") {
      readScreen(p.device)
      screenPairing = null
    }
  }

  Process {
    id: screenProc
    property string device: ""
    stdout: StdioCollector {
      onStreamFinished: {
        // Unreadable: no state, so a click waiting on it ends (setScreen).
        var st = null
        try { st = JSON.parse(text) } catch (e) {}
        root.setScreen(screenProc.device, st)
      }
    }
    onExited: if (root.screenThen !== "" && root.screenThen !== screenProc.device) Qt.callLater(function() { root.readScreen(root.screenThen) })
  }
  Process {
    id: pairProc
    stdout: SplitParser {
      onRead: function(line) {
        try { root.pairingEvent(JSON.parse(line)) } catch (e) {}
      }
    }
    // Ended without an answer (the code ran out is an error event first).
    onExited: function(code) {
      if (root.screenPairing && root.screenPairing.phase !== "error")
        root.screenPairing = Object.assign({}, root.screenPairing, { phase: "error", message: "Pairing stopped" })
    }
  }
  // A demo's Screen: it waits like a connection, then opens nothing (the
  // card grows back), or with demoScreen "opens" acts as if a window opened
  // (the panel fades as the card, to see the hand-off).
  Timer {
    id: demoOpening
    property string device: ""
    interval: 2000
    onTriggered: {
      root.setBusy("screen", false)
      if (root.demoScreenKind === "opens") { root.screenOpened(device); return }
      root.report("Demo: no window opens", false)
      root.screenOpenFailed(device)
    }
  }
  // The demo's code: made like a real one, for a code nobody can use.
  Process {
    id: demoPairQr
    command: ["qrencode", "-t", "ASCII", "-m", "0", "WIFI:T:ADB;S:sceny-demo;P:demo;;"]
    stdout: StdioCollector {
      onStreamFinished: root.pairingEvent({ ev: "qr", ascii: text })
    }
  }

  // Pairing acts on any device the daemon knows, not only the one followed.
  function runOn(deviceId, verb) {
    var key = verb + ":" + deviceId
    if (!deviceId || isBusy(key)) return
    if (demo) { demoRun(verb, [], key); return }
    setBusy(key, true)
    var proc = actionComponent.createObject(root, {
      key: key,
      wait: { kind: verb, device: String(deviceId) },
      command: [bridge, verb, deviceId]
    })
    proc.running = true
  }
  function pairWith(id) { runOn(id, "pair") }
  function acceptPairing(id) { runOn(id, "accept") }
  function rejectPairing(id) { runOn(id, "reject") }
  function unpair(id) { runOn(id, "unpair") }

  function ring() { run("ring") }
  // A ping, with an optional message the device shows in its notification.
  function ping(message) {
    var m = String(message || "").trim()
    run("ping", m !== "" ? [m] : [], "ping")
  }
  // Typed text or a link: a lone web address opens on the device, anything
  // else lands on its clipboard (Model.linkFor).
  function sendText(text) {
    var t = String(text || "")
    if (t.trim() === "") return
    var url = Model.linkFor(t)
    if (url !== "") run("url", [url], "text")
    else run("text", [t], "text")
  }
  function sendClipboard() { run("clipboard") }
  function sendFiles() { run("share") }
  // Media controls go to one player: the one given, else the playing one.
  function mediaAction(action, player) {
    var p = player || activePlayer
    if (!p) return
    if (action === "Next") { if (p.canGoNext && skipWait(p, action)) p.next() }
    else if (action === "Previous") { if (p.canGoPrevious && skipWait(p, action)) p.previous() }
    else if (p.canTogglePlaying) p.togglePlaying()
  }

  // A skip waits for the next track's title (the phone sends it a moment
  // later); a second press meanwhile is dropped, not queued.
  function skipKey(player, action) { return "skip:" + String(player ? player.dbusName : "") + ":" + action }
  function skipWait(player, action) {
    var key = skipKey(player, action)
    if (isBusy(key)) return false
    startWait(key, { kind: "track", player: player, title: String(player.trackTitle || "") })
    return true
  }

  function seek(player, seconds) {
    if (player && player.canSeek && player.positionSupported) player.position = Math.max(0, seconds)
  }

  // The phone has one media volume; every exported player reports and sets it.
  readonly property var volumePlayer: {
    for (var i = 0; i < players.length; i++) if (players[i].volumeSupported) return players[i]
    return null
  }

  function setVolume(v) {
    if (volumePlayer) volumePlayer.volume = Math.max(0, Math.min(1, v))
  }
  function dismiss(n) { if (n) run("dismiss", [n.id], "dismiss:" + n.id, { kind: "dismiss", note: String(n.id) }) }
  // A reply or an app action usually makes the phone update or drop the
  // notification; the clicked control waits for that, briefly.
  function noteWait(n) { return { kind: "note", note: String(n.id), before: JSON.stringify(Model.findNotification(device, n.id)) } }
  function reply(n, text) {
    var message = String(text || "").trim()
    if (n && n.replyId && message !== "") run("reply", [n.replyId, message], "reply:" + n.id, noteWait(n))
  }
  function notificationAction(n, action) {
    if (n) run("action", [n.id, action], "action:" + n.id + ":" + action, noteWait(n))
  }

  function openMessages() {
    if (device) Quickshell.execDetached(["uwsm-app", "--", "kdeconnect-sms", "--device", device.id])
  }
  function openKdeConnect() {
    Quickshell.execDetached(["uwsm-app", "--", "kdeconnect-app"])
  }
  function startDaemon() {
    Quickshell.execDetached(["systemctl", "--user", "start", "app-org.kde.kdeconnect.daemon@autostart.service"])
  }

  // Text messages (threads, the open conversation), started on first use,
  // or from the start when the bar counts unread messages.
  readonly property var sms: smsService
  // The device whose messages are read: the viewed one when it has text
  // messages, else the last one viewed that had them. A tablet without a SIM
  // never takes the reader away from the phone (nor its unread count).
  property string smsDeviceId: ""
  function followSms() {
    if (device && device.paired && device.can && device.can.sms === true) smsDeviceId = String(device.id)
    else if (smsDeviceId === "" && device && device.paired && !(device.can && device.can.sms === false)) smsDeviceId = String(device.id)
  }
  onDeviceChanged: { followSms(); warmApps() }
  readonly property bool barCountsMessages: profile.barIndicators.indexOf("messages") >= 0
  SmsService {
    id: smsService
    bridge: root.bridge
    deviceId: root.smsDeviceId
    // Keeps running in demo (the view shows made-up threads and ignores it).
    reachable: root.reachable
    // Once started (start() on first use) it stays started.
    wanted: root.barCountsMessages
  }

  // Contacts: the viewed device's cards, read on first use of the page
  // (contacts.opened()). The device is asked for its cards again only on the
  // user's own Refresh (contacts.refresh()).
  readonly property var contacts: contactsService
  ContactsService {
    id: contactsService
    bridge: root.bridge
    deviceId: root.device ? String(root.device.id) : ""
    reachable: root.reachable
    demoPicture: root.demoPicture
  }

  Timer {
    id: statusTimer
    interval: 3500
    onTriggered: { root.actionStatus = ""; root.actionFailed = false }
  }

  // ---- Files: the viewed device's newest photos (#65), files it sent (#37) ----
  // Photos are asked for when a panel opens on the device (at most every
  // 20 s): the bridge mounts its storage (KDE Connect's sftp) and lists
  // them. Per device: { loading, ok, missing, error, photos, at }.
  property var photoState: ({})
  readonly property string demoPicture: smsService.cacheBase + "/demo/picture.jpg"
  // The demo's own gallery pictures, if any were put there (not in the
  // repository): ~/.cache/sceny.devices/demo/gallery/, in name order.
  property var demoGallery: []
  FolderListModel {
    id: demoGalleryFolder
    folder: "file://" + smsService.cacheBase + "/demo/gallery"
    nameFilters: ["*.jpg", "*.jpeg", "*.png", "*.webp"]
    showDirs: false
    sortField: FolderListModel.Name
    onCountChanged: {
      var files = []
      for (var i = 0; i < count; i++) files.push(String(get(i, "filePath")))
      root.demoGallery = files
    }
  }
  readonly property var photoInfo: demo ? { ok: true, photos: Model.demoPhotos(demoPicture, undefined, demoGallery),
      albums: [{ name: "Camera", path: "/demo/DCIM/Camera", count: 842 }, { name: "Screenshots", path: "/demo/Pictures/Screenshots", count: 211 },
               { name: "WhatsApp Images", path: "/demo/WhatsApp Images", count: 96 }, { name: "WhatsApp Video", path: "/demo/WhatsApp Video", count: 41 },
               { name: "Download", path: "/demo/Download", count: 18 }] }
    : (device ? photoState[String(device.id)] || null : null)
  readonly property var photos: photoInfo && photoInfo.ok ? photoInfo.photos : []
  function setPhotoState(id, value) {
    var next = Object.assign({}, photoState)
    next[id] = value
    photoState = next
  }
  function refreshPhotos(force) {
    if (demo || !device || device.reachable !== true || !(device.can && device.can.files)) return
    var id = String(device.id)
    var st = photoState[id]
    if (st && st.loading) return
    // A good list is reused for 20 s. A mount that failed is not asked for
    // again on its own for 10 minutes: each attempt makes KDE Connect pop
    // its error (#100); Try again asks at once. No sshfs asks for no mount,
    // so it is checked on every open.
    if (!force && st && st.ok && Date.now() - st.at < 20000) return
    if (!force && st && !st.ok && st.error && Date.now() - st.at < 600000) return
    setPhotoState(id, Object.assign({}, st || { photos: [] }, { loading: true, at: Date.now() }))
    // The first look since the shell started: the last list at once, from
    // the cache, while the device is read (that takes seconds).
    if (!st) {
      var cached = photosComponent.createObject(root, { deviceId: id, cachedRun: true, command: [bridge, "photos-cached", id] })
      cached.running = true
    }
    var proc = photosComponent.createObject(root, { deviceId: id, command: [bridge, "photos", id] })
    proc.running = true
  }
  // A copy of a photo in Pictures/<device>/; the toast says where.
  function savePhoto(path) {
    if (demo) { report("Demo: a made-up photo", false); return }
    var key = "save:" + String(path)
    if (!device || isBusy(key)) return
    setBusy(key, true)
    var proc = actionComponent.createObject(root, { key: key, command: [bridge, "save-file", path, Model.deviceLabel(device)] })
    proc.running = true
  }
  Component {
    id: photosComponent
    Process {
      id: photosProc
      property string deviceId: ""
      // The cached list: shown only while the real look has not answered.
      property bool cachedRun: false
      stdout: StdioCollector {
        onStreamFinished: {
          var r = null
          try { r = JSON.parse(text) } catch (e) { r = { ok: false, error: "Could not read its storage" } }
          if (photosProc.cachedRun) {
            var now = root.photoState[photosProc.deviceId]
            if (r.ok && now && now.loading && !now.ok)
              root.setPhotoState(photosProc.deviceId, Object.assign({}, now, { ok: true, photos: r.photos, cached: true }))
          } else {
            root.setPhotoState(photosProc.deviceId, Object.assign({ photos: [] }, r, { loading: false, at: Date.now() }))
          }
          photosProc.destroy()
        }
      }
    }
  }

  // Received files: from the snapshot, less the ones dismissed here (they
  // leave the bridge's list at its next snapshot).
  property var dismissedFiles: ({})
  readonly property var received: {
    if (demo) return Model.demoReceived().filter(function(r) { return !dismissedFiles[r.path] })
    var list = device && device.received ? device.received : []
    return list.filter(function(r) { return !dismissedFiles[r.path] })
  }
  function dismissReceived(entry) {
    if (!entry || !device) return
    var next = Object.assign({}, dismissedFiles)
    next[entry.path] = true
    dismissedFiles = next
    if (!demo) Quickshell.execDetached([bridge, "received-dismiss", String(device.id), entry.path])
  }
  // Opening, as Omarchy's own panels do: through uwsm-app, so the app runs
  // as the user's (its own scope, like one from the launcher), not as a
  // child of the shell. The bridge picks the app as GIO does, as Files does
  // (a type's parents count: JSON is text), where xdg-open looks up the
  // exact type only and opens nothing; with no app for the type, it shows
  // the file in Files and the toast says so. Show in folder is Files with
  // the file selected.
  // `fromDevice`: a file the device sent (a picture opens as a sandboxed copy).
  function openPath(path, fromDevice) {
    if (!path) return
    var cmd = [bridge, "open-file", String(path)]
    if (fromDevice === true) cmd.push("--from-device")
    var proc = actionComponent.createObject(root, { key: "open", command: cmd })
    proc.running = true
  }
  // A track's art from the phone, shown only as a safe copy the bridge makes
  // (decoded in glycin's sandbox): url -> file:// of the copy, "" while there
  // is none. Asked once per url; a url that is not a local file has none.
  property var safeArt: ({})
  function artFor(url) { return safeArt[String(url || "")] || "" }
  function requestArt(url) {
    var u = String(url || "")
    if (u === "" || safeArt[u] !== undefined) return
    var next = Object.keys(safeArt).length > 200 ? {} : Object.assign({}, safeArt)
    next[u] = ""
    safeArt = next
    if (u.indexOf("file://") !== 0) return
    var proc = artComponent.createObject(root, { url: u, command: [bridge, "safe-image", decodeURIComponent(u.slice(7)), "512"] })
    proc.running = true
  }
  Component {
    id: artComponent
    Process {
      id: artProc
      property string url: ""
      stdout: StdioCollector {
        onStreamFinished: {
          var path = String(text || "").trim()
          var next = Object.assign({}, root.safeArt)
          next[artProc.url] = path !== "" ? "file://" + encodeURI(path) : ""
          root.safeArt = next
          artProc.destroy()
        }
      }
    }
  }

  // A file on the device: copied here first (the bridge keeps a few in the
  // cache), then opened, so the app reads a local file: a video plays at
  // its pace, not the network's. The tile shows a ring meanwhile.
  function openFromDevice(path) {
    if (!path) return
    var key = "open:" + String(path)
    if (isBusy(key)) return
    setBusy(key, true)
    var proc = actionComponent.createObject(root, { key: key, command: [bridge, "open-file", String(path), "--local"] })
    proc.running = true
  }
  function revealPath(path) {
    if (!path) return
    Quickshell.execDetached(["uwsm-app", "--", "nautilus", "--select", Model.fileUri(path)])
  }

  // The file on the clipboard (an image as image data).
  function copyFile(path) {
    if (demo) { report("Copied", false); return }
    var key = "copy:" + String(path)
    if (isBusy(key)) return
    setBusy(key, true)
    var proc = actionComponent.createObject(root, { key: key, command: [bridge, "copy-file", path] })
    proc.running = true
  }

  Component {
    id: actionComponent

    Process {
      id: proc
      property string key: ""
      property var wait: null
      property int exitCode: -1
      // Its success says nothing worth a toast (the screen's window opening
      // is the answer itself); a failure is still said.
      property bool quietSuccess: false

      stdout: StdioCollector { id: procOut }
      stderr: StdioCollector { id: procErr }

      function finish() {
        var out = String(procOut.text || "").trim()
        var err = String(procErr.text || "").trim()
        // Waiting starts before busy ends, so the ring does not blink between.
        // Its line waits too: "Dismissed" shows when the notification goes.
        if (proc.exitCode === 0 && proc.wait) {
          root.startWait(proc.key, Object.assign({ said: out }, proc.wait))
          root.setBusy(proc.key, false)
          proc.destroy()
          return
        }
        root.setBusy(proc.key, false)
        if (proc.exitCode === 0) { if (!proc.quietSuccess) root.report(out, false) }
        else if (proc.exitCode === 1) root.report(err || out || "Cancelled", false)
        else root.report(err || out || "That did not work", true)
        proc.destroy()
      }

      // The collectors settle just after the exit signal, so read them on the
      // next turn of the event loop rather than inside it.
      onExited: function(code) {
        proc.exitCode = code
        Qt.callLater(proc.finish)
      }
    }
  }

  Process {
    id: watcher
    command: [root.bridge, "watch"]
    running: true

    stdout: SplitParser {
      onRead: function(line) {
        try {
          root.liveSnapshot = JSON.parse(line)
          if (!root.demo) root.snapshot = root.liveSnapshot
          root.watchError = ""
          restart.interval = 1000
        } catch (e) {
          root.watchError = "Unreadable update from kdeconnect-bridge"
        }
      }
    }
    stderr: SplitParser {
      onRead: function(line) { if (String(line).trim() !== "") root.watchError = String(line).trim() }
    }

    // A dead watcher would freeze the bar on its last picture, so it comes
    // back on its own, backing off from 1 s to 30 s if it keeps dying.
    onExited: function(code) {
      restart.interval = Math.min(30000, restart.interval * 2)
      restart.restart()
    }
  }

  Timer {
    id: restart
    interval: 1000
    onTriggered: watcher.running = true
  }
}
