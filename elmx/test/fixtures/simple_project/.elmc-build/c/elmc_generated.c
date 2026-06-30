#include "elmc_generated.h"
#include "elmc_pebble.h"
#include <stdbool.h>
#include <stdio.h>

#if defined(__GNUC__)
#pragma GCC diagnostic ignored "-Wunused-function"
#pragma GCC diagnostic ignored "-Wunused-variable"
#endif

#define ELMC_UNION_ACCELTAP 7
#define ELMC_UNION_BERLIN 2
#define ELMC_UNION_CELSIUS 1
#define ELMC_UNION_CLOCKSTYLE24H 10
#define ELMC_UNION_COMPANION_TYPES_BERLIN 2
#define ELMC_UNION_COMPANION_TYPES_CELSIUS 1
#define ELMC_UNION_COMPANION_TYPES_CURRENTLOCATION 1
#define ELMC_UNION_COMPANION_TYPES_FAHRENHEIT 2
#define ELMC_UNION_COMPANION_TYPES_NEWYORK 4
#define ELMC_UNION_COMPANION_TYPES_PROVIDETEMPERATURE 1
#define ELMC_UNION_COMPANION_TYPES_REQUESTWEATHER 1
#define ELMC_UNION_COMPANION_TYPES_ZURICH 3
#define ELMC_UNION_CURRENTLOCATION 1
#define ELMC_UNION_CURRENTTIMESTRING 9
#define ELMC_UNION_DECREMENT 2
#define ELMC_UNION_DEFAULTFONT 1
#define ELMC_UNION_DOWN 4
#define ELMC_UNION_DOWNPRESSED 6
#define ELMC_UNION_FAHRENHEIT 2
#define ELMC_UNION_FIRMWAREVERSIONSTRING 15
#define ELMC_UNION_INCREMENT 1
#define ELMC_UNION_LAUNCHPHONE 3
#define ELMC_UNION_LAUNCHQUICKLAUNCH 6
#define ELMC_UNION_LAUNCHSMARTSTRAP 8
#define ELMC_UNION_LAUNCHSYSTEM 1
#define ELMC_UNION_LAUNCHTIMELINEACTION 7
#define ELMC_UNION_LAUNCHUNKNOWN 9
#define ELMC_UNION_LAUNCHUSER 2
#define ELMC_UNION_LAUNCHWAKEUP 4
#define ELMC_UNION_LAUNCHWORKER 5
#define ELMC_UNION_MAIN_ACCELTAP 7
#define ELMC_UNION_MAIN_CLOCKSTYLE24H 10
#define ELMC_UNION_MAIN_CURRENTTIMESTRING 9
#define ELMC_UNION_MAIN_DECREMENT 2
#define ELMC_UNION_MAIN_DOWNPRESSED 6
#define ELMC_UNION_MAIN_FIRMWAREVERSIONSTRING 15
#define ELMC_UNION_MAIN_INCREMENT 1
#define ELMC_UNION_MAIN_PROVIDETEMPERATURE 8
#define ELMC_UNION_MAIN_SELECTPRESSED 5
#define ELMC_UNION_MAIN_TICK 3
#define ELMC_UNION_MAIN_TIMEZONEISSET 11
#define ELMC_UNION_MAIN_TIMEZONENAME 12
#define ELMC_UNION_MAIN_UPPRESSED 4
#define ELMC_UNION_MAIN_WATCHCOLORNAME 14
#define ELMC_UNION_MAIN_WATCHMODELNAME 13
#define ELMC_UNION_NEWYORK 4
#define ELMC_UNION_PEBBLE_BUTTON_DOWN 4
#define ELMC_UNION_PEBBLE_BUTTON_SELECT 3
#define ELMC_UNION_PEBBLE_BUTTON_UP 2
#define ELMC_UNION_PEBBLE_PLATFORM_LAUNCHPHONE 3
#define ELMC_UNION_PEBBLE_PLATFORM_LAUNCHQUICKLAUNCH 6
#define ELMC_UNION_PEBBLE_PLATFORM_LAUNCHSMARTSTRAP 8
#define ELMC_UNION_PEBBLE_PLATFORM_LAUNCHSYSTEM 1
#define ELMC_UNION_PEBBLE_PLATFORM_LAUNCHTIMELINEACTION 7
#define ELMC_UNION_PEBBLE_PLATFORM_LAUNCHUNKNOWN 9
#define ELMC_UNION_PEBBLE_PLATFORM_LAUNCHUSER 2
#define ELMC_UNION_PEBBLE_PLATFORM_LAUNCHWAKEUP 4
#define ELMC_UNION_PEBBLE_PLATFORM_LAUNCHWORKER 5
#define ELMC_UNION_PEBBLE_UI_RESOURCES_DEFAULTFONT 1
#define ELMC_UNION_PEBBLE_UI_ROTATION 1
#define ELMC_UNION_PEBBLE_UI_WAITINGFORCOMPANION 1
#define ELMC_UNION_REQUESTWEATHER 1
#define ELMC_UNION_ROTATION 1
#define ELMC_UNION_SELECT 3
#define ELMC_UNION_SELECTPRESSED 5
#define ELMC_UNION_TICK 3
#define ELMC_UNION_TIMEZONEISSET 11
#define ELMC_UNION_TIMEZONENAME 12
#define ELMC_UNION_UP 2
#define ELMC_UNION_UPPRESSED 4
#define ELMC_UNION_WAITINGFORCOMPANION 1
#define ELMC_UNION_WATCHCOLORNAME 14
#define ELMC_UNION_WATCHMODELNAME 13
#define ELMC_UNION_ZURICH 3

const char *elmc_debug_union_ctor_name(elmc_int_t tag) {
  switch (tag) {
    case 10: return "ClockStyle24h";
    case 11: return "TimezoneIsSet";
    case 12: return "TimezoneName";
    case 13: return "WatchModelName";
    case 14: return "WatchColorName";
    case 15: return "FirmwareVersionString";
    default: return NULL;
  }
}

