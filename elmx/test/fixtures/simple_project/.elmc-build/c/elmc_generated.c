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
#define ELMC_UNION_COMPANION_TYPES_FAHRENHEIT 2
#define ELMC_UNION_COMPANION_TYPES_PROVIDETEMPERATURE 1
#define ELMC_UNION_COMPANION_TYPES_REQUESTWEATHER 1
#define ELMC_UNION_CURRENTTIMESTRING 9
#define ELMC_UNION_DECREMENT 2
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
#define ELMC_UNION_PEBBLE_TOUCH_DOWN 2
#define ELMC_UNION_PEBBLE_TOUCH_UP 1
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
#define ELMC_UNION_UPPRESSED 4
#define ELMC_UNION_WATCHCOLORNAME 14
#define ELMC_UNION_WATCHMODELNAME 13
#define ELMC_UNION_WINDOWNODE 1
#define ELMC_UNION_WINDOWSTACK 1

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
  ELMC_FIELD_PEBBLE_TOUCH_POINT_X = 0,
  ELMC_FIELD_PEBBLE_TOUCH_POINT_Y = 1,
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

static RC elmc_fn_Pebble_Platform_launchReasonToInt_native(ElmcValue **out, elmc_int_t launchReason);

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

static RC elmc_fn_Pebble_Ui_path_closure_0(ElmcValue **out, ElmcValue **args, int argc, ElmcValue **captures, int capture_count) {
  (void)captures;
  (void)capture_count;
  RC Rc = RC_SUCCESS;

  ElmcValue *owned[1] = {0};
  CATCH_BEGIN
    /* plan block 0 */
    CATCH_BEGIN
      const elmc_int_t plan_native_int_1 = ELMC_RECORD_GET_INDEX_INT((argc > 0 ? args[0] : NULL), ELMC_FIELD_PEBBLE_UI_POINT_X);
      const elmc_int_t plan_native_int_2 = ELMC_RECORD_GET_INDEX_INT((argc > 0 ? args[0] : NULL), ELMC_FIELD_PEBBLE_UI_POINT_Y);
      Rc = elmc_tuple2_ints(&owned[0], plan_native_int_1, plan_native_int_2);
      CHECK_RC(Rc);
      *out = owned[0];
      owned[0] = NULL;
    CATCH_END
  CATCH_END

  elmc_release_array_lifo(owned, DIM(owned));
  return Rc;
}

static elmc_int_t elmc_fn_Main_helper(elmc_int_t value) {
  /* Ownership policy: borrow_arg, borrow_result, direct_call_abi */
  /* plan block 0 */
  return value + 2;
}

static elmc_int_t elmc_fn_Main_advanced(elmc_int_t n) {
  /* Ownership policy: borrow_arg, borrow_result, direct_call_abi */
  elmc_int_t plan_native_int_1 __attribute__((unused)) = 0;
  elmc_int_t plan_native_int_4 __attribute__((unused)) = 0;
  bool plan_native_bool_3 = false;
  /* plan block 0 */
  plan_native_int_1 = elmc_fn_Main_helper(n);
  plan_native_bool_3 = (plan_native_int_1 > 10);
  if (plan_native_bool_3) goto elmc_plan_block_3;
  plan_native_int_4 = plan_native_int_1 + 1;
  elmc_plan_block_3:
  const elmc_int_t plan_native_int_5 = (plan_native_bool_3) ? plan_native_int_1 : plan_native_int_4;
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
  CATCH_END
  elmc_release_array_lifo(owned, DIM(owned));
  return Rc;
}

static RC elmc_fn_Main_requestWeather(ElmcValue **out, ElmcValue *location) {
  /* Ownership policy: borrow_arg, borrow_result, direct_call_abi */
  RC Rc = RC_SUCCESS;
  ElmcValue *owned[3] = {0};
  CATCH_BEGIN
    /* plan block 0 */
    Rc = elmc_new_int(&owned[0], 1);
    CHECK_RC(Rc);
    owned[2] = elmc_retain(location);
    Rc = elmc_tuple2(&owned[1], owned[0], owned[2]);
    CHECK_RC(Rc);
    Rc = elmc_cmd_companion_send_value(out, owned[1]);
    CHECK_RC(Rc);
  CATCH_END
  elmc_release_array_lifo(owned, DIM(owned));
  return Rc;
}

static RC elmc_fn_Main_requestSystemInfo(ElmcValue **out) {
  /* Ownership policy: borrow_arg, borrow_result, direct_call_abi */
  RC Rc = RC_SUCCESS;
  ElmcValue *owned[8] = {0};
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
    ElmcValue *plan_list_items_22626[7] = { owned[0], owned[1], owned[2], owned[3], owned[4], owned[5], owned[6] };
    Rc = elmc_list_from_values(&owned[7], plan_list_items_22626, 7);
    CHECK_RC(Rc);
    Rc = elmc_cmd_batch(out, owned[7]);
    CHECK_RC(Rc);
  CATCH_END
  elmc_release_array_lifo(owned, DIM(owned));
  return Rc;
}

