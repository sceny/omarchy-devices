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
"${IPC[@]}" live                   # back to the phone
"${IPC[@]}" page settings          # also main, messages
"${IPC[@]}" openThread <id> ; "${IPC[@]}" loadOlder
"${IPC[@]}" pressDismiss 0         # demo only: a notification's X
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

`preview.png` (the marketplace card and the README) is composed by
`tools/listing-image` from two demo shots of a 2560x1440 screen:

1. Move to an empty workspace:
   `hyprctl dispatch 'hl.dsp.focus({ workspace = "9" })'`, and the pointer
   off the panel.
2. Start the made-up player: `tools/demo-player ~/.cache/sceny.devices/demo/cover.png &`
   (any square image as the cover).
3. `demo ""`, `open`, then `grim main.png`; `messages`, `openThread 9001`,
   then `grim messages.png`.
4. `tools/listing-image main.png messages.png preview.png`, and look at every
   pixel before committing.
5. Back: `close`, `live`, stop the player, return to your workspace.

## Contributing

`main` is what users install and moves only at a release; changes go into
`develop` through pull requests, CI green and checked in a running shell. A
release merges `develop` into `main`; the `release` workflow tags it and
publishes the notes from [CHANGELOG.md](../../CHANGELOG.md).
