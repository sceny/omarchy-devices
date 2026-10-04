[Devices](../README.md) › Troubleshooting

# Troubleshooting

| Symptom | Check |
|---|---|
| The pill is missing | `omarchy restart shell`; errors are in `journalctl --user -t omarchy-shell`. |
| The device shows away | *Reconnect* on its page; Settings → This computer; on Samsung, battery use *Unrestricted*. |
| A feature is missing | Settings → its row under *What it can do*: *Turn on* or *Fix* does what it can and says what is left (a permission on the phone). |
| No gallery | Its row, or the Gallery's *Try again*; a storage that stopped answering is mounted again, else *Restart KDE Connect*. |
| A photo is missing | Gallery shows what the phone's gallery does; a folder marked hidden or `.nomedia` is left out. The first look takes up to a minute. |
| No notifications after pairing again | Notifications' *Fix* (with the screen set up), else restart the phone ([#95](https://github.com/sceny/omarchy-devices/issues/95)). |
| *Call* on a notification does nothing | Android blocks it from the background ([#30](https://github.com/sceny/omarchy-devices/issues/30)): open the app in a window from the notification. |
| Anything else | **Fix with AI** beside a problem: your default coding agent opens in a terminal on it. |

## What KDE Connect cannot do

The panel shows what KDE Connect sends. Today it does not:

- send **ongoing** notifications (navigation, timers, downloads);
- pass on an app's **buttons** (*Mark as read*) or the phone's **read
  state**;
- carry **RCS** chats (only SMS and MMS);
- keep each player's **position**: only the playing one has a seek bar.
- on an **iPhone**, share notifications, texts or media: files and the
  clipboard only, while the app is open;
- answer a call, carry its audio, or say when it was **answered or ended**:
  a ringing card gives up after 45 s, and a call you decline shows as
  missed ([#60](https://github.com/sceny/omarchy-devices/issues/60)).

It also forwards things the phone hides: a dropped paused player
([#33](https://github.com/sceny/omarchy-devices/issues/33)), One UI's "1 more notification" ([#52](https://github.com/sceny/omarchy-devices/issues/52)).

## Diagnostics

```bash
~/.config/omarchy/plugins/sceny.devices/bin/kdeconnect-bridge snapshot | jq .   # what the plugin sees
kdeconnect-cli -l                                                              # paired and reachable
timeout 8 qs -p /usr/share/omarchy/shell/shell.qml ipc call sceny.devices status
```
