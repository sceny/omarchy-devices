# Changelog

Every release is a tag (`vX.Y.Z`) on `main`, with the same version in
`manifest.json`.

## Unreleased

- Several devices: with two or more paired devices, a tab each at the top
  of the panel (`1`–`9`, Shift+H / Shift+L), and a chip each in the bar:
  the first device always, the others while they have news (notifications,
  unread messages, a low battery). Each chip has its own bubble; clicking
  it opens the panel on that device. The panel opens on the first
  connected device. Folded sections are kept per device. With one device,
  nothing changes (#73).
- The pill never disappears: with nothing to show (nothing paired, or
  KDE Connect stopped) it keeps a devices glyph to click.
- A device asking to pair shows a card at the top of the panel, above the
  tabs, with its key, *Accept* and *Reject*; it pushes the rest down while
  it lasts.
- The open-panel mark under the pill spans every chip (#67).
- IPC: `view <device>`, `openOn <device>`, `tabs`; `demo many`. Leaving a
  demo (`live`) puts every setting back as it was when the demo began.
- Settings for devices (#74): a nickname and an icon for each device, used
  in the bar and the tabs. With several devices, Settings lists them
  (drag to move, or Shift+K / Shift+J; pair, accept and reject there
  too); each has its own page: nickname, icon, whether it shows in
  the bar (always, only with news, never), whether it has a tab, and its
  own layout, bar and shortcuts, marked CUSTOM with *use the defaults*.
  *Defaults for all devices* sets the rest. Unpair is on the device's page.
- The Devices section is gone from the main page: tabs, the pairing card
  and Settings do its work.
- Edit the page in place (✎ on the device's header, or `E`): each section
  becomes a bar to drag or switch off, every shortcut shows (drag the
  chosen ones, click to add or take one away), and ✓ Done ends it. Each
  device keeps its own; a device's page in Settings points there, and
  *Defaults for all devices* keeps the sections and shortcuts.
- Drag to reorder: every order has a grip to drag by (devices, sections,
  bar indicators, shortcuts), and the tabs can be dragged sideways. While
  one moves, the others slide aside to show where it will land; on release
  it glides into place. Shift+K / Shift+J glide the same way. The ↑ ↓
  buttons on each row are gone: the grip and the keys do their work.

### Fixed
- Moving the first section up in Layout did nothing: it swapped with the
  hidden Devices section.
- A low battery turned the whole pill red; now only the battery glyph and
  its % do. Beside the battery glyph, the % joins it (a thin space apart),
  so the two read as one.
- A newly ticked bar indicator went to the end; it now goes to its natural
  place (connection, battery, %, counts, playing, bubble), so % follows
  the battery.

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
