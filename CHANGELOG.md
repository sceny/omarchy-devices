[Devices](README.md) › What's new

# What's new

Each version, newest first, grouped by what it touches. `omarchy plugin
update sceny.devices` brings the latest; each is a tag (`vX.Y.Z`) and a
GitHub release with these notes.

## Unreleased

### Highlights

- **From anywhere**: the phone in the panel away from home, through
  Tailscale (Omarchy's installer, from the panel) or NordVPN Meshnet, or an
  address you type. Its page says how it is connected now; a new network
  is announced at once; a Wi-Fi that keeps its devices apart is named as
  the likely cause.

### Issues

- [#119](https://github.com/sceny/omarchy-devices/issues/119) Networking: one reliable path to each device, at home and away
- [#8](https://github.com/sceny/omarchy-devices/issues/8) Reach devices over Tailscale or a custom address

### Upgrading

- **The firewall's fix** opens KDE Connect's ports to every private
  network (home, office) and to your mesh, instead of only the network
  you were on. Rules you have stay.
- **This computer** has a *Mesh network* row (optional).

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
