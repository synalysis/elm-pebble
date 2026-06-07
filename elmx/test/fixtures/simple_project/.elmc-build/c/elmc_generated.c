#include "elmc_generated.h"
#include <stdio.h>

#if defined(__GNUC__)
#pragma GCC diagnostic ignored "-Wunused-function"
#endif

#define ELMC_RENDER_OP_NONE 0
#define ELMC_RENDER_OP_CLEAR 2
#define ELMC_RENDER_OP_PIXEL 3
#define ELMC_RENDER_OP_LINE 4
#define ELMC_RENDER_OP_RECT 5
#define ELMC_RENDER_OP_FILL_RECT 6
#define ELMC_RENDER_OP_CIRCLE 7
#define ELMC_RENDER_OP_FILL_CIRCLE 8
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
#define ELMC_RENDER_OP_FILL_RADIAL 23
#define ELMC_RENDER_OP_COMPOSITING_MODE 24
#define ELMC_RENDER_OP_BITMAP_IN_RECT 25
#define ELMC_RENDER_OP_ROTATED_BITMAP 26
#define ELMC_RENDER_OP_TEXT_INT_WITH_FONT 27
#define ELMC_RENDER_OP_TEXT_LABEL_WITH_FONT 28
#define ELMC_RENDER_OP_TEXT 29
#define ELMC_CONTEXT_STROKE_WIDTH 1
#define ELMC_CONTEXT_ANTIALIASED 2
#define ELMC_CONTEXT_STROKE_COLOR 3
#define ELMC_CONTEXT_FILL_COLOR 4
#define ELMC_CONTEXT_TEXT_COLOR 5
#define ELMC_CONTEXT_COMPOSITING_MODE 6
#define ELMC_UI_NODE_WINDOW_STACK 1000
#define ELMC_UI_NODE_WINDOW 1001
#define ELMC_UI_NODE_CANVAS_LAYER 1002
#define ELMC_BUTTON_BACK 0
#define ELMC_BUTTON_UP 1
#define ELMC_BUTTON_SELECT 2
#define ELMC_BUTTON_DOWN 3
#define ELMC_BUTTON_EVENT_PRESSED 1
#define ELMC_BUTTON_EVENT_RELEASED 2
#define ELMC_BUTTON_EVENT_LONG_PRESSED 3
#define ELMC_SUBSCRIPTION_SECOND_CHANGE 1
#define ELMC_SUBSCRIPTION_BUTTON_UP 2
#define ELMC_SUBSCRIPTION_BUTTON_SELECT 4
#define ELMC_SUBSCRIPTION_BUTTON_DOWN 8
#define ELMC_SUBSCRIPTION_ACCEL_TAP 16
#define ELMC_SUBSCRIPTION_HOUR_CHANGE 1024
#define ELMC_SUBSCRIPTION_MINUTE_CHANGE 2048
#define ELMC_SUBSCRIPTION_FRAME_BASE 8192
#define ELMC_SUBSCRIPTION_BUTTON_RAW 16384
#define ELMC_SUBSCRIPTION_DAY_CHANGE 65536
#define ELMC_SUBSCRIPTION_MONTH_CHANGE 131072
#define ELMC_SUBSCRIPTION_YEAR_CHANGE 262144
#define ELMC_SUBSCRIPTION_BUTTON_LONG_UP 128
#define ELMC_SUBSCRIPTION_BUTTON_LONG_SELECT 256
#define ELMC_SUBSCRIPTION_BUTTON_LONG_DOWN 512
#define ELMC_TEXT_ALIGN_LEFT 0
#define ELMC_TEXT_ALIGN_CENTER 1
#define ELMC_TEXT_ALIGN_RIGHT 2
#define ELMC_TEXT_OVERFLOW_WORD_WRAP 0
#define ELMC_TEXT_OVERFLOW_TRAILING_ELLIPSIS 1
#define ELMC_TEXT_OVERFLOW_FILL 2
#define ELMC_TEXT_OVERFLOW_SHIFT 2
#define ELMC_COLOR_ARMY_GREEN 212
#define ELMC_COLOR_BABY_BLUE_EYES 235
#define ELMC_COLOR_BLACK 192
#define ELMC_COLOR_BLUE 195
#define ELMC_COLOR_BLUE_MOON 199
#define ELMC_COLOR_BRASS 233
#define ELMC_COLOR_BRIGHT_GREEN 220
#define ELMC_COLOR_BRILLIANT_ROSE 246
#define ELMC_COLOR_BULGARIAN_ROSE 208
#define ELMC_COLOR_CADET_BLUE 218
#define ELMC_COLOR_CELESTE 239
#define ELMC_COLOR_CHROME_YELLOW 248
#define ELMC_COLOR_CLEAR_COLOR 0
#define ELMC_COLOR_COBALT_BLUE 198
#define ELMC_COLOR_CYAN 207
#define ELMC_COLOR_DARK_CANDY_APPLE_RED 224
#define ELMC_COLOR_DARK_GRAY 213
#define ELMC_COLOR_DARK_GREEN 196
#define ELMC_COLOR_DUKE_BLUE 194
#define ELMC_COLOR_ELECTRIC_BLUE 223
#define ELMC_COLOR_ELECTRIC_ULTRAMARINE 211
#define ELMC_COLOR_FASHION_MAGENTA 242
#define ELMC_COLOR_FOLLY 241
#define ELMC_COLOR_GREEN 204
#define ELMC_COLOR_ICTERINE 253
#define ELMC_COLOR_IMPERIAL_PURPLE 209
#define ELMC_COLOR_INCHWORM 237
#define ELMC_COLOR_INDIGO 210
#define ELMC_COLOR_ISLAMIC_GREEN 200
#define ELMC_COLOR_JAEGER_GREEN 201
#define ELMC_COLOR_JAZZBERRY_JAM 225
#define ELMC_COLOR_KELLY_GREEN 216
#define ELMC_COLOR_LAVENDER_INDIGO 231
#define ELMC_COLOR_LIBERTY 214
#define ELMC_COLOR_LIGHT_GRAY 234
#define ELMC_COLOR_LIMERICK 232
#define ELMC_COLOR_MAGENTA 243
#define ELMC_COLOR_MALACHITE 205
#define ELMC_COLOR_MAY_GREEN 217
#define ELMC_COLOR_MEDIUM_AQUAMARINE 222
#define ELMC_COLOR_MEDIUM_SPRING_GREEN 206
#define ELMC_COLOR_MELON 250
#define ELMC_COLOR_MIDNIGHT_GREEN 197
#define ELMC_COLOR_MINT_GREEN 238
#define ELMC_COLOR_ORANGE 244
#define ELMC_COLOR_OXFORD_BLUE 193
#define ELMC_COLOR_PASTEL_YELLOW 254
#define ELMC_COLOR_PICTON_BLUE 219
#define ELMC_COLOR_PURPLE 226
#define ELMC_COLOR_PURPUREUS 230
#define ELMC_COLOR_RAJAH 249
#define ELMC_COLOR_RED 240
#define ELMC_COLOR_RICH_BRILLIANT_LAVENDER 251
#define ELMC_COLOR_ROSE_VALE 229
#define ELMC_COLOR_SCREAMIN_GREEN 221
#define ELMC_COLOR_SHOCKING_PINK 247
#define ELMC_COLOR_SPRING_BUD 236
#define ELMC_COLOR_SUNSET_ORANGE 245
#define ELMC_COLOR_TIFFANY_BLUE 202
#define ELMC_COLOR_VERY_LIGHT_BLUE 215
#define ELMC_COLOR_VIVID_CERULEAN 203
#define ELMC_COLOR_VIVID_VIOLET 227
#define ELMC_COLOR_WHITE 255
#define ELMC_COLOR_WINDSOR_TAN 228
#define ELMC_COLOR_YELLOW 252


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




#include "elmc_pebble.h"
#include <string.h>

typedef ElmcPebbleDrawCmd ElmcGeneratedPebbleDrawCmd;

static void elmc_generated_draw_init(ElmcGeneratedPebbleDrawCmd *cmd, int64_t kind) {
  memset(cmd, 0, sizeof(*cmd));
  cmd->kind = kind;
}


static elmc_int_t elmc_fn_Main_helper_native(const elmc_int_t value);

ElmcValue *elmc_fn_Main_helper(ElmcValue ** const args, const int argc);
ElmcValue *elmc_fn_Main_advanced(ElmcValue ** const args, const int argc);
ElmcValue *elmc_fn_Main_counterOf(ElmcValue ** const args, const int argc);
ElmcValue *elmc_fn_Main_temperatureOf(ElmcValue ** const args, const int argc);
ElmcValue *elmc_fn_Main_requestWeather(ElmcValue ** const args, const int argc);
ElmcValue *elmc_fn_Main_requestSystemInfo(ElmcValue ** const args, const int argc);
ElmcValue *elmc_fn_Main_init(ElmcValue ** const args, const int argc);
ElmcValue *elmc_fn_Main_update(ElmcValue ** const args, const int argc);
ElmcValue *elmc_fn_Main_handleAppMsg(ElmcValue ** const args, const int argc);
ElmcValue *elmc_fn_Main_handlePlatformMsg(ElmcValue ** const args, const int argc);
ElmcValue *elmc_fn_Main_subscriptions(ElmcValue ** const args, const int argc);
ElmcValue *elmc_fn_Main_view(ElmcValue ** const args, const int argc);
ElmcValue *elmc_fn_Main_statusDraw(ElmcValue ** const args, const int argc);
ElmcValue *elmc_fn_Main_counterDraw(ElmcValue ** const args, const int argc);
ElmcValue *elmc_fn_Main_temperatureValue(ElmcValue ** const args, const int argc);
ElmcValue *elmc_fn_Main_main(ElmcValue ** const args, const int argc);
ElmcValue *elmc_fn_Pebble_Platform_launchReasonToInt(ElmcValue ** const args, const int argc);
ElmcValue *elmc_fn_Pebble_Ui_path(ElmcValue ** const args, const int argc);
ElmcValue *elmc_fn_Pebble_Ui_rotationToPebbleAngle(ElmcValue ** const args, const int argc);
ElmcValue *elmc_fn_Companion_Internal_encodeLocationCode(ElmcValue ** const args, const int argc);
ElmcValue *elmc_fn_Companion_Internal_watchToPhoneTag(ElmcValue ** const args, const int argc);
ElmcValue *elmc_fn_Companion_Internal_watchToPhoneValue(ElmcValue ** const args, const int argc);
ElmcValue *elmc_fn_Companion_Watch_sendWatchToPhone(ElmcValue ** const args, const int argc);

