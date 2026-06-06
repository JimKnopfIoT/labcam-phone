import QtQuick 2.0
import Sailfish.Silica 1.0
import "OverlayConfig.js" as Cfg

// One device panel: two value rows (Mode | Value+Unit), below that a
// scroll graph and the device name. Covers DMM/BB3/USB/KEL via properties.
Rectangle {
    id: panel

    property string deviceLabel: ""
    property string labelExtra: ""          // e.g. USB protocol
    property bool   ok: false

    // Row 1
    property string row1Mode: ""
    property string row1Value: ""
    property string row1Unit: ""
    property string row1Aux: ""             // small supplementary info (D+ ...)
    property color  row1ValueColor: Cfg.COLORS.voltage
    property color  row1ModeColor: Cfg.COLORS.mode

    // Row 2 -- either Mode|Value OR centered sub-text (DMM)
    property bool   row2IsSub: false
    property string row2Mode: ""
    property string row2Value: ""
    property string row2Unit: ""
    property string row2Aux: ""
    property color  row2ValueColor: Cfg.COLORS.current
    property color  row2ModeColor: Cfg.COLORS.mode
    property string subText: "—"
    property color  subColor: Cfg.COLORS.subtext

    // Graph
    property alias  graph: graph
    property bool   graphVisible: true

    // Sizes centrally adjustable (set smaller by the bar per orientation -> reduce height).
    property real pad: Theme.paddingSmall
    property real valueSize: Theme.fontSizeMedium
    property real unitSize: Theme.fontSizeExtraSmall
    property real modeSize: Theme.fontSizeExtraSmall
    property real labelSize: Theme.fontSizeExtraSmall
    property real graphHeight: Theme.itemSizeExtraSmall * 0.75

    radius: 4
    color: Cfg.COLORS.background
    implicitHeight: col.implicitHeight + 2 * pad
    height: implicitHeight

    readonly property real _valueSize: valueSize
    readonly property real _unitSize: unitSize
    readonly property real _modeSize: modeSize
    readonly property real _dimOpacity: ok ? 1.0 : 0.45

    Column {
        id: col
        anchors {
            left: parent.left; right: parent.right
            verticalCenter: parent.verticalCenter
            margins: panel.pad
        }
        spacing: 2

        // --- Row 1 ---
        Item {
            width: parent.width
            height: Math.max(r1Mode.height, r1Value.height)
            opacity: _dimOpacity

            Label {
                id: r1Mode
                anchors { left: parent.left; verticalCenter: parent.verticalCenter }
                width: parent.width * 0.40
                text: row1Mode
                color: row1ModeColor
                font.pixelSize: _modeSize
                font.bold: true
                truncationMode: TruncationMode.Fade
            }
            Row {
                id: r1Value
                anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                spacing: 2
                Label {
                    anchors.baseline: r1Num.baseline
                    text: row1Aux
                    color: row1ValueColor
                    font.pixelSize: Theme.fontSizeExtraSmall
                    visible: text.length > 0
                }
                Item {  // spacer between aux (D+ ...) and the main value
                    width: Theme.paddingMedium; height: 1
                    visible: row1Aux.length > 0
                }
                Label {
                    id: r1Num
                    text: row1Value
                    color: row1ValueColor
                    font.pixelSize: _valueSize
                    font.bold: true
                }
                Label {
                    anchors.baseline: r1Num.baseline
                    text: row1Unit
                    color: row1ValueColor
                    font.pixelSize: _unitSize
                }
            }
        }

        // --- Row 2 (Mode|Value) ---
        Item {
            width: parent.width
            height: row2IsSub ? 0 : Math.max(r2Mode.height, r2Value.height)
            visible: !row2IsSub
            opacity: _dimOpacity

            Label {
                id: r2Mode
                anchors { left: parent.left; verticalCenter: parent.verticalCenter }
                width: parent.width * 0.40
                text: row2Mode
                color: row2ModeColor
                font.pixelSize: _modeSize
                font.bold: true
                truncationMode: TruncationMode.Fade
            }
            Row {
                id: r2Value
                anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                spacing: 2
                Label {
                    anchors.baseline: r2Num.baseline
                    text: row2Aux
                    color: row2ValueColor
                    font.pixelSize: Theme.fontSizeExtraSmall
                    visible: text.length > 0
                }
                Item {  // spacer between aux (D- ...) and the main value
                    width: Theme.paddingMedium; height: 1
                    visible: row2Aux.length > 0
                }
                Label {
                    id: r2Num
                    text: row2Value
                    color: row2ValueColor
                    font.pixelSize: _valueSize
                    font.bold: true
                }
                Label {
                    anchors.baseline: r2Num.baseline
                    text: row2Unit
                    color: row2ValueColor
                    font.pixelSize: _unitSize
                }
            }
        }

        // --- Row 2 (sub-text, DMM) ---
        Label {
            visible: row2IsSub
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            text: subText
            color: subColor
            font.pixelSize: labelSize
            opacity: _dimOpacity
        }

        // --- Graph ---
        ScrollGraph {
            id: graph
            width: parent.width
            height: graphHeight
            visible: graphVisible
        }

        // --- Device name ---
        Label {
            width: parent.width
            text: deviceLabel + (labelExtra.length > 0 ? "  " + labelExtra : "")
            color: ok ? Cfg.COLORS.label : Cfg.COLORS.offlineLabel
            font.pixelSize: labelSize
            font.bold: true
            truncationMode: TruncationMode.Fade
        }
    }
}
