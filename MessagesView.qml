import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model

// Text messages, two panes: the threads on the left, the open conversation
// on the right. Draws SmsService's models and sends it the user's intent.
//
// Keyboard (while the composer is not focused): j/k move through the threads,
// Enter opens one and puts the cursor in the composer. In the composer, Enter
// sends and Esc steps back to the thread list.
Item {
  id: view

  property var sms: null
  property var bar: null
  property color foreground: Color.foreground
  property color urgent: Color.urgent
  property string fontFamily: Style.font.family

  readonly property color dim: Qt.darker(foreground, 1.55)
  readonly property color faint: Qt.darker(foreground, 2.2)

  // A thread was opened (by the user or restored): the panel remembers it.
  signal threadOpened(var tid)
  // The unread chip was clicked; the panel keeps the choice.
  signal unreadToggled()
  // A call to the open conversation's number: here through Bluetooth (#59),
  // else on the device's dialer. The panel says which (`callTip`).
  property bool canCall: false
  property string callTip: ""
  signal callRequested(string number)

  // Unsent text per conversation, kept while switching threads. Memory only:
  // it is message text, so it never goes to disk.
  property var drafts: ({})
  property var draftThread: -1

  function stashDraft() {
    if (draftThread === undefined || draftThread < 0) return
    var next = Object.assign({}, drafts)
    if (composer.text.trim() !== "") next[draftThread] = composer.text
    else delete next[draftThread]
    drafts = next
  }

  property int threadCursor: 0
  property bool cursorActive: false
  // Any text field here holding the keyboard: the panel's key catcher stands
  // aside while one does.
  readonly property bool composerFocused: composer.activeFocus || toField.activeFocus || searchField.activeFocus
  // Writing a reply: PgUp/PgDn scroll the conversation instead of the list.
  readonly property bool typingReply: composer.activeFocus
  // Where the keys go when no field has them: the conversation list, or the
  // open conversation (l / → in, h / ← out, Esc out). Each side shows its
  // highlight only while the keys go there.
  property string pane: "list"
  readonly property bool inConversation: pane === "conversation" && !!openRow && !typingReply
  // The message the keys are on in the open conversation: 0 is the newest.
  property int messageCursor: 0
  signal reported(string text)
  readonly property var shown: sms ? sms.shownThreads : null

  // New message: recipients picked in the "To" field, as [{title, number}].
  property bool newMode: false
  property var recipients: []
  property var suggestions: []
  property int suggestionCursor: 0
  property bool sendingNew: false

  function startNew(typeHere) {
    if (!sms) return
    sms.start()
    sms.closeThread()
    newMode = true
    recipients = []
    toField.text = ""
    refreshSuggestions()
    if (typeHere !== false) Qt.callLater(function() { toField.forceActiveFocus() })
  }

  function setToText(t) { toField.text = t; refreshSuggestions() }

  // Text back from a call: the caller's conversation when there is one, else
  // a new message with the caller already picked. While the reader is still
  // getting its conversations, the caller waits as the recipient and moves
  // into their conversation if it arrives.
  property string waitingCaller: ""
  function textTo(number, who, typeHere) {
    if (!sms) return
    sms.start()
    var tid = sms.threadForAddress(number)
    if (tid >= 0) { waitingCaller = ""; openThread(tid, typeHere); return }
    startNew(false)
    recipients = [{ title: who || Model.formatNumber(number), number: number }]
    refreshSuggestions()
    waitingCaller = sms.ready ? "" : number
    if (typeHere) Qt.callLater(function() { composer.forceActiveFocus() })
  }
  Connections {
    target: view.sms
    function onModelRevisionChanged() {
      if (view.waitingCaller === "") return
      if (!view.newMode || view.recipients.length !== 1 || view.recipients[0].number !== view.waitingCaller) { view.waitingCaller = ""; return }
      var tid = view.sms.threadForAddress(view.waitingCaller)
      if (tid < 0) { if (view.sms.ready) view.waitingCaller = ""; return }
      var draft = composer.text
      var typing = composer.activeFocus
      view.cancelNew()
      view.openThread(tid, typing)
      composer.text = draft
    }
  }

  function cancelNew() {
    newMode = false
    sendingNew = false
    recipients = []
    waitingCaller = ""
  }

  // With someone picked and nothing typed, no list: it finds the next
  // person, it is not a list to browse.
  function refreshSuggestions() {
    var typed = toField.text.trim()
    var list = sms && (typed !== "" || recipients.length === 0) ? sms.candidates(typed, 8) : []
    // What was typed, when it is a number nobody in the list has, comes
    // first (as messaging apps show it): Enter or a click sends to it, the
    // matches a ↓ away. Esc closing the suggestions does the same by key.
    var digits = typed.replace(/\D/g, "")
    if (/^\+?[\d\s().-]+$/.test(typed) && digits.length >= 3
        && !list.some(function(c) { return String(c.number || "").replace(/\D/g, "") === digits }))
      list = [{ title: Model.formatNumber(typed), number: typed, tid: -1, note: "This number" }].concat(list)
    suggestions = list
    suggestionCursor = 0
  }

  function addRecipient(c) {
    if (!c) return
    // One person with a conversation already: go to it, keeping what was typed.
    if (recipients.length === 0 && c.tid !== undefined && c.tid >= 0) {
      var draft = composer.text
      cancelNew()
      openThread(c.tid, true)
      composer.text = draft
      return
    }
    for (var i = 0; i < recipients.length; i++) if (recipients[i].number === c.number) return
    recipients = recipients.concat([{ title: c.title, number: c.number }])
    toField.text = ""
    refreshSuggestions()
  }

  // Enter in the "To" field: the highlighted suggestion, else what was typed
  // when it looks like a number.
  function acceptTo() {
    var typed = toField.text.trim()
    if (suggestions.length > 0 && (typed !== "" || recipients.length === 0)) { addRecipient(suggestions[suggestionCursor]); return }
    if (typed.replace(/\D/g, "").length >= 3) { addRecipient({ title: Model.formatNumber(typed), number: typed, tid: -1 }); return }
    if (recipients.length > 0) composer.forceActiveFocus()
  }

  function removeRecipient(i) {
    var next = recipients.slice()
    next.splice(i, 1)
    recipients = next
    refreshSuggestions()
  }
  readonly property var openRow: {
    var rev = sms ? sms.modelRevision : 0
    if (!sms || sms.openThreadId < 0) return null
    var at = sms.indexOfThread(sms.openThreadId)
    return at >= 0 ? sms.threads.get(at) : null
  }

  function moveCursor(dy) {
    if (!shown || shown.count === 0) return
    if (!cursorActive) { cursorActive = true; return }
    // Up from the first conversation: into search, as / does (and down from
    // search comes back).
    if (dy < 0 && threadCursor === 0) { focusSearch(); return }
    cursorTo(threadCursor + dy)
  }

  // The keys in messages: across (h/l, ←/→) between the list and the open
  // conversation; up and down on whichever side has them.
  function moveKey(dx, dy) {
    if (dx > 0) { enterConversation(); return }
    if (dx < 0) { pane = "list"; return }
    if (dy === 0) return
    if (pane === "conversation" && openRow) moveMessage(dy)
    else moveCursor(dy)
  }
  function enterConversation() {
    if (!openRow || messageList.count === 0 || pane === "conversation") return
    pane = "conversation"
    messageTo(Math.min(messageCursor, messageList.count - 1))
  }
  // Down is newer (towards the bottom, index 0), up is older.
  function moveMessage(dy) { messageTo(messageCursor - dy) }
  function messageTo(i) {
    if (messageList.count === 0) return
    messageGlide.stop()
    var from = messageList.contentY
    messageCursor = Math.max(0, Math.min(messageList.count - 1, i))
    messageList.positionViewAtIndex(messageCursor, ListView.Contain)
    glide(messageList, messageGlide, from, messageList.contentY)
  }
  // PgUp/PgDn in the conversation: the cursor a screen of messages at a time.
  function pageMessage(pages) {
    if (messageList.count === 0) return
    var avg = messageList.contentHeight / Math.max(1, messageList.count)
    messageTo(messageCursor + pages * Math.max(1, Math.floor(messageList.height / Math.max(1, avg)) - 1))
  }
  // Enter on a message: its picture opens (a copy made in the sandbox);
  // otherwise its text goes on the clipboard.
  function activateMessage() {
    var m = view.sms ? view.sms.messages.get(messageCursor) : null
    if (!m) return
    var files = []
    try { files = JSON.parse(m.attachments || "[]") } catch (e) {}
    for (var i = 0; i < files.length; i++) {
      if (String(files[i].mime).indexOf("image/") === 0) { view.sms.fetchAttachment(files[i].part, files[i].id, files[i].mime); return }
    }
    if (String(m.body || "") !== "") { copyText(m.body); return }
    if (files.length > 0) view.sms.fetchAttachment(files[0].part, files[0].id, files[0].mime)
  }
  // The text goes to wl-copy over stdin, never on its command line.
  Process {
    id: textCopier
    property string text: ""
    command: ["wl-copy"]
    stdinEnabled: true
    onStarted: { write(text); text = ""; stdinEnabled = false }
    onExited: { stdinEnabled = true; view.reported("Copied") }
  }
  function copyText(t) {
    if (textCopier.running) return
    textCopier.text = String(t)
    textCopier.running = true
  }

  function cursorTo(i) {
    if (!shown || shown.count === 0) return
    // The list glides to keep the cursor in sight, at the panel's pace, as
    // the cursor moves (a jump, then the move, read as two steps). Where it
    // goes is what positionViewAtIndex would set; it starts from where it is.
    threadGlide.stop()
    var from = threadList.contentY
    cursorByPointer = false
    cursorActive = true
    threadCursor = Math.max(0, Math.min(shown.count - 1, i))
    threadList.positionViewAtIndex(threadCursor, ListView.Contain)
    glide(threadList, threadGlide, from, threadList.contentY)
  }

  // Scrolling by key: from where the list is to where it goes, at the
  // panel's pace (Model.MOTION); a key held down starts each glide from
  // where the last one had got to.
  function glide(list, anim, from, to) {
    anim.stop()
    list.contentY = from
    if (Math.abs(to - from) < 0.5) return
    anim.from = from
    anim.to = to
    anim.start()
  }
  NumberAnimation { id: threadGlide; target: threadList; property: "contentY"; duration: Model.MOTION.inMs * view.motion; easing.type: Easing.OutCubic }
  NumberAnimation { id: messageGlide; target: messageList; property: "contentY"; duration: Model.MOTION.inMs * view.motion; easing.type: Easing.OutCubic }

  // PgUp/PgDn on the conversation list: the cursor a screen of rows at a
  // time, as the arrows move it one row; `pages` > 0 up.
  function pageCursor(pages) {
    if (!shown || shown.count === 0) return
    var rowHeight = threadList.contentHeight / Math.max(1, threadList.count)
    var rows = Math.max(1, Math.floor(threadList.height / Math.max(1, rowHeight)) - 1)
    cursorTo((cursorActive ? threadCursor : 0) - pages * rows)
  }

  // Where the pointer last was on screen, so a row that slides under a still
  // pointer (the keys scrolled the list) is told apart from the pointer
  // moving onto it.
  property point lastPointer: Qt.point(-1, -1)
  // The cursor last moved by the pointer: the highlight lands at once.
  property bool cursorByPointer: false
  function pointerAt(area, index) {
    var g = area.mapToGlobal(area.mouseX, area.mouseY)
    var moved = Math.abs(g.x - lastPointer.x) > 0.5 || Math.abs(g.y - lastPointer.y) > 0.5
    lastPointer = Qt.point(g.x, g.y)
    if (!moved) return
    cursorByPointer = true
    cursorActive = true
    threadCursor = index
  }

  function activateCursor() {
    if (inConversation) { activateMessage(); return }
    if (!shown || threadCursor < 0 || threadCursor >= shown.count) return
    openThread(shown.get(threadCursor).tid, true)
  }

  function focusSearch() { searchField.forceActiveFocus(); searchField.selectAll() }
  function setSearch(q) { searchField.text = q }
  readonly property string searchText: searchField.text
  readonly property string toText: toField.text

  // Esc undoes the innermost thing open, one at a time: a name being typed
  // in "To" (its list goes with it), the new message, the search. False
  // when nothing is open here, so the panel closes messages.
  function goBack() {
    if (pane === "conversation") { pane = "list"; return true }
    if (newMode && toField.text !== "") { toField.text = ""; return true }
    if (newMode) { cancelNew(); return true }
    if (searchField.text !== "") { searchField.text = ""; return true }
    return false
  }

  // PgUp/PgDn: a screen of the open conversation, `pages` > 0 up (older).
  // The list runs bottom to top, but contentY still grows downwards on
  // screen, so up is a smaller contentY.
  function scrollMessages(pages) {
    if (!openRow || messageList.height <= 0) return
    // Oldest at the top edge, newest at the bottom one. A conversation that
    // fits has nothing to scroll: it stays at the bottom, as it opened.
    var top = messageList.originY
    var bottom = messageList.originY + messageList.contentHeight - messageList.height
    if (bottom <= top) return
    var step = messageList.height * 0.85 * pages
    // From where a glide under way has got to, or from rest; to the next screen.
    var base = messageGlide.running ? messageGlide.to : messageList.contentY
    glide(messageList, messageGlide, messageList.contentY, Math.max(top, Math.min(bottom, base - step)))
  }

  // `typeHere` puts the cursor in the composer: for the user's own click or
  // Enter, never for a scripted open (IPC), where keystrokes meant for
  // another window could land in a text and Enter would send it.
  function openThread(tid, typeHere) {
    if (!sms) return
    // Another conversation: the keys back on the list, its newest message next.
    if (sms.openThreadId !== tid) { pane = "list"; messageCursor = 0 }
    stashDraft()
    newMode = false
    sms.openThread(tid)
    draftThread = tid
    composer.text = drafts[tid] || ""
    threadOpened(tid)
    var at = sms.indexOfThread(tid)
    if (shown && shown !== sms.threads) {
      for (var j = 0; j < shown.count; j++) if (shown.get(j).tid === tid) { at = j; break }
    }
    if (at >= 0 && at < (shown ? shown.count : 0)) { cursorByPointer = true; threadCursor = at; threadList.positionViewAtIndex(at, ListView.Contain) }
    if (typeHere) Qt.callLater(function() { composer.forceActiveFocus() })
  }

  function blurComposer() {
    composer.focus = false
  }

  function focusComposer() {
    if (openRow || newMode) composer.forceActiveFocus()
  }

  // A conversation's messages ease in when they land: they rise into place
  // while the skeleton, if one showed, fades. The header and the composer
  // stay on the pane's edges and never move; only their contents change.

  // The header's who: its shape only while the conversation is not known
  // yet (opened before the list arrived). Moving between conversations,
  // the name crossfades in place: out quickly, swap, in at the shared pace,
  // so j/k held down just keeps crossfading to wherever it stops.
  readonly property bool headerLoading: !newMode && !!sms && sms.openThreadId >= 0 && !openRow
  property var shownRow: null
  onOpenRowChanged: {
    if (!openRow || !shownRow || openRow.tid === shownRow.tid) { shownRow = openRow; return }
    headerSwap.restart()
  }
  SequentialAnimation {
    id: headerSwap
    NumberAnimation { target: headerWho; property: "opacity"; to: 0; duration: Model.MOTION.outMs * view.motion; easing.type: Easing.OutCubic }
    ScriptAction { script: view.shownRow = view.openRow }
    NumberAnimation { target: headerWho; property: "opacity"; to: 1; duration: Model.MOTION.inMs * view.motion; easing.type: Easing.OutCubic }
  }

  // A skeleton only for a wait worth showing: a load that lands within a
  // quarter second goes straight to its content, with no flash of shapes.
  readonly property int skeletonDelayMs: 250
  readonly property bool conversationWaiting: !newMode && !!sms && sms.openThreadId >= 0 && sms.loading && messageList.count === 0
  property bool conversationSkeleton: false
  onConversationWaitingChanged: {
    conversationSkeleton = false
    if (conversationWaiting) conversationSkeletonDelay.restart()
    else {
      conversationSkeletonDelay.stop()
      if (messageList.count > 0) paneReveal.restart()
    }
  }
  Timer { id: conversationSkeletonDelay; interval: view.skeletonDelayMs; onTriggered: view.conversationSkeleton = true }

  readonly property bool threadsWaiting: !!sms && !sms.ready && sms.reachable
  property bool threadsSkeleton: false
  onThreadsWaitingChanged: {
    threadsSkeleton = false
    if (threadsWaiting) threadsSkeletonDelay.restart(); else threadsSkeletonDelay.stop()
  }
  Timer { id: threadsSkeletonDelay; interval: view.skeletonDelayMs; onTriggered: view.threadsSkeleton = true }
  Component.onCompleted: if (threadsWaiting) threadsSkeletonDelay.restart()

  property real motion: 1

  // The conversations ease in the same way when they land after their
  // skeleton; the title, search and key hints around them stay put.
  readonly property bool threadsReady: !!sms && sms.ready
  onThreadsReadyChanged: if (threadsReady) threadReveal.restart()

  ParallelAnimation {
    id: threadReveal
    NumberAnimation { target: threadList; property: "opacity"; from: 0; to: 1; duration: Model.MOTION.inMs * view.motion; easing.type: Easing.OutCubic }
    NumberAnimation { target: threadShift; property: "y"; from: Style.space(14); to: 0; duration: Model.MOTION.inMs * view.motion; easing.type: Easing.OutCubic }
  }

  ParallelAnimation {
    id: paneReveal
    NumberAnimation { target: messageList; property: "opacity"; from: 0; to: 1; duration: Model.MOTION.inMs * view.motion; easing.type: Easing.OutCubic }
    NumberAnimation { target: listShift; property: "y"; from: Style.space(14); to: 0; duration: Model.MOTION.inMs * view.motion; easing.type: Easing.OutCubic }
  }

  Connections {
    target: view.sms
    function onNewThreadReady(tid) {
      if (!view.newMode) return
      view.cancelNew()
      view.openThread(tid, true)
    }
  }

  RowLayout {
    anchors.fill: parent
    spacing: 0

    // ---- Threads ----
    Item {
      Layout.preferredWidth: Style.space(300)
      Layout.fillHeight: true

      ColumnLayout {
        anchors.fill: parent
        spacing: Style.space(6)

        RowLayout {
          Layout.fillWidth: true
          PanelSectionHeader {
            Layout.fillWidth: true
            text: "CONVERSATIONS"
            foreground: view.foreground
            fontFamily: view.fontFamily
          }
          // The unread count is the filter: click (or u) for unread only.
          Button {
            visible: !!view.sms && (view.sms.unreadCount > 0 || view.sms.unreadOnly)
            text: (view.sms ? view.sms.unreadCount : 0) + " unread"
            tooltipText: view.sms && view.sms.unreadOnly ? "Show all conversations (u)" : "Show unread only (u)"
            selected: !!view.sms && view.sms.unreadOnly
            bordered: true
            foreground: view.foreground
            fontFamily: view.fontFamily
            fontSize: Style.font.caption
            verticalPadding: Style.space(2)
            horizontalPadding: Style.space(8)
            onClicked: view.unreadToggled()
          }
          PanelActionButton {
            iconText: Model.GLYPH.newMessage
            tooltipText: "New message (n)"
            foreground: view.foreground
            fontFamily: view.fontFamily
            enabled: !!view.sms && view.sms.reachable
            onClicked: view.startNew()
          }
        }

        PanelField {
          id: searchField
          Layout.fillWidth: true
          placeholderText: "Search conversations  /"
          foreground: view.foreground
          font.family: view.fontFamily
          onTextChanged: if (view.sms) view.sms.setQuery(text)
          onAccepted: { if (view.shown && view.shown.count > 0) view.openThread(view.shown.get(0).tid, true) }
          escapeStep: "clear"
          onSteppedOut: focus = false
          Keys.onDownPressed: { focus = false; view.cursorTo(0) }
        }

        Text {
          Layout.fillWidth: true
          visible: !!view.sms && view.sms.filtering && !!view.shown && view.shown.count === 0
          textFormat: Text.PlainText
          text: view.sms && view.sms.unreadOnly && view.sms.query.trim() === "" ? "Nothing unread." : "No conversation matches."
          color: view.dim
          font.family: view.fontFamily
          font.pixelSize: Style.font.bodySmall
        }

        Text {
          Layout.fillWidth: true
          visible: !!view.sms && !view.sms.ready && !view.sms.reachable
          textFormat: Text.PlainText
          wrapMode: Text.WordWrap
          text: "The device is away. Conversations load when it reconnects."
          color: view.dim
          font.family: view.fontFamily
          font.pixelSize: Style.font.bodySmall
        }

        // The conversations on their way from the phone: the shape of the
        // list, until the first ones land.
        Column {
          Layout.fillWidth: true
          visible: view.threadsWaiting
          opacity: view.threadsSkeleton ? 1 : 0
          Behavior on opacity { NumberAnimation { duration: Model.MOTION.inMs * view.motion; easing.type: Easing.OutCubic } }
          spacing: Style.space(2)
          Repeater {
            model: 6
            Item {
              required property int index
              width: parent.width - Style.space(8)
              height: Style.space(32) + Style.space(12)
              Skeleton {
                id: faceBone
                x: Style.space(8)
                anchors.verticalCenter: parent.verticalCenter
                width: Style.space(32)
                height: Style.space(32)
                radius: width / 2
                foreground: view.foreground
                motion: view.motion
              }
              Skeleton {
                x: faceBone.x + faceBone.width + Style.space(10)
                y: faceBone.y + Style.space(3)
                width: (parent.width - x - Style.space(8)) * [0.55, 0.4, 0.65, 0.35, 0.5, 0.45][index]
                height: Style.space(10)
                foreground: view.foreground
                motion: view.motion
              }
              Skeleton {
                x: faceBone.x + faceBone.width + Style.space(10)
                y: faceBone.y + faceBone.height - height - Style.space(3)
                width: (parent.width - x - Style.space(8)) * [0.85, 0.7, 0.9, 0.6, 0.8, 0.75][index]
                height: Style.space(8)
                foreground: view.foreground
                motion: view.motion
              }
            }
          }
        }

        ListView {
          id: threadList
          WheelScroll { flickable: threadList; motion: view.motion }
          Layout.fillWidth: true
          Layout.fillHeight: true
          clip: true
          model: view.shown
          transform: Translate { id: threadShift }
          spacing: Style.space(2)
          boundsBehavior: Flickable.StopAtBounds
          ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

          // The cursor is one highlight that slides from row to row at the
          // panel's pace when the keys move it, and lands at once where the
          // pointer goes (it never trails the mouse). Writing a reply, it
          // steps back: the keys go to the composer.
          currentIndex: view.threadCursor
          highlightFollowsCurrentItem: true
          highlightMoveDuration: view.cursorByPointer ? 0 : Model.MOTION.inMs * view.motion
          highlightMoveVelocity: -1
          highlightResizeDuration: 0
          highlightResizeVelocity: -1
          highlight: CursorSurface {
            width: threadList.width - Style.space(8)
            hasCursor: true
            foreground: view.foreground
            opacity: view.cursorActive && !view.typingReply && view.pane === "list" ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: Model.MOTION.inMs * view.motion; easing.type: Easing.OutCubic } }
          }

          delegate: ThreadRow {
            width: threadList.width - Style.space(8)
          }
        }

        Text {
          Layout.fillWidth: true
          textFormat: Text.PlainText
          wrapMode: Text.WordWrap
          text: "j/k move · Enter open · / search · u unread · n new · h/l side · i reply · PgUp/PgDn page · Esc back"
          color: view.faint
          font.family: view.fontFamily
          font.pixelSize: Style.font.caption
        }
      }
    }

    Rectangle {
      Layout.fillHeight: true
      Layout.preferredWidth: 1
      Layout.leftMargin: Style.space(10)
      Layout.rightMargin: Style.space(12)
      color: view.faint
    }

    // ---- The open conversation ----
    Item {
      Layout.fillWidth: true
      Layout.fillHeight: true

      Column {
        anchors.centerIn: parent
        visible: !(!!view.sms && view.sms.openThreadId >= 0) && !view.newMode
        spacing: Style.space(6)
        Text {
          anchors.horizontalCenter: parent.horizontalCenter
          text: Model.GLYPH.messages
          color: view.dim
          font.family: view.fontFamily
          font.pixelSize: Style.font.display
        }
        Text {
          anchors.horizontalCenter: parent.horizontalCenter
          textFormat: Text.PlainText
          text: "Pick a conversation"
          color: view.dim
          font.family: view.fontFamily
          font.pixelSize: Style.font.body
        }
      }

      ColumnLayout {
        id: convPane
        anchors.fill: parent
        visible: (!!view.sms && view.sms.openThreadId >= 0) || view.newMode
        spacing: Style.space(8)

        // ---- New message: who to ----
        ColumnLayout {
          Layout.fillWidth: true
          visible: view.newMode
          spacing: Style.space(6)

          RowLayout {
            Layout.fillWidth: true
            Text {
              Layout.fillWidth: true
              textFormat: Text.PlainText
              text: "New message"
              color: view.foreground
              font.family: view.fontFamily
              font.pixelSize: Style.font.title
              font.bold: true
            }
            PanelActionButton {
              iconText: Model.GLYPH.close
              tooltipText: "Cancel"
              foreground: view.foreground
              fontFamily: view.fontFamily
              onClicked: view.cancelNew()
            }
          }

          Flow {
            Layout.fillWidth: true
            spacing: Style.space(6)
            visible: view.recipients.length > 0

            Repeater {
              model: view.recipients
              BorderSurface {
                required property var modelData
                required property int index
                implicitWidth: chipRow.implicitWidth + Style.space(12)
                implicitHeight: chipRow.implicitHeight + Style.space(6)
                radius: Style.cornerRadius
                color: Style.selectedFillFor(view.foreground, Color.accent)
                Row {
                  id: chipRow
                  anchors.centerIn: parent
                  spacing: Style.space(6)
                  Text {
                    anchors.verticalCenter: parent.verticalCenter
                    textFormat: Text.PlainText
                    text: modelData.title
                    color: view.foreground
                    font.family: view.fontFamily
                    font.pixelSize: Style.font.bodySmall
                  }
                  Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: Model.GLYPH.close
                    color: view.dim
                    font.family: view.fontFamily
                    font.pixelSize: Style.font.caption
                    MouseArea {
                      anchors.fill: parent
                      anchors.margins: -Style.space(4)
                      cursorShape: Qt.PointingHandCursor
                      onClicked: view.removeRecipient(index)
                    }
                  }
                }
              }
            }
          }

          PanelField {
            id: toField
            Layout.fillWidth: true
            placeholderText: view.recipients.length > 0 ? "Add someone else" : "To: name or number"
            foreground: view.foreground
            font.family: view.fontFamily
            onTextChanged: view.refreshSuggestions()
            onAccepted: view.acceptTo()
            // Esc: the suggestions close and what was typed stays (Enter then
            // sends to exactly that); then the field clears; then the new
            // message is left. Typing brings the suggestions back.
            escapeStep: "clear"
            floating: view.suggestions.length > 0 && text.trim() !== ""
            onCloseFloating: view.suggestions = []
            onSteppedOut: view.goBack()
            Keys.onDownPressed: view.suggestionCursor = Math.min(view.suggestions.length - 1, view.suggestionCursor + 1)
            Keys.onUpPressed: view.suggestionCursor = Math.max(0, view.suggestionCursor - 1)
            Keys.onPressed: function(event) {
              if (event.key === Qt.Key_Backspace && text === "" && view.recipients.length > 0) {
                view.removeRecipient(view.recipients.length - 1)
                event.accepted = true
              } else if (event.key === Qt.Key_Tab && view.recipients.length > 0) {
                composer.forceActiveFocus()
                event.accepted = true
              }
            }
          }

          Text {
            Layout.fillWidth: true
            visible: !!view.sms && view.sms.contactCount === 0
            textFormat: Text.PlainText
            wrapMode: Text.WordWrap
            text: "Contact names are not synced from the device yet, so search matches numbers. Allow contacts in its KDE Connect app to search by name."
            color: view.dim
            font.family: view.fontFamily
            font.pixelSize: Style.font.caption
          }
        }

        ListView {
          id: suggestionList
          WheelScroll { flickable: suggestionList; motion: view.motion }
          Layout.fillWidth: true
          Layout.fillHeight: true
          visible: view.newMode
          clip: true
          model: view.suggestions
          spacing: Style.space(2)
          delegate: CursorSurface {
            id: suggestion
            required property var modelData
            required property int index
            width: suggestionList.width
            hasCursor: view.suggestionCursor === index
            foreground: view.foreground
            implicitHeight: suggestionText.implicitHeight + Style.space(10)
            MouseArea {
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onEntered: view.suggestionCursor = suggestion.index
              // The user's own click: on to writing the message.
              onClicked: {
                view.addRecipient(suggestion.modelData)
                if (view.newMode) composer.forceActiveFocus()
              }
            }
            Column {
              id: suggestionText
              anchors.left: parent.left
              anchors.leftMargin: Style.space(10)
              anchors.verticalCenter: parent.verticalCenter
              Text {
                textFormat: Text.PlainText
                text: suggestion.modelData.title
                color: view.foreground
                font.family: view.fontFamily
                font.pixelSize: Style.font.body
              }
              Text {
                textFormat: Text.PlainText
                visible: suggestion.modelData.name !== ""
                text: suggestion.modelData.note ? suggestion.modelData.note : Model.formatNumber(suggestion.modelData.number)
                color: view.dim
                font.family: view.fontFamily
                font.pixelSize: Style.font.caption
              }
            }
          }
        }

        // ---- Conversation header: who ----
        // Pinned to the top: while the conversation loads it shows the
        // shape of a name and a number, then the text lands in place.
        ColumnLayout {
          id: headerWho
          Layout.fillWidth: true
          visible: !view.newMode
          spacing: Style.space(1)
          Item {
            Layout.fillWidth: true
            implicitHeight: headerTitle.implicitHeight
            Text {
              id: headerTitle
              width: parent.width - (headerCall.visible ? headerCall.width + Style.space(8) : 0)
              textFormat: Text.PlainText
              text: view.shownRow ? view.shownRow.title : " "
              color: view.foreground
              opacity: view.headerLoading ? 0 : 1
              font.family: view.fontFamily
              font.pixelSize: Style.font.title
              font.bold: true
              elide: Text.ElideRight
              Behavior on opacity { NumberAnimation { duration: (view.headerLoading ? Model.MOTION.outMs : Model.MOTION.inMs) * view.motion; easing.type: Easing.OutCubic } }
            }
            // Call them: one person's conversation only.
            PanelActionButton {
              id: headerCall
              visible: view.canCall && !view.headerLoading && !!view.shownRow && !view.shownRow.group && String(view.shownRow.addresses || "") !== ""
                && String(view.shownRow.addresses).indexOf(",") < 0
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              iconText: Model.GLYPH.callBack
              tooltipText: view.callTip
              foreground: view.foreground
              fontFamily: view.fontFamily
              onClicked: if (view.shownRow) view.callRequested(String(view.shownRow.addresses))
            }
            Skeleton {
              visible: view.headerLoading
              anchors.verticalCenter: parent.verticalCenter
              width: Math.min(parent.width, Style.space(180))
              height: Math.round(headerTitle.implicitHeight * 0.6)
              foreground: view.foreground
              motion: view.motion
            }
          }
          Item {
            Layout.fillWidth: true
            visible: view.headerLoading || (!!view.shownRow && view.shownRow.addresses !== view.shownRow.title)
            implicitHeight: headerNumber.implicitHeight
            Text {
              id: headerNumber
              width: parent.width
              textFormat: Text.PlainText
              text: view.shownRow ? view.shownRow.addresses : " "
              color: view.dim
              opacity: view.headerLoading ? 0 : 1
              font.family: view.fontFamily
              font.pixelSize: Style.font.caption
              elide: Text.ElideRight
              Behavior on opacity { NumberAnimation { duration: (view.headerLoading ? Model.MOTION.outMs : Model.MOTION.inMs) * view.motion; easing.type: Easing.OutCubic } }
            }
            Skeleton {
              visible: view.headerLoading
              anchors.verticalCenter: parent.verticalCenter
              width: Math.min(parent.width, Style.space(110))
              height: Math.round(headerNumber.implicitHeight * 0.6)
              foreground: view.foreground
              motion: view.motion
            }
          }
        }

        PanelSeparator { Layout.fillWidth: true; foreground: view.foreground; visible: !view.newMode }

        ListView {
          id: messageList
          WheelScroll { flickable: messageList; motion: view.motion }
          visible: !view.newMode
          Layout.fillWidth: true
          Layout.fillHeight: true
          clip: true
          model: view.sms ? view.sms.messages : null
          transform: Translate { id: listShift }
          // Newest at the bottom, like every messaging app; older pages grow
          // upwards without moving what is on screen.
          verticalLayoutDirection: ListView.BottomToTop
          spacing: Style.space(6)
          boundsBehavior: Flickable.StopAtBounds
          ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
          // The message the keys are on: one highlight that slides from
          // message to message, shown only while the keys go here.
          currentIndex: view.messageCursor
          highlightFollowsCurrentItem: true
          highlightMoveDuration: Model.MOTION.inMs * view.motion
          highlightMoveVelocity: -1
          highlightResizeDuration: 0
          highlightResizeVelocity: -1
          highlight: CursorSurface {
            width: messageList.width
            hasCursor: true
            foreground: view.foreground
            opacity: view.inConversation ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: Model.MOTION.inMs * view.motion; easing.type: Easing.OutCubic } }
          }

          function maybeLoadMore() {
            if (!view.sms || !view.sms.hasMore || view.sms.loading) return
            // Near the top, or not enough history yet to fill the pane.
            if (contentHeight < height || visibleArea.yPosition < 0.08) view.sms.loadMore()
          }
          onContentYChanged: maybeLoadMore()
          onCountChanged: Qt.callLater(maybeLoadMore)

          // Only once there are messages: a conversation still opening shows
          // its skeleton instead.
          header: Item {
            width: messageList.width
            height: view.sms && view.sms.loading && messageList.count > 0 ? Style.space(24) : 0
            Row {
              anchors.centerIn: parent
              visible: parent.height > 0
              spacing: Style.space(6)
              WaitRing {
                anchors.verticalCenter: parent.verticalCenter
                running: parent.visible
                motion: view.motion
                color: view.dim
                size: Math.round(Style.font.bodySmall * 0.8)
              }
              Text {
                anchors.verticalCenter: parent.verticalCenter
                textFormat: Text.PlainText
                text: "Loading older messages…"
                color: view.dim
                font.family: view.fontFamily
                font.pixelSize: Style.font.caption
              }
            }
          }

          // The conversation on its way from the phone: bubbles' shapes,
          // newest at the bottom like the messages that replace them.
          Column {
            parent: messageList
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            anchors.rightMargin: Style.space(10)
            visible: opacity > 0
            opacity: view.conversationWaiting && view.conversationSkeleton ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: (view.conversationSkeleton ? Model.MOTION.inMs : Model.MOTION.outMs) * view.motion; easing.type: Easing.OutCubic } }
            spacing: Style.space(6)
            Repeater {
              model: 6
              Item {
                required property int index
                readonly property bool mine: [false, true, false, false, true, false][index]
                width: parent.width
                height: bubbleBone.height
                Skeleton {
                  id: bubbleBone
                  x: parent.mine ? parent.width - width : 0
                  width: parent.width * [0.5, 0.35, 0.62, 0.3, 0.45, 0.55][parent.index]
                  height: [Style.space(34), Style.space(34), Style.space(52), Style.space(34), Style.space(52), Style.space(34)][parent.index]
                  radius: Style.space(10)
                  foreground: view.foreground
                  motion: view.motion
                }
              }
            }
          }

          delegate: Bubble {
            width: messageList.width - Style.space(10)
          }
        }

        RowLayout {
          Layout.fillWidth: true
          spacing: Style.space(6)

          PanelField {
            id: composer
            Layout.fillWidth: true
            placeholderText: !view.sms || !view.sms.reachable ? "The device is away"
              : (view.newMode && view.recipients.length === 0 ? "Pick who to send to first" : "Text message")
            enabled: !!view.sms && view.sms.reachable
            foreground: view.foreground
            font.family: view.fontFamily
            onAccepted: view.sendComposer()
            // Esc leaves the reply; the draft stays.
            onSteppedOut: view.blurComposer()
          }
          // A new conversation waits for its thread to show up; the button
          // is the ring meanwhile.
          WaitButton {
            glyph: Model.GLYPH.send
            waiting: view.newMode && view.sendingNew
            motion: view.motion
            tooltipText: waiting ? "Sending" : "Send"
            foreground: view.foreground
            fontFamily: view.fontFamily
            enabled: composer.text.trim() !== "" && !!view.sms && view.sms.reachable
              && (!view.newMode || (view.recipients.length > 0 && !view.sendingNew))
            onClicked: view.sendComposer()
          }
        }
      }
    }
  }

  function sendComposer() {
    if (!sms) return
    if (newMode) {
      if (recipients.length === 0 || sendingNew) return
      var numbers = []
      for (var i = 0; i < recipients.length; i++) numbers.push(recipients[i].number)
      if (sms.sendNew(numbers, composer.text)) { composer.text = ""; sendingNew = true }
      return
    }
    if (sms.reply(composer.text)) {
      composer.text = ""
      var next = Object.assign({}, drafts)
      delete next[sms.openThreadId]
      drafts = next
    }
  }

  component ThreadRow: CursorSurface {
    id: row
    required property int index
    required property var tid
    required property string title
    required property string initial
    required property string snippet
    required property var date
    required property bool unread
    required property bool group

    readonly property bool isOpen: !!view.sms && view.sms.openThreadId === tid
    // Where the keys go, shown: the list cursor's highlight while they go to
    // the list; writing a reply, it steps back (the open conversation keeps
    // its selected look) and the composer's focus shows instead.
    // The cursor is the list's sliding highlight (threadList.highlight).
    hasCursor: false
    current: isOpen
    foreground: view.foreground
    implicitHeight: rowContent.implicitHeight + Style.space(12)

    MouseArea {
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      // The pointer takes the cursor only when it moves: rows the keys
      // scroll under a resting pointer do not (they took it back from the
      // arrow, which then seemed to scroll without moving).
      onEntered: view.pointerAt(this, row.index)
      onPositionChanged: view.pointerAt(this, row.index)
      onClicked: view.openThread(row.tid, true)
    }

    RowLayout {
      id: rowContent
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      anchors.leftMargin: Style.space(8)
      anchors.rightMargin: Style.space(8)
      spacing: Style.space(10)

      Rectangle {
        Layout.preferredWidth: Style.space(32)
        Layout.preferredHeight: Style.space(32)
        radius: width / 2
        color: Style.selectedFillFor(view.foreground, Color.accent)
        Text {
          anchors.centerIn: parent
          textFormat: Text.PlainText
          text: row.group ? Model.GLYPH.group : row.initial
          color: view.foreground
          font.family: view.fontFamily
          font.pixelSize: Style.font.body
          font.bold: true
        }
      }

      ColumnLayout {
        Layout.fillWidth: true
        spacing: Style.space(2)

        RowLayout {
          Layout.fillWidth: true
          spacing: Style.space(6)
          Text {
            Layout.fillWidth: true
            textFormat: Text.PlainText
            text: row.title
            color: view.foreground
            font.family: view.fontFamily
            font.pixelSize: Style.font.body
            font.bold: row.unread
            elide: Text.ElideRight
          }
          Text {
            textFormat: Text.PlainText
            text: Model.threadTime(row.date)
            color: row.unread ? view.foreground : view.dim
            font.family: view.fontFamily
            font.pixelSize: Style.font.caption
          }
        }
        RowLayout {
          Layout.fillWidth: true
          spacing: Style.space(6)
          Text {
            Layout.fillWidth: true
            textFormat: Text.PlainText
            text: row.snippet
            color: row.unread ? view.foreground : view.dim
            font.family: view.fontFamily
            font.pixelSize: Style.font.bodySmall
            elide: Text.ElideRight
            maximumLineCount: 1
          }
          Rectangle {
            visible: row.unread
            Layout.preferredWidth: Style.space(8)
            Layout.preferredHeight: Style.space(8)
            radius: width / 2
            color: view.foreground
          }
        }
      }
    }
  }

  component Bubble: Item {
    id: bubble
    required property string body
    required property bool sent
    required property string time
    required property bool pending
    required property bool failed
    required property string sender
    required property bool showDay
    required property string day
    required property string attachments

    readonly property var files: {
      try { return JSON.parse(attachments) } catch (e) { return [] }
    }
    readonly property real maxWidth: width * 0.78
    readonly property real padX: Style.space(10)
    readonly property real padY: Style.space(7)
    readonly property bool isGroup: !!view.openRow && view.openRow.group

    implicitHeight: bubbleColumn.implicitHeight

    Column {
      id: bubbleColumn
      width: parent.width
      spacing: Style.space(3)

      Text {
        visible: bubble.showDay
        width: parent.width
        topPadding: Style.space(10)
        bottomPadding: Style.space(4)
        horizontalAlignment: Text.AlignHCenter
        textFormat: Text.PlainText
        text: bubble.day.toUpperCase()
        color: view.dim
        font.family: view.fontFamily
        font.pixelSize: Style.font.caption
        font.bold: true
        font.letterSpacing: 1.0
      }

      Text {
        visible: bubble.isGroup && !bubble.sent && bubble.sender !== ""
        textFormat: Text.PlainText
        text: bubble.sender
        color: view.dim
        font.family: view.fontFamily
        font.pixelSize: Style.font.caption
      }

      Item {
        width: parent.width
        height: body.height

        Rectangle {
          id: body
          anchors.right: bubble.sent ? parent.right : undefined
          anchors.left: bubble.sent ? undefined : parent.left
          width: Math.max(bodyText.visible ? bodyText.width : 0, fileColumn.width, Style.space(24)) + bubble.padX * 2
          height: (fileColumn.visible ? fileColumn.height : 0)
            + (bodyText.visible ? bodyText.height : 0)
            + (fileColumn.visible && bodyText.visible ? Style.space(6) : 0)
            + bubble.padY * 2
          radius: Style.cornerRadius
          color: bubble.sent
            ? Style.selectedFillFor(view.foreground, Color.accent)
            : Style.hoverFillFor(view.foreground, Color.accent)
          border.width: bubble.failed ? 1 : 0
          border.color: view.urgent
          opacity: bubble.pending ? 0.7 : 1.0

          // Pictures show their preview; click fetches the full file from the
          // phone and opens it. Other files (voice, video) are a chip.
          Column {
            id: fileColumn
            x: bubble.padX
            y: bubble.padY
            visible: bubble.files.length > 0
            spacing: Style.space(6)

            Repeater {
              model: bubble.files
              Item {
                id: file
                required property var modelData
                // A missing preview falls back to the chip instead of an empty box.
                readonly property bool picture: String(modelData.mime).indexOf("image/") === 0 && modelData.thumb !== "" && preview.status !== Image.Error
                readonly property bool fetching: !!view.sms && view.sms.isFetching(modelData.id)
                width: picture ? Style.space(140) : fileChip.implicitWidth
                height: picture ? Style.space(140) : fileChip.implicitHeight

                Image {
                  id: preview
                  anchors.fill: parent
                  visible: file.picture
                  source: file.picture ? "file://" + file.modelData.thumb : ""
                  fillMode: Image.PreserveAspectCrop
                  asynchronous: true
                  smooth: true
                  opacity: file.fetching ? 0.5 : 1.0
                }
                Row {
                  id: fileChip
                  visible: !file.picture
                  spacing: Style.space(6)
                  Item {
                    width: chipGlyph.implicitWidth
                    height: chipGlyph.implicitHeight
                    Text {
                      id: chipGlyph
                      opacity: file.fetching ? 0 : 1
                      text: String(file.modelData.mime).indexOf("video/") === 0 ? Model.GLYPH.video
                        : (String(file.modelData.mime).indexOf("audio/") === 0 ? Model.GLYPH.music
                        : (String(file.modelData.mime).indexOf("image/") === 0 ? Model.GLYPH.picture : Model.GLYPH.file))
                      color: view.foreground
                      font.family: view.fontFamily
                      font.pixelSize: Style.font.heading
                    }
                    WaitRing {
                      anchors.centerIn: parent
                      running: file.fetching && !file.picture
                      motion: view.motion
                      color: view.foreground
                      size: Math.round(Style.font.body * 0.8)
                    }
                  }
                  Text {
                    anchors.verticalCenter: parent.verticalCenter
                    textFormat: Text.PlainText
                    text: (String(file.modelData.mime).indexOf("video/") === 0 ? "Video"
                      : (String(file.modelData.mime).indexOf("audio/") === 0 ? "Voice message"
                      : (String(file.modelData.mime).indexOf("image/") === 0 ? "Picture" : "File")))
                      + (file.fetching ? " · opening…" : " · open")
                    color: view.foreground
                    font.family: view.fontFamily
                    font.pixelSize: Style.font.bodySmall
                  }
                }
                WaitRing {
                  anchors.centerIn: parent
                  running: file.fetching && file.picture
                  motion: view.motion
                  color: view.foreground
                  size: Math.round(Style.font.heading * 0.8)
                }
                MouseArea {
                  anchors.fill: parent
                  cursorShape: Qt.PointingHandCursor
                  enabled: !file.fetching && !!view.sms && view.sms.reachable
                  onClicked: view.sms.fetchAttachment(file.modelData.part, file.modelData.id, file.modelData.mime)
                }
              }
            }
          }

          TextEdit {
            id: bodyText
            visible: bubble.body !== ""
            x: bubble.padX
            y: bubble.padY + (fileColumn.visible ? fileColumn.height + Style.space(6) : 0)
            width: Math.min(implicitWidth, bubble.maxWidth - bubble.padX * 2)
            readOnly: true
            selectByMouse: true
            textFormat: TextEdit.PlainText
            wrapMode: TextEdit.Wrap
            text: bubble.body
            color: view.foreground
            selectionColor: Style.selectionFillFor(view.foreground, Color.accent)
            font.family: view.fontFamily
            font.pixelSize: Style.font.body
          }
        }
      }

      Row {
        anchors.right: bubble.sent ? parent.right : undefined
        spacing: Style.space(4)
        WaitRing {
          anchors.verticalCenter: parent.verticalCenter
          running: bubble.pending && !bubble.failed
          motion: view.motion
          color: view.faint
          size: Math.round(Style.font.caption * 0.8)
        }
        Text {
          textFormat: Text.PlainText
          text: bubble.time + (bubble.failed ? " · Not sent" : (bubble.pending ? " · Sending…" : ""))
          color: bubble.failed ? view.urgent : view.faint
          font.family: view.fontFamily
          font.pixelSize: Style.font.caption
        }
      }
    }
  }
}
