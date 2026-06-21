#ifndef ELMC_PEBBLE_H
#define ELMC_PEBBLE_H

#define ELMC_PEBBLE_APLITE_DIRECT_VIEW_SCENE 1
typedef struct ElmcPebbleApp ElmcPebbleApp;

enum {
  ELMC_SCENE_PL_EMPTY = 0,
  ELMC_SCENE_PL_U8 = 1,
  ELMC_SCENE_PL_I32 = 4,
  ELMC_SCENE_PL_PIXEL = 5,
  ELMC_SCENE_PL_CIRCLE_U8 = 7,
  ELMC_SCENE_PL_TEXT_LABEL_BASE = 8,
  ELMC_SCENE_PL_COORDS_COLOR_U8 = 9,
  ELMC_SCENE_PL_CIRCLE_I32 = 10,
  ELMC_SCENE_PL_ROUND_U8 = 11,
  ELMC_SCENE_PL_COORDS_COLOR_I32 = 12,
  ELMC_SCENE_PL_ROUND_I32 = 14,
  ELMC_SCENE_PL_TEXT_BASE = 16,
  ELMC_SCENE_PL_FULL = 24
};

typedef struct {
  ElmcPebbleApp *app;
  int command_count;
} ElmcSceneWriter;

void elmc_scene_writer_init_app(ElmcSceneWriter *writer, ElmcPebbleApp *app);


#include "elmc_worker.h"

