import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
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
  readonly property bool showDevices: Model.layoutFlag(setting("showDevices", true))
  // The viewed device's profile (Service.profile): its sections, their
  // order and its shortcuts, its own changes over the defaults.
  readonly property var profile: phone ? phone.profile : Model.resolveProfile(Model.readSettings(settings), null, true)
  readonly property bool showShortcuts: profile.showShortcuts
  readonly property bool showMedia: profile.showMedia
  readonly property bool showNotifications: profile.showNotifications
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
  readonly property string targetPage: messagesOpen ? "messages" : (settingsOpen ? "settings" : "main")
  readonly property string shownPage: showMessages ? "messages" : (showSettings ? "settings" : "main")
  // +1 moves forward (the new page comes in from the right), -1 goes back.
  property int pageDirection: 1
  // Stretches every transition; 1 normally. The `slowMotion` IPC sets it, so
  // a transition can be caught mid-way in a screenshot.
  property real motion: 1

  function applyShownPage() {
    showSettings = settingsOpen
    showMessages = messagesOpen
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
    if (targetPage === shownPage && !pageSwap.running) return
    // Closed, or just opening: nothing to show off, the panel fades in anyway.
    if (!opened) { snapPage(); return }
    pageDirection = targetPage === "main" ? -1 : 1
    pageSwap.restart()
  }

  // The card (the panel's box) follows the page's size with an animation.
  // KeyboardPanel is a full-screen layer surface and the card an item inside
  // it, so this costs no window resize. Snapping it at the swap was the jump
  // seen mid-transition on the way to and from messages (the width) and back
  // from settings (the height). Only page changes animate it: a fold already
  // animates the height itself, and a second animation on top would lag.
  readonly property real targetCardWidth: panel.fittedContentWidth(showMessages ? Style.space(880) : Style.space(400))
  // No cap of our own: KeyboardPanel already clamps to what fits on screen.
  readonly property real targetCardHeight: panel.fittedContentHeight(column.implicitHeight)
  property real cardWidth: targetCardWidth
  property real cardHeight: targetCardHeight
  Behavior on cardWidth {
    enabled: pageSwap.running || deviceSwap.running
    NumberAnimation { duration: Model.MOTION.inMs * root.motion; easing.type: Easing.OutCubic }
  }
  Behavior on cardHeight {
    enabled: pageSwap.running || deviceSwap.running
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
    onStopped: if (root.shownPage !== root.targetPage) { root.pageDirection = root.targetPage === "main" ? -1 : 1; pageSwap.restart() }
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
  readonly property bool wantsSetup: opened && ((showMain && !reachable) || showSettings)
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
  }

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
  readonly property var settingsRows: Model.settingsRows(
    { showDevices: showDevices, showShortcuts: showShortcuts, showMedia: showMedia, showNotifications: showNotifications },
    shortcutOrder, device ? device.can : null, sectionOrder, barIndicators, batteryLowOnly)

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

  // Every device KDE Connect knows, for the Devices section.
  readonly property var deviceRows: Model.deviceRows(snapshot, device ? device.id : "")
  // Whether the Devices section has anything to offer (a choice or a request).
  readonly property bool devicesWanted: Model.showDevicesSection(deviceRows)
  property int deviceIndex: 0
  // The device whose Unpair is armed (x once, then x again; or two clicks).
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
    phone.view(pendingDevice)
    pendingDevice = ""
    browsedName = ""
    replyingTo = ""
    replyFocused = false
    composing = false
    composerFocused = false
    notifIndex = 0
    deviceIndexCursor = 0
  }
  property int deviceIndexCursor: 0
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

  // Enter on a device row: the one thing it is waiting for.
  function deviceMainAction(row) {
    if (!row || !phone) return
    if (row.incoming) phone.acceptPairing(row.id)
    else if (!row.paired && !row.outgoing) phone.pairWith(row.id)
    else if (row.paired && !row.current) selectDevice(row.id)
  }

  readonly property var actions: Model.shortcutTiles(shortcutOrder, can)
  readonly property int actionColumns: Math.max(1, Math.min(4, actions.length))

  // The sections drawn under the header, in the chosen order: switched on
  // in Layout and with something in them. Devices shows while the device is
  // away too (another one may be there to switch to).
  readonly property var drawnSections: {
    var s = []
    for (var i = 0; i < sectionOrder.length; i++) {
      var key = sectionOrder[i]
      if (key === "devices") { if (showDevices && devicesWanted) s.push(key) }
      else if (!reachable) continue
      else if (key === "actions" && showShortcuts && actions.length > 0) s.push(key)
      else if (key === "media" && showMedia && players.length > 0) s.push(key)
      else if (key === "notifications" && showNotifications && notifications.length > 0) s.push(key)
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
    values[key] = !Model.layoutFlag(setting(key, true))
    persistSettings(values)
  }

  function toggleShortcutKey(key) { persistSettings({ shortcuts: Model.toggleShortcut(shortcutOrder, key) }) }

  function moveShortcutKey(key, delta) {
    persistSettings({ shortcuts: Model.moveShortcut(shortcutOrder, key, delta) })
    // Keep the cursor on the row that moved.
    Qt.callLater(function() {
      for (var i = 0; i < settingsRows.length; i++)
        if (settingsRows[i].kind === "shortcut" && settingsRows[i].key === key) { settingsIndex = i; return }
    })
  }

  function moveSectionKey(section, delta) {
    persistSettings({ sectionOrder: Model.moveShortcut(sectionOrder, section, delta) })
    // Keep the cursor on the row that moved.
    Qt.callLater(function() {
      for (var i = 0; i < settingsRows.length; i++)
        if (settingsRows[i].kind === "layout" && settingsRows[i].section === section) { settingsIndex = i; return }
    })
  }

  function moveBarIndicator(key, delta) {
    persistSettings({ barIndicators: Model.moveShortcut(barIndicators, key, delta) })
    // Keep the cursor on the row that moved.
    Qt.callLater(function() {
      for (var i = 0; i < settingsRows.length; i++)
        if (settingsRows[i].kind === "bar" && settingsRows[i].key === key) { settingsIndex = i; return }
    })
  }

  function resetShortcuts() { persistSettings({ shortcuts: Model.DEFAULT_SHORTCUTS.slice() }) }

  // A settings row under a folded section is not there to land on.
  function settingsRowShown(i) {
    var row = settingsRows[i]
    if (!row) return false
    if (row.kind === "layout") return !isCollapsed("layout")
    if (row.kind === "shortcut") return !isCollapsed("shortcuts")
    if (row.kind === "bar" || row.kind === "barFlag") return !isCollapsed("bar")
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
    else if (row.kind === "bar") persistSettings({ barIndicators: Model.toggleBarIndicator(barIndicators, row.key) })
    else if (row.kind === "barFlag") persistSettings({ batteryLowOnly: !batteryLowOnly })
    else if (row.kind === "reset") resetShortcuts()
    else if (row.kind === "kdeconnect" && phone) { phone.openKdeConnect(); root.close() }
  }

  function openMessagesView(threadId, typeHere) {
    // A tablet without a SIM (or a computer) has no text messages.
    if (device && can.sms !== true) {
      if (phone) phone.report(Model.deviceLabel(device) + " has no text messages", false)
      return
    }
    replyingTo = ""
    replyFocused = false
    composing = false
    composerFocused = false
    settingsOpen = false
    messagesOpen = true
    if (sms) {
      sms.start()
      if (threadId !== undefined && threadId >= 0) sms.openThread(threadId)
      // Demo conversations are made up: the real last conversation is not
      // among them.
      else if (device && !(phone && phone.demo) && lastThreads[device.id] !== undefined && sms.openThreadId < 0) {
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
    messagesOpen = false
    replyingTo = ""
    replyFocused = false
    composing = false
    composerFocused = false
    settingsOpen = true
    settingsIndex = 0
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
  }

  function moveCursor(dx, dy) {
    ensureCursor()
    var s = sections
    if (s.length === 0) return
    if (dx !== 0) {
      if (focusSection === "actions") actionIndex = Math.max(0, Math.min(actions.length - 1, actionIndex + dx))
      else if (focusSection === "media") showPlayer(shownPlayer + dx)
      return
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
    if (focusSection === "devices" && !isCollapsed("devices")) {
      var nd = deviceIndex + dy
      if (nd >= 0 && nd < deviceRows.length) { deviceIndex = nd; return }
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
    if (focusSection === "devices") deviceIndex = dy > 0 ? 0 : deviceRows.length - 1
    scrollToCursor()
  }

  function activateCursor() {
    ensureCursor()
    // A folded section opens on Enter; its content is not there to act on.
    if ((focusSection === "devices" || focusSection === "media" || focusSection === "notifications") && isCollapsed(focusSection)) {
      toggleCollapsed(focusSection)
      return
    }
    if (focusSection === "devices") { deviceMainAction(deviceRows[deviceIndex]); return }
    if (focusSection === "actions") {
      var a = actions[actionIndex]
      if (a && a.enabled) runAction(a.key)
    } else if (focusSection === "media") {
      var shownCard = cardRepeater.itemAt(shownPlayer)
      if (shownCard) shownCard.togglePlaying()
    } else if (focusSection === "notifications") {
      openReply(notifications[notifIndex])
    }
  }

  function scrollToCursor() {
    if (focusSection !== "notifications" || !notifColumn) return
    var item = notifColumn.children[notifIndex]
    if (!item || !panelFlick) return
    Qt.callLater(function() {
      var y = item.mapToItem(panelFlick.contentItem, 0, 0).y
      var margin = Style.space(6)
      var maxY = Math.max(0, panelFlick.contentHeight - panelFlick.height)
      if (y < panelFlick.contentY + margin) panelFlick.contentY = Math.max(0, y - margin)
      else if (y + item.height > panelFlick.contentY + panelFlick.height - margin)
        panelFlick.contentY = Math.min(maxY, y + item.height + margin - panelFlick.height)
    })
  }

  // Middle click on the bar pill: straight to messages.
  function openMessagesFromHotkey() {
    openFromHotkey()
    openMessagesView(-1)
    snapPage()
  }

  function onOpened() {
    // The device asked for (a chip, IPC), else the first connected one.
    if (phone) phone.viewOnOpen()
    deviceSwap.stop()
    pendingDevice = ""
    // Positions are kept current while closed (Service), but re-read now too,
    // so the seek bar is already where it belongs when the panel shows.
    if (phone) phone.refreshPositions()
    cursorActive = false
    browsedName = ""
    settingsOpen = false
    messagesOpen = false
    snapPage()
    replyingTo = ""
    replyFocused = false
    composing = false
    composerFocused = false
    if (panelFlick) panelFlick.contentY = 0
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
      else if (name === "messages") root.openMessagesView(-1)
      else { root.settingsOpen = false; root.messagesOpen = false }
      return root.targetPage
    }
    function slowMotion(factor: real): string { root.motion = factor > 0 ? factor : 1; if (messagesView) messagesView.motion = root.motion; return String(root.motion) }
    function unreadOnly(): string { root.toggleUnreadOnly(); return JSON.stringify({ on: root.unreadOnly, shown: root.sms ? root.sms.shownThreads.count : 0 }) }
    function forgetLastThread(): string { root.persistSettings({ lastThread: {} }); return "ok" }
    // Sample failing checks, to look at the fix buttons (replaced by the next
    // real check within 10 s).
    function demoSetup(): string {
      if (!root.phone) return "no service"
      root.phone.setupChecks = [
        { key: "installed", ok: true, label: "KDE Connect installed", detail: "", fix: "", fixLabel: "" },
        { key: "running", ok: false, label: "KDE Connect running", detail: "It starts at login; it is not running now", fix: "start", fixLabel: "Start" },
        { key: "firewall", ok: false, label: "Firewall lets devices in", detail: "Ports 1714:1764 are closed; allow them from 192.168.1.0/24", fix: "firewall", fixLabel: "Allow" },
        { key: "paired", ok: false, label: "A device is paired", detail: "Open KDE Connect on the phone or tablet and pair it with this computer", fix: "", fixLabel: "" }
      ]
      return "ok"
    }
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
    function tabs(): string {
      var list = root.phone ? root.phone.ordered : []
      return JSON.stringify({ shown: root.manyDevices, viewed: root.device ? root.device.id : "",
        tabs: root.tabDevices.map(function(d) { return d.id }),
        pill: root.phone ? root.phone.pill.chips.map(function(c) { return { id: c.id, text: c.text, bubble: c.bubble, dimmed: c.dimmed } }) : [],
        resting: root.phone ? root.phone.pill.resting : null, pairing: root.phone ? root.phone.pill.pairing : false })
    }
    function devices(): string { return JSON.stringify({ shown: root.drawnSections.indexOf("devices") >= 0, rows: root.deviceRows.map(function(r) { return r.name + ":" + r.status.split(" ·")[0] }) }) }
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
        contacts: s.contactCount, error: s.lastError, composerFocused: messagesView ? messagesView.composerFocused : false })
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
    function demo(kind: string): string { if (root.phone) root.phone.showDemo(kind); return "demo " + kind }
    function openReply(index: int): string {
      var n = root.notifications[index]
      if (!n || !n.replyId) return "no replyable notification at " + index
      root.cursorActive = true; root.focusSection = "notifications"; root.notifIndex = index
      root.openReply(n)
      return "ok"
    }
    function live(): string { if (root.phone) root.phone.showLive(); return "live" }
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
      if (key === "batteryLowOnly") root.persistSettings({ batteryLowOnly: !root.batteryLowOnly })
      else root.persistSettings({ barIndicators: Model.toggleBarIndicator(root.barIndicators, key) })
      return JSON.stringify({ indicators: root.barIndicators, lowOnly: root.batteryLowOnly })
    }
    function moveBar(key: string, delta: int): string { root.moveBarIndicator(key, delta); return JSON.stringify(root.barIndicators) }
    function resetShortcuts(): string { root.resetShortcuts(); return "ok" }
    // What the panel is showing, so a check can assert on the picture.
    function status(): string {
      return JSON.stringify({
        opened: root.opened,
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
        layout: { showShortcuts: root.showShortcuts, showMedia: root.showMedia, showNotifications: root.showNotifications },
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
      blocked: root.replyFocused || root.composerFocused || (root.messagesOpen && !!messagesView && messagesView.composerFocused)

      onMoveRequested: function(dx, dy) {
        if (root.messagesOpen) { if (dy !== 0) messagesView.moveCursor(dy); return }
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
        if (root.mainView && root.cursorActive && root.focusSection === "devices" && !root.isCollapsed("devices")) {
          var dr = root.deviceRows[root.deviceIndex]
          if (dr && (dr.incoming || dr.outgoing)) root.phone.rejectPairing(dr.id)
          else root.armOrUnpair(dr)
          return
        }
        if (root.mainView && root.cursorActive && root.focusSection === "notifications") {
          var n = root.notifications[root.notifIndex]
          if (n && n.dismissable) root.phone.dismiss(n)
        }
      }
      onCloseRequested: root.messagesOpen ? root.closeMessagesView() : (root.settingsOpen ? root.closeSettings() : root.close())
      onTabRequested: function(direction) { root.switchPanel(direction) }
      // PgUp/PgDn scroll the open conversation. Keys has no page-key handlers
      // and a second Keys.onPressed here would replace the catcher's own, so
      // these are window shortcuts, live only while messages are open.
      Shortcut {
        sequences: ["PgUp"]
        enabled: root.opened && root.messagesOpen
        onActivated: if (messagesView) messagesView.scrollMessages(1)
      }
      Shortcut {
        sequences: ["PgDown"]
        enabled: root.opened && root.messagesOpen
        onActivated: if (messagesView) messagesView.scrollMessages(-1)
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
          if (root.cursorActive && row && row.kind === "shortcut" && row.on && (t === "K" || t === "J"))
            root.moveShortcutKey(row.key, t === "K" ? -1 : 1)
          else if (root.cursorActive && row && row.kind === "layout" && (t === "K" || t === "J"))
            root.moveSectionKey(row.section, t === "K" ? -1 : 1)
          else if (root.cursorActive && row && row.kind === "bar" && row.on && (t === "K" || t === "J"))
            root.moveBarIndicator(row.key, t === "K" ? -1 : 1)
          return
        }
        if (t === "s") { root.openSettings(); return }
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

      // ---- The pairing card: a device asking to pair floats over the top
      //      of the page until it is answered; it never pushes the page ----
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

        z: 11
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        anchors.topMargin: showing ? 0 : -Style.space(10)
        width: parent.width
        // Covers the whole header (tabs and all), so nothing peeks from under it.
        height: Math.max(pairRow.implicitHeight + Style.space(20),
                         (tabStrip.visible ? tabStrip.height + Style.space(12) : 0) + hero.height)
        radius: Style.cornerRadius
        color: root.bar ? root.bar.background : Color.background
        borderSpec: Border.controlSpec("focus", root.foreground, Color.accent)
        opacity: showing ? 1 : 0
        visible: opacity > 0.01

        Behavior on opacity { NumberAnimation { duration: (pairCard.showing ? Model.MOTION.inMs : Model.MOTION.outMs) * root.motion; easing.type: Easing.OutCubic } }
        Behavior on anchors.topMargin { NumberAnimation { duration: Model.MOTION.inMs * root.motion; easing.type: Easing.OutCubic } }

        // Clicks on the card stay on the card.
        MouseArea { anchors.fill: parent }

        RowLayout {
          id: pairRow
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          anchors.leftMargin: Style.space(12)
          anchors.rightMargin: Style.space(10)
          spacing: Style.space(10)

          Text {
            textFormat: Text.PlainText
            text: Model.deviceGlyph(pairCard.shown)
            color: Color.accent
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
              text: "WANTS TO PAIR"
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
            }
            Text {
              width: parent.width
              textFormat: Text.PlainText
              elide: Text.ElideRight
              text: pairCard.shown ? Model.deviceLabel(pairCard.shown) : ""
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
              // Compare it with the one the device shows.
              text: pairCard.shown && pairCard.shown.verificationKey ? "Key " + pairCard.shown.verificationKey : ""
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
            }
          }
          Button {
            text: "Accept"
            bordered: true
            enabled: !pairCard.waiting
            foreground: root.foreground
            fontFamily: root.fontFamily
            fontSize: Style.font.bodySmall
            onClicked: if (root.phone && pairCard.shown) root.phone.acceptPairing(pairCard.shown.id)
          }
          Button {
            text: "Reject"
            enabled: !pairCard.waiting
            foreground: root.foreground
            fontFamily: root.fontFamily
            fontSize: Style.font.bodySmall
            onClicked: if (root.phone && pairCard.shown) root.phone.rejectPairing(pairCard.shown.id)
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
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

        Column {
          id: column
          // Laid out at the card's final width while the card itself is still
          // animating, so the page never re-flows during a page change.
          width: panelFlick.width + (root.targetCardWidth - root.cardWidth)
          spacing: Style.space(12)

          // ---- Tabs: one per device, only with two or more. Main page and
          //      messages; settings has its own device list ----
          Flickable {
            id: tabStrip
            visible: root.manyDevices && !root.showSettings
            width: parent.width
            height: visible ? tabRow.implicitHeight : 0
            contentWidth: tabRow.implicitWidth
            contentHeight: tabRow.implicitHeight
            clip: true
            interactive: contentWidth > width
            boundsBehavior: Flickable.StopAtBounds
            flickableDirection: Flickable.HorizontalFlick

            Row {
              id: tabRow
              spacing: Style.space(4)
              Repeater {
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
                  tooltipText: textless ? Model.deviceLabel(modelData) + " has no text messages"
                    : Model.deviceLabel(modelData) + " · " + (modelData.reachable === true ? Model.metaLine(root.snapshot, modelData, root.lowPercent) : "Away")
                  onClicked: root.switchDevice(modelData.id)
                  onCurrentChanged: if (current) tabStrip.showTab(tab)
                }
              }
            }

            // Keeps the selected tab in view when the row scrolls.
            function showTab(item) {
              if (!item) return
              if (item.x < contentX) contentX = item.x
              else if (item.x + item.width > contentX + width) contentX = item.x + item.width - width
            }
          }

          PanelHero {
            id: hero
            width: parent.width
            // Nickname, then the full name when they differ.
            title: {
              if (!root.device) return "Devices"
              var nick = root.profile.nickname
              return nick && nick !== root.device.name ? nick + " · " + root.device.name : String(root.device.name || "")
            }
            meta: root.showSettings ? "Settings"
              : (root.showMessages ? (root.sms && root.sms.ready ? "Messages · " + root.sms.threads.count + " conversations" : "Messages")
              : Model.metaLine(root.snapshot, root.device, root.lowPercent))
            foreground: root.foreground
            fontFamily: root.fontFamily
            iconOpacity: root.reachable ? 1.0 : 0.45
            iconComponent: Component {
              Text {
                textFormat: Text.PlainText
                text: Model.deviceIcon(root.device, root.profile)
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.display
              }
            }
            trailingControl: Component {
              PanelActionButton {
                iconText: root.showMain ? Model.GLYPH.settings : Model.GLYPH.back
                tooltipText: root.showMain ? "Settings" : "Back"
                foreground: root.foreground
                fontFamily: root.fontFamily
                onClicked: root.messagesOpen ? root.closeMessagesView() : (root.settingsOpen ? root.closeSettings() : root.openSettings())
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
            width: parent.width
            height: pageColumn.implicitHeight
            implicitHeight: pageColumn.implicitHeight

            Column {
              id: pageColumn
              x: pageHost.slide
              width: parent.width
              spacing: Style.space(12)
              // ---- The sections, in the order chosen in settings. They are fixed
              //      items placed by that order, so a new order rebuilds
              //      nothing: the media cards and a half-typed text keep their state ----
              Item {
                id: sectionsBox
                readonly property var items: ({ devices: devicesColumn, actions: actionsColumn, media: mediaColumn, notifications: notificationsColumn })
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
                height: {
                  var h = 0
                  for (var i = 0; i < root.drawnSections.length; i++) h += items[root.drawnSections[i]].height + (i > 0 ? gap : 0)
                  return h
                }
                implicitHeight: height

                // ---- Devices: only when there is a choice or a decision ----
                Column {
                  id: devicesColumn
                  y: sectionsBox.topOf("devices")
                  visible: root.showMain && root.drawnSections.indexOf("devices") >= 0
                  width: parent.width
                  spacing: Style.space(6)

                  PanelSeparator { visible: root.separatedAbove("devices"); foreground: root.foreground }

                  FoldToggle {

                    foreground: root.foreground

                    fontFamily: root.fontFamily

                    motion: root.motion

                    animate: root.settled
                    width: parent.width
                    title: "DEVICES · " + root.deviceRows.length
                    folded: root.isCollapsed("devices")
                    summary: Model.devicesSummary(root.deviceRows)
                    onToggled: root.toggleCollapsed("devices")
                  }

                  FoldBody {

                    motion: root.motion

                    animate: root.settled
                    id: deviceColumn
                    open: !root.isCollapsed("devices")
                    spacing: Style.space(4)

                    Repeater {
                      model: root.deviceRows
                      DeviceRow {
                        required property var modelData
                        required property int index
                        width: deviceColumn.width
                        row: modelData
                        rowIndex: index
                      }
                    }
                  }
                }

                // ---- Shortcuts: up to four per row, in the order chosen in settings.
                //      Folded, a row of icons in the header that still work ----
                Column {
                  id: actionsColumn
                  y: sectionsBox.topOf("actions")
                  visible: root.showMain && root.drawnSections.indexOf("actions") >= 0
                  width: parent.width
                  spacing: Style.space(8)

                  PanelSeparator { visible: root.separatedAbove("actions"); foreground: root.foreground }

                  RowLayout {
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
                    open: !root.isCollapsed("actions")

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

                      TextField {
                        id: composerField
                        Layout.fillWidth: true
                        placeholderText: "Text or a link for " + Model.deviceLabel(root.device)
                        foreground: root.foreground
                        font.family: root.fontFamily
                        onActiveFocusChanged: root.composerFocused = activeFocus
                        Keys.onEscapePressed: root.closeComposer()
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
                  visible: root.showMain && root.drawnSections.indexOf("media") >= 0
                  width: parent.width
                  spacing: Style.space(8)

                  PanelSeparator { visible: root.separatedAbove("media"); foreground: root.foreground }

                  RowLayout {
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
                      thumb: root.shownPlayerObject && root.shownPlayerObject.trackArtUrl ? root.shownPlayerObject.trackArtUrl : ""
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
                    open: !root.isCollapsed("media")
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
                  visible: root.showMain && root.drawnSections.indexOf("notifications") >= 0
                  width: parent.width
                  spacing: Style.space(8)

                  PanelSeparator { visible: root.separatedAbove("notifications"); foreground: root.foreground }

                  FoldToggle {

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
                    open: !root.isCollapsed("notifications")
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
              }

              // ---- Away, not paired, or KDE Connect down ----
              Column {
                id: awayColumn
                visible: root.showMain && !root.reachable
                width: parent.width
                spacing: Style.space(10)

                Text {
                  textFormat: Text.PlainText
                  width: parent.width
                  wrapMode: Text.WordWrap
                  color: root.dim
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.body
                  text: {
                    if (!root.phone || !root.snapshot) return "Looking for your devices…"
                    if (!root.phone.daemon) return "Start it to reach your devices. It normally starts by itself when you log in."
                    if (!root.device) return "No device is paired yet. Open KDE Connect on your phone or tablet and pair it with this computer."
                    return root.device.name + " is away. It reconnects by itself when it is on the same network with the KDE Connect app running."
                  }
                }

                // What stands in the way, with a fix for what can be fixed here.
                SetupChecks {
                  visible: !!root.snapshot
                  width: parent.width
                  checks: root.phone ? root.phone.setupChecks : []
                  busyFixes: root.phone ? root.phone.setupFixing : ({})
                  showPhoneSteps: !root.device
                  foreground: root.foreground
                  urgent: root.urgent
                  fontFamily: root.fontFamily
                  onFixRequested: function(what) { if (root.phone) root.phone.fixSetup(what) }
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
                onUnreadToggled: root.toggleUnreadOnly()
                foreground: root.foreground
                urgent: root.urgent
                fontFamily: root.fontFamily
              }

              // ---- Settings, in place of everything above but the header ----
              SettingsView {
                visible: root.showSettings
                width: parent.width
                rows: root.settingsRows
                cursorIndex: root.cursorActive ? root.settingsIndex : -1
                shortcutsShown: root.showShortcuts
                collapsed: root.collapsed
                flags: ({ showDevices: root.showDevices, showShortcuts: root.showShortcuts, showMedia: root.showMedia, showNotifications: root.showNotifications })
                order: root.shortcutOrder
                sectionOrder: root.sectionOrder
                barIndicators: root.barIndicators
                batteryLowOnly: root.batteryLowOnly
                motion: root.motion
                animate: root.settled
                onFoldToggled: function(key) { root.toggleCollapsed(key) }
                setupChecks: root.phone ? root.phone.setupChecks : []
                setupFixing: root.phone ? root.phone.setupFixing : ({})
                onFixRequested: function(what) { if (root.phone) root.phone.fixSetup(what) }
                foreground: root.foreground
                fontFamily: root.fontFamily
                onActivated: function(index) { root.activateSetting(index) }
                onMoveRequested: function(key, delta) { root.moveShortcutKey(key, delta) }
                onSectionMoveRequested: function(section, delta) { root.moveSectionKey(section, delta) }
                onBarMoveRequested: function(key, delta) { root.moveBarIndicator(key, delta) }
                onHovered: function(index) { root.cursorActive = true; root.settingsIndex = index }
              }
            }
          }
        }
      }
    }
  }

  // A section header that folds: chevron, title, and in place of the
  // content, one line saying what is in it.
  component DeviceRow: CursorSurface {
    id: drow
    property var row: ({})
    property int rowIndex: 0
    readonly property bool armed: root.unpairArmed === row.id
    readonly property bool working: !!root.phone && (root.phone.isBusy("pair:" + row.id) || root.phone.isBusy("accept:" + row.id)
      || root.phone.isBusy("reject:" + row.id) || root.phone.isBusy("unpair:" + row.id))

    hasCursor: root.cursorActive && root.focusSection === "devices" && root.deviceIndex === rowIndex
    current: row.current === true
    foreground: root.foreground
    implicitHeight: drowContent.implicitHeight + Style.space(12)

    MouseArea {
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: drow.row.paired && !drow.row.current ? Qt.PointingHandCursor : Qt.ArrowCursor
      onEntered: { root.cursorActive = true; root.focusSection = "devices"; root.deviceIndex = drow.rowIndex }
      onClicked: if (drow.row.paired && !drow.row.current) root.selectDevice(drow.row.id)
    }

    RowLayout {
      id: drowContent
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      anchors.leftMargin: Style.space(10)
      anchors.rightMargin: Style.space(8)
      spacing: Style.space(10)

      Text {
        text: drow.row.glyph || ""
        color: root.foreground
        opacity: drow.row.reachable ? 1.0 : 0.5
        font.family: root.fontFamily
        font.pixelSize: Style.font.heading
      }

      ColumnLayout {
        Layout.fillWidth: true
        spacing: Style.space(1)
        Text {
          Layout.fillWidth: true
          textFormat: Text.PlainText
          text: drow.row.name || ""
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
          font.bold: drow.row.current === true
          elide: Text.ElideRight
        }
        Text {
          Layout.fillWidth: true
          textFormat: Text.PlainText
          text: (drow.row.status || "") + (drow.row.key ? " · Key " + drow.row.key : "")
          color: drow.row.incoming ? root.foreground : root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          elide: Text.ElideRight
        }
      }

      Row {
        id: drowButtons
        spacing: Style.space(6)
        Layout.alignment: Qt.AlignVCenter
        opacity: drow.working ? 0 : 1.0
        enabled: !drow.working
        Behavior on opacity { NumberAnimation { duration: Model.MOTION.outMs * root.motion; easing.type: Easing.OutCubic } }


        Button {
          visible: drow.row.incoming === true
          text: "Accept"
          bordered: true
          foreground: root.foreground
          fontFamily: root.fontFamily
          fontSize: Style.font.bodySmall
          onClicked: root.phone.acceptPairing(drow.row.id)
        }
        Button {
          visible: drow.row.incoming === true || drow.row.outgoing === true
          text: drow.row.incoming ? "Reject" : "Cancel"
          foreground: root.foreground
          fontFamily: root.fontFamily
          fontSize: Style.font.bodySmall
          onClicked: root.phone.rejectPairing(drow.row.id)
        }
        Button {
          visible: !drow.row.paired && !drow.row.incoming && !drow.row.outgoing
          text: "Pair"
          bordered: true
          foreground: root.foreground
          fontFamily: root.fontFamily
          fontSize: Style.font.bodySmall
          onClicked: root.phone.pairWith(drow.row.id)
        }
        Button {
          visible: drow.row.paired === true && !drow.row.incoming
          text: drow.armed ? "Unpair?" : "Unpair"
          tooltipText: drow.armed ? "Click again to unpair" : ""
          foreground: drow.armed ? root.urgent : root.foreground
          fontFamily: root.fontFamily
          fontSize: Style.font.bodySmall
          onClicked: root.armOrUnpair(drow.row)
        }
      }
    }

    // Over the buttons, outside the layout, so nothing in the row moves.
    WaitRing {
      x: drowContent.x + drowButtons.x + (drowButtons.width - width) / 2
      y: drowContent.y + drowButtons.y + (drowButtons.height - height) / 2
      running: drow.working
      motion: root.motion
      color: root.foreground
      size: Math.round(Style.font.icon * 0.8)
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

    hasCursor: root.cursorActive && root.focusSection === "media"
    foreground: root.foreground
    implicitHeight: cardContent.implicitHeight + Style.space(14)
    Component.onCompleted: root.cardsBuilt += 1

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
            source: card.artUrl
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

    hasCursor: root.cursorActive && root.focusSection === "actions" && root.actionIndex === tileIndex
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

    hasCursor: root.cursorActive && root.focusSection === "notifications" && root.notifIndex === rowIndex
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

          TextField {
            id: replyField
            Layout.fillWidth: true
            placeholderText: "Reply to " + Model.notificationTitle(row.note)
            foreground: root.foreground
            font.family: root.fontFamily
            onActiveFocusChanged: root.replyFocused = activeFocus
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
            Keys.onEscapePressed: { text = ""; root.closeReply() }
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
