// SPDX-License-Identifier: GPL-2.0-or-later
// Part of LabCam, a lab-instrument / thermal-camera / component-ID fork of
// harbour-advanced-camera (C) Adam Pigg and contributors, GPL-2.0-or-later.
// LabCam additions (C) 2026 the LabCam contributors.

#include "thermalcamera.h"

#include <QDebug>
#include <cstring>
#include <cerrno>
#include <cmath>
#include <limits>
#include <fcntl.h>
#include <unistd.h>
#include <sys/ioctl.h>
#include <sys/mman.h>
#include <sys/select.h>
#include <linux/videodev2.h>

// Sensor: 256x192 image; the UVC stream is 256x384 with temperature data appended below.
static const int SRC_W = 256;
static const int SRC_H = 384;     // YUYV total
static const int IMG_H = 192;     // upper half = image

// ---- INFERNO palette: 256 entries linearly interpolated from control points ----
struct RGB { int r, g, b; };
static QRgb g_lut[256];
static bool g_lutReady = false;
static void buildLut()
{
    static const struct { double t; RGB c; } cp[] = {
        {0.00, {  0,   0,   4}}, {0.14, { 40,  11,  84}},
        {0.29, {101,  21, 110}}, {0.43, {159,  42,  99}},
        {0.57, {212,  72,  66}}, {0.71, {245, 125,  21}},
        {0.86, {250, 193,  39}}, {1.00, {252, 255, 164}},
    };
    const int n = sizeof(cp) / sizeof(cp[0]);
    for (int i = 0; i < 256; ++i) {
        double t = i / 255.0;
        int k = 0;
        while (k < n - 2 && t > cp[k + 1].t) ++k;
        double f = (t - cp[k].t) / (cp[k + 1].t - cp[k].t);
        if (f < 0) f = 0; if (f > 1) f = 1;
        int r = int(cp[k].c.r + f * (cp[k + 1].c.r - cp[k].c.r));
        int g = int(cp[k].c.g + f * (cp[k + 1].c.g - cp[k].c.g));
        int b = int(cp[k].c.b + f * (cp[k + 1].c.b - cp[k].c.b));
        g_lut[i] = qRgb(r, g, b);
    }
    g_lutReady = true;
}

// Separable 5-tap Gaussian ([1,4,6,4,1]/16, radius ~2) — basis for an edge-preserving
// unsharp mask (cleaner than a plain Laplacian high-pass).
static QImage gauss5(const QImage &src)
{
    static const int K[5] = {1, 4, 6, 4, 1};
    const int w = src.width(), h = src.height();
    QImage tmp(w, h, QImage::Format_RGB32);
    for (int y = 0; y < h; ++y) {                       // horizontal pass
        const QRgb *s = reinterpret_cast<const QRgb *>(src.scanLine(y));
        QRgb *d = reinterpret_cast<QRgb *>(tmp.scanLine(y));
        for (int x = 0; x < w; ++x) {
            int r = 0, g = 0, b = 0;
            for (int i = -2; i <= 2; ++i) {
                int xx = x + i; if (xx < 0) xx = 0; if (xx >= w) xx = w - 1;
                int k = K[i + 2]; QRgb p = s[xx];
                r += k * qRed(p); g += k * qGreen(p); b += k * qBlue(p);
            }
            d[x] = qRgb(r >> 4, g >> 4, b >> 4);
        }
    }
    QImage out(w, h, QImage::Format_RGB32);
    for (int y = 0; y < h; ++y) {                       // vertical pass
        QRgb *d = reinterpret_cast<QRgb *>(out.scanLine(y));
        for (int x = 0; x < w; ++x) {
            int r = 0, g = 0, b = 0;
            for (int i = -2; i <= 2; ++i) {
                int yy = y + i; if (yy < 0) yy = 0; if (yy >= h) yy = h - 1;
                int k = K[i + 2];
                QRgb p = reinterpret_cast<const QRgb *>(tmp.scanLine(yy))[x];
                r += k * qRed(p); g += k * qGreen(p); b += k * qBlue(p);
            }
            d[x] = qRgb(r >> 4, g >> 4, b >> 4);
        }
    }
    return out;
}

