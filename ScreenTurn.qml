import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Commons
import qs.Ui
import "Model.js" as Model

// A docked screen turning or folding (the bridge's screen-watch): a card in
// the panel's look turns (a quarter or half turn) or morphs from the
// window's old place to its new one, while the window, hidden, moves under
// it; then it fades as the window shows again. One per bar, on that bar's
// screen; it never takes input.
PanelWindow {
  id: turn

  property var phone: null
  property Item anchorItem: null
  property color foreground: Color.foreground
  property string fontFamily: Style.font.family
  property real motion: 1

  readonly property var barWindow: anchorItem && anchorItem.QsWindow ? anchorItem.QsWindow.window : null
  readonly property var ev: phone ? phone.screenTurn : null
  readonly property bool mine: !!ev && !!screen && ev.monitor === screen.name

  // Mapped, empty and click-through, while a docked screen is open (or a
  // demo screen is ready): a layer mapped on demand misses the first frames
  // and fades in itself, so the card would arrive late and see-through.
  readonly property bool armed: !!phone && (Object.keys(phone.screenWatchers).length > 0
    || (phone.demo && phone.demoScreenKind === "ready"))
  screen: barWindow ? barWindow.screen : null
  visible: armed || journey.running || card.opacity > 0.01
  anchors { top: true; bottom: true; left: true; right: true }
  color: "transparent"
  WlrLayershell.namespace: "sceny-devices-turn"
  WlrLayershell.layer: WlrLayer.Overlay
  WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
  exclusionMode: ExclusionMode.Ignore
  mask: Region {}

  onEvChanged: if (mine) start()

  // The card's centre, size, turn and scale. A turn keeps the old size and
  // turns it, scaled to the new one (the same shape on its side); a morph
  // changes the size itself.
  property real cx: 0
  property real cy: 0
  property real cw: 0
  property real ch: 0
  property real rot: 0
  property real sc: 1
  property real toRot: 0
  property real toSc: 1
  property real toW: 0
  property real toH: 0

  function start() {
    if (!ev || !ev.from || !ev.to) return
    journey.stop()
    var f = ev.from, t = ev.to
    var turning = ev.kind === "turn"
    cx = f[0] + f[2] / 2; cy = f[1] + f[3] / 2
    cw = f[2]; ch = f[3]
    rot = 0; sc = 1
    toRot = turning ? ev.angle : 0
    toSc = !turning ? 1 : (Math.abs(ev.angle) === 90 ? t[2] / f[3] : t[2] / f[2])
    toW = turning ? f[2] : t[2]
    toH = turning ? f[3] : t[3]
    toX = t[0] + t[2] / 2; toY = t[1] + t[3] / 2
    card.opacity = 1
    journey.start()
  }
  property real toX: 0
  property real toY: 0

  SequentialAnimation {
    id: journey
    ParallelAnimation {
      NumberAnimation { target: turn; property: "cx"; to: turn.toX; duration: (Model.MOTION.outMs + Model.MOTION.inMs) * turn.motion; easing.type: Easing.OutCubic }
      NumberAnimation { target: turn; property: "cy"; to: turn.toY; duration: (Model.MOTION.outMs + Model.MOTION.inMs) * turn.motion; easing.type: Easing.OutCubic }
      NumberAnimation { target: turn; property: "cw"; to: turn.toW; duration: (Model.MOTION.outMs + Model.MOTION.inMs) * turn.motion; easing.type: Easing.OutCubic }
      NumberAnimation { target: turn; property: "ch"; to: turn.toH; duration: (Model.MOTION.outMs + Model.MOTION.inMs) * turn.motion; easing.type: Easing.OutCubic }
      NumberAnimation { target: turn; property: "rot"; to: turn.toRot; duration: (Model.MOTION.outMs + Model.MOTION.inMs) * turn.motion; easing.type: Easing.OutCubic }
      NumberAnimation { target: turn; property: "sc"; to: turn.toSc; duration: (Model.MOTION.outMs + Model.MOTION.inMs) * turn.motion; easing.type: Easing.OutCubic }
    }
    // The window shows again under it (the bridge, at the same beat).
    NumberAnimation { target: card; property: "opacity"; to: 0; duration: Model.MOTION.outMs * turn.motion; easing.type: Easing.InCubic }
  }

  BorderSurface {
    id: card
    opacity: 0
    width: turn.cw
    height: turn.ch
    x: turn.cx - width / 2
    y: turn.cy - height / 2
    rotation: turn.rot
    scale: turn.sc
    radius: Style.cornerRadius
    color: Qt.rgba(Color.background.r, Color.background.g, Color.background.b, 1)
    borderSpec: Border.surfaceSpec("popups", "border", Color.popups.border, Math.max(1, Style.space(2)))

    Text {
      anchors.centerIn: parent
      text: Model.GLYPH.screen
      color: turn.foreground
      font.family: turn.fontFamily
      font.pixelSize: Style.font.icon * 2
    }
  }
}
