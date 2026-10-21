[Devices](README.md) › What's new

# What's new

Each version, newest first, grouped by what it touches. `omarchy plugin
update sceny.devices` brings the latest; each is a tag (`vX.Y.Z`) and a
GitHub release with these notes.

## 0.9.0 — 2026-10-21

### Highlights

- **Calls here** ([#59](https://github.com/sceny/omarchy-devices/issues/59)):
  answer and make calls with the audio on this computer, over Bluetooth. The
  card follows a call to its end: microphone, keypad, volume, a second call
  held or joined, music here paused meanwhile. Call back, or call from a
  conversation.
- **Contacts**: the phone's address book in the panel, two panes like
  Messages: a searchable list with each person's photo, and the full card.
  *Message* starts a text, *Call* opens the dialer on the phone, an email, an
  address and a website open in their app. Texts take their names from the
  same cards.
- **A failed restart after the clipboard setting is tried again**: when
  KDE Connect's clipboard plugin could not be started again after the plugin
  wrote `sendPassword=false`, nothing said it still ran on the old setting;
  the plugin now finishes the restart on its next look at the device
  ([#344](https://github.com/sceny/omarchy-devices/issues/344)).
- **Dismiss all**: a button beside the Notifications title clears them in
  one press, and Shift+Delete does the same from the keyboard
  ([#194](https://github.com/sceny/omarchy-devices/issues/194),
  [#252](https://github.com/sceny/omarchy-devices/issues/252)).
- **The plugin's adb runs on its own server**: the adb and scrcpy the plugin
  starts use a server in the plugin's runtime folder, not the one you use
  for your own work ([#320](https://github.com/sceny/omarchy-devices/pull/320)).
- **Settings opens without a freeze**: each group of rows built a hidden row for every row of the page, about twenty times over, so opening Settings stopped the panel for most of a second; each group now builds only its own rows, and a test fails when one does not ([#389](https://github.com/sceny/omarchy-devices/issues/389)).
- **Keys is a list over the page you are on**: `?` opens every key as an
  overlay instead of a page, so a key can be tried with the list in view.
  Each group folds with a one-line summary, the one for where you are is
  unfolded, descriptions are a few words, and each group's **Open** (or
  `Shift+O`) goes to its page or section and marks it for a moment
  ([#352](https://github.com/sceny/omarchy-devices/issues/352)).
- **A feature's switch works while KDE Connect is away**: an away device's rows no longer show every feature as away with the switch gone. A feature you turned off shows as off, the switch of one that is on turns it off, and a missing permission is allowed over the screen link when it reaches the device ([#373](https://github.com/sceny/omarchy-devices/issues/373)).
- **Dismissing the last notification no longer makes the section vanish**: the rows fade, the section folds closed, and only then is it gone, at the panel's own pace, as the Gallery does.
- **The All apps tile is laid out in its place**: coming back to the main page, the tile first showed at the end of the first PINNED row and glided to its place once the apps arrived; it now glides only when a pin or an unpin of yours moves it ([#369](https://github.com/sceny/omarchy-devices/issues/369)).
- **The widget loads with Qt 6.12**: Qt 6.12 shows a file only the types its folder's `qmldir` lists, and ours listed only the clipboard, so the bar widget and its panel did not load; every component is listed, and a test fails when one used by name is not ([#365](https://github.com/sceny/omarchy-devices/issues/365)).
- **Saving a nickname with Enter keeps the keys working**: the field is left before the row is rebuilt by the new name, so the page no longer logs an error and stops answering its keys ([#214](https://github.com/sceny/omarchy-devices/issues/214)).
- **Notification access reads as allowed right after the grant**: Android lists the listener a moment after it is enabled, so the grant is read back a few times before it is called not allowed ([#188](https://github.com/sceny/omarchy-devices/issues/188)).
- **A closed screen leaves no log behind**: closing a screen with no watcher running left its filtered scrcpy log in the runtime folder; the close now removes it ([#292](https://github.com/sceny/omarchy-devices/issues/292)).
- **Notifications asks for access on a new pairing**: the permissions are read once the screen state is known, and a fresh pairing had none until the Screen page was opened; the panel now reads it when it opens ([#200](https://github.com/sceny/omarchy-devices/issues/200)).
- **Unpairing closes the device's pages**: the From anywhere and the Screen and apps page of a device that was just unpaired stayed open on nothing; the panel now goes back to where the device's page was ([#260](https://github.com/sceny/omarchy-devices/issues/260)).
- **A closed panel gives the keyboard back to its keys**: a text field that held the keyboard when the panel closed still held it when the panel opened again, so the keys did nothing until a click ([#285](https://github.com/sceny/omarchy-devices/issues/285)).
- **Turning Gallery on gets storage access too**: the switch turned on from off set up the plugin's own step only; it now runs the package and the permission as well, and says what is left for you ([#189](https://github.com/sceny/omarchy-devices/issues/189)).
- **No error in the log at startup**: the panel read a device's app windows before its app list existed; it now waits for the list ([#199](https://github.com/sceny/omarchy-devices/issues/199)).
- **A conversation loads whole when a message arrives as it opens**: a live
  message for the open conversation moved the loaded count on before the
  history page came, and the page was then taken for another request and
  dropped, leaving only the newest message until the conversation was left
  and opened again. The page is now matched with what was asked.
- **Dismiss all says one thing when some stay**: when the phone ignored
  several notifications, each row raised its own "did not dismiss it" line;
  the press now says once how many stayed, and a single row's X keeps its
  own line ([#287](https://github.com/sceny/omarchy-devices/issues/287)).
- **A message notification opens its own conversation**: a sender whose
  name this computer does not know ("Name (Alert)"), or a short code that
  sits inside a longer number, could open another conversation, or the one
  left open before. The notification now finds its conversation by name,
  then by the exact number, then by the message itself, and opens none when
  it cannot tell: the list, searched for the sender.
- **The call button in a conversation shows only for a number you can
  dial**: a service's short code or a sender's name no longer gets one
  ([#335](https://github.com/sceny/omarchy-devices/issues/335)).
- **A media session is not a notification**: when KDE Connect does not
  export an app's player, its playback notification (Previous, Play, Next,
  not dismissable) showed in Notifications with no Now playing beside it.
  It is hidden by its shape, as the phone keeps it in its media area
  ([#350](https://github.com/sceny/omarchy-devices/issues/350)).
- **Passwords never leave with your own auto-share**: when you turned
  automatic sharing on for a device in KDE Connect, the copies a password
  manager marks still went to it. The plugin now also writes
  `sendPassword=false` when you set none, and keeps a `sendPassword=true`
  you wrote ([#286](https://github.com/sceny/omarchy-devices/issues/286)).
- **A call pauses every local player but the phone's**: the skip matched
  `kdeconnect` anywhere in a player's name, so a local app whose name merely
  contained it kept playing during a call. It now matches the phone players'
  exported prefix only
  ([#267](https://github.com/sceny/omarchy-devices/issues/267)).
- **Nothing scripted focuses a text field**: the scripted press of the Send
  text shortcut, the Nickname and From anywhere address rows, and a call
  card's Text back each put the cursor in a field; now only your own click
  or Enter does. A new check follows every IPC function through what it
  calls and fails on a focus without that gate
  ([#308](https://github.com/sceny/omarchy-devices/issues/308)).
- **The Contacts and Messages pages keep their key hints in view**: with
  the ask or a problem line above the page, it now takes the card's
  remaining height instead of a fixed 600 px, so the hints show on a 720 px
  screen without scrolling
  ([#332](https://github.com/sceny/omarchy-devices/issues/332),
  [#339](https://github.com/sceny/omarchy-devices/issues/339)).
- **The keyboard cursor reaches Unpair, Reset shortcuts and a pairing
  request**: in a device's Settings and in *For all devices*, `j` on the last
  row now shows the cursor there and scrolls the page to it
  ([#324](https://github.com/sceny/omarchy-devices/issues/324)).
- **The keyboard reaches the last row with the pointer at rest**: on the
  main page, Settings and All apps, a page that scrolled under a still
  pointer let the row beneath it take the cursor, so `j` looped among the
  upper rows and never reached Keys. A hover now moves the cursor only when
  the pointer moves ([#254](https://github.com/sceny/omarchy-devices/issues/254)).
- **New message suggestions follow the pointer, not the list**: typing a
  name changes the suggestions under a still pointer, and the row beneath it
  no longer takes the cursor from the keys. The check that guards every
  hover now reads every QML file and handlers of any layout
  ([#325](https://github.com/sceny/omarchy-devices/issues/325)).
- **A resting pointer never takes the cursor in Messages or Contacts**,
  whatever it touched last: the lists now read the panel's one pointer
  position instead of keeping their own
  ([#327](https://github.com/sceny/omarchy-devices/issues/327)).
- **A resting pointer never takes the cursor on the main page or in
  Settings either**: a pointer move over a header or a gap was kept until
  the next row asked, so a fold that moved content under a still pointer
  let that row take the cursor. A hover now runs only when the very event
  that brought it is a move
  ([#330](https://github.com/sceny/omarchy-devices/issues/330)).
- **From anywhere**: the phone in the panel away from home, through Tailscale
  or NordVPN Meshnet, or an address you type. Its page says how it is
  connected now.
- **Sound, per window** ([#129](https://github.com/sceny/omarchy-devices/issues/129)):
  an open app and the Screen shortcut say where their sound plays (Here, On
  the phone, Both), with its volume here.
- **Setup that gets out of the way**: Settings shows no plumbing. With one
  device it is that device's page: what it shares with this computer, a
  switch each. What a feature needs is asked where you use it. The first run
  is one card: one password installs everything, starts KDE Connect and goes
  on to Add a device.
- **One card for a problem, and it closes**: whatever failed shows in one
  place under the device header (*Fix*, *Details*, *Fix with AI*), ✕ folds it
  away until something new breaks, and a red dot stays on the gear, section,
  shortcut and page it affects.
- **Back goes where you came from**: the pages form one stack. Esc and the
  back arrow return to the page you left, and a **Home** button (`0`) goes to
  the main page from two pages deep.
- **The panel opens at once**: a click on the chip draws the main page on the
  first frame, with no wait.
- **Private text stays private**: call numbers, keypad tones and contact
  searches no longer go on a command line, and Fix with AI names a device by
  its kind and quotes every detail as data.
- **A hidden test rig** (`dev/rig`): a second shell and a small Android
  emulator paired to a private KDE Connect, so changes are tried without
  touching the desktop or a real phone
  ([development](docs/internals/development.md#the-test-rig)).
- **Contacts asks for contacts, Messages does not**: the permission to read
  contacts is asked on the Contacts page, with *Allow* when the plugin can
  grant it, instead of on the Messages page where texts were the errand.
  Messages is whole with numbers instead of names; if contacts worked and
  stopped, both pages still show that problem. Searching a new message by
  name offers the same *Allow*. A Contacts page with the permission given and
  no cards says so (*No contacts on Pixel 8 yet*) (#272).
- **The on-screen display names nothing a device sent**: with no panel
  open, a result shows in Omarchy's display, whose line any local user can
  read. It now says "Saved to Pictures", "The app is open" or "Ringing the
  device", never a received file's name, an app's label or the device's
  name; the panel's toast keeps the full text.
- **Hardening**: contact fields are capped, and the firewall rules open KDE
  Connect's ports to private ranges only.
- **A missed call offers Calls here**: while it is not set up, the missed-call
  card says *Call back from here* with **Set up**, which
  carries the steps on by itself (a password card first when root is needed,
  Omarchy's Bluetooth to pair the phone, *Connect* when it dropped). *No
  thanks* turns Calls here off. The ringing card is unchanged.
- **More hardening**: the bridge's text commands (ping, text, url, dial)
  take their text on standard input only, and refuse it on the command line.
  A file opened from a device's storage must be a regular file inside that
  storage and within the cache's size limit, and is copied in bounded steps.
  The build's checks for these are stricter, and the text field's selection
  rules are now tested by running the field. Smaller: the conversation list
  finds a thread without scanning, and an album-art decode that cannot start
  no longer holds a slot.
- **Hardening, mesh and files**: a mesh peer is remembered by its id, not its
  name; the screen's stills and the messages folder are private from the start;
  Omarchy's folder from the environment is used only when root owns it; the CI
  actions are pinned to commits and kept current. A contact's value you open
  goes on the opened program's command line, now said in the security page.

### Issues

- [#8](https://github.com/sceny/omarchy-devices/issues/8) Reach devices over Tailscale or a custom address
- [#59](https://github.com/sceny/omarchy-devices/issues/59) Answer and place calls with the audio on the computer (Bluetooth hands-free)
- [#119](https://github.com/sceny/omarchy-devices/issues/119) Networking: one reliable path to each device, at home and away (mesh, USB, Bluetooth, firewall)
- [#122](https://github.com/sceny/omarchy-devices/issues/122) Notification click opens exactly what it is about, as Phone Link does (investigation)
- [#129](https://github.com/sceny/omarchy-devices/issues/129) Sound: where a device's sound plays, per window, from the plugin
- [#152](https://github.com/sceny/omarchy-devices/issues/152) Screen and apps off still shows the Screen shortcut and the Apps section
- [#153](https://github.com/sceny/omarchy-devices/issues/153) Problems: one fixed card that closes, red dots where the effect is, an ask on use
- [#159](https://github.com/sceny/omarchy-devices/issues/159) Settings shows "Everything works" although the rules say it shows nothing while everything works
- [#160](https://github.com/sceny/omarchy-devices/issues/160) MessagesView: binding loop on a picture message's "picture" property
- [#171](https://github.com/sceny/omarchy-devices/issues/171) Call numbers, keypad tones and contact searches still go on the bridge's command line
- [#172](https://github.com/sceny/omarchy-devices/issues/172) Diagnostics: a failing check with three buttons cuts its name and wraps its detail
- [#175](https://github.com/sceny/omarchy-devices/issues/175) First run: KDE Connect is not started after the install, so the card never goes on to Add a device
- [#176](https://github.com/sceny/omarchy-devices/issues/176) First run: the password card shows two of the seven actions, one cut off mid-line
- [#177](https://github.com/sceny/omarchy-devices/issues/177) Gallery shows a problem on a fresh pairing, before the user has used it
- [#178](https://github.com/sceny/omarchy-devices/issues/178) Gallery keeps saying to allow storage after the plugin has granted it
- [#188](https://github.com/sceny/omarchy-devices/issues/188) Notification access: Allow reads back as not allowed right after the grant landed
- [#189](https://github.com/sceny/omarchy-devices/issues/189) Gallery switch turned on from off enables the plugin but does not grant storage; nothing says what is left
- [#191](https://github.com/sceny/omarchy-devices/issues/191) Bridge `watch` leaves its `ip -o monitor address` child running when it exits
- [#194](https://github.com/sceny/omarchy-devices/issues/194) Clear all notifications
- [#199](https://github.com/sceny/omarchy-devices/issues/199) Startup: TypeError 'appWindowsOf' of null at Panel.qml allApps binding
- [#200](https://github.com/sceny/omarchy-devices/issues/200) Cold pairing: Notifications ask does not show until the device's screen state has been read
- [#201](https://github.com/sceny/omarchy-devices/issues/201) dev/soak ignores RIG_TMP_ROOT (cannot find a rig started with a custom root)
- [#203](https://github.com/sceny/omarchy-devices/issues/203) Show the panel's keyboard keys in the panel
- [#214](https://github.com/sceny/omarchy-devices/issues/214) Settings: saving a nickname with Enter logs 'root is not defined' and the page's keys stop
- [#246](https://github.com/sceny/omarchy-devices/issues/246) Notifications: folding moves the summary's ellipsis when the dismiss-all button hides
- [#250](https://github.com/sceny/omarchy-devices/issues/250) Keys page: a test that fails when Model.KEYS and the key handlers drift apart
- [#252](https://github.com/sceny/omarchy-devices/issues/252) Notifications: a key for dismiss all
- [#254](https://github.com/sceny/omarchy-devices/issues/254) Settings: with the pointer resting on the panel, the keys cannot reach the last rows (the cursor jumps back as the page scrolls)
- [#256](https://github.com/sceny/omarchy-devices/issues/256) Keys page: compact rows with key caps, and each control's tooltip names its key
- [#259](https://github.com/sceny/omarchy-devices/issues/259) public-text check: close three gaps and three false positives found in review of #257
- [#260](https://github.com/sceny/omarchy-devices/issues/260) Unpairing a device leaves its From anywhere or Screen and apps page open
- [#262](https://github.com/sceny/omarchy-devices/issues/262) Panel edits made in demo mode are written to the real shell.json entry
- [#264](https://github.com/sceny/omarchy-devices/issues/264) Rig: IPC hooks for the away card's Why? and a lost From anywhere address
- [#267](https://github.com/sceny/omarchy-devices/issues/267) Calls: the player skip for a call matches 'kdeconnect' anywhere in the bus name
- [#272](https://github.com/sceny/omarchy-devices/issues/272) Contacts: the Contacts page asks for contacts, Messages no longer does
- [#276](https://github.com/sceny/omarchy-devices/issues/276) Public-text check: a sentence with an exempting word still hides a leak in the same sentence
- [#282](https://github.com/sceny/omarchy-devices/issues/282) MessagesView: binding loop at line 1203 when a conversation opens (still on 0.8.3 to 0.8.5)
- [#285](https://github.com/sceny/omarchy-devices/issues/285) Panel: keyboard focus goes to keyCatcher when the panel closes
- [#286](https://github.com/sceny/omarchy-devices/issues/286) Clipboard: a user's own autoShare=true still sends passwords (write sendPassword=false when absent)
- [#287](https://github.com/sceny/omarchy-devices/issues/287) Notifications: dismiss all raises one failure toast per row
- [#288](https://github.com/sceny/omarchy-devices/issues/288) Rig check devices-screen-window: no scrcpy window within 30 s on a cold emulator (flake)
- [#289](https://github.com/sceny/omarchy-devices/issues/289) Sandbox: two commands on one store collide (verify-clean fails on the other's live container)
- [#290](https://github.com/sceny/omarchy-devices/issues/290) Sandbox: run_cleanup is not trapped on HUP, so a vanished caller can leave a container
- [#291](https://github.com/sceny/omarchy-devices/issues/291) Sandbox: hostile-test keeps its work under $TMPDIR and loses its result when the scratch directory goes
- [#292](https://github.com/sceny/omarchy-devices/issues/292) Screen: the filtered scrcpy log stays in the runtime directory after a bridge-only screen-close
- [#304](https://github.com/sceny/omarchy-devices/issues/304) dev/release-prepare runs the freeze check and refuses a release while main is frozen
- [#306](https://github.com/sceny/omarchy-devices/issues/306) Releasing: a class is named by its mechanism first; a pass carries forward only on an identical tree
- [#308](https://github.com/sceny/omarchy-devices/issues/308) IPC pressShortcut, pressSetting and pressScreenAction can focus a text field
- [#309](https://github.com/sceny/omarchy-devices/issues/309) Review list: every line names the tests that check it; lints for logs, images, root and listeners
- [#317](https://github.com/sceny/omarchy-devices/issues/317) release-prepare: an urgent fix is refused when GitHub cannot be read; --check-freeze fails outside the repository
- [#324](https://github.com/sceny/omarchy-devices/issues/324) Settings: the keyboard cursor on Unpair and Reset shortcuts is not drawn and the page does not scroll to it
- [#325](https://github.com/sceny/omarchy-devices/issues/325) Hover-needs-a-pointer-move check misses block handlers and the Messages suggestions list
- [#327](https://github.com/sceny/omarchy-devices/issues/327) Messages: a resting pointer can still take the cursor once when it last moved outside the lists
- [#330](https://github.com/sceny/omarchy-devices/issues/330) Main page: a resting pointer can still take the cursor when content moves under it after it last moved over a header
- [#332](https://github.com/sceny/omarchy-devices/issues/332) Contacts: the key-hint line is below the fold on a 720 px screen while the ask shows
- [#333](https://github.com/sceny/omarchy-devices/issues/333) Demo: a contacts permission that broke, so the problem on Contacts and Messages can be seen
- [#335](https://github.com/sceny/omarchy-devices/issues/335) Messages: the header call button shows for short-code senders, which cannot be dialled
- [#339](https://github.com/sceny/omarchy-devices/issues/339) Messages: the key-hint line is cut off at the bottom when a note shows above the page
- [#344](https://github.com/sceny/omarchy-devices/issues/344) Clipboard: a failed restart after writing sendPassword=false is never retried for a device with its own auto-share
- [#350](https://github.com/sceny/omarchy-devices/issues/350) A phone's media session shows as a notification with no player in Now playing
- [#365](https://github.com/sceny/omarchy-devices/issues/365) Bar widget does not load with Qt 6.12: qmldir lists only Clipboard
- [#368](https://github.com/sceny/omarchy-devices/issues/368) Sandbox: verify-clean reads processes host-wide, so another store's run fails it and the lock test
- [#369](https://github.com/sceny/omarchy-devices/issues/369) Apps: the All apps tile jumps to its place after going to Messages and back
- [#373](https://github.com/sceny/omarchy-devices/issues/373) Settings: a feature's switch and its permission are blocked while KDE Connect is away, though other gateways serve them
- [#376](https://github.com/sceny/omarchy-devices/issues/376) Sandbox: verify-clean process check misses a store path with regex characters and matches a sibling store
- [#384](https://github.com/sceny/omarchy-devices/issues/384) Sandbox: hostile-test's interrupt trap does not exit, so a signal mid-run disarms the rest of the test
- [#385](https://github.com/sceny/omarchy-devices/issues/385) Sandbox: hostile-test step 16 fails while another run's session is live on the shared store
- [#389](https://github.com/sceny/omarchy-devices/issues/389) Opening Settings from the main page freezes the panel for about half a second
- [#391](https://github.com/sceny/omarchy-devices/issues/391) AppPinRow: the All apps tile's glide guard throws ReferenceError (glides is not defined), so its pinsKnown check never runs (#372)
- [#392](https://github.com/sceny/omarchy-devices/issues/392) Sandbox: hostile test step 16 does not judge the out-dir runs or the dev pull's containers

### Pull requests without an issue

- [#142](https://github.com/sceny/omarchy-devices/pull/142) Setup that gets out of the way: asked where you use it, no plumbing in Settings
- [#143](https://github.com/sceny/omarchy-devices/pull/143) Contacts: the phone's address book in the panel
- [#144](https://github.com/sceny/omarchy-devices/pull/144) Contacts: the list shows each person's photo
- [#145](https://github.com/sceny/omarchy-devices/pull/145) Contacts: an email, an address and a website open in their app
- [#146](https://github.com/sceny/omarchy-devices/pull/146) Contacts: say what Google Contacts holds, and find a card there
- [#147](https://github.com/sceny/omarchy-devices/pull/147) Contacts: a photo is round, like the initial it replaces
- [#148](https://github.com/sceny/omarchy-devices/pull/148) Nested navigation: Back returns to where you came from, Home from two deep
- [#149](https://github.com/sceny/omarchy-devices/pull/149) Hidden test rig with a small Android emulator
- [#150](https://github.com/sceny/omarchy-devices/pull/150) AGENTS: the owner's install follows develop by timer
- [#151](https://github.com/sceny/omarchy-devices/pull/151) The panel opens at once
- [#157](https://github.com/sceny/omarchy-devices/pull/157) Release procedure: security review, emulator regression, owner's go
- [#158](https://github.com/sceny/omarchy-devices/pull/158) Docs for 0.9: Contacts setup, limits for Calls and Contacts, CHANGELOG issues
- [#164](https://github.com/sceny/omarchy-devices/pull/164) dev/loaded-code: check the shell runs the plugin's files
- [#166](https://github.com/sceny/omarchy-devices/pull/166) releasing.md: release security review is a threat-model review
- [#167](https://github.com/sceny/omarchy-devices/pull/167) Releasing: the owner is asked only when every check passed on the exact SHA running on their machine
- [#179](https://github.com/sceny/omarchy-devices/pull/179) Rig: a cold computer for the cold-install check
- [#180](https://github.com/sceny/omarchy-devices/pull/180) Releasing: a security FAIL rejects the candidate; whole-plugin review every release
- [#185](https://github.com/sceny/omarchy-devices/pull/185) Fix with AI: fence device-supplied names and details
- [#190](https://github.com/sceny/omarchy-devices/pull/190) Albums row: remove the unattributed stackAfter warning
- [#192](https://github.com/sceny/omarchy-devices/pull/192) dev/soak: the 30-minute resilience soak driver
- [#208](https://github.com/sceny/omarchy-devices/pull/208) CI: run the marketplace's validation and security baseline on PRs into main
- [#209](https://github.com/sceny/omarchy-devices/pull/209) dev/release-prepare: a release PR has its version on the first push
- [#210](https://github.com/sceny/omarchy-devices/pull/210) Class lints for private text on argv (C1) and the clipboard read without a paste (C2)
- [#212](https://github.com/sceny/omarchy-devices/pull/212) isPhonePlayer: anchor to KDE Connect's exact bus-name prefix
- [#216](https://github.com/sceny/omarchy-devices/pull/216) release.yml: check and publish jobs, no expression under permissions
- [#217](https://github.com/sceny/omarchy-devices/pull/217) Class lint C1: .exec( is a sink; an allowed bare name is checked where it is given a value
- [#218](https://github.com/sceny/omarchy-devices/pull/218) Releasing: the release template, the status page and the finding classes
- [#220](https://github.com/sceny/omarchy-devices/pull/220) AGENTS.md: the contributor code rule
- [#221](https://github.com/sceny/omarchy-devices/pull/221) dev/sandbox: run one exact contributor commit in a rootless podman container
- [#226](https://github.com/sceny/omarchy-devices/pull/226) Standing texts say what is: AGENTS.md and docs/internals
- [#228](https://github.com/sceny/omarchy-devices/pull/228) diagnose-panel: a KDE Connect fault is handled in the plugin
- [#238](https://github.com/sceny/omarchy-devices/pull/238) dev/sandbox: the rig's compositor starts in the container, so hostile-test phase 14 runs
- [#239](https://github.com/sceny/omarchy-devices/pull/239) dev/sandbox: hostile-test tells the rig's own X socket from a host one
- [#240](https://github.com/sceny/omarchy-devices/pull/240) dev/sandbox dev: a session for Sceny's own tree, version pins, recordings
- [#243](https://github.com/sceny/omarchy-devices/pull/243) All development and testing in the sandbox
- [#244](https://github.com/sceny/omarchy-devices/pull/244) Sandbox docs follow-up: --session, --timeout, rig sync
- [#247](https://github.com/sceny/omarchy-devices/pull/247) Review: every non-blocking finding becomes an issue; public comments hold no run details
- [#249](https://github.com/sceny/omarchy-devices/pull/249) Review: an item not checked is checked before the merge or tracked
- [#257](https://github.com/sceny/omarchy-devices/pull/257) CI: fail the build on public text that names our setup, leaves an item with no issue, or names another repo's issue bare
- [#258](https://github.com/sceny/omarchy-devices/pull/258) Sandbox: one image per repository on a common base; omarchy-paperclipai and dev/soak run in it
- [#270](https://github.com/sceny/omarchy-devices/pull/270) CI: the release brings develop level with a public-text status on the commit
- [#280](https://github.com/sceny/omarchy-devices/pull/280) Harden mesh peer matching, stills, cache folder and Omarchy path; pin CI actions
- [#296](https://github.com/sceny/omarchy-devices/pull/296) Class lint: allowed parameter names are checked where they are given; no shell strings in scripts
- [#299](https://github.com/sceny/omarchy-devices/pull/299) Hardening: text commands refuse argv, bounded device-file copy, text field run in tests
- [#318](https://github.com/sceny/omarchy-devices/pull/318) Open from the device: check the opened file's own path against the mount
- [#320](https://github.com/sceny/omarchy-devices/pull/320) Run the plugin's adb and scrcpy against its own adb server
- [#322](https://github.com/sceny/omarchy-devices/pull/322) Calls: the missed-call card offers Calls here while it is not set up
- [#334](https://github.com/sceny/omarchy-devices/pull/334) Rig: drop show, hide and up --visible; the rig is always hidden
- [#348](https://github.com/sceny/omarchy-devices/pull/348) Messages: a message notification opens its own conversation or none
- [#349](https://github.com/sceny/omarchy-devices/pull/349) Messages: a conversation loads whole when a message arrives as it opens
- [#353](https://github.com/sceny/omarchy-devices/pull/353) Keys: an overlay over the current page, folding groups, each with Open
- [#367](https://github.com/sceny/omarchy-devices/pull/367) Sandbox: install quickshell from Omarchy repository to match host
- [#370](https://github.com/sceny/omarchy-devices/pull/370) Panel: Notifications fades and folds away when the last one goes
- [#388](https://github.com/sceny/omarchy-devices/pull/388) Sandbox: drop the unused [omarchy] pacman repository

### Upgrading

- **The tabs can change order after the upgrade**: a stored `deviceOrder` is
  now honoured, so devices you reordered before show in that order.
- **A firewall problem card can appear after the upgrade**, with *Fix*, when
  the firewall does not let KDE Connect in.
- **The firewall's fix** opens KDE Connect's ports to every private network
  (home, office) and to your mesh, instead of only the network you were on.
  Rules you have stay.
- **This computer** has a *Mesh network* row (optional).
- **Calls here is on for every device**: it needs the phone paired over
  Bluetooth, and its switch on a device's page turns it off for that device.
  Until it is set up, a missed call offers *Call back from here*.
- **The sound setting has a third place**, *Both* (Android 13); an open
  app's tile keeps its own choice. A stored `here` or `phone` reads as before.
- **The plugin writes `sendPassword=false`** into KDE Connect's clipboard
  settings for each paired device that has no choice of its own, as it
  already does for `autoShare`; a value you wrote there stays.
- **`?` opens the keys as an overlay** over the page you are on, no longer a
  page of their own.
- Nothing else in your settings is rewritten; new keys (`closedProblems`)
  appear on your next change.

## 0.8.5 — 2026-10-14

### Fixes

- An attachment you did not ask for no longer opens: only the attachment you clicked is opened, and a picture is always opened as the copy decoded in the sandbox, whatever name or type the phone gives it (marketplace review omacom/omarchy-plugin-marketplace#10096).
- A gallery photo's copy button now copies the same sandbox-decoded picture that opening it shows, never the phone's file as it came; a picture that cannot be read safely is not copied, and any other file is copied from a copy made here (marketplace review omacom/omarchy-plugin-marketplace#10096).

## 0.8.4 — 2026-10-14

### Fixes

- A paste no longer makes the shell read the clipboard unbounded or wait on it: the text is read when you paste, outside the shell, with a size limit and a deadline, and a slow or failed read inserts nothing (marketplace review omacom/omarchy-plugin-marketplace#10096).
- The shell never takes part in a clipboard transfer: copy, cut, paste and selecting text go through one door that runs the system's clipboard tools outside the shell, with a size limit and a deadline, so a program that never reads what you copied (or never finishes what it pastes) cannot freeze the bar. In a field, Ctrl+C, Ctrl+X, Ctrl+V, Ctrl+A and Shift with the arrow keys work as before, and the mouse still places the cursor and selects (a drag, Shift+click, a word on a double click, all on a triple). A message in a conversation is copied by a double click; it can no longer be selected by dragging. A gallery photo is no longer dragged out of the panel: use its copy button, then paste it where you want it (marketplace review omacom/omarchy-plugin-marketplace#10096; `docs/architecture/001`).

## 0.8.3 — 2026-10-13

### Highlights

- **Text fields never read the clipboard until you paste**: a field is
  built on a text edit, which asks only which formats the clipboard offers
  and reads its text when you paste (Ctrl+V, Shift+Insert). Focusing a
  field, or another program copying while one has the keyboard, makes the
  shell read nothing. Typing, accented characters, Esc's steps, drafts and
  suggestions work as before; Enter stops at the field. A field holds at most
  32767 characters, as before, and a paste is cut to that before it is
  inserted, so a huge paste or a line-broken one is instant instead of
  stopping the shell. Middle-click paste and dropping text onto a field no
  longer insert anything.
- **A window is found by its exact title**: opening the device's screen or
  an app focuses an open window by its address and otherwise starts it
  directly, with each part of the command kept as it is.
- **Clipboard: a copy leaves on your click**: the Clipboard shortcut is the
  only way a copy is sent to a device. The plugin turns KDE Connect's
  automatic sharing off for each paired device that has no choice of its
  own, and leaves a choice you made there alone. `docs/security.md` says so.
- **Call details are kept short**: a caller's name and number are cut to
  the same length as other device text before they are used.

### Issues

- [#137](https://github.com/sceny/omarchy-devices/issues/137) Marketplace review: omacom/omarchy-plugin-marketplace#10096 (a focused text field made the shell read the clipboard's whole text)

## 0.8.2 — 2026-10-11

### Highlights

- **Text fields no longer read the clipboard while they are not in use**: a
  field is editable only while it has the keyboard, so a hidden composer,
  reply or search field no longer makes the shell read whatever another
  program put on the clipboard, however large. Typing, Esc's steps, drafts
  and suggestions work as before.
- **No typed text or clipboard in a log**: the screen window's log keeps only
  the two lines that tell the plugin the phone turned or folded. It is kept in
  memory (`$XDG_RUNTIME_DIR`), readable by you alone, and removed when the
  window closes; logs an earlier version left in the cache are removed.
- **Text from a device is capped**: notifications (title, text, the newest
  100, the newest 50 messages of a conversation), text messages, app names and
  contact files are cut to a size no real device reaches before they reach the
  panel.
- **A track's art is read only from KDE Connect's art cache**, one picture at a
  time per player.
- **The cache folder is yours alone** (`~/.cache/sceny.devices`, mode 0700), and
  the screen's stills no longer fall back to `/tmp` without a runtime folder.

### Issues

- [#170](https://github.com/sceny/omarchy-devices/issues/170) Text fields read the clipboard on every change, before any paste

### Upgrading

- Nothing in your settings changes.

## 0.8.1 — 2026-10-10

### Highlights

- **Private text stays off command lines**: a reply to a notification, a
  text or link sent to the phone, a ping's message and a number to call back
  reach the plugin's helper over stdin, never as command-line arguments,
  which any local process can read. The one-time code for pairing a phone's
  screen link is never on a command line either.

### Issues

- [#162](https://github.com/sceny/omarchy-devices/issues/162) The adb pairing password is on two command lines (qrencode, adb pair)
- [#137](https://github.com/sceny/omarchy-devices/issues/137) Marketplace review of 0.8.0: a notification reply's text was a command-line argument

### Upgrading

- Nothing in your settings changes. The call-back notice no longer repeats
  the number.

## 0.8.0 — 2026-10-05

### Highlights

- **Screen**: the phone's screen on your desktop, docked under its chip in
  the phone's own shape and turning as you turn it, or as a window; your
  mouse and keyboard, the clipboard both ways, files dropped on it. Set up
  from the panel, once.
- **Apps**: each of the phone's apps in a window of its own, tiled with
  the rest, with its icon; pinned and recent rows, All apps with search,
  a notification's app opened in a window; Shift+Enter pops one out.
- **Setup that just works**: a device's page says what it can do, and
  one switch per feature does every step the plugin can, here and on the
  phone, then carries on by itself after the one step left to you. The
  panel installs what the computer is missing; KDE Connect's own app is
  no longer needed.
- **Settings in one shape**: it starts with whether everything works and
  lists each problem once, where its cause is, with *Fix all* and *Fix
  with AI*; My devices, For all devices, This computer. A red line on the
  main page says when something needs you.
- **A password only for what is shown**: a card says why and lists every
  package and firewall rule before the prompt; only that runs.
- **Repairs by itself**: the gallery after a phone restart, notifications
  dismissed while the device was away or gone quiet after pairing again,
  the screen once the phone is back; a device the phone's link lost while
  its screen still answers keeps its screen and apps, and one *Fix* finds
  it again.
- **Fix with AI**: your default coding agent opens on a problem, as
  Omarchy opens it, with the plugin's guide; what it fixes that the
  plugin's fix missed, it offers to report, with nothing private in it.
- **Docs**: one page per feature, a Setup section, Security and privacy.

### Issues

- [#2](https://github.com/sceny/omarchy-devices/issues/2) Screen mirroring with scrcpy
- [#116](https://github.com/sceny/omarchy-devices/issues/116) Phone apps in their own windows
- [#126](https://github.com/sceny/omarchy-devices/issues/126) Setup that just works: one model of sources and features, Settings for it
- [#128](https://github.com/sceny/omarchy-devices/issues/128) Setup items: features from the items they need, sources as modules
- [#121](https://github.com/sceny/omarchy-devices/issues/121) Troubleshooting that fixes itself, for every capability
- [#63](https://github.com/sceny/omarchy-devices/issues/63) Setup checks name the phone permission a feature is missing
- [#101](https://github.com/sceny/omarchy-devices/issues/101) Fix with AI: Omarchy's agent on the plugin's errors
- [#99](https://github.com/sceny/omarchy-devices/issues/99) Photos could not read the phone, and KDE Connect's mount error popped up again and again
- [#4](https://github.com/sceny/omarchy-devices/issues/4) Notifications dismissed on the device stayed in the panel
- [#95](https://github.com/sceny/omarchy-devices/issues/95) No notifications after unpairing from the computer and pairing again
- [#52](https://github.com/sceny/omarchy-devices/issues/52) A hidden System UI "1 more notification" showed in the panel
- [#33](https://github.com/sceny/omarchy-devices/issues/33) Now playing kept a player the phone had hidden
- [#31](https://github.com/sceny/omarchy-devices/issues/31) The messages resync after a KDE Connect restart, checked

### Pull requests without an issue

- [#125](https://github.com/sceny/omarchy-devices/pull/125) Sections: one header height, folds that fade alike; Apps polish
- [#130](https://github.com/sceny/omarchy-devices/pull/130) Docs for 0.8, and found by what it does
- [#132](https://github.com/sceny/omarchy-devices/pull/132) Docs: features for show, setup as its own section, security and privacy
- [#133](https://github.com/sceny/omarchy-devices/pull/133) Docs: features as features; Built on at the README's end

### Upgrading

- **Settings has one shape** with one device or many: the status, My
  devices (your device is in the list; its own settings are on its page),
  For all devices with two or more, This computer (once Connection). The
  KDE Connect settings row is gone. Nothing in your settings is
  rewritten; new keys appear on your next change.
- **Apps** joins your saved order of sections, switched on, and shows
  once a device's screen is set up. **Screen** joins the device's
  shortcuts when its screen is first set up, once.
- **New, per device:** *Opens under the bar* for the screen, an app's
  sound here or on the phone, and the Screen and apps switch; all on in
  the ways they were.
- **New optional packages**, installed from the panel on a click, after a
  card: scrcpy, android-tools and android-udev for the screen and apps;
  sshfs for the gallery.

## 0.7.0 — 2026-10-02

### Highlights

- **Several devices**: a tab and a chip each, and settings for each one.
- **Calls** ring in the bar; a missed call offers to call or text back.
- **Gallery and Received**: the phone's newest photos and videos, and the
  files it sent you.
- **Setup**: checks with fixes, a QR code for the app (Android or iPhone),
  a pairing pop-up with the key, and a demo phone to look around first.
- **Make it yours**: edit the page in place, drag anything to reorder.
- **Keyboard**: one cursor that slides, and messages fully by keyboard.
- **Safety**: every image from the phone is decoded in a sandbox.

### Issues

- [#72](https://github.com/sceny/omarchy-devices/issues/72) Many devices, step 1: profiles, settings read as defaults, chips and attention
- [#73](https://github.com/sceny/omarchy-devices/issues/73) Many devices, step 2: tabs, per-device pages, chips in the pill, the pairing card
- [#74](https://github.com/sceny/omarchy-devices/issues/74) Many devices, step 3: Settings for devices
- [#75](https://github.com/sceny/omarchy-devices/issues/75) Many devices, step 4: the Connection page and Reconnect
- [#58](https://github.com/sceny/omarchy-devices/issues/58) Incoming and missed calls in the bar and the panel
- [#65](https://github.com/sceny/omarchy-devices/issues/65) The phone's newest photos in the panel (Gallery)
- [#37](https://github.com/sceny/omarchy-devices/issues/37) Inbox of files received from the device
- [#81](https://github.com/sceny/omarchy-devices/issues/81) Edit a device's page in place
- [#84](https://github.com/sceny/omarchy-devices/issues/84) The bar joins edit in place
- [#92](https://github.com/sceny/omarchy-devices/issues/92) Pairing: a pop-up and a glow when a device asks to pair
- [#62](https://github.com/sceny/omarchy-devices/issues/62) Preview the panel with a demo phone before setting up
- [#64](https://github.com/sceny/omarchy-devices/issues/64) A QR code to install the phone app
- [#69](https://github.com/sceny/omarchy-devices/issues/69) Find a paired device that is away, and say why when it cannot
- [#105](https://github.com/sceny/omarchy-devices/issues/105) Gallery: decode the phone's files in a sandbox
- [#107](https://github.com/sceny/omarchy-devices/issues/107) Images from the phone decoded by the shell, unsandboxed
- [#100](https://github.com/sceny/omarchy-devices/issues/100) Gallery asked for the mount on every open after a failure
- [#102](https://github.com/sceny/omarchy-devices/issues/102) Messages: a conversation opened while another loaded stayed on skeletons
- [#108](https://github.com/sceny/omarchy-devices/issues/108) Demo mode showed the real device's nickname
- [#67](https://github.com/sceny/omarchy-devices/issues/67) The line under the pill covered only part of it

### Pull requests without an issue

- [#111](https://github.com/sceny/omarchy-devices/pull/111) One keyboard cursor and one Esc everywhere, messages by keyboard, pictures open sandboxed
- [#104](https://github.com/sceny/omarchy-devices/pull/104) The hand cursor over the panel's buttons
- [#87](https://github.com/sceny/omarchy-devices/pull/87) The resting glyph with nothing paired
- [#112](https://github.com/sceny/omarchy-devices/pull/112) The user guide: a picture per topic, from demo mode

### Upgrading

- **Received** and **Gallery** join your saved order at the end, switched
  on; each shows only while it has something.
- The Devices section is gone; its switch is ignored. Nothing in your
  settings is rewritten.

## 0.6.1 — 2026-09-28

### Docs
- A new picture for the marketplace and the README: the pill in the bar,
  the panel with shortcuts, Now playing and notifications, and the
  messages view, in one shot.
- A one-screen README, a short user guide (getting started, the panel,
  messages, settings, troubleshooting) and the technical pages apart.

### Fixed
- Demo mode shows every feature even while the real phone is away: the
  messages view no longer refuses to open, and the shortcuts are no
  longer dimmed.

## 0.6.0 — 2026-09-27

### Panel
- Every click that goes to the device shows it is waiting: the clicked
  control (the dismiss X, a notification's action or reply button, a
  shortcut, the pairing buttons, next and previous) turns into a small
  ring until the device's answer shows, not only until the call returns.
  A dismiss the phone never confirms brings the X back and says so. The
  line under a click ("Dismissed") shows once the device has answered.
- Chat notifications (WhatsApp, Signal and other group or one-to-one
  chats) show each sender's name and messages the way the phone does,
  instead of raw `<b>` and `<br/>` markup. Folded, it shows the latest
  message and its sender; *Show all* shows the whole conversation. A
  group's unread count, which came glued to its name ("Book club
  (8 messages)"), shows beside the name, dimmed (#39). The text is always
  shown as plain text, so nothing in a message is interpreted.
- Scrolling follows the wheel: a long spin goes as far as it was spun
  and a nudge moves a little, instead of about one step per spin; a
  touchpad moves the lists with the fingers. On the main page, the
  conversation list, the messages and the new-message suggestions.
- Demo mode waits as long as a phone about takes, so the waiting states
  can be looked at; `pressDismiss` presses a demo notification's X.

### Messages
- The conversation list and a conversation that is opening show
  skeletons when loading takes more than a quarter second; the messages
  ease in when they land. The conversation's header and the composer stay
  on the pane's edges while the panel resizes, and the name crossfades in
  place when moving between conversations. Loading older messages, a
  message being sent and an attachment being fetched show the ring.
- Pressing an action (such as *Mark as read*) or sending a reply on a
  text-message notification in the panel marks its conversation read in
  the messages view at once, instead of when the phone reports it.
- When KDE Connect restarts, the plugin asks the phone for its
  conversations again, so nothing from the previous run stays stale.

### Fixed
- Opening a conversation could show only its latest message, with no
  older ones to scroll to, after the plugin had asked the phone for every
  conversation (at start, or after KDE Connect restarted). The count KDE
  Connect sends after that is how many messages it holds, not how long
  the conversation is; only the answer to a page the plugin asked for is
  taken as that now.

## 0.5.0 — 2026-09-26

### Bar
- Choose what the bar shows beside the device glyph, in order: connection
  (Wi-Fi, Bluetooth, crossed out while away), battery, battery %,
  notification and unread-message counts, now playing, and a notification
  count bubble on the glyph (#3).
- The new default is the bubble and the battery only when low: a healthy
  device with nothing new is the glyph alone.

### Panel
- Order the sections (Devices, Shortcuts, Now playing, Notifications) in
  Layout settings, with the arrows or Shift+K/Shift+J; each has its own
  switch.
- Shortcuts fold like the other sections; folded, they become a row of
  icons in the header that still work.
- Notifications hides while there are none.
- Send text or a link to the device: a Send text shortcut opens a field;
  text lands on the device's clipboard, a link arrives ready to open, and
  Ctrl+Enter sends it as a ping with that message (#10).
- Cellular signal bars beside the network type on the meta line
  (`󰣸 LTE`) (#11).

### Fixed
- Sending a notification reply with Enter opened the reply field again.

### Upgrading
- The `showPercent` setting is gone: the bar follows the Bar settings
  (`barIndicators`, `batteryLowOnly`). For the old pill (`󰄜 63%`), tick only
  Battery % there and turn *Battery only when low* off.

## 0.4.0 — 2026-09-26

The first public release, as `sceny.devices`.

### Text messages
- A two-pane view inside the panel: conversations with unread marks, a
  one-click unread filter and search; the conversation with day headers,
  history that loads as you scroll, and reply.
- New messages with a recipient search over contacts and past threads.
- Picture messages (MMS) with previews that open full size.
- The conversation last open comes back; unsent drafts are kept while you
  switch (in memory only).
- Text-message notifications expand to the full text and open their
  conversation.

### Devices
- Phones, tablets, laptops, computers and TVs, each with its own glyph.
- A Devices section when there is a choice: switch, pair, accept or reject a
  request with its verification key, unpair.
- Setup checks (installed, running, firewall, paired, connected) with a fix
  for what can be fixed here, and the steps on the phone.

### Panel
- Shortcuts you choose and order; media as a carousel of the device's
  players with seek and volume; notifications with reply, dismiss and the
  app's own actions.
- Sections fold, on the main page and in settings, and remember it.
- Results show as a toast, or in Omarchy's on-screen display when the panel
  is closed.
- Page changes and the panel's size animate at one pace.
- Demo mode for screenshots, with made-up notifications and conversations.
