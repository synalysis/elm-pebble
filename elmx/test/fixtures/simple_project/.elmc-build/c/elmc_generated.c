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
#define ELMC_UNION_DOWN 4
#define ELMC_UNION_DOWNPRESSED 6
#define ELMC_UNION_FAHRENHEIT 2
#define ELMC_UNION_FIRMWAREVERSIONSTRING 15
#define ELMC_UNION_INCREMENT 1
#define ELMC_UNION_JUST 1
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
#define ELMC_UNION_MAYBE_JUST 1
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
#define ELMC_UNION_PEBBLE_UI_ROTATION 1
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

enum {
  ELMC_FIELD_MAIN_MODEL_TEMPERATURE = 1,
  ELMC_FIELD_MAIN_MODEL_VALUE = 0,
  ELMC_FIELD_PEBBLE_ACCEL_SAMPLE_X = 0,
  ELMC_FIELD_PEBBLE_ACCEL_SAMPLE_Y = 1,
  ELMC_FIELD_PEBBLE_GAME_COLLISION_CIRCLE_X = 0,
  ELMC_FIELD_PEBBLE_GAME_COLLISION_CIRCLE_Y = 1,
  ELMC_FIELD_PEBBLE_GAME_COLLISION_RECT_H = 3,
  ELMC_FIELD_PEBBLE_GAME_COLLISION_RECT_W = 2,
  ELMC_FIELD_PEBBLE_GAME_COLLISION_RECT_X = 0,
  ELMC_FIELD_PEBBLE_GAME_COLLISION_RECT_Y = 1,
  ELMC_FIELD_PEBBLE_GAME_MATH_VEC2_X = 0,
  ELMC_FIELD_PEBBLE_GAME_MATH_VEC2_Y = 1,
  ELMC_FIELD_PEBBLE_GAME_SPRITE_SPRITE_H = 4,
  ELMC_FIELD_PEBBLE_GAME_SPRITE_SPRITE_W = 3,
  ELMC_FIELD_PEBBLE_GAME_SPRITE_SPRITE_X = 1,
  ELMC_FIELD_PEBBLE_GAME_SPRITE_SPRITE_Y = 2,
  ELMC_FIELD_PEBBLE_PLATFORM_LAUNCHCONTEXT_REASON = 0,
  ELMC_FIELD_PEBBLE_UI_POINT_X = 0,
  ELMC_FIELD_PEBBLE_UI_POINT_Y = 1,
  ELMC_FIELD_PEBBLE_UI_RECT_H = 3,
  ELMC_FIELD_PEBBLE_UI_RECT_W = 2,
  ELMC_FIELD_PEBBLE_UI_RECT_X = 0,
  ELMC_FIELD_PEBBLE_UI_RECT_Y = 1
};

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
  ElmcValue *out = NULL;
  return elmc_render_cmd6_take(&out, kind, p0, p1, p2, p3, p4, p5) == RC_SUCCESS ? out : NULL;
}

static RC elmc_fn_Main_temperatureValue_native(elmc_int_t *out, ElmcValue * const temperature);
static RC elmc_fn_Pebble_Ui_rotationToPebbleAngle_native(elmc_int_t *out);
static RC elmc_fn_Companion_Internal_watchToPhoneTag_native(elmc_int_t *out, ElmcValue * const message);
static RC elmc_fn_Companion_Internal_watchToPhoneValue_native(elmc_int_t *out, ElmcValue * const message);

static RC elmc_fn_Pebble_Platform_launchReasonToInt_native(ElmcValue **out, elmc_int_t launchReason);
static RC elmc_fn_Companion_Internal_encodeLocationCode_native(ElmcValue **out, elmc_int_t value);

static elmc_int_t elmc_fn_Main_helper(elmc_int_t value);
static elmc_int_t elmc_fn_Main_advanced(elmc_int_t n);
static elmc_int_t elmc_fn_Main_counterOf(ElmcValue *model);
static RC elmc_fn_Main_temperatureOf(ElmcValue **out, ElmcValue *model);
static RC elmc_fn_Main_requestWeather(ElmcValue **out, ElmcValue *location);
static RC elmc_fn_Main_requestSystemInfo(ElmcValue **out);
RC elmc_fn_Main_init(ElmcValue **out, ElmcValue *launchContext);
RC elmc_fn_Main_update(ElmcValue **out, ElmcValue *msg, ElmcValue *model);
static RC elmc_fn_Main_handleAppMsg(ElmcValue **out, ElmcValue *msg, ElmcValue *model);
static RC elmc_fn_Main_handlePlatformMsg(ElmcValue **out, ElmcValue *msg, ElmcValue *model);
RC elmc_fn_Main_subscriptions(ElmcValue **out, ElmcValue *_unused_0);
RC elmc_fn_Main_view(ElmcValue **out, ElmcValue *model);
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

  ElmcValue *owned[1] = {0};
  CATCH_BEGIN
    /* plan block 0 */
    CATCH_BEGIN
      const elmc_int_t plan_native_int_1 = ELMC_RECORD_GET_INDEX_INT((argc > 0 ? args[0] : NULL), ELMC_FIELD_PEBBLE_ACCEL_SAMPLE_X);
      const elmc_int_t plan_native_int_2 = ELMC_RECORD_GET_INDEX_INT((argc > 0 ? args[0] : NULL), ELMC_FIELD_PEBBLE_ACCEL_SAMPLE_Y);
      ElmcValue *plan_ephemeral_box_17442 = elmc_new_int_take(plan_native_int_1);
      ElmcValue *plan_ephemeral_box_17458 = elmc_new_int_take(plan_native_int_2);
      Rc = elmc_tuple2(&owned[0], plan_ephemeral_box_17442, plan_ephemeral_box_17458);
      CHECK_RC(Rc);
      elmc_release(plan_ephemeral_box_17442);
      elmc_release(plan_ephemeral_box_17458);
      *out = owned[0];
      owned[0] = NULL;
    CATCH_END;
  CATCH_END;

  elmc_release_array_lifo(owned, 1);
  return Rc;
}
static RC elmc_fn_Pebble_Ui_rotationToPebbleAngle_closure_0(ElmcValue **out, ElmcValue **args, int argc, ElmcValue **captures, int capture_count) {
  (void)captures;
  (void)capture_count;
  RC Rc = RC_SUCCESS;

  ElmcValue *owned[2] = {0};
  CATCH_BEGIN
    /* plan block 0 */
    CATCH_BEGIN
      if (!elmc_union_tag_matches((argc > 0 ? args[0] : NULL), ELMC_UNION_PEBBLE_UI_ROTATION)) {
        goto elmc_plan_block_4;
      }
      owned[1] = elmc_tuple_second((argc > 0 ? args[0] : NULL));
      owned[0] = elmc_retain(owned[1]);
      elmc_plan_block_4:
      *out = owned[0];
      owned[0] = NULL;
    CATCH_END;
  CATCH_END;

  elmc_release_array_lifo(owned, 2);
  return Rc;
}

static elmc_int_t elmc_fn_Main_helper(elmc_int_t value) {
  /* Ownership policy: borrow_arg, borrow_result, direct_call_abi */
  /* plan block 0 */
  return value + 2;
}

static elmc_int_t elmc_fn_Main_advanced(elmc_int_t n) {
  /* Ownership policy: borrow_arg, borrow_result, direct_call_abi */
  elmc_int_t plan_native_int_1 = 0;
  elmc_int_t plan_native_int_5 = 0;
  /* plan block 0 */
  plan_native_int_1 = elmc_fn_Main_helper(n);
  const bool plan_native_bool_3 = (plan_native_int_1 > 10);
  if (plan_native_bool_3) {
    goto elmc_plan_block_3;
  } else {
    goto elmc_plan_block_2;
  }
  goto elmc_plan_block_3;
  elmc_plan_block_2:
  const elmc_int_t plan_native_int_4 = plan_native_int_1 + 1;
  elmc_plan_block_3:
  plan_native_int_5 = (plan_native_bool_3) ? plan_native_int_1 : plan_native_int_4;
  return plan_native_int_5;
}

static elmc_int_t elmc_fn_Main_counterOf(ElmcValue *model) {
  /* Ownership policy: borrow_arg, borrow_result, direct_call_abi */
  /* plan block 0 */
  const elmc_int_t plan_native_int_1 = ELMC_RECORD_GET_INDEX_INT(model, ELMC_FIELD_MAIN_MODEL_VALUE);
  return plan_native_int_1;
}

static RC elmc_fn_Main_temperatureOf(ElmcValue **out, ElmcValue *model) {
  /* Ownership policy: borrow_arg, borrow_result, direct_call_abi */
  RC Rc = RC_SUCCESS;
  ElmcValue *owned[1] = {0};
  CATCH_BEGIN
    /* plan block 0 */
    owned[0] = elmc_record_get_index(model, ELMC_FIELD_MAIN_MODEL_TEMPERATURE);
    *out = owned[0];
    owned[0] = NULL;
  CATCH_END;

  elmc_release_array_lifo(owned, 1);
  return Rc;
}

static RC elmc_fn_Main_requestWeather(ElmcValue **out, ElmcValue *location) {
  /* Ownership policy: borrow_arg, borrow_result, direct_call_abi */
  RC Rc = RC_SUCCESS;
  ElmcValue *owned[7] = {0};
  CATCH_BEGIN
    /* plan block 0 */
    Rc = elmc_cmd0(&owned[1], ELMC_PEBBLE_CMD_COMPANION_SEND);
    CHECK_RC(Rc);
    owned[3] = elmc_retain(location);
    ElmcValue *plan_ephemeral_box_16818 = elmc_new_int_take(1);
    Rc = elmc_tuple2(&owned[4], plan_ephemeral_box_16818, owned[3]);
    CHECK_RC(Rc);
    elmc_release(plan_ephemeral_box_16818);
    elmc_release(owned[3]);
    owned[3] = NULL;
    Rc = elmc_fn_Companion_Internal_watchToPhoneTag(&owned[2], owned[4]);
    CHECK_RC(Rc);
    elmc_release(owned[4]);
    owned[4] = NULL;
    owned[4] = elmc_retain(location);
    ElmcValue *plan_ephemeral_box_16834 = elmc_new_int_take(1);
    Rc = elmc_tuple2(&owned[0], plan_ephemeral_box_16834, owned[4]);
    CHECK_RC(Rc);
    elmc_release(plan_ephemeral_box_16834);
    elmc_release(owned[4]);
    owned[4] = NULL;
    Rc = elmc_fn_Companion_Internal_watchToPhoneValue(&owned[3], owned[0]);
    CHECK_RC(Rc);
    elmc_release(owned[0]);
    owned[0] = NULL;
    Rc = elmc_tuple2_ints(&owned[5], 0, 0);
    CHECK_RC(Rc);
    ElmcValue *plan_ephemeral_box_16850 = elmc_new_int_take(0);
    Rc = elmc_tuple2(&owned[6], plan_ephemeral_box_16850, owned[5]);
    CHECK_RC(Rc);
    elmc_release(plan_ephemeral_box_16850);
    elmc_release(owned[5]);
    owned[5] = NULL;
    ElmcValue *plan_ephemeral_box_16866 = elmc_new_int_take(0);
    Rc = elmc_tuple2(&owned[4], plan_ephemeral_box_16866, owned[6]);
    CHECK_RC(Rc);
    elmc_release(plan_ephemeral_box_16866);
    elmc_release(owned[6]);
    owned[6] = NULL;
    Rc = elmc_tuple2(&owned[0], owned[3], owned[4]);
    CHECK_RC(Rc);
    elmc_release(owned[3]);
    owned[3] = NULL;
    elmc_release(owned[4]);
    owned[4] = NULL;
    Rc = elmc_tuple2(&owned[3], owned[2], owned[0]);
    CHECK_RC(Rc);
    elmc_release(owned[2]);
    owned[2] = NULL;
    elmc_release(owned[0]);
    owned[0] = NULL;
    Rc = elmc_tuple2(out, owned[1], owned[3]);
    CHECK_RC(Rc);
  CATCH_END;

  elmc_release_array_lifo(owned, 7);
  return Rc;
}

