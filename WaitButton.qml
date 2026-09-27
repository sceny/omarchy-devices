import QtQuick
import qs.Ui

// A row's icon button that turns into the waiting ring while the device
// works on its click, and takes no second click meanwhile.
PanelActionButton {
  id: button
  property string glyph: ""
  property bool waiting: false
  property real motion: 1

  iconText: waiting ? "" : glyph

  WaitRing {
    anchors.centerIn: parent
    running: button.waiting
    motion: button.motion
    color: button.foreground
    font.family: button.fontFamily
    font.pixelSize: button.fontSize
  }
}
