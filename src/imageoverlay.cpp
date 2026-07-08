// SPDX-License-Identifier: GPL-2.0-or-later
// Part of LabCam, a lab-instrument / thermal-camera / component-ID fork of
// harbour-advanced-camera (C) Adam Pigg and contributors, GPL-2.0-or-later.
// LabCam additions (C) 2026 the LabCam contributors.

#include "imageoverlay.h"

#include <QImage>
#include <QImageReader>
#include <QPainter>
#include <QPainterPath>
#include <QPolygonF>
#include <QPointF>
#include <QRectF>
#include <QPen>
#include <QFileInfo>
#include <QUrl>
#include <QDebug>

ImageOverlay::ImageOverlay(QObject *parent) : QObject(parent)
{
}

static QString toLocalPath(const QString &p)
{
    if (p.startsWith("file://"))
        return QUrl(p).toLocalFile();
    return p;
}

QString ImageOverlay::burnOverlay(const QString &photoPathIn,
                                  const QString &overlayPathIn,
                                  int gravity,
                                  int quality,
                                  double widthFraction,
                                  const QString &outPathIn)
{
    const QString photoPath = toLocalPath(photoPathIn);
    const QString overlayPath = toLocalPath(overlayPathIn);

    // Load photo with EXIF orientation applied — upright as seen by the viewer.
    QImageReader reader(photoPath);
    reader.setAutoTransform(true);
    QImage photo = reader.read();
    if (photo.isNull()) {
        const QString msg = QStringLiteral("burnOverlay: cannot read photo: %1 (%2)")
                .arg(photoPath, reader.errorString());
        qWarning() << msg;
        emit error(msg);
        return QString();
    }
    if (photo.format() != QImage::Format_RGB32
            && photo.format() != QImage::Format_ARGB32) {
        photo = photo.convertToFormat(QImage::Format_RGB32);
    }

    QImage overlay(overlayPath);
    if (overlay.isNull()) {
        const QString msg = QStringLiteral("burnOverlay: cannot read overlay: %1").arg(overlayPath);
        qWarning() << msg;
        emit error(msg);
        return QString();
    }

    // Scale overlay to a fraction of the photo width (preserving aspect ratio).
    // widthFraction = 1.0 → full width (landscape bar at top/bottom),
    // <1.0 → narrow strip anchored to the left (portrait).
    if (widthFraction <= 0.0) widthFraction = 1.0;
    if (widthFraction > 1.0)  widthFraction = 1.0;
    const int targetW = qMax(1, qRound(photo.width() * widthFraction));
    QImage ov = overlay;
    if (ov.width() != targetW) {
        ov = overlay.scaledToWidth(targetW, Qt::SmoothTransformation);
    }
    // If the strip is taller than the photo (portrait: tall left column in a 3:4 photo),
    // scale it down proportionally to the photo height so nothing is clipped.
    if (ov.height() > photo.height()) {
        ov = ov.scaledToHeight(photo.height(), Qt::SmoothTransformation);
    }
    // gravity: 0=top-left, 1=bottom-left, 2=bottom-right.
    const int x = (gravity == 2) ? (photo.width() - ov.width()) : 0;
    const int y = (gravity == 1 || gravity == 2) ? (photo.height() - ov.height()) : 0;

    QPainter painter(&photo);
    painter.setRenderHint(QPainter::SmoothPixmapTransform, true);
    painter.drawImage(x, y, ov);
    painter.end();

    QString out = toLocalPath(outPathIn);
    if (out.isEmpty()) {
        const QFileInfo fi(photoPath);
        out = fi.absolutePath() + QStringLiteral("/")
                + fi.completeBaseName() + QStringLiteral("_ovl.jpg");
    }

    if (!photo.save(out, "JPEG", quality)) {
        const QString msg = QStringLiteral("burnOverlay: save failed: %1").arg(out);
        qWarning() << msg;
        emit error(msg);
        return QString();
    }

    qDebug() << "burnOverlay: saved" << out;
    emit composed(out);
    return out;
}

