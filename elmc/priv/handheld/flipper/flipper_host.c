#include "flipper_host.h"
#include "handheld_host.h"

#include <stdlib.h>
#include <string.h>

#include <furi.h>
#include <furi_hal_random.h>
#include <gui/gui.h>
#include <gui/view_port.h>
#include <input/input.h>

#define FB_W 128
#define FB_H 64
#define TEXT_SLOTS 4

typedef struct {
    int16_t x;
    int16_t y;
    char text[32];
} Label;

typedef struct FlipperApp {
    Gui *gui;
    ViewPort *viewport;
    FuriMessageQueue *queue;
    FuriMutex *mutex;
    uint8_t fb[FB_W * FB_H];
    Label labels[TEXT_SLOTS];
    int label_n;
    int buttons[8];
    volatile int exit_req;
    HandheldHost host;
} FlipperApp;

static int clamp_ink(int32_t color) { return color != 0; }

static void put_px(FlipperApp *app, int x, int y, int ink) {
    if (x < 0 || y < 0 || x >= FB_W || y >= FB_H) return;
    app->fb[y * FB_W + x] = ink ? 1 : 0;
}

static void fill_rect(FlipperApp *app, int x, int y, int w, int h, int ink) {
    int x1, y1;
    if (w < 0) {
        x += w;
        w = -w;
    }
    if (h < 0) {
        y += h;
        h = -h;
    }
    for (y1 = y; y1 < y + h; y1++) {
        for (x1 = x; x1 < x + w; x1++) put_px(app, x1, y1, ink);
    }
}

static void draw_line(FlipperApp *app, int x0, int y0, int x1, int y1, int ink) {
    int dx = x1 > x0 ? x1 - x0 : x0 - x1;
    int sx = x0 < x1 ? 1 : -1;
    int dy = y1 > y0 ? y0 - y1 : y1 - y0;
    int sy = y0 < y1 ? 1 : -1;
    int err = dx + dy;
    for (;;) {
        int e2;
        put_px(app, x0, y0, ink);
        if (x0 == x1 && y0 == y1) break;
        e2 = 2 * err;
        if (e2 >= dy) {
            err += dy;
            x0 += sx;
        }
        if (e2 <= dx) {
            err += dx;
            y0 += sy;
        }
    }
}

static void draw_circle(FlipperApp *app, int cx, int cy, int r, int ink, int fill) {
    int x = r;
    int y = 0;
    int err = 1 - x;
    if (r < 0) return;
    while (x >= y) {
        if (fill) {
            int i;
            for (i = cx - x; i <= cx + x; i++) {
                put_px(app, i, cy + y, ink);
                put_px(app, i, cy - y, ink);
            }
            for (i = cx - y; i <= cx + y; i++) {
                put_px(app, i, cy + x, ink);
                put_px(app, i, cy - x, ink);
            }
        } else {
            put_px(app, cx + x, cy + y, ink);
            put_px(app, cx + y, cy + x, ink);
            put_px(app, cx - y, cy + x, ink);
            put_px(app, cx - x, cy + y, ink);
            put_px(app, cx - x, cy - y, ink);
            put_px(app, cx - y, cy - x, ink);
            put_px(app, cx + y, cy - x, ink);
            put_px(app, cx + x, cy - y, ink);
        }
        y++;
        if (err < 0) {
            err += 2 * y + 1;
        } else {
            x--;
            err += 2 * (y - x) + 1;
        }
    }
}

static void metrics(void *ud, HandheldDisplayMetrics *out) {
    (void)ud;
    out->width = FB_W;
    out->height = FB_H;
    out->color_depth = 1;
}

