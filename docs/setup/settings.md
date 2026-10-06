[Devices](../../README.md) › Setup › Settings

# Settings

Press `s` or the cog. With one device, Settings is its page; with several,
your devices, then *For all devices*.

![Settings: what the phone shares with this computer, a switch each (demo data)](../images/settings.png)

- **What it shares with this computer:** a switch per feature the device
  can do; off, it stops sending it ([Your devices](devices.md)).
- **Sections, shortcuts and the bar** are edited on the page itself (`E`).
  With two or more devices, *For all devices* sets them for devices that
  did not change them.
- **Add a device** pairs a new one
  ([Getting started](getting-started.md#the-first-time)).

While everything works, Settings says nothing about it. When something
stops, it leads Settings with *Fix all* and *Fix with AI* (your coding
agent opens on it: [what it may do](../security.md#fix-with-ai)), and the
cog shows a dot. A password is asked only after a card says what for.

## What is kept

| What | Where |
|---|---|
| Layout, folds, bar, shortcuts, each device's nickname and order | Omarchy's `shell.json` |
| Thumbnails, received files, copies of opened files | `~/.cache/sceny.devices/` |
| Drafts, where the panel was | Memory only |

Change settings in the panel, not in `shell.json` while the shell runs.
