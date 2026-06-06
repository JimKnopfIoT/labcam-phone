.pragma library

// ============================================================
//  Overlay configuration + display logic (ported from
//  the lab data server's config.js + overlay.js to QML).
//
//  Same JSON STATE schema as delivered by the instrument STATE backend:
//    devices.dmm  {ok, mode, value, unit, range}
//    devices.bb3a {ok, mode, voltage, current, output}
//    devices.bb3b {ok, mode, voltage, current, output, dp, dn, protocol}  (USB / Fnirsi C1)
//    devices.kel  {ok, mode, voltage, current, output}
// ============================================================

// ---------- Backend ----------
// Default WebSocket URL. The phone has no "same host as HTML" concept,
// so the lab PC IP must be set here (or via Settings).
var DEFAULT_WS_URL = "ws://192.168.10.6:7891"

// ---------- Colors (from config.js) ----------
var COLORS = {
    background:      "#6c191919",   // rgba(26,26,26,0.42) -- 50% more transparent than before (0.85)
    graphBackground: "#33000000",   // rgba(0,0,0,0.2)
    graphBorder:     "#2a2a2a",
    graphGrid:       "#14ffffff",   // rgba(255,255,255,0.08)

    voltage: "#00d3ff",
    current: "#e4b700",
    mode:    "#64ff00",
    label:   "#00d3ff",
    subtext: "#6a7a7c",

    offlineLabel: "#cc6666",
    shorted:      "#cc6666"
}

// ---------- Graph defaults ----------
var GRAPH = {
    lineWidth:      2,
    millisPerPixel: 50
}

// Per device (from config.js): fixed Y scale (min/max) and scroll speed.
// dmm: maxValue is set live from mode/range (see dmmYMax).
var CHARTS = {
    dmm:  { minValue: 0, maxValue: 12, millisPerPixel: 165 },
    bb3a: { minValue: 0, maxValue: 20, millisPerPixel: 119 },
    bb3b: { minValue: 0, maxValue:  6, millisPerPixel: 119 },
    lcr:  { minValue: 0, maxValue:  1, millisPerPixel: 119 },   // DE-5000 placeholder (no data yet)
    kel:  { millisPerPixel: 1190 }
}

