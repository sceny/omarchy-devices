import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Ui
import "Model.js" as Model

// The phone panel's settings page, shown in place of the phone view.
//
// Presentation only: it draws `rows` (Model.settingsPageRows, one flat list
// so the keyboard cursor is a single index) and emits intent. Panel.qml owns
// the cursor, the scope (the device list, one device's page, the defaults)
// and writes shell.json.
Column {
  id: root

  property var rows: []
  property int cursorIndex: -1
  property bool shortcutsShown: true
  property var setupChecks: []
  property var setupFixing: ({})
  // Folding, like the main page's sections, and remembered the same way.
  property var collapsed: ({})
  property var flags: ({})
  property var order: []
  property var sectionOrder: []
  property var barIndicators: []
  property bool batteryLowOnly: true
  // Many devices: what the page edits ("root", "device", "defaults"), which
  // of its settings the device changed, the icon picker, Unpair armed.
  property string scopeKind: "root"
  property var custom: ({})
  property bool iconPicking: false
  property bool unpairArmed: false
  property string deviceName: ""
  property var phone: null
  // The panel's own background: a dragged row is painted solid over it, so
  // it never shows the row it passes over through itself.
  property color panelBackground: Color.background
  property real motion: 1
  property bool animate: true
  function isFolded(key) { return collapsed[key] === true }
  property color foreground: Color.foreground
  property string fontFamily: Style.font.family

  signal activated(int index)
  signal moveRequested(string key, int delta)
  signal sectionMoveRequested(string section, int delta)
  signal barMoveRequested(string key, int delta)
  signal hovered(int index)
  signal fixRequested(string what)
  signal foldToggled(string key)
  signal rejectRequested(string id)
  signal deviceMoveRequested(string id, int delta)
  signal nicknameSet(string text)
  signal iconSet(string code)
  signal barPlaceSet(string place)
  signal nicknameFocus(bool focused)

  readonly property color dim: Qt.darker(foreground, 1.55)

  function firstIndex(kind) {
    for (var i = 0; i < rows.length; i++) if (rows[i].kind === kind) return i
    return -1
  }
  function hasKind(kinds) {
    for (var i = 0; i < rows.length; i++) if (kinds.indexOf(rows[i].kind) >= 0) return true
    return false
  }
  readonly property bool hasGroups: firstIndex("layout") >= 0
  readonly property bool hasList: hasKind(["device", "request", "available"])
  readonly property bool hasIdentity: firstIndex("nickname") >= 0
  function groupTitle(title, group) {
    return scopeKind === "device" && Model.groupCustom(custom, group) ? title + " · CUSTOM" : title
  }
  function devicesSummary() {
    var n = 0, asking = 0
    for (var i = 0; i < rows.length; i++) {
      if (rows[i].kind === "device") n++
      if (rows[i].kind === "request") asking++
    }
    var line = n === 1 ? "1 device" : n + " devices"
    return asking > 0 ? line + " · " + asking + (asking === 1 ? " wants to pair" : " want to pair") : line
  }

  // The user's click or Enter on the Nickname row only (never scripted).
  function editNickname() { if (nicknameField) nicknameField.forceActiveFocus() }
  property var nicknameField: null

  spacing: Style.space(6)

  // ---- Devices: every device, in order; asking to pair; in reach ----
  FoldToggle {
    visible: root.hasList
    width: root.width
    title: "DEVICES"
    summary: root.devicesSummary()
    folded: root.isFolded("devicesList")
    foreground: root.foreground
    fontFamily: root.fontFamily
    motion: root.motion
    animate: root.animate
    onToggled: root.foldToggled("devicesList")
  }

  FoldBody {
    visible: root.hasList
    open: !root.isFolded("devicesList")
    motion: root.motion
    animate: root.animate
    spacing: Style.space(4)

      Text {
        visible: root.firstIndex("device") >= 0
        textFormat: Text.PlainText
        width: root.width
        wrapMode: Text.WordWrap
        text: "The first opens when the panel does and always shows in the bar. Shift+K and Shift+J move the selected one."
        color: root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
      }

      Repeater {
        model: root.rows
        ListRow {
          required property var modelData
          required property int index
          visible: modelData.kind === "device" || modelData.kind === "request" || modelData.kind === "available"
          width: root.width
          row: modelData
          rowIndex: index
        }
      }
  }

  // ---- This device: its name and icon, and on its page where it shows ----
  Item { visible: root.hasIdentity && root.scopeKind === "root"; width: 1; height: Style.space(6) }
  PanelSeparator { visible: root.hasIdentity && root.scopeKind === "root"; foreground: root.foreground }

  FoldToggle {
    visible: root.hasIdentity
    width: root.width
    title: root.scopeKind === "device" ? "DEVICE" : "THIS DEVICE"
    summary: root.deviceName
    folded: root.isFolded("identity")
    foreground: root.foreground
    fontFamily: root.fontFamily
    motion: root.motion
    animate: root.animate
    onToggled: root.foldToggled("identity")
  }

  FoldBody {
    visible: root.hasIdentity
    open: !root.isFolded("identity")
    motion: root.motion
    animate: root.animate
    spacing: Style.space(4)

      Repeater {
        model: root.rows
        IdentityRow {
          required property var modelData
          required property int index
          visible: ["nickname", "icon", "barPlace", "showInPanel"].indexOf(modelData.kind) >= 0
          width: root.width
          row: modelData
          rowIndex: index
        }
      }
  }

  // ---- Defaults for all devices (the list's page) ----
  Repeater {
    model: root.rows
    ListRow {
      required property var modelData
      required property int index
      visible: modelData.kind === "defaults"
      width: root.width
      row: modelData
      rowIndex: index
    }
  }

  Item { visible: root.hasGroups && (root.hasIdentity || root.hasList); width: 1; height: Style.space(6) }
  PanelSeparator { visible: root.hasGroups && (root.hasIdentity || root.hasList); foreground: root.foreground }

  Column {
    id: groupsBox
    visible: root.hasGroups
    width: root.width
    spacing: Style.space(6)

    // ---- Layout ----
    FoldToggle {
      width: root.width
      title: root.groupTitle("LAYOUT", "layout")
      summary: Model.layoutSummary(root.flags, root.sectionOrder)
      folded: root.isFolded("layout")
      foreground: root.foreground
      fontFamily: root.fontFamily
      motion: root.motion
      animate: root.animate
      onToggled: root.foldToggled("layout")
    }

    FoldBody {
      open: !root.isFolded("layout")
      motion: root.motion
      animate: root.animate
      spacing: Style.space(6)

        Text {
          textFormat: Text.PlainText
          width: root.width
          wrapMode: Text.WordWrap
          text: "The sections under the header, in this order. Shift+K and Shift+J move the selected one."
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
        }

        Repeater {
          model: root.rows
          LayoutRow {
            required property var modelData
            required property int index
            visible: modelData.kind === "layout"
            width: root.width
            row: modelData
            rowIndex: index
          }
        }

    }

    Item { width: 1; height: Style.space(6) }
    PanelSeparator { foreground: root.foreground }

    // ---- Bar: what the pill shows beside the device glyph ----
    FoldToggle {
      width: root.width
      title: root.groupTitle("BAR", "bar")
      summary: Model.barSummary(root.barIndicators, root.batteryLowOnly)
      folded: root.isFolded("bar")
      foreground: root.foreground
      fontFamily: root.fontFamily
      motion: root.motion
      animate: root.animate
      onToggled: root.foldToggled("bar")
    }

    FoldBody {
      open: !root.isFolded("bar")
      motion: root.motion
      animate: root.animate
      spacing: Style.space(6)

        Text {
          textFormat: Text.PlainText
          width: root.width
          wrapMode: Text.WordWrap
          text: "Ticked ones show beside the device glyph in the bar, in this order. Shift+K and Shift+J move the selected one."
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
        }

        Repeater {
          model: root.rows
          ShortcutRow {
            required property var modelData
            required property int index
            visible: modelData.kind === "bar"
            width: root.width
            row: modelData
            rowIndex: index
          }
        }

        Repeater {
          model: root.rows
          LayoutRow {
            required property var modelData
            required property int index
            visible: modelData.kind === "barFlag"
            width: root.width
            row: modelData
            rowIndex: index
          }
        }
    }

    Item { width: 1; height: Style.space(6) }
    PanelSeparator { foreground: root.foreground }

    // ---- Shortcuts ----
    FoldToggle {
      width: root.width
      title: root.groupTitle("SHORTCUTS", "shortcuts")
      summary: Model.shortcutsSummary(root.order)
      folded: root.isFolded("shortcuts")
      foreground: root.foreground
      fontFamily: root.fontFamily
      motion: root.motion
      animate: root.animate
      onToggled: root.foldToggled("shortcuts")
    }

    FoldBody {
      open: !root.isFolded("shortcuts")
      motion: root.motion
      animate: root.animate
      spacing: Style.space(6)

        Text {
          textFormat: Text.PlainText
          width: root.width
          wrapMode: Text.WordWrap
          text: root.shortcutsShown
            ? "Ticked ones show under the header, four per row, in this order. Shift+K and Shift+J move the selected one."
            : "The shortcuts row is off in Layout. What you pick here shows once it is on again."
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
        }

        Repeater {
          model: root.rows
          ShortcutRow {
            required property var modelData
            required property int index
            visible: modelData.kind === "shortcut"
            width: root.width
            row: modelData
            rowIndex: index
          }
        }

    }

    Repeater {
      model: root.rows
      ListRow {
        required property var modelData
        required property int index
        visible: modelData.kind === "resetGroup"
        width: root.width
        row: modelData
        rowIndex: index
      }
    }
  }

  Item { visible: root.scopeKind === "root"; width: 1; height: Style.space(6) }
  PanelSeparator { visible: root.scopeKind === "root"; foreground: root.foreground }

  // ---- Add a device: the steps on it (pairing starts there) ----
  FoldToggle {
    visible: root.scopeKind === "root"
    width: root.width
    title: "ADD A DEVICE"
    summary: "Install KDE Connect on it, same Wi-Fi, pair from it"
    folded: root.collapsed["addDevice"] !== false
    foreground: root.foreground
    fontFamily: root.fontFamily
    motion: root.motion
    animate: root.animate
    onToggled: root.foldToggled("addDevice")
  }

  FoldBody {
    visible: root.scopeKind === "root"
    open: root.collapsed["addDevice"] === false
    motion: root.motion
    animate: root.animate
    spacing: Style.space(6)

      SetupChecks {
        width: root.width
        checks: []
        showPhoneSteps: true
        foreground: root.foreground
        urgent: Color.urgent
        fontFamily: root.fontFamily
      }
  }

  Item { visible: root.scopeKind === "root"; width: 1; height: Style.space(6) }
  PanelSeparator { visible: root.scopeKind === "root"; foreground: root.foreground }

  // ---- Setup ----
  FoldToggle {
    visible: root.scopeKind === "root"
    width: root.width
    title: "SETUP"
    summary: Model.setupSummary(root.setupChecks)
    folded: root.isFolded("setup")
    foreground: root.foreground
    fontFamily: root.fontFamily
    motion: root.motion
    animate: root.animate
    onToggled: root.foldToggled("setup")
  }

  FoldBody {
    visible: root.scopeKind === "root"
    open: !root.isFolded("setup")
    motion: root.motion
    animate: root.animate
    spacing: Style.space(6)

      SetupChecks {
        width: root.width
        checks: root.setupChecks
        busyFixes: root.setupFixing
        showPhoneSteps: true
        foreground: root.foreground
        urgent: Color.urgent
        fontFamily: root.fontFamily
        onFixRequested: function(what) { root.fixRequested(what) }
      }
  }

  Item { width: 1; height: Style.space(2) }

  Row {
    spacing: Style.space(8)

    Button {
      readonly property int rowIndex: root.firstIndex("unpair")
      visible: rowIndex >= 0
      text: root.unpairArmed ? "Unpair? Again to confirm" : "Unpair"
      iconText: Model.GLYPH.close
      tooltipText: "Forget this device; pair again from it to come back"
      foreground: root.unpairArmed ? Color.urgent : root.foreground
      fontFamily: root.fontFamily
      bordered: true
      hasCursor: root.cursorIndex === rowIndex
      onHovered: function(on) { if (on) root.hovered(rowIndex) }
      onClicked: root.activated(rowIndex)
    }

    Button {
      readonly property int rowIndex: root.firstIndex("reset")
      visible: rowIndex >= 0
      text: "Reset shortcuts"
      iconText: Model.GLYPH.reset
      tooltipText: "Back to Ring, Send files, Clipboard and Messages"
      foreground: root.foreground
      fontFamily: root.fontFamily
      bordered: true
      hasCursor: root.cursorIndex === rowIndex
      onHovered: function(on) { if (on) root.hovered(rowIndex) }
      onClicked: root.activated(rowIndex)
    }

    Button {
      readonly property int rowIndex: root.firstIndex("kdeconnect")
      visible: rowIndex >= 0
      text: "KDE Connect settings"
      iconText: Model.GLYPH.phoneCog
      tooltipText: "Pairing, device permissions and KDE Connect's own plugins"
      foreground: root.foreground
      fontFamily: root.fontFamily
      bordered: true
      hasCursor: root.cursorIndex === rowIndex
      onHovered: function(on) { if (on) root.hovered(rowIndex) }
      onClicked: root.activated(rowIndex)
    }
  }

  // ---- Drag to reorder ----
  // The drag in progress, shared by the rows of its order: while a row is
  // dragged, the rows between its place and where it would land slide over
  // by one row (animated), so the gap shows where it goes. On release it
  // glides into the gap, and only then is the new order written; the page
  // is rebuilt in the places already on screen, so nothing jumps.
  property string dragKind: ""
  property int dragPos: -1
  property int dragSteps: 0
  property real dragPitch: 0
  // True for the instant the order is written: shifts drop to 0 without
  // animating, in the same frame the rows are rebuilt in their new places.
  property bool dragCommitting: false

  // How far a row of `kind` at `pos` makes room for the dragged one.
  function rowShift(kind, pos) {
    if (dragKind !== kind || pos < 0 || pos === dragPos) return 0
    if (dragSteps > 0 && pos > dragPos && pos <= dragPos + dragSteps) return -dragPitch
    if (dragSteps < 0 && pos < dragPos && pos >= dragPos + dragSteps) return dragPitch
    return 0
  }

  // A row's grip: drag it to move the row (its arrows use the same glide).
  component Grip: Text {
    id: grip
    property Item row: null
    property string kind: ""
    property int pos: 0
    property int count: 1
    property real gap: Style.space(6)
    property real dragY: 0
    readonly property real pitch: row ? row.height + gap : 1
    readonly property int steps: Math.max(-pos, Math.min(count - 1 - pos, Math.round(dragY / pitch)))
    // Held, or gliding into place after the release.
    readonly property bool active: area.pressed || settle.running
    property int landing: 0
    signal moved(int delta)

    text: Model.GLYPH.grip
    color: area.containsMouse || area.pressed ? root.foreground : root.dim
    font.family: root.fontFamily
    font.pixelSize: Style.font.icon
    Layout.alignment: Qt.AlignVCenter

    onStepsChanged: if (area.pressed) root.dragSteps = steps

    function begin() {
      root.dragKind = kind
      root.dragPos = pos
      root.dragPitch = pitch
      root.dragSteps = 0
    }
    // Glides to `delta` places away, then writes the move.
    function glideTo(delta) {
      landing = Math.max(-pos, Math.min(count - 1 - pos, delta))
      root.dragSteps = landing
      settle.from = dragY
      settle.to = landing * pitch
      settle.restart()
    }
    // The arrows: the same glide, from where the row is.
    function animateMove(delta) {
      if (active || delta === 0) return
      begin()
      dragY = 0
      glideTo(delta)
    }

    NumberAnimation {
      id: settle
      target: grip
      property: "dragY"
      duration: Model.MOTION.inMs * root.motion
      easing.type: Easing.OutCubic
      onFinished: {
        var d = grip.landing
        root.dragCommitting = true
        root.dragKind = ""
        grip.dragY = 0
        // Rebuilds the rows (this grip with them): the last use of it.
        if (d !== 0) grip.moved(d)
        root.dragCommitting = false
      }
    }

    MouseArea {
      id: area
      anchors.fill: parent
      anchors.margins: -Style.space(4)
      hoverEnabled: true
      // The page's own scrolling does not take the drag away.
      preventStealing: true
      cursorShape: pressed ? Qt.ClosedHandCursor : Qt.OpenHandCursor
      property real startY: 0
      // Scene coordinates: the pointer's place, however far the row moved.
      onPressed: function(m) { if (settle.running) return; startY = mapToItem(null, m.x, m.y).y; grip.dragY = 0; grip.begin() }
      onPositionChanged: function(m) { if (pressed) grip.dragY = mapToItem(null, m.x, m.y).y - startY }
      onReleased: grip.glideTo(grip.steps)
      onCanceled: grip.glideTo(0)
    }
  }

  // The place a row takes while an order is being dragged: the dragged row
  // follows the pointer (no animation), the others slide aside (animated).
  component DragShift: Translate {
    property var grip: null
    property string kind: ""
    property int pos: -1
    y: grip && grip.active ? grip.dragY : root.rowShift(kind, pos)
    Behavior on y {
      enabled: !root.dragCommitting && !!grip && !grip.active
      NumberAnimation { duration: Model.MOTION.inMs * root.motion; easing.type: Easing.OutCubic }
    }
  }

  // A row of the device list (a device, one asking to pair, one in reach),
  // the Defaults row, or a group's "use the defaults".
  component ListRow: CursorSurface {
    id: listRow
    property var row: ({})
    property int rowIndex: -1
    readonly property bool working: !!root.phone && (root.phone.isBusy("pair:" + row.id) || root.phone.isBusy("accept:" + row.id) || root.phone.isBusy("reject:" + row.id))

    hasCursor: root.cursorIndex === rowIndex
    foreground: root.foreground
    implicitHeight: listContent.implicitHeight + Style.space(12)
    transform: DragShift { grip: listGrip; kind: "device"; pos: listRow.row.kind === "device" ? (listRow.row.pos || 0) : -1 }
    z: listGrip.active ? 10 : 0
    color: listGrip.active ? Qt.tint(root.panelBackground, fill) : (hasCursor ? fill : (current ? currentFill : "transparent"))

    MouseArea {
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onEntered: root.hovered(listRow.rowIndex)
      onClicked: root.activated(listRow.rowIndex)
    }

    RowLayout {
      id: listContent
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      anchors.leftMargin: Style.space(10)
      anchors.rightMargin: Style.space(6)
      spacing: Style.space(10)

      Grip {
        id: listGrip
        visible: listRow.row.kind === "device"
        row: listRow
        kind: "device"
        pos: listRow.row.pos || 0
        count: listRow.row.count || 1
        gap: Style.space(4)
        onMoved: function(delta) { root.deviceMoveRequested(listRow.row.id, delta) }
      }

      Text {
        visible: (listRow.row.glyph || "") !== ""
        text: listRow.row.glyph || ""
        color: root.foreground
        opacity: listRow.row.away === true ? 0.5 : 1
        font.family: root.fontFamily
        font.pixelSize: Style.font.icon
        Layout.preferredWidth: Style.space(20)
        horizontalAlignment: Text.AlignHCenter
        Layout.alignment: Qt.AlignVCenter
      }

      ColumnLayout {
        Layout.fillWidth: true
        spacing: Style.space(1)
        Text {
          textFormat: Text.PlainText
          Layout.fillWidth: true
          text: listRow.row.kind === "device" && listRow.row.title !== listRow.row.name
            ? listRow.row.title + "  ·  " + listRow.row.name : (listRow.row.title || listRow.row.label || "")
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
          elide: Text.ElideRight
        }
        Text {
          textFormat: Text.PlainText
          Layout.fillWidth: true
          visible: text !== ""
          text: listRow.row.status || listRow.row.hint || ""
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          elide: Text.ElideRight
        }
      }

      // A device: move it in the order, then open its page.
      Row {
        visible: listRow.row.kind === "device"
        spacing: Style.space(2)
        Layout.alignment: Qt.AlignVCenter
        PanelActionButton {
          iconText: Model.GLYPH.up
          tooltipText: "Move up"
          foreground: root.foreground
          fontFamily: root.fontFamily
          enabled: listRow.row.first !== true
          onHovered: function(on) { if (on) root.hovered(listRow.rowIndex) }
          onClicked: listGrip.animateMove(-1)
        }
        PanelActionButton {
          iconText: Model.GLYPH.down
          tooltipText: "Move down"
          foreground: root.foreground
          fontFamily: root.fontFamily
          enabled: listRow.row.last !== true
          onHovered: function(on) { if (on) root.hovered(listRow.rowIndex) }
          onClicked: listGrip.animateMove(1)
        }
      }

      // Asking to pair: accept or reject. In reach: pair.
      Button {
        visible: listRow.row.kind === "request" || listRow.row.kind === "available"
        Layout.alignment: Qt.AlignVCenter
        text: listRow.working ? "Waiting…" : (listRow.row.kind === "request" ? "Accept" : (listRow.row.waiting ? "Waiting…" : "Pair"))
        enabled: !listRow.working && listRow.row.waiting !== true
        bordered: true
        foreground: root.foreground
        fontFamily: root.fontFamily
        fontSize: Style.font.bodySmall
        onClicked: root.activated(listRow.rowIndex)
      }
      PanelActionButton {
        visible: listRow.row.kind === "request"
        iconText: Model.GLYPH.close
        tooltipText: "Reject"
        foreground: root.foreground
        fontFamily: root.fontFamily
        onClicked: root.rejectRequested(listRow.row.id)
      }

      Text {
        visible: listRow.row.kind === "device" || listRow.row.kind === "defaults"
        text: Model.GLYPH.chevronRight
        color: root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.icon
        Layout.alignment: Qt.AlignVCenter
      }
      Text {
        visible: listRow.row.kind === "resetGroup"
        text: Model.GLYPH.reset
        color: root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.icon
        Layout.alignment: Qt.AlignVCenter
      }
    }
  }

  // A device's own: nickname, icon (with its picker), place in the bar, and
  // whether it has a tab.
  component IdentityRow: Column {
    id: idRow
    property var row: ({})
    property int rowIndex: -1
    spacing: Style.space(4)

    CursorSurface {
      width: parent.width
      hasCursor: root.cursorIndex === idRow.rowIndex
      foreground: root.foreground
      implicitHeight: idContent.implicitHeight + Style.space(12)

      MouseArea {
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onEntered: root.hovered(idRow.rowIndex)
        onClicked: root.activated(idRow.rowIndex)
      }

      RowLayout {
        id: idContent
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        anchors.leftMargin: Style.space(10)
        anchors.rightMargin: Style.space(10)
        spacing: Style.space(10)

        ColumnLayout {
          Layout.fillWidth: true
          spacing: Style.space(1)
          Text {
            textFormat: Text.PlainText
            Layout.fillWidth: true
            text: idRow.row.label || ""
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
            elide: Text.ElideRight
          }
          Text {
            textFormat: Text.PlainText
            Layout.fillWidth: true
            text: idRow.row.hint || ""
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            wrapMode: Text.WordWrap
          }
        }

        // Nickname: typed here; Enter keeps it, Esc leaves it as it was.
        // Blank goes back to the name KDE Connect reports.
        TextField {
          id: nick
          visible: idRow.row.kind === "nickname"
          Layout.preferredWidth: Style.space(150)
          Layout.alignment: Qt.AlignVCenter
          text: idRow.row.value || ""
          placeholderText: root.deviceName
          foreground: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
          Component.onCompleted: if (idRow.row.kind === "nickname") root.nicknameField = nick
          onActiveFocusChanged: root.nicknameFocus(activeFocus)
          onAccepted: { root.nicknameSet(text); root.nicknameFocus(false) }
          Keys.onEscapePressed: { text = idRow.row.value || ""; root.nicknameFocus(false) }
        }

        Text {
          visible: idRow.row.kind === "icon"
          text: idRow.row.glyph || ""
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.display
          Layout.alignment: Qt.AlignVCenter
        }

        Row {
          visible: idRow.row.kind === "barPlace"
          spacing: Style.space(4)
          Layout.alignment: Qt.AlignVCenter
          Repeater {
            model: ["always", "attention", "never"]
            Button {
              required property var modelData
              text: Model.BAR_PLACE_LABELS[modelData]
              selected: idRow.row.value === modelData
              bordered: true
              foreground: root.foreground
              fontFamily: root.fontFamily
              fontSize: Style.font.bodySmall
              onClicked: root.barPlaceSet(modelData)
            }
          }
        }

        ToggleSwitch {
          visible: idRow.row.kind === "showInPanel"
          Layout.alignment: Qt.AlignVCenter
          checked: idRow.row.on === true
          cursorRing: false
          foreground: root.foreground
          onHovered: function(on) { if (on) root.hovered(idRow.rowIndex) }
          onToggled: root.activated(idRow.rowIndex)
        }
      }
    }

    // The icon picker, under the Icon row while it is open.
    Flow {
      visible: idRow.row.kind === "icon" && root.iconPicking
      width: parent.width
      leftPadding: Style.space(10)
      spacing: Style.space(4)
      Button {
        text: "Its kind"
        selected: (idRow.row.value || "") === ""
        bordered: true
        foreground: root.foreground
        fontFamily: root.fontFamily
        fontSize: Style.font.bodySmall
        onClicked: root.iconSet("")
      }
      Repeater {
        model: Model.ICON_CHOICES
        Button {
          required property var modelData
          iconText: String.fromCodePoint(parseInt(modelData.code, 16))
          tooltipText: modelData.label
          selected: idRow.row.value === modelData.code
          bordered: true
          foreground: root.foreground
          fontFamily: root.fontFamily
          onClicked: root.iconSet(modelData.code)
        }
      }
    }
  }

  component LayoutRow: CursorSurface {
    id: layoutRow
    property var row: ({})
    property int rowIndex: -1

    hasCursor: root.cursorIndex === rowIndex
    foreground: root.foreground
    implicitHeight: layoutContent.implicitHeight + Style.space(12)
    transform: DragShift { grip: layoutGrip; kind: "layout"; pos: layoutRow.row.kind === "layout" ? (layoutRow.row.pos || 0) : -1 }
    z: layoutGrip.active ? 10 : 0
    color: layoutGrip.active ? Qt.tint(root.panelBackground, fill) : (hasCursor ? fill : (current ? currentFill : "transparent"))

    MouseArea {
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onEntered: root.hovered(layoutRow.rowIndex)
      onClicked: root.activated(layoutRow.rowIndex)
    }

    RowLayout {
      id: layoutContent
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      anchors.leftMargin: Style.space(10)
      anchors.rightMargin: Style.space(10)
      spacing: Style.space(10)

      Grip {
        id: layoutGrip
        visible: layoutRow.row.kind === "layout"
        row: layoutRow
        kind: "layout"
        pos: layoutRow.row.pos || 0
        count: layoutRow.row.count || 1
        onMoved: function(delta) { root.sectionMoveRequested(layoutRow.row.section, delta) }
      }

      ColumnLayout {
        Layout.fillWidth: true
        spacing: Style.space(1)

        Text {
          textFormat: Text.PlainText
          Layout.fillWidth: true
          text: layoutRow.row.label || ""
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
          elide: Text.ElideRight
        }
        Text {
          textFormat: Text.PlainText
          Layout.fillWidth: true
          text: layoutRow.row.hint || ""
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          elide: Text.ElideRight
        }
      }

      Row {
        visible: layoutRow.row.kind === "layout"
        spacing: Style.space(2)
        Layout.alignment: Qt.AlignVCenter

        PanelActionButton {
          iconText: Model.GLYPH.up
          tooltipText: "Move up"
          foreground: root.foreground
          fontFamily: root.fontFamily
          enabled: layoutRow.row.first !== true
          onHovered: function(on) { if (on) root.hovered(layoutRow.rowIndex) }
          onClicked: layoutGrip.animateMove(-1)
        }
        PanelActionButton {
          iconText: Model.GLYPH.down
          tooltipText: "Move down"
          foreground: root.foreground
          fontFamily: root.fontFamily
          enabled: layoutRow.row.last !== true
          onHovered: function(on) { if (on) root.hovered(layoutRow.rowIndex) }
          onClicked: layoutGrip.animateMove(1)
        }
      }

      ToggleSwitch {
        Layout.alignment: Qt.AlignVCenter
        checked: layoutRow.row.on === true
        cursorRing: false
        foreground: root.foreground
        onHovered: function(on) { if (on) root.hovered(layoutRow.rowIndex) }
        onToggled: root.activated(layoutRow.rowIndex)
      }
    }
  }

  component ShortcutRow: CursorSurface {
    id: shortcutRow
    property var row: ({})
    property int rowIndex: -1

    hasCursor: root.cursorIndex === rowIndex
    foreground: root.foreground
    opacity: shortcutRow.row.kind !== "shortcut" || root.shortcutsShown ? 1.0 : 0.55
    implicitHeight: shortcutContent.implicitHeight + Style.space(10)
    transform: DragShift { grip: shortcutGrip; kind: shortcutRow.row.kind; pos: shortcutRow.row.on === true ? (shortcutRow.row.pos || 0) : -1 }
    z: shortcutGrip.active ? 10 : 0
    color: shortcutGrip.active ? Qt.tint(root.panelBackground, fill) : (hasCursor ? fill : (current ? currentFill : "transparent"))

    MouseArea {
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onEntered: root.hovered(shortcutRow.rowIndex)
      onClicked: root.activated(shortcutRow.rowIndex)
    }

    RowLayout {
      id: shortcutContent
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      anchors.leftMargin: Style.space(10)
      anchors.rightMargin: Style.space(6)
      spacing: Style.space(10)

      // Only chosen ones have a place to move in; the grip keeps its room
      // either way, so the rows line up.
      Grip {
        id: shortcutGrip
        opacity: shortcutRow.row.on === true ? 1 : 0
        enabled: shortcutRow.row.on === true
        row: shortcutRow
        kind: shortcutRow.row.kind
        pos: Math.max(0, shortcutRow.row.pos || 0)
        count: shortcutRow.row.count || 1
        onMoved: function(delta) {
          if (shortcutRow.row.kind === "bar") root.barMoveRequested(shortcutRow.row.key, delta)
          else root.moveRequested(shortcutRow.row.key, delta)
        }
      }

      Text {
        text: shortcutRow.row.on ? Model.GLYPH.checked : Model.GLYPH.unchecked
        color: shortcutRow.row.on ? root.foreground : root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.icon
        Layout.alignment: Qt.AlignVCenter
      }

      Text {
        text: shortcutRow.row.glyph || ""
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.icon
        Layout.preferredWidth: Style.space(18)
        horizontalAlignment: Text.AlignHCenter
        Layout.alignment: Qt.AlignVCenter
      }

      ColumnLayout {
        Layout.fillWidth: true
        spacing: Style.space(1)

        Text {
          textFormat: Text.PlainText
          Layout.fillWidth: true
          text: shortcutRow.row.label || ""
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
          elide: Text.ElideRight
        }
        Text {
          textFormat: Text.PlainText
          Layout.fillWidth: true
          text: shortcutRow.row.available === false
            ? "Not offered by this device right now"
            : (shortcutRow.row.hint || "")
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          elide: Text.ElideRight
        }
      }

      Row {
        visible: shortcutRow.row.on === true
        spacing: Style.space(2)
        Layout.alignment: Qt.AlignVCenter

        PanelActionButton {
          iconText: Model.GLYPH.up
          tooltipText: "Move earlier"
          foreground: root.foreground
          fontFamily: root.fontFamily
          enabled: shortcutRow.row.first !== true
          onHovered: function(on) { if (on) root.hovered(shortcutRow.rowIndex) }
          onClicked: shortcutGrip.animateMove(-1)
        }
        PanelActionButton {
          iconText: Model.GLYPH.down
          tooltipText: "Move later"
          foreground: root.foreground
          fontFamily: root.fontFamily
          enabled: shortcutRow.row.last !== true
          onHovered: function(on) { if (on) root.hovered(shortcutRow.rowIndex) }
          onClicked: shortcutGrip.animateMove(1)
        }
      }
    }
  }
}
