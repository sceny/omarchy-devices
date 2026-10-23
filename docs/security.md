[Devices](../README.md) › Security and privacy

# Security and privacy

## It stays between you and your phone

- KDE Connect pairs the two with a key you compare on both, and encrypts
  what they send, on your own network. The firewall rule the plugin adds
  opens KDE Connect's ports to the private address ranges (`10.0.0.0/8`,
  `172.16.0.0/12`, `192.168.0.0/16`) and to a mesh's interface (Tailscale,
  NordVPN Meshnet), never to everyone. It is a rule on the sender's address,
  not on the network: a public Wi-Fi that hands out private addresses
  reaches those ports too, and pairing, which needs the key you compare on
  both screens, is what keeps others out.
- No account, no telemetry, no cloud. It never sends a text, rings or
  plays anything on its own. It keeps caches only
  (`~/.cache/sceny.devices/`); drafts stay in memory.
- What you copy here stays here until you press **Clipboard**: the plugin
  turns off KDE Connect's automatic sharing of every copy, and of passwords
  a password manager marks, for each device. What you copy on the phone
  still arrives here. Turn automatic sharing back on in KDE Connect's own
  settings and the plugin leaves it on, but passwords still never go unless
  you also turn on sending passwords there.
  In the phone's screen window the clipboard is scrcpy's own: Ctrl+V there
  sends this computer's clipboard to the phone, and a copy made on the
  phone sets this computer's clipboard.
- A notification's buttons come from the notice KDE Connect itself posts
  on this computer for it. The plugin listens for that one notice, from KDE
  Connect only, holds its text in memory just long enough to match it, and
  writes only the buttons of a notification that has some to the cache,
  under a digest of its key, never its text or key.
- A contact's website, address or email that you open goes on the command
  line of the browser or app that opens it, and stays there while that
  program runs, where another program on this computer can read it So does a
  contact's name when you choose *Find in contacts app*: it is in the
  address given to the contacts app's launcher.
- A picture from the phone is decoded in a sandbox, and you see a copy made
  from its pixels, never the phone's file. A picture is recognised by what
  the file holds, not its name, and a message attachment opens only when you
  clicked it.

- The panel's commands (`omarchy-shell` IPC) are for the user who runs the
  shell: another program running as the same user can use them to do what a
  click does, such as sending this computer's clipboard to a device, sending
  files or answering a call. The plugin does not tell that program from
  you. It never focuses a text field for it, so no message is typed or sent
  that way; what the same user can already do on this computer (read the
  clipboard, run `kdeconnect-cli`) is not made harder here.

## The screen and apps: what Wireless debugging allows

The screen and the apps need Android's **Developer options** and
**Wireless debugging** (adb). While it is on, a computer you paired with
can control the phone fully: see its screen, type, open and install apps.
So:

- Pairing is your own act: a QR code here, new each time, for two minutes;
  it pairs only with the phone that scanned it. Its password is never on
  a command line, where another program on this computer could read it. Android
  allows it per Wi-Fi, and turns it off when the phone restarts.
- Take it back any time: *Developer options › Revoke USB debugging
  authorizations*, or turn Wireless debugging off.
- With the screen set up, the plugin can allow KDE Connect a permission
  over adb, and only on your click.

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

Each asset and the tests that hold it: [assets and tests](internals/security-assets.md).
