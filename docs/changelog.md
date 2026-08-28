# Changelog

## Validation matrix

Check these states on Omarchy before a release:

- setup: probing, installable, unsupported, installing
- authentication: signed out, signing in, signed in
- tunnel: disconnected, connecting, verifying, connected, disconnecting
- failure: no internet, command error, network interference, unexpected drop
- Firewall: Off, On, Always On
- allowance: unlimited, finite, above 90%
- locations: loading, populated, unavailable, no search match
- motion: on and off
- themes: light, dark, square corners, rounded corners
- input: pointer, keyboard, reduced panel height

## 0.5.4 — no FileView, no recents file

Marketplace re-review flagged FileView reading and writing a predictable
`state.json` independently of `stateDirPrepareCommand()`. That file only
stored the last three locations. Pinning already exists: star a favourite.

Persisted recents are gone. There is no `state.json` and no FileView.
Favourites stay in Omarchy widget settings. The disconnected hero keeps
the last connected city as one `lastLocation` string in that same store
and looks up nickname/region from the live locations list. The state
directory remains owner-private (`0700`) for short-lived sign-in/update
result markers only (`mktemp` plus `mv -T`, bounded `cat`).

## 0.5.3 — installer fix from marketplace review

On a default Arch/Omarchy setup (`LocalFileSigLevel = Optional`), the 0.5.2
installer downloaded the detached signature next to the package as
`windscribe-cli.pkg.tar.zst.sig`. `pacman -U` then re-verified that signature
against **pacman's** keyring, which does not hold Windscribe's key, and the
install failed with "required key missing from keyring" — after the plugin's
own pinned-key verification had already passed.

The signature is now stored under a non-adjacent name
(`windscribe-cli.sig`), so pacman installs the already-verified package
without consulting its keyring. The plugin's `gpgv` check against the
repository-pinned key remains the trust boundary and still runs before
`sudo`. Nothing is imported into `pacman-key`, keeping system trust state
untouched. A regression test asserts the signature path stays non-adjacent.

## 0.5.2 — marketplace security hardening

- The first-run installer discovers the newest supported stable Arch CLI from
  Windscribe's platform-specific update API. Beta and unsupported entries,
  rollback versions, malformed hashes, and URLs outside the expected CDN path
  are refused.
- The repository pins Windscribe's Linux signing key (primary fingerprint
  `441B49B9D5AFCCAC158444F4E699B988472B0781`, signing subkey
  `495B477E0F3FA67C20ED94B2BD09F61D249A38FA`). Both the API SHA-256 and
  the CDN's detached package signature must verify before `sudo pacman` runs.
- The package remains inside a private `mktemp` directory through verification
  and installation, and the download itself is capped at 64 MiB.
- Every subprocess stream read by Quickshell now passes through a producer-side
  byte limiter. Status, ports, and fallbacks allow 16 KiB per stream; actions
  allow 64 KiB; the full location list allows 256 KiB. Overflow returns a
  distinct failure instead of feeding an unbounded `StdioCollector`.
- The limiter forwards termination signals so existing watchdog and
  action-cancellation behavior remains intact. `setpriv --pdeathsig TERM`
  also ties the CLI to the limiter if Quickshell kills the wrapper on reload.
- Removal docs explicitly warn that uninstalling the widget does not disconnect
  the tunnel or disable the Firewall, and give the optional cleanup commands.

## 0.5.1 — state directory and command hardening

- The state directory is created and repaired as owner-private (`0700`),
  refusing a symlink at its path.
- Sign-in and update result markers are written through `mktemp` plus
  `mv -f -T`, so a planted marker is replaced rather than followed, and are
  read back through bounded `cat`.
- Tests cover the directory preparation and marker commands.

## 0.5.0 — the terminal panel

The instrument-card look was replaced with the terminal design: dashed and
dotted leader lines, numbered exit rows, `[ on ]` bracket toggles, one
full-width block button, and a settings *view* (`s` / `esc`) instead of a
tab strip.

Every value shown must be CLI-sourced, so the design's demo data was
replaced with reality:

- Per-exit latency (`12ms`) has no `windscribe-cli` source → replaced by the
  real `10g` / `pro` flags and the favourite star. The fastest-location row
  keeps Windscribe's own latency-based choice.
- Demo protocols (`websocket`, `openvpn tcp`) → the Linux client's real set:
  wireguard, udp, tcp, stealth, wstunnel; ports come live from
  `windscribe-cli ports`.
- "start on boot" is not CLI-settable on the GUI build → dropped; the
  general section instead carries real rows: appearance (theme-bound), data
  allowance, rotate ip, update, account, sign out.
- The demo's cycling IP → `windscribe-cli ip rotate` behind the header
  rotate control.
- Hardcoded design colors → alpha ramps over the Omarchy theme foreground,
  with `Color.accent` as the signal colour, so every theme keeps the
  hierarchy. The inverted connect button and dropdown surfaces derive an
  opposite pole from the foreground's HSL lightness.
- `TunnelInstrument.qml` retired; the hero + button + stats + wave live in
  `Panel.qml`.

Later 0.5.0 fixes from on-device runs: the hero renders identically in both
tunnel states (city big, `nickname · region` below, resolved from the
locations list even when the CLI reports the combined "City Nickname"
form); traffic counters and connection time are cumulative per connection
instead of resetting when the panel closes; and the transient "Connected:
City" status line was removed so the panel no longer resizes on connect.
