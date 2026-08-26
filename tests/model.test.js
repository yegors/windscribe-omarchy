const assert = require("node:assert/strict")
const fs = require("node:fs")
const path = require("node:path")
const test = require("node:test")
const vm = require("node:vm")

const source = fs
  .readFileSync(path.join(__dirname, "..", "Model.js"), "utf8")
  .replace(/^\s*\.pragma library\s*$/m, "")
const Model = {}
vm.createContext(Model)
vm.runInContext(source, Model, { filename: "Model.js" })

test("parseStatus reads a connected tunnel", () => {
  const status = Model.parseStatus([
    "Internet connectivity: available",
    "Login state: Logged in",
    "Firewall state: Always On",
    "*Connect state: Connected: Toronto [Network interference]",
    "Protocol: WireGuard:443",
    "VPN IP: 10.10.10.10",
    "Data usage: 512.00 MiB / 10.00 GiB",
    "Update available: 2.23.12",
  ].join("\n"))

  assert.deepEqual(
    {
      internet: status.internet,
      loginState: status.loginState,
      firewall: status.firewall,
      state: status.state,
      city: status.city,
      protocol: status.protocol,
      ip: status.ip,
      ipIsVpn: status.ipIsVpn,
      tunnelTestPending: status.tunnelTestPending,
      networkInterference: status.networkInterference,
    },
    {
      internet: "available",
      loginState: "Logged in",
      firewall: "Always On",
      state: "Connected",
      city: "Toronto",
      protocol: "WireGuard:443",
      ip: "10.10.10.10",
      ipIsVpn: true,
      tunnelTestPending: true,
      networkInterference: true,
    },
  )
})

test("parseStatus reads disconnected and error states", () => {
  const disconnected = Model.parseStatus([
    "Login state: Logged out",
    "Firewall state: Off",
    "Connect state: Disconnected",
    "Public IP: 203.0.113.5",
  ].join("\n"))
  assert.equal(disconnected.state, "Disconnected")
  assert.equal(disconnected.ip, "203.0.113.5")
  assert.equal(disconnected.ipIsVpn, false)

  const failed = Model.parseStatus("Connect state: Error: Location does not exist")
  assert.equal(failed.state, "Error")
  assert.equal(failed.stateError, "Location does not exist")
})

test("parseStatus does not mistake localized output for the English contract", () => {
  const status = Model.parseStatus([
    "Internetverbindung: verfügbar",
    "Anmeldestatus: Angemeldet",
    "Verbindungsstatus: Verbunden: Frankfurt",
  ].join("\n"))
  assert.equal(status.state, "Unknown")
  assert.equal(status.loginState, "")
})

test("parseLocations handles flags, pinned IPs, and duplicates", () => {
  const locations = Model.parseLocations([
    "Best Location - Toronto",
    "Canada - Toronto - The 6 (10 Gbps)",
    "United States - New York - Radiohall [2001:db8::1] (Pro)",
    "United States - New York - Radiohall [2001:db8::1] (Pro)",
    "France - Paris - Jardin (Disabled)",
  ].join("\n"))

  assert.equal(locations.length, 3)
  assert.equal(locations[0].tenGbps, true)
  assert.equal(locations[1].pro, true)
  assert.equal(locations[2].disabled, true)
})

test("parseDataUsage supports finite, unlimited, and localized decimals", () => {
  assert.equal(Model.parseDataUsage("512.00 MiB / 1.00 GiB").fraction, 0.5)
  assert.equal(Model.parseDataUsage("512,00 MiB / 1,00 GiB").fraction, 0.5)
  assert.equal(Model.parseDataUsage("4.00 GiB / Unlimited").unlimited, true)
})

test("parseRoute accepts only safe interface and address values", () => {
  const valid = Model.parseRoute('[{"dev":"windscribe0","prefsrc":"10.0.0.2"}]')
  assert.equal(valid.dev, "windscribe0")
  assert.equal(valid.src, "10.0.0.2")

  const invalid = Model.parseRoute('[{"dev":"vpn/../../etc","prefsrc":"not-an-ip"}]')
  assert.equal(invalid.dev, "")
  assert.equal(invalid.src, "")
})

test("normalizeProtocol accepts supported protocols and valid ports", () => {
  assert.equal(Model.normalizeProtocol("WireGuard"), "wireguard")
  assert.equal(Model.normalizeProtocol("udp:53"), "udp:53")
  assert.equal(Model.normalizeProtocol("wstunnel:65535"), "wstunnel:65535")
  assert.equal(Model.normalizeProtocol("udp:0"), "")
  assert.equal(Model.normalizeProtocol("udp:65536"), "")
  assert.equal(Model.normalizeProtocol("ikev2:500"), "")
  assert.equal(Model.normalizeProtocol("wireguard:not-a-port"), "")
})

test("location and label helpers reject unsafe input", () => {
  assert.equal(Model.isSafeLocation("Toronto"), true)
  assert.equal(Model.isSafeLocation("-n"), false)
  assert.equal(Model.isSafeLocation("Toronto; rm -rf /"), false)
  assert.equal(Model.markupSafe("<b>&"), "‹b›＆")
})
