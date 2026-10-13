import QtQuick
import QtQuick.Controls

// The one touch control: at least Theme.touch square, chamfered (cutSm), label in body.
// Variants come from color/textColor/borderColor: default (panelAlt fill, strong border),
// filled (accent, signal, category colour: the border follows the fill, label bold),
// outline (panelAlt fill with a coloured border and label: Stop, Reboot, CLI Mode).
// With `iconSource` set and `compact` true it collapses to a square icon-only button.
Button {
    id: b
    property color color: Theme.panelAlt
    property color textColor: Theme.text
    readonly property bool filled: !Qt.colorEqual(color, Theme.panelAlt)
    property color borderColor: filled ? color : Theme.borderStrong
    property string iconSource: ""
    property bool compact: false
    readonly property bool iconOnly: compact && iconSource !== ""
    implicitHeight: Theme.touch
    opacity: enabled ? 1 : 0.45
    implicitWidth: iconOnly ? Theme.touch : Math.max(Theme.touch, Math.ceil(row.implicitWidth) + Theme.space4 * 2)
    font.pixelSize: Theme.fontSize
    font.family: Theme.fontSans
    font.bold: filled
    background: Chamfer {
        cut: Theme.cutSm
        color: b.down ? Qt.lighter(b.color, b.filled ? 1.15 : 1.6) : b.color
        borderColor: b.visualFocus ? Theme.focus : b.borderColor
    }
    contentItem: Item {
        Row {
            id: row
            anchors.centerIn: parent
            spacing: Theme.space2
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
