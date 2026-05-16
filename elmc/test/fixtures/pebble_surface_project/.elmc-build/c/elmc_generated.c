#include "elmc_generated.h"
#include <stdio.h>

#if defined(__GNUC__)
#pragma GCC diagnostic ignored "-Wunused-function"
#endif

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


static ElmcValue *elmc_fn_Elm_Kernel_PebbleWatch_healthValue_native(const elmc_int_t metric, ElmcValue * const toMsg);
static ElmcValue *elmc_fn_Elm_Kernel_PebbleWatch_healthSumToday_native(const elmc_int_t metric, ElmcValue * const toMsg);
static ElmcValue *elmc_fn_Elm_Kernel_PebbleWatch_healthSum_native(const elmc_int_t metric, const elmc_int_t startSeconds, const elmc_int_t endSeconds, ElmcValue * const toMsg);
static ElmcValue *elmc_fn_Elm_Kernel_PebbleWatch_healthAccessible_native(const elmc_int_t metric, const elmc_int_t startSeconds, const elmc_int_t endSeconds, ElmcValue * const toMsg);

static ElmcValue *elmc_partial_ref_1(ElmcValue **args, int argc, ElmcValue **captures, int capture_count) {
  (void)args;
  (void)argc;
  (void)captures;
  (void)capture_count;
  ElmcValue *call_args[2] = {0};
  call_args[0] = (capture_count > 0) ? captures[0] : NULL;
  call_args[1] = (argc > 0) ? args[0] : NULL;
  return elmc_fn_Elm_Kernel_PebbleWatch_healthValue(call_args, 2);
}

static ElmcValue *elmc_partial_ref_2(ElmcValue **args, int argc, ElmcValue **captures, int capture_count) {
  (void)args;
  (void)argc;
  (void)captures;
  (void)capture_count;
  ElmcValue *call_args[2] = {0};
  call_args[0] = (capture_count > 0) ? captures[0] : NULL;
  call_args[1] = (argc > 0) ? args[0] : NULL;
  return elmc_fn_Elm_Kernel_PebbleWatch_healthSumToday(call_args, 2);
}

static ElmcValue *elmc_partial_ref_3(ElmcValue **args, int argc, ElmcValue **captures, int capture_count) {
  (void)args;
  (void)argc;
  (void)captures;
  (void)capture_count;
  ElmcValue *call_args[4] = {0};
  call_args[0] = (capture_count > 0) ? captures[0] : NULL;
  call_args[1] = (capture_count > 1) ? captures[1] : NULL;
  call_args[2] = (capture_count > 2) ? captures[2] : NULL;
  call_args[3] = (argc > 0) ? args[0] : NULL;
  return elmc_fn_Elm_Kernel_PebbleWatch_healthSum(call_args, 4);
}

static ElmcValue *elmc_partial_ref_4(ElmcValue **args, int argc, ElmcValue **captures, int capture_count) {
  (void)args;
  (void)argc;
  (void)captures;
  (void)capture_count;
  ElmcValue *call_args[4] = {0};
  call_args[0] = (capture_count > 0) ? captures[0] : NULL;
  call_args[1] = (capture_count > 1) ? captures[1] : NULL;
  call_args[2] = (capture_count > 2) ? captures[2] : NULL;
  call_args[3] = (argc > 0) ? args[0] : NULL;
  return elmc_fn_Elm_Kernel_PebbleWatch_healthAccessible(call_args, 4);
}


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

