#ifndef HANDHELD_HOST_IMPL_H
#define HANDHELD_HOST_IMPL_H

#include "handheld_host.h"

#define HANDHELD_FB_W 320
#define HANDHELD_FB_H 240

#define HANDHELD_HAS_SENSORS (1u << 0)
#define HANDHELD_HAS_NFC (1u << 1)
#define HANDHELD_HAS_IR (1u << 2)
#define HANDHELD_HAS_USB (1u << 3)
#define HANDHELD_HAS_RADIO (1u << 4)
#define HANDHELD_HAS_GPIO (1u << 5)
#define HANDHELD_HAS_HAPTICS (1u << 6)
#define HANDHELD_HAS_FS (1u << 7)

#define HANDHELD_MASK_ALL                                                                  \
    (HANDHELD_HAS_SENSORS | HANDHELD_HAS_NFC | HANDHELD_HAS_IR | HANDHELD_HAS_USB |       \
     HANDHELD_HAS_RADIO | HANDHELD_HAS_GPIO | HANDHELD_HAS_HAPTICS | HANDHELD_HAS_FS)

typedef struct HandheldProfile {
    int16_t width;
    int16_t height;
    uint8_t color_depth;
} HandheldProfile;

typedef struct HandheldUd {
    HandheldProfile profile;
    uint16_t fb[HANDHELD_FB_W * HANDHELD_FB_H];
    int present_count;
    int buttons[8];
    int touch_x, touch_y, touch_down;
    char kv_key[16][32];
    char kv_val[16][64];
    int kv_n;
    int exit_req;
    int nfc_scanning;
    int ir_pulses;
    int usb_hid;
    int gpio_value[8];
    int vibrate_ms;
    int battery_pct;
    char last_text[64];
    char last_log[96];
    int last_cmd;
} HandheldUd;

void handheld_host_init(HandheldHost *host, HandheldUd *ud, const HandheldProfile *profile,
                        unsigned module_mask);
const HandheldProfile *handheld_profile_meowkit(void);
uint16_t handheld_fb_at(const HandheldUd *ud, int x, int y);

#endif
