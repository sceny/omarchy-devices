# Changelog

Every release is a tag (`vX.Y.Z`) on `main`, with the same version in
`manifest.json`.

## Unreleased

- Send text or a link to the device from the panel: a Send text shortcut
  opens a field; text lands on the device's clipboard, a link arrives ready
  to open, and Ctrl+Enter sends it as a ping with that message (#10).
- Fixed: sending a notification reply with Enter opened the reply field
  again.
- Cellular signal bars beside the network type on the panel's meta line
  (`󰣸 LTE`); the bars alone when the phone has no type to report, nothing
  on a device with no cellular network (#11).

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
