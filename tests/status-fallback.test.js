const assert = require("node:assert/strict")
const fs = require("node:fs")
const path = require("node:path")
const test = require("node:test")
const vm = require("node:vm")

const root = path.join(__dirname, "..")
const Model = {}
vm.createContext(Model)
vm.runInContext(fs.readFileSync(path.join(root, "Model.js"), "utf8"), Model)
const panel = fs.readFileSync(path.join(root, "Panel.qml"), "utf8")
const fallback = panel.slice(panel.indexOf("// ── Unreadable status"))
const visibility = fallback.match(/^\s*visible: (.+(?:\r?\n\s+&&.+)*)/m)[1]

function showsFallback(raw, options = {}) {
  const status = Model.parseStatus(raw)
  return vm.runInNewContext(visibility, {
    vpn: {
      installed: true,
      statusRead: true,
      loginState: status.loginState,
      connectionState: status.state,
      loggedIn: status.loginState === "Logged in",
      loggedOut: status.loginState === "Logged out",
      connected: status.state === "Connected",
      ...options,
    },
  })
}

test("recognized login and connection states do not claim the CLI is outdated", () => {
  for (const label of ["Login state", "Login"]) {
    for (const state of [
      "Logged in", "Logged out", "Logging in",
      "Error: Incorrect username, password, or 2FA code",
      "Unknown error", "Could not log in. Please try again.",
    ]) {
      const output = `${label}: ${state}`
      assert.equal(showsFallback(output), false, output)
    }
  }
  for (const label of ["Connect state", "Connection"]) {
    for (const state of ["Connected", "Connecting", "Disconnecting", "Disconnected", "Error: handshake failed"]) {
      const output = `${label}: ${state}`
      assert.equal(showsFallback(output), false, output)
    }
  }
})

test("unreadable status warning waits for an installed CLI and completed read", () => {
  for (const output of ["", "Unrecognized status format", "Anmeldestatus: Angemeldet"]) {
    assert.equal(showsFallback(output), true)
    assert.equal(showsFallback(output, { statusRead: false }), false)
    assert.equal(showsFallback(output, { installed: false }), false)
  }
})
