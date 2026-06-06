import QtQuick 2.0
import Sailfish.Silica 1.0

// Component identification result as a read-only overlay at the bottom.
// INTENTIONALLY no MouseArea/Flickable -> does NOT capture taps (shutter stays free).
// Compact + small font; shows component information only (no live measurement reference).
Rectangle {
    id: card

    property var result: null        // parsed card (JS object) or null
    property bool busy: false
    property string error: ""

    // Font sizes small + centrally adjustable (tuning parameter).
    readonly property real fsHead: Theme.fontSizeExtraSmall * 0.95
    readonly property real fsBody: Theme.fontSizeExtraSmall * 0.78

    visible: busy || error.length > 0 || result !== null
    // Semi-transparent grey: contrast for text, image remains visible underneath.
    color: Qt.rgba(0.13, 0.13, 0.13, 0.5)
    radius: 0                          // full width, flush with edge
    height: content.height + 2 * Theme.paddingSmall

    function _txt(v) { return (v === undefined || v === null || v === "") ? "—" : "" + v }
    function _pct(v) { return (typeof v === "number") ? Math.round(v * 100) + " %" : "—" }

    Column {
        id: content
        // Starting at the far left (no left indent), only small vertical/right margin.
        anchors {
            left: parent.left; right: parent.right; bottom: parent.bottom
            leftMargin: 0; rightMargin: Theme.paddingSmall
            bottomMargin: Theme.paddingSmall; topMargin: Theme.paddingSmall
        }
        spacing: 0

        Label {
            visible: card.busy
            text: "Identifying ..."
            color: "white"
            font.pixelSize: card.fsBody
        }
        Label {
            width: parent.width
            visible: !card.busy && card.error.length > 0
            text: "Error: " + card.error
            color: "#ff6b6b"
            font.pixelSize: card.fsBody
            wrapMode: Text.Wrap
            maximumLineCount: 2
            elide: Text.ElideRight
        }

        // --- Result (compact) ---
        // Line 1: Class · Name/Value
        Label {
            width: parent.width
            visible: card.result !== null
            text: _txt(card.result ? card.result.klasse : null)
                  + (card.result && card.result.bezeichnung ? "  ·  " + card.result.bezeichnung
                       : (card.result && card.result.wert ? "  ·  " + card.result.wert : ""))
            color: "white"
            font { pixelSize: card.fsHead; bold: true }
            elide: Text.ElideRight
        }
        // Line 2: Manufacturer · Value(Tolerance) · Confidence
        Label {
            width: parent.width
            visible: card.result !== null
            text: (card.result && card.result.hersteller ? card.result.hersteller : "Manufacturer —")
                  + (card.result && card.result.wert ? "  ·  " + card.result.wert
                       + (card.result.toleranz ? " " + card.result.toleranz : "") : "")
                  + "  ·  " + _pct(card.result ? card.result.konfidenz : null)
            color: "white"
            font.pixelSize: card.fsBody
            elide: Text.ElideRight
        }
        // Line 3: expected measurement values (component spec, no live measurement reference)
        Label {
            width: parent.width
            visible: card.result !== null && (card.result.erwartung_ohm || card.result.erwartung_diode)
            text: (card.result && card.result.erwartung_ohm ? "Ω " + card.result.erwartung_ohm : "")
                  + (card.result && card.result.erwartung_diode
                       ? (card.result.erwartung_ohm ? "   " : "") + "Diode " + card.result.erwartung_diode : "")
            color: "#d0d0d0"
            font.pixelSize: card.fsBody
            elide: Text.ElideRight
        }
        // Line 4: a short note (max. 1 line)
        Label {
            width: parent.width
            visible: card.result !== null && card.result.hinweis
            text: _txt(card.result ? card.result.hinweis : null)
            color: "#c0c0c0"
            font.pixelSize: card.fsBody
            elide: Text.ElideRight
            maximumLineCount: 1
        }
        // Line 5: datasheet link (white, underlined, tappable -> opens in browser).
        // Only this label captures taps (small area bottom-left; shutter remains free).
        Label {
            id: dsLink
            width: parent.width
            visible: card.result !== null && card.result.datenblatt_url
            text: "Datasheet: " + (card.result && card.result.datenblatt_url ? card.result.datenblatt_url : "")
            color: "white"
            font { pixelSize: card.fsBody; underline: true }
            elide: Text.ElideRight
            maximumLineCount: 1
            MouseArea {
                anchors.fill: parent
                enabled: dsLink.visible
                onClicked: if (card.result && card.result.datenblatt_url)
                               Qt.openUrlExternally(card.result.datenblatt_url)
            }
        }
    }
}
