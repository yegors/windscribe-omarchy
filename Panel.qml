import QtQuick
import QtQuick.Controls
import qs.Commons
import qs.Ui
import "Model.js" as Model
import "." as WindscribeCore

Panel {
  id: root
  moduleName: "com.windscribe.vpn"
  ipcTarget: "com.windscribe.vpn"
  manageIpc: false

  readonly property var vpn: WindscribeCore.VpnState

  property var anchorItem: null
  property var hostWidget: null
  property string tab: "locations"
  property string locationQuery: ""
  property int locationIndex: 0
  property int connectionIndex: 0
  property int recoveryIndex: 0
  property string focusedConnectionKey: "firewall"
  property string focusSection: "header"
  property bool cursorActive: true
  property var favoriteLocations: []
  property bool signOutArmed: false
  property int panelOwnerId: 0
  property string ddOpen: ""
  property int ddIndex: 0

  readonly property var barIdentity: hostWidget || root

  // The design's ink levels, derived from the theme foreground so every
  // Omarchy palette keeps the same hierarchy.
  readonly property color fg: bar ? bar.foreground : Color.foreground
  readonly property color urgentFg: bar ? bar.urgent : Color.urgent
  readonly property color accent: Color.accent
  readonly property color valueFg: Qt.rgba(fg.r, fg.g, fg.b, 0.92)
  readonly property color rowFg: Qt.rgba(fg.r, fg.g, fg.b, 0.80)
  readonly property color labelFg: Qt.rgba(fg.r, fg.g, fg.b, 0.60)
  readonly property color dimFg: Qt.rgba(fg.r, fg.g, fg.b, 0.45)
  readonly property color faintFg: Qt.rgba(fg.r, fg.g, fg.b, 0.32)
  readonly property color hairline: Qt.rgba(fg.r, fg.g, fg.b, 0.10)
  readonly property color leaderLine: Qt.rgba(fg.r, fg.g, fg.b, 0.16)
  readonly property color accentDim: Qt.rgba(accent.r, accent.g, accent.b, 0.45)
  // Opposite pole of the foreground: text on the filled connect button and
  // an opaque surface for dropdown menus, on light and dark themes alike.
  // hslHue is -1 for achromatic colors, so clamp it.
  readonly property color inverseFg: fg.hslLightness > 0.5
    ? Qt.hsla(Math.max(0, fg.hslHue), Math.min(fg.hslSaturation, 0.25), 0.07, 1)
    : Qt.hsla(Math.max(0, fg.hslHue), Math.min(fg.hslSaturation, 0.25), 0.96, 1)
  readonly property string contentFontFamily: bar ? bar.fontFamily : Style.font.family

  readonly property real fzCity: Style.font.display
  readonly property real fzTitle: Style.font.bodySmall
  readonly property real fzRow: Style.font.bodySmall
  readonly property real fzMeta: Style.font.caption
  readonly property real fzSmall: Math.max(8, Math.round(Style.font.caption * 0.92))
  readonly property real fzMicro: Math.max(8, Math.round(Style.font.caption * 0.84))

  readonly property string toggleHint: vpn.active ? "Disconnect Windscribe" : "Connect Windscribe"
  readonly property var visibleEntries: buildEntries()
  readonly property var connectionEntries: buildConnectionEntries()
  readonly property bool recoveryVisible: vpn.networkInterference || vpn.connectionState === "Error"
  readonly property bool motionOn: {
    var value = settings ? settings.motion : undefined
    return value !== false && String(value === undefined ? "on" : value) !== "off"
  }
  readonly property string selectedProtocol: Model.normalizeProtocol(
    (settings && settings.preferredProtocol) || ""
  )
  readonly property string selectedProtocolBase: Model.protocolBase(selectedProtocol)
  readonly property string selectedProtocolPort: Model.protocolPort(selectedProtocol)
  readonly property var portOptions: buildPortOptions()
  readonly property var protocolOptions: [
    { value: "", label: "automatic" },
    { value: "wireguard", label: "wireguard" },
    { value: "udp", label: "udp" },
    { value: "tcp", label: "tcp" },
    { value: "stealth", label: "stealth" },
    { value: "wstunnel", label: "wstunnel" }
  ]
  readonly property var waveLevels: buildWave()
  readonly property bool tunnelSettled: vpn.connected && !vpn.transitional
    && vpn.desiredState === -1 && !vpn.busy

  function open() {
    root.controller.show()
  }

  function close() {
    root.controller.hide()
  }

  function toggle() {
    if (root.opened) root.close()
    else root.open()
  }

  function switchPanel(direction) {
    if (root.bar && typeof root.bar.switchPanelFrom === "function")
      return root.bar.switchPanelFrom(root.barIdentity, direction)
    return false
  }

  function setTab(key) {
    if (key !== "locations" && key !== "connection") return
    tab = key
    ddOpen = ""
    focusSection = "header"
    if (panelFlick) panelFlick.contentY = 0
  }

  function cycleTab(direction) {
    if (!vpn.installed || !vpn.loggedIn) return
    setTab(tab === "locations" ? "connection" : "locations")
  }

  function syncFavoriteLocations() {
    var source = settings && settings.favoriteLocations instanceof Array
      ? settings.favoriteLocations
      : []
    favoriteLocations = source.slice()
  }

  function isFavorite(value) {
    var target = String(value || "").toLowerCase()
    for (var i = 0; i < favoriteLocations.length; i++)
      if (String(favoriteLocations[i] || "").toLowerCase() === target) return true
    return false
  }

  function entryMatches(entry, query) {
    if (query === "") return true
    return String(entry.city).toLowerCase().indexOf(query) !== -1
      || String(entry.country).toLowerCase().indexOf(query) !== -1
      || String(entry.nickname).toLowerCase().indexOf(query) !== -1
  }

  // Resolves a nickname, a city, or the CLI status line's combined
  // "City Nickname" form to one locations entry.
  function locationByTarget(value) {
    var target = String(value || "").trim().toLowerCase()
    if (target === "") return null
    var available = vpn.locations || []
    for (var i = 0; i < available.length; i++) {
      var city = String(available[i].city).toLowerCase()
      var nickname = String(available[i].nickname).toLowerCase()
      if (target === nickname || target === city) return available[i]
      if (nickname !== ""
          && (target === city + " " + nickname
              || target === city + " - " + nickname)) return available[i]
    }
    return null
  }

  readonly property var currentLocation: locationByTarget(vpn.city)

  function entryForTarget(value, kindFallback) {
    var resolved = locationByTarget(value)
    return resolved
      ? { kind: "location", city: resolved.city, country: resolved.country,
          nickname: resolved.nickname, pro: resolved.pro, tenGbps: resolved.tenGbps }
      : { kind: kindFallback, city: String(value), country: "", nickname: "", pro: false, tenGbps: false }
  }

  function entryTarget(entry) {
    if (!entry || entry.kind === "best") return ""
    return String(entry.nickname || entry.city || "")
  }

  function entryKey(entry) {
    return (String(entry.country || "") + "|" + String(entry.city || "")
      + "|" + String(entry.nickname || "")).toLowerCase()
  }

  function targetKey(value) {
    return "target:" + String(value || "").toLowerCase()
  }

  function lcText(value) {
    return vpn.markupSafeText(value).toLowerCase()
  }

  function buildConnectionEntries() {
    var out = ["firewall", "protocol", "notifications", "motion"]
    if (selectedProtocolBase !== "") out.splice(2, 0, "port")
    if (vpn.connected && vpn.ipIsVpn) out.push("rotate")
    if (vpn.updateAvailable !== "") out.push("update")
    out.push("signout")
    return out
  }

  function buildPortOptions() {
    var out = [{ value: "", label: "auto" }]
    var seen = ({})
    var ports = vpn.portsProtocol === selectedProtocolBase ? vpn.availablePorts : []
    for (var i = 0; i < ports.length; i++) {
      var value = String(ports[i])
      if (seen[value]) continue
      seen[value] = true
      out.push({ value: value, label: value })
    }
    if (selectedProtocolPort !== "" && !seen[selectedProtocolPort])
      out.push({ value: selectedProtocolPort, label: selectedProtocolPort })
    return out
  }

  function buildEntries() {
    var query = String(locationQuery || "").trim().toLowerCase()
    var out = []
    var seen = ({})

    var bestMatches = query === ""
      || "best location".indexOf(query) === 0
      || "fastest location".indexOf(query) === 0
      || "best".indexOf(query) === 0
    if (vpn.installed && bestMatches)
      out.push({ kind: "best", city: "", country: "", nickname: "", pro: false, tenGbps: false })

    for (var i = 0; i < favoriteLocations.length; i++) {
      var favorite = String(favoriteLocations[i] || "").trim()
      if (favorite === "" || seen[targetKey(favorite)]) continue
      var entry = entryForTarget(favorite, "favorite")
      if (entryMatches(entry, query)) {
        out.push(entry)
        seen[entryKey(entry)] = true
        seen[targetKey(favorite)] = true
      }
    }

    var matched = false
    for (var k = 0; k < out.length; k++)
      if (out[k].kind !== "best") matched = true
    var available = vpn.locations || []
    for (var j = 0; j < available.length; j++) {
      var location = available[j]
      if (location.disabled) continue
      var candidate = { kind: "location", city: location.city, country: location.country,
                        nickname: location.nickname, pro: location.pro, tenGbps: location.tenGbps }
      var key = entryKey(candidate)
      if (seen[key] || seen[targetKey(entryTarget(candidate))] || !entryMatches(candidate, query)) continue
      out.push(candidate)
      seen[key] = true
      seen[targetKey(entryTarget(candidate))] = true
      matched = true
    }
    if (query !== "" && !matched && vpn.installed && vpn.isSafeLocation(locationQuery.trim()))
      out.push({ kind: "custom", city: locationQuery.trim(), country: "", nickname: "", pro: false, tenGbps: false })

    return out
  }

  function rowIndexLabel(index) {
    var value = index + 1
    return (value < 10 ? "0" : "") + value
  }

  function entrySlug(entry) {
    if (entry.kind === "best") return "fastest location"
    if (entry.kind === "custom") return "connect “" + lcText(entry.city) + "”"
    return Model.slugify(entry.city)
  }

  function entryMeta(entry) {
    if (entry.kind === "best") return "auto · lowest latency"
    if (entry.kind === "custom") return "city, region, or nickname"
    var parts = []
    if (entry.country) parts.push(Model.slugify(entry.country))
    if (entry.nickname) parts.push(lcText(entry.nickname))
    if (entry.pro) parts.push("pro")
    return parts.join(" · ")
  }

  function entryBadge(entry) {
    if (entry.kind === "best") return "auto"
    return entry.tenGbps ? "10g" : ""
  }

  function entryTitle(entry) {
    if (entry.kind === "best") return "Fastest location"
    if (entry.kind === "custom") return "Connect to “" + vpn.markupSafeText(entry.city) + "”"
    return vpn.markupSafeText(entry.city)
  }

  function entrySubtitle(entry) {
    if (entry.kind === "best") return "Windscribe's lowest-latency choice"
    if (entry.kind === "custom") return "City, region, country code, or nickname"
    var parts = []
    if (entry.country) parts.push(vpn.markupSafeText(entry.country))
    if (entry.nickname) parts.push(vpn.markupSafeText(entry.nickname))
    if (entry.pro) parts.push("Pro")
    if (entry.tenGbps) parts.push("10 Gbps")
    return parts.join(" · ")
  }

  function entryStarable(entry) {
    return entry.kind === "location" || entry.kind === "favorite" || entry.kind === "custom"
  }

  function entryCurrent(entry) {
    if (entry.city === "") return false
    // vpn.city may be the CLI's combined "City Nickname" form; compare
    // against the resolved city so the current row still highlights.
    var current = root.currentLocation
      ? String(root.currentLocation.city)
      : String(vpn.city || "")
    return current !== ""
      && String(entry.city).toLowerCase() === current.toLowerCase()
  }

  function activateEntry(entry) {
    if (entry.kind === "best") vpn.connectBest()
    else vpn.connectTo(entryTarget(entry))
  }

  // ── Hero copy ─────────────────────────────────────────────────────────
  function heroTargetCity() {
    if (vpn.city !== "") return String(vpn.city)
    if (!vpn.connected && vpn.lastLocation !== "") return String(vpn.lastLocation)
    return ""
  }

  // Both states render identically: the city big, "nickname · region" below.
  function heroCityText() {
    var target = heroTargetCity()
    if (target === "") return vpn.connected ? "connected" : "last location"
    var resolved = locationByTarget(target)
    return lcText(resolved ? resolved.city : target)
  }

  function heroMetaText() {
    var target = heroTargetCity()
    if (target === "") return vpn.connected ? "" : "cli default"
    var resolved = locationByTarget(target)
    if (!resolved) return ""
    var parts = []
    if (resolved.nickname) parts.push(lcText(resolved.nickname))
    if (resolved.country) parts.push(Model.slugify(resolved.country))
    return parts.join(" · ")
  }

  function firewallShort() {
    return "fw " + (vpn.firewallOn ? "on" : "off")
  }

  function tunnelLineText() {
    if (vpn.transitional || vpn.desiredState !== -1 || vpn.connectionState === "Disconnecting")
      return lcText(vpn.pendingLabel !== "" ? vpn.pendingLabel : vpn.statusText)
    if (vpn.connected) {
      var parts = []
      if (vpn.tunnelTestPending) parts.push("verifying")
      var proto = Model.protocolStatusShort(vpn.protocol)
      if (proto !== "") parts.push(proto)
      parts.push(firewallShort())
      return parts.join(" · ")
    }
    var next = selectedProtocolBase === ""
      ? "auto"
      : Model.protocolShortName(selectedProtocolBase)
        + (selectedProtocolPort !== "" ? "/" + selectedProtocolPort : "")
    return "next: " + next + " · " + firewallShort()
  }

  function connectLabel() {
    if (vpn.transitional || vpn.desiredState !== -1 || vpn.busy || vpn.connectionState === "Disconnecting") {
      var pending = vpn.pendingLabel !== "" ? vpn.pendingLabel : vpn.statusText
      return lcText(pending)
    }
    if (vpn.connected) return "■ disconnect · " + Model.formatDuration(vpn.uptimeSec)
    return "▶ connect"
  }

  function protocolValueText() {
    if (selectedProtocolBase === "") return "automatic"
    for (var i = 0; i < protocolOptions.length; i++)
      if (protocolOptions[i].value === selectedProtocolBase) return protocolOptions[i].label
    return selectedProtocolBase
  }

  function portValueText() {
    return selectedProtocolPort === "" ? "auto" : selectedProtocolPort
  }

  function buildWave() {
    var n = 44
    var rx = vpn.rxHistory || []
    var tx = vpn.txHistory || []
    var vals = []
    var max = 0
    for (var i = 0; i < n; i++) {
      var ri = rx.length - n + i
      var ti = tx.length - n + i
      var v = (ri >= 0 ? Number(rx[ri]) || 0 : 0) + (ti >= 0 ? Number(tx[ti]) || 0 : 0)
      vals.push(v)
      if (v > max) max = v
    }
    var out = []
    for (var j = 0; j < n; j++) out.push(max > 0 ? vals[j] / max : 0)
    return out
  }

  function persistSetting(key, value) {
    if (!root.bar || !root.bar.shell || typeof root.bar.shell.updateEntryInline !== "function") return
    var entry = { id: root.moduleName }
    for (var existing in settings) if (existing !== "id") entry[existing] = settings[existing]
    entry[key] = value
    root.bar.shell.updateEntryInline(root.moduleName, entry)
  }

  function persistLastLocation() {
    var current = settings && settings.lastLocation !== undefined ? String(settings.lastLocation) : ""
    if (vpn.lastLocation === "" || current === vpn.lastLocation) return
    persistSetting("lastLocation", vpn.lastLocation)
  }

  function toggleFavorite(value) {
    var target = String(value || "").trim()
    if (target === "") return
    var next = []
    var found = false
    for (var i = 0; i < favoriteLocations.length; i++) {
      var current = String(favoriteLocations[i] || "")
      if (current.toLowerCase() === target.toLowerCase()) found = true
      else if (current !== "" && next.indexOf(current) === -1) next.push(current)
    }
    if (!found) next.unshift(target)
    favoriteLocations = next
    persistSetting("favoriteLocations", next)
    clampLocationIndex()
  }

  function clampLocationIndex() {
    locationIndex = Math.max(0, Math.min(locationIndex, Math.max(0, visibleEntries.length - 1)))
  }

  function focusHeader() {
    cursorActive = true
    focusSection = "header"
    keyCatcher.forceActiveFocus()
    if (panelFlick) panelFlick.contentY = 0
  }

  function ensurePanelItemVisible(item) {
    if (!item || !panelFlick || !panelColumn) return
    var point = item.mapToItem(panelColumn, 0, 0)
    var margin = Style.space(14)
    var top = point.y
    var bottom = top + item.height
    if (top < panelFlick.contentY + margin)
      panelFlick.contentY = Math.max(0, top - margin)
    else if (bottom > panelFlick.contentY + panelFlick.height - margin)
      panelFlick.contentY = Math.min(maxScroll(), bottom - panelFlick.height + margin)
  }

  function connectionControl(key) {
    if (key === "firewall") return firewallControl
    if (key === "protocol") return protocolPicker
    if (key === "port") return portPicker
    if (key === "notifications") return alertsControl
    if (key === "motion") return motionControl
    if (key === "rotate") return rotateAction
    if (key === "update") return updateAction
    if (key === "signout") return signOutAction
    return null
  }

  function focusLocation(index) {
    cursorActive = true
    focusSection = "locations"
    locationIndex = Math.max(0, Math.min(Number(index), Math.max(0, visibleEntries.length - 1)))
    keyCatcher.forceActiveFocus()
    Qt.callLater(function() {
      locationList.positionViewAtIndex(locationIndex, ListView.Contain)
      root.ensurePanelItemVisible(locationList)
    })
  }

  function focusConnection(index) {
    cursorActive = true
    focusSection = "connection"
    connectionIndex = Math.max(0, Math.min(Number(index), Math.max(0, connectionEntries.length - 1)))
    focusedConnectionKey = connectionEntries.length > 0 ? connectionEntries[connectionIndex] : ""
    keyCatcher.forceActiveFocus()
    Qt.callLater(function() {
      root.ensurePanelItemVisible(root.connectionControl(root.connectionEntries[root.connectionIndex]))
    })
  }

  function focusRecovery(index) {
    cursorActive = true
    focusSection = "recovery"
    recoveryIndex = Math.max(0, Math.min(Number(index), 1))
    keyCatcher.forceActiveFocus()
    Qt.callLater(function() { root.ensurePanelItemVisible(recoveryRow) })
  }

  function focusConnectionKey(key) {
    var index = connectionEntries.indexOf(key)
    if (index >= 0) focusConnection(index)
  }

  function connectionHasCursor(key) {
    return cursorActive && tab === "connection" && focusSection === "connection"
      && focusedConnectionKey === key
  }

  // ── Dropdown popups ──────────────────────────────────────────────────
  function ddOptions() {
    if (ddOpen === "protocol") return protocolOptions
    if (ddOpen === "port") return portOptions
    return []
  }

  function ddCurrentValue() {
    if (ddOpen === "protocol") return selectedProtocolBase
    if (ddOpen === "port") return selectedProtocolPort
    return ""
  }

  function toggleDropdown(key) {
    if (ddOpen === key) {
      ddOpen = ""
      return
    }
    ddOpen = key
    var options = ddOptions()
    var current = ddCurrentValue()
    ddIndex = 0
    for (var i = 0; i < options.length; i++)
      if (options[i].value === current) ddIndex = i
    focusConnectionKey(key)
  }

  function pickDropdown(value) {
    if (ddOpen === "protocol") {
      persistSetting("preferredProtocol", value)
      if (value !== "") vpn.refreshPorts(value)
    } else if (ddOpen === "port") {
      persistSetting("preferredProtocol",
        selectedProtocolBase + (value === "" ? "" : ":" + value))
    }
    ddOpen = ""
  }

  function moveCursor(direction) {
    cursorActive = true
    if (ddOpen !== "") {
      var options = ddOptions()
      if (options.length > 0)
        ddIndex = (ddIndex + direction + options.length) % options.length
      return
    }
    if (tab === "connection") {
      if (connectionEntries.length === 0) {
        focusSection = "header"
        return
      }
      if (focusSection === "header") {
        if (direction > 0) {
          if (recoveryVisible) focusRecovery(recoveryIndex)
          else focusConnection(connectionIndex)
        }
        return
      }
      if (focusSection === "recovery") {
        if (direction < 0) {
          if (recoveryIndex === 0) focusHeader()
          else recoveryIndex -= 1
        } else if (recoveryIndex === 0) {
          recoveryIndex = 1
        } else {
          focusConnection(connectionIndex)
        }
        return
      }
      if (direction < 0 && connectionIndex === 0) {
        focusHeader()
        return
      }
      connectionIndex = (connectionIndex + direction + connectionEntries.length) % connectionEntries.length
      focusedConnectionKey = connectionEntries[connectionIndex]
      Qt.callLater(function() {
        root.ensurePanelItemVisible(root.connectionControl(root.connectionEntries[root.connectionIndex]))
      })
      return
    }
    // The list is only rendered while installed and signed in; never let the
    // cursor wander into it (or Enter act on it) otherwise.
    if (!vpn.installed || !vpn.loggedIn || visibleEntries.length === 0) {
      focusSection = "header"
      return
    }
    if (focusSection === "header") {
      if (direction > 0) {
        if (recoveryVisible) focusRecovery(recoveryIndex)
        else focusLocation(locationIndex)
      }
      return
    }
    if (focusSection === "recovery") {
      if (direction < 0) {
        if (recoveryIndex === 0) focusHeader()
        else recoveryIndex -= 1
      } else if (recoveryIndex === 0) {
        recoveryIndex = 1
      } else {
        focusLocation(locationIndex)
      }
      return
    }
    if (direction < 0 && locationIndex === 0) {
      focusHeader()
      return
    }
    locationIndex = (locationIndex + direction + visibleEntries.length) % visibleEntries.length
    Qt.callLater(function() { locationList.positionViewAtIndex(locationIndex, ListView.Contain) })
  }

  function activateConnection() {
    if (connectionEntries.length === 0) return
    var key = focusedConnectionKey
    // Pure-UI rows stay usable while the CLI is busy, matching the mouse.
    var uiOnly = key === "protocol" || key === "port"
      || key === "notifications" || key === "motion"
    if (vpn.busy && !uiOnly) return
    if (key === "firewall") {
      if (!vpn.firewallLocked) vpn.setFirewall(!vpn.firewallOn)
    }
    else if (key === "protocol") toggleDropdown("protocol")
    else if (key === "port") toggleDropdown("port")
    else if (key === "notifications")
      persistSetting("notifications", !vpn.notificationsOn)
    else if (key === "motion")
      persistSetting("motion", !root.motionOn)
    else if (key === "rotate") vpn.rotateIp()
    else if (key === "update") vpn.updateCli()
    else if (key === "signout") {
      if (signOutArmed) {
        signOutArmed = false
        signOutArmTimer.stop()
        vpn.signOut()
      } else {
        signOutArmed = true
        signOutArmTimer.restart()
      }
    }
  }

  function activateRecovery() {
    if (recoveryIndex === 0) {
      var resolved = root.currentLocation
      if (resolved) vpn.connectTo(String(resolved.nickname || resolved.city))
      else if (vpn.city !== "") vpn.connectTo(vpn.city)
      else vpn.connect()
    } else {
      setTab("connection")
      focusConnectionKey("protocol")
    }
  }

  function activateCursor() {
    if (ddOpen !== "") {
      var options = ddOptions()
      if (options.length > 0)
        pickDropdown(options[Math.max(0, Math.min(ddIndex, options.length - 1))].value)
      else ddOpen = ""
      return
    }
    if (focusSection === "locations" && tab === "locations"
        && vpn.installed && vpn.loggedIn && visibleEntries.length > 0) {
      activateEntry(visibleEntries[locationIndex])
      return
    }
    if (focusSection === "recovery" && recoveryVisible) {
      activateRecovery()
      return
    }
    if (focusSection === "connection" && tab === "connection") {
      activateConnection()
      return
    }
    if (!vpn.installed) {
      if (vpn.installSupported) vpn.installCli()
      return
    }
    if (vpn.loggedOut && !vpn.connected) {
      vpn.signIn()
      return
    }
    if (focusSection === "header") vpn.toggle()
  }

  function handleClose() {
    if (ddOpen !== "") {
      ddOpen = ""
      return
    }
    if (tab === "connection") {
      setTab("locations")
      return
    }
    close()
  }

  function focusSearch() {
    searchField.forceActiveFocus()
    searchField.selectAll()
  }

  function maxScroll() {
    return Math.max(0, panelFlick.contentHeight - panelFlick.height)
  }

  onSettingsChanged: {
    syncFavoriteLocations()
    persistLastLocation()
  }
  Connections {
    target: vpn
    function onLastLocationChanged() { root.persistLastLocation() }
  }
  onSelectedProtocolBaseChanged: {
    if (selectedProtocolBase !== "") vpn.refreshPorts(selectedProtocolBase)
    else if (ddOpen === "port") ddOpen = ""
  }
  onRecoveryVisibleChanged: {
    if (!recoveryVisible && opened && focusSection === "recovery") focusHeader()
  }
  onVisibleEntriesChanged: clampLocationIndex()
  onConnectionEntriesChanged: {
    var preserved = connectionEntries.indexOf(focusedConnectionKey)
    connectionIndex = preserved >= 0
      ? preserved
      : Math.max(0, Math.min(connectionIndex, Math.max(0, connectionEntries.length - 1)))
    focusedConnectionKey = connectionEntries.length > 0 ? connectionEntries[connectionIndex] : ""
  }
  Component.onCompleted: {
    syncFavoriteLocations()
    persistLastLocation()
    panelOwnerId = vpn.registerPanelOwner()
  }
  Component.onDestruction: vpn.setPanelOwnerOpen(panelOwnerId, false)

  onOpenedChanged: {
    vpn.setPanelOwnerOpen(panelOwnerId, opened)
    if (opened) {
      tab = "locations"
      ddOpen = ""
      signOutArmed = false
      vpn.refresh()
      if (vpn.cliOnlyBuild && !vpn.locationsLoaded) vpn.refreshLocations()
      if (root.selectedProtocolBase !== "") vpn.refreshPorts(root.selectedProtocolBase)
      cursorActive = true
      focusSection = "header"
      Qt.callLater(function() { keyCatcher.forceActiveFocus() })
    }
  }

  Timer {
    id: signOutArmTimer
    interval: 5000
    repeat: false
    onTriggered: root.signOutArmed = false
  }

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.barIdentity
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(400))
    contentHeight: panel.fittedContentHeight(panelColumn.implicitHeight, Style.space(700))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      blocked: searchField.activeFocus
      onMoveRequested: function(dx, dy) {
        if (dy !== 0) root.moveCursor(dy)
        else if (dx !== 0) root.cycleTab(dx)
      }
      onActivateRequested: root.activateCursor()
      onCloseRequested: root.handleClose()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onTextKey: function(text) {
        if (root.ddOpen !== "") return
        if (text === "t" || text === "T") vpn.toggle()
        else if (text === "r" || text === "R") {
          vpn.refresh()
          vpn.refreshLocations()
        } else if (text === "w" || text === "W") {
          if (!vpn.firewallLocked) vpn.setFirewall(!vpn.firewallOn)
        } else if (text === "s" || text === "S") {
          root.cycleTab(1)
        } else if (text === "f" || text === "F") {
          if (root.tab === "locations" && root.focusSection === "locations" && root.visibleEntries.length > 0) {
            var entry = root.visibleEntries[root.locationIndex]
            if (root.entryStarable(entry)) root.toggleFavorite(root.entryTarget(entry))
          }
        } else if (text === "/") {
          if (root.tab !== "locations") root.setTab("locations")
          Qt.callLater(root.focusSearch)
        }
      }

      Flickable {
        id: panelFlick
        anchors.fill: parent
        contentWidth: width
        contentHeight: panelColumn.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        flickableDirection: Flickable.VerticalFlick
        interactive: contentHeight > height
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

        // Fixed steps instead of Flickable's momentum: one wheel notch moves
        // about a row and a half, and the content never coasts.
        WheelHandler {
          target: null
          acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
          onWheel: function(event) {
            var dy = event.pixelDelta.y !== 0 ? event.pixelDelta.y : (event.angleDelta.y / 120) * Style.space(72)
            panelFlick.contentY = Math.max(0, Math.min(root.maxScroll(), panelFlick.contentY - dy))
            event.accepted = true
          }
        }

        Column {
          id: panelColumn
          width: panelFlick.width
          spacing: Style.space(12)

          // ── Header: wordmark · dashed leader · VPN IP · rotate ─────────
          Item {
            id: headerItem
            width: parent.width
            implicitHeight: Style.space(22)
            Accessible.role: Accessible.StaticText
            Accessible.name: "Windscribe. " + vpn.statusText

            Text {
              id: wordmark
              anchors.left: parent.left
              anchors.verticalCenter: parent.verticalCenter
              text: "windscribe"
              textFormat: Text.PlainText
              color: root.fg
              font.family: root.contentFontFamily
              font.pixelSize: root.fzTitle
              font.bold: true
              font.letterSpacing: 0.3
            }

            Leader {
              anchors.left: wordmark.right
              anchors.leftMargin: Style.space(10)
              anchors.right: headerRight.left
              anchors.rightMargin: Style.space(10)
              anchors.verticalCenter: parent.verticalCenter
              lineColor: root.leaderLine
            }

            Row {
              id: headerRight
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.space(8)

              Text {
                anchors.verticalCenter: parent.verticalCenter
                text: {
                  if (root.tab === "connection") return "settings"
                  if (vpn.connected && vpn.ipIsVpn && vpn.ipAddress !== "")
                    return vpn.markupSafeText(vpn.ipAddress)
                  return "off"
                }
                textFormat: Text.PlainText
                color: root.tab !== "connection" && vpn.connected && vpn.ipIsVpn
                  ? root.accent
                  : root.labelFg
                font.family: root.contentFontFamily
                font.pixelSize: root.fzMeta
                font.bold: root.tab !== "connection" && vpn.connected && vpn.ipIsVpn
                font.letterSpacing: 0.3
              }

              Text {
                id: rotateGlyph
                visible: root.tab === "locations" && vpn.connected && vpn.ipIsVpn
                anchors.verticalCenter: parent.verticalCenter
                text: "󰑓"
                textFormat: Text.PlainText
                color: rotateArea.containsMouse && !vpn.busy ? root.fg : root.dimFg
                font.family: root.contentFontFamily
                font.pixelSize: root.fzMeta
                Accessible.role: Accessible.Button
                Accessible.name: "Rotate IP"
                Accessible.focusable: true
                Accessible.onPressAction: if (!vpn.busy) vpn.rotateIp()

                MouseArea {
                  id: rotateArea
                  anchors.fill: parent
                  anchors.margins: -Style.space(4)
                  hoverEnabled: true
                  enabled: !vpn.busy
                  cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                  onClicked: vpn.rotateIp()
                }
              }
            }
          }

          // ── First run: Windscribe isn't there yet ───────────────────────
          Text {
            visible: !vpn.installed && !vpn.archProbed
            width: parent.width
            text: "probing system…"
            textFormat: Text.PlainText
            color: root.dimFg
            font.family: root.contentFontFamily
            font.pixelSize: root.fzSmall
          }

          Column {
            visible: !vpn.installed && vpn.installSupported
            width: parent.width
            spacing: Style.space(8)

            BlockButton {
              width: parent.width
              label: vpn.installing ? "installing…" : "▶ install windscribe"
              primary: !vpn.installing
              enabled: !vpn.installing
              hasCursor: root.cursorActive && root.focusSection === "header"
              accessibleName: "Install Windscribe CLI"
              onActivated: vpn.installCli()
              onHoverFocus: root.focusHeader()
            }

            Text {
              width: parent.width
              text: vpn.installing ? "finish in the terminal" : "required to connect"
              textFormat: Text.PlainText
              color: root.faintFg
              font.family: root.contentFontFamily
              font.pixelSize: root.fzMicro
            }
          }

          Column {
            visible: !vpn.installed && vpn.archProbed && !vpn.installSupported
            width: parent.width
            spacing: Style.space(4)

            Text {
              width: parent.width
              text: "windscribe cli is unavailable"
              textFormat: Text.PlainText
              color: root.rowFg
              font.family: root.contentFontFamily
              font.pixelSize: root.fzRow
              font.bold: true
              wrapMode: Text.WordWrap
            }

            Text {
              width: parent.width
              text: "this system is not currently supported"
              textFormat: Text.PlainText
              color: root.dimFg
              font.family: root.contentFontFamily
              font.pixelSize: root.fzSmall
              wrapMode: Text.WordWrap
            }
          }

          // ── Sign in ─────────────────────────────────────────────────────
          Column {
            visible: vpn.installed && vpn.loggedOut && !vpn.connected
            width: parent.width
            spacing: Style.space(8)

            BlockButton {
              width: parent.width
              label: vpn.signingIn ? "signing in…" : "▶ sign in"
              primary: !vpn.signingIn
              enabled: !vpn.busy
              hasCursor: root.cursorActive && root.focusSection === "header"
              accessibleName: "Sign in to Windscribe"
              onActivated: vpn.signIn()
              onHoverFocus: root.focusHeader()
            }

            Text {
              width: parent.width
              text: "credentials stay in windscribe's terminal prompt"
              textFormat: Text.PlainText
              color: root.faintFg
              font.family: root.contentFontFamily
              font.pixelSize: root.fzMicro
            }
          }

          // ── Hero: destination, tunnel line, the one big action ──────────
          Column {
            visible: vpn.installed && (vpn.loggedIn || vpn.connected) && root.tab === "locations"
            width: parent.width
            spacing: Style.space(12)

            Column {
              width: parent.width
              spacing: Style.space(5)

              Text {
                width: parent.width
                text: root.heroCityText()
                textFormat: Text.PlainText
                color: vpn.connected ? root.fg : root.labelFg
                font.family: root.contentFontFamily
                font.pixelSize: root.fzCity
                font.bold: true
                font.letterSpacing: -0.3
                elide: Text.ElideRight
              }

              Item {
                width: parent.width
                implicitHeight: heroMeta.implicitHeight

                Text {
                  id: heroMeta
                  anchors.left: parent.left
                  anchors.right: tunnelLine.left
                  anchors.rightMargin: Style.space(10)
                  text: root.heroMetaText()
                  textFormat: Text.PlainText
                  color: root.dimFg
                  font.family: root.contentFontFamily
                  font.pixelSize: root.fzSmall
                  elide: Text.ElideRight
                }

                Text {
                  id: tunnelLine
                  anchors.right: parent.right
                  text: root.tunnelLineText()
                  textFormat: Text.PlainText
                  color: root.tunnelSettled && !vpn.tunnelTestPending ? root.accent : root.labelFg
                  font.family: root.contentFontFamily
                  font.pixelSize: root.fzSmall
                  font.letterSpacing: 0.3
                }
              }
            }

            BlockButton {
              id: connectButton
              width: parent.width
              label: root.connectLabel()
              primary: !vpn.active && !vpn.busy && !vpn.transitional
              accented: root.tunnelSettled
              enabled: !vpn.busy
              hasCursor: root.cursorActive && root.focusSection === "header"
              accessibleName: root.toggleHint
              onActivated: vpn.toggle()
              onHoverFocus: root.focusHeader()
            }

            // ── down / up / data ──────────────────────────────────────────
            Item {
              width: parent.width
              implicitHeight: Style.space(40)

              Rectangle {
                anchors.top: parent.top
                width: parent.width
                height: 1
                color: root.hairline
              }

              Rectangle {
                anchors.bottom: parent.bottom
                width: parent.width
                height: 1
                color: root.hairline
              }

              Row {
                anchors.fill: parent
                anchors.topMargin: 1
                anchors.bottomMargin: 1

                Repeater {
                  model: [
                    { label: "down", kind: "rx" },
                    { label: "up", kind: "tx" },
                    { label: "data", kind: "sum" }
                  ]

                  Item {
                    id: statCell
                    required property var modelData
                    required property int index
                    width: parent.width / 3
                    height: parent.height

                    Rectangle {
                      visible: statCell.index > 0
                      anchors.left: parent.left
                      width: 1
                      height: parent.height
                      color: root.hairline
                    }

                    Column {
                      anchors.left: parent.left
                      anchors.leftMargin: statCell.index > 0 ? Style.space(12) : Style.space(2)
                      anchors.verticalCenter: parent.verticalCenter
                      spacing: Style.space(3)

                      Text {
                        text: statCell.modelData.label
                        textFormat: Text.PlainText
                        color: root.dimFg
                        font.family: root.contentFontFamily
                        font.pixelSize: root.fzMicro
                        font.letterSpacing: 1
                      }

                      Text {
                        text: {
                          if (!vpn.connected) return "—"
                          if (statCell.modelData.kind === "rx") return Model.formatRate(vpn.rxRate)
                          if (statCell.modelData.kind === "tx") return Model.formatRate(vpn.txRate)
                          return Model.formatBytes(vpn.sessionRx + vpn.sessionTx)
                        }
                        textFormat: Text.PlainText
                        color: vpn.connected ? root.valueFg : root.faintFg
                        font.family: root.contentFontFamily
                        font.pixelSize: root.fzRow
                        font.bold: true
                      }
                    }
                  }
                }
              }
            }

            // ── Live traffic wave: 44 bars from the kernel counters ──────
            Item {
              width: parent.width
              implicitHeight: Style.space(16)
              Accessible.role: Accessible.StaticText
              Accessible.name: vpn.connected ? "Live traffic activity" : "No tunnel activity"

              Row {
                id: waveRow
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                spacing: Style.space(2)
                readonly property real barWidth:
                  (width - spacing * 43) / 44

                Repeater {
                  model: 44

                  Rectangle {
                    id: waveBar
                    required property int index
                    readonly property real level: vpn.connected ? root.waveLevels[index] : 0
                    width: waveRow.barWidth
                    anchors.bottom: parent.bottom
                    height: Style.space(2) + level * Style.space(14)
                    color: !vpn.connected
                      ? root.hairline
                      : (level > 0.5 ? root.accent : root.accentDim)

                    Behavior on height {
                      enabled: root.motionOn
                      NumberAnimation { duration: 300; easing.type: Easing.OutCubic }
                    }
                  }
                }
              }
            }
          }

          // ── Status / errors / recovery ──────────────────────────────────
          Text {
            visible: vpn.lastError !== ""
            width: parent.width
            text: vpn.lastError
            textFormat: Text.PlainText
            color: root.urgentFg
            font.family: root.contentFontFamily
            font.pixelSize: root.fzSmall
            wrapMode: Text.WordWrap
          }

          Row {
            id: recoveryRow
            visible: root.recoveryVisible
            spacing: Style.space(14)

            BracketAction {
              label: "retry"
              tone: root.accent
              enabled: !vpn.busy
              hasCursor: root.cursorActive && root.focusSection === "recovery" && root.recoveryIndex === 0
              accessibleName: "Retry connection"
              onActivated: {
                root.recoveryIndex = 0
                root.activateRecovery()
              }
              onHoverFocus: root.focusRecovery(0)
            }

            BracketAction {
              label: "change protocol"
              tone: root.labelFg
              hasCursor: root.cursorActive && root.focusSection === "recovery" && root.recoveryIndex === 1
              accessibleName: "Change protocol"
              onActivated: {
                root.recoveryIndex = 1
                root.activateRecovery()
              }
              onHoverFocus: root.focusRecovery(1)
            }
          }

          // ── Search ──────────────────────────────────────────────────────
          Item {
            visible: vpn.installed && vpn.loggedIn && root.tab === "locations"
            width: parent.width
            implicitHeight: Style.space(30)

            Rectangle {
              anchors.top: parent.top
              width: parent.width
              height: 1
              color: root.hairline
            }

            Text {
              id: searchSigil
              anchors.left: parent.left
              anchors.verticalCenter: parent.verticalCenter
              anchors.verticalCenterOffset: 1
              text: "/"
              textFormat: Text.PlainText
              color: root.accent
              font.family: root.contentFontFamily
              font.pixelSize: root.fzMeta
              font.bold: true
            }

            TextInput {
              id: searchField
              anchors.left: searchSigil.right
              anchors.leftMargin: Style.space(9)
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              anchors.verticalCenterOffset: 1
              color: root.fg
              font.family: root.contentFontFamily
              font.pixelSize: root.fzRow
              clip: true
              selectByMouse: true
              Accessible.role: Accessible.EditableText
              Accessible.name: "Search locations"
              onTextChanged: {
                root.locationQuery = text
                root.locationIndex = 0
              }
              onAccepted: {
                if (root.visibleEntries.length > 0)
                  root.activateEntry(root.visibleEntries[root.locationIndex])
                root.focusLocation(root.locationIndex)
              }
              Keys.onDownPressed: function(event) {
                // The first Down enters the list on the current match; only
                // later ones advance it.
                var step = root.focusSection === "locations" ? 1 : 0
                root.focusLocation(Math.min(root.locationIndex + step,
                  Math.max(0, root.visibleEntries.length - 1)))
                event.accepted = true
              }
              Keys.onUpPressed: function(event) {
                root.focusLocation(Math.max(0, root.locationIndex - 1))
                event.accepted = true
              }
              Keys.onEscapePressed: {
                text = ""
                root.focusHeader()
              }

              Text {
                visible: searchField.text === ""
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                text: "search all exits…"
                textFormat: Text.PlainText
                color: root.dimFg
                font.family: root.contentFontFamily
                font.pixelSize: root.fzRow
              }
            }

            MouseArea {
              anchors.fill: parent
              cursorShape: Qt.IBeamCursor
              acceptedButtons: Qt.NoButton
            }
          }

          // ── Locations ───────────────────────────────────────────────────
          Column {
            visible: vpn.installed && vpn.loggedIn && root.tab === "locations"
            width: parent.width
            spacing: Style.space(6)

            Text {
              visible: vpn.loadingLocations
              width: parent.width
              text: "loading exits…"
              textFormat: Text.PlainText
              color: root.dimFg
              font.family: root.contentFontFamily
              font.pixelSize: root.fzSmall
            }

            Text {
              visible: vpn.locationsUnavailable && !vpn.cliOnlyBuild
              width: parent.width
              text: "type a city, region, country code, or nickname"
              textFormat: Text.PlainText
              color: root.dimFg
              font.family: root.contentFontFamily
              font.pixelSize: root.fzSmall
              wrapMode: Text.WordWrap
            }

            Text {
              visible: !vpn.loadingLocations && root.visibleEntries.length === 0
              width: parent.width
              text: root.locationQuery === "" ? "no exits available" : "no exits match"
              textFormat: Text.PlainText
              color: root.dimFg
              font.family: root.contentFontFamily
              font.pixelSize: root.fzSmall
            }

            ListView {
              id: locationList
              visible: root.visibleEntries.length > 0
              width: parent.width
              height: Math.min(contentHeight, Style.space(272))
              clip: true
              spacing: 0
              model: root.visibleEntries
              currentIndex: root.locationIndex
              boundsBehavior: Flickable.StopAtBounds
              ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

              WheelHandler {
                target: null
                acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
                onWheel: function(event) {
                  var dy = event.pixelDelta.y !== 0
                    ? event.pixelDelta.y
                    : (event.angleDelta.y / 120) * Style.space(56)
                  locationList.contentY = Math.max(
                    0,
                    Math.min(locationList.contentHeight - locationList.height, locationList.contentY - dy)
                  )
                  event.accepted = true
                }
              }

              delegate: CursorSurface {
                id: locationRow
                required property var modelData
                required property int index
                width: locationList.width
                implicitHeight: Style.space(26)
                foreground: root.fg
                hasCursor: root.cursorActive && root.focusSection === "locations" && root.locationIndex === index
                Accessible.role: Accessible.Button
                Accessible.name: (root.entryCurrent(modelData) ? "Current location. " : "")
                  + root.entryTitle(modelData) + ". " + root.entrySubtitle(modelData)
                Accessible.focusable: true
                Accessible.focused: hasCursor
                Accessible.onPressAction: if (!vpn.busy) root.activateEntry(modelData)

                MouseArea {
                  anchors.fill: parent
                  anchors.rightMargin: favoriteStar.width + Style.space(6)
                  hoverEnabled: true
                  cursorShape: vpn.busy ? Qt.ArrowCursor : Qt.PointingHandCursor
                  enabled: !vpn.busy
                  onEntered: root.focusLocation(locationRow.index)
                  onClicked: root.activateEntry(locationRow.modelData)
                }

                Text {
                  id: rowIndex
                  anchors.left: parent.left
                  anchors.leftMargin: Style.space(2)
                  anchors.verticalCenter: parent.verticalCenter
                  width: Style.space(20)
                  text: root.rowIndexLabel(locationRow.index)
                  textFormat: Text.PlainText
                  color: root.faintFg
                  font.family: root.contentFontFamily
                  font.pixelSize: root.fzSmall
                }

                Text {
                  id: rowSlug
                  anchors.left: rowIndex.right
                  anchors.verticalCenter: parent.verticalCenter
                  width: Math.min(implicitWidth, parent.width - rowIndex.width - rowRight.width - Style.space(20))
                  text: root.entrySlug(locationRow.modelData)
                  textFormat: Text.PlainText
                  color: root.entryCurrent(locationRow.modelData)
                    ? root.accent
                    : (locationRow.modelData.kind === "best"
                        || (root.entryStarable(locationRow.modelData)
                            && root.isFavorite(root.entryTarget(locationRow.modelData)))
                        ? root.fg
                        : root.rowFg)
                  font.family: root.contentFontFamily
                  font.pixelSize: root.fzRow
                  font.bold: locationRow.modelData.kind === "best"
                    || root.entryCurrent(locationRow.modelData)
                    || (root.entryStarable(locationRow.modelData)
                        && root.isFavorite(root.entryTarget(locationRow.modelData)))
                  elide: Text.ElideRight
                }

                Text {
                  anchors.left: rowSlug.right
                  anchors.leftMargin: Style.space(8)
                  anchors.right: rowRight.left
                  anchors.rightMargin: Style.space(8)
                  anchors.verticalCenter: parent.verticalCenter
                  text: root.entryMeta(locationRow.modelData)
                  textFormat: Text.PlainText
                  color: root.faintFg
                  font.family: root.contentFontFamily
                  font.pixelSize: root.fzSmall
                  elide: Text.ElideRight
                }

                Row {
                  id: rowRight
                  anchors.right: parent.right
                  anchors.verticalCenter: parent.verticalCenter
                  spacing: Style.space(7)

                  Text {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: text !== ""
                    text: root.entryBadge(locationRow.modelData)
                    textFormat: Text.PlainText
                    color: locationRow.modelData.kind === "best" || locationRow.modelData.tenGbps
                      ? root.accent
                      : root.dimFg
                    font.family: root.contentFontFamily
                    font.pixelSize: root.fzSmall
                  }

                  Text {
                    id: favoriteStar
                    anchors.verticalCenter: parent.verticalCenter
                    width: Style.space(14)
                    horizontalAlignment: Text.AlignHCenter
                    text: locationRow.modelData.kind === "best"
                      ? " "
                      : (root.isFavorite(root.entryTarget(locationRow.modelData)) ? "*" : "·")
                    textFormat: Text.PlainText
                    color: root.entryStarable(locationRow.modelData)
                        && root.isFavorite(root.entryTarget(locationRow.modelData))
                      ? root.accent
                      : root.faintFg
                    font.family: root.contentFontFamily
                    font.pixelSize: root.fzRow
                    font.bold: true
                    Accessible.role: Accessible.Button
                    Accessible.ignored: !root.entryStarable(locationRow.modelData)
                    Accessible.focusable: root.entryStarable(locationRow.modelData)
                    Accessible.focused: false
                    Accessible.name: root.entryStarable(locationRow.modelData)
                      ? (root.isFavorite(root.entryTarget(locationRow.modelData))
                          ? "Remove from Favourites"
                          : "Add to Favourites")
                      : ""
                    Accessible.onPressAction: {
                      if (root.entryStarable(locationRow.modelData))
                        root.toggleFavorite(root.entryTarget(locationRow.modelData))
                    }

                    MouseArea {
                      anchors.fill: parent
                      anchors.margins: -Style.space(4)
                      enabled: root.entryStarable(locationRow.modelData)
                      hoverEnabled: true
                      cursorShape: Qt.PointingHandCursor
                      onEntered: root.focusLocation(locationRow.index)
                      onClicked: root.toggleFavorite(root.entryTarget(locationRow.modelData))
                    }
                  }
                }
              }
            }
          }

          // ── Settings ────────────────────────────────────────────────────
          Column {
            visible: vpn.installed && vpn.loggedIn && root.tab === "connection"
            width: parent.width
            spacing: Style.space(4)

            SectionLabel { text: "connection" }

            SettingRow {
              id: firewallControl
              width: parent.width
              label: "firewall"
              valueText: vpn.firewall === ""
                ? "[ … ]"
                : (vpn.firewallLocked ? "[ always ]" : (vpn.firewallOn ? "[ on ]" : "[ off ]"))
              valueColor: vpn.firewallOn ? root.accent : root.dimFg
              valueBold: true
              interactive: !vpn.firewallLocked && !vpn.busy
              hasCursor: root.connectionHasCursor("firewall")
              accessibleRole: Accessible.CheckBox
              accessibleName: "Firewall"
              accessibleChecked: vpn.firewallOn
              onRowClicked: if (!vpn.firewallLocked) vpn.setFirewall(!vpn.firewallOn)
              onRowHovered: root.focusConnectionKey("firewall")
            }

            DropdownRow {
              id: protocolPicker
              width: parent.width
              key: "protocol"
              label: "preferred protocol"
              valueText: root.protocolValueText()
              options: root.protocolOptions
              currentValue: root.selectedProtocolBase
            }

            DropdownRow {
              id: portPicker
              visible: root.selectedProtocolBase !== ""
              width: parent.width
              key: "port"
              label: vpn.loadingPorts ? "port · loading…" : "port"
              valueText: root.portValueText()
              options: root.portOptions
              currentValue: root.selectedProtocolPort
            }

            SettingRow {
              id: alertsControl
              width: parent.width
              label: "connection alerts"
              valueText: vpn.notificationsOn ? "[ on ]" : "[ off ]"
              valueColor: vpn.notificationsOn ? root.accent : root.dimFg
              valueBold: true
              hasCursor: root.connectionHasCursor("notifications")
              accessibleRole: Accessible.CheckBox
              accessibleName: "Connection alerts"
              accessibleChecked: vpn.notificationsOn
              onRowClicked: root.persistSetting("notifications", !vpn.notificationsOn)
              onRowHovered: root.focusConnectionKey("notifications")
            }

            SettingRow {
              id: motionControl
              width: parent.width
              label: "interface motion"
              valueText: root.motionOn ? "[ on ]" : "[ off ]"
              valueColor: root.motionOn ? root.accent : root.dimFg
              valueBold: true
              hasCursor: root.connectionHasCursor("motion")
              accessibleRole: Accessible.CheckBox
              accessibleName: "Interface motion"
              accessibleChecked: root.motionOn
              onRowClicked: root.persistSetting("motion", !root.motionOn)
              onRowHovered: root.focusConnectionKey("motion")
            }

            Text {
              width: parent.width
              topPadding: Style.space(4)
              text: "protocol & port apply on next connect"
              textFormat: Text.PlainText
              color: root.faintFg
              font.family: root.contentFontFamily
              font.pixelSize: root.fzMicro
            }

            SectionLabel {
              text: "general"
              topPadding: Style.space(14)
            }

            SettingRow {
              width: parent.width
              label: "appearance"
              valueText: "omarchy theme"
              valueColor: root.valueFg
              interactive: false
              accessibleName: "Appearance follows the Omarchy theme"
            }

            SettingRow {
              visible: vpn.dataUsage !== ""
              width: parent.width
              label: "data allowance"
              valueText: vpn.markupSafeText(vpn.dataUsage).toLowerCase()
              valueColor: !vpn.usage.unlimited && vpn.usage.fraction > 0.9
                ? root.urgentFg
                : root.valueFg
              interactive: false
              accessibleName: "Data allowance " + vpn.markupSafeText(vpn.dataUsage)
            }

            SettingRow {
              id: rotateAction
              visible: vpn.connected && vpn.ipIsVpn
              width: parent.width
              label: "rotate ip"
              valueText: vpn.pendingLabel === "Rotating IP…" ? "[ rotating… ]" : "[ rotate ]"
              valueColor: root.rowFg
              valueBold: true
              interactive: !vpn.busy
              hasCursor: root.connectionHasCursor("rotate")
              accessibleName: "Rotate IP"
              onRowClicked: vpn.rotateIp()
              onRowHovered: root.focusConnectionKey("rotate")
            }

            SettingRow {
              id: updateAction
              visible: vpn.updateAvailable !== ""
              width: parent.width
              label: "update available"
              valueText: vpn.updating
                ? "[ updating… ]"
                : "[ " + vpn.markupSafeText(vpn.updateAvailable).toLowerCase() + " ]"
              valueColor: root.accent
              valueBold: true
              interactive: !vpn.busy
              hasCursor: root.connectionHasCursor("update")
              accessibleName: "Update Windscribe to " + vpn.markupSafeText(vpn.updateAvailable)
              onRowClicked: vpn.updateCli()
              onRowHovered: root.focusConnectionKey("update")
            }

            SettingRow {
              width: parent.width
              label: "account"
              valueText: vpn.loginState === "" ? "checking" : root.lcText(vpn.loginState)
              valueColor: root.valueFg
              interactive: false
              accessibleName: "Account " + vpn.markupSafeText(vpn.loginState)
            }

            SettingRow {
              id: signOutAction
              width: parent.width
              label: "sign out"
              valueText: root.signOutArmed ? "[ confirm ]" : "[ sign out ]"
              valueColor: root.signOutArmed ? root.urgentFg : root.rowFg
              valueBold: true
              interactive: !vpn.busy
              hasCursor: root.connectionHasCursor("signout")
              accessibleName: root.signOutArmed ? "Confirm sign out" : "Sign out"
              onRowClicked: {
                root.focusConnectionKey("signout")
                root.activateConnection()
              }
              onRowHovered: root.focusConnectionKey("signout")
            }

            Text {
              width: parent.width
              topPadding: Style.space(4)
              text: vpn.firewallOn ? "sign-out keeps the firewall up" : " "
              textFormat: Text.PlainText
              color: root.faintFg
              font.family: root.contentFontFamily
              font.pixelSize: root.fzMicro
            }
          }

          // ── Footer keys ─────────────────────────────────────────────────
          Item {
            visible: vpn.installed && vpn.loggedIn
            width: parent.width
            implicitHeight: Style.space(24)

            Rectangle {
              anchors.top: parent.top
              width: parent.width
              height: 1
              color: root.hairline
            }

            Row {
              anchors.left: parent.left
              anchors.verticalCenter: parent.verticalCenter
              anchors.verticalCenterOffset: 2
              spacing: Style.space(14)

              KeyHint { hint: root.tab === "locations" ? "↵ connect" : "↑↓ move" }
              KeyHint { hint: root.tab === "locations" ? "f favourite" : "↵ change" }
              KeyHint {
                visible: root.tab === "locations"
                hint: "/ search"
                clickable: true
                onActivated: {
                  root.setTab("locations")
                  Qt.callLater(root.focusSearch)
                }
              }
              KeyHint {
                hint: root.tab === "locations" ? "s settings" : "s back"
                clickable: true
                onActivated: root.cycleTab(1)
              }
              KeyHint { hint: root.tab === "locations" ? "esc close" : "esc back" }
            }
          }
        }
      }
    }
  }

  // A 1px dashed or dotted rule — the design's leader lines. Drawn with
  // fillRect segments because Context2D's setLineDash is unreliable.
  component Leader: Canvas {
    id: leader
    property color lineColor: root.leaderLine
    property bool dotted: false
    height: 1
    onPaint: {
      var ctx = getContext("2d")
      ctx.clearRect(0, 0, width, height)
      ctx.fillStyle = String(leader.lineColor)
      var dash = leader.dotted ? 1 : 3
      var gap = 3
      for (var x = 0; x < width; x += dash + gap)
        ctx.fillRect(x, 0, Math.min(dash, width - x), 1)
    }
    onWidthChanged: requestPaint()
    onLineColorChanged: requestPaint()
    onDottedChanged: requestPaint()
  }

  // The one big action. Filled with the foreground when it is the primary
  // move; a quiet accent outline while the tunnel is up.
  component BlockButton: Rectangle {
    id: block
    property string label: ""
    property bool primary: false
    property bool accented: false
    property bool hasCursor: false
    property string accessibleName: label
    signal activated()
    signal hoverFocus()

    implicitHeight: Style.space(38)
    radius: 0
    color: block.primary && block.enabled ? root.fg : "transparent"
    border.width: 1
    border.color: {
      if (block.primary && block.enabled) return root.fg
      if (block.accented) return block.hasCursor || blockArea.containsMouse ? root.accent : root.accentDim
      return block.hasCursor || blockArea.containsMouse ? root.labelFg : root.leaderLine
    }
    opacity: enabled ? 1.0 : 0.85
    Accessible.role: Accessible.Button
    Accessible.name: accessibleName
    Accessible.focusable: true
    Accessible.focused: hasCursor
    Accessible.onPressAction: if (block.enabled) block.activated()

    Text {
      anchors.centerIn: parent
      text: block.label
      textFormat: Text.PlainText
      color: block.primary && block.enabled
        ? root.inverseFg
        : (block.accented ? root.accent : root.labelFg)
      font.family: root.contentFontFamily
      font.pixelSize: root.fzMeta
      font.bold: true
      font.letterSpacing: 2
    }

    MouseArea {
      id: blockArea
      anchors.fill: parent
      hoverEnabled: true
      enabled: block.enabled
      cursorShape: block.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
      onEntered: block.hoverFocus()
      onClicked: block.activated()
    }
  }

  // "[ retry ]"-style inline action.
  component BracketAction: CursorSurface {
    id: bracket
    property string label: ""
    property color tone: root.rowFg
    property string accessibleName: label
    signal activated()
    signal hoverFocus()

    foreground: root.fg
    implicitWidth: bracketText.implicitWidth + Style.space(8)
    implicitHeight: Style.space(22)
    opacity: enabled ? 1.0 : 0.6
    Accessible.role: Accessible.Button
    Accessible.name: accessibleName
    Accessible.focusable: true
    Accessible.focused: hasCursor
    Accessible.onPressAction: if (bracket.enabled) bracket.activated()

    Text {
      id: bracketText
      anchors.centerIn: parent
      text: "[ " + bracket.label + " ]"
      textFormat: Text.PlainText
      color: bracket.tone
      font.family: root.contentFontFamily
      font.pixelSize: root.fzMeta
      font.bold: true
    }

    MouseArea {
      anchors.fill: parent
      hoverEnabled: true
      enabled: bracket.enabled
      cursorShape: bracket.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
      onEntered: bracket.hoverFocus()
      onClicked: bracket.activated()
    }
  }

  component SectionLabel: Text {
    textFormat: Text.PlainText
    color: root.faintFg
    font.family: root.contentFontFamily
    font.pixelSize: root.fzMicro
    font.letterSpacing: 1.5
    bottomPadding: Style.space(4)
  }

  // label ····· value — the settings grammar. Toggles and actions render
  // their state as "[ on ]" bracket text.
  component SettingRow: CursorSurface {
    id: srow
    property string label: ""
    property string valueText: ""
    property color valueColor: root.valueFg
    property bool valueBold: false
    property bool interactive: true
    property int accessibleRole: Accessible.Button
    property string accessibleName: label
    property bool accessibleChecked: false
    signal rowClicked()
    signal rowHovered()

    foreground: root.fg
    implicitHeight: Style.space(26)
    Accessible.role: interactive ? accessibleRole : Accessible.StaticText
    Accessible.name: accessibleName
    Accessible.checkable: accessibleRole === Accessible.CheckBox
    Accessible.checked: accessibleChecked
    Accessible.focusable: interactive
    Accessible.focused: hasCursor
    Accessible.onPressAction: if (srow.interactive) srow.rowClicked()
    Accessible.onToggleAction: if (srow.interactive) srow.rowClicked()

    MouseArea {
      anchors.fill: parent
      hoverEnabled: true
      enabled: srow.interactive
      cursorShape: srow.interactive ? Qt.PointingHandCursor : Qt.ArrowCursor
      onEntered: srow.rowHovered()
      // A click anywhere else while a menu is open dismisses it first.
      onClicked: {
        if (root.ddOpen !== "") root.ddOpen = ""
        else srow.rowClicked()
      }
    }

    Text {
      id: srowLabel
      anchors.left: parent.left
      anchors.verticalCenter: parent.verticalCenter
      text: srow.label
      textFormat: Text.PlainText
      color: root.labelFg
      font.family: root.contentFontFamily
      font.pixelSize: root.fzMeta
    }

    Leader {
      anchors.left: srowLabel.right
      anchors.leftMargin: Style.space(9)
      anchors.right: srowValue.left
      anchors.rightMargin: Style.space(9)
      anchors.verticalCenter: parent.verticalCenter
      dotted: true
      lineColor: root.hairline
    }

    Text {
      id: srowValue
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      text: srow.valueText
      textFormat: Text.PlainText
      color: srow.valueColor
      font.family: root.contentFontFamily
      font.pixelSize: root.fzMeta
      font.bold: srow.valueBold
    }
  }

  // A SettingRow with an in-panel dropdown menu, keyboard first.
  component DropdownRow: Item {
    id: dd
    property string key: ""
    property string label: ""
    property string valueText: ""
    property var options: []
    property string currentValue: ""
    readonly property bool popupOpen: root.ddOpen === dd.key

    // The open menu takes part in layout, so the panel grows around it and
    // nothing below it is overpainted or clipped.
    implicitHeight: ddRow.implicitHeight + (popupOpen ? ddPopup.height + Style.space(2) : 0)
    z: popupOpen ? 20 : 0

    SettingRow {
      id: ddRow
      width: dd.width
      label: dd.label
      valueText: dd.valueText + " ▾"
      valueColor: root.valueFg
      interactive: true
      hasCursor: root.connectionHasCursor(dd.key)
      accessibleName: dd.label + ". " + dd.valueText
      onRowClicked: root.toggleDropdown(dd.key)
      onRowHovered: root.focusConnectionKey(dd.key)
    }

    Rectangle {
      id: ddPopup
      visible: dd.popupOpen
      anchors.right: parent.right
      y: ddRow.height + Style.space(2)
      width: Style.space(170)
      implicitHeight: ddColumn.implicitHeight + Style.space(8)
      color: root.inverseFg
      border.width: 1
      border.color: root.leaderLine
      radius: 0

      Column {
        id: ddColumn
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.topMargin: Style.space(4)

        Repeater {
          model: dd.options

          Item {
            id: ddOption
            required property var modelData
            required property int index
            readonly property bool selected: modelData.value === dd.currentValue
            width: ddColumn.width
            implicitHeight: Style.space(22)
            Accessible.role: Accessible.ListItem
            Accessible.name: modelData.label
            Accessible.selected: selected
            Accessible.focusable: true
            Accessible.onPressAction: root.pickDropdown(ddOption.modelData.value)

            Rectangle {
              anchors.fill: parent
              color: root.ddIndex === ddOption.index || ddOptionArea.containsMouse
                ? Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.08)
                : "transparent"
            }

            Text {
              anchors.left: parent.left
              anchors.leftMargin: Style.space(10)
              anchors.verticalCenter: parent.verticalCenter
              text: ddOption.modelData.label
              textFormat: Text.PlainText
              color: ddOption.selected ? root.fg : root.labelFg
              font.family: root.contentFontFamily
              font.pixelSize: root.fzMeta
              font.bold: ddOption.selected
            }

            Text {
              visible: ddOption.selected
              anchors.right: parent.right
              anchors.rightMargin: Style.space(10)
              anchors.verticalCenter: parent.verticalCenter
              text: "«"
              textFormat: Text.PlainText
              color: root.accent
              font.family: root.contentFontFamily
              font.pixelSize: root.fzMeta
              font.bold: true
            }

            MouseArea {
              id: ddOptionArea
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onEntered: root.ddIndex = ddOption.index
              onClicked: root.pickDropdown(ddOption.modelData.value)
            }
          }
        }
      }
    }
  }

  component KeyHint: Text {
    id: hintText
    property string hint: ""
    property bool clickable: false
    signal activated()

    text: hint
    textFormat: Text.PlainText
    color: clickable && hintArea.containsMouse ? root.labelFg : root.faintFg
    font.family: root.contentFontFamily
    font.pixelSize: root.fzMicro
    Accessible.role: clickable ? Accessible.Button : Accessible.StaticText
    Accessible.name: hint
    Accessible.focusable: clickable
    Accessible.onPressAction: if (hintText.clickable) hintText.activated()

    MouseArea {
      id: hintArea
      anchors.fill: parent
      anchors.margins: -Style.space(3)
      hoverEnabled: hintText.clickable
      enabled: hintText.clickable
      cursorShape: hintText.clickable ? Qt.PointingHandCursor : Qt.ArrowCursor
      onClicked: hintText.activated()
    }
  }
}