#define ELMC_PEBBLE_FEATURE_TICK_EVENTS 1
#define ELMC_PEBBLE_FEATURE_HOUR_EVENTS 0
#define ELMC_PEBBLE_FEATURE_MINUTE_EVENTS 0
#define ELMC_PEBBLE_FEATURE_DAY_EVENTS 0
#define ELMC_PEBBLE_FEATURE_MONTH_EVENTS 0
#define ELMC_PEBBLE_FEATURE_YEAR_EVENTS 0
#define ELMC_PEBBLE_FEATURE_FRAME_EVENTS 0
#define ELMC_PEBBLE_FEATURE_BUTTON_EVENTS 1
#define ELMC_PEBBLE_FEATURE_RAW_BUTTON_EVENTS 1
#define ELMC_PEBBLE_FEATURE_ACCEL_EVENTS 1
#define ELMC_PEBBLE_FEATURE_ACCEL_DATA_EVENTS 0
#define ELMC_PEBBLE_FEATURE_BATTERY_EVENTS 0
#define ELMC_PEBBLE_FEATURE_CONNECTION_EVENTS 0
#define ELMC_PEBBLE_FEATURE_HEALTH_EVENTS 0
#define ELMC_PEBBLE_FEATURE_APP_FOCUS_EVENTS 0
#define ELMC_PEBBLE_FEATURE_COMPASS_EVENTS 0
#define ELMC_PEBBLE_FEATURE_DICTATION_EVENTS 0
#define ELMC_PEBBLE_FEATURE_UNOBSTRUCTED_AREA_EVENTS 0
#define ELMC_PEBBLE_FEATURE_INBOX_EVENTS 0
#define ELMC_PEBBLE_FEATURE_CMD_TIMER_AFTER_MS 1
#define ELMC_PEBBLE_FEATURE_CMD_STORAGE_WRITE_INT 0
#define ELMC_PEBBLE_FEATURE_CMD_STORAGE_READ_INT 0
#define ELMC_PEBBLE_FEATURE_CMD_STORAGE_WRITE_STRING 0
#define ELMC_PEBBLE_FEATURE_CMD_STORAGE_READ_STRING 0
#define ELMC_PEBBLE_FEATURE_CMD_RANDOM_GENERATE 0
#define ELMC_PEBBLE_FEATURE_CMD_STORAGE_DELETE 0
#define ELMC_PEBBLE_FEATURE_CMD_COMPANION_SEND 1
#define ELMC_PEBBLE_FEATURE_CMD_BACKLIGHT 0
#define ELMC_PEBBLE_FEATURE_CMD_GET_CURRENT_TIME_STRING 0
#define ELMC_PEBBLE_FEATURE_CMD_GET_CURRENT_DATE_TIME 0
#define ELMC_PEBBLE_FEATURE_CMD_GET_BATTERY_LEVEL 0
#define ELMC_PEBBLE_FEATURE_CMD_GET_CONNECTION_STATUS 0
#define ELMC_PEBBLE_FEATURE_CMD_GET_CLOCK_STYLE_24H 0
#define ELMC_PEBBLE_FEATURE_CMD_GET_TIMEZONE_IS_SET 0
#define ELMC_PEBBLE_FEATURE_CMD_GET_TIMEZONE 0
#define ELMC_PEBBLE_FEATURE_CMD_GET_WATCH_MODEL 0
#define ELMC_PEBBLE_FEATURE_CMD_GET_WATCH_COLOR 0
#define ELMC_PEBBLE_FEATURE_CMD_GET_FIRMWARE_VERSION 0
#define ELMC_PEBBLE_FEATURE_CMD_WAKEUP_SCHEDULE_AFTER_SECONDS 0
#define ELMC_PEBBLE_FEATURE_CMD_WAKEUP_CANCEL 0
#define ELMC_PEBBLE_FEATURE_CMD_LOG_INFO_CODE 0
#define ELMC_PEBBLE_FEATURE_CMD_LOG_WARN_CODE 0
#define ELMC_PEBBLE_FEATURE_CMD_LOG_ERROR_CODE 0
#define ELMC_PEBBLE_FEATURE_CMD_VIBES_CANCEL 0
#define ELMC_PEBBLE_FEATURE_CMD_VIBES_SHORT_PULSE 0
#define ELMC_PEBBLE_FEATURE_CMD_VIBES_LONG_PULSE 0
#define ELMC_PEBBLE_FEATURE_CMD_VIBES_DOUBLE_PULSE 0
#define ELMC_PEBBLE_FEATURE_CMD_VIBES_CUSTOM_PATTERN 0
#define ELMC_PEBBLE_FEATURE_CMD_HEALTH_VALUE 0
#define ELMC_PEBBLE_FEATURE_CMD_HEALTH_SUM_TODAY 0
#define ELMC_PEBBLE_FEATURE_CMD_HEALTH_SUM 0
#define ELMC_PEBBLE_FEATURE_CMD_HEALTH_ACCESSIBLE 0
#define ELMC_PEBBLE_FEATURE_CMD_HEALTH_SUPPORTED 0
#define ELMC_PEBBLE_FEATURE_CMD_DATA_LOG_BYTES 0
#define ELMC_PEBBLE_FEATURE_CMD_DATA_LOG_INT32 0
#define ELMC_PEBBLE_FEATURE_CMD_COMPASS_PEEK 0
#define ELMC_PEBBLE_FEATURE_CMD_DICTATION_START 0
#define ELMC_PEBBLE_FEATURE_CMD_DICTATION_STOP 0
#define ELMC_PEBBLE_FEATURE_CMD_UNOBSTRUCTED_BOUNDS_PEEK 0
#define ELMC_PEBBLE_FEATURE_DRAW_TEXT_INT 1
#define ELMC_PEBBLE_FEATURE_DRAW_CLEAR 1
#define ELMC_PEBBLE_FEATURE_DRAW_PIXEL 1
#define ELMC_PEBBLE_FEATURE_DRAW_LINE 1
#define ELMC_PEBBLE_FEATURE_DRAW_RECT 0
#define ELMC_PEBBLE_FEATURE_DRAW_FILL_RECT 0
#define ELMC_PEBBLE_FEATURE_DRAW_CIRCLE 0
#define ELMC_PEBBLE_FEATURE_DRAW_FILL_CIRCLE 0
#define ELMC_PEBBLE_FEATURE_DRAW_TEXT_LABEL 1
#define ELMC_PEBBLE_FEATURE_DRAW_CONTEXT 1
#define ELMC_PEBBLE_FEATURE_DRAW_STROKE_WIDTH 1
#define ELMC_PEBBLE_FEATURE_DRAW_ANTIALIASED 1
#define ELMC_PEBBLE_FEATURE_DRAW_STROKE_COLOR 1
#define ELMC_PEBBLE_FEATURE_DRAW_FILL_COLOR 1
#define ELMC_PEBBLE_FEATURE_DRAW_TEXT_COLOR 1
#define ELMC_PEBBLE_FEATURE_DRAW_ROUND_RECT 1
#define ELMC_PEBBLE_FEATURE_DRAW_ARC 1
#define ELMC_PEBBLE_FEATURE_DRAW_PATH 1
#define ELMC_PEBBLE_FEATURE_DRAW_FILL_RADIAL 0
#define ELMC_PEBBLE_FEATURE_DRAW_COMPOSITING_MODE 0
#define ELMC_PEBBLE_FEATURE_DRAW_BITMAP_IN_RECT 0
#define ELMC_PEBBLE_FEATURE_DRAW_VECTOR_AT 0
#define ELMC_PEBBLE_FEATURE_DRAW_VECTOR_SEQUENCE_AT 0
#define ELMC_PEBBLE_FEATURE_DRAW_BITMAP_SEQUENCE_AT 0
#define ELMC_PEBBLE_FEATURE_DRAW_ROTATED_BITMAP 0
#define ELMC_PEBBLE_FEATURE_DRAW_TEXT 0
#ifndef ELMC_PEBBLE_DIRTY_REGION_ENABLED
#if defined(PBL_PLATFORM_APLITE) || defined(PBL_PLATFORM_BASALT) || defined(PBL_PLATFORM_CHALK) || defined(PBL_PLATFORM_DIORITE) || defined(PBL_PLATFORM_EMERY) || defined(PBL_PLATFORM_FLINT) || defined(PBL_PLATFORM_GABBRO)
#define ELMC_PEBBLE_DIRTY_REGION_ENABLED 0
#else
#define ELMC_PEBBLE_DIRTY_REGION_ENABLED 1
#endif
#endif

#ifndef ELMC_PEBBLE_SCENE_CACHE_ENABLED
/* Encode the view once into a compact byte stream; draw decodes with a cursor.
   Incremental dirty regions (prev_scene diff) stay off on Pebble targets until reliable. */
#define ELMC_PEBBLE_SCENE_CACHE_ENABLED 1
#endif

#ifndef ELMC_PEBBLE_SCENE_INITIAL_CAPACITY
#define ELMC_PEBBLE_SCENE_INITIAL_CAPACITY 1024
#endif

