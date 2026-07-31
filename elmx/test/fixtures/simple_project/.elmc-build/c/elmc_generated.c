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
#define ELMC_UNION_MAYBE_NOTHING 2
#define ELMC_UNION_NEWYORK 4
#define ELMC_UNION_NOTHING 2
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
    case 1: return "Increment";
    case 2: return "Decrement";
    case 3: return "Tick";
    case 4: return "UpPressed";
    case 5: return "SelectPressed";
    case 6: return "DownPressed";
    case 7: return "AccelTap";
    case 8: return "ProvideTemperature";
    case 9: return "CurrentTimeString";
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
static RC elmc_fn_Pebble_Ui_rotationToPebbleAngle_native(elmc_int_t *out, ElmcValue * const patternArg);
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
RC elmc_fn_Main_subscriptions(ElmcValue **out, ElmcValue *ignoredArg);
RC elmc_fn_Main_view(ElmcValue **out, ElmcValue *model);
static RC elmc_fn_Main_temperatureValue(ElmcValue **out, ElmcValue *temperature);
static RC elmc_fn_Main_main(ElmcValue **out);
static RC elmc_fn_Pebble_Platform_launchReasonToInt(ElmcValue **out, ElmcValue *launchReason);
static ElmcValue *elmc_fn_Pebble_Ui_windowStack(ElmcValue *windows);
static ElmcValue *elmc_fn_Pebble_Ui_window(ElmcValue *id, ElmcValue *layers);
static ElmcValue *elmc_fn_Pebble_Ui_canvasLayer(ElmcValue *id, ElmcValue *ops);
static RC elmc_fn_Pebble_Ui_path(ElmcValue **out, ElmcValue *points, ElmcValue *offset, ElmcValue *rotation);
static RC elmc_fn_Pebble_Ui_rotationToPebbleAngle(ElmcValue **out, ElmcValue *patternArg);
static RC elmc_fn_Companion_Internal_encodeLocationCode(ElmcValue **out, ElmcValue *value);
static RC elmc_fn_Companion_Internal_watchToPhoneTag(ElmcValue **out, ElmcValue *message);
static RC elmc_fn_Companion_Internal_watchToPhoneValue(ElmcValue **out, ElmcValue *message);

static RC elmc_fn_Pebble_Ui_path_closure_0(ElmcValue **out, ElmcValue **args, int argc, ElmcValue **captures, int capture_count) {
  (void)captures;
  (void)capture_count;
  RC Rc = RC_SUCCESS;

  ElmcValue *owned[1] = {0};
  CATCH_BEGIN
    elmc_int_t plan_native_int_1 = 0;
    elmc_int_t plan_native_int_2 = 0;
    /* plan block 0 */
    CATCH_BEGIN
      plan_native_int_1 = ELMC_RECORD_GET_INDEX_INT((argc > 0 ? args[0] : NULL), ELMC_FIELD_PEBBLE_UI_POINT_X);
      plan_native_int_2 = ELMC_RECORD_GET_INDEX_INT((argc > 0 ? args[0] : NULL), ELMC_FIELD_PEBBLE_UI_POINT_Y);
      ElmcValue *plan_ephemeral_box_6514 = ELMC_RC_INT_BOX(plan_native_int_1);
      ElmcValue *plan_ephemeral_box_6530 = ELMC_RC_INT_BOX(plan_native_int_2);
      Rc = elmc_tuple2(&owned[0], plan_ephemeral_box_6514, plan_ephemeral_box_6530);
      CHECK_RC(Rc);
      elmc_release(plan_ephemeral_box_6514);
      elmc_release(plan_ephemeral_box_6530);
      *out = owned[0];
      owned[0] = NULL;
    CATCH_END
  CATCH_END

  elmc_release_array_lifo(owned, 1);
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
  elmc_int_t plan_native_int_4 = 0;
  elmc_int_t plan_native_int_5 = 0;
  bool plan_native_bool_3 = false;
  /* plan block 0 */
  plan_native_int_1 = elmc_fn_Main_helper(n);
  plan_native_bool_3 = (plan_native_int_1 > 10);
  if (plan_native_bool_3) goto elmc_plan_block_3;
  plan_native_int_4 = plan_native_int_1 + 1;
  elmc_plan_block_3:
  plan_native_int_5 = (plan_native_bool_3) ? plan_native_int_1 : plan_native_int_4;
  return plan_native_int_5;
}

static elmc_int_t elmc_fn_Main_counterOf(ElmcValue *model) {
  /* Ownership policy: borrow_arg, borrow_result, direct_call_abi */
  elmc_int_t plan_native_int_1 = 0;
  /* plan block 0 */
  plan_native_int_1 = ELMC_RECORD_GET_INDEX_INT(model, ELMC_FIELD_MAIN_MODEL_VALUE);
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
  CATCH_END
  elmc_release_array_lifo(owned, 1);
  return Rc;
}

static RC elmc_fn_Main_requestWeather(ElmcValue **out, ElmcValue *location) {
  /* Ownership policy: borrow_arg, borrow_result, direct_call_abi */
  RC Rc = RC_SUCCESS;
  ElmcValue *owned[16] = {0};
  CATCH_BEGIN
    /* plan block 0 */
    Rc = elmc_cmd0(&owned[0], ELMC_PEBBLE_CMD_COMPANION_SEND);
    CHECK_RC(Rc);
    Rc = elmc_new_int(&owned[1], 1);
    CHECK_RC(Rc);
    owned[3] = elmc_retain(location);
    Rc = elmc_tuple2(&owned[2], owned[1], owned[3]);
    CHECK_RC(Rc);
    Rc = elmc_fn_Companion_Internal_watchToPhoneTag(&owned[4], owned[2]);
    CHECK_RC(Rc);
    if (owned[4] == owned[2]) {
      owned[2] = NULL;
    }
    Rc = elmc_new_int(&owned[5], 1);
    CHECK_RC(Rc);
    owned[7] = elmc_retain(location);
    Rc = elmc_tuple2(&owned[6], owned[5], owned[7]);
    CHECK_RC(Rc);
    Rc = elmc_fn_Companion_Internal_watchToPhoneValue(&owned[8], owned[6]);
    CHECK_RC(Rc);
    if (owned[8] == owned[6]) {
      owned[6] = NULL;
    }
    Rc = elmc_new_int(&owned[9], 0);
    CHECK_RC(Rc);
    Rc = elmc_new_int(&owned[10], 0);
    CHECK_RC(Rc);
    Rc = elmc_tuple2_ints(&owned[11], 0, 0);
    CHECK_RC(Rc);
    Rc = elmc_tuple2(&owned[12], owned[10], owned[11]);
    CHECK_RC(Rc);
    Rc = elmc_tuple2(&owned[13], owned[9], owned[12]);
    CHECK_RC(Rc);
    Rc = elmc_tuple2(&owned[14], owned[8], owned[13]);
    CHECK_RC(Rc);
    Rc = elmc_tuple2(&owned[15], owned[4], owned[14]);
    CHECK_RC(Rc);
    Rc = elmc_tuple2(out, owned[0], owned[15]);
    CHECK_RC(Rc);
  CATCH_END
  elmc_release_array_lifo(owned, 16);
  return Rc;
}

