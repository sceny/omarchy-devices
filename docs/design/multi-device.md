# Devices, many at once: design

**Status:** proposal, revision 2, 2026-09-28. Nothing here is built yet.
Revision 2 folds in an independent adversarial UX review
([what changed](#15-what-revision-2-changed)).
**Decided** marks what the owner settled; **Open** marks what still needs a
decision (all listed in [Open decisions](#13-open-decisions)).

This takes Devices from *one phone, one pill, one page* to *any number of
devices, each a first-class thing with its own way of showing up*: the bar,
the panel, settings, the Connection page, calls and pairing, storage,
migration, and the order to build it in. Section 14 is the first version to
ship; the rest is where it grows.

---

## 1. Why

Today the plugin follows one device: one `deviceId`, one flat set of settings,
one pill, one page. A second device is an exception: it shows only in the
Devices section, only when there is a choice, and everything else belongs to
whichever device is followed.

With a phone and a tablet (or two phones, or another computer), the plugin
cannot answer:

- Which device does the bar show, and where does the others' news go?
- Why can a tablet not have its own sections and shortcuts?
- Where do I add or fix a second device while the first one works?

## 2. Principles

1. **Every device is first-class.** Each paired device has its own
   **profile**: what it shows, where, and how.
2. **Settings manage devices.** *(Decided.)* Everything about a device is set
   in Settings, on that device's own page.
3. **Each device decides how it shows in the bar.** *(Decided: per device.)*
4. **The bar never disappears.** Whatever the devices' choices, the widget
   always draws something to click (4.2). Everything else hangs off it.
5. **One rule for anything that shows more than one device:** the attention
   table (4.4). The bar, the tabs and the Connection page all follow it.
6. **The panel shows one device at a time.** Its page is that device's
   profile. Calls and pairing requests are the two things that come forward
   from any device.
7. **KDE Connect stays the source of truth, and its own notifications are
   not duplicated.** With the panel closed, KDE Connect already notifies a
   ringing call (*Incoming call from …*, *Mute Call*) and a pairing request
   (*Accept pairing*) on the desktop; the plugin marks the bar, it does not
   add a second popup.
8. **Each device looks the way its user named it.** *(Decided.)* A nickname
   and an icon, both the user's choice, used wherever the device appears.
9. **The main screen is for using the devices you have.** *(Decided.)* It
   shows the device (one) or the device tabs (several), and the gear.
   Nothing about setup or adding is always there; things come forward only
   while they need the user (5.4).
10. **Existing users see no surprise.** The new version reads today's
    settings as they are and changes only what the user changes (10).

## 3. Words

One name per thing, used the same way in the UI, the docs and IPC.

| Word | Means |
|---|---|
| **Device** | Anything paired with KDE Connect: phone, tablet, another computer, a TV. |
| **Profile** | One device's settings: nickname, icon, bar, sections, shortcuts, calls. |
| **Defaults** | What a device uses for any setting it has not changed, and what a new device starts with. |
| **Custom** | A setting a device changed away from the default, marked so, with *Reset*. |
| **Nickname** | The device's name in tabs, the bar and cards, chosen by the user; until set, the name KDE Connect reports. |
| **Icon** | The device's glyph, chosen by the user; until set, the one for its kind. |
| **Viewed device** | The one the panel shows right now. |
| **Tab** | One device in the panel header, shown only with two or more devices in the panel. |
| **Chip** | One device inside the pill: its icon, its marks, its indicators. |
| **Connection** | The page for this computer's checks, adding a device and pairing requests (6). Replaces today's *Setup* and the working names *Devices and connection*, *Connection and checks*. |
| **Attention** | Something a device wants the user to see (the table in 4.4). *Away* is not attention. |

"Devices" stays the product's name only; no section, page or group is called
Devices.

## 4. The bar

### 4.1 Each device picks how it shows *(Decided: per device)*

In the device's page in Settings, **In the bar**:

| Choice | What it does |
|---|---|
| **Always** | A chip in the pill, always (dimmed while away). |
| **With attention** | A chip only while it has attention (4.4). |
| **Never** | No chip, except while it rings (a call overrides the choice). Its pairing requests still mark the pill (4.4). |
| **Own pill** *(later: 14)* | A separate pill beside the main one, for this device alone. |

Each device also picks **its indicators** (today's Bar settings: connection,
battery, %, notification count, unread messages, now playing, bubble,
*battery only when low*). Their order stays one global order in the first
version (14).

```
 󰄜①  󰓶󰂃            phone: always, 1 new · tablet: with attention, low battery
```

- A chip's bubble sits on **its own** icon: a count always belongs to one
  device; nothing is summed.
- **Click** a chip: the panel opens on that device. **Middle click:** that
  device's messages. Chips are at least the size of today's pill glyph.
- **Keyboard:** the panel's hotkey opens on the first connected device; the
  tabs take it from there. IPC takes a device (11.2).
- **Tooltip:** one line per device and its attention.
- **Width changes** (a chip arriving or leaving) animate at `Model.MOTION`;
  nothing snaps.
- **Vertical bars:** chips stack along the bar, icon only, as today's
  vertical pill shows the glyph only.

### 4.2 The pill never disappears

When no chip qualifies (every device *with attention* and none has any, the
only device away and set *with attention*, KDE Connect stopped, nothing
paired), the pill shows **one resting glyph**:

| Situation | Resting glyph |
|---|---|
| Devices paired, none qualifying | The first device's icon, dimmed |
| Nothing paired | The generic devices glyph |
| KDE Connect stopped | The generic devices glyph, dimmed, with the gear dot's warning in its tooltip |

It is always clickable and always opens the panel. The first-run and
KDE-Connect-stopped screens are reached this way.

### 4.3 Own pills *(Decided in principle; deferred; Open: placement)*

Omarchy writes bar-widget settings by the widget's id (`updateEntryInline`):
every copy of the widget gets the same settings, so two copies cannot follow
two devices. An own pill is therefore drawn by the same widget, beside the
main pill, with the bar's usual gap: it looks separate but moves with it.
Placing pills apart needs a per-copy id from Omarchy (an issue there).
Because an own pill cannot be placed apart yet, it ships after the first
version.

### 4.4 Attention: every signal, every place

One table for everything that shows more than one device. A signal shows
only where its row says.

| Signal | Chip / resting glyph | Tab | Gear | Card over the panel | Panel closed |
|---|---|---|---|---|---|
| New notifications | Bubble with the count | Count | · | · | Bubble on the chip |
| Unread text messages | Count, if the device's indicators include it | Count, added to the tab's | · | · | As the chip |
| Ringing call | The ringing device always has a chip while it rings, whatever its choice, glowing on the ring beat | Glows | · | Call card | KDE Connect's own notification + the glow |
| Missed call | Missed-call mark | Missed-call mark | · | Call card until closed | Mark on the chip |
| Low battery | Urgent battery mark | Battery mark | · | · | Mark on the chip |
| Pairing request | Pairing mark on the resting or first chip | · | · | Pairing card | KDE Connect's own notification + the mark |
| Setup check failing | · | · | Dot | · | Tooltip of the pill |
| Away | Dimmed (chip set *Always*), else nothing | Dimmed | · | · | Dimmed or nothing |

- **Attention**, for a device set *With attention*: new notifications,
  unread messages (if counted), a ringing or missed call, low battery.
  **Away is not attention**: its absence is not news.
- **Marks are distinct glyphs**, not one dot: a missed call, a low battery
  and a pairing request each have their own, so a keyboard user reads them
  without a tooltip. The selected tab's details line says them in words.
- **Two calls at once:** one card, the newer call on top, and a line
  *Also ringing: Tab* under it.
- **A call and a pairing request at once:** the call card on top; the
  pairing card waits under it and is still there after the call (a request
  that expires meanwhile leaves with a toast, *Pixel 8's request expired*).

## 5. The panel

### 5.1 Header: the device, or one tab per device *(Decided)*

**One device in the panel: no tabs.** The header is today's: icon,
nickname, status line, gear.

```
 󰄜  S23                                                     ⚙
    󰂅 86% · Wi-Fi · 󰣶 LTE
```

**Two or more: a row of tabs above it.** One tab per device shown in the
panel (each device's *Show in panel* switch, on by default), in the device
order, side by side like the chips, with the same icons and nicknames.
Under the tabs, the same header, for the selected device.

```
 [󰄜 S23 ①] [󰓶 Tab 󰂃] [󱈸 Work]                               ⚙
 󰄜  S23 · Galaxy S23 Ultra
    󰂅 86% · Wi-Fi · 󰣶 LTE
```

An away device's details say what is known and offer the next step:

```
 [󰄜 S23] [󰓶 Tab] [󱈸 Work]                                    ⚙
 󰓶  Tab · Galaxy Tab S9
    Away since 14:05                          [Reconnect]
```

- **One component:** the one-device header is the tabs' header without the
  tab row. The name line is the nickname, followed by the full name when
  the two differ, in both layouts.
- **One to two devices:** the header's name rises into the first tab and the
  second tab slides in, at `Model.MOTION`; the reverse on the way back.
- **Tabs** are icon and nickname as set (8.2). **Marks** follow 4.4. Away:
  dimmed.
- **Which tab is selected on open:** the first *connected* device in the
  order; if none is connected, the first. A ringing call opens on its
  device. (Order is set in Settings; there is no separate pin.)
- **Show in panel:** a device switched off (the tablet sold last year)
  keeps its profile and its pairing but has no tab; Settings still lists
  it. After 30 days away, its Settings row suggests switching it off or
  unpairing; nothing happens on its own.
- **More tabs than fit:** the row scrolls sideways, the selected tab in view.
- **Keys** (main page only): `1`–`9` select a tab; `Shift+H` / `Shift+L` the
  previous and next. On the Messages page the tab row stays visible and
  clickable, and the keys stay the messages view's own (it takes text).
  Settings and Connection hide the tab row.
- **Selecting a tab** changes the page with the page transition, sliding
  towards the tab's side.
- **Reconnect** in the details runs the search (6.3 step 2) **in place**;
  the details line shows *Looking…* and then the result. It does not leave
  the page. *Why not?* (after a search that found nothing) opens the
  device's checks on its Settings page.

### 5.2 The page: one device, its profile

The page below the header is the viewed device's sections, in its order,
with its shortcuts. Capabilities still hide what the device cannot do (no
Messages on a tablet without a SIM).

- **Folded sections, last conversation, unread filter** are kept per device.
- **Fresh on every open:** the tab as in 5.1, the media carousel on the
  active player, search empty, nothing focused.
- **Acting on another device's attention** (a call card's *Text back* for
  the tablet while the phone is viewed) switches the view to that device
  first, with the page transition, then acts.

### 5.3 Everything view *(Open; later)*

An optional first tab, *Everything*: notifications from every device in one
list, each tagged with its device. The one place that mixes devices.

### 5.4 What comes forward only when needed

| When | What shows | Until |
|---|---|---|
| A device asks to pair | **The pairing card** at the top, above the tabs (it is about all devices, not the viewed one), pushing everything down (it grows in and out at `Model.MOTION`; covering the header hid the tabs it is about): icon, name, verification key (compare it with the device), *Accept*, *Reject*. Also KDE Connect's own notification. | Answered, withdrawn or expired |
| A device is away | Its details line, with *Reconnect* (5.1) | It is back |
| A call rings or was missed | The call card (7.1) | It ends, or is closed |
| A setup check fails | A dot on the gear | Fixed, or the check is ignored (6.2) |
| Nothing is paired | The panel opens on Connection | A device is paired |

The pairing card names the device and scripted calls never focus anything.
Unlike a toast, it is part of the panel while it lasts, above the tabs.

Adding a device needs no button on the main screen: pairing usually starts
on the new device (open the app, pick this computer), and the computer
answers with the pairing card. For the rest (installing the app, the
network), *Add a device* is in Settings (8).

## 6. Connection

A page of its own, like Messages: **this computer, adding a device, pairing
requests**. Per-device things (reconnect, checks, features, unpair) live on
the device's own page in Settings (8), so each device has one place.

**Ways in:** Settings (*Connection*, *Add a device*), the gear's dot (at the
failing check), the panel when nothing is paired, `page connection` over
IPC.

### 6.1 Layout

```
 CONNECTION                                                  ←
 THIS COMPUTER
  ✓ KDE Connect        Running · 26.08.1
  ✓ Firewall           Open to 192.168.1.0/24
  ✓ Network            Wi-Fi · 192.168.1.0/24
 PAIRING REQUESTS
  󰄜 Pixel 8            4E5A 3506                  [Accept] [Reject]
 ADD A DEVICE
  1  Install KDE Connect on it        Google Play ↗  F-Droid ↗  [QR]
  2  Join this Wi-Fi (192.168.1.0/24)
  3  Open the app and pick this computer; accept here
  Looking for new devices…   (new ones appear here with Pair)
```

*Pairing requests* shows only while there is one. The *Looking for new
devices* list searches while the page is open.

### 6.2 UX rules (Connection and every device page)

- **Every row has the same parts:** status icon · name · short status · one
  action. No row is a sentence built from pieces.
- **States are icons and short words**; times are data (*2 h ago*); at most
  one line of advice, under its row.
- **Detail on demand:** a row's detail opens in its fold (`FoldToggle` /
  `FoldBody`) when the user opens it; results never appear in the flow on
  their own.
- **Results are toasts.**
- **Fixes that change the system** (install, firewall) ask first and run
  only on a click.
- **A check can be ignored** (*Ignore* on a failing check the user does not
  want to fix, such as the firewall on a machine that uses Bluetooth only):
  it stops lighting the gear's dot; stored in settings; *Undo* on the row.

### 6.3 Reconnect and its checks *(Chosen in revision 2: the label **Reconnect**; the owner may revisit)*

*Reconnect* (in an away device's details, or its Settings page) runs:

| Step | Check | Shown as |
|---|---|---|
| 1 | This computer (KDE Connect running, firewall, on a network, KDE Connect's Wi-Fi link on) | That item and its fix |
| 2 | Search the network (`forceOnNetworkChange`), wait about 8 s | *Looking…*, then found or not |
| 3 | *(later)* Anything at the last address (ping, the neighbour table) | *Likely* not on this network, or asleep |
| 4 | *(later)* The app listening there (TCP 1716) | *Likely* the app is closed or stopped by battery saving |

- **Steps 3–4 run only on the same network as last time:** the same default
  gateway (and SSID) as when the device was last connected. On any other
  network the plugin never touches an address, so it never pings a stranger
  that happens to hold the same address.
- **Verdicts are likely causes, worded as such**, never certainties; the
  plugin never advises re-pairing on an inference. Device-maker advice
  (Samsung's *Unrestricted* battery use) shows only for that maker's
  devices.
- **Last seen** (link, address, gateway, when) is kept in the cache
  (`~/.cache/sceny.devices/`), so it survives a restart; with none, the
  details say *Not seen since this computer started*.
- **Opening the panel** on an away device runs step 2 once, at most once a
  minute. *(To verify: that a search does not disturb connected devices.)*

Facts behind the steps (kdeconnect-android `6d6eb6b`): the app listens on UDP
1716 and the first free TCP port 1716–1764; it announces itself (UDP
broadcast, mDNS) only on networks trusted in the app; newer Android needs a
local-network permission to broadcast.

### 6.4 Features per device *(later)*

On a connected device's Settings page: what works and what the phone must
allow (notifications, SMS, contacts, phone and call log, media), from what
its KDE Connect offers (#63).

## 7. Calls, notifications and messages with many devices

### 7.1 Calls

- A call from **any** device shows the call card over the panel, whatever
  device is viewed, naming the device by its nickname. The ringing device
  always has a chip while it rings (even set *Never*), glowing on the ring
  beat (`Model.RING_BEAT`).
- **Panel closed:** KDE Connect's own notification plus the glow (principle
  7). The plugin does not open the panel or raise a second popup.
- **Calls on or off** per device, in its profile.

### 7.2 Notifications

Per device, on its page, as today; other devices' attention shows on their
tabs and chips.

### 7.3 Messages

Per device: the messages view belongs to the viewed device. A message reader
runs per device only while needed (its messages page is open, or its
indicators count unread messages).

### 7.4 Media

Players are matched to a device by the device name KDE Connect puts in each
player's identity (*Spotify - Galaxy S23 Ultra*); the players' bus names do
not carry the device id (checked). Two paired devices with the same name
would share players, so Connection flags it: *Two devices are called Pixel
8: rename one in the KDE Connect app on it* (the name is the device's, set
on the device). Until renamed, neither shows media, rather than the wrong
one's.

## 8. Settings

*(Decided: settings manage devices.)*

### 8.1 One device: one flat page

With one device, Settings is today's page: its groups apply to that device,
with no *Defaults*, no *Custom* marks and no device list. *Nickname* and
*Icon* join the top, and *Connection* and *Add a device* the bottom.

### 8.2 Two or more devices

```
 SETTINGS                                                    ←
 DEVICES
   󰄜 S23      Galaxy S23 Ultra · Connected                    ›
   󰓶 Tab      Galaxy Tab S9 · Away 2 h                        ›
   ＋ Add a device                                            ›
 DEFAULTS FOR NEW DEVICES AND UNCHANGED SETTINGS              ›
 GENERAL
   Low battery     15 %
   Connection                                      1 to fix   ›
```

A device's row opens its page:

```
 SETTINGS › S23                                              ←
   Nickname        S23                  Short names keep the tabs narrow
   Icon            󰄜  [ choose ]
   In the bar      Always
   Show in panel   On
   Indicators      Bubble · Battery when low
   Sections        Shortcuts, Now playing, Notifications     Custom  ↺
   Shortcuts       Ring, Send files, Clipboard, Messages
   Calls           On
   Status          Connected · Wi-Fi · 86%        [Check]   (away: [Reconnect])
   Unpair
```

- **Order:** drag a device row by its grip, or Shift+K / Shift+J on it (no
  arrow keys: they always move the cursor). Dragging a tab sideways moves
  it too. The order is the tabs' and the chips'. Every other order in
  Settings (sections, bar indicators, shortcuts) drags the same way.
- **Identity is never inherited:** nickname, icon, *In the bar* and *Show in
  panel* belong to the device only; the rest may be *Custom* or default.
- **Custom** marks a changed setting; ↺ on it goes back to the default.
  *Reset all to defaults* (at the bottom) asks twice and never touches
  identity.
- **Lists merge with releases:** a device's custom section or shortcut list
  still gains a section or shortcut added in a later release, at its
  default place (as `normalizeSections` already does).
- **Going from one device to two:** the one device's settings become the
  defaults, and the new device starts from them; nothing is marked Custom.
- **Unpair** asks twice. Unpairing keeps the profile (pairing again brings
  it back); the profile goes when the user removes it from the device list.

### 8.3 Nickname and icon *(Decided: both the user's choice; Open: a length limit)*

- **Nickname:** the user's text. Settings recommends a short one. Blank means
  the name KDE Connect reports; line breaks are not allowed. *(Open: a
  typing limit, recommended 24 characters, so nothing ever needs cutting.)*
- **Icon:** picked from a grid of glyphs (phones, tablets, laptops,
  desktops, TVs, watches, and home, work, star, heart), with a live
  preview; until picked, the icon for the kind (`Model.DEVICE_KINDS`).
- **Used wherever the device appears:** tab, chip, cards, toasts, the OSD,
  Settings (with the full name beside it), tooltips.

### 8.4 Editing a device's page in place *(Decided)*

A device's sections and shortcuts are edited on its own page, not in
Settings: ✎ on the device's header turns the page into its editor. ✎ shows
only while the pointer is on that header, so the page has no chrome at rest;
a right-click on the page (KDE's *Enter Edit Mode* idiom) and `E` open it
too.

- Each section becomes a bar: its grip, its name, what it holds now (or
  when it would show), and its switch. Every section shows while editing,
  on or off, with something in it or not.
- Every shortcut shows: the chosen ones in order, with a −, dragged within
  the grid; the others dimmed, with a +. A click adds or takes one away.
- Moves glide like every order (`Reorder`, in a grid for the tiles).
- ✓ Done, `E` or Esc ends it; it is off on every open and on changing
  device. Changes go to the viewed device's profile.
- Settings keeps what has no place on the page: a device's page shows
  *Sections and shortcuts ›*, which opens this editor. *Defaults for all
  devices* keeps the sections and shortcuts, having no page of its own.

## 9. Starting points by device kind *(Open; later)*

A new device's defaults can depend on its kind (phone: calls and messages;
tablet: media; computer: clipboard, files, commands #9; TV: media, never in
the bar).

## 10. Storage and migration

### 10.1 Storage

One `shell.json` entry, as today (`updateEntryInline`). Today's flat keys
stay and **are the defaults**; profiles are a map by device id holding only
what differs; identity lives only in the profile:

```json
{
  "id": "sceny.devices",
  "barIndicators": ["battery", "bubble"],
  "batteryLowOnly": true,
  "sectionOrder": ["actions", "media", "notifications"],
  "shortcuts": ["ring", "share", "clipboard", "messages"],
  "showCalls": true,
  "lowBatteryPercent": 15,
  "deviceOrder": ["a1b2c3", "d4e5f6"],
  "ignoredChecks": [],
  "devices": {
    "a1b2c3": { "nickname": "S23", "bar": "always" },
    "d4e5f6": { "nickname": "Tab", "icon": "F04F6", "bar": "attention", "shortcuts": ["share", "clipboard"] }
  },
  "lastThread": { "a1b2c3": 9001 }
}
```

- `manifest.json` keeps describing the flat keys; `deviceOrder`, `devices`
  and `ignoredChecks` are documented in `docs/internals/` (the manifest
  schema cannot describe a map by device id, and the panel edits them).
- Device ids and nicknames are local configuration, never copied into the
  repository.

### 10.2 Migration: read, don't rewrite

- **Nothing is written on upgrade.** The new version reads today's keys as
  the defaults, and `deviceId` (if set) as the first place in the order.
  The file changes only on the user's next change, from the panel, as
  today. So no panel on any monitor writes on its own, and downgrading
  still finds the keys it knows.
- **The first device** (today's followed one) gets *In the bar: Always*
  **stored explicitly** on its first write, so reordering never changes how
  it shows.
- **What an existing user will see change** (listed in the release's
  *Upgrading* notes):
  - with two or more paired devices: tabs, and a chip per device set
    *Always* (the first) or *With attention* (the others);
  - the Devices section is gone from the main page (its jobs are in the
    tabs, the pairing card and Settings);
  - the pill keeps its place when the phone is away (dimmed resting glyph),
    as today.

## 11. How it is built

### 11.1 Files

| Part | Change |
|---|---|
| `bin/kdeconnect-bridge` | Little: `watch` already reports every device and, with #68, each device's calls. Later: `diagnose <device>` (6.3 steps 3–4). |
| `Model.js` | New, pure and tested with `node`: `resolveProfile`, `readSettings` (old keys as defaults), `chips` (with the resting glyph), `attention`, `openingDevice`, `connectionRows`. Most existing functions already take a device. |
| `Service.qml` | From `device` to `devices`: per-device notifications, players, calls, message readers when needed, last seen (cached). |
| `BarWidget.qml` | Draws chips (and later own pills) from `Model.chips`; never empty. |
| `Panel.qml` | The viewed device and its profile; the header (tabs from two devices); the pairing card; the gear's dot; the Devices section removed; pages: main, messages, settings, connection. |
| `SettingsView.qml` | One device: the flat page. Several: the device list, a device's page, Defaults, General. |
| `ConnectionPage.qml` | Replaces `SetupChecks.qml`. |
| `AGENTS.md` | Rewrite: the Devices section rule, *the battery is a detail* (per chip), *UI state persists* (per device), *settings are written only by the panel* (and never on upgrade), *a section shows when…* (per device). |

### 11.2 IPC takes a device

Every verb that acts on a device (`ring`, `sendFiles`, `sendClipboard`,
`messages`, `openThread`, `newMessage`, `media`, `volume`, …) takes an
optional device: its id or nickname. Without one, it acts on the viewed
device, else the one the panel would open on. New: `open <device>`,
`page connection`. Thread ids are per device; `openThread` without a device
means the viewed one's.

## 12. Build order

Each step ships on its own and never removes something before its
replacement is there.

| Step | Delivers | Keeps until later |
|---|---|---|
| 1 | Storage and `readSettings` (no writes on upgrade), `resolveProfile`, `chips`, `attention`, `openingDevice`; tests. No visible change. | Everything |
| 2 | The header (tabs from two devices, opening rule), the pairing card, per-device pages (sections, shortcuts, folds), IPC with a device, the pill's chips and resting glyph (*Always / With attention / Never*) | The Devices section's unpair (until step 3) |
| 3 | Settings: flat for one device; device list, device page, Defaults, nickname, icon, order, *Show in panel*, Unpair. The Devices section goes. | Today's setup page |
| 4 | Connection page (this computer, pairing requests, add a device), Reconnect step 2 in place, last seen cached, *Ignore* on checks. Takes over #69 / PR #70. | · |
| 5 | Later: own pills, Reconnect steps 3–4, features per device (#63), QR (#64), connect by address (#8), starting points by kind, Everything view, per-device indicator order | · |

PR #68 (calls) is compatible and merges on its own: its bridge keeps calls
per device already.

## 13. Open decisions

1. **Nickname length:** a typing limit (24 recommended) or none?
2. **Own pills:** keep for later (recommended), knowing they sit beside the
   main pill until Omarchy gives widget copies their own settings; file that
   Omarchy issue now?
3. **Everything view:** later or never?
4. **Starting points by kind:** later or never?
5. **Probing a device** (6.3 steps 3–4, same network only): acceptable under
   "KDE Connect is the source of truth", as diagnosis only?
6. **Version:** release steps 1–4 as 1.0.0?
7. **Show in panel after 30 days away:** suggest only (as written), or
   nothing at all?

## 14. First version

Steps 1–4 of the build order:

- one device looks and works as today, plus nickname and icon;
- two or more: tabs, a chip each (*Always / With attention / Never*), a pill
  that never disappears, per-device sections, shortcuts and folds;
- the pairing card; calls from any device (with #68);
- Settings: flat for one device, a device list and pages for several;
- the Connection page with Reconnect's search in place;
- IPC with a device; migration that writes nothing on upgrade.

Deferred: own pills, per-device indicator order, probing steps, features per
device, QR, connect by address, starting points by kind, Everything view,
*Apply to all devices* (dropped: it copied identity and wiped others'
settings; *Reset* per setting covers the need).

## 15. What revision 2 changed

From the adversarial review (all findings addressed; the reviewer's own
cut list was taken, except the icon picker, kept because two phones of the
same kind need telling apart):

| Review finding | Revision 2 |
|---|---|
| The bar could go empty; no way into the panel | Principle 4, 4.2: the resting glyph |
| *Away* was both attention and not news; missing signals | 4.4: one table, every signal and place; away is not attention |
| Migration wrote on upgrade and changed what users see | 10.2: read old keys as defaults, write on the user's change only, *Upgrading* notes |
| Calls and pairing only inside an open panel | Principle 7: KDE Connect's own notifications (verified: *Incoming call*, *Accept pairing*) plus marks; two calls; call over pairing |
| Opens on an away first tab; stale tabs forever | 5.1: opens on the first connected; *Show in panel* per device |
| IPC without a device; arrow keys; tab keys on other pages | 11.2; order by Shift+K/J only; keys per page |
| Four names for one page; per-device actions in two places | 3, 6: *Connection* for this computer and adding; everything per device on its Settings page |
| Defaults vs custom confusing; *Apply to all* destructive | 8.1 flat for one device; identity never inherited; *Apply* dropped; lists merge |
| Reconnect overclaimed; probing strangers; results pushing rows | 6.3: same network only, likely causes, cached last seen, runs in place; 6.2 folds |
| Build order removed things before replacing them | 12: each step keeps what it has not replaced |
| Media matched by name mixes same-named devices | 7.4: flagged in Connection, no media until renamed (the bus name carries no device id: checked) |
| Long nicknames | 8.3: no line breaks, blank means the KDE name; a length limit is Open |
| One-device header vs tabs header mismatch | 5.1: one name line in both (nickname · full name) |
| Chips appearing jiggle the bar | 4.1: width animates at `Model.MOTION` |
| Vertical bars | 4.1: chips stack, icon only |
| Tab dot means too many things | 4.4: distinct glyphs per mark; the details line says them |
| Gear dot nags for ignored checks | 6.2: *Ignore* per check |
| Demo preview inside real setup | Dropped from Connection (demo stays an IPC/doc tool) |
| Calls said to be the only interruption | Principle 6: calls and pairing requests |
