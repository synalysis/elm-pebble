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

static elmc_int_t elmc_fn_Main_helper_native(const elmc_int_t value);
static elmc_int_t elmc_fn_Main_advanced_native(ElmcValue * const n);

static ElmcValue *elmc_fn_Main_helper(ElmcValue ** const args, const int argc);
static ElmcValue *elmc_fn_Main_advanced(ElmcValue ** const args, const int argc);
static RC elmc_fn_Main_counterOf(ElmcValue **out, ElmcValue ** const args, const int argc);
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

  return elmc_new_int_take(elmc_fn_Main_helper_native(value));
}

static elmc_int_t elmc_fn_Main_helper_native(const elmc_int_t value) {

  return (value + 2);
}

static ElmcValue *elmc_fn_Main_advanced(ElmcValue ** const args, const int argc) {
  /* Ownership policy: borrow_arg, borrow_result */

  ElmcValue *n = (argc > 0) ? args[0] : NULL;

  return elmc_new_int_take(elmc_fn_Main_advanced_native(n));
}

static elmc_int_t elmc_fn_Main_advanced_native(ElmcValue * const n) {

  // inlined Main.helper

  const elmc_int_t native_let_base_1 = (elmc_as_int(n) + 2);

  elmc_int_t native_if_1;
  if ((native_let_base_1 > 10)) {

    native_if_1 = native_let_base_1;
  } else {

    native_if_1 = (native_let_base_1 + 1);
  }

  return native_if_1;
}

static RC elmc_fn_Main_counterOf(ElmcValue **out, ElmcValue ** const args, const int argc) {
  /* Ownership policy: borrow_arg, borrow_result */
  RC Rc = RC_SUCCESS;

  ElmcValue *model = (argc > 0) ? args[0] : NULL;

  ElmcValue *tmp_1 = elmc_record_get_index(model, ELMC_FIELD_MAIN_MODEL_VALUE);

  *out = tmp_1;

  return Rc;
}

static RC elmc_fn_Main_temperatureOf(ElmcValue **out, ElmcValue ** const args, const int argc) {
  /* Ownership policy: borrow_arg, borrow_result */
  RC Rc = RC_SUCCESS;

  ElmcValue *model = (argc > 0) ? args[0] : NULL;

  ElmcValue *tmp_1 = elmc_record_get_index(model, ELMC_FIELD_MAIN_MODEL_TEMPERATURE);

  *out = tmp_1;

  return Rc;
}

static RC elmc_fn_Main_requestWeather(ElmcValue **out, ElmcValue ** const args, const int argc) {
  /* Ownership policy: borrow_arg, borrow_result */
  RC Rc = RC_SUCCESS;
  ElmcValue *owned[2] = {0};

  ElmcValue *location = (argc > 0) ? args[0] : NULL;

  CATCH_BEGIN

    ElmcValue *tmp_1 = NULL;
    Rc = elmc_new_int(&tmp_1, ELMC_UNION_COMPANION_TYPES_REQUESTWEATHER);
    CHECK_RC(Rc);
    ElmcValue *tmp_2 = elmc_retain(location);
    Rc = elmc_tuple2_take(&owned[0], tmp_1, tmp_2);
    CHECK_RC(Rc);

    ElmcValue *call_args_3[1] = { owned[0] };
    Rc = elmc_fn_Companion_Watch_sendWatchToPhone(&owned[1], call_args_3, 1);
    CHECK_RC(Rc);

    elmc_release(owned[0]);

    *out = owned[1];
  CATCH_END;

  if (Rc != RC_SUCCESS) {
    elmc_release_array_lifo(owned, DIM(owned));
  }
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
    elmc_release(owned[0]);

    *out = owned[1];
  CATCH_END;

  if (Rc != RC_SUCCESS) {
    elmc_release_array_lifo(owned, DIM(owned));
  }
  return Rc;
}

