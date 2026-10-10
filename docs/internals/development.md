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

## The test rig

All development and testing happens in `dev/rig`: a second Omarchy shell in
its own Hyprland, hidden inside a headless `labwc`, with the plugin
installed from the working tree and a small Android emulator as the phone.
Nothing is mapped on the owner's monitors, no focus or window of theirs
moves, nothing is written to their `~/.config`, and the owner's shell, KDE
Connect daemon, adb server and phone are never touched. The owner looks at a
finished result with `dev/rig show`.

```bash
dev/rig up                  # hidden rig, emulator booted and paired (about 2 to 4 minutes)
dev/rig sync                # install the working tree as the plugin
dev/rig ipc status          # the panel's IPC, as in the next section
dev/rig screenshot x.png    # the nested shell, hidden or not
dev/rig phone status        # battery N, notify T X, sms 555... X, call 555..., hangup N, shot, pair
dev/rig restart-shell       # after a change to Panel.qml, Model.js and the like
dev/rig check               # every check against the running rig (the phone's battery, a notification,
                            # a call, the screen link and its window, the host left untouched)
dev/rig down                # tear it down and prove nothing is left
dev/rig ci                  # up, check, down in one command
dev/rig ps | reap | verify-clean | logs <name> | exec -- <cmd> | selftest
dev/rig show | hide         # the owner's: puts the rig on their screen and takes it off
```

With `--owner none` a rig ends only by `down` or its TTL (`--ttl`); address it
with `dev/rig --rig <id> <command>`.

**The phone.** A headless emulator (`emulator -no-window`, API 34 x86_64 Google
APIs image, KVM) started and deleted by the rig, with the pinned KDE Connect
for Android installed and permitted over adb, paired to a `kdeconnectd` on the
rig's own session bus. All of it runs in a user and network namespace with no
route out (`10.255.0.2`, a loopback relay for the discovery packets), so the
owner's daemon and phone cannot see it and it cannot see them. The bridge
runs against the rig's bus and finds the emulator through the rig's adb
server; scrcpy mirrors into the hidden session.

```bash
dev/rig phone battery 20          # the phone's battery level
dev/rig phone notify Calendar "Team sync at 3 pm"
dev/rig phone sms 5550100 "Lunch at noon?"   # an incoming text (the emulator cannot send one out)
dev/rig phone call 5550100        # ring; hangup 0 ends it
```

The rig's phone is named *Rig laptop* on its side and announces itself as
`sdk_gphone64_x86_64`; numbers are 555 numbers. Sending a text, ringing and
the volume are still the owner's go.

**Size.** The emulator is set to 1.5 GB of RAM (about 1.4 GB resident when
idle, about 3.7 GB at the peak of the boot), 2 cores, 720x1280, and a 2 GB
data partition (about 950 MB on disk per rig, deleted by `down`). The
system image is installed once on the host (`system-images;android-34;google_apis;x86_64`,
4.2 GB) and the KDE Connect APK is cached once (6.5 MB, checked against its
sha256 and signer every time).

**Host prerequisites.** `labwc`, `wtype`, `socat`, `iproute2`, `dbus`,
`kdeconnect`, `python3`, `curl`, and for the screen checks `scrcpy`; an Android
SDK with the emulator, platform-tools and the system image above
(`ANDROID_SDK_ROOT`, default `~/Android/Sdk`); read-write access to `/dev/kvm`
(group `kvm`); unprivileged user namespaces. Installing any of them is the
owner's go: `dev/rig up` names what is missing and the command to run.

**Rules.** The PID namespace is shared with the host: kill only by recorded
pid or the rig's `OPR_RIG_ID` tag, never by name. A rig has an owner process
and a TTL; `dev/rig reap` ends the dead ones and `dev/rig verify-clean`
proves nothing is left. A hidden rig that shows up on the owner's desktop is a
defect: the rig asserts it.

**Without the phone.** `dev/rig up --no-phone` keeps the shell and plugin
(demo mode, screenshots); `--bare` skips the plugin install too.

## Driving the panel

In the rig, `dev/rig ipc <function>` is `"${IPC[@]}" <function>`; the list
below shows the function names.

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
`develop` through pull requests, CI green and checked in the rig. A
release merges `develop` into `main`; the `release` workflow tags it and
publishes the notes from [CHANGELOG.md](../../CHANGELOG.md).
