#include <pebble.h>
#include <stdio.h>
#include <string.h>
#include <stdbool.h>
#include <stdlib.h>
#include <stdarg.h>
#include "elmc_emulator_build_flags.h"
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
         (marker >= 0xED994000 && marker <= 0xED9944FF) ||
         (marker >= 0xED995000 && marker <= 0xED9952FF);
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

#ifndef ELMC_PEBBLE_EMULATOR_STORAGE_LOGS
#define ELMC_PEBBLE_EMULATOR_STORAGE_LOGS 0
#endif

#if ELMC_PEBBLE_EMULATOR_STORAGE_LOGS
#define ELMC_PEBBLE_STORAGE_LOG(level, fmt, ...) app_log(level, __FILE_NAME__, __LINE__, fmt, ##__VA_ARGS__)
#define companion_inbox_log(fmt, ...) app_log(APP_LOG_LEVEL_INFO, "companion", 0, fmt, ##__VA_ARGS__)

static void emulator_storage_snapshot_callback(void *data) {
  (void)data;
  for (uint32_t key = 0; key < 256; key++) {
    if (!persist_exists(key)) {
      continue;
    }
    int size = persist_get_size(key);
    if (size <= 0) {
      continue;
    }
    if (size == (int)sizeof(int32_t)) {
      int32_t value = persist_read_int(key);
      ELMC_PEBBLE_STORAGE_LOG(APP_LOG_LEVEL_INFO, "cmd storage_read key=%lu value=%ld rc=0",
              (unsigned long)key, (long)value);
    } else {
      char value[128] = "";
      persist_read_string(key, value, sizeof(value));
      ELMC_PEBBLE_STORAGE_LOG(APP_LOG_LEVEL_INFO, "cmd storage_read_string key=%lu value=%s rc=0",
              (unsigned long)key, value);
    }
  }
}
#else
#define ELMC_PEBBLE_STORAGE_LOG(level, fmt, ...) do { } while (0)
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
static bool s_render_pending = false;
static AppTimer *s_render_coalesce_timer = NULL;
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
  ELMC_INBOX_MAX_TUPLES = 16,
  ELMC_INBOX_STRING_MAX = 128,
  ELMC_INBOX_TUPLE_WIRE_BYTES = 12,
  ELMC_INBOX_CSTRING_NONE = 0,
  ELMC_INBOX_CSTRING_INBOX = 1,
};

typedef struct {
  uint32_t key;
  uint8_t type;
  uint16_t length;
  int32_t int_value;
  uint8_t cstring_kind;
} ElmcInboxTupleSnapshot;

static ElmcInboxTupleSnapshot s_inbox_snapshots[ELMC_INBOX_MAX_TUPLES];
static int s_inbox_snapshot_count = 0;
static char s_inbox_cstring_snapshot[ELMC_INBOX_STRING_MAX];
static uint8_t s_inbox_tuple_wire[ELMC_INBOX_MAX_TUPLES][ELMC_INBOX_TUPLE_WIRE_BYTES];
static uint8_t s_inbox_cstring_tuple_wire[ELMC_INBOX_STRING_MAX + 8];
#if ELMC_PEBBLE_FEATURE_INBOX_EVENTS
static ElmcInboxTupleSnapshot s_companion_pending[ELMC_INBOX_MAX_TUPLES];
static uint8_t s_companion_pending_wire[ELMC_INBOX_MAX_TUPLES][ELMC_INBOX_TUPLE_WIRE_BYTES];
#endif

enum {
  ELMC_DEBUG_STORAGE_OP_WRITE = 1,
  ELMC_DEBUG_STORAGE_OP_DELETE = 2,
  ELMC_DEBUG_STORAGE_OP_SNAPSHOT = 4,
};

enum {
  ELMC_DEBUG_STORAGE_TYPE_INT = 1,
  ELMC_DEBUG_STORAGE_TYPE_STRING = 2,
};

enum {
  ELMC_DEBUG_SIMULATOR_KEY_COMPASS_HEADING = 0x454c4d10,
  ELMC_DEBUG_SIMULATOR_KEY_DICTATION_TEXT = 0x454c4d11,
  ELMC_DEBUG_SIMULATOR_KEY_WEATHER_TEMPERATURE_C = 0x454c4d12,
  ELMC_DEBUG_SIMULATOR_KEY_WEATHER_CONDITION_WIRE = 0x454c4d13,
};
static int64_t s_last_render_request_ms = 0;
static int s_render_sequence = 0;
static int s_last_logged_draw_sequence = 0;
#if ELMC_PEBBLE_FEATURE_DRAW_VECTOR_SEQUENCE_AT
static int64_t s_vector_sequence_anim_start_ms = 0;
static int s_vector_sequence_anim_origin_seq = 0;
static AppTimer *s_vector_sequence_timer = NULL;
static uint32_t s_cached_sequence_resource_id = ELM_PEBBLE_RESOURCE_ID_MISSING;
static GDrawCommandSequence *s_cached_sequence = NULL;
#endif
#if ELMC_PEBBLE_FEATURE_DRAW_VECTOR_AT
#define VECTOR_IMAGE_CACHE_CAPACITY 8

typedef struct {
  uint32_t resource_id;
  GDrawCommandImage *image;
} VectorImageCacheEntry;

static VectorImageCacheEntry s_vector_image_cache[VECTOR_IMAGE_CACHE_CAPACITY];
#endif
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
static bool s_last_companion_request_valid = false;
static int s_last_companion_request_tag = 0;
static int s_last_companion_request_value = 0;
#endif
#if ELMC_PEBBLE_FEATURE_COMPASS_EVENTS || ELMC_PEBBLE_FEATURE_CMD_COMPASS_PEEK
static double s_simulator_compass_heading_degrees = 180.0;
static bool s_simulator_compass_heading_valid = true;
#endif
#if ELMC_PEBBLE_FEATURE_DICTATION_EVENTS || ELMC_PEBBLE_FEATURE_CMD_DICTATION_START || ELMC_PEBBLE_FEATURE_CMD_DICTATION_STOP
static char s_simulator_dictation_text[128] = "Hello";
#ifdef PBL_DICTATION
static DictationSession *s_dictation_session = NULL;
#endif
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
static void schedule_render_model(void);
static void render_coalesce_callback(void *data);
static void apply_pending_cmd(void);
static void startup_cmd_callback(void *data);
static ElmcValue *build_launch_context(AppLaunchReason launch);
#if ELMC_PEBBLE_FEATURE_CMD_COMPANION_SEND
static bool send_companion_request(int request_tag, int request_value);
static void flush_pending_companion_request(void);
static void companion_resync_callback(void *data);
#endif

#if ELMC_PEBBLE_STARTUP_SERVICE_SUBSCRIPTIONS && (ELMC_PEBBLE_FEATURE_TICK_EVENTS || ELMC_PEBBLE_FEATURE_HOUR_EVENTS || ELMC_PEBBLE_FEATURE_MINUTE_EVENTS || ELMC_PEBBLE_FEATURE_DAY_EVENTS || ELMC_PEBBLE_FEATURE_MONTH_EVENTS || ELMC_PEBBLE_FEATURE_YEAR_EVENTS)
static TimeUnits subscribed_time_units(void) {
  TimeUnits units = 0;
#if ELMC_PEBBLE_FEATURE_TICK_EVENTS
  units |= SECOND_UNIT;
#endif
#if ELMC_PEBBLE_FEATURE_MINUTE_EVENTS
  units |= MINUTE_UNIT;
#endif
#if ELMC_PEBBLE_FEATURE_HOUR_EVENTS
  units |= HOUR_UNIT;
#endif
#if ELMC_PEBBLE_FEATURE_DAY_EVENTS
  units |= DAY_UNIT;
#endif
#if ELMC_PEBBLE_FEATURE_MONTH_EVENTS
  units |= MONTH_UNIT;
#endif
#if ELMC_PEBBLE_FEATURE_YEAR_EVENTS
  units |= YEAR_UNIT;
#endif
  return units == 0 ? SECOND_UNIT : units;
}
#endif

