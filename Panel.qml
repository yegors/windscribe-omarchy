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

  readonly property var barIdentity: hostWidget || root
  readonly property color contentForeground: bar ? bar.foreground : Color.foreground
  readonly property color dimForeground: Qt.darker(contentForeground, 1.5)
  readonly property color urgentForeground: bar ? bar.urgent : Color.urgent
  readonly property string contentFontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property string toggleHint: vpn.active ? "Disconnect Windscribe" : "Connect Windscribe"
  readonly property var visibleEntries: buildEntries()
  readonly property var quickEntries: buildQuickEntries()
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
  readonly property string currentLocationText: locationDisplay(vpn.city)
  readonly property string instrumentProtocol: vpn.protocol !== ""
    ? vpn.markupSafeText(vpn.protocol)
    : Model.protocolLabel((settings && settings.preferredProtocol) || "")
  readonly property var protocolOptions: [
    { value: "", label: "Automatic", description: "Let Windscribe choose" },
    { value: "wireguard", label: "WireGuard", description: "Fast, modern, post-quantum capable" },
    { value: "udp", label: "UDP", description: "Fast OpenVPN transport" },
    { value: "tcp", label: "TCP", description: "Reliable OpenVPN transport" },
    { value: "stealth", label: "Stealth", description: "For restrictive networks" },
    { value: "wstunnel", label: "WStunnel", description: "WebSocket tunnel for restrictive networks" }
  ]

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
    focusSection = "header"
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

  function locationByTarget(value) {
    var target = String(value || "").toLowerCase()
    var available = vpn.locations || []
    for (var i = 0; i < available.length; i++) {
      if (String(available[i].nickname).toLowerCase() === target
          || String(available[i].city).toLowerCase() === target) return available[i]
    }
    return null
  }

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

  function locationDisplay(value) {
    var raw = String(value || "")
    return raw === "" ? "" : vpn.markupSafeText(raw)
  }

  function buildQuickEntries() {
    var out = [{ kind: "best", title: "Best Location", target: "" }]
    for (var i = 0; i < vpn.recents.length && out.length < 3; i++) {
      var recent = vpn.recents[i]
      if (!recent || !recent.city) continue
      var resolved = locationByTarget(recent.city)
      out.push({
        kind: "recent",
        title: resolved ? (resolved.nickname || resolved.city) : String(recent.city),
        target: String(recent.city),
        city: resolved ? resolved.city : String(recent.city)
      })
    }
    return out
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
    var out = [{ value: "", label: "Automatic", description: "Windscribe’s default port" }]
    var seen = ({})
    var ports = vpn.portsProtocol === selectedProtocolBase ? vpn.availablePorts : []
    for (var i = 0; i < ports.length; i++) {
      var value = String(ports[i])
      if (seen[value]) continue
      seen[value] = true
      out.push({ value: value, label: value, description: "Port " + value })
    }
    if (selectedProtocolPort !== "" && !seen[selectedProtocolPort])
      out.push({ value: selectedProtocolPort, label: selectedProtocolPort, description: "Current port" })
    return out
  }

  function buildEntries() {
    var query = String(locationQuery || "").trim().toLowerCase()
    var out = []
    var seen = ({})

    var bestMatches = query === ""
      || "best location".indexOf(query) === 0
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

    if (query === "") {
      for (var r = 0; r < vpn.recents.length; r++) {
        var recent = vpn.recents[r]
        if (!recent || !recent.city || seen[targetKey(recent.city)]) continue
        var recentEntry = entryForTarget(recent.city, "recent")
        out.push(recentEntry)
        seen[entryKey(recentEntry)] = true
        seen[targetKey(recent.city)] = true
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

  function entryTitle(entry) {
    if (entry.kind === "best") return "Best Location"
    if (entry.kind === "custom") return "Connect to “" + vpn.markupSafeText(entry.city) + "”"
    return vpn.markupSafeText(entry.city)
  }

  function entrySubtitle(entry) {
    if (entry.kind === "best") return "Windscribe’s lowest-latency choice"
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
    var current = String(vpn.city || "").toLowerCase()
    return current !== "" && entry.city !== ""
      && String(entry.city).toLowerCase() === current
  }

  function activateEntry(entry) {
    if (entry.kind === "best") vpn.connectBest()
    else vpn.connectTo(entryTarget(entry))
  }

  function persistSetting(key, value) {
    if (!root.bar || !root.bar.shell || typeof root.bar.shell.updateEntryInline !== "function") return
    var entry = { id: root.moduleName }
    for (var existing in settings) if (existing !== "id") entry[existing] = settings[existing]
    entry[key] = value
    root.bar.shell.updateEntryInline(root.moduleName, entry)
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

  function moveCursor(direction) {
    cursorActive = true
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
    if (visibleEntries.length === 0) {
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
    if (connectionEntries.length === 0 || vpn.busy) return
    var key = focusedConnectionKey
    if (key === "firewall") vpn.setFirewall(!vpn.firewallOn)
    else if (key === "protocol") protocolPicker.open()
    else if (key === "port") portPicker.open()
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
      if (vpn.city !== "") vpn.connectTo(vpn.city)
      else vpn.connect()
    } else {
      setTab("connection")
      focusConnectionKey("protocol")
    }
  }

  function activateCursor() {
    if (focusSection === "locations" && tab === "locations" && visibleEntries.length > 0) {
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

  function focusSearch() {
    searchField.forceActiveFocus()
    searchField.selectAll()
  }

  function maxScroll() {
    return Math.max(0, panelFlick.contentHeight - panelFlick.height)
  }

  onSettingsChanged: syncFavoriteLocations()
  onSelectedProtocolBaseChanged: {
    if (protocolPicker) protocolPicker.value = selectedProtocolBase
    if (selectedProtocolBase !== "") vpn.refreshPorts(selectedProtocolBase)
  }
  onSelectedProtocolPortChanged: if (portPicker) portPicker.value = selectedProtocolPort
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
    panelOwnerId = vpn.registerPanelOwner()
  }
  Component.onDestruction: vpn.setPanelOwnerOpen(panelOwnerId, false)

  onOpenedChanged: {
    vpn.setPanelOwnerOpen(panelOwnerId, opened)
    if (opened) {
      tab = "locations"
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

  Component {
    id: vpnIcon
    WindscribeCore.WindscribeIcon {
      iconSize: Style.font.display
      color: root.contentForeground
      opacity: vpn.active ? 1.0 : 0.6
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.barIdentity
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(440))
    contentHeight: panel.fittedContentHeight(panelColumn.implicitHeight, Style.space(700))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      blocked: searchField.activeFocus || protocolPicker.popupOpen || portPicker.popupOpen
      onMoveRequested: function(dx, dy) {
        if (dy !== 0) root.moveCursor(dy)
        else if (dx !== 0) root.cycleTab(dx)
      }
      onActivateRequested: root.activateCursor()
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onTextKey: function(text) {
        if (text === "t" || text === "T") vpn.toggle()
        else if (text === "r" || text === "R") {
          vpn.refresh()
          vpn.refreshLocations()
        } else if (text === "w" || text === "W") {
          vpn.setFirewall(!vpn.firewallOn)
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

          Item {
            id: heroContainer
            width: parent.width
            implicitHeight: hero.implicitHeight

            PanelHero {
              id: hero
              width: parent.width
              iconComponent: vpnIcon
              title: "Windscribe"
              meta: ""
              foreground: root.contentForeground
              fontFamily: root.contentFontFamily

              trailingControl: Component {
                ToggleSwitch {
                  id: powerSwitch
                  // A live tunnel is enough to show the switch: you can
                  // always disconnect, even before sign-in state is known.
                  visible: vpn.installed && (vpn.loggedIn || vpn.connected)
                  checked: vpn.active
                  busy: vpn.busy
                  hasCursor: root.cursorActive && root.focusSection === "header"
                  foreground: hero.foreground
                  Accessible.role: Accessible.CheckBox
                  Accessible.name: root.toggleHint
                  Accessible.checkable: true
                  Accessible.checked: checked
                  Accessible.onPressAction: if (!vpn.busy) vpn.toggle()
                  Accessible.onToggleAction: if (!vpn.busy) vpn.toggle()
                  onHovered: function(on) { if (on) root.focusHeader() }
                  onToggled: vpn.toggle()

                  PanelToolTip {
                    visible: powerSwitch.containsMouse
                    text: root.toggleHint
                    fontFamily: hero.fontFamily
                  }
                }
              }
            }
          }

          // ── Live tunnel instrument ──────────────────────────────────────
          WindscribeCore.TunnelInstrument {
            visible: vpn.installed && (vpn.loggedIn || vpn.connected)
            width: parent.width
            active: vpn.active
            connected: vpn.connected
            busy: vpn.busy
            tunnelChanging: vpn.transitional || vpn.desiredState !== -1
            firewallOn: vpn.firewallOn
            firewallText: vpn.firewall === "" ? "Checking" : vpn.markupSafeText(vpn.firewall)
            tunnelTestPending: vpn.tunnelTestPending
            networkInterference: vpn.networkInterference
            motionEnabled: root.motionOn
            presentationActive: root.opened
            stateText: vpn.statusText
            locationText: root.currentLocationText
            protocolText: root.instrumentProtocol
            ipAddress: vpn.markupSafeText(vpn.ipAddress)
            ipIsVpn: vpn.ipIsVpn
            rxHistory: vpn.rxHistory
            txHistory: vpn.txHistory
            rxRate: vpn.rxRate
            txRate: vpn.txRate
            sessionRx: vpn.sessionRx
            sessionTx: vpn.sessionTx
            uptimeSec: vpn.uptimeSec
            foreground: root.contentForeground
            accent: Color.accent
            urgent: root.urgentForeground
            fontFamily: root.contentFontFamily
            onRotateRequested: vpn.rotateIp()
          }

          Text {
            visible: vpn.actionStatus !== "" || vpn.lastError !== ""
            width: parent.width
            text: vpn.actionStatus !== "" ? vpn.actionStatus : vpn.lastError
            textFormat: Text.PlainText
            color: vpn.lastError !== "" && vpn.actionStatus === "" ? root.urgentForeground : root.dimForeground
            font.family: root.contentFontFamily
            font.pixelSize: Style.font.bodySmall
            wrapMode: Text.WordWrap
          }

          Row {
            id: recoveryRow
            visible: root.recoveryVisible
            spacing: Style.space(8)

            Button {
              text: "Retry"
              bordered: true
              foreground: root.contentForeground
              fontFamily: root.contentFontFamily
              enabled: !vpn.busy
              hasCursor: root.cursorActive && root.focusSection === "recovery" && root.recoveryIndex === 0
              Accessible.role: Accessible.Button
              Accessible.name: text
              Accessible.onPressAction: {
                if (!vpn.busy) {
                  root.recoveryIndex = 0
                  root.activateRecovery()
                }
              }
              onHovered: function(on) { if (on) root.focusRecovery(0) }
              onClicked: {
                root.recoveryIndex = 0
                root.activateRecovery()
              }
            }

            Button {
              text: "Change protocol"
              bordered: true
              foreground: root.contentForeground
              fontFamily: root.contentFontFamily
              hasCursor: root.cursorActive && root.focusSection === "recovery" && root.recoveryIndex === 1
              Accessible.role: Accessible.Button
              Accessible.name: text
              Accessible.onPressAction: {
                root.recoveryIndex = 1
                root.activateRecovery()
              }
              onHovered: function(on) { if (on) root.focusRecovery(1) }
              onClicked: {
                root.recoveryIndex = 1
                root.activateRecovery()
              }
            }
          }

          // ── First run: Windscribe isn't there yet ───────────────────────
          Column {
            visible: !vpn.installed && !vpn.archProbed
            width: parent.width
            spacing: Style.space(8)

            Text {
              width: parent.width
              text: "Checking system…"
              textFormat: Text.PlainText
              color: root.dimForeground
              font.family: root.contentFontFamily
              font.pixelSize: Style.font.bodySmall
              horizontalAlignment: Text.AlignHCenter
            }
          }

          Column {
            visible: !vpn.installed && vpn.installSupported
            width: parent.width
            spacing: Style.space(8)

            ActionRow {
              width: parent.width
              hasCursor: root.cursorActive && root.focusSection === "header"
              icon: "󰇚"
              title: vpn.installing ? "Installing…" : "Install Windscribe CLI"
              subtitle: vpn.installing
                ? "Finish in the terminal"
                : "Required to connect"
              enabled: !vpn.installing
              onRowHovered: root.focusHeader()
              onRowClicked: vpn.installCli()
            }
          }

          Column {
            visible: !vpn.installed && vpn.archProbed && !vpn.installSupported
            width: parent.width
            spacing: Style.space(8)

            Text {
              width: parent.width
              text: "Windscribe CLI is unavailable"
              textFormat: Text.PlainText
              color: root.contentForeground
              font.family: root.contentFontFamily
              font.pixelSize: Style.font.body
              font.bold: true
              wrapMode: Text.WordWrap
            }

            Text {
              width: parent.width
              text: "This system is not currently supported."
              textFormat: Text.PlainText
              color: root.dimForeground
              font.family: root.contentFontFamily
              font.pixelSize: Style.font.caption
              wrapMode: Text.WordWrap
            }
          }

          // ── Sign in ─────────────────────────────────────────────────────
          ActionRow {
            visible: vpn.installed && vpn.loggedOut && !vpn.connected
            width: parent.width
            hasCursor: root.cursorActive && root.focusSection === "header"
            icon: "󰌆"
            title: vpn.signingIn ? "Signing in…" : "Sign in"
            subtitle: "Credentials stay in Windscribe’s terminal prompt"
            enabled: !vpn.busy
            onRowHovered: root.focusHeader()
            onRowClicked: vpn.signIn()
          }

          // ── Immediate destinations: pill chips with a leading mark, so
          // they read as actions — never as navigation. ────────────────────
          Row {
            id: quickRow
            visible: vpn.installed && vpn.loggedIn
            width: parent.width
            spacing: Style.space(6)
            readonly property real cellWidth: (width - spacing * Math.max(0, root.quickEntries.length - 1))
              / Math.max(1, root.quickEntries.length)

            Repeater {
              model: root.quickEntries

              QuickChip {
                required property var modelData
                width: quickRow.cellWidth
                icon: modelData.kind === "best" ? "󰓾" : "󰋚"
                label: vpn.markupSafeText(modelData.title)
                selected: modelData.kind === "recent"
                  && String(vpn.city).toLowerCase() === String(modelData.city).toLowerCase()
                enabled: !vpn.busy
                onActivated: {
                  if (modelData.kind === "best") vpn.connectBest()
                  else vpn.connectTo(modelData.target)
                }
              }
            }
          }

          // ── Tabs: one segmented strip, so navigation can't be mistaken
          // for the action chips above it. ─────────────────────────────────
          Rectangle {
            id: tabRow
            visible: vpn.installed && vpn.loggedIn
            width: parent.width
            implicitHeight: Style.space(30)
            radius: Style.cornerRadius > 0 ? Style.space(7) : 0
            color: Qt.rgba(root.contentForeground.r, root.contentForeground.g, root.contentForeground.b, 0.035)
            border.color: Qt.rgba(root.contentForeground.r, root.contentForeground.g, root.contentForeground.b, 0.12)
            border.width: 1

            Row {
              anchors.fill: parent
              anchors.margins: Style.space(2)

              TabCell { text: "Locations"; tabKey: "locations"; width: (tabRow.width - Style.space(4)) / 2; height: parent.height }
              TabCell { text: "Connection"; tabKey: "connection"; width: (tabRow.width - Style.space(4)) / 2; height: parent.height }
            }
          }

          // ── Locations ───────────────────────────────────────────────────
          Column {
            visible: vpn.installed && vpn.loggedIn && root.tab === "locations"
            width: parent.width
            spacing: Style.space(12)

            Item {
              width: parent.width
              implicitHeight: Math.max(locationHeader.implicitHeight, favoriteSummary.implicitHeight)

              PanelSectionHeader {
                id: locationHeader
                text: "Locations"
                foreground: root.contentForeground
                fontFamily: root.contentFontFamily
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
              }

              Text {
                id: favoriteSummary
                text: root.favoriteLocations.length === 0
                  ? (vpn.locations.length > 0 ? vpn.locations.length + " available" : "Search by name")
                  : root.favoriteLocations.length + (root.favoriteLocations.length === 1 ? " favourite" : " favourites")
                textFormat: Text.PlainText
                color: root.dimForeground
                font.family: root.contentFontFamily
                font.pixelSize: Style.font.caption
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
              }
            }

            TextField {
              id: searchField
              width: parent.width
              text: root.locationQuery
              placeholderText: "Search locations"
              foreground: root.contentForeground
              font.family: root.contentFontFamily
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
                root.focusLocation(Math.min(root.locationIndex + 1, root.visibleEntries.length - 1))
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
            }

            Text {
              visible: vpn.loadingLocations
              width: parent.width
              text: "Loading locations…"
              textFormat: Text.PlainText
              color: root.dimForeground
              font.family: root.contentFontFamily
              font.pixelSize: Style.font.bodySmall
              horizontalAlignment: Text.AlignHCenter
            }

            Text {
              visible: vpn.locationsUnavailable && !vpn.cliOnlyBuild
              width: parent.width
              text: "Enter a city, region, country code, or nickname."
              textFormat: Text.PlainText
              color: root.dimForeground
              font.family: root.contentFontFamily
              font.pixelSize: Style.font.caption
              wrapMode: Text.WordWrap
            }

            Text {
              visible: !vpn.loadingLocations && root.visibleEntries.length === 0
              width: parent.width
              text: root.locationQuery === ""
                ? "No locations available"
                : "No locations found"
              textFormat: Text.PlainText
              color: root.dimForeground
              font.family: root.contentFontFamily
              font.pixelSize: Style.font.bodySmall
              horizontalAlignment: Text.AlignHCenter
            }

            ListView {
              id: locationList
              visible: root.visibleEntries.length > 0
              width: parent.width
              height: Math.min(contentHeight, Style.space(260))
              clip: true
              spacing: Style.space(3)
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
                implicitHeight: Math.max(locationCopy.implicitHeight, favoriteStar.implicitHeight) + Style.space(12)
                foreground: root.contentForeground
                hasCursor: root.cursorActive && root.focusSection === "locations" && root.locationIndex === index
                Accessible.role: Accessible.Button
                Accessible.name: (root.entryCurrent(modelData) ? "Current location. " : "")
                  + root.entryTitle(modelData) + ". " + root.entrySubtitle(modelData)
                Accessible.focusable: true
                Accessible.focused: hasCursor
                Accessible.onPressAction: if (!vpn.busy) root.activateEntry(modelData)

                MouseArea {
                  anchors.fill: parent
                  anchors.rightMargin: favoriteStar.width + Style.space(12)
                  hoverEnabled: true
                  cursorShape: vpn.busy ? Qt.ArrowCursor : Qt.PointingHandCursor
                  enabled: !vpn.busy
                  onEntered: root.focusLocation(locationRow.index)
                  onClicked: root.activateEntry(locationRow.modelData)
                }

                Column {
                  id: locationCopy
                  anchors.left: parent.left
                  anchors.leftMargin: Style.space(12)
                  anchors.right: currentMark.left
                  anchors.rightMargin: Style.space(8)
                  anchors.verticalCenter: parent.verticalCenter
                  spacing: Style.space(1)

                  Text {
                    width: parent.width
                    text: root.entryTitle(locationRow.modelData)
                    textFormat: Text.PlainText
                    color: root.contentForeground
                    font.family: root.contentFontFamily
                    font.pixelSize: Style.font.body
                    font.bold: locationRow.modelData.kind === "best"
                      || (root.entryStarable(locationRow.modelData)
                          && root.isFavorite(root.entryTarget(locationRow.modelData)))
                    elide: Text.ElideRight
                  }

                  Text {
                    visible: text !== ""
                    width: parent.width
                    text: root.entrySubtitle(locationRow.modelData)
                    textFormat: Text.PlainText
                    color: root.dimForeground
                    font.family: root.contentFontFamily
                    font.pixelSize: Style.font.caption
                    elide: Text.ElideRight
                  }
                }

                Text {
                  id: currentMark
                  anchors.right: favoriteStar.left
                  anchors.rightMargin: Style.space(12)
                  anchors.verticalCenter: parent.verticalCenter
                  text: root.entryCurrent(locationRow.modelData) ? "●" : ""
                  textFormat: Text.PlainText
                  color: Color.accent
                  font.family: root.contentFontFamily
                  font.pixelSize: Style.font.caption
                }

                Text {
                  id: favoriteStar
                  width: Style.space(34)
                  anchors.right: parent.right
                  anchors.rightMargin: Style.space(6)
                  anchors.verticalCenter: parent.verticalCenter
                  text: locationRow.modelData.kind === "best"
                    ? "󰒋"
                    : (root.isFavorite(root.entryTarget(locationRow.modelData)) ? "★" : "☆")
                  textFormat: Text.PlainText
                  color: root.entryStarable(locationRow.modelData)
                      && root.isFavorite(root.entryTarget(locationRow.modelData))
                    ? Color.accent
                    : root.dimForeground
                  font.family: root.contentFontFamily
                  font.pixelSize: Style.font.title
                  horizontalAlignment: Text.AlignHCenter
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

          // ── Connection ──────────────────────────────────────────────────
          Column {
            visible: vpn.installed && vpn.loggedIn && root.tab === "connection"
            width: parent.width
            spacing: Style.space(10)

            PanelSectionHeader {
              text: "Connection"
              foreground: root.contentForeground
              fontFamily: root.contentFontFamily
            }

            ToggleRow {
              id: firewallControl
              width: parent.width
              title: "Firewall"
              subtitle: vpn.firewallLocked
                ? "Always On is locked by Windscribe"
                : "Blocks traffic outside the VPN"
              stateText: vpn.firewall === "" ? "Checking" : vpn.markupSafeText(vpn.firewall)
              checked: vpn.firewallOn
              busy: vpn.busy
              interactive: !vpn.firewallLocked
              hasCursor: root.connectionHasCursor("firewall")
              onRowHovered: root.focusConnectionKey("firewall")
              onRowToggled: vpn.setFirewall(!vpn.firewallOn)
            }

            SearchableDropdown {
              id: protocolPicker
              width: parent.width
              showLabel: true
              label: "Preferred Protocol"
              placeholderText: "Choose a protocol"
              triggerLabel: "Automatic"
              foreground: root.contentForeground
              fontFamily: root.contentFontFamily
              options: root.protocolOptions
              value: root.selectedProtocolBase
              hasCursor: root.connectionHasCursor("protocol")
              onHovered: function(on) { if (on) root.focusConnectionKey("protocol") }
              onChanged: function(v) {
                root.persistSetting("preferredProtocol", v)
                vpn.refreshPorts(v)
              }
            }

            SearchableDropdown {
              id: portPicker
              visible: root.selectedProtocolBase !== ""
              width: parent.width
              showLabel: true
              label: "Port"
              placeholderText: vpn.loadingPorts ? "Loading ports…" : "Choose a port"
              triggerLabel: "Automatic"
              foreground: root.contentForeground
              fontFamily: root.contentFontFamily
              options: root.portOptions
              value: root.selectedProtocolPort
              hasCursor: root.connectionHasCursor("port")
              onHovered: function(on) { if (on) root.focusConnectionKey("port") }
              onChanged: function(v) {
                var next = root.selectedProtocolBase + (v === "" ? "" : ":" + v)
                root.persistSetting("preferredProtocol", next)
              }
            }

            Text {
              width: parent.width
              text: "Used on your next connection."
              textFormat: Text.PlainText
              color: root.dimForeground
              font.family: root.contentFontFamily
              font.pixelSize: Style.font.caption
            }

            ToggleRow {
              id: alertsControl
              width: parent.width
              title: "Connection alerts"
              subtitle: "Connections and unexpected drops"
              checked: vpn.notificationsOn
              hasCursor: root.connectionHasCursor("notifications")
              onRowHovered: root.focusConnectionKey("notifications")
              onRowToggled: root.persistSetting("notifications", !vpn.notificationsOn)
            }

            ToggleRow {
              id: motionControl
              width: parent.width
              title: "Interface motion"
              subtitle: "Tunnel flow and state transitions"
              checked: root.motionOn
              hasCursor: root.connectionHasCursor("motion")
              onRowHovered: root.focusConnectionKey("motion")
              onRowToggled: root.persistSetting("motion", !root.motionOn)
            }

            ActionRow {
              id: rotateAction
              visible: vpn.connected && vpn.ipIsVpn
              width: parent.width
              icon: "󰑓"
              title: vpn.pendingLabel === "Rotating IP…" ? "Rotating IP…" : "Rotate IP"
              subtitle: "New address, same location"
              enabled: !vpn.busy
              hasCursor: root.connectionHasCursor("rotate")
              onRowHovered: root.focusConnectionKey("rotate")
              onRowClicked: vpn.rotateIp()
            }

            ActionRow {
              id: updateAction
              visible: vpn.updateAvailable !== ""
              width: parent.width
              icon: "󰚰"
              title: vpn.updating ? "Updating Windscribe…" : "Update Windscribe"
              subtitle: vpn.updateAvailable === "" ? "" : "Version " + vpn.markupSafeText(vpn.updateAvailable)
              enabled: !vpn.busy
              hasCursor: root.connectionHasCursor("update")
              onRowHovered: root.focusConnectionKey("update")
              onRowClicked: vpn.updateCli()
            }

            // ── Data allowance: plan usage with a quiet meter ─────────────
            Column {
              visible: vpn.dataUsage !== ""
              width: parent.width
              spacing: Style.space(6)

              Item {
                width: parent.width
                implicitHeight: Math.max(allowanceTitle.implicitHeight, allowanceValue.implicitHeight)

                Text {
                  id: allowanceTitle
                  anchors.left: parent.left
                  anchors.leftMargin: Style.space(12)
                  anchors.verticalCenter: parent.verticalCenter
                  text: "Data allowance"
                  textFormat: Text.PlainText
                  color: root.contentForeground
                  font.family: root.contentFontFamily
                  font.pixelSize: Style.font.body
                  font.bold: true
                }

                Text {
                  id: allowanceValue
                  anchors.right: parent.right
                  anchors.rightMargin: Style.space(10)
                  anchors.verticalCenter: parent.verticalCenter
                  text: vpn.markupSafeText(vpn.dataUsage)
                  textFormat: Text.PlainText
                  color: !vpn.usage.unlimited && vpn.usage.fraction > 0.9
                    ? root.urgentForeground
                    : root.dimForeground
                  font.family: root.contentFontFamily
                  font.pixelSize: Style.font.caption
                }
              }

              Rectangle {
                visible: !vpn.usage.unlimited
                x: Style.space(12)
                width: parent.width - Style.space(22)
                height: 3
                radius: 1.5
                color: Qt.rgba(root.contentForeground.r, root.contentForeground.g, root.contentForeground.b, 0.14)

                Rectangle {
                  width: parent.width * Math.max(0, Math.min(1, vpn.usage.fraction))
                  height: parent.height
                  radius: parent.radius
                  color: vpn.usage.fraction > 0.9 ? root.urgentForeground : Color.accent

                  Behavior on width {
                    NumberAnimation { duration: root.motionOn ? 220 : 0; easing.type: Easing.OutCubic }
                  }
                }
              }
            }

            PanelSeparator { foreground: root.contentForeground }

            Item {
              width: parent.width
              implicitHeight: Math.max(accountHeader.implicitHeight, accountState.implicitHeight)

              PanelSectionHeader {
                id: accountHeader
                text: "Account"
                foreground: root.contentForeground
                fontFamily: root.contentFontFamily
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
              }

              Text {
                id: accountState
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                text: vpn.markupSafeText(vpn.loginState === "" ? "Checking" : vpn.loginState)
                textFormat: Text.PlainText
                color: root.dimForeground
                font.family: root.contentFontFamily
                font.pixelSize: Style.font.caption
              }
            }

            ActionRow {
              id: signOutAction
              width: parent.width
              icon: "󰍃"
              title: root.signOutArmed ? "Confirm sign out" : "Sign out"
              subtitle: vpn.firewallOn ? "Disconnects; Firewall stays on" : "Disconnect and sign out"
              enabled: !vpn.busy
              hasCursor: root.connectionHasCursor("signout")
              onRowHovered: root.focusConnectionKey("signout")
              onRowClicked: {
                root.focusConnectionKey("signout")
                root.activateConnection()
              }
            }
          }

          Text {
            visible: vpn.installed && vpn.loggedIn
            width: parent.width
            text: root.tab === "locations"
              ? "J/K move · Enter connect · F favourite · / search\n←/→ tab · T tunnel · R refresh"
              : "J/K move · Enter change · W Firewall\n←/→ tab · T tunnel · R refresh"
            textFormat: Text.PlainText
            color: root.dimForeground
            font.family: root.contentFontFamily
            font.pixelSize: Style.font.caption
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WordWrap
          }
        }
      }
    }
  }

  component TabCell: Item {
    id: cell
    property string tabKey: ""
    property string text: ""
    readonly property bool active: root.tab === tabKey
    Accessible.role: Accessible.PageTab
    Accessible.name: text
    Accessible.selected: active
    Accessible.focusable: true
    Accessible.onPressAction: root.setTab(tabKey)

    Rectangle {
      anchors.fill: parent
      radius: Style.cornerRadius > 0 ? Style.space(5) : 0
      color: cell.active
        ? Qt.rgba(root.contentForeground.r, root.contentForeground.g, root.contentForeground.b, 0.10)
        : (cellArea.containsMouse
            ? Qt.rgba(root.contentForeground.r, root.contentForeground.g, root.contentForeground.b, 0.05)
            : "transparent")
    }

    // The active tab carries a small accent tick — state you can read from
    // across the room, in any theme.
    Rectangle {
      visible: cell.active
      anchors.horizontalCenter: parent.horizontalCenter
      anchors.bottom: parent.bottom
      anchors.bottomMargin: Style.space(3)
      width: Style.space(16)
      height: 2
      radius: 1
      color: Color.accent
    }

    Text {
      anchors.centerIn: parent
      anchors.verticalCenterOffset: -1
      text: cell.text
      textFormat: Text.PlainText
      color: cell.active ? root.contentForeground : root.dimForeground
      font.family: root.contentFontFamily
      font.pixelSize: Style.font.bodySmall
      font.bold: cell.active
    }

    MouseArea {
      id: cellArea
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: root.setTab(cell.tabKey)
    }
  }

  component QuickChip: Rectangle {
    id: chip
    property string icon: ""
    property string label: ""
    property bool selected: false
    signal activated()

    implicitHeight: chipRow.implicitHeight + Style.space(12)
    radius: height / 2
    color: chip.selected
      ? Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, 0.13)
      : (chipArea.containsMouse && chip.enabled
          ? Qt.rgba(root.contentForeground.r, root.contentForeground.g, root.contentForeground.b, 0.09)
          : Qt.rgba(root.contentForeground.r, root.contentForeground.g, root.contentForeground.b, 0.045))
    border.color: chip.selected
      ? Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, 0.55)
      : Qt.rgba(root.contentForeground.r, root.contentForeground.g, root.contentForeground.b, 0.13)
    border.width: 1
    opacity: enabled ? 1.0 : 0.55
    Accessible.role: Accessible.Button
    Accessible.name: label
    Accessible.focusable: true
    Accessible.onPressAction: if (chip.enabled) chip.activated()

    Row {
      id: chipRow
      anchors.centerIn: parent
      spacing: Style.space(6)

      Text {
        anchors.verticalCenter: parent.verticalCenter
        text: chip.icon
        textFormat: Text.PlainText
        color: chip.selected ? Color.accent : root.dimForeground
        font.family: root.contentFontFamily
        font.pixelSize: Style.font.bodySmall
      }

      Text {
        anchors.verticalCenter: parent.verticalCenter
        width: Math.min(implicitWidth, chip.width - Style.space(38))
        text: chip.label
        textFormat: Text.PlainText
        color: root.contentForeground
        font.family: root.contentFontFamily
        font.pixelSize: Style.font.caption
        font.bold: chip.selected
        elide: Text.ElideRight
      }
    }

    MouseArea {
      id: chipArea
      anchors.fill: parent
      hoverEnabled: true
      enabled: chip.enabled
      cursorShape: chip.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
      onClicked: chip.activated()
    }
  }

  component ToggleRow: CursorSurface {
    id: toggleRow
    property string title: ""
    property string subtitle: ""
    property string stateText: ""
    property bool checked: false
    property bool busy: false
    property bool interactive: true
    signal rowToggled()
    signal rowHovered()

    foreground: root.contentForeground
    implicitHeight: toggleCopy.implicitHeight + Style.space(14)
    opacity: interactive ? 1.0 : 0.72
    Accessible.role: Accessible.CheckBox
    Accessible.name: title
    Accessible.checkable: true
    Accessible.checked: checked
    Accessible.focusable: true
    Accessible.focused: hasCursor
    Accessible.onPressAction: {
      if (toggleRow.interactive && !toggleRow.busy) toggleRow.rowToggled()
    }
    Accessible.onToggleAction: {
      if (toggleRow.interactive && !toggleRow.busy) toggleRow.rowToggled()
    }

    MouseArea {
      anchors.fill: parent
      hoverEnabled: true
      enabled: toggleRow.interactive && !toggleRow.busy
      cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
      onEntered: toggleRow.rowHovered()
      onClicked: toggleRow.rowToggled()
    }

    Column {
      id: toggleCopy
      anchors.left: parent.left
      anchors.right: toggleState.left
      anchors.leftMargin: Style.space(12)
      anchors.rightMargin: Style.space(10)
      anchors.verticalCenter: parent.verticalCenter
      spacing: Style.space(2)

      Text {
        width: parent.width
        text: toggleRow.title
        textFormat: Text.PlainText
        color: root.contentForeground
        font.family: root.contentFontFamily
        font.pixelSize: Style.font.body
        font.bold: true
        elide: Text.ElideRight
      }

      Text {
        width: parent.width
        visible: toggleRow.subtitle !== ""
        text: toggleRow.subtitle
        textFormat: Text.PlainText
        color: root.dimForeground
        font.family: root.contentFontFamily
        font.pixelSize: Style.font.caption
        elide: Text.ElideRight
      }
    }

    Row {
      id: toggleState
      anchors.right: parent.right
      anchors.rightMargin: Style.space(10)
      anchors.verticalCenter: parent.verticalCenter
      spacing: Style.space(8)

      Text {
        visible: toggleRow.stateText !== ""
        anchors.verticalCenter: parent.verticalCenter
        text: toggleRow.stateText
        textFormat: Text.PlainText
        color: root.dimForeground
        font.family: root.contentFontFamily
        font.pixelSize: Style.font.caption
      }

      ToggleSwitch {
        anchors.verticalCenter: parent.verticalCenter
        checked: toggleRow.checked
        busy: toggleRow.busy
        interactive: false
        foreground: root.contentForeground
      }
    }
  }

  component ActionRow: CursorSurface {
    id: actionRow
    property string icon: ""
    property string title: ""
    property string subtitle: ""
    signal rowClicked()
    signal rowHovered()

    foreground: root.contentForeground
    implicitHeight: actionContent.implicitHeight + Style.space(14)
    opacity: enabled ? 1.0 : 0.55
    Accessible.role: Accessible.Button
    Accessible.name: title
    Accessible.focusable: true
    Accessible.focused: hasCursor
    Accessible.onPressAction: if (actionRow.enabled) actionRow.rowClicked()

    MouseArea {
      anchors.fill: parent
      hoverEnabled: true
      enabled: actionRow.enabled
      cursorShape: actionRow.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
      onEntered: actionRow.rowHovered()
      onClicked: actionRow.rowClicked()
    }

    Row {
      id: actionContent
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.leftMargin: Style.space(12)
      anchors.rightMargin: Style.space(12)
      anchors.verticalCenter: parent.verticalCenter
      spacing: Style.space(10)

      Text {
        anchors.verticalCenter: parent.verticalCenter
        text: actionRow.icon
        textFormat: Text.PlainText
        color: root.contentForeground
        font.family: root.contentFontFamily
        font.pixelSize: Style.font.title
      }

      Column {
        width: parent.width - x
        spacing: Style.space(2)

        Text {
          width: parent.width
          text: actionRow.title
          textFormat: Text.PlainText
          color: root.contentForeground
          font.family: root.contentFontFamily
          font.pixelSize: Style.font.body
          font.bold: true
          elide: Text.ElideRight
        }

        Text {
          width: parent.width
          visible: actionRow.subtitle !== ""
          text: actionRow.subtitle
          textFormat: Text.PlainText
          color: root.dimForeground
          font.family: root.contentFontFamily
          font.pixelSize: Style.font.caption
          wrapMode: Text.WordWrap
        }
      }
    }
  }
}
