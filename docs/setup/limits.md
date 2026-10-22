[Devices](../../README.md) › Setup › What it cannot do

# What it cannot do

The panel shows what KDE Connect sends. Today it does not:

- send **ongoing** notifications (navigation, timers, downloads);
- pass on an app's **buttons** (*Mark as read*) or the phone's **read
  state**;
- carry **RCS** chats (only SMS and MMS);
- **paste** or **drop** a picture into a reply: attach it with the
  attach button. The panel never takes part in a clipboard transfer or a drag
  (the shell would freeze on a program that never answers);
- keep each player's **position**: only the playing one has a seek bar;
- on an **iPhone**, share notifications, texts or media: files and the
  clipboard only, while the app is open;
- answer a call, carry its audio, or say when it was **answered or ended**:
  [Calls here](calls-here.md) does, over Bluetooth. Without it, a ringing
  card gives up after 45 s, and a call you decline shows as missed
  ([#60](https://github.com/sceny/omarchy-devices/issues/60)).
- keep a text field from reading the **clipboard** while you type in it: Qt
  reads what another program copied each time the clipboard changes, whatever
  its size, and has no switch for it. The panel's fields are editable only
  while they have the keyboard, so this lasts only while you type in one
  ([#170](https://github.com/sceny/omarchy-devices/issues/170)).

## Calls

- **Mute the ringer** from the computer, and a ringing card that follows
  the call to its **end**, wait for KDE Connect to pass them on
  ([#61](https://github.com/sceny/omarchy-devices/issues/61)). With
  [Calls here](calls-here.md) the card follows the call to its end.
- Once a call's audio is here, it goes back to the phone from the
  **phone's** audio button: Bluetooth hands-free has no way to send it back
  from the computer.
- With a Bluetooth **headset** on the computer, its microphone needs its
  own hands-free link, so its sound is plainer during the call.

## Contacts

- Cards are **read-only**: changed on the phone.
- The panel cannot tell **which account** holds a contact: a card synced
  with another account (Samsung, work) still offers *Find in Google
  Contacts*, which finds nothing there.
- An **iPhone** sends no contacts at all.
- A card without a photo shows the person's initial.

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
