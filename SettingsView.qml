import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Ui
import "Model.js" as Model

// The phone panel's settings page, shown in place of the phone view.
//
// Presentation only: it draws `rows` (Model.settingsPageRows, one flat list
// so the keyboard cursor is a single index) and emits intent. Panel.qml owns
// the cursor, the scope (the device list, one device's page, the defaults)
// and writes shell.json.
Column {
  id: root

  property var rows: []
  property int cursorIndex: -1
  // The page's keyboard cursor (Panel's CursorGlide): rows mark where it stops.
  property Item cursorGlide: null
  property bool shortcutsShown: true
  property var setupFixing: ({})
  // This computer's network, for Add a device's steps.
  property string network: ""
  property string appPlatform: "android"
  signal appPlatformSet(string platform)
  // Screen and apps (scope "screen"): the page's model (Model.screenSetup)
  // and the pairing code it shows.
  property var screenSetup: null
  property var screenQr: null
  // Its screen's window is open: the tile is on, with its ✕.
  property bool screenOpen: false
  signal screenPlaceChosen(bool docked)
  signal appSoundChosen(string sound)
  // What it can do: a feature's one action, its switch; Fix what I can.
  signal featureRequested(int index)
  signal featureSwitched(int index, bool on)
  signal fixAllRequested()
  // Fix with AI (#101): the person's coding agent, with what went wrong.
  // what: "features" (the section's), "feature" or "check" (a row's).
  signal fixWithAiRequested(string what, int index)
  signal checkAgainRequested()
  property string agentName: ""
  readonly property string aiTip: agentName !== "" ? "Opens " + agentName + ", your default coding agent, in a terminal, on what is wrong here"
    : "Choose your coding agent first (Omarchy's own choice), then again"
  // What it can do's problems: a marker and the section's own Fix all and
  // Fix with AI in its title.
  readonly property int featureProblems: rows.filter(function(r) { return r.kind === "feature" && r.problem }).length
  readonly property string featuresLine: {
    var f = rows.filter(function(r) { return r.kind === "feature" })
    if (featureProblems > 0) return featureProblems + (featureProblems === 1 ? " needs attention" : " need attention")
    var on = f.filter(function(r) { return r.state === "on" }).length
    var setup = f.filter(function(r) { return r.state === "setup" }).length
    return on + " on" + (setup > 0 ? " · " + setup + " to set up" : "")
  }
  property int fixAllCount: 0
  signal screenCloseRequested()
  // A pairing that just completed here: ✓ in place of its card, for a moment.
  property var justPaired: null
  // Pairings asked here: when each started (the card's countdown), and a
  // note for one that was not accepted in time (on its row).
  property var pairingNotes: ({})
  property var pairingSince: ({})
  property real pairClock: 0
  // Folding, like the main page's sections, and remembered the same way.
  property var collapsed: ({})
  property var flags: ({})
  property var order: []
  property var sectionOrder: []
  property var barIndicators: []
  property bool batteryLowOnly: true
  // Many devices: what the page edits ("root", "device", "defaults"), which
  // of its settings the device changed, the icon picker, Unpair armed.
  property string scopeKind: "root"
  property var custom: ({})
  property bool iconPicking: false
  property bool unpairArmed: false
  property string deviceName: ""
  property var phone: null
  // The panel's own background: a dragged row is painted solid over it, so
  // it never shows the row it passes over through itself.
  property color panelBackground: Color.background
  property real motion: 1
  property bool animate: true
  function isFolded(key) { return collapsed[key] === true }
  property color foreground: Color.foreground
  property string fontFamily: Style.font.family

  signal activated(int index)
  signal moveRequested(string key, int delta)
  signal sectionMoveRequested(string section, int delta)
  signal barMoveRequested(string key, int delta)
  signal hovered(int index)
  signal fixRequested(string what)
  signal ignoreRequested(string key, bool on)
  // Nothing set up yet: a look at the panel with a made-up phone (#62).
  property bool canPreview: false
  signal previewRequested()
  signal foldToggled(string key)
  signal rejectRequested(string id)
  signal deviceMoveRequested(string id, int delta)
  signal nicknameSet(string text)
  signal iconSet(string code)
  signal barPlaceSet(string place)
  signal nicknameFocus(bool focused)

  readonly property color dim: Qt.darker(foreground, 1.55)

  function firstIndex(kind) {
    for (var i = 0; i < rows.length; i++) if (rows[i].kind === kind) return i
    return -1
  }
  function hasKind(kinds) {
    for (var i = 0; i < rows.length; i++) if (kinds.indexOf(rows[i].kind) >= 0) return true
    return false
  }
  readonly property bool hasGroups: firstIndex("layout") >= 0
  readonly property bool hasList: scopeKind !== "connection" && scopeKind !== "addDevice" && scopeKind !== "screen" && hasKind(["device", "request", "available"])
  readonly property bool hasIdentity: firstIndex("nickname") >= 0
  function groupTitle(title, group) {
    return scopeKind === "device" && Model.groupCustom(custom, group) ? title + " · CUSTOM" : title
  }
  function devicesSummary() {
    var n = 0, asking = 0
    for (var i = 0; i < rows.length; i++) {
      if (rows[i].kind === "device") n++
      if (rows[i].kind === "request") asking++
    }
    var line = n === 1 ? "1 device" : n + " devices"
    return asking > 0 ? line + " · " + asking + (asking === 1 ? " wants to pair" : " want to pair") : line
  }

  // The user's click or Enter on the Nickname row only (never scripted).
  function editNickname() { if (nicknameField) nicknameField.forceActiveFocus() }
  property var nicknameField: null

  spacing: Style.space(6)

  // ---- Devices: every device, in order; asking to pair; in reach ----
  FoldToggle {
    visible: root.hasList
    width: root.width
    title: "DEVICES"
    summary: root.devicesSummary()
    folded: root.isFolded("devicesList")
    foreground: root.foreground
    fontFamily: root.fontFamily
    motion: root.motion
    animate: root.animate
    onToggled: root.foldToggled("devicesList")
  }

  FoldBody {
    visible: root.hasList
    open: !root.isFolded("devicesList")
    motion: root.motion
    animate: root.animate
    spacing: Style.space(4)

      Text {
        visible: root.firstIndex("device") >= 0
        textFormat: Text.PlainText
        width: root.width
        wrapMode: Text.WordWrap
        text: "The first opens when the panel does and always shows in the bar. Drag one by its grip, or Shift+K / Shift+J on the selected one."
        color: root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
      }

      Repeater {
        model: root.rows
        ListRow {
          required property var modelData
          required property int index
          visible: modelData.kind === "device" || modelData.kind === "request" || modelData.kind === "available"
          width: root.width
          row: modelData
          rowIndex: index
        }
      }
  }

  // ---- This device: its name and icon, and on its page where it shows ----
  Item { visible: root.hasIdentity && root.scopeKind === "root"; width: 1; height: Style.space(6) }
  PanelSeparator { visible: root.hasIdentity && root.scopeKind === "root"; foreground: root.foreground }

  FoldToggle {
    visible: root.hasIdentity
    width: root.width
    title: root.scopeKind === "device" ? "DEVICE" : "THIS DEVICE"
    summary: root.deviceName
    folded: root.isFolded("identity")
    foreground: root.foreground
    fontFamily: root.fontFamily
    motion: root.motion
    animate: root.animate
    onToggled: root.foldToggled("identity")
  }

  FoldBody {
    visible: root.hasIdentity
    open: !root.isFolded("identity")
    motion: root.motion
    animate: root.animate
    spacing: Style.space(4)

      Repeater {
        model: root.rows
        IdentityRow {
          required property var modelData
          required property int index
          visible: ["nickname", "icon", "barPlace", "showInPanel"].indexOf(modelData.kind) >= 0
          width: root.width
          row: modelData
          rowIndex: index
        }
      }
  }

  // ---- Defaults for all devices (the list's page); on a device's page,
  //      its sections and shortcuts, edited on the page itself ----
  Repeater {
    model: root.rows
    ListRow {
      required property var modelData
      required property int index
      visible: modelData.kind === "defaults" || modelData.kind === "editPage" || modelData.kind === "screen"
      width: root.width
      row: modelData
      rowIndex: index
    }
  }

  // ---- What it can do (docs/design/setup.md): a row per feature, folding;
  //      a problem marks its title, which then holds Fix all and Fix with AI ----
  Item { visible: root.firstIndex("feature") >= 0; width: 1; height: Style.space(6) }
  RowLayout {
    visible: root.firstIndex("feature") >= 0
    width: root.width
    spacing: Style.space(4)
    FoldToggle {
      id: featuresFold
      Layout.fillWidth: true
      title: "WHAT IT CAN DO"
      summary: root.featuresLine
      folded: root.isFolded("features")
      foreground: root.featureProblems > 0 ? Color.urgent : root.foreground
      fontFamily: root.fontFamily
      motion: root.motion
      animate: root.animate
      onToggled: root.foldToggled("features")
    }
    Button {
      visible: root.featureProblems > 0 && root.fixAllCount > 0
      Layout.preferredHeight: featuresFold.headerHeight
      text: root.phone && root.phone.isBusy("fixAll") ? "Fixing…" : "Fix all"
      enabled: !(root.phone && root.phone.isBusy("fixAll"))
      tooltipText: "Every fix the plugin can do, here and on the device"
      verticalPadding: 0
      bordered: true
      foreground: root.foreground
      fontFamily: root.fontFamily
      fontSize: Style.font.caption
      onClicked: root.fixAllRequested()
    }
    Button {
      visible: root.featureProblems > 0
      Layout.preferredHeight: featuresFold.headerHeight
      text: "Fix with AI"
      tooltipText: root.aiTip
      verticalPadding: 0
      foreground: root.foreground
      fontFamily: root.fontFamily
      fontSize: Style.font.caption
      onClicked: root.fixWithAiRequested("features", -1)
    }
  }
  FoldBody {
    visible: root.firstIndex("feature") >= 0
    open: !root.isFolded("features")
    motion: root.motion
    animate: root.animate
    Repeater {
      model: root.rows
      FeatureRow {
        required property var modelData
        required property int index
        visible: modelData.kind === "feature"
        width: root.width
        row: modelData
        rowIndex: index
      }
    }
  }

  Item { visible: root.hasGroups && (root.hasIdentity || root.hasList); width: 1; height: Style.space(6) }
  PanelSeparator { visible: root.hasGroups && (root.hasIdentity || root.hasList); foreground: root.foreground }

  Column {
    id: groupsBox
    visible: root.hasGroups
    width: root.width
    spacing: Style.space(6)

    // ---- Layout ----
    FoldToggle {
      width: root.width
      title: root.groupTitle("LAYOUT", "layout")
      summary: Model.layoutSummary(root.flags, root.sectionOrder)
      folded: root.isFolded("layout")
      foreground: root.foreground
      fontFamily: root.fontFamily
      motion: root.motion
      animate: root.animate
      onToggled: root.foldToggled("layout")
    }

    FoldBody {
      open: !root.isFolded("layout")
      motion: root.motion
      animate: root.animate
      spacing: Style.space(6)

        Text {
          textFormat: Text.PlainText
          width: root.width
          wrapMode: Text.WordWrap
          text: "The sections under the header, in this order. Drag one by its grip, or Shift+K / Shift+J on the selected one."
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
        }

        Repeater {
          model: root.rows
          LayoutRow {
            required property var modelData
            required property int index
            visible: modelData.kind === "layout"
            width: root.width
            row: modelData
            rowIndex: index
          }
        }

    }

    Item { width: 1; height: Style.space(6) }
    PanelSeparator { foreground: root.foreground }

    // ---- Bar: what the pill shows beside the device glyph ----
    FoldToggle {
      width: root.width
      title: root.groupTitle("BAR", "bar")
      summary: Model.barSummary(root.barIndicators, root.batteryLowOnly)
      folded: root.isFolded("bar")
      foreground: root.foreground
      fontFamily: root.fontFamily
      motion: root.motion
      animate: root.animate
      onToggled: root.foldToggled("bar")
    }

    FoldBody {
      open: !root.isFolded("bar")
      motion: root.motion
      animate: root.animate
      spacing: Style.space(6)

        Text {
          textFormat: Text.PlainText
          width: root.width
          wrapMode: Text.WordWrap
          text: "Ticked ones show beside the device glyph in the bar, in this order. Drag one by its grip, or Shift+K / Shift+J on the selected one."
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
        }

        Repeater {
          model: root.rows
          ShortcutRow {
            required property var modelData
            required property int index
            visible: modelData.kind === "bar"
            width: root.width
            row: modelData
            rowIndex: index
          }
        }

        Repeater {
          model: root.rows
          LayoutRow {
            required property var modelData
            required property int index
            visible: modelData.kind === "barFlag"
            width: root.width
            row: modelData
            rowIndex: index
          }
        }
    }

    Item { width: 1; height: Style.space(6) }
    PanelSeparator { foreground: root.foreground }

    // ---- Shortcuts ----
    FoldToggle {
      width: root.width
      title: root.groupTitle("SHORTCUTS", "shortcuts")
      summary: Model.shortcutsSummary(root.order)
      folded: root.isFolded("shortcuts")
      foreground: root.foreground
      fontFamily: root.fontFamily
      motion: root.motion
      animate: root.animate
      onToggled: root.foldToggled("shortcuts")
    }

    FoldBody {
      open: !root.isFolded("shortcuts")
      motion: root.motion
      animate: root.animate
      spacing: Style.space(6)

        Text {
          textFormat: Text.PlainText
          width: root.width
          wrapMode: Text.WordWrap
          text: root.shortcutsShown
            ? "Ticked ones show under the header, four per row, in this order. Drag one by its grip, or Shift+K / Shift+J on the selected one."
            : "The shortcuts row is off in Layout. What you pick here shows once it is on again."
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
        }

        Repeater {
          model: root.rows
          ShortcutRow {
            required property var modelData
            required property int index
            visible: modelData.kind === "shortcut"
            width: root.width
            row: modelData
            rowIndex: index
          }
        }

    }

    Repeater {
      model: root.rows
      ListRow {
        required property var modelData
        required property int index
        visible: modelData.kind === "resetGroup"
        width: root.width
        row: modelData
        rowIndex: index
      }
    }
  }

  // ---- Connection and Add a device: rows that open the Connection page ----
  Item { visible: root.firstIndex("connection") >= 0; width: 1; height: Style.space(6) }
  PanelSeparator { visible: root.firstIndex("connection") >= 0; foreground: root.foreground }
  Repeater {
    model: root.rows
    ListRow {
      required property var modelData
      required property int index
      visible: modelData.kind === "connection" || modelData.kind === "addDevice"
      width: root.width
      row: modelData
      rowIndex: index
    }
  }

  // ---- Connection: this computer (checking what exists). Add a device:
  //      requests to pair, the steps on it, devices in reach (making a new
  //      pairing) ----
  // The page is named This computer: its checks need no header of their own.
  Text {
    visible: root.scopeKind === "connection" && root.firstIndex("check") < 0
    textFormat: Text.PlainText
    text: "Checking…"
    color: root.dim
    font.family: root.fontFamily
    font.pixelSize: Style.font.bodySmall
  }
  Repeater {
    model: root.rows
    CheckRow {
      required property var modelData
      required property int index
      visible: modelData.kind === "check"
      width: root.width
      row: modelData
      rowIndex: index
    }
  }
  // Every fix there is, this computer's and the device's, in one go: a
  // password only after its card says what for.
  Button {
    visible: root.scopeKind === "connection" && root.fixAllCount > 0
    text: root.phone && root.phone.isBusy("fixAll") ? "Fixing…" : "Fix all (" + root.fixAllCount + ")"
    iconText: Model.GLYPH.check
    enabled: !(root.phone && root.phone.isBusy("fixAll"))
    tooltipText: "Runs every fix the plugin can do here and on the device; anything that needs your password is shown first"
    bordered: true
    foreground: root.foreground
    fontFamily: root.fontFamily
    fontSize: Style.font.bodySmall
    onClicked: root.fixAllRequested()
  }

  PanelSectionHeader {
    visible: root.firstIndex("request") >= 0 && root.scopeKind === "addDevice"
    text: "PAIRING REQUESTS"
    foreground: root.foreground
    fontFamily: root.fontFamily
  }
  Repeater {
    model: root.scopeKind === "addDevice" ? root.rows : []
    PairingCardRow {
      required property var modelData
      required property int index
      visible: modelData.kind === "request"
      width: root.width
      row: modelData
      rowIndex: index
    }
  }
  PairedCard { visible: root.scopeKind === "addDevice" && !!root.justPaired && root.justPaired.kind === "request" }

  PanelSectionHeader {
    visible: root.scopeKind === "addDevice"
    text: "ON THE DEVICE"
    foreground: root.foreground
    fontFamily: root.fontFamily
  }
  SetupChecks {
    visible: root.scopeKind === "addDevice"
    width: root.width
    network: root.network
    // The app's QR code: on Add a device always, for a first device or another (#64).
    showQr: root.scopeKind === "addDevice"
    platform: root.appPlatform
    onPlatformSet: function(p) { root.appPlatformSet(p) }
    foreground: root.foreground
    fontFamily: root.fontFamily
  }
  Text {
    visible: root.scopeKind === "addDevice"
    width: root.width
    textFormat: Text.PlainText
    wrapMode: Text.WordWrap
    text: root.firstIndex("available") >= 0 ? "In reach, to pair with:" : "Looking for new devices… they show here with Pair."
    color: root.dim
    font.family: root.fontFamily
    font.pixelSize: Style.font.caption
  }
  Repeater {
    model: root.scopeKind === "addDevice" ? root.rows : []
    ListRow {
      required property var modelData
      required property int index
      visible: modelData.kind === "available" && !modelData.pairKey
      width: root.width
      row: modelData
      rowIndex: index
    }
  }
  // A pairing this computer asked for, waiting on the device: a card.
  Repeater {
    model: root.scopeKind === "addDevice" ? root.rows : []
    PairingCardRow {
      required property var modelData
      required property int index
      visible: modelData.kind === "available" && !!modelData.pairKey
      width: root.width
      row: modelData
      rowIndex: index
    }
  }
  PairedCard { visible: root.scopeKind === "addDevice" && !!root.justPaired && root.justPaired.kind === "available" }

  // ---- Screen and apps: the steps, then the page's actions ----
  ScreenSetup {
    visible: root.scopeKind === "screen"
    width: root.width
    setup: root.screenSetup
    qr: root.screenQr
    showLine: !root.screenSetup || root.screenSetup.state !== "ready"
    foreground: root.foreground
    fontFamily: root.fontFamily
  }
  // Each control drawn as what it is: the screen (a tile, as its shortcut),
  // where it opens (one of two), a switch, and the setup's own actions.
  Repeater {
    model: root.scopeKind === "screen" ? root.rows : []
    ScreenTileRow {
      required property var modelData
      required property int index
      visible: modelData.kind === "screenAction" && modelData.key === "open"
      row: modelData
      rowIndex: index
    }
  }
  Repeater {
    model: root.scopeKind === "screen" ? root.rows : []
    ScreenPlaceRow {
      required property var modelData
      required property int index
      visible: modelData.kind === "screenAction" && modelData.key === "place"
      row: modelData
      rowIndex: index
    }
  }
  Repeater {
    model: root.scopeKind === "screen" ? root.rows : []
    ScreenSoundRow {
      required property var modelData
      required property int index
      visible: modelData.kind === "screenAction" && modelData.key === "appSound"
      row: modelData
      rowIndex: index
    }
  }
  Repeater {
    model: root.scopeKind === "screen" ? root.rows : []
    ListRow {
      required property var modelData
      required property int index
      visible: modelData.kind === "screenAction" && modelData.key !== "open" && modelData.key !== "place" && modelData.key !== "appSound"
      width: root.width
      row: modelData
      rowIndex: index
    }
  }

  // Not ready to pair: what the panel shows once a phone is set up, with a
  // made-up one. Last, after pairing, which comes first.
  Button {
    visible: root.scopeKind === "addDevice" && root.canPreview
    text: "Preview with a demo phone"
    iconText: Model.GLYPH.phone
    tooltipText: "What the panel shows once a phone is set up; made-up data, nothing reaches a device"
    bordered: true
    foreground: root.foreground
    fontFamily: root.fontFamily
    fontSize: Style.font.bodySmall
    onClicked: root.previewRequested()
  }

  // The page's buttons (Unpair, Reset shortcuts, KDE Connect settings):
  // their row takes room only when one of them shows (hidden buttons still
  // left it 44 px tall, an empty band at the bottom of Add a device).
  readonly property bool hasButtons: firstIndex("unpair") >= 0 || firstIndex("reset") >= 0 || firstIndex("kdeconnect") >= 0
  Item { visible: root.hasButtons; width: 1; height: Style.space(2) }

  Row {
    visible: root.hasButtons
    spacing: Style.space(8)

    Button {
      readonly property int rowIndex: root.firstIndex("unpair")
      visible: rowIndex >= 0
      text: root.unpairArmed ? "Unpair? Again to confirm" : "Unpair"
      iconText: Model.GLYPH.close
      tooltipText: "Forget this device; pair again from it to come back"
      foreground: root.unpairArmed ? Color.urgent : root.foreground
      fontFamily: root.fontFamily
      bordered: true
      hasCursor: root.cursorIndex === rowIndex
      onHovered: function(on) { if (on) root.hovered(rowIndex) }
      onClicked: root.activated(rowIndex)
    }

    Button {
      readonly property int rowIndex: root.firstIndex("reset")
      visible: rowIndex >= 0
      text: "Reset shortcuts"
      iconText: Model.GLYPH.reset
      tooltipText: "Back to Ring, Send files, Clipboard and Messages"
      foreground: root.foreground
      fontFamily: root.fontFamily
      bordered: true
      hasCursor: root.cursorIndex === rowIndex
      onHovered: function(on) { if (on) root.hovered(rowIndex) }
      onClicked: root.activated(rowIndex)
    }

    Button {
      readonly property int rowIndex: root.firstIndex("kdeconnect")
      visible: rowIndex >= 0
      text: "KDE Connect settings"
      iconText: Model.GLYPH.phoneCog
      tooltipText: "Pairing, device permissions and KDE Connect's own plugins"
      foreground: root.foreground
      fontFamily: root.fontFamily
      bordered: true
      hasCursor: root.cursorIndex === rowIndex
      onHovered: function(on) { if (on) root.hovered(rowIndex) }
      onClicked: root.activated(rowIndex)
    }
  }

  // ---- Moving rows in their orders (Reorder): drag, arrows, keyboard ----
  function rowAt(kind, pos) {
    for (var i = 0; i < rows.length; i++) {
      var r = rows[i]
      if (r.kind === kind && r.pos === pos && (r.on === true || kind === "device" || kind === "layout")) return r
    }
    return null
  }
  function countOf(kind) {
    var n = 0
    for (var i = 0; i < rows.length; i++) {
      var r = rows[i]
      if (r.kind === kind && r.pos >= 0 && (r.on === true || kind === "device" || kind === "layout")) n++
    }
    return n
  }
  function orderFor(kind) {
    return kind === "device" ? deviceOrder : kind === "layout" ? layoutOrder
         : kind === "bar" ? barOrder : kind === "shortcut" ? shortcutOrder : null
  }
  // The keyboard (Shift+K / Shift+J): the same glide as the arrows and a drop.
  function glideMove(kind, pos, delta) {
    var o = orderFor(kind)
    if (!o || pos < 0) return false
    o.step(pos, delta)
    return true
  }

  Reorder {
    id: deviceOrder
    count: root.countOf("device")
    gap: Style.space(4)
    motion: root.motion
    onMoved: function(a, b) { var r = root.rowAt("device", a); if (r) root.deviceMoveRequested(r.id, b - a) }
  }
  Reorder {
    id: layoutOrder
    count: root.countOf("layout")
    gap: Style.space(6)
    motion: root.motion
    onMoved: function(a, b) { var r = root.rowAt("layout", a); if (r) root.sectionMoveRequested(r.section, b - a) }
  }
  Reorder {
    id: barOrder
    count: root.countOf("bar")
    gap: Style.space(6)
    motion: root.motion
    onMoved: function(a, b) { var r = root.rowAt("bar", a); if (r) root.barMoveRequested(r.key, b - a) }
  }
  Reorder {
    id: shortcutOrder
    count: root.countOf("shortcut")
    gap: Style.space(6)
    motion: root.motion
    onMoved: function(a, b) { var r = root.rowAt("shortcut", a); if (r) root.moveRequested(r.key, b - a) }
  }

  // A row of the device list (a device, one asking to pair, one in reach),
  // the Defaults row, or a group's "use the defaults".
  component ListRow: CursorSurface {
    id: listRow
    property var row: ({})
    property int rowIndex: -1
    readonly property bool hasPills: !!row.pills && row.pills.length > 0
    readonly property bool working: !!root.phone && (root.phone.isBusy("pair:" + row.id) || root.phone.isBusy("accept:" + row.id) || root.phone.isBusy("reject:" + row.id))

    hasCursor: false
    CursorStop { here: root.cursorIndex === rowIndex; glide: root.cursorGlide }
    foreground: root.foreground
    implicitHeight: listContent.implicitHeight + Style.space(12)
    readonly property int place: listRow.row.kind === "device" ? (listRow.row.pos || 0) : -1
    readonly property bool moving: place >= 0 && deviceOrder.from === place
    onHeightChanged: if (place >= 0) deviceOrder.itemSize = height
    transform: ReorderShift { order: deviceOrder; index: listRow.place }
    z: moving ? 10 : 0
    // Solid while it moves, so the row it passes over never shows through.
    color: moving ? Qt.tint(root.panelBackground, fill) : (hasCursor ? fill : (current ? currentFill : "transparent"))

    MouseArea {
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onEntered: root.hovered(listRow.rowIndex)
      onClicked: root.activated(listRow.rowIndex)
    }

    RowLayout {
      id: listContent
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      anchors.leftMargin: Style.space(10)
      anchors.rightMargin: Style.space(6)
      spacing: Style.space(10)

      ReorderGrip {
        visible: listRow.place >= 0
        order: deviceOrder
        index: listRow.place
        item: listRow
        foreground: root.foreground
        fontFamily: root.fontFamily
      }

      Text {
        visible: (listRow.row.glyph || "") !== ""
        text: listRow.row.glyph || ""
        color: root.foreground
        opacity: listRow.row.away === true ? 0.5 : 1
        font.family: root.fontFamily
        font.pixelSize: Style.font.icon
        Layout.preferredWidth: Style.space(20)
        horizontalAlignment: Text.AlignHCenter
        Layout.alignment: Qt.AlignVCenter
      }

      ColumnLayout {
        Layout.fillWidth: true
        spacing: Style.space(1)
        Text {
          textFormat: Text.PlainText
          Layout.fillWidth: true
          text: listRow.row.kind === "device" && listRow.row.title !== listRow.row.name
            ? listRow.row.title + "  ·  " + listRow.row.name : (listRow.row.title || listRow.row.label || "")
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
          elide: Text.ElideRight
        }
        Text {
          textFormat: Text.PlainText
          Layout.fillWidth: true
          visible: text !== "" && !listRow.hasPills
          readonly property string note: root.pairingNotes[listRow.row.id] || ""
          text: note !== "" ? note + " · pair again" : (listRow.row.status || listRow.row.hint || "")
          color: note !== "" ? Color.urgent : root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          elide: Text.ElideRight
        }
        // Connection: a pill per capability, on, off (more can be set up)
        // or failing, in place of a one-word summary.
        Flow {
          visible: listRow.hasPills
          Layout.fillWidth: true
          Layout.topMargin: Style.space(3)
          spacing: Style.space(4)
          Repeater {
            model: listRow.hasPills ? listRow.row.pills : []
            CapabilityPill {
              required property var modelData
              pill: modelData
            }
          }
        }
        // Pairing: the key to compare, drawn as on the pop-up.
        PairingKey {
          Layout.topMargin: Style.space(4)
          key: listRow.row.pairKey || ""
          caption: listRow.row.kind === "request" ? "check it matches" : "accept on it if it matches"
          compact: true
          foreground: root.foreground
          fontFamily: root.fontFamily
        }
      }

      // Asking to pair: accept or reject. In reach: pair.
      Button {
        visible: listRow.row.kind === "request" || listRow.row.kind === "available"
        Layout.alignment: Qt.AlignVCenter
        text: listRow.working ? "Waiting…" : (listRow.row.kind === "request" ? "Accept" : (listRow.row.waiting ? "Waiting…" : "Pair"))
        enabled: !listRow.working && listRow.row.waiting !== true
        bordered: true
        foreground: root.foreground
        fontFamily: root.fontFamily
        fontSize: Style.font.bodySmall
        onClicked: root.activated(listRow.rowIndex)
      }
      PanelActionButton {
        visible: listRow.row.kind === "request"
        iconText: Model.GLYPH.close
        tooltipText: "Reject"
        foreground: root.foreground
        fontFamily: root.fontFamily
        onClicked: root.rejectRequested(listRow.row.id)
      }

      Text {
        visible: ["device", "defaults", "editPage", "screen", "connection", "addDevice"].indexOf(listRow.row.kind) >= 0
        text: Model.GLYPH.chevronRight
        color: root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.icon
        Layout.alignment: Qt.AlignVCenter
      }
      // A choice on Screen and apps (Opens under the bar, Opens as a window).
      Text {
        visible: listRow.row.kind === "screenAction" && listRow.row.on !== undefined
        text: listRow.row.on === true ? Model.GLYPH.checked : Model.GLYPH.unchecked
        color: listRow.row.on === true ? root.foreground : root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.icon
        Layout.alignment: Qt.AlignVCenter
      }
      Text {
        visible: listRow.row.kind === "resetGroup"
        text: Model.GLYPH.reset
        color: root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.icon
        Layout.alignment: Qt.AlignVCenter
      }
    }
  }

  // A pairing that just completed: its card, turned ✓, before the panel goes
  // to the device.
  component PairedCard: BorderSurface {
    width: root.width
    implicitHeight: pairedRow.implicitHeight + 2 * Style.space(12)
    radius: Style.cornerRadius
    color: root.panelBackground
    borderSpec: Border.controlSpec("focus", root.foreground, Color.accent)
    RowLayout {
      id: pairedRow
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      anchors.leftMargin: Style.space(14)
      anchors.rightMargin: Style.space(12)
      spacing: Style.space(14)
      Text {
        text: root.justPaired ? root.justPaired.glyph : ""
        color: Color.accent
        font.family: root.fontFamily
        font.pixelSize: Style.font.display
      }
      ColumnLayout {
        Layout.fillWidth: true
        spacing: Style.space(2)
        Text {
          Layout.fillWidth: true
          textFormat: Text.PlainText
          text: Model.GLYPH.check + "  Paired with " + (root.justPaired ? root.justPaired.title : "")
          color: Color.accent
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
          font.bold: true
          elide: Text.ElideRight
        }
        Text {
          Layout.fillWidth: true
          textFormat: Text.PlainText
          text: "Opening it…"
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
        }
      }
    }
  }

  // A pairing in progress, on Add a device: a card, as the pop-up and the
  // panel's pairing card draw it (the device, what it asks; the key and the
  // answer on one row).
  component PairingCardRow: Column {
    id: pcard
    property var row: ({})
    property int rowIndex: -1
    readonly property bool incoming: row.kind === "request"
    readonly property bool working: !!root.phone && (root.phone.isBusy("accept:" + row.id) || root.phone.isBusy("reject:" + row.id))
    spacing: 0

    BorderSurface {
      width: parent.width
      implicitHeight: pcardContent.implicitHeight + 2 * Style.space(12)
      radius: Style.cornerRadius
      color: root.panelBackground
      borderSpec: Border.controlSpec(root.cursorIndex === pcard.rowIndex ? "hover-cursor" : "focus", root.foreground, Color.accent)

      MouseArea {
        anchors.fill: parent
        hoverEnabled: true
        onEntered: root.hovered(pcard.rowIndex)
      }

      RowLayout {
        id: pcardContent
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        anchors.leftMargin: Style.space(14)
        anchors.rightMargin: Style.space(12)
        spacing: Style.space(14)

        Text {
          Layout.alignment: Qt.AlignTop
          Layout.topMargin: Style.space(2)
          text: pcard.row.glyph || ""
          color: Color.accent
          font.family: root.fontFamily
          font.pixelSize: Style.font.display
        }
        ColumnLayout {
          Layout.fillWidth: true
          spacing: Style.space(8)
          RowLayout {
            Layout.fillWidth: true
            Text {
              Layout.fillWidth: true
              textFormat: Text.PlainText
              text: pcard.incoming ? (pcard.row.title || "A device") + " wants to pair" : "Pairing with " + (pcard.row.title || "a device")
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
              font.bold: true
              elide: Text.ElideRight
            }
            // KDE Connect gives up after 30 s: how long is left.
            Text {
              readonly property real since: root.pairingSince[pcard.row.id] || 0
              visible: !pcard.incoming && since > 0
              textFormat: Text.PlainText
              text: Model.pairSecondsLeft(since, root.pairClock) + " s"
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
            }
          }
          RowLayout {
            Layout.fillWidth: true
            spacing: Style.space(8)
            PairingKey {
              Layout.fillWidth: true
              Layout.alignment: Qt.AlignBottom
              key: pcard.row.pairKey || ""
              caption: pcard.incoming ? "check it matches" : "accept on it if it matches"
              foreground: root.foreground
              fontFamily: root.fontFamily
            }
            Item { Layout.fillWidth: true; visible: !pcard.row.pairKey }
            Button {
              Layout.alignment: Qt.AlignBottom
              visible: pcard.incoming
              text: pcard.working ? "Waiting…" : "Accept"
              enabled: !pcard.working
              bordered: true
              foreground: root.foreground
              fontFamily: root.fontFamily
              fontSize: Style.font.bodySmall
              onClicked: root.activated(pcard.rowIndex)
            }
            Button {
              Layout.alignment: Qt.AlignBottom
              text: pcard.incoming ? "Reject" : "Cancel"
              enabled: !pcard.working
              foreground: root.foreground
              fontFamily: root.fontFamily
              fontSize: Style.font.bodySmall
              onClicked: root.rejectRequested(pcard.row.id)
            }
          }
        }
      }
    }
  }

  // A capability on the Connection row: on (✓), off (○: an optional
  // feature not set up; neutral, nothing is wrong) or failing (!).
  component CapabilityPill: Rectangle {
    id: pillBox
    property var pill: ({})
    readonly property bool failing: pill.state === "fail"
    readonly property bool on: pill.state === "on"
    implicitWidth: pillRow.implicitWidth + Style.space(12)
    implicitHeight: pillRow.implicitHeight + Style.space(4)
    radius: height / 2
    color: "transparent"
    border.width: 1
    border.color: failing ? Color.urgent : (on ? Qt.darker(root.foreground, 1.3) : Qt.darker(root.foreground, 2.2))
    Row {
      id: pillRow
      anchors.centerIn: parent
      spacing: Style.space(4)
      Text {
        anchors.verticalCenter: parent.verticalCenter
        text: pillBox.failing ? Model.GLYPH.alert : (pillBox.on ? Model.GLYPH.check : Model.GLYPH.optional)
        color: pillBox.failing ? Color.urgent : (pillBox.on ? root.foreground : root.dim)
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
      }
      Text {
        anchors.verticalCenter: parent.verticalCenter
        textFormat: Text.PlainText
        text: pillBox.pill.label || ""
        color: pillBox.failing ? Color.urgent : (pillBox.on ? root.foreground : root.dim)
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
      }
    }
  }

  // The device's screen as a tile, drawn as its Screen shortcut is: on (the
  // accent, a ✕ to close it) while its window is open, where a click brings
  // it forward. Its status and a line of help beside it.
  component ScreenTileRow: Row {
    id: str
    property var row: ({})
    property int rowIndex: -1
    readonly property bool working: !!root.phone && root.phone.isBusy("screen")
    width: root.width
    spacing: Style.space(14)

    CursorSurface {
      id: tileBox
      width: Math.round((root.width - 3 * Style.space(8)) / 4)
      height: tileCol.implicitHeight + Style.space(18)
      hasCursor: false
      bordered: true
      foreground: root.foreground
      CursorStop { here: root.cursorIndex === str.rowIndex; glide: root.cursorGlide }

      Rectangle {
        anchors.fill: parent
        radius: tileBox.radius
        color: Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, 0.14)
        border.width: 1
        border.color: Color.accent
        opacity: root.screenOpen ? 1 : 0
        visible: opacity > 0
        Behavior on opacity { NumberAnimation { duration: (root.screenOpen ? Model.MOTION.inMs : Model.MOTION.outMs) * root.motion; easing.type: Easing.OutCubic } }
      }
      Column {
        id: tileCol
        anchors.centerIn: parent
        spacing: Style.space(4)
        // Connecting: the waiting ring in place of the glyph, as on the
        // shortcut's tile.
        Item {
          anchors.horizontalCenter: parent.horizontalCenter
          width: tileGlyph.implicitWidth
          height: tileGlyph.implicitHeight
          Text {
            id: tileGlyph
            anchors.centerIn: parent
            text: Model.GLYPH.screen
            color: root.screenOpen ? Color.accent : root.foreground
            opacity: str.working ? 0 : 1.0
            font.family: root.fontFamily
            font.pixelSize: Style.font.heading + 2
            Behavior on opacity { NumberAnimation { duration: Model.MOTION.outMs * root.motion; easing.type: Easing.OutCubic } }
          }
          WaitRing {
            anchors.centerIn: parent
            running: str.working
            motion: root.motion
            color: root.foreground
            size: Math.round(Style.font.heading * 0.8)
          }
        }
        Text {
          anchors.horizontalCenter: parent.horizontalCenter
          textFormat: Text.PlainText
          text: str.row.label || ""
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
        }
      }
      MouseArea {
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onEntered: root.hovered(str.rowIndex)
        onClicked: root.activated(str.rowIndex)
      }
      PanelActionButton {
        visible: root.screenOpen
        anchors.top: parent.top
        anchors.right: parent.right
        anchors.margins: Style.space(2)
        size: Style.space(18)
        iconText: Model.GLYPH.close
        tooltipText: "Close its screen"
        foreground: root.foreground
        fontFamily: root.fontFamily
        onClicked: root.screenCloseRequested()
      }
    }
    Column {
      anchors.verticalCenter: tileBox.verticalCenter
      width: str.width - tileBox.width - str.spacing
      spacing: Style.space(2)
      Text {
        width: parent.width
        textFormat: Text.PlainText
        wrapMode: Text.WordWrap
        text: root.screenSetup ? root.screenSetup.line : ""
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.bodySmall
      }
      Text {
        width: parent.width
        textFormat: Text.PlainText
        wrapMode: Text.WordWrap
        text: root.screenOpen ? "Open: click to bring it forward" : (str.row.hint || "")
        color: root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
      }
    }
  }

  // Where the screen opens: one of two, as a choice is drawn in Settings
  // (the chosen one filled), with a line on the chosen one.
  // Where an app's sound plays (#116): one of two, as where the screen opens.
  component ScreenSoundRow: Column {
    id: ssr
    property var row: ({})
    property int rowIndex: -1
    width: root.width
    spacing: Style.space(6)
    topPadding: Style.space(6)

    PanelSectionHeader {
      text: "AN APP'S SOUND"
      foreground: root.foreground
      fontFamily: root.fontFamily
    }
    Item {
      width: parent.width
      height: soundRow.implicitHeight + Style.space(8)
      CursorStop { here: root.cursorIndex === ssr.rowIndex; glide: root.cursorGlide }
      MouseArea {
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.NoButton
        onEntered: root.hovered(ssr.rowIndex)
      }
      Row {
        id: soundRow
        anchors.verticalCenter: parent.verticalCenter
        x: Style.space(4)
        spacing: Style.space(4)
        Button {
          text: "Here"
          iconText: Model.GLYPH.volume
          selected: ssr.row.sound === "here"
          bordered: true
          foreground: root.foreground
          fontFamily: root.fontFamily
          fontSize: Style.font.bodySmall
          onClicked: root.appSoundChosen("here")
        }
        Button {
          text: "On " + (ssr.row.device || "the device")
          iconText: Model.GLYPH.phone
          selected: ssr.row.sound === "phone"
          bordered: true
          foreground: root.foreground
          fontFamily: root.fontFamily
          fontSize: Style.font.bodySmall
          onClicked: root.appSoundChosen("phone")
        }
      }
    }
    Text {
      width: parent.width
      textFormat: Text.PlainText
      wrapMode: Text.WordWrap
      text: ssr.row.hint || ""
      color: root.dim
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
    }
  }

  component ScreenPlaceRow: Column {
    id: spr
    property var row: ({})
    property int rowIndex: -1
    width: root.width
    spacing: Style.space(6)
    topPadding: Style.space(6)

    PanelSectionHeader {
      text: "OPENS"
      foreground: root.foreground
      fontFamily: root.fontFamily
    }
    Item {
      width: parent.width
      height: segRow.implicitHeight + Style.space(8)
      CursorStop { here: root.cursorIndex === spr.rowIndex; glide: root.cursorGlide }
      MouseArea {
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.NoButton
        onEntered: root.hovered(spr.rowIndex)
      }
      Row {
        id: segRow
        anchors.verticalCenter: parent.verticalCenter
        x: Style.space(4)
        spacing: Style.space(4)
        Button {
          text: "Under the bar"
          iconText: Model.GLYPH.dockTop
          selected: spr.row.docked === true
          bordered: true
          foreground: root.foreground
          fontFamily: root.fontFamily
          fontSize: Style.font.bodySmall
          onClicked: root.screenPlaceChosen(true)
        }
        Button {
          text: "As a window"
          iconText: Model.GLYPH.window
          selected: spr.row.docked === false
          bordered: true
          foreground: root.foreground
          fontFamily: root.fontFamily
          fontSize: Style.font.bodySmall
          onClicked: root.screenPlaceChosen(false)
        }
      }
    }
    Text {
      width: parent.width
      textFormat: Text.PlainText
      wrapMode: Text.WordWrap
      text: spr.row.hint || ""
      color: root.dim
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
    }
    // How to free it and dock it back: Omarchy's keys, as key caps.
    Column {
      topPadding: Style.space(4)
      spacing: Style.space(5)
      Repeater {
        model: spr.row.keys || []
        Row {
          required property var modelData
          spacing: Style.space(10)
          Row {
            id: caps
            width: Style.space(96)
            spacing: Style.space(3)
            // No key for it on this machine: said, as the tips say it.
            Text {
              visible: !modelData.keys || modelData.keys.length === 0
              anchors.verticalCenter: parent.verticalCenter
              textFormat: Text.PlainText
              text: Model.NO_SHORTCUT
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              font.italic: true
            }
            Repeater {
              model: modelData.keys || []
              Rectangle {
                required property string modelData
                width: capText.implicitWidth + Style.space(10)
                height: capText.implicitHeight + Style.space(4)
                radius: Style.space(3)
                color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.08)
                border.width: 1
                border.color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.22)
                Text {
                  id: capText
                  anchors.centerIn: parent
                  textFormat: Text.PlainText
                  text: modelData
                  color: root.foreground
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                }
              }
            }
          }
          Text {
            anchors.verticalCenter: caps.verticalCenter
            textFormat: Text.PlainText
            text: modelData.text
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
          }
        }
      }
    }
  }

  // A check on this computer: its status icon, name, short status and one
  // action (its fix), with a line of detail while it fails. A failing one
  // can be ignored (it stops lighting the gear's dot) and brought back.
  // A feature of the device: its glyph, name and state, what is missing, its
  // one action (it just works: the plugin does every step it can), and a
  // switch where it can be turned off (its KDE Connect plugins).
  component FeatureRow: CursorSurface {
    id: featureRow
    property var row: ({})
    property int rowIndex: -1
    readonly property bool working: !!root.phone && (root.phone.isBusy("feature:" + row.key) || root.phone.isBusy("fixAll"))
    readonly property bool acts: row.key === "screen" || (row.steps || []).length > 0
    hasCursor: false
    CursorStop { here: root.cursorIndex === featureRow.rowIndex; glide: root.cursorGlide }
    foreground: root.foreground
    implicitHeight: featureContent.implicitHeight + Style.space(12)

    MouseArea {
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: featureRow.acts ? Qt.PointingHandCursor : Qt.ArrowCursor
      onEntered: root.hovered(featureRow.rowIndex)
      onClicked: if (featureRow.acts) root.featureRequested(featureRow.rowIndex)
    }

    RowLayout {
      id: featureContent
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      anchors.leftMargin: Style.space(10)
      anchors.rightMargin: Style.space(6)
      spacing: Style.space(10)

      Text {
        Layout.alignment: Qt.AlignVCenter
        Layout.preferredWidth: Style.space(20)
        horizontalAlignment: Text.AlignHCenter
        text: featureRow.row.glyph || ""
        color: featureRow.row.state === "on" ? root.foreground : root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
      }
      ColumnLayout {
        Layout.fillWidth: true
        spacing: Style.space(1)
        RowLayout {
          Layout.fillWidth: true
          spacing: Style.space(10)
          Text {
            Layout.fillWidth: true
            textFormat: Text.PlainText
            text: featureRow.row.label || ""
            color: featureRow.row.state === "on" || featureRow.row.state === "attention" || featureRow.row.state === "setup" ? root.foreground : root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
            elide: Text.ElideRight
          }
          Text {
            textFormat: Text.PlainText
            text: featureRow.working ? "Working…" : (featureRow.row.stateLabel || "")
            color: featureRow.row.state === "attention" ? Color.urgent : root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
          }
        }
        Text {
          Layout.fillWidth: true
          visible: text !== "" && featureRow.row.state !== "on" && !featureRow.row.pending
          textFormat: Text.PlainText
          wrapMode: Text.WordWrap
          text: featureRow.row.detail || featureRow.row.hint || ""
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
        }
        // What a fix left: the step for the user, then waiting for it (it is
        // seen when done) or Check again; or that it did not work.
        Text {
          visible: !!featureRow.row.pending
          Layout.fillWidth: true
          textFormat: Text.PlainText
          wrapMode: Text.WordWrap
          text: featureRow.row.pending ? featureRow.row.pending.text : ""
          color: featureRow.row.pending && featureRow.row.pending.failed ? Color.urgent : root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
        }
        RowLayout {
          visible: !!featureRow.row.pending && featureRow.row.pending.failed !== true
          spacing: Style.space(6)
          WaitRing {
            visible: !!featureRow.row.pending && featureRow.row.pending.wait === true
            running: visible
            color: root.dim
            size: Math.round(Style.font.caption * 0.9)
          }
          Text {
            visible: !!featureRow.row.pending && featureRow.row.pending.wait === true
            textFormat: Text.PlainText
            text: "Waiting for it…"
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
          }
          Button {
            visible: !!featureRow.row.pending && featureRow.row.pending.wait !== true && featureRow.row.pending.failed !== true
            text: "Check again"
            foreground: root.foreground
            fontFamily: root.fontFamily
            fontSize: Style.font.caption
            onClicked: root.checkAgainRequested()
          }
        }
        // Its actions, on a line of their own so the name keeps its room.
        Row {
          visible: fixButton.visible || aiButton.visible
          Layout.topMargin: Style.space(4)
          spacing: Style.space(6)
          Button {
            id: fixButton
            // Not while it waits for the user's step: nothing to press again.
            visible: !(featureRow.row.pending && featureRow.row.pending.wait === true) && featureRow.acts && ((featureRow.row.state !== "on" && featureRow.row.state !== "off" && featureRow.row.state !== "away" && featureRow.row.state !== "unavailable")
                                         || featureRow.row.problem === true)
            text: featureRow.working ? "Working…" : (featureRow.row.state === "attention" ? "Fix" : featureRow.row.key === "screen" ? "Set up" : "Turn on")
            enabled: !featureRow.working
            tooltipText: (featureRow.row.steps || []).some(function(s) { return s.fix && s.fix.verb === "fix" && s.fix.what !== "restart" })
              ? "Shows what your password is for before asking for it" : "Does what it can, then says what is left"
            bordered: true
            foreground: root.foreground
            fontFamily: root.fontFamily
            fontSize: Style.font.bodySmall
            onClicked: root.featureRequested(featureRow.rowIndex)
          }
          Button {
            id: aiButton
            visible: featureRow.row.problem === true && !featureRow.working
            text: "Fix with AI"
            tooltipText: root.aiTip
            foreground: root.foreground
            fontFamily: root.fontFamily
            fontSize: Style.font.bodySmall
            onClicked: root.fixWithAiRequested("feature", featureRow.rowIndex)
          }
        }
      }
      ToggleSwitch {
        visible: featureRow.row.switchable === true && featureRow.row.state !== "away" && featureRow.row.state !== "unavailable"
        Layout.alignment: Qt.AlignVCenter
        checked: featureRow.row.on !== false
        busy: featureRow.working
        foreground: root.foreground
        onToggled: root.featureSwitched(featureRow.rowIndex, featureRow.row.on === false)
      }
    }
  }

  component CheckRow: CursorSurface {
    id: checkRow
    property var row: ({})
    property int rowIndex: -1
    // Optional (Screen and apps): missing is a choice, not a fault; it
    // offers its install, never alerts and has nothing to ignore.
    readonly property bool optional: row.optional === true
    readonly property bool failing: row.ok !== true && row.ignored !== true && !optional
    readonly property bool offering: row.ok !== true && (failing || optional)
    // Optional and installed: its button leads to the next step (Set up a device).
    readonly property bool leading: row.ok === true && optional && (row.fix || "") !== ""
    readonly property bool fixing: root.setupFixing[row.fix] === true
    hasCursor: false
    CursorStop { here: root.cursorIndex === rowIndex; glide: root.cursorGlide }
    foreground: root.foreground
    implicitHeight: checkContent.implicitHeight + Style.space(12)

    MouseArea {
      anchors.fill: parent
      hoverEnabled: true
      onEntered: root.hovered(checkRow.rowIndex)
    }

    RowLayout {
      id: checkContent
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      anchors.leftMargin: Style.space(10)
      anchors.rightMargin: Style.space(6)
      spacing: Style.space(10)

      Text {
        Layout.alignment: Qt.AlignVCenter
        Layout.preferredWidth: Style.space(20)
        horizontalAlignment: Text.AlignHCenter
        text: checkRow.row.ok === true ? Model.GLYPH.check : (checkRow.optional ? Model.GLYPH.optional : Model.GLYPH.alert)
        color: checkRow.failing ? Color.urgent : root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
      }
      ColumnLayout {
        Layout.fillWidth: true
        spacing: Style.space(1)
        RowLayout {
          Layout.fillWidth: true
          spacing: Style.space(10)
          Text {
            Layout.fillWidth: true
            textFormat: Text.PlainText
            text: checkRow.row.label || ""
            color: checkRow.offering ? root.foreground : root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
            elide: Text.ElideRight
          }
          Text {
            textFormat: Text.PlainText
            text: checkRow.row.ignored === true ? "Ignored" : (checkRow.row.status || "")
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
          }
        }
        Text {
          Layout.fillWidth: true
          visible: checkRow.offering && text !== ""
          textFormat: Text.PlainText
          wrapMode: Text.WordWrap
          text: checkRow.row.detail || ""
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
        }
      }
      Button {
        visible: (checkRow.offering || checkRow.leading) && (checkRow.row.fix || "") !== ""
        Layout.alignment: Qt.AlignVCenter
        text: checkRow.fixing ? "Working…" : (checkRow.row.fixLabel || "Fix")
        iconText: checkRow.fixing ? "\u{F0996}" : ""
        iconSpinning: checkRow.fixing
        enabled: !checkRow.fixing
        tooltipText: ["install", "firewall", "screen"].indexOf(checkRow.row.fix) >= 0 ? "Asks for your password" : ""
        bordered: true
        foreground: root.foreground
        fontFamily: root.fontFamily
        fontSize: Style.font.bodySmall
        onClicked: root.fixRequested(checkRow.row.fix)
      }
      Button {
        visible: checkRow.row.ok !== true && !checkRow.optional
        Layout.alignment: Qt.AlignVCenter
        text: checkRow.row.ignored === true ? "Undo" : "Ignore"
        tooltipText: checkRow.row.ignored === true ? "Light the gear's dot again while it fails" : "Leave it as it is; the gear's dot stops showing it"
        foreground: root.foreground
        fontFamily: root.fontFamily
        fontSize: Style.font.bodySmall
        onClicked: root.ignoreRequested(checkRow.row.key, checkRow.row.ignored !== true)
      }
      Button {
        visible: checkRow.failing
        Layout.alignment: Qt.AlignVCenter
        text: "Fix with AI"
        tooltipText: root.aiTip
        foreground: root.foreground
        fontFamily: root.fontFamily
        fontSize: Style.font.bodySmall
        onClicked: root.fixWithAiRequested("check", checkRow.rowIndex)
      }
    }
  }

  // A device's own: nickname, icon (with its picker), place in the bar, and
  // whether it has a tab.
  component IdentityRow: Column {
    id: idRow
    property var row: ({})
    property int rowIndex: -1
    spacing: Style.space(4)

    CursorSurface {
      width: parent.width
      hasCursor: false
      CursorStop { here: root.cursorIndex === idRow.rowIndex; glide: root.cursorGlide }
      foreground: root.foreground
      implicitHeight: idContent.implicitHeight + Style.space(12)

      MouseArea {
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onEntered: root.hovered(idRow.rowIndex)
        onClicked: root.activated(idRow.rowIndex)
      }

      RowLayout {
        id: idContent
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        anchors.leftMargin: Style.space(10)
        anchors.rightMargin: Style.space(10)
        spacing: Style.space(10)

        ColumnLayout {
          Layout.fillWidth: true
          spacing: Style.space(1)
          Text {
            textFormat: Text.PlainText
            Layout.fillWidth: true
            text: idRow.row.label || ""
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
            elide: Text.ElideRight
          }
          Text {
            textFormat: Text.PlainText
            Layout.fillWidth: true
            text: idRow.row.hint || ""
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            wrapMode: Text.WordWrap
          }
        }

        // Nickname: typed here; Enter keeps it, Esc leaves it as it was.
        // Blank goes back to the name KDE Connect reports.
        PanelField {
          id: nick
          visible: idRow.row.kind === "nickname"
          Layout.preferredWidth: Style.space(150)
          Layout.alignment: Qt.AlignVCenter
          text: idRow.row.value || ""
          placeholderText: root.deviceName
          foreground: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
          Component.onCompleted: if (idRow.row.kind === "nickname") root.nicknameField = nick
          onActiveFocusChanged: root.nicknameFocus(activeFocus)
          onAccepted: { root.nicknameSet(text); root.nicknameFocus(false) }
          // Esc puts the saved nickname back and leaves.
          escapeStep: "revert"
          savedText: idRow.row.value || ""
          onSteppedOut: root.nicknameFocus(false)
        }

        Text {
          visible: idRow.row.kind === "icon"
          text: idRow.row.glyph || ""
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.display
          Layout.alignment: Qt.AlignVCenter
        }

        Row {
          visible: idRow.row.kind === "barPlace"
          spacing: Style.space(4)
          Layout.alignment: Qt.AlignVCenter
          Repeater {
            model: ["always", "attention", "never"]
            Button {
              required property var modelData
              text: Model.BAR_PLACE_LABELS[modelData]
              selected: idRow.row.value === modelData
              bordered: true
              foreground: root.foreground
              fontFamily: root.fontFamily
              fontSize: Style.font.bodySmall
              onClicked: root.barPlaceSet(modelData)
            }
          }
        }

        ToggleSwitch {
          visible: idRow.row.kind === "showInPanel"
          Layout.alignment: Qt.AlignVCenter
          checked: idRow.row.on === true
          cursorRing: false
          foreground: root.foreground
          onHovered: function(on) { if (on) root.hovered(idRow.rowIndex) }
          onToggled: root.activated(idRow.rowIndex)
        }
      }
    }

    // The icon picker, under the Icon row while it is open.
    Flow {
      visible: idRow.row.kind === "icon" && root.iconPicking
      width: parent.width
      leftPadding: Style.space(10)
      spacing: Style.space(4)
      Button {
        text: "Its kind"
        selected: (idRow.row.value || "") === ""
        bordered: true
        foreground: root.foreground
        fontFamily: root.fontFamily
        fontSize: Style.font.bodySmall
        onClicked: root.iconSet("")
      }
      Repeater {
        model: Model.ICON_CHOICES
        Button {
          required property var modelData
          iconText: String.fromCodePoint(parseInt(modelData.code, 16))
          tooltipText: modelData.label
          selected: idRow.row.value === modelData.code
          bordered: true
          foreground: root.foreground
          fontFamily: root.fontFamily
          onClicked: root.iconSet(modelData.code)
        }
      }
    }
  }

  component LayoutRow: CursorSurface {
    id: layoutRow
    property var row: ({})
    property int rowIndex: -1

    hasCursor: false
    CursorStop { here: root.cursorIndex === rowIndex; glide: root.cursorGlide }
    foreground: root.foreground
    implicitHeight: layoutContent.implicitHeight + Style.space(12)
    readonly property int place: layoutRow.row.kind === "layout" ? (layoutRow.row.pos || 0) : -1
    readonly property bool moving: place >= 0 && layoutOrder.from === place
    onHeightChanged: if (place >= 0) layoutOrder.itemSize = height
    transform: ReorderShift { order: layoutOrder; index: layoutRow.place }
    z: moving ? 10 : 0
    color: moving ? Qt.tint(root.panelBackground, fill) : (hasCursor ? fill : (current ? currentFill : "transparent"))

    MouseArea {
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onEntered: root.hovered(layoutRow.rowIndex)
      onClicked: root.activated(layoutRow.rowIndex)
    }

    RowLayout {
      id: layoutContent
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      anchors.leftMargin: Style.space(10)
      anchors.rightMargin: Style.space(10)
      spacing: Style.space(10)

      ReorderGrip {
        visible: layoutRow.place >= 0
        order: layoutOrder
        index: layoutRow.place
        item: layoutRow
        foreground: root.foreground
        fontFamily: root.fontFamily
      }

      ColumnLayout {
        Layout.fillWidth: true
        spacing: Style.space(1)

        Text {
          textFormat: Text.PlainText
          Layout.fillWidth: true
          text: layoutRow.row.label || ""
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
          elide: Text.ElideRight
        }
        Text {
          textFormat: Text.PlainText
          Layout.fillWidth: true
          text: layoutRow.row.hint || ""
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          elide: Text.ElideRight
        }
      }

      ToggleSwitch {
        Layout.alignment: Qt.AlignVCenter
        checked: layoutRow.row.on === true
        cursorRing: false
        foreground: root.foreground
        onHovered: function(on) { if (on) root.hovered(layoutRow.rowIndex) }
        onToggled: root.activated(layoutRow.rowIndex)
      }
    }
  }

  component ShortcutRow: CursorSurface {
    id: shortcutRow
    property var row: ({})
    property int rowIndex: -1

    hasCursor: false
    CursorStop { here: root.cursorIndex === rowIndex; glide: root.cursorGlide }
    foreground: root.foreground
    opacity: shortcutRow.row.kind !== "shortcut" || root.shortcutsShown ? 1.0 : 0.55
    implicitHeight: shortcutContent.implicitHeight + Style.space(10)
    readonly property var order: root.orderFor(shortcutRow.row.kind)
    readonly property int place: shortcutRow.row.on === true ? (shortcutRow.row.pos || 0) : -1
    readonly property bool moving: place >= 0 && !!order && order.from === place
    onHeightChanged: if (place >= 0 && order) order.itemSize = height
    transform: ReorderShift { order: shortcutRow.order; index: shortcutRow.place }
    z: moving ? 10 : 0
    color: moving ? Qt.tint(root.panelBackground, fill) : (hasCursor ? fill : (current ? currentFill : "transparent"))

    MouseArea {
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onEntered: root.hovered(shortcutRow.rowIndex)
      onClicked: root.activated(shortcutRow.rowIndex)
    }

    RowLayout {
      id: shortcutContent
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      anchors.leftMargin: Style.space(10)
      anchors.rightMargin: Style.space(6)
      spacing: Style.space(10)

      // Only chosen ones have a place to move in; the grip keeps its room
      // either way, so the rows line up.
      ReorderGrip {
        opacity: shortcutRow.place >= 0 ? 1 : 0
        order: shortcutRow.order
        index: shortcutRow.place
        item: shortcutRow
        foreground: root.foreground
        fontFamily: root.fontFamily
      }

      Text {
        text: shortcutRow.row.on ? Model.GLYPH.checked : Model.GLYPH.unchecked
        color: shortcutRow.row.on ? root.foreground : root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.icon
        Layout.alignment: Qt.AlignVCenter
      }

      Text {
        text: shortcutRow.row.glyph || ""
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.icon
        Layout.preferredWidth: Style.space(18)
        horizontalAlignment: Text.AlignHCenter
        Layout.alignment: Qt.AlignVCenter
      }

      ColumnLayout {
        Layout.fillWidth: true
        spacing: Style.space(1)

        Text {
          textFormat: Text.PlainText
          Layout.fillWidth: true
          text: shortcutRow.row.label || ""
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
          elide: Text.ElideRight
        }
        Text {
          textFormat: Text.PlainText
          Layout.fillWidth: true
          text: shortcutRow.row.available === false
            ? "Not offered by this device right now"
            : (shortcutRow.row.hint || "")
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          elide: Text.ElideRight
        }
      }

    }
  }
}
