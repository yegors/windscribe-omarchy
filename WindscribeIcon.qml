import QtQuick
import QtQuick.Shapes
import qs.Commons

// The Windscribe badge, drawn natively from the official mark's vector path
// (Windscribe/Desktop-App, src/client/frontend/gui/svg/BADGE_BLACK_ICON.svg)
// so it takes the theme foreground instead of a fixed brand color and stays
// crisp at any size — no bitmap, no icon-theme lookup, works identically on
// the GUI and CLI-only builds.
Item {
  id: root

  property real iconSize: Style.font.icon
  property color color: Color.foreground

  readonly property real viewBox: 40

  width: iconSize
  height: iconSize
  implicitWidth: iconSize
  implicitHeight: iconSize

  Item {
    anchors.centerIn: parent
    width: root.viewBox
    height: root.viewBox
    // Scaled from the 40px viewBox down to the requested size, so the shape
    // geometry stays sharp rather than being rasterized then stretched.
    scale: Math.min(root.width, root.height) / root.viewBox

    Shape {
      anchors.fill: parent
      antialiasing: true
      preferredRendererType: Shape.CurveRenderer

      ShapePath {
        fillColor: root.color
        strokeWidth: 0
        strokeColor: "transparent"
        // The badge ring and the W are separate subpaths that carve holes
        // out of each other; the SVG renders them with the nonzero rule.
        fillRule: ShapePath.WindingFill

        PathSvg {
          path: "M20 3.017L8.003 7.996L3.018 19.979L8.005 32.034L19.964 36.983L31.997 32.03L36.982 19.979L31.997 7.996L20 3.017ZM34.734 6.764L39.786 18.909C40.071 19.592 40.071 20.36 39.788 21.043L34.735 33.259C34.451 33.944 33.905 34.489 33.219 34.772L21.027 39.79C20.686 39.93 20.325 40 19.963 40C19.6 40 19.237 39.929 18.895 39.788L6.778 34.772C6.093 34.489 5.55 33.946 5.266 33.262L0.212 21.043C-0.071 20.36 -0.07 19.592 0.214 18.909L5.266 6.764C5.55 6.083 6.091 5.542 6.773 5.259L18.929 0.214C19.272 0.071 19.636 0 20 0C20.364 0 20.728 0.071 21.071 0.214L33.227 5.259C33.909 5.542 34.451 6.083 34.734 6.764ZM26.333 24.903L20.2 18.193L14.067 24.903L14.067 12L11 12L11 28L13.818 28C14.632 28 15.412 27.674 15.987 27.093L20.2 22.323L24.413 27.093C24.988 27.674 25.768 28 26.581 28L29.4 28L29.4 12L26.333 12L26.333 24.903Z"
        }
      }
    }
  }
}