QString ImageOverlay::burnImageRect(const QString &photoPathIn,
                                    const QString &overlayPathIn,
                                    double nx, double ny, double nw, double nh,
                                    int quality,
                                    const QString &outPathIn)
{
    const QString photoPath = toLocalPath(photoPathIn);
    const QString overlayPath = toLocalPath(overlayPathIn);

    QImageReader reader(photoPath);
    reader.setAutoTransform(true);   // EXIF-upright — normalized display coords match
    QImage photo = reader.read();
    if (photo.isNull()) {
        const QString msg = QStringLiteral("burnImageRect: cannot read photo: %1 (%2)")
                .arg(photoPath, reader.errorString());
        qWarning() << msg; emit error(msg); return QString();
    }
    if (photo.format() != QImage::Format_RGB32 && photo.format() != QImage::Format_ARGB32)
        photo = photo.convertToFormat(QImage::Format_RGB32);

    QImage overlay(overlayPath);
    if (overlay.isNull()) {
        const QString msg = QStringLiteral("burnImageRect: cannot read overlay: %1").arg(overlayPath);
        qWarning() << msg; emit error(msg); return QString();
    }

    const double W = photo.width();
    const double H = photo.height();
    const QRectF dst(nx * W, ny * H, nw * W, nh * H);
    if (dst.width() < 1 || dst.height() < 1) {
        qWarning() << "burnImageRect: empty target rect"; return QString();
    }
    QImage ov = overlay.scaled(qRound(dst.width()), qRound(dst.height()),
                               Qt::IgnoreAspectRatio, Qt::SmoothTransformation);

    QPainter painter(&photo);
    painter.setRenderHint(QPainter::SmoothPixmapTransform, true);
    painter.drawImage(QPointF(dst.x(), dst.y()), ov);   // QPainter clips to photo bounds
    painter.end();

    QString out = toLocalPath(outPathIn);
    if (out.isEmpty()) {
        const QFileInfo fi(photoPath);
        out = fi.absolutePath() + QStringLiteral("/")
                + fi.completeBaseName() + QStringLiteral("_ovl.jpg");
    }
    if (!photo.save(out, "JPEG", quality)) {
        const QString msg = QStringLiteral("burnImageRect: save failed: %1").arg(out);
        qWarning() << msg; emit error(msg); return QString();
    }
    qDebug() << "burnImageRect: saved" << out;
    emit composed(out);
    return out;
}

QString ImageOverlay::drawSilhouette(const QString &photoPathIn,
                                     const QVariantList &pointsNorm,
                                     double nx, double ny, double nw, double nh,
                                     const QString &outPathIn,
                                     int quality)
{
    const QString photoPath = toLocalPath(photoPathIn);

    QImageReader reader(photoPath);
    reader.setAutoTransform(true); // upright as in the viewfinder — ROI mapping matches
    QImage photo = reader.read();
    if (photo.isNull()) {
        const QString msg = QStringLiteral("drawSilhouette: cannot read photo: %1 (%2)")
                .arg(photoPath, reader.errorString());
        qWarning() << msg;
        emit error(msg);
        return QString();
    }
    if (photo.format() != QImage::Format_RGB32
            && photo.format() != QImage::Format_ARGB32) {
        photo = photo.convertToFormat(QImage::Format_RGB32);
    }

    const double W = photo.width();
    const double H = photo.height();
    // Map points (0..1 within ROI) to full-image pixels.
    QPolygonF poly;
    for (const QVariant &pv : pointsNorm) {
        const QVariantList xy = pv.toList();
        if (xy.size() < 2)
            continue;
        const double px = xy.at(0).toDouble();
        const double py = xy.at(1).toDouble();
        poly << QPointF((nx + px * nw) * W, (ny + py * nh) * H);
    }
    if (poly.size() < 3) {
        qWarning() << "drawSilhouette: too few points" << poly.size();
        return QString();
    }

    // Bounding box of the component — draw white corner brackets only (like the outer selection frame).
    const QRectF bb = poly.boundingRect();
    if (bb.width() <= 0 || bb.height() <= 0) {
        qWarning() << "drawSilhouette: empty bounding box";
        return QString();
    }
    const double x = bb.x(), y = bb.y(), w = bb.width(), h = bb.height();
    const double len = qMax(8.0, qMin(w, h) * 0.22);  // length of corner arms
    QPainterPath path;
    path.moveTo(x, y + len);             path.lineTo(x, y);             path.lineTo(x + len, y);             // top-left
    path.moveTo(x + w - len, y);         path.lineTo(x + w, y);         path.lineTo(x + w, y + len);         // top-right
    path.moveTo(x + w, y + h - len);     path.lineTo(x + w, y + h);     path.lineTo(x + w - len, y + h);     // bottom-right
    path.moveTo(x + len, y + h);         path.lineTo(x, y + h);         path.lineTo(x, y + h - len);         // bottom-left

    QPainter painter(&photo);
    painter.setRenderHint(QPainter::Antialiasing, true);
    const int lw = qMax(3, int(photo.width() / 320));
    // White corners only (no dark border).
    QPen pen(Qt::white);
    pen.setWidth(lw);
    pen.setCapStyle(Qt::FlatCap);
    pen.setJoinStyle(Qt::MiterJoin);
    painter.setPen(pen);
    painter.setBrush(Qt::NoBrush);
    painter.drawPath(path);
    painter.end();

    QString out = toLocalPath(outPathIn);
    if (out.isEmpty()) {
        const QFileInfo fi(photoPath);
        out = fi.absolutePath() + QStringLiteral("/")
                + fi.completeBaseName() + QStringLiteral("_sil.jpg");
    }
    if (!photo.save(out, "JPEG", quality)) {
        const QString msg = QStringLiteral("drawSilhouette: save failed: %1").arg(out);
        qWarning() << msg;
        emit error(msg);
        return QString();
    }
    qDebug() << "drawSilhouette: saved" << out << "points" << poly.size();
    return out;
}
