[Devices](../../README.md) › Internals › Releasing

# Releasing

The steps for a release are in [AGENTS.md](../../AGENTS.md), *Releasing*.
This page holds the chain every release follows, the checks that close one,
and their templates. Releasing a version to Omarchy is always the owner's call.

| Check | Who | When |
|---|---|---|
| Review with a security check | Panel QA | every pull request |
| Regression on the emulator | Panel QA | before every release |
| Cold install and upgrade | Plugin DevOps runs, Panel QA passes | before every release |
| Security review | the security specialist | every release, patch included, opened with the regression |
| Go | the owner | before anything touches `main` or the marketplace |

## The release template

Every release is the same chain of tasks, created together when the release is
started. Nothing is added by hand later: a task found missing is a change to
this template. `X.Y.Z` is the version.

| Kind | When | Branch | Pull request into |
|---|---|---|---|
| **minor** | a new feature on `develop` | `release-X.Y.Z` from `develop` | `develop`, then `develop` into `main` |
| **patch** | fixes only on `develop` | the same as minor | the same as minor |
| **urgent** | a fix users need now, or a maintainer's finding on the marketplace issue; only after the owner's go for it | `fix-X.Y.Z` from `main` | `main`, then `main` into `develop` |

| # | Task | Role | After | Done when |
|---|---|---|---|---|
| R0 | the release (holds the status page) | Omar | R1 to R7 | the freeze check is clean, the release is published, the marketplace issue is filed or not needed, both trackers are closed |
| R1 | prepare: `dev/release-prepare X.Y.Z` (version, CHANGELOG section, branch); for urgent, the fix itself is on this pull request | Panel Engineer | | the head has the version and its CHANGELOG section; CI is green, `release` check included, on the first push |
| R2 | review with security check (the regular pull-request review) | Panel QA | R1 | PASS on the candidate SHA; for minor and patch, merged into `develop` |
| R3 | regression, cold install, upgrade from the live tag | Plugin DevOps runs, Panel QA gives the verdict | R2 | the regression record is PASS on the candidate SHA, with the *needs a real device* list |
| R4 | release security review: the whole plugin, plus `last-tag..candidate` | the security specialist | R2 | PASS on the candidate SHA; a FAIL rejects the candidate |
| R5 | the owner's machine on the candidate | Plugin DevOps | R3, R4 | the owner's folder is at the SHA, the shell is restarted and `dev/loaded-code` exits 0 |
| R6 | the owner's go: the status page and nothing else | the chief of staff carries it to the owner | R5 | the owner said go or no for that SHA |
| R7 | merge, tag, publish, back to `develop` (*Releasing* steps 2 and 3; the owner's machine back to `develop`) | Plugin DevOps | R6 | tag `vX.Y.Z` on a merge commit, never a squash; the release is published; `develop` is level with `main` |

On R0, Omar then files or edits the marketplace issue and opens the
`marketplace-review` tracking issue (*Releasing* step 4) and runs the freeze
check. A step only the owner's account can do on the marketplace issue is a
named step for the chief of staff, once, in this chain.

- **The candidate is the head of R1's pull request when R2 passes.** R3 and R4
  start only then. A new commit on it voids R2 to R6: each runs again on the
  new head, and no task is created.
- **R4 is always the full review.** Its kind is never decided per release.
- **R6 is asked only when the status page reads PASS for R2, R3, R4 and R5, all
  on one SHA.**
- **A maintainer's finding** starts an urgent chain for the next Z. Its R1
  fixes the class (*Every pull request: review with a security check*), not
  only the case.

## The release status page

One page holds the state of a release and is kept current on R0: the owner
and the team read it, and the go request is this page and a link to it. It
changes when a check's verdict or the candidate changes, never because time
passed. It holds nothing private beyond what the tasks already hold.

```markdown
# Devices X.Y.Z: <minor | patch | urgent>

**Candidate:** `<full SHA>` (head of <pull request link>)  ·  **Freeze:** none | marketplace #<n> open
**Why this release:** <one line; for urgent, the finding, linked>

## Pre-go checks (all PASS on the candidate SHA before the go request)

| Check | Task | Verdict | On SHA |
|---|---|---|---|
| CI (test, release) | <pull request checks link> | green / red | `<sha>` |
| Review with security check | R2 | PASS / FAIL / not yet | `<sha>` |
| Regression on the emulator | R3 | PASS / FAIL / not yet | `<sha>` |
| Cold install, upgrade from vLAST | R3 | PASS / FAIL / not yet | `<sha>` |
| Release security review | R4 | PASS / FAIL / not yet | `<sha>` |
| Owner's machine on the candidate | R5 | done / not yet | `<sha>` |

## Needs a real device (for the owner)
- <item>, or *none*

## Outside findings this release answers
- <finding, link>, then <fix pull request>, then <its class test or lint>

## Next
- **<step>**, <role>, <after which task>
```

A row on another SHA than the candidate counts as not done. Nothing in the
table is removed or shortened for any kind.

## Preparing the branch: `dev/release-prepare`

A pull request into `main` runs the `release` check from its first push: the
version in `manifest.json` has a `## X.Y.Z — YYYY-MM-DD` section in
`CHANGELOG.md` with entries and no tag yet. The script makes a branch that
passes it before anything is pushed.

```bash
dev/release-prepare 0.10.0                                         # release-0.10.0 from origin/develop
dev/release-prepare 0.9.1 --from main --note "What the fix does"   # fix-0.9.1 from origin/main
```

- From `develop`, `## Unreleased` becomes the version's section (it must have
  entries). From `main` there is no Unreleased section: the section is added
  above the newest version with each `--note` under *Fixes* (at least one).