static void draw(void *ud, int op, const int32_t *args, int nargs, const char *text) {
    FlipperApp *app = ud;
    int32_t a[6] = {0, 0, 0, 0, 0, 0};
    int i;
    int ink;
    if (!app) return;
    for (i = 0; i < nargs && i < 6; i++) a[i] = args ? args[i] : 0;
    ink = clamp_ink(a[4] ? a[4] : a[2]);
    furi_mutex_acquire(app->mutex, FuriWaitForever);
    switch (op) {
    case HANDHELD_DRAW_CLEAR:
        memset(app->fb, clamp_ink(a[0]) ? 1 : 0, sizeof app->fb);
        app->label_n = 0;
        break;
    case HANDHELD_DRAW_PIXEL:
        put_px(app, a[0], a[1], clamp_ink(a[2]));
        break;
    case HANDHELD_DRAW_LINE:
        draw_line(app, a[0], a[1], a[2], a[3], ink);
        break;
    case HANDHELD_DRAW_RECT:
        fill_rect(app, a[0], a[1], a[2], 1, ink);
        fill_rect(app, a[0], a[1] + a[3] - 1, a[2], 1, ink);
        fill_rect(app, a[0], a[1], 1, a[3], ink);
        fill_rect(app, a[0] + a[2] - 1, a[1], 1, a[3], ink);
        break;
    case HANDHELD_DRAW_FILL_RECT:
        fill_rect(app, a[0], a[1], a[2], a[3], clamp_ink(a[4]));
        break;
    case HANDHELD_DRAW_CIRCLE:
        draw_circle(app, a[0], a[1], a[2], clamp_ink(a[3]), 0);
        break;
    case HANDHELD_DRAW_FILL_CIRCLE:
        draw_circle(app, a[0], a[1], a[2], clamp_ink(a[3]), 1);
        break;
    case HANDHELD_DRAW_TEXT:
        if (text && app->label_n < TEXT_SLOTS) {
            Label *label = &app->labels[app->label_n++];
            label->x = (int16_t)a[0];
            label->y = (int16_t)a[1];
            snprintf(label->text, sizeof label->text, "%s", text);
        }
        break;
    default:
        break;
    }
    furi_mutex_release(app->mutex);
}

static void present(void *ud) {
    FlipperApp *app = ud;
    if (app && app->viewport) view_port_update(app->viewport);
}

static int button(void *ud, int id) {
    FlipperApp *app = ud;
    if (!app || id < 1 || id > 7) return 0;
    return app->buttons[id];
}

static int touch(void *ud, int *x, int *y, int *down) {
    (void)ud;
    if (x) *x = 0;
    if (y) *y = 0;
    if (down) *down = 0;
    return 0;
}

static void log_msg(void *ud, int level, const char *msg) {
    (void)ud;
    (void)level;
    if (msg) FURI_LOG_I("elm", "%s", msg);
}

static int kv_unused(void *ud, const char *key, char *buf, int cap) {
    (void)ud;
    (void)key;
    (void)buf;
    (void)cap;
    return -1;
}

static int kv_set_unused(void *ud, const char *key, const char *val) {
    (void)ud;
    (void)key;
    (void)val;
    return -1;
}

static int timer_unused(void *ud, int ms, int token) {
    (void)ud;
    (void)ms;
    (void)token;
    return -1;
}

static uint32_t rnd(void *ud) {
    (void)ud;
    return furi_hal_random_get();
}

static void request_exit(void *ud) {
    FlipperApp *app = ud;
    if (app) app->exit_req = 1;
}

static const HandheldHostCoreV1 k_core = {
    1, 1, log_msg, kv_unused, kv_set_unused, timer_unused, rnd, request_exit};
static const HandheldHostGraphicsV1 k_graphics = {1, 1, metrics, draw, present};
static const HandheldHostInputV1 k_input = {1, 1, button, touch};

static void bind_host(FlipperApp *app) {
    memset(&app->host, 0, sizeof app->host);
    app->host.abi_major = HANDHELD_ABI_MAJOR;
    app->host.abi_minor = HANDHELD_ABI_MINOR;
    app->host.ud = app;
    app->host.core = &k_core;
    app->host.graphics = &k_graphics;
    app->host.input = &k_input;
}

