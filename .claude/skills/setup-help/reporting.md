# Reporting what the plugin's own fix missed

Read this only after you fixed something the plugin's automatic fix could
not, or found a fault it does not know. This follows Omarchy's own rules for
reporting (`/usr/share/omarchy/default/agents/skills/diagnose-crash/reporting.md`):
the same three conditions, the same search first, the same signature.

## Why report

The panel's *Fix* is meant to cover what goes wrong. When it did not, the
report teaches it: the next person gets the fix in one click.

## Where it goes

| The fault is in | File it on |
|---|---|
| Devices (the plugin, its automatic fix) | `sceny/omarchy-devices`, label `bug` |
| KDE Connect | **`sceny/omarchy-devices` only**, label `external:kde-connect`. Never on KDE's trackers (bugs.kde.org, invent.kde.org): KDE has strict rules against AI-written reports. The owner's KDE Connect specialist takes it from there. |
| Omarchy | `basecamp/omarchy`, following Omarchy's own `reporting.md` (linked above) |
| Another project (scrcpy, Hyprland, an Arch package…) | that project's own repository, following its contribution rules; if they forbid AI-written reports, do not file there: say so to the person |

## Three conditions, all required

1. **It is verified**, on evidence: you saw the fault and what fixed it. A
   guess is not a report.
2. **The person has explicitly agreed.** Show them the exact title and body,
   and wait for a yes. Never file unprompted.
3. **The machine can file it:** `gh auth status` succeeds. If `gh` is missing
   or not logged in, do not install or log it in: hand the person the
   finished text to submit themselves.

## Nothing private, ever

A report never carries anything about the person or their phone. Leave out,
or replace with a neutral placeholder:

- phone numbers (use 555 numbers if one is needed), contact names, message
  or notification text, app names from their notifications;
- device names and ids, the phone's model when it is not the point, serial
  numbers, adb serials, KDE Connect device ids;
- IP addresses, network names (SSID), hostnames, user names, home paths
  (write `~`);
- anything from `kdeconnect-bridge snapshot`, `features` or `doctor` as it
  is: describe the state ("the gallery's mount did not answer") instead of
  pasting it.

Re-read the body for these before showing it to the person.

## Search before filing

```bash
gh search issues --repo sceny/omarchy-devices "<what failed>"
gh issue list --repo sceny/omarchy-devices --state all --search "<feature> <symptom>"
```

Include closed issues: one closed as fixed that still happens is a
regression, worth more than a new issue. If the same fault is there, add a
comment only when you bring something it lacks (a narrower trigger, the fix
that worked); "it happens to me too" is noise.

## What the issue says

- **Title:** what the automatic fix missed, in a line ("Gallery: Fix does not
  clear a mount left after the phone restarts").
- **What the panel showed** (the feature, its state, the plugin's fix and its
  result), **what was wrong**, **what fixed it** (the commands, without
  private data), and **what the automatic fix could do** to cover it.
- Versions: `omarchy version`, the plugin's (`manifest.json`), KDE Connect's
  (`kdeconnect-cli --version`), Android's major version if it matters.

## Signing

End with a line naming the model and agent harness that wrote it:

> Filed by \<model name\> via \<agent harness\>.

Use your actual names; if you are not sure, say so rather than invent one.
