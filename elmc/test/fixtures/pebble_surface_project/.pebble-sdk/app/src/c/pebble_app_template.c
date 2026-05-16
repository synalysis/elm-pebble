#include <pebble.h>
#include <stdio.h>
#include <stdbool.h>
#include <stdlib.h>
#include "elmc/c/elmc_pebble.h"
#if ELMC_PEBBLE_FEATURE_CMD_COMPANION_SEND || ELMC_PEBBLE_FEATURE_INBOX_EVENTS
#include "generated/companion_protocol.h"
#endif
#include "generated/resource_ids.h"

#ifndef ELMC_PEBBLE_DEBUG_LOGS
#define ELMC_PEBBLE_DEBUG_LOGS 0
#endif

#if ELMC_PEBBLE_DEBUG_LOGS
#define ELMC_PEBBLE_DEBUG_LOG(level, ...) APP_LOG(level, __VA_ARGS__)
#else
#define ELMC_PEBBLE_DEBUG_LOG(level, ...) do { } while (0)
#endif

#ifndef ELMC_PEBBLE_RUNTIME_LOGS
#define ELMC_PEBBLE_RUNTIME_LOGS 0
#endif

#ifndef ELMC_AGENT_PROBE_INIT_STAGE
#define ELMC_AGENT_PROBE_INIT_STAGE 99
#endif

#ifndef ELMC_AGENT_PROBES
#define ELMC_AGENT_PROBES 0
#endif

// #region agent log
#if ELMC_AGENT_PROBES
#define ELMC_AGENT_PROBE_SESSION_LIMIT 64
static uint32_t s_agent_probe_tags[ELMC_AGENT_PROBE_SESSION_LIMIT];
static int s_agent_probe_session_count = 0;
static bool agent_init_probe_enabled(uint32_t marker) {
  return marker == 0xED993051 ||
         marker == 0xED993052 ||
         marker == 0xED993152 ||
         marker == 0xED993020 ||
         marker == 0xED993040 ||
         (marker >= 0xED993900 && marker <= 0xED993DFF) ||
         (marker >= 0xED993600 && marker <= 0xED9938FF) ||
         (marker >= 0xED994000 && marker <= 0xED9944FF);
}

static void agent_init_probe(uint32_t marker) {
  if (!agent_init_probe_enabled(marker)) {
    return;
  }
  for (int i = 0; i < s_agent_probe_session_count; i++) {
    if (s_agent_probe_tags[i] == marker) {
      return;
    }
  }
  if (s_agent_probe_session_count < ELMC_AGENT_PROBE_SESSION_LIMIT) {
    DataLoggingSessionRef session = data_logging_create(marker, DATA_LOGGING_BYTE_ARRAY, 1, false);
    if (session) {
      s_agent_probe_tags[s_agent_probe_session_count] = marker;
      s_agent_probe_session_count++;
      data_logging_finish(session);
    }
  }
}
#define ELMC_AGENT_INIT_PROBE(marker) agent_init_probe(marker)

static void agent_draw_cmd_probe(int slot, const ElmcPebbleDrawCmd *cmd) {
  if (!cmd || slot < 0 || slot > 3) {
    return;
  }
  uint32_t slot_bits = ((uint32_t)slot & 0x0f) << 4;
  ELMC_AGENT_INIT_PROBE(0xED993600 | slot_bits | ((uint32_t)cmd->kind & 0x0f));
  ELMC_AGENT_INIT_PROBE(0xED994000 | (((uint32_t)slot & 0x0f) << 8) | ((uint32_t)cmd->p0 & 0xff));
  ELMC_AGENT_INIT_PROBE(0xED994100 | (((uint32_t)slot & 0x0f) << 8) | ((uint32_t)cmd->p1 & 0xff));
  ELMC_AGENT_INIT_PROBE(0xED994200 | (((uint32_t)slot & 0x0f) << 8) | ((uint32_t)cmd->p2 & 0xff));
  ELMC_AGENT_INIT_PROBE(0xED994300 | (((uint32_t)slot & 0x0f) << 8) | ((uint32_t)cmd->p3 & 0xff));
  ELMC_AGENT_INIT_PROBE(0xED994400 | (((uint32_t)slot & 0x0f) << 8) | ((uint32_t)cmd->p4 & 0xff));
}

static uint32_t agent_probe_count_byte(int value) {
  if (value < 0) {
    return (uint32_t)(0x80 | ((-value) & 0x7f));
  }
  return (uint32_t)(value > 0x7f ? 0x7f : value);
}
#else
#define ELMC_AGENT_INIT_PROBE(marker) do { (void)(marker); } while (0)
#define agent_draw_cmd_probe(slot, cmd) do { (void)(slot); (void)(cmd); } while (0)
#define agent_probe_count_byte(value) (0)
#endif
// #endregion

#if !ELMC_PEBBLE_RUNTIME_LOGS && !ELMC_PEBBLE_DEBUG_LOGS
static inline void elmc_pebble_log_noop(int level, const char *format, ...) {
  (void)level;
  (void)format;
}
#undef APP_LOG
#define APP_LOG(level, ...) elmc_pebble_log_noop(level, __VA_ARGS__)
#endif

#if defined(ELMC_PEBBLE_TRACE_FUNCTIONS)
#define ELMC_PEBBLE_TRACE_ENTER(name) app_log(APP_LOG_LEVEL_INFO, __FILE_NAME__, __LINE__, "t+%d", __LINE__)
#define ELMC_PEBBLE_TRACE_EXIT(name) app_log(APP_LOG_LEVEL_INFO, __FILE_NAME__, __LINE__, "t-%d", __LINE__)
#define ELMC_PEBBLE_TRACE_MSG(...) app_log(APP_LOG_LEVEL_INFO, __FILE_NAME__, __LINE__, __VA_ARGS__)
#else
#define ELMC_PEBBLE_TRACE_ENTER(name) do { } while (0)
#define ELMC_PEBBLE_TRACE_EXIT(name) do { } while (0)
#define ELMC_PEBBLE_TRACE_MSG(...) do { } while (0)
#endif

#ifndef ELMC_PEBBLE_FEATURE_DRAW_TEXT_INT
#define ELMC_PEBBLE_FEATURE_DRAW_TEXT_INT 1
#endif
#ifndef ELMC_PEBBLE_FEATURE_DRAW_CLEAR
#define ELMC_PEBBLE_FEATURE_DRAW_CLEAR 1
#endif
#ifndef ELMC_PEBBLE_FEATURE_DRAW_PIXEL
#define ELMC_PEBBLE_FEATURE_DRAW_PIXEL 1
#endif
#ifndef ELMC_PEBBLE_FEATURE_DRAW_LINE
#define ELMC_PEBBLE_FEATURE_DRAW_LINE 1
#endif
#ifndef ELMC_PEBBLE_FEATURE_DRAW_RECT
#define ELMC_PEBBLE_FEATURE_DRAW_RECT 1
#endif
#ifndef ELMC_PEBBLE_FEATURE_DRAW_FILL_RECT
#define ELMC_PEBBLE_FEATURE_DRAW_FILL_RECT 1
#endif
#ifndef ELMC_PEBBLE_FEATURE_DRAW_CIRCLE
#define ELMC_PEBBLE_FEATURE_DRAW_CIRCLE 1
#endif
#ifndef ELMC_PEBBLE_FEATURE_DRAW_FILL_CIRCLE
#define ELMC_PEBBLE_FEATURE_DRAW_FILL_CIRCLE 1
#endif
#ifndef ELMC_PEBBLE_FEATURE_DRAW_TEXT_LABEL
#define ELMC_PEBBLE_FEATURE_DRAW_TEXT_LABEL 1
#endif
#ifndef ELMC_PEBBLE_FEATURE_DRAW_CONTEXT
#define ELMC_PEBBLE_FEATURE_DRAW_CONTEXT 1
#endif
#ifndef ELMC_PEBBLE_FEATURE_DRAW_STROKE_WIDTH
#define ELMC_PEBBLE_FEATURE_DRAW_STROKE_WIDTH 1
#endif
#ifndef ELMC_PEBBLE_FEATURE_DRAW_ANTIALIASED
#define ELMC_PEBBLE_FEATURE_DRAW_ANTIALIASED 1
#endif
#ifndef ELMC_PEBBLE_FEATURE_DRAW_STROKE_COLOR
#define ELMC_PEBBLE_FEATURE_DRAW_STROKE_COLOR 1
#endif
#ifndef ELMC_PEBBLE_FEATURE_DRAW_FILL_COLOR
#define ELMC_PEBBLE_FEATURE_DRAW_FILL_COLOR 1
#endif
#ifndef ELMC_PEBBLE_FEATURE_DRAW_TEXT_COLOR
#define ELMC_PEBBLE_FEATURE_DRAW_TEXT_COLOR 1
#endif
#ifndef ELMC_PEBBLE_FEATURE_DRAW_ROUND_RECT
#define ELMC_PEBBLE_FEATURE_DRAW_ROUND_RECT 1
#endif
#ifndef ELMC_PEBBLE_FEATURE_DRAW_ARC
#define ELMC_PEBBLE_FEATURE_DRAW_ARC 1
#endif
#ifndef ELMC_PEBBLE_FEATURE_DRAW_PATH
#define ELMC_PEBBLE_FEATURE_DRAW_PATH 1
#endif
#ifndef ELMC_PEBBLE_FEATURE_DRAW_FILL_RADIAL
#define ELMC_PEBBLE_FEATURE_DRAW_FILL_RADIAL 1
#endif
#ifndef ELMC_PEBBLE_NATIVE_FILL_RADIAL_ENABLED
#define ELMC_PEBBLE_NATIVE_FILL_RADIAL_ENABLED 1
#endif
#ifndef ELMC_PEBBLE_FEATURE_DRAW_COMPOSITING_MODE
#define ELMC_PEBBLE_FEATURE_DRAW_COMPOSITING_MODE 1
#endif
#ifndef ELMC_PEBBLE_FEATURE_DRAW_BITMAP_IN_RECT
#define ELMC_PEBBLE_FEATURE_DRAW_BITMAP_IN_RECT 1
#endif
#ifndef ELMC_PEBBLE_FEATURE_DRAW_ROTATED_BITMAP
#define ELMC_PEBBLE_FEATURE_DRAW_ROTATED_BITMAP 1
#endif
#ifndef ELMC_PEBBLE_FEATURE_DRAW_TEXT
#define ELMC_PEBBLE_FEATURE_DRAW_TEXT 1
#endif

#ifndef ELMC_PEBBLE_APP_MESSAGE_INBOX_SIZE
#define ELMC_PEBBLE_APP_MESSAGE_INBOX_SIZE 128
#endif
#ifndef ELMC_PEBBLE_APP_MESSAGE_OUTBOX_SIZE
#define ELMC_PEBBLE_APP_MESSAGE_OUTBOX_SIZE 64
#endif
#ifndef ELMC_PEBBLE_STARTUP_SERVICE_SUBSCRIPTIONS
#define ELMC_PEBBLE_STARTUP_SERVICE_SUBSCRIPTIONS 1
#endif
#ifndef ELMC_PEBBLE_STARTUP_RENDER
#define ELMC_PEBBLE_STARTUP_RENDER 1
#endif

#ifndef ELMC_PEBBLE_DIRTY_REGION_ENABLED
#if defined(PBL_PLATFORM_APLITE) || defined(PBL_PLATFORM_BASALT) || defined(PBL_PLATFORM_CHALK) || defined(PBL_PLATFORM_DIORITE) || defined(PBL_PLATFORM_FLINT) || defined(PBL_PLATFORM_EMERY) || defined(PBL_PLATFORM_GABBRO)
#define ELMC_PEBBLE_DIRTY_REGION_ENABLED 0
#else
#define ELMC_PEBBLE_DIRTY_REGION_ENABLED 1
#endif
#endif

static Window *s_main_window;
static Layer *s_draw_layer;
static GFont s_font;
static ElmcPebbleApp s_elm_app;
static AppTimer *s_timer = NULL;
#if ELMC_PEBBLE_FEATURE_FRAME_EVENTS
static AppTimer *s_frame_timer = NULL;
static int64_t s_frame_count = 0;
static int64_t s_frame_elapsed_ms = 0;
static uint32_t s_frame_interval_ms = 33;
static bool s_frame_timer_started = false;
#endif
static bool s_logged_first_draw = false;

enum {
  ELMC_DEBUG_STORAGE_KEY_OP = 0x454c4d00,
  ELMC_DEBUG_STORAGE_KEY_KEY = 0x454c4d01,
  ELMC_DEBUG_STORAGE_KEY_TYPE = 0x454c4d02,
  ELMC_DEBUG_STORAGE_KEY_INT_VALUE = 0x454c4d03,
  ELMC_DEBUG_STORAGE_KEY_STRING_VALUE = 0x454c4d04,
};

enum {
  ELMC_DEBUG_STORAGE_OP_WRITE = 1,
  ELMC_DEBUG_STORAGE_OP_DELETE = 2,
};