static void blit(Canvas *canvas, const uint8_t *fb) {
    int y;
    canvas_clear(canvas);
    canvas_set_color(canvas, ColorBlack);
    for (y = 0; y < FB_H; y++) {
        int x = 0;
        const uint8_t *row = fb + y * FB_W;
        while (x < FB_W) {
            int start;
            while (x < FB_W && !row[x]) x++;
            start = x;
            while (x < FB_W && row[x]) x++;
            if (x > start) canvas_draw_box(canvas, start, y, (size_t)(x - start), 1);
        }
    }
}

static void draw_callback(Canvas *canvas, void *ctx) {
    FlipperApp *app = ctx;
    Label labels[TEXT_SLOTS];
    int label_n;
    int i;
    /* The GUI thread stack is a few kilobytes. A 128×64 copy does not fit. */
    furi_mutex_acquire(app->mutex, FuriWaitForever);
    blit(canvas, app->fb);
    label_n = app->label_n;
    memcpy(labels, app->labels, sizeof labels);
    furi_mutex_release(app->mutex);
    canvas_set_font(canvas, FontSecondary);
    canvas_set_color(canvas, ColorBlack);
    for (i = 0; i < label_n; i++) {
        /* Elm gives the top left. Flipper anchors a string on its baseline. */
        canvas_draw_str_aligned(
            canvas, labels[i].x, labels[i].y, AlignLeft, AlignTop, labels[i].text);
    }
}

static int button_id(InputKey key) {
    switch (key) {
    case InputKeyUp:
        return HANDHELD_BTN_UP;
    case InputKeyDown:
        return HANDHELD_BTN_DOWN;
    case InputKeyLeft:
        return HANDHELD_BTN_LEFT;
    case InputKeyRight:
        return HANDHELD_BTN_RIGHT;
    case InputKeyOk:
        return HANDHELD_BTN_OK;
    case InputKeyBack:
        return HANDHELD_BTN_BACK;
    default:
        return 0;
    }
}

static void input_callback(InputEvent *event, void *ctx) {
    FlipperApp *app = ctx;
    furi_message_queue_put(app->queue, event, 0);
}

static void apply_input(FlipperApp *app, const InputEvent *event) {
    int id = button_id(event->key);
    int32_t args[2];
    if (event->key == InputKeyBack && event->type == InputTypeLong) {
        app->exit_req = 1;
        return;
    }
    if (!id) return;
    if (event->type == InputTypePress || event->type == InputTypeShort) {
        app->buttons[id] = 1;
    } else if (event->type == InputTypeRelease) {
        app->buttons[id] = 0;
    } else {
        return;
    }
    args[0] = id;
    args[1] = app->buttons[id];
    meow_app_event(HANDHELD_EVT_BUTTON, args, 2);
}

int32_t flipper_app_main(void *arg) {
    FlipperApp *app = malloc(sizeof(FlipperApp));
    InputEvent event;
    (void)arg;
    if (!app) return -1;
    memset(app, 0, sizeof *app);
    app->mutex = furi_mutex_alloc(FuriMutexTypeNormal);
    app->queue = furi_message_queue_alloc(8, sizeof(InputEvent));
    app->viewport = view_port_alloc();
    bind_host(app);
    view_port_draw_callback_set(app->viewport, draw_callback, app);
    view_port_input_callback_set(app->viewport, input_callback, app);
    app->gui = furi_record_open(RECORD_GUI);
    gui_add_view_port(app->gui, app->viewport, GuiLayerFullscreen);

    if (meow_app_start(&app->host) != 0) app->exit_req = 1;
    view_port_update(app->viewport);

    while (!app->exit_req) {
        FuriStatus status = furi_message_queue_get(app->queue, &event, furi_ms_to_ticks(40));
        if (status == FuriStatusOk) apply_input(app, &event);
        meow_app_frame(40);
        view_port_update(app->viewport);
    }

    meow_app_stop();
    gui_remove_view_port(app->gui, app->viewport);
    furi_record_close(RECORD_GUI);
    view_port_free(app->viewport);
    furi_message_queue_free(app->queue);
    furi_mutex_free(app->mutex);
    free(app);
    return 0;
}
