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

  // ---- Moving rows in their orders (Reorder): drag, arrows, keyboard ----
  function rowAt(kind, pos) {
    for (var i = 0; i < rows.length; i++) {
      var r = rows[i]
      if (r.kind === kind && r.pos === pos && (r.on === true || kind === "device" || kind === "layout")) return r
    }
    return null
  }
  function countOf(kind) {
    var n = 0
    for (var i = 0; i < rows.length; i++) {
      var r = rows[i]
      if (r.kind === kind && r.pos >= 0 && (r.on === true || kind === "device" || kind === "layout")) n++
    }
    return n
  }
  function orderFor(kind) {
    return kind === "device" ? deviceOrder : kind === "layout" ? layoutOrder
         : kind === "bar" ? barOrder : kind === "shortcut" ? shortcutOrder : null
  }
  // The keyboard (Shift+K / Shift+J): the same glide as the arrows and a drop.
  function glideMove(kind, pos, delta) {
    var o = orderFor(kind)
    if (!o || pos < 0) return false
    o.step(pos, delta)
    return true
  }

  Reorder {
    id: deviceOrder
    count: root.countOf("device")
    gap: Style.space(4)
    motion: root.motion
    onMoved: function(a, b) { var r = root.rowAt("device", a); if (r) root.deviceMoveRequested(r.id, b - a) }
  }
  Reorder {
    id: layoutOrder
    count: root.countOf("layout")
    gap: Style.space(6)
    motion: root.motion
    onMoved: function(a, b) { var r = root.rowAt("layout", a); if (r) root.sectionMoveRequested(r.section, b - a) }
  }
  Reorder {
    id: barOrder
    count: root.countOf("bar")
    gap: Style.space(6)
    motion: root.motion
    onMoved: function(a, b) { var r = root.rowAt("bar", a); if (r) root.barMoveRequested(r.key, b - a) }
  }
  Reorder {
    id: shortcutOrder
    count: root.countOf("shortcut")
    gap: Style.space(6)
    motion: root.motion
    onMoved: function(a, b) { var r = root.rowAt("shortcut", a); if (r) root.moveRequested(r.key, b - a) }
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
    readonly property int place: listRow.row.kind === "device" ? (listRow.row.pos || 0) : -1
    readonly property bool moving: place >= 0 && deviceOrder.from === place
    onHeightChanged: if (place >= 0) deviceOrder.itemSize = height
    transform: ReorderShift { order: deviceOrder; index: listRow.place }
    z: moving ? 10 : 0
    // Solid while it moves, so the row it passes over never shows through.
    color: moving ? Qt.tint(root.panelBackground, fill) : (hasCursor ? fill : (current ? currentFill : "transparent"))

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

      ReorderGrip {
        visible: listRow.place >= 0
        order: deviceOrder
        index: listRow.place
        item: listRow
        foreground: root.foreground
        fontFamily: root.fontFamily
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
          onClicked: deviceOrder.step(listRow.place, -1)
        }
        PanelActionButton {
          iconText: Model.GLYPH.down
          tooltipText: "Move down"
          foreground: root.foreground
          fontFamily: root.fontFamily
          enabled: listRow.row.last !== true
          onHovered: function(on) { if (on) root.hovered(listRow.rowIndex) }
          onClicked: deviceOrder.step(listRow.place, 1)
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
    readonly property int place: layoutRow.row.kind === "layout" ? (layoutRow.row.pos || 0) : -1
    readonly property bool moving: place >= 0 && layoutOrder.from === place
    onHeightChanged: if (place >= 0) layoutOrder.itemSize = height
    transform: ReorderShift { order: layoutOrder; index: layoutRow.place }
    z: moving ? 10 : 0
    color: moving ? Qt.tint(root.panelBackground, fill) : (hasCursor ? fill : (current ? currentFill : "transparent"))

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

      ReorderGrip {
        visible: layoutRow.place >= 0
        order: layoutOrder
        index: layoutRow.place
        item: layoutRow
        foreground: root.foreground
        fontFamily: root.fontFamily
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
          onClicked: layoutOrder.step(layoutRow.place, -1)
        }
        PanelActionButton {
          iconText: Model.GLYPH.down
          tooltipText: "Move down"
          foreground: root.foreground
          fontFamily: root.fontFamily
          enabled: layoutRow.row.last !== true
          onHovered: function(on) { if (on) root.hovered(layoutRow.rowIndex) }
          onClicked: layoutOrder.step(layoutRow.place, 1)
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
    readonly property var order: root.orderFor(shortcutRow.row.kind)
    readonly property int place: shortcutRow.row.on === true ? (shortcutRow.row.pos || 0) : -1
    readonly property bool moving: place >= 0 && !!order && order.from === place
    onHeightChanged: if (place >= 0 && order) order.itemSize = height
    transform: ReorderShift { order: shortcutRow.order; index: shortcutRow.place }
    z: moving ? 10 : 0
    color: moving ? Qt.tint(root.panelBackground, fill) : (hasCursor ? fill : (current ? currentFill : "transparent"))

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
      ReorderGrip {
        opacity: shortcutRow.place >= 0 ? 1 : 0
        order: shortcutRow.order
        index: shortcutRow.place
        item: shortcutRow
        foreground: root.foreground
        fontFamily: root.fontFamily
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
          onClicked: shortcutRow.order.step(shortcutRow.place, -1)
        }
        PanelActionButton {
          iconText: Model.GLYPH.down
          tooltipText: "Move later"
          foreground: root.foreground
          fontFamily: root.fontFamily
          enabled: shortcutRow.row.last !== true
          onHovered: function(on) { if (on) root.hovered(shortcutRow.rowIndex) }
          onClicked: shortcutRow.order.step(shortcutRow.place, 1)
        }
      }
    }
  }
}
