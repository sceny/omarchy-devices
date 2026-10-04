import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Ui
import "Model.js" as Model

// All apps: every app of the device (the system's own too), each opening in
// a window here. A search, the recently opened first, then A to Z. The
// panel's keys move the cursor here (moveKey, activate); `/` goes to the
// search, `p` pins the app under the cursor.
Item {
  id: view

  property var apps: []              // the device's apps (Service.appsOf)
  property var pinned: []            // packages kept in the Apps section
  property string listState: ""      // the list's: "" (reading), "ready", or the screen's state
  property string deviceName: ""
  property var isWorking: function(app) { return false }
  property Item glide: null
  property bool cursorActive: false
  property real motion: 1
  property color foreground: Color.foreground
  property string fontFamily: Style.font.family

  signal openRequested(var app)
  signal pinRequested(var app, bool on)
  signal refreshRequested()
  signal hovered()

  readonly property color dim: Qt.darker(foreground, 1.55)
  readonly property bool searchFocused: searchField.activeFocus
  readonly property var page: Model.appsForPage(apps, searchField.text)
  // Where the keys can go: the recent row, then the list.
  readonly property var stops: page.recent.concat(page.all)
  property int cursor: 0
  // As many columns as fit tiles of about 84 px, spread over the width.
  readonly property real gap: Style.space(6)
  readonly property int columns: Math.max(1, Math.floor((width + gap) / (Style.space(84) + gap)))
  readonly property real cellWidth: (width - gap * (columns - 1)) / columns

  implicitHeight: content.implicitHeight

  function focusSearch() { searchField.forceActiveFocus() }
  function clampCursor() { cursor = Math.max(0, Math.min(stops.length - 1, cursor)) }
  onStopsChanged: clampCursor()

  // The cursor moves in the row it is in: the recent row is a row of its own.
  function moveKey(dx, dy) {
    if (stops.length === 0) return
    var r = page.recent.length
    if (dx !== 0) { cursor = Math.max(0, Math.min(stops.length - 1, cursor + dx)); return }
    if (cursor < r) {
      if (dy > 0) cursor = r + Math.min(cursor, page.all.length - 1)
      return
    }
    var i = cursor - r
    var next = i + dy * columns
    if (next < 0) { cursor = r > 0 ? Math.min(r - 1, i % columns) : cursor; return }
    if (next >= page.all.length) {
      // The last row is short: the last app, unless already in that row.
      if (Math.floor(i / columns) < Math.floor((page.all.length - 1) / columns)) cursor = r + page.all.length - 1
      return
    }
    cursor = r + next
  }
  function activate() {
    var app = stops[cursor]
    if (app) openRequested(app)
  }
  function togglePin() {
    var app = stops[cursor]
    if (app) pinRequested(app, pinned.indexOf(app.package) < 0)
  }
  // Esc: the search's own step first (PanelField), then the page goes back.
  function goBack() {
    if (searchField.text !== "") { searchField.text = ""; return true }
    return false
  }
  function reset() {
    searchField.text = ""
    cursor = 0
  }

  ColumnLayout {
    id: content
    width: parent.width
    spacing: Style.space(10)

    RowLayout {
      Layout.fillWidth: true
      spacing: Style.space(6)

      PanelField {
        id: searchField
        Layout.fillWidth: true
        placeholderText: "Search apps  /"
        foreground: view.foreground
        font.family: view.fontFamily
        escapeStep: "clear"
        onSteppedOut: focus = false
        onAccepted: { if (view.page.all.length > 0) view.openRequested(view.page.all[0]) }
        onTextChanged: view.cursor = 0
        Keys.onDownPressed: { focus = false; view.cursor = 0 }
      }
      PanelActionButton {
        iconText: Model.GLYPH.refresh
        tooltipText: "Read the apps of " + view.deviceName + " again"
        foreground: view.foreground
        fontFamily: view.fontFamily
        onClicked: view.refreshRequested()
      }
    }

    // Reading the list: a few seconds the first time (then a day in the cache).
    Row {
      visible: view.apps.length === 0
      spacing: Style.space(8)
      WaitRing {
        anchors.verticalCenter: parent.verticalCenter
        running: parent.visible && view.listState === ""
        visible: view.listState === ""
        motion: view.motion
        color: view.foreground
        size: Math.round(Style.font.body * 0.9)
      }
      Text {
        anchors.verticalCenter: parent.verticalCenter
        textFormat: Text.PlainText
        text: view.listState === "" ? "Reading the apps of " + view.deviceName + "…"
          : view.deviceName + " cannot be reached: its apps show once it can"
        color: view.dim
        font.family: view.fontFamily
        font.pixelSize: Style.font.bodySmall
      }
    }

    Text {
      visible: view.apps.length > 0 && view.page.all.length === 0
      textFormat: Text.PlainText
      text: "No app matches."
      color: view.dim
      font.family: view.fontFamily
      font.pixelSize: Style.font.bodySmall
    }

    PanelSectionHeader {
      visible: view.page.recent.length > 0
      Layout.fillWidth: true
      text: "RECENT"
      foreground: view.foreground
      fontFamily: view.fontFamily
    }
    Flow {
      visible: view.page.recent.length > 0
      Layout.fillWidth: true
      spacing: view.gap
      Repeater {
        model: view.page.recent
        AppTile {
          required property var modelData
          required property int index
          width: view.cellWidth
          app: modelData
          pinned: view.pinned.indexOf(modelData.package) >= 0
          working: view.isWorking(modelData)
          here: view.cursorActive && view.cursor === index
          glide: view.glide
          motion: view.motion
          foreground: view.foreground
          fontFamily: view.fontFamily
          onActivated: view.openRequested(modelData)
          onPinToggled: view.pinRequested(modelData, !pinned)
          onHovered: { view.cursor = index; view.hovered() }
        }
      }
    }

    PanelSectionHeader {
      visible: view.page.all.length > 0
      Layout.fillWidth: true
      text: searchField.text.trim() !== "" ? "MATCHES" : "ALL APPS · " + view.page.all.length
      foreground: view.foreground
      fontFamily: view.fontFamily
    }
    Flow {
      Layout.fillWidth: true
      spacing: view.gap
      Repeater {
        model: view.page.all
        AppTile {
          required property var modelData
          required property int index
          width: view.cellWidth
          app: modelData
          pinned: view.pinned.indexOf(modelData.package) >= 0
          working: view.isWorking(modelData)
          here: view.cursorActive && view.cursor === view.page.recent.length + index
          glide: view.glide
          motion: view.motion
          foreground: view.foreground
          fontFamily: view.fontFamily
          onActivated: view.openRequested(modelData)
          onPinToggled: view.pinRequested(modelData, !pinned)
          onHovered: { view.cursor = view.page.recent.length + index; view.hovered() }
        }
      }
    }

    // Said plainly, not found out later.
    Text {
      visible: view.apps.length > 0
      Layout.fillWidth: true
      Layout.topMargin: Style.space(4)
      textFormat: Text.PlainText
      wrapMode: Text.WordWrap
      text: "Each app opens in a window of its own; " + view.deviceName + "'s own screen stays free. An app that protects its screen (many banks) shows black."
      color: view.dim
      font.family: view.fontFamily
      font.pixelSize: Style.font.caption
    }
  }
}
