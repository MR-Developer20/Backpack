import QtQuick

// One tool in the launcher grid: category rail, name, two-line description, metadata strip.
// Rest: hull fill, grid border. Selected: hull-raised fill, 2px border in the category colour.
Chamfer {
    id: tile
    property var tool
    property bool selected: false
    signal tapped()
    readonly property color cat: Theme.categoryColor(tool.category)
    width: Theme.tileW - Theme.space3
    height: Theme.tileH - Theme.space3
    cut: Theme.cutMd
    color: selected ? Theme.panelAlt : Theme.panel
    borderColor: selected ? cat : Theme.border
    borderWidth: selected ? 2 : 1   // a selected control gets a 2px border in its accent

    function meta() {
        if (tool.gui) return "GUI"
        var cmds = tool.commands, root = cmds.length > 0, tty = cmds.length > 0
        for (var i = 0; i < cmds.length; i++) { root = root && !!cmds[i].needs_root; tty = tty && !!cmds[i].tty }
        if (root || tty) return [root ? "ROOT" : "", tty ? "TTY" : ""].filter(Boolean).join(" // ")
        return cmds.length + (cmds.length === 1 ? " ACTION" : " ACTIONS")
    }

    Rectangle {
        x: Theme.space3; y: Theme.space3
        width: Theme.rail; height: parent.height - Theme.space3 * 2
        color: tile.cat
    }
    Column {
        anchors { left: parent.left; right: parent.right; top: parent.top; leftMargin: Theme.space3 * 2 + Theme.rail; rightMargin: Theme.space3; topMargin: Theme.space3 }
        spacing: Theme.space1
        Text {
            width: parent.width
            text: tool.name
            color: Theme.text
            font.family: Theme.fontSans; font.pixelSize: Theme.tileNameFont; font.bold: true
            elide: Text.ElideRight
        }
        Text {
            width: parent.width
            text: tool.description
            color: Theme.muted
            font.family: Theme.fontSans; font.pixelSize: Theme.smallFont
            wrapMode: Text.WordWrap
            maximumLineCount: 2
            elide: Text.ElideRight
        }
    }
    Text {
        anchors { right: parent.right; bottom: parent.bottom; rightMargin: Theme.space3; bottomMargin: Theme.space2 }
        text: tile.meta()
        color: Theme.muted
        font.family: Theme.fontSans; font.pixelSize: Theme.microFont; font.weight: Font.Medium
        font.letterSpacing: Theme.microFont * 0.16
    }
    MouseArea { anchors.fill: parent; onClicked: tile.tapped() }
}
