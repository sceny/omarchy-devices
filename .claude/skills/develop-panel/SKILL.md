---
name: develop-panel
description: Change the Devices Omarchy plugin (sceny.devices) and see the change working. Use when editing any of its QML, Model.js, the KDE Connect bridge or manifest.json, adding a control, a setting or a messages feature, or restyling the panel. Covers the edit loop, the tests, when the shell must restart, driving the panel over IPC, demo mode, and how to look at the render (including transitions). Read AGENTS.md first for the boundary and the rules.
---

# Changing the plugin

## 1. Where to edit

This repository is the plugin. It installs with
`omarchy plugin add https://github.com/sceny/omarchy-devices.git` into
`~/.config/omarchy/plugins/sceny.devices`, and on a development machine that
folder can be the working clone itself.

## 2. Check logic before the shell sees it

Pure logic lives in `Model.js` and in the bridge. Test both:

```bash
node --test tests/*.test.js                       # Model.js
python3 -m unittest discover -s tests    # kdeconnect-bridge helpers
bin/kdeconnect-bridge snapshot           # what the plugin sees, as JSON
```

Add a test for every rule you touch. The data comes from a real device: never
paste real numbers, names or message text into a test; use 555 numbers.

## 3. Get the change into the shell

Steps 3 to 5 need a running Omarchy shell. Without one (a cloud session),
follow AGENTS.md, *Workflow*: the pull request says the change is not
checked live, and the merge waits for someone who checks it.

- **The shell runs the installed copy, not your clone** (AGENTS.md,
  *Workflow*): push the branch, then in the installed copy
  `git fetch && git switch <branch>`; `git switch develop && git pull` when
  done.
- `Service.qml`, `SmsService.qml` and the bridge reload by themselves when
  they change in the installed copy ("Local plugin changed, reloading"). `BarWidget.qml` logs the same
  line but the pill keeps drawing the old code: restart.
- **Anything the panel or the pill loads (`Panel.qml`, `SettingsView.qml`,
  `MessagesView.qml`, `BarWidget.qml`, `Model.js`) is cached by the shell:** only
  `omarchy restart shell` picks it up. New IPC functions answer "Function not
  found" until then. A restart blinks the whole bar, so batch changes.
- **Let a reload finish before restarting the shell.** When the installed
  copy's files change, the shell reloads the plugin; wait until the panel
  answers over IPC again, then `omarchy restart shell`. A restart while the
  reload is still creating objects can crash the shell.

  ```bash
  for i in $(seq 1 20); do timeout 3 qs -p /usr/share/omarchy/shell/shell.qml ipc call sceny.devices status >/dev/null 2>&1 && break; sleep 0.5; done
  sleep 2 && omarchy restart shell
  ```

- **After every restart, confirm the panel answers, from the new shell.**
  The old shell can still answer IPC for a moment while it goes away; a
  scripted step sent to it acts on its copy of the settings, which then
  lands in `shell.json`. Wait for a new process first:

  ```bash
  old=$(pgrep -x quickshell); omarchy restart shell
  until p=$(pgrep -x quickshell) && [ "$p" != "$old" ]; do sleep 0.3; done
  timeout 8 qs -p /usr/share/omarchy/shell/shell.qml ipc call sceny.devices status
  ```

  "Target not found" means the plugin failed to load and the widget is gone
  from the bar. Read `journalctl --user -t omarchy-shell -n 80 -o cat`. The
  error can land after a quick log check has passed; the IPC check cannot.

## 4. Drive it over IPC, always with a timeout

```bash
IPC=(timeout 8 qs -p /usr/share/omarchy/shell/shell.qml ipc call sceny.devices)
"${IPC[@]}" status                  # what the panel shows
"${IPC[@]}" open ; "${IPC[@]}" close
"${IPC[@]}" page settings           # also: main, messages, connection
"${IPC[@]}" demo ""                 # sample notifications; also demo away|down|none; then live
"${IPC[@]}" demo many               # several devices: tabs, chips; many-pair adds a pairing request
"${IPC[@]}" demo charging           # the demo phone charging (its battery glyph and % in the pill)
"${IPC[@]}" filesInfo ; "${IPC[@]}" dismissReceived 0   # Photos and Received; never open a real phone's photos in a check (they are private)
"${IPC[@]}" demoSetup ; "${IPC[@]}" ignoreCheck firewall true   # Connection: a failing firewall (the gear's dot); Ignore / Undo
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
"${IPC[@]}" slowMotion 10           # stretch every transition; slowMotion 1 to undo
```

None of these focus a text field, by design (AGENTS.md). Opening an unread
thread marks it seen: undo that in
`~/.cache/sceny.devices/sms-seen-<device>.json` after a test.

**A save reloads the plugin.** Saving any file in the plugin folder, even a
`.md`, drops the IPC target for a moment (`Target not found`). Wait about
2 s after a save before scripted IPC, and check each call's answer before a
later step that undoes it: an undo after a failed call makes the change
instead of undoing it.

**Simulated keys go to whatever has keyboard focus.** For keyboard checks
(`wtype`), open the panel over IPC, and before every key check that
`status` shows `"opened": true` and the expected `cursor`; stop at the first
mismatch. Never while the owner is typing. `wtype -M shift -k k` types a
lowercase k: type `K` for Shift+K.

## 5. Look at it

```bash
pgrep -x hyprlock && echo "LOCKED: do not open the panel"
"${IPC[@]}" open; sleep 1.2; grim -g "$(hyprctl monitors -j | jq -r '.[0] | "\(.x),\(.y) \(.width)x\(.height)"')" /tmp/panel.png
```

Read the image: cut edges, wrapped labels, anything that jumped. For motion,
`slowMotion 10`, trigger it, and capture a frame part-way. Opening the panel
takes keyboard focus: not while the owner is typing, and never on a locked
screen. A screenshot of a real device shows real messages and notifications:
keep it out of the repository and delete it once read.

## 6. Ship

Branch from `develop`, `gh pr create --base develop`, CI green, the change
checked in a running shell, squash-merge, then `git switch develop && git
pull` in the installed clone (AGENTS.md, *Workflow*). A pull request into
`main` is only a release or an urgent fix, and never while `main` is frozen
for a marketplace review (AGENTS.md, *Releasing*). Users get `main` with
`omarchy plugin update sceny.devices` after a release.
