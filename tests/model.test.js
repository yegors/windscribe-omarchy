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

test("protocol helpers use Windscribe labels and split ports", () => {
  assert.equal(Model.protocolLabel(""), "Automatic")
  assert.equal(Model.protocolLabel("wireguard:443"), "WireGuard:443")
  assert.equal(Model.protocolLabel("udp"), "UDP")
  assert.equal(Model.protocolBase("stealth:8443"), "stealth")
  assert.equal(Model.protocolPort("stealth:8443"), "8443")
  assert.equal(Model.protocolPort("wstunnel"), "")
})

test("terminal shorthand helpers compress protocols and slugs", () => {
  assert.equal(Model.protocolShortName("wireguard"), "wg")
  assert.equal(Model.protocolShortName("wstunnel:443"), "ws")
  assert.equal(Model.protocolShortName(""), "")
  assert.equal(Model.protocolStatusShort("WireGuard:443"), "wg/443")
  assert.equal(Model.protocolStatusShort("UDP"), "udp")
  assert.equal(Model.protocolStatusShort("Stealth:8443"), "stealth/8443")
  assert.equal(Model.protocolStatusShort(""), "")
  assert.equal(Model.slugify("Washington DC"), "washington-dc")
  assert.equal(Model.slugify("  US East "), "us-east")
  assert.equal(Model.slugify("<x>"), "‹x›")
})

test("parsePorts accepts Windscribe's list and removes invalid duplicates", () => {
  assert.deepEqual(
    Array.from(Model.parsePorts("443, 80, 53, 443, 0, 65536")),
    ["443", "80", "53"],
  )
})

test("traffic formatters stay compact", () => {
  assert.equal(Model.formatRate(0), "0 B/s")
  assert.equal(Model.formatRate(1536), "1.50 KB/s")
  assert.equal(Model.formatBytes(10 * 1024 * 1024), "10.0 MB")
  assert.equal(Model.formatDuration(3725), "1h 02m")
})

test("location and label helpers reject unsafe input", () => {
  assert.equal(Model.isSafeLocation("Toronto"), true)
  assert.equal(Model.isSafeLocation("-n"), false)
  assert.equal(Model.isSafeLocation("Toronto; rm -rf /"), false)
  assert.equal(Model.markupSafe("<b>&"), "‹b›＆")
  assert.equal(Model.shellQuote("a'b"), "'a'\"'\"'b'")
})

test("boundedCommand preserves argv and applies a hard maximum", () => {
  assert.deepEqual(
    Array.from(Model.boundedCommand(
      "file:///plugin/scripts/bounded-output",
      16384,
      ["windscribe-cli", "connect", "New York; still one argument"],
    )),
    [
      "file:///plugin/scripts/bounded-output",
      "16384",
      "windscribe-cli",
      "connect",
      "New York; still one argument",
    ],
  )
  assert.equal(Model.boundedCommand("/limiter", 2000000, ["true"])[1], "1048576")
  assert.equal(Model.outputLimitExitCode(), 125)
})

test("bounded-output has producer-side caps and signal forwarding", () => {
  const limiter = path.join(__dirname, "..", "scripts", "bounded-output")
  fs.accessSync(limiter, fs.constants.X_OK)
  const source = fs.readFileSync(limiter, "utf8")
  assert.match(source, /count=1 iflag=fullblock/)
  assert.match(source, /stdout\.overflow/)
  assert.match(source, /stderr\.overflow/)
  assert.match(source, /exit "\$overflow_exit"/)
  assert.match(source, /forward_signal TERM 143/)
  assert.match(source, /setpriv --pdeathsig TERM/)
})

test("bounded-output preserves status and fails closed on overflow", {
  skip: process.platform !== "linux",
}, () => {
  const { spawnSync } = require("node:child_process")
  const limiter = path.join(__dirname, "..", "scripts", "bounded-output")

  const normal = spawnSync(
    limiter,
    ["64", "bash", "-c", "printf out; printf err >&2; exit 7"],
    { encoding: "utf8" },
  )
  assert.equal(normal.status, 7)
  assert.equal(normal.stdout, "out")
  assert.equal(normal.stderr, "err")

  const payload = "x".repeat(65)
  const stdoutOverflow = spawnSync(
    limiter,
    ["64", "printf", "%s", payload],
    { encoding: "utf8" },
  )
  assert.equal(stdoutOverflow.status, Model.outputLimitExitCode())
  assert.equal(Buffer.byteLength(stdoutOverflow.stdout), 64)

  const stderrOverflow = spawnSync(
    limiter,
    ["64", "bash", "-c", "printf '%s' \"$1\" >&2", "bounded-output", payload],
    { encoding: "utf8" },
  )
  assert.equal(stderrOverflow.status, Model.outputLimitExitCode())
  assert.equal(Buffer.byteLength(stderrOverflow.stderr), 64)
})