#define ELMC_FIELD_MAIN_MODEL_TEMPERATURE 1
#define ELMC_FIELD_MAIN_MODEL_VALUE 0
#define ELMC_FIELD_PEBBLE_ACCEL_CONFIG_SAMPLESPERUPDATE 0
#define ELMC_FIELD_PEBBLE_ACCEL_CONFIG_SAMPLINGRATE 1
#define ELMC_FIELD_PEBBLE_ACCEL_SAMPLE_X 0
#define ELMC_FIELD_PEBBLE_ACCEL_SAMPLE_Y 1
#define ELMC_FIELD_PEBBLE_ACCEL_SAMPLE_Z 2
#define ELMC_FIELD_PEBBLE_CMD_CURRENTDATETIME_DAY 2
#define ELMC_FIELD_PEBBLE_CMD_CURRENTDATETIME_DAYOFWEEK 3
#define ELMC_FIELD_PEBBLE_CMD_CURRENTDATETIME_HOUR 4
#define ELMC_FIELD_PEBBLE_CMD_CURRENTDATETIME_MINUTE 5
#define ELMC_FIELD_PEBBLE_CMD_CURRENTDATETIME_MONTH 1
#define ELMC_FIELD_PEBBLE_CMD_CURRENTDATETIME_SECOND 6
#define ELMC_FIELD_PEBBLE_CMD_CURRENTDATETIME_UTCOFFSETMINUTES 7
#define ELMC_FIELD_PEBBLE_CMD_CURRENTDATETIME_YEAR 0
#define ELMC_FIELD_PEBBLE_COMPASS_HEADING_DEGREES 0
#define ELMC_FIELD_PEBBLE_COMPASS_HEADING_ISVALID 1
#define ELMC_FIELD_PEBBLE_FRAME_FRAME_DTMS 0
#define ELMC_FIELD_PEBBLE_FRAME_FRAME_ELAPSEDMS 1
#define ELMC_FIELD_PEBBLE_FRAME_FRAME_FRAME 2
#define ELMC_FIELD_PEBBLE_GAME_COLLISION_CIRCLE_R 2
#define ELMC_FIELD_PEBBLE_GAME_COLLISION_CIRCLE_X 0
#define ELMC_FIELD_PEBBLE_GAME_COLLISION_CIRCLE_Y 1
#define ELMC_FIELD_PEBBLE_GAME_COLLISION_RECT_H 3
#define ELMC_FIELD_PEBBLE_GAME_COLLISION_RECT_W 2
#define ELMC_FIELD_PEBBLE_GAME_COLLISION_RECT_X 0
#define ELMC_FIELD_PEBBLE_GAME_COLLISION_RECT_Y 1
#define ELMC_FIELD_PEBBLE_GAME_MATH_VEC2_X 0
#define ELMC_FIELD_PEBBLE_GAME_MATH_VEC2_Y 1
#define ELMC_FIELD_PEBBLE_GAME_SPRITE_SPRITE_BITMAP 0
#define ELMC_FIELD_PEBBLE_GAME_SPRITE_SPRITE_H 4
#define ELMC_FIELD_PEBBLE_GAME_SPRITE_SPRITE_W 3
#define ELMC_FIELD_PEBBLE_GAME_SPRITE_SPRITE_X 1
#define ELMC_FIELD_PEBBLE_GAME_SPRITE_SPRITE_Y 2
#define ELMC_FIELD_PEBBLE_PLATFORM_LAUNCHCONTEXT_HASCOMPASS 5
#define ELMC_FIELD_PEBBLE_PLATFORM_LAUNCHCONTEXT_HASMICROPHONE 4
#define ELMC_FIELD_PEBBLE_PLATFORM_LAUNCHCONTEXT_LAUNCHBUTTON 7
#define ELMC_FIELD_PEBBLE_PLATFORM_LAUNCHCONTEXT_QUICKLAUNCHACTION 8
#define ELMC_FIELD_PEBBLE_PLATFORM_LAUNCHCONTEXT_REASON 0
#define ELMC_FIELD_PEBBLE_PLATFORM_LAUNCHCONTEXT_SCREEN 3
#define ELMC_FIELD_PEBBLE_PLATFORM_LAUNCHCONTEXT_SUPPORTSHEALTH 6
#define ELMC_FIELD_PEBBLE_PLATFORM_LAUNCHCONTEXT_WATCHMODEL 1
#define ELMC_FIELD_PEBBLE_PLATFORM_LAUNCHCONTEXT_WATCHPROFILEID 2
#define ELMC_FIELD_PEBBLE_PLATFORM_LAUNCHSCREEN_COLORMODE 3
#define ELMC_FIELD_PEBBLE_PLATFORM_LAUNCHSCREEN_HEIGHT 1
#define ELMC_FIELD_PEBBLE_PLATFORM_LAUNCHSCREEN_SHAPE 2
#define ELMC_FIELD_PEBBLE_PLATFORM_LAUNCHSCREEN_WIDTH 0
#define ELMC_FIELD_PEBBLE_SPEAKER_LIMITS_MAXNOTES 0
#define ELMC_FIELD_PEBBLE_SPEAKER_LIMITS_MAXSAMPLEBYTESTOTAL 2
#define ELMC_FIELD_PEBBLE_SPEAKER_LIMITS_MAXTRACKS 1
#define ELMC_FIELD_PEBBLE_SPEAKER_NOTE_DURATIONMS 2
#define ELMC_FIELD_PEBBLE_SPEAKER_NOTE_MIDINOTE 0
#define ELMC_FIELD_PEBBLE_SPEAKER_NOTE_VELOCITY 3
#define ELMC_FIELD_PEBBLE_SPEAKER_NOTE_WAVEFORM 1
#define ELMC_FIELD_PEBBLE_SPEAKER_TRACK_NOTES 0
#define ELMC_FIELD_PEBBLE_SPEAKER_TRACK_SAMPLE 1
#define ELMC_FIELD_PEBBLE_SPEAKER_RESOURCES_SAMPLEINFO_BASEMIDINOTE 3
#define ELMC_FIELD_PEBBLE_SPEAKER_RESOURCES_SAMPLEINFO_FORMAT 2
#define ELMC_FIELD_PEBBLE_SPEAKER_RESOURCES_SAMPLEINFO_LOOP 4
#define ELMC_FIELD_PEBBLE_SPEAKER_RESOURCES_SAMPLEINFO_NAME 1
#define ELMC_FIELD_PEBBLE_SPEAKER_RESOURCES_SAMPLEINFO_NUMBYTES 5
#define ELMC_FIELD_PEBBLE_SPEAKER_RESOURCES_SAMPLEINFO_SAMPLE 0
#define ELMC_FIELD_PEBBLE_TIME_CURRENTDATETIME_DAY 2
#define ELMC_FIELD_PEBBLE_TIME_CURRENTDATETIME_DAYOFWEEK 3
#define ELMC_FIELD_PEBBLE_TIME_CURRENTDATETIME_HOUR 4
#define ELMC_FIELD_PEBBLE_TIME_CURRENTDATETIME_MINUTE 5
#define ELMC_FIELD_PEBBLE_TIME_CURRENTDATETIME_MONTH 1
#define ELMC_FIELD_PEBBLE_TIME_CURRENTDATETIME_SECOND 6
#define ELMC_FIELD_PEBBLE_TIME_CURRENTDATETIME_UTCOFFSETMINUTES 7
#define ELMC_FIELD_PEBBLE_TIME_CURRENTDATETIME_YEAR 0
#define ELMC_FIELD_PEBBLE_UI_POINT_X 0
#define ELMC_FIELD_PEBBLE_UI_POINT_Y 1
#define ELMC_FIELD_PEBBLE_UI_RECT_H 3
#define ELMC_FIELD_PEBBLE_UI_RECT_W 2
#define ELMC_FIELD_PEBBLE_UI_RECT_X 0
#define ELMC_FIELD_PEBBLE_UI_RECT_Y 1
#define ELMC_FIELD_PEBBLE_UI_TEXTOPTIONS_ALIGNMENT 0
#define ELMC_FIELD_PEBBLE_UI_TEXTOPTIONS_OVERFLOW 1
#define ELMC_FIELD_PEBBLE_UI_RESOURCES_ANIMATEDBITMAPINFO_ANIMATEDBITMAP 0
#define ELMC_FIELD_PEBBLE_UI_RESOURCES_ANIMATEDBITMAPINFO_DURATIONMS 5
#define ELMC_FIELD_PEBBLE_UI_RESOURCES_ANIMATEDBITMAPINFO_FRAMECOUNT 4
#define ELMC_FIELD_PEBBLE_UI_RESOURCES_ANIMATEDBITMAPINFO_HEIGHT 3
#define ELMC_FIELD_PEBBLE_UI_RESOURCES_ANIMATEDBITMAPINFO_NAME 1
#define ELMC_FIELD_PEBBLE_UI_RESOURCES_ANIMATEDBITMAPINFO_WIDTH 2
#define ELMC_FIELD_PEBBLE_UI_RESOURCES_ANIMATEDVECTORINFO_ANIMATEDVECTOR 0
#define ELMC_FIELD_PEBBLE_UI_RESOURCES_ANIMATEDVECTORINFO_NAME 1
#define ELMC_FIELD_PEBBLE_UI_RESOURCES_FONTINFO_FONT 0
#define ELMC_FIELD_PEBBLE_UI_RESOURCES_FONTINFO_HEIGHT 2
#define ELMC_FIELD_PEBBLE_UI_RESOURCES_FONTINFO_NAME 1
#define ELMC_FIELD_PEBBLE_UI_RESOURCES_STATICBITMAPINFO_HEIGHT 3
#define ELMC_FIELD_PEBBLE_UI_RESOURCES_STATICBITMAPINFO_NAME 1
#define ELMC_FIELD_PEBBLE_UI_RESOURCES_STATICBITMAPINFO_STATICBITMAP 0
#define ELMC_FIELD_PEBBLE_UI_RESOURCES_STATICBITMAPINFO_WIDTH 2
#define ELMC_FIELD_PEBBLE_UI_RESOURCES_STATICVECTORINFO_NAME 1
#define ELMC_FIELD_PEBBLE_UI_RESOURCES_STATICVECTORINFO_STATICVECTOR 0
#define ELMC_FIELD_PEBBLE_WATCHINFO_FIRMWAREVERSION_MAJOR 0
#define ELMC_FIELD_PEBBLE_WATCHINFO_FIRMWAREVERSION_MINOR 1
#define ELMC_FIELD_PEBBLE_WATCHINFO_FIRMWAREVERSION_PATCH 2

#define ELMC_RESOURCE_SLOT_DEFAULTFONT 1

#define ELMC_RENDER_OP_CLEAR 2
#define ELMC_RENDER_OP_PIXEL 3
#define ELMC_RENDER_OP_LINE 4
#define ELMC_RENDER_OP_PUSH_CONTEXT 10
#define ELMC_RENDER_OP_POP_CONTEXT 11
#define ELMC_RENDER_OP_STROKE_WIDTH 12
#define ELMC_RENDER_OP_ANTIALIASED 13
#define ELMC_RENDER_OP_STROKE_COLOR 14
#define ELMC_RENDER_OP_FILL_COLOR 15
#define ELMC_RENDER_OP_TEXT_COLOR 16
#define ELMC_RENDER_OP_ROUND_RECT 17
#define ELMC_RENDER_OP_ARC 18
#define ELMC_RENDER_OP_PATH_FILLED 20
#define ELMC_RENDER_OP_PATH_OUTLINE 21
#define ELMC_RENDER_OP_PATH_OUTLINE_OPEN 22
#define ELMC_RENDER_OP_TEXT_INT_WITH_FONT 27
#define ELMC_RENDER_OP_TEXT_LABEL_WITH_FONT 28
#define ELMC_BUTTON_UP 1
#define ELMC_BUTTON_SELECT 2
#define ELMC_BUTTON_DOWN 3
#define ELMC_BUTTON_EVENT_PRESSED 1
#define ELMC_SUBSCRIPTION_SECOND_CHANGE 1
#define ELMC_SUBSCRIPTION_ACCEL_TAP 16
#define ELMC_SUBSCRIPTION_BUTTON_RAW 16384
#define ELMC_COLOR_BLACK 192
#define ELMC_COLOR_WHITE 255

