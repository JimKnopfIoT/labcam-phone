// SPDX-License-Identifier: GPL-2.0-or-later
// Part of LabCam, a lab-instrument / thermal-camera / component-ID fork of
// harbour-advanced-camera (C) Adam Pigg and contributors, GPL-2.0-or-later.
// LabCam additions (C) 2026 the LabCam contributors.

#include "componentid.h"

#include <QImage>
#include <QImageReader>
#include <QBuffer>
#include <QUrl>
#include <QRect>
#include <QNetworkRequest>
#include <QNetworkReply>
#include <QNetworkProxy>
#include <QDebug>

static QString toLocalPath(const QString &p)
{
    if (p.startsWith("file://"))
        return QUrl(p).toLocalFile();
    return p;
}

ComponentId::ComponentId(QObject *parent)
    : QObject(parent),
      m_serviceUrl(QStringLiteral("http://192.168.10.6:7895/identify")),
      m_busy(false)
{
    // Disable system proxy for local LAN requests (prevents "unknown error" via proxy).
    m_nam.setProxy(QNetworkProxy(QNetworkProxy::NoProxy));
}

void ComponentId::setServiceUrl(const QString &url)
{
    if (url != m_serviceUrl) {
        m_serviceUrl = url;
        emit serviceUrlChanged();
    }
}

void ComponentId::setBusy(bool b)
{
    if (b != m_busy) {
        m_busy = b;
        emit busyChanged();
    }
}

void ComponentId::identify(const QString &photoPathIn,
                           double nx, double ny, double nw, double nh,
                           const QString &dmmJson)
{
    const QString photoPath = toLocalPath(photoPathIn);

    QImageReader reader(photoPath);
    reader.setAutoTransform(true); // upright photo (EXIF) -> ROI matches the viewfinder view
    QImage img = reader.read();
    if (img.isNull()) {
        emit failed(QStringLiteral("Cannot read photo: %1 (%2)").arg(photoPath, reader.errorString()));
        return;
    }

    const int w = img.width();
    const int h = img.height();
    int x = qBound(0, int(nx * w), w - 1);
    int y = qBound(0, int(ny * h), h - 1);
    int cw = qBound(1, int(nw * w), w - x);
    int ch = qBound(1, int(nh * h), h - y);
    QImage crop = img.copy(QRect(x, y, cw, ch));

    // Limit long edge to <=1568 (saves tokens/bandwidth; the service would rescale anyway).
    const int maxEdge = qMax(crop.width(), crop.height());
    if (maxEdge > 1568) {
        crop = crop.scaled(crop.width() * 1568 / maxEdge,
                           crop.height() * 1568 / maxEdge,
                           Qt::KeepAspectRatio, Qt::SmoothTransformation);
    }

    QByteArray jpeg;
    QBuffer buf(&jpeg);
    buf.open(QIODevice::WriteOnly);
    crop.save(&buf, "JPEG", 90);
    buf.close();

    const QByteArray b64 = jpeg.toBase64();
    QString dmm = dmmJson.trimmed();
    if (dmm.isEmpty())
        dmm = QStringLiteral("null");

    QByteArray body;
    body.reserve(b64.size() + 64);
    body.append("{\"image_b64\":\"");
    body.append(b64);
    body.append("\",\"dmm\":");
    body.append(dmm.toUtf8());
    body.append("}");

    QNetworkRequest req{QUrl(m_serviceUrl)};
    req.setHeader(QNetworkRequest::ContentTypeHeader, QByteArrayLiteral("application/json"));

    qWarning() << "ComponentId.identify POST" << m_serviceUrl
               << "crop" << crop.width() << "x" << crop.height()
               << "bodyBytes" << body.size();
    setBusy(true);
    QNetworkReply *reply = m_nam.post(req, body);
    connect(reply, &QNetworkReply::finished, this, [this, reply]() {
        setBusy(false);
        if (reply->error() != QNetworkReply::NoError) {
            const int code = int(reply->error());
            const QString msg = reply->errorString();
            qWarning() << "ComponentId POST ERROR code" << code << msg;
            emit failed(QStringLiteral("[%1] %2").arg(code).arg(msg));
        } else {
            emit resultReady(QString::fromUtf8(reply->readAll()));
        }
        reply->deleteLater();
    });
}
