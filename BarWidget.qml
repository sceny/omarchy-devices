import QtQuick
import qs.Commons
import qs.Ui
import "Model.js" as Model

// Bar pill for the phone: the phone glyph and its battery, "󰄜 63%󱐋".
//
// A text pill, not BarIconButton: that one is a fixed one-glyph slot and would
// clip the percentage. Away (or KDE Connect down) it keeps its place, dimmed
// and without a number, so the bar does not reflow as the phone comes and goes.
// Low battery and not charging turns it urgent.
BarWidget {
  id: root
  moduleName: "sceny.devices"

  readonly property var phone: bar && bar.shell ? bar.shell.serviceFor("sceny.devices") : null
  readonly property var device: phone ? phone.device : null
  readonly property bool reachable: phone ? phone.reachable : false
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
    text: root.vertical ? Model.deviceGlyph(root.device) : Model.barText(root.device, root.setting("showPercent", true) !== false)
    horizontalMargin: 8.75
    dimmed: !root.reachable
    active: Model.lowBattery(root.device, root.lowPercent)
    tooltipText: root.opened ? "" : Model.tooltip(root.phone ? root.phone.snapshot : null, root.device, root.phone ? root.phone.nowPlaying : "")

    onPressed: function(b) {
      if (b === Qt.MiddleButton && panelLoader.item && panelLoader.item.openMessagesFromHotkey) panelLoader.item.openMessagesFromHotkey()
      else root.togglePanel()
    }
  }
}
