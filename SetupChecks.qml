import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Ui
import "Model.js" as Model

// KDE Connect setup, checked and fixable: installed, running, the firewall,
// a paired and connected device, then what to do on the phone. Draws
// `checks` (kdeconnect-bridge doctor) and asks for fixes; nothing changes on
// the system without a click on a fix.
Column {
  id: root

  property var checks: []
  property var busyFixes: ({})
  property bool showPhoneSteps: true
  property color foreground: Color.foreground
  property color urgent: Color.urgent
  property string fontFamily: Style.font.family

  signal fixRequested(string what)

  readonly property color dim: Qt.darker(foreground, 1.55)

  spacing: Style.space(6)

  Repeater {
    model: root.checks
    RowLayout {
      id: check
      required property var modelData
      width: root.width
      spacing: Style.space(10)

      Text {
        Layout.alignment: Qt.AlignTop
        Layout.topMargin: Style.space(1)
        text: check.modelData.ok ? Model.GLYPH.check : Model.GLYPH.alert
        color: check.modelData.ok ? root.dim : root.urgent
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
      }
      ColumnLayout {
        Layout.fillWidth: true
        spacing: Style.space(1)
        Text {
          Layout.fillWidth: true
          textFormat: Text.PlainText
          text: check.modelData.label
          color: check.modelData.ok ? root.dim : root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
          elide: Text.ElideRight
        }
        Text {
          Layout.fillWidth: true
          visible: text !== ""
          textFormat: Text.PlainText
          text: check.modelData.detail || ""
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          wrapMode: Text.WordWrap
        }
      }
      Button {
        visible: (check.modelData.fix || "") !== ""
        Layout.alignment: Qt.AlignTop
        text: root.busyFixes[check.modelData.fix] ? "Working…" : (check.modelData.fixLabel || "Fix")
        iconText: root.busyFixes[check.modelData.fix] ? "\u{F0996}" : ""
        iconSpinning: root.busyFixes[check.modelData.fix] === true
        enabled: !root.busyFixes[check.modelData.fix]
        tooltipText: check.modelData.fix === "install" || check.modelData.fix === "firewall" ? "Asks for your password" : ""
        bordered: true
        foreground: root.foreground
        fontFamily: root.fontFamily
        fontSize: Style.font.bodySmall
        onClicked: root.fixRequested(check.modelData.fix)
      }
    }
  }

  Item { width: 1; height: Style.space(4); visible: root.showPhoneSteps }

  PanelSectionHeader {
    visible: root.showPhoneSteps
    text: "ON THE PHONE OR TABLET"
    foreground: root.foreground
    fontFamily: root.fontFamily
  }

  Repeater {
    model: root.showPhoneSteps ? [
      { text: "Install KDE Connect", links: [
        { label: "Google Play", url: "https://play.google.com/store/apps/details?id=org.kde.kdeconnect_tp" },
        { label: "F-Droid", url: "https://f-droid.org/packages/org.kde.kdeconnect_tp/" }] },
      { text: "Join the same network as this computer and pair from the app", links: [] },
      { text: "Allow what you want here: notification access, SMS, contacts, media control", links: [] },
      { text: "Samsung: set the app's battery use to Unrestricted, so the link survives sleep", links: [] }
    ] : []

    RowLayout {
      id: step
      required property var modelData
      required property int index
      width: root.width
      spacing: Style.space(10)

      Text {
        Layout.alignment: Qt.AlignTop
        textFormat: Text.PlainText
        text: (step.index + 1) + "."
        color: root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.bodySmall
      }
      Flow {
        Layout.fillWidth: true
        spacing: Style.space(8)
        Text {
          width: Math.min(implicitWidth, parent.width)
          textFormat: Text.PlainText
          wrapMode: Text.WordWrap
          text: step.modelData.text
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
        }
        Repeater {
          model: step.modelData.links
          Text {
            required property var modelData
            textFormat: Text.PlainText
            text: modelData.label + " ↗"
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            font.underline: linkMouse.containsMouse
            MouseArea {
              id: linkMouse
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: Qt.openUrlExternally(parent.modelData.url)
            }
          }
        }
      }
    }
  }
}
