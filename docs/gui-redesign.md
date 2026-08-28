# GUI redesign

## Goal

Give the plugin a distinct Windscribe identity and make the home screen useful
without a world map.

Research completed on 2026-08-26 against:

- Windscribe Linux CLI and product documentation
- Windscribe Desktop App terminology and home-screen behavior
- OmaProton VPN at commit `87652ad`
- the plugin's pre-0.3.0 UI

## Product decisions

- Use Windscribe terms: **Best Location**, **Firewall**, **Connection**,
  **Favourites**, and **Preferred Protocol**.
- Keep Omarchy's panel, theme, and keyboard conventions.
- Do not display guessed origin, latency, DNS safety, R.O.B.E.R.T. state, or a
  synthetic privacy score.
- Keep operational copy short; explain consequences in subtitles and tooltips.
- Keep packaging implementation details out of the product UI.

## Visual direction

The 0.3.0 home screen used `TunnelInstrument.qml` (retired in 0.5.0):

- abstract device-to-exit tunnel
- animated packet direction driven by RX/TX counters
- mirrored meter for up to 60 seconds observed while the panel is open
- Firewall ring
- live protocol/port, VPN IP, allowance, and view-scoped transfer/time
- explicit verification and interference states
- motion-off fallback

## Implementation status

- [x] Remove `WorldMap.qml`, `World.js`, and `Geo.js`
- [x] Replace the inherited traffic chart
- [x] Add the Tunnel Instrument
- [x] Promote Best Location and recent destinations
- [x] Expand searchable locations and preserve datacenter nicknames
- [x] Rename Protection to Connection and Kill Switch to Firewall
- [x] Add keyboard navigation for Connection controls
- [x] Add dynamic protocol-port discovery
- [x] Add Rotate IP and update actions
- [x] Preserve Firewall state during sign-out
- [x] Rewrite manifest and README copy
- [x] Pass parser/formatter tests and static editor diagnostics
- [ ] Complete Linux/Omarchy runtime and visual validation

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

## 0.5.0 — the terminal panel

0.5.0 replaces the instrument-card look with the approved terminal design
(Claude Design project "Windscribe VPN plugin redesign", `Windscribe
Panel.dc.html`). The whole panel is typographic: dashed and dotted leader
lines, numbered exit rows, `[ on ]` bracket toggles, one full-width block
button, and a settings *view* (`s` / `esc`) instead of a tab strip.

Design-to-reality substitutions, because every value shown must be
CLI-sourced:

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

## 0.4.0 refresh

Feedback from the first on-device run, and the fixes:

- The protocol capsule sat centered on the tunnel line with a translucent
  fill, so the line struck through the label. It is now a callout: capsule
  above the line, tied to it by a hairline tick. The track also stops short
  of both nodes, so nothing relies on opaque fills to mask it.
- Quick destinations and the tab strip were both bordered `Button`s and read
  as the same control. Quick destinations are now pill chips with a leading
  mark (target for Best Location, history for recents); tabs are one
  segmented strip whose active cell is filled and carries an accent tick.
- VPN IP (with rotate) moved into the instrument header under the Firewall
  badge — the area that describes the connection. The allowance line left
  the instrument for a metered **Data allowance** row on the Connection tab.
- The instrument frame dropped its full border for corner brackets that take
  the signal colour while a tunnel is up; the readout strip gained hairline
  dividers; the live line gained a soft glow; the device node shows a
  monitor glyph.

## Validation matrix

Check these states on Omarchy:

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
