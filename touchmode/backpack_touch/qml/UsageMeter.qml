import QtQuick
import QtQuick.Layouts

// Tab-bar module: live CPU and RAM usage as two labelled bars. Tap opens the system monitor.
Chamfer {
    id: meter
    signal tapped()
    property bool compact: false
    implicitHeight: Theme.touch
    readonly property int compactWidth: Theme.s(110)   // bars only
    readonly property int fullWidth: Theme.s(200)      // bars with percentages
    implicitWidth: compact ? compactWidth : fullWidth
    cut: Theme.cutSm
    color: area.pressed ? Qt.lighter(Theme.panelAlt, 1.3) : Theme.panelAlt
    borderColor: Theme.borderStrong

    component Row1: RowLayout {
        property string label
        property real value
        property color barColor
        spacing: Theme.s(6)
        Text { font.family: Theme.fontSans; text: label; color: Theme.muted; font.pixelSize: Theme.labelFont; font.bold: true; font.letterSpacing: Theme.labelFont * 0.14; Layout.preferredWidth: Theme.s(40) }
        Rectangle {
            Layout.fillWidth: true; Layout.preferredHeight: Theme.s(6)
            color: Theme.bg
            Rectangle { width: parent.width * Math.min(1, value / 100); height: parent.height; color: barColor }
        }
        Text { font.family: Theme.fontSans
            visible: !meter.compact
            text: Math.round(value) + "%"; color: Theme.text; font.pixelSize: Theme.s(13)
            horizontalAlignment: Text.AlignRight; Layout.preferredWidth: Theme.s(40)
        }
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.leftMargin: Theme.s(12); anchors.rightMargin: Theme.s(12)
        anchors.topMargin: Theme.s(10); anchors.bottomMargin: Theme.s(10)
        spacing: Theme.s(4)
        Row1 { Layout.fillWidth: true; label: "CPU"; value: sysmon ? sysmon.cpu : 0; barColor: Theme.acid }
        Row1 { Layout.fillWidth: true; label: "RAM"; value: sysmon ? sysmon.mem : 0; barColor: Theme.cyan }
    }
    MouseArea { id: area; anchors.fill: parent; onClicked: meter.tapped() }
}
