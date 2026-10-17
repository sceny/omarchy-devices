---
name: develop-panel
description: Change the Devices Omarchy plugin (sceny.devices) and see the change working, in the sandbox (dev/sandbox dev) where the hidden test rig (dev/rig) and its Android emulator run. Use when editing any of its QML, Model.js, the KDE Connect bridge or manifest.json, adding a control, a setting or a messages feature, or restyling the panel. Covers the edit loop, the tests, when the shell must restart, driving the panel over IPC, demo mode, the emulator, and how to look at the render (including transitions) and bring screenshots and recordings out. Read AGENTS.md first for the boundary and the rules.
---

# Changing the plugin

## 1. Where to edit

This repository is the plugin. Work in your own clone, never in the owner's
installed copy (`~/.config/omarchy/plugins/sceny.devices`). Everything below
runs in the sandbox (`dev/sandbox dev`, `docs/internals/development.md`): a
rootless container with no home, no credentials, no network and no host
socket, holding the hidden rig (`dev/rig`): a second shell in its own
compositor, the working tree installed as the plugin, and a small Android
emulator as the phone. `dev/rig` is not run on the host. The owner's shell,
desktop and phone are never used. Commands in this skill that start with
`RIG` or `IPC` go through the session:

```bash
RIG=(dev/sandbox dev rig)          # dev/rig's verbs, on the session's rig
IPC=(dev/sandbox dev rig ipc)      # the panel's IPC
```

With two or more sessions open, every `dev/sandbox dev` command needs the
session named: `dev/sandbox dev --session ID rig`, `dev/sandbox dev --session ID
rig ipc` (`dev/sandbox dev status` lists them). Leave other agents' sessions alone.

## 2. Check logic before the shell sees it

Pure logic lives in `Model.js` and in the bridge. Test both in the session:

```bash
dev/sandbox dev exec -- node --test tests/*.test.js              # Model.js
dev/sandbox dev --timeout 900 exec -- python3 -m unittest discover -s tests    # kdeconnect-bridge helpers (the full run outlasts the default timeout)
"${RIG[@]}" exec -- bin/kdeconnect-bridge snapshot               # what the plugin sees, as JSON
```

Add a test for every rule you touch. The data comes from a real device: never
paste real numbers, names or message text into a test; use 555 numbers.
`bin/kdeconnect-bridge` runs only through `RIG exec`: on the host it would read
the owner's KDE Connect.

## 3. Get the change into the rig

```bash
dev/sandbox dev start      # once: prints the session id; it ends by itself (TTL, at most four hours)
dev/sandbox dev sync       # after each edit: the tracked files go in (git add a new file first)
dev/sandbox dev up         # once per session: the rig, emulator booted and paired (2 to 4 minutes)
"${RIG[@]}" sync           # after each sync: installs the synced tree as the plugin
"${RIG[@]}" restart-shell  # after Panel.qml, SettingsView.qml, MessagesView.qml, BarWidget.qml, Model.js
"${IPC[@]}" status         # the panel answers
"${RIG[@]}" logs shell     # a QML error lands here
```

- `Service.qml`, `SmsService.qml` and the bridge reload by themselves on
  `rig sync`. `BarWidget.qml` logs the same line but the pill keeps
  drawing the old code: restart the rig's shell.
- **Anything the panel or the pill loads is cached by the shell:** only
  `rig restart-shell` picks it up. New IPC functions answer "Function not
  found" until then.
- **After every restart, confirm the panel answers** (`"${IPC[@]}" status`)
  **and runs the files you synced** (`"${RIG[@]}" exec -- dev/loaded-code
  <plugin dir>/sceny.devices`, the plugin dir from `"${RIG[@]}" status`). `status` is answered
  by old code too; a rescan does not reload a plugin, only a restart does.
  "Target not found" means the plugin failed to load and the widget is gone
  from the bar; read `"${RIG[@]}" logs shell`. The error can land after a quick
  log check has passed; the IPC check cannot.
- **Always stop the session** (`dev/sandbox dev stop --all`, then
  `dev/sandbox verify-clean`). At most two sessions run at once; `dev/sandbox
  dev status` lists them and `--session <id>` addresses one. Never kill a
  process by name.
- A session needs podman, `/dev/kvm` and a GPU render node on the host. Without
  them (a cloud session, no Omarchy), follow AGENTS.md, *Workflow*: the pull
  request says the change is not checked live, and the merge waits for someone
  who checks it.
