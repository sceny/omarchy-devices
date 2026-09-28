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

  Text {
    id: handset
    textFormat: Text.PlainText
    text: Model.GLYPH.callBack
    color: root.color
    font.family: root.fontFamily
    font.pixelSize: root.size * 0.78
    // Low and to the left, leaving the top right corner to the waves.
    x: 0
    y: root.size - height * 0.95
    transformOrigin: Item.Center
  }

  // The waves: quarter arcs around the handset's earpiece corner, inside out.
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
        centerX: root.size * 0.42
        centerY: root.size * 0.58
        radiusX: root.size * (0.30 + 0.15 * ring)
        radiusY: radiusX
        startAngle: -80
        sweepAngle: 70
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
          NumberAnimation { target: handset; property: "rotation"; to: -Model.RING_BEAT.angle; duration: root.waveMs; easing.type: Easing.OutCubic }
          NumberAnimation { target: handset; property: "rotation"; to: Model.RING_BEAT.angle; duration: root.waveMs; easing.type: Easing.OutCubic }
          NumberAnimation { target: handset; property: "rotation"; to: -Model.RING_BEAT.angle / 2; duration: root.waveMs; easing.type: Easing.OutCubic }
          NumberAnimation { target: handset; property: "rotation"; to: 0; duration: root.fadeMs; easing.type: Easing.OutCubic }
        }
      }
      PauseAnimation { duration: Model.RING_BEAT.gapMs * root.motion }
    }
    PauseAnimation { duration: (Model.RING_BEAT.restMs - Model.RING_BEAT.gapMs) * root.motion }
  }

  function settle() {
    handset.rotation = 0
    wave0.opacity = wave1.opacity = wave2.opacity = Model.RING_BEAT.restWave
  }
}
