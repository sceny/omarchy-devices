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
- **[Calls](docs/calls-and-devices.md)**: who is calling, and a missed call
  to call or text back.
- **[Now playing and shortcuts](docs/panel.md)**: the phone's player; ring
  it, send files, the clipboard, a link.
- **[Gallery and files](docs/gallery-and-files.md)**: its newest photos and
  videos, and the files it sent you.
- **[Screen and apps](docs/screen-and-apps.md)**: its screen, and each of
  its [apps](docs/apps.md), in a window here, with your mouse and keyboard.
- **[Several devices](docs/calls-and-devices.md)**: a tab and a chip each.
- **[Setup](docs/getting-started.md)**: one switch per feature does every
  step it can and says the one left to you; [Settings](docs/settings.md)
  lists what needs you, with *Fix all* and *Fix with AI*.

| Key | Action |
|---|---|
| Click / middle-click the pill | Open the panel / messages |
| `j` `k` · Enter | Move · activate (Shift+Enter: an app popped out) |
| `a` | All apps |
| `r` · `x` | Reply to · dismiss a notification |
| `s` · `E` · Esc | Settings · edit the page · back |

## Privacy and safety

- Everything stays between the computer and your phone, over your own
  network. It never sends a text, rings or plays anything on its own.
- The phone's screen needs Wireless debugging, which you turn on and pair
  yourself; only a computer that scanned your code can use it.
- A password only after a card shows what it is for; nothing else runs
  with it. *Fix with AI* opens your own agent, and files an issue only with
  your yes, never with your data.
- Pictures from the phone are opened in a sandbox first: what you see is a
  copy made from their pixels, never the phone's file.
- It keeps only caches, in `~/.cache/sceny.devices/`. Drafts stay in
  memory.

## User guide

[Getting started](docs/getting-started.md) ·
[The panel](docs/panel.md) ·
[Messages](docs/messages.md) ·
[Gallery and files](docs/gallery-and-files.md) ·
[Screen and apps](docs/screen-and-apps.md) ·
[Apps](docs/apps.md) ·
[Calls and devices](docs/calls-and-devices.md) ·
[Settings](docs/settings.md) ·
[Troubleshooting](docs/troubleshooting.md) ·
[What's new](CHANGELOG.md)

## Internals

[How it works](docs/internals/how-it-works.md) ·
[Messages and media](docs/internals/messages-and-media.md) ·
[Development](docs/internals/development.md) ·
[Screenshots](docs/internals/screenshots.md)

MIT, © Sceny. Not affiliated with KDE or Omarchy.
