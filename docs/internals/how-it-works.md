[Devices](../../README.md) › Internals › How it works

# How it works

KDE Connect is the source of truth: the plugin holds no device state, and
writes nothing outside its folder but caches in `~/.cache/sceny.devices/`.

| File | Holds |
|---|---|
| `bin/kdeconnect-bridge` | Python over D-Bus (Gio). `watch` prints a JSON snapshot on start, after every KDE Connect signal (debounced 250 ms) and every 30 s. Action verbs (`ring`, `ping`, `clipboard`, `share`, `text`, `url`, `media`, `dismiss`, `reply`, `action`) run one call and print one line. `sms` speaks JSON lines. |
| `Service.qml` | The watcher, the action runner, waiting on the device's answer, the MPRIS players. |
| `SmsService.qml` | Text messages: threads and the open conversation, search, what was seen here. |
| `Model.js` | Pure functions from data to what is drawn; tested with `node`. |
| `BarWidget.qml`, `Panel.qml` | The pill; the panel, keyboard, settings and IPC. |
| `SettingsView.qml`, `MessagesView.qml`, `SetupChecks.qml` | Settings, messages, the setup checks. |

The bridge exists because the shell has no generic D-Bus binding, and shell
D-Bus clients (`busctl`, `gdbus`) open a connection per call and cannot
listen.

## Messages

`kdeconnect-bridge sms <device>` holds one connection to KDE Connect's
`conversations` interface. Commands on stdin (`load`, `reply`, `send`,
`attachment`, `refresh`), events on stdout (`threads`, `thread`, `messages`,
`message`, `attachment`, `contacts`, `sent`, `error`); the protocol is at
the top of the bridge's `sms` section.

- History comes in pages. A page is complete when full, when KDE Connect
  answers the request with `conversationLoaded`, or when the burst goes
  quiet for 0.8 s. That count is how many messages KDE Connect holds, so it
  is trusted only as the answer to a page asked for.
- KDE Connect cannot mark messages read. A thread is unread when the phone
  says so and has a message newer than what was opened here
  (`sms-seen-<device>.json`).
- Chat notifications arrive as markup KDE Connect builds (`<b>sender</b>`,
  `<br/>`); the bridge splits that fixed format into plain pairs and the
  panel shows only plain text.
- Nothing scripted focuses the composer: keystrokes meant for another window
  must never become a sent text.

## Media

KDE Connect exports each phone player as
`org.mpris.MediaPlayer2.kdeconnect.mpris_*`, which the shell tracks live.
All of a phone's players report one position, so only the playing card
shows a seek bar. The player list changes only when a player appears or
goes: a seek reports "paused" for a moment, and nothing blinks for it.

## Motion

One pace, `Model.MOTION`: out in 90 ms, in over 220 ms, OutCubic. A page
change fades and slides the old page out and the new one in while the card
resizes to fit. `slowMotion 10` over IPC stretches everything, to catch a
frame mid-way.
