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
    // what the bar needs, tier by tier (each adds to the one before; 5 gaps between 6 items):
    // tabs + two icon buttons (Split, Settings) + the compact meter; + the wordmark; + Split with
    // its label and command; + the Settings label; + the meter's percentages. Terminal, Keyboard and
    // Wi-Fi live in the Settings sheet, which leaves portrait room for the meter.
    readonly property real barMeterOnly: Theme.gap * 2 + tabs.implicitWidth + Theme.touch * 2 + meter.compactWidth + Theme.gap * 4 + Theme.space4
    readonly property real barWordmark: barMeterOnly + wordmarkMetrics.advanceWidth + Theme.space2 * 2 + Theme.gap
    readonly property real barLabels: barWordmark + splitBtn.fullWidth - Theme.touch
    readonly property real barSettings: barLabels + gearBtn.fullWidth - Theme.touch
    readonly property real barMeter: barSettings + meter.fullWidth - meter.compactWidth
    readonly property bool compact: width < barLabels
    TextMetrics { id: wordmarkMetrics; text: "BACKPACK//LIVE"; font.family: Theme.fontDisplay; font.pixelSize: Theme.wordmarkFont; font.weight: Font.ExtraBold; font.letterSpacing: Theme.wordmarkFont * 0.08 }
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

    // Theme.scale = the UI size slider, lowered in 0.05 steps while even the narrowest top bar (tabs +
    // five icon buttons, no meter) is wider than the window, so the gear stays on screen. Assigned, not
    // bound: the bar's width depends on the scale. A new slider value or window width starts again from
    // the slider value; re-measuring after that only ever lowers it, so it always settles.
    readonly property real barFloor: barMeterOnly - meter.compactWidth - Theme.gap
    readonly property real scaleWanted: settings ? settings.uiScale : 1.0
    function fitScale() {
        var min = settings ? settings.uiScaleMin : 0.5
        if (barFloor <= width || Theme.scale <= min + 0.001) return
        var fit = Math.floor(width / (barFloor / Theme.scale) * 20 + 0.001) / 20   // the bar grows ~linearly with the scale
        Theme.scale = Math.max(min, Math.min(Theme.scale - 0.05, fit))
    }
    function refitScale() { Theme.scale = scaleWanted; Qt.callLater(fitScale) }
    onWidthChanged: refitScale()
    onScaleWantedChanged: refitScale()
    onBarFloorChanged: Qt.callLater(fitScale)
    Binding { target: Theme; property: "section"; value: win.section }

    function sectionCategories(sec) {
        return manifest ? manifest.categories.filter(function (c) { return c.section === sec }) : []
    }
    function firstCategory(sec) { var c = sectionCategories(sec); return c.length ? c[0].id : "" }
    // switching section resets the chip to its first category and keeps the open tool only if it belongs there
    function selectSection(sec) { section = sec; category = firstCategory(sec); if (tool && tool.section !== sec) tool = null }

    function selectTool(t) { cmdIndex = 0; tool = t; runState = "" }   // reset cmdIndex first: bindings index tool.commands[cmdIndex]
    // the command Run will execute with the form's current values; `<name>` stays where a
    // required field is still empty (run() then reports that as an error)
    function updateRunLine() {
        runLine = (!tool || !runner || cmdIndex >= tool.commands.length) ? "" : runner.commandLine(tool.id, cmdIndex, form.values())
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
        function onOutput(s) { output.append(s) }
        function onLaunched(line) { output.append(line + "\n"); win.runState = "LAUNCHED" }
        function onStarted(cl) { win.runState = "RUNNING"; output.append("$ " + cl + "\n") }
        function onFinished(code) { win.runState = "EXIT " + code; output.append("\n[exit " + code + "]\n") }
        function onError(e) { win.runState = "ERROR // " + e; output.append("error: " + e + "\n") }
    }

    // ---------------------------------------------------------------- top bar
    header: Rectangle {
        height: Theme.barH
        color: Theme.panel
        Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: Theme.border }
        Text {   // the local IPv4 address, flush with the window's top-right corner: no padding, no margin
            z: 2
            anchors.top: parent.top; anchors.right: parent.right
            padding: 0
            text: sysmon && sysmon.ipv4 !== "" ? sysmon.ipv4 : "NO IPV4"
            color: Theme.muted
            font.family: Theme.fontMono; font.pixelSize: Theme.ipFont; font.letterSpacing: 0
            lineHeightMode: Text.FixedHeight; lineHeight: Theme.ipFont
        }
        RowLayout {
            anchors.fill: parent
            anchors.margins: Theme.gap
            spacing: win.compact ? Theme.s(6) : Theme.gap
            Text {   // wordmark: whole, or not at all when the bar cannot fit it beside the tabs and buttons
                visible: win.width >= win.barWordmark
                text: "BACKPACK//LIVE"; color: Theme.text
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
                                anchors.bottom: parent.bottom; width: parent.width; height: Math.round(Theme.s(3))   // whole pixels: no blended edge row
                                color: tab.on ? tab.tabAccent : "transparent"
                            }
                            MouseArea { anchors.fill: parent; onClicked: win.selectSection(tab.modelData.id) }
                        }
                    }
                }
            }
            Item { Layout.fillWidth: true }
            TouchButton {
                id: splitBtn
                text: (system && system.splitActive) ? "Exit split" : "Split"
                icon.name: (system && system.splitActive) ? "exitsplit" : "split"
                command: (system && system.splitActive) ? "pkill -f backpack-split" : "foot --app-id backpack-split"
                altText: (system && system.splitActive) ? "Split" : "Exit split"
                altCommand: (system && system.splitActive) ? "foot --app-id backpack-split" : "pkill -f backpack-split"
                selected: !!(system && system.splitActive)
                textColor: selected ? Theme.accent : Theme.text
                borderColor: selected ? Theme.accent : Theme.borderStrong
                compact: win.compact
                onClicked: system.toggleSplit(win.portrait)
            }
            UsageMeter {   // percentages once everything else has its label; dropped entirely when narrow
                id: meter
                visible: win.width >= win.barMeterOnly
                compact: win.width < win.barMeter
                onTapped: win.monitorOpen = true
            }
            TouchButton {   // its label is the last to appear: the gear reads on its own
                id: gearBtn
                text: "Settings"; icon.name: "settings"; compact: win.width < win.barSettings
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

                // Title, description, action chips and form scroll together; the Run row, the run line and
                // the output's minimum height stay in view below them at any UI size. When it all
                // fits, the form alone is still capped at 40% of the pane so the output keeps its room.
                // Whole-pixel heights, so the rows below (and the clip edge) land on pixels.
                Flickable {
                    id: headFlick
                    readonly property real headH: headCol.implicitHeight - (form.visible ? form.implicitHeight : 0)
                    readonly property real room: toolPane.height - Theme.space4 * 2 - Theme.space2 * 3 - runRow.height - runLineRow.implicitHeight
                                                 - (win.appMode ? 0 : output.Layout.minimumHeight)
                    Layout.fillWidth: true
                    Layout.preferredHeight: Math.floor(Math.max(Math.min(headCol.implicitHeight, Theme.touch),
                        Math.min(headCol.implicitHeight, headH + (form.visible ? toolPane.height * 0.4 : 0), room)))
                    contentHeight: headCol.implicitHeight
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds
                    // the bar sits in the pane's right padding, so the content width (and its wrapping) never
                    // depends on whether it shows: that feedback loop never settles
                    ScrollBar.vertical: BpScrollBar {
                        parent: toolPane
                        x: Math.round(toolPane.width - Theme.space4 + (Theme.space4 - width) / 2)
                        y: Theme.space4 + headFlick.y; height: headFlick.height
                    }
                    ColumnLayout {
                        id: headCol
                        width: headFlick.width
                        spacing: Theme.space2
                        Text { font.family: Theme.fontSans; text: win.tool ? win.tool.name : ""; color: Theme.text; font.pixelSize: Theme.titleFont; font.bold: true; font.letterSpacing: Theme.titleFont * 0.02; Layout.preferredHeight: Math.ceil(implicitHeight) }
                        Text { font.family: Theme.fontSans
                            Layout.fillWidth: true; Layout.preferredHeight: Math.ceil(implicitHeight)
                            text: win.tool ? win.tool.description : ""
                            color: Theme.muted; font.pixelSize: Theme.smallFont; wrapMode: Text.WordWrap; lineHeightMode: Text.FixedHeight; lineHeight: Theme.smallLine
                        }
                        Flow {
                            Layout.fillWidth: true
                            Layout.minimumWidth: 0
                            Layout.preferredWidth: 0
                            spacing: Theme.space2
                            visible: win.tool && win.tool.commands.length > 1
                            Repeater {
                                model: win.tool ? win.tool.commands : []
                                delegate: Chip {   // the chosen action: 2px accent border and accent label; Run stays the one primary
                                    required property int index
                                    required property var modelData
                                    text: modelData.label
                                    command: modelData.template
                                    selected: win.cmdIndex === index
                                    onClicked: win.cmdIndex = index
                                }
                            }
                        }
                        ToolForm {
                            visible: !win.appMode   // the form still supplies its defaults to runCurrent()
                            Layout.fillWidth: true
                            id: form
                            command: win.tool ? win.tool.commands[win.cmdIndex] : null
                            onChanged: win.updateRunLine()
                        }
                    }
                }
                Flow {   // wraps when the UI size is large
                    id: runRow
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
                    Layout.preferredWidth: 0
                    spacing: Theme.gap
                    TouchButton {
                        text: win.tool && win.tool.gui ? "Open" : "Run"
                        command: win.runLine
                        commandMaxWidth: Math.min(Theme.s(360), runRow.width - Theme.space4 * 2)   // never wider than the pane
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
                    id: runLineRow
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
                    // Theme.s(100), less on a screen too short for it beside the Run row and a touch-tall head
                    Layout.minimumHeight: Math.max(Theme.s(40), Math.min(Theme.s(100), toolPane.height - Theme.space4 * 2 - Theme.space2 * 3
                                                   - runRow.height - runLineRow.implicitHeight - Theme.touch))
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
            if (action === "wifi") win.wifiOpen = true
            else if (action === "terminal") system.openTerminal()
            else if (action === "keyboard") system.toggleKeyboard()
            else if (action === "reboot") system.reboot()
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
    Component.onCompleted: { refitScale(); if (demoSection !== "") selectSection(demoSection) }
}
