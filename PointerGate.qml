import QtQuick

// Whether a hover is the pointer's own move. Content that scrolls, folds or
// slides under a pointer at rest makes Qt send the row now beneath it an
// enter: that must not take the keyboard cursor. A page feeds `at` from a
// HoverHandler on an ancestor of its content (one on a sibling below it is
// never delivered a hover), and every hover that moves a cursor asks
// `moved()` first: true once per real move of the pointer, never for content
// moving under it.
QtObject {
  id: gate
  property point at: Qt.point(-1, -1)
  property point seen: Qt.point(-1, -1)

  function moved() {
    var m = Math.abs(at.x - seen.x) > 0.5 || Math.abs(at.y - seen.y) > 0.5
    seen = at
    return m
  }
  // A key moved the cursor: a move made before it is spent.
  function settle() { seen = at }

  // The same question for a hover that knows where the pointer is (`p`, in
  // the window's coordinates). A row hears the pointer before the HoverHandler
  // does, so `at` is where the pointer stood before this event: a real move
  // differs from it, content settling under a pointer at rest does not,
  // whatever the pointer touched last.
  function movedTo(p) { return Math.abs(p.x - at.x) > 0.5 || Math.abs(p.y - at.y) > 0.5 }
}
