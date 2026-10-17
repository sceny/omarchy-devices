pragma Singleton
import QtQuick
QtObject {
  readonly property real cornerRadius: 4
  readonly property var font: ({ family: "sans-serif", body: 14 })
  readonly property var spacing: ({ controlPaddingX: 8, inputPaddingY: 4 })
  function controlFill(focus, hover, fg, accent) { return "#202020" }
  function selectionFillFor(fg, accent) { return "#335588" }
}
