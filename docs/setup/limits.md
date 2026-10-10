[Devices](../../README.md) › Setup › What it cannot do

# What it cannot do

The panel shows what KDE Connect sends. Today it does not:

- send **ongoing** notifications (navigation, timers, downloads);
- pass on an app's **buttons** (*Mark as read*) or the phone's **read
  state**;
- carry **RCS** chats (only SMS and MMS);
- keep each player's **position**: only the playing one has a seek bar;
- on an **iPhone**, share notifications, texts or media: files and the
  clipboard only, while the app is open;
- edit a **contact**: cards are read-only, changed on the phone;
- tell **which account** holds a contact: a card synced with another
  account (Samsung, work) still offers *Find in Google Contacts*, which
  finds nothing there; an iPhone sends no contacts at all;
- answer a call, carry its audio, or say when it was **answered or ended**:
  a ringing card gives up after 45 s, and a call you decline shows as
  missed ([#60](https://github.com/sceny/omarchy-devices/issues/60)).

## The screen and apps

- Apps in windows need **Android 10** or newer; older phones open only the
  whole screen.
- An app that **protects its screen** (many banks) shows black.
- **Sound** here needs Android 11; **Both** needs Android 13, and an app
  can keep its sound out of it. One window takes the phone's whole sound
  at a time, and changing where it plays opens the window again.
- A notification opens its **app**, not the exact screen inside it:
  KDE Connect does not forward the tap target
  ([#122](https://github.com/sceny/omarchy-devices/issues/122)). A **text
  message** is the exception — it opens its conversation in
  [Messages](../use/messages.md), since the texts come from the phone too.

## From anywhere

- The **screen and apps** reach the phone over the mesh only while it is on
  a Wi-Fi with Wireless debugging on: Android turns it off on mobile data.
  Everything else works on any network.
- Meshes other than Tailscale and NordVPN Meshnet (ZeroTier, your own
  WireGuard): type the phone's address on its page.

## What the phone hides

Like the phone, it hides what the phone hides: a paused player Android dropped
([#33](https://github.com/sceny/omarchy-devices/issues/33)), One UI's "1 more notification" ([#52](https://github.com/sceny/omarchy-devices/issues/52)).
