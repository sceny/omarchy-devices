[Devices](README.md) › What's new

# What's new

Each version, newest first, grouped by what it touches. `omarchy plugin
update sceny.devices` brings the latest; each is a tag (`vX.Y.Z`) and a
GitHub release with these notes.

## Unreleased

### Highlights

- **A conversation loads whole when a message arrives as it opens**: a live
  message for the open conversation moved the loaded count on before the
  history page came, and the page was then taken for another request and
  dropped, leaving only the newest message until the conversation was left
  and opened again. The page is now matched with what was asked.
- **Dismiss all says one thing when some stay**: when the phone ignored
  several notifications, each row raised its own "did not dismiss it" line;
  the press now says once how many stayed, and a single row's X keeps its
  own line ([#287](https://github.com/sceny/omarchy-devices/issues/287)).
- **A message notification opens its own conversation**: a sender whose
  name this computer does not know ("Name (Alert)"), or a short code that
  sits inside a longer number, could open another conversation, or the one
  left open before. The notification now finds its conversation by name,
  then by the exact number, then by the message itself, and opens none when
  it cannot tell: the list, searched for the sender.
- **The call button in a conversation shows only for a number you can
  dial**: a service's short code or a sender's name no longer gets one
  ([#335](https://github.com/sceny/omarchy-devices/issues/335)).
- **A media session is not a notification**: when KDE Connect does not
  export an app's player, its playback notification (Previous, Play, Next,
  not dismissable) showed in Notifications with no Now playing beside it.
  It is hidden by its shape, as the phone keeps it in its media area
  ([#350](https://github.com/sceny/omarchy-devices/issues/350)).
- **Passwords never leave with your own auto-share**: when you turned
  automatic sharing on for a device in KDE Connect, the copies a password
  manager marks still went to it. The plugin now also writes
  `sendPassword=false` when you set none, and keeps a `sendPassword=true`
  you wrote ([#286](https://github.com/sceny/omarchy-devices/issues/286)).
- **A call pauses every local player but the phone's**: the skip matched
  `kdeconnect` anywhere in a player's name, so a local app whose name merely
  contained it kept playing during a call. It now matches the phone players'
  exported prefix only
  ([#267](https://github.com/sceny/omarchy-devices/issues/267)).
- **Nothing scripted focuses a text field**: the scripted press of the Send
  text shortcut, the Nickname and From anywhere address rows, and a call
  card's Text back each put the cursor in a field; now only your own click
  or Enter does. A new check follows every IPC function through what it
  calls and fails on a focus without that gate
  ([#308](https://github.com/sceny/omarchy-devices/issues/308)).
- **The Contacts and Messages pages keep their key hints in view**: with
  the ask or a problem line above the page, it now takes the card's
  remaining height instead of a fixed 600 px, so the hints show on a 720 px
  screen without scrolling
  ([#332](https://github.com/sceny/omarchy-devices/issues/332),
  [#339](https://github.com/sceny/omarchy-devices/issues/339)).
- **The keyboard cursor reaches Unpair, Reset shortcuts and a pairing
  request**: in a device's Settings and in *For all devices*, `j` on the last
  row now shows the cursor there and scrolls the page to it
  ([#324](https://github.com/sceny/omarchy-devices/issues/324)).
- **The keyboard reaches the last row with the pointer at rest**: on the
  main page, Settings and All apps, a page that scrolled under a still
  pointer let the row beneath it take the cursor, so `j` looped among the
  upper rows and never reached Keys. A hover now moves the cursor only when
  the pointer moves ([#254](https://github.com/sceny/omarchy-devices/issues/254)).
- **New message suggestions follow the pointer, not the list**: typing a
  name changes the suggestions under a still pointer, and the row beneath it
  no longer takes the cursor from the keys. The check that guards every
  hover now reads every QML file and handlers of any layout
  ([#325](https://github.com/sceny/omarchy-devices/issues/325)).
- **A resting pointer never takes the cursor in Messages or Contacts**,
  whatever it touched last: the lists now read the panel's one pointer
  position instead of keeping their own
  ([#327](https://github.com/sceny/omarchy-devices/issues/327)).
- **A resting pointer never takes the cursor on the main page or in
  Settings either**: a pointer move over a header or a gap was kept until
  the next row asked, so a fold that moved content under a still pointer
  let that row take the cursor. A hover now runs only when the very event
  that brought it is a move
  ([#330](https://github.com/sceny/omarchy-devices/issues/330)).
- **Calls here** ([#59](https://github.com/sceny/omarchy-devices/issues/59)):
  answer and make calls with the audio on this computer, over Bluetooth. The
  card follows a call to its end: microphone, keypad, volume, a second call
  held or joined, music here paused meanwhile. Call back, or call from a
  conversation.
- **Contacts**: the phone's address book in the panel, two panes like
  Messages: a searchable list with each person's photo, and the full card.
  *Message* starts a text, *Call* opens the dialer on the phone, an email, an
  address and a website open in their app. Texts take their names from the
  same cards.
- **From anywhere**: the phone in the panel away from home, through Tailscale
  or NordVPN Meshnet, or an address you type. Its page says how it is
  connected now.
- **Sound, per window** ([#129](https://github.com/sceny/omarchy-devices/issues/129)):
  an open app and the Screen shortcut say where their sound plays (Here, On
  the phone, Both), with its volume here.
- **Setup that gets out of the way**: Settings shows no plumbing. With one
  device it is that device's page: what it shares with this computer, a
  switch each. What a feature needs is asked where you use it. The first run
  is one card: one password installs everything, starts KDE Connect and goes
  on to Add a device.
- **One card for a problem, and it closes**: whatever failed shows in one
  place under the device header (*Fix*, *Details*, *Fix with AI*), ✕ folds it
  away until something new breaks, and a red dot stays on the gear, section,
  shortcut and page it affects.
- **Back goes where you came from**: the pages form one stack. Esc and the
  back arrow return to the page you left, and a **Home** button (`0`) goes to
  the main page from two pages deep.
- **The panel opens at once**: a click on the chip draws the main page on the
  first frame, with no wait.
- **Private text stays private**: call numbers, keypad tones and contact
  searches no longer go on a command line, and Fix with AI names a device by
  its kind and quotes every detail as data.
- **A hidden test rig** (`dev/rig`): a second shell and a small Android
  emulator paired to a private KDE Connect, so changes are tried without
  touching the desktop or a real phone
  ([development](docs/internals/development.md#the-test-rig)).
- **Contacts asks for contacts, Messages does not**: the permission to read
  contacts is asked on the Contacts page, with *Allow* when the plugin can
  grant it, instead of on the Messages page where texts were the errand.
  Messages is whole with numbers instead of names; if contacts worked and
  stopped, both pages still show that problem. Searching a new message by
  name offers the same *Allow*. A Contacts page with the permission given and
  no cards says so (*No contacts on Pixel 8 yet*) (#272).
- **The on-screen display names nothing a device sent**: with no panel
  open, a result shows in Omarchy's display, whose line any local user can
  read. It now says "Saved to Pictures", "The app is open" or "Ringing the
  device", never a received file's name, an app's label or the device's
  name; the panel's toast keeps the full text.
- **Hardening**: contact fields are capped, and the firewall rules open KDE
  Connect's ports to private ranges only.
- **A missed call offers Calls here**: while it is not set up, the missed-call
  card says *Call back from here* with **Set up**, which
  carries the steps on by itself (a password card first when root is needed,
  Omarchy's Bluetooth to pair the phone, *Connect* when it dropped). *No
  thanks* turns Calls here off. The ringing card is unchanged.
- **More hardening**: the bridge's text commands (ping, text, url, dial)
  take their text on standard input only, and refuse it on the command line.
  A file opened from a device's storage must be a regular file inside that
  storage and within the cache's size limit, and is copied in bounded steps.
  The build's checks for these are stricter, and the text field's selection
  rules are now tested by running the field. Smaller: the conversation list
  finds a thread without scanning, and an album-art decode that cannot start
  no longer holds a slot.
- **Hardening, mesh and files**: a mesh peer is remembered by its id, not its
  name; the screen's stills and the messages folder are private from the start;
  Omarchy's folder from the environment is used only when root owns it; the CI
  actions are pinned to commits and kept current. A contact's value you open
  goes on the opened program's command line, now said in the security page.

### Issues

- [#119](https://github.com/sceny/omarchy-devices/issues/119) Networking: one reliable path to each device, at home and away
- [#8](https://github.com/sceny/omarchy-devices/issues/8) Reach devices over Tailscale or a custom address
- [#59](https://github.com/sceny/omarchy-devices/issues/59) Answer and place calls with the audio on the computer (Bluetooth hands-free)
- [#129](https://github.com/sceny/omarchy-devices/issues/129) Sound: where a device's sound plays, per window, from the plugin
- [#122](https://github.com/sceny/omarchy-devices/issues/122) Notification open: a text message opens its conversation, any other its app; the exact screen inside it needs KDE Connect's help
- [#153](https://github.com/sceny/omarchy-devices/issues/153) Problems: one fixed card that closes, red dots where the effect is, an ask on use
- [#159](https://github.com/sceny/omarchy-devices/issues/159) Settings shows "Everything works" although the rules say it shows nothing while everything works
- [#152](https://github.com/sceny/omarchy-devices/issues/152) Editing a device's page offered the Screen shortcut and the Apps section while Screen and apps was off
- [#160](https://github.com/sceny/omarchy-devices/issues/160) MessagesView: binding loop on a picture message's "picture" property
- [#171](https://github.com/sceny/omarchy-devices/issues/171) Call numbers, keypad tones and contact searches still go on the bridge's command line
- [#172](https://github.com/sceny/omarchy-devices/issues/172) Diagnostics: a failing check with three buttons cuts its name and wraps its detail
- [#175](https://github.com/sceny/omarchy-devices/issues/175) First run: KDE Connect is not started after the install, so the card never goes on to Add a device
- [#176](https://github.com/sceny/omarchy-devices/issues/176) First run: the password card shows two of the seven actions, one cut off mid-line
- [#177](https://github.com/sceny/omarchy-devices/issues/177) Gallery shows a problem on a fresh pairing, before the user has used it
- [#178](https://github.com/sceny/omarchy-devices/issues/178) Gallery keeps saying to allow storage after the plugin has granted it
- [#191](https://github.com/sceny/omarchy-devices/issues/191) Bridge `watch` leaves its `ip -o monitor address` child running when it exits

### Pull requests without an issue

- [#143](https://github.com/sceny/omarchy-devices/pull/143) Contacts: the phone's address book in the panel (with [#144](https://github.com/sceny/omarchy-devices/pull/144), [#145](https://github.com/sceny/omarchy-devices/pull/145), [#146](https://github.com/sceny/omarchy-devices/pull/146), [#147](https://github.com/sceny/omarchy-devices/pull/147): photos, links that open in their app, Google Contacts, round photos)
- [#148](https://github.com/sceny/omarchy-devices/pull/148) Nested navigation: Back returns to where you came from, Home from two deep
- [#149](https://github.com/sceny/omarchy-devices/pull/149) Hidden test rig with a small Android emulator: all development goes into it
- [#151](https://github.com/sceny/omarchy-devices/pull/151) The panel opens at once: draw from what is in memory
- [#142](https://github.com/sceny/omarchy-devices/pull/142) Setup that gets out of the way: asked where you use it, no plumbing in Settings
- [#164](https://github.com/sceny/omarchy-devices/pull/164) dev/loaded-code: check that the shell runs the plugin's files, not the code it read at start
- [#179](https://github.com/sceny/omarchy-devices/pull/179) Rig: a cold computer for the cold-install check
- [#185](https://github.com/sceny/omarchy-devices/pull/185) Fix with AI: fence device-supplied names and details
- [#190](https://github.com/sceny/omarchy-devices/pull/190) Albums row: its edges are two items, not a Repeater's delegates that move away
- [#192](https://github.com/sceny/omarchy-devices/pull/192) dev/soak: the 30-minute resilience soak driver and its media-player fixture
- [#150](https://github.com/sceny/omarchy-devices/pull/150), [#157](https://github.com/sceny/omarchy-devices/pull/157), [#158](https://github.com/sceny/omarchy-devices/pull/158), [#166](https://github.com/sceny/omarchy-devices/pull/166), [#167](https://github.com/sceny/omarchy-devices/pull/167), [#180](https://github.com/sceny/omarchy-devices/pull/180) Development and release docs: install follows `develop`, release procedure, security review, Contacts and Calls limits

### Upgrading

- **The tabs can change order after the upgrade**: a stored `deviceOrder` is
  now honoured, so devices you reordered before show in that order.
- **A firewall problem card can appear after the upgrade**, with *Fix*, when
  the firewall does not let KDE Connect in.
- **The firewall's fix** opens KDE Connect's ports to every private network
  (home, office) and to your mesh, instead of only the network you were on.
  Rules you have stay.
- **This computer** has a *Mesh network* row (optional).
- Nothing else in your settings is rewritten; new keys (`closedProblems`)
  appear on your next change.

## 0.8.5 — 2026-10-14

### Fixes

- An attachment you did not ask for no longer opens: only the attachment you clicked is opened, and a picture is always opened as the copy decoded in the sandbox, whatever name or type the phone gives it (marketplace review omacom/omarchy-plugin-marketplace#10096).
- A gallery photo's copy button now copies the same sandbox-decoded picture that opening it shows, never the phone's file as it came; a picture that cannot be read safely is not copied, and any other file is copied from a copy made here (marketplace review omacom/omarchy-plugin-marketplace#10096).

## 0.8.4 — 2026-10-14

### Fixes

- A paste no longer makes the shell read the clipboard unbounded or wait on it: the text is read when you paste, outside the shell, with a size limit and a deadline, and a slow or failed read inserts nothing (marketplace review omacom/omarchy-plugin-marketplace#10096).
- The shell never takes part in a clipboard transfer: copy, cut, paste and selecting text go through one door that runs the system's clipboard tools outside the shell, with a size limit and a deadline, so a program that never reads what you copied (or never finishes what it pastes) cannot freeze the bar. In a field, Ctrl+C, Ctrl+X, Ctrl+V, Ctrl+A and Shift with the arrow keys work as before, and the mouse still places the cursor and selects (a drag, Shift+click, a word on a double click, all on a triple). A message in a conversation is copied by a double click; it can no longer be selected by dragging. A gallery photo is no longer dragged out of the panel: use its copy button, then paste it where you want it (marketplace review omacom/omarchy-plugin-marketplace#10096; `docs/architecture/001`).

## 0.8.3 — 2026-10-13

### Highlights

- **Text fields never read the clipboard until you paste**: a field is
  built on a text edit, which asks only which formats the clipboard offers
  and reads its text when you paste (Ctrl+V, Shift+Insert). Focusing a
  field, or another program copying while one has the keyboard, makes the
  shell read nothing. Typing, accented characters, Esc's steps, drafts and
  suggestions work as before; Enter stops at the field. A field holds at most
  32767 characters, as before, and a paste is cut to that before it is
  inserted, so a huge paste or a line-broken one is instant instead of
  stopping the shell. Middle-click paste and dropping text onto a field no
  longer insert anything.
- **A window is found by its exact title**: opening the device's screen or
  an app focuses an open window by its address and otherwise starts it
  directly, with each part of the command kept as it is.
- **Clipboard: a copy leaves on your click**: the Clipboard shortcut is the
  only way a copy is sent to a device. The plugin turns KDE Connect's
  automatic sharing off for each paired device that has no choice of its
  own, and leaves a choice you made there alone. `docs/security.md` says so.
- **Call details are kept short**: a caller's name and number are cut to
  the same length as other device text before they are used.

### Issues

- [#137](https://github.com/sceny/omarchy-devices/issues/137) Marketplace review: omacom/omarchy-plugin-marketplace#10096 (a focused text field made the shell read the clipboard's whole text)

## 0.8.2 — 2026-10-11

### Highlights

- **Text fields no longer read the clipboard while they are not in use**: a
  field is editable only while it has the keyboard, so a hidden composer,
  reply or search field no longer makes the shell read whatever another
  program put on the clipboard, however large. Typing, Esc's steps, drafts
  and suggestions work as before.
- **No typed text or clipboard in a log**: the screen window's log keeps only
  the two lines that tell the plugin the phone turned or folded. It is kept in
  memory (`$XDG_RUNTIME_DIR`), readable by you alone, and removed when the
  window closes; logs an earlier version left in the cache are removed.
- **Text from a device is capped**: notifications (title, text, the newest
  100, the newest 50 messages of a conversation), text messages, app names and
  contact files are cut to a size no real device reaches before they reach the
  panel.
- **A track's art is read only from KDE Connect's art cache**, one picture at a
  time per player.
- **The cache folder is yours alone** (`~/.cache/sceny.devices`, mode 0700), and
  the screen's stills no longer fall back to `/tmp` without a runtime folder.

### Issues

- [#170](https://github.com/sceny/omarchy-devices/issues/170) Text fields read the clipboard on every change, before any paste

### Upgrading

- Nothing in your settings changes.

## 0.8.1 — 2026-10-10

### Highlights

- **Private text stays off command lines**: a reply to a notification, a
  text or link sent to the phone, a ping's message and a number to call back
  reach the plugin's helper over stdin, never as command-line arguments,
  which any local process can read. The one-time code for pairing a phone's
  screen link is never on a command line either.

### Issues

- [#162](https://github.com/sceny/omarchy-devices/issues/162) The adb pairing password is on two command lines (qrencode, adb pair)
- [#137](https://github.com/sceny/omarchy-devices/issues/137) Marketplace review of 0.8.0: a notification reply's text was a command-line argument

### Upgrading

- Nothing in your settings changes. The call-back notice no longer repeats
  the number.

## 0.8.0 — 2026-10-05

### Highlights

- **Screen**: the phone's screen on your desktop, docked under its chip in
  the phone's own shape and turning as you turn it, or as a window; your
  mouse and keyboard, the clipboard both ways, files dropped on it. Set up
  from the panel, once.
- **Apps**: each of the phone's apps in a window of its own, tiled with
  the rest, with its icon; pinned and recent rows, All apps with search,
  a notification's app opened in a window; Shift+Enter pops one out.
- **Setup that just works**: a device's page says what it can do, and
  one switch per feature does every step the plugin can, here and on the
  phone, then carries on by itself after the one step left to you. The
  panel installs what the computer is missing; KDE Connect's own app is
  no longer needed.
- **Settings in one shape**: it starts with whether everything works and
  lists each problem once, where its cause is, with *Fix all* and *Fix
  with AI*; My devices, For all devices, This computer. A red line on the
  main page says when something needs you.
- **A password only for what is shown**: a card says why and lists every
  package and firewall rule before the prompt; only that runs.
- **Repairs by itself**: the gallery after a phone restart, notifications
  dismissed while the device was away or gone quiet after pairing again,
  the screen once the phone is back; a device the phone's link lost while
  its screen still answers keeps its screen and apps, and one *Fix* finds
  it again.
- **Fix with AI**: your default coding agent opens on a problem, as
  Omarchy opens it, with the plugin's guide; what it fixes that the
  plugin's fix missed, it offers to report, with nothing private in it.
- **Docs**: one page per feature, a Setup section, Security and privacy.

### Issues

- [#2](https://github.com/sceny/omarchy-devices/issues/2) Screen mirroring with scrcpy
- [#116](https://github.com/sceny/omarchy-devices/issues/116) Phone apps in their own windows
- [#126](https://github.com/sceny/omarchy-devices/issues/126) Setup that just works: one model of sources and features, Settings for it
- [#128](https://github.com/sceny/omarchy-devices/issues/128) Setup items: features from the items they need, sources as modules
- [#121](https://github.com/sceny/omarchy-devices/issues/121) Troubleshooting that fixes itself, for every capability
- [#63](https://github.com/sceny/omarchy-devices/issues/63) Setup checks name the phone permission a feature is missing
- [#101](https://github.com/sceny/omarchy-devices/issues/101) Fix with AI: Omarchy's agent on the plugin's errors
- [#99](https://github.com/sceny/omarchy-devices/issues/99) Photos could not read the phone, and KDE Connect's mount error popped up again and again
- [#4](https://github.com/sceny/omarchy-devices/issues/4) Notifications dismissed on the device stayed in the panel
- [#95](https://github.com/sceny/omarchy-devices/issues/95) No notifications after unpairing from the computer and pairing again
- [#52](https://github.com/sceny/omarchy-devices/issues/52) A hidden System UI "1 more notification" showed in the panel
- [#33](https://github.com/sceny/omarchy-devices/issues/33) Now playing kept a player the phone had hidden
- [#31](https://github.com/sceny/omarchy-devices/issues/31) The messages resync after a KDE Connect restart, checked

### Pull requests without an issue

- [#125](https://github.com/sceny/omarchy-devices/pull/125) Sections: one header height, folds that fade alike; Apps polish
- [#130](https://github.com/sceny/omarchy-devices/pull/130) Docs for 0.8, and found by what it does
- [#132](https://github.com/sceny/omarchy-devices/pull/132) Docs: features for show, setup as its own section, security and privacy
- [#133](https://github.com/sceny/omarchy-devices/pull/133) Docs: features as features; Built on at the README's end

### Upgrading

- **Settings has one shape** with one device or many: the status, My
  devices (your device is in the list; its own settings are on its page),
  For all devices with two or more, This computer (once Connection). The
  KDE Connect settings row is gone. Nothing in your settings is
  rewritten; new keys appear on your next change.
- **Apps** joins your saved order of sections, switched on, and shows
  once a device's screen is set up. **Screen** joins the device's
  shortcuts when its screen is first set up, once.
- **New, per device:** *Opens under the bar* for the screen, an app's
  sound here or on the phone, and the Screen and apps switch; all on in
  the ways they were.
- **New optional packages**, installed from the panel on a click, after a
  card: scrcpy, android-tools and android-udev for the screen and apps;
  sshfs for the gallery.

## 0.7.0 — 2026-10-02

### Highlights

- **Several devices**: a tab and a chip each, and settings for each one.
- **Calls** ring in the bar; a missed call offers to call or text back.
- **Gallery and Received**: the phone's newest photos and videos, and the
  files it sent you.
- **Setup**: checks with fixes, a QR code for the app (Android or iPhone),
  a pairing pop-up with the key, and a demo phone to look around first.
- **Make it yours**: edit the page in place, drag anything to reorder.
- **Keyboard**: one cursor that slides, and messages fully by keyboard.
- **Safety**: every image from the phone is decoded in a sandbox.

### Issues

- [#72](https://github.com/sceny/omarchy-devices/issues/72) Many devices, step 1: profiles, settings read as defaults, chips and attention
- [#73](https://github.com/sceny/omarchy-devices/issues/73) Many devices, step 2: tabs, per-device pages, chips in the pill, the pairing card
- [#74](https://github.com/sceny/omarchy-devices/issues/74) Many devices, step 3: Settings for devices
- [#75](https://github.com/sceny/omarchy-devices/issues/75) Many devices, step 4: the Connection page and Reconnect
- [#58](https://github.com/sceny/omarchy-devices/issues/58) Incoming and missed calls in the bar and the panel
- [#65](https://github.com/sceny/omarchy-devices/issues/65) The phone's newest photos in the panel (Gallery)
- [#37](https://github.com/sceny/omarchy-devices/issues/37) Inbox of files received from the device
- [#81](https://github.com/sceny/omarchy-devices/issues/81) Edit a device's page in place
- [#84](https://github.com/sceny/omarchy-devices/issues/84) The bar joins edit in place
- [#92](https://github.com/sceny/omarchy-devices/issues/92) Pairing: a pop-up and a glow when a device asks to pair
- [#62](https://github.com/sceny/omarchy-devices/issues/62) Preview the panel with a demo phone before setting up
- [#64](https://github.com/sceny/omarchy-devices/issues/64) A QR code to install the phone app
- [#69](https://github.com/sceny/omarchy-devices/issues/69) Find a paired device that is away, and say why when it cannot
- [#105](https://github.com/sceny/omarchy-devices/issues/105) Gallery: decode the phone's files in a sandbox
- [#107](https://github.com/sceny/omarchy-devices/issues/107) Images from the phone decoded by the shell, unsandboxed
- [#100](https://github.com/sceny/omarchy-devices/issues/100) Gallery asked for the mount on every open after a failure
- [#102](https://github.com/sceny/omarchy-devices/issues/102) Messages: a conversation opened while another loaded stayed on skeletons
- [#108](https://github.com/sceny/omarchy-devices/issues/108) Demo mode showed the real device's nickname
- [#67](https://github.com/sceny/omarchy-devices/issues/67) The line under the pill covered only part of it

### Pull requests without an issue

- [#111](https://github.com/sceny/omarchy-devices/pull/111) One keyboard cursor and one Esc everywhere, messages by keyboard, pictures open sandboxed
- [#104](https://github.com/sceny/omarchy-devices/pull/104) The hand cursor over the panel's buttons
- [#87](https://github.com/sceny/omarchy-devices/pull/87) The resting glyph with nothing paired
- [#112](https://github.com/sceny/omarchy-devices/pull/112) The user guide: a picture per topic, from demo mode

### Upgrading

- **Received** and **Gallery** join your saved order at the end, switched
  on; each shows only while it has something.
- The Devices section is gone; its switch is ignored. Nothing in your
  settings is rewritten.

## 0.6.1 — 2026-09-28

### Docs
- A new picture for the marketplace and the README: the pill in the bar,
  the panel with shortcuts, Now playing and notifications, and the
  messages view, in one shot.
- A one-screen README, a short user guide (getting started, the panel,
  messages, settings, troubleshooting) and the technical pages apart.

### Fixed
- Demo mode shows every feature even while the real phone is away: the
  messages view no longer refuses to open, and the shortcuts are no
  longer dimmed.

## 0.6.0 — 2026-09-27

### Panel
- Every click that goes to the device shows it is waiting: the clicked
  control (the dismiss X, a notification's action or reply button, a
  shortcut, the pairing buttons, next and previous) turns into a small
  ring until the device's answer shows, not only until the call returns.
  A dismiss the phone never confirms brings the X back and says so. The
  line under a click ("Dismissed") shows once the device has answered.
- Chat notifications (WhatsApp, Signal and other group or one-to-one
  chats) show each sender's name and messages the way the phone does,
  instead of raw `<b>` and `<br/>` markup. Folded, it shows the latest
  message and its sender; *Show all* shows the whole conversation. A
  group's unread count, which came glued to its name ("Book club
  (8 messages)"), shows beside the name, dimmed (#39). The text is always
  shown as plain text, so nothing in a message is interpreted.
- Scrolling follows the wheel: a long spin goes as far as it was spun
  and a nudge moves a little, instead of about one step per spin; a
  touchpad moves the lists with the fingers. On the main page, the
  conversation list, the messages and the new-message suggestions.
- Demo mode waits as long as a phone about takes, so the waiting states
  can be looked at; `pressDismiss` presses a demo notification's X.

### Messages
- The conversation list and a conversation that is opening show
  skeletons when loading takes more than a quarter second; the messages
  ease in when they land. The conversation's header and the composer stay
  on the pane's edges while the panel resizes, and the name crossfades in
  place when moving between conversations. Loading older messages, a
  message being sent and an attachment being fetched show the ring.
- Pressing an action (such as *Mark as read*) or sending a reply on a
  text-message notification in the panel marks its conversation read in
  the messages view at once, instead of when the phone reports it.
- When KDE Connect restarts, the plugin asks the phone for its
  conversations again, so nothing from the previous run stays stale.

### Fixed
- Opening a conversation could show only its latest message, with no
  older ones to scroll to, after the plugin had asked the phone for every
  conversation (at start, or after KDE Connect restarted). The count KDE
  Connect sends after that is how many messages it holds, not how long
  the conversation is; only the answer to a page the plugin asked for is
  taken as that now.

## 0.5.0 — 2026-09-26

### Bar
- Choose what the bar shows beside the device glyph, in order: connection
  (Wi-Fi, Bluetooth, crossed out while away), battery, battery %,
  notification and unread-message counts, now playing, and a notification
  count bubble on the glyph (#3).
- The new default is the bubble and the battery only when low: a healthy
  device with nothing new is the glyph alone.

### Panel
- Order the sections (Devices, Shortcuts, Now playing, Notifications) in
  Layout settings, with the arrows or Shift+K/Shift+J; each has its own
  switch.
- Shortcuts fold like the other sections; folded, they become a row of
  icons in the header that still work.
- Notifications hides while there are none.
- Send text or a link to the device: a Send text shortcut opens a field;
  text lands on the device's clipboard, a link arrives ready to open, and
  Ctrl+Enter sends it as a ping with that message (#10).
- Cellular signal bars beside the network type on the meta line
  (`󰣸 LTE`) (#11).

### Fixed
- Sending a notification reply with Enter opened the reply field again.

### Upgrading
- The `showPercent` setting is gone: the bar follows the Bar settings
  (`barIndicators`, `batteryLowOnly`). For the old pill (`󰄜 63%`), tick only
  Battery % there and turn *Battery only when low* off.

## 0.4.0 — 2026-09-26

The first public release, as `sceny.devices`.

### Text messages
- A two-pane view inside the panel: conversations with unread marks, a
  one-click unread filter and search; the conversation with day headers,
  history that loads as you scroll, and reply.
- New messages with a recipient search over contacts and past threads.
- Picture messages (MMS) with previews that open full size.
- The conversation last open comes back; unsent drafts are kept while you
  switch (in memory only).
- Text-message notifications expand to the full text and open their
  conversation.

### Devices
- Phones, tablets, laptops, computers and TVs, each with its own glyph.
- A Devices section when there is a choice: switch, pair, accept or reject a
  request with its verification key, unpair.
- Setup checks (installed, running, firewall, paired, connected) with a fix
  for what can be fixed here, and the steps on the phone.

### Panel
- Shortcuts you choose and order; media as a carousel of the device's
  players with seek and volume; notifications with reply, dismiss and the
  app's own actions.
- Sections fold, on the main page and in settings, and remember it.
- Results show as a toast, or in Omarchy's on-screen display when the panel
  is closed.
- Page changes and the panel's size animate at one pace.
- Demo mode for screenshots, with made-up notifications and conversations.