- It sets `"version"`, commits both files (`--no-commit` leaves them staged, uncommitted)
  and prints the next step. Write the section's remaining groups after it.
- It refuses a version already tagged (here or on origin), one not above the
  base's version, one the base's CHANGELOG already has, an empty Unreleased
  section, an existing branch and a tree with tracked changes.
- Tested in `tests/test_release_prepare.py`, which runs `dev/release-notes`,
  the `release` workflow's own extraction, on what the script wrote.

The release pull request into `main` is merged with a merge commit. GitHub has
no per-pull-request check of the merge method, so the pull request's `release`
check prints a reminder and the `release` run on `main` fails, after tagging
and publishing, when the tagged commit has one parent. Merge `main` into
`develop` meanwhile and use a merge commit for the next release.

## Every pull request into `main`: the marketplace's checks

The `marketplace-check` job runs the marketplace's own validation and
security baseline (the two steps of its *Validate plugin update* workflow,
taken from `omacom/omarchy-plugin-marketplace` `main`, not copied) on the
pull request's head commit, so their answer reaches us before the bots'.
`dev/marketplace-check.mjs` only gives those scripts that commit. The job
summary holds the bots' two reports, word for word. The job fails when the
validation fails, the baseline says it needs fixes, or the check cannot
complete (a change in the marketplace's scripts shows up here first). A
baseline that needs a maintainer's review passes, with a warning naming any
capability new since the listed snapshot.

Run it on any commit (the listed one, a candidate) with *Run workflow*, or
by hand:

```bash
git clone --depth 1 https://github.com/omacom/omarchy-plugin-marketplace /tmp/mp
(cd /tmp/mp && npm ci)
GITHUB_TOKEN=$(gh auth token) MARKETPLACE_DIR=/tmp/mp node dev/marketplace-check.mjs <full-sha> /tmp/reports
```

## Every pull request: review with a security check

One reviewer, Panel QA. This list is the record of faults already met: each
class the security specialist finds is added here, with a test that fails the
build where one can; a finding from outside the team (the marketplace's
maintainer, a security report) is fixed as its class, with that test. Besides
the change itself, the reviewer answers each line below from the diff. A
finding blocks the pull request.

- No value a person, a device or the API wrote is on the argv of any process
  the plugin starts, whichever process or helper starts it. A bridge verb reads
  such text from stdin. `tests/test_argv.py` finds every place QML starts a
  process and fails on any argument that is not a literal or on its reviewed
  allowlist (`ARGV_ALLOWED`, with the reason each is not private text); an
  allowed bare name (`id`) also has every value it is given in its file read
  (`ASSIGNED_ALLOWED`), so a local variable of the same name cannot carry text;
  a function whose parameter is such a name has every call read the same way.
  `tests/test_shell_argv.py` fails on `shell=True`, `os.system`, `bash -c` and
  `sh -c` in `bin/`, `lib/`, `dev/` and `tools/` unless the line is on its
  allowlist with a reason. The reviewer reads every new line of any list from
  the diff.
- The shell is never a party to a Wayland data transfer, and nothing reaches
  the clipboard's contents without the user's own paste (Ctrl+V): no
  `TextInput`, `TextField` or `TextArea`, no Omarchy type built on one
  (`NumberField`, `MultiSelect`, `SearchableDropdown`, `TextField` from
  `qs.Ui`, and any other its folder holds), no `Quickshell.clipboardText`
  read anywhere (it reads the whole clipboard in the shell, unbounded,
  waiting for the program that offers it), no `TextEdit` but `PanelField`'s
  and no Omarchy type with one inside (read-only text is a `Text`),
  `selectByMouse: false` written on it (the default is true; Qt would own
  the primary selection), no `selectByKeyboard: true`, no text item's own
  `copy()`, `cut()` or `paste()`, no `DropArea`, no system drag (`Drag.Automatic`), `wl-copy` and `wl-paste` only in
  `Clipboard.qml`, the copy's text on stdin, the read with a byte limit and
  a deadline, no `cliphist`. `tests/test_argv.py` (`ClipboardOnlyOnPaste`)
  and `tests/test_panelfield.py` (`ShippedQml`, naming file:line) fail on
  each; `dev/sandbox dev exec -- dev/clip-check --rig ID` shows it in a session's rig (every
  selection gesture, a reader that never reads, an owner that never
  writes).
