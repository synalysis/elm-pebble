#include "handheld_host.h"
#include "elmc_worker.h"

/* Wraps the Elm worker as the symbol the MeowKit loader and a Flipper FAP call.
 * Draw ids stay on the graphics path. Everything else is a host command.
 */
static const HandheldHost *g_host;
static ElmcWorkerState g_state;

static int is_draw(int32_t kind) {
    switch (kind) {
    case HANDHELD_DRAW_CLEAR:
    case HANDHELD_DRAW_PIXEL:
    case HANDHELD_DRAW_LINE:
    case HANDHELD_DRAW_RECT:
    case HANDHELD_DRAW_FILL_RECT:
    case HANDHELD_DRAW_CIRCLE:
    case HANDHELD_DRAW_FILL_CIRCLE:
    case HANDHELD_DRAW_TEXT:
        return 1;
    default:
        return 0;
    }
}

static void release_all(ElmcValue **values, int count);

static ElmcValue *new_int(elmc_int_t value) {
    ElmcValue *out = NULL;
    if (elmc_new_int(&out, value) != RC_SUCCESS) return NULL;
    return out;
}

static ElmcValue *new_bool(int value) {
    ElmcValue *out = NULL;
    if (elmc_new_bool(&out, value ? 1 : 0) != RC_SUCCESS) return NULL;
    return out;
}

static void dispatch_applied(elmc_int_t tag, ElmcValue *payload);

/* Handheld.Display.Metrics is declared width, height, colorDepth. */
static ElmcValue *metrics_record(void) {
    HandheldDisplayMetrics metrics = {320, 240, 16};
    ElmcValue *values[3];
    ElmcValue *record = NULL;
    const char *names[] = {"width", "height", "colorDepth"};
    if (g_host && g_host->graphics && g_host->graphics->metrics) {
        g_host->graphics->metrics(g_host->ud, &metrics);
    }
    values[0] = new_int(metrics.width);
    values[1] = new_int(metrics.height);
    values[2] = new_int(metrics.color_depth > 0 ? metrics.color_depth : 16);
    if (!values[0] || !values[1] || !values[2] ||
        elmc_record_new(&record, 3, names, values) != RC_SUCCESS) {
        release_all(values, 3);
        return NULL;
    }
    release_all(values, 3);
    return record;
}

/* Constructor tags sit in p0, or in p1 when the command also takes a module or pin.
 * Gpio.Level is Low = 1, High = 2. The host reports 0 and 1. */
static void reply_cmd(const ElmcWorkerDispatchCmd *cmd, int rc) {
    switch ((int32_t)cmd->kind) {
    case HANDHELD_CMD_BATTERY:
        if (rc < 0) return;
        dispatch_applied((elmc_int_t)cmd->p0, new_int(rc));
        break;
    case HANDHELD_CMD_DISPLAY_METRICS:
        dispatch_applied((elmc_int_t)cmd->p0, metrics_record());
        break;
    case HANDHELD_CMD_MODULE_READY:
        dispatch_applied((elmc_int_t)cmd->p1, new_bool(rc ? 1 : 0));
        break;
    case HANDHELD_CMD_GPIO_READ:
        if (rc < 0) return;
        dispatch_applied((elmc_int_t)cmd->p1, new_int(rc ? 2 : 1));
        break;
    default:
        break;
    }
}

static int g_drain_depth;

static void drain_cmds(void) {
    ElmcWorkerDispatchCmd cmds[8];
    int results[8];
    int count;
    int i;
    if (g_drain_depth >= 8) return;
    count = elmc_worker_last_dispatch_cmd_count(&g_state);
    if (count <= 0) return;
    if (count > 8) count = 8;
    g_drain_depth++;
    for (i = 0; i < count; i++) {
        int32_t params[6];
        results[i] = 0;
        if (elmc_worker_last_dispatch_cmd_at(&g_state, i, &cmds[i]) != 0) {
            cmds[i].kind = -1;
            continue;
        }
        params[0] = (int32_t)cmds[i].p0;
        params[1] = (int32_t)cmds[i].p1;
        params[2] = (int32_t)cmds[i].p2;
        params[3] = (int32_t)cmds[i].p3;
        params[4] = (int32_t)cmds[i].p4;
        params[5] = (int32_t)cmds[i].p5;
        if (is_draw((int32_t)cmds[i].kind)) {
            handheld_apply_draw(g_host, (int32_t)cmds[i].kind, params, cmds[i].text);
        } else {
            results[i] = handheld_apply_cmd(g_host, (int32_t)cmds[i].kind, params, cmds[i].text);
        }
    }
    for (i = 0; i < count; i++) {
        if (cmds[i].kind < 0 || is_draw((int32_t)cmds[i].kind)) continue;
        reply_cmd(&cmds[i], results[i]);
    }
    g_drain_depth--;
}

static void release_all(ElmcValue **values, int count) {
    int i;
    for (i = 0; i < count; i++) elmc_release(values[i]);
}

/* LaunchScreen is declared width, height, colorDepth. Device tags follow
 * declaration order: MeowKit = 1, FlipperZero = 2. */
