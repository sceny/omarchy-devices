[Devices](../../README.md) › Internals › How it works

# How it works

KDE Connect is the source of truth: the plugin holds no device state, and
writes nothing outside its folder but caches in `~/.cache/sceny.devices/`.

| File | Holds |
|---|---|
| `bin/kdeconnect-bridge` | Python over D-Bus (Gio). `watch` prints a JSON snapshot on start, after every KDE Connect signal (debounced 250 ms) and every 30 s. Action verbs (`ring`, `ping`, `clipboard`, `share`, `text`, `url`, `media`, `dismiss`, `reply`, `action`, `dial`) run one call and print one line. `sms` speaks JSON lines. |
| `Service.qml` | The watcher, the action runner, waiting on the device's answer, the MPRIS players. |
| `SmsService.qml` | Text messages: threads and the open conversation, search, what was seen here. |
| `Model.js` | Pure functions from data to what is drawn; tested with `node`. |
| `BarWidget.qml`, `Panel.qml` | The pill; the panel, keyboard, settings and IPC. |
| `SettingsView.qml`, `MessagesView.qml`, `SetupChecks.qml` | Settings (Connection is one of its pages), messages, the steps on a new device (and the app's QR code, from `qrencode`, part of Omarchy). |
| `PanelField.qml` | Every text field: Esc steps back the same way everywhere. |
| `CursorGlide.qml`, `CursorStop.qml` | The keyboard cursor, drawn once per page and sliding to where it stops. |

The bridge exists because the shell has no generic D-Bus binding, and shell
D-Bus clients (`busctl`, `gdbus`) open a connection per call and cannot
listen. How messages and media work is on
[their own page](messages-and-media.md).

## Motion

One pace, `Model.MOTION`: out in 90 ms, in over 220 ms, OutCubic. A page
change fades and slides the old page out and the new one in while the card
resizes to fit. `slowMotion 10` over IPC stretches everything, to catch a
frame mid-way.
