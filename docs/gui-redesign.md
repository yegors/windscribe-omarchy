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

The home screen uses `TunnelInstrument.qml`:

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
