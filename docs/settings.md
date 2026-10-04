[Devices](../README.md) › Settings

# Settings

Press `s` or the cog. Settings starts with whether everything works, and
lists what needs you with *Fix all* and *Fix with AI* (your coding agent
opens on it). The main page shows a red line too.

![Settings: one thing to fix with Fix all and Fix with AI, My devices and This computer (demo data)](images/settings.png)

- **My devices:** open one for its page (tabs go to the next); drag by the
  grip to reorder.
- **What it can do**, on its page: a feature per row; its button does
  every step the plugin can and says what is left; its switch turns it off.
- **Sections, shortcuts and the bar** are edited on the page itself (`E`).
  With two or more devices, *For all devices* sets them for devices that
  did not change them.
- **This computer:** KDE Connect, the firewall, the network, the screen's
  and gallery's tools. *Ignore* one you will not fix.
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
