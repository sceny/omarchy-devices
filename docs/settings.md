[Devices](../README.md) › Settings

# Settings

Press `s` or the cog. Settings starts with whether everything works; when
something needs you, each problem is listed with *Fix all* and *Fix with
AI* (your default coding agent opens on it). The main page shows a red
line too.

![Settings: the status, My devices and This computer (demo data)](images/settings.png)

- **My devices:** open one for its own page (tabs go to the next). Drag one
  by its grip to reorder (the first opens with the panel).
- **What it can do**, on a device's page: a row per feature, *On* or what
  it still needs. Its button does every step the plugin can and tells you
  the one left to you. The switch turns a feature off for that device.
- **Sections, shortcuts and the bar** are edited on the page itself (`E`).
  With two or more devices, *For all devices* sets them for devices that
  did not change them.
- **This computer** checks KDE Connect, the firewall, the network and the
  tools the screen and the gallery need, with *Fix all*. *Ignore* one you
  will not fix.
- **Add a device** pairs a new one, then shows what it can do.
- **A password** is asked only after a card says what for: the packages by
  name, the firewall rule as written. Nothing else runs with it.

## What is kept

| What | Where |
|---|---|
| Layout, folds, bar, shortcuts, each device's nickname and order | Omarchy's `shell.json` |
| Thumbnails, received files, copies of opened files | `~/.cache/sceny.devices/` |
| Drafts, where the panel was | Memory only |

Change settings in the panel, not in `shell.json` while the shell runs.
