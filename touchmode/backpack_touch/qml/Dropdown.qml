import QtQuick
import QtQuick.Controls

// A touch-tall dropdown in the Field Terminal look: a raised field chamfered cut-sm showing the
// chosen option, and under it a list of touch-tall option rows. model = [{value, label, command}]:
// an option that runs a command when chosen shows it under its label in `command` type (the
// design's rule for anything that runs a command). Open = the 2px acid border, like a focused field.
ComboBox {
    id: box
    textRole: "label"
    valueRole: "value"
    implicitHeight: Theme.touch
    implicitWidth: Theme.s(320)
    font.family: Theme.fontSans
    font.pixelSize: Theme.fontSize
    readonly property var current: currentIndex >= 0 && model && currentIndex < model.length ? model[currentIndex] : null

    component OptionText: Column {
        property var option
        property color ink: Theme.text
        spacing: Theme.s(2)
        Text {
            width: parent.width
            text: option ? option.label : ""; color: ink; elide: Text.ElideRight
            font.family: Theme.fontSans; font.pixelSize: Theme.fontSize
        }
        Text {   // `command` type: regular, untracked, never uppercased
            width: parent.width
            visible: !!option && !!option.command
            text: option && option.command ? option.command : ""; color: Theme.muted; elide: Text.ElideRight
            font.family: Theme.fontMono; font.pixelSize: Theme.commandFont; font.weight: Font.Normal; font.letterSpacing: 0
        }
    }

    background: Chamfer {
        cut: Theme.cutSm
        color: box.down ? Qt.lighter(Theme.panelAlt, 1.6) : Theme.panelAlt
        borderColor: box.popup.visible || box.visualFocus ? Theme.focus : Theme.borderStrong
        borderWidth: box.popup.visible || box.visualFocus ? 2 : 1
    }
    contentItem: Item {
        OptionText {
            anchors.left: parent.left; anchors.leftMargin: Theme.space4
            anchors.right: parent.right; anchors.rightMargin: Theme.space2
            anchors.verticalCenter: parent.verticalCenter
            option: box.current
        }
    }
    indicator: Icon {
        name: "chevron"
        x: box.width - width - Theme.space4
        y: Math.round((box.height - height) / 2)
        width: Theme.s(20); height: Theme.s(20)
        color: box.popup.visible ? Theme.acid : Theme.text
    }
    rightPadding: Theme.s(20) + Theme.space4 * 2
    leftPadding: 0

    delegate: ItemDelegate {
        id: opt
        required property var modelData
        required property int index
        readonly property bool on: box.currentIndex === index
        width: ListView.view ? ListView.view.width : box.width
        height: Theme.touch
        padding: 0
        background: Chamfer {
            cut: Theme.cutSm
            color: opt.down ? Qt.lighter(Theme.panelAlt, 1.6) : Theme.panelAlt
            borderColor: opt.on ? Theme.acid : Theme.borderStrong
            borderWidth: opt.on ? 2 : 1
        }
        contentItem: Item {
            OptionText {
                anchors.left: parent.left; anchors.leftMargin: Theme.space4
                anchors.right: parent.right; anchors.rightMargin: Theme.space4
                anchors.verticalCenter: parent.verticalCenter
                option: opt.modelData
                ink: opt.on ? Theme.acid : Theme.text
            }
        }
    }

    popup: Popup {
        y: box.height + Theme.space1
        width: box.width
        padding: Theme.space2
        implicitHeight: Math.min(list.contentHeight + padding * 2, box.Window.height ? box.Window.height * 0.6 : 100000)
        background: Chamfer { cut: Theme.cutSm; color: Theme.panel; borderColor: Theme.borderStrong }
        contentItem: ListView {
            id: list
            clip: true
            spacing: Theme.space1
            implicitHeight: contentHeight
            model: box.popup.visible ? box.delegateModel : null
            currentIndex: box.highlightedIndex
            boundsBehavior: Flickable.StopAtBounds
            ScrollBar.vertical: BpScrollBar {}
        }
    }
}