#if defined(PBL_PLATFORM_APLITE) || defined(PBL_PLATFORM_BASALT) || defined(PBL_PLATFORM_CHALK) || defined(PBL_PLATFORM_DIORITE) || defined(PBL_PLATFORM_FLINT) || defined(PBL_PLATFORM_EMERY) || defined(PBL_PLATFORM_GABBRO)
#include <pebble.h>
static inline void elmc_agent_generated_probe(uint32_t tag) {
  static uint32_t seen_tags[16];
  static int seen_count = 0;
  for (int i = 0; i < seen_count; i++) {
    if (seen_tags[i] == tag) return;
  }
  if (seen_count >= 16) return;
  DataLoggingSessionRef session = data_logging_create(tag, DATA_LOGGING_BYTE_ARRAY, 1, false);
  if (session) {
    seen_tags[seen_count++] = tag;
    data_logging_finish(session);
  }
}
#else
static inline void elmc_agent_generated_probe(uint32_t tag) {
  (void)tag;
}
#endif

static inline ElmcValue *elmc_render_cmd6(
elmc_int_t kind, elmc_int_t p0, elmc_int_t p1, elmc_int_t p2,
elmc_int_t p3, elmc_int_t p4, elmc_int_t p5) {
  ElmcValue *params = elmc_tuple2_take_value(
  elmc_new_int_take(p0),
  elmc_tuple2_take_value(
  elmc_new_int_take(p1),
  elmc_tuple2_take_value(
  elmc_new_int_take(p2),
  elmc_tuple2_take_value(
  elmc_new_int_take(p3),
  elmc_tuple2_take_value(
  elmc_new_int_take(p4),
  elmc_tuple2_take_value(elmc_new_int_take(p5), elmc_int_zero()))))));
  return elmc_tuple2_take_value(elmc_new_int_take(kind), params);
}

static elmc_int_t elmc_fn_Main_helper_native(const elmc_int_t value);
static elmc_int_t elmc_fn_Main_advanced_native(const elmc_int_t n);
static elmc_int_t elmc_fn_Main_counterOf_native(ElmcValue * const model);

static ElmcValue *elmc_fn_Main_helper(ElmcValue ** const args, const int argc);
static ElmcValue *elmc_fn_Main_advanced(ElmcValue ** const args, const int argc);
static ElmcValue *elmc_fn_Main_counterOf(ElmcValue ** const args, const int argc);
static RC elmc_fn_Main_temperatureOf(ElmcValue **out, ElmcValue ** const args, const int argc);
static RC elmc_fn_Main_requestWeather(ElmcValue **out, ElmcValue ** const args, const int argc);
static RC elmc_fn_Main_requestSystemInfo(ElmcValue **out, ElmcValue ** const args, const int argc);
RC elmc_fn_Main_init(ElmcValue **out, ElmcValue ** const args, const int argc);
RC elmc_fn_Main_update(ElmcValue **out, ElmcValue ** const args, const int argc);
static RC elmc_fn_Main_handleAppMsg(ElmcValue **out, ElmcValue ** const args, const int argc);
static RC elmc_fn_Main_handlePlatformMsg(ElmcValue **out, ElmcValue ** const args, const int argc);
RC elmc_fn_Main_subscriptions(ElmcValue **out, ElmcValue ** const args, const int argc);
static RC elmc_fn_Main_statusDraw(ElmcValue **out, ElmcValue ** const args, const int argc);
static RC elmc_fn_Main_counterDraw(ElmcValue **out, ElmcValue ** const args, const int argc);
static RC elmc_fn_Main_temperatureValue(ElmcValue **out, ElmcValue ** const args, const int argc);
static ElmcValue *elmc_fn_Main_main(ElmcValue ** const args, const int argc);
static RC elmc_fn_Pebble_Platform_launchReasonToInt(ElmcValue **out, ElmcValue ** const args, const int argc);
static RC elmc_fn_Companion_Internal_encodeLocationCode(ElmcValue **out, ElmcValue ** const args, const int argc);
static RC elmc_fn_Companion_Internal_watchToPhoneTag(ElmcValue **out, ElmcValue ** const args, const int argc);
static RC elmc_fn_Companion_Internal_watchToPhoneValue(ElmcValue **out, ElmcValue ** const args, const int argc);
static RC elmc_fn_Companion_Watch_sendWatchToPhone(ElmcValue **out, ElmcValue ** const args, const int argc);

static ElmcValue *elmc_fn_Main_helper(ElmcValue ** const args, const int argc) {
  /* Ownership policy: borrow_arg, borrow_result */

  elmc_int_t value = (argc > 0 && args[0]) ? elmc_as_int(args[0]) : 0;

  ElmcValue *out = NULL;
  RC Rc = RC_SUCCESS;
  CATCH_BEGIN
    Rc = elmc_new_int(&out, elmc_fn_Main_helper_native(value));
    CHECK_RC(Rc);
  CATCH_END
  return out;
}

static elmc_int_t elmc_fn_Main_helper_native(const elmc_int_t value) {

  return (value + 2);
}

static ElmcValue *elmc_fn_Main_advanced(ElmcValue ** const args, const int argc) {
  /* Ownership policy: borrow_arg, borrow_result */

  elmc_int_t n = (argc > 0 && args[0]) ? elmc_as_int(args[0]) : 0;

  ElmcValue *out = NULL;
  RC Rc = RC_SUCCESS;
  CATCH_BEGIN
    Rc = elmc_new_int(&out, elmc_fn_Main_advanced_native(n));
    CHECK_RC(Rc);
  CATCH_END
  return out;
}

static elmc_int_t elmc_fn_Main_advanced_native(const elmc_int_t n) {

  // inlined Main.helper

  const elmc_int_t native_let_base_1 = (n + 2);

  elmc_int_t native_if_1;
  if ((native_let_base_1 > 10)) {

    native_if_1 = native_let_base_1;
  } else {

    native_if_1 = (native_let_base_1 + 1);
  }

  return native_if_1;
}

static ElmcValue *elmc_fn_Main_counterOf(ElmcValue ** const args, const int argc) {
  /* Ownership policy: borrow_arg, borrow_result */

  ElmcValue *model = (argc > 0) ? args[0] : NULL;

  ElmcValue *out = NULL;
  RC Rc = RC_SUCCESS;
  CATCH_BEGIN
    Rc = elmc_new_int(&out, elmc_fn_Main_counterOf_native(model));
    CHECK_RC(Rc);
  CATCH_END
  return out;
}

static elmc_int_t elmc_fn_Main_counterOf_native(ElmcValue * const model) {

  return ELMC_RECORD_GET_INDEX_INT(model, ELMC_FIELD_MAIN_MODEL_VALUE);
}

static RC elmc_fn_Main_temperatureOf(ElmcValue **out, ElmcValue ** const args, const int argc) {
  /* Ownership policy: borrow_arg, borrow_result */
  RC Rc = RC_SUCCESS;
  ElmcValue *owned[1] = {0};

  ElmcValue *model = (argc > 0) ? args[0] : NULL;

  owned[0] = elmc_record_get_index(model, ELMC_FIELD_MAIN_MODEL_TEMPERATURE);

  *out = owned[0];
  owned[0] = NULL;

  elmc_release_array_lifo(owned, DIM(owned));
  return Rc;
}

static RC elmc_fn_Main_requestWeather(ElmcValue **out, ElmcValue ** const args, const int argc) {
  /* Ownership policy: borrow_arg, borrow_result */
  RC Rc = RC_SUCCESS;
  ElmcValue *owned[4] = {0};

  ElmcValue *location = (argc > 0) ? args[0] : NULL;

  CATCH_BEGIN

    Rc = elmc_new_int(&owned[0], ELMC_UNION_COMPANION_TYPES_REQUESTWEATHER);
    CHECK_RC(Rc);
    owned[1] = elmc_retain(location);
    Rc = elmc_tuple2_take(&owned[2], owned[0], owned[1]);
    CHECK_RC(Rc);
    owned[0] = NULL;
    owned[1] = NULL;

    ElmcValue *call_args_4[1] = { owned[2] };
    Rc = elmc_fn_Companion_Watch_sendWatchToPhone(out, call_args_4, 1);
    CHECK_RC(Rc);

  CATCH_END;

  elmc_release_array_lifo(owned, DIM(owned));
  return Rc;
}

static RC elmc_fn_Main_requestSystemInfo(ElmcValue **out, ElmcValue ** const args, const int argc) {
  /* Ownership policy: borrow_arg, borrow_result */
  RC Rc = RC_SUCCESS;
  ElmcValue *owned[2] = {0};
  (void)args;
  (void)argc;

  CATCH_BEGIN

    ElmcValue *tmp_1 = elmc_cmd1(ELMC_PEBBLE_CMD_GET_CURRENT_TIME_STRING, ELMC_PEBBLE_MSG_CURRENTTIMESTRING);

    ElmcValue *tmp_2 = elmc_cmd1(ELMC_PEBBLE_CMD_GET_CLOCK_STYLE_24H, ELMC_PEBBLE_MSG_CLOCKSTYLE24H);

    ElmcValue *tmp_3 = elmc_cmd1(ELMC_PEBBLE_CMD_GET_TIMEZONE_IS_SET, ELMC_PEBBLE_MSG_TIMEZONEISSET);

    ElmcValue *tmp_4 = elmc_cmd1(ELMC_PEBBLE_CMD_GET_TIMEZONE, ELMC_PEBBLE_MSG_TIMEZONENAME);

    ElmcValue *tmp_5 = elmc_cmd1(ELMC_PEBBLE_CMD_GET_WATCH_MODEL, ELMC_PEBBLE_MSG_WATCHMODELNAME);

    ElmcValue *tmp_6 = elmc_cmd1(ELMC_PEBBLE_CMD_GET_WATCH_COLOR, ELMC_PEBBLE_MSG_WATCHCOLORNAME);

    ElmcValue *tmp_7 = elmc_cmd1(ELMC_PEBBLE_CMD_GET_FIRMWARE_VERSION, ELMC_PEBBLE_MSG_FIRMWAREVERSIONSTRING);

    ElmcValue *list_items_8[7] = { tmp_1, tmp_2, tmp_3, tmp_4, tmp_5, tmp_6, tmp_7 };
    Rc = elmc_list_from_values_take(&owned[0], list_items_8, 7);
    CHECK_RC(Rc);

    owned[1] = elmc_cmd_batch(owned[0]);

    *out = owned[1];
    owned[1] = NULL;
  CATCH_END;

  elmc_release_array_lifo(owned, DIM(owned));
  return Rc;
}

