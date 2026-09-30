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
  // This bar's panel is open: it shows the pairing itself, so the card waits,
  // until the panel has faded out too (never drawn over it as it closes).
  property bool panelOpen: false
  property bool panelGone: !panelOpen
  onPanelOpenChanged: {
    if (panelOpen) { panelGone = false; panelGoneTimer.stop() }
    else panelGoneTimer.restart()
  }
  Timer { id: panelGoneTimer; interval: Model.MOTION.outMs + Model.MOTION.inMs; onTriggered: popup.panelGone = true }
  // The chip it points at, in the bar's window.
  property Item anchorItem: null
  property color foreground: Color.foreground
  property string fontFamily: Style.font.family
  property real motion: 1

  // Only a device asking to pair: a pairing started here, from the panel,
  // is the user's own and stays on its card in the panel (Add a device).
  readonly property var request: phone ? phone.pairingRequest : null
  // ✕ hides this request's card; a new request shows again.
  property string hiddenId: ""
  // Kept while it fades out, so the text does not blank mid-fade.
  property var shown: null
  onRequestChanged: {
    if (request) shown = request
    else hiddenId = ""
  }
  Component.onCompleted: if (request) shown = request
  readonly property bool showing: !!request && String(request.id) !== hiddenId && panelGone
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

    // The device and what is asked; then the key and the answer on one
    // row (the key's caption above it says what to check).
    RowLayout {
      id: content
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      anchors.leftMargin: Style.space(16)
      anchors.rightMargin: Style.space(12)
      spacing: Style.space(14)

      Text {
        Layout.alignment: Qt.AlignTop
        Layout.topMargin: Style.space(2)
        text: popup.shown ? Model.deviceGlyph(popup.shown) : ""
        color: Color.accent
        font.family: popup.fontFamily
        font.pixelSize: Style.font.display
      }
      ColumnLayout {
        Layout.fillWidth: true
        spacing: Style.space(8)
        RowLayout {
          Layout.fillWidth: true
          spacing: Style.space(8)
          Text {
            Layout.fillWidth: true
            textFormat: Text.PlainText
            text: (popup.shown ? String(popup.shown.name || "A device") : "") + " wants to pair"
            color: popup.foreground
            font.family: popup.fontFamily
            font.pixelSize: Style.font.body
            font.bold: true
            elide: Text.ElideRight
          }
          PanelActionButton {
            iconText: Model.GLYPH.close
            tooltipText: "Hide; the request still waits in the panel"
            foreground: popup.foreground
            fontFamily: popup.fontFamily
            onClicked: if (popup.shown) popup.hiddenId = String(popup.shown.id)
          }
        }
        RowLayout {
          Layout.fillWidth: true
          spacing: Style.space(8)
          PairingKey {
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignBottom
            key: popup.shown ? String(popup.shown.verificationKey || "") : ""
            caption: "check it matches"
            foreground: popup.foreground
            fontFamily: popup.fontFamily
          }
          Item { Layout.fillWidth: true; visible: !popup.shown || !popup.shown.verificationKey }
          Button {
            Layout.alignment: Qt.AlignBottom
            text: popup.waiting ? "Waiting…" : "Accept"
            enabled: !popup.waiting
            bordered: true
            foreground: popup.foreground
            fontFamily: popup.fontFamily
            fontSize: Style.font.bodySmall
            onClicked: if (popup.phone && popup.shown) popup.phone.acceptPairing(popup.shown.id)
          }
          Button {
            Layout.alignment: Qt.AlignBottom
            text: "Reject"
            enabled: !popup.waiting
            foreground: popup.foreground
            fontFamily: popup.fontFamily
            fontSize: Style.font.bodySmall
            onClicked: if (popup.phone && popup.shown) popup.phone.rejectPairing(popup.shown.id)
          }
        }
      }
    }
  }
}