ElmcValue *elmc_fn_Main_init(ElmcValue ** const args, const int argc) {
  /* Ownership policy: borrow_arg, borrow_result */
  (void)args;
  (void)argc;
ElmcValue *launchContext = (argc > 0) ? args[0] : NULL;
  (void)launchContext;
  
  
  

  
  ElmcValue *tmp_1 = elmc_record_get_index(launchContext, 0 /* reason */);
  

  
  ElmcValue *call_args_2[1] = { tmp_1 };
  ElmcValue *tmp_2 = elmc_fn_Pebble_Platform_launchReasonToInt(call_args_2, 1);
  
  elmc_release(tmp_1);

  const elmc_int_t native_i_3 = elmc_as_int(tmp_2);
  elmc_release(tmp_2);

  const elmc_int_t native_let_launchReasonValue_4 = native_i_3;
  
  
  ElmcValue *tmp_5 = elmc_new_string("00:00");
  ElmcValue *tmp_6 = elmc_new_int(native_let_launchReasonValue_4);
  const char *rec_names_7[2] = { "latestTime", "ticks" };
  ElmcValue *rec_values_7[2] = { tmp_5, tmp_6 };
    ElmcValue *tmp_7 = elmc_record_new_take(2, rec_names_7, rec_values_7);

  
  ElmcValue *tmp_8 = elmc_int_zero();
  ElmcValue *tmp_9 = elmc_new_int(1);
  ElmcValue *tmp_10 = elmc_new_int(1000);
  ElmcValue *tmp_11 = elmc_int_zero();
  ElmcValue *tmp_12 = elmc_int_zero();
  ElmcValue *tmp_13 = elmc_int_zero();
  
  
  ElmcValue *tmp_14 = elmc_tuple2_ints(0, 0);

    ElmcValue *tmp_15 = elmc_tuple2_take(tmp_13, tmp_14);

    ElmcValue *tmp_16 = elmc_tuple2_take(tmp_12, tmp_15);

    ElmcValue *tmp_17 = elmc_tuple2_take(tmp_11, tmp_16);

    ElmcValue *tmp_18 = elmc_tuple2_take(tmp_10, tmp_17);

    ElmcValue *tmp_19 = elmc_tuple2_take(tmp_9, tmp_18);

  ElmcValue *tmp_20 = elmc_new_int(23);
  ElmcValue *tmp_21 = elmc_new_int(23);
  ElmcValue *tmp_22 = elmc_new_int(7);
  ElmcValue *tmp_23 = elmc_new_int(8);
  ElmcValue *tmp_24 = elmc_new_int(9);
  ElmcValue *tmp_25 = elmc_new_int(10);
  ElmcValue *tmp_26 = elmc_new_int(2);
  ElmcValue *tmp_27 = elmc_new_int(7);
  ElmcValue *tmp_28 = elmc_new_int(42);
  ElmcValue *tmp_29 = elmc_int_zero();
  ElmcValue *tmp_30 = elmc_int_zero();
  
  
  ElmcValue *tmp_31 = elmc_tuple2_ints(0, 0);

    ElmcValue *tmp_32 = elmc_tuple2_take(tmp_30, tmp_31);

    ElmcValue *tmp_33 = elmc_tuple2_take(tmp_29, tmp_32);

    ElmcValue *tmp_34 = elmc_tuple2_take(tmp_28, tmp_33);

    ElmcValue *tmp_35 = elmc_tuple2_take(tmp_27, tmp_34);

    ElmcValue *tmp_36 = elmc_tuple2_take(tmp_26, tmp_35);

  ElmcValue *tmp_37 = elmc_new_int(3);
  ElmcValue *tmp_38 = elmc_new_int(7);
  ElmcValue *tmp_39 = elmc_new_int(18);
  ElmcValue *tmp_40 = elmc_int_zero();
  ElmcValue *tmp_41 = elmc_int_zero();
  
  
  ElmcValue *tmp_42 = elmc_tuple2_ints(0, 0);

    ElmcValue *tmp_43 = elmc_tuple2_take(tmp_41, tmp_42);

    ElmcValue *tmp_44 = elmc_tuple2_take(tmp_40, tmp_43);

    ElmcValue *tmp_45 = elmc_tuple2_take(tmp_39, tmp_44);

    ElmcValue *tmp_46 = elmc_tuple2_take(tmp_38, tmp_45);

    ElmcValue *tmp_47 = elmc_tuple2_take(tmp_37, tmp_46);

  ElmcValue *tmp_48 = elmc_new_int(26);
  ElmcValue *tmp_49 = elmc_new_int(8);
  ElmcValue *tmp_50 = elmc_new_string("saved");
  ElmcValue *tmp_51 = elmc_int_zero();
  ElmcValue *tmp_52 = elmc_int_zero();
  
  
  ElmcValue *tmp_53 = elmc_tuple2_ints(0, 0);

    ElmcValue *tmp_54 = elmc_tuple2_take(tmp_52, tmp_53);

    ElmcValue *tmp_55 = elmc_tuple2_take(tmp_51, tmp_54);

    ElmcValue *tmp_56 = elmc_tuple2_take(tmp_50, tmp_55);

    ElmcValue *tmp_57 = elmc_tuple2_take(tmp_49, tmp_56);

    ElmcValue *tmp_58 = elmc_tuple2_take(tmp_48, tmp_57);

  ElmcValue *tmp_59 = elmc_new_int(27);
  ElmcValue *tmp_60 = elmc_new_int(8);
  ElmcValue *tmp_61 = elmc_new_int(19);
  ElmcValue *tmp_62 = elmc_int_zero();
  ElmcValue *tmp_63 = elmc_int_zero();
  
  
  ElmcValue *tmp_64 = elmc_tuple2_ints(0, 0);

    ElmcValue *tmp_65 = elmc_tuple2_take(tmp_63, tmp_64);

    ElmcValue *tmp_66 = elmc_tuple2_take(tmp_62, tmp_65);

    ElmcValue *tmp_67 = elmc_tuple2_take(tmp_61, tmp_66);

    ElmcValue *tmp_68 = elmc_tuple2_take(tmp_60, tmp_67);

    ElmcValue *tmp_69 = elmc_tuple2_take(tmp_59, tmp_68);

  ElmcValue *tmp_70 = elmc_new_int(4);
  ElmcValue *tmp_71 = elmc_new_int(7);
  ElmcValue *tmp_72 = elmc_int_zero();
  ElmcValue *tmp_73 = elmc_int_zero();
  ElmcValue *tmp_74 = elmc_int_zero();
  
  
  ElmcValue *tmp_75 = elmc_tuple2_ints(0, 0);

    ElmcValue *tmp_76 = elmc_tuple2_take(tmp_74, tmp_75);

    ElmcValue *tmp_77 = elmc_tuple2_take(tmp_73, tmp_76);

    ElmcValue *tmp_78 = elmc_tuple2_take(tmp_72, tmp_77);

    ElmcValue *tmp_79 = elmc_tuple2_take(tmp_71, tmp_78);

    ElmcValue *tmp_80 = elmc_tuple2_take(tmp_70, tmp_79);

  ElmcValue *tmp_81 = elmc_new_int(11);
  ElmcValue *tmp_82 = elmc_new_int(17);
  ElmcValue *tmp_83 = elmc_new_int(12);
  ElmcValue *tmp_84 = elmc_new_int(24);
  ElmcValue *tmp_85 = elmc_new_int(25);
  

  ElmcValue *tmp_86 = elmc_new_int(1);
  ElmcValue *tmp_87 = elmc_new_int(29);
  
  ElmcValue *call_args_88[1] = { tmp_86 };
  ElmcValue *head_88 = elmc_fn_Pebble_Health_value(call_args_88, 1);
  ElmcValue *extra_args_88[1] = { tmp_87 };
  ElmcValue *tmp_88 = elmc_apply_extra(head_88, extra_args_88, 1);
  
  elmc_release(head_88);
  elmc_release(tmp_86);
  elmc_release(tmp_87);

  

  ElmcValue *tmp_89 = elmc_new_int(1);
  ElmcValue *tmp_90 = elmc_new_int(30);
  
  ElmcValue *call_args_91[1] = { tmp_89 };
  ElmcValue *head_91 = elmc_fn_Pebble_Health_sumToday(call_args_91, 1);
  ElmcValue *extra_args_91[1] = { tmp_90 };
  ElmcValue *tmp_91 = elmc_apply_extra(head_91, extra_args_91, 1);
  
  elmc_release(head_91);
  elmc_release(tmp_89);
  elmc_release(tmp_90);

  

  ElmcValue *tmp_92 = elmc_new_int(3);
  ElmcValue *tmp_93 = elmc_int_zero();
  ElmcValue *tmp_94 = elmc_new_int(3600);
  ElmcValue *tmp_95 = elmc_new_int(31);
  
  ElmcValue *call_args_96[3] = { tmp_92, tmp_93, tmp_94 };
  ElmcValue *head_96 = elmc_fn_Pebble_Health_sum(call_args_96, 3);
  ElmcValue *extra_args_96[1] = { tmp_95 };
  ElmcValue *tmp_96 = elmc_apply_extra(head_96, extra_args_96, 1);
  
  elmc_release(head_96);
  elmc_release(tmp_92);
  elmc_release(tmp_93);
  elmc_release(tmp_94);
  elmc_release(tmp_95);

  

  ElmcValue *tmp_97 = elmc_new_int(2);
  ElmcValue *tmp_98 = elmc_int_zero();
  ElmcValue *tmp_99 = elmc_new_int(3600);
  ElmcValue *tmp_100 = elmc_new_int(32);
  
  ElmcValue *call_args_101[3] = { tmp_97, tmp_98, tmp_99 };
  ElmcValue *head_101 = elmc_fn_Pebble_Health_accessible(call_args_101, 3);
  ElmcValue *extra_args_101[1] = { tmp_100 };
  ElmcValue *tmp_101 = elmc_apply_extra(head_101, extra_args_101, 1);
  
  elmc_release(head_101);
  elmc_release(tmp_97);
  elmc_release(tmp_98);
  elmc_release(tmp_99);
  elmc_release(tmp_100);

  

  
  ElmcValue *call_args_102[1] = {  };
  ElmcValue *tmp_102 = elmc_fn_Pebble_Light_interaction(call_args_102, 0);
  
  

  

  
  ElmcValue *call_args_103[1] = {  };
  ElmcValue *tmp_103 = elmc_fn_Pebble_Light_disable(call_args_103, 0);
  
  

  

  
  ElmcValue *call_args_104[1] = {  };
  ElmcValue *tmp_104 = elmc_fn_Pebble_Light_enable(call_args_104, 0);
  
  

  ElmcValue *tmp_105 = elmc_new_int(13);
  ElmcValue *tmp_106 = elmc_new_int(14);
  ElmcValue *tmp_107 = elmc_new_int(15);
  ElmcValue *tmp_108 = elmc_new_int(16);
  

  ElmcValue *tmp_109 = elmc_new_int(60);
  
  ElmcValue *call_args_110[1] = { tmp_109 };
  ElmcValue *tmp_110 = elmc_fn_Pebble_Wakeup_scheduleAfterSeconds(call_args_110, 1);
  
  elmc_release(tmp_109);

  

  ElmcValue *tmp_111 = elmc_new_int(1);
  
  ElmcValue *call_args_112[1] = { tmp_111 };
  ElmcValue *tmp_112 = elmc_fn_Pebble_Wakeup_cancel(call_args_112, 1);
  
  elmc_release(tmp_111);

  

  ElmcValue *tmp_113 = elmc_new_int(101);
  
  ElmcValue *call_args_114[1] = { tmp_113 };
  ElmcValue *tmp_114 = elmc_fn_Pebble_Log_infoCode(call_args_114, 1);
  
  elmc_release(tmp_113);

  

  ElmcValue *tmp_115 = elmc_new_int(202);
  
  ElmcValue *call_args_116[1] = { tmp_115 };
  ElmcValue *tmp_116 = elmc_fn_Pebble_Log_warnCode(call_args_116, 1);
  
  elmc_release(tmp_115);

  

  ElmcValue *tmp_117 = elmc_new_int(303);
  
  ElmcValue *call_args_118[1] = { tmp_117 };
  ElmcValue *tmp_118 = elmc_fn_Pebble_Log_errorCode(call_args_118, 1);
  
  elmc_release(tmp_117);

  ElmcValue *list_items_119[34] = { tmp_8, tmp_19, tmp_20, tmp_21, tmp_22, tmp_23, tmp_24, tmp_25, tmp_36, tmp_47, tmp_58, tmp_69, tmp_80, tmp_81, tmp_82, tmp_83, tmp_84, tmp_85, tmp_88, tmp_91, tmp_96, tmp_101, tmp_102, tmp_103, tmp_104, tmp_105, tmp_106, tmp_107, tmp_108, tmp_110, tmp_112, tmp_114, tmp_116, tmp_118 };
  ElmcValue *tmp_119 = elmc_list_from_values_take(list_items_119, 34);
  

    ElmcValue *tmp_120 = elmc_tuple2_take(tmp_7, tmp_119);


  
  
  return tmp_120;

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
  
  ElmcValue *tmp_1 = elmc_new_int(2149706865);
  
  
  return tmp_1;

}

