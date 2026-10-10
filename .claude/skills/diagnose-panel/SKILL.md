---
name: diagnose-panel
description: Diagnose the Devices Omarchy plugin (sceny.devices) when the bar or panel shows something wrong or nothing at all: the widget missing, the device shown away while it is connected, stale media, notifications or messages not arriving, a blink or a jump. Walks from the symptom to the layer at fault (shell, bridge, KDE Connect daemon, the phone app) with the commands that tell them apart. Read AGENTS.md first.
---

# When something looks wrong

Work down the layers. Each step says which layer is at fault; stop at the first
that disagrees with what the device shows.

**Reproduce it in the rig first** (`dev/rig up`, `docs/internals/development.md`):
the commands below run there with `dev/rig exec -- <command>` (the rig's
session bus, adb server and display) and `dev/rig ipc <function>` for the
panel's IPC, against the rig's emulator (`dev/rig phone ...` makes the
notification, text, call or battery change in question). Everything the
owner's machine adds (a real phone, a firewall, Samsung's battery
optimisation) is asked of the owner, never run against their desktop, daemon
or phone by an agent. A fault that does not reproduce in the rig is a fact
about their setup: say so and ask.

## 1. Is the plugin loaded?

```bash
IPC=(dev/rig ipc)
"${IPC[@]}" status
dev/rig logs shell | grep -F sceny.devices | grep -vE 'IpcHandler|Local plugin'
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
dbus-monitor --session "type='signal',member='NameOwnerChanged',arg0='org.kde.kdeconnect'"   # KDE Connect restarts
```

Match `NameOwnerChanged` without `sender='org.freedesktop.DBus'`: with
dbus-broker, a monitor given that sender receives none of them (a normal
`Gio` subscription with that sender does).

Timestamp the stream while reproducing. It has settled real questions here: a
seek sends Paused then Playing within ~100 ms (the blink), the phone rounds
volume to its steps and KDE Connect answers a set twice (echo, then the step),
and all of a phone's players share one position.

## 5. When KDE Connect is at fault

The panel agrees with KDE Connect, and KDE Connect disagrees with the phone.
The fault is KDE Connect's, and the plugin does not work around it: the
owner's KDE Connect specialist fixes it at the source. A suspected KDE
Connect fault gets two issues here, so the plugin side and the KDE Connect
side are tracked apart.

1. **Rule out stale state on the desktop.** Ask the phone again and compare:
   `requestPlayerList` on the device's `mprisremote` object for media, or a
   reconnect for everything else. An answer that still disagrees with the
   phone is the phone app's; one that corrects itself is the desktop
   daemon's.
2. **Find the cause in the source.** Shallow-clone the side at fault into
   the scratchpad
   ([kdeconnect-android](https://invent.kde.org/network/kdeconnect-android)
   or [kdeconnect-kde](https://invent.kde.org/network/kdeconnect-kde)) and
   find the code that produces what you saw. Note the file and the commit.
3. **Ask the owner what the phone shows** when the evidence cannot tell
   (a hidden player, a notification only the shade has).
4. **File the KDE Connect issue**, labelled `external:kde-connect`: what
   KDE Connect does, the evidence (the D-Bus calls and what they returned,
   the source file at its commit), where the fix belongs, and a
   *KDE Connect work* section. That section lists every KDE bug report,
   merge request, branch and fork on the KDE Connect side that we create
   or follow; add each one as it appears. #35 is the model.
5. **File the plugin issue**, labelled `bug`: what the user sees, why (one
   line, pointing to the KDE Connect issue), and when it closes (a KDE
   Connect release with the fix, checked in the panel). Mark it blocked by
   the KDE Connect issue. #33 is the model.

   ```bash
   gh issue create --label external:kde-connect --title "KDE Connect: <what it does>" --body-file <scratchpad>/kde.md
   gh issue create --label bug --title "<what the user sees>" --body-file <scratchpad>/plugin.md
   gh api -X POST repos/sceny/omarchy-devices/issues/<plugin>/dependencies/blocked_by \
     -F issue_id="$(gh api repos/sceny/omarchy-devices/issues/<kde> -q .id)"
   ```

   No real data in either: no app, track, contact or message names from
   the device.
6. **Add it to the list below** with the plugin issue's number, so the next
   diagnosis stops here. Change the plugin only when the owner asks for a
   workaround.

## Known KDE Connect limits (not bugs here)

- Ongoing notifications (navigation, timers, downloads) are dropped by the
  phone app before sending.
- App buttons (*Mark as read*, …) and read state from the phone need a KDE
  Connect that passes them on; no release does yet (#29). Buttons that open
  a screen on the phone (*Call*) may do nothing (#30).
- A notification dismissed on the phone can stay if its one cancel packet
  is lost: under investigation in #4.
- A paused player the phone has hidden (Android hides one after about
  10 minutes) stays in Now playing: the phone app forwards every open media
  session (#33).
- A System UI notification reading "1 more notification" shows while the
  phone shows nothing: One UI's hidden summary, forwarded by the phone
  app (#52).
- A call's answer or end never reaches the panel, nor does a ringer mute:
  the telephony plugin signals only ringing and missed on D-Bus (#60, #61).
  A declined call arrives as missed.
- After the computer unpairs a connected phone and it pairs again, the
  phone may send no notifications until it restarts (#95). A pairing
  started or ended on the phone does not do this.
- RCS chats may be missing (only the SMS/MMS store is read).
- No names without the contacts permission on the phone.
