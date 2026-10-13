import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

// System monitor sheet: CPU and RAM graphs with what the hardware reports about each.
Sheet {
    id: sheet
    title: "System monitor"
    facts: sysmon ? sysmon.cpuCores + " // " + sysmon.memCapacity : ""
    sheetWidth: Theme.s(760)

    component Section: ColumnLayout {
        id: sec
        property string title
        property string value
        property color lineColor
        property var samples: []
        property var facts: []        // [[label, text], ...]
        Layout.fillWidth: true
        spacing: Theme.space2
        SheetHeading { text: sec.title; value: sec.value; valueColor: sec.lineColor; Layout.topMargin: Theme.space4 }
        UsageGraph {
            Layout.fillWidth: true
            Layout.preferredHeight: Theme.s(140)
            samples: sec.samples
            capacity: sysmon ? sysmon.historyLength : 60
            lineColor: sec.lineColor
        }
        GridLayout {
            Layout.fillWidth: true
            columns: 2; columnSpacing: Theme.space4; rowSpacing: Theme.space1
            Repeater {
                model: sec.facts.length * 2
                Text {
                    required property int index
                    readonly property bool isLabel: index % 2 === 0
                    text: sec.facts[Math.floor(index / 2)][isLabel ? 0 : 1]
                    color: isLabel ? Theme.muted : Theme.text
                    font.family: Theme.fontSans; font.pixelSize: Theme.smallFont
                    Layout.fillWidth: !isLabel
                    wrapMode: Text.WordWrap; lineHeightMode: Text.FixedHeight; lineHeight: Theme.smallLine
                }
            }
        }
    }

    function moduleFacts() {
        var m = sysmon.memModules, f = [["Capacity", sysmon.memCapacity]]
        for (var i = 0; i < m.length; i++) {
            var d = m[i], parts = [d.size, d.type, d.speed].filter(function (x) { return x !== "" }).join(" ")
            var who = [d.manufacturer, d.part].filter(function (x) { return x !== "" }).join(" ")
            f.push([d.slot !== "" ? d.slot : "Module " + (i + 1), parts + (who !== "" ? ", " + who : "")])
        }
        if (sysmon.memModulesNote !== "") f.push(["Modules", sysmon.memModulesNote])
        return f
    }

    Section {
        title: "CPU"
        value: sysmon ? Math.round(sysmon.cpu) + "%" : ""
        lineColor: Theme.acid
        samples: sysmon ? sysmon.cpuHistory : []
        facts: sysmon ? [["Model", sysmon.cpuModel], ["Cores", sysmon.cpuCores]] : []
    }
    Section {
        title: "RAM"
        value: sysmon ? Math.round(sysmon.mem) + "%" : ""
        lineColor: Theme.cyan
        samples: sysmon ? sysmon.memHistory : []
        facts: sysmon ? [["In use", sysmon.memText]].concat(sheet.moduleFacts()) : []
    }
    RowLayout {
        Layout.fillWidth: true
        Layout.topMargin: Theme.space4
        Item { Layout.fillWidth: true }
        TouchButton { text: "Close"; onClicked: sheet.closed() }
    }
}
