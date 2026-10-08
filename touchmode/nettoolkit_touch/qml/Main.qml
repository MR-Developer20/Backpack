import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Window

ApplicationWindow {
    id: win
    visible: true
    // Windowed, not FullScreen: sway tiles this borderless window to fill the screen, so the
    // Split/Terminal buttons can tile a foot terminal beside it. (Qt-on-Wayland may still mark
    // the toplevel fullscreen when its size matches the output, so those handlers also run
    // `swaymsg fullscreen disable` before spawning foot.)
    visibility: Window.Windowed
    width: 1280; height: 800
    color: Theme.bg
    title: "NetToolkit Live"

    property string category: (manifest && manifest.categories.length) ? manifest.categories[0].id : ""
    property var tool: null
    property int cmdIndex: 0
    property string confirmAction: ""

    function selectTool(t) { tool = t; cmdIndex = 0; status.text = "" }
    function toolById(id) {
        if (!manifest) return null
        for (var i = 0; i < manifest.tools.length; i++) if (manifest.tools[i].id === id) return manifest.tools[i]
        return null
    }
    function runCurrent() {
        if (!tool) return
        output.clear()
        runner.run(tool.id, cmdIndex, form.values())
    }

    Connections {
        target: runner
        function onOutput(s) { output.append(s) }
        function onStarted(cl) { status.text = "$ " + cl; output.append("$ " + cl + "\n") }
        function onFinished(code) { output.append("\n[exit " + code + "]\n") }
        function onError(e) { status.text = "error: " + e; output.append("error: " + e + "\n") }
    }

    // ---------------------------------------------------------------- top bar
    header: Rectangle {
        height: 84
        color: Theme.panel
        RowLayout {
            anchors.fill: parent
            anchors.margins: 10
            spacing: 10
            Text { text: "NetToolkit Live"; color: Theme.text; font.pixelSize: 28; font.bold: true }
            Text { text: "Touch Mode"; color: Theme.accent; font.pixelSize: 18; Layout.leftMargin: 4 }
            Item { Layout.fillWidth: true }
            TouchButton { text: "Terminal"; onClicked: system.openTerminal() }
            TouchButton { text: "Split"; onClicked: system.splitTerminal() }
            TouchButton { text: "Reboot"; color: "#3a3f2a"; onClicked: confirmAction = "reboot" }
            TouchButton { text: "Shutdown"; color: "#4a2328"; onClicked: confirmAction = "poweroff" }
        }
    }

    // ---------------------------------------------------------------- body
    RowLayout {
        anchors.fill: parent
        anchors.margins: 10
        spacing: 10

        // left: categories + tiles
        ColumnLayout {
            Layout.preferredWidth: Math.round(win.width * 0.5)
            Layout.maximumWidth: Math.round(win.width * 0.5)
            Layout.minimumWidth: 0
            Layout.fillHeight: true
            spacing: 10
            Flow {
                Layout.fillWidth: true
                Layout.minimumWidth: 0
                Layout.preferredWidth: 0
                spacing: 8
                Repeater {
                    model: manifest ? manifest.categories : []
                    delegate: TouchButton {
                        required property var modelData
                        text: modelData.label
                        color: win.category === modelData.id ? Theme.categoryColor(modelData.id) : Theme.panelAlt
                        textColor: win.category === modelData.id ? Theme.bg : Theme.text
                        onClicked: win.category = modelData.id
                    }
                }
            }
            GridView {
                id: grid
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                cellWidth: Theme.tileW
                cellHeight: Theme.tileH
                model: manifest ? manifest.tools.filter(function (t) { return t.category === win.category }) : []
                delegate: Tile {
                    required property var modelData
                    tool: modelData
                    selected: win.tool !== null && win.tool.id === modelData.id
                    onTapped: win.selectTool(modelData)
                }
                ScrollBar.vertical: ScrollBar { width: 18 }
            }
        }

        // right: tool panel
        Rectangle {
            Layout.fillWidth: true
            Layout.minimumWidth: 0
            Layout.fillHeight: true
            radius: 14
            color: Theme.panel
            border.color: Theme.border

            Text {
                visible: !win.tool
                anchors.centerIn: parent
                text: "Tap a tool to begin"
                color: Theme.muted
                font.pixelSize: 24
            }

            ColumnLayout {
                visible: !!win.tool
                anchors.fill: parent
                anchors.margins: 14
                spacing: 10

                Text { text: win.tool ? win.tool.name : ""; color: Theme.text; font.pixelSize: 26; font.bold: true }
                Text {
                    Layout.fillWidth: true
                    text: win.tool ? win.tool.description : ""
                    color: Theme.muted; font.pixelSize: Theme.smallFont; wrapMode: Text.WordWrap
                }
                Flow {
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
                    Layout.preferredWidth: 0
                    spacing: 8
                    visible: win.tool && win.tool.commands.length > 1
                    Repeater {
                        model: win.tool ? win.tool.commands : []
                        delegate: TouchButton {
                            required property int index
                            required property var modelData
                            text: modelData.label
                            color: win.cmdIndex === index ? Theme.accent : Theme.panelAlt
                            textColor: win.cmdIndex === index ? Theme.bg : Theme.text
                            onClicked: win.cmdIndex = index
                        }
                    }
                }
                Flickable {
                    Layout.fillWidth: true
                    Layout.preferredHeight: Math.min(form.implicitHeight, win.height * 0.35)
                    contentHeight: form.implicitHeight
                    clip: true
                    ToolForm {
                        id: form
                        width: parent.width
                        command: win.tool ? win.tool.commands[win.cmdIndex] : null
                    }
                }
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 10
                    TouchButton {
                        text: win.tool && win.tool.gui ? "Open" : "Run"
                        color: Theme.accent; textColor: Theme.bg
                        enabled: !runner.running
                        onClicked: win.runCurrent()
                    }
                    TouchButton { text: "Stop"; color: Theme.danger; enabled: runner.running; onClicked: runner.stop() }
                    TouchButton { text: "Clear"; onClicked: output.clear() }
                    Text {
                        visible: win.tool && win.tool.commands[win.cmdIndex].needs_root
                        text: "runs as root"; color: Theme.warn; font.pixelSize: Theme.smallFont
                    }
                    Item { Layout.fillWidth: true }
                }
                Text {
                    id: status
                    Layout.fillWidth: true
                    color: Theme.muted; font.pixelSize: 13; font.family: "DejaVu Sans Mono"; elide: Text.ElideMiddle
                }
                OutputPane {
                    id: output
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                }
            }
        }
    }

    // ---------------------------------------------------------------- confirm overlay
    Rectangle {
        visible: confirmAction !== ""
        anchors.fill: parent
        color: "#b0000000"
        MouseArea { anchors.fill: parent; onClicked: confirmAction = "" }
        Rectangle {
            anchors.centerIn: parent
            width: 520; height: 220; radius: 16
            color: Theme.panel; border.color: Theme.border
            ColumnLayout {
                anchors.fill: parent; anchors.margins: 24; spacing: 20
                Text {
                    Layout.fillWidth: true
                    text: confirmAction === "reboot" ? "Reboot the machine?" : "Shut down the machine?"
                    color: Theme.text; font.pixelSize: 26; horizontalAlignment: Text.AlignHCenter
                }
                RowLayout {
                    Layout.alignment: Qt.AlignHCenter
                    spacing: 20
                    TouchButton { text: "Cancel"; onClicked: confirmAction = "" }
                    TouchButton {
                        text: confirmAction === "reboot" ? "Reboot" : "Shut down"
                        color: Theme.danger
                        onClicked: { var a = confirmAction; confirmAction = ""; a === "reboot" ? system.reboot() : system.poweroff() }
                    }
                }
            }
        }
    }

    // ---------------------------------------------------------------- demo / screenshot automation
    Timer {
        running: demoTool !== ""
        interval: 1500
        onTriggered: { var t = toolById(demoTool); if (t) { category = t.category; selectTool(t); runTimer.start() } }
    }
    Timer { id: runTimer; interval: 1500; onTriggered: runCurrent() }
}