static RC elmc_fn_Main_requestSystemInfo(ElmcValue **out) {
  /* Ownership policy: borrow_arg, borrow_result, direct_call_abi */
  RC Rc = RC_SUCCESS;
  ElmcValue *owned[8] = {0};
  CATCH_BEGIN
    /* plan block 0 */
    Rc = elmc_cmd1(&owned[1], ELMC_PEBBLE_CMD_GET_CURRENT_TIME_STRING, ELMC_PEBBLE_MSG_CURRENTTIMESTRING);
    CHECK_RC(Rc);
    Rc = elmc_cmd1(&owned[2], ELMC_PEBBLE_CMD_GET_CLOCK_STYLE_24H, ELMC_PEBBLE_MSG_CLOCKSTYLE24H);
    CHECK_RC(Rc);
    Rc = elmc_cmd1(&owned[3], ELMC_PEBBLE_CMD_GET_TIMEZONE_IS_SET, ELMC_PEBBLE_MSG_TIMEZONEISSET);
    CHECK_RC(Rc);
    Rc = elmc_cmd1(&owned[4], ELMC_PEBBLE_CMD_GET_TIMEZONE, ELMC_PEBBLE_MSG_TIMEZONENAME);
    CHECK_RC(Rc);
    Rc = elmc_cmd1(&owned[5], ELMC_PEBBLE_CMD_GET_WATCH_MODEL, ELMC_PEBBLE_MSG_WATCHMODELNAME);
    CHECK_RC(Rc);
    Rc = elmc_cmd1(&owned[6], ELMC_PEBBLE_CMD_GET_WATCH_COLOR, ELMC_PEBBLE_MSG_WATCHCOLORNAME);
    CHECK_RC(Rc);
    Rc = elmc_cmd1(&owned[7], ELMC_PEBBLE_CMD_GET_FIRMWARE_VERSION, ELMC_PEBBLE_MSG_FIRMWAREVERSIONSTRING);
    CHECK_RC(Rc);
    owned[0] = elmc_retain(owned[1]);
    elmc_release(owned[1]);
    owned[1] = NULL;
    owned[1] = elmc_retain(owned[2]);
    elmc_release(owned[2]);
    owned[2] = NULL;
    owned[2] = elmc_retain(owned[3]);
    elmc_release(owned[3]);
    owned[3] = NULL;
    owned[3] = elmc_retain(owned[4]);
    elmc_release(owned[4]);
    owned[4] = NULL;
    owned[4] = elmc_retain(owned[5]);
    elmc_release(owned[5]);
    owned[5] = NULL;
    owned[5] = elmc_retain(owned[6]);
    elmc_release(owned[6]);
    owned[6] = NULL;
    owned[6] = elmc_retain(owned[7]);
    elmc_release(owned[7]);
    owned[7] = NULL;
    ElmcValue *plan_list_items_16882[7] = { owned[0], owned[1], owned[2], owned[3], owned[4], owned[5], owned[6] };
    Rc = elmc_list_from_values_take(&owned[7], plan_list_items_16882, 7);
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

  elmc_release_array_lifo(owned, 8);
  return Rc;
}

RC elmc_fn_Main_init(ElmcValue **out, ElmcValue *launchContext) {
  /* Ownership policy: borrow_arg, borrow_result, direct_call_abi */
  RC Rc = RC_SUCCESS;
  ElmcValue *owned[10] = {0};
  CATCH_BEGIN
    /* plan block 0 */
    owned[1] = elmc_record_get_index(launchContext, ELMC_FIELD_PEBBLE_PLATFORM_LAUNCHCONTEXT_REASON);
    Rc = elmc_fn_Pebble_Platform_launchReasonToInt(&owned[0], owned[1]);
    CHECK_RC(Rc);
    elmc_release(owned[1]);
    owned[1] = NULL;
    owned[1] = elmc_retain(owned[0]);
    owned[2] = elmc_maybe_nothing();
    owned[3] = elmc_retain(owned[2]);
    owned[4] = elmc_retain(owned[1]);
    owned[5] = elmc_retain(owned[3]);
    ElmcValue *rec_values_8_86[2] = { owned[4], owned[5] };
    Rc = elmc_record_new_values_take(&owned[6], 2, rec_values_8_86);
    CHECK_RC(Rc);
    owned[4] = NULL;
    owned[5] = NULL;
    owned[4] = NULL;
    owned[5] = NULL;
    owned[5] = elmc_unit();
    ElmcValue *plan_ephemeral_box_16898 = elmc_new_int_take(2);
    Rc = elmc_tuple2(&owned[7], plan_ephemeral_box_16898, owned[5]);
    CHECK_RC(Rc);
    elmc_release(plan_ephemeral_box_16898);
    elmc_release(owned[5]);
    owned[5] = NULL;
    Rc = elmc_fn_Main_requestWeather(&owned[4], owned[7]);
    CHECK_RC(Rc);
    elmc_release(owned[7]);
    owned[7] = NULL;
    Rc = elmc_fn_Main_requestSystemInfo(&owned[5]);
    CHECK_RC(Rc);
    owned[7] = elmc_retain(owned[4]);
    owned[8] = elmc_retain(owned[5]);
    ElmcValue *plan_list_items_16914[2] = { owned[7], owned[8] };
    Rc = elmc_list_from_values_take(&owned[9], plan_list_items_16914, 2);
    CHECK_RC(Rc);
    owned[7] = NULL;
    owned[8] = NULL;
    owned[7] = elmc_cmd_batch(owned[9]);
    elmc_release(owned[9]);
    owned[9] = NULL;
    Rc = elmc_tuple2(out, owned[6], owned[7]);
    CHECK_RC(Rc);
    elmc_release(owned[0]);
    owned[0] = NULL;
    elmc_release(owned[1]);
    owned[1] = NULL;
    elmc_release(owned[2]);
    owned[2] = NULL;
    elmc_release(owned[3]);
    owned[3] = NULL;
    elmc_release(owned[4]);
    owned[4] = NULL;
    elmc_release(owned[5]);
    owned[5] = NULL;
  CATCH_END;

  elmc_release_array_lifo(owned, 10);
  return Rc;
}

RC elmc_fn_Main_update(ElmcValue **out, ElmcValue *msg, ElmcValue *model) {
  /* Ownership policy: borrow_arg, borrow_result, direct_call_abi */
  RC Rc = RC_SUCCESS;
  ElmcValue *owned[2] = {0};
  CATCH_BEGIN
    elmc_int_t __plan_state = 0;
    for (;;) {
      switch (__plan_state) {
        case 0:
          switch (elmc_union_tag_as_int(msg)) {
          case ELMC_UNION_MAIN_TICK: __plan_state = 2; break;
          case ELMC_UNION_MAIN_UPPRESSED: __plan_state = 4; break;
          case ELMC_UNION_MAIN_SELECTPRESSED: __plan_state = 6; break;
          case ELMC_UNION_MAIN_DOWNPRESSED: __plan_state = 8; break;
          case ELMC_UNION_MAIN_ACCELTAP: __plan_state = 10; break;
          default: __plan_state = 12; break;
        }
        break;
        case 2:
        owned[0] = elmc_tuple_second(msg);
        Rc = elmc_fn_Main_handlePlatformMsg(&owned[1], msg, model);
        CHECK_RC(Rc);
        __plan_state = 15; break;
        case 4:
        Rc = elmc_fn_Main_handlePlatformMsg(&owned[1], msg, model);
        CHECK_RC(Rc);
        __plan_state = 15; break;
        case 6:
        Rc = elmc_fn_Main_handlePlatformMsg(&owned[1], msg, model);
        CHECK_RC(Rc);
        __plan_state = 15; break;
        case 8:
        Rc = elmc_fn_Main_handlePlatformMsg(&owned[1], msg, model);
        CHECK_RC(Rc);
        __plan_state = 15; break;
        case 10:
        Rc = elmc_fn_Main_handlePlatformMsg(&owned[1], msg, model);
        CHECK_RC(Rc);
        __plan_state = 15; break;
        case 12:
        Rc = elmc_fn_Main_handleAppMsg(&owned[1], msg, model);
        CHECK_RC(Rc);
        __plan_state = 15; break;
        case 14:
        __plan_state = 15; break;
        case 15:
        *out = owned[1];
        owned[1] = NULL;
        __plan_state = -1; break;
        default:
        break;
      }
      if (__plan_state < 0) break;
    }
  CATCH_END;

  elmc_release_array_lifo(owned, 2);
  return Rc;
}

