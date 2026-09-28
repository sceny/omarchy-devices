[Devices](../README.md) › Settings

# Settings

![Settings (demo data)](images/settings.png)

Press `s` or the cog.

- **Layout:** show, hide and order the sections. Fold any of them to one
  line; folded shortcuts still work as a row of icons.
- **Bar:** what the pill shows beside the glyph, in order. With
  *Battery only when low* on, the battery stays hidden until it runs low.
- **Shortcuts:** which ones, in what order.
- **Setup:** the KDE Connect checks, with fixes, and the steps on the phone.

## What is kept

| What | Where |
|---|---|
| Layout, bar, shortcuts, folds, the device you follow, the last conversation | Omarchy's `shell.json`, this widget's entry |
| Picture previews, which conversations you opened | `~/.cache/sceny.devices/` |
| Unsent drafts | Memory only |

Change settings in the panel, not in `shell.json` while the shell runs.