static RC elmc_fn_Main_requestSystemInfo(ElmcValue **out) {
  /* Ownership policy: borrow_arg, borrow_result, direct_call_abi */
  RC Rc = RC_SUCCESS;
  ElmcValue *owned[15] = {0};
  CATCH_BEGIN
    /* plan block 0 */
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
    owned[7] = elmc_retain(owned[0]);
    owned[8] = elmc_retain(owned[1]);
    owned[9] = elmc_retain(owned[2]);
    owned[10] = elmc_retain(owned[3]);
    owned[11] = elmc_retain(owned[4]);
    owned[12] = elmc_retain(owned[5]);
    owned[13] = elmc_retain(owned[6]);
    ElmcValue *plan_list_items_6114[7] = { owned[7], owned[8], owned[9], owned[10], owned[11], owned[12], owned[13] };
    Rc = elmc_list_from_values_take(&owned[14], plan_list_items_6114, 7);
    CHECK_RC(Rc);
    owned[7] = NULL;
    owned[8] = NULL;
    owned[9] = NULL;
    owned[10] = NULL;
    owned[11] = NULL;
    owned[12] = NULL;
    owned[13] = NULL;
    Rc = elmc_cmd_batch(out, owned[14]);
    CHECK_RC(Rc);
  CATCH_END
  elmc_release_array_lifo(owned, 15);
  return Rc;
}

RC elmc_fn_Main_init(ElmcValue **out, ElmcValue *launchContext) {
  /* Ownership policy: borrow_arg, borrow_result, direct_call_abi */
  RC Rc = RC_SUCCESS;
  ElmcValue *owned[12] = {0};
  CATCH_BEGIN
    /* plan block 0 */
    owned[0] = elmc_record_get_index(launchContext, ELMC_FIELD_PEBBLE_PLATFORM_LAUNCHCONTEXT_REASON);
    Rc = elmc_fn_Pebble_Platform_launchReasonToInt(&owned[1], owned[0]);
    CHECK_RC(Rc);
    if (owned[1] == owned[0]) {
      owned[0] = NULL;
    }
    owned[3] = elmc_retain(owned[1]);
    owned[4] = elmc_maybe_nothing();
    ElmcValue *rec_values_8_76[2] = { owned[3], owned[4] };
    Rc = elmc_record_new_values_take(&owned[2], 2, rec_values_8_76);
    CHECK_RC(Rc);
    owned[3] = NULL;
    owned[4] = NULL;
    owned[3] = NULL;
    owned[4] = NULL;
    Rc = elmc_new_int(&owned[5], 2);
    CHECK_RC(Rc);
    owned[6] = elmc_unit();
    Rc = elmc_tuple2(&owned[7], owned[5], owned[6]);
    CHECK_RC(Rc);
    Rc = elmc_fn_Main_requestWeather(&owned[8], owned[7]);
    CHECK_RC(Rc);
    if (owned[8] == owned[7]) {
      owned[7] = NULL;
    }
    Rc = elmc_fn_Main_requestSystemInfo(&owned[9]);
    CHECK_RC(Rc);
    ElmcValue *plan_list_items_6130[2] = { owned[8], owned[9] };
    Rc = elmc_list_from_values_take(&owned[10], plan_list_items_6130, 2);
    CHECK_RC(Rc);
    owned[8] = NULL;
    owned[9] = NULL;
    Rc = elmc_cmd_batch(&owned[11], owned[10]);
    CHECK_RC(Rc);
    Rc = elmc_tuple2(out, owned[2], owned[11]);
    CHECK_RC(Rc);
  CATCH_END
  elmc_release_array_lifo(owned, 12);
  return Rc;
}

RC elmc_fn_Main_update(ElmcValue **out, ElmcValue *msg, ElmcValue *model) {
  /* Ownership policy: borrow_arg, borrow_result, direct_call_abi */
  RC Rc = RC_SUCCESS;
  ElmcValue *owned[2] = {0};
  CATCH_BEGIN
    /* plan block 0 */
    switch (elmc_union_tag_as_int(msg)) {
      case ELMC_UNION_MAIN_TICK: goto elmc_plan_block_2;
      case ELMC_UNION_MAIN_UPPRESSED: goto elmc_plan_block_4;
      case ELMC_UNION_MAIN_SELECTPRESSED: goto elmc_plan_block_6;
      case ELMC_UNION_MAIN_DOWNPRESSED: goto elmc_plan_block_8;
      case ELMC_UNION_MAIN_ACCELTAP: goto elmc_plan_block_10;
      default: goto elmc_plan_block_12;
    }
    elmc_plan_block_2:
    owned[1] = elmc_tuple_second_borrow(msg);
    Rc = elmc_fn_Main_handlePlatformMsg(&owned[0], msg, model);
    CHECK_RC(Rc);
    goto elmc_plan_block_15;
    elmc_plan_block_4:
    Rc = elmc_fn_Main_handlePlatformMsg(&owned[0], msg, model);
    CHECK_RC(Rc);
    goto elmc_plan_block_15;
    elmc_plan_block_6:
    Rc = elmc_fn_Main_handlePlatformMsg(&owned[0], msg, model);
    CHECK_RC(Rc);
    goto elmc_plan_block_15;
    elmc_plan_block_8:
    Rc = elmc_fn_Main_handlePlatformMsg(&owned[0], msg, model);
    CHECK_RC(Rc);
    goto elmc_plan_block_15;
    elmc_plan_block_10:
    Rc = elmc_fn_Main_handlePlatformMsg(&owned[0], msg, model);
    CHECK_RC(Rc);
    goto elmc_plan_block_15;
    elmc_plan_block_12:
    Rc = elmc_fn_Main_handleAppMsg(&owned[0], msg, model);
    CHECK_RC(Rc);
    elmc_plan_block_15:
    *out = owned[0];
    owned[0] = NULL;
  CATCH_END
  owned[1] = NULL;
  elmc_release_array_lifo(owned, 2);
  return Rc;
}

