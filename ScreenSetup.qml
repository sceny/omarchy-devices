import QtQuick
import QtQuick.Layouts
import qs.Commons
import "Model.js" as Model

// Screen and apps, for one device (Model.screenSetup): where it stands, the
// steps to set it up (done ones ticked, the current one bright), and the
// pairing QR code under its step while it waits to be scanned. The page's
// actions are its keyboard rows, drawn by SettingsView.
Column {
  id: root

  property var setup: null
  // The pairing code to show (Model.qrGrid), while pairing on this page.
  property var qr: null
  property color foreground: Color.foreground
  property string fontFamily: Style.font.family

  readonly property color dim: Qt.darker(foreground, 1.55)

  spacing: Style.space(6)

  Text {
    width: root.width
    textFormat: Text.PlainText
    wrapMode: Text.WordWrap
    text: root.setup ? root.setup.line : "Checking…"
    color: root.setup && root.setup.state === "ready" ? root.foreground : root.dim
    font.family: root.fontFamily
    font.pixelSize: Style.font.bodySmall
  }

  Repeater {
    model: root.setup && root.setup.state !== "ready" && root.setup.state !== "checking" ? root.setup.steps : []

    RowLayout {
      id: step
      required property var modelData
      required property int index
      width: root.width
      spacing: Style.space(10)

      Text {
        Layout.alignment: Qt.AlignTop
        Layout.preferredWidth: Style.space(16)
        textFormat: Text.PlainText
        text: step.modelData.done ? Model.GLYPH.check : (step.index + 1) + "."
        color: step.modelData.current ? root.foreground : root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.bodySmall
      }
      ColumnLayout {
        Layout.fillWidth: true
        spacing: Style.space(8)
        Text {
          Layout.fillWidth: true
          textFormat: Text.PlainText
          wrapMode: Text.WordWrap
          text: step.modelData.text
          color: step.modelData.current ? root.foreground : root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
        }
        // The pairing code, under its step, while it waits to be scanned.
        Row {
          visible: step.modelData.qr === true && root.setup.showQr && root.qr !== null
          Layout.topMargin: Style.space(4)
          Layout.bottomMargin: Style.space(6)
          spacing: Style.space(12)
          QrCode {
            id: code
            grid: root.qr
          }
          Text {
            anchors.verticalCenter: parent.verticalCenter
            width: Math.max(Style.space(80), step.width - code.width - Style.space(40))
            textFormat: Text.PlainText
            wrapMode: Text.WordWrap
            text: "Developer options › Wireless debugging › Pair device with QR code. The code works once, for two minutes."
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
          }
        }
        Text {
          visible: step.modelData.qr === true && root.setup.pairingNote !== ""
          Layout.fillWidth: true
          textFormat: Text.PlainText
          wrapMode: Text.WordWrap
          text: root.setup.pairingNote
          color: root.setup.pairingNote !== "" && root.setup.actions.some(function(a) { return a.key === "pair" }) ? Color.urgent : root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
        }
      }
    }
  }

  Text {
    visible: !!root.setup && root.setup.usbNote !== ""
    width: root.width
    textFormat: Text.PlainText
    wrapMode: Text.WordWrap
    text: root.setup ? root.setup.usbNote : ""
    color: root.dim
    font.family: root.fontFamily
    font.pixelSize: Style.font.caption
  }
}
