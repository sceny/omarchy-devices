# Devices: an Omarchy plugin

Read this before changing, testing or diagnosing anything here. Two skills carry
the procedures:

- `.claude/skills/develop-panel/`: how to change it and see the change working.
- `.claude/skills/diagnose-panel/`: something looks wrong in the bar or panel, and why.

## What this is

A plugin for the Omarchy shell (Quickshell/QML), id `sceny.devices`: a bar
widget and a panel over the phones and tablets paired with
[KDE Connect](https://kdeconnect.kde.org/). Battery in the bar; in the panel,
shortcuts, the device's media players, its notifications, and a full
text-message view. The README and `docs/` are the user-facing description.

## The boundary: KDE Connect is the source of truth

The plugin holds no device state of its own. Everything comes from the KDE
Connect daemon over D-Bus, through `bin/kdeconnect-bridge`, or from the MPRIS
players KDE Connect exports (media). The only files the plugin writes outside
its folder are caches under `~/.cache/sceny.devices/`.

- **A feature KDE Connect does not offer is not faked.** Ongoing notifications
  never leave the phone; messages cannot be marked read on the phone; RCS is
  not in the SMS store. Say so in the UI or the docs
  (`docs/troubleshooting.md`) instead.
- **A KDE Connect fault is fixed at its source, not worked around.** When
  the panel shows what KDE Connect reports and KDE Connect is suspected,
  file two issues here (`diagnose-panel`, step 5): a KDE Connect issue
  (`external:kde-connect`) for the owner's KDE Connect specialist, which
  links every KDE bug report, merge request, branch and fork we create or
  follow; and a plugin issue (`bug`), blocked by it. The plugin changes only
  when the owner asks for a workaround.
- **The bridge speaks D-Bus; QML speaks to the bridge.** QML has no generic
  D-Bus binding, and every shell D-Bus client (`busctl`, `gdbus`) opens a
  connection per call and cannot listen. One Python process (PyGObject) holds
  one connection and listens.

## Files

| File | Holds |
|---|---|
| `bin/kdeconnect-bridge` | `watch` (device snapshots, event-driven), one-shot action verbs, and `sms` (JSON lines on stdin/stdout) |
| `Service.qml` | the watcher, the action runner, MPRIS players, and `SmsService` |
| `SmsService.qml` | text messages: threads and the open conversation as ListModels, search, what was seen here |
| `Model.js` | pure functions from data to what is drawn; no QML, checked with `node` |
| `BarWidget.qml` | the bar pill |
| `Panel.qml` | the panel: pages, keyboard, settings persistence, the IPC target |
| `SettingsView.qml`, `MessagesView.qml` | the settings page and the two-pane messages view |
| `SetupChecks.qml` | KDE Connect setup checks (`kdeconnect-bridge doctor`) with fixes, and the phone steps |
| `FoldToggle.qml`, `FoldBody.qml` | the folding section header and body, shared by the main page and settings |
| `Reorder.qml`, `ReorderShift.qml`, `ReorderGrip.qml` | moving an item in an order (drag, arrows, keyboard): the order being moved, an item's place, a row's grip; used by every order in settings and by the tabs |
| `manifest.json` | id, entry points, settings and their defaults |

## Rules: what the owner decided, so nobody undoes it

Each rule is a decision the owner made or guards against a known fault.
Keep them; change one only with the owner.

- **Never send a text message while testing.** A test reply goes to a real
  person. Check the send path up to the D-Bus argument types, and leave the
  first real send to the owner.
- **Nothing scripted focuses a text field.** IPC `openThread`, `newMessage`
  and the like never focus the composer: keystrokes meant for another window
  would land in a text, and Enter would send it. Only the user's own click or
  Enter on a thread does.
- **No real personal data in the repository.** No phone numbers, device ids,
  message text or contact names in code, comments, docs, tests or commit
  messages. Examples use 555 numbers; screenshots (`preview.png`, `docs/`)
  come from `demo` mode, which fakes notifications and conversations and
  names the device Pixel 8. The demo picture message reads a local file
  (`~/.cache/sceny.devices/demo/picture.jpg`) that is not in the repository.
- **Asking the phone for every conversation is expensive.**
  `requestAllConversationThreads` makes the phone send one packet per
  conversation: the bridge asks at start and after a KDE Connect restart,
  never per user action. When the panel acts on a text-message
  notification, it marks the conversation read itself.
- **Media comes from MPRIS, not `mprisremote`.** KDE Connect's `mprisremote`
  object shows one "current" player, which goes stale when the phone
  switches apps. The exported `org.mpris.MediaPlayer2.kdeconnect.*` players are live.
- **The media card shows the active player only**, like the phone; the others
  are a carousel away (arrows, dots, swipe, drag, `h`/`l`). It opens on the
  active player (playing, else last played) every time.
- **Nothing blinks on a seek.** A seek makes the phone report Paused then
  Playing within about 100 ms. Never rebuild or re-sort the player list on
  play state, never hide the seek bar or flip the play button on a pause
  shorter than the grace (1.5 s for the button, 4 s for the seek bar).
- **The volume slider stays where it was left.** The phone has coarse volume
  steps and reports the step it rounded to; the panel keeps showing the
  user's level while the phone's reports are only its answer to that set.
- **One pace for all motion: `Model.MOTION`** (90 ms out, 220 ms in, OutCubic).
  Nothing animates on its own clock. A page change fades and slides the old
  page out, swaps it at the midpoint, and slides the new one in, while the
  panel's box (the card) animates to the new size at the same beat. The card
  is an item inside a full-screen layer surface, so animating it costs no
  window resize; snapping it jumps mid-transition. The page is
  laid out at the card's final width from the first frame, so it never
  re-flows while the card moves.
- **Size animations are for the user's own changes.** A hidden page has no
  height, so while a page appears or the panel opens, fold and carousel
  animations are off (`settled`); otherwise every section grows from nothing
  as the page slides in.
- **The battery is a detail, not the headline.** Bar pill: the device glyph
  and the indicators the user picks, in order (`barIndicators`); the owner's
  default is the battery with the *Battery only when low* switch on
  (`batteryLowOnly`: off, battery and % always show) and the notification
  bubble, so a healthy phone with nothing new is the glyph
  alone. Counts and the bubble hide at 0; away, nothing stale shows. Panel:
  the header icon is the device; the battery is a text-sized glyph leading
  the meta line. The bolt already says charging; do not add the word.
- **UI state persists.** What the user arranged is still there after the
  panel closes, the shell restarts or the machine reboots, stored in this
  widget's `shell.json` entry: folded sections, main page and settings (`collapsed`), section
  visibility and order (`sectionOrder`), shortcuts, bar indicators, the
  device order (`deviceOrder`; an old `deviceId` is read as its first
  place), the conversation last open in messages, per device (`lastThread`), and the
  messages unread filter (`unreadOnly`). With two or more devices, a
  device's own changes (its folds, sections, shortcuts, bar indicators)
  go into its profile (`devices`), as do every device's nickname, icon,
  place in the bar and tab; with one device, everything but its nickname
  and icon stays in the flat keys (`docs/design/multi-device.md`). New UI
  state follows the same path unless it is private: unsent message drafts
  stay in memory (they are message text) and read state lives in the cache.
  Deliberately fresh on every open: the panel opens on its main page, on
  the device asked for (a chip, IPC) else the first connected one in the
  order, the media carousel on the active player, search empty, nothing
  focused. The device viewed with a tab is not stored.
- **Settings are written only by the panel**, into this widget's
  `shell.json` entry (`updateEntryInline`), on the user's action (settings
  page, folding a section). Never on upgrade: old entries are read as they
  are (`Model.readSettings`) and new keys appear on the user's next change.
