pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import "Model.js" as Model

// Windscribe state for the bar widget, driven entirely by windscribe-cli.
//
// The CLI allows one instance at a time, so every call is serialized. Actions
// ask in-flight readers to stop and wait for their exit before taking the
// slot. Connect and disconnect stay blocking — exit status remains the truth
// while `pendingLabel` keeps the UI responsive.
//
// Traffic comes from the kernel's own counters for the tunnel interface,
// found via `ip route get` so the device name never needs to be known.
Item {
  id: root

  // Injected by BarWidget from the shell's per-widget settings (shell.json).
  property var settings: ({})
  // Aggregated across per-monitor panel instances; drives faster polling and
  // traffic sampling while at least one panel is open.
  property bool panelOpen: false
  property int _nextPanelOwnerId: 0
  property var _openPanelOwners: ({})

  property bool installed: false
  property bool installing: false
  property bool updating: false
  property bool signingIn: false
  // Official Arch CLI is x86_64 only. Anything else (aarch64, armv7, i686)
  // has no package to download — we refuse to try rather than fail in pacman.
  property string machine: ""
  property bool archProbed: false
  readonly property bool installSupported: archProbed
    && (machine === "x86_64" || machine === "amd64")
  // The headless package ships a service marker and prints locations to
  // stdout. Other installations may route that command to another surface,
  // so the plugin falls back to direct location entry.
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
  property var availablePorts: []
  property string portsProtocol: ""

  property string lastError: ""
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
  property bool stateDirReady: false
  property string signInResultPath: ""
  property string updateResultPath: ""

  property string _statusOutput: ""
  property string _statusError: ""
  property string _locationsOutput: ""
  property string _portsOutput: ""
  property string _actionOutput: ""
  property string _actionError: ""
  property string _signInResultOutput: ""
  property string _updateResultOutput: ""
  property bool _statusAborted: false
  property bool _locationsAborted: false
  property bool _portsAborted: false
  property bool _actionAborted: false
  property bool _actionQueued: false
  property var _queuedActionCommand: []
  property string _queuedActionKind: ""
  property string _queuedActionLabel: ""
  property bool _retryLocationsAfterAction: false
  property bool _retryPortsAfterAction: false
  property bool _statusInitialized: false
  property bool _expectDown: false
  property string _actionKind: ""
  property var _target: null
  property string _requestedPortsProtocol: ""
  property string _portsInFlightProtocol: ""
  property bool _updatePending: false
  property bool _signInPending: false
  property bool _signInLauncherExited: false
  property bool _updateLauncherExited: false
  property int _signInFallbackSuccesses: 0
  property int _updateFallbackSuccesses: 0

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
  readonly property bool busy: updating || signingIn || _updatePending || _signInPending || _actionQueued
    || actionProcess.running || signInFallbackProcess.running
    || updateFallbackProcess.running || transitional
  readonly property bool loadingLocations: locationsProcess.running
  readonly property bool loadingPorts: portsProcess.running
  readonly property bool firewallLocked: firewall === "Always On"
  readonly property bool firewallOn: firewall === "On" || firewallLocked
  readonly property int refreshIntervalSec: intSetting("refreshIntervalSec", 5, 2, 60)
  readonly property bool notificationsOn: {
    var value = setting("notifications", true)
    return value !== false && String(value) !== "off"
  }
  readonly property var usage: Model.parseDataUsage(dataUsage)

  // Counters are cumulative per connection, not per view: closing the panel
  // only pauses sampling. The kernel's interface counters keep counting, so
  // the first sample after reopening rolls the unseen traffic into the
  // totals. Resets happen on connect/disconnect transitions in applyStatus.
  onPanelOpenChanged: {
    if (panelOpen && connected) {
      if (_connectedSinceMs === 0) _connectedSinceMs = Date.now()
      if (linkDevice === "") routeProbe()
    }
  }

  readonly property string statusText: {
    if (!installed) {
      if (installing) return "Installing Windscribe…"
      if (!archProbed) return "Checking system…"
      if (archProbed && !installSupported) return "Windscribe CLI unavailable"
      return "Setup required"
    }
    if (updating || _updatePending) return "Updating Windscribe…"
    if (signingIn || _signInPending) return "Signing in…"
    if ((actionProcess.running || _actionQueued) && pendingLabel !== "") return pendingLabel
    if (internet === "unavailable") return "No internet connection"
    if (loginState === "Logging in") return "Logging in…"
    if (loggedOut) return "Not signed in"
    if (loginState.indexOf("Error") === 0) return "Login error"
    if (desiredState === 1 && !connected) return "Connecting…"
    if (desiredState === 0 && connectionState !== "Disconnected") return "Disconnecting…"
    if (connectionState === "Connected") {
      if (networkInterference) return "Tunnel check failed"
      if (tunnelTestPending) return "Verifying tunnel…"
      return "Connected"
    }
    if (connectionState === "Connecting") return "Connecting…"
    if (connectionState === "Disconnecting") return "Disconnecting…"
    if (connectionState === "Disconnected") return "Ready to connect"
    if (connectionState === "Error") return "Connection error"
    return "Checking status…"
  }

  function markupSafeText(raw) {
    return Model.markupSafe(raw)
  }

  function registerPanelOwner() {
    _nextPanelOwnerId += 1
    return _nextPanelOwnerId
  }

  function setPanelOwnerOpen(ownerId, open) {
    if (!ownerId) return
    var next = ({})
    var count = 0
    for (var key in _openPanelOwners) {
      if (String(key) === String(ownerId)) continue
      next[key] = true
      count += 1
    }
    if (open) {
      next[String(ownerId)] = true
      count += 1
    }
    _openPanelOwners = next
    panelOpen = count > 0
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

  function readersFree() {
    return !statusProcess.running && !locationsProcess.running && !portsProcess.running
      && !signInFallbackProcess.running && !updateFallbackProcess.running
  }

  function localCliFree() {
    return readersFree() && !actionProcess.running && !_actionQueued
      && !_updatePending && !_signInPending
  }

  function cliFree() {
    return localCliFree() && !updating && !signingIn
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

  function refreshPorts(value) {
    var requested = Model.protocolBase(value)
    _requestedPortsProtocol = requested
    if (!installed || !loggedIn || requested === "") {
      availablePorts = []
      portsProtocol = ""
      return
    }
    if (portsProcess.running) {
      // Let the in-flight read finish. Its result is tagged with the protocol
      // that launched it and discarded if the user has since chosen another.
      return
    }
    if (!cliFree()) {
      portsRetry.restart()
      return
    }
    _portsAborted = false
    _portsOutput = ""
    _portsInFlightProtocol = requested
    portsProcess.command = ["windscribe-cli", "ports", requested]
    portsProcess.running = true
    portsWatchdog.restart()
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
      if (wasConnected) trafficReset()
      linkDevice = ""
      // A tunnel we didn't ask to close is the one thing a person must hear
      // about: the icon dimming is not a signal most people read.
      if (_statusInitialized && wasConnected && s.state === "Disconnected") {
        if (!_expectDown && !actionProcess.running) {
          notify("Windscribe disconnected",
                 firewallOn
                   ? "The Firewall is blocking traffic until you reconnect."
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

    var preferredBase = Model.protocolBase(protocolPreference())
    if (panelOpen && loggedIn && preferredBase !== ""
        && portsProtocol !== preferredBase && !portsProcess.running)
      portsRetry.restart()
  }

  function toggle() {
    if (!installed || busy) return
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
    if (!installed || busy) return
    desiredState = 1
    _expectDown = false
    _target = null
    runAction(connectCommand(null), "connect", "Connecting…")
  }

  function connectBest() {
    if (!installed || busy) return
    desiredState = 1
    _expectDown = false
    _target = null
    runAction(connectCommand("best"), "connect", "Connecting to Best Location…")
  }

  function connectTo(location) {
    if (!installed || busy) return
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
    if (!installed || busy) return
    desiredState = 0
    _expectDown = true
    runAction(["windscribe-cli", "disconnect"], "disconnect", "Disconnecting…")
  }

  function setFirewall(on) {
    if (!installed || busy || firewallLocked) return
    runAction(["windscribe-cli", "firewall", on ? "on" : "off"], "firewall", "")
  }

  // New IP on the same server (needs a plan that allows it; errors surface).
  function rotateIp() {
    if (!installed || busy || !connected) return
    runAction(["windscribe-cli", "ip", "rotate"], "rotate", "Rotating IP…")
  }

  function signOut() {
    if (!installed || busy) return
    desiredState = 0
    _expectDown = true
    runAction(["windscribe-cli", "logout", firewallOn ? "on" : "off"], "logout", "Signing out…")
  }

  // Sign-in is interactive (username, password, 2FA, on the CLI-only build a
  // captcha), so it happens in Omarchy's floating terminal. The command is a
  // fixed literal — nothing user-typed crosses a shell boundary. A private
  // result marker tells the panel exactly when the CLI has released its slot.
  function operationResultPath(kind) {
    return stateDir + "/" + kind + "-" + Date.now() + "-"
      + Math.floor(Math.random() * 1000000000) + ".result"
  }

  function startSignIn() {
    if (!_signInPending) return
    if (!readersSettled() || actionProcess.running || _actionQueued) {
      signInQueueTimer.restart()
      return
    }
    _signInPending = false
    signingIn = true
    _signInResultOutput = ""
    _signInLauncherExited = false
    _signInFallbackSuccesses = 0
    var loginCommand = "windscribe-cli login"
    if (stateDirReady) {
      signInResultPath = operationResultPath("signin")
      loginCommand = Model.terminalCommandWithResult(loginCommand, signInResultPath)
    } else {
      signInResultPath = ""
    }
    signInLaunchProcess.command = [
      "omarchy-launch-floating-terminal-with-presentation",
      loginCommand
    ]
    signInLaunchProcess.running = true
    signInWatch.restart()
  }

  function signIn() {
    if (!installed || busy) return
    lastError = ""
    _signInPending = true
    startSignIn()
  }

  function finishSignIn(result) {
    if (!signingIn) return
    signInWatch.stop()
    signingIn = false
    if (signInLaunchProcess.running) signInLaunchProcess.running = false
    var marker = signInResultPath
    signInResultPath = ""
    if (marker !== "") Quickshell.execDetached(["rm", "-f", "--", marker])
    if (result !== 0) {
      lastError = "Sign in did not complete"
      errorClearTimer.restart()
    } else if (!loggedIn) {
      loginState = "Logging in"
    }
    refresh()
  }

  // Official command-line package from windscribe.com.
  // A floating terminal owns the sudo prompt; this process never touches
  // privileges. The command is a fixed literal — nothing user-typed crosses
  // a shell boundary.
  function installCli() {
    if (installed || installing || !installSupported) return
    installing = true
    lastError = ""
    Quickshell.execDetached(["omarchy-launch-floating-terminal-with-presentation",
      Model.cliInstallCommand()])
    installWatch.restart()
  }

  // Updates can ask for elevation, so the terminal owns the prompt. The panel
  // watches status and clears the busy label once the advertised update is gone.
  function startUpdate() {
    if (!_updatePending) return
    if (!readersSettled() || actionProcess.running || _actionQueued) {
      updateQueueTimer.restart()
      return
    }
    _updatePending = false
    updating = true
    _updateResultOutput = ""
    _updateLauncherExited = false
    _updateFallbackSuccesses = 0
    var updateCommand = "windscribe-cli update"
    if (stateDirReady) {
      updateResultPath = operationResultPath("update")
      updateCommand = Model.terminalCommandWithResult(updateCommand, updateResultPath)
    } else {
      updateResultPath = ""
    }
    updateLaunchProcess.command = [
      "omarchy-launch-floating-terminal-with-presentation",
      updateCommand
    ]
    updateLaunchProcess.running = true
    updateWatch.restart()
  }

  function updateCli() {
    if (!installed || busy) return
    lastError = ""
    _updatePending = true
    startUpdate()
  }

  function finishUpdate(result) {
    if (!updating) return
    updateWatch.stop()
    updating = false
    if (updateLaunchProcess.running) updateLaunchProcess.running = false
    var marker = updateResultPath
    updateResultPath = ""
    if (marker !== "") Quickshell.execDetached(["rm", "-f", "--", marker])
    if (result !== 0) {
      lastError = "Update did not complete"
      errorClearTimer.restart()
    }
    refresh()
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
    if (!stateDirReady) return
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
    _connectedSinceMs = 0
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

  function readersSettled() {
    return readersFree() && !_statusAborted && !_locationsAborted && !_portsAborted
  }

  function startQueuedAction() {
    if (!_actionQueued) return
    if (!readersSettled()) {
      actionQueueTimer.restart()
      return
    }
    _actionKind = _queuedActionKind
    pendingLabel = _queuedActionLabel
    actionProcess.command = _queuedActionCommand
    _actionQueued = false
    _queuedActionCommand = []
    _queuedActionKind = ""
    _queuedActionLabel = ""
    actionProcess.running = true
    actionWatchdog.restart()
  }

  function resumeDeferredReads() {
    if (_retryLocationsAfterAction) {
      _retryLocationsAfterAction = false
      locationsRetry.restart()
    }
    if (_retryPortsAfterAction) {
      _retryPortsAfterAction = false
      portsRetry.restart()
    }
  }

  // Windscribe permits one CLI process. Readers are asked to stop, then the
  // action waits for their onExited handlers before taking the singleton slot.
  function runAction(command, kind, label) {
    if (statusProcess.running) {
      _statusAborted = true
      statusProcess.running = false
    }
    if (locationsProcess.running) {
      _locationsAborted = true
      locationsProcess.running = false
      _retryLocationsAfterAction = true
    }
    if (portsProcess.running) {
      _portsAborted = true
      portsProcess.running = false
      _retryPortsAfterAction = true
    }
    lastError = ""
    errorClearTimer.stop()
    _actionAborted = false
    pendingLabel = label || ""
    _actionOutput = ""
    _actionError = ""
    _queuedActionCommand = command
    _queuedActionKind = kind || ""
    _queuedActionLabel = label || ""
    _actionQueued = true
    // desiredTimeout is armed when the action EXITS, not here — a blocking
    // connect may legitimately outlive it, and status can't poll meanwhile.
    desiredTimeout.stop()
    startQueuedAction()
  }

  Process {
    id: stateDirProcess
    running: true
    command: ["bash", "-c", Model.stateDirPrepareCommand(root.stateDir)]
    onExited: function(exitCode) {
      root.stateDirReady = exitCode === 0
      if (root.stateDirReady) stateFile.reload()
      else root.applyState("{}")
    }
  }

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
    id: locationsRetry
    interval: 600
    repeat: false
    onTriggered: root.refreshLocations()
  }

  Timer {
    id: portsRetry
    interval: 600
    repeat: false
    onTriggered: root.refreshPorts(root._requestedPortsProtocol)
  }

  Timer {
    id: actionQueueTimer
    interval: 40
    repeat: false
    onTriggered: root.startQueuedAction()
  }

  Timer {
    id: updateQueueTimer
    interval: 80
    repeat: false
    onTriggered: root.startUpdate()
  }

  Timer {
    id: signInQueueTimer
    interval: 80
    repeat: false
    onTriggered: root.startSignIn()
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

  Timer {
    id: portsWatchdog
    interval: 15000
    repeat: false
    onTriggered: {
      if (!portsProcess.running) return
      root._portsAborted = true
      portsProcess.running = false
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
    interval: 1000
    repeat: true
    property int ticks: 0
    onRunningChanged: if (running) ticks = 0
    onTriggered: {
      ticks += 1
      if (signInResultProcess.running) return
      if (root.signInResultPath !== "") {
        root._signInResultOutput = ""
        signInResultProcess.command = ["cat", root.signInResultPath]
        signInResultProcess.running = true
      }
      if (((root._signInLauncherExited && ticks >= 8) || ticks > 30) && ticks % 3 === 0
          && !signInFallbackProcess.running) {
        signInFallbackProcess.command = ["windscribe-cli", "status"]
        signInFallbackProcess.running = true
      }
    }
  }

  // Same idea for the package install: up to five minutes for the download.
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

  Timer {
    id: updateWatch
    interval: 1000
    repeat: true
    property int ticks: 0
    onRunningChanged: if (running) ticks = 0
    onTriggered: {
      ticks += 1
      if (updateResultProcess.running) return
      if (root.updateResultPath !== "") {
        root._updateResultOutput = ""
        updateResultProcess.command = ["cat", root.updateResultPath]
        updateResultProcess.running = true
      }
      if (((root._updateLauncherExited && ticks >= 8) || ticks > 30) && ticks % 3 === 0
          && !updateFallbackProcess.running) {
        updateFallbackProcess.command = ["windscribe-cli", "status"]
        updateFallbackProcess.running = true
      }
    }
  }

  Process {
    id: signInLaunchProcess
    running: false
    command: []
    onExited: root._signInLauncherExited = true
  }

  Process {
    id: updateLaunchProcess
    running: false
    command: []
    onExited: root._updateLauncherExited = true
  }

  Process {
    id: signInFallbackProcess
    running: false
    command: []
    environment: ({ LC_ALL: "C", LANG: "C", LANGUAGE: "en" })
    stdout: StdioCollector { id: signInFallbackStdout; waitForEnd: true }
    onExited: function(exitCode) {
      if (!root.signingIn) {
        root.refresh()
        return
      }
      if (exitCode !== 0) {
        root._signInFallbackSuccesses = 0
        return
      }
      root.applyStatus(String(signInFallbackStdout.text || ""))
      if (root.loggedIn) {
        root.finishSignIn(0)
      } else {
        root._signInFallbackSuccesses += 1
        if (root._signInFallbackSuccesses >= 2) root.finishSignIn(1)
      }
    }
  }

  Process {
    id: updateFallbackProcess
    running: false
    command: []
    environment: ({ LC_ALL: "C", LANG: "C", LANGUAGE: "en" })
    stdout: StdioCollector { id: updateFallbackStdout; waitForEnd: true }
    onExited: function(exitCode) {
      if (!root.updating) {
        root.refresh()
        return
      }
      if (exitCode !== 0) {
        root._updateFallbackSuccesses = 0
        return
      }
      root.applyStatus(String(updateFallbackStdout.text || ""))
      if (root.updateAvailable === "") {
        root.finishUpdate(0)
      } else {
        root._updateFallbackSuccesses += 1
        if (root._updateFallbackSuccesses >= 2) root.finishUpdate(1)
      }
    }
  }

  Process {
    id: signInResultProcess
    running: false
    command: []
    stdout: StdioCollector {
      id: signInResultStdout
      waitForEnd: true
      onStreamFinished: root._signInResultOutput = text
    }
    onExited: function(exitCode) {
      if (exitCode !== 0) return
      var result = parseInt(String(root._signInResultOutput || signInResultStdout.text || "1"), 10)
      root.finishSignIn(result)
    }
  }

  Process {
    id: updateResultProcess
    running: false
    command: []
    stdout: StdioCollector {
      id: updateResultStdout
      waitForEnd: true
      onStreamFinished: root._updateResultOutput = text
    }
    onExited: function(exitCode) {
      if (exitCode !== 0) return
      var result = parseInt(String(root._updateResultOutput || updateResultStdout.text || "1"), 10)
      root.finishUpdate(result)
    }
  }

  FileView {
    id: stateFile
    path: root.statePath
    printErrors: false
    onLoaded: if (root.stateDirReady) root.applyState(text())
    onLoadFailed: root.applyState("{}")
  }

  Process {
    id: archProcess
    running: true
    command: ["uname", "-m"]
    stdout: StdioCollector { id: archStdout; waitForEnd: true }
    onExited: function() {
      root.machine = String(archStdout.text || "").trim()
      root.archProbed = true
    }
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
    // Windscribe localizes CLI output to the system language. These two
    // machine-parsed calls must stay on its stable English output contract.
    environment: ({ LC_ALL: "C", LANG: "C", LANGUAGE: "en" })
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
    environment: ({ LC_ALL: "C", LANG: "C", LANGUAGE: "en" })
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
          root.locations = []
          root.locationsLoaded = false
          root.locationsUnavailable = true
        }
      }
      root.refresh()
    }
  }

  Process {
    id: portsProcess
    running: false
    command: []
    environment: ({ LC_ALL: "C", LANG: "C", LANGUAGE: "en" })
    stdout: StdioCollector {
      id: portsStdout
      waitForEnd: true
      onStreamFinished: root._portsOutput = text
    }
    onExited: function(exitCode) {
      portsWatchdog.stop()
      var completedProtocol = root._portsInFlightProtocol
      root._portsInFlightProtocol = ""
      if (root._portsAborted) {
        root._portsAborted = false
        if (!root._retryPortsAfterAction && !root._actionQueued && !actionProcess.running)
          portsRetry.restart()
        return
      }
      if (completedProtocol !== root._requestedPortsProtocol) {
        portsRetry.restart()
        return
      }
      if (exitCode === 0) {
        root.availablePorts = Model.parsePorts(root._portsOutput || portsStdout.text || "")
        root.portsProtocol = completedProtocol
      } else {
        root.availablePorts = []
        root.portsProtocol = ""
      }
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
        root._actionKind = ""
        root._target = null
        root.pendingLabel = ""
        root.resumeDeferredReads()
        root.refresh()
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
          // No in-panel confirmation: the hero, tunnel line, and button
          // already flip on connect, and a transient line would resize the
          // panel. The desktop notification carries the CLI's own words.
          var lines = stdout.split(/\r?\n/).filter(function(l) { return l.trim() !== "" })
          var line = Model.elide(lines.length > 0 ? lines[lines.length - 1] : "Connected")
          root.recordRecent(target)
          root.notify("Windscribe connected", line, "normal")
        }
        // Post-exit settle guard: drop the optimistic state if status never
        // confirms it within a poll cycle or two.
        if (root.desiredState !== -1) desiredTimeout.restart()
      }
      settleTimer.ticks = 0
      settleTimer.restart()
      root.resumeDeferredReads()
    }
  }
}
