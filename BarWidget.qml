import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "." as WindscribeCore

BarWidget {
  id: root
  moduleName: "com.windscribe.vpn"

  readonly property bool opened: panelLoader.item ? panelLoader.item.opened === true : false
  readonly property bool popoutSwitchClosing: panelLoader.item
    ? panelLoader.item.popoutSwitchClosing === true
    : false

  function injectPanel() {
    var target = panelLoader.item
    if (!target) return
    if ("bar" in target) target.bar = root.bar
    if ("settings" in target) target.settings = root.settings
    if ("anchorItem" in target) target.anchorItem = button
    if ("hostWidget" in target) target.hostWidget = root
  }

  function syncSettings() {
    WindscribeCore.VpnState.settings = root.settings || ({})
  }

  function open() {
    if (panelLoader.item) panelLoader.item.open()
  }

  function close() {
    if (panelLoader.item) panelLoader.item.close()
  }

  function toggle() {
    if (panelLoader.item) panelLoader.item.toggle()
  }

  function closeForPopoutSwitch() {
    if (panelLoader.item) panelLoader.item.closeForPopoutSwitch()
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  onBarChanged: injectPanel()
  onSettingsChanged: {
    syncSettings()
    injectPanel()
  }
  Component.onCompleted: syncSettings()

  Loader {
    id: panelLoader
    active: true
    source: Qt.resolvedUrl("Panel.qml")
    visible: false
    onLoaded: {
      root.injectPanel()
      Qt.callLater(root.injectPanel)
    }
  }

  IpcHandler {
    target: "com.windscribe.vpn"

    function open() { root.open() }
    function close() { root.close() }
    function show() { root.open() }
    function hide() { root.close() }
    function toggle() { root.toggle() }

    function connect(): string {
      WindscribeCore.VpnState.connect()
      return WindscribeCore.VpnState.statusText
    }

    function connectTo(location: string): string {
      WindscribeCore.VpnState.connectTo(location)
      return WindscribeCore.VpnState.statusText
    }

    function best(): string {
      WindscribeCore.VpnState.connectBest()
      return WindscribeCore.VpnState.statusText
    }

    function disconnect(): string {
      WindscribeCore.VpnState.disconnect()
      return WindscribeCore.VpnState.statusText
    }

    function toggleVpn(): string {
      WindscribeCore.VpnState.toggle()
      return WindscribeCore.VpnState.statusText
    }

    function firewall(state: string): string {
      var value = String(state || "").trim().toLowerCase()
      if (value === "on") WindscribeCore.VpnState.setFirewall(true)
      else if (value === "off") WindscribeCore.VpnState.setFirewall(false)
      return WindscribeCore.VpnState.firewall
    }

    function rotate(): string {
      WindscribeCore.VpnState.rotateIp()
      return WindscribeCore.VpnState.statusText
    }

    function refresh(): string {
      WindscribeCore.VpnState.refresh()
      WindscribeCore.VpnState.refreshLocations()
      return WindscribeCore.VpnState.statusText
    }

    function status(): string {
      return JSON.stringify({
        installed: WindscribeCore.VpnState.installed,
        cliOnlyBuild: WindscribeCore.VpnState.cliOnlyBuild,
        state: WindscribeCore.VpnState.connectionState,
        active: WindscribeCore.VpnState.active,
        loggedIn: WindscribeCore.VpnState.loggedIn,
        city: WindscribeCore.VpnState.city,
        protocol: WindscribeCore.VpnState.protocol,
        ip: WindscribeCore.VpnState.ipAddress,
        ipIsVpn: WindscribeCore.VpnState.ipIsVpn,
        firewall: WindscribeCore.VpnState.firewall,
        dataUsage: WindscribeCore.VpnState.dataUsage,
        error: WindscribeCore.VpnState.lastError
      })
    }
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    tooltipText: WindscribeCore.VpnState.markupSafeText(
      "Windscribe · " + WindscribeCore.VpnState.statusText
        + (WindscribeCore.VpnState.city === "" ? "" : " · " + WindscribeCore.VpnState.city)
        + (WindscribeCore.VpnState.firewallOn ? " · Kill switch on" : "")
    )
    iconComponent: Component {
      // The pulse animates the wrapper so it never clobbers the state
      // binding on the mark's own opacity.
      Item {
        id: markWrap

        WindscribeCore.WindscribeIcon {
          anchors.centerIn: parent
          // The badge fills its box corner to corner, so it reads larger than
          // the neighbouring glyphs at equal size — trimmed to sit level.
          iconSize: Style.space(11)
          color: button.foreground
          opacity: WindscribeCore.VpnState.active ? 1.0 : 0.55
        }

        // Breathes while a connect or disconnect is in flight.
        SequentialAnimation on opacity {
          running: WindscribeCore.VpnState.busy
          loops: Animation.Infinite
          alwaysRunToEnd: true
          NumberAnimation { to: 0.35; duration: 550 }
          NumberAnimation { to: 1.0; duration: 550 }
        }
      }
    }
    onPressed: function(buttonCode) {
      if (buttonCode === Qt.RightButton) WindscribeCore.VpnState.toggle()
      else if (buttonCode === Qt.MiddleButton) {
        WindscribeCore.VpnState.refresh()
        WindscribeCore.VpnState.refreshLocations()
      } else root.toggle()
    }
  }
}
