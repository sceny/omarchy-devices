[Devices](../../README.md) › Internals › Releasing

# Releasing

The steps for a release are in [AGENTS.md](../../AGENTS.md), *Releasing*.
This page holds the checks that close one, with the templates. Releasing a
version to Omarchy is always the owner's call.

| Check | Who | When |
|---|---|---|
| Review with a security check | Panel QA | every pull request |
| Regression on the emulator | Panel QA | before every release |
| Cold install and upgrade | Plugin DevOps runs, Panel QA passes | before every release |
| Security review | the security specialist | every release, patch included, opened with the regression |
| Go | the owner | before anything touches `main` or the marketplace |

## Every pull request: review with a security check

One reviewer, Panel QA. This list is the record of faults already met: each
class the security specialist finds is added here, with a test that fails the
build where one can. Besides the change itself, the reviewer answers each line
below from the diff. A finding blocks the pull request.

- Private text (messages, contact names, numbers, clipboard) stays off
  argv and out of logs. A bridge verb reads it from stdin; a test fails if it
  reaches a command line.
- Nothing from a device is decoded outside the sandbox. A QML `Image` never
  points at a file the device sent.
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

## Regression on the emulator

Panel QA runs the whole plugin in the rig (`dev/rig up`, then `dev/rig check`
and the feature passes in `develop-panel`), on the candidate: the head of
`develop` after the release pull request is merged. Every feature gets one
pass or fail against its rule in AGENTS.md, not only what changed.

Calls and texts go only as far as the *Never* rules allow: the D-Bus argument
types (`tests/test_calls.py`) and demo mode (`demoCall`, `pressCall`). The
panel is looked at, not only measured (`slowMotion 10` for a transition).

The record is a document on the release task:

| Feature | Rule (AGENTS.md) | How checked | Pass/fail | Evidence |
|---|---|---|---|---|
| Media: seek | Nothing blinks on a seek | `dev/rig phone` pause/play within 100 ms, three screenshots | pass | `seek-1.png`..`seek-3.png` |

- *Rule* names the rule by its bold title.
- *How checked* is a command or IPC call someone else can repeat.
- *Evidence* is a screenshot, a log line or a test name, from the rig or demo
  mode only.
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
`main`). Plugin DevOps runs them in the rig and Panel QA passes them.

**Cold install.** A rig with none of the plugin's dependencies: the first-run
card, `fix ready` with one password, pairing, then each feature switch in
turn. Every step finishes by itself or stops at the user's one step, and no
package is asked for twice. `dev/rig cold begin` makes the cold computer
(`docs/internals/development.md`); each step is a row with its evidence, and
what the rig cannot prove goes on the *needs a real device* list.

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
