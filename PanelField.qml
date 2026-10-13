import QtQuick
import Quickshell
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
// It is a TextEdit, not a TextField: a TextField (QQuickTextInput) reads the
// whole clipboard text whenever it becomes editable or the clipboard changes
// (q_canPasteChanged: mimeData()->text()), with no limit on size or time, so
// another program's clipboard could stall the shell. A TextEdit asks the
// clipboard only which formats it offers (QQuickTextControl::canPaste), and
// reads the text when the user pastes. The look is Omarchy's TextField's.
//
// Pasted text is cut to the room left before Qt sees it: Qt inserts a paste,
// a middle click's selection or a drop whole, and a few megabytes stall the
// shell for seconds (line breaks cost far more). So Ctrl+V and Shift+Insert
// are handled here (`_insert`; the clipboard is read at that key and nowhere
// else), a middle click on the field does nothing (Quickshell cannot read the
// primary selection) and a drop onto it is refused.
FocusScope {
  id: field

  property string escapeStep: "keep"
  property string savedText: ""
  property bool floating: false
  signal closeFloating()
  signal steppedOut()
  signal accepted()

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

  readonly property var _breaks: new RegExp("[\\r\\n\\t" + String.fromCharCode(0x2028, 0x2029) + "]+", "g")

  // Replaces the selection with `incoming` cut to the cap, on one line.
  function _insert(incoming) {
    if (incoming === "" || incoming === undefined || incoming === null) return
    if (edit.selectionStart !== edit.selectionEnd) edit.remove(edit.selectionStart, edit.selectionEnd)
    var room = Math.max(0, maximumLength - edit.length)
    var part = incoming.slice(0, room)
    var last = part.length > 0 ? part.charCodeAt(part.length - 1) : 0
    if (last >= 0xD800 && last <= 0xDBFF) part = part.slice(0, -1)
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
  implicitHeight: edit.implicitHeight + _padY * 2 + Border.top(_borderSpec) + Border.bottom(_borderSpec)

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
    interactive: false
    contentWidth: edit.width
    contentHeight: edit.height
    function ensureVisible(r) {
      if (contentX >= r.x) contentX = r.x
      else if (contentX + width <= r.x + r.width) contentX = r.x + r.width - width
    }

    TextMetrics { id: measure; font: edit.font; text: edit.text + edit.preeditText }

    TextEdit {
      id: edit
      focus: true
      width: Math.max(flick.width, measure.advanceWidth + 4)
      height: Math.max(flick.height, contentHeight)
      textFormat: TextEdit.PlainText
      wrapMode: TextEdit.NoWrap
      selectByMouse: true
      font.family: Style.font.family
      font.pixelSize: Style.font.body
      color: field.foreground
      selectionColor: Style.selectionFillFor(field.foreground, field.accent)
      selectedTextColor: field.foreground
      verticalAlignment: TextEdit.AlignVCenter
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
        if (!event.matches(StandardKey.Paste)) return
        event.accepted = true
        field._insert(Quickshell.clipboardText)
      }
      // The owner's own keys (Keys.onPressed, onDownPressed, ...) first.
      Keys.forwardTo: [field]
      // Enter ends the line instead of adding one.
      Keys.onReturnPressed: function(event) { event.accepted = true; field.accepted() }
      Keys.onEnterPressed: function(event) { event.accepted = true; field.accepted() }
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

    MouseArea {
      anchors.fill: edit
      acceptedButtons: Qt.MiddleButton
    }

    DropArea {
      anchors.fill: edit
      onDropped: function(drop) { drop.accepted = false }
    }
  }

  Text {
    anchors.left: flick.left
    anchors.right: flick.right
    anchors.verticalCenter: flick.verticalCenter
    visible: edit.length === 0 && edit.preeditText === ""
    text: field.placeholderText
    font: edit.font
    color: Qt.darker(field.foreground, 1.6)
    elide: Text.ElideRight
    textFormat: Text.PlainText
  }

  HoverHandler { id: hover; cursorShape: Qt.IBeamCursor }
  TapHandler { onTapped: edit.forceActiveFocus() }
}
