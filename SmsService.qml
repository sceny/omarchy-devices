import QtQuick
import Quickshell
import Quickshell.Io
import "Model.js" as Model

// Text messages for one phone: the thread list and the open conversation.
//
// Runs `kdeconnect-bridge sms <device>` once the messages view is first used and
// keeps it while the phone is reachable. Commands go to its stdin, events
// come back one JSON line each (see the bridge for the protocol).
//
// Both lists are ListModels, not arrays: a new message moves one thread row
// and adds one bubble, where replacing an array would reset the views and
// throw away the scroll position.
Item {
  id: sms

  property string bridge: ""
  property string deviceId: ""
  property bool reachable: false

  // Started on first use of the messages view, then kept.
  property bool wanted: false
  // A demo device (made-up id) has no messages to read.
  readonly property bool active: wanted && reachable && deviceId !== "" && deviceId.indexOf("demo") !== 0 && bridge !== ""

  property bool ready: false
  property int contactCount: 0
  property var contacts: []          // [{name, number}] from the phone's synced vCards
  property string lastError: ""

  readonly property alias threads: threadModel
  readonly property alias messages: messageModel

  // The open conversation.
  property var openThreadId: -1
  property bool loading: false
  property bool hasMore: false
  property int loadedCount: 0
  readonly property int pageSize: 30

  // What was read here: thread id -> date of the newest message seen on this
  // computer. The phone's own read state cannot be changed over KDE Connect,
  // so a thread is unread when the phone says so AND it has a message newer
  // than what was seen here. Kept on disk, so a restart does not bring back
  // marks already dealt with.
  property var seen: ({})
  // Set by the panel while the messages view is on screen: a message arriving
  // in the open thread then counts as seen.
  property bool viewing: false

  readonly property string cacheBase: (Quickshell.env("XDG_CACHE_HOME") || (Quickshell.env("HOME") + "/.cache")) + "/sceny.devices"

  FileView {
    id: seenFile
    path: sms.deviceId !== "" ? sms.cacheBase + "/sms-seen-" + sms.deviceId + ".json" : ""
    watchChanges: false
    printErrors: false
    atomicWrites: true
    onLoaded: {
      try { sms.seen = JSON.parse(text()) || ({}) } catch (e) { sms.seen = ({}) }
      sms.recomputeUnread()
    }
  }

  function saveSeen() {
    if (seenFile.path !== "") seenFile.setText(JSON.stringify(seen) + "\n")
  }

  // Demo conversations are made up: what is opened in demo mode is kept
  // apart, starts empty on every showDemo(), and never reaches the file.
  property var demoSeen: ({})
  function seenMap() { return demo ? demoSeen : seen }

  function isUnread(tid, date, readOnPhone, sentLast) {
    return !readOnPhone && !sentLast && date > (seenMap()[tid] || 0)
  }

  function recomputeUnread() {
    for (var i = 0; i < threadModel.count; i++) {
      var r = threadModel.get(i)
      var u = isUnread(r.tid, r.date, r.readOnPhone, r.sentLast)
      if (r.unread !== u) threadModel.setProperty(i, "unread", u)
    }
    modelRevision++
  }

  // ---- search and the unread filter ----
  property string query: ""
  // Only threads with something unread (set by the panel, remembered there).
  // The open thread stays listed after it counts as read, until another opens.
  property bool unreadOnly: false
  onUnreadOnlyChanged: applyQuery()
  ListModel { id: filteredModel }
  readonly property bool filtering: query.trim() !== "" || unreadOnly
  readonly property var shownThreads: filtering ? filteredModel : threadModel

  function setQuery(q) {
    query = q
    applyQuery()
  }

  function applyQuery() {
    filteredModel.clear()
    var terms = query.trim().toLowerCase().split(/\s+/).filter(function(t) { return t !== "" })
    if (terms.length === 0 && !unreadOnly) return
    for (var i = 0; i < threadModel.count && filteredModel.count < 200; i++) {
      var r = threadModel.get(i)
      if (unreadOnly && !r.unread && r.tid !== openThreadId) continue
      var hit = true
      for (var t = 0; t < terms.length && hit; t++) hit = r.search.indexOf(terms[t]) >= 0
      if (hit) filteredModel.append({
        tid: r.tid, title: r.title, initial: r.initial, addresses: r.addresses, addressKeys: r.addressKeys,
        snippet: r.snippet, date: r.date, unread: r.unread, group: r.group, search: r.search,
        readOnPhone: r.readOnPhone, sentLast: r.sentLast
      })
    }
  }

  // Keep a filtered list current as threads change, without redoing it on
  // every single signal.
  Timer { id: requery; interval: 300; onTriggered: if (sms.filtering) sms.applyQuery() }
  onModelRevisionChanged: if (filtering) requery.restart()

  signal sentOk()
  // A new message's thread showed up (sendNew): the view opens it.
  signal newThreadReady(var tid)

  // Recipients of the last sendNew, as digit keys, until their thread appears.
  property var pendingNewKeys: []

  // Attachments asked for by the user, by file id; opened when they land.
  property var pendingFiles: ({})

  ListModel { id: threadModel }
  ListModel { id: messageModel }

  function start() { wanted = true }

  // The viewed device changed (a tab, a chip): this reader follows it from a
  // clean slate, so one device's conversations never show under another.
  // The seen marks follow too (their file is per device).
  onDeviceIdChanged: {
    if (demo) return
    closeThread()
    threadModel.clear()
    seen = ({})
    ready = false
    modelRevision++
    if (proc.running) {
      proc.running = false
      Qt.callLater(function() { if (sms.active && !proc.running) proc.running = true })
    }
  }

  // Demo: made-up conversations (Model.demoThreads) in place of the real
  // ones, for screenshots. Bridge events are ignored meanwhile and nothing
  // can be sent; showLive() asks the bridge for the real list again.
  property bool demo: false

  // Demo data arrives after a phone's usual delay, so the skeletons the
  // view shows meanwhile can be looked at too.
  readonly property int demoDelay: 900

  function showDemo() {
    demo = true
    demoSeen = ({})
    threadModel.clear()
    ready = false
    modelRevision++
    openThreadId = -1
    messageModel.clear()
    demoThreadsTimer.restart()
  }

  Timer {
    id: demoThreadsTimer
    interval: sms.demoDelay
    onTriggered: {
      if (!sms.demo) return
      var threads = Model.demoThreads()
      for (var i = 0; i < threads.length; i++) threadModel.append(threadRow(threads[i]))
      sms.ready = true
      sms.modelRevision++
    }
  }

  Timer {
    id: demoOpenTimer
    interval: sms.demoDelay
    onTriggered: {
      if (!sms.demo || sms.openThreadId < 0) return
      var convo = sms.openThreadId === 9001 ? Model.demoConversation(undefined, sms.cacheBase + "/demo/picture.jpg") : []
      for (var d = convo.length - 1; d >= 0; d--) messageModel.append(sms.messageRow(convo[d]))
      sms.loadedCount = messageModel.count
      sms.loading = false
      sms.refreshDays()
    }
  }

  function showLive() {
    if (!demo) return
    demo = false
    demoThreadsTimer.stop()
    demoOpenTimer.stop()
    closeThread()
    threadModel.clear()
    ready = false
    modelRevision++
    send({ cmd: "refresh" })
  }

  function send(obj) {
    if (!proc.running) return false
    proc.write(JSON.stringify(obj) + "\n")
    return true
  }

  // ---- threads ----

  function threadRow(t) {
    var title = Model.threadTitle(t.names, t.addresses)
    var keys = []
    for (var i = 0; i < t.addresses.length; i++) {
      var d = String(t.addresses[i]).replace(/\D/g, "")
      keys.push(d.length >= 10 ? d.slice(-10) : d)
    }
    return {
      tid: t.id,
      title: title,
      initial: Model.avatarInitial(title),
      addresses: t.addresses.join(", "),
      addressKeys: keys.join(" "),
      snippet: (t.sent ? "You: " : "") + (t.snippet || (t.attachments > 0 ? "Picture" : "")),
      date: t.date,
      unread: isUnread(t.id, t.date, t.read === true, t.sent === true),
      readOnPhone: t.read === true,
      sentLast: t.sent === true,
      group: t.group === true,
      search: (title + " " + t.addresses.join(" ") + " " + (t.snippet || "")).toLowerCase()
    }
  }

  function indexOfThread(tid) {
    for (var i = 0; i < threadModel.count; i++) if (threadModel.get(i).tid === tid) return i
    return -1
  }

  function upsertThread(t) {
    var row = threadRow(t)
    var at = indexOfThread(row.tid)
    if (at >= 0 && threadModel.get(at).date > row.date) return
    // Keep newest first: find where this date belongs.
    var to = 0
    while (to < threadModel.count && threadModel.get(to).date > row.date && threadModel.get(to).tid !== row.tid) to++
    if (at < 0) threadModel.insert(to, row)
    else {
      if (to > at) to = at
      if (at !== to) threadModel.move(at, to, 1)
      threadModel.set(to, row)
    }
  }

  function markSeen(tid) {
    var at = indexOfThread(tid)
    var date = at >= 0 ? threadModel.get(at).date : Date.now()
    if ((seenMap()[tid] || 0) >= date) return
    var next = Object.assign({}, seenMap())
    next[tid] = date
    if (demo) demoSeen = next
    else { seen = next; saveSeen() }
    if (at >= 0) threadModel.setProperty(at, "unread", false)
    modelRevision++
  }

  // ListModel.get() is not tracked by bindings; modelRevision is bumped on
  // every change so this recounts.
  readonly property int unreadCount: {
    var rev = modelRevision + threadModel.count
    var n = 0
    for (var i = 0; i < threadModel.count; i++) if (threadModel.get(i).unread) n++
    return n
  }
  property int modelRevision: 0

  // ---- the open conversation ----

  function messageRow(m) {
    var names = m.addresses || []
    return {
      uid: m.uid,
      body: m.body || "",
      date: m.date,
      time: Model.clockTime(m.date),
      sent: m.sent === true,
      pending: m.type === 4 || m.type === 6,
      failed: m.type === 5,
      optimistic: false,
      sender: !m.sent && names.length > 0 ? Model.formatNumber(names[0]) : "",
      attachments: JSON.stringify(m.attachments || []),
      showDay: false,
      day: Model.dayLabel(m.date)
    }
  }

  function openThread(tid) {
    if (demo) {
      if (tid === openThreadId && (messageModel.count > 0 || loading)) return
      openThreadId = tid
      messageModel.clear()
      hasMore = false
      loading = true
      demoOpenTimer.restart()
      return
    }
    start()
    if (tid === openThreadId && (messageModel.count > 0 || loading)) return
    openThreadId = tid
    messageModel.clear()
    loadedCount = 0
    hasMore = true
    // The page still on its way is the previous conversation's; its answer
    // is dropped (another thread), so this one is asked for now.
    loading = false
    markSeen(tid)
    loadMore()
  }

  function closeThread() {
    openThreadId = -1
    messageModel.clear()
    loading = false
  }

  function loadMore() {
    if (openThreadId < 0 || loading || !hasMore) return
    if (send({ cmd: "load", thread: openThreadId, start: loadedCount, count: pageSize })) loading = true
  }

  function indexOfMessage(uid) {
    for (var i = 0; i < messageModel.count; i++) if (messageModel.get(i).uid === uid) return i
    return -1
  }

  // A day header sits above the oldest message of each day. The list is
  // newest first, so that is where the next (older) row has another day, or
  // the last row once nothing older is left to load.
  function refreshDays() {
    for (var i = 0; i < messageModel.count; i++) {
      var here = messageModel.get(i).date
      var show = i === messageModel.count - 1 ? !hasMore : !Model.sameDay(here, messageModel.get(i + 1).date)
      if (messageModel.get(i).showDay !== show) messageModel.setProperty(i, "showDay", show)
    }
  }

  function upsertMessage(m) {
    if (m.thread !== openThreadId) return
    // A real message replaces the bubble put up for it on send.
    if (m.sent) {
      for (var o = 0; o < messageModel.count; o++) {
        var row = messageModel.get(o)
        if (row.optimistic && row.body === (m.body || "")) { messageModel.remove(o); break }
      }
    }
    var at = indexOfMessage(m.uid)
    if (at >= 0) { messageModel.set(at, messageRow(m)); return }
    var to = 0
    while (to < messageModel.count && messageModel.get(to).date > m.date) to++
    messageModel.insert(to, messageRow(m))
    loadedCount += 1
    refreshDays()
  }

  function reply(text) {
    var body = String(text || "").trim()
    if (demo || openThreadId < 0 || body === "") return false
    if (!send({ cmd: "reply", thread: openThreadId, text: body })) return false
    // Show it at once; the phone's own copy replaces it when it arrives.
    messageModel.insert(0, {
      uid: -Date.now(), body: body, date: Date.now(), time: Model.clockTime(Date.now()),
      sent: true, pending: true, failed: false, optimistic: true, sender: "",
      attachments: "[]", showDay: false, day: Model.dayLabel(Date.now())
    })
    refreshDays()
    return true
  }

  function sendNew(addresses, text) {
    if (demo) return false
    var body = String(text || "").trim()
    if (body === "" || !addresses || addresses.length === 0) return false
    if (!send({ cmd: "send", addresses: addresses, text: body })) return false
    var keys = []
    for (var i = 0; i < addresses.length; i++) keys.push(digitKey(addresses[i]))
    pendingNewKeys = keys.sort()
    return true
  }

  function digitKey(address) {
    var d = String(address || "").replace(/\D/g, "")
    return d.length >= 10 ? d.slice(-10) : d
  }

  // The one-to-one thread with this number, or -1.
  function threadForAddress(address) {
    var key = digitKey(address)
    if (!key) return -1
    for (var i = 0; i < threadModel.count; i++) {
      var t = threadModel.get(i)
      if (!t.group && t.addressKeys === key) return t.tid
    }
    return -1
  }

  // Who a new message can go to, for the "To" field: synced contacts and the
  // numbers of existing one-to-one threads, matched on name or digits.
  function candidates(query, limit) {
    var q = String(query || "").trim().toLowerCase()
    var qd = q.replace(/\D/g, "")
    var out = []
    var seenKeys = {}
    function consider(name, number, tid) {
      var key = digitKey(number)
      if (!key || seenKeys[key]) return
      var hit = q === "" || (name && name.toLowerCase().indexOf(q) >= 0) || (qd.length >= 2 && String(number).replace(/\D/g, "").indexOf(qd) >= 0)
      if (!hit) return
      seenKeys[key] = true
      out.push({ name: name || "", number: number, title: name || Model.formatNumber(number), tid: tid })
    }
    // Demo mode shows made-up people only: the phone's synced contacts are
    // real, so they stay out of it (a screenshot of the demo is public).
    var people = demo ? [] : contacts
    for (var c = 0; c < people.length && out.length < (limit || 8); c++)
      consider(people[c].name, people[c].number, threadForAddress(people[c].number))
    for (var i = 0; i < threadModel.count && out.length < (limit || 8); i++) {
      var t = threadModel.get(i)
      if (!t.group) consider(t.title !== Model.formatNumber(t.addresses) ? t.title : "", t.addresses, t.tid)
    }
    return out
  }

  function fetchAttachment(part, id, mime) {
    // Demo pictures are local files already.
    if (demo) {
      for (var i = 0; i < messageModel.count; i++) {
        var files = JSON.parse(messageModel.get(i).attachments)
        for (var j = 0; j < files.length; j++)
          if (files[j].id === id && files[j].thumb) { Quickshell.execDetached([sms.bridge, "open-file", files[j].thumb]); return }
      }
      return
    }
    var next = Object.assign({}, pendingFiles)
    next[id] = true
    pendingFiles = next
    send({ cmd: "attachment", part: part, id: id, mime: mime || "" })
  }

  function isFetching(id) { return pendingFiles[id] === true }

  signal attachmentReady(string path)

  function handle(ev) {
    if (demo) return
    if (ev.ev === "threads") {
      threadModel.clear()
      for (var i = 0; i < ev.threads.length; i++) threadModel.append(threadRow(ev.threads[i]))
      ready = true
      modelRevision++
    } else if (ev.ev === "thread") {
      upsertThread(ev.thread)
      if (viewing && ev.thread.id === openThreadId) markSeen(ev.thread.id)
      modelRevision++
      if (pendingNewKeys.length > 0) {
        var keys = []
        for (var k = 0; k < ev.thread.addresses.length; k++) keys.push(digitKey(ev.thread.addresses[k]))
        if (JSON.stringify(keys.sort()) === JSON.stringify(pendingNewKeys)) {
          pendingNewKeys = []
          newThreadReady(ev.thread.id)
        }
      }
    } else if (ev.ev === "removed") {
      var at = indexOfThread(ev.thread)
      if (at >= 0) threadModel.remove(at)
      if (ev.thread === openThreadId) closeThread()
      modelRevision++
    } else if (ev.ev === "messages") {
      if (ev.thread !== openThreadId || ev.start !== loadedCount) return
      for (var j = 0; j < ev.messages.length; j++) {
        var m = ev.messages[j]
        if (indexOfMessage(m.uid) < 0) messageModel.append(messageRow(m))
      }
      loadedCount += ev.messages.length
      hasMore = ev.hasMore === true && ev.messages.length > 0
      loading = false
      refreshDays()
    } else if (ev.ev === "message") {
      upsertMessage(ev.message)
    } else if (ev.ev === "contacts") {
      contactCount = ev.count
      contacts = ev.contacts || []
    } else if (ev.ev === "attachment") {
      // Open what the user asked for (a picture: the bridge's copy made in
      // the sandbox), as Files would: GIO's default app for its type
      // (xdg-open knows none for HEIC, and opened nothing), through uwsm-app.
      var wanted = pendingFiles[ev.name] === true || Object.keys(pendingFiles).length > 0
      if (wanted) {
        pendingFiles = ({})
        Quickshell.execDetached([sms.bridge, "open-file", ev.path])
      }
      attachmentReady(ev.path)
    } else if (ev.ev === "sent") {
      sentOk()
    } else if (ev.ev === "error") {
      lastError = ev.message || "Something went wrong"
      if (ev.cmd === "load") loading = false
      if (ev.cmd === "attachment") pendingFiles = ({})
      errorClear.restart()
    }
  }

  Timer { id: errorClear; interval: 6000; onTriggered: sms.lastError = "" }

  Process {
    id: proc
    command: [sms.bridge, "sms", sms.deviceId]
    running: sms.active
    stdinEnabled: true

    stdout: SplitParser {
      onRead: function(line) {
        var ev = null
        try { ev = JSON.parse(line) } catch (e) {
          // Clears like any error; the length only (the line may hold message text).
          console.warn("sceny.devices sms: an unreadable line, " + String(line).length + " characters")
          sms.lastError = "Unreadable update from kdeconnect-bridge"
          errorClear.restart()
          return
        }
        // A fault here is the panel's, not the bridge's: logged, with the
        // event's type only.
        try { sms.handle(ev) } catch (e2) { console.warn("sceny.devices sms: " + e2 + " while handling " + ev.ev) }
      }
    }

    onRunningChanged: {
      if (!running) {
        sms.ready = false
        sms.loading = false
        if (sms.active) restartSms.restart()
      } else if (sms.openThreadId >= 0) {
        // Came back (phone reconnected, bridge restarted): reload the page.
        var tid = sms.openThreadId
        sms.openThreadId = -1
        Qt.callLater(function() { sms.openThread(tid) })
      }
    }
  }

  Timer {
    id: restartSms
    interval: 3000
    onTriggered: if (sms.active && !proc.running) proc.running = true
  }
  // Started and stopped here, not by a binding alone: the restart above
  // assigns `running`, which drops `running: sms.active`, and the reader
  // then stayed stopped after messages went inactive and back (a demo, the
  // phone away). Another device restarts it (onDeviceIdChanged, above).
  onActiveChanged: proc.running = sms.active
}
