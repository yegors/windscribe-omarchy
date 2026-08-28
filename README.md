# Windscribe for Omarchy

A bar widget for [Windscribe](https://windscribe.com) VPN on Omarchy. Click the badge, pick a city, connect, watch the traffic. Firewall, protocol selection, and IP rotation are in the panel too.

This is not the official desktop app. I installed Omarchy, wanted the VPN on the bar, and wired the plugin to the official Linux CLI so it talks to the same client you'd run in a terminal.

<img src="preview.png" width="840" alt="Windscribe for Omarchy: connection panel and settings">

## Install

```bash
omarchy plugin add https://github.com/yegors/windscribe-omarchy.git --enable
```

Open the Windscribe badge on the bar. If the CLI isn't installed yet, the panel will offer to install it (that step asks for sudo in a floating terminal). Then sign in. Username and password go into Windscribe's own prompt, not into this plugin.

The installer uses `curl`, `jq`, GnuPG, and `pacman`, all included with a
normal Omarchy installation.

From there: connect, search exits with `/`, star the ones you want at the top. Right click the badge to connect or disconnect without opening the panel. `s` opens settings.

## Updating

```bash
omarchy plugin update com.windscribe.vpn
omarchy-restart-shell
```

That second command restarts the Omarchy shell. Plugin updates don't always reload in place, so if you pulled a new version and it still looks like the old one, you probably skipped the restart.

## Remove

```bash
omarchy plugin remove com.windscribe.vpn
```

This removes the bar widget. It does not uninstall the Windscribe CLI.
An active tunnel or Firewall also stays active after the widget is gone. If
you want normal networking first, run these separately:

```bash
windscribe-cli status
windscribe-cli disconnect
windscribe-cli firewall off
omarchy plugin remove com.windscribe.vpn
```

To remove the CLI package too:

```bash
sudo pacman -R windscribe-cli
```

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

## Design

The panel is typographic: dashed and dotted leader lines, numbered exit rows,
`[ on ]` bracket toggles, and one full-width connect button. Colors are
derived from the active Omarchy theme's foreground and accent, so it follows
your theme instead of shipping its own.

Decisions that shape it:

- Windscribe's own terms, as-is: fastest location, Firewall, Favourites,
  preferred protocol.
- Omarchy's panel, theme, and keyboard conventions win over brand styling.
- Nothing is shown that can't be measured. No guessed origin, no per-exit
  latency (the CLI doesn't expose ping per city; the fastest-location row is
  Windscribe's own latency pick), no DNS safety claims, no synthetic privacy
  score.
- Copy stays short, and consequences are stated where you act.
- Packaging details stay out of the product UI.

## Widget settings

Stored with the Omarchy bar entry:

- `refreshIntervalSec`: closed-panel status interval, from 2 to 60 seconds
- `preferredProtocol`: protocol with optional `:port`
- `notifications`: connection alert toggle
- `motion`: interface animation toggle
- `favoriteLocations`: managed by the stars in the exit list
- `lastLocation`: last connected city label, for the disconnected hero

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
- asks the official Windscribe update API for the latest supported stable Arch
  CLI and only accepts its expected HTTPS CDN path
- verifies both the API-provided SHA-256 and the package's detached signature
  against the [Windscribe Linux signing key](https://windscribe.com/windscribe_linux_signing_key.pub)
  bundled with this plugin before asking for sudo
- downloads that package into a private mktemp directory, not a shared `/tmp` path
- caps subprocess stdout and stderr before the Omarchy shell collects it
- validates user-entered locations before they reach the CLI
- renders CLI output as plain, sanitized text
- reads tunnel byte counters only while the panel is open
- stores short-lived sign-in/update result markers under a `0700` directory
  at `~/.local/state/omarchy-windscribe/` (written with `mktemp` plus `mv -T`,
  read through bounded `cat`). Favourites and the last-city hero label persist
  in the Omarchy widget settings, not a plugin-private file.

Install, sign-in, and update use Omarchy's floating terminal because those
commands may need interactive input.

## Development

```bash
./scripts/validate.sh
```

The validator runs Omarchy plugin validation, shell syntax checks, `qmllint`,
optional `shellcheck`, and the Node tests when Node is available.

## Acknowledgements

The Windscribe badge is redrawn from the official
[Windscribe Desktop App](https://github.com/Windscribe/Desktop-App) asset and
follows the active Omarchy theme.

## License

[MIT](LICENSE)