- **Never edit `shell.json` by hand while the shell runs.** Each monitor has
  its own panel holding its own copy of the settings; a hand edit leaves one
  stale, and the next toggle starts from the wrong state. Go through the
  plugin (IPC `fold`, the settings hooks) and read the file back.
- **Results never push the layout.** A click's outcome is a toast floating
  over the panel, or Omarchy's OSD (`omarchy-osd`) when no panel is open.
  Nothing appears in the flow of the panel for a moment and moves the rest.
- **Orders move with a glide, never a jump.** Every order (devices,
  sections, bar indicators, shortcuts, tabs) moves through `Reorder`:
  while an item moves, the others slide aside to show where it lands; it
  glides in at `Model.MOTION`, and only then is the order written. A drag
  and Shift+K / Shift+J look the same; there are no ↑ ↓ buttons (the grip
  says a row moves). A new order uses
  these components, not a copy.
- **Sections fold with an animation, never a jump:** content grows or
  shrinks (`FoldBody`), the chevron turns, the one-line summary fades, all
  at `Model.MOTION`. Folded Now playing keeps the cover and a play button;
  folded Shortcuts become a row of icons that still work.
  Every section, on the main page and in settings, uses the same
  `FoldToggle`/`FoldBody`; a new section does too, with its own summary.
