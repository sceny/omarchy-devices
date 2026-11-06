[Devices](../../README.md) › Setup › What it cannot do

# What it cannot do

The panel shows what KDE Connect sends. Today it does not:

- send **ongoing** notifications (navigation, timers, downloads);
- mark messages **read** on the phone: reading a conversation here clears
  only its notification
  ([#29](https://github.com/sceny/omarchy-devices/issues/29));
- show an app's **buttons** (*Mark as read*) on a notification already on
  the phone when it connected, or one that arrived silent: only on those
  that arrive while the panel runs
  ([#436](https://github.com/sceny/omarchy-devices/issues/436));
- carry **RCS** chats, only SMS and MMS;
- **paste** or **drop** a picture into a reply: use the attach button. The
  panel never takes part in a clipboard transfer or a drag, which would
  freeze the shell on a program that never answers;
- keep each player's **position**: only the playing one has a seek bar;
- on an **iPhone**, share notifications, texts, media or contacts: files
  and the clipboard only, while the app is open.

While you type in a field, Qt reads each new **clipboard** copy, whatever
its size, with no switch for it. Fields are editable only while they have
the keyboard, so this lasts only while you type
([#170](https://github.com/sceny/omarchy-devices/issues/170)).

Like the phone, it hides a paused player Android dropped
([#33](https://github.com/sceny/omarchy-devices/issues/33)) and One UI's
"1 more notification" ([#52](https://github.com/sceny/omarchy-devices/issues/52)).

By feature: [Calls](limits-calls.md) · [Contacts](limits-contacts.md) ·
[Screen and apps](limits-screen-and-apps.md) ·
[From anywhere](limits-anywhere.md)
