[Devices](../README.md) › Security and privacy

# Security and privacy

## It stays between you and your phone

- KDE Connect pairs the two with a key you compare on both, and encrypts
  what they send. The firewall rules the plugin adds open KDE Connect's
  ports to your home and office networks (the private address ranges) and
  to your mesh (Tailscale, NordVPN Meshnet), never to everyone.
- From anywhere goes through your own mesh account: the plugin reads the
  mesh's list of your devices to find your phone, and gives KDE Connect
  its address. Nothing else leaves this computer.
- No account, no telemetry, no cloud. It never sends a text, rings or
  plays anything on its own. It keeps caches only
  (`~/.cache/sceny.devices/`); drafts stay in memory.
- A picture from the phone is decoded in a sandbox, and you see a copy made
  from its pixels, never the phone's file.

## The screen and apps: what Wireless debugging allows

The screen and the apps need Android's **Developer options** and
**Wireless debugging** (adb). While it is on, a computer you paired with
can control the phone fully: see its screen, type, open and install apps.
So:

- Pairing is your own act: a QR code here, new each time, for two minutes;
  it pairs only with the phone that scanned it. Android allows it per
  Wi-Fi, and turns it off when the phone restarts.
- Take it back any time: *Developer options › Revoke USB debugging
  authorizations*, or turn Wireless debugging off.
- With the screen set up, the plugin can allow KDE Connect a permission
  over adb, and only on your click.

## Calls here: what Bluetooth hands-free allows

Paired for calls, the computer is the phone's hands-free, as a car is: it
hears and places calls, and sends tones. Nothing more of the phone.

- Pairing is your own act, in Omarchy's Bluetooth; the plugin uses the
  phone paired under its name only after your click.
- A call is answered, placed or ended only by your click. Between calls
  the audio stays on the phone.
- Take it back any time: forget the computer in the phone's Bluetooth, or
  turn Calls here off.

## Every step shown before it runs

- A password only after a card says what for: the packages by name, the
  firewall rule as written. Only that plan runs with it, checked again
  before it does, and nothing installed is downgraded.
- A change on the phone (a permission) is a click's, said in its row.

## Fix with AI

It opens **your** default coding agent, the way Omarchy opens it, with the
plugin's guide. That guide tells it never to open the phone's data, send
anything from it, or change the phone without asking. An issue it offers
to file carries nothing private, and is filed only with your yes. The
agent talks to its own service: what you tell it is up to you.
