pragma Singleton
import QtQuick
QtObject {
  property int pasted: 0
  property int copied: 0
  property string copiedText: ""
  function readInto(cb) { pasted++; cb("") }
  function copyText(t) { copied++; copiedText = t }
}
