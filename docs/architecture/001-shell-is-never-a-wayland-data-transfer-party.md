# 001 — The shell is never a party to a Wayland data transfer

Status: accepted · 2026-10-14, amended the same day (keyboard selection,
§2.3; what retires when Qt fixes land, §5.1) · owner of the decision: Mies
(architecture) · implements: SCE-696 · under: SCE-694 (Devices 0.8.4),
SCE-603 (marketplace #10096)

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

One QML component owns the boundary: **`Clipboard`**, a singleton in the
plugin (`Clipboard.qml`, registered in `qmldir`; sharing it beyond the plugin
is §7's open part). Nothing else in the plugin runs `wl-copy`
or `wl-paste`, reads `Quickshell.clipboardText`, or constructs a `Process`
for a clipboard verb.

```
Clipboard.copyText(text: string, done?: function) -> bool  // started
    // text to the system clipboard. Runs ["wl-copy"] with `text` on stdin,
    // never on argv (private text off the command line — test_argv.py C1).
    // stdinEnabled closed after the write. One in-flight copy at a time;
    // `done` is called when it ended.

Clipboard.copyPrimary(text: string, done?: function) -> bool  // started
    // same, ["wl-copy", "--primary"], for a middle-click-paste target we
    // chose to offer (today: none; reserved so a future need has a home).

(file copy) kdeconnect-bridge copy-file <mime> <path>
    // an image/file as data, out of the shell already
    // (bin/kdeconnect-bridge:1222); argv carries the path, never the bytes.
    // Called from Service.qml as today, or forwarded by Clipboard; either
    // way the shell is not the source. Named so the inventory is complete.

Clipboard.readInto(cb: function(text: string)) -> bool  // started
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
- **Keyboard selection is the component's too.** Every key Qt's text control
  handles ends at its `accept:` label, which calls `setClipboardSelection()`
  (`qquicktextcontrol.cpp:962-965`, 6.11.2): if a selection survives the
  key, the shell takes the primary selection, exactly as by mouse. The full
  list of callers of `setClipboardSelection()` is six: mouse extend (×2),
  mouse release, double click, the Select-All key, and `accept:`. Which keys
  leave a selection standing is not a short list: **Shift+movement**
  (`cursorMoveKeyEvent` with `KeepAnchor`, reached only with
  `selectByKeyboard`), `Key_Direction_L`/`R`, and also Undo or Redo with
  nothing to undo (`QTextDocument::undo` replaces the cursor only when
  `pos >= 0`). So the rule does not list the dangerous keys; it lists the
  safe ones:
  - a **read-only** surface keeps `selectByKeyboard` at its read-only
    default (`false`; `qquicktextedit.cpp` `setReadOnly`), and nothing sets
    it `true`; its own keys (Copy, Select-All) are taken before Qt, as the
    message bubble does;
  - an **editable** surface (`PanelField`, the only one, plain text) takes
    every selection key before Qt sees it (`event.matches(StandardKey.SelectNextChar)`
    and the other `Select*` standard keys: char, word, line, line start and
    end, document start and end, page) and moves the selection itself,
    `edit.select(anchor, newPosition)`, keeping the anchor where the
    selection began; `Key_Direction_L`/`R` are swallowed;
  - **while a selection stands** on an editable surface, a key reaches Qt
    only if it consumes the selection: text input, Backspace, Delete and the
    `Delete*` standard keys (each removes it before `accept:`). Plain Left
    and Right collapse it to its start or end in the component. Before any
    other key reaches Qt (Undo, Redo, Up, Down, Home, End, a key added
    later), the component calls `edit.deselect()`. Qt's `accept:` then
    never finds a selection standing, whatever the key.
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
  the bridge's `copy-file`) or, if drag is kept, the file handed to a drag
  helper process — decided in the implementation issue, not here (§7).

## 3. What this rules out

- **Patch the next path the reviewer names, again.** Rejected: this is the
  behaviour the owner stopped. Five rounds on #10096 each closed exactly the
  path named (TextInput read → focus read → paste read) and left the next
  one. Cost of continuing: one release per path, indefinitely, and a
  marketplace listing frozen the whole time.
- **Wait for Qt.** Rejected on measurement (qtbase and qtdeclarative,
  compared by tag and by file content). The source-side fix (qtbase
  0b3ed8ba40, `QWaylandPipeWriteHelper::safeWriteWithTimeout`) is in
  **6.12.0 and `dev` only**: not in 6.11.2, not on the 6.11 branch under any
  SHA, and the installed Qt is 6.11.2. It also **bounds one stall, not the
  attack**: each `send` request still waits up to 5 s on the GUI thread, so a
  peer that asks again and again keeps the shell frozen 5 s at a time
  (inferred from the code, not run). The target-side `canPaste` /
  `q_canPasteChanged` in-process read is fixed only on qtdeclarative `dev`
  (ef692a52e3, 2026-09-13), not in 6.12.0. The unbounded `readData` loop
  (`Q_FOREVER`, 1 s per `poll`, no total cap) is unchanged on every branch,
  `dev` included. Cost of waiting: the freeze ships to users until Omarchy's
  Qt carries fixes that, on the read side, do not exist yet. What each fix
  retires when it does land is §5.1.
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
let components touch the clipboard again), but it is the only thing that
stops the freeze. It is undone piece by piece, as §5.1 says, never at once.

### 5.1 What retires when Qt fixes land

**No fix waits for Qt.** Every piece below ships now. Retiring one is a later,
separate change, made only when its trigger holds; a Qt fix that is announced,
merged on `dev` or shipped in a Qt that Omarchy does not install retires
nothing. "Omarchy's Qt" is what Omarchy installs: `pacman -Q qt6-base
qt6-declarative` on a current Omarchy, 6.11.2 today.

| Piece (ships now) | Qt defect it covers | Upstream, measured 2026-10-14 | Retires when |
|---|---|---|---|
| Copy and cut through `Clipboard.copyText` (`wl-copy`); Copy and Cut keys taken before Qt; no QML call to a text item's `copy()`/`cut()` | The shell as clipboard source: blocking `write` on the GUI thread (`data_source_send`) | qtbase 0b3ed8ba40 in 6.12.0: a 5 s cap **per request**, still on the GUI thread | Omarchy's Qt serves a selection without the GUI thread waiting on the peer (asynchronous, or a total bound across requests), **and** C-clip-3(a) passes with Qt's own `copy()`. 6.12.0 alone does not meet it. |
| `selectByMouse: false`, component-driven selection | The shell as primary-selection source (`setClipboardSelection`, mouse paths) | Same as above | Same trigger as the row above, **and** C-clip-3(c) passes with `selectByMouse: true`. |
| Selection keys taken by `PanelField`; `selectByKeyboard` never `true` on read-only text | The shell as primary-selection source (`accept:` → `setClipboardSelection`) | Same as above | Same trigger as the first row, **and** C-clip-3(c) passes with Qt's own Shift+movement. |
| No `Drag.Automatic` / `Drag.active` (gallery drag-out dropped, copy kept) | The shell as drag source (same `data_source_send`, inside `QDrag::exec`'s nested event loop) | Same as above | Same trigger as the first row, **and** a null-reading drop target cannot stall the shell in the rig. |
| Paste through `Clipboard.readInto` (bounded `wl-paste`); Paste key taken before Qt; no QML call to `paste()` | The shell as reader: `QWaylandMimeData::readData`, `Q_FOREVER` with 1 s per `poll`, no total time or byte cap | **No fix on any branch**: identical in 6.11.2, 6.11, 6.12.0 and `dev` | Omarchy's Qt bounds the read in total time and bytes, or reads off the GUI thread, **and** C-clip-3(b) passes with Qt's own `paste()`. |
| Middle click swallowed on every text surface | Qt's middle-button paste of the primary selection (the same read) | Same as above | Same trigger as the row above. |
| Drops refused (`DropArea`) | A drop read in-process (the same read) | Same as above | Same trigger as the paste row. |
| No `TextField` / `TextInput` / `TextArea` | `QQuickTextInput::canPaste` / `q_canPasteChanged` read the payload on every clipboard change, no gesture needed | qtdeclarative ef692a52e3 (2026-09-13) on `dev` only; not in 6.12.0 | Omarchy's Qt carries ef692a52e3. Then `TextInput` is allowed **under every rule above**, no fewer; it is the cheapest piece to keep, and the last worth retiring. |

**Never retires:** the `Clipboard` component (the one door; once the copy
and paste rows retire, its insides may call Qt's clipboard, and its callers
do not change), the rule that `wl-copy`/`wl-paste` appear only in it, and
C-clip-3, which is both the proof a row's trigger asks for and the guard
after a row is gone.

**Who looks:** the release regression records Omarchy's Qt versions
(`pacman -Q qt6-base qt6-declarative`) beside the candidate. When one meets a
trigger above, the regression's author files the retirement as its own
issue for Panel Engineer, naming the row. Nobody re-opens this record for
it.

**Blast radius at the seam:** the seam is "QML ↔ system clipboard." Before
this record it was touched by five source paths (copy and cut, mouse
selection, keyboard selection, the Select-All key, the gallery drag) and
three read paths (paste, middle click, a drop) across four files; after it,
by one component. That narrowing is the point.

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
- no `selectByKeyboard: true` (new);
- no call to a text item's own `copy()`, `cut()` or `paste()` (new; the
  pattern `\.(copy|cut|paste)\(\)` outside `Clipboard.qml`, so a context-menu
  item cannot reach Qt's clipboard);
- `PanelField.qml`'s key handler matches every `StandardKey.Select*` (new;
  the list in §2.3) and `Key_Direction_L`/`R`, and calls `deselect()` on
  the path where a key reaches Qt while a selection stands;
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
the `timeout` and inserts nothing, the shell still answering; (c) **the shell
never takes the primary selection**: put a marker there first
(`wl-copy --primary <marker>` under `dev/rig exec`), make each selection
gesture in the panel (a mouse drag, a double click, Shift+Left/Right,
Shift+Home/End, Ctrl+Shift+Left, Ctrl+A, on a `PanelField` and on a message
bubble; then, with a selection standing in a fresh `PanelField`, Ctrl+Z,
Ctrl+Shift+Z, Home, End, Up, Down, and Left at the start of the text), and
after each, `wl-paste --primary` still returns the marker. If
any Qt path, listed in §2.3 or not, makes the shell the owner, the selected
text comes back instead and the check fails. Panel QA owns
building this from this spec; the PoC reader is a few lines of
`wl-paste`/a null-reading data-control client run under `dev/rig exec`.

The release does not go to the owner (SCE-694) until C-clip-3 is green on the
candidate; a measurement that the layout fits is not the proof — the freeze
test is.

## 7. The open part

- **The gallery drag (`Panel.qml:6586`).** I did not decide its
  replacement, only that the shell must not be the Qt DnD source. Default set
  so work continues: **drop `Drag.Automatic` and keep the existing copy
  button** (the bridge's `copy-file`) as the way a photo leaves to another
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
