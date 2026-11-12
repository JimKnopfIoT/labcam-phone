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
    readonly property real _axisSize: Theme.fontSizeExtraSmall * 0.62   // scale labels in the graph
    // All panels the same height (DMM otherwise has a sub-text row instead of a value row -> shorter).
    readonly property real _panelHeight: Math.max(pDmm.implicitHeight, pBb3a.implicitHeight,
                                                   pBb3b.implicitHeight, pLcr.implicitHeight,
                                                   pKel.implicitHeight)

    implicitHeight: grid.height
    height: grid.height

    InstrumentClient {
        id: client
        // Address from the settings; empty = built-in default.
        wsUrl: settings.global.instrumentServer !== "" ? settings.global.instrumentServer
                                                       : Cfg.DEFAULT_WS_URL
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
            graph.axisFontSize: bar._axisSize
            height: bar._panelHeight
            deviceLabel: "DMM7510"
            // Double tap on the name disconnects the instrument (no queries, no open connection).
            labelInteractive: true
            onLabelDoubleClicked: client.sendCommand({ cmd: "device_connection", device: "dmm", connected: !!client.dmm.disconnected })
            row2IsSub: true
            graph.colors: [Cfg.COLORS.voltage]
            graph.millisPerPixel: Cfg.CHARTS.dmm.millisPerPixel
            graph.minValue: Cfg.CHARTS.dmm.minValue
            graph.maxValue: Cfg.CHARTS.dmm.maxValue
        }
        InstrumentPanel {
            id: pBb3a
            width: bar.cellWidth
            graphInteractive: true          // tap on the graph: V / A / both
            graph.perSeries: true           // V and A each get their own scale (otherwise A sits on the bottom edge)
            graph.units: ["V", "A"]
            valueSize: bar._valueSize; modeSize: bar._modeSize
            graphHeight: bar._graphHeight; pad: bar._pad
            graph.axisFontSize: bar._axisSize
            height: bar._panelHeight
            deviceLabel: "BB3 Ch1 PSU"
            labelInteractive: true
            onLabelDoubleClicked: client.sendCommand({ cmd: "device_connection", device: "bb3", connected: !!client.bb3a.disconnected })
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
            graphInteractive: true          // tap on the graph: V / A / both
            graph.perSeries: true           // V and A each get their own scale (otherwise A sits on the bottom edge)
            graph.units: ["V", "A"]
            valueSize: bar._valueSize; modeSize: bar._modeSize
            graphHeight: bar._graphHeight; pad: bar._pad
            graph.axisFontSize: bar._axisSize
            height: bar._panelHeight
            deviceLabel: "USB"
            labelInteractive: true
            onLabelDoubleClicked: client.sendCommand({ cmd: "device_connection", device: "usb", connected: !!client.bb3b.disconnected })
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
            graph.axisFontSize: bar._axisSize
            height: bar._panelHeight
            deviceLabel: "DER EE DE-5000"
            row1Mode: "LCR"; row1Value: "—"
            // Tap on the name toggles the source CP2102 <-> RN4871 (BLE).
            labelInteractive: true
            onLabelClicked: client.sendCommand({ cmd: "lcr_source", value: "toggle" })
            graph.colors: [Cfg.COLORS.voltage]
            graph.millisPerPixel: Cfg.CHARTS.lcr.millisPerPixel
            graph.minValue: Cfg.CHARTS.lcr.minValue
            graph.maxValue: Cfg.CHARTS.lcr.maxValue
        }
        InstrumentPanel {
            id: pKel
            width: bar.cellWidth
            graphInteractive: true          // tap on the graph: V / A / both
            graph.perSeries: true           // V and A each get their own scale (otherwise A sits on the bottom edge)
            graph.units: ["V", "A"]
            valueSize: bar._valueSize; modeSize: bar._modeSize
            graphHeight: bar._graphHeight; pad: bar._pad
            graph.axisFontSize: bar._axisSize
            height: bar._panelHeight
            deviceLabel: "KEL103"
            labelInteractive: true
            onLabelDoubleClicked: client.sendCommand({ cmd: "device_connection", device: "kel", connected: !!client.kel.disconnected })
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
        pDmm.labelExtra = s.disconnected ? "disconnected" : ""
        // Overflow (open leads / range exceeded) -> "OL", like on the instrument.
        var overload = s.ok && Cfg.isOverload(s.value)
        if (s.ok) {
            var f = Cfg.fmtDmm(s.value, s.unit || "", s.mode, s.range)
            pDmm.row1Value = f.sign + f.num
            pDmm.row1Unit = f.unit
        } else {
            pDmm.row1Value = "—"; pDmm.row1Unit = ""
        }

        var isShorted = s.ok && !overload && s.mode === "Diode" && s.value !== null
                && isFinite(s.value) && Math.abs(s.value) < 0.05
        pDmm.subText = isShorted ? "Shorted" : "—"
        pDmm.subColor = isShorted ? Cfg.COLORS.shorted : Cfg.COLORS.subtext

        // Do NOT feed the overflow sentinel (9.9e37) into the graph: it blows up
        // any scale and the rasterizer then discards the whole path (trace gone /
        // black line). Insert a gap instead.
        if (s.ok && overload) {
            pDmm.graph.appendGap(0, Date.now())
            // Keep the scale on the instrument range during overflow too, otherwise the
            // axis label freezes on the last value (without a unit).
            pDmm.graph.units = [s.unit || ""]
            pDmm.graph.minValue = 0
            pDmm.graph.maxValue = Cfg.dmmYMax(null, s.mode, Cfg.dmmEffectiveRange(s.range, s.mode))
        } else if (s.ok && s.value !== null && isFinite(s.value)) {
            pDmm.graph.units = [s.unit || ""]
            pDmm.graph.append(0, Date.now(), s.value)
            var eff = Cfg.dmmEffectiveRange(s.range, s.mode)
            pDmm.graph.minValue = 0
            pDmm.graph.maxValue = Cfg.dmmYMax(s.value, s.mode, eff)
        } else {
            pDmm.graph.appendGap(0, Date.now())
        }
    }

    // ---- Two-row devices (BB3 / USB / KEL) ----
    function _renderTwoLine(panel, s, opts) {
        panel.ok = s.ok
        panel.labelExtra = s.disconnected ? "disconnected" : ""
        var isOff = s.output === false
        if (opts.modeSingle) panel.row1Mode = s.mode || "—"

        // Offline (ok:false) => show nothing. The BLE backends (USB/DE-5000) keep their
        // LAST reading in the payload even when ok:false — without this gate those stale
        // values would keep showing (and get burned into the photo). Wired devices already
        // mask their stale value (DMM sentinel / KEL null / BB3 output:false).
        if (!s.ok) {
            panel.row1Value = "—"
            panel.row2Value = "—"
        } else {
            panel.row1Value = isOff ? "OFF" : Cfg.fmt3(s.voltage)
            panel.row2Value = isOff ? "OFF" : Cfg.fmt3(s.current)
        }

        if (opts.usb) {
            if (s.ok && s.dp !== null && s.dn !== null
                    && isFinite(s.dp) && isFinite(s.dn)) {
                panel.row1Aux = "D+ " + s.dp.toFixed(2)
                panel.row2Aux = "D− " + s.dn.toFixed(2)
            } else {
                panel.row1Aux = ""
                panel.row2Aux = ""
            }
            if (!s.disconnected)
                panel.labelExtra = (s.ok && s.protocol && s.protocol !== "—") ? s.protocol : ""
        }

        var live = !isOff && s.ok
        if (live && isFinite(s.voltage)) panel.graph.append(0, Date.now(), s.voltage)
        else                             panel.graph.appendGap(0, Date.now())
        if (live && isFinite(s.current)) panel.graph.append(1, Date.now(), s.current)
        else                             panel.graph.appendGap(1, Date.now())
    }

    // ---- LCR (DE-5000, CP2102 OR RN4871/BLE) ----
    function _renderLcr() {
        var s = client.lcr
        pLcr.ok = s.ok

        pLcr.row1Mode = s.mode || "LCR"

        // Offline (ok:false) => "—". The DE-5000 BLE backend keeps its last value in the
        // payload (status searching/offline); without the ok gate it would stay on screen.
        if (s.ok) {
            var f = Cfg.fmtLcr(s.value, s.unit || "")
            pLcr.row1Value = f.num
            pLcr.row1Unit = f.unit

            // Secondary value (D / Q / ESR / θ) on line 2 — otherwise empty.
            if (s.sec_mode && s.sec_mode.length > 0) {
                var g = Cfg.fmtLcr(s.sec_value, s.sec_unit || "")
                pLcr.row2Mode = s.sec_mode; pLcr.row2Value = g.num; pLcr.row2Unit = g.unit
            } else {
                pLcr.row2Mode = ""; pLcr.row2Value = ""; pLcr.row2Unit = ""
            }
        } else {
            pLcr.row1Value = "—"; pLcr.row1Unit = ""
            pLcr.row2Mode = ""; pLcr.row2Value = ""; pLcr.row2Unit = ""
        }

        // Source/status in the label extra: USB / BLE / BLE… (searching) / — (offline).
        var src = (s.source === "rn4871") ? "BLE" : "USB"
        var extra
        if (s.status === "searching")    extra = "BLE…"
        else if (s.status === "offline") extra = src + " —"
        else if (s.freq)                 extra = src + " · " + (s.freq >= 1000 ? (s.freq / 1000) + "k" : s.freq) + "Hz"
        else                             extra = src
        pLcr.labelExtra = extra

        if (s.ok && s.value !== null && isFinite(s.value)) {
            pLcr.graph.units = [s.unit || ""]
            pLcr.graph.append(0, Date.now(), s.value)
            pLcr.graph.minValue = 0
            pLcr.graph.maxValue = Cfg.lcrYMax(s.value)
        }
    }

    function _render() {
        _renderDmm()
        _renderTwoLine(pBb3a, client.bb3a, ({}))
        _renderTwoLine(pBb3b, client.bb3b, ({ usb: true }))
        _renderTwoLine(pKel,  client.kel,  ({ modeSingle: true }))
        _renderLcr()
    }
}
