[Devices](../README.md) › Settings

# Settings

Press `s` or the cog. With several devices, they are listed: drag one by
its grip (the first opens with the panel), or open one for its own page.

![Settings: three devices, the defaults, Connection and Add a device (demo data)](images/settings.png)

- **Sections, shortcuts and the bar** are edited on the page itself (`E`).
  *Defaults for all devices* sets them for devices that did not change
  them.
- **Connection** checks this computer; a red dot on the cog means a check
  fails. *Ignore* one you will not fix.
- **Add a device** pairs a new one.

## What is kept

| What | Where |
|---|---|
| Layout, folds, bar, shortcuts, each device's nickname and order | Omarchy's `shell.json` |
| Thumbnails, received files, copies of opened files | `~/.cache/sceny.devices/` |
| Drafts, where the panel was | Memory only |

Change settings in the panel, not in `shell.json` while the shell runs.
