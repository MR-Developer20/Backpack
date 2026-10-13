import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

// System monitor popup: CPU and RAM graphs with what the hardware reports about each.
Rectangle {
    id: sheet
    signal closed()
    color: Theme.scrim
    MouseArea { anchors.fill: parent; onClicked: sheet.closed() }

    component Section: ColumnLayout {
        id: sec
        property string title
        property string value
        property color lineColor
        property var samples: []
        property var facts: []        // [[label, text], ...]
        spacing: Theme.s(8)
        RowLayout {
            Layout.fillWidth: true
            Text { font.family: Theme.fontSans; text: sec.title; color: Theme.muted; font.pixelSize: Theme.labelFont; font.bold: true; font.letterSpacing: Theme.labelFont * 0.14 }
            Item { Layout.fillWidth: true }
            Text { font.family: Theme.fontSans; text: sec.value; color: sec.lineColor; font.pixelSize: Theme.fontSize; font.bold: true }
        }
        UsageGraph {
            Layout.fillWidth: true
            Layout.preferredHeight: Theme.s(140)
            samples: sec.samples
            capacity: sysmon ? sysmon.historyLength : 60
            lineColor: sec.lineColor
        }
        GridLayout {
            Layout.fillWidth: true
            columns: 2; columnSpacing: Theme.s(14); rowSpacing: Theme.s(4)
            Repeater {
                model: sec.facts.length * 2
                Text { font.family: Theme.fontSans
                    required property int index
                    readonly property bool isLabel: index % 2 === 0
                    text: sec.facts[Math.floor(index / 2)][isLabel ? 0 : 1]
                    color: isLabel ? Theme.muted : Theme.text
                    font.pixelSize: Theme.smallFont
                    Layout.fillWidth: !isLabel
                    wrapMode: Text.WordWrap
                }
            }
        }
    }

    function moduleFacts() {
        if (!sysmon) return []
        var f = [["Capacity", sysmon.memCapacity]], m = sysmon.memModules
        for (var i = 0; i < m.length; i++) {
            var d = m[i], parts = [d.size, d.type, d.speed].filter(function (x) { return x !== "" }).join(" ")
            var who = [d.manufacturer, d.part].filter(function (x) { return x !== "" }).join(" ")
            f.push([d.slot !== "" ? d.slot : "Module " + (i + 1), parts + (who !== "" ? ", " + who : "")])
        }
        if (sysmon.memModulesNote !== "") f.push(["Modules", sysmon.memModulesNote])
        return f
    }

    Chamfer {
        anchors.centerIn: parent
        width: Math.min(parent.width - 40, Theme.s(760))
        height: Math.min(parent.height - 40, body.implicitHeight + Theme.s(48))
        cut: Theme.cutLg
        color: Theme.panel; borderColor: Theme.borderStrong
        MouseArea { anchors.fill: parent }   // swallow clicks

        Flickable {
            anchors.fill: parent
            anchors.margins: Theme.s(24)
            contentHeight: body.implicitHeight
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            ColumnLayout {
                id: body
                width: parent.width
                spacing: Theme.s(18)
                RowLayout {
                    Layout.fillWidth: true
                    Text { font.family: Theme.fontSans; text: "System monitor"; color: Theme.text; font.pixelSize: Theme.titleFont; font.bold: true }
                    Item { Layout.fillWidth: true }
                    TouchButton { text: "Close"; onClicked: sheet.closed() }
                }
                Section {
                    Layout.fillWidth: true
                    title: "CPU"
                    value: sysmon ? Math.round(sysmon.cpu) + "%" : ""
                    lineColor: Theme.acid
                    samples: sysmon ? sysmon.cpuHistory : []
                    facts: sysmon ? [["Model", sysmon.cpuModel], ["Cores", sysmon.cpuCores]] : []
                }
                Section {
                    Layout.fillWidth: true
                    title: "RAM"
                    value: sysmon ? Math.round(sysmon.mem) + "%" : ""
                    lineColor: Theme.cyan
                    samples: sysmon ? sysmon.memHistory : []
                    facts: sysmon ? [["In use", sysmon.memText]].concat(sheet.moduleFacts()) : []
                }
            }
        }
    }
}
