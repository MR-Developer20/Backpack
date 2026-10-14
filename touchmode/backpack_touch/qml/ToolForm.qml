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
                sourceComponent: modelData.type === "flag" ? flagC : (modelData.type === "choice" ? choiceC
                                 : (modelData.type === "interface" ? ifaceC : textC))
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
    Component {
        id: ifaceC
        // An interface field: the machine's interfaces as a list that drops down under the field,
        // read again each time it opens (USB adapters come and go, monitor mode renames them).
        AbstractButton {
            id: pick
            objectName: "interfacePicker"
            property var row
            // [{name, tag}]: manifest options first (e.g. "any"), "Auto" when the field may be empty
            property var entries: []
            function refresh() {
                if (!row) return
                var a = row.modelData, list = []
                if (!a.required) list.push({ name: "", tag: "THE TOOL CHOOSES" })
                for (var i = 0; i < a.options.length; i++) list.push({ name: a.options[i], tag: a.options[i] === "any" ? "ALL INTERFACES" : "" })
                var found = manifest.interfaces(a.kind)
                for (var j = 0; j < found.length; j++) {
                    var f = found[j]
                    list.push({ name: f.name, tag: ({ wifi: "WI-FI", monitor: "WI-FI // MONITOR", wired: "WIRED", other: "VIRTUAL" })[f.kind] + (f.up ? " // UP" : " // DOWN") })
                }
                entries = list
            }
            function tagOf(v) {
                for (var i = 0; i < entries.length; i++) if (entries[i].name === v) return entries[i].tag
                return ""
            }
            function choose(v) { if (row) { row.value = v; form.changed() } }
            onRowChanged: {
                refresh()
                if (!row) return
                var d = String(row.modelData.default), have = entries.some(function (e) { return e.name === d })
                // the manifest default when it exists here, else the first real interface (up ones are listed first)
                var hw = entries.filter(function (e) { return e.name !== "" && row.modelData.options.indexOf(e.name) < 0 })
                choose(have ? d : (hw.length ? hw[0].name : (entries.length ? entries[0].name : "")))
            }
            onClicked: { refresh(); popup.open() }
            padding: 0
            activeFocusOnTab: true
            Accessible.role: Accessible.ComboBox
            Accessible.name: (row ? row.modelData.label : "") + ": " + (row && row.value !== "" ? row.value : "auto")
            Keys.onReturnPressed: clicked()
            Keys.onEnterPressed: clicked()
            background: Item {
                Chamfer {   // focus ring
                    visible: pick.visualFocus
                    anchors.fill: parent; anchors.margins: -Theme.s(4)
                    cut: Theme.cutSm + Theme.s(4)
                    color: "transparent"; borderColor: Theme.focus; borderWidth: 2
                }
                Chamfer {
                    anchors.fill: parent
                    cut: Theme.cutSm; color: pick.down ? Qt.lighter(Theme.panelAlt, 1.6) : Theme.panelAlt
                    borderColor: popup.visible ? Theme.accent : Theme.borderStrong; borderWidth: popup.visible ? 2 : 1
                }
            }
            contentItem: RowLayout {
                spacing: Theme.space3
                Text {
                    readonly property bool none: !pick.row || (pick.row.value === "" && pick.row.modelData.required)
                    text: none ? (pick.row && pick.row.modelData.kind === "wired" ? "No wired interface found"
                                  : (pick.row && (pick.row.modelData.kind === "wifi" || pick.row.modelData.kind === "monitor")
                                     ? "No Wi-Fi interface found" : "No interface found"))
                          : (pick.row.value === "" ? "Auto" : pick.row.value)
                    color: none ? Theme.muted : Theme.text
                    font.family: Theme.fontMono; font.pixelSize: Theme.fontSize
                    elide: Text.ElideRight; Layout.fillWidth: true; Layout.leftMargin: Theme.space3
                }
                Text {   // what the chosen entry is, in the micro strip type
                    text: pick.row ? pick.tagOf(pick.row.value) : ""
                    color: Theme.muted
                    font.family: Theme.fontSans; font.pixelSize: Theme.microFont; font.weight: Font.Medium; font.letterSpacing: Theme.microFont * 0.16
                }
                Text {
                    text: "CHANGE"; color: Theme.accent
                    font.family: Theme.fontSans; font.pixelSize: Theme.microFont; font.weight: Font.Medium; font.letterSpacing: Theme.microFont * 0.16
                    Layout.rightMargin: Theme.space3
                }
            }

            Popup {
                id: popup
                y: pick.height + Theme.space1
                width: pick.width
                margins: Theme.space2   // stays inside the window; moves up when there is no room below
                padding: Theme.space2
                height: Math.min(implicitHeight, Theme.touch * 5 + Theme.space2 * 6)
                background: Chamfer { cut: Theme.cutMd; color: Theme.panel; borderColor: Theme.borderStrong }
                contentItem: ListView {
                    id: list
                    clip: true
                    implicitHeight: contentHeight
                    spacing: Theme.space2
                    model: pick.entries
                    ScrollBar.vertical: BpScrollBar {}
                    delegate: AbstractButton {
                        id: opt
                        required property var modelData
                        readonly property bool on: pick.row && pick.row.value === modelData.name
                        width: list.width - (list.contentHeight > list.height ? Theme.s(18) : 0); height: Theme.touch   // clear of the scroll bar
                        padding: 0
                        background: Chamfer {
                            cut: Theme.cutSm; color: opt.down ? Qt.lighter(Theme.panelAlt, 1.6) : Theme.panelAlt
                            borderColor: opt.on ? Theme.accent : Theme.borderStrong; borderWidth: opt.on ? 2 : 1
                        }
                        contentItem: RowLayout {
                            spacing: Theme.space3
                            Text {
                                text: opt.modelData.name === "" ? "Auto" : opt.modelData.name
                                color: opt.on ? Theme.accent : Theme.text
                                font.family: Theme.fontMono; font.pixelSize: Theme.fontSize
                                elide: Text.ElideRight; Layout.fillWidth: true; Layout.leftMargin: Theme.space3
                            }
                            Text {
                                text: opt.modelData.tag; color: Theme.muted
                                font.family: Theme.fontSans; font.pixelSize: Theme.microFont; font.weight: Font.Medium; font.letterSpacing: Theme.microFont * 0.16
                                Layout.rightMargin: Theme.space3
                            }
                        }
                        onClicked: { pick.choose(modelData.name); popup.close() }
                    }
                }
            }
        }
    }
}
