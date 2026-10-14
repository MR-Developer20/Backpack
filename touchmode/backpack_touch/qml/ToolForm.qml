import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

// Form generated from the selected command's args. Exposes values() for the runner and emits
// changed() whenever a value is edited, so the command line shown next to Run can follow.
ColumnLayout {
    id: form
    property var command
    property var fieldItems: []
    signal changed()
    spacing: Theme.space2
    onCommandChanged: Qt.callLater(changed)

    function values() {
        var v = {}
        for (var i = 0; i < repeater.count; i++) {
            var it = repeater.itemAt(i)
            if (it) v[it.argName] = it.value
        }
        return v
    }

    Repeater {
        id: repeater
        model: command ? command.args : []
        delegate: RowLayout {
            id: row
            required property var modelData
            property string argName: modelData.name
            property var value: modelData.type === "flag" ? (modelData.default === true) : String(modelData.default)
            Layout.fillWidth: true
            spacing: Theme.space3

            Text { font.family: Theme.fontSans
                text: modelData.label + (modelData.required ? " *" : "")   // what a person recognises, from the manifest
                color: Theme.text
                font.pixelSize: Theme.fontSize
                Layout.preferredWidth: Theme.s(150)
                elide: Text.ElideRight
            }
            Loader {   // as tall as its control: a choice row wraps when the options do not fit
                Layout.fillWidth: true
                Layout.preferredHeight: item ? Math.max(Theme.touch, Math.ceil(item.implicitHeight)) : Theme.touch
                sourceComponent: modelData.type === "flag" ? flagC : (modelData.type === "choice" ? choiceC : textC)
                onLoaded: item.row = row
            }
        }
    }

    Component {
        id: textC
        Chamfer {
            property var row
            cut: Theme.cutSm; color: Theme.panelAlt; borderColor: input.activeFocus ? Theme.focus : Theme.borderStrong; borderWidth: input.activeFocus ? 2 : 1
            TextInput {
                id: input
                anchors.fill: parent; anchors.margins: Theme.space3
                text: row ? String(row.modelData.default) : ""
                color: Theme.text
                font.pixelSize: Theme.fontSize
                font.family: Theme.fontMono
                inputMethodHints: row && row.modelData.type === "int" ? Qt.ImhDigitsOnly : Qt.ImhNone
                verticalAlignment: TextInput.AlignVCenter
                clip: true
                onTextChanged: if (row) { row.value = text; form.changed() }
                onActiveFocusChanged: if (activeFocus) system.fieldFocused()   // the on-screen keyboard only for a finger or pen
            }
        }
    }
    Component {
        id: flagC
        Item {
            property var row
            Switch {   // touch tall (the hit area), chamfered track; the flag it emits beside it in command type
                id: sw
                anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter
                padding: 0; implicitHeight: Theme.touch
                checked: row ? row.modelData.default === true : false
                onToggled: if (row) { row.value = checked; form.changed() }
                indicator: Chamfer {
                    implicitWidth: Theme.s(96); implicitHeight: Theme.s(44)
                    y: Math.round((sw.height - height) / 2)   // whole pixels: no blended edge row
                    cut: Theme.cutSm
                    color: sw.checked ? Theme.accent : Theme.panelAlt
                    borderColor: sw.checked ? Theme.accent : Theme.borderStrong
                    Rectangle {
                        x: sw.checked ? parent.width - width - Theme.s(4) : Theme.s(4)
                        y: Theme.s(4); width: Theme.s(36); height: Theme.s(36); color: sw.checked ? Theme.bg : Theme.text
                        Behavior on x { NumberAnimation { duration: 80 } }
                    }
                }
                contentItem: Text {
                    leftPadding: sw.indicator.width + Theme.s(12)
                    text: sw.checked ? (row ? row.modelData.flag : "on") : "off"
                    color: Theme.muted; font.family: Theme.fontMono; font.pixelSize: Theme.commandFont
                    font.weight: Font.Normal; font.letterSpacing: 0
                    verticalAlignment: Text.AlignVCenter
                }
            }
        }
    }
    Component {
        id: choiceC
        Flow {
            property var row
            spacing: Theme.space2
            Repeater {
                model: row ? row.modelData.options : []
                delegate: Chip {   // one value each; selected = the 2px accent border, not a second primary
                    required property var modelData
                    text: modelData
                    selected: row && row.value === modelData
                    onClicked: { row.value = modelData; form.changed() }
                }
            }
        }
    }
}
