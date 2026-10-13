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
    readonly property bool compact: width < Theme.s(1400)   // icon-only tool buttons when narrow (or UI size is large)
    property string section: (manifest && manifest.sections.length) ? manifest.sections[0].id : "network"
    property string category: firstCategory(section)
    property var tool: null
    // Extra-tab apps: just an Open button, no argument form or output pane
    readonly property bool appMode: !!tool && tool.section === "extra"
    property int cmdIndex: 0
    property string confirmAction: ""
    property bool wifiOpen: false
    property bool settingsOpen: false
    property bool monitorOpen: false

    Binding { target: Theme; property: "scale"; value: settings ? settings.uiScale : 1.0 }
    Binding { target: Theme; property: "section"; value: win.section }

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
        function onOutput(s) { output.append(s); if (win.appMode) status.text = s.trim() }
        function onStarted(cl) { status.text = "$ " + cl; output.append("$ " + cl + "\n") }
        function onFinished(code) { output.append("\n[exit " + code + "]\n") }
        function onError(e) { status.text = "error: " + e; output.append("error: " + e + "\n") }
    }

    // ---------------------------------------------------------------- top bar
    header: Rectangle {
        height: Theme.barH
        color: Theme.panel
        Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: Theme.border }
        RowLayout {
            anchors.fill: parent
            anchors.margins: Theme.gap
            spacing: win.compact ? Theme.s(6) : Theme.gap
            Text {   // wordmark
                visible: win.width >= Theme.s(960)   // dropped first when the bar gets tight
                text: win.compact ? "BACKPACK" : "BACKPACK//LIVE"; color: Theme.text
                font.family: Theme.fontDisplay; font.pixelSize: Theme.wordmarkFont; font.weight: Font.ExtraBold
                font.letterSpacing: Theme.wordmarkFont * 0.08
                Layout.leftMargin: Theme.space2; Layout.rightMargin: Theme.space2
            }
            // section tabs: label over a micro strip (section index // tool count), underlined when open
            Repeater {
                model: manifest ? manifest.sections : []
                delegate: Item {
                    id: tab
                    required property var modelData
                    required property int index
                    readonly property bool on: win.section === modelData.id
                    readonly property color tabAccent: modelData.id === "data" ? Theme.cyan : Theme.acid
                    Layout.fillHeight: true
                    Layout.bottomMargin: -Theme.gap
                    implicitWidth: Math.max(Theme.touch, Math.ceil(tabCol.implicitWidth) + Theme.space4 * 2)
                    Column {
                        id: tabCol
                        anchors.centerIn: parent
                        spacing: Theme.s(2)
                        Text {
                            text: tab.modelData.label.toUpperCase()
                            color: tab.on ? tab.tabAccent : Theme.muted
                            font.family: Theme.fontSans; font.pixelSize: Theme.labelFont; font.bold: true
                            font.letterSpacing: Theme.labelFont * 0.14
                        }
                        Text {
                            visible: !win.compact
                            text: "SEC." + ("0" + (tab.index + 1)).slice(-2) + " // " + tab.modelData.count
                            color: Theme.muted
                            font.family: Theme.fontSans; font.pixelSize: Theme.microFont; font.weight: Font.Medium
                            font.letterSpacing: Theme.microFont * 0.16
                        }
                    }
                    Rectangle {
                        anchors.bottom: parent.bottom; width: parent.width; height: Theme.s(3)
                        color: tab.on ? tab.tabAccent : "transparent"
                    }
                    MouseArea { anchors.fill: parent; onClicked: win.selectSection(tab.modelData.id) }
                }
            }
            Item { Layout.fillWidth: true }
            TouchButton { text: "Terminal"; iconSource: "../icons/terminal.png"; compact: win.compact; onClicked: system.openTerminal() }
            TouchButton {
                text: (system && system.splitActive) ? "Exit split" : "Split"
                iconSource: (system && system.splitActive) ? "../icons/exitsplit.png" : "../icons/split.png"
                textColor: (system && system.splitActive) ? Theme.warn : Theme.text
                borderColor: (system && system.splitActive) ? Theme.warn : Theme.borderStrong
                compact: win.compact
                onClicked: system.toggleSplit(win.portrait)
            }
            TouchButton {
                text: "Keyboard"; iconSource: "../icons/keyboard.png"; compact: win.compact
                // amber outline while the on-screen keyboard is open (caution: it covers the screen)
                textColor: (system && system.keyboardVisible) ? Theme.warn : Theme.text
                borderColor: (system && system.keyboardVisible) ? Theme.warn : Theme.borderStrong
                onClicked: system.toggleKeyboard()
            }
            TouchButton { text: "Wi-Fi"; iconSource: "../icons/wifi.png"; compact: win.compact; onClicked: win.wifiOpen = true }
            UsageMeter {
                visible: win.width >= Theme.s(880)
                compact: win.compact
                onTapped: win.monitorOpen = true
            }
            TouchButton {
                text: "Settings"; iconSource: "../icons/settings.png"; compact: true
                borderColor: win.settingsOpen ? Theme.focus : Theme.borderStrong
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
                    delegate: Item {   // category chip: 48px tall inside a touch-tall row
                        id: chip
                        required property var modelData
                        readonly property bool on: win.category === modelData.id
                        implicitHeight: Theme.touch
                        implicitWidth: Math.ceil(chipLabel.implicitWidth) + Theme.space4 * 2
                        Chamfer {
                            anchors.verticalCenter: parent.verticalCenter
                            width: parent.width; height: Theme.chipH
                            cut: Theme.cutSm
                            color: chip.on ? Theme.categoryColor(chip.modelData.id) : Theme.panelAlt
                            borderColor: chip.on ? Theme.categoryColor(chip.modelData.id) : Theme.borderStrong
                            Text {
                                id: chipLabel
                                anchors.centerIn: parent
                                text: chip.modelData.label.toUpperCase()
                                color: chip.on ? Theme.inkOnAccent : Theme.text
                                font.family: Theme.fontSans; font.pixelSize: Theme.labelFont; font.bold: true
                                font.letterSpacing: Theme.labelFont * 0.14
                            }
                        }
                        MouseArea { anchors.fill: parent; onClicked: win.category = chip.modelData.id }
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
        Chamfer {
            id: toolPane
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.minimumWidth: 0
            Layout.minimumHeight: 0
            cut: Theme.cutLg
            color: Theme.panel
            borderColor: Theme.border

            EmptyState { visible: !win.tool; anchors.fill: parent; anchors.margins: Theme.cutLg / 2 }

            ColumnLayout {
                visible: !!win.tool
                anchors.fill: parent
                anchors.margins: Theme.s(14)
                spacing: Theme.gap

                Text { font.family: Theme.fontSans; text: win.tool ? win.tool.name : ""; color: Theme.text; font.pixelSize: Theme.titleFont; font.bold: true; font.letterSpacing: Theme.titleFont * 0.02 }
                Text { font.family: Theme.fontSans
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
                            textColor: win.cmdIndex === index ? Theme.inkOnAccent : Theme.text
                            onClicked: win.cmdIndex = index
                        }
                    }
                }
                Flickable {
                    visible: !win.appMode   // the form still supplies its defaults to runCurrent()
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
                        color: Theme.accent; textColor: Theme.inkOnAccent
                        enabled: !(runner && runner.running)
                        onClicked: win.runCurrent()
                    }
                    TouchButton { visible: !win.appMode; text: "Stop"; textColor: Theme.danger; borderColor: Theme.danger; enabled: !!(runner && runner.running); onClicked: runner.stop() }
                    TouchButton { visible: !win.appMode; text: "Clear"; onClicked: output.clear() }
                    Text { font.family: Theme.fontSans
                        visible: !!win.tool && win.cmdIndex < win.tool.commands.length && win.tool.commands[win.cmdIndex].needs_root
                        height: Theme.touch; verticalAlignment: Text.AlignVCenter
                        text: "RUNS AS ROOT"; color: Theme.warn; font.pixelSize: Theme.labelFont; font.bold: true; font.letterSpacing: Theme.labelFont * 0.14
                    }
                }
                Text {
                    id: status
                    Layout.fillWidth: true
                    color: text.indexOf("error:") === 0 ? Theme.danger : Theme.muted
                    font.pixelSize: Theme.smallFont; font.family: Theme.fontMono; elide: Text.ElideMiddle
                }
                Item { visible: win.appMode; Layout.fillHeight: true }
                OutputPane {
                    id: output
                    visible: !win.appMode
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

    SysMonitorSheet {
        visible: win.monitorOpen
        anchors.fill: parent
        onClosed: win.monitorOpen = false
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
        Chamfer {   // centred on whole pixels
            x: Math.round((parent.width - width) / 2); y: Math.round((parent.height - height) / 2)
            width: Math.min(Theme.s(560), parent.width - 40); height: Math.ceil(confirmCol.implicitHeight) + Theme.s(48)
            cut: Theme.cutLg
            color: Theme.panel; borderColor: Theme.borderStrong
            MouseArea { anchors.fill: parent }   // swallow clicks
            ColumnLayout {
                id: confirmCol
                anchors.fill: parent; anchors.margins: Theme.s(24); spacing: Theme.s(20)
                Text { font.family: Theme.fontSans
                    Layout.fillWidth: true
                    text: confirmAction === "reboot" ? "Reboot the machine?"
                        : confirmAction === "cli" ? "Switch to CLI Mode?" : "Shut down the machine?"
                    color: Theme.text; font.pixelSize: Theme.titleFont; horizontalAlignment: Text.AlignHCenter
                }
                Text { font.family: Theme.fontSans
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
                        color: confirmAction === "cli" ? Theme.warn : Theme.dangerFill
                        textColor: Theme.inkOnDanger
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
    Timer { running: demoMonitor; interval: 4000; onTriggered: win.monitorOpen = true }
    Timer { running: demoSettings; interval: 1200; onTriggered: { settings.refresh(); win.settingsOpen = true } }
    Component.onCompleted: if (demoSection !== "") selectSection(demoSection)
}
