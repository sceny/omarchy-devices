import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Wayland
import qs.Commons
import qs.Ui
import "Model.js" as Model

// A docked screen turning or folding (the bridge's screen-watch), as Android
// turns its own screen. The card starts with a still of the window's last
// picture and turns with the device (a quarter or half turn) or morphs into
// the new shape (a fold), softening as it moves, while the window, hidden,
// moves under it. When the device's new picture comes (a still of it, grabbed
// from the hidden window), it fades in on the card already laid out for the
// new shape, turned back by the turn still to come, so the two pictures turn
// into each other. The card arrives showing exactly the new picture; the
// window then shows under it and the card goes. Without stills, a plain card
// in the panel's look does the same. One per bar, on that bar's screen; it
// never takes input.
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
  property real toX: 0
  property real toY: 0
  // Set in start(), from the event itself: a binding on `ev` may not have
  // caught up when start() runs (a turn then played as a morph).
  property bool turning: false
  readonly property real journeyMs: (Model.MOTION.outMs + Model.MOTION.inMs) * motion

  // The stills (files in memory the bridge removes), how far the new one
  // has faded in, and how soft the picture is while it moves.
  property string oldStill: ""
  property string newStill: ""
  property real blend: 0
  property real soft: 0

  function start() {
    if (!ev || !ev.from || !ev.to) return
    journey.stop(); fade.stop(); blendIn.stop()
    turning = ev.kind === "turn"
    oldStill = ev.still ? "file://" + ev.still : ""
    newStill = ""
    blend = 0
    soft = 0
    var f = ev.from, t = ev.to
    cx = f[0] + f[2] / 2; cy = f[1] + f[3] / 2
    cw = f[2]; ch = f[3]
    rot = 0; sc = 1
    toRot = turning ? ev.angle : 0
    toSc = !turning ? 1 : (Math.abs(ev.angle) === 90 ? t[2] / f[3] : t[2] / f[2])
    toW = turning ? f[2] : t[2]
    toH = turning ? f[3] : t[3]
    toX = t[0] + t[2] / 2; toY = t[1] + t[3] / 2
    arrived = false
    revealed = false
    card.opacity = 1
    holdLimit.restart()
    journey.start()
  }

  // The new picture: it fades in over what is left of the journey (at
  // least a beat), so the card arrives showing it alone.
  function picture(path) {
    newStill = "file://" + path
    blendIn.duration = Math.max(Model.MOTION.outMs * motion, journeyMs - journey.elapsed())
    blendIn.restart()
  }
  NumberAnimation { id: blendIn; target: turn; property: "blend"; to: 1; easing.type: Easing.InOutQuad }

  // The card goes once it has arrived and the window shows under it (the
  // watcher, when the new picture is there). Showing the same picture as the
  // window, it goes quickly; a plain card or an old still crossfades.
  property bool arrived: false
  property bool revealed: false
  function fadeWhenBoth() {
    if (!revealed || !arrived || fade.running || card.opacity <= 0) return
    fade.duration = (newStill !== "" ? Model.MOTION.outMs : Model.MOTION.inMs) * motion
    fade.start()
  }
  Connections {
    target: turn.phone
    function onScreenRevealed(id) {
      if (!turn.ev || String(turn.ev.device || "") !== id) return
      turn.revealed = true
      turn.fadeWhenBoth()
    }
    function onScreenPicture(id, path) {
      if (!turn.ev || String(turn.ev.device || "") !== id || !path) return
      turn.picture(path)
    }
  }
  // The window shows at most this late (the watcher's own limit, and a beat).
  Timer { id: holdLimit; interval: 1700; onTriggered: { turn.revealed = true; turn.arrived = true; turn.fadeWhenBoth() } }
  NumberAnimation { id: fade; target: card; property: "opacity"; to: 0; easing.type: Easing.InOutQuad }

  SequentialAnimation {
    id: journey
    // How far along it is: the new picture blends in over what is left.
    property real startedAt: 0
    function elapsed() { return running ? Date.now() - startedAt : turn.journeyMs }
    onStarted: startedAt = Date.now()
    ParallelAnimation {
      NumberAnimation { target: turn; property: "cx"; to: turn.toX; duration: turn.journeyMs; easing.type: Easing.OutCubic }
      NumberAnimation { target: turn; property: "cy"; to: turn.toY; duration: turn.journeyMs; easing.type: Easing.OutCubic }
      NumberAnimation { target: turn; property: "cw"; to: turn.toW; duration: turn.journeyMs; easing.type: Easing.OutCubic }
      NumberAnimation { target: turn; property: "ch"; to: turn.toH; duration: turn.journeyMs; easing.type: Easing.OutCubic }
      NumberAnimation { target: turn; property: "rot"; to: turn.toRot; duration: turn.journeyMs; easing.type: Easing.InOutCubic }
      NumberAnimation { target: turn; property: "sc"; to: turn.toSc; duration: turn.journeyMs; easing.type: Easing.OutCubic }
      // Softer while it moves, as a picture in motion is, and sharp again
      // as it lands: it then matches the window exactly.
      SequentialAnimation {
        NumberAnimation { target: turn; property: "soft"; to: 1; duration: Model.MOTION.outMs * turn.motion; easing.type: Easing.OutQuad }
        NumberAnimation { target: turn; property: "soft"; to: 0; duration: Model.MOTION.inMs * turn.motion; easing.type: Easing.InQuad }
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

    // The pictures, inside the card's border (the window sits there too).
    Item {
      id: pictures
      anchors.fill: parent
      anchors.margins: Math.max(1, Style.space(2))
      visible: false
      clip: true

      // The old picture fills the card as it was.
      Image {
        id: oldImage
        anchors.fill: parent
        source: turn.oldStill
        cache: false
        asynchronous: false
        // Never stretched, never zoomed: a turn keeps the card's shape, so
        // the picture fills it; a fold changes it, so each picture keeps its
        // own proportions inside it (the card's colour around it).
        fillMode: turn.turning ? Image.PreserveAspectCrop : Image.PreserveAspectFit
        opacity: 1 - turn.blend
      }
      // The new one is laid out for the new shape: turned back by the turn
      // still to come (the card's rotation brings it upright), on its side
      // for a quarter turn. A fold fills the card as it morphs.
      Image {
        id: newImage
        anchors.centerIn: parent
        readonly property bool quarter: turn.turning && Math.abs(turn.toRot) === 90
        width: quarter ? parent.height : parent.width
        height: quarter ? parent.width : parent.height
        rotation: turn.turning ? -turn.toRot : 0
        source: turn.newStill
        cache: false
        asynchronous: false
        fillMode: turn.turning ? Image.PreserveAspectCrop : Image.PreserveAspectFit
        opacity: turn.blend
      }
    }
    MultiEffect {
      anchors.fill: pictures
      source: pictures
      visible: (turn.oldStill !== "" && oldImage.status === Image.Ready) || (turn.newStill !== "" && newImage.status === Image.Ready)
      blurEnabled: true
      blurMax: 32
      blur: 0.5 * turn.soft
      brightness: -0.1 * turn.soft
      saturation: -0.12 * turn.soft
    }

    // No old still: the device's glyph, upright and its own size while the
    // card turns and scales around it, until the new picture fades in.
    Text {
      visible: turn.oldStill === "" || oldImage.status !== Image.Ready
      opacity: 1 - turn.blend
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
