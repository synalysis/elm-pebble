#include "handheld_host_impl.h"

#include <stdio.h>
#include <string.h>

static const HandheldProfile k_meowkit = {320, 240, 16};

const HandheldProfile *handheld_profile_meowkit(void) { return &k_meowkit; }

uint16_t handheld_fb_at(const HandheldUd *ud, int x, int y) {
    if (!ud || x < 0 || y < 0 || x >= ud->profile.width || y >= ud->profile.height) return 0;
    return ud->fb[y * HANDHELD_FB_W + x];
}

static uint16_t encode_color(const HandheldUd *ud, int32_t color) {
    if (ud->profile.color_depth <= 1) return color ? 1 : 0;
    return (uint16_t)color;
}

static void put_px(HandheldUd *ud, int x, int y, uint16_t color) {
    if (x < 0 || y < 0 || x >= ud->profile.width || y >= ud->profile.height) return;
    if (x >= HANDHELD_FB_W || y >= HANDHELD_FB_H) return;
    ud->fb[y * HANDHELD_FB_W + x] = color;
}

static void h_log(void *ud, int level, const char *msg) {
    HandheldUd *u = ud;
    (void)level;
    snprintf(u->last_log, sizeof u->last_log, "%s", msg ? msg : "");
}

static int h_kv_get(void *ud, const char *key, char *buf, int cap) {
    HandheldUd *u = ud;
    int i;
    if (!key || !buf || cap <= 0) return -1;
    for (i = 0; i < u->kv_n; i++) {
        if (strcmp(u->kv_key[i], key) == 0) {
            snprintf(buf, (size_t)cap, "%s", u->kv_val[i]);
            return (int)strlen(buf);
        }
    }
    return -1;
}

static int h_kv_set(void *ud, const char *key, const char *val) {
    HandheldUd *u = ud;
    int i;
    if (!key || !val) return -1;
    for (i = 0; i < u->kv_n; i++) {
        if (strcmp(u->kv_key[i], key) == 0) {
            snprintf(u->kv_val[i], sizeof u->kv_val[i], "%s", val);
            return 0;
        }
    }
    if (u->kv_n >= 16) return -1;
    snprintf(u->kv_key[u->kv_n], sizeof u->kv_key[0], "%s", key);
    snprintf(u->kv_val[u->kv_n], sizeof u->kv_val[0], "%s", val);
    u->kv_n++;
    return 0;
}

static int h_timer(void *ud, int ms, int token) {
    (void)ud;
    (void)ms;
    (void)token;
    return 0;
}

static uint32_t h_random(void *ud) {
    (void)ud;
    return 0x4d656f77u;
}

static void h_exit(void *ud) { ((HandheldUd *)ud)->exit_req = 1; }

static void h_metrics(void *ud, HandheldDisplayMetrics *out) {
    HandheldUd *u = ud;
    out->width = u->profile.width;
    out->height = u->profile.height;
    out->color_depth = u->profile.color_depth;
}

static void h_draw(void *ud, int op, const int32_t *args, int nargs, const char *text) {
    HandheldUd *u = ud;
    uint16_t color;
    int x, y, w, h, i, j;
    if (text) snprintf(u->last_text, sizeof u->last_text, "%s", text);
    if (op == HANDHELD_DRAW_CLEAR) {
        color = encode_color(u, nargs > 0 ? args[0] : 0);
        for (y = 0; y < u->profile.height; y++)
            for (x = 0; x < u->profile.width; x++) put_px(u, x, y, color);
        return;
    }
    if (op == HANDHELD_DRAW_FILL_RECT && nargs >= 5) {
        x = args[0];
        y = args[1];
        w = args[2];
        h = args[3];
        color = encode_color(u, args[4]);
        for (j = 0; j < h; j++)
            for (i = 0; i < w; i++) put_px(u, x + i, y + j, color);
        return;
    }
    if (op == HANDHELD_DRAW_PIXEL && nargs >= 3) {
        put_px(u, args[0], args[1], encode_color(u, args[2]));
    }
}

static void h_present(void *ud) { ((HandheldUd *)ud)->present_count++; }

static int h_button(void *ud, int id) {
    HandheldUd *u = ud;
    if (id < 0 || id >= 8) return 0;
    return u->buttons[id];
}

static int h_touch(void *ud, int *x, int *y, int *down) {
    HandheldUd *u = ud;
    if (x) *x = u->touch_x;
    if (y) *y = u->touch_y;
    if (down) *down = u->touch_down;
    return 0;
}

static void h_imu(void *ud, int32_t out_mg[3]) {
    (void)ud;
    out_mg[0] = 0;
    out_mg[1] = 0;
    out_mg[2] = 1000;
}

static int h_battery(void *ud) { return ((HandheldUd *)ud)->battery_pct; }

static int64_t h_rtc(void *ud) {
    (void)ud;
    return 1700000000;
}

static void h_vibrate(void *ud, int ms) { ((HandheldUd *)ud)->vibrate_ms = ms; }

static void h_led(void *ud, int r, int g, int b) {
    (void)ud;
    (void)r;
    (void)g;
    (void)b;
}

static int path_ok(const char *rel) {
    if (!rel || rel[0] == '/' || strstr(rel, "..")) return 0;
    return 1;
}

static int h_fs_read(void *ud, const char *rel, char *buf, int cap) {
    (void)ud;
    if (!path_ok(rel) || !buf || cap <= 0) return -1;
    snprintf(buf, (size_t)cap, "%s", rel);
    return (int)strlen(buf);
}