- **Sections move without being rebuilt.** Shortcuts, Now playing and
  Notifications are fixed items placed by `sectionOrder`
  (`sectionsBox`), so a new order keeps the media cards and a half-typed
  text. `stackBefore`/`stackAfter` are not callable from QML; do not reach
  for them. A separator goes between sections, never under the header.
- **A section shows when its switch is on and it has something:** Now
  playing while a player exists, Notifications while there are any (no
  empty state).
- **A device's page is edited in place** (✎ on its header, or `E`): every
  section becomes a bar with its grip and switch, every shortcut shows
  (drag the chosen ones, click to add or take away), and ✓ Done, `E` or
  Esc ends it. It edits the viewed device's profile (with one device, the
  flat keys), and is off on every open. Settings keeps only what has no
  place on the page (nickname, icon, place in the bar, the device list);
  *Defaults for all devices* keeps the sections and shortcuts, since the
  defaults have no page of their own. There is no Devices section: tabs switch devices, the
  pairing card answers requests, and Settings' device list pairs, orders
  and unpairs (Unpair asks twice).
- **Each device's settings are its own** (`docs/design/multi-device.md`):
  with two or more devices, Settings lists them; a device's page edits its
  nickname, icon, place in the bar, tab, and any group it changes (marked
  CUSTOM, with *use the defaults*); *Defaults for all devices* edits the
  flat keys. Identity (nickname, icon, bar, tab) is never inherited. With
  one device, Settings is one flat page. Moving a device writes down how
  each one shows in the bar, so moving never changes it.
- **Playback notifications are not notifications here**: from an app with a
  media player now, naming its track or not dismissable. The media card
  already shows them; the phone keeps them out of its list too.
- **Look at the render before saying done.** A measurement is not the layout
  fitting. Use `slowMotion 10` to catch a transition mid-way.
- **After every shell restart, confirm the panel answers over IPC.** A QML
  error takes the whole widget off the bar, and it can be logged after a
  quick log check has already passed (an attached handler that does not
  exist, such as `Keys.onPageUpPressed`, does exactly that).

- **Fixes change the system only on a click.** `fix install` and `fix firewall`
  go through `pkexec` (one password prompt); the firewall rule is limited to
  the local network the default route is on, never opened to everyone.

## Workflow

- **Re-read an issue before starting it**, body and comments
  (`gh issue view <n> --comments`): the owner edits issues to change scope.
- **Two branches.** `main` is what users get: `omarchy plugin add` and
  `omarchy plugin update` install the latest commit of the default branch,
  and the marketplace lists one commit of `main`. `main` moves only at a
  release (*Releasing*); a commit on `main` between releases ships
  unreviewed code to anyone who installs or updates, and shows the listing
  as *Update unverified*. `develop` is where work lands. Keep `main` the
  GitHub default branch.