- Private text (messages, contact names, numbers, clipboard) stays out of
  logs.
- The on-screen display's line (`omarchy-osd`, read by any local user) names
  nothing a device sent: a toast with a value passes its own display line
  (`report`'s third argument, the bridge's `say(..., osd=...)`).
  `tests/test_argv.py` (`OsdLines`) fails on a toast that does not.
- Nothing from a device is decoded outside the sandbox. A QML `Image` never
  points at a file the device sent.
- A file from the device reaches `open-file` / `gio open` only through one
  gate (`open_file`, `--from-device` or `--local`): what the file holds
  decides whether it is a picture (then only the sandbox's copy opens, and
  with no sandbox nothing opens), never its name or a type the device
  claims. A fetched attachment is opened only when this plugin asked for
  that id: the bridge sends no event for another, and the panel matches the
  exact id. `tests/test_bridge.py` (`FetchedAttachments`,
  `OpenPicturesSafely`) fails for an unrequested name and for a picture with
  no recorded type; `tests/test_qml.py` (`DeviceFilesOpenThroughTheGate`)
  fails on a QML start of `open-file` without the flag.
- Root goes only through `pkexec`, described first (`--describe`) and run
  only as confirmed (`--confirm <hash>`).
- The firewall opens only the private ranges and a mesh's interface: its
  rule sources are a subset of `PRIVATE_LANS`, whatever network this
  computer is on. A test feeds a public network, a `/1` and a `/0`.
- No command line is handed to a script that evaluates it
  (`omarchy-launch-or-focus`, `omarchy-launch-or-focus-webapp`). A window is
  found by its exact title and focused by address, else the command runs as an
  argv list. A test fails if the bridge calls those scripts.
- No new network listener. No command, path or argument built from device
  data without a fixed verb and a checked value.
- No third-party verbose log that records input or the clipboard. A log of
  another program's output keeps only the lines the plugin reads
  (`SCREEN_LOG_LINES`), in `$XDG_RUNTIME_DIR`, mode 0600.
- Device strings are capped at the bridge (`cap_text`, one limit per kind of
  text), before they reach the shell: contact fields, call names and numbers,
  Bluetooth names included, and a total budget per read. A test sends
  oversized input.
- No work per foreign event at rest without a rate limit and a check of what
  the event names (a player's art URL, a file the device sent).
- No personal data in code, comments, docs, tests, screenshots or commit
  messages.
- Nothing a device sent reaches the Fix with AI prompt except quoted, capped
  and labelled as data (`Model.aiPrompt`; a device is named by its kind). A
  test feeds a device named with an instruction.

The review comment names each line it checked, including the ones that do not
apply.

**Every finding has an owner before the review is done.** A finding that does
not block the pull request becomes a GitHub issue here (`bug`, or
`enhancement`; a Paperclip task when it concerns only our own tooling), with
its owner and its priority, before the review task is marked done. The review
comment links it. A finding written only in a comment has no owner and is
lost once the pull request merges.

**Nothing merges unchecked and untracked.** An item the review did not check
(an entry point read in the diff but not driven, a path opened another way,
a rule the author says is kept by hand with no test holding it) is checked
before the merge, or it becomes a GitHub issue with its owner that the
comment links. The merge waits for one of the two. A question the author
asks in the pull request (a design doubt, an alternative) goes to the role
that decides it, and the author gets the answer on the pull request.

**What a public comment holds.** A review comment on GitHub is read by the
author and by anyone after them. It holds the verdict, what was checked,
described as the plugin's behaviour (what was done in the panel and what it
showed), and each change the author must make, with the rule it follows. It
never holds how or where we ran it: the sandbox, an image, the rig, an
emulator, a local path, a host name, test-run counts, or a failure that comes
from our own setup. Those go on the Paperclip task.

