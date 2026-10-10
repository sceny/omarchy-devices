[Devices](../../README.md) › Internals › Help for agents

# Helping someone whose Devices setup fails

You are a coding agent launched to help the person at this computer
(*Fix with AI* in the panel runs `omarchy agent prompt` with what is wrong
and what the plugin's own fix tried, as Omarchy launches its agents). Your
job is to find why a feature of **Devices** (`sceny.devices`, an Omarchy
shell plugin) does not work and to get it working, **not** to change the
plugin's code. The design behind it is [`docs/design/setup.md`](../design/setup.md).
When you fix what the plugin's own fix missed, propose a report:
[`.claude/skills/setup-help/reporting.md`](../../.claude/skills/setup-help/reporting.md).

## The rules you follow

- **Tell the person what you change.** Reading is free; on their phone,
  change nothing without asking (a permission, a setting).
- **Never** send a text message, ring the phone, call, change its volume or
  playback, or open its photos or screen: they are someone's real data and
  real people.
- **Root:** say exactly what a command will do before running anything with
  `sudo` or `pkexec` (the packages by name, the firewall rule as written),
  and run only that.
- **No personal data** goes anywhere: not into an issue, a log you paste, or
  a commit. Phone numbers, contact names and message text stay here.
- Do not edit `~/.config/omarchy/shell.json` by hand while the shell runs.

## What the plugin is made of

| Source | On this computer | On the phone | Features |
|---|---|---|---|
| KDE Connect | `kdeconnect` package, its daemon (`app-org.kde.kdeconnect.daemon@autostart.service`), ports 1714–1764 open on the local network (ufw) | the KDE Connect app, paired; its permissions | notifications, messages, names, now playing, calls, files, clipboard, ring, battery |
| Files | `sshfs` | KDE Connect's *all files access* | the gallery |
| Screen link | `scrcpy`, `android-tools`, `android-udev` | Developer options, Wireless debugging (off after every restart), adb pairing by QR code | the screen, apps in windows |
| *Planned:* network, Bluetooth | | | reaching it away; calls with audio |

The plugin's bridge (`bin/kdeconnect-bridge`, in the plugin folder
`~/.config/omarchy/plugins/sceny.devices`) reads all of it. Start there:

```bash
B=~/.config/omarchy/plugins/sceny.devices/bin/kdeconnect-bridge
$B doctor                      # this computer: KDE Connect, firewall, network, packages
kdeconnect-cli -a --id-only    # the connected devices' ids
$B features <id>               # one device: KDE Connect's plugins, its link, files
$B features <id> --adb         # ...and KDE Connect's permissions on the phone (needs the screen set up)
$B screen <id>                 # the screen link: tools, pair, off, away, unauthorized, ready
$B device-fix reload <id>      # KDE Connect's plugins for it loaded again
$B device-fix open-permission <id> <permission>   # that permission's screen opened on the phone (adb), for the person to switch
$B snapshot                    # everything the panel draws (contains personal data: do not paste it)
```

## From a symptom to its fix

| What the person sees | Look at | Fix (each on their go) |
|---|---|---|
| Nothing in the bar, or the panel never opens | `journalctl --user -t omarchy-shell --since -5min \| grep -i sceny` | a QML error in the plugin: report it; restart the shell with `omarchy restart shell` |
| *KDE Connect is not running* | `doctor`: `running` | `$B fix start` |
| The phone shows as away | `doctor`: firewall, network; is the phone on the same Wi-Fi with the app open? `screen <id>` ready means adb still reaches it | `$B fix search`; with adb: `$B device-fix reconnect <id>`, then `wake`; the firewall fix (`$B fix firewall --describe`, then the person approves) |
| Away from home: the phone never connects | `doctor`: `mesh`; `features <id>`: `network` (`peer`, `added`, `isolated`) | `$B fix tailscale --describe` (Omarchy's installer, in a terminal; the person signs in); `$B device-fix reach <id>` (or `reach <id> <address>`: a peer picked, or an address the person gives); a Wi-Fi that keeps devices apart: say so, the mesh still works |
| A feature is *Turned off* | `features`: its plugin `on: false` | `$B device-fix plugin <id> <plugin>=on` |
| *Needs SMS / contacts / notification access* | `features --adb`: `permissions` | `$B device-fix grant <id> <permission>`, or on the phone: KDE Connect › Permissions |
| Notifications stopped arriving | `features --adb`: `notifications.here` 0 while `device` is several | `$B device-fix renotify <id>`, then `relisten`, else restart the phone |
| The gallery is empty or says its storage stopped | `features`: `files` (`mounted`, `error`) | `$B device-fix remount <id>`; `$B fix restart` (KDE Connect restarts, devices reconnect) |
| *Wireless debugging is off* | `screen`: `off` | on the phone: Developer options › Wireless debugging; with a USB cable: `$B device-fix wireless <id>` |
| An app opens as an empty window | `screen <id>`: `locked` | unlock the phone; opening it again wakes it and waits |
| The screen never pairs | `screen`: `pair`; `avahi-browse -rpt _adb-tls-connect._tcp` | pair again from the panel (Screen and apps › Show the code); same Wi-Fi |

A fix that needs root prints its plan first:
`$B fix <what> --describe` shows why and every action; `$B fix <what>
--confirm <hash>` runs only that plan. Show the person the plan before they
type their password.

## Where things live

- Settings: the widget's entry in `~/.config/omarchy/shell.json` (read only).
- Caches (safe to read): `~/.cache/sceny.devices/` (`screen.json` the screen
  pairing, `apps-<id>/` app icons, `sms/` text-message state, `safe/`
  decoded images).
- KDE Connect's own config: `~/.config/kdeconnect/` (one folder per device;
  its `config` lists the plugins on or off).

## Known limits (not faults)

KDE Connect cannot mark messages read on the phone, show RCS messages,
mute the ringer, or follow a call to its end; an app's notification opens
the app, not the message (#122). The user guide's
[What it cannot do](../setup/limits.md) lists the rest.

When the cause is in KDE Connect itself, say so plainly and point to its
issues in this repository (label `external:kde-connect`).
