import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Ui
import "Model.js" as Model

// Adding a device: the steps on it (pairing starts there), for the
// Connection page. This computer's checks are the page's own rows.
Column {
  id: root

  // This computer's network ("192.168.1.0/24"), named in the Wi-Fi step.
  property string network: ""
  // A QR code for the app's store page in the install step: the phone's
  // camera opens it (#64). Drawn from qrencode (Omarchy ships it); without
  // it, the links alone.
  property bool showQr: false
  property var qr: null
  Process {
    running: root.showQr && root.qr === null
    command: ["qrencode", "-t", "ASCII", "-m", "0", Model.APP_LINKS.play]
    stdout: StdioCollector { onStreamFinished: root.qr = Model.qrGrid(text) }
  }
  property color foreground: Color.foreground
  property string fontFamily: Style.font.family

  readonly property color dim: Qt.darker(foreground, 1.55)

  spacing: Style.space(6)

  Repeater {
    model: [
      { text: "Install KDE Connect on it", qr: true, links: [
        { label: "Google Play", url: Model.APP_LINKS.play },
        { label: "F-Droid", url: Model.APP_LINKS.fdroid }] },
      { text: "Join this computer's Wi-Fi" + (root.network !== "" ? " (" + root.network + ")" : ""), links: [] },
      { text: "Open the app and pick this computer; accept here", links: [] },
      { text: "Allow what you want here: notification access, SMS, contacts, media control", links: [] }
    ]

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
