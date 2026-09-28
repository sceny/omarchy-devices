[Devices](../README.md) › Settings

# Settings

![Settings (demo data)](images/settings.png)

Press `s` or the cog.

- **This device:** its nickname and icon, used in the bar and the tabs.
- **With several devices:** a list of them. Drag one by its grip, or use
  the arrows or Shift+K / Shift+J (the first opens with the panel and
  always shows in the bar); dragging a tab in the panel moves it too.
  Open one to set its nickname, icon, whether it shows in the bar
  (always, only with news, never), whether it has a tab, and its own
  layout, bar and shortcuts; *Defaults for all devices* sets them for
  the rest. Devices asking to pair or in reach show there too.
- **Layout:** show, hide and order the sections. Fold any of them to one
  line; folded shortcuts still work as a row of icons.
- **Bar:** what the pill shows beside the glyph, in order. With
  *Battery only when low* on, the battery stays hidden until it runs low.
- **Shortcuts:** which ones, in what order.
- **Add a device** and **Setup:** the steps on the new device, and the
  KDE Connect checks with fixes.

## What is kept

| What | Where |
|---|---|
| Layout, bar, shortcuts, folds, each device's nickname, icon and settings, their order, the last conversation | Omarchy's `shell.json`, this widget's entry |
| Picture previews, which conversations you opened | `~/.cache/sceny.devices/` |
| Unsent drafts | Memory only |

Change settings in the panel, not in `shell.json` while the shell runs.
