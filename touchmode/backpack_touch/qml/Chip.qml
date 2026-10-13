import QtQuick
import QtQuick.Controls

// Chip: the design's 48px chamfered control inside a touch-tall row, label in `label` type
// (uppercase, tracked) over the command it runs in `command` type, left-aligned. Used for the
// action chips in the tool pane (which command of a tool) and the choice chips in a form (one
// value of an argument; no command). Selected = the 2px accent border and an accent label.
// A real button: keyboard focus (2px acid ring, 2px outside), Space/Enter, accessible role.
// Category chips (which fill with their cat-* colour) are drawn in Main.qml.
AbstractButton {
    id: chip
    property string command: ""
    property bool selected: false
    property color accent: Theme.accent
    property int commandMaxWidth: Theme.s(360)
    padding: 0
    implicitHeight: Theme.touch
    implicitWidth: Math.ceil(Math.max(label.implicitWidth, command !== "" ? Math.min(cmd.implicitWidth, commandMaxWidth) : 0)) + Theme.space4 * 2
    activeFocusOnTab: true
    Accessible.role: Accessible.Button
    Accessible.name: text + (command !== "" ? ": " + command : "")
    Keys.onReturnPressed: clicked()
    Keys.onEnterPressed: clicked()
    background: Item {
        Chamfer {   // focus ring
            visible: chip.visualFocus
            anchors.centerIn: parent; width: parent.width + Theme.s(8); height: Theme.chipH + Theme.s(8)
            cut: Theme.cutSm + Theme.s(4)
            color: "transparent"; borderColor: Theme.focus; borderWidth: 2
        }
        Chamfer {
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width; height: Theme.chipH
            cut: Theme.cutSm
            color: chip.down ? Qt.lighter(Theme.panelAlt, 1.6) : Theme.panelAlt
            borderColor: chip.selected ? chip.accent : Theme.borderStrong
            borderWidth: chip.selected ? 2 : 1
        }
    }
    contentItem: Item {
        Column {
            anchors.left: parent.left; anchors.leftMargin: Theme.space4
            anchors.verticalCenter: parent.verticalCenter
            spacing: Theme.s(2)
            Text {
                id: label
                text: chip.text
                color: chip.selected ? chip.accent : Theme.text
                font.family: Theme.fontSans; font.pixelSize: Theme.labelFont; font.bold: true
                font.letterSpacing: Theme.labelFont * 0.14; font.capitalization: Font.AllUppercase
            }
            Text {   // the command line: regular, untracked, never uppercased; elided when too long
                id: cmd
                visible: chip.command !== ""
                width: Math.min(implicitWidth, chip.commandMaxWidth)
                text: chip.command
                elide: Text.ElideRight
                font.family: Theme.fontMono; font.pixelSize: Theme.commandFont
                font.weight: Font.Normal; font.letterSpacing: 0
                color: chip.selected ? chip.accent : Theme.muted
                opacity: chip.selected ? 0.8 : 1
            }
        }
    }
}