- **Every change goes into `develop` through a pull request:** a
  short-lived branch from `develop`, `gh pr create --base develop`, CI
  green, the change checked in a running shell (check the branch out in the
  installed clone), squash-merge, delete the branch. `Closes #n` in a pull
  request into `develop` closes nothing (GitHub acts on it only for the
  default branch): close the issue by hand after the merge, with a comment
  naming the pull request.
- **Without a running Omarchy shell** (a cloud session, a machine without
  Omarchy), do the rest (code, tests, CI, the pull request), say in the pull
  request that the change is not checked in a running shell, and leave the
  merge until someone checks it there.
- **Check the freeze before merging anything into `main`**, and whenever
  you look at the open issues. It takes two steps:
  each open `marketplace-review` issue here points to a marketplace issue,
  and the marketplace issue says whether its review is still open:

  ```bash
  gh issue list --label marketplace-review --state open --json number,body \
    --jq '.[] | "\(.number) \(.body | capture("omacom/omarchy-plugin-marketplace#(?<n>[0-9]+)").n)"' |
  while read -r ours theirs; do
    echo "#$ours -> omacom/omarchy-plugin-marketplace#$theirs $(gh issue view "$theirs" \
      --repo omacom/omarchy-plugin-marketplace --json state -q .state)"
  done
  ```

  - `OPEN`: a review is in progress and `main` is frozen.
  - `CLOSED`: the two are out of sync; sync them now. Read the marketplace
    issue's last report (published, or what to fix), comment the outcome
    on our issue, and close it.
  - No output: nothing is under review.
- **Keep the repository apart from the installed copy.** Work in your own
  clone, outside the shell's plugin folder. The plugin folder holds an
  installed copy following `develop`; update it with `git pull`
  (`omarchy plugin update` reads `main` and does not bring `develop`
  changes). To check a branch live, push it, `git switch` to it in the
  installed copy, and switch back to `develop` afterwards.
- **An urgent fix for users** is a branch from `main` with a pull request
  into `main`, only while `main` is not frozen (*Releasing*, step 5);
  afterwards merge `main` into `develop`.
- **Instruction docs state what to do.** AGENTS.md, CLAUDE.md, the skills
  and `docs/internals/` give steps, conditions and rules in the
  present tense; the reason for a rule is a present-tense consequence. How
  something came about goes in commit messages and `CHANGELOG.md`.
- **Docs are for users first, and short.** The README is one screen: what
  it does, the picture, the main keys, privacy, then links to the user guide
  and the internals. User pages (`docs/`) are screenshot-first (demo data
  only), with little text, a breadcrumb back to the README on each page, and
  no history. Anything technical goes in `docs/internals/`, linked from the
  README's last section. Cut words before adding them: a page that grows
  past about 250 words is split or trimmed.

## Releasing

When the owner says to release, run every step below to the end without
stopping to ask: the owner approved the whole process, the marketplace
request included. Stop only when a check fails or the freeze check finds
`main` frozen, and report that.

0. **Check the freeze** (*Workflow*). A marketplace issue still open means
   `main` is frozen: say so and release nothing.
1. **Pick the version**: a new feature raises Y (`0.5.0` → `0.6.0`), fixes
   alone raise Z (`0.6.0` → `0.6.1`).
   **Prepare on a branch from `develop`** (`release-X.Y.Z`): rename
   `## Unreleased` in `CHANGELOG.md` to `## X.Y.Z — YYYY-MM-DD`, group the
   entries by area (Bar, Panel, Messages, Fixed), and add an *Upgrading*
   group when a setting or a default changes. Set `"version": "X.Y.Z"` in
   `manifest.json`. Pull request into `develop`, CI green, squash-merge.
