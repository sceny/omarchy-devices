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
  property color foreground: Color.foreground
  property string fontFamily: Style.font.family
  // Transitions stretch with the panel's slow motion, and pause while a page
  // appears (the panel's `settled`).
  property real motion: 1
  property bool animate: true
  readonly property color dim: Qt.darker(foreground, 1.55)
  signal toggled()

  implicitHeight: foldRow.implicitHeight
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
  }
}
