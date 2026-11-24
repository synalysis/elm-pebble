#include "handheld_host.h"

/* Replay numeric draw and command ids onto the portable host.
 * The same function is linked into a MeowKit blob and a Flipper FAP. */
int handheld_apply_draw(const HandheldHost *host, int32_t kind, const int32_t *params,
                        const char *text) {
    if (!host || !host->graphics || !host->graphics->draw) return -1;
    host->graphics->draw(host->ud, kind, params, params ? 6 : 0, text);
    return 0;
}

int handheld_apply_cmd(const HandheldHost *host, int32_t kind, const int32_t *params,
                       const char *text) {
    int32_t p0 = params ? params[0] : 0;
    int32_t p1 = params ? params[1] : 0;
    if (!host) return -1;
    switch (kind) {
    case HANDHELD_CMD_VIBES_CANCEL:
        if (host->haptics) host->haptics->vibrate(host->ud, 0);
        return host->haptics ? 0 : -1;
    case HANDHELD_CMD_VIBES_SHORT:
        if (host->haptics) host->haptics->vibrate(host->ud, 80);
        return host->haptics ? 0 : -1;
    case HANDHELD_CMD_VIBES_LONG:
        if (host->haptics) host->haptics->vibrate(host->ud, 300);
        return host->haptics ? 0 : -1;
    case HANDHELD_CMD_VIBES_DOUBLE:
        if (host->haptics) host->haptics->vibrate(host->ud, 160);
        return host->haptics ? 0 : -1;
    case HANDHELD_CMD_BATTERY:
        return host->sensors ? host->sensors->battery(host->ud) : -1;
    case HANDHELD_CMD_DISPLAY_METRICS: {
        HandheldDisplayMetrics m;
        if (!host->graphics) return -1;
        host->graphics->metrics(host->ud, &m);
        return m.width;
    }
    case HANDHELD_CMD_MODULE_READY:
        return handheld_module_ready(host, p0);
    case HANDHELD_CMD_NFC_SCAN:
        return host->nfc ? host->nfc->scan_start(host->ud) : -1;
    case HANDHELD_CMD_NFC_READ: {
        char buf[32];
        if (!host->nfc) return -1;
        return host->nfc->read(host->ud, buf, (int)sizeof buf);
    }
    case HANDHELD_CMD_IR_SEND:
        return host->ir ? host->ir->send_raw(host->ud, NULL, p0) : -1;
    case HANDHELD_CMD_GPIO_WRITE:
        if (!host->gpio) return -1;
        host->gpio->write(host->ud, p0, p1);
        return 0;
    case HANDHELD_CMD_GPIO_READ:
        return host->gpio ? host->gpio->read(host->ud, p0) : -1;
    case HANDHELD_CMD_USB_HID_TAP:
        return host->usb ? host->usb->hid_tap(host->ud, p0) : -1;
    case HANDHELD_CMD_RADIO_HTTP_GET: {
        char buf[32];
        if (!host->radio) return -1;
        return host->radio->http_get(host->ud, text ? text : "", buf, (int)sizeof buf);
    }
    default:
        return -1;
    }
}
