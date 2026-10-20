import QtQuick
import qs.Commons

// One key, drawn as a key cap. The Keys overlay and the Screen and apps page
// both draw their keys with this, so a key reads the same everywhere.
Rectangle {
  id: cap
  property string label: ""
  property color foreground: Color.foreground
  property string fontFamily: Style.font.family

  width: capText.implicitWidth + Style.space(10)
  height: capText.implicitHeight + Style.space(4)
  radius: Style.space(3)
  color: Qt.rgba(foreground.r, foreground.g, foreground.b, 0.08)
  border.width: 1
  border.color: Qt.rgba(foreground.r, foreground.g, foreground.b, 0.22)

  Text {
    id: capText
    anchors.centerIn: parent
    textFormat: Text.PlainText
    text: cap.label
    color: cap.foreground
    font.family: cap.fontFamily
    font.pixelSize: Style.font.caption
  }
}
