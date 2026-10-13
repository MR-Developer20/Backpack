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

    component GroupLabel: Text {
        color: Theme.muted; font.pixelSize: Theme.s(14); font.bold: true; font.letterSpacing: Theme.s(2)
        font.capitalization: Font.AllUppercase
    }

    Rectangle {
        id: panel
        anchors.centerIn: parent
        width: Math.min(parent.width - 40, Theme.s(680))
        height: Math.min(parent.height - 40, body.implicitHeight + Theme.s(48))
        radius: Theme.s(16)
        color: Theme.panel; border.color: Theme.border
        MouseArea { anchors.fill: parent }   // swallow clicks

        Flickable {
            anchors.fill: parent
            anchors.margins: Theme.s(24)
            contentHeight: body.implicitHeight
            clip: true
            boundsBehavior: Flickable.StopAtBounds

            ColumnLayout {
                id: body
                width: parent.width
                spacing: Theme.s(14)

                RowLayout {
                    Layout.fillWidth: true
                    Image { source: "../icons/settings.png"; Layout.preferredWidth: Theme.icon; Layout.preferredHeight: Theme.icon; sourceSize.width: 96; sourceSize.height: 96 }
                    Text { text: "Settings"; color: Theme.text; font.pixelSize: Theme.titleFont; font.bold: true }
                    Item { Layout.fillWidth: true }
                    TouchButton { text: "Close"; onClicked: sheet.closed() }
                }

                // ------------------------------------------------ display
                GroupLabel { text: "Display"; Layout.topMargin: Theme.s(4) }
                RowLayout {
                    Layout.fillWidth: true
                    spacing: Theme.s(14)
                    Text { text: "UI size"; color: Theme.text; font.pixelSize: Theme.fontSize }
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
                            width: scaleSlider.availableWidth; height: Theme.s(8); radius: height / 2
                            color: Theme.panelAlt; border.color: Theme.border
                            Rectangle { width: scaleSlider.visualPosition * parent.width; height: parent.height; radius: parent.radius; color: Theme.accent }
                        }
                        handle: Rectangle {
                            x: scaleSlider.leftPadding + scaleSlider.visualPosition * (scaleSlider.availableWidth - width)
                            y: scaleSlider.topPadding + scaleSlider.availableHeight / 2 - height / 2
                            width: Theme.s(40); height: Theme.s(40); radius: width / 2
                            color: scaleSlider.pressed ? Qt.lighter(Theme.accent, 1.2) : Theme.accent
                            border.color: Theme.bg; border.width: 2
                        }
                    }
                    TouchButton { text: "+"; implicitWidth: Theme.touch; onClicked: scaleSlider.value = Math.min(scaleSlider.to, scaleSlider.value + 0.05) }
                    Text {
                        text: Math.round(scaleSlider.value * 100) + "%"
                        color: Theme.accent; font.pixelSize: Theme.fontSize; font.bold: true
                        Layout.preferredWidth: Theme.s(70); horizontalAlignment: Text.AlignRight
                    }
                }
                TouchButton {
                    visible: settings && Math.abs(settings.uiScale - 1.0) > 0.001
                    text: "Reset to 100%"
                    onClicked: { settings.uiScale = 1.0; scaleSlider.value = 1.0 }
                }

                // ------------------------------------------------ system
                GroupLabel { text: "System"; Layout.topMargin: Theme.s(8) }
                Flow {
                    Layout.fillWidth: true
                    spacing: Theme.gap
                    TouchButton {
                        text: settings && settings.inRam ? "Running from RAM" : (settings && settings.ramBusy ? "Loading… " + settings.ramProgress + "%" : "Load to RAM")
                        color: Theme.accent; textColor: Theme.bg
                        enabled: settings ? settings.canLoadToRam : false
                        onClicked: settings.loadToRam()
                    }
                    TouchButton {
                        text: "Switch to CLI Mode"
                        color: Theme.panelAlt; textColor: Theme.warn
                        onClicked: sheet.confirm("cli")
                    }
                }
                Rectangle {   // Load to RAM progress
                    visible: settings ? settings.ramBusy : false
                    Layout.fillWidth: true
                    Layout.preferredHeight: Theme.s(10)
                    radius: height / 2
                    color: Theme.panelAlt
                    Rectangle { width: parent.width * (settings ? settings.ramProgress : 0) / 100; height: parent.height; radius: parent.radius; color: Theme.accent }
                }
                Text {
                    Layout.fillWidth: true
                    text: settings ? (settings.ramMessage !== "" ? settings.ramMessage : settings.ramSummary) : ""
                    color: Theme.muted; font.pixelSize: Theme.smallFont; wrapMode: Text.WordWrap
                }

                // ------------------------------------------------ power
                GroupLabel { text: "Power"; Layout.topMargin: Theme.s(8) }
                Flow {
                    Layout.fillWidth: true
                    spacing: Theme.gap
                    TouchButton { text: "Reboot"; iconSource: "../icons/reboot.png"; color: Theme.cautionFill; onClicked: sheet.confirm("reboot") }
                    TouchButton { text: "Shut down"; iconSource: "../icons/power.png"; color: Theme.dangerFill; onClicked: sheet.confirm("poweroff") }
                }
            }
        }
    }
}
