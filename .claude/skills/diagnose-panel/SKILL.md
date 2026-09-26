---
name: diagnose-panel
description: Diagnose the Devices Omarchy plugin (sceny.devices) when the bar or panel shows something wrong or nothing at all: the widget missing, the device shown away while it is connected, stale media, notifications or messages not arriving, a blink or a jump. Walks from the symptom to the layer at fault (shell, bridge, KDE Connect daemon, the phone app) with the commands that tell them apart. Read AGENTS.md first.
---

# When something looks wrong

Work down the layers. Each step says which layer is at fault; stop at the first
that disagrees with what the device shows.

## 1. Is the plugin loaded?

```bash
IPC=(timeout 8 qs -p /usr/share/omarchy/shell/shell.qml ipc call sceny.devices)
"${IPC[@]}" status
journalctl --user -t omarchy-shell -n 120 -o cat | grep -F sceny.devices | grep -vE 'IpcHandler|Local plugin'
```

"Target not found", or a QML error in the log, is the shell layer: the widget
is off the bar. "Handler was registered but will not be used" is normal (one
panel per monitor).

## 2. Is the bridge running and reading?

```bash
ps -eo pid,etimes,args | grep '[k]deconnect-bridge'   # one `watch`; `sms` once messages were opened
bin/kdeconnect-bridge snapshot
```

`status` shows `watchError` from the bridge. If `snapshot` disagrees with the
panel, the fault is in QML; if it agrees, go down a layer.

## 3. Is KDE Connect itself right?

```bash
kdeconnect-cli -l                                       # paired and reachable?
systemctl --user status app-org.kde.kdeconnect.daemon@autostart.service
busctl --user tree org.kde.kdeconnect | grep devices     # the device's plugin objects
busctl --user list | grep kdeconnect.mpris               # media players KDE Connect exports
```

"Reachable" false with the phone on the same Wi-Fi: the firewall
(`sudo ufw status | grep 1714`), the phone's battery optimisation (Samsung:
set KDE Connect to *Unrestricted*), or the phone app closed.

## 4. Watch what actually arrives

```bash
dbus-monitor --session "type='signal',sender='org.kde.kdeconnect'" | grep -E 'member=|string'
dbus-monitor --session "type='signal',interface='org.freedesktop.DBus.Properties',path='/org/mpris/MediaPlayer2'"
```

Timestamp the stream while reproducing. It has settled real questions here: a
seek sends Paused then Playing within ~100 ms (the blink), the phone rounds
volume to its steps and KDE Connect answers a set twice (echo, then the step),
and all of a phone's players share one position.

## Known KDE Connect limits (not bugs here)

- Ongoing notifications (navigation, timers, downloads) are dropped by the
  phone app before sending.
- Messages cannot be marked read over KDE Connect.
- RCS chats may be missing (only the SMS/MMS store is read).
- No names without the contacts permission on the phone.