static __attribute__((noinline, noclone)) RC elmc_fn_Main_handleAppMsg(ElmcValue **out, ElmcValue *msg, ElmcValue *model) {
  /* Ownership policy: borrow_arg, borrow_result, direct_call_abi */
  RC Rc = RC_SUCCESS;
  enum { ELMC_OWNED_SLOT_COUNT = 34 };
  ElmcValue **owned = (ElmcValue **)elmc_calloc(ELMC_OWNED_SLOT_COUNT, sizeof(ElmcValue *), "owned_slots");
  if (!owned) return RC_ERR_OUT_OF_MEMORY;
  CATCH_BEGIN
    elmc_int_t plan_native_int_4 = 0;
    elmc_int_t plan_native_int_10 = 0;
    elmc_int_t plan_native_int_15 = 0;
    elmc_int_t plan_native_int_21 = 0;
    elmc_int_t plan_native_int_33 = 0;
    /* plan block 0 */
    switch (elmc_union_tag_as_int(msg)) {
      case ELMC_UNION_MAIN_INCREMENT: goto elmc_plan_block_2;
      case ELMC_UNION_MAIN_DECREMENT: goto elmc_plan_block_4;
      case ELMC_UNION_MAIN_PROVIDETEMPERATURE: goto elmc_plan_block_6;
      case ELMC_UNION_MAIN_CURRENTTIMESTRING: goto elmc_plan_block_8;
      case ELMC_UNION_MAIN_CLOCKSTYLE24H: goto elmc_plan_block_10;
      case ELMC_UNION_MAIN_TIMEZONEISSET: goto elmc_plan_block_12;
      case ELMC_UNION_MAIN_TIMEZONENAME: goto elmc_plan_block_14;
      case ELMC_UNION_MAIN_WATCHMODELNAME: goto elmc_plan_block_16;
      case ELMC_UNION_MAIN_WATCHCOLORNAME: goto elmc_plan_block_18;
      case ELMC_UNION_MAIN_FIRMWAREVERSIONSTRING: goto elmc_plan_block_20;
      default: goto elmc_plan_block_22;
    }
    elmc_plan_block_2:
    plan_native_int_4 = elmc_fn_Main_counterOf(model);
    plan_native_int_10 = plan_native_int_4 + 1;
    Rc = elmc_fn_Main_temperatureOf(&owned[2], model);
    CHECK_RC(Rc);
    ElmcValue *rec_values_10_77[2] = { ELMC_RC_INT_BOX(plan_native_int_10), owned[2] };
    Rc = elmc_record_new_values_take(&owned[1], 2, rec_values_10_77);
    CHECK_RC(Rc);
    owned[2] = NULL;
    owned[2] = NULL;
    owned[3] = elmc_cmd_none();
    Rc = elmc_tuple2(&owned[0], owned[1], owned[3]);
    CHECK_RC(Rc);
    goto elmc_plan_block_25;
    elmc_plan_block_4:
    plan_native_int_15 = elmc_fn_Main_counterOf(model);
    plan_native_int_21 = plan_native_int_15 - 1;
    Rc = elmc_fn_Main_temperatureOf(&owned[5], model);
    CHECK_RC(Rc);
    ElmcValue *rec_values_22_78[2] = { ELMC_RC_INT_BOX(plan_native_int_21), owned[5] };
    Rc = elmc_record_new_values_take(&owned[4], 2, rec_values_22_78);
    CHECK_RC(Rc);
    owned[5] = NULL;
    owned[5] = NULL;
    owned[6] = elmc_cmd_none();
    Rc = elmc_tuple2(&owned[0], owned[4], owned[6]);
    CHECK_RC(Rc);
    goto elmc_plan_block_25;
    elmc_plan_block_6:
    owned[7] = elmc_tuple_second_borrow(msg);
    plan_native_int_33 = elmc_fn_Main_counterOf(model);
    Rc = elmc_maybe_just(&owned[9], owned[7]);
    CHECK_RC(Rc);
    owned[7] = NULL;
    ElmcValue *rec_values_35_79[2] = { ELMC_RC_INT_BOX(plan_native_int_33), owned[9] };
    Rc = elmc_record_new_values_take(&owned[8], 2, rec_values_35_79);
    CHECK_RC(Rc);
    owned[9] = NULL;
    owned[9] = NULL;
    owned[10] = elmc_cmd_none();
    Rc = elmc_tuple2(&owned[0], owned[8], owned[10]);
    CHECK_RC(Rc);
    goto elmc_plan_block_25;
    elmc_plan_block_8:
    owned[11] = elmc_tuple_second_borrow(msg);
    owned[12] = elmc_cmd_none();
    owned[13] = elmc_retain(model);
    Rc = elmc_tuple2(&owned[0], owned[13], owned[12]);
    CHECK_RC(Rc);
    goto elmc_plan_block_25;
    elmc_plan_block_10:
    owned[14] = elmc_tuple_second_borrow(msg);
    owned[15] = elmc_cmd_none();
    owned[16] = elmc_retain(model);
    Rc = elmc_tuple2(&owned[0], owned[16], owned[15]);
    CHECK_RC(Rc);
    goto elmc_plan_block_25;
    elmc_plan_block_12:
    owned[17] = elmc_tuple_second_borrow(msg);
    owned[18] = elmc_cmd_none();
    owned[19] = elmc_retain(model);
    Rc = elmc_tuple2(&owned[0], owned[19], owned[18]);
    CHECK_RC(Rc);
    goto elmc_plan_block_25;
    elmc_plan_block_14:
    owned[20] = elmc_tuple_second_borrow(msg);
    owned[21] = elmc_cmd_none();
    owned[22] = elmc_retain(model);
    Rc = elmc_tuple2(&owned[0], owned[22], owned[21]);
    CHECK_RC(Rc);
    goto elmc_plan_block_25;
    elmc_plan_block_16:
    owned[23] = elmc_tuple_second_borrow(msg);
    owned[24] = elmc_cmd_none();
    owned[25] = elmc_retain(model);
    Rc = elmc_tuple2(&owned[0], owned[25], owned[24]);
    CHECK_RC(Rc);
    goto elmc_plan_block_25;
    elmc_plan_block_18:
    owned[26] = elmc_tuple_second_borrow(msg);
    owned[27] = elmc_cmd_none();
    owned[28] = elmc_retain(model);
    Rc = elmc_tuple2(&owned[0], owned[28], owned[27]);
    CHECK_RC(Rc);
    goto elmc_plan_block_25;
    elmc_plan_block_20:
    owned[29] = elmc_tuple_second_borrow(msg);
    owned[30] = elmc_cmd_none();
    owned[31] = elmc_retain(model);
    Rc = elmc_tuple2(&owned[0], owned[31], owned[30]);
    CHECK_RC(Rc);
    goto elmc_plan_block_25;
    elmc_plan_block_22:
    owned[32] = elmc_cmd_none();
    owned[33] = elmc_retain(model);
    Rc = elmc_tuple2(&owned[0], owned[33], owned[32]);
    CHECK_RC(Rc);
    elmc_plan_block_25:
    *out = owned[0];
    owned[0] = NULL;
  CATCH_END
  owned[11] = NULL;
  owned[14] = NULL;
  owned[17] = NULL;
  owned[20] = NULL;
  owned[23] = NULL;
  owned[26] = NULL;
  owned[29] = NULL;
  owned[7] = NULL;
  elmc_release_array_lifo(owned, ELMC_OWNED_SLOT_COUNT);
  elmc_free(owned);
  return Rc;
}