RC elmc_fn_Main_init(ElmcValue **out, ElmcValue ** const args, const int argc) {
  /* Ownership policy: borrow_arg, borrow_result */
  RC Rc = RC_SUCCESS;
  ElmcValue *owned[6] = {0};

  ElmcValue *launchContext = (argc > 0) ? args[0] : NULL;

  CATCH_BEGIN

    ElmcValue *call_args_1[1] = { ELMC_RECORD_GET_INDEX(launchContext, ELMC_FIELD_PEBBLE_PLATFORM_LAUNCHCONTEXT_REASON) };
    Rc = elmc_fn_Pebble_Platform_launchReasonToInt(&owned[0], call_args_1, 1);
    CHECK_RC(Rc);

    const elmc_int_t native_i_3 = elmc_as_int(owned[0]);
    elmc_release(owned[0]);

    const elmc_int_t native_let_initial_4 = native_i_3;

    ElmcValue *tmp_4_boxed_int = elmc_new_int_take(native_let_initial_4);

    ElmcValue *tmp_5 = elmc_maybe_nothing();

    ElmcValue *rec_values_5[2] = { tmp_4_boxed_int, tmp_5 };
    Rc = elmc_record_new_values_take(&owned[1], 2, rec_values_5);
    CHECK_RC(Rc);

    ElmcValue *tmp_6 = NULL;
    Rc = elmc_new_int(&tmp_6, ELMC_UNION_COMPANION_TYPES_BERLIN);
    CHECK_RC(Rc);

    ElmcValue *call_args_7[1] = { tmp_6 };
    Rc = elmc_fn_Main_requestWeather(&owned[2], call_args_7, 1);
    CHECK_RC(Rc);

    elmc_release(tmp_6);

    ElmcValue *tmp_9 = ({ ElmcValue *__z = NULL; RC __call_rc = elmc_fn_Main_requestSystemInfo(&__z, NULL, 0); if (__call_rc != RC_SUCCESS) __z = NULL; __z; })
    ;
    ElmcValue *list_items_10[2] = { owned[2], tmp_9 };
    Rc = elmc_list_from_values_take(&owned[3], list_items_10, 2);
    CHECK_RC(Rc);
    owned[2] = NULL;

    owned[4] = elmc_cmd_batch(owned[3]);
    elmc_release(owned[3]);

    Rc = elmc_tuple2_take(&owned[5], owned[1], owned[4]);
    CHECK_RC(Rc);
    owned[1] = NULL;
    owned[4] = NULL;

    *out = owned[5];
  CATCH_END;

  if (Rc != RC_SUCCESS) {
    elmc_release_array_lifo(owned, DIM(owned));
  }
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
    ElmcValue *tmp_1 = NULL;
    switch (case_msg_tag_1) {
      case ELMC_PEBBLE_MSG_TICK: {

        ElmcValue *call_args_2[2] = { msg, model };
        Rc = elmc_fn_Main_handlePlatformMsg(&tmp_1, call_args_2, 2);
        CHECK_RC(Rc);

        break;
      }
      case ELMC_PEBBLE_MSG_UPPRESSED: {

        ElmcValue *call_args_4[2] = { msg, model };
        Rc = elmc_fn_Main_handlePlatformMsg(&tmp_1, call_args_4, 2);
        CHECK_RC(Rc);

        break;
      }
      case ELMC_PEBBLE_MSG_SELECTPRESSED: {

        ElmcValue *call_args_6[2] = { msg, model };
        Rc = elmc_fn_Main_handlePlatformMsg(&tmp_1, call_args_6, 2);
        CHECK_RC(Rc);

        break;
      }
      case ELMC_PEBBLE_MSG_DOWNPRESSED: {

        ElmcValue *call_args_8[2] = { msg, model };
        Rc = elmc_fn_Main_handlePlatformMsg(&tmp_1, call_args_8, 2);
        CHECK_RC(Rc);

        break;
      }
      case ELMC_PEBBLE_MSG_ACCELTAP: {

        ElmcValue *call_args_10[2] = { msg, model };
        Rc = elmc_fn_Main_handlePlatformMsg(&tmp_1, call_args_10, 2);
        CHECK_RC(Rc);

        break;
      }
      default: {

        ElmcValue *call_args_12[2] = { msg, model };
        Rc = elmc_fn_Main_handleAppMsg(&tmp_1, call_args_12, 2);
        CHECK_RC(Rc);

        break;
      }

    }

    *out = tmp_1;
  CATCH_END;

  if (Rc != RC_SUCCESS) {
    elmc_release_array_lifo(owned, DIM(owned));
  }
  return Rc;
}

