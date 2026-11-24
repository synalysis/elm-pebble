/**
 * Portable host ABI for Elm apps on MeowKit, Flipper Zero, and later Flipper One.
 *
 * Apps never call LovyanGFX, Mooncake, or the Flipper SDK. They call this table.
 * MeowKit injects it from the SD loader. Flipper fills it inside a normal FAP
 * (no custom loader) and calls meow_app_start() directly.
 *
 * Stability:
 *   - Never reuse or renumber an op id inside a module major.
 *   - New calls are appended; bump that module's minor.
 *   - A breaking layout change bumps HANDHELD_ABI_MAJOR and keeps the old major.
 *   - Optional modules are NULL when the device does not implement them.
 *   - Screen size and color depth come from graphics->metrics. Do not hardcode
 *     320x240 or 128x64 in Elm.
 */
#ifndef HANDHELD_HOST_H
#define HANDHELD_HOST_H

#include <stddef.h>
#include <stdint.h>

#define HANDHELD_ABI_MAJOR 1
#define HANDHELD_ABI_MINOR 1

#define HANDHELD_MOD_NFC 1
#define HANDHELD_MOD_IR 2
#define HANDHELD_MOD_GPIO 3
#define HANDHELD_MOD_USB 4
#define HANDHELD_MOD_RADIO 5
#define HANDHELD_MOD_SENSORS 6

/* Draw op ids match the existing elmc draw kinds so a program can replay
 * them on every device. */
#define HANDHELD_DRAW_CLEAR 2
#define HANDHELD_DRAW_PIXEL 3
#define HANDHELD_DRAW_LINE 4
#define HANDHELD_DRAW_RECT 5
#define HANDHELD_DRAW_FILL_RECT 6
#define HANDHELD_DRAW_CIRCLE 7
#define HANDHELD_DRAW_FILL_CIRCLE 8
#define HANDHELD_DRAW_TEXT 29

/* Command ids match elmc Pebble command kinds, then handheld-only ids append. */
#define HANDHELD_CMD_VIBES_CANCEL 13
#define HANDHELD_CMD_VIBES_SHORT 14
#define HANDHELD_CMD_VIBES_LONG 15
#define HANDHELD_CMD_VIBES_DOUBLE 16
#define HANDHELD_CMD_BATTERY 24
#define HANDHELD_CMD_STORAGE_WRITE_INT 2
#define HANDHELD_CMD_STORAGE_READ_INT 3
#define HANDHELD_CMD_DISPLAY_METRICS 62
#define HANDHELD_CMD_MODULE_READY 63
#define HANDHELD_CMD_NFC_SCAN 64
#define HANDHELD_CMD_NFC_READ 65
#define HANDHELD_CMD_IR_SEND 66
#define HANDHELD_CMD_GPIO_WRITE 67
#define HANDHELD_CMD_GPIO_READ 68
#define HANDHELD_CMD_RADIO_HTTP_GET 69
#define HANDHELD_CMD_USB_HID_TAP 70

#define HANDHELD_BTN_A 1
#define HANDHELD_BTN_B 2
#define HANDHELD_BTN_UP 3
#define HANDHELD_BTN_DOWN 4
#define HANDHELD_BTN_LEFT 5
#define HANDHELD_BTN_RIGHT 6
#define HANDHELD_BTN_OK 7
#define HANDHELD_BTN_BACK 8

/* meow_app_event args:
 *   BUTTON  args[0] = button id, args[1] = 1 pressed / 0 released
 *   TOUCH   args[0] = x, args[1] = y, args[2] = 1 down / 0 up
 *   NFC     tag text is read from the NFC module
 * Subscription masks below match the worker fields handheld_*_tag.
 */
/* These fit in a signed 32-bit subscription mask. Bits 27-29 are unused by Pebble. */
#define HANDHELD_SUB_PRESSES 134217728
#define HANDHELD_SUB_TAPS 268435456
#define HANDHELD_SUB_NFC 536870912

#define HANDHELD_EVT_BUTTON 1
#define HANDHELD_EVT_TOUCH 2
#define HANDHELD_EVT_TICK 3
#define HANDHELD_EVT_NFC 4
#define HANDHELD_EVT_IR 5

typedef struct HandheldDisplayMetrics {
    int16_t width;
    int16_t height;
    uint8_t color_depth; /* 1 = mono, 16 = RGB565 */
} HandheldDisplayMetrics;

typedef struct HandheldHostCoreV1 {
    uint16_t major;
    uint16_t minor;
    void (*log)(void *ud, int level, const char *msg);
    int (*kv_get)(void *ud, const char *key, char *buf, int cap);
    int (*kv_set)(void *ud, const char *key, const char *val);
    int (*timer_after)(void *ud, int ms, int token);
    uint32_t (*random)(void *ud);
    void (*request_exit)(void *ud);
} HandheldHostCoreV1;