static ElmcValue *elmc_lambda_1(ElmcValue **args, int argc, ElmcValue **captures, int capture_count) {
  (void)args;
  (void)argc;
  (void)captures;
  (void)capture_count;
  ElmcValue *p = (argc > 0) ? args[0] : NULL;
  
  
  ElmcValue *tmp_1 = elmc_record_get(p, "x");
  

  
  ElmcValue *tmp_2 = elmc_record_get(p, "y");
  

    ElmcValue *tmp_3 = elmc_tuple2_take(tmp_1, tmp_2);

  return tmp_3;
}

static ElmcValue *elmc_lambda_2(ElmcValue **args, int argc, ElmcValue **captures, int capture_count) {
  (void)args;
  (void)argc;
  (void)captures;
  (void)capture_count;
  ElmcValue *patternArg = (argc > 0) ? args[0] : NULL;
  
  
  ElmcValue *tmp_1;
  
  

    ElmcValue *tmp_2 = ((ElmcTuple2 *)patternArg->payload)->second ? elmc_retain(((ElmcTuple2 *)patternArg->payload)->second) : elmc_int_zero();

    tmp_1 = tmp_2;


  

  return tmp_1;
}


ElmcValue *elmc_fn_Main_helper(ElmcValue ** const args, const int argc) {
  /* Ownership policy: borrow_arg, borrow_result */
  (void)args;
  (void)argc;
  elmc_int_t value = (argc > 0 && args[0]) ? elmc_as_int(args[0]) : 0;
  return elmc_new_int(elmc_fn_Main_helper_native(value));
}

static elmc_int_t elmc_fn_Main_helper_native(const elmc_int_t value) {
  (void)value;
  
  
  
  return (value + 2);
}



ElmcValue *elmc_fn_Main_advanced(ElmcValue ** const args, const int argc) {
  /* Ownership policy: borrow_arg, borrow_result */
  (void)args;
  (void)argc;
ElmcValue *n = (argc > 0) ? args[0] : NULL;
  (void)n;
  
  
    // inlined Main.helper

  const elmc_int_t native_let_base_1 = (elmc_as_int(n) + 2);
  
  
  ElmcValue *tmp_1;
  if ((native_let_base_1 > 10)) {
    ElmcValue *tmp_2 = elmc_new_int(native_let_base_1);
    tmp_1 = tmp_2;

  } else {

      ElmcValue *tmp_3 = elmc_new_int((native_let_base_1 + 1));

    tmp_1 = tmp_3;

  }


  
  
  return tmp_1;

}


ElmcValue *elmc_fn_Main_counterOf(ElmcValue ** const args, const int argc) {
  /* Ownership policy: borrow_arg, borrow_result */
  (void)args;
  (void)argc;
ElmcValue *model = (argc > 0) ? args[0] : NULL;
  (void)model;
  
  
  ElmcValue *tmp_1 = elmc_record_get_index(model, 1 /* value */);
  

  
  
  return tmp_1;

}


ElmcValue *elmc_fn_Main_temperatureOf(ElmcValue ** const args, const int argc) {
  /* Ownership policy: borrow_arg, borrow_result */
  (void)args;
  (void)argc;
ElmcValue *model = (argc > 0) ? args[0] : NULL;
  (void)model;
  
  
  ElmcValue *tmp_1 = elmc_record_get_index(model, 0 /* temperature */);
  

  
  
  return tmp_1;

}


ElmcValue *elmc_fn_Main_requestWeather(ElmcValue ** const args, const int argc) {
  /* Ownership policy: borrow_arg, borrow_result */
  (void)args;
  (void)argc;
ElmcValue *location = (argc > 0) ? args[0] : NULL;
  (void)location;
  
  

  
  
  ElmcValue *tmp_1 = elmc_tuple2_ints(1, elmc_as_int(location));

  
  ElmcValue *call_args_2[1] = { tmp_1 };
  ElmcValue *tmp_2 = elmc_fn_Companion_Watch_sendWatchToPhone(call_args_2, 1);
  
  elmc_release(tmp_1);

  
  
  return tmp_2;

}


ElmcValue *elmc_fn_Main_requestSystemInfo(ElmcValue ** const args, const int argc) {
  /* Ownership policy: borrow_arg, borrow_result */
  (void)args;
  (void)argc;

  
  
  
  ElmcValue *tmp_1 = elmc_new_int(7);
  ElmcValue *tmp_2 = elmc_new_int(8);
  ElmcValue *tmp_3 = elmc_new_int(9);
  ElmcValue *tmp_4 = elmc_new_int(10);
  ElmcValue *tmp_5 = elmc_new_int(11);
  ElmcValue *tmp_6 = elmc_new_int(17);
  ElmcValue *tmp_7 = elmc_new_int(12);
  ElmcValue *list_items_8[7] = { tmp_1, tmp_2, tmp_3, tmp_4, tmp_5, tmp_6, tmp_7 };
  ElmcValue *tmp_8 = elmc_list_from_values_take(list_items_8, 7);
  

  
  
  return tmp_8;

}


ElmcValue *elmc_fn_Main_init(ElmcValue ** const args, const int argc) {
  /* Ownership policy: borrow_arg, borrow_result */
  (void)args;
  (void)argc;
ElmcValue *launchContext = (argc > 0) ? args[0] : NULL;
  (void)launchContext;
  
  
  

  
  ElmcValue *tmp_1 = elmc_record_get_index(launchContext, 2 /* reason */);
  

  
  ElmcValue *call_args_2[1] = { tmp_1 };
  ElmcValue *tmp_2 = elmc_fn_Pebble_Platform_launchReasonToInt(call_args_2, 1);
  
  elmc_release(tmp_1);

  const elmc_int_t native_i_3 = elmc_as_int(tmp_2);
  elmc_release(tmp_2);

  const elmc_int_t native_let_initial_4 = native_i_3;
  
  
  
  
  const char *rec_names_4[2] = { "temperature", "value" };
  elmc_int_t rec_values_4[2] = { 0, native_let_initial_4 };
  ElmcValue *tmp_4 = elmc_record_new_ints(2, rec_names_4, rec_values_4);

  
  

  ElmcValue *tmp_5 = elmc_new_int(2);
  
  ElmcValue *call_args_6[1] = { tmp_5 };
  ElmcValue *tmp_6 = elmc_fn_Main_requestWeather(call_args_6, 1);
  
  elmc_release(tmp_5);

  ElmcValue *tmp_7 = elmc_fn_Main_requestSystemInfo(NULL, 0);
  ElmcValue *list_items_8[2] = { tmp_6, tmp_7 };
  ElmcValue *tmp_8 = elmc_list_from_values_take(list_items_8, 2);
  

    ElmcValue *tmp_9 = elmc_tuple2_take(tmp_4, tmp_8);


  
  
  return tmp_9;

}


ElmcValue *elmc_fn_Main_update(ElmcValue ** const args, const int argc) {
  /* Ownership policy: borrow_arg, borrow_result */
  (void)args;
  (void)argc;
ElmcValue *msg = (argc > 0) ? args[0] : NULL;
  ElmcValue *model = (argc > 1) ? args[1] : NULL;
  (void)msg;
  (void)model;
  
  
  const int case_msg_tag_1 = (msg && (msg)->tag == ELMC_TAG_INT ? elmc_as_int(msg) : (msg && (msg)->tag == ELMC_TAG_TUPLE2 && (msg)->payload != NULL ? elmc_as_int(((ElmcTuple2 *)(msg)->payload)->first) : -1));
  ElmcValue *tmp_1 = elmc_int_zero();
  switch (case_msg_tag_1) {
  case 3:


      ElmcValue *tmp_2 = msg ? elmc_retain(msg) : elmc_int_zero();
      ElmcValue *tmp_3 = model ? elmc_retain(model) : elmc_int_zero();
  
      ElmcValue *call_args_4[2] = { tmp_2, tmp_3 };
      ElmcValue *tmp_4 = elmc_fn_Main_handlePlatformMsg(call_args_4, 2);
  
      elmc_release(tmp_2);
      elmc_release(tmp_3);

    tmp_1 = tmp_4;
    break;
case 4:


      ElmcValue *tmp_5 = msg ? elmc_retain(msg) : elmc_int_zero();
      ElmcValue *tmp_6 = model ? elmc_retain(model) : elmc_int_zero();
  
      ElmcValue *call_args_7[2] = { tmp_5, tmp_6 };
      ElmcValue *tmp_7 = elmc_fn_Main_handlePlatformMsg(call_args_7, 2);
  
      elmc_release(tmp_5);
      elmc_release(tmp_6);

    tmp_1 = tmp_7;
    break;
case 5:


      ElmcValue *tmp_8 = msg ? elmc_retain(msg) : elmc_int_zero();
      ElmcValue *tmp_9 = model ? elmc_retain(model) : elmc_int_zero();
  
      ElmcValue *call_args_10[2] = { tmp_8, tmp_9 };
      ElmcValue *tmp_10 = elmc_fn_Main_handlePlatformMsg(call_args_10, 2);
  
      elmc_release(tmp_8);
      elmc_release(tmp_9);

    tmp_1 = tmp_10;
    break;
case 6:


      ElmcValue *tmp_11 = msg ? elmc_retain(msg) : elmc_int_zero();
      ElmcValue *tmp_12 = model ? elmc_retain(model) : elmc_int_zero();
  
      ElmcValue *call_args_13[2] = { tmp_11, tmp_12 };
      ElmcValue *tmp_13 = elmc_fn_Main_handlePlatformMsg(call_args_13, 2);
  
      elmc_release(tmp_11);
      elmc_release(tmp_12);

    tmp_1 = tmp_13;
    break;
case 7:


      ElmcValue *tmp_14 = msg ? elmc_retain(msg) : elmc_int_zero();
      ElmcValue *tmp_15 = model ? elmc_retain(model) : elmc_int_zero();
  
      ElmcValue *call_args_16[2] = { tmp_14, tmp_15 };
      ElmcValue *tmp_16 = elmc_fn_Main_handlePlatformMsg(call_args_16, 2);
  
      elmc_release(tmp_14);
      elmc_release(tmp_15);

    tmp_1 = tmp_16;
    break;
default:


      ElmcValue *tmp_17 = msg ? elmc_retain(msg) : elmc_int_zero();
      ElmcValue *tmp_18 = model ? elmc_retain(model) : elmc_int_zero();
  
      ElmcValue *call_args_19[2] = { tmp_17, tmp_18 };
      ElmcValue *tmp_19 = elmc_fn_Main_handleAppMsg(call_args_19, 2);
  
      elmc_release(tmp_17);
      elmc_release(tmp_18);

    tmp_1 = tmp_19;
    break;

  }

  
  
  return tmp_1;

}