#ifndef ELMC_PEBBLE_SCENE_GROW_CHUNK
#if defined(PBL_PLATFORM_APLITE)
#define ELMC_PEBBLE_SCENE_GROW_CHUNK 32
#else
#define ELMC_PEBBLE_SCENE_GROW_CHUNK 64
#endif
#endif

#ifndef ELMC_PEBBLE_SCENE_TRIM_SLACK
#define ELMC_PEBBLE_SCENE_TRIM_SLACK 0
#endif

/* Retained scene-byte pools: grow once per slot, never shrink or realloc per frame. */
#ifndef ELMC_PEBBLE_SCENE_POOL_SLOTS
#define ELMC_PEBBLE_SCENE_POOL_SLOTS 10
#endif

#ifndef ELMC_PEBBLE_SCENE_STATIC_CAPACITY
#define ELMC_PEBBLE_SCENE_STATIC_CAPACITY 0
#endif

#ifndef ELMC_PEBBLE_SCENE_CHUNK_SIZE
#define ELMC_PEBBLE_SCENE_CHUNK_SIZE 0
#endif

    #ifndef ELMC_PEBBLE_DRAW_PATH_PROBES
    #define ELMC_PEBBLE_DRAW_PATH_PROBES 0
    #endif

    #define ELMC_DRAW_PATH_RENDER_MODEL_ENTER 0xED9A0101U
    #define ELMC_DRAW_PATH_RENDER_MODEL_EXIT 0xED9A8101U
    #define ELMC_DRAW_PATH_DRAW_UPDATE_ENTER 0xED9A0102U
    #define ELMC_DRAW_PATH_DRAW_UPDATE_EXIT 0xED9A8102U
    #define ELMC_DRAW_PATH_ENSURE_SCENE_ENTER 0xED9A0103U
    #define ELMC_DRAW_PATH_ENSURE_SCENE_EXIT 0xED9A8103U
    #define ELMC_DRAW_PATH_SCENE_NEXT_ENTER 0xED9A0104U
    #define ELMC_DRAW_PATH_SCENE_NEXT_EXIT 0xED9A8104U
    #define ELMC_DRAW_PATH_VIEW_APPEND_ENTER 0xED9A0105U
    #define ELMC_DRAW_PATH_VIEW_APPEND_EXIT 0xED9A8105U
    #define ELMC_DRAW_PATH_ELM_INIT_ENTER 0xED9A0106U
    #define ELMC_DRAW_PATH_ELM_INIT_EXIT 0xED9A8106U
    #define ELMC_DRAW_PATH_FONT_FOR_TEXT_ENTER 0xED9A0107U
    #define ELMC_DRAW_PATH_FONT_FOR_TEXT_EXIT 0xED9A8107U
    #define ELMC_DRAW_PATH_GRAPHICS_TEXT_ENTER 0xED9A0108U
    #define ELMC_DRAW_PATH_GRAPHICS_TEXT_EXIT 0xED9A8108U

    #if ELMC_PEBBLE_DRAW_PATH_PROBES && defined(ELMC_PEBBLE_PLATFORM)
    #include <data_logging.h>
    static inline void elmc_draw_path_probe(uint32_t tag) {
      DataLoggingSessionRef session = data_logging_create(tag, DATA_LOGGING_BYTE_ARRAY, 1, false);
      if (session) {
        data_logging_finish(session);
      }
    }
    #define ELMC_DRAW_PATH_PROBE(tag) elmc_draw_path_probe((uint32_t)(tag))
    #else
    #define ELMC_DRAW_PATH_PROBE(tag) do { (void)(tag); } while (0)
    #endif

typedef struct {
  unsigned char *bytes;
  int byte_count;
  int byte_capacity;
  int command_count;
  uint64_t hash;
  int dirty;
  int pool_slot;
#if ELMC_PEBBLE_SCENE_CHUNK_SIZE > 0
  struct ElmcPebbleSceneChunk *chunks;
#endif
} ElmcPebbleSceneBuffer;

#if ELMC_PEBBLE_SCENE_CHUNK_SIZE > 0
typedef struct ElmcPebbleSceneChunk {
  struct ElmcPebbleSceneChunk *next;
  int used;
  unsigned char bytes[ELMC_PEBBLE_SCENE_CHUNK_SIZE];
} ElmcPebbleSceneChunk;
#endif

typedef struct {
  int x;
  int y;
  int w;
  int h;
} ElmcPebbleRect;

typedef struct ElmcPebbleApp {
  ElmcWorkerState worker;
  int initialized;
  int run_mode;
  int has_prev_ui;
  int64_t prev_window_id;
  int64_t prev_layer_id;
  uint64_t prev_ops_hash;
  ElmcValue *stream_view_result;
  ElmcPebbleSceneBuffer scene;
#if ELMC_PEBBLE_SCENE_CACHE_ENABLED
  int scene_draw_byte_offset;
#endif
#if ELMC_PEBBLE_DIRTY_REGION_ENABLED
  ElmcPebbleSceneBuffer prev_scene;
  ElmcPebbleRect dirty_rect;
  int dirty_rect_valid;
  int dirty_rect_full;
#endif
} ElmcPebbleApp;

typedef enum {
  ELMC_PEBBLE_MODE_APP = 0,
  ELMC_PEBBLE_MODE_WATCHFACE = 1
} ElmcPebbleRunMode;