// "Superfine": smooth upscale (x3 -> 768x576) + unsharp mask (strength 'amt').
static QImage upscaleSharp(const QImage &src, double amt)
{
    QImage up = src.scaled(src.width() * 3, src.height() * 3,
                           Qt::IgnoreAspectRatio, Qt::SmoothTransformation);
    if (amt <= 0.0) return up;
    QImage blur = gauss5(up);
    const int w = up.width(), h = up.height();
    QImage out(w, h, QImage::Format_RGB32);
    for (int y = 0; y < h; ++y) {
        const QRgb *u = reinterpret_cast<const QRgb *>(up.scanLine(y));
        const QRgb *bl = reinterpret_cast<const QRgb *>(blur.scanLine(y));
        QRgb *o = reinterpret_cast<QRgb *>(out.scanLine(y));
        for (int x = 0; x < w; ++x) {
            int r = qRed(u[x])   + int(amt * (qRed(u[x])   - qRed(bl[x])));
            int g = qGreen(u[x]) + int(amt * (qGreen(u[x]) - qGreen(bl[x])));
            int b = qBlue(u[x])  + int(amt * (qBlue(u[x])  - qBlue(bl[x])));
            if (r < 0) r = 0; if (r > 255) r = 255;
            if (g < 0) g = 0; if (g > 255) g = 255;
            if (b < 0) b = 0; if (b > 255) b = 255;
            o[x] = qRgb(r, g, b);
        }
    }
    return out;
}

ThermalCamera::ThermalCamera(QObject *parent) : QObject(parent)
{
    if (!g_lutReady) buildLut();
}

ThermalCamera::~ThermalCamera()
{
    stop();
}

void ThermalCamera::setStatus(const QString &s)
{
    m_status = s;
    qWarning() << "[thermal]" << s;     // goes to journald
    emit statusChanged();
}

QImage ThermalCamera::currentFrame()
{
    QMutexLocker lock(&m_mx);
    return m_frame;
}

void ThermalCamera::setTempOffset(double v)
{
    m_tempOffset.store(v);
    emit tempOffsetChanged();
    emit tempUpdated();   // update display/labels immediately
}

void ThermalCamera::setSharpen(double v)
{
    if (v < 0) v = 0; if (v > 4) v = 4;
    m_sharpen.store(v);
    emit sharpenChanged();
}

double ThermalCamera::tempAt(double nx, double ny)
{
    QMutexLocker lock(&m_mx);
    if (!m_tempValid || m_tw <= 0 || m_th <= 0)
        return std::numeric_limits<double>::quiet_NaN();
    int x = int(nx * m_tw); if (x < 0) x = 0; if (x >= m_tw) x = m_tw - 1;
    int y = int(ny * m_th); if (y < 0) y = 0; if (y >= m_th) y = m_th - 1;
    return double(m_temps[y * m_tw + x]) + m_tempOffset.load();
}

void ThermalCamera::start(const QString &dev)
{
    if (m_run.load()) return;
    m_dev = dev;
    m_run.store(true);
    emit activeChanged();
    m_thread = std::thread(&ThermalCamera::loop, this);
}

void ThermalCamera::stop()
{
    if (!m_run.load()) { if (m_thread.joinable()) m_thread.join(); return; }
    m_run.store(false);
    if (m_thread.joinable()) m_thread.join();
    emit activeChanged();
}

static int xioctl(int fd, unsigned long req, void *arg)
{
    int r;
    do { r = ioctl(fd, req, arg); } while (r == -1 && errno == EINTR);
    return r;
}