static int h_fs_write(void *ud, const char *rel, const char *data, int len) {
    (void)ud;
    (void)data;
    (void)len;
    return path_ok(rel) ? 0 : -1;
}

static int h_nfc_scan(void *ud) {
    ((HandheldUd *)ud)->nfc_scanning = 1;
    return 0;
}

static void h_nfc_stop(void *ud) { ((HandheldUd *)ud)->nfc_scanning = 0; }

static int h_nfc_read(void *ud, char *buf, int cap) {
    (void)ud;
    if (!buf || cap < 5) return -1;
    snprintf(buf, (size_t)cap, "nfc");
    return 3;
}

static int h_ir_send(void *ud, const uint16_t *pulses, int count) {
    (void)pulses;
    ((HandheldUd *)ud)->ir_pulses += count;
    return 0;
}

static int h_ir_recv(void *ud) {
    (void)ud;
    return 0;
}

static int h_usb_begin(void *ud) {
    ((HandheldUd *)ud)->usb_hid = 1;
    return 0;
}

static void h_usb_end(void *ud) { ((HandheldUd *)ud)->usb_hid = 0; }

static int h_usb_tap(void *ud, int keycode) {
    (void)keycode;
    return ((HandheldUd *)ud)->usb_hid ? 0 : -1;
}

static int h_wifi(void *ud) {
    (void)ud;
    return 1;
}

static int h_http(void *ud, const char *url, char *buf, int cap) {
    (void)ud;
    if (!url || !buf || cap <= 0) return -1;
    snprintf(buf, (size_t)cap, "ok");
    return 2;
}

static void h_gpio_mode(void *ud, int pin, int mode) {
    (void)ud;
    (void)pin;
    (void)mode;
}

static void h_gpio_write(void *ud, int pin, int value) {
    if (pin < 0 || pin >= 8) return;
    ((HandheldUd *)ud)->gpio_value[pin] = value;
}

static int h_gpio_read(void *ud, int pin) {
    if (pin < 0 || pin >= 8) return 0;
    return ((HandheldUd *)ud)->gpio_value[pin];
}

static const HandheldHostCoreV1 k_core = {
    1, 0, h_log, h_kv_get, h_kv_set, h_timer, h_random, h_exit};
static const HandheldHostGraphicsV1 k_gfx = {1, 0, h_metrics, h_draw, h_present};
static const HandheldHostInputV1 k_input = {1, 0, h_button, h_touch};
static const HandheldHostSensorsV1 k_sensors = {1, 0, h_imu, h_battery, h_rtc};
static const HandheldHostHapticsV1 k_haptics = {1, 0, h_vibrate, h_led};
static const HandheldHostFsV1 k_fs = {1, 0, h_fs_read, h_fs_write};
static const HandheldHostNfcV1 k_nfc = {1, 0, h_nfc_scan, h_nfc_stop, h_nfc_read};
static const HandheldHostIrV1 k_ir = {1, 0, h_ir_send, h_ir_recv};
static const HandheldHostUsbV1 k_usb = {1, 0, h_usb_begin, h_usb_end, h_usb_tap};
static const HandheldHostRadioV1 k_radio = {1, 0, h_wifi, h_http};
static const HandheldHostGpioV1 k_gpio = {1, 0, h_gpio_mode, h_gpio_write, h_gpio_read};

void handheld_host_init(HandheldHost *host, HandheldUd *ud, const HandheldProfile *profile,
                        unsigned module_mask) {
    memset(host, 0, sizeof *host);
    memset(ud, 0, sizeof *ud);
    ud->profile = *profile;
    ud->battery_pct = 80;
    host->abi_major = HANDHELD_ABI_MAJOR;
    host->abi_minor = HANDHELD_ABI_MINOR;
    host->ud = ud;
    host->core = &k_core;
    host->graphics = &k_gfx;
    host->input = &k_input;
    host->haptics = (module_mask & HANDHELD_HAS_HAPTICS) ? &k_haptics : NULL;
    host->fs = (module_mask & HANDHELD_HAS_FS) ? &k_fs : NULL;
    host->sensors = (module_mask & HANDHELD_HAS_SENSORS) ? &k_sensors : NULL;
    host->nfc = (module_mask & HANDHELD_HAS_NFC) ? &k_nfc : NULL;
    host->ir = (module_mask & HANDHELD_HAS_IR) ? &k_ir : NULL;
    host->usb = (module_mask & HANDHELD_HAS_USB) ? &k_usb : NULL;
    host->radio = (module_mask & HANDHELD_HAS_RADIO) ? &k_radio : NULL;
    host->gpio = (module_mask & HANDHELD_HAS_GPIO) ? &k_gpio : NULL;
}

const void *handheld_module(const HandheldHost *host, const char *name) {
    if (!host || !name) return NULL;
    if (strcmp(name, "core") == 0) return host->core;
    if (strcmp(name, "graphics") == 0) return host->graphics;
    if (strcmp(name, "input") == 0) return host->input;
    if (strcmp(name, "sensors") == 0) return host->sensors;
    if (strcmp(name, "haptics") == 0) return host->haptics;
    if (strcmp(name, "fs") == 0) return host->fs;
    if (strcmp(name, "nfc") == 0) return host->nfc;
    if (strcmp(name, "ir") == 0) return host->ir;
    if (strcmp(name, "usb") == 0) return host->usb;
    if (strcmp(name, "radio") == 0) return host->radio;
    if (strcmp(name, "gpio") == 0) return host->gpio;
    return NULL;
}

