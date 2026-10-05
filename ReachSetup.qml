import QtQuick
import QtQuick.Layouts
import qs.Commons
import "Model.js" as Model

// From anywhere, for one device (Model.reachSetup, #119): where it stands,
// how it is connected now, what its network likely does, and the steps to
// reach it on any network (done ones ticked, the current one bright). The
// page's actions are its keyboard rows, drawn by SettingsView.
Column {
  id: root

  property var setup: null
  property color foreground: Color.foreground
  property string fontFamily: Style.font.family

  readonly property color dim: Qt.darker(foreground, 1.55)

  spacing: Style.space(6)

  Text {
    width: root.width
    textFormat: Text.PlainText
    wrapMode: Text.WordWrap
    text: root.setup ? root.setup.line : "Checking…"
    color: root.setup && root.setup.state === "ready" ? root.foreground : root.dim
    font.family: root.fontFamily
    font.pixelSize: Style.font.bodySmall
  }
  Text {
    visible: text !== ""
    width: root.width
    textFormat: Text.PlainText
    wrapMode: Text.WordWrap
    text: root.setup ? root.setup.now : ""
    color: root.dim
    font.family: root.fontFamily
    font.pixelSize: Style.font.caption
  }
  Repeater {
    model: root.setup ? root.setup.notes : []
    Text {
      required property var modelData
      width: root.width
      textFormat: Text.PlainText
      wrapMode: Text.WordWrap
      text: modelData
      color: root.foreground
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
    }
  }
  Repeater {
    model: root.setup ? root.setup.steps : []

    RowLayout {
      id: step
      required property var modelData
      required property int index
      width: root.width
      spacing: Style.space(10)

      Text {
        Layout.alignment: Qt.AlignTop
        Layout.preferredWidth: Style.space(16)
        textFormat: Text.PlainText
        text: step.modelData.done ? Model.GLYPH.check : (step.index + 1) + "."
        color: step.modelData.current ? root.foreground : root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.bodySmall
      }
      Text {
        Layout.fillWidth: true
        textFormat: Text.PlainText
        wrapMode: Text.WordWrap
        text: step.modelData.text
        color: step.modelData.current ? root.foreground : root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.bodySmall
      }
    }
  }
}
