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

static RC elmc_fn_Main_helper_native(elmc_int_t *out, const elmc_int_t value);
static RC elmc_fn_Main_advanced_native(elmc_int_t *out, const elmc_int_t n);
static RC elmc_fn_Main_counterOf_native(elmc_int_t *out, ElmcValue * const model);
static RC elmc_fn_Main_temperatureValue_native(elmc_int_t *out, ElmcValue * const temperature);
static RC elmc_fn_Pebble_Platform_launchReasonToInt_native(elmc_int_t *out, ElmcValue * const launchReason);
static RC elmc_fn_Pebble_Ui_rotationToPebbleAngle_native(elmc_int_t *out);
static RC elmc_fn_Companion_Internal_encodeLocationCode_native(elmc_int_t *out, ElmcValue * const value);
static RC elmc_fn_Companion_Internal_watchToPhoneTag_native(elmc_int_t *out, ElmcValue * const message);
static RC elmc_fn_Companion_Internal_watchToPhoneValue_native(elmc_int_t *out, ElmcValue * const message);

static RC elmc_fn_Main_helper(ElmcValue **out, elmc_int_t value);
static RC elmc_fn_Main_advanced(ElmcValue **out, elmc_int_t n);
static RC elmc_fn_Main_counterOf(ElmcValue **out, ElmcValue *model);
static RC elmc_fn_Main_temperatureOf(ElmcValue **out, ElmcValue *model);
static RC elmc_fn_Main_requestWeather(ElmcValue **out, ElmcValue *location);
static RC elmc_fn_Main_requestSystemInfo(ElmcValue **out);
RC elmc_fn_Main_init(ElmcValue **out, ElmcValue *launchContext);
RC elmc_fn_Main_update(ElmcValue **out, ElmcValue *msg, ElmcValue *model);
static RC elmc_fn_Main_handleAppMsg(ElmcValue **out, ElmcValue *msg, ElmcValue *model);
static RC elmc_fn_Main_handlePlatformMsg(ElmcValue **out, ElmcValue *msg, ElmcValue *model);
RC elmc_fn_Main_subscriptions(ElmcValue **out, ElmcValue *_unused_0);
RC elmc_fn_Main_view(ElmcValue **out, ElmcValue *model);
static RC elmc_fn_Main_statusDraw(ElmcValue **out, ElmcValue *model);
static RC elmc_fn_Main_counterDraw(ElmcValue **out, ElmcValue *model);
static RC elmc_fn_Main_temperatureValue(ElmcValue **out, ElmcValue *temperature);
static RC elmc_fn_Main_main(ElmcValue **out);
static RC elmc_fn_Pebble_Platform_launchReasonToInt(ElmcValue **out, ElmcValue *launchReason);
static ElmcValue *elmc_fn_Pebble_Ui_windowStack(ElmcValue *windows);
static ElmcValue *elmc_fn_Pebble_Ui_window(ElmcValue *id, ElmcValue *layers);
static ElmcValue *elmc_fn_Pebble_Ui_canvasLayer(ElmcValue *id, ElmcValue *ops);
static RC elmc_fn_Pebble_Ui_path(ElmcValue **out, ElmcValue *points, ElmcValue *offset, ElmcValue *rotation);
static RC elmc_fn_Pebble_Ui_rotationToPebbleAngle(ElmcValue **out);
static RC elmc_fn_Companion_Internal_encodeLocationCode(ElmcValue **out, ElmcValue *value);
static RC elmc_fn_Companion_Internal_watchToPhoneTag(ElmcValue **out, ElmcValue *message);
static RC elmc_fn_Companion_Internal_watchToPhoneValue(ElmcValue **out, ElmcValue *message);

static RC elmc_fn_Pebble_Ui_path_closure_0(ElmcValue **out, ElmcValue **args, int argc, ElmcValue **captures, int capture_count) {
  (void)captures;
  (void)capture_count;
  RC Rc = RC_SUCCESS;

  ElmcValue *owned[4] = {0};
  CATCH_BEGIN
    /* plan block 0 */
    CATCH_BEGIN
      owned[0] = (argc > 0 ? args[0] : NULL);
      owned[1] = elmc_record_get_index(owned[0], 0 /* x */);
      owned[2] = elmc_record_get_index(owned[0], 1 /* y */);
      Rc = elmc_tuple2(&owned[3], owned[1], owned[2]);
      CHECK_RC(Rc);
      owned[1] = NULL;
      owned[2] = NULL;
      *out = owned[3];
      owned[3] = NULL;
      owned[3] = NULL;
    CATCH_END;
  CATCH_END;

  elmc_release_array_lifo(owned, 4);
  return Rc;
}
static RC elmc_fn_Pebble_Ui_rotationToPebbleAngle_closure_0(ElmcValue **out, ElmcValue **args, int argc, ElmcValue **captures, int capture_count) {
  (void)captures;
  (void)capture_count;
  RC Rc = RC_SUCCESS;

  ElmcValue *owned[4] = {0};
  CATCH_BEGIN
    /* plan block 0 */
    CATCH_BEGIN
      owned[0] = (argc > 0 ? args[0] : NULL);
      if (elmc_union_tag_matches(owned[0], 1)) goto elmc_plan_block_2; else goto elmc_plan_block_4;
      elmc_plan_block_2:
      owned[2] = elmc_union_payload(owned[0]);
      owned[3] = elmc_retain(owned[2]);
      owned[2] = NULL;
      owned[1] = elmc_retain(owned[3]);
      owned[3] = NULL;
      goto elmc_plan_block_4;
      elmc_plan_block_4:
      *out = owned[1];
      owned[1] = NULL;
      owned[1] = NULL;
    CATCH_END;
  CATCH_END;

  elmc_release_array_lifo(owned, 4);
  return Rc;
}

static RC elmc_fn_Main_helper(ElmcValue **out, elmc_int_t value) {
  /* Ownership policy: borrow_arg, borrow_result, direct_call_abi */
  RC Rc = RC_SUCCESS;
  ElmcValue *owned[2] = {0};
  CATCH_BEGIN
    /* plan block 0 */
    Rc = elmc_new_int(&owned[0], value);
    CHECK_RC(Rc);
    Rc = elmc_new_int(&owned[1], elmc_as_int(owned[0]) + 2);
    CHECK_RC(Rc);
    *out = owned[1];
    owned[1] = NULL;
    owned[1] = NULL;
    owned[0] = NULL;
  CATCH_END;

  elmc_release_array_lifo(owned, 2);
  return Rc;
}
static RC elmc_fn_Main_helper_native(elmc_int_t *out, const elmc_int_t value) {
  ElmcValue *boxed = NULL;
  RC Rc = elmc_fn_Main_helper(&boxed, value);
  if (Rc != RC_SUCCESS) return Rc;
  *out = elmc_as_int(boxed);
  elmc_release(boxed);
  return RC_SUCCESS;
}

static RC elmc_fn_Main_advanced(ElmcValue **out, elmc_int_t n) {
  /* Ownership policy: borrow_arg, borrow_result, direct_call_abi */
  RC Rc = RC_SUCCESS;
  ElmcValue *owned[6] = {0};
  CATCH_BEGIN
    /* plan block 0 */
    Rc = elmc_new_int(&owned[0], n);
    CHECK_RC(Rc);
    Rc = elmc_fn_Main_helper(&owned[1], elmc_as_int(owned[0]));
    CHECK_RC(Rc);
    Rc = elmc_new_int(&owned[2], 10);
    CHECK_RC(Rc);
    Rc = elmc_new_bool(&owned[3], (elmc_as_int(owned[1]) > elmc_as_int(owned[2])) ? 1 : 0);
    CHECK_RC(Rc);
    owned[2] = NULL;
    if (elmc_as_int(owned[3]) != 0) {
      goto elmc_plan_block_1;
    } else {
      goto elmc_plan_block_2;
    }
    elmc_plan_block_1:
    goto elmc_plan_block_3;
    elmc_plan_block_2:
    Rc = elmc_new_int(&owned[4], elmc_as_int(owned[1]) + 1);
    CHECK_RC(Rc);
    goto elmc_plan_block_3;
    elmc_plan_block_3:
    if (elmc_as_int(owned[3]) != 0) {
      owned[5] = elmc_retain(owned[1]);
    } else {
      owned[5] = elmc_retain(owned[4]);
    }
    owned[4] = NULL;
    owned[3] = NULL;
    *out = owned[5];
    owned[5] = NULL;
    owned[5] = NULL;
    owned[0] = NULL;
  CATCH_END;

  elmc_release_array_lifo(owned, 6);
  return Rc;
}
static RC elmc_fn_Main_advanced_native(elmc_int_t *out, const elmc_int_t n) {
  ElmcValue *boxed = NULL;
  RC Rc = elmc_fn_Main_advanced(&boxed, n);
  if (Rc != RC_SUCCESS) return Rc;
  *out = elmc_as_int(boxed);
  elmc_release(boxed);
  return RC_SUCCESS;
}

static RC elmc_fn_Main_counterOf(ElmcValue **out, ElmcValue *model) {
  /* Ownership policy: borrow_arg, borrow_result, direct_call_abi */
  RC Rc = RC_SUCCESS;
  ElmcValue *owned[2] = {0};
  CATCH_BEGIN
    /* plan block 0 */
    owned[0] = model;
    owned[1] = elmc_record_get_index(owned[0], 0 /* value */);
    *out = owned[1];
    owned[1] = NULL;
    owned[1] = NULL;
    owned[0] = NULL;
  CATCH_END;

  elmc_release_array_lifo(owned, 2);
  return Rc;
}
static RC elmc_fn_Main_counterOf_native(elmc_int_t *out, ElmcValue * const model) {
  ElmcValue *boxed = NULL;
  RC Rc = elmc_fn_Main_counterOf(&boxed, model);
  if (Rc != RC_SUCCESS) return Rc;
  *out = elmc_as_int(boxed);
  elmc_release(boxed);
  return RC_SUCCESS;
}

static RC elmc_fn_Main_temperatureOf(ElmcValue **out, ElmcValue *model) {
  /* Ownership policy: borrow_arg, borrow_result, direct_call_abi */
  RC Rc = RC_SUCCESS;
  ElmcValue *owned[2] = {0};
  CATCH_BEGIN
    /* plan block 0 */
    owned[0] = model;
    owned[1] = elmc_record_get_index(owned[0], 1 /* temperature */);
    *out = owned[1];
    owned[1] = NULL;
    owned[1] = NULL;
    owned[0] = NULL;
  CATCH_END;

  elmc_release_array_lifo(owned, 2);
  return Rc;
}

static RC elmc_fn_Main_requestWeather(ElmcValue **out, ElmcValue *location) {
  /* Ownership policy: borrow_arg, borrow_result, direct_call_abi */
  RC Rc = RC_SUCCESS;
  ElmcValue *owned[18] = {0};
  CATCH_BEGIN
    /* plan block 0 */
    owned[0] = location;
    Rc = elmc_new_int(&owned[1], ELMC_PEBBLE_CMD_COMPANION_SEND);
    CHECK_RC(Rc);
    Rc = elmc_new_int(&owned[2], 1);
    CHECK_RC(Rc);
    Rc = elmc_tuple2(&owned[3], owned[2], owned[0]);
    CHECK_RC(Rc);
    owned[2] = NULL;
    owned[4] = elmc_fn_Companion_Internal_watchToPhoneTag(owned[3]);
    owned[3] = NULL;
    Rc = elmc_new_int(&owned[5], 1);
    CHECK_RC(Rc);
    Rc = elmc_tuple2(&owned[6], owned[5], owned[0]);
    CHECK_RC(Rc);
    owned[5] = NULL;
    owned[7] = elmc_fn_Companion_Internal_watchToPhoneValue(owned[6]);
    owned[6] = NULL;
    Rc = elmc_new_int(&owned[8], 0);
    CHECK_RC(Rc);
    Rc = elmc_new_int(&owned[9], 0);
    CHECK_RC(Rc);
    Rc = elmc_new_int(&owned[10], 0);
    CHECK_RC(Rc);
    Rc = elmc_new_int(&owned[11], 0);
    CHECK_RC(Rc);
    Rc = elmc_tuple2(&owned[12], owned[10], owned[11]);
    CHECK_RC(Rc);
    owned[10] = NULL;
    owned[11] = NULL;
    Rc = elmc_tuple2(&owned[13], owned[9], owned[12]);
    CHECK_RC(Rc);
    owned[9] = NULL;
    owned[12] = NULL;
    Rc = elmc_tuple2(&owned[14], owned[8], owned[13]);
    CHECK_RC(Rc);
    owned[8] = NULL;
    owned[13] = NULL;
    Rc = elmc_tuple2(&owned[15], owned[7], owned[14]);
    CHECK_RC(Rc);
    owned[7] = NULL;
    owned[14] = NULL;
    Rc = elmc_tuple2(&owned[16], owned[4], owned[15]);
    CHECK_RC(Rc);
    owned[4] = NULL;
    owned[15] = NULL;
    Rc = elmc_tuple2(&owned[17], owned[1], owned[16]);
    CHECK_RC(Rc);
    owned[1] = NULL;
    owned[16] = NULL;
    *out = owned[17];
    owned[17] = NULL;
    owned[17] = NULL;
    owned[0] = NULL;
  CATCH_END;

  elmc_release_array_lifo(owned, 18);
  return Rc;
}