enum {
  ELMC_DEBUG_STORAGE_TYPE_INT = 1,
  ELMC_DEBUG_STORAGE_TYPE_STRING = 2,
};
static int64_t s_last_render_request_ms = 0;
static int s_render_sequence = 0;
static int s_last_logged_draw_sequence = 0;
#if ELMC_PEBBLE_FEATURE_CMD_BACKLIGHT
static bool s_forced_backlight = false;
#endif
#if ELMC_PEBBLE_FEATURE_CMD_RANDOM_GENERATE
static int32_t s_random_seed = 1722529;
#endif
#if ELMC_PEBBLE_FEATURE_CMD_COMPANION_SEND
static bool s_pending_companion_request = false;
static int s_pending_request_tag = 0;
static int s_pending_request_value = 0;
#endif
// #region agent log
static bool s_agent_after_companion_dispatch = false;
// #endregion
static ElmcPebbleRunMode s_run_mode = ELMC_PEBBLE_MODE_APP;

typedef struct {
  GColor stroke_color;
  GColor fill_color;
  GColor text_color;
  GCompOp compositing_mode;
  uint8_t stroke_width;
  bool antialiased;
} DrawStyleState;

static int64_t monotonic_ms(void) {
  time_t seconds = 0;
  uint16_t milliseconds = 0;
  time_ms(&seconds, &milliseconds);
  return ((int64_t)seconds * 1000) + milliseconds;
}

static void render_model(void);
static void apply_pending_cmd(void);
static void startup_cmd_callback(void *data);
static ElmcValue *build_launch_context(AppLaunchReason launch);
#if ELMC_PEBBLE_FEATURE_CMD_COMPANION_SEND
static bool send_companion_request(int request_tag, int request_value);
static void flush_pending_companion_request(void);
#endif

static GFont system_font_for_height(int64_t requested_height) {
  GFont font = NULL;
  if (requested_height <= 18) font = fonts_get_system_font(FONT_KEY_GOTHIC_18_BOLD);
  if (!font && requested_height <= 28) font = fonts_get_system_font(FONT_KEY_GOTHIC_24_BOLD);
  if (!font && requested_height <= 36) font = fonts_get_system_font(FONT_KEY_GOTHIC_28_BOLD);
  if (!font) font = s_font;
  if (!font) font = fonts_get_system_font(FONT_KEY_GOTHIC_24);
  return font;
}

#if ELMC_PEBBLE_FEATURE_DRAW_TEXT_INT || ELMC_PEBBLE_FEATURE_DRAW_TEXT_LABEL
static GFont font_from_id(int64_t font_id, bool *should_unload) {
  uint32_t resource_id = elm_pebble_font_resource_id(font_id);
  if (resource_id == ELM_PEBBLE_RESOURCE_ID_MISSING) {
    if (should_unload) *should_unload = false;
    return s_font;
  }
  if (should_unload) *should_unload = true;
  return fonts_load_custom_font(resource_get_handle(resource_id));
}
#endif

static GFont font_from_id_for_height(int64_t font_id, int64_t requested_height, bool *should_unload) {
  uint32_t resource_id = elm_pebble_font_resource_id(font_id);

  if (resource_id == ELM_PEBBLE_RESOURCE_ID_MISSING) {
    if (should_unload) *should_unload = false;
    return system_font_for_height(requested_height);
  }

  if (should_unload) *should_unload = true;
  return fonts_load_custom_font(resource_get_handle(resource_id));
}
#if ELMC_PEBBLE_FEATURE_CMD_GET_WATCH_MODEL
static int64_t watch_model_to_elm_tag(WatchInfoModel model);
#endif
#if ELMC_PEBBLE_FEATURE_CMD_GET_WATCH_COLOR
static int64_t watch_color_to_elm_tag(WatchInfoColor color);
#endif

#if ELMC_PEBBLE_FEATURE_CMD_GET_WATCH_MODEL
static int64_t watch_model_to_elm_tag(WatchInfoModel model) {
  (void)model;
  return 0;
}
#endif

#if ELMC_PEBBLE_FEATURE_CMD_GET_WATCH_COLOR
static int64_t watch_color_to_elm_tag(WatchInfoColor color) {
  (void)color;
  return 0;
}
#endif

#if ELMC_PEBBLE_FEATURE_CMD_HEALTH_VALUE || ELMC_PEBBLE_FEATURE_CMD_HEALTH_SUM_TODAY || ELMC_PEBBLE_FEATURE_CMD_HEALTH_SUM || ELMC_PEBBLE_FEATURE_CMD_HEALTH_ACCESSIBLE
#ifdef PBL_HEALTH
static HealthMetric health_metric_from_code(int64_t value) {
  if (value < 0) value = 0;
  if (value > 7) value = 7;
  return (HealthMetric)value;
}
#endif

static time_t health_time_from_seconds(int64_t seconds) {
  if (seconds < 0) return (time_t)0;
  return (time_t)seconds;
}
#endif

#if ELMC_PEBBLE_FEATURE_CMD_TIMER_AFTER_MS
static void timer_cmd_callback(void *data) {
  ELMC_PEBBLE_TRACE_ENTER("timer_cmd_callback");
  (void)data;
  s_timer = NULL;
  if (elmc_pebble_tick(&s_elm_app) == 0) {
    apply_pending_cmd();
    render_model();
  }
  ELMC_PEBBLE_TRACE_EXIT("timer_cmd_callback");
}
#endif

#if ELMC_PEBBLE_FEATURE_FRAME_EVENTS
static void frame_timer_callback(void *data);

static uint32_t frame_interval_from_subscriptions(void) {
  int64_t subscriptions = elmc_pebble_active_subscriptions(&s_elm_app);
  int64_t encoded = (subscriptions >> 16) & 0x7fff;
  if (encoded <= 0) return 33;
  if (encoded > 1000) return 1000;
  return (uint32_t)encoded;
}

static void schedule_frame_timer_if_needed(void) {
  ELMC_PEBBLE_TRACE_ENTER("schedule_frame_timer_if_needed");
  if (s_run_mode != ELMC_PEBBLE_MODE_APP || s_frame_timer) {
    ELMC_PEBBLE_TRACE_EXIT("schedule_frame_timer_if_needed");
    return;
  }
  if ((elmc_pebble_active_subscriptions(&s_elm_app) & ELMC_PEBBLE_SUB_FRAME) == 0) {
    ELMC_PEBBLE_TRACE_EXIT("schedule_frame_timer_if_needed");
    return;
  }
  s_frame_timer = app_timer_register(s_frame_interval_ms, frame_timer_callback, NULL);
  if (!s_frame_timer_started) {
    s_frame_timer_started = true;
    ELMC_PEBBLE_DEBUG_LOG(APP_LOG_LEVEL_INFO, "frame timer scheduled interval_ms=%lu", (unsigned long)s_frame_interval_ms);
  }
  ELMC_PEBBLE_TRACE_EXIT("schedule_frame_timer_if_needed");
}

static void frame_timer_callback(void *data) {
  ELMC_PEBBLE_TRACE_ENTER("frame_timer_callback");
  (void)data;
  s_frame_timer = NULL;
  s_frame_count += 1;
  s_frame_elapsed_ms += s_frame_interval_ms;
  int rc = elmc_pebble_dispatch_frame(&s_elm_app, s_frame_interval_ms, s_frame_elapsed_ms, s_frame_count);
  if (rc == 0) {
    apply_pending_cmd();
    render_model();
  }
  schedule_frame_timer_if_needed();
  ELMC_PEBBLE_TRACE_EXIT("frame_timer_callback");
}
#endif

