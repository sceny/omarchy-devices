import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.Commons
import qs.Ui
import "Model.js" as Model

// The Keys overlay (#352): every key the panel answers to, over the page the
// user is on, so a key can be tried on the page while the list stays in reach.
// Each group is a folding section (FoldToggle, FoldBody) with its keys as key
// caps and an Open that goes to the group's place. One group is unfolded at a
// time: the one holding the cursor.
//
// Presentation only: Panel.qml owns what is shown, where the cursor is and
// the navigation, and the keys (Shift+J / Shift+K, Shift+O, ? and Esc).
BorderSurface {
  id: card

  property var groups: []
  property bool shown: false
  // The group holding the cursor, and the one unfolded (-1: all folded).
  property int cursor: 0
  property int unfolded: 0
  property real motion: 1
  property bool animate: true
  property color foreground: Color.foreground
  property color panelBackground: Color.background
  property string fontFamily: Style.font.family
  readonly property color dim: Qt.darker(foreground, 1.55)

  signal groupClicked(int index)
  signal openRequested(int index)

  radius: Style.cornerRadius
  color: panelBackground
  borderSpec: Border.controlSpec("focus", foreground, Color.accent)
  opacity: shown ? 1 : 0
  visible: opacity > 0.01
  Behavior on opacity { NumberAnimation { duration: (card.shown ? Model.MOTION.inMs : Model.MOTION.outMs) * card.motion; easing.type: Easing.OutCubic } }

  readonly property real inset: Style.space(10)
  height: Math.min(list.implicitHeight + 2 * inset, parent ? parent.height * 0.62 : 0)

  // A click on the card is the card's: the page under it takes none.
  MouseArea { anchors.fill: parent; acceptedButtons: Qt.AllButtons }

  // Keeps the group holding the cursor in view as the groups fold.
  function follow() {
    var item = cursorGlide.target
    if (!item || !flick) return
    var y = item.mapToItem(flick.contentItem, 0, 0).y
    var maxY = Math.max(0, flick.contentHeight - flick.height)
    var to = flick.contentY
    if (y < flick.contentY) to = Math.max(0, y - Style.space(4))
    else if (y + item.height > flick.contentY + flick.height) to = Math.min(maxY, y + item.height + Style.space(4) - flick.height)
    if (Math.abs(to - flick.contentY) < 0.5) return
    glideY.stop()
    glideY.from = flick.contentY
    glideY.to = to
    glideY.start()
  }
  onCursorChanged: Qt.callLater(follow)
  NumberAnimation { id: glideY; target: flick; property: "contentY"; duration: Model.MOTION.inMs * card.motion; easing.type: Easing.OutCubic }

  Flickable {
    id: flick
    anchors.fill: parent
    anchors.margins: card.inset
    contentWidth: width
    contentHeight: list.implicitHeight
    clip: true
    boundsBehavior: Flickable.StopAtBounds
    flickableDirection: Flickable.VerticalFlick
    interactive: contentHeight > height
    WheelScroll { flickable: flick; motion: card.motion }
    ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

    // The overlay's own keyboard cursor, drawn once behind its groups.
    CursorGlide {
      id: cursorGlide
      shown: card.shown
      motion: card.motion
      foreground: card.foreground
    }

    Column {
      id: list
      width: flick.width - Style.space(10)
      spacing: Style.space(4)

      Repeater {
        model: card.groups
        Column {
          id: group
          required property var modelData
          required property int index
          readonly property bool open: card.unfolded === group.index
          width: list.width
          spacing: Style.space(2)
          // The widest line of keys ("1–9 · Shift+H Shift+L") fits its column.
          readonly property real capsWidth: Math.round(width * 0.46)

          Item {
            id: head
            width: group.width
            height: foldHead.implicitHeight
            CursorStop { here: card.cursor === group.index; glide: cursorGlide }
            RowLayout {
              anchors.fill: parent
              spacing: Style.space(4)
              FoldToggle {
                id: foldHead
                Layout.fillWidth: true
                title: String(group.modelData.group).toUpperCase()
                summary: group.modelData.summary
                folded: !group.open
                foreground: card.foreground
                fontFamily: card.fontFamily
                motion: card.motion
                animate: card.animate
                onToggled: card.groupClicked(group.index)
              }
              Button {
                visible: !!group.modelData.place
                Layout.alignment: Qt.AlignVCenter
                Layout.preferredHeight: foldHead.headerHeight
                verticalPadding: 0
                text: "Open"
                tooltipText: Model.keyTip(Model.keysOpenLabel(group.modelData.group), "keysOpen")
                foreground: card.foreground
                fontFamily: card.fontFamily
                fontSize: Style.font.bodySmall
                onClicked: card.openRequested(group.index)
              }
            }
          }

          FoldBody {
            open: group.open
            motion: card.motion
            animate: card.animate
            spacing: Style.space(4)
            Repeater {
              model: group.modelData.items
              RowLayout {
                id: keyLine
                required property var modelData
                width: group.width
                spacing: Style.space(10)
                Flow {
                  Layout.preferredWidth: group.capsWidth
                  Layout.alignment: Qt.AlignTop
                  Layout.leftMargin: Style.space(10)
                  spacing: Style.space(3)
                  Repeater {
                    model: keyLine.modelData.caps
                    Item {
                      id: token
                      required property string modelData
                      readonly property bool between: modelData === "·"
                      width: between ? betweenText.implicitWidth : cap.width
                      height: cap.height
                      KeyCap {
                        id: cap
                        visible: !token.between
                        label: token.modelData
                        foreground: card.foreground
                        fontFamily: card.fontFamily
                      }
                      Text {
                        id: betweenText
                        visible: token.between
                        anchors.centerIn: parent
                        textFormat: Text.PlainText
                        text: "·"
                        color: card.dim
                        font.family: card.fontFamily
                        font.pixelSize: Style.font.caption
                      }
                    }
                  }
                }
                Text {
                  Layout.fillWidth: true
                  Layout.alignment: Qt.AlignTop
                  textFormat: Text.PlainText
                  text: keyLine.modelData.label
                  color: card.dim
                  font.family: card.fontFamily
                  font.pixelSize: Style.font.bodySmall
                  wrapMode: Text.WordWrap
                }
              }
            }
          }
        }
      }
    }
  }
}
