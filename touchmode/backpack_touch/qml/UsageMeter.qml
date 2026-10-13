import QtQuick
import QtQuick.Layouts

// Tab-bar module: live CPU and RAM usage as two labelled bars. Tap opens the system monitor.
Rectangle {
    id: meter
    signal tapped()
    property bool compact: false
    implicitHeight: Theme.touch
    implicitWidth: compact ? Theme.s(110) : Theme.s(200)
    radius: Theme.s(10)
    color: area.pressed ? Qt.lighter(Theme.panelAlt, 1.3) : Theme.panelAlt
    border.color: Theme.border

    component Row1: RowLayout {
        property string label
        property real value
        property color barColor
        spacing: Theme.s(6)
        Text { font.family: Theme.fontSans; text: label; color: Theme.muted; font.pixelSize: Theme.s(13); font.bold: true; Layout.preferredWidth: Theme.s(32) }
        Rectangle {
            Layout.fillWidth: true; Layout.preferredHeight: Theme.s(8); radius: height / 2
            color: Theme.bg
            Rectangle { width: parent.width * Math.min(1, value / 100); height: parent.height; radius: parent.radius; color: barColor }
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
        Row1 { Layout.fillWidth: true; label: "CPU"; value: sysmon ? sysmon.cpu : 0; barColor: Theme.accent }
        Row1 { Layout.fillWidth: true; label: "RAM"; value: sysmon ? sysmon.mem : 0; barColor: Theme.warn }
    }
    MouseArea { id: area; anchors.fill: parent; onClicked: meter.tapped() }
}