static void apply_pending_cmd(void) {
  ELMC_PEBBLE_TRACE_ENTER("apply_pending_cmd");
  for (int cmd_guard = 0; cmd_guard < 32; cmd_guard++) {
    ElmcPebbleCmd cmd = {0};
    if (elmc_pebble_take_cmd(&s_elm_app, &cmd) != 0 || cmd.kind == ELMC_PEBBLE_CMD_NONE) {
      ELMC_PEBBLE_DEBUG_LOG(APP_LOG_LEVEL_INFO, "cmd drain complete count=%d", cmd_guard);
      ELMC_PEBBLE_TRACE_EXIT("apply_pending_cmd");
      return;
    }
    ELMC_PEBBLE_TRACE_MSG("trace cmd kind=%lld p0=%lld p1=%lld", (long long)cmd.kind, (long long)cmd.p0, (long long)cmd.p1);
    ELMC_PEBBLE_DEBUG_LOG(APP_LOG_LEVEL_INFO, "cmd drain kind=%lld p0=%lld", (long long)cmd.kind, (long long)cmd.p0);

    switch (cmd.kind) {
#if ELMC_PEBBLE_FEATURE_CMD_TIMER_AFTER_MS
    case ELMC_PEBBLE_CMD_TIMER_AFTER_MS: {
      uint32_t timeout_ms = cmd.p0 > 0 ? (uint32_t)cmd.p0 : 1;
      if (s_timer) {
        if (!app_timer_reschedule(s_timer, timeout_ms)) {
          app_timer_cancel(s_timer);
          s_timer = app_timer_register(timeout_ms, timer_cmd_callback, NULL);
        }
      } else {
        s_timer = app_timer_register(timeout_ms, timer_cmd_callback, NULL);
      }
      APP_LOG(APP_LOG_LEVEL_INFO, "cmd timer_after_ms=%lu", (unsigned long)timeout_ms);
      break;
    }
#endif
#if ELMC_PEBBLE_FEATURE_CMD_STORAGE_WRITE_INT
    case ELMC_PEBBLE_CMD_STORAGE_WRITE_INT: {
      uint32_t key = (uint32_t)cmd.p0;
      int32_t value = (int32_t)cmd.p1;
      status_t status = persist_write_int(key, value);
      APP_LOG(APP_LOG_LEVEL_INFO, "cmd storage_write key=%lu value=%ld status=%ld",
              (unsigned long)key, (long)value, (long)status);
      break;
    }
#endif
#if ELMC_PEBBLE_FEATURE_CMD_STORAGE_READ_INT
    case ELMC_PEBBLE_CMD_STORAGE_READ_INT: {
      uint32_t key = (uint32_t)cmd.p0;
      int64_t target = cmd.p1;
      int32_t value = persist_read_int(key);
      int rc = target > 0 ? elmc_pebble_dispatch_tag_value(&s_elm_app, target, value) : -6;
      APP_LOG(APP_LOG_LEVEL_INFO, "cmd storage_read key=%lu value=%ld rc=%d",
              (unsigned long)key, (long)value, rc);
      break;
    }
#endif
#if ELMC_PEBBLE_FEATURE_CMD_STORAGE_WRITE_STRING
    case ELMC_PEBBLE_CMD_STORAGE_WRITE_STRING: {
      uint32_t key = (uint32_t)cmd.p0;
      status_t status = persist_write_string(key, cmd.text);
      APP_LOG(APP_LOG_LEVEL_INFO, "cmd storage_write_string key=%lu value=%s status=%ld",
              (unsigned long)key, cmd.text, (long)status);
      break;
    }
#endif
#if ELMC_PEBBLE_FEATURE_CMD_STORAGE_READ_STRING
    case ELMC_PEBBLE_CMD_STORAGE_READ_STRING: {
      uint32_t key = (uint32_t)cmd.p0;
      int64_t target = cmd.p1;
      char value[128] = "";
      if (persist_exists(key)) {
        persist_read_string(key, value, sizeof(value));
      }
      int rc = target > 0 ? elmc_pebble_dispatch_tag_string(&s_elm_app, target, value) : -6;
      APP_LOG(APP_LOG_LEVEL_INFO, "cmd storage_read_string key=%lu value=%s rc=%d",
              (unsigned long)key, value, rc);
      break;
    }
#endif
#if ELMC_PEBBLE_FEATURE_CMD_RANDOM_GENERATE
    case ELMC_PEBBLE_CMD_RANDOM_GENERATE: {
      s_random_seed = (int32_t)(((int64_t)s_random_seed * 1103515245 + 12345) & 0x7fffffff);
      if (s_random_seed <= 0) {
        s_random_seed = 1;
      }
      int64_t target = cmd.p0;
      int rc = target > 0
                   ? elmc_pebble_dispatch_tag_value(&s_elm_app, target, s_random_seed)
                   : elmc_pebble_dispatch_random_int(&s_elm_app, s_random_seed);
      ELMC_PEBBLE_DEBUG_LOG(APP_LOG_LEVEL_INFO, "cmd random_generate target=%lld value=%ld rc=%d",
              (long long)target, (long)s_random_seed, rc);
      break;
    }
#endif
#if ELMC_PEBBLE_FEATURE_CMD_STORAGE_DELETE
    case ELMC_PEBBLE_CMD_STORAGE_DELETE: {
      uint32_t key = (uint32_t)cmd.p0;
      status_t status = persist_delete(key);
      APP_LOG(APP_LOG_LEVEL_INFO, "cmd storage_delete key=%lu status=%ld",
              (unsigned long)key, (long)status);
      break;
    }
#endif
#if ELMC_PEBBLE_FEATURE_CMD_COMPANION_SEND
    case ELMC_PEBBLE_CMD_COMPANION_SEND: {
      int request_tag = (int)cmd.p0;
      int request_value = (int)cmd.p1;
      if (!send_companion_request(request_tag, request_value)) {
        s_pending_companion_request = true;
        s_pending_request_tag = request_tag;
        s_pending_request_value = request_value;
      }
      break;
    }
#endif
#if ELMC_PEBBLE_FEATURE_CMD_BACKLIGHT
    case ELMC_PEBBLE_CMD_BACKLIGHT: {
      if (cmd.p0 == 0) {
        light_enable_interaction();
        APP_LOG(APP_LOG_LEVEL_INFO, "cmd backlight interaction");
      } else if (cmd.p0 == 1) {
        s_forced_backlight = false;
        light_enable(false);
        APP_LOG(APP_LOG_LEVEL_INFO, "cmd backlight disable");
      } else if (cmd.p0 == 2) {
        s_forced_backlight = true;
        light_enable(true);
        APP_LOG(APP_LOG_LEVEL_INFO, "cmd backlight enable");
      } else {
        APP_LOG(APP_LOG_LEVEL_WARNING, "cmd backlight unknown mode=%ld", (long)cmd.p0);
      }
      break;
    }
#endif
#if ELMC_PEBBLE_FEATURE_CMD_GET_CURRENT_TIME_STRING
    case ELMC_PEBBLE_CMD_GET_CURRENT_TIME_STRING: {
      char time_buffer[16] = {0};
      clock_copy_time_string(time_buffer, sizeof(time_buffer));
#if ELMC_PEBBLE_FEATURE_MSG_CURRENT_TIME
      int rc =
          elmc_pebble_dispatch_tag_string(&s_elm_app, ELMC_PEBBLE_MSG_CURRENT_TIME_TARGET, time_buffer);
      APP_LOG(APP_LOG_LEVEL_INFO, "cmd current_time=%s rc=%d", time_buffer, rc);
      if (rc == 0) {
        apply_pending_cmd();
        render_model();
      }
#else
      APP_LOG(APP_LOG_LEVEL_INFO, "cmd current_time ignored (no msg tag)");
#endif
      break;
    }
#endif
#if ELMC_PEBBLE_FEATURE_CMD_GET_CURRENT_DATE_TIME
    case ELMC_PEBBLE_CMD_GET_CURRENT_DATE_TIME: {
      time_t now = time(NULL);
      struct tm *local = localtime(&now);
      if (!local || ELMC_PEBBLE_MSG_CURRENT_DATE_TIME_TARGET <= 0) {
        APP_LOG(APP_LOG_LEVEL_WARNING, "cmd current_date_time unavailable");
        break;
      }

      int64_t day_of_week = local->tm_wday == 0 ? 6 : local->tm_wday - 1;
      const char *field_names[] = {
          "year", "month", "day", "dayOfWeek", "hour", "minute", "second", "utcOffsetMinutes"};
      int64_t field_values[] = {
          local->tm_year + 1900,
          local->tm_mon + 1,
          local->tm_mday,
          day_of_week,
          local->tm_hour,
          local->tm_min,
          local->tm_sec,
          0};
      int rc = elmc_pebble_dispatch_tag_record_int_fields(
          &s_elm_app,
          ELMC_PEBBLE_MSG_CURRENT_DATE_TIME_TARGET,
          8,
          field_names,
          field_values);
      APP_LOG(APP_LOG_LEVEL_INFO, "cmd current_date_time rc=%d", rc);
      if (rc == 0) {
        apply_pending_cmd();
        render_model();
      }
      break;
    }
#endif
#if ELMC_PEBBLE_FEATURE_CMD_GET_BATTERY_LEVEL
    case ELMC_PEBBLE_CMD_GET_BATTERY_LEVEL: {
      BatteryChargeState state = battery_state_service_peek();
      int rc = -6;
      if (ELMC_PEBBLE_MSG_BATTERY_LEVEL_TARGET > 0) {
        rc = elmc_pebble_dispatch_tag_value(
            &s_elm_app,
            ELMC_PEBBLE_MSG_BATTERY_LEVEL_TARGET,
            state.charge_percent);
      }
      APP_LOG(APP_LOG_LEVEL_INFO, "cmd battery_level=%d rc=%d", state.charge_percent, rc);
      if (rc == 0) {
        apply_pending_cmd();
        render_model();
      }
      break;
    }
#endif
#if ELMC_PEBBLE_FEATURE_CMD_GET_CONNECTION_STATUS
    case ELMC_PEBBLE_CMD_GET_CONNECTION_STATUS: {
      bool connected = connection_service_peek_pebble_app_connection();
      int rc = -6;
      if (ELMC_PEBBLE_MSG_CONNECTION_STATUS_TARGET > 0) {
        rc = elmc_pebble_dispatch_tag_bool(
            &s_elm_app,
            ELMC_PEBBLE_MSG_CONNECTION_STATUS_TARGET,
            connected);
      }
      APP_LOG(APP_LOG_LEVEL_INFO, "cmd connection_status=%d rc=%d", connected ? 1 : 0, rc);
      if (rc == 0) {
        apply_pending_cmd();
        render_model();
      }
      break;
    }
#endif
#if ELMC_PEBBLE_FEATURE_CMD_HEALTH_VALUE
    case ELMC_PEBBLE_CMD_HEALTH_VALUE: {
      int64_t value = 0;
#ifdef PBL_HEALTH
      value = health_service_peek_current_value(health_metric_from_code(cmd.p0));
#endif
      int rc = cmd.p1 > 0 ? elmc_pebble_dispatch_tag_value(&s_elm_app, cmd.p1, value) : -6;
      APP_LOG(APP_LOG_LEVEL_INFO, "cmd health_value metric=%ld value=%ld rc=%d",
              (long)cmd.p0, (long)value, rc);
      if (rc == 0) {
        apply_pending_cmd();
        render_model();
      }
      break;
    }
#endif
#if ELMC_PEBBLE_FEATURE_CMD_HEALTH_SUM_TODAY
    case ELMC_PEBBLE_CMD_HEALTH_SUM_TODAY: {
      int64_t value = 0;
#ifdef PBL_HEALTH
      value = health_service_sum_today(health_metric_from_code(cmd.p0));
#endif
      int rc = cmd.p1 > 0 ? elmc_pebble_dispatch_tag_value(&s_elm_app, cmd.p1, value) : -6;
      APP_LOG(APP_LOG_LEVEL_INFO, "cmd health_sum_today metric=%ld value=%ld rc=%d",
              (long)cmd.p0, (long)value, rc);
      if (rc == 0) {
        apply_pending_cmd();
        render_model();
      }
      break;
    }
#endif
#if ELMC_PEBBLE_FEATURE_CMD_HEALTH_SUM
    case ELMC_PEBBLE_CMD_HEALTH_SUM: {
      int64_t value = 0;
#ifdef PBL_HEALTH
      value = health_service_sum(
          health_metric_from_code(cmd.p0),
          health_time_from_seconds(cmd.p1),
          health_time_from_seconds(cmd.p2));
#endif
      int rc = cmd.p3 > 0 ? elmc_pebble_dispatch_tag_value(&s_elm_app, cmd.p3, value) : -6;
      APP_LOG(APP_LOG_LEVEL_INFO, "cmd health_sum metric=%ld value=%ld rc=%d",
              (long)cmd.p0, (long)value, rc);
      if (rc == 0) {
        apply_pending_cmd();
        render_model();
      }
      break;
    }
#endif
#if ELMC_PEBBLE_FEATURE_CMD_HEALTH_ACCESSIBLE
    case ELMC_PEBBLE_CMD_HEALTH_ACCESSIBLE: {
      bool accessible = false;
#ifdef PBL_HEALTH
      HealthServiceAccessibilityMask mask = health_service_metric_accessible(
          health_metric_from_code(cmd.p0),
          health_time_from_seconds(cmd.p1),
          health_time_from_seconds(cmd.p2));
      accessible = (mask & HealthServiceAccessibilityMaskAvailable) != 0;
#endif
      int rc = cmd.p3 > 0 ? elmc_pebble_dispatch_tag_bool(&s_elm_app, cmd.p3, accessible) : -6;
      APP_LOG(APP_LOG_LEVEL_INFO, "cmd health_accessible metric=%ld accessible=%d rc=%d",
              (long)cmd.p0, accessible ? 1 : 0, rc);
      if (rc == 0) {
        apply_pending_cmd();
        render_model();
      }
      break;
    }
#endif
#if ELMC_PEBBLE_FEATURE_CMD_GET_CLOCK_STYLE_24H
    case ELMC_PEBBLE_CMD_GET_CLOCK_STYLE_24H: {
      APP_LOG(APP_LOG_LEVEL_INFO, "cmd get_clock_style_24h ignored (no msg tag)");
      break;
    }
#endif
#if ELMC_PEBBLE_FEATURE_CMD_GET_TIMEZONE_IS_SET
    case ELMC_PEBBLE_CMD_GET_TIMEZONE_IS_SET: {
      APP_LOG(APP_LOG_LEVEL_INFO, "cmd get_timezone_is_set ignored (no msg tag)");
      break;
    }
#endif
#if ELMC_PEBBLE_FEATURE_CMD_GET_TIMEZONE
    case ELMC_PEBBLE_CMD_GET_TIMEZONE: {
      APP_LOG(APP_LOG_LEVEL_INFO, "cmd get_timezone ignored (no msg tag)");
      break;
    }
#endif
#if ELMC_PEBBLE_FEATURE_CMD_GET_WATCH_MODEL
    case ELMC_PEBBLE_CMD_GET_WATCH_MODEL: {
      int64_t model_tag = watch_model_to_elm_tag(watch_info_get_model());
      APP_LOG(APP_LOG_LEVEL_INFO, "cmd watch_model_tag=%ld ignored (no msg tag)", (long)model_tag);
      break;
    }
#endif
#if ELMC_PEBBLE_FEATURE_CMD_GET_WATCH_COLOR
    case ELMC_PEBBLE_CMD_GET_WATCH_COLOR: {
      int64_t color_tag = watch_color_to_elm_tag(watch_info_get_color());
      APP_LOG(APP_LOG_LEVEL_INFO, "cmd watch_color_tag=%ld ignored (no msg tag)", (long)color_tag);
      break;
    }
#endif
#if ELMC_PEBBLE_FEATURE_CMD_GET_FIRMWARE_VERSION
    case ELMC_PEBBLE_CMD_GET_FIRMWARE_VERSION: {
      APP_LOG(APP_LOG_LEVEL_INFO, "cmd get_firmware_version ignored (no msg tag)");
      break;
    }
#endif
#if ELMC_PEBBLE_FEATURE_CMD_WAKEUP_SCHEDULE_AFTER_SECONDS
    case ELMC_PEBBLE_CMD_WAKEUP_SCHEDULE_AFTER_SECONDS: {
      time_t now = time(NULL);
      WakeupId id = wakeup_schedule(now + cmd.p0, 0, true);
      APP_LOG(APP_LOG_LEVEL_INFO, "cmd wakeup_schedule_after=%ld id=%ld", (long)cmd.p0, (long)id);
      break;
    }
#endif
#if ELMC_PEBBLE_FEATURE_CMD_WAKEUP_CANCEL
    case ELMC_PEBBLE_CMD_WAKEUP_CANCEL: {
      WakeupId id = (WakeupId)cmd.p0;
      wakeup_cancel(id);
      bool ok = true;
      APP_LOG(APP_LOG_LEVEL_INFO, "cmd wakeup_cancel id=%ld ok=%d", (long)id, ok ? 1 : 0);
      break;
    }
#endif
#if ELMC_PEBBLE_FEATURE_CMD_LOG_INFO_CODE
    case ELMC_PEBBLE_CMD_LOG_INFO_CODE: {
      APP_LOG(APP_LOG_LEVEL_INFO, "elm log info code=%ld", (long)cmd.p0);
      break;
    }
#endif
#if ELMC_PEBBLE_FEATURE_CMD_LOG_WARN_CODE
    case ELMC_PEBBLE_CMD_LOG_WARN_CODE: {
      APP_LOG(APP_LOG_LEVEL_WARNING, "elm log warn code=%ld", (long)cmd.p0);
      break;
    }
#endif
#if ELMC_PEBBLE_FEATURE_CMD_LOG_ERROR_CODE
    case ELMC_PEBBLE_CMD_LOG_ERROR_CODE: {
      APP_LOG(APP_LOG_LEVEL_ERROR, "elm log error code=%ld", (long)cmd.p0);
      break;
    }
#endif
#if ELMC_PEBBLE_FEATURE_CMD_VIBES_CANCEL
    case ELMC_PEBBLE_CMD_VIBES_CANCEL: {
      vibes_cancel();
      APP_LOG(APP_LOG_LEVEL_INFO, "cmd vibes_cancel");
      break;
    }
#endif
#if ELMC_PEBBLE_FEATURE_CMD_VIBES_SHORT_PULSE
    case ELMC_PEBBLE_CMD_VIBES_SHORT_PULSE: {
      vibes_short_pulse();
      APP_LOG(APP_LOG_LEVEL_INFO, "cmd vibes_short_pulse");
      break;
    }
#endif
#if ELMC_PEBBLE_FEATURE_CMD_VIBES_LONG_PULSE
    case ELMC_PEBBLE_CMD_VIBES_LONG_PULSE: {
      vibes_long_pulse();
      APP_LOG(APP_LOG_LEVEL_INFO, "cmd vibes_long_pulse");
      break;
    }
#endif
#if ELMC_PEBBLE_FEATURE_CMD_VIBES_DOUBLE_PULSE
    case ELMC_PEBBLE_CMD_VIBES_DOUBLE_PULSE: {
      vibes_double_pulse();
      APP_LOG(APP_LOG_LEVEL_INFO, "cmd vibes_double_pulse");
      break;
    }
#endif
    default:
      break;
    }
  }
  APP_LOG(APP_LOG_LEVEL_WARNING, "cmd drain guard reached");
  ELMC_PEBBLE_TRACE_EXIT("apply_pending_cmd");
}

