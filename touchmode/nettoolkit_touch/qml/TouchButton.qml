import QtQuick
import QtQuick.Controls

Button {
    id: b
    property color color: Theme.panelAlt
    property color textColor: Theme.text
    implicitHeight: Theme.touch
    implicitWidth: Math.max(Theme.touch * 2, label.implicitWidth + 36)
    font.pixelSize: Theme.fontSize
    background: Rectangle {
        radius: 10
        color: b.down ? Qt.lighter(b.color, 1.3) : b.color
        border.color: Theme.border
        border.width: 1
    }
    contentItem: Text {
        id: label
        text: b.text
        font: b.font
        color: b.textColor
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
        elide: Text.ElideRight
    }
}
