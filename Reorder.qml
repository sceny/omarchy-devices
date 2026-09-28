import QtQuick
import "Model.js" as Model

// One order being moved: devices, sections, bar indicators, shortcuts, tabs.
// Every way of moving an item goes through here, so they all look the same:
// a drag (begin, dragTo, release) and the keyboard (step).
//
// While an item moves, the ones between its place and where it would land
// slide aside by its size, animated (ReorderShift), so the gap shows where
// it goes. When it lets go (or at once for a step) it glides into the gap at
// the plugin's pace; only then is the new order written (`moved`). The items
// are rebuilt in the places already on screen, so nothing jumps.
Item {
  id: order
  visible: false

  // Along which axis items sit: "y" (rows) or "x" (tabs).
  property string axis: "y"
  property int count: 0
  // The space between two items.
  property real gap: 0
  property real motion: 1
  // An item's size along the axis. Unset: every item is the size of the one
  // moving (rows). Tabs pass their own widths.
  property var extentOf: null
  // A row's size, kept by the rows: for a step (arrows, keyboard) that
  // starts without an item in hand.
  property real itemSize: 0

  // The item moving (-1: none), where it would land, its live offset.
  property int from: -1
  property int to: -1
  property real offset: 0
  property real movingExtent: 0
  // True for the instant the order is written: the items drop their shifts
  // without animating, in the same frame they are rebuilt in their places.
  property bool committing: false
  readonly property bool moving: from >= 0

  signal moved(int from, int to)

  function extent(i) { return extentOf ? extentOf(i) : movingExtent }

  function begin(i, size) {
    glide.stop()
    from = i
    to = i
    offset = 0
    movingExtent = size !== undefined ? size : (extentOf ? extentOf(i) : itemSize)
  }

  // A drag moved the item by `off`: where it would land, by the middles of
  // the items it passes.
  function dragTo(off) {
    if (from < 0) return
    offset = off
    to = Model.reorderTarget(from, off, count, extent, gap)
  }

  // Where the moving item ends up, from its own place.
  function offsetFor(a, b) { return Model.reorderOffset(a, b, extent, gap) }

  function release() {
    if (from < 0) return
    glide.from = offset
    glide.to = offsetFor(from, to)
    glide.restart()
  }

  // The arrows and the keyboard: one step, gliding like a drop.
  function step(i, delta, size) {
    if (moving || i < 0 || i >= count) return
    var t = Math.max(0, Math.min(count - 1, i + delta))
    if (t === i) return
    begin(i, size)
    to = t
    release()
  }

  // How far item `i` slides aside for the moving one.
  function shift(i) { return Model.reorderShift(i, from, to, movingExtent + gap) }

  NumberAnimation {
    id: glide
    target: order
    property: "offset"
    duration: Model.MOTION.inMs * order.motion
    easing.type: Easing.OutCubic
    onFinished: {
      var a = order.from, b = order.to
      order.committing = true
      order.from = -1
      order.to = -1
      order.offset = 0
      // Rebuilds the items; they are already where the new order puts them.
      if (a >= 0 && b >= 0 && a !== b) order.moved(a, b)
      order.committing = false
    }
  }
}