static RC elmc_fn_Main_requestSystemInfo(ElmcValue **out) {
  /* Ownership policy: borrow_arg, borrow_result, direct_call_abi */
  RC Rc = RC_SUCCESS;
  ElmcValue *owned[23] = {0};
  CATCH_BEGIN
    /* plan block 0 */
    owned[0] = elmc_list_nil();
    Rc = elmc_new_int(&owned[1], 15);
    CHECK_RC(Rc);
    Rc = elmc_cmd1(&owned[2], ELMC_PEBBLE_CMD_GET_FIRMWARE_VERSION, elmc_as_int(owned[1]));
    CHECK_RC(Rc);
    owned[1] = NULL;
    Rc = elmc_list_cons(&owned[3], owned[2], owned[0]);
    CHECK_RC(Rc);
    owned[2] = NULL;
    owned[0] = NULL;
    Rc = elmc_new_int(&owned[4], 14);
    CHECK_RC(Rc);
    Rc = elmc_cmd1(&owned[5], ELMC_PEBBLE_CMD_GET_WATCH_COLOR, elmc_as_int(owned[4]));
    CHECK_RC(Rc);
    owned[4] = NULL;
    Rc = elmc_list_cons(&owned[6], owned[5], owned[3]);
    CHECK_RC(Rc);
    owned[5] = NULL;
    owned[3] = NULL;
    Rc = elmc_new_int(&owned[7], 13);
    CHECK_RC(Rc);
    Rc = elmc_cmd1(&owned[8], ELMC_PEBBLE_CMD_GET_WATCH_MODEL, elmc_as_int(owned[7]));
    CHECK_RC(Rc);
    owned[7] = NULL;
    Rc = elmc_list_cons(&owned[9], owned[8], owned[6]);
    CHECK_RC(Rc);
    owned[8] = NULL;
    owned[6] = NULL;
    Rc = elmc_new_int(&owned[10], 12);
    CHECK_RC(Rc);
    Rc = elmc_cmd1(&owned[11], ELMC_PEBBLE_CMD_GET_TIMEZONE, elmc_as_int(owned[10]));
    CHECK_RC(Rc);
    owned[10] = NULL;
    Rc = elmc_list_cons(&owned[12], owned[11], owned[9]);
    CHECK_RC(Rc);
    owned[11] = NULL;
    owned[9] = NULL;
    Rc = elmc_new_int(&owned[13], 11);
    CHECK_RC(Rc);
    Rc = elmc_cmd1(&owned[14], ELMC_PEBBLE_CMD_GET_TIMEZONE_IS_SET, elmc_as_int(owned[13]));
    CHECK_RC(Rc);
    owned[13] = NULL;
    Rc = elmc_list_cons(&owned[15], owned[14], owned[12]);
    CHECK_RC(Rc);
    owned[14] = NULL;
    owned[12] = NULL;
    Rc = elmc_new_int(&owned[16], 10);
    CHECK_RC(Rc);
    Rc = elmc_cmd1(&owned[17], ELMC_PEBBLE_CMD_GET_CLOCK_STYLE_24H, elmc_as_int(owned[16]));
    CHECK_RC(Rc);
    owned[16] = NULL;
    Rc = elmc_list_cons(&owned[18], owned[17], owned[15]);
    CHECK_RC(Rc);
    owned[17] = NULL;
    owned[15] = NULL;
    Rc = elmc_new_int(&owned[19], 9);
    CHECK_RC(Rc);
    Rc = elmc_cmd1(&owned[20], ELMC_PEBBLE_CMD_GET_CURRENT_TIME_STRING, elmc_as_int(owned[19]));
    CHECK_RC(Rc);
    owned[19] = NULL;
    Rc = elmc_list_cons(&owned[21], owned[20], owned[18]);
    CHECK_RC(Rc);
    owned[20] = NULL;
    owned[18] = NULL;
    owned[22] = elmc_cmd_batch(owned[21]);
    owned[21] = NULL;
    *out = owned[22];
    owned[22] = NULL;
    owned[22] = NULL;
  CATCH_END;

  elmc_release_array_lifo(owned, 23);
  return Rc;
}

RC elmc_fn_Main_init(ElmcValue **out, ElmcValue *launchContext) {
  /* Ownership policy: borrow_arg, borrow_result, direct_call_abi */
  RC Rc = RC_SUCCESS;
  ElmcValue *owned[14] = {0};
  CATCH_BEGIN
    /* plan block 0 */
    owned[0] = launchContext;
    owned[1] = elmc_record_get_index(owned[0], 0 /* reason */);
    owned[2] = elmc_fn_Pebble_Platform_launchReasonToInt(owned[1]);
    owned[1] = NULL;
    owned[3] = elmc_maybe_nothing();
    owned[5] = elmc_retain(owned[2]);
    const char *rec_names_4[2] = { "value", "temperature" };
    ElmcValue *rec_values_4[2] = { owned[5], owned[3] };
    Rc = elmc_record_new_static_take(&owned[4], 2, rec_names_4, rec_values_4);
    CHECK_RC(Rc);
    owned[5] = NULL;
    owned[3] = NULL;
    owned[6] = elmc_list_nil();
    Rc = elmc_fn_Main_requestSystemInfo(&owned[7]);
    CHECK_RC(Rc);
    Rc = elmc_list_cons(&owned[8], owned[7], owned[6]);
    CHECK_RC(Rc);
    owned[7] = NULL;
    owned[6] = NULL;
    Rc = elmc_new_int(&owned[9], 2);
    CHECK_RC(Rc);
    Rc = elmc_fn_Main_requestWeather(&owned[10], owned[9]);
    CHECK_RC(Rc);
    owned[9] = NULL;
    Rc = elmc_list_cons(&owned[11], owned[10], owned[8]);
    CHECK_RC(Rc);
    owned[10] = NULL;
    owned[8] = NULL;
    owned[12] = elmc_cmd_batch(owned[11]);
    owned[11] = NULL;
    Rc = elmc_tuple2(&owned[13], owned[4], owned[12]);
    CHECK_RC(Rc);
    owned[4] = NULL;
    owned[12] = NULL;
    *out = owned[13];
    owned[13] = NULL;
    owned[13] = NULL;
    elmc_release(owned[2]);
    owned[2] = NULL;
    owned[2] = NULL;
    owned[0] = NULL;
  CATCH_END;

  elmc_release_array_lifo(owned, 14);
  return Rc;
}

RC elmc_fn_Main_update(ElmcValue **out, ElmcValue *msg, ElmcValue *model) {
  /* Ownership policy: borrow_arg, borrow_result, direct_call_abi */
  RC Rc = RC_SUCCESS;
  ElmcValue *owned[23] = {0};
  CATCH_BEGIN
    /* plan block 0 */
    owned[0] = msg;
    owned[1] = model;
    if (elmc_union_tag_matches(owned[0], 3)) goto elmc_plan_block_2; else if (elmc_union_tag_matches(owned[0], 4)) goto elmc_plan_block_4; else if (elmc_union_tag_matches(owned[0], 5)) goto elmc_plan_block_6; else if (elmc_union_tag_matches(owned[0], 6)) goto elmc_plan_block_8; else if (elmc_union_tag_matches(owned[0], 7)) goto elmc_plan_block_10; else goto elmc_plan_block_12;
    elmc_plan_block_2:
    owned[3] = elmc_union_payload(owned[0]);
    owned[4] = elmc_retain(owned[3]);
    owned[3] = NULL;
    owned[6] = msg;
    owned[7] = model;
    Rc = elmc_fn_Main_handlePlatformMsg(&owned[5], owned[6], owned[7]);
    CHECK_RC(Rc);
    owned[2] = elmc_retain(owned[5]);
    owned[5] = NULL;
    goto elmc_plan_block_14;
    elmc_plan_block_4:
    owned[9] = msg;
    owned[10] = model;
    Rc = elmc_fn_Main_handlePlatformMsg(&owned[8], owned[9], owned[10]);
    CHECK_RC(Rc);
    owned[2] = elmc_retain(owned[8]);
    owned[8] = NULL;
    goto elmc_plan_block_14;
    elmc_plan_block_6:
    owned[12] = msg;
    owned[13] = model;
    Rc = elmc_fn_Main_handlePlatformMsg(&owned[11], owned[12], owned[13]);
    CHECK_RC(Rc);
    owned[2] = elmc_retain(owned[11]);
    owned[11] = NULL;
    goto elmc_plan_block_14;
    elmc_plan_block_8:
    owned[15] = msg;
    owned[16] = model;
    Rc = elmc_fn_Main_handlePlatformMsg(&owned[14], owned[15], owned[16]);
    CHECK_RC(Rc);
    owned[2] = elmc_retain(owned[14]);
    owned[14] = NULL;
    goto elmc_plan_block_14;
    elmc_plan_block_10:
    owned[18] = msg;
    owned[19] = model;
    Rc = elmc_fn_Main_handlePlatformMsg(&owned[17], owned[18], owned[19]);
    CHECK_RC(Rc);
    owned[2] = elmc_retain(owned[17]);
    owned[17] = NULL;
    goto elmc_plan_block_14;
    elmc_plan_block_12:
    owned[21] = msg;
    owned[22] = model;
    Rc = elmc_fn_Main_handleAppMsg(&owned[20], owned[21], owned[22]);
    CHECK_RC(Rc);
    owned[2] = elmc_retain(owned[20]);
    owned[20] = NULL;
    goto elmc_plan_block_14;
    elmc_plan_block_14:
    *out = owned[2];
    owned[2] = NULL;
    owned[2] = NULL;
    owned[0] = NULL;
    owned[1] = NULL;
    owned[6] = NULL;
    owned[7] = NULL;
    owned[9] = NULL;
    owned[10] = NULL;
    owned[12] = NULL;
    owned[13] = NULL;
    owned[15] = NULL;
    owned[16] = NULL;
    owned[18] = NULL;
    owned[19] = NULL;
    owned[21] = NULL;
    owned[22] = NULL;
  CATCH_END;

  elmc_release_array_lifo(owned, 23);
  return Rc;
}