RC elmc_fn_Main_init(ElmcValue **out, ElmcValue *launchContext) {
  /* Ownership policy: borrow_arg, borrow_result, direct_call_abi */
  RC Rc = RC_SUCCESS;
  ElmcValue *owned[10] = {0};
  CATCH_BEGIN
    /* plan block 0 */
    owned[0] = elmc_record_get_index(launchContext, ELMC_FIELD_PEBBLE_PLATFORM_LAUNCHCONTEXT_REASON);
    Rc = elmc_fn_Pebble_Platform_launchReasonToInt_native(&owned[1], (owned[0] && (owned[0])->tag == ELMC_TAG_INT ? elmc_as_int(owned[0]) : (owned[0] && (owned[0])->tag == ELMC_TAG_TUPLE2 && (owned[0])->payload != NULL ? elmc_as_int(((ElmcTuple2 *)(owned[0])->payload)->first) : -1)));
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
    Rc = elmc_fn_Main_requestWeather(&owned[6], owned[5]);
    CHECK_RC(Rc);
    if (owned[6] == owned[5]) {
      owned[5] = NULL;
    }
    Rc = elmc_fn_Main_requestSystemInfo(&owned[7]);
    CHECK_RC(Rc);
    ElmcValue *plan_list_items_22642[2] = { owned[6], owned[7] };
    Rc = elmc_list_from_values(&owned[8], plan_list_items_22642, 2);
    CHECK_RC(Rc);
    Rc = elmc_cmd_batch(&owned[9], owned[8]);
    CHECK_RC(Rc);
    Rc = elmc_tuple2(out, owned[2], owned[9]);
    CHECK_RC(Rc);
  CATCH_END
  elmc_release_array_lifo(owned, DIM(owned));
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
  elmc_release_array_lifo(owned, DIM(owned));
  return Rc;
}

static __attribute__((noinline, noclone)) RC elmc_fn_Main_handleAppMsg(ElmcValue **out, ElmcValue *msg, ElmcValue *model) {
  /* Ownership policy: borrow_arg, borrow_result, direct_call_abi */
  RC Rc = RC_SUCCESS;
  enum { ELMC_OWNED_SLOT_COUNT = 34 };
  ElmcValue **owned = elmc_owned_slots_acquire(ELMC_OWNED_SLOT_COUNT);
  if (!owned) return RC_ERR_OUT_OF_MEMORY;
  CATCH_BEGIN
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
    const elmc_int_t plan_native_int_4 = elmc_fn_Main_counterOf(model);
    const elmc_int_t plan_native_int_10 = plan_native_int_4 + 1;
    Rc = elmc_fn_Main_temperatureOf(&owned[2], model);
    CHECK_RC(Rc);
    ElmcValue *plan_ephemeral_box_22658 = NULL;
    Rc = elmc_new_int(&plan_ephemeral_box_22658, plan_native_int_10);
    CHECK_RC(Rc);
    ElmcValue *rec_values_10_77[2] = { plan_ephemeral_box_22658, owned[2] };
    Rc = elmc_record_new_values_take(&owned[1], 2, rec_values_10_77);
    CHECK_RC(Rc);
    owned[2] = NULL;
    owned[2] = NULL;
    owned[3] = elmc_cmd_none();
    Rc = elmc_tuple2(&owned[0], owned[1], owned[3]);
    CHECK_RC(Rc);
    goto elmc_plan_block_25;
    elmc_plan_block_4:
    const elmc_int_t plan_native_int_15 = elmc_fn_Main_counterOf(model);
    const elmc_int_t plan_native_int_21 = plan_native_int_15 - 1;
    Rc = elmc_fn_Main_temperatureOf(&owned[5], model);
    CHECK_RC(Rc);
    ElmcValue *plan_ephemeral_box_22674 = NULL;
    Rc = elmc_new_int(&plan_ephemeral_box_22674, plan_native_int_21);
    CHECK_RC(Rc);
    ElmcValue *rec_values_22_78[2] = { plan_ephemeral_box_22674, owned[5] };
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
    const elmc_int_t plan_native_int_33 = elmc_fn_Main_counterOf(model);
    Rc = elmc_maybe_just(&owned[9], owned[7]);
    CHECK_RC(Rc);
    owned[7] = NULL;
    ElmcValue *plan_ephemeral_box_22690 = NULL;
    Rc = elmc_new_int(&plan_ephemeral_box_22690, plan_native_int_33);
    CHECK_RC(Rc);
    ElmcValue *rec_values_35_79[2] = { plan_ephemeral_box_22690, owned[9] };
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
  elmc_owned_slots_release(owned, ELMC_OWNED_SLOT_COUNT);
  return Rc;
}