ElmcValue *elmc_fn_Main_handleAppMsg(ElmcValue ** const args, const int argc) {
  /* Ownership policy: borrow_arg, borrow_result */
  (void)args;
  (void)argc;
ElmcValue *msg = (argc > 0) ? args[0] : NULL;
  ElmcValue *model = (argc > 1) ? args[1] : NULL;
  (void)msg;
  (void)model;
  
  
  const int case_msg_tag_1 = (msg && (msg)->tag == ELMC_TAG_INT ? elmc_as_int(msg) : (msg && (msg)->tag == ELMC_TAG_TUPLE2 && (msg)->payload != NULL ? elmc_as_int(((ElmcTuple2 *)(msg)->payload)->first) : -1));
  ElmcValue *tmp_1 = elmc_int_zero();
  switch (case_msg_tag_1) {
  case 1:

        // inlined Main.counterOf

      const elmc_int_t native_let_counter_2 = ELMC_RECORD_GET_INDEX_INT(model, 1 /* value */);
  
  
  

      ElmcValue *tmp_2 = model ? elmc_retain(model) : elmc_int_zero();
  
      ElmcValue *call_args_3[1] = { tmp_2 };
      ElmcValue *tmp_3 = elmc_fn_Main_temperatureOf(call_args_3, 1);
  
      elmc_release(tmp_2);

  
      ElmcValue *tmp_4 = elmc_new_int((native_let_counter_2 + 1));

      const char *rec_names_5[2] = { "temperature", "value" };
      ElmcValue *rec_values_5[2] = { tmp_3, tmp_4 };
        ElmcValue *tmp_5 = elmc_record_new_take(2, rec_names_5, rec_values_5);

      ElmcValue *tmp_6 = elmc_int_zero();
        ElmcValue *tmp_7 = elmc_tuple2_take(tmp_5, tmp_6);


    tmp_1 = tmp_7;
    break;
case 2:

        // inlined Main.counterOf

      const elmc_int_t native_let_counter_8 = ELMC_RECORD_GET_INDEX_INT(model, 1 /* value */);
  
  
  

      ElmcValue *tmp_8 = model ? elmc_retain(model) : elmc_int_zero();
  
      ElmcValue *call_args_9[1] = { tmp_8 };
      ElmcValue *tmp_9 = elmc_fn_Main_temperatureOf(call_args_9, 1);
  
      elmc_release(tmp_8);

  
      ElmcValue *tmp_10 = elmc_new_int((native_let_counter_8 - 1));

      const char *rec_names_11[2] = { "temperature", "value" };
      ElmcValue *rec_values_11[2] = { tmp_9, tmp_10 };
        ElmcValue *tmp_11 = elmc_record_new_take(2, rec_names_11, rec_values_11);

      ElmcValue *tmp_12 = elmc_int_zero();
        ElmcValue *tmp_13 = elmc_tuple2_take(tmp_11, tmp_12);


    tmp_1 = tmp_13;
    break;
case 8:

      ElmcValue *tmp_14 = elmc_new_int(1);
      ElmcValue *tmp_15 = ((ElmcTuple2 *)msg->payload)->second ? elmc_retain(((ElmcTuple2 *)msg->payload)->second) : elmc_int_zero();
        ElmcValue *tmp_16 = elmc_tuple2_take(tmp_14, tmp_15);

  

      ElmcValue *tmp_17 = model ? elmc_retain(model) : elmc_int_zero();
  
      ElmcValue *call_args_18[1] = { tmp_17 };
      ElmcValue *tmp_18 = elmc_fn_Main_counterOf(call_args_18, 1);
  
      elmc_release(tmp_17);

      const char *rec_names_19[2] = { "temperature", "value" };
      ElmcValue *rec_values_19[2] = { tmp_16, tmp_18 };
        ElmcValue *tmp_19 = elmc_record_new_take(2, rec_names_19, rec_values_19);

      ElmcValue *tmp_20 = elmc_int_zero();
        ElmcValue *tmp_21 = elmc_tuple2_take(tmp_19, tmp_20);

    tmp_1 = tmp_21;
    break;
case 9:
    ElmcValue *tmp_22 = model ? elmc_retain(model) : elmc_int_zero();
      ElmcValue *tmp_23 = elmc_int_zero();
        ElmcValue *tmp_24 = elmc_tuple2_take(tmp_22, tmp_23);

    tmp_1 = tmp_24;
    break;
case 10:
    ElmcValue *tmp_25 = model ? elmc_retain(model) : elmc_int_zero();
      ElmcValue *tmp_26 = elmc_int_zero();
        ElmcValue *tmp_27 = elmc_tuple2_take(tmp_25, tmp_26);

    tmp_1 = tmp_27;
    break;
case 11:
    ElmcValue *tmp_28 = model ? elmc_retain(model) : elmc_int_zero();
      ElmcValue *tmp_29 = elmc_int_zero();
        ElmcValue *tmp_30 = elmc_tuple2_take(tmp_28, tmp_29);

    tmp_1 = tmp_30;
    break;
case 12:
    ElmcValue *tmp_31 = model ? elmc_retain(model) : elmc_int_zero();
      ElmcValue *tmp_32 = elmc_int_zero();
        ElmcValue *tmp_33 = elmc_tuple2_take(tmp_31, tmp_32);

    tmp_1 = tmp_33;
    break;
case 13:
    ElmcValue *tmp_34 = model ? elmc_retain(model) : elmc_int_zero();
      ElmcValue *tmp_35 = elmc_int_zero();
        ElmcValue *tmp_36 = elmc_tuple2_take(tmp_34, tmp_35);

    tmp_1 = tmp_36;
    break;
case 14:
    ElmcValue *tmp_37 = model ? elmc_retain(model) : elmc_int_zero();
      ElmcValue *tmp_38 = elmc_int_zero();
        ElmcValue *tmp_39 = elmc_tuple2_take(tmp_37, tmp_38);

    tmp_1 = tmp_39;
    break;
case 15:
    ElmcValue *tmp_40 = model ? elmc_retain(model) : elmc_int_zero();
      ElmcValue *tmp_41 = elmc_int_zero();
        ElmcValue *tmp_42 = elmc_tuple2_take(tmp_40, tmp_41);

    tmp_1 = tmp_42;
    break;
default:
    ElmcValue *tmp_43 = model ? elmc_retain(model) : elmc_int_zero();
      ElmcValue *tmp_44 = elmc_int_zero();
        ElmcValue *tmp_45 = elmc_tuple2_take(tmp_43, tmp_44);

    tmp_1 = tmp_45;
    break;

  }

  
  
  return tmp_1;

}