static void startup_cmd_callback(void *data) {
  ELMC_PEBBLE_TRACE_ENTER("startup_cmd_callback");
  // #region agent log
  ELMC_AGENT_INIT_PROBE(0xED991001);
  // #endregion
  (void)data;
  apply_pending_cmd();
  // #region agent log
  ELMC_AGENT_INIT_PROBE(0xED991002);
  // #endregion
#if ELMC_PEBBLE_STARTUP_RENDER
  render_model();
  // #region agent log
  ELMC_AGENT_INIT_PROBE(0xED991003);
  // #endregion
#endif
  ELMC_PEBBLE_TRACE_EXIT("startup_cmd_callback");
}

static GColor color_from_code(int64_t value) {
  int code = (int)(value & 0xff);
  int red = ((code >> 4) & 0x3) * 85;
  int green = ((code >> 2) & 0x3) * 85;
  int blue = (code & 0x3) * 85;
#ifdef PBL_COLOR
  return GColorFromRGB(red, green, blue);
#else
  int luminance = (red * 30 + green * 59 + blue * 11) / 100;
  return luminance >= 128 ? GColorWhite : GColorBlack;
#endif
}

#if ELMC_PEBBLE_FEATURE_DRAW_COMPOSITING_MODE
static GCompOp compositing_from_code(int64_t value) {
  switch ((int)value) {
    case 1:
      return GCompOpAnd;
    case 2:
      return GCompOpOr;
    case 3:
      return GCompOpSet;
    case 4:
      return GCompOpClear;
    case 0:
    default:
      return GCompOpAssign;
  }
}
#endif

static DrawStyleState draw_style_default(void) {
  DrawStyleState style = {
      .stroke_color = GColorBlack,
      .fill_color = GColorBlack,
      .text_color = GColorBlack,
      .compositing_mode = GCompOpAssign,
      .stroke_width = 1,
      .antialiased = true,
  };
  return style;
}

static void apply_draw_style(GContext *ctx, const DrawStyleState *style) {
  if (!ctx || !style) {
    return;
  }
  graphics_context_set_stroke_color(ctx, style->stroke_color);
  graphics_context_set_fill_color(ctx, style->fill_color);
  graphics_context_set_text_color(ctx, style->text_color);
  graphics_context_set_compositing_mode(ctx, style->compositing_mode);
  graphics_context_set_stroke_width(ctx, style->stroke_width > 0 ? style->stroke_width : 1);
}

static bool rect_params_are_valid(int64_t w, int64_t h) {
  return w > 0 && h > 0;
}

static GRect rect_from_params(int64_t x, int64_t y, int64_t w, int64_t h) {
  return GRect((int16_t)x, (int16_t)y, (int16_t)w, (int16_t)h);
}

#if ELMC_PEBBLE_DIRTY_REGION_ENABLED
static int min_int(int a, int b) {
  return a < b ? a : b;
}

static int max_int(int a, int b) {
  return a > b ? a : b;
}

static bool rect_is_empty(GRect rect) {
  return rect.size.w <= 0 || rect.size.h <= 0;
}

static GRect rect_intersection(GRect a, GRect b) {
  int x1 = max_int(a.origin.x, b.origin.x);
  int y1 = max_int(a.origin.y, b.origin.y);
  int x2 = min_int(a.origin.x + a.size.w, b.origin.x + b.size.w);
  int y2 = min_int(a.origin.y + a.size.h, b.origin.y + b.size.h);
  if (x2 <= x1 || y2 <= y1) return GRect(0, 0, 0, 0);
  return GRect((int16_t)x1, (int16_t)y1, (int16_t)(x2 - x1), (int16_t)(y2 - y1));
}

static bool rects_intersect(GRect a, GRect b) {
  if (rect_is_empty(a) || rect_is_empty(b)) return false;
  return a.origin.x < b.origin.x + b.size.w &&
         b.origin.x < a.origin.x + a.size.w &&
         a.origin.y < b.origin.y + b.size.h &&
         b.origin.y < a.origin.y + a.size.h;
}

static bool draw_cmd_bounds(const ElmcPebbleDrawCmd *cmd, GRect *out_rect) {
  if (!cmd || !out_rect) return false;
  switch (cmd->kind) {
  case ELMC_PEBBLE_DRAW_PIXEL:
    *out_rect = GRect((int16_t)cmd->p0, (int16_t)cmd->p1, 1, 1);
    return true;
  case ELMC_PEBBLE_DRAW_LINE: {
    int x1 = min_int(cmd->p0, cmd->p2);
    int y1 = min_int(cmd->p1, cmd->p3);
    int x2 = max_int(cmd->p0, cmd->p2);
    int y2 = max_int(cmd->p1, cmd->p3);
    *out_rect = GRect((int16_t)x1, (int16_t)y1, (int16_t)(x2 - x1 + 1), (int16_t)(y2 - y1 + 1));
    return true;
  }
  case ELMC_PEBBLE_DRAW_RECT:
  case ELMC_PEBBLE_DRAW_FILL_RECT:
  case ELMC_PEBBLE_DRAW_ROUND_RECT:
  case ELMC_PEBBLE_DRAW_ARC:
  case ELMC_PEBBLE_DRAW_FILL_RADIAL:
    *out_rect = GRect((int16_t)cmd->p0, (int16_t)cmd->p1, (int16_t)cmd->p2, (int16_t)cmd->p3);
    return !rect_is_empty(*out_rect);
  case ELMC_PEBBLE_DRAW_CIRCLE:
  case ELMC_PEBBLE_DRAW_FILL_CIRCLE: {
    int r = cmd->p2 < 0 ? 0 : cmd->p2;
    *out_rect = GRect((int16_t)(cmd->p0 - r), (int16_t)(cmd->p1 - r), (int16_t)(r * 2 + 1), (int16_t)(r * 2 + 1));
    return !rect_is_empty(*out_rect);
  }
  case ELMC_PEBBLE_DRAW_TEXT:
  case ELMC_PEBBLE_DRAW_BITMAP_IN_RECT:
    *out_rect = GRect((int16_t)cmd->p1, (int16_t)cmd->p2, (int16_t)cmd->p3, (int16_t)cmd->p4);
    return !rect_is_empty(*out_rect);
  default:
    return false;
  }
}

static bool draw_cmd_should_execute(const ElmcPebbleDrawCmd *cmd, bool dirty_full, GRect dirty_rect) {
  if (dirty_full) return true;
  if (!cmd) return false;
  switch (cmd->kind) {
  case ELMC_PEBBLE_DRAW_PUSH_CONTEXT:
  case ELMC_PEBBLE_DRAW_POP_CONTEXT:
  case ELMC_PEBBLE_DRAW_STROKE_WIDTH:
  case ELMC_PEBBLE_DRAW_ANTIALIASED:
  case ELMC_PEBBLE_DRAW_STROKE_COLOR:
  case ELMC_PEBBLE_DRAW_FILL_COLOR:
  case ELMC_PEBBLE_DRAW_TEXT_COLOR:
  case ELMC_PEBBLE_DRAW_COMPOSITING_MODE:
  case ELMC_PEBBLE_DRAW_CLEAR:
    return true;
  default: {
    GRect bounds;
    return draw_cmd_bounds(cmd, &bounds) && rects_intersect(bounds, dirty_rect);
  }
  }
}
#endif

