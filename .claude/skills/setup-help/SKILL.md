---
name: setup-help
description: Help the person at this computer when a Devices (sceny.devices) feature fails or will not set up: KDE Connect not running or away, a feature turned off, a missing phone permission, notifications that stopped, the gallery's storage, the screen and Wireless debugging. Reads the plugin's own checks and fixes them on the person's go, without changing the plugin's code. Used by the panel's Diagnose.
---

Read `docs/internals/help-for-agents.md` in the plugin folder
(`~/.config/omarchy/plugins/sceny.devices`) and follow it: its rules come
first (ask before any change, never text, ring or open the phone's data,
say exactly what root will do before running it, no personal data out).

Then work from the error you were given:

1. Read this computer's state: `bin/kdeconnect-bridge doctor`.
2. Read the device's: `bin/kdeconnect-bridge features <id> --adb` and,
   for the screen, `bin/kdeconnect-bridge screen <id>`.
3. Match the symptom in the guide's table; tell the person the cause in a
   sentence and the fix you propose; run it only on their go.
4. Check it worked (read the state again) and say so.

For a fault in the plugin itself (a QML error, the bar empty), see the
`diagnose-panel` skill and report it instead of patching the installed copy.