ElmcValue *elmc_fn_Main_handlePlatformMsg(ElmcValue ** const args, const int argc) {
  /* Ownership policy: borrow_arg, borrow_result */
  (void)args;
  (void)argc;
ElmcValue *msg = (argc > 0) ? args[0] : NULL;
  ElmcValue *model = (argc > 1) ? args[1] : NULL;
  (void)msg;
  (void)model;
  
  
  const int case_msg_tag_1 = (msg && (msg)->tag == ELMC_TAG_INT ? elmc_as_int(msg) : (msg && (msg)->tag == ELMC_TAG_TUPLE2 && (msg)->payload != NULL ? elmc_as_int(((ElmcTuple2 *)(msg)->payload)->first) : -1));
  ElmcValue *tmp_1 = elmc_int_zero();
  switch (case_msg_tag_1) {
  case 3:
    


      ElmcValue *tmp_2 = model ? elmc_retain(model) : elmc_int_zero();
  
      ElmcValue *call_args_3[1] = { tmp_2 };
      ElmcValue *tmp_3 = elmc_fn_Main_counterOf(call_args_3, 1);
  
      elmc_release(tmp_2);

      
  
  

      ElmcValue *tmp_4 = elmc_retain(tmp_3);
  
      ElmcValue *call_args_5[1] = { tmp_4 };
      ElmcValue *tmp_5 = elmc_fn_Main_advanced(call_args_5, 1);
  
      elmc_release(tmp_4);

      const elmc_int_t native_i_6 = elmc_as_int(tmp_5);
      elmc_release(tmp_5);

      const elmc_int_t native_let_next_7 = native_i_6;
  
  
  

      ElmcValue *tmp_7 = model ? elmc_retain(model) : elmc_int_zero();
  
      ElmcValue *call_args_8[1] = { tmp_7 };
      ElmcValue *tmp_8 = elmc_fn_Main_temperatureOf(call_args_8, 1);
  
      elmc_release(tmp_7);

      ElmcValue *tmp_9 = elmc_new_int(native_let_next_7);
      const char *rec_names_10[2] = { "temperature", "value" };
      ElmcValue *rec_values_10[2] = { tmp_8, tmp_9 };
        ElmcValue *tmp_10 = elmc_record_new_take(2, rec_names_10, rec_values_10);

      ElmcValue *tmp_11 = elmc_new_int(1);
      ElmcValue *tmp_12 = elmc_new_int(1000);
      ElmcValue *tmp_13 = elmc_int_zero();
      ElmcValue *tmp_14 = elmc_int_zero();
      ElmcValue *tmp_15 = elmc_int_zero();
  
  
      ElmcValue *tmp_16 = elmc_tuple2_ints(0, 0);

        ElmcValue *tmp_17 = elmc_tuple2_take(tmp_15, tmp_16);

        ElmcValue *tmp_18 = elmc_tuple2_take(tmp_14, tmp_17);

        ElmcValue *tmp_19 = elmc_tuple2_take(tmp_13, tmp_18);

        ElmcValue *tmp_20 = elmc_tuple2_take(tmp_12, tmp_19);

        ElmcValue *tmp_21 = elmc_tuple2_take(tmp_11, tmp_20);

        ElmcValue *tmp_22 = elmc_tuple2_take(tmp_10, tmp_21);


      elmc_release(tmp_3);

    tmp_1 = tmp_22;
    break;
case 4:

        // inlined Main.counterOf

      const elmc_int_t native_let_counter_23 = ELMC_RECORD_GET_INDEX_INT(model, 1 /* value */);
  
  
  
      const elmc_int_t native_let_next_23 = (native_let_counter_23 + 1);
  
  
  

      ElmcValue *tmp_23 = model ? elmc_retain(model) : elmc_int_zero();
  
      ElmcValue *call_args_24[1] = { tmp_23 };
      ElmcValue *tmp_24 = elmc_fn_Main_temperatureOf(call_args_24, 1);
  
      elmc_release(tmp_23);

      ElmcValue *tmp_25 = elmc_new_int(native_let_next_23);
      const char *rec_names_26[2] = { "temperature", "value" };
      ElmcValue *rec_values_26[2] = { tmp_24, tmp_25 };
        ElmcValue *tmp_26 = elmc_record_new_take(2, rec_names_26, rec_values_26);

      ElmcValue *tmp_27 = elmc_new_int(2);
      ElmcValue *tmp_28 = elmc_new_int(1);
      ElmcValue *tmp_29 = elmc_new_int(native_let_next_23);
      ElmcValue *tmp_30 = elmc_int_zero();
      ElmcValue *tmp_31 = elmc_int_zero();
  
  
      ElmcValue *tmp_32 = elmc_tuple2_ints(0, 0);

        ElmcValue *tmp_33 = elmc_tuple2_take(tmp_31, tmp_32);

        ElmcValue *tmp_34 = elmc_tuple2_take(tmp_30, tmp_33);

        ElmcValue *tmp_35 = elmc_tuple2_take(tmp_29, tmp_34);

        ElmcValue *tmp_36 = elmc_tuple2_take(tmp_28, tmp_35);

        ElmcValue *tmp_37 = elmc_tuple2_take(tmp_27, tmp_36);

        ElmcValue *tmp_38 = elmc_tuple2_take(tmp_26, tmp_37);



    tmp_1 = tmp_38;
    break;
case 5:
    ElmcValue *tmp_39 = model ? elmc_retain(model) : elmc_int_zero();
  
  

      ElmcValue *tmp_40 = elmc_new_int(2);
  
      ElmcValue *call_args_41[1] = { tmp_40 };
      ElmcValue *tmp_41 = elmc_fn_Main_requestWeather(call_args_41, 1);
  
      elmc_release(tmp_40);

      ElmcValue *tmp_42 = elmc_fn_Main_requestSystemInfo(NULL, 0);
      ElmcValue *list_items_43[2] = { tmp_41, tmp_42 };
      ElmcValue *tmp_43 = elmc_list_from_values_take(list_items_43, 2);
  

        ElmcValue *tmp_44 = elmc_tuple2_take(tmp_39, tmp_43);

    tmp_1 = tmp_44;
    break;
case 6:

        // inlined Main.counterOf

      const elmc_int_t native_let_counter_45 = ELMC_RECORD_GET_INDEX_INT(model, 1 /* value */);
  
  
  

      ElmcValue *tmp_45 = model ? elmc_retain(model) : elmc_int_zero();
  
      ElmcValue *call_args_46[1] = { tmp_45 };
      ElmcValue *tmp_46 = elmc_fn_Main_temperatureOf(call_args_46, 1);
  
      elmc_release(tmp_45);

  
      ElmcValue *tmp_47 = elmc_new_int((native_let_counter_45 - 1));

      const char *rec_names_48[2] = { "temperature", "value" };
      ElmcValue *rec_values_48[2] = { tmp_46, tmp_47 };
        ElmcValue *tmp_48 = elmc_record_new_take(2, rec_names_48, rec_values_48);

      ElmcValue *tmp_49 = elmc_new_int(4);
      ElmcValue *tmp_50 = elmc_new_int(1);
      ElmcValue *tmp_51 = elmc_int_zero();
      ElmcValue *tmp_52 = elmc_int_zero();
      ElmcValue *tmp_53 = elmc_int_zero();
  
  
      ElmcValue *tmp_54 = elmc_tuple2_ints(0, 0);

        ElmcValue *tmp_55 = elmc_tuple2_take(tmp_53, tmp_54);

        ElmcValue *tmp_56 = elmc_tuple2_take(tmp_52, tmp_55);

        ElmcValue *tmp_57 = elmc_tuple2_take(tmp_51, tmp_56);

        ElmcValue *tmp_58 = elmc_tuple2_take(tmp_50, tmp_57);

        ElmcValue *tmp_59 = elmc_tuple2_take(tmp_49, tmp_58);

        ElmcValue *tmp_60 = elmc_tuple2_take(tmp_48, tmp_59);


    tmp_1 = tmp_60;
    break;
case 7:

        // inlined Main.counterOf

      const elmc_int_t native_let_counter_61 = ELMC_RECORD_GET_INDEX_INT(model, 1 /* value */);
  
  
  

      ElmcValue *tmp_61 = model ? elmc_retain(model) : elmc_int_zero();
  
      ElmcValue *call_args_62[1] = { tmp_61 };
      ElmcValue *tmp_62 = elmc_fn_Main_temperatureOf(call_args_62, 1);
  
      elmc_release(tmp_61);

  
      ElmcValue *tmp_63 = elmc_new_int((native_let_counter_61 + 1));

      const char *rec_names_64[2] = { "temperature", "value" };
      ElmcValue *rec_values_64[2] = { tmp_62, tmp_63 };
        ElmcValue *tmp_64 = elmc_record_new_take(2, rec_names_64, rec_values_64);

      ElmcValue *tmp_65 = elmc_int_zero();
        ElmcValue *tmp_66 = elmc_tuple2_take(tmp_64, tmp_65);


    tmp_1 = tmp_66;
    break;
default:
    ElmcValue *tmp_67 = model ? elmc_retain(model) : elmc_int_zero();
      ElmcValue *tmp_68 = elmc_int_zero();
        ElmcValue *tmp_69 = elmc_tuple2_take(tmp_67, tmp_68);

    tmp_1 = tmp_69;
    break;

  }

  
  
  return tmp_1;

}


ElmcValue *elmc_fn_Main_subscriptions(ElmcValue ** const args, const int argc) {
  /* Ownership policy: borrow_arg, borrow_result */
  (void)args;
  (void)argc;
ElmcValue *_ = (argc > 0) ? args[0] : NULL;
  (void)_;
  
  ElmcValue *tmp_1 = elmc_new_int(16401);
  
  
  return tmp_1;

}


