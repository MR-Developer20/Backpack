import QtQuick
import QtQuick.Layouts

// Group heading inside a sheet: uppercase label in ink-muted, optional value on the right, and
// a grid hairline under both.
ColumnLayout {
    id: heading
    property string text
    property string value: ""
    property color valueColor: Theme.accent
    Layout.fillWidth: true
    spacing: Theme.space1
    RowLayout {
        Layout.fillWidth: true
        Text {
            text: heading.text
            color: Theme.muted; font.family: Theme.fontSans; font.pixelSize: Theme.labelFont; font.bold: true
            font.letterSpacing: Theme.labelFont * 0.14; font.capitalization: Font.AllUppercase
        }
        Item { Layout.fillWidth: true }
        Text {
            visible: heading.value !== ""
            text: heading.value
            color: heading.valueColor; font.family: Theme.fontSans; font.pixelSize: Theme.fontSize; font.bold: true
        }
    }
    Rectangle { Layout.fillWidth: true; Layout.preferredHeight: 1; color: Theme.border }
}
