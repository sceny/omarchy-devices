import QtQuick
import qs.Commons
import qs.Ui
import "Model.js" as Model

// Bar pill for the phone: the device glyph, then the indicators chosen in
// settings, in order (Model.barText): by default the battery only when low,
// and a notification count drawn on the glyph (the bubble).
//
// A text pill, not BarIconButton: that one is a fixed one-glyph slot and would
// clip the indicators. Away (or KDE Connect down) it keeps its place, dimmed
// and without numbers. Low battery and not charging turns it urgent.
BarWidget {
  id: root
  moduleName: "sceny.devices"

  readonly property var phone: bar && bar.shell ? bar.shell.serviceFor("sceny.devices") : null
  readonly property var device: phone ? phone.device : null
  readonly property bool reachable: phone ? phone.reachable : false
  readonly property var indicators: Model.normalizeBarIndicators(setting("barIndicators", null))
  readonly property bool lowOnly: Model.layoutFlag(setting("batteryLowOnly", true))
  readonly property int notificationCount: phone && phone.notifications ? phone.notifications.length : 0
  readonly property int unreadMessages: phone && phone.sms ? phone.sms.unreadCount : 0
  readonly property int bubble: Model.barBubble(device, indicators, notificationCount)
  readonly property var call: phone ? phone.call : null
  readonly property int lowPercent: {
    var n = parseInt(String(setting("lowBatteryPercent", 15)), 10)
    return isFinite(n) ? n : 15
  }

  function syncService() {
    if (root.phone && "settings" in root.phone) root.phone.settings = root.settings
  }

  function injectPanel() {
    var target = panelLoader.item
    if (!target) return
    if ("bar" in target) target.bar = root.bar
    if ("settings" in target) target.settings = root.settings
    if ("anchorItem" in target) target.anchorItem = button
    if ("hostWidget" in target) target.hostWidget = root
    if ("phone" in target) target.phone = root.phone
  }

  function togglePanel() {
    if (panelLoader.item && panelLoader.item.toggle) panelLoader.item.toggle()
  }

  // Shape contract for shell summon/hide/toggle routing and popout switching.
  readonly property bool opened: panelLoader.item ? panelLoader.item.opened === true : false
  function open() { if (panelLoader.item && panelLoader.item.openFromHotkey) panelLoader.item.openFromHotkey() }
  function close() { if (panelLoader.item && panelLoader.item.close) panelLoader.item.close() }
  readonly property bool popoutSwitchClosing: panelLoader.item ? panelLoader.item.popoutSwitchClosing === true : false
  function closeForPopoutSwitch() { if (panelLoader.item) panelLoader.item.closeForPopoutSwitch() }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

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

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.vertical ? Model.deviceGlyph(root.device) : Model.barText(root.device, root.indicators, {
      lowPercent: root.lowPercent, lowOnly: root.lowOnly, notifications: root.notificationCount,
      messages: root.unreadMessages, playing: !!root.phone && root.phone.nowPlaying !== "", call: root.call })
    horizontalMargin: 8.75
    dimmed: !root.reachable
    // A ringing phone makes the pill glow ring, ring, rest, in the accent
    // colour of the card's phone (Service.ringLit); a low battery lights it
    // steadily, urgent.
    readonly property bool ringLit: !!root.phone && root.phone.ringLit
    active: Model.lowBattery(root.device, root.lowPercent) || ringLit
    activeColor: ringLit ? Color.accent : (root.bar ? root.bar.urgent : Color.urgent)
    tooltipText: root.opened ? "" : Model.tooltip(root.phone ? root.phone.snapshot : null, root.device, root.phone ? root.phone.nowPlaying : "", root.unreadMessages, root.call)

    onPressed: function(b) {
      if (b === Qt.MiddleButton && panelLoader.item && panelLoader.item.openMessagesFromHotkey) panelLoader.item.openMessagesFromHotkey()
      else root.togglePanel()
    }
  }

  // The bubble: the notification count on the glyph's top right corner, like
  // a phone's app badge. Drawn over the pill, so it adds no width. The glyph
  // is the start of the pill's centred label.
  TextMetrics {
    id: glyphMetrics
    font.family: button.fontFamily
    font.pixelSize: button.fontSize
    text: Model.deviceGlyph(root.device)
  }

  Rectangle {
    visible: root.bubble > 0
    readonly property real glyphLeft: (button.width - button.labelWidth) / 2
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
      text: root.bubble > 9 ? "9+" : String(root.bubble)
      color: "white"
      font.family: button.fontFamily
      font.pixelSize: Math.max(6, parent.height * 0.72)
      font.bold: true
    }
  }
}
