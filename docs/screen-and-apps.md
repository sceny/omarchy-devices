[Devices](../README.md) › Screen and apps

# Screen and apps

The phone's screen in a window here, with your mouse and keyboard (the
**Screen** shortcut), and its [apps](apps.md) each in a window. It comes
from [scrcpy](https://github.com/Genymobile/scrcpy), not KDE Connect, and
is set up once per device.

![Screen and apps: the steps on the phone and the pairing QR code (demo data)](images/screen-setup.png)

## Set it up

**Settings › Screen and apps** on the device's page walks you through it:

1. **Install** scrcpy and adb (it asks for your password).
2. On the phone, turn on **Developer options**: tap *Build number* seven
   times (*Settings › About phone*).
3. Turn on **Wireless debugging** in *Developer options*, on this Wi-Fi.
4. **Show the code** here; on the phone, *Wireless debugging › Pair device
   with QR code*, and scan it.

The **Screen** shortcut then joins the device's shortcuts. It opens
**docked**, in the phone's shape under its chip, on every workspace, or
*as a window* (its Screen and apps page). Full screen: Omarchy's pop-out
key, then its full screen key; the page shows your keys.

Android 10 and older: *USB debugging* and a cable instead.

## When it stops working

- *Wireless debugging is off*: Android turns it off after a restart or on
  another Wi-Fi. Turn it on; the screen (or the app) then opens by
  itself. A *Quick settings developer tile* makes that one tap.
- *Allow USB debugging*: answer the prompt on the phone, with *Always
  allow from this computer*.

## Privacy

Only a computer that scanned your code can control the phone; take that
back on the phone: *Developer options › Revoke USB debugging
authorizations*.
