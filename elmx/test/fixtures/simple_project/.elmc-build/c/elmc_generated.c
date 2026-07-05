#include "elmc_generated.h"
#include "elmc_pebble.h"
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>

#if defined(__GNUC__)
#pragma GCC diagnostic ignored "-Wunused-function"
#pragma GCC diagnostic ignored "-Wunused-variable"
#endif

#define ELMC_UNION_ACCELTAP 7
#define ELMC_UNION_BERLIN 2
#define ELMC_UNION_CANVASLAYER 1
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
#define ELMC_UNION_PEBBLE_UI_CANVASLAYER 1
#define ELMC_UNION_PEBBLE_UI_RESOURCES_DEFAULTFONT 1
#define ELMC_UNION_PEBBLE_UI_ROTATION 1
#define ELMC_UNION_PEBBLE_UI_WAITINGFORCOMPANION 1
#define ELMC_UNION_PEBBLE_UI_WINDOWNODE 1
#define ELMC_UNION_PEBBLE_UI_WINDOWSTACK 1
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
#define ELMC_UNION_WINDOWNODE 1
#define ELMC_UNION_WINDOWSTACK 1
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
#define ELMC_RENDER_OP_CONTEXT_GROUP 19
#define ELMC_RENDER_OP_PATH_FILLED 20
#define ELMC_RENDER_OP_PATH_OUTLINE 21
#define ELMC_RENDER_OP_PATH_OUTLINE_OPEN 22
#define ELMC_RENDER_OP_TEXT_INT_WITH_FONT 27
#define ELMC_RENDER_OP_TEXT_LABEL_WITH_FONT 28
#define ELMC_CONTEXT_STROKE_WIDTH 1
#define ELMC_CONTEXT_ANTIALIASED 2
#define ELMC_CONTEXT_STROKE_COLOR 3
#define ELMC_CONTEXT_FILL_COLOR 4
#define ELMC_CONTEXT_TEXT_COLOR 5
#define ELMC_UI_NODE_WINDOW_STACK 1000
#define ELMC_UI_NODE_WINDOW 1001
#define ELMC_UI_NODE_CANVAS_LAYER 1002
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

static RC elmc_fn_Main_helper(ElmcValue **out, ElmcValue ** const args, const int argc);
static RC elmc_fn_Main_advanced(ElmcValue **out, ElmcValue ** const args, const int argc);
static RC elmc_fn_Main_counterOf(ElmcValue **out, ElmcValue ** const args, const int argc);
static RC elmc_fn_Main_temperatureOf(ElmcValue **out, ElmcValue ** const args, const int argc);
static RC elmc_fn_Main_requestWeather(ElmcValue **out, ElmcValue ** const args, const int argc);
static RC elmc_fn_Main_requestSystemInfo(ElmcValue **out, ElmcValue ** const args, const int argc);
RC elmc_fn_Main_init(ElmcValue **out, ElmcValue ** const args, const int argc);
RC elmc_fn_Main_update(ElmcValue **out, ElmcValue ** const args, const int argc);
static RC elmc_fn_Main_handleAppMsg(ElmcValue **out, ElmcValue ** const args, const int argc);
static RC elmc_fn_Main_handlePlatformMsg(ElmcValue **out, ElmcValue ** const args, const int argc);
RC elmc_fn_Main_subscriptions(ElmcValue **out, ElmcValue ** const args, const int argc);
RC elmc_fn_Main_view(ElmcValue **out, ElmcValue ** const args, const int argc);
static RC elmc_fn_Main_statusDraw(ElmcValue **out, ElmcValue ** const args, const int argc);
static RC elmc_fn_Main_counterDraw(ElmcValue **out, ElmcValue ** const args, const int argc);
static RC elmc_fn_Main_temperatureValue(ElmcValue **out, ElmcValue ** const args, const int argc);
static RC elmc_fn_Main_main(ElmcValue **out, ElmcValue ** const args, const int argc);
static RC elmc_fn_Pebble_Platform_launchReasonToInt(ElmcValue **out, ElmcValue ** const args, const int argc);
static ElmcValue *elmc_fn_Pebble_Ui_windowStack(ElmcValue ** const args, const int argc);
static ElmcValue *elmc_fn_Pebble_Ui_window(ElmcValue ** const args, const int argc);
static ElmcValue *elmc_fn_Pebble_Ui_canvasLayer(ElmcValue ** const args, const int argc);
static RC elmc_fn_Pebble_Ui_path(ElmcValue **out, ElmcValue ** const args, const int argc);
static RC elmc_fn_Pebble_Ui_rotationToPebbleAngle(ElmcValue **out, ElmcValue ** const args, const int argc);
static RC elmc_fn_Companion_Internal_encodeLocationCode(ElmcValue **out, ElmcValue ** const args, const int argc);
static RC elmc_fn_Companion_Internal_watchToPhoneTag(ElmcValue **out, ElmcValue ** const args, const int argc);
static RC elmc_fn_Companion_Internal_watchToPhoneValue(ElmcValue **out, ElmcValue ** const args, const int argc);
static RC elmc_fn_Companion_Watch_sendWatchToPhone(ElmcValue **out, ElmcValue ** const args, const int argc);

static ElmcValue *elmc_lambda_1(ElmcValue **args, int argc, ElmcValue **captures, int capture_count) {
  (void)captures;
  (void)capture_count;
  ElmcValue *patternArg = (argc > 0) ? args[0] : NULL;
  (void)patternArg;

  ElmcValue *tmp_1 = NULL;

  tmp_1 = ((ElmcTuple2 *)patternArg->payload)->second ? elmc_retain(((ElmcTuple2 *)patternArg->payload)->second) : elmc_int_zero();

  return tmp_1;
}

static RC elmc_fn_Main_helper(ElmcValue **out, ElmcValue ** const args, const int argc) {
  /* Ownership policy: borrow_arg, borrow_result */

  elmc_int_t value = (argc > 0 && args[0]) ? elmc_as_int(args[0]) : 0;

  RC Rc = elmc_new_int(out, elmc_fn_Main_helper_native(value));
  return Rc;

}

static elmc_int_t elmc_fn_Main_helper_native(const elmc_int_t value) {

  return (value + 2);
}

