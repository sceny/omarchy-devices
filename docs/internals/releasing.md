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
| Security review | the security specialist | once, when the release closes |
| Go | the owner | before anything touches `main` or the marketplace |

## Every pull request: review with a security check

One reviewer, Panel QA. Besides the change itself, the reviewer answers each
line below from the diff. A finding blocks the pull request.

- Private text (messages, contact names, numbers, clipboard) stays off
  argv and out of logs. A bridge verb reads it from stdin; a test fails if it
  reaches a command line.
- Nothing from a device is decoded outside the sandbox. A QML `Image` never
  points at a file the device sent.
- Root goes only through `pkexec`, described first (`--describe`) and run
  only as confirmed (`--confirm <hash>`).
- The firewall opens only the private ranges and a mesh's interface.
- No new network listener. No command, path or argument built from device
  data without a fixed verb and a checked value.
- No personal data in code, comments, docs, tests, screenshots or commit
  messages.

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

Omar sends the list to the owner as one request that says exactly what to do
and why. An item stays open until the owner has done it or waived it, and the
go waits for it.

## Cold install and upgrade

Both start from the tag that is live now (`git tag`, the latest `vX.Y.Z` on
`main`). Plugin DevOps runs them in the rig and Panel QA passes them.

**Cold install.** A rig with none of the plugin's dependencies: the first-run
card, `fix ready` with one password, pairing, then each feature switch in
turn. Every step finishes by itself or stops at the user's one step, and no
package is asked for twice.

**Upgrade.** Install the live tag with a `shell.json` entry for one device
and another for two devices with profiles, then move to the candidate. Old
settings read back unchanged, nothing is written until the user changes
something, IPC answers after the restart and `dev/loaded-code` finds the
running code matching the candidate's files, and a firewall rule comes only
from a click.

Both results go into the regression record as rows.

## Security review of the release

The security specialist reviews `git diff <last-tag>..<candidate>` once, when
the release closes and the regression has passed. It covers:

- argv and logs, for every verb that carries private text;
- every `pkexec` plan and the firewall rules as written;
- sandboxed decoding of everything a device sends;
- the D-Bus and adb surfaces the diff adds or widens;
- the capabilities the marketplace bot will report, as a list for the
  maintainer's review.

The verdict is a document on the release task: pass, or findings with file
and line. Findings are fixed on `develop`; a fix changes the candidate, so the
changed head is regressed again where the fix reaches.

## The owner's go

Omar brings the owner, in one request: the regression record, the security
verdict and the *needs a real device* results. The owner answers go or not for
this release.

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
