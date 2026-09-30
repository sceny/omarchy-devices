import QtQuick
import qs.Commons
import "Model.js" as Model

// The key two devices show while they pair, to compare: a small caption
// above (what to do with it), the key itself large, apart, in the accent.
// The pop-up, the panel's pairing card and the Add a device rows all draw it
// with this, so it reads the same everywhere.
Column {
  id: root
  property string key: ""
  // What to do with it: "Check it matches", "Accept on it if it matches".
  property string caption: ""
  property color foreground: Color.foreground
  property string fontFamily: Style.font.family
  // The panel's rows use a smaller key than a card.
  property bool compact: false

  visible: key !== ""
  spacing: Style.space(1)

  Text {
    textFormat: Text.PlainText
    text: ("Key · " + root.caption).toUpperCase()
    color: Qt.darker(root.foreground, 1.55)
    font.family: root.fontFamily
    font.pixelSize: Style.font.caption - 1
    font.letterSpacing: 0.6
  }
  Text {
    textFormat: Text.PlainText
    text: root.key
    color: Color.accent
    font.family: root.fontFamily
    font.pixelSize: root.compact ? Style.font.body + 1 : Style.font.heading + 2
    font.bold: true
    font.letterSpacing: root.compact ? 1.2 : 2
  }
}
