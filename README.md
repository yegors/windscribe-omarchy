# Windscribe for Omarchy

**Windscribe, built for Omarchy.** A live world map of every Windscribe
location, one click to connect, the kill switch, live tunnel traffic, and
sign-in — all in one bar widget for [Omarchy Quattro](https://omarchy.org).
Click the Windscribe mark and you're somewhere else.

<img src="preview.png" width="720" alt="Windscribe for Omarchy — a live world map, one click to connect, tunnel traffic, built for Omarchy">

## Why it doesn't look like a VPN app

Because it *is* Omarchy, all the way down:

- **It wears your theme.** Every colour, the font, the switches, the
  Windscribe mark, and the world map are drawn from Omarchy's theme tokens.
  Switch from Tokyo Night to Catppuccin Latte and the whole panel —
  coastlines, city dots, the lit city, the traffic chart — follows on the
  spot. The mark is the official badge redrawn as a native vector path, not a
  pasted-in bitmap.
- **It feels like the panels next to it.** The hero, the power switch, the
  rows, the keyboard cursor — the same Quattro components your Wi-Fi and
  Bluetooth panels are built from. `J`/`K` walk it, `Enter` connects, `/`
  finds a city, `←`/`→` flip tabs, `Esc` backs out.
- **It mostly stays out of the terminal.** Install and sign-in each open one
  of Omarchy's own floating terminals (the package install needs your
  password; sign-in needs your credentials and 2FA). When each command
  finishes, Omarchy shows **Done** and closes the terminal after a keypress.
  Everything else is a click in the panel.
- **A map, without a map service.** Every Windscribe city on a world outline,
  the connected one lit and pulsing, hover for the nickname, click to
  connect — all from files inside the plugin. No tiles, no geocoding, no
  requests.
- **Traffic you can see.** While connected, download and upload rates with a
  60-second sparkline and session totals, read once a second from the
  kernel's own counters for the tunnel interface — only while the panel is
  open, so it costs nothing when you're not looking.

It drives the official `windscribe-cli`. No API keys, no tokens, and no
credentials are stored by this plugin — your password and 2FA code go
straight into the CLI's own prompt in a terminal, and Windscribe's client
owns the session from there.

## What you need

- Omarchy Quattro on **x86_64** — Windscribe’s Arch CLI has no ARM build, and
  the panel will say so instead of trying to install