static RC elmc_fn_Main_handleAppMsg(ElmcValue **out, ElmcValue *msg, ElmcValue *model) {
  /* Ownership policy: borrow_arg, borrow_result, direct_call_abi */
  RC Rc = RC_SUCCESS;
  ElmcValue *owned[56] = {0};
  CATCH_BEGIN
    /* plan block 0 */
    owned[0] = msg;
    owned[1] = model;
    if (elmc_union_tag_matches(owned[0], 1)) goto elmc_plan_block_2; else if (elmc_union_tag_matches(owned[0], 2)) goto elmc_plan_block_4; else if (elmc_union_tag_matches(owned[0], 8)) goto elmc_plan_block_6; else if (elmc_union_tag_matches(owned[0], 9)) goto elmc_plan_block_8; else if (elmc_union_tag_matches(owned[0], 10)) goto elmc_plan_block_10; else if (elmc_union_tag_matches(owned[0], 11)) goto elmc_plan_block_12; else if (elmc_union_tag_matches(owned[0], 12)) goto elmc_plan_block_14; else if (elmc_union_tag_matches(owned[0], 13)) goto elmc_plan_block_16; else if (elmc_union_tag_matches(owned[0], 14)) goto elmc_plan_block_18; else if (elmc_union_tag_matches(owned[0], 15)) goto elmc_plan_block_20; else goto elmc_plan_block_22;
    elmc_plan_block_2:
    owned[4] = model;
    Rc = elmc_fn_Main_counterOf(&owned[3], owned[4]);
    CHECK_RC(Rc);
    Rc = elmc_new_int(&owned[5], elmc_as_int(owned[3]) + 1);
    CHECK_RC(Rc);
    Rc = elmc_fn_Main_temperatureOf(&owned[6], owned[4]);
    CHECK_RC(Rc);
    const char *rec_names_7[2] = { "value", "temperature" };
    ElmcValue *rec_values_7[2] = { owned[5], owned[6] };
    Rc = elmc_record_new_static_take(&owned[7], 2, rec_names_7, rec_values_7);
    CHECK_RC(Rc);
    owned[5] = NULL;
    owned[6] = NULL;
    Rc = elmc_cmd0(&owned[8], ELMC_PEBBLE_CMD_NONE);
    CHECK_RC(Rc);
    Rc = elmc_tuple2(&owned[9], owned[7], owned[8]);
    CHECK_RC(Rc);
    owned[7] = NULL;
    owned[8] = NULL;
    owned[2] = elmc_retain(owned[9]);
    owned[9] = NULL;
    goto elmc_plan_block_24;
    elmc_plan_block_4:
    owned[11] = model;
    Rc = elmc_fn_Main_counterOf(&owned[10], owned[11]);
    CHECK_RC(Rc);
    Rc = elmc_new_int(&owned[12], elmc_as_int(owned[10]) - 1);
    CHECK_RC(Rc);
    Rc = elmc_fn_Main_temperatureOf(&owned[13], owned[11]);
    CHECK_RC(Rc);
    const char *rec_names_14[2] = { "value", "temperature" };
    ElmcValue *rec_values_14[2] = { owned[12], owned[13] };
    Rc = elmc_record_new_static_take(&owned[14], 2, rec_names_14, rec_values_14);
    CHECK_RC(Rc);
    owned[12] = NULL;
    owned[13] = NULL;
    Rc = elmc_cmd0(&owned[15], ELMC_PEBBLE_CMD_NONE);
    CHECK_RC(Rc);
    Rc = elmc_tuple2(&owned[16], owned[14], owned[15]);
    CHECK_RC(Rc);
    owned[14] = NULL;
    owned[15] = NULL;
    owned[2] = elmc_retain(owned[16]);
    owned[16] = NULL;
    goto elmc_plan_block_24;
    elmc_plan_block_6:
    owned[17] = elmc_union_payload(owned[0]);
    owned[18] = elmc_retain(owned[17]);
    owned[17] = NULL;
    owned[20] = model;
    Rc = elmc_fn_Main_counterOf(&owned[19], owned[20]);
    CHECK_RC(Rc);
    owned[21] = elmc_retain(owned[18]);
    Rc = elmc_maybe_just_own(&owned[22], owned[21]);
    CHECK_RC(Rc);
    owned[21] = NULL;
    const char *rec_names_23[2] = { "value", "temperature" };
    ElmcValue *rec_values_23[2] = { owned[19], owned[22] };
    Rc = elmc_record_new_static_take(&owned[23], 2, rec_names_23, rec_values_23);
    CHECK_RC(Rc);
    owned[19] = NULL;
    owned[22] = NULL;
    Rc = elmc_cmd0(&owned[24], ELMC_PEBBLE_CMD_NONE);
    CHECK_RC(Rc);
    Rc = elmc_tuple2(&owned[25], owned[23], owned[24]);
    CHECK_RC(Rc);
    owned[23] = NULL;
    owned[24] = NULL;
    owned[2] = elmc_retain(owned[25]);
    owned[25] = NULL;
    goto elmc_plan_block_24;
    elmc_plan_block_8:
    owned[26] = elmc_union_payload(owned[0]);
    owned[27] = elmc_retain(owned[26]);
    owned[26] = NULL;
    Rc = elmc_cmd0(&owned[28], ELMC_PEBBLE_CMD_NONE);
    CHECK_RC(Rc);
    Rc = elmc_tuple2(&owned[29], owned[20], owned[28]);
    CHECK_RC(Rc);
    owned[28] = NULL;
    owned[2] = elmc_retain(owned[29]);
    owned[29] = NULL;
    goto elmc_plan_block_24;
    elmc_plan_block_10:
    owned[30] = elmc_union_payload(owned[0]);
    owned[31] = elmc_retain(owned[30]);
    owned[30] = NULL;
    Rc = elmc_cmd0(&owned[32], ELMC_PEBBLE_CMD_NONE);
    CHECK_RC(Rc);
    Rc = elmc_tuple2(&owned[33], owned[20], owned[32]);
    CHECK_RC(Rc);
    owned[32] = NULL;
    owned[2] = elmc_retain(owned[33]);
    owned[33] = NULL;
    goto elmc_plan_block_24;
    elmc_plan_block_12:
    owned[34] = elmc_union_payload(owned[0]);
    owned[35] = elmc_retain(owned[34]);
    owned[34] = NULL;
    Rc = elmc_cmd0(&owned[36], ELMC_PEBBLE_CMD_NONE);
    CHECK_RC(Rc);
    Rc = elmc_tuple2(&owned[37], owned[20], owned[36]);
    CHECK_RC(Rc);
    owned[36] = NULL;
    owned[2] = elmc_retain(owned[37]);
    owned[37] = NULL;
    goto elmc_plan_block_24;
    elmc_plan_block_14:
    owned[38] = elmc_union_payload(owned[0]);
    owned[39] = elmc_retain(owned[38]);
    owned[38] = NULL;
    Rc = elmc_cmd0(&owned[40], ELMC_PEBBLE_CMD_NONE);
    CHECK_RC(Rc);
    Rc = elmc_tuple2(&owned[41], owned[20], owned[40]);
    CHECK_RC(Rc);
    owned[40] = NULL;
    owned[2] = elmc_retain(owned[41]);
    owned[41] = NULL;
    goto elmc_plan_block_24;
    elmc_plan_block_16:
    owned[42] = elmc_union_payload(owned[0]);
    owned[43] = elmc_retain(owned[42]);
    owned[42] = NULL;
    Rc = elmc_cmd0(&owned[44], ELMC_PEBBLE_CMD_NONE);
    CHECK_RC(Rc);
    Rc = elmc_tuple2(&owned[45], owned[20], owned[44]);
    CHECK_RC(Rc);
    owned[44] = NULL;
    owned[2] = elmc_retain(owned[45]);
    owned[45] = NULL;
    goto elmc_plan_block_24;
    elmc_plan_block_18:
    owned[46] = elmc_union_payload(owned[0]);
    owned[47] = elmc_retain(owned[46]);
    owned[46] = NULL;
    Rc = elmc_cmd0(&owned[48], ELMC_PEBBLE_CMD_NONE);
    CHECK_RC(Rc);
    Rc = elmc_tuple2(&owned[49], owned[20], owned[48]);
    CHECK_RC(Rc);
    owned[48] = NULL;
    owned[2] = elmc_retain(owned[49]);
    owned[49] = NULL;
    goto elmc_plan_block_24;
    elmc_plan_block_20:
    owned[50] = elmc_union_payload(owned[0]);
    owned[51] = elmc_retain(owned[50]);
    owned[50] = NULL;
    Rc = elmc_cmd0(&owned[52], ELMC_PEBBLE_CMD_NONE);
    CHECK_RC(Rc);
    Rc = elmc_tuple2(&owned[53], owned[20], owned[52]);
    CHECK_RC(Rc);
    owned[52] = NULL;
    owned[2] = elmc_retain(owned[53]);
    owned[53] = NULL;
    goto elmc_plan_block_24;
    elmc_plan_block_22:
    Rc = elmc_cmd0(&owned[54], ELMC_PEBBLE_CMD_NONE);
    CHECK_RC(Rc);
    Rc = elmc_tuple2(&owned[55], owned[20], owned[54]);
    CHECK_RC(Rc);
    owned[54] = NULL;
    owned[2] = elmc_retain(owned[55]);
    owned[55] = NULL;
    goto elmc_plan_block_24;
    elmc_plan_block_24:
    *out = owned[2];
    owned[2] = NULL;
    owned[2] = NULL;
    owned[0] = NULL;
    owned[1] = NULL;
    owned[4] = NULL;
    owned[11] = NULL;
    owned[20] = NULL;
  CATCH_END;

  elmc_release_array_lifo(owned, 56);
  return Rc;
}

static RC elmc_fn_Main_handlePlatformMsg(ElmcValue **out, ElmcValue *msg, ElmcValue *model) {
  /* Ownership policy: borrow_arg, borrow_result, direct_call_abi */
  RC Rc = RC_SUCCESS;
  ElmcValue *owned[48] = {0};
  CATCH_BEGIN
    /* plan block 0 */
    owned[0] = msg;
    owned[1] = model;
    if (elmc_union_tag_matches(owned[0], 3)) goto elmc_plan_block_2; else if (elmc_union_tag_matches(owned[0], 4)) goto elmc_plan_block_4; else if (elmc_union_tag_matches(owned[0], 5)) goto elmc_plan_block_6; else if (elmc_union_tag_matches(owned[0], 6)) goto elmc_plan_block_8; else if (elmc_union_tag_matches(owned[0], 7)) goto elmc_plan_block_10; else goto elmc_plan_block_12;
    elmc_plan_block_2:
    owned[3] = elmc_union_payload(owned[0]);
    owned[4] = elmc_retain(owned[3]);
    owned[3] = NULL;
    owned[6] = model;
    Rc = elmc_fn_Main_counterOf(&owned[5], owned[6]);
    CHECK_RC(Rc);
    Rc = elmc_fn_Main_advanced(&owned[7], elmc_as_int(owned[5]));
    CHECK_RC(Rc);
    Rc = elmc_fn_Main_temperatureOf(&owned[8], owned[6]);
    CHECK_RC(Rc);
    owned[10] = elmc_retain(owned[7]);
    const char *rec_names_9[2] = { "value", "temperature" };
    ElmcValue *rec_values_9[2] = { owned[10], owned[8] };
    Rc = elmc_record_new_static_take(&owned[9], 2, rec_names_9, rec_values_9);
    CHECK_RC(Rc);
    owned[10] = NULL;
    owned[8] = NULL;
    Rc = elmc_new_int(&owned[11], 1000);
    CHECK_RC(Rc);
    Rc = elmc_cmd1(&owned[12], ELMC_PEBBLE_CMD_TIMER_AFTER_MS, elmc_as_int(owned[11]));
    CHECK_RC(Rc);
    owned[11] = NULL;
    Rc = elmc_tuple2(&owned[13], owned[9], owned[12]);
    CHECK_RC(Rc);
    owned[9] = NULL;
    owned[12] = NULL;
    owned[2] = elmc_retain(owned[13]);
    owned[13] = NULL;
    goto elmc_plan_block_14;
    elmc_plan_block_4:
    owned[15] = model;
    Rc = elmc_fn_Main_counterOf(&owned[14], owned[15]);
    CHECK_RC(Rc);
    Rc = elmc_new_int(&owned[16], elmc_as_int(owned[14]) + 1);
    CHECK_RC(Rc);
    owned[17] = elmc_retain(owned[16]);
    Rc = elmc_fn_Main_temperatureOf(&owned[18], owned[15]);
    CHECK_RC(Rc);
    const char *rec_names_19[2] = { "value", "temperature" };
    ElmcValue *rec_values_19[2] = { owned[17], owned[18] };
    Rc = elmc_record_new_static_take(&owned[19], 2, rec_names_19, rec_values_19);
    CHECK_RC(Rc);
    owned[17] = NULL;
    owned[18] = NULL;
    Rc = elmc_new_int(&owned[20], 1);
    CHECK_RC(Rc);
    Rc = elmc_cmd2(&owned[21], ELMC_PEBBLE_CMD_STORAGE_WRITE_INT, elmc_as_int(owned[20]), elmc_as_int(owned[16]));
    CHECK_RC(Rc);
    owned[20] = NULL;
    owned[16] = NULL;
    Rc = elmc_tuple2(&owned[22], owned[19], owned[21]);
    CHECK_RC(Rc);
    owned[19] = NULL;
    owned[21] = NULL;
    owned[2] = elmc_retain(owned[22]);
    owned[22] = NULL;
    goto elmc_plan_block_14;
    elmc_plan_block_6:
    owned[23] = elmc_list_nil();
    Rc = elmc_fn_Main_requestSystemInfo(&owned[24]);
    CHECK_RC(Rc);
    Rc = elmc_list_cons(&owned[25], owned[24], owned[23]);
    CHECK_RC(Rc);
    owned[24] = NULL;
    owned[23] = NULL;
    Rc = elmc_new_int(&owned[26], 2);
    CHECK_RC(Rc);
    Rc = elmc_fn_Main_requestWeather(&owned[27], owned[26]);
    CHECK_RC(Rc);
    owned[26] = NULL;
    Rc = elmc_list_cons(&owned[28], owned[27], owned[25]);
    CHECK_RC(Rc);
    owned[27] = NULL;
    owned[25] = NULL;
    owned[29] = elmc_cmd_batch(owned[28]);
    owned[28] = NULL;
    Rc = elmc_tuple2(&owned[30], owned[15], owned[29]);
    CHECK_RC(Rc);
    owned[29] = NULL;
    owned[2] = elmc_retain(owned[30]);
    owned[30] = NULL;
    goto elmc_plan_block_14;
    elmc_plan_block_8:
    owned[32] = model;
    Rc = elmc_fn_Main_counterOf(&owned[31], owned[32]);
    CHECK_RC(Rc);
    Rc = elmc_new_int(&owned[33], elmc_as_int(owned[31]) - 1);
    CHECK_RC(Rc);
    Rc = elmc_fn_Main_temperatureOf(&owned[34], owned[32]);
    CHECK_RC(Rc);
    const char *rec_names_35[2] = { "value", "temperature" };
    ElmcValue *rec_values_35[2] = { owned[33], owned[34] };
    Rc = elmc_record_new_static_take(&owned[35], 2, rec_names_35, rec_values_35);
    CHECK_RC(Rc);
    owned[33] = NULL;
    owned[34] = NULL;
    Rc = elmc_new_int(&owned[36], 1);
    CHECK_RC(Rc);
    Rc = elmc_cmd1(&owned[37], ELMC_PEBBLE_CMD_STORAGE_DELETE, elmc_as_int(owned[36]));
    CHECK_RC(Rc);
    owned[36] = NULL;
    Rc = elmc_tuple2(&owned[38], owned[35], owned[37]);
    CHECK_RC(Rc);
    owned[35] = NULL;
    owned[37] = NULL;
    owned[2] = elmc_retain(owned[38]);
    owned[38] = NULL;
    goto elmc_plan_block_14;
    elmc_plan_block_10:
    owned[40] = model;
    Rc = elmc_fn_Main_counterOf(&owned[39], owned[40]);
    CHECK_RC(Rc);
    Rc = elmc_new_int(&owned[41], elmc_as_int(owned[39]) + 1);
    CHECK_RC(Rc);
    Rc = elmc_fn_Main_temperatureOf(&owned[42], owned[40]);
    CHECK_RC(Rc);
    const char *rec_names_43[2] = { "value", "temperature" };
    ElmcValue *rec_values_43[2] = { owned[41], owned[42] };
    Rc = elmc_record_new_static_take(&owned[43], 2, rec_names_43, rec_values_43);
    CHECK_RC(Rc);
    owned[41] = NULL;
    owned[42] = NULL;
    Rc = elmc_cmd0(&owned[44], ELMC_PEBBLE_CMD_NONE);
    CHECK_RC(Rc);
    Rc = elmc_tuple2(&owned[45], owned[43], owned[44]);
    CHECK_RC(Rc);
    owned[43] = NULL;
    owned[44] = NULL;
    owned[2] = elmc_retain(owned[45]);
    owned[45] = NULL;
    goto elmc_plan_block_14;
    elmc_plan_block_12:
    Rc = elmc_cmd0(&owned[46], ELMC_PEBBLE_CMD_NONE);
    CHECK_RC(Rc);
    Rc = elmc_tuple2(&owned[47], owned[40], owned[46]);
    CHECK_RC(Rc);
    owned[46] = NULL;
    owned[2] = elmc_retain(owned[47]);
    owned[47] = NULL;
    goto elmc_plan_block_14;
    elmc_plan_block_14:
    *out = owned[2];
    owned[2] = NULL;
    owned[2] = NULL;
    owned[0] = NULL;
    owned[1] = NULL;
    owned[6] = NULL;
    owned[15] = NULL;
    owned[32] = NULL;
    owned[40] = NULL;
  CATCH_END;

  elmc_release_array_lifo(owned, 48);
  return Rc;
}

