# Changelog

Every release is a tag (`vX.Y.Z`) on `main`, with the same version in
`manifest.json`.

## Unreleased

- Pressing an action (such as *Mark as read*) or sending a reply on a
  text-message notification in the panel marks its conversation read in
  the messages view at once, instead of when the phone reports it.

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