typedef enum {
  ELMC_PEBBLE_MSG_UNKNOWN = 0,
  ELMC_PEBBLE_MSG_INCREMENT = 1,
  ELMC_PEBBLE_MSG_DECREMENT = 2,
  ELMC_PEBBLE_MSG_TICK = 3,
  ELMC_PEBBLE_MSG_UPPRESSED = 4,
  ELMC_PEBBLE_MSG_SELECTPRESSED = 5,
  ELMC_PEBBLE_MSG_DOWNPRESSED = 6,
  ELMC_PEBBLE_MSG_ACCELTAP = 7,
  ELMC_PEBBLE_MSG_PROVIDETEMPERATURE = 8,
  ELMC_PEBBLE_MSG_CURRENTTIMESTRING = 9,
  ELMC_PEBBLE_MSG_CLOCKSTYLE24H = 10,
  ELMC_PEBBLE_MSG_TIMEZONEISSET = 11,
  ELMC_PEBBLE_MSG_TIMEZONENAME = 12,
  ELMC_PEBBLE_MSG_WATCHMODELNAME = 13,
  ELMC_PEBBLE_MSG_WATCHCOLORNAME = 14,
  ELMC_PEBBLE_MSG_FIRMWAREVERSIONSTRING = 15,
} ElmcPebbleMsgTag;

#define ELMC_PEBBLE_HAS_MSG_INCREMENT 1
#define ELMC_PEBBLE_HAS_MSG_DECREMENT 1
#define ELMC_PEBBLE_HAS_MSG_TICK 1
#define ELMC_PEBBLE_HAS_MSG_UPPRESSED 1
#define ELMC_PEBBLE_HAS_MSG_SELECTPRESSED 1
#define ELMC_PEBBLE_HAS_MSG_DOWNPRESSED 1
#define ELMC_PEBBLE_HAS_MSG_ACCELTAP 1
#define ELMC_PEBBLE_HAS_MSG_PROVIDETEMPERATURE 1
#define ELMC_PEBBLE_HAS_MSG_CURRENTTIMESTRING 1
#define ELMC_PEBBLE_HAS_MSG_CLOCKSTYLE24H 1
#define ELMC_PEBBLE_HAS_MSG_TIMEZONEISSET 1
#define ELMC_PEBBLE_HAS_MSG_TIMEZONENAME 1
#define ELMC_PEBBLE_HAS_MSG_WATCHMODELNAME 1
#define ELMC_PEBBLE_HAS_MSG_WATCHCOLORNAME 1
#define ELMC_PEBBLE_HAS_MSG_FIRMWAREVERSIONSTRING 1

typedef enum {
  ELMC_PEBBLE_BUTTON_BACK = 0,
  ELMC_PEBBLE_BUTTON_UP = 1,
  ELMC_PEBBLE_BUTTON_SELECT = 2,
  ELMC_PEBBLE_BUTTON_DOWN = 3
} ElmcPebbleButtonId;

#define ELMC_BUTTON_EVENT_PRESSED 1
#define ELMC_BUTTON_EVENT_RELEASED 2
#define ELMC_BUTTON_EVENT_LONG_PRESSED 3


typedef enum {
  ELMC_PEBBLE_ACCEL_AXIS_X = 1,
  ELMC_PEBBLE_ACCEL_AXIS_Y = 2,
  ELMC_PEBBLE_ACCEL_AXIS_Z = 3
} ElmcPebbleAccelAxis;


typedef struct {
  int32_t kind;
  int32_t p0;
  int32_t p1;
  int32_t p2;
  int32_t p3;
  int32_t p4;
  int32_t p5;
  union {
    char text[64];
#if ELMC_PEBBLE_FEATURE_DRAW_PATH
    struct {
      int16_t path_x[16];
      int16_t path_y[16];
      int16_t path_offset_x;
      int16_t path_offset_y;
      int16_t path_rotation;
      uint8_t path_point_count;
    };
#endif
  };
} ElmcPebbleDrawCmd;

int elmc_scene_writer_push_cmd(ElmcSceneWriter *writer, const ElmcPebbleDrawCmd *cmd);
void elmc_draw_cmd_init(ElmcPebbleDrawCmd *cmd, int32_t kind);

#if ELMC_PEBBLE_FEATURE_DRAW_TEXT || ELMC_PEBBLE_FEATURE_DRAW_TEXT_LABEL
static inline int elmc_scene_format_nonzero_int_at(char *text, int start, elmc_int_t value) {
  elmc_int_t direct_value = value;
  char direct_digits[12];
  int direct_digit_count = 0;
  int direct_text_i = start;
  int direct_negative = direct_value < 0;
  if (direct_negative && direct_text_i < 63) {
    text[direct_text_i++] = '-';
  }
  do {
    elmc_int_t direct_digit = direct_value % 10;
    if (direct_digit < 0) direct_digit = -direct_digit;
    direct_digits[direct_digit_count++] = (char)('0' + direct_digit);
    direct_value /= 10;
  } while (direct_value != 0 && direct_digit_count < (int)sizeof(direct_digits));
  while (direct_digit_count > 0 && direct_text_i < 63) {
    text[direct_text_i++] = direct_digits[--direct_digit_count];
  }
  text[direct_text_i] = '\0';
  return direct_text_i;
}

