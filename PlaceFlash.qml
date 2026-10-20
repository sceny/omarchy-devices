import QtQuick
import qs.Commons
import "Model.js" as Model

// A place marked for a moment (a Keys group's Open lands on it): it fades in,
// holds, and fades out at the shared pace. It takes no click.
Rectangle {
  id: flash
  property real motion: 1
  property color accent: Color.accent

  function pulse() { mark.restart() }

  enabled: false
  radius: Style.cornerRadius
  color: Qt.alpha(accent, 0.1)
  border.width: 2
  border.color: Qt.alpha(accent, 0.8)
  opacity: 0
  visible: opacity > 0.01

  SequentialAnimation {
    id: mark
    NumberAnimation { target: flash; property: "opacity"; to: 1; duration: Model.MOTION.inMs * flash.motion; easing.type: Easing.OutCubic }
    PauseAnimation { duration: Model.PLACE_FLASH_HOLD_MS * flash.motion }
    NumberAnimation { target: flash; property: "opacity"; to: 0; duration: Model.MOTION.outMs * flash.motion; easing.type: Easing.OutCubic }
  }
}