2. **Merge `develop` into `main`** through a pull request titled
   *Release X.Y.Z* (`gh pr create --base main --head develop`), CI green,
   merged with a merge commit, never squashed, so both branches keep one
   history. The `release` check on that pull request fails while the
   version in `manifest.json` is already tagged or has no CHANGELOG
   section with entries.
3. **The `release` workflow tags and publishes** when the merge lands on
   `main`: it tags the merge commit `vX.Y.Z`, publishes the release with
   that CHANGELOG section as its notes, and brings `develop` level with
   `main`. Check it ran (`gh run list --workflow release --limit 1`,
   `gh release view vX.Y.Z`). If it failed, do what it does by hand:

   ```bash
   git tag -a vX.Y.Z -m "Devices X.Y.Z" origin/main && git push origin vX.Y.Z
   gh release create vX.Y.Z --title "Devices X.Y.Z" --notes-file notes.md --verify-tag --latest
   git fetch origin && git switch develop && git merge --ff-only origin/main && git push
   ```

4. **Request the marketplace review** (`omacom/omarchy-plugin-marketplace`)
   as soon as the release is published, with the text below as it stands:
   the owner approved it for every release. It is filed from a session,
   not from CI (CI cannot open issues in another repository). The
   *Standard installation* box stays unticked: Devices needs KDE Connect
   set up separately, which is why the marketplace lists it `manual-setup`.
   - Not listed yet: the plugin submission issue form (the marketplace's
     `SUBMISSION.md`).
   - Listed: the *Verify and publish a newer upstream commit* form, with the
     full SHA of the current head of `main`:

     ```bash
     cat > /tmp/devices-verify.md <<EOF
     ### Verification action

     Verify and publish a newer upstream commit

     ### Plugin ID

     sceny.devices

     ### Repository URL

     https://github.com/sceny/omarchy-devices

     ### Target commit

     $(git rev-parse origin/main)

     ### Verification acknowledgment

     - [x] I understand that only the exact target commit can become a verified marketplace snapshot and that verification is not a security audit.

     ### Standard installation acknowledgment

     - [ ] I confirm that this listed root plugin supports the standard Omarchy installation path and does not require manual setup.
     EOF
     gh issue create --repo omacom/omarchy-plugin-marketplace --title "[Verify]: Devices" --body-file /tmp/devices-verify.md
     ```

   Then open the tracking issue here, labelled `marketplace-review`, with
   the marketplace issue and the commit under review in its body:

   ```bash
   gh issue create --label marketplace-review \
     --title "Marketplace review: omacom/omarchy-plugin-marketplace#<n> (vX.Y.Z)" \
     --body "Marketplace: omacom/omarchy-plugin-marketplace#<n>
   Commit under review: $(git rev-parse origin/main)"
   ```

   Status notes (bot reports matched, the maintainer's requests) go on that
   issue as comments, never into commits.

   Then report to the owner: the release link, the marketplace issue, the
   tracking issue, and that `main` is frozen.
5. **Freeze `main` while the marketplace issue is open** (the check is in
   *Workflow*). The marketplace checks, reviews and publishes one exact
   commit, and refuses to publish when `main` moved after its checks. Merge
   nothing into `main` meanwhile; work keeps landing on `develop`. The
   freeze ends when the marketplace closes its issue; the freeze check then
   finds the two out of sync and syncs them (*Workflow*).
6. **If `main` moves during the freeze anyway:** edit the submission issue
   (every edit makes the bots check the current head of `main`; the
   submission form has no commit field), wait until both bot reports
   (validation and security baseline) name the new commit, tell the
   maintainer in a comment which commit is ready and whether the reported
   capabilities changed, and put the new commit on the tracking issue.

## Never

- Send a text, ring a device, or change the device's volume or playback in a
  test without the owner's go.
- Leave a test's side effect behind: opening an unread thread marks it seen in
  `~/.cache/sceny.devices/sms-seen-<device>.json`; undo it.
- Commit anything read from a real device.
