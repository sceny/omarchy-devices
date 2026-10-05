# Devices

Your phone on your [Omarchy](https://omarchy.org) desktop. Answer its texts
and notifications from your keyboard, see who is calling, play its music,
open its photos, and use its screen and apps in windows here, with your
mouse and keyboard, while the phone stays in your pocket. Android phones
and tablets; an iPhone or iPad shares files and the clipboard.

**[Devices on the Omarchy plugins marketplace](https://plugins.omarchy.org/plugin.html?id=sceny.devices)**
· install: `omarchy plugin add https://github.com/sceny/omarchy-devices.git --enable`

![Devices in the Omarchy bar: the pill with its notification bubble, the phone's screen in a window, the panel with its apps, notifications, Now playing and the Gallery, and the messages view with a conversation (demo data)](preview.png)

- **[Screen and apps](docs/screen-and-apps.md)**: its screen docked by
  the bar in the phone's shape, turning as you turn it; each of its
  [apps](docs/apps.md) in a window of its own, a map beside your browser.
- **[Notifications](docs/panel.md)**: reply, dismiss, press the app's own
  buttons; a chat shows who said what.
- **[Messages](docs/messages.md)**: every conversation, with pictures;
  reply or start one, all from the keyboard.
- **[Calls](docs/calls.md)**: who is calling, by name; a missed call to
  call or text back.
- **[Now playing](docs/panel.md)**: the phone's player here, cover, seek
  and volume; **shortcuts** to ring it, send files, a link or the clipboard.
- **[Gallery and files](docs/gallery-and-files.md)**: its newest photos and
  videos, and the files it sent you, a drag away from any window.
- **[Several devices](docs/panel.md#several-devices)**: a tab and a chip
  each, with its own news.

| Key | Action |
|---|---|
| Click / middle-click the pill | Open the panel / messages |
| `j` `k` · Enter | Move · activate (Shift+Enter: an app popped out) |
| `a` | All apps |
| `r` · `x` | Reply to · dismiss a notification |
| `s` · `E` · Esc | Settings · edit the page · back |

## Sets itself up

- **One switch per feature:** it installs what this computer needs, turns
  on what the phone must share, allows the phone's permission when it can,
  and says the one step left to you; then it carries on by itself.
- **Repairs by itself:** the gallery after a phone restart, notifications
  dismissed while it was away, the screen once the phone is back.
- **Every step shown first:** a password only after a card says exactly
  what for, and only that runs. Settings lists each problem once.
- **[Fix with AI](docs/security.md#fix-with-ai):** your own coding agent
  opens on what is wrong, with the plugin's guide.

## Security and privacy

Between you and your phone only, on your network: no account, no
telemetry. Pictures from the phone are decoded in a sandbox. The screen
needs Wireless debugging, which you pair and can revoke:
[Security and privacy](docs/security.md).

## User guide

**Use it:**
[The panel](docs/panel.md) ·
[Messages](docs/messages.md) ·
[Calls](docs/calls.md) ·
[Gallery and files](docs/gallery-and-files.md) ·
[Screen and apps](docs/screen-and-apps.md) ·
[Apps](docs/apps.md) ·
[What's new](CHANGELOG.md)

**Set it up:**
[Getting started](docs/setup/getting-started.md) ·
[Your devices](docs/setup/devices.md) ·
[Screen and apps](docs/setup/screen-and-apps.md) ·
[Settings](docs/setup/settings.md) ·
[Troubleshooting](docs/setup/troubleshooting.md) ·
[What it cannot do](docs/setup/limits.md) ·
[Security and privacy](docs/security.md)

## Internals

[How it works](docs/internals/how-it-works.md) ·
[Messages and media](docs/internals/messages-and-media.md) ·
[Development](docs/internals/development.md) ·
[Screenshots](docs/internals/screenshots.md)

## Built on

- [KDE Connect](https://kdeconnect.kde.org/): the link to the phone, its
  notifications, texts, calls, media, files and clipboard.
- [scrcpy](https://github.com/Genymobile/scrcpy) and
  [adb](https://developer.android.com/tools/adb): the screen and the apps.
- [Omarchy](https://omarchy.org) and [Quickshell](https://quickshell.org):
  the bar and the panel.
- [glycin](https://gitlab.gnome.org/GNOME/glycin), `ffmpegthumbnailer` and
  `sshfs`: pictures decoded in a sandbox, and the phone's storage here.

The panel installs and sets up what it needs of them.

MIT, © Sceny. Not affiliated with KDE, Genymobile or Omarchy.
