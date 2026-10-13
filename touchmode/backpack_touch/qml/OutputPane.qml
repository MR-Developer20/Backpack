import QtQuick
import QtQuick.Controls

Chamfer {
    id: pane
    property alias text: area.text
    cut: Theme.cutMd
    color: Theme.outputBg
    borderColor: Theme.border

    function append(s) {
        area.text += s
        if (area.text.length > 200000) area.text = area.text.slice(-150000)
        flick.contentY = Math.max(0, area.height - flick.height)
    }
    function clear() { area.text = "" }

    Flickable {
        id: flick
        anchors.fill: parent
        anchors.margins: Theme.space3
        contentHeight: area.height
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        TextEdit {
            id: area
            width: flick.width
            readOnly: true
            selectByMouse: true
            wrapMode: TextEdit.WrapAnywhere
            color: Theme.outputInk
            font.family: Theme.fontMono
            font.pixelSize: Theme.smallFont
            text: ""
        }
        ScrollBar.vertical: ScrollBar { width: Theme.s(18); policy: ScrollBar.AsNeeded }
    }
}