static void draw_update_proc(Layer *layer, GContext *ctx) {
  ELMC_PEBBLE_TRACE_ENTER("draw_update_proc");
  // #region agent log
  ELMC_AGENT_INIT_PROBE(0xED993001);
  // #endregion
  if (!layer || !ctx) {
    APP_LOG(APP_LOG_LEVEL_WARNING, "draw skipped null layer/context");
    ELMC_PEBBLE_TRACE_EXIT("draw_update_proc");
    return;
  }
  // #region agent log
  ELMC_AGENT_INIT_PROBE(0xED993010);
  // #endregion
  if (!s_logged_first_draw) {
    ELMC_PEBBLE_DEBUG_LOG(APP_LOG_LEVEL_INFO, "draw begin seq=%d", s_render_sequence);
  }
  GRect bounds = layer_get_bounds(layer);
  // #region agent log
  ELMC_AGENT_INIT_PROBE(0xED993011);
  // #endregion
  bool dirty_full = true;
  GRect paint_rect = bounds;
#if ELMC_PEBBLE_DIRTY_REGION_ENABLED
  ElmcPebbleRect runtime_dirty_rect = {0, 0, bounds.size.w, bounds.size.h};
  int runtime_dirty_full = 1;
  int dirty_rc = elmc_pebble_scene_dirty_rect(&s_elm_app, &runtime_dirty_rect, &runtime_dirty_full);
  // #region agent log
  ELMC_AGENT_INIT_PROBE(0xED993002);
  // #endregion
  dirty_full = dirty_rc <= 0 || runtime_dirty_full != 0;
  if (!dirty_full) {
    paint_rect = rect_intersection(
        bounds,
        GRect((int16_t)runtime_dirty_rect.x,
              (int16_t)runtime_dirty_rect.y,
              (int16_t)runtime_dirty_rect.w,
              (int16_t)runtime_dirty_rect.h));
    if (rect_is_empty(paint_rect)) {
      if (!s_logged_first_draw) {
        ELMC_PEBBLE_DEBUG_LOG(APP_LOG_LEVEL_INFO, "draw skipped empty dirty rect");
        s_logged_first_draw = true;
      }
#if ELMC_PEBBLE_FEATURE_FRAME_EVENTS
      schedule_frame_timer_if_needed();
#endif
      ELMC_PEBBLE_TRACE_EXIT("draw_update_proc");
      return;
    }
  }
#endif
  (void)dirty_full;
  graphics_context_set_fill_color(ctx, GColorWhite);
  graphics_fill_rect(ctx, paint_rect, 0, GCornerNone);
  // #region agent log
  ELMC_AGENT_INIT_PROBE(0xED993020);
  // #endregion
  if (!s_logged_first_draw) {
    ELMC_PEBBLE_DEBUG_LOG(APP_LOG_LEVEL_INFO, "draw base filled x=%d y=%d w=%d h=%d full=%d",
            paint_rect.origin.x, paint_rect.origin.y, paint_rect.size.w, paint_rect.size.h, dirty_full ? 1 : 0);
  }

#if ELMC_PEBBLE_FEATURE_DRAW_TEXT_INT
  char text_buf[32];
#endif
  bool drew_text = false;
  DrawStyleState style_stack[8];
  int style_top = 0;
  style_stack[style_top] = draw_style_default();
  apply_draw_style(ctx, &style_stack[style_top]);
  // #region agent log
  ELMC_AGENT_INIT_PROBE(0xED993030);
  // #endregion
  if (!s_logged_first_draw) {
    ELMC_PEBBLE_DEBUG_LOG(APP_LOG_LEVEL_INFO, "draw style applied");
  }

  enum {
    DRAW_HEAP_CHUNK_CAPACITY = 32,
    DRAW_MEDIUM_HEAP_CHUNK_CAPACITY = 16,
    DRAW_SMALL_HEAP_CHUNK_CAPACITY = 8,
    DRAW_TINY_HEAP_CHUNK_CAPACITY = 1,
    DRAW_CHUNK_GUARD = 128
  };
  int draw_chunk_capacity = DRAW_HEAP_CHUNK_CAPACITY;
  ElmcPebbleDrawCmd *draw_chunk =
      (ElmcPebbleDrawCmd *)malloc(sizeof(ElmcPebbleDrawCmd) * draw_chunk_capacity);
  if (!draw_chunk) {
    draw_chunk_capacity = DRAW_MEDIUM_HEAP_CHUNK_CAPACITY;
    draw_chunk = (ElmcPebbleDrawCmd *)malloc(sizeof(ElmcPebbleDrawCmd) * draw_chunk_capacity);
  }
  if (!draw_chunk) {
    draw_chunk_capacity = DRAW_SMALL_HEAP_CHUNK_CAPACITY;
    draw_chunk = (ElmcPebbleDrawCmd *)malloc(sizeof(ElmcPebbleDrawCmd) * draw_chunk_capacity);
  }
  if (!draw_chunk) {
    draw_chunk_capacity = DRAW_TINY_HEAP_CHUNK_CAPACITY;
    draw_chunk = (ElmcPebbleDrawCmd *)malloc(sizeof(ElmcPebbleDrawCmd) * draw_chunk_capacity);
  }
  if (!draw_chunk) {
    APP_LOG(APP_LOG_LEVEL_WARNING, "draw skipped: unable to allocate command chunk");
    ELMC_PEBBLE_TRACE_EXIT("draw_update_proc");
    return;
  }
  // #region agent log
  ELMC_AGENT_INIT_PROBE(0xED993040);
  // #endregion
  int draw_skip = 0;
  int chunks_processed = 0;

  for (int chunk = 0; chunk < DRAW_CHUNK_GUARD; chunk++) {
    // #region agent log
    ELMC_AGENT_INIT_PROBE(0xED993050);
    // #endregion
    int chunk_count = elmc_pebble_scene_commands_from(
        &s_elm_app,
        draw_chunk,
        draw_chunk_capacity,
        draw_skip);
    // #region agent log
    ELMC_AGENT_INIT_PROBE(0xED993051);
    if (chunk == 0 && draw_skip == 0) {
      ELMC_AGENT_INIT_PROBE(0xED993900 | agent_probe_count_byte(chunk_count));
      ELMC_AGENT_INIT_PROBE(0xED993A00 | agent_probe_count_byte(s_elm_app.scene.byte_count));
      ELMC_AGENT_INIT_PROBE(0xED993B00 | agent_probe_count_byte(s_elm_app.scene.command_count));
      if (s_elm_app.scene.bytes && s_elm_app.scene.byte_count >= 2) {
        ELMC_AGENT_INIT_PROBE(0xED993C00 | ((uint32_t)s_elm_app.scene.bytes[0] & 0xff));
        ELMC_AGENT_INIT_PROBE(0xED993D00 | ((uint32_t)s_elm_app.scene.bytes[1] & 0xff));
      }
    }
    // #endregion
    if (!s_logged_first_draw) {
      ELMC_PEBBLE_DEBUG_LOG(APP_LOG_LEVEL_INFO, "draw chunk=%d count=%d skip=%d cap=%d",
              chunk, chunk_count, draw_skip, draw_chunk_capacity);
    }
    chunks_processed = chunk + 1;
    if (chunk_count <= 0) {
      // #region agent log
      ELMC_AGENT_INIT_PROBE(s_agent_after_companion_dispatch ? 0xED993152 : 0xED993052);
      // #endregion
      if (!s_logged_first_draw) {
        ELMC_PEBBLE_DEBUG_LOG(APP_LOG_LEVEL_INFO, "draw complete chunks=%d cmds=%d chunk_cap=%d last=%d",
                chunk, draw_skip, draw_chunk_capacity, chunk_count);
        s_logged_first_draw = true;
      }
      break;
    }

    for (int i = 0; i < chunk_count; i++) {
      const ElmcPebbleDrawCmd *cmd = &draw_chunk[i];
      if (draw_skip + i < 4) {
        // #region agent log
        agent_draw_cmd_probe(draw_skip + i, cmd);
        // #endregion
      }
      // #region agent log
      ELMC_AGENT_INIT_PROBE(0xED993060);
      // #endregion
      if (!s_logged_first_draw && draw_skip + i < 12) {
        ELMC_PEBBLE_DEBUG_LOG(APP_LOG_LEVEL_INFO,
                "draw cmd index=%d kind=%lld p0=%lld p1=%lld p2=%lld p3=%lld p4=%lld",
                draw_skip + i,
                (long long)cmd->kind,
                (long long)cmd->p0,
                (long long)cmd->p1,
                (long long)cmd->p2,
                (long long)cmd->p3,
                (long long)cmd->p4);
      }
      if (
#if ELMC_PEBBLE_DIRTY_REGION_ENABLED
          !draw_cmd_should_execute(cmd, dirty_full, paint_rect)
#else
          false
#endif
      ) {
        if (draw_skip + i < 4) {
          // #region agent log
          ELMC_AGENT_INIT_PROBE(0xED993700 | (((uint32_t)(draw_skip + i) & 0x0f) << 4) | ((uint32_t)cmd->kind & 0x0f));
          // #endregion
        }
        continue;
      }
      if (draw_skip + i < 4) {
        // #region agent log
        ELMC_AGENT_INIT_PROBE(0xED993800 | (((uint32_t)(draw_skip + i) & 0x0f) << 4) | ((uint32_t)cmd->kind & 0x0f));
        // #endregion
      }
      switch (cmd->kind) {
#if ELMC_PEBBLE_FEATURE_DRAW_CONTEXT
      case ELMC_PEBBLE_DRAW_PUSH_CONTEXT:
        if (style_top < (int)(sizeof(style_stack) / sizeof(style_stack[0])) - 1) {
          style_stack[style_top + 1] = style_stack[style_top];
          style_top += 1;
          apply_draw_style(ctx, &style_stack[style_top]);
        }
        break;
      case ELMC_PEBBLE_DRAW_POP_CONTEXT:
        if (style_top > 0) {
          style_top -= 1;
          apply_draw_style(ctx, &style_stack[style_top]);
        }
        break;
#endif
#if ELMC_PEBBLE_FEATURE_DRAW_STROKE_WIDTH
      case ELMC_PEBBLE_DRAW_STROKE_WIDTH: {
        uint8_t width = (uint8_t)(cmd->p0 <= 0 ? 1 : cmd->p0);
        style_stack[style_top].stroke_width = width;
        graphics_context_set_stroke_width(ctx, width);
        break;
      }
#endif
#if ELMC_PEBBLE_FEATURE_DRAW_ANTIALIASED
      case ELMC_PEBBLE_DRAW_ANTIALIASED:
        style_stack[style_top].antialiased = cmd->p0 != 0;
        graphics_context_set_antialiased(ctx, style_stack[style_top].antialiased);
        break;
#endif
#if ELMC_PEBBLE_FEATURE_DRAW_STROKE_COLOR
      case ELMC_PEBBLE_DRAW_STROKE_COLOR:
        style_stack[style_top].stroke_color = color_from_code(cmd->p0);
        graphics_context_set_stroke_color(ctx, style_stack[style_top].stroke_color);
        break;
#endif
#if ELMC_PEBBLE_FEATURE_DRAW_FILL_COLOR
      case ELMC_PEBBLE_DRAW_FILL_COLOR:
        style_stack[style_top].fill_color = color_from_code(cmd->p0);
        graphics_context_set_fill_color(ctx, style_stack[style_top].fill_color);
        break;
#endif
#if ELMC_PEBBLE_FEATURE_DRAW_TEXT_COLOR
      case ELMC_PEBBLE_DRAW_TEXT_COLOR:
        style_stack[style_top].text_color = color_from_code(cmd->p0);
        graphics_context_set_text_color(ctx, style_stack[style_top].text_color);
        break;
#endif
#if ELMC_PEBBLE_FEATURE_DRAW_COMPOSITING_MODE
      case ELMC_PEBBLE_DRAW_COMPOSITING_MODE:
        style_stack[style_top].compositing_mode = compositing_from_code(cmd->p0);
        graphics_context_set_compositing_mode(ctx, style_stack[style_top].compositing_mode);
        break;
#endif
#if ELMC_PEBBLE_FEATURE_DRAW_CLEAR
      case ELMC_PEBBLE_DRAW_CLEAR:
        graphics_context_set_fill_color(ctx, color_from_code(cmd->p0));
        graphics_fill_rect(ctx, paint_rect, 0, GCornerNone);
        graphics_context_set_fill_color(ctx, style_stack[style_top].fill_color);
        break;
#endif
#if ELMC_PEBBLE_FEATURE_DRAW_LINE
      case ELMC_PEBBLE_DRAW_LINE: {
        int16_t x1 = (int16_t)cmd->p0;
        int16_t y1 = (int16_t)cmd->p1;
        int16_t x2 = (int16_t)cmd->p2;
        int16_t y2 = (int16_t)cmd->p3;
        graphics_context_set_stroke_color(ctx, color_from_code(cmd->p4));
        graphics_draw_line(ctx, GPoint(x1, y1), GPoint(x2, y2));
        graphics_context_set_stroke_color(ctx, style_stack[style_top].stroke_color);
        break;
      }
#endif
#if ELMC_PEBBLE_FEATURE_DRAW_FILL_RECT
      case ELMC_PEBBLE_DRAW_FILL_RECT: {
        int16_t x = (int16_t)cmd->p0;
        int16_t y = (int16_t)cmd->p1;
        int16_t w = (int16_t)cmd->p2;
        int16_t h = (int16_t)cmd->p3;
        if (rect_params_are_valid(w, h)) {
          graphics_context_set_fill_color(ctx, color_from_code(cmd->p4));
          graphics_fill_rect(ctx, GRect(x, y, w, h), 0, GCornerNone);
          graphics_context_set_fill_color(ctx, style_stack[style_top].fill_color);
        }
        break;
      }
#endif
#if ELMC_PEBBLE_FEATURE_DRAW_RECT
      case ELMC_PEBBLE_DRAW_RECT: {
        int16_t x = (int16_t)cmd->p0;
        int16_t y = (int16_t)cmd->p1;
        int16_t w = (int16_t)cmd->p2;
        int16_t h = (int16_t)cmd->p3;
        if (rect_params_are_valid(w, h)) {
          graphics_context_set_stroke_color(ctx, color_from_code(cmd->p4));
          graphics_draw_rect(ctx, GRect(x, y, w, h));
          graphics_context_set_stroke_color(ctx, style_stack[style_top].stroke_color);
        }
        break;
      }
#endif
#if ELMC_PEBBLE_FEATURE_DRAW_ROUND_RECT
      case ELMC_PEBBLE_DRAW_ROUND_RECT: {
        int16_t x = (int16_t)cmd->p0;
        int16_t y = (int16_t)cmd->p1;
        int16_t w = (int16_t)cmd->p2;
        int16_t h = (int16_t)cmd->p3;
        uint16_t radius = (uint16_t)(cmd->p4 < 0 ? 0 : cmd->p4);
        if (rect_params_are_valid(w, h)) {
          graphics_context_set_stroke_color(ctx, color_from_code(cmd->p5));
          graphics_draw_round_rect(ctx, GRect(x, y, w, h), radius);
          graphics_context_set_stroke_color(ctx, style_stack[style_top].stroke_color);
        }
        break;
      }
#endif
#if ELMC_PEBBLE_FEATURE_DRAW_ARC
      case ELMC_PEBBLE_DRAW_ARC: {
        int16_t x = (int16_t)cmd->p0;
        int16_t y = (int16_t)cmd->p1;
        int16_t w = (int16_t)cmd->p2;
        int16_t h = (int16_t)cmd->p3;
        int32_t angle_start = (int32_t)cmd->p4;
        int32_t angle_end = (int32_t)cmd->p5;
        if (rect_params_are_valid(w, h)) {
          graphics_draw_arc(ctx, GRect(x, y, w, h), GOvalScaleModeFitCircle, angle_start, angle_end);
        }
        break;
      }
#endif
#if ELMC_PEBBLE_FEATURE_DRAW_FILL_RADIAL
      case ELMC_PEBBLE_DRAW_FILL_RADIAL: {
#if ELMC_PEBBLE_NATIVE_FILL_RADIAL_ENABLED
        int16_t x = (int16_t)cmd->p0;
        int16_t y = (int16_t)cmd->p1;
        int16_t w = (int16_t)cmd->p2;
        int16_t h = (int16_t)cmd->p3;
        int32_t angle_start = (int32_t)cmd->p4;
        int32_t angle_end = (int32_t)cmd->p5;
        if (rect_params_are_valid(w, h)) {
          uint16_t thickness = (uint16_t)((w < h ? w : h) / 2);
          graphics_fill_radial(ctx, GRect(x, y, w, h), GOvalScaleModeFitCircle, thickness, angle_start, angle_end);
        }
#endif
        break;
      }
#endif
#if ELMC_PEBBLE_FEATURE_DRAW_PATH
      case ELMC_PEBBLE_DRAW_PATH_FILLED:
      case ELMC_PEBBLE_DRAW_PATH_OUTLINE:
      case ELMC_PEBBLE_DRAW_PATH_OUTLINE_OPEN: {
        int count = (int)cmd->path_point_count;
        if (count <= 1) {
          break;
        }
        if (count > 16) {
          count = 16;
        }
        GPoint points[16];
        for (int j = 0; j < count; j++) {
          points[j] = GPoint((int16_t)cmd->path_x[j], (int16_t)cmd->path_y[j]);
        }
        GPathInfo path_info = {
            .num_points = (uint32_t)count,
            .points = points,
        };
        GPath *path = gpath_create(&path_info);
        if (!path) {
          break;
        }
        gpath_move_to(path, GPoint((int16_t)cmd->path_offset_x, (int16_t)cmd->path_offset_y));
        if (cmd->path_rotation != 0) {
          gpath_rotate_to(path, (int32_t)cmd->path_rotation);
        }
        if (cmd->kind == ELMC_PEBBLE_DRAW_PATH_FILLED) {
          gpath_draw_filled(ctx, path);
        } else if (cmd->kind == ELMC_PEBBLE_DRAW_PATH_OUTLINE) {
          gpath_draw_outline(ctx, path);
        } else {
          gpath_draw_outline_open(ctx, path);
        }
        gpath_destroy(path);
        break;
      }
#endif
#if ELMC_PEBBLE_FEATURE_DRAW_CIRCLE
      case ELMC_PEBBLE_DRAW_CIRCLE: {
        int16_t x = (int16_t)cmd->p0;
        int16_t y = (int16_t)cmd->p1;
        int16_t r = (int16_t)cmd->p2;
        graphics_context_set_stroke_color(ctx, color_from_code(cmd->p3));
        graphics_draw_circle(ctx, GPoint(x, y), r);
        graphics_context_set_stroke_color(ctx, style_stack[style_top].stroke_color);
        break;
      }
#endif
#if ELMC_PEBBLE_FEATURE_DRAW_FILL_CIRCLE
      case ELMC_PEBBLE_DRAW_FILL_CIRCLE: {
        int16_t x = (int16_t)cmd->p0;
        int16_t y = (int16_t)cmd->p1;
        int16_t r = (int16_t)cmd->p2;
        graphics_context_set_fill_color(ctx, color_from_code(cmd->p3));
        graphics_fill_circle(ctx, GPoint(x, y), r);
        graphics_context_set_fill_color(ctx, style_stack[style_top].fill_color);
        break;
      }
#endif
#if ELMC_PEBBLE_FEATURE_DRAW_PIXEL
      case ELMC_PEBBLE_DRAW_PIXEL: {
        int16_t x = (int16_t)cmd->p0;
        int16_t y = (int16_t)cmd->p1;
        graphics_context_set_stroke_color(ctx, color_from_code(cmd->p2));
        graphics_draw_pixel(ctx, GPoint(x, y));
        graphics_context_set_stroke_color(ctx, style_stack[style_top].stroke_color);
        break;
      }
#endif
#if ELMC_PEBBLE_FEATURE_DRAW_TEXT_INT
      case ELMC_PEBBLE_DRAW_TEXT_INT_WITH_FONT: {
        bool should_unload = false;
        GFont font = font_from_id(cmd->p0, &should_unload);
        if (!font) {
          break;
        }
        snprintf(text_buf, sizeof(text_buf), "%lld", (long long)cmd->p3);
        graphics_draw_text(ctx, text_buf, font,
                           GRect((int16_t)cmd->p1, (int16_t)cmd->p2, bounds.size.w, bounds.size.h),
                           GTextOverflowModeWordWrap,
                           GTextAlignmentCenter, NULL);
        if (should_unload && font) fonts_unload_custom_font(font);
        drew_text = true;
        break;
      }
#endif
#if ELMC_PEBBLE_FEATURE_DRAW_TEXT_LABEL
      case ELMC_PEBBLE_DRAW_TEXT_LABEL_WITH_FONT: {
        bool should_unload = false;
        GFont font = font_from_id(cmd->p0, &should_unload);
        if (!font) {
          break;
        }
        const char *label = "Label";
        if (cmd->p3 == 0) {
          label = "Waiting for companion app";
        }
        graphics_draw_text(ctx, label, font,
                           GRect((int16_t)cmd->p1, (int16_t)cmd->p2, bounds.size.w, bounds.size.h),
                           GTextOverflowModeWordWrap,
                           GTextAlignmentCenter, NULL);
        if (should_unload && font) fonts_unload_custom_font(font);
        drew_text = true;
        break;
      }
#endif
#if ELMC_PEBBLE_FEATURE_DRAW_TEXT
      case ELMC_PEBBLE_DRAW_TEXT: {
        bool should_unload = false;
        GFont font = font_from_id_for_height(cmd->p0, cmd->p4, &should_unload);
        if (!font) {
          break;
        }
        if (rect_params_are_valid(cmd->p3, cmd->p4)) {
          graphics_draw_text(ctx, cmd->text, font,
                             rect_from_params(cmd->p1, cmd->p2, cmd->p3, cmd->p4),
                             GTextOverflowModeWordWrap,
                             GTextAlignmentCenter, NULL);
        }
        if (should_unload && font) fonts_unload_custom_font(font);
        drew_text = true;
        break;
      }
#endif
#if ELMC_PEBBLE_FEATURE_DRAW_BITMAP_IN_RECT
      case ELMC_PEBBLE_DRAW_BITMAP_IN_RECT: {
        uint32_t resource_id = elm_pebble_bitmap_resource_id(cmd->p0);
        if (resource_id == ELM_PEBBLE_RESOURCE_ID_MISSING) {
          break;
        }
        GBitmap *bitmap = gbitmap_create_with_resource(resource_id);
        if (!bitmap) {
          break;
        }
        if (rect_params_are_valid(cmd->p3, cmd->p4)) {
          graphics_draw_bitmap_in_rect(ctx, bitmap, rect_from_params(cmd->p1, cmd->p2, cmd->p3, cmd->p4));
        }
        gbitmap_destroy(bitmap);
        break;
      }
#endif
      default:
        break;
      }
    }

    draw_skip += chunk_count;
    if (chunk_count < draw_chunk_capacity) {
      if (!s_logged_first_draw) {
        ELMC_PEBBLE_DEBUG_LOG(APP_LOG_LEVEL_INFO, "draw complete chunks=%d cmds=%d chunk_cap=%d",
                chunk + 1, draw_skip, draw_chunk_capacity);
        s_logged_first_draw = true;
      }
      break;
    }
  }
  free(draw_chunk);

  if (s_last_logged_draw_sequence != s_render_sequence && s_last_render_request_ms > 0) {
    int64_t latency_ms = monotonic_ms() - s_last_render_request_ms;
    ELMC_PEBBLE_DEBUG_LOG(APP_LOG_LEVEL_INFO, "draw rendered seq=%d latency_ms=%lld chunks=%d cmds=%d chunk_cap=%d",
            s_render_sequence,
            (long long)latency_ms,
            chunks_processed,
            draw_skip,
            draw_chunk_capacity);
    s_last_logged_draw_sequence = s_render_sequence;
    (void)latency_ms;
  }

  (void)drew_text;
  (void)chunks_processed;

#if ELMC_PEBBLE_FEATURE_FRAME_EVENTS
  schedule_frame_timer_if_needed();
#endif
  ELMC_PEBBLE_TRACE_EXIT("draw_update_proc");
}