static RC elmc_fn_Main_handleAppMsg(ElmcValue **out, ElmcValue ** const args, const int argc) {
  /* Ownership policy: borrow_arg, borrow_result */
  RC Rc = RC_SUCCESS;
  ElmcValue *owned[5] = {0};

  ElmcValue *msg = (argc > 0) ? args[0] : NULL;
  ElmcValue *model = (argc > 1) ? args[1] : NULL;

  CATCH_BEGIN

    const int case_msg_tag_1 = (msg && (msg)->tag == ELMC_TAG_INT ? elmc_as_int(msg) : (msg && (msg)->tag == ELMC_TAG_TUPLE2 && (msg)->payload != NULL ? elmc_as_int(((ElmcTuple2 *)(msg)->payload)->first) : -1));
    ElmcValue *tmp_1 = NULL;
    switch (case_msg_tag_1) {
      case ELMC_PEBBLE_MSG_INCREMENT: {

        // inlined Main.counterOf

        const elmc_int_t native_let_counter_2 = ELMC_RECORD_GET_INDEX_INT(model, ELMC_FIELD_MAIN_MODEL_VALUE);

        ElmcValue *tmp_2_boxed_int = elmc_new_int_take((native_let_counter_2 + 1));

        ElmcValue *call_args_3[1] = { model };
        Rc = elmc_fn_Main_temperatureOf(&owned[0], call_args_3, 1);
        CHECK_RC(Rc);

        ElmcValue *rec_values_4[2] = { tmp_2_boxed_int, owned[0] };
        Rc = elmc_record_new_values_take(&owned[1], 2, rec_values_4);
        CHECK_RC(Rc);
        owned[0] = NULL;

        ElmcValue *tmp_5 = elmc_int_zero();
        Rc = elmc_tuple2_take(&tmp_1, owned[1], tmp_5);
        CHECK_RC(Rc);
        owned[1] = NULL;

        break;
      }
      case ELMC_PEBBLE_MSG_DECREMENT: {

        // inlined Main.counterOf

        const elmc_int_t native_let_counter_6 = ELMC_RECORD_GET_INDEX_INT(model, ELMC_FIELD_MAIN_MODEL_VALUE);

        ElmcValue *tmp_6_boxed_int = elmc_new_int_take((native_let_counter_6 - 1));

        ElmcValue *call_args_7[1] = { model };
        Rc = elmc_fn_Main_temperatureOf(&owned[2], call_args_7, 1);
        CHECK_RC(Rc);

        ElmcValue *rec_values_8[2] = { tmp_6_boxed_int, owned[2] };
        Rc = elmc_record_new_values_take(&owned[3], 2, rec_values_8);
        CHECK_RC(Rc);
        owned[2] = NULL;

        ElmcValue *tmp_9 = elmc_int_zero();
        Rc = elmc_tuple2_take(&tmp_1, owned[3], tmp_9);
        CHECK_RC(Rc);
        owned[3] = NULL;

        break;
      }
      case ELMC_PEBBLE_MSG_PROVIDETEMPERATURE: {

        // inlined Main.counterOf
        ElmcValue *tmp_10_boxed_int = elmc_new_int_take(ELMC_RECORD_GET_INDEX_INT(model, ELMC_FIELD_MAIN_MODEL_VALUE));

        ElmcValue *tmp_11 = ((ElmcTuple2 *)msg->payload)->second ? elmc_retain(((ElmcTuple2 *)msg->payload)->second) : elmc_int_zero();
        ElmcValue *tmp_12 = NULL;
        Rc = elmc_maybe_just(&tmp_12, tmp_11);
        CHECK_RC(Rc);
        elmc_release(tmp_11);

        ElmcValue *rec_values_12[2] = { tmp_10_boxed_int, tmp_12 };
        Rc = elmc_record_new_values_take(&owned[4], 2, rec_values_12);
        CHECK_RC(Rc);

        ElmcValue *tmp_13 = elmc_int_zero();
        Rc = elmc_tuple2_take(&tmp_1, owned[4], tmp_13);
        CHECK_RC(Rc);
        owned[4] = NULL;

        break;
      }
      case ELMC_PEBBLE_MSG_CURRENTTIMESTRING: {
        ElmcValue *tmp_14 = model ? elmc_retain(model) : elmc_int_zero();
        ElmcValue *tmp_15 = elmc_int_zero();
        Rc = elmc_tuple2_take(&tmp_1, tmp_14, tmp_15);
        CHECK_RC(Rc);

        break;
      }
      case ELMC_PEBBLE_MSG_CLOCKSTYLE24H: {
        ElmcValue *tmp_16 = model ? elmc_retain(model) : elmc_int_zero();
        ElmcValue *tmp_17 = elmc_int_zero();
        Rc = elmc_tuple2_take(&tmp_1, tmp_16, tmp_17);
        CHECK_RC(Rc);

        break;
      }
      case ELMC_PEBBLE_MSG_TIMEZONEISSET: {
        ElmcValue *tmp_18 = model ? elmc_retain(model) : elmc_int_zero();
        ElmcValue *tmp_19 = elmc_int_zero();
        Rc = elmc_tuple2_take(&tmp_1, tmp_18, tmp_19);
        CHECK_RC(Rc);

        break;
      }
      case ELMC_PEBBLE_MSG_TIMEZONENAME: {
        ElmcValue *tmp_20 = model ? elmc_retain(model) : elmc_int_zero();
        ElmcValue *tmp_21 = elmc_int_zero();
        Rc = elmc_tuple2_take(&tmp_1, tmp_20, tmp_21);
        CHECK_RC(Rc);

        break;
      }
      case ELMC_PEBBLE_MSG_WATCHMODELNAME: {
        ElmcValue *tmp_22 = model ? elmc_retain(model) : elmc_int_zero();
        ElmcValue *tmp_23 = elmc_int_zero();
        Rc = elmc_tuple2_take(&tmp_1, tmp_22, tmp_23);
        CHECK_RC(Rc);

        break;
      }
      case ELMC_PEBBLE_MSG_WATCHCOLORNAME: {
        ElmcValue *tmp_24 = model ? elmc_retain(model) : elmc_int_zero();
        ElmcValue *tmp_25 = elmc_int_zero();
        Rc = elmc_tuple2_take(&tmp_1, tmp_24, tmp_25);
        CHECK_RC(Rc);

        break;
      }
      case ELMC_PEBBLE_MSG_FIRMWAREVERSIONSTRING: {
        ElmcValue *tmp_26 = model ? elmc_retain(model) : elmc_int_zero();
        ElmcValue *tmp_27 = elmc_int_zero();
        Rc = elmc_tuple2_take(&tmp_1, tmp_26, tmp_27);
        CHECK_RC(Rc);

        break;
      }
      default: {
        ElmcValue *tmp_28 = model ? elmc_retain(model) : elmc_int_zero();
        ElmcValue *tmp_29 = elmc_int_zero();
        Rc = elmc_tuple2_take(&tmp_1, tmp_28, tmp_29);
        CHECK_RC(Rc);

        break;
      }

    }

    *out = tmp_1;
  CATCH_END;

  if (Rc != RC_SUCCESS) {
    elmc_release_array_lifo(owned, DIM(owned));
  }
  return Rc;
}

