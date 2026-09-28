[Devices](../../README.md) › Internals › Screenshots

# Screenshots

`preview.png` (the marketplace card and the README) is composed by
`tools/listing-image` from two demo shots of a 2560x1440 screen:

1. Move to an empty workspace:
   `hyprctl dispatch 'hl.dsp.focus({ workspace = "9" })'`, and the pointer
   off the panel.
2. Start the made-up player: `tools/demo-player ~/.cache/sceny.devices/demo/cover.png &`
   (any square image as the cover).
3. `demo ""`, `open`, then `grim main.png`; `messages`, `openThread 9001`,
   then `grim messages.png`.
4. `tools/listing-image main.png messages.png preview.png`, and look at every
   pixel before committing.
5. Back: `close`, `live`, stop the player, return to your workspace.
