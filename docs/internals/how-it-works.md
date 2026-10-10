[Devices](../../README.md) › Internals › How it works

# How it works

Each source is the truth for its feature: KDE Connect (over D-Bus) for
notifications, messages, calls, media, files and the rest; scrcpy over adb
for the screen and apps; KDE Connect's storage over sshfs for the gallery;
adb for KDE Connect's permissions on the phone. The plugin holds no device
state, and writes nothing outside its folder but caches in
`~/.cache/sceny.devices/`. The design is
[`docs/design/setup.md`](../design/setup.md).

| File | Holds |
|---|---|
| `bin/kdeconnect-bridge` | Python over D-Bus (Gio). `watch` prints a JSON snapshot on start, after every KDE Connect signal (debounced 250 ms) and every 30 s. Action verbs (`ring`, `ping`, `clipboard`, `share`, `text`, `url`, `media`, `dismiss`, `reply`, `action`, `dial`) run one call and print one line. `sms` speaks JSON lines. Setup and the screen: below. |
| `Service.qml` | The watcher, the action runner, waiting on the device's answer, the MPRIS players. |
| `SmsService.qml` | Text messages: threads and the open conversation, search, what was seen here. |
| `Model.js` | Pure functions from data to what is drawn; tested with `node`. |
| `BarWidget.qml`, `Panel.qml` | The pill; the panel, keyboard, settings and IPC. |
| `SettingsView.qml`, `MessagesView.qml`, `SetupChecks.qml` | Settings (the first run's card, diagnostics and Add a device are among its pages), messages, the steps on a new device (and the app's QR code, from `qrencode`, part of Omarchy). |
| `PanelField.qml` | Every text field: Esc steps back the same way everywhere. |
| `CursorGlide.qml`, `CursorStop.qml` | The keyboard cursor, drawn once per page and sliding to where it stops. |
| `ScreenSetup.qml`, `ScreenTurn.qml` | A device's Screen and apps page; the docked screen turning or folding. |
| `AppsView.qml`, `AppTile.qml`, `AppPinRow.qml`, `KeyedApps.qml` | All apps, an app's tile, the pinned row, a row's tiles kept as it changes. |

The bridge exists because the shell has no generic D-Bus binding, and shell
D-Bus clients (`busctl`, `gdbus`) open a connection per call and cannot
listen. How messages and media work is on
[their own page](messages-and-media.md).

## Sources, gateways and setup items

`Model.deviceSetup` works out a device's state from the bridge's reports,
never by hand:

- **Gateways** are how the plugin gets something from a device: KDE
  Connect, Android's permissions, the storage link, the screen link
  (Bluetooth is planned).
- **Setup items** are what a gateway needs, each checked once where it
  lives (this computer or the device): a KDE Connect plugin on, a
  permission, a package, the mount, the link itself. Each has its state
  (ok, missing, broken, off, unavailable, unknown, away) and its remedies.
- **Features** list the items they need, and the ones their own switch
  turns off. A feature's state comes from its items, the same way for all.

A problem is a broken item, shown once with the features it affects: in
Settings' status, the cog's dot and the main page's line. *Fix* and *Fix
all* run an item's remedies (`device-fix`, or `fix` for this computer);
one that needs root is described first (`fix <what> --describe`) and runs
only as shown (`--confirm <hash>`). A device either gateway reaches is
here: with KDE Connect lost and adb still there, its screen and apps keep
working and KDE Connect's link is the one problem.

## The bridge's setup and screen commands

| Command | Does |
|---|---|
| `doctor` | This computer (diagnostics): KDE Connect, the firewall, the network, the mesh, the packages. |
| `features <id> [--adb]` | One device: KDE Connect's plugins, its link, its storage, its network (`network`: meshes, its peer, how it is reached); with adb, its permissions and notification count. |
| `fix <what> [--describe \| --confirm H]` | This computer: ready (the first run: every package and the firewall's rule in one prompt), install, firewall, sshfs, screen (root, as shown), tailscale (Omarchy's installer in its terminal, as shown), start, restart, search. |
| `device-fix <what> <id> [arg]` | One device: plugin, grant, open-permission, remount, reload, renotify, relisten, reconnect, wake, wireless, reach, unreach. |
| `screen <id>` | The screen link: tools, pair, off, away, unauthorized or ready, and whether it is locked. |
| `screen-open <id> [package] [label]` | Its screen docked (or `--tiled`), or an app tiled (or `--pop`); waits for an unlock. |
| `screen-watch`, `screen-pair`, `screen-dock` | The docked screen following turns; pairing by QR code; docking an open window. |
| `screen-sound <id> here\|phone\|both [package] [label]` | Where a window's sound plays: kept per app (`apps-<id>/sound.json`, the cache), and an open window closed and opened again in its place (floating: a rule at its rectangle; tiled: swapped back to its side, measured). scrcpy: nothing (the whole output, the device quiet), `--no-audio`, or `--audio-source=playback --audio-dup`. |
| `screen-volume <id> [package] [label] [--set L] [--mute M]` | Its sound here: the window's own PipeWire stream (by its process, from `pw-dump`), set with `wpctl`; never the device's volume. |
| `apps <id>`, `icons <id>` | Its apps from the cache (from the device once a day); their icons, decoded in a sandbox. |

## The network: from anywhere (#119)

KDE Connect finds a device by broadcast, which stays on one network. The
**Network** gateway gives it a path that does not:

- **A mesh**: Tailscale first (Omarchy installs it), NordVPN Meshnet the
  same way. The bridge reads its peers (`tailscale status --json`,
  `nordvpn meshnet peer list`; no root) and matches the device among them:
  an address KDE Connect or adb reaches it at (adb lists the device's own
  `tun0`) is certain; then the peer picked or matched before
  (`network.json` in the cache); then the same name. Failing those, the
  page lists the mesh's phones to pick from. A wrong address is harmless:
  KDE Connect talks only to a device showing its paired certificate.
- **KDE Connect's custom devices** (its daemon's `customDevices`, a
  writable D-Bus property, which its own settings write) get the peer's
  address, or one the user typed (#8). The address this plugin gave before
  is replaced; the user's own stay.
- **The firewall** (`fix firewall`): KDE Connect's ports from the private
  ranges (10/8, 172.16/12, 192.168/16, as Omarchy opens Sunshine's) and
  `in on tailscale0` / `nordlynx`; only the rules not there yet.
- **A network change** (`ip monitor address`, in `watch`): KDE Connect
  announces itself again (`forceOnNetworkChange`). It asks Qt about the
  network, which needs NetworkManager; Omarchy's network has none.
- **adb**: USB first, then Wi-Fi, then the mesh. Away from the Wi-Fi, mDNS
  does not reach the device: its mesh address at the port Wireless
  debugging had last (kept in `screen.json`). Wireless debugging listens on
  every interface, but Android turns it off off Wi-Fi.
- **Client isolation**: KDE Connect lost while adb reaches the device, and
  its Wi-Fi address on this network does not answer a ping: the page and
  the away card say the Wi-Fi likely keeps its devices apart.

KDE Connect also has a Bluetooth link (*Bluetooth (beta)*, off by default
in its 26.08 build); the plugin does not turn it on.

## Motion

One pace, `Model.MOTION`: out in 90 ms, in over 220 ms, OutCubic. A page
change fades and slides the old page out and the new one in while the card
resizes to fit. `slowMotion 10` over IPC stretches everything, to catch a
frame mid-way.
