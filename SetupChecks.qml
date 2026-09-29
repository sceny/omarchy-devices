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
  property color foreground: Color.foreground
  property string fontFamily: Style.font.family

  readonly property color dim: Qt.darker(foreground, 1.55)

  spacing: Style.space(6)

  Repeater {
    model: [
      { text: "Install KDE Connect on it", links: [
        { label: "Google Play", url: "https://play.google.com/store/apps/details?id=org.kde.kdeconnect_tp" },
        { label: "F-Droid", url: "https://f-droid.org/packages/org.kde.kdeconnect_tp/" }] },
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
