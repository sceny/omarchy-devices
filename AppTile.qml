import QtQuick
import qs.Commons
import qs.Ui
import "Model.js" as Model

// One of the device's apps: its icon and its name. A click opens it in a
// window here; while it opens, its icon is the waiting ring. Hovered, a pin
// keeps it in the Apps section (or lets it go). Used by the Apps section
// and the All apps page alike.
//
// The icon is the safe PNG the bridge wrote from decoded pixels (never a
// file from the device); without one, the name's first letter in a circle
// (an app not read yet, or one with no icon to read); in demo mode, a glyph.
Item {
  id: tile

  property var app: ({})
  property bool working: false
  property bool pinned: false
  property bool canPin: true
  property bool canForget: false      // a recent app: its ✕ takes it out of the recent ones
  property bool here: false           // the keyboard cursor is on it
  // Draggable (to pin it, or to move it among the pinned): the owner moves
  // it (`dragMoved` gives the pointer's travel and where it is, in the
  // window) and decides what a drop does. A press that does not travel is
  // a click.
  property bool dragEnabled: false
  readonly property bool dragging: mouse.dragging
  // A tile dragged out of its row (`followsPointer`): where it is drawn,
  // from its own place (the owner's Translate). Kept under the pointer every
  // frame, so it stays there when its row moves meanwhile (a row above
  // growing a line); back to 0 when let go.
  property bool followsPointer: false
  property real followX: 0
  property real followY: 0
  function refollow() {
    var now = tile.mapToItem(null, 0, 0)
    var baseX = now.x - followX, baseY = now.y - followY
    followX = (mouse.pointer.x - mouse.pressAt.x) - (baseX - mouse.origin.x)
    followY = (mouse.pointer.y - mouse.pressAt.y) - (baseY - mouse.origin.y)
  }
  FrameAnimation { running: tile.followsPointer && mouse.dragging; onTriggered: tile.refollow() }
  onDraggingChanged: if (!dragging) { followX = 0; followY = 0 }
  property Item glide: null
  property real motion: 1
  property real iconSize: Style.space(40)
  property color foreground: Color.foreground
  property string fontFamily: Style.font.family

  // pop: Shift held (open it as Omarchy's pop-out, not tiled).
  signal activated(bool pop)
  signal pinToggled()
  signal forgetRequested()
  signal dragStarted()
  signal dragMoved(real dx, real dy, point at)
  signal dragEnded(point at)
  signal hovered()
  // Its window is open (#129): the badge's click, to choose where its sound plays.
  signal soundRequested()

  readonly property bool hasIcon: !!app.icon && app.icon !== "none"
  readonly property bool windowOpen: app.open === true
  readonly property bool hot: mouse.containsMouse || here

  // Compact (a folded section's row of icons): the icon alone, centred, so
  // the cursor's highlight sits around it, as a header's button holds its
  // glyph: an 18 px icon in a 22 px box, a section header's height
  // (FoldToggle.headerHeight).
  // Whole pixels, the same margin on every side: a half pixel left over
  // put the icon (snapped to the pixel grid) off the middle of the
  // cursor's square (drawn where the tile is, fractions and all).
  property bool compact: false
  readonly property int iconPx: Math.round(iconSize)
  readonly property int margin: Math.round(Style.space(2))
  implicitWidth: compact ? iconPx + 2 * margin : Style.space(76)
  implicitHeight: compact ? iconPx + 2 * margin : column.implicitHeight + Style.space(12)

  CursorStop { here: tile.here; glide: tile.glide }

  Column {
    id: column
    anchors.horizontalCenter: parent.horizontalCenter
    anchors.top: tile.compact ? undefined : parent.top
    anchors.topMargin: tile.compact ? 0 : Style.space(6)
    anchors.verticalCenter: tile.compact ? parent.verticalCenter : undefined
    spacing: Style.space(5)

    Item {
      id: iconBox
      anchors.horizontalCenter: parent.horizontalCenter
      width: tile.iconPx
      height: tile.iconPx

      // No icon: a letter (or the demo's glyph) in a circle, in the
      // theme's colours.
      Rectangle {
        anchors.fill: parent
        radius: width / 2
        color: Qt.rgba(tile.foreground.r, tile.foreground.g, tile.foreground.b, 0.12)
        border.width: 1
        border.color: Qt.rgba(tile.foreground.r, tile.foreground.g, tile.foreground.b, 0.25)
        opacity: icon.status === Image.Ready ? 0 : 1
        Behavior on opacity { NumberAnimation { duration: Model.MOTION.inMs * tile.motion; easing.type: Easing.OutCubic } }
        // Centred by what it paints, not its text box: a glyph sits off the
        // middle of its line, which shows in a small circle.
        Text {
          id: mark
          textFormat: Text.PlainText
          text: tile.app.glyph || Model.appLetter(tile.app.name)
          color: tile.foreground
          font.family: tile.fontFamily
          font.pixelSize: tile.app.glyph ? Math.round(tile.iconSize * 0.5) : Math.round(tile.iconSize * 0.42)
          font.bold: !tile.app.glyph
          x: Math.round(parent.width / 2 - (markBounds.tightBoundingRect.x + markBounds.tightBoundingRect.width / 2))
          y: Math.round(parent.height / 2 - (baselineOffset + markBounds.tightBoundingRect.y + markBounds.tightBoundingRect.height / 2))
          TextMetrics { id: markBounds; font: mark.font; text: mark.text }
        }
      }
      Image {
        id: icon
        anchors.fill: parent
        source: tile.hasIcon ? "file://" + tile.app.icon : ""
        sourceSize.width: Math.round(tile.iconSize * 2)
        sourceSize.height: Math.round(tile.iconSize * 2)
        asynchronous: true
        smooth: true
        mipmap: true
        fillMode: Image.PreserveAspectFit
        opacity: status === Image.Ready && !tile.working ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: Model.MOTION.inMs * tile.motion; easing.type: Easing.OutCubic } }
      }
      WaitRing {
        anchors.centerIn: parent
        running: tile.working
        motion: tile.motion
        color: tile.foreground
        size: Math.round(tile.iconSize * 0.6)
      }
    }

    Text {
      visible: !tile.compact
      anchors.horizontalCenter: parent.horizontalCenter
      width: tile.width - Style.space(4)
      horizontalAlignment: Text.AlignHCenter
      textFormat: Text.PlainText
      elide: Text.ElideRight
      text: tile.app.name || ""
      color: tile.foreground
      font.family: tile.fontFamily
      font.pixelSize: Style.font.caption
    }
  }

  MouseArea {
    id: mouse
    anchors.fill: parent
    hoverEnabled: true
    cursorShape: dragging ? Qt.ClosedHandCursor : Qt.PointingHandCursor
    // Held by a drag: the page does not scroll under it.
    preventStealing: tile.dragEnabled
    property point pressAt
    property point pointer
    property point origin
    property bool dragging: false
    property bool dragged: false
    onEntered: tile.hovered()
    onPressed: function(m) { pressAt = mapToItem(null, m.x, m.y); pointer = pressAt; origin = tile.mapToItem(null, 0, 0); dragging = false; dragged = false }
    onPositionChanged: function(m) {
      if (!pressed || !tile.dragEnabled) return
      var p = mapToItem(null, m.x, m.y)
      pointer = p
      var dx = p.x - pressAt.x, dy = p.y - pressAt.y
      if (!dragging && Math.abs(dx) + Math.abs(dy) > Style.space(8)) { dragging = true; dragged = true; tile.dragStarted() }
      if (dragging) tile.dragMoved(dx, dy, p)
    }
    // Where it was let go, read before the tile goes back to its place.
    onReleased: function(m) { if (dragging) { var at = mapToItem(null, m.x, m.y); dragging = false; tile.dragEnded(at) } }
    onCanceled: if (dragging) { dragging = false; tile.dragEnded(Qt.point(-1e6, -1e6)) }
    onClicked: function(ev) { if (!dragged) tile.activated((ev.modifiers & Qt.ShiftModifier) !== 0) }
  }

  // Kept in the Apps section, or not: shown while hovered (and always for a
  // pinned one under the keys, so `p` has something to show).
  PanelActionButton {
    visible: tile.canPin && (tile.hot || pinFlash.running) && !tile.dragging
    anchors.top: parent.top
    anchors.right: parent.right
    size: Style.space(18)
    iconText: tile.pinned ? Model.GLYPH.pinOff : Model.GLYPH.pin
    tooltipText: tile.pinned ? "Unpin from the Apps section (p)" : "Pin to the Apps section (p)"
    foreground: tile.pinned ? Color.accent : tile.foreground
    fontFamily: tile.fontFamily
    onClicked: { tile.pinToggled(); pinFlash.restart() }
  }
  Timer { id: pinFlash; interval: 900 }

  // Its window is open here: where its sound plays, at the icon's corner;
  // a click (or v) chooses it again (#129). Not on a folded row's icons.
  Rectangle {
    id: soundBadge
    readonly property real size: Math.round(Style.space(18))
    visible: tile.windowOpen && !tile.compact && !tile.dragging
    x: column.x + iconBox.x + iconBox.width - size * 0.6
    y: column.y + iconBox.y + iconBox.height - size * 0.6
    width: size
    height: size
    radius: size / 2
    color: Color.background
    border.width: 1
    border.color: soundMouse.containsMouse ? Color.accent : Qt.rgba(tile.foreground.r, tile.foreground.g, tile.foreground.b, 0.35)
    Text {
      anchors.centerIn: parent
      textFormat: Text.PlainText
      text: tile.app.sound === "phone" ? Model.GLYPH.phone : tile.app.sound === "both" ? Model.GLYPH.devices : Model.GLYPH.volume
      color: soundMouse.containsMouse ? Color.accent : tile.foreground
      font.family: tile.fontFamily
      font.pixelSize: Math.round(soundBadge.size * 0.62)
    }
    MouseArea {
      id: soundMouse
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onEntered: tile.hovered()
      onClicked: tile.soundRequested()
    }
    PanelToolTip {
      visible: soundMouse.containsMouse
      text: "Its sound plays " + ({ here: "here", phone: "on the device", both: "here and on the device" })[tile.app.sound || "here"] + " · change it (v)"
      fontFamily: tile.fontFamily
    }
  }

  // Out of the recent ones (x), shown while hovered.
  PanelActionButton {
    visible: tile.canForget && tile.hot && !tile.dragging
    anchors.top: parent.top
    anchors.left: parent.left
    size: Style.space(18)
    iconText: Model.GLYPH.close
    tooltipText: "Remove from recent apps (x)"
    foreground: tile.foreground
    fontFamily: tile.fontFamily
    onClicked: tile.forgetRequested()
  }

  PanelToolTip {
    visible: mouse.containsMouse && !mouse.dragging && !soundMouse.containsMouse
    // An app (not All apps): Shift opens it popped out.
    text: tile.working ? "Opening " + (tile.app.name || "") + "…"
      : tile.windowOpen ? (tile.app.name || "") + " is open: click to bring it forward"
      : "Open " + (tile.app.name || "") + " in a window" + (tile.app.package ? " · Shift+click: popped out" : "")
    fontFamily: tile.fontFamily
  }
}