static void render_model(void) {
  ELMC_PEBBLE_TRACE_ENTER("render_model");
  // #region agent log
  ELMC_AGENT_INIT_PROBE(s_agent_after_companion_dispatch ? 0xED992101 : 0xED992001);
  // #endregion
  int64_t value = elmc_pebble_model_as_int(&s_elm_app);
  // #region agent log
  ELMC_AGENT_INIT_PROBE(s_agent_after_companion_dispatch ? 0xED992102 : 0xED992002);
  // #endregion
  s_render_sequence += 1;
  s_last_render_request_ms = monotonic_ms();
  layer_mark_dirty(s_draw_layer);
  ELMC_PEBBLE_DEBUG_LOG(APP_LOG_LEVEL_INFO, "elmc render seq=%d model=%lld", s_render_sequence, (long long)value);
  (void)value;
  ELMC_PEBBLE_TRACE_EXIT("render_model");
}

static void tick_handler(struct tm *tick_time, TimeUnits units_changed) {
  ELMC_PEBBLE_TRACE_ENTER("tick_handler");
#if ELMC_PEBBLE_FEATURE_CMD_COMPANION_SEND
  flush_pending_companion_request();
#endif
#if ELMC_PEBBLE_FEATURE_HOUR_EVENTS
  if ((units_changed & HOUR_UNIT) != 0 && tick_time) {
    int rc = elmc_pebble_dispatch_hour(&s_elm_app, tick_time->tm_hour);
    APP_LOG(APP_LOG_LEVEL_INFO, "hour dispatch hour=%d rc=%d", tick_time->tm_hour, rc);
    if (rc == 0) {
      apply_pending_cmd();
      render_model();
    }
  }
#endif
#if ELMC_PEBBLE_FEATURE_MINUTE_EVENTS
  if ((units_changed & MINUTE_UNIT) != 0 && tick_time) {
    int rc = elmc_pebble_dispatch_minute(&s_elm_app, tick_time->tm_min);
    APP_LOG(APP_LOG_LEVEL_INFO, "minute dispatch minute=%d rc=%d", tick_time->tm_min, rc);
    if (rc == 0) {
      apply_pending_cmd();
      render_model();
    }
  }
#endif
#if ELMC_PEBBLE_FEATURE_TICK_EVENTS
  if (elmc_pebble_tick(&s_elm_app) == 0) {
    apply_pending_cmd();
    render_model();
  }
#else
  (void)tick_time;
  (void)units_changed;
#endif
  ELMC_PEBBLE_TRACE_EXIT("tick_handler");
}

#if ELMC_PEBBLE_FEATURE_CMD_COMPANION_SEND
static bool send_companion_request(int request_tag, int request_value) {
  ELMC_PEBBLE_TRACE_ENTER("send_companion_request");
  DictionaryIterator *iter = NULL;
  AppMessageResult rc = app_message_outbox_begin(&iter);
  if (rc != APP_MSG_OK || !iter) {
    APP_LOG(APP_LOG_LEVEL_WARNING, "outbox_begin failed: %d", rc);
    ELMC_PEBBLE_TRACE_EXIT("send_companion_request");
    return false;
  }

  if (!companion_protocol_encode_watch_to_phone(iter, request_tag, request_value)) {
    APP_LOG(APP_LOG_LEVEL_WARNING, "protocol encode failed tag=%d value=%d", request_tag, request_value);
    ELMC_PEBBLE_TRACE_EXIT("send_companion_request");
    return false;
  }
  dict_write_end(iter);

  rc = app_message_outbox_send();
  APP_LOG(APP_LOG_LEVEL_INFO, "watch -> companion tag=%d value=%d rc=%d", request_tag, request_value, rc);
  bool ok = rc == APP_MSG_OK;
  ELMC_PEBBLE_TRACE_EXIT("send_companion_request");
  return ok;
}

static void flush_pending_companion_request(void) {
  ELMC_PEBBLE_TRACE_ENTER("flush_pending_companion_request");
  if (!s_pending_companion_request) {
    ELMC_PEBBLE_TRACE_EXIT("flush_pending_companion_request");
    return;
  }
  if (send_companion_request(s_pending_request_tag, s_pending_request_value)) {
    s_pending_companion_request = false;
  }
  ELMC_PEBBLE_TRACE_EXIT("flush_pending_companion_request");
}
#endif

static bool debug_storage_tuple_int(Tuple *tuple, int32_t *out) {
  if (!tuple || !out) {
    return false;
  }
  if (tuple->type == TUPLE_INT) {
    *out = tuple->value->int32;
    return true;
  }
  if (tuple->type == TUPLE_UINT) {
    *out = (int32_t)tuple->value->uint32;
    return true;
  }
  return false;
}

static bool handle_debug_storage(DictionaryIterator *iter) {
  ELMC_PEBBLE_TRACE_ENTER("handle_debug_storage");
  // #region agent log
  ELMC_AGENT_INIT_PROBE(0xED995100);
  // #endregion
  Tuple *op_tuple = dict_find(iter, ELMC_DEBUG_STORAGE_KEY_OP);
  // #region agent log
  ELMC_AGENT_INIT_PROBE(0xED995111);
  // #endregion
  Tuple *key_tuple = dict_find(iter, ELMC_DEBUG_STORAGE_KEY_KEY);
  // #region agent log
  ELMC_AGENT_INIT_PROBE(0xED995112);
  // #endregion
  int32_t op = 0;
  int32_t key_value = 0;

  if (!debug_storage_tuple_int(op_tuple, &op) || !debug_storage_tuple_int(key_tuple, &key_value)) {
    // #region agent log
    ELMC_AGENT_INIT_PROBE(0xED995101);
    // #endregion
    ELMC_PEBBLE_TRACE_EXIT("handle_debug_storage");
    return false;
  }

  uint32_t key = (uint32_t)key_value;
  if (op == ELMC_DEBUG_STORAGE_OP_DELETE) {
    // #region agent log
    ELMC_AGENT_INIT_PROBE(0xED9951D1);
    // #endregion
    status_t status = persist_delete(key);
    APP_LOG(APP_LOG_LEVEL_INFO, "debug storage_delete key=%lu status=%ld",
            (unsigned long)key, (long)status);
    ELMC_PEBBLE_TRACE_EXIT("handle_debug_storage");
    return true;
  }

  int32_t type = 0;
  if (op != ELMC_DEBUG_STORAGE_OP_WRITE ||
      !debug_storage_tuple_int(dict_find(iter, ELMC_DEBUG_STORAGE_KEY_TYPE), &type)) {
    // #region agent log
    ELMC_AGENT_INIT_PROBE(0xED9951E1);
    // #endregion
    APP_LOG(APP_LOG_LEVEL_WARNING, "debug storage ignored op=%ld key=%lu",
            (long)op, (unsigned long)key);
    ELMC_PEBBLE_TRACE_EXIT("handle_debug_storage");
    return true;
  }

  if (type == ELMC_DEBUG_STORAGE_TYPE_INT) {
    // #region agent log
    ELMC_AGENT_INIT_PROBE(0xED9951E2);
    // #endregion
    int32_t value = 0;
    if (!debug_storage_tuple_int(dict_find(iter, ELMC_DEBUG_STORAGE_KEY_INT_VALUE), &value)) {
      APP_LOG(APP_LOG_LEVEL_WARNING, "debug storage_write missing int key=%lu",
              (unsigned long)key);
      ELMC_PEBBLE_TRACE_EXIT("handle_debug_storage");
      return true;
    }
    status_t status = persist_write_int(key, value);
    APP_LOG(APP_LOG_LEVEL_INFO, "debug storage_write key=%lu value=%ld status=%ld",
            (unsigned long)key, (long)value, (long)status);
    ELMC_PEBBLE_TRACE_EXIT("handle_debug_storage");
    return true;
  }

  if (type == ELMC_DEBUG_STORAGE_TYPE_STRING) {
    // #region agent log
    ELMC_AGENT_INIT_PROBE(0xED9951E3);
    // #endregion
    Tuple *value_tuple = dict_find(iter, ELMC_DEBUG_STORAGE_KEY_STRING_VALUE);
    const char *value = value_tuple && value_tuple->type == TUPLE_CSTRING ? value_tuple->value->cstring : "";
    status_t status = persist_write_string(key, value);
    APP_LOG(APP_LOG_LEVEL_INFO, "debug storage_write_string key=%lu value=%s status=%ld",
            (unsigned long)key, value, (long)status);
    ELMC_PEBBLE_TRACE_EXIT("handle_debug_storage");
    return true;
  }

  APP_LOG(APP_LOG_LEVEL_WARNING, "debug storage ignored type=%ld key=%lu",
          (long)type, (unsigned long)key);
  ELMC_PEBBLE_TRACE_EXIT("handle_debug_storage");
  return true;
}