static GFont system_font_for_height(int64_t requested_height) {
  GFont font = NULL;
  if (requested_height <= 18) font = fonts_get_system_font(FONT_KEY_GOTHIC_18_BOLD);
  if (!font && requested_height <= 28) font = fonts_get_system_font(FONT_KEY_GOTHIC_24_BOLD);
  if (!font && requested_height <= 36) font = fonts_get_system_font(FONT_KEY_GOTHIC_28_BOLD);
  if (!font && requested_height <= 52) font = fonts_get_system_font(FONT_KEY_BITHAM_42_BOLD);
  if (!font) font = fonts_get_system_font(FONT_KEY_BITHAM_42_BOLD);
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

#if ELMC_PEBBLE_FEATURE_COMPASS_EVENTS || ELMC_PEBBLE_FEATURE_CMD_COMPASS_PEEK
static double simulator_compass_heading_degrees(void) {
  return s_simulator_compass_heading_valid ? s_simulator_compass_heading_degrees : 0.0;
}

static bool simulator_compass_heading_is_valid(void) {
  return s_simulator_compass_heading_valid;
}

static void simulator_compass_set_heading(int32_t degrees, bool valid) {
  if (degrees < 0) {
    degrees = 0;
  }
  if (degrees >= 360) {
    degrees = degrees % 360;
  }
  s_simulator_compass_heading_degrees = (double)degrees;
  s_simulator_compass_heading_valid = valid;
}
#endif

#if ELMC_PEBBLE_FEATURE_DICTATION_EVENTS || ELMC_PEBBLE_FEATURE_CMD_DICTATION_START || ELMC_PEBBLE_FEATURE_CMD_DICTATION_STOP
static void simulator_dictation_set_text(const char *text) {
  if (!text) {
    s_simulator_dictation_text[0] = '\0';
    return;
  }
  strncpy(s_simulator_dictation_text, text, sizeof(s_simulator_dictation_text) - 1);
  s_simulator_dictation_text[sizeof(s_simulator_dictation_text) - 1] = '\0';
}

static bool dictation_phone_connected(void) {
  return connection_service_peek_pebble_app_connection();
}

static bool dictation_has_microphone(void) {
#ifdef PBL_MICROPHONE
  return true;
#else
  return false;
#endif
}
#endif

#if ELMC_PEBBLE_FEATURE_CMD_VIBES_CUSTOM_PATTERN || ELMC_PEBBLE_FEATURE_CMD_DATA_LOG_BYTES
static int parse_int_list(const char *text, int32_t *out_values, int max_values) {
  if (!text || !out_values || max_values <= 0) {
    return 0;
  }

  int count = 0;
  const char *cursor = text;
  while (*cursor && count < max_values) {
    char *end = NULL;
    long value = strtol(cursor, &end, 10);
    if (end == cursor) {
      break;
    }
    out_values[count++] = (int32_t)value;
    if (*end == ',') {
      cursor = end + 1;
    } else {
      break;
    }
  }
  return count;
}
#endif

#if ELMC_PEBBLE_FEATURE_ACCEL_DATA_EVENTS
static AccelSamplingRate accel_sampling_rate_from_hz(int hz) {
  switch (hz) {
    case 10:
      return ACCEL_SAMPLING_10HZ;
    case 50:
      return ACCEL_SAMPLING_50HZ;
    case 100:
      return ACCEL_SAMPLING_100HZ;
    case 25:
    default:
      return ACCEL_SAMPLING_25HZ;
  }
}
#endif

#if ELMC_PEBBLE_FEATURE_CMD_COMPASS_PEEK
static int dispatch_compass_current_result(int64_t target, double degrees, bool is_valid, int error_code) {
  if (target <= 0) {
    return -6;
  }

  if (is_valid) {
    const char *names[] = {"degrees", "isValid"};
    ElmcValue *values[2];
    values[0] = elmc_new_float(degrees);
    values[1] = elmc_new_bool(1);
    if (!values[0] || !values[1]) {
      if (values[0]) elmc_release(values[0]);
      if (values[1]) elmc_release(values[1]);
      return -2;
    }
    ElmcValue *heading = elmc_record_new(2, names, values);
    elmc_release(values[0]);
    elmc_release(values[1]);
    if (!heading) {
      return -2;
    }
    ElmcValue *result = elmc_result_ok(heading);
    elmc_release(heading);
    if (!result) {
      return -2;
    }
    int rc = elmc_pebble_dispatch_tag_payload(&s_elm_app, target, result);
    elmc_release(result);
    return rc;
  }

  ElmcValue *error_value = elmc_new_int(error_code);
  if (!error_value) {
    return -2;
  }
  ElmcValue *result = elmc_result_err(error_value);
  elmc_release(error_value);
  if (!result) {
    return -2;
  }
  int rc = elmc_pebble_dispatch_tag_payload(&s_elm_app, target, result);
  elmc_release(result);
  return rc;
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
      ELMC_PEBBLE_STORAGE_LOG(APP_LOG_LEVEL_INFO, "cmd storage_write key=%lu value=%ld status=%ld",
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
      ELMC_PEBBLE_STORAGE_LOG(APP_LOG_LEVEL_INFO, "cmd storage_read key=%lu value=%ld rc=%d",
              (unsigned long)key, (long)value, rc);
      break;
    }
#endif
#if ELMC_PEBBLE_FEATURE_CMD_STORAGE_WRITE_STRING
    case ELMC_PEBBLE_CMD_STORAGE_WRITE_STRING: {
      uint32_t key = (uint32_t)cmd.p0;
      status_t status = persist_write_string(key, cmd.text);
      ELMC_PEBBLE_STORAGE_LOG(APP_LOG_LEVEL_INFO, "cmd storage_write_string key=%lu value=%s status=%ld",
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
      ELMC_PEBBLE_STORAGE_LOG(APP_LOG_LEVEL_INFO, "cmd storage_read_string key=%lu value=%s rc=%d",
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
      (void)rc;
      break;
    }
#endif
#if ELMC_PEBBLE_FEATURE_CMD_STORAGE_DELETE
    case ELMC_PEBBLE_CMD_STORAGE_DELETE: {
      uint32_t key = (uint32_t)cmd.p0;
      status_t status = persist_delete(key);
      ELMC_PEBBLE_STORAGE_LOG(APP_LOG_LEVEL_INFO, "cmd storage_delete key=%lu status=%ld",
              (unsigned long)key, (long)status);
      break;
    }
#endif
#if ELMC_PEBBLE_FEATURE_CMD_COMPANION_SEND
    case ELMC_PEBBLE_CMD_COMPANION_SEND: {
      int request_tag = (int)cmd.p0;
      int request_value = (int)cmd.p1;
      s_last_companion_request_tag = request_tag;
      s_last_companion_request_value = request_value;
      s_last_companion_request_valid = true;
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
#if ELMC_PEBBLE_FEATURE_CMD_VIBES_CUSTOM_PATTERN
    case ELMC_PEBBLE_CMD_VIBES_CUSTOM_PATTERN: {
      int32_t segments[64];
      int count = parse_int_list(cmd.text, segments, 64);
      if (count > 0) {
        vibes_enqueue_custom_pattern(segments, count);
      }
      APP_LOG(APP_LOG_LEVEL_INFO, "cmd vibes_custom_pattern count=%d", count);
      break;
    }
#endif
#if ELMC_PEBBLE_FEATURE_CMD_DATA_LOG_BYTES
    case ELMC_PEBBLE_CMD_DATA_LOG_BYTES: {
      int32_t bytes[64];
      int count = parse_int_list(cmd.text, bytes, 64);
      if (count > 0) {
        uint8_t payload[64];
        for (int i = 0; i < count; i++) {
          int value = bytes[i];
          if (value < 0) value = 0;
          if (value > 255) value = 255;
          payload[i] = (uint8_t)value;
        }
        DataLoggingSessionRef session =
            data_logging_create((uint32_t)cmd.p0, DATA_LOGGING_BYTE_ARRAY, count, true);
        if (session) {
          data_logging_log(session, payload, count);
          data_logging_finish(session);
        }
      }
      APP_LOG(APP_LOG_LEVEL_INFO, "cmd data_log_bytes tag=%ld count=%d", (long)cmd.p0, count);
      break;
    }
#endif
#if ELMC_PEBBLE_FEATURE_CMD_DATA_LOG_INT32
    case ELMC_PEBBLE_CMD_DATA_LOG_INT32: {
      uint32_t payload = (uint32_t)cmd.p1;
      DataLoggingSessionRef session =
          data_logging_create((uint32_t)cmd.p0, DATA_LOGGING_UINT, 1, true);
      if (session) {
        data_logging_log(session, &payload, 1);
        data_logging_finish(session);
      }
      APP_LOG(APP_LOG_LEVEL_INFO, "cmd data_log_int32 tag=%ld value=%ld", (long)cmd.p0, (long)cmd.p1);
      break;
    }
#endif
#if ELMC_PEBBLE_FEATURE_CMD_COMPASS_PEEK
    case ELMC_PEBBLE_CMD_COMPASS_PEEK: {
      double degrees = simulator_compass_heading_degrees();
      bool is_valid = simulator_compass_heading_is_valid();
#ifdef PBL_COMPASS
      CompassHeadingData heading;
      CompassStatus status = compass_service_peek(&heading);
      if (status == CompassStatusAvailable) {
        degrees = (double)heading.true_heading * 360.0 / TRIG_MAX_ANGLE;
        is_valid = true;
      } else if (status == CompassStatusDataInvalid) {
        is_valid = false;
      } else {
        is_valid = false;
      }
#endif
      int error_code = is_valid ? 0 : 1;
      int rc = dispatch_compass_current_result(cmd.p0, degrees, is_valid, error_code);
      APP_LOG(APP_LOG_LEVEL_INFO, "cmd compass_peek degrees=%ld valid=%d rc=%d",
              (long)degrees, is_valid ? 1 : 0, rc);
      if (rc == 0) {
        apply_pending_cmd();
        render_model();
      }
      break;
    }
#endif
#if ELMC_PEBBLE_FEATURE_CMD_UNOBSTRUCTED_BOUNDS_PEEK
    case ELMC_PEBBLE_CMD_UNOBSTRUCTED_BOUNDS_PEEK: {
      GRect bounds = current_unobstructed_bounds();
      int rc = dispatch_unobstructed_bounds_result(cmd.p0, bounds);
      APP_LOG(APP_LOG_LEVEL_INFO, "cmd unobstructed_bounds_peek x=%ld y=%ld w=%ld h=%ld rc=%d",
              (long)bounds.origin.x, (long)bounds.origin.y, (long)bounds.size.w,
              (long)bounds.size.h, rc);
      if (rc == 0) {
        apply_pending_cmd();
        render_model();
      }
      break;
    }
#endif
#if ELMC_PEBBLE_FEATURE_CMD_DICTATION_START
    case ELMC_PEBBLE_CMD_DICTATION_START: {
      if (!dictation_has_microphone()) {
        elmc_pebble_dispatch_dictation_result(&s_elm_app, 0, 0, NULL);
      } else if (!dictation_phone_connected()) {
        elmc_pebble_dispatch_dictation_result(&s_elm_app, 0, 1, NULL);
      } else {
#ifdef PBL_DICTATION
        if (!s_dictation_session) {
          s_dictation_session = dictation_session_create(30000, dictation_session_callback, NULL);
        }
        if (s_dictation_session) {
          elmc_pebble_dispatch_dictation_status(&s_elm_app, 0);
          dictation_session_start(s_dictation_session);
        }
#else
        elmc_pebble_dispatch_dictation_status(&s_elm_app, 0);
        elmc_pebble_dispatch_dictation_status(&s_elm_app, 1);
        elmc_pebble_dispatch_dictation_status(&s_elm_app, 2);
        elmc_pebble_dispatch_dictation_result(&s_elm_app, 1, 0, s_simulator_dictation_text);
#endif
      }
      APP_LOG(APP_LOG_LEVEL_INFO, "cmd dictation_start");
      break;
    }
#endif
#if ELMC_PEBBLE_FEATURE_CMD_DICTATION_STOP
    case ELMC_PEBBLE_CMD_DICTATION_STOP: {
#ifdef PBL_DICTATION
      if (s_dictation_session) {
        dictation_session_stop(s_dictation_session);
      }
#else
      elmc_pebble_dispatch_dictation_result(&s_elm_app, 0, 2, NULL);
#endif
      APP_LOG(APP_LOG_LEVEL_INFO, "cmd dictation_stop");
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

#if ELMC_PEBBLE_FEATURE_DRAW_TEXT
static GTextAlignment text_alignment_from_options(int32_t options) {
  switch (options & 0x3) {
  case 0:
    return GTextAlignmentLeft;
  case 2:
    return GTextAlignmentRight;
  case 1:
  default:
    return GTextAlignmentCenter;
  }
}

static GTextOverflowMode text_overflow_from_options(int32_t options) {
  switch ((options >> 2) & 0x3) {
  case 1:
    return GTextOverflowModeTrailingEllipsis;
  case 2:
    return GTextOverflowModeFill;
  case 0:
  default:
    return GTextOverflowModeWordWrap;
  }
}
#endif

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

#if ELMC_PEBBLE_FEATURE_DRAW_TEXT_INT || ELMC_PEBBLE_FEATURE_DRAW_TEXT_LABEL
static GRect text_point_rect(GRect bounds, int64_t x, int64_t y) {
  int width = bounds.size.w - (int)x;
  int height = bounds.size.h - (int)y;
  if (width < 1) width = 1;
  if (height < 1) height = 1;
  return GRect((int16_t)x, (int16_t)y, (int16_t)width, (int16_t)height);
}
#endif

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

#if ELMC_PEBBLE_FEATURE_DRAW_VECTOR_SEQUENCE_AT
static void vector_sequence_timer_callback(void *data) {
  (void)data;
  s_vector_sequence_timer = NULL;
  layer_mark_dirty(s_draw_layer);
}

static void vector_sequence_cache_clear(void) {
  if (s_cached_sequence) {
    gdraw_command_sequence_destroy(s_cached_sequence);
    s_cached_sequence = NULL;
  }
  s_cached_sequence_resource_id = ELM_PEBBLE_RESOURCE_ID_MISSING;
}

static GDrawCommandSequence *vector_sequence_cached(uint32_t resource_id) {
  if (resource_id == ELM_PEBBLE_RESOURCE_ID_MISSING) {
    return NULL;
  }
  if (s_cached_sequence && s_cached_sequence_resource_id == resource_id) {
    return s_cached_sequence;
  }
  vector_sequence_cache_clear();
  s_cached_sequence_resource_id = resource_id;
  s_cached_sequence = gdraw_command_sequence_create_with_resource(resource_id);
  if (!s_cached_sequence) {
    APP_LOG(APP_LOG_LEVEL_WARNING, "vector sequence load failed resource_id=%lu", (unsigned long)resource_id);
  }
  return s_cached_sequence;
}
#endif

#if ELMC_PEBBLE_FEATURE_DRAW_VECTOR_AT
static void vector_image_cache_clear(void) {
  for (int i = 0; i < VECTOR_IMAGE_CACHE_CAPACITY; i++) {
    if (s_vector_image_cache[i].image) {
      gdraw_command_image_destroy(s_vector_image_cache[i].image);
      s_vector_image_cache[i].image = NULL;
    }
    s_vector_image_cache[i].resource_id = ELM_PEBBLE_RESOURCE_ID_MISSING;
  }
}

static GDrawCommandImage *vector_image_cached(uint32_t resource_id) {
  int empty_slot = -1;

  if (resource_id == ELM_PEBBLE_RESOURCE_ID_MISSING) {
    return NULL;
  }

  for (int i = 0; i < VECTOR_IMAGE_CACHE_CAPACITY; i++) {
    if (s_vector_image_cache[i].resource_id == resource_id && s_vector_image_cache[i].image) {
      return s_vector_image_cache[i].image;
    }
    if (empty_slot < 0 && s_vector_image_cache[i].image == NULL) {
      empty_slot = i;
    }
  }

  {
    int slot = empty_slot >= 0 ? empty_slot : 0;
    if (s_vector_image_cache[slot].image) {
      gdraw_command_image_destroy(s_vector_image_cache[slot].image);
    }
    s_vector_image_cache[slot].resource_id = resource_id;
    s_vector_image_cache[slot].image = gdraw_command_image_create_with_resource(resource_id);
    if (!s_vector_image_cache[slot].image) {
      APP_LOG(APP_LOG_LEVEL_WARNING, "vector image load failed resource_id=%lu", (unsigned long)resource_id);
    }
    return s_vector_image_cache[slot].image;
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
        if (x1 != x2 || y1 != y2) {
          graphics_context_set_stroke_color(ctx, color_from_code(cmd->p4));
          graphics_draw_line(ctx, GPoint(x1, y1), GPoint(x2, y2));
          graphics_context_set_stroke_color(ctx, style_stack[style_top].stroke_color);
        }
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
                           text_point_rect(bounds, cmd->p1, cmd->p2),
                           GTextOverflowModeWordWrap,
                           GTextAlignmentLeft, NULL);
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
        if (cmd->text[0] != '\0') {
          label = cmd->text;
        } else if (cmd->p3 == 0) {
          label = "Waiting for companion app";
        }
        graphics_draw_text(ctx, label, font,
                           text_point_rect(bounds, cmd->p1, cmd->p2),
                           GTextOverflowModeWordWrap,
                           GTextAlignmentLeft, NULL);
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
                             text_overflow_from_options(cmd->p5),
                             text_alignment_from_options(cmd->p5), NULL);
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
#if ELMC_PEBBLE_FEATURE_DRAW_VECTOR_AT
      case ELMC_PEBBLE_DRAW_VECTOR_AT: {
        uint32_t resource_id = elm_pebble_vector_resource_id(cmd->p0);
        GDrawCommandImage *image = vector_image_cached(resource_id);
        if (!image) {
          break;
        }
        gdraw_command_image_draw(ctx, image, GPoint(cmd->p1, cmd->p2));
        break;
      }
#endif
#if ELMC_PEBBLE_FEATURE_DRAW_VECTOR_SEQUENCE_AT
      case ELMC_PEBBLE_DRAW_VECTOR_SEQUENCE_AT: {
        uint32_t resource_id = elm_pebble_vector_resource_id(cmd->p0);
        GDrawCommandSequence *sequence = vector_sequence_cached(resource_id);
        if (!sequence) {
          break;
        }
        if (s_vector_sequence_anim_origin_seq != s_render_sequence) {
          s_vector_sequence_anim_start_ms = monotonic_ms();
          s_vector_sequence_anim_origin_seq = s_render_sequence;
        }
        uint32_t elapsed = (uint32_t)(monotonic_ms() - s_vector_sequence_anim_start_ms);
        GDrawCommandFrame *frame = gdraw_command_sequence_get_frame_by_elapsed(sequence, elapsed);
        if (frame) {
          gdraw_command_frame_draw(ctx, sequence, frame, GPoint(cmd->p1, cmd->p2));
        }
        uint32_t total_duration = gdraw_command_sequence_get_total_duration(sequence);
        uint16_t play_count = gdraw_command_sequence_get_play_count(sequence);
        bool animating = false;
        if (play_count == 0xFFFF && total_duration > 0) {
          animating = true;
        } else if (play_count > 0 && total_duration > 0) {
          animating = elapsed < (uint32_t)total_duration * (uint32_t)play_count;
        }
        if (animating && !s_vector_sequence_timer) {
          s_vector_sequence_timer = app_timer_register(33, vector_sequence_timer_callback, NULL);
        } else if (!animating) {
          vector_sequence_cache_clear();
        }
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

static void render_coalesce_callback(void *data) {
  ELMC_PEBBLE_TRACE_ENTER("render_coalesce_callback");
  (void)data;
  s_render_coalesce_timer = NULL;
  render_model();
  ELMC_PEBBLE_TRACE_EXIT("render_coalesce_callback");
}

static void schedule_render_model(void) {
  if (s_render_coalesce_timer) {
    return;
  }
  s_render_coalesce_timer = app_timer_register(16, render_coalesce_callback, NULL);
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
  if (!s_draw_layer) {
    s_render_pending = true;
#if ELMC_PEBBLE_EMULATOR_STORAGE_LOGS
    companion_inbox_log("render deferred seq=%d model=%lld", s_render_sequence, (long long)value);
#endif
    ELMC_PEBBLE_TRACE_EXIT("render_model");
    return;
  }
  s_render_pending = false;
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
#if ELMC_PEBBLE_FEATURE_DAY_EVENTS
  if ((units_changed & DAY_UNIT) != 0 && tick_time) {
    int rc = elmc_pebble_dispatch_day(&s_elm_app, tick_time->tm_mday);
    APP_LOG(APP_LOG_LEVEL_INFO, "day dispatch day=%d rc=%d", tick_time->tm_mday, rc);
    if (rc == 0) {
      apply_pending_cmd();
      render_model();
    }
  }
#endif
#if ELMC_PEBBLE_FEATURE_MONTH_EVENTS
  if ((units_changed & MONTH_UNIT) != 0 && tick_time) {
    int month = tick_time->tm_mon + 1;
    int rc = elmc_pebble_dispatch_month(&s_elm_app, month);
    APP_LOG(APP_LOG_LEVEL_INFO, "month dispatch month=%d rc=%d", month, rc);
    if (rc == 0) {
      apply_pending_cmd();
      render_model();
    }
  }
#endif
#if ELMC_PEBBLE_FEATURE_YEAR_EVENTS
  if ((units_changed & YEAR_UNIT) != 0 && tick_time) {
    int year = tick_time->tm_year + 1900;
    int rc = elmc_pebble_dispatch_year(&s_elm_app, year);
    APP_LOG(APP_LOG_LEVEL_INFO, "year dispatch year=%d rc=%d", year, rc);
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

static void companion_resync_callback(void *data) {
  ELMC_PEBBLE_TRACE_ENTER("companion_resync_callback");
  (void)data;
  flush_pending_companion_request();
  if (s_last_companion_request_valid) {
    (void)send_companion_request(s_last_companion_request_tag, s_last_companion_request_value);
  }
  ELMC_PEBBLE_TRACE_EXIT("companion_resync_callback");
}
#endif

static bool debug_storage_tuple_int(Tuple *tuple, int32_t *out) {
  if (!tuple || !out) {
    return false;
  }
  if (tuple->type == TUPLE_INT) {
    if (tuple->length == sizeof(int8_t)) {
      *out = tuple->value->int8;
    } else if (tuple->length == sizeof(int16_t)) {
      *out = tuple->value->int16;
    } else {
      *out = tuple->value->int32;
    }
    return true;
  }
  if (tuple->type == TUPLE_UINT) {
    if (tuple->length == sizeof(uint8_t)) {
      *out = (int32_t)tuple->value->uint8;
    } else if (tuple->length == sizeof(uint16_t)) {
      *out = (int32_t)tuple->value->uint16;
    } else {
      *out = (int32_t)tuple->value->uint32;
    }
    return true;
  }
  return false;
}

static bool elmc_inbox_snapshot_from_tuple(ElmcInboxTupleSnapshot *snap, const Tuple *source) {
  if (!snap || !source) {
    return false;
  }

  memset(snap, 0, sizeof(*snap));
  snap->key = source->key;
  snap->type = (uint8_t)source->type;
  snap->length = source->length;
  snap->cstring_kind = ELMC_INBOX_CSTRING_NONE;

  switch (source->type) {
    case TUPLE_INT:
      if (source->length == sizeof(int8_t)) {
        snap->int_value = source->value->int8;
      } else if (source->length == sizeof(int16_t)) {
        snap->int_value = source->value->int16;
      } else {
        snap->int_value = source->value->int32;
      }
      return true;
    case TUPLE_UINT:
      if (source->length == sizeof(uint8_t)) {
        snap->int_value = (int32_t)source->value->uint8;
      } else if (source->length == sizeof(uint16_t)) {
        snap->int_value = (int32_t)source->value->uint16;
      } else {
        snap->int_value = (int32_t)source->value->uint32;
      }
      return true;
    case TUPLE_CSTRING: {
      size_t copy_len = source->length > 0 ? (size_t)source->length : 1;
      if (copy_len > ELMC_INBOX_STRING_MAX) {
        copy_len = ELMC_INBOX_STRING_MAX;
      }
      memcpy(s_inbox_cstring_snapshot, source->value->cstring, copy_len);
      s_inbox_cstring_snapshot[ELMC_INBOX_STRING_MAX - 1] = '\0';
      snap->length = (uint16_t)(strlen(s_inbox_cstring_snapshot) + 1);
      snap->cstring_kind = ELMC_INBOX_CSTRING_INBOX;
      return true;
    }
    default:
      return false;
  }
}

static Tuple *elmc_inbox_materialize_tuple(const ElmcInboxTupleSnapshot *snap, uint8_t *int_wire) {
  if (!snap) {
    return NULL;
  }

  if (snap->type == TUPLE_CSTRING && snap->cstring_kind == ELMC_INBOX_CSTRING_INBOX) {
    Tuple *tuple = (Tuple *)s_inbox_cstring_tuple_wire;
    memset(s_inbox_cstring_tuple_wire, 0, sizeof(s_inbox_cstring_tuple_wire));
    tuple->key = snap->key;
    tuple->type = TUPLE_CSTRING;
    tuple->length = snap->length;
    memcpy(tuple->value->cstring, s_inbox_cstring_snapshot, snap->length);
    return tuple;
  }

  if (!int_wire) {
    return NULL;
  }

  Tuple *tuple = (Tuple *)int_wire;
  memset(int_wire, 0, ELMC_INBOX_TUPLE_WIRE_BYTES);
  tuple->key = snap->key;
  tuple->type = (TupleType)snap->type;
  tuple->length = snap->length;
  if (snap->type == TUPLE_INT) {
    tuple->value->int32 = snap->int_value;
  } else if (snap->type == TUPLE_UINT) {
    tuple->value->uint32 = (uint32_t)snap->int_value;
  }
  return tuple;
}

static int inbox_snapshot_tuples(DictionaryIterator *iter) {
  s_inbox_snapshot_count = 0;
  if (!iter) {
    return 0;
  }

  Tuple *tuple = dict_read_first(iter);
  while (tuple && s_inbox_snapshot_count < ELMC_INBOX_MAX_TUPLES) {
    if (elmc_inbox_snapshot_from_tuple(&s_inbox_snapshots[s_inbox_snapshot_count], tuple)) {
      s_inbox_snapshot_count++;
    }
    tuple = dict_read_next(iter);
  }
  return s_inbox_snapshot_count;
}

static Tuple *inbox_find_tuple(uint32_t key) {
  for (int i = 0; i < s_inbox_snapshot_count; i++) {
    if (s_inbox_snapshots[i].key == key) {
      return elmc_inbox_materialize_tuple(&s_inbox_snapshots[i], s_inbox_tuple_wire[i]);
    }
  }
  return NULL;
}

static Tuple *inbox_tuple_at(int index) {
  if (index < 0 || index >= s_inbox_snapshot_count) {
    return NULL;
  }
  return elmc_inbox_materialize_tuple(&s_inbox_snapshots[index], s_inbox_tuple_wire[index]);
}

static bool handle_debug_storage(void) {
  ELMC_PEBBLE_TRACE_ENTER("handle_debug_storage");
  // #region agent log
  ELMC_AGENT_INIT_PROBE(0xED995100);
  // #endregion
  Tuple *op_tuple = inbox_find_tuple(ELMC_DEBUG_STORAGE_KEY_OP);
  // #region agent log
  ELMC_AGENT_INIT_PROBE(0xED995111);
  // #endregion
  Tuple *key_tuple = inbox_find_tuple(ELMC_DEBUG_STORAGE_KEY_KEY);
  // #region agent log
  ELMC_AGENT_INIT_PROBE(0xED995112);
  // #endregion
  int32_t op = 0;
  int32_t key_value = 0;

  if (!debug_storage_tuple_int(op_tuple, &op)) {
    // #region agent log
    ELMC_AGENT_INIT_PROBE(0xED995101);
    // #endregion
    ELMC_PEBBLE_TRACE_EXIT("handle_debug_storage");
    return false;
  }

  if (op == ELMC_DEBUG_STORAGE_OP_SNAPSHOT) {
#if ELMC_PEBBLE_EMULATOR_STORAGE_LOGS
    emulator_storage_snapshot_callback(NULL);
#endif
    ELMC_PEBBLE_TRACE_EXIT("handle_debug_storage");
    return true;
  }

  if (!debug_storage_tuple_int(key_tuple, &key_value)) {
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
    ELMC_PEBBLE_STORAGE_LOG(APP_LOG_LEVEL_INFO, "debug storage_delete key=%lu status=%ld",
            (unsigned long)key, (long)status);
    (void)status;
    ELMC_PEBBLE_TRACE_EXIT("handle_debug_storage");
    return true;
  }

  int32_t type = 0;
  if (op != ELMC_DEBUG_STORAGE_OP_WRITE ||
      !debug_storage_tuple_int(inbox_find_tuple(ELMC_DEBUG_STORAGE_KEY_TYPE), &type)) {
    // #region agent log
    ELMC_AGENT_INIT_PROBE(0xED9951E1);
    // #endregion
    APP_LOG(APP_LOG_LEVEL_WARNING, "debug storage ignored op=%ld key=%lu",
            (long)op, (unsigned long)key);
    ELMC_PEBBLE_TRACE_EXIT("handle_debug_storage");
    return false;
  }

  if (type == ELMC_DEBUG_STORAGE_TYPE_INT) {
    // #region agent log
    ELMC_AGENT_INIT_PROBE(0xED9951E2);
    // #endregion
    int32_t value = 0;
    if (!debug_storage_tuple_int(inbox_find_tuple(ELMC_DEBUG_STORAGE_KEY_INT_VALUE), &value)) {
      ELMC_PEBBLE_STORAGE_LOG(APP_LOG_LEVEL_WARNING, "debug storage_write missing int key=%lu",
              (unsigned long)key);
      ELMC_PEBBLE_TRACE_EXIT("handle_debug_storage");
      return true;
    }
    status_t status = persist_write_int(key, value);
    ELMC_PEBBLE_STORAGE_LOG(APP_LOG_LEVEL_INFO, "debug storage_write key=%lu value=%ld status=%ld",
            (unsigned long)key, (long)value, (long)status);
    (void)status;
    ELMC_PEBBLE_TRACE_EXIT("handle_debug_storage");
    return true;
  }

  if (type == ELMC_DEBUG_STORAGE_TYPE_STRING) {
    // #region agent log
    ELMC_AGENT_INIT_PROBE(0xED9951E3);
    // #endregion
    Tuple *value_tuple = inbox_find_tuple(ELMC_DEBUG_STORAGE_KEY_STRING_VALUE);
    const char *value = value_tuple && value_tuple->type == TUPLE_CSTRING ? value_tuple->value->cstring : "";
    status_t status = persist_write_string(key, value);
    ELMC_PEBBLE_STORAGE_LOG(APP_LOG_LEVEL_INFO, "debug storage_write_string key=%lu value=%s status=%ld",
            (unsigned long)key, value, (long)status);
    (void)status;
    ELMC_PEBBLE_TRACE_EXIT("handle_debug_storage");
    return true;
  }

  APP_LOG(APP_LOG_LEVEL_WARNING, "debug storage ignored type=%ld key=%lu",
          (long)type, (unsigned long)key);
  ELMC_PEBBLE_TRACE_EXIT("handle_debug_storage");
  return false;
}

#if ELMC_PEBBLE_FEATURE_INBOX_EVENTS
static void companion_pending_clear(void);
#endif

static bool companion_simulator_weather_tuple(const Tuple *tuple) {
#if ELMC_PEBBLE_FEATURE_INBOX_EVENTS
  int32_t wire_value = 0;
  if (!tuple || !debug_storage_tuple_int((Tuple *)tuple, &wire_value)) {
    return false;
  }

  CompanionProtocolPhoneToWatchMessage message = {0};
  if (tuple->key == ELMC_DEBUG_SIMULATOR_KEY_WEATHER_TEMPERATURE_C) {
    message.kind = COMPANION_PROTOCOL_PHONE_TO_WATCH_KIND_PROVIDE_TEMPERATURE;
    message.int_fields[0] = 1; /* Celsius wire code */
    message.union_value_fields[0] = wire_value;
  } else if (tuple->key == ELMC_DEBUG_SIMULATOR_KEY_WEATHER_CONDITION_WIRE) {
    message.kind = COMPANION_PROTOCOL_PHONE_TO_WATCH_KIND_PROVIDE_CONDITION;
    message.int_fields[0] = wire_value;
  } else {
    return false;
  }

  int rc = companion_protocol_dispatch_phone_to_watch(&s_elm_app, &message);
#if ELMC_PEBBLE_EMULATOR_STORAGE_LOGS
  companion_inbox_log("simulator weather key=%lu value=%ld rc=%d",
                      (unsigned long)tuple->key, (long)wire_value, rc);
#endif
  if (rc == 0) {
    companion_pending_clear();
    s_agent_after_companion_dispatch = true;
    apply_pending_cmd();
  }
  return rc == 0;
#else
  (void)tuple;
  return false;
#endif
}

#if ELMC_PEBBLE_FEATURE_CMD_COMPANION_SEND || ELMC_PEBBLE_FEATURE_INBOX_EVENTS
static bool companion_decode_and_dispatch_snapshots(const ElmcInboxTupleSnapshot *snapshots, uint8_t wire[][ELMC_INBOX_TUPLE_WIRE_BYTES], int tuple_count) {
  CompanionProtocolPhoneToWatchDecoder decoder;
  companion_protocol_phone_to_watch_decoder_init(&decoder);

  for (int i = 0; i < tuple_count; i++) {
    Tuple *tuple = elmc_inbox_materialize_tuple(&snapshots[i], wire[i]);
    if (!tuple) {
      continue;
    }
    companion_protocol_phone_to_watch_decoder_push_tuple(&decoder, tuple);
  }

  CompanionProtocolPhoneToWatchMessage message = {0};
  if (companion_protocol_phone_to_watch_decoder_finish(&decoder, &message) &&
      message.kind != COMPANION_PROTOCOL_PHONE_TO_WATCH_KIND_UNKNOWN) {
    int rc = companion_protocol_dispatch_phone_to_watch(&s_elm_app, &message);
    APP_LOG(APP_LOG_LEVEL_INFO, "companion response kind=%d rc=%d", (int)message.kind, rc);
#if ELMC_PEBBLE_EMULATOR_STORAGE_LOGS
    companion_inbox_log("companion dispatch kind=%d rc=%d", (int)message.kind, rc);
#endif
    if (rc == 0) {
      s_agent_after_companion_dispatch = true;
      apply_pending_cmd();
      schedule_render_model();
      return true;
    }
    layer_mark_dirty(s_draw_layer);
    return false;
  }

  APP_LOG(APP_LOG_LEVEL_WARNING, "companion decode failed saw_tag=%d tag=%ld tuples=%d",
          decoder.saw_tag ? 1 : 0, (long)decoder.tag, tuple_count);
#if ELMC_PEBBLE_EMULATOR_STORAGE_LOGS
  companion_inbox_log("companion decode failed saw_tag=%d tag=%ld tuples=%d",
                      decoder.saw_tag ? 1 : 0, (long)decoder.tag, tuple_count);
#endif

  for (int i = 0; i < tuple_count; i++) {
    Tuple *tuple = elmc_inbox_materialize_tuple(&snapshots[i], wire[i]);
    if (!tuple || (tuple->type != TUPLE_INT && tuple->type != TUPLE_UINT)) {
      continue;
    }
    int32_t wire_value = 0;
    if (!debug_storage_tuple_int(tuple, &wire_value)) {
      continue;
    }
    int rc = elmc_pebble_dispatch_appmessage(&s_elm_app, tuple->key, wire_value);
    APP_LOG(APP_LOG_LEVEL_INFO, "appmessage key=%lu value=%ld rc=%d",
            (unsigned long)tuple->key, (long)wire_value, rc);
    if (rc == 0) {
      apply_pending_cmd();
      schedule_render_model();
    }
  }
  return false;
}
#endif

#if ELMC_PEBBLE_FEATURE_INBOX_EVENTS
#define COMPANION_PENDING_FLUSH_MS 250
#define COMPANION_PENDING_MAX_AGE_MS 2500

static int s_companion_pending_count = 0;
static int64_t s_companion_pending_first_ms = 0;
static AppTimer *s_companion_pending_timer = NULL;

static void schedule_companion_pending_flush(void);
static int32_t companion_pending_message_tag(void);

static void companion_pending_clear(void) {
  s_companion_pending_count = 0;
  s_companion_pending_first_ms = 0;
  if (s_companion_pending_timer) {
    app_timer_cancel(s_companion_pending_timer);
    s_companion_pending_timer = NULL;
  }
}

static bool companion_try_decode_pending(void) {
  if (s_companion_pending_count <= 0) {
    return false;
  }

  CompanionProtocolPhoneToWatchDecoder decoder;
  companion_protocol_phone_to_watch_decoder_init(&decoder);

  for (int i = 0; i < s_companion_pending_count; i++) {
    Tuple *tuple = elmc_inbox_materialize_tuple(&s_companion_pending[i], s_companion_pending_wire[i]);
    if (!tuple) {
      continue;
    }
    companion_protocol_phone_to_watch_decoder_push_tuple(&decoder, tuple);
  }

  CompanionProtocolPhoneToWatchMessage message = {0};
  if (!companion_protocol_phone_to_watch_decoder_finish(&decoder, &message) ||
      message.kind == COMPANION_PROTOCOL_PHONE_TO_WATCH_KIND_UNKNOWN) {
#if ELMC_PEBBLE_EMULATOR_STORAGE_LOGS
    companion_inbox_log("companion pending decode failed saw_tag=%d tag=%ld tuples=%d",
                        decoder.saw_tag ? 1 : 0, (long)decoder.tag, s_companion_pending_count);
#endif
    return false;
  }

  int rc = companion_protocol_dispatch_phone_to_watch(&s_elm_app, &message);
#if ELMC_PEBBLE_EMULATOR_STORAGE_LOGS
  companion_inbox_log("companion pending dispatch kind=%d rc=%d tuples=%d",
                      (int)message.kind, rc, s_companion_pending_count);
#endif
  if (rc != 0) {
    return false;
  }

  s_agent_after_companion_dispatch = true;
  apply_pending_cmd();
  schedule_render_model();
  return true;
}

static void companion_pending_flush(void *data) {
  (void)data;
  s_companion_pending_timer = NULL;
  if (s_companion_pending_count <= 0) {
    return;
  }

  if (companion_try_decode_pending()) {
    companion_pending_clear();
    return;
  }

  int64_t age_ms = monotonic_ms() - s_companion_pending_first_ms;
  if (age_ms >= COMPANION_PENDING_MAX_AGE_MS) {
#if ELMC_PEBBLE_EMULATOR_STORAGE_LOGS
    companion_inbox_log("companion pending expired age=%lld count=%d tag=%ld",
                        (long long)age_ms, s_companion_pending_count,
                        (long)companion_pending_message_tag());
#endif
    companion_pending_clear();
    return;
  }

  schedule_companion_pending_flush();
}

static void schedule_companion_pending_flush(void) {
  if (s_companion_pending_timer) {
    app_timer_cancel(s_companion_pending_timer);
  }
  s_companion_pending_timer = app_timer_register(COMPANION_PENDING_FLUSH_MS, companion_pending_flush, NULL);
}

static int32_t companion_pending_message_tag(void) {
  for (int i = 0; i < s_companion_pending_count; i++) {
    if (s_companion_pending[i].key == COMPANION_PROTOCOL_KEY_MESSAGE_TAG) {
      return s_companion_pending[i].int_value;
    }
  }
  return 0;
}

static void companion_pending_append(void) {
  if (s_inbox_snapshot_count <= 0) {
    return;
  }

  for (int i = 0; i < s_inbox_snapshot_count; i++) {
    const ElmcInboxTupleSnapshot *snap = &s_inbox_snapshots[i];

    if (snap->key == COMPANION_PROTOCOL_KEY_MESSAGE_TAG && s_companion_pending_count > 0) {
      int32_t pending_tag = companion_pending_message_tag();
      if (pending_tag != 0 && pending_tag != snap->int_value) {
        if (!companion_try_decode_pending()) {
#if ELMC_PEBBLE_EMULATOR_STORAGE_LOGS
          companion_inbox_log("companion pending tag switch %ld -> %ld dropped=%d",
                              (long)pending_tag, (long)snap->int_value, s_companion_pending_count);
#endif
        }
        companion_pending_clear();
      }
    }

    if (s_companion_pending_count >= ELMC_INBOX_MAX_TUPLES) {
      companion_pending_clear();
    }

    if (s_companion_pending_count == 0) {
      s_companion_pending_first_ms = monotonic_ms();
    }

    s_companion_pending[s_companion_pending_count] = *snap;
    s_companion_pending[s_companion_pending_count].cstring_kind = ELMC_INBOX_CSTRING_NONE;
    memcpy(
        s_companion_pending_wire[s_companion_pending_count],
        s_inbox_tuple_wire[i],
        ELMC_INBOX_TUPLE_WIRE_BYTES);
    s_companion_pending_count++;

    if (companion_try_decode_pending()) {
      companion_pending_clear();
      continue;
    }

    schedule_companion_pending_flush();
  }
}
#endif

static bool handle_debug_simulator_settings(void) {
#if ELMC_PEBBLE_FEATURE_COMPASS_EVENTS || ELMC_PEBBLE_FEATURE_CMD_COMPASS_PEEK || ELMC_PEBBLE_FEATURE_DICTATION_EVENTS || ELMC_PEBBLE_FEATURE_CMD_DICTATION_START || ELMC_PEBBLE_FEATURE_CMD_DICTATION_STOP || ELMC_PEBBLE_FEATURE_INBOX_EVENTS
  bool handled = false;

  for (int i = 0; i < s_inbox_snapshot_count; i++) {
    const Tuple *tuple = inbox_tuple_at(i);
    if (!tuple) {
      continue;
    }
#if ELMC_PEBBLE_FEATURE_INBOX_EVENTS
    if (companion_simulator_weather_tuple(tuple)) {
      handled = true;
    }
#endif
#if ELMC_PEBBLE_FEATURE_COMPASS_EVENTS || ELMC_PEBBLE_FEATURE_CMD_COMPASS_PEEK
    if (tuple->key == ELMC_DEBUG_SIMULATOR_KEY_COMPASS_HEADING &&
        (tuple->type == TUPLE_INT || tuple->type == TUPLE_UINT)) {
      simulator_compass_set_heading(tuple->value->int32, true);
      handled = true;
    }
#endif
#if ELMC_PEBBLE_FEATURE_DICTATION_EVENTS || ELMC_PEBBLE_FEATURE_CMD_DICTATION_START || ELMC_PEBBLE_FEATURE_CMD_DICTATION_STOP
    if (tuple->key == ELMC_DEBUG_SIMULATOR_KEY_DICTATION_TEXT && tuple->type == TUPLE_CSTRING) {
      simulator_dictation_set_text((const char *)tuple->value->cstring);
      handled = true;
    }
#endif
  }

  return handled;
#else
  (void)0;
  return false;
#endif
}

static void inbox_received_handler(DictionaryIterator *iter, void *context) {
  ELMC_PEBBLE_TRACE_ENTER("inbox_received_handler");
  // #region agent log
  ELMC_AGENT_INIT_PROBE(0xED995001);
  // #endregion
  (void)context;
  inbox_snapshot_tuples(iter);
#if ELMC_PEBBLE_EMULATOR_STORAGE_LOGS
  companion_inbox_log("inbox tuples=%d", s_inbox_snapshot_count);
  for (int i = 0; i < s_inbox_snapshot_count; i++) {
    companion_inbox_log("  key=%lu type=%d value=%ld",
                        (unsigned long)s_inbox_snapshots[i].key,
                        (int)s_inbox_snapshots[i].type,
                        (long)s_inbox_snapshots[i].int_value);
  }
#endif

  if (handle_debug_storage()) {
    ELMC_PEBBLE_TRACE_EXIT("inbox_received_handler");
    return;
  }
  if (handle_debug_simulator_settings()) {
    apply_pending_cmd();
    render_model();
    ELMC_PEBBLE_TRACE_EXIT("inbox_received_handler");
    return;
  }

#if ELMC_PEBBLE_FEATURE_INBOX_EVENTS
  // #region agent log
  ELMC_AGENT_INIT_PROBE(0xED995201);
  // #endregion
  if (s_inbox_snapshot_count > 1 &&
      companion_decode_and_dispatch_snapshots(
          s_inbox_snapshots, s_inbox_tuple_wire, s_inbox_snapshot_count)) {
    companion_pending_clear();
    ELMC_PEBBLE_TRACE_EXIT("inbox_received_handler");
    return;
  }
  companion_pending_append();
  schedule_companion_pending_flush();
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

#if ELMC_PEBBLE_FEATURE_BUTTON_EVENTS || ELMC_PEBBLE_FEATURE_RAW_BUTTON_EVENTS
static void note_user_interaction(void) {
  light_enable_interaction();
}
#endif

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

#if ELMC_PEBBLE_FEATURE_APP_FOCUS_EVENTS
static void app_focus_handler(bool in_focus) {
  ELMC_PEBBLE_TRACE_ENTER("app_focus_handler");
  int rc = elmc_pebble_dispatch_app_focus(&s_elm_app, in_focus ? 1 : 0);
  APP_LOG(APP_LOG_LEVEL_INFO, "app focus in_focus=%d rc=%d", in_focus ? 1 : 0, rc);
  if (rc == 0) {
    apply_pending_cmd();
    render_model();
  }
  ELMC_PEBBLE_TRACE_EXIT("app_focus_handler");
}
#endif

#if ELMC_PEBBLE_FEATURE_UNOBSTRUCTED_AREA_EVENTS
static GRect current_unobstructed_bounds(void) {
  GRect bounds = GRect(0, 0, PBL_IF_ROUND_ELSE(180, 144), PBL_IF_ROUND_ELSE(180, 168));
  if (s_main_window) {
    bounds = layer_get_unobstructed_bounds(window_get_root_layer(s_main_window));
    if (bounds.size.w <= 0 || bounds.size.h <= 0) {
      bounds = layer_get_bounds(window_get_root_layer(s_main_window));
    }
  }
  return bounds;
}

static int dispatch_unobstructed_bounds_result(int64_t target, GRect bounds) {
  if (target <= 0) {
    return -6;
  }

  const char *names[] = {"x", "y", "w", "h"};
  ElmcValue *values[4];
  values[0] = elmc_new_int(bounds.origin.x);
  values[1] = elmc_new_int(bounds.origin.y);
  values[2] = elmc_new_int(bounds.size.w);
  values[3] = elmc_new_int(bounds.size.h);
  if (!values[0] || !values[1] || !values[2] || !values[3]) {
    for (int i = 0; i < 4; i++) {
      if (values[i]) {
        elmc_release(values[i]);
      }
    }
    return -2;
  }

  ElmcValue *record = elmc_record_new(4, names, values);
  for (int i = 0; i < 4; i++) {
    elmc_release(values[i]);
  }
  if (!record) {
    return -2;
  }

  int rc = elmc_pebble_dispatch_tag_payload(&s_elm_app, target, record);
  elmc_release(record);
  return rc;
}

static void unobstructed_will_change_handler(GRect final_bounds, void *context) {
  (void)context;
  ELMC_PEBBLE_TRACE_ENTER("unobstructed_will_change_handler");
  int rc = elmc_pebble_dispatch_unobstructed_will_change(
      &s_elm_app, final_bounds.origin.x, final_bounds.origin.y, final_bounds.size.w,
      final_bounds.size.h);
  APP_LOG(APP_LOG_LEVEL_INFO, "unobstructed will_change rc=%d", rc);
  if (rc == 0) {
    apply_pending_cmd();
    render_model();
  }
  ELMC_PEBBLE_TRACE_EXIT("unobstructed_will_change_handler");
}

static void unobstructed_change_handler(AnimationProgress progress, void *context) {
  (void)context;
  ELMC_PEBBLE_TRACE_ENTER("unobstructed_change_handler");
  int rc = elmc_pebble_dispatch_unobstructed_changing(&s_elm_app, (int)progress);
  APP_LOG(APP_LOG_LEVEL_INFO, "unobstructed changing progress=%d rc=%d", (int)progress, rc);
  if (rc == 0) {
    apply_pending_cmd();
    render_model();
  }
  ELMC_PEBBLE_TRACE_EXIT("unobstructed_change_handler");
}

static void unobstructed_did_change_handler(void *context) {
  (void)context;
  ELMC_PEBBLE_TRACE_ENTER("unobstructed_did_change_handler");
  int rc = elmc_pebble_dispatch_unobstructed_did_change(&s_elm_app);
  APP_LOG(APP_LOG_LEVEL_INFO, "unobstructed did_change rc=%d", rc);
  if (rc == 0) {
    apply_pending_cmd();
    render_model();
  }
  ELMC_PEBBLE_TRACE_EXIT("unobstructed_did_change_handler");
}
#endif

#if ELMC_PEBBLE_FEATURE_COMPASS_EVENTS
static void compass_handler(CompassHeadingData heading) {
  ELMC_PEBBLE_TRACE_ENTER("compass_handler");
  double degrees = simulator_compass_heading_degrees();
  bool is_valid = simulator_compass_heading_is_valid();
  if (heading.compass_status == CompassStatusAvailable) {
    degrees = (double)heading.true_heading * 360.0 / TRIG_MAX_ANGLE;
    is_valid = true;
  } else if (heading.compass_status == CompassStatusDataInvalid) {
    is_valid = false;
  }
  int rc = elmc_pebble_dispatch_compass_heading(&s_elm_app, degrees, is_valid ? 1 : 0);
  APP_LOG(APP_LOG_LEVEL_INFO, "compass dispatch degrees=%ld valid=%d rc=%d",
          (long)degrees, is_valid ? 1 : 0, rc);
  if (rc == 0) {
    apply_pending_cmd();
    render_model();
  }
  ELMC_PEBBLE_TRACE_EXIT("compass_handler");
}
#endif

#if ELMC_PEBBLE_FEATURE_DICTATION_EVENTS || ELMC_PEBBLE_FEATURE_CMD_DICTATION_START || ELMC_PEBBLE_FEATURE_CMD_DICTATION_STOP
#ifdef PBL_DICTATION
static void dictation_session_callback(DictationSessionStatus status, char *transcription, void *context) {
  ELMC_PEBBLE_TRACE_ENTER("dictation_session_callback");
  (void)context;
  switch (status) {
    case DictationSessionStatusFailure:
      elmc_pebble_dispatch_dictation_status(&s_elm_app, 2);
      elmc_pebble_dispatch_dictation_result(&s_elm_app, 0, 3, transcription ? transcription : "");
      break;
    case DictationSessionStatusSuccess:
      elmc_pebble_dispatch_dictation_status(&s_elm_app, 2);
      elmc_pebble_dispatch_dictation_result(
          &s_elm_app, 1, 0, transcription ? transcription : s_simulator_dictation_text);
      break;
    default:
      elmc_pebble_dispatch_dictation_status(&s_elm_app, 1);
      break;
  }
  apply_pending_cmd();
  render_model();
  ELMC_PEBBLE_TRACE_EXIT("dictation_session_callback");
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
  if (s_render_pending) {
    s_render_pending = false;
    layer_mark_dirty(s_draw_layer);
#if ELMC_PEBBLE_EMULATOR_STORAGE_LOGS
    companion_inbox_log("render flushed after window load");
#endif
  }
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
  ElmcValue *screen_shape = elmc_new_string(PBL_IF_ROUND_ELSE("Round", "Rectangular"));
  ElmcValue *screen_color_mode = elmc_new_string(PBL_IF_COLOR_ELSE("Color", "BlackWhite"));
  const char *screen_names[] = {"color_mode", "height", "shape", "width"};
  ElmcValue *screen_values[] = {screen_color_mode, screen_height, screen_shape, screen_width};
  ElmcValue *screen = elmc_record_new(4, screen_names, screen_values);
  elmc_release(screen_width);
  elmc_release(screen_height);
  elmc_release(screen_shape);
  elmc_release(screen_color_mode);

  ElmcValue *reason = elmc_new_int(launch_reason_to_elm_tag(launch));
  ElmcValue *watch_model = elmc_new_string("");
  ElmcValue *watch_profile_id = elmc_new_string("");
  ElmcValue *has_microphone = elmc_new_bool(
#ifdef PBL_MICROPHONE
      1
#else
      0
#endif
  );
  ElmcValue *has_compass = elmc_new_bool(
#ifdef PBL_COMPASS
      1
#else
      0
#endif
  );
  ElmcValue *supports_health = elmc_new_bool(
#ifdef PBL_HEALTH
      1
#else
      0
#endif
  );
  const char *context_names[] = {
      "has_compass", "has_microphone", "reason", "screen", "supports_health", "watchModel",
      "watchProfileId"};
  ElmcValue *context_values[] = {has_compass, has_microphone, reason, screen, supports_health,
                                 watch_model, watch_profile_id};
  ElmcValue *context = elmc_record_new(7, context_names, context_values);
  elmc_release(reason);
  elmc_release(screen);
  elmc_release(watch_model);
  elmc_release(watch_profile_id);
  elmc_release(has_microphone);
  elmc_release(has_compass);
  elmc_release(supports_health);
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
  // #region agent probe
#if ELMC_AGENT_PROBE_INIT_STAGE == 1
  window_stack_push(s_main_window, true);
  ELMC_PEBBLE_DEBUG_LOG(APP_LOG_LEVEL_INFO, "window pushed");
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
#if ELMC_PEBBLE_FEATURE_CMD_COMPANION_SEND || ELMC_PEBBLE_FEATURE_INBOX_EVENTS
    app_message_register_inbox_received(inbox_received_handler);
    app_message_register_inbox_dropped(inbox_dropped_handler);
    app_message_register_outbox_sent(outbox_sent_handler);
    app_message_register_outbox_failed(outbox_failed_handler);
    AppMessageResult app_message_rc = app_message_open(ELMC_PEBBLE_APP_MESSAGE_INBOX_SIZE, ELMC_PEBBLE_APP_MESSAGE_OUTBOX_SIZE);
    (void)app_message_rc;
#if ELMC_PEBBLE_FEATURE_CMD_COMPANION_SEND
    AppTimer *companion_resync_timer = app_timer_register(500, companion_resync_callback, NULL);
    (void)companion_resync_timer;
    companion_resync_timer = app_timer_register(1500, companion_resync_callback, NULL);
    (void)companion_resync_timer;
#endif
#endif
    AppTimer *startup_timer = app_timer_register(1, startup_cmd_callback, NULL);
    (void)startup_timer;
#if ELMC_PEBBLE_EMULATOR_STORAGE_LOGS
    AppTimer *storage_snapshot_timer = app_timer_register(1500, emulator_storage_snapshot_callback, NULL);
    (void)storage_snapshot_timer;
#endif
#if ELMC_PEBBLE_FEATURE_FRAME_EVENTS
    if (s_run_mode == ELMC_PEBBLE_MODE_APP) {
      s_frame_interval_ms = frame_interval_from_subscriptions();
    }
#endif
#if ELMC_PEBBLE_STARTUP_SERVICE_SUBSCRIPTIONS && (ELMC_PEBBLE_FEATURE_TICK_EVENTS || ELMC_PEBBLE_FEATURE_HOUR_EVENTS || ELMC_PEBBLE_FEATURE_MINUTE_EVENTS || ELMC_PEBBLE_FEATURE_DAY_EVENTS || ELMC_PEBBLE_FEATURE_MONTH_EVENTS || ELMC_PEBBLE_FEATURE_YEAR_EVENTS)
    tick_timer_service_subscribe(subscribed_time_units(), tick_handler);
#endif
#if ELMC_PEBBLE_STARTUP_SERVICE_SUBSCRIPTIONS && ELMC_PEBBLE_FEATURE_ACCEL_EVENTS
    if (s_run_mode == ELMC_PEBBLE_MODE_APP) {
      accel_tap_service_subscribe(accel_tap_handler);
    }
#endif
#if ELMC_PEBBLE_STARTUP_SERVICE_SUBSCRIPTIONS && ELMC_PEBBLE_FEATURE_ACCEL_DATA_EVENTS
    if (s_run_mode == ELMC_PEBBLE_MODE_APP) {
      accel_data_service_subscribe(ELMC_PEBBLE_ACCEL_SAMPLES_PER_UPDATE, accel_data_handler);
      accel_service_set_sampling_rate(accel_sampling_rate_from_hz(ELMC_PEBBLE_ACCEL_SAMPLING_HZ));
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
#if ELMC_PEBBLE_STARTUP_SERVICE_SUBSCRIPTIONS && ELMC_PEBBLE_FEATURE_APP_FOCUS_EVENTS
    app_focus_service_subscribe((AppFocusHandlers){
        .did_focus = app_focus_handler,
        .will_blur = app_focus_handler,
    });
#endif
#if ELMC_PEBBLE_STARTUP_SERVICE_SUBSCRIPTIONS && ELMC_PEBBLE_FEATURE_COMPASS_EVENTS
#ifdef PBL_COMPASS
    compass_service_subscribe(compass_handler);
#endif
#endif
#if ELMC_PEBBLE_STARTUP_SERVICE_SUBSCRIPTIONS && ELMC_PEBBLE_FEATURE_UNOBSTRUCTED_AREA_EVENTS
    unobstructed_area_service_subscribe((UnobstructedAreaHandlers){
        .will_change = unobstructed_will_change_handler,
        .change = unobstructed_change_handler,
        .did_change = unobstructed_did_change_handler,
    }, NULL);
    {
      GRect bounds = current_unobstructed_bounds();
      unobstructed_change_handler(0, NULL);
      unobstructed_did_change_handler(NULL);
      (void)bounds;
    }
#endif
#if ELMC_PEBBLE_STARTUP_SERVICE_SUBSCRIPTIONS && ELMC_PEBBLE_FEATURE_DICTATION_EVENTS
#ifdef PBL_DICTATION
    if (!s_dictation_session) {
      s_dictation_session = dictation_session_create(30000, dictation_session_callback, NULL);
    }
#endif
#endif
#if ELMC_PEBBLE_FEATURE_CMD_COMPANION_SEND
    flush_pending_companion_request();
#endif
  } else {
    APP_LOG(APP_LOG_LEVEL_ERROR, "elmc_pebble_init failed: %d", rc);
  }

  window_stack_push(s_main_window, true);
  ELMC_PEBBLE_DEBUG_LOG(APP_LOG_LEVEL_INFO, "window pushed");
  // #region agent log
  ELMC_AGENT_INIT_PROBE(0xED990A01);
  // #endregion
  ELMC_PEBBLE_TRACE_EXIT("init");
}

static void deinit(void) {
  ELMC_PEBBLE_TRACE_ENTER("deinit");
  ELMC_PEBBLE_DEBUG_LOG(APP_LOG_LEVEL_INFO, "app deinit start");
#if ELMC_PEBBLE_FEATURE_TICK_EVENTS || ELMC_PEBBLE_FEATURE_HOUR_EVENTS || ELMC_PEBBLE_FEATURE_MINUTE_EVENTS || ELMC_PEBBLE_FEATURE_DAY_EVENTS || ELMC_PEBBLE_FEATURE_MONTH_EVENTS || ELMC_PEBBLE_FEATURE_YEAR_EVENTS
  tick_timer_service_unsubscribe();
#endif
  if (s_timer) {
    app_timer_cancel(s_timer);
    s_timer = NULL;
  }
  if (s_render_coalesce_timer) {
    app_timer_cancel(s_render_coalesce_timer);
    s_render_coalesce_timer = NULL;
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
#if ELMC_PEBBLE_FEATURE_APP_FOCUS_EVENTS
  app_focus_service_unsubscribe();
#endif
#if ELMC_PEBBLE_FEATURE_UNOBSTRUCTED_AREA_EVENTS
  unobstructed_area_service_unsubscribe();
#endif
#if ELMC_PEBBLE_FEATURE_COMPASS_EVENTS
#ifdef PBL_COMPASS
  compass_service_unsubscribe();
#endif
#endif
#if ELMC_PEBBLE_FEATURE_DICTATION_EVENTS
#ifdef PBL_DICTATION
  if (s_dictation_session) {
    dictation_session_destroy(s_dictation_session);
    s_dictation_session = NULL;
  }
#endif
#endif
#if ELMC_PEBBLE_FEATURE_CMD_BACKLIGHT
  if (s_forced_backlight) {
    light_enable(false);
    s_forced_backlight = false;
  }
#endif
#if ELMC_PEBBLE_FEATURE_DRAW_VECTOR_AT
  vector_image_cache_clear();
#endif
#if ELMC_PEBBLE_FEATURE_DRAW_VECTOR_SEQUENCE_AT
  if (s_vector_sequence_timer) {
    app_timer_cancel(s_vector_sequence_timer);
    s_vector_sequence_timer = NULL;
  }
  vector_sequence_cache_clear();
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