static RC elmc_fn_Main_handlePlatformMsg(ElmcValue **out, ElmcValue *msg, ElmcValue *model) {
  /* Ownership policy: borrow_arg, borrow_result, direct_call_abi */
  RC Rc = RC_SUCCESS;
  enum { ELMC_OWNED_SLOT_COUNT = 24 };
  ElmcValue **owned = (ElmcValue **)elmc_calloc(ELMC_OWNED_SLOT_COUNT, sizeof(ElmcValue *), "owned_slots");
  if (!owned) return RC_ERR_OUT_OF_MEMORY;
  CATCH_BEGIN
    elmc_int_t plan_native_int_5 = 0;
    elmc_int_t plan_native_int_11 = 0;
    elmc_int_t plan_native_int_17 = 0;
    elmc_int_t plan_native_int_18 = 0;
    elmc_int_t plan_native_int_41 = 0;
    elmc_int_t plan_native_int_47 = 0;
    elmc_int_t plan_native_int_53 = 0;
    elmc_int_t plan_native_int_59 = 0;
    /* plan block 0 */
    switch (elmc_union_tag_as_int(msg)) {
      case ELMC_UNION_MAIN_TICK: goto elmc_plan_block_2;
      case ELMC_UNION_MAIN_UPPRESSED: goto elmc_plan_block_4;
      case ELMC_UNION_MAIN_SELECTPRESSED: goto elmc_plan_block_6;
      case ELMC_UNION_MAIN_DOWNPRESSED: goto elmc_plan_block_8;
      case ELMC_UNION_MAIN_ACCELTAP: goto elmc_plan_block_10;
      default: goto elmc_plan_block_12;
    }
    elmc_plan_block_2:
    owned[1] = elmc_tuple_second_borrow(msg);
    plan_native_int_5 = elmc_fn_Main_counterOf(model);
    plan_native_int_11 = elmc_fn_Main_advanced(plan_native_int_5);
    Rc = elmc_fn_Main_temperatureOf(&owned[3], model);
    CHECK_RC(Rc);
    ElmcValue *rec_values_11_80[2] = { ELMC_RC_INT_BOX(plan_native_int_11), owned[3] };
    Rc = elmc_record_new_values_take(&owned[2], 2, rec_values_11_80);
    CHECK_RC(Rc);
    owned[3] = NULL;
    owned[3] = NULL;
    Rc = elmc_cmd1(&owned[4], ELMC_PEBBLE_CMD_TIMER_AFTER_MS, 1000);
    CHECK_RC(Rc);
    Rc = elmc_tuple2(&owned[0], owned[2], owned[4]);
    CHECK_RC(Rc);
    goto elmc_plan_block_15;
    elmc_plan_block_4:
    plan_native_int_17 = elmc_fn_Main_counterOf(model);
    plan_native_int_18 = plan_native_int_17 + 1;
    Rc = elmc_fn_Main_temperatureOf(&owned[6], model);
    CHECK_RC(Rc);
    ElmcValue *rec_values_24_81[2] = { ELMC_RC_INT_BOX(plan_native_int_18), owned[6] };
    Rc = elmc_record_new_values_take(&owned[5], 2, rec_values_24_81);
    CHECK_RC(Rc);
    owned[6] = NULL;
    owned[6] = NULL;
    Rc = elmc_cmd2(&owned[7], ELMC_PEBBLE_CMD_STORAGE_WRITE_INT, 1, plan_native_int_18);
    CHECK_RC(Rc);
    Rc = elmc_tuple2(&owned[0], owned[5], owned[7]);
    CHECK_RC(Rc);
    goto elmc_plan_block_15;
    elmc_plan_block_6:
    Rc = elmc_new_int(&owned[8], 2);
    CHECK_RC(Rc);
    owned[9] = elmc_unit();
    Rc = elmc_tuple2(&owned[10], owned[8], owned[9]);
    CHECK_RC(Rc);
    Rc = elmc_fn_Main_requestWeather(&owned[11], owned[10]);
    CHECK_RC(Rc);
    if (owned[11] == owned[10]) {
      owned[10] = NULL;
    }
    Rc = elmc_fn_Main_requestSystemInfo(&owned[12]);
    CHECK_RC(Rc);
    ElmcValue *plan_list_items_6146[2] = { owned[11], owned[12] };
    Rc = elmc_list_from_values_take(&owned[13], plan_list_items_6146, 2);
    CHECK_RC(Rc);
    owned[11] = NULL;
    owned[12] = NULL;
    Rc = elmc_cmd_batch(&owned[14], owned[13]);
    CHECK_RC(Rc);
    owned[15] = elmc_retain(model);
    Rc = elmc_tuple2(&owned[0], owned[15], owned[14]);
    CHECK_RC(Rc);
    goto elmc_plan_block_15;
    elmc_plan_block_8:
    plan_native_int_41 = elmc_fn_Main_counterOf(model);
    plan_native_int_47 = plan_native_int_41 - 1;
    Rc = elmc_fn_Main_temperatureOf(&owned[17], model);
    CHECK_RC(Rc);
    ElmcValue *rec_values_50_82[2] = { ELMC_RC_INT_BOX(plan_native_int_47), owned[17] };
    Rc = elmc_record_new_values_take(&owned[16], 2, rec_values_50_82);
    CHECK_RC(Rc);
    owned[17] = NULL;
    owned[17] = NULL;
    Rc = elmc_cmd1(&owned[18], ELMC_PEBBLE_CMD_STORAGE_DELETE, 1);
    CHECK_RC(Rc);
    Rc = elmc_tuple2(&owned[0], owned[16], owned[18]);
    CHECK_RC(Rc);
    goto elmc_plan_block_15;
    elmc_plan_block_10:
    plan_native_int_53 = elmc_fn_Main_counterOf(model);
    plan_native_int_59 = plan_native_int_53 + 1;
    Rc = elmc_fn_Main_temperatureOf(&owned[20], model);
    CHECK_RC(Rc);
    ElmcValue *rec_values_63_83[2] = { ELMC_RC_INT_BOX(plan_native_int_59), owned[20] };
    Rc = elmc_record_new_values_take(&owned[19], 2, rec_values_63_83);
    CHECK_RC(Rc);
    owned[20] = NULL;
    owned[20] = NULL;
    owned[21] = elmc_cmd_none();
    Rc = elmc_tuple2(&owned[0], owned[19], owned[21]);
    CHECK_RC(Rc);
    goto elmc_plan_block_15;
    elmc_plan_block_12:
    owned[22] = elmc_cmd_none();
    owned[23] = elmc_retain(model);
    Rc = elmc_tuple2(&owned[0], owned[23], owned[22]);
    CHECK_RC(Rc);
    elmc_plan_block_15:
    *out = owned[0];
    owned[0] = NULL;
  CATCH_END
  owned[1] = NULL;
  elmc_release_array_lifo(owned, ELMC_OWNED_SLOT_COUNT);
  elmc_free(owned);
  return Rc;
}

RC elmc_fn_Main_subscriptions(ElmcValue **out, ElmcValue *ignoredArg) {
  /* Ownership policy: borrow_arg, borrow_result, direct_call_abi */
  (void)ignoredArg;
  RC Rc = RC_SUCCESS;
  ElmcValue *owned[6] = {0};
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
    ElmcValue *plan_list_items_6162[5] = { owned[0], owned[1], owned[2], owned[3], owned[4] };
    Rc = elmc_list_from_values_take(&owned[5], plan_list_items_6162, 5);
    CHECK_RC(Rc);
    owned[0] = NULL;
    owned[1] = NULL;
    owned[2] = NULL;
    owned[3] = NULL;
    owned[4] = NULL;
    *out = owned[5];
    owned[5] = NULL;
  CATCH_END
  elmc_release_array_lifo(owned, 6);
  return Rc;
}

