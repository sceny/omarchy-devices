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

  // A short line about the last click: "Ringing Pixel 8",
  // "Sending 2 files", or the reason it failed. Clears itself.
  property string actionStatus: ""
  property bool actionFailed: false

  // verb (or verb:notification) -> true while that action runs, so a second
  // click on the same thing waits instead of stacking up.
  property var busy: ({})

  function isBusy(key) { return busy[key] === true }

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

  function run(verb, args, key) {
    if (!device || !device.reachable) return
    if (demo) { report("Demo mode: nothing was sent to the device", false); return }
    key = key || verb
    if (busy[key]) return
    setBusy(key, true)
    var proc = actionComponent.createObject(root, {
      key: key,
      command: [bridge, verb, device.id].concat(args || [])
    })
    proc.running = true
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
    if (demo) { report("Demo mode: nothing was sent to the device", false); return }
    var key = verb + ":" + deviceId
    if (!deviceId || busy[key]) return
    setBusy(key, true)
    var proc = actionComponent.createObject(root, { key: key, command: [bridge, verb, deviceId] })
    proc.running = true
  }
  function pairWith(id) { runOn(id, "pair") }
  function acceptPairing(id) { runOn(id, "accept") }
  function rejectPairing(id) { runOn(id, "reject") }
  function unpair(id) { runOn(id, "unpair") }

  function ring() { run("ring") }
  function ping() { run("ping") }
  function sendClipboard() { run("clipboard") }
  function sendFiles() { run("share") }
  // Media controls go to one player: the one given, else the playing one.
  function mediaAction(action, player) {
    var p = player || activePlayer
    if (!p) return
    if (action === "Next") { if (p.canGoNext) p.next() }
    else if (action === "Previous") { if (p.canGoPrevious) p.previous() }
    else if (p.canTogglePlaying) p.togglePlaying()
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
  function dismiss(n) { if (n) run("dismiss", [n.id], "dismiss:" + n.id) }
  function reply(n, text) {
    var message = String(text || "").trim()
    if (n && n.replyId && message !== "") run("reply", [n.replyId, message], "reply:" + n.id)
  }
  function notificationAction(n, action) { if (n) run("action", [n.id, action], "action:" + n.id) }

  function openMessages() {
    if (device) Quickshell.execDetached(["uwsm-app", "--", "kdeconnect-sms", "--device", device.id])
  }
  function openKdeConnect() {
    Quickshell.execDetached(["uwsm-app", "--", "kdeconnect-app"])
  }
  function startDaemon() {
    Quickshell.execDetached(["systemctl", "--user", "start", "app-org.kde.kdeconnect.daemon@autostart.service"])
  }

  // Text messages (threads, the open conversation), started on first use.
  readonly property var sms: smsService
  SmsService {
    id: smsService
    bridge: root.bridge
    deviceId: root.device && root.device.paired ? String(root.device.id) : ""
    // Keeps running in demo (the view shows made-up threads and ignores it).
    reachable: root.reachable
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
      property int exitCode: -1

      stdout: StdioCollector { id: procOut }
      stderr: StdioCollector { id: procErr }

      function finish() {
        var out = String(procOut.text || "").trim()
        var err = String(procErr.text || "").trim()
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
