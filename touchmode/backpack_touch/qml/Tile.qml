import QtQuick

Rectangle {
    id: tile
    property var tool
    property bool selected: false
    signal tapped()
    width: Theme.tileW - 12
    height: Theme.tileH - 12
    radius: Theme.radiusLarge
    // Field Terminal: selected = signal-dim fill with a signal edge; previous look: the category hue
    color: selected ? (Theme.ft ? Theme.accentDim : Qt.darker(Theme.categoryColor(tool.category), 2.2)) : Theme.panel
    border.color: selected ? (Theme.ft ? Theme.accent : Theme.categoryColor(tool.category)) : Theme.border
    border.width: selected ? (Theme.ft ? 2 : 3) : 1

    Rectangle {
        width: Theme.s(Theme.ft ? 6 : 10); height: parent.height - Theme.s(28); x: Theme.s(12); y: Theme.s(14); radius: Theme.ft ? 0 : Theme.s(5)
        color: Theme.categoryColor(tool.category)
    }
    Column {
        anchors { left: parent.left; right: parent.right; top: parent.top; leftMargin: Theme.s(32); rightMargin: Theme.s(12); topMargin: Theme.s(14) }
        spacing: Theme.s(6)
        Text { font.family: Theme.fontSans
            width: parent.width
            text: tool.name
            color: Theme.text
            font.pixelSize: Theme.s(22)
            font.bold: true
            elide: Text.ElideRight
        }
        Text { font.family: Theme.fontSans
            width: parent.width
            text: tool.description
            color: Theme.muted
            font.pixelSize: Theme.smallFont
            wrapMode: Text.WordWrap
            maximumLineCount: 3
            elide: Text.ElideRight
        }
    }
    Text { font.family: Theme.fontSans
        anchors { right: parent.right; bottom: parent.bottom; margins: Theme.s(10) }
        text: tool.gui ? "GUI" : (tool.commands.length + (tool.commands.length === 1 ? " action" : " actions"))
        color: Theme.muted
        font.pixelSize: Theme.s(13)
    }
    MouseArea { anchors.fill: parent; onClicked: tile.tapped() }
}