ElmcValue *elmc_fn_Main_main(ElmcValue ** const args, const int argc) {
  /* Ownership policy: borrow_arg, borrow_result */
  (void)args;
  (void)argc;

  
  
  ElmcValue *tmp_1 = elmc_int_zero();
  
  
  return tmp_1;

}

ElmcValue *elmc_fn_Elm_Kernel_PebbleWatch_healthValue(ElmcValue ** const args, const int argc) {
  /* Ownership policy: borrow_arg, borrow_result */
  (void)args;
  (void)argc;
  elmc_int_t metric = (argc > 0 && args[0]) ? elmc_as_int(args[0]) : 0;
  ElmcValue *toMsg = (argc > 1) ? args[1] : NULL;
  return elmc_fn_Elm_Kernel_PebbleWatch_healthValue_native(metric, toMsg);
}

static ElmcValue *elmc_fn_Elm_Kernel_PebbleWatch_healthValue_native(const elmc_int_t metric, ElmcValue * const toMsg) {
  (void)metric;
  (void)toMsg;
  
      
ElmcValue *tmp_1 = elmc_new_int(metric);
  ElmcValue *tmp_2 = toMsg ? elmc_retain(toMsg) : elmc_int_zero();
    ElmcValue *tmp_3 = elmc_tuple2_take(tmp_1, tmp_2);

      
  ElmcValue *tmp_4 = elmc_int_zero();
  elmc_release(tmp_3);

  
  return tmp_4;
}