static RC elmc_fn_Main_handlePlatformMsg(ElmcValue **out, ElmcValue *msg, ElmcValue *model) {
  /* Ownership policy: borrow_arg, borrow_result, direct_call_abi */
  RC Rc = RC_SUCCESS;
  ElmcValue *owned[22] = {0};
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
    const elmc_int_t plan_native_int_5 = elmc_fn_Main_counterOf(model);
    const elmc_int_t plan_native_int_11 = elmc_fn_Main_advanced(plan_native_int_5);
    Rc = elmc_fn_Main_temperatureOf(&owned[3], model);
    CHECK_RC(Rc);
    ElmcValue *plan_ephemeral_box_22706 = NULL;
    Rc = elmc_new_int(&plan_ephemeral_box_22706, plan_native_int_11);
    CHECK_RC(Rc);
    ElmcValue *rec_values_11_80[2] = { plan_ephemeral_box_22706, owned[3] };
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
    const elmc_int_t plan_native_int_17 = elmc_fn_Main_counterOf(model);
    const elmc_int_t plan_native_int_18 = plan_native_int_17 + 1;
    Rc = elmc_fn_Main_temperatureOf(&owned[6], model);
    CHECK_RC(Rc);
    ElmcValue *plan_ephemeral_box_22722 = NULL;
    Rc = elmc_new_int(&plan_ephemeral_box_22722, plan_native_int_18);
    CHECK_RC(Rc);
    ElmcValue *rec_values_24_81[2] = { plan_ephemeral_box_22722, owned[6] };
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
    Rc = elmc_fn_Main_requestWeather(&owned[9], owned[8]);
    CHECK_RC(Rc);
    if (owned[9] == owned[8]) {
      owned[8] = NULL;
    }
    Rc = elmc_fn_Main_requestSystemInfo(&owned[10]);
    CHECK_RC(Rc);
    ElmcValue *plan_list_items_22738[2] = { owned[9], owned[10] };
    Rc = elmc_list_from_values(&owned[11], plan_list_items_22738, 2);
    CHECK_RC(Rc);
    Rc = elmc_cmd_batch(&owned[12], owned[11]);
    CHECK_RC(Rc);
    owned[13] = elmc_retain(model);
    Rc = elmc_tuple2(&owned[0], owned[13], owned[12]);
    CHECK_RC(Rc);
    goto elmc_plan_block_15;
    elmc_plan_block_8:
    const elmc_int_t plan_native_int_37 = elmc_fn_Main_counterOf(model);
    const elmc_int_t plan_native_int_43 = plan_native_int_37 - 1;
    Rc = elmc_fn_Main_temperatureOf(&owned[15], model);
    CHECK_RC(Rc);
    ElmcValue *plan_ephemeral_box_22754 = NULL;
    Rc = elmc_new_int(&plan_ephemeral_box_22754, plan_native_int_43);
    CHECK_RC(Rc);
    ElmcValue *rec_values_46_82[2] = { plan_ephemeral_box_22754, owned[15] };
    Rc = elmc_record_new_values_take(&owned[14], 2, rec_values_46_82);
    CHECK_RC(Rc);
    owned[15] = NULL;
    owned[15] = NULL;
    Rc = elmc_cmd1(&owned[16], ELMC_PEBBLE_CMD_STORAGE_DELETE, 1);
    CHECK_RC(Rc);
    Rc = elmc_tuple2(&owned[0], owned[14], owned[16]);
    CHECK_RC(Rc);
    goto elmc_plan_block_15;
    elmc_plan_block_10:
    const elmc_int_t plan_native_int_49 = elmc_fn_Main_counterOf(model);
    const elmc_int_t plan_native_int_55 = plan_native_int_49 + 1;
    Rc = elmc_fn_Main_temperatureOf(&owned[18], model);
    CHECK_RC(Rc);
    ElmcValue *plan_ephemeral_box_22770 = NULL;
    Rc = elmc_new_int(&plan_ephemeral_box_22770, plan_native_int_55);
    CHECK_RC(Rc);
    ElmcValue *rec_values_59_83[2] = { plan_ephemeral_box_22770, owned[18] };
    Rc = elmc_record_new_values_take(&owned[17], 2, rec_values_59_83);
    CHECK_RC(Rc);
    owned[18] = NULL;
    owned[18] = NULL;
    owned[19] = elmc_cmd_none();
    Rc = elmc_tuple2(&owned[0], owned[17], owned[19]);
    CHECK_RC(Rc);
    goto elmc_plan_block_15;
    elmc_plan_block_12:
    owned[20] = elmc_cmd_none();
    owned[21] = elmc_retain(model);
    Rc = elmc_tuple2(&owned[0], owned[21], owned[20]);
    CHECK_RC(Rc);
    elmc_plan_block_15:
    *out = owned[0];
    owned[0] = NULL;
  CATCH_END
  owned[1] = NULL;
  elmc_release_array_lifo(owned, DIM(owned));
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
    ElmcValue *plan_list_items_22786[5] = { owned[0], owned[1], owned[2], owned[3], owned[4] };
    Rc = elmc_list_from_values(&owned[5], plan_list_items_22786, 5);
    CHECK_RC(Rc);
    *out = owned[5];
    owned[5] = NULL;
  CATCH_END
  elmc_release_array_lifo(owned, DIM(owned));
  return Rc;
}

