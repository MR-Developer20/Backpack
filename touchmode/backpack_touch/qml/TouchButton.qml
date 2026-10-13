import QtQuick
import QtQuick.Controls

// Large touch target. With `iconSource` set and `compact` true it collapses to a square icon-only
// button (used when the launcher is narrow: split view or portrait).
Button {
    id: b
    property color color: Theme.panelAlt
    property color textColor: Theme.text
    property string iconSource: ""
    property bool compact: false
    readonly property bool iconOnly: compact && iconSource !== ""
    implicitHeight: Theme.touch
    opacity: enabled ? 1 : 0.45
    implicitWidth: iconOnly ? Theme.touch : Math.max(Theme.touch * 2, row.implicitWidth + Theme.s(36))
    font.pixelSize: Theme.fontSize
    background: Rectangle {
        radius: Theme.s(10)
        color: b.down ? Qt.lighter(b.color, 1.3) : b.color
        border.color: Theme.border
        border.width: 1
    }
    contentItem: Item {
        Row {
            id: row
            anchors.centerIn: parent
            spacing: Theme.s(10)
            Image {
                visible: b.iconSource !== ""
                source: b.iconSource
                width: Theme.icon; height: Theme.icon
                sourceSize.width: 96; sourceSize.height: 96
                fillMode: Image.PreserveAspectFit
                anchors.verticalCenter: parent.verticalCenter
            }
            Text {
                visible: !b.iconOnly
                text: b.text
                font: b.font
                color: b.textColor
                verticalAlignment: Text.AlignVCenter
                anchors.verticalCenter: parent.verticalCenter
                elide: Text.ElideRight
            }
        }
    }
}
