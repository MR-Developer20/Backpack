import QtQuick
import QtQuick.Controls

// Square scroll bar: a rail-wide (6px) handle in grid-strong, ink while pressed, no rounded
// corners. Shown only while there is something to scroll.
ScrollBar {
    id: bar
    width: Theme.s(18)
    padding: Theme.s(6)
    policy: ScrollBar.AsNeeded
    visible: policy === ScrollBar.AlwaysOn || size < 1.0
    contentItem: Rectangle {
        implicitWidth: Theme.s(6); implicitHeight: Theme.s(6)
        color: bar.pressed ? Theme.ink : Theme.borderStrong
    }
}