RC elmc_fn_Main_view(ElmcValue **out, ElmcValue *model) {
  /* Ownership policy: borrow_arg, borrow_result, direct_call_abi */
  // #region agent log
  elmc_agent_generated_probe(0xED998100);
  // #endregion

  RC Rc = RC_SUCCESS;
  enum { ELMC_OWNED_SLOT_COUNT = 61 };
  ElmcValue **owned = elmc_owned_slots_acquire(ELMC_OWNED_SLOT_COUNT);
  if (!owned) return RC_ERR_OUT_OF_MEMORY;
  CATCH_BEGIN
    /* plan block 0 */
    Rc = elmc_new_int(&owned[0], 1);
    CHECK_RC(Rc);
    Rc = elmc_new_int(&owned[1], 1);
    CHECK_RC(Rc);
    Rc = elmc_render_cmd6_take(&owned[2], ELMC_RENDER_OP_CLEAR, ELMC_COLOR_WHITE, 0, 0, 0, 0, 0);
    CHECK_RC(Rc);
    Rc = elmc_tuple2_ints(&owned[3], ELMC_CONTEXT_STROKE_WIDTH, 3);
    CHECK_RC(Rc);
    Rc = elmc_tuple2_ints(&owned[4], ELMC_CONTEXT_ANTIALIASED, 1);
    CHECK_RC(Rc);
    ElmcValue *plan_ephemeral_box_22802 = NULL;
    Rc = elmc_new_int(&plan_ephemeral_box_22802, ELMC_CONTEXT_STROKE_COLOR);
    CHECK_RC(Rc);
    ElmcValue *plan_ephemeral_box_22818 = NULL;
    Rc = elmc_new_int(&plan_ephemeral_box_22818, ELMC_COLOR_BLACK);
    CHECK_RC(Rc);
    Rc = elmc_tuple2(&owned[5], plan_ephemeral_box_22802, plan_ephemeral_box_22818);
    CHECK_RC(Rc);
    elmc_release(plan_ephemeral_box_22802);
    elmc_release(plan_ephemeral_box_22818);
    ElmcValue *plan_ephemeral_box_22834 = NULL;
    Rc = elmc_new_int(&plan_ephemeral_box_22834, ELMC_CONTEXT_FILL_COLOR);
    CHECK_RC(Rc);
    ElmcValue *plan_ephemeral_box_22850 = NULL;
    Rc = elmc_new_int(&plan_ephemeral_box_22850, ELMC_COLOR_BLACK);
    CHECK_RC(Rc);
    Rc = elmc_tuple2(&owned[6], plan_ephemeral_box_22834, plan_ephemeral_box_22850);
    CHECK_RC(Rc);
    elmc_release(plan_ephemeral_box_22834);
    elmc_release(plan_ephemeral_box_22850);
    ElmcValue *plan_ephemeral_box_22866 = NULL;
    Rc = elmc_new_int(&plan_ephemeral_box_22866, ELMC_CONTEXT_TEXT_COLOR);
    CHECK_RC(Rc);
    ElmcValue *plan_ephemeral_box_22882 = NULL;
    Rc = elmc_new_int(&plan_ephemeral_box_22882, ELMC_COLOR_BLACK);
    CHECK_RC(Rc);
    Rc = elmc_tuple2(&owned[7], plan_ephemeral_box_22866, plan_ephemeral_box_22882);
    CHECK_RC(Rc);
    elmc_release(plan_ephemeral_box_22866);
    elmc_release(plan_ephemeral_box_22882);
    ElmcValue *plan_list_items_22898[5] = { owned[3], owned[4], owned[5], owned[6], owned[7] };
    Rc = elmc_list_from_values(&owned[8], plan_list_items_22898, 5);
    CHECK_RC(Rc);
    Rc = elmc_render_cmd6_take(&owned[9], ELMC_RENDER_OP_ROUND_RECT, 6, 6, 132, 70, 6, ELMC_COLOR_BLACK);
    CHECK_RC(Rc);
    Rc = elmc_render_cmd6_take(&owned[10], ELMC_RENDER_OP_ARC, 20, 16, 36, 36, 0, 45000);
    CHECK_RC(Rc);
    ElmcValue *rec_values_46_84[2] = { elmc_int_zero(), elmc_retain(elmc_int_zero()) };
    Rc = elmc_record_new_values_take(&owned[11], 2, rec_values_46_84);
    CHECK_RC(Rc);
    ElmcValue *plan_ephemeral_box_22914 = NULL;
    Rc = elmc_new_int(&plan_ephemeral_box_22914, 10);
    CHECK_RC(Rc);
    ElmcValue *plan_ephemeral_box_22930 = NULL;
    Rc = elmc_new_int(&plan_ephemeral_box_22930, 4);
    CHECK_RC(Rc);
    ElmcValue *rec_values_53_85[2] = { plan_ephemeral_box_22914, plan_ephemeral_box_22930 };
    Rc = elmc_record_new_values_take(&owned[12], 2, rec_values_53_85);
    CHECK_RC(Rc);
    ElmcValue *plan_ephemeral_box_22946 = NULL;
    Rc = elmc_new_int(&plan_ephemeral_box_22946, 16);
    CHECK_RC(Rc);
    ElmcValue *plan_ephemeral_box_22962 = NULL;
    Rc = elmc_new_int(&plan_ephemeral_box_22962, 14);
    CHECK_RC(Rc);
    ElmcValue *rec_values_60_86[2] = { plan_ephemeral_box_22946, plan_ephemeral_box_22962 };
    Rc = elmc_record_new_values_take(&owned[13], 2, rec_values_60_86);
    CHECK_RC(Rc);
    ElmcValue *plan_ephemeral_box_22978 = NULL;
    Rc = elmc_new_int(&plan_ephemeral_box_22978, 8);
    CHECK_RC(Rc);
    ElmcValue *plan_ephemeral_box_22994 = NULL;
    Rc = elmc_new_int(&plan_ephemeral_box_22994, 24);
    CHECK_RC(Rc);
    ElmcValue *rec_values_67_87[2] = { plan_ephemeral_box_22978, plan_ephemeral_box_22994 };
    Rc = elmc_record_new_values_take(&owned[14], 2, rec_values_67_87);
    CHECK_RC(Rc);
    ElmcValue *plan_ephemeral_box_23010 = NULL;
    Rc = elmc_new_int(&plan_ephemeral_box_23010, 18);
    CHECK_RC(Rc);
    ElmcValue *rec_values_74_88[2] = { elmc_int_zero(), plan_ephemeral_box_23010 };
    Rc = elmc_record_new_values_take(&owned[15], 2, rec_values_74_88);
    CHECK_RC(Rc);
    ElmcValue *plan_list_record_items_23026[5] = { owned[11], owned[12], owned[13], owned[14], owned[15] };
    Rc = elmc_list_from_record_array(&owned[16], plan_list_record_items_23026, 5);
    CHECK_RC(Rc);
    Rc = elmc_new_int(&owned[17], 16);
    CHECK_RC(Rc);
    ElmcValue *plan_ephemeral_box_23042 = NULL;
    Rc = elmc_new_int(&plan_ephemeral_box_23042, 86);
    CHECK_RC(Rc);
    ElmcValue *rec_values_82_89[2] = { plan_ephemeral_box_23042, owned[17] };
    Rc = elmc_record_new_values_take(&owned[18], 2, rec_values_82_89);
    CHECK_RC(Rc);
    owned[17] = NULL;
    Rc = elmc_new_int(&owned[19], 1);
    CHECK_RC(Rc);
    Rc = elmc_new_int(&owned[20], 0);
    CHECK_RC(Rc);
    Rc = elmc_tuple2(&owned[21], owned[19], owned[20]);
    CHECK_RC(Rc);
    Rc = elmc_fn_Pebble_Ui_path(&owned[22], owned[16], owned[18], owned[21]);
    CHECK_RC(Rc);
    if (owned[22] == owned[16]) {
      owned[16] = NULL;
    }
    if (owned[22] == owned[18]) {
      owned[18] = NULL;
    }
    if (owned[22] == owned[21]) {
      owned[21] = NULL;
    }
    ElmcValue *plan_ephemeral_box_23058 = NULL;
    Rc = elmc_new_int(&plan_ephemeral_box_23058, ELMC_RENDER_OP_PATH_OUTLINE);
    CHECK_RC(Rc);
    Rc = elmc_tuple2(&owned[23], plan_ephemeral_box_23058, owned[22]);
    CHECK_RC(Rc);
    elmc_release(plan_ephemeral_box_23058);
    ElmcValue *rec_values_95_90[2] = { elmc_int_zero(), elmc_retain(elmc_int_zero()) };
    Rc = elmc_record_new_values_take(&owned[24], 2, rec_values_95_90);
    CHECK_RC(Rc);
    ElmcValue *plan_ephemeral_box_23074 = NULL;
    Rc = elmc_new_int(&plan_ephemeral_box_23074, 8);
    CHECK_RC(Rc);
    ElmcValue *plan_ephemeral_box_23090 = NULL;
    Rc = elmc_new_int(&plan_ephemeral_box_23090, 6);
    CHECK_RC(Rc);
    ElmcValue *rec_values_102_91[2] = { plan_ephemeral_box_23074, plan_ephemeral_box_23090 };
    Rc = elmc_record_new_values_take(&owned[25], 2, rec_values_102_91);
    CHECK_RC(Rc);
    ElmcValue *plan_ephemeral_box_23106 = NULL;
    Rc = elmc_new_int(&plan_ephemeral_box_23106, 6);
    CHECK_RC(Rc);
    ElmcValue *plan_ephemeral_box_23122 = NULL;
    Rc = elmc_new_int(&plan_ephemeral_box_23122, 14);
    CHECK_RC(Rc);
    ElmcValue *rec_values_109_92[2] = { plan_ephemeral_box_23106, plan_ephemeral_box_23122 };
    Rc = elmc_record_new_values_take(&owned[26], 2, rec_values_109_92);
    CHECK_RC(Rc);
    ElmcValue *plan_ephemeral_box_23138 = NULL;
    Rc = elmc_new_int(&plan_ephemeral_box_23138, 2);
    CHECK_RC(Rc);
    ElmcValue *plan_ephemeral_box_23154 = NULL;
    Rc = elmc_new_int(&plan_ephemeral_box_23154, 20);
    CHECK_RC(Rc);
    ElmcValue *rec_values_116_93[2] = { plan_ephemeral_box_23138, plan_ephemeral_box_23154 };
    Rc = elmc_record_new_values_take(&owned[27], 2, rec_values_116_93);
    CHECK_RC(Rc);
    ElmcValue *plan_ephemeral_box_23170 = NULL;
    Rc = elmc_new_int(&plan_ephemeral_box_23170, 14);
    CHECK_RC(Rc);
    ElmcValue *rec_values_123_94[2] = { elmc_int_zero(), plan_ephemeral_box_23170 };
    Rc = elmc_record_new_values_take(&owned[28], 2, rec_values_123_94);
    CHECK_RC(Rc);
    ElmcValue *plan_list_record_items_23186[5] = { owned[24], owned[25], owned[26], owned[27], owned[28] };
    Rc = elmc_list_from_record_array(&owned[29], plan_list_record_items_23186, 5);
    CHECK_RC(Rc);
    ElmcValue *plan_ephemeral_box_23202 = NULL;
    Rc = elmc_new_int(&plan_ephemeral_box_23202, 108);
    CHECK_RC(Rc);
    ElmcValue *plan_ephemeral_box_23218 = NULL;
    Rc = elmc_new_int(&plan_ephemeral_box_23218, 26);
    CHECK_RC(Rc);
    ElmcValue *rec_values_131_95[2] = { plan_ephemeral_box_23202, plan_ephemeral_box_23218 };
    Rc = elmc_record_new_values_take(&owned[30], 2, rec_values_131_95);
    CHECK_RC(Rc);
    Rc = elmc_new_int(&owned[31], 1);
    CHECK_RC(Rc);
    Rc = elmc_new_int(&owned[32], 0);
    CHECK_RC(Rc);
    Rc = elmc_tuple2(&owned[33], owned[31], owned[32]);
    CHECK_RC(Rc);
    Rc = elmc_fn_Pebble_Ui_path(&owned[34], owned[29], owned[30], owned[33]);
    CHECK_RC(Rc);
    if (owned[34] == owned[29]) {
      owned[29] = NULL;
    }
    if (owned[34] == owned[30]) {
      owned[30] = NULL;
    }
    if (owned[34] == owned[33]) {
      owned[33] = NULL;
    }
    ElmcValue *plan_ephemeral_box_23234 = NULL;
    Rc = elmc_new_int(&plan_ephemeral_box_23234, ELMC_RENDER_OP_PATH_FILLED);
    CHECK_RC(Rc);
    Rc = elmc_tuple2(&owned[35], plan_ephemeral_box_23234, owned[34]);
    CHECK_RC(Rc);
    elmc_release(plan_ephemeral_box_23234);
    ElmcValue *rec_values_144_96[2] = { elmc_int_zero(), elmc_retain(elmc_int_zero()) };
    Rc = elmc_record_new_values_take(&owned[36], 2, rec_values_144_96);
    CHECK_RC(Rc);
    ElmcValue *plan_ephemeral_box_23250 = NULL;
    Rc = elmc_new_int(&plan_ephemeral_box_23250, 8);
    CHECK_RC(Rc);
    ElmcValue *plan_ephemeral_box_23266 = NULL;
    Rc = elmc_new_int(&plan_ephemeral_box_23266, 4);
    CHECK_RC(Rc);
    ElmcValue *rec_values_151_97[2] = { plan_ephemeral_box_23250, plan_ephemeral_box_23266 };
    Rc = elmc_record_new_values_take(&owned[37], 2, rec_values_151_97);
    CHECK_RC(Rc);
    ElmcValue *plan_ephemeral_box_23282 = NULL;
    Rc = elmc_new_int(&plan_ephemeral_box_23282, 16);
    CHECK_RC(Rc);
    ElmcValue *plan_ephemeral_box_23298 = NULL;
    Rc = elmc_new_int(&plan_ephemeral_box_23298, 2);
    CHECK_RC(Rc);
    ElmcValue *rec_values_158_98[2] = { plan_ephemeral_box_23282, plan_ephemeral_box_23298 };
    Rc = elmc_record_new_values_take(&owned[38], 2, rec_values_158_98);
    CHECK_RC(Rc);
    ElmcValue *plan_ephemeral_box_23314 = NULL;
    Rc = elmc_new_int(&plan_ephemeral_box_23314, 24);
    CHECK_RC(Rc);
    ElmcValue *plan_ephemeral_box_23330 = NULL;
    Rc = elmc_new_int(&plan_ephemeral_box_23330, 6);
    CHECK_RC(Rc);
    ElmcValue *rec_values_165_99[2] = { plan_ephemeral_box_23314, plan_ephemeral_box_23330 };
    Rc = elmc_record_new_values_take(&owned[39], 2, rec_values_165_99);
    CHECK_RC(Rc);
    ElmcValue *plan_list_record_items_23346[4] = { owned[36], owned[37], owned[38], owned[39] };
    Rc = elmc_list_from_record_array(&owned[40], plan_list_record_items_23346, 4);
    CHECK_RC(Rc);
    ElmcValue *plan_ephemeral_box_23362 = NULL;
    Rc = elmc_new_int(&plan_ephemeral_box_23362, 10);
    CHECK_RC(Rc);
    ElmcValue *plan_ephemeral_box_23378 = NULL;
    Rc = elmc_new_int(&plan_ephemeral_box_23378, 78);
    CHECK_RC(Rc);
    ElmcValue *rec_values_173_100[2] = { plan_ephemeral_box_23362, plan_ephemeral_box_23378 };
    Rc = elmc_record_new_values_take(&owned[41], 2, rec_values_173_100);
    CHECK_RC(Rc);
    Rc = elmc_new_int(&owned[42], 1);
    CHECK_RC(Rc);
    Rc = elmc_new_int(&owned[43], 0);
    CHECK_RC(Rc);
    Rc = elmc_tuple2(&owned[44], owned[42], owned[43]);
    CHECK_RC(Rc);
    Rc = elmc_fn_Pebble_Ui_path(&owned[45], owned[40], owned[41], owned[44]);
    CHECK_RC(Rc);
    if (owned[45] == owned[40]) {
      owned[40] = NULL;
    }
    if (owned[45] == owned[41]) {
      owned[41] = NULL;
    }
    if (owned[45] == owned[44]) {
      owned[44] = NULL;
    }
    ElmcValue *plan_ephemeral_box_23394 = NULL;
    Rc = elmc_new_int(&plan_ephemeral_box_23394, ELMC_RENDER_OP_PATH_OUTLINE_OPEN);
    CHECK_RC(Rc);
    Rc = elmc_tuple2(&owned[46], plan_ephemeral_box_23394, owned[45]);
    CHECK_RC(Rc);
    elmc_release(plan_ephemeral_box_23394);
    ElmcValue *plan_list_items_23410[5] = { owned[9], owned[10], owned[23], owned[35], owned[46] };
    Rc = elmc_list_from_values(&owned[47], plan_list_items_23410, 5);
    CHECK_RC(Rc);
    Rc = elmc_tuple2(&owned[48], owned[8], owned[47]);
    CHECK_RC(Rc);
    ElmcValue *plan_ephemeral_box_23426 = NULL;
    Rc = elmc_new_int(&plan_ephemeral_box_23426, ELMC_RENDER_OP_CONTEXT_GROUP);
    CHECK_RC(Rc);
    Rc = elmc_tuple2(&owned[49], plan_ephemeral_box_23426, owned[48]);
    CHECK_RC(Rc);
    elmc_release(plan_ephemeral_box_23426);
    Rc = elmc_render_cmd6_take(&owned[50], ELMC_RENDER_OP_LINE, 0, 84, 143, 84, ELMC_COLOR_BLACK, 0);
    CHECK_RC(Rc);
    Rc = elmc_render_cmd6_take(&owned[51], ELMC_RENDER_OP_PIXEL, 72, 84, ELMC_COLOR_BLACK, 0, 0, 0);
    CHECK_RC(Rc);
    Rc = elmc_fn_Main_statusDraw(&owned[52], model);
    CHECK_RC(Rc);
    Rc = elmc_fn_Main_counterDraw(&owned[53], model);
    CHECK_RC(Rc);
    ElmcValue *plan_list_items_23442[6] = { owned[2], owned[49], owned[50], owned[51], owned[52], owned[53] };
    Rc = elmc_list_from_values(&owned[54], plan_list_items_23442, 6);
    CHECK_RC(Rc);
    Rc = elmc_tuple2(&owned[55], owned[1], owned[54]);
    CHECK_RC(Rc);
    ElmcValue *plan_ephemeral_box_23458 = NULL;
    Rc = elmc_new_int(&plan_ephemeral_box_23458, ELMC_UI_NODE_CANVAS_LAYER);
    CHECK_RC(Rc);
    Rc = elmc_tuple2(&owned[56], plan_ephemeral_box_23458, owned[55]);
    CHECK_RC(Rc);
    elmc_release(plan_ephemeral_box_23458);
    ElmcValue *plan_list_items_23474[1] = { owned[56] };
    Rc = elmc_list_from_values(&owned[57], plan_list_items_23474, 1);
    CHECK_RC(Rc);
    Rc = elmc_tuple2(&owned[58], owned[0], owned[57]);
    CHECK_RC(Rc);
    ElmcValue *plan_ephemeral_box_23490 = NULL;
    Rc = elmc_new_int(&plan_ephemeral_box_23490, ELMC_UI_NODE_WINDOW);
    CHECK_RC(Rc);
    Rc = elmc_tuple2(&owned[59], plan_ephemeral_box_23490, owned[58]);
    CHECK_RC(Rc);
    elmc_release(plan_ephemeral_box_23490);
    ElmcValue *plan_list_items_23506[1] = { owned[59] };
    Rc = elmc_list_from_values(&owned[60], plan_list_items_23506, 1);
    CHECK_RC(Rc);
    ElmcValue *plan_ephemeral_box_23522 = NULL;
    Rc = elmc_new_int(&plan_ephemeral_box_23522, ELMC_UI_NODE_WINDOW_STACK);
    CHECK_RC(Rc);
    Rc = elmc_tuple2(out, plan_ephemeral_box_23522, owned[60]);
    CHECK_RC(Rc);
    elmc_release(plan_ephemeral_box_23522);
  CATCH_END
  elmc_release_array_lifo(owned, ELMC_OWNED_SLOT_COUNT);
  elmc_owned_slots_release(owned, ELMC_OWNED_SLOT_COUNT);
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
    *out = elmc_retain(owned[0]);
    owned[0] = NULL;
  CATCH_END
  elmc_release_array_lifo(owned, DIM(owned));
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
  ElmcValue *plan_ephemeral_box_23538 = NULL;
  {
    RC __alloc_rc = elmc_new_int(&plan_ephemeral_box_23538, 1);
    if (__alloc_rc != RC_SUCCESS) {
      ELMC_RC_LOG_FAIL(__alloc_rc, "elmc_new_int", "allocation failed");
      return NULL;
    }
  }
  {
    ElmcValue *__rc_ret = NULL;
    RC __alloc_rc = elmc_tuple2(&__rc_ret, plan_ephemeral_box_23538, owned[0]);
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
  ElmcValue *plan_ephemeral_box_23554 = NULL;
  {
    RC __alloc_rc = elmc_new_int(&plan_ephemeral_box_23554, 1);
    if (__alloc_rc != RC_SUCCESS) {
      ELMC_RC_LOG_FAIL(__alloc_rc, "elmc_new_int", "allocation failed");
      return NULL;
    }
  }
  {
    ElmcValue *__rc_ret = NULL;
    RC __alloc_rc = elmc_tuple2(&__rc_ret, plan_ephemeral_box_23554, owned[0]);
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
  ElmcValue *plan_ephemeral_box_23570 = NULL;
  {
    RC __alloc_rc = elmc_new_int(&plan_ephemeral_box_23570, 1);
    if (__alloc_rc != RC_SUCCESS) {
      ELMC_RC_LOG_FAIL(__alloc_rc, "elmc_new_int", "allocation failed");
      return NULL;
    }
  }
  {
    ElmcValue *__rc_ret = NULL;
    RC __alloc_rc = elmc_tuple2(&__rc_ret, plan_ephemeral_box_23570, owned[0]);
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
    /* plan block 0 */
    int list_walk_need_reverse_0 = 1;
    ElmcValue *list_walk_map_head_0 = elmc_list_nil();
    if (points && points->tag == ELMC_TAG_LAZY_MAP) {
      Rc = elmc_lazy_map(&list_walk_map_head_0, points, elmc_fn_Pebble_Ui_path_closure_0, NULL, 0);
      CHECK_RC(Rc);
      list_walk_need_reverse_0 = 0;
    } else {
      ElmcValue *list_walk_src_0 = NULL;
      Rc = elmc_list_materialize_cons(&list_walk_src_0, points);
      CHECK_RC(Rc);
      ElmcValue *list_walk_map_cursor_0 = list_walk_src_0;
      while (list_walk_map_cursor_0 && list_walk_map_cursor_0->tag == ELMC_TAG_LIST && list_walk_map_cursor_0->payload != NULL) {
        ElmcCons *list_walk_map_node_0 = (ElmcCons *)list_walk_map_cursor_0->payload;
        ElmcValue *list_walk_map_item_0 = NULL;
        ElmcValue *loop_args[1] = { list_walk_map_node_0->head };
        Rc = elmc_fn_Pebble_Ui_path_closure_0(&list_walk_map_item_0, loop_args, 1, NULL, 0);
        CHECK_RC(Rc);
        {
          ElmcValue *__acc_next__ = NULL;
          Rc = elmc_list_cons(&__acc_next__, list_walk_map_item_0, list_walk_map_head_0);
          CHECK_RC(Rc);
          elmc_release(list_walk_map_item_0);
          list_walk_map_item_0 = NULL;
          elmc_release(list_walk_map_head_0);
          list_walk_map_head_0 = __acc_next__;
        }
        list_walk_map_cursor_0 = list_walk_map_node_0->tail;
      }
      elmc_release(list_walk_src_0);
    }
    if (list_walk_need_reverse_0) {
      ElmcValue *__rev_prev__ = elmc_list_nil();
      ElmcValue *__rev_cur__ = list_walk_map_head_0;
      while (__rev_cur__ && __rev_cur__->tag == ELMC_TAG_LIST && __rev_cur__->payload != NULL) {
        ElmcCons *__rev_node__ = (ElmcCons *)__rev_cur__->payload;
        ElmcValue *__rev_next__ = __rev_node__->tail;
        __rev_node__->tail = __rev_prev__;
        __rev_prev__ = __rev_cur__;
        __rev_cur__ = __rev_next__;
      }
      list_walk_map_head_0 = __rev_prev__;
    }
    owned[1] = list_walk_map_head_0;
    const elmc_int_t plan_native_int_5 = ELMC_RECORD_GET_INDEX_INT(offset, ELMC_FIELD_PEBBLE_UI_POINT_X);
    const elmc_int_t plan_native_int_6 = ELMC_RECORD_GET_INDEX_INT(offset, ELMC_FIELD_PEBBLE_UI_POINT_Y);
    Rc = elmc_tuple2_ints(&owned[2], plan_native_int_5, plan_native_int_6);
    CHECK_RC(Rc);
    Rc = elmc_fn_Pebble_Ui_rotationToPebbleAngle(&owned[3], rotation);
    CHECK_RC(Rc);
    Rc = elmc_tuple2(&owned[4], owned[2], owned[3]);
    CHECK_RC(Rc);
    Rc = elmc_tuple2(out, owned[1], owned[4]);
    CHECK_RC(Rc);
  CATCH_END
  elmc_release_array_lifo(owned, DIM(owned));
  return Rc;
}

static RC elmc_fn_Pebble_Ui_rotationToPebbleAngle(ElmcValue **out, ElmcValue *patternArg) {
  /* Ownership policy: borrow_arg, borrow_result, direct_call_abi */
  RC Rc = RC_SUCCESS;
  ElmcValue *owned[1] = {0};
  CATCH_BEGIN
    /* plan block 0 */
    owned[0] = elmc_tuple_second_borrow(patternArg);
    *out = elmc_retain(owned[0]);
    owned[0] = NULL;
  CATCH_END
  elmc_release_array_lifo(owned, DIM(owned));
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

static RC elmc_fn_Main_view_commands_append(ElmcValue ** const args, const int argc, ElmcSceneWriter * const writer);

static RC elmc_fn_Main_view_commands_append(ElmcValue ** const args, const int argc, ElmcSceneWriter * const writer) {
  ElmcValue *model = (argc > 0) ? args[0] : NULL;

  if (!writer)
    return RC_ERR_INVALID_ARG;
  RC Rc = RC_SUCCESS;
  ElmcValue *owned[2] = {0};

#if defined(PBL_PLATFORM_APLITE)
  static ElmcPebbleDrawCmd scene_cmd;
#else
  ElmcPebbleDrawCmd scene_cmd;
#endif

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

      Rc = elmc_fn_Main_temperatureValue(&owned[1], elmc_maybe_or_tuple_just_payload_borrow(owned[0]));
      CHECK_RC(Rc);

      const elmc_int_t native_i_17 = elmc_as_int(owned[1]);

      elmc_draw_cmd_init(&scene_cmd, ELMC_RENDER_OP_TEXT_INT_WITH_FONT);
      scene_cmd.p0 = 1;
      scene_cmd.p1 = 0;
      scene_cmd.p2 = 28;
      scene_cmd.p3 = native_i_17;
      Rc = elmc_scene_writer_push_cmd(writer, &scene_cmd);
      CHECK_RC(Rc);

    }
    else if (elmc_maybe_is_nothing(owned[0])) {

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

    const elmc_int_t native_call_19 = elmc_fn_Main_counterOf(model);

    elmc_draw_cmd_init(&scene_cmd, ELMC_RENDER_OP_TEXT_INT_WITH_FONT);
    scene_cmd.p0 = 1;
    scene_cmd.p1 = 0;
    scene_cmd.p2 = 56;
    scene_cmd.p3 = native_call_19;
    Rc = elmc_scene_writer_push_cmd(writer, &scene_cmd);
    CHECK_RC(Rc);

  CATCH_END
  elmc_release_array_lifo(owned, DIM(owned));

  return Rc;

}

RC elmc_fn_Main_view_scene_append(ElmcValue ** const args, const int argc, ElmcSceneWriter * const writer) {
  return elmc_fn_Main_view_commands_append(args, argc, writer);
}