static RC elmc_fn_Main_handleAppMsg(ElmcValue **out, ElmcValue *msg, ElmcValue *model) {
  /* Ownership policy: borrow_arg, borrow_result, direct_call_abi */
  RC Rc = RC_SUCCESS;
  ElmcValue *owned[5] = {0};
  CATCH_BEGIN
    elmc_int_t plan_native_int_4 = 0;
    elmc_int_t plan_native_int_15 = 0;
    elmc_int_t __plan_state = 0;
    for (;;) {
      switch (__plan_state) {
        case 0:
          switch (elmc_union_tag_as_int(msg)) {
          case ELMC_UNION_MAIN_INCREMENT: __plan_state = 2; break;
          case ELMC_UNION_MAIN_DECREMENT: __plan_state = 4; break;
          case ELMC_UNION_MAIN_PROVIDETEMPERATURE: __plan_state = 6; break;
          case ELMC_UNION_MAIN_CURRENTTIMESTRING: __plan_state = 8; break;
          case ELMC_UNION_MAIN_CLOCKSTYLE24H: __plan_state = 10; break;
          case ELMC_UNION_MAIN_TIMEZONEISSET: __plan_state = 12; break;
          case ELMC_UNION_MAIN_TIMEZONENAME: __plan_state = 14; break;
          case ELMC_UNION_MAIN_WATCHMODELNAME: __plan_state = 16; break;
          case ELMC_UNION_MAIN_WATCHCOLORNAME: __plan_state = 18; break;
          case ELMC_UNION_MAIN_FIRMWAREVERSIONSTRING: __plan_state = 20; break;
          default: __plan_state = 22; break;
        }
        break;
        case 2:
        plan_native_int_4 = elmc_fn_Main_counterOf(model);
        Rc = elmc_new_int(&owned[3], plan_native_int_4 + 1);
        CHECK_RC(Rc);
        owned[2] = elmc_retain(owned[3]);
        elmc_release(owned[3]);
        owned[3] = NULL;
        Rc = elmc_fn_Main_temperatureOf(&owned[3], model);
        CHECK_RC(Rc);
        owned[1] = elmc_retain(owned[3]);
        elmc_release(owned[3]);
        owned[3] = NULL;
        owned[3] = elmc_retain(owned[2]);
        elmc_release(owned[2]);
        owned[2] = NULL;
        owned[2] = elmc_retain(owned[1]);
        elmc_release(owned[1]);
        owned[1] = NULL;
        ElmcValue *rec_values_10_87[2] = { owned[3], owned[2] };
        Rc = elmc_record_new_values_take(&owned[1], 2, rec_values_10_87);
        CHECK_RC(Rc);
        owned[3] = NULL;
        owned[2] = NULL;
        owned[3] = NULL;
        owned[2] = NULL;
        Rc = elmc_cmd0(&owned[2], ELMC_PEBBLE_CMD_NONE);
        CHECK_RC(Rc);
        Rc = elmc_tuple2(&owned[3], owned[1], owned[2]);
        CHECK_RC(Rc);
        elmc_release(owned[1]);
        owned[1] = NULL;
        elmc_release(owned[2]);
        owned[2] = NULL;
        owned[1] = owned[3];
        owned[3] = NULL;

        __plan_state = 25; break;
        case 4:
        plan_native_int_15 = elmc_fn_Main_counterOf(model);
        Rc = elmc_new_int(&owned[4], plan_native_int_15 - 1);
        CHECK_RC(Rc);
        owned[3] = elmc_retain(owned[4]);
        elmc_release(owned[4]);
        owned[4] = NULL;
        Rc = elmc_fn_Main_temperatureOf(&owned[4], model);
        CHECK_RC(Rc);
        owned[2] = elmc_retain(owned[4]);
        elmc_release(owned[4]);
        owned[4] = NULL;
        owned[4] = elmc_retain(owned[3]);
        elmc_release(owned[3]);
        owned[3] = NULL;
        owned[3] = elmc_retain(owned[2]);
        elmc_release(owned[2]);
        owned[2] = NULL;
        ElmcValue *rec_values_22_88[2] = { owned[4], owned[3] };
        Rc = elmc_record_new_values_take(&owned[2], 2, rec_values_22_88);
        CHECK_RC(Rc);
        owned[4] = NULL;
        owned[3] = NULL;
        owned[4] = NULL;
        owned[3] = NULL;
        Rc = elmc_cmd0(&owned[3], ELMC_PEBBLE_CMD_NONE);
        CHECK_RC(Rc);
        Rc = elmc_tuple2(&owned[4], owned[2], owned[3]);
        CHECK_RC(Rc);
        elmc_release(owned[2]);
        owned[2] = NULL;
        elmc_release(owned[3]);
        owned[3] = NULL;
        owned[1] = owned[4];
        owned[4] = NULL;

        __plan_state = 25; break;
        case 6:
        owned[2] = elmc_tuple_second(msg);
        elmc_int_t plan_call_int_27 = elmc_fn_Main_counterOf(model);
        Rc = elmc_new_int(&owned[4], plan_call_int_27);
        CHECK_RC(Rc);
        owned[3] = elmc_retain(owned[4]);
        elmc_release(owned[4]);
        owned[4] = NULL;
        owned[4] = elmc_retain(owned[2]);
        elmc_release(owned[2]);
        owned[2] = NULL;
        Rc = elmc_maybe_just_own(&owned[2], owned[4]);
        CHECK_RC(Rc);
        owned[4] = NULL;
        owned[4] = elmc_retain(owned[2]);
        elmc_release(owned[2]);
        owned[2] = NULL;
        owned[2] = elmc_retain(owned[3]);
        elmc_release(owned[3]);
        owned[3] = NULL;
        owned[3] = elmc_retain(owned[4]);
        elmc_release(owned[4]);
        owned[4] = NULL;
        ElmcValue *rec_values_35_89[2] = { owned[2], owned[3] };
        Rc = elmc_record_new_values_take(&owned[4], 2, rec_values_35_89);
        CHECK_RC(Rc);
        owned[2] = NULL;
        owned[3] = NULL;
        owned[2] = NULL;
        owned[3] = NULL;
        Rc = elmc_cmd0(&owned[2], ELMC_PEBBLE_CMD_NONE);
        CHECK_RC(Rc);
        Rc = elmc_tuple2(&owned[3], owned[4], owned[2]);
        CHECK_RC(Rc);
        elmc_release(owned[4]);
        owned[4] = NULL;
        elmc_release(owned[2]);
        owned[2] = NULL;
        owned[1] = owned[3];
        owned[3] = NULL;

        __plan_state = 25; break;
        case 8:
        owned[2] = elmc_tuple_second(msg);
        Rc = elmc_cmd0(&owned[3], ELMC_PEBBLE_CMD_NONE);
        CHECK_RC(Rc);
        owned[4] = elmc_retain(model);
        elmc_release(owned[2]);
        owned[2] = NULL;
        Rc = elmc_tuple2(&owned[2], owned[4], owned[3]);
        CHECK_RC(Rc);
        elmc_release(owned[4]);
        owned[4] = NULL;
        elmc_release(owned[3]);
        owned[3] = NULL;
        owned[1] = owned[2];
        owned[2] = NULL;

        __plan_state = 25; break;
        case 10:
        owned[2] = elmc_tuple_second(msg);
        Rc = elmc_cmd0(&owned[3], ELMC_PEBBLE_CMD_NONE);
        CHECK_RC(Rc);
        owned[4] = elmc_retain(model);
        elmc_release(owned[2]);
        owned[2] = NULL;
        Rc = elmc_tuple2(&owned[2], owned[4], owned[3]);
        CHECK_RC(Rc);
        elmc_release(owned[4]);
        owned[4] = NULL;
        elmc_release(owned[3]);
        owned[3] = NULL;
        owned[1] = owned[2];
        owned[2] = NULL;

        __plan_state = 25; break;
        case 12:
        owned[2] = elmc_tuple_second(msg);
        Rc = elmc_cmd0(&owned[3], ELMC_PEBBLE_CMD_NONE);
        CHECK_RC(Rc);
        owned[4] = elmc_retain(model);
        elmc_release(owned[2]);
        owned[2] = NULL;
        Rc = elmc_tuple2(&owned[2], owned[4], owned[3]);
        CHECK_RC(Rc);
        elmc_release(owned[4]);
        owned[4] = NULL;
        elmc_release(owned[3]);
        owned[3] = NULL;
        owned[1] = owned[2];
        owned[2] = NULL;

        __plan_state = 25; break;
        case 14:
        owned[2] = elmc_tuple_second(msg);
        Rc = elmc_cmd0(&owned[3], ELMC_PEBBLE_CMD_NONE);
        CHECK_RC(Rc);
        owned[4] = elmc_retain(model);
        elmc_release(owned[2]);
        owned[2] = NULL;
        Rc = elmc_tuple2(&owned[2], owned[4], owned[3]);
        CHECK_RC(Rc);
        elmc_release(owned[4]);
        owned[4] = NULL;
        elmc_release(owned[3]);
        owned[3] = NULL;
        owned[1] = owned[2];
        owned[2] = NULL;

        __plan_state = 25; break;
        case 16:
        owned[2] = elmc_tuple_second(msg);
        Rc = elmc_cmd0(&owned[3], ELMC_PEBBLE_CMD_NONE);
        CHECK_RC(Rc);
        owned[4] = elmc_retain(model);
        elmc_release(owned[2]);
        owned[2] = NULL;
        Rc = elmc_tuple2(&owned[2], owned[4], owned[3]);
        CHECK_RC(Rc);
        elmc_release(owned[4]);
        owned[4] = NULL;
        elmc_release(owned[3]);
        owned[3] = NULL;
        owned[1] = owned[2];
        owned[2] = NULL;

        __plan_state = 25; break;
        case 18:
        owned[2] = elmc_tuple_second(msg);
        Rc = elmc_cmd0(&owned[3], ELMC_PEBBLE_CMD_NONE);
        CHECK_RC(Rc);
        owned[4] = elmc_retain(model);
        elmc_release(owned[2]);
        owned[2] = NULL;
        Rc = elmc_tuple2(&owned[2], owned[4], owned[3]);
        CHECK_RC(Rc);
        elmc_release(owned[4]);
        owned[4] = NULL;
        elmc_release(owned[3]);
        owned[3] = NULL;
        owned[1] = owned[2];
        owned[2] = NULL;

        __plan_state = 25; break;
        case 20:
        owned[2] = elmc_tuple_second(msg);
        elmc_release(owned[2]);
        owned[2] = NULL;
        Rc = elmc_cmd0(&owned[2], ELMC_PEBBLE_CMD_NONE);
        CHECK_RC(Rc);
        owned[3] = elmc_retain(model);
        Rc = elmc_tuple2(&owned[0], owned[3], owned[2]);
        CHECK_RC(Rc);
        elmc_release(owned[3]);
        owned[3] = NULL;
        elmc_release(owned[2]);
        owned[2] = NULL;
        owned[1] = owned[0];
        owned[0] = NULL;

        __plan_state = 25; break;
        case 22:
        Rc = elmc_cmd0(&owned[2], ELMC_PEBBLE_CMD_NONE);
        CHECK_RC(Rc);
        owned[3] = elmc_retain(model);
        Rc = elmc_tuple2(&owned[0], owned[3], owned[2]);
        CHECK_RC(Rc);
        elmc_release(owned[3]);
        owned[3] = NULL;
        elmc_release(owned[2]);
        owned[2] = NULL;
        owned[1] = owned[0];
        owned[0] = NULL;

        __plan_state = 25; break;
        case 24:
        __plan_state = 25; break;
        case 25:
        *out = owned[1];
        owned[1] = NULL;
        __plan_state = -1; break;
        default:
        break;
      }
      if (__plan_state < 0) break;
    }
  CATCH_END;

  elmc_release_array_lifo(owned, 5);
  return Rc;
}

