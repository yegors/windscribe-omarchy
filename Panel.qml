import QtQuick
import QtQuick.Controls
import qs.Commons
import qs.Ui
import "Geo.js" as Geo
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
  property string focusSection: "header"
  property bool cursorActive: true
  property var favoriteLocations: []
  property bool signOutArmed: false

  readonly property var barIdentity: hostWidget || root
  readonly property color contentForeground: bar ? bar.foreground : Color.foreground
  readonly property color dimForeground: Qt.darker(contentForeground, 1.5)
  readonly property color urgentForeground: bar ? bar.urgent : Color.urgent
  readonly property string contentFontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property string toggleHint: vpn.active ? "Disconnect Windscribe" : "Connect Windscribe"
  readonly property var visibleEntries: buildEntries()
  readonly property var mapCities: buildMapCities()
  readonly property var protocolOptions: [
    { value: "auto", label: "Auto (app default)" },
    { value: "wireguard", label: "WireGuard" },
    { value: "udp", label: "OpenVPN UDP" },
    { value: "tcp", label: "OpenVPN TCP" },
    { value: "stealth", label: "Stealth" },
    { value: "wstunnel", label: "WStunnel" }
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
    if (key !== "locations" && key !== "protection") return
    tab = key
  }

  function cycleTab(direction) {
    if (!vpn.installed || !vpn.loggedIn) return
    setTab(tab === "locations" ? "protection" : "locations")
  }

  function syncFavoriteLocations() {
    var source = settings && settings.favoriteLocations instanceof Array
      ? settings.favoriteLocations
      : []
    favoriteLocations = source.slice()
  }

  function isFavorite(city) {
    var target = String(city || "").toLowerCase()
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

  function locationByCity(city) {
    var target = String(city || "").toLowerCase()
    var available = vpn.locations || []
    for (var i = 0; i < available.length; i++)
      if (String(available[i].city).toLowerCase() === target) return available[i]
    return null
  }

  function entryForCity(city, kindFallback) {
    var resolved = locationByCity(city)
    return resolved
      ? { kind: "location", city: resolved.city, country: resolved.country,
          nickname: resolved.nickname, pro: resolved.pro, tenGbps: resolved.tenGbps }
      : { kind: kindFallback, city: String(city), country: "", nickname: "", pro: false, tenGbps: false }
  }

  function buildEntries() {
    var query = String(locationQuery || "").trim().toLowerCase()
    var out = []
    var seen = ({})

    var bestMatches = query === ""
      || "fastest location".indexOf(query) === 0
      || "best".indexOf(query) === 0
    if (vpn.installed && bestMatches)
      out.push({ kind: "best", city: "", country: "", nickname: "", pro: false, tenGbps: false })

    if (query === "") {
      for (var r = 0; r < vpn.recents.length; r++) {
        var recent = vpn.recents[r]
        if (!recent || !recent.city || seen[String(recent.city).toLowerCase()]) continue
        out.push(entryForCity(recent.city, "favorite"))
        seen[String(recent.city).toLowerCase()] = true
      }
    }

    for (var i = 0; i < favoriteLocations.length; i++) {
      var favorite = String(favoriteLocations[i] || "").trim()
      if (favorite === "" || seen[favorite.toLowerCase()]) continue
      var entry = entryForCity(favorite, "favorite")
      if (entryMatches(entry, query)) {
        out.push(entry)
        seen[favorite.toLowerCase()] = true
      }
    }

    if (query !== "") {
      var matched = false
      for (var k = 0; k < out.length; k++)
        if (out[k].kind === "location" || out[k].kind === "favorite") matched = true
      var available = vpn.locations || []
      for (var j = 0; j < available.length; j++) {
        var location = available[j]
        if (location.disabled || seen[String(location.city).toLowerCase()]) continue
        var candidate = { kind: "location", city: location.city, country: location.country,
                          nickname: location.nickname, pro: location.pro, tenGbps: location.tenGbps }
        if (entryMatches(candidate, query)) {
          out.push(candidate)
          seen[String(location.city).toLowerCase()] = true
          matched = true
        }
      }
      if (!matched && vpn.installed && vpn.isSafeLocation(locationQuery.trim()))
        out.push({ kind: "custom", city: locationQuery.trim(), country: "", nickname: "", pro: false, tenGbps: false })
    }

    if (query === "" && vpn.installed && !vpn.cliOnlyBuild && vpn.locationsUnavailable)
      out.push({ kind: "openapp", city: "", country: "", nickname: "", pro: false, tenGbps: false })

    return out
  }

  function buildMapCities() {
    var out = []
    var available = vpn.locations || []
    for (var i = 0; i < available.length; i++) {
      var location = available[i]
      if (location.disabled) continue
      var hit = Geo.locate(location.city)
      if (!hit) continue
      out.push({ city: location.city, country: location.country,
                 nickname: location.nickname, lat: hit[0], lon: hit[1] })
    }
    return out
  }

  function entryLabel(entry) {
    if (entry.kind === "best") return "Fastest location"
    if (entry.kind === "openapp") return "Open location list in the Windscribe app"
    if (entry.kind === "custom") return "Connect to “" + vpn.markupSafeText(entry.city) + "”"
    var label = vpn.markupSafeText(entry.city)
    if (entry.country !== "") label += " — " + vpn.markupSafeText(entry.country)
    if (entry.nickname !== "") label += " · " + vpn.markupSafeText(entry.nickname)
    if (entry.pro) label += " · Pro"
    if (entry.tenGbps) label += " · 10G"
    return label
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
    else if (entry.kind === "openapp") vpn.openLocationsInApp()
    else vpn.connectTo(entry.city)
  }

  function persistSetting(key, value) {
    if (!root.bar || !root.bar.shell || typeof root.bar.shell.updateEntryInline !== "function") return
    var entry = { id: root.moduleName }
    for (var existing in settings) if (existing !== "id") entry[existing] = settings[existing]
    entry[key] = value
    root.bar.shell.updateEntryInline(root.moduleName, entry)
  }

  function toggleFavorite(city) {
    var target = String(city || "").trim()
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
  }

  function focusLocation(index) {
    cursorActive = true
    focusSection = "locations"
    locationIndex = Math.max(0, Math.min(Number(index), Math.max(0, visibleEntries.length - 1)))
    keyCatcher.forceActiveFocus()
    Qt.callLater(function() { locationList.positionViewAtIndex(locationIndex, ListView.Contain) })
  }

  function moveCursor(direction) {
    cursorActive = true
    if (tab !== "locations" || visibleEntries.length === 0) {
      focusSection = "header"
      return
    }
    if (focusSection === "header") {
      if (direction > 0) focusLocation(locationIndex)
      return
    }
    if (direction < 0 && locationIndex === 0) {
      focusHeader()
      return
    }
    locationIndex = (locationIndex + direction + visibleEntries.length) % visibleEntries.length
    Qt.callLater(function() { locationList.positionViewAtIndex(locationIndex, ListView.Contain) })
  }

  function activateCursor() {
    if (focusSection === "locations" && tab === "locations" && visibleEntries.length > 0) {
      activateEntry(visibleEntries[locationIndex])
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
    // Enter only toggles the tunnel from the Locations tab, where the hero
    // ring is the focused control — a stray Enter on Protection must never
    // change the connection.
    if (tab === "locations") vpn.toggle()
  }

  function focusSearch() {
    searchField.forceActiveFocus()
    searchField.selectAll()
  }

  function maxScroll() {
    return Math.max(0, panelFlick.contentHeight - panelFlick.height)
  }

  onSettingsChanged: syncFavoriteLocations()
  onVisibleEntriesChanged: clampLocationIndex()
  Component.onCompleted: syncFavoriteLocations()

  onOpenedChanged: {
    vpn.panelOpen = opened
    if (opened) {
      tab = "locations"
      signOutArmed = false
      vpn.refresh()
      if (vpn.cliOnlyBuild && !vpn.locationsLoaded) vpn.refreshLocations()
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
      blocked: searchField.activeFocus || protocolPicker.popupOpen
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
            if (root.entryStarable(entry)) root.toggleFavorite(entry.city)
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
              meta: vpn.markupSafeText(
                vpn.statusText + (vpn.city === "" ? "" : " · " + vpn.city)
              )
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

          // ── Map ─────────────────────────────────────────────────────────
          WorldMap {
            visible: vpn.installed && (root.mapCities.length > 0 || vpn.currentPlace !== null)
            width: parent.width
            cities: root.mapCities
            current: vpn.currentPlace
            connected: vpn.connected
            busy: vpn.busy
            foreground: root.contentForeground
            fontFamily: root.contentFontFamily
            onCityClicked: function(c) { vpn.connectTo(c.city) }
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
              title: vpn.installing ? "Installing Windscribe…" : "Install Windscribe"
              subtitle: vpn.installing
                ? "Finish the install in the terminal that opened"
                : "Opens a terminal — Omarchy handles the install"
              enabled: !vpn.installing
              onRowHovered: root.focusHeader()
              onRowClicked: vpn.installCli()
            }

            Text {
              width: parent.width
              text: "Installs the official Windscribe CLI from windscribe.com — no desktop app, this panel is the wrapper. You'll also need a Windscribe account — a free one works."
              textFormat: Text.PlainText
              color: root.dimForeground
              font.family: root.contentFontFamily
              font.pixelSize: Style.font.caption
              wrapMode: Text.WordWrap
            }
          }

          Column {
            visible: !vpn.installed && vpn.archProbed && !vpn.installSupported
            width: parent.width
            spacing: Style.space(8)

            Text {
              width: parent.width
              text: "Unsupported on this CPU"
              textFormat: Text.PlainText
              color: root.contentForeground
              font.family: root.contentFontFamily
              font.pixelSize: Style.font.body
              font.bold: true
              wrapMode: Text.WordWrap
            }

            Text {
              width: parent.width
              text: "Windscribe's Arch CLI is x86_64 only — there is no ARM package, so this panel will not try to install it. If that changes, or if windscribe-cli is already on PATH, the widget will pick it up."
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
            title: "Sign in to Windscribe"
            subtitle: "Opens a terminal for your username, password, and 2FA"
            onRowHovered: root.focusHeader()
            onRowClicked: vpn.signIn()
          }

          // ── Connection detail ───────────────────────────────────────────
          Column {
            visible: vpn.ipAddress !== "" || (vpn.connected && vpn.protocol !== "")
            width: parent.width
            spacing: Style.space(4)

            Item {
              width: parent.width
              visible: vpn.ipAddress !== ""
              implicitHeight: Math.max(ipLabel.implicitHeight, ipValue.implicitHeight)

              Text {
                id: ipLabel
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                text: vpn.ipIsVpn ? "VPN IP" : "Public IP"
                textFormat: Text.PlainText
                color: root.dimForeground
                font.family: root.contentFontFamily
                font.pixelSize: Style.font.bodySmall
              }

              Row {
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                spacing: Style.space(8)

                Text {
                  id: ipValue
                  anchors.verticalCenter: parent.verticalCenter
                  text: vpn.markupSafeText(vpn.ipAddress)
                  textFormat: Text.PlainText
                  color: root.contentForeground
                  font.family: root.contentFontFamily
                  font.pixelSize: Style.font.bodySmall
                  font.bold: true
                }

                Text {
                  id: rotateButton
                  visible: vpn.connected && vpn.ipIsVpn
                  anchors.verticalCenter: parent.verticalCenter
                  text: "↻"
                  textFormat: Text.PlainText
                  color: rotateArea.containsMouse ? root.contentForeground : root.dimForeground
                  font.family: root.contentFontFamily
                  font.pixelSize: Style.font.body
                  font.bold: true

                  MouseArea {
                    id: rotateArea
                    anchors.fill: parent
                    anchors.margins: -Style.space(4)
                    hoverEnabled: true
                    cursorShape: vpn.busy ? Qt.ArrowCursor : Qt.PointingHandCursor
                    enabled: !vpn.busy
                    onClicked: vpn.rotateIp()
                  }

                  PanelToolTip {
                    visible: rotateArea.containsMouse
                    text: "New IP on this server"
                    fontFamily: root.contentFontFamily
                  }
                }
              }
            }

            InfoPair {
              visible: vpn.connected && vpn.protocol !== ""
              width: parent.width
              label: "Protocol"
              value: vpn.markupSafeText(vpn.protocol)
            }

            InfoPair {
              visible: vpn.dataUsage !== ""
              width: parent.width
              label: "Data usage"
              value: vpn.markupSafeText(vpn.dataUsage)
            }

            // Free-plan meter; hidden on Unlimited.
            Rectangle {
              visible: vpn.dataUsage !== "" && !vpn.usage.unlimited
              width: parent.width
              height: 3
              radius: 1.5
              color: Qt.rgba(root.contentForeground.r, root.contentForeground.g, root.contentForeground.b, 0.15)

              Rectangle {
                width: parent.width * vpn.usage.fraction
                height: parent.height
                radius: parent.radius
                color: vpn.usage.fraction > 0.9 ? root.urgentForeground : root.contentForeground
              }
            }
          }

          // ── Traffic ─────────────────────────────────────────────────────
          Traffic {
            visible: vpn.connected && !vpn.busy && vpn.rxHistory.length > 0
            width: parent.width
            rxHistory: vpn.rxHistory
            txHistory: vpn.txHistory
            rxRate: vpn.rxRate
            txRate: vpn.txRate
            sessionRx: vpn.sessionRx
            sessionTx: vpn.sessionTx
            uptimeSec: vpn.uptimeSec
            foreground: root.contentForeground
            fontFamily: root.contentFontFamily
          }

          // ── Tabs ────────────────────────────────────────────────────────
          Row {
            id: tabRow
            visible: vpn.installed && vpn.loggedIn
            width: parent.width
            spacing: Style.space(8)
            readonly property real cellWidth: (width - spacing) / 2

            TabPill { text: "Locations"; tabKey: "locations"; width: tabRow.cellWidth }
            TabPill { text: "Protection"; tabKey: "protection"; width: tabRow.cellWidth }
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
                text: "LOCATIONS"
                foreground: root.contentForeground
                fontFamily: root.contentFontFamily
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
              }

              Text {
                id: favoriteSummary
                text: root.favoriteLocations.length === 0
                  ? "Type to find locations"
                  : root.favoriteLocations.length + (root.favoriteLocations.length === 1 ? " favorite" : " favorites")
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
              placeholderText: "Search locations, or type a city and press Enter"
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
              text: "Loading Windscribe locations…"
              textFormat: Text.PlainText
              color: root.dimForeground
              font.family: root.contentFontFamily
              font.pixelSize: Style.font.bodySmall
              horizontalAlignment: Text.AlignHCenter
            }

            Text {
              visible: vpn.locationsUnavailable && !vpn.cliOnlyBuild
              width: parent.width
              text: "The GUI app keeps the location list in its own window. Type a city, country, or nickname above and press Enter to connect."
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
                ? "No favorites yet. Type a location, then star it."
                : "No matching locations."
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
              height: Math.min(contentHeight, Style.space(200))
              clip: true
              spacing: Style.space(3)
              model: root.visibleEntries
              currentIndex: root.locationIndex
              boundsBehavior: Flickable.StopAtBounds

              delegate: CursorSurface {
                id: locationRow
                required property var modelData
                required property int index
                width: locationList.width
                implicitHeight: Math.max(locationLabel.implicitHeight, favoriteStar.implicitHeight) + Style.space(12)
                foreground: root.contentForeground
                hasCursor: root.cursorActive && root.focusSection === "locations" && root.locationIndex === index

                MouseArea {
                  anchors.fill: parent
                  anchors.rightMargin: favoriteStar.width + Style.space(12)
                  hoverEnabled: true
                  cursorShape: vpn.busy ? Qt.ArrowCursor : Qt.PointingHandCursor
                  enabled: !vpn.busy
                  onEntered: root.focusLocation(locationRow.index)
                  onClicked: root.activateEntry(locationRow.modelData)
                }

                Text {
                  id: locationLabel
                  anchors.left: parent.left
                  anchors.leftMargin: Style.space(12)
                  anchors.right: currentMark.left
                  anchors.rightMargin: Style.space(8)
                  anchors.verticalCenter: parent.verticalCenter
                  text: root.entryLabel(locationRow.modelData)
                  textFormat: Text.PlainText
                  color: root.contentForeground
                  font.family: root.contentFontFamily
                  font.pixelSize: Style.font.body
                  font.bold: locationRow.modelData.kind === "best"
                    || (root.entryStarable(locationRow.modelData) && root.isFavorite(locationRow.modelData.city))
                  elide: Text.ElideRight
                }

                Text {
                  id: currentMark
                  anchors.right: favoriteStar.left
                  anchors.rightMargin: Style.space(12)
                  anchors.verticalCenter: parent.verticalCenter
                  text: root.entryCurrent(locationRow.modelData) ? "●" : ""
                  textFormat: Text.PlainText
                  color: root.contentForeground
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
                    ? "⚡"
                    : locationRow.modelData.kind === "openapp"
                      ? "›"
                      : (root.isFavorite(locationRow.modelData.city) ? "★" : "☆")
                  textFormat: Text.PlainText
                  color: root.entryStarable(locationRow.modelData) && root.isFavorite(locationRow.modelData.city)
                    ? Color.accent
                    : root.dimForeground
                  font.family: root.contentFontFamily
                  font.pixelSize: Style.font.title
                  horizontalAlignment: Text.AlignHCenter

                  MouseArea {
                    anchors.fill: parent
                    enabled: root.entryStarable(locationRow.modelData)
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onEntered: root.focusLocation(locationRow.index)
                    onClicked: root.toggleFavorite(locationRow.modelData.city)
                  }
                }
              }
            }
          }

          // ── Protection ──────────────────────────────────────────────────
          Column {
            visible: vpn.installed && vpn.loggedIn && root.tab === "protection"
            width: parent.width
            spacing: Style.space(12)

            Item {
              width: parent.width
              implicitHeight: Math.max(firewallHeader.implicitHeight, firewallSwitch.implicitHeight)

              PanelSectionHeader {
                id: firewallHeader
                text: "KILL SWITCH"
                foreground: root.contentForeground
                fontFamily: root.contentFontFamily
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
              }

              Text {
                anchors.right: firewallSwitch.left
                anchors.rightMargin: Style.space(10)
                anchors.verticalCenter: parent.verticalCenter
                text: vpn.firewall === "" ? "Checking…" : vpn.markupSafeText(vpn.firewall)
                textFormat: Text.PlainText
                color: root.dimForeground
                font.family: root.contentFontFamily
                font.pixelSize: Style.font.bodySmall
              }

              ToggleSwitch {
                id: firewallSwitch
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                checked: vpn.firewallOn
                busy: vpn.busy
                interactive: vpn.installed && !vpn.firewallLocked
                foreground: root.contentForeground
                onToggled: vpn.setFirewall(!vpn.firewallOn)

                PanelToolTip {
                  visible: firewallSwitch.containsMouse
                  text: vpn.firewallLocked
                    ? "Always On is set in Windscribe preferences"
                    : "Block all traffic outside the VPN tunnel"
                  fontFamily: root.contentFontFamily
                }
              }
            }

            Text {
              width: parent.width
              text: "If the VPN drops, the Windscribe firewall blocks every packet until you reconnect — nothing leaks out in the gap."
              textFormat: Text.PlainText
              color: root.dimForeground
              font.family: root.contentFontFamily
              font.pixelSize: Style.font.caption
              wrapMode: Text.WordWrap
            }

            SearchableDropdown {
              id: protocolPicker
              width: parent.width
              showLabel: true
              label: "Preferred protocol"
              placeholderText: "Auto (app default)"
              fontFamily: root.contentFontFamily
              options: root.protocolOptions
              value: String((root.settings && root.settings.preferredProtocol) || "")
              onChanged: function(v) { root.persistSetting("preferredProtocol", v) }
            }

            Text {
              width: parent.width
              text: "Applied on the next connect. Stealth and WStunnel help on restrictive networks."
              textFormat: Text.PlainText
              color: root.dimForeground
              font.family: root.contentFontFamily
              font.pixelSize: Style.font.caption
              wrapMode: Text.WordWrap
            }

            Item {
              width: parent.width
              implicitHeight: Math.max(notifyText.implicitHeight, notifySwitch.implicitHeight)

              Text {
                id: notifyText
                anchors.left: parent.left
                anchors.right: notifySwitch.left
                anchors.rightMargin: Style.space(10)
                anchors.verticalCenter: parent.verticalCenter
                text: "Notifications — connected, and unexpected drops"
                textFormat: Text.PlainText
                color: root.contentForeground
                font.family: root.contentFontFamily
                font.pixelSize: Style.font.bodySmall
                wrapMode: Text.WordWrap
              }

              ToggleSwitch {
                id: notifySwitch
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                checked: vpn.notificationsOn
                foreground: root.contentForeground
                onToggled: root.persistSetting("notifications", vpn.notificationsOn ? "off" : "on")
              }
            }

            PanelSeparator { foreground: root.contentForeground }

            PanelSectionHeader {
              text: "ACCOUNT"
              foreground: root.contentForeground
              fontFamily: root.contentFontFamily
            }

            InfoPair {
              width: parent.width
              label: "Status"
              value: vpn.markupSafeText(vpn.loginState === "" ? "Checking…" : vpn.loginState)
            }

            Text {
              visible: vpn.updateAvailable !== ""
              width: parent.width
              text: vpn.markupSafeText("Update available: " + vpn.updateAvailable + " — run “windscribe-cli update”")
              textFormat: Text.PlainText
              color: root.dimForeground
              font.family: root.contentFontFamily
              font.pixelSize: Style.font.caption
              wrapMode: Text.WordWrap
            }

            ActionRow {
              width: parent.width
              icon: "󰍃"
              title: root.signOutArmed ? "Sign out — click again to confirm" : "Sign out"
              subtitle: "Disconnects, signs out, and turns the firewall off"
              enabled: !vpn.busy
              onRowClicked: {
                if (root.signOutArmed) {
                  root.signOutArmed = false
                  signOutArmTimer.stop()
                  vpn.signOut()
                } else {
                  root.signOutArmed = true
                  signOutArmTimer.restart()
                }
              }
            }
          }

          Text {
            width: parent.width
            text: "J/K move · Enter connect · F star · / search · ←/→ tab · T toggle · W kill switch · R refresh"
            textFormat: Text.PlainText
            color: root.dimForeground
            font.family: root.contentFontFamily
            font.pixelSize: Style.font.caption
            horizontalAlignment: Text.AlignHCenter
            elide: Text.ElideRight
          }
        }
      }
    }
  }

  component TabPill: Button {
    id: pill
    property string tabKey: ""
    fontSize: Style.font.bodySmall
    foreground: root.contentForeground
    fontFamily: root.contentFontFamily
    horizontalPadding: Style.spacing.controlPaddingX
    verticalPadding: Style.spacing.controlPaddingY + Style.space(2)
    bordered: true
    active: root.tab === tabKey
    onClicked: root.setTab(tabKey)
  }

  component InfoPair: Item {
    id: pair
    property string label: ""
    property string value: ""
    implicitHeight: Math.max(pairLabel.implicitHeight, pairValue.implicitHeight)

    Text {
      id: pairLabel
      anchors.left: parent.left
      anchors.verticalCenter: parent.verticalCenter
      text: pair.label
      textFormat: Text.PlainText
      color: root.dimForeground
      font.family: root.contentFontFamily
      font.pixelSize: Style.font.bodySmall
    }

    Text {
      id: pairValue
      anchors.left: pairLabel.right
      anchors.leftMargin: Style.space(12)
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      text: pair.value
      textFormat: Text.PlainText
      color: root.contentForeground
      font.family: root.contentFontFamily
      font.pixelSize: Style.font.bodySmall
      font.bold: true
      horizontalAlignment: Text.AlignRight
      elide: Text.ElideMiddle
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

    MouseArea {
      anchors.fill: parent
      hoverEnabled: true
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