RC elmc_fn_Main_init(ElmcValue **out, ElmcValue ** const args, const int argc) {
  /* Ownership policy: borrow_arg, borrow_result */
  RC Rc = RC_SUCCESS;
  ElmcValue *owned[7] = {0};

  ElmcValue *launchContext = (argc > 0) ? args[0] : NULL;

  CATCH_BEGIN

    ElmcValue *call_args_1[1] = { ELMC_RECORD_GET_INDEX(launchContext, ELMC_FIELD_PEBBLE_PLATFORM_LAUNCHCONTEXT_REASON) };
    Rc = elmc_fn_Pebble_Platform_launchReasonToInt(&owned[0], call_args_1, 1);
    CHECK_RC(Rc);

    const elmc_int_t native_i_3 = elmc_as_int(owned[0]);
    ;

    const elmc_int_t native_let_initial_4 = native_i_3;

    ElmcValue *tmp_4_boxed_int = NULL;
    Rc = elmc_new_int(&tmp_4_boxed_int, native_let_initial_4);
    CHECK_RC(Rc);

    ElmcValue *tmp_5 = elmc_maybe_nothing();

    ElmcValue *rec_values_1[2] = { tmp_4_boxed_int, tmp_5 };
    Rc = elmc_record_new_values_take(&owned[1], 2, rec_values_1);
    CHECK_RC(Rc);

    Rc = elmc_new_int(&owned[2], ELMC_UNION_COMPANION_TYPES_BERLIN);
    CHECK_RC(Rc);

    ElmcValue *call_args_6[1] = { owned[2] };
    Rc = elmc_fn_Main_requestWeather(&owned[3], call_args_6, 1);
    CHECK_RC(Rc);

    Rc = elmc_fn_Main_requestSystemInfo(&owned[4], NULL, 0);
    CHECK_RC(Rc);

    ElmcValue *list_items_8[2] = { owned[3], owned[4] };
    Rc = elmc_list_from_values_take(&owned[5], list_items_8, 2);
    CHECK_RC(Rc);
    owned[3] = NULL;
    owned[4] = NULL;

    owned[6] = elmc_cmd_batch(owned[5]);

    Rc = elmc_tuple2_take(out, owned[1], owned[6]);
    CHECK_RC(Rc);
    owned[1] = NULL;
    owned[6] = NULL;

  CATCH_END;

  elmc_release_array_lifo(owned, DIM(owned));
  return Rc;
}

RC elmc_fn_Main_update(ElmcValue **out, ElmcValue ** const args, const int argc) {
  /* Ownership policy: borrow_arg, borrow_result */
  RC Rc = RC_SUCCESS;
  ElmcValue *owned[6] = {0};

  ElmcValue *msg = (argc > 0) ? args[0] : NULL;
  ElmcValue *model = (argc > 1) ? args[1] : NULL;

  CATCH_BEGIN

    const int case_msg_tag_1 = (msg && (msg)->tag == ELMC_TAG_INT ? elmc_as_int(msg) : (msg && (msg)->tag == ELMC_TAG_TUPLE2 && (msg)->payload != NULL ? elmc_as_int(((ElmcTuple2 *)(msg)->payload)->first) : -1));

    switch (case_msg_tag_1) {
      case ELMC_PEBBLE_MSG_TICK: {

        ElmcValue *call_args_2[2] = { msg, model };
        Rc = elmc_fn_Main_handlePlatformMsg(&owned[0], call_args_2, 2);
        CHECK_RC(Rc);

        *out = owned[0];
        owned[0] = NULL;
        break;
      }
      case ELMC_PEBBLE_MSG_UPPRESSED: {

        ElmcValue *call_args_4[2] = { msg, model };
        Rc = elmc_fn_Main_handlePlatformMsg(&owned[1], call_args_4, 2);
        CHECK_RC(Rc);

        *out = owned[1];
        owned[1] = NULL;
        break;
      }
      case ELMC_PEBBLE_MSG_SELECTPRESSED: {

        ElmcValue *call_args_6[2] = { msg, model };
        Rc = elmc_fn_Main_handlePlatformMsg(&owned[2], call_args_6, 2);
        CHECK_RC(Rc);

        *out = owned[2];
        owned[2] = NULL;
        break;
      }
      case ELMC_PEBBLE_MSG_DOWNPRESSED: {

        ElmcValue *call_args_8[2] = { msg, model };
        Rc = elmc_fn_Main_handlePlatformMsg(&owned[3], call_args_8, 2);
        CHECK_RC(Rc);

        *out = owned[3];
        owned[3] = NULL;
        break;
      }
      case ELMC_PEBBLE_MSG_ACCELTAP: {

        ElmcValue *call_args_10[2] = { msg, model };
        Rc = elmc_fn_Main_handlePlatformMsg(&owned[4], call_args_10, 2);
        CHECK_RC(Rc);

        *out = owned[4];
        owned[4] = NULL;
        break;
      }
      default: {

        ElmcValue *call_args_12[2] = { msg, model };
        Rc = elmc_fn_Main_handleAppMsg(&owned[5], call_args_12, 2);
        CHECK_RC(Rc);

        *out = owned[5];
        owned[5] = NULL;
        break;
      }

    }

  CATCH_END;

  elmc_release_array_lifo(owned, DIM(owned));
  return Rc;
}

