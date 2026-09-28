import QtQuick
import QtQuick.Shapes
import "Model.js" as Model

// A ringing phone: the handset glyph and three sound waves drawn beside it,
// so each can move on its own (a font glyph is one picture). On the ring
// beat (Model.RING_BEAT) the waves light from the inside out and fade
// together while the handset rocks; between rings they rest, faint, and the
// handset stands upright.
Item {
  id: root

  property bool ringing: false
  property color color: "white"
  property string fontFamily: ""
  property real size: 32
  // Stretches the beat, like every other motion (the panel's slowMotion).
  property real motion: 1

  readonly property real waveMs: Model.RING_BEAT.waveMs * motion
  readonly property real fadeMs: Model.RING_BEAT.fadeMs * motion

  implicitWidth: size
  implicitHeight: size

  // The handset as drawn (the glyph's ink, not its text box), so the waves
  // centre on the handset itself.
  TextMetrics {
    id: ink
    font: handset.font
    text: handset.text
  }
  readonly property real handsetSize: size * 0.78
  readonly property real centerX: handset.x + ink.tightBoundingRect.x + ink.tightBoundingRect.width / 2
  readonly property real centerY: handset.y + handset.baselineOffset + ink.tightBoundingRect.y + ink.tightBoundingRect.height / 2

  Text {
    id: handset
    textFormat: Text.PlainText
    text: Model.GLYPH.callBack
    color: root.color
    font.family: root.fontFamily
    font.pixelSize: root.handsetSize
    // Left, its ink centred on the icon's middle line; the waves take the
    // space up and to its right.
    x: -ink.tightBoundingRect.x
    y: root.size / 2 - baselineOffset - ink.tightBoundingRect.y - ink.tightBoundingRect.height / 2
    // Rocks about its own middle.
    transform: Rotation { id: rock; origin.x: root.centerX - handset.x; origin.y: root.centerY - handset.y }
  }

  // The waves: arcs centred on the handset's middle, opening up and to the
  // right (around -45°, where the handset leaves its corner empty).
  component Wave: Shape {
    property int ring: 0
    anchors.fill: parent
    opacity: Model.RING_BEAT.restWave
    preferredRendererType: Shape.CurveRenderer
    ShapePath {
      strokeColor: root.color
      strokeWidth: Math.max(1.5, root.size * 0.075)
      fillColor: "transparent"
      capStyle: ShapePath.RoundCap
      PathAngleArc {
        centerX: root.centerX
        centerY: root.centerY
        radiusX: root.handsetSize * (0.40 + 0.17 * ring)
        radiusY: radiusX
        startAngle: -45 - 32
        sweepAngle: 64
      }
    }
  }
  Wave { id: wave0; ring: 0 }
  Wave { id: wave1; ring: 1 }
  Wave { id: wave2; ring: 2 }

  // One ring: each wave lights in turn and all fade together, while the
  // handset rocks left, right, half back, upright. 3 waves + a fade long.
  SequentialAnimation {
    id: beat
    running: root.ringing && root.visible
    loops: Animation.Infinite
    onRunningChanged: if (!running) root.settle()

    SequentialAnimation {
      loops: Model.RING_BEAT.rings
      ParallelAnimation {
        SequentialAnimation {
          NumberAnimation { target: wave0; property: "opacity"; to: 1; duration: root.waveMs; easing.type: Easing.OutCubic }
          PauseAnimation { duration: root.waveMs * 2 }
          NumberAnimation { target: wave0; property: "opacity"; to: Model.RING_BEAT.restWave; duration: root.fadeMs; easing.type: Easing.OutCubic }
        }
        SequentialAnimation {
          PauseAnimation { duration: root.waveMs }
          NumberAnimation { target: wave1; property: "opacity"; to: 1; duration: root.waveMs; easing.type: Easing.OutCubic }
          PauseAnimation { duration: root.waveMs }
          NumberAnimation { target: wave1; property: "opacity"; to: Model.RING_BEAT.restWave; duration: root.fadeMs; easing.type: Easing.OutCubic }
        }
        SequentialAnimation {
          PauseAnimation { duration: root.waveMs * 2 }
          NumberAnimation { target: wave2; property: "opacity"; to: 1; duration: root.waveMs; easing.type: Easing.OutCubic }
          NumberAnimation { target: wave2; property: "opacity"; to: Model.RING_BEAT.restWave; duration: root.fadeMs; easing.type: Easing.OutCubic }
        }
        SequentialAnimation {
          NumberAnimation { target: rock; property: "angle"; to: -Model.RING_BEAT.angle; duration: root.waveMs; easing.type: Easing.OutCubic }
          NumberAnimation { target: rock; property: "angle"; to: Model.RING_BEAT.angle; duration: root.waveMs; easing.type: Easing.OutCubic }
          NumberAnimation { target: rock; property: "angle"; to: -Model.RING_BEAT.angle / 2; duration: root.waveMs; easing.type: Easing.OutCubic }
          NumberAnimation { target: rock; property: "angle"; to: 0; duration: root.fadeMs; easing.type: Easing.OutCubic }
        }
      }
      PauseAnimation { duration: Model.RING_BEAT.gapMs * root.motion }
    }
    PauseAnimation { duration: (Model.RING_BEAT.restMs - Model.RING_BEAT.gapMs) * root.motion }
  }

  function settle() {
    rock.angle = 0
    wave0.opacity = wave1.opacity = wave2.opacity = Model.RING_BEAT.restWave
  }
}
