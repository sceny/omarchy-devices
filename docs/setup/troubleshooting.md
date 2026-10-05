[Devices](../../README.md) › Setup › Troubleshooting

# Troubleshooting

| Symptom | Check |
|---|---|
| The pill is missing | `omarchy restart shell`; errors are in `journalctl --user -t omarchy-shell`. |
| The device shows away | *Reconnect* on its page; Settings → This computer; on Samsung, battery use *Unrestricted*. *Screen and apps only*: Settings' *Fix* reconnects KDE Connect. |
| A feature is missing | Its row under *What it can do*, on the device's page: *Turn on* or *Fix*. |
| No gallery | Its row, or the Gallery's *Try again*: its storage is mounted again, else KDE Connect restarted. |
| A photo is missing | Gallery shows what the phone's gallery does; a folder marked hidden or `.nomedia` is left out. The first look takes up to a minute. |
| No notifications after pairing again | Notifications' *Fix* (with the screen set up), else restart the phone ([#95](https://github.com/sceny/omarchy-devices/issues/95)). |
| *Call* on a notification does nothing | Android blocks it from the background ([#30](https://github.com/sceny/omarchy-devices/issues/30)): open the app in a window from the notification. |
| Anything else | **Fix with AI** beside a problem: your coding agent opens on it. |

## Away

When a device is not in reach, its page says where it was last seen and
offers *Reconnect*.

![An away device with Reconnect (demo data)](../images/away.png)

If KDE Connect lost it but its screen still opens, it is not away: the
panel keeps its screen and apps (*Screen and apps only*), and Settings
lists KDE Connect with a *Fix* that points KDE Connect at the phone's
address on the network.

What KDE Connect cannot do (ongoing notifications, RCS, answering calls…): [What it cannot do](limits.md).

What the plugin sees, for the technically minded:
[help for agents](../internals/help-for-agents.md).