`dev/public-text-check` holds these rules in `dev/public-text-rules.json` and
fails the `public-text` check on a pull request whose body, comment, review or
review comment: names the setup (`public-text-environment`: the tools, paths,
test counts, task numbers); says something is left with no issue reference in
its bullet or paragraph (`open-item-no-owner`); or names another repository's
issue without its owner (`unlinked-reference`). The failure names the text's
URL, the check and the matched words; the author or reviewer edits the text and
the check runs again on the edit. Every run reads all the pull request's text
through the API, so a plain comment is read on the next run of any event. A pull
request about a tool may name it (`allowed_when_changed`); a pattern that
catches a product word gets an exception in the rules file and a case in
`tests/test_public_text.py`. The same rules check the standing texts
(`AGENTS.md`, `CLAUDE.md`, the skills, `docs/internals/`) for task numbers,
dates and the owner's words as history, in the unit tests.

`public-text` is a required status check on `develop` (a repository ruleset,
no bypass): a pull request into `develop` merges only while its last run
passes. A direct push to `develop` is refused, so the `release` workflow posts
a `public-text` success status on the `main` commit it brings `develop` level
with (a push to `main` has no pull request text).

## Regression on the emulator

Panel QA runs the whole plugin in the sandbox, on the candidate: the head of
`develop` after the release pull request is merged, by its full SHA:

```bash
dev/sandbox run sceny/omarchy-devices <sha> --steps tests,rig,script --script regression.sh
```

The tests run, `dev/rig ci` runs its checks, and the script runs with a rig up
and drives the feature passes of `develop-panel`; it writes its evidence
(screenshots, recordings, logs) under `$SANDBOX_OUT`, which the run brings out as
data. While writing or debugging the script, a `dev/sandbox dev` session on a
checkout of that SHA does the same interactively; the record is the `run`.
Every feature gets one pass or fail against its rule in AGENTS.md, not only
what changed.

Calls and texts go only as far as the *Never* rules allow: the D-Bus argument
types (`tests/test_calls.py`) and demo mode (`demoCall`, `pressCall`). The
panel is looked at, not only measured (`slowMotion 10` for a transition).