ElmcValue *elmc_fn_Elm_Kernel_PebbleWatch_healthSumToday(ElmcValue ** const args, const int argc) {
  /* Ownership policy: borrow_arg, borrow_result */
  (void)args;
  (void)argc;
  elmc_int_t metric = (argc > 0 && args[0]) ? elmc_as_int(args[0]) : 0;
  ElmcValue *toMsg = (argc > 1) ? args[1] : NULL;
  return elmc_fn_Elm_Kernel_PebbleWatch_healthSumToday_native(metric, toMsg);
}

static ElmcValue *elmc_fn_Elm_Kernel_PebbleWatch_healthSumToday_native(const elmc_int_t metric, ElmcValue * const toMsg) {
  (void)metric;
  (void)toMsg;
  
      
ElmcValue *tmp_1 = elmc_new_int(metric);
  ElmcValue *tmp_2 = toMsg ? elmc_retain(toMsg) : elmc_int_zero();
    ElmcValue *tmp_3 = elmc_tuple2_take(tmp_1, tmp_2);

      
  ElmcValue *tmp_4 = elmc_int_zero();
  elmc_release(tmp_3);

  
  return tmp_4;
}

ElmcValue *elmc_fn_Elm_Kernel_PebbleWatch_healthSum(ElmcValue ** const args, const int argc) {
  /* Ownership policy: borrow_arg, borrow_result */
  (void)args;
  (void)argc;
  elmc_int_t metric = (argc > 0 && args[0]) ? elmc_as_int(args[0]) : 0;
  elmc_int_t startSeconds = (argc > 1 && args[1]) ? elmc_as_int(args[1]) : 0;
  elmc_int_t endSeconds = (argc > 2 && args[2]) ? elmc_as_int(args[2]) : 0;
  ElmcValue *toMsg = (argc > 3) ? args[3] : NULL;
  return elmc_fn_Elm_Kernel_PebbleWatch_healthSum_native(metric, startSeconds, endSeconds, toMsg);
}

