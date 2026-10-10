---
name: develop-panel
description: Change the Devices Omarchy plugin (sceny.devices) and see the change working, in the hidden test rig (dev/rig) with its Android emulator. Use when editing any of its QML, Model.js, the KDE Connect bridge or manifest.json, adding a control, a setting or a messages feature, or restyling the panel. Covers the edit loop, the tests, when the shell must restart, driving the panel over IPC, demo mode, the emulator, and how to look at the render (including transitions). Read AGENTS.md first for the boundary and the rules.
---

# Changing the plugin

## 1. Where to edit

This repository is the plugin. Work in your own clone, never in the owner's
installed copy (`~/.config/omarchy/plugins/sceny.devices`). Everything below
runs in the hidden rig (`dev/rig`, `docs/internals/development.md`): a
second shell in its own compositor, the working tree installed as the
plugin, and a small Android emulator as the phone. The owner's shell, desktop
and phone are never used.

## 2. Check logic before the shell sees it

Pure logic lives in `Model.js` and in the bridge. Test both:

```bash
node --test tests/*.test.js                       # Model.js
python3 -m unittest discover -s tests    # kdeconnect-bridge helpers
bin/kdeconnect-bridge snapshot           # what the plugin sees, as JSON
```

Add a test for every rule you touch. The data comes from a real device: never
paste real numbers, names or message text into a test; use 555 numbers.

## 3. Get the change into the rig

```bash
dev/rig up                 # once: hidden, emulator paired (2 to 4 minutes); --no-phone for demo-only work
dev/rig sync               # after each edit: installs the working tree as the plugin
dev/rig restart-shell      # after Panel.qml, SettingsView.qml, MessagesView.qml, BarWidget.qml, Model.js
dev/rig ipc status         # the panel answers
dev/rig logs shell         # a QML error lands here
```

- `Service.qml`, `SmsService.qml` and the bridge reload by themselves on
  `dev/rig sync`. `BarWidget.qml` logs the same line but the pill keeps
  drawing the old code: restart the rig's shell.
- **Anything the panel or the pill loads is cached by the shell:** only
  `dev/rig restart-shell` picks it up. New IPC functions answer "Function not
  found" until then.
- **After every restart, confirm the panel answers** (`dev/rig ipc status`).
  "Target not found" means the plugin failed to load and the widget is gone
  from the bar; read `dev/rig logs shell`. The error can land after a quick
  log check has passed; the IPC check cannot.
- **Always take the rig down** (`dev/rig down`, then `dev/rig verify-clean`).
  Several rigs may run at once; with `--owner none` address one with
  `dev/rig --rig <id> <command>`. Never kill a rig's processes by name.
- Without the rig (a cloud session, no `labwc` or Android SDK), follow
  AGENTS.md, *Workflow*: the pull request says the change is not checked live,
  and the merge waits for someone who checks it.

The phone is the rig's emulator, named by the rig, with 555 numbers:

```bash
dev/rig phone status
dev/rig phone battery 20                       # the battery, in the bar and the panel
dev/rig phone notify Calendar "Team sync"      # a notification on the phone
dev/rig phone sms 5550100 "Lunch at noon?"     # an incoming text
dev/rig phone call 5550100 ; dev/rig phone hangup 0   # a call on the phone
dev/rig check                                  # every check against the rig, including the screen link
```

Anything a check does to the emulator is free: it is deleted by `dev/rig
down`. Sending a text from the panel, ringing and changing volume still wait
for the owner's go, though the emulator is the one that would receive them.

## 4. Drive it over IPC

`dev/rig ipc <function> [args]` is the call in the rig; the list gives the
function names (write `IPC=(dev/rig ipc)` to use them as shown).

