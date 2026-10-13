import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

// Settings popup: UI size, Load to RAM, Switch to CLI Mode, and power. Reboot, Shut down and
// Switch to CLI Mode go through Main.qml's confirm dialog (confirm(action)).
Rectangle {
    id: sheet
    signal closed()
    signal confirm(string action)
    color: Theme.scrim
    MouseArea { anchors.fill: parent; onClicked: sheet.closed() }

    // group heading: uppercase label over a grid hairline
    component GroupLabel: ColumnLayout {
        property alias text: label.text
        Layout.fillWidth: true
        spacing: Theme.space1
        Text {
            id: label
            color: Theme.muted; font.family: Theme.fontSans; font.pixelSize: Theme.labelFont; font.bold: true
            font.letterSpacing: Theme.labelFont * 0.14; font.capitalization: Font.AllUppercase
        }
        Rectangle { Layout.fillWidth: true; Layout.preferredHeight: 1; color: Theme.border }
    }

    Chamfer {
        id: panel
        anchors.centerIn: parent
        width: Math.min(parent.width - 40, Theme.s(560))
        height: Math.min(parent.height - 40, body.implicitHeight + Theme.space6 * 2)
        cut: Theme.cutLg
        color: Theme.panel; borderColor: Theme.borderStrong
        MouseArea { anchors.fill: parent }   // swallow clicks

        Flickable {
            anchors.fill: parent
            anchors.margins: Theme.space6
            contentHeight: body.implicitHeight
            clip: true
            boundsBehavior: Flickable.StopAtBounds

            ColumnLayout {
                id: body
                width: parent.width
                spacing: Theme.space2

                RowLayout {
                    Layout.fillWidth: true
                    spacing: Theme.space4
                    Text { text: "Settings"; color: Theme.text; font.family: Theme.fontSans; font.pixelSize: Theme.titleFont; font.bold: true; font.letterSpacing: Theme.titleFont * 0.02 }
                    Text {
                        Layout.fillWidth: true; horizontalAlignment: Text.AlignRight; elide: Text.ElideLeft
                        text: "BACKPACK // LIVE // " + (settings ? settings.ramFacts : "")
                        color: Theme.muted; font.family: Theme.fontSans; font.pixelSize: Theme.microFont; font.weight: Font.Medium
                        font.letterSpacing: Theme.microFont * 0.16
                    }
                }

                // ------------------------------------------------ display
                GroupLabel { text: "Display"; Layout.topMargin: Theme.space4 }
                RowLayout {
                    Layout.fillWidth: true
                    spacing: Theme.space2
                    Text { text: "UI size"; color: Theme.muted; font.family: Theme.fontSans; font.pixelSize: Theme.smallFont; Layout.rightMargin: Theme.space2 }
                    TouchButton { text: "−"; implicitWidth: Theme.touch; onClicked: scaleSlider.value = Math.max(scaleSlider.from, scaleSlider.value - 0.05) }
                    Slider {
                        id: scaleSlider
                        Layout.fillWidth: true
                        Layout.preferredHeight: Theme.touch
                        from: settings ? settings.uiScaleMin : 0.75
                        to: settings ? settings.uiScaleMax : 1.6
                        stepSize: 0.05
                        snapMode: Slider.SnapAlways
                        // apply on release (or on the +/- buttons): resizing live under a finger
                        // moves the slider itself
                        value: settings ? settings.uiScale : 1.0
                        onPressedChanged: if (!pressed) settings.uiScale = value
                        onValueChanged: if (!pressed && settings && Math.abs(value - settings.uiScale) > 0.001) settings.uiScale = value
                        background: Rectangle {
                            x: scaleSlider.leftPadding
                            y: scaleSlider.topPadding + scaleSlider.availableHeight / 2 - height / 2
                            width: scaleSlider.availableWidth; height: Theme.s(4)
                            color: Theme.borderStrong
                            Rectangle { width: scaleSlider.visualPosition * parent.width; height: parent.height; color: Theme.accent }
                        }
                        handle: Chamfer {
                            x: scaleSlider.leftPadding + scaleSlider.visualPosition * (scaleSlider.availableWidth - width)
                            y: scaleSlider.topPadding + scaleSlider.availableHeight / 2 - height / 2
                            width: Theme.s(28); height: Theme.s(40)
                            cut: Theme.cutSm; borderWidth: 0
                            color: scaleSlider.pressed ? Qt.lighter(Theme.accent, 1.15) : Theme.accent
                        }
                    }
                    TouchButton { text: "+"; implicitWidth: Theme.touch; onClicked: scaleSlider.value = Math.min(scaleSlider.to, scaleSlider.value + 0.05) }
                    Text {
                        text: scaleSlider.value.toFixed(2).replace(/0$/, "") + "×"
                        color: Theme.accent; font.family: Theme.fontSans; font.pixelSize: Theme.fontSize; font.bold: true
                        Layout.preferredWidth: Theme.s(64); horizontalAlignment: Text.AlignRight
                    }
                }
                TouchButton {
                    visible: settings && Math.abs(settings.uiScale - 1.0) > 0.001
                    text: "Reset to 1.0×"
                    onClicked: { settings.uiScale = 1.0; scaleSlider.value = 1.0 }
                }

                // ------------------------------------------------ system
                GroupLabel { text: "System"; Layout.topMargin: Theme.space4 }
                Flow {
                    Layout.fillWidth: true
                    spacing: Theme.gap
                    TouchButton {
                        text: settings && settings.inRam ? "Running from RAM" : (settings && settings.ramBusy ? "Loading… " + settings.ramProgress + "%" : "Load to RAM")
                        color: Theme.accent; textColor: Theme.inkOnAccent
                        enabled: settings ? settings.canLoadToRam : false
                        onClicked: settings.loadToRam()
                    }
                    TouchButton {   // caution: leaves GUI Mode
                        text: "Switch to CLI Mode"
                        textColor: Theme.warn; borderColor: Theme.warn
                        onClicked: sheet.confirm("cli")
                    }
                }
                Rectangle {   // Load to RAM progress
                    visible: settings ? settings.ramBusy : false
                    Layout.fillWidth: true
                    Layout.preferredHeight: Theme.s(4)
                    color: Theme.borderStrong
                    Rectangle { width: parent.width * (settings ? settings.ramProgress : 0) / 100; height: parent.height; color: Theme.accent }
                }
                Text {
                    Layout.fillWidth: true
                    text: settings ? (settings.ramMessage !== "" ? settings.ramMessage : settings.ramSummary) : ""
                    color: Theme.muted; font.family: Theme.fontSans; font.pixelSize: Theme.smallFont; wrapMode: Text.WordWrap
                }

                // ------------------------------------------------ power
                GroupLabel { text: "Power"; Layout.topMargin: Theme.space4 }
                RowLayout {
                    Layout.fillWidth: true
                    spacing: Theme.gap
                    TouchButton { text: "Reboot"; textColor: Theme.danger; borderColor: Theme.danger; onClicked: sheet.confirm("reboot") }
                    TouchButton { text: "Shut down"; textColor: Theme.danger; borderColor: Theme.danger; onClicked: sheet.confirm("poweroff") }
                    Item { Layout.fillWidth: true }
                    TouchButton { text: "Close"; onClicked: sheet.closed() }
                }
            }
        }
    }
}
