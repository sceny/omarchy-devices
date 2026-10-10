import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model

// The device's contacts, two panes like messages: the people on the left, the
// open card on the right. Draws ContactsService's models and sends the user's
// intent back out; nothing is kept or edited here, since the device is the
// truth for its contacts.
//
// Keyboard: j/k move through the list, Enter opens a card, / searches, h/l
// cross between the panes, r asks the device again. In the card, Enter runs
// the row's first action, which is never a call: a call leaves this computer
// for the phone, so it waits for a click.
//
// An email, an address and a website open where Omarchy opens them (the mail
// app, the map, the browser): a window the user goes on in, so the panel
// closes behind it, as it does for the contacts app.
Item {
  id: view

  property var contacts: null
  property var device: null
  property var bar: null
  property color foreground: Color.foreground
  property color urgent: Color.urgent
  property string fontFamily: Style.font.family
  property real motion: 1

  readonly property color dim: Qt.darker(foreground, 1.55)
  readonly property color faint: Qt.darker(foreground, 2.2)

  // A result floats over the panel as a toast; nothing here pushes the layout.
  signal reported(string text)
  // Message: the messages view takes it from here with that conversation (or
  // a new message to the number) open. No text is ever written: the message
  // is the user's to type.
  signal messageContact(string number, string who)
  // Call: the phone's dialer on the number, as a call back from a missed call
  // does. The call itself stays the user's tap on the phone.
  signal callContact(string number, string who)
  // Omarchy's own contacts app was opened: it is a window the user goes on
  // in, so the panel closes behind it.
  signal appOpened()

  // ---- what is drawn ----

  readonly property var rows: contacts ? contacts.rows : null
  readonly property bool hasCard: !!contacts && contacts.openId !== ""
  // The cards are on their way: the list shows its shape meanwhile.
  readonly property bool listWaiting: !!contacts && !contacts.ready && (contacts.active || contacts.demo)

  // ---- the keyboard ----
  //
  // One cursor per pane, and it is the list's own sliding highlight (the
  // CursorSurface each list draws as its `highlight`), as messages does it:
  // the rows draw none of their own. A letter is a section of the list, so
  // the highlight covers the person, never their letter.
  property int rowCursor: 0
  property bool cursorActive: false
  // Where the keys go: the list, or the open card (l / → in, h / ← out).
  property string pane: "list"
  readonly property bool inCard: pane === "card" && hasCard
  property int detailCursor: 0
  // The search holds the keyboard: the panel's key catcher stands aside.
  readonly property bool searchFocused: searchField.activeFocus
  readonly property string searchText: searchField.text

  function focusSearch() {
    searchField.forceActiveFocus()
    searchField.selectAll()
  }
  function setSearch(q) { searchField.text = q }

  function refresh() {
    if (!contacts) return
    contacts.refresh()
    if (contacts.demo) return
    view.reported(contacts.reachable ? "Asking " + Model.deviceLabel(device) + " for its contacts"
                                     : "Reading the contacts already here")
  }

  // A detail opened in its app: `kind` is web, map or mail.
  function openDetail(kind, value) {
    if (!contacts || !contacts.openDetail(kind, value)) return
    appOpened()
  }

  function openApp() {
    if (!contacts || !contacts.hasApp) return
    if (!contacts.openApp()) return
    appOpened()
  }

  // The keys across (h/l, ←/→) and up and down on whichever pane has them.
  function moveKey(dx, dy) {
    if (dx > 0) { enterCard(); return }
    if (dx < 0) { pane = "list"; return }
    if (dy === 0) return
    if (inCard) moveDetail(dy)
    else moveCursor(dy)
  }

  function enterCard() {
    if (!hasCard || detailList.count === 0 || pane === "card") return
    pane = "card"
    detailTo(Math.min(detailCursor, detailList.count - 1))
  }

  function moveCursor(dy) {
    if (!rows || rows.count === 0) return
    if (!cursorActive) { cursorActive = true; return }
    // Up from the first person: into search, as / does (and down from search
    // comes back).
    if (dy < 0 && rowCursor === 0) { focusSearch(); return }
    cursorTo(rowCursor + dy)
  }

  function cursorTo(i) {
    if (!rows || rows.count === 0) return
    // The list glides to keep the cursor in sight, at the panel's pace, from
    // where it is to where positionViewAtIndex would put it.
    rowGlide.stop()
    var from = rowList.contentY
    cursorByPointer = false
    cursorActive = true
    rowCursor = Math.max(0, Math.min(rows.count - 1, i))
    rowList.positionViewAtIndex(rowCursor, ListView.Contain)
    glide(rowList, rowGlide, from, rowList.contentY)
  }

  // PgUp/PgDn: the cursor a screen of rows at a time; `pages` > 0 up.
  function pageCursor(pages) {
    if (!rows || rows.count === 0) return
    var rowHeight = rowList.contentHeight / Math.max(1, rowList.count)
    var step = Math.max(1, Math.floor(rowList.height / Math.max(1, rowHeight)) - 1)
    cursorTo((cursorActive ? rowCursor : 0) - pages * step)
  }

  function moveDetail(dy) { detailTo(detailCursor + dy) }
  function detailTo(i) {
    if (detailList.count === 0) return
    detailGlide.stop()
    var from = detailList.contentY
    detailCursor = Math.max(0, Math.min(detailList.count - 1, i))
    detailList.positionViewAtIndex(detailCursor, ListView.Contain)
    glide(detailList, detailGlide, from, detailList.contentY)
  }

  // Scrolling by key: from where the list is to where it goes, at the shared
  // pace; a key held down starts each glide from where the last one got to.
  function glide(list, anim, from, to) {
    anim.stop()
    list.contentY = from
    if (Math.abs(to - from) < 0.5) return
    anim.from = from
    anim.to = to
    anim.start()
  }
  NumberAnimation { id: rowGlide; target: rowList; property: "contentY"; duration: Model.MOTION.inMs * view.motion; easing.type: Easing.OutCubic }
  NumberAnimation { id: detailGlide; target: detailList; property: "contentY"; duration: Model.MOTION.inMs * view.motion; easing.type: Easing.OutCubic }

  // Where the pointer last was on screen, so a row sliding under a still
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
    rowCursor = index
  }

  function activateCursor() {
    if (inCard) { runFirstAction(detailCursor); return }
    if (!rows || rowCursor < 0 || rowCursor >= rows.count) return
    openContact(rows.get(rowCursor).id)
  }

  function openContact(id) {
    if (!contacts) return
    contacts.openContact(id)
    // The keys stay on the list (there is nothing here to type into); the new
    // card's first row is where they land when they cross over.
    detailCursor = 0
    cardReveal.restart()
  }

  // Enter on a detail row: its first action, which is Message on a number,
  // the mail app, the map or the browser on what opens there, and Copy on
  // everything else. Never a call.
  function runFirstAction(i) {
    var row = contacts && i >= 0 && i < detailList.count ? contacts.details.get(i) : null
    if (!row) return
    var actions = String(row.actions)
    if (actions.indexOf("message") >= 0) { messageContact(row.raw, contacts.openTitle); return }
    var open = ["mail", "map", "web"].filter(function(k) { return actions.indexOf(k) >= 0 })[0]
    if (open) { openDetail(open, row.raw); return }
    copyText(row.raw)
  }

  // Esc undoes the innermost thing open, one at a time: the card the keys are
  // in, then the search. False when nothing is open here, so the panel closes
  // contacts.
  function goBack() {
    if (pane === "card") { pane = "list"; return true }
    if (searchField.text !== "") { searchField.text = ""; return true }
    return false
  }

  // A detail goes to the clipboard through wl-copy's stdin, never on its
  // command line: an address or a note is the person's own.
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

  // ---- the shapes and the reveals ----

  // A skeleton only for a wait worth showing: cards that land within a
  // quarter second go straight to their list, with no flash of shapes.
  readonly property int skeletonDelayMs: 250
  property bool listSkeleton: false
  onListWaitingChanged: {
    listSkeleton = false
    if (listWaiting) listSkeletonDelay.restart(); else listSkeletonDelay.stop()
  }
  Timer { id: listSkeletonDelay; interval: view.skeletonDelayMs; onTriggered: view.listSkeleton = true }
  Component.onCompleted: if (listWaiting) listSkeletonDelay.restart()

  // The people ease in when they land, as a conversation's messages do; the
  // title, search and key hints around them stay put.
  readonly property bool listReady: !!contacts && contacts.ready
  onListReadyChanged: if (listReady) listReveal.restart()

  ParallelAnimation {
    id: listReveal
    NumberAnimation { target: rowList; property: "opacity"; from: 0; to: 1; duration: Model.MOTION.inMs * view.motion; easing.type: Easing.OutCubic }
    NumberAnimation { target: rowShift; property: "y"; from: Style.space(14); to: 0; duration: Model.MOTION.inMs * view.motion; easing.type: Easing.OutCubic }
  }

  // A card opens with the same beat: its rows rise into place while the one
  // before them has already gone.
  ParallelAnimation {
    id: cardReveal
    NumberAnimation { target: cardColumn; property: "opacity"; from: 0; to: 1; duration: Model.MOTION.inMs * view.motion; easing.type: Easing.OutCubic }
    NumberAnimation { target: cardShift; property: "y"; from: Style.space(10); to: 0; duration: Model.MOTION.inMs * view.motion; easing.type: Easing.OutCubic }
  }

  RowLayout {
    anchors.fill: parent
    spacing: 0

    // ---- The people ----
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
            text: "CONTACTS"
            foreground: view.foreground
            fontFamily: view.fontFamily
          }
          // This computer's own contacts app, when it has one: the cards here
          // are read-only, so a change is made there or on the device.
          PanelActionButton {
            visible: !!view.contacts && view.contacts.hasApp
            iconText: Model.GLYPH.openIn
            tooltipText: view.contacts && view.contacts.hasApp ? "Open " + view.contacts.appName : ""
            foreground: view.foreground
            fontFamily: view.fontFamily
            onClicked: view.openApp()
          }
          // The device is asked for its cards again only here: it sends one
          // packet per contact, so nothing else asks.
          WaitButton {
            glyph: Model.GLYPH.refresh
            waiting: !!view.contacts && view.contacts.reading
            motion: view.motion
            tooltipText: waiting ? "Reading its contacts" : "Read its contacts again (r)"
            foreground: view.foreground
            fontFamily: view.fontFamily
            enabled: !!view.contacts
            onClicked: view.refresh()
          }
        }

        PanelField {
          id: searchField
          Layout.fillWidth: true
          placeholderText: "Search contacts  /"
          foreground: view.foreground
          font.family: view.fontFamily
          onTextChanged: if (view.contacts) view.contacts.setQuery(text)
          onAccepted: if (view.rows && view.rows.count > 0) view.openContact(view.rows.get(0).id)
          escapeStep: "clear"
          onSteppedOut: focus = false
          Keys.onDownPressed: { focus = false; view.cursorTo(0) }
        }

        // Nothing to show: the device decides whether contacts leave it at
        // all, so this points at that, never at a fault here.
        Text {
          Layout.fillWidth: true
          visible: !!view.contacts && view.contacts.ready && !!view.rows && view.rows.count === 0
          textFormat: Text.PlainText
          wrapMode: Text.WordWrap
          text: view.contacts ? Model.contactsEmpty(view.contacts.listState, view.contacts.query, view.device) : ""
          color: view.dim
          font.family: view.fontFamily
          font.pixelSize: Style.font.bodySmall
        }

        Text {
          Layout.fillWidth: true
          visible: !!view.contacts && view.contacts.lastError !== ""
          textFormat: Text.PlainText
          wrapMode: Text.WordWrap
          text: view.contacts ? view.contacts.lastError : ""
          color: view.urgent
          font.family: view.fontFamily
          font.pixelSize: Style.font.caption
        }

        // The cards on their way: the shape of the list, until the first
        // people land.
        Column {
          Layout.fillWidth: true
          visible: view.listWaiting
          opacity: view.listSkeleton ? 1 : 0
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
                y: faceBone.y + Style.space(4)
                width: (parent.width - x - Style.space(8)) * [0.5, 0.42, 0.6, 0.35, 0.52, 0.45][index]
                height: Style.space(10)
                foreground: view.foreground
                motion: view.motion
              }
              Skeleton {
                x: faceBone.x + faceBone.width + Style.space(10)
                y: faceBone.y + faceBone.height - height - Style.space(4)
                width: (parent.width - x - Style.space(8)) * [0.72, 0.6, 0.8, 0.55, 0.68, 0.62][index]
                height: Style.space(8)
                foreground: view.foreground
                motion: view.motion
              }
            }
          }
        }

        ListView {
          id: rowList
          WheelScroll { flickable: rowList; motion: view.motion }
          Layout.fillWidth: true
          Layout.fillHeight: true
          clip: true
          model: view.rows
          transform: Translate { id: rowShift }
          spacing: Style.space(2)
          boundsBehavior: Flickable.StopAtBounds
          ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

          // A letter heads its group, as the rows say (`first`, `letter`): a
          // section of the list, so the cursor's highlight covers the person
          // and never their letter.
          section.property: "letter"
          section.criteria: ViewSection.FullString
          section.delegate: Text {
            required property string section
            width: rowList.width
            leftPadding: Style.space(8)
            topPadding: Style.space(8)
            bottomPadding: Style.space(2)
            textFormat: Text.PlainText
            text: section
            color: view.dim
            font.family: view.fontFamily
            font.pixelSize: Style.font.caption
            font.bold: true
            font.letterSpacing: 1.0
          }

          // The cursor is one highlight that slides from row to row at the
          // panel's pace when the keys move it, and lands at once where the
          // pointer goes (it never trails the mouse).
          currentIndex: view.rowCursor
          highlightFollowsCurrentItem: true
          highlightMoveDuration: view.cursorByPointer ? 0 : Model.MOTION.inMs * view.motion
          highlightMoveVelocity: -1
          highlightResizeDuration: 0
          highlightResizeVelocity: -1
          highlight: CursorSurface {
            width: rowList.width - Style.space(8)
            hasCursor: true
            foreground: view.foreground
            opacity: view.cursorActive && !view.searchFocused && view.pane === "list" ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: Model.MOTION.inMs * view.motion; easing.type: Easing.OutCubic } }
          }

          delegate: ContactRow {
            width: rowList.width - Style.space(8)
          }
        }

        Text {
          Layout.fillWidth: true
          textFormat: Text.PlainText
          wrapMode: Text.WordWrap
          // The pane is narrow enough for two lines: each hint holds together
          // (no-break spaces), so a line never ends on a bare key.
          text: ["j/k move", "Enter open", "/ search", "h/l side",
                 "r read again", "PgUp/PgDn page", "Esc back"].join(" · ")
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

    // ---- The open card ----
    Item {
      Layout.fillWidth: true
      Layout.fillHeight: true

      Column {
        anchors.centerIn: parent
        visible: !view.hasCard
        spacing: Style.space(6)
        Text {
          anchors.horizontalCenter: parent.horizontalCenter
          text: Model.GLYPH.contacts
          color: view.dim
          font.family: view.fontFamily
          font.pixelSize: Style.font.display
        }
        Text {
          anchors.horizontalCenter: parent.horizontalCenter
          textFormat: Text.PlainText
          text: "Pick a contact"
          color: view.dim
          font.family: view.fontFamily
          font.pixelSize: Style.font.body
        }
      }

      ColumnLayout {
        id: cardColumn
        anchors.fill: parent
        visible: view.hasCard
        transform: Translate { id: cardShift }
        spacing: Style.space(8)

        RowLayout {
          Layout.fillWidth: true
          spacing: Style.space(12)

          // The picture the bridge wrote from the decoded pixels, in its own
          // sandbox: a card's own bytes never reach the shell, and until one
          // is ready the initial stands in its place. A picture is a
          // rounded tile, as a photo and a track's cover are drawn here;
          // the circle is for initials, which it covers to its corners.
          Rectangle {
            id: face
            readonly property string photo: view.contacts ? view.contacts.openPhoto : ""
            readonly property bool shown: photo !== "" && faceImage.status === Image.Ready
            Layout.preferredWidth: Style.space(56)
            Layout.preferredHeight: Style.space(56)
            radius: face.shown ? Style.cornerRadius : width / 2
            color: Style.selectedFillFor(view.foreground, Color.accent)
            clip: true

            Text {
              anchors.centerIn: parent
              visible: !face.shown
              textFormat: Text.PlainText
              text: view.contacts ? view.contacts.openInitial : ""
              color: view.foreground
              font.family: view.fontFamily
              font.pixelSize: Style.font.heading
              font.bold: true
            }
            Image {
              id: faceImage
              anchors.fill: parent
              visible: face.shown
              source: face.photo !== "" ? "file://" + encodeURI(face.photo) : ""
              fillMode: Image.PreserveAspectCrop
              sourceSize.width: Style.space(56) * 2
              sourceSize.height: Style.space(56) * 2
              asynchronous: true
              smooth: true
            }
          }

          ColumnLayout {
            Layout.fillWidth: true
            spacing: Style.space(1)
            Text {
              Layout.fillWidth: true
              textFormat: Text.PlainText
              text: view.contacts ? view.contacts.openTitle : ""
              color: view.foreground
              font.family: view.fontFamily
              font.pixelSize: Style.font.title
              font.bold: true
              elide: Text.ElideRight
            }
            Text {
              Layout.fillWidth: true
              visible: text !== ""
              textFormat: Text.PlainText
              text: view.contacts && view.contacts.openCard ? String(view.contacts.openCard.nickname || "") : ""
              color: view.dim
              font.family: view.fontFamily
              font.pixelSize: Style.font.caption
              elide: Text.ElideRight
            }
          }
        }

        PanelSeparator { Layout.fillWidth: true; foreground: view.foreground }

        ListView {
          id: detailList
          WheelScroll { flickable: detailList; motion: view.motion }
          Layout.fillWidth: true
          Layout.fillHeight: true
          clip: true
          model: view.contacts ? view.contacts.details : null
          spacing: Style.space(2)
          boundsBehavior: Flickable.StopAtBounds
          ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

          // The detail the keys are on: one highlight, shown only while the
          // keys go to this pane.
          currentIndex: view.detailCursor
          highlightFollowsCurrentItem: true
          highlightMoveDuration: Model.MOTION.inMs * view.motion
          highlightMoveVelocity: -1
          highlightResizeDuration: 0
          highlightResizeVelocity: -1
          highlight: CursorSurface {
            width: detailList.width
            hasCursor: true
            foreground: view.foreground
            opacity: view.inCard ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: Model.MOTION.inMs * view.motion; easing.type: Easing.OutCubic } }
          }

          delegate: DetailRow {
            width: detailList.width
          }
        }
      }
    }
  }

  // A person in the list. The row carries no cursor of its own: the list's
  // sliding highlight is the cursor.
  component ContactRow: CursorSurface {
    id: row
    required property var model
    required property int index

    readonly property bool isOpen: !!view.contacts && view.contacts.openId === String(model.id)
    hasCursor: false
    current: isOpen
    foreground: view.foreground
    implicitHeight: rowContent.implicitHeight + Style.space(12)

    MouseArea {
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      // The pointer takes the cursor only when it moves: rows the keys
      // scroll under a resting pointer do not.
      onEntered: view.pointerAt(this, row.index)
      onPositionChanged: view.pointerAt(this, row.index)
      onClicked: view.openContact(row.model.id)
    }

    RowLayout {
      id: rowContent
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      anchors.leftMargin: Style.space(8)
      anchors.rightMargin: Style.space(8)
      spacing: Style.space(10)

      // The list keeps to the initial: a picture per row is a decode per
      // row, and the card already shows the face.
      Rectangle {
        Layout.preferredWidth: Style.space(32)
        Layout.preferredHeight: Style.space(32)
        radius: width / 2
        color: Style.selectedFillFor(view.foreground, Color.accent)
        Text {
          anchors.centerIn: parent
          textFormat: Text.PlainText
          text: row.model.initial
          color: view.foreground
          font.family: view.fontFamily
          font.pixelSize: Style.font.body
          font.bold: true
        }
      }

      ColumnLayout {
        Layout.fillWidth: true
        spacing: Style.space(2)
        Text {
          Layout.fillWidth: true
          textFormat: Text.PlainText
          text: row.model.name
          color: view.foreground
          font.family: view.fontFamily
          font.pixelSize: Style.font.body
          elide: Text.ElideRight
        }
        Text {
          Layout.fillWidth: true
          visible: text !== ""
          textFormat: Text.PlainText
          text: row.model.line
          color: view.dim
          font.family: view.fontFamily
          font.pixelSize: Style.font.bodySmall
          elide: Text.ElideRight
          maximumLineCount: 1
        }
      }
    }
  }

  // One detail of the open card: what it is, what it says, and what can be
  // done with it. The buttons keep their own hover; the row's cursor is the
  // list's highlight.
  component DetailRow: Item {
    id: detail
    required property var model
    required property int index

    readonly property string actions: String(model.actions || "")
    implicitHeight: detailContent.implicitHeight + Style.space(10)

    RowLayout {
      id: detailContent
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      anchors.leftMargin: Style.space(8)
      anchors.rightMargin: Style.space(8)
      spacing: Style.space(10)

      Text {
        Layout.alignment: Qt.AlignTop
        Layout.topMargin: Style.space(2)
        text: detail.model.glyph
        color: view.dim
        font.family: view.fontFamily
        font.pixelSize: Style.font.icon
      }

      ColumnLayout {
        Layout.fillWidth: true
        spacing: Style.space(1)
        Text {
          Layout.fillWidth: true
          textFormat: Text.PlainText
          text: detail.model.label
          color: view.dim
          font.family: view.fontFamily
          font.pixelSize: Style.font.caption
        }
        Text {
          Layout.fillWidth: true
          textFormat: Text.PlainText
          wrapMode: Text.WordWrap
          text: detail.model.value
          color: view.foreground
          font.family: view.fontFamily
          font.pixelSize: Style.font.body
        }
      }

      PanelActionButton {
        visible: detail.actions.indexOf("message") >= 0
        Layout.alignment: Qt.AlignTop
        iconText: Model.GLYPH.callText
        tooltipText: "Message"
        foreground: view.foreground
        fontFamily: view.fontFamily
        onClicked: view.messageContact(detail.model.raw, view.contacts ? view.contacts.openTitle : "")
      }

      // The dialer opens on the device, so it waits for the device: reading
      // a card works while it is away, calling from it does not.
      PanelActionButton {
        visible: detail.actions.indexOf("call") >= 0
        enabled: !!view.contacts && view.contacts.reachable
        Layout.alignment: Qt.AlignTop
        iconText: Model.GLYPH.callBack
        tooltipText: "Open the dialer on " + Model.deviceLabel(view.device)
        foreground: view.foreground
        fontFamily: view.fontFamily
        onClicked: view.callContact(detail.model.raw, view.contacts ? view.contacts.openTitle : "")
      }

      PanelActionButton {
        visible: detail.actions.indexOf("mail") >= 0
        Layout.alignment: Qt.AlignTop
        iconText: Model.GLYPH.mail
        tooltipText: "Write an email"
        foreground: view.foreground
        fontFamily: view.fontFamily
        onClicked: view.openDetail("mail", detail.model.raw)
      }

      PanelActionButton {
        visible: detail.actions.indexOf("map") >= 0
        Layout.alignment: Qt.AlignTop
        iconText: Model.GLYPH.map
        tooltipText: "Show on the map"
        foreground: view.foreground
        fontFamily: view.fontFamily
        onClicked: view.openDetail("map", detail.model.raw)
      }

      PanelActionButton {
        visible: detail.actions.indexOf("web") >= 0
        Layout.alignment: Qt.AlignTop
        iconText: Model.GLYPH.web
        tooltipText: "Open in the browser"
        foreground: view.foreground
        fontFamily: view.fontFamily
        onClicked: view.openDetail("web", detail.model.raw)
      }

      PanelActionButton {
        visible: detail.actions.indexOf("copy") >= 0
        Layout.alignment: Qt.AlignTop
        iconText: Model.GLYPH.copy
        tooltipText: "Copy"
        foreground: view.foreground
        fontFamily: view.fontFamily
        onClicked: view.copyText(detail.model.raw)
      }
    }
  }
}