void ThermalCamera::loop()
{
    const QByteArray devUtf8 = m_dev.toUtf8();
    int fd = ::open(devUtf8.constData(), O_RDWR | O_NONBLOCK);
    if (fd < 0) {
        setStatus(QStringLiteral("open %1 FAILED: %2").arg(m_dev).arg(strerror(errno)));
        m_run.store(false); emit activeChanged();
        return;
    }
    setStatus(QStringLiteral("open %1 OK").arg(m_dev));

    struct v4l2_format fmt; memset(&fmt, 0, sizeof fmt);
    fmt.type = V4L2_BUF_TYPE_VIDEO_CAPTURE;
    fmt.fmt.pix.width = SRC_W;
    fmt.fmt.pix.height = SRC_H;
    fmt.fmt.pix.pixelformat = V4L2_PIX_FMT_YUYV;
    fmt.fmt.pix.field = V4L2_FIELD_NONE;
    if (xioctl(fd, VIDIOC_S_FMT, &fmt) < 0) {
        setStatus(QStringLiteral("S_FMT FAILED: %1").arg(strerror(errno)));
        ::close(fd); m_run.store(false); emit activeChanged(); return;
    }
    const int w = fmt.fmt.pix.width;
    const int h = fmt.fmt.pix.height;
    setStatus(QStringLiteral("Format %1x%2 YUYV").arg(w).arg(h));

    struct v4l2_requestbuffers req; memset(&req, 0, sizeof req);
    req.count = 4; req.type = V4L2_BUF_TYPE_VIDEO_CAPTURE; req.memory = V4L2_MEMORY_MMAP;
    if (xioctl(fd, VIDIOC_REQBUFS, &req) < 0 || req.count < 2) {
        setStatus(QStringLiteral("REQBUFS FAILED: %1").arg(strerror(errno)));
        ::close(fd); m_run.store(false); emit activeChanged(); return;
    }
    struct Buf { void *start; size_t len; };
    Buf bufs[8]; unsigned nbuf = req.count > 8 ? 8 : req.count;
    for (unsigned i = 0; i < nbuf; ++i) {
        struct v4l2_buffer b; memset(&b, 0, sizeof b);
        b.type = V4L2_BUF_TYPE_VIDEO_CAPTURE; b.memory = V4L2_MEMORY_MMAP; b.index = i;
        if (xioctl(fd, VIDIOC_QUERYBUF, &b) < 0) { setStatus("QUERYBUF FAILED"); ::close(fd); m_run.store(false); emit activeChanged(); return; }
        bufs[i].len = b.length;
        bufs[i].start = mmap(nullptr, b.length, PROT_READ | PROT_WRITE, MAP_SHARED, fd, b.m.offset);
        if (bufs[i].start == MAP_FAILED) { setStatus("mmap FAILED"); ::close(fd); m_run.store(false); emit activeChanged(); return; }
        xioctl(fd, VIDIOC_QBUF, &b);
    }
    enum v4l2_buf_type type = V4L2_BUF_TYPE_VIDEO_CAPTURE;
    if (xioctl(fd, VIDIOC_STREAMON, &type) < 0) {
        setStatus(QStringLiteral("STREAMON FAILED: %1").arg(strerror(errno)));
        ::close(fd); m_run.store(false); emit activeChanged(); return;
    }
    setStatus(QStringLiteral("Streaming %1").arg(m_dev));

    QImage img(SRC_W, IMG_H, QImage::Format_RGB32);
    bool firstFrame = true;
    std::vector<float> temps(SRC_W * IMG_H);   // temperature grid (deg C, without offset)
    double emaLo = 0, emaHi = 0; bool emaInit = false;
    const double RANGE_SMOOTH = 0.7;           // smoothing of displayed min/max (prevents flicker)
    while (m_run.load()) {
        fd_set fds; FD_ZERO(&fds); FD_SET(fd, &fds);
        struct timeval tv; tv.tv_sec = 1; tv.tv_usec = 0;
        int r = select(fd + 1, &fds, nullptr, nullptr, &tv);
        if (r <= 0) { if (r < 0 && errno == EINTR) continue; continue; }

        struct v4l2_buffer b; memset(&b, 0, sizeof b);
        b.type = V4L2_BUF_TYPE_VIDEO_CAPTURE; b.memory = V4L2_MEMORY_MMAP;
        if (xioctl(fd, VIDIOC_DQBUF, &b) < 0) { if (errno == EAGAIN) continue; continue; }

        const unsigned char *data = static_cast<const unsigned char *>(bufs[b.index].start);
        // Auto-contrast over the upper image half (Y channel, every 2nd byte).
        int lo = 255, hi = 0;
        for (int y = 0; y < IMG_H; ++y) {
            const unsigned char *row = data + (y * w) * 2;
            for (int x = 0; x < w; ++x) { int Y = row[x * 2]; if (Y < lo) lo = Y; if (Y > hi) hi = Y; }
        }
        int span = hi - lo; if (span < 1) span = 1;
        for (int y = 0; y < IMG_H; ++y) {
            const unsigned char *row = data + (y * w) * 2;
            QRgb *out = reinterpret_cast<QRgb *>(img.scanLine(y));
            for (int x = 0; x < w; ++x) {
                int Y = row[x * 2];
                int idx = (Y - lo) * 255 / span; if (idx < 0) idx = 0; if (idx > 255) idx = 255;
                out[x] = g_lut[idx];
            }
        }
        QImage fin = upscaleSharp(img, m_sharpen.load());   // x3 + unsharp (superfine)

        // ---- Decode temperature from the LOWER stream half (16-bit LE) ----
        // P2 Pro: lower 256x192 = raw temperature, raw/64 - 273.15 = deg C.
        double tmin = 1e9, tmax = -1e9; int mnX = 0, mnY = 0, mxX = 0, mxY = 0;
        for (int y = 0; y < IMG_H; ++y) {
            const unsigned char *row = data + ((IMG_H + y) * w) * 2;
            float *trow = temps.data() + y * SRC_W;
            for (int x = 0; x < w; ++x) {
                int raw = row[x * 2] | (row[x * 2 + 1] << 8);
                double c = raw / 64.0 - 273.15;
                trow[x] = float(c);
                if (c < tmin) { tmin = c; mnX = x; mnY = y; }
                if (c > tmax) { tmax = c; mxX = x; mxY = y; }
            }
        }
        // Plausibility check — mark as invalid if values are out of range.
        bool tok = (tmax > -60.0 && tmax < 600.0 && tmin > -60.0 && tmin < 600.0);
        if (tok) {
            if (!emaInit) { emaLo = tmin; emaHi = tmax; emaInit = true; }
            else { emaLo = RANGE_SMOOTH * emaLo + (1 - RANGE_SMOOTH) * tmin;
                   emaHi = RANGE_SMOOTH * emaHi + (1 - RANGE_SMOOTH) * tmax; }
        }

        {
            QMutexLocker lock(&m_mx);
            m_frame = fin;
            ++m_id;
            if (tok) {
                m_temps = temps; m_tw = SRC_W; m_th = IMG_H;
                m_tMin = emaLo; m_tMax = emaHi;
                m_tMinX = (mnX + 0.5) / SRC_W; m_tMinY = (mnY + 0.5) / IMG_H;
                m_tMaxX = (mxX + 0.5) / SRC_W; m_tMaxY = (mxY + 0.5) / IMG_H;
                m_tempValid = true;
            } else {
                m_tempValid = false;
            }
        }
        if (firstFrame) { setStatus(QStringLiteral("Frames running (%1x%2)").arg(w).arg(IMG_H)); firstFrame = false; }
        emit frameReady(m_id);
        if (tok) emit tempUpdated();
        xioctl(fd, VIDIOC_QBUF, &b);
    }

    xioctl(fd, VIDIOC_STREAMOFF, &type);
    for (unsigned i = 0; i < nbuf; ++i) munmap(bufs[i].start, bufs[i].len);
    ::close(fd);
    setStatus(QStringLiteral("stopped"));
}

QImage ThermalImageProvider::requestImage(const QString &, QSize *size, const QSize &)
{
    QImage img = m_cam->currentFrame();
    if (img.isNull()) { img = QImage(2, 2, QImage::Format_RGB32); img.fill(Qt::black); }
    if (size) *size = img.size();
    return img;
}
