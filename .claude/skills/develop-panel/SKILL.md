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

- `Service.qml`, `SmsService.qml`, `BarWidget.qml` and the bridge reload by
  themselves when saved ("Local plugin changed, reloading").
- **Anything the panel loads (`Panel.qml`, `SettingsView.qml`,
  `MessagesView.qml`, `Model.js`) is cached by the shell:** only
  `omarchy restart shell` picks it up. New IPC functions answer "Function not
  found" until then. A restart blinks the whole bar, so batch changes.
- **After every restart, confirm the panel answers:**

  ```bash
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
"${IPC[@]}" page settings           # also: main, messages
"${IPC[@]}" demo ""                 # sample notifications; also demo away|down|none; then live
"${IPC[@]}" showPlayer 1            # media carousel
"${IPC[@]}" messages ; "${IPC[@]}" smsStatus ; "${IPC[@]}" openThread <id> ; "${IPC[@]}" loadOlder
"${IPC[@]}" searchThreads <text> ; "${IPC[@]}" newMessage <digits>
"${IPC[@]}" slowMotion 10           # stretch every transition; slowMotion 1 to undo
```

None of these focus a text field, by design (AGENTS.md). Opening an unread
thread marks it seen: undo that in
`~/.cache/sceny.devices/sms-seen-<device>.json` after a test.

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

## 6. Publish

Commit, push. Other machines take it with `omarchy plugin update sceny.devices`.
