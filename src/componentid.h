// SPDX-License-Identifier: GPL-2.0-or-later
// Part of LabCam, a lab-instrument / thermal-camera / component-ID fork of
// harbour-advanced-camera (C) Adam Pigg and contributors, GPL-2.0-or-later.
// LabCam additions (C) 2026 the LabCam contributors.

#ifndef COMPONENTID_H
#define COMPONENTID_H

#include <QObject>
#include <QString>
#include <QNetworkAccessManager>

// Crops the selected ROI from the captured photo, sends it (base64) to the
// component-ID service (POST /identify) and reports the JSON response via signal.
// Registered as context property "componentId".
class ComponentId : public QObject
{
    Q_OBJECT
    Q_PROPERTY(QString serviceUrl READ serviceUrl WRITE setServiceUrl NOTIFY serviceUrlChanged)
    Q_PROPERTY(bool busy READ busy NOTIFY busyChanged)
public:
    explicit ComponentId(QObject *parent = nullptr);

    QString serviceUrl() const { return m_serviceUrl; }
    void setServiceUrl(const QString &url);
    bool busy() const { return m_busy; }

    // nx,ny,nw,nh: normalized ROI [0..1] relative to the upright (EXIF-transformed) photo.
    // dmmJson: valid JSON object as a string, or "null".
    Q_INVOKABLE void identify(const QString &photoPath,
                              double nx, double ny, double nw, double nh,
                              const QString &dmmJson);

signals:
    void serviceUrlChanged();
    void busyChanged();
    void resultReady(const QString &json);
    void failed(const QString &error);

private:
    void setBusy(bool b);
    QString m_serviceUrl;
    bool m_busy;
    QNetworkAccessManager m_nam;
};

#endif // COMPONENTID_H
