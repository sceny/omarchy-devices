import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Ui
import "Model.js" as Model

// A section header that folds, shared by the main page and the settings
// page: chevron, title, and in place of the content, one line saying what is
// in it (and a small picture, for the media cover).
Item {
  id: fold
  property string title: ""
  property string summary: ""
  // A small picture beside the summary while folded (the media cover).
  property string thumb: ""
  property bool folded: false
  // A section read from the device (Gallery): at the header's right, a
  // small ring while it is read, else a refresh button while the pointer
  // is on the header (no chrome at rest). Its place is kept, so the header
  // never moves.
  property bool canBusy: false
  property bool busy: false
  property string refreshTip: "Look again"
  property color foreground: Color.foreground
  property string fontFamily: Style.font.family
  // Transitions stretch with the panel's slow motion, and pause while a page
  // appears (the panel's `settled`).
  property real motion: 1
  property bool animate: true
  readonly property color dim: Qt.darker(foreground, 1.55)
  signal toggled()
  signal refreshRequested()

  // One height for every section header, folded or open, text alone or with
  // icons beside it, so the title never moves as a section folds: the size
  // of a header's buttons (folded Shortcuts), which everything beside a
  // title takes (folded Apps' icons, the play button, the arrows, the ring);
  // the cover is smaller.
  readonly property real headerHeight: Style.space(22)
  implicitHeight: Math.max(foldRow.implicitHeight, headerHeight)
  implicitWidth: foldRow.implicitWidth

  MouseArea {
    anchors.fill: parent
    cursorShape: Qt.PointingHandCursor
    onClicked: fold.toggled()
  }

  // Explicit margins rather than one spacing: the cover's gap exists only
  // while the cover shows, so an open section has no phantom space, and the
  // cover sits a little apart from the title and the track on either side.
  RowLayout {
    id: foldRow
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.verticalCenter: parent.verticalCenter
    spacing: 0

    Text {
      Layout.rightMargin: Style.space(6)
      Layout.alignment: Qt.AlignVCenter
      text: Model.GLYPH.chevronRight
      rotation: fold.folded ? 0 : 90
      color: fold.dim
      font.family: fold.fontFamily
      font.pixelSize: Style.font.caption
      Behavior on rotation { enabled: fold.animate; NumberAnimation { duration: Model.MOTION.inMs * fold.motion; easing.type: Easing.OutCubic } }
    }
    PanelSectionHeader {
      Layout.rightMargin: Style.space(10)
      Layout.alignment: Qt.AlignVCenter
      text: fold.title
      foreground: fold.foreground
      fontFamily: fold.fontFamily
    }
    Image {
      id: foldThumb
      readonly property bool shown: fold.folded && fold.thumb !== "" && status !== Image.Error
      Layout.preferredWidth: shown ? Style.space(18) : 0
      Layout.preferredHeight: Style.space(18)
      Layout.rightMargin: shown ? Style.space(8) : 0
      Layout.alignment: Qt.AlignVCenter
      source: fold.thumb
      sourceSize.width: 36
      sourceSize.height: 36
      fillMode: Image.PreserveAspectCrop
      asynchronous: true
      clip: true
      opacity: shown ? 1 : 0
      Behavior on Layout.preferredWidth { enabled: fold.animate; NumberAnimation { duration: Model.MOTION.inMs * fold.motion; easing.type: Easing.OutCubic } }
      Behavior on Layout.rightMargin { enabled: fold.animate; NumberAnimation { duration: Model.MOTION.inMs * fold.motion; easing.type: Easing.OutCubic } }
      Behavior on opacity { enabled: fold.animate; NumberAnimation { duration: (foldThumb.shown ? Model.MOTION.inMs : Model.MOTION.outMs) * fold.motion; easing.type: Easing.OutCubic } }
    }

    // Always laid out, so the header never reflows; it only fades.
    Text {
      Layout.fillWidth: true
      Layout.alignment: Qt.AlignVCenter
      textFormat: Text.PlainText
      text: fold.summary
      color: fold.foreground
      opacity: fold.folded ? 0.85 : 0
      font.family: fold.fontFamily
      font.pixelSize: Style.font.bodySmall
      elide: Text.ElideRight
      Behavior on opacity { enabled: fold.animate; NumberAnimation { duration: (fold.folded ? Model.MOTION.inMs : Model.MOTION.outMs) * fold.motion; easing.type: Easing.OutCubic } }
    }
    Item {
      visible: fold.canBusy
      Layout.preferredWidth: fold.headerHeight
      Layout.preferredHeight: fold.headerHeight
      Layout.leftMargin: Style.space(6)
      Layout.alignment: Qt.AlignVCenter
      // One at a time, at the panel's pace: the one leaving fades out, and
      // only once it is gone does the other fade in.
      WaitRing {
        id: foldRing
        anchors.centerIn: parent
        running: fold.busy && !foldRefresh.visible
        motion: fold.motion
        color: fold.dim
        size: Style.font.caption
      }
      PanelActionButton {
        id: foldRefresh
        anchors.centerIn: parent
        size: fold.headerHeight
        fontSize: Style.font.caption
        iconText: Model.GLYPH.refresh
        tooltipText: fold.refreshTip
        foreground: fold.foreground
        fontFamily: fold.fontFamily
        readonly property bool wanted: !fold.busy && foldHover.hovered && !foldRing.visible
        opacity: wanted ? 1 : 0
        visible: opacity > 0
        Behavior on opacity { NumberAnimation { duration: (foldRefresh.wanted ? Model.MOTION.inMs : Model.MOTION.outMs) * fold.motion; easing.type: Easing.OutCubic } }
        onClicked: fold.refreshRequested()
      }
    }
  }
  HoverHandler { id: foldHover; enabled: fold.canBusy }
}
