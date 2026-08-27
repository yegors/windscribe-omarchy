import QtQuick
import qs.Commons
import qs.Ui
import "Model.js" as Model

// A live, abstract view of the VPN path. Every mark is backed by state the
// plugin already knows: tunnel state, exit label, protocol, Firewall, IP,
// and kernel traffic counters. No origin lookup or invented score.
//
// The card is drawn as an instrument: corner brackets instead of a boxed
// border, a callout capsule for the protocol above the line — never crossing
// it — and one ink throughout, taken from the active theme.
Item {
  id: root

  property bool active: false
  property bool connected: false
  property bool busy: false
  property bool tunnelChanging: false
  property bool firewallOn: false
  property bool tunnelTestPending: false
  property bool networkInterference: false
  property bool motionEnabled: true
  property bool presentationActive: true

  property string stateText: ""
  property string locationText: ""
  property string protocolText: ""
  property string firewallText: ""
  property string ipAddress: ""
  property bool ipIsVpn: false

  property var rxHistory: []
  property var txHistory: []
  property real rxRate: 0
  property real txRate: 0
  property real sessionRx: 0
  property real sessionTx: 0
  property int uptimeSec: 0

  property color foreground: Color.foreground
  property color accent: Color.accent
  property color urgent: Color.urgent
  property string fontFamily: Style.font.family

  signal rotateRequested()

  readonly property color dim: Qt.darker(foreground, 1.5)
  readonly property color faint: Qt.rgba(foreground.r, foreground.g, foreground.b, 0.14)
  readonly property color signalColor: networkInterference
    ? urgent
    : (active ? accent : dim)
  readonly property bool packetsRunning: motionEnabled && connected
    && !networkInterference && (rxRate > 0 || txRate > 0)
  readonly property int meterBars: 60
  property real trackPulse: 1
  readonly property real trafficPeak: {
    var peak = 1024
    for (var i = 0; i < rxHistory.length; i++) peak = Math.max(peak, Number(rxHistory[i]) || 0)
    for (var j = 0; j < txHistory.length; j++) peak = Math.max(peak, Number(txHistory[j]) || 0)
    return peak
  }

  implicitWidth: parent ? parent.width : Style.space(400)
  implicitHeight: frame.implicitHeight

  onBusyChanged: if (!busy) trackPulse = 1
  onMotionEnabledChanged: if (!motionEnabled) trackPulse = 1
  onPresentationActiveChanged: if (!presentationActive) trackPulse = 1

  function sample(series, slot) {
    var source = series || []
    var index = source.length - meterBars + slot
    return index >= 0 && index < source.length ? Math.max(0, Number(source[index]) || 0) : 0
  }

  function meterHeight(value, available) {
    if (value <= 0 || trafficPeak <= 0) return 1
    return Math.max(2, Math.min(available, value / trafficPeak * available))
  }

  function flowDuration(rate) {
    var activity = Math.log(1 + Math.max(0, Number(rate) || 0) / 1024)
    return Math.round(Math.max(620, 2100 - activity * 145))
  }

  Rectangle {
    id: frame
    width: parent.width
    implicitHeight: content.implicitHeight + Style.space(30)
    radius: Style.cornerRadius > 0 ? Style.space(8) : 0
    color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.030)

    // Corner brackets, not a box: the card reads as an instrument. They take
    // the signal color while a tunnel is up.
    Repeater {
      model: [
        { rightSide: false, bottomSide: false },
        { rightSide: true, bottomSide: false },
        { rightSide: false, bottomSide: true },
        { rightSide: true, bottomSide: true }
      ]

      Item {
        id: bracket
        required property var modelData
        readonly property color bracketColor: root.active
          ? Qt.rgba(root.signalColor.r, root.signalColor.g, root.signalColor.b, 0.55)
          : Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.30)
        x: modelData.rightSide ? frame.width - Style.space(12) : 0
        y: modelData.bottomSide ? frame.height - Style.space(12) : 0
        width: Style.space(12)
        height: Style.space(12)

        Rectangle {
          width: bracket.width
          height: 1
          y: bracket.modelData.bottomSide ? bracket.height - 1 : 0
          color: bracket.bracketColor
        }

        Rectangle {
          width: 1
          height: bracket.height
          x: bracket.modelData.rightSide ? bracket.width - 1 : 0
          color: bracket.bracketColor
        }
      }
    }

    Column {
      id: content
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.top: parent.top
      anchors.margins: Style.space(15)
      spacing: Style.space(10)

      // ── Header: identity left, protection and address right ────────────
      Item {
        width: parent.width
        implicitHeight: Math.max(locationColumn.implicitHeight, statusColumn.implicitHeight)

        Column {
          id: locationColumn
          anchors.left: parent.left
          anchors.right: statusColumn.left
          anchors.rightMargin: Style.space(12)
          anchors.verticalCenter: parent.verticalCenter
          spacing: Style.space(2)

          Text {
            width: parent.width
            text: root.locationText !== ""
              ? root.locationText
              : (root.tunnelChanging && root.active ? "Choosing an exit…" : "No active tunnel")
            textFormat: Text.PlainText
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.title
            font.bold: true
            elide: Text.ElideRight
          }

          Text {
            width: parent.width
            text: root.stateText
            textFormat: Text.PlainText
            color: root.networkInterference ? root.urgent : root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            elide: Text.ElideRight
          }
        }

        Column {
          id: statusColumn
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          spacing: Style.space(5)

          Rectangle {
            id: firewallBadge
            anchors.right: parent.right
            implicitWidth: firewallLabel.implicitWidth + Style.space(16)
            implicitHeight: firewallLabel.implicitHeight + Style.space(8)
            radius: height / 2
            color: root.firewallOn
              ? Qt.rgba(root.signalColor.r, root.signalColor.g, root.signalColor.b, 0.13)
              : "transparent"
            border.color: root.firewallOn
              ? Qt.rgba(root.signalColor.r, root.signalColor.g, root.signalColor.b, 0.72)
              : root.faint
            border.width: 1

            Text {
              id: firewallLabel
              anchors.centerIn: parent
              text: "FIREWALL  " + (root.firewallText || "Checking")
              textFormat: Text.PlainText
              color: root.firewallOn ? root.signalColor : root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              font.bold: true
            }
          }

          // The address this connection presents, right where the
          // connection lives. Click to rotate.
          Text {
            id: ipText
            visible: root.ipAddress !== ""
            anchors.right: parent.right
            text: (root.ipIsVpn ? "VPN IP  " : "PUBLIC IP  ") + root.ipAddress
              + (root.connected && root.ipIsVpn ? "  ↻" : "")
            textFormat: Text.PlainText
            color: ipArea.containsMouse && ipArea.enabled ? root.signalColor : root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            font.bold: ipArea.containsMouse && ipArea.enabled
            Accessible.role: root.connected && root.ipIsVpn
              ? Accessible.Button
              : Accessible.StaticText
            Accessible.name: root.connected && root.ipIsVpn
              ? "Rotate IP. Current " + text
              : text
            Accessible.focusable: root.connected && root.ipIsVpn
            Accessible.onPressAction: {
              if (root.connected && root.ipIsVpn && !root.busy) root.rotateRequested()
            }

            MouseArea {
              id: ipArea
              anchors.fill: parent
              anchors.margins: -Style.space(4)
              enabled: root.connected && root.ipIsVpn && !root.busy
              hoverEnabled: true
              cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
              onClicked: root.rotateRequested()
            }

            PanelToolTip {
              visible: ipArea.containsMouse && ipArea.enabled
              text: "Rotate IP — new address, same location"
              fontFamily: root.fontFamily
            }
          }
        }
      }

      // ── The tunnel ──────────────────────────────────────────────────────
      Item {
        id: tunnel
        width: parent.width
        height: Style.space(88)

        readonly property real deviceCx: Style.space(16)
        readonly property real exitCx: width - Style.space(19)
        readonly property real trackY: Style.space(46)
        // Clear of the exit node's 17px radius, so labels never collide.
        readonly property real labelY: trackY + Style.space(21)

        // Protocol callout: a capsule floating above the line, tied to it
        // with a hairline tick — the line never crosses the label.
        Rectangle {
          id: protocolCapsule
          anchors.horizontalCenter: parent.horizontalCenter
          y: 0
          implicitWidth: protocolLabel.implicitWidth + Style.space(18)
          implicitHeight: protocolLabel.implicitHeight + Style.space(8)
          radius: height / 2
          color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.05)
          border.color: root.active
            ? Qt.rgba(root.signalColor.r, root.signalColor.g, root.signalColor.b, 0.60)
            : root.faint
          border.width: 1

          Text {
            id: protocolLabel
            anchors.centerIn: parent
            text: root.protocolText || "Automatic"
            textFormat: Text.PlainText
            color: root.active ? root.foreground : root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            font.bold: root.active
          }
        }

        Rectangle {
          id: calloutTick
          anchors.horizontalCenter: parent.horizontalCenter
          y: protocolCapsule.height + Style.space(1)
          width: 1
          height: tunnel.trackY - protocolCapsule.height - Style.space(4)
          color: root.active
            ? Qt.rgba(root.signalColor.r, root.signalColor.g, root.signalColor.b, 0.40)
            : root.faint
        }

        // Soft glow under the live line.
        Rectangle {
          x: track.x
          y: tunnel.trackY - 3
          width: track.width
          height: 6
          radius: 3
          color: root.signalColor
          opacity: root.active ? 0.10 * root.trackPulse : 0
        }

        Rectangle {
          id: track
          x: tunnel.deviceCx + Style.space(16)
          y: tunnel.trackY - 1
          width: tunnel.exitCx - Style.space(19) - x
          height: 2
          radius: 1
          color: root.faint
        }

        Rectangle {
          id: liveTrack
          x: track.x
          y: track.y
          width: track.width
          height: track.height
          radius: track.radius
          color: root.signalColor
          opacity: (root.active ? 0.9 : 0.26) * root.trackPulse

          SequentialAnimation {
            running: root.presentationActive && root.motionEnabled && root.tunnelChanging && root.visible
            loops: Animation.Infinite
            alwaysRunToEnd: true
            NumberAnimation {
              target: root
              property: "trackPulse"
              to: 0.28
              duration: 420
              easing.type: Easing.InOutSine
            }
            NumberAnimation {
              target: root
              property: "trackPulse"
              to: 1.0
              duration: 420
              easing.type: Easing.InOutSine
            }
          }
        }

        Repeater {
          model: 6

          Rectangle {
            id: packet
            required property int index
            readonly property bool inbound: index % 2 === 0
            width: inbound ? 6 : 4
            height: inbound ? 3 : 2
            radius: height / 2
            y: tunnel.trackY + (inbound ? -6 : 5)
            color: root.signalColor
            opacity: root.packetsRunning && (inbound ? root.rxRate > 0 : root.txRate > 0)
              ? (inbound ? 0.95 : 0.64)
              : 0

            SequentialAnimation on x {
              running: root.presentationActive && root.packetsRunning && root.visible
              loops: Animation.Infinite
              PauseAnimation { duration: packet.index * 170 }
              NumberAnimation {
                from: packet.inbound ? track.x + track.width : track.x
                to: packet.inbound ? track.x : track.x + track.width
                duration: root.flowDuration(packet.inbound ? root.rxRate : root.txRate)
                easing.type: Easing.InOutSine
              }
              PauseAnimation { duration: 180 }
            }

            Behavior on opacity {
              NumberAnimation { duration: root.motionEnabled ? 140 : 0 }
            }
          }
        }

        // The track stops short of both nodes, so nothing needs an opaque
        // fill to hide it.
        Rectangle {
          id: deviceNode
          width: Style.space(28)
          height: width
          radius: width / 2
          x: tunnel.deviceCx - width / 2
          y: tunnel.trackY - height / 2
          color: "transparent"
          border.color: root.active ? root.signalColor : root.dim
          border.width: 2

          Text {
            anchors.centerIn: parent
            text: "󰍹"
            textFormat: Text.PlainText
            color: root.active ? root.signalColor : root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.space(12)
          }
        }

        Item {
          id: exitNode
          width: Style.space(34)
          height: width
          x: tunnel.exitCx - width / 2
          y: tunnel.trackY - height / 2

          Rectangle {
            id: firewallRing
            anchors.centerIn: parent
            width: parent.width
            height: width
            radius: width / 2
            color: "transparent"
            border.color: root.firewallOn ? root.signalColor : root.dim
            border.width: root.firewallOn ? 2 : 1
            opacity: root.firewallOn ? 0.95 : 0.5
          }

          Rectangle {
            id: pulseRing
            visible: root.active
            anchors.centerIn: parent
            width: parent.width
            height: width
            radius: width / 2
            color: "transparent"
            border.color: root.signalColor
            border.width: 1
            opacity: 0

            ParallelAnimation {
              running: root.presentationActive && root.motionEnabled && root.active && root.visible
              loops: Animation.Infinite
              onRunningChanged: {
                if (!running) {
                  pulseRing.scale = 1
                  pulseRing.opacity = 0
                }
              }
              NumberAnimation {
                target: pulseRing
                property: "scale"
                from: 0.82
                to: 1.72
                duration: 1450
                easing.type: Easing.OutCubic
              }
              SequentialAnimation {
                NumberAnimation { target: pulseRing; property: "opacity"; from: 0; to: 0.62; duration: 220 }
                NumberAnimation { target: pulseRing; property: "opacity"; to: 0; duration: 1230 }
              }
            }
          }

          WindscribeIcon {
            anchors.centerIn: parent
            iconSize: Style.space(17)
            color: root.active ? root.signalColor : root.dim
          }
        }

        Text {
          anchors.left: parent.left
          y: tunnel.labelY
          text: "THIS DEVICE"
          textFormat: Text.PlainText
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          font.bold: true
        }

        Text {
          anchors.right: parent.right
          y: tunnel.labelY
          text: "VPN EXIT"
          textFormat: Text.PlainText
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          font.bold: true
        }

        Text {
          anchors.horizontalCenter: parent.horizontalCenter
          y: tunnel.labelY
          text: root.networkInterference
            ? "CHECK FAILED"
            : (root.tunnelTestPending
                ? "VERIFYING"
                : (root.connected
                    ? "ENCRYPTED TUNNEL"
                    : (root.tunnelChanging
                        ? (root.active ? "NEGOTIATING" : "CLOSING TUNNEL")
                        : "TUNNEL IDLE")))
          textFormat: Text.PlainText
          color: root.networkInterference ? root.urgent : root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          font.bold: true
        }
      }

      // ── Mirrored activity band ──────────────────────────────────────────
      Item {
        id: meter
        width: parent.width
        height: Style.space(50)

        Rectangle {
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          height: 1
          color: root.faint
        }

        Row {
          id: meterRow
          anchors.fill: parent
          spacing: Style.space(2)

          Repeater {
            model: root.meterBars

            Item {
              id: meterSlot
              required property int index
              width: (meter.width - (root.meterBars - 1) * meterRow.spacing) / root.meterBars
              height: meter.height
              readonly property real downValue: root.sample(root.rxHistory, index)
              readonly property real upValue: root.sample(root.txHistory, index)

              Rectangle {
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.bottom: parent.verticalCenter
                anchors.bottomMargin: 1
                width: parent.width
                height: root.meterHeight(meterSlot.downValue, meter.height / 2 - 2)
                radius: Math.min(width / 2, 2)
                color: root.signalColor
                opacity: meterSlot.downValue > 0 ? 0.82 : 0.10

                Behavior on height {
                  NumberAnimation { duration: root.motionEnabled ? 180 : 0; easing.type: Easing.OutCubic }
                }
              }

              Rectangle {
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.top: parent.verticalCenter
                anchors.topMargin: 1
                width: parent.width
                height: root.meterHeight(meterSlot.upValue, meter.height / 2 - 2)
                radius: Math.min(width / 2, 2)
                color: root.foreground
                opacity: meterSlot.upValue > 0 ? 0.46 : 0.08

                Behavior on height {
                  NumberAnimation { duration: root.motionEnabled ? 180 : 0; easing.type: Easing.OutCubic }
                }
              }
            }
          }
        }
      }

      // ── Readouts, separated by hairlines ────────────────────────────────
      Row {
        width: parent.width

        Repeater {
          model: [
            { label: "DOWN", value: Model.formatRate(root.rxRate) },
            { label: "UP", value: Model.formatRate(root.txRate) },
            { label: "VIEW DATA", value: Model.formatBytes(root.sessionRx + root.sessionTx) },
            { label: "VIEW TIME", value: Model.formatDuration(root.uptimeSec) }
          ]

          Item {
            id: metric
            required property var modelData
            required property int index
            width: content.width / 4
            implicitHeight: metricColumn.implicitHeight

            Rectangle {
              visible: metric.index > 0
              anchors.left: parent.left
              anchors.verticalCenter: parent.verticalCenter
              width: 1
              height: metric.implicitHeight - Style.space(2)
              color: root.faint
            }

            Column {
              id: metricColumn
              width: parent.width
              spacing: Style.space(1)

              Text {
                width: parent.width
                text: modelData.label
                textFormat: Text.PlainText
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                font.bold: true
                horizontalAlignment: Text.AlignHCenter
              }

              Text {
                width: parent.width
                text: modelData.value
                textFormat: Text.PlainText
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.bodySmall
                font.bold: true
                horizontalAlignment: Text.AlignHCenter
                elide: Text.ElideRight
              }
            }
          }
        }
      }
    }
  }
}
