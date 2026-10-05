[Devices](../README.md) › Troubleshooting

# Troubleshooting

| Symptom | Check |
|---|---|
| The pill is missing | `omarchy restart shell`; errors are in `journalctl --user -t omarchy-shell`. |
| The device shows away | *Reconnect* on its page; Settings → This computer; on Samsung, battery use *Unrestricted*. |
| A feature is missing | Its row under *What it can do*, on the device's page: *Turn on* or *Fix*. |
| No gallery | Its row, or the Gallery's *Try again*: its storage is mounted again, else KDE Connect restarted. |
| A photo is missing | Gallery shows what the phone's gallery does; a folder marked hidden or `.nomedia` is left out. The first look takes up to a minute. |
| No notifications after pairing again | Notifications' *Fix* (with the screen set up), else restart the phone ([#95](https://github.com/sceny/omarchy-devices/issues/95)). |
| *Call* on a notification does nothing | Android blocks it from the background ([#30](https://github.com/sceny/omarchy-devices/issues/30)): open the app in a window from the notification. |
| Anything else | **Fix with AI** beside a problem: your coding agent opens on it. |

## What KDE Connect cannot do

The panel shows what KDE Connect sends. Today it does not:

- send **ongoing** notifications (navigation, timers, downloads);
- pass on an app's **buttons** (*Mark as read*) or the phone's **read
  state**;
- carry **RCS** chats (only SMS and MMS);
- keep each player's **position**: only the playing one has a seek bar;
- on an **iPhone**, share notifications, texts or media: files and the
  clipboard only, while the app is open;
- answer a call, carry its audio, or say when it was **answered or ended**:
  a ringing card gives up after 45 s, and a call you decline shows as
  missed ([#60](https://github.com/sceny/omarchy-devices/issues/60)).

Like the phone, it hides what the phone hides: a paused player Android dropped
([#33](https://github.com/sceny/omarchy-devices/issues/33)), One UI's "1 more notification" ([#52](https://github.com/sceny/omarchy-devices/issues/52)).

What the plugin sees, for the technically minded:
[help for agents](internals/help-for-agents.md).
