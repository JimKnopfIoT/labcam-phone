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
        ctx.strokeStyle = borderColor
        ctx.lineWidth = 1
        ctx.strokeRect(0.5, 0.5, w - 1, h - 1)

        var now = Date.now()
        _prune(now)

        // Determine scale
        var lo = minValue, hi = maxValue
        if (autoScale) {
            lo = Number.POSITIVE_INFINITY; hi = Number.NEGATIVE_INFINITY
            for (var s0 = 0; s0 < _series.length; s0++) {
                var a0 = _series[s0]
                for (var i0 = 0; i0 < a0.length; i0++) {
                    if (a0[i0].v < lo) lo = a0[i0].v
                    if (a0[i0].v > hi) hi = a0[i0].v
                }
            }
            if (!isFinite(lo) || !isFinite(hi)) { lo = 0; hi = 1 }
            if (lo === hi) { lo -= 0.5; hi += 0.5 }
            var mid = (lo + hi) / 2, half = (hi - lo) / 2 * 1.08
            lo = mid - half; hi = mid + half
        }
        var span = (hi - lo) || 1

        function yPix(v) { return h - ((v - lo) / span) * h }

        // Draw series
        for (var s = 0; s < _series.length; s++) {
            var arr = _series[s]
            if (arr.length < 1) continue
            ctx.strokeStyle = colors[s] !== undefined ? colors[s] : "#ffffff"
            ctx.lineWidth = lineWidth
            ctx.lineJoin = "round"
            ctx.beginPath()
            var started = false
            for (var i = 0; i < arr.length; i++) {
                var x = w - (now - arr[i].t) / millisPerPixel
                var y = yPix(arr[i].v)
                if (!started) { ctx.moveTo(x, y); started = true }
                else          { ctx.lineTo(x, y) }
            }
            ctx.stroke()
        }
    }
}
