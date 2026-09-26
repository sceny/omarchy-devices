import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
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

  function cancelNew() {
    newMode = false
    sendingNew = false
    recipients = []
  }

  function refreshSuggestions() {
    suggestions = sms ? sms.candidates(toField.text, 8) : []
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
    cursorTo(threadCursor + dy)
  }

  function cursorTo(i) {
    if (!shown || shown.count === 0) return
    cursorActive = true
    threadCursor = Math.max(0, Math.min(shown.count - 1, i))
    threadList.positionViewAtIndex(threadCursor, ListView.Contain)
  }

  function activateCursor() {
    if (!shown || threadCursor < 0 || threadCursor >= shown.count) return
    openThread(shown.get(threadCursor).tid, true)
  }

  function focusSearch() { searchField.forceActiveFocus(); searchField.selectAll() }
  function setSearch(q) { searchField.text = q }

  // PgUp/PgDn: a screen of the open conversation. The list runs bottom to
  // top, so "up" (older) is towards the end of the content.
  function scrollMessages(pages) {
    if (!openRow || messageList.height <= 0) return
    var step = messageList.height * 0.85 * pages
    var minY = messageList.originY
    var maxY = messageList.originY + Math.max(0, messageList.contentHeight - messageList.height)
    messageList.contentY = Math.max(minY, Math.min(maxY, messageList.contentY + step))
  }

  // `typeHere` puts the cursor in the composer: for the user's own click or
  // Enter, never for a scripted open (IPC), where keystrokes meant for
  // another window could land in a text and Enter would send it.
  function openThread(tid, typeHere) {
    if (!sms) return
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
    if (at >= 0 && at < (shown ? shown.count : 0)) { threadCursor = at; threadList.positionViewAtIndex(at, ListView.Contain) }
    if (typeHere) Qt.callLater(function() { composer.forceActiveFocus() })
  }

  function blurComposer() {
    composer.focus = false
  }

  function focusComposer() {
    if (openRow || newMode) composer.forceActiveFocus()
  }

  // Opening a conversation eases it in: the messages rise into place. The
  // new-message pane comes in from the right instead, as a new page would.
  readonly property string paneKey: (newMode ? "new" : "thread") + ":" + (sms ? sms.openThreadId : -1)
  onPaneKeyChanged: if (newMode || (sms && sms.openThreadId >= 0)) paneReveal.restart()

  property real motion: 1

  ParallelAnimation {
    id: paneReveal
    NumberAnimation { target: convPane; property: "opacity"; from: 0; to: 1; duration: Model.MOTION.inMs * view.motion; easing.type: Easing.OutCubic }
    NumberAnimation { target: paneShift; property: "x"; from: view.newMode ? Style.space(24) : 0; to: 0; duration: Model.MOTION.inMs * view.motion; easing.type: Easing.OutCubic }
    NumberAnimation { target: paneShift; property: "y"; from: view.newMode ? 0 : Style.space(14); to: 0; duration: Model.MOTION.inMs * view.motion; easing.type: Easing.OutCubic }
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

        TextField {
          id: searchField
          Layout.fillWidth: true
          placeholderText: "Search conversations  /"
          foreground: view.foreground
          font.family: view.fontFamily
          onTextChanged: if (view.sms) view.sms.setQuery(text)
          onAccepted: { if (view.shown && view.shown.count > 0) view.openThread(view.shown.get(0).tid, true) }
          Keys.onEscapePressed: { if (text !== "") text = ""; else focus = false }
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
          visible: !!view.sms && !view.sms.ready
          textFormat: Text.PlainText
          wrapMode: Text.WordWrap
          text: view.sms && !view.sms.reachable ? "The device is away. Conversations load when it reconnects." : "Loading conversations…"
          color: view.dim
          font.family: view.fontFamily
          font.pixelSize: Style.font.bodySmall
        }

        ListView {
          id: threadList
          Layout.fillWidth: true
          Layout.fillHeight: true
          clip: true
          model: view.shown
          spacing: Style.space(2)
          boundsBehavior: Flickable.StopAtBounds
          ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

          delegate: ThreadRow {
            width: threadList.width - Style.space(8)
          }
        }

        Text {
          Layout.fillWidth: true
          textFormat: Text.PlainText
          wrapMode: Text.WordWrap
          text: "j/k move · Enter open · / search · u unread · n new · i reply · PgUp/PgDn scroll · Esc back"
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
        visible: !view.openRow && !view.newMode
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
        visible: !!view.openRow || view.newMode
        spacing: Style.space(8)
        transform: Translate { id: paneShift }

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

          TextField {
            id: toField
            Layout.fillWidth: true
            placeholderText: view.recipients.length > 0 ? "Add someone else" : "To: name or number"
            foreground: view.foreground
            font.family: view.fontFamily
            onTextChanged: view.refreshSuggestions()
            onAccepted: view.acceptTo()
            Keys.onEscapePressed: view.cancelNew()
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
              onClicked: view.addRecipient(suggestion.modelData)
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
                text: Model.formatNumber(suggestion.modelData.number)
                color: view.dim
                font.family: view.fontFamily
                font.pixelSize: Style.font.caption
              }
            }
          }
        }

        // ---- Conversation header: who ----
        ColumnLayout {
          Layout.fillWidth: true
          visible: !view.newMode
          spacing: Style.space(1)
          Text {
            Layout.fillWidth: true
            textFormat: Text.PlainText
            text: view.openRow ? view.openRow.title : ""
            color: view.foreground
            font.family: view.fontFamily
            font.pixelSize: Style.font.title
            font.bold: true
            elide: Text.ElideRight
          }
          Text {
            Layout.fillWidth: true
            textFormat: Text.PlainText
            visible: !!view.openRow && view.openRow.addresses !== view.openRow.title
            text: view.openRow ? view.openRow.addresses : ""
            color: view.dim
            font.family: view.fontFamily
            font.pixelSize: Style.font.caption
            elide: Text.ElideRight
          }
        }

        PanelSeparator { Layout.fillWidth: true; foreground: view.foreground; visible: !view.newMode }

        ListView {
          id: messageList
          visible: !view.newMode
          Layout.fillWidth: true
          Layout.fillHeight: true
          clip: true
          model: view.sms ? view.sms.messages : null
          // Newest at the bottom, like every messaging app; older pages grow
          // upwards without moving what is on screen.
          verticalLayoutDirection: ListView.BottomToTop
          spacing: Style.space(6)
          boundsBehavior: Flickable.StopAtBounds
          ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

          function maybeLoadMore() {
            if (!view.sms || !view.sms.hasMore || view.sms.loading) return
            // Near the top, or not enough history yet to fill the pane.
            if (contentHeight < height || visibleArea.yPosition < 0.08) view.sms.loadMore()
          }
          onContentYChanged: maybeLoadMore()
          onCountChanged: Qt.callLater(maybeLoadMore)

          header: Item {
            width: messageList.width
            height: view.sms && view.sms.loading ? Style.space(24) : 0
            Text {
              anchors.centerIn: parent
              visible: parent.height > 0
              textFormat: Text.PlainText
              text: "Loading older messages…"
              color: view.dim
              font.family: view.fontFamily
              font.pixelSize: Style.font.caption
            }
          }

          delegate: Bubble {
            width: messageList.width - Style.space(10)
          }
        }

        RowLayout {
          Layout.fillWidth: true
          spacing: Style.space(6)

          TextField {
            id: composer
            Layout.fillWidth: true
            placeholderText: !view.sms || !view.sms.reachable ? "The device is away"
              : (view.newMode && view.recipients.length === 0 ? "Pick who to send to first" : "Text message")
            enabled: !!view.sms && view.sms.reachable
            foreground: view.foreground
            font.family: view.fontFamily
            onAccepted: view.sendComposer()
            Keys.onEscapePressed: view.blurComposer()
          }
          PanelActionButton {
            iconText: Model.GLYPH.send
            tooltipText: "Send"
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
    hasCursor: view.cursorActive && view.threadCursor === index
    current: isOpen
    foreground: view.foreground
    implicitHeight: rowContent.implicitHeight + Style.space(12)

    MouseArea {
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onEntered: { view.cursorActive = true; view.threadCursor = row.index }
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
                  Text {
                    text: String(file.modelData.mime).indexOf("video/") === 0 ? Model.GLYPH.video
                      : (String(file.modelData.mime).indexOf("audio/") === 0 ? Model.GLYPH.music
                      : (String(file.modelData.mime).indexOf("image/") === 0 ? Model.GLYPH.picture : Model.GLYPH.file))
                    color: view.foreground
                    font.family: view.fontFamily
                    font.pixelSize: Style.font.heading
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

      Text {
        anchors.right: bubble.sent ? parent.right : undefined
        textFormat: Text.PlainText
        text: bubble.time + (bubble.failed ? " · Not sent" : (bubble.pending ? " · Sending…" : ""))
        color: bubble.failed ? view.urgent : view.faint
        font.family: view.fontFamily
        font.pixelSize: Style.font.caption
      }
    }
  }
}