static RC elmc_fn_Main_handleAppMsg(ElmcValue **out, ElmcValue ** const args, const int argc) {
  /* Ownership policy: borrow_arg, borrow_result */
  RC Rc = RC_SUCCESS;
  ElmcValue *owned[22] = {0};

  ElmcValue *msg = (argc > 0) ? args[0] : NULL;
  ElmcValue *model = (argc > 1) ? args[1] : NULL;

  CATCH_BEGIN

    const int case_msg_tag_1 = (msg && (msg)->tag == ELMC_TAG_INT ? elmc_as_int(msg) : (msg && (msg)->tag == ELMC_TAG_TUPLE2 && (msg)->payload != NULL ? elmc_as_int(((ElmcTuple2 *)(msg)->payload)->first) : -1));

    switch (case_msg_tag_1) {
      case ELMC_PEBBLE_MSG_INCREMENT: {

        // inlined Main.counterOf

        const elmc_int_t native_let_counter_2 = ELMC_RECORD_GET_INDEX_INT(model, ELMC_FIELD_MAIN_MODEL_VALUE);

        ElmcValue *tmp_2_boxed_int = NULL;
        Rc = elmc_new_int(&tmp_2_boxed_int, (native_let_counter_2 + 1));
        CHECK_RC(Rc);

        ElmcValue *call_args_3[1] = { model };
        Rc = elmc_fn_Main_temperatureOf(&owned[0], call_args_3, 1);
        CHECK_RC(Rc);

        ElmcValue *rec_values_2[2] = { tmp_2_boxed_int, owned[0] };
        Rc = elmc_record_new_values_take(out, 2, rec_values_2);
        CHECK_RC(Rc);
        owned[0] = NULL;

        owned[1] = elmc_int_zero();
        Rc = elmc_tuple2_take(out, (*out), owned[1]);
        CHECK_RC(Rc);
        owned[1] = NULL;

        break;
      }
      case ELMC_PEBBLE_MSG_DECREMENT: {

        // inlined Main.counterOf

        const elmc_int_t native_let_counter_5 = ELMC_RECORD_GET_INDEX_INT(model, ELMC_FIELD_MAIN_MODEL_VALUE);

        ElmcValue *tmp_5_boxed_int = NULL;
        Rc = elmc_new_int(&tmp_5_boxed_int, (native_let_counter_5 - 1));
        CHECK_RC(Rc);

        ElmcValue *call_args_6[1] = { model };
        Rc = elmc_fn_Main_temperatureOf(&owned[2], call_args_6, 1);
        CHECK_RC(Rc);

        ElmcValue *rec_values_3[2] = { tmp_5_boxed_int, owned[2] };
        Rc = elmc_record_new_values_take(out, 2, rec_values_3);
        CHECK_RC(Rc);
        owned[2] = NULL;

        owned[3] = elmc_int_zero();
        Rc = elmc_tuple2_take(out, (*out), owned[3]);
        CHECK_RC(Rc);
        owned[3] = NULL;

        break;
      }
      case ELMC_PEBBLE_MSG_PROVIDETEMPERATURE: {

        // inlined Main.counterOf
        ElmcValue *tmp_8_boxed_int = NULL;
        Rc = elmc_new_int(&tmp_8_boxed_int, ELMC_RECORD_GET_INDEX_INT(model, ELMC_FIELD_MAIN_MODEL_VALUE));
        CHECK_RC(Rc);

        owned[4] = ((ElmcTuple2 *)msg->payload)->second ? elmc_retain(((ElmcTuple2 *)msg->payload)->second) : elmc_int_zero();
        ElmcValue *tmp_9 = NULL;
        Rc = elmc_maybe_just(&tmp_9, owned[4]);
        CHECK_RC(Rc);
        owned[4] = NULL;

        ElmcValue *rec_values_4[2] = { tmp_8_boxed_int, tmp_9 };
        Rc = elmc_record_new_values_take(out, 2, rec_values_4);
        CHECK_RC(Rc);

        owned[5] = elmc_int_zero();
        Rc = elmc_tuple2_take(out, (*out), owned[5]);
        CHECK_RC(Rc);
        owned[5] = NULL;

        break;
      }
      case ELMC_PEBBLE_MSG_CURRENTTIMESTRING: {
        owned[6] = model ? elmc_retain(model) : elmc_int_zero();
        owned[7] = elmc_int_zero();
        Rc = elmc_tuple2_take(out, owned[6], owned[7]);
        CHECK_RC(Rc);
        owned[6] = NULL;
        owned[7] = NULL;

        break;
      }
      case ELMC_PEBBLE_MSG_CLOCKSTYLE24H: {
        owned[8] = model ? elmc_retain(model) : elmc_int_zero();
        owned[9] = elmc_int_zero();
        Rc = elmc_tuple2_take(out, owned[8], owned[9]);
        CHECK_RC(Rc);
        owned[8] = NULL;
        owned[9] = NULL;

        break;
      }
      case ELMC_PEBBLE_MSG_TIMEZONEISSET: {
        owned[10] = model ? elmc_retain(model) : elmc_int_zero();
        owned[11] = elmc_int_zero();
        Rc = elmc_tuple2_take(out, owned[10], owned[11]);
        CHECK_RC(Rc);
        owned[10] = NULL;
        owned[11] = NULL;

        break;
      }
      case ELMC_PEBBLE_MSG_TIMEZONENAME: {
        owned[12] = model ? elmc_retain(model) : elmc_int_zero();
        owned[13] = elmc_int_zero();
        Rc = elmc_tuple2_take(out, owned[12], owned[13]);
        CHECK_RC(Rc);
        owned[12] = NULL;
        owned[13] = NULL;

        break;
      }
      case ELMC_PEBBLE_MSG_WATCHMODELNAME: {
        owned[14] = model ? elmc_retain(model) : elmc_int_zero();
        owned[15] = elmc_int_zero();
        Rc = elmc_tuple2_take(out, owned[14], owned[15]);
        CHECK_RC(Rc);
        owned[14] = NULL;
        owned[15] = NULL;

        break;
      }
      case ELMC_PEBBLE_MSG_WATCHCOLORNAME: {
        owned[16] = model ? elmc_retain(model) : elmc_int_zero();
        owned[17] = elmc_int_zero();
        Rc = elmc_tuple2_take(out, owned[16], owned[17]);
        CHECK_RC(Rc);
        owned[16] = NULL;
        owned[17] = NULL;

        break;
      }
      case ELMC_PEBBLE_MSG_FIRMWAREVERSIONSTRING: {
        owned[18] = model ? elmc_retain(model) : elmc_int_zero();
        owned[19] = elmc_int_zero();
        Rc = elmc_tuple2_take(out, owned[18], owned[19]);
        CHECK_RC(Rc);
        owned[18] = NULL;
        owned[19] = NULL;

        break;
      }
      default: {
        owned[20] = model ? elmc_retain(model) : elmc_int_zero();
        owned[21] = elmc_int_zero();
        Rc = elmc_tuple2_take(out, owned[20], owned[21]);
        CHECK_RC(Rc);
        owned[20] = NULL;
        owned[21] = NULL;

        break;
      }

    }

  CATCH_END;

  elmc_release_array_lifo(owned, DIM(owned));
  return Rc;
}

static RC elmc_fn_Main_handlePlatformMsg(ElmcValue **out, ElmcValue ** const args, const int argc) {
  /* Ownership policy: borrow_arg, borrow_result */
  RC Rc = RC_SUCCESS;
  ElmcValue *owned[13] = {0};

  ElmcValue *msg = (argc > 0) ? args[0] : NULL;
  ElmcValue *model = (argc > 1) ? args[1] : NULL;

  CATCH_BEGIN

    const int case_msg_tag_1 = (msg && (msg)->tag == ELMC_TAG_INT ? elmc_as_int(msg) : (msg && (msg)->tag == ELMC_TAG_TUPLE2 && (msg)->payload != NULL ? elmc_as_int(((ElmcTuple2 *)(msg)->payload)->first) : -1));

    switch (case_msg_tag_1) {
      case ELMC_PEBBLE_MSG_TICK: {

        // inlined Main.counterOf

        const elmc_int_t native_let_counter_2 = ELMC_RECORD_GET_INDEX_INT(model, ELMC_FIELD_MAIN_MODEL_VALUE);

        // inlined Main.helper

        const elmc_int_t native_let_base_2 = (native_let_counter_2 + 2);

        elmc_int_t native_if_2;
        if ((native_let_base_2 > 10)) {

        native_if_2 = native_let_base_2;
        } else {

        native_if_2 = (native_let_base_2 + 1);
        }

        // inlined Main.advanced

        const elmc_int_t native_let_next_3 = native_if_2;

        ElmcValue *tmp_3_boxed_int = NULL;
        Rc = elmc_new_int(&tmp_3_boxed_int, native_let_next_3);
        CHECK_RC(Rc);

        ElmcValue *call_args_4[1] = { model };
        Rc = elmc_fn_Main_temperatureOf(&owned[0], call_args_4, 1);
        CHECK_RC(Rc);

        ElmcValue *rec_values_5[2] = { tmp_3_boxed_int, owned[0] };
        Rc = elmc_record_new_values_take(out, 2, rec_values_5);
        CHECK_RC(Rc);
        owned[0] = NULL;

        ElmcValue *tmp_6 = elmc_cmd1(ELMC_PEBBLE_CMD_TIMER_AFTER_MS, 1000);

        Rc = elmc_tuple2_take(out, (*out), tmp_6);
        CHECK_RC(Rc);

        break;
      }
      case ELMC_PEBBLE_MSG_UPPRESSED: {

        // inlined Main.counterOf

        const elmc_int_t native_let_counter_7 = ELMC_RECORD_GET_INDEX_INT(model, ELMC_FIELD_MAIN_MODEL_VALUE);

        Rc = elmc_new_int(&owned[1], (native_let_counter_7 + 1));
        CHECK_RC(Rc);

        ElmcValue *tmp_7_boxed_int = NULL;
        Rc = elmc_new_int(&tmp_7_boxed_int, elmc_as_int(owned[1]));
        CHECK_RC(Rc);

        ElmcValue *call_args_8[1] = { model };
        Rc = elmc_fn_Main_temperatureOf(&owned[2], call_args_8, 1);
        CHECK_RC(Rc);

        ElmcValue *rec_values_6[2] = { tmp_7_boxed_int, owned[2] };
        Rc = elmc_record_new_values_take(out, 2, rec_values_6);
        CHECK_RC(Rc);
        owned[2] = NULL;

        ElmcValue *tmp_10 = elmc_cmd2(ELMC_PEBBLE_CMD_STORAGE_WRITE_INT, 1, elmc_as_int(owned[1]));

        Rc = elmc_tuple2_take(out, (*out), tmp_10);
        CHECK_RC(Rc);

        break;
      }
      case ELMC_PEBBLE_MSG_SELECTPRESSED: {
        owned[3] = model ? elmc_retain(model) : elmc_int_zero();

        Rc = elmc_new_int(&owned[4], ELMC_UNION_COMPANION_TYPES_BERLIN);
        CHECK_RC(Rc);

        ElmcValue *call_args_11[1] = { owned[4] };
        Rc = elmc_fn_Main_requestWeather(&owned[5], call_args_11, 1);
        CHECK_RC(Rc);

        Rc = elmc_fn_Main_requestSystemInfo(&owned[6], NULL, 0);
        CHECK_RC(Rc);

        ElmcValue *list_items_13[2] = { owned[5], owned[6] };
        Rc = elmc_list_from_values_take(out, list_items_13, 2);
        CHECK_RC(Rc);
        owned[5] = NULL;
        owned[6] = NULL;

        owned[7] = elmc_cmd_batch((*out));

        Rc = elmc_tuple2_take(out, owned[3], owned[7]);
        CHECK_RC(Rc);
        owned[3] = NULL;
        owned[7] = NULL;

        break;
      }
      case ELMC_PEBBLE_MSG_DOWNPRESSED: {

        // inlined Main.counterOf

        const elmc_int_t native_let_counter_15 = ELMC_RECORD_GET_INDEX_INT(model, ELMC_FIELD_MAIN_MODEL_VALUE);

        ElmcValue *tmp_15_boxed_int = NULL;
        Rc = elmc_new_int(&tmp_15_boxed_int, (native_let_counter_15 - 1));
        CHECK_RC(Rc);

        ElmcValue *call_args_16[1] = { model };
        Rc = elmc_fn_Main_temperatureOf(&owned[8], call_args_16, 1);
        CHECK_RC(Rc);

        ElmcValue *rec_values_7[2] = { tmp_15_boxed_int, owned[8] };
        Rc = elmc_record_new_values_take(out, 2, rec_values_7);
        CHECK_RC(Rc);
        owned[8] = NULL;

        ElmcValue *tmp_18 = elmc_cmd1(ELMC_PEBBLE_CMD_STORAGE_DELETE, 1);

        Rc = elmc_tuple2_take(out, (*out), tmp_18);
        CHECK_RC(Rc);

        break;
      }
      case ELMC_PEBBLE_MSG_ACCELTAP: {

        // inlined Main.counterOf

        const elmc_int_t native_let_counter_19 = ELMC_RECORD_GET_INDEX_INT(model, ELMC_FIELD_MAIN_MODEL_VALUE);

        ElmcValue *tmp_19_boxed_int = NULL;
        Rc = elmc_new_int(&tmp_19_boxed_int, (native_let_counter_19 + 1));
        CHECK_RC(Rc);

        ElmcValue *call_args_20[1] = { model };
        Rc = elmc_fn_Main_temperatureOf(&owned[9], call_args_20, 1);
        CHECK_RC(Rc);

        ElmcValue *rec_values_8[2] = { tmp_19_boxed_int, owned[9] };
        Rc = elmc_record_new_values_take(out, 2, rec_values_8);
        CHECK_RC(Rc);
        owned[9] = NULL;

        owned[10] = elmc_int_zero();
        Rc = elmc_tuple2_take(out, (*out), owned[10]);
        CHECK_RC(Rc);
        owned[10] = NULL;

        break;
      }
      default: {
        owned[11] = model ? elmc_retain(model) : elmc_int_zero();
        owned[12] = elmc_int_zero();
        Rc = elmc_tuple2_take(out, owned[11], owned[12]);
        CHECK_RC(Rc);
        owned[11] = NULL;
        owned[12] = NULL;

        break;
      }

    }

  CATCH_END;

  elmc_release_array_lifo(owned, DIM(owned));
  return Rc;
}

