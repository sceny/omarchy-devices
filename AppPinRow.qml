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
  property string emptyText: "Drag apps here to pin them"
  // The All apps tile at the row's right end (the section).
  property bool allTile: false
  property int cursorAt: -1           // the keyboard cursor's tile (`count`: the All apps tile)
  property Item glide: null
  property real motion: 1
  property var isWorking: function(app) { return false }
  property color foreground: Color.foreground
  property string fontFamily: Style.font.family

  signal activated(var app, bool pop)
  signal hovered(int index)
  signal reordered(int from, int to)
  signal pinRequested(var app, int at)
  signal unpinRequested(var app)
  signal allRequested()
  signal soundRequested(var app)       // an open app's badge (#129)

  readonly property int count: apps.length
  readonly property real cellWidth: (width - gap * (columns - 1)) / columns
  readonly property real cellHeight: probe.implicitHeight
  readonly property bool moving: pinOrder.moving
  // Something is being dragged in: the box lights up.
  property bool incoming: false
  // A pinned tile dragged out of the row: let go, it is unpinned.
  property bool outside: false
  // The tiles, kept while the pinned ones change, so the rest glide to their
  // places (one unpinned, the ones after it slide back, a line up included).
  KeyedApps { id: pinModel; apps: row.apps }
  // A drop already slid the tiles where the new order puts them: the order
  // is written with them landing there at once.
  property bool settling: false
  function settle(write) {
    settling = true
    pinOrder.cancel(true)
    write()
    settling = false
  }
  // Size animations are for the user's own changes: off while the page appears.
  property bool animate: true
  // The slots in use now, an app coming in included: a tile that goes to a
  // new line takes its room at once, the rows below moving with it, not on
  // the drop.
  readonly property int cells: allTile ? Model.allAppsSlot(count, columns, incoming) + 1 : count + (incoming && count > 0 ? 1 : 0)
  readonly property real fullHeight: cells > 0 ? Math.ceil(cells / columns) * (cellHeight + gap) - gap
    : (showEmpty ? emptyBox.height : 0)

  implicitHeight: shownHeight
  property real shownHeight: fullHeight
  Behavior on shownHeight { enabled: row.animate; NumberAnimation { duration: Model.MOTION.inMs * row.motion; easing.type: Easing.OutCubic } }

  AppTile { id: probe; visible: false; app: ({ name: "x" }) }

  Reorder {
    id: pinOrder
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
  function step(i, delta) { if (i >= 0 && i < count) pinOrder.step(i, delta) }

  // Where a point (in the window) falls in the row: a slot, or -1 when it
  // is not over the row.
  function slotAt(at) {
    var p = row.mapFromItem(null, at.x, at.y)
    var h = Math.max(fullHeight, cellHeight)
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
      pinOrder.begin(count, cellWidth)
    }
    pinOrder.to = slot
    return true
  }
  // Dropped: pinned where the gap was (true), or not over the row (false).
  function externalDrop(app, at) {
    if (!incoming) return false
    var slot = pinOrder.to
    if (slotAt(at) < 0) { externalCancel(); return false }
    settle(function() { row.incoming = false; row.pinRequested(app, slot) })
    return true
  }
  function externalCancel() {
    if (!incoming) return
    pinOrder.cancel(false)
    incoming = false
  }

  // Empty, on the All apps page: a box to drop an app into.
  Rectangle {
    id: emptyBox
    visible: row.showEmpty && row.count === 0 && !row.allTile
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
    model: pinModel
    AppTile {
      id: pinTile
      required property string json
      required property int index
      readonly property var modelData: JSON.parse(json)
      readonly property var slot: Model.gridSlot(index, row.columns, row.cellWidth, row.cellHeight, row.gap)
      x: slot.x
      y: slot.y
      readonly property bool glides: row.animate && !row.settling && !pinOrder.committing && !pinOrder.moving
      Behavior on x { enabled: pinTile.glides; NumberAnimation { duration: Model.MOTION.inMs * row.motion; easing.type: Easing.OutCubic } }
      Behavior on y { enabled: pinTile.glides; NumberAnimation { duration: Model.MOTION.inMs * row.motion; easing.type: Easing.OutCubic } }
      width: row.cellWidth
      z: pinOrder.from === index ? 10 : 0
      transform: ReorderShift { order: pinOrder; index: pinTile.index }
      opacity: pinOrder.from === index && row.outside ? 0.45 : 1
      Behavior on opacity { NumberAnimation { duration: Model.MOTION.outMs * row.motion } }
      app: modelData
      pinned: true
      working: row.isWorking(modelData)
      here: row.visible && row.cursorAt === index
      glide: row.glide
      motion: row.motion
      foreground: row.foreground
      fontFamily: row.fontFamily
      dragEnabled: true
      onActivated: function(pop) { row.activated(modelData, pop) }
      onSoundRequested: row.soundRequested(modelData)
      onPinToggled: row.unpinRequested(modelData)
      onHovered: row.hovered(index)
      onDragStarted: { row.outside = false; pinOrder.begin(index, row.cellWidth) }
      onDragMoved: function(dx, dy, at) {
        row.outside = row.slotAt(at) < 0
        if (row.outside) { pinOrder.offsetX = dx; pinOrder.offsetY = dy; pinOrder.to = pinOrder.count - 1 }
        else pinOrder.dragBy(dx, dy)
      }
      onDragEnded: function(at) {
        if (row.slotAt(at) < 0) {
          var app = modelData
          row.outside = false
          row.settle(function() { row.unpinRequested(app) })
        } else pinOrder.release()
      }
    }
  }

  // The rest of the apps, after the pinned ones (no recent row).
  AppTile {
    visible: row.allTile
    // At the row's right end; one place on when the pins reach it (an app
    // coming in included), as the pinned ones slide.
    readonly property var slot: Model.gridSlot(Model.allAppsSlot(row.count, row.columns, row.incoming), row.columns, row.cellWidth, row.cellHeight, row.gap)
    x: slot.x
    y: slot.y
    Behavior on x { NumberAnimation { duration: Model.MOTION.inMs * row.motion; easing.type: Easing.OutCubic } }
    Behavior on y { NumberAnimation { duration: Model.MOTION.inMs * row.motion; easing.type: Easing.OutCubic } }
    width: row.cellWidth
    canPin: false
    app: ({ name: "All apps", glyph: Model.GLYPH.apps, icon: "" })
    here: row.visible && row.allTile && row.cursorAt === row.count
    glide: row.glide
    motion: row.motion
    foreground: row.foreground
    fontFamily: row.fontFamily
    onActivated: row.allRequested()
    onHovered: row.hovered(row.count)
  }
}