static RC elmc_fn_Main_handlePlatformMsg(ElmcValue **out, ElmcValue ** const args, const int argc) {
  /* Ownership policy: borrow_arg, borrow_result */
  RC Rc = RC_SUCCESS;
  ElmcValue *owned[11] = {0};

  ElmcValue *msg = (argc > 0) ? args[0] : NULL;
  ElmcValue *model = (argc > 1) ? args[1] : NULL;

  CATCH_BEGIN

    const int case_msg_tag_1 = (msg && (msg)->tag == ELMC_TAG_INT ? elmc_as_int(msg) : (msg && (msg)->tag == ELMC_TAG_TUPLE2 && (msg)->payload != NULL ? elmc_as_int(((ElmcTuple2 *)(msg)->payload)->first) : -1));
    ElmcValue *tmp_1 = NULL;
    switch (case_msg_tag_1) {
      case ELMC_PEBBLE_MSG_TICK: {

        // inlined Main.counterOf
        ElmcValue *tmp_2 = NULL;
        Rc = elmc_new_int(&tmp_2, ELMC_RECORD_GET_INDEX_INT(model, ELMC_FIELD_MAIN_MODEL_VALUE));
        CHECK_RC(Rc);

        // inlined Main.helper

        const elmc_int_t native_let_base_3 = (elmc_as_int(tmp_2) + 2);

        elmc_int_t native_if_3;
        if ((native_let_base_3 > 10)) {

        native_if_3 = native_let_base_3;
        } else {

        native_if_3 = (native_let_base_3 + 1);
        }

        // inlined Main.advanced

        const elmc_int_t native_let_next_4 = native_if_3;

        ElmcValue *tmp_4_boxed_int = elmc_new_int_take(native_let_next_4);

        ElmcValue *call_args_5[1] = { model };
        Rc = elmc_fn_Main_temperatureOf(&owned[0], call_args_5, 1);
        CHECK_RC(Rc);

        ElmcValue *rec_values_6[2] = { tmp_4_boxed_int, owned[0] };
        Rc = elmc_record_new_values_take(&owned[1], 2, rec_values_6);
        CHECK_RC(Rc);
        owned[0] = NULL;

        ElmcValue *tmp_7 = elmc_cmd1(ELMC_PEBBLE_CMD_TIMER_AFTER_MS, 1000);

        Rc = elmc_tuple2_take(&tmp_1, owned[1], tmp_7);
        CHECK_RC(Rc);
        owned[1] = NULL;

        elmc_release(tmp_2);

        break;
      }
      case ELMC_PEBBLE_MSG_UPPRESSED: {

        // inlined Main.counterOf

        const elmc_int_t native_let_counter_8 = ELMC_RECORD_GET_INDEX_INT(model, ELMC_FIELD_MAIN_MODEL_VALUE);

        ElmcValue *tmp_8 = NULL;
        Rc = elmc_new_int(&tmp_8, (native_let_counter_8 + 1));
        CHECK_RC(Rc);

        ElmcValue *tmp_9_boxed_int = elmc_new_int_take(elmc_as_int(tmp_8));

        ElmcValue *call_args_10[1] = { model };
        Rc = elmc_fn_Main_temperatureOf(&owned[2], call_args_10, 1);
        CHECK_RC(Rc);

        ElmcValue *rec_values_11[2] = { tmp_9_boxed_int, owned[2] };
        Rc = elmc_record_new_values_take(&owned[3], 2, rec_values_11);
        CHECK_RC(Rc);
        owned[2] = NULL;

        ElmcValue *tmp_12 = elmc_cmd2(ELMC_PEBBLE_CMD_STORAGE_WRITE_INT, 1, elmc_as_int(tmp_8));

        Rc = elmc_tuple2_take(&tmp_1, owned[3], tmp_12);
        CHECK_RC(Rc);
        owned[3] = NULL;

        elmc_release(tmp_8);

        break;
      }
      case ELMC_PEBBLE_MSG_SELECTPRESSED: {
        ElmcValue *tmp_13 = model ? elmc_retain(model) : elmc_int_zero();

        ElmcValue *tmp_14 = NULL;
        Rc = elmc_new_int(&tmp_14, ELMC_UNION_COMPANION_TYPES_BERLIN);
        CHECK_RC(Rc);

        ElmcValue *call_args_15[1] = { tmp_14 };
        Rc = elmc_fn_Main_requestWeather(&owned[4], call_args_15, 1);
        CHECK_RC(Rc);

        elmc_release(tmp_14);

        ElmcValue *tmp_17 = ({ ElmcValue *__z = NULL; RC __call_rc = elmc_fn_Main_requestSystemInfo(&__z, NULL, 0); if (__call_rc != RC_SUCCESS) __z = NULL; __z; })
        ;
        ElmcValue *list_items_18[2] = { owned[4], tmp_17 };
        Rc = elmc_list_from_values_take(&owned[5], list_items_18, 2);
        CHECK_RC(Rc);
        owned[4] = NULL;

        owned[6] = elmc_cmd_batch(owned[5]);
        elmc_release(owned[5]);

        Rc = elmc_tuple2_take(&tmp_1, tmp_13, owned[6]);
        CHECK_RC(Rc);
        owned[6] = NULL;

        break;
      }
      case ELMC_PEBBLE_MSG_DOWNPRESSED: {

        // inlined Main.counterOf

        const elmc_int_t native_let_counter_20 = ELMC_RECORD_GET_INDEX_INT(model, ELMC_FIELD_MAIN_MODEL_VALUE);

        ElmcValue *tmp_20_boxed_int = elmc_new_int_take((native_let_counter_20 - 1));

        ElmcValue *call_args_21[1] = { model };
        Rc = elmc_fn_Main_temperatureOf(&owned[7], call_args_21, 1);
        CHECK_RC(Rc);

        ElmcValue *rec_values_22[2] = { tmp_20_boxed_int, owned[7] };
        Rc = elmc_record_new_values_take(&owned[8], 2, rec_values_22);
        CHECK_RC(Rc);
        owned[7] = NULL;

        ElmcValue *tmp_23 = elmc_cmd1(ELMC_PEBBLE_CMD_STORAGE_DELETE, 1);

        Rc = elmc_tuple2_take(&tmp_1, owned[8], tmp_23);
        CHECK_RC(Rc);
        owned[8] = NULL;

        break;
      }
      case ELMC_PEBBLE_MSG_ACCELTAP: {

        // inlined Main.counterOf

        const elmc_int_t native_let_counter_24 = ELMC_RECORD_GET_INDEX_INT(model, ELMC_FIELD_MAIN_MODEL_VALUE);

        ElmcValue *tmp_24_boxed_int = elmc_new_int_take((native_let_counter_24 + 1));

        ElmcValue *call_args_25[1] = { model };
        Rc = elmc_fn_Main_temperatureOf(&owned[9], call_args_25, 1);
        CHECK_RC(Rc);

        ElmcValue *rec_values_26[2] = { tmp_24_boxed_int, owned[9] };
        Rc = elmc_record_new_values_take(&owned[10], 2, rec_values_26);
        CHECK_RC(Rc);
        owned[9] = NULL;

        ElmcValue *tmp_27 = elmc_int_zero();
        Rc = elmc_tuple2_take(&tmp_1, owned[10], tmp_27);
        CHECK_RC(Rc);
        owned[10] = NULL;

        break;
      }
      default: {
        ElmcValue *tmp_28 = model ? elmc_retain(model) : elmc_int_zero();
        ElmcValue *tmp_29 = elmc_int_zero();
        Rc = elmc_tuple2_take(&tmp_1, tmp_28, tmp_29);
        CHECK_RC(Rc);

        break;
      }

    }

    *out = tmp_1;
  CATCH_END;

  if (Rc != RC_SUCCESS) {
    elmc_release_array_lifo(owned, DIM(owned));
  }
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
  CATCH_END;

  if (Rc != RC_SUCCESS) {
    elmc_release_array_lifo(owned, DIM(owned));
  }
  return Rc;
}

