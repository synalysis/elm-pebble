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

typedef int (*ElmcDirectCommandsAppendFn)(
    ElmcValue ** const args, const int argc,
    ElmcGeneratedPebbleDrawCmd * const out_cmds, const int max_cmds,
    const int skip, int * const count, int * const emitted);

static inline int elmc_direct_commands_from(
    ElmcDirectCommandsAppendFn append,
    ElmcValue ** const args, const int argc,
    void * const out_cmds, const int max_cmds,
    const int skip, int *out_emitted) {
  int count = 0;
  int emitted = 0;
  if (!out_cmds || max_cmds <= 0) return -1;
  if (skip < 0) return -1;
  int rc = append(args, argc, (ElmcGeneratedPebbleDrawCmd *)out_cmds, max_cmds, skip, &count, &emitted);
  if (out_emitted) *out_emitted = emitted;
  return rc < 0 ? rc : count;
}




ElmcValue *elmc_fn_Main_parseHourFromTimeString(ElmcValue ** const args, const int argc);
ElmcValue *elmc_fn_Main_highRateAccelConfig(ElmcValue ** const args, const int argc);
ElmcValue *elmc_fn_Main_init(ElmcValue ** const args, const int argc);
ElmcValue *elmc_fn_Main_update(ElmcValue ** const args, const int argc);
ElmcValue *elmc_fn_Main_subscriptions(ElmcValue ** const args, const int argc);
ElmcValue *elmc_fn_Main_view(ElmcValue ** const args, const int argc);
ElmcValue *elmc_fn_Main_main(ElmcValue ** const args, const int argc);
ElmcValue *elmc_fn_Pebble_DataLog_tag(ElmcValue ** const args, const int argc);
ElmcValue *elmc_fn_Pebble_Light_interaction(ElmcValue ** const args, const int argc);
ElmcValue *elmc_fn_Pebble_Light_disable(ElmcValue ** const args, const int argc);
ElmcValue *elmc_fn_Pebble_Light_enable(ElmcValue ** const args, const int argc);
ElmcValue *elmc_fn_Pebble_Log_infoCode(ElmcValue ** const args, const int argc);
ElmcValue *elmc_fn_Pebble_Log_warnCode(ElmcValue ** const args, const int argc);
ElmcValue *elmc_fn_Pebble_Log_errorCode(ElmcValue ** const args, const int argc);
ElmcValue *elmc_fn_Pebble_Platform_launchReasonToInt(ElmcValue ** const args, const int argc);
ElmcValue *elmc_fn_Pebble_Wakeup_scheduleAfterSeconds(ElmcValue ** const args, const int argc);
ElmcValue *elmc_fn_Pebble_Wakeup_cancel(ElmcValue ** const args, const int argc);




ElmcValue *elmc_fn_Main_parseHourFromTimeString(ElmcValue ** const args, const int argc) {
  /* Ownership policy: retain_arg, retain_result */
  (void)args;
  (void)argc;
ElmcValue *value = (argc > 0) ? args[0] : NULL;
  (void)value;
  
  
  ElmcValue *tmp_1 = elmc_int_zero();
  
  
  ElmcValue *tmp_2 = elmc_new_int(2);
  ElmcValue *tmp_3 = value ? elmc_retain(value) : elmc_int_zero();
  ElmcValue *tmp_4 = elmc_string_left(tmp_2, tmp_3);
  elmc_release(tmp_2);
  elmc_release(tmp_3);
  

  ElmcValue *tmp_5 = elmc_string_to_int(tmp_4);
  elmc_release(tmp_4);
  

  ElmcValue *tmp_6 = elmc_maybe_with_default(tmp_1, tmp_5);
  elmc_release(tmp_1);
  elmc_release(tmp_5);
  

  
  
  return tmp_6;

}


