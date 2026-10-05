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
text-message view. The README and `docs/` are the user-facing description.

## The boundary: each source is the truth for its feature

The plugin holds no device state of its own. Each feature comes from its
source: KDE Connect's daemon over D-Bus (through `bin/kdeconnect-bridge`) or
the MPRIS players it exports (media); the screen and apps from scrcpy over
adb; the gallery from KDE Connect's storage over sshfs; KDE Connect's
permissions on the phone from adb. KDE Connect is one source among them, not
the centre (`docs/design/setup.md`). The only files the plugin writes outside
its folder are caches under `~/.cache/sceny.devices/`.

- **The plugin takes control of what it needs** (the owner's premise): it
  does every setup step it can itself (its packages, KDE Connect's plugins
  per device, the phone's permissions over adb, the mount) and asks only for
  what it cannot, one step at a time, then carries on by itself. KDE
  Connect's daemon and command line are enough: its own app is never needed.
- **A feature no source offers is not faked.** Ongoing notifications never
  leave the phone; messages cannot be marked read on the phone; RCS is not
  in the SMS store. Say so in the UI or the docs (`docs/setup/limits.md`).
- **A KDE Connect fault is handled here when a user meets it:** fixed or
  filtered in the plugin (a dead mount mounted again, a hidden notification
  or player not shown, notifications read again), and still tracked
  upstream: a KDE Connect issue (`external:kde-connect`, for the owner's
  KDE Connect specialist, linking every KDE report, merge request, branch
  and fork) and a plugin issue (`bug`) (`diagnose-panel`, step 5). The
  plugin's handling goes when KDE Connect has its own fix.
- **Second sources, one feature each, by the owner's decision.** The
  device's screen and apps come from scrcpy over adb (`kdeconnect-bridge
  screen*`), which KDE Connect does not offer. Each second source serves
  only its feature; everything else stays KDE Connect.
- **Omarchy only: use what Omarchy provides.** Its commands
  (`omarchy-pkg-add`, `omarchy-launch-or-focus`,
  `omarchy-hyprland-window-pop`, `omarchy-osd`), the packages and services
  it installs (Avahi, `qrencode`, `uwsm-app`, ufw letting mDNS in) and its
  Hyprland (Lua dispatch). Read `/usr/share/omarchy/bin` and
  `/usr/share/omarchy/default/hypr` before writing a helper; no paths for
  other distributions, compositors or an older Hyprland.
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
| `SetupChecks.qml` | the steps on a new device, for Add a device (This computer's rows are its checks, from `kdeconnect-bridge doctor`) |
| `ScreenSetup.qml` | a device's Screen and apps page: where it stands and the steps on it (`Model.screenSetup`, from `kdeconnect-bridge screen`) |
| `AppsView.qml`, `AppTile.qml`, `AppPinRow.qml`, `KeyedApps.qml` | the All apps page, an app's tile, the pinned row, and a row's apps kept as tiles while it changes (the Apps section and the page) |
| `ScreenTurn.qml` | a docked screen turning or folding: the card that turns or morphs to its new place while the window moves under it |
| `QrCode.qml` | every QR code the panel shows: the app's store page, adb's pairing |
| `PairingPopup.qml`, `PairingKey.qml` | the card under the bar when a device asks to pair, and the key as every pairing card draws it |
| `PanelField.qml` | every text field: Esc steps back the same way everywhere |
| `CursorGlide.qml`, `CursorStop.qml` | the keyboard cursor, drawn once per page and sliding; where it stops |
| `FoldToggle.qml`, `FoldBody.qml` | the folding section header and body, shared by the main page and settings |
| `Reorder.qml`, `ReorderShift.qml`, `ReorderGrip.qml` | moving an item in an order (drag, arrows, keyboard): the order being moved, an item's place, a row's grip; used by every order in settings and by the tabs |
| `manifest.json` | id, entry points, settings and their defaults |

## Rules: what the owner decided, so nobody undoes it

Each rule is a decision the owner made or guards against a known fault.
Keep them; change one only with the owner.

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
- **Asking the phone for every conversation is expensive.**
  `requestAllConversationThreads` makes the phone send one packet per
  conversation: the bridge asks at start and after a KDE Connect restart,
  never per user action. When the panel acts on a text-message
  notification, it marks the conversation read itself.
- **Media comes from MPRIS, not `mprisremote`.** KDE Connect's `mprisremote`
  object shows one "current" player, which goes stale when the phone
  switches apps. The exported `org.mpris.MediaPlayer2.kdeconnect.*` players are live.
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
  window resize; snapping it jumps mid-transition. The page is
  laid out at the card's final width from the first frame, so it never
  re-flows while the card moves.
- **Size animations are for the user's own changes.** A hidden page has no
  height, so while a page appears or the panel opens, fold and carousel
  animations are off (`settled`); otherwise every section grows from nothing
  as the page slides in.
- **The battery is a detail, not the headline.** Bar pill: the device glyph
  and the indicators the user picks, in order (`barIndicators`); the owner's
  default is the battery with the *Battery only when low* switch on
  (`batteryLowOnly`: off, battery and % always show) and the notification
  bubble, so a healthy phone with nothing new is the glyph
  alone. Counts and the bubble hide at 0; away, nothing stale shows. Panel:
  the header icon is the device; the battery is a text-sized glyph leading
  the meta line. The bolt already says charging; do not add the word.
- **UI state persists.** What the user arranged is still there after the
  panel closes, the shell restarts or the machine reboots, stored in this
  widget's `shell.json` entry: folded sections, main page and settings (`collapsed`), section
  visibility and order (`sectionOrder`), shortcuts, bar indicators, the
  device order (`deviceOrder`; an old `deviceId` is read as its first
  place), the conversation last open in messages, per device (`lastThread`), and the
  messages unread filter (`unreadOnly`). With two or more devices, a
  device's own changes (its folds, sections, shortcuts, bar indicators)
  go into its profile (`devices`), as do every device's nickname, icon,
  place in the bar and tab; with one device, everything but its nickname
  and icon stays in the flat keys (`docs/design/multi-device.md`). New UI
  state follows the same path unless it is private: unsent message drafts
  stay in memory (they are message text) and read state lives in the cache.
  Opened again within five minutes of closing (`Model.KEEP_PLACE_MS`), the
  panel goes back where it was: the page, the Settings page, the device,
  the scroll, the conversation (a glance at a picture, then back). Later,
  or when it must open elsewhere (setup, another device's chip), it opens
  fresh: on its main page, on the device asked for (a chip, IPC) else the
  first connected one in the order. Always: the media carousel on the
  active player, edit mode off, nothing focused. Where it was is kept in
  memory only, never stored.
- **Settings are written only by the panel**, into this widget's
  `shell.json` entry (`updateEntryInline`), on the user's action (settings
  page, folding a section). Never on upgrade: old entries are read as they
  are (`Model.readSettings`) and new keys appear on the user's next change.
- **Never edit `shell.json` by hand while the shell runs.** Each monitor has
  its own panel holding its own copy of the settings; a hand edit leaves one
  stale, and the next toggle starts from the wrong state. Go through the
  plugin (IPC `fold`, the settings hooks) and read the file back.
- **Results never push the layout.** A click's outcome is a toast floating
  over the panel, or Omarchy's OSD (`omarchy-osd`) when no panel is open.
  Nothing appears in the flow of the panel for a moment and moves the rest.
- **Orders move with a glide, never a jump.** The pill in the bar slides
  its parts to a new order too (a slot per kind, `Model.BAR_PART_KEYS`).
  Every order (devices,
  sections, bar indicators, shortcuts, tabs) moves through `Reorder`:
  while an item moves, the others slide aside to show where it lands; it
  glides in at `Model.MOTION`, and only then is the order written. A drag
  and Shift+K / Shift+J look the same; there are no ↑ ↓ buttons (the grip
  says a row moves). A new order uses
  these components, not a copy.
- **Sections fold with an animation, never a jump:** content grows or
  shrinks (`FoldBody`), the chevron turns, the one-line summary fades, all
  at `Model.MOTION`. Folded Now playing keeps the cover and a play button;
  folded Shortcuts become a row of icons that still work.
  Every section, on the main page and in settings, uses the same
  `FoldToggle`/`FoldBody`; a new section does too, with its own summary.
  Every header is one height (`FoldToggle.headerHeight`), folded or open,
  so the title never moves: what a header shows beside its title (icons, a
  cover, buttons) is at most that tall.
- **Sections move without being rebuilt.** Shortcuts, Now playing and
  Notifications are fixed items placed by `sectionOrder`
  (`sectionsBox`), so a new order keeps the media cards and a half-typed
  text. `stackBefore`/`stackAfter` are not callable from QML; do not reach
  for them. A separator goes between sections, never under the header.
- **A section shows when its switch is on and it has something:** Now
  playing while a player exists, Notifications while there are any (no
  empty state).
- **A device's page is edited in place** (✎, shown only while the pointer
  is on the device's header so the page has no chrome at rest; a
  right-click on the page, KDE's *Enter Edit Mode* idiom; a right-click on
  the device's chip in the bar, one action as Omarchy's own widgets do; or
  `E`): the Bar strip leads (the chip drawn as the bar shows it, a little
  larger, so it reads as the bar; *Battery only when low*, *Calls*; the
  real pill is the preview), every
  section becomes a bar with its grip and switch, every shortcut shows
  (drag the chosen ones, click to add or take away), and changes show at once (page and pill);
  ✓ Done or `E` keeps them and Esc puts back what was there when it began. It edits the viewed device's profile (with one device, the
  flat keys), and is off on every open. Settings keeps only what has no
  place on the page (nickname, icon, place in the bar, the device list);
  *For all devices* keeps the sections, shortcuts and bar,
  since the defaults have no page of their own. There is no Devices section: tabs switch devices, the
  pairing card answers requests, and Settings' device list pairs, orders
  and unpairs (Unpair asks twice).
- **Settings has one shape whatever the number of devices**
  (`docs/design/setup.md`, section 6): the status first (*Everything
  works*, or each problem once, its line opening the page that fixes it,
  with *Fix all* and *Fix with AI*), MY DEVICES (every device, the one in
  view too, asking to pair, Add a device), *For all devices* (two or more
  devices only: with one, its layout is the defaults), This computer.
  Folds go one level deep; anything deeper is a page, with its back arrow.
- **Each device's settings are its own** (`docs/design/multi-device.md`):
  a device's page (tabs to the others' pages) edits its nickname, icon,
  and with two or more devices its place in the bar, tab, and any group
  it changes (its row says *Its own*, with *use the defaults*); *For all devices*
  edits the flat keys. Identity (nickname, icon, bar, tab) is never
  inherited. Moving a device writes down how each one shows in the bar,
  so moving never changes it.
- **Features, gateways and setup items are three things**
  (`docs/design/setup.md` section 4, #128): a feature is what the user
  gets; a gateway is how the plugin gets it (KDE Connect, Android's
  permissions, the storage link, the screen link; Bluetooth planned); a
  setup item is what a gateway needs, checked once where it lives (this
  computer or the device). Features list the items they need
  (`Model.FEATURES` `needs`) and the ones their switch turns off, only
  their own (`switch`); every state comes from the items
  (`Model.deviceSetup`). A new source is a gateway with its items, never a
  branch for one feature.
- **A device is here by any gateway.** KDE Connect away while the screen
  link reaches it is not *away*: its screen, apps and the shortcuts that
  need no KDE Connect stay on the main page, and KDE Connect's link is one
  problem whose fix uses what adb knows (`device-fix reconnect`: KDE
  Connect pointed at the device's address, kept with the user's own custom
  devices; else `wake`: KDE Connect on the device let run in the
  background and opened). The away card shows only when no gateway reaches
  it.
- **One switch gets a feature working.** Turning a feature on runs every
  step the plugin can, across its gateways, this computer's packages
  first (one password card for them); it stops only at a step the user
  must do, waits for it where it can be seen, and then carries on by
  itself. A step that needs a page of its own (the screen link's pairing)
  opens that page.
- **A problem shows once, where its cause is**, and is counted the same
  everywhere (`Model.settingsProblems`): this computer's failing checks
  (not optional, not ignored) and connected devices' broken items (they
  worked and stopped), each once with the features it affects (none
  turned off), and fixes that did not work. Settings' status lists them;
  the gear's dot and a line at the top of the main page (folding in)
  count them. The main page's line closes (✕): the problems it showed then
  stay out of it (`closedProblems`, written on the close only), a new one
  brings it back; the dot and the status keep every problem. This computer holds only this computer; a package installed
  is all it says of the screen or the gallery. *Fix all* runs what its
  page is about: the status what it lists, This computer its checks, a
  device's page that device.
- **The gallery and received files are read, never kept beyond the cache**
  (two sections, Gallery and Received, each gone while it has nothing).
  The gallery is read from the device's storage (KDE Connect's sftp, which
  needs `sshfs`) only when a panel opens on it, at most every 20 s, as
  Android's media index finds it (no hidden, `.nomedia` or
  `Android/data`/`obb` folders; the folder is the album); a failed mount
  is asked for again only after 10 minutes or on *Try again*. Its
  thumbnails, folder listings (`media-dirs.json`), the copies a click
  opens (`open/`, 2 GB at most) and the list of received files
  (`received-<device>.json`, from `shareReceived`) live in
  `~/.cache/sceny.devices/`, never in `shell.json`. A received entry goes
  when dismissed or when its file is gone. A check never opens a real
  phone's photos: use the demo.
- **An image from the device is decoded only in a sandbox, never by the
  shell.** Gallery thumbnails, notification icons, a track's art, a
  picture message's preview and a received picture are decoded through
  GdkPixbuf (glycin: bubblewrap and a syscall filter per decode); a
  video's frame comes from `ffmpegthumbnailer` in our own bubblewrap (no
  network, no home, that one file read-only, limits on memory, time and
  output). The shell loads only images the bridge wrote from the decoded
  pixels (`safe/`, Gallery thumbnails, `sms/preview_*`); a QML `Image`
  never points at a file the device sent. An app's icon is read from its
  installed package and drawn as SVG by the bridge, then decoded the same
  way (`apps-<device>/`). With no sandbox, there is no
  picture, never an unsandboxed decode. A picture opened full size (a
  gallery tile, a received picture, a picture message's) is a JPEG made
  the same way (`open/`); one that does not decode is not opened. Other
  files open in their app (a click), the user's own choice of app, as in
  Files.
- **One keyboard cursor, drawn once per page.** On the main page and in
  Settings, a row, tile or card holding the cursor carries a `CursorStop`
  and draws no cursor of its own; the page's `CursorGlide` slides there at
  `Model.MOTION` with the keys and lands at once under the pointer, and
  the page glides to keep it in sight (`followCursor`). Messages does the
  same with its lists' highlights. Inline buttons keep their own hover. A
  new row, tile or card the keys reach uses `CursorStop`, not its own
  `hasCursor`.
- **Every text field is a `PanelField`**, so Esc steps back the same way
  everywhere, one thing at a time: what floats over the field
  (suggestions) closes and the text stays; then the field's own step
  (`escapeStep`: `keep` a draft, `clear` a search, `revert` a setting); then the field is
  left and the page's Esc takes over. A field never sets its own
  `Keys.onEscapePressed`; a new field uses `PanelField`, not a copy.
- **Apps are windows of their own, tiled by default** (no setting;
  Shift+Enter or Shift+click opens one as Omarchy's pop-out instead,
  floating and pinned at the top right in the device's shape; its sound
  stays on the device, without a word, while another app plays there,
  `Model.appSound`, since scrcpy takes the device's whole output; a
  locked device is woken and the app opens once it is unlocked, never an
  empty window): one
  virtual display per app, following its window (`--flex-display`), and
  never the device's on-screen keyboard (`--display-ime-policy=hide`):
  typing is this computer's keyboard. All apps shows every app, the
  system's own too (no switch). The section has two labelled rows, each
  hidden while it has nothing: PINNED (`pinnedApps`, a setting; places
  count the apps the device has, so another device's pins stay put) and
  RECENT (`opened.json`, in the cache: usage, never `shell.json`; ✕ or
  `x` takes one out, `app-forget`, until it opens again); All apps leads
  with PINNED, a place to drop even when empty. `AppPinRow` is the pinned
  row everywhere: its order moves through `Reorder` (drag, Shift+H /
  Shift+L), an app dragged in opens a gap where it lands and is pinned
  there, one dragged out is unpinned. The list is read only for a
  device whose screen is set up, from the cache, and from the device at
  most once a day; icons once per app version. A notification opens its
  app (the package is in KDE Connect's id, Android's key), never the
  message itself (#122). Opening a real app in a check is the owner's
  go, as the screen is.
- **Opening a place closes the panel; opening an item keeps it.** An
  album, a file's folder (*Show in Files*) or KDE Connect's app opens a
  window the user goes on in, so the panel closes; a gallery tile or a
  received file opens and the panel stays, to open the next one.
- **Playback notifications are not notifications here**: from an app with a
  media player now, naming its track or not dismissable. The media card
  already shows them; the phone keeps them out of its list too.
- **What the phone hides is hidden here** (KDE Connect forwards it): One
  UI's own "1 more notification" (`isHiddenSummary`), and a player paused
  as long as Android takes to hide it (`PLAYER_HIDE_MS`, 10 minutes; the
  player list still changes only when that is crossed, never on a seek).
  A device that comes back gets its notifications read again while no
  panel is open (`device-fix renotify`), so one dismissed there while its
  cancel was lost goes.
- **Fix with AI, on every problem, always** (a feature's row, a failing
  check, the gallery's error, and the title of *What it can do* for all of
  them, beside *Fix all*): the person's default coding agent, launched
  exactly as Omarchy launches it (`omarchy agent prompt`, its own mode; no
  default yet: `omarchy agent --pick`), named in the tooltip, with the
  problems, what the plugin's own fix tried, and the `setup-help` skill by
  path (as `omarchy agent crash` does). What the agent fixes that our fix
  missed it proposes as an issue (`reporting.md`: Omarchy's rules, nothing
  private, KDE Connect's faults on this repository only). A fix that stops
  at the user's step says it in the row: *Waiting for it…* where it can be
  seen when done, else *Check again*.
- **Look at the render before saying done.** A measurement is not the layout
  fitting. Use `slowMotion 10` to catch a transition mid-way.
- **After every shell restart, confirm the panel answers over IPC.** A QML
  error takes the whole widget off the bar, and it can be logged after a
  quick log check has already passed (an attached handler that does not
  exist, such as `Keys.onPageUpPressed`, does exactly that).

- **What a device can do is on its page** (`Model.FEATURES`,
  `featureRows`, from `kdeconnect-bridge features`): a row per feature, its
  state in one word (On, Set up, Needs attention, Turned off, Not on this
  device, Away), what is missing, one action that runs every step the
  plugin can do (`featurePlan`) and stops at the first only the user can
  do, and a switch where its KDE Connect plugins can be turned off for that
  device. Screen and apps keeps its own page; its switch is the plugin's
  (`screenFeature`, per device like `screenDocked`): off, there is no Apps
  section, no Screen shortcut, no app button on a notification, nothing read
  over adb, its window closes, and nothing about it counts as a problem.
- **A password only for what was shown.** A fix that needs root (packages,
  the firewall) is described first (`fix <what> --describe`: why, every
  package pacman would install, the firewall's rules as written) on a card
  over the panel; only Continue brings the password prompt, and the bridge
  runs only that plan (`--confirm <hash>`, built again and compared). Only
  packages not installed at any version go to pacman, so nothing installed
  is downgraded. A change on the phone (a permission) is a click's too.
- **This computer and Add a device are two Settings pages:** one checks what
  exists, the other makes a new pairing (then goes on to the new device's
  page, what it can do). This computer (`settingsScope` `connection`):
  this computer's checks, *Fix all* (status icon, name, short status,
  one action; *Ignore* stops a check lighting the gear's dot, kept in
  `ignoredChecks`); the panel opens on it while KDE Connect is down. Add a
  device (`addDevice`): requests to pair, the steps on the device, devices
  in reach (it searches while open); the panel opens on it while nothing
  is paired. An away device's page offers
  *Reconnect* in place (a search, `fix search`; it never leaves the
  page), and opening the panel on it searches once a minute at most.
  Last seen comes from the bridge's cache (`last-seen.json`); causes are
  worded as likely, and Samsung advice shows for Samsung devices only.
- **Pairing comes forward, never over the keyboard.** A device asking to
  pair brings `PairingPopup` under the bar (a layer surface with no
  keyboard focus, input only on its card) and glows the first chip;
  the panel never opens by itself, since it takes the keyboard. The
  pop-up is for a device asking only: a pairing started from the panel
  stays on its Add a device card (key, countdown of KDE Connect's 30 s,
  `Model.PAIR_TIMEOUT_S`). The key is drawn by `PairingKey` everywhere,
  as KDE Connect shows it (one word). Pairing actions show their result
  in place (`Model.shownInPlace`): no toast unless they fail.
- **Fixes change the system only on a click.** `fix install`, `fix firewall`,
  `fix sshfs` and `fix screen` go through `pkexec` (one password prompt;
  packages through Omarchy's `omarchy-pkg-add`, with Omarchy's bin on the
  `PATH` pkexec clears); the
  firewall rule is limited to the local network the default route is on,
  never opened to everyone.
- **A feature that needs more than KDE Connect ships its own setup.** A
  package, a setting on the device or a pairing is a step the panel walks
  the user through: a check (This computer's row from `doctor`; optional
  when only that feature needs it, so missing it is never a problem), a fix on
  a click, and the steps on the device, each ticked when it is done. Never
  a manual install in the docs instead. Test the setup on a machine
  without the dependency before installing it, and install it through the
  new fix.
- **Pairing adb is the user's own act.** The panel shows a QR code (Android's
  *Pair device with QR code*, a new name and password each time, two
  minutes); the bridge pairs only with the device that scanned it. Reading
  the state connects only to a device adb already trusts. Opening a real
  device's screen in a check is the owner's go: it shows their data.
- **The screen opens under the bar unless the device's `screenDocked`
  is off** (the page's *Opens under the bar* / *Opens as a window*):
  Omarchy's pop-out (floating, pinned, tagged `pop`, opaque like its
  picture-in-picture) under the device's chip, in the device's own shape
  (its display now, rotation and a foldable's screen included, fitted to
  70% of the screen's height and 45% of its width: `Model.dockRect`,
  `fit_display`). On Screen the card grows into that rectangle at
  `Model.MOTION` and waits there (*Connecting…*, with one tip from
  `Model.SCREEN_TIPS`, a different one each opening: only what is true of
  scrcpy as it opens here, Alt shortcuts since Super belongs to Hyprland);
  the window opens exactly
  there under it (a Hyprland rule set with `hyprctl eval` just before; the
  window inset by Hyprland's border, which is drawn outside it, so window
  and border cover the card) and fades in; the panel then fades out as the
  card, which keeps the phone's shape until it is gone. A failure grows the
  card back. Its window already open: brought forward, no card journey.
  Docking and undocking an open window go by its address, so the panel
  keeps the keyboard.
- **A docked screen follows the device's turns and folds, as Android turns
  its own screen** (`screen-watch`, run by the service, JSON lines;
  `ScreenTurn.qml`, mapped while a docked screen is open). scrcpy runs
  verbose under `stdbuf -oL -eL` (written to a file, its lines were held
  back), its output a log read every 10 ms. Its device side's
  `DisplayMonitor: … -> …` comes before the new picture is sent: a still of
  the window's own last picture (`grim -T`, by the window's toplevel id, so
  it works while hidden) goes out with the `refit` event, the card shows it
  over the window and turns it (the way the device turned, from Android's
  rotation; a half turn upside down) or morphs it (a fold: each picture
  fitted at its own proportions, never zoomed or stretched), softening as
  it moves; the window hides and moves under it. When `Texture: WxH` says
  the new picture came, a still of it (taken again while it is only the old
  picture stretched to the new size) goes out as `picture`. The transition
  is blur to reveal: the old picture blurs at once and stays blurred while
  the new one is on its way (a few hundred ms on a real phone; a sharp
  sideways picture held meanwhile reads as a third state), the new one
  fades in under the blur, laid out for the new shape, then sharpens. Once
  sharp, the window shows under it (`revealed`) and the card fades as one
  layer (an item's opacity applies to each of its
  parts: its background showed through). Stills live in
  `$XDG_RUNTIME_DIR/sceny.devices/` and are removed after the turn; they
  are this computer's own screen pixels, not a file the device sent.
  `Texture` alone starts with the plain card, a frame late. A window the
  user moved or resized stays put and turns in place. The bridge's
  `dock_rect` mirrors `Model.dockRect`: change both, and their shared test
  cases.
- **What the platform does not offer natively is behind a switch marked
  (experimental), off by default.** A screen that opens as a window is tiled
  by Omarchy's layout; with *Fit its tile to it (experimental)*
  (`screenFitTile`), its tile takes the device's width at the tile's
  height, at most half the monitor, the window beside it the rest, when it
  opens and as the device turns (`fit_tile`, `--fit`; the layout moves a
  shared edge from either side, so the change is measured and corrected).
  Alone on its workspace, a tile fills it.
- **Keys the panel tells are this machine's,** read from Hyprland
  (`hyprctl binds`: Omarchy's pop-out and full screen, found by their
  description or command; `bound_keys`), never assumed. An action with no
  key here says *no shortcut*, on the page and in the tips alike.
- **Setting up the screen adds the Screen shortcut, once.** When a
  device's screen first reads ready with a panel open, Screen joins its
  shortcuts (the flat keys with one device, its profile with several) and
  its profile notes `screenShortcut: "added"`, so a removal stays removed.

## Workflow

- **Re-read an issue before starting it**, body and comments
  (`gh issue view <n> --comments`): the owner edits issues to change scope.
- **Two branches.** `main` is what users get: `omarchy plugin add` and
  `omarchy plugin update` install the latest commit of the default branch,
  and the marketplace lists one commit of `main`. `main` moves only at a
  release (*Releasing*); a commit on `main` between releases ships
  unreviewed code to anyone who installs or updates, and shows the listing
  as *Update unverified*. `develop` is where work lands. Keep `main` the
  GitHub default branch.
- **Every change goes into `develop` through a pull request:** a
  short-lived branch from `develop`, `gh pr create --base develop`, CI
  green, the change checked in a running shell (check the branch out in the
  installed clone), squash-merge, delete the branch. `Closes #n` in a pull
  request into `develop` closes nothing (GitHub acts on it only for the
  default branch): close the issue by hand after the merge, with a comment
  naming the pull request.
- **Without a running Omarchy shell** (a cloud session, a machine without
  Omarchy), do the rest (code, tests, CI, the pull request), say in the pull
  request that the change is not checked in a running shell, and leave the
  merge until someone checks it there.
- **Check the freeze before merging anything into `main`**, and whenever
  you look at the open issues. It takes two steps:
  each open `marketplace-review` issue here points to a marketplace issue,
  and the marketplace issue says whether its review is still open:

  ```bash
  gh issue list --label marketplace-review --state open --json number,body \
    --jq '.[] | "\(.number) \(.body | capture("omacom/omarchy-plugin-marketplace#(?<n>[0-9]+)").n)"' |
  while read -r ours theirs; do
    echo "#$ours -> omacom/omarchy-plugin-marketplace#$theirs $(gh issue view "$theirs" \
      --repo omacom/omarchy-plugin-marketplace --json state -q .state)"
  done
  ```

  - `OPEN`: a review is in progress and `main` is frozen.
  - `CLOSED`: the two are out of sync; sync them now. Read the marketplace
    issue's last report (published, or what to fix), comment the outcome
    on our issue, and close it.
  - No output: nothing is under review.
- **Keep the repository apart from the installed copy.** Work in your own
  clone, outside the shell's plugin folder. The plugin folder holds an
  installed copy following `develop`; update it with `git pull`
  (`omarchy plugin update` reads `main` and does not bring `develop`
  changes). To check a branch live, push it, `git switch` to it in the
  installed copy, and switch back to `develop` afterwards.
- **An urgent fix for users** is a branch from `main` with a pull request
  into `main`, only while `main` is not frozen (*Releasing*, step 5);
  afterwards merge `main` into `develop`.
- **Instruction docs state what to do.** AGENTS.md, CLAUDE.md, the skills
  and `docs/internals/` give steps, conditions and rules in the
  present tense; the reason for a rule is a present-tense consequence. How
  something came about goes in commit messages and `CHANGELOG.md`.
- **Docs are for users first, and short.** The README is one screen: what
  it does, the picture, the main keys, privacy, then links to the user guide
  and the internals. User pages (`docs/`) are screenshot-first (demo data
  only), with little text, a breadcrumb back to the README on each page, and
  no history. A feature's page shows the feature; its setup lives in the
  Setup section (`docs/setup/`), and the feature's page links to it,
  never mixing the two. Anything technical goes in `docs/internals/`, linked from the
  README's last section. Cut words before adding them: a page that grows
  past about 250 words is split or trimmed.

## Releasing

When the owner says to release, run every step below to the end without
stopping to ask: the owner approved the whole process, the marketplace
request included. Stop only when a check fails or the freeze check finds
`main` frozen, and report that.

0. **Check the freeze** (*Workflow*). A marketplace issue still open means
   `main` is frozen: say so and release nothing.
1. **Pick the version**: a new feature raises Y (`0.5.0` → `0.6.0`), fixes
   alone raise Z (`0.6.0` → `0.6.1`).
   **Prepare on a branch from `develop`** (`release-X.Y.Z`): turn
   `## Unreleased` in `CHANGELOG.md` (the guide's *What's new*, linked from
   the README) into `## X.Y.Z — YYYY-MM-DD` with *Highlights* (a few lines
   on the big things), *Issues* and *Pull requests without an issue* (each
   linked, with its title), and *Upgrading* when a setting or a default
   changes. Set `"version": "X.Y.Z"` in `manifest.json`. Pull request into
   `develop`, CI green, squash-merge.
2. **Merge `develop` into `main`** through a pull request titled
   *Release X.Y.Z* (`gh pr create --base main --head develop`), CI green,
   merged with a merge commit, never squashed, so both branches keep one
   history. The `release` check on that pull request fails while the
   version in `manifest.json` is already tagged or has no CHANGELOG
   section with entries.
3. **The `release` workflow tags and publishes** when the merge lands on
   `main`: it tags the merge commit `vX.Y.Z`, publishes the release with
   that CHANGELOG section as its notes, and brings `develop` level with
   `main`. Check it ran (`gh run list --workflow release --limit 1`,
   `gh release view vX.Y.Z`). If it failed, do what it does by hand:

   ```bash
   git tag -a vX.Y.Z -m "Devices X.Y.Z" origin/main && git push origin vX.Y.Z
   gh release create vX.Y.Z --title "Devices X.Y.Z" --notes-file notes.md --verify-tag --latest
   git fetch origin && git switch develop && git merge --ff-only origin/main && git push
   ```

4. **Request the marketplace review** (`omacom/omarchy-plugin-marketplace`)
   as soon as the release is published, with the text below as it stands:
   the owner approved it for every release. It is filed from a session,
   not from CI (CI cannot open issues in another repository). The
   *Standard installation* box stays unticked: Devices needs KDE Connect
   set up separately, which is why the marketplace lists it `manual-setup`.
   - Not listed yet: the plugin submission issue form (the marketplace's
     `SUBMISSION.md`).
   - Listed: the *Verify and publish a newer upstream commit* form, with the
     full SHA of the current head of `main`:

     ```bash
     cat > /tmp/devices-verify.md <<EOF
     ### Verification action

     Verify and publish a newer upstream commit

     ### Plugin ID

     sceny.devices

     ### Repository URL

     https://github.com/sceny/omarchy-devices

     ### Target commit

     $(git rev-parse origin/main)

     ### Verification acknowledgment

     - [x] I understand that only the exact target commit can become a verified marketplace snapshot and that verification is not a security audit.

     ### Standard installation acknowledgment

     - [ ] I confirm that this listed root plugin supports the standard Omarchy installation path and does not require manual setup.
     EOF
     gh issue create --repo omacom/omarchy-plugin-marketplace --title "[Verify]: Devices" --body-file /tmp/devices-verify.md
     ```

   Then open the tracking issue here, labelled `marketplace-review`, with
   the marketplace issue and the commit under review in its body:

   ```bash
   gh issue create --label marketplace-review \
     --title "Marketplace review: omacom/omarchy-plugin-marketplace#<n> (vX.Y.Z)" \
     --body "Marketplace: omacom/omarchy-plugin-marketplace#<n>
   Commit under review: $(git rev-parse origin/main)"
   ```

   Status notes (bot reports matched, the maintainer's requests) go on that
   issue as comments, never into commits.

   Then report to the owner: the release link, the marketplace issue, the
   tracking issue, and that `main` is frozen.
5. **Freeze `main` while the marketplace issue is open** (the check is in
   *Workflow*). The marketplace checks, reviews and publishes one exact
   commit, and refuses to publish when `main` moved after its checks. Merge
   nothing into `main` meanwhile; work keeps landing on `develop`. The
   freeze ends when the marketplace closes its issue; the freeze check then
   finds the two out of sync and syncs them (*Workflow*).
6. **If `main` moves during the freeze anyway:** edit the submission issue
   (every edit makes the bots check the current head of `main`; the
   submission form has no commit field), wait until both bot reports
   (validation and security baseline) name the new commit, tell the
   maintainer in a comment which commit is ready and whether the reported
   capabilities changed, and put the new commit on the tracking issue.

## Never

- Send a text, ring a device, or change the device's volume or playback in a
  test without the owner's go.
- Leave a test's side effect behind: opening an unread thread marks it seen in
  `~/.cache/sceny.devices/sms-seen-<device>.json`; undo it.
- Commit anything read from a real device.