static RC elmc_fn_Main_handlePlatformMsg(ElmcValue **out, ElmcValue *msg, ElmcValue *model) {
  /* Ownership policy: borrow_arg, borrow_result, direct_call_abi */
  RC Rc = RC_SUCCESS;
  ElmcValue *owned[5] = {0};
  CATCH_BEGIN
    elmc_int_t plan_native_int_5 = 0;
    elmc_int_t plan_native_int_17 = 0;
    elmc_int_t plan_native_int_41 = 0;
    elmc_int_t plan_native_int_53 = 0;
    elmc_int_t __plan_state = 0;
    for (;;) {
      switch (__plan_state) {
        case 0:
          switch (elmc_union_tag_as_int(msg)) {
          case ELMC_UNION_MAIN_TICK: __plan_state = 2; break;
          case ELMC_UNION_MAIN_UPPRESSED: __plan_state = 4; break;
          case ELMC_UNION_MAIN_SELECTPRESSED: __plan_state = 6; break;
          case ELMC_UNION_MAIN_DOWNPRESSED: __plan_state = 8; break;
          case ELMC_UNION_MAIN_ACCELTAP: __plan_state = 10; break;
          default: __plan_state = 12; break;
        }
        break;
        case 2:
        owned[1] = elmc_tuple_second(msg);
        plan_native_int_5 = elmc_fn_Main_counterOf(model);
        elmc_int_t plan_call_int_6 = elmc_fn_Main_advanced(plan_native_int_5);
        Rc = elmc_new_int(&owned[2], plan_call_int_6);
        CHECK_RC(Rc);
        elmc_release(owned[1]);
        owned[1] = NULL;
        owned[1] = elmc_retain(owned[2]);
        elmc_release(owned[2]);
        owned[2] = NULL;
        Rc = elmc_fn_Main_temperatureOf(&owned[2], model);
        CHECK_RC(Rc);
        owned[0] = elmc_retain(owned[2]);
        elmc_release(owned[2]);
        owned[2] = NULL;
        owned[2] = elmc_retain(owned[1]);
        elmc_release(owned[1]);
        owned[1] = NULL;
        owned[1] = elmc_retain(owned[0]);
        elmc_release(owned[0]);
        owned[0] = NULL;
        ElmcValue *rec_values_11_90[2] = { owned[2], owned[1] };
        Rc = elmc_record_new_values_take(&owned[0], 2, rec_values_11_90);
        CHECK_RC(Rc);
        owned[2] = NULL;
        owned[1] = NULL;
        owned[2] = NULL;
        owned[1] = NULL;
        Rc = elmc_cmd1(&owned[2], ELMC_PEBBLE_CMD_TIMER_AFTER_MS, 1000);
        CHECK_RC(Rc);
        Rc = elmc_tuple2(&owned[1], owned[0], owned[2]);
        CHECK_RC(Rc);
        elmc_release(owned[0]);
        owned[0] = NULL;
        elmc_release(owned[2]);
        owned[2] = NULL;
        owned[0] = owned[1];
        owned[1] = NULL;

        __plan_state = 15; break;
        case 4:
        plan_native_int_17 = elmc_fn_Main_counterOf(model);
        Rc = elmc_new_int(&owned[3], plan_native_int_17 + 1);
        CHECK_RC(Rc);
        owned[2] = elmc_retain(owned[3]);
        Rc = elmc_fn_Main_temperatureOf(&owned[4], model);
        CHECK_RC(Rc);
        owned[1] = elmc_retain(owned[4]);
        elmc_release(owned[4]);
        owned[4] = NULL;
        owned[4] = elmc_retain(owned[2]);
        elmc_release(owned[2]);
        owned[2] = NULL;
        owned[2] = elmc_retain(owned[1]);
        elmc_release(owned[1]);
        owned[1] = NULL;
        ElmcValue *rec_values_24_91[2] = { owned[4], owned[2] };
        Rc = elmc_record_new_values_take(&owned[1], 2, rec_values_24_91);
        CHECK_RC(Rc);
        owned[4] = NULL;
        owned[2] = NULL;
        owned[4] = NULL;
        owned[2] = NULL;
        Rc = elmc_cmd2(&owned[4], ELMC_PEBBLE_CMD_STORAGE_WRITE_INT, 1, elmc_as_int(owned[3]));
        CHECK_RC(Rc);
        elmc_release(owned[3]);
        owned[3] = NULL;
        Rc = elmc_tuple2(&owned[2], owned[1], owned[4]);
        CHECK_RC(Rc);
        elmc_release(owned[1]);
        owned[1] = NULL;
        elmc_release(owned[4]);
        owned[4] = NULL;
        owned[0] = owned[2];
        owned[2] = NULL;

        __plan_state = 15; break;
        case 6:
        owned[3] = elmc_unit();
        ElmcValue *plan_ephemeral_box_16930 = elmc_new_int_take(2);
        Rc = elmc_tuple2(&owned[4], plan_ephemeral_box_16930, owned[3]);
        CHECK_RC(Rc);
        elmc_release(plan_ephemeral_box_16930);
        elmc_release(owned[3]);
        owned[3] = NULL;
        Rc = elmc_fn_Main_requestWeather(&owned[2], owned[4]);
        CHECK_RC(Rc);
        elmc_release(owned[4]);
        owned[4] = NULL;
        Rc = elmc_fn_Main_requestSystemInfo(&owned[3]);
        CHECK_RC(Rc);
        owned[4] = elmc_retain(owned[2]);
        elmc_release(owned[2]);
        owned[2] = NULL;
        owned[2] = elmc_retain(owned[3]);
        elmc_release(owned[3]);
        owned[3] = NULL;
        ElmcValue *plan_list_items_16946[2] = { owned[4], owned[2] };
        Rc = elmc_list_from_values_take(&owned[3], plan_list_items_16946, 2);
        CHECK_RC(Rc);
        owned[4] = NULL;
        owned[2] = NULL;
        owned[2] = elmc_cmd_batch(owned[3]);
        elmc_release(owned[3]);
        owned[3] = NULL;
        owned[3] = elmc_retain(model);
        Rc = elmc_tuple2(&owned[1], owned[3], owned[2]);
        CHECK_RC(Rc);
        elmc_release(owned[3]);
        owned[3] = NULL;
        elmc_release(owned[2]);
        owned[2] = NULL;
        owned[0] = owned[1];
        owned[1] = NULL;

        __plan_state = 15; break;
        case 8:
        plan_native_int_41 = elmc_fn_Main_counterOf(model);
        Rc = elmc_new_int(&owned[3], plan_native_int_41 - 1);
        CHECK_RC(Rc);
        owned[2] = elmc_retain(owned[3]);
        elmc_release(owned[3]);
        owned[3] = NULL;
        Rc = elmc_fn_Main_temperatureOf(&owned[3], model);
        CHECK_RC(Rc);
        owned[1] = elmc_retain(owned[3]);
        elmc_release(owned[3]);
        owned[3] = NULL;
        owned[3] = elmc_retain(owned[2]);
        elmc_release(owned[2]);
        owned[2] = NULL;
        owned[2] = elmc_retain(owned[1]);
        elmc_release(owned[1]);
        owned[1] = NULL;
        ElmcValue *rec_values_50_92[2] = { owned[3], owned[2] };
        Rc = elmc_record_new_values_take(&owned[1], 2, rec_values_50_92);
        CHECK_RC(Rc);
        owned[3] = NULL;
        owned[2] = NULL;
        owned[3] = NULL;
        owned[2] = NULL;
        Rc = elmc_cmd1(&owned[3], ELMC_PEBBLE_CMD_STORAGE_DELETE, 1);
        CHECK_RC(Rc);
        Rc = elmc_tuple2(&owned[2], owned[1], owned[3]);
        CHECK_RC(Rc);
        elmc_release(owned[1]);
        owned[1] = NULL;
        elmc_release(owned[3]);
        owned[3] = NULL;
        owned[0] = owned[2];
        owned[2] = NULL;

        __plan_state = 15; break;
        case 10:
        plan_native_int_53 = elmc_fn_Main_counterOf(model);
        Rc = elmc_new_int(&owned[3], plan_native_int_53 + 1);
        CHECK_RC(Rc);
        owned[2] = elmc_retain(owned[3]);
        elmc_release(owned[3]);
        owned[3] = NULL;
        Rc = elmc_fn_Main_temperatureOf(&owned[3], model);
        CHECK_RC(Rc);
        owned[1] = elmc_retain(owned[3]);
        elmc_release(owned[3]);
        owned[3] = NULL;
        owned[3] = elmc_retain(owned[2]);
        elmc_release(owned[2]);
        owned[2] = NULL;
        owned[2] = elmc_retain(owned[1]);
        elmc_release(owned[1]);
        owned[1] = NULL;
        ElmcValue *rec_values_63_93[2] = { owned[3], owned[2] };
        Rc = elmc_record_new_values_take(&owned[1], 2, rec_values_63_93);
        CHECK_RC(Rc);
        owned[3] = NULL;
        owned[2] = NULL;
        owned[3] = NULL;
        owned[2] = NULL;
        Rc = elmc_cmd0(&owned[2], ELMC_PEBBLE_CMD_NONE);
        CHECK_RC(Rc);
        Rc = elmc_tuple2(&owned[3], owned[1], owned[2]);
        CHECK_RC(Rc);
        elmc_release(owned[1]);
        owned[1] = NULL;
        elmc_release(owned[2]);
        owned[2] = NULL;
        owned[0] = owned[3];
        owned[3] = NULL;

        __plan_state = 15; break;
        case 12:
        Rc = elmc_cmd0(&owned[2], ELMC_PEBBLE_CMD_NONE);
        CHECK_RC(Rc);
        owned[3] = elmc_retain(model);
        Rc = elmc_tuple2(&owned[1], owned[3], owned[2]);
        CHECK_RC(Rc);
        elmc_release(owned[3]);
        owned[3] = NULL;
        elmc_release(owned[2]);
        owned[2] = NULL;
        owned[0] = owned[1];
        owned[1] = NULL;

        __plan_state = 15; break;
        case 14:
        __plan_state = 15; break;
        case 15:
        *out = owned[0];
        owned[0] = NULL;
        __plan_state = -1; break;
        default:
        break;
      }
      if (__plan_state < 0) break;
    }
  CATCH_END;

  elmc_release_array_lifo(owned, 5);
  return Rc;
}

RC elmc_fn_Main_subscriptions(ElmcValue **out, ElmcValue *_unused_0) {
  /* Ownership policy: borrow_arg, borrow_result, direct_call_abi */
  (void)_unused_0;
  RC Rc = RC_SUCCESS;
  ElmcValue *owned[11] = {0};
  CATCH_BEGIN
    /* plan block 0 */
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
    owned[5] = elmc_retain(owned[0]);
    owned[6] = elmc_retain(owned[1]);
    owned[7] = elmc_retain(owned[2]);
    owned[8] = elmc_retain(owned[3]);
    owned[9] = elmc_retain(owned[4]);
    ElmcValue *plan_list_items_16962[5] = { owned[5], owned[6], owned[7], owned[8], owned[9] };
    Rc = elmc_list_from_values_take(&owned[10], plan_list_items_16962, 5);
    CHECK_RC(Rc);
    owned[5] = NULL;
    owned[6] = NULL;
    owned[7] = NULL;
    owned[8] = NULL;
    owned[9] = NULL;
    *out = owned[10];
    owned[10] = NULL;
    elmc_release(owned[0]);
    owned[0] = NULL;
    elmc_release(owned[1]);
    owned[1] = NULL;
    elmc_release(owned[2]);
    owned[2] = NULL;
    elmc_release(owned[3]);
    owned[3] = NULL;
    elmc_release(owned[4]);
    owned[4] = NULL;
  CATCH_END;

  elmc_release_array_lifo(owned, 11);
  return Rc;
}

