import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

// A sheet over the launcher: scrim, then a hull panel chamfered cut-lg and padded space-6,
// centred on whole pixels. Title on the left, a micro strip of live facts on the right.
// Content goes in `body` (a ColumnLayout); the sheet scrolls when the content is taller.
Rectangle {
    id: sheet
    signal closed()
    property string title
    property string facts: ""
    property int sheetWidth: Theme.s(560)
    readonly property real contentWidth: body.width   // what a row inside may take
    default property alias content: body.data
    color: Theme.scrim
    MouseArea { anchors.fill: parent; onClicked: sheet.closed() }

    Chamfer {
        x: Math.round((parent.width - width) / 2); y: Math.round((parent.height - height) / 2)
        width: Math.min(parent.width - Theme.space10, sheet.sheetWidth)
        height: Math.min(parent.height - Theme.space10, Math.ceil(body.implicitHeight) + Theme.space6 * 2)
        cut: Theme.cutLg
        color: Theme.panel; borderColor: Theme.borderStrong
        MouseArea { anchors.fill: parent }   // swallow clicks

        Flickable {
            id: flick
            anchors.fill: parent
            anchors.margins: Theme.space6
            // the content is exactly as wide as the sheet's padding box: left to itself the Flickable
            // takes its children's implicit width, and a row that wants more (a long command line,
            // a wide list) then pushed everything on its right past the sheet's edge, clipped
            contentWidth: width
            contentHeight: body.implicitHeight
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            ScrollBar.vertical: BpScrollBar {   // in the right padding, so it never covers content
                parent: flick.parent
                anchors.top: flick.top; anchors.bottom: flick.bottom; anchors.left: flick.right
            }

            ColumnLayout {
                id: body
                width: flick.width
                spacing: Theme.space2

                RowLayout {
                    Layout.fillWidth: true
                    Layout.bottomMargin: Theme.space2
                    spacing: Theme.space4
                    Text {
                        text: sheet.title; color: Theme.text
                        font.family: Theme.fontSans; font.pixelSize: Theme.titleFont; font.bold: true; font.letterSpacing: Theme.titleFont * 0.02
                    }
                    Text {
                        Layout.fillWidth: true; horizontalAlignment: Text.AlignRight; elide: Text.ElideLeft
                        text: sheet.facts
                        color: Theme.muted; font.family: Theme.fontSans; font.pixelSize: Theme.microFont; font.weight: Font.Medium
                        font.letterSpacing: Theme.microFont * 0.16; font.capitalization: Font.AllUppercase
                    }
                }
            }
        }
    }
}
