import QtQuick
import "Model.js" as Model

// Waiting on the device: Omarchy's loading glyph, turning. It sits where the
// clicked control was (the control hides under it), so nothing moves while
// the device answers. It fades in and out at the shared pace and turns once
// per four arrivals (Model.MOTION.inMs), so it keeps the panel's clock too.
Text {
  id: ring
  property bool running: false
  property real motion: 1

  textFormat: Text.PlainText
  text: "\u{F0996}"          // loading, as Omarchy's own panels draw it
  horizontalAlignment: Text.AlignHCenter
  verticalAlignment: Text.AlignVCenter
  transformOrigin: Item.Center
  opacity: running ? 1 : 0
  visible: opacity > 0

  Behavior on opacity {
    NumberAnimation { duration: (ring.running ? Model.MOTION.inMs : Model.MOTION.outMs) * ring.motion; easing.type: Easing.OutCubic }
  }

  RotationAnimator on rotation {
    running: ring.visible
    from: 0
    to: 360
    duration: Model.MOTION.inMs * 4 * ring.motion
    loops: Animation.Infinite
  }
}
