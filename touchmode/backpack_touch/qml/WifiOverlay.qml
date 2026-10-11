import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

// Wi-Fi discovery + connect overlay (NetworkManager via nmcli in the backend).
Rectangle {
    id: overlay
    property string selectedSsid: ""
    property bool selectedSecured: false
    property string lastMessage: ""
    signal closed()
    color: "#c0000000"
    MouseArea { anchors.fill: parent; onClicked: overlay.closed() }

    Component.onCompleted: wifi.scan()
    Connections {
        target: wifi
        function onMessage(m) { overlay.lastMessage = m }
    }

    Rectangle {
        anchors.centerIn: parent
        width: Math.min(parent.width - 40, 760)
        height: Math.min(parent.height - 40, 640)
        radius: 16
        color: Theme.panel; border.color: Theme.border
        MouseArea { anchors.fill: parent }   // swallow clicks

        ColumnLayout {
            anchors.fill: parent; anchors.margins: 18; spacing: 10
            RowLayout {
                Layout.fillWidth: true
                Image { source: "../icons/wifi.png"; width: 32; height: 32; sourceSize.width: 96; sourceSize.height: 96 }
                Text { text: "Wi-Fi"; color: Theme.text; font.pixelSize: 26; font.bold: true }
                Item { Layout.fillWidth: true }
                TouchButton { text: wifi.busy ? "Scanning…" : "Rescan"; enabled: !wifi.busy; onClicked: wifi.scan() }
                TouchButton { text: "Close"; onClicked: overlay.closed() }
            }
            Text {
                Layout.fillWidth: true
                text: wifi.status
                color: wifi.status.indexOf("Connected") === 0 ? Theme.accent : Theme.muted
                font.pixelSize: Theme.fontSize; elide: Text.ElideRight
            }

            ListView {
                id: list
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                model: wifi.networks
                spacing: 6
                ScrollBar.vertical: ScrollBar { width: 18 }
                delegate: Rectangle {
                    required property var modelData
                    width: list.width - 24
                    height: 62
                    radius: 10
                    color: overlay.selectedSsid === modelData.ssid ? Qt.darker(Theme.accent, 2.2) : Theme.panelAlt
                    border.color: overlay.selectedSsid === modelData.ssid ? Theme.accent : Theme.border
                    RowLayout {
                        anchors.fill: parent; anchors.margins: 12; spacing: 12
                        // signal bars
                        Row {
                            spacing: 3
                            Repeater {
                                model: 4
                                Rectangle {
                                    required property int index
                                    width: 7; height: 10 + index * 7
                                    anchors.bottom: parent.bottom
                                    radius: 2
                                    color: modelData.signal >= (index + 1) * 22 ? Theme.accent : Theme.border
                                }
                            }
                        }
                        Text { text: modelData.ssid; color: Theme.text; font.pixelSize: Theme.fontSize; Layout.fillWidth: true; elide: Text.ElideRight }
                        Text { text: modelData.inUse ? "connected" : ""; color: Theme.accent; font.pixelSize: Theme.smallFont }
                        Text { text: modelData.secured ? "🔒 " + modelData.security : "open"; color: Theme.muted; font.pixelSize: Theme.smallFont }
                    }
                    MouseArea {
                        anchors.fill: parent
                        onClicked: { overlay.selectedSsid = modelData.ssid; overlay.selectedSecured = modelData.secured; pw.text = "" }
                    }
                }
                Text {
                    anchors.centerIn: parent
                    visible: list.count === 0
                    text: wifi.busy ? "Scanning for networks…" : (wifi.hasDevice ? "No networks found" : "No Wi-Fi adapter detected")
                    color: Theme.muted; font.pixelSize: Theme.fontSize
                }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 10
                visible: overlay.selectedSsid !== ""
                Text { text: overlay.selectedSsid; color: Theme.text; font.pixelSize: Theme.fontSize; elide: Text.ElideRight; Layout.maximumWidth: 200 }
                Rectangle {
                    Layout.fillWidth: true; Layout.preferredHeight: Theme.touch
                    radius: 8; color: Theme.panelAlt; border.color: Theme.border
                    visible: overlay.selectedSecured
                    TextInput {
                        id: pw
                        anchors.fill: parent; anchors.margins: 12
                        color: Theme.text; font.pixelSize: Theme.fontSize
                        echoMode: showPw.checked ? TextInput.Normal : TextInput.Password
                        verticalAlignment: TextInput.AlignVCenter
                        clip: true
                        onActiveFocusChanged: if (activeFocus) system.showKeyboard()
                        Text { visible: !pw.text && !pw.activeFocus; text: "password"; color: Theme.muted; font.pixelSize: Theme.fontSize; anchors.verticalCenter: parent.verticalCenter }
                    }
                }
                CheckBox { id: showPw; visible: overlay.selectedSecured; text: "show"; font.pixelSize: Theme.smallFont; contentItem: Text { text: showPw.text; color: Theme.muted; leftPadding: showPw.indicator.width + 6; verticalAlignment: Text.AlignVCenter; font.pixelSize: Theme.smallFont } }
                TouchButton {
                    text: "Connect"; color: Theme.accent; textColor: Theme.bg
                    enabled: !wifi.busy && (!overlay.selectedSecured || pw.text.length > 0)
                    onClicked: { system.hideKeyboard(); wifi.connectTo(overlay.selectedSsid, pw.text) }
                }
                TouchButton { text: "Forget"; visible: overlay.selectedSsid !== ""; onClicked: wifi.forget(overlay.selectedSsid) }
            }
            RowLayout {
                Layout.fillWidth: true
                Text { Layout.fillWidth: true; text: overlay.lastMessage; color: Theme.warn; font.pixelSize: Theme.smallFont; elide: Text.ElideRight }
                TouchButton { text: "Disconnect"; visible: wifi.status.indexOf("Connected") === 0; onClicked: wifi.disconnect() }
            }
        }
    }
}
