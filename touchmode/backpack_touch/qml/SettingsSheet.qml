import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

// Settings sheet: UI size, orientation, the Terminal / Keyboard / Wi-Fi buttons (moved here from the
// top bar), Load to RAM, Switch to CLI Mode, and power. Reboot, Shut down and Switch to CLI Mode ask
// once more inside the sheet; the confirm button uses the signal fill. Emits act(action) once
// confirmed, and act("terminal" | "keyboard" | "wifi") straight away.
// Every row of buttons is a Flow, so nothing runs past the sheet's right edge: buttons wrap, and
// their command lines are capped at the sheet's width.
Sheet {
    id: sheet
    signal act(string action)
    property string ask: ""       // "", "reboot", "poweroff" or "cli": the pending question
    title: "Settings"
    facts: "BACKPACK // LIVE // " + (settings ? settings.ramFacts : "")
    onVisibleChanged: if (!visible) ask = ""
    // a button's command line never makes it wider than the sheet's content
    readonly property int commandMax: Math.max(Theme.s(80), contentWidth - Theme.space4 * 2)

    // the question and its consequence, in words, with Cancel and a signal-filled confirm
    component Confirm: ColumnLayout {
        property string action
        property string question
        property string consequence
        property string verb
        property string command
        visible: sheet.ask === action
        Layout.fillWidth: true
        spacing: Theme.space2
        Text { Layout.fillWidth: true; text: question; color: Theme.text; font.family: Theme.fontSans; font.pixelSize: Theme.fontSize; font.bold: true; wrapMode: Text.WordWrap }
        Text { Layout.fillWidth: true; text: consequence; color: Theme.muted; font.family: Theme.fontSans; font.pixelSize: Theme.smallFont; wrapMode: Text.WordWrap; lineHeightMode: Text.FixedHeight; lineHeight: Theme.smallLine }
        Flow {
            Layout.fillWidth: true; Layout.minimumWidth: 0; Layout.preferredWidth: 0
            spacing: Theme.gap
            TouchButton { text: "Cancel"; onClicked: sheet.ask = "" }
            TouchButton {
                text: verb; command: parent.parent.command; color: Theme.dangerFill; textColor: Theme.inkOnDanger
                commandMaxWidth: sheet.commandMax
                onClicked: { var a = sheet.ask; sheet.ask = ""; sheet.act(a) }
            }
        }
    }

    // ------------------------------------------------ display
    SheetHeading { text: "Display"; Layout.topMargin: Theme.space4 }
    Text { text: "UI size"; color: Theme.muted; font.family: Theme.fontSans; font.pixelSize: Theme.smallFont }
    RowLayout {
        Layout.fillWidth: true
        spacing: Theme.space2
        TouchButton { text: "−"; implicitWidth: Theme.touch; onClicked: scaleSlider.value = Math.max(scaleSlider.from, scaleSlider.value - 0.05) }
        Slider {
            id: scaleSlider
            Layout.fillWidth: true
            Layout.minimumWidth: Theme.s(60)
            Layout.preferredWidth: 0
            Layout.preferredHeight: Theme.touch
            from: settings ? settings.uiScaleMin : 0.5
            to: settings ? settings.uiScaleMax : 1.6
            stepSize: 0.05
            snapMode: Slider.SnapAlways
            value: settings ? settings.uiScale : 1.0
            // applies live, as the design says; the value is saved by Settings on every change
            onMoved: settings.uiScale = value
            onValueChanged: if (settings && Math.abs(value - settings.uiScale) > 0.001) settings.uiScale = value
            background: Rectangle {
                x: scaleSlider.leftPadding
                y: scaleSlider.topPadding + scaleSlider.availableHeight / 2 - height / 2
                width: scaleSlider.availableWidth; height: Theme.s(4)
                color: Theme.borderStrong
                Rectangle { width: scaleSlider.visualPosition * parent.width; height: parent.height; color: Theme.acid }   // the sheet is global: acid, whatever the section
            }
            handle: Chamfer {
                x: scaleSlider.leftPadding + scaleSlider.visualPosition * (scaleSlider.availableWidth - width)
                y: scaleSlider.topPadding + scaleSlider.availableHeight / 2 - height / 2
                width: Theme.s(28); height: Theme.s(40)
                cut: Theme.cutSm; borderWidth: 0
                color: scaleSlider.pressed ? Qt.lighter(Theme.acid, 1.15) : Theme.acid
            }
        }
        TouchButton { text: "+"; implicitWidth: Theme.touch; onClicked: scaleSlider.value = Math.min(scaleSlider.to, scaleSlider.value + 0.05) }
        Text {
            text: scaleSlider.value.toFixed(2).replace(/0$/, "") + "×"
            color: Theme.acid; font.family: Theme.fontSans; font.pixelSize: Theme.fontSize; font.bold: true
            Layout.preferredWidth: Theme.s(72); horizontalAlignment: Text.AlignRight
        }
    }
    TouchButton {
        visible: settings && Math.abs(settings.uiScale - 1.0) > 0.001
        text: "Reset to 1.0×"
        onClicked: { settings.uiScale = 1.0; scaleSlider.value = 1.0 }
    }
    Text {   // Main.fitScale lowered the size so the top bar fits this screen
        visible: settings && Theme.scale < settings.uiScale - 0.001
        Layout.fillWidth: true
        text: "This screen fits up to " + Theme.scale.toFixed(2).replace(/0$/, "") + "×, so that is what is shown."
        color: Theme.warn; font.family: Theme.fontSans; font.pixelSize: Theme.smallFont
        wrapMode: Text.WordWrap; lineHeightMode: Text.FixedHeight; lineHeight: Theme.smallLine
    }
    Text { text: "Orientation"; color: Theme.muted; font.family: Theme.fontSans; font.pixelSize: Theme.smallFont; Layout.topMargin: Theme.space2 }
    Dropdown {
        Layout.fillWidth: true
        Layout.minimumWidth: 0
        model: settings ? settings.rotations : []
        Component.onCompleted: currentIndex = settings ? indexOfValue(settings.rotation) : 0
        onActivated: function (i) { settings.rotation = valueAt(i) }
    }

    // ------------------------------------------------ session: the buttons that were in the top bar
    SheetHeading { text: "Session"; Layout.topMargin: Theme.space4 }
    Flow {
        Layout.fillWidth: true; Layout.minimumWidth: 0; Layout.preferredWidth: 0
        spacing: Theme.gap
        TouchButton {
            text: "Wi-Fi"; icon.name: "wifi"
            onClicked: sheet.act("wifi")
        }
        TouchButton {
            text: (system && system.keyboardVisible) ? "Hide keyboard" : "Keyboard"; icon.name: "keyboard"
            command: (system && system.keyboardVisible) ? "pkill -USR1 -x wvkbd-mobintl" : "pkill -USR2 -x wvkbd-mobintl"
            commandMaxWidth: sheet.commandMax
            // amber while the on-screen keyboard is open: caution, it covers the screen
            selected: !!(system && system.keyboardVisible)
            textColor: selected ? Theme.warn : Theme.text
            borderColor: selected ? Theme.warn : Theme.borderStrong
            onClicked: sheet.act("keyboard")
        }
        TouchButton {
            text: "Terminal"; icon.name: "terminal"
            command: "foot --app-id backpack-term"; commandMaxWidth: sheet.commandMax
            onClicked: sheet.act("terminal")
        }
    }

    // ------------------------------------------------ system
    SheetHeading { text: "System"; Layout.topMargin: Theme.space4 }
    Flow {
        visible: sheet.ask !== "cli"
        Layout.fillWidth: true
        spacing: Theme.gap
        TouchButton {
            text: settings && settings.inRam ? "Running from RAM" : (settings && settings.ramBusy ? "Loading… " + settings.ramProgress + "%" : "Load to RAM")
            command: settings ? settings.ramCommand : ""; commandMaxWidth: sheet.commandMax
            color: Theme.acid; textColor: Theme.inkOnAccent
            enabled: settings ? settings.canLoadToRam : false
            onClicked: settings.loadToRam()
        }
        TouchButton {   // caution: leaves GUI Mode
            text: "Switch to CLI Mode"; command: settings ? settings.cliCommand : ""; commandMaxWidth: sheet.commandMax
            textColor: Theme.warn; borderColor: Theme.warn
            onClicked: sheet.ask = "cli"
        }
    }
    Rectangle {   // Load to RAM progress, inline where the helper text was
        visible: settings ? settings.ramBusy : false
        Layout.fillWidth: true
        Layout.preferredHeight: Theme.s(4)
        color: Theme.borderStrong
        Rectangle { width: parent.width * (settings ? settings.ramProgress : 0) / 100; height: parent.height; color: Theme.acid }
    }
    Text {
        visible: sheet.ask !== "cli"
        Layout.fillWidth: true
        text: settings ? (settings.ramMessage !== "" ? settings.ramMessage : settings.ramSummary) : ""
        color: Theme.muted; font.family: Theme.fontSans; font.pixelSize: Theme.smallFont; wrapMode: Text.WordWrap; lineHeightMode: Text.FixedHeight; lineHeight: Theme.smallLine
    }
    Confirm {
        action: "cli"; verb: "Switch to CLI Mode"; command: settings ? settings.cliCommand : ""; question: "Switch to CLI Mode?"
        consequence: "GUI Mode closes with its running tools and terminals and you get a text login on the console. Reboot to come back to GUI Mode."
    }

    // ------------------------------------------------ power
    SheetHeading { text: "Power"; Layout.topMargin: Theme.space4 }
    Flow {
        visible: sheet.ask !== "reboot" && sheet.ask !== "poweroff"
        Layout.fillWidth: true; Layout.minimumWidth: 0; Layout.preferredWidth: 0
        spacing: Theme.gap
        TouchButton { text: "Reboot"; command: system ? system.rebootCommand : ""; commandMaxWidth: sheet.commandMax; textColor: Theme.danger; borderColor: Theme.danger; onClicked: sheet.ask = "reboot" }
        TouchButton { text: "Shut down"; command: system ? system.poweroffCommand : ""; commandMaxWidth: sheet.commandMax; textColor: Theme.danger; borderColor: Theme.danger; onClicked: sheet.ask = "poweroff" }
    }
    Confirm {
        action: "reboot"; verb: "Reboot"; command: system ? system.rebootCommand : ""; question: "Reboot?"
        consequence: "Running tools stop. Anything not saved to the persistence partition is lost."
    }
    Confirm {
        action: "poweroff"; verb: "Shut down"; command: system ? system.poweroffCommand : ""; question: "Shut down?"
        consequence: "Running tools stop. Anything not saved to the persistence partition is lost."
    }
    TouchButton { Layout.alignment: Qt.AlignRight; Layout.topMargin: Theme.space2; text: "Close"; onClicked: sheet.closed() }
}
