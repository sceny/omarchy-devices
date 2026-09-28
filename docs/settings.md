[Devices](../README.md) › Settings

# Settings

![Settings (demo data)](images/settings.png)

Press `s` or the cog.

- **This device:** its nickname and icon, used in the bar and the tabs.
- **With several devices:** a list of them; drag one by its grip (the
  first opens with the panel). Open one for its nickname, icon, place in
  the bar (always, with news, never) and tab. Devices asking to pair or in
  reach show there too.
- **Sections and shortcuts** are edited on the page itself (✎).
  *Defaults for all devices* sets them for devices that did not change
  them.
- **Folds:** any section folds to one line; folded shortcuts still work as
  a row of icons.
- **Bar:** what the pill shows beside the glyph, in order. With
  *Battery only when low* on, the battery stays hidden until it runs low.
- **Add a device** and **Setup:** the steps on the new device, and the
  KDE Connect checks with fixes.

## What is kept

| What | Where |
|---|---|
| Layout, bar, shortcuts, folds, each device's nickname, icon and settings, their order, the last conversation | Omarchy's `shell.json`, this widget's entry |
| Picture previews, which conversations you opened | `~/.cache/sceny.devices/` |
| Unsent drafts | Memory only |

Change settings in the panel, not in `shell.json` while the shell runs.