static ElmcValue *elmc_fn_Elm_Kernel_PebbleWatch_healthSum_native(const elmc_int_t metric, const elmc_int_t startSeconds, const elmc_int_t endSeconds, ElmcValue * const toMsg) {
  (void)metric;
  (void)startSeconds;
  (void)endSeconds;
  (void)toMsg;
  
  ElmcValue *tmp_1 = elmc_int_zero();
  
  return tmp_1;
}

ElmcValue *elmc_fn_Elm_Kernel_PebbleWatch_healthAccessible(ElmcValue ** const args, const int argc) {
  /* Ownership policy: borrow_arg, borrow_result */
  (void)args;
  (void)argc;
  elmc_int_t metric = (argc > 0 && args[0]) ? elmc_as_int(args[0]) : 0;
  elmc_int_t startSeconds = (argc > 1 && args[1]) ? elmc_as_int(args[1]) : 0;
  elmc_int_t endSeconds = (argc > 2 && args[2]) ? elmc_as_int(args[2]) : 0;
  ElmcValue *toMsg = (argc > 3) ? args[3] : NULL;
  return elmc_fn_Elm_Kernel_PebbleWatch_healthAccessible_native(metric, startSeconds, endSeconds, toMsg);
}

static ElmcValue *elmc_fn_Elm_Kernel_PebbleWatch_healthAccessible_native(const elmc_int_t metric, const elmc_int_t startSeconds, const elmc_int_t endSeconds, ElmcValue * const toMsg) {
  (void)metric;
  (void)startSeconds;
  (void)endSeconds;
  (void)toMsg;
  
  ElmcValue *tmp_1 = elmc_int_zero();
  
  return tmp_1;
}

ElmcValue *elmc_fn_Pebble_Accel_defaultConfig(ElmcValue ** const args, const int argc) {
  /* Ownership policy: borrow_arg, borrow_result */
  (void)args;
  (void)argc;

  
  
  
  
  
  const char *rec_names_1[2] = { "samplesPerUpdate", "samplingRate" };
  elmc_int_t rec_values_1[2] = { 1, 2 };
  ElmcValue *tmp_1 = elmc_record_new_ints(2, rec_names_1, rec_values_1);

  
  
  return tmp_1;

}

