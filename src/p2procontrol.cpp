// p2procontrol.cpp — InfiRay P2 Pro vendor commands over usbfs. © JimKnopfIoT (shared with harbour-ircam).
#include "p2procontrol.h"

#include <QFile>
#include <QFileInfo>
#include <cerrno>
#include <cstring>
#include <fcntl.h>
#include <unistd.h>
#include <sys/ioctl.h>
#include <linux/usbdevice_fs.h>

namespace p2pro {

static const unsigned char REQ_OUT = 0x41;   // vendor, host-to-device, interface
static const unsigned char REQ_IN = 0xC1;    // vendor, device-to-host, interface
static const unsigned char CMD_WRITE = 0x45;
static const unsigned char CMD_READ = 0x44;
static const unsigned short W_VALUE = 0x78;
static const unsigned CTRL_TIMEOUT_MS = 1000;
static const int READY_TIMEOUT_MS = 2000;
// A gain switch recalibrates the sensor and keeps the camera busy for ~2.6 s.
static const int GAIN_TIMEOUT_MS = 15000;

static const unsigned short PROP_TPD_PARAMS = 0x8514;
static const unsigned short DIR_SET = 0x4000;
static const unsigned TPD_PROP_GAIN_SEL = 5;

static int readSysInt(const QString &path)
{
    QFile f(path);
    if (!f.open(QIODevice::ReadOnly))
        return -1;
    bool ok = false;
    const int v = f.readAll().trimmed().toInt(&ok);
    return ok ? v : -1;
}

QString usbNodeFor(const QString &videoNode)
{
    // .../videoN/device -> the UVC interface (1-1:1.0); its parent is the USB device.
    const QString iface = QFileInfo(QStringLiteral("/sys/class/video4linux/") + videoNode
                                    + QStringLiteral("/device")).canonicalFilePath();
    if (iface.isEmpty())
        return QString();
    const QString usbDev = QFileInfo(iface).path();
    const int bus = readSysInt(usbDev + QStringLiteral("/busnum"));
    const int dev = readSysInt(usbDev + QStringLiteral("/devnum"));
    if (bus <= 0 || dev <= 0)
        return QString();
    return QString::asprintf("/dev/bus/usb/%03d/%03d", bus, dev);
}

int openUsb(const QString &usbNode)
{
    const QByteArray p = usbNode.toUtf8();
    return ::open(p.constData(), O_RDWR | O_CLOEXEC);
}

static int ctrl(int fd, unsigned char type, unsigned char req, unsigned short index,
                void *data, unsigned short len)
{
    struct usbdevfs_ctrltransfer c;
    memset(&c, 0, sizeof c);
    c.bRequestType = type;
    c.bRequest = req;
    c.wValue = W_VALUE;
    c.wIndex = index;
    c.wLength = len;
    c.timeout = CTRL_TIMEOUT_MS;
    c.data = data;
    int r;
    do { r = ioctl(fd, USBDEVFS_CONTROL, &c); } while (r == -1 && errno == EINTR);
    return r;
}

static QString errnoText(const char *what)
{
    return QStringLiteral("%1: %2").arg(QLatin1String(what),
                                        QString::fromLocal8Bit(strerror(errno)));
}

// Poll the command status until the camera has taken the command
// (i2c_usb_check_access_done in the vendor SDK).
static bool waitReady(int fd, int timeoutMs, QString *err)
{
    for (int ms = 0; ms < timeoutMs; ms += 5) {
        unsigned char st = 0;
        if (ctrl(fd, REQ_IN, CMD_READ, 0x0200, &st, 1) != 1) {
            *err = errnoText("status");
            return false;
        }
        if (st & 0xFC) {
            *err = QString::asprintf("camera status 0x%02x", st);
            return false;
        }
        if (!(st & 0x03))
            return true;
        usleep(5000);
    }
    *err = QStringLiteral("camera did not answer");
    return false;
}

static void putBE16(unsigned char *p, unsigned v) { p[0] = v >> 8; p[1] = v; }
static void putBE32(unsigned char *p, unsigned v)
{
    p[0] = v >> 24; p[1] = v >> 16; p[2] = v >> 8; p[3] = v;
}

// "Long command": cmd (LE16) + p1 (BE16) + p2 (BE32) to 0x9d00, then p3, p4 (BE32) to 0x1d08.
static bool longCmd(int fd, unsigned short cmd, unsigned p1, unsigned p2,
                    unsigned p3, unsigned p4, int timeoutMs, QString *err)
{
    unsigned char a[8], b[8];
    a[0] = cmd & 0xff;
    a[1] = cmd >> 8;
    putBE16(a + 2, p1);
    putBE32(a + 4, p2);
    putBE32(b, p3);
    putBE32(b + 4, p4);
    if (ctrl(fd, REQ_OUT, CMD_WRITE, 0x9d00, a, sizeof a) != int(sizeof a)
            || ctrl(fd, REQ_OUT, CMD_WRITE, 0x1d08, b, sizeof b) != int(sizeof b)) {
        *err = errnoText("command");
        return false;
    }
    return waitReady(fd, timeoutMs, err);
}

bool setHighGain(int fd, bool high, QString *err)
{
    return longCmd(fd, PROP_TPD_PARAMS | DIR_SET, TPD_PROP_GAIN_SEL, high ? 1 : 0, 0, 0,
                   GAIN_TIMEOUT_MS, err);
}

bool getHighGain(int fd, bool *high, QString *err)
{
    if (!longCmd(fd, PROP_TPD_PARAMS, TPD_PROP_GAIN_SEL, 0, 0, 2, READY_TIMEOUT_MS, err))
        return false;
    unsigned char v[2] = { 0, 0 };
    if (ctrl(fd, REQ_IN, CMD_READ, 0x1d10, v, 2) != 2) {
        *err = errnoText("read");
        return false;
    }
    *high = ((v[0] << 8) | v[1]) != 0;
    return true;
}

} // namespace p2pro
