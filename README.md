# Devices

Your phone in the [Omarchy](https://omarchy.org) bar, through
[KDE Connect](https://kdeconnect.kde.org/): texts, notifications and media
without picking it up.

![Devices in the Omarchy bar: the pill with its notification bubble, the panel with shortcuts, Now playing and notifications, and the messages view with a conversation (demo data)](preview.png)

- **Messages:** every conversation, its whole history and picture messages;
  reply or start one from the keyboard.
- **Notifications** with reply and dismiss; a chat shows who said what.
- **Now playing:** the phone's player, seek bar and volume.
- **Shortcuts:** ring it, send files, your clipboard or a link.
- **The bar** shows the device glyph, a bubble for new notifications, and
  the battery when low.

| Key | Action |
|---|---|
| Click / middle-click the pill | Open the panel / messages |
| `j` `k` · Enter | Move · activate |
| `r` · `x` | Reply to · dismiss a notification |
| `s` · Esc | Settings · back |

## Privacy

- Everything goes between the computer and your phone over your own
  network, through KDE Connect. Devices sends nothing anywhere else.
- It keeps only caches, in `~/.cache/sceny.devices/`: picture previews and
  which conversations you opened. Unsent drafts stay in memory.
- It never sends a text or rings the phone on its own.

## User guide

1. [Getting started](docs/getting-started.md)
2. [The panel](docs/panel.md)
3. [Messages](docs/messages.md)
4. [Settings](docs/settings.md)
5. [Troubleshooting](docs/troubleshooting.md): includes what KDE Connect
   cannot do

## Internals

- [How it works](docs/internals/how-it-works.md): the files, the bridge,
  motion
- [Messages and media](docs/internals/messages-and-media.md): history, read
  state, chats, players
- [Development](docs/internals/development.md): tests, demo mode, driving the
  panel, contributing
- [Screenshots](docs/internals/screenshots.md): regenerating the listing image

MIT, © Sceny. Not affiliated with KDE or Omarchy.
