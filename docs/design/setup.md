[Devices](../../README.md) › Design › Setup

# Setup that just works: design

**Status:** built in 0.8.0 except where marked *planned*; Bluetooth calls
(#59) built for 0.9.0. 2026-10-05.

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
  and scrcpy), files (sshfs over KDE Connect), the phone's permissions,
  Bluetooth (PipeWire's hands-free service, for calls); *planned:* the
  network. A source has a part on this computer
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
| Bluetooth | Bluetooth on here, PipeWire's hands-free service (this computer); paired for calls, kept and connected (device); Calls here on (the plugin's switch) | Calls here (#59) |

A feature's state comes from its items the same way for every feature:
away > being read > turned off > not on this device > needs attention >
to set up > on. Everything reads it: the device page's rows, Settings'
status, the gear dot, the main page's line, *Fix all*, *Fix with AI*.

## 5. Just works

A feature's one action (*Turn on*, *Fix*) runs every step the plugin can do,
in order, and stops at the first one only the user can do:

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

One shape whatever the number of devices; each setting where its scope
is; folds one level deep, anything deeper a page of its own.

```
Settings
├─ Status                      Everything works, or each problem once (its place ›),
│                              Fix all, Fix with AI
├─ MY DEVICES                  every device (the one in view too), asking to pair
│   ├─ <Device> ›              its page, with tabs to the others
│   │   ├─ THIS DEVICE         nickname, icon; with several: bar, tab
│   │   ├─ WHAT IT CAN DO      a row per feature: its state, one action, a switch
│   │   ├─ Sections, shortcuts and bar   (edited on the page; the defaults or its own)
│   │   └─ Unpair
│   └─ Add a device ›          pair it, then its page
├─ For all devices ›           (two or more: with one, its layout is the defaults)
└─ This computer ›             KDE Connect, firewall, network, Screen tools, Gallery tools
```

- **A problem shows once, where its cause is.** This computer holds only
  this computer (KDE Connect, the firewall, the network, the packages); a
  device's page holds that device (its features, its permissions, Wireless
  debugging, its mount). A feature that needs something here says so
  (*Needs sshfs on this computer*), and its one click installs it.
- **The status** lists every problem (Model.settingsProblems: a check
  failing here, not optional nor ignored; a broken item on a connected
  device, once with the features it affects; a fix that did not work). The gear's dot and
  a line at the top of the main page count the same list.
- **Fix all** runs what its page is about: the status everything (this
  computer first, one password), This computer its checks, a device's
  page that device's features.
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
| #60/#61 calls: ringing and missed only | Calls here (#59, Bluetooth) follows every call to its end and answers it; KDE Connect still names the caller. No ringer mute (#61) |

## 8. Connectivity (#119, #8, planned) and Bluetooth (#59)

The network is not built yet; its place is set so it does not drift.
Bluetooth is built:

- **The network is a source.** This computer gets a *Network* row (the
  firewall for every local network and VPN, not just the default route);
  a device gets *Reach it away* (an address KDE Connect keeps,
  `customDevices`; Tailscale peers). Its link shows on the device page
  (`activeProviderNames`: Wi-Fi, Bluetooth).
- **Bluetooth is a source** (built for 0.9.0, #59). This computer: Bluetooth
  on (`fix bluetooth-on`, Omarchy's switch; installed and started behind
  the password card, `fix bluetooth`) and PipeWire's hands-free service
  (`fix audio`, Omarchy's audio restart). The device: paired over
  Bluetooth (the user's step in Omarchy's Bluetooth, which the step opens
  and waits for), kept on the click that turns it on (the phone paired
  under its name), and connected. The feature: *Calls here*, a row of its
  own beside *Calls*: who is calling needs KDE Connect and no Bluetooth,
  answering here needs Bluetooth and no KDE Connect.

## 9. Rules this changes (AGENTS.md)

- The boundary: each source is the truth for its feature; KDE Connect is
  one of them; KDE Connect's faults are handled here when met.
- This computer and Add a device are Settings pages; the device's
  features live on its page; Settings has one shape (section 6).
- Fixes still change the system only on a click (one password prompt), and
  a change on the phone (a permission) only on a click too.
