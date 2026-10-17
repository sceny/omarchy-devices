import QtQuick

// Whether a hover is the pointer's own move. Content that scrolls, folds or
// slides under a pointer at rest makes Qt send the row now beneath it an
// enter: that must not take the keyboard cursor. A page feeds `heard` from a
// HoverHandler on an ancestor of its content (one on a sibling below it is
// never delivered a hover). A row hears the pointer before that handler
// does, so a hover that moves a cursor hands its action to `take` and it
// runs only when the same event reaches the handler at a new position. The
// ask never outlives its event: no move is kept for a later hover.
QtObject {
  id: gate
  property point at: Qt.point(-1, -1)
  property var pending: null

  function take(action) {
    if (pending) return
    pending = action
    Qt.callLater(drop)
  }
  function drop() { pending = null }

  function heard(p) {
    var m = moved(p)
    at = p
    var action = pending
    pending = null
    if (m && action) action()
  }

  // The same question for a hover that knows where the pointer is (`p`, in
  // the window's coordinates) and answers at once: `at` is where the pointer
  // stood before this event, so a real move differs from it and content
  // settling under a pointer at rest does not.
  function movedTo(p) { return moved(p) }

  function moved(p) { return Math.abs(p.x - at.x) > 0.5 || Math.abs(p.y - at.y) > 0.5 }
}
