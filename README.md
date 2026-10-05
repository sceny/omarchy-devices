# Devices

Your Android phone or tablet in the [Omarchy](https://omarchy.org) bar:
notifications, texts, calls, media and photos through
[KDE Connect](https://kdeconnect.kde.org/), and its screen and apps in
windows here through [scrcpy](https://github.com/Genymobile/scrcpy),
without picking it up. An iPhone or iPad shares files and the clipboard.

**[Devices on the Omarchy plugins marketplace](https://plugins.omarchy.org/plugin.html?id=sceny.devices)**
· install: `omarchy plugin add https://github.com/sceny/omarchy-devices.git --enable`

![Devices in the Omarchy bar: the pill with its notification bubble, the phone's screen in a window, the panel with its apps, notifications, Now playing and the Gallery, and the messages view with a conversation (demo data)](preview.png)

- **[Notifications](docs/panel.md)**: reply, dismiss, the app's own buttons.
- **[Messages](docs/messages.md)**: every conversation and picture; reply
  or start one from the keyboard.
- **[Calls](docs/calls.md)**: who is calling, and a missed call
  to call or text back.
- **[Now playing and shortcuts](docs/panel.md)**: the phone's player; ring
  it, send files, the clipboard, a link.
- **[Gallery and files](docs/gallery-and-files.md)**: its newest photos and
  videos, and the files it sent you.
- **[Screen and apps](docs/screen-and-apps.md)**: its screen, and each of
  its [apps](docs/apps.md), in a window here, with your mouse and keyboard.
- **[Several devices](docs/panel.md#several-devices)**: a tab and a chip each.

| Key | Action |
|---|---|
| Click / middle-click the pill | Open the panel / messages |
| `j` `k` · Enter | Move · activate (Shift+Enter: an app popped out) |
| `a` | All apps |
| `r` · `x` | Reply to · dismiss a notification |
| `s` · `E` · Esc | Settings · edit the page · back |

## Sets itself up

- **One switch per feature:** it installs what this computer needs, turns
  on KDE Connect's part, allows the phone's permission when it can, and
  says the one step left to you; then it carries on by itself.
- **Repairs by itself:** the gallery after a phone restart, notifications
  dismissed while it was away, the screen once Wireless debugging is back.
  KDE Connect lost the phone? One *Fix* finds it through the screen link.
- **Every step shown first:** a password only after a card says exactly
  what for, and only that runs. Settings lists each problem once, where it
  is.
- **[Fix with AI](docs/security.md#fix-with-ai):** your own coding agent
  opens on what is wrong, with the plugin's guide.

## Security and privacy

Between you and your phone only, on your network: no account, no
telemetry. Pictures from the phone are decoded in a sandbox. The screen
needs Wireless debugging, which you pair and can revoke.
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

MIT, © Sceny. Not affiliated with KDE or Omarchy.
