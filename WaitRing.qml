import QtQuick
import QtQuick.Shapes
import "Model.js" as Model

// Waiting on the device: an open ring, turning. It sits where the clicked
// control was (the control hides under it), so nothing moves while the
// device answers. Drawn, not a font glyph: a glyph turns around its text
// box, which is not the glyph's centre, so it sat off and wobbled. It fades
// in and out at the shared pace and turns once per four arrivals
// (Model.MOTION.inMs), so it keeps the panel's clock too.
Item {
  id: ring
  property bool running: false
  property real motion: 1
  property color color: "white"
  property real size: 14

  implicitWidth: size
  implicitHeight: size
  opacity: running ? 1 : 0
  visible: opacity > 0

  Behavior on opacity {
    NumberAnimation { duration: (ring.running ? Model.MOTION.inMs : Model.MOTION.outMs) * ring.motion; easing.type: Easing.OutCubic }
  }

  Shape {
    id: arc
    anchors.centerIn: parent
    width: ring.size
    height: ring.size
    preferredRendererType: Shape.CurveRenderer
    readonly property real stroke: Math.max(1.5, ring.size / 8)

    ShapePath {
      strokeColor: ring.color
      strokeWidth: arc.stroke
      fillColor: "transparent"
      capStyle: ShapePath.RoundCap
      PathAngleArc {
        centerX: ring.size / 2
        centerY: ring.size / 2
        radiusX: (ring.size - arc.stroke) / 2
        radiusY: (ring.size - arc.stroke) / 2
        startAngle: 0
        sweepAngle: 270
      }
    }

    RotationAnimator on rotation {
      running: ring.visible
      from: 0
      to: 360
      duration: Model.MOTION.inMs * 4 * ring.motion
      loops: Animation.Infinite
    }
  }
}
