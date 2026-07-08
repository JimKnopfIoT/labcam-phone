// SPDX-License-Identifier: GPL-2.0-or-later
// Part of LabCam, a lab-instrument / thermal-camera / component-ID fork of
// harbour-advanced-camera (C) Adam Pigg and contributors, GPL-2.0-or-later.
// LabCam additions (C) 2026 the LabCam contributors.

#ifndef THERMALCAMERA_H
#define THERMALCAMERA_H

// V4L2 capturer for the InfiRay P2 Pro (UVC 0bda:5830, /dev/video2).
// Delivers YUYV 256x384: upper 256x192 = thermal image, lower half = 16-bit temperature data.
// v1: upper half (Y channel) -> auto-contrast -> INFERNO palette -> QImage; exposed
// to QML via a QQuickImageProvider. Capture runs in a dedicated std::thread.
// Upscaling/unsharp/temperature (hotspot, deg C) to follow in v2.

#include <QObject>
#include <QImage>
#include <QMutex>
#include <QString>
#include <QQuickImageProvider>
#include <atomic>
#include <thread>
#include <vector>

class ThermalCamera : public QObject
{
    Q_OBJECT
    Q_PROPERTY(QString status READ status NOTIFY statusChanged)
    Q_PROPERTY(bool active READ active NOTIFY activeChanged)
    // Temperature (deg C) from the lower stream half (16-bit). Min/Max + normalized
    // positions (0..1 over the 256x192 image, same orientation as the display image).
    Q_PROPERTY(double tMin READ tMin NOTIFY tempUpdated)
    Q_PROPERTY(double tMax READ tMax NOTIFY tempUpdated)
    Q_PROPERTY(double tMinX READ tMinX NOTIFY tempUpdated)
    Q_PROPERTY(double tMinY READ tMinY NOTIFY tempUpdated)
    Q_PROPERTY(double tMaxX READ tMaxX NOTIFY tempUpdated)
    Q_PROPERTY(double tMaxY READ tMaxY NOTIFY tempUpdated)
    Q_PROPERTY(bool tempValid READ tempValid NOTIFY tempUpdated)
    // Calibration offset (deg C), added to all decoded temperatures.
    Q_PROPERTY(double tempOffset READ tempOffset WRITE setTempOffset NOTIFY tempOffsetChanged)
    // Sharpening (unsharp mask) applied to the upscaled image; 0 = off, ~1.2 = default.
    Q_PROPERTY(double sharpen READ sharpen WRITE setSharpen NOTIFY sharpenChanged)
public:
    explicit ThermalCamera(QObject *parent = nullptr);
    ~ThermalCamera() override;

    QString status() const { return m_status; }
    bool active() const { return m_run.load(); }

    double tMin()  { QMutexLocker l(&m_mx); return m_tMin + m_tempOffset.load(); }
    double tMax()  { QMutexLocker l(&m_mx); return m_tMax + m_tempOffset.load(); }
    double tMinX() { QMutexLocker l(&m_mx); return m_tMinX; }
    double tMinY() { QMutexLocker l(&m_mx); return m_tMinY; }
    double tMaxX() { QMutexLocker l(&m_mx); return m_tMaxX; }
    double tMaxY() { QMutexLocker l(&m_mx); return m_tMaxY; }
    bool tempValid() { QMutexLocker l(&m_mx); return m_tempValid; }
    double tempOffset() const { return m_tempOffset; }
    void setTempOffset(double v);
    double sharpen() const { return m_sharpen; }
    void setSharpen(double v);

    // Thread-safe copy of the most recent frame (for the ImageProvider).
    QImage currentFrame();

    // Temperature (deg C, including offset) at normalized position (nx,ny) in the image; NaN if invalid.
    Q_INVOKABLE double tempAt(double nx, double ny);

    Q_INVOKABLE void start(const QString &dev = QStringLiteral("/dev/video2"));
    Q_INVOKABLE void stop();

signals:
    void frameReady(quint64 frame);   // 'frame' statt 'id' (id ist in QML reserviert)
    void statusChanged();
    void activeChanged();
    void tempUpdated();
    void tempOffsetChanged();
    void sharpenChanged();

private:
    void loop();                         // runs in the worker thread
    void setStatus(const QString &s);

    QString m_dev;
    QString m_status;
    std::atomic<bool> m_run{false};
    std::thread m_thread;
    QMutex m_mx;
    QImage m_frame;
    quint64 m_id{0};

    // Temperature grid (256x192, deg C without offset) + derived values, guarded by m_mx.
    std::vector<float> m_temps;
    int m_tw{0}, m_th{0};
    double m_tMin{0}, m_tMax{0};
    double m_tMinX{0}, m_tMinY{0}, m_tMaxX{0}, m_tMaxY{0};
    bool m_tempValid{false};
    std::atomic<double> m_tempOffset{0.0};
    std::atomic<double> m_sharpen{1.2};
};

// Exposes the most recent thermal frame as image://thermal/<id>.
class ThermalImageProvider : public QQuickImageProvider
{
public:
    explicit ThermalImageProvider(ThermalCamera *cam)
        : QQuickImageProvider(QQuickImageProvider::Image), m_cam(cam) {}
    QImage requestImage(const QString &id, QSize *size, const QSize &requested) override;
private:
    ThermalCamera *m_cam;
};

#endif // THERMALCAMERA_H