static RC elmc_fn_Main_statusDraw(ElmcValue **out, ElmcValue ** const args, const int argc) {
  /* Ownership policy: borrow_arg, borrow_result */
  RC Rc = RC_SUCCESS;
  ElmcValue *owned[13] = {0};

  ElmcValue *model = (argc > 0) ? args[0] : NULL;

  CATCH_BEGIN

    ElmcValue *call_args_1[1] = { model };
    Rc = elmc_fn_Main_temperatureOf(&owned[0], call_args_1, 1);
    CHECK_RC(Rc);

    if (((owned[0] && owned[0]->tag == ELMC_TAG_MAYBE && ((ElmcMaybe *)owned[0]->payload)->is_just == 1) || (owned[0] && owned[0]->tag == ELMC_TAG_TUPLE2 && owned[0]->payload != NULL && elmc_as_int(((ElmcTuple2 *)owned[0]->payload)->first) == 1))) {
      ElmcValue *tmp_3 = NULL;
      Rc = elmc_new_int(&tmp_3, ELMC_RENDER_OP_TEXT_INT_WITH_FONT);
      CHECK_RC(Rc);

      ElmcValue *tmp_4 = NULL;
      Rc = elmc_new_int(&tmp_4, ELMC_RESOURCE_SLOT_DEFAULTFONT);
      CHECK_RC(Rc);
      ElmcValue *tmp_5 = elmc_int_zero();
      ElmcValue *tmp_6 = NULL;
      Rc = elmc_new_int(&tmp_6, 28);
      CHECK_RC(Rc);

      ElmcValue *call_args_7[1] = { elmc_maybe_or_tuple_just_payload_borrow(owned[0]) };
      Rc = elmc_fn_Main_temperatureValue(&owned[2], call_args_7, 1);
      CHECK_RC(Rc);

      Rc = elmc_tuple2_ints(&owned[3], 0, 0);
      CHECK_RC(Rc);

      Rc = elmc_tuple2_take(&owned[4], owned[2], owned[3]);
      CHECK_RC(Rc);
      owned[2] = NULL;
      owned[3] = NULL;

      Rc = elmc_tuple2_take(&owned[5], tmp_6, owned[4]);
      CHECK_RC(Rc);
      owned[4] = NULL;

      Rc = elmc_tuple2_take(&owned[6], tmp_5, owned[5]);
      CHECK_RC(Rc);
      owned[5] = NULL;

      Rc = elmc_tuple2_take(&owned[7], tmp_4, owned[6]);
      CHECK_RC(Rc);
      owned[6] = NULL;

      Rc = elmc_tuple2_take(&owned[1], tmp_3, owned[7]);
      CHECK_RC(Rc);
      owned[7] = NULL;

    } else {
      ElmcValue *tmp_9 = NULL;
      Rc = elmc_new_int(&tmp_9, ELMC_RENDER_OP_TEXT_LABEL_WITH_FONT);
      CHECK_RC(Rc);

      ElmcValue *tmp_10 = NULL;
      Rc = elmc_new_int(&tmp_10, ELMC_RESOURCE_SLOT_DEFAULTFONT);
      CHECK_RC(Rc);
      ElmcValue *tmp_11 = elmc_int_zero();
      ElmcValue *tmp_12 = NULL;
      Rc = elmc_new_int(&tmp_12, 28);
      CHECK_RC(Rc);
      ElmcValue *tmp_13 = elmc_int_zero();
      ElmcValue *tmp_14 = elmc_int_zero();
      ElmcValue *tmp_15 = NULL;
      Rc = elmc_new_int(&tmp_15, ELMC_UNION_PEBBLE_UI_WAITINGFORCOMPANION);
      CHECK_RC(Rc);
      Rc = elmc_tuple2_take(&owned[8], tmp_14, tmp_15);
      CHECK_RC(Rc);

      Rc = elmc_tuple2_take(&owned[9], tmp_13, owned[8]);
      CHECK_RC(Rc);
      owned[8] = NULL;

      Rc = elmc_tuple2_take(&owned[10], tmp_12, owned[9]);
      CHECK_RC(Rc);
      owned[9] = NULL;

      Rc = elmc_tuple2_take(&owned[11], tmp_11, owned[10]);
      CHECK_RC(Rc);
      owned[10] = NULL;

      Rc = elmc_tuple2_take(&owned[12], tmp_10, owned[11]);
      CHECK_RC(Rc);
      owned[11] = NULL;

      Rc = elmc_tuple2_take(&owned[1], tmp_9, owned[12]);
      CHECK_RC(Rc);
      owned[12] = NULL;
    }

    elmc_release(owned[0]);

    *out = owned[1];
  CATCH_END;

  if (Rc != RC_SUCCESS) {
    elmc_release_array_lifo(owned, DIM(owned));
  }
  return Rc;
}

