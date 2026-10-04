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

  // Along which axis items sit: "y" (rows) or "x" (tabs). With `columns`
  // set, the items sit in a grid of cells (the shortcut tiles): a drag moves
  // in both directions and lands in the nearest cell.
  property string axis: "y"
  property int columns: 0
  property real cellWidth: 0
  property real cellHeight: 0
  readonly property bool grid: columns > 0
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
  // In a grid, the moving item's offset in both directions.
  property real offsetX: 0
  property real offsetY: 0
  property real movingExtent: 0
  // True for the instant the order is written: the items drop their shifts
  // without animating, in the same frame they are rebuilt in their places.
  property bool committing: false
  readonly property bool moving: from >= 0

  signal moved(int from, int to)

  function extent(i) { return extentOf ? extentOf(i) : movingExtent }

  function begin(i, size) {
    glide.stop()
    gridGlide.stop()
    from = i
    to = i
    offset = 0
    offsetX = 0
    offsetY = 0
    movingExtent = size !== undefined ? size : (extentOf ? extentOf(i) : itemSize)
  }

  // A drag moved the item by `off`: where it would land, by the middles of
  // the items it passes.
  function dragTo(off) {
    if (from < 0) return
    offset = off
    to = Model.reorderTarget(from, off, count, extent, gap)
  }

  // In a grid: moved by dx, dy; it would land in the nearest cell.
  function dragBy(dx, dy) {
    if (from < 0) return
    offsetX = dx
    offsetY = dy
    to = Model.gridTarget(from, dx, dy, count, columns, cellWidth, cellHeight, gap)
  }
  function cell(k) { return Model.gridSlot(k, columns, cellWidth, cellHeight, gap) }
  // Item `i`'s shift in a grid, while the moving one would land at `to`.
  function shiftX(i) { if (from < 0 || i === from) return 0; return cell(Model.reorderSlot(i, from, to)).x - cell(i).x }
  function shiftY(i) { if (from < 0 || i === from) return 0; return cell(Model.reorderSlot(i, from, to)).y - cell(i).y }

  // Where the moving item ends up, from its own place.
  function offsetFor(a, b) { return Model.reorderOffset(a, b, extent, gap) }

  function release() {
    if (from < 0) return
    if (grid) {
      gridX.from = offsetX
      gridX.to = cell(to).x - cell(from).x
      gridY.from = offsetY
      gridY.to = cell(to).y - cell(from).y
      gridGlide.restart()
      return
    }
    glide.from = offset
    glide.to = offsetFor(from, to)
    glide.restart()
  }

  // The keyboard: one step, gliding like a drop.
  function step(i, delta, size) {
    if (grid) {
      if (moving || i < 0 || i >= count) return
      var g = Math.max(0, Math.min(count - 1, i + delta))
      if (g === i) return
      begin(i, size)
      to = g
      release()
      return
    }
    if (moving || i < 0 || i >= count) return
    var t = Math.max(0, Math.min(count - 1, i + delta))
    if (t === i) return
    begin(i, size)
    to = t
    release()
  }

  // How far item `i` slides aside for the moving one.
  function shift(i) { return Model.reorderShift(i, from, to, movingExtent + gap) }

  // Ends a move without writing it: an item dragged in from elsewhere that
  // went away (the others slide back), or one dragged out and taken away
  // (`settled`: the others stay where they slid, the list is rebuilt there).
  function cancel(settled) {
    glide.stop()
    gridGlide.stop()
    committing = settled === true
    from = -1
    to = -1
    offset = 0
    offsetX = 0
    offsetY = 0
    committing = false
  }

  // Writes the move once the item is in place; the items are rebuilt where
  // the new order puts them, which is where they already are.
  function commit() {
    var a = from, b = to
    committing = true
    from = -1
    to = -1
    offset = 0
    offsetX = 0
    offsetY = 0
    if (a >= 0 && b >= 0 && a !== b) moved(a, b)
    committing = false
  }

  NumberAnimation {
    id: glide
    target: order
    property: "offset"
    duration: Model.MOTION.inMs * order.motion
    easing.type: Easing.OutCubic
    onFinished: order.commit()
  }
  ParallelAnimation {
    id: gridGlide
    NumberAnimation { id: gridX; target: order; property: "offsetX"; duration: Model.MOTION.inMs * order.motion; easing.type: Easing.OutCubic }
    NumberAnimation { id: gridY; target: order; property: "offsetY"; duration: Model.MOTION.inMs * order.motion; easing.type: Easing.OutCubic }
    onFinished: order.commit()
  }
}
