// SPDX-License-Identifier: GPL-2.0-or-later
// Part of LabCam, a lab-instrument / thermal-camera / component-ID fork of
// harbour-advanced-camera (C) Adam Pigg and contributors, GPL-2.0-or-later.
// LabCam additions (C) 2026 the LabCam contributors.

#ifndef IMAGEOVERLAY_H
#define IMAGEOVERLAY_H

#include <QObject>
#include <QString>
#include <QVariantList>

// Composites a QML-rendered overlay PNG (with alpha) onto a captured photo and
// saves the result non-destructively as "<basename>_ovl.jpg".
// The photo is loaded with EXIF auto-transform (upright), and the overlay is
// already rendered upright in UI orientation — no further rotation is needed.
class ImageOverlay : public QObject
{
    Q_OBJECT
public:
    explicit ImageOverlay(QObject *parent = nullptr);

    // gravity: 0 = top-left, 1 = bottom-left, 2 = bottom-right.
    // widthFraction: overlay width as a fraction of the photo width (1.0 = full width
    //   top/bottom = landscape bar; <1.0 = narrow strip on the left = portrait).
    // Returns the path of the saved file, or "" on error.
    // outPath: empty = default "<basename>_ovl.jpg" next to the photo; otherwise explicit target path.
    Q_INVOKABLE QString burnOverlay(const QString &photoPath,
                                    const QString &overlayPath,
                                    int gravity = 0,
                                    int quality = 95,
                                    double widthFraction = 1.0,
                                    const QString &outPath = QString());

    // Composites an overlay PNG at a NORMALIZED rectangle position into the (EXIF-upright)
    // photo: target rect = [nx,ny,nw,nh] * (W,H). nx<0 / nw>1 is allowed (e.g. IR wider than
    // the image area) — QPainter clips automatically to the photo. Used for the P2 Pro thermal
    // image (WYSIWYG at the display position). Returns outPath, or "" on error.
    Q_INVOKABLE QString burnImageRect(const QString &photoPath,
                                      const QString &overlayPath,
                                      double nx, double ny, double nw, double nh,
                                      int quality = 95,
                                      const QString &outPath = QString());

    // Draws a tight silhouette (polygon outline) around the identified component into the photo.
    // pointsNorm: list of [x,y] points, normalized 0..1 WITHIN the ROI crop.
    // nx,ny,nw,nh: ROI in the (EXIF-upright) photo, normalized 0..1 — maps points onto the
    // full image: X=(nx+px*nw)*W, Y=(ny+py*nh)*H. Returns outPath, or "" on error.
    Q_INVOKABLE QString drawSilhouette(const QString &photoPath,
                                       const QVariantList &pointsNorm,
                                       double nx, double ny, double nw, double nh,
                                       const QString &outPath,
                                       int quality = 95);

signals:
    void composed(const QString &outputPath);
    void error(const QString &message);
};

#endif // IMAGEOVERLAY_H