ElmcValue *elmc_fn_Main_view(ElmcValue ** const args, const int argc) {
  /* Ownership policy: borrow_arg, borrow_result */
  (void)args;
  (void)argc;
ElmcValue *model = (argc > 0) ? args[0] : NULL;
  (void)model;
  // #region agent log
elmc_agent_generated_probe(0xED998100);
// #endregion

  ElmcValue *tmp_1 = elmc_new_int(ELMC_UI_NODE_WINDOW_STACK);
  
  ElmcValue *tmp_2 = elmc_new_int(ELMC_UI_NODE_WINDOW);
  ElmcValue *tmp_3 = elmc_new_int(1);
  
  ElmcValue *tmp_4 = elmc_new_int(ELMC_UI_NODE_CANVAS_LAYER);
  ElmcValue *tmp_5 = elmc_new_int(1);
  
  ElmcValue *tmp_6 = elmc_new_int(ELMC_RENDER_OP_CLEAR);
  ElmcValue *tmp_7 = elmc_new_int(ELMC_COLOR_WHITE);
  ElmcValue *tmp_8 = elmc_int_zero();
  ElmcValue *tmp_9 = elmc_int_zero();
  ElmcValue *tmp_10 = elmc_int_zero();
  
  
  ElmcValue *tmp_11 = elmc_tuple2_ints(0, 0);

    ElmcValue *tmp_12 = elmc_tuple2_take(tmp_10, tmp_11);

    ElmcValue *tmp_13 = elmc_tuple2_take(tmp_9, tmp_12);

    ElmcValue *tmp_14 = elmc_tuple2_take(tmp_8, tmp_13);

    ElmcValue *tmp_15 = elmc_tuple2_take(tmp_7, tmp_14);

    ElmcValue *tmp_16 = elmc_tuple2_take(tmp_6, tmp_15);

  ElmcValue *tmp_17 = elmc_new_int(ELMC_RENDER_OP_CONTEXT_GROUP);
  
  
  
  ElmcValue *tmp_18 = elmc_tuple2_ints(ELMC_CONTEXT_STROKE_WIDTH, 3);

  
  
  ElmcValue *tmp_19 = elmc_tuple2_ints(ELMC_CONTEXT_ANTIALIASED, 1);

  
  
  ElmcValue *tmp_20 = elmc_tuple2_ints(ELMC_CONTEXT_STROKE_COLOR, ELMC_COLOR_BLACK);

  
  
  ElmcValue *tmp_21 = elmc_tuple2_ints(ELMC_CONTEXT_FILL_COLOR, ELMC_COLOR_BLACK);

  
  
  ElmcValue *tmp_22 = elmc_tuple2_ints(ELMC_CONTEXT_TEXT_COLOR, ELMC_COLOR_BLACK);

  ElmcValue *list_items_23[5] = { tmp_18, tmp_19, tmp_20, tmp_21, tmp_22 };
  ElmcValue *tmp_23 = elmc_list_from_values_take(list_items_23, 5);
  

  
  ElmcValue *tmp_24 = elmc_new_int(17);
  ElmcValue *tmp_25 = elmc_new_int(6);
  ElmcValue *tmp_26 = elmc_new_int(6);
  ElmcValue *tmp_27 = elmc_new_int(132);
  ElmcValue *tmp_28 = elmc_new_int(70);
  
  
  ElmcValue *tmp_29 = elmc_tuple2_ints(6, ELMC_COLOR_BLACK);

    ElmcValue *tmp_30 = elmc_tuple2_take(tmp_28, tmp_29);

    ElmcValue *tmp_31 = elmc_tuple2_take(tmp_27, tmp_30);

    ElmcValue *tmp_32 = elmc_tuple2_take(tmp_26, tmp_31);

    ElmcValue *tmp_33 = elmc_tuple2_take(tmp_25, tmp_32);

    ElmcValue *tmp_34 = elmc_tuple2_take(tmp_24, tmp_33);

  ElmcValue *tmp_35 = elmc_new_int(18);
  ElmcValue *tmp_36 = elmc_new_int(20);
  ElmcValue *tmp_37 = elmc_new_int(16);
  ElmcValue *tmp_38 = elmc_new_int(36);
  ElmcValue *tmp_39 = elmc_new_int(36);
  
  
  ElmcValue *tmp_40 = elmc_tuple2_ints(0, 45000);

    ElmcValue *tmp_41 = elmc_tuple2_take(tmp_39, tmp_40);

    ElmcValue *tmp_42 = elmc_tuple2_take(tmp_38, tmp_41);

    ElmcValue *tmp_43 = elmc_tuple2_take(tmp_37, tmp_42);

    ElmcValue *tmp_44 = elmc_tuple2_take(tmp_36, tmp_43);

    ElmcValue *tmp_45 = elmc_tuple2_take(tmp_35, tmp_44);

  ElmcValue *tmp_46 = elmc_new_int(ELMC_RENDER_OP_PATH_OUTLINE);
  

  
  
  
  
  const char *rec_names_47[2] = { "x", "y" };
  elmc_int_t rec_values_47[2] = { 0, 0 };
  ElmcValue *tmp_47 = elmc_record_new_ints(2, rec_names_47, rec_values_47);

  
  
  
  const char *rec_names_48[2] = { "x", "y" };
  elmc_int_t rec_values_48[2] = { 10, 4 };
  ElmcValue *tmp_48 = elmc_record_new_ints(2, rec_names_48, rec_values_48);

  
  
  
  const char *rec_names_49[2] = { "x", "y" };
  elmc_int_t rec_values_49[2] = { 16, 14 };
  ElmcValue *tmp_49 = elmc_record_new_ints(2, rec_names_49, rec_values_49);

  
  
  
  const char *rec_names_50[2] = { "x", "y" };
  elmc_int_t rec_values_50[2] = { 8, 24 };
  ElmcValue *tmp_50 = elmc_record_new_ints(2, rec_names_50, rec_values_50);

  
  
  
  const char *rec_names_51[2] = { "x", "y" };
  elmc_int_t rec_values_51[2] = { 0, 18 };
  ElmcValue *tmp_51 = elmc_record_new_ints(2, rec_names_51, rec_values_51);

  ElmcValue *list_items_52[5] = { tmp_47, tmp_48, tmp_49, tmp_50, tmp_51 };
  ElmcValue *tmp_52 = elmc_list_from_values_take(list_items_52, 5);
  

  
  
  
  const char *rec_names_53[2] = { "x", "y" };
  elmc_int_t rec_values_53[2] = { 86, 16 };
  ElmcValue *tmp_53 = elmc_record_new_ints(2, rec_names_53, rec_values_53);

  ElmcValue *tmp_54 = elmc_int_zero();
  
  ElmcValue *call_args_55[3] = { tmp_52, tmp_53, tmp_54 };
  ElmcValue *tmp_55 = elmc_fn_Pebble_Ui_path(call_args_55, 3);
  
  elmc_release(tmp_52);
  elmc_release(tmp_53);
  elmc_release(tmp_54);

    ElmcValue *tmp_56 = elmc_tuple2_take(tmp_46, tmp_55);

  ElmcValue *tmp_57 = elmc_new_int(ELMC_RENDER_OP_PATH_FILLED);
  

  
  
  
  
  const char *rec_names_58[2] = { "x", "y" };
  elmc_int_t rec_values_58[2] = { 0, 0 };
  ElmcValue *tmp_58 = elmc_record_new_ints(2, rec_names_58, rec_values_58);

  
  
  
  const char *rec_names_59[2] = { "x", "y" };
  elmc_int_t rec_values_59[2] = { 8, 6 };
  ElmcValue *tmp_59 = elmc_record_new_ints(2, rec_names_59, rec_values_59);

  
  
  
  const char *rec_names_60[2] = { "x", "y" };
  elmc_int_t rec_values_60[2] = { 6, 14 };
  ElmcValue *tmp_60 = elmc_record_new_ints(2, rec_names_60, rec_values_60);

  
  
  
  const char *rec_names_61[2] = { "x", "y" };
  elmc_int_t rec_values_61[2] = { 2, 20 };
  ElmcValue *tmp_61 = elmc_record_new_ints(2, rec_names_61, rec_values_61);

  
  
  
  const char *rec_names_62[2] = { "x", "y" };
  elmc_int_t rec_values_62[2] = { 0, 14 };
  ElmcValue *tmp_62 = elmc_record_new_ints(2, rec_names_62, rec_values_62);

  ElmcValue *list_items_63[5] = { tmp_58, tmp_59, tmp_60, tmp_61, tmp_62 };
  ElmcValue *tmp_63 = elmc_list_from_values_take(list_items_63, 5);
  

  
  
  
  const char *rec_names_64[2] = { "x", "y" };
  elmc_int_t rec_values_64[2] = { 108, 26 };
  ElmcValue *tmp_64 = elmc_record_new_ints(2, rec_names_64, rec_values_64);

  ElmcValue *tmp_65 = elmc_int_zero();
  
  ElmcValue *call_args_66[3] = { tmp_63, tmp_64, tmp_65 };
  ElmcValue *tmp_66 = elmc_fn_Pebble_Ui_path(call_args_66, 3);
  
  elmc_release(tmp_63);
  elmc_release(tmp_64);
  elmc_release(tmp_65);

    ElmcValue *tmp_67 = elmc_tuple2_take(tmp_57, tmp_66);

  ElmcValue *tmp_68 = elmc_new_int(ELMC_RENDER_OP_PATH_OUTLINE_OPEN);
  

  
  
  
  
  const char *rec_names_69[2] = { "x", "y" };
  elmc_int_t rec_values_69[2] = { 0, 0 };
  ElmcValue *tmp_69 = elmc_record_new_ints(2, rec_names_69, rec_values_69);

  
  
  
  const char *rec_names_70[2] = { "x", "y" };
  elmc_int_t rec_values_70[2] = { 8, 4 };
  ElmcValue *tmp_70 = elmc_record_new_ints(2, rec_names_70, rec_values_70);

  
  
  
  const char *rec_names_71[2] = { "x", "y" };
  elmc_int_t rec_values_71[2] = { 16, 2 };
  ElmcValue *tmp_71 = elmc_record_new_ints(2, rec_names_71, rec_values_71);

  
  
  
  const char *rec_names_72[2] = { "x", "y" };
  elmc_int_t rec_values_72[2] = { 24, 6 };
  ElmcValue *tmp_72 = elmc_record_new_ints(2, rec_names_72, rec_values_72);

  ElmcValue *list_items_73[4] = { tmp_69, tmp_70, tmp_71, tmp_72 };
  ElmcValue *tmp_73 = elmc_list_from_values_take(list_items_73, 4);
  

  
  
  
  const char *rec_names_74[2] = { "x", "y" };
  elmc_int_t rec_values_74[2] = { 10, 78 };
  ElmcValue *tmp_74 = elmc_record_new_ints(2, rec_names_74, rec_values_74);

  ElmcValue *tmp_75 = elmc_int_zero();
  
  ElmcValue *call_args_76[3] = { tmp_73, tmp_74, tmp_75 };
  ElmcValue *tmp_76 = elmc_fn_Pebble_Ui_path(call_args_76, 3);
  
  elmc_release(tmp_73);
  elmc_release(tmp_74);
  elmc_release(tmp_75);

    ElmcValue *tmp_77 = elmc_tuple2_take(tmp_68, tmp_76);

  ElmcValue *list_items_78[5] = { tmp_34, tmp_45, tmp_56, tmp_67, tmp_77 };
  ElmcValue *tmp_78 = elmc_list_from_values_take(list_items_78, 5);
  

    ElmcValue *tmp_79 = elmc_tuple2_take(tmp_23, tmp_78);

    ElmcValue *tmp_80 = elmc_tuple2_take(tmp_17, tmp_79);

  ElmcValue *tmp_81 = elmc_new_int(4);
  ElmcValue *tmp_82 = elmc_int_zero();
  ElmcValue *tmp_83 = elmc_new_int(84);
  ElmcValue *tmp_84 = elmc_new_int(143);
  ElmcValue *tmp_85 = elmc_new_int(84);
  
  
  ElmcValue *tmp_86 = elmc_tuple2_ints(ELMC_COLOR_BLACK, 0);

    ElmcValue *tmp_87 = elmc_tuple2_take(tmp_85, tmp_86);

    ElmcValue *tmp_88 = elmc_tuple2_take(tmp_84, tmp_87);

    ElmcValue *tmp_89 = elmc_tuple2_take(tmp_83, tmp_88);

    ElmcValue *tmp_90 = elmc_tuple2_take(tmp_82, tmp_89);

    ElmcValue *tmp_91 = elmc_tuple2_take(tmp_81, tmp_90);

  ElmcValue *tmp_92 = elmc_new_int(3);
  ElmcValue *tmp_93 = elmc_new_int(72);
  ElmcValue *tmp_94 = elmc_new_int(84);
  ElmcValue *tmp_95 = elmc_new_int(ELMC_COLOR_BLACK);
  ElmcValue *tmp_96 = elmc_int_zero();
  
  
  ElmcValue *tmp_97 = elmc_tuple2_ints(0, 0);

    ElmcValue *tmp_98 = elmc_tuple2_take(tmp_96, tmp_97);

    ElmcValue *tmp_99 = elmc_tuple2_take(tmp_95, tmp_98);

    ElmcValue *tmp_100 = elmc_tuple2_take(tmp_94, tmp_99);

    ElmcValue *tmp_101 = elmc_tuple2_take(tmp_93, tmp_100);

    ElmcValue *tmp_102 = elmc_tuple2_take(tmp_92, tmp_101);

  

  ElmcValue *tmp_103 = model ? elmc_retain(model) : elmc_int_zero();
  
  ElmcValue *call_args_104[1] = { tmp_103 };
  ElmcValue *tmp_104 = elmc_fn_Main_statusDraw(call_args_104, 1);
  
  elmc_release(tmp_103);

  

  ElmcValue *tmp_105 = model ? elmc_retain(model) : elmc_int_zero();
  
  ElmcValue *call_args_106[1] = { tmp_105 };
  ElmcValue *tmp_106 = elmc_fn_Main_counterDraw(call_args_106, 1);
  
  elmc_release(tmp_105);

  ElmcValue *list_items_107[6] = { tmp_16, tmp_80, tmp_91, tmp_102, tmp_104, tmp_106 };
  ElmcValue *tmp_107 = elmc_list_from_values_take(list_items_107, 6);
  

    ElmcValue *tmp_108 = elmc_tuple2_take(tmp_5, tmp_107);

    ElmcValue *tmp_109 = elmc_tuple2_take(tmp_4, tmp_108);

  ElmcValue *list_items_110[1] = { tmp_109 };
  ElmcValue *tmp_110 = elmc_list_from_values_take(list_items_110, 1);
  

    ElmcValue *tmp_111 = elmc_tuple2_take(tmp_3, tmp_110);

    ElmcValue *tmp_112 = elmc_tuple2_take(tmp_2, tmp_111);

  ElmcValue *list_items_113[1] = { tmp_112 };
  ElmcValue *tmp_113 = elmc_list_from_values_take(list_items_113, 1);
  

    ElmcValue *tmp_114 = elmc_tuple2_take(tmp_1, tmp_113);

  
  // #region agent log
if (!tmp_114) {
  elmc_agent_generated_probe(0xED998113);
} else if (tmp_114->tag == ELMC_TAG_TUPLE2) {
  elmc_agent_generated_probe(0xED998111);
} else if (tmp_114->tag == ELMC_TAG_LIST) {
  elmc_agent_generated_probe(0xED998112);
} else {
  elmc_agent_generated_probe(0xED998110);
}

// #endregion

  return tmp_114;

}


