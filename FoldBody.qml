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
  // Open, it stays visible even at height 0: a hidden item's children count
  // as hidden, so its content would measure 0 and it could never grow (a
  // section that starts hidden, such as Files, stayed an empty header).
  visible: open || height > 0.5
  // Clipped while it folds or unfolds; open and still, its content may
  // reach past it (a tile dragged to another row).
  clip: !open || Math.abs(height - bodyColumn.implicitHeight) > 0.5
  opacity: open ? 1 : 0

  Behavior on height { enabled: body.animate; NumberAnimation { duration: Model.MOTION.inMs * body.motion; easing.type: Easing.OutCubic } }
  Behavior on opacity { enabled: body.animate; NumberAnimation { duration: (body.open ? Model.MOTION.inMs : Model.MOTION.outMs) * body.motion; easing.type: Easing.OutCubic } }

  Column {
    id: bodyColumn
    width: parent.width
  }
}