RC elmc_fn_Main_subscriptions(ElmcValue **out, ElmcValue ** const args, const int argc) {
  /* Ownership policy: borrow_arg, borrow_result */
  RC Rc = RC_SUCCESS;
  ElmcValue *owned[1] = {0};

  ElmcValue *_unused_0 = (argc > 0) ? args[0] : NULL;
  (void)_unused_0;

  CATCH_BEGIN

    ElmcValue *tmp_1 = elmc_sub1(ELMC_SUBSCRIPTION_SECOND_CHANGE, ELMC_PEBBLE_MSG_TICK);

    ElmcValue *tmp_2 = elmc_sub3(ELMC_SUBSCRIPTION_BUTTON_RAW, ELMC_BUTTON_UP, ELMC_BUTTON_EVENT_PRESSED, ELMC_PEBBLE_MSG_UPPRESSED);

    ElmcValue *tmp_3 = elmc_sub3(ELMC_SUBSCRIPTION_BUTTON_RAW, ELMC_BUTTON_SELECT, ELMC_BUTTON_EVENT_PRESSED, ELMC_PEBBLE_MSG_SELECTPRESSED);

    ElmcValue *tmp_4 = elmc_sub3(ELMC_SUBSCRIPTION_BUTTON_RAW, ELMC_BUTTON_DOWN, ELMC_BUTTON_EVENT_PRESSED, ELMC_PEBBLE_MSG_DOWNPRESSED);

    ElmcValue *tmp_5 = elmc_sub1(ELMC_SUBSCRIPTION_ACCEL_TAP, ELMC_PEBBLE_MSG_ACCELTAP);

    ElmcValue *list_items_6[5] = { tmp_1, tmp_2, tmp_3, tmp_4, tmp_5 };
    Rc = elmc_list_from_values_take(&owned[0], list_items_6, 5);
    CHECK_RC(Rc);

    *out = owned[0];
    owned[0] = NULL;
  CATCH_END;

  elmc_release_array_lifo(owned, DIM(owned));
  return Rc;
}

static RC elmc_fn_Main_statusDraw(ElmcValue **out, ElmcValue ** const args, const int argc) {
  /* Ownership policy: borrow_arg, borrow_result */
  RC Rc = RC_SUCCESS;
  ElmcValue *owned[15] = {0};

  ElmcValue *model = (argc > 0) ? args[0] : NULL;

  CATCH_BEGIN

    ElmcValue *call_args_1[1] = { model };
    Rc = elmc_fn_Main_temperatureOf(&owned[0], call_args_1, 1);
    CHECK_RC(Rc);

    if (elmc_maybe_is_just(owned[0])) {
      ElmcValue *call_args_3[1] = { elmc_maybe_or_tuple_just_payload_borrow(owned[0]) };
      Rc = elmc_fn_Main_temperatureValue(&owned[2], call_args_3, 1);
      CHECK_RC(Rc);
      const elmc_int_t native_i_5 = elmc_as_int(owned[2]);
      ;
      owned[1] = elmc_render_cmd6(ELMC_RENDER_OP_TEXT_INT_WITH_FONT, 1, 0, 28, native_i_5, 0, 0);

    } else {
      Rc = elmc_new_int(&owned[3], ELMC_RENDER_OP_TEXT_LABEL_WITH_FONT);
      CHECK_RC(Rc);

      Rc = elmc_new_int(&owned[4], ELMC_RESOURCE_SLOT_DEFAULTFONT);
      CHECK_RC(Rc);
      owned[5] = elmc_int_zero();
      Rc = elmc_new_int(&owned[6], 28);
      CHECK_RC(Rc);
      owned[7] = elmc_int_zero();
      owned[8] = elmc_int_zero();
      Rc = elmc_new_int(&owned[9], ELMC_UNION_PEBBLE_UI_WAITINGFORCOMPANION);
      CHECK_RC(Rc);
      Rc = elmc_tuple2_take(&owned[10], owned[8], owned[9]);
      CHECK_RC(Rc);
      owned[8] = NULL;
      owned[9] = NULL;

      Rc = elmc_tuple2_take(&owned[11], owned[7], owned[10]);
      CHECK_RC(Rc);
      owned[7] = NULL;
      owned[10] = NULL;

      Rc = elmc_tuple2_take(&owned[12], owned[6], owned[11]);
      CHECK_RC(Rc);
      owned[6] = NULL;
      owned[11] = NULL;

      Rc = elmc_tuple2_take(&owned[13], owned[5], owned[12]);
      CHECK_RC(Rc);
      owned[5] = NULL;
      owned[12] = NULL;

      Rc = elmc_tuple2_take(&owned[14], owned[4], owned[13]);
      CHECK_RC(Rc);
      owned[4] = NULL;
      owned[13] = NULL;

      Rc = elmc_tuple2_take(&owned[1], owned[3], owned[14]);
      CHECK_RC(Rc);
      owned[3] = NULL;
      owned[14] = NULL;
    }

    *out = owned[1];
    owned[1] = NULL;
  CATCH_END;

  elmc_release_array_lifo(owned, DIM(owned));
  return Rc;
}

static RC elmc_fn_Main_counterDraw(ElmcValue **out, ElmcValue ** const args, const int argc) {
  /* Ownership policy: borrow_arg, borrow_result */
  RC Rc = RC_SUCCESS;

  ElmcValue *model = (argc > 0) ? args[0] : NULL;

  // inlined Main.counterOf

  const elmc_int_t native_let_counter_1 = ELMC_RECORD_GET_INDEX_INT(model, ELMC_FIELD_MAIN_MODEL_VALUE);

  ElmcValue *tmp_1 = elmc_render_cmd6(ELMC_RENDER_OP_TEXT_INT_WITH_FONT, 1, 0, 56, native_let_counter_1, 0, 0);

  *out = tmp_1;

  return Rc;
}

static RC elmc_fn_Main_temperatureValue(ElmcValue **out, ElmcValue ** const args, const int argc) {
  /* Ownership policy: borrow_arg, borrow_result */
  RC Rc = RC_SUCCESS;
  ElmcValue *owned[3] = {0};

  ElmcValue *temperature = (argc > 0) ? args[0] : NULL;

  if (elmc_union_tag_matches(temperature, 1)) {
    owned[1] = ((ElmcTuple2 *)temperature->payload)->second ? elmc_retain(((ElmcTuple2 *)temperature->payload)->second) : elmc_int_zero();

    owned[0] = owned[1];
    owned[1] = NULL;

  } else {
    owned[2] = ((ElmcTuple2 *)temperature->payload)->second ? elmc_retain(((ElmcTuple2 *)temperature->payload)->second) : elmc_int_zero();

    owned[0] = owned[2];
    owned[2] = NULL;
  }

  *out = owned[0];
  owned[0] = NULL;

  elmc_release_array_lifo(owned, DIM(owned));
  return Rc;
}