static void inbox_received_handler(DictionaryIterator *iter, void *context) {
  ELMC_PEBBLE_TRACE_ENTER("inbox_received_handler");
  // #region agent log
  ELMC_AGENT_INIT_PROBE(0xED995001);
  // #endregion
  (void)context;
  if (handle_debug_storage(iter)) {
    ELMC_PEBBLE_TRACE_EXIT("inbox_received_handler");
    return;
  }

#if ELMC_PEBBLE_FEATURE_INBOX_EVENTS
  // #region agent log
  ELMC_AGENT_INIT_PROBE(0xED995201);
  // #endregion
  Tuple *tuple = dict_read_first(iter);
  CompanionProtocolPhoneToWatchDecoder decoder;
  companion_protocol_phone_to_watch_decoder_init(&decoder);

  while (tuple) {
    companion_protocol_phone_to_watch_decoder_push_tuple(&decoder, tuple);
    tuple = dict_read_next(iter);
  }
  // #region agent log
  ELMC_AGENT_INIT_PROBE(0xED995202);
  // #endregion

  CompanionProtocolPhoneToWatchMessage message = {0};
  if (companion_protocol_phone_to_watch_decoder_finish(&decoder, &message) &&
      message.kind != COMPANION_PROTOCOL_PHONE_TO_WATCH_KIND_UNKNOWN) {
    // #region agent log
    ELMC_AGENT_INIT_PROBE(0xED995002);
    // #endregion
    int rc = companion_protocol_dispatch_phone_to_watch(&s_elm_app, &message);
    // #region agent log
    ELMC_AGENT_INIT_PROBE(rc == 0 ? 0xED995003 : 0xED99E503);
    // #endregion
    APP_LOG(APP_LOG_LEVEL_INFO, "companion response kind=%d rc=%d", (int)message.kind, rc);
    if (rc == 0) {
      // #region agent log
      s_agent_after_companion_dispatch = true;
      // #endregion
      apply_pending_cmd();
      // #region agent log
      ELMC_AGENT_INIT_PROBE(0xED995004);
      // #endregion
      render_model();
      // #region agent log
      ELMC_AGENT_INIT_PROBE(0xED995005);
      // #endregion
    } else {
      layer_mark_dirty(s_draw_layer);
    }
    ELMC_PEBBLE_TRACE_EXIT("inbox_received_handler");
    return;
  }
  // #region agent log
  ELMC_AGENT_INIT_PROBE(0xED9950F2);
  // #endregion

  tuple = dict_read_first(iter);
  while (tuple) {
    if (tuple->type == TUPLE_INT || tuple->type == TUPLE_UINT) {
      int rc = elmc_pebble_dispatch_appmessage(&s_elm_app, tuple->key, tuple->value->int32);
      APP_LOG(APP_LOG_LEVEL_INFO, "appmessage key=%lu value=%ld rc=%d",
              (unsigned long)tuple->key, (long)tuple->value->int32, rc);
      if (rc == 0) {
        apply_pending_cmd();
        render_model();
      }
    }
    tuple = dict_read_next(iter);
  }
#else
  (void)iter;
#endif
  ELMC_PEBBLE_TRACE_EXIT("inbox_received_handler");
}

static void inbox_dropped_handler(AppMessageResult reason, void *context) {
  ELMC_PEBBLE_TRACE_ENTER("inbox_dropped_handler");
  (void)context;
  APP_LOG(APP_LOG_LEVEL_WARNING, "inbox dropped: %d", reason);
  ELMC_PEBBLE_TRACE_EXIT("inbox_dropped_handler");
}

static void outbox_sent_handler(DictionaryIterator *iter, void *context) {
  ELMC_PEBBLE_TRACE_ENTER("outbox_sent_handler");
  (void)iter;
  (void)context;
  APP_LOG(APP_LOG_LEVEL_INFO, "outbox sent");
  ELMC_PEBBLE_TRACE_EXIT("outbox_sent_handler");
}

static void outbox_failed_handler(DictionaryIterator *iter, AppMessageResult reason, void *context) {
  ELMC_PEBBLE_TRACE_ENTER("outbox_failed_handler");
  (void)iter;
  (void)context;
  APP_LOG(APP_LOG_LEVEL_WARNING, "outbox failed: %d", reason);
  ELMC_PEBBLE_TRACE_EXIT("outbox_failed_handler");
}

static void note_user_interaction(void) {
  light_enable_interaction();
}

#if ELMC_PEBBLE_FEATURE_BUTTON_EVENTS && !ELMC_PEBBLE_FEATURE_RAW_BUTTON_EVENTS
static void click_handler(ClickRecognizerRef recognizer, void *context) {
  ELMC_PEBBLE_TRACE_ENTER("click_handler");
  (void)context;
  note_user_interaction();
  ButtonId pebble_button_id = click_recognizer_get_button_id(recognizer);
  ElmcPebbleButtonId button_id = ELMC_PEBBLE_BUTTON_SELECT;
  if (pebble_button_id == BUTTON_ID_UP) {
    button_id = ELMC_PEBBLE_BUTTON_UP;
  } else if (pebble_button_id == BUTTON_ID_DOWN) {
    button_id = ELMC_PEBBLE_BUTTON_DOWN;
  }

  int rc = elmc_pebble_dispatch_button(&s_elm_app, button_id);
  APP_LOG(APP_LOG_LEVEL_INFO, "button dispatch id=%d rc=%d", (int)button_id, rc);
  if (rc == 0) {
    apply_pending_cmd();
    render_model();
  }
  ELMC_PEBBLE_TRACE_EXIT("click_handler");
}

#if ELMC_PEBBLE_FEATURE_BUTTON_EVENTS && !ELMC_PEBBLE_FEATURE_RAW_BUTTON_EVENTS
static void click_config_provider(void *context) {
  (void)context;
  window_single_click_subscribe(BUTTON_ID_UP, click_handler);
  window_single_click_subscribe(BUTTON_ID_SELECT, click_handler);
  window_single_click_subscribe(BUTTON_ID_DOWN, click_handler);
}
#endif
#endif

#if ELMC_PEBBLE_FEATURE_RAW_BUTTON_EVENTS
static ElmcPebbleButtonId raw_button_id(ButtonId pebble_button_id) {
  if (pebble_button_id == BUTTON_ID_BACK) {
    return ELMC_PEBBLE_BUTTON_BACK;
  }
  if (pebble_button_id == BUTTON_ID_UP) {
    return ELMC_PEBBLE_BUTTON_UP;
  }
  if (pebble_button_id == BUTTON_ID_DOWN) {
    return ELMC_PEBBLE_BUTTON_DOWN;
  }
  return ELMC_PEBBLE_BUTTON_SELECT;
}

static void raw_button_down_handler(ClickRecognizerRef recognizer, void *context) {
  ELMC_PEBBLE_TRACE_ENTER("raw_button_down_handler");
  (void)context;
  note_user_interaction();
  ElmcPebbleButtonId button_id = raw_button_id(click_recognizer_get_button_id(recognizer));
  int rc = elmc_pebble_dispatch_button_raw(&s_elm_app, button_id, 1);
  ELMC_PEBBLE_DEBUG_LOG(APP_LOG_LEVEL_INFO, "raw button down id=%d rc=%d", (int)button_id, rc);
  if (rc == 0) {
    apply_pending_cmd();
    render_model();
  }
  ELMC_PEBBLE_TRACE_EXIT("raw_button_down_handler");
}

static void raw_button_up_handler(ClickRecognizerRef recognizer, void *context) {
  ELMC_PEBBLE_TRACE_ENTER("raw_button_up_handler");
  (void)context;
  note_user_interaction();
  ElmcPebbleButtonId button_id = raw_button_id(click_recognizer_get_button_id(recognizer));
  int rc = elmc_pebble_dispatch_button_raw(&s_elm_app, button_id, 0);
  ELMC_PEBBLE_DEBUG_LOG(APP_LOG_LEVEL_INFO, "raw button up id=%d rc=%d", (int)button_id, rc);
  if (rc == 0) {
    apply_pending_cmd();
    render_model();
  }
  ELMC_PEBBLE_TRACE_EXIT("raw_button_up_handler");
}

static void raw_back_click_handler(ClickRecognizerRef recognizer, void *context) {
  ELMC_PEBBLE_TRACE_ENTER("raw_back_click_handler");
  (void)recognizer;
  (void)context;
  note_user_interaction();
  int rc = elmc_pebble_dispatch_button_raw(&s_elm_app, ELMC_PEBBLE_BUTTON_BACK, 1);
  ELMC_PEBBLE_DEBUG_LOG(APP_LOG_LEVEL_INFO, "raw button back click rc=%d", rc);
  if (rc == 0) {
    apply_pending_cmd();
    render_model();
  }
  ELMC_PEBBLE_TRACE_EXIT("raw_back_click_handler");
}

static void raw_click_config_provider(void *context) {
  (void)context;
  window_single_click_subscribe(BUTTON_ID_BACK, raw_back_click_handler);
  window_raw_click_subscribe(BUTTON_ID_UP, raw_button_down_handler, raw_button_up_handler, NULL);
  window_raw_click_subscribe(BUTTON_ID_SELECT, raw_button_down_handler, raw_button_up_handler, NULL);
  window_raw_click_subscribe(BUTTON_ID_DOWN, raw_button_down_handler, raw_button_up_handler, NULL);
}
#endif

#if ELMC_PEBBLE_FEATURE_ACCEL_EVENTS
static void accel_tap_handler(AccelAxisType axis, int32_t direction) {
  ELMC_PEBBLE_TRACE_ENTER("accel_tap_handler");
  int32_t mapped_axis = ELMC_PEBBLE_ACCEL_AXIS_X;
  if (axis == ACCEL_AXIS_Y) {
    mapped_axis = ELMC_PEBBLE_ACCEL_AXIS_Y;
  } else if (axis == ACCEL_AXIS_Z) {
    mapped_axis = ELMC_PEBBLE_ACCEL_AXIS_Z;
  }

  int rc = elmc_pebble_dispatch_accel_tap(&s_elm_app, mapped_axis, direction);
  APP_LOG(APP_LOG_LEVEL_INFO, "accel tap axis=%ld dir=%ld rc=%d", (long)mapped_axis, (long)direction,
          rc);
  if (rc == 0) {
    apply_pending_cmd();
    render_model();
  }
  ELMC_PEBBLE_TRACE_EXIT("accel_tap_handler");
}
#endif

#if ELMC_PEBBLE_FEATURE_ACCEL_DATA_EVENTS
static void accel_data_handler(AccelData *data, uint32_t num_samples) {
  ELMC_PEBBLE_TRACE_ENTER("accel_data_handler");
  if (!data || num_samples == 0) {
    ELMC_PEBBLE_TRACE_EXIT("accel_data_handler");
    return;
  }
  int rc = elmc_pebble_dispatch_accel_data(&s_elm_app, data[0].x, data[0].y, data[0].z);
  APP_LOG(APP_LOG_LEVEL_INFO, "accel data x=%ld y=%ld z=%ld rc=%d",
          (long)data[0].x, (long)data[0].y, (long)data[0].z, rc);
  if (rc == 0) {
    apply_pending_cmd();
    render_model();
  }
  ELMC_PEBBLE_TRACE_EXIT("accel_data_handler");
}
#endif

#if ELMC_PEBBLE_FEATURE_BATTERY_EVENTS
static void battery_handler(BatteryChargeState state) {
  ELMC_PEBBLE_TRACE_ENTER("battery_handler");
  int rc = elmc_pebble_dispatch_battery(&s_elm_app, state.charge_percent);
  APP_LOG(APP_LOG_LEVEL_INFO, "battery dispatch rc=%d", rc);
  if (rc == 0) {
    apply_pending_cmd();
    render_model();
  }
  ELMC_PEBBLE_TRACE_EXIT("battery_handler");
}
#endif

#if ELMC_PEBBLE_FEATURE_CONNECTION_EVENTS
static void connection_handler(bool connected) {
  ELMC_PEBBLE_TRACE_ENTER("connection_handler");
  int rc = elmc_pebble_dispatch_connection(&s_elm_app, connected);
  APP_LOG(APP_LOG_LEVEL_INFO, "connection dispatch rc=%d", rc);
  if (rc == 0) {
    apply_pending_cmd();
    render_model();
  }
  ELMC_PEBBLE_TRACE_EXIT("connection_handler");
}
#endif

#if ELMC_PEBBLE_FEATURE_HEALTH_EVENTS
#ifdef PBL_HEALTH
static int health_event_to_code(HealthEventType event) {
  switch (event) {
    case HealthEventMovementUpdate:
      return 1;
    case HealthEventSleepUpdate:
      return 2;
    case HealthEventSignificantUpdate:
    default:
      return 0;
  }
}

static void health_handler(HealthEventType event, void *context) {
  ELMC_PEBBLE_TRACE_ENTER("health_handler");
  (void)context;
  int rc = elmc_pebble_dispatch_health(&s_elm_app, health_event_to_code(event));
  APP_LOG(APP_LOG_LEVEL_INFO, "health dispatch event=%d rc=%d", (int)event, rc);
  if (rc == 0) {
    apply_pending_cmd();
    render_model();
  }
  ELMC_PEBBLE_TRACE_EXIT("health_handler");
}
#endif
#endif

