import QtQuick 2.0
import Sailfish.Silica 1.0
import "OverlayConfig.js" as Cfg

// JBC DME-2A solder station: the four ports in compact form (status dot, port, tool,
// actual/set). Data = STATE.devices.jbc from the backend. Same height as the other
// panels; the four rows share the space above the device name.
Rectangle {
    id: panel

    property var  jbc: null                 // STATE.devices.jbc
    property real pad: Theme.paddingSmall
    property real rowSize: Theme.fontSizeExtraSmall
    property real labelSize: Theme.fontSizeExtraSmall
    signal labelDoubleClicked()

    readonly property bool ok: !!(jbc && jbc.ok)
    readonly property real _rowH: Math.max(1, (height - 2 * pad - nameItem.height - 4 * col.spacing) / 4)
    readonly property real _font: Math.min(rowSize, _rowH * 0.9)

    function stateColor(s) {
        if (s === "work")  return Cfg.COLORS.jbcWork
        if (s === "stand") return Cfg.COLORS.jbcStand
        if (s === "sleep") return Cfg.COLORS.jbcSleep
        if (s === "hiber") return Cfg.COLORS.jbcHiber
        if (s === "error") return Cfg.COLORS.shorted
        return Cfg.COLORS.subtext
    }
    // temperature -> colour as in labcam-web (cold cyan … hot orange, too hot red)
    function tempColor(t, set) {
        if (t === null || t === undefined || !isFinite(t)) return Cfg.COLORS.subtext
        if (set && t > set + 25) return Cfg.COLORS.jbcHot
        if (t < 60)  return Cfg.COLORS.jbcHiber
        if (t < 150) return Cfg.COLORS.jbcTeal
        if (t < 250) return Cfg.COLORS.jbcStand
        return Cfg.COLORS.jbcWork
    }

    radius: 4
    color: Cfg.COLORS.background

    Column {
        id: col
        anchors { fill: parent; margins: panel.pad }
        spacing: 2

        Repeater {
            model: 4
            Item {
                width: col.width
                height: panel._rowH
                opacity: panel.ok ? 1.0 : 0.45
                readonly property var p: (panel.ok && panel.jbc.ports && panel.jbc.ports.length > index)
                                         ? panel.jbc.ports[index] : null
                readonly property bool has: !!(p && p.tool_id)

                Rectangle {
                    id: dot
                    anchors.verticalCenter: parent.verticalCenter
                    width: panel._font * 0.55; height: width; radius: width / 2
                    color: has ? panel.stateColor(p.state) : Cfg.COLORS.subtext
                }
                Label {
                    id: pno
                    anchors { left: dot.right; leftMargin: panel._font * 0.35; verticalCenter: parent.verticalCenter }
                    text: "P" + (index + 1)
                    color: Cfg.COLORS.label
                    font.pixelSize: panel._font
                    font.bold: true
                }
                Label {
                    anchors { left: pno.right; leftMargin: panel._font * 0.35; right: temp.left
                              rightMargin: panel._font * 0.3; verticalCenter: parent.verticalCenter }
                    text: has ? p.tool : "—"
                    color: "#cfcfcf"
                    font.pixelSize: panel._font
                    truncationMode: TruncationMode.Fade
                }
                Label {
                    id: temp
                    anchors { right: setL.left; rightMargin: panel._font * 0.2; verticalCenter: parent.verticalCenter }
                    text: (has && p.temp !== null) ? Math.round(p.temp) + "°" : "—"
                    color: has ? panel.tempColor(p.temp, p.set) : Cfg.COLORS.subtext
                    font.pixelSize: panel._font
                    font.bold: true
                }
                Label {
                    id: setL
                    anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                    width: panel._font * 2.3
                    horizontalAlignment: Text.AlignRight
                    text: (has && p.set !== null) ? "/" + Math.round(p.set) : ""
                    color: Cfg.COLORS.subtext
                    font.pixelSize: panel._font
                }
            }
        }

        // Device name; a double tap disconnects the station or connects it again.
        Item {
            id: nameItem
            width: col.width
            height: nameLabel.height
            Label {
                id: nameLabel
                width: parent.width
                text: "JBC DME-2A" + ((panel.jbc && panel.jbc.disconnected) ? "  disconnected" : "")
                color: panel.ok ? Cfg.COLORS.label : Cfg.COLORS.offlineLabel
                font.pixelSize: panel.labelSize
                font.bold: true
                truncationMode: TruncationMode.Fade
            }
            MouseArea {
                anchors.fill: parent
                onDoubleClicked: panel.labelDoubleClicked()
            }
        }
    }
}