static RC elmc_fn_Main_counterDraw(ElmcValue **out, ElmcValue ** const args, const int argc) {
  /* Ownership policy: borrow_arg, borrow_result */
  RC Rc = RC_SUCCESS;
  ElmcValue *owned[6] = {0};

  ElmcValue *model = (argc > 0) ? args[0] : NULL;

  CATCH_BEGIN

    // inlined Main.counterOf

    const elmc_int_t native_let_counter_1 = ELMC_RECORD_GET_INDEX_INT(model, ELMC_FIELD_MAIN_MODEL_VALUE);

    ElmcValue *tmp_1 = NULL;
    Rc = elmc_new_int(&tmp_1, ELMC_RENDER_OP_TEXT_INT_WITH_FONT);
    CHECK_RC(Rc);

    ElmcValue *tmp_2 = NULL;
    Rc = elmc_new_int(&tmp_2, ELMC_RESOURCE_SLOT_DEFAULTFONT);
    CHECK_RC(Rc);
    ElmcValue *tmp_3 = elmc_int_zero();
    ElmcValue *tmp_4 = NULL;
    Rc = elmc_new_int(&tmp_4, 56);
    CHECK_RC(Rc);
    ElmcValue *tmp_5 = NULL;
    Rc = elmc_new_int(&tmp_5, native_let_counter_1);
    CHECK_RC(Rc);

    Rc = elmc_tuple2_ints(&owned[0], 0, 0);
    CHECK_RC(Rc);

    Rc = elmc_tuple2_take(&owned[1], tmp_5, owned[0]);
    CHECK_RC(Rc);
    owned[0] = NULL;

    Rc = elmc_tuple2_take(&owned[2], tmp_4, owned[1]);
    CHECK_RC(Rc);
    owned[1] = NULL;

    Rc = elmc_tuple2_take(&owned[3], tmp_3, owned[2]);
    CHECK_RC(Rc);
    owned[2] = NULL;

    Rc = elmc_tuple2_take(&owned[4], tmp_2, owned[3]);
    CHECK_RC(Rc);
    owned[3] = NULL;

    Rc = elmc_tuple2_take(&owned[5], tmp_1, owned[4]);
    CHECK_RC(Rc);
    owned[4] = NULL;

    *out = owned[5];
  CATCH_END;

  if (Rc != RC_SUCCESS) {
    elmc_release_array_lifo(owned, DIM(owned));
  }
  return Rc;
}