static ElmcValue *launch_context(const HandheldHost *host) {
    HandheldDisplayMetrics metrics = {320, 240, 16};
    int device_tag = 1;
    int touch = 0;
    ElmcValue *depth = NULL;
    ElmcValue *height = NULL;
    ElmcValue *width = NULL;
    ElmcValue *screen_values[3];
    ElmcValue *screen = NULL;
    ElmcValue *device_value = NULL;
    ElmcValue *touch_value = NULL;
    ElmcValue *context_values[3];
    ElmcValue *context = NULL;
    const char *screen_names[] = {"width", "height", "colorDepth"};
    const char *context_names[] = {"device", "screen", "touch"};

    if (host && host->graphics && host->graphics->metrics) {
        host->graphics->metrics(host->ud, &metrics);
    }
    if (metrics.width == 128 && metrics.height == 64 && metrics.color_depth <= 1) {
        device_tag = 2;
    }
    touch = host && host->input && host->input->touch;

    depth = new_int(metrics.color_depth > 0 ? metrics.color_depth : 16);
    height = new_int(metrics.height);
    width = new_int(metrics.width);
    screen_values[0] = width;
    screen_values[1] = height;
    screen_values[2] = depth;
    if (!depth || !height || !width ||
        elmc_record_new(&screen, 3, screen_names, screen_values) != RC_SUCCESS) {
        release_all(screen_values, 3);
        return NULL;
    }
    release_all(screen_values, 3);

    device_value = new_int(device_tag);
    touch_value = new_bool(touch);
    context_values[0] = device_value;
    context_values[1] = screen;
    context_values[2] = touch_value;
    if (!device_value || !touch_value ||
        elmc_record_new(&context, 3, context_names, context_values) != RC_SUCCESS) {
        elmc_release(screen);
        elmc_release(device_value);
        elmc_release(touch_value);
        return NULL;
    }
    elmc_release(screen);
    elmc_release(device_value);
    elmc_release(touch_value);
    return context;
}

static void render_view(void);

int meow_app_start(const HandheldHost *host) {
    ElmcValue *flags;
    g_host = host;
    flags = launch_context(host);
    if (elmc_worker_init(&g_state, flags) != 0) {
        elmc_release(flags);
        return 1;
    }
    elmc_release(flags);
    drain_cmds();
    render_view();
    return 0;
}

static void render_view(void) {
    if (elmc_worker_capture_view(&g_state) == 0) drain_cmds();
}

void meow_app_stop(void) { elmc_worker_deinit(&g_state); }

static void dispatch_msg(ElmcValue *msg) {
    if (!msg) return;
    if (elmc_worker_dispatch(&g_state, msg) == 0) {
        drain_cmds();
        render_view();
    }
    elmc_release(msg);
}

/* Unary Elm constructors are (tag, payload). Nullary ones are the tag int. */
static void dispatch_applied(elmc_int_t tag, ElmcValue *payload) {
    ElmcValue *tag_value = NULL;
    ElmcValue *msg = NULL;
    if (tag <= 0 || !payload) {
        if (payload) elmc_release(payload);
        return;
    }
    if (elmc_new_int(&tag_value, tag) != RC_SUCCESS) {
        elmc_release(payload);
        return;
    }
    if (elmc_tuple2_take(&msg, tag_value, payload) != RC_SUCCESS) {
        elmc_release(tag_value);
        elmc_release(payload);
        return;
    }
    dispatch_msg(msg);
}

static void dispatch_nullary(elmc_int_t tag) {
    ElmcValue *msg = NULL;
    if (tag <= 0) return;
    if (elmc_new_int(&msg, tag) != RC_SUCCESS) return;
    dispatch_msg(msg);
}

static ElmcValue *point_record(int x, int y) {
    ElmcValue *x_value = new_int(x);
    ElmcValue *y_value = new_int(y);
    ElmcValue *values[2];
    ElmcValue *point = NULL;
    const char *names[] = {"x", "y"};
    values[0] = x_value;
    values[1] = y_value;
    if (!x_value || !y_value || elmc_record_new(&point, 2, names, values) != RC_SUCCESS) {
        release_all(values, 2);
        return NULL;
    }
    release_all(values, 2);
    return point;
}

static void on_button(const int32_t *args, int nargs) {
    int id;
    int pressed;
    if (!args || nargs < 1) return;
    id = args[0];
    pressed = nargs < 2 || args[1] != 0;
    if (!pressed || id <= 0) return;
    /* Button tags follow Handheld.Input.Button declaration order, which matches
     * HANDHELD_BTN_* including Back = 8. */
    dispatch_applied(g_state.handheld_presses_tag, new_int(id));
    dispatch_nullary(elmc_worker_button_raw_msg_tag(&g_state, id, 1));
}

static void on_touch(const int32_t *args, int nargs) {
    int down;
    if (!args || nargs < 2) return;
    down = nargs < 3 || args[2] != 0;
    if (!down) return;
    dispatch_applied(g_state.handheld_taps_tag, point_record(args[0], args[1]));
}

static void on_nfc(void) {
    char text[48];
    ElmcValue *value = NULL;
    if (g_state.handheld_nfc_tag <= 0) return;
    text[0] = '\0';
    if (g_host && g_host->nfc && g_host->nfc->read) {
        if (g_host->nfc->read(g_host->ud, text, (int)sizeof text) < 0) text[0] = '\0';
    }
    if (elmc_new_string(&value, text) != RC_SUCCESS) return;
    dispatch_applied(g_state.handheld_nfc_tag, value);
}

void meow_app_event(int kind, const int32_t *args, int nargs) {
    switch (kind) {
    case HANDHELD_EVT_BUTTON:
        on_button(args, nargs);
        break;
    case HANDHELD_EVT_TOUCH:
        on_touch(args, nargs);
        break;
    case HANDHELD_EVT_NFC:
        on_nfc();
        break;
    default:
        (void)args;
        (void)nargs;
        break;
    }
}

void meow_app_frame(int dt_ms) {
    (void)dt_ms;
    render_view();
}