The clipboard is a row of its own: `dev/clip-check --rig ID` passes in the sandbox on the
candidate, and the row records Omarchy's Qt beside it (`pacman -Q qt6-base
qt6-declarative`). When that Qt meets a trigger in
`docs/architecture/001` (section 5.1), the regression's author files the
retirement it names as its own issue for Panel Engineer.

The record is a document on the release task:

| Feature | Rule (AGENTS.md) | How checked | Pass/fail | Evidence |
|---|---|---|---|---|
| Media: seek | Nothing blinks on a seek | `dev/sandbox dev rig phone` pause/play within 100 ms, three screenshots | pass | `seek-1.png`..`seek-3.png` |

- *Rule* names the rule by its bold title.
- *How checked* is a command or IPC call someone else can repeat.
- *Evidence* is a screenshot, a log line or a test name, from the sandbox's rig or
  demo mode only.
- A fail is a GitHub issue, fixed on `develop`, and the row is checked again
  on the new head. A release does not go with a fail.

### Needs a real device

What the emulator cannot judge goes in a separate list on the same document,
not in the record as a pass: Bluetooth audio, a real call, a carrier's
messages, a vendor's battery settings, a phone's permission screens.

| What | Why the emulator cannot | What the owner does | Result |
|---|---|---|---|

Omar sends the list to the owner as one request (*The owner's request*) that
says exactly what to do and why. An item stays open until the owner has done
it or waived it, and the go waits for it.

## Cold install and upgrade

Both start from the tag that is live now (`git tag`, the latest `vX.Y.Z` on
`main`). Plugin DevOps runs them in the sandbox and Panel QA passes them: the
cold install in `dev/sandbox run` on the candidate's SHA (`--steps script`), the
upgrade in a `dev/sandbox dev` session, which holds the live tag beside the
candidate's tree (`dev sync --tree DIR --as live`,
`docs/internals/development.md`).

**Cold install.** A sandbox rig with none of the plugin's dependencies: the first-run
card, `fix ready` with one password, pairing, then each feature switch in
turn. Every step finishes by itself or stops at the user's one step, and no
package is asked for twice. `dev/rig cold begin` in the script makes the cold computer
(`docs/internals/development.md`); each step is a row with its evidence, and
what the sandbox's rig cannot prove goes on the *needs a real device* list.

**Upgrade.** Install the live tag with a `shell.json` entry for one device
and another for two devices with profiles, then move to the candidate. Old
settings read back unchanged, nothing is written until the user changes
something, IPC answers after the restart and `dev/loaded-code` finds the
running code matching the candidate's files, and a firewall rule comes only
from a click.

Both results go into the regression record as rows.

## Security review of the release

Every release, patch included, gets a pass over the whole plugin against its
threat model, with `git diff <last-tag>..<candidate>` on top. The task opens
with the regression, when the release branch is prepared, and the verdict is
given on the candidate once the regression has passed. The review goes beyond
the per-pull-request list, which is assumed already run: it looks for faults
nobody has met yet. It traces untrusted input through the whole code path,
unchanged code included.

The attackers:

- Another local user or process: `/proc`, file modes in the cache and runtime
  directory, ports on `127.0.0.1`, the session D-Bus, logs.
- A hostile paired device: everything it sends is attacker input (rich text,
  paths, URLs, the *Fix with AI* prompt).
- The local network and mesh: discovery, pairing, the firewall as written.
- The `pkexec` boundary: what root runs, and whether a user process can change
  it.
- Supply chain and CI: packages, workflows, what the marketplace bots report.
- Data on disk and in logs: verbose tool logs, caches, temporary files.
- Input with no size or time limit: a cap before the shell, a bound on
  processes and decodes.
- Work at rest: the panel closed, hidden or folded.
- D-Bus and MPRIS names any local process can take.

The review also lists the capabilities the marketplace bot will report, for the
maintainer's review.

- A finding is reproduced where possible.
- Every finding gets a search for the same class across the plugin.
- An unfixed vulnerability stays off public GitHub (issues, commits, pull
  request text) until its fix is released.

The verdict is a document on the release task: pass, or findings with file
and line. Findings are fixed on `develop`; a fix changes the candidate, so the
changed head is regressed again where the fix reaches.

A FAIL from the Security Specialist rejects the candidate. It is fixed and re-reviewed on the new head, or the release does not happen. Nobody downgrades or waives it; only the owner can.

When anyone outside finds a security issue in a released version, the security
specialist writes on the release task why the review missed it and what class
is added to the threat model and to the per-pull-request list above.

## The owner's request

The owner is asked for the real-device checks and the go once per release,
and only when nothing an agent can check is left open. This is the standing
rule for every release closing, not for one version.

- **One exact SHA.** Every agent check of the release (the pull-request
  reviews, the full regression, the cold install, the upgrade, the security
  review) has passed on the same candidate SHA. The request names that SHA.
- **A new commit voids.** A commit on the candidate voids every check and any
  open request. The checks run again on the new head before anyone asks.
- **The owner's machine runs the SHA.** Before the request, its plugin folder
  is at the SHA, the shell is restarted and `dev/loaded-code` exits 0. The
  request names the SHA and these results. Plugin DevOps does this, never a
  command the owner pastes and runs.
- **Back to `develop`.** After the checks, the owner's machine goes back to
  `develop` the same way: folder, restart, `dev/loaded-code`.
- **Once, with every item.** The request holds the regression record, the
  security verdict and the whole *needs a real device* list. The owner
  installs and runs nothing; they only use the phone and answer.

## The owner's go

The owner answers go or not for this release on that request.

- Until the go, nothing is merged into `main`, tagged or released, and
  nothing is filed on or edited in the Omarchy marketplace.
- A go covers one release. The next release asks again.
- An urgent fix for users is a release: it asks for its own go, with a
  shorter record that names what the fix touches.

Then *Releasing* steps 2 to 6 run as written.

## Questions from outside

The maintainer's comments on a marketplace issue, replies on an open upstream
report, and new issues and pull requests on the plugin repository are
answered or routed the day they arrive. Omar runs a daily check over all
three. An answer that needs the owner goes to the owner through Omar, once,
with a recommendation. A finding from a maintainer is a fix in the plugin
before it is a reply.
