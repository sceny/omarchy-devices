import QtQuick
import qs.Commons
import qs.Ui
import "Model.js" as Model

// The pinned apps, in their order: a row of tiles that wraps, used by the
// Apps section and the All apps page. Its order moves through Reorder as
// every order does: drag a tile (the others slide aside, it glides into the
// gap, then the order is written) or Shift+H / Shift+L (`step`). It is also
// where an app is pinned by dragging: one dragged in from elsewhere
// (`externalMove`) opens a gap where it would land and is pinned there on
// the drop (`externalDrop`); a pinned one dragged out of the row is
// unpinned. With `showEmpty`, an empty row is a box to drop into.
Item {
  id: row

  property var apps: []
  property int columns: 5
  property real gap: 0
  property bool showEmpty: false
  property string emptyText: "Drag an app here to pin it"
  // The All apps tile after the pinned ones (the section, without a recent row).
  property bool allTile: false
  property int cursorAt: -1           // the keyboard cursor's tile (`count`: the All apps tile)
  property Item glide: null
  property real motion: 1
  property var isWorking: function(app) { return false }
  property color foreground: Color.foreground
  property string fontFamily: Style.font.family

  signal activated(var app)
  signal hovered(int index)
  signal reordered(int from, int to)
  signal pinRequested(var app, int at)
  signal unpinRequested(var app)
  signal allRequested()

  readonly property int count: apps.length
  readonly property real cellWidth: (width - gap * (columns - 1)) / columns
  readonly property real cellHeight: probe.implicitHeight
  readonly property bool moving: order.moving
  // Something is being dragged in: the box lights up.
  property bool incoming: false
  // A pinned tile dragged out of the row: let go, it is unpinned.
  property bool outside: false
  readonly property int cells: count + (allTile ? 1 : 0)

  implicitHeight: cells > 0 ? Math.ceil(cells / columns) * (cellHeight + gap) - gap
    : (showEmpty ? emptyBox.height : 0)

  AppTile { id: probe; visible: false; app: ({ name: "x" }) }

  Reorder {
    id: order
    columns: row.columns
    cellWidth: row.cellWidth
    cellHeight: row.cellHeight
    gap: row.gap
    // An app coming in takes a slot of its own, after the last.
    count: row.count + (row.incoming ? 1 : 0)
    motion: row.motion
    onMoved: function(a, b) { row.reordered(a, b) }
  }

  // Shift+H / Shift+L on a pinned tile.
  function step(i, delta) { if (i >= 0 && i < count) order.step(i, delta) }

  // Where a point (in the window) falls in the row: a slot, or -1 when it
  // is not over the row.
  function slotAt(at) {
    var p = row.mapFromItem(null, at.x, at.y)
    var h = Math.max(implicitHeight, cellHeight)
    if (p.x < -gap || p.x > width + gap || p.y < -cellHeight * 0.4 || p.y > h + cellHeight * 0.4) return -1
    var col = Math.max(0, Math.min(columns - 1, Math.floor(p.x / (cellWidth + gap))))
    var r = Math.max(0, Math.floor(p.y / (cellHeight + gap)))
    return Math.max(0, Math.min(count, r * columns + col))
  }
  function isPinned(app) {
    for (var i = 0; i < apps.length; i++) if (apps[i].package === app.package) return true
    return false
  }
  // An app dragged from elsewhere is over `at`: a gap opens where it would land.
  function externalMove(app, at) {
    if (!app || isPinned(app)) return false
    var slot = slotAt(at)
    if (slot < 0) { externalCancel(); return false }
    if (!incoming) {
      incoming = true
      order.begin(count, cellWidth)
    }
    order.to = slot
    return true
  }
  // Dropped: pinned where the gap was (true), or not over the row (false).
  function externalDrop(app, at) {
    if (!incoming) return false
    var slot = order.to
    order.cancel(true)
    incoming = false
    if (slotAt(at) < 0) return false
    pinRequested(app, slot)
    return true
  }
  function externalCancel() {
    if (!incoming) return
    order.cancel(false)
    incoming = false
  }

  // Empty, on the All apps page: a box to drop an app into.
  Rectangle {
    id: emptyBox
    visible: row.showEmpty && row.cells === 0
    width: row.width
    height: Math.round(row.cellHeight * 0.75)
    radius: Style.cornerRadius
    color: row.incoming ? Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, 0.12) : "transparent"
    border.width: 1
    border.color: row.incoming ? Color.accent : Qt.rgba(row.foreground.r, row.foreground.g, row.foreground.b, 0.25)
    Behavior on color { ColorAnimation { duration: Model.MOTION.inMs * row.motion } }
    Text {
      anchors.centerIn: parent
      textFormat: Text.PlainText
      text: row.emptyText
      color: Qt.darker(row.foreground, 1.55)
      font.family: row.fontFamily
      font.pixelSize: Style.font.caption
    }
  }

  Repeater {
    model: row.apps
    AppTile {
      id: pinTile
      required property var modelData
      required property int index
      readonly property var slot: Model.gridSlot(index, row.columns, row.cellWidth, row.cellHeight, row.gap)
      x: slot.x
      y: slot.y
      width: row.cellWidth
      z: order.from === index ? 10 : 0
      transform: ReorderShift { order: order; index: pinTile.index }
      opacity: order.from === index && row.outside ? 0.45 : 1
      Behavior on opacity { NumberAnimation { duration: Model.MOTION.outMs * row.motion } }
      app: modelData
      pinned: true
      working: row.isWorking(modelData)
      here: row.cursorAt === index
      glide: row.glide
      motion: row.motion
      foreground: row.foreground
      fontFamily: row.fontFamily
      dragEnabled: true
      onActivated: row.activated(modelData)
      onPinToggled: row.unpinRequested(modelData)
      onHovered: row.hovered(index)
      onDragStarted: { row.outside = false; order.begin(index, row.cellWidth) }
      onDragMoved: function(dx, dy, at) {
        row.outside = row.slotAt(at) < 0
        if (row.outside) { order.offsetX = dx; order.offsetY = dy; order.to = order.count - 1 }
        else order.dragBy(dx, dy)
      }
      onDragEnded: function(at) {
        if (row.slotAt(at) < 0) {
          row.outside = false
          order.cancel(true)
          row.unpinRequested(modelData)
        } else order.release()
      }
    }
  }

  // The rest of the apps, after the pinned ones (no recent row).
  AppTile {
    visible: row.allTile
    // One place on while an app comes in, as the pinned ones slide.
    readonly property var slot: Model.gridSlot(row.count + (row.incoming ? 1 : 0), row.columns, row.cellWidth, row.cellHeight, row.gap)
    x: slot.x
    y: slot.y
    Behavior on x { NumberAnimation { duration: Model.MOTION.inMs * row.motion; easing.type: Easing.OutCubic } }
    Behavior on y { NumberAnimation { duration: Model.MOTION.inMs * row.motion; easing.type: Easing.OutCubic } }
    width: row.cellWidth
    canPin: false
    app: ({ name: "All apps", glyph: Model.GLYPH.apps, icon: "" })
    here: row.cursorAt === row.count
    glide: row.glide
    motion: row.motion
    foreground: row.foreground
    fontFamily: row.fontFamily
    onActivated: row.allRequested()
    onHovered: row.hovered(row.count)
  }
}