ElmcValue *elmc_fn_Main_highRateAccelConfig(ElmcValue ** const args, const int argc) {
  /* Ownership policy: borrow_arg, borrow_result */
  (void)args;
  (void)argc;

  
  
  
  
  
  const char *rec_names_1[2] = { "samplesPerUpdate", "samplingRate" };
  elmc_int_t rec_values_1[2] = { 2, 4 };
  ElmcValue *tmp_1 = elmc_record_new_ints(2, rec_names_1, rec_values_1);

  
  
  return tmp_1;

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

  const elmc_int_t native_let_launchReasonValue_4 = native_i_3;
  
  
  ElmcValue *tmp_4 = elmc_new_string("00:00");
  ElmcValue *tmp_5 = elmc_new_int(native_let_launchReasonValue_4);
  const char *rec_names_6[2] = { "latestTime", "ticks" };
  ElmcValue *rec_values_6[2] = { tmp_4, tmp_5 };
    ElmcValue *tmp_6 = elmc_record_new_take(2, rec_names_6, rec_values_6);

  
  ElmcValue *tmp_7 = elmc_new_int(ELMC_PEBBLE_CMD_NONE);
  ElmcValue *tmp_8 = elmc_new_int(ELMC_PEBBLE_CMD_TIMER_AFTER_MS);
  ElmcValue *tmp_9 = elmc_new_int(1000);
  ElmcValue *tmp_10 = elmc_int_zero();
  ElmcValue *tmp_11 = elmc_int_zero();
  ElmcValue *tmp_12 = elmc_int_zero();
  
  
  ElmcValue *tmp_13 = elmc_tuple2_ints(0, 0);

    ElmcValue *tmp_14 = elmc_tuple2_take(tmp_12, tmp_13);

    ElmcValue *tmp_15 = elmc_tuple2_take(tmp_11, tmp_14);

    ElmcValue *tmp_16 = elmc_tuple2_take(tmp_10, tmp_15);

    ElmcValue *tmp_17 = elmc_tuple2_take(tmp_9, tmp_16);

    ElmcValue *tmp_18 = elmc_tuple2_take(tmp_8, tmp_17);

  ElmcValue *tmp_19 = elmc_new_int(ELMC_PEBBLE_CMD_GET_CURRENT_DATE_TIME);
  ElmcValue *tmp_20 = elmc_new_int(16);
  ElmcValue *tmp_21 = elmc_int_zero();
  ElmcValue *tmp_22 = elmc_int_zero();
  ElmcValue *tmp_23 = elmc_int_zero();
  
  
  ElmcValue *tmp_24 = elmc_tuple2_ints(0, 0);

    ElmcValue *tmp_25 = elmc_tuple2_take(tmp_23, tmp_24);

    ElmcValue *tmp_26 = elmc_tuple2_take(tmp_22, tmp_25);

    ElmcValue *tmp_27 = elmc_tuple2_take(tmp_21, tmp_26);

    ElmcValue *tmp_28 = elmc_tuple2_take(tmp_20, tmp_27);

    ElmcValue *tmp_29 = elmc_tuple2_take(tmp_19, tmp_28);

  ElmcValue *tmp_30 = elmc_new_int(ELMC_PEBBLE_CMD_GET_CURRENT_DATE_TIME);
  ElmcValue *tmp_31 = elmc_new_int(16);
  ElmcValue *tmp_32 = elmc_int_zero();
  ElmcValue *tmp_33 = elmc_int_zero();
  ElmcValue *tmp_34 = elmc_int_zero();
  
  
  ElmcValue *tmp_35 = elmc_tuple2_ints(0, 0);

    ElmcValue *tmp_36 = elmc_tuple2_take(tmp_34, tmp_35);

    ElmcValue *tmp_37 = elmc_tuple2_take(tmp_33, tmp_36);

    ElmcValue *tmp_38 = elmc_tuple2_take(tmp_32, tmp_37);

    ElmcValue *tmp_39 = elmc_tuple2_take(tmp_31, tmp_38);

    ElmcValue *tmp_40 = elmc_tuple2_take(tmp_30, tmp_39);

  ElmcValue *tmp_41 = elmc_new_int(ELMC_PEBBLE_CMD_GET_CURRENT_TIME_STRING);
  ElmcValue *tmp_42 = elmc_new_int(17);
  ElmcValue *tmp_43 = elmc_int_zero();
  ElmcValue *tmp_44 = elmc_int_zero();
  ElmcValue *tmp_45 = elmc_int_zero();
  
  
  ElmcValue *tmp_46 = elmc_tuple2_ints(0, 0);

    ElmcValue *tmp_47 = elmc_tuple2_take(tmp_45, tmp_46);

    ElmcValue *tmp_48 = elmc_tuple2_take(tmp_44, tmp_47);

    ElmcValue *tmp_49 = elmc_tuple2_take(tmp_43, tmp_48);

    ElmcValue *tmp_50 = elmc_tuple2_take(tmp_42, tmp_49);

    ElmcValue *tmp_51 = elmc_tuple2_take(tmp_41, tmp_50);

  ElmcValue *tmp_52 = elmc_new_int(ELMC_PEBBLE_CMD_GET_CLOCK_STYLE_24H);
  ElmcValue *tmp_53 = elmc_new_int(18);
  ElmcValue *tmp_54 = elmc_int_zero();
  ElmcValue *tmp_55 = elmc_int_zero();
  ElmcValue *tmp_56 = elmc_int_zero();
  
  
  ElmcValue *tmp_57 = elmc_tuple2_ints(0, 0);

    ElmcValue *tmp_58 = elmc_tuple2_take(tmp_56, tmp_57);

    ElmcValue *tmp_59 = elmc_tuple2_take(tmp_55, tmp_58);

    ElmcValue *tmp_60 = elmc_tuple2_take(tmp_54, tmp_59);

    ElmcValue *tmp_61 = elmc_tuple2_take(tmp_53, tmp_60);

    ElmcValue *tmp_62 = elmc_tuple2_take(tmp_52, tmp_61);

  ElmcValue *tmp_63 = elmc_new_int(ELMC_PEBBLE_CMD_GET_TIMEZONE_IS_SET);
  ElmcValue *tmp_64 = elmc_new_int(19);
  ElmcValue *tmp_65 = elmc_int_zero();
  ElmcValue *tmp_66 = elmc_int_zero();
  ElmcValue *tmp_67 = elmc_int_zero();
  
  
  ElmcValue *tmp_68 = elmc_tuple2_ints(0, 0);

    ElmcValue *tmp_69 = elmc_tuple2_take(tmp_67, tmp_68);

    ElmcValue *tmp_70 = elmc_tuple2_take(tmp_66, tmp_69);

    ElmcValue *tmp_71 = elmc_tuple2_take(tmp_65, tmp_70);

    ElmcValue *tmp_72 = elmc_tuple2_take(tmp_64, tmp_71);

    ElmcValue *tmp_73 = elmc_tuple2_take(tmp_63, tmp_72);

  ElmcValue *tmp_74 = elmc_new_int(ELMC_PEBBLE_CMD_GET_TIMEZONE);
  ElmcValue *tmp_75 = elmc_new_int(20);
  ElmcValue *tmp_76 = elmc_int_zero();
  ElmcValue *tmp_77 = elmc_int_zero();
  ElmcValue *tmp_78 = elmc_int_zero();
  
  
  ElmcValue *tmp_79 = elmc_tuple2_ints(0, 0);

    ElmcValue *tmp_80 = elmc_tuple2_take(tmp_78, tmp_79);

    ElmcValue *tmp_81 = elmc_tuple2_take(tmp_77, tmp_80);

    ElmcValue *tmp_82 = elmc_tuple2_take(tmp_76, tmp_81);

    ElmcValue *tmp_83 = elmc_tuple2_take(tmp_75, tmp_82);

    ElmcValue *tmp_84 = elmc_tuple2_take(tmp_74, tmp_83);

  ElmcValue *tmp_85 = elmc_new_int(ELMC_PEBBLE_CMD_STORAGE_WRITE_INT);
  ElmcValue *tmp_86 = elmc_new_int(7);
  ElmcValue *tmp_87 = elmc_new_int(42);
  ElmcValue *tmp_88 = elmc_int_zero();
  ElmcValue *tmp_89 = elmc_int_zero();
  
  
  ElmcValue *tmp_90 = elmc_tuple2_ints(0, 0);

    ElmcValue *tmp_91 = elmc_tuple2_take(tmp_89, tmp_90);

    ElmcValue *tmp_92 = elmc_tuple2_take(tmp_88, tmp_91);

    ElmcValue *tmp_93 = elmc_tuple2_take(tmp_87, tmp_92);

    ElmcValue *tmp_94 = elmc_tuple2_take(tmp_86, tmp_93);

    ElmcValue *tmp_95 = elmc_tuple2_take(tmp_85, tmp_94);

  ElmcValue *tmp_96 = elmc_new_int(ELMC_PEBBLE_CMD_STORAGE_READ_INT);
  ElmcValue *tmp_97 = elmc_new_int(7);
  ElmcValue *tmp_98 = elmc_new_int(21);
  ElmcValue *tmp_99 = elmc_int_zero();
  ElmcValue *tmp_100 = elmc_int_zero();
  
  
  ElmcValue *tmp_101 = elmc_tuple2_ints(0, 0);

    ElmcValue *tmp_102 = elmc_tuple2_take(tmp_100, tmp_101);

    ElmcValue *tmp_103 = elmc_tuple2_take(tmp_99, tmp_102);

    ElmcValue *tmp_104 = elmc_tuple2_take(tmp_98, tmp_103);

    ElmcValue *tmp_105 = elmc_tuple2_take(tmp_97, tmp_104);

    ElmcValue *tmp_106 = elmc_tuple2_take(tmp_96, tmp_105);

  ElmcValue *tmp_107 = elmc_new_int(ELMC_PEBBLE_CMD_STORAGE_WRITE_STRING);
  ElmcValue *tmp_108 = elmc_new_int(8);
  ElmcValue *tmp_109 = elmc_new_string("saved");
  ElmcValue *tmp_110 = elmc_int_zero();
  ElmcValue *tmp_111 = elmc_int_zero();
  
  
  ElmcValue *tmp_112 = elmc_tuple2_ints(0, 0);

    ElmcValue *tmp_113 = elmc_tuple2_take(tmp_111, tmp_112);

    ElmcValue *tmp_114 = elmc_tuple2_take(tmp_110, tmp_113);

    ElmcValue *tmp_115 = elmc_tuple2_take(tmp_109, tmp_114);

    ElmcValue *tmp_116 = elmc_tuple2_take(tmp_108, tmp_115);

    ElmcValue *tmp_117 = elmc_tuple2_take(tmp_107, tmp_116);

  ElmcValue *tmp_118 = elmc_new_int(ELMC_PEBBLE_CMD_STORAGE_READ_STRING);
  ElmcValue *tmp_119 = elmc_new_int(8);
  ElmcValue *tmp_120 = elmc_new_int(22);
  ElmcValue *tmp_121 = elmc_int_zero();
  ElmcValue *tmp_122 = elmc_int_zero();
  
  
  ElmcValue *tmp_123 = elmc_tuple2_ints(0, 0);

    ElmcValue *tmp_124 = elmc_tuple2_take(tmp_122, tmp_123);

    ElmcValue *tmp_125 = elmc_tuple2_take(tmp_121, tmp_124);

    ElmcValue *tmp_126 = elmc_tuple2_take(tmp_120, tmp_125);

    ElmcValue *tmp_127 = elmc_tuple2_take(tmp_119, tmp_126);

    ElmcValue *tmp_128 = elmc_tuple2_take(tmp_118, tmp_127);

  ElmcValue *tmp_129 = elmc_new_int(ELMC_PEBBLE_CMD_STORAGE_DELETE);
  ElmcValue *tmp_130 = elmc_new_int(7);
  ElmcValue *tmp_131 = elmc_int_zero();
  ElmcValue *tmp_132 = elmc_int_zero();
  ElmcValue *tmp_133 = elmc_int_zero();
  
  
  ElmcValue *tmp_134 = elmc_tuple2_ints(0, 0);

    ElmcValue *tmp_135 = elmc_tuple2_take(tmp_133, tmp_134);

    ElmcValue *tmp_136 = elmc_tuple2_take(tmp_132, tmp_135);

    ElmcValue *tmp_137 = elmc_tuple2_take(tmp_131, tmp_136);

    ElmcValue *tmp_138 = elmc_tuple2_take(tmp_130, tmp_137);

    ElmcValue *tmp_139 = elmc_tuple2_take(tmp_129, tmp_138);

  ElmcValue *tmp_140 = elmc_new_int(ELMC_PEBBLE_CMD_GET_WATCH_MODEL);
  ElmcValue *tmp_141 = elmc_new_int(27);
  ElmcValue *tmp_142 = elmc_int_zero();
  ElmcValue *tmp_143 = elmc_int_zero();
  ElmcValue *tmp_144 = elmc_int_zero();
  
  
  ElmcValue *tmp_145 = elmc_tuple2_ints(0, 0);

    ElmcValue *tmp_146 = elmc_tuple2_take(tmp_144, tmp_145);

    ElmcValue *tmp_147 = elmc_tuple2_take(tmp_143, tmp_146);

    ElmcValue *tmp_148 = elmc_tuple2_take(tmp_142, tmp_147);

    ElmcValue *tmp_149 = elmc_tuple2_take(tmp_141, tmp_148);

    ElmcValue *tmp_150 = elmc_tuple2_take(tmp_140, tmp_149);

  ElmcValue *tmp_151 = elmc_new_int(ELMC_PEBBLE_CMD_GET_WATCH_COLOR);
  ElmcValue *tmp_152 = elmc_new_int(28);
  ElmcValue *tmp_153 = elmc_int_zero();
  ElmcValue *tmp_154 = elmc_int_zero();
  ElmcValue *tmp_155 = elmc_int_zero();
  
  
  ElmcValue *tmp_156 = elmc_tuple2_ints(0, 0);

    ElmcValue *tmp_157 = elmc_tuple2_take(tmp_155, tmp_156);

    ElmcValue *tmp_158 = elmc_tuple2_take(tmp_154, tmp_157);

    ElmcValue *tmp_159 = elmc_tuple2_take(tmp_153, tmp_158);

    ElmcValue *tmp_160 = elmc_tuple2_take(tmp_152, tmp_159);

    ElmcValue *tmp_161 = elmc_tuple2_take(tmp_151, tmp_160);

  ElmcValue *tmp_162 = elmc_new_int(ELMC_PEBBLE_CMD_GET_FIRMWARE_VERSION);
  ElmcValue *tmp_163 = elmc_new_int(29);
  ElmcValue *tmp_164 = elmc_int_zero();
  ElmcValue *tmp_165 = elmc_int_zero();
  ElmcValue *tmp_166 = elmc_int_zero();
  
  
  ElmcValue *tmp_167 = elmc_tuple2_ints(0, 0);

    ElmcValue *tmp_168 = elmc_tuple2_take(tmp_166, tmp_167);

    ElmcValue *tmp_169 = elmc_tuple2_take(tmp_165, tmp_168);

    ElmcValue *tmp_170 = elmc_tuple2_take(tmp_164, tmp_169);

    ElmcValue *tmp_171 = elmc_tuple2_take(tmp_163, tmp_170);

    ElmcValue *tmp_172 = elmc_tuple2_take(tmp_162, tmp_171);

  ElmcValue *tmp_173 = elmc_new_int(ELMC_PEBBLE_CMD_GET_BATTERY_LEVEL);
  ElmcValue *tmp_174 = elmc_new_int(30);
  ElmcValue *tmp_175 = elmc_int_zero();
  ElmcValue *tmp_176 = elmc_int_zero();
  ElmcValue *tmp_177 = elmc_int_zero();
  
  
  ElmcValue *tmp_178 = elmc_tuple2_ints(0, 0);

    ElmcValue *tmp_179 = elmc_tuple2_take(tmp_177, tmp_178);

    ElmcValue *tmp_180 = elmc_tuple2_take(tmp_176, tmp_179);

    ElmcValue *tmp_181 = elmc_tuple2_take(tmp_175, tmp_180);

    ElmcValue *tmp_182 = elmc_tuple2_take(tmp_174, tmp_181);

    ElmcValue *tmp_183 = elmc_tuple2_take(tmp_173, tmp_182);

  ElmcValue *tmp_184 = elmc_new_int(ELMC_PEBBLE_CMD_GET_CONNECTION_STATUS);
  ElmcValue *tmp_185 = elmc_new_int(31);
  ElmcValue *tmp_186 = elmc_int_zero();
  ElmcValue *tmp_187 = elmc_int_zero();
  ElmcValue *tmp_188 = elmc_int_zero();
  
  
  ElmcValue *tmp_189 = elmc_tuple2_ints(0, 0);

    ElmcValue *tmp_190 = elmc_tuple2_take(tmp_188, tmp_189);

    ElmcValue *tmp_191 = elmc_tuple2_take(tmp_187, tmp_190);

    ElmcValue *tmp_192 = elmc_tuple2_take(tmp_186, tmp_191);

    ElmcValue *tmp_193 = elmc_tuple2_take(tmp_185, tmp_192);

    ElmcValue *tmp_194 = elmc_tuple2_take(tmp_184, tmp_193);

  ElmcValue *tmp_195 = elmc_new_int(ELMC_PEBBLE_CMD_HEALTH_VALUE);
  ElmcValue *tmp_196 = elmc_new_int(1);
  ElmcValue *tmp_197 = elmc_new_int(32);
  ElmcValue *tmp_198 = elmc_int_zero();
  ElmcValue *tmp_199 = elmc_int_zero();
  
  
  ElmcValue *tmp_200 = elmc_tuple2_ints(0, 0);

    ElmcValue *tmp_201 = elmc_tuple2_take(tmp_199, tmp_200);

    ElmcValue *tmp_202 = elmc_tuple2_take(tmp_198, tmp_201);

    ElmcValue *tmp_203 = elmc_tuple2_take(tmp_197, tmp_202);

    ElmcValue *tmp_204 = elmc_tuple2_take(tmp_196, tmp_203);

    ElmcValue *tmp_205 = elmc_tuple2_take(tmp_195, tmp_204);

  ElmcValue *tmp_206 = elmc_new_int(ELMC_PEBBLE_CMD_HEALTH_SUM_TODAY);
  ElmcValue *tmp_207 = elmc_new_int(1);
  ElmcValue *tmp_208 = elmc_new_int(33);
  ElmcValue *tmp_209 = elmc_int_zero();
  ElmcValue *tmp_210 = elmc_int_zero();
  
  
  ElmcValue *tmp_211 = elmc_tuple2_ints(0, 0);

    ElmcValue *tmp_212 = elmc_tuple2_take(tmp_210, tmp_211);

    ElmcValue *tmp_213 = elmc_tuple2_take(tmp_209, tmp_212);

    ElmcValue *tmp_214 = elmc_tuple2_take(tmp_208, tmp_213);

    ElmcValue *tmp_215 = elmc_tuple2_take(tmp_207, tmp_214);

    ElmcValue *tmp_216 = elmc_tuple2_take(tmp_206, tmp_215);

  ElmcValue *tmp_217 = elmc_new_int(ELMC_PEBBLE_CMD_HEALTH_SUM);
  ElmcValue *tmp_218 = elmc_new_int(3);
  ElmcValue *tmp_219 = elmc_int_zero();
  ElmcValue *tmp_220 = elmc_new_int(3600);
  ElmcValue *tmp_221 = elmc_new_int(34);
  
  
  ElmcValue *tmp_222 = elmc_tuple2_ints(0, 0);

    ElmcValue *tmp_223 = elmc_tuple2_take(tmp_221, tmp_222);

    ElmcValue *tmp_224 = elmc_tuple2_take(tmp_220, tmp_223);

    ElmcValue *tmp_225 = elmc_tuple2_take(tmp_219, tmp_224);

    ElmcValue *tmp_226 = elmc_tuple2_take(tmp_218, tmp_225);

    ElmcValue *tmp_227 = elmc_tuple2_take(tmp_217, tmp_226);

  ElmcValue *tmp_228 = elmc_new_int(ELMC_PEBBLE_CMD_HEALTH_ACCESSIBLE);
  ElmcValue *tmp_229 = elmc_new_int(2);
  ElmcValue *tmp_230 = elmc_int_zero();
  ElmcValue *tmp_231 = elmc_new_int(3600);
  ElmcValue *tmp_232 = elmc_new_int(35);
  
  
  ElmcValue *tmp_233 = elmc_tuple2_ints(0, 0);

    ElmcValue *tmp_234 = elmc_tuple2_take(tmp_232, tmp_233);

    ElmcValue *tmp_235 = elmc_tuple2_take(tmp_231, tmp_234);

    ElmcValue *tmp_236 = elmc_tuple2_take(tmp_230, tmp_235);

    ElmcValue *tmp_237 = elmc_tuple2_take(tmp_229, tmp_236);

    ElmcValue *tmp_238 = elmc_tuple2_take(tmp_228, tmp_237);

  

  
  ElmcValue *call_args_239[1] = {  };
  ElmcValue *tmp_239 = elmc_fn_Pebble_Light_interaction(call_args_239, 0);
  
  

  

  
  ElmcValue *call_args_240[1] = {  };
  ElmcValue *tmp_240 = elmc_fn_Pebble_Light_disable(call_args_240, 0);
  
  

  

  
  ElmcValue *call_args_241[1] = {  };
  ElmcValue *tmp_241 = elmc_fn_Pebble_Light_enable(call_args_241, 0);
  
  

  ElmcValue *tmp_242 = elmc_new_int(ELMC_PEBBLE_CMD_VIBES_CANCEL);
  ElmcValue *tmp_243 = elmc_new_int(ELMC_PEBBLE_CMD_VIBES_SHORT_PULSE);
  ElmcValue *tmp_244 = elmc_new_int(ELMC_PEBBLE_CMD_VIBES_LONG_PULSE);
  ElmcValue *tmp_245 = elmc_new_int(ELMC_PEBBLE_CMD_VIBES_DOUBLE_PULSE);
  ElmcValue *tmp_246 = elmc_new_int(ELMC_PEBBLE_CMD_VIBES_CUSTOM_PATTERN);
  
  ElmcValue *tmp_247 = elmc_new_int(100);
  ElmcValue *tmp_248 = elmc_new_int(50);
  ElmcValue *tmp_249 = elmc_new_int(100);
  ElmcValue *list_items_250[3] = { tmp_247, tmp_248, tmp_249 };
  ElmcValue *tmp_250 = elmc_list_from_values_take(list_items_250, 3);
  

  ElmcValue *tmp_251 = elmc_int_zero();
  ElmcValue *tmp_252 = elmc_int_zero();
  ElmcValue *tmp_253 = elmc_int_zero();
  
  
  ElmcValue *tmp_254 = elmc_tuple2_ints(0, 0);

    ElmcValue *tmp_255 = elmc_tuple2_take(tmp_253, tmp_254);

    ElmcValue *tmp_256 = elmc_tuple2_take(tmp_252, tmp_255);

    ElmcValue *tmp_257 = elmc_tuple2_take(tmp_251, tmp_256);

    ElmcValue *tmp_258 = elmc_tuple2_take(tmp_250, tmp_257);

    ElmcValue *tmp_259 = elmc_tuple2_take(tmp_246, tmp_258);

  ElmcValue *tmp_260 = elmc_new_int(ELMC_PEBBLE_CMD_DATA_LOG_BYTES);
  

  ElmcValue *tmp_261 = elmc_new_int(42);
  
  ElmcValue *call_args_262[1] = { tmp_261 };
  ElmcValue *tmp_262 = elmc_fn_Pebble_DataLog_tag(call_args_262, 1);
  
  elmc_release(tmp_261);

  
  ElmcValue *tmp_263 = elmc_new_int(1);
  ElmcValue *tmp_264 = elmc_new_int(2);
  ElmcValue *tmp_265 = elmc_new_int(3);
  ElmcValue *list_items_266[3] = { tmp_263, tmp_264, tmp_265 };
  ElmcValue *tmp_266 = elmc_list_from_values_take(list_items_266, 3);
  

  ElmcValue *tmp_267 = elmc_int_zero();
  ElmcValue *tmp_268 = elmc_int_zero();
  
  
  ElmcValue *tmp_269 = elmc_tuple2_ints(0, 0);

    ElmcValue *tmp_270 = elmc_tuple2_take(tmp_268, tmp_269);

    ElmcValue *tmp_271 = elmc_tuple2_take(tmp_267, tmp_270);

    ElmcValue *tmp_272 = elmc_tuple2_take(tmp_266, tmp_271);

    ElmcValue *tmp_273 = elmc_tuple2_take(tmp_262, tmp_272);

    ElmcValue *tmp_274 = elmc_tuple2_take(tmp_260, tmp_273);

  ElmcValue *tmp_275 = elmc_new_int(ELMC_PEBBLE_CMD_DATA_LOG_INT32);
  

  ElmcValue *tmp_276 = elmc_new_int(43);
  
  ElmcValue *call_args_277[1] = { tmp_276 };
  ElmcValue *tmp_277 = elmc_fn_Pebble_DataLog_tag(call_args_277, 1);
  
  elmc_release(tmp_276);

  ElmcValue *tmp_278 = elmc_new_int(9001);
  ElmcValue *tmp_279 = elmc_int_zero();
  ElmcValue *tmp_280 = elmc_int_zero();
  
  
  ElmcValue *tmp_281 = elmc_tuple2_ints(0, 0);

    ElmcValue *tmp_282 = elmc_tuple2_take(tmp_280, tmp_281);

    ElmcValue *tmp_283 = elmc_tuple2_take(tmp_279, tmp_282);

    ElmcValue *tmp_284 = elmc_tuple2_take(tmp_278, tmp_283);

    ElmcValue *tmp_285 = elmc_tuple2_take(tmp_277, tmp_284);

    ElmcValue *tmp_286 = elmc_tuple2_take(tmp_275, tmp_285);

  ElmcValue *tmp_287 = elmc_new_int(ELMC_PEBBLE_CMD_COMPASS_PEEK);
  ElmcValue *tmp_288 = elmc_new_int(39);
  ElmcValue *tmp_289 = elmc_int_zero();
  ElmcValue *tmp_290 = elmc_int_zero();
  ElmcValue *tmp_291 = elmc_int_zero();
  
  
  ElmcValue *tmp_292 = elmc_tuple2_ints(0, 0);

    ElmcValue *tmp_293 = elmc_tuple2_take(tmp_291, tmp_292);

    ElmcValue *tmp_294 = elmc_tuple2_take(tmp_290, tmp_293);

    ElmcValue *tmp_295 = elmc_tuple2_take(tmp_289, tmp_294);

    ElmcValue *tmp_296 = elmc_tuple2_take(tmp_288, tmp_295);

    ElmcValue *tmp_297 = elmc_tuple2_take(tmp_287, tmp_296);

  ElmcValue *tmp_298 = elmc_new_int(ELMC_PEBBLE_CMD_DICTATION_START);
  ElmcValue *tmp_299 = elmc_new_int(ELMC_PEBBLE_CMD_DICTATION_STOP);
  

  ElmcValue *tmp_300 = elmc_new_int(60);
  
  ElmcValue *call_args_301[1] = { tmp_300 };
  ElmcValue *tmp_301 = elmc_fn_Pebble_Wakeup_scheduleAfterSeconds(call_args_301, 1);
  
  elmc_release(tmp_300);

  

  ElmcValue *tmp_302 = elmc_new_int(1);
  
  ElmcValue *call_args_303[1] = { tmp_302 };
  ElmcValue *tmp_303 = elmc_fn_Pebble_Wakeup_cancel(call_args_303, 1);
  
  elmc_release(tmp_302);

  

  ElmcValue *tmp_304 = elmc_new_int(101);
  
  ElmcValue *call_args_305[1] = { tmp_304 };
  ElmcValue *tmp_305 = elmc_fn_Pebble_Log_infoCode(call_args_305, 1);
  
  elmc_release(tmp_304);

  

  ElmcValue *tmp_306 = elmc_new_int(202);
  
  ElmcValue *call_args_307[1] = { tmp_306 };
  ElmcValue *tmp_307 = elmc_fn_Pebble_Log_warnCode(call_args_307, 1);
  
  elmc_release(tmp_306);

  

  ElmcValue *tmp_308 = elmc_new_int(303);
  
  ElmcValue *call_args_309[1] = { tmp_308 };
  ElmcValue *tmp_309 = elmc_fn_Pebble_Log_errorCode(call_args_309, 1);
  
  elmc_release(tmp_308);

  ElmcValue *list_items_310[40] = { tmp_7, tmp_18, tmp_29, tmp_40, tmp_51, tmp_62, tmp_73, tmp_84, tmp_95, tmp_106, tmp_117, tmp_128, tmp_139, tmp_150, tmp_161, tmp_172, tmp_183, tmp_194, tmp_205, tmp_216, tmp_227, tmp_238, tmp_239, tmp_240, tmp_241, tmp_242, tmp_243, tmp_244, tmp_245, tmp_259, tmp_274, tmp_286, tmp_297, tmp_298, tmp_299, tmp_301, tmp_303, tmp_305, tmp_307, tmp_309 };
  ElmcValue *tmp_310 = elmc_list_from_values_take(list_items_310, 40);
  

    ElmcValue *tmp_311 = elmc_tuple2_take(tmp_6, tmp_310);


  
  
  return tmp_311;

}


