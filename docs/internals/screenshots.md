[Devices](../../README.md) › Internals › Screenshots

# Screenshots

Every picture comes from demo mode, and every one is looked at before it is
committed: a real name, number, photo or contact must never be in one.
Demo mode puts the settings back when it ends (`live`); compare `shell.json`
before and after.

## The README picture

`preview.png` (the marketplace card and the README) is composed by
`tools/listing-image` from two demo shots of a 2560x1440 screen:

1. Put the panel's monitor on an empty workspace, and the pointer off the
   panel (`hyprctl dispatch 'hl.dsp.cursor.move({ x = 300, y = 700 })'`).
2. Start the made-up player: `tools/demo-player ~/.cache/sceny.devices/demo/cover.png &`
   (any square image as the cover). The demo's Gallery shows up to eight
   pictures from `~/.cache/sceny.devices/demo/gallery/` (yours, not in the
   repository; none with a person, a watermark in the middle, or someone
   else's characters).
3. The pointer off the panel *before* `open` (else the cursor shows).
   `demo ""`, the Gallery in view (Shortcuts folded, `moveSection`), `open`,
   then `grim -o <monitor> main.png`; `messages`, `openThread 9001`, then
   `grim -o <monitor> messages.png`.
4. `tools/listing-image main.png messages.png preview.png`. If the panel's
   size changed, measure the cards again (`cardRect`) and move the labels.
5. Back: `close`, `live`, stop the player, return to your workspace.

## The user guide's pictures

One topic per picture, cropped to the panel's card alone (`cardRect` gives
it on the desktop): `grim -g "x,y wxh"`. For a section, open it and fold the
others (`fold`). Calls: `demoCall ringing|missed`; several devices:
`demo many`; editing: `edit`; away: `demoAway`; a page of Settings:
`page connection|addDevice`, `settingsScope <device>`. Strip them
(`magick f.png -strip f.png`) into `docs/images/`.