ElmcValue *elmc_fn_Main_statusDraw(ElmcValue ** const args, const int argc) {
  /* Ownership policy: borrow_arg, borrow_result */
  (void)args;
  (void)argc;
ElmcValue *model = (argc > 0) ? args[0] : NULL;
  (void)model;
  
      


  ElmcValue *tmp_1 = model ? elmc_retain(model) : elmc_int_zero();
  
  ElmcValue *call_args_2[1] = { tmp_1 };
  ElmcValue *tmp_2 = elmc_fn_Main_temperatureOf(call_args_2, 1);
  
  elmc_release(tmp_1);

      
  
  ElmcValue *tmp_3;
  
  if (((tmp_2 && tmp_2->tag == ELMC_TAG_MAYBE && ((ElmcMaybe *)tmp_2->payload)->is_just == 1) || (tmp_2 && tmp_2->tag == ELMC_TAG_TUPLE2 && tmp_2->payload != NULL && elmc_as_int(((ElmcTuple2 *)tmp_2->payload)->first) == 1))) {


    ElmcValue *tmp_4 = elmc_new_int(27);
      ElmcValue *tmp_5 = elmc_new_int(1);
      ElmcValue *tmp_6 = elmc_int_zero();
      ElmcValue *tmp_7 = elmc_new_int(28);
  

      ElmcValue *tmp_8 = elmc_maybe_or_tuple_just_payload_borrow(tmp_2) ? elmc_retain(elmc_maybe_or_tuple_just_payload_borrow(tmp_2)) : elmc_int_zero();
  
      ElmcValue *call_args_9[1] = { tmp_8 };
      ElmcValue *tmp_9 = elmc_fn_Main_temperatureValue(call_args_9, 1);
  
      elmc_release(tmp_8);

  
  
      ElmcValue *tmp_10 = elmc_tuple2_ints(0, 0);

        ElmcValue *tmp_11 = elmc_tuple2_take(tmp_9, tmp_10);

        ElmcValue *tmp_12 = elmc_tuple2_take(tmp_7, tmp_11);

        ElmcValue *tmp_13 = elmc_tuple2_take(tmp_6, tmp_12);

        ElmcValue *tmp_14 = elmc_tuple2_take(tmp_5, tmp_13);

        ElmcValue *tmp_15 = elmc_tuple2_take(tmp_4, tmp_14);


    tmp_3 = tmp_15;


}
else {


    ElmcValue *tmp_16 = elmc_new_int(ELMC_RENDER_OP_TEXT_LABEL_WITH_FONT);
      ElmcValue *tmp_17 = elmc_new_int(1);
      ElmcValue *tmp_18 = elmc_int_zero();
      ElmcValue *tmp_19 = elmc_new_int(28);
      ElmcValue *tmp_20 = elmc_int_zero();
  
  
      ElmcValue *tmp_21 = elmc_tuple2_ints(0, 1);

        ElmcValue *tmp_22 = elmc_tuple2_take(tmp_20, tmp_21);

        ElmcValue *tmp_23 = elmc_tuple2_take(tmp_19, tmp_22);

        ElmcValue *tmp_24 = elmc_tuple2_take(tmp_18, tmp_23);

        ElmcValue *tmp_25 = elmc_tuple2_take(tmp_17, tmp_24);

        ElmcValue *tmp_26 = elmc_tuple2_take(tmp_16, tmp_25);


    tmp_3 = tmp_26;


}

  

  elmc_release(tmp_2);

  
  
  return tmp_3;

}


ElmcValue *elmc_fn_Main_counterDraw(ElmcValue ** const args, const int argc) {
  /* Ownership policy: borrow_arg, borrow_result */
  (void)args;
  (void)argc;
ElmcValue *model = (argc > 0) ? args[0] : NULL;
  (void)model;
  
  
    // inlined Main.counterOf

  const elmc_int_t native_let_counter_1 = ELMC_RECORD_GET_INDEX_INT(model, 1 /* value */);
  
  ElmcValue *tmp_1 = elmc_new_int(27);
  ElmcValue *tmp_2 = elmc_new_int(1);
  ElmcValue *tmp_3 = elmc_int_zero();
  ElmcValue *tmp_4 = elmc_new_int(56);
  ElmcValue *tmp_5 = elmc_new_int(native_let_counter_1);
  
  
  ElmcValue *tmp_6 = elmc_tuple2_ints(0, 0);

    ElmcValue *tmp_7 = elmc_tuple2_take(tmp_5, tmp_6);

    ElmcValue *tmp_8 = elmc_tuple2_take(tmp_4, tmp_7);

    ElmcValue *tmp_9 = elmc_tuple2_take(tmp_3, tmp_8);

    ElmcValue *tmp_10 = elmc_tuple2_take(tmp_2, tmp_9);

    ElmcValue *tmp_11 = elmc_tuple2_take(tmp_1, tmp_10);


  
  
  return tmp_11;

}


ElmcValue *elmc_fn_Main_temperatureValue(ElmcValue ** const args, const int argc) {
  /* Ownership policy: borrow_arg, borrow_result */
  (void)args;
  (void)argc;
ElmcValue *temperature = (argc > 0) ? args[0] : NULL;
  (void)temperature;
  
  
  ElmcValue *tmp_1;
  
  if ((temperature) && (((temperature)->tag == ELMC_TAG_INT && elmc_as_int(temperature) == 1) || ((temperature)->tag == ELMC_TAG_TUPLE2 && (temperature)->payload != NULL && elmc_as_int(((ElmcTuple2 *)(temperature)->payload)->first) == 1))) {


    ElmcValue *tmp_2 = ((ElmcTuple2 *)temperature->payload)->second ? elmc_retain(((ElmcTuple2 *)temperature->payload)->second) : elmc_int_zero();

    tmp_1 = tmp_2;


}
else {


    ElmcValue *tmp_3 = ((ElmcTuple2 *)temperature->payload)->second ? elmc_retain(((ElmcTuple2 *)temperature->payload)->second) : elmc_int_zero();

    tmp_1 = tmp_3;


}

  

  
  
  return tmp_1;

}


ElmcValue *elmc_fn_Main_main(ElmcValue ** const args, const int argc) {
  /* Ownership policy: borrow_arg, borrow_result */
  (void)args;
  (void)argc;

  
  
  ElmcValue *tmp_1 = elmc_int_zero();
  
  
  return tmp_1;

}


ElmcValue *elmc_fn_Pebble_Platform_launchReasonToInt(ElmcValue ** const args, const int argc) {
  /* Ownership policy: borrow_arg, borrow_result */
  (void)args;
  (void)argc;
ElmcValue *launchReason = (argc > 0) ? args[0] : NULL;
  (void)launchReason;
  
  
  const int case_msg_tag_1 = (launchReason && (launchReason)->tag == ELMC_TAG_INT ? elmc_as_int(launchReason) : (launchReason && (launchReason)->tag == ELMC_TAG_TUPLE2 && (launchReason)->payload != NULL ? elmc_as_int(((ElmcTuple2 *)(launchReason)->payload)->first) : -1));
  ElmcValue *tmp_1 = elmc_int_zero();
  switch (case_msg_tag_1) {
  case 1:

    tmp_1 = elmc_int_zero();
    break;
case 2:

    tmp_1 = elmc_new_int(1);
    break;
case 3:

    tmp_1 = elmc_new_int(2);
    break;
case 4:

    tmp_1 = elmc_new_int(3);
    break;
case 5:

    tmp_1 = elmc_new_int(4);
    break;
case 6:

    tmp_1 = elmc_new_int(5);
    break;
case 7:

    tmp_1 = elmc_new_int(6);
    break;
case 8:

    tmp_1 = elmc_new_int(7);
    break;
case 9:

    tmp_1 = elmc_new_int(-1);
    break;
default:
    tmp_1 = elmc_int_zero();
    break;

  }

  
  
  return tmp_1;

}


