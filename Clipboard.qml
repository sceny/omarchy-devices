pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// The only door between the panel and the system clipboard (docs/architecture/
// 001): the shell is never a party to a Wayland data transfer. Qt serves a
// selection with a blocking write and reads one on the GUI thread without a
// bound, so a program that never reads, or never finishes writing, would
// freeze the bar. Every crossing is a short-lived wl-copy / wl-paste process
// here, bounded in bytes and time; nothing else in the plugin names either
// tool, reads `Quickshell.clipboardText`, or lets a text item copy, cut or
// paste by itself. A file goes out through the bridge's copy-file (Service.qml),
// out of the shell too.
//
// A failure never blocks: a read that is late or fails answers "", a copy
// asked while one runs is dropped, not queued.
Singleton {
  id: clipboard

  // Past the read's own deadline (2 s, then 1 s more): the answer comes anyway.
  readonly property int watchdogMs: 4500

  property var _readDone: null
  property var _copyDone: null

  // `text` goes to wl-copy's stdin, never to its command line. Answers whether
  // the copy started; `done` is called when it ended.
  function copyText(text, done) {
    return _copy(false, text, done)
  }

  // The primary selection (middle-click paste). No caller today.
  function copyPrimary(text, done) {
    return _copy(true, text, done)
  }

  // The only read: `cb(text)` with what arrived in time, else `cb("")`.
  // Answers whether the read started; one runs at a time.
  function readInto(cb) {
    if (_read.running) return false
    _readDone = cb
    _read.running = true
    readWatchdog.restart()
    return true
  }

  function _copy(primary, text, done) {
    if (_copier.running) return false
    _copier.text = String(text)
    _copier.command = primary ? ["wl-copy", "--primary"] : ["wl-copy"]
    _copyDone = done || null
    _copier.running = true
    copyWatchdog.restart()
    return true
  }

  function _call(fn, arg) {
    if (typeof fn !== "function") return
    try { fn(arg) } catch (e) { console.warn("Clipboard: a callback failed:", e) }
  }

  function _readEnded(text) {
    readWatchdog.stop()
    var cb = _readDone
    _readDone = null
    _call(cb, text)
  }

  function _copyEnded() {
    copyWatchdog.stop()
    var cb = _copyDone
    _copyDone = null
    _call(cb)
  }

  Process {
    id: _copier
    property string text: ""
    stdinEnabled: true
    onStarted: { write(text); text = ""; stdinEnabled = false }
    onExited: { stdinEnabled = true; clipboard._copyEnded() }
  }

  // wl-paste, stopped after 2 s (and 1 s more) and cut at 128 KiB, its text
  // cut to whole UTF-8 characters, and printed only when the read ended in
  // time (status 0, or 141: wl-paste stopped by the cut). A slow or failed
  // read prints nothing.
  Process {
    id: _read
    command: ["bash", "-c", "exec 2>/dev/null; set -o pipefail; buf=$(timeout -k 1 2 wl-paste --no-newline --type text | head -c 131072); case $? in 0|141) printf %s \"$buf\" | iconv -f UTF-8 -t UTF-8 -c;; esac"]
    stdout: StdioCollector {
      onStreamFinished: clipboard._readEnded(text)
    }
  }

  Timer {
    id: readWatchdog
    interval: clipboard.watchdogMs
    onTriggered: { _read.running = false; clipboard._readEnded("") }
  }
  Timer {
    id: copyWatchdog
    interval: clipboard.watchdogMs
    onTriggered: { _copier.running = false }
  }
}
