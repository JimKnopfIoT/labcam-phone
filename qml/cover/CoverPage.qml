import QtQuick 2.0
import Sailfish.Silica 1.0

CoverBackground {
    // faint oversized app-icon watermark behind the cover content
    Image {
        anchors.centerIn: parent
        source: "/usr/share/icons/hicolor/172x172/apps/harbour-labcam.png"
        sourceSize { width: 172; height: 172 }
        width: parent.width * 1.5
        height: width
        fillMode: Image.PreserveAspectFit
        opacity: 0.12
        smooth: true
        asynchronous: true
    }

    TextArea {
        id: label
        anchors.centerIn: parent
        color: Theme.primaryColor
        font.bold: true
        horizontalAlignment: Text.AlignHCenter
        readOnly: true
        width: parent.width - 2 * Theme.paddingSmall
        text: qsTr("Advanced Camera")
    }
}
