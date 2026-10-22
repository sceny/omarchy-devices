import QtQuick
import qs.Commons
import qs.Ui

// Every text field in the plugin is one of these, so Esc steps back the same
// way everywhere, one thing at a time:
// 1. something floating over the field (`floating`: suggestions) closes,
//    and what was typed stays (`closeFloating`);
// 2. else the field's own step (`escapeStep`): "keep" (a draft stays: a reply, a text to
//    send), "clear" (a search empties first), or "revert" (a setting goes
//    back to `savedText`);
// 3. then the field is left (`steppedOut`): its owner releases the focus, and the
//    page's own Esc takes over from there.
// Fields set these, never their own Keys.onEscapePressed.
//
// `multiline` (a text message): the text wraps, Shift+Enter ends a line, Enter
// still accepts, and the field grows with its text up to `maxLines`, then
// scrolls. It grows at the owner's pace (`growMs`), never in a jump.
//
// It is a TextEdit, not a TextField: a TextField (QQuickTextInput) reads the
// whole clipboard text whenever it becomes editable or the clipboard changes
// (q_canPasteChanged: mimeData()->text()), with no limit on size or time, so
// another program's clipboard could stall the shell. A TextEdit asks the
// clipboard only which formats it offers (QQuickTextControl::canPaste), and
// reads the text when the user pastes. The look is Omarchy's TextField's.
//
// Nothing here is a party to a Wayland data transfer (docs/architecture/001):
// Qt's own copy, cut, paste and selection would make the shell serve or read a
// selection, with a blocking call and no bound. Qt makes the shell the primary
// selection's owner whenever one of its keys or clicks leaves a selection
// standing (setClipboardSelection). So:
// - Ctrl+C, Ctrl+X, Ctrl+V and their Insert keys go through `Clipboard` (the one
//   door: bounded wl-copy and wl-paste out of the shell);
// - the selection is this field's: Ctrl+A, Shift with a movement key (every
//   StandardKey.Select*), and the mouse (a drag, Shift+click, a word on a double
//   click, all on a triple) move it with `select`, which touches no clipboard;
// - while a selection stands, a key reaches Qt only if it removes it (text,
//   Backspace, Delete) or is a modifier alone; Left and Right collapse it here,
//   and any other key finds it gone (`deselect`);
// - the mouse never reaches the TextEdit, so a middle click pastes nothing.
// A TextEdit takes no drops, so nothing here is a drop target.
//
// Pasted text is cut to the room left before Qt sees it (`_insert`): Qt inserts
// a paste whole, and a few megabytes stall the shell for seconds (line breaks
// cost far more).
FocusScope {
  id: field

  property string escapeStep: "keep"
  property string savedText: ""
  property bool floating: false
  signal closeFloating()
  signal steppedOut()
  signal accepted()

  property bool multiline: false
  property int maxLines: 5
  property int growMs: 0
  property alias text: edit.text
  property alias font: edit.font
  property alias cursorPosition: edit.cursorPosition
  property string placeholderText: ""
  // QQuickTextInput capped a field at 32767 characters; a TextEdit does not,
  // and a paste of megabytes would stall every keystroke after it.
  property int maximumLength: 32767
  property color foreground: Color.foreground
  property color accent: Color.accent
  readonly property bool hovered: hover.hovered
  function selectAll() { edit.selectAll() }

  // Where a selection key moves the cursor (-1: not one). Positions count
  // UTF-16 units, and a step never splits a surrogate pair.
  function _selectTarget(event) {
    var p = edit.cursorPosition, t = edit.text
    if (event.matches(StandardKey.SelectPreviousChar)) {
      var back = Math.max(0, p - 1)
      return back > 0 && _low(t.charCodeAt(back)) ? back - 1 : back
    }
    if (event.matches(StandardKey.SelectNextChar)) {
      var on = Math.min(edit.length, p + 1)
      return on < edit.length && _low(t.charCodeAt(on)) ? on + 1 : on
    }
    if (event.matches(StandardKey.SelectPreviousWord)) return p - t.slice(0, p).match(/\S*\s*$/)[0].length
    if (event.matches(StandardKey.SelectNextWord)) return p + t.slice(p).match(/^\S*\s*/)[0].length
    if (event.matches(StandardKey.SelectStartOfLine) || event.matches(StandardKey.SelectStartOfBlock)
        || event.matches(StandardKey.SelectStartOfDocument) || event.matches(StandardKey.SelectPreviousLine)
        || event.matches(StandardKey.SelectPreviousPage)) return 0
    if (event.matches(StandardKey.SelectEndOfLine) || event.matches(StandardKey.SelectEndOfBlock)
        || event.matches(StandardKey.SelectEndOfDocument) || event.matches(StandardKey.SelectNextLine)
        || event.matches(StandardKey.SelectNextPage)) return edit.length
    return -1
  }
  function _low(c) { return c >= 0xDC00 && c <= 0xDFFF }

  readonly property var _modifierKeys: [Qt.Key_Shift, Qt.Key_Control, Qt.Key_Meta, Qt.Key_Alt, Qt.Key_AltGr,
    Qt.Key_Super_L, Qt.Key_Super_R, Qt.Key_Hyper_L, Qt.Key_Hyper_R, Qt.Key_CapsLock, Qt.Key_NumLock, Qt.Key_ScrollLock]

  // A key Qt may have while a selection stands: one that removes it before
  // Qt's `accept:` (typed text, Backspace, Delete and its kinds, as Qt reads
  // them), or a modifier alone, which Qt ignores and which must not end the
  // selection Ctrl+C is about to copy.
  function _keepsSelection(event) {
    if (_modifierKeys.indexOf(event.key) >= 0) return true
    if (event.key === Qt.Key_Backspace && !(event.modifiers & ~Qt.ShiftModifier)) return true
    if (multiline && _newLine(event)) return true
    if (event.matches(StandardKey.Delete) || event.matches(StandardKey.DeleteStartOfWord)
        || event.matches(StandardKey.DeleteEndOfWord) || event.matches(StandardKey.DeleteEndOfLine)) return true
    var ctrl = event.modifiers & (Qt.ControlModifier | Qt.MetaModifier)
    return event.text !== "" && event.text.charCodeAt(0) >= 0x20 && event.text.charCodeAt(0) !== 0x7F && !ctrl
  }

  function _enter(event) {
    if (multiline && _newLine(event)) _insert("\n")
    else accepted()
  }

  function _newLine(event) {
    return (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) && (event.modifiers & Qt.ShiftModifier)
  }

  // The selection's fixed end: where it began.
  function _anchor() {
    if (edit.selectionStart === edit.selectionEnd) return edit.cursorPosition
    return edit.cursorPosition === edit.selectionStart ? edit.selectionEnd : edit.selectionStart
  }

  // The word at `p` (a run without spaces), for a double click.
  function _selectWord(p) {
    var t = edit.text
    edit.select(p - t.slice(0, p).match(/\S*$/)[0].length, p + t.slice(p).match(/^\S*/)[0].length)
  }

  readonly property var _breaks: new RegExp((multiline ? "[\\r\\t" : "[\\r\\n\\t") + String.fromCharCode(0x2028, 0x2029) + "]+", "g")

  // Replaces the selection with `incoming` cut to the cap, on one line.
  function _insert(incoming) {
    if (incoming === "" || incoming === undefined || incoming === null) return
    if (edit.selectionStart !== edit.selectionEnd) edit.remove(edit.selectionStart, edit.selectionEnd)
    var room = Math.max(0, maximumLength - edit.length)
    var part = incoming.slice(0, room)
    var last = part.length > 0 ? part.charCodeAt(part.length - 1) : 0
    if (last >= 0xD800 && last <= 0xDBFF) part = part.slice(0, -1)
    if (multiline) part = part.replace(/\r\n?/g, "\n")
    part = part.replace(_breaks, " ")
    var at = edit.cursorPosition
    edit.insert(at, part)
    edit.cursorPosition = at + part.length
  }

  readonly property var _borderSpec: Border.controlSpec(
    activeFocus ? "focus" : (hovered ? "hover-cursor" : "normal"), foreground, accent)
  readonly property real _padX: Style.spacing.controlPaddingX
  readonly property real _padY: Style.spacing.inputPaddingY

  implicitWidth: 120
  readonly property real _frameHeight: _padY * 2 + Border.top(_borderSpec) + Border.bottom(_borderSpec)
  readonly property real _wantHeight: multiline
    ? Math.min(Math.ceil(edit.contentHeight), Math.max(1, maxLines) * lineMetrics.lineSpacing) + _frameHeight
    : edit.implicitHeight + _frameHeight
  property real _shownHeight: _wantHeight
  Behavior on _shownHeight {
    enabled: field.multiline && field.growMs > 0
    NumberAnimation { duration: field.growMs; easing.type: Easing.OutCubic }
  }
  implicitHeight: _shownHeight
  FontMetrics { id: lineMetrics; font: edit.font }

  BorderSurface {
    anchors.fill: parent
    color: Style.controlFill(field.activeFocus, field.hovered, field.foreground, field.accent)
    borderSpec: field._borderSpec
    radius: Style.cornerRadius
  }

  Flickable {
    id: flick
    anchors.fill: parent
    anchors.leftMargin: field._padX + Border.left(field._borderSpec)
    anchors.rightMargin: field._padX + Border.right(field._borderSpec)
    anchors.topMargin: field._padY + Border.top(field._borderSpec)
    anchors.bottomMargin: field._padY + Border.bottom(field._borderSpec)
    clip: true
    interactive: field.multiline
    contentWidth: edit.width
    contentHeight: edit.height
    function ensureVisible(r) {
      if (contentX >= r.x) contentX = r.x
      else if (contentX + width <= r.x + r.width) contentX = r.x + r.width - width
      if (!field.multiline) return
      if (contentY > r.y) contentY = r.y
      else if (contentY + height < r.y + r.height) contentY = r.y + r.height - height
      contentY = Math.max(0, Math.min(contentY, contentHeight - height))
    }
    onHeightChanged: ensureVisible(edit.cursorRectangle)

    TextMetrics { id: measure; font: edit.font; text: edit.text + edit.preeditText }

    TextEdit {
      id: edit
      focus: true
      width: field.multiline ? flick.width : Math.max(flick.width, measure.advanceWidth + 4)
      height: Math.max(flick.height, contentHeight)
      textFormat: TextEdit.PlainText
      wrapMode: field.multiline ? TextEdit.WrapAtWordBoundaryOrAnywhere : TextEdit.NoWrap
      selectByMouse: false
      font.family: Style.font.family
      font.pixelSize: Style.font.body
      color: field.foreground
      selectionColor: Style.selectionFillFor(field.foreground, field.accent)
      selectedTextColor: field.foreground
      verticalAlignment: field.multiline ? TextEdit.AlignTop : TextEdit.AlignVCenter
      onCursorRectangleChanged: flick.ensureVisible(cursorRectangle)

      // Over the cap, then one line: a paste or an input method can bring
      // more text than the cap or a line break. The cap runs first, so the
      // line-break scan never reads more than the cap.
      onTextChanged: {
        var cap = Math.max(0, field.maximumLength)
        if (length > cap) {
          var at = cursorPosition
          var keep = cap
          var last = keep > 0 ? getText(keep - 1, keep).charCodeAt(0) : 0
          if (last >= 0xD800 && last <= 0xDBFF) keep--
          remove(keep, length)
          cursorPosition = Math.min(at, keep)
        }
        field._breaks.lastIndex = 0
        if (!field._breaks.test(text)) return
        var pos = cursorPosition
        text = text.replace(field._breaks, " ")
        cursorPosition = Math.min(pos, text.length)
      }

      Keys.onPressed: function(event) {
        if (event.matches(StandardKey.Paste)) {
          event.accepted = true
          Clipboard.readInto(function(incoming) { if (edit.activeFocus) field._insert(incoming) })
        } else if (event.matches(StandardKey.Copy) || event.matches(StandardKey.Cut)) {
          event.accepted = true
          if (selectionStart === selectionEnd) return
          Clipboard.copyText(selectedText)
          if (event.matches(StandardKey.Cut)) remove(selectionStart, selectionEnd)
        } else if (event.matches(StandardKey.SelectAll)) {
          event.accepted = true
          selectAll()
        } else if (field._selectTarget(event) >= 0) {
          event.accepted = true
          moveCursorSelection(field._selectTarget(event))
        } else if (event.key === Qt.Key_Direction_L || event.key === Qt.Key_Direction_R) {
          event.accepted = true
        } else if (selectionStart !== selectionEnd && !field._keepsSelection(event)) {
          if (event.matches(StandardKey.MoveToPreviousChar)) { event.accepted = true; cursorPosition = selectionStart }
          else if (event.matches(StandardKey.MoveToNextChar)) { event.accepted = true; cursorPosition = selectionEnd }
          else deselect()
        }
      }
      // The owner's own keys (Keys.onPressed, onDownPressed, ...) first.
      Keys.forwardTo: [field]
      // Enter ends the line instead of adding one; in a multiline field
      // Shift+Enter adds it.
      Keys.onReturnPressed: function(event) { event.accepted = true; field._enter(event) }
      Keys.onEnterPressed: function(event) { event.accepted = true; field._enter(event) }
      Keys.onTabPressed: function(event) { event.accepted = true }
      Keys.onBacktabPressed: function(event) { event.accepted = true }
      Keys.onEscapePressed: function(event) {
        event.accepted = true
        if (field.floating) { field.closeFloating(); return }
        if (field.escapeStep === "clear" && text !== "") { text = ""; return }
        if (field.escapeStep === "revert") text = field.savedText
        field.steppedOut()
      }
    }
  }

  Text {
    anchors.left: flick.left
    anchors.right: flick.right
    anchors.verticalCenter: field.multiline ? undefined : flick.verticalCenter
    anchors.top: field.multiline ? flick.top : undefined
    visible: edit.length === 0 && edit.preeditText === ""
    text: field.placeholderText
    font: edit.font
    color: Qt.darker(field.foreground, 1.6)
    elide: Text.ElideRight
    textFormat: Text.PlainText
  }

  HoverHandler { id: hover; cursorShape: Qt.IBeamCursor }
  // The mouse places the cursor and selects here, never through Qt's
  // selectByMouse, which would own the primary selection. It takes the middle
  // button too, and does nothing with it: no primary paste.
  MouseArea {
    anchors.fill: parent
    acceptedButtons: Qt.LeftButton | Qt.MiddleButton
    property int anchorAt: 0
    property int clicks: 0
    function _at(m) { var p = mapToItem(edit, m.x, m.y); return edit.positionAt(p.x, p.y) }
    Timer { id: clickRun; interval: Qt.styleHints.mouseDoubleClickInterval }
    onPressed: function(m) {
      if (m.button !== Qt.LeftButton) return
      edit.forceActiveFocus()
      clicks = clickRun.running ? clicks + 1 : 1
      clickRun.restart()
      var at = _at(m)
      anchorAt = clicks === 1 && (m.modifiers & Qt.ShiftModifier) ? field._anchor() : at
      if (clicks === 2) field._selectWord(at)
      else if (clicks > 2) edit.selectAll()
      else edit.select(anchorAt, at)
    }
    onPositionChanged: function(m) {
      if (clicks === 1 && (pressedButtons & Qt.LeftButton)) edit.select(anchorAt, _at(m))
    }
  }
}