RC elmc_fn_Main_view(ElmcValue **out, ElmcValue *model) {
  /* Ownership policy: borrow_arg, borrow_result, direct_call_abi */
  // #region agent log
  elmc_agent_generated_probe(0xED998100);
  // #endregion

  RC Rc = RC_SUCCESS;
  enum { ELMC_OWNED_SLOT_COUNT = 119 };
  ElmcValue **owned = (ElmcValue **)elmc_calloc(ELMC_OWNED_SLOT_COUNT, sizeof(ElmcValue *), "owned_slots");
  if (!owned) return RC_ERR_OUT_OF_MEMORY;
  CATCH_BEGIN
    /* plan block 0 */
    Rc = elmc_render_cmd6_take(&owned[5], ELMC_RENDER_OP_CLEAR, ELMC_COLOR_WHITE, 0, 0, 0, 0, 0);
    CHECK_RC(Rc);
    Rc = elmc_tuple2_ints(&owned[6], ELMC_CONTEXT_STROKE_WIDTH, 3);
    CHECK_RC(Rc);
    Rc = elmc_tuple2_ints(&owned[7], ELMC_CONTEXT_ANTIALIASED, 1);
    CHECK_RC(Rc);
    ElmcValue *plan_ephemeral_box_16978 = elmc_new_int_take(ELMC_CONTEXT_STROKE_COLOR);
    ElmcValue *plan_ephemeral_box_16994 = elmc_new_int_take(ELMC_COLOR_BLACK);
    Rc = elmc_tuple2(&owned[10], plan_ephemeral_box_16978, plan_ephemeral_box_16994);
    CHECK_RC(Rc);
    elmc_release(plan_ephemeral_box_16978);
    elmc_release(plan_ephemeral_box_16994);
    ElmcValue *plan_ephemeral_box_17010 = elmc_new_int_take(ELMC_CONTEXT_FILL_COLOR);
    ElmcValue *plan_ephemeral_box_17026 = elmc_new_int_take(ELMC_COLOR_BLACK);
    Rc = elmc_tuple2(&owned[11], plan_ephemeral_box_17010, plan_ephemeral_box_17026);
    CHECK_RC(Rc);
    elmc_release(plan_ephemeral_box_17010);
    elmc_release(plan_ephemeral_box_17026);
    ElmcValue *plan_ephemeral_box_17042 = elmc_new_int_take(ELMC_CONTEXT_TEXT_COLOR);
    ElmcValue *plan_ephemeral_box_17058 = elmc_new_int_take(ELMC_COLOR_BLACK);
    Rc = elmc_tuple2(&owned[12], plan_ephemeral_box_17042, plan_ephemeral_box_17058);
    CHECK_RC(Rc);
    elmc_release(plan_ephemeral_box_17042);
    elmc_release(plan_ephemeral_box_17058);
    owned[8] = elmc_retain(owned[6]);
    owned[9] = elmc_retain(owned[7]);
    owned[13] = elmc_retain(owned[10]);
    owned[14] = elmc_retain(owned[11]);
    owned[15] = elmc_retain(owned[12]);
    ElmcValue *plan_list_items_17074[5] = { owned[8], owned[9], owned[13], owned[14], owned[15] };
    Rc = elmc_list_from_values_take(&owned[16], plan_list_items_17074, 5);
    CHECK_RC(Rc);
    owned[8] = NULL;
    owned[9] = NULL;
    owned[13] = NULL;
    owned[14] = NULL;
    owned[15] = NULL;
    Rc = elmc_render_cmd6_take(&owned[17], ELMC_RENDER_OP_ROUND_RECT, 6, 6, 132, 70, 6, ELMC_COLOR_BLACK);
    CHECK_RC(Rc);
    Rc = elmc_render_cmd6_take(&owned[18], ELMC_RENDER_OP_ARC, 20, 16, 36, 36, 0, 45000);
    CHECK_RC(Rc);
    Rc = elmc_new_int(&owned[20], 0);
    CHECK_RC(Rc);
    owned[21] = elmc_retain(owned[20]);
    Rc = elmc_new_int(&owned[22], 0);
    CHECK_RC(Rc);
    owned[23] = elmc_retain(owned[22]);
    owned[24] = elmc_retain(owned[21]);
    owned[25] = elmc_retain(owned[23]);
    elmc_int_t rec_values_51_94[2] = { elmc_as_int(owned[24]), elmc_as_int(owned[25]) };
    Rc = elmc_record_new_values_ints(&owned[26], 2, rec_values_51_94);
    CHECK_RC(Rc);
    elmc_release(owned[24]);
    owned[24] = NULL;
    elmc_release(owned[25]);
    owned[25] = NULL;
    Rc = elmc_new_int(&owned[24], 10);
    CHECK_RC(Rc);
    owned[25] = elmc_retain(owned[24]);
    Rc = elmc_new_int(&owned[27], 4);
    CHECK_RC(Rc);
    owned[28] = elmc_retain(owned[27]);
    owned[29] = elmc_retain(owned[25]);
    owned[30] = elmc_retain(owned[28]);
    elmc_int_t rec_values_58_95[2] = { elmc_as_int(owned[29]), elmc_as_int(owned[30]) };
    Rc = elmc_record_new_values_ints(&owned[31], 2, rec_values_58_95);
    CHECK_RC(Rc);
    elmc_release(owned[29]);
    owned[29] = NULL;
    elmc_release(owned[30]);
    owned[30] = NULL;
    Rc = elmc_new_int(&owned[29], 16);
    CHECK_RC(Rc);
    owned[30] = elmc_retain(owned[29]);
    Rc = elmc_new_int(&owned[32], 14);
    CHECK_RC(Rc);
    owned[33] = elmc_retain(owned[32]);
    owned[34] = elmc_retain(owned[30]);
    owned[35] = elmc_retain(owned[33]);
    elmc_int_t rec_values_65_96[2] = { elmc_as_int(owned[34]), elmc_as_int(owned[35]) };
    Rc = elmc_record_new_values_ints(&owned[36], 2, rec_values_65_96);
    CHECK_RC(Rc);
    elmc_release(owned[34]);
    owned[34] = NULL;
    elmc_release(owned[35]);
    owned[35] = NULL;
    Rc = elmc_new_int(&owned[34], 8);
    CHECK_RC(Rc);
    owned[35] = elmc_retain(owned[34]);
    Rc = elmc_new_int(&owned[37], 24);
    CHECK_RC(Rc);
    owned[38] = elmc_retain(owned[37]);
    owned[39] = elmc_retain(owned[35]);
    owned[40] = elmc_retain(owned[38]);
    elmc_int_t rec_values_72_97[2] = { elmc_as_int(owned[39]), elmc_as_int(owned[40]) };
    Rc = elmc_record_new_values_ints(&owned[41], 2, rec_values_72_97);
    CHECK_RC(Rc);
    elmc_release(owned[39]);
    owned[39] = NULL;
    elmc_release(owned[40]);
    owned[40] = NULL;
    Rc = elmc_new_int(&owned[39], 0);
    CHECK_RC(Rc);
    owned[40] = elmc_retain(owned[39]);
    Rc = elmc_new_int(&owned[42], 18);
    CHECK_RC(Rc);
    owned[43] = elmc_retain(owned[42]);
    owned[44] = elmc_retain(owned[40]);
    owned[45] = elmc_retain(owned[43]);
    elmc_int_t rec_values_79_98[2] = { elmc_as_int(owned[44]), elmc_as_int(owned[45]) };
    Rc = elmc_record_new_values_ints(&owned[46], 2, rec_values_79_98);
    CHECK_RC(Rc);
    elmc_release(owned[44]);
    owned[44] = NULL;
    elmc_release(owned[45]);
    owned[45] = NULL;
    owned[44] = elmc_retain(owned[26]);
    owned[45] = elmc_retain(owned[31]);
    owned[47] = elmc_retain(owned[36]);
    owned[48] = elmc_retain(owned[41]);
    owned[49] = elmc_retain(owned[46]);
    ElmcValue *plan_list_record_items_17090[5] = { owned[44], owned[45], owned[47], owned[48], owned[49] };
    Rc = elmc_list_from_record_array(&owned[50], plan_list_record_items_17090, 5);
    CHECK_RC(Rc);
    owned[44] = NULL;
    owned[45] = NULL;
    owned[47] = NULL;
    owned[48] = NULL;
    owned[49] = NULL;
    Rc = elmc_new_int(&owned[44], 86);
    CHECK_RC(Rc);
    owned[45] = elmc_retain(owned[44]);
    Rc = elmc_new_int(&owned[47], 16);
    CHECK_RC(Rc);
    owned[48] = elmc_retain(owned[47]);
    owned[49] = elmc_retain(owned[45]);
    owned[51] = elmc_retain(owned[48]);
    elmc_int_t rec_values_92_99[2] = { elmc_as_int(owned[49]), elmc_as_int(owned[51]) };
    Rc = elmc_record_new_values_ints(&owned[52], 2, rec_values_92_99);
    CHECK_RC(Rc);
    elmc_release(owned[49]);
    owned[49] = NULL;
    elmc_release(owned[51]);
    owned[51] = NULL;
    ElmcValue *plan_ephemeral_box_17106 = elmc_new_int_take(1);
    ElmcValue *plan_ephemeral_box_17122 = elmc_new_int_take(0);
    Rc = elmc_tuple2(&owned[53], plan_ephemeral_box_17106, plan_ephemeral_box_17122);
    CHECK_RC(Rc);
    elmc_release(plan_ephemeral_box_17106);
    elmc_release(plan_ephemeral_box_17122);
    Rc = elmc_fn_Pebble_Ui_path(&owned[49], owned[50], owned[52], owned[53]);
    CHECK_RC(Rc);
    elmc_release(owned[50]);
    owned[50] = NULL;
    elmc_release(owned[52]);
    owned[52] = NULL;
    elmc_release(owned[53]);
    owned[53] = NULL;
    ElmcValue *plan_ephemeral_box_17138 = elmc_new_int_take(ELMC_RENDER_OP_PATH_OUTLINE);
    Rc = elmc_tuple2(&owned[50], plan_ephemeral_box_17138, owned[49]);
    CHECK_RC(Rc);
    elmc_release(plan_ephemeral_box_17138);
    elmc_release(owned[49]);
    owned[49] = NULL;
    Rc = elmc_new_int(&owned[49], 0);
    CHECK_RC(Rc);
    owned[51] = elmc_retain(owned[49]);
    Rc = elmc_new_int(&owned[52], 0);
    CHECK_RC(Rc);
    owned[53] = elmc_retain(owned[52]);
    owned[54] = elmc_retain(owned[51]);
    owned[55] = elmc_retain(owned[53]);
    elmc_int_t rec_values_105_100[2] = { elmc_as_int(owned[54]), elmc_as_int(owned[55]) };
    Rc = elmc_record_new_values_ints(&owned[56], 2, rec_values_105_100);
    CHECK_RC(Rc);
    elmc_release(owned[54]);
    owned[54] = NULL;
    elmc_release(owned[55]);
    owned[55] = NULL;
    Rc = elmc_new_int(&owned[54], 8);
    CHECK_RC(Rc);
    owned[55] = elmc_retain(owned[54]);
    Rc = elmc_new_int(&owned[57], 6);
    CHECK_RC(Rc);
    owned[58] = elmc_retain(owned[57]);
    owned[59] = elmc_retain(owned[55]);
    owned[60] = elmc_retain(owned[58]);
    elmc_int_t rec_values_112_101[2] = { elmc_as_int(owned[59]), elmc_as_int(owned[60]) };
    Rc = elmc_record_new_values_ints(&owned[61], 2, rec_values_112_101);
    CHECK_RC(Rc);
    elmc_release(owned[59]);
    owned[59] = NULL;
    elmc_release(owned[60]);
    owned[60] = NULL;
    Rc = elmc_new_int(&owned[59], 6);
    CHECK_RC(Rc);
    owned[60] = elmc_retain(owned[59]);
    Rc = elmc_new_int(&owned[62], 14);
    CHECK_RC(Rc);
    owned[63] = elmc_retain(owned[62]);
    owned[64] = elmc_retain(owned[60]);
    owned[65] = elmc_retain(owned[63]);
    elmc_int_t rec_values_119_102[2] = { elmc_as_int(owned[64]), elmc_as_int(owned[65]) };
    Rc = elmc_record_new_values_ints(&owned[66], 2, rec_values_119_102);
    CHECK_RC(Rc);
    elmc_release(owned[64]);
    owned[64] = NULL;
    elmc_release(owned[65]);
    owned[65] = NULL;
    Rc = elmc_new_int(&owned[64], 2);
    CHECK_RC(Rc);
    owned[65] = elmc_retain(owned[64]);
    Rc = elmc_new_int(&owned[67], 20);
    CHECK_RC(Rc);
    owned[68] = elmc_retain(owned[67]);
    owned[69] = elmc_retain(owned[65]);
    owned[70] = elmc_retain(owned[68]);
    elmc_int_t rec_values_126_103[2] = { elmc_as_int(owned[69]), elmc_as_int(owned[70]) };
    Rc = elmc_record_new_values_ints(&owned[71], 2, rec_values_126_103);
    CHECK_RC(Rc);
    elmc_release(owned[69]);
    owned[69] = NULL;
    elmc_release(owned[70]);
    owned[70] = NULL;
    Rc = elmc_new_int(&owned[69], 0);
    CHECK_RC(Rc);
    owned[70] = elmc_retain(owned[69]);
    Rc = elmc_new_int(&owned[72], 14);
    CHECK_RC(Rc);
    owned[73] = elmc_retain(owned[72]);
    owned[74] = elmc_retain(owned[70]);
    owned[75] = elmc_retain(owned[73]);
    elmc_int_t rec_values_133_104[2] = { elmc_as_int(owned[74]), elmc_as_int(owned[75]) };
    Rc = elmc_record_new_values_ints(&owned[76], 2, rec_values_133_104);
    CHECK_RC(Rc);
    elmc_release(owned[74]);
    owned[74] = NULL;
    elmc_release(owned[75]);
    owned[75] = NULL;
    owned[74] = elmc_retain(owned[56]);
    owned[75] = elmc_retain(owned[61]);
    owned[77] = elmc_retain(owned[66]);
    owned[78] = elmc_retain(owned[71]);
    owned[79] = elmc_retain(owned[76]);
    ElmcValue *plan_list_record_items_17154[5] = { owned[74], owned[75], owned[77], owned[78], owned[79] };
    Rc = elmc_list_from_record_array(&owned[80], plan_list_record_items_17154, 5);
    CHECK_RC(Rc);
    owned[74] = NULL;
    owned[75] = NULL;
    owned[77] = NULL;
    owned[78] = NULL;
    owned[79] = NULL;
    Rc = elmc_new_int(&owned[74], 108);
    CHECK_RC(Rc);
    owned[75] = elmc_retain(owned[74]);
    Rc = elmc_new_int(&owned[77], 26);
    CHECK_RC(Rc);
    owned[78] = elmc_retain(owned[77]);
    owned[79] = elmc_retain(owned[75]);
    owned[81] = elmc_retain(owned[78]);
    elmc_int_t rec_values_146_105[2] = { elmc_as_int(owned[79]), elmc_as_int(owned[81]) };
    Rc = elmc_record_new_values_ints(&owned[82], 2, rec_values_146_105);
    CHECK_RC(Rc);
    elmc_release(owned[79]);
    owned[79] = NULL;
    elmc_release(owned[81]);
    owned[81] = NULL;
    ElmcValue *plan_ephemeral_box_17170 = elmc_new_int_take(1);
    ElmcValue *plan_ephemeral_box_17186 = elmc_new_int_take(0);
    Rc = elmc_tuple2(&owned[83], plan_ephemeral_box_17170, plan_ephemeral_box_17186);
    CHECK_RC(Rc);
    elmc_release(plan_ephemeral_box_17170);
    elmc_release(plan_ephemeral_box_17186);
    Rc = elmc_fn_Pebble_Ui_path(&owned[79], owned[80], owned[82], owned[83]);
    CHECK_RC(Rc);
    elmc_release(owned[80]);
    owned[80] = NULL;
    elmc_release(owned[82]);
    owned[82] = NULL;
    elmc_release(owned[83]);
    owned[83] = NULL;
    ElmcValue *plan_ephemeral_box_17202 = elmc_new_int_take(ELMC_RENDER_OP_PATH_FILLED);
    Rc = elmc_tuple2(&owned[80], plan_ephemeral_box_17202, owned[79]);
    CHECK_RC(Rc);
    elmc_release(plan_ephemeral_box_17202);
    elmc_release(owned[79]);
    owned[79] = NULL;
    Rc = elmc_new_int(&owned[79], 0);
    CHECK_RC(Rc);
    owned[81] = elmc_retain(owned[79]);
    Rc = elmc_new_int(&owned[82], 0);
    CHECK_RC(Rc);
    owned[83] = elmc_retain(owned[82]);
    owned[84] = elmc_retain(owned[81]);
    owned[85] = elmc_retain(owned[83]);
    elmc_int_t rec_values_159_106[2] = { elmc_as_int(owned[84]), elmc_as_int(owned[85]) };
    Rc = elmc_record_new_values_ints(&owned[86], 2, rec_values_159_106);
    CHECK_RC(Rc);
    elmc_release(owned[84]);
    owned[84] = NULL;
    elmc_release(owned[85]);
    owned[85] = NULL;
    Rc = elmc_new_int(&owned[84], 8);
    CHECK_RC(Rc);
    owned[85] = elmc_retain(owned[84]);
    Rc = elmc_new_int(&owned[87], 4);
    CHECK_RC(Rc);
    owned[88] = elmc_retain(owned[87]);
    owned[89] = elmc_retain(owned[85]);
    owned[90] = elmc_retain(owned[88]);
    elmc_int_t rec_values_166_107[2] = { elmc_as_int(owned[89]), elmc_as_int(owned[90]) };
    Rc = elmc_record_new_values_ints(&owned[91], 2, rec_values_166_107);
    CHECK_RC(Rc);
    elmc_release(owned[89]);
    owned[89] = NULL;
    elmc_release(owned[90]);
    owned[90] = NULL;
    Rc = elmc_new_int(&owned[89], 16);
    CHECK_RC(Rc);
    owned[90] = elmc_retain(owned[89]);
    Rc = elmc_new_int(&owned[92], 2);
    CHECK_RC(Rc);
    owned[93] = elmc_retain(owned[92]);
    owned[94] = elmc_retain(owned[90]);
    owned[95] = elmc_retain(owned[93]);
    elmc_int_t rec_values_173_108[2] = { elmc_as_int(owned[94]), elmc_as_int(owned[95]) };
    Rc = elmc_record_new_values_ints(&owned[96], 2, rec_values_173_108);
    CHECK_RC(Rc);
    elmc_release(owned[94]);
    owned[94] = NULL;
    elmc_release(owned[95]);
    owned[95] = NULL;
    Rc = elmc_new_int(&owned[94], 24);
    CHECK_RC(Rc);
    owned[95] = elmc_retain(owned[94]);
    Rc = elmc_new_int(&owned[97], 6);
    CHECK_RC(Rc);
    owned[98] = elmc_retain(owned[97]);
    owned[99] = elmc_retain(owned[95]);
    owned[100] = elmc_retain(owned[98]);
    elmc_int_t rec_values_180_109[2] = { elmc_as_int(owned[99]), elmc_as_int(owned[100]) };
    Rc = elmc_record_new_values_ints(&owned[101], 2, rec_values_180_109);
    CHECK_RC(Rc);
    elmc_release(owned[99]);
    owned[99] = NULL;
    elmc_release(owned[100]);
    owned[100] = NULL;
    owned[99] = elmc_retain(owned[86]);
    owned[100] = elmc_retain(owned[91]);
    owned[102] = elmc_retain(owned[96]);
    owned[103] = elmc_retain(owned[101]);
    ElmcValue *plan_list_record_items_17218[4] = { owned[99], owned[100], owned[102], owned[103] };
    Rc = elmc_list_from_record_array(&owned[104], plan_list_record_items_17218, 4);
    CHECK_RC(Rc);
    owned[99] = NULL;
    owned[100] = NULL;
    owned[102] = NULL;
    owned[103] = NULL;
    Rc = elmc_new_int(&owned[99], 10);
    CHECK_RC(Rc);
    owned[100] = elmc_retain(owned[99]);
    Rc = elmc_new_int(&owned[102], 78);
    CHECK_RC(Rc);
    owned[103] = elmc_retain(owned[102]);
    owned[105] = elmc_retain(owned[100]);
    owned[106] = elmc_retain(owned[103]);
    elmc_int_t rec_values_192_110[2] = { elmc_as_int(owned[105]), elmc_as_int(owned[106]) };
    Rc = elmc_record_new_values_ints(&owned[107], 2, rec_values_192_110);
    CHECK_RC(Rc);
    elmc_release(owned[105]);
    owned[105] = NULL;
    elmc_release(owned[106]);
    owned[106] = NULL;
    ElmcValue *plan_ephemeral_box_17234 = elmc_new_int_take(1);
    ElmcValue *plan_ephemeral_box_17250 = elmc_new_int_take(0);
    Rc = elmc_tuple2(&owned[108], plan_ephemeral_box_17234, plan_ephemeral_box_17250);
    CHECK_RC(Rc);
    elmc_release(plan_ephemeral_box_17234);
    elmc_release(plan_ephemeral_box_17250);
    Rc = elmc_fn_Pebble_Ui_path(&owned[105], owned[104], owned[107], owned[108]);
    CHECK_RC(Rc);
    elmc_release(owned[104]);
    owned[104] = NULL;
    elmc_release(owned[107]);
    owned[107] = NULL;
    elmc_release(owned[108]);
    owned[108] = NULL;
    ElmcValue *plan_ephemeral_box_17266 = elmc_new_int_take(ELMC_RENDER_OP_PATH_OUTLINE_OPEN);
    Rc = elmc_tuple2(&owned[104], plan_ephemeral_box_17266, owned[105]);
    CHECK_RC(Rc);
    elmc_release(plan_ephemeral_box_17266);
    elmc_release(owned[105]);
    owned[105] = NULL;
    owned[19] = elmc_retain(owned[17]);
    owned[105] = elmc_retain(owned[18]);
    owned[106] = elmc_retain(owned[50]);
    owned[107] = elmc_retain(owned[80]);
    owned[108] = elmc_retain(owned[104]);
    ElmcValue *plan_list_items_17282[5] = { owned[19], owned[105], owned[106], owned[107], owned[108] };
    Rc = elmc_list_from_values_take(&owned[109], plan_list_items_17282, 5);
    CHECK_RC(Rc);
    owned[19] = NULL;
    owned[105] = NULL;
    owned[106] = NULL;
    owned[107] = NULL;
    owned[108] = NULL;
    Rc = elmc_tuple2(&owned[19], owned[16], owned[109]);
    CHECK_RC(Rc);
    elmc_release(owned[16]);
    owned[16] = NULL;
    elmc_release(owned[109]);
    owned[109] = NULL;
    ElmcValue *plan_ephemeral_box_17298 = elmc_new_int_take(ELMC_RENDER_OP_CONTEXT_GROUP);
    Rc = elmc_tuple2(&owned[16], plan_ephemeral_box_17298, owned[19]);
    CHECK_RC(Rc);
    elmc_release(plan_ephemeral_box_17298);
    elmc_release(owned[19]);
    owned[19] = NULL;
    Rc = elmc_render_cmd6_take(&owned[108], ELMC_RENDER_OP_LINE, 0, 84, 143, 84, ELMC_COLOR_BLACK, 0);
    CHECK_RC(Rc);
    Rc = elmc_render_cmd6_take(&owned[110], ELMC_RENDER_OP_PIXEL, 72, 84, ELMC_COLOR_BLACK, 0, 0, 0);
    CHECK_RC(Rc);
    Rc = elmc_fn_Main_statusDraw(&owned[111], model);
    CHECK_RC(Rc);
    Rc = elmc_fn_Main_counterDraw(&owned[112], model);
    CHECK_RC(Rc);
    owned[0] = elmc_retain(owned[5]);
    owned[113] = elmc_retain(owned[16]);
    owned[114] = elmc_retain(owned[108]);
    owned[115] = elmc_retain(owned[110]);
    owned[116] = elmc_retain(owned[111]);
    owned[117] = elmc_retain(owned[112]);
    ElmcValue *plan_list_items_17314[6] = { owned[0], owned[113], owned[114], owned[115], owned[116], owned[117] };
    Rc = elmc_list_from_values_take(&owned[118], plan_list_items_17314, 6);
    CHECK_RC(Rc);
    owned[0] = NULL;
    owned[113] = NULL;
    owned[114] = NULL;
    owned[115] = NULL;
    owned[116] = NULL;
    owned[117] = NULL;
    ElmcValue *plan_ephemeral_box_17330 = elmc_new_int_take(1);
    Rc = elmc_tuple2(&owned[0], plan_ephemeral_box_17330, owned[118]);
    CHECK_RC(Rc);
    elmc_release(plan_ephemeral_box_17330);
    elmc_release(owned[118]);
    owned[118] = NULL;
    ElmcValue *plan_ephemeral_box_17346 = elmc_new_int_take(ELMC_UI_NODE_CANVAS_LAYER);
    Rc = elmc_tuple2(&owned[4], plan_ephemeral_box_17346, owned[0]);
    CHECK_RC(Rc);
    elmc_release(plan_ephemeral_box_17346);
    elmc_release(owned[0]);
    owned[0] = NULL;
    owned[0] = elmc_retain(owned[4]);
    ElmcValue *plan_list_items_17362[1] = { owned[0] };
    Rc = elmc_list_from_values_take(&owned[3], plan_list_items_17362, 1);
    CHECK_RC(Rc);
    owned[0] = NULL;
    ElmcValue *plan_ephemeral_box_17378 = elmc_new_int_take(1);
    Rc = elmc_tuple2(&owned[0], plan_ephemeral_box_17378, owned[3]);
    CHECK_RC(Rc);
    elmc_release(plan_ephemeral_box_17378);
    elmc_release(owned[3]);
    owned[3] = NULL;
    ElmcValue *plan_ephemeral_box_17394 = elmc_new_int_take(ELMC_UI_NODE_WINDOW);
    Rc = elmc_tuple2(&owned[2], plan_ephemeral_box_17394, owned[0]);
    CHECK_RC(Rc);
    elmc_release(plan_ephemeral_box_17394);
    elmc_release(owned[0]);
    owned[0] = NULL;
    owned[0] = elmc_retain(owned[2]);
    ElmcValue *plan_list_items_17410[1] = { owned[0] };
    Rc = elmc_list_from_values_take(&owned[1], plan_list_items_17410, 1);
    CHECK_RC(Rc);
    owned[0] = NULL;
    ElmcValue *plan_ephemeral_box_17426 = elmc_new_int_take(ELMC_UI_NODE_WINDOW_STACK);
    Rc = elmc_tuple2(out, plan_ephemeral_box_17426, owned[1]);
    CHECK_RC(Rc);
    elmc_release(plan_ephemeral_box_17426);
    elmc_release(owned[5]);
    owned[5] = NULL;
    elmc_release(owned[6]);
    owned[6] = NULL;
    elmc_release(owned[7]);
    owned[7] = NULL;
    elmc_release(owned[10]);
    owned[10] = NULL;
    elmc_release(owned[11]);
    owned[11] = NULL;
    elmc_release(owned[12]);
    owned[12] = NULL;
    elmc_release(owned[17]);
    owned[17] = NULL;
    elmc_release(owned[18]);
    owned[18] = NULL;
    elmc_release(owned[20]);
    owned[20] = NULL;
    elmc_release(owned[21]);
    owned[21] = NULL;
    elmc_release(owned[22]);
    owned[22] = NULL;
    elmc_release(owned[23]);
    owned[23] = NULL;
    elmc_release(owned[26]);
    owned[26] = NULL;
    elmc_release(owned[24]);
    owned[24] = NULL;
    elmc_release(owned[25]);
    owned[25] = NULL;
    elmc_release(owned[27]);
    owned[27] = NULL;
    elmc_release(owned[28]);
    owned[28] = NULL;
    elmc_release(owned[31]);
    owned[31] = NULL;
    elmc_release(owned[29]);
    owned[29] = NULL;
    elmc_release(owned[30]);
    owned[30] = NULL;
    elmc_release(owned[32]);
    owned[32] = NULL;
    elmc_release(owned[33]);
    owned[33] = NULL;
    elmc_release(owned[36]);
    owned[36] = NULL;
    elmc_release(owned[34]);
    owned[34] = NULL;
    elmc_release(owned[35]);
    owned[35] = NULL;
    elmc_release(owned[37]);
    owned[37] = NULL;
    elmc_release(owned[38]);
    owned[38] = NULL;
    elmc_release(owned[41]);
    owned[41] = NULL;
    elmc_release(owned[39]);
    owned[39] = NULL;
    elmc_release(owned[40]);
    owned[40] = NULL;
    elmc_release(owned[42]);
    owned[42] = NULL;
    elmc_release(owned[43]);
    owned[43] = NULL;
    elmc_release(owned[46]);
    owned[46] = NULL;
    elmc_release(owned[44]);
    owned[44] = NULL;
    elmc_release(owned[45]);
    owned[45] = NULL;
    elmc_release(owned[47]);
    owned[47] = NULL;
    elmc_release(owned[48]);
    owned[48] = NULL;
    elmc_release(owned[50]);
    owned[50] = NULL;
    elmc_release(owned[49]);
    owned[49] = NULL;
    elmc_release(owned[51]);
    owned[51] = NULL;
    elmc_release(owned[52]);
    owned[52] = NULL;
    elmc_release(owned[53]);
    owned[53] = NULL;
    elmc_release(owned[56]);
    owned[56] = NULL;
    elmc_release(owned[54]);
    owned[54] = NULL;
    elmc_release(owned[55]);
    owned[55] = NULL;
    elmc_release(owned[57]);
    owned[57] = NULL;
    elmc_release(owned[58]);
    owned[58] = NULL;
    elmc_release(owned[61]);
    owned[61] = NULL;
    elmc_release(owned[59]);
    owned[59] = NULL;
    elmc_release(owned[60]);
    owned[60] = NULL;
    elmc_release(owned[62]);
    owned[62] = NULL;
    elmc_release(owned[63]);
    owned[63] = NULL;
    elmc_release(owned[66]);
    owned[66] = NULL;
    elmc_release(owned[64]);
    owned[64] = NULL;
    elmc_release(owned[65]);
    owned[65] = NULL;
    elmc_release(owned[67]);
    owned[67] = NULL;
    elmc_release(owned[68]);
    owned[68] = NULL;
    elmc_release(owned[71]);
    owned[71] = NULL;
    elmc_release(owned[69]);
    owned[69] = NULL;
    elmc_release(owned[70]);
    owned[70] = NULL;
    elmc_release(owned[72]);
    owned[72] = NULL;
    elmc_release(owned[73]);
    owned[73] = NULL;
    elmc_release(owned[76]);
    owned[76] = NULL;
    elmc_release(owned[74]);
    owned[74] = NULL;
    elmc_release(owned[75]);
    owned[75] = NULL;
    elmc_release(owned[77]);
    owned[77] = NULL;
    elmc_release(owned[78]);
    owned[78] = NULL;
    elmc_release(owned[80]);
    owned[80] = NULL;
    elmc_release(owned[79]);
    owned[79] = NULL;
    elmc_release(owned[81]);
    owned[81] = NULL;
    elmc_release(owned[82]);
    owned[82] = NULL;
    elmc_release(owned[83]);
    owned[83] = NULL;
    elmc_release(owned[86]);
    owned[86] = NULL;
    elmc_release(owned[84]);
    owned[84] = NULL;
    elmc_release(owned[85]);
    owned[85] = NULL;
    elmc_release(owned[87]);
    owned[87] = NULL;
    elmc_release(owned[88]);
    owned[88] = NULL;
    elmc_release(owned[91]);
    owned[91] = NULL;
    elmc_release(owned[89]);
    owned[89] = NULL;
    elmc_release(owned[90]);
    owned[90] = NULL;
    elmc_release(owned[92]);
    owned[92] = NULL;
    elmc_release(owned[93]);
    owned[93] = NULL;
    elmc_release(owned[96]);
    owned[96] = NULL;
    elmc_release(owned[94]);
    owned[94] = NULL;
    elmc_release(owned[95]);
    owned[95] = NULL;
    elmc_release(owned[97]);
    owned[97] = NULL;
    elmc_release(owned[98]);
    owned[98] = NULL;
    elmc_release(owned[101]);
    owned[101] = NULL;
    elmc_release(owned[99]);
    owned[99] = NULL;
    elmc_release(owned[100]);
    owned[100] = NULL;
    elmc_release(owned[102]);
    owned[102] = NULL;
    elmc_release(owned[103]);
    owned[103] = NULL;
    elmc_release(owned[104]);
    owned[104] = NULL;
    elmc_release(owned[16]);
    owned[16] = NULL;
    elmc_release(owned[108]);
    owned[108] = NULL;
    elmc_release(owned[110]);
    owned[110] = NULL;
    elmc_release(owned[111]);
    owned[111] = NULL;
    elmc_release(owned[112]);
    owned[112] = NULL;
    elmc_release(owned[4]);
    owned[4] = NULL;
    elmc_release(owned[2]);
    owned[2] = NULL;
  CATCH_END;

  elmc_release_array_lifo(owned, ELMC_OWNED_SLOT_COUNT);
  elmc_free(owned);
  return Rc;
}