RC elmc_fn_Main_subscriptions(ElmcValue **out, ElmcValue *_unused_0) {
  /* Ownership policy: borrow_arg, borrow_result, direct_call_abi */
  RC Rc = RC_SUCCESS;
  ElmcValue *owned[24] = {0};
  CATCH_BEGIN
    /* plan block 0 */
    owned[0] = _unused_0;
    owned[1] = elmc_list_nil();
    Rc = elmc_new_int(&owned[2], 7);
    CHECK_RC(Rc);
    Rc = elmc_sub1(&owned[3], ELMC_SUBSCRIPTION_ACCEL_TAP, elmc_as_int(owned[2]));
    CHECK_RC(Rc);
    Rc = elmc_list_cons(&owned[4], owned[3], owned[1]);
    CHECK_RC(Rc);
    owned[3] = NULL;
    owned[1] = NULL;
    Rc = elmc_new_int(&owned[5], ELMC_BUTTON_DOWN);
    CHECK_RC(Rc);
    Rc = elmc_new_int(&owned[6], ELMC_BUTTON_EVENT_PRESSED);
    CHECK_RC(Rc);
    Rc = elmc_new_int(&owned[7], 6);
    CHECK_RC(Rc);
    Rc = elmc_sub3(&owned[8], ELMC_SUBSCRIPTION_BUTTON_RAW, elmc_as_int(owned[5]), elmc_as_int(owned[6]), elmc_as_int(owned[7]));
    CHECK_RC(Rc);
    Rc = elmc_list_cons(&owned[9], owned[8], owned[4]);
    CHECK_RC(Rc);
    owned[8] = NULL;
    owned[4] = NULL;
    Rc = elmc_new_int(&owned[10], ELMC_BUTTON_SELECT);
    CHECK_RC(Rc);
    Rc = elmc_new_int(&owned[11], ELMC_BUTTON_EVENT_PRESSED);
    CHECK_RC(Rc);
    Rc = elmc_new_int(&owned[12], 5);
    CHECK_RC(Rc);
    Rc = elmc_sub3(&owned[13], ELMC_SUBSCRIPTION_BUTTON_RAW, elmc_as_int(owned[10]), elmc_as_int(owned[11]), elmc_as_int(owned[12]));
    CHECK_RC(Rc);
    Rc = elmc_list_cons(&owned[14], owned[13], owned[9]);
    CHECK_RC(Rc);
    owned[13] = NULL;
    owned[9] = NULL;
    Rc = elmc_new_int(&owned[15], ELMC_BUTTON_UP);
    CHECK_RC(Rc);
    Rc = elmc_new_int(&owned[16], ELMC_BUTTON_EVENT_PRESSED);
    CHECK_RC(Rc);
    Rc = elmc_new_int(&owned[17], 4);
    CHECK_RC(Rc);
    Rc = elmc_sub3(&owned[18], ELMC_SUBSCRIPTION_BUTTON_RAW, elmc_as_int(owned[15]), elmc_as_int(owned[16]), elmc_as_int(owned[17]));
    CHECK_RC(Rc);
    Rc = elmc_list_cons(&owned[19], owned[18], owned[14]);
    CHECK_RC(Rc);
    owned[18] = NULL;
    owned[14] = NULL;
    Rc = elmc_new_int(&owned[20], 3);
    CHECK_RC(Rc);
    Rc = elmc_sub1(&owned[21], ELMC_SUBSCRIPTION_SECOND_CHANGE, elmc_as_int(owned[20]));
    CHECK_RC(Rc);
    Rc = elmc_list_cons(&owned[22], owned[21], owned[19]);
    CHECK_RC(Rc);
    owned[21] = NULL;
    owned[19] = NULL;
    owned[23] = elmc_sub_batch(owned[22]);
    owned[22] = NULL;
    *out = owned[23];
    owned[23] = NULL;
    owned[23] = NULL;
    elmc_release(owned[2]);
    owned[2] = NULL;
    owned[2] = NULL;
    elmc_release(owned[5]);
    owned[5] = NULL;
    owned[5] = NULL;
    elmc_release(owned[6]);
    owned[6] = NULL;
    owned[6] = NULL;
    elmc_release(owned[7]);
    owned[7] = NULL;
    owned[7] = NULL;
    elmc_release(owned[10]);
    owned[10] = NULL;
    owned[10] = NULL;
    elmc_release(owned[11]);
    owned[11] = NULL;
    owned[11] = NULL;
    elmc_release(owned[12]);
    owned[12] = NULL;
    owned[12] = NULL;
    elmc_release(owned[15]);
    owned[15] = NULL;
    owned[15] = NULL;
    elmc_release(owned[16]);
    owned[16] = NULL;
    owned[16] = NULL;
    elmc_release(owned[17]);
    owned[17] = NULL;
    owned[17] = NULL;
    elmc_release(owned[20]);
    owned[20] = NULL;
    owned[20] = NULL;
    owned[0] = NULL;
  CATCH_END;

  elmc_release_array_lifo(owned, 24);
  return Rc;
}

