import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

// Form generated from the selected command's args. Exposes values() for the runner.
ColumnLayout {
    id: form
    property var command
    property var fieldItems: []
    spacing: Theme.space2

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
                text: modelData.name + (modelData.required ? " *" : "")
                color: Theme.text
                font.pixelSize: Theme.fontSize
                Layout.preferredWidth: Theme.s(150)
                elide: Text.ElideRight
            }
            Loader {
                Layout.fillWidth: true
                Layout.preferredHeight: Theme.touch
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
                onTextChanged: if (row) row.value = text
                onActiveFocusChanged: if (activeFocus) system.showKeyboard()
            }
        }
    }
    Component {
        id: flagC
        Item {
            property var row
            Switch {
                id: sw
                anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter
                checked: row ? row.modelData.default === true : false
                onToggled: if (row) row.value = checked
                indicator: Rectangle {
                    implicitWidth: Theme.s(96); implicitHeight: Theme.s(44)
                    color: sw.checked ? Theme.accent : Theme.panelAlt
                    border.color: sw.checked ? Theme.accent : Theme.borderStrong
                    Rectangle {
                        x: sw.checked ? parent.width - width - Theme.s(4) : Theme.s(4)
                        y: Theme.s(4); width: Theme.s(36); height: Theme.s(36); color: sw.checked ? Theme.bg : Theme.text
                        Behavior on x { NumberAnimation { duration: 80 } }
                    }
                }
                contentItem: Text { font.family: Theme.fontSans
                    leftPadding: sw.indicator.width + Theme.s(12)
                    text: sw.checked ? (row ? row.modelData.flag : "on") : "off"
                    color: Theme.muted; font.pixelSize: Theme.fontSize
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
                delegate: TouchButton {
                    required property var modelData
                    text: modelData
                    selected: row && row.value === modelData   // 2px accent border, not a second primary
                    textColor: selected ? Theme.accent : Theme.text
                    borderColor: selected ? Theme.accent : Theme.borderStrong
                    onClicked: row.value = modelData
                }
            }
        }
    }
}
