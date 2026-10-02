import QtQuick
import QtQml
import QtQuick.Layouts
import Quickshell.Io
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
  // it, the links alone. Android or iPhone (a toggle, kept by the panel):
  // the iPhone app does far less, and the step says so.
  property bool showQr: false
  property string platform: "android"
  signal platformSet(string platform)
  readonly property bool ios: platform === "ios"
  property var qrs: ({})
  readonly property var qr: qrs[platform] || null
  // One qrencode per phone, each with its own address: made once, when
  // that phone's code is first shown.
  Instantiator {
    model: [{ key: "android", url: Model.APP_LINKS.play }, { key: "ios", url: Model.APP_LINKS.appStore }]
    delegate: Process {
      id: qrMaker
      required property var modelData
      running: root.showQr && root.platform === modelData.key && root.qrs[modelData.key] === undefined
      command: ["qrencode", "-t", "ASCII", "-m", "0", modelData.url]
      stdout: StdioCollector {
        onStreamFinished: {
          var next = Object.assign({}, root.qrs)
          next[qrMaker.modelData.key] = Model.qrGrid(text)
          root.qrs = next
        }
      }
    }
  }
  property color foreground: Color.foreground
  property string fontFamily: Style.font.family

  readonly property color dim: Qt.darker(foreground, 1.55)

  spacing: Style.space(6)

  Repeater {
    model: [
      { text: "Install KDE Connect on it", qr: true, links: root.ios
        ? [{ label: "App Store", url: Model.APP_LINKS.appStore }]
        : [{ label: "Google Play", url: Model.APP_LINKS.play }, { label: "F-Droid", url: Model.APP_LINKS.fdroid }] },
      { text: "Join this computer's Wi-Fi" + (root.network !== "" ? " (" + root.network + ")" : ""), links: [] },
      { text: "Open the app and pick this computer; accept here", links: [] },
      { text: root.ios ? "Allow local network access when it asks" : "Allow what you want here: notification access, SMS, contacts, media control", links: [] }
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

      // Which phone the code is for: two choices, as Settings draws one
      // (bordered, the chosen one filled), with room around the code.
      Row {
        visible: step.modelData.qr === true && root.showQr
        Layout.topMargin: Style.space(6)
        spacing: Style.space(4)
        Repeater {
          model: [{ key: "android", label: "Android" }, { key: "ios", label: "iPhone" }]
          Button {
            required property var modelData
            text: modelData.label
            selected: root.platform === modelData.key
            bordered: true
            foreground: root.foreground
            fontFamily: root.fontFamily
            fontSize: Style.font.bodySmall
            onClicked: if (root.platform !== modelData.key) root.platformSet(modelData.key)
          }
        }
      }

      // The QR code: black on white with its quiet zone, whatever the
      // theme, so a phone's camera reads it.
      Row {
        visible: step.modelData.qr === true && root.showQr && root.qr !== null
        Layout.topMargin: Style.space(4)
        Layout.bottomMargin: Style.space(6)
        spacing: Style.space(12)
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
            // A paint asked while hidden (the code is hidden while the other
            // phone's is made) is skipped: paint again when it shows.
            onVisibleChanged: if (visible) requestPaint()
            onWidthChanged: requestPaint()
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
          text: "Scan with the phone's camera to open " + (root.ios ? "the App Store" : "Google Play")
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
        }
      }
      // The iPhone app does far less: said here, not found out later.
      Text {
        visible: step.modelData.qr === true && root.showQr && root.ios
        Layout.fillWidth: true
        textFormat: Text.PlainText
        wrapMode: Text.WordWrap
        text: "With an iPhone, this panel gets files and the clipboard from it. It cannot show the iPhone's notifications or messages, and the iPhone stays connected only while KDE Connect is open on it."
        color: root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
      }
      }
    }
  }
}