ElmcValue *elmc_fn_Pebble_Health_value(ElmcValue ** const args, const int argc) {
  /* Ownership policy: borrow_arg, borrow_result */
  (void)args;
  (void)argc;
ElmcValue *metric = (argc > 0) ? args[0] : NULL;
  (void)metric;
  
  

  

  ElmcValue *tmp_1 = elmc_retain(metric);
  
  ElmcValue *call_args_2[1] = { tmp_1 };
  ElmcValue *tmp_2 = elmc_fn_Pebble_Health_metricToInt(call_args_2, 1);
  
  elmc_release(tmp_1);

  
  ElmcValue *cap_3[1] = { tmp_2 };
  ElmcValue *tmp_3 = elmc_closure_new(elmc_partial_ref_1, 1, 1, cap_3);

  
  elmc_release(tmp_2);

  
  
  return tmp_3;

}

ElmcValue *elmc_fn_Pebble_Health_sumToday(ElmcValue ** const args, const int argc) {
  /* Ownership policy: borrow_arg, borrow_result */
  (void)args;
  (void)argc;
ElmcValue *metric = (argc > 0) ? args[0] : NULL;
  (void)metric;
  
  

  

  ElmcValue *tmp_1 = elmc_retain(metric);
  
  ElmcValue *call_args_2[1] = { tmp_1 };
  ElmcValue *tmp_2 = elmc_fn_Pebble_Health_metricToInt(call_args_2, 1);
  
  elmc_release(tmp_1);

  
  ElmcValue *cap_3[1] = { tmp_2 };
  ElmcValue *tmp_3 = elmc_closure_new(elmc_partial_ref_2, 1, 1, cap_3);

  
  elmc_release(tmp_2);

  
  
  return tmp_3;

}

ElmcValue *elmc_fn_Pebble_Health_sum(ElmcValue ** const args, const int argc) {
  /* Ownership policy: borrow_arg, borrow_result */
  (void)args;
  (void)argc;
ElmcValue *metric = (argc > 0) ? args[0] : NULL;
  ElmcValue *startSeconds = (argc > 1) ? args[1] : NULL;
  ElmcValue *endSeconds = (argc > 2) ? args[2] : NULL;
  (void)metric;
  (void)startSeconds;
  (void)endSeconds;
  
  

  

  ElmcValue *tmp_1 = elmc_retain(metric);
  
  ElmcValue *call_args_2[1] = { tmp_1 };
  ElmcValue *tmp_2 = elmc_fn_Pebble_Health_metricToInt(call_args_2, 1);
  
  elmc_release(tmp_1);

  ElmcValue *tmp_3 = elmc_retain(startSeconds);
  ElmcValue *tmp_4 = elmc_retain(endSeconds);
  
  ElmcValue *cap_5[3] = { tmp_2, tmp_3, tmp_4 };
  ElmcValue *tmp_5 = elmc_closure_new(elmc_partial_ref_3, 1, 3, cap_5);

  
  elmc_release(tmp_2);
  elmc_release(tmp_3);
  elmc_release(tmp_4);

  
  
  return tmp_5;

}

ElmcValue *elmc_fn_Pebble_Health_accessible(ElmcValue ** const args, const int argc) {
  /* Ownership policy: borrow_arg, borrow_result */
  (void)args;
  (void)argc;
ElmcValue *metric = (argc > 0) ? args[0] : NULL;
  ElmcValue *startSeconds = (argc > 1) ? args[1] : NULL;
  ElmcValue *endSeconds = (argc > 2) ? args[2] : NULL;
  (void)metric;
  (void)startSeconds;
  (void)endSeconds;
  
  

  

  ElmcValue *tmp_1 = elmc_retain(metric);
  
  ElmcValue *call_args_2[1] = { tmp_1 };
  ElmcValue *tmp_2 = elmc_fn_Pebble_Health_metricToInt(call_args_2, 1);
  
  elmc_release(tmp_1);

  ElmcValue *tmp_3 = elmc_retain(startSeconds);
  ElmcValue *tmp_4 = elmc_retain(endSeconds);
  
  ElmcValue *cap_5[3] = { tmp_2, tmp_3, tmp_4 };
  ElmcValue *tmp_5 = elmc_closure_new(elmc_partial_ref_4, 1, 3, cap_5);

  
  elmc_release(tmp_2);
  elmc_release(tmp_3);
  elmc_release(tmp_4);

  
  
  return tmp_5;

}

