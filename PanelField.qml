import QtQuick
import qs.Ui

// Every text field in the plugin is one of these, so Esc steps back the same
// way everywhere, one thing at a time:
// 1. something floating over the field (`floating`: suggestions) closes,
//    and what was typed stays (`closeFloating`);
// 2. else the field's own step: "keep" (a draft stays: a reply, a text to
//    send), "clear" (a search empties first), or "revert" (a setting goes
//    back to `savedText`);
// 3. then the field is left (`left`): its owner releases the focus, and the
//    page's own Esc takes over from there.
// Fields set these, never their own Keys.onEscapePressed.
TextField {
  id: field
  property string escape: "keep"
  property string savedText: ""
  property bool floating: false
  signal closeFloating()
  signal left()

  Keys.onEscapePressed: {
    if (floating) { closeFloating(); return }
    if (escape === "clear" && text !== "") { text = ""; return }
    if (escape === "revert") text = savedText
    left()
  }
}