ElmcValue *elmc_fn_Main_update(ElmcValue ** const args, const int argc) {
  /* Ownership policy: borrow_arg, borrow_result */
  (void)args;
  (void)argc;
ElmcValue *msg = (argc > 0) ? args[0] : NULL;
  ElmcValue *model = (argc > 1) ? args[1] : NULL;
  (void)msg;
  (void)model;
  
  ElmcValue *tmp_1 = elmc_int_zero();
  
  
  return tmp_1;

}


ElmcValue *elmc_fn_Main_subscriptions(ElmcValue ** const args, const int argc) {
  /* Ownership policy: borrow_arg, borrow_result */
  (void)args;
  (void)argc;
ElmcValue *_ = (argc > 0) ? args[0] : NULL;
  (void)_;
  
  ElmcValue *tmp_1 = elmc_new_int(2151672945);
  
  
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

  
  

  
  ElmcValue *tmp_1 = elmc_new_int(2);
  
  ElmcValue *tmp_2 = elmc_record_get_index(model, 0 /* latestTime */);
  

  ElmcValue *tmp_3 = elmc_string_left(tmp_1, tmp_2);
  elmc_release(tmp_1);
  elmc_release(tmp_2);
  

  ElmcValue *tmp_4 = elmc_string_to_int(tmp_3);
  elmc_release(tmp_3);
  

  const elmc_int_t native_maybe_default_5 = elmc_maybe_with_default_int(0, tmp_4);
  elmc_release(tmp_4);
  // inlined Main.parseHourFromTimeString

  const elmc_int_t native_let_parsedInt_6 = native_maybe_default_5;
  
      

  
  ElmcValue *tmp_6 = elmc_int_zero();
  
  ElmcValue *tmp_7 = elmc_new_string("3.14");
  ElmcValue *tmp_8 = elmc_string_to_float(tmp_7);
  elmc_release(tmp_7);
  

  ElmcValue *tmp_9 = elmc_maybe_with_default(tmp_6, tmp_8);
  elmc_release(tmp_6);
  elmc_release(tmp_8);
  

  ElmcValue *tmp_10 = elmc_basics_floor(tmp_9);
  elmc_release(tmp_9);
  

      
  ElmcValue *tmp_11 = elmc_new_int(ELMC_UI_NODE_WINDOW_STACK);
  
  ElmcValue *tmp_12 = elmc_new_int(ELMC_UI_NODE_WINDOW);
  ElmcValue *tmp_13 = elmc_new_int(1);
  
  ElmcValue *tmp_14 = elmc_new_int(ELMC_UI_NODE_CANVAS_LAYER);
  ElmcValue *tmp_15 = elmc_new_int(1);
  
  ElmcValue *tmp_16 = elmc_new_int(ELMC_RENDER_OP_CLEAR);
  ElmcValue *tmp_17 = elmc_new_int(ELMC_COLOR_WHITE);
  ElmcValue *tmp_18 = elmc_int_zero();
  ElmcValue *tmp_19 = elmc_int_zero();
  ElmcValue *tmp_20 = elmc_int_zero();
  
  
  ElmcValue *tmp_21 = elmc_tuple2_ints(0, 0);

    ElmcValue *tmp_22 = elmc_tuple2_take(tmp_20, tmp_21);

    ElmcValue *tmp_23 = elmc_tuple2_take(tmp_19, tmp_22);

    ElmcValue *tmp_24 = elmc_tuple2_take(tmp_18, tmp_23);

    ElmcValue *tmp_25 = elmc_tuple2_take(tmp_17, tmp_24);

    ElmcValue *tmp_26 = elmc_tuple2_take(tmp_16, tmp_25);

  ElmcValue *tmp_27 = elmc_new_int(ELMC_PEBBLE_CMD_STORAGE_READ_STRING);
  ElmcValue *tmp_28 = elmc_new_int(1);
  ElmcValue *tmp_29 = elmc_int_zero();
  ElmcValue *tmp_30 = elmc_new_int(24);
  ElmcValue *tmp_31 = elmc_new_int(native_let_parsedInt_6);
  
  
  ElmcValue *tmp_32 = elmc_tuple2_ints(0, 0);

    ElmcValue *tmp_33 = elmc_tuple2_take(tmp_31, tmp_32);

    ElmcValue *tmp_34 = elmc_tuple2_take(tmp_30, tmp_33);

    ElmcValue *tmp_35 = elmc_tuple2_take(tmp_29, tmp_34);

    ElmcValue *tmp_36 = elmc_tuple2_take(tmp_28, tmp_35);

    ElmcValue *tmp_37 = elmc_tuple2_take(tmp_27, tmp_36);

  ElmcValue *tmp_38 = elmc_new_int(ELMC_PEBBLE_CMD_STORAGE_READ_STRING);
  ElmcValue *tmp_39 = elmc_new_int(1);
  ElmcValue *tmp_40 = elmc_int_zero();
  ElmcValue *tmp_41 = elmc_new_int(48);
  ElmcValue *tmp_42 = tmp_10 ? elmc_retain(tmp_10) : elmc_int_zero();
  
  
  ElmcValue *tmp_43 = elmc_tuple2_ints(0, 0);

    ElmcValue *tmp_44 = elmc_tuple2_take(tmp_42, tmp_43);

    ElmcValue *tmp_45 = elmc_tuple2_take(tmp_41, tmp_44);

    ElmcValue *tmp_46 = elmc_tuple2_take(tmp_40, tmp_45);

    ElmcValue *tmp_47 = elmc_tuple2_take(tmp_39, tmp_46);

    ElmcValue *tmp_48 = elmc_tuple2_take(tmp_38, tmp_47);

  ElmcValue *tmp_49 = elmc_new_int(ELMC_PEBBLE_CMD_STORAGE_READ_STRING);
  ElmcValue *tmp_50 = elmc_new_int(1);
  ElmcValue *tmp_51 = elmc_int_zero();
  ElmcValue *tmp_52 = elmc_new_int(72);
  
  ElmcValue *tmp_53 = elmc_record_get_index(model, 1 /* ticks */);
  

  
  
  ElmcValue *tmp_54 = elmc_tuple2_ints(0, 0);

    ElmcValue *tmp_55 = elmc_tuple2_take(tmp_53, tmp_54);

    ElmcValue *tmp_56 = elmc_tuple2_take(tmp_52, tmp_55);

    ElmcValue *tmp_57 = elmc_tuple2_take(tmp_51, tmp_56);

    ElmcValue *tmp_58 = elmc_tuple2_take(tmp_50, tmp_57);

    ElmcValue *tmp_59 = elmc_tuple2_take(tmp_49, tmp_58);

  ElmcValue *list_items_60[4] = { tmp_26, tmp_37, tmp_48, tmp_59 };
  ElmcValue *tmp_60 = elmc_list_from_values_take(list_items_60, 4);
  

    ElmcValue *tmp_61 = elmc_tuple2_take(tmp_15, tmp_60);

    ElmcValue *tmp_62 = elmc_tuple2_take(tmp_14, tmp_61);

  ElmcValue *list_items_63[1] = { tmp_62 };
  ElmcValue *tmp_63 = elmc_list_from_values_take(list_items_63, 1);
  

    ElmcValue *tmp_64 = elmc_tuple2_take(tmp_13, tmp_63);

    ElmcValue *tmp_65 = elmc_tuple2_take(tmp_12, tmp_64);

  ElmcValue *list_items_66[1] = { tmp_65 };
  ElmcValue *tmp_66 = elmc_list_from_values_take(list_items_66, 1);
  

    ElmcValue *tmp_67 = elmc_tuple2_take(tmp_11, tmp_66);

  elmc_release(tmp_10);


  
  // #region agent log
if (!tmp_67) {
  elmc_agent_generated_probe(0xED998113);
} else if (tmp_67->tag == ELMC_TAG_TUPLE2) {
  elmc_agent_generated_probe(0xED998111);
} else if (tmp_67->tag == ELMC_TAG_LIST) {
  elmc_agent_generated_probe(0xED998112);
} else {
  elmc_agent_generated_probe(0xED998110);
}

// #endregion

  return tmp_67;

}