static inline void elmc_scene_text_from_nonzero_int(char *text, elmc_int_t value) {
  (void)elmc_scene_format_nonzero_int_at(text, 0, value);
}

static inline void elmc_scene_text_prefix_and_nonzero_int(char *text, const char *prefix, elmc_int_t value) {
  int direct_text_i = 0;
  while (prefix && prefix[direct_text_i] && direct_text_i < 63) {
    text[direct_text_i] = prefix[direct_text_i];
    direct_text_i++;
  }
  (void)elmc_scene_format_nonzero_int_at(text, direct_text_i, value);
}
#endif

int elmc_pebble_scene_decode_record(
    const unsigned char *bytes,
    int byte_count,
    int *offset,
    ElmcPebbleDrawCmd *out_cmd);


RC elmc_fn_Main_view_scene_append(
    ElmcValue ** const args,
    const int argc,
    ElmcSceneWriter * const writer);

typedef struct {
  int64_t kind;
  int64_t p0;
  int64_t p1;
  int64_t p2;
  int64_t p3;
  int64_t p4;
  int64_t p5;
  char text[128];
} ElmcPebbleCmd;

typedef enum {
  ELMC_PEBBLE_DRAW_NONE = 0,
  ELMC_PEBBLE_DRAW_CLEAR = 2,
  ELMC_PEBBLE_DRAW_PIXEL = 3,
  ELMC_PEBBLE_DRAW_LINE = 4,
  ELMC_PEBBLE_DRAW_RECT = 5,
  ELMC_PEBBLE_DRAW_FILL_RECT = 6,
  ELMC_PEBBLE_DRAW_CIRCLE = 7,
  ELMC_PEBBLE_DRAW_FILL_CIRCLE = 8,
  ELMC_PEBBLE_DRAW_PUSH_CONTEXT = 10,
  ELMC_PEBBLE_DRAW_POP_CONTEXT = 11,
  ELMC_PEBBLE_DRAW_STROKE_WIDTH = 12,
  ELMC_PEBBLE_DRAW_ANTIALIASED = 13,
  ELMC_PEBBLE_DRAW_STROKE_COLOR = 14,
  ELMC_PEBBLE_DRAW_FILL_COLOR = 15,
  ELMC_PEBBLE_DRAW_TEXT_COLOR = 16,
  ELMC_PEBBLE_DRAW_ROUND_RECT = 17,
  ELMC_PEBBLE_DRAW_ARC = 18,
  ELMC_PEBBLE_DRAW_CONTEXT_GROUP = 19,
  ELMC_PEBBLE_DRAW_PATH_FILLED = 20,
  ELMC_PEBBLE_DRAW_PATH_OUTLINE = 21,
  ELMC_PEBBLE_DRAW_PATH_OUTLINE_OPEN = 22,
  ELMC_PEBBLE_DRAW_FILL_RADIAL = 23,
  ELMC_PEBBLE_DRAW_COMPOSITING_MODE = 24,
  ELMC_PEBBLE_DRAW_BITMAP_IN_RECT = 25,
  ELMC_PEBBLE_DRAW_ROTATED_BITMAP = 26,
  ELMC_PEBBLE_DRAW_TEXT_INT_WITH_FONT = 27,
  ELMC_PEBBLE_DRAW_TEXT_LABEL_WITH_FONT = 28,
  ELMC_PEBBLE_DRAW_TEXT = 29,
  ELMC_PEBBLE_DRAW_VECTOR_AT = 30,
  ELMC_PEBBLE_DRAW_VECTOR_SEQUENCE_AT = 31,
  ELMC_PEBBLE_DRAW_BITMAP_SEQUENCE_AT = 32
} ElmcPebbleDrawKind;


