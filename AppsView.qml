import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Ui
import "Model.js" as Model

// All apps: every app of the device (the system's own too), each opening in
// a window here. PINNED leads, always there as a place to drag an app to
// (AppPinRow), then a search, the recently opened, then A to Z. The panel's
// keys move the cursor here (moveKey, activate); `/` goes to the search,
// `p` pins the app under the cursor, Shift+H / Shift+L move a pinned one.
Item {
  id: view

  property var apps: []              // the device's apps (Service.appsOf)
  property var pinned: []            // packages kept in the Apps section
  property string listState: ""      // the list's: "" (reading), "ready", or the screen's state
  property string deviceName: ""
  property bool reading: false        // the list or its icons are being read
  property var isWorking: function(app) { return false }
  property Item glide: null
  property bool cursorActive: false
  property real motion: 1
  property bool animate: true
  property color foreground: Color.foreground
  property string fontFamily: Style.font.family

  signal openRequested(var app)
  signal pinRequested(var app, bool on)
  signal pinAtRequested(var app, int at)
  signal pinMoved(int from, int to)
  signal forgetRequested(var app)
  signal refreshRequested()
  signal hovered()

  readonly property color dim: Qt.darker(foreground, 1.55)
  readonly property bool searchFocused: searchField.activeFocus
  readonly property var page: Model.appsForPage(apps, searchField.text)
  readonly property var pinnedApps: Model.pinnedAppsOf(apps, pinned)
  // Where the keys can go: PINNED, the recent row, then the list.
  readonly property var stops: pinnedApps.concat(page.recent, page.all)
  readonly property var cursorRows: Model.cursorRows([pinnedApps.length, page.recent.length, page.all.length], columns)
  readonly property int recentBase: pinnedApps.length
  readonly property int allBase: pinnedApps.length + page.recent.length
  property int cursor: 0
  // As many columns as fit tiles of about 84 px, spread over the width.
  readonly property real gap: Style.space(6)
  readonly property int columns: Math.max(1, Math.floor((width + gap) / (Style.space(84) + gap)))
  readonly property real cellWidth: (width - gap * (columns - 1)) / columns

  implicitHeight: content.implicitHeight

  function focusSearch() { searchField.forceActiveFocus() }
  function clampCursor() { cursor = Math.max(0, Math.min(stops.length - 1, cursor)) }
  onStopsChanged: clampCursor()

  // The cursor moves in its row; PINNED, RECENT and the list are rows of
  // their own.
  function moveKey(dx, dy) {
    if (stops.length === 0) return
    var t = Model.cursorStep(cursorRows, cursor, dx, dy)
    if (t >= 0) cursor = t
  }
  // Shift+H / Shift+L on a pinned app: it moves among the pinned.
  function movePinnedKey(delta) {
    if (cursor >= pinnedApps.length) return
    pinRow.step(cursor, delta)
    cursor = Math.max(0, Math.min(pinnedApps.length - 1, cursor + delta))
  }
  function activate() {
    var app = stops[cursor]
    if (app) openRequested(app)
  }
  // x: a recent app under the cursor leaves the recent ones.
  function forget() {
    var app = stops[cursor]
    if (app && cursor >= recentBase && cursor < allBase) forgetRequested(app)
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
      // The ring while the list or its icons are read; no second read meanwhile.
      WaitButton {
        glyph: Model.GLYPH.refresh
        waiting: view.reading
        motion: view.motion
        tooltipText: view.reading ? "Reading the apps of " + view.deviceName + "…" : "Read the apps of " + view.deviceName + " again"
        foreground: view.foreground
        fontFamily: view.fontFamily
        onClicked: if (!view.reading) view.refreshRequested()
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
      visible: view.apps.length > 0
      Layout.fillWidth: true
      text: "PINNED"
      foreground: view.foreground
      fontFamily: view.fontFamily
    }
    AppPinRow {
      id: pinRow
      visible: view.apps.length > 0
      Layout.fillWidth: true
      Layout.preferredHeight: implicitHeight
      z: moving ? 2 : 0
      apps: view.pinnedApps
      columns: view.columns
      gap: view.gap
      showEmpty: true
      animate: view.animate
      cursorAt: view.cursorActive ? view.cursor : -1
      glide: view.glide
      motion: view.motion
      isWorking: view.isWorking
      foreground: view.foreground
      fontFamily: view.fontFamily
      onActivated: function(app) { view.openRequested(app) }
      onHovered: function(i) { view.cursor = i; view.hovered() }
      onReordered: function(a, b) { view.pinMoved(a, b) }
      onPinRequested: function(app, at) { view.pinAtRequested(app, at) }
      onUnpinRequested: function(app) { view.pinRequested(app, false) }
    }

    PanelSectionHeader {
      visible: view.page.recent.length > 0
      Layout.fillWidth: true
      text: "RECENT"
      foreground: view.foreground
      fontFamily: view.fontFamily
    }
    Grid {
      visible: view.page.recent.length > 0
      Layout.fillWidth: true
      columns: view.columns
      columnSpacing: view.gap
      rowSpacing: view.gap
      // One that goes (✕): the rest slide over.
      move: Transition {
        enabled: view.animate
        NumberAnimation { properties: "x,y"; duration: Model.MOTION.inMs * view.motion; easing.type: Easing.OutCubic }
      }
      KeyedApps { id: recentModel; apps: view.page.recent }
      Repeater {
        model: recentModel
        AppTile {
          id: recentTile
          required property string json
          required property int index
          readonly property var modelData: JSON.parse(json)
          width: view.cellWidth
          z: dragging ? 10 : 0
          transform: Translate {
            x: recentTile.followX
            y: recentTile.followY
            Behavior on x { enabled: !recentTile.dragging; NumberAnimation { duration: Model.MOTION.inMs * view.motion; easing.type: Easing.OutCubic } }
            Behavior on y { enabled: !recentTile.dragging; NumberAnimation { duration: Model.MOTION.inMs * view.motion; easing.type: Easing.OutCubic } }
          }
          dragEnabled: true
          followsPointer: true
          onDragMoved: function(dx, dy, at) { pinRow.externalMove(modelData, at) }
          onDragEnded: function(at) { pinRow.externalDrop(modelData, at) }
          app: modelData
          pinned: view.pinned.indexOf(modelData.package) >= 0
          working: view.isWorking(modelData)
          here: view.cursorActive && view.cursor === view.recentBase + index
          glide: view.glide
          motion: view.motion
          foreground: view.foreground
          fontFamily: view.fontFamily
          onActivated: view.openRequested(modelData)
          onPinToggled: view.pinRequested(modelData, !pinned)
          canForget: true
          onForgetRequested: view.forgetRequested(modelData)
          onHovered: { view.cursor = view.recentBase + index; view.hovered() }
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
    Grid {
      Layout.fillWidth: true
      columns: view.columns
      columnSpacing: view.gap
      rowSpacing: view.gap
      Repeater {
        model: view.page.all
        AppTile {
          id: allTile
          required property var modelData
          required property int index
          width: view.cellWidth
          z: dragging ? 10 : 0
          transform: Translate {
            x: allTile.followX
            y: allTile.followY
            Behavior on x { enabled: !allTile.dragging; NumberAnimation { duration: Model.MOTION.inMs * view.motion; easing.type: Easing.OutCubic } }
            Behavior on y { enabled: !allTile.dragging; NumberAnimation { duration: Model.MOTION.inMs * view.motion; easing.type: Easing.OutCubic } }
          }
          dragEnabled: true
          followsPointer: true
          onDragMoved: function(dx, dy, at) { pinRow.externalMove(modelData, at) }
          onDragEnded: function(at) { pinRow.externalDrop(modelData, at) }
          app: modelData
          pinned: view.pinned.indexOf(modelData.package) >= 0
          working: view.isWorking(modelData)
          here: view.cursorActive && view.cursor === view.allBase + index
          glide: view.glide
          motion: view.motion
          foreground: view.foreground
          fontFamily: view.fontFamily
          onActivated: view.openRequested(modelData)
          onPinToggled: view.pinRequested(modelData, !pinned)
          onHovered: { view.cursor = view.allBase + index; view.hovered() }
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