ElmcValue *elmc_fn_Main_main(ElmcValue ** const args, const int argc) {
  /* Ownership policy: borrow_arg, borrow_result */
  (void)args;
  (void)argc;

  
  
  ElmcValue *tmp_1 = elmc_int_zero();
  
  
  return tmp_1;

}


ElmcValue *elmc_fn_Pebble_DataLog_tag(ElmcValue ** const args, const int argc) {
  /* Ownership policy: borrow_arg, borrow_result */
  (void)args;
  (void)argc;

  
  
  ElmcValue *tmp_1 = elmc_new_int(1);
  
  
  return tmp_1;

}


ElmcValue *elmc_fn_Pebble_Light_interaction(ElmcValue ** const args, const int argc) {
  /* Ownership policy: borrow_arg, borrow_result */
  (void)args;
  (void)argc;

  
  
  
  ElmcValue *tmp_1 = elmc_int_zero();
  ElmcValue *tmp_2 = elmc_cmd_backlight_from_maybe(tmp_1);
  elmc_release(tmp_1);
  

  
  
  return tmp_2;

}


ElmcValue *elmc_fn_Pebble_Light_disable(ElmcValue ** const args, const int argc) {
  /* Ownership policy: borrow_arg, borrow_result */
  (void)args;
  (void)argc;

  
  
  
  ElmcValue *tmp_1 = elmc_new_int(1);
  ElmcValue *tmp_2 = elmc_int_zero();
    ElmcValue *tmp_3 = elmc_tuple2_take(tmp_1, tmp_2);

  ElmcValue *tmp_4 = elmc_cmd_backlight_from_maybe(tmp_3);
  elmc_release(tmp_3);
  

  
  
  return tmp_4;

}