typedef enum {
  ELMC_PEBBLE_CMD_NONE = 0,
  ELMC_PEBBLE_CMD_TIMER_AFTER_MS = 1,
  ELMC_PEBBLE_CMD_STORAGE_WRITE_INT = 2,
  ELMC_PEBBLE_CMD_STORAGE_READ_INT = 3,
  ELMC_PEBBLE_CMD_STORAGE_DELETE = 4,
  ELMC_PEBBLE_CMD_COMPANION_SEND = 5,
  ELMC_PEBBLE_CMD_BACKLIGHT = 6,
  ELMC_PEBBLE_CMD_GET_CURRENT_TIME_STRING = 7,
  ELMC_PEBBLE_CMD_GET_CLOCK_STYLE_24H = 8,
  ELMC_PEBBLE_CMD_GET_TIMEZONE_IS_SET = 9,
  ELMC_PEBBLE_CMD_GET_TIMEZONE = 10,
  ELMC_PEBBLE_CMD_GET_WATCH_MODEL = 11,
  ELMC_PEBBLE_CMD_GET_FIRMWARE_VERSION = 12,
  ELMC_PEBBLE_CMD_VIBES_CANCEL = 13,
  ELMC_PEBBLE_CMD_VIBES_SHORT_PULSE = 14,
  ELMC_PEBBLE_CMD_VIBES_LONG_PULSE = 15,
  ELMC_PEBBLE_CMD_VIBES_DOUBLE_PULSE = 16,
  ELMC_PEBBLE_CMD_GET_WATCH_COLOR = 17,
  ELMC_PEBBLE_CMD_WAKEUP_SCHEDULE_AFTER_SECONDS = 18,
  ELMC_PEBBLE_CMD_WAKEUP_CANCEL = 19,
  ELMC_PEBBLE_CMD_LOG_INFO_CODE = 20,
  ELMC_PEBBLE_CMD_LOG_WARN_CODE = 21,
  ELMC_PEBBLE_CMD_LOG_ERROR_CODE = 22,
  ELMC_PEBBLE_CMD_GET_CURRENT_DATE_TIME = 23,
  ELMC_PEBBLE_CMD_GET_BATTERY_LEVEL = 24,
  ELMC_PEBBLE_CMD_GET_CONNECTION_STATUS = 25,
  ELMC_PEBBLE_CMD_STORAGE_WRITE_STRING = 26,
  ELMC_PEBBLE_CMD_STORAGE_READ_STRING = 27,
  ELMC_PEBBLE_CMD_RANDOM_GENERATE = 28,
  ELMC_PEBBLE_CMD_HEALTH_VALUE = 29,
  ELMC_PEBBLE_CMD_HEALTH_SUM_TODAY = 30,
  ELMC_PEBBLE_CMD_HEALTH_SUM = 31,
  ELMC_PEBBLE_CMD_HEALTH_ACCESSIBLE = 32,
  ELMC_PEBBLE_CMD_VIBES_CUSTOM_PATTERN = 33,
  ELMC_PEBBLE_CMD_DATA_LOG_BYTES = 34,
  ELMC_PEBBLE_CMD_DATA_LOG_INT32 = 35,
  ELMC_PEBBLE_CMD_COMPASS_PEEK = 36,
  ELMC_PEBBLE_CMD_DICTATION_START = 37,
  ELMC_PEBBLE_CMD_DICTATION_STOP = 38,
  ELMC_PEBBLE_CMD_UNOBSTRUCTED_BOUNDS_PEEK = 39,
  ELMC_PEBBLE_CMD_HEALTH_SUPPORTED = 40
} ElmcPebbleCommandKind;


typedef enum {
  ELMC_PEBBLE_UI_WINDOW_STACK = 1000,
  ELMC_PEBBLE_UI_WINDOW_NODE = 1001,
  ELMC_PEBBLE_UI_CANVAS_LAYER = 1002
} ElmcPebbleUiNodeKind;


