[Devices](../../README.md) › Setup › Screen and apps

# Set up the screen and apps

Once per phone. The screen and the apps come from
[scrcpy](https://github.com/Genymobile/scrcpy) over adb, not KDE Connect.
What they do: [Screen and apps](../screen-and-apps.md).

![Screen and apps: the steps on the phone and the pairing QR code (demo data)](../images/screen-setup.png)

**Settings ›** the device **› Screen and apps** walks you through it, and
ticks each step as it sees it done:

1. **Install** scrcpy and adb (a card says what, then your password).
2. On the phone, turn on **Developer options**: tap *Build number* seven
   times (*Settings › About phone*).
3. Turn on **Wireless debugging** in *Developer options*, on this Wi-Fi.
4. **Show the code** here; on the phone, *Wireless debugging › Pair device
   with QR code*, and scan it.

The **Screen** shortcut then joins the device's shortcuts. *Opens under the
bar* or *Opens as a window* on the same page. Android 10 and older:
*USB debugging* and a cable instead.

Not wanted? Its switch on the device's page turns it off: no screen, no
apps, nothing about it to fix.

## When it stops working

- *Wireless debugging is off*: Android turns it off after a restart or on
  another Wi-Fi. Turn it on; the screen (or the app) then opens by itself.
  A *Quick settings developer tile* makes that one tap.
- *Allow USB debugging*: answer the prompt on the phone, with *Always
  allow from this computer*.
- Locked: the phone wakes, and an app opens once you unlock it.

## Security

Wireless debugging lets a paired computer control the phone fully: what
that means and how to take it back, in
[Security](../security.md#the-screen-and-apps-what-wireless-debugging-allows).