typedef struct HandheldHostGraphicsV1 {
    uint16_t major;
    uint16_t minor;
    void (*metrics)(void *ud, HandheldDisplayMetrics *out);
    void (*draw)(void *ud, int op, const int32_t *args, int nargs, const char *text);
    void (*present)(void *ud);
} HandheldHostGraphicsV1;

typedef struct HandheldHostInputV1 {
    uint16_t major;
    uint16_t minor;
    int (*button)(void *ud, int id);
    int (*touch)(void *ud, int *x, int *y, int *down);
} HandheldHostInputV1;

typedef struct HandheldHostSensorsV1 {
    uint16_t major;
    uint16_t minor;
    void (*imu)(void *ud, int32_t out_mg[3]);
    int (*battery)(void *ud);
    int64_t (*rtc)(void *ud);
} HandheldHostSensorsV1;

typedef struct HandheldHostHapticsV1 {
    uint16_t major;
    uint16_t minor;
    void (*vibrate)(void *ud, int ms);
    void (*led)(void *ud, int r, int g, int b);
} HandheldHostHapticsV1;

typedef struct HandheldHostFsV1 {
    uint16_t major;
    uint16_t minor;
    int (*read)(void *ud, const char *rel, char *buf, int cap);
    int (*write)(void *ud, const char *rel, const char *data, int len);
} HandheldHostFsV1;

typedef struct HandheldHostNfcV1 {
    uint16_t major;
    uint16_t minor;
    int (*scan_start)(void *ud);
    void (*scan_stop)(void *ud);
    int (*read)(void *ud, char *buf, int cap);
} HandheldHostNfcV1;

typedef struct HandheldHostIrV1 {
    uint16_t major;
    uint16_t minor;
    int (*send_raw)(void *ud, const uint16_t *pulses, int count);
    int (*recv_start)(void *ud);
} HandheldHostIrV1;

typedef struct HandheldHostUsbV1 {
    uint16_t major;
    uint16_t minor;
    int (*hid_begin)(void *ud);
    void (*hid_end)(void *ud);
    int (*hid_tap)(void *ud, int keycode);
} HandheldHostUsbV1;

typedef struct HandheldHostRadioV1 {
    uint16_t major;
    uint16_t minor;
    int (*wifi_status)(void *ud);
    int (*http_get)(void *ud, const char *url, char *buf, int cap);
} HandheldHostRadioV1;

typedef struct HandheldHostGpioV1 {
    uint16_t major;
    uint16_t minor;
    void (*mode)(void *ud, int pin, int mode);
    void (*write)(void *ud, int pin, int value);
    int (*read)(void *ud, int pin);
} HandheldHostGpioV1;

typedef struct HandheldHost {
    uint16_t abi_major;
    uint16_t abi_minor;
    void *ud;
    const HandheldHostCoreV1 *core;
    const HandheldHostGraphicsV1 *graphics;
    const HandheldHostInputV1 *input;
    const HandheldHostSensorsV1 *sensors;
    const HandheldHostHapticsV1 *haptics;
    const HandheldHostFsV1 *fs;
    const HandheldHostNfcV1 *nfc;
    const HandheldHostIrV1 *ir;
    const HandheldHostUsbV1 *usb;
    const HandheldHostRadioV1 *radio;
    const HandheldHostGpioV1 *gpio;
} HandheldHost;

/* App entry used by the MeowKit loader (dlsym) and by Flipper app_main. */
int meow_app_start(const HandheldHost *host);
void meow_app_stop(void);
void meow_app_event(int kind, const int32_t *args, int nargs);
void meow_app_frame(int dt_ms);

int handheld_apply_cmd(const HandheldHost *host, int32_t kind, const int32_t *params,
                       const char *text);
int handheld_apply_draw(const HandheldHost *host, int32_t kind, const int32_t *params,
                        const char *text);

const void *handheld_module(const HandheldHost *host, const char *name);

/* Inline so a Flipper FAP can link the shim without the desktop host. */
static inline int handheld_module_ready(const HandheldHost *host, int module_id) {
    if (!host) return 0;
    switch (module_id) {
    case HANDHELD_MOD_NFC: return host->nfc ? 1 : 0;
    case HANDHELD_MOD_IR: return host->ir ? 1 : 0;
    case HANDHELD_MOD_GPIO: return host->gpio ? 1 : 0;
    case HANDHELD_MOD_USB: return host->usb ? 1 : 0;
    case HANDHELD_MOD_RADIO: return host->radio ? 1 : 0;
    case HANDHELD_MOD_SENSORS: return host->sensors ? 1 : 0;
    default: return 0;
    }
}

#endif
