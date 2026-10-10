[Devices](../../README.md) › Setup › From anywhere

# Set up From anywhere

Once per computer, then once per phone. What it does:
[From anywhere](../use/anywhere.md).

A device that is away offers **From anywhere** on its card. The page walks
you through it, and ticks each step as it sees it done. *Set it up* does what it can:

1. **Tailscale on this computer**, with Omarchy's own installer (as
   *Install › Service › Tailscale* does): a card says what it does, then a
   terminal asks for your password and a browser page signs you in.
   NordVPN Meshnet, if it is on, is used instead.
2. **On the phone**: install Tailscale from its store and sign in with the
   same account (with Meshnet: turn it on in NordVPN).
3. **KDE Connect gets its address**, by itself once the phone shows up on
   the mesh. When the panel cannot tell which device is yours, it lists
   your phones: pick it.

The firewall's fix (*Diagnostics › Firewall*, or the first run's card) lets KDE Connect in from
your home and office networks and from the mesh, never from everyone.

**Its address** on the same page takes any IP that reaches the phone (your
own VPN, another network): KDE Connect tries it as well.

## When it stops working

- *KDE Connect lost its address*, or the phone's address changed: *Fix*
  gives it the new one.
- *Signed out* on This computer: *Set up* runs Omarchy's installer again,
  which signs you back in.

Take it back: *Stop reaching it through Tailscale* on its page.
