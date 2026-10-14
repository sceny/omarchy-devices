# 001 — The shell is never a party to a Wayland data transfer

Status: accepted · 2026-10-14 · owner of the decision: Mies (architecture) ·
implements: SCE-696 · under: SCE-694 (Devices 0.8.4), SCE-603 (marketplace #10096)

This is the first architecture record in the repository. It governs
`sceny.devices` and any future panel or component the plugin ships, and it is
the rule every clipboard, selection and drag question is decided against from
now on.

## 1. The question

In one sentence: **who holds the Wayland selection, primary selection and
drag payload when the user copies from or pastes into the panel — the shell
process, or a subprocess the shell cannot be frozen by?**

Every clipboard defect filed against this plugin (0.8.1 → 0.8.4, and
marketplace #10096's five rounds) is one instance of the same question
answered the wrong way for one more code path. The owner's instruction is to
stop answering it per-path and answer it once, for every path that exists and
every path a future component could add.

## 2. The decision

**The shell process is never a party to a Wayland data transfer — not a
source, not a target, not a drag-and-drop source or destination — in either
direction. Every crossing of the clipboard boundary goes through a
short-lived `wl-copy` / `wl-paste` subprocess, bounded in bytes and time,
and the QML side never holds, reads or serves a selection itself.**

This is a single invariant with one owning component and one check. It is the
same pattern Omarchy's own shell uses for its clipboard history
(`/usr/share/omarchy/shell/plugins/clipboard/capture.sh` reads through
`wl-paste` subprocesses; omacom/omarchy#8753 names the in-process read as the
fault), and the same boundary KDE's David Edmundson drew when he reviewed the
Qt fix (qtbase 0b3ed8ba40).

### 2.1 Why the process boundary is the fix, not a limit

Qt's QtWayland client serves and reads selections on the **GUI thread**, with
a blocking syscall and no bound, at the installed version (qt6-base 6.11.2):

- **As a source** (the shell owns a selection and another client asks for it):
  `QWaylandDataSource::data_source_send`
  (`qtbase/src/plugins/platforms/wayland/qwaylanddatasource.cpp:45`, 6.11.2)
  ignores `SIGPIPE` and calls a single blocking `write(fd, …)` with no
  timeout. `QWaylandPrimarySelectionSourceV1::…_send`
  (`qwaylandprimaryselectionv1.cpp:119`) is identical. A requester that opens
  the pipe and never reads fills the ~64 KiB pipe buffer; `write` blocks; the
  shell's GUI thread is frozen until the requester relents. This is a
  deliberate hang any local Wayland client can trigger.
- **As a target** (the shell reads a selection):
  `QWaylandMimeData::readData` (`qwaylanddataoffer.cpp:242`) polls with a
  **1 s deadline per `poll()` call inside a `Q_FOREVER` loop** and **no
  aggregate byte or time cap** — a provider that dribbles one byte just under
  every second feeds the loop forever. `QQuickTextInput::canPaste` /
  `q_canPasteChanged` (`qtdeclarative/src/quick/items/qquicktextinput.cpp:2576,3010`)
  call `mimeData()->text()`, forcing that read **on every `QClipboard`
  `dataChanged` signal and whenever the field becomes editable** — no paste
  gesture needed.

The subprocess moves both blocking calls out of the shell. `wl-copy` forks and
serves paste requests from its own throwaway process (it even unlinks its temp
file and keeps only the fd: `wl-clipboard/src/wl-copy.c`); if a hostile reader
freezes it, it freezes a subprocess, not the bar. `wl-paste` reads in its own
process and we cap it with `timeout` and `head -c`; a slow provider costs us a
bounded wait and an empty result, never the GUI thread.

### 2.2 The component and its contract

One QML component owns the boundary. Call it **`Clipboard`** (a singleton
under `qs` Commons, created once). Nothing else in the plugin runs `wl-copy`
or `wl-paste`, reads `Quickshell.clipboardText`, or constructs a `Process`
for a clipboard verb.

```
Clipboard.copyText(text: string) -> void
    // text to the system clipboard. Runs ["wl-copy"] with `text` on stdin,
    // never on argv (private text off the command line — test_argv.py C1).
    // stdinEnabled closed after the write. One in-flight copy at a time.

Clipboard.copyPrimary(text: string) -> void
    // same, ["wl-copy", "--primary"], for a middle-click-paste target we
    // chose to offer (today: none; reserved so a future need has a home).

Clipboard.copyFileData(mime: string, path: string) -> void
    // an image/file as data. Routed through the bridge
    // (`kdeconnect-bridge copy-file`), which already does this out of the
    // shell (bin/kdeconnect-bridge:1222); argv carries the path, never the
    // bytes. Unchanged by this record; named so the inventory is complete.

Clipboard.readInto(cb: function(text: string)) -> void
    // the only clipboard read. Runs the bounded wl-paste script
    // (timeout -k 1 2 wl-paste --no-newline --type text | head -c 131072,
    // then iconv -c), calls cb(text) with what arrived in time, or cb("")
    // on timeout/failure. The caller inserts under its own byte cap.
```

Error cases are explicit and never block: a read that times out or fails
calls back `""`; a copy that cannot start (one already running) is dropped,
not queued; neither raises, neither waits on the GUI thread.

### 2.3 What the QML side may and may not do

A text surface in the panel is a `TextEdit` (never `TextField` / `TextInput`
/ `TextArea`: `QQuickTextInput::canPaste` reads the payload in-process; a
`TextEdit`'s `canPaste` only checks the advertised format list,
`qquicktextcontrol.cpp:1675` `hasText()`). On that `TextEdit`:

- **`selectByMouse: false`.** `selectByMouse` makes Qt call
  `setClipboardSelection()` on mouse move and release
  (`qquicktextcontrol.cpp:520,550,1195`), which makes the **shell** own the
  primary selection — a blocking source. Selection highlight, where offered,
  is driven by the component itself with `edit.select(start, end)` /
  `edit.selectAll()`, which call `setTextCursor` only and touch no clipboard
  (`qquicktextedit.cpp` `select`/`selectAll`).
- **Copy / Cut / Select-All / Paste are intercepted** at `Keys.onPressed`
  (priority `BeforeItem`, as `PanelKeyCatcher` already does) and routed to
  `Clipboard`. Qt's `copy()` / `cut()` / `paste()` are never reached, so Qt
  never calls `setMimeData` / `setClipboardSelection` and the shell never
  becomes a source. Paste reads through `Clipboard.readInto`.
- **Middle-click is swallowed** (a `MouseArea` with
  `acceptedButtons: Qt.MiddleButton` and no handler) so Qt's
  middle-button primary-selection paste (`qquicktextcontrol.cpp:1197`) never
  runs, and **a drop is refused** (`DropArea { onDropped: drop.accepted = false }`).
  PanelField.qml already does both; this record makes them the rule for every
  text surface, including the read-only message bubbles and contact details.
- **No `Drag.dragType: Drag.Automatic`.** `QDrag::exec` enters a nested event
  loop and makes the shell a DnD source through the same blocking
  `data_source_send` (the gallery tile, `Panel.qml:6586`). Dragging a gallery
  file to another window is re-expressed without the shell owning the drag:
  either a copy-to-clipboard affordance (the tile's existing copy button,
  `Clipboard.copyFileData`) or, if drag is kept, the file handed to a drag
  helper process — decided in the implementation issue, not here (§7).

## 3. What this rules out

- **Patch the next path the reviewer names, again.** Rejected: this is the
  behaviour the owner stopped. Five rounds on #10096 each closed exactly the
  path named (TextInput read → focus read → paste read) and left the next
  one. Cost of continuing: one release per path, indefinitely, and a
  marketplace listing frozen the whole time.
- **Wait for Qt.** Rejected on measurement. The source-side fix (0b3ed8ba40,
  a 5 s write cap) shipped in **6.12.0 only, no 6.11 backport**, and the
  installed Qt is 6.11.2. Worse, 6.12.0 does **not** fix the target side: the
  `canPaste`/`q_canPasteChanged` in-process read and the unbounded
  `readData` loop are byte-identical in 6.11.2, 6.12.0 and `dev`
  (verified against the tags). Upgrading Qt would close one of the four paths
  and leave the one the reviewer actually keeps hitting. Cost of waiting: the
  freeze ships to users until Omarchy upgrades Qt *and* Qt fixes the read,
  the second of which is not even on a branch.
- **Keep Qt's clipboard, cap it in QML.** Rejected: the blocking `write` and
  the in-process `text()` read are below the QML surface; QML cannot wrap or
  time them out. The only lever QML has is *not reaching them*.
- **Disable the clipboard globally** (`QT_CONFIG(clipboard)` off, or no
  copy/paste at all). Rejected: copying a message, a contact detail, a photo
  is a real feature the product keeps. The decision keeps the feature and
  moves only the transport.
- **One `wl-copy`/`wl-paste` call per call site** (what 0.8.4 partly does:
  MessagesView and ContactsView each own a `wl-copy` Process). Rejected as
  the end state: it works but it is the per-component sprawl that lets the
  next component forget. One component plus a lint is the same mechanism made
  un-forgettable.

## 4. The migration

No persisted shape changes; nothing in `shell.json` or the cache is read or
written differently, so there is no data migration. The migration is of
**code paths**, and it is a consolidation, not a rewrite:

- `MessagesView.qml` and `ContactsView.qml` already copy through `wl-copy`
  over stdin (good) — they move to `Clipboard.copyText` so the Process lives
  once.
- `PanelField.qml` already reads through bounded `wl-paste` and refuses
  middle-click and drops (good) — its read moves behind `Clipboard.readInto`;
  its `selectByMouse: true` (`PanelField.qml:122`) becomes `false` with
  component-driven selection.
- `MessagesView.qml:1318` (the message bubble, `readOnly` but
  `selectByMouse: true`) and any other `selectByMouse` lose it; selection, if
  offered, is component-driven.
- `Panel.qml:6586` (the gallery tile `Drag.Automatic`) is re-expressed per §7.
- `bin/kdeconnect-bridge copy-file` is unchanged.

Because the reads and the copies were already out-of-process in 0.8.4, the
behavioural delta users see is only in mouse-selection and the gallery drag;
everything else is the same bytes through one door instead of several.

## 5. Consequences and the reversal path

**Easier:** a new component (and the second plugin, `omarchy-paperclipai`,
when it shows text) gets the safe clipboard for free by using `Clipboard`;
there is one place to read when a clipboard question arises; the security
reviewer checks one component, not every text surface; the lint makes a
regression a red build, not a sixth marketplace round.

**Harder:** mouse selection becomes component-driven rather than Qt's
built-in, which is more QML to carry (a selection drag handler). Copy/cut/
paste must be wired per text surface rather than inherited from Qt — but all
text surfaces are already `PanelField` or a controlled `TextEdit`, so the
wiring has one home.

**Cost to undo in three months:** low for the invariant (delete the lint,
let components touch the clipboard again) but you would be undoing the only
thing that stops the freeze, so the signal to undo is narrow: **Qt fixes both
the source blocking-write *and* the target in-process/unbounded read, the
fixed version is what Omarchy ships, and a rig freeze test passes against
stock Qt text widgets.** Until all three hold, the invariant stands. Track it
against qtbase `dev` `qquicktextinput.cpp` `canPaste` and
`qwaylanddataoffer.cpp` `readData`; the day both carry a bound, re-open this
record.

**Blast radius at the seam:** the seam is "QML ↔ system clipboard." Today it
is touched by 4 source paths and 1 read path across 4 files; after this it is
touched by 1 component. That narrowing is the point.

## 6. The check

Three checks, all buildable without asking what was meant. The first two are
class lints in the style of `tests/test_panelfield.py` / `test_clipboard.py`
(they already partially exist and are extended, not duplicated). The third is
the rig proof that the invariant actually holds at runtime.

**C-clip-1 (QML owns no Wayland data transfer).** Over every `*.qml` shipped
(exclude `dev/`, `tests/`), all must hold, each failure naming the file:line:

- no `TextField`/`TextInput`/`TextArea` instantiation (already in
  `test_panelfield.py:51`);
- no `selectByMouse: true` (new);
- no `Drag.dragType` / `Drag.Automatic` / `Drag.active` / `Drag.mimeData`
  (new);
- no `Quickshell.clipboardText` (already in `test_panelfield.py:109`);
- `wl-copy` and `wl-paste` appear in **`Clipboard.qml` only** (new — today
  they are scattered across PanelField, MessagesView, ContactsView); every
  other file reaches the clipboard through the `Clipboard` singleton.

**C-clip-2 (the read is bounded, out of the shell).** The one `wl-paste`
invocation is wrapped in `timeout -k <n> <n> wl-paste …` and piped through
`head -c <bytes>` (extends `test_panelfield.py:105`); it is run in a
`Process`, never `Quickshell.clipboardText`; private text never reaches a
`wl-copy` argv (it is on stdin — extends `test_argv.py`'s C1 class so a copy
that puts text on the command line fails the build).

**C-clip-3 (a hostile peer cannot freeze the shell — rig).** In the rig, with
the panel open: (a) a reader that requests the shell's selection and never
drains it must not stall IPC — select text in a message bubble, run a
clipboard/primary reader that holds the pipe, and assert
`dev/rig ipc status` answers within a small bound (the omacom/omarchy#8753
method: compare the IPC round-trip against a cold baseline, assert no multi-
second stall); (b) a paste from a provider that never finishes returns within
the `timeout` and inserts nothing, the shell still answering. Panel QA owns
building this from this spec; the PoC reader is a few lines of
`wl-paste`/a null-reading data-control client run under `dev/rig exec`.

The release does not go to the owner (SCE-694) until C-clip-3 is green on the
candidate; a measurement that the layout fits is not the proof — the freeze
test is.

## 7. The open part

- **The gallery drag (`Panel.qml:6586`).** I did not decide its
  replacement, only that the shell must not be the Qt DnD source. Default set
  so work continues: **drop `Drag.Automatic` and keep the existing copy
  button** (`Clipboard.copyFileData`) as the way a photo leaves to another
  window; "drag the tile into a window" loses the drag and keeps the copy.
  What would settle it otherwise: if a real drag-out is judged necessary,
  hand the file to a drag-source helper **process** (the shell still not the
  source) — measured against whether a null-reading drop target can stall the
  shell. Owner of that measurement: Panel Engineer with Panel QA; decide in
  the implementation issue, not by re-opening this record.
- **Component-driven mouse selection.** Whether selection-by-drag is offered
  at all on read-only bubbles, or only Select-All + copy via keys/buttons, is
  a UX call for the implementation (Charles Xavier if it changes what the
  user feels). The invariant does not require selection; it requires that
  whatever selection exists is `edit.select(...)`-driven, never
  `selectByMouse`.
- **The singleton's home.** Whether `Clipboard` lives in the plugin or is
  proposed up to Omarchy's shared `qs` Commons (so Omarchy's own panels and
  the second plugin share one implementation) is a boundary question with
  Omarchy; default is plugin-local now, propose sharing to Omar once it has
  proven out here. This also feeds omacom/omarchy#8753, where Omarchy's own
  always-alive text inputs have the read-side stall: our component is the
  reference answer to offer there.