RC elmc_fn_Main_view(ElmcValue **out, ElmcValue *model) {
  /* Ownership policy: borrow_arg, borrow_result, direct_call_abi */
  // #region agent log
  elmc_agent_generated_probe(0xED998100);
  // #endregion

  RC Rc = RC_SUCCESS;
  enum { ELMC_OWNED_SLOT_COUNT = 65 };
  ElmcValue **owned = (ElmcValue **)elmc_calloc(ELMC_OWNED_SLOT_COUNT, sizeof(ElmcValue *), "owned_slots");
  if (!owned) return RC_ERR_OUT_OF_MEMORY;
  CATCH_BEGIN
    /* plan block 0 */
    Rc = elmc_new_int(&owned[0], 1);
    CHECK_RC(Rc);
    Rc = elmc_new_int(&owned[1], 1);
    CHECK_RC(Rc);
    Rc = elmc_render_cmd6_take(&owned[52], ELMC_RENDER_OP_CLEAR, ELMC_COLOR_WHITE, 0, 0, 0, 0, 0);
    CHECK_RC(Rc);
    Rc = elmc_tuple2_ints(&owned[4], ELMC_CONTEXT_STROKE_WIDTH, 3);
    CHECK_RC(Rc);
    Rc = elmc_tuple2_ints(&owned[2], ELMC_CONTEXT_ANTIALIASED, 1);
    CHECK_RC(Rc);
    ElmcValue *plan_ephemeral_box_6178 = ELMC_RC_INT_BOX(ELMC_CONTEXT_STROKE_COLOR);
    ElmcValue *plan_ephemeral_box_6194 = ELMC_RC_INT_BOX(ELMC_COLOR_BLACK);
    Rc = elmc_tuple2(&owned[6], plan_ephemeral_box_6178, plan_ephemeral_box_6194);
    CHECK_RC(Rc);
    elmc_release(plan_ephemeral_box_6178);
    elmc_release(plan_ephemeral_box_6194);
    ElmcValue *plan_ephemeral_box_6210 = ELMC_RC_INT_BOX(ELMC_CONTEXT_FILL_COLOR);
    ElmcValue *plan_ephemeral_box_6226 = ELMC_RC_INT_BOX(ELMC_COLOR_BLACK);
    Rc = elmc_tuple2(&owned[3], plan_ephemeral_box_6210, plan_ephemeral_box_6226);
    CHECK_RC(Rc);
    elmc_release(plan_ephemeral_box_6210);
    elmc_release(plan_ephemeral_box_6226);
    ElmcValue *plan_ephemeral_box_6242 = ELMC_RC_INT_BOX(ELMC_CONTEXT_TEXT_COLOR);
    ElmcValue *plan_ephemeral_box_6258 = ELMC_RC_INT_BOX(ELMC_COLOR_BLACK);
    Rc = elmc_tuple2(&owned[8], plan_ephemeral_box_6242, plan_ephemeral_box_6258);
    CHECK_RC(Rc);
    elmc_release(plan_ephemeral_box_6242);
    elmc_release(plan_ephemeral_box_6258);
    owned[5] = elmc_retain(owned[2]);
    owned[7] = elmc_retain(owned[3]);
    ElmcValue *plan_list_items_6274[5] = { owned[4], owned[5], owned[6], owned[7], owned[8] };
    Rc = elmc_list_from_values_take(&owned[9], plan_list_items_6274, 5);
    CHECK_RC(Rc);
    owned[4] = NULL;
    owned[5] = NULL;
    owned[6] = NULL;
    owned[7] = NULL;
    owned[8] = NULL;
    Rc = elmc_render_cmd6_take(&owned[10], ELMC_RENDER_OP_ROUND_RECT, 6, 6, 132, 70, 6, ELMC_COLOR_BLACK);
    CHECK_RC(Rc);
    Rc = elmc_render_cmd6_take(&owned[46], ELMC_RENDER_OP_ARC, 20, 16, 36, 36, 0, 45000);
    CHECK_RC(Rc);
    ElmcValue *rec_values_51_84[2] = { ELMC_RC_INT_BOX(0), elmc_retain(ELMC_RC_INT_BOX(0)) };
    Rc = elmc_record_new_values_take(&owned[11], 2, rec_values_51_84);
    CHECK_RC(Rc);
    ElmcValue *rec_values_58_85[2] = { ELMC_RC_INT_BOX(10), ELMC_RC_INT_BOX(4) };
    Rc = elmc_record_new_values_take(&owned[12], 2, rec_values_58_85);
    CHECK_RC(Rc);
    ElmcValue *rec_values_65_86[2] = { ELMC_RC_INT_BOX(16), ELMC_RC_INT_BOX(14) };
    Rc = elmc_record_new_values_take(&owned[13], 2, rec_values_65_86);
    CHECK_RC(Rc);
    ElmcValue *rec_values_72_87[2] = { ELMC_RC_INT_BOX(8), ELMC_RC_INT_BOX(24) };
    Rc = elmc_record_new_values_take(&owned[14], 2, rec_values_72_87);
    CHECK_RC(Rc);
    ElmcValue *rec_values_79_88[2] = { ELMC_RC_INT_BOX(0), ELMC_RC_INT_BOX(18) };
    Rc = elmc_record_new_values_take(&owned[15], 2, rec_values_79_88);
    CHECK_RC(Rc);
    ElmcValue *plan_list_record_items_6290[5] = { owned[11], owned[12], owned[13], owned[14], owned[15] };
    Rc = elmc_list_from_record_array(&owned[16], plan_list_record_items_6290, 5);
    CHECK_RC(Rc);
    owned[11] = NULL;
    owned[12] = NULL;
    owned[13] = NULL;
    owned[14] = NULL;
    owned[15] = NULL;
    ElmcValue *rec_values_92_89[2] = { ELMC_RC_INT_BOX(86), ELMC_RC_INT_BOX(16) };
    Rc = elmc_record_new_values_take(&owned[17], 2, rec_values_92_89);
    CHECK_RC(Rc);
    Rc = elmc_new_int(&owned[18], 1);
    CHECK_RC(Rc);
    Rc = elmc_new_int(&owned[19], 0);
    CHECK_RC(Rc);
    Rc = elmc_tuple2(&owned[20], owned[18], owned[19]);
    CHECK_RC(Rc);
    Rc = elmc_fn_Pebble_Ui_path(&owned[21], owned[16], owned[17], owned[20]);
    CHECK_RC(Rc);
    if (owned[21] == owned[16]) {
      owned[16] = NULL;
    }
    if (owned[21] == owned[17]) {
      owned[17] = NULL;
    }
    if (owned[21] == owned[20]) {
      owned[20] = NULL;
    }
    ElmcValue *plan_ephemeral_box_6306 = ELMC_RC_INT_BOX(ELMC_RENDER_OP_PATH_OUTLINE);
    Rc = elmc_tuple2(&owned[47], plan_ephemeral_box_6306, owned[21]);
    CHECK_RC(Rc);
    elmc_release(plan_ephemeral_box_6306);
    ElmcValue *rec_values_105_90[2] = { ELMC_RC_INT_BOX(0), elmc_retain(ELMC_RC_INT_BOX(0)) };
    Rc = elmc_record_new_values_take(&owned[23], 2, rec_values_105_90);
    CHECK_RC(Rc);
    Rc = elmc_new_int(&owned[22], 6);
    CHECK_RC(Rc);
    ElmcValue *rec_values_112_91[2] = { ELMC_RC_INT_BOX(8), owned[22] };
    Rc = elmc_record_new_values_take(&owned[24], 2, rec_values_112_91);
    CHECK_RC(Rc);
    owned[22] = NULL;
    ElmcValue *rec_values_119_92[2] = { ELMC_RC_INT_BOX(6), ELMC_RC_INT_BOX(14) };
    Rc = elmc_record_new_values_take(&owned[25], 2, rec_values_119_92);
    CHECK_RC(Rc);
    ElmcValue *rec_values_126_93[2] = { ELMC_RC_INT_BOX(2), ELMC_RC_INT_BOX(20) };
    Rc = elmc_record_new_values_take(&owned[26], 2, rec_values_126_93);
    CHECK_RC(Rc);
    ElmcValue *rec_values_133_94[2] = { ELMC_RC_INT_BOX(0), ELMC_RC_INT_BOX(14) };
    Rc = elmc_record_new_values_take(&owned[27], 2, rec_values_133_94);
    CHECK_RC(Rc);
    ElmcValue *plan_list_record_items_6322[5] = { owned[23], owned[24], owned[25], owned[26], owned[27] };
    Rc = elmc_list_from_record_array(&owned[28], plan_list_record_items_6322, 5);
    CHECK_RC(Rc);
    owned[23] = NULL;
    owned[24] = NULL;
    owned[25] = NULL;
    owned[26] = NULL;
    owned[27] = NULL;
    Rc = elmc_new_int(&owned[29], 26);
    CHECK_RC(Rc);
    ElmcValue *rec_values_146_95[2] = { ELMC_RC_INT_BOX(108), owned[29] };
    Rc = elmc_record_new_values_take(&owned[30], 2, rec_values_146_95);
    CHECK_RC(Rc);
    owned[29] = NULL;
    Rc = elmc_new_int(&owned[31], 1);
    CHECK_RC(Rc);
    Rc = elmc_new_int(&owned[32], 0);
    CHECK_RC(Rc);
    Rc = elmc_tuple2(&owned[33], owned[31], owned[32]);
    CHECK_RC(Rc);
    Rc = elmc_fn_Pebble_Ui_path(&owned[34], owned[28], owned[30], owned[33]);
    CHECK_RC(Rc);
    if (owned[34] == owned[28]) {
      owned[28] = NULL;
    }
    if (owned[34] == owned[30]) {
      owned[30] = NULL;
    }
    if (owned[34] == owned[33]) {
      owned[33] = NULL;
    }
    ElmcValue *plan_ephemeral_box_6338 = ELMC_RC_INT_BOX(ELMC_RENDER_OP_PATH_FILLED);
    Rc = elmc_tuple2(&owned[48], plan_ephemeral_box_6338, owned[34]);
    CHECK_RC(Rc);
    elmc_release(plan_ephemeral_box_6338);
    ElmcValue *rec_values_159_96[2] = { ELMC_RC_INT_BOX(0), elmc_retain(ELMC_RC_INT_BOX(0)) };
    Rc = elmc_record_new_values_take(&owned[35], 2, rec_values_159_96);
    CHECK_RC(Rc);
    ElmcValue *rec_values_166_97[2] = { ELMC_RC_INT_BOX(8), ELMC_RC_INT_BOX(4) };
    Rc = elmc_record_new_values_take(&owned[36], 2, rec_values_166_97);
    CHECK_RC(Rc);
    ElmcValue *rec_values_173_98[2] = { ELMC_RC_INT_BOX(16), ELMC_RC_INT_BOX(2) };
    Rc = elmc_record_new_values_take(&owned[37], 2, rec_values_173_98);
    CHECK_RC(Rc);
    ElmcValue *rec_values_180_99[2] = { ELMC_RC_INT_BOX(24), ELMC_RC_INT_BOX(6) };
    Rc = elmc_record_new_values_take(&owned[38], 2, rec_values_180_99);
    CHECK_RC(Rc);
    ElmcValue *plan_list_record_items_6354[4] = { owned[35], owned[36], owned[37], owned[38] };
    Rc = elmc_list_from_record_array(&owned[39], plan_list_record_items_6354, 4);
    CHECK_RC(Rc);
    owned[35] = NULL;
    owned[36] = NULL;
    owned[37] = NULL;
    owned[38] = NULL;
    ElmcValue *rec_values_192_100[2] = { ELMC_RC_INT_BOX(10), ELMC_RC_INT_BOX(78) };
    Rc = elmc_record_new_values_take(&owned[40], 2, rec_values_192_100);
    CHECK_RC(Rc);
    Rc = elmc_new_int(&owned[41], 1);
    CHECK_RC(Rc);
    Rc = elmc_new_int(&owned[42], 0);
    CHECK_RC(Rc);
    Rc = elmc_tuple2(&owned[43], owned[41], owned[42]);
    CHECK_RC(Rc);
    Rc = elmc_fn_Pebble_Ui_path(&owned[44], owned[39], owned[40], owned[43]);
    CHECK_RC(Rc);
    if (owned[44] == owned[39]) {
      owned[39] = NULL;
    }
    if (owned[44] == owned[40]) {
      owned[40] = NULL;
    }
    if (owned[44] == owned[43]) {
      owned[43] = NULL;
    }
    ElmcValue *plan_ephemeral_box_6370 = ELMC_RC_INT_BOX(ELMC_RENDER_OP_PATH_OUTLINE_OPEN);
    Rc = elmc_tuple2(&owned[49], plan_ephemeral_box_6370, owned[44]);
    CHECK_RC(Rc);
    elmc_release(plan_ephemeral_box_6370);
    owned[45] = owned[10];
    owned[10] = NULL;
    ElmcValue *plan_list_items_6386[5] = { owned[45], owned[46], owned[47], owned[48], owned[49] };
    Rc = elmc_list_from_values_take(&owned[50], plan_list_items_6386, 5);
    CHECK_RC(Rc);
    owned[45] = NULL;
    owned[46] = NULL;
    owned[47] = NULL;
    owned[48] = NULL;
    owned[49] = NULL;
    Rc = elmc_tuple2(&owned[51], owned[9], owned[50]);
    CHECK_RC(Rc);
    ElmcValue *plan_ephemeral_box_6402 = ELMC_RC_INT_BOX(ELMC_RENDER_OP_CONTEXT_GROUP);
    Rc = elmc_tuple2(&owned[53], plan_ephemeral_box_6402, owned[51]);
    CHECK_RC(Rc);
    elmc_release(plan_ephemeral_box_6402);
    Rc = elmc_render_cmd6_take(&owned[54], ELMC_RENDER_OP_LINE, 0, 84, 143, 84, ELMC_COLOR_BLACK, 0);
    CHECK_RC(Rc);
    Rc = elmc_render_cmd6_take(&owned[55], ELMC_RENDER_OP_PIXEL, 72, 84, ELMC_COLOR_BLACK, 0, 0, 0);
    CHECK_RC(Rc);
    Rc = elmc_fn_Main_statusDraw(&owned[56], model);
    CHECK_RC(Rc);
    Rc = elmc_fn_Main_counterDraw(&owned[57], model);
    CHECK_RC(Rc);
    ElmcValue *plan_list_items_6418[6] = { owned[52], owned[53], owned[54], owned[55], owned[56], owned[57] };
    Rc = elmc_list_from_values_take(&owned[58], plan_list_items_6418, 6);
    CHECK_RC(Rc);
    owned[52] = NULL;
    owned[53] = NULL;
    owned[54] = NULL;
    owned[55] = NULL;
    owned[56] = NULL;
    owned[57] = NULL;
    Rc = elmc_tuple2(&owned[59], owned[1], owned[58]);
    CHECK_RC(Rc);
    ElmcValue *plan_ephemeral_box_6434 = ELMC_RC_INT_BOX(ELMC_UI_NODE_CANVAS_LAYER);
    Rc = elmc_tuple2(&owned[60], plan_ephemeral_box_6434, owned[59]);
    CHECK_RC(Rc);
    elmc_release(plan_ephemeral_box_6434);
    ElmcValue *plan_list_items_6450[1] = { owned[60] };
    Rc = elmc_list_from_values_take(&owned[61], plan_list_items_6450, 1);
    CHECK_RC(Rc);
    owned[60] = NULL;
    Rc = elmc_tuple2(&owned[62], owned[0], owned[61]);
    CHECK_RC(Rc);
    ElmcValue *plan_ephemeral_box_6466 = ELMC_RC_INT_BOX(ELMC_UI_NODE_WINDOW);
    Rc = elmc_tuple2(&owned[63], plan_ephemeral_box_6466, owned[62]);
    CHECK_RC(Rc);
    elmc_release(plan_ephemeral_box_6466);
    ElmcValue *plan_list_items_6482[1] = { owned[63] };
    Rc = elmc_list_from_values_take(&owned[64], plan_list_items_6482, 1);
    CHECK_RC(Rc);
    owned[63] = NULL;
    ElmcValue *plan_ephemeral_box_6498 = ELMC_RC_INT_BOX(ELMC_UI_NODE_WINDOW_STACK);
    Rc = elmc_tuple2(out, plan_ephemeral_box_6498, owned[64]);
    CHECK_RC(Rc);
    elmc_release(plan_ephemeral_box_6498);
  CATCH_END
  elmc_release_array_lifo(owned, ELMC_OWNED_SLOT_COUNT);
  elmc_free(owned);
  return Rc;
}

