import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

// Wi-Fi discovery + connect sheet (NetworkManager via nmcli in the backend).
Sheet {
    id: overlay
    property string selectedSsid: ""
    property bool selectedSecured: false
    property string selectedSecurity: ""
    property string lastMessage: ""
    property bool showPw: false
    // read through guards: the backend object goes away before the QML tree at shutdown
    readonly property bool busy: wifi ? wifi.busy : false
    readonly property string status: wifi ? wifi.status : ""
    readonly property bool hasDevice: wifi ? wifi.hasDevice : false
    readonly property var networks: wifi ? wifi.networks : []
    title: "Wi-Fi"
    facts: overlay.busy ? "SCANNING" : (overlay.status.indexOf("Connected") === 0 ? "CONNECTED" : (overlay.hasDevice ? "NOT CONNECTED" : "NO ADAPTER"))
    sheetWidth: Theme.s(760)

    // The sheet is created hidden at startup, often before NetworkManager has the adapter up,
    // so scan each time it is opened rather than once at creation.
    onVisibleChanged: if (visible) wifi.scan()
    Connections {
        target: wifi
        function onMessage(m) { overlay.lastMessage = m }
    }

    Text {
        Layout.fillWidth: true
        text: overlay.status
        color: overlay.status.indexOf("Connected") === 0 ? Theme.accent : Theme.muted
        font.family: Theme.fontSans; font.pixelSize: Theme.smallFont; wrapMode: Text.WordWrap
    }

    ListView {
        id: list
        Layout.fillWidth: true
        Layout.preferredHeight: Theme.s(300)
        clip: true
        model: overlay.networks
        spacing: Theme.space2
        ScrollBar.vertical: BpScrollBar {}
        delegate: Item {
            id: row
            required property var modelData
            readonly property bool on: overlay.selectedSsid === modelData.ssid
            width: list.width - Theme.s(24)
            height: Theme.touch
            Chamfer {
                anchors.fill: parent
                cut: Theme.cutSm
                color: Theme.panelAlt
                borderColor: row.on ? Theme.accent : Theme.borderStrong
                borderWidth: row.on ? 2 : 1
            }
            RowLayout {
                anchors.fill: parent; anchors.margins: Theme.space3; spacing: Theme.space3
                Row {   // signal strength: four square bars
                    spacing: Theme.s(3)
                    Repeater {
                        model: 4
                        Rectangle {
                            required property int index
                            width: Theme.s(6); height: Theme.s(10) + index * Theme.s(7)
                            anchors.bottom: parent.bottom
                            color: row.modelData.signal >= (index + 1) * 22 ? Theme.accent : Theme.border
                        }
                    }
                }
                Text { text: row.modelData.ssid; color: Theme.text; font.family: Theme.fontSans; font.pixelSize: Theme.fontSize; Layout.fillWidth: true; elide: Text.ElideRight }
                Text {
                    visible: row.modelData.inUse
                    text: "CONNECTED"; color: Theme.accent
                    font.family: Theme.fontSans; font.pixelSize: Theme.microFont; font.weight: Font.Medium; font.letterSpacing: Theme.microFont * 0.16
                }
                Text {   // the security in words, never a lock glyph
                    text: row.modelData.secured ? row.modelData.security : "OPEN"; color: Theme.muted
                    font.family: Theme.fontSans; font.pixelSize: Theme.microFont; font.weight: Font.Medium; font.letterSpacing: Theme.microFont * 0.16
                    font.capitalization: Font.AllUppercase
                }
            }
            MouseArea {
                anchors.fill: parent
                onClicked: { overlay.selectedSsid = row.modelData.ssid; overlay.selectedSecured = row.modelData.secured; overlay.selectedSecurity = row.modelData.security; pw.text = "" }
            }
        }
        Text {
            anchors.centerIn: parent
            visible: list.count === 0
            text: overlay.busy ? "Scanning for networks…" : (overlay.hasDevice ? "No networks found" : "No Wi-Fi adapter detected")
            color: Theme.muted; font.family: Theme.fontSans; font.pixelSize: Theme.fontSize
        }
    }

    RowLayout {   // connect to the selected network
        Layout.fillWidth: true
        spacing: Theme.gap
        visible: overlay.selectedSsid !== ""
        Text { text: overlay.selectedSsid; color: Theme.text; font.family: Theme.fontSans; font.pixelSize: Theme.fontSize; elide: Text.ElideRight; Layout.maximumWidth: Theme.s(200) }
        Chamfer {
            Layout.fillWidth: true; Layout.preferredHeight: Theme.touch
            visible: overlay.selectedSecured
            cut: Theme.cutSm; color: Theme.panelAlt
            borderColor: pw.activeFocus ? Theme.focus : Theme.borderStrong; borderWidth: pw.activeFocus ? 2 : 1
            TextInput {
                id: pw
                anchors.fill: parent; anchors.margins: Theme.space3
                color: Theme.text; font.family: Theme.fontMono; font.pixelSize: Theme.fontSize
                echoMode: overlay.showPw ? TextInput.Normal : TextInput.Password
                verticalAlignment: TextInput.AlignVCenter
                clip: true
                onActiveFocusChanged: if (activeFocus) system.showKeyboard()
                Text { visible: !pw.text && !pw.activeFocus; text: "password"; color: Theme.muted; font.family: Theme.fontMono; font.pixelSize: Theme.fontSize; anchors.verticalCenter: parent.verticalCenter }
            }
        }
        TouchButton {
            visible: overlay.selectedSecured
            text: overlay.showPw ? "Hide" : "Show"; selected: overlay.showPw
            textColor: overlay.showPw ? Theme.accent : Theme.text; borderColor: overlay.showPw ? Theme.accent : Theme.borderStrong
            onClicked: overlay.showPw = !overlay.showPw
        }
        TouchButton {
            text: "Connect"; color: Theme.accent; textColor: Theme.inkOnAccent
            enabled: !overlay.busy && (!overlay.selectedSecured || pw.text.length > 0)
            onClicked: { system.hideKeyboard(); wifi.connectTo(overlay.selectedSsid, pw.text, overlay.selectedSecurity) }
        }
        TouchButton { text: "Forget"; textColor: Theme.danger; borderColor: Theme.danger; onClicked: wifi.forget(overlay.selectedSsid) }
    }
    Text {
        Layout.fillWidth: true
        visible: overlay.lastMessage !== ""
        text: overlay.lastMessage; color: Theme.warn
        font.family: Theme.fontSans; font.pixelSize: Theme.smallFont; wrapMode: Text.WordWrap
    }
    RowLayout {
        Layout.fillWidth: true
        Layout.topMargin: Theme.space4
        spacing: Theme.gap
        TouchButton { text: "Disconnect"; visible: overlay.status.indexOf("Connected") === 0; onClicked: wifi.disconnect() }
        TouchButton { text: overlay.busy ? "Scanning…" : "Rescan"; enabled: !overlay.busy; onClicked: wifi.scan() }
        Item { Layout.fillWidth: true }
        TouchButton { text: "Close"; onClicked: overlay.closed() }
    }
}