static RC elmc_fn_Main_temperatureValue(ElmcValue **out, ElmcValue *temperature) {
  /* Ownership policy: borrow_arg, borrow_result, direct_call_abi */
  RC Rc = RC_SUCCESS;
  ElmcValue *owned[2] = {0};
  CATCH_BEGIN
    /* plan block 0 */
    if (elmc_union_tag_as_int(temperature) != ELMC_UNION_COMPANION_TYPES_CELSIUS) {
      if (elmc_union_tag_as_int(temperature) == ELMC_UNION_COMPANION_TYPES_FAHRENHEIT) goto elmc_plan_block_4;
      else goto elmc_plan_block_6;
    }
    owned[0] = elmc_tuple_second(temperature);
    owned[1] = elmc_retain(owned[0]);
    goto elmc_plan_block_6;
    elmc_plan_block_4:
    elmc_release(owned[0]);
    owned[0] = NULL;
    owned[0] = elmc_tuple_second(temperature);
    elmc_release(owned[1]);
    owned[1] = NULL;
    owned[1] = elmc_retain(owned[0]);
    elmc_plan_block_6:
    *out = owned[1];
    owned[1] = NULL;
  CATCH_END;

  elmc_release_array_lifo(owned, 2);
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
  CATCH_BEGIN
    /* plan block 0 */
    Rc = elmc_new_int(out, 0);
    CHECK_RC(Rc);
  CATCH_END;

  return Rc;
}

