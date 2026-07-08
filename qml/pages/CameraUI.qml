import QtQuick 2.0
import Sailfish.Silica 1.0
import QtMultimedia 5.6
import QtPositioning 5.2
import QtSensors 5.0
import Nemo.KeepAlive 1.2
import QtQuick.Layouts 1.1
import uk.co.piggz.harbour_advanced_camera 1.0
import "../components/"
import "../overlay/"

Page {
    id: page

    // The effective value will be restricted by ApplicationWindow.allowedOrientations
    allowedOrientations: Orientation.All

    property alias camera: camera
    property bool _cameraReload: false
    property bool _completed: false
    property bool _focusAndSnap: false
    property bool _loadParameters: true
    property bool _recordingVideo: false
    property bool _manualModeSelected: false
    readonly property real zoomStepSize: 0.05
    readonly property real zoomStepButton: 5.0
    property int controlsRotation: 0
    property int _pictureRotation: Screen.primaryOrientation == Qt.PortraitOrientation ? 0 : 90
    // Use easy device orientation values
    // 0=unknown, 1=portrait, 2=portrait inverted, 3=landscape, 4=landscape inverted
    property int _orientation: OrientationReading.TopUp
    property bool showInstruments: true
    // P2-Pro thermal camera: 0=off, 1=area (aligned over the camera image), 2=fullscreen. Button cycles.
    property int irMode: 0
    // Align IR to the camera frame (area mode): zoom + offset (parallax, main camera top / P2 Pro bottom).
    // Applies live AND to the burned-in photo (uses the on-screen position).
    // ==> calibrate these 3 values via screenshot at a typical working distance.
    property real irAlignScale: 1.0   // (Area: full width; value only for optional fine-tuning)
    property real irAlignVPos: 1.0    // (Area now uses irSplit instead of VPos)
    property real irSplit: 0.5        // Area mode: IR occupies the lower (1-irSplit) fraction of screen height (0.5 = half/half)
    property real irAlignDx: 0        // x offset in px (fine-tuning)
    property real irAlignDy: 0        // y offset in px (positive = further down)
    // Zoom/crop + shift the camera viewfinder ONLY in IR mode so it roughly matches the IR area
    // (parallax/FOV; exact match not required). ==> calibrate via screenshot.
    property real camZoomIr: 1.0      // Zoom/crop of camera image when IR is on (1 = off)
    property real camDxIr: 0          // x offset of camera image (px) in IR mode
    property real camDyIr: 0          // y offset of camera image (px) in IR mode (positive = down)
    // P2-Pro temperature (lower stream half -> degrees C in C++): optional overlays.
    property bool irShowMarkers: false   // hotspots (min/max) + tap measurement points
    property bool irShowBar: false       // temperature scale/colorbar on the right
    // IR camera status: has a frame arrived since switch-on? And did we wait long enough
    // (probe) to show "no camera detected"?
    property bool _irFrameSeen: false
    property bool _irProbed: false

    // After switching on, wait briefly for the first IR frame; if none arrives -> notice.
    Timer {
        id: irProbeTimer
        interval: 2500
        repeat: false
        onTriggered: if (!page._irFrameSeen) page._irProbed = true
    }

    // Burn overlay into the photo when shooting (non-destructive: also creates *_ovl.jpg)
    property bool burnOverlayIntoPhoto: true
    // Portrait: overlay strip width as a fraction of the viewfinder/photo width (layout + burn-in)
    readonly property real instrumentStripFraction: 0.36

    // ---- Image area (letterbox) in PAGE coordinate system (visual orientation) ----
    // IMPORTANT: Do NOT use videoOutput.contentRect -- it is in the window/physical
    // coordinate system and does NOT match the rotated page in landscape (was the cause of
    // the broken landscape display). Instead, compute from page dimensions + image aspect
    // ratio (like GridOverlay: centered, constrained to the shorter axis).
    readonly property bool _isPortrait: page.height > page.width
    readonly property real _sensorAspect: {
        var r = (settings.global.captureMode === "image")
                ? camera.imageCapture.resolution : camera.videoRecorder.resolution
        return (r && r.width > 0 && r.height > 0) ? (r.width / r.height) : (16.0 / 9.0)
    }
    // Display aspect ratio (W/H) in the current visual orientation.
    readonly property real _imgAspect: _isPortrait ? (1.0 / _sensorAspect) : _sensorAspect
    readonly property rect _imgRect: {
        var pw = page.width, ph = page.height
        var a = _imgAspect
        var iw, ih
        if (pw / ph > a) { ih = ph; iw = ph * a }   // Page wider than image -> left/right margins
        else             { iw = pw; ih = pw / a }   // top/bottom margins
        return Qt.rect((pw - iw) / 2, (ph - ih) / 2, iw, ih)
    }

    property string _pendingPhotoPath: ""
    property string _pendingOverlayPath: ""
    property real _pendingOverlayFraction: 1.0
    property bool _overlayInFlight: false
    // Burn IR thermal image into the photo (WYSIWYG at the display position)
    property string _pendingIrPath: ""
    property bool _irInFlight: false
    property rect _irRect: Qt.rect(0, 0, 0, 0)   // normalized against page._imgRect

    // ---- Component ID (phase 3) ----
    property Item videoOutput: null        // set by root (viewfinder VideoOutput) for ROI mapping
    property bool componentMode: false     // selection frame + identify active (opt-in; off = no API usage)
    property bool _identifyPending: false
    property string _idPhotoPath: ""       // last photo taken for identify (for save-with-text)

    // When turning off, reset everything: no pending request, card gone, nothing hanging.
    onComponentModeChanged: {
        if (!componentMode) {
            _identifyPending = false
            componentCard.busy = false
            componentCard.result = null
            componentCard.error = ""
        }
    }

    OrientationSensor {
        id: orientationSensor
        active: true

        onReadingChanged: {
            if (reading.orientation >= OrientationReading.TopUp
                    && reading.orientation <= OrientationReading.RightUp) {
                _orientation = reading.orientation
                console.log("Orientation:", reading.orientation, _orientation);
            }

            switch (reading.orientation) {
            case OrientationReading.TopUp:
                _pictureRotation = 0; break
            case OrientationReading.TopDown:
                _pictureRotation = 180; break
            case OrientationReading.LeftUp:
                _pictureRotation = 270; break
            case OrientationReading.RightUp:
                _pictureRotation = 90; break
            default:
                // Keep device orientation at previous state
            }
        }
    }

    DisplayBlanking {
        preventBlanking: camera.videoRecorder.recorderState === CameraRecorder.RecordingState
    }

    PositionSource {
        id: positionSource

        active: settings.global.locationMetadata

        onActiveChanged: {
            // PositionSource is activated a moment after initialization
            // regardless "active" property assignment. It looks like Qt bug.
            // Code below workaround it.
            console.log("positionSource.active: " + positionSource.active)
            if (positionSource.active != settings.global.locationMetadata) {
                if (settings.global.locationMetadata) {
                    start();
                } else {
                    stop();
                }
            }
        }

        updateInterval: 1000 // ms
    }

    // Orientation sensors for primary (back camera) & secondary (front camera)
    readonly property var _rotationValues: {
        "primary": [270, 270, 90, 180, 0, 270, 270],
        "secondary"//Uses orientation sensor value 0-6
        : [90, 90, 270, 180, 0, 90, 90],
        "ui": [0, 90, 0, 0, 270, 0, 0, 0, 180] //Uses enum value 1,2,4,8
    }

    readonly property int viewfinderOrientation: {
        var rotation = 0
        switch (orientation) {
        case Orientation.Landscape:
            rotation = 90
            break
        case Orientation.PortraitInverted:
            rotation = 180
            break
        case Orientation.LandscapeInverted:
            rotation = 270
            break
        }

        return (720 + camera.orientation + rotation) % 360
    }

    RotationAnimation on controlsRotation {
        running: _orientation === OrientationReading.TopUp
        to: 270
        duration: 200
        direction: RotationAnimation.Shortest
    }
    RotationAnimation on controlsRotation {
        running: _orientation === OrientationReading.TopDown
        to: 90
        duration: 200
        direction: RotationAnimation.Shortest
    }
    RotationAnimation on controlsRotation {
        running: _orientation === OrientationReading.LeftUp
        to: 180
        duration: 200
        direction: RotationAnimation.Shortest
    }
    RotationAnimation on controlsRotation {
        running: _orientation === OrientationReading.RightUp
        to: 0
        duration: 200
        direction: RotationAnimation.Shortest
    }

    focus: true

    defaultOrientationTransition: Transition {
        NumberAnimation {
        }
    }

    Camera {
        id: camera

        cameraState: page._completed
                     && !page._cameraReload ? Camera.ActiveState : Camera.UnloadedState

        imageProcessing.colorFilter: CameraImageProcessing.ColorFilterNone
        imageProcessing.denoisingLevel: 1
        imageProcessing.contrast: 1
        imageProcessing.sharpeningLevel: 1

        // Write Orientation to metadata
        metaData.orientation:  camera.position === Camera.FrontFace ? (720 + camera.orientation - _pictureRotation) % 360 : (720 + camera.orientation + _pictureRotation) % 360
        metaData.cameraManufacturer: CameraManufacturer === "" ? null : CameraManufacturer
        metaData.cameraModel: CameraPrettyModelName === "" ? null : CameraPrettyModelName

        metaData.gpsSpeed: settings.global.locationMetadata && positionSource.position.speedValid ? positionSource.speed : null
        metaData.gpsImgDirection: settings.global.locationMetadata && positionSource.directionValid ? positionSource.direction : null

        metaData.gpsLatitude: settings.global.locationMetadata && positionSource.position.latitudeValid ? positionSource.position.coordinate.latitude : null
        metaData.gpsLongitude: settings.global.locationMetadata && positionSource.position.longitudeValid ? positionSource.position.coordinate.longitude : null
        metaData.gpsAltitude: settings.global.locationMetadata && positionSource.position.altitudeValid ? positionSource.position.coordinate.altitude : null

        exposure {
            //exposureCompensation: -1.0
            exposureMode: Camera.ExposureAuto
        }

        flash.mode: Camera.FlashOff

        imageCapture {
            onImageCaptured: {
                photoPreview.source = preview // Show the preview in an Image
                console.log("Camera: captured", photoPreview.source)
            }
            onImageSaved: {
                console.log("Camera: image saved", path)
                if (_identifyPending) {
                    _identifyPending = false
                    _idPhotoPath = path   // remember: for "save photo with text"
                    _runIdentify(path)    // component ID: not added to gallery, no burn-in
                    return
                }
                // Do NOT add the original directly to the gallery -- let _tryCompose decide:
                // with overlay -> keep only the composited _ovl (delete original),
                // without overlay -> keep original.
                _pendingPhotoPath = path
                _tryCompose()
            }
            onResolutionChanged: {
                console.log("Image resolution changed:",
                            camera.imageCapture.resolution)
                camera.viewfinder.resolution = getNearestViewFinderResolution()
            }
        }

        videoRecorder {
            audioSampleRate: 48000
            audioBitRate: settings.global.audioBitrate
            audioChannels: 1
            audioCodec: "audio/mpeg, mpegversion=(int)4"
            frameRate: 30
            videoCodec: "video/x-h264"
            mediaContainer: "video/quicktime, variant=(string)iso"
            videoEncodingMode: CameraRecorder.AverageBitRateEncoding
            videoBitRate: settings.global.videoBitrate

            onRecorderStateChanged: {
                if (camera.videoRecorder.recorderState === CameraRecorder.StoppedState) {
                    console.log("saved to: " + camera.videoRecorder.outputLocation)
                }
            }

            onRecorderStatusChanged: {
                if (camera.videoRecorder.recorderStatus === CameraRecorder.FinalizingStatus) {
                    var path = camera.videoRecorder.outputLocation.toString()
                    path = path.replace(/^(file:\/{2})/, "")
                    galleryModel.append({
                                            "filePath": path,
                                            "isVideo": true
                                        })
                }
            }

            onResolutionChanged: {
                console.log("Video resolution changed:",
                            settings.resolution("video"))
                camera.viewfinder.resolution = getNearestViewFinderResolution()
            }
        }

        onLockStatusChanged: {
            if (camera.lockStatus === Camera.Locked && _focusAndSnap
                    && !_recordingVideo) {
                camera.metaData.date = new Date()
                _beginCapture()
                camera.imageCapture.captureToLocation(
                            fsOperations.writableLocation(
                                "image",
                                settings.global.storagePath) + "/IMG_" + Qt.formatDateTime(
                                new Date(), "yyyyMMdd_hhmmss") + ".jpg")
                animFlash.start()
                _focusAndSnap = false
            }
        }

        onCameraStatusChanged: {
            console.log("Camera status:", cameraStatusStr())

            if (cameraStatus === Camera.StartingStatus) {
                settingsOverlay.setCamera(camera)
            }

            if (cameraStatus === Camera.ActiveStatus && _loadParameters) {
                if (zoomSlider.maximumValue != camera.maximumDigitalZoom) {
                    zoomSlider.maximumValue = camera.maximumDigitalZoom
                }

                if (settings.global.captureMode === "video") {
                    camera.captureMode = Camera.CaptureVideo
                    btnModeSwitch._hilighted2 = true
                } else {
                    camera.captureMode = Camera.CaptureStillImage
                    btnModeSwitch._hilighted2 = false
                }

                settingsOverlay.setMode(settings.global.captureMode)

                camera.viewfinder.resolution = getNearestViewFinderResolution()
                applySettings()

                lblResolution.forceUpdate = !lblResolution.forceUpdate
            }
        }

        onOrientationChanged: {
            console.log("Orientation:", orientation);
        }
    }

    Item {
        id: controlsContainer
        z: page.irMode > 0 ? 1 : 0   // when IR is active, raise controls above the IR overlay
        rotation: _rotationValues["ui"][page.orientation]
        width: page.orientation === Orientation.Portrait
               || page.orientation === Orientation.PortraitInverted ? parent.height : parent.width
        height: page.orientation === Orientation.Portrait
                || page.orientation === Orientation.PortraitInverted ? parent.width : parent.height
        anchors.centerIn: parent

        GridOverlay {
            aspect: settings.global.captureMode
                    === "image" ? ratio(camera.imageCapture.resolution) : ratio(
                                      camera.videoRecorder.resolution)

            function ratio(resolution) {
                return resolution.width / resolution.height
            }
        }

        Slider {
            id: zoomSlider
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom
            width: parent.width * 0.75
            minimumValue: 1
            maximumValue: camera.maximumDigitalZoom
            value: camera.digitalZoom
            stepSize: zoomStepSize
            rotation: {
                // Zoom slider should be slide up to zoom in
                if (_orientation === OrientationReading.TopUp)
                    return -180
                else if (_orientation === OrientationReading.TopDown)
                    return 0
                else if (_orientation === OrientationReading.LeftUp)
                    return 180
                else if (_orientation === OrientationReading.RightUp)
                    return 0
            }

            onValueChanged: {
                if (value != camera.digitalZoom)
                    camera.digitalZoom = value
            }

            Connections {
                target: camera

                onDigitalZoomChanged: {
                    zoomSlider.value = camera.digitalZoom
                }
            }
        }

        Image {
            id: photoPreview
            rotation: page.controlsRotation
            onStatusChanged: {
                if (photoPreview.status === Image.Ready) {
                    console.log('photoPreview ready')
                }
            }
        }

        RoundButton {
            id: btnCapture

            anchors.verticalCenter: parent.verticalCenter
            anchors.right: parent.right
            anchors.rightMargin: Theme.paddingMedium

            size: Theme.itemSizeLarge
            rotation: page.controlsRotation

            image: shutterIcon()
            icon.anchors.margins: Theme.paddingSmall
            onClicked: doShutter()
        }


        RoundButton {
            id: teleLense
            image: camera.deviceId == "1" ? "../pics/icon-m-tele-lense-active.png" : "../pics/icon-m-tele-lense.png"
            size: Theme.itemSizeSmall
            icon.anchors.margins: Theme.paddingSmall
            onClicked: if (settings.global.cameraId != "1") { switchCamera("1")}
            anchors.right: btnCapture.left
            anchors.rightMargin: Theme.paddingLarge * 1.337
            anchors.bottom: wideLense.top
            anchors.bottomMargin: Theme.paddingSmall
            rotation: page.controlsRotation
            visible: checkIfCamExists("1") && (camera.videoRecorder.recorderStatus !== CameraRecorder.RecordingStatus) && settings.global.cameraCount > 3 && settings.global.enableWideCameraButtons
        }
        RoundButton {
            id: wideLense
            image: camera.deviceId == "0" ? "../pics/icon-m-wide-lense-active.png" : "../pics/icon-m-wide-lense.png"
            size: Theme.itemSizeSmall
            icon.anchors.margins: Theme.paddingSmall
            onClicked: if (settings.global.cameraId != "0") { switchCamera("0")}
            anchors.right: btnCapture.left
            anchors.rightMargin: Theme.paddingLarge * 1.337
            anchors.verticalCenter: btnCapture.verticalCenter
            rotation: page.controlsRotation
            visible: checkIfCamExists("0") && (camera.videoRecorder.recorderStatus !== CameraRecorder.RecordingStatus) && settings.global.cameraCount > 3 && settings.global.enableWideCameraButtons
        }
        RoundButton {
            id: uwideLense
            image: camera.deviceId == "2" ? "../pics/icon-m-uwide-lense-active.png" : "../pics/icon-m-uwide-lense.png"
            size: Theme.itemSizeSmall
            icon.anchors.margins: Theme.paddingSmall
            onClicked: if (settings.global.cameraId != "2") { switchCamera("2")}
            anchors.right: btnCapture.left
            anchors.rightMargin: Theme.paddingLarge * 1.337
            anchors.top: wideLense.bottom
            anchors.topMargin: Theme.paddingSmall
            rotation: page.controlsRotation
            visible: checkIfCamExists("2") && (camera.videoRecorder.recorderStatus !== CameraRecorder.RecordingStatus) && settings.global.cameraCount > 3 && settings.global.enableWideCameraButtons
        }


        Rectangle {
            id: rectFlash
            anchors.fill: parent
            opacity: 0

            NumberAnimation on opacity {
                id: animFlash
                from: 1.0
                to: 0.0
                duration: 200
            }
        }

        Column {
            id: grdOnscreenControls
            spacing: Theme.paddingMedium
            rotation: page.controlsRotation
            height: childrenRect.height

            anchors.horizontalCenter: {
                if ((_orientation === OrientationReading.TopUp)
                        || (_orientation === OrientationReading.TopDown))
                    return parent.right
                else
                    return parent.horizontalCenter
            }

            anchors.verticalCenter: {
                if ((_orientation === OrientationReading.TopUp)
                        || (_orientation === OrientationReading.TopDown))
                    return parent.verticalCenter
                else
                    return parent.top
            }

            anchors.verticalCenterOffset: {
                if ((_orientation === OrientationReading.TopUp)
                        || (_orientation === OrientationReading.TopDown))
                    return 0
                else
                    return Theme.itemSizeLarge
            }

            anchors.horizontalCenterOffset: {
                if ((_orientation === OrientationReading.TopUp)
                        || (_orientation === OrientationReading.TopDown))
                    return -(btnCapture.width + height + teleLense.height)
                else
                    return 0
            }

            Row {
                id: rowTop
                spacing: Theme.paddingMedium

                Item {
                    height: 1
                    width: Theme.itemSizeLarge
                }

                Label {
                    id: lblCameraId
                    text: qsTr("Camera: ") + camera.deviceId
                    color: Theme.lightPrimaryColor
                }

                Label {
                    property bool forceUpdate: false
                    id: lblResolution
                    color: Theme.lightPrimaryColor
                    text: (forceUpdate
                           || !forceUpdate) ? settings.sizeToStr(
                                                  (settings.global.captureMode === "video" ? camera.videoRecorder.resolution : camera.imageCapture.resolution)) : ""
                }

                Label {
                    id: lblRecordTime
                    visible: settings.global.captureMode === "video"
                    color: Theme.lightPrimaryColor
                    //text: Qt.formatDateTime(new Date(camera.videoRecorder.duration), "hh:mm:ss") //Doest work as return 01:00:00 for 0
                    text: msToTime(camera.videoRecorder.duration)
                }
                Item {
                    height: 1
                    width: Theme.itemSizeLarge
                }
            }

            Slider {
                id: exposureCompensationSlider
                width: rowTop.childrenRect.width
                minimumValue: -2
                maximumValue: +2
                value: 0
                stepSize: 0.1
                visible: settings.global.showManualControls
                valueText : (Math.round(value*10)/10) + " EV"

                onValueChanged: {
                    if (value != camera.exposure.exposureCompensation)
                        camera.exposure.exposureCompensation = value
                }

                Connections {
                    target: camera.exposure

                    onExposureCompensationChanged: {
                        exposureCompensationSlider.value = camera.exposure.exposureCompensation
                    }
                }
            }
        }

        SettingsOverlay {
            id: settingsOverlay
            iconRotation: page.controlsRotation
        }

        RoundButton {
            id: btnGallery

            visible: galleryModel.count > 0
            enabled: visible

            anchors.top: btnCameraSwitch.bottom
            anchors.bottomMargin: Theme.paddingMedium
            anchors.right: parent.right
            anchors.rightMargin: Theme.paddingMedium
            icon.rotation: page.controlsRotation

            size: Theme.itemSizeSmall

            image: "image://theme/icon-m-image"

            onClicked: {
                camera.stop()
                pageStack.push(Qt.resolvedUrl("GalleryUI.qml"), {
                                   "fileList": galleryModel
                               })
            }
        }

        RoundButton {
            id: btnCameraSwitch
            icon.source: "image://theme/icon-camera-switch"
            visible: settings.global.cameraCount > 1
            icon.rotation: page.controlsRotation
            property string prevCamId
            anchors {
                top: parent.top
                topMargin: Theme.paddingMedium
                right: parent.right
                rightMargin: Theme.paddingMedium
            }
            onClicked: {
                switchToNextCamera()
            }
        }

        IconSwitch {
            id: btnModeSwitch
            anchors.bottom: parent.bottom
            anchors.bottomMargin: Theme.paddingMedium
            anchors.right: parent.right
            anchors.rightMargin: (rotation === 90
                                  || rotation === 270) ? Theme.paddingLarge
                                                         * 2 : Theme.paddingMedium
            rotation: page.controlsRotation
            width: Theme.itemSizeSmall

            icon1Source: "image://theme/icon-camera-camera-mode"
            icon2Source: "image://theme/icon-camera-video"
            button1Name: "image"
            button2Name: "video"

            onClicked: {
                console.log("selected:", name)
                camera.stop()
                settingsOverlay.setMode(name)
                if (name === button1Name) {
                    camera.captureMode = Camera.CaptureStillImage
                } else {
                    camera.captureMode = Camera.CaptureVideo
                }
                camera.start()
            }
        }
    }

    //End controlsContainer

    // ---- Instrument overlay (lab instruments via WebSocket) ----
    InstrumentBar {
        id: instrumentBar
        visible: page.showInstruments
        z: 2                       // above the IR overlay -> stays visible even in fullscreen
        // Orientation from actual page geometry (more reliable than isPortrait).
        readonly property bool _portrait: page.height > page.width
        portrait: _portrait

        // Anchor to the image area computed in PAGE coordinates (page._imgRect) so the bar
        // stays within the image in both orientations. Portrait: at the very top, at the edge.
        x: page._imgRect.x + Theme.paddingMedium
        y: _portrait ? Theme.paddingMedium : (page._imgRect.y + Theme.paddingMedium)
        // Landscape: 4 panels across the full image width at the top. Portrait: narrow strip LEFT.
        width: _portrait
               ? Math.round(page._imgRect.width * page.instrumentStripFraction)
               : Math.round(page._imgRect.width - 2 * Theme.paddingMedium)
    }

    // ---- P2 Pro thermal camera (V4L2 via thermalCam, image://thermal/<frame>) ----
    // irMode 1 = area: IR aligned to the camera frame (zoom + offset, irAlign*),
    //   centered over page._imgRect. 2 = fullscreen (whole page).
    // z=0: sits above camera/instruments (declared earlier), but BELOW the buttons.
    Rectangle {
        id: irView
        visible: page.irMode > 0
        z: 0
        color: page.irMode === 2 ? "black" : "transparent"

        readonly property bool _portrait: page.height > page.width
        // Aligned area: width = image width * scale; 4:3 (landscape) or 3:4 (portrait).
        readonly property real _alignW: page._imgRect.width * page.irAlignScale
        readonly property real _alignH: _portrait ? _alignW * 4 / 3 : _alignW * 3 / 4
        // Area mode: portrait = lower half of screen (two halves, full width).
        //   Landscape = bottom-right corner: from below the instruments to bottom, 4:3 width,
        //   but at most up to the screen center. Fullscreen = whole page. Instruments on top via z.
        readonly property real _barBottom: instrumentBar.visible
            ? (instrumentBar.y + instrumentBar.height + Theme.paddingMedium) : 0
        readonly property real _landH: Math.max(0, page.height - _barBottom)
        readonly property real _landW: Math.min(_landH * 4 / 3, page.width / 2)

        width:  page.irMode === 2 ? page.width
                : (_portrait ? page.width : _landW)
        height: page.irMode === 2 ? page.height
                : (_portrait ? (page.height * (1 - page.irSplit)) : _landH)
        x: page.irMode === 2 ? 0
           : (_portrait ? page.irAlignDx : (page.width - _landW + page.irAlignDx))
        y: page.irMode === 2 ? 0
           : (_portrait ? (page.height * page.irSplit + page.irAlignDy) : (_barBottom + page.irAlignDy))

        // User measurement points (normalized 0..1 over the thermal image, landscape orientation).
        ListModel { id: irPoints }

        // Mapping thermal-normalized (nx,ny) <-> irView local coordinates. Takes into account
        // the image rotation (_irRot) and fillMode (Crop in area mode / Fit in fullscreen). Source
        // is landscape (4:3), so aS=4/3 relative to the UN-rotated item dimensions.
        readonly property real _srcAspect: 4 / 3
        function _disp() {
            var wI = _portrait ? height : width      // item dimensions BEFORE rotation
            var hI = _portrait ? width  : height
            var aS = _srcAspect
            var fit = (page.irMode === 2)
            var dW = fit ? Math.min(wI, hI * aS) : Math.max(wI, hI * aS)
            var dH = fit ? Math.min(hI, wI / aS) : Math.max(hI, wI / aS)
            return Qt.size(dW, dH)
        }
        function irLocal(nx, ny) {
            var d = _disp()
            var dx = (nx - 0.5) * d.width
            var dy = (ny - 0.5) * d.height
            var th = irImage._irRot * Math.PI / 180
            var c = Math.cos(th), s = Math.sin(th)
            return Qt.point(width / 2 + (dx * c - dy * s),
                            height / 2 + (dx * s + dy * c))
        }
        function irUnmap(px, py) {
            var d = _disp()
            var rx = px - width / 2, ry = py - height / 2
            var th = irImage._irRot * Math.PI / 180
            var c = Math.cos(th), s = Math.sin(th)
            var dx = rx * c + ry * s          // inverse Rotation (Transponierte)
            var dy = -rx * s + ry * c
            return Qt.point(dx / d.width + 0.5, dy / d.height + 0.5)
        }

        Image {
            id: irImage
            anchors.centerIn: parent
            // Orientation-dependent rotation so the image stays upright in EVERY orientation
            // (including upside-down/PortraitInverted = 270 instead of 90 -> the desired 180).
            // Portrait orientations: transpose item dimensions (landscape sensor rotated 90/270).
            readonly property int _irRot: {
                switch (page.orientation) {
                case Orientation.PortraitInverted:  return 270
                case Orientation.LandscapeInverted: return 180
                case Orientation.Landscape:         return 0
                default:                            return 90   // portrait
                }
            }
            width:  irView._portrait ? parent.height : parent.width
            height: irView._portrait ? parent.width  : parent.height
            rotation: _irRot
            // Area half: fill (full width, some crop); fullscreen: show all (Fit).
            fillMode: page.irMode === 2 ? Image.PreserveAspectFit : Image.PreserveAspectCrop
            cache: false
            smooth: true
            source: ""
        }

        // ---- Notice when no IR camera is detected (no open / no frames) ----
        Rectangle {
            anchors.centerIn: parent
            visible: page.irMode > 0 && page._irProbed && !page._irFrameSeen
            radius: Theme.paddingMedium
            color: "#cc000000"
            width: Math.min(parent.width - 2 * Theme.paddingLarge, noCamCol.width + 2 * Theme.paddingLarge)
            height: noCamCol.height + 2 * Theme.paddingLarge
            Column {
                id: noCamCol
                anchors.centerIn: parent
                spacing: Theme.paddingSmall
                Label {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: "No IR camera detected"
                    color: "white"
                    font.pixelSize: Theme.fontSizeMedium
                    font.bold: true
                }
                Label {
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: Math.min(implicitWidth, irView.width - 4 * Theme.paddingLarge)
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.WordWrap
                    text: "Connect the InfiRay P2 Pro via USB, then tap the IR button again."
                    color: Theme.secondaryColor
                    font.pixelSize: Theme.fontSizeExtraSmall
                }
            }
        }

        // ---- Temperature overlay: hotspots (min/max), tap measurement points, colorbar ----
        // Upright (Canvas does NOT rotate with the image) -> text always readable; captured by
        // grab (irView.grabToImage) and automatically included in the photo.
        Canvas {
            id: thermalOverlay
            anchors.fill: parent
            visible: page.irMode > 0 && (page.irShowMarkers || page.irShowBar) && thermalCam.tempValid
            antialiasing: true
            renderStrategy: Canvas.Cooperative
            onWidthChanged: requestPaint()
            onHeightChanged: requestPaint()
            onVisibleChanged: requestPaint()

            function _cross(ctx, p, color, label) {
                var r = Math.round(Math.max(7, width * 0.018))
                ctx.strokeStyle = color
                ctx.lineWidth = 2
                ctx.beginPath()
                ctx.moveTo(p.x - r, p.y); ctx.lineTo(p.x + r, p.y)
                ctx.moveTo(p.x, p.y - r); ctx.lineTo(p.x, p.y + r)
                ctx.stroke()
                ctx.fillStyle = "#5aff5a"          // text green (readable on bright surfaces too)
                ctx.fillText(label, p.x + r + 3, p.y - r)
            }

            onPaint: {
                var ctx = getContext("2d")
                ctx.clearRect(0, 0, width, height)
                ctx.textBaseline = "top"
                ctx.font = "bold " + Math.round(Math.max(13, height * 0.045)) + "px sans-serif"

                if (!thermalCam.tempValid) return

                if (page.irShowBar) {
                    var pad = Math.round(height * 0.06)
                    var bw = Math.round(Math.max(8, width * 0.022))
                    var bx = width - bw - Math.round(width * 0.10)
                    var by = pad, bh = height - 2 * pad
                    var g = ctx.createLinearGradient(0, by, 0, by + bh)   // top hot -> bottom cold
                    g.addColorStop(0.00, "#fcffa4"); g.addColorStop(0.25, "#f57d15")
                    g.addColorStop(0.50, "#d44842"); g.addColorStop(0.75, "#65156e")
                    g.addColorStop(1.00, "#000004")
                    ctx.fillStyle = g
                    ctx.fillRect(bx, by, bw, bh)
                    ctx.strokeStyle = "#80ffffff"; ctx.lineWidth = 1
                    ctx.strokeRect(bx, by, bw, bh)
                    ctx.fillStyle = "#ffffff"
                    ctx.textAlign = "right"
                    var lx = bx - 4
                    ctx.fillText(thermalCam.tMax.toFixed(0) + "C", lx, by - 2)
                    ctx.fillText(((thermalCam.tMax + thermalCam.tMin) / 2).toFixed(0), lx, by + bh / 2)
                    ctx.fillText(thermalCam.tMin.toFixed(0), lx, by + bh - Math.round(height * 0.045))
                    ctx.textAlign = "left"
                }

                if (page.irShowMarkers) {
                    _cross(ctx, irView.irLocal(thermalCam.tMaxX, thermalCam.tMaxY),
                           "#ff3b30", thermalCam.tMax.toFixed(1) + "C")
                    _cross(ctx, irView.irLocal(thermalCam.tMinX, thermalCam.tMinY),
                           "#5ac8fa", thermalCam.tMin.toFixed(1) + "C")
                    for (var i = 0; i < irPoints.count; ++i) {
                        var pt = irPoints.get(i)
                        var t = thermalCam.tempAt(pt.nx, pt.ny)
                        _cross(ctx, irView.irLocal(pt.nx, pt.ny),
                               "#5aff5a", (i + 1) + ": " + t.toFixed(1) + "C")
                    }
                }
            }
        }

        // A tap adds a measurement point; tapping near an existing point removes it (only when
        // markers are active). Sits below the controls (controlsContainer z:1) -> shutter stays free.
        MouseArea {
            anchors.fill: parent
            enabled: page.irMode > 0 && page.irShowMarkers
            propagateComposedEvents: true
            // A tap near an existing point removes it; otherwise adds a new point (max 6).
            onClicked: {
                var n = irView.irUnmap(mouse.x, mouse.y)
                if (n.x < 0 || n.x > 1 || n.y < 0 || n.y > 1) { mouse.accepted = false; return }
                var best = -1, bd = 1e9
                for (var i = 0; i < irPoints.count; ++i) {
                    var p = irPoints.get(i)
                    var d = (p.nx - n.x) * (p.nx - n.x) + (p.ny - n.y) * (p.ny - n.y)
                    if (d < bd) { bd = d; best = i }
                }
                if (best >= 0 && bd < 0.0025) irPoints.remove(best)   // ~5% radius -> remove
                else if (irPoints.count < 6) irPoints.append({ nx: n.x, ny: n.y })
                thermalOverlay.requestPaint()
            }
        }
    }
    Connections {
        target: thermalCam
        onFrameReady: {
            if (page.irMode > 0) irImage.source = "image://thermal/" + frame
            page._irFrameSeen = true     // frame arrived -> notice disappears
            page._irProbed = false
        }
        onTempUpdated: if (thermalOverlay.visible) thermalOverlay.requestPaint()
        // If the capturer goes inactive (e.g. open /dev/video2 failed), report immediately.
        onActiveChanged: {
            if (page.irMode > 0 && !thermalCam.active && !page._irFrameSeen)
                page._irProbed = true
        }
    }

    RoundButton {
        id: btnInstruments
        size: Theme.itemSizeSmall
        anchors {
            bottom: parent.bottom
            bottomMargin: Theme.paddingMedium
            left: parent.left
            leftMargin: Theme.paddingMedium
        }
        rotation: page.controlsRotation
        icon.source: "image://theme/icon-m-developer-mode"
        icon.opacity: page.showInstruments ? 1.0 : 0.4
        onClicked: page.showInstruments = !page.showInstruments
    }

    // P2 Pro thermal camera: one tap = area, again = fullscreen, again = off.
    RoundButton {
        id: btnIr
        size: Theme.itemSizeSmall
        anchors {
            bottom: btnInstruments.top
            bottomMargin: Theme.paddingMedium
            left: parent.left
            leftMargin: Theme.paddingMedium
        }
        rotation: page.controlsRotation
        icon.source: "image://theme/icon-m-levels"
        icon.opacity: page.irMode > 0 ? 1.0 : 0.4
        onClicked: {
            var was = page.irMode
            page.irMode = (page.irMode + 1) % 3
            if (page.irMode > 0) {
                if (was === 0) {                 // turning IR on -> start camera + probe
                    page._irFrameSeen = false
                    page._irProbed = false
                    thermalCam.start()
                    irProbeTimer.restart()
                }
            } else {                             // IR off
                thermalCam.stop()
                irProbeTimer.stop()
                page._irProbed = false
            }
        }
    }

    // ---- P2 Pro temperature: hotspots/measurement points on/off (only when IR is active) ----
    RoundButton {
        id: btnIrMarkers
        size: Theme.itemSizeSmall
        visible: page.irMode > 0
        z: 2
        anchors {
            bottom: parent.bottom
            bottomMargin: Theme.paddingMedium
            right: parent.right
            rightMargin: Theme.paddingMedium
        }
        rotation: page.controlsRotation
        icon.source: "image://theme/icon-m-location"
        icon.opacity: page.irShowMarkers ? 1.0 : 0.4
        onClicked: {
            page.irShowMarkers = !page.irShowMarkers
            thermalOverlay.requestPaint()
        }
    }

    // ---- P2 Pro temperature: colorbar on/off (only when IR is active) ----
    RoundButton {
        id: btnIrBar
        size: Theme.itemSizeSmall
        visible: page.irMode > 0
        z: 2
        anchors {
            bottom: btnIrMarkers.top
            bottomMargin: Theme.paddingMedium
            right: parent.right
            rightMargin: Theme.paddingMedium
        }
        rotation: page.controlsRotation
        icon.source: "image://theme/icon-m-levels"
        icon.opacity: page.irShowBar ? 1.0 : 0.4
        onClicked: {
            page.irShowBar = !page.irShowBar
            thermalOverlay.requestPaint()
        }
    }

    // ---- Component ID: selection frame -- white corner brackets only ----
    // Portrait: to the RIGHT of the instrument strip (does not overlap it).
    // Landscape: BELOW the instruments. Size adapted to the available area.
    Item {
        id: roiFrame
        visible: page.componentMode

        // Edge of the instruments (right in portrait, bottom in landscape) -- otherwise image boundary.
        readonly property real _stripRight: (instrumentBar.visible && page._isPortrait)
            ? (instrumentBar.x + instrumentBar.width + Theme.paddingMedium)
            : page._imgRect.x
        readonly property real _barBottom: (instrumentBar.visible && !page._isPortrait)
            ? (instrumentBar.y + instrumentBar.height + Theme.paddingMedium)
            : page._imgRect.y
        readonly property real _imgRight: page._imgRect.x + page._imgRect.width
        readonly property real _imgBottom: page._imgRect.y + page._imgRect.height
        readonly property real _availW: page._isPortrait ? (_imgRight - _stripRight) : page._imgRect.width
        readonly property real _availH: page._isPortrait ? page._imgRect.height : (_imgBottom - _barBottom)

        width: Math.round(Math.max(Theme.itemSizeMedium, Math.min(_availW, _availH) * 0.78))
        height: width
        x: Math.round((page._isPortrait ? (_stripRight + _imgRight) / 2
                                        : (page._imgRect.x + _imgRight) / 2) - width / 2)
        y: Math.round((page._isPortrait ? (page._imgRect.y + _imgBottom) / 2
                                        : (_barBottom + _imgBottom) / 2) - height / 2)

        readonly property int cornerLen: Math.round(width * 0.18)  // length of corner arms
        readonly property int stroke: 5                            // stroke width (thicker)
        readonly property color cornerColor: "white"

        // 4 corners x 2 arms (horizontal + vertical) = 8 rectangles.
        // index: 0=top-left, 1=top-right, 2=bottom-right, 3=bottom-left.
        Repeater {
            model: 4
            Item {
                anchors.fill: parent
                readonly property bool atRight: (index === 1 || index === 2)
                readonly property bool atBottom: (index === 2 || index === 3)
                Rectangle {  // horizontal arm
                    width: roiFrame.cornerLen; height: roiFrame.stroke
                    color: roiFrame.cornerColor
                    x: parent.atRight ? parent.width - width : 0
                    y: parent.atBottom ? parent.height - height : 0
                }
                Rectangle {  // vertical arm
                    width: roiFrame.stroke; height: roiFrame.cornerLen
                    color: roiFrame.cornerColor
                    x: parent.atRight ? parent.width - width : 0
                    y: parent.atBottom ? parent.height - height : 0
                }
            }
        }
        Label {
            anchors { bottom: parent.top; horizontalCenter: parent.horizontalCenter; bottomMargin: Theme.paddingSmall }
            text: "Component in frame -> shutter"
            color: "white"
            font.pixelSize: Theme.fontSizeExtraSmall
        }
    }

    // ---- Component ID: toggle button ----
    RoundButton {
        id: btnComponent
        size: Theme.itemSizeSmall
        anchors {
            bottom: btnIr.top            // above the IR button (stack: instruments->IR->magnifier->save)
            bottomMargin: Theme.paddingMedium
            left: parent.left
            leftMargin: Theme.paddingMedium
        }
        rotation: page.controlsRotation
        icon.source: "image://theme/icon-m-search"
        icon.opacity: page.componentMode ? 1.0 : 0.4
        onClicked: page.componentMode = !page.componentMode
    }

    // ---- "Save photo with text" (only when a result is available) ----
    RoundButton {
        id: btnSaveResult
        size: Theme.itemSizeSmall
        visible: page.componentMode
        anchors {
            bottom: btnComponent.top
            bottomMargin: Theme.paddingMedium
            left: parent.left
            leftMargin: Theme.paddingMedium
        }
        rotation: page.controlsRotation
        icon.source: "image://theme/icon-m-image"
        icon.opacity: componentCard.result !== null ? 1.0 : 0.4
        onClicked: page.saveResultImage()
    }

    // ---- Component ID: result card ----
    ComponentCard {
        id: componentCard
        // Always at the bottom, full image width, starting from the left; display-only (does
        // not capture taps -> shutter stays free), height = content height.
        anchors {
            left: parent.left
            right: parent.right
            bottom: parent.bottom
        }
        // NO own rotation: the Silica page already orients the content upright.
    }

    // ---- Component ID: silhouette live over the viewfinder (what was marked) ----
    Canvas {
        id: silhouetteCanvas
        anchors.fill: parent
        z: 1
        visible: page.componentMode && componentCard.result
                 && componentCard.result.silhouette
                 && componentCard.result.silhouette.length >= 3
        onVisibleChanged: requestPaint()
        // Draw corner-bracket path around a box (x,y,w,h) onto a 2D context.
        function _corners(ctx, x, y, w, h, len) {
            ctx.beginPath()
            ctx.moveTo(x, y + len);         ctx.lineTo(x, y);         ctx.lineTo(x + len, y)
            ctx.moveTo(x + w - len, y);     ctx.lineTo(x + w, y);     ctx.lineTo(x + w, y + len)
            ctx.moveTo(x + w, y + h - len); ctx.lineTo(x + w, y + h); ctx.lineTo(x + w - len, y + h)
            ctx.moveTo(x + len, y + h);     ctx.lineTo(x, y + h);     ctx.lineTo(x, y + h - len)
        }
        onPaint: {
            var ctx = getContext("2d")
            ctx.clearRect(0, 0, width, height)
            if (!visible)
                return
            var pts = componentCard.result.silhouette
            // Polygon is normalized to the ROI crop -> map onto the frame (roiFrame),
            // then compute bounding box and draw as white corner brackets (like the outer frame).
            var minX = 1e9, minY = 1e9, maxX = -1e9, maxY = -1e9
            for (var i = 0; i < pts.length; i++) {
                var X = roiFrame.x + pts[i][0] * roiFrame.width
                var Y = roiFrame.y + pts[i][1] * roiFrame.height
                if (X < minX) minX = X; if (X > maxX) maxX = X
                if (Y < minY) minY = Y; if (Y > maxY) maxY = Y
            }
            var w = maxX - minX, h = maxY - minY
            if (w <= 0 || h <= 0) return
            var len = Math.max(10, Math.min(w, h) * 0.22)
            ctx.lineJoin = "miter"; ctx.lineCap = "butt"
            ctx.strokeStyle = "white"; ctx.lineWidth = 5               // white corners only
            _corners(ctx, minX, minY, w, h, len); ctx.stroke()
        }
        Connections {
            target: componentCard
            onResultChanged: silhouetteCanvas.requestPaint()
        }
    }

    Connections {
        target: componentId
        onResultReady: {
            componentCard.busy = false
            try {
                componentCard.result = JSON.parse(json)
                componentCard.error = ""
            } catch (e) {
                componentCard.error = "Response could not be parsed: " + e
                componentCard.result = null
            }
        }
        onFailed: {
            componentCard.busy = false
            componentCard.error = error
            componentCard.result = null
        }
    }


    MouseArea {
        id: mouseFocusArea
        anchors.fill: parent
        z: -1 //Send to back
        onClicked: {

            if (settingsOverlay.panelOpen) {
                settingsOverlay.hideAllPanels()
                return
            }

            // If in auto or macro focus mode, focus on the specified point
            if (camera.focus.focusMode === Camera.FocusAuto
                    || camera.focus.focusMode === Camera.FocusMacro
                    || camera.focus.focusMode === Camera.FocusContinuous) {
                var focusPoint
                switch ((360 - viewfinderOrientation) % 360) {
                case 90:
                    focusPoint = Qt.point(mouse.y, width - mouse.x)
                    break
                case 180:
                    focusPoint = Qt.point(width - mouse.x, height - mouse.y)
                    break
                case 270:
                    focusPoint = Qt.point(height - mouse.y, mouse.x)
                    break
                default:
                    focusPoint = Qt.point(mouse.x, mouse.y)
                    break
                }

                // Normalize the focus point.
                focusPoint.x = focusPoint.x / Math.max(page.width, page.height)
                focusPoint.y = focusPoint.y / Math.min(page.width, page.height)

                camera.focus.focusPointMode = Camera.FocusPointCustom
                camera.focus.setCustomFocusPoint(focusPoint)
                camera.unlock()
            }
            camera.searchAndLock()
            if (!_manualModeSelected) focusPointTimer.restart()
        }
    }

    Rectangle {
        id: focusCircle
        height: (camera.lockStatus === Camera.Locked) ? Theme.itemSizeSmall : Theme.itemSizeMedium
        width: height
        radius: width / 2
        border.width: 4
        border.color: focusColor()
        color: "transparent"
        visible: camera.focus.focusPointMode === Camera.FocusPointCustom

        x: {
            var ret = 0
            switch ((360 - viewfinderOrientation) % 360) {
            case 90:
                ret = page.width - camera.focus.customFocusPoint.y * page.width
                break
            case 180:
                ret = page.width - camera.focus.customFocusPoint.x * page.width
                break
            case 270:
                ret = camera.focus.customFocusPoint.y * page.width
                break
            default:
                ret = camera.focus.customFocusPoint.x * page.width
                break
            }
        }

        y: {
            var ret = 0
            switch ((360 - viewfinderOrientation) % 360) {
            case 90:
                ret = camera.focus.customFocusPoint.x * page.height
                break
            case 180:
                ret = page.height - camera.focus.customFocusPoint.y * page.height
                break
            case 270:
                ret = page.height - camera.focus.customFocusPoint.x * page.height
                break
            default:
                ret = camera.focus.customFocusPoint.y * page.height
                break
            }
        }

        transform: Translate {
            x: -focusCircle.width / 2
            y: -focusCircle.height / 2
        }
    }

    Component.onCompleted: {
        settings.global.cameraCount = QtMultimedia.availableCameras.length
        settings.calculateEnabledCameras()
        camera.deviceId = settings.global.cameraId
        _completed = true
    }

    Connections {
        target: window

        onActiveFocusChanged: {
            if (!window.activeFocus) {
                camera.stop()
            } else {
                if (pageStack.depth === 1)
                    camera.start()
            }
        }
    }

    Connections {
        target: pageStack

        onDepthChanged: {
            if (pageStack.depth === 1) {
                console.log("Calling camera.start() due to pageStack change")
                camera.start()
            }
        }
    }

    ListModel {
        id: galleryModel
    }

    ListModel {
        id: viewfinderResolutionModel
    }

    Timer {
        id: tmrDelayedStart
        repeat: false
        running: false
        interval: 200
        onTriggered: {
            console.log("camera delayed start", settings.global.cameraId)
            _loadParameters = true
            camera.deviceId = settings.global.cameraId
            camera.start()
            _cameraReload = true
        }
    }

    Timer {
        id: reloadTimer
        interval: 100
        running: page._cameraReload
                 && camera.cameraStatus === Camera.UnloadedStatus
        onTriggered: {
            page._cameraReload = false
        }
    }

    Timer {
        id: focusPointTimer
        interval: 7000
        onTriggered: {
            //Set the focus point back to centre
            camera.focus.setFocusPointMode(Camera.FocusPointAuto)
            // and unlock camera so AF is working again
            camera.unlock()
            if (camera.focus.focusMode === Camera.FocusAuto) camera.searchAndLock()
        }
    }

    function volUp() {
        if (settings.global.swapZoomControl) {
            zoomOut()
        } else {
            zoomIn()
        }
    }

    function volDown() {
        if (settings.global.swapZoomControl) {
            zoomIn()
        } else {
            zoomOut()
        }
    }

    Keys.onPressed: {
        console.log(event);
        if (event.isAutoRepeat) {
            return
        }
        if (event.key === Qt.Key_CameraFocus
                && settings.mode.focus === Camera.FocusManual) {
            camera.searchAndLock()
        } else if (event.key === Qt.Key_Camera) {
            doShutter()
        }
    }

    function cameraStatusStr() {
        switch(camera.cameraStatus){
        case Camera.ActiveStatus:
            return "Active"
        case Camera.StartingStatus:
            return "Starting"
        case Camera.StoppingStatus:
            return "Stopping"
        case Camera.StandbyStatus:
            return "Standby"
        case Camera.LoadedStatus:
            return "Loaded"
        case Camera.LoadingStatus:
            return "Loading"
        case Camera.UnloadingStatus:
            return "Unloading"
        case Camera.UnloadedStatus:
            return "Unloaded"
        case Camera.UnavailableStatus:
            return "Unavailable"
        default:
            return "unknown (" + camera.cameraStatus + ")"
        }
    }

    function focusStr(focus) {
        // TODO: It's possible to combine multiple Camera::FocusMode values, for example FocusMacro + FocusContinuous.
        switch (focus) {
        case CameraFocus.FocusManual:
            return "Manual"
        case CameraFocus.FocusHyperfocal:
            return "Hyperfocal"
        case CameraFocus.FocusInfinity:
            return "Infinity"
        case CameraFocus.FocusAuto:
            return "Auto"
        case CameraFocus.FocusContinuous:
            return "Continuous"
        case CameraFocus.FocusMacro:
            return "Macro"
        default:
            return "unknown (" + focus + ")"
        }
    }

    function applySettings() {
        console.log("Applying settings in", settings.global.captureMode,
                    "mode for", camera.deviceId, "camera with status",
                    cameraStatusStr())

        camera.imageProcessing.setColorFilter(settings.mode.effect)
        camera.exposure.setExposureMode(settings.mode.exposure)
        camera.flash.setFlashMode(settings.mode.flash)
        camera.imageProcessing.setWhiteBalanceMode(settings.mode.whiteBalance)
        setFocusMode(settings.mode.focus)

        if (settings.mode.iso === 0) {
            camera.exposure.setAutoIsoSensitivity()
        } else {
            camera.exposure.setManualIsoSensitivity(settings.mode.iso)
        }

        camera.imageCapture.setResolution(settings.resolution("image"))
        camera.videoRecorder.resolution = settings.resolution("video")
    }

    function setFocusMode(focus) {
        var requestedFocus = focus === Camera.FocusManual ? Camera.FocusAuto : focus
        if (!camera.focus.isFocusModeSupported(requestedFocus)) {
            console.log("focus mode " + focusStr(requestedFocus) +
                        " is not supported, keeping " + focusStr(camera.focus.focusMode))
            return
        }
        console.log("setting focus mode " +
                    focusStr(camera.focus.focusMode) + " -> " + focusStr(focus))

        if (focus === Camera.FocusManual) {
            _manualModeSelected = true
        } else {
            _manualModeSelected = false
        }
        if (camera.focus.focusMode !== requestedFocus) {
            camera.stop()
            camera.focus.setFocusMode(requestedFocus)
            camera.start()
        }
        camera.unlock() // Do not forget to unlock camera when changing focus mode
        settings.mode.focus = focus

        //Set the focus point back to centre
        camera.focus.setFocusPointMode(Camera.FocusPointAuto)

        // Do not lock focus when continuous focus is declared // TODO: We need to allow combination of continous with Auto + Macro
        if (focus !== Camera.FocusContinuous && focus !== Camera.FocusManual) {
            camera.searchAndLock()
        }
    }

    function getNearestViewFinderResolution() {

        /// Tries to find the most correct ViewFinder resolution
        /// for the selected camera settings
        ///
        /// In order of preference:
        ///  * viewFinderResolution for the nearest aspect ratio as set in jolla-camera's dconf settings
        ///  * viewFinderResolution as set in jolla-camera's dconf settings
        ///  * Best match from camera.supportedViewfinderResolutions() that fit to screen and have the same aspect ratio
        ///  * device resolution

        var currentRatioSize = modelResolution.sizeToRatio(
                    settings.resolution(settings.global.captureMode))
        var currentRatio = currentRatioSize.height
                > 0 ? currentRatioSize.width / currentRatioSize.height : 0
        if (currentRatio > 0) {
            if (currentRatio <= 4.0 / 3
                    && settings.jollaCamera.viewfinderResolution_4_3) {
                return settings.strToSize(
                            settings.jollaCamera.viewfinderResolution_4_3)
            } else if (settings.jollaCamera.viewfinderResolution_16_9) {
                return settings.strToSize(
                            settings.jollaCamera.viewfinderResolution_16_9)
            }
        }

        if (settings.jollaCamera.viewfinderResolution) {
            return settings.strToSize(settings.jollaCamera.viewfinderResolution)
        }

        var supportedResolutions = camera.supportedViewfinderResolutions()
        if (supportedResolutions.length > 0) {
            var bestMatch = 0
            for (var i = 0; i < supportedResolutions.length; i++) {
                var w = supportedResolutions[i].width;
                var h = supportedResolutions[i].height;
                if (w > Screen.height || h > Screen.width) {
                    continue
                }
                if (currentRatio > 0) {
                    var ratio = w / h
                    var bestMatchRatio = supportedResolutions[bestMatch].width / supportedResolutions[bestMatch].height
                    if (Math.abs(ratio - currentRatio) < Math.abs(bestMatchRatio - currentRatio)) {
                        bestMatch = i; // better match to aspect ratio
                    } else if (Math.abs(ratio - currentRatio) == Math.abs(bestMatchRatio - currentRatio) &&
                               w > supportedResolutions[bestMatch].width && h > supportedResolutions[bestMatch].height) {
                        bestMatch = i; // same aspect ratio, better resolution
                    }
                } else {
                    if (w > supportedResolutions[bestMatch].width && h > supportedResolutions[bestMatch].height) {
                        bestMatch = i; // just select best resolution
                    }
                }
            }
            console.log("Choosing view finder resolution: " + supportedResolutions[bestMatch].width + "x" + supportedResolutions[bestMatch].height)
            return Qt.size(supportedResolutions[bestMatch].width, supportedResolutions[bestMatch].height)
        }

        return Qt.size(Screen.height, Screen.width)
    }

    // ---- Overlay compositing on shutter release ----
    function overlayTmpFile() {
        return fsOperations.writableLocation(
                    "image", settings.global.storagePath) + "/.ovl_tmp.png"
    }
    function irTmpFile() {
        return fsOperations.writableLocation(
                    "image", settings.global.storagePath) + "/.ir_tmp.png"
    }

    // Call on shutter release: renders the overlay (upscaled for sharp text)
    // into a temporary PNG. The actual compositing happens in _tryCompose()
    // once both the photo and the overlay are ready.
    function _beginCapture() {
        _pendingPhotoPath = ""
        _pendingOverlayPath = ""
        _pendingIrPath = ""
        // WYSIWYG: burns in whatever is visible in the viewfinder (instruments + IR thermal) --
        // even without a live connection. Both grabs run in parallel with the photo; _tryCompose
        // composites as soon as the photo and both grabs are ready.
        var wantInstr = burnOverlayIntoPhoto && showInstruments
        var wantIr = page.irMode > 0
        _overlayInFlight = wantInstr
        _irInFlight = wantIr
        var res = camera.imageCapture.resolution
        var base = Math.min((res && res.width > 0) ? res.width : 2000, 3000)
        if (wantInstr) {
            // Portrait: narrow left strip; landscape: full width at the top.
            _pendingOverlayFraction = instrumentBar._portrait ? page.instrumentStripFraction : 1.0
            var targetW = Math.max(1, Math.round(base * _pendingOverlayFraction))
            var targetH = Math.max(1, Math.round(
                                       targetW * instrumentBar.height / instrumentBar.width))
            instrumentBar.grabToImage(function (result) {
                var p = overlayTmpFile()
                _pendingOverlayPath = (result && result.saveToFile(p)) ? p : ""
                if (_pendingOverlayPath.length === 0)
                    console.warn("overlay grab/save failed")
                _overlayInFlight = false
                _tryCompose()
            }, Qt.size(targetW, targetH))
        }
        if (wantIr) {
            // IR position normalized against the image area (page._imgRect) -> photo mapping.
            // nx<0 / nw>1 possible (IR wider than image) -> C++ clips to photo.
            _irRect = Qt.rect((irView.x - page._imgRect.x) / page._imgRect.width,
                              (irView.y - page._imgRect.y) / page._imgRect.height,
                              irView.width / page._imgRect.width,
                              irView.height / page._imgRect.height)
            irView.grabToImage(function (result) {
                var p = irTmpFile()
                _pendingIrPath = (result && result.saveToFile(p)) ? p : ""
                if (_pendingIrPath.length === 0)
                    console.warn("IR grab/save failed")
                _irInFlight = false
                _tryCompose()
            })
        }
    }

    function _tryCompose() {
        if (_overlayInFlight || _irInFlight)
            return // grab(s) still running
        if (_pendingPhotoPath.length === 0)
            return // photo not yet saved
        // Layer order as in viewfinder (z): IR FIRST (bottom), instruments ON TOP -- otherwise
        // the (fullscreen-sized) IR would cover the instruments in the photo.
        var result = ""
        if (_pendingIrPath.length > 0) {
            result = imageOverlay.burnImageRect(_pendingPhotoPath, _pendingIrPath,
                                                _irRect.x, _irRect.y, _irRect.width, _irRect.height,
                                                95, "")   // "" -> creates <photo>_ovl.jpg
        }
        if (_pendingOverlayPath.length > 0) {
            var base = (result.length > 0) ? result : _pendingPhotoPath
            var dst = (result.length > 0) ? result : ""   // burn on top of the IR result
            var r = imageOverlay.burnOverlay(base, _pendingOverlayPath, 0, 95,
                                             _pendingOverlayFraction, dst)
            if (r.length > 0)
                result = r
        }
        if (result.length > 0) {
            // Keep the composited image, delete the native original (only ONE image in the gallery).
            galleryModel.append({ "filePath": result, "isVideo": false })
            fsOperations.deleteFile(_pendingPhotoPath)
        } else {
            // No overlay produced -> keep original, otherwise there would be no photo at all.
            galleryModel.append({ "filePath": _pendingPhotoPath, "isVideo": false })
        }
        _pendingPhotoPath = ""
        _pendingOverlayPath = ""
        _pendingIrPath = ""
    }

    // ---- Component ID: shutter -> photo -> ROI crop sent to the service ----
    function _identifyCapture() {
        if (!componentMode)   // hard gate: no identify / no API usage when off
            return
        _identifyPending = true
        componentCard.busy = true
        componentCard.result = null
        componentCard.error = ""
        camera.imageCapture.captureToLocation(
                    fsOperations.writableLocation("image", settings.global.storagePath)
                    + "/.compid_tmp.jpg")
        animFlash.start()
    }

    function _roiNorm() {
        // Normalize ROI (roiFrame) relative to the displayed image -- PAGE system (page._imgRect),
        // NOT videoOutput.contentRect (window system, shifted/rotated in landscape).
        var def = [0.25, 0.25, 0.5, 0.5]
        var cr = page._imgRect
        if (!cr || cr.width <= 0 || cr.height <= 0)
            return def
        var nx = (roiFrame.x - cr.x) / cr.width
        var ny = (roiFrame.y - cr.y) / cr.height
        var nw = roiFrame.width / cr.width
        var nh = roiFrame.height / cr.height
        nx = Math.max(0, Math.min(1, nx))
        ny = Math.max(0, Math.min(1, ny))
        nw = Math.max(0.02, Math.min(1 - nx, nw))
        nh = Math.max(0.02, Math.min(1 - ny, nh))
        return [nx, ny, nw, nh]
    }

    function _dmmJson() {
        if (showInstruments && instrumentBar.connected
                && instrumentBar.dmm && instrumentBar.dmm.ok)
            return JSON.stringify(instrumentBar.dmm)
        return "null"
    }

    function _runIdentify(path) {
        if (!componentMode) {     // hard gate: no request if turned off in the meantime
            componentCard.busy = false
            return
        }
        var r = _roiNorm()
        componentId.identify(path, r[0], r[1], r[2], r[3], _dmmJson())
    }

    // "Save photo with text" (on demand): composite onto the REAL photo (1) the instrument
    // overlay (top, orientation-dependent as in normal burn) and (2) the result text
    // (bottom). grabToImage does not capture the camera image -> compositing in C++.
    function saveResultImage() {
        if (!componentCard.result || _idPhotoPath.length === 0) {
            console.warn("save: no result / no photo to save")
            return
        }
        var dir = fsOperations.writableLocation("image", settings.global.storagePath)
        // Step 0: draw tight silhouette around the component into the real photo (if available).
        var base0 = _silhouetteBase(dir)
        // Step 1: instrument overlay onto the photo (if visible), otherwise proceed directly.
        if (showInstruments && instrumentBar.visible && instrumentBar.width > 0) {
            var fraction = instrumentBar._portrait ? page.instrumentStripFraction : 1.0
            var res = camera.imageCapture.resolution
            var base = Math.min((res && res.width > 0) ? res.width : 2000, 3000)
            var tW = Math.max(1, Math.round(base * fraction))
            var tH = Math.max(1, Math.round(tW * instrumentBar.height / instrumentBar.width))
            var instrPng = dir + "/.compid_instr.png"
            instrumentBar.grabToImage(function (ri) {
                var basePhoto = base0
                if (ri && ri.saveToFile(instrPng)) {
                    var step1 = imageOverlay.burnOverlay(base0, instrPng, 0, 95, fraction,
                                                         dir + "/.compid_step1.jpg")
                    if (step1.length > 0)
                        basePhoto = step1
                }
                _composeCardOnto(basePhoto, dir)
            }, Qt.size(tW, tH))
        } else {
            _composeCardOnto(base0, dir)
        }
    }

    // Draws (synchronously in C++) the silhouette into the photo; returns the new base photo
    // (or the original if no / too few points are available).
    function _silhouetteBase(dir) {
        var sil = componentCard.result ? componentCard.result.silhouette : null
        if (sil && sil.length >= 3) {
            var r = _roiNorm()
            var out = imageOverlay.drawSilhouette(_idPhotoPath, sil, r[0], r[1], r[2], r[3],
                                                  dir + "/.compid_sil.jpg", 95)
            if (out.length > 0)
                return out
        }
        return _idPhotoPath
    }

    function _composeCardOnto(basePhoto, dir) {
        var cardPng = dir + "/.compid_card.png"
        // Card full width, bottom left.
        componentCard.grabToImage(function (rc) {
            if (!rc || !rc.saveToFile(cardPng)) {
                console.warn("save: card grab failed")
                return
            }
            var out = dir + "/IMG_" + Qt.formatDateTime(new Date(), "yyyyMMdd_hhmmss") + "_id.jpg"
            var saved = imageOverlay.burnOverlay(basePhoto, cardPng, 1, 95, 1.0, out)
            if (saved.length > 0)
                galleryModel.append({ "filePath": saved, "isVideo": false })
            else
                console.warn("save: compositing failed")
        })
    }

    function doShutter() {
        camera.metaData.date = new Date()
        // Component ID mode: shutter identifies the frame content instead of taking a photo.
        if (componentMode && camera.captureMode === Camera.CaptureStillImage) {
            _identifyCapture()
            return
        }
        if (camera.captureMode === Camera.CaptureStillImage) {
            if ((camera.focus.focusMode === Camera.FocusAuto
                 && !_manualModeSelected)
                    || camera.focus.focusMode === Camera.FocusMacro
                    || camera.focus.focusMode === Camera.FocusContinuous) {
                _focusAndSnap = true
                camera.searchAndLock()
            } else {
                if (camera.lockStatus != Camera.Searching || camera.focus.focusMode === Camera.FocusManual) {
                    _beginCapture()
                    camera.imageCapture.captureToLocation(
                                fsOperations.writableLocation(
                                    "image",
                                    settings.global.storagePath) + "/IMG_" + Qt.formatDateTime(
                                    new Date(), "yyyyMMdd_hhmmss") + ".jpg")
                    animFlash.start()
                }
            }
        } else {
            if (camera.videoRecorder.recorderStatus === CameraRecorder.RecordingStatus) {
                camera.videoRecorder.stop()
            } else {
                camera.videoRecorder.outputLocation = fsOperations.writableLocation(
                            "video",
                            settings.global.storagePath) + "/VID_" + Qt.formatDateTime(
                            new Date(), "yyyyMMdd_hhmmss") + ".mp4"
                if ((camera.focus.focusMode === Camera.FocusAuto
                     && !_manualModeSelected)
                        || camera.focus.focusMode === Camera.FocusMacro
                        || camera.focus.focusMode === Camera.FocusContinuous) {
                    camera.unlock()
                }
                camera.videoRecorder.record()
            }
        }
    }

    function zoomIn() {
        if (camera.digitalZoom < camera.maximumDigitalZoom) {
            camera.digitalZoom += zoomStepButton;
        }
    }

    function zoomOut() {
        if (camera.digitalZoom > 1) {
            camera.digitalZoom -= zoomStepButton;
        }
    }

    function focusColor() {
        if (camera.lockStatus === Camera.Unlocked) {
            return "white"
        } else if (camera.lockStatus === Camera.Searching) {
            return "#e3e3e3" //light grey
        } else {
            return "lightgreen"
        }
    }

    function shutterIcon() {
        if (camera.captureMode === Camera.CaptureStillImage) {
            return "image://theme/icon-camera-shutter"
        } else {
            if (camera.videoRecorder.recorderStatus === CameraRecorder.RecordingStatus) {
                return "image://theme/icon-camera-video-shutter-off"
            } else {
                return "image://theme/icon-camera-video-shutter-on"
            }
        }
    }

    function msToTime(millis) {
        return new Date(millis).toISOString().substr(11, 8)
    }

    function switchCamera(camId) {
        console.log("Switching camera to", camId)
        console.log("Setting temp resolution")
        camera.imageCapture.setResolution(settings.strToSize("320x240"))
        camera.stop()
        _loadParameters = false
        if (camId !== "") settings.global.cameraId = camId;
        else if (parseInt(settings.global.cameraId) + 1 == settings.global.cameraCount) settings.global.cameraId = "0";
        else settings.global.cameraId = parseInt(settings.global.cameraId) + 1;
        tmrDelayedStart.start()
    }

    function checkIfCamExists(camId) {
        console.log("Check if cam exists: ", camId, settings.enabledCameras.length)
        var found = false;
        for(var i = 0; i < settings.enabledCameras.length; i++) {
            if(settings.enabledCameras[i] === camId)
                found = true;
        }
        return found
    }

    function switchToNextCamera() {
        console.log("Switching no next camera from", settings.global.cameraId, settings.enabledCameras)
        if (settings.enabledCameras.length == 0) {
            switchCamera(0)
        }else if (settings.enabledCameras.length == 1) {
            switchCamera(settings.enabledCameras[0])
        } else {
            var idx = settings.enabledCameras.indexOf(settings.global.cameraId);
            if (idx >= 0) {
                idx++;
                if (idx >= settings.enabledCameras.length) {
                    idx = 0
                }
                switchCamera(settings.enabledCameras[idx])
            } else {
                switchCamera(settings.enabledCameras[0])
            }
        }
    }
}