```bash
IPC=(dev/rig ipc)
"${IPC[@]}" status                  # what the panel shows
"${IPC[@]}" open ; "${IPC[@]}" close
"${IPC[@]}" page settings           # also: main, messages, connection (diagnostics), ready (the first run's card)
"${IPC[@]}" demo ""                 # sample notifications; also demo away|down|none; then live
"${IPC[@]}" demo many               # several devices: tabs, chips; many-pair adds a pairing request
"${IPC[@]}" demo charging           # the demo phone charging (its battery glyph and % in the pill)
"${IPC[@]}" filesInfo ; "${IPC[@]}" dismissReceived 0   # Photos and Received; never open a real phone's photos in a check (they are private)
"${IPC[@]}" demoSetup ; "${IPC[@]}" ignoreCheck firewall true   # this computer: a failing firewall (a problem: the status, the main page's line, the gear's dot); Ignore / Undo
"${IPC[@]}" demoFeature ask         # demo only: notification access to allow, said in Notifications; stopped: it stopped arriving; "" as set up
"${IPC[@]}" demoAway ; "${IPC[@]}" reconnect   # the phone away (last seen 12 min ago); Reconnect as its button (never a real search in demo)
"${IPC[@]}" preview true            # Preview with a demo phone (the user's demo, with its strip); false: Back to setup
"${IPC[@]}" view <device> ; "${IPC[@]}" openOn <device> ; "${IPC[@]}" tabs   # id, nickname or name
"${IPC[@]}" settingsScope <root|defaults|device> ; "${IPC[@]}" settingsRowsInfo   # a settings page and its rows
"${IPC[@]}" pressSetting <index> ; "${IPC[@]}" nickname <text> ; "${IPC[@]}" pickIcon <hex> ; "${IPC[@]}" moveDevice <device> -1
                                    # as a click would; anything changed in a demo (defaults too) is put back by `live`
"${IPC[@]}" demoCall ringing        # demo only: a call on the viewed device (replaces the last); missed, none
"${IPC[@]}" pressTextBack ; "${IPC[@]}" closeCall   # the call card; never Call back in a test (it opens the phone's dialer)
"${IPC[@]}" demoTextTo 555-0199 ; "${IPC[@]}" pressEscape   # demo only: Text back to any number; Esc as the key; smsStatus shows newMessage
"${IPC[@]}" move 0 1                 # an arrow key (dx dy): the cursor moves, the glide slides; never Enter (slowMotion 10 to watch)
"${IPC[@]}" rightClickChip <device> ; "${IPC[@]}" edit   # edit in place (edit toggles); editBar/editBarFlag/editMoveBar, editSection/editShortcut/editMoveSection/editMoveShortcut
                                    # edits write settings: run them in a demo, which `live` puts back
"${IPC[@]}" showPlayer 1            # media carousel
"${IPC[@]}" messages ; "${IPC[@]}" smsStatus ; "${IPC[@]}" openThread <id> ; "${IPC[@]}" loadOlder
"${IPC[@]}" searchThreads <text> ; "${IPC[@]}" newMessage <digits>
"${IPC[@]}" fold actions ; "${IPC[@]}" moveSection media -1    # fold a section; move one in the order
"${IPC[@]}" toggleBar <key> ; "${IPC[@]}" moveBar <key> -1      # bar indicators; toggleBar batteryLowOnly
"${IPC[@]}" pressAction <index> "<action>"   # demo only: press a notification's action as a click would
"${IPC[@]}" pressDismiss <index>      # demo only: its X, to see the waiting ring
"${IPC[@]}" compose "<text>"        # the Send text field with <text>, unfocused; compose - closes it
"${IPC[@]}" demoWindow Maps true ; "${IPC[@]}" soundCard com.example.maps   # demo only: an app's window "open" (its badge); its sound card ("" the screen's)
"${IPC[@]}" soundInfo ; "${IPC[@]}" soundVolume 0.4 ; "${IPC[@]}" chooseSound phone   # the card; a real choice reopens the real window (owner's go)
"${IPC[@]}" slowMotion 10           # stretch every transition; slowMotion 1 to undo
```

None of these focus a text field, by design (AGENTS.md). Opening an unread
thread marks it seen: undo that in
`~/.cache/sceny.devices/sms-seen-<device>.json` after a test.

**A sync reloads the plugin.** `dev/rig sync` drops the IPC target for a
moment (`Target not found`). Wait about 2 s after it before scripted IPC, and check each call's answer before a
later step that undoes it: an undo after a failed call makes the change
instead of undoing it.

**Simulated keys go to whatever has keyboard focus.** For keyboard checks,
send them to the rig's compositor only (`dev/rig exec -- wtype ...`, which
runs with the rig's Wayland display), open the panel over IPC, and before
every key check that `status` shows `"opened": true` and the expected
`cursor`; stop at the first mismatch. Never `wtype` outside `dev/rig exec`:
it would type into the owner's windows. `wtype -M shift -k k` types a
lowercase k: type `K` for Shift+K.

## 5. Look at it

```bash
dev/rig ipc open; sleep 1.2; dev/rig screenshot /tmp/panel.png
```

Read the image: cut edges, wrapped labels, anything that jumped. For motion,
`slowMotion 10`, trigger it, and capture a frame part-way. The rig has no
lock screen and takes no keyboard from the owner. A screenshot of a rig shows
only the emulator's data (the demo or a 555 number), so it can go in a pull
request; never one of a real device. The owner looks at a finished result
with `dev/rig show` (and `dev/rig hide` afterwards): an agent never runs it
unasked.

## 6. Ship

Branch from `develop`, `gh pr create --base develop`, CI green, the change
checked in the rig, squash-merge (AGENTS.md, *Workflow*). A pull request into
`main` is only a release or an urgent fix, and never while `main` is frozen
for a marketplace review (AGENTS.md, *Releasing*). Users get `main` with
`omarchy plugin update sceny.devices` after a release.