static RC elmc_fn_Pebble_Platform_launchReasonToInt_native(ElmcValue **out, elmc_int_t launchReason) {
  RC Rc = RC_SUCCESS;
  CATCH_BEGIN
    elmc_int_t case_int_1;
    case_int_1 = 0;
    switch (launchReason) {
      case ELMC_UNION_LAUNCHSYSTEM: {
        case_int_1 = 0;
        break;
      }
      case ELMC_UNION_LAUNCHUSER: {
        case_int_1 = 1;
        break;
      }
      case ELMC_UNION_LAUNCHPHONE: {
        case_int_1 = 2;
        break;
      }
      case ELMC_UNION_LAUNCHWAKEUP: {
        case_int_1 = 3;
        break;
      }
      case ELMC_UNION_LAUNCHWORKER: {
        case_int_1 = 4;
        break;
      }
      case ELMC_UNION_LAUNCHQUICKLAUNCH: {
        case_int_1 = 5;
        break;
      }
      case ELMC_UNION_LAUNCHTIMELINEACTION: {
        case_int_1 = 6;
        break;
      }
      case ELMC_UNION_LAUNCHSMARTSTRAP: {
        case_int_1 = 7;
        break;
      }
      case ELMC_UNION_LAUNCHUNKNOWN: {
        case_int_1 = -1;
        break;
      }

    }
    Rc = elmc_new_int(out, case_int_1);
    CHECK_RC(Rc);
  CATCH_END
  return Rc;
}
static RC elmc_fn_Pebble_Platform_launchReasonToInt(ElmcValue **out, ElmcValue *launchReason) {
  /* Ownership policy: borrow_arg, borrow_result, direct_call_abi */
  return elmc_fn_Pebble_Platform_launchReasonToInt_native(out, (launchReason && (launchReason)->tag == ELMC_TAG_INT ? elmc_as_int(launchReason) : (launchReason && (launchReason)->tag == ELMC_TAG_TUPLE2 && (launchReason)->payload != NULL ? elmc_as_int(((ElmcTuple2 *)(launchReason)->payload)->first) : -1)));
}

