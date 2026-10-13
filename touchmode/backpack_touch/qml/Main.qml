import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Window

ApplicationWindow {
    id: win
    visible: true
    // Windowed, not FullScreen: sway tiles this borderless window to fill the screen, so the
    // Split button can tile a foot terminal beside/below it. (Qt-on-Wayland may still mark the
    // toplevel fullscreen when its size matches the output, so handlers run
    // `swaymsg fullscreen disable` before spawning foot.)
    visibility: Window.Windowed
    width: 1280; height: 800
    color: Theme.bg
    title: "Backpack Live"

    // layout modes: narrow (split view or portrait) -> icon-only top bar; portrait -> stacked panes
    readonly property bool portrait: height > width
    readonly property bool compact: width < Theme.s(1100)   // icon-only tool buttons when narrow (or UI size is large)
    property string section: (manifest && manifest.sections.length) ? manifest.sections[0].id : "network"
    property string category: firstCategory(section)
    property var tool: null
    property int cmdIndex: 0
    property string confirmAction: ""
    property bool wifiOpen: false
    property bool settingsOpen: false

    Binding { target: Theme; property: "scale"; value: settings ? settings.uiScale : 1.0 }

    function sectionCategories(sec) {
        return manifest ? manifest.categories.filter(function (c) { return c.section === sec }) : []
    }
    function firstCategory(sec) { var c = sectionCategories(sec); return c.length ? c[0].id : "" }
    function selectSection(sec) { section = sec; category = firstCategory(sec) }

    function selectTool(t) { cmdIndex = 0; tool = t; status.text = "" }   // reset cmdIndex first: bindings index tool.commands[cmdIndex]
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
        height: Theme.barH
        color: Theme.panel
        RowLayout {
            anchors.fill: parent
            anchors.margins: Theme.gap
            spacing: win.compact ? Theme.s(6) : Theme.gap
            Text { visible: !win.portrait || win.width >= Theme.s(900); text: win.compact ? "Backpack" : "Backpack Live"; color: Theme.text; font.pixelSize: Theme.s(28); font.bold: true }
            Text { visible: win.width >= Theme.s(1600); text: "GUI Mode"; color: Theme.accent; font.pixelSize: Theme.s(18); Layout.leftMargin: Theme.s(4) }
            // section tabs: Network / Data
            Repeater {
                model: manifest ? manifest.sections : []
                delegate: TouchButton {
                    required property var modelData
                    Layout.leftMargin: index === 0 ? Theme.gap : 0
                    required property int index
                    text: win.compact ? modelData.label : modelData.label + "  " + modelData.count
                    color: win.section === modelData.id ? Theme.accent : Theme.panelAlt
                    textColor: win.section === modelData.id ? Theme.bg : Theme.text
                    onClicked: win.selectSection(modelData.id)
                }
            }
            Item { Layout.fillWidth: true }
            TouchButton { text: "Terminal"; iconSource: "../icons/terminal.png"; compact: win.compact; onClicked: system.openTerminal() }
            TouchButton {
                text: (system && system.splitActive) ? "Exit split" : "Split"
                iconSource: (system && system.splitActive) ? "../icons/exitsplit.png" : "../icons/split.png"
                color: (system && system.splitActive) ? Theme.activeFill : Theme.panelAlt
                compact: win.compact
                onClicked: system.toggleSplit(win.portrait)
            }
            TouchButton {
                text: "Keyboard"; iconSource: "../icons/keyboard.png"; compact: win.compact
                color: (system && system.keyboardVisible) ? Theme.accent : Theme.panelAlt
                textColor: (system && system.keyboardVisible) ? Theme.bg : Theme.text
                onClicked: system.toggleKeyboard()
            }
            TouchButton { text: "Wi-Fi"; iconSource: "../icons/wifi.png"; compact: win.compact; onClicked: win.wifiOpen = true }
            TouchButton {
                text: "eDEX"; iconSource: "../icons/edex.png"; compact: win.compact
                color: Theme.edexFill
                visible: system ? system.edexAvailable() : false
                onClicked: system.launchEdex()
            }
            TouchButton {
                text: "Settings"; iconSource: "../icons/settings.png"; compact: true
                color: win.settingsOpen ? Theme.accent : Theme.panelAlt
                onClicked: { settings.refresh(); win.settingsOpen = true }
            }
        }
    }

    // ---------------------------------------------------------------- body (2 columns, or stacked in portrait)
    GridLayout {
        anchors.fill: parent
        anchors.margins: Theme.gap
        columns: win.portrait ? 1 : 2
        rowSpacing: Theme.gap; columnSpacing: Theme.gap

        // tiles pane
        ColumnLayout {
            Layout.fillWidth: win.portrait
            Layout.fillHeight: !win.portrait
            Layout.preferredWidth: win.portrait ? -1 : Math.round(win.width * 0.5)
            Layout.maximumWidth: win.portrait ? 1000000 : Math.round(win.width * 0.5)
            Layout.preferredHeight: win.portrait ? Math.round(win.height * 0.42) : -1
            Layout.minimumWidth: 0
            spacing: Theme.gap
            Flow {
                Layout.fillWidth: true
                Layout.minimumWidth: 0
                Layout.preferredWidth: 0
                spacing: Theme.s(8)
                Repeater {
                    model: win.sectionCategories(win.section)
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
                ScrollBar.vertical: ScrollBar { width: Theme.s(18) }
            }
        }

        // tool pane
        Rectangle {
            id: toolPane
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.minimumWidth: 0
            Layout.minimumHeight: 0
            radius: Theme.s(14)
            color: Theme.panel
            border.color: Theme.border

            Text {
                visible: !win.tool
                anchors.centerIn: parent
                text: "Tap a tool to begin"
                color: Theme.muted
                font.pixelSize: Theme.s(24)
            }

            ColumnLayout {
                visible: !!win.tool
                anchors.fill: parent
                anchors.margins: Theme.s(14)
                spacing: Theme.gap

                Text { text: win.tool ? win.tool.name : ""; color: Theme.text; font.pixelSize: Theme.titleFont; font.bold: true }
                Text {
                    Layout.fillWidth: true
                    text: win.tool ? win.tool.description : ""
                    color: Theme.muted; font.pixelSize: Theme.smallFont; wrapMode: Text.WordWrap
                }
                Flow {
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
                    Layout.preferredWidth: 0
                    spacing: Theme.s(8)
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
                    Layout.preferredHeight: Math.min(form.implicitHeight, toolPane.height * 0.4)
                    contentHeight: form.implicitHeight
                    clip: true
                    ToolForm {
                        id: form
                        width: parent.width
                        command: win.tool ? win.tool.commands[win.cmdIndex] : null
                    }
                }
                Flow {   // wraps when the UI size is large
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
                    Layout.preferredWidth: 0
                    spacing: Theme.gap
                    TouchButton {
                        text: win.tool && win.tool.gui ? "Open" : "Run"
                        color: Theme.accent; textColor: Theme.bg
                        enabled: !(runner && runner.running)
                        onClicked: win.runCurrent()
                    }
                    TouchButton { text: "Stop"; color: Theme.danger; enabled: !!(runner && runner.running); onClicked: runner.stop() }
                    TouchButton { text: "Clear"; onClicked: output.clear() }
                    Text {
                        visible: !!win.tool && win.cmdIndex < win.tool.commands.length && win.tool.commands[win.cmdIndex].needs_root
                        height: Theme.touch; verticalAlignment: Text.AlignVCenter
                        text: "runs as root"; color: Theme.warn; font.pixelSize: Theme.smallFont
                    }
                }
                Text {
                    id: status
                    Layout.fillWidth: true
                    color: Theme.muted; font.pixelSize: Theme.s(13); font.family: "DejaVu Sans Mono"; elide: Text.ElideMiddle
                }
                OutputPane {
                    id: output
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    Layout.minimumHeight: Theme.s(100)
                }
            }
        }
    }

    // ---------------------------------------------------------------- overlays
    WifiOverlay {
        visible: win.wifiOpen
        anchors.fill: parent
        onClosed: { win.wifiOpen = false; system.hideKeyboard() }
    }

    SettingsSheet {
        visible: win.settingsOpen
        anchors.fill: parent
        onClosed: win.settingsOpen = false
        onConfirm: function (action) { confirmAction = action }
    }

    Rectangle {
        visible: confirmAction !== ""
        anchors.fill: parent
        color: Theme.scrim
        MouseArea { anchors.fill: parent; onClicked: confirmAction = "" }
        Rectangle {
            anchors.centerIn: parent
            width: Math.min(Theme.s(560), parent.width - 40); height: confirmCol.implicitHeight + Theme.s(48); radius: Theme.s(16)
            color: Theme.panel; border.color: Theme.border
            MouseArea { anchors.fill: parent }   // swallow clicks
            ColumnLayout {
                id: confirmCol
                anchors.fill: parent; anchors.margins: Theme.s(24); spacing: Theme.s(20)
                Text {
                    Layout.fillWidth: true
                    text: confirmAction === "reboot" ? "Reboot the machine?"
                        : confirmAction === "cli" ? "Switch to CLI Mode?" : "Shut down the machine?"
                    color: Theme.text; font.pixelSize: Theme.titleFont; horizontalAlignment: Text.AlignHCenter
                }
                Text {
                    Layout.fillWidth: true
                    visible: confirmAction === "cli"
                    text: "GUI Mode closes, along with any running tools and terminals, and you get a text login on the console. Reboot to come back to GUI Mode."
                    color: Theme.muted; font.pixelSize: Theme.smallFont; wrapMode: Text.WordWrap; horizontalAlignment: Text.AlignHCenter
                }
                RowLayout {
                    Layout.alignment: Qt.AlignHCenter
                    spacing: Theme.s(20)
                    TouchButton { text: "Cancel"; onClicked: confirmAction = "" }
                    TouchButton {
                        text: confirmAction === "reboot" ? "Reboot" : confirmAction === "cli" ? "Switch" : "Shut down"
                        color: confirmAction === "cli" ? Theme.warn : Theme.danger
                        textColor: confirmAction === "cli" ? Theme.bg : Theme.text
                        onClicked: {
                            var a = confirmAction; confirmAction = ""; win.settingsOpen = false
                            if (a === "reboot") system.reboot()
                            else if (a === "cli") settings.switchToCli()
                            else system.poweroff()
                        }
                    }
                }
            }
        }
    }

    // ---------------------------------------------------------------- demo / screenshot automation
    Timer {
        running: demoTool !== ""
        interval: 1500
        onTriggered: { var t = toolById(demoTool); if (t) { section = t.section; category = t.category; selectTool(t); runTimer.start() } }
    }
    Timer { id: runTimer; interval: 1500; onTriggered: runCurrent() }
    Timer { running: demoWifi; interval: 1200; onTriggered: win.wifiOpen = true }
    Timer { running: demoSettings; interval: 1200; onTriggered: { settings.refresh(); win.settingsOpen = true } }
    Component.onCompleted: if (demoSection !== "") selectSection(demoSection)
}
