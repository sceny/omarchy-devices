[Devices](../README.md) › Settings

# Settings

Press `s` or the cog. With several devices, they are listed: drag one by
its grip (the first opens with the panel), or open one for its own page.

![Settings: what the device can do, This computer and Add a device (demo data)](images/settings.png)

- **What it can do:** a row per feature, *On* or what it still needs. Its
  button does every step the plugin can (turns on KDE Connect's part,
  allows a permission on the phone, installs a package) and tells you the
  one left to you. The switch turns a feature off for that device. When
  something is wrong, its title says so, with *Fix all* and *Fix with AI*
  (your default coding agent opens on it).
- **Sections, shortcuts and the bar** are edited on the page itself (`E`).
  *Defaults for all devices* sets them for devices that did not change
  them.
- **This computer** checks KDE Connect, the firewall and the network, with
  *Fix what I can*. A red dot on the cog means something needs you;
  *Ignore* one you will not fix.
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
