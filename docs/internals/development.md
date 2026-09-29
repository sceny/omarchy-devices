[Devices](../../README.md) › Internals › Development

# Development

Read [AGENTS.md](../../AGENTS.md) first: the rules the plugin is built to,
and the steps for changes and releases.

## Tests

```bash
node --test tests/*.test.js              # Model.js
python3 -m unittest discover -s tests    # the bridge's pure pieces
bin/kdeconnect-bridge snapshot           # what the plugin sees
```

## Driving the panel

```bash
IPC=(timeout 8 qs -p /usr/share/omarchy/shell/shell.qml ipc call sceny.devices)
"${IPC[@]}" status                 # what the panel shows
"${IPC[@]}" demo ""                # made-up notifications and conversations; demo away|down|none
"${IPC[@]}" demo many              # several devices (tabs, chips); many-pair adds a pairing request
"${IPC[@]}" view "Galaxy Tab S9"   # view a device (id, nickname or name); openOn opens on it; tabs
"${IPC[@]}" settingsScope "Galaxy Tab S9"   # a device's settings page; also root, defaults
"${IPC[@]}" live                   # back to the phone
"${IPC[@]}" page settings          # also main, messages
"${IPC[@]}" openThread <id> ; "${IPC[@]}" loadOlder
"${IPC[@]}" pressDismiss 0         # demo only: a notification's X
"${IPC[@]}" demoCall ringing       # demo only: a call on the viewed device; also missed, none
"${IPC[@]}" pressTextBack ; "${IPC[@]}" closeCall   # the call card's Text back (nothing focused) and X
"${IPC[@]}" demoTextTo 555-0199 ; "${IPC[@]}" pressEscape   # demo only: Text back to any number; Esc on the panel
"${IPC[@]}" rightClickChip <device> ; "${IPC[@]}" edit   # edit the page (and again to end); then editBar <key>, editBarFlag <key>, editMoveBar <key> -1, editSection <key>, editShortcut <key>
"${IPC[@]}" slowMotion 10          # stretch every transition
```

None of them focuses a text field.

**Demo mode** sends nothing to the phone. It fakes notifications and
conversations (fictional names, 555 numbers, an 18:40 clock), waits as long
as a phone would, and names the device Pixel 8. Media stays the real
players. Screenshots come from demo mode only; the picture message reads
`~/.cache/sceny.devices/demo/picture.jpg`, which is not in the repository.

**Reloading:** saving `Service.qml`, `SmsService.qml` or the bridge reloads
the plugin; `Panel.qml`, `MessagesView.qml`, `BarWidget.qml` and `Model.js`
need `omarchy restart shell`. Errors land in
`journalctl --user -t omarchy-shell`.

## Screenshots

See [Screenshots](screenshots.md): demo data only.

## Contributing

`main` is what users install and moves only at a release; changes go into
`develop` through pull requests, CI green and checked in a running shell. A
release merges `develop` into `main`; the `release` workflow tags it and
publishes the notes from [CHANGELOG.md](../../CHANGELOG.md).
