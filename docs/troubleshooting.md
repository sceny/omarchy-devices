[Devices](../README.md) › Troubleshooting

# Troubleshooting

| Symptom | Check |
|---|---|
| The pill is missing | `omarchy restart shell`; errors are in `journalctl --user -t omarchy-shell`. |
| The device shows away | *Reconnect* on its page; Settings → Connection for this computer; on Samsung, battery use *Unrestricted*. |
| No notifications | Notification access for KDE Connect on the phone. |
| Numbers instead of names | The contacts permission on the phone. |
| No calls | The phone and call log permissions for KDE Connect on the phone. |
| No photos | *Install* sshfs from the Files section; allow storage access in the app. |
| A notification you never see on the phone | KDE Connect forwarded a hidden one (below). |

## What KDE Connect cannot do

The panel shows what KDE Connect sends. Today it does not:

- send **ongoing** notifications (navigation, timers, downloads);
- pass on an app's **buttons** (*Mark as read*) or the phone's **read
  state**;
- carry **RCS** chats (only SMS and MMS);
- keep each player's **position**: only the playing one has a seek bar.
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
