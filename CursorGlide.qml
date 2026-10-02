import QtQuick
import qs.Commons
import qs.Ui
import "Model.js" as Model

// The keyboard cursor, drawn once for a page: a highlight behind the page
// that goes to the row, tile or card holding the cursor (its CursorStop).
// Moved by a key (`keyedAt`, just now), it slides there at the panel's pace;
// moved by the pointer, or appearing, it lands at once, so it never trails
// the mouse. Every frame it keeps to its item, so a fold opening or the page
// sliding carries it along. Items under it draw no cursor of their own.
Item {
  id: glide
  property Item target: null
  property bool shown: true
  property real motion: 1
  property color foreground: Color.foreground
  // When a key last moved the cursor (Date.now()); set by the page.
  property double keyedAt: 0

  readonly property bool active: shown && !!target && target.visible
  opacity: active ? 1 : 0
  visible: opacity > 0
  Behavior on opacity { NumberAnimation { duration: Model.MOTION.inMs * glide.motion; easing.type: Easing.OutCubic } }

  // The slide in progress: from where it was, to where its item is now.
  property rect from: Qt.rect(0, 0, 0, 0)
  property double startedAt: 0
  property bool placed: false

  onTargetChanged: {
    if (target && placed && opacity > 0 && Date.now() - keyedAt < 400) {
      from = Qt.rect(x, y, width, height)
      startedAt = Date.now()
    } else {
      startedAt = 0
    }
    track()
  }
  // Faded out: the next time it shows, it lands where it goes.
  onOpacityChanged: if (opacity === 0) placed = false

  function track() {
    if (!target || !parent) return
    var p = target.mapToItem(parent, 0, 0)
    var tx = p.x, ty = p.y, tw = target.width, th = target.height
    var span = Math.max(1, Model.MOTION.inMs * motion)
    var t = startedAt > 0 ? Math.min(1, (Date.now() - startedAt) / span) : 1
    if (t >= 1) {
      startedAt = 0
      x = tx; y = ty; width = tw; height = th
    } else {
      var e = 1 - Math.pow(1 - t, 3)
      x = from.x + (tx - from.x) * e
      y = from.y + (ty - from.y) * e
      width = from.width + (tw - from.width) * e
      height = from.height + (th - from.height) * e
    }
    placed = true
  }
  FrameAnimation { running: glide.active || glide.visible; onTriggered: glide.track() }

  CursorSurface {
    anchors.fill: parent
    hasCursor: true
    foreground: glide.foreground
    radius: glide.target && glide.target.radius !== undefined ? glide.target.radius : Style.cornerRadius
  }
}
