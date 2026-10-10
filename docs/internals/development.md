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
"${IPC[@]}" demo charging          # the demo phone charging
"${IPC[@]}" filesInfo ; "${IPC[@]}" dismissReceived 0   # Photos and Received: what they hold; forget a received file (demo: made-up files)
bin/kdeconnect-bridge photos-cached <device>   # the last photo list, at once (the panel shows it while the phone is read)
"${IPC[@]}" preview true           # Preview with a demo phone, as its button (false: Back to setup)
"${IPC[@]}" view "Galaxy Tab S9"   # view a device (id, nickname or name); openOn opens on it; tabs
"${IPC[@]}" settingsScope "Galaxy Tab S9"   # a device's settings page; also root, defaults
"${IPC[@]}" live                   # back to the phone
"${IPC[@]}" page settings          # also main, messages, connection
"${IPC[@]}" demoSetup ; "${IPC[@]}" demoAway ; "${IPC[@]}" reconnect   # This computer's checks; the phone away; Reconnect
"${IPC[@]}" openThread <id> ; "${IPC[@]}" loadOlder
"${IPC[@]}" pressDismiss 0         # demo only: a notification's X
"${IPC[@]}" demoCall ringing       # demo only: a call on the viewed device; also missed, none
"${IPC[@]}" pressTextBack ; "${IPC[@]}" closeCall   # the call card's Text back (nothing focused) and X
"${IPC[@]}" demoTextTo 555-0199 ; "${IPC[@]}" pressEscape   # demo only: Text back to any number; Esc on the panel
"${IPC[@]}" move 0 1                 # an arrow key (dx dy): the cursor moves, the glide slides; never Enter (slowMotion 10 to watch)
"${IPC[@]}" rightClickChip <device> ; "${IPC[@]}" edit   # edit the page (and again to end); then editBar <key>, editBarFlag <key>, editMoveBar <key> -1, editSection <key>, editShortcut <key>
"${IPC[@]}" problems ; "${IPC[@]}" closeBanner   # what needs the user (status, dot, main page's line); close that line
"${IPC[@]}" settingsRowsInfo ; "${IPC[@]}" pressSetting <index>   # Settings' rows; a row as Enter would
"${IPC[@]}" switchFeature screen false ; "${IPC[@]}" screenFeatureInfo   # a feature's switch on the device page shown
"${IPC[@]}" demoScreen ready ; "${IPC[@]}" appsInfo   # demo only: the screen link's state; the Apps section
"${IPC[@]}" askRoot firewall ; "${IPC[@]}" cancelRoot   # the password card (nothing runs until Continue)
"${IPC[@]}" navInfo ; "${IPC[@]}" goBack ; "${IPC[@]}" goHome   # the page stack (base, stack, home shown, back tip); Esc / the arrow, and Home, as keys
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
