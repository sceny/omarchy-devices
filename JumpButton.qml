import QtQuick
import qs.Commons
import qs.Ui
import "Model.js" as Model

// A long list's way back to its end: a glassy pill, an arrow and the list's
// name, floating over the list at the edge it jumps to (`edge`: "top" or
// "bottom" on screen). It shows once the list is scrolled away from that
// end (Model.jumpShown) and fades as it comes back, so it never moves the
// layout. A click glides the list there at the panel's pace.
//
// Declare it inside the Flickable (or ListView) it scrolls; it places
// itself over the view, not in the content.
Item {
  id: jump
  property Flickable flickable: null
  property string edge: "top"
  property string label: ""
  property string tooltipText: ""
  property color foreground: Color.foreground
  property color background: Color.background
  property string fontFamily: Style.font.family
  property real motion: 1
  // Off while the list is not the user's to scroll (a page changing).
  property bool allowed: true

  readonly property real distance: flickable
    ? Model.jumpDistance(edge, flickable.contentY, flickable.originY, flickable.contentHeight, flickable.height) : 0
  readonly property bool showing: allowed && !!flickable && flickable.visible
    && (glide.running ? false : Model.jumpShown(distance, flickable.height))

  parent: flickable
  z: 5
  anchors.horizontalCenter: parent ? parent.horizontalCenter : undefined
  y: !parent ? 0 : edge === "bottom"
    ? parent.height - height - Style.space(10) + (showing ? 0 : Style.space(8))
    : Style.space(10) - (showing ? 0 : Style.space(8))
  width: row.implicitWidth + Style.space(24)
  height: row.implicitHeight + Style.space(12)
  opacity: showing ? 1 : 0
  visible: opacity > 0.01
  Behavior on opacity { NumberAnimation { duration: (jump.showing ? Model.MOTION.inMs : Model.MOTION.outMs) * jump.motion; easing.type: Easing.OutCubic } }
  Behavior on y { NumberAnimation { duration: Model.MOTION.inMs * jump.motion; easing.type: Easing.OutCubic } }

  // Where the edge is, worked out as the glide goes: a ListView's height is
  // an estimate until its rows are built, so the end can move under it.
  function target() {
    var f = flickable
    return edge === "bottom" ? f.originY + Math.max(0, f.contentHeight - f.height) : f.originY
  }
  function go() {
    if (!flickable) return
    glide.stop()
    glide.from = flickable.contentY
    glide.to = target()
    glide.start()
  }
  // A ListView lands on its first or last row exactly, whichever this edge
  // shows: its estimated height can leave the glide a few pixels short.
  function land() {
    var f = flickable
    if (!f || typeof f.positionViewAtBeginning !== "function") return
    var first = (edge === "top") === (f.verticalLayoutDirection !== ListView.BottomToTop)
    if (first) f.positionViewAtBeginning(); else f.positionViewAtEnd()
  }
  NumberAnimation {
    id: glide
    target: jump.flickable
    property: "contentY"
    duration: Model.MOTION.inMs * jump.motion
    easing.type: Easing.OutCubic
    onFinished: jump.land()
  }

  // Glass: the panel's colour let through, a sheen on top and a fine edge.
  Rectangle {
    anchors.fill: parent
    radius: height / 2
    color: Qt.rgba(jump.background.r, jump.background.g, jump.background.b, 0.62)
    border.width: 1
    border.color: Qt.rgba(jump.foreground.r, jump.foreground.g, jump.foreground.b, mouse.containsMouse ? 0.32 : 0.18)
    Behavior on border.color { ColorAnimation { duration: Model.MOTION.inMs * jump.motion } }
    Rectangle {
      anchors.fill: parent
      anchors.margins: 1
      radius: height / 2
      opacity: mouse.containsMouse ? 1 : 0.6
      Behavior on opacity { NumberAnimation { duration: Model.MOTION.inMs * jump.motion; easing.type: Easing.OutCubic } }
      gradient: Gradient {
        GradientStop { position: 0; color: Qt.rgba(jump.foreground.r, jump.foreground.g, jump.foreground.b, 0.14) }
        GradientStop { position: 1; color: Qt.rgba(jump.foreground.r, jump.foreground.g, jump.foreground.b, 0.03) }
      }
    }
  }

  Row {
    id: row
    anchors.centerIn: parent
    spacing: Style.space(6)
    Text {
      anchors.verticalCenter: parent.verticalCenter
      textFormat: Text.PlainText
      text: jump.edge === "bottom" ? Model.GLYPH.toBottom : Model.GLYPH.toTop
      color: jump.foreground
      font.family: jump.fontFamily
      font.pixelSize: Style.font.bodySmall
    }
    Text {
      anchors.verticalCenter: parent.verticalCenter
      textFormat: Text.PlainText
      text: jump.label
      color: jump.foreground
      font.family: jump.fontFamily
      font.pixelSize: Style.font.caption
    }
  }

  MouseArea {
    id: mouse
    anchors.fill: parent
    hoverEnabled: true
    enabled: jump.showing
    cursorShape: Qt.PointingHandCursor
    onClicked: jump.go()
  }

  PanelToolTip {
    visible: jump.tooltipText !== "" && mouse.containsMouse && jump.showing
    text: jump.tooltipText
    fontFamily: jump.fontFamily
  }
}
