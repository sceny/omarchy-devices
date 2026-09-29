import QtQuick
import QtQuick.Layouts
import Quickshell.Io
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
  // A QR code for the app's store page beside the install step, while no
  // device is paired: the phone's camera opens it. Drawn by qrencode
  // (Omarchy ships it); without it, the links alone.
  property bool showQr: false
  property var qr: null
  Process {
    running: root.showQr && root.qr === null
    command: ["qrencode", "-t", "ASCII", "-m", "0", Model.APP_LINKS.play]
    stdout: StdioCollector { onStreamFinished: root.qr = Model.qrGrid(text) }
  }
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
      { text: "Install KDE Connect", qr: true, links: [
        { label: "Google Play", url: Model.APP_LINKS.play },
        { label: "F-Droid", url: Model.APP_LINKS.fdroid }] },
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
      ColumnLayout {
      Layout.fillWidth: true
      spacing: Style.space(8)
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

      // The QR code: black on white with its quiet zone, whatever the
      // theme, so a phone's camera reads it.
      Row {
        visible: step.modelData.qr === true && root.showQr && root.qr !== null
        spacing: Style.space(10)
        Rectangle {
          id: qrBox
          readonly property int modules: root.qr ? root.qr.size + 4 : 0
          readonly property int cell: 4
          width: modules * cell
          height: width
          color: "white"
          radius: Style.space(2)
          Canvas {
            id: qrCanvas
            anchors.fill: parent
            onPaint: {
              var ctx = getContext("2d")
              ctx.reset()
              ctx.fillStyle = "white"
              ctx.fillRect(0, 0, width, height)
              var g = root.qr
              if (!g) return
              ctx.fillStyle = "black"
              for (var r = 0; r < g.size; r++)
                for (var c = 0; c < g.size; c++)
                  if (g.dark[r][c]) ctx.fillRect((c + 2) * qrBox.cell, (r + 2) * qrBox.cell, qrBox.cell, qrBox.cell)
            }
            Connections {
              target: root
              function onQrChanged() { qrCanvas.requestPaint() }
            }
          }
        }
        Text {
          anchors.verticalCenter: parent.verticalCenter
          width: Math.max(Style.space(80), step.width - qrBox.width - Style.space(40))
          textFormat: Text.PlainText
          wrapMode: Text.WordWrap
          text: "Scan with the phone's camera to open Google Play"
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
        }
      }
      }
    }
  }
}
