import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import qs.Commons
import qs.Ui
import "Model.js" as Model

// A device asking to pair, under the bar the moment it asks: its name, the
// key to compare with the one on it, Accept, Reject, and ✕ to hide the card
// (the request still waits in the panel). It never takes the keyboard: the
// panel does when it opens, so the panel never opens by itself, and keys
// typed into another window must not land anywhere here. It goes by itself
// when the request is answered (here, on the device, in the panel) or
// withdrawn. One per bar, on that bar's screen.
PanelWindow {
  id: popup

  property var phone: null
  // This bar's panel is open: it shows the pairing itself, so the card waits.
  property bool panelOpen: false
  // The chip it points at, in the bar's window.
  property Item anchorItem: null
  property color foreground: Color.foreground
  property string fontFamily: Style.font.family
  property real motion: 1

  // A device asking to pair, else a pairing this computer asked for (the
  // device accepts it; the card shows the key to check there, and Cancel).
  readonly property var request: phone ? (phone.pairingRequest || phone.pairingOut) : null
  readonly property bool outgoing: !!shown && shown.pairRequestedByPeer !== true
  // ✕ hides this request's card; a new request shows again.
  property string hiddenId: ""
  // Kept while it fades out, so the text does not blank mid-fade.
  property var shown: null
  onRequestChanged: {
    if (request) shown = request
    else hiddenId = ""
  }
  Component.onCompleted: if (request) shown = request
  readonly property bool showing: !!request && String(request.id) !== hiddenId && !panelOpen
  readonly property bool waiting: !!shown && !!phone
    && (phone.isBusy("accept:" + shown.id) || phone.isBusy("reject:" + shown.id))

  // Where the chip is: the bar's window is anchored to one edge of the
  // screen; the card sits just past it, centred on the chip.
  readonly property var barWindow: anchorItem && anchorItem.QsWindow ? anchorItem.QsWindow.window : null
  readonly property bool barAtBottom: !!barWindow && !!barWindow.anchors && barWindow.anchors.bottom === true && barWindow.anchors.top !== true
  readonly property real chipX: {
    if (!anchorItem || !barWindow) return width - card.width - Style.space(12)
    var p = anchorItem.mapToItem(null, 0, 0)
    return p.x + anchorItem.width / 2
  }
  readonly property real gap: Style.space(8)

  screen: barWindow ? barWindow.screen : null
  visible: showing || card.opacity > 0.01
  anchors { top: true; bottom: true; left: true; right: true }
  color: "transparent"
  WlrLayershell.namespace: "sceny-devices-pairing"
  WlrLayershell.layer: WlrLayer.Overlay
  WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
  exclusionMode: ExclusionMode.Ignore
  // Clicks reach only the card; everything around it stays the desktop's.
  mask: Region { item: card }

  BorderSurface {
    id: card
    width: Math.min(Style.space(420), popup.width - 2 * Style.space(12))
    height: content.implicitHeight + 2 * Style.space(14)
    x: Math.max(Style.space(12), Math.min(popup.width - width - Style.space(12), popup.chipX - width / 2))
    y: popup.barAtBottom ? popup.height - (popup.barWindow ? popup.barWindow.height : 0) - height - popup.gap
                         : (popup.barWindow ? popup.barWindow.height : 0) + popup.gap
    radius: Style.cornerRadius
    // Solid: whatever is under it never shows through.
    color: Qt.rgba(Color.background.r, Color.background.g, Color.background.b, 1)
    borderSpec: Border.surfaceSpec("popups", "border", Color.popups.border, Math.max(1, Style.space(2)))
    opacity: popup.showing ? 1 : 0
    // In from the bar's side, at the plugin's pace.
    transform: Translate { y: popup.showing ? 0 : (popup.barAtBottom ? Style.space(10) : -Style.space(10))
      Behavior on y { NumberAnimation { duration: (popup.showing ? Model.MOTION.inMs : Model.MOTION.outMs) * popup.motion; easing.type: Easing.OutCubic } } }
    Behavior on opacity { NumberAnimation { duration: (popup.showing ? Model.MOTION.inMs : Model.MOTION.outMs) * popup.motion; easing.type: Easing.OutCubic } }

    RowLayout {
      id: content
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      anchors.leftMargin: Style.space(16)
      anchors.rightMargin: Style.space(10)
      spacing: Style.space(12)

      Text {
        Layout.alignment: Qt.AlignVCenter
        text: popup.shown ? Model.deviceGlyph(popup.shown) : ""
        color: Color.accent
        font.family: popup.fontFamily
        font.pixelSize: Style.font.heading + 6
      }
      ColumnLayout {
        Layout.fillWidth: true
        spacing: Style.space(2)
        Text {
          Layout.fillWidth: true
          textFormat: Text.PlainText
          text: popup.outgoing ? "Pairing with " + (popup.shown ? String(popup.shown.name || "a device") : "")
                               : (popup.shown ? String(popup.shown.name || "A device") : "") + " wants to pair"
          color: popup.foreground
          font.family: popup.fontFamily
          font.pixelSize: Style.font.body
          font.bold: true
          elide: Text.ElideRight
        }
        // The key is what the user checks: large, apart, in the accent,
        // with what to do with it beside it.
        RowLayout {
          visible: !!popup.shown && !!popup.shown.verificationKey
          Layout.topMargin: Style.space(6)
          spacing: Style.space(10)
          Rectangle {
            implicitWidth: keyText.implicitWidth + Style.space(16)
            implicitHeight: keyText.implicitHeight + Style.space(6)
            radius: Style.cornerRadius
            color: "transparent"
            border.width: 1
            border.color: Color.accent
            Text {
              id: keyText
              anchors.centerIn: parent
              textFormat: Text.PlainText
              text: popup.shown ? String(popup.shown.verificationKey || "") : ""
              color: Color.accent
              font.family: popup.fontFamily
              font.pixelSize: Style.font.heading
              font.bold: true
              font.letterSpacing: 1.5
            }
          }
          Text {
            Layout.fillWidth: true
            textFormat: Text.PlainText
            wrapMode: Text.WordWrap
            text: popup.outgoing ? "Accept it on the device if it shows this key." : "The same key on it? Then accept."
            color: Qt.darker(popup.foreground, 1.55)
            font.family: popup.fontFamily
            font.pixelSize: Style.font.caption
          }
        }
        RowLayout {
          Layout.topMargin: Style.space(6)
          spacing: Style.space(8)
          Button {
            visible: !popup.outgoing
            text: popup.waiting ? "Waiting…" : "Accept"
            enabled: !popup.waiting
            bordered: true
            foreground: popup.foreground
            fontFamily: popup.fontFamily
            fontSize: Style.font.bodySmall
            onClicked: if (popup.phone && popup.shown) popup.phone.acceptPairing(popup.shown.id)
          }
          Button {
            text: popup.outgoing ? "Cancel" : "Reject"
            enabled: !popup.waiting
            foreground: popup.foreground
            fontFamily: popup.fontFamily
            fontSize: Style.font.bodySmall
            onClicked: if (popup.phone && popup.shown) popup.phone.rejectPairing(popup.shown.id)
          }
        }
      }
      PanelActionButton {
        Layout.alignment: Qt.AlignTop
        iconText: Model.GLYPH.close
        tooltipText: "Hide; the request still waits in the panel"
        foreground: popup.foreground
        fontFamily: popup.fontFamily
        onClicked: if (popup.shown) popup.hiddenId = String(popup.shown.id)
      }
    }
  }
}