static RC elmc_fn_Main_temperatureValue(ElmcValue **out, ElmcValue *temperature) {
  /* Ownership policy: borrow_arg, borrow_result, direct_call_abi */
  RC Rc = RC_SUCCESS;
  ElmcValue *owned[1] = {0};
  CATCH_BEGIN
    /* plan block 0 */
    if (elmc_union_tag_as_int(temperature) != ELMC_UNION_COMPANION_TYPES_CELSIUS) {
      if (elmc_union_tag_as_int(temperature) == ELMC_UNION_COMPANION_TYPES_FAHRENHEIT) goto elmc_plan_block_4;
      else goto elmc_plan_block_7;
    }
    owned[0] = elmc_tuple_second_borrow(temperature);
    goto elmc_plan_block_7;
    elmc_plan_block_4:
    owned[0] = elmc_tuple_second_borrow(temperature);
    elmc_plan_block_7:
    *out = owned[0];
    owned[0] = NULL;
  CATCH_END
  owned[0] = NULL;
  elmc_release_array_lifo(owned, 1);
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
  CATCH_END
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
  /* Ownership policy: borrow_arg, borrow_result, direct_call_abi */
  ElmcValue *owned[1] = {0};
  /* plan block 0 */
  owned[0] = elmc_retain(windows);
  {
    ElmcValue *__rc_ret = NULL;
    RC __alloc_rc = elmc_tuple2(&__rc_ret, ELMC_RC_INT_BOX(1), owned[0]);
    if (__alloc_rc != RC_SUCCESS) {
      ELMC_RC_LOG_FAIL(__alloc_rc, "elmc_tuple2", "allocation failed");
      return NULL;
    }
    return __rc_ret;
  }
  owned[0] = NULL;
}

