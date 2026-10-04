import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Window as QW
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model

// The phone panel: who is connected and how charged, four quick actions, what
// the phone is playing, and the phone's notifications with reply and dismiss.
//
// Keyboard: j/k (or arrows) move between rows, h/l along the shortcuts or the
// media carousel, Enter activates (play/pause on media), [/] skip track, x
// dismisses a notification, r replies, -/= phone volume, ,/. seek 10 s, s opens
// settings. Esc closes (or leaves settings), Tab moves to the next bar panel.
Panel {
  id: root
  moduleName: "sceny.devices"
  ipcTarget: "sceny.devices"
  manageIpc: false

  property var anchorItem: null
  property var hostWidget: null
  property var phone: null
  property bool openedFromHotkey: false

  readonly property var barIdentity: hostWidget || root
  readonly property var snapshot: phone ? phone.snapshot : null
  readonly property var device: phone ? phone.device : null
  readonly property bool reachable: phone ? phone.reachable : false
  readonly property var players: phone ? phone.players : []
  readonly property var volumePlayer: phone ? phone.volumePlayer : null
  readonly property var notifications: phone ? phone.notifications : []
  readonly property var can: device && device.can ? device.can : ({})

  // Layout settings, from this widget's shell.json entry. Written only by the
  // settings page (persistSettings), read everywhere else.
  // The viewed device's profile (Service.profile): its sections, their
  // order and its shortcuts, its own changes over the defaults.
  readonly property var profile: phone ? phone.profile : Model.resolveProfile(Model.readSettings(settings), null, true)
  readonly property bool showShortcuts: profile.showShortcuts
  readonly property bool showMedia: profile.showMedia
  readonly property bool showNotifications: profile.showNotifications
  readonly property bool showPhotos: profile.showPhotos
  readonly property bool showReceived: profile.showReceived
  // Files: the device's newest photos (#65) and the files it sent (#37).
  // The photos drawn: the device's, except when they go to none. Then the
  // tiles fade, the section folds closed, and only then are they gone (no
  // blink, no jump, no empty section left open).
  readonly property var livePhotos: phone ? phone.photos : []
  property var shownPhotos: []
  property bool photosFading: false
  property bool photosClosing: false
  onLivePhotosChanged: {
    if (livePhotos.length > 0) {
      photoLeave.stop(); photoClose.stop()
      photosFading = false; photosClosing = false
      // The same photos keep their tiles: a read starting or ending gives a
      // new list, and new tiles would restart a tile's ring and reload its
      // picture (a blink).
      if (Model.photosKey(livePhotos) !== Model.photosKey(shownPhotos)) shownPhotos = livePhotos
    } else if (shownPhotos.length > 0 && !photosFading) {
      photosFading = true
      photoLeave.restart()
    }
  }
  Timer {
    id: photoLeave
    interval: Model.MOTION.outMs * root.motion
    onTriggered: {
      // Nothing else in the section: it folds closed before it goes.
      if (!root.photosHint) { root.photosClosing = true; photoClose.restart() }
      else { root.shownPhotos = []; root.photosFading = false }
    }
  }
  Timer {
    id: photoClose
    interval: Model.MOTION.inMs * root.motion
    onTriggered: { root.shownPhotos = []; root.photosFading = false; root.photosClosing = false }
  }
  readonly property var photos: shownPhotos
  // The tiles, one per photo, changed in place (Model.listOps) so they glide.
  ListModel { id: photoModel }
  onShownPhotosChanged: {
    var keys = shownPhotos.map(Model.photoIdentity), old = []
    for (var i = 0; i < photoModel.count; i++) old.push(photoModel.get(i).key)
    Model.listOps(old, keys).forEach(function(o) {
      if (o.op === "remove") photoModel.remove(o.at, 1)
      else if (o.op === "move") photoModel.move(o.from, o.to, 1)
      else photoModel.insert(o.at, { key: o.key, json: JSON.stringify(shownPhotos[o.at]) })
    })
    for (var j = 0; j < shownPhotos.length; j++) {
      var json = JSON.stringify(shownPhotos[j])
      if (photoModel.get(j).json !== json) photoModel.setProperty(j, "json", json)
    }
  }
  readonly property var photoInfo: phone ? phone.photoInfo : null
  readonly property var received: phone ? phone.received : []
  // Something to show, or a step that makes photos possible (sshfs, the
  // phone's storage permission).
  readonly property bool photosHint: !!photoInfo && photoInfo.ok === false
  readonly property bool hasPhotos: photos.length > 0 || photosHint
  // The keyboard cursor in Files: the photos (a grid of four), then the
  // received files.
  property int photoIndex: 0
  property int receivedIndex: 0
  readonly property int photoColumns: 4
  // Opening a place (an album, a file's folder, KDE Connect) closes the
  // panel: the user goes on in that window. Opening an item (a photo, a
  // received file) keeps it open, to open the next one.
  function openPhotoFolder(path) {
    if (phone && phone.demo) { phone.report("Demo: made-up photos", false); return }
    if (phone) { phone.openPath(path); root.close() }
  }
  function openPhoto(photo) {
    if (!photo) return
    if (photo.demo) { if (phone) phone.report("Demo: a made-up photo", false); return }
    if (phone) phone.openFromDevice(photo.path)
  }
  function openReceived(entry) {
    if (!entry) return
    if (String(entry.path).indexOf("/demo/") === 0) { if (phone) phone.report("Demo: a made-up file", false); return }
    if (phone) phone.openPath(entry.path, true)
  }
  function showReceivedFolder(entry) {
    if (!entry) return
    if (String(entry.path).indexOf("/demo/") === 0) { if (phone) phone.report("Demo: a made-up file", false); return }
    if (phone) { phone.revealPath(entry.path); root.close() }
  }
  readonly property var shortcutOrder: profile.shortcuts
  // What the bar pill shows beside the glyph (Bar settings; BarWidget draws it).
  readonly property var barIndicators: Model.normalizeBarIndicators(setting("barIndicators", null))
  readonly property bool batteryLowOnly: Model.layoutFlag(setting("batteryLowOnly", true))
  // The order of the sections under the header (Layout settings).
  readonly property var sectionOrder: profile.sectionOrder
  // Several devices: tabs in the header (Service.panelDevices).
  readonly property var tabDevices: phone ? phone.panelDevices : []
  readonly property bool manyDevices: tabDevices.length > 1

  property bool settingsOpen: false
  // Text messages: a two-pane view in place of the phone view, in a wider panel.
  property bool messagesOpen: false
  readonly property bool mainView: !settingsOpen && !messagesOpen

  // What the page area shows. It trails settingsOpen/messagesOpen by half a
  // transition, so the old page can leave before the new one arrives, and the
  // panel resizes (messages is wider) while nothing is on screen: the panel
  // container only fades, and resizing its surface every frame would stutter.
  property bool showSettings: false
  property bool showMessages: false
  readonly property bool showMain: !showSettings && !showMessages
  // Each page of Settings (the list, Connection, Add a device, a device's
  // page) is a page of its own, so moving between them animates too: the
  // scope opened is the target (targetScope), and the one shown
  // (settingsScope) changes with the page, at the change's midpoint.
  readonly property string targetPage: messagesOpen ? "messages" : (settingsOpen ? "settings/" + targetScope : "main")
  readonly property string shownPage: showMessages ? "messages" : (showSettings ? "settings/" + settingsScope : "main")
  // Back (the new page from the left) to the main page, and to the Settings
  // list from one of its pages; forward otherwise.
  function directionTo(target) {
    if (target === "main") return -1
    return target === "settings/root" && shownPage.indexOf("settings/") === 0 ? -1 : 1
  }
  // +1 moves forward (the new page comes in from the right), -1 goes back.
  property int pageDirection: 1
  // Stretches every transition; 1 normally. The `slowMotion` IPC sets it, so
  // a transition can be caught mid-way in a screenshot.
  property real motion: 1

  function applyShownPage() {
    showSettings = settingsOpen
    showMessages = messagesOpen
    settingsScope = targetScope
  }

  // Land on the target page at once, no transition (the panel opening).
  // Apply first: stopping runs onStopped, which only restarts when the
  // shown page is still behind.
  function snapPage() {
    applyShownPage()
    pageSwap.stop()
    pageHost.opacity = 1
    pageHost.slide = 0
  }

  onTargetPageChanged: {
    // Leaving the preview runs its own change (previewSwap).
    if (previewLeaving) return
    if (targetPage === shownPage && !pageSwap.running) return
    // Closed, or just opening: nothing to show off, the panel fades in anyway.
    if (!opened) { snapPage(); return }
    pageDirection = directionTo(targetPage)
    pageSwap.restart()
  }

  // The card (the panel's box) follows the page's size with an animation.
  // KeyboardPanel is a full-screen layer surface and the card an item inside
  // it, so this costs no window resize. Snapping it at the swap was the jump
  // seen mid-transition on the way to and from messages (the width) and back
  // from settings (the height). Only page changes animate it: a fold already
  // animates the height itself, and a second animation on top would lag.
  // The page's width, plus its margins on both sides (pageGutter).
  readonly property real targetCardWidth: panel.fittedContentWidth((showMessages ? Style.space(880) : Style.space(400)) + 2 * pageGutter)
  // The margin every page keeps on both sides, wide enough for the scroll
  // bar (about 7 px, drawn at the right edge) and a gap: when the bar shows,
  // nothing is under it, and nothing shifts when it comes or goes.
  readonly property real pageGutter: Style.space(12)
  // No cap of our own: KeyboardPanel already clamps to what fits on screen.
  readonly property real targetCardHeight: panel.fittedContentHeight(column.implicitHeight)
  property real cardWidth: targetCardWidth
  property real cardHeight: targetCardHeight
  Behavior on cardWidth {
    enabled: pageSwap.running || deviceSwap.running || previewSwap.running
    NumberAnimation { duration: Model.MOTION.inMs * root.motion; easing.type: Easing.OutCubic }
  }
  Behavior on cardHeight {
    enabled: pageSwap.running || deviceSwap.running || previewSwap.running
    NumberAnimation { duration: Model.MOTION.inMs * root.motion; easing.type: Easing.OutCubic }
  }

  SequentialAnimation {
    id: pageSwap
    readonly property real travel: Style.space(28)
    ParallelAnimation {
      NumberAnimation { target: pageHost; property: "opacity"; to: 0; duration: Model.MOTION.outMs * root.motion; easing.type: Easing.InCubic }
      NumberAnimation { target: pageHost; property: "slide"; to: -root.pageDirection * pageSwap.travel; duration: Model.MOTION.outMs * root.motion; easing.type: Easing.InCubic }
    }
    ScriptAction {
      script: {
        root.applyShownPage()
        pageHost.slide = root.pageDirection * pageSwap.travel
        if (panelFlick) panelFlick.contentY = 0
      }
    }
    ParallelAnimation {
      NumberAnimation { target: pageHost; property: "opacity"; to: 1; duration: Model.MOTION.inMs * root.motion; easing.type: Easing.OutCubic }
      NumberAnimation { target: pageHost; property: "slide"; to: 0; duration: Model.MOTION.inMs * root.motion; easing.type: Easing.OutCubic }
    }
    // A change of mind mid-way (Esc right after opening) lands too.
    onStopped: if (root.shownPage !== root.targetPage) { root.pageDirection = root.directionTo(root.targetPage); pageSwap.restart() }
  }

  // Leaving the preview (backToSetup): the still of the old page fades and
  // slides out, the real page and the panel's size take over at the
  // midpoint, and the page comes in: the same beat as pageSwap.
  SequentialAnimation {
    id: previewSwap
    ParallelAnimation {
      NumberAnimation { target: previewStripCard; property: "opacity"; from: 1; to: 0; duration: Model.MOTION.outMs * root.motion; easing.type: Easing.InCubic }
      NumberAnimation { target: pageStill; property: "opacity"; from: 1; to: 0; duration: Model.MOTION.outMs * root.motion; easing.type: Easing.InCubic }
      NumberAnimation { target: pageStill; property: "x"; from: 0; to: pageSwap.travel; duration: Model.MOTION.outMs * root.motion; easing.type: Easing.InCubic }
    }
    ScriptAction {
      script: {
        pageStill.visible = false
        pageStill.source = ""
        pageStill.x = 0
        pageStill.opacity = 1
        previewStrip.held = false
        root.applyShownPage()
        root.cardWidth = Qt.binding(function() { return root.targetCardWidth })
        root.cardHeight = Qt.binding(function() { return root.targetCardHeight })
        pageColumn.opacity = 1
        pageHost.opacity = 0
        pageHost.slide = -pageSwap.travel
        if (panelFlick) panelFlick.contentY = 0
      }
    }
    ParallelAnimation {
      NumberAnimation { target: pageHost; property: "opacity"; to: 1; duration: Model.MOTION.inMs * root.motion; easing.type: Easing.OutCubic }
      NumberAnimation { target: pageHost; property: "slide"; to: 0; duration: Model.MOTION.inMs * root.motion; easing.type: Easing.OutCubic }
    }
    onStopped: {
      root.previewLeaving = false
      previewStrip.held = false
      previewStripCard.opacity = 1
      pageStill.visible = false
      pageStill.source = ""
      pageColumn.opacity = 1
      pageHost.opacity = 1
      pageHost.slide = 0
      root.applyShownPage()
      root.cardWidth = Qt.binding(function() { return root.targetCardWidth })
      root.cardHeight = Qt.binding(function() { return root.targetCardHeight })
    }
  }

  // The same beat for changing the viewed device (switchDevice).
  SequentialAnimation {
    id: deviceSwap
    ParallelAnimation {
      NumberAnimation { target: pageHost; property: "opacity"; to: 0; duration: Model.MOTION.outMs * root.motion; easing.type: Easing.InCubic }
      NumberAnimation { target: pageHost; property: "slide"; to: -root.deviceDirection * pageSwap.travel; duration: Model.MOTION.outMs * root.motion; easing.type: Easing.InCubic }
    }
    ScriptAction {
      script: {
        root.applyDevice()
        pageHost.slide = root.deviceDirection * pageSwap.travel
        if (panelFlick) panelFlick.contentY = 0
      }
    }
    ParallelAnimation {
      NumberAnimation { target: pageHost; property: "opacity"; to: 1; duration: Model.MOTION.inMs * root.motion; easing.type: Easing.OutCubic }
      NumberAnimation { target: pageHost; property: "slide"; to: 0; duration: Model.MOTION.inMs * root.motion; easing.type: Easing.OutCubic }
    }
    // Stopped mid-way (the panel closing): land where it was going.
    onStopped: { if (root.pendingDevice !== "") root.applyDevice(); pageHost.opacity = 1; pageHost.slide = 0 }
  }
  readonly property var sms: phone ? phone.sms : null

  // What a click came to ("Clipboard sent", or why it failed), shown as a
  // toast over the panel: it never pushes the content down.
  readonly property string toastText: phone && phone.actionStatus !== "" ? phone.actionStatus
    : (sms && sms.lastError !== "" ? sms.lastError : "")
  readonly property bool toastFailed: phone && phone.actionStatus !== "" ? phone.actionFailed : (sms && sms.lastError !== "")

  // The setup checks run while a panel shows them: nothing connected, or
  // the settings page open.
  // Always while open: the gear's dot says when a check on this computer fails.
  readonly property bool wantsSetup: opened
  property bool countedSetup: false
  onWantsSetupChanged: {
    if (!phone || wantsSetup === countedSetup) return
    phone.setupWanted = Math.max(0, phone.setupWanted + (wantsSetup ? 1 : -1))
    countedSetup = wantsSetup
  }

  // The service sends results to Omarchy's on-screen display while no panel
  // is open (the file chooser closes it, for one).
  onOpenedChanged: {
    if (phone) phone.openPanels = Math.max(0, phone.openPanels + (opened ? 1 : -1))
    settled = false
    if (opened) settleTimer.restart()
    // Where it was, for a reopen within Model.KEEP_PLACE_MS (onOpened).
    else leftPlace = { at: Date.now(), settingsOpen: settingsOpen, messagesOpen: messagesOpen, scope: targetScope,
                       device: device ? String(device.id) : "", y: panelFlick ? panelFlick.contentY : 0 }
  }
  property var leftPlace: null
  // The page's keyboard cursor, drawn once (CursorGlide, in pageHost).
  property Item cursorGlide: null

  // Size animations (folds, the carousel, the cover) run for the user's own
  // changes only. A hidden page has no height, so while a page appears (or
  // the panel opens) every section would otherwise grow from nothing: that
  // made the way back from settings and messages stutter.
  property bool settled: false
  Timer {
    id: settleTimer
    interval: Model.MOTION.inMs * root.motion + 40
    onTriggered: root.settled = root.opened && !pageSwap.running && !deviceSwap.running
  }
  Connections {
    target: pageSwap
    function onRunningChanged() {
      root.settled = false
      if (!pageSwap.running) settleTimer.restart()
    }
  }
  Connections {
    target: deviceSwap
    function onRunningChanged() {
      root.settled = false
      if (!deviceSwap.running) settleTimer.restart()
    }
  }
  Component.onDestruction: {
    if (opened && phone) phone.openPanels = Math.max(0, phone.openPanels - 1)
    if (countedSetup && phone) phone.setupWanted = Math.max(0, phone.setupWanted - 1)
  }
  property int settingsIndex: 0

  // ---- Settings for devices ----
  // What the settings page edits: "root" (the device list, or with one
  // device the whole flat page), "defaults", or a device's id (its page).
  property string settingsScope: "root"
  property string targetScope: "root"
  readonly property var pairedDevices: phone ? phone.ordered : []
  readonly property bool singleDevice: pairedDevices.length <= 1
  readonly property var scopeDevice: {
    var id = settingsScope === "root" && singleDevice && pairedDevices.length === 1 ? String(pairedDevices[0].id) : settingsScope
    for (var i = 0; i < pairedDevices.length; i++) if (String(pairedDevices[i].id) === id) return pairedDevices[i]
    return null
  }
  readonly property int scopeIndex: {
    for (var i = 0; i < pairedDevices.length; i++) if (scopeDevice && pairedDevices[i].id === scopeDevice.id) return i
    return -1
  }
  readonly property bool editingDevice: settingsScope !== "root" && settingsScope !== "defaults" && !!scopeDevice
  readonly property var profilesRead: phone ? phone.profiles : Model.readSettings(settings)
  readonly property var scopeProfile: scopeDevice ? Model.resolveProfile(profilesRead, scopeDevice, scopeIndex === 0) : null
  // The profile the page's groups edit: the device's own on its page, else
  // the defaults (with one device, the flat keys as always).
  readonly property var editProfile: editingDevice ? scopeProfile : Model.resolveProfile(profilesRead, null, true)
  // Screen and apps: a page for one device ("screen:<id>"), set up through
  // scrcpy and adb (Model.screenSetup); reached from the Screen shortcut
  // and from the device's page.
  readonly property string screenId: settingsScope.indexOf("screen:") === 0 ? settingsScope.slice(7) : ""
  readonly property var screenDevice: {
    var list = snapshot && snapshot.devices ? snapshot.devices : []
    for (var i = 0; i < list.length; i++) if (String(list[i].id) === screenId) return list[i]
    return null
  }
  readonly property var screenPairing: phone && phone.screenPairing && phone.screenPairing.device === screenId ? phone.screenPairing : null
  readonly property var screenSetup: screenId === "" ? null
    : Model.screenSetup(phone ? phone.screenOf(screenId) : null, screenDevice, screenPairing)
  function openScreenSetup(id) {
    if (!id) return
    if (!settingsOpen) openSettings()
    openScope("screen:" + id)
    if (phone) phone.readScreen(id)
  }
  // A Connection row's button: its fix, or for Screen and apps once
  // installed, the viewed device's setup page.
  function fixRequested(what) {
    if (!phone) return
    if (what === "setup") openScreenSetup(device ? String(device.id) : "")
    else phone.fixSetup(what)
  }
  // Wireless debugging seen on the device while its page shows: the code
  // shows by itself, once per visit (Stop, or a failure, leaves it to the
  // button). Showing a code pairs nothing until the device scans it.
  property string screenAutoPaired: ""
  onScreenSetupChanged: {
    var s = screenSetup
    if (!s || !phone || !opened || !showSettings || screenPairing || screenAutoPaired === screenId) return
    var st = phone.screenOf(screenId)
    if (st && st.seen === true && (s.state === "pair" || s.state === "off")) {
      screenAutoPaired = screenId
      phone.startScreenPair(screenId)
    }
  }
  function screenAction(key) {
    if (!phone || screenId === "") return
    if (key === "install") phone.fixSetup("screen")
    else if (key === "pair") phone.startScreenPair(screenId)
    else if (key === "stopPair") phone.stopScreenPair()
    else if (key === "check") phone.readScreen(screenId)
    else if (key === "open") phone.openScreen(screenId, "", "")
  }
  // Read again while the page shows (a setting turned on, the cable
  // plugged in, the install done); a pairing on the page stops when it goes.
  Timer {
    interval: 3000
    repeat: true
    running: root.opened && root.showSettings && root.screenId !== "" && !root.screenPairing
    onTriggered: if (root.phone) root.phone.readScreen(root.screenId)
  }
  onScreenIdChanged: {
    if (screenId === "" && phone && phone.screenPairing) phone.stopScreenPair()
    screenAutoPaired = ""
  }
  Connections {
    target: root.phone
    function onScreenSetupNeeded(id) { if (root.opened) root.openScreenSetup(id) }
  }
  // What the settings page binds to: never missing, even for the moment a
  // reload tears the panel down.
  readonly property var editedProfile: editProfile || ({ showShortcuts: true, showMedia: true, showNotifications: true, showPhotos: true, showReceived: true,
    shortcuts: [], sectionOrder: [], barIndicators: [], batteryLowOnly: true, custom: {} })
  // ---- Connection (a settings scope): this computer, pairing, adding ----
  // Checks the user chose not to fix (a firewall on a Bluetooth-only
  // machine): they no longer light the gear's dot.
  // The phone the app's QR code is for on Add a device: "android" (the
  // default; the key is left out) or "ios". Kept, so the next device added
  // starts on the same choice.
  readonly property string appPlatform: setting("appPlatform", "android") === "ios" ? "ios" : "android"
  function setAppPlatform(p) { persistSettings({ appPlatform: p === "ios" ? "ios" : undefined }) }
  readonly property var ignoredChecks: {
    var v = setting("ignoredChecks", [])
    return Array.isArray(v) ? v : []
  }
  readonly property var setupChecks: phone ? phone.setupChecks : []
  readonly property int computerIssues: Model.connectionIssues(setupChecks, ignoredChecks)
  function ignoreCheck(key, on) {
    var next = ignoredChecks.filter(function(k) { return k !== key })
    if (on) next.push(key)
    persistSettings({ ignoredChecks: next.length > 0 ? next : undefined })
  }
  // Nothing to show on the main page without them: KDE Connect down (the
  // panel opens on Connection, what is broken), or nothing paired (it opens
  // on Add a device, what to do next).
  readonly property string openingScope: !phone || !snapshot ? "" : (!phone.daemon ? "connection" : (pairedDevices.length === 0 ? "addDevice" : ""))
  // The viewed device away: where it was and what Reconnect found.
  readonly property var awayInfo: Model.awayState(device, phone ? phone.setupNetwork : "", phone ? phone.searchedAt : 0,
                                                  phone ? phone.awayClock : Date.now())
  function openConnection() {
    if (!settingsOpen) openSettings()
    openScope("connection")
  }
  function openAddDevice() {
    if (!settingsOpen) openSettings()
    openScope("addDevice")
  }
  // A pairing on Add a device that completes: its card says so in place
  // (✓ Paired with …) for a moment, then the panel goes to the device's
  // page. No toast: the card and the page say it. Adding another is the
  // gear → Add a device again.
  property var pairingIds: ({})       // id -> "request" | "available": cards shown here
  property var justPaired: null       // { id, title, glyph, kind }
  // A pairing asked here: when it started (the card counts down KDE
  // Connect's 30 s), and what became of one that was not accepted in time
  // (said on its row, in place). A cancel the user pressed says nothing.
  property var pairingSince: ({})     // id -> ms
  property var pairingNotes: ({})     // id -> "Not accepted in time"
  property var pairingCancelled: ({}) // id -> true
  property real pairClock: Date.now()
  Timer {
    running: root.opened && root.showSettings && root.settingsScope === "addDevice" && Object.keys(root.pairingSince).length > 0
    interval: 1000
    repeat: true
    onTriggered: root.pairClock = Date.now()
  }
  function cancelPairing(id) {
    var c = Object.assign({}, pairingCancelled)
    c[String(id)] = true
    pairingCancelled = c
    if (phone) phone.rejectPairing(id)
  }
  function pairWithHere(id) {
    var n = Object.assign({}, pairingNotes)
    delete n[String(id)]
    pairingNotes = n
    if (phone) phone.pairWith(id)
  }
  function isPaired(id) {
    for (var i = 0; i < pairedDevices.length; i++) if (String(pairedDevices[i].id) === String(id)) return true
    return false
  }
  onSettingsRowsChanged: {
    if (settingsScope !== "addDevice") return
    var next = Object.assign({}, pairingIds), since = Object.assign({}, pairingSince), notes = Object.assign({}, pairingNotes)
    var cancelled = Object.assign({}, pairingCancelled), changed = false
    var waiting = {}
    settingsRows.forEach(function(r) {
      if ((r.kind === "request" || r.kind === "available") && r.pairKey) {
        waiting[r.id] = true
        if (next[r.id] !== r.kind) { next[r.id] = r.kind; changed = true }
        if (r.kind === "available" && !since[r.id]) { since[r.id] = Date.now(); changed = true }
      }
    })
    // A pairing asked here that is no longer waiting and not paired: KDE
    // Connect gave up on it (30 s), unless the user cancelled it.
    Object.keys(since).forEach(function(id) {
      if (waiting[id] || isPaired(id)) return
      if (!cancelled[id]) notes[id] = "Not accepted in time"
      delete since[id]
      delete next[id]
      delete cancelled[id]
      changed = true
    })
    if (changed) { pairingIds = next; pairingSince = since; pairingNotes = notes; pairingCancelled = cancelled; pairClock = Date.now() }
  }
  onPairedDevicesChanged: {
    if (!opened || !showSettings || settingsScope !== "addDevice") return
    for (var i = 0; i < pairedDevices.length; i++) {
      var d = pairedDevices[i], kind = pairingIds[String(d.id)]
      if (!kind) continue
      var next = Object.assign({}, pairingIds)
      delete next[String(d.id)]
      pairingIds = next
      justPaired = { id: String(d.id), title: Model.deviceLabel(d), glyph: Model.deviceGlyph(d), kind: kind }
      pairedMove.restart()
      return
    }
  }
  Timer {
    id: pairedMove
    interval: 1200
    onTriggered: {
      var p = root.justPaired
      root.justPaired = null
      if (!p || !root.opened || !root.showSettings || root.settingsScope !== "addDevice") return
      if (root.phone) root.phone.view(p.id)
      root.closeSettings()
    }
  }
  // While Add a device shows, it looks for new devices.
  Timer {
    running: root.opened && root.showSettings && root.settingsScope === "addDevice"
    interval: 30000
    repeat: true
    triggeredOnStart: true
    onTriggered: if (root.phone) root.phone.searchDevices(true)
  }

  readonly property var settingsRows: screenId !== "" ? Model.screenRows(screenSetup)
    : settingsScope === "connection" ? Model.connectionRows(setupChecks, ignoredChecks)
    : settingsScope === "addDevice" ? Model.addDeviceRows(Model.devicesListRows(snapshot, profilesRead, lowPercent))
    : Model.settingsPageRows({
    scope: editingDevice ? "device" : (settingsScope === "defaults" ? "defaults" : "root"),
    single: singleDevice,
    connection: Model.connectionSummary(setupChecks, ignoredChecks),
    devices: Model.devicesListRows(snapshot, profilesRead, lowPercent),
    identity: scopeProfile ? { nickname: scopeProfile.nickname, icon: scopeProfile.icon, glyph: Model.deviceIcon(scopeDevice, scopeProfile),
                               bar: scopeProfile.bar, showInPanel: scopeProfile.showInPanel } : null,
    edit: editProfile,
    can: scopeDevice ? scopeDevice.can : (device ? device.can : null)
  })

  function openScope(scope) {
    targetScope = scope
    settingsIndex = 0
    iconPicking = false
    if (panelFlick) panelFlick.contentY = 0
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }
  // Esc and the back arrow on a device's page or the defaults: to the list.
  // A demo leaves nothing in the settings: entering it keeps a copy of this
  // widget's entry (on the service, shared by every monitor's panel), and
  // leaving it writes that copy back, undoing anything changed meanwhile,
  // defaults included. Keys added during the demo go.
  function enterDemo(kind) {
    if (!phone) return
    if (!phone.demo || phone.settingsBeforeDemo === null) phone.settingsBeforeDemo = JSON.parse(JSON.stringify(root.settings || {}))
    phone.showDemo(kind)
  }
  // ---- Preview: a demo phone before any device is set up (#62) ----
  // The demo, entered from the setup checks, with a strip saying so. Nothing
  // in it reaches a device; leaving it puts every setting back.
  // Where the preview began (Add a device, or the main page), for Back to setup.
  property string previewFrom: ""
  function startPreview() {
    if (!phone || phone.preview) return
    previewFrom = settingsOpen ? settingsScope : "main"
    enterDemo("")
    phone.preview = true
    settingsOpen = false
    messagesOpen = false
    if (panelFlick) panelFlick.contentY = 0
  }
  function endPreview() {
    if (!phone || !phone.preview) return
    phone.showLive()
    leaveDemo()
  }
  // Back to setup: out of the preview, onto the page it began from.
  // One page change: whatever the preview had open (its messages, editing
  // its page) gives way to the page it began from, and the demo turns live
  // at the change's midpoint, while no page shows: the fading page never
  // shows the real phone's data. On the same page, the page fades out and
  // back in around the swap.
  // Turning the demo live rebuilds the whole panel for the real device
  // (about 0.1 s): done in the middle of a page change, it froze the change
  // and the slide-in then jumped. So the page is captured first and shown
  // still while the demo turns live underneath (a click's latency, nothing
  // moving), and only then does the change run, on a fresh clock
  // (previewSwap): the still fades out, the real page comes in, and the
  // panel's size follows at the same beat.
  property bool previewLeaving: false
  function backToSetup() {
    if (!opened || previewLeaving) { if (!opened) finishBackToSetup(); return }
    previewLeaving = true
    previewStrip.held = true
    cardWidth = cardWidth
    cardHeight = cardHeight
    pageHost.grabToImage(function(result) {
      pageStill.source = result.url
      pageStill.visible = true
      pageColumn.opacity = 0
      finishBackToSetup()
      Qt.callLater(function() { previewSwap.restart() })
    }, Qt.size(pageHost.width * pageHost.dpr, pageHost.height * pageHost.dpr))
  }
  function finishBackToSetup() {
    var from = previewFrom
    if (editing) stopEditing()
    if (from !== "" && from !== "main") { openSettings(); openScope(from) }
    else { messagesOpen = false; settingsOpen = false }
    endPreview()
  }

  readonly property bool canPreview: !!snapshot && !device && !!phone && !phone.preview
  // A real device connecting ends the preview: the panel shows it instead.
  readonly property bool liveConnected: !!phone && !!phone.liveSnapshot
    && (phone.liveSnapshot.devices || []).some(function(d) { return d && d.paired === true && d.reachable === true })
  onLiveConnectedChanged: if (liveConnected) endPreview()

  function leaveDemo() {
    var before = phone ? phone.settingsBeforeDemo : null
    if (!before) { forgetDemoProfiles(); return }
    phone.settingsBeforeDemo = null
    if (JSON.stringify(before) === JSON.stringify(root.settings || {})) return
    var values = {}
    for (var k in root.settings) if (k !== "id") values[k] = before[k]
    for (var b in before) if (b !== "id") values[b] = before[b]
    persistSettings(values)
  }

  // Without a copy (a demo entered before this was kept): profiles and order
  // written for demo devices (made-up ids) are removed.
  function forgetDemoProfiles() {
    var devs = settings && settings.devices && typeof settings.devices === "object" ? settings.devices : {}
    var order = settings && Array.isArray(settings.deviceOrder) ? settings.deviceOrder : null
    var demoIds = Object.keys(devs).filter(function(k) { return k.indexOf("demo") === 0 })
    var orderHasDemo = !!order && order.some(function(k) { return String(k).indexOf("demo") === 0 })
    var emptyLeft = (settings && settings.devices !== undefined && Object.keys(devs).length === 0) || (!!order && order.length === 0)
    if (demoIds.length === 0 && !orderHasDemo && !emptyLeft) return
    var next = Object.assign({}, devs)
    demoIds.forEach(function(k) { delete next[k] })
    var left = order ? order.filter(function(k) { return String(k).indexOf("demo") !== 0 }) : []
    // Nothing left: the keys go (undefined is not written), as before the demo.
    persistSettings({ devices: Object.keys(next).length > 0 ? next : undefined, deviceOrder: left.length > 0 ? left : undefined })
  }
  function settingsInfo() {
    return JSON.stringify({ scope: editingDevice ? "device" : settingsScope, title: heroDevice ? Model.deviceTitle(heroDevice, heroProfile) : "",
      rows: settingsRows.map(function(r) { return r.kind + (r.key ? ":" + r.key : "") + (r.id ? ":" + r.id : "") }) })
  }
  function screenInfo() {
    var s = screenSetup
    return JSON.stringify(s ? { state: s.state, line: s.line, current: s.steps.filter(function(x) { return x.current }).map(function(x) { return x.key }),
      pairing: s.pairingNote, qr: s.showQr, actions: s.actions.map(function(a) { return a.key }) } : { scope: settingsScope })
  }
  function settingsBack() {
    // Screen and apps goes back to its device's page (with one device, root).
    if (screenId !== "") { openScope(manyDevices ? screenId : "root"); return true }
    if (settingsScope !== "root") { openScope("root"); return true }
    return false
  }

  // A change to what the page edits: the device's profile on its page, else
  // the flat keys (the defaults).
  function persistScoped(values) {
    if (editingDevice) persistDeviceProfile(String(scopeDevice.id), values)
    else persistSettings(values)
  }
  function persistDeviceProfile(id, values) {
    var idx = -1
    for (var i = 0; i < pairedDevices.length; i++) if (String(pairedDevices[i].id) === String(id)) idx = i
    var entry = Model.withProfile(root.settings, String(id), values, idx === 0)
    persistSettings({ devices: entry.devices })
  }
  // Identity is always the device's own, with one device too.
  function setIdentity(values) {
    if (scopeDevice) persistDeviceProfile(String(scopeDevice.id), values)
  }
  // A group's settings back to the defaults, on a device's page.
  function resetGroup(group) {
    var keys = Model.SETTING_GROUPS[group] || []
    var values = {}
    keys.forEach(function(k) { values[k] = null })
    persistScoped(values)
  }
  function moveDevice(id, delta) {
    var ids = Model.movedOrder(snapshot, profilesRead, id, delta)
    var entry = Model.withDeviceOrder(root.settings, snapshot, ids)
    persistSettings({ deviceOrder: entry.deviceOrder, devices: entry.devices || {} })
    Qt.callLater(function() {
      for (var i = 0; i < settingsRows.length; i++)
        if (settingsRows[i].kind === "device" && settingsRows[i].id === String(id)) { settingsIndex = i; return }
    })
  }
  function cycleBarPlace() {
    var order = ["always", "attention", "never"]
    var at = order.indexOf(scopeProfile ? (scopeProfile.bar === "own" ? "always" : scopeProfile.bar) : "always")
    setIdentity({ bar: order[(at + 1) % order.length] })
  }
  property bool iconPicking: false
  // The header names the device a settings page edits, else the viewed one.
  // A page about no one device names none: Connection, Add a device, and
  // with several devices the list and the defaults. The header then reads
  // Devices, with the plugin's own glyph. A device's page, and with one
  // device all of Settings (its settings), name the device.
  readonly property bool heroNeutral: showSettings
    && (settingsScope === "connection" || settingsScope === "addDevice" || (manyDevices && !editingDevice))
  readonly property var heroDevice: heroNeutral ? null : (showSettings && screenDevice ? screenDevice : (showSettings && editingDevice ? scopeDevice : device))
  readonly property var heroProfile: heroNeutral ? null : (showSettings && editingDevice ? scopeProfile : profile)
  // The nickname field has focus (typing goes to it, not to the keys).
  property bool nicknameFocused: false

  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color urgent: bar ? bar.urgent : Color.urgent
  readonly property color dim: Qt.darker(foreground, 1.55)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property int lowPercent: {
    var n = parseInt(String(setting("lowBatteryPercent", 15)), 10)
    return isFinite(n) ? n : 15
  }

  // The notification whose reply field is open, by id; "" when none.
  property string replyingTo: ""
  property bool replyFocused: false

  // The send-text composer under the shortcuts, and whether its field has
  // focus (the key catcher stands aside). What is typed stays in memory until
  // it is sent, like a message draft; the composer itself opens closed.
  property bool composing: false
  property bool composerFocused: false

  // ---- Calls (Service.call): a device ringing, or a call missed ----
  readonly property var call: phone ? phone.call : null
  // The device the call came to (not always the viewed one).
  readonly property var callDevice: {
    if (!call || !phone) return null
    for (var i = 0; i < pairedDevices.length; i++) if (String(pairedDevices[i].id) === call.device) return pairedDevices[i]
    return null
  }
  readonly property var callProfile: callDevice ? Model.resolveProfile(profilesRead, callDevice, pairedDevices.length > 0 && pairedDevices[0].id === callDevice.id) : null
  // Text back: on the call's device, its conversation with the caller when
  // there is one, else a new message to the number. Only the user's click
  // passes typeHere, so only it focuses the composer.
  function textBack(c, typeHere) {
    if (!c || !phone) return
    phone.closeCall()
    if (device && String(device.id) !== c.device) phone.view(c.device)
    // Not the conversation left open: opening it would mark it seen.
    openMessagesView(-1, false, true)
    Qt.callLater(function() { if (messagesView) messagesView.textTo(c.number, c.who, typeHere === true) })
  }
  function callBack(c) {
    if (!c || !phone) return
    phone.closeCall()
    phone.callBack(c)
  }

  // ---- Editing the page in place (docs/design/multi-device.md) ----
  // The viewed device's page edits itself: each section becomes a bar with
  // a grip and its switch, every shortcut shows (drag the chosen ones,
  // click to add or take away), and Done ends it. Changes go to the viewed
  // device's profile (with one device, the flat keys). Fresh on every open.
  property bool editing: false
  // Edits show at once (the page, the pill); Esc puts back what was there
  // when editing began, ✓ and E keep them. What editing can change: the
  // profiles (several devices) or the flat keys (one device).
  readonly property var editKeys: ["devices", "sectionOrder", "showShortcuts", "showMedia", "showNotifications", "showPhotos", "showReceived",
                                   "shortcuts", "barIndicators", "batteryLowOnly", "showCalls"]
  property var editBefore: null
  function startEditing() {
    if (!showMain) { settingsOpen = false; messagesOpen = false }
    composing = false
    composerFocused = false
    replyingTo = ""
    var before = {}
    for (var i = 0; i < editKeys.length; i++) before[editKeys[i]] = root.settings ? root.settings[editKeys[i]] : undefined
    editBefore = JSON.parse(JSON.stringify(before))
    editing = true
    cursorActive = false
    if (panelFlick) panelFlick.contentY = 0
  }
  function stopEditing() { editing = false; editBefore = null; Qt.callLater(function() { keyCatcher.forceActiveFocus() }) }
  function cancelEditing() {
    var before = editBefore
    stopEditing()
    if (!before) return
    var values = {}, changed = false
    for (var i = 0; i < editKeys.length; i++) {
      var k = editKeys[i]
      if (JSON.stringify(before[k]) === JSON.stringify(root.settings ? root.settings[k] : undefined)) continue
      values[k] = before[k]
      changed = true
    }
    if (!changed) return
    persistSettings(values)
    if (phone) phone.report("Changes undone", false)
  }
  function toggleEditing() { if (editing) stopEditing(); else startEditing() }
  // A right-click on a chip in the bar: the panel on that device, editing
  // its page (the bar strip leads it). Switching device ends editing, so a
  // switch carries it over.
  property bool editOnArrival: false
  function editFromBar(id) {
    var key = String(id || "")
    if (!opened) {
      if (phone && key !== "") phone.requestView(key)
      openFromHotkey()
      startEditing()
    } else if (key === "" || !device || String(device.id) === key) {
      startEditing()
    } else {
      editOnArrival = true
      switchDevice(key, true)
    }
  }

  // Right-click on the main page: a small menu (Edit page, Settings), as a
  // right-click on the Plasma desktop offers Enter Edit Mode. `menuAt` is
  // where it opens, in the panel's coordinates.
  property bool pageMenuOpen: false
  property point menuAt: Qt.point(0, 0)
  function openPageMenu(x, y) { menuAt = Qt.point(x, y); pageMenuOpen = true }
  function closePageMenu() { pageMenuOpen = false }
  // A section's Layout switch, from the page.
  function sectionFlag(key) { var l = Model.layoutBySection(key); return l ? l.key : "" }
  function toggleSectionShown(key) {
    var flag = sectionFlag(key)
    if (flag === "") return
    var values = {}
    values[flag] = !profile[flag]
    persistProfile(values)
  }
  function toggleShortcutOnPage(key) { persistProfile({ shortcuts: Model.toggleShortcut(shortcutOrder, key) }) }
  // The viewed device's chip in the bar, from the page.
  readonly property var barOrder: Model.normalizeBarIndicators(profile.barIndicators)
  function toggleBarOnPage(key) { persistProfile({ barIndicators: Model.toggleBarIndicator(barOrder, key) }) }
  function toggleBarFlagOnPage(key) {
    var values = {}
    values[key] = profile[key] !== true
    persistProfile(values)
  }

  // One cursor for keyboard and mouse, as in the stock panels.
  property bool cursorActive: false
  property string focusSection: "actions"
  property int actionIndex: 0

  // Media is a carousel, like the phone's own media card: the active player
  // shows, the others are a swipe away. `browsedName` is the player the user
  // paged to (its D-Bus name), cleared on every open so the panel always opens
  // on the active one, and kept while open so a player starting elsewhere does
  // not yank the card away from the one being looked at.
  property string browsedName: ""
  readonly property int shownPlayer: {
    var ps = players
    if (browsedName !== "")
      for (var i = 0; i < ps.length; i++) if (ps[i].dbusName === browsedName) return i
    var active = phone ? phone.activePlayer : null
    for (var j = 0; j < ps.length; j++) if (ps[j] === active) return j
    return 0
  }
  readonly property var shownPlayerObject: players.length > 0 ? players[Math.min(shownPlayer, players.length - 1)] : null

  // Live offset while a card is dragged sideways, and whether a drag is on.
  // Cards built since the shell started; a check that the carousel is not
  // torn down and rebuilt on a play-state change (it blinked once).
  property int cardsBuilt: 0

  property real swipeOffset: 0
  property bool swiping: false

  function showPlayer(index) {
    if (players.length === 0) return
    var i = Math.max(0, Math.min(players.length - 1, index))
    browsedName = String(players[i].dbusName || "")
  }

  function dragCarousel(dx) {
    swiping = true
    // Resist past either end, the way a phone carousel does.
    var atStart = shownPlayer === 0 && dx > 0
    var atEnd = shownPlayer === players.length - 1 && dx < 0
    swipeOffset = atStart || atEnd ? dx * 0.25 : dx
  }

  function endCarouselDrag(dx) {
    swiping = false
    swipeOffset = 0
    if (Math.abs(dx) >= Style.space(60)) showPlayer(shownPlayer + (dx < 0 ? 1 : -1))
  }
  property int notifIndex: 0

  // The device whose Unpair is armed (two presses on Unpair).
  property string unpairArmed: ""
  Timer { id: unpairDisarm; interval: 3000; onTriggered: root.unpairArmed = "" }

  // Folded sections, from this widget's settings; folded on the user's click.
  // The main page's sections fold per device (the viewed device's profile);
  // the settings page's groups fold once for all.
  readonly property var collapsed: Model.collapsedState(setting("collapsed", null))
  readonly property var pageSections: ["devices", "actions", "media", "notifications"]
  function isCollapsed(key) {
    return pageSections.indexOf(key) >= 0 ? profile.collapsed[key] === true : collapsed[key] === true
  }
  // Only folded sections are stored; unfolding drops the key.
  function toggleCollapsed(key) {
    var perDevice = pageSections.indexOf(key) >= 0
    var next = Object.assign({}, perDevice ? profile.collapsed : collapsed)
    if (next[key] === true) delete next[key]
    else next[key] = true
    if (perDevice) persistProfile({ collapsed: next })
    else persistSettings({ collapsed: next })
  }

  // A change to the viewed device's own profile. With one device there is
  // nothing to tell apart: it is written as today's flat keys (the defaults).
  function persistProfile(values) {
    if (!manyDevices || !device) { persistSettings(values); return }
    var entry = Model.withProfile(root.settings, String(device.id), values, phone ? phone.deviceIndex === 0 : false)
    persistSettings({ devices: entry.devices })
  }

  // The conversation last open in messages, per device, so the messages
  // view comes back to it (UI state persists: see AGENTS.md).
  readonly property var lastThreads: {
    var v = setting("lastThread", null)
    return v && typeof v === "object" && !Array.isArray(v) ? v : ({})
  }
  // Messages: unread only, remembered like the rest of the UI state.
  readonly property bool unreadOnly: setting("unreadOnly", false) === true
  function toggleUnreadOnly() { persistSettings({ unreadOnly: !unreadOnly }) }
  Binding { target: root.sms; property: "unreadOnly"; value: root.unreadOnly; when: !!root.sms }

  function rememberThread(tid) {
    if (phone && phone.demo) return
    if (!device || tid === undefined || tid < 0 || lastThreads[device.id] === tid) return
    var next = Object.assign({}, lastThreads)
    next[device.id] = tid
    persistSettings({ lastThread: next })
  }

  // Viewing a device (a tab, a chip, the Devices section, IPC). Not stored:
  // the panel opens by the order's rule (Service.viewOnOpen).
  function selectDevice(id) { switchDevice(id) }

  // Changes the viewed device like a page change: the page slides out, the
  // device swaps while nothing shows, and its page slides in, from the side
  // of its tab.
  property string pendingDevice: ""
  property int deviceDirection: 1
  // On the Messages page a tab switches whose texts are read: a device
  // without text messages is not one to switch to there (its tab is dimmed
  // and says so). `leaveMessages` (a chip in the bar: "show me this
  // device") goes to its main page instead.
  function hasTexts(d) { return !!d && !!d.can && d.can.sms === true }
  function switchDevice(id, leaveMessages) {
    if (!phone || !id || (device && String(device.id) === String(id))) return
    var target = phone.findDevice(id)
    if (messagesOpen && target && !hasTexts(target)) {
      if (leaveMessages === true) closeMessagesView()
      else { phone.report(Model.deviceLabel(target) + " has no text messages", false); return }
    }
    var from = -1, to = -1
    for (var i = 0; i < tabDevices.length; i++) {
      if (device && tabDevices[i].id === device.id) from = i
      if (String(tabDevices[i].id) === String(id)) to = i
    }
    deviceDirection = to >= from ? 1 : -1
    if (!opened) { phone.view(id); return }
    pendingDevice = String(id)
    deviceSwap.restart()
  }
  function applyDevice() {
    if (!phone || pendingDevice === "") return
    editing = false
    phone.view(pendingDevice)
    phone.refreshPhotos(false)
    if (editOnArrival) { editOnArrival = false; startEditing() }
    pendingDevice = ""
    browsedName = ""
    replyingTo = ""
    replyFocused = false
    composing = false
    composerFocused = false
    notifIndex = 0
  }
  // A tab dropped at `to`: its device moves there among the tabs; devices
  // without a tab keep their places in the order.
  function dropTab(from, to) {
    if (from === to || from < 0 || !phone) return
    var tabIds = tabDevices.map(function(d) { return String(d.id) })
    var moved = tabIds.splice(from, 1)[0]
    tabIds.splice(to, 0, moved)
    var all = pairedDevices.map(function(d) { return String(d.id) })
    var next = [], t = 0
    for (var i = 0; i < all.length; i++) next.push(tabDevices.some(function(d) { return String(d.id) === all[i] }) ? tabIds[t++] : all[i])
    var entry = Model.withDeviceOrder(root.settings, snapshot, next)
    persistSettings({ deviceOrder: entry.deviceOrder, devices: entry.devices || {} })
  }
  function tabAt(i) { if (i >= 0 && i < tabDevices.length) switchDevice(tabDevices[i].id) }
  function tabStep(delta) {
    for (var i = 0; i < tabDevices.length; i++)
      if (device && tabDevices[i].id === device.id) { tabAt(Math.max(0, Math.min(tabDevices.length - 1, i + delta))); return }
  }

  function armOrUnpair(row) {
    if (!row || !row.paired || !phone) return
    if (unpairArmed === row.id) { unpairArmed = ""; unpairDisarm.stop(); phone.unpair(row.id); return }
    unpairArmed = row.id
    unpairDisarm.restart()
    phone.report("Unpair " + row.name + "? Do it again to confirm", false)
  }

  readonly property var actions: Model.shortcutTiles(shortcutOrder, can)
  readonly property int actionColumns: Math.max(1, Math.min(4, actions.length))

  // The sections drawn under the header, in the chosen order: switched on
  // in Layout and with something in them, while the device is here.
  readonly property var drawnSections: {
    // Editing: every section, on or off, with something in it or not.
    if (editing) return Model.visibleSections(sectionOrder)
    var s = []
    for (var i = 0; i < sectionOrder.length; i++) {
      var key = sectionOrder[i]
      // The Devices section is gone: tabs switch, the pairing card and
      // Settings' device list pair and unpair.
      if (key === "devices") continue
      else if (!reachable) continue
      else if (key === "actions" && showShortcuts && actions.length > 0) s.push(key)
      else if (key === "media" && showMedia && players.length > 0) s.push(key)
      else if (key === "notifications" && showNotifications && notifications.length > 0) s.push(key)
      else if (key === "photos" && showPhotos && hasPhotos) s.push(key)
      else if (key === "received" && showReceived && received.length > 0) s.push(key)
    }
    return s
  }
  // A line between sections, never under the header.
  function separatedAbove(key) { return drawnSections.indexOf(key) > 0 }

  // Where the keyboard cursor can go, top to bottom.
  readonly property var sections: drawnSections


  function runAction(key) {
    if (!phone) return
    if (key === "ring") phone.ring()
    else if (key === "share") phone.sendFiles()
    else if (key === "clipboard") phone.sendClipboard()
    else if (key === "text") toggleComposer()
    else if (key === "ping") phone.ping()
    else if (key === "playPause") phone.mediaAction("PlayPause")
    else if (key === "messages") root.openMessagesView(-1)
    else if (key === "kdeconnect") { phone.openKdeConnect(); root.close() }
    else if (key === "screen" && device) phone.pressScreen(String(device.id))
  }

  // ---- Settings ----

  // Same shape as the calendar plugin: merge into this widget's shell.json
  // entry, apply locally at once, and let the shell write the file (which
  // then reaches the bars on every other monitor).
  function persistSettings(values) {
    var entry = { id: root.moduleName }
    for (var existing in root.settings) if (existing !== "id") entry[existing] = root.settings[existing]
    for (var key in values) entry[key] = values[key]
    root.settings = entry
    if (root.hostWidget && "settings" in root.hostWidget) root.hostWidget.settings = entry
    if (root.bar && root.bar.shell && typeof root.bar.shell.updateEntryInline === "function")
      root.bar.shell.updateEntryInline(root.moduleName, entry)
  }

  function toggleLayout(key) {
    var values = {}
    values[key] = !Model.layoutFlag(editProfile[key])
    persistScoped(values)
  }

  function toggleShortcutKey(key) { persistScoped({ shortcuts: Model.toggleShortcut(editProfile.shortcuts, key) }) }

  function moveShortcutKey(key, delta) {
    persistScoped({ shortcuts: Model.moveShortcut(editProfile.shortcuts, key, delta) })
    // Keep the cursor on the row that moved.
    Qt.callLater(function() {
      for (var i = 0; i < settingsRows.length; i++)
        if (settingsRows[i].kind === "shortcut" && settingsRows[i].key === key) { settingsIndex = i; return }
    })
  }

  function moveSectionKey(section, delta) {
    // The order as shown (the Devices section is not on the page any more).
    persistScoped({ sectionOrder: Model.moveShortcut(Model.visibleSections(editProfile.sectionOrder), section, delta) })
    // Keep the cursor on the row that moved.
    Qt.callLater(function() {
      for (var i = 0; i < settingsRows.length; i++)
        if (settingsRows[i].kind === "layout" && settingsRows[i].section === section) { settingsIndex = i; return }
    })
  }

  function moveBarIndicator(key, delta) {
    persistScoped({ barIndicators: Model.moveShortcut(editProfile.barIndicators, key, delta) })
    // Keep the cursor on the row that moved.
    Qt.callLater(function() {
      for (var i = 0; i < settingsRows.length; i++)
        if (settingsRows[i].kind === "bar" && settingsRows[i].key === key) { settingsIndex = i; return }
    })
  }

  function resetShortcuts() { persistScoped({ shortcuts: Model.DEFAULT_SHORTCUTS.slice() }) }

  // A settings row under a folded section is not there to land on.
  function settingsRowShown(i) {
    var row = settingsRows[i]
    if (!row) return false
    if (row.kind === "layout") return !isCollapsed("layout")
    if (row.kind === "shortcut") return !isCollapsed("shortcuts")
    if (row.kind === "bar" || row.kind === "barFlag") return !isCollapsed("bar")
    if (row.kind === "device" || row.kind === "request" || row.kind === "available") return !isCollapsed("devicesList")
    if (["nickname", "icon", "barPlace", "showInPanel"].indexOf(row.kind) >= 0) return !isCollapsed("identity")
    return true
  }
  function nextSettingsRow(from, dy) {
    var i = from
    for (var step = 0; step < settingsRows.length; step++) {
      i += dy
      if (i < 0 || i >= settingsRows.length) return from
      if (settingsRowShown(i)) return i
    }
    return from
  }

  function activateSetting(index) {
    var row = settingsRows[index]
    if (!row) return
    settingsIndex = index
    if (row.kind === "layout") toggleLayout(row.key)
    else if (row.kind === "shortcut") toggleShortcutKey(row.key)
    else if (row.kind === "bar") persistScoped({ barIndicators: Model.toggleBarIndicator(editProfile.barIndicators, row.key) })
    else if (row.kind === "barFlag") { var flag = {}; flag[row.key] = !editProfile[row.key]; persistScoped(flag) }
    else if (row.kind === "reset") resetShortcuts()
    else if (row.kind === "device") openScope(row.id)
    else if (row.kind === "defaults") openScope("defaults")
    else if (row.kind === "request" && phone) phone.acceptPairing(row.id)
    else if (row.kind === "available" && phone && !row.waiting) pairWithHere(row.id)
    else if (row.kind === "nickname") { if (settingsView) settingsView.editNickname() }
    else if (row.kind === "icon") iconPicking = !iconPicking
    else if (row.kind === "barPlace") cycleBarPlace()
    else if (row.kind === "showInPanel") setIdentity({ showInPanel: !scopeProfile.showInPanel })
    else if (row.kind === "resetGroup") resetGroup(row.key)
    else if (row.kind === "editPage") { if (editingDevice && scopeDevice) phone.view(scopeDevice.id); settingsOpen = false; Qt.callLater(startEditing) }
    else if (row.kind === "unpair" && scopeDevice) armOrUnpair({ id: String(scopeDevice.id), name: Model.deviceLabel(scopeDevice), paired: true })
    else if (row.kind === "kdeconnect" && phone) { phone.openKdeConnect(); root.close() }
    else if (row.kind === "connection" || row.kind === "addDevice") openScope(row.kind)
    else if (row.kind === "check" && phone && row.fix !== "" && (!row.ok || row.optional)) fixRequested(row.fix)
    else if (row.kind === "screen") openScreenSetup(String(editingDevice && scopeDevice ? scopeDevice.id : (device ? device.id : "")))
    else if (row.kind === "screenAction") screenAction(row.key)
  }

  // `fresh`: not back to the conversation left open (the caller picks one).
  function openMessagesView(threadId, typeHere, fresh) {
    // A tablet without a SIM (or a computer) has no text messages.
    if (device && can.sms !== true) {
      if (phone) phone.report(Model.deviceLabel(device) + " has no text messages", false)
      return
    }
    replyingTo = ""
    replyFocused = false
    composing = false
    composerFocused = false
    editing = false
    settingsOpen = false
    messagesOpen = true
    if (sms) {
      sms.start()
      if (threadId !== undefined && threadId >= 0) sms.openThread(threadId)
      // Demo conversations are made up: the real last conversation is not
      // among them.
      else if (fresh !== true && device && !(phone && phone.demo) && lastThreads[device.id] !== undefined && sms.openThreadId < 0) {
        // Back to the conversation left open; the composer stays unfocused.
        var last = lastThreads[device.id]
        Qt.callLater(function() { if (messagesView) messagesView.openThread(last, false) })
      }
    }
    if (panelFlick) panelFlick.contentY = 0
    Qt.callLater(function() {
      if (threadId !== undefined && threadId >= 0 && messagesView) messagesView.openThread(threadId, typeHere === true)
      else keyCatcher.forceActiveFocus()
    })
  }

  function closeMessagesView() {
    messagesOpen = false
    if (panelFlick) panelFlick.contentY = 0
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  // Notifications opened to their full text, by id. Memory only: they go
  // away with the notification.
  property var expandedNotes: ({})
  function toggleExpanded(n) {
    if (!n) return
    var next = Object.assign({}, expandedNotes)
    if (next[n.id]) delete next[n.id]
    else next[n.id] = true
    expandedNotes = next
  }

  // A text-message notification opens its conversation; with no thread to
  // match, the messages view opens searched for who sent it.
  function openNotificationConversation(n) {
    if (!n) return
    var tid = threadForNotification(n)
    if (tid >= 0) { openMessagesView(tid, true); return }
    openMessagesView(-1)
    Qt.callLater(function() { if (messagesView) messagesView.setSearch(Model.notificationTitle(n)) })
  }

  function isTextNotification(n) {
    return !!n && (Model.isMessagingApp(n.app) || threadForNotification(n) >= 0)
  }

  // An action pressed or a reply sent on a text-message notification from
  // the panel means the message was seen here: its conversation stops
  // counting as unread at once. The phone's own read state follows a moment
  // later (after its app writes it), or never on a KDE Connect that ignores
  // read changes to messages it already has. Only SMS apps: another
  // messenger's sender can share a name with an SMS conversation.
  function markNotificationSeen(n) {
    if (!n || !sms || !Model.isMessagingApp(n.app)) return
    var tid = threadForNotification(n)
    if (tid >= 0) sms.markSeen(tid)
  }

  function threadForNotification(n) {
    if (!sms || !n) return -1
    var rev = sms.modelRevision
    var rows = []
    for (var i = 0; i < sms.threads.count; i++) rows.push(sms.threads.get(i))
    return Model.threadForNotification(n, rows)
  }

  function openSettings() {
    editing = false
    messagesOpen = false
    replyingTo = ""
    replyFocused = false
    composing = false
    composerFocused = false
    settingsOpen = true
    settingsIndex = 0
    targetScope = "root"
    iconPicking = false
    if (panelFlick) panelFlick.contentY = 0
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  function closeSettings() {
    settingsOpen = false
    if (panelFlick) panelFlick.contentY = 0
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  function mediaKey(i) { return i === 0 ? "Previous" : (i === 2 ? "Next" : "PlayPause") }

  // The slider shows where it was left, not where the phone rounded it to.
  // The phone's media volume has coarse steps (15 on many phones) and reports
  // the level rounded down to a whole percent, so after every drag the knob
  // jumped. `volumeWish` is the level set here; it stays on screen while the
  // phone's report is just the step it snapped to. Any later report the phone
  // makes on its own (its buttons, another app) drops the wish and shows it.
  readonly property real reportedVolume: volumePlayer ? volumePlayer.volume : 0
  property real volumeWish: -1
  property bool volumeAwaiting: false
  property real volumeSnapped: -1
  readonly property real shownVolume: volumeWish >= 0 ? volumeWish : reportedVolume

  function setVolumeWish(v) {
    if (!phone || !volumePlayer) return
    v = Math.max(0, Math.min(1, v))
    volumeWish = v
    volumeSnapped = reportedVolume
    volumeAwaiting = true
    volumeAwait.restart()
    phone.setVolume(v)
  }

  onReportedVolumeChanged: {
    if (volumeWish < 0) return
    if (volumeAwaiting) {
      // The answer to our set comes in twice: KDE Connect echoes the value
      // sent, then the phone reports the step it snapped to. Everything in
      // the window is the answer. Keep the wish unless the phone lands more
      // than a step away (a volume limit on the phone).
      volumeSnapped = reportedVolume
      if (Math.abs(reportedVolume - volumeWish) > 0.08) volumeWish = -1
      return
    }
    if (Math.abs(reportedVolume - volumeSnapped) > 0.001) volumeWish = -1
  }

  // The answer window. After it, a change is the phone's own.
  Timer {
    id: volumeAwait
    interval: 2500
    onTriggered: { root.volumeAwaiting = false; root.volumeSnapped = root.reportedVolume }
  }

  // Mute remembers the level it came from, so unmute puts it back.
  property real volumeBeforeMute: 0.5
  function toggleMute() {
    if (!phone || !volumePlayer) return
    if (shownVolume > 0.001) { volumeBeforeMute = shownVolume; setVolumeWish(0) }
    else setVolumeWish(volumeBeforeMute > 0.001 ? volumeBeforeMute : 0.5)
  }

  function nudgeVolume(delta) {
    if (phone && volumePlayer) setVolumeWish(Math.round((shownVolume + delta) * 20) / 20)
  }

  function nudgePosition(seconds) {
    var p = shownPlayerObject
    if (phone && p && p.positionSupported) phone.seek(p, p.position + seconds)
  }

  function openReply(n) {
    if (!n || !n.replyId) return
    replyingTo = n.id
  }

  // Only the user's click or Enter on the Send text tile opens it focused.
  function toggleComposer() {
    if (composing) { closeComposer(); return }
    composing = true
    Qt.callLater(function() { if (composing) composerField.forceActiveFocus() })
  }

  function closeComposer() {
    composing = false
    composerFocused = false
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  function sendComposed(asPing) {
    var t = composerField.text
    if (!phone || t.trim() === "") return
    if (asPing) phone.ping(t)
    else phone.sendText(t)
    composerField.text = ""
    closeComposer()
  }

  function closeReply() {
    replyingTo = ""
    replyFocused = false
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  function ensureCursor() {
    var s = sections
    if (s.length === 0) return
    if (s.indexOf(focusSection) < 0) focusSection = s[0]
    if (notifIndex >= notifications.length) notifIndex = Math.max(0, notifications.length - 1)
    if (photoIndex >= photos.length) photoIndex = Math.max(0, photos.length - 1)
    if (receivedIndex >= received.length) receivedIndex = Math.max(0, received.length - 1)
  }

  function moveCursor(dx, dy) {
    ensureCursor()
    var s = sections
    if (s.length === 0) return
    if (dx !== 0) {
      if (focusSection === "actions") actionIndex = Math.max(0, Math.min(actions.length - 1, actionIndex + dx))
      else if (focusSection === "media") showPlayer(shownPlayer + dx)
      else if (focusSection === "photos") photoIndex = Math.max(0, Math.min(photos.length - 1, photoIndex + dx))
      return
    }
    // Photos are a grid of four; j/k walk its rows before leaving it.
    if (focusSection === "photos" && !isCollapsed("photos")) {
      var down = photoIndex + dy * photoColumns
      if (down >= 0 && down < photos.length) { photoIndex = down; return }
    }
    if (focusSection === "received" && !isCollapsed("received")) {
      var step = receivedIndex + dy
      if (step >= 0 && step < received.length) { receivedIndex = step; return }
    }
    // The shortcuts are a grid: j/k walk its rows before leaving it. Folded,
    // they are one row of icons in the header.
    if (focusSection === "actions" && !isCollapsed("actions")) {
      var below = actionIndex + dy * actionColumns
      if (below >= 0 && below < actions.length) { actionIndex = below; return }
      if (dy > 0 && Math.floor(actionIndex / actionColumns) < Math.floor((actions.length - 1) / actionColumns)) {
        actionIndex = actions.length - 1
        return
      }
    }
    if (focusSection === "notifications" && !isCollapsed("notifications")) {
      var next = notifIndex + dy
      if (next >= 0 && next < notifications.length) { notifIndex = next; scrollToCursor(); return }
      if (next >= notifications.length) return
    }
    var at = s.indexOf(focusSection) + dy
    if (at < 0 || at >= s.length) return
    focusSection = s[at]
    if (focusSection === "notifications") notifIndex = dy > 0 ? 0 : notifications.length - 1
    if (focusSection === "photos") photoIndex = dy > 0 ? 0 : Math.max(0, photos.length - 1)
    if (focusSection === "received") receivedIndex = dy > 0 ? 0 : Math.max(0, received.length - 1)
    scrollToCursor()
  }

  function activateCursor() {
    ensureCursor()
    // Editing: Enter shows or hides the section under the cursor.
    if (editing) { toggleSectionShown(focusSection); return }
    // A folded section opens on Enter; its content is not there to act on.
    if ((focusSection === "media" || focusSection === "notifications" || focusSection === "photos" || focusSection === "received") && isCollapsed(focusSection)) {
      toggleCollapsed(focusSection)
      return
    }
    if (focusSection === "actions") {
      var a = actions[actionIndex]
      if (a && a.enabled) runAction(a.key)
    } else if (focusSection === "media") {
      var shownCard = cardRepeater.itemAt(shownPlayer)
      if (shownCard) shownCard.togglePlaying()
    } else if (focusSection === "notifications") {
      openReply(notifications[notifIndex])
    } else if (focusSection === "photos") {
      openPhoto(photos[photoIndex])
    } else if (focusSection === "received") {
      openReceived(received[receivedIndex])
    }
  }

  // The page keeps the cursor in sight, gliding there at the panel's pace:
  // whatever holds it (the glide's item), on the main page or in Settings.
  function followCursor() {
    var item = cursorGlide ? cursorGlide.target : null
    if (!item || !panelFlick || !item.visible) return
    var y = item.mapToItem(panelFlick.contentItem, 0, 0).y
    var margin = Style.space(6)
    var maxY = Math.max(0, panelFlick.contentHeight - panelFlick.height)
    var to = panelFlick.contentY
    if (y < panelFlick.contentY + margin) to = Math.max(0, y - margin)
    else if (y + item.height > panelFlick.contentY + panelFlick.height - margin)
      to = Math.min(maxY, y + item.height + margin - panelFlick.height)
    glidePage(to)
  }
  function scrollToCursor() { Qt.callLater(followCursor) }
  // PgUp/PgDn on the main page and in Settings: a screen at a time.
  function pageBy(pages) {
    if (!panelFlick) return
    var maxY = Math.max(0, panelFlick.contentHeight - panelFlick.height)
    var base = pageGlide.running ? pageGlide.to : panelFlick.contentY
    glidePage(Math.max(0, Math.min(maxY, base - pages * panelFlick.height * 0.85)))
  }
  function glidePage(to) {
    pageGlide.stop()
    if (Math.abs(to - panelFlick.contentY) < 0.5) return
    pageGlide.from = panelFlick.contentY
    pageGlide.to = to
    pageGlide.start()
  }
  NumberAnimation { id: pageGlide; target: panelFlick; property: "contentY"; duration: Model.MOTION.inMs * root.motion; easing.type: Easing.OutCubic }

  // Middle click on the bar pill: straight to messages.
  function openMessagesFromHotkey() {
    openFromHotkey()
    openMessagesView(-1)
    snapPage()
  }

  function onOpened() {
    editing = false
    pageMenuOpen = false
    // Opened again soon after closing: back where it was (Model.placeToResume).
    var resume = Model.placeToResume(leftPlace, Date.now(), { openingScope: openingScope, requested: phone ? phone.requestedId : "" })
    leftPlace = null
    // The device asked for (a chip, IPC), else the first connected one;
    // resuming, the one it was on.
    if (phone) phone.viewOnOpen()
    if (phone && resume && resume.device !== "" && phone.findDevice(resume.device)) phone.view(resume.device)
    // A paired device that is away is looked for once (Service.searchIfAway).
    if (phone) phone.searchIfAway()
    deviceSwap.stop()
    pendingDevice = ""
    // Positions are kept current while closed (Service), but re-read now too,
    // so the seek bar is already where it belongs when the panel shows.
    if (phone) phone.refreshPositions()
    // The newest photos, asked for when the panel opens (Service.refreshPhotos).
    if (phone) phone.refreshPhotos(false)
    cursorActive = false
    browsedName = ""
    settingsOpen = false
    messagesOpen = false
    // Nothing paired, or KDE Connect down: straight to Connection.
    if (openingScope !== "") { settingsOpen = true; targetScope = openingScope; settingsIndex = 0 }
    else if (resume && resume.settingsOpen) { settingsOpen = true; targetScope = resume.scope; settingsIndex = 0 }
    else if (resume && resume.messagesOpen) openMessagesView(-1)
    snapPage()
    replyingTo = ""
    replyFocused = false
    composing = false
    composerFocused = false
    if (panelFlick) panelFlick.contentY = 0
    // Back to where the page was scrolled, once it is laid out.
    if (resume && resume.y > 0 && !messagesOpen) Qt.callLater(function() { if (panelFlick) panelFlick.contentY = Math.min(resume.y, Math.max(0, panelFlick.contentHeight - panelFlick.height)) })
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  function open() { openedFromHotkey = false; root.controller.show(); root.onOpened() }
  function openFromHotkey() { openedFromHotkey = true; root.controller.show(); root.onOpened() }
  function close() { root.controller.hide() }
  function toggle() { if (root.opened) root.close(); else root.open() }

  function switchPanel(direction) {
    if (bar && typeof bar.switchPanelFrom === "function")
      return bar.switchPanelFrom(root.barIdentity, direction)
    return false
  }

  onNotificationsChanged: ensureCursor()



  IpcHandler {
    target: root.ipcTarget
    function open(): void { root.openFromHotkey() }
    function close(): void { root.close() }
    function show(): void { root.openFromHotkey() }
    function hide(): void { root.close() }
    function toggle(): void { root.toggle() }
    function ring(): string { if (root.phone) root.phone.ring(); return "ok" }
    function sendFiles(): string { if (root.phone) root.phone.sendFiles(); return "ok" }
    function sendClipboard(): string { if (root.phone) root.phone.sendClipboard(); return "ok" }
    function messages(): string { var was = root.opened; if (!was) root.openFromHotkey(); root.openMessagesView(-1); if (!was) root.snapPage(); return "ok" }
    // Scripted: opens the thread but never focuses the composer.
    function openThread(tid: int): string { var was = root.opened; if (!was) root.openFromHotkey(); root.openMessagesView(tid, false); if (!was) root.snapPage(); return "ok" }
    // For checking the transitions: open a page as a click would.
    function page(name: string): string {
      if (name === "settings") root.openSettings()
      else if (name === "connection") root.openConnection()
      else if (name === "addDevice") root.openAddDevice()
      else if (name === "messages") root.openMessagesView(-1)
      else { root.settingsOpen = false; root.messagesOpen = false }
      return root.targetPage
    }
    function slowMotion(factor: real): string { root.motion = factor > 0 ? factor : 1; if (messagesView) messagesView.motion = root.motion; return String(root.motion) }
    function unreadOnly(): string { root.toggleUnreadOnly(); return JSON.stringify({ on: root.unreadOnly, shown: root.sms ? root.sms.shownThreads.count : 0 }) }
    function forgetLastThread(): string { root.persistSettings({ lastThread: {} }); return "ok" }
    // Demo: sample failing checks on this computer, to look at the fixes and
    // the gear's dot (kept until `live`; a demo starts if none runs).
    function demoSetup(): string {
      if (!root.phone) return "no service"
      if (!root.phone.demo) root.enterDemo("")
      root.phone.demoChecks = true
      root.phone.setupNetwork = "192.168.1.0/24"
      root.phone.setupChecks = [
        { key: "installed", ok: true, label: "KDE Connect installed", status: "Installed", detail: "", fix: "", fixLabel: "" },
        { key: "running", ok: true, label: "KDE Connect running", status: "Running", detail: "", fix: "", fixLabel: "" },
        { key: "firewall", ok: false, label: "Firewall lets devices in", status: "Closed", detail: "Ports 1714:1764 are closed; allow them from 192.168.1.0/24", fix: "firewall", fixLabel: "Allow" },
        { key: "network", ok: true, label: "On a network", status: "192.168.1.0/24", detail: "", fix: "", fixLabel: "" }
      ]
      return JSON.stringify({ issues: root.computerIssues })
    }
    // Screen and apps on the viewed device: its page, as the device's row
    // would open it; what the page shows. demoScreen: a made-up state
    // (tools, pair, off, unauthorized, away, ready; demo only).
    function screen(): string { if (root.device) root.openScreenSetup(String(root.device.id)); return root.screenInfo() }
    function screenInfo(): string { return root.screenInfo() }
    function demoScreen(kind: string): string {
      if (!root.phone || !root.phone.demo) return "demo only"
      root.phone.demoScreenKind = kind || "pair"
      if (root.device) root.phone.readScreen(String(root.device.id))
      return root.screenInfo()
    }
    function pressScreenAction(key: string): string {
      if (!root.phone || !root.phone.demo) return "demo only"
      root.screenAction(key)
      return root.screenInfo()
    }
    // Demo: the phone away, last seen 12 minutes ago on this network.
    function demoAway(): string {
      if (!root.phone) return "no service"
      root.enterDemo("away")
      root.phone.setupNetwork = "192.168.1.0/24"
      root.phone.searchedAt = 0
      return "ok"
    }
    // Reconnect on the viewed device, as its button would; what it shows.
    function reconnect(): string {
      if (root.phone) root.phone.searchDevices(false)
      return JSON.stringify(root.awayInfo)
    }
    // A check ignored (or not), as its Ignore / Undo would.
    function ignoreCheck(key: string, on: bool): string { root.ignoreCheck(key, on); return JSON.stringify({ ignored: root.ignoredChecks, issues: root.computerIssues }) }
    // Demo only: press a notification's action as a click would, to check
    // what follows in the panel. Refused on live data, where it would act on
    // the phone.
    function pressAction(index: int, action: string): string {
      if (!root.phone || !root.phone.demo) return "demo only"
      var n = root.notifications[index]
      if (!n) return "no notification " + index
      root.phone.notificationAction(n, action)
      root.markNotificationSeen(n)
      return JSON.stringify({ unread: root.sms ? root.sms.unreadCount : -1 })
    }
    // Demo only: dismiss a notification as a click on its X would, to look
    // at the waiting ring. Refused on live data.
    function pressDismiss(index: int): string {
      if (!root.phone || !root.phone.demo) return "demo only"
      var n = root.notifications[index]
      if (!n) return "no notification " + index
      root.phone.dismiss(n)
      return "ok"
    }
    function expandNotification(index: int): string { root.toggleExpanded(root.notifications[index]); return JSON.stringify(root.expandedNotes) }
    function toast(text: string): string { if (root.phone) root.phone.report(text, false); return "ok" }
    // Many devices. A device is its id, nickname or name. Every verb acts on
    // the viewed device; `view` picks it, `openOn` opens the panel on it.
    function view(key: string): string {
      var d = root.phone ? root.phone.findDevice(key) : null
      if (!d) return "no device " + key
      // Closed: the next open lands on it (Service.viewOnOpen).
      if (root.opened) root.switchDevice(d.id); else root.phone.requestView(d.id)
      return "ok"
    }
    function openOn(key: string): string {
      var d = root.phone ? root.phone.findDevice(key) : null
      if (!d) return "no device " + key
      root.phone.requestView(d.id)
      if (root.opened) root.switchDevice(d.id); else root.openFromHotkey()
      return "ok"
    }
    // Settings for devices: open a scope ("root", "defaults", or a device's
    // id, nickname or name) as a click would, and what its page lists.
    function settingsScope(key: string): string {
      if (!root.settingsOpen) { root.openFromHotkey(); root.openSettings() }
      if (key === "root" || key === "defaults") root.openScope(key)
      else {
        var d = root.phone ? root.phone.findDevice(key) : null
        if (!d) return "no device " + key
        root.openScope(String(d.id))
      }
      root.snapPage()
      return root.settingsInfo()
    }
    function settingsRowsInfo(): string { return root.settingsInfo() }
    // Demo only: a made-up caller ringing, or a call missed, on the viewed
    // device; "none" ends it.
    function demoCall(kind: string): string {
      if (!root.phone || !root.phone.demo) return "demo only"
      root.phone.showDemoCall(kind)
      return JSON.stringify(root.call)
    }
    function closeCall(): string { if (root.phone) root.phone.closeCall(); return JSON.stringify(root.call) }
    // Demo only: Text back, without focusing the composer (scripted).
    function pressTextBack(): string {
      if (!root.phone || !root.phone.demo) return "demo only"
      root.textBack(root.call, false)
      return JSON.stringify({ device: root.device ? root.device.id : "", call: root.call })
    }
    // Demo only: Text back to any number, as from a call.
    function demoTextTo(number: string): string {
      if (!root.phone || !root.phone.demo) return "demo only"
      root.textBack({ device: root.device ? String(root.device.id) : "", number: number, who: "" }, false)
      return "ok"
    }
    // Esc on the panel (not in a text field), as the key would.
    // Where the panel's card is on the desktop (for screenshots that show
    // the panel and nothing else): x, y, width, height in global pixels.
    function cardRect(): string {
      var o = panel.cardOrigin
      var sx = panel.screen ? panel.screen.x : 0, sy = panel.screen ? panel.screen.y : 0
      return JSON.stringify({ x: Math.round(sx + o.x), y: Math.round(sy + o.y), w: Math.round(panel.contentWidth), h: Math.round(panel.contentHeight) })
    }
    // The arrows, as pressed (dx, dy each -1, 0 or 1): never Enter, so a
    // check cannot open anything into a text field.
    function move(dx: int, dy: int): string { keyCatcher.moveRequested(dx, dy); return JSON.stringify({ section: root.focusSection, settingsIndex: root.settingsIndex }) }
    function pressEscape(): string { keyCatcher.closeRequested(); return JSON.stringify({ messages: root.messagesOpen, open: root.opened }) }
    // The right-click menu, opened as a right-click at x, y would.
    function pageMenu(x: int, y: int): string { root.openPageMenu(x, y); return JSON.stringify({ open: root.pageMenuOpen }) }
    // Checks while editing, as a click or a drag would: a section's switch, a
    // shortcut or bar indicator added or taken away, a section or a chosen
    // tile moved (glide), a bar switch.
    function editSection(key: string): string { root.toggleSectionShown(key); return JSON.stringify({ media: root.profile.showMedia, actions: root.profile.showShortcuts, notifications: root.profile.showNotifications, photos: root.profile.showPhotos, received: root.profile.showReceived }) }
    function editShortcut(key: string): string { root.toggleShortcutOnPage(key); return JSON.stringify(root.shortcutOrder) }
    function editMoveSection(key: string, delta: int): string { sectionMove.step(root.drawnSections.indexOf(key), delta); return "ok" }
    function editMoveShortcut(key: string, delta: int): string { tileMove.step(root.shortcutOrder.indexOf(key), delta); return "ok" }
    // A right-click on a device's chip (id, nickname or name; "" the first).
    function rightClickChip(key: string): string {
      var d = key === "" ? null : (root.phone ? root.phone.findDevice(key) : null)
      root.editFromBar(d ? String(d.id) : "")
      return JSON.stringify({ editing: root.editing, device: root.device ? String(root.device.id) : "" })
    }
    function editBar(key: string): string { root.toggleBarOnPage(key); return JSON.stringify(root.barOrder) }
    function editBarFlag(key: string): string { root.toggleBarFlagOnPage(key); return JSON.stringify({ batteryLowOnly: root.profile.batteryLowOnly, showCalls: root.profile.showCalls }) }
    function editMoveBar(key: string, delta: int): string { barMove.step(root.barOrder.indexOf(key), delta); return "ok" }
    // Edit the page in place, and again to finish; what editing shows.
    function edit(): string {
      root.toggleEditing()
      return JSON.stringify({ editing: root.editing, sections: root.drawnSections, shortcuts: root.shortcutOrder, bar: root.barOrder })
    }
    // Checks: a settings row pressed as a click would; a nickname entered as
    // Enter in its field would; an icon picked (hex, "" for its kind).
    function pressSetting(index: int): string { root.activateSetting(index); return root.settingsInfo() }
    function nickname(text: string): string { settingsView.nicknameSet(text); return root.settingsInfo() }
    function pickIcon(code: string): string { settingsView.iconSet(code); return root.settingsInfo() }
    // A settings row moved one step as the keyboard would (Reorder's glide);
    // the order's state right after, for checks.
    function glide(kind: string, pos: int, delta: int): string {
      var ok = settingsView.glideMove(kind, pos, delta)
      var o = settingsView.orderFor(kind)
      return JSON.stringify({ ok: ok, from: o ? o.from : null, to: o ? o.to : null, count: o ? o.count : null, itemSize: o ? o.itemSize : null, extent: o ? o.movingExtent : null })
    }
    // A tab dropped at another tab's place, as a drag would (checks the
    // order kept for devices without a tab).
    function dragTab(from: int, to: int): string {
      root.dropTab(from, to)
      return JSON.stringify(root.pairedDevices.map(function(x) { return x.id }))
    }
    function moveDevice(key: string, delta: int): string {
      var d = root.phone ? root.phone.findDevice(key) : null
      if (!d) return "no device " + key
      root.moveDevice(String(d.id), delta)
      return JSON.stringify(root.pairedDevices.map(function(x) { return x.id }))
    }
    function tabs(): string {
      var list = root.phone ? root.phone.ordered : []
      return JSON.stringify({ shown: root.manyDevices, viewed: root.device ? root.device.id : "",
        tabs: root.tabDevices.map(function(d) { return d.id }),
        pill: root.phone ? root.phone.pill.chips.map(function(c) { return { id: c.id, text: c.text, bubble: c.bubble, dimmed: c.dimmed } }) : [],
        resting: root.phone ? root.phone.pill.resting : null, pairing: root.phone ? root.phone.pill.pairing : false })
    }
    function devices(): string { return JSON.stringify(Model.devicesListRows(root.snapshot, root.profilesRead, root.lowPercent).map(function(r) { return r.kind + ":" + r.title + ":" + r.status.split(" ·")[0] })) }
    function fold(key: string): string { root.toggleCollapsed(key); return JSON.stringify(root.collapsed) }
    function pageState(): string {
      return JSON.stringify({ target: root.targetPage, shown: root.shownPage, running: pageSwap.running,
                              opacity: Math.round(pageHost.opacity * 100) / 100, slide: Math.round(pageHost.slide) })
    }
    function smsStatus(): string {
      var s = root.sms
      if (!s) return "{}"
      return JSON.stringify({ active: s.active, ready: s.ready, threads: s.threads.count, unread: s.unreadCount,
        open: s.openThreadId, loaded: s.messages.count, hasMore: s.hasMore, loading: s.loading,
        contacts: s.contactCount, error: s.lastError, composerFocused: messagesView ? messagesView.composerFocused : false,
        newMessage: messagesView && messagesView.newMode ? { to: messagesView.recipients.map(function(r) { return r.number }), typed: messagesView.toText, suggestions: messagesView.suggestions.length } : null,
        search: messagesView ? messagesView.searchText : "" })
    }
    function loadOlder(): string { if (root.sms) root.sms.loadMore(); return "ok" }
    function searchThreads(q: string): string {
      if (!root.sms) return "0"
      if (messagesView) messagesView.setSearch(q); else root.sms.setQuery(q)
      return String(root.sms.shownThreads.count)
    }
    // Scripted: shows the new-message pane without focusing anything.
    function newMessage(query: string): string {
      root.openFromHotkey(); root.openMessagesView(-1)
      messagesView.startNew(false)
      messagesView.setToText(query)
      return JSON.stringify(messagesView.suggestions.map(function(c) { return { hasName: c.name !== "", tid: c.tid } }))
    }
    function firstThreads(n: int): string {
      var s = root.sms, out = []
      for (var i = 0; s && i < Math.min(n, s.threads.count); i++) { var t = s.threads.get(i); out.push({ tid: t.tid, unread: t.unread, group: t.group }) }
      return JSON.stringify(out)
    }
    function media(action: string): string { if (root.phone) root.phone.mediaAction(action); return "ok" }
    function volume(percent: int): string { root.setVolumeWish(percent / 100); return "ok" }
    function showPlayer(index: int): string { root.showPlayer(index); return String(root.shownPlayer) }
    function seekTo(index: int, seconds: int): string {
      var p = root.players[index]
      if (!p || !root.phone) return "no player at " + index
      root.phone.seek(p, seconds)
      return "ok"
    }
    function demo(kind: string): string { root.enterDemo(kind); return "demo " + kind }
    function openReply(index: int): string {
      var n = root.notifications[index]
      if (!n || !n.replyId) return "no replyable notification at " + index
      root.cursorActive = true; root.focusSection = "notifications"; root.notifIndex = index
      root.openReply(n)
      return "ok"
    }
    // Files: what the section holds; a received file forgotten, as its ×.
    function filesInfo(): string {
      return JSON.stringify({ photos: root.photos.map(function(p) { return p.name }), received: root.received.map(function(r) { return r.name }),
        albums: root.photoInfo && root.photoInfo.albums ? root.photoInfo.albums.map(function(a) { return a.name }) : [],
        state: root.photoInfo ? { ok: root.photoInfo.ok, missing: root.photoInfo.missing || "" } : null })
    }
    function dismissReceived(index: int): string {
      if (root.phone) root.phone.dismissReceived(root.received[index])
      return JSON.stringify(root.received.map(function(r) { return r.name }))
    }
    function live(): string { if (root.phone) root.phone.showLive(); root.leaveDemo(); return "live" }
    // The phone Add a device's QR code is for, as its toggle would: android or ios.
    function appPlatform(platform: string): string { root.setAppPlatform(platform); return root.appPlatform }
    // Preview with a demo phone (on) or Back to setup (off), as the buttons would.
    function preview(on: bool): string {
      if (on) root.startPreview(); else root.backToSetup()
      return JSON.stringify({ preview: !!root.phone && root.phone.preview, demo: !!root.phone && root.phone.demo })
    }
    function settings(): string { root.openFromHotkey(); root.openSettings(); return "ok" }
    function toggleLayout(key: string): string { root.toggleLayout(key); return "ok" }
    // Scripted: shows the send-text composer with `text` in it, never focused.
    function compose(text: string): string {
      root.composing = text !== "-"
      composerField.text = text === "-" ? "" : text
      return JSON.stringify({ open: root.composing, focused: root.composerFocused, hint: Model.composerHint(composerField.text, root.device, root.can.ping === true) })
    }
    function toggleShortcut(key: string): string { root.toggleShortcutKey(key); return "ok" }
    function moveShortcut(key: string, delta: int): string { root.moveShortcutKey(key, delta); return "ok" }
    function moveSection(key: string, delta: int): string { root.moveSectionKey(key, delta); return JSON.stringify(root.sectionOrder) }
    function toggleBar(key: string): string {
      if (key === "batteryLowOnly" || key === "showCalls") { var flag = {}; flag[key] = !root.editProfile[key]; root.persistScoped(flag) }
      else root.persistScoped({ barIndicators: Model.toggleBarIndicator(root.editProfile.barIndicators, key) })
      return JSON.stringify({ indicators: root.editProfile.barIndicators, lowOnly: root.editProfile.batteryLowOnly, calls: root.editProfile.showCalls })
    }
    function moveBar(key: string, delta: int): string { root.moveBarIndicator(key, delta); return JSON.stringify(root.barIndicators) }
    function resetShortcuts(): string { root.resetShortcuts(); return "ok" }
    // What the panel is showing, so a check can assert on the picture.
    function status(): string {
      return JSON.stringify({
        opened: root.opened,
        messagesOpen: root.messagesOpen,
        preview: !!root.phone && root.phone.preview,
        editing: root.editing,
        call: root.call,
        daemon: root.phone ? root.phone.daemon : false,
        device: root.device ? root.device.name : null,
        reachable: root.reachable,
        bar: Model.barText(root.device, root.barIndicators, { lowPercent: root.lowPercent, lowOnly: root.batteryLowOnly,
          notifications: root.notifications.length, messages: root.sms ? root.sms.unreadCount : 0,
          playing: !!root.phone && root.phone.nowPlaying !== "" }),
        bubble: Model.barBubble(root.device, root.barIndicators, root.notifications.length),
        meta: Model.metaLine(root.snapshot, root.device),
        battery: Model.batteryText(root.device),
        players: root.players.map(function(p) {
          return { app: Model.playerApp(p.identity, root.device ? root.device.name : ""),
                   title: p.trackTitle, playing: p.isPlaying,
                   position: Math.round(p.position), length: Math.round(p.length),
                   canSeek: p.canSeek, positionSupported: p.positionSupported,
                   volume: p.volumeSupported ? p.volume : null }
        }),
        notifications: root.notifications.length,
        actionStatus: root.phone ? root.phone.actionStatus : "",
        busy: root.phone ? Object.keys(root.phone.busy) : [],
        watchError: root.phone ? root.phone.watchError : "",
        settingsOpen: root.settingsOpen,
        layout: { showShortcuts: root.showShortcuts, showMedia: root.showMedia, showNotifications: root.showNotifications, showPhotos: root.showPhotos, showReceived: root.showReceived },
        files: { photos: root.photos.length, received: root.received.length, state: root.photoInfo ? { ok: root.photoInfo.ok, loading: !!root.photoInfo.loading, missing: root.photoInfo.missing || "", error: root.photoInfo.error || "" } : null },
        shortcuts: root.shortcutOrder,
        sections: root.sections,
        shownPlayer: root.shownPlayer,
        volume: { reported: root.reportedVolume, wish: root.volumeWish, shown: root.shownVolume },
        shownPlaying: cardRepeater.itemAt(root.shownPlayer) ? cardRepeater.itemAt(root.shownPlayer).playing : null,
        cardsBuilt: root.cardsBuilt,
        sectionOrder: root.sectionOrder, settingsIndex: root.settingsIndex,
        composing: root.composing, composerFocused: root.composerFocused, replying: root.replyingTo, cursor: root.cursorActive ? root.focusSection + ":" + (root.focusSection === "notifications" ? root.notifIndex : root.actionIndex) : "",
        browsed: root.browsedName
      })
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.barIdentity
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: root.cardWidth
    contentHeight: root.cardHeight

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      blocked: root.replyFocused || root.composerFocused || root.nicknameFocused || (root.messagesOpen && !!messagesView && messagesView.composerFocused)

      onMoveRequested: function(dx, dy) {
        if (root.messagesOpen) { messagesView.moveKey(dx, dy); return }
        // A key moved it: the cursor slides, and the page follows it.
        if (root.cursorGlide) root.cursorGlide.keyedAt = Date.now()
        Qt.callLater(root.followCursor)
        if (root.settingsOpen) {
          if (!root.cursorActive) { root.cursorActive = true; return }
          if (dy !== 0) root.settingsIndex = root.nextSettingsRow(root.settingsIndex, dy)
          return
        }
        if (!root.cursorActive) { root.cursorActive = true; root.ensureCursor(); return }
        root.moveCursor(dx, dy)
      }
      onActivateRequested: {
        if (root.messagesOpen) { messagesView.activateCursor(); return }
        if (!root.cursorActive) return
        if (root.settingsOpen) root.activateSetting(root.settingsIndex)
        else root.activateCursor()
      }
      onDeleteRequested: {
        if (root.mainView && root.cursorActive && root.focusSection === "received") {
          if (root.phone) root.phone.dismissReceived(root.received[root.receivedIndex])
          return
        }
        if (root.mainView && root.cursorActive && root.focusSection === "notifications") {
          var n = root.notifications[root.notifIndex]
          if (n && n.dismissable) root.phone.dismiss(n)
        }
      }
      onCloseRequested: {
        if (root.pageMenuOpen) root.closePageMenu()
        else if (root.editing) root.cancelEditing()
        else if (root.messagesOpen) { if (!messagesView.goBack()) root.closeMessagesView() }
        else if (root.settingsOpen) { if (!root.settingsBack()) root.closeSettings() }
        else root.close()
      }
      onTabRequested: function(direction) { root.switchPanel(direction) }
      // PgUp/PgDn in messages: the conversation list a screen at a time, as
      // the arrows move it a row; while writing a reply, the open
      // conversation instead. Keys has no page-key handlers and a second
      // Keys.onPressed here would replace the catcher's own, so these are
      // window shortcuts, live only while messages are open.
      Shortcut {
        sequences: ["PgUp"]
        enabled: root.opened && !root.messagesOpen
        onActivated: root.pageBy(1)
      }
      Shortcut {
        sequences: ["PgDown"]
        enabled: root.opened && !root.messagesOpen
        onActivated: root.pageBy(-1)
      }
      Shortcut {
        sequences: ["PgUp"]
        enabled: root.opened && root.messagesOpen
        onActivated: if (messagesView) { if (messagesView.typingReply) messagesView.scrollMessages(1); else if (messagesView.inConversation) messagesView.pageMessage(1); else messagesView.pageCursor(1) }
      }
      Shortcut {
        sequences: ["PgDown"]
        enabled: root.opened && root.messagesOpen
        onActivated: if (messagesView) { if (messagesView.typingReply) messagesView.scrollMessages(-1); else if (messagesView.inConversation) messagesView.pageMessage(-1); else messagesView.pageCursor(-1) }
      }
      onTextKey: function(t) {
        if (root.messagesOpen) {
          if (!messagesView) return
          if (t === "i") messagesView.focusComposer()
          else if (t === "n") messagesView.startNew(true)
          else if (t === "/") messagesView.focusSearch()
          else if (t === "u") root.toggleUnreadOnly()
          else if (t === "g") messagesView.cursorTo(0)
          else if (t === "G") messagesView.cursorTo(1e9)
          return
        }
        if (t === "m") { root.openMessagesView(-1); return }
        if (root.settingsOpen) {
          var row = root.settingsRows[root.settingsIndex]
          // Shift+K / Shift+J glide the row like its arrows (Reorder).
          if (root.cursorActive && row && (t === "K" || t === "J")
              && (row.kind === "device" || row.kind === "layout" || ((row.kind === "shortcut" || row.kind === "bar") && row.on)))
            settingsView.glideMove(row.kind, row.pos, t === "K" ? -1 : 1)
          return
        }
        if (t === "s") { root.openSettings(); return }
        // E: edit this page in place, and again to finish.
        if (t === "E") { root.toggleEditing(); return }
        // Editing: Shift+K / Shift+J move the section under the cursor.
        if (root.editing && (t === "K" || t === "J") && root.cursorActive) {
          sectionMove.step(root.drawnSections.indexOf(root.focusSection), t === "K" ? -1 : 1)
          return
        }
        // Tabs (with two or more devices): 1-9, and Shift+H / Shift+L.
        if (root.manyDevices && t >= "1" && t <= "9") { root.tabAt(Number(t) - 1); return }
        if (root.manyDevices && (t === "H" || t === "L")) { root.tabStep(t === "H" ? -1 : 1); return }
        if (t === "c" && root.cursorActive && root.focusSection !== "") {
          root.toggleCollapsed(root.focusSection)
          return
        }
        if (t === "-") { root.nudgeVolume(-0.05); return }
        if (t === "=" || t === "+") { root.nudgeVolume(0.05); return }
        if (t === ",") { root.nudgePosition(-10); return }
        if (t === ".") { root.nudgePosition(10); return }
        if (t === "[" && root.phone) { root.phone.mediaAction("Previous", root.shownPlayerObject); return }
        if (t === "]" && root.phone) { root.phone.mediaAction("Next", root.shownPlayerObject); return }
        if (t === "e" && root.cursorActive && root.focusSection === "notifications") { root.toggleExpanded(root.notifications[root.notifIndex]); return }
        if (t === "o" && root.cursorActive && root.focusSection === "notifications") {
          var tn = root.notifications[root.notifIndex]
          if (root.isTextNotification(tn)) root.openNotificationConversation(tn)
          return
        }
        if (t === "r" && root.cursorActive && root.focusSection === "notifications")
          root.openReply(root.notifications[root.notifIndex])
      }

      // ---- The page menu (right-click): Edit page, Settings ----
      MouseArea {
        anchors.fill: parent
        z: 20
        visible: root.pageMenuOpen
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        onPressed: root.closePageMenu()
      }
      BorderSurface {
        id: pageMenu
        z: 21
        visible: root.pageMenuOpen
        x: Math.min(root.menuAt.x, parent.width - width - Style.space(6))
        y: Math.min(root.menuAt.y, parent.height - height - Style.space(6))
        width: menuColumn.implicitWidth + Style.space(8)
        height: menuColumn.implicitHeight + Style.space(8)
        radius: Style.cornerRadius
        color: root.bar ? root.bar.background : Color.background
        borderSpec: Border.controlSpec("normal", root.foreground, Color.accent)
        Column {
          id: menuColumn
          anchors.centerIn: parent
          // As wide as its widest entry (the entries fill it).
          width: Math.max(menuEdit.implicitWidth, menuSettings.implicitWidth)
          Button {
            id: menuEdit
            width: menuColumn.width
            leftAlign: true
            iconText: Model.GLYPH.edit
            text: "Edit page"
            foreground: root.foreground
            fontFamily: root.fontFamily
            fontSize: Style.font.bodySmall
            onClicked: { root.closePageMenu(); root.startEditing() }
          }
          Button {
            id: menuSettings
            width: menuColumn.width
            leftAlign: true
            iconText: Model.GLYPH.settings
            text: "Settings"
            foreground: root.foreground
            fontFamily: root.fontFamily
            fontSize: Style.font.bodySmall
            onClicked: { root.closePageMenu(); root.openSettings() }
          }
        }
      }

      BorderSurface {
        id: toast
        property string shownText: ""
        property bool shownFailed: false
        readonly property bool showing: root.toastText !== ""
        onShowingChanged: if (showing) { shownText = root.toastText; shownFailed = root.toastFailed }
        Connections {
          target: root
          function onToastTextChanged() { if (root.toastText !== "") { toast.shownText = root.toastText; toast.shownFailed = root.toastFailed } }
        }

        z: 10
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: Style.space(8) + (showing ? 0 : -Style.space(10))
        width: Math.min(parent.width - Style.space(32), toastLabel.implicitWidth + Style.space(28))
        height: toastLabel.implicitHeight + Style.space(14)
        radius: Style.cornerRadius
        color: root.bar ? root.bar.background : Color.background
        borderSpec: Border.controlSpec(shownFailed ? "focus" : "normal", shownFailed ? root.urgent : root.foreground, Color.accent)
        opacity: showing ? 1 : 0
        visible: opacity > 0.01

        Behavior on opacity { NumberAnimation { duration: (toast.showing ? Model.MOTION.inMs : Model.MOTION.outMs) * root.motion; easing.type: Easing.OutCubic } }
        Behavior on anchors.bottomMargin { NumberAnimation { duration: Model.MOTION.inMs * root.motion; easing.type: Easing.OutCubic } }

        Text {
          id: toastLabel
          anchors.centerIn: parent
          width: Math.min(implicitWidth, toast.parent ? toast.parent.width - Style.space(60) : implicitWidth)
          horizontalAlignment: Text.AlignHCenter
          wrapMode: Text.WordWrap
          textFormat: Text.PlainText
          text: toast.shownText
          color: toast.shownFailed ? root.urgent : root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
        }
      }

      Flickable {
        id: panelFlick
        WheelScroll { flickable: panelFlick; motion: root.motion }
        anchors.fill: parent
        contentWidth: width
        contentHeight: column.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        flickableDirection: Flickable.VerticalFlick
        interactive: contentHeight > height
        ScrollBar.vertical: ScrollBar { id: pageScrollBar; policy: ScrollBar.AsNeeded }
        // Right-click anywhere on the main page opens its menu; other buttons
        // pass through to the page.
        MouseArea {
          x: column.x
          width: column.width
          height: column.height
          z: 50
          enabled: root.showMain && !root.editing
          acceptedButtons: Qt.RightButton
          // A MouseArea claims the arrow from the start; this one covers the
          // page, so it gives the cursor back to the controls under it.
          cursorShape: undefined
          onClicked: function(m) { var p = mapToItem(keyCatcher, m.x, m.y); root.openPageMenu(p.x, p.y) }
        }

        Column {
          id: column
          // Inside the page margins (pageGutter), on every page.
          x: root.pageGutter
          // Laid out at the card's final width while the card itself is still
          // animating, so the page never re-flows during a page change.
          width: panelFlick.width + (root.targetCardWidth - root.cardWidth) - 2 * root.pageGutter
          spacing: Style.space(12)

          // ---- Preview: says the phone is a demo, with the way back ----
          // Leaving with Back to setup, it stays until the page change's
          // midpoint, fading with the old page, then folds away with the
          // panel's resize: closing at the click moved the page under it.
          FoldBody {
            id: previewStrip
            property bool held: false
            open: (!!root.phone && root.phone.preview) || held
            motion: root.motion
            animate: root.settled
            BorderSurface {
              id: previewStripCard
              width: parent.width
              implicitHeight: previewRow.implicitHeight + Style.space(14)
              radius: Style.cornerRadius
              color: Style.selectedFillFor(root.foreground, Color.accent)
              borderSpec: Border.controlSpec("hover-cursor", root.foreground, Color.accent)
              RowLayout {
                id: previewRow
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                anchors.leftMargin: Style.space(12)
                anchors.rightMargin: Style.space(8)
                spacing: Style.space(10)
                Text {
                  text: Model.GLYPH.devices
                  color: Color.accent
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.icon
                }
                ColumnLayout {
                  Layout.fillWidth: true
                  spacing: Style.space(1)
                  Text {
                    Layout.fillWidth: true
                    textFormat: Text.PlainText
                    text: "Demo: set up KDE Connect to see your phone"
                    color: root.foreground
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.bodySmall
                    font.bold: true
                    wrapMode: Text.WordWrap
                  }
                  Text {
                    Layout.fillWidth: true
                    textFormat: Text.PlainText
                    text: "Made-up data; nothing here reaches a device"
                    color: root.dim
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                    wrapMode: Text.WordWrap
                  }
                }
                Button {
                  text: "Back to setup"
                  bordered: true
                  foreground: root.foreground
                  fontFamily: root.fontFamily
                  fontSize: Style.font.bodySmall
                  onClicked: root.backToSetup()
                }
              }
            }
          }

          // ---- The pairing card: a device asking to pair, at the top, above
          //      the tabs (it is about all devices, not the one viewed),
          //      pushing everything down until it is answered. It grows in
          //      and out at the plugin's pace (FoldBody), never jumps ----
          FoldBody {
            open: pairCard.showing
            motion: root.motion
            animate: root.settled
            BorderSurface {
              id: pairCard
              // Kept while it fades out, so the text does not blank mid-fade.
              property var shown: null
              readonly property var request: root.phone ? root.phone.pairingRequest : null
              readonly property bool showing: !!request && root.showMain
              onRequestChanged: if (request) shown = request
              Component.onCompleted: if (request) shown = request
              readonly property bool waiting: !!shown && !!root.phone
                && (root.phone.isBusy("accept:" + shown.id) || root.phone.isBusy("reject:" + shown.id))

              width: parent.width
              height: pairRow.implicitHeight + Style.space(20)
              radius: Style.cornerRadius
              color: root.bar ? root.bar.background : Color.background
              borderSpec: Border.controlSpec("focus", root.foreground, Color.accent)


              // Clicks on the card stay on the card.
              MouseArea { anchors.fill: parent }

              // The same pattern as the pop-up (PairingPopup): the device and
              // what it asks; then the key and the answer on one row.
              RowLayout {
                id: pairRow
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                anchors.leftMargin: Style.space(14)
                anchors.rightMargin: Style.space(12)
                spacing: Style.space(14)

                Text {
                  textFormat: Text.PlainText
                  text: Model.deviceGlyph(pairCard.shown)
                  color: Color.accent
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.display
                  Layout.alignment: Qt.AlignTop
                  Layout.topMargin: Style.space(2)
                }
                ColumnLayout {
                  Layout.fillWidth: true
                  spacing: Style.space(8)
                  Text {
                    Layout.fillWidth: true
                    textFormat: Text.PlainText
                    elide: Text.ElideRight
                    text: (pairCard.shown ? Model.deviceLabel(pairCard.shown) : "") + " wants to pair"
                    color: root.foreground
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.body
                    font.bold: true
                  }
                  RowLayout {
                    Layout.fillWidth: true
                    spacing: Style.space(8)
                    PairingKey {
                      Layout.fillWidth: true
                      Layout.alignment: Qt.AlignBottom
                      key: pairCard.shown ? String(pairCard.shown.verificationKey || "") : ""
                      caption: "check it matches"
                      foreground: root.foreground
                      fontFamily: root.fontFamily
                    }
                    Item { Layout.fillWidth: true; visible: !pairCard.shown || !pairCard.shown.verificationKey }
                    Button {
                      Layout.alignment: Qt.AlignBottom
                      text: pairCard.waiting ? "Waiting…" : "Accept"
                      bordered: true
                      enabled: !pairCard.waiting
                      foreground: root.foreground
                      fontFamily: root.fontFamily
                      fontSize: Style.font.bodySmall
                      onClicked: if (root.phone && pairCard.shown) root.phone.acceptPairing(pairCard.shown.id)
                    }
                    Button {
                      Layout.alignment: Qt.AlignBottom
                      text: "Reject"
                      enabled: !pairCard.waiting
                      foreground: root.foreground
                      fontFamily: root.fontFamily
                      fontSize: Style.font.bodySmall
                      onClicked: if (root.phone && pairCard.shown) root.phone.rejectPairing(pairCard.shown.id)
                    }
                  }
                }
              }
            }
          }

          // ---- The call card: a device ringing, or a call missed, at the
          //      top above the tabs (it may be about any device), pushing
          //      everything down while it lasts; it grows in and out ----
          FoldBody {
            open: callCard.showing
            motion: root.motion
            animate: root.settled
            BorderSurface {
              id: callCard
              // Kept while it closes, so the text does not blank mid-fold.
              property var shown: null
              readonly property bool showing: !!root.call && root.showMain
              readonly property bool ringing: !!shown && shown.state === "ringing"
              Connections {
                target: root
                function onCallChanged() { if (root.call) callCard.shown = root.call }
              }
              Component.onCompleted: if (root.call) shown = root.call
              width: parent.width
              height: callRow.implicitHeight + Style.space(20)
              radius: Style.cornerRadius
              color: root.bar ? root.bar.background : Color.background
              borderSpec: Border.controlSpec(ringing ? "focus" : "normal", root.foreground, Color.accent)

              // Clicks on the card stay on the card.
              MouseArea { anchors.fill: parent }

              RowLayout {
                id: callRow
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                anchors.leftMargin: Style.space(12)
                anchors.rightMargin: Style.space(8)
                spacing: Style.space(10)

                // Ringing: the handset and its waves, moving on the ring beat.
                RingingPhone {
                  visible: callCard.ringing
                  ringing: callCard.ringing && callCard.showing && root.opened
                  color: Color.accent
                  fontFamily: root.fontFamily
                  size: Style.font.display
                  motion: root.motion
                  Layout.alignment: Qt.AlignVCenter
                }
                Text {
                  visible: !callCard.ringing
                  textFormat: Text.PlainText
                  text: Model.GLYPH.callMissed
                  color: root.urgent
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.display
                  Layout.alignment: Qt.AlignVCenter
                }

                Column {
                  Layout.fillWidth: true
                  Layout.alignment: Qt.AlignVCenter
                  spacing: Style.space(2)
                  Text {
                    width: parent.width
                    textFormat: Text.PlainText
                    elide: Text.ElideRight
                    // With several devices, which one it came to.
                    text: Model.callHeading(callCard.shown)
                      + (root.manyDevices && root.callDevice ? " · " + Model.deviceTitle(root.callDevice, root.callProfile).toUpperCase() : "")
                    color: root.dim
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                  }
                  Text {
                    width: parent.width
                    textFormat: Text.PlainText
                    elide: Text.ElideRight
                    text: callCard.shown ? callCard.shown.who : ""
                    color: root.foreground
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.body
                    font.bold: true
                  }
                  Text {
                    width: parent.width
                    visible: text !== ""
                    textFormat: Text.PlainText
                    elide: Text.ElideRight
                    text: callCard.shown ? callCard.shown.detail : ""
                    color: root.dim
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.bodySmall
                  }
                }

                // Missed: call back on the device. Ringing: answering is the phone's.
                PanelActionButton {
                  visible: !callCard.ringing && !!callCard.shown && callCard.shown.number !== ""
                    && !!root.callDevice && !!root.callDevice.can && root.callDevice.can.share === true
                  iconText: Model.GLYPH.callBack
                  tooltipText: "Call back from " + Model.deviceTitle(root.callDevice, root.callProfile)
                  foreground: root.foreground
                  fontFamily: root.fontFamily
                  onClicked: root.callBack(callCard.shown)
                }
                PanelActionButton {
                  visible: !!callCard.shown && callCard.shown.number !== ""
                    && !!root.callDevice && !!root.callDevice.can && root.callDevice.can.sms === true
                  iconText: Model.GLYPH.callText
                  tooltipText: callCard.ringing ? "Text instead" : "Text back"
                  foreground: root.foreground
                  fontFamily: root.fontFamily
                  onClicked: root.textBack(callCard.shown, true)
                }
                PanelActionButton {
                  iconText: Model.GLYPH.close
                  tooltipText: "Close"
                  foreground: root.foreground
                  fontFamily: root.fontFamily
                  onClicked: if (root.phone) root.phone.closeCall()
                }
              }
            }
          }

          // ---- Tabs: one per device, only with two or more. Main page and
          //      messages; settings has its own device list ----
          Item {
            id: tabBox
            visible: root.manyDevices && !root.showSettings
            width: parent.width
            height: visible ? tabRow.implicitHeight : 0

          // Settings for all devices sits on the devices' own line, at its
          // end (as a phone picker and its settings do): the header below
          // is only the viewed device's. With one device there is no tab
          // row, and the gear stays in the header.
          PanelActionButton {
            id: tabsGear
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            visible: root.showMain
            iconText: Model.GLYPH.settings
            tooltipText: root.computerIssues > 0 ? "Settings · Connection: " + Model.connectionSummary(root.setupChecks, root.ignoredChecks) : "Settings"
            foreground: root.foreground
            fontFamily: root.fontFamily
            onClicked: root.computerIssues > 0 ? root.openConnection() : root.openSettings()
            GearDot { visible: root.computerIssues > 0 }
          }

          Flickable {
            id: tabStrip
            anchors.left: parent.left
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            anchors.right: tabsGear.visible ? tabsGear.left : parent.right
            anchors.rightMargin: tabsGear.visible ? Style.space(6) : 0
            contentWidth: tabRow.implicitWidth
            contentHeight: tabRow.implicitHeight
            clip: true
            interactive: contentWidth > width
            boundsBehavior: Flickable.StopAtBounds
            flickableDirection: Flickable.HorizontalFlick
            // More tabs to either side (the arrows show then).
            readonly property bool moreLeft: contentX > 1
            readonly property bool moreRight: contentX + width < contentWidth - 1

            // Glides to a place at the plugin's pace.
            NumberAnimation { id: tabGlide; target: tabStrip; property: "contentX"; duration: Model.MOTION.inMs * root.motion; easing.type: Easing.OutCubic }
            function glideTo(x) {
              tabGlide.stop()
              tabGlide.to = Math.max(0, Math.min(contentWidth - width, x))
              tabGlide.start()
            }
            // One step: most of a row's width, so a tab cut at the edge comes
            // fully into view.
            function page(dir) { glideTo(contentX + dir * width * 0.7) }

            // The wheel (either direction) scrolls the row sideways.
            WheelHandler {
              target: null
              acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
              onWheel: function(event) {
                var d = event.angleDelta.x !== 0 ? event.angleDelta.x : event.angleDelta.y
                if (tabStrip.contentWidth > tabStrip.width) tabStrip.glideTo(tabStrip.contentX - d)
              }
            }

            Row {
              id: tabRow
              spacing: Style.space(4)
              Repeater {
                id: tabRepeater
                model: root.tabDevices
                Button {
                  id: tab
                  required property var modelData
                  required property int index
                  readonly property int deviceIndex: {
                    var list = root.phone ? root.phone.ordered : []
                    for (var i = 0; i < list.length; i++) if (list[i].id === modelData.id) return i
                    return 0
                  }
                  readonly property var tabProfile: root.phone ? Model.resolveProfile(root.phone.profiles, modelData, deviceIndex === 0) : null
                  readonly property var st: root.phone && root.phone.deviceStates[modelData.id] ? root.phone.deviceStates[modelData.id] : ({})
                  readonly property var news: Model.attention(modelData, tabProfile, st)
                  readonly property bool current: !!root.device && root.device.id === modelData.id
                  iconText: Model.deviceIcon(modelData, tabProfile)
                  // Its marks, in its own glyphs: the count, a low battery.
                  text: Model.deviceTitle(modelData, tabProfile)
                    + (news.notifications > 0 ? " " + news.notifications : "")
                    + (news.lowBattery ? " " + String.fromCodePoint(0xF0083) : "")
                  selected: current
                  bordered: true
                  // Dimmed while away, and on the Messages page for a device
                  // without text messages (switchDevice says why).
                  readonly property bool textless: root.showMessages && !root.hasTexts(modelData)
                  opacity: modelData.reachable === true && !textless ? 1 : 0.5
                  foreground: root.foreground
                  fontFamily: root.fontFamily
                  fontSize: Style.font.bodySmall
                  iconSize: Style.font.body
                  tooltipText: tab.moving ? "" : textless ? Model.deviceLabel(modelData) + " has no text messages"
                    : Model.deviceLabel(modelData) + " · " + (modelData.reachable === true ? Model.metaLine(root.snapshot, modelData, root.lowPercent) : "Away")
                  onClicked: root.switchDevice(modelData.id)
                  onCurrentChanged: if (current) tabStrip.showTab(tab)

                  // Drag a tab sideways to move its device in the order (a
                  // click still selects it: the drag starts past a threshold).
                  // The others slide aside; it glides in on release (Reorder).
                  readonly property bool moving: tabOrder.from === tab.index
                  transform: ReorderShift { order: tabOrder; index: tab.index }
                  z: moving ? 5 : 0
                  // Solid while dragged, so the tab it passes over never shows
                  // through; otherwise the kit's own fills (hover, selected).
                  color: tab.moving ? Qt.tint(root.bar ? root.bar.background : Color.background, Style.hoverFillFor(root.foreground, Color.accent))
                    : hot ? Style.hoverFillFor(root.foreground, Color.accent)
                    : selected ? Style.selectedFillFor(root.foreground, Color.accent) : "transparent"
                  DragHandler {
                    id: tabDrag
                    target: null
                    yAxis.enabled: false
                    grabPermissions: PointerHandler.CanTakeOverFromAnything
                    onTranslationChanged: if (active) tabOrder.dragTo(translation.x)
                    onActiveChanged: {
                      if (active) tabOrder.begin(tab.index, tab.width)
                      else tabOrder.release()
                    }
                  }
                }
              }
            }

            // Keeps the selected tab in view when the row scrolls, clear of
            // the arrows.
            function showTab(item) {
              if (!item) return
              var pad = tabArrowWidth
              if (item.x - pad < contentX) glideTo(item.x - pad)
              else if (item.x + item.width + pad > contentX + width) glideTo(item.x + item.width + pad - width)
            }
            readonly property real tabArrowWidth: Style.space(28)

            // The tabs' order, moved by dragging a tab (sideways).
            Reorder {
              id: tabOrder
              axis: "x"
              count: root.tabDevices.length
              gap: tabRow.spacing
              motion: root.motion
              extentOf: function(i) { var t = tabRepeater.itemAt(i); return t ? t.width : 0 }
              onMoved: function(a, b) { root.dropTab(a, b) }
            }
          }

          // The arrows: at an edge with more tabs beyond it, over a fade into
          // the panel, so a cut tab reads as "more this way".
          component TabArrow: Item {
            id: arrow
            property int dir: 1
            property bool shown: false
            width: tabStrip.tabArrowWidth + Style.space(12)
            height: parent.height
            opacity: shown ? 1 : 0
            visible: opacity > 0.01
            Behavior on opacity { NumberAnimation { duration: (arrow.shown ? Model.MOTION.inMs : Model.MOTION.outMs) * root.motion; easing.type: Easing.OutCubic } }
            Rectangle {
              anchors.fill: parent
              gradient: Gradient {
                orientation: Gradient.Horizontal
                GradientStop { position: 0; color: arrow.dir > 0 ? "transparent" : (root.bar ? root.bar.background : Color.background) }
                GradientStop { position: 0.45; color: root.bar ? root.bar.background : Color.background }
                GradientStop { position: 1; color: arrow.dir > 0 ? (root.bar ? root.bar.background : Color.background) : "transparent" }
              }
              rotation: 0
            }
            PanelActionButton {
              anchors.verticalCenter: parent.verticalCenter
              anchors.right: arrow.dir > 0 ? parent.right : undefined
              anchors.left: arrow.dir < 0 ? parent.left : undefined
              iconText: arrow.dir > 0 ? Model.GLYPH.right : Model.GLYPH.left
              tooltipText: arrow.dir > 0 ? "More devices" : "Back"
              foreground: root.foreground
              fontFamily: root.fontFamily
              onClicked: tabStrip.page(arrow.dir)
            }
          }
          TabArrow { dir: -1; shown: tabStrip.moreLeft; anchors.left: tabStrip.left }
          TabArrow { dir: 1; shown: tabStrip.moreRight; anchors.right: tabStrip.right }
          }

          PanelHero {
            id: hero
            width: parent.width
            // The pointer on the header reveals ✎ (edit this page).
            HoverHandler { id: heroHover }
            // Nickname, then the full name when they differ.
            title: {
              if (!root.heroDevice) return "Devices"
              var nick = root.heroProfile ? root.heroProfile.nickname : ""
              return nick && nick !== root.heroDevice.name ? nick + " · " + root.heroDevice.name : String(root.heroDevice.name || "")
            }
            // On a device's page the title already names it.
            meta: root.showSettings ? (root.screenId !== "" ? "Screen and apps" : root.settingsScope === "connection" ? "Connection" : root.settingsScope === "addDevice" ? "Add a device"
                : root.settingsScope === "defaults" && !root.editingDevice ? "Settings · Defaults for all devices" : "Settings")
              : (root.showMessages ? (root.sms && root.sms.ready ? "Messages · " + root.sms.threads.count + " conversations" : "Messages")
              : Model.metaLine(root.snapshot, root.device, root.lowPercent))
            foreground: root.foreground
            fontFamily: root.fontFamily
            iconOpacity: root.heroNeutral || (root.heroDevice && root.heroDevice.reachable === true) ? 1.0 : 0.45
            iconComponent: Component {
              Text {
                textFormat: Text.PlainText
                text: root.heroNeutral ? Model.GLYPH.devices : Model.deviceIcon(root.heroDevice, root.heroProfile)
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.display
              }
            }
            // Edit this page (✎, then ✓ Done), and the gear (only while there
            // is no tab row to carry it) or the back arrow on other pages.
            trailingControl: Component {
              Row {
                spacing: Style.space(2)
                // ✎ shows only while the pointer is on the header (or while
                // editing, as ✓): no noise at rest. It keeps its room either
                // way, so the gear beside it never moves.
                PanelActionButton {
                  visible: root.showMain && !!root.device
                  opacity: root.editing || heroHover.hovered ? 1 : 0
                  enabled: opacity > 0.5
                  Behavior on opacity { NumberAnimation { duration: (heroHover.hovered || root.editing ? Model.MOTION.inMs : Model.MOTION.outMs) * root.motion; easing.type: Easing.OutCubic } }
                  iconText: root.editing ? Model.GLYPH.check : Model.GLYPH.edit
                  tooltipText: root.editing ? "Done: keep the changes (Esc undoes them)" : "Edit this page"
                  foreground: root.editing ? Color.accent : root.foreground
                  fontFamily: root.fontFamily
                  onClicked: root.toggleEditing()
                }
                PanelActionButton {
                  visible: !(root.showMain && root.manyDevices)
                  iconText: root.showMain ? Model.GLYPH.settings : Model.GLYPH.back
                  tooltipText: !root.showMain ? "Back" : (root.computerIssues > 0 ? "Settings · Connection: " + Model.connectionSummary(root.setupChecks, root.ignoredChecks) : "Settings")
                  foreground: root.foreground
                  fontFamily: root.fontFamily
                  onClicked: {
                    if (root.messagesOpen) root.closeMessagesView()
                    else if (root.settingsOpen) { if (!root.settingsBack()) root.closeSettings() }
                    else if (root.computerIssues > 0) root.openConnection()
                    else root.openSettings()
                  }
                  GearDot { visible: root.showMain && root.computerIssues > 0 }
                }
              }
            }
          }

          // Everything below the header is one page, and changing page is an
          // animation: the old page slides out and fades, the page (and, for
          // messages, the panel size) swaps while nothing is visible, and the
          // new one slides in. See pageSwap.
          Item {
            id: pageHost
            property real slide: 0
            // The keyboard cursor of the main page and Settings: one
            // highlight behind the page, sliding to the row, tile or card
            // that holds it (CursorStop). Messages has its own.
            CursorGlide {
              shown: root.cursorActive && !root.showMessages
              motion: root.motion
              foreground: root.foreground
              Component.onCompleted: root.cursorGlide = this
            }
            readonly property real dpr: QW.Screen.devicePixelRatio > 0 ? QW.Screen.devicePixelRatio : 1
            width: parent.width
            height: pageColumn.implicitHeight
            implicitHeight: pageColumn.implicitHeight

            Column {
              id: pageColumn
              x: pageHost.slide
              width: parent.width
              spacing: Style.space(12)
              // ---- Editing: the device's chip in the Omarchy bar, as tiles: drag
              //      the chosen ones, click to add or take one away. The pill
              //      in the bar changes as they do: it is the preview ----
              FoldBody {
                id: barEdit
                open: root.editing && root.showMain
                motion: root.motion
                animate: root.settled
                spacing: Style.space(8)

                // Lined up with the section bars below: the chip's glyph
                // where their grips are (the bar is not a section; it does
                // not move).
                RowLayout {
                  x: Style.space(8)
                  width: parent.width - Style.space(16)
                  spacing: Style.space(10)
                  Text {
                    Layout.alignment: Qt.AlignVCenter
                    text: Model.deviceIcon(root.device, root.profile)
                    color: root.dim
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.body
                  }
                Column {
                  Layout.fillWidth: true
                  spacing: Style.space(1)
                  Text {
                    textFormat: Text.PlainText
                    text: "BAR"
                    color: root.foreground
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                    font.bold: true
                  }
                  Text {
                    width: parent.width
                    textFormat: Text.PlainText
                    text: "What its chip shows beside the glyph, in order"
                    color: root.dim
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                    elide: Text.ElideRight
                  }
                }
                }

                // The chip, drawn a little larger than in the bar: its glyph
                // (it does not move), then one cell per indicator as the bar
                // shows it, the chosen ones in order, a divider, the rest.
                BorderSurface {
                  width: parent.width
                  implicitHeight: flagsRow.y + flagsRow.height + Style.space(6)
                  radius: Style.cornerRadius
                  color: "transparent"
                  borderSpec: Border.controlSpec("normal", root.foreground, Color.accent)

                  Text {
                    id: chipGlyph
                    x: Style.space(10)
                    y: barGrid.y + Style.space(3)
                    text: Model.deviceIcon(root.device, root.profile)
                    color: root.foreground
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.body + 2
                  }

                  Grid {
                    id: barGrid
                    x: chipGlyph.x + chipGlyph.implicitWidth + Style.space(8)
                    y: Style.space(5)
                    width: parent.width - x - Style.space(6)
                    columns: 7
                    spacing: Style.space(2)
                    readonly property real cellWidth: (width - spacing * (columns - 1)) / columns

                    Reorder {
                      id: barMove
                      columns: barGrid.columns
                      cellWidth: barGrid.cellWidth
                      cellHeight: barGrid.children.length > 1 ? barGrid.children[1].height : 0
                      gap: barGrid.spacing
                      count: root.barOrder.length
                      motion: root.motion
                      onMoved: function(a, b) {
                        root.persistProfile({ barIndicators: Model.moveShortcut(root.barOrder, root.barOrder[a], b - a) })
                      }
                    }

                    Repeater {
                      model: root.editing ? Model.editBarTiles(root.barOrder) : []
                      BarTile {
                        required property var modelData
                        width: barGrid.cellWidth
                        tile: modelData
                      }
                    }
                  }

                  // Between what the chip shows and what it could.
                  Rectangle {
                    readonly property int shown: root.barOrder.length
                    visible: shown > 0 && shown < 7
                    x: barGrid.x + shown * (barGrid.cellWidth + barGrid.spacing) - barGrid.spacing / 2 - width / 2
                    y: barGrid.y + Style.space(2)
                    width: 1
                    height: barGrid.height - Style.space(4)
                    color: root.dim
                    opacity: 0.5
                  }

                  // Under a rule, inside the box: how the chip behaves. Compact,
                  // so they read as the bar's, not as sections of their own.
                  Rectangle {
                    id: flagsRule
                    x: Style.space(8)
                    y: barGrid.y + barGrid.height + Style.space(5)
                    width: parent.width - Style.space(16)
                    height: 1
                    color: root.dim
                    opacity: 0.3
                  }
                  RowLayout {
                    id: flagsRow
                    x: Style.space(10)
                    y: flagsRule.y + Style.space(5)
                    width: parent.width - Style.space(20)
                    spacing: Style.space(16)
                    Repeater {
                      model: [
                        { key: "batteryLowOnly", label: "Battery only when low", hint: "Off, the battery and its % always show" },
                        { key: "showCalls", label: "Calls", hint: "A ringing phone on the chip while it rings, and the call card" }
                      ]
                      RowLayout {
                        id: flagItem
                        required property var modelData
                        spacing: Style.space(8)
                        Text {
                          textFormat: Text.PlainText
                          text: flagItem.modelData.label
                          color: root.foreground
                          font.family: root.fontFamily
                          font.pixelSize: Style.font.caption
                          MouseArea {
                            id: flagMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.toggleBarFlagOnPage(flagItem.modelData.key)
                          }
                          PanelToolTip {
                            visible: flagMouse.containsMouse
                            text: flagItem.modelData.hint
                          }
                        }
                        ToggleSwitch {
                          checked: root.profile[flagItem.modelData.key] === true
                          cursorRing: false
                          foreground: root.foreground
                          onToggled: root.toggleBarFlagOnPage(flagItem.modelData.key)
                        }
                      }
                    }
                    Item { Layout.fillWidth: true }
                  }
                }

              }

              // ---- The sections, in the order chosen in settings. They are fixed
              //      items placed by that order, so a new order rebuilds
              //      nothing: the media cards and a half-typed text keep their state ----
              Item {
                id: sectionsBox
                readonly property var items: ({ actions: actionsColumn, media: mediaColumn, notifications: notificationsColumn, photos: photosColumn, received: receivedSection })
                readonly property real gap: Style.space(12)
                function topOf(key) {
                  var y = 0
                  for (var i = 0; i < root.drawnSections.length; i++) {
                    var k = root.drawnSections[i]
                    if (k === key) return y
                    y += items[k].height + gap
                  }
                  return 0
                }
                visible: root.showMain && root.drawnSections.length > 0
                width: parent.width

                // Editing: the sections' order, moved by their grips (Reorder).
                Reorder {
                  id: sectionMove
                  count: root.editing ? root.drawnSections.length : 0
                  gap: sectionsBox.gap
                  motion: root.motion
                  extentOf: function(i) { var k = root.drawnSections[i]; return sectionsBox.items[k] ? sectionsBox.items[k].height : 0 }
                  onMoved: function(a, b) {
                    var key = root.drawnSections[a]
                    root.persistProfile({ sectionOrder: Model.moveShortcut(Model.visibleSections(root.sectionOrder), key, b - a) })
                  }
                }
                height: {
                  var h = 0
                  for (var i = 0; i < root.drawnSections.length; i++) h += items[root.drawnSections[i]].height + (i > 0 ? gap : 0)
                  return h
                }
                implicitHeight: height

                // ---- Shortcuts: up to four per row, in the order chosen in settings.
                //      Folded, a row of icons in the header that still work ----
                Column {
                  id: actionsColumn
                  y: sectionsBox.topOf("actions")
                  transform: ReorderShift { order: sectionMove; index: root.editing ? root.drawnSections.indexOf("actions") : -1 }
                  z: sectionMove.from >= 0 && sectionMove.from === root.drawnSections.indexOf("actions") ? 10 : 0
                  visible: root.showMain && root.drawnSections.indexOf("actions") >= 0
                  width: parent.width
                  spacing: Style.space(8)

                  PanelSeparator { visible: root.separatedAbove("actions"); foreground: root.foreground }

                  EditBar { section: "actions"; item: actionsColumn }

                  RowLayout {
                    visible: !root.editing
                    width: parent.width
                    spacing: Style.space(4)

                    FoldToggle {
                      Layout.fillWidth: true
                      foreground: root.foreground
                      fontFamily: root.fontFamily
                      motion: root.motion
                      animate: root.settled
                      title: "SHORTCUTS"
                      folded: root.isCollapsed("actions")
                      onToggled: root.toggleCollapsed("actions")
                    }

                    Row {
                      visible: root.isCollapsed("actions")
                      Layout.alignment: Qt.AlignVCenter
                      spacing: Style.space(2)

                      Repeater {
                        model: root.actions
                        PanelActionButton {
                          required property var modelData
                          required property int index
                          iconText: modelData.glyph
                          tooltipText: modelData.label
                          size: Style.space(22)
                          foreground: root.foreground
                          fontFamily: root.fontFamily
                          enabled: modelData.enabled === true
                          hasCursor: root.cursorActive && root.focusSection === "actions" && root.actionIndex === index
                          onHovered: function(on) { if (on) { root.cursorActive = true; root.focusSection = "actions"; root.actionIndex = index } }
                          onClicked: root.runAction(modelData.key)
                        }
                      }
                    }
                  }

                  FoldBody {
                    motion: root.motion
                    animate: root.settled
                    open: !root.isCollapsed("actions") && !root.editing

                    Grid {
                      id: actionGrid
                      width: parent.width
                      columns: root.actionColumns
                      spacing: Style.space(8)

                      Repeater {
                        model: root.actions
                        ActionTile {
                          required property var modelData
                          required property int index
                          width: (actionGrid.width - actionGrid.spacing * (root.actionColumns - 1)) / root.actionColumns
                          action: modelData
                          tileIndex: index
                        }
                      }
                    }
                  }

                  // ---- Editing: every shortcut; drag the chosen ones, click to
                  //      add or take one away ----
                  FoldBody {
                    motion: root.motion
                    animate: root.settled
                    open: root.editing

                    Grid {
                      id: editGrid
                      width: parent.width
                      columns: 4
                      spacing: Style.space(8)
                      readonly property real cellWidth: (width - spacing * (columns - 1)) / columns

                      Reorder {
                        id: tileMove
                        columns: editGrid.columns
                        cellWidth: editGrid.cellWidth
                        cellHeight: editGrid.children.length > 1 ? editGrid.children[1].height : 0
                        gap: editGrid.spacing
                        count: root.shortcutOrder.length
                        motion: root.motion
                        onMoved: function(a, b) {
                          root.persistProfile({ shortcuts: Model.moveShortcut(root.shortcutOrder, root.shortcutOrder[a], b - a) })
                        }
                      }

                      Repeater {
                        model: root.editing ? Model.editShortcutTiles(root.shortcutOrder, root.can) : []
                        EditTile {
                          required property var modelData
                          width: editGrid.cellWidth
                          tile: modelData
                          order: tileMove
                          onToggle: function(key) { root.toggleShortcutOnPage(key) }
                        }
                      }
                    }
                  }

                  // ---- Send text: typed text or a link, or a ping carrying it.
                  //      Outside the fold, so the folded icon opens it too ----
                  FoldBody {
                    id: composerBody
                    open: root.composing
                    motion: root.motion
                    animate: root.settled
                    spacing: Style.space(4)

                    RowLayout {
                      width: parent.width
                      spacing: Style.space(6)

                      PanelField {
                        id: composerField
                        Layout.fillWidth: true
                        placeholderText: "Text or a link for " + Model.deviceLabel(root.device)
                        foreground: root.foreground
                        font.family: root.fontFamily
                        onActiveFocusChanged: root.composerFocused = activeFocus
                        // Esc closes it; the text stays for next time.
                        onSteppedOut: root.closeComposer()
                        // Enter is taken here, not in onAccepted: TextInput passes
                        // it on, and the key catcher would run the tile again.
                        Keys.onPressed: function(event) {
                          if (event.key !== Qt.Key_Return && event.key !== Qt.Key_Enter) return
                          event.accepted = true
                          var ping = (event.modifiers & Qt.ControlModifier) !== 0
                          if (!ping || root.can.ping === true) root.sendComposed(ping)
                        }
                      }
                      PanelActionButton {
                        visible: root.can.ping === true
                        iconText: Model.GLYPH.wave
                        tooltipText: "Ping with this message (Ctrl+Enter)"
                        foreground: root.foreground
                        fontFamily: root.fontFamily
                        enabled: composerField.text.trim() !== ""
                        onClicked: root.sendComposed(true)
                      }
                      PanelActionButton {
                        iconText: Model.GLYPH.send
                        tooltipText: (Model.linkFor(composerField.text) !== "" ? "Send the link, to open there" : "Put it on its clipboard") + " (Enter)"
                        foreground: root.foreground
                        fontFamily: root.fontFamily
                        enabled: composerField.text.trim() !== ""
                        onClicked: root.sendComposed(false)
                      }
                    }

                    Text {
                      width: parent.width
                      textFormat: Text.PlainText
                      wrapMode: Text.WordWrap
                      text: Model.composerHint(composerField.text, root.device, root.can.ping === true)
                      color: root.dim
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.caption
                    }
                  }
                }

                // ---- What the phone is playing: the active player's card; the rest
                //      are a carousel away (arrows, dots, sideways swipe, drag, h/l) ----
                Column {
                  id: mediaColumn
                  y: sectionsBox.topOf("media")
                  transform: ReorderShift { order: sectionMove; index: root.editing ? root.drawnSections.indexOf("media") : -1 }
                  z: sectionMove.from >= 0 && sectionMove.from === root.drawnSections.indexOf("media") ? 10 : 0
                  visible: root.showMain && root.drawnSections.indexOf("media") >= 0
                  width: parent.width
                  spacing: Style.space(8)

                  PanelSeparator { visible: root.separatedAbove("media"); foreground: root.foreground }

                  EditBar { section: "media"; item: mediaColumn }

                  RowLayout {
                    visible: !root.editing
                    width: parent.width
                    spacing: Style.space(4)

                    FoldToggle {

                      foreground: root.foreground

                      fontFamily: root.fontFamily

                      motion: root.motion

                      animate: root.settled
                      Layout.fillWidth: true
                      title: "NOW PLAYING"
                      folded: root.isCollapsed("media")
                      summary: root.shownPlayerObject
                        ? Model.mediaSummary(root.shownPlayerObject.trackTitle, root.shownPlayerObject.trackArtist,
                            Model.playerApp(root.shownPlayerObject.identity, root.device ? root.device.name : ""))
                        : ""
                      thumb: root.shownPlayerObject && root.shownPlayerObject.trackArtUrl && root.phone ? root.phone.artFor(root.shownPlayerObject.trackArtUrl) : ""
                      onToggled: root.toggleCollapsed("media")
                    }

                    // Folded, the line keeps a play/pause for the shown player.
                    PanelActionButton {
                      visible: root.isCollapsed("media") && !!root.shownPlayerObject
                      Layout.alignment: Qt.AlignVCenter
                      iconText: root.shownPlayerObject && root.shownPlayerObject.isPlaying ? Model.GLYPH.pause : Model.GLYPH.play
                      tooltipText: root.shownPlayerObject && root.shownPlayerObject.isPlaying ? "Pause" : "Play"
                      size: Style.space(22)
                      foreground: root.foreground
                      fontFamily: root.fontFamily
                      onClicked: if (root.phone) root.phone.mediaAction("PlayPause", root.shownPlayerObject)
                    }

                    Row {
                      visible: root.players.length > 1 && !root.isCollapsed("media")
                      spacing: Style.space(4)
                      Layout.alignment: Qt.AlignVCenter

                      PanelActionButton {
                        anchors.verticalCenter: parent.verticalCenter
                        iconText: Model.GLYPH.left
                        tooltipText: "Previous player"
                        size: Style.space(20)
                        fontSize: Style.font.body
                        foreground: root.foreground
                        fontFamily: root.fontFamily
                        enabled: root.shownPlayer > 0
                        onClicked: root.showPlayer(root.shownPlayer - 1)
                      }

                      Row {
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: Style.space(5)

                        Repeater {
                          model: root.players.length
                          Rectangle {
                            required property int index
                            anchors.verticalCenter: parent.verticalCenter
                            width: index === root.shownPlayer ? Style.space(14) : Style.space(6)
                            height: Style.space(6)
                            radius: height / 2
                            color: index === root.shownPlayer ? root.foreground : root.dim
                            Behavior on width { enabled: root.settled; NumberAnimation { duration: Model.MOTION.inMs * root.motion; easing.type: Easing.OutCubic } }

                            MouseArea {
                              anchors.fill: parent
                              anchors.margins: -Style.space(4)
                              cursorShape: Qt.PointingHandCursor
                              onClicked: root.showPlayer(parent.index)
                            }
                          }
                        }
                      }

                      PanelActionButton {
                        anchors.verticalCenter: parent.verticalCenter
                        iconText: Model.GLYPH.right
                        tooltipText: "Next player"
                        size: Style.space(20)
                        fontSize: Style.font.body
                        foreground: root.foreground
                        fontFamily: root.fontFamily
                        enabled: root.shownPlayer < root.players.length - 1
                        onClicked: root.showPlayer(root.shownPlayer + 1)
                      }
                    }
                  }

                  FoldBody {

                    motion: root.motion

                    animate: root.settled
                    open: !root.isCollapsed("media") && !root.editing
                    spacing: Style.space(8)

                    // One card wide; the strip of all cards slides behind it.
                    Item {
                      id: carouselBox
                      width: parent.width
                      readonly property var shownCard: cardRepeater.count > root.shownPlayer ? cardRepeater.itemAt(root.shownPlayer) : null
                      height: shownCard ? shownCard.implicitHeight : 0
                      clip: true
                      Behavior on height { enabled: root.settled; NumberAnimation { duration: Model.MOTION.inMs * root.motion; easing.type: Easing.OutCubic } }

                      Row {
                        id: cardStrip
                        spacing: Style.space(16)
                        x: -root.shownPlayer * (carouselBox.width + spacing) + root.swipeOffset
                        Behavior on x {
                          enabled: !root.swiping && root.settled
                          NumberAnimation { duration: Model.MOTION.inMs * root.motion; easing.type: Easing.OutCubic }
                        }

                        Repeater {
                          id: cardRepeater
                          model: root.players
                          MediaCard {
                            required property var modelData
                            required property int index
                            width: carouselBox.width
                            player: modelData
                            cardIndex: index
                          }
                        }
                      }

                      // A sideways two-finger swipe (horizontal wheel) pages the
                      // carousel. Vertical wheel is refused so it still scrolls the panel.
                      MouseArea {
                        anchors.fill: parent
                        acceptedButtons: Qt.NoButton
                        // Over the cards: the cursor stays the buttons' own.
                        cursorShape: undefined
                        property real pending: 0
                        onWheel: function(wheel) {
                          var dx = wheel.angleDelta.x
                          if (Math.abs(dx) <= Math.abs(wheel.angleDelta.y) || root.players.length < 2) { wheel.accepted = false; return }
                          wheel.accepted = true
                          if (swipeCooldown.running) return
                          pending += dx
                          if (Math.abs(pending) >= 90) {
                            root.showPlayer(root.shownPlayer + (pending < 0 ? 1 : -1))
                            pending = 0
                            swipeCooldown.restart()
                          }
                        }
                        Timer { id: swipeCooldown; interval: 450 }
                      }
                    }

                    // The phone has one media volume, whichever app is playing.
                    RowLayout {
                      visible: !!root.volumePlayer
                      width: parent.width
                      spacing: Style.space(8)

                      PanelActionButton {
                        iconText: root.shownVolume <= 0.001 ? Model.GLYPH.volumeOff : Model.GLYPH.volume
                        tooltipText: (root.shownVolume <= 0.001 ? "Unmute " : "Mute ") + Model.deviceLabel(root.device)
                        foreground: root.foreground
                        fontFamily: root.fontFamily
                        onClicked: root.toggleMute()
                      }
                      PanelSlider {
                        id: volumeSlider
                        Layout.fillWidth: true
                        bar: root.bar
                        minimum: 0
                        maximum: 1
                        step: 0.05
                        value: root.shownVolume
                        onReleased: function(v) { root.setVolumeWish(v) }
                      }
                      Text {
                        textFormat: Text.PlainText
                        Layout.preferredWidth: Style.space(34)
                        horizontalAlignment: Text.AlignRight
                        text: Math.round((volumeSlider.dragging ? volumeSlider.liveValue : volumeSlider.value) * 100) + "%"
                        color: root.dim
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.caption
                      }
                    }
                  }
                }

                // ---- The phone's notifications ----
                Column {
                  id: notificationsColumn
                  y: sectionsBox.topOf("notifications")
                  transform: ReorderShift { order: sectionMove; index: root.editing ? root.drawnSections.indexOf("notifications") : -1 }
                  z: sectionMove.from >= 0 && sectionMove.from === root.drawnSections.indexOf("notifications") ? 10 : 0
                  visible: root.showMain && root.drawnSections.indexOf("notifications") >= 0
                  width: parent.width
                  spacing: Style.space(8)

                  PanelSeparator { visible: root.separatedAbove("notifications"); foreground: root.foreground }

                  EditBar { section: "notifications"; item: notificationsColumn }

                  FoldToggle {
                    visible: !root.editing

                    foreground: root.foreground

                    fontFamily: root.fontFamily

                    motion: root.motion

                    animate: root.settled
                    width: parent.width
                    title: root.notifications.length > 0 ? "NOTIFICATIONS · " + root.notifications.length : "NOTIFICATIONS"
                    folded: root.isCollapsed("notifications")
                    summary: Model.notificationsSummary(root.notifications)
                    onToggled: root.toggleCollapsed("notifications")
                  }

                  FoldBody {

                    motion: root.motion

                    animate: root.settled
                    open: !root.isCollapsed("notifications") && !root.editing
                    spacing: Style.space(8)

                    Column {
                      id: notifColumn
                      width: parent.width
                      spacing: Style.space(4)

                      Repeater {
                        model: root.notifications
                        NotificationRow {
                          required property var modelData
                          required property int index
                          width: notifColumn.width
                          note: modelData
                          rowIndex: index
                        }
                      }
                    }
                  }
                }

                // ---- Gallery: the newest photos and videos on the device
                //      (click opens; copy, save, drag), and a link per folder
                //      for all of them in the file manager ----
                Column {
                  id: photosColumn
                  y: sectionsBox.topOf("photos")
                  // Folding closed when its last photos went (see shownPhotos).
                  height: root.photosClosing ? 0 : implicitHeight
                  clip: root.photosClosing
                  Behavior on height { enabled: root.photosClosing; NumberAnimation { duration: Model.MOTION.inMs * root.motion; easing.type: Easing.OutCubic } }
                  transform: ReorderShift { order: sectionMove; index: root.editing ? root.drawnSections.indexOf("photos") : -1 }
                  z: sectionMove.from >= 0 && sectionMove.from === root.drawnSections.indexOf("photos") ? 10 : 0
                  visible: root.showMain && root.drawnSections.indexOf("photos") >= 0
                  width: parent.width
                  spacing: Style.space(8)

                  PanelSeparator { visible: root.separatedAbove("photos"); foreground: root.foreground }

                  EditBar { section: "photos"; item: photosColumn }

                  FoldToggle {
                    visible: !root.editing
                    foreground: root.foreground
                    fontFamily: root.fontFamily
                    motion: root.motion
                    animate: root.settled
                    width: parent.width
                    title: "GALLERY"
                    canBusy: true
                    busy: !!root.photoInfo && root.photoInfo.loading === true
                    refreshTip: "Look at the phone again"
                    onRefreshRequested: if (root.phone) root.phone.refreshPhotos(true)
                    folded: root.isCollapsed("photos")
                    summary: Model.photosSummary(root.photos)
                    onToggled: root.toggleCollapsed("photos")
                  }

                  FoldBody {
                    motion: root.motion
                    animate: root.settled
                    open: !root.isCollapsed("photos") && !root.editing
                    spacing: Style.space(8)

                    // Photos need sshfs, or the phone's leave to read its storage.
                    RowLayout {
                      visible: root.photosHint
                      width: parent.width
                      spacing: Style.space(10)
                      Text {
                        Layout.fillWidth: true
                        textFormat: Text.PlainText
                        wrapMode: Text.WordWrap
                        text: root.photoInfo && root.photoInfo.missing === "sshfs"
                          ? "The gallery of " + Model.deviceLabel(root.device) + " needs sshfs on this computer"
                          : "Gallery: allow storage access in KDE Connect on " + Model.deviceLabel(root.device)
                        color: root.dim
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.caption
                      }
                      Button {
                        readonly property bool installing: !!root.phone && root.phone.setupFixing["sshfs"] === true
                        text: root.photoInfo && root.photoInfo.missing === "sshfs" ? (installing ? "Installing…" : "Install") : "Try again"
                        enabled: !installing
                        tooltipText: root.photoInfo && root.photoInfo.missing === "sshfs" ? "Asks for your password" : (root.photoInfo ? root.photoInfo.error || "" : "")
                        bordered: true
                        foreground: root.foreground
                        fontFamily: root.fontFamily
                        fontSize: Style.font.bodySmall
                        onClicked: {
                          if (!root.phone) return
                          if (root.photoInfo && root.photoInfo.missing === "sshfs") root.phone.fixSetup("sshfs")
                          else root.phone.refreshPhotos(true)
                        }
                      }
                    }

                    // The tiles are kept, one per photo (photoModel), so a
                    // photo that goes fades out and the rest glide to their
                    // new places, one that comes fades in: at the panel's
                    // pace, and only once the page has settled.
                    GridView {
                      id: photoGrid
                      visible: root.photos.length > 0
                      opacity: root.photosFading ? 0 : 1
                      Behavior on opacity { NumberAnimation { duration: Model.MOTION.outMs * root.motion; easing.type: Easing.OutCubic } }
                      readonly property int columns: root.photoColumns
                      readonly property real spacing: Style.space(6)
                      readonly property real cell: (parent.width - spacing * (columns - 1)) / columns
                      // A cell is a tile and the gap after it; the last gap
                      // falls outside the section.
                      width: parent.width + spacing
                      height: Math.ceil(count / columns) * cellHeight - spacing
                      cellWidth: cell + spacing
                      cellHeight: cell + spacing
                      interactive: false
                      model: photoModel
                      delegate: Item {
                        required property string json
                        required property int index
                        width: photoGrid.cellWidth
                        height: photoGrid.cellHeight
                        PhotoTile {
                          width: photoGrid.cell
                          height: photoGrid.cell
                          photo: JSON.parse(parent.json)
                          place: parent.index
                        }
                      }
                      add: Transition {
                        enabled: root.settled
                        NumberAnimation { property: "opacity"; from: 0; to: 1; duration: Model.MOTION.inMs * root.motion; easing.type: Easing.OutCubic }
                      }
                      remove: Transition {
                        enabled: root.settled
                        NumberAnimation { property: "opacity"; to: 0; duration: Model.MOTION.outMs * root.motion; easing.type: Easing.OutCubic }
                      }
                      displaced: Transition {
                        enabled: root.settled
                        NumberAnimation { properties: "x,y"; duration: Model.MOTION.inMs * root.motion; easing.type: Easing.OutCubic }
                        NumberAnimation { property: "opacity"; to: 1; duration: Model.MOTION.inMs * root.motion }
                      }
                      move: Transition {
                        enabled: root.settled
                        NumberAnimation { properties: "x,y"; duration: Model.MOTION.inMs * root.motion; easing.type: Easing.OutCubic }
                      }
                    }

                    // Everything else: the biggest albums (Camera,
                    // Screenshots, …), wherever this phone keeps them,
                    // opened in the file manager (the storage KDE Connect
                    // mounted). Only from a fresh look: the cached list may
                    // predate the mount. Wider than the panel, they scroll
                    // sideways (the wheel, a swipe or a drag); while they
                    // fit, they sit at the right.
                    Flickable {
                      id: albumStrip
                      width: parent.width
                      height: albumRow.implicitHeight
                      visible: root.photos.length > 0 && !!root.photoInfo && !!root.photoInfo.albums
                        && root.photoInfo.albums.length > 0 && !root.photoInfo.cached
                      contentWidth: Math.max(width, albumRow.implicitWidth)
                      contentHeight: height
                      flickableDirection: Flickable.HorizontalFlick
                      boundsBehavior: Flickable.StopAtBounds
                      interactive: albumRow.implicitWidth > width
                      clip: true
                      Row {
                        id: albumRow
                        x: Math.max(0, albumStrip.width - implicitWidth)
                        spacing: Style.space(4)
                        Repeater {
                          model: root.photoInfo && root.photoInfo.albums ? root.photoInfo.albums : []
                          Button {
                            required property var modelData
                            text: modelData.name
                            iconText: Model.GLYPH.folderOpen
                            tooltipText: modelData.count + " in " + modelData.name + ": opens the album in your file manager"
                            foreground: root.foreground
                            fontFamily: root.fontFamily
                            fontSize: Style.font.bodySmall
                            onClicked: root.openPhotoFolder(modelData.path)
                          }
                        }
                      }
                      // The wheel moves the row while it has more that way;
                      // at an end, the page scrolls as usual. Over the links:
                      // no button taken, and the cursor stays theirs.
                      MouseArea {
                        parent: albumStrip
                        anchors.fill: parent
                        acceptedButtons: Qt.NoButton
                        cursorShape: undefined
                        onWheel: function(wheel) {
                          var d = wheel.pixelDelta.x !== 0 || wheel.pixelDelta.y !== 0
                            ? (wheel.pixelDelta.x !== 0 ? wheel.pixelDelta.x : wheel.pixelDelta.y)
                            : (wheel.angleDelta.x !== 0 ? wheel.angleDelta.x : wheel.angleDelta.y) / 2
                          var most = Math.max(0, albumStrip.contentWidth - albumStrip.width)
                          var x = Math.max(0, Math.min(most, albumStrip.contentX - d))
                          wheel.accepted = albumStrip.interactive && x !== albumStrip.contentX
                          if (wheel.accepted) albumStrip.contentX = x
                        }
                      }
                      NumberAnimation {
                        id: albumGlide
                        target: albumStrip
                        property: "contentX"
                        duration: Model.MOTION.inMs * root.motion
                        easing.type: Easing.OutCubic
                      }
                      function glideAlbums(dir) {
                        var most = Math.max(0, albumStrip.contentWidth - albumStrip.width)
                        albumGlide.stop()
                        albumGlide.to = Math.max(0, Math.min(most, albumStrip.contentX + dir * albumStrip.width * 0.75))
                        albumGlide.start()
                      }
                      // More to either side: the edge fades and an arrow
                      // shows (it moves the row along), so the row reads as
                      // one that goes on even when a link ends at the edge.
                      Repeater {
                        model: [{ left: true }, { left: false }]
                        Rectangle {
                          id: albumEdge
                          required property var modelData
                          readonly property color panel: root.bar ? root.bar.background : Color.background
                          parent: albumStrip
                          anchors.left: modelData.left ? parent.left : undefined
                          anchors.right: modelData.left ? undefined : parent.right
                          width: Style.space(40)
                          height: parent.height
                          opacity: modelData.left ? (albumStrip.atXBeginning ? 0 : 1) : (albumStrip.atXEnd ? 0 : 1)
                          visible: opacity > 0
                          Behavior on opacity { NumberAnimation { duration: Model.MOTION.inMs * root.motion; easing.type: Easing.OutCubic } }
                          PanelActionButton {
                            anchors.verticalCenter: parent.verticalCenter
                            anchors.left: albumEdge.modelData.left ? parent.left : undefined
                            anchors.right: albumEdge.modelData.left ? undefined : parent.right
                            iconText: albumEdge.modelData.left ? Model.GLYPH.left : Model.GLYPH.right
                            tooltipText: albumEdge.modelData.left ? "Earlier albums" : "More albums"
                            size: Style.space(20)
                            fontSize: Style.font.body
                            foreground: root.foreground
                            fontFamily: root.fontFamily
                            onClicked: albumStrip.glideAlbums(albumEdge.modelData.left ? -1 : 1)
                          }
                          gradient: Gradient {
                            orientation: Gradient.Horizontal
                            GradientStop { position: 0; color: modelData.left ? panel : Qt.rgba(panel.r, panel.g, panel.b, 0) }
                            GradientStop { position: 1; color: modelData.left ? Qt.rgba(panel.r, panel.g, panel.b, 0) : panel }
                          }
                        }
                      }
                    }
                  }
                }

                // ---- Received: the files the device sent (open, show in folder,
                //      forget); gone while there are none ----
                Column {
                  id: receivedSection
                  y: sectionsBox.topOf("received")
                  transform: ReorderShift { order: sectionMove; index: root.editing ? root.drawnSections.indexOf("received") : -1 }
                  z: sectionMove.from >= 0 && sectionMove.from === root.drawnSections.indexOf("received") ? 10 : 0
                  visible: root.showMain && root.drawnSections.indexOf("received") >= 0
                  width: parent.width
                  spacing: Style.space(8)

                  PanelSeparator { visible: root.separatedAbove("received"); foreground: root.foreground }

                  EditBar { section: "received"; item: receivedSection }

                  FoldToggle {
                    visible: !root.editing
                    foreground: root.foreground
                    fontFamily: root.fontFamily
                    motion: root.motion
                    animate: root.settled
                    width: parent.width
                    title: "RECEIVED"
                    folded: root.isCollapsed("received")
                    summary: Model.receivedSummary(root.received)
                    onToggled: root.toggleCollapsed("received")
                  }

                  FoldBody {
                    motion: root.motion
                    animate: root.settled
                    open: !root.isCollapsed("received") && !root.editing
                    spacing: Style.space(2)

                    Column {
                      id: receivedColumn
                      width: parent.width
                      spacing: Style.space(2)
                      Repeater {
                        model: root.received
                        ReceivedRow {
                          required property var modelData
                          required property int index
                          width: receivedColumn.width
                          entry: modelData
                          place: index
                        }
                      }
                    }
                  }
                }
              }

              // ---- Away, not paired, or KDE Connect down ----
              // Away: where it was last seen, and Reconnect, in place (the
              // search runs here and the result lands here). Nothing paired
              // or KDE Connect down: the way to Connection.
              Column {
                id: awayColumn
                visible: root.showMain && !root.reachable
                width: parent.width
                spacing: Style.space(8)
                readonly property bool away: !!root.device && root.device.paired === true && !!root.phone && root.phone.daemon

                Text {
                  textFormat: Text.PlainText
                  width: parent.width
                  wrapMode: Text.WordWrap
                  color: root.foreground
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.body
                  text: {
                    if (!root.phone || !root.snapshot) return "Looking for your devices…"
                    if (!root.phone.daemon) return "KDE Connect is not running."
                    if (!root.device) return "No device is paired yet."
                    return Model.deviceLabel(root.device) + " is away"
                  }
                }

                Repeater {
                  model: awayColumn.away ? root.awayInfo.lines : []
                  Text {
                    required property string modelData
                    textFormat: Text.PlainText
                    width: awayColumn.width
                    wrapMode: Text.WordWrap
                    text: modelData
                    color: root.dim
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.bodySmall
                  }
                }

                Row {
                  spacing: Style.space(8)
                  Button {
                    visible: awayColumn.away
                    text: root.awayInfo.searching ? "Looking…" : "Reconnect"
                    iconText: root.awayInfo.searching ? "\u{F0996}" : Model.GLYPH.refresh
                    iconSpinning: root.awayInfo.searching
                    enabled: !root.awayInfo.searching
                    tooltipText: "Looks for it on the network; connected devices stay connected"
                    bordered: true
                    foreground: root.foreground
                    fontFamily: root.fontFamily
                    fontSize: Style.font.bodySmall
                    onClicked: if (root.phone) root.phone.searchDevices(false)
                  }
                  Button {
                    visible: !!root.snapshot && (!awayColumn.away || root.computerIssues > 0)
                    readonly property bool adding: root.computerIssues === 0 && root.openingScope === "addDevice"
                    text: adding ? "Add a device" : (root.computerIssues > 0 ? "Connection · " + Model.connectionSummary(root.setupChecks, root.ignoredChecks) : "Connection")
                    iconText: Model.GLYPH.chevronRight
                    bordered: true
                    foreground: root.computerIssues > 0 ? root.urgent : root.foreground
                    fontFamily: root.fontFamily
                    fontSize: Style.font.bodySmall
                    onClicked: adding ? root.openAddDevice() : root.openConnection()
                  }
                }

                // Before any device is set up: what the panel will show,
                // with a made-up phone (#62).
                Button {
                  visible: root.canPreview
                  text: "Preview with a demo phone"
                  iconText: Model.GLYPH.phone
                  tooltipText: "What the panel shows once a phone is set up; made-up data, nothing reaches a device"
                  bordered: true
                  foreground: root.foreground
                  fontFamily: root.fontFamily
                  fontSize: Style.font.bodySmall
                  onClicked: root.startPreview()
                }
              }

              // ---- Text messages, in place of everything above but the header ----
              MessagesView {
                id: messagesView
                Binding { target: root.sms; property: "viewing"; value: root.opened && root.messagesOpen; when: !!root.sms }
                visible: root.showMessages
                width: parent.width
                height: visible ? Style.space(600) : 0
                sms: root.sms
                bar: root.bar
                onThreadOpened: function(tid) { root.rememberThread(tid) }
                onReported: function(text) { if (root.phone) root.phone.report(text, false) }
                onUnreadToggled: root.toggleUnreadOnly()
                // A text field here let go of the keyboard (Esc, a click
                // away): the panel's keys take it back, so the next Esc
                // still goes somewhere.
                onComposerFocusedChanged: {
                  if (composerFocused || !root.messagesOpen) return
                  Qt.callLater(function() { if (root.messagesOpen && !messagesView.composerFocused) keyCatcher.forceActiveFocus() })
                }
                foreground: root.foreground
                urgent: root.urgent
                fontFamily: root.fontFamily
              }

              // ---- Settings, in place of everything above but the header ----
              SettingsView {
                id: settingsView
                visible: root.showSettings
                width: parent.width
                rows: root.settingsRows
                cursorIndex: root.cursorActive ? root.settingsIndex : -1
                cursorGlide: root.cursorGlide
                // The groups show what the page edits: a device's own
                // profile on its page, else the defaults.
                shortcutsShown: root.editedProfile.showShortcuts
                collapsed: root.collapsed
                flags: ({ showShortcuts: root.editedProfile.showShortcuts, showMedia: root.editedProfile.showMedia, showNotifications: root.editedProfile.showNotifications, showPhotos: root.editedProfile.showPhotos, showReceived: root.editedProfile.showReceived })
                order: root.editedProfile.shortcuts
                sectionOrder: root.editedProfile.sectionOrder
                barIndicators: root.editedProfile.barIndicators
                batteryLowOnly: root.editedProfile.batteryLowOnly
                scopeKind: root.screenId !== "" ? "screen" : root.editingDevice ? "device" : (["defaults", "connection", "addDevice"].indexOf(root.settingsScope) >= 0 ? root.settingsScope : "root")
                screenSetup: root.screenSetup
                screenQr: root.screenPairing ? root.screenPairing.qr : null
                custom: root.editingDevice ? root.editedProfile.custom : ({})
                iconPicking: root.iconPicking
                unpairArmed: !!root.scopeDevice && root.unpairArmed === String(root.scopeDevice.id)
                deviceName: root.scopeDevice ? Model.deviceLabel(root.scopeDevice) : ""
                phone: root.phone
                panelBackground: root.bar ? root.bar.background : Color.background
                onRejectRequested: function(id) { root.cancelPairing(id) }
                pairingNotes: root.pairingNotes
                pairingSince: root.pairingSince
                pairClock: root.pairClock
                onDeviceMoveRequested: function(id, delta) { root.moveDevice(id, delta) }
                onNicknameSet: function(text) {
                  var t = String(text || "").replace(/\s+/g, " ").trim()
                  root.setIdentity({ nickname: t === "" ? null : t })
                  keyCatcher.forceActiveFocus()
                }
                onIconSet: function(code) { root.setIdentity({ icon: code === "" ? null : code }); root.iconPicking = false }
                onBarPlaceSet: function(place) { root.setIdentity({ bar: place }) }
                onNicknameFocus: function(focused) {
                  root.nicknameFocused = focused
                  if (!focused) Qt.callLater(function() { keyCatcher.forceActiveFocus() })
                }
                motion: root.motion
                animate: root.settled
                onFoldToggled: function(key) { root.toggleCollapsed(key) }
                setupFixing: root.phone ? root.phone.setupFixing : ({})
                network: root.phone ? root.phone.setupNetwork : ""
                appPlatform: root.appPlatform
                onAppPlatformSet: function(p) { root.setAppPlatform(p) }
                justPaired: root.justPaired
                onFixRequested: function(what) { root.fixRequested(what) }
                onIgnoreRequested: function(key, on) { root.ignoreCheck(key, on) }
                canPreview: root.canPreview
                onPreviewRequested: root.startPreview()
                foreground: root.foreground
                fontFamily: root.fontFamily
                onActivated: function(index) { root.activateSetting(index) }
                onMoveRequested: function(key, delta) { root.moveShortcutKey(key, delta) }
                onSectionMoveRequested: function(section, delta) { root.moveSectionKey(section, delta) }
                onBarMoveRequested: function(key, delta) { root.moveBarIndicator(key, delta) }
                onHovered: function(index) { root.cursorActive = true; root.settingsIndex = index }
              }

            }
            // The old page held still while the demo turns live (backToSetup).
            Image {
              id: pageStill
              visible: false
              width: pageHost.width
              height: sourceSize.height / pageHost.dpr
              asynchronous: false
              cache: false
            }
          }
        }
      }
    }
  }

  // Editing: a section as one bar, its grip, its name and what it holds
  // now (or when it would show), and its switch. Dimmed while switched off.
  component EditBar: FoldBody {
    id: editBar
    property string section: ""
    property Item item: null
    readonly property int place: root.drawnSections.indexOf(section)
    readonly property string flag: root.sectionFlag(section)
    readonly property bool on: flag !== "" && root.profile[flag] === true
    readonly property string title: section === "actions" ? "SHORTCUTS" : (section === "media" ? "NOW PLAYING" : (section === "photos" ? "GALLERY" : (section === "received" ? "RECEIVED" : "NOTIFICATIONS")))
    readonly property string now: section === "actions" ? Model.shortcutsSummary(root.shortcutOrder)
      : section === "media" ? (root.shownPlayerObject ? Model.mediaSummary(root.shownPlayerObject.trackTitle, root.shownPlayerObject.trackArtist, "") : "")
      : section === "photos" ? (root.photos.length > 0 ? Model.photosSummary(root.photos) : "")
      : section === "received" ? (root.received.length > 0 ? Model.receivedSummary(root.received) : "")
      : (root.notifications.length > 0 ? Model.notificationsSummary(root.notifications) : "")
    open: root.editing
    motion: root.motion
    animate: root.settled

    CursorSurface {
      width: parent.width
      implicitHeight: barRow.implicitHeight + Style.space(12)
      hasCursor: false
      CursorStop { here: root.cursorActive && root.focusSection === editBar.section; glide: root.cursorGlide }
      foreground: root.foreground
      // Solid while it moves, so what it passes over never shows through.
      color: sectionMove.from >= 0 && sectionMove.from === editBar.place ? Qt.tint(root.bar ? root.bar.background : Color.background, fill)
        : (hasCursor ? fill : "transparent")

      MouseArea {
        anchors.fill: parent
        hoverEnabled: true
        onEntered: { root.cursorActive = true; root.focusSection = editBar.section }
        onClicked: root.toggleSectionShown(editBar.section)
      }

      RowLayout {
        id: barRow
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        anchors.leftMargin: Style.space(8)
        anchors.rightMargin: Style.space(8)
        spacing: Style.space(10)

        ReorderGrip {
          order: sectionMove
          index: editBar.place
          item: editBar.item
          foreground: root.foreground
          fontFamily: root.fontFamily
        }
        ColumnLayout {
          Layout.fillWidth: true
          spacing: Style.space(1)
          opacity: editBar.on ? 1 : 0.5
          Text {
            textFormat: Text.PlainText
            Layout.fillWidth: true
            text: editBar.title
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            font.bold: true
            elide: Text.ElideRight
          }
          Text {
            textFormat: Text.PlainText
            Layout.fillWidth: true
            text: !editBar.on ? "Hidden" : (editBar.now !== "" ? editBar.now.replace(/\s+/g, " ") : (Model.SECTION_EMPTY[editBar.section] || ""))
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            elide: Text.ElideRight
          }
        }
        ToggleSwitch {
          Layout.alignment: Qt.AlignVCenter
          checked: editBar.on
          cursorRing: false
          foreground: root.foreground
          onToggled: root.toggleSectionShown(editBar.section)
        }
      }
    }
  }

  // Editing: a tile (a shortcut, a bar indicator). A chosen one (a − on its
  // corner) drags to another place and a click takes it away; the others
  // (dimmed, a +) are added with a click.
  component EditTile: BorderSurface {
    id: editTile
    property var tile: ({})
    // The order its chosen tiles move in (a Reorder), and what a click does.
    property var order: null
    signal toggle(string key)
    readonly property bool moving: !!order && order.from >= 0 && tile.chosen === true && order.from === tile.pos
    implicitHeight: editColumn.implicitHeight + Style.space(18)
    radius: Style.cornerRadius
    borderSpec: Border.controlSpec(tileMouse.containsMouse || moving ? "hover-cursor" : "normal", root.foreground, Color.accent)
    color: moving ? Qt.tint(root.bar ? root.bar.background : Color.background, Style.hoverFillFor(root.foreground, Color.accent))
      : (tileMouse.containsMouse ? Style.hoverFillFor(root.foreground, Color.accent) : "transparent")
    opacity: tile.chosen === true ? 1 : 0.45
    transform: ReorderShift { order: editTile.order; index: editTile.tile.chosen === true ? editTile.tile.pos : -1 }
    z: moving ? 10 : 0

    Column {
      id: editColumn
      anchors.centerIn: parent
      spacing: Style.space(4)
      Text {
        anchors.horizontalCenter: parent.horizontalCenter
        text: editTile.tile.glyph || ""
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.heading + 2
      }
      Text {
        textFormat: Text.PlainText
        anchors.horizontalCenter: parent.horizontalCenter
        width: Math.min(implicitWidth, editTile.width - Style.space(8))
        elide: Text.ElideRight
        text: editTile.tile.label || ""
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
      }
    }
    Text {
      anchors.top: parent.top
      anchors.right: parent.right
      anchors.margins: Style.space(3)
      text: editTile.tile.chosen === true ? Model.GLYPH.remove : Model.GLYPH.add
      color: editTile.tile.chosen === true ? root.foreground : Color.accent
      font.family: root.fontFamily
      font.pixelSize: Style.font.body
    }

    MouseArea {
      id: tileMouse
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: editTile.tile.chosen === true ? (pressed ? Qt.ClosedHandCursor : Qt.OpenHandCursor) : Qt.PointingHandCursor
      onClicked: editTile.toggle(editTile.tile.key)
    }
    DragHandler {
      target: null
      enabled: editTile.tile.chosen === true
      grabPermissions: PointerHandler.CanTakeOverFromAnything
      onActiveChanged: {
        if (active) editTile.order.begin(editTile.tile.pos, editTile.width)
        else if (editTile.order.from === editTile.tile.pos) editTile.order.release()
      }
      onTranslationChanged: if (active) editTile.order.dragBy(translation.x, translation.y)
    }
  }

  // A failing check on this computer: a dot on the gear, until it is fixed
  // or ignored (Connection).
  component GearDot: Rectangle {
    anchors.right: parent.right
    anchors.top: parent.top
    anchors.margins: Style.space(3)
    width: Math.max(5, Math.round(Style.font.caption * 0.55))
    height: width
    radius: width / 2
    color: root.urgent
  }

  // Editing the bar: an indicator as the bar shows it, with a small caption.
  // A chosen one drags to another place (barMove) and a click takes it away;
  // the others (dimmed) are added with a click.
  component BarTile: Rectangle {
    id: barTile
    property var tile: ({})
    readonly property bool moving: barMove.from >= 0 && tile.chosen === true && barMove.from === tile.pos
    implicitHeight: tileColumn.implicitHeight + Style.space(6)
    radius: Style.cornerRadius
    color: moving ? Qt.tint(root.bar ? root.bar.background : Color.background, Style.hoverFillFor(root.foreground, Color.accent))
      : (barTileMouse.containsMouse ? Style.hoverFillFor(root.foreground, Color.accent) : "transparent")
    opacity: tile.chosen === true ? 1 : 0.4
    transform: ReorderShift { order: barMove; index: barTile.tile.chosen === true ? barTile.tile.pos : -1 }
    z: moving ? 10 : 0

    Column {
      id: tileColumn
      anchors.horizontalCenter: parent.horizontalCenter
      anchors.top: parent.top
      anchors.topMargin: Style.space(3)
      spacing: Style.space(2)
      Item {
        anchors.horizontalCenter: parent.horizontalCenter
        width: Math.max(sampleText.implicitWidth, bubbleDot.width)
        height: sampleText.implicitHeight
        Text {
          id: sampleText
          anchors.centerIn: parent
          visible: barTile.tile.key !== "bubble"
          text: barTile.tile.sample || ""
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.body + 2
        }
        // The bubble is a count on the device glyph: drawn as the bar does.
        Rectangle {
          id: bubbleDot
          visible: barTile.tile.key === "bubble"
          anchors.centerIn: parent
          height: Math.round(sampleText.implicitHeight * 0.62)
          width: height
          radius: height / 2
          color: Color.urgent
          Text {
            anchors.centerIn: parent
            text: barTile.tile.sample || ""
            color: "white"
            font.family: root.fontFamily
            font.pixelSize: Math.max(6, parent.height * 0.72)
            font.bold: true
          }
        }
      }
      Text {
        anchors.horizontalCenter: parent.horizontalCenter
        width: Math.min(implicitWidth, barTile.width - Style.space(2))
        elide: Text.ElideRight
        textFormat: Text.PlainText
        text: barTile.tile.label || ""
        color: root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption - 1
      }
    }

    MouseArea {
      id: barTileMouse
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: barTile.tile.chosen === true ? (pressed ? Qt.ClosedHandCursor : Qt.OpenHandCursor) : Qt.PointingHandCursor
      onClicked: root.toggleBarOnPage(barTile.tile.key)
    }
    PanelToolTip {
      visible: barTileMouse.containsMouse && barMove.from < 0
      text: (barTile.tile.hint || "") + (barTile.tile.chosen === true ? " · click to take away, drag to move" : " · click to add")
    }
    DragHandler {
      target: null
      enabled: barTile.tile.chosen === true
      grabPermissions: PointerHandler.CanTakeOverFromAnything
      onActiveChanged: {
        if (active) barMove.begin(barTile.tile.pos, barTile.width)
        else if (barMove.from === barTile.tile.pos) barMove.release()
      }
      onTranslationChanged: if (active) barMove.dragBy(translation.x, translation.y)
    }
  }

  // Files: one of the device's newest photos, square. A click opens it, the
  // corner button copies it, a drag drops the file into a window. In demo,
  // a part of the one demo picture (`clip`), so four look like four.
  component PhotoTile: CursorSurface {
    id: tile
    property var photo: ({})
    property int place: 0
    readonly property string url: "file://" + encodeURI(String(photo.path || ""))
    hasCursor: false
    CursorStop { here: root.cursorActive && root.focusSection === "photos" && root.photoIndex === place; glide: root.cursorGlide }
    foreground: root.foreground
    radius: Style.cornerRadius
    clip: true

    Item {
      anchors.fill: parent
      anchors.margins: Style.space(2)
      clip: true
      Image {
        readonly property var c: tile.photo.clip || [0, 0, 1, 1]
        width: parent.width / c[2]
        height: parent.height / c[3]
        x: -c[0] * width
        y: -c[1] * height
        source: tile.photo.thumb ? "file://" + encodeURI(tile.photo.thumb) : ""
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        smooth: true
        sourceSize.width: 512
      }
      // Without a thumbnail (or the demo picture): the kind of picture.
      Text {
        anchors.centerIn: parent
        visible: !tile.photo.thumb
        text: tile.photo.video ? Model.GLYPH.video : Model.GLYPH.picture
        color: root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.heading
      }
    }
    // Opening: the file comes over first (a local copy), with a ring.
    readonly property bool opening: !!root.phone && root.phone.isBusy("open:" + String(photo.path || ""))
    Rectangle {
      anchors.centerIn: parent
      visible: tileOpenRing.visible
      opacity: tileOpenRing.opacity
      width: Style.font.heading * 1.6
      height: width
      radius: width / 2
      color: Qt.rgba(0, 0, 0, 0.55)
    }
    WaitRing {
      id: tileOpenRing
      anchors.centerIn: parent
      running: tile.opening
      motion: root.motion
      color: "white"
      size: Style.font.heading
    }
    // A video: a play mark in the corner, as galleries draw it.
    Rectangle {
      visible: tile.photo.video === true
      anchors.left: parent.left
      anchors.bottom: parent.bottom
      anchors.margins: Style.space(6)
      width: Style.font.heading
      height: width
      radius: width / 2
      color: Qt.rgba(0, 0, 0, 0.55)
      Text {
        anchors.centerIn: parent
        text: Model.GLYPH.play
        color: "white"
        font.family: root.fontFamily
        font.pixelSize: Style.font.bodySmall
      }
    }
    // The file itself, for a drop into another window.
    Drag.active: tileDrag.active
    Drag.dragType: Drag.Automatic
    Drag.supportedActions: Qt.CopyAction
    Drag.mimeData: ({ "text/uri-list": tile.url })
    DragHandler { id: tileDrag; target: null; enabled: !tile.photo.demo }
    // Hover without taking it from the buttons: ↗ shows only on this tile.
    HoverHandler { id: tileHover }

    MouseArea {
      id: tileMouse
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onEntered: { root.cursorActive = true; root.focusSection = "photos"; root.photoIndex = tile.place }
      onClicked: root.openPhoto(tile.photo)
    }
    // Save and copy read the file over the network: each turns into the
    // ring while it works, and stays while it does, pointer on the tile or not.
    readonly property bool saving: !!root.phone && root.phone.isBusy("save:" + String(photo.path || ""))
    readonly property bool copying: !!root.phone && root.phone.isBusy("copy:" + String(photo.path || ""))
    WaitButton {
      id: saveTile
      anchors.top: parent.top
      anchors.right: copyTile.left
      visible: tileHover.hovered || tile.saving
      glyph: Model.GLYPH.download
      waiting: tile.saving
      motion: root.motion
      tooltipText: "Save a copy in Pictures"
      foreground: "white"
      fontFamily: root.fontFamily
      onClicked: if (root.phone && !tile.saving) root.phone.savePhoto(tile.photo.path)
    }
    WaitButton {
      id: copyTile
      anchors.top: parent.top
      anchors.right: parent.right
      visible: tileHover.hovered || tile.copying
      glyph: Model.GLYPH.clipboard
      waiting: tile.copying
      motion: root.motion
      tooltipText: tile.photo.video ? "Copy the file" : "Copy the image"
      foreground: "white"
      fontFamily: root.fontFamily
      onClicked: if (root.phone && !tile.copying) root.phone.copyFile(tile.photo.path)
    }
    PanelToolTip {
      visible: tileMouse.containsMouse
      text: (tile.photo.album || "Photo") + (tile.photo.video ? " · video" : "") + " · " + Model.threadTime(tile.photo.at, Date.now())
        + (tile.photo.video ? " · click to play" : " · click to open") + ", drag into a window"
    }
  }

  // Received: a file the device sent. A click (or Enter) opens it in its
  // app, as Omarchy opens files (uwsm-app); the folder button shows it
  // selected in Files; × forgets it here (the file stays).
  component ReceivedRow: CursorSurface {
    id: rrow
    property var entry: ({})
    property int place: 0
    hasCursor: false
    CursorStop { here: root.cursorActive && root.focusSection === "received" && root.receivedIndex === place; glide: root.cursorGlide }
    foreground: root.foreground
    implicitHeight: rrowContent.implicitHeight + Style.space(10)

    MouseArea {
      id: rrowMouse
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onEntered: { root.cursorActive = true; root.focusSection = "received"; root.receivedIndex = rrow.place }
      onClicked: root.openReceived(rrow.entry)
    }
    PanelToolTip {
      visible: rrowMouse.containsMouse
      text: "Open in its app"
    }
    RowLayout {
      id: rrowContent
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      anchors.leftMargin: Style.space(8)
      anchors.rightMargin: Style.space(4)
      spacing: Style.space(10)
      Item {
        Layout.preferredWidth: Style.space(28)
        Layout.preferredHeight: Style.space(28)
        Image {
          anchors.fill: parent
          visible: status === Image.Ready
          // The bridge's safe copy (decoded in the sandbox), never the file.
          source: rrow.entry.preview ? "file://" + encodeURI(rrow.entry.preview) : ""
          fillMode: Image.PreserveAspectCrop
          asynchronous: true
          sourceSize.width: 64
        }
        Text {
          anchors.centerIn: parent
          visible: parent.children[0].status !== Image.Ready
          text: Model.isImage(rrow.entry.name) ? Model.GLYPH.picture : Model.GLYPH.document
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.heading
        }
      }
      ColumnLayout {
        Layout.fillWidth: true
        spacing: Style.space(1)
        Text {
          Layout.fillWidth: true
          textFormat: Text.PlainText
          text: rrow.entry.name || ""
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
          elide: Text.ElideMiddle
        }
        Text {
          Layout.fillWidth: true
          textFormat: Text.PlainText
          text: Model.sizeText(rrow.entry.size) + " · " + Model.threadTime(rrow.entry.at, Date.now())
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
        }
      }
      PanelActionButton {
        iconText: Model.GLYPH.folderOpen
        tooltipText: "Show in Files"
        foreground: root.foreground
        fontFamily: root.fontFamily
        onClicked: root.showReceivedFolder(rrow.entry)
      }
      PanelActionButton {
        iconText: Model.GLYPH.close
        tooltipText: "Forget it here (the file stays)"
        foreground: root.foreground
        fontFamily: root.fontFamily
        onClicked: if (root.phone) root.phone.dismissReceived(rrow.entry)
      }
    }
  }

  component MediaCard: CursorSurface {
    id: card
    property var player: null
    property int cardIndex: 0
    // What the phone reports, and what the card shows. A seek makes the phone
    // report "paused" for a moment while it buffers; showing that flipped the
    // play/pause button and back. So a pause from the phone shows only once it
    // has lasted 1.5 s. A press here flips the button at once instead.
    readonly property bool reportedPlaying: !!(player && player.isPlaying)
    property bool playing: reportedPlaying

    onReportedPlayingChanged: {
      if (reportedPlaying) { playing = true; pauseGrace.stop() }
      else if (!playing) pauseGrace.stop()
      else pauseGrace.restart()
    }
    Timer {
      id: pauseGrace
      interval: 1500
      onTriggered: card.playing = card.reportedPlaying
    }

    function togglePlaying() {
      if (!player || !player.canTogglePlaying) return
      playing = !playing
      settle.restart()
      if (root.phone) root.phone.mediaAction("PlayPause", player)
    }
    // If the phone has not followed the press within 3 s, show what it reports.
    Timer {
      id: settle
      interval: 3000
      onTriggered: card.playing = card.reportedPlaying
    }

    // Artwork holds through a blank: if the phone re-sends track info the URL
    // can drop out for a moment, and the image would vanish and come back.
    // A real change of art (or a track with none) still lands, 2 s later.
    readonly property string reportedArt: player && player.trackArtUrl ? String(player.trackArtUrl) : ""
    property string artUrl: reportedArt
    onArtUrlChanged: if (root.phone) root.phone.requestArt(artUrl)
    onReportedArtChanged: {
      if (reportedArt !== "") { artUrl = reportedArt; artClear.stop() }
      else artClear.restart()
    }
    Timer {
      id: artClear
      interval: 2000
      onTriggered: card.artUrl = card.reportedArt
    }

    readonly property real length: player && player.lengthSupported ? player.length : 0
    readonly property real position: player && player.positionSupported ? player.position : 0
    readonly property bool seekable: !!(player && player.canSeek && player.positionSupported && length > 0)
    readonly property string app: player ? Model.playerApp(player.identity, root.device ? root.device.name : "") : ""
    readonly property string artist: player ? String(player.trackArtist || "").trim() : ""
    readonly property string title: player ? String(player.trackTitle || "").trim() : ""

    // The progress row rides out short pauses: a seek makes the phone report
    // "paused" while it buffers, and hiding the row on that made the card
    // collapse and come back. It goes only after a few seconds really paused.
    property bool showProgress: playing
    onPlayingChanged: {
      if (playing) { showProgress = true; progressGrace.stop() }
      else progressGrace.restart()
    }
    Timer {
      id: progressGrace
      interval: 4000
      onTriggered: card.showProgress = card.playing
    }

    hasCursor: false
    CursorStop { here: root.cursorActive && root.focusSection === "media"; glide: root.cursorGlide }
    foreground: root.foreground
    implicitHeight: cardContent.implicitHeight + Style.space(14)
    Component.onCompleted: {
      root.cardsBuilt += 1
      if (root.phone) root.phone.requestArt(artUrl)
    }

    // Drag the card sideways to page the carousel, as on the phone. Buttons
    // and the seek bar sit above this and keep their own presses.
    MouseArea {
      id: swipeArea
      anchors.fill: parent
      hoverEnabled: true
      preventStealing: true
      enabled: true
      property real startX: 0
      property real dx: 0
      cursorShape: root.players.length > 1 ? (pressed ? Qt.ClosedHandCursor : Qt.OpenHandCursor) : Qt.ArrowCursor
      onEntered: { root.cursorActive = true; root.focusSection = "media" }
      onPressed: function(mouse) { startX = mapToItem(null, mouse.x, 0).x; dx = 0 }
      onPositionChanged: function(mouse) {
        if (!pressed || root.players.length < 2) return
        dx = mapToItem(null, mouse.x, 0).x - startX
        if (Math.abs(dx) > 4) root.dragCarousel(dx)
      }
      onReleased: root.endCarouselDrag(root.players.length < 2 ? 0 : dx)
      onCanceled: root.endCarouselDrag(0)
    }

    ColumnLayout {
      id: cardContent
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      anchors.leftMargin: Style.space(8)
      anchors.rightMargin: Style.space(8)
      spacing: Style.space(4)

      RowLayout {
        Layout.fillWidth: true
        spacing: Style.space(10)

        Item {
          Layout.preferredWidth: Style.space(44)
          Layout.preferredHeight: Style.space(44)

          Image {
            id: cardArt
            anchors.fill: parent
            // retainWhileLoading keeps the old picture up until the new one is
            // ready, so a reload never shows a gap.
            visible: source != "" && status !== Image.Error && status !== Image.Null
            // The phone's art, as a safe copy (decoded in the sandbox).
            source: root.phone ? root.phone.artFor(card.artUrl) : ""
            retainWhileLoading: true
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
            sourceSize.width: 88
            sourceSize.height: 88
            opacity: card.playing ? 1.0 : 0.6
          }
          Text {
            anchors.centerIn: parent
            visible: !cardArt.visible
            text: Model.GLYPH.music
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.display
          }
        }

        ColumnLayout {
          Layout.fillWidth: true
          spacing: Style.space(2)

          Text {
            textFormat: Text.PlainText
            Layout.fillWidth: true
            text: card.title || card.app
            color: root.foreground
            opacity: card.playing ? 1.0 : 0.75
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
            font.bold: true
            elide: Text.ElideRight
          }
          Text {
            textFormat: Text.PlainText
            Layout.fillWidth: true
            text: card.artist && card.artist !== card.title ? card.app + " · " + card.artist : card.app
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            elide: Text.ElideRight
          }
        }

        Row {
          spacing: Style.space(2)
          Layout.alignment: Qt.AlignVCenter

          Repeater {
            model: 3
            WaitButton {
              required property int index
              // Play/pause flips at once (card.playing); a skip waits for the track.
              readonly property bool skipping: index !== 1 && !!root.phone && !!card.player
                && root.phone.isBusy(root.phone.skipKey(card.player, root.mediaKey(index)))
              waiting: skipping
              motion: root.motion
              glyph: index === 0 ? Model.GLYPH.previous
                : (index === 2 ? Model.GLYPH.next
                : (card.playing ? Model.GLYPH.pause : Model.GLYPH.play))
              fontSize: index === 1 ? Style.font.heading : Style.font.icon
              size: Style.space(28)
              foreground: root.foreground
              fontFamily: root.fontFamily
              enabled: !!card.player && !skipping && (index === 0 ? card.player.canGoPrevious
                : (index === 2 ? card.player.canGoNext : card.player.canTogglePlaying))
              // Enter plays/pauses, so the keyboard cursor sits on that button.
              hasCursor: index === 1 && root.cursorActive && root.focusSection === "media"
              onHovered: function(on) { if (on) { root.cursorActive = true; root.focusSection = "media" } }
              onClicked: {
                if (index === 1) card.togglePlaying()
                else if (root.phone) root.phone.mediaAction(root.mediaKey(index), card.player)
              }
            }
          }
        }
      }

      // Progress: elapsed, a seek bar, total. Drag or click to jump.
      //
      // Only while playing: KDE Connect reports one position shared by all of
      // the phone's players (a paused YouTube "advanced" in step with a
      // playing podcast), so a paused card's position would be made up.
      RowLayout {
        Layout.fillWidth: true
        visible: card.length > 0 && card.showProgress
        spacing: Style.space(8)

        Text {
          textFormat: Text.PlainText
          Layout.preferredWidth: Style.space(38)
          text: Model.formatTime(seekBar.dragging ? seekBar.liveValue : card.position)
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
        }
        PanelSlider {
          id: seekBar
          Layout.fillWidth: true
          bar: root.bar
          minimum: 0
          maximum: Math.max(1, card.length)
          step: 1
          value: Math.min(card.position, card.length)
          enabled: card.seekable
          onReleased: function(v) { if (root.phone) root.phone.seek(card.player, v) }
        }
        Text {
          textFormat: Text.PlainText
          Layout.preferredWidth: Style.space(38)
          horizontalAlignment: Text.AlignRight
          text: Model.formatTime(card.length)
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
        }
      }
    }
  }

  component ActionTile: CursorSurface {
    id: tile
    property var action: ({})
    property int tileIndex: 0
    readonly property bool working: root.phone ? root.phone.isBusy(action.key) : false

    hasCursor: false
    CursorStop { here: root.cursorActive && root.focusSection === "actions" && root.actionIndex === tileIndex; glide: root.cursorGlide }
    foreground: root.foreground
    bordered: true
    opacity: action.enabled ? 1.0 : 0.4
    implicitHeight: tileColumn.implicitHeight + Style.space(18)

    Column {
      id: tileColumn
      anchors.centerIn: parent
      spacing: Style.space(4)

      Item {
        anchors.horizontalCenter: parent.horizontalCenter
        width: tileGlyph.implicitWidth
        height: tileGlyph.implicitHeight
        Text {
          id: tileGlyph
          anchors.centerIn: parent
          text: tile.action.glyph || ""
          color: root.foreground
          opacity: tile.working ? 0 : 1.0
          font.family: root.fontFamily
          font.pixelSize: Style.font.heading + 2
          Behavior on opacity { NumberAnimation { duration: Model.MOTION.outMs * root.motion; easing.type: Easing.OutCubic } }
        }
        WaitRing {
          anchors.centerIn: parent
          running: tile.working
          motion: root.motion
          color: root.foreground
          size: Math.round(Style.font.heading * 0.8)
        }
      }
      Text {
        textFormat: Text.PlainText
        anchors.horizontalCenter: parent.horizontalCenter
        text: tile.action.label || ""
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
      }
    }

    MouseArea {
      id: tileMouse
      anchors.fill: parent
      hoverEnabled: true
      enabled: tile.action.enabled === true
      cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
      onEntered: { root.cursorActive = true; root.focusSection = "actions"; root.actionIndex = tile.tileIndex }
      onClicked: root.runAction(tile.action.key)
    }

    PanelToolTip {
      visible: tileMouse.containsMouse && (tile.action.hint || "") !== ""
      text: tile.action.hint || ""
      fontFamily: root.fontFamily
    }
  }

  component NotificationRow: CursorSurface {
    id: row
    property var note: ({})
    property int rowIndex: 0
    readonly property bool replying: root.replyingTo !== "" && root.replyingTo === note.id
    readonly property string body: Model.notificationBody(note)
    readonly property bool expanded: root.expandedNotes[note.id] === true
    readonly property bool isText: root.isTextNotification(note)
    // A chat (WhatsApp, Signal...): its messages by sender, as plain text.
    readonly property var groups: Model.conversationGroups(note)
    readonly property bool isChat: groups.length > 0
    property bool chatTruncated: false
    readonly property var latest: Model.latestMessage(note)
    readonly property var titleParts: Model.chatTitle(note)
    readonly property bool canExpand: isChat ? (groups.length > 1 || chatTruncated || expanded
      || (!!latest && latest.text !== groups[groups.length - 1].text))
      : (bodyText.truncated || (expanded && bodyText.lineCount > 3))

    hasCursor: false
    CursorStop { here: root.cursorActive && root.focusSection === "notifications" && root.notifIndex === rowIndex; glide: root.cursorGlide }
    foreground: root.foreground
    implicitHeight: rowContent.implicitHeight + Style.space(14)

    onReplyingChanged: if (replying) Qt.callLater(function() { replyField.forceActiveFocus() })

    MouseArea {
      anchors.fill: parent
      hoverEnabled: true
      acceptedButtons: row.isText ? Qt.LeftButton : Qt.NoButton
      cursorShape: row.isText ? Qt.PointingHandCursor : Qt.ArrowCursor
      onEntered: { root.cursorActive = true; root.focusSection = "notifications"; root.notifIndex = row.rowIndex }
      onClicked: if (row.isText) root.openNotificationConversation(row.note)
    }

    RowLayout {
      id: rowContent
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.top: parent.top
      anchors.topMargin: Style.space(7)
      anchors.leftMargin: Style.space(10)
      anchors.rightMargin: Style.space(6)
      spacing: Style.space(10)

      Item {
        Layout.alignment: Qt.AlignTop
        Layout.topMargin: Style.space(2)
        Layout.preferredWidth: Style.space(22)
        Layout.preferredHeight: Style.space(22)

        Image {
          id: appIcon
          anchors.fill: parent
          visible: status === Image.Ready
          source: row.note.icon ? "file://" + row.note.icon : ""
          fillMode: Image.PreserveAspectFit
          asynchronous: true
          sourceSize.width: 44
          sourceSize.height: 44
        }
        Text {
          anchors.centerIn: parent
          visible: !appIcon.visible
          text: Model.GLYPH.bell
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.icon
        }
      }

      ColumnLayout {
        Layout.fillWidth: true
        Layout.alignment: Qt.AlignTop
        spacing: Style.space(2)

        Text {
          textFormat: Text.PlainText
          Layout.fillWidth: true
          visible: text !== ""
          text: String(row.note.app || "").toUpperCase()
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          font.bold: true
          font.letterSpacing: 1.0
          elide: Text.ElideRight
        }
        // The title; a group chat's unread count sits beside it, dimmed,
        // and stays in view while a long name shortens. The title may use
        // the whole row but the count's room, so it is cut only when it does
        // not fit; the count follows the text as drawn (contentWidth), since
        // a measured width can fall short of a drawn emoji.
        Item {
          Layout.fillWidth: true
          implicitHeight: noteTitle.implicitHeight
          Text {
            id: noteTitle
            width: parent.width - (chatCount.visible ? chatCount.implicitWidth + Style.space(6) : 0)
            textFormat: Text.PlainText
            text: row.titleParts.title
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
            font.bold: true
            elide: Text.ElideRight
          }
          Text {
            id: chatCount
            visible: text !== ""
            x: Math.min(noteTitle.contentWidth, noteTitle.width) + Style.space(6)
            y: noteTitle.baselineOffset - baselineOffset
            textFormat: Text.PlainText
            text: row.titleParts.count
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
          }
        }
        // Three lines, and the whole message on a click (or e).
        Text {
          id: bodyText
          textFormat: Text.PlainText
          Layout.fillWidth: true
          visible: row.body !== "" && !row.isChat
          text: row.body
          color: root.foreground
          opacity: 0.8
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
          wrapMode: Text.Wrap
          maximumLineCount: row.expanded ? 500 : 3
          elide: Text.ElideRight

          MouseArea {
            anchors.fill: parent
            enabled: bodyText.truncated || (row.expanded && bodyText.lineCount > 3)
            cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
            onClicked: root.toggleExpanded(row.note)
          }
        }
        // A chat: like the phone, folded it is the latest message and who
        // sent it; all of it on a click (or e). Names are bold by font, never by markup: nothing the phone
        // sends is interpreted.
        ColumnLayout {
          Layout.fillWidth: true
          visible: row.isChat
          spacing: Style.space(4)
          Repeater {
            model: row.expanded ? row.groups : (row.latest ? [row.latest] : [])
            ColumnLayout {
              id: chatGroup
              required property var modelData
              required property int index
              Layout.fillWidth: true
              spacing: 0
              Text {
                Layout.fillWidth: true
                visible: text !== ""
                textFormat: Text.PlainText
                text: chatGroup.modelData.sender
                color: root.foreground
                opacity: 0.9
                font.family: root.fontFamily
                font.pixelSize: Style.font.bodySmall
                font.bold: true
                elide: Text.ElideRight
              }
              Text {
                Layout.fillWidth: true
                textFormat: Text.PlainText
                text: chatGroup.modelData.text
                color: root.foreground
                opacity: 0.8
                font.family: root.fontFamily
                font.pixelSize: Style.font.bodySmall
                wrapMode: Text.Wrap
                maximumLineCount: row.expanded ? 500 : 3
                elide: Text.ElideRight
                onTruncatedChanged: if (!row.expanded) row.chatTruncated = truncated
                Component.onCompleted: if (!row.expanded) row.chatTruncated = truncated

                MouseArea {
                  anchors.fill: parent
                  enabled: row.canExpand
                  cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                  onClicked: root.toggleExpanded(row.note)
                }
              }
            }
          }
        }
        Text {
          // Only when there is more to show or hide.
          visible: row.canExpand
          textFormat: Text.PlainText
          text: row.expanded ? "Show less" : "Show all"
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          font.underline: moreMouse.containsMouse
          MouseArea {
            id: moreMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: root.toggleExpanded(row.note)
          }
        }

        Flow {
          Layout.fillWidth: true
          Layout.topMargin: Style.space(4)
          visible: (row.note.actions || []).length > 0 && !row.replying
          spacing: Style.space(6)

          Repeater {
            model: row.note.actions || []
            Item {
              id: noteAction
              required property var modelData
              readonly property bool working: !!root.phone && root.phone.isBusy("action:" + row.note.id + ":" + String(modelData))
              implicitWidth: noteActionButton.implicitWidth
              implicitHeight: noteActionButton.implicitHeight
              Button {
                id: noteActionButton
                anchors.fill: parent
                text: String(noteAction.modelData)
                foreground: root.foreground
                fontFamily: root.fontFamily
                fontSize: Style.font.caption
                bordered: true
                verticalPadding: Style.space(2)
                horizontalPadding: Style.space(8)
                opacity: noteAction.working ? 0 : 1.0
                enabled: !noteAction.working
                Behavior on opacity { NumberAnimation { duration: Model.MOTION.outMs * root.motion; easing.type: Easing.OutCubic } }
                onClicked: {
                  root.phone.notificationAction(row.note, String(noteAction.modelData))
                  root.markNotificationSeen(row.note)
                }
              }
              WaitRing {
                anchors.centerIn: parent
                running: noteAction.working
                motion: root.motion
                color: root.foreground
                size: Math.round(Style.font.bodySmall * 0.8)
              }
            }
          }
        }

        RowLayout {
          Layout.fillWidth: true
          Layout.topMargin: Style.space(4)
          visible: row.replying
          spacing: Style.space(6)

          PanelField {
            id: replyField
            Layout.fillWidth: true
            placeholderText: "Reply to " + Model.notificationTitle(row.note)
            foreground: root.foreground
            font.family: root.fontFamily
            onActiveFocusChanged: root.replyFocused = activeFocus
            // Esc closes the reply; what was written stays (it threw it away).
            onSteppedOut: root.closeReply()
            onAccepted: {
              if (text.trim() === "") return
              root.phone.reply(row.note, text)
              root.markNotificationSeen(row.note)
              text = ""
              root.closeReply()
            }
            // Enter is taken here: TextInput passes it on after onAccepted,
            // and the key catcher would open this reply again.
            Keys.onPressed: function(event) {
              if (event.key !== Qt.Key_Return && event.key !== Qt.Key_Enter) return
              event.accepted = true
              accepted()
            }
          }
          PanelActionButton {
            iconText: Model.GLYPH.send
            tooltipText: "Send reply"
            foreground: root.foreground
            fontFamily: root.fontFamily
            enabled: replyField.text.trim() !== ""
            onClicked: replyField.accepted()
          }
        }
      }

      Row {
        Layout.alignment: Qt.AlignTop
        spacing: Style.space(2)

        PanelActionButton {
          visible: row.isText
          iconText: Model.GLYPH.messages
          tooltipText: "Open the conversation (o)"
          foreground: root.foreground
          fontFamily: root.fontFamily
          onClicked: root.openNotificationConversation(row.note)
        }
        // While a sent reply is on its way, its button is the ring.
        WaitButton {
          readonly property bool sending: !!root.phone && root.phone.isBusy("reply:" + row.note.id)
          visible: !!row.note.replyId
          glyph: Model.GLYPH.reply
          waiting: sending
          motion: root.motion
          tooltipText: sending ? "Sending the reply" : "Reply"
          foreground: root.foreground
          fontFamily: root.fontFamily
          enabled: !sending
          onClicked: row.replying ? root.closeReply() : root.openReply(row.note)
        }
        // The X turns into the ring until the phone has let it go.
        WaitButton {
          readonly property bool dismissing: !!root.phone && root.phone.isBusy("dismiss:" + row.note.id)
          visible: row.note.dismissable === true
          glyph: Model.GLYPH.close
          waiting: dismissing
          motion: root.motion
          tooltipText: dismissing ? "Dismissing on " + Model.deviceLabel(root.device) : "Dismiss on " + Model.deviceLabel(root.device)
          foreground: root.foreground
          hoverColor: root.urgent
          fontFamily: root.fontFamily
          enabled: !!root.phone && !dismissing
          onClicked: root.phone.dismiss(row.note)
        }
      }
    }
  }
}