ElmcValue *elmc_fn_Pebble_Ui_path(ElmcValue ** const args, const int argc) {
  /* Ownership policy: borrow_arg, retain_result */
  (void)args;
  (void)argc;
ElmcValue *points = (argc > 0) ? args[0] : NULL;
  ElmcValue *offset = (argc > 1) ? args[1] : NULL;
  ElmcValue *rotation = (argc > 2) ? args[2] : NULL;
  (void)points;
  (void)offset;
  (void)rotation;
  
  
    
  ElmcValue *tmp_1 = elmc_closure_new(elmc_lambda_1, 1, 0, NULL);

  ElmcValue *tmp_2 = points ? elmc_retain(points) : elmc_int_zero();
  ElmcValue *tmp_3 = elmc_list_map(tmp_1, tmp_2);
  elmc_release(tmp_1);
  elmc_release(tmp_2);
  

  
  
  ElmcValue *tmp_4 = elmc_tuple2_ints(ELMC_RECORD_GET_INDEX_INT(offset, 0 /* x */), ELMC_RECORD_GET_INDEX_INT(offset, 1 /* y */));

  

  ElmcValue *tmp_5 = rotation ? elmc_retain(rotation) : elmc_int_zero();
  
  ElmcValue *call_args_6[1] = { tmp_5 };
  ElmcValue *tmp_6 = elmc_fn_Pebble_Ui_rotationToPebbleAngle(call_args_6, 1);
  
  elmc_release(tmp_5);

    ElmcValue *tmp_7 = elmc_tuple2_take(tmp_4, tmp_6);

    ElmcValue *tmp_8 = elmc_tuple2_take(tmp_3, tmp_7);

  
  
  return tmp_8;

}


ElmcValue *elmc_fn_Pebble_Ui_rotationToPebbleAngle(ElmcValue ** const args, const int argc) {
  /* Ownership policy: borrow_arg, borrow_result */
  (void)args;
  (void)argc;

  
  
    
  ElmcValue *tmp_1 = elmc_closure_new(elmc_lambda_2, 1, 0, NULL);

  
  
  return tmp_1;

}


ElmcValue *elmc_fn_Companion_Internal_encodeLocationCode(ElmcValue ** const args, const int argc) {
  /* Ownership policy: borrow_arg, borrow_result */
  (void)args;
  (void)argc;
ElmcValue *value = (argc > 0) ? args[0] : NULL;
  (void)value;
  
  
  const int case_msg_tag_1 = (value && (value)->tag == ELMC_TAG_INT ? elmc_as_int(value) : (value && (value)->tag == ELMC_TAG_TUPLE2 && (value)->payload != NULL ? elmc_as_int(((ElmcTuple2 *)(value)->payload)->first) : -1));
  ElmcValue *tmp_1 = elmc_int_zero();
  switch (case_msg_tag_1) {
  case 1:

    tmp_1 = elmc_new_int(1);
    break;
case 2:

    tmp_1 = elmc_new_int(2);
    break;
case 3:

    tmp_1 = elmc_new_int(3);
    break;
case 4:

    tmp_1 = elmc_new_int(4);
    break;
default:
    tmp_1 = elmc_int_zero();
    break;

  }

  
  
  return tmp_1;

}


ElmcValue *elmc_fn_Companion_Internal_watchToPhoneTag(ElmcValue ** const args, const int argc) {
  /* Ownership policy: borrow_arg, borrow_result */
  (void)args;
  (void)argc;
ElmcValue *message = (argc > 0) ? args[0] : NULL;
  (void)message;
  
  
  ElmcValue *tmp_1;
  
  



    tmp_1 = elmc_new_int(2);


  

  
  
  return tmp_1;

}


ElmcValue *elmc_fn_Companion_Internal_watchToPhoneValue(ElmcValue ** const args, const int argc) {
  /* Ownership policy: borrow_arg, borrow_result */
  (void)args;
  (void)argc;
ElmcValue *message = (argc > 0) ? args[0] : NULL;
  (void)message;
  
  
  ElmcValue *tmp_1;
  
  



      ElmcValue *tmp_2 = ((ElmcTuple2 *)message->payload)->second ? elmc_retain(((ElmcTuple2 *)message->payload)->second) : elmc_int_zero();
  
      ElmcValue *call_args_3[1] = { tmp_2 };
      ElmcValue *tmp_3 = elmc_fn_Companion_Internal_encodeLocationCode(call_args_3, 1);
  
      elmc_release(tmp_2);


    tmp_1 = tmp_3;


  

  
  
  return tmp_1;

}


ElmcValue *elmc_fn_Companion_Watch_sendWatchToPhone(ElmcValue ** const args, const int argc) {
  /* Ownership policy: borrow_arg, borrow_result */
  (void)args;
  (void)argc;
ElmcValue *message = (argc > 0) ? args[0] : NULL;
  (void)message;
  
  ElmcValue *tmp_1 = elmc_new_int(5);
  

  ElmcValue *tmp_2 = message ? elmc_retain(message) : elmc_int_zero();
  
  ElmcValue *call_args_3[1] = { tmp_2 };
  ElmcValue *tmp_3 = elmc_fn_Companion_Internal_watchToPhoneTag(call_args_3, 1);
  
  elmc_release(tmp_2);

  

  ElmcValue *tmp_4 = message ? elmc_retain(message) : elmc_int_zero();
  
  ElmcValue *call_args_5[1] = { tmp_4 };
  ElmcValue *tmp_5 = elmc_fn_Companion_Internal_watchToPhoneValue(call_args_5, 1);
  
  elmc_release(tmp_4);

  ElmcValue *tmp_6 = elmc_int_zero();
  ElmcValue *tmp_7 = elmc_int_zero();
  
  
  ElmcValue *tmp_8 = elmc_tuple2_ints(0, 0);

    ElmcValue *tmp_9 = elmc_tuple2_take(tmp_7, tmp_8);

    ElmcValue *tmp_10 = elmc_tuple2_take(tmp_6, tmp_9);

    ElmcValue *tmp_11 = elmc_tuple2_take(tmp_5, tmp_10);

    ElmcValue *tmp_12 = elmc_tuple2_take(tmp_3, tmp_11);

    ElmcValue *tmp_13 = elmc_tuple2_take(tmp_1, tmp_12);

  
  
  return tmp_13;

}


static int elmc_fn_Main_view_commands_append(ElmcValue ** const args, const int argc, ElmcGeneratedPebbleDrawCmd * const out_cmds, const int max_cmds, const int skip, int * const count, int * const emitted);

