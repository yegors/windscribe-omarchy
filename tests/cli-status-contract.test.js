const assert = require("node:assert/strict")
const fs = require("node:fs")
const path = require("node:path")
const test = require("node:test")
const vm = require("node:vm")

const root = path.join(__dirname, "..")
const Model = {}
vm.createContext(Model)
vm.runInContext(fs.readFileSync(path.join(root, "Model.js"), "utf8"), Model)

// Fixtures follow onStateResponse() and the string helpers at these tags.
// Addresses and location names are illustrative; labels and omissions are not.
// https://github.com/Windscribe/Desktop-App/blob/v2.24.13/src/windscribe-cli/backendcommander.cpp
// https://github.com/Windscribe/Desktop-App/blob/v2.25.8/src/windscribe-cli/backendcommander.cpp
// https://github.com/Windscribe/Desktop-App/blob/v2.25.8/src/windscribe-cli/strings.cpp
const connected = [
  [
    "Internet connectivity: available",
    "Login state: Logged in",
    "Firewall state: Always On",
    "Connect state: Connected: Toronto - The 6",
    "Protocol: WireGuard:443",
    "VPN IP: 203.0.113.9",
    "Data usage: 1.00 GB / 10.00 GB",
    "Update available: 2.25.8",
  ].join("\n"),
  [
    "Login:       Logged in",
    "Connection:  Connected to Toronto - The 6",
    "Protocol:    WireGuard:443",
    "IP:          203.0.113.9 (VPN)",
    "Firewall:    Always On",
    "Data usage:  1.00 GB / 10.00 GB",
    "Internet:    Available",
    "Update:      2.25.8 available",
  ].join("\n"),
]

test("released old and new CLI status formats produce equivalent connected state", () => {
  for (const raw of connected) {
    const status = Model.parseStatus(raw)
    assert.equal(status.loginState, "Logged in")
    assert.equal(status.state, "Connected")
    assert.equal(status.city, "Toronto - The 6")
    assert.equal(status.protocol, "WireGuard:443")
    assert.equal(status.ip, "203.0.113.9")
    assert.equal(status.ipIsVpn, true)
    assert.equal(status.firewall, "Always On")
    assert.equal(status.internet, "available")
    assert.equal(status.updateAvailable, "2.25.8")
    assert.equal(Model.parseDataUsage(status.dataUsage).fraction, 0.1)
  }
})

test("2.25 omits unverified IPs, transition protocols, and absent updates", () => {
  const cases = [
    ["Connecting to Toronto - The 6", "Connecting", false, false],
    ["Disconnecting", "Disconnecting", false, false],
    ["Connected to Toronto - The 6 (checking the connection)", "Connected", true, false],
    ["Connected to Toronto - The 6 (network interference detected)", "Connected", false, true],
  ]
  for (const [connection, state, pending, interference] of cases) {
    const lines = ["Login: Logged in", `Connection: ${connection}`]
    if (state === "Connected") lines.push("Protocol: WireGuard:443")
    lines.push("Firewall: On", "Data usage: 0 bytes / Unlimited", "Internet: Unavailable")
    const status = Model.parseStatus(lines.join("\n"))
    assert.equal(status.state, state)
    assert.equal(status.ip, "")
    assert.equal(status.ipIsVpn, false)
    assert.equal(status.protocol, state === "Connected" ? "WireGuard:443" : "")
    assert.equal(status.updateAvailable, "")
    assert.equal(status.tunnelTestPending, pending)
    assert.equal(status.networkInterference, interference)
    assert.equal(status.internet, "unavailable")
    assert.equal(Model.parseDataUsage(status.dataUsage).unlimited, true)
  }
  const loggedOut = Model.parseStatus("Login: Logged out\nIP: 198.51.100.8 (public)\nFirewall: Off\nInternet: Available")
  assert.equal(loggedOut.loginState, "Logged out")
  assert.equal(loggedOut.state, "Unknown") // The CLI intentionally omits Connection.
  assert.equal(loggedOut.ip, "198.51.100.8")
  assert.equal(loggedOut.ipIsVpn, false)
})

const keyLimit = 'Disconnected due to reaching WireGuard key limit. Use "windscribe-cli keylimit delete" if you want to delete the oldest key instead, and try again.'

test("released key-limit disconnects retain both state and actionable reason", () => {
  for (const [label, reason] of [
    ["Connect state", keyLimit.replace(". Use", ".  Use")],
    ["Connection", keyLimit],
  ]) {
    const status = Model.parseStatus(`${label}: ${reason}`)
    assert.equal(status.state, "Disconnected")
    assert.equal(status.stateError, reason)
    assert.equal(status.city, "")
  }
})

function loadQmlFunctions(filename, names, context) {
  const source = fs.readFileSync(path.join(root, filename), "utf8")
  vm.createContext(context)
  for (const name of names) {
    const match = source.match(new RegExp(`^  function ${name}\\([^)]*\\) \\{[\\s\\S]*?^  \\}`, "m"))
    assert.ok(match, `${name} is present`)
    vm.runInContext(match[0], context)
  }
}

test("released LocationID city-plus-nickname identifies only the matching exit", () => {
  // LocationID::createApiLocationId stores city + " - " + nick in city().
  // https://github.com/Windscribe/Desktop-App/blob/v2.25.8/src/client/client-common/types/locationid.cpp
  const locations = [
    { city: "Toronto", nickname: "Comfort Zone" },
    { city: "Toronto", nickname: "The 6" },
    { city: "New York", nickname: "Radiohall" },
  ]
  const context = { vpn: { locations, city: "" }, root: {} }
  loadQmlFunctions("Panel.qml", ["locationByTarget", "entryCurrent"], context)
  for (const raw of connected) {
    context.vpn.city = Model.parseStatus(raw).city
    context.root.currentLocation = context.locationByTarget(context.vpn.city)
    assert.deepEqual(locations.map((entry) => context.entryCurrent(entry)), [false, true, false])
  }
  context.vpn.city = "Toronto"
  context.root.currentLocation = context.locationByTarget(context.vpn.city)
  assert.deepEqual(locations.map((entry) => context.entryCurrent(entry)), [true, true, false])
})

test("status application clears an omitted IP and surfaces a key-limit disconnect", () => {
  let resets = 0
  let errors = 0
  let notifications = 0
  const context = {
    Model,
    connectionState: "Connected",
    ipAddress: "203.0.113.9",
    ipIsVpn: true,
    lastError: "",
    linkDevice: "windscribe0",
    _statusInitialized: true,
    _expectDown: false,
    actionProcess: { running: false },
    desiredState: -1,
    panelOpen: false,
    firewallOn: true,
    errorClearTimer: { restart() { errors++ } },
    trafficReset() { resets++ },
    notify() { notifications++ },
    protocolPreference() { return "" },
  }
  loadQmlFunctions("VpnState.qml", ["applyStatus"], context)
  context.applyStatus(`Login: Logged in\nConnection: ${keyLimit}\nFirewall: On\nInternet: Available`)
  assert.equal(context.connectionState, "Disconnected")
  assert.equal(context.ipAddress, "")
  assert.equal(context.ipIsVpn, false)
  assert.equal(context.lastError, keyLimit)
  assert.equal(resets, 1)
  assert.equal(errors, 1)
  assert.equal(notifications, 1)
})
