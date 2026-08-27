# Windscribe for Omarchy

A bar widget for [Windscribe](https://windscribe.com) VPN on Omarchy. Click the badge, pick a city, connect, watch the traffic. Firewall, protocol selection, and IP rotation are in the panel too.

This is not the official desktop app. I installed Omarchy, wanted the VPN on the bar, and wired the plugin to the official Linux CLI so it talks to the same client you'd run in a terminal.

<img src="preview.png" width="840" alt="Windscribe for Omarchy: connection panel and settings">

## Install

```bash
omarchy plugin add https://github.com/yegors/windscribe-omarchy.git --enable
```

Open the Windscribe badge on the bar. If the CLI isn't installed yet, the panel will offer to install it (that step asks for sudo in a floating terminal). Then sign in. Username and password go into Windscribe's own prompt, not into this plugin.

From there: connect, search exits with `/`, star the ones you want at the top. Right click the badge to connect or disconnect without opening the panel. `s` opens settings.

## Updating

```bash
omarchy plugin update com.windscribe.vpn
omarchy-restart-shell
```

That second command restarts the Omarchy shell. Plugin updates don't always reload in place, so if you pulled a new version and it still looks like the old one, you probably skipped the restart.

## Keyboard

- `J` / `K` or arrows: move
- `Enter`: connect, or toggle the selected control
- `/`: search exits
- `F`: star or unstar a favourite
- `S` or `←` / `→`: settings and back
- `T`: connect or disconnect
- `W`: toggle Firewall
- `R`: refresh
- `Esc`: leave search, close a menu, go back, then close

Middle click the badge to refresh status and locations.

Protocol and port changes apply on the next connect. Sign-out asks for a second confirm, and if the Firewall is on it stays on.

The fastest-location row is Windscribe's own latency pick. This plugin doesn't measure ping per city because the CLI doesn't expose it, and it doesn't guess your physical location.

## Widget settings

Stored with the Omarchy bar entry:

- `refreshIntervalSec`: closed-panel status interval, from 2 to 60 seconds
- `preferredProtocol`: protocol with optional `:port`
- `notifications`: connection alert toggle
- `motion`: interface animation toggle
- `favoriteLocations`: managed by the stars in the exit list

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
- downloads the CLI package into a private mktemp directory, not a shared `/tmp` path
- validates user-entered locations before they reach the CLI
- renders CLI output as plain, sanitized text
- reads tunnel byte counters only while the panel is open
- stores recent location labels plus short-lived sign-in/update result markers
  under a `0700` directory at `~/.local/state/omarchy-windscribe/`

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
follows the active Omarchy theme.

## License

[MIT](LICENSE)