static int elmc_fn_Main_view_commands_append(ElmcValue ** const args, const int argc, ElmcGeneratedPebbleDrawCmd * const out_cmds, const int max_cmds, const int skip, int * const count, int * const emitted) {
  (void)args;
  (void)argc;
  ElmcValue *model = (argc > 0) ? args[0] : NULL;
  (void)model;
  if (!out_cmds || !count || !emitted || max_cmds <= 0) return -1;
  int direct_stop = 0;
  


 if (!direct_stop && *emitted >= skip && *count < max_cmds) {

  elmc_generated_draw_init(&out_cmds[*count], ELMC_RENDER_OP_CLEAR);
    out_cmds[*count].p0 = ELMC_COLOR_WHITE;
    *count += 1;
  }
 if (!direct_stop) {
   *emitted += 1;
   if (*count >= max_cmds) direct_stop = 1;
 }

 if (!direct_stop && *emitted >= skip && *count < max_cmds) {

  elmc_generated_draw_init(&out_cmds[*count], ELMC_RENDER_OP_PUSH_CONTEXT);
    
    *count += 1;
  }
 if (!direct_stop) {
   *emitted += 1;
   if (*count >= max_cmds) direct_stop = 1;
 }
 if (!direct_stop && *emitted >= skip && *count < max_cmds) {

  elmc_generated_draw_init(&out_cmds[*count], ELMC_RENDER_OP_STROKE_WIDTH);
    out_cmds[*count].p0 = 3;
    *count += 1;
  }
 if (!direct_stop) {
   *emitted += 1;
   if (*count >= max_cmds) direct_stop = 1;
 }
 if (!direct_stop && *emitted >= skip && *count < max_cmds) {

  elmc_generated_draw_init(&out_cmds[*count], ELMC_RENDER_OP_ANTIALIASED);
    out_cmds[*count].p0 = 1;
    *count += 1;
  }
 if (!direct_stop) {
   *emitted += 1;
   if (*count >= max_cmds) direct_stop = 1;
 }
 if (!direct_stop && *emitted >= skip && *count < max_cmds) {

  elmc_generated_draw_init(&out_cmds[*count], ELMC_RENDER_OP_STROKE_COLOR);
    out_cmds[*count].p0 = ELMC_COLOR_BLACK;
    *count += 1;
  }
 if (!direct_stop) {
   *emitted += 1;
   if (*count >= max_cmds) direct_stop = 1;
 }
 if (!direct_stop && *emitted >= skip && *count < max_cmds) {

  elmc_generated_draw_init(&out_cmds[*count], ELMC_RENDER_OP_FILL_COLOR);
    out_cmds[*count].p0 = ELMC_COLOR_BLACK;
    *count += 1;
  }
 if (!direct_stop) {
   *emitted += 1;
   if (*count >= max_cmds) direct_stop = 1;
 }
 if (!direct_stop && *emitted >= skip && *count < max_cmds) {

  elmc_generated_draw_init(&out_cmds[*count], ELMC_RENDER_OP_TEXT_COLOR);
    out_cmds[*count].p0 = ELMC_COLOR_BLACK;
    *count += 1;
  }
 if (!direct_stop) {
   *emitted += 1;
   if (*count >= max_cmds) direct_stop = 1;
 }

 if (!direct_stop && *emitted >= skip && *count < max_cmds) {

  elmc_generated_draw_init(&out_cmds[*count], ELMC_RENDER_OP_ROUND_RECT);
    out_cmds[*count].p0 = 6;
  out_cmds[*count].p1 = 6;
  out_cmds[*count].p2 = 132;
  out_cmds[*count].p3 = 70;
  out_cmds[*count].p4 = 6;
  out_cmds[*count].p5 = ELMC_COLOR_BLACK;
    *count += 1;
  }
 if (!direct_stop) {
   *emitted += 1;
   if (*count >= max_cmds) direct_stop = 1;
 }

 if (!direct_stop && *emitted >= skip && *count < max_cmds) {

  elmc_generated_draw_init(&out_cmds[*count], ELMC_RENDER_OP_ARC);
    out_cmds[*count].p0 = 20;
  out_cmds[*count].p1 = 16;
  out_cmds[*count].p2 = 36;
  out_cmds[*count].p3 = 36;
  out_cmds[*count].p4 = 0;
  out_cmds[*count].p5 = 45000;
    *count += 1;
  }
 if (!direct_stop) {
   *emitted += 1;
   if (*count >= max_cmds) direct_stop = 1;
 }

  if (!direct_stop && *emitted >= skip && *count < max_cmds) {




  elmc_generated_draw_init(&out_cmds[*count], ELMC_RENDER_OP_PATH_OUTLINE);
    out_cmds[*count].path_point_count = 5;
    out_cmds[*count].path_offset_x = 86;
    out_cmds[*count].path_offset_y = 16;
    out_cmds[*count].path_rotation = 0;
    out_cmds[*count].path_x[0] = 0;
    out_cmds[*count].path_y[0] = 0;

    out_cmds[*count].path_x[1] = 10;
    out_cmds[*count].path_y[1] = 4;

    out_cmds[*count].path_x[2] = 16;
    out_cmds[*count].path_y[2] = 14;

    out_cmds[*count].path_x[3] = 8;
    out_cmds[*count].path_y[3] = 24;

    out_cmds[*count].path_x[4] = 0;
    out_cmds[*count].path_y[4] = 18;

    *count += 1;
  }
  if (!direct_stop) {
    *emitted += 1;
    if (*count >= max_cmds) direct_stop = 1;
  }

  if (!direct_stop && *emitted >= skip && *count < max_cmds) {




  elmc_generated_draw_init(&out_cmds[*count], ELMC_RENDER_OP_PATH_FILLED);
    out_cmds[*count].path_point_count = 5;
    out_cmds[*count].path_offset_x = 108;
    out_cmds[*count].path_offset_y = 26;
    out_cmds[*count].path_rotation = 0;
    out_cmds[*count].path_x[0] = 0;
    out_cmds[*count].path_y[0] = 0;

    out_cmds[*count].path_x[1] = 8;
    out_cmds[*count].path_y[1] = 6;

    out_cmds[*count].path_x[2] = 6;
    out_cmds[*count].path_y[2] = 14;

    out_cmds[*count].path_x[3] = 2;
    out_cmds[*count].path_y[3] = 20;

    out_cmds[*count].path_x[4] = 0;
    out_cmds[*count].path_y[4] = 14;

    *count += 1;
  }
  if (!direct_stop) {
    *emitted += 1;
    if (*count >= max_cmds) direct_stop = 1;
  }

  if (!direct_stop && *emitted >= skip && *count < max_cmds) {




  elmc_generated_draw_init(&out_cmds[*count], ELMC_RENDER_OP_PATH_OUTLINE_OPEN);
    out_cmds[*count].path_point_count = 4;
    out_cmds[*count].path_offset_x = 10;
    out_cmds[*count].path_offset_y = 78;
    out_cmds[*count].path_rotation = 0;
    out_cmds[*count].path_x[0] = 0;
    out_cmds[*count].path_y[0] = 0;

    out_cmds[*count].path_x[1] = 8;
    out_cmds[*count].path_y[1] = 4;

    out_cmds[*count].path_x[2] = 16;
    out_cmds[*count].path_y[2] = 2;

    out_cmds[*count].path_x[3] = 24;
    out_cmds[*count].path_y[3] = 6;

    *count += 1;
  }
  if (!direct_stop) {
    *emitted += 1;
    if (*count >= max_cmds) direct_stop = 1;
  }
 if (!direct_stop && *emitted >= skip && *count < max_cmds) {

  elmc_generated_draw_init(&out_cmds[*count], ELMC_RENDER_OP_POP_CONTEXT);
    
    *count += 1;
  }
 if (!direct_stop) {
   *emitted += 1;
   if (*count >= max_cmds) direct_stop = 1;
 }

 if (!direct_stop && *emitted >= skip && *count < max_cmds) {

  elmc_generated_draw_init(&out_cmds[*count], ELMC_RENDER_OP_LINE);
    out_cmds[*count].p0 = 0;
  out_cmds[*count].p1 = 84;
  out_cmds[*count].p2 = 143;
  out_cmds[*count].p3 = 84;
  out_cmds[*count].p4 = ELMC_COLOR_BLACK;
    *count += 1;
  }
 if (!direct_stop) {
   *emitted += 1;
   if (*count >= max_cmds) direct_stop = 1;
 }

 if (!direct_stop && *emitted >= skip && *count < max_cmds) {

  elmc_generated_draw_init(&out_cmds[*count], ELMC_RENDER_OP_PIXEL);
    out_cmds[*count].p0 = 72;
  out_cmds[*count].p1 = 84;
  out_cmds[*count].p2 = ELMC_COLOR_BLACK;
    *count += 1;
  }
 if (!direct_stop) {
   *emitted += 1;
   if (*count >= max_cmds) direct_stop = 1;
 }

if (!direct_stop) {

  ElmcValue *tmp_13 = model ? elmc_retain(model) : elmc_int_zero();
if (!direct_stop) {


    ElmcValue *tmp_14 = tmp_13 ? elmc_retain(tmp_13) : elmc_int_zero();
  
    ElmcValue *call_args_15[1] = { tmp_14 };
    ElmcValue *tmp_15 = elmc_fn_Main_temperatureOf(call_args_15, 1);
  
    elmc_release(tmp_14);

  if (((tmp_15 && tmp_15->tag == ELMC_TAG_MAYBE && ((ElmcMaybe *)tmp_15->payload)->is_just == 1) || (tmp_15 && tmp_15->tag == ELMC_TAG_TUPLE2 && tmp_15->payload != NULL && elmc_as_int(((ElmcTuple2 *)tmp_15->payload)->first) == 1))) {

     if (!direct_stop && *emitted >= skip && *count < max_cmds) {


          ElmcValue *tmp_16 = elmc_maybe_or_tuple_just_payload_borrow(tmp_15) ? elmc_retain(elmc_maybe_or_tuple_just_payload_borrow(tmp_15)) : elmc_int_zero();
  
          ElmcValue *call_args_17[1] = { tmp_16 };
          ElmcValue *tmp_17 = elmc_fn_Main_temperatureValue(call_args_17, 1);
  
          elmc_release(tmp_16);

          const elmc_int_t native_i_18 = elmc_as_int(tmp_17);
          elmc_release(tmp_17);

      elmc_generated_draw_init(&out_cmds[*count], ELMC_RENDER_OP_TEXT_INT_WITH_FONT);
        out_cmds[*count].p0 = 1;
      out_cmds[*count].p1 = 0;
      out_cmds[*count].p2 = 28;
      out_cmds[*count].p3 = native_i_18;
        *count += 1;
      }
     if (!direct_stop) {
       *emitted += 1;
       if (*count >= max_cmds) direct_stop = 1;
     }



}
else if (((tmp_15 && tmp_15->tag == ELMC_TAG_MAYBE && ((ElmcMaybe *)tmp_15->payload)->is_just == 0) || (tmp_15 && tmp_15->tag == ELMC_TAG_INT && elmc_as_int(tmp_15) == 0))) {

      if (!direct_stop && *emitted >= skip && *count < max_cmds) {

      ElmcValue *tmp_20 = elmc_new_int(1);
      elmc_generated_draw_init(&out_cmds[*count], ELMC_RENDER_OP_TEXT_LABEL_WITH_FONT);
        out_cmds[*count].p0 = 1;
      out_cmds[*count].p1 = 0;
      out_cmds[*count].p2 = 28;
      out_cmds[*count].p3 = 0;
      out_cmds[*count].p4 = 0;
        if (tmp_20 && tmp_20->tag == ELMC_TAG_STRING && tmp_20->payload) {
          const char *direct_text = (const char *)tmp_20->payload;
          int direct_text_i = 0;
          while (direct_text[direct_text_i] && direct_text_i < 63) {
            out_cmds[*count].text[direct_text_i] = direct_text[direct_text_i];
            direct_text_i++;
          }
          out_cmds[*count].text[direct_text_i] = '\0';

        }

        *count += 1;
        elmc_release(tmp_20);
      }
      if (!direct_stop) {
        *emitted += 1;
        if (*count >= max_cmds) direct_stop = 1;
      }



}

  elmc_release(tmp_15);
}

  elmc_release(tmp_13);
}

if (!direct_stop) {

  ElmcValue *tmp_21 = model ? elmc_retain(model) : elmc_int_zero();
if (!direct_stop) {
    // inlined Main.counterOf

  const elmc_int_t direct_native_let_counter_22 = ELMC_RECORD_GET_INDEX_INT(tmp_21, 1 /* value */);
   if (!direct_stop && *emitted >= skip && *count < max_cmds) {

    elmc_generated_draw_init(&out_cmds[*count], ELMC_RENDER_OP_TEXT_INT_WITH_FONT);
      out_cmds[*count].p0 = 1;
    out_cmds[*count].p1 = 0;
    out_cmds[*count].p2 = 56;
    out_cmds[*count].p3 = direct_native_let_counter_22;
      *count += 1;
    }
   if (!direct_stop) {
     *emitted += 1;
     if (*count >= max_cmds) direct_stop = 1;
   }

}

  elmc_release(tmp_21);
}

  return 0;
}

int elmc_fn_Main_view_commands(ElmcValue ** const args, const int argc, void * const out_cmds, const int max_cmds) {
  return elmc_fn_Main_view_commands_from(args, argc, out_cmds, max_cmds, 0, NULL);
}

int elmc_fn_Main_view_commands_from(ElmcValue ** const args, const int argc, void * const out_cmds, const int max_cmds, const int skip, int *out_emitted) {
  int count = 0;
  int emitted = 0;
  if (!out_cmds || max_cmds <= 0) return -1;
  if (skip < 0) return -1;
  int rc = elmc_fn_Main_view_commands_append(args, argc, (ElmcGeneratedPebbleDrawCmd *)out_cmds, max_cmds, skip, &count, &emitted);
  if (out_emitted) *out_emitted = emitted;
  return rc < 0 ? rc : count;
}

