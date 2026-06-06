import QtQuick 2.0
import Sailfish.Silica 1.0
import "OverlayConfig.js" as Cfg

// Overlay bar with the four device panels. Contains the WebSocket client and
// feeds display texts + graphs on every STATE update.
Item {
    id: bar

    property alias wsUrl: client.wsUrl
    property alias connected: client.connected
    property alias dmm: client.dmm          // for optional DMM anchor of component ID
    // Orientation is passed in explicitly from the page (NOT inferred from the bar's
    // geometry -- a bar docked at the top is always wider than it is tall).
    property bool portrait: false
    property int columns: portrait ? 1 : 5           // Portrait: 1 column stacked on the left; Landscape: 5 side-by-side at the top
    readonly property real gap: Theme.paddingSmall
    readonly property real cellWidth: (width - (columns - 1) * gap) / columns

    // Compact sizes -- equally small in BOTH orientations (portrait was fine, landscape
    // should be just as compact).
    readonly property real _valueSize: Theme.fontSizeSmall
    readonly property real _modeSize: Theme.fontSizeExtraSmall
    readonly property real _graphHeight: 0.5 * Theme.itemSizeExtraSmall
    readonly property real _pad: Theme.paddingSmall / 2
    // All panels the same height (DMM otherwise has a sub-text row instead of a value row -> shorter).
    readonly property real _panelHeight: Math.max(pDmm.implicitHeight, pBb3a.implicitHeight,
                                                   pBb3b.implicitHeight, pLcr.implicitHeight,
                                                   pKel.implicitHeight)

    implicitHeight: grid.height
    height: grid.height

    InstrumentClient {
        id: client
        wsUrl: Cfg.DEFAULT_WS_URL
        onStateUpdated: bar._render()
    }

    Grid {
        id: grid
        anchors.horizontalCenter: parent.horizontalCenter
        columns: bar.columns
        columnSpacing: bar.gap
        rowSpacing: bar.gap

        InstrumentPanel {
            id: pDmm
            width: bar.cellWidth
            valueSize: bar._valueSize; modeSize: bar._modeSize
            graphHeight: bar._graphHeight; pad: bar._pad
            height: bar._panelHeight
            deviceLabel: "DMM7510"
            row2IsSub: true
            graph.colors: [Cfg.COLORS.voltage]
            graph.millisPerPixel: Cfg.CHARTS.dmm.millisPerPixel
            graph.minValue: Cfg.CHARTS.dmm.minValue
            graph.maxValue: Cfg.CHARTS.dmm.maxValue
        }
        InstrumentPanel {
            id: pBb3a
            width: bar.cellWidth
            valueSize: bar._valueSize; modeSize: bar._modeSize
            graphHeight: bar._graphHeight; pad: bar._pad
            height: bar._panelHeight
            deviceLabel: "BB3 Ch1 PSU"
            row1Mode: "CV"; row1Unit: "V"
            row2Mode: "CC"; row2Unit: "A"
            graph.colors: [Cfg.COLORS.voltage, Cfg.COLORS.current]
            graph.millisPerPixel: Cfg.CHARTS.bb3a.millisPerPixel
            graph.minValue: Cfg.CHARTS.bb3a.minValue
            graph.maxValue: Cfg.CHARTS.bb3a.maxValue
        }
        InstrumentPanel {
            id: pBb3b
            width: bar.cellWidth
            valueSize: bar._valueSize; modeSize: bar._modeSize
            graphHeight: bar._graphHeight; pad: bar._pad
            height: bar._panelHeight
            deviceLabel: "USB"
            row1Mode: "V"; row1Unit: "V"
            row2Mode: "A"; row2Unit: "A"
            graph.colors: [Cfg.COLORS.voltage, Cfg.COLORS.current]
            graph.millisPerPixel: Cfg.CHARTS.bb3b.millisPerPixel
            graph.minValue: Cfg.CHARTS.bb3b.minValue
            graph.maxValue: Cfg.CHARTS.bb3b.maxValue
        }
        InstrumentPanel {
            id: pLcr
            width: bar.cellWidth
            valueSize: bar._valueSize; modeSize: bar._modeSize
            graphHeight: bar._graphHeight; pad: bar._pad
            height: bar._panelHeight
            deviceLabel: "DER EE DE-5000"
            ok: false                  // Placeholder: grey/transparent like an offline device (DE-5000 integration to follow)
            row1Mode: "LCR"; row1Value: "—"
            graph.colors: [Cfg.COLORS.voltage]
            graph.millisPerPixel: Cfg.CHARTS.lcr.millisPerPixel
            graph.minValue: Cfg.CHARTS.lcr.minValue
            graph.maxValue: Cfg.CHARTS.lcr.maxValue
        }
        InstrumentPanel {
            id: pKel
            width: bar.cellWidth
            valueSize: bar._valueSize; modeSize: bar._modeSize
            graphHeight: bar._graphHeight; pad: bar._pad
            height: bar._panelHeight
            deviceLabel: "KEL103"
            row1Unit: "V"
            row2Unit: "A"
            graph.colors: [Cfg.COLORS.voltage, Cfg.COLORS.current]
            graph.millisPerPixel: Cfg.CHARTS.kel.millisPerPixel
            graph.maxValue: NaN        // Auto-scale (kel has no fixed maxValue)
        }
    }

    function reconnect() { client.reconnect() }

    // ---- DMM ----
    function _renderDmm() {
        var s = client.dmm
        pDmm.ok = s.ok
        pDmm.row1Mode = s.mode || "—"
        var f = Cfg.fmtDmm(s.value, s.unit || "", s.mode, s.range)
        pDmm.row1Value = f.sign + f.num
        pDmm.row1Unit = f.unit

        var isShorted = s.mode === "Diode" && s.value !== null
                && isFinite(s.value) && Math.abs(s.value) < 0.05
        pDmm.subText = isShorted ? "Shorted" : "—"
        pDmm.subColor = isShorted ? Cfg.COLORS.shorted : Cfg.COLORS.subtext

        if (s.ok && s.value !== null && isFinite(s.value)) {
            pDmm.graph.append(0, Date.now(), s.value)
            var eff = Cfg.dmmEffectiveRange(s.range, s.mode)
            pDmm.graph.minValue = 0
            pDmm.graph.maxValue = Cfg.dmmYMax(s.value, s.mode, eff)
        }
    }

    // ---- Two-row devices (BB3 / USB / KEL) ----
    function _renderTwoLine(panel, s, opts) {
        panel.ok = s.ok
        var isOff = s.output === false
        if (opts.modeSingle) panel.row1Mode = s.mode || "—"

        panel.row1Value = isOff ? "OFF" : Cfg.fmt3(s.voltage)
        panel.row2Value = isOff ? "OFF" : Cfg.fmt3(s.current)

        if (opts.usb) {
            if (s.ok && s.dp !== null && s.dn !== null
                    && isFinite(s.dp) && isFinite(s.dn)) {
                panel.row1Aux = "D+ " + s.dp.toFixed(2)
                panel.row2Aux = "D− " + s.dn.toFixed(2)
            } else {
                panel.row1Aux = ""
                panel.row2Aux = ""
            }
            panel.labelExtra = (s.ok && s.protocol && s.protocol !== "—") ? s.protocol : ""
        }

        if (!isOff && s.ok && isFinite(s.voltage)) panel.graph.append(0, Date.now(), s.voltage)
        if (!isOff && s.ok && isFinite(s.current)) panel.graph.append(1, Date.now(), s.current)
    }

    function _render() {
        _renderDmm()
        _renderTwoLine(pBb3a, client.bb3a, ({}))
        _renderTwoLine(pBb3b, client.bb3b, ({ usb: true }))
        _renderTwoLine(pKel,  client.kel,  ({ modeSingle: true }))
    }
}
