import QtQuick
import QtQuick.Controls

// The one touch control: at least Theme.touch square, chamfered (cutSm), label in body.
// Variants come from color/textColor/borderColor: default (panelAlt fill, strong border),
// filled (accent, signal, category colour: the border follows the fill, label bold),
// outline (panelAlt fill with a coloured border and label: Stop, Reboot, CLI Mode).
// `selected` is the toggled state: a 2px border in borderColor (the design's "selected or
// focused control gets a 2px border in its accent"). Keyboard focus draws the 2px acid ring
// offset 2px outside the control. With `icon.name` (an Icon.qml glyph name; Button's own `icon`
// group is FINAL, so it cannot be redeclared) set and `compact` true it collapses to a square
// icon-only button; the glyph is vector geometry in the label colour.
// `command` is the command line this button runs, shown under the label in `command` type
// (the design: every button that runs a command shows it; ink-muted, or the label colour at
// 75% on a filled button; `<arg>` placeholders until a field is filled; elided when too long).
// Buttons that only change the screen leave it empty.
Button {
    id: b
    property color color: Theme.panelAlt
    property color textColor: Theme.text
    readonly property bool filled: !Qt.colorEqual(color, Theme.panelAlt)
    property color borderColor: filled ? color : Theme.borderStrong
    property bool selected: false
    property bool compact: false
    property string command: ""
    property int commandMaxWidth: Theme.s(360)
    readonly property bool iconOnly: compact && icon.name !== ""
    readonly property bool showCommand: command !== "" && !iconOnly
    // the command line's colour: muted on a plain button, the label colour on filled/outline ones
    readonly property bool coloured: !Qt.colorEqual(textColor, Theme.text)
    implicitHeight: Theme.touch
    opacity: enabled ? 1 : 0.45
    // the width this button takes with its label and command shown (the top bar sums these to
    // decide whether it can afford labels); implicitWidth is that, or a square when icon-only
    readonly property real fullWidth: Math.max(Theme.touch, Math.ceil((icon.name !== "" ? Theme.icon + Theme.space2 : 0)
                                      + Math.max(label.implicitWidth, command !== "" ? Math.min(cmd.implicitWidth, commandMaxWidth) : 0)) + Theme.space4 * 2)
    implicitWidth: iconOnly ? Theme.touch : fullWidth
    font.pixelSize: Theme.fontSize
    font.family: Theme.fontSans
    font.bold: filled || selected
    background: Item {
        Chamfer {   // focus ring
            visible: b.visualFocus
            anchors.fill: parent; anchors.margins: -Theme.s(4)
            cut: Theme.cutSm + Theme.s(4)
            color: "transparent"; borderColor: Theme.focus; borderWidth: 2
        }
        Chamfer {
            anchors.fill: parent
            cut: Theme.cutSm
            color: b.down ? Qt.lighter(b.color, b.filled ? 1.15 : 1.6) : b.color
            borderColor: b.borderColor
            borderWidth: b.selected ? 2 : 1
        }
    }
    contentItem: Item {
        Row {
            id: row
            anchors.centerIn: parent
            spacing: Theme.space2
            Icon {
                visible: b.icon.name !== ""
                name: b.icon.name
                color: b.textColor
                width: Theme.icon; height: Theme.icon
                anchors.verticalCenter: parent.verticalCenter
            }
            Column {
                visible: !b.iconOnly
                anchors.verticalCenter: parent.verticalCenter
                spacing: Theme.s(2)
                Text {
                    id: label
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: b.text
                    font: b.font
                    color: b.textColor
                    elide: Text.ElideRight
                }
                Text {   // the command line, in `command` type: regular, untracked, never uppercased
                    id: cmd
                    visible: b.showCommand
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: Math.min(implicitWidth, b.commandMaxWidth)
                    text: b.command
                    elide: Text.ElideRight
                    font.family: Theme.fontMono; font.pixelSize: Theme.commandFont
                    font.weight: Font.Normal; font.letterSpacing: 0
                    color: b.filled || b.coloured ? b.textColor : Theme.muted
                    opacity: b.filled ? 0.75 : (b.coloured ? 0.8 : 1)
                }
            }
        }
    }
}
