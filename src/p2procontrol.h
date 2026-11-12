// p2procontrol.h — InfiRay P2 Pro vendor commands over usbfs. © JimKnopfIoT (shared with harbour-ircam).
//
// The P2 Pro takes its settings as vendor control transfers on endpoint 0
// (bRequest 0x45 write / 0x44 read, wValue 0x78), not as UVC controls, so they
// cannot go through the V4L2 node. They go through /dev/bus/usb/BBB/DDD
// instead; the kernel lets vendor requests past the interface that uvcvideo
// holds, so this works while the stream runs. usbfs ioctls need the node
// opened for writing.
//
// Protocol from P2Pro-Viewer (LeoDJ, MIT), cross-checked against lbatalha/p2-viewer
// and stanelie/p2-viewer: "long command" prop_tpd_params with TPD_PROP_GAIN_SEL —
// 1 = high gain (-20..150 °C), 0 = low gain (100..600 °C). The temperature plane keeps
// its scale in both; only the saturation point moves. The camera recalibrates by
// itself after the switch (busy for ~2.6 s), so no separate shutter command is sent.
#ifndef P2PROCONTROL_H
#define P2PROCONTROL_H

#include <QString>

namespace p2pro {

static const int VID = 0x0bda;
static const int PID = 0x5830;

// usbfs node of the USB device behind a V4L2 node ("video2"); empty if unknown.
QString usbNodeFor(const QString &videoNode);

// Open the usbfs node read-write; -1 with errno set on failure.
int openUsb(const QString &usbNode);

// Gain select. On failure returns false and fills *err.
bool setHighGain(int fd, bool high, QString *err);
bool getHighGain(int fd, bool *high, QString *err);

} // namespace p2pro

#endif // P2PROCONTROL_H
