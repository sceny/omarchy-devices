import QtQuick
import "Model.js" as Model

// Scrolling follows the hand, like anywhere else on the desktop. Left to
// itself, a list turns each wheel event into a fixed step and a burst of
// events into about one, so a long spin moved a couple of messages. Here
// every event adds its whole distance: a touchpad moves the list 1:1 with the
// fingers, and a mouse wheel's notches add up into one glide at the shared
// pace, so a fast spin goes as far as it was spun.
//
// Declare it inside the Flickable (or ListView) it scrolls.
WheelHandler {
  id: wheel
  property Flickable flickable: null
  property real motion: 1
  // One notch: about three lines, as desktop apps scroll.
  property real notch: 72

  target: null
  orientation: Qt.Vertical
  acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad

  property real goal: 0

  function clamp(y) {
    var f = flickable
    var top = f.originY
    var bottom = f.originY + Math.max(0, f.contentHeight - f.height)
    return Math.max(top, Math.min(bottom, y))
  }

  onWheel: function(event) {
    var f = flickable
    if (!f || f.contentHeight <= f.height) return
    if (event.pixelDelta.y !== 0) {
      glide.stop()
      f.contentY = clamp(f.contentY - event.pixelDelta.y)
      goal = f.contentY
    } else if (event.angleDelta.y !== 0) {
      goal = clamp((glide.running ? goal : f.contentY) - event.angleDelta.y / 120 * notch)
      glide.to = goal
      glide.restart()
    }
    event.accepted = true
  }

  property NumberAnimation glide: NumberAnimation {
    target: wheel.flickable
    property: "contentY"
    duration: Model.MOTION.inMs * wheel.motion
    easing.type: Easing.OutCubic
  }
}
