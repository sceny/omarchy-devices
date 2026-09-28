import QtQuick
import "Model.js" as Model

// An item's place while its order moves (Reorder): the moving item follows
// the pointer or its glide, the others slide aside, animated. Set as the
// item's `transform`. `index` -1: not part of the order.
Translate {
  id: place
  property Reorder order: null
  property int index: -1

  readonly property bool isMoving: !!order && index >= 0 && order.from === index
  readonly property real value: !order || index < 0 ? 0 : (isMoving ? order.offset : order.shift(index))
  readonly property bool inGrid: !!order && order.grid && index >= 0

  x: inGrid ? (isMoving ? order.offsetX : order.shiftX(index)) : (order && order.axis === "x" ? value : 0)
  y: inGrid ? (isMoving ? order.offsetY : order.shiftY(index)) : (order && order.axis === "y" ? value : 0)

  Behavior on x {
    enabled: !!place.order && !place.order.committing && !place.isMoving
    NumberAnimation { duration: Model.MOTION.inMs * (place.order ? place.order.motion : 1); easing.type: Easing.OutCubic }
  }
  Behavior on y {
    enabled: !!place.order && !place.order.committing && !place.isMoving
    NumberAnimation { duration: Model.MOTION.inMs * (place.order ? place.order.motion : 1); easing.type: Easing.OutCubic }
  }
}