static RC elmc_fn_Main_temperatureValue(ElmcValue **out, ElmcValue ** const args, const int argc) {
  /* Ownership policy: borrow_arg, borrow_result */
  RC Rc = RC_SUCCESS;
  ElmcValue *owned[1] = {0};

  ElmcValue *temperature = (argc > 0) ? args[0] : NULL;

  if ((temperature) && (((temperature)->tag == ELMC_TAG_INT && elmc_as_int(temperature) == 1) || ((temperature)->tag == ELMC_TAG_TUPLE2 && (temperature)->payload != NULL && elmc_as_int(((ElmcTuple2 *)(temperature)->payload)->first) == 1))) {
    owned[0] = ((ElmcTuple2 *)temperature->payload)->second ? elmc_retain(((ElmcTuple2 *)temperature->payload)->second) : elmc_int_zero();

  } else {
    owned[0] = ((ElmcTuple2 *)temperature->payload)->second ? elmc_retain(((ElmcTuple2 *)temperature->payload)->second) : elmc_int_zero();
  }

  *out = owned[0];

  if (Rc != RC_SUCCESS) {
    elmc_release_array_lifo(owned, DIM(owned));
  }
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
    ElmcValue *tmp_2 = NULL;
    elmc_int_t case_int_2;
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
    Rc = elmc_new_int(&tmp_2, case_int_2);
    CHECK_RC(Rc);

    *out = tmp_2;
  CATCH_END;

  return Rc;
}

static RC elmc_fn_Companion_Internal_encodeLocationCode(ElmcValue **out, ElmcValue ** const args, const int argc) {
  /* Ownership policy: borrow_arg, borrow_result */
  RC Rc = RC_SUCCESS;

  ElmcValue *value = (argc > 0) ? args[0] : NULL;

  CATCH_BEGIN

    const int case_msg_tag_1 = (value && (value)->tag == ELMC_TAG_INT ? elmc_as_int(value) : (value && (value)->tag == ELMC_TAG_TUPLE2 && (value)->payload != NULL ? elmc_as_int(((ElmcTuple2 *)(value)->payload)->first) : -1));
    ElmcValue *tmp_2 = NULL;
    elmc_int_t case_int_2;
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
    Rc = elmc_new_int(&tmp_2, case_int_2);
    CHECK_RC(Rc);

    *out = tmp_2;
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
  CATCH_END;

  if (Rc != RC_SUCCESS) {
    elmc_release_array_lifo(owned, DIM(owned));
  }
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
  CATCH_END;

  if (Rc != RC_SUCCESS) {
    elmc_release_array_lifo(owned, DIM(owned));
  }
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
    elmc_release(owned[0]);

    ElmcValue *call_args_4[1] = { message };
    Rc = elmc_fn_Companion_Internal_watchToPhoneValue(&owned[1], call_args_4, 1);
    CHECK_RC(Rc);

    const elmc_int_t native_i_6 = elmc_as_int(owned[1]);
    elmc_release(owned[1]);

    ElmcValue *tmp_7 = elmc_cmd2(ELMC_PEBBLE_CMD_COMPANION_SEND, native_i_3, native_i_6);

    *out = tmp_7;
  CATCH_END;

  if (Rc != RC_SUCCESS) {
    elmc_release_array_lifo(owned, DIM(owned));
  }
  return Rc;
}