RC elmc_fn_Main_view(ElmcValue **out, ElmcValue *model) {
  /* Ownership policy: borrow_arg, borrow_result, direct_call_abi */
  // #region agent log
  elmc_agent_generated_probe(0xED998100);
  // #endregion

  RC Rc = RC_SUCCESS;
  ElmcValue *owned[166] = {0};
  CATCH_BEGIN
    /* plan block 0 */
    owned[0] = model;
    Rc = elmc_new_int(&owned[1], ELMC_UI_NODE_WINDOW_STACK);
    CHECK_RC(Rc);
    owned[2] = elmc_list_nil();
    Rc = elmc_new_int(&owned[3], ELMC_UI_NODE_WINDOW);
    CHECK_RC(Rc);
    Rc = elmc_new_int(&owned[4], 1);
    CHECK_RC(Rc);
    owned[5] = elmc_list_nil();
    Rc = elmc_new_int(&owned[6], ELMC_UI_NODE_CANVAS_LAYER);
    CHECK_RC(Rc);
    Rc = elmc_new_int(&owned[7], 1);
    CHECK_RC(Rc);
    owned[8] = elmc_list_nil();
    Rc = elmc_fn_Main_counterDraw(&owned[9], owned[0]);
    CHECK_RC(Rc);
    Rc = elmc_list_cons(&owned[10], owned[9], owned[8]);
    CHECK_RC(Rc);
    owned[9] = NULL;
    owned[8] = NULL;
    Rc = elmc_fn_Main_statusDraw(&owned[11], owned[0]);
    CHECK_RC(Rc);
    Rc = elmc_list_cons(&owned[12], owned[11], owned[10]);
    CHECK_RC(Rc);
    owned[11] = NULL;
    owned[10] = NULL;
    Rc = elmc_new_int(&owned[13], 72);
    CHECK_RC(Rc);
    Rc = elmc_new_int(&owned[14], 84);
    CHECK_RC(Rc);
    Rc = elmc_new_int(&owned[15], ELMC_COLOR_BLACK);
    CHECK_RC(Rc);
    owned[16] = elmc_render_cmd6(ELMC_RENDER_OP_PIXEL, elmc_as_int(owned[13]), elmc_as_int(owned[14]), elmc_as_int(owned[15]), 0, 0, 0);
    if (!owned[16]) {
      Rc = RC_ERR_OUT_OF_MEMORY;
      CHECK_RC(Rc);
    }
    Rc = elmc_list_cons(&owned[17], owned[16], owned[12]);
    CHECK_RC(Rc);
    owned[16] = NULL;
    owned[12] = NULL;
    Rc = elmc_new_int(&owned[18], 0);
    CHECK_RC(Rc);
    Rc = elmc_new_int(&owned[19], 84);
    CHECK_RC(Rc);
    Rc = elmc_new_int(&owned[20], 143);
    CHECK_RC(Rc);
    Rc = elmc_new_int(&owned[21], 84);
    CHECK_RC(Rc);
    Rc = elmc_new_int(&owned[22], ELMC_COLOR_BLACK);
    CHECK_RC(Rc);
    owned[23] = elmc_render_cmd6(ELMC_RENDER_OP_LINE, elmc_as_int(owned[18]), elmc_as_int(owned[19]), elmc_as_int(owned[20]), elmc_as_int(owned[21]), elmc_as_int(owned[22]), 0);
    if (!owned[23]) {
      Rc = RC_ERR_OUT_OF_MEMORY;
      CHECK_RC(Rc);
    }
    Rc = elmc_list_cons(&owned[24], owned[23], owned[17]);
    CHECK_RC(Rc);
    owned[23] = NULL;
    owned[17] = NULL;
    Rc = elmc_new_int(&owned[25], ELMC_RENDER_OP_CONTEXT_GROUP);
    CHECK_RC(Rc);
    owned[26] = elmc_list_nil();
    Rc = elmc_new_int(&owned[27], ELMC_CONTEXT_TEXT_COLOR);
    CHECK_RC(Rc);
    Rc = elmc_new_int(&owned[28], ELMC_COLOR_BLACK);
    CHECK_RC(Rc);
    Rc = elmc_tuple2(&owned[29], owned[27], owned[28]);
    CHECK_RC(Rc);
    owned[27] = NULL;
    owned[28] = NULL;
    Rc = elmc_list_cons(&owned[30], owned[29], owned[26]);
    CHECK_RC(Rc);
    owned[29] = NULL;
    owned[26] = NULL;
    Rc = elmc_new_int(&owned[31], ELMC_CONTEXT_FILL_COLOR);
    CHECK_RC(Rc);
    Rc = elmc_new_int(&owned[32], ELMC_COLOR_BLACK);
    CHECK_RC(Rc);
    Rc = elmc_tuple2(&owned[33], owned[31], owned[32]);
    CHECK_RC(Rc);
    owned[31] = NULL;
    owned[32] = NULL;
    Rc = elmc_list_cons(&owned[34], owned[33], owned[30]);
    CHECK_RC(Rc);
    owned[33] = NULL;
    owned[30] = NULL;
    Rc = elmc_new_int(&owned[35], ELMC_CONTEXT_STROKE_COLOR);
    CHECK_RC(Rc);
    Rc = elmc_new_int(&owned[36], ELMC_COLOR_BLACK);
    CHECK_RC(Rc);
    Rc = elmc_tuple2(&owned[37], owned[35], owned[36]);
    CHECK_RC(Rc);
    owned[35] = NULL;
    owned[36] = NULL;
    Rc = elmc_list_cons(&owned[38], owned[37], owned[34]);
    CHECK_RC(Rc);
    owned[37] = NULL;
    owned[34] = NULL;
    Rc = elmc_new_int(&owned[39], ELMC_CONTEXT_ANTIALIASED);
    CHECK_RC(Rc);
    Rc = elmc_new_int(&owned[40], 1);
    CHECK_RC(Rc);
    Rc = elmc_tuple2(&owned[41], owned[39], owned[40]);
    CHECK_RC(Rc);
    owned[39] = NULL;
    owned[40] = NULL;
    Rc = elmc_list_cons(&owned[42], owned[41], owned[38]);
    CHECK_RC(Rc);
    owned[41] = NULL;
    owned[38] = NULL;
    Rc = elmc_new_int(&owned[43], ELMC_CONTEXT_STROKE_WIDTH);
    CHECK_RC(Rc);
    Rc = elmc_new_int(&owned[44], 3);
    CHECK_RC(Rc);
    Rc = elmc_tuple2(&owned[45], owned[43], owned[44]);
    CHECK_RC(Rc);
    owned[43] = NULL;
    owned[44] = NULL;
    Rc = elmc_list_cons(&owned[46], owned[45], owned[42]);
    CHECK_RC(Rc);
    owned[45] = NULL;
    owned[42] = NULL;
    owned[47] = elmc_list_nil();
    Rc = elmc_new_int(&owned[48], ELMC_RENDER_OP_PATH_OUTLINE_OPEN);
    CHECK_RC(Rc);
    owned[49] = elmc_list_nil();
    Rc = elmc_new_int(&owned[50], 24);
    CHECK_RC(Rc);
    Rc = elmc_new_int(&owned[51], 6);
    CHECK_RC(Rc);
    const char *rec_names_52[2] = { "x", "y" };
    ElmcValue *rec_values_52[2] = { owned[50], owned[51] };
    Rc = elmc_record_new_static_take(&owned[52], 2, rec_names_52, rec_values_52);
    CHECK_RC(Rc);
    owned[50] = NULL;
    owned[51] = NULL;
    Rc = elmc_list_cons(&owned[53], owned[52], owned[49]);
    CHECK_RC(Rc);
    owned[52] = NULL;
    owned[49] = NULL;
    Rc = elmc_new_int(&owned[54], 16);
    CHECK_RC(Rc);
    Rc = elmc_new_int(&owned[55], 2);
    CHECK_RC(Rc);
    const char *rec_names_56[2] = { "x", "y" };
    ElmcValue *rec_values_56[2] = { owned[54], owned[55] };
    Rc = elmc_record_new_static_take(&owned[56], 2, rec_names_56, rec_values_56);
    CHECK_RC(Rc);
    owned[54] = NULL;
    owned[55] = NULL;
    Rc = elmc_list_cons(&owned[57], owned[56], owned[53]);
    CHECK_RC(Rc);
    owned[56] = NULL;
    owned[53] = NULL;
    Rc = elmc_new_int(&owned[58], 8);
    CHECK_RC(Rc);
    Rc = elmc_new_int(&owned[59], 4);
    CHECK_RC(Rc);
    const char *rec_names_60[2] = { "x", "y" };
    ElmcValue *rec_values_60[2] = { owned[58], owned[59] };
    Rc = elmc_record_new_static_take(&owned[60], 2, rec_names_60, rec_values_60);
    CHECK_RC(Rc);
    owned[58] = NULL;
    owned[59] = NULL;
    Rc = elmc_list_cons(&owned[61], owned[60], owned[57]);
    CHECK_RC(Rc);
    owned[60] = NULL;
    owned[57] = NULL;
    Rc = elmc_new_int(&owned[62], 0);
    CHECK_RC(Rc);
    Rc = elmc_new_int(&owned[63], 0);
    CHECK_RC(Rc);
    const char *rec_names_64[2] = { "x", "y" };
    ElmcValue *rec_values_64[2] = { owned[62], owned[63] };
    Rc = elmc_record_new_static_take(&owned[64], 2, rec_names_64, rec_values_64);
    CHECK_RC(Rc);
    owned[62] = NULL;
    owned[63] = NULL;
    Rc = elmc_list_cons(&owned[65], owned[64], owned[61]);
    CHECK_RC(Rc);
    owned[64] = NULL;
    owned[61] = NULL;
    Rc = elmc_new_int(&owned[66], 10);
    CHECK_RC(Rc);
    Rc = elmc_new_int(&owned[67], 78);
    CHECK_RC(Rc);
    const char *rec_names_68[2] = { "x", "y" };
    ElmcValue *rec_values_68[2] = { owned[66], owned[67] };
    Rc = elmc_record_new_static_take(&owned[68], 2, rec_names_68, rec_values_68);
    CHECK_RC(Rc);
    owned[66] = NULL;
    owned[67] = NULL;
    Rc = elmc_new_int(&owned[69], 1);
    CHECK_RC(Rc);
    Rc = elmc_new_int(&owned[70], 0);
    CHECK_RC(Rc);
    Rc = elmc_tuple2(&owned[71], owned[69], owned[70]);
    CHECK_RC(Rc);
    owned[69] = NULL;
    owned[70] = NULL;
    owned[72] = elmc_fn_Pebble_Ui_path(owned[65], owned[68], owned[71]);
    owned[65] = NULL;
    owned[68] = NULL;
    owned[71] = NULL;
    Rc = elmc_tuple2(&owned[73], owned[48], owned[72]);
    CHECK_RC(Rc);
    owned[48] = NULL;
    owned[72] = NULL;
    Rc = elmc_list_cons(&owned[74], owned[73], owned[47]);
    CHECK_RC(Rc);
    owned[73] = NULL;
    owned[47] = NULL;
    Rc = elmc_new_int(&owned[75], ELMC_RENDER_OP_PATH_FILLED);
    CHECK_RC(Rc);
    owned[76] = elmc_list_nil();
    Rc = elmc_new_int(&owned[77], 0);
    CHECK_RC(Rc);
    Rc = elmc_new_int(&owned[78], 14);
    CHECK_RC(Rc);
    const char *rec_names_79[2] = { "x", "y" };
    ElmcValue *rec_values_79[2] = { owned[77], owned[78] };
    Rc = elmc_record_new_static_take(&owned[79], 2, rec_names_79, rec_values_79);
    CHECK_RC(Rc);
    owned[77] = NULL;
    owned[78] = NULL;
    Rc = elmc_list_cons(&owned[80], owned[79], owned[76]);
    CHECK_RC(Rc);
    owned[79] = NULL;
    owned[76] = NULL;
    Rc = elmc_new_int(&owned[81], 2);
    CHECK_RC(Rc);
    Rc = elmc_new_int(&owned[82], 20);
    CHECK_RC(Rc);
    const char *rec_names_83[2] = { "x", "y" };
    ElmcValue *rec_values_83[2] = { owned[81], owned[82] };
    Rc = elmc_record_new_static_take(&owned[83], 2, rec_names_83, rec_values_83);
    CHECK_RC(Rc);
    owned[81] = NULL;
    owned[82] = NULL;
    Rc = elmc_list_cons(&owned[84], owned[83], owned[80]);
    CHECK_RC(Rc);
    owned[83] = NULL;
    owned[80] = NULL;
    Rc = elmc_new_int(&owned[85], 6);
    CHECK_RC(Rc);
    Rc = elmc_new_int(&owned[86], 14);
    CHECK_RC(Rc);
    const char *rec_names_87[2] = { "x", "y" };
    ElmcValue *rec_values_87[2] = { owned[85], owned[86] };
    Rc = elmc_record_new_static_take(&owned[87], 2, rec_names_87, rec_values_87);
    CHECK_RC(Rc);
    owned[85] = NULL;
    owned[86] = NULL;
    Rc = elmc_list_cons(&owned[88], owned[87], owned[84]);
    CHECK_RC(Rc);
    owned[87] = NULL;
    owned[84] = NULL;
    Rc = elmc_new_int(&owned[89], 8);
    CHECK_RC(Rc);
    Rc = elmc_new_int(&owned[90], 6);
    CHECK_RC(Rc);
    const char *rec_names_91[2] = { "x", "y" };
    ElmcValue *rec_values_91[2] = { owned[89], owned[90] };
    Rc = elmc_record_new_static_take(&owned[91], 2, rec_names_91, rec_values_91);
    CHECK_RC(Rc);
    owned[89] = NULL;
    owned[90] = NULL;
    Rc = elmc_list_cons(&owned[92], owned[91], owned[88]);
    CHECK_RC(Rc);
    owned[91] = NULL;
    owned[88] = NULL;
    Rc = elmc_new_int(&owned[93], 0);
    CHECK_RC(Rc);
    Rc = elmc_new_int(&owned[94], 0);
    CHECK_RC(Rc);
    const char *rec_names_95[2] = { "x", "y" };
    ElmcValue *rec_values_95[2] = { owned[93], owned[94] };
    Rc = elmc_record_new_static_take(&owned[95], 2, rec_names_95, rec_values_95);
    CHECK_RC(Rc);
    owned[93] = NULL;
    owned[94] = NULL;
    Rc = elmc_list_cons(&owned[96], owned[95], owned[92]);
    CHECK_RC(Rc);
    owned[95] = NULL;
    owned[92] = NULL;
    Rc = elmc_new_int(&owned[97], 108);
    CHECK_RC(Rc);
    Rc = elmc_new_int(&owned[98], 26);
    CHECK_RC(Rc);
    const char *rec_names_99[2] = { "x", "y" };
    ElmcValue *rec_values_99[2] = { owned[97], owned[98] };
    Rc = elmc_record_new_static_take(&owned[99], 2, rec_names_99, rec_values_99);
    CHECK_RC(Rc);
    owned[97] = NULL;
    owned[98] = NULL;
    Rc = elmc_new_int(&owned[100], 1);
    CHECK_RC(Rc);
    Rc = elmc_new_int(&owned[101], 0);
    CHECK_RC(Rc);
    Rc = elmc_tuple2(&owned[102], owned[100], owned[101]);
    CHECK_RC(Rc);
    owned[100] = NULL;
    owned[101] = NULL;
    owned[103] = elmc_fn_Pebble_Ui_path(owned[96], owned[99], owned[102]);
    owned[96] = NULL;
    owned[99] = NULL;
    owned[102] = NULL;
    Rc = elmc_tuple2(&owned[104], owned[75], owned[103]);
    CHECK_RC(Rc);
    owned[75] = NULL;
    owned[103] = NULL;
    Rc = elmc_list_cons(&owned[105], owned[104], owned[74]);
    CHECK_RC(Rc);
    owned[104] = NULL;
    owned[74] = NULL;
    Rc = elmc_new_int(&owned[106], ELMC_RENDER_OP_PATH_OUTLINE);
    CHECK_RC(Rc);
    owned[107] = elmc_list_nil();
    Rc = elmc_new_int(&owned[108], 0);
    CHECK_RC(Rc);
    Rc = elmc_new_int(&owned[109], 18);
    CHECK_RC(Rc);
    const char *rec_names_110[2] = { "x", "y" };
    ElmcValue *rec_values_110[2] = { owned[108], owned[109] };
    Rc = elmc_record_new_static_take(&owned[110], 2, rec_names_110, rec_values_110);
    CHECK_RC(Rc);
    owned[108] = NULL;
    owned[109] = NULL;
    Rc = elmc_list_cons(&owned[111], owned[110], owned[107]);
    CHECK_RC(Rc);
    owned[110] = NULL;
    owned[107] = NULL;
    Rc = elmc_new_int(&owned[112], 8);
    CHECK_RC(Rc);
    Rc = elmc_new_int(&owned[113], 24);
    CHECK_RC(Rc);
    const char *rec_names_114[2] = { "x", "y" };
    ElmcValue *rec_values_114[2] = { owned[112], owned[113] };
    Rc = elmc_record_new_static_take(&owned[114], 2, rec_names_114, rec_values_114);
    CHECK_RC(Rc);
    owned[112] = NULL;
    owned[113] = NULL;
    Rc = elmc_list_cons(&owned[115], owned[114], owned[111]);
    CHECK_RC(Rc);
    owned[114] = NULL;
    owned[111] = NULL;
    Rc = elmc_new_int(&owned[116], 16);
    CHECK_RC(Rc);
    Rc = elmc_new_int(&owned[117], 14);
    CHECK_RC(Rc);
    const char *rec_names_118[2] = { "x", "y" };
    ElmcValue *rec_values_118[2] = { owned[116], owned[117] };
    Rc = elmc_record_new_static_take(&owned[118], 2, rec_names_118, rec_values_118);
    CHECK_RC(Rc);
    owned[116] = NULL;
    owned[117] = NULL;
    Rc = elmc_list_cons(&owned[119], owned[118], owned[115]);
    CHECK_RC(Rc);
    owned[118] = NULL;
    owned[115] = NULL;
    Rc = elmc_new_int(&owned[120], 10);
    CHECK_RC(Rc);
    Rc = elmc_new_int(&owned[121], 4);
    CHECK_RC(Rc);
    const char *rec_names_122[2] = { "x", "y" };
    ElmcValue *rec_values_122[2] = { owned[120], owned[121] };
    Rc = elmc_record_new_static_take(&owned[122], 2, rec_names_122, rec_values_122);
    CHECK_RC(Rc);
    owned[120] = NULL;
    owned[121] = NULL;
    Rc = elmc_list_cons(&owned[123], owned[122], owned[119]);
    CHECK_RC(Rc);
    owned[122] = NULL;
    owned[119] = NULL;
    Rc = elmc_new_int(&owned[124], 0);
    CHECK_RC(Rc);
    Rc = elmc_new_int(&owned[125], 0);
    CHECK_RC(Rc);
    const char *rec_names_126[2] = { "x", "y" };
    ElmcValue *rec_values_126[2] = { owned[124], owned[125] };
    Rc = elmc_record_new_static_take(&owned[126], 2, rec_names_126, rec_values_126);
    CHECK_RC(Rc);
    owned[124] = NULL;
    owned[125] = NULL;
    Rc = elmc_list_cons(&owned[127], owned[126], owned[123]);
    CHECK_RC(Rc);
    owned[126] = NULL;
    owned[123] = NULL;
    Rc = elmc_new_int(&owned[128], 86);
    CHECK_RC(Rc);
    Rc = elmc_new_int(&owned[129], 16);
    CHECK_RC(Rc);
    const char *rec_names_130[2] = { "x", "y" };
    ElmcValue *rec_values_130[2] = { owned[128], owned[129] };
    Rc = elmc_record_new_static_take(&owned[130], 2, rec_names_130, rec_values_130);
    CHECK_RC(Rc);
    owned[128] = NULL;
    owned[129] = NULL;
    Rc = elmc_new_int(&owned[131], 1);
    CHECK_RC(Rc);
    Rc = elmc_new_int(&owned[132], 0);
    CHECK_RC(Rc);
    Rc = elmc_tuple2(&owned[133], owned[131], owned[132]);
    CHECK_RC(Rc);
    owned[131] = NULL;
    owned[132] = NULL;
    owned[134] = elmc_fn_Pebble_Ui_path(owned[127], owned[130], owned[133]);
    owned[127] = NULL;
    owned[130] = NULL;
    owned[133] = NULL;
    Rc = elmc_tuple2(&owned[135], owned[106], owned[134]);
    CHECK_RC(Rc);
    owned[106] = NULL;
    owned[134] = NULL;
    Rc = elmc_list_cons(&owned[136], owned[135], owned[105]);
    CHECK_RC(Rc);
    owned[135] = NULL;
    owned[105] = NULL;
    Rc = elmc_new_int(&owned[137], 20);
    CHECK_RC(Rc);
    Rc = elmc_new_int(&owned[138], 16);
    CHECK_RC(Rc);
    Rc = elmc_new_int(&owned[139], 36);
    CHECK_RC(Rc);
    Rc = elmc_new_int(&owned[140], 36);
    CHECK_RC(Rc);
    Rc = elmc_new_int(&owned[141], 0);
    CHECK_RC(Rc);
    Rc = elmc_new_int(&owned[142], 45000);
    CHECK_RC(Rc);
    owned[143] = elmc_render_cmd6(ELMC_RENDER_OP_ARC, elmc_as_int(owned[137]), elmc_as_int(owned[138]), elmc_as_int(owned[139]), elmc_as_int(owned[140]), elmc_as_int(owned[141]), elmc_as_int(owned[142]));
    if (!owned[143]) {
      Rc = RC_ERR_OUT_OF_MEMORY;
      CHECK_RC(Rc);
    }
    Rc = elmc_list_cons(&owned[144], owned[143], owned[136]);
    CHECK_RC(Rc);
    owned[143] = NULL;
    owned[136] = NULL;
    Rc = elmc_new_int(&owned[145], 6);
    CHECK_RC(Rc);
    Rc = elmc_new_int(&owned[146], 6);
    CHECK_RC(Rc);
    Rc = elmc_new_int(&owned[147], 132);
    CHECK_RC(Rc);
    Rc = elmc_new_int(&owned[148], 70);
    CHECK_RC(Rc);
    Rc = elmc_new_int(&owned[149], 6);
    CHECK_RC(Rc);
    Rc = elmc_new_int(&owned[150], ELMC_COLOR_BLACK);
    CHECK_RC(Rc);
    owned[151] = elmc_render_cmd6(ELMC_RENDER_OP_ROUND_RECT, elmc_as_int(owned[145]), elmc_as_int(owned[146]), elmc_as_int(owned[147]), elmc_as_int(owned[148]), elmc_as_int(owned[149]), elmc_as_int(owned[150]));
    if (!owned[151]) {
      Rc = RC_ERR_OUT_OF_MEMORY;
      CHECK_RC(Rc);
    }
    Rc = elmc_list_cons(&owned[152], owned[151], owned[144]);
    CHECK_RC(Rc);
    owned[151] = NULL;
    owned[144] = NULL;
    Rc = elmc_tuple2(&owned[153], owned[46], owned[152]);
    CHECK_RC(Rc);
    owned[46] = NULL;
    owned[152] = NULL;
    Rc = elmc_tuple2(&owned[154], owned[25], owned[153]);
    CHECK_RC(Rc);
    owned[25] = NULL;
    owned[153] = NULL;
    Rc = elmc_list_cons(&owned[155], owned[154], owned[24]);
    CHECK_RC(Rc);
    owned[154] = NULL;
    owned[24] = NULL;
    Rc = elmc_new_int(&owned[156], ELMC_COLOR_WHITE);
    CHECK_RC(Rc);
    owned[157] = elmc_render_cmd6(ELMC_RENDER_OP_CLEAR, elmc_as_int(owned[156]), 0, 0, 0, 0, 0);
    if (!owned[157]) {
      Rc = RC_ERR_OUT_OF_MEMORY;
      CHECK_RC(Rc);
    }
    Rc = elmc_list_cons(&owned[158], owned[157], owned[155]);
    CHECK_RC(Rc);
    owned[157] = NULL;
    owned[155] = NULL;
    Rc = elmc_tuple2(&owned[159], owned[7], owned[158]);
    CHECK_RC(Rc);
    owned[7] = NULL;
    owned[158] = NULL;
    Rc = elmc_tuple2(&owned[160], owned[6], owned[159]);
    CHECK_RC(Rc);
    owned[6] = NULL;
    owned[159] = NULL;
    Rc = elmc_list_cons(&owned[161], owned[160], owned[5]);
    CHECK_RC(Rc);
    owned[160] = NULL;
    owned[5] = NULL;
    Rc = elmc_tuple2(&owned[162], owned[4], owned[161]);
    CHECK_RC(Rc);
    owned[4] = NULL;
    owned[161] = NULL;
    Rc = elmc_tuple2(&owned[163], owned[3], owned[162]);
    CHECK_RC(Rc);
    owned[3] = NULL;
    owned[162] = NULL;
    Rc = elmc_list_cons(&owned[164], owned[163], owned[2]);
    CHECK_RC(Rc);
    owned[163] = NULL;
    owned[2] = NULL;
    Rc = elmc_tuple2(&owned[165], owned[1], owned[164]);
    CHECK_RC(Rc);
    owned[1] = NULL;
    owned[164] = NULL;
    *out = owned[165];
    owned[165] = NULL;
    owned[165] = NULL;
    elmc_release(owned[13]);
    owned[13] = NULL;
    owned[13] = NULL;
    elmc_release(owned[14]);
    owned[14] = NULL;
    owned[14] = NULL;
    elmc_release(owned[15]);
    owned[15] = NULL;
    owned[15] = NULL;
    elmc_release(owned[18]);
    owned[18] = NULL;
    owned[18] = NULL;
    elmc_release(owned[19]);
    owned[19] = NULL;
    owned[19] = NULL;
    elmc_release(owned[20]);
    owned[20] = NULL;
    owned[20] = NULL;
    elmc_release(owned[21]);
    owned[21] = NULL;
    owned[21] = NULL;
    elmc_release(owned[22]);
    owned[22] = NULL;
    owned[22] = NULL;
    elmc_release(owned[137]);
    owned[137] = NULL;
    owned[137] = NULL;
    elmc_release(owned[138]);
    owned[138] = NULL;
    owned[138] = NULL;
    elmc_release(owned[139]);
    owned[139] = NULL;
    owned[139] = NULL;
    elmc_release(owned[140]);
    owned[140] = NULL;
    owned[140] = NULL;
    elmc_release(owned[141]);
    owned[141] = NULL;
    owned[141] = NULL;
    elmc_release(owned[142]);
    owned[142] = NULL;
    owned[142] = NULL;
    elmc_release(owned[145]);
    owned[145] = NULL;
    owned[145] = NULL;
    elmc_release(owned[146]);
    owned[146] = NULL;
    owned[146] = NULL;
    elmc_release(owned[147]);
    owned[147] = NULL;
    owned[147] = NULL;
    elmc_release(owned[148]);
    owned[148] = NULL;
    owned[148] = NULL;
    elmc_release(owned[149]);
    owned[149] = NULL;
    owned[149] = NULL;
    elmc_release(owned[150]);
    owned[150] = NULL;
    owned[150] = NULL;
    elmc_release(owned[156]);
    owned[156] = NULL;
    owned[156] = NULL;
    owned[0] = NULL;
  CATCH_END;

  elmc_release_array_lifo(owned, 166);
  return Rc;
}

