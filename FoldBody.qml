import QtQuick
import "Model.js" as Model

// The content of a folding section: it grows and shrinks to its height,
// clipped, fading at the shared pace, instead of popping in and out.
Item {
  id: body
  property bool open: true
  property real motion: 1
  property bool animate: true
  property alias spacing: bodyColumn.spacing
  default property alias content: bodyColumn.data

  width: parent ? parent.width : 0
  height: open ? bodyColumn.implicitHeight : 0
  implicitHeight: height
  visible: height > 0.5
  clip: true
  opacity: open ? 1 : 0

  Behavior on height { enabled: body.animate; NumberAnimation { duration: Model.MOTION.inMs * body.motion; easing.type: Easing.OutCubic } }
  Behavior on opacity { enabled: body.animate; NumberAnimation { duration: (body.open ? Model.MOTION.inMs : Model.MOTION.outMs) * body.motion; easing.type: Easing.OutCubic } }

  Column {
    id: bodyColumn
    width: parent.width
  }
}
