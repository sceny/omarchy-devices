import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Ui
import "Model.js" as Model

// The phone panel's settings page, shown in place of the phone view.
//
// Presentation only: it draws `rows` (Model.settingsRows, one flat list so the
// keyboard cursor is a single index) and emits intent. Panel.qml owns the
// cursor and writes shell.json.
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

  readonly property color dim: Qt.darker(foreground, 1.55)

  function firstIndex(kind) {
    for (var i = 0; i < rows.length; i++) if (rows[i].kind === kind) return i
    return -1
  }

  spacing: Style.space(6)

  // ---- Layout ----
  FoldToggle {
    width: root.width
    title: "LAYOUT"
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
    title: "BAR"
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
    title: "SHORTCUTS"
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

  Item { width: 1; height: Style.space(6) }
  PanelSeparator { foreground: root.foreground }

  // ---- Setup ----
  FoldToggle {
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
      readonly property int rowIndex: root.firstIndex("reset")
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

  component LayoutRow: CursorSurface {
    id: layoutRow
    property var row: ({})
    property int rowIndex: -1

    hasCursor: root.cursorIndex === rowIndex
    foreground: root.foreground
    implicitHeight: layoutContent.implicitHeight + Style.space(12)

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
          onClicked: root.sectionMoveRequested(layoutRow.row.section, -1)
        }
        PanelActionButton {
          iconText: Model.GLYPH.down
          tooltipText: "Move down"
          foreground: root.foreground
          fontFamily: root.fontFamily
          enabled: layoutRow.row.last !== true
          onHovered: function(on) { if (on) root.hovered(layoutRow.rowIndex) }
          onClicked: root.sectionMoveRequested(layoutRow.row.section, 1)
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
          onClicked: shortcutRow.row.kind === "bar" ? root.barMoveRequested(shortcutRow.row.key, -1) : root.moveRequested(shortcutRow.row.key, -1)
        }
        PanelActionButton {
          iconText: Model.GLYPH.down
          tooltipText: "Move later"
          foreground: root.foreground
          fontFamily: root.fontFamily
          enabled: shortcutRow.row.last !== true
          onHovered: function(on) { if (on) root.hovered(shortcutRow.rowIndex) }
          onClicked: shortcutRow.row.kind === "bar" ? root.barMoveRequested(shortcutRow.row.key, 1) : root.moveRequested(shortcutRow.row.key, 1)
        }
      }
    }
  }
}