// Symlink creation is a privilege on some platforms (Windows without
// Developer Mode); probe instead of assuming.
function canSymlink() {
  const os = require("node:os")
  const probeDir = fs.mkdtempSync(path.join(os.tmpdir(), "ws-symlink-"))
  try {
    fs.symlinkSync(probeDir, path.join(probeDir, "probe"))
    return true
  } catch {
    return false
  } finally {
    fs.rmSync(probeDir, { recursive: true, force: true })
  }
}

test("stateDirPrepareCommand hardens a real directory and refuses a symlink", () => {
  const os = require("node:os")
  const { execFileSync } = require("node:child_process")
  const cmd = Model.stateDirPrepareCommand("/tmp/omarchy-windscribe")
  assert.match(cmd, /\[ -L "\$dir" \]/)
  assert.match(cmd, /chmod 700 "\$dir"/)
  assert.match(cmd, /mkdir -m 700 "\$dir"/)
  assert.equal(cmd.includes("mkdir -p \"$dir\""), false)

  // The execution phase needs POSIX modes and a real bash; the static
  // command checks above already ran everywhere.
  if (process.platform === "win32") return

  const tmp = fs.mkdtempSync(path.join(os.tmpdir(), "ws-state-"))
  try {
    const existing = path.join(tmp, "omarchy-windscribe")
    fs.mkdirSync(existing, { mode: 0o755 })
    const recents = { recents: [{ key: "loc:toronto", city: "Toronto" }] }
    fs.writeFileSync(path.join(existing, "state.json"), JSON.stringify(recents))
    execFileSync("bash", ["-c", Model.stateDirPrepareCommand(existing)])
    const st = fs.lstatSync(existing)
    assert.equal(st.isSymbolicLink(), false)
    assert.equal(st.isDirectory(), true)
    assert.equal(st.mode & 0o777, 0o700)
    assert.deepEqual(JSON.parse(fs.readFileSync(path.join(existing, "state.json"), "utf8")), recents)

    const fresh = path.join(tmp, "nested", "omarchy-windscribe")
    execFileSync("bash", ["-c", Model.stateDirPrepareCommand(fresh)])
    const created = fs.lstatSync(fresh)
    assert.equal(created.isSymbolicLink(), false)
    assert.equal(created.mode & 0o777, 0o700)

    if (canSymlink()) {
      const linked = path.join(tmp, "linked")
      fs.symlinkSync(existing, linked)
      assert.throws(
        () => execFileSync("bash", ["-c", Model.stateDirPrepareCommand(linked)], { stdio: "pipe" }),
      )
      assert.equal(fs.lstatSync(linked).isSymbolicLink(), true)
      assert.deepEqual(JSON.parse(fs.readFileSync(path.join(existing, "state.json"), "utf8")), recents)
    }
  } finally {
    fs.rmSync(tmp, { recursive: true, force: true })
  }
})

test("terminalCommandWithResult writes the marker without following a symlink", () => {
  const os = require("node:os")
  const { execFileSync } = require("node:child_process")
  const marker = "/tmp/omarchy-windscribe/signin.result"
  const cmd = Model.terminalCommandWithResult("windscribe-cli login", marker)
  assert.equal(cmd.includes("rm -f \"$result\""), false)
  assert.match(cmd, /mktemp "\$\{result\}\.XXXXXX"/)
  assert.match(cmd, /mv -f -T "\$tmp" "\$result"/)
  assert.match(cmd, /windscribe-cli login/)

  // The execution phase needs POSIX paths inside bash; the static command
  // checks above already ran everywhere.
  if (process.platform === "win32") return

  const tmp = fs.mkdtempSync(path.join(os.tmpdir(), "ws-marker-"))
  try {
    execFileSync("mv", ["-T", "--version"], { stdio: "ignore" })
  } catch {
    fs.rmSync(tmp, { recursive: true, force: true })
    return
  }
  if (!canSymlink()) {
    fs.rmSync(tmp, { recursive: true, force: true })
    return
  }

  try {
    const result = path.join(tmp, "signin.result")
    const outside = path.join(tmp, "outside")
    fs.writeFileSync(outside, "untouched")
    fs.symlinkSync(outside, result)
    execFileSync("bash", ["-c", Model.terminalCommandWithResult("true", result)])
    assert.equal(fs.lstatSync(result).isSymbolicLink(), false)
    assert.equal(fs.readFileSync(result, "utf8"), "0")
    assert.equal(fs.readFileSync(outside, "utf8"), "untouched")
  } finally {
    fs.rmSync(tmp, { recursive: true, force: true })
  }
})
