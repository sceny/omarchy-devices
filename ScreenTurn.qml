import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Wayland
import qs.Commons
import qs.Ui
import "Model.js" as Model

// A docked screen turning or folding (the bridge's screen-watch), as Android
// turns its own screen: a still of the window's last picture turns with the
// device (a quarter or half turn) or morphs into the new shape (a fold),
// softening as it moves, while the window, hidden, moves under it; once the
// card has arrived and the device's new picture is there, the window shows
// under it and the still crossfades into it. Without a still (it came too
// late), a plain card in the panel's look does the same. One per bar, on
// that bar's screen; it never takes input.
PanelWindow {
  id: turn

  property var phone: null
  property Item anchorItem: null
  property color foreground: Color.foreground
  property string fontFamily: Style.font.family
  property real motion: 1

  readonly property var barWindow: anchorItem && anchorItem.QsWindow ? anchorItem.QsWindow.window : null
  readonly property var ev: phone ? phone.screenTurn : null

  // Mapped, empty and click-through, while a docked screen is open (or a
  // demo screen is ready): a layer mapped on demand misses the first frames
  // and fades in itself, so the card would arrive late and see-through.
  readonly property bool armed: !!phone && (Object.keys(phone.screenWatchers).length > 0
    || (phone.demo && (phone.demoScreenKind === "ready" || phone.demoScreenKind === "opens")))
  screen: barWindow ? barWindow.screen : null
  visible: armed || journey.running || fade.running || card.opacity > 0.01
  anchors { top: true; bottom: true; left: true; right: true }
  color: "transparent"
  WlrLayershell.namespace: "sceny-devices-turn"
  WlrLayershell.layer: WlrLayer.Overlay
  WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
  exclusionMode: ExclusionMode.Ignore
  mask: Region {}

  // Checked here, not in a binding of its own: a binding may not have
  // caught up when the event arrives, and the first turn was missed.
  onEvChanged: if (ev && screen && ev.monitor === screen.name) start()

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

  // The still, when there is one (a file in memory the bridge removes).
  property string still: ""
  property real soft: 0

  function start() {
    if (!ev || !ev.from || !ev.to) return
    journey.stop()
    still = ev.still ? "file://" + ev.still : ""
    soft = 0
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
    fade.stop()
    arrived = false
    revealed = false
    card.opacity = 1
    holdLimit.restart()
    journey.start()
  }
  property real toX: 0
  property real toY: 0

  // The card crossfades into the window once it has arrived and the window
  // shows under it (the watcher, when the new picture is there); it holds
  // while the picture is late. Without a still, nothing is held back: the
  // plain card fades as soon as the window shows.
  property bool arrived: false
  property bool revealed: false
  function fadeWhenBoth() { if (revealed && (arrived || still === "") && !fade.running && card.opacity > 0) fade.start() }
  Connections {
    target: turn.phone
    function onScreenRevealed(id) {
      if (!turn.ev || String(turn.ev.device || "") !== id) return
      turn.revealed = true
      turn.fadeWhenBoth()
    }
  }
  // The window shows at most this late (the watcher's own limit, and a beat).
  Timer { id: holdLimit; interval: 1700; onTriggered: { turn.revealed = true; turn.fadeWhenBoth() } }
  NumberAnimation { id: fade; target: card; property: "opacity"; to: 0; duration: (turn.still !== "" ? Model.MOTION.inMs : Model.MOTION.outMs) * turn.motion; easing.type: Easing.InOutQuad }

  SequentialAnimation {
    id: journey
    ParallelAnimation {
      NumberAnimation { target: turn; property: "cx"; to: turn.toX; duration: (Model.MOTION.outMs + Model.MOTION.inMs) * turn.motion; easing.type: Easing.OutCubic }
      NumberAnimation { target: turn; property: "cy"; to: turn.toY; duration: (Model.MOTION.outMs + Model.MOTION.inMs) * turn.motion; easing.type: Easing.OutCubic }
      NumberAnimation { target: turn; property: "cw"; to: turn.toW; duration: (Model.MOTION.outMs + Model.MOTION.inMs) * turn.motion; easing.type: Easing.OutCubic }
      NumberAnimation { target: turn; property: "ch"; to: turn.toH; duration: (Model.MOTION.outMs + Model.MOTION.inMs) * turn.motion; easing.type: Easing.OutCubic }
      NumberAnimation { target: turn; property: "rot"; to: turn.toRot; duration: (Model.MOTION.outMs + Model.MOTION.inMs) * turn.motion; easing.type: Easing.OutCubic }
      NumberAnimation { target: turn; property: "sc"; to: turn.toSc; duration: (Model.MOTION.outMs + Model.MOTION.inMs) * turn.motion; easing.type: Easing.OutCubic }
      // Softer while it moves, as a picture in motion is.
      SequentialAnimation {
        NumberAnimation { target: turn; property: "soft"; to: 1; duration: Model.MOTION.outMs * turn.motion; easing.type: Easing.OutQuad }
        NumberAnimation { target: turn; property: "soft"; to: 0.35; duration: Model.MOTION.inMs * turn.motion; easing.type: Easing.InOutQuad }
      }
    }
    ScriptAction { script: { turn.arrived = true; turn.fadeWhenBoth() } }
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

    // The still: the window's last picture, inside the card's border (the
    // window sits there too), filling it (a morph crops, never stretches).
    Image {
      id: stillImage
      anchors.fill: parent
      anchors.margins: Math.max(1, Style.space(2))
      visible: false
      source: turn.still
      cache: false
      asynchronous: false
      fillMode: Image.PreserveAspectCrop
    }
    MultiEffect {
      anchors.fill: stillImage
      source: stillImage
      visible: turn.still !== "" && stillImage.status === Image.Ready
      blurEnabled: true
      blurMax: 32
      blur: 0.55 * turn.soft
      brightness: -0.12 * turn.soft
      saturation: -0.15 * turn.soft
    }

    // No still: the device's glyph, upright and its own size while the card
    // turns and scales around it.
    Text {
      visible: turn.still === "" || stillImage.status !== Image.Ready
      anchors.centerIn: parent
      rotation: -turn.rot
      scale: turn.sc > 0 ? 1 / turn.sc : 1
      text: Model.GLYPH.screen
      color: turn.foreground
      font.family: turn.fontFamily
      font.pixelSize: Style.font.icon * 2
    }
  }
}