- A Windscribe account — a free one works; sign up at
  [windscribe.com](https://windscribe.com)

That's it. The panel installs the Windscribe CLI for you if it isn't there.

## Install

```bash
omarchy plugin add https://github.com/yegors/windscribe-omarchy.git --enable
```

Then click the Windscribe mark in your bar. The panel walks you through the
rest:

1. **Install Windscribe** — one click; Omarchy opens a terminal, downloads the
   official [CLI-only Arch package](https://windscribe.com/install/desktop/linux_zst_x64_cli)
   from windscribe.com, and installs it with `pacman`. The terminal asks for
   your password, since it's a system package. No AUR, no desktop app — this
   panel is the wrapper.
2. **Sign in** — one click; a terminal opens for your username, password, and
   2FA code. At Omarchy's **Done** prompt, press any key to close it.
3. **Connect** — the switch at the top, a dot on the map, or a row below.

If you'd rather place the widget yourself, drop `--enable` and run:

```bash
omarchy plugin enable com.windscribe.vpn right
```

### Already have the desktop app?

The two Arch packages are mutually exclusive, and both include
`windscribe-cli`. This widget installs the **CLI-only** build so the location
list and map can render in the panel.

If you already have the **desktop app (GUI)**, leave it — the widget still
works. One caveat: `windscribe-cli locations` opens the list in the app
window instead of printing it, so you get free-text connect, favorites,
recents, the fastest-server row, and a shortcut that opens the app's own
list, but not the full map. To switch to the CLI-only build:

```bash
sudo pacman -R windscribe
omarchy restart shell
```

Then click **Install Windscribe** in the panel, or:

```bash
curl -fL -o windscribe-cli.pkg.tar.zst "https://windscribe.com/install/desktop/linux_zst_x64_cli"
sudo pacman -U windscribe-cli.pkg.tar.zst
```

## Update

```bash
omarchy plugin update com.windscribe.vpn
```

## Remove

```bash
omarchy plugin remove com.windscribe.vpn --yes
```

That disables the widget, removes it from your bar, and deletes the plugin
folder. It leaves your Windscribe session, settings, and any active tunnel
alone — disconnect and sign out first if you want those gone too:

```bash
windscribe-cli disconnect
windscribe-cli logout
```

The widget also keeps a small file of your recent locations at
`~/.local/state/omarchy-windscribe/state.json`; delete it if you like.
Windscribe itself uninstalls with `sudo pacman -R windscribe` (or
`windscribe-cli`).

## How to use it

### The bar icon

The Windscribe badge sits in your bar in the theme's foreground colour.
Solid means connected; dimmed means not; breathing means a connect or
disconnect is in flight.

| Action | What it does |
| --- | --- |
| Left-click | Open the panel |
| Right-click | Toggle — connect to the last location, or disconnect |
| Middle-click | Refresh status and the location list |

### The map

Under the header is a world map. Every dot is a Windscribe city; the bright,
pulsing one is where your traffic exits right now. Hover a dot for the city,
country, and nickname; click it to connect there.

It's drawn entirely offline: the coastlines are a bundled Natural Earth
outline, the dots come from `windscribe-cli locations` matched against a
bundled coordinate table, and nothing is ever fetched. The map deliberately
does **not** show *your* location — finding it would take a geo-IP lookup,
which this plugin promises never to make. Lighting the exit city is the
honest version.

### The power switch

The switch at the top is the same toggle as right-click: connect to your last
location (Windscribe's default), or disconnect. While a connect is running
the widget shows "Connecting to …" and flips the switch optimistically; if it
fails, the switch drops back and the reason is shown under the map for a few
seconds.

### Locations

The **Fastest location** row asks Windscribe for the best server for you.
Below it: your three most recent locations, your starred favorites, and — on
the CLI-only build — search over every location by city, country, or
nickname ("The 6" works). Type anything and press Enter to connect to it,
even if it isn't in the list — ISO codes and region names work too. `F` stars
the highlighted row; favorites and recents float to the top.

### Protection

The second tab holds how you're protected:

- **Kill switch** — Windscribe's firewall. If the VPN drops, every packet is
  blocked until you reconnect; nothing leaks in the gap. If it's set to
  *Always On* in Windscribe preferences, the CLI can't turn it off and the
  switch shows as locked.
- **Preferred protocol** — WireGuard, OpenVPN UDP/TCP, Stealth, or WStunnel,
  applied on the next connect. Stealth and WStunnel are built for networks
  that block VPNs.
- **Notifications** — "connected" on connect, and a critical alert if the
  tunnel drops unexpectedly. The alert tells you whether the kill switch is
  holding the line or you're exposed.
- **Sign out** — asks for a second click, because signing out also
  disconnects and drops the firewall.

### The detail rows

When connected: your VPN IP (with a **↻** button — one click for a fresh IP
on the same server), the live protocol and port, and your data usage. On a
free plan the usage row grows a thin meter that turns urgent past 90%.

### Traffic

While you're connected, download and upload rates with a 60-second sparkline
and the session's totals and uptime. Download is the filled area with a solid
line; upload is the dashed line — one ink, told apart by shape, not colour,
so it reads the same on every theme and for colour-blind eyes. Hover the
chart to read the values at any second. The numbers come from
`/sys/class/net/<tunnel>/statistics`, found via `ip route get` so the
interface never needs to be named, and are read only while the panel is open.

### Keyboard

| Key | What it does |
| --- | --- |
| `J`/`K` or arrows | Move through the location list |
| `Enter` | Connect to the highlighted row (or toggle, from the header) |
| `F` | Star/unstar the highlighted location |
| `/` | Focus location search |
| `←`/`→` | Switch between Locations and Protection |
| `T` | Connect/disconnect |
| `W` | Toggle the kill switch |
| `R` | Refresh status and locations |
| `Esc` | Close search, then the panel |

## Settings

Configurable from Omarchy's widget settings (inline on the widget's entry in
`~/.config/omarchy/shell.json`):

| Setting | Default | What it controls |
| --- | --- | --- |
| `refreshIntervalSec` | 5 | Status poll interval while the panel is closed. Open panel: every 3 s. |
| `preferredProtocol` | *(empty)* | `wireguard`, `udp`, `tcp`, `stealth`, or `wstunnel`, optionally with a port (`stealth:443`). Empty = app default. Also settable from the panel. |
| `notifications` | `on` | Desktop notifications on connect and unexpected drops. |
| `favoriteLocations` | `[]` | Starred locations; managed with the panel's stars. |

## Scripting and keybindings

The widget answers Omarchy Shell IPC on its plugin id:

```bash
vpn=com.windscribe.vpn
omarchy-shell "$vpn" toggle          # open/close the panel
omarchy-shell "$vpn" toggleVpn       # connect/disconnect
omarchy-shell "$vpn" connect         # last location
omarchy-shell "$vpn" best            # fastest server
omarchy-shell "$vpn" connectTo "Toronto"
omarchy-shell "$vpn" disconnect
omarchy-shell "$vpn" firewall on
omarchy-shell "$vpn" rotate          # new IP, same server
omarchy-shell "$vpn" refresh
omarchy-shell "$vpn" status         # JSON
```

Hyprland keybinding example:

```
bind = SUPER SHIFT, V, exec, omarchy-shell com.windscribe.vpn toggleVpn
```

## Security and privacy

This plugin runs unsandboxed inside the Omarchy shell process, like every
Omarchy plugin. It:

- stores no credentials, tokens, or account data
- makes no network requests of its own during normal use — the map,
  coordinates, and world outline are bundled; installing the CLI downloads
  the official package from windscribe.com
- runs the fixed package installer in Omarchy's floating terminal; that
  terminal invokes `sudo pacman -U` and owns the password prompt
- runs direct CLI and system probes as argument lists, not through a shell;
  install and sign-in use **fixed literal shell strings** in Omarchy's
  terminal, and nothing user-typed crosses that shell boundary
- location names echoed into `windscribe-cli connect` are validated against a
  strict character allow-list first, and every string the CLI prints is
  sanitised before it reaches a label
- reads the tunnel's byte counters under `/sys/class/net/` once a second
  while the panel is open, and writes exactly one file of its own
  (`~/.local/state/omarchy-windscribe/state.json`: recent location labels)

**What's visible to other processes.** Omarchy exposes every plugin over a
Quickshell IPC socket that only your own user (and root) can reach. Through
it, any process running as you can call this widget's `connect`,
`disconnect`, and `status` methods — the same things that process could
already do by running `windscribe-cli` directly. `status` returns connection
facts (state, city, IP, firewall), never account identity.

**Notifications** go through `notify-send` and contain only the connection
state and location.

## Notes

**How the two builds are told apart.** The CLI-only package ships a systemd
user unit (`/usr/lib/systemd/user/windscribe.service`) that the GUI package
doesn't; the widget checks for that file once. On GUI builds it never runs
`windscribe-cli locations` on its own, because that opens the app window —
the one location-list fetch a GUI user gets is the explicit "open in app"
row.

**One CLI at a time.** `windscribe-cli` allows a single instance. The widget
serializes every call: polls defer politely, actions take priority, and a
status poll that collides with a CLI you're running in a terminal (sign-in
included) just skips that beat.

**Parsing.** Status and location output are parsed against the exact formats
in [Windscribe/Desktop-App](https://github.com/Windscribe/Desktop-App)
(`src/windscribe-cli/strings.cpp`), including the tunnel-test `*` marker and
`[Network interference]` suffix.

## Credits

The world outline is [Natural Earth](https://www.naturalearthdata.com/)
1:110m land data — free, public-domain map data made by volunteers — projected
once into `World.js` by a build script. The Windscribe badge is drawn from
the official mark in
[Windscribe/Desktop-App](https://github.com/Windscribe/Desktop-App),
recoloured to the active theme. The panel's map-and-traffic design owes a nod
to [omaproton-vpn](https://github.com/grichard99/omaproton-vpn) (MIT), whose
one-ink instrument style this widget follows.

## License

[MIT](LICENSE)