#define ELMC_PEBBLE_MSG_PHONE_TO_WATCH_TARGET -1
#define ELMC_PEBBLE_WATCH_MODEL_UNKNOWNMODEL 1
#define ELMC_PEBBLE_WATCH_MODEL_PEBBLEORIGINAL 2
#define ELMC_PEBBLE_WATCH_MODEL_PEBBLESTEEL 3
#define ELMC_PEBBLE_WATCH_MODEL_PEBBLETIME 4
#define ELMC_PEBBLE_WATCH_MODEL_PEBBLETIMESTEEL 5
#define ELMC_PEBBLE_WATCH_MODEL_PEBBLETIMEROUND14 6
#define ELMC_PEBBLE_WATCH_MODEL_PEBBLETIMEROUND20 7
#define ELMC_PEBBLE_WATCH_MODEL_PEBBLE2HR 8
#define ELMC_PEBBLE_WATCH_MODEL_PEBBLE2SE 9
#define ELMC_PEBBLE_WATCH_MODEL_PEBBLETIME2 10
#define ELMC_PEBBLE_WATCH_MODEL_COREDEVICESP2D 11
#define ELMC_PEBBLE_WATCH_MODEL_COREDEVICESPT2 12
#define ELMC_PEBBLE_WATCH_MODEL_COREDEVICESPR2 13
#define ELMC_PEBBLE_WATCH_COLOR_UNKNOWNCOLOR 1
#define ELMC_PEBBLE_WATCH_COLOR_BLACK 2
#define ELMC_PEBBLE_WATCH_COLOR_WHITE 3
#define ELMC_PEBBLE_WATCH_COLOR_RED 4
#define ELMC_PEBBLE_WATCH_COLOR_ORANGE 5
#define ELMC_PEBBLE_WATCH_COLOR_GRAY 6
#define ELMC_PEBBLE_WATCH_COLOR_STAINLESSSTEEL 7
#define ELMC_PEBBLE_WATCH_COLOR_MATTEBLACK 8
#define ELMC_PEBBLE_WATCH_COLOR_BLUE 9
#define ELMC_PEBBLE_WATCH_COLOR_GREEN 10
#define ELMC_PEBBLE_WATCH_COLOR_PINK 11
#define ELMC_PEBBLE_WATCH_COLOR_TIMEWHITE 12
#define ELMC_PEBBLE_WATCH_COLOR_TIMEBLACK 13
#define ELMC_PEBBLE_WATCH_COLOR_TIMERED 14
#define ELMC_PEBBLE_WATCH_COLOR_TIMESTEELSILVER 15
#define ELMC_PEBBLE_WATCH_COLOR_TIMESTEELBLACK 16
#define ELMC_PEBBLE_WATCH_COLOR_TIMESTEELGOLD 17
#define ELMC_PEBBLE_WATCH_COLOR_TIMEROUNDSILVER14 18
#define ELMC_PEBBLE_WATCH_COLOR_TIMEROUNDBLACK14 19
#define ELMC_PEBBLE_WATCH_COLOR_TIMEROUNDSILVER20 20
#define ELMC_PEBBLE_WATCH_COLOR_TIMEROUNDBLACK20 21
#define ELMC_PEBBLE_WATCH_COLOR_TIMEROUNDROSEGOLD14 22
#define ELMC_PEBBLE_WATCH_COLOR_PEBBLE2HRBLACK 23
#define ELMC_PEBBLE_WATCH_COLOR_PEBBLE2HRLIME 24
#define ELMC_PEBBLE_WATCH_COLOR_PEBBLE2HRFLAME 25
#define ELMC_PEBBLE_WATCH_COLOR_PEBBLE2HRWHITE 26
#define ELMC_PEBBLE_WATCH_COLOR_PEBBLE2HRAQUA 27
#define ELMC_PEBBLE_WATCH_COLOR_PEBBLE2SEBLACK 28
#define ELMC_PEBBLE_WATCH_COLOR_PEBBLE2SEWHITE 29
#define ELMC_PEBBLE_WATCH_COLOR_PEBBLETIME2BLACK 30
#define ELMC_PEBBLE_WATCH_COLOR_PEBBLETIME2SILVER 31
#define ELMC_PEBBLE_WATCH_COLOR_PEBBLETIME2GOLD 32
#define ELMC_PEBBLE_WATCH_COLOR_COREDEVICESP2DBLACK 33
#define ELMC_PEBBLE_WATCH_COLOR_COREDEVICESP2DWHITE 34
#define ELMC_PEBBLE_WATCH_COLOR_COREDEVICESPT2BLACKGREY 35
#define ELMC_PEBBLE_WATCH_COLOR_COREDEVICESPT2BLACKRED 36
#define ELMC_PEBBLE_WATCH_COLOR_COREDEVICESPT2SILVERBLUE 37
#define ELMC_PEBBLE_WATCH_COLOR_COREDEVICESPT2SILVERGREY 38
#define ELMC_PEBBLE_WATCH_COLOR_COREDEVICESPR2BLACK20 39
#define ELMC_PEBBLE_WATCH_COLOR_COREDEVICESPR2SILVER20 40
#define ELMC_PEBBLE_WATCH_COLOR_COREDEVICESPR2GOLD14 41
#define ELMC_PEBBLE_WATCH_COLOR_COREDEVICESPR2SILVER14 42
    #define ELMC_PEBBLE_SUB_TICK (1 << 0)
    #define ELMC_PEBBLE_SUB_BUTTON_UP (1 << 1)
    #define ELMC_PEBBLE_SUB_BUTTON_SELECT (1 << 2)
    #define ELMC_PEBBLE_SUB_BUTTON_DOWN (1 << 3)
    #define ELMC_PEBBLE_SUB_ACCEL_TAP (1 << 4)
    #define ELMC_PEBBLE_SUB_BATTERY (1 << 5)
    #define ELMC_PEBBLE_SUB_CONNECTION (1 << 6)
    #define ELMC_PEBBLE_SUB_HOUR (1 << 10)
    #define ELMC_PEBBLE_SUB_MINUTE (1 << 11)
    #define ELMC_PEBBLE_SUB_APPMESSAGE (1 << 12)
    #define ELMC_PEBBLE_SUB_FRAME (1 << 13)
    #define ELMC_PEBBLE_SUB_BUTTON_RAW (1 << 14)
    #define ELMC_PEBBLE_SUB_ACCEL_DATA (1 << 15)
    #define ELMC_PEBBLE_SUB_DAY (1 << 16)
    #define ELMC_PEBBLE_SUB_MONTH (1 << 17)
    #define ELMC_PEBBLE_SUB_YEAR (1 << 18)
    #define ELMC_PEBBLE_SUB_APP_FOCUS (1 << 19)
    #define ELMC_PEBBLE_SUB_COMPASS (1 << 20)
    #define ELMC_PEBBLE_SUB_DICTATION (1 << 21)
    #define ELMC_PEBBLE_SUB_UNOBSTRUCTED_AREA (1 << 22)
    #define ELMC_PEBBLE_SUB_HEALTH (1LL << 31)
