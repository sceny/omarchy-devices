import QtQuick
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
// A field is editable only while it has the keyboard. Qt reads the whole
// clipboard text on every clipboard change in each editable field, shown or
// not (QQuickTextInput::q_canPasteChanged); a read-only field skips it. A
// click or a focus call still makes it editable at once.
TextField {
  id: field
  property string escapeStep: "keep"
  property string savedText: ""
  property bool floating: false
  signal closeFloating()
  signal steppedOut()

  readOnly: true
  Component.onCompleted: readOnly = !activeFocus
  // Qt moves the cursor to the end when readOnly changes: keep the clicked place.
  onActiveFocusChanged: {
    var at = cursorPosition
    readOnly = !activeFocus
    if (activeFocus) cursorPosition = at
  }

  Keys.onEscapePressed: {
    if (floating) { closeFloating(); return }
    if (escapeStep === "clear" && text !== "") { text = ""; return }
    if (escapeStep === "revert") text = savedText
    steppedOut()
  }
}