// ============================================================
//  DMM formatting -- unit follows the DEVICE range, not the value.
//  Returns {sign, num, unit}.
// ============================================================
function fmtDmm(value, baseUnit, mode, range) {
    if (value === null || value === undefined || !isFinite(value) || Math.abs(value) > 1e30) {
        return { sign: "", num: "", unit: baseUnit || "" }
    }
    var abs = Math.abs(value)
    var scaled = value
    var unit = baseUnit || ""
    var fixedDecimals = null

    // Diode always in V with 2 integer and 6 decimal digits (DMM7510 display)
    if (mode === "Diode") {
        var s = Math.abs(value).toFixed(6)
        var dotIdx = s.indexOf(".")
        if (dotIdx < 2) s = repeat("0", 2 - dotIdx) + s
        return { sign: value < 0 ? "-" : "", num: s, unit: "V" }
    }

    var r = (range !== null && range !== undefined && isFinite(range)) ? Math.abs(range) : null

    if (baseUnit === "V" || baseUnit === "A") {
        var prefix
        if (r !== null) {
            if (r <= 1.05e-4)      prefix = "µ"
            else if (r <= 1.05e-1) prefix = "m"
            else                   prefix = ""
        } else {
            if (abs > 0 && abs < 1.2e-4)   prefix = "µ"
            else if (abs > 0 && abs < 1.2) prefix = "m"
            else                           prefix = ""
        }
        if (prefix === "µ")      { scaled = value * 1e6; unit = "µ" + baseUnit }
        else if (prefix === "m") { scaled = value * 1e3; unit = "m" + baseUnit }
    } else if (baseUnit === "Ω") {
        var prefixO
        if (r !== null) {
            if (r >= 1.05e6)      prefixO = "M"
            else if (r >= 1.05e3) prefixO = "k"
            else                  prefixO = ""
        } else {
            if (abs >= 1.2e6)     prefixO = "M"
            else if (abs >= 1.2e3) prefixO = "k"
            else                  prefixO = ""
        }
        if (prefixO === "M")      { scaled = value / 1e6; unit = "MΩ" }
        else if (prefixO === "k") { scaled = value / 1e3; unit = "kΩ" }
    } else if (baseUnit === "F") {
        var prefixF
        if (r !== null) {
            if (r >= 1.05e-4)      prefixF = "m"
            else if (r >= 1.05e-7) prefixF = "µ"
            else                   prefixF = "n"
        } else {
            if (abs >= 1.2e-4)      prefixF = "m"
            else if (abs >= 1.2e-7) prefixF = "µ"
            else                    prefixF = "n"
        }
        if (prefixF === "m")      { scaled = value * 1e3; unit = "mF" }
        else if (prefixF === "µ") { scaled = value * 1e6; unit = "µF" }
        else                      { scaled = value * 1e9; unit = "nF" }
    } else if (baseUnit === "Hz") {
        if (abs >= 1.2e6)      { scaled = value / 1e6; unit = "MHz" }
        else if (abs >= 1.2e3) { scaled = value / 1e3; unit = "kHz" }
        fixedDecimals = 3
    } else if (baseUnit === "s") {
        if (abs > 0 && abs < 1e-6)      { scaled = value * 1e9; unit = "ns" }
        else if (abs > 0 && abs < 1e-3) { scaled = value * 1e6; unit = "µs" }
        else if (abs > 0 && abs < 1)    { scaled = value * 1e3; unit = "ms" }
        fixedDecimals = 3
    } else if (baseUnit === "°C") {
        fixedDecimals = 3
    } else if (mode === "Ratio") {
        fixedDecimals = 3
    }

    // 8-digit rule
    var decimals
    if (fixedDecimals !== null) {
        decimals = fixedDecimals
    } else {
        var absScaled = Math.abs(scaled)
        if (absScaled === 0 || !isFinite(absScaled)) {
            decimals = 7
        } else {
            var intDigits = Math.max(1, Math.floor(Math.log(absScaled) / Math.LN10) + 1)
            decimals = Math.max(0, 8 - intDigits)
        }
    }
    return {
        sign: scaled < 0 ? "-" : "",
        num: Math.abs(scaled).toFixed(decimals),
        unit: unit
    }
}

function fmt3(v) {
    if (v === null || v === undefined || !isFinite(v)) return "—"
    return v.toFixed(3)
}

function repeat(ch, n) {
    var out = ""
    for (var i = 0; i < n; i++) out += ch
    return out
}

// ============================================================
//  DMM graph Y-maximum + range hold logic (32 s)
// ============================================================
function dmmYMax(value, mode, range) {
    if (mode === "Diode") return 12
    if (range !== null && range !== undefined && isFinite(range) && Math.abs(range) > 0) {
        return Math.abs(range) * 1.2
    }
    if (value === null || value === undefined || !isFinite(value)) return 1.2
    var abs = Math.abs(value)
    if (abs < 1e-12) return 1.2
    var decade = Math.pow(10, Math.ceil(Math.log(abs) / Math.LN10))
    return decade * 1.2
}

var RANGE_HOLD_MS = 32000
var _dmmRangeHistory = ({})   // range (as string) -> last timestamp
var _dmmHistoryMode = null

function dmmEffectiveRange(currentRange, currentMode) {
    var now = Date.now()
    if (_dmmHistoryMode !== currentMode) {
        _dmmRangeHistory = ({})
        _dmmHistoryMode = currentMode
    }
    if (currentRange !== null && currentRange !== undefined && isFinite(currentRange)) {
        _dmmRangeHistory["" + currentRange] = now
    }
    var maxR = null
    for (var key in _dmmRangeHistory) {
        if (now - _dmmRangeHistory[key] > RANGE_HOLD_MS) {
            delete _dmmRangeHistory[key]
            continue
        }
        var rv = parseFloat(key)
        if (maxR === null || rv > maxR) maxR = rv
    }
    if (maxR === null) return currentRange
    return maxR
}