ElmcValue *elmc_fn_Pebble_Light_enable(ElmcValue ** const args, const int argc) {
  /* Ownership policy: borrow_arg, borrow_result */
  (void)args;
  (void)argc;

  
  
  
  ElmcValue *tmp_1 = elmc_new_int(1);
  ElmcValue *tmp_2 = elmc_new_int(1);
    ElmcValue *tmp_3 = elmc_tuple2_take(tmp_1, tmp_2);

  ElmcValue *tmp_4 = elmc_cmd_backlight_from_maybe(tmp_3);
  elmc_release(tmp_3);
  

  
  
  return tmp_4;

}


ElmcValue *elmc_fn_Pebble_Log_infoCode(ElmcValue ** const args, const int argc) {
  /* Ownership policy: borrow_arg, borrow_result */
  (void)args;
  (void)argc;

  
  
  ElmcValue *tmp_1 = elmc_int_zero();
  
  
  return tmp_1;

}


ElmcValue *elmc_fn_Pebble_Log_warnCode(ElmcValue ** const args, const int argc) {
  /* Ownership policy: borrow_arg, borrow_result */
  (void)args;
  (void)argc;

  
  
  ElmcValue *tmp_1 = elmc_int_zero();
  
  
  return tmp_1;

}


ElmcValue *elmc_fn_Pebble_Log_errorCode(ElmcValue ** const args, const int argc) {
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


ElmcValue *elmc_fn_Pebble_Wakeup_scheduleAfterSeconds(ElmcValue ** const args, const int argc) {
  /* Ownership policy: borrow_arg, borrow_result */
  (void)args;
  (void)argc;

  
  
  ElmcValue *tmp_1 = elmc_int_zero();
  
  
  return tmp_1;

}


ElmcValue *elmc_fn_Pebble_Wakeup_cancel(ElmcValue ** const args, const int argc) {
  /* Ownership policy: borrow_arg, borrow_result */
  (void)args;
  (void)argc;

  
  
  ElmcValue *tmp_1 = elmc_int_zero();
  
  
  return tmp_1;

}


static int elmc_fn_Main_view_commands_append(ElmcValue ** const args, const int argc, ElmcGeneratedPebbleDrawCmd * const out_cmds, const int max_cmds, const int skip, int * const count, int * const emitted);

static int elmc_fn_Main_view_commands_append(ElmcValue ** const args, const int argc, ElmcGeneratedPebbleDrawCmd * const out_cmds, const int max_cmds, const int skip, int * const count, int * const emitted) {
  (void)args;
  (void)argc;
  ElmcValue *model = (argc > 0) ? args[0] : NULL;
  (void)model;
  if (!out_cmds || !count || !emitted || max_cmds <= 0) return -1;
  int direct_stop = 0;
  if (!direct_stop) {


  
    ElmcValue *tmp_1 = elmc_new_int(2);
  
    ElmcValue *tmp_2 = elmc_record_get_index(model, 0 /* latestTime */);
  

    ElmcValue *tmp_3 = elmc_string_left(tmp_1, tmp_2);
    elmc_release(tmp_1);
    elmc_release(tmp_2);
  

    ElmcValue *tmp_4 = elmc_string_to_int(tmp_3);
    elmc_release(tmp_3);
  

    const elmc_int_t native_maybe_default_5 = elmc_maybe_with_default_int(0, tmp_4);
    elmc_release(tmp_4);
    // inlined Main.parseHourFromTimeString
    const elmc_int_t direct_hoisted_int_6 = native_maybe_default_5;

  const elmc_int_t direct_native_let_parsedInt_7 = direct_hoisted_int_6;
  if (!direct_stop) {

  
      ElmcValue *tmp_8 = elmc_int_zero();
  
      ElmcValue *tmp_9 = elmc_new_string("3.14");
      ElmcValue *tmp_10 = elmc_string_to_float(tmp_9);
      elmc_release(tmp_9);
  

      ElmcValue *tmp_11 = elmc_maybe_with_default(tmp_8, tmp_10);
      elmc_release(tmp_8);
      elmc_release(tmp_10);
  

      ElmcValue *tmp_12 = elmc_basics_floor(tmp_11);
      elmc_release(tmp_11);
  

      const elmc_int_t native_i_13 = elmc_as_int(tmp_12);
      elmc_release(tmp_12);

    const elmc_int_t direct_native_let_parsedFloatAsInt_14 = native_i_13;



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

      elmc_generated_draw_init(&out_cmds[*count], ELMC_RENDER_OP_TEXT_INT_WITH_FONT);
        out_cmds[*count].p0 = 1;
      out_cmds[*count].p1 = 0;
      out_cmds[*count].p2 = 24;
      out_cmds[*count].p3 = direct_native_let_parsedInt_7;
        *count += 1;
      }
     if (!direct_stop) {
       *emitted += 1;
       if (*count >= max_cmds) direct_stop = 1;
     }

     if (!direct_stop && *emitted >= skip && *count < max_cmds) {

      elmc_generated_draw_init(&out_cmds[*count], ELMC_RENDER_OP_TEXT_INT_WITH_FONT);
        out_cmds[*count].p0 = 1;
      out_cmds[*count].p1 = 0;
      out_cmds[*count].p2 = 48;
      out_cmds[*count].p3 = direct_native_let_parsedFloatAsInt_14;
        *count += 1;
      }
     if (!direct_stop) {
       *emitted += 1;
       if (*count >= max_cmds) direct_stop = 1;
     }

     if (!direct_stop && *emitted >= skip && *count < max_cmds) {

      elmc_generated_draw_init(&out_cmds[*count], ELMC_RENDER_OP_TEXT_INT_WITH_FONT);
        out_cmds[*count].p0 = 1;
      out_cmds[*count].p1 = 0;
      out_cmds[*count].p2 = 72;
      out_cmds[*count].p3 = ELMC_RECORD_GET_INDEX_INT(model, 1 /* ticks */);
        *count += 1;
      }
     if (!direct_stop) {
       *emitted += 1;
       if (*count >= max_cmds) direct_stop = 1;
     }

  }

}

  return 0;
}

int elmc_fn_Main_view_commands(ElmcValue ** const args, const int argc, void * const out_cmds, const int max_cmds) {
  return elmc_direct_commands_from(&elmc_fn_Main_view_commands_append, args, argc, out_cmds, max_cmds, 0, NULL);
}

int elmc_fn_Main_view_commands_from(ElmcValue ** const args, const int argc, void * const out_cmds, const int max_cmds, const int skip, int *out_emitted) {
  return elmc_direct_commands_from(&elmc_fn_Main_view_commands_append, args, argc, out_cmds, max_cmds, skip, out_emitted);
}

