import QtQuick 2.0
import QtWebSockets 1.0

// WebSocket client for the instrument STATE backend (server.py, ws://<PC>:7891).
// Connects, parses the JSON STATE, and exposes the devices as properties.
// Reconnects every 2 s -- analogous to the browser variant (overlay.js).
Item {
    id: root

    property string wsUrl: ""        // empty => default from OverlayConfig
    property bool   connected: false

    // Parsed STATE.devices.* -- empty defaults so bindings never see undefined.
    property var dmm:  ({ ok: false, mode: "—", value: null, unit: "", range: null })
    property var bb3a: ({ ok: false, mode: "—", voltage: null, current: null, output: null })
    property var bb3b: ({ ok: false, mode: "—", voltage: null, current: null, output: null,
                          dp: null, dn: null, protocol: "—" })
    property var kel:  ({ ok: false, mode: "—", voltage: null, current: null, output: null })

    property double lastTs: 0

    // Fired on every valid update -- graphs connect here.
    signal stateUpdated()

    function _applyState(state) {
        var d = state.devices || {}
        if (d.dmm)  root.dmm  = d.dmm
        if (d.bb3a) root.bb3a = d.bb3a
        if (d.bb3b) root.bb3b = d.bb3b
        if (d.kel)  root.kel  = d.kel
        if (state.ts) root.lastTs = state.ts
        root.stateUpdated()
    }

    WebSocket {
        id: socket
        url: root.wsUrl
        active: root.wsUrl.length > 0

        onTextMessageReceived: {
            try {
                root._applyState(JSON.parse(message))
            } catch (e) {
                console.warn("[instr] bad message:", e)
            }
        }

        onStatusChanged: {
            switch (status) {
            case WebSocket.Open:
                console.log("[instr] WS connected", url)
                root.connected = true
                break
            case WebSocket.Closed:
            case WebSocket.Error:
                if (root.connected) console.log("[instr] WS closed, reconnecting in 2 s")
                root.connected = false
                reconnectTimer.restart()
                break
            }
        }
    }

    Timer {
        id: reconnectTimer
        interval: 2000
        repeat: false
        onTriggered: {
            if (!root.connected && root.wsUrl.length > 0) {
                socket.active = false
                socket.active = true
            }
        }
    }

    function reconnect() {
        socket.active = false
        socket.active = true
    }
}