static RC elmc_fn_Main_statusDraw(ElmcValue **out, ElmcValue *model) {
  /* Ownership policy: borrow_arg, borrow_result, direct_call_abi */
  RC Rc = RC_SUCCESS;
  ElmcValue *owned[24] = {0};
  CATCH_BEGIN
    /* plan block 0 */
    owned[0] = model;
    Rc = elmc_fn_Main_temperatureOf(&owned[1], owned[0]);
    CHECK_RC(Rc);
    Rc = elmc_new_int(&owned[2], elmc_maybe_is_nothing(owned[1]) ? 1 : 0);
    CHECK_RC(Rc);
    if (elmc_as_int(owned[2]) != 0) {
      goto elmc_plan_block_1;
    } else {
      goto elmc_plan_block_2;
    }
    elmc_plan_block_1:
    Rc = elmc_new_int(&owned[3], ELMC_RENDER_OP_TEXT_LABEL_WITH_FONT);
    CHECK_RC(Rc);
    Rc = elmc_new_int(&owned[4], 1);
    CHECK_RC(Rc);
    Rc = elmc_new_int(&owned[5], 0);
    CHECK_RC(Rc);
    Rc = elmc_new_int(&owned[6], 28);
    CHECK_RC(Rc);
    Rc = elmc_new_int(&owned[7], 0);
    CHECK_RC(Rc);
    Rc = elmc_new_int(&owned[8], 0);
    CHECK_RC(Rc);
    Rc = elmc_new_int(&owned[9], 1);
    CHECK_RC(Rc);
    Rc = elmc_tuple2(&owned[10], owned[8], owned[9]);
    CHECK_RC(Rc);
    owned[8] = NULL;
    owned[9] = NULL;
    Rc = elmc_tuple2(&owned[11], owned[7], owned[10]);
    CHECK_RC(Rc);
    owned[7] = NULL;
    owned[10] = NULL;
    Rc = elmc_tuple2(&owned[12], owned[6], owned[11]);
    CHECK_RC(Rc);
    owned[6] = NULL;
    owned[11] = NULL;
    Rc = elmc_tuple2(&owned[13], owned[5], owned[12]);
    CHECK_RC(Rc);
    owned[5] = NULL;
    owned[12] = NULL;
    Rc = elmc_tuple2(&owned[14], owned[4], owned[13]);
    CHECK_RC(Rc);
    owned[4] = NULL;
    owned[13] = NULL;
    Rc = elmc_tuple2(&owned[15], owned[3], owned[14]);
    CHECK_RC(Rc);
    owned[3] = NULL;
    owned[14] = NULL;
    goto elmc_plan_block_3;
    elmc_plan_block_2:
    owned[16] = elmc_maybe_just_payload(owned[1]);
    owned[17] = elmc_retain(owned[16]);
    owned[16] = NULL;
    Rc = elmc_new_int(&owned[18], 1);
    CHECK_RC(Rc);
    Rc = elmc_new_int(&owned[19], 0);
    CHECK_RC(Rc);
    Rc = elmc_new_int(&owned[20], 28);
    CHECK_RC(Rc);
    Rc = elmc_fn_Main_temperatureValue(&owned[21], owned[17]);
    CHECK_RC(Rc);
    owned[22] = elmc_render_cmd6(ELMC_RENDER_OP_TEXT_INT_WITH_FONT, elmc_as_int(owned[18]), elmc_as_int(owned[19]), elmc_as_int(owned[20]), elmc_as_int(owned[21]), 0, 0);
    if (!owned[22]) {
      Rc = RC_ERR_OUT_OF_MEMORY;
      CHECK_RC(Rc);
    }
    goto elmc_plan_block_3;
    elmc_plan_block_3:
    if (elmc_as_int(owned[2]) != 0) {
      owned[23] = elmc_retain(owned[15]);
    } else {
      owned[23] = elmc_retain(owned[22]);
    }
    owned[15] = NULL;
    owned[22] = NULL;
    owned[2] = NULL;
    *out = owned[23];
    owned[23] = NULL;
    owned[23] = NULL;
    owned[0] = NULL;
  CATCH_END;

  elmc_release_array_lifo(owned, 24);
  return Rc;
}

