pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import "Model.js" as Model
import "Geo.js" as Geo

// Windscribe state for the bar widget, driven entirely by windscribe-cli.
//
// The CLI allows one instance at a time, so every call is serialized: reads
// defer politely, actions kill an in-flight read and take the slot. Connect
// and disconnect run blocking — the exit code and output are the truth about
// what happened — while `pendingLabel` keeps the UI honest in the meantime.
//
// Traffic comes from the kernel's own counters for the tunnel interface,
// found via `ip route get` so the device name never needs to be known.
Item {
  id: root

  // Injected by BarWidget from the shell's per-widget settings (shell.json).
  property var settings: ({})
  // Set by the panel; drives faster polling and traffic sampling.
  property bool panelOpen: false

  property bool installed: false
  property bool installing: false
  // The CLI-only build ships a systemd user unit the GUI build does not.
  // Only the CLI-only build prints `windscribe-cli locations` to stdout —
  // the GUI build opens the location list in the app window instead.
  property bool cliOnlyBuild: false
  property bool buildProbed: false

  property string internet: ""
  property string loginState: ""
  property string firewall: ""
  property string connectionState: "Unknown"
  property string city: ""
  property string protocol: ""
  property string ipAddress: ""
  property bool ipIsVpn: false
  property string dataUsage: ""
  property string updateAvailable: ""
  property bool tunnelTestPending: false
  property bool networkInterference: false

  property var locations: []
  property bool locationsLoaded: false
  property bool locationsUnavailable: false

  property string lastError: ""
  property string actionStatus: ""
  property string pendingLabel: ""
  property int desiredState: -1

  // Tunnel throughput, from /sys/class/net/<dev>/statistics. Sampled once a
  // second, only while the panel is open and the tunnel is up.
  property string linkDevice: ""
  property var rxHistory: []
  property var txHistory: []
  property real rxRate: 0
  property real txRate: 0
  property real sessionRx: 0
  property real sessionTx: 0
  property int uptimeSec: 0
  property real _lastRx: -1
  property real _lastTx: -1
  property real _lastSampleMs: 0
  property real _connectedSinceMs: 0
  readonly property int trafficSamples: 60

  // Last three places connected to, persisted across shell restarts.
  // Location labels only — nothing secret.
  property var recents: []
  readonly property string stateDir: (Quickshell.env("XDG_STATE_HOME") || (Quickshell.env("HOME") + "/.local/state")) + "/omarchy-windscribe"
  readonly property string statePath: stateDir + "/state.json"

  property string _statusOutput: ""
  property string _statusError: ""
  property string _locationsOutput: ""
  property string _actionOutput: ""
  property string _actionError: ""
  property bool _statusAborted: false
  property bool _locationsAborted: false
  property bool _actionAborted: false
  property bool _statusInitialized: false
  property bool _expectDown: false
  property string _actionKind: ""
  property var _target: null

  readonly property bool loggedIn: loginState === "Logged in"
  readonly property bool loggedOut: loginState === "Logged out"
  readonly property bool connected: connectionState === "Connected"
  readonly property bool transitional: connectionState === "Connecting"
    || connectionState === "Disconnecting"
  readonly property bool backendActive: connectionState === "Connected"
    || connectionState === "Connecting"
  readonly property bool active: desiredState === -1
    ? backendActive
    : desiredState === 1
  readonly property bool busy: actionProcess.running || transitional
  readonly property bool loadingLocations: locationsProcess.running
  readonly property bool firewallLocked: firewall === "Always On"
  readonly property bool firewallOn: firewall === "On" || firewallLocked
  readonly property int refreshIntervalSec: intSetting("refreshIntervalSec", 5, 2, 60)
  readonly property bool notificationsOn: String(setting("notifications", "on")) !== "off"
  readonly property var usage: Model.parseDataUsage(dataUsage)
  // {city, lat, lon} for the connected city, when its coordinates are known.
  readonly property var currentPlace: {
    if (city === "") return null
    var hit = Geo.locate(city)
    return hit ? { city: city, lat: hit[0], lon: hit[1] } : null
  }

  readonly property string statusText: {
    if (!installed) return installing ? "Installing Windscribe…" : "Windscribe not installed"
    if (actionProcess.running && pendingLabel !== "") return pendingLabel
    if (internet === "unavailable") return "No internet"
    if (loginState === "Logging in") return "Logging in…"
    if (loggedOut) return "Not signed in"
    if (loginState.indexOf("Error") === 0) return "Login error"
    if (desiredState === 1 && !connected) return "Connecting…"
    if (desiredState === 0 && connectionState !== "Disconnected") return "Disconnecting…"
    if (connectionState === "Connected") {
      if (networkInterference) return "Connected · network interference"
      if (tunnelTestPending) return "Connected · verifying…"
      return "Connected"
    }
    if (connectionState === "Connecting") return "Connecting…"
    if (connectionState === "Disconnecting") return "Disconnecting…"
    if (connectionState === "Disconnected") return "Disconnected"
    if (connectionState === "Error") return "Connection error"
    return "Checking…"
  }

  function markupSafeText(raw) {
    return Model.markupSafe(raw)
  }

  function isSafeLocation(value) {
    return Model.isSafeLocation(value)
  }

  function setting(name, fallback) {
    var value = settings ? settings[name] : undefined
    return value === undefined || value === null ? fallback : value
  }

  function intSetting(name, fallback, min, max) {
    var n = parseInt(String(setting(name, fallback)), 10)
    if (!isFinite(n)) n = fallback
    return Math.max(min, Math.min(max, n))
  }

  function protocolPreference() {
    return Model.normalizeProtocol(setting("preferredProtocol", ""))
  }

  function cliFree() {
    return !statusProcess.running && !locationsProcess.running && !actionProcess.running
  }

  function refresh() {
    if (!installed) {
      if (!whichProcess.running) {
        whichProcess.command = ["which", "windscribe-cli"]
        whichProcess.running = true
      }
      return
    }
    if (!cliFree()) return
    _statusAborted = false
    _statusOutput = ""
    _statusError = ""
    statusProcess.command = ["windscribe-cli", "status"]
    statusProcess.running = true
    statusWatchdog.restart()
  }

  function refreshLocations() {
    if (!installed || !cliOnlyBuild || locationsProcess.running) return
    // Only one windscribe-cli may run at a time; defer instead of dropping
    // when another call is in flight.
    if (!cliFree()) {
      locationsRetry.restart()
      return
    }
    _locationsAborted = false
    _locationsOutput = ""
    locationsProcess.command = ["windscribe-cli", "locations"]
    locationsProcess.running = true
    locationsWatchdog.restart()
  }

  // On GUI builds the location list only exists in the app window; this pops
  // it open there. Routed through the action process so it serializes with
  // other CLI calls and surfaces failures.
  function openLocationsInApp() {
    if (!installed || cliOnlyBuild || actionProcess.running) return
    runAction(["windscribe-cli", "locations"], "locations", "")
  }

  function applyStatus(raw) {
    var s = Model.parseStatus(raw)
    var wasConnected = connectionState === "Connected"
    internet = s.internet
    loginState = s.loginState
    firewall = s.firewall
    connectionState = s.state
    city = s.city
    protocol = s.protocol
    ipAddress = s.ip
    ipIsVpn = s.ipIsVpn
    dataUsage = s.dataUsage
    updateAvailable = s.updateAvailable
    tunnelTestPending = s.tunnelTestPending
    networkInterference = s.networkInterference
    if (s.state === "Error" && s.stateError !== "" && lastError === "") {
      lastError = Model.elide(s.stateError)
      errorClearTimer.restart()
    }

    if (s.state === "Connected") {
      if (!wasConnected) {
        trafficReset()
        _connectedSinceMs = Date.now()
      }
      if (linkDevice === "") routeProbe()
    } else {
      linkDevice = ""
      // A tunnel we didn't ask to close is the one thing a person must hear
      // about: the icon dimming is not a signal most people read.
      if (_statusInitialized && wasConnected && s.state === "Disconnected") {
        if (!_expectDown && !actionProcess.running) {
          notify("Windscribe disconnected",
                 firewallOn
                   ? "The kill switch is blocking all traffic until you reconnect."
                   : "Traffic is no longer going through the VPN.",
                 "critical")
        }
        _expectDown = false
      }
    }
    _statusInitialized = true

    if (desiredState === 1 && s.state === "Connected") {
      desiredState = -1
      desiredTimeout.stop()
    } else if (desiredState === 0 && s.state === "Disconnected") {
      desiredState = -1
      desiredTimeout.stop()
    }
  }

  function toggle() {
    if (!installed || actionProcess.running) return
    if (active) disconnect()
    else connect()
  }

  function connectCommand(target) {
    var args = ["windscribe-cli", "connect"]
    if (target) args.push(target)
    var proto = protocolPreference()
    if (proto !== "") args.push(proto)
    return args
  }

  function connect() {
    if (!installed || actionProcess.running) return
    desiredState = 1
    _expectDown = false
    _target = null
    runAction(connectCommand(null), "connect", "Connecting…")
  }

  function connectBest() {
    if (!installed || actionProcess.running) return
    desiredState = 1
    _expectDown = false
    _target = null
    runAction(connectCommand("best"), "connect", "Connecting to fastest…")
  }

  function connectTo(location) {
    if (!installed || actionProcess.running) return
    var target = String(location || "").trim()
    if (!Model.isSafeLocation(target)) {
      lastError = "Invalid Windscribe location"
      errorClearTimer.restart()
      return
    }
    desiredState = 1
    _expectDown = false
    _target = { key: "loc:" + target.toLowerCase(), city: target }
    runAction(connectCommand(target), "connect", "Connecting to " + Model.markupSafe(target) + "…")
  }

  function connectRecent(index) {
    var r = recents[index]
    if (!r || !r.city) return
    connectTo(r.city)
  }

  function disconnect() {
    if (!installed || actionProcess.running) return
    desiredState = 0
    _expectDown = true
    runAction(["windscribe-cli", "disconnect"], "disconnect", "Disconnecting…")
  }

  function setFirewall(on) {
    if (!installed || actionProcess.running || firewallLocked) return
    runAction(["windscribe-cli", "firewall", on ? "on" : "off"], "firewall", "")
  }

  // New IP on the same server (needs a plan that allows it; errors surface).
  function rotateIp() {
    if (!installed || actionProcess.running || !connected) return
    runAction(["windscribe-cli", "ip", "rotate"], "rotate", "Rotating IP…")
  }

  function signOut() {
    if (!installed || actionProcess.running) return
    desiredState = 0
    _expectDown = true
    runAction(["windscribe-cli", "logout"], "logout", "Signing out…")
  }

  // Sign-in is interactive (username, password, 2FA, on the CLI-only build a
  // captcha), so it happens in Omarchy's floating terminal. The command is a
  // fixed literal — nothing user-typed crosses a shell boundary. While the
  // terminal owns the CLI's single instance, our polls skip politely.
  function signIn() {
    if (!installed) return
    Quickshell.execDetached(["omarchy-launch-floating-terminal-with-presentation", "windscribe-cli login"])
    signInWatch.restart()
  }

  // Omarchy's own installer flow: a floating terminal owns the password
  // prompt, so the shell process never touches privileges. windscribe-v2-bin
  // repackages the official release from GitHub.
  function installCli() {
    if (installed || installing) return
    installing = true
    lastError = ""
    Quickshell.execDetached(["omarchy-install-app", "Windscribe", "windscribe-v2-bin"])
    installWatch.restart()
  }

  function notify(summary, body, urgency) {
    if (!notificationsOn) return
    Quickshell.execDetached(["notify-send", "-a", "Windscribe", "-i", "network-vpn",
                             "-u", urgency || "normal", summary, body || ""])
  }

  function recordRecent(target) {
    if (!target || !target.key) return
    var next = [target]
    for (var i = 0; i < recents.length && next.length < 3; i++) {
      if (recents[i] && recents[i].key !== target.key) next.push(recents[i])
    }
    recents = next
    saveState()
  }

  function applyState(text) {
    try {
      var s = JSON.parse(String(text || "{}"))
      recents = Array.isArray(s.recents) ? s.recents.slice(0, 3) : []
    } catch (e) {
      recents = []
    }
  }

  function saveState() {
    stateFile.setText(JSON.stringify({ recents: recents }))
  }

  function trafficReset() {
    rxHistory = []
    txHistory = []
    rxRate = 0
    txRate = 0
    sessionRx = 0
    sessionTx = 0
    uptimeSec = 0
    _lastRx = -1
    _lastTx = -1
    _lastSampleMs = 0
  }

  function routeProbe() {
    if (routeProcess.running) return
    routeProcess.command = ["ip", "-j", "route", "get", "1.1.1.1"]
    routeProcess.running = true
  }

  // sysfs files report a size of 0, so they're read with `cat` — about a
  // millisecond once a second, and not a windscribe-cli call, so it never
  // contends for the CLI's single instance.
  function trafficSample() {
    if (trafficProcess.running || linkDevice === "") return
    var base = "/sys/class/net/" + linkDevice + "/statistics/"
    trafficProcess.command = ["cat", base + "rx_bytes", base + "tx_bytes"]
    trafficProcess.running = true
  }

  function trafficApply(text) {
    var parts = String(text || "").trim().split(/\s+/)
    var rx = parseFloat(parts[0])
    var tx = parseFloat(parts[1])
    if (!isFinite(rx) || !isFinite(tx)) return
    var now = Date.now()
    if (_lastRx >= 0 && _lastSampleMs > 0) {
      var dt = Math.max(0.25, (now - _lastSampleMs) / 1000)
      var drx = Math.max(0, rx - _lastRx)
      var dtx = Math.max(0, tx - _lastTx)
      rxRate = drx / dt
      txRate = dtx / dt
      sessionRx += drx
      sessionTx += dtx
      var h = rxHistory.slice(); h.push(rxRate); if (h.length > trafficSamples) h.shift(); rxHistory = h
      var g = txHistory.slice(); g.push(txRate); if (g.length > trafficSamples) g.shift(); txHistory = g
    }
    _lastRx = rx
    _lastTx = tx
    _lastSampleMs = now
    uptimeSec = _connectedSinceMs > 0 ? Math.floor((now - _connectedSinceMs) / 1000) : 0
  }

  // windscribe-cli only allows one instance at a time, so an action takes
  // priority over any read that happens to be in flight.
  function runAction(command, kind, label) {
    if (statusProcess.running) {
      _statusAborted = true
      statusProcess.running = false
    }
    if (locationsProcess.running) {
      _locationsAborted = true
      locationsProcess.running = false
      locationsRetry.restart()
    }
    lastError = ""
    actionStatus = ""
    errorClearTimer.stop()
    _actionAborted = false
    _actionKind = kind || ""
    pendingLabel = label || ""
    _actionOutput = ""
    _actionError = ""
    actionProcess.command = command
    actionProcess.running = true
    actionWatchdog.restart()
    // desiredTimeout is armed when the action EXITS, not here — a blocking
    // connect may legitimately outlive it, and status can't poll meanwhile.
    desiredTimeout.stop()
  }

  Component.onCompleted: Quickshell.execDetached(["mkdir", "-p", stateDir])

  Timer {
    id: refreshTimer
    interval: (root.panelOpen ? 3 : root.refreshIntervalSec) * 1000
    repeat: true
    running: true
    triggeredOnStart: true
    onTriggered: root.refresh()
  }

  Timer {
    id: trafficTimer
    interval: 1000
    repeat: true
    running: root.panelOpen && root.connected && root.linkDevice !== ""
    triggeredOnStart: true
    onTriggered: root.trafficSample()
  }

  Timer {
    id: settleTimer
    property int ticks: 0
    interval: 1000
    repeat: true
    running: false
    onTriggered: {
      ticks += 1
      root.refresh()
      if (ticks >= 6) {
        ticks = 0
        running = false
      }
    }
  }

  Timer {
    id: errorClearTimer
    interval: 8000
    repeat: false
    onTriggered: root.lastError = ""
  }

  Timer {
    id: actionStatusTimer
    interval: 6000
    repeat: false
    onTriggered: root.actionStatus = ""
  }

  Timer {
    id: locationsRetry
    interval: 600
    repeat: false
    onTriggered: root.refreshLocations()
  }

  Timer {
    id: statusWatchdog
    interval: 15000
    repeat: false
    onTriggered: {
      if (!statusProcess.running) return
      root._statusAborted = true
      statusProcess.running = false
      root.connectionState = "Unknown"
    }
  }

  Timer {
    id: locationsWatchdog
    interval: 20000
    repeat: false
    onTriggered: {
      if (!locationsProcess.running) return
      root._locationsAborted = true
      locationsProcess.running = false
    }
  }

  // Blocking connects legitimately take a while; this is a backstop, not a
  // deadline.
  Timer {
    id: actionWatchdog
    interval: 90000
    repeat: false
    onTriggered: {
      if (!actionProcess.running) return
      root._actionAborted = true
      actionProcess.running = false
      root.desiredState = -1
      root.pendingLabel = ""
      root.lastError = "Windscribe did not finish the requested action"
      errorClearTimer.restart()
      root.refresh()
    }
  }

  Timer {
    id: desiredTimeout
    interval: 20000
    repeat: false
    onTriggered: {
      root.desiredState = -1
      root.refresh()
    }
  }

  // Sign-in happens out of process in a terminal; poll for a while so the
  // panel flips to the signed-in view on its own.
  Timer {
    id: signInWatch
    interval: 3000
    repeat: true
    property int ticks: 0
    onRunningChanged: if (running) ticks = 0
    onTriggered: {
      ticks += 1
      root.refresh()
      if (root.loggedIn || ticks > 60) stop()
    }
  }

  // Same idea for the package install: up to five minutes for the AUR build.
  Timer {
    id: installWatch
    interval: 3000
    repeat: true
    property int ticks: 0
    onRunningChanged: if (running) ticks = 0
    onTriggered: {
      ticks += 1
      root.refresh()
      if (root.installed || ticks > 100) {
        stop()
        root.installing = false
      }
    }
  }

  FileView {
    id: stateFile
    path: root.statePath
    printErrors: false
    onLoaded: root.applyState(text())
    onLoadFailed: root.applyState("{}")
  }

  Process {
    id: whichProcess
    running: false
    command: []
    onExited: function(exitCode) {
      var was = root.installed
      root.installed = exitCode === 0
      if (root.installed) {
        if (!was) {
          root.installing = false
          root.lastError = ""
        }
        if (!root.buildProbed && !buildProbeProcess.running) {
          buildProbeProcess.command = ["test", "-f", "/usr/lib/systemd/user/windscribe.service"]
          buildProbeProcess.running = true
        } else {
          root.refresh()
        }
      } else {
        root.connectionState = "Unknown"
        root.loginState = ""
        root.city = ""
        root.ipAddress = ""
      }
    }
  }

  Process {
    id: buildProbeProcess
    running: false
    command: []
    onExited: function(exitCode) {
      root.cliOnlyBuild = exitCode === 0
      root.buildProbed = true
      root.locationsUnavailable = !root.cliOnlyBuild
      // Locations first; the status refresh chains after it exits.
      if (root.cliOnlyBuild) root.refreshLocations()
      root.refresh()
    }
  }

  Process {
    id: routeProcess
    running: false
    command: []
    stdout: StdioCollector { id: routeStdout; waitForEnd: true }
    onExited: function(exitCode) {
      if (exitCode !== 0 || !root.connected) return
      var route = Model.parseRoute(String(routeStdout.text || ""))
      root.linkDevice = route.dev
    }
  }

  Process {
    id: trafficProcess
    running: false
    command: []
    stdout: StdioCollector { id: trafficStdout; waitForEnd: true }
    onExited: function(exitCode) {
      if (exitCode === 0) root.trafficApply(String(trafficStdout.text || ""))
    }
  }

  Process {
    id: statusProcess
    running: false
    command: []
    stdout: StdioCollector {
      id: statusStdout
      waitForEnd: true
      onStreamFinished: root._statusOutput = text
    }
    stderr: StdioCollector {
      id: statusStderr
      waitForEnd: true
      onStreamFinished: root._statusError = text
    }
    onExited: function(exitCode) {
      statusWatchdog.stop()
      if (root._statusAborted) {
        root._statusAborted = false
        return
      }
      var stdout = String(root._statusOutput || statusStdout.text || "")
      var stderr = String(root._statusError || statusStderr.text || "")
      if (exitCode === 0) {
        root.applyStatus(stdout)
      } else {
        var output = (stdout + "\n" + stderr).trim()
        // Transient collision with a CLI run outside the widget — the sign-in
        // terminal, or the user's own shell.
        if (/already running/i.test(output)) return
        root.connectionState = "Unknown"
        if (!actionProcess.running && output !== "" && root.lastError === "") {
          root.lastError = Model.elide(output)
          errorClearTimer.restart()
        }
      }
    }
  }

  Process {
    id: locationsProcess
    running: false
    command: []
    stdout: StdioCollector {
      id: locationsStdout
      waitForEnd: true
      onStreamFinished: root._locationsOutput = text
    }
    onExited: function(exitCode) {
      locationsWatchdog.stop()
      if (root._locationsAborted) {
        root._locationsAborted = false
        return
      }
      if (exitCode === 0) {
        var parsed = Model.parseLocations(root._locationsOutput || locationsStdout.text || "")
        if (parsed.length > 0) {
          root.locations = parsed
          root.locationsLoaded = true
          root.locationsUnavailable = false
        } else {
          root.locationsUnavailable = true
        }
      }
      root.refresh()
    }
  }

  Process {
    id: actionProcess
    running: false
    command: []
    stdout: StdioCollector {
      id: actionStdout
      waitForEnd: true
      onStreamFinished: root._actionOutput = text
    }
    stderr: StdioCollector {
      id: actionStderr
      waitForEnd: true
      onStreamFinished: root._actionError = text
    }
    onExited: function(exitCode) {
      actionWatchdog.stop()
      if (root._actionAborted) {
        root._actionAborted = false
        return
      }
      var stdout = String(root._actionOutput || actionStdout.text || "")
      var stderr = String(root._actionError || actionStderr.text || "")
      var kind = root._actionKind
      var target = root._target
      root._actionKind = ""
      root._target = null
      root.pendingLabel = ""
      if (exitCode !== 0) {
        root.desiredState = -1
        root._expectDown = false
        desiredTimeout.stop()
        // The CLI reports errors on stdout, not stderr.
        root.lastError = Model.elide(stdout || stderr || "Windscribe command failed")
        errorClearTimer.restart()
      } else {
        root.lastError = ""
        if (kind === "connect") {
          var lines = stdout.split(/\r?\n/).filter(function(l) { return l.trim() !== "" })
          var line = Model.elide(lines.length > 0 ? lines[lines.length - 1] : "Connected")
          root.actionStatus = line
          actionStatusTimer.restart()
          root.recordRecent(target)
          root.notify("Windscribe connected", line, "normal")
        }
        // Post-exit settle guard: drop the optimistic state if status never
        // confirms it within a poll cycle or two.
        if (root.desiredState !== -1) desiredTimeout.restart()
      }
      settleTimer.ticks = 0
      settleTimer.restart()
    }
  }
}
