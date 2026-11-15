import QtQuick
import QtQuick.Shapes
import qs
import "icons.js" as Icons

// Theme-tinted line icon. Geometry is tessellated once; no shader effects.
Item {
    id: root

    property string name
    property color color: Theme.text
    property real size: Theme.iconSize
    property real stroke: 2

    implicitWidth: size
    implicitHeight: size

    Shape {
        width: 24
        height: 24
        anchors.centerIn: parent
        scale: root.size / 24
        preferredRendererType: Shape.CurveRenderer

        ShapePath {
            strokeColor: root.color
            strokeWidth: root.stroke
            fillColor: "transparent"
            capStyle: ShapePath.RoundCap
            joinStyle: ShapePath.RoundJoin
            PathSvg {
                path: Icons.paths[root.name] || "M0 0"
            }
        }
    }
}