#ifndef ELMC_PEBBLE_ACCEL_SAMPLES_PER_UPDATE
#define ELMC_PEBBLE_ACCEL_SAMPLES_PER_UPDATE 1
#endif
#ifndef ELMC_PEBBLE_ACCEL_SAMPLING_HZ
#define ELMC_PEBBLE_ACCEL_SAMPLING_HZ 25
#endif
    int elmc_pebble_init(ElmcPebbleApp *app, ElmcValue *flags);
    int elmc_pebble_init_with_mode(ElmcPebbleApp *app, ElmcValue *flags, int run_mode);
    int elmc_pebble_dispatch_int(ElmcPebbleApp *app, int64_t tag);
    int elmc_pebble_dispatch_tag_value(ElmcPebbleApp *app, int64_t tag, int64_t value);
    int elmc_pebble_dispatch_tag_bool(ElmcPebbleApp *app, int64_t tag, int value);
    int elmc_pebble_dispatch_tag_string(ElmcPebbleApp *app, int64_t tag, const char *value);
    int elmc_pebble_dispatch_tag_payload(ElmcPebbleApp *app, int64_t tag, ElmcValue *payload);
    int elmc_pebble_dispatch_tag_int_values(
        ElmcPebbleApp *app,
        int64_t outer_tag,
        int64_t inner_tag,
        int field_count,
        const int64_t *field_values);
    int elmc_pebble_dispatch_tag_record_int_fields(
        ElmcPebbleApp *app,
        int64_t tag,
        int field_count,
        const char **field_names,
        const int64_t *field_values);
    int elmc_pebble_msg_from_appmessage(int32_t key, int32_t value, int64_t *out_tag);
    int elmc_pebble_dispatch_appmessage(ElmcPebbleApp *app, int32_t key, int32_t value);
    int elmc_pebble_dispatch_button(ElmcPebbleApp *app, int32_t button_id);
    int elmc_pebble_dispatch_button_raw(ElmcPebbleApp *app, int32_t button_id, int32_t pressed);
    int elmc_pebble_dispatch_accel_tap(ElmcPebbleApp *app, int32_t axis, int32_t direction);
    int elmc_pebble_dispatch_accel_data(ElmcPebbleApp *app, int32_t x, int32_t y, int32_t z);
    int elmc_pebble_dispatch_storage_string(ElmcPebbleApp *app, const char *value);
    int elmc_pebble_dispatch_random_int(ElmcPebbleApp *app, int32_t value);
    int elmc_pebble_dispatch_battery(ElmcPebbleApp *app, int level);
    int elmc_pebble_dispatch_connection(ElmcPebbleApp *app, int connected);
    int elmc_pebble_dispatch_health(ElmcPebbleApp *app, int event);
    int elmc_pebble_dispatch_app_focus(ElmcPebbleApp *app, int in_focus);
    #if ELMC_PEBBLE_FEATURE_COMPASS_EVENTS
    int elmc_pebble_dispatch_compass_heading(ElmcPebbleApp *app, double degrees, int is_valid);
    #endif
    int elmc_pebble_dispatch_dictation_status(ElmcPebbleApp *app, int status);
    int elmc_pebble_dispatch_dictation_result(ElmcPebbleApp *app, int is_ok, int error_code, const char *text);
    int elmc_pebble_dispatch_unobstructed_will_change(ElmcPebbleApp *app, int x, int y, int w, int h);
    int elmc_pebble_dispatch_unobstructed_changing(ElmcPebbleApp *app, int progress);
    int elmc_pebble_dispatch_unobstructed_did_change(ElmcPebbleApp *app);
    int elmc_pebble_dispatch_frame(ElmcPebbleApp *app, int64_t dt_ms, int64_t elapsed_ms, int64_t frame);
    int elmc_pebble_dispatch_hour(ElmcPebbleApp *app, int hour);
    int elmc_pebble_dispatch_minute(ElmcPebbleApp *app, int minute);
    int elmc_pebble_dispatch_day(ElmcPebbleApp *app, int day);
    int elmc_pebble_dispatch_month(ElmcPebbleApp *app, int month);
    int elmc_pebble_dispatch_year(ElmcPebbleApp *app, int year);
    int elmc_pebble_take_cmd(ElmcPebbleApp *app, ElmcPebbleCmd *out_cmd);
    int elmc_pebble_view_command(ElmcPebbleApp *app, ElmcPebbleDrawCmd *out_cmd);
    int elmc_pebble_view_commands(ElmcPebbleApp *app, ElmcPebbleDrawCmd *out_cmds, int max_cmds);
    int elmc_pebble_view_commands_from(ElmcPebbleApp *app, ElmcPebbleDrawCmd *out_cmds, int max_cmds, int skip);
    int elmc_pebble_scene_commands_from(ElmcPebbleApp *app, ElmcPebbleDrawCmd *out_cmds, int max_cmds, int skip);
    void elmc_pebble_scene_reset_draw_cursor(ElmcPebbleApp *app);
    int elmc_pebble_scene_commands_next(ElmcPebbleApp *app, ElmcPebbleDrawCmd *out_cmds, int max_cmds);
    int elmc_pebble_ensure_scene(ElmcPebbleApp *app);
    int elmc_pebble_scene_command_count(ElmcPebbleApp *app);
    int elmc_pebble_scene_dirty_rect(ElmcPebbleApp *app, ElmcPebbleRect *out_rect, int *out_full);
    void elmc_pebble_invalidate_scene(ElmcPebbleApp *app);
    void elmc_pebble_clear_view_cache(ElmcPebbleApp *app);
    int elmc_pebble_tick(ElmcPebbleApp *app);
    int64_t elmc_pebble_active_subscriptions(ElmcPebbleApp *app);
    int64_t elmc_pebble_model_as_int(ElmcPebbleApp *app);
    int elmc_pebble_run_mode(ElmcPebbleApp *app);
    void elmc_pebble_deinit(ElmcPebbleApp *app);

    #if defined(ELMC_PEBBLE_PLATFORM) && ELMC_PEBBLE_HEAP_LOG
    void elmc_pebble_heap_log(const char *label);
    void elmc_pebble_render_diag_log(const char *phase, int render_seq, const ElmcPebbleApp *app);
    #else
    #define elmc_pebble_heap_log(label) do { (void)(label); } while (0)
    #define elmc_pebble_render_diag_log(phase, render_seq, app) \
      do { \
        (void)(phase); \
        (void)(render_seq); \
        (void)(app); \
      } while (0)
    #endif
#endif