static RC elmc_fn_Main_counterDraw(ElmcValue **out, ElmcValue *model) {
  /* Ownership policy: borrow_arg, borrow_result, direct_call_abi */
  RC Rc = RC_SUCCESS;
  ElmcValue *owned[6] = {0};
  CATCH_BEGIN
    /* plan block 0 */
    owned[0] = model;
    Rc = elmc_fn_Main_counterOf(&owned[1], owned[0]);
    CHECK_RC(Rc);
    Rc = elmc_new_int(&owned[2], 1);
    CHECK_RC(Rc);
    Rc = elmc_new_int(&owned[3], 0);
    CHECK_RC(Rc);
    Rc = elmc_new_int(&owned[4], 56);
    CHECK_RC(Rc);
    owned[5] = elmc_render_cmd6(ELMC_RENDER_OP_TEXT_INT_WITH_FONT, elmc_as_int(owned[2]), elmc_as_int(owned[3]), elmc_as_int(owned[4]), elmc_as_int(owned[1]), 0, 0);
    if (!owned[5]) {
      Rc = RC_ERR_OUT_OF_MEMORY;
      CHECK_RC(Rc);
    }
    *out = owned[5];
    owned[5] = NULL;
    owned[5] = NULL;
    elmc_release(owned[1]);
    owned[1] = NULL;
    owned[1] = NULL;
    elmc_release(owned[2]);
    owned[2] = NULL;
    owned[2] = NULL;
    elmc_release(owned[3]);
    owned[3] = NULL;
    owned[3] = NULL;
    elmc_release(owned[4]);
    owned[4] = NULL;
    owned[4] = NULL;
    owned[0] = NULL;
  CATCH_END;

  elmc_release_array_lifo(owned, 6);
  return Rc;
}

static RC elmc_fn_Main_temperatureValue(ElmcValue **out, ElmcValue *temperature) {
  /* Ownership policy: borrow_arg, borrow_result, direct_call_abi */
  RC Rc = RC_SUCCESS;
  ElmcValue *owned[6] = {0};
  CATCH_BEGIN
    /* plan block 0 */
    owned[0] = temperature;
    if (elmc_union_tag_matches(owned[0], 1)) goto elmc_plan_block_2; else if (elmc_union_tag_matches(owned[0], 2)) goto elmc_plan_block_4; else goto elmc_plan_block_6;
    elmc_plan_block_2:
    owned[2] = elmc_union_payload(owned[0]);
    owned[3] = elmc_retain(owned[2]);
    owned[2] = NULL;
    owned[1] = elmc_retain(owned[3]);
    owned[3] = NULL;
    goto elmc_plan_block_6;
    elmc_plan_block_4:
    owned[4] = elmc_union_payload(owned[0]);
    owned[5] = elmc_retain(owned[4]);
    owned[4] = NULL;
    owned[1] = elmc_retain(owned[5]);
    owned[5] = NULL;
    goto elmc_plan_block_6;
    elmc_plan_block_6:
    *out = owned[1];
    owned[1] = NULL;
    owned[1] = NULL;
    owned[0] = NULL;
  CATCH_END;

  elmc_release_array_lifo(owned, 6);
  return Rc;
}
static RC elmc_fn_Main_temperatureValue_native(elmc_int_t *out, ElmcValue * const temperature) {
  ElmcValue *boxed = NULL;
  RC Rc = elmc_fn_Main_temperatureValue(&boxed, temperature);
  if (Rc != RC_SUCCESS) return Rc;
  *out = elmc_as_int(boxed);
  elmc_release(boxed);
  return RC_SUCCESS;
}

static RC elmc_fn_Main_main(ElmcValue **out) {
  /* Ownership policy: borrow_arg, borrow_result, direct_call_abi */
  RC Rc = RC_SUCCESS;
  ElmcValue *owned[1] = {0};
  CATCH_BEGIN
    /* plan block 0 */
    Rc = elmc_new_int(&owned[0], 0);
    CHECK_RC(Rc);
    *out = owned[0];
    owned[0] = NULL;
    owned[0] = NULL;
  CATCH_END;

  elmc_release_array_lifo(owned, 1);
  return Rc;
}

static RC elmc_fn_Pebble_Platform_launchReasonToInt(ElmcValue **out, ElmcValue *launchReason) {
  /* Ownership policy: borrow_arg, borrow_result, direct_call_abi */
  RC Rc = RC_SUCCESS;
  ElmcValue *owned[11] = {0};
  CATCH_BEGIN
    /* plan block 0 */
    owned[0] = launchReason;
    if (elmc_union_tag_matches(owned[0], 1)) goto elmc_plan_block_2; else if (elmc_union_tag_matches(owned[0], 2)) goto elmc_plan_block_4; else if (elmc_union_tag_matches(owned[0], 3)) goto elmc_plan_block_6; else if (elmc_union_tag_matches(owned[0], 4)) goto elmc_plan_block_8; else if (elmc_union_tag_matches(owned[0], 5)) goto elmc_plan_block_10; else if (elmc_union_tag_matches(owned[0], 6)) goto elmc_plan_block_12; else if (elmc_union_tag_matches(owned[0], 7)) goto elmc_plan_block_14; else if (elmc_union_tag_matches(owned[0], 8)) goto elmc_plan_block_16; else if (elmc_union_tag_matches(owned[0], 9)) goto elmc_plan_block_18; else goto elmc_plan_block_20;
    elmc_plan_block_2:
    Rc = elmc_new_int(&owned[2], 0);
    CHECK_RC(Rc);
    owned[1] = elmc_retain(owned[2]);
    owned[2] = NULL;
    goto elmc_plan_block_20;
    elmc_plan_block_4:
    Rc = elmc_new_int(&owned[3], 1);
    CHECK_RC(Rc);
    owned[1] = elmc_retain(owned[3]);
    owned[3] = NULL;
    goto elmc_plan_block_20;
    elmc_plan_block_6:
    Rc = elmc_new_int(&owned[4], 2);
    CHECK_RC(Rc);
    owned[1] = elmc_retain(owned[4]);
    owned[4] = NULL;
    goto elmc_plan_block_20;
    elmc_plan_block_8:
    Rc = elmc_new_int(&owned[5], 3);
    CHECK_RC(Rc);
    owned[1] = elmc_retain(owned[5]);
    owned[5] = NULL;
    goto elmc_plan_block_20;
    elmc_plan_block_10:
    Rc = elmc_new_int(&owned[6], 4);
    CHECK_RC(Rc);
    owned[1] = elmc_retain(owned[6]);
    owned[6] = NULL;
    goto elmc_plan_block_20;
    elmc_plan_block_12:
    Rc = elmc_new_int(&owned[7], 5);
    CHECK_RC(Rc);
    owned[1] = elmc_retain(owned[7]);
    owned[7] = NULL;
    goto elmc_plan_block_20;
    elmc_plan_block_14:
    Rc = elmc_new_int(&owned[8], 6);
    CHECK_RC(Rc);
    owned[1] = elmc_retain(owned[8]);
    owned[8] = NULL;
    goto elmc_plan_block_20;
    elmc_plan_block_16:
    Rc = elmc_new_int(&owned[9], 7);
    CHECK_RC(Rc);
    owned[1] = elmc_retain(owned[9]);
    owned[9] = NULL;
    goto elmc_plan_block_20;
    elmc_plan_block_18:
    Rc = elmc_new_int(&owned[10], -1);
    CHECK_RC(Rc);
    owned[1] = elmc_retain(owned[10]);
    owned[10] = NULL;
    goto elmc_plan_block_20;
    elmc_plan_block_20:
    *out = owned[1];
    owned[1] = NULL;
    owned[1] = NULL;
    owned[0] = NULL;
  CATCH_END;

  elmc_release_array_lifo(owned, 11);
  return Rc;
}
static RC elmc_fn_Pebble_Platform_launchReasonToInt_native(elmc_int_t *out, ElmcValue * const launchReason) {
  ElmcValue *boxed = NULL;
  RC Rc = elmc_fn_Pebble_Platform_launchReasonToInt(&boxed, launchReason);
  if (Rc != RC_SUCCESS) return Rc;
  *out = elmc_as_int(boxed);
  elmc_release(boxed);
  return RC_SUCCESS;
}

static ElmcValue * elmc_fn_Pebble_Ui_windowStack(ElmcValue *windows) {
  /* Ownership policy: borrow_arg, retain_result, direct_call_abi */
  ElmcValue *owned[3] = {0};
  /* plan block 0 */
  owned[0] = windows;
  CATCH_BEGIN
    owned[1] = elmc_new_int_take(1);
  CATCH_END;
  CATCH_BEGIN
    owned[2] = elmc_tuple2_take_value(owned[1], owned[0]);
    owned[1] = NULL;
  CATCH_END;
  {
    ElmcValue *__ret = owned[2];
    owned[2] = NULL;
    elmc_release_array_lifo(owned, 3);
    return __ret;
  }
  owned[0] = NULL;
}