static ElmcValue * elmc_fn_Pebble_Ui_window(ElmcValue *id, ElmcValue *layers) {
  /* Ownership policy: borrow_arg, borrow_result, direct_call_abi */
  ElmcValue *owned[3] = {0};
  /* plan block 0 */
  owned[1] = elmc_retain(id);
  owned[2] = elmc_retain(layers);
  owned[0] = NULL;
  {
    RC __alloc_rc = elmc_tuple2(&owned[0], owned[1], owned[2]);
    if (__alloc_rc != RC_SUCCESS) {
      ELMC_RC_LOG_FAIL(__alloc_rc, "elmc_tuple2", "allocation failed");
      owned[0] = NULL;;
    }
  }
  owned[1] = NULL;
  owned[2] = NULL;
  {
    ElmcValue *__rc_ret = NULL;
    RC __alloc_rc = elmc_tuple2(&__rc_ret, ELMC_RC_INT_BOX(1), owned[0]);
    if (__alloc_rc != RC_SUCCESS) {
      ELMC_RC_LOG_FAIL(__alloc_rc, "elmc_tuple2", "allocation failed");
      return NULL;
    }
    return __rc_ret;
  }
  owned[0] = NULL;
}

static ElmcValue * elmc_fn_Pebble_Ui_canvasLayer(ElmcValue *id, ElmcValue *ops) {
  /* Ownership policy: borrow_arg, borrow_result, direct_call_abi */
  ElmcValue *owned[3] = {0};
  /* plan block 0 */
  owned[1] = elmc_retain(id);
  owned[2] = elmc_retain(ops);
  owned[0] = NULL;
  {
    RC __alloc_rc = elmc_tuple2(&owned[0], owned[1], owned[2]);
    if (__alloc_rc != RC_SUCCESS) {
      ELMC_RC_LOG_FAIL(__alloc_rc, "elmc_tuple2", "allocation failed");
      owned[0] = NULL;;
    }
  }
  owned[1] = NULL;
  owned[2] = NULL;
  {
    ElmcValue *__rc_ret = NULL;
    RC __alloc_rc = elmc_tuple2(&__rc_ret, ELMC_RC_INT_BOX(1), owned[0]);
    if (__alloc_rc != RC_SUCCESS) {
      ELMC_RC_LOG_FAIL(__alloc_rc, "elmc_tuple2", "allocation failed");
      return NULL;
    }
    return __rc_ret;
  }
  owned[0] = NULL;
}

