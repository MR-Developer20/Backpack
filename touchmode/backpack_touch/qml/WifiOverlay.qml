import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

// Wi-Fi discovery + connect sheet (NetworkManager via nmcli in the backend).
Sheet {
    id: overlay
    property string selectedSsid: ""
    property bool selectedSecured: false
    property string selectedSecurity: ""
    // NetworkManager has a saved profile for it: Connect works without typing the password again
    readonly property bool selectedKnown: {
        for (var i = 0; i < networks.length; i++) if (networks[i].ssid === selectedSsid) return !!networks[i].known
        return false
    }
    readonly property bool useSaved: selectedKnown && pw.text.length === 0
    property string lastMessage: ""
    property bool showPw: false
    // read through guards: the backend object goes away before the QML tree at shutdown
    readonly property bool busy: wifi ? wifi.busy : false
    readonly property string status: wifi ? wifi.status : ""
    readonly property bool hasDevice: wifi ? wifi.hasDevice : false
    readonly property var networks: wifi ? wifi.networks : []
    readonly property string device: wifi ? wifi.device : ""
    // nmcli cannot build an 802.1X profile from the connect command: Connect is disabled and says why
    readonly property bool enterprise: selectedSecurity.indexOf("802.1X") >= 0
    // an SSID as the shell would need it, for the command lines under the buttons
    function select(n) { selectedSsid = n.ssid; selectedSecured = n.secured; selectedSecurity = n.security; pw.text = "" }
    function quoted(s) { return /^[A-Za-z0-9_.:@-]+$/.test(s) ? s : "'" + s.replace(/'/g, "'\\''") + "'" }
    title: "Wi-Fi"
    facts: overlay.busy ? "SCANNING" : (overlay.status.indexOf("Connected") === 0 ? "CONNECTED" : (overlay.hasDevice ? "NOT CONNECTED" : "NO ADAPTER"))
    sheetWidth: Theme.s(760)

    // The sheet is created hidden at startup, often before NetworkManager has the adapter up,
    // so scan each time it is opened rather than once at creation.
    onVisibleChanged: if (visible) wifi.scan()
    Connections {
        target: wifi
        function onMessage(m) { overlay.lastMessage = m }
        function onNetworksChanged() {   // test hook BACKPACK_DEMO_WIFI_SELECT=<ssid>
            if (demoWifiSelect === "" || overlay.selectedSsid !== "") return
            for (var i = 0; i < overlay.networks.length; i++) if (overlay.networks[i].ssid === demoWifiSelect) overlay.select(overlay.networks[i])
        }
    }

    Text {
        Layout.fillWidth: true
        text: overlay.status
        color: overlay.status.indexOf("Connected") === 0 ? Theme.accent : Theme.muted
        font.family: Theme.fontSans; font.pixelSize: Theme.smallFont; wrapMode: Text.WordWrap; lineHeightMode: Text.FixedHeight; lineHeight: Theme.smallLine
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
            activeFocusOnTab: true   // keyboard / Stream Deck: Space or Enter selects the network
            Keys.onSpacePressed: overlay.select(row.modelData)
            Keys.onReturnPressed: overlay.select(row.modelData)
            Chamfer {   // focus ring
                visible: row.activeFocus
                anchors.fill: parent; anchors.margins: -Theme.s(3)
                cut: Theme.cutSm + Theme.s(3)
                color: "transparent"; borderColor: Theme.focus; borderWidth: 2
            }
            Chamfer {
                anchors.fill: parent
                cut: Theme.cutSm
                color: Theme.panelAlt
                borderColor: row.on ? Theme.accent : Theme.borderStrong
                borderWidth: row.on ? 2 : 1
            }
            RowLayout {
                anchors.fill: parent; anchors.margins: Theme.space3; spacing: Theme.space3
                Text {   // signal strength in words (micro), as the design asks outside the top bar
                    text: row.modelData.signal + "%"; color: row.modelData.signal >= 50 ? Theme.accent : Theme.muted
                    font.family: Theme.fontSans; font.pixelSize: Theme.microFont; font.weight: Font.Medium; font.letterSpacing: Theme.microFont * 0.16
                    Layout.preferredWidth: Theme.s(44); horizontalAlignment: Text.AlignRight
                }
                Text { text: row.modelData.ssid; color: Theme.text; font.family: Theme.fontSans; font.pixelSize: Theme.fontSize; Layout.fillWidth: true; elide: Text.ElideRight }
                Text {
                    visible: !!row.modelData.known && !row.modelData.inUse
                    text: "SAVED"; color: Theme.muted
                    font.family: Theme.fontSans; font.pixelSize: Theme.microFont; font.weight: Font.Medium; font.letterSpacing: Theme.microFont * 0.16
                }
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
                onClicked: overlay.select(row.modelData)
            }
        }
        Text {
            anchors.centerIn: parent
            visible: list.count === 0
            text: overlay.busy ? "Scanning for networks…" : (overlay.hasDevice ? "No networks found" : "No Wi-Fi adapter detected")
            color: Theme.muted; font.family: Theme.fontSans; font.pixelSize: Theme.fontSize
        }
    }

    // connect to the selected network: its name, then the password field on a line of its own
    // (it used to share one row with Show, Connect and Forget and their command lines, which
    // squeezed the field to nothing and pushed the buttons past the sheet's right edge)
    ColumnLayout {
        id: connectBox
        Layout.fillWidth: true
        spacing: Theme.space2
        visible: overlay.selectedSsid !== ""
        Text {
            Layout.fillWidth: true
            text: overlay.selectedSsid; color: Theme.text; elide: Text.ElideRight
            font.family: Theme.fontSans; font.pixelSize: Theme.fontSize; font.bold: true
        }
        RowLayout {
            Layout.fillWidth: true
            spacing: Theme.gap
            visible: overlay.selectedSecured && !overlay.enterprise
            Chamfer {
                Layout.fillWidth: true; Layout.minimumWidth: Theme.s(120); Layout.preferredHeight: Theme.touch
                cut: Theme.cutSm; color: Theme.panelAlt
                borderColor: pw.activeFocus ? Theme.focus : Theme.borderStrong; borderWidth: pw.activeFocus ? 2 : 1
                TextInput {
                    id: pw
                    readonly property string deckRole: "text"   // the deck's Select brings up the on-screen keyboard
                    activeFocusOnTab: true
                    anchors.fill: parent; anchors.margins: Theme.space3
                    color: Theme.text; font.family: Theme.fontMono; font.pixelSize: Theme.fontSize
                    echoMode: overlay.showPw ? TextInput.Normal : TextInput.Password
                    verticalAlignment: TextInput.AlignVCenter
                    clip: true
                    onActiveFocusChanged: if (activeFocus) system.fieldFocused()   // the on-screen keyboard only for a finger or pen
                    onAccepted: if (connectButton.enabled) connectButton.clicked()
                    Text {
                        visible: !pw.text && !pw.activeFocus
                        text: overlay.selectedKnown ? "saved password" : "password"
                        color: Theme.muted; font.family: Theme.fontMono; font.pixelSize: Theme.fontSize
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }
            }
            TouchButton {
                text: overlay.showPw ? "Hide" : "Show"; selected: overlay.showPw
                textColor: overlay.showPw ? Theme.accent : Theme.text; borderColor: overlay.showPw ? Theme.accent : Theme.borderStrong
                onClicked: overlay.showPw = !overlay.showPw
            }
        }
        Flow {
            id: connectRow
            Layout.fillWidth: true
            Layout.minimumWidth: 0
            Layout.preferredWidth: 0
            spacing: Theme.gap
            TouchButton {
                id: connectButton
                text: "Connect"; color: Theme.accent; textColor: Theme.inkOnAccent
                commandMaxWidth: Math.min(Theme.s(470), overlay.contentWidth - Theme.space4 * 2)
                // a saved network comes up with its stored password; a typed one is shown as dots, never in clear
                command: overlay.useSaved ? "nmcli con up id " + overlay.quoted(overlay.selectedSsid)
                         : "nmcli dev wifi connect " + overlay.quoted(overlay.selectedSsid)
                           + (overlay.selectedSecured ? (pw.text.length > 0 ? " password " + "\u2022".repeat(Math.min(12, pw.text.length)) : " password <password>") : "")
                // a secured network needs a password unless NetworkManager already has one saved
                enabled: !overlay.busy && !overlay.enterprise && (!overlay.selectedSecured || overlay.selectedKnown || pw.text.length > 0)
                onClicked: { system.hideKeyboard(); wifi.connectTo(overlay.selectedSsid, pw.text, overlay.selectedSecurity) }
            }
            TouchButton {
                visible: overlay.selectedKnown
                text: "Forget"; command: "nmcli con delete id " + overlay.quoted(overlay.selectedSsid)
                commandMaxWidth: Math.min(Theme.s(470), overlay.contentWidth - Theme.space4 * 2)
                textColor: Theme.danger; borderColor: Theme.danger; onClicked: wifi.forget(overlay.selectedSsid)
            }
        }
    }
    Text {
        Layout.fillWidth: true
        visible: overlay.lastMessage !== "" || overlay.enterprise
        text: overlay.enterprise ? "Enterprise (802.1X) networks need a profile made in the terminal: nmtui" : overlay.lastMessage; color: Theme.warn
        font.family: Theme.fontSans; font.pixelSize: Theme.smallFont; wrapMode: Text.WordWrap; lineHeightMode: Text.FixedHeight; lineHeight: Theme.smallLine
    }
    RowLayout {
        id: actions
        Layout.fillWidth: true
        Layout.topMargin: Theme.space4
        spacing: Theme.gap
        TouchButton {
            id: disconnectButton
            text: "Disconnect"; command: "nmcli dev disconnect " + (overlay.device !== "" ? overlay.device : "<device>")
            visible: overlay.status.indexOf("Connected") === 0; onClicked: wifi.disconnect()
        }
        TouchButton {
            text: overlay.busy ? "Scanning…" : "Rescan"; command: "nmcli -t -f IN-USE,SSID,SIGNAL,SECURITY dev wifi list --rescan yes"
            // the whole line when it fits; elided so the row never runs past the sheet when Disconnect shows
            // measured from the sheet, not from this row: a row of buttons is as wide as they want, so a
            // command line sized from the row's own width pushed Close past the sheet's right edge
            commandMaxWidth: Math.max(0, Math.min(Theme.s(470), overlay.contentWidth - closeButton.implicitWidth - Theme.space4 * 2 - actions.spacing * 2
                                      - (disconnectButton.visible ? disconnectButton.implicitWidth + actions.spacing : 0)))
            enabled: !overlay.busy; onClicked: wifi.scan()
        }
        Item { Layout.fillWidth: true }
        TouchButton { id: closeButton; text: "Close"; onClicked: overlay.closed() }
    }
}