static ElmcValue * elmc_fn_Pebble_Ui_window(ElmcValue *id, ElmcValue *layers) {
  /* Ownership policy: borrow_arg, retain_result, direct_call_abi */
  ElmcValue *owned[5] = {0};
  /* plan block 0 */
  owned[0] = id;
  owned[1] = layers;
  CATCH_BEGIN
    owned[2] = elmc_new_int_take(1);
  CATCH_END;
  CATCH_BEGIN
    owned[3] = elmc_tuple2_take_value(owned[0], owned[1]);
  CATCH_END;
  CATCH_BEGIN
    owned[4] = elmc_tuple2_take_value(owned[2], owned[3]);
    owned[2] = NULL;
    owned[3] = NULL;
  CATCH_END;
  {
    ElmcValue *__ret = owned[4];
    owned[4] = NULL;
    elmc_release_array_lifo(owned, 5);
    return __ret;
  }
  owned[0] = NULL;
  owned[1] = NULL;
}

static ElmcValue * elmc_fn_Pebble_Ui_canvasLayer(ElmcValue *id, ElmcValue *ops) {
  /* Ownership policy: borrow_arg, retain_result, direct_call_abi */
  ElmcValue *owned[5] = {0};
  /* plan block 0 */
  owned[0] = id;
  owned[1] = ops;
  CATCH_BEGIN
    owned[2] = elmc_new_int_take(1);
  CATCH_END;
  CATCH_BEGIN
    owned[3] = elmc_tuple2_take_value(owned[0], owned[1]);
  CATCH_END;
  CATCH_BEGIN
    owned[4] = elmc_tuple2_take_value(owned[2], owned[3]);
    owned[2] = NULL;
    owned[3] = NULL;
  CATCH_END;
  {
    ElmcValue *__ret = owned[4];
    owned[4] = NULL;
    elmc_release_array_lifo(owned, 5);
    return __ret;
  }
  owned[0] = NULL;
  owned[1] = NULL;
}

static RC elmc_fn_Pebble_Ui_path(ElmcValue **out, ElmcValue *points, ElmcValue *offset, ElmcValue *rotation) {
  /* Ownership policy: borrow_arg, retain_result, direct_call_abi */
  RC Rc = RC_SUCCESS;
  ElmcValue *owned[11] = {0};
  CATCH_BEGIN
    /* plan block 0 */
    owned[0] = points;
    owned[1] = offset;
    owned[2] = rotation;
    Rc = elmc_closure_new_rc(&owned[3], elmc_fn_Pebble_Ui_path_closure_0, 1, 0, NULL);
    CHECK_RC(Rc);
    Rc = elmc_list_map(&owned[4], owned[3], owned[0]);
    CHECK_RC(Rc);
    owned[3] = NULL;
    owned[5] = elmc_record_get_index(owned[1], 0 /* x */);
    owned[6] = elmc_record_get_index(owned[1], 1 /* y */);
    Rc = elmc_tuple2(&owned[7], owned[5], owned[6]);
    CHECK_RC(Rc);
    owned[5] = NULL;
    owned[6] = NULL;
    owned[8] = elmc_fn_Pebble_Ui_rotationToPebbleAngle(owned[2]);
    Rc = elmc_tuple2(&owned[9], owned[7], owned[8]);
    CHECK_RC(Rc);
    owned[7] = NULL;
    owned[8] = NULL;
    Rc = elmc_tuple2(&owned[10], owned[4], owned[9]);
    CHECK_RC(Rc);
    owned[4] = NULL;
    owned[9] = NULL;
    *out = owned[10];
    owned[10] = NULL;
    owned[10] = NULL;
    owned[0] = NULL;
    owned[1] = NULL;
    owned[2] = NULL;
  CATCH_END;

  elmc_release_array_lifo(owned, 11);
  return Rc;
}

static RC elmc_fn_Pebble_Ui_rotationToPebbleAngle(ElmcValue **out) {
  /* Ownership policy: borrow_arg, borrow_result, direct_call_abi */
  RC Rc = RC_SUCCESS;
  ElmcValue *owned[1] = {0};
  CATCH_BEGIN
    /* plan block 0 */
    Rc = elmc_closure_new_rc(&owned[0], elmc_fn_Pebble_Ui_rotationToPebbleAngle_closure_0, 1, 0, NULL);
    CHECK_RC(Rc);
    *out = owned[0];
    owned[0] = NULL;
    owned[0] = NULL;
  CATCH_END;

  elmc_release_array_lifo(owned, 1);
  return Rc;
}
static RC elmc_fn_Pebble_Ui_rotationToPebbleAngle_native(elmc_int_t *out) {
  ElmcValue *boxed = NULL;
  RC Rc = elmc_fn_Pebble_Ui_rotationToPebbleAngle(&boxed);
  if (Rc != RC_SUCCESS) return Rc;
  *out = elmc_as_int(boxed);
  elmc_release(boxed);
  return RC_SUCCESS;
}

static RC elmc_fn_Companion_Internal_encodeLocationCode(ElmcValue **out, ElmcValue *value) {
  /* Ownership policy: borrow_arg, borrow_result, direct_call_abi */
  RC Rc = RC_SUCCESS;
  ElmcValue *owned[6] = {0};
  CATCH_BEGIN
    /* plan block 0 */
    owned[0] = value;
    if (elmc_union_tag_matches(owned[0], 1)) goto elmc_plan_block_2; else if (elmc_union_tag_matches(owned[0], 2)) goto elmc_plan_block_4; else if (elmc_union_tag_matches(owned[0], 3)) goto elmc_plan_block_6; else if (elmc_union_tag_matches(owned[0], 4)) goto elmc_plan_block_8; else goto elmc_plan_block_10;
    elmc_plan_block_2:
    Rc = elmc_new_int(&owned[2], 1);
    CHECK_RC(Rc);
    owned[1] = elmc_retain(owned[2]);
    owned[2] = NULL;
    goto elmc_plan_block_10;
    elmc_plan_block_4:
    Rc = elmc_new_int(&owned[3], 2);
    CHECK_RC(Rc);
    owned[1] = elmc_retain(owned[3]);
    owned[3] = NULL;
    goto elmc_plan_block_10;
    elmc_plan_block_6:
    Rc = elmc_new_int(&owned[4], 3);
    CHECK_RC(Rc);
    owned[1] = elmc_retain(owned[4]);
    owned[4] = NULL;
    goto elmc_plan_block_10;
    elmc_plan_block_8:
    Rc = elmc_new_int(&owned[5], 4);
    CHECK_RC(Rc);
    owned[1] = elmc_retain(owned[5]);
    owned[5] = NULL;
    goto elmc_plan_block_10;
    elmc_plan_block_10:
    *out = owned[1];
    owned[1] = NULL;
    owned[1] = NULL;
    owned[0] = NULL;
  CATCH_END;

  elmc_release_array_lifo(owned, 6);
  return Rc;
}
static RC elmc_fn_Companion_Internal_encodeLocationCode_native(elmc_int_t *out, ElmcValue * const value) {
  ElmcValue *boxed = NULL;
  RC Rc = elmc_fn_Companion_Internal_encodeLocationCode(&boxed, value);
  if (Rc != RC_SUCCESS) return Rc;
  *out = elmc_as_int(boxed);
  elmc_release(boxed);
  return RC_SUCCESS;
}

static RC elmc_fn_Companion_Internal_watchToPhoneTag(ElmcValue **out, ElmcValue *message) {
  /* Ownership policy: borrow_arg, borrow_result, direct_call_abi */
  RC Rc = RC_SUCCESS;
  ElmcValue *owned[5] = {0};
  CATCH_BEGIN
    /* plan block 0 */
    owned[0] = message;
    if (elmc_union_tag_matches(owned[0], 1)) goto elmc_plan_block_2; else goto elmc_plan_block_4;
    elmc_plan_block_2:
    owned[2] = elmc_union_payload(owned[0]);
    owned[3] = elmc_retain(owned[2]);
    owned[2] = NULL;
    Rc = elmc_new_int(&owned[4], 2);
    CHECK_RC(Rc);
    owned[1] = elmc_retain(owned[4]);
    owned[4] = NULL;
    goto elmc_plan_block_4;
    elmc_plan_block_4:
    *out = owned[1];
    owned[1] = NULL;
    owned[1] = NULL;
    owned[0] = NULL;
  CATCH_END;

  elmc_release_array_lifo(owned, 5);
  return Rc;
}
static RC elmc_fn_Companion_Internal_watchToPhoneTag_native(elmc_int_t *out, ElmcValue * const message) {
  ElmcValue *boxed = NULL;
  RC Rc = elmc_fn_Companion_Internal_watchToPhoneTag(&boxed, message);
  if (Rc != RC_SUCCESS) return Rc;
  *out = elmc_as_int(boxed);
  elmc_release(boxed);
  return RC_SUCCESS;
}

static RC elmc_fn_Companion_Internal_watchToPhoneValue(ElmcValue **out, ElmcValue *message) {
  /* Ownership policy: borrow_arg, borrow_result, direct_call_abi */
  RC Rc = RC_SUCCESS;
  ElmcValue *owned[5] = {0};
  CATCH_BEGIN
    /* plan block 0 */
    owned[0] = message;
    if (elmc_union_tag_matches(owned[0], 1)) goto elmc_plan_block_2; else goto elmc_plan_block_4;
    elmc_plan_block_2:
    owned[2] = elmc_union_payload(owned[0]);
    owned[3] = elmc_retain(owned[2]);
    owned[2] = NULL;
    owned[4] = elmc_fn_Companion_Internal_encodeLocationCode(owned[3]);
    owned[1] = elmc_retain(owned[4]);
    owned[4] = NULL;
    goto elmc_plan_block_4;
    elmc_plan_block_4:
    *out = owned[1];
    owned[1] = NULL;
    owned[1] = NULL;
    owned[0] = NULL;
  CATCH_END;

  elmc_release_array_lifo(owned, 5);
  return Rc;
}
static RC elmc_fn_Companion_Internal_watchToPhoneValue_native(elmc_int_t *out, ElmcValue * const message) {
  ElmcValue *boxed = NULL;
  RC Rc = elmc_fn_Companion_Internal_watchToPhoneValue(&boxed, message);
  if (Rc != RC_SUCCESS) return Rc;
  *out = elmc_as_int(boxed);
  elmc_release(boxed);
  return RC_SUCCESS;
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

    owned[0] = elmc_retain(model);

    Rc = elmc_fn_Main_temperatureOf(&owned[1], owned[0]);
    CHECK_RC(Rc);
    if (owned[1] == owned[0]) {
      owned[0] = NULL;
    }

    if (elmc_maybe_is_just(owned[1])) {

      Rc = elmc_fn_Main_temperatureValue(&owned[2], elmc_maybe_or_tuple_just_payload_borrow(owned[1]));
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

      elmc_draw_cmd_init(&scene_cmd, ELMC_RENDER_OP_TEXT_LABEL_WITH_FONT);
      scene_cmd.p0 = 1;
      scene_cmd.p1 = 0;
      scene_cmd.p2 = 28;
      scene_cmd.p3 = 0;
      scene_cmd.p4 = 0;
      {
        const char *direct_text = "Waiting for companion app";
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

    owned[3] = owned[0];

    elmc_int_t native_call_19 = 0;
    Rc = elmc_fn_Main_counterOf_native(&native_call_19, owned[3]);
    CHECK_RC(Rc);

    Rc = elmc_new_int(&owned[4], native_call_19);
    CHECK_RC(Rc);

    elmc_draw_cmd_init(&scene_cmd, ELMC_RENDER_OP_TEXT_INT_WITH_FONT);
    scene_cmd.p0 = 1;
    scene_cmd.p1 = 0;
    scene_cmd.p2 = 56;
    scene_cmd.p3 = elmc_as_int(owned[4]);
    Rc = elmc_scene_writer_push_cmd(writer, &scene_cmd);
    CHECK_RC(Rc);

  CATCH_END;
  elmc_release_array_lifo(owned, DIM(owned));

  return Rc;

}

RC elmc_fn_Main_view_scene_append(ElmcValue ** const args, const int argc, ElmcSceneWriter * const writer) {
  return elmc_fn_Main_view_commands_append(args, argc, writer);
}