static void main_window_load(Window *window) {
  ELMC_PEBBLE_TRACE_ENTER("main_window_load");
  ELMC_PEBBLE_DEBUG_LOG(APP_LOG_LEVEL_INFO, "window load");
  Layer *window_layer = window_get_root_layer(window);
  GRect bounds = layer_get_bounds(window_layer);

  s_font = fonts_get_system_font(FONT_KEY_GOTHIC_24_BOLD);
  if (!s_font) {
    s_font = fonts_get_system_font(FONT_KEY_GOTHIC_24);
  }
  s_draw_layer = layer_create(bounds);
  if (!s_draw_layer) {
    APP_LOG(APP_LOG_LEVEL_ERROR, "draw layer create failed");
    ELMC_PEBBLE_TRACE_EXIT("main_window_load");
    return;
  }
  layer_set_update_proc(s_draw_layer, draw_update_proc);
  layer_add_child(window_layer, s_draw_layer);
  ELMC_PEBBLE_TRACE_EXIT("main_window_load");
}

static void main_window_unload(Window *window) {
  ELMC_PEBBLE_TRACE_ENTER("main_window_unload");
  (void)window;
  layer_destroy(s_draw_layer);
  s_draw_layer = NULL;
  ELMC_PEBBLE_TRACE_EXIT("main_window_unload");
}

static int launch_reason_to_elm_tag(AppLaunchReason launch) {
  switch (launch) {
    case APP_LAUNCH_SYSTEM:
      return 1;
    case APP_LAUNCH_USER:
      return 2;
    case APP_LAUNCH_PHONE:
      return 3;
    case APP_LAUNCH_WAKEUP:
      return 4;
    case APP_LAUNCH_WORKER:
      return 5;
    case APP_LAUNCH_QUICK_LAUNCH:
      return 6;
    case APP_LAUNCH_TIMELINE_ACTION:
      return 7;
    case APP_LAUNCH_SMARTSTRAP:
      return 8;
    default:
      return 9;
  }
}

static ElmcValue *build_launch_context(AppLaunchReason launch) {
  ELMC_PEBBLE_TRACE_ENTER("build_launch_context");
  GRect bounds = layer_get_bounds(window_get_root_layer(s_main_window));
  if (bounds.size.w <= 0 || bounds.size.h <= 0) {
#ifdef PBL_DISPLAY_WIDTH
    bounds.size.w = PBL_DISPLAY_WIDTH;
#else
    bounds.size.w = PBL_IF_ROUND_ELSE(180, 144);
#endif
#ifdef PBL_DISPLAY_HEIGHT
    bounds.size.h = PBL_DISPLAY_HEIGHT;
#else
    bounds.size.h = PBL_IF_ROUND_ELSE(180, 168);
#endif
  }

  ElmcValue *screen_width = elmc_new_int(bounds.size.w);
  ElmcValue *screen_height = elmc_new_int(bounds.size.h);
  ElmcValue *screen_is_color = elmc_new_bool(PBL_IF_COLOR_ELSE(1, 0));
  ElmcValue *screen_is_round = elmc_new_bool(PBL_IF_ROUND_ELSE(1, 0));
  const char *screen_names[] = {"height", "isColor", "isRound", "width"};
  ElmcValue *screen_values[] = {screen_height, screen_is_color, screen_is_round, screen_width};
  ElmcValue *screen = elmc_record_new(4, screen_names, screen_values);
  elmc_release(screen_width);
  elmc_release(screen_height);
  elmc_release(screen_is_color);
  elmc_release(screen_is_round);

  ElmcValue *reason = elmc_new_int(launch_reason_to_elm_tag(launch));
  ElmcValue *watch_model = elmc_new_string("");
  ElmcValue *watch_profile_id = elmc_new_string("");
  const char *context_names[] = {"reason", "screen", "watchModel", "watchProfileId"};
  ElmcValue *context_values[] = {reason, screen, watch_model, watch_profile_id};
  ElmcValue *context = elmc_record_new(4, context_names, context_values);
  elmc_release(reason);
  elmc_release(screen);
  elmc_release(watch_model);
  elmc_release(watch_profile_id);
  ELMC_PEBBLE_TRACE_EXIT("build_launch_context");
  return context;
}

static void init(void) {
  ELMC_PEBBLE_TRACE_ENTER("init");
  ELMC_PEBBLE_DEBUG_LOG(APP_LOG_LEVEL_INFO, "app init start");
#ifdef ELMC_WATCHFACE_MODE
  s_run_mode = ELMC_PEBBLE_MODE_WATCHFACE;
#else
  s_run_mode = ELMC_PEBBLE_MODE_APP;
#endif

  s_main_window = window_create();
  if (!s_main_window) {
    APP_LOG(APP_LOG_LEVEL_ERROR, "window create failed");
    ELMC_PEBBLE_TRACE_EXIT("init");
    return;
  }
  window_set_window_handlers(s_main_window, (WindowHandlers){
                                               .load = main_window_load,
                                               .unload = main_window_unload,
                                           });
#if ELMC_PEBBLE_FEATURE_RAW_BUTTON_EVENTS
  if (s_run_mode == ELMC_PEBBLE_MODE_APP) {
    window_set_click_config_provider(s_main_window, raw_click_config_provider);
  }
#elif ELMC_PEBBLE_FEATURE_BUTTON_EVENTS
  if (s_run_mode == ELMC_PEBBLE_MODE_APP) {
    window_set_click_config_provider(s_main_window, click_config_provider);
  }
#endif
  window_stack_push(s_main_window, true);
  ELMC_PEBBLE_DEBUG_LOG(APP_LOG_LEVEL_INFO, "window pushed");
  // #region agent probe
#if ELMC_AGENT_PROBE_INIT_STAGE == 1
  ELMC_PEBBLE_TRACE_EXIT("init");
  return;
#endif
  // #endregion

  AppLaunchReason launch = launch_reason();
  ElmcValue *flags = build_launch_context(launch);
  // #region agent probe
#if ELMC_AGENT_PROBE_INIT_STAGE == 2
  elmc_release(flags);
  ELMC_PEBBLE_TRACE_EXIT("init");
  return;
#endif
  // #endregion
  ELMC_PEBBLE_DEBUG_LOG(APP_LOG_LEVEL_INFO, "elmc init begin");
  int rc = elmc_pebble_init_with_mode(&s_elm_app, flags, s_run_mode);
  elmc_release(flags);
  ELMC_PEBBLE_DEBUG_LOG(APP_LOG_LEVEL_INFO, "elmc init rc=%d launch_reason=%d mode=%d", rc, (int)launch, (int)s_run_mode);
  // #region agent log
  ELMC_AGENT_INIT_PROBE(rc == 0 ? 0xED980302 : 0xED98E302);
  // #endregion
  // #region agent probe
#if ELMC_AGENT_PROBE_INIT_STAGE == 3
  ELMC_PEBBLE_TRACE_EXIT("init");
  return;
#endif
  // #endregion

  if (rc == 0) {
    app_message_register_inbox_received(inbox_received_handler);
    app_message_register_inbox_dropped(inbox_dropped_handler);
    app_message_register_outbox_sent(outbox_sent_handler);
    app_message_register_outbox_failed(outbox_failed_handler);
    AppMessageResult app_message_rc = app_message_open(ELMC_PEBBLE_APP_MESSAGE_INBOX_SIZE, ELMC_PEBBLE_APP_MESSAGE_OUTBOX_SIZE);
    (void)app_message_rc;
    AppTimer *startup_timer = app_timer_register(1, startup_cmd_callback, NULL);
    (void)startup_timer;
#if ELMC_PEBBLE_FEATURE_FRAME_EVENTS
    if (s_run_mode == ELMC_PEBBLE_MODE_APP) {
      s_frame_interval_ms = frame_interval_from_subscriptions();
    }
#endif
#if ELMC_PEBBLE_STARTUP_SERVICE_SUBSCRIPTIONS && (ELMC_PEBBLE_FEATURE_TICK_EVENTS || ELMC_PEBBLE_FEATURE_HOUR_EVENTS || ELMC_PEBBLE_FEATURE_MINUTE_EVENTS)
    tick_timer_service_subscribe(SECOND_UNIT, tick_handler);
#endif
#if ELMC_PEBBLE_STARTUP_SERVICE_SUBSCRIPTIONS && ELMC_PEBBLE_FEATURE_ACCEL_EVENTS
    if (s_run_mode == ELMC_PEBBLE_MODE_APP) {
      accel_tap_service_subscribe(accel_tap_handler);
    }
#endif
#if ELMC_PEBBLE_STARTUP_SERVICE_SUBSCRIPTIONS && ELMC_PEBBLE_FEATURE_ACCEL_DATA_EVENTS
    if (s_run_mode == ELMC_PEBBLE_MODE_APP) {
      accel_data_service_subscribe(1, accel_data_handler);
      accel_service_set_sampling_rate(ACCEL_SAMPLING_25HZ);
    }
#endif
#if ELMC_PEBBLE_STARTUP_SERVICE_SUBSCRIPTIONS && ELMC_PEBBLE_FEATURE_BATTERY_EVENTS
    battery_state_service_subscribe(battery_handler);
#endif
#if ELMC_PEBBLE_STARTUP_SERVICE_SUBSCRIPTIONS && ELMC_PEBBLE_FEATURE_CONNECTION_EVENTS
    connection_service_subscribe((ConnectionHandlers){
        .pebble_app_connection_handler = connection_handler,
    });
#endif
#if ELMC_PEBBLE_STARTUP_SERVICE_SUBSCRIPTIONS && ELMC_PEBBLE_FEATURE_HEALTH_EVENTS
#ifdef PBL_HEALTH
    health_service_events_subscribe(health_handler, NULL);
#endif
#endif
#if ELMC_PEBBLE_FEATURE_CMD_COMPANION_SEND
    flush_pending_companion_request();
#endif
  } else {
    APP_LOG(APP_LOG_LEVEL_ERROR, "elmc_pebble_init failed: %d", rc);
  }
  // #region agent log
  ELMC_AGENT_INIT_PROBE(0xED990A01);
  // #endregion
  ELMC_PEBBLE_TRACE_EXIT("init");
}

static void deinit(void) {
  ELMC_PEBBLE_TRACE_ENTER("deinit");
  ELMC_PEBBLE_DEBUG_LOG(APP_LOG_LEVEL_INFO, "app deinit start");
#if ELMC_PEBBLE_FEATURE_TICK_EVENTS || ELMC_PEBBLE_FEATURE_HOUR_EVENTS || ELMC_PEBBLE_FEATURE_MINUTE_EVENTS
  tick_timer_service_unsubscribe();
#endif
  if (s_timer) {
    app_timer_cancel(s_timer);
    s_timer = NULL;
  }
#if ELMC_PEBBLE_FEATURE_FRAME_EVENTS
  if (s_frame_timer) {
    app_timer_cancel(s_frame_timer);
    s_frame_timer = NULL;
  }
#endif
  if (s_run_mode == ELMC_PEBBLE_MODE_APP && ELMC_PEBBLE_FEATURE_ACCEL_EVENTS) {
    accel_tap_service_unsubscribe();
  }
#if ELMC_PEBBLE_FEATURE_ACCEL_DATA_EVENTS
  if (s_run_mode == ELMC_PEBBLE_MODE_APP) {
    accel_data_service_unsubscribe();
  }
#endif
#if ELMC_PEBBLE_FEATURE_BATTERY_EVENTS
  battery_state_service_unsubscribe();
#endif
#if ELMC_PEBBLE_FEATURE_CONNECTION_EVENTS
  connection_service_unsubscribe();
#endif
#if ELMC_PEBBLE_FEATURE_HEALTH_EVENTS
#ifdef PBL_HEALTH
  health_service_events_unsubscribe();
#endif
#endif
#if ELMC_PEBBLE_FEATURE_CMD_BACKLIGHT
  if (s_forced_backlight) {
    light_enable(false);
    s_forced_backlight = false;
  }
#endif
  elmc_pebble_deinit(&s_elm_app);
  // #region agent log
#if ELMC_AGENT_PROBES
  s_agent_probe_session_count = 0;
#endif
  // #endregion
  if (s_main_window) {
    window_destroy(s_main_window);
    s_main_window = NULL;
  }
  ELMC_PEBBLE_DEBUG_LOG(APP_LOG_LEVEL_INFO, "app deinit complete");
  ELMC_PEBBLE_TRACE_EXIT("deinit");
}

int main(void) {
  ELMC_PEBBLE_TRACE_ENTER("main");
  // #region agent log
  ELMC_AGENT_INIT_PROBE(0xED990001);
  // #endregion
  init();
  // #region agent log
  ELMC_AGENT_INIT_PROBE(0xED990002);
  // #endregion
  ELMC_PEBBLE_TRACE_MSG("trace before app_event_loop");
  // #region agent log
  ELMC_AGENT_INIT_PROBE(0xED990003);
  // #endregion
  app_event_loop();
  ELMC_PEBBLE_TRACE_MSG("trace after app_event_loop");
  // #region agent log
  ELMC_AGENT_INIT_PROBE(0xED990004);
  // #endregion
  deinit();
  ELMC_PEBBLE_TRACE_EXIT("main");
}
