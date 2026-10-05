[Devices](../../README.md) › Internals › Screenshots

# Screenshots

Every picture comes from demo mode, and every one is looked at before it is
committed: a real name, number, photo or contact must never be in one.
Demo mode puts the settings back when it ends (`live`); compare `shell.json`
before and after.

## The README picture

`preview.png` (the marketplace card and the README) is composed by
`tools/listing-image` from two demo shots of a 2560x1440 screen, and a
made-up phone screen for the screen's window (`tools/phone-screen`, which
it runs: generated, so nothing in it is from a real device; its clock is
the shot's):

1. Put the panel's monitor on an empty workspace, and the pointer off the
   panel (`hyprctl dispatch 'hl.dsp.cursor.move({ x = 300, y = 700 })'`).
2. Start the made-up player: `tools/demo-player ~/.cache/sceny.devices/demo/cover.png &`
   (any square image as the cover). The demo's Gallery shows up to eight
   pictures from `~/.cache/sceny.devices/demo/gallery/` (yours, not in the
   repository; no one recognisable, no watermark in the middle, no
   one else's characters).
3. The pointer off the panel *before* `open` (else the cursor shows).
   `demo ""`, `open`, then Shortcuts and Received folded, Apps,
   notifications, Now playing and the Gallery open (`fold <section>`), then
   `grim -o <monitor> main.png`. `messages`, `u` if only the unread ones
   show (the demo keeps your filter), `openThread 9001`, a few seconds,
   then `grim -o <monitor> messages.png`.
4. `tools/listing-image main.png messages.png preview.png`. If the panel's
   size changed, measure the cards again (`cardRect`) and move the labels.
5. Back: `close`, `live`, stop the player (`pkill -f '^python3 tools/demo-player'`:
   anchored, or it matches the shell running it), return to your workspace.

## The screen's pictures

The demo opens no window, so `screen-docked.png` and `screen-turned.png`
put a made-up phone screen (`tools/phone-screen`, portrait and
`2316x1080`) where the plugin docks the real one, on a demo desktop shot
with the panel closed: at `Model.dockRect`'s place and size for the pill
(470x1008 under it, turned 1152x537), framed 2 px in the accent colour as
Hyprland frames a window; then cropped around it and scaled down.

## The user guide's pictures

One topic per picture, cropped to the panel's card alone (`cardRect` gives
it on the desktop): `grim -g "x,y wxh"`. For a section, open it and fold the
others (`fold`). Calls: `demoCall ringing|missed`; several devices:
`demo many`; editing: `edit`; away: `demoAway`; a page of Settings:
`page connection|addDevice`, `settingsScope <device>`. Strip them
(`magick f.png -strip f.png`) into `docs/images/`.
