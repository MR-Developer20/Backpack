import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

// Form generated from the selected command's args. Exposes values() for the runner.
ColumnLayout {
    id: form
    property var command
    property var fieldItems: []
    spacing: Theme.s(10)

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
            spacing: Theme.s(12)

            Text {
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
        Rectangle {
            property var row
            radius: Theme.s(8); color: Theme.panelAlt; border.color: Theme.border
            TextInput {
                anchors.fill: parent; anchors.margins: Theme.s(12)
                text: row ? String(row.modelData.default) : ""
                color: Theme.text
                font.pixelSize: Theme.fontSize
                font.family: "DejaVu Sans Mono"
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
                    implicitWidth: Theme.s(96); implicitHeight: Theme.s(44); radius: Theme.s(22)
                    color: sw.checked ? Theme.accent : Theme.panelAlt
                    border.color: Theme.border
                    Rectangle {
                        x: sw.checked ? parent.width - width - Theme.s(4) : Theme.s(4)
                        y: Theme.s(4); width: Theme.s(36); height: Theme.s(36); radius: Theme.s(18); color: Theme.text
                        Behavior on x { NumberAnimation { duration: 80 } }
                    }
                }
                contentItem: Text {
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
            spacing: Theme.s(8)
            Repeater {
                model: row ? row.modelData.options : []
                delegate: TouchButton {
                    required property var modelData
                    text: modelData
                    color: row && row.value === modelData ? Theme.accent : Theme.panelAlt
                    textColor: row && row.value === modelData ? Theme.bg : Theme.text
                    onClicked: row.value = modelData
                }
            }
        }
    }
}
