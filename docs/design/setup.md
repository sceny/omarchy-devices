[Devices](../../README.md) › Design › Setup

# Setup that just works: design

**Status:** built in 0.8.0 except where marked *planned*. 2026-10-04.

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

## 4. The model (`Model.js`: `FEATURES`, `featureStates`)

One table says what each feature needs; every state is worked out from the
bridge's report (`doctor`, now per device), never set by hand:

| Feature | KDE Connect plugins | Permissions (Android) | Other sources |
|---|---|---|---|
| Notifications | notifications | notification access | |
| Messages | sms, telephony | SMS, contacts | |
| Names | contacts | contacts | |
| Now playing | mpriscontrol | notification access | |
| Calls | telephony | phone, call log | *planned:* Bluetooth (#59) |
| Gallery | sftp | all files access | sshfs here |
| Files it sends | share | | |
| Clipboard | clipboard | | |
| Ring | findmyphone | | |
| Battery | battery | | |
| Screen | | | scrcpy and adb here; Wireless debugging; adb pairing |
| Apps | | | the screen; Android 10 |

Everything reads the same states: the gear dot, Connection's pills, the
device page's rows, the hints in sections, *Fix what I can*, *Diagnose*.

## 5. Just works

A feature's one action (*Turn on*, *Fix*) runs every step the plugin can do,
in order, and stops at the first one only the user can do:

1. this computer's packages, all in one password prompt (`fix install`,
   `fix sshfs`, `fix screen`);
2. KDE Connect running, its plugins on for this device (`setPluginEnabled`);
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

```
Settings
├─ <Device>                    (one device: this is the root page)
│   ├─ Nickname · Icon · Bar · Tab
│   ├─ WHAT IT CAN DO          a row per feature: its state, one action
│   ├─ Sections, shortcuts and bar   (edited on the page)
│   └─ Unpair
├─ This computer               the sources' part here, Fix what I can
├─ Add a device                pair it, then the features it can turn on
└─ Defaults for all devices    (several devices)
```

- **The device page** says what it can do and does it: one row per feature,
  with a switch where it can be turned off, the state, and its action.
  Screen and apps keeps its own page (its steps, where it opens, the sound).
- **This computer** is Connection, renamed: KDE Connect, the firewall, the
  packages; *planned:* the network and Bluetooth rows.
- **Add a device** pairs, then shows what the new device can turn on.
- **KDE Connect settings** goes: nothing is left there that the plugin does
  not do.

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

Not built in 0.8; their places are set so they do not drift:

- **The network is a source.** This computer gets a *Network* row (the
  firewall for every local network and VPN, not just the default route);
  a device gets *Reach it away* (an address KDE Connect keeps,
  `customDevices`; Tailscale peers). Its link shows on the device page
  (`activeProviderNames`: Wi-Fi, Bluetooth).
- **Bluetooth is a source.** This computer: BlueZ and the audio profiles;
  the device: paired for calls; the feature: *Calls* with the audio here.

## 9. Rules this changes (AGENTS.md)

- The boundary: each source is the truth for its feature; KDE Connect is
  one of them; KDE Connect's faults are handled here when met.
- Connection and Add a device: Connection is *This computer*; the device's
  features live on its page.
- Fixes still change the system only on a click (one password prompt), and
  a change on the phone (a permission) only on a click too.