static ElmcValue * elmc_fn_Pebble_Ui_windowStack(ElmcValue *windows) {
  /* Ownership policy: borrow_arg, retain_result, direct_call_abi */
  ElmcValue *owned[1] = {0};
  /* plan block 0 */
  owned[0] = elmc_retain(windows);
  return elmc_tuple2_take_value(elmc_new_int_take(1), owned[0]);
}

static ElmcValue * elmc_fn_Pebble_Ui_window(ElmcValue *id, ElmcValue *layers) {
  /* Ownership policy: borrow_arg, retain_result, direct_call_abi */
  ElmcValue *owned[3] = {0};
  /* plan block 0 */
  owned[2] = elmc_retain(id);
  owned[0] = elmc_retain(layers);
  owned[1] = elmc_tuple2_take_value(owned[2], owned[0]);
  elmc_release(owned[2]);
  owned[2] = NULL;
  elmc_release(owned[0]);
  owned[0] = NULL;
  return elmc_tuple2_take_value(elmc_new_int_take(1), owned[1]);
}

static ElmcValue * elmc_fn_Pebble_Ui_canvasLayer(ElmcValue *id, ElmcValue *ops) {
  /* Ownership policy: borrow_arg, retain_result, direct_call_abi */
  ElmcValue *owned[3] = {0};
  /* plan block 0 */
  owned[2] = elmc_retain(id);
  owned[0] = elmc_retain(ops);
  owned[1] = elmc_tuple2_take_value(owned[2], owned[0]);
  elmc_release(owned[2]);
  owned[2] = NULL;
  elmc_release(owned[0]);
  owned[0] = NULL;
  return elmc_tuple2_take_value(elmc_new_int_take(1), owned[1]);
}

static RC elmc_fn_Pebble_Ui_path(ElmcValue **out, ElmcValue *points, ElmcValue *offset, ElmcValue *rotation) {
  /* Ownership policy: borrow_arg, retain_result, direct_call_abi */
  RC Rc = RC_SUCCESS;
  ElmcValue *owned[4] = {0};
  CATCH_BEGIN
    /* plan block 0 */
    Rc = elmc_closure_new_rc(&owned[2], elmc_fn_Pebble_Ui_path_closure_0, 1, 0, NULL);
    CHECK_RC(Rc);
    Rc = elmc_list_map(&owned[3], owned[2], points);
    CHECK_RC(Rc);
    elmc_release(owned[2]);
    owned[2] = NULL;
    const elmc_int_t plan_native_int_5 = ELMC_RECORD_GET_INDEX_INT(offset, ELMC_FIELD_PEBBLE_UI_POINT_X);
    const elmc_int_t plan_native_int_6 = ELMC_RECORD_GET_INDEX_INT(offset, ELMC_FIELD_PEBBLE_UI_POINT_Y);
    ElmcValue *plan_ephemeral_box_17474 = elmc_new_int_take(plan_native_int_5);
    ElmcValue *plan_ephemeral_box_17490 = elmc_new_int_take(plan_native_int_6);
    Rc = elmc_tuple2(&owned[1], plan_ephemeral_box_17474, plan_ephemeral_box_17490);
    CHECK_RC(Rc);
    elmc_release(plan_ephemeral_box_17474);
    elmc_release(plan_ephemeral_box_17490);
    Rc = elmc_fn_Pebble_Ui_rotationToPebbleAngle(&owned[0]);
    CHECK_RC(Rc);
    ElmcValue *plan_closure_argv_17506[1] = { rotation };
    Rc = elmc_closure_call_rc(&owned[2], owned[0], plan_closure_argv_17506, 1);
    CHECK_RC(Rc);
    elmc_release(owned[0]);
    owned[0] = NULL;
    Rc = elmc_tuple2(&owned[0], owned[1], owned[2]);
    CHECK_RC(Rc);
    elmc_release(owned[1]);
    owned[1] = NULL;
    elmc_release(owned[2]);
    owned[2] = NULL;
    Rc = elmc_tuple2(out, owned[3], owned[0]);
    CHECK_RC(Rc);
  CATCH_END;

  elmc_release_array_lifo(owned, 4);
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

static RC elmc_fn_Companion_Internal_encodeLocationCode_native(ElmcValue **out, elmc_int_t value) {
  RC Rc = RC_SUCCESS;
  CATCH_BEGIN
    elmc_int_t case_int_1;
    case_int_1 = 0;
    switch (value) {
      case ELMC_UNION_COMPANION_TYPES_CURRENTLOCATION: {
        case_int_1 = 1;
        break;
      }
      case ELMC_UNION_COMPANION_TYPES_BERLIN: {
        case_int_1 = 2;
        break;
      }
      case ELMC_UNION_COMPANION_TYPES_ZURICH: {
        case_int_1 = 3;
        break;
      }
      case ELMC_UNION_COMPANION_TYPES_NEWYORK: {
        case_int_1 = 4;
        break;
      }

    }
    Rc = elmc_new_int(out, case_int_1);
    CHECK_RC(Rc);
  CATCH_END
  return Rc;
}
static RC elmc_fn_Companion_Internal_encodeLocationCode(ElmcValue **out, ElmcValue *value) {
  /* Ownership policy: borrow_arg, borrow_result, direct_call_abi */
  return elmc_fn_Companion_Internal_encodeLocationCode_native(out, (value && (value)->tag == ELMC_TAG_INT ? elmc_as_int(value) : (value && (value)->tag == ELMC_TAG_TUPLE2 && (value)->payload != NULL ? elmc_as_int(((ElmcTuple2 *)(value)->payload)->first) : -1)));
}

static RC elmc_fn_Companion_Internal_watchToPhoneTag(ElmcValue **out, ElmcValue *message) {
  /* Ownership policy: borrow_arg, borrow_result, direct_call_abi */
  RC Rc = RC_SUCCESS;
  ElmcValue *owned[2] = {0};
  CATCH_BEGIN
    /* plan block 0 */
    if (!elmc_union_tag_matches(message, ELMC_UNION_COMPANION_TYPES_REQUESTWEATHER)) {
      goto elmc_plan_block_4;
    }
    owned[1] = elmc_tuple_second(message);
    Rc = elmc_new_int(&owned[0], 2);
    CHECK_RC(Rc);
    elmc_release(owned[1]);
    owned[1] = NULL;
    owned[1] = owned[0];
    owned[0] = NULL;

    elmc_plan_block_4:
    *out = owned[1];
    owned[1] = NULL;
  CATCH_END;

  elmc_release_array_lifo(owned, 2);
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
  ElmcValue *owned[2] = {0};
  CATCH_BEGIN
    /* plan block 0 */
    if (!elmc_union_tag_matches(message, ELMC_UNION_COMPANION_TYPES_REQUESTWEATHER)) {
      goto elmc_plan_block_4;
    }
    owned[1] = elmc_tuple_second(message);
    Rc = elmc_fn_Companion_Internal_encodeLocationCode(&owned[0], owned[1]);
    CHECK_RC(Rc);
    elmc_plan_block_4:
    *out = owned[0];
    owned[0] = NULL;
  CATCH_END;

  elmc_release_array_lifo(owned, 2);
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
  ElmcValue *owned[2] = {0};

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

    Rc = elmc_fn_Main_temperatureOf(&owned[0], model);
    CHECK_RC(Rc);

    if (elmc_maybe_is_just(owned[0])) {

      ElmcValue *tmp_15 = elmc_int_zero();
      int64_t direct_i_16 = elmc_as_int_number(tmp_15);
      elmc_release(tmp_15);

      Rc = elmc_fn_Main_temperatureValue(&owned[1], elmc_maybe_or_tuple_just_payload_borrow(owned[0]));
      CHECK_RC(Rc);

      const elmc_int_t native_i_19 = elmc_as_int(owned[1]);

      elmc_draw_cmd_init(&scene_cmd, ELMC_RENDER_OP_TEXT_INT_WITH_FONT);
      scene_cmd.p0 = direct_i_16;
      scene_cmd.p1 = 0;
      scene_cmd.p2 = 28;
      scene_cmd.p3 = native_i_19;
      Rc = elmc_scene_writer_push_cmd(writer, &scene_cmd);
      CHECK_RC(Rc);

    }
    else if (elmc_maybe_is_nothing(owned[0])) {

      ElmcValue *tmp_21 = elmc_int_zero();
      int64_t direct_i_22 = elmc_as_int_number(tmp_21);
      elmc_release(tmp_21);

      ElmcValue *tmp_23 = elmc_int_zero();
      elmc_draw_cmd_init(&scene_cmd, ELMC_RENDER_OP_TEXT_LABEL_WITH_FONT);
      scene_cmd.p0 = direct_i_22;
      scene_cmd.p1 = 0;
      scene_cmd.p2 = 28;
      scene_cmd.p3 = 0;
      scene_cmd.p4 = 0;
      if (tmp_23 && tmp_23->tag == ELMC_TAG_STRING && tmp_23->payload) {
        const char *direct_text = (const char *)tmp_23->payload;
        int direct_text_i = 0;
        while (direct_text[direct_text_i] && direct_text_i < 63) {
          scene_cmd.text[direct_text_i] = direct_text[direct_text_i];
          direct_text_i++;
        }
        scene_cmd.text[direct_text_i] = '\0';

      }

      Rc = elmc_scene_writer_push_cmd(writer, &scene_cmd);
      CHECK_RC(Rc);
      elmc_release(tmp_23);

    }

    // inlined Main.counterOf
    const elmc_int_t direct_hoisted_int_24 = ELMC_RECORD_GET_INDEX_INT(model, ELMC_FIELD_MAIN_MODEL_VALUE);

    const elmc_int_t direct_native_let_counter_25 = direct_hoisted_int_24;
    ElmcValue *tmp_26 = elmc_int_zero();
    int64_t direct_i_27 = elmc_as_int_number(tmp_26);
    elmc_release(tmp_26);

    elmc_draw_cmd_init(&scene_cmd, ELMC_RENDER_OP_TEXT_INT_WITH_FONT);
    scene_cmd.p0 = direct_i_27;
    scene_cmd.p1 = 0;
    scene_cmd.p2 = 56;
    scene_cmd.p3 = direct_native_let_counter_25;
    Rc = elmc_scene_writer_push_cmd(writer, &scene_cmd);
    CHECK_RC(Rc);

  CATCH_END;
  elmc_release_array_lifo(owned, DIM(owned));

  return Rc;

}

RC elmc_fn_Main_view_scene_append(ElmcValue ** const args, const int argc, ElmcSceneWriter * const writer) {
  return elmc_fn_Main_view_commands_append(args, argc, writer);
}
