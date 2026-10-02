import QtQuick

// Marks its parent (a row, a tile, a card) as a place the keyboard cursor
// stops: while `here`, the page's CursorGlide draws the cursor there. The
// parent draws no cursor of its own (its hasCursor stays false).
Item {
  id: stop
  property bool here: false
  property Item glide: null
  function claim() {
    if (!glide) return
    if (here) { glide.target = parent; return }
    // Let go a moment later, and only if no other stop has claimed it: the
    // cursor moving makes one stop "not here" and the next "here", in either
    // order, and a gap between would make the glide land instead of slide.
    Qt.callLater(function() { if (!stop.here && stop.glide && stop.glide.target === stop.parent) stop.glide.target = null })
  }
  onHereChanged: claim()
  onGlideChanged: claim()
  Component.onCompleted: claim()
}
