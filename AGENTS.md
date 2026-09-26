# Devices: an Omarchy plugin

Read this before changing, testing or diagnosing anything here. Two skills carry
the procedures:

- `.claude/skills/develop-panel/`: how to change it and see the change working.
- `.claude/skills/diagnose-panel/`: something looks wrong in the bar or panel, and why.

## What this is

A plugin for the Omarchy shell (Quickshell/QML), id `sceny.devices`: a bar
widget and a panel over the phones and tablets paired with
[KDE Connect](https://kdeconnect.kde.org/). Battery in the bar; in the panel,
shortcuts, the device's media players, its notifications, and a full
text-message view. The README is the user-facing description.

## The boundary: KDE Connect is the source of truth

The plugin holds no device state of its own. Everything comes from the KDE
Connect daemon over D-Bus, through `bin/kdeconnect-bridge`, or from the MPRIS
players KDE Connect exports (media). The only files the plugin writes outside
its folder are caches under `~/.cache/sceny.devices/`.

- **A feature KDE Connect does not offer is not faked.** Ongoing notifications
  never leave the phone; messages cannot be marked read on the phone; RCS is
  not in the SMS store. Say so in the UI or the README instead.
- **The bridge speaks D-Bus; QML speaks to the bridge.** QML has no generic
  D-Bus binding, and every shell D-Bus client (`busctl`, `gdbus`) opens a
  connection per call and cannot listen. One Python process (PyGObject) holds
  one connection and listens.

## Files

| File | Holds |
|---|---|
| `bin/kdeconnect-bridge` | `watch` (device snapshots, event-driven), one-shot action verbs, and `sms` (JSON lines on stdin/stdout) |
| `Service.qml` | the watcher, the action runner, MPRIS players, and `SmsService` |
| `SmsService.qml` | text messages: threads and the open conversation as ListModels, search, what was seen here |
| `Model.js` | pure functions from data to what is drawn; no QML, checked with `node` |
| `BarWidget.qml` | the bar pill |
| `Panel.qml` | the panel: pages, keyboard, settings persistence, the IPC target |
| `SettingsView.qml`, `MessagesView.qml` | the settings page and the two-pane messages view |
| `SetupChecks.qml` | KDE Connect setup checks (`kdeconnect-bridge doctor`) with fixes, and the phone steps |
| `FoldToggle.qml`, `FoldBody.qml` | the folding section header and body, shared by the main page and settings |
| `manifest.json` | id, entry points, settings and their defaults |

## Rules: what the owner decided, so nobody undoes it

Each rule records a fault that was hit or a decision the owner made.

- **Never send a text message while testing.** A test reply goes to a real
  person. Check the send path up to the D-Bus argument types, and leave the
  first real send to the owner.
- **Nothing scripted focuses a text field.** IPC `openThread`, `newMessage`
  and the like never focus the composer: keystrokes meant for another window
  would land in a text, and Enter would send it. Only the user's own click or
  Enter on a thread does.
- **No real personal data in the repository.** No phone numbers, device ids,
  message text or contact names in code, comments, docs, tests or commit
  messages. Examples use 555 numbers; screenshots (`preview.png`, `docs/`)
  come from `demo` mode, which fakes notifications and conversations and
  names the device Pixel 8. The demo picture message reads a local file
  (`~/.cache/sceny.devices/demo/picture.jpg`) that is not in the repository.
- **Media comes from MPRIS, not `mprisremote`.** KDE Connect's `mprisremote`
  object shows one "current" player that went stale when the phone switched
  apps. The exported `org.mpris.MediaPlayer2.kdeconnect.*` players are live.
- **The media card shows the active player only**, like the phone; the others
  are a carousel away (arrows, dots, swipe, drag, `h`/`l`). It opens on the
  active player (playing, else last played) every time.
- **Nothing blinks on a seek.** A seek makes the phone report Paused then
  Playing within about 100 ms. Never rebuild or re-sort the player list on
  play state, never hide the seek bar or flip the play button on a pause
  shorter than the grace (1.5 s for the button, 4 s for the seek bar).
- **The volume slider stays where it was left.** The phone has coarse volume
  steps and reports the step it rounded to; the panel keeps showing the
  user's level while the phone's reports are only its answer to that set.
- **One pace for all motion: `Model.MOTION`** (90 ms out, 220 ms in, OutCubic).
  Nothing animates on its own clock. A page change fades and slides the old
  page out, swaps it at the midpoint, and slides the new one in, while the
  panel's box (the card) animates to the new size at the same beat. The card
  is an item inside a full-screen layer surface, so animating it costs no
  window resize; snapping it was the jump seen mid-transition. The page is
  laid out at the card's final width from the first frame, so it never
  re-flows while the card moves.
- **Size animations are for the user's own changes.** A hidden page has no
  height, so while a page appears or the panel opens, fold and carousel
  animations are off (`settled`); otherwise every section grows from nothing
  as the page slides in.
- **The battery is a detail, not the headline.** Bar pill: glyph and percent.
  Panel: the header icon is the device; the battery is a text-sized glyph
  leading the meta line. The bolt already says charging; do not add the word.
- **UI state persists.** What the user arranged is still there after the
  panel closes, the shell restarts or the machine reboots, stored in this
  widget's `shell.json` entry: folded sections, main page and settings (`collapsed`), section
  visibility and shortcuts, the followed device (`deviceId`), and the
  conversation last open in messages, per device (`lastThread`), and the
  messages unread filter (`unreadOnly`). New UI
  state follows the same path unless it is private: unsent message drafts
  stay in memory (they are message text) and read state lives in the cache.
  Deliberately fresh on every open: the panel opens on its main page, the
  media carousel on the active player, search empty, nothing focused.
- **Settings are written only by the panel**, into this widget's
  `shell.json` entry (`updateEntryInline`), on the user's action (settings
  page, folding a section, choosing a device).