static RC elmc_fn_Main_view_commands_append(ElmcValue ** const args, const int argc, ElmcSceneWriter * const writer);

static RC elmc_fn_Main_view_commands_append(ElmcValue ** const args, const int argc, ElmcSceneWriter * const writer) {
  ElmcValue *model = (argc > 0) ? args[0] : NULL;

  if (!writer)
    return RC_ERR_INVALID_ARG;
  RC Rc = RC_SUCCESS;
  ElmcValue *owned[2] = {0};

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

    ElmcValue *tmp_13 = model ? elmc_retain(model) : elmc_int_zero();

    ElmcValue *call_args_14[1] = { tmp_13 };
    Rc = elmc_fn_Main_temperatureOf(&owned[0], call_args_14, 1);
    CHECK_RC(Rc);

    if (((owned[0] && owned[0]->tag == ELMC_TAG_MAYBE && ((ElmcMaybe *)owned[0]->payload)->is_just == 1) || (owned[0] && owned[0]->tag == ELMC_TAG_TUPLE2 && owned[0]->payload != NULL && elmc_as_int(((ElmcTuple2 *)owned[0]->payload)->first) == 1))) {

      ElmcValue *call_args_16[1] = { elmc_maybe_or_tuple_just_payload_borrow(owned[0]) };
      Rc = elmc_fn_Main_temperatureValue(&owned[1], call_args_16, 1);
      CHECK_RC(Rc);

      const elmc_int_t native_i_18 = elmc_as_int(owned[1]);
      elmc_release(owned[1]);

      elmc_draw_cmd_init(&scene_cmd, ELMC_RENDER_OP_TEXT_INT_WITH_FONT);
      scene_cmd.p0 = 1;
      scene_cmd.p1 = 0;
      scene_cmd.p2 = 28;
      scene_cmd.p3 = native_i_18;
      if (elmc_scene_writer_push_cmd(writer, &scene_cmd) != 0) {
        Rc = RC_ERR_SCENE_BUFFER_OVERFLOW;
        break;
      }

    }
    else if (((owned[0] && owned[0]->tag == ELMC_TAG_MAYBE && ((ElmcMaybe *)owned[0]->payload)->is_just == 0) || (owned[0] && owned[0]->tag == ELMC_TAG_INT && elmc_as_int(owned[0]) == 0))) {

      ElmcValue *tmp_20 = NULL;
      Rc = elmc_new_int(&tmp_20, ELMC_UNION_PEBBLE_UI_WAITINGFORCOMPANION);
      CHECK_RC(Rc);
      elmc_draw_cmd_init(&scene_cmd, ELMC_RENDER_OP_TEXT_LABEL_WITH_FONT);
      scene_cmd.p0 = 1;
      scene_cmd.p1 = 0;
      scene_cmd.p2 = 28;
      scene_cmd.p3 = 0;
      scene_cmd.p4 = 0;
      if (tmp_20 && tmp_20->tag == ELMC_TAG_STRING && tmp_20->payload) {
        const char *direct_text = (const char *)tmp_20->payload;
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
      elmc_release(tmp_20);

    }

    elmc_release(owned[0]);

    elmc_release(tmp_13);

    ElmcValue *tmp_21 = model ? elmc_retain(model) : elmc_int_zero();
    // inlined Main.counterOf
    const elmc_int_t direct_hoisted_int_22 = ELMC_RECORD_GET_INDEX_INT(tmp_21, ELMC_FIELD_MAIN_MODEL_VALUE);

    const elmc_int_t direct_native_let_counter_23 = direct_hoisted_int_22;

    elmc_draw_cmd_init(&scene_cmd, ELMC_RENDER_OP_TEXT_INT_WITH_FONT);
    scene_cmd.p0 = 1;
    scene_cmd.p1 = 0;
    scene_cmd.p2 = 56;
    scene_cmd.p3 = direct_native_let_counter_23;
    if (elmc_scene_writer_push_cmd(writer, &scene_cmd) != 0) {
      Rc = RC_ERR_SCENE_BUFFER_OVERFLOW;
      break;
    }

    elmc_release(tmp_21);

  CATCH_END;
  if (Rc != RC_SUCCESS) {
    elmc_release_array_lifo(owned, DIM(owned));
  }

  return Rc;

}

RC elmc_fn_Main_view_scene_append(ElmcValue ** const args, const int argc, ElmcSceneWriter * const writer) {
  return elmc_fn_Main_view_commands_append(args, argc, writer);
}
