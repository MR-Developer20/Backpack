import QtQuick

Rectangle {
    id: tile
    property var tool
    property bool selected: false
    signal tapped()
    width: Theme.tileW - 12
    height: Theme.tileH - 12
    radius: 14
    color: selected ? Qt.darker(Theme.categoryColor(tool.category), 2.2) : Theme.panel
    border.color: selected ? Theme.categoryColor(tool.category) : Theme.border
    border.width: selected ? 3 : 1

    Rectangle {
        width: 10; height: parent.height - 28; x: 12; y: 14; radius: 5
        color: Theme.categoryColor(tool.category)
    }
    Column {
        anchors { left: parent.left; right: parent.right; top: parent.top; leftMargin: 32; rightMargin: 12; topMargin: 14 }
        spacing: 6
        Text {
            width: parent.width
            text: tool.name
            color: Theme.text
            font.pixelSize: Theme.fontSize + 2
            font.bold: true
            elide: Text.ElideRight
        }
        Text {
            width: parent.width
            text: tool.description
            color: Theme.muted
            font.pixelSize: Theme.smallFont
            wrapMode: Text.WordWrap
            maximumLineCount: 3
            elide: Text.ElideRight
        }
    }
    Text {
        anchors { right: parent.right; bottom: parent.bottom; margins: 10 }
        text: tool.gui ? "GUI" : (tool.commands.length + (tool.commands.length === 1 ? " action" : " actions"))
        color: Theme.muted
        font.pixelSize: 13
    }
    MouseArea { anchors.fill: parent; onClicked: tile.tapped() }
}
