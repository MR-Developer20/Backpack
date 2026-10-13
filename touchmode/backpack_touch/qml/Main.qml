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

    // layout modes: portrait -> stacked panes. The top bar is measured, not thresholded: it shows the
    // tool buttons with label + command line when their full widths fit beside the wordmark, the tabs
    // and the gear (`compact` = they do not: icon-only buttons), then spends what is left on the
    // "//LIVE" half of the wordmark and the meter's percentages, in that order. Every term is an
    // implicit width that does not depend on the tier chosen, so there is no binding loop.
    readonly property bool portrait: height > width
    readonly property real barLabels: Theme.gap * 2 + Theme.space2 * 2 + wmShort.advanceWidth + tabs.implicitWidth
                                      + termBtn.fullWidth + splitBtn.fullWidth + kbdBtn.fullWidth + wifiBtn.fullWidth
                                      + meter.compactWidth + Theme.touch + Theme.gap * 8 + Theme.space4
    readonly property real barWordmark: barLabels + (wmLong.advanceWidth - wmShort.advanceWidth)
    readonly property real barMeter: barWordmark + (meter.fullWidth - meter.compactWidth)
    readonly property bool compact: width < barLabels
    TextMetrics { id: wmShort; text: "BACKPACK"; font.family: Theme.fontDisplay; font.pixelSize: Theme.wordmarkFont; font.weight: Font.ExtraBold; font.letterSpacing: Theme.wordmarkFont * 0.08 }
    TextMetrics { id: wmLong; text: "BACKPACK//LIVE"; font: wmShort.font }
    property string section: (manifest && manifest.sections.length) ? manifest.sections[0].id : "network"
    property string category: firstCategory(section)
    property var tool: null
    // Extra-tab apps: just an Open button, no argument form or output pane
    readonly property bool appMode: !!tool && tool.section === "extra"
    property int cmdIndex: 0
    property bool wifiOpen: false
    property bool settingsOpen: false
    property bool monitorOpen: false
    property string runState: ""     // the status strip: LAUNCHED / RUNNING / EXIT n / ERROR // ...
    property string runLine: ""      // the command line Run will execute, as the form stands

    Binding { target: Theme; property: "scale"; value: settings ? settings.uiScale : 1.0 }
    Binding { target: Theme; property: "section"; value: win.section }

    function sectionCategories(sec) {
        return manifest ? manifest.categories.filter(function (c) { return c.section === sec }) : []
    }
    function firstCategory(sec) { var c = sectionCategories(sec); return c.length ? c[0].id : "" }
    // switching section resets the chip to its first category and keeps the open tool only if it belongs there
    function selectSection(sec) { section = sec; category = firstCategory(sec); if (tool && tool.section !== sec) tool = null }

    function selectTool(t) { cmdIndex = 0; tool = t; runState = "" }   // reset cmdIndex first: bindings index tool.commands[cmdIndex]
    // the command Run will execute with the form's current values; `<arg>` placeholders while a
    // required field is empty (the runner reports that as an error)
    function updateRunLine() {
        if (!tool || !runner || cmdIndex >= tool.commands.length) { runLine = ""; return }
        var line = runner.commandLine(tool.id, cmdIndex, form.values())
        runLine = line.indexOf("error:") === 0 ? tool.commands[cmdIndex].template : line
    }
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
        // the status strip states facts in micro caps; the pane itself echoes the command line
        function onOutput(s) { output.append(s); if (win.appMode) win.runState = "LAUNCHED" }
        function onStarted(cl) { win.runState = "RUNNING"; output.append("$ " + cl + "\n") }
        function onFinished(code) { win.runState = "EXIT " + code; output.append("\n[exit " + code + "]\n") }
        function onError(e) { win.runState = "ERROR // " + e; output.append("error: " + e + "\n") }
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
            Text {   // wordmark: "//LIVE" only once the labelled buttons fit; dropped entirely when narrow
                visible: win.width >= Theme.s(960)
                text: win.width >= win.barWordmark ? "BACKPACK//LIVE" : "BACKPACK"; color: Theme.text
                font.family: Theme.fontDisplay; font.pixelSize: Theme.wordmarkFont; font.weight: Font.ExtraBold
                font.letterSpacing: Theme.wordmarkFont * 0.08
                Layout.leftMargin: Theme.space2; Layout.rightMargin: Theme.space2
            }
            // section tabs: label over a micro strip (section index // tool count), underlined when open
            Item {
                id: tabs
                Layout.fillHeight: true
                Layout.bottomMargin: -Theme.gap   // the underline sits on the bar's bottom edge
                implicitWidth: tabRow.implicitWidth
                Row {
                    id: tabRow
                    height: parent.height
                    spacing: Theme.gap
                    Repeater {
                        model: manifest ? manifest.sections : []
                        delegate: Item {
                            id: tab
                            required property var modelData
                            required property int index
                            readonly property bool on: win.section === modelData.id
                            readonly property color tabAccent: modelData.id === "data" ? Theme.cyan : Theme.acid
                            height: tabRow.height
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
                                Text {   // micro strip: always shown, stays ink-muted on the active tab
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
                }
            }
            Item { Layout.fillWidth: true }
            TouchButton {
                id: termBtn
                text: "Terminal"; icon.name: "terminal"; compact: win.compact
                command: "foot --app-id backpack-term"
                onClicked: system.openTerminal()
            }
            TouchButton {
                id: splitBtn
                text: (system && system.splitActive) ? "Exit split" : "Split"
                icon.name: (system && system.splitActive) ? "exitsplit" : "split"
                command: (system && system.splitActive) ? "swaymsg '[app_id=backpack-split] kill'" : "foot --app-id backpack-split"
                selected: !!(system && system.splitActive)
                textColor: selected ? Theme.accent : Theme.text
                borderColor: selected ? Theme.accent : Theme.borderStrong
                compact: win.compact
                onClicked: system.toggleSplit(win.portrait)
            }
            TouchButton {
                id: kbdBtn
                text: "Keyboard"; icon.name: "keyboard"; compact: win.compact
                command: (system && system.keyboardVisible) ? "pkill -USR1 -x wvkbd-mobintl" : "pkill -USR2 -x wvkbd-mobintl"
                // amber while the on-screen keyboard is open: caution, it covers the screen
                selected: !!(system && system.keyboardVisible)
                textColor: selected ? Theme.warn : Theme.text
                borderColor: selected ? Theme.warn : Theme.borderStrong
                onClicked: system.toggleKeyboard()
            }
            TouchButton { id: wifiBtn; text: "Wi-Fi"; icon.name: "wifi"; compact: win.compact; onClicked: win.wifiOpen = true }
            UsageMeter {   // percentages only once the wordmark is whole; dropped entirely when narrow
                id: meter
                visible: win.width >= Theme.s(880)
                compact: win.width < win.barMeter
                onTapped: win.monitorOpen = true
            }
            TouchButton {
                text: "Settings"; icon.name: "settings"; compact: true
                selected: win.settingsOpen; borderColor: selected ? Theme.accent : Theme.borderStrong
                onClicked: { settings.refresh(); win.settingsOpen = true }
            }
        }
    }

    // ---------------------------------------------------------------- body (2 columns, or stacked in portrait)
    GridLayout {
        anchors.fill: parent
        anchors.margins: Theme.space2
        columns: win.portrait ? 1 : 2
        rowSpacing: Theme.space4; columnSpacing: Theme.space4   // gap between panes

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
                spacing: Theme.space2
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
                ScrollBar.vertical: BpScrollBar {}
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
                anchors.margins: Theme.space4   // panel padding
                spacing: Theme.space2

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
                    spacing: Theme.space2
                    visible: win.tool && win.tool.commands.length > 1
                    Repeater {
                        model: win.tool ? win.tool.commands : []
                        delegate: TouchButton {
                            required property int index
                            required property var modelData
                            text: modelData.label
                            command: modelData.template
                            // the chosen action: 2px accent border and accent label; Run stays the one primary
                            selected: win.cmdIndex === index
                            textColor: selected ? Theme.accent : Theme.text
                            borderColor: selected ? Theme.accent : Theme.borderStrong
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
                        onChanged: win.updateRunLine()
                    }
                }
                Flow {   // wraps when the UI size is large
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
                    Layout.preferredWidth: 0
                    spacing: Theme.gap
                    TouchButton {
                        text: win.tool && win.tool.gui ? "Open" : "Run"
                        command: win.runLine
                        color: Theme.accent; textColor: Theme.inkOnAccent
                        enabled: !(runner && runner.running)
                        onClicked: win.runCurrent()
                    }
                    TouchButton {
                        visible: !win.appMode; text: "Stop"; textColor: Theme.danger; borderColor: Theme.danger
                        command: "kill -TERM " + ((runner && runner.running) ? runner.pid : "<pid>")
                        enabled: !!(runner && runner.running); onClicked: runner.stop()
                    }
                    TouchButton { visible: !win.appMode; text: "Clear"; onClicked: output.clear() }
                    Text { font.family: Theme.fontSans
                        visible: !!win.tool && win.cmdIndex < win.tool.commands.length && win.tool.commands[win.cmdIndex].needs_root
                        height: Theme.touch; verticalAlignment: Text.AlignVCenter
                        text: "RUNS AS ROOT"; color: Theme.warn; font.pixelSize: Theme.labelFont; font.bold: true; font.letterSpacing: Theme.labelFont * 0.14
                    }
                }
                RowLayout {   // the command Run will execute (phosphor), then the status strip
                    Layout.fillWidth: true
                    spacing: Theme.space4
                    Text {
                        Layout.fillWidth: true
                        text: win.runLine !== "" ? "$ " + win.runLine : ""
                        color: Theme.outputInk; font.family: Theme.fontMono; font.pixelSize: Theme.smallFont; elide: Text.ElideRight
                    }
                    Text {   // status strip: micro caps, ink-muted; errors in signal
                        id: status
                        readonly property bool root: !!win.tool && win.cmdIndex < win.tool.commands.length && win.tool.commands[win.cmdIndex].needs_root
                        Layout.maximumWidth: Theme.s(480)
                        text: win.runState + (win.runState !== "" && root ? " // ROOT" : "")
                        color: text.indexOf("ERROR") === 0 ? Theme.danger : Theme.muted
                        font.family: Theme.fontSans; font.pixelSize: Theme.microFont; font.weight: Font.Medium
                        font.letterSpacing: Theme.microFont * 0.16; font.capitalization: Font.AllUppercase; elide: Text.ElideRight
                    }
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
    // Sheets live in the window overlay so the scrim covers the top bar as well.
    WifiOverlay {
        parent: Overlay.overlay
        visible: win.wifiOpen
        anchors.fill: parent
        onClosed: { win.wifiOpen = false; system.hideKeyboard() }
    }

    SysMonitorSheet {
        parent: Overlay.overlay
        visible: win.monitorOpen
        anchors.fill: parent
        onClosed: win.monitorOpen = false
    }

    SettingsSheet {
        id: settingsSheet
        parent: Overlay.overlay
        visible: win.settingsOpen
        anchors.fill: parent
        onClosed: win.settingsOpen = false
        onAct: function (action) {
            win.settingsOpen = false
            if (action === "reboot") system.reboot()
            else if (action === "cli") settings.switchToCli()
            else system.poweroff()
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
    Timer { running: demoSettings; interval: 1200; onTriggered: { settings.refresh(); win.settingsOpen = true; if (demoAsk !== "") settingsSheet.ask = demoAsk } }
    Component.onCompleted: if (demoSection !== "") selectSection(demoSection)
}
