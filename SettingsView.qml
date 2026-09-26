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
  property color foreground: Color.foreground
  property string fontFamily: Style.font.family

  signal activated(int index)
  signal moveRequested(string key, int delta)
  signal hovered(int index)

  readonly property color dim: Qt.darker(foreground, 1.55)

  function firstIndex(kind) {
    for (var i = 0; i < rows.length; i++) if (rows[i].kind === kind) return i
    return -1
  }

  spacing: Style.space(6)

  // ---- Layout ----
  PanelSectionHeader {
    text: "LAYOUT"
    foreground: root.foreground
    fontFamily: root.fontFamily
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

  Item { width: 1; height: Style.space(6) }
  PanelSeparator { foreground: root.foreground }

  // ---- Shortcuts ----
  PanelSectionHeader {
    text: "SHORTCUTS"
    foreground: root.foreground
    fontFamily: root.fontFamily
  }

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
    opacity: root.shortcutsShown ? 1.0 : 0.55
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
          onClicked: root.moveRequested(shortcutRow.row.key, -1)
        }
        PanelActionButton {
          iconText: Model.GLYPH.down
          tooltipText: "Move later"
          foreground: root.foreground
          fontFamily: root.fontFamily
          enabled: shortcutRow.row.last !== true
          onHovered: function(on) { if (on) root.hovered(shortcutRow.rowIndex) }
          onClicked: root.moveRequested(shortcutRow.row.key, 1)
        }
      }
    }
  }
}