- A commit not written by Sceny never goes through `dev`: it runs only in
  `dev/sandbox run` after the owner's go (AGENTS.md, *Workflow*).

The phone is the rig's emulator, named by the rig, with 555 numbers:

```bash
"${RIG[@]}" phone status
"${RIG[@]}" phone battery 20                       # the battery, in the bar and the panel
"${RIG[@]}" phone notify Calendar "Team sync"      # a notification on the phone
"${RIG[@]}" phone sms 5550100 "Lunch at noon?"     # an incoming text
"${RIG[@]}" phone call 5550100 ; "${RIG[@]}" phone hangup 0   # a call on the phone
"${RIG[@]}" check                                  # every check against the rig, including the screen link
```

Anything a check does to the emulator is free: it goes with the session.
Sending a text from the panel, ringing and changing volume still wait for the
owner's go, though the emulator is the one that would receive them.

## 4. Drive it over IPC

`"${IPC[@]}" <function> [args]` is the call in the rig; the list gives the
function names.

```bash
"${IPC[@]}" status                  # what the panel shows
"${IPC[@]}" open ; "${IPC[@]}" close
"${IPC[@]}" page settings           # also: main, messages, connection (diagnostics), ready (the first run's card)
"${IPC[@]}" demo ""                 # sample notifications; also demo away|down|none; then live
"${IPC[@]}" demo many               # several devices: tabs, chips; many-pair adds a pairing request
"${IPC[@]}" demo charging           # the demo phone charging (its battery glyph and % in the pill)
"${IPC[@]}" filesInfo ; "${IPC[@]}" dismissReceived 0   # Photos and Received; never open a real phone's photos in a check (they are private)
"${IPC[@]}" demoSetup ; "${IPC[@]}" ignoreCheck firewall true   # this computer: a failing firewall (a problem: the status, the card under the header, the gear's dot, a failing screen-tools check adds the Screen shortcut's dot after `editShortcut screen`); Ignore / Undo
"${IPC[@]}" demoFeature ask         # demo only: notification access to allow, said in Notifications; stopped: it stopped arriving; "" as set up
"${IPC[@]}" demoAway ; "${IPC[@]}" reconnect   # the phone away (last seen 12 min ago); Reconnect as its button (never a real search in demo)
"${IPC[@]}" reach ; "${IPC[@]}" reachInfo   # the viewed device's From anywhere page, as its row opens it (#119)
"${IPC[@]}" demoReach <ready|setup|pick|none|isolated|lost>   # demo only: a made-up network and This computer's mesh row; lost: the address KDE Connect had and lost (the Network problem in Settings' status, the main page's line and Fix all); then `page main` after `demo away` shows the away card's lines
"${IPC[@]}" demoAwayOn <device> ; "${IPC[@]}" pressAwayWhy   # demo only: one device of `demo many` away and viewed (id, nickname or name); Why? on the away card (toggles), answering what the card shows
"${IPC[@]}" preview true            # Preview with a demo phone (the user's demo, with its strip); false: Back to setup
"${IPC[@]}" view <device> ; "${IPC[@]}" openOn <device> ; "${IPC[@]}" tabs   # id, nickname or name
"${IPC[@]}" settingsScope <root|defaults|device> ; "${IPC[@]}" settingsRowsInfo   # a settings page and its rows
"${IPC[@]}" pressSetting <index> ; "${IPC[@]}" nickname <text> ; "${IPC[@]}" pickIcon <hex> ; "${IPC[@]}" moveDevice <device> -1
                                    # as a click would; anything changed in a demo (defaults too) is put back by `live`
"${IPC[@]}" demoCall ringing        # demo only: a call on the viewed device (replaces the last); missed, none
"${IPC[@]}" demoBluetooth off       # demo only: the missed-call card per Bluetooth state; ready, off, adapter, unpaired, unkept, dropped
"${IPC[@]}" pressCallOffer none     # demo only: the offer's No thanks (or open: Open Calls here)
"${IPC[@]}" pressTextBack ; "${IPC[@]}" closeCall   # the call card; never Call back in a test (it opens the phone's dialer)
"${IPC[@]}" demoTextTo 555-0199 ; "${IPC[@]}" pressEscape   # demo only: Text back to any number; Esc as the key; smsStatus shows newMessage
"${IPC[@]}" move 0 1                 # an arrow key (dx dy): the cursor moves, the glide slides; never Enter (slowMotion 10 to watch)
"${IPC[@]}" rightClickChip <device> ; "${IPC[@]}" edit   # edit in place (edit toggles); editBar/editBarFlag/editMoveBar, editSection/editShortcut/editMoveSection/editMoveShortcut
                                    # edits write settings: run them in a demo, which `live` puts back
"${IPC[@]}" showPlayer 1            # media carousel
"${IPC[@]}" messages ; "${IPC[@]}" smsStatus ; "${IPC[@]}" openThread <id> ; "${IPC[@]}" loadOlder
"${IPC[@]}" searchThreads <text> ; "${IPC[@]}" newMessage <digits>
"${IPC[@]}" demoMessageContact 555-0199 ; "${IPC[@]}" navInfo ; "${IPC[@]}" goBack ; "${IPC[@]}" goHome   # the page stack (base, stack, home shown, back tip); Esc / the arrow, and Home, as keys
"${IPC[@]}" fold actions ; "${IPC[@]}" moveSection media -1    # fold a section; move one in the order
"${IPC[@]}" toggleBar <key> ; "${IPC[@]}" moveBar <key> -1      # bar indicators; toggleBar batteryLowOnly
"${IPC[@]}" pressAction <index> "<action>"   # demo only: press a notification's action as a click would
"${IPC[@]}" pressDismiss <index>      # demo only: its X, to see the waiting ring
"${IPC[@]}" pressDismissAll           # demo only: the header's dismiss all, every row's ring
"${IPC[@]}" compose "<text>"        # the Send text field with <text>, unfocused; compose - closes it
"${IPC[@]}" demoWindow Maps true ; "${IPC[@]}" soundCard com.example.maps   # demo only: an app's window "open" (its badge); its sound card ("" the screen's)
"${IPC[@]}" soundInfo ; "${IPC[@]}" soundVolume 0.4 ; "${IPC[@]}" chooseSound phone   # the card; a real choice reopens the real window (owner's go)
"${IPC[@]}" slowMotion 10           # stretch every transition; slowMotion 1 to undo
```