static ElmcValue * elmc_fn_Main_main(ElmcValue ** const args, const int argc) {
  /* Ownership policy: borrow_arg, borrow_result */
  (void)args;
  (void)argc;
  ElmcValue *tmp_1 = elmc_int_zero();
  return tmp_1;
}

static RC elmc_fn_Pebble_Platform_launchReasonToInt(ElmcValue **out, ElmcValue ** const args, const int argc) {
  /* Ownership policy: borrow_arg, borrow_result */
  RC Rc = RC_SUCCESS;

  ElmcValue *launchReason = (argc > 0) ? args[0] : NULL;

  CATCH_BEGIN

    const int case_msg_tag_1 = (launchReason && (launchReason)->tag == ELMC_TAG_INT ? elmc_as_int(launchReason) : (launchReason && (launchReason)->tag == ELMC_TAG_TUPLE2 && (launchReason)->payload != NULL ? elmc_as_int(((ElmcTuple2 *)(launchReason)->payload)->first) : -1));

    elmc_int_t case_int_2;
    case_int_2 = 0;
    switch (case_msg_tag_1) {
      case ELMC_UNION_LAUNCHSYSTEM: {
        case_int_2 = 0;
        break;
      }
      case ELMC_UNION_LAUNCHUSER: {
        case_int_2 = 1;
        break;
      }
      case ELMC_UNION_LAUNCHPHONE: {
        case_int_2 = 2;
        break;
      }
      case ELMC_UNION_LAUNCHWAKEUP: {
        case_int_2 = 3;
        break;
      }
      case ELMC_UNION_LAUNCHWORKER: {
        case_int_2 = 4;
        break;
      }
      case ELMC_UNION_LAUNCHQUICKLAUNCH: {
        case_int_2 = 5;
        break;
      }
      case ELMC_UNION_LAUNCHTIMELINEACTION: {
        case_int_2 = 6;
        break;
      }
      case ELMC_UNION_LAUNCHSMARTSTRAP: {
        case_int_2 = 7;
        break;
      }
      case ELMC_UNION_LAUNCHUNKNOWN: {
        case_int_2 = -1;
        break;
      }

    }
    Rc = elmc_new_int(out, case_int_2);
    CHECK_RC(Rc);

  CATCH_END;

  return Rc;
}

static RC elmc_fn_Companion_Internal_encodeLocationCode(ElmcValue **out, ElmcValue ** const args, const int argc) {
  /* Ownership policy: borrow_arg, borrow_result */
  RC Rc = RC_SUCCESS;

  ElmcValue *value = (argc > 0) ? args[0] : NULL;

  CATCH_BEGIN

    const int case_msg_tag_1 = (value && (value)->tag == ELMC_TAG_INT ? elmc_as_int(value) : (value && (value)->tag == ELMC_TAG_TUPLE2 && (value)->payload != NULL ? elmc_as_int(((ElmcTuple2 *)(value)->payload)->first) : -1));

    elmc_int_t case_int_2;
    case_int_2 = 0;
    switch (case_msg_tag_1) {
      case ELMC_UNION_COMPANION_TYPES_CURRENTLOCATION: {
        case_int_2 = 1;
        break;
      }
      case ELMC_UNION_COMPANION_TYPES_BERLIN: {
        case_int_2 = 2;
        break;
      }
      case ELMC_UNION_COMPANION_TYPES_ZURICH: {
        case_int_2 = 3;
        break;
      }
      case ELMC_UNION_COMPANION_TYPES_NEWYORK: {
        case_int_2 = 4;
        break;
      }

    }
    Rc = elmc_new_int(out, case_int_2);
    CHECK_RC(Rc);

  CATCH_END;

  return Rc;
}

static RC elmc_fn_Companion_Internal_watchToPhoneTag(ElmcValue **out, ElmcValue ** const args, const int argc) {
  /* Ownership policy: borrow_arg, borrow_result */
  RC Rc = RC_SUCCESS;
  ElmcValue *owned[1] = {0};

  ElmcValue *message = (argc > 0) ? args[0] : NULL;
  (void)message;

  CATCH_BEGIN

    Rc = elmc_new_int(&owned[0], 2);
    CHECK_RC(Rc);

    *out = owned[0];
    owned[0] = NULL;
  CATCH_END;

  elmc_release_array_lifo(owned, DIM(owned));
  return Rc;
}

static RC elmc_fn_Companion_Internal_watchToPhoneValue(ElmcValue **out, ElmcValue ** const args, const int argc) {
  /* Ownership policy: borrow_arg, borrow_result */
  RC Rc = RC_SUCCESS;
  ElmcValue *owned[2] = {0};

  ElmcValue *message = (argc > 0) ? args[0] : NULL;

  CATCH_BEGIN

    ElmcValue *call_args_2[1] = { ((ElmcTuple2 *)message->payload)->second };
    Rc = elmc_fn_Companion_Internal_encodeLocationCode(&owned[0], call_args_2, 1);
    CHECK_RC(Rc);

    *out = owned[0];
    owned[0] = NULL;
  CATCH_END;

  elmc_release_array_lifo(owned, DIM(owned));
  return Rc;
}

static RC elmc_fn_Companion_Watch_sendWatchToPhone(ElmcValue **out, ElmcValue ** const args, const int argc) {
  /* Ownership policy: borrow_arg, borrow_result */
  RC Rc = RC_SUCCESS;
  ElmcValue *owned[2] = {0};

  ElmcValue *message = (argc > 0) ? args[0] : NULL;

  CATCH_BEGIN

    ElmcValue *call_args_1[1] = { message };
    Rc = elmc_fn_Companion_Internal_watchToPhoneTag(&owned[0], call_args_1, 1);
    CHECK_RC(Rc);

    const elmc_int_t native_i_3 = elmc_as_int(owned[0]);
    ;

    ElmcValue *call_args_4[1] = { message };
    Rc = elmc_fn_Companion_Internal_watchToPhoneValue(&owned[1], call_args_4, 1);
    CHECK_RC(Rc);

    const elmc_int_t native_i_6 = elmc_as_int(owned[1]);
    ;

    ElmcValue *tmp_7 = elmc_cmd2(ELMC_PEBBLE_CMD_COMPANION_SEND, native_i_3, native_i_6);

    *out = tmp_7;
  CATCH_END;

  elmc_release_array_lifo(owned, DIM(owned));
  return Rc;
}

static RC elmc_fn_Main_view_commands_append(ElmcValue ** const args, const int argc, ElmcSceneWriter * const writer);

