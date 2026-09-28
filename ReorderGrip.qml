import QtQuick
import QtQuick.Layouts
import qs.Commons
import "Model.js" as Model

// The handle a row is dragged by, to move it in its order (Reorder). The
// row follows the pointer; on release it glides into place.
Text {
  id: grip
  property Reorder order: null
  property int index: -1
  // The row that moves, for its height.
  property Item item: null
  property color foreground: Color.foreground
  property color dim: Qt.darker(foreground, 1.55)
  property string fontFamily: Style.font.family

  text: Model.GLYPH.grip
  color: area.containsMouse || area.pressed ? foreground : dim
  font.family: fontFamily
  font.pixelSize: Style.font.icon
  Layout.alignment: Qt.AlignVCenter

  MouseArea {
    id: area
    anchors.fill: parent
    anchors.margins: -Style.space(4)
    enabled: grip.index >= 0 && !!grip.order
    hoverEnabled: true
    // The page's own scrolling does not take the drag away.
    preventStealing: true
    cursorShape: pressed ? Qt.ClosedHandCursor : Qt.OpenHandCursor
    property real start: 0
    // Scene coordinates: the pointer's place, however far the row moved.
    onPressed: function(m) {
      if (grip.order.moving) return
      start = mapToItem(null, m.x, m.y).y
      grip.order.begin(grip.index, grip.item ? grip.item.height : grip.height)
    }
    onPositionChanged: function(m) { if (pressed && grip.order.from === grip.index) grip.order.dragTo(mapToItem(null, m.x, m.y).y - start) }
    onReleased: if (grip.order.from === grip.index) grip.order.release()
    onCanceled: if (grip.order.from === grip.index) { grip.order.to = grip.index; grip.order.release() }
  }
}
