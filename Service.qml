import QtQuick
import Quickshell
import Quickshell.Io
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

  function showDemo(kind) {
    demo = true
    snapshot = Model.demoSnapshot(liveSnapshot || snapshot, kind || "")
    smsService.showDemo()
  }

  function showLive() {
    demo = false
    snapshot = liveSnapshot
    smsService.showLive()
  }
  readonly property var device: Model.pickDevice(snapshot, String(setting("deviceId", "")))
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
        if (p && Model.isPhonePlayer(p.dbusName, p.identity, deviceName)) out.push(p)
      }
      out.sort(function(a, b) { return String(a.identity || "").localeCompare(String(b.identity || "")) })
    }
    var same = out.length === players.length
    for (var j = 0; same && j < out.length; j++) same = out[j] === players[j]
    if (!same) players = out
  }

  onDeviceNameChanged: updatePlayers()
  onReachableChanged: updatePlayers()
  Component.onCompleted: updatePlayers()

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

  // ---- Calls (Model.callState): the phone ringing, or a call missed ----
  // KDE Connect never says a call ended, so time decides when ringing stops
  // counting; `clock` is re-read when the call's state can next change.
  readonly property bool showCalls: Model.layoutFlag(setting("showCalls", true))
  property real clock: Date.now()
  // The `at` of the last call the user closed. Memory only: after a restart
  // the bridge has forgotten the call too.
  property real callClosedAt: 0
  readonly property var call: showCalls ? Model.callState(device, clock, callClosedAt) : null
  readonly property var pendingCall: device && device.call ? device.call : null
  onPendingCallChanged: clock = Date.now()

  function closeCall() { if (call) callClosedAt = call.at }

  // On for each ring of the beat (Model.ringPhases): the pill glows ring,
  // ring, rest, in step with the card's waves.
  readonly property bool ringing: !!call && call.state === "ringing"
  readonly property var ringPhases: Model.ringPhases()
  property int ringPhase: 0
  readonly property bool ringLit: ringing && ringPhases[ringPhase].lit
  Timer {
    running: root.ringing
    repeat: true
    interval: root.ringPhases[root.ringPhase].ms
    onRunningChanged: root.ringPhase = 0
    onTriggered: root.ringPhase = (root.ringPhase + 1) % root.ringPhases.length
  }

  // The phone's dialer on the number (a tel: link through KDE Connect's
  // share): the call itself is the user's tap on the phone.
  function callBack(number) {
    var n = String(number || "").trim()
    if (n !== "") run("dial", [n], "dial")
  }

  Timer {
    // Wakes when the shown call runs out (plus a beat), not every second.
    readonly property real due: Model.callExpiresIn(Model.callState(root.device, root.clock, root.callClosedAt), root.clock)
    interval: Math.max(250, due + 250)
    running: due >= 0
    onTriggered: root.clock = Date.now()
  }

  // Demo mode rings (or misses) a made-up caller, over the demo snapshot.
  function showDemoCall(kind) {
    if (!demo) showDemo("")
    var copy = JSON.parse(JSON.stringify(snapshot || {}))
    var d = Model.pickDevice(copy, "")
    if (!d) return
    d.call = Model.demoCall(kind, Date.now())
    callClosedAt = 0
    snapshot = copy
  }

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
        if (w.said) report(w.said, false)
        continue
      }
      if (now > w.until) {
        changed = true
        if (w.fail !== "") report(w.fail, true)
        else if (w.said) report(w.said, false)
        continue
      }
      next[key] = w
    }
    if (changed) waits = next
  }

  onSnapshotChanged: if (Object.keys(waits).length > 0) checkWaits()

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
      interval: 900
      running: true
      onTriggered: {
        if ((verb === "dismiss" || verb === "action") && root.demo && root.snapshot)
          root.snapshot = Model.withoutNotification(root.snapshot, note)
        root.setBusy(key, false)
        root.report("Demo mode: nothing was sent to the device", false)
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

  function runDoctor() {
    if (doctorProc.running) return
    doctorProc.running = true
  }

  function fixSetup(what) {
    if (!what || setupFixing[what]) return
    var next = Object.assign({}, setupFixing)
    next[what] = true
    setupFixing = next
    var proc = actionComponent.createObject(root, { key: "fix:" + what, command: [bridge, "fix", what] })
    proc.exited.connect(function() {
      var done = Object.assign({}, root.setupFixing)
      delete done[what]
      root.setupFixing = done
      Qt.callLater(root.runDoctor)
    })
    proc.running = true
  }

  Process {
    id: doctorProc
    command: [root.bridge, "doctor"]
    stdout: StdioCollector {
      id: doctorOut
      onStreamFinished: {
        try { root.setupChecks = JSON.parse(text).checks || [] } catch (e) {}
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
  readonly property bool barCountsMessages: Model.normalizeBarIndicators(settings ? settings.barIndicators : null).indexOf("messages") >= 0
  SmsService {
    id: smsService
    bridge: root.bridge
    deviceId: root.device && root.device.paired ? String(root.device.id) : ""
    // Keeps running in demo (the view shows made-up threads and ignores it).
    reachable: root.reachable
    // Once started (start() on first use) it stays started.
    wanted: root.barCountsMessages
  }

  Timer {
    id: statusTimer
    interval: 3500
    onTriggered: { root.actionStatus = ""; root.actionFailed = false }
  }

  Component {
    id: actionComponent

    Process {
      id: proc
      property string key: ""
      property var wait: null
      property int exitCode: -1

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
        if (proc.exitCode === 0) root.report(out, false)
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