static RC elmc_fn_Main_view_commands_append(ElmcValue ** const args, const int argc, ElmcSceneWriter * const writer) {
  ElmcValue *model = (argc > 0) ? args[0] : NULL;

  if (!writer)
    return RC_ERR_INVALID_ARG;
  RC Rc = RC_SUCCESS;
  ElmcValue *owned[5] = {0};

  static ElmcPebbleDrawCmd scene_cmd;

  CATCH_BEGIN

    elmc_draw_cmd_init(&scene_cmd, ELMC_RENDER_OP_CLEAR);
    scene_cmd.p0 = ELMC_COLOR_WHITE;
    if (elmc_scene_writer_push_cmd(writer, &scene_cmd) != 0) {
      Rc = RC_ERR_SCENE_BUFFER_OVERFLOW;
      break;
    }

    elmc_draw_cmd_init(&scene_cmd, ELMC_RENDER_OP_PUSH_CONTEXT);

    if (elmc_scene_writer_push_cmd(writer, &scene_cmd) != 0) {
      Rc = RC_ERR_SCENE_BUFFER_OVERFLOW;
      break;
    }

    elmc_draw_cmd_init(&scene_cmd, ELMC_RENDER_OP_STROKE_WIDTH);
    scene_cmd.p0 = 3;
    if (elmc_scene_writer_push_cmd(writer, &scene_cmd) != 0) {
      Rc = RC_ERR_SCENE_BUFFER_OVERFLOW;
      break;
    }

    elmc_draw_cmd_init(&scene_cmd, ELMC_RENDER_OP_ANTIALIASED);
    scene_cmd.p0 = 1;
    if (elmc_scene_writer_push_cmd(writer, &scene_cmd) != 0) {
      Rc = RC_ERR_SCENE_BUFFER_OVERFLOW;
      break;
    }

    elmc_draw_cmd_init(&scene_cmd, ELMC_RENDER_OP_STROKE_COLOR);
    scene_cmd.p0 = ELMC_COLOR_BLACK;
    if (elmc_scene_writer_push_cmd(writer, &scene_cmd) != 0) {
      Rc = RC_ERR_SCENE_BUFFER_OVERFLOW;
      break;
    }

    elmc_draw_cmd_init(&scene_cmd, ELMC_RENDER_OP_FILL_COLOR);
    scene_cmd.p0 = ELMC_COLOR_BLACK;
    if (elmc_scene_writer_push_cmd(writer, &scene_cmd) != 0) {
      Rc = RC_ERR_SCENE_BUFFER_OVERFLOW;
      break;
    }

    elmc_draw_cmd_init(&scene_cmd, ELMC_RENDER_OP_TEXT_COLOR);
    scene_cmd.p0 = ELMC_COLOR_BLACK;
    if (elmc_scene_writer_push_cmd(writer, &scene_cmd) != 0) {
      Rc = RC_ERR_SCENE_BUFFER_OVERFLOW;
      break;
    }

    elmc_draw_cmd_init(&scene_cmd, ELMC_RENDER_OP_ROUND_RECT);
    scene_cmd.p0 = 6;
    scene_cmd.p1 = 6;
    scene_cmd.p2 = 132;
    scene_cmd.p3 = 70;
    scene_cmd.p4 = 6;
    scene_cmd.p5 = ELMC_COLOR_BLACK;
    if (elmc_scene_writer_push_cmd(writer, &scene_cmd) != 0) {
      Rc = RC_ERR_SCENE_BUFFER_OVERFLOW;
      break;
    }

    elmc_draw_cmd_init(&scene_cmd, ELMC_RENDER_OP_ARC);
    scene_cmd.p0 = 20;
    scene_cmd.p1 = 16;
    scene_cmd.p2 = 36;
    scene_cmd.p3 = 36;
    scene_cmd.p4 = 0;
    scene_cmd.p5 = 45000;
    if (elmc_scene_writer_push_cmd(writer, &scene_cmd) != 0) {
      Rc = RC_ERR_SCENE_BUFFER_OVERFLOW;
      break;
    }

    elmc_draw_cmd_init(&scene_cmd, ELMC_RENDER_OP_PATH_OUTLINE);
    scene_cmd.path_point_count = 5;
    scene_cmd.path_offset_x = 86;
    scene_cmd.path_offset_y = 16;
    scene_cmd.path_rotation = 0;
    scene_cmd.path_x[0] = 0;
    scene_cmd.path_y[0] = 0;

    scene_cmd.path_x[1] = 10;
    scene_cmd.path_y[1] = 4;

    scene_cmd.path_x[2] = 16;
    scene_cmd.path_y[2] = 14;

    scene_cmd.path_x[3] = 8;
    scene_cmd.path_y[3] = 24;

    scene_cmd.path_x[4] = 0;
    scene_cmd.path_y[4] = 18;

    if (elmc_scene_writer_push_cmd(writer, &scene_cmd) != 0) {
      Rc = RC_ERR_SCENE_BUFFER_OVERFLOW;
      break;
    }

    elmc_draw_cmd_init(&scene_cmd, ELMC_RENDER_OP_PATH_FILLED);
    scene_cmd.path_point_count = 5;
    scene_cmd.path_offset_x = 108;
    scene_cmd.path_offset_y = 26;
    scene_cmd.path_rotation = 0;
    scene_cmd.path_x[0] = 0;
    scene_cmd.path_y[0] = 0;

    scene_cmd.path_x[1] = 8;
    scene_cmd.path_y[1] = 6;

    scene_cmd.path_x[2] = 6;
    scene_cmd.path_y[2] = 14;

    scene_cmd.path_x[3] = 2;
    scene_cmd.path_y[3] = 20;

    scene_cmd.path_x[4] = 0;
    scene_cmd.path_y[4] = 14;

    if (elmc_scene_writer_push_cmd(writer, &scene_cmd) != 0) {
      Rc = RC_ERR_SCENE_BUFFER_OVERFLOW;
      break;
    }

    elmc_draw_cmd_init(&scene_cmd, ELMC_RENDER_OP_PATH_OUTLINE_OPEN);
    scene_cmd.path_point_count = 4;
    scene_cmd.path_offset_x = 10;
    scene_cmd.path_offset_y = 78;
    scene_cmd.path_rotation = 0;
    scene_cmd.path_x[0] = 0;
    scene_cmd.path_y[0] = 0;

    scene_cmd.path_x[1] = 8;
    scene_cmd.path_y[1] = 4;

    scene_cmd.path_x[2] = 16;
    scene_cmd.path_y[2] = 2;

    scene_cmd.path_x[3] = 24;
    scene_cmd.path_y[3] = 6;

    if (elmc_scene_writer_push_cmd(writer, &scene_cmd) != 0) {
      Rc = RC_ERR_SCENE_BUFFER_OVERFLOW;
      break;
    }

    elmc_draw_cmd_init(&scene_cmd, ELMC_RENDER_OP_POP_CONTEXT);

    if (elmc_scene_writer_push_cmd(writer, &scene_cmd) != 0) {
      Rc = RC_ERR_SCENE_BUFFER_OVERFLOW;
      break;
    }

    elmc_draw_cmd_init(&scene_cmd, ELMC_RENDER_OP_LINE);
    scene_cmd.p0 = 0;
    scene_cmd.p1 = 84;
    scene_cmd.p2 = 143;
    scene_cmd.p3 = 84;
    scene_cmd.p4 = ELMC_COLOR_BLACK;
    if (elmc_scene_writer_push_cmd(writer, &scene_cmd) != 0) {
      Rc = RC_ERR_SCENE_BUFFER_OVERFLOW;
      break;
    }

    elmc_draw_cmd_init(&scene_cmd, ELMC_RENDER_OP_PIXEL);
    scene_cmd.p0 = 72;
    scene_cmd.p1 = 84;
    scene_cmd.p2 = ELMC_COLOR_BLACK;
    if (elmc_scene_writer_push_cmd(writer, &scene_cmd) != 0) {
      Rc = RC_ERR_SCENE_BUFFER_OVERFLOW;
      break;
    }

    owned[0] = model ? elmc_retain(model) : elmc_int_zero();

    ElmcValue *call_args_13[1] = { owned[0] };
    Rc = elmc_fn_Main_temperatureOf(&owned[1], call_args_13, 1);
    CHECK_RC(Rc);

    if (elmc_maybe_is_just(owned[1])) {

      ElmcValue *call_args_15[1] = { elmc_maybe_or_tuple_just_payload_borrow(owned[1]) };
      Rc = elmc_fn_Main_temperatureValue(&owned[2], call_args_15, 1);
      CHECK_RC(Rc);

      const elmc_int_t native_i_17 = elmc_as_int(owned[2]);
      ELMC_RELEASE(owned[2]);
      owned[2] = NULL;;

      elmc_draw_cmd_init(&scene_cmd, ELMC_RENDER_OP_TEXT_INT_WITH_FONT);
      scene_cmd.p0 = 1;
      scene_cmd.p1 = 0;
      scene_cmd.p2 = 28;
      scene_cmd.p3 = native_i_17;
      if (elmc_scene_writer_push_cmd(writer, &scene_cmd) != 0) {
        Rc = RC_ERR_SCENE_BUFFER_OVERFLOW;
        break;
      }

    }
    else if (elmc_maybe_is_nothing(owned[1])) {

      Rc = elmc_new_int(&owned[3], ELMC_UNION_PEBBLE_UI_WAITINGFORCOMPANION);
      CHECK_RC(Rc);
      elmc_draw_cmd_init(&scene_cmd, ELMC_RENDER_OP_TEXT_LABEL_WITH_FONT);
      scene_cmd.p0 = 1;
      scene_cmd.p1 = 0;
      scene_cmd.p2 = 28;
      scene_cmd.p3 = 0;
      scene_cmd.p4 = 0;
      if (owned[3] && owned[3]->tag == ELMC_TAG_STRING && owned[3]->payload) {
        const char *direct_text = (const char *)owned[3]->payload;
        int direct_text_i = 0;
        while (direct_text[direct_text_i] && direct_text_i < 63) {
          scene_cmd.text[direct_text_i] = direct_text[direct_text_i];
          direct_text_i++;
        }
        scene_cmd.text[direct_text_i] = '\0';

      }

      if (elmc_scene_writer_push_cmd(writer, &scene_cmd) != 0) {
        Rc = RC_ERR_SCENE_BUFFER_OVERFLOW;
        break;
      }
      ELMC_RELEASE(owned[3]);
      owned[3] = NULL;

    }

    ELMC_RELEASE(owned[1]);
    owned[1] = NULL;

    ELMC_RELEASE(owned[0]);
    owned[0] = NULL;

    owned[4] = model ? elmc_retain(model) : elmc_int_zero();

    const elmc_int_t native_call_19 = elmc_fn_Main_counterOf_native(owned[4]);

    ElmcValue *tmp_20 = NULL;
    Rc = elmc_new_int(&tmp_20, native_call_19);
    CHECK_RC(Rc);

    elmc_draw_cmd_init(&scene_cmd, ELMC_RENDER_OP_TEXT_INT_WITH_FONT);
    scene_cmd.p0 = 1;
    scene_cmd.p1 = 0;
    scene_cmd.p2 = 56;
    scene_cmd.p3 = elmc_as_int(tmp_20);
    if (elmc_scene_writer_push_cmd(writer, &scene_cmd) != 0) {
      Rc = RC_ERR_SCENE_BUFFER_OVERFLOW;
      break;
    }

    elmc_release(tmp_20);

    ELMC_RELEASE(owned[4]);
    owned[4] = NULL;

  CATCH_END;
  if (Rc != RC_SUCCESS) {
    elmc_release_array_lifo(owned, DIM(owned));
  }

  return Rc;

}

RC elmc_fn_Main_view_scene_append(ElmcValue ** const args, const int argc, ElmcSceneWriter * const writer) {
  return elmc_fn_Main_view_commands_append(args, argc, writer);
}