static RC elmc_fn_Main_advanced(ElmcValue **out, ElmcValue ** const args, const int argc) {
  /* Ownership policy: borrow_arg, borrow_result */

  elmc_int_t n = (argc > 0 && args[0]) ? elmc_as_int(args[0]) : 0;

  RC Rc = elmc_new_int(out, elmc_fn_Main_advanced_native(n));
  return Rc;

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

static RC elmc_fn_Main_counterOf(ElmcValue **out, ElmcValue ** const args, const int argc) {
  /* Ownership policy: borrow_arg, borrow_result */

  ElmcValue *model = (argc > 0) ? args[0] : NULL;

  RC Rc = elmc_new_int(out, elmc_fn_Main_counterOf_native(model));
  return Rc;

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
  ElmcValue *owned[3] = {0};

  ElmcValue *location = (argc > 0) ? args[0] : NULL;

  CATCH_BEGIN

    Rc = elmc_new_int(&owned[0], ELMC_UNION_COMPANION_TYPES_REQUESTWEATHER);
    CHECK_RC(Rc);
    owned[1] = elmc_retain(location);
    Rc = elmc_tuple2_take(&owned[2], owned[0], owned[1]);
    CHECK_RC(Rc);
    owned[0] = NULL;
    owned[1] = NULL;

    Rc = elmc_fn_Companion_Watch_sendWatchToPhone(out, (ElmcValue *[]){ owned[2] }, 1);
    CHECK_RC(Rc);

  CATCH_END;

  elmc_release_array_lifo(owned, DIM(owned));
  return Rc;
}

static RC elmc_fn_Main_requestSystemInfo(ElmcValue **out, ElmcValue ** const args, const int argc) {
  /* Ownership policy: borrow_arg, borrow_result */
  RC Rc = RC_SUCCESS;
  ElmcValue *owned[8] = {0};
  (void)args;
  (void)argc;

  CATCH_BEGIN

    Rc = elmc_cmd1(&owned[0], ELMC_PEBBLE_CMD_GET_CURRENT_TIME_STRING, ELMC_PEBBLE_MSG_CURRENTTIMESTRING);
    CHECK_RC(Rc);

    Rc = elmc_cmd1(&owned[1], ELMC_PEBBLE_CMD_GET_CLOCK_STYLE_24H, ELMC_PEBBLE_MSG_CLOCKSTYLE24H);
    CHECK_RC(Rc);

    Rc = elmc_cmd1(&owned[2], ELMC_PEBBLE_CMD_GET_TIMEZONE_IS_SET, ELMC_PEBBLE_MSG_TIMEZONEISSET);
    CHECK_RC(Rc);

    Rc = elmc_cmd1(&owned[3], ELMC_PEBBLE_CMD_GET_TIMEZONE, ELMC_PEBBLE_MSG_TIMEZONENAME);
    CHECK_RC(Rc);

    Rc = elmc_cmd1(&owned[4], ELMC_PEBBLE_CMD_GET_WATCH_MODEL, ELMC_PEBBLE_MSG_WATCHMODELNAME);
    CHECK_RC(Rc);

    Rc = elmc_cmd1(&owned[5], ELMC_PEBBLE_CMD_GET_WATCH_COLOR, ELMC_PEBBLE_MSG_WATCHCOLORNAME);
    CHECK_RC(Rc);

    Rc = elmc_cmd1(&owned[6], ELMC_PEBBLE_CMD_GET_FIRMWARE_VERSION, ELMC_PEBBLE_MSG_FIRMWAREVERSIONSTRING);
    CHECK_RC(Rc);

    ElmcValue *list_items_8[7] = { owned[0], owned[1], owned[2], owned[3], owned[4], owned[5], owned[6] };
    Rc = elmc_list_from_values_take(&owned[7], list_items_8, 7);
    CHECK_RC(Rc);
    owned[0] = NULL;
    owned[1] = NULL;
    owned[2] = NULL;
    owned[3] = NULL;
    owned[4] = NULL;
    owned[5] = NULL;
    owned[6] = NULL;

    *out = elmc_cmd_batch(owned[7]);

  CATCH_END;

  elmc_release_array_lifo(owned, DIM(owned));
  return Rc;
}

RC elmc_fn_Main_init(ElmcValue **out, ElmcValue ** const args, const int argc) {
  /* Ownership policy: borrow_arg, borrow_result */
  RC Rc = RC_SUCCESS;
  ElmcValue *owned[9] = {0};

  ElmcValue *launchContext = (argc > 0) ? args[0] : NULL;

  CATCH_BEGIN

    Rc = elmc_fn_Pebble_Platform_launchReasonToInt(&owned[0], (ElmcValue *[]){ ELMC_RECORD_GET_INDEX(launchContext, ELMC_FIELD_PEBBLE_PLATFORM_LAUNCHCONTEXT_REASON) }, 1);
    CHECK_RC(Rc);

    const elmc_int_t native_i_3 = elmc_as_int(owned[0]);

    const elmc_int_t native_let_initial_4 = native_i_3;

    Rc = elmc_new_int(&owned[1], native_let_initial_4);
    CHECK_RC(Rc);

    Rc = elmc_new_float(&owned[2], (double)(double)0);
    CHECK_RC(Rc);

    ElmcValue *rec_values_1[2] = { owned[1], owned[2] };
    Rc = elmc_record_new_values_take(&owned[3], 2, rec_values_1);
    CHECK_RC(Rc);
    owned[1] = NULL;
    owned[2] = NULL;

    Rc = elmc_new_int(&owned[4], ELMC_UNION_COMPANION_TYPES_BERLIN);
    CHECK_RC(Rc);

    Rc = elmc_fn_Main_requestWeather(&owned[5], (ElmcValue *[]){ owned[4] }, 1);
    CHECK_RC(Rc);

    Rc = elmc_fn_Main_requestSystemInfo(&owned[6], NULL, 0);
    CHECK_RC(Rc);

    ElmcValue *list_items_8[2] = { owned[5], owned[6] };
    Rc = elmc_list_from_values_take(&owned[7], list_items_8, 2);
    CHECK_RC(Rc);
    owned[5] = NULL;
    owned[6] = NULL;

    owned[8] = elmc_cmd_batch(owned[7]);

    Rc = elmc_tuple2_take(out, owned[3], owned[8]);
    CHECK_RC(Rc);
    owned[3] = NULL;
    owned[8] = NULL;

  CATCH_END;

  elmc_release_array_lifo(owned, DIM(owned));
  return Rc;
}

RC elmc_fn_Main_update(ElmcValue **out, ElmcValue ** const args, const int argc) {
  /* Ownership policy: borrow_arg, borrow_result */
  RC Rc = RC_SUCCESS;

  ElmcValue *msg = (argc > 0) ? args[0] : NULL;
  ElmcValue *model = (argc > 1) ? args[1] : NULL;

  CATCH_BEGIN

    const int case_msg_tag_1 = (msg && (msg)->tag == ELMC_TAG_INT ? elmc_as_int(msg) : (msg && (msg)->tag == ELMC_TAG_TUPLE2 && (msg)->payload != NULL ? elmc_as_int(((ElmcTuple2 *)(msg)->payload)->first) : -1));

    switch (case_msg_tag_1) {
      case ELMC_PEBBLE_MSG_TICK: {

        ElmcValue *call_args_2[2] = { msg, model };
        Rc = elmc_fn_Main_handlePlatformMsg(out, call_args_2, 2);
        CHECK_RC(Rc);

        break;
      }
      case ELMC_PEBBLE_MSG_UPPRESSED: {

        ElmcValue *call_args_4[2] = { msg, model };
        Rc = elmc_fn_Main_handlePlatformMsg(out, call_args_4, 2);
        CHECK_RC(Rc);

        break;
      }
      case ELMC_PEBBLE_MSG_SELECTPRESSED: {

        ElmcValue *call_args_6[2] = { msg, model };
        Rc = elmc_fn_Main_handlePlatformMsg(out, call_args_6, 2);
        CHECK_RC(Rc);

        break;
      }
      case ELMC_PEBBLE_MSG_DOWNPRESSED: {

        ElmcValue *call_args_8[2] = { msg, model };
        Rc = elmc_fn_Main_handlePlatformMsg(out, call_args_8, 2);
        CHECK_RC(Rc);

        break;
      }
      case ELMC_PEBBLE_MSG_ACCELTAP: {

        ElmcValue *call_args_10[2] = { msg, model };
        Rc = elmc_fn_Main_handlePlatformMsg(out, call_args_10, 2);
        CHECK_RC(Rc);

        break;
      }
      default: {

        ElmcValue *call_args_12[2] = { msg, model };
        Rc = elmc_fn_Main_handleAppMsg(out, call_args_12, 2);
        CHECK_RC(Rc);

        break;
      }

    }

  CATCH_END;

  return Rc;
}

static RC elmc_fn_Main_handleAppMsg(ElmcValue **out, ElmcValue ** const args, const int argc) {
  /* Ownership policy: borrow_arg, borrow_result */
  RC Rc = RC_SUCCESS;
  ElmcValue *owned[24] = {0};

  ElmcValue *msg = (argc > 0) ? args[0] : NULL;
  ElmcValue *model = (argc > 1) ? args[1] : NULL;

  CATCH_BEGIN

    const int case_msg_tag_1 = (msg && (msg)->tag == ELMC_TAG_INT ? elmc_as_int(msg) : (msg && (msg)->tag == ELMC_TAG_TUPLE2 && (msg)->payload != NULL ? elmc_as_int(((ElmcTuple2 *)(msg)->payload)->first) : -1));

    switch (case_msg_tag_1) {
      case ELMC_PEBBLE_MSG_INCREMENT: {

        // inlined Main.counterOf

        const elmc_int_t native_let_counter_2 = ELMC_RECORD_GET_INDEX_INT(model, ELMC_FIELD_MAIN_MODEL_VALUE);

        Rc = elmc_new_int(&owned[0], (native_let_counter_2 + 1));
        CHECK_RC(Rc);

        Rc = elmc_fn_Main_temperatureOf(out, (ElmcValue *[]){ model }, 1);
        CHECK_RC(Rc);

        ElmcValue *rec_values_2[2] = { owned[0], (*out) };
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

        const elmc_int_t native_let_counter_4 = ELMC_RECORD_GET_INDEX_INT(model, ELMC_FIELD_MAIN_MODEL_VALUE);

        Rc = elmc_new_int(&owned[2], (native_let_counter_4 - 1));
        CHECK_RC(Rc);

        Rc = elmc_fn_Main_temperatureOf(out, (ElmcValue *[]){ model }, 1);
        CHECK_RC(Rc);

        ElmcValue *rec_values_3[2] = { owned[2], (*out) };
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
        Rc = elmc_new_int(&owned[4], ELMC_RECORD_GET_INDEX_INT(model, ELMC_FIELD_MAIN_MODEL_VALUE));
        CHECK_RC(Rc);

        owned[5] = ((ElmcTuple2 *)msg->payload)->second ? elmc_retain(((ElmcTuple2 *)msg->payload)->second) : elmc_int_zero();
        Rc = elmc_maybe_just_own(&owned[6], owned[5]);
        CHECK_RC(Rc);
        owned[5] = NULL;

        ElmcValue *rec_values_4[2] = { owned[4], owned[6] };
        Rc = elmc_record_new_values_take(out, 2, rec_values_4);
        CHECK_RC(Rc);
        owned[4] = NULL;
        owned[6] = NULL;

        owned[7] = elmc_int_zero();
        Rc = elmc_tuple2_take(out, (*out), owned[7]);
        CHECK_RC(Rc);
        owned[7] = NULL;

        break;
      }
      case ELMC_PEBBLE_MSG_CURRENTTIMESTRING: {
        owned[8] = model ? elmc_retain(model) : elmc_int_zero();
        owned[9] = elmc_int_zero();
        Rc = elmc_tuple2_take(out, owned[8], owned[9]);
        CHECK_RC(Rc);
        owned[8] = NULL;
        owned[9] = NULL;

        break;
      }
      case ELMC_PEBBLE_MSG_CLOCKSTYLE24H: {
        owned[10] = model ? elmc_retain(model) : elmc_int_zero();
        owned[11] = elmc_int_zero();
        Rc = elmc_tuple2_take(out, owned[10], owned[11]);
        CHECK_RC(Rc);
        owned[10] = NULL;
        owned[11] = NULL;

        break;
      }
      case ELMC_PEBBLE_MSG_TIMEZONEISSET: {
        owned[12] = model ? elmc_retain(model) : elmc_int_zero();
        owned[13] = elmc_int_zero();
        Rc = elmc_tuple2_take(out, owned[12], owned[13]);
        CHECK_RC(Rc);
        owned[12] = NULL;
        owned[13] = NULL;

        break;
      }
      case ELMC_PEBBLE_MSG_TIMEZONENAME: {
        owned[14] = model ? elmc_retain(model) : elmc_int_zero();
        owned[15] = elmc_int_zero();
        Rc = elmc_tuple2_take(out, owned[14], owned[15]);
        CHECK_RC(Rc);
        owned[14] = NULL;
        owned[15] = NULL;

        break;
      }
      case ELMC_PEBBLE_MSG_WATCHMODELNAME: {
        owned[16] = model ? elmc_retain(model) : elmc_int_zero();
        owned[17] = elmc_int_zero();
        Rc = elmc_tuple2_take(out, owned[16], owned[17]);
        CHECK_RC(Rc);
        owned[16] = NULL;
        owned[17] = NULL;

        break;
      }
      case ELMC_PEBBLE_MSG_WATCHCOLORNAME: {
        owned[18] = model ? elmc_retain(model) : elmc_int_zero();
        owned[19] = elmc_int_zero();
        Rc = elmc_tuple2_take(out, owned[18], owned[19]);
        CHECK_RC(Rc);
        owned[18] = NULL;
        owned[19] = NULL;

        break;
      }
      case ELMC_PEBBLE_MSG_FIRMWAREVERSIONSTRING: {
        owned[20] = model ? elmc_retain(model) : elmc_int_zero();
        owned[21] = elmc_int_zero();
        Rc = elmc_tuple2_take(out, owned[20], owned[21]);
        CHECK_RC(Rc);
        owned[20] = NULL;
        owned[21] = NULL;

        break;
      }
      default: {
        owned[22] = model ? elmc_retain(model) : elmc_int_zero();
        owned[23] = elmc_int_zero();
        Rc = elmc_tuple2_take(out, owned[22], owned[23]);
        CHECK_RC(Rc);
        owned[22] = NULL;
        owned[23] = NULL;

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
  ElmcValue *owned[16] = {0};

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

        Rc = elmc_new_int(&owned[0], native_let_next_3);
        CHECK_RC(Rc);

        Rc = elmc_fn_Main_temperatureOf(out, (ElmcValue *[]){ model }, 1);
        CHECK_RC(Rc);

        ElmcValue *rec_values_5[2] = { owned[0], (*out) };
        Rc = elmc_record_new_values_take(out, 2, rec_values_5);
        CHECK_RC(Rc);
        owned[0] = NULL;

        Rc = elmc_cmd1(&owned[1], ELMC_PEBBLE_CMD_TIMER_AFTER_MS, 1000);
        CHECK_RC(Rc);

        Rc = elmc_tuple2_take(out, (*out), owned[1]);
        CHECK_RC(Rc);
        owned[1] = NULL;

        break;
      }
      case ELMC_PEBBLE_MSG_UPPRESSED: {

        // inlined Main.counterOf

        const elmc_int_t native_let_counter_5 = ELMC_RECORD_GET_INDEX_INT(model, ELMC_FIELD_MAIN_MODEL_VALUE);

        Rc = elmc_new_int(&owned[2], (native_let_counter_5 + 1));
        CHECK_RC(Rc);

        Rc = elmc_new_int(&owned[3], elmc_as_int(owned[2]));
        CHECK_RC(Rc);

        Rc = elmc_fn_Main_temperatureOf(out, (ElmcValue *[]){ model }, 1);
        CHECK_RC(Rc);

        ElmcValue *rec_values_6[2] = { owned[3], (*out) };
        Rc = elmc_record_new_values_take(out, 2, rec_values_6);
        CHECK_RC(Rc);
        owned[3] = NULL;

        Rc = elmc_cmd2(&owned[4], ELMC_PEBBLE_CMD_STORAGE_WRITE_INT, 1, elmc_as_int(owned[2]));
        CHECK_RC(Rc);

        Rc = elmc_tuple2_take(out, (*out), owned[4]);
        CHECK_RC(Rc);
        owned[4] = NULL;

        break;
      }
      case ELMC_PEBBLE_MSG_SELECTPRESSED: {
        owned[5] = model ? elmc_retain(model) : elmc_int_zero();

        Rc = elmc_new_int(&owned[6], ELMC_UNION_COMPANION_TYPES_BERLIN);
        CHECK_RC(Rc);

        Rc = elmc_fn_Main_requestWeather(&owned[7], (ElmcValue *[]){ owned[6] }, 1);
        CHECK_RC(Rc);

        Rc = elmc_fn_Main_requestSystemInfo(&owned[8], NULL, 0);
        CHECK_RC(Rc);

        ElmcValue *list_items_10[2] = { owned[7], owned[8] };
        Rc = elmc_list_from_values_take(out, list_items_10, 2);
        CHECK_RC(Rc);
        owned[7] = NULL;
        owned[8] = NULL;

        owned[9] = elmc_cmd_batch((*out));

        Rc = elmc_tuple2_take(out, owned[5], owned[9]);
        CHECK_RC(Rc);
        owned[5] = NULL;
        owned[9] = NULL;

        break;
      }
      case ELMC_PEBBLE_MSG_DOWNPRESSED: {

        // inlined Main.counterOf

        const elmc_int_t native_let_counter_12 = ELMC_RECORD_GET_INDEX_INT(model, ELMC_FIELD_MAIN_MODEL_VALUE);

        Rc = elmc_new_int(&owned[10], (native_let_counter_12 - 1));
        CHECK_RC(Rc);

        Rc = elmc_fn_Main_temperatureOf(out, (ElmcValue *[]){ model }, 1);
        CHECK_RC(Rc);

        ElmcValue *rec_values_7[2] = { owned[10], (*out) };
        Rc = elmc_record_new_values_take(out, 2, rec_values_7);
        CHECK_RC(Rc);
        owned[10] = NULL;

        Rc = elmc_cmd1(&owned[11], ELMC_PEBBLE_CMD_STORAGE_DELETE, 1);
        CHECK_RC(Rc);

        Rc = elmc_tuple2_take(out, (*out), owned[11]);
        CHECK_RC(Rc);
        owned[11] = NULL;

        break;
      }
      case ELMC_PEBBLE_MSG_ACCELTAP: {

        // inlined Main.counterOf

        const elmc_int_t native_let_counter_14 = ELMC_RECORD_GET_INDEX_INT(model, ELMC_FIELD_MAIN_MODEL_VALUE);

        Rc = elmc_new_int(&owned[12], (native_let_counter_14 + 1));
        CHECK_RC(Rc);

        Rc = elmc_fn_Main_temperatureOf(out, (ElmcValue *[]){ model }, 1);
        CHECK_RC(Rc);

        ElmcValue *rec_values_8[2] = { owned[12], (*out) };
        Rc = elmc_record_new_values_take(out, 2, rec_values_8);
        CHECK_RC(Rc);
        owned[12] = NULL;

        owned[13] = elmc_int_zero();
        Rc = elmc_tuple2_take(out, (*out), owned[13]);
        CHECK_RC(Rc);
        owned[13] = NULL;

        break;
      }
      default: {
        owned[14] = model ? elmc_retain(model) : elmc_int_zero();
        owned[15] = elmc_int_zero();
        Rc = elmc_tuple2_take(out, owned[14], owned[15]);
        CHECK_RC(Rc);
        owned[14] = NULL;
        owned[15] = NULL;

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
  ElmcValue *owned[5] = {0};

  ElmcValue *_unused_0 = (argc > 0) ? args[0] : NULL;
  (void)_unused_0;

  CATCH_BEGIN

    Rc = elmc_sub1(&owned[0], ELMC_SUBSCRIPTION_SECOND_CHANGE, ELMC_PEBBLE_MSG_TICK);
    CHECK_RC(Rc);

    Rc = elmc_sub3(&owned[1], ELMC_SUBSCRIPTION_BUTTON_RAW, ELMC_BUTTON_UP, ELMC_BUTTON_EVENT_PRESSED, ELMC_PEBBLE_MSG_UPPRESSED);
    CHECK_RC(Rc);

    Rc = elmc_sub3(&owned[2], ELMC_SUBSCRIPTION_BUTTON_RAW, ELMC_BUTTON_SELECT, ELMC_BUTTON_EVENT_PRESSED, ELMC_PEBBLE_MSG_SELECTPRESSED);
    CHECK_RC(Rc);

    Rc = elmc_sub3(&owned[3], ELMC_SUBSCRIPTION_BUTTON_RAW, ELMC_BUTTON_DOWN, ELMC_BUTTON_EVENT_PRESSED, ELMC_PEBBLE_MSG_DOWNPRESSED);
    CHECK_RC(Rc);

    Rc = elmc_sub1(&owned[4], ELMC_SUBSCRIPTION_ACCEL_TAP, ELMC_PEBBLE_MSG_ACCELTAP);
    CHECK_RC(Rc);

    ElmcValue *list_items_6[5] = { owned[0], owned[1], owned[2], owned[3], owned[4] };
    Rc = elmc_list_from_values_take(out, list_items_6, 5);
    CHECK_RC(Rc);
    owned[0] = NULL;
    owned[1] = NULL;
    owned[2] = NULL;
    owned[3] = NULL;
    owned[4] = NULL;

  CATCH_END;

  elmc_release_array_lifo(owned, DIM(owned));
  return Rc;
}

RC elmc_fn_Main_view(ElmcValue **out, ElmcValue ** const args, const int argc) {
  /* Ownership policy: borrow_arg, borrow_result */
  RC Rc = RC_SUCCESS;
  ElmcValue *owned[93] = {0};

  ElmcValue *model = (argc > 0) ? args[0] : NULL;

  CATCH_BEGIN
    // #region agent log
    elmc_agent_generated_probe(0xED998100);
    // #endregion

    Rc = elmc_new_int(&owned[0], ELMC_UI_NODE_WINDOW_STACK);
    CHECK_RC(Rc);

    Rc = elmc_new_int(&owned[1], ELMC_UI_NODE_WINDOW);
    CHECK_RC(Rc);

    Rc = elmc_new_int(&owned[2], 1);
    CHECK_RC(Rc);

    Rc = elmc_new_int(&owned[3], ELMC_UI_NODE_CANVAS_LAYER);
    CHECK_RC(Rc);

    Rc = elmc_new_int(&owned[4], 1);
    CHECK_RC(Rc);

    ElmcValue *tmp_6 = elmc_render_cmd6(ELMC_RENDER_OP_CLEAR, ELMC_COLOR_WHITE, 0, 0, 0, 0, 0);

    Rc = elmc_new_int(&owned[5], ELMC_RENDER_OP_CONTEXT_GROUP);
    CHECK_RC(Rc);

    Rc = elmc_tuple2_ints(&owned[6], ELMC_CONTEXT_STROKE_WIDTH, 3);
    CHECK_RC(Rc);

    Rc = elmc_tuple2_ints(&owned[7], ELMC_CONTEXT_ANTIALIASED, 1);
    CHECK_RC(Rc);

    Rc = elmc_tuple2_ints(&owned[8], ELMC_CONTEXT_STROKE_COLOR, ELMC_COLOR_BLACK);
    CHECK_RC(Rc);

    Rc = elmc_tuple2_ints(&owned[9], ELMC_CONTEXT_FILL_COLOR, ELMC_COLOR_BLACK);
    CHECK_RC(Rc);

    Rc = elmc_tuple2_ints(&owned[10], ELMC_CONTEXT_TEXT_COLOR, ELMC_COLOR_BLACK);
    CHECK_RC(Rc);

    ElmcValue *list_items_12[5] = { owned[6], owned[7], owned[8], owned[9], owned[10] };
    Rc = elmc_list_from_values_take(&owned[11], list_items_12, 5);
    CHECK_RC(Rc);
    owned[6] = NULL;
    owned[7] = NULL;
    owned[8] = NULL;
    owned[9] = NULL;
    owned[10] = NULL;

    ElmcValue *tmp_14 = elmc_render_cmd6(ELMC_RENDER_OP_ROUND_RECT, 6, 6, 132, 70, 6, ELMC_COLOR_BLACK);

    ElmcValue *tmp_15 = elmc_render_cmd6(ELMC_RENDER_OP_ARC, 20, 16, 36, 36, 0, 45000);

    Rc = elmc_new_int(&owned[12], ELMC_RENDER_OP_PATH_OUTLINE);
    CHECK_RC(Rc);

    Rc = elmc_new_int(&owned[13], 0);
    CHECK_RC(Rc);

    ElmcValue *rec_values_9[2] = { owned[13], elmc_retain(owned[13]) };
    Rc = elmc_record_new_values_take(&owned[14], 2, rec_values_9);
    CHECK_RC(Rc);
    owned[13] = NULL;

    Rc = elmc_new_int(&owned[15], 10);
    CHECK_RC(Rc);

    Rc = elmc_new_int(&owned[16], 4);
    CHECK_RC(Rc);

    ElmcValue *rec_values_10[2] = { owned[15], owned[16] };
    Rc = elmc_record_new_values_take(&owned[17], 2, rec_values_10);
    CHECK_RC(Rc);
    owned[15] = NULL;
    owned[16] = NULL;

    Rc = elmc_new_int(&owned[18], 16);
    CHECK_RC(Rc);

    Rc = elmc_new_int(&owned[19], 14);
    CHECK_RC(Rc);

    ElmcValue *rec_values_11[2] = { owned[18], owned[19] };
    Rc = elmc_record_new_values_take(&owned[20], 2, rec_values_11);
    CHECK_RC(Rc);
    owned[18] = NULL;
    owned[19] = NULL;

    Rc = elmc_new_int(&owned[21], 8);
    CHECK_RC(Rc);

    Rc = elmc_new_int(&owned[22], 24);
    CHECK_RC(Rc);

    ElmcValue *rec_values_12[2] = { owned[21], owned[22] };
    Rc = elmc_record_new_values_take(&owned[23], 2, rec_values_12);
    CHECK_RC(Rc);
    owned[21] = NULL;
    owned[22] = NULL;

    Rc = elmc_new_int(&owned[24], 0);
    CHECK_RC(Rc);

    Rc = elmc_new_int(&owned[25], 18);
    CHECK_RC(Rc);

    ElmcValue *rec_values_13[2] = { owned[24], owned[25] };
    Rc = elmc_record_new_values_take(&owned[26], 2, rec_values_13);
    CHECK_RC(Rc);
    owned[24] = NULL;
    owned[25] = NULL;

    ElmcValue *list_record_items_28[5] = { owned[14], owned[17], owned[20], owned[23], owned[26] };
    Rc = elmc_list_from_record_array(&owned[27], list_record_items_28, 5);
    CHECK_RC(Rc);
    owned[14] = NULL;
    owned[17] = NULL;
    owned[20] = NULL;
    owned[23] = NULL;
    owned[26] = NULL;

    Rc = elmc_new_int(&owned[28], 86);
    CHECK_RC(Rc);

    Rc = elmc_new_int(&owned[29], 16);
    CHECK_RC(Rc);

    ElmcValue *rec_values_14[2] = { owned[28], owned[29] };
    Rc = elmc_record_new_values_take(&owned[30], 2, rec_values_14);
    CHECK_RC(Rc);
    owned[28] = NULL;
    owned[29] = NULL;

    Rc = elmc_new_int(&owned[31], ELMC_UNION_PEBBLE_UI_ROTATION);
    CHECK_RC(Rc);
    owned[32] = elmc_int_zero();
    Rc = elmc_tuple2_take(&owned[33], owned[31], owned[32]);
    CHECK_RC(Rc);
    owned[31] = NULL;
    owned[32] = NULL;

    ElmcValue *call_args_35[3] = { owned[27], owned[30], owned[33] };
    Rc = elmc_fn_Pebble_Ui_path(&owned[34], call_args_35, 3);
    CHECK_RC(Rc);

    Rc = elmc_tuple2_take(&owned[35], owned[12], owned[34]);
    CHECK_RC(Rc);
    owned[12] = NULL;
    owned[34] = NULL;

    Rc = elmc_new_int(&owned[36], ELMC_RENDER_OP_PATH_FILLED);
    CHECK_RC(Rc);

    Rc = elmc_new_int(&owned[37], 0);
    CHECK_RC(Rc);

    ElmcValue *rec_values_15[2] = { owned[37], elmc_retain(owned[37]) };
    Rc = elmc_record_new_values_take(&owned[38], 2, rec_values_15);
    CHECK_RC(Rc);
    owned[37] = NULL;

    Rc = elmc_new_int(&owned[39], 8);
    CHECK_RC(Rc);

    Rc = elmc_new_int(&owned[40], 6);
    CHECK_RC(Rc);

    ElmcValue *rec_values_16[2] = { owned[39], owned[40] };
    Rc = elmc_record_new_values_take(&owned[41], 2, rec_values_16);
    CHECK_RC(Rc);
    owned[39] = NULL;
    owned[40] = NULL;

    Rc = elmc_new_int(&owned[42], 6);
    CHECK_RC(Rc);

    Rc = elmc_new_int(&owned[43], 14);
    CHECK_RC(Rc);

    ElmcValue *rec_values_17[2] = { owned[42], owned[43] };
    Rc = elmc_record_new_values_take(&owned[44], 2, rec_values_17);
    CHECK_RC(Rc);
    owned[42] = NULL;
    owned[43] = NULL;

    Rc = elmc_new_int(&owned[45], 2);
    CHECK_RC(Rc);

    Rc = elmc_new_int(&owned[46], 20);
    CHECK_RC(Rc);

    ElmcValue *rec_values_18[2] = { owned[45], owned[46] };
    Rc = elmc_record_new_values_take(&owned[47], 2, rec_values_18);
    CHECK_RC(Rc);
    owned[45] = NULL;
    owned[46] = NULL;

    Rc = elmc_new_int(&owned[48], 0);
    CHECK_RC(Rc);

    Rc = elmc_new_int(&owned[49], 14);
    CHECK_RC(Rc);

    ElmcValue *rec_values_19[2] = { owned[48], owned[49] };
    Rc = elmc_record_new_values_take(&owned[50], 2, rec_values_19);
    CHECK_RC(Rc);
    owned[48] = NULL;
    owned[49] = NULL;

    ElmcValue *list_record_items_52[5] = { owned[38], owned[41], owned[44], owned[47], owned[50] };
    Rc = elmc_list_from_record_array(&owned[51], list_record_items_52, 5);
    CHECK_RC(Rc);
    owned[38] = NULL;
    owned[41] = NULL;
    owned[44] = NULL;
    owned[47] = NULL;
    owned[50] = NULL;

    Rc = elmc_new_int(&owned[52], 108);
    CHECK_RC(Rc);

    Rc = elmc_new_int(&owned[53], 26);
    CHECK_RC(Rc);

    ElmcValue *rec_values_20[2] = { owned[52], owned[53] };
    Rc = elmc_record_new_values_take(&owned[54], 2, rec_values_20);
    CHECK_RC(Rc);
    owned[52] = NULL;
    owned[53] = NULL;

    Rc = elmc_new_int(&owned[55], ELMC_UNION_PEBBLE_UI_ROTATION);
    CHECK_RC(Rc);
    owned[56] = elmc_int_zero();
    Rc = elmc_tuple2_take(&owned[57], owned[55], owned[56]);
    CHECK_RC(Rc);
    owned[55] = NULL;
    owned[56] = NULL;

    ElmcValue *call_args_59[3] = { owned[51], owned[54], owned[57] };
    Rc = elmc_fn_Pebble_Ui_path(&owned[58], call_args_59, 3);
    CHECK_RC(Rc);

    Rc = elmc_tuple2_take(&owned[59], owned[36], owned[58]);
    CHECK_RC(Rc);
    owned[36] = NULL;
    owned[58] = NULL;

    Rc = elmc_new_int(&owned[60], ELMC_RENDER_OP_PATH_OUTLINE_OPEN);
    CHECK_RC(Rc);

    Rc = elmc_new_int(&owned[61], 0);
    CHECK_RC(Rc);

    ElmcValue *rec_values_21[2] = { owned[61], elmc_retain(owned[61]) };
    Rc = elmc_record_new_values_take(&owned[62], 2, rec_values_21);
    CHECK_RC(Rc);
    owned[61] = NULL;

    Rc = elmc_new_int(&owned[63], 8);
    CHECK_RC(Rc);

    Rc = elmc_new_int(&owned[64], 4);
    CHECK_RC(Rc);

    ElmcValue *rec_values_22[2] = { owned[63], owned[64] };
    Rc = elmc_record_new_values_take(&owned[65], 2, rec_values_22);
    CHECK_RC(Rc);
    owned[63] = NULL;
    owned[64] = NULL;

    Rc = elmc_new_int(&owned[66], 16);
    CHECK_RC(Rc);

    Rc = elmc_new_int(&owned[67], 2);
    CHECK_RC(Rc);

    ElmcValue *rec_values_23[2] = { owned[66], owned[67] };
    Rc = elmc_record_new_values_take(&owned[68], 2, rec_values_23);
    CHECK_RC(Rc);
    owned[66] = NULL;
    owned[67] = NULL;

    Rc = elmc_new_int(&owned[69], 24);
    CHECK_RC(Rc);

    Rc = elmc_new_int(&owned[70], 6);
    CHECK_RC(Rc);

    ElmcValue *rec_values_24[2] = { owned[69], owned[70] };
    Rc = elmc_record_new_values_take(&owned[71], 2, rec_values_24);
    CHECK_RC(Rc);
    owned[69] = NULL;
    owned[70] = NULL;

    ElmcValue *list_record_items_73[4] = { owned[62], owned[65], owned[68], owned[71] };
    Rc = elmc_list_from_record_array(&owned[72], list_record_items_73, 4);
    CHECK_RC(Rc);
    owned[62] = NULL;
    owned[65] = NULL;
    owned[68] = NULL;
    owned[71] = NULL;

    Rc = elmc_new_int(&owned[73], 10);
    CHECK_RC(Rc);

    Rc = elmc_new_int(&owned[74], 78);
    CHECK_RC(Rc);

    ElmcValue *rec_values_25[2] = { owned[73], owned[74] };
    Rc = elmc_record_new_values_take(&owned[75], 2, rec_values_25);
    CHECK_RC(Rc);
    owned[73] = NULL;
    owned[74] = NULL;

    Rc = elmc_new_int(&owned[76], ELMC_UNION_PEBBLE_UI_ROTATION);
    CHECK_RC(Rc);
    owned[77] = elmc_int_zero();
    Rc = elmc_tuple2_take(&owned[78], owned[76], owned[77]);
    CHECK_RC(Rc);
    owned[76] = NULL;
    owned[77] = NULL;

    ElmcValue *call_args_80[3] = { owned[72], owned[75], owned[78] };
    Rc = elmc_fn_Pebble_Ui_path(&owned[79], call_args_80, 3);
    CHECK_RC(Rc);

    Rc = elmc_tuple2_take(&owned[80], owned[60], owned[79]);
    CHECK_RC(Rc);
    owned[60] = NULL;
    owned[79] = NULL;

    ElmcValue *list_items_82[5] = { tmp_14, tmp_15, owned[35], owned[59], owned[80] };
    Rc = elmc_list_from_values_take(&owned[81], list_items_82, 5);
    CHECK_RC(Rc);
    tmp_14 = NULL;
    tmp_15 = NULL;
    owned[35] = NULL;
    owned[59] = NULL;
    owned[80] = NULL;

    Rc = elmc_tuple2_take(&owned[82], owned[11], owned[81]);
    CHECK_RC(Rc);
    owned[11] = NULL;
    owned[81] = NULL;

    Rc = elmc_tuple2_take(&owned[83], owned[5], owned[82]);
    CHECK_RC(Rc);
    owned[5] = NULL;
    owned[82] = NULL;

    ElmcValue *tmp_85 = elmc_render_cmd6(ELMC_RENDER_OP_LINE, 0, 84, 143, 84, ELMC_COLOR_BLACK, 0);

    ElmcValue *tmp_86 = elmc_render_cmd6(ELMC_RENDER_OP_PIXEL, 72, 84, ELMC_COLOR_BLACK, 0, 0, 0);

    Rc = elmc_fn_Main_statusDraw(&owned[84], (ElmcValue *[]){ model }, 1);
    CHECK_RC(Rc);

    Rc = elmc_fn_Main_counterDraw(&owned[85], (ElmcValue *[]){ model }, 1);
    CHECK_RC(Rc);

    ElmcValue *list_items_91[6] = { tmp_6, owned[83], tmp_85, tmp_86, owned[84], owned[85] };
    Rc = elmc_list_from_values_take(&owned[86], list_items_91, 6);
    CHECK_RC(Rc);
    tmp_6 = NULL;
    owned[83] = NULL;
    tmp_85 = NULL;
    tmp_86 = NULL;
    owned[84] = NULL;
    owned[85] = NULL;

    Rc = elmc_tuple2_take(&owned[87], owned[4], owned[86]);
    CHECK_RC(Rc);
    owned[4] = NULL;
    owned[86] = NULL;

    Rc = elmc_tuple2_take(&owned[88], owned[3], owned[87]);
    CHECK_RC(Rc);
    owned[3] = NULL;
    owned[87] = NULL;

    ElmcValue *list_items_93[1] = { owned[88] };
    Rc = elmc_list_from_values_take(&owned[89], list_items_93, 1);
    CHECK_RC(Rc);
    owned[88] = NULL;

    Rc = elmc_tuple2_take(&owned[90], owned[2], owned[89]);
    CHECK_RC(Rc);
    owned[2] = NULL;
    owned[89] = NULL;

    Rc = elmc_tuple2_take(&owned[91], owned[1], owned[90]);
    CHECK_RC(Rc);
    owned[1] = NULL;
    owned[90] = NULL;

    ElmcValue *list_items_95[1] = { owned[91] };
    Rc = elmc_list_from_values_take(&owned[92], list_items_95, 1);
    CHECK_RC(Rc);
    owned[91] = NULL;

    Rc = elmc_tuple2_take(out, owned[0], owned[92]);
    CHECK_RC(Rc);
    owned[0] = NULL;
    owned[92] = NULL;

    // #region agent log
    if (!(*out)) {
      elmc_agent_generated_probe(0xED998113);
    } else if ((*out)->tag == ELMC_TAG_TUPLE2) {
      elmc_agent_generated_probe(0xED998111);
    } else if ((*out)->tag == ELMC_TAG_LIST) {
      elmc_agent_generated_probe(0xED998112);
    } else {
      elmc_agent_generated_probe(0xED998110);
    }

    // #endregion

  CATCH_END;

  elmc_release_array_lifo(owned, DIM(owned));
  return Rc;
}

static RC elmc_fn_Main_statusDraw(ElmcValue **out, ElmcValue ** const args, const int argc) {
  /* Ownership policy: borrow_arg, borrow_result */
  RC Rc = RC_SUCCESS;
  ElmcValue *owned[8] = {0};

  ElmcValue *model = (argc > 0) ? args[0] : NULL;

  CATCH_BEGIN

    Rc = elmc_fn_Main_temperatureOf(&owned[0], (ElmcValue *[]){ model }, 1);
    CHECK_RC(Rc);

    if (elmc_maybe_is_just(owned[0])) {
      Rc = elmc_fn_Main_temperatureValue(out, (ElmcValue *[]){ elmc_maybe_or_tuple_just_payload_borrow(owned[0]) }, 1);
      CHECK_RC(Rc);
      const elmc_int_t native_i_5 = elmc_as_int((*out));
      *out = elmc_render_cmd6(ELMC_RENDER_OP_TEXT_INT_WITH_FONT, 1, 0, 28, native_i_5, 0, 0);

    } else {
      Rc = elmc_new_int(&owned[1], ELMC_RENDER_OP_TEXT_LABEL_WITH_FONT);
      CHECK_RC(Rc);

      Rc = elmc_new_int(&owned[2], ELMC_RESOURCE_SLOT_DEFAULTFONT);
      CHECK_RC(Rc);
      owned[3] = elmc_int_zero();
      Rc = elmc_new_int(&owned[4], 28);
      CHECK_RC(Rc);
      owned[5] = elmc_int_zero();
      owned[6] = elmc_int_zero();
      Rc = elmc_new_int(&owned[7], ELMC_UNION_PEBBLE_UI_WAITINGFORCOMPANION);
      CHECK_RC(Rc);
      Rc = elmc_tuple2_take(out, owned[6], owned[7]);
      CHECK_RC(Rc);
      owned[6] = NULL;
      owned[7] = NULL;

      Rc = elmc_tuple2_take(out, owned[5], (*out));
      CHECK_RC(Rc);
      owned[5] = NULL;

      Rc = elmc_tuple2_take(out, owned[4], (*out));
      CHECK_RC(Rc);
      owned[4] = NULL;

      Rc = elmc_tuple2_take(out, owned[3], (*out));
      CHECK_RC(Rc);
      owned[3] = NULL;

      Rc = elmc_tuple2_take(out, owned[2], (*out));
      CHECK_RC(Rc);
      owned[2] = NULL;

      Rc = elmc_tuple2_take(out, owned[1], (*out));
      CHECK_RC(Rc);
      owned[1] = NULL;
    }

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
  ElmcValue *owned[2] = {0};

  ElmcValue *temperature = (argc > 0) ? args[0] : NULL;

  if (elmc_union_tag_matches(temperature, ELMC_UNION_COMPANION_TYPES_CELSIUS)) {
    owned[0] = ((ElmcTuple2 *)temperature->payload)->second ? elmc_retain(((ElmcTuple2 *)temperature->payload)->second) : elmc_int_zero();

    *out = owned[0];
    owned[0] = NULL;

  } else {
    owned[1] = ((ElmcTuple2 *)temperature->payload)->second ? elmc_retain(((ElmcTuple2 *)temperature->payload)->second) : elmc_int_zero();

    *out = owned[1];
    owned[1] = NULL;
  }

  elmc_release_array_lifo(owned, DIM(owned));
  return Rc;
}

static RC elmc_fn_Main_main(ElmcValue **out, ElmcValue ** const args, const int argc) {
  /* Ownership policy: borrow_arg, borrow_result */
  RC Rc = RC_SUCCESS;

  (void)args;
  (void)argc;

  *out = elmc_int_zero();

  return Rc;
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

static ElmcValue * elmc_fn_Pebble_Ui_windowStack(ElmcValue ** const args, const int argc) {
  /* Ownership policy: borrow_arg, retain_result */
  ElmcValue *windows = (argc > 0) ? args[0] : NULL;
  ElmcValue *tmp_1 = elmc_new_int_take(ELMC_UNION_PEBBLE_UI_WINDOWSTACK);
  ElmcValue *tmp_2 = windows ? elmc_retain(windows) : elmc_int_zero();
  ElmcValue *tmp_3 = elmc_tuple2_take_value(tmp_1, tmp_2);
  tmp_1 = NULL;
  tmp_2 = NULL;

  return tmp_3;
}

static ElmcValue * elmc_fn_Pebble_Ui_window(ElmcValue ** const args, const int argc) {
  /* Ownership policy: borrow_arg, retain_result */
  ElmcValue *id = (argc > 0) ? args[0] : NULL;
  ElmcValue *layers = (argc > 1) ? args[1] : NULL;
  ElmcValue *tmp_1 = elmc_new_int_take(ELMC_UNION_PEBBLE_UI_WINDOWNODE);
  ElmcValue *tmp_2 = elmc_retain(id);
  ElmcValue *tmp_3 = layers ? elmc_retain(layers) : elmc_int_zero();
  ElmcValue *tmp_4 = elmc_tuple2_take_value(tmp_2, tmp_3);
  tmp_2 = NULL;
  tmp_3 = NULL;

  ElmcValue *tmp_5 = elmc_tuple2_take_value(tmp_1, tmp_4);
  tmp_1 = NULL;
  tmp_4 = NULL;

  return tmp_5;
}

static ElmcValue * elmc_fn_Pebble_Ui_canvasLayer(ElmcValue ** const args, const int argc) {
  /* Ownership policy: borrow_arg, retain_result */
  ElmcValue *id = (argc > 0) ? args[0] : NULL;
  ElmcValue *ops = (argc > 1) ? args[1] : NULL;
  ElmcValue *tmp_1 = elmc_new_int_take(ELMC_UNION_PEBBLE_UI_CANVASLAYER);
  ElmcValue *tmp_2 = elmc_retain(id);
  ElmcValue *tmp_3 = ops ? elmc_retain(ops) : elmc_int_zero();
  ElmcValue *tmp_4 = elmc_tuple2_take_value(tmp_2, tmp_3);
  tmp_2 = NULL;
  tmp_3 = NULL;

  ElmcValue *tmp_5 = elmc_tuple2_take_value(tmp_1, tmp_4);
  tmp_1 = NULL;
  tmp_4 = NULL;

  return tmp_5;
}

static RC elmc_fn_Pebble_Ui_path(ElmcValue **out, ElmcValue ** const args, const int argc) {
  /* Ownership policy: borrow_arg, retain_result */
  RC Rc = RC_SUCCESS;
  ElmcValue *owned[12] = {0};

  ElmcValue *points = (argc > 0) ? args[0] : NULL;
  ElmcValue *offset = (argc > 1) ? args[1] : NULL;
  ElmcValue *rotation = (argc > 2) ? args[2] : NULL;

  CATCH_BEGIN

    /* elm/core: List.map */
    owned[2] = points ? elmc_retain(points) : elmc_int_zero();
    owned[3] = elmc_list_nil();
    ElmcValue **list_fwd_tail_4 = &owned[3];

    // List.map

    if (owned[2] && owned[2]->tag == ELMC_TAG_INT_LIST) {
      ElmcIntListPayload *_ilp_4 = (ElmcIntListPayload *)owned[2]->payload;
      int _ilen_4 = _ilp_4 ? _ilp_4->length : 0;
      for (int _ii_4 = 0; _ii_4 < _ilen_4; _ii_4++) {
        ElmcValue *list_map_head_4 = NULL;
        Rc = elmc_new_int(&list_map_head_4, _ilp_4->values[_ii_4]);
        CHECK_RC(Rc);

        owned[4] = elmc_record_get_index(list_map_head_4, 0 /* x */);

        owned[5] = elmc_record_get_index(list_map_head_4, 1 /* y */);

        Rc = elmc_tuple2_take(&owned[6], owned[4], owned[5]);
        CHECK_RC(Rc);
        owned[4] = NULL;
        owned[5] = NULL;

        ElmcValue *list_map_item_4 = owned[6] ? elmc_retain(owned[6]) : elmc_int_zero();
        ELMC_RELEASE(owned[6]);
        owned[6] = NULL;;
        if (elmc_list_nil() && elmc_list_nil()->tag == ELMC_TAG_INT_LIST && list_map_item_4 && (list_map_item_4->tag == ELMC_TAG_INT || list_map_item_4->tag == ELMC_TAG_CHAR)) {
          ElmcIntListPayload *_ilp_0 = (ElmcIntListPayload *)elmc_list_nil()->payload;
          int int_list_cons_tail_len_0 = _ilp_0 ? _ilp_0->length : 0;
          elmc_int_t int_list_cons_buf_0[1 + int_list_cons_tail_len_0];
          int_list_cons_buf_0[0] = elmc_as_int(list_map_item_4);
          for (int _ii_0 = 0; _ii_0 < int_list_cons_tail_len_0; _ii_0++) {
            int_list_cons_buf_0[_ii_0 + 1] = _ilp_0->values[_ii_0];
          }
          Rc = elmc_list_from_int_array(&owned[8], int_list_cons_buf_0, int_list_cons_tail_len_0 + 1);
          CHECK_RC(Rc);

        } else {
          Rc = elmc_list_cons(&owned[8], list_map_item_4, elmc_list_nil());
          CHECK_RC(Rc);

        }

        elmc_release(list_map_item_4);
        if (owned[8]) {
          *list_fwd_tail_4 = owned[8];
          list_fwd_tail_4 = &((ElmcCons *)owned[8]->payload)->tail;
        }
        owned[8] = NULL;

        elmc_release(list_map_head_4);;
      }
      CHECK_RC(Rc);
    } else {
      ElmcValue *list_walk_cursor_4 = owned[2];
      while (list_walk_cursor_4 && list_walk_cursor_4->tag == ELMC_TAG_LIST && list_walk_cursor_4->payload != NULL) {
        ElmcCons *list_walk_node_4 = (ElmcCons *)list_walk_cursor_4->payload;
        ElmcValue *list_map_head_4 = list_walk_node_4->head;

        owned[4] = elmc_record_get_index(list_map_head_4, 0 /* x */);

        owned[5] = elmc_record_get_index(list_map_head_4, 1 /* y */);

        Rc = elmc_tuple2_take(&owned[6], owned[4], owned[5]);
        CHECK_RC(Rc);
        owned[4] = NULL;
        owned[5] = NULL;

        ElmcValue *list_map_item_4 = owned[6] ? elmc_retain(owned[6]) : elmc_int_zero();
        ELMC_RELEASE(owned[6]);
        owned[6] = NULL;;
        if (elmc_list_nil() && elmc_list_nil()->tag == ELMC_TAG_INT_LIST && list_map_item_4 && (list_map_item_4->tag == ELMC_TAG_INT || list_map_item_4->tag == ELMC_TAG_CHAR)) {
          ElmcIntListPayload *_ilp_0 = (ElmcIntListPayload *)elmc_list_nil()->payload;
          int int_list_cons_tail_len_0 = _ilp_0 ? _ilp_0->length : 0;
          elmc_int_t int_list_cons_buf_0[1 + int_list_cons_tail_len_0];
          int_list_cons_buf_0[0] = elmc_as_int(list_map_item_4);
          for (int _ii_0 = 0; _ii_0 < int_list_cons_tail_len_0; _ii_0++) {
            int_list_cons_buf_0[_ii_0 + 1] = _ilp_0->values[_ii_0];
          }
          Rc = elmc_list_from_int_array(&owned[8], int_list_cons_buf_0, int_list_cons_tail_len_0 + 1);
          CHECK_RC(Rc);

        } else {
          Rc = elmc_list_cons(&owned[8], list_map_item_4, elmc_list_nil());
          CHECK_RC(Rc);

        }

        elmc_release(list_map_item_4);
        if (owned[8]) {
          *list_fwd_tail_4 = owned[8];
          list_fwd_tail_4 = &((ElmcCons *)owned[8]->payload)->tail;
        }
        owned[8] = NULL;

        list_walk_cursor_4 = list_walk_node_4->tail;
      }
    }

    owned[7] = owned[3];
    owned[3] = NULL;

    Rc = elmc_tuple2_ints(&owned[9], ELMC_RECORD_GET_INDEX_INT(offset, ELMC_FIELD_PEBBLE_UI_POINT_X), ELMC_RECORD_GET_INDEX_INT(offset, ELMC_FIELD_PEBBLE_UI_POINT_Y));
    CHECK_RC(Rc);

    ElmcValue *head_11 = NULL;
    Rc = elmc_fn_Pebble_Ui_rotationToPebbleAngle(&head_11, NULL, 0);
    CHECK_RC(Rc);
    ElmcValue *call_args_11[1] = { rotation };
    owned[10] = elmc_closure_call(head_11, call_args_11, 1);

    elmc_release(head_11);;

    Rc = elmc_tuple2_take(&owned[11], owned[9], owned[10]);
    CHECK_RC(Rc);
    owned[9] = NULL;
    owned[10] = NULL;

    Rc = elmc_tuple2_take(out, owned[7], owned[11]);
    CHECK_RC(Rc);
    owned[7] = NULL;
    owned[11] = NULL;

  CATCH_END;

  elmc_release_array_lifo(owned, DIM(owned));
  return Rc;
}

static RC elmc_fn_Pebble_Ui_rotationToPebbleAngle(ElmcValue **out, ElmcValue ** const args, const int argc) {
  /* Ownership policy: borrow_arg, borrow_result */
  RC Rc = RC_SUCCESS;

  (void)args;
  (void)argc;

  CATCH_BEGIN

    ElmcValue *tmp_1 = NULL;
    Rc = elmc_closure_new(&tmp_1, elmc_lambda_1, 1, 0, NULL);
    CHECK_RC(Rc);

    *out = tmp_1;
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

  ElmcValue *message = (argc > 0) ? args[0] : NULL;
  (void)message;

  CATCH_BEGIN

    Rc = elmc_new_int(out, 2);
    CHECK_RC(Rc);

  CATCH_END;

  return Rc;
}

static RC elmc_fn_Companion_Internal_watchToPhoneValue(ElmcValue **out, ElmcValue ** const args, const int argc) {
  /* Ownership policy: borrow_arg, borrow_result */
  RC Rc = RC_SUCCESS;

  ElmcValue *message = (argc > 0) ? args[0] : NULL;

  CATCH_BEGIN

    Rc = elmc_fn_Companion_Internal_encodeLocationCode(out, (ElmcValue *[]){ ((ElmcTuple2 *)message->payload)->second }, 1);
    CHECK_RC(Rc);

  CATCH_END;

  return Rc;
}

static RC elmc_fn_Companion_Watch_sendWatchToPhone(ElmcValue **out, ElmcValue ** const args, const int argc) {
  /* Ownership policy: borrow_arg, borrow_result */
  RC Rc = RC_SUCCESS;
  ElmcValue *owned[2] = {0};

  ElmcValue *message = (argc > 0) ? args[0] : NULL;

  CATCH_BEGIN

    Rc = elmc_fn_Companion_Internal_watchToPhoneTag(&owned[0], (ElmcValue *[]){ message }, 1);
    CHECK_RC(Rc);

    const elmc_int_t native_i_3 = elmc_as_int(owned[0]);

    Rc = elmc_fn_Companion_Internal_watchToPhoneValue(&owned[1], (ElmcValue *[]){ message }, 1);
    CHECK_RC(Rc);

    const elmc_int_t native_i_6 = elmc_as_int(owned[1]);

    Rc = elmc_cmd2(out, ELMC_PEBBLE_CMD_COMPANION_SEND, native_i_3, native_i_6);
    CHECK_RC(Rc);

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
  ElmcValue *owned[6] = {0};

  static ElmcPebbleDrawCmd scene_cmd;

  CATCH_BEGIN

    elmc_draw_cmd_init(&scene_cmd, ELMC_RENDER_OP_CLEAR);
    scene_cmd.p0 = ELMC_COLOR_WHITE;
    Rc = elmc_scene_writer_push_cmd(writer, &scene_cmd);
    CHECK_RC(Rc);

    elmc_draw_cmd_init(&scene_cmd, ELMC_RENDER_OP_PUSH_CONTEXT);

    Rc = elmc_scene_writer_push_cmd(writer, &scene_cmd);
    CHECK_RC(Rc);

    elmc_draw_cmd_init(&scene_cmd, ELMC_RENDER_OP_STROKE_WIDTH);
    scene_cmd.p0 = 3;
    Rc = elmc_scene_writer_push_cmd(writer, &scene_cmd);
    CHECK_RC(Rc);

    elmc_draw_cmd_init(&scene_cmd, ELMC_RENDER_OP_ANTIALIASED);
    scene_cmd.p0 = 1;
    Rc = elmc_scene_writer_push_cmd(writer, &scene_cmd);
    CHECK_RC(Rc);

    elmc_draw_cmd_init(&scene_cmd, ELMC_RENDER_OP_STROKE_COLOR);
    scene_cmd.p0 = ELMC_COLOR_BLACK;
    Rc = elmc_scene_writer_push_cmd(writer, &scene_cmd);
    CHECK_RC(Rc);

    elmc_draw_cmd_init(&scene_cmd, ELMC_RENDER_OP_FILL_COLOR);
    scene_cmd.p0 = ELMC_COLOR_BLACK;
    Rc = elmc_scene_writer_push_cmd(writer, &scene_cmd);
    CHECK_RC(Rc);

    elmc_draw_cmd_init(&scene_cmd, ELMC_RENDER_OP_TEXT_COLOR);
    scene_cmd.p0 = ELMC_COLOR_BLACK;
    Rc = elmc_scene_writer_push_cmd(writer, &scene_cmd);
    CHECK_RC(Rc);

    elmc_draw_cmd_init(&scene_cmd, ELMC_RENDER_OP_ROUND_RECT);
    scene_cmd.p0 = 6;
    scene_cmd.p1 = 6;
    scene_cmd.p2 = 132;
    scene_cmd.p3 = 70;
    scene_cmd.p4 = 6;
    scene_cmd.p5 = ELMC_COLOR_BLACK;
    Rc = elmc_scene_writer_push_cmd(writer, &scene_cmd);
    CHECK_RC(Rc);

    elmc_draw_cmd_init(&scene_cmd, ELMC_RENDER_OP_ARC);
    scene_cmd.p0 = 20;
    scene_cmd.p1 = 16;
    scene_cmd.p2 = 36;
    scene_cmd.p3 = 36;
    scene_cmd.p4 = 0;
    scene_cmd.p5 = 45000;
    Rc = elmc_scene_writer_push_cmd(writer, &scene_cmd);
    CHECK_RC(Rc);

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

    Rc = elmc_scene_writer_push_cmd(writer, &scene_cmd);
    CHECK_RC(Rc);

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

    Rc = elmc_scene_writer_push_cmd(writer, &scene_cmd);
    CHECK_RC(Rc);

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

    Rc = elmc_scene_writer_push_cmd(writer, &scene_cmd);
    CHECK_RC(Rc);

    elmc_draw_cmd_init(&scene_cmd, ELMC_RENDER_OP_POP_CONTEXT);

    Rc = elmc_scene_writer_push_cmd(writer, &scene_cmd);
    CHECK_RC(Rc);

    elmc_draw_cmd_init(&scene_cmd, ELMC_RENDER_OP_LINE);
    scene_cmd.p0 = 0;
    scene_cmd.p1 = 84;
    scene_cmd.p2 = 143;
    scene_cmd.p3 = 84;
    scene_cmd.p4 = ELMC_COLOR_BLACK;
    Rc = elmc_scene_writer_push_cmd(writer, &scene_cmd);
    CHECK_RC(Rc);

    elmc_draw_cmd_init(&scene_cmd, ELMC_RENDER_OP_PIXEL);
    scene_cmd.p0 = 72;
    scene_cmd.p1 = 84;
    scene_cmd.p2 = ELMC_COLOR_BLACK;
    Rc = elmc_scene_writer_push_cmd(writer, &scene_cmd);
    CHECK_RC(Rc);

    owned[0] = model ? elmc_retain(model) : elmc_int_zero();

    Rc = elmc_fn_Main_temperatureOf(&owned[1], (ElmcValue *[]){ owned[0] }, 1);
    CHECK_RC(Rc);

    if (elmc_maybe_is_just(owned[1])) {

      Rc = elmc_fn_Main_temperatureValue(&owned[2], (ElmcValue *[]){ elmc_maybe_or_tuple_just_payload_borrow(owned[1]) }, 1);
      CHECK_RC(Rc);

      const elmc_int_t native_i_17 = elmc_as_int(owned[2]);

      elmc_draw_cmd_init(&scene_cmd, ELMC_RENDER_OP_TEXT_INT_WITH_FONT);
      scene_cmd.p0 = 1;
      scene_cmd.p1 = 0;
      scene_cmd.p2 = 28;
      scene_cmd.p3 = native_i_17;
      Rc = elmc_scene_writer_push_cmd(writer, &scene_cmd);
      CHECK_RC(Rc);

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

      Rc = elmc_scene_writer_push_cmd(writer, &scene_cmd);
      CHECK_RC(Rc);

    }

    owned[4] = model ? elmc_retain(model) : elmc_int_zero();

    const elmc_int_t native_call_19 = elmc_fn_Main_counterOf_native(owned[4]);

    Rc = elmc_new_int(&owned[5], native_call_19);
    CHECK_RC(Rc);

    elmc_draw_cmd_init(&scene_cmd, ELMC_RENDER_OP_TEXT_INT_WITH_FONT);
    scene_cmd.p0 = 1;
    scene_cmd.p1 = 0;
    scene_cmd.p2 = 56;
    scene_cmd.p3 = elmc_as_int(owned[5]);
    Rc = elmc_scene_writer_push_cmd(writer, &scene_cmd);
    CHECK_RC(Rc);

  CATCH_END;
  elmc_release_array_lifo(owned, DIM(owned));

  return Rc;

}

RC elmc_fn_Main_view_scene_append(ElmcValue ** const args, const int argc, ElmcSceneWriter * const writer) {
  return elmc_fn_Main_view_commands_append(args, argc, writer);
}
