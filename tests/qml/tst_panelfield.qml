import QtQuick
import QtTest
import "."

// Runs against PanelField.qml copied next to a stub Clipboard (tests/test_panelfield.py).
TestCase {
  id: tc
  name: "PanelField"
  width: 300; height: 60
  visible: true
  when: windowShown

  Component { id: fieldC; PanelField { width: 280; height: 40 } }
  property var field: null

  function make(txt, pos) {
    if (field) field.destroy()
    field = createTemporaryObject(fieldC, tc)
    field.text = txt
    field.forceActiveFocus()
    verify(field.activeFocus)
    field.cursorPosition = pos
    return field
  }
  function edit(item) {
    if (item.selectionStart !== undefined && item.moveCursorSelection !== undefined) return item
    var kids = item.children || []
    if (item.contentItem) kids = kids.concat(item.contentItem.children)
    for (var i = 0; i < kids.length; i++) {
      var e = edit(kids[i])
      if (e) return e
    }
    return null
  }
  function selLen() { var e = edit(field); return e.selectionEnd - e.selectionStart }

  function test_shift_keys_leave_no_selection_standing() {
    var f = make("one two three", 4)
    keyClick(Qt.Key_Right, Qt.ShiftModifier)
    keyClick(Qt.Key_Right, Qt.ShiftModifier)
    compare(selLen(), 2)
    keyClick(Qt.Key_Down)
    compare(selLen(), 0)
  }

  function test_ctrl_a_selects_in_the_field_and_a_plain_arrow_collapses_it() {
    var f = make("one two", 0)
    keyClick(Qt.Key_A, Qt.ControlModifier)
    compare(selLen(), 7)
    keyClick(Qt.Key_Right)
    compare(selLen(), 0)
    compare(f.cursorPosition, 7)
  }

  function test_a_key_that_is_not_text_ends_a_selection() {
    var f = make("one two", 0)
    keyClick(Qt.Key_A, Qt.ControlModifier)
    keyClick(Qt.Key_Home)
    compare(selLen(), 0)
    keyClick(Qt.Key_A, Qt.ControlModifier)
    keyClick(Qt.Key_B, Qt.ControlModifier)
    compare(selLen(), 0)
  }

  function test_a_modifier_alone_keeps_the_selection_for_copy() {
    var f = make("one two", 0)
    keyClick(Qt.Key_A, Qt.ControlModifier)
    keyPress(Qt.Key_Control)
    compare(selLen(), 7)
    keyRelease(Qt.Key_Control)
  }

  function test_typing_replaces_the_selection() {
    var f = make("one two", 0)
    keyClick(Qt.Key_A, Qt.ControlModifier)
    keyClick(Qt.Key_X)
    compare(f.text, "x")
  }

  function test_the_mouse_places_the_cursor_and_drags_a_selection() {
    var f = make("hello world", 0)
    mouseClick(f, 150, 20, Qt.LeftButton)
    verify(f.cursorPosition > 0)
    mousePress(f, 8, 20, Qt.LeftButton)
    mouseMove(f, 60, 20)
    mouseRelease(f, 60, 20, Qt.LeftButton)
    verify(selLen() > 0)
  }

  function test_a_double_click_takes_the_whole_word_and_three_take_all() {
    var f = make("foo-bar baz", 0)
    mouseDoubleClickSequence(f, 20, 20, Qt.LeftButton)
    compare(edit(f).selectedText, "foo-bar")
    mouseClick(f, 20, 20, Qt.LeftButton)
    mouseClick(f, 20, 20, Qt.LeftButton)
    mouseClick(f, 20, 20, Qt.LeftButton)
    compare(edit(f).selectedText, "foo-bar baz")
  }

  function test_a_middle_click_reaches_nothing() {
    var f = make("hello", 5)
    Clipboard.pasted = 0
    mouseClick(f, 10, 20, Qt.MiddleButton)
    compare(f.text, "hello")
    compare(f.cursorPosition, 5)
    compare(Clipboard.pasted, 0)
  }
}
