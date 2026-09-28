import QtQuick
import "Model.js" as Model

// A placeholder block where content is on its way from the device: the
// shape of what will land there, breathing slowly at the shared pace.
Rectangle {
  id: bone
  property color foreground: "white"
  property real motion: 1

  radius: Math.min(height / 2, 6)
  color: Qt.rgba(foreground.r, foreground.g, foreground.b, 0.12)

  SequentialAnimation on opacity {
    running: bone.visible
    loops: Animation.Infinite
    NumberAnimation { from: 1; to: 0.45; duration: Model.MOTION.inMs * 3 * bone.motion; easing.type: Easing.InOutSine }
    NumberAnimation { from: 0.45; to: 1; duration: Model.MOTION.inMs * 3 * bone.motion; easing.type: Easing.InOutSine }
  }
}
