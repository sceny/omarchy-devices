import QtQuick
import qs.Commons

// A QR code (Model.qrGrid): black on white with its quiet zone, whatever the
// theme, so a phone's camera reads it. Used by every code the panel shows:
// the app's store page (Add a device) and pairing for the screen (Screen
// and apps).
Rectangle {
  id: root
  property var grid: null
  property int cell: 4
  readonly property int modules: grid ? grid.size + 4 : 0
  width: modules * cell
  height: width
  color: "white"
  radius: Style.space(2)

  onGridChanged: canvas.requestPaint()

  Canvas {
    id: canvas
    anchors.fill: parent
    // A paint asked while hidden (a code is hidden while another is made)
    // is skipped: paint again when it shows.
    onVisibleChanged: if (visible) requestPaint()
    onWidthChanged: requestPaint()
    onPaint: {
      var ctx = getContext("2d")
      ctx.reset()
      ctx.fillStyle = "white"
      ctx.fillRect(0, 0, width, height)
      var g = root.grid
      if (!g) return
      ctx.fillStyle = "black"
      for (var r = 0; r < g.size; r++)
        for (var c = 0; c < g.size; c++)
          if (g.dark[r][c]) ctx.fillRect((c + 2) * root.cell, (r + 2) * root.cell, root.cell, root.cell)
    }
  }
}
