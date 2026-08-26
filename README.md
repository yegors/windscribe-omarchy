# Windscribe for Omarchy

Windscribe controls that belong in the bar.

Connect, pick a location, watch the tunnel, rotate your IP, and control the
Firewall without turning a terminal into permanent desk furniture.

<img src="preview.png" width="720" alt="Windscribe for Omarchy with the live Tunnel Instrument, quick locations, and searchable location list">

## What it does

- Connects to your last exit or **Best Location**
- Searches Windscribe cities, regions, country codes, and datacenter nicknames
- Keeps **Favourites** and recent destinations close
- Shows live download/upload activity from the tunnel interface
- Displays protocol, port, VPN IP, observed transfer, and data allowance
- Rotates the current VPN IP
- Controls the Windscribe **Firewall**
- Selects a Preferred Protocol and a live, protocol-specific port
- Reports tunnel verification and network-interference states
- Supports mouse and keyboard control

Connection controls use the official `windscribe-cli`; live traffic comes
from the tunnel interface's kernel counters.

## Install

```bash
omarchy plugin add https://github.com/yegors/windscribe-omarchy.git --enable
```

Then open the Windscribe bar widget:

1. **Install Windscribe CLI**
2. **Sign in**
3. **Connect**

Credentials are entered directly into Windscribe's terminal prompt. The plugin
does not receive or store them.

## The home screen

The **Tunnel Instrument** replaces the usual VPN world map with information
that matters now:

- **This device → VPN exit** shows tunnel state
- Moving packets reflect real download and upload activity
- The exit ring reflects Firewall state
- The center capsule shows the active protocol and port
- The mirrored activity band shows up to 60 seconds observed while open
- VPN IP, allowance, rates, and this view's transfer/time stay visible

The instrument never looks up or guesses your physical location. If motion is
disabled, the same states remain visible without animation.

## Locations

**Best Location** uses Windscribe's latency-based choice.

The location list puts Favourites and recent exits first, followed by every
available datacenter. Search accepts a city, region, country code, or nickname.
Rows retain Windscribe's **Pro** and **10 Gbps** labels.

Selecting a datacenter nickname connects to that exact exit. Selecting a city
lets Windscribe choose an exit there.

## Connection controls

- **Firewall** blocks traffic outside the VPN tunnel
- **Preferred Protocol** offers Automatic, WireGuard, UDP, TCP, Stealth, and
  WStunnel
- **Port** is populated from `windscribe-cli ports` for the selected protocol
- **Connection alerts** cover successful connections and unexpected drops
- **Interface motion** disables decorative state animation
- **Rotate IP** requests a new address at the current location
- **Update Windscribe** runs the official updater when one is advertised

When signing out, an enabled Firewall stays enabled.

## Bar controls

- Left click: open or close the panel
- Right click: connect or disconnect
- Middle click: refresh status and locations

The badge is solid while active, dim while disconnected, and breathes during a
state change when interface motion is enabled.

## Keyboard

- `J` / `K` or arrows: move
- `Enter`: activate the selected control
- `/`: search locations
- `F`: toggle a Favourite
- `←` / `→`: switch Locations / Connection
- `T`: connect or disconnect
- `W`: toggle Firewall
- `R`: refresh
- `Esc`: leave search or close the panel

## Settings

Widget settings are stored with the Omarchy bar entry:

- `refreshIntervalSec`: closed-panel status interval, from 2 to 60 seconds
- `preferredProtocol`: protocol with optional `:port`
- `notifications`: connection alert toggle
- `motion`: interface animation toggle
- `favoriteLocations`: managed by the stars in the location list

## Scripting

```bash
vpn=com.windscribe.vpn
omarchy-shell "$vpn" toggle
omarchy-shell "$vpn" toggleVpn
omarchy-shell "$vpn" best
omarchy-shell "$vpn" connectTo "The 6"
omarchy-shell "$vpn" disconnect
omarchy-shell "$vpn" firewall on
omarchy-shell "$vpn" rotate
omarchy-shell "$vpn" refresh
omarchy-shell "$vpn" status
```

## Privacy and security

The plugin:

- stores no credentials, tokens, or account identity
- makes no location or telemetry requests of its own
- passes normal commands as argument arrays rather than shell strings
- validates user-entered locations before they reach the CLI
- renders CLI output as plain, sanitized text
- reads tunnel byte counters only while the panel is open
- stores recent location labels plus short-lived sign-in/update result markers
  under `~/.local/state/omarchy-windscribe/`

Install, sign-in, and update use Omarchy's floating terminal because those
commands may need interactive input.

## Development

```bash
./scripts/validate.sh
```

The validator runs Omarchy plugin validation, `qmllint`, and the Node parser
tests when Node is available.

## Acknowledgements

The Windscribe badge is redrawn from the official
[Windscribe Desktop App](https://github.com/Windscribe/Desktop-App) asset and
inherits the active Omarchy theme.

Early panel integration research referenced
[OmaProton VPN](https://github.com/grichard99/omaproton-vpn) under MIT. The
current map-free tunnel visualization, Windscribe location experience, and
copy were rebuilt for this plugin.

## License

[MIT](LICENSE)
