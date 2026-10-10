import QtQuick
import Quickshell
import Quickshell.Io
import "Model.js" as Model

// The contacts of one device: the cards KDE Connect syncs from it, as the
// contacts page draws them.
//
// `kdeconnect-bridge contacts <device>` reads the vCards already on disk, so
// it answers while the device is away too. Only the user's own Refresh adds
// `--sync`, which asks the device for its cards again: the device sends one
// packet per card, so a panel opening never does it.
//
// Nothing is kept here and nothing is edited: the device is the truth, and a
// change is made on the device or in Omarchy's own contacts app.
//
// The list is a ListModel, not an array: a search re-fills it without
// resetting the view, and replacing an array would throw away the scroll
// position.
Item {
  id: contacts

  property string bridge: ""
  property string deviceId: ""
  property bool reachable: false

  // Started on first use of the contacts page, then kept.
  property bool wanted: false
  // A demo device (made-up id) has no cards to read.
  readonly property bool active: wanted && deviceId !== "" && deviceId.indexOf("demo") !== 0 && bridge !== ""

  property bool ready: false
  // What the page has: "ready" with cards, "empty" with none, "away" with
  // none and nothing reaching the device (Model.contactsEmpty words each).
  property string listState: ""
  property string lastError: ""

  // Every card of the device, as the bridge read them (name order). The open
  // card and its details come from these, never from the rows.
  property var cards: []
  // The rows the page draws: the cards the search leaves.
  readonly property alias rows: rowModel

  // Omarchy's own contacts app, { name, url }; null on a computer with none.
  // A demo shows it only when a real read already found it: a made-up device
  // is never read.
  property var app: null
  readonly property bool hasApp: !!(app && app.name)
  readonly property string appName: hasApp ? String(app.name) : ""

  ListModel { id: rowModel }
  ListModel { id: detailModel }

  // ListModel.get() is not tracked by bindings; this is bumped on every
  // change, so a count or a row read in a binding is read again.
  property int revision: 0

  function start() { wanted = true }

  // ---- reading ----

  property bool reading: false
  property bool syncing: false
  property real readAt: 0
  // One read at a time: another asked for meanwhile runs after it, with
  // --sync when either of them wanted it.
  property var again: null

  // A panel opened on the page: the reader starts, and the cards on disk are
  // read again when what is shown is older than Model.CONTACTS_READ_MS.
  // Never a sync.
  function opened() {
    start()
    if (demo || !active || reading) return
    if (ready && Date.now() - readAt < Model.CONTACTS_READ_MS) return
    read(false)
  }

  // The user's own Refresh: the device is asked for its cards again while
  // something reaches it, else the cards on disk are read again.
  function refresh() {
    if (demo) return
    start()
    read(reachable)
  }

  function read(sync) {
    if (!active) return
    if (proc.running) {
      again = { sync: sync === true || !!(again && again.sync) }
      return
    }
    again = null
    proc.device = deviceId
    proc.command = [bridge, "contacts", deviceId].concat(sync === true ? ["--sync"] : [])
    syncing = sync === true
    reading = true
    proc.running = true
  }

  function apply(data) {
    cards = data.contacts || []
    app = data.app || null
    ready = true
    readAt = Date.now()
    listState = cards.length > 0 ? "ready" : (reachable ? "empty" : "away")
    applyQuery()
    // The card the page has open is the same person, read again.
    if (openId !== "") openContact(openId)
  }

  // Away with nothing read is not the same as away with cards on disk.
  onReachableChanged: if (ready && cards.length === 0) listState = reachable ? "empty" : "away"

  // The viewed device changed (a tab, a chip): this reader follows it from a
  // clean slate, so one device's contacts never show under another.
  onDeviceIdChanged: {
    if (demo) return
    // `app` is this computer's, not the device's: it stays.
    cards = []
    ready = false
    listState = ""
    readAt = 0
    again = null
    closeContact()
    applyQuery()
    // The read on its way is the previous device's: stopped, and this one
    // asked for once it has gone.
    if (proc.running) { proc.running = false; again = { sync: false } }
    else read(false)
  }

  onActiveChanged: if (active && !ready) read(false)

  // ---- search: the rows only, never another read ----

  property string query: ""
  readonly property bool filtering: query.trim() !== ""

  function setQuery(q) {
    query = q
    applyQuery()
  }

  function applyQuery() {
    rowModel.clear()
    var list = Model.contactRows(cards, query)
    for (var i = 0; i < list.length; i++) rowModel.append(list[i])
    revision++
  }

  // ---- the open card ----

  property string openId: ""
  property var openCard: null
  readonly property alias details: detailModel
  readonly property string openTitle: openCard ? Model.contactTitle(openCard) : ""
  readonly property string openPhoto: openCard ? String(openCard.photo || "") : ""
  readonly property string openInitial: openCard ? Model.avatarInitial(String(openCard.name || "").trim()) : ""

  function openContact(id) {
    var card = Model.contactById(cards, id)
    openId = card ? String(id) : ""
    openCard = card
    detailModel.clear()
    if (!card) return
    var rows = Model.contactDetails(card)
    for (var i = 0; i < rows.length; i++) {
      var r = rows[i]
      // `actions` as one string: a ListModel turns an array into a nested
      // model of its own, which a row cannot ask `indexOf`.
      detailModel.append({ kind: r.kind, glyph: r.glyph, label: r.label, value: r.value,
                           raw: r.raw, actions: (r.actions || []).join(" ") })
    }
    revision++
  }

  function closeContact() {
    openId = ""
    openCard = null
    detailModel.clear()
    revision++
  }

  // ---- demo: made-up people, for screenshots and checks ----
  // A real device's contacts are personal, so a picture is taken of these.

  property bool demo: false
  // Demo cards arrive after a device's usual delay, so the skeletons the
  // page shows meanwhile can be looked at too.
  readonly property int demoDelay: 900

  function showDemo() {
    demo = true
    cards = []
    ready = false
    listState = ""
    closeContact()
    applyQuery()
    demoTimer.restart()
  }

  Timer {
    id: demoTimer
    interval: contacts.demoDelay
    onTriggered: {
      if (!contacts.demo) return
      contacts.cards = Model.demoContacts()
      contacts.ready = true
      contacts.readAt = Date.now()
      contacts.listState = "ready"
      contacts.applyQuery()
    }
  }

  function showLive() {
    if (!demo) return
    demo = false
    demoTimer.stop()
    cards = []
    ready = false
    listState = ""
    readAt = 0
    closeContact()
    applyQuery()
    read(false)
  }

  // Omarchy's own contacts app, opened exactly as Omarchy opens a web app
  // (the bridge's `contacts-app`). It says so itself when there is none.
  function openApp() {
    if (bridge === "") return false
    Quickshell.execDetached([bridge, "contacts-app"])
    return true
  }

  // A contact's email, address or website in its app (`kind`: mail, map,
  // web), through the bridge, which refuses what is not a link.
  function openDetail(kind, value) {
    if (bridge === "") return false
    Quickshell.execDetached([bridge, "contact-open", kind, String(value)])
    return true
  }

  Timer { id: errorClear; interval: 6000; onTriggered: contacts.lastError = "" }

  Process {
    id: proc
    property string device: ""

    stdout: StdioCollector {
      onStreamFinished: {
        // The answer of a read started for another device is dropped.
        if (proc.device !== contacts.deviceId) return
        var data = null
        try { data = JSON.parse(text) } catch (e) {
          console.warn("sceny.devices contacts: an unreadable answer, " + String(text).length + " characters")
          contacts.lastError = "Unreadable answer from kdeconnect-bridge"
          errorClear.restart()
          return
        }
        if (!data || !data.contacts) return
        // A fault here is the panel's, not the bridge's: logged without the
        // cards, which are personal.
        try { contacts.apply(data) } catch (e2) { console.warn("sceny.devices contacts: " + e2 + " while reading the cards") }
      }
    }

    stderr: StdioCollector {
      onStreamFinished: {
        var message = String(text).trim()
        if (message === "") return
        contacts.lastError = message
        errorClear.restart()
      }
    }

    onExited: function(code) {
      contacts.reading = false
      contacts.syncing = false
      if (code !== 0 && contacts.lastError === "") {
        contacts.lastError = "Could not read the contacts"
        errorClear.restart()
      }
      if (contacts.again) {
        var next = contacts.again
        contacts.again = null
        Qt.callLater(function() { contacts.read(next.sync) })
      }
    }
  }
}
