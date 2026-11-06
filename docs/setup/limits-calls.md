[Devices](../../README.md) › Setup › [What it cannot do](limits.md) › Calls

# Calls: what it cannot do

- Without [Calls here](calls-here.md), the panel cannot answer a call,
  carry its audio, or tell when it was **answered or ended**: a ringing
  card gives up after 45 s, and a call you decline shows as missed
  ([#60](https://github.com/sceny/omarchy-devices/issues/60)). With Calls
  here, the card follows the call to its end.
- **Muting the ringer** from the computer waits for KDE Connect to pass it
  on ([#61](https://github.com/sceny/omarchy-devices/issues/61)).
- Once a call's audio is here, it goes back to the phone from the
  **phone's** audio button: Bluetooth hands-free has no way to send it back
  from the computer.
- With a Bluetooth **headset** on the computer, its microphone needs its
  own hands-free link, so its sound is plainer during the call.

Setup: [Calls here](calls-here.md) · All limits: [What it cannot do](limits.md)
