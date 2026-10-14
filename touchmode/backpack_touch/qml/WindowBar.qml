import QtQuick
import QtQuick.Window

// The top bar of an app window (windows.py frames every app: this bar on top, the app below, both
// in one floating sway container). Sway draws the 5px strip above it (the bar's own title strip),
// which drags the whole frame. Close / Maximize / Split sit at the top left; the rest is the app's
// name, or the split question (left or right; top or bottom in portrait).
Window {
    id: bar
    property string appTitle: ""
    property bool active: false        // the frame holds the focused window
    property bool maximized: true
    property string side: ""           // "" | "a" (left / top) | "b" (right / bottom)
    property bool portrait: false
    property bool asking: false
    // the bar's height without sway's strip; windows.py sizes the bar's sway container to it
    readonly property int contentH: Theme.chipH + Theme.space2 * 2
    signal closeRequested()
    signal maximizeRequested()
    signal splitRequested()
    signal sideChosen(string side)

    title: "Backpack window bar"
    color: Theme.panel
    flags: Qt.FramelessWindowHint
    onContentHChanged: windows.refit(bar)

    Row {
        id: buttons
        anchors.left: parent.left; anchors.leftMargin: Theme.space2
        anchors.verticalCenter: parent.verticalCenter
        spacing: Theme.space2
        TouchButton {
            compact: true; icon.name: "close"
            implicitWidth: Theme.chipH; implicitHeight: Theme.chipH
            textColor: Theme.danger; borderColor: Theme.danger
            focusPolicy: Qt.NoFocus
            onClicked: bar.closeRequested()
        }
        TouchButton {
            compact: true; icon.name: bar.maximized ? "restore" : "maximize"
            implicitWidth: Theme.chipH; implicitHeight: Theme.chipH
            focusPolicy: Qt.NoFocus
            onClicked: bar.maximizeRequested()
        }
        TouchButton {
            compact: true; icon.name: "split"
            implicitWidth: Theme.chipH; implicitHeight: Theme.chipH
            selected: bar.side !== "" || bar.asking
            borderColor: selected ? Theme.accent : Theme.borderStrong
            focusPolicy: Qt.NoFocus
            onClicked: bar.splitRequested()
        }
    }

    Text {   // the app's name
        visible: !bar.asking
        anchors.left: buttons.right; anchors.leftMargin: Theme.space4
        anchors.right: parent.right; anchors.rightMargin: Theme.space4
        anchors.verticalCenter: parent.verticalCenter
        text: bar.appTitle.toUpperCase()
        elide: Text.ElideRight
        font.family: Theme.fontSans; font.pixelSize: Theme.labelFont
        font.letterSpacing: Theme.labelFont * 0.14
        color: bar.active ? Theme.text : Theme.muted
    }

    Row {   // split: which side
        visible: bar.asking
        anchors.left: buttons.right; anchors.leftMargin: Theme.space4
        anchors.verticalCenter: parent.verticalCenter
        spacing: Theme.space2
        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: "SPLIT TO"
            font.family: Theme.fontSans; font.pixelSize: Theme.microFont
            font.letterSpacing: Theme.microFont * 0.16
            color: Theme.muted
        }
        TouchButton {
            text: bar.portrait ? "Top" : "Left"
            implicitHeight: Theme.chipH
            focusPolicy: Qt.NoFocus
            onClicked: bar.sideChosen("a")
        }
        TouchButton {
            text: bar.portrait ? "Bottom" : "Right"
            implicitHeight: Theme.chipH
            focusPolicy: Qt.NoFocus
            onClicked: bar.sideChosen("b")
        }
        TouchButton {
            text: "Cancel"
            implicitHeight: Theme.chipH
            focusPolicy: Qt.NoFocus
            onClicked: bar.asking = false
        }
    }

    Rectangle {   // hairline between the bar and the app: acid on the focused frame
        anchors.left: parent.left; anchors.right: parent.right; anchors.bottom: parent.bottom
        height: 1
        color: bar.active ? Theme.accent : Theme.border
    }
}