static RC elmc_fn_Pebble_Ui_path(ElmcValue **out, ElmcValue *points, ElmcValue *offset, ElmcValue *rotation) {
  /* Ownership policy: borrow_arg, borrow_result, direct_call_abi */
  RC Rc = RC_SUCCESS;
  ElmcValue *owned[5] = {0};
  CATCH_BEGIN
    elmc_int_t plan_native_int_5 = 0;
    elmc_int_t plan_native_int_6 = 0;
    /* plan block 0 */
    Rc = elmc_closure_new_rc(&owned[0], elmc_fn_Pebble_Ui_path_closure_0, 1, 0, NULL);
    CHECK_RC(Rc);
    /* elm/core: List.map */
    Rc = elmc_list_map(&owned[1], owned[0], points);
    CHECK_RC(Rc);
    plan_native_int_5 = ELMC_RECORD_GET_INDEX_INT(offset, ELMC_FIELD_PEBBLE_UI_POINT_X);
    plan_native_int_6 = ELMC_RECORD_GET_INDEX_INT(offset, ELMC_FIELD_PEBBLE_UI_POINT_Y);
    ElmcValue *plan_ephemeral_box_6546 = ELMC_RC_INT_BOX(plan_native_int_5);
    ElmcValue *plan_ephemeral_box_6562 = ELMC_RC_INT_BOX(plan_native_int_6);
    Rc = elmc_tuple2(&owned[2], plan_ephemeral_box_6546, plan_ephemeral_box_6562);
    CHECK_RC(Rc);
    elmc_release(plan_ephemeral_box_6546);
    elmc_release(plan_ephemeral_box_6562);
    Rc = elmc_fn_Pebble_Ui_rotationToPebbleAngle(&owned[3], rotation);
    CHECK_RC(Rc);
    Rc = elmc_tuple2(&owned[4], owned[2], owned[3]);
    CHECK_RC(Rc);
    Rc = elmc_tuple2(out, owned[1], owned[4]);
    CHECK_RC(Rc);
  CATCH_END
  elmc_release_array_lifo(owned, 5);
  return Rc;
}

static RC elmc_fn_Pebble_Ui_rotationToPebbleAngle(ElmcValue **out, ElmcValue *patternArg) {
  /* Ownership policy: borrow_arg, borrow_result, direct_call_abi */
  RC Rc = RC_SUCCESS;
  ElmcValue *owned[1] = {0};
  CATCH_BEGIN
    /* plan block 0 */
    owned[0] = elmc_tuple_second_borrow(patternArg);
    *out = owned[0];
    owned[0] = NULL;
  CATCH_END
  owned[0] = NULL;
  elmc_release_array_lifo(owned, 1);
  return Rc;
}
static RC elmc_fn_Pebble_Ui_rotationToPebbleAngle_native(elmc_int_t *out, ElmcValue * const patternArg) {
  ElmcValue *boxed = NULL;
  RC Rc = elmc_fn_Pebble_Ui_rotationToPebbleAngle(&boxed, patternArg);
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
    owned[1] = elmc_tuple_second_borrow(message);
    Rc = elmc_new_int(&owned[0], 2);
    CHECK_RC(Rc);
    *out = owned[0];
    owned[0] = NULL;
  CATCH_END
  owned[1] = NULL;
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
    owned[1] = elmc_tuple_second_borrow(message);
    Rc = elmc_fn_Companion_Internal_encodeLocationCode(&owned[0], owned[1]);
    CHECK_RC(Rc);
    *out = owned[0];
    owned[0] = NULL;
  CATCH_END
  owned[1] = NULL;
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
static RC elmc_fn_Main_statusDraw_commands_append(ElmcValue ** const args, const int argc, ElmcSceneWriter * const writer);

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

    ElmcValue *direct_call_args_13[1] = { model };
    Rc = elmc_fn_Main_statusDraw_commands_append(direct_call_args_13, 1, writer);
    CHECK_RC(Rc);

    const elmc_int_t native_call_14 = elmc_fn_Main_counterOf(model);

    Rc = elmc_new_int(&owned[0], native_call_14);
    CHECK_RC(Rc);

    Rc = elmc_new_int(&owned[1], 1);
    CHECK_RC(Rc);
    int64_t direct_i_15 = elmc_as_int_number(owned[1]);

    elmc_draw_cmd_init(&scene_cmd, ELMC_RENDER_OP_TEXT_INT_WITH_FONT);
    scene_cmd.p0 = direct_i_15;
    scene_cmd.p1 = 0;
    scene_cmd.p2 = 56;
    scene_cmd.p3 = elmc_as_int(owned[0]);
    Rc = elmc_scene_writer_push_cmd(writer, &scene_cmd);
    CHECK_RC(Rc);

  CATCH_END
  elmc_release_array_lifo(owned, DIM(owned));

  return Rc;

}

RC elmc_fn_Main_view_scene_append(ElmcValue ** const args, const int argc, ElmcSceneWriter * const writer) {
  return elmc_fn_Main_view_commands_append(args, argc, writer);
}

static RC elmc_fn_Main_statusDraw_commands_append(ElmcValue ** const args, const int argc, ElmcSceneWriter * const writer) {
  ElmcValue *model = (argc > 0) ? args[0] : NULL;

  if (!writer)
    return RC_ERR_INVALID_ARG;
  RC Rc = RC_SUCCESS;
  ElmcValue *owned[4] = {0};

  static ElmcPebbleDrawCmd scene_cmd;

  CATCH_BEGIN

    Rc = elmc_fn_Main_temperatureOf(&owned[0], model);
    CHECK_RC(Rc);

    if (elmc_maybe_is_just(owned[0])) {

      Rc = elmc_new_int(&owned[1], 1);
      CHECK_RC(Rc);
      int64_t direct_i_3 = elmc_as_int_number(owned[1]);

      Rc = elmc_fn_Main_temperatureValue(&owned[2], elmc_maybe_or_tuple_just_payload_borrow(owned[0]));
      CHECK_RC(Rc);

      const elmc_int_t native_i_6 = elmc_as_int(owned[2]);

      elmc_draw_cmd_init(&scene_cmd, ELMC_RENDER_OP_TEXT_INT_WITH_FONT);
      scene_cmd.p0 = direct_i_3;
      scene_cmd.p1 = 0;
      scene_cmd.p2 = 28;
      scene_cmd.p3 = native_i_6;
      Rc = elmc_scene_writer_push_cmd(writer, &scene_cmd);
      CHECK_RC(Rc);

    }
    else if (elmc_maybe_is_nothing(owned[0])) {

      Rc = elmc_new_int(&owned[3], 1);
      CHECK_RC(Rc);
      int64_t direct_i_8 = elmc_as_int_number(owned[3]);

      elmc_draw_cmd_init(&scene_cmd, ELMC_RENDER_OP_TEXT_LABEL_WITH_FONT);
      scene_cmd.p0 = direct_i_8;
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

  CATCH_END
  elmc_release_array_lifo(owned, DIM(owned));

  return Rc;

}
