[Devices](../../README.md) › Internals › Opening a notification where it belongs

# Opening a notification where it belongs (#122)

Clicking a notification in the panel should open **exactly what it is
about** — the chat, the email, the order — in that app's window here, the
way Microsoft Phone Link does. This is what the phone's own tap does: it
fires the notification's `contentIntent`. This page records what is
possible from here, what is already done, and what is left to the owner.

## What the notification gives us

KDE Connect forwards each notification with Android's key as its id
(`user|package|id|tag|uid`), the title, the text, and the notification's
own actions and inline reply. It does **not** forward the
`contentIntent` (the tap target) or any deep link: its protocol was never
built to carry "open it" (see [#29](https://github.com/sceny/omarchy-devices/issues/29),
[#30](https://github.com/sceny/omarchy-devices/issues/30)). So the id gives
us the **package** — enough to open the app in a window
([#116](https://github.com/sceny/omarchy-devices/issues/116)) — but not the
screen inside it.

## Already done: the one class with enough data

For **SMS and MMS**, the plugin is its own source of the conversation. A
text-message notification already opens the exact thread in the panel's
Messages view (`openNotificationConversation` → `threadForNotification`),
not just the Messages app. For this class, #122 is effectively met today,
by the plugin's own data rather than by firing anything on the phone.

Every other app (WhatsApp, Signal, email, a shop) opens its window
(`Model.appForNotification` → `openApp`, on the app's own virtual display).

## Route 1: fire the `contentIntent` over adb — needs a helper

The exact tap means invoking the notification's `PendingIntent`. From the
computer, over the already-trusted adb (shell uid 2000), this was
investigated against the AOSP framework and a real device (Android 16,
SDK 36):

- **No shell command fires it.** `cmd notification` (Android 16) has
  `list`, `get`, `post`, `snooze`; no `click`. `cmd statusbar` clicks QS
  tiles, not notifications. `am`/`cmd activity` cannot send another app's
  `PendingIntent`.
- **The binder path needs a registered listener.**
  `IStatusBarService.onNotificationClick(key, nv)` and
  `INotificationManager.getActiveNotificationsFromListener(token, …)` both
  require a token from `registerListener`, which is guarded by
  `enforceSystemOrSystemUI` (system/phone uid, else the signature-level
  `STATUS_BAR_SERVICE`). On the device the shell package lists
  `STATUS_BAR_SERVICE` as granted, so a **scrcpy-style server-side helper**
  (a dexed class run with `app_process` as the shell user, exactly as
  `scrcpy-server` runs) could plausibly register as a listener, read the
  live `StatusBarNotification` for a key, and call
  `sbn.getNotification().contentIntent.send(…)` — with
  `ActivityOptions.setLaunchDisplayId(<the app's virtual display>)` so it
  lands in the window here, not on the phone's own screen.
- This is a real sub-project: its own Java source, a dex build, shipped
  like `scrcpy-server`, and a first real fire that opens a real app — the
  **owner's go**, as the screen is. It is not faked in the meantime:
  until it exists, the notification opens the app, and the limits page
  says the screen inside it is not reached yet.
- It would also answer [#30](https://github.com/sceny/omarchy-devices/issues/30):
  an action that opens a screen on the phone (*Call*) could fire on the
  app's virtual display instead of doing nothing.

A build toolchain for the helper (JDK + `d8`) is not on this machine, and
running a downloaded one is not allowed here, so the helper was designed
but not built in this pass.

## Route 2: per-app deep links — rejected as faking

Mapping a notification to an app-specific deep link (a `content://` URI, an
intent extra) would need a hand-written, brittle table per app, guessed
from the title and text KDE Connect sends. That is exactly the "a feature
no source offers is not faked" rule: the notification does not carry the
target, so we would be guessing it. Not built.

## Route 3: KDE Connect upstream — the clean fix

The honest home for this is KDE Connect itself: its Android app has
notification access and holds the real `PendingIntent`. A protocol
addition — "open this notification on the device" (fire its
`contentIntent`), ideally on a given display id — would let the plugin ask
for the exact screen without a helper of our own. Tracked on this
repository as a KDE Connect fault/gap (`external:kde-connect`); the
proposal draft is in the pull request for the owner to file. The plugin's
handling (the helper, if built) goes when KDE Connect ships its own.

## Where this leaves #122

- SMS/MMS: the exact conversation already opens (plugin's Messages).
- Every other app: its window opens; the screen inside it waits on the
  helper (Route 1, owner's go) or KDE Connect (Route 3).