None of these focus a text field, by design (AGENTS.md). Opening an unread
thread marks it seen in the session's own cache, which `dev stop` deletes.

**A sync reloads the plugin.** `rig sync` drops the IPC target for a
moment (`Target not found`). Wait about 2 s after it before scripted IPC, and check each call's answer before a
later step that undoes it: an undo after a failed call makes the change
instead of undoing it.

**Simulated keys go to whatever has keyboard focus.** For keyboard checks,
send them to the rig's compositor only (`"${RIG[@]}" exec -- wtype ...`, which
runs with the rig's Wayland display), open the panel over IPC, and before
every key check that `status` shows `"opened": true` and the expected
`cursor`; stop at the first mismatch. Never `wtype` on the host: it would type
into the owner's windows. `wtype -M shift -k k` types a
lowercase k: type `K` for Shift+K.

## 5. Look at it

```bash
"${IPC[@]}" open; sleep 1.2; dev/sandbox dev shot panel
dev/sandbox dev pull --out /tmp/panel-shots      # screenshots/panel.png, as data; a directory outside any git repository
```

Read the image: cut edges, wrapped labels, anything that jumped. For motion,
`slowMotion 10`, trigger it, and capture a frame part-way, or record it:

```bash
dev/sandbox dev record move 8 5 -- /opt/devside.sh rig ipc open   # 8 s at up to 5 frames/s while the command runs, plus 2 s
```

A pull brings the recording out as WebM and empties the session's output. The
rig has no lock screen and takes no keyboard from the owner. A screenshot or
recording of a rig shows only the emulator's data (the demo or a 555 number),
so it can go in a pull request or on the task; never one of a real device.
The owner looks at a finished result in those files: an agent never puts a rig
on the owner's screen.

## 6. Ship

Branch from `develop`, `gh pr create --base develop`, CI green, the change
checked in the sandbox, squash-merge (AGENTS.md, *Workflow*). A pull request into
`main` is only a release or an urgent fix, and never while `main` is frozen
for a marketplace review (AGENTS.md, *Releasing*). Users get `main` with
`omarchy plugin update sceny.devices` after a release.
