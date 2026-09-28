import QtQuick
import qs.Commons
import qs.Ui
import "Model.js" as Model

// Bar pill for the devices: one chip per device that shows (Model.chips, in
// the user's order), each its own icon, its chosen indicators and its own
// notification bubble; a resting glyph when no chip shows, so the pill never
// disappears. With one device this is today's pill.
//
// Chips are text pills, not BarIconButton: that one is a fixed one-glyph slot
// and would clip the indicators. An away device keeps its chip dimmed when it
// shows always. A low battery turns its glyph and % red, not the whole chip:
// a chip is drawn in parts (Model.barParts), each its own colour.
BarWidget {
  id: root
  moduleName: "sceny.devices"

  readonly property var phone: bar && bar.shell ? bar.shell.serviceFor("sceny.devices") : null
  readonly property var pill: phone ? phone.pill : ({ chips: [], resting: { glyph: Model.GLYPH.devices, dimmed: true, ringing: false }, pairing: false })
  // What is drawn: the chips, or the resting glyph as one chip of no device.
  readonly property var items: pill.chips.length > 0 ? pill.chips
    : [{ id: "", glyph: pill.resting.glyph, text: pill.resting.glyph, parts: [{ text: pill.resting.glyph, urgent: false }],
         bubble: 0, dimmed: pill.resting.dimmed, ringing: false, marks: {} }]

  function syncService() {
    if (root.phone && "settings" in root.phone) root.phone.settings = root.settings
  }

  function injectPanel() {
    var target = panelLoader.item
    if (!target) return
    if ("bar" in target) target.bar = root.bar
    if ("settings" in target) target.settings = root.settings
    if ("anchorItem" in target) target.anchorItem = chipRow
    if ("hostWidget" in target) target.hostWidget = root
    if ("phone" in target) target.phone = root.phone
  }

  function deviceById(id) {
    var list = phone ? phone.ordered : []
    for (var i = 0; i < list.length; i++) if (String(list[i].id) === String(id)) return list[i]
    return null
  }

  // A chip opens the panel on its device; on the device already shown it
  // closes it; on another while open it switches to it. The resting glyph
  // (no device) opens on the usual one.
  function chipPressed(button, id) {
    var panel = panelLoader.item
    if (!panel) return
    if (button === Qt.MiddleButton) {
      if (phone && id !== "") phone.requestView(id)
      if (panel.openMessagesFromHotkey) panel.openMessagesFromHotkey()
      return
    }
    if (!panel.opened) {
      if (phone && id !== "") phone.requestView(id)
      panel.open()
    } else if (id === "" || !phone || !phone.device || String(phone.device.id) === String(id)) {
      panel.close()
    } else if (panel.switchDevice) {
      panel.switchDevice(id, true)
    }
  }

  // Shape contract for shell summon/hide/toggle routing and popout switching.
  readonly property bool opened: panelLoader.item ? panelLoader.item.opened === true : false
  function open() { if (panelLoader.item && panelLoader.item.openFromHotkey) panelLoader.item.openFromHotkey() }
  function close() { if (panelLoader.item && panelLoader.item.close) panelLoader.item.close() }
  readonly property bool popoutSwitchClosing: panelLoader.item ? panelLoader.item.popoutSwitchClosing === true : false
  function closeForPopoutSwitch() { if (panelLoader.item) panelLoader.item.closeForPopoutSwitch() }

  // The open-panel mark under the pill spans every chip's label (#67).
  readonly property real openPanelIndicatorWidth: root.vertical ? 0 : Math.max(0, chipRow.width - 2 * Style.spaceReal(8.75))

  implicitWidth: chipRow.implicitWidth
  implicitHeight: chipRow.implicitHeight
  // A chip arriving or leaving widens or narrows the pill at the plugin's pace.
  Behavior on implicitWidth { NumberAnimation { duration: Model.MOTION.inMs; easing.type: Easing.OutCubic } }

  onBarChanged: injectPanel()
  onSettingsChanged: { injectPanel(); syncService() }
  onPhoneChanged: { injectPanel(); syncService() }

  Loader {
    id: panelLoader
    active: true
    source: Qt.resolvedUrl("Panel.qml")
    visible: false
    onLoaded: {
      root.injectPanel()
      Qt.callLater(root.injectPanel)
    }
  }

  // Side by side on a horizontal bar, stacked (icons only) on a vertical one.
  Grid {
    id: chipRow
    anchors.centerIn: parent
    columns: root.vertical ? 1 : Math.max(1, root.items.length)

    Repeater {
      model: root.items

      Item {
        id: chip
        required property var modelData
        required property int index
        readonly property var dev: root.deviceById(modelData.id)
        // On a vertical bar, the glyph alone.
        readonly property var parts: root.vertical ? [{ text: chip.modelData.glyph, urgent: false }] : (chip.modelData.parts || [])
        implicitWidth: button.implicitWidth
        implicitHeight: button.implicitHeight

        // The button gives the chip its size, clicks and tooltip; the parts
        // are drawn over it (its own label is one colour).
        WidgetButton {
          id: button
          anchors.fill: parent
          bar: root.bar
          text: chip.modelData.glyph
          labelVisible: false
          fixedWidth: root.vertical ? -1 : partsRow.implicitWidth + 2 * Style.spaceReal(8.75)
          horizontalMargin: 8.75
          dimmed: chip.modelData.dimmed === true
          tooltipText: root.opened ? "" : (chip.dev
            ? Model.tooltip(root.phone ? root.phone.snapshot : null, chip.dev,
                root.phone && root.phone.device && root.phone.device.id === chip.dev.id ? root.phone.nowPlaying : "",
                root.phone && root.phone.sms && root.phone.sms.deviceId === String(chip.dev.id) ? root.phone.sms.unreadCount : 0)
            : Model.tooltip(root.phone ? root.phone.snapshot : null, null, "", 0))
          onPressed: function(b) { root.chipPressed(b, chip.modelData.id) }
        }

        Row {
          id: partsRow
          anchors.centerIn: parent
          spacing: glyphMetrics.spaceWidth
          opacity: button.opacity
          Repeater {
            model: chip.parts
            Text {
              required property var modelData
              textFormat: Text.PlainText
              text: modelData.text
              color: modelData.urgent ? (root.bar ? root.bar.urgent : Color.urgent) : (root.bar ? root.bar.barForeground : Color.foreground)
              font.family: button.fontFamily
              font.pixelSize: button.fontSize
              renderType: Text.NativeRendering
              anchors.verticalCenter: parent.verticalCenter
              Behavior on color { ColorAnimation { duration: 160 } }
            }
          }
        }

        // The bubble: this device's notification count on its own icon, like
        // a phone's app badge. Drawn over the chip, so it adds no width.
        TextMetrics {
          id: glyphMetrics
          font.family: button.fontFamily
          font.pixelSize: button.fontSize
          text: chip.modelData.glyph
          readonly property real spaceWidth: spaceMetrics.advanceWidth
        }
        TextMetrics {
          id: spaceMetrics
          font.family: button.fontFamily
          font.pixelSize: button.fontSize
          text: " "
        }

        Rectangle {
          visible: chip.modelData.bubble > 0
          readonly property real glyphLeft: partsRow.x
          height: Math.max(9, Math.round(button.fontSize * 0.72))
          width: Math.max(height, bubbleText.implicitWidth + 4)
          radius: height / 2
          x: glyphLeft + glyphMetrics.advanceWidth - width * 0.55
          y: button.height / 2 - glyphMetrics.height / 2 - height * 0.2
          // Red with a white count, like a phone's badge; no outline.
          color: Color.urgent

          Text {
            id: bubbleText
            anchors.centerIn: parent
            text: chip.modelData.bubble > 9 ? "9+" : String(chip.modelData.bubble)
            color: "white"
            font.family: button.fontFamily
            font.pixelSize: Math.max(6, parent.height * 0.72)
            font.bold: true
          }
        }

        // A device asking to pair: an accent dot at the first chip's lower
        // left, until it is answered.
        Rectangle {
          visible: chip.index === 0 && root.pill.pairing === true
          readonly property real glyphLeft: partsRow.x
          width: Math.max(5, Math.round(button.fontSize * 0.36))
          height: width
          radius: width / 2
          x: glyphLeft - width * 0.4
          y: button.height / 2 + glyphMetrics.height / 2 - height * 0.8
          color: Color.accent
        }
      }
    }
  }
}
