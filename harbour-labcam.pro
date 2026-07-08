# NOTICE:
#
# Application name defined in TARGET has a corresponding QML filename.
# If name defined in TARGET is changed, the following needs to be done
# to match new name:
#   - corresponding QML filename must be changed
#   - desktop icon filename must be changed
#   - desktop filename must be changed
#   - icon definition filename in desktop file must be changed
#   - translation filenames have to be changed

# The name of your application
TARGET = harbour-labcam

CONFIG += sailfishapp

QT += multimedia network

SOURCES += src/harbour-labcam.cpp \
    src/componentid.cpp \
    src/deviceinfo.cpp \
    src/effectsmodel.cpp \
    src/exifmodel.cpp \
    src/exposuremodel.cpp \
    src/isomodel.cpp \
    src/metadatamodel.cpp \
    src/resolutionmodel.cpp \
    src/wbmodel.cpp \
    src/focusmodel.cpp \
    src/flashmodel.cpp \
    src/fsoperations.cpp \
    src/resourcehandler.cpp \
    src/storagemodel.cpp \
    src/imageoverlay.cpp \
    src/thermalcamera.cpp

DISTFILES += \
    README.md \
    qml/pics/icon-m-tele-lense-active.png \
    qml/pics/icon-m-tele-lense.svg \
    qml/pics/icon-m-uwide-lense-active.png \
    qml/pics/icon-m-uwide-lense.svg \
    qml/pics/icon-m-wide-lense-active.png \
    qml/pics/icon-m-wide-lense.svg \
    qml/components/AboutMedia.qml \
    qml/pages/AboutImage.qml \
    qml/pages/AboutVideo.qml \
    rpm/harbour-labcam.changes.run.in \
    rpm/harbour-labcam.spec \
    translations/*.ts \
    harbour-labcam.desktop \
    qml/harbour-labcam.qml \
    qml/components/DockedListView.qml \
    qml/components/IconSwitch.qml \
    qml/components/RoundButton.qml \
    qml/cover/CoverPage.qml \
    qml/pages/CameraUI.qml \
    qml/pages/GalleryUI.qml \
    qml/pages/Settings.qml \
    qml/pages/SettingsOverlay.qml \
    qml/overlay/OverlayConfig.js \
    qml/overlay/InstrumentClient.qml \
    qml/overlay/ScrollGraph.qml \
    qml/overlay/InstrumentPanel.qml \
    qml/overlay/InstrumentBar.qml \
    qml/overlay/ComponentCard.qml


SAILFISHAPP_ICONS = 86x86 108x108 128x128 172x172

# to disable building translations every time, comment out the
# following CONFIG line
CONFIG += sailfishapp_i18n

# German translation is enabled as an example. If you aren't
# planning to localize your app, remember to comment out the
# following TRANSLATIONS line. And also do not forget to
# modify the localized app name in the the .desktop file.
TRANSLATIONS += translations/harbour-labcam-de.ts \
                translations/harbour-labcam-es.ts \
                translations/harbour-labcam-fi.ts \
                translations/harbour-labcam-fr.ts \
                translations/harbour-labcam-sv.ts \
                translations/harbour-labcam-zh_CN.ts

HEADERS += \
    src/effectsmodel.h \
    src/exifmodel.h \
    src/exposuremodel.h \
    src/isomodel.h \
    src/metadatamodel.h \
    src/resolutionmodel.h \
    src/wbmodel.h \
    src/focusmodel.h \
    src/flashmodel.h \
    src/fsoperations.h \
    src/resourcehandler.h \
    src/storagemodel.h \
    src/imageoverlay.h \
    src/componentid.h \
    src/thermalcamera.h

CONFIG += c++11
LIBS += -ldl -lpthread
