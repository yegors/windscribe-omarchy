import QtQuick
import QtQuick.Shapes
import qs.Commons
import "World.js" as World

// Where in the world you are, and where else you could be.
//
// Land is a single bundled SVG path (World.js, Natural Earth, public domain)
// drawn from the theme foreground at low alpha; every Windscribe city is a
// dim dot; the connected city is a bright dot with a slow pulse. Hover a dot
// for its name, click it to connect there. Everything here is local — no
// tiles, no geocoding, no requests.
//
// The map deliberately does not draw *your* location or a line to the
// server: finding it would take a geo-IP lookup, which this plugin promises
// never to make. Lighting the exit city is the honest version.
Item {
  id: root

  // [{city, country, nickname, lat, lon}]
  property var cities: []
  // {city, lat, lon} for the connected location, or null.
  property var current: null
  property bool connected: false
  property bool busy: false
  property color foreground: Color.foreground
  property string fontFamily: Style.font.family
  readonly property color dim: Qt.darker(foreground, 1.55)

  signal cityClicked(var city)

  property var hovered: null

  implicitHeight: Math.round(width * World.HEIGHT / World.WIDTH)
  readonly property real sx: width / World.WIDTH
  readonly property real sy: height / World.HEIGHT
  clip: true

  function isCurrent(c) {
    return current && c
      && String(current.city).toLowerCase() === String(c.city).toLowerCase()
  }

  function px(c) { return World.project(c.lat, c.lon)[0] * sx }
  function py(c) { return World.project(c.lat, c.lon)[1] * sy }

  // Land
  Shape {
    anchors.fill: parent
    antialiasing: true
    preferredRendererType: Shape.CurveRenderer
    transform: Scale { xScale: root.sx; yScale: root.sy }

    ShapePath {
      fillColor: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.10)
      strokeColor: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.28)
      strokeWidth: 0.35
      joinStyle: ShapePath.RoundJoin
      fillRule: ShapePath.WindingFill
      PathSvg { path: World.PATH }
    }
  }

  // Pulse behind the connected city
  Rectangle {
    id: pulse
    visible: root.connected && root.current !== null
    width: 8; height: 8; radius: 4
    color: "transparent"
    border.color: root.foreground
    border.width: 1.5
    x: root.current ? root.px(root.current) - width / 2 : 0
    y: root.current ? root.py(root.current) - height / 2 : 0
    transformOrigin: Item.Center

    SequentialAnimation on scale {
      running: pulse.visible
      loops: Animation.Infinite
      NumberAnimation { from: 0.8; to: 3.2; duration: 1800; easing.type: Easing.OutQuad }
    }
    SequentialAnimation on opacity {
      running: pulse.visible
      loops: Animation.Infinite
      NumberAnimation { from: 0.9; to: 0.0; duration: 1800; easing.type: Easing.OutQuad }
    }
  }

  // Connected city when it isn't in the list (GUI builds have no list).
  Rectangle {
    visible: root.current !== null && !root.currentListed
    width: 7; height: 7; radius: 3.5
    color: root.foreground
    x: root.current ? root.px(root.current) - width / 2 : 0
    y: root.current ? root.py(root.current) - height / 2 : 0
  }
  readonly property bool currentListed: {
    if (!current) return false
    for (var i = 0; i < cities.length; i++) if (isCurrent(cities[i])) return true
    return false
  }

  // Cities
  Repeater {
    model: root.cities

    Item {
      id: dot
      required property var modelData
      readonly property bool current: root.isCurrent(modelData)
      readonly property bool hot: root.hovered === modelData

      // A 14px hit area around a 3px dot, so it's clickable without hunting.
      width: 14; height: 14
      x: root.px(modelData) - width / 2
      y: root.py(modelData) - height / 2
      z: current ? 3 : (hot ? 2 : 1)

      Rectangle {
        anchors.centerIn: parent
        width: dot.current ? 7 : (dot.hot ? 5 : 2.5)
        height: width
        radius: width / 2
        color: dot.current || dot.hot ? root.foreground : root.dim
        opacity: dot.current ? 1.0 : (dot.hot ? 1.0 : 0.55)
        Behavior on width { NumberAnimation { duration: 90 } }
      }

      MouseArea {
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: root.busy ? Qt.ArrowCursor : Qt.PointingHandCursor
        onEntered: root.hovered = dot.modelData
        onExited: if (root.hovered === dot.modelData) root.hovered = null
        onClicked: if (!root.busy) root.cityClicked(dot.modelData)
      }
    }
  }

  // Hover label, kept inside the map's bounds
  Rectangle {
    id: label
    visible: root.hovered !== null
    z: 10
    readonly property real dotX: root.hovered ? root.px(root.hovered) : 0
    readonly property real dotY: root.hovered ? root.py(root.hovered) : 0
    width: labelText.implicitWidth + Style.space(8)
    height: labelText.implicitHeight + Style.space(4)
    radius: Style.cornerRadius > 0 ? Style.space(3) : 0
    color: Style.controlFill(false, true, root.foreground, Color.accent)
    border.color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.35)
    border.width: 1
    x: Math.max(0, Math.min(root.width - width, dotX + 9))
    y: Math.max(0, Math.min(root.height - height, dotY - height / 2))

    Text {
      id: labelText
      anchors.centerIn: parent
      // CLI-derived strings; PlainText keeps them from being sniffed as
      // rich text.
      text: root.hovered
        ? (String(root.hovered.city)
           + (root.hovered.country ? " — " + root.hovered.country : "")
           + (root.hovered.nickname ? "  ·  " + root.hovered.nickname : ""))
        : ""
      textFormat: Text.PlainText
      color: root.foreground
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
    }
  }
}
