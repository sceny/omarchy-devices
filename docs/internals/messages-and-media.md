[Devices](../../README.md) › Internals › Messages and media

# Messages and media

## Messages

`kdeconnect-bridge sms <device>` holds one connection to KDE Connect's
`conversations` interface. Commands on stdin (`load`, `reply`, `send`,
`attachment`, `refresh`), events on stdout (`threads`, `thread`, `messages`,
`message`, `attachment`, `contacts`, `sent`, `error`); the protocol is at
the top of the bridge's `sms` section.

- History comes in pages. A page is complete when full, when KDE Connect
  answers the request with `conversationLoaded`, or when the burst goes
  quiet for 0.8 s. That count is how many messages KDE Connect holds, so it
  is trusted only as the answer to a page asked for.
- KDE Connect cannot mark messages read. A thread is unread when the phone
  says so and has a message newer than what was opened here
  (`sms-seen-<device>.json`).
- Chat notifications arrive as markup KDE Connect builds (`<b>sender</b>`,
  `<br/>`); the bridge splits that fixed format into plain pairs and the
  panel shows only plain text.
- Nothing scripted focuses the composer: keystrokes meant for another window
  must never become a sent text.

## Contacts

`kdeconnect-bridge contacts <device> [--sync]` reads the vCards KDE
Connect's contacts plugin writes and prints every card as JSON (`--sync`
asks the phone first); the names of text threads come from the same
parser. A card's photo is decoded in the sandbox and cached; its own bytes
never reach the shell. `contacts-app` opens the contacts web app Omarchy
installs (`omarchy-launch-or-focus-webapp`) and says so when there is none.
Nothing is written back: the phone is the truth for its cards.

## Media

KDE Connect exports each phone player as
`org.mpris.MediaPlayer2.kdeconnect.mpris_*`, which the shell tracks live.
All of a phone's players report one position, so only the playing card
shows a seek bar. The player list changes only when a player appears or
goes: a seek reports "paused" for a moment, and nothing blinks for it.
