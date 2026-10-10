[Devices](../../README.md) › Design › Setup

# Setup that just works: design

**Status:** built in 0.8.0 except where marked *planned*; sections 5 and 6
reworked after a new user's first run (2026-10-06): the engine stays, what
it shows changes.

## 1. The premise (the owner's)

- **The plugin takes control of what it needs.** Not a manual to follow: the
  plugin does every step it can itself and asks only for what it cannot (a
  tap on the phone, a password), one step at a time, then carries on by
  itself. Not even a wizard where it can be avoided: *it just works*.
- **KDE Connect is one source among others,** not the centre. The screen and
  apps come from adb and scrcpy, the gallery from KDE Connect's storage over
  sshfs, the phone's permissions from adb; Bluetooth comes later.
- **KDE Connect's daemon and command line are enough.** The plugin sets up
  what KDE Connect's own app would (pairing, which of its plugins run per
  device): that app is never needed.
- **What KDE Connect gets wrong is handled here** when a user meets it
  (a dead mount, a hidden notification forwarded, a stale player): the
  plugin fixes or filters it, and the KDE Connect issue stays open so the
  fix can go when KDE Connect has its own.

## 2. Words

- **Source:** where something comes from: KDE Connect, the screen link (adb
  and scrcpy), files (sshfs over KDE Connect), the phone's permissions;
  *planned:* the network, Bluetooth. A source has a part on this computer
  (packages, services, the firewall), a part on the device (pairing, a
  setting, a permission) and a live state.
- **Feature:** what the user wants: Notifications, Messages, Names, Now
  playing, Gallery, Files they send, Screen, Apps, Calls, Clipboard, Ring,
  Battery. A feature needs sources, KDE Connect plugins and permissions.
- **Step:** one thing a feature still needs. The plugin does it (*auto*) or
  asks for it (*ask*: on the phone, a password, a scan).
- **Remedy:** what a feature that was working tries, in order, when it
  breaks (#121).

## 3. States: one word for each, everywhere

| State | Means | Gear dot |
|---|---|---|
| **On** | works | no |
| **Set up** | not set up yet (optional) | no |
| **Needs attention** | was set up, now broken: the remedies, then one step | yes |
| **Turned off** | the user turned it off (its KDE Connect plugins are off) | no |
| **Not on this device** | the device cannot (no SIM, Android 9, an iPhone) | no |

A check the user ignored (*Ignore*, `ignoredChecks`) stops lighting the dot.

## 4. The model (`Model.js`: `GATEWAYS`, `FEATURES`, `deviceSetup`; #128)

Three layers, read from the bridge's reports (`doctor`, `features`,
`screen`), never set by hand:

- **Gateways**: how the plugin gets something from a device.
- **Setup items**: what a gateway needs, each checked once where it lives,
  with its remedies; states ok, missing, broken (it worked and stopped),
  off, unavailable, unknown, away.
- **Features**: what the user gets, from the items they need.