ElmcValue *elmc_fn_Pebble_Health_metricToInt(ElmcValue ** const args, const int argc) {
  /* Ownership policy: borrow_arg, borrow_result */
  (void)args;
  (void)argc;
ElmcValue *metric = (argc > 0) ? args[0] : NULL;
  (void)metric;
  
  ElmcValue *tmp_1;
  
  if ((metric) && (((metric)->tag == ELMC_TAG_INT && elmc_as_int(metric) == 1) || ((metric)->tag == ELMC_TAG_TUPLE2 && (metric)->payload != NULL && elmc_as_int(((ElmcTuple2 *)(metric)->payload)->first) == 1))) {



    tmp_1 = elmc_int_zero();

}
else if ((metric) && (((metric)->tag == ELMC_TAG_INT && elmc_as_int(metric) == 2) || ((metric)->tag == ELMC_TAG_TUPLE2 && (metric)->payload != NULL && elmc_as_int(((ElmcTuple2 *)(metric)->payload)->first) == 2))) {



    tmp_1 = elmc_new_int(1);

}
else if ((metric) && (((metric)->tag == ELMC_TAG_INT && elmc_as_int(metric) == 3) || ((metric)->tag == ELMC_TAG_TUPLE2 && (metric)->payload != NULL && elmc_as_int(((ElmcTuple2 *)(metric)->payload)->first) == 3))) {



    tmp_1 = elmc_new_int(2);

}
else if ((metric) && (((metric)->tag == ELMC_TAG_INT && elmc_as_int(metric) == 4) || ((metric)->tag == ELMC_TAG_TUPLE2 && (metric)->payload != NULL && elmc_as_int(((ElmcTuple2 *)(metric)->payload)->first) == 4))) {



    tmp_1 = elmc_new_int(3);

}
else if ((metric) && (((metric)->tag == ELMC_TAG_INT && elmc_as_int(metric) == 5) || ((metric)->tag == ELMC_TAG_TUPLE2 && (metric)->payload != NULL && elmc_as_int(((ElmcTuple2 *)(metric)->payload)->first) == 5))) {



    tmp_1 = elmc_new_int(4);

}
else if ((metric) && (((metric)->tag == ELMC_TAG_INT && elmc_as_int(metric) == 6) || ((metric)->tag == ELMC_TAG_TUPLE2 && (metric)->payload != NULL && elmc_as_int(((ElmcTuple2 *)(metric)->payload)->first) == 6))) {



    tmp_1 = elmc_new_int(5);

}
else if ((metric) && (((metric)->tag == ELMC_TAG_INT && elmc_as_int(metric) == 7) || ((metric)->tag == ELMC_TAG_TUPLE2 && (metric)->payload != NULL && elmc_as_int(((ElmcTuple2 *)(metric)->payload)->first) == 7))) {



    tmp_1 = elmc_new_int(6);

}
else {



    tmp_1 = elmc_new_int(7);

}

  

  
  
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
  
  ElmcValue *tmp_1;
  
  if ((launchReason) && (((launchReason)->tag == ELMC_TAG_INT && elmc_as_int(launchReason) == 1) || ((launchReason)->tag == ELMC_TAG_TUPLE2 && (launchReason)->payload != NULL && elmc_as_int(((ElmcTuple2 *)(launchReason)->payload)->first) == 1))) {



    tmp_1 = elmc_int_zero();

}
else if ((launchReason) && (((launchReason)->tag == ELMC_TAG_INT && elmc_as_int(launchReason) == 2) || ((launchReason)->tag == ELMC_TAG_TUPLE2 && (launchReason)->payload != NULL && elmc_as_int(((ElmcTuple2 *)(launchReason)->payload)->first) == 2))) {



    tmp_1 = elmc_new_int(1);

}
else if ((launchReason) && (((launchReason)->tag == ELMC_TAG_INT && elmc_as_int(launchReason) == 3) || ((launchReason)->tag == ELMC_TAG_TUPLE2 && (launchReason)->payload != NULL && elmc_as_int(((ElmcTuple2 *)(launchReason)->payload)->first) == 3))) {



    tmp_1 = elmc_new_int(2);

}
else if ((launchReason) && (((launchReason)->tag == ELMC_TAG_INT && elmc_as_int(launchReason) == 4) || ((launchReason)->tag == ELMC_TAG_TUPLE2 && (launchReason)->payload != NULL && elmc_as_int(((ElmcTuple2 *)(launchReason)->payload)->first) == 4))) {



    tmp_1 = elmc_new_int(3);

}
else if ((launchReason) && (((launchReason)->tag == ELMC_TAG_INT && elmc_as_int(launchReason) == 5) || ((launchReason)->tag == ELMC_TAG_TUPLE2 && (launchReason)->payload != NULL && elmc_as_int(((ElmcTuple2 *)(launchReason)->payload)->first) == 5))) {



    tmp_1 = elmc_new_int(4);

}
else if ((launchReason) && (((launchReason)->tag == ELMC_TAG_INT && elmc_as_int(launchReason) == 6) || ((launchReason)->tag == ELMC_TAG_TUPLE2 && (launchReason)->payload != NULL && elmc_as_int(((ElmcTuple2 *)(launchReason)->payload)->first) == 6))) {



    tmp_1 = elmc_new_int(5);

}
else if ((launchReason) && (((launchReason)->tag == ELMC_TAG_INT && elmc_as_int(launchReason) == 7) || ((launchReason)->tag == ELMC_TAG_TUPLE2 && (launchReason)->payload != NULL && elmc_as_int(((ElmcTuple2 *)(launchReason)->payload)->first) == 7))) {



    tmp_1 = elmc_new_int(6);

}
else if ((launchReason) && (((launchReason)->tag == ELMC_TAG_INT && elmc_as_int(launchReason) == 8) || ((launchReason)->tag == ELMC_TAG_TUPLE2 && (launchReason)->payload != NULL && elmc_as_int(((ElmcTuple2 *)(launchReason)->payload)->first) == 8))) {



    tmp_1 = elmc_new_int(7);

}
else {



    tmp_1 = elmc_new_int(-1);

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

  const elmc_int_t direct_native_let_parsedInt_6 = native_maybe_default_5;

  
    ElmcValue *tmp_7 = elmc_int_zero();
  
    ElmcValue *tmp_8 = elmc_new_string("3.14");
    ElmcValue *tmp_9 = elmc_string_to_float(tmp_8);
    elmc_release(tmp_8);
  

    ElmcValue *tmp_10 = elmc_maybe_with_default(tmp_7, tmp_9);
    elmc_release(tmp_7);
    elmc_release(tmp_9);
  

    ElmcValue *tmp_11 = elmc_basics_floor(tmp_10);
    elmc_release(tmp_10);
  

  


   if (*emitted >= skip && *count < max_cmds) {

     elmc_generated_draw_init(&out_cmds[*count], ELMC_PEBBLE_DRAW_CLEAR);
      out_cmds[*count].p0 = 255;
      *count += 1;
    }
   *emitted += 1;
   if (*count >= max_cmds) return 0;

   if (*emitted >= skip && *count < max_cmds) {

     elmc_generated_draw_init(&out_cmds[*count], ELMC_PEBBLE_DRAW_TEXT_INT_WITH_FONT);
      out_cmds[*count].p0 = 1;
    out_cmds[*count].p1 = 0;
    out_cmds[*count].p2 = 24;
    out_cmds[*count].p3 = direct_native_let_parsedInt_6;
      *count += 1;
    }
   *emitted += 1;
   if (*count >= max_cmds) return 0;

   if (*emitted >= skip && *count < max_cmds) {

     elmc_generated_draw_init(&out_cmds[*count], ELMC_PEBBLE_DRAW_TEXT_INT_WITH_FONT);
      out_cmds[*count].p0 = 1;
    out_cmds[*count].p1 = 0;
    out_cmds[*count].p2 = 48;
    out_cmds[*count].p3 = elmc_as_int(tmp_11);
      *count += 1;
    }
   *emitted += 1;
   if (*count >= max_cmds) return 0;

   if (*emitted >= skip && *count < max_cmds) {

     elmc_generated_draw_init(&out_cmds[*count], ELMC_PEBBLE_DRAW_TEXT_INT_WITH_FONT);
      out_cmds[*count].p0 = 1;
    out_cmds[*count].p1 = 0;
    out_cmds[*count].p2 = 72;
    out_cmds[*count].p3 = ELMC_RECORD_GET_INDEX_INT(model, 1 /* ticks */);
      *count += 1;
    }
   *emitted += 1;
   if (*count >= max_cmds) return 0;

    elmc_release(tmp_11);


  return 0;
}

int elmc_fn_Main_view_commands(ElmcValue ** const args, const int argc, void * const out_cmds, const int max_cmds) {
  return elmc_fn_Main_view_commands_from(args, argc, out_cmds, max_cmds, 0);
}

int elmc_fn_Main_view_commands_from(ElmcValue ** const args, const int argc, void * const out_cmds, const int max_cmds, const int skip) {
  int count = 0;
  int emitted = 0;
  if (!out_cmds || max_cmds <= 0) return -1;
  if (skip < 0) return -1;
  int rc = elmc_fn_Main_view_commands_append(args, argc, (ElmcGeneratedPebbleDrawCmd *)out_cmds, max_cmds, skip, &count, &emitted);
  return rc < 0 ? rc : count;
}