- **Never edit `shell.json` by hand while the shell runs.** Each monitor has
  its own panel holding its own copy of the settings; a hand edit leaves one
  stale, and the next toggle starts from the wrong state. Go through the
  plugin (IPC `fold`, the settings hooks) and read the file back.
- **Results never push the layout.** A click's outcome is a toast floating
  over the panel, or Omarchy's OSD (`omarchy-osd`) when no panel is open.
  Nothing appears in the flow of the panel for a moment and moves the rest.
- **Sections fold with an animation, never a jump:** content grows or
  shrinks (`FoldBody`), the chevron turns, the one-line summary fades, all
  at `Model.MOTION`. Folded Now playing keeps the cover and a play button.
  Every section, on the main page and in settings, uses the same
  `FoldToggle`/`FoldBody`; a new section does too, with its own summary.
- **Devices appear only when there is a choice**: a second paired device,
  one to pair with, or a request. Unpair asks twice.
- **Playback notifications are not notifications here**: from an app with a
  media player now, naming its track or not dismissable. The media card
  already shows them; the phone keeps them out of its list too.
- **Look at the render before saying done.** A measurement is not the layout
  fitting. Use `slowMotion 10` to catch a transition mid-way.
- **After every shell restart, confirm the panel answers over IPC.** A QML
  error takes the whole widget off the bar, and it can be logged after a
  quick log check has already passed (`Keys.onPageUpPressed` does not exist
  and did exactly that).

- **Fixes change the system only on a click.** `fix install` and `fix firewall`
  go through `pkexec` (one password prompt); the firewall rule is limited to
  the local network the default route is on, never opened to everyone.

## Workflow

- **Re-read an issue before starting it**, body and comments
  (`gh issue view <n> --comments`): the owner edits issues to change scope.
- **`main` is what users install** (`omarchy plugin add`/`update` take it).
  It only moves through pull requests: a short-lived branch per change, CI
  green, and the change checked in a running shell (check the branch out in
  the installed clone) before merging. Squash-merge, delete the branch.
- **Releases are tags on `main`** (`vX.Y.Z`), with an entry in
  `CHANGELOG.md` and the same `version` in `manifest.json`, published as a
  GitHub release. The marketplace listing moves to a new release only
  through its *Verify and publish a newer upstream commit* form.
- **The README has three parts, in this order:** for users (what it does,
  screenshots, keyboard, what KDE Connect cannot do), getting started
  (requirements, setup, install, update, remove), under the hood (how it
  works, development). Nothing technical above getting started.

## Never

- Send a text, ring a device, or change the device's volume or playback in a
  test without the owner's go.
- Leave a test's side effect behind: opening an unread thread marks it seen in
  `~/.cache/sceny.devices/sms-seen-<device>.json`; undo it.
- Commit anything read from a real device.
