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
- Edit the page in place (✎ on hovering the device's name, a right-click
  on the page, or `E`): each section
  becomes a bar to drag or switch off, every shortcut shows (drag the
  chosen ones, click to add or take one away), and ✓ Done ends it. Each
  device keeps its own; a device's page in Settings points there, and
  *Defaults for all devices* keeps the sections and shortcuts.
- Drag to reorder: every order has a grip to drag by (devices, sections,
  bar indicators, shortcuts), and the tabs can be dragged sideways. While
  one moves, the others slide aside to show where it will land; on release
  it glides into place. Shift+K / Shift+J glide the same way. The ↑ ↓
  buttons on each row are gone: the grip and the keys do their work.
- Calls (#58): while a device rings, its chip in the bar shows a ringing
  phone that glows ring by ring, and a card above the tabs names the
  caller (and the device, with several), its sound waves ringing; the
  panel opens on the ringing device. A missed call stays in the chip and
  on the card until closed, with *Call back* (the phone's dialer, ready on
  the number) and *Text back*, both on the device the call came to. A
  *Calls* switch in each device's bar settings turns it off. KDE Connect
  does not say when a call is answered or ends, so a ringing card gives up
  after 45 s.
- IPC: `demoCall ringing|missed|none`, `pressTextBack`, `closeCall`,
  `demoTextTo`, `pressEscape`.

- The bar joins edit in place (#84): editing a device's page starts with
  its chip, drawn as the bar shows it, a little larger: drag an
  indicator to move it, click to add or take one away; then the
  *Battery only when low* and *Calls* switches; the pill in the bar
  changes as you go. A right-click on a device's chip opens it. The bar
  leaves a device's Settings; *Defaults for all devices* keeps it.
- The pill in the bar moves as its indicators do: a new order slides
  each one to its place, and one that comes or goes fades, at the panel's
  pace.
- Editing a page: changes show at once; ✓ (or `E`) keeps them, and Esc
  now undoes everything since editing began.
- IPC: `rightClickChip`, `editBar`, `editBarFlag`, `editMoveBar`.

- Received (#37): a section with the files the device sent you (open in its app,
  show in Files, forget); they are kept in the cache. Their folders are
  watched: a file renamed there is followed, and one deleted or moved away
  leaves the list at once (where the system allows a watch; otherwise
  within 30 s). Gone while there are none.
- Gallery (#65): a section with the device's newest photos and videos,
  found as the phone's own gallery finds them: all of its shared storage,
  WhatsApp's included, but hidden and `.nomedia` folders and apps' private
  ones; each folder is an album. Each folder's listing is kept, so only
  what changed is read again. A small ring at the header's right shows
  while the phone is read (the last photos show meanwhile); idle, a
  refresh button takes its place while the pointer is on the header.
  - Click a tile to open it: the file is copied here first (a ring on the
    tile) and the copy opens, so a video plays at its own pace, not the
    network's; the copies are a cache of 2 GB at most. From a tile's
    corner, copy it or save a copy in Pictures/<device>, with its own date
    and only once; or drag it into a window.
  - The biggest albums open in the file manager (a folder icon); the row
    scrolls sideways when they do not fit (the arrows at its edges, the
    wheel, a swipe or a drag)). Opening an album, or a received
    file's folder, closes the panel; opening a photo or a file keeps it
    open for the next.
  - A file from the phone is decoded only in a sandbox: images through
    glycin (each decode in its own bubblewrap sandbox), a video's frame
    in one of ours (no network, no home, only that file); the panel
    shows a JPEG made from the pixels, never the phone's file (#105).
  - Read through KDE Connect, which needs `sshfs`: the section offers to
    install it. When the storage cannot be opened, the section says so
    with *Try again*, and asks again by itself only after 10 minutes, so
    KDE Connect's error does not pop up on every open (#100).
  - Received and Gallery join every saved order at the end, each with its
    own switch; each is gone while it has nothing.
- IPC: `filesInfo`, `dismissReceived`.
- Connection and Add a device (#75), two Settings pages in place of the
  Setup and Add a device folds. Connection checks this computer (KDE
  Connect, the firewall, the network) with fixes; a check can be ignored,
  and a failing one puts a red dot on the cog, which then opens
  Connection. Add a device lists requests to pair, the steps on the
  device and devices in reach to pair with. The panel opens on Add a
  device while nothing is paired, and on Connection while KDE Connect is
  down.
- Reconnect (#69): an away device's page says where it was last seen
  (kept across restarts) and whether that was another network, with
  *Reconnect*: it looks for the device, then says what to try. Opening the
  panel on an away device looks once by itself.
- IPC: `page connection|addDevice`, `demoAway`, `reconnect`, `ignoreCheck`;
  `demoSetup` stays until `live`.

- Pairing (#92): a device asking to pair brings a card under the bar at
  once (its key, *Accept*, *Reject*), and the first chip glows on the ring
  beat while it waits; the card never takes the keyboard, and it waits
  while the panel is open (the panel shows the request itself). A pairing
  started from the panel shows no pop-up: it is a card on Add a device,
  with the key and a countdown of KDE Connect's 30 seconds; not accepted
  in time, its row says so; accepted, the card turns *✓ Paired* and the
  panel goes to the device. The key reads the same everywhere: large, one
  word, as KDE Connect shows it. Pairing actions no longer toast when they
  work.

### Fixed
- Images from the phone (notification icons, a track's art, a picture
  message's preview) were decoded by the shell itself; they are now shown
  only as copies decoded in a sandbox (glycin), as the Gallery's are, and
  a received picture's preview too (#107).
- No hand cursor showed over the panel's buttons: the main page's
  right-click area and the media swipe area held the arrow over them.
- Messages: opening a conversation while another was still loading left
  every conversation on skeletons until the shell restarted (#102).
- A device joining could swap two others in the order (the first device:
  the one always in the bar, opened first).
- Settings pages without buttons ended in an empty band (Add a device,
  Connection).
- An error from the messages reader could stay on screen for good.
- *Bar: use the defaults* left a device's *Calls* switch as it was.
- While charging, the % beside the battery overlapped its bolt; it now
  starts past the glyph's ink.
- New message: after picking someone, every contact stayed listed; the
  list now shows only while typing a name, and a click on a contact goes
  on to the message. In messages, Esc undoes one thing at a time: the
  name being typed, then the new message, then the search, then messages. After Esc leaves a
  text field, the next Esc still closes messages.
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