| Gateway | Setup items (where) | Features |
|---|---|---|
| KDE Connect | the link (device); a plugin per feature (device); notifications arriving (device, health) | all but Screen and apps |
| Android permissions | notification access, SMS, contacts, phone, all files access (device, over adb or a tap) | Notifications, Now playing, Messages, Names, Calls, Gallery |
| Storage link | sshfs (this computer); its storage mounted (device, health) | Gallery |
| Screen link | scrcpy and adb (this computer); Wireless debugging and adb pairing (device); Screen and apps on (the plugin's switch) | Screen and apps |
| *planned:* Bluetooth | BlueZ and audio here; paired for calls | Calls with audio (#59) |

A feature's state comes from its items the same way for every feature:
away > being read > turned off > not on this device > needs attention >
to set up > on. Everything reads it: the device page's rows, Settings'
status, the gear dot, the main page's line, *Fix all*, *Fix with AI*.

## 5. Just works, then out of the way

The engine above runs unseen. The panel shows three things only: the
feature working; the one act only the user can do, at the moment they
reach for what it gives; and their preferences. Every step is one of three
kinds:

| Kind | Examples | What shows |
|---|---|---|
| The plugin does it alone | KDE Connect's plugins, the mount, reconnecting, reading notifications again | nothing |
| Root on this computer | the packages, the firewall rule | once, at the first run: one card, one password (`fix ready`) |
| Only the user's hands on the device | install the app, pair, a permission, Wireless debugging | where the feature is used, once, then gone |

Where each is asked: notification access in Notifications; SMS and
contacts on the Messages page; the gallery's storage in its section; the
screen on the first **Open** of a notification's app or the Screen
shortcut, after which what was pressed opens by itself. An ask sits only
where the user already is: nothing advertises a feature.

A feature's one action (*Allow*, *Fix*, a switch turned on) runs every step
the plugin can do, in order, and stops at the first one only the user can
do:

1. a package this computer needs (sshfs, scrcpy), first and in one
   password prompt after a card says what for: the same item This
   computer shows;
2. KDE Connect's plugins on for this device (`setPluginEnabled`);
3. the phone's permissions, granted over adb when the screen is set up
   (`pm grant`, the notification listener, all files access), else the one
   tap to do on the phone;
4. the mount, the search, the pairing.

What is left is one step, said plainly, with what it needs (a QR code, the
switch's place on the phone), and the plugin goes on by itself when it is
done (as the screen does after a restart).

Turning a feature **off** turns its KDE Connect plugins off for that device,
so the phone stops sending it.

## 6. Settings

Preferences, not status. Each setting where its scope is; folds one level
deep, anything deeper a page of its own.

```
Settings (one device: its page)        Settings (several)
├─ Status   only while something       ├─ Status   only while something needs the user
│           needs the user             ├─ MY DEVICES   every device, asking to pair, Add a device
├─ THIS DEVICE   nickname, icon        │   └─ <Device> ›   its page, tabs to the others
├─ WHAT IT SHARES WITH THIS COMPUTER   └─ For all devices ›
│     a switch per feature it can do
├─ Sections, shortcuts and bar ›   (edited on the page)
├─ Add a device ›
└─ Unpair
```

- **Nothing while all is well:** no *Everything works*, no state words,
  no tools by name. The status appears only when something stopped and
  the plugin could not fix it alone.
- **A problem shows where its effect is.** On the main page, in the
  section of the feature it stopped (*Fix*, *Details*, *Fix with AI*;
  `Model.sectionNote`); a problem with no section (this computer, a link)
  in the line at the top. Settings' status lists them all; the gear's dot
  counts them.
- **Diagnostics** (this computer's checks: KDE Connect, the firewall, the
  network, the packages) is a page reached from a problem it causes, not
  a place in Settings.
- **What it shares** lists only what the device can do: a device that is
  not Android (an iPhone) has no screen link and no Android steps.
- **Screen and apps** keeps its own page (its steps, where it opens, the
  sound). **KDE Connect settings** goes: nothing is left there that the
  plugin does not do.

## 7. KDE Connect's faults, handled here

| KDE Connect issue | What the plugin does |
|---|---|
| #98 dead mount (Gallery, #99) | unmount, then mount again, before giving up; never shows an error as an empty gallery |
| #94 no notifications after re-pairing (#95) | reloads the device's plugins, then asks again |
| #51 One UI's hidden "1 more notification" (#52) | not shown |
| #35 a player Android hid (#33) | not shown once the phone has no session for it |
| #38 a group chat's title with its count | the count taken out of the title |
| #29/#30 actions that open a screen on the phone | opened in the app's window (the screen, when set up) |
| #60/#61 calls: ringing and missed only | stays as it is (no D-Bus for more); Bluetooth calls are #59 |

## 8. Planned: connectivity (#119, #8) and Bluetooth (#59)

Not built in 0.8; their places are set so they do not drift, in section 5's
shape (asked where used, nothing shown once it works):

- **The network is a source.** Its firewall rule for every local network
  and VPN joins `fix ready`; a device out of reach asks on its away card
  to be reached away from home (an address KDE Connect keeps,
  `customDevices`; Tailscale peers, matched silently when certain). The
  link a device is on is not shown.
- **Bluetooth is a source.** This computer: BlueZ and the audio profiles;
  the device: paired for calls, offered after a missed or ended call (a
  ringing call is too short to pair); then *Answer here* on the call
  card.

## 9. Rules this changes (AGENTS.md)

- The boundary: each source is the truth for its feature; KDE Connect is
  one of them; KDE Connect's faults are handled here when met.
- Setup never shows plumbing; using a feature gets it working; a problem
  shows where its effect is; Settings is preferences, the device's page
  with one device (sections 5 and 6).
- Fixes still change the system only on a click (one password prompt), and
  a change on the phone (a permission) only on a click too.
