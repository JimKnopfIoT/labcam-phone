import QtQuick 2.0
import "OverlayConfig.js" as Cfg

// Scrolling mini-graph (replacement for smoothie.js).
// Ring buffer per series of {t, v}; x = width - (now - t)/millisPerPixel.
// Fixed scale via minValue/maxValue, otherwise auto (1.08 factor like smoothie).
Canvas {
    id: canvas

    property var    colors: [Cfg.COLORS.voltage]   // one color per series
    property real   lineWidth: Cfg.GRAPH.lineWidth
    property real   millisPerPixel: Cfg.GRAPH.millisPerPixel
    property real   minValue: 0
    property real   maxValue: NaN                   // NaN => auto-scale
    property bool   autoScale: isNaN(maxValue)

    // Solo series: -1 = draw all, otherwise only this one (then always auto scale,
    // otherwise e.g. the current disappears at the bottom of a 0..20 V scale).
    property int    soloSeries: -1

    // Each series gets its OWN scale (0 at the bottom, maximum at the top) AND its own
    // horizontal band: series 0 on top, series 1 below. A shared scale for volts AND amps
    // is meaningless anyway and flattens the smaller quantity (0.07 A next to 5.2 V) onto
    // the bottom edge; scaled individually, two constant values lie exactly on top of
    // each other (only the colour drawn last is visible).
    // Separate bands solve both.
    // The bands also apply in solo mode: A stays below, V stays on top. The trace must not
    // move when switching, or it looks like a different value.
    property bool   perSeries: false

    // Scale labels: a strip is kept free on the right, showing per band the upper scale
    // end at the top and the lower one (usually 0) at the bottom, in the series colour.
    property bool   showScale: true
    property real   axisFontSize: 10
    property var    units: []            // base unit per series ("V", "A", "Ω" ...)

    property color  bgColor:   Cfg.COLORS.graphBackground
    property color  gridColor: Cfg.COLORS.graphGrid
    property color  borderColor: Cfg.COLORS.graphBorder

    // One array of {t, v} per series. Non-reactive (redrawn via timer).
    property var _series: []

    function _ensureSeries(n) {
        while (_series.length < n) _series.push([])
    }

    // Append a value. seriesIndex 0..n-1.
    function append(seriesIndex, t, v) {
        _ensureSeries(seriesIndex + 1)
        if (v === null || v === undefined || !isFinite(v)) return
        _series[seriesIndex].push({ t: t, v: v })
    }

    // Mark a gap (e.g. DMM in overflow "OL"): the trace is interrupted
    // instead of being drawn across the missing period.
    function appendGap(seriesIndex, t) {
        _ensureSeries(seriesIndex + 1)
        var arr = _series[seriesIndex]
        if (arr.length > 0 && arr[arr.length - 1].v === null) return   // no double gap
        arr.push({ t: t, v: null })
    }

    // Advance series solo: all -> series 0 -> series 1 -> ... -> all.
    function toggleSolo() {
        var n = (colors && colors.length) ? colors.length : 1
        if (n < 2) return
        soloSeries = (soloSeries >= n - 1) ? -1 : soloSeries + 1
        requestPaint()
    }

    // Compact scale number with engineering prefix: 12000000 -> "12M", 0.0216 -> "21.6m".
    function _fmtAxis(v) {
        if (v === null || v === undefined || !isFinite(v)) return ""
        var a = Math.abs(v)
        if (a < 1e-12) return "0"
        var PFX = [[1e9, "G"], [1e6, "M"], [1e3, "k"], [1, ""], [1e-3, "m"], [1e-6, "µ"], [1e-9, "n"]]
        for (var i = 0; i < PFX.length; i++) {
            if (a >= PFX[i][0]) {
                var n = v / PFX[i][0]
                var t = (Math.abs(n) >= 10) ? n.toFixed(0) : n.toFixed(1)
                if (t.length > 2 && t.substring(t.length - 2) === ".0") t = t.substring(0, t.length - 2)
                return t + PFX[i][1]
            }
        }
        return v.toExponential(0)
    }

    function clearAll() {
        _series = []
        requestPaint()
    }

    function _prune(now) {
        // Discard points that have scrolled off the left edge by more than (width+50)px.
        var maxAge = (width + 50) * millisPerPixel
        for (var s = 0; s < _series.length; s++) {
            var arr = _series[s]
            var cut = 0
            while (cut < arr.length - 1 && (now - arr[cut].t) > maxAge) cut++
            if (cut > 0) _series[s] = arr.slice(cut)
        }
    }

    Timer {
        interval: 100; running: canvas.visible; repeat: true
        onTriggered: canvas.requestPaint()
    }

    onPaint: {
        var ctx = getContext("2d")
        var w = width, h = height
        ctx.clearRect(0, 0, w, h)

        // Background + border
        ctx.fillStyle = bgColor
        ctx.fillRect(0, 0, w, h)

        var now = Date.now()
        _prune(now)

        var solo = soloSeries >= 0

        // --- Min/max of a series (gaps skipped) ---
        function _bounds(idx) {
            var mn = Number.POSITIVE_INFINITY, mx = Number.NEGATIVE_INFINITY
            var a = _series[idx] || []
            for (var i0 = 0; i0 < a.length; i0++) {
                var v0 = a[i0].v
                if (v0 === null) continue
                if (v0 < mn) mn = v0
                if (v0 > mx) mx = v0
            }
            return { mn: mn, mx: mx }
        }
        // Auto scale with zero at the bottom (the natural reading for V/A/Ω).
        function _zeroBased(mn, mx) {
            if (!isFinite(mn) || !isFinite(mx)) return { lo: 0, hi: 1 }
            var lo0 = Math.min(0, mn)
            var hi0 = (mx > lo0) ? lo0 + (mx - lo0) * 1.08 : lo0 + 1
            return { lo: lo0, hi: hi0 }
        }

        // --- Determine the scale per series ---
        var scales = []
        var sharedAuto = null
        for (var s1 = 0; s1 < _series.length; s1++) {
            if (solo || perSeries) {
                var b = _bounds(s1)
                scales.push(_zeroBased(b.mn, b.mx))
            } else if (autoScale) {
                if (sharedAuto === null) {
                    var mn2 = Number.POSITIVE_INFINITY, mx2 = Number.NEGATIVE_INFINITY
                    for (var s2 = 0; s2 < _series.length; s2++) {
                        var b2 = _bounds(s2)
                        if (b2.mn < mn2) mn2 = b2.mn
                        if (b2.mx > mx2) mx2 = b2.mx
                    }
                    if (!isFinite(mn2) || !isFinite(mx2)) { mn2 = 0; mx2 = 1 }
                    if (mn2 === mx2) { mn2 -= 0.5; mx2 += 0.5 }
                    var mid = (mn2 + mx2) / 2, half = (mx2 - mn2) / 2 * 1.08
                    sharedAuto = { lo: mid - half, hi: mid + half }
                }
                scales.push(sharedAuto)
            } else {
                scales.push({ lo: minValue, hi: maxValue })
            }
        }

        // Bands: without perSeries the trace uses the full height, otherwise each series gets
        // a fixed horizontal band (V on top, A below), regardless of whether both or only
        // one series is drawn at the moment (the trace must not jump).
        var bandCount = !perSeries ? 1
                      : Math.max(1, (colors && colors.length) ? colors.length : _series.length)
        var bandH = h / bandCount

        // Leave a little room at the top and bottom: a trace at 0 would otherwise sit exactly
        // on the edge and could not be seen there.
        var inset = Math.min(lineWidth, bandH / 4)

        // Clamp y: a single outlier (e.g. a sentinel that slipped through) otherwise
        // produces coordinates around 1e33, the rasterizer then discards the
        // WHOLE path and the trace disappears.
        function yPix(sc, band, v) {
            var span = (sc.hi - sc.lo) || 1
            var top = band * bandH
            var y = (top + bandH - inset) - ((v - sc.lo) / span) * Math.max(1, bandH - 2 * inset)
            if (y < -h) return -h
            if (y > 2 * h) return 2 * h
            return y
        }

        // --- Keep the right-hand strip free for the scale ---
        // Readability over completeness: if two numbers do not fit into a band, only the
        // upper scale end is shown (the scale is always zero-based, so the bottom is 0).
        var bothLabels = bandH >= 2.3 * axisFontSize
        var axisFont = bothLabels ? axisFontSize
                                  : Math.max(6, Math.min(axisFontSize, bandH * 0.8))
        ctx.font = axisFont + "px sans-serif"
        var labels = []          // per series {top, bot} or null
        var axisW = 0
        for (var s3 = 0; s3 < _series.length; s3++) {
            if (!showScale || (solo && s3 !== soloSeries) || _series[s3].length < 1) {
                labels.push(null)
                continue
            }
            var u = (units && units[s3] !== undefined && units[s3] !== null) ? units[s3] : ""
            var lab = { top: _fmtAxis(scales[s3].hi) + u,
                        bot: bothLabels ? _fmtAxis(scales[s3].lo) : "" }
            labels.push(lab)
            axisW = Math.max(axisW, ctx.measureText(lab.top).width, ctx.measureText(lab.bot).width)
        }
        if (axisW > 0) axisW = Math.min(axisW + 6, w * 0.4)
        var plotW = w - axisW

        // Draw series
        for (var s = 0; s < _series.length; s++) {
            if (solo && s !== soloSeries) continue
            var arr = _series[s]
            if (arr.length < 1) continue
            ctx.strokeStyle = colors[s] !== undefined ? colors[s] : "#ffffff"
            ctx.lineWidth = lineWidth
            ctx.lineJoin = "round"
            ctx.beginPath()
            var started = false
            for (var i = 0; i < arr.length; i++) {
                if (arr[i].v === null) { started = false; continue }   // gap
                var x = plotW - (now - arr[i].t) / millisPerPixel
                var y = yPix(scales[s], bandCount > 1 ? s : 0, arr[i].v)
                if (!started) { ctx.moveTo(x, y); started = true }
                else          { ctx.lineTo(x, y) }
            }
            ctx.stroke()
        }

        // Label the scale ends on the right (colour = series colour)
        if (axisW > 0) {
            ctx.textAlign = "right"
            for (var s4 = 0; s4 < labels.length; s4++) {
                if (!labels[s4]) continue
                var bTop = (bandCount > 1 ? s4 : 0) * bandH
                ctx.fillStyle = colors[s4] !== undefined ? colors[s4] : "#ffffff"
                ctx.textBaseline = "top"
                ctx.fillText(labels[s4].top, w - 3, bTop + 1)
                if (labels[s4].bot.length > 0) {
                    ctx.textBaseline = "bottom"
                    ctx.fillText(labels[s4].bot, w - 3, bTop + bandH - 1)
                }
            }
        }
    }
}
