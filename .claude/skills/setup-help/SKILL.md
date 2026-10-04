---
name: setup-help
description: Help the person at this computer when a Devices (sceny.devices) feature fails or will not set up: KDE Connect not running or away, a feature turned off, a missing phone permission, notifications that stopped, the gallery's storage, the screen and Wireless debugging. Reads the plugin's own checks and fixes them, without changing the plugin's code, and reports what the plugin's own fix missed. Used by the panel's Fix with AI.
---

Read `docs/internals/help-for-agents.md` in the plugin folder
(`~/.config/omarchy/plugins/sceny.devices`) and follow it. Its rules come
first: never text, ring or open the phone's data; say exactly what root
will do before running it; no personal data leaves this computer.

Then work from what the panel showed you (the problems, and what the
plugin's own fix tried):

1. Read this computer's state: `bin/kdeconnect-bridge doctor`.
2. Read the device's: `bin/kdeconnect-bridge features <id> --adb` and, for
   the screen, `bin/kdeconnect-bridge screen <id>`.
3. Match the symptom in the guide's table; tell the person the cause in a
   sentence and the fix; run it.
4. Read the state again to check it worked, and say so.
5. If the plugin's own fix had been tried and did not work, or there was
   none for it, and you found what does: that is what the automatic fix
   should learn. Follow `reporting.md` (here) to propose an issue: verified,
   shown to the person first, nothing private, KDE Connect's faults on this
   repository only.

For a fault in the plugin itself (a QML error, the bar empty), see the
`diagnose-panel` skill and report it instead of patching the installed copy.
