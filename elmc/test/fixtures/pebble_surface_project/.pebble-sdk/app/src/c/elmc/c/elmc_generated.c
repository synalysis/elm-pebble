#include "elmc_generated.h"



ElmcValue *elmc_fn_Main_parseHourFromTimeString(ElmcValue **args, int argc) {
  /* Ownership policy: retain_arg, retain_result */
  (void)args;
  (void)argc;
ElmcValue *value = (argc > 0) ? args[0] : NULL;
  
  
  ElmcValue *tmp_1 = elmc_new_int(0);
  
  
  ElmcValue *tmp_2 = elmc_new_int(2);
  ElmcValue *tmp_3 = value ? elmc_retain(value) : elmc_new_int(0);
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

ElmcValue *elmc_fn_Main_init(ElmcValue **args, int argc) {
  /* Ownership policy: borrow_arg, borrow_result */
  (void)args;
  (void)argc;
ElmcValue *launchReason = (argc > 0) ? args[0] : NULL;
  
  
  ElmcValue *tmp_1 = launchReason ? elmc_retain(launchReason) : elmc_new_int(0);
  ElmcValue *call_args_2[1] = { tmp_1 };
  ElmcValue *tmp_2 = elmc_fn_Pebble_Platform_launchReasonToInt(call_args_2, 1);
  elmc_release(tmp_1);

  
  ElmcValue *tmp_3 = elmc_new_string("00:00");
  ElmcValue *tmp_4 = tmp_2 ? elmc_retain(tmp_2) : elmc_new_int(0);
  const char *rec_names_5[2] = { "latestTime", "ticks" };
  ElmcValue *rec_values_5[2] = { tmp_3, tmp_4 };
  ElmcValue *tmp_5 = elmc_record_new(2, rec_names_5, rec_values_5);
  elmc_release(tmp_3);
  elmc_release(tmp_4);

  ElmcValue *tmp_6 = elmc_new_int(0);
  ElmcValue *tmp_7 = elmc_tuple2(tmp_5, tmp_6);
  elmc_release(tmp_5);
  elmc_release(tmp_6);

  elmc_release(tmp_2);

  return tmp_7;

}

ElmcValue *elmc_fn_Main_update(ElmcValue **args, int argc) {
  /* Ownership policy: borrow_arg, borrow_result */
  (void)args;
  (void)argc;
ElmcValue *msg = (argc > 0) ? args[0] : NULL;
  ElmcValue *model = (argc > 1) ? args[1] : NULL;
  
  ElmcValue *tmp_1 = elmc_new_int(0);
  if ((msg) && (((msg)->tag == ELMC_TAG_INT && elmc_as_int(msg) == 1) || ((msg)->tag == ELMC_TAG_TUPLE2 && (msg)->payload != NULL && elmc_as_int(((ElmcTuple2 *)(msg)->payload)->first) == 1))) {

      ElmcValue *tmp_2 = elmc_record_get(model, "ticks");
      ElmcValue *tmp_3 = elmc_new_int(1);
      ElmcValue *tmp_4 = elmc_new_int(elmc_as_int(tmp_2) + elmc_as_int(tmp_3));
      elmc_release(tmp_2);
      elmc_release(tmp_3);

      const char *rec_names_5[1] = { "ticks" };
      ElmcValue *rec_values_5[1] = { tmp_4 };
      ElmcValue *tmp_5 = elmc_record_new(1, rec_names_5, rec_values_5);
      elmc_release(tmp_4);

      ElmcValue *tmp_6 = elmc_new_int(1);
      ElmcValue *tmp_7 = elmc_new_int(1000);
      ElmcValue *tmp_8 = elmc_new_int(0);
      ElmcValue *tmp_9 = elmc_new_int(0);
      ElmcValue *tmp_10 = elmc_new_int(0);
      ElmcValue *tmp_11 = elmc_new_int(0);
      ElmcValue *tmp_12 = elmc_new_int(0);
      ElmcValue *tmp_13 = elmc_tuple2(tmp_11, tmp_12);
      elmc_release(tmp_11);
      elmc_release(tmp_12);

      ElmcValue *tmp_14 = elmc_tuple2(tmp_10, tmp_13);
      elmc_release(tmp_10);
      elmc_release(tmp_13);

      ElmcValue *tmp_15 = elmc_tuple2(tmp_9, tmp_14);
      elmc_release(tmp_9);
      elmc_release(tmp_14);

      ElmcValue *tmp_16 = elmc_tuple2(tmp_8, tmp_15);
      elmc_release(tmp_8);
      elmc_release(tmp_15);

      ElmcValue *tmp_17 = elmc_tuple2(tmp_7, tmp_16);
      elmc_release(tmp_7);
      elmc_release(tmp_16);

      ElmcValue *tmp_18 = elmc_tuple2(tmp_6, tmp_17);
      elmc_release(tmp_6);
      elmc_release(tmp_17);

      ElmcValue *tmp_19 = elmc_tuple2(tmp_5, tmp_18);
      elmc_release(tmp_5);
      elmc_release(tmp_18);

    elmc_release(tmp_1);
    tmp_1 = tmp_19;
}
else if ((msg) && (((msg)->tag == ELMC_TAG_INT && elmc_as_int(msg) == 2) || ((msg)->tag == ELMC_TAG_TUPLE2 && (msg)->payload != NULL && elmc_as_int(((ElmcTuple2 *)(msg)->payload)->first) == 2))) {
    ElmcValue *tmp_20 = model ? elmc_retain(model) : elmc_new_int(0);
      ElmcValue *tmp_21 = elmc_new_int(2);
      ElmcValue *tmp_22 = elmc_new_int(10);
      ElmcValue *tmp_23 = elmc_record_get(model, "ticks");
      ElmcValue *tmp_24 = elmc_new_int(1);
      ElmcValue *tmp_25 = elmc_new_int(elmc_as_int(tmp_23) + elmc_as_int(tmp_24));
      elmc_release(tmp_23);
      elmc_release(tmp_24);

      ElmcValue *tmp_26 = elmc_new_int(0);
      ElmcValue *tmp_27 = elmc_new_int(0);
      ElmcValue *tmp_28 = elmc_new_int(0);
      ElmcValue *tmp_29 = elmc_new_int(0);
      ElmcValue *tmp_30 = elmc_tuple2(tmp_28, tmp_29);
      elmc_release(tmp_28);
      elmc_release(tmp_29);

      ElmcValue *tmp_31 = elmc_tuple2(tmp_27, tmp_30);
      elmc_release(tmp_27);
      elmc_release(tmp_30);

      ElmcValue *tmp_32 = elmc_tuple2(tmp_26, tmp_31);
      elmc_release(tmp_26);
      elmc_release(tmp_31);

      ElmcValue *tmp_33 = elmc_tuple2(tmp_25, tmp_32);
      elmc_release(tmp_25);
      elmc_release(tmp_32);

      ElmcValue *tmp_34 = elmc_tuple2(tmp_22, tmp_33);
      elmc_release(tmp_22);
      elmc_release(tmp_33);

      ElmcValue *tmp_35 = elmc_tuple2(tmp_21, tmp_34);
      elmc_release(tmp_21);
      elmc_release(tmp_34);

      ElmcValue *tmp_36 = elmc_tuple2(tmp_20, tmp_35);
      elmc_release(tmp_20);
      elmc_release(tmp_35);

    elmc_release(tmp_1);
    tmp_1 = tmp_36;
}
else if ((msg) && (((msg)->tag == ELMC_TAG_INT && elmc_as_int(msg) == 3) || ((msg)->tag == ELMC_TAG_TUPLE2 && (msg)->payload != NULL && elmc_as_int(((ElmcTuple2 *)(msg)->payload)->first) == 3))) {
    ElmcValue *tmp_37 = model ? elmc_retain(model) : elmc_new_int(0);
      ElmcValue *tmp_38 = elmc_new_int(0);
      ElmcValue *tmp_39 = elmc_tuple2(tmp_37, tmp_38);
      elmc_release(tmp_37);
      elmc_release(tmp_38);

    elmc_release(tmp_1);
    tmp_1 = tmp_39;
}
else if ((msg) && (((msg)->tag == ELMC_TAG_INT && elmc_as_int(msg) == 4) || ((msg)->tag == ELMC_TAG_TUPLE2 && (msg)->payload != NULL && elmc_as_int(((ElmcTuple2 *)(msg)->payload)->first) == 4))) {
    ElmcValue *tmp_40 = model ? elmc_retain(model) : elmc_new_int(0);
      ElmcValue *tmp_41 = elmc_new_int(4);
      ElmcValue *tmp_42 = elmc_new_int(10);
      ElmcValue *tmp_43 = elmc_new_int(0);
      ElmcValue *tmp_44 = elmc_new_int(0);
      ElmcValue *tmp_45 = elmc_new_int(0);
      ElmcValue *tmp_46 = elmc_new_int(0);
      ElmcValue *tmp_47 = elmc_new_int(0);
      ElmcValue *tmp_48 = elmc_tuple2(tmp_46, tmp_47);
      elmc_release(tmp_46);
      elmc_release(tmp_47);

      ElmcValue *tmp_49 = elmc_tuple2(tmp_45, tmp_48);
      elmc_release(tmp_45);
      elmc_release(tmp_48);

      ElmcValue *tmp_50 = elmc_tuple2(tmp_44, tmp_49);
      elmc_release(tmp_44);
      elmc_release(tmp_49);

      ElmcValue *tmp_51 = elmc_tuple2(tmp_43, tmp_50);
      elmc_release(tmp_43);
      elmc_release(tmp_50);

      ElmcValue *tmp_52 = elmc_tuple2(tmp_42, tmp_51);
      elmc_release(tmp_42);
      elmc_release(tmp_51);

      ElmcValue *tmp_53 = elmc_tuple2(tmp_41, tmp_52);
      elmc_release(tmp_41);
      elmc_release(tmp_52);

      ElmcValue *tmp_54 = elmc_tuple2(tmp_40, tmp_53);
      elmc_release(tmp_40);
      elmc_release(tmp_53);

    elmc_release(tmp_1);
    tmp_1 = tmp_54;
}
else if ((msg) && (((msg)->tag == ELMC_TAG_INT && elmc_as_int(msg) == 5) || ((msg)->tag == ELMC_TAG_TUPLE2 && (msg)->payload != NULL && elmc_as_int(((ElmcTuple2 *)(msg)->payload)->first) == 5))) {
    ElmcValue *tmp_55 = model ? elmc_retain(model) : elmc_new_int(0);
  
      ElmcValue *call_args_56[1] = {  };
      ElmcValue *tmp_56 = elmc_fn_Pebble_Vibes_shortPulse(call_args_56, 0);
  

      ElmcValue *tmp_57 = elmc_tuple2(tmp_55, tmp_56);
      elmc_release(tmp_55);
      elmc_release(tmp_56);

    elmc_release(tmp_1);
    tmp_1 = tmp_57;
}
else if ((msg) && (((msg)->tag == ELMC_TAG_INT && elmc_as_int(msg) == 6) || ((msg)->tag == ELMC_TAG_TUPLE2 && (msg)->payload != NULL && elmc_as_int(((ElmcTuple2 *)(msg)->payload)->first) == 6))) {
    ElmcValue *tmp_58 = model ? elmc_retain(model) : elmc_new_int(0);
  
      ElmcValue *tmp_59 = elmc_new_int(404);
      ElmcValue *call_args_60[1] = { tmp_59 };
      ElmcValue *tmp_60 = elmc_fn_Pebble_Log_infoCode(call_args_60, 1);
      elmc_release(tmp_59);

      ElmcValue *tmp_61 = elmc_tuple2(tmp_58, tmp_60);
      elmc_release(tmp_58);
      elmc_release(tmp_60);

    elmc_release(tmp_1);
    tmp_1 = tmp_61;
}
else if ((msg) && (((msg)->tag == ELMC_TAG_INT && elmc_as_int(msg) == 7) || ((msg)->tag == ELMC_TAG_TUPLE2 && (msg)->payload != NULL && elmc_as_int(((ElmcTuple2 *)(msg)->payload)->first) == 7))) {
    ElmcValue *tmp_62 = model ? elmc_retain(model) : elmc_new_int(0);
  
      ElmcValue *tmp_63 = elmc_new_int(505);
      ElmcValue *call_args_64[1] = { tmp_63 };
      ElmcValue *tmp_64 = elmc_fn_Pebble_Log_warnCode(call_args_64, 1);
      elmc_release(tmp_63);

      ElmcValue *tmp_65 = elmc_tuple2(tmp_62, tmp_64);
      elmc_release(tmp_62);
      elmc_release(tmp_64);

    elmc_release(tmp_1);
    tmp_1 = tmp_65;
}
else if ((msg) && (((msg)->tag == ELMC_TAG_INT && elmc_as_int(msg) == 8) || ((msg)->tag == ELMC_TAG_TUPLE2 && (msg)->payload != NULL && elmc_as_int(((ElmcTuple2 *)(msg)->payload)->first) == 8))) {

      ElmcValue *tmp_66 = ((ElmcTuple2 *)msg->payload)->second ? elmc_retain(((ElmcTuple2 *)msg->payload)->second) : elmc_new_int(0);
  
      ElmcValue *tmp_67 = ((ElmcTuple2 *)msg->payload)->second ? elmc_retain(((ElmcTuple2 *)msg->payload)->second) : elmc_new_int(0);
      ElmcValue *call_args_68[1] = { tmp_67 };
      ElmcValue *tmp_68 = elmc_fn_Main_parseHourFromTimeString(call_args_68, 1);
      elmc_release(tmp_67);

      const char *rec_names_69[2] = { "latestTime", "ticks" };
      ElmcValue *rec_values_69[2] = { tmp_66, tmp_68 };
      ElmcValue *tmp_69 = elmc_record_new(2, rec_names_69, rec_values_69);
      elmc_release(tmp_66);
      elmc_release(tmp_68);

      ElmcValue *tmp_70 = elmc_new_int(0);
      ElmcValue *tmp_71 = elmc_tuple2(tmp_69, tmp_70);
      elmc_release(tmp_69);
      elmc_release(tmp_70);

    elmc_release(tmp_1);
    tmp_1 = tmp_71;
}
else if ((msg) && (((msg)->tag == ELMC_TAG_INT && elmc_as_int(msg) == 12) || ((msg)->tag == ELMC_TAG_TUPLE2 && (msg)->payload != NULL && elmc_as_int(((ElmcTuple2 *)(msg)->payload)->first) == 12))) {

      ElmcValue *tmp_72 = ((ElmcTuple2 *)msg->payload)->second ? elmc_retain(((ElmcTuple2 *)msg->payload)->second) : elmc_new_int(0);
      const char *rec_names_73[1] = { "ticks" };
      ElmcValue *rec_values_73[1] = { tmp_72 };
      ElmcValue *tmp_73 = elmc_record_new(1, rec_names_73, rec_values_73);
      elmc_release(tmp_72);

      ElmcValue *tmp_74 = elmc_new_int(0);
      ElmcValue *tmp_75 = elmc_tuple2(tmp_73, tmp_74);
      elmc_release(tmp_73);
      elmc_release(tmp_74);

    elmc_release(tmp_1);
    tmp_1 = tmp_75;
}
else if ((msg) && (((msg)->tag == ELMC_TAG_INT && elmc_as_int(msg) == 16) || ((msg)->tag == ELMC_TAG_TUPLE2 && (msg)->payload != NULL && elmc_as_int(((ElmcTuple2 *)(msg)->payload)->first) == 16))) {
    ElmcValue *tmp_76 = elmc_new_int(0);
    elmc_release(tmp_1);
    tmp_1 = tmp_76;
}
else if ((msg) && (((msg)->tag == ELMC_TAG_INT && elmc_as_int(msg) == 17) || ((msg)->tag == ELMC_TAG_TUPLE2 && (msg)->payload != NULL && elmc_as_int(((ElmcTuple2 *)(msg)->payload)->first) == 17))) {
    ElmcValue *tmp_77 = elmc_new_int(0);
    elmc_release(tmp_1);
    tmp_1 = tmp_77;
}
else if ((msg) && (((msg)->tag == ELMC_TAG_INT && elmc_as_int(msg) == 9) || ((msg)->tag == ELMC_TAG_TUPLE2 && (msg)->payload != NULL && elmc_as_int(((ElmcTuple2 *)(msg)->payload)->first) == 9))) {
    ElmcValue *tmp_78 = model ? elmc_retain(model) : elmc_new_int(0);
      ElmcValue *tmp_79 = elmc_new_int(0);
      ElmcValue *tmp_80 = elmc_tuple2(tmp_78, tmp_79);
      elmc_release(tmp_78);
      elmc_release(tmp_79);

    elmc_release(tmp_1);
    tmp_1 = tmp_80;
}
else if ((msg) && (((msg)->tag == ELMC_TAG_INT && elmc_as_int(msg) == 10) || ((msg)->tag == ELMC_TAG_TUPLE2 && (msg)->payload != NULL && elmc_as_int(((ElmcTuple2 *)(msg)->payload)->first) == 10))) {
    ElmcValue *tmp_81 = model ? elmc_retain(model) : elmc_new_int(0);
      ElmcValue *tmp_82 = elmc_new_int(0);
      ElmcValue *tmp_83 = elmc_tuple2(tmp_81, tmp_82);
      elmc_release(tmp_81);
      elmc_release(tmp_82);

    elmc_release(tmp_1);
    tmp_1 = tmp_83;
}
else if ((msg) && (((msg)->tag == ELMC_TAG_INT && elmc_as_int(msg) == 11) || ((msg)->tag == ELMC_TAG_TUPLE2 && (msg)->payload != NULL && elmc_as_int(((ElmcTuple2 *)(msg)->payload)->first) == 11))) {
    ElmcValue *tmp_84 = model ? elmc_retain(model) : elmc_new_int(0);
      ElmcValue *tmp_85 = elmc_new_int(0);
      ElmcValue *tmp_86 = elmc_tuple2(tmp_84, tmp_85);
      elmc_release(tmp_84);
      elmc_release(tmp_85);

    elmc_release(tmp_1);
    tmp_1 = tmp_86;
}
else if ((msg) && (((msg)->tag == ELMC_TAG_INT && elmc_as_int(msg) == 13) || ((msg)->tag == ELMC_TAG_TUPLE2 && (msg)->payload != NULL && elmc_as_int(((ElmcTuple2 *)(msg)->payload)->first) == 13))) {
    ElmcValue *tmp_87 = model ? elmc_retain(model) : elmc_new_int(0);
      ElmcValue *tmp_88 = elmc_new_int(0);
      ElmcValue *tmp_89 = elmc_tuple2(tmp_87, tmp_88);
      elmc_release(tmp_87);
      elmc_release(tmp_88);

    elmc_release(tmp_1);
    tmp_1 = tmp_89;
}
else if ((msg) && (((msg)->tag == ELMC_TAG_INT && elmc_as_int(msg) == 14) || ((msg)->tag == ELMC_TAG_TUPLE2 && (msg)->payload != NULL && elmc_as_int(((ElmcTuple2 *)(msg)->payload)->first) == 14))) {
    ElmcValue *tmp_90 = model ? elmc_retain(model) : elmc_new_int(0);
      ElmcValue *tmp_91 = elmc_new_int(0);
      ElmcValue *tmp_92 = elmc_tuple2(tmp_90, tmp_91);
      elmc_release(tmp_90);
      elmc_release(tmp_91);

    elmc_release(tmp_1);
    tmp_1 = tmp_92;
}
else if ((msg) && (((msg)->tag == ELMC_TAG_INT && elmc_as_int(msg) == 15) || ((msg)->tag == ELMC_TAG_TUPLE2 && (msg)->payload != NULL && elmc_as_int(((ElmcTuple2 *)(msg)->payload)->first) == 15))) {
    ElmcValue *tmp_93 = model ? elmc_retain(model) : elmc_new_int(0);
      ElmcValue *tmp_94 = elmc_new_int(0);
      ElmcValue *tmp_95 = elmc_tuple2(tmp_93, tmp_94);
      elmc_release(tmp_93);
      elmc_release(tmp_94);

    elmc_release(tmp_1);
    tmp_1 = tmp_95;
}


  return tmp_1;

}

ElmcValue *elmc_fn_Main_subscriptions(ElmcValue **args, int argc) {
  /* Ownership policy: borrow_arg, borrow_result */
  (void)args;
  (void)argc;
ElmcValue *_ = (argc > 0) ? args[0] : NULL;
  (void)_;
  ElmcValue *tmp_1 = elmc_new_int(127);
  return tmp_1;

}

ElmcValue *elmc_fn_Main_view(ElmcValue **args, int argc) {
  /* Ownership policy: borrow_arg, borrow_result */
  (void)args;
  (void)argc;
ElmcValue *model = (argc > 0) ? args[0] : NULL;
  
  
  ElmcValue *tmp_1 = elmc_record_get(model, "latestTime");
  ElmcValue *call_args_2[1] = { tmp_1 };
  ElmcValue *tmp_2 = elmc_fn_Main_parseHourFromTimeString(call_args_2, 1);
  elmc_release(tmp_1);

  
  
  ElmcValue *tmp_3 = elmc_new_int(0);
  
  ElmcValue *tmp_4 = elmc_new_string("3.14");
  ElmcValue *tmp_5 = elmc_string_to_float(tmp_4);
  elmc_release(tmp_4);

  ElmcValue *tmp_6 = elmc_maybe_with_default(tmp_3, tmp_5);
  elmc_release(tmp_3);
  elmc_release(tmp_5);

  ElmcValue *tmp_7 = elmc_basics_floor(tmp_6);
  elmc_release(tmp_6);

  ElmcValue *tmp_8 = elmc_new_int(1000);
  ElmcValue *tmp_9 = elmc_list_nil();
  ElmcValue *tmp_10 = elmc_new_int(1001);
  ElmcValue *tmp_11 = elmc_new_int(1);
  ElmcValue *tmp_12 = elmc_list_nil();
  ElmcValue *tmp_13 = elmc_new_int(1002);
  ElmcValue *tmp_14 = elmc_new_int(1);
  ElmcValue *tmp_15 = elmc_list_nil();
  ElmcValue *tmp_16 = elmc_new_int(1);
  ElmcValue *tmp_17 = elmc_new_int(0);
  ElmcValue *tmp_18 = elmc_new_int(72);
  ElmcValue *tmp_19 = elmc_record_get(model, "ticks");
  ElmcValue *tmp_20 = elmc_new_int(0);
  ElmcValue *tmp_21 = elmc_new_int(0);
  ElmcValue *tmp_22 = elmc_new_int(0);
  ElmcValue *tmp_23 = elmc_tuple2(tmp_21, tmp_22);
  elmc_release(tmp_21);
  elmc_release(tmp_22);

  ElmcValue *tmp_24 = elmc_tuple2(tmp_20, tmp_23);
  elmc_release(tmp_20);
  elmc_release(tmp_23);

  ElmcValue *tmp_25 = elmc_tuple2(tmp_19, tmp_24);
  elmc_release(tmp_19);
  elmc_release(tmp_24);

  ElmcValue *tmp_26 = elmc_tuple2(tmp_18, tmp_25);
  elmc_release(tmp_18);
  elmc_release(tmp_25);

  ElmcValue *tmp_27 = elmc_tuple2(tmp_17, tmp_26);
  elmc_release(tmp_17);
  elmc_release(tmp_26);

  ElmcValue *tmp_28 = elmc_tuple2(tmp_16, tmp_27);
  elmc_release(tmp_16);
  elmc_release(tmp_27);

  ElmcValue *tmp_29 = elmc_list_cons(tmp_28, tmp_15);
  elmc_release(tmp_28);
  elmc_release(tmp_15);

  ElmcValue *tmp_30 = elmc_new_int(1);
  ElmcValue *tmp_31 = elmc_new_int(0);
  ElmcValue *tmp_32 = elmc_new_int(48);
  ElmcValue *tmp_33 = tmp_7 ? elmc_retain(tmp_7) : elmc_new_int(0);
  ElmcValue *tmp_34 = elmc_new_int(0);
  ElmcValue *tmp_35 = elmc_new_int(0);
  ElmcValue *tmp_36 = elmc_new_int(0);
  ElmcValue *tmp_37 = elmc_tuple2(tmp_35, tmp_36);
  elmc_release(tmp_35);
  elmc_release(tmp_36);

  ElmcValue *tmp_38 = elmc_tuple2(tmp_34, tmp_37);
  elmc_release(tmp_34);
  elmc_release(tmp_37);

  ElmcValue *tmp_39 = elmc_tuple2(tmp_33, tmp_38);
  elmc_release(tmp_33);
  elmc_release(tmp_38);

  ElmcValue *tmp_40 = elmc_tuple2(tmp_32, tmp_39);
  elmc_release(tmp_32);
  elmc_release(tmp_39);

  ElmcValue *tmp_41 = elmc_tuple2(tmp_31, tmp_40);
  elmc_release(tmp_31);
  elmc_release(tmp_40);

  ElmcValue *tmp_42 = elmc_tuple2(tmp_30, tmp_41);
  elmc_release(tmp_30);
  elmc_release(tmp_41);

  ElmcValue *tmp_43 = elmc_list_cons(tmp_42, tmp_29);
  elmc_release(tmp_42);
  elmc_release(tmp_29);

  ElmcValue *tmp_44 = elmc_new_int(1);
  ElmcValue *tmp_45 = elmc_new_int(0);
  ElmcValue *tmp_46 = elmc_new_int(24);
  ElmcValue *tmp_47 = tmp_2 ? elmc_retain(tmp_2) : elmc_new_int(0);
  ElmcValue *tmp_48 = elmc_new_int(0);
  ElmcValue *tmp_49 = elmc_new_int(0);
  ElmcValue *tmp_50 = elmc_new_int(0);
  ElmcValue *tmp_51 = elmc_tuple2(tmp_49, tmp_50);
  elmc_release(tmp_49);
  elmc_release(tmp_50);

  ElmcValue *tmp_52 = elmc_tuple2(tmp_48, tmp_51);
  elmc_release(tmp_48);
  elmc_release(tmp_51);

  ElmcValue *tmp_53 = elmc_tuple2(tmp_47, tmp_52);
  elmc_release(tmp_47);
  elmc_release(tmp_52);

  ElmcValue *tmp_54 = elmc_tuple2(tmp_46, tmp_53);
  elmc_release(tmp_46);
  elmc_release(tmp_53);

  ElmcValue *tmp_55 = elmc_tuple2(tmp_45, tmp_54);
  elmc_release(tmp_45);
  elmc_release(tmp_54);

  ElmcValue *tmp_56 = elmc_tuple2(tmp_44, tmp_55);
  elmc_release(tmp_44);
  elmc_release(tmp_55);

  ElmcValue *tmp_57 = elmc_list_cons(tmp_56, tmp_43);
  elmc_release(tmp_56);
  elmc_release(tmp_43);

  ElmcValue *tmp_58 = elmc_new_int(2);
  ElmcValue *tmp_59 = elmc_new_int(0);
  ElmcValue *tmp_60 = elmc_new_int(0);
  ElmcValue *tmp_61 = elmc_new_int(0);
  ElmcValue *tmp_62 = elmc_new_int(0);
  ElmcValue *tmp_63 = elmc_new_int(0);
  ElmcValue *tmp_64 = elmc_new_int(0);
  ElmcValue *tmp_65 = elmc_tuple2(tmp_63, tmp_64);
  elmc_release(tmp_63);
  elmc_release(tmp_64);

  ElmcValue *tmp_66 = elmc_tuple2(tmp_62, tmp_65);
  elmc_release(tmp_62);
  elmc_release(tmp_65);

  ElmcValue *tmp_67 = elmc_tuple2(tmp_61, tmp_66);
  elmc_release(tmp_61);
  elmc_release(tmp_66);

  ElmcValue *tmp_68 = elmc_tuple2(tmp_60, tmp_67);
  elmc_release(tmp_60);
  elmc_release(tmp_67);

  ElmcValue *tmp_69 = elmc_tuple2(tmp_59, tmp_68);
  elmc_release(tmp_59);
  elmc_release(tmp_68);

  ElmcValue *tmp_70 = elmc_tuple2(tmp_58, tmp_69);
  elmc_release(tmp_58);
  elmc_release(tmp_69);

  ElmcValue *tmp_71 = elmc_list_cons(tmp_70, tmp_57);
  elmc_release(tmp_70);
  elmc_release(tmp_57);

  ElmcValue *tmp_72 = elmc_tuple2(tmp_14, tmp_71);
  elmc_release(tmp_14);
  elmc_release(tmp_71);

  ElmcValue *tmp_73 = elmc_tuple2(tmp_13, tmp_72);
  elmc_release(tmp_13);
  elmc_release(tmp_72);

  ElmcValue *tmp_74 = elmc_list_cons(tmp_73, tmp_12);
  elmc_release(tmp_73);
  elmc_release(tmp_12);

  ElmcValue *tmp_75 = elmc_tuple2(tmp_11, tmp_74);
  elmc_release(tmp_11);
  elmc_release(tmp_74);

  ElmcValue *tmp_76 = elmc_tuple2(tmp_10, tmp_75);
  elmc_release(tmp_10);
  elmc_release(tmp_75);

  ElmcValue *tmp_77 = elmc_list_cons(tmp_76, tmp_9);
  elmc_release(tmp_76);
  elmc_release(tmp_9);

  ElmcValue *tmp_78 = elmc_tuple2(tmp_8, tmp_77);
  elmc_release(tmp_8);
  elmc_release(tmp_77);

  elmc_release(tmp_7);

  elmc_release(tmp_2);

  return tmp_78;

}

ElmcValue *elmc_fn_Main_main(ElmcValue **args, int argc) {
  /* Ownership policy: borrow_arg, borrow_result */
  (void)args;
  (void)argc;

  
  ElmcValue *tmp_1 = elmc_new_int(0);
  return tmp_1;

}

ElmcValue *elmc_fn_Elm_Kernel_PebbleWatch_none(ElmcValue **args, int argc) {
  /* Ownership policy: borrow_arg, borrow_result */
  (void)args;
  (void)argc;

  
  ElmcValue *tmp_1 = elmc_new_int(0);
  return tmp_1;

}

ElmcValue *elmc_fn_Elm_Kernel_PebbleWatch_timerAfter(ElmcValue **args, int argc) {
  /* Ownership policy: borrow_arg, borrow_result */
  (void)args;
  (void)argc;
ElmcValue *ms = (argc > 0) ? args[0] : NULL;
  
  ElmcValue *tmp_1 = ms ? elmc_retain(ms) : elmc_new_int(0);
  ElmcValue *tmp_2 = elmc_new_int(0);
  elmc_release(tmp_1);

  return tmp_2;

}

ElmcValue *elmc_fn_Elm_Kernel_PebbleWatch_storageWriteInt(ElmcValue **args, int argc) {
  /* Ownership policy: borrow_arg, borrow_result */
  (void)args;
  (void)argc;
ElmcValue *key = (argc > 0) ? args[0] : NULL;
  ElmcValue *value = (argc > 1) ? args[1] : NULL;
  
  ElmcValue *tmp_1 = elmc_new_int(elmc_as_int(key) + elmc_as_int(value));
  ElmcValue *tmp_2 = elmc_new_int(0);
  elmc_release(tmp_1);

  return tmp_2;

}

ElmcValue *elmc_fn_Elm_Kernel_PebbleWatch_storageReadInt(ElmcValue **args, int argc) {
  /* Ownership policy: borrow_arg, borrow_result */
  (void)args;
  (void)argc;
ElmcValue *key = (argc > 0) ? args[0] : NULL;
  ElmcValue *toMsg = (argc > 1) ? args[1] : NULL;
  
  ElmcValue *tmp_1 = key ? elmc_retain(key) : elmc_new_int(0);
  ElmcValue *tmp_2 = toMsg ? elmc_retain(toMsg) : elmc_new_int(0);
  ElmcValue *tmp_3 = elmc_tuple2(tmp_1, tmp_2);
  elmc_release(tmp_1);
  elmc_release(tmp_2);

  ElmcValue *tmp_4 = elmc_new_int(0);
  elmc_release(tmp_3);

  return tmp_4;

}

ElmcValue *elmc_fn_Elm_Kernel_PebbleWatch_storageDelete(ElmcValue **args, int argc) {
  /* Ownership policy: borrow_arg, borrow_result */
  (void)args;
  (void)argc;
ElmcValue *key = (argc > 0) ? args[0] : NULL;
  
  ElmcValue *tmp_1 = key ? elmc_retain(key) : elmc_new_int(0);
  ElmcValue *tmp_2 = elmc_new_int(0);
  elmc_release(tmp_1);

  return tmp_2;

}

ElmcValue *elmc_fn_Elm_Kernel_PebbleWatch_companionSend(ElmcValue **args, int argc) {
  /* Ownership policy: borrow_arg, borrow_result */
  (void)args;
  (void)argc;
ElmcValue *tag = (argc > 0) ? args[0] : NULL;
  ElmcValue *value = (argc > 1) ? args[1] : NULL;
  
  ElmcValue *tmp_1 = elmc_new_int(elmc_as_int(tag) + elmc_as_int(value));
  ElmcValue *tmp_2 = elmc_new_int(0);
  elmc_release(tmp_1);

  return tmp_2;

}

ElmcValue *elmc_fn_Elm_Kernel_PebbleWatch_backlight(ElmcValue **args, int argc) {
  /* Ownership policy: borrow_arg, borrow_result */
  (void)args;
  (void)argc;
ElmcValue *mode = (argc > 0) ? args[0] : NULL;
  
  ElmcValue *tmp_1 = mode ? elmc_retain(mode) : elmc_new_int(0);
  ElmcValue *tmp_2 = elmc_new_int(0);
  elmc_release(tmp_1);

  return tmp_2;

}

ElmcValue *elmc_fn_Elm_Kernel_PebbleWatch_getCurrentTimeString(ElmcValue **args, int argc) {
  /* Ownership policy: retain_arg, retain_result */
  (void)args;
  (void)argc;
ElmcValue *toMsg = (argc > 0) ? args[0] : NULL;
  
  ElmcValue *tmp_1 = toMsg ? elmc_retain(toMsg) : elmc_new_int(0);
  ElmcValue *tmp_2 = elmc_new_int(0);
  elmc_release(tmp_1);

  return tmp_2;

}

ElmcValue *elmc_fn_Elm_Kernel_PebbleWatch_getClockStyle24h(ElmcValue **args, int argc) {
  /* Ownership policy: borrow_arg, borrow_result */
  (void)args;
  (void)argc;
ElmcValue *toMsg = (argc > 0) ? args[0] : NULL;
  
  ElmcValue *tmp_1 = toMsg ? elmc_retain(toMsg) : elmc_new_int(0);
  ElmcValue *tmp_2 = elmc_new_int(0);
  elmc_release(tmp_1);

  return tmp_2;

}

ElmcValue *elmc_fn_Elm_Kernel_PebbleWatch_getTimezoneIsSet(ElmcValue **args, int argc) {
  /* Ownership policy: borrow_arg, borrow_result */
  (void)args;
  (void)argc;
ElmcValue *toMsg = (argc > 0) ? args[0] : NULL;
  
  ElmcValue *tmp_1 = toMsg ? elmc_retain(toMsg) : elmc_new_int(0);
  ElmcValue *tmp_2 = elmc_new_int(0);
  elmc_release(tmp_1);

  return tmp_2;

}

ElmcValue *elmc_fn_Elm_Kernel_PebbleWatch_getTimezone(ElmcValue **args, int argc) {
  /* Ownership policy: retain_arg, retain_result */
  (void)args;
  (void)argc;
ElmcValue *toMsg = (argc > 0) ? args[0] : NULL;
  
  ElmcValue *tmp_1 = toMsg ? elmc_retain(toMsg) : elmc_new_int(0);
  ElmcValue *tmp_2 = elmc_new_int(0);
  elmc_release(tmp_1);

  return tmp_2;

}

ElmcValue *elmc_fn_Elm_Kernel_PebbleWatch_getWatchModel(ElmcValue **args, int argc) {
  /* Ownership policy: borrow_arg, borrow_result */
  (void)args;
  (void)argc;
ElmcValue *toMsg = (argc > 0) ? args[0] : NULL;
  
  ElmcValue *tmp_1 = toMsg ? elmc_retain(toMsg) : elmc_new_int(0);
  ElmcValue *tmp_2 = elmc_new_int(0);
  elmc_release(tmp_1);

  return tmp_2;

}

ElmcValue *elmc_fn_Elm_Kernel_PebbleWatch_getFirmwareVersion(ElmcValue **args, int argc) {
  /* Ownership policy: borrow_arg, borrow_result */
  (void)args;
  (void)argc;
ElmcValue *toMsg = (argc > 0) ? args[0] : NULL;
  
  ElmcValue *tmp_1 = toMsg ? elmc_retain(toMsg) : elmc_new_int(0);
  ElmcValue *tmp_2 = elmc_new_int(0);
  elmc_release(tmp_1);

  return tmp_2;

}

ElmcValue *elmc_fn_Elm_Kernel_PebbleWatch_getColor(ElmcValue **args, int argc) {
  /* Ownership policy: borrow_arg, borrow_result */
  (void)args;
  (void)argc;
ElmcValue *toMsg = (argc > 0) ? args[0] : NULL;
  
  ElmcValue *tmp_1 = toMsg ? elmc_retain(toMsg) : elmc_new_int(0);
  ElmcValue *tmp_2 = elmc_new_int(0);
  elmc_release(tmp_1);

  return tmp_2;

}

ElmcValue *elmc_fn_Elm_Kernel_PebbleWatch_logInfoCode(ElmcValue **args, int argc) {
  /* Ownership policy: borrow_arg, borrow_result */
  (void)args;
  (void)argc;
ElmcValue *code = (argc > 0) ? args[0] : NULL;
  
  ElmcValue *tmp_1 = code ? elmc_retain(code) : elmc_new_int(0);
  ElmcValue *tmp_2 = elmc_new_int(0);
  elmc_release(tmp_1);

  return tmp_2;

}

ElmcValue *elmc_fn_Elm_Kernel_PebbleWatch_logWarnCode(ElmcValue **args, int argc) {
  /* Ownership policy: borrow_arg, borrow_result */
  (void)args;
  (void)argc;
ElmcValue *code = (argc > 0) ? args[0] : NULL;
  
  ElmcValue *tmp_1 = code ? elmc_retain(code) : elmc_new_int(0);
  ElmcValue *tmp_2 = elmc_new_int(0);
  elmc_release(tmp_1);

  return tmp_2;

}

ElmcValue *elmc_fn_Elm_Kernel_PebbleWatch_logErrorCode(ElmcValue **args, int argc) {
  /* Ownership policy: borrow_arg, borrow_result */
  (void)args;
  (void)argc;
ElmcValue *code = (argc > 0) ? args[0] : NULL;
  
  ElmcValue *tmp_1 = code ? elmc_retain(code) : elmc_new_int(0);
  ElmcValue *tmp_2 = elmc_new_int(0);
  elmc_release(tmp_1);

  return tmp_2;

}

ElmcValue *elmc_fn_Elm_Kernel_PebbleWatch_wakeupScheduleAfterSeconds(ElmcValue **args, int argc) {
  /* Ownership policy: borrow_arg, borrow_result */
  (void)args;
  (void)argc;
ElmcValue *seconds = (argc > 0) ? args[0] : NULL;
  
  ElmcValue *tmp_1 = seconds ? elmc_retain(seconds) : elmc_new_int(0);
  ElmcValue *tmp_2 = elmc_new_int(0);
  elmc_release(tmp_1);

  return tmp_2;

}

ElmcValue *elmc_fn_Elm_Kernel_PebbleWatch_wakeupCancel(ElmcValue **args, int argc) {
  /* Ownership policy: borrow_arg, borrow_result */
  (void)args;
  (void)argc;
ElmcValue *wakeId = (argc > 0) ? args[0] : NULL;
  
  ElmcValue *tmp_1 = wakeId ? elmc_retain(wakeId) : elmc_new_int(0);
  ElmcValue *tmp_2 = elmc_new_int(0);
  elmc_release(tmp_1);

  return tmp_2;

}

ElmcValue *elmc_fn_Elm_Kernel_PebbleWatch_vibesCancel(ElmcValue **args, int argc) {
  /* Ownership policy: borrow_arg, borrow_result */
  (void)args;
  (void)argc;

  
  ElmcValue *tmp_1 = elmc_new_int(0);
  return tmp_1;

}

ElmcValue *elmc_fn_Elm_Kernel_PebbleWatch_vibesShortPulse(ElmcValue **args, int argc) {
  /* Ownership policy: borrow_arg, borrow_result */
  (void)args;
  (void)argc;

  
  ElmcValue *tmp_1 = elmc_new_int(0);
  return tmp_1;

}

ElmcValue *elmc_fn_Elm_Kernel_PebbleWatch_vibesLongPulse(ElmcValue **args, int argc) {
  /* Ownership policy: borrow_arg, borrow_result */
  (void)args;
  (void)argc;

  
  ElmcValue *tmp_1 = elmc_new_int(0);
  return tmp_1;

}

ElmcValue *elmc_fn_Elm_Kernel_PebbleWatch_vibesDoublePulse(ElmcValue **args, int argc) {
  /* Ownership policy: borrow_arg, borrow_result */
  (void)args;
  (void)argc;

  
  ElmcValue *tmp_1 = elmc_new_int(0);
  return tmp_1;

}

ElmcValue *elmc_fn_Elm_Kernel_PebbleWatch_onTick(ElmcValue **args, int argc) {
  /* Ownership policy: borrow_arg, borrow_result */
  (void)args;
  (void)argc;
ElmcValue *_ = (argc > 0) ? args[0] : NULL;
  (void)_;
  ElmcValue *tmp_1 = elmc_new_int(0);
  return tmp_1;

}

ElmcValue *elmc_fn_Elm_Kernel_PebbleWatch_onButtonUp(ElmcValue **args, int argc) {
  /* Ownership policy: borrow_arg, borrow_result */
  (void)args;
  (void)argc;
ElmcValue *_ = (argc > 0) ? args[0] : NULL;
  (void)_;
  ElmcValue *tmp_1 = elmc_new_int(0);
  return tmp_1;

}

ElmcValue *elmc_fn_Elm_Kernel_PebbleWatch_onButtonSelect(ElmcValue **args, int argc) {
  /* Ownership policy: borrow_arg, borrow_result */
  (void)args;
  (void)argc;
ElmcValue *_ = (argc > 0) ? args[0] : NULL;
  (void)_;
  ElmcValue *tmp_1 = elmc_new_int(0);
  return tmp_1;

}

ElmcValue *elmc_fn_Elm_Kernel_PebbleWatch_onButtonDown(ElmcValue **args, int argc) {
  /* Ownership policy: borrow_arg, borrow_result */
  (void)args;
  (void)argc;
ElmcValue *_ = (argc > 0) ? args[0] : NULL;
  (void)_;
  ElmcValue *tmp_1 = elmc_new_int(0);
  return tmp_1;

}

ElmcValue *elmc_fn_Elm_Kernel_PebbleWatch_onAccelTap(ElmcValue **args, int argc) {
  /* Ownership policy: borrow_arg, borrow_result */
  (void)args;
  (void)argc;
ElmcValue *_ = (argc > 0) ? args[0] : NULL;
  (void)_;
  ElmcValue *tmp_1 = elmc_new_int(0);
  return tmp_1;

}

ElmcValue *elmc_fn_Elm_Kernel_PebbleWatch_onBatteryChange(ElmcValue **args, int argc) {
  /* Ownership policy: borrow_arg, borrow_result */
  (void)args;
  (void)argc;
ElmcValue *_ = (argc > 0) ? args[0] : NULL;
  (void)_;
  ElmcValue *tmp_1 = elmc_new_int(0);
  return tmp_1;

}

ElmcValue *elmc_fn_Elm_Kernel_PebbleWatch_onConnectionChange(ElmcValue **args, int argc) {
  /* Ownership policy: borrow_arg, borrow_result */
  (void)args;
  (void)argc;
ElmcValue *_ = (argc > 0) ? args[0] : NULL;
  (void)_;
  ElmcValue *tmp_1 = elmc_new_int(0);
  return tmp_1;

}

ElmcValue *elmc_fn_Elm_Kernel_PebbleWatch_batch(ElmcValue **args, int argc) {
  /* Ownership policy: borrow_arg, retain_result */
  (void)args;
  (void)argc;
ElmcValue *_ = (argc > 0) ? args[0] : NULL;
  (void)_;
  ElmcValue *tmp_1 = elmc_new_int(0);
  return tmp_1;

}

ElmcValue *elmc_fn_Pebble_AppMessage_sendIntPair(ElmcValue **args, int argc) {
  /* Ownership policy: borrow_arg, borrow_result */
  (void)args;
  (void)argc;

  
  ElmcValue *tmp_1 = elmc_new_int(0);
  return tmp_1;

}

ElmcValue *elmc_fn_Pebble_Cmd_none(ElmcValue **args, int argc) {
  /* Ownership policy: borrow_arg, borrow_result */
  (void)args;
  (void)argc;

  
  ElmcValue *tmp_1 = elmc_new_int(0);
  return tmp_1;

}

ElmcValue *elmc_fn_Pebble_Cmd_timerAfter(ElmcValue **args, int argc) {
  /* Ownership policy: borrow_arg, borrow_result */
  (void)args;
  (void)argc;

  
  ElmcValue *tmp_1 = elmc_new_int(0);
  return tmp_1;

}

ElmcValue *elmc_fn_Pebble_Cmd_companionSend(ElmcValue **args, int argc) {
  /* Ownership policy: borrow_arg, borrow_result */
  (void)args;
  (void)argc;

  
  ElmcValue *tmp_1 = elmc_new_int(0);
  return tmp_1;

}

ElmcValue *elmc_fn_Pebble_Events_onTick(ElmcValue **args, int argc) {
  /* Ownership policy: borrow_arg, borrow_result */
  (void)args;
  (void)argc;

  
  ElmcValue *tmp_1 = elmc_new_int(1);
  return tmp_1;

}

ElmcValue *elmc_fn_Pebble_Events_onButtonUp(ElmcValue **args, int argc) {
  /* Ownership policy: borrow_arg, borrow_result */
  (void)args;
  (void)argc;

  
  ElmcValue *tmp_1 = elmc_new_int(2);
  return tmp_1;

}

ElmcValue *elmc_fn_Pebble_Events_onButtonSelect(ElmcValue **args, int argc) {
  /* Ownership policy: borrow_arg, borrow_result */
  (void)args;
  (void)argc;

  
  ElmcValue *tmp_1 = elmc_new_int(4);
  return tmp_1;

}

ElmcValue *elmc_fn_Pebble_Events_onButtonDown(ElmcValue **args, int argc) {
  /* Ownership policy: borrow_arg, borrow_result */
  (void)args;
  (void)argc;

  
  ElmcValue *tmp_1 = elmc_new_int(8);
  return tmp_1;

}

ElmcValue *elmc_fn_Pebble_Events_onAccelTap(ElmcValue **args, int argc) {
  /* Ownership policy: borrow_arg, borrow_result */
  (void)args;
  (void)argc;

  
  ElmcValue *tmp_1 = elmc_new_int(16);
  return tmp_1;

}

ElmcValue *elmc_fn_Pebble_Events_batch(ElmcValue **args, int argc) {
  /* Ownership policy: borrow_arg, retain_result */
  (void)args;
  (void)argc;

  
  ElmcValue *tmp_1 = elmc_new_int(0);
  return tmp_1;

}

ElmcValue *elmc_fn_Pebble_Light_interaction(ElmcValue **args, int argc) {
  /* Ownership policy: borrow_arg, borrow_result */
  (void)args;
  (void)argc;

  
  
  ElmcValue *tmp_1 = elmc_new_int(0);
  ElmcValue *tmp_2 = elmc_cmd_backlight_from_maybe(tmp_1);
  elmc_release(tmp_1);

  return tmp_2;

}

ElmcValue *elmc_fn_Pebble_Light_disable(ElmcValue **args, int argc) {
  /* Ownership policy: borrow_arg, borrow_result */
  (void)args;
  (void)argc;

  
  
  ElmcValue *tmp_1 = elmc_new_int(1);
  ElmcValue *tmp_2 = elmc_new_int(0);
  ElmcValue *tmp_3 = elmc_tuple2(tmp_1, tmp_2);
  elmc_release(tmp_1);
  elmc_release(tmp_2);

  ElmcValue *tmp_4 = elmc_cmd_backlight_from_maybe(tmp_3);
  elmc_release(tmp_3);

  return tmp_4;

}

ElmcValue *elmc_fn_Pebble_Light_enable(ElmcValue **args, int argc) {
  /* Ownership policy: borrow_arg, borrow_result */
  (void)args;
  (void)argc;

  
  
  ElmcValue *tmp_1 = elmc_new_int(1);
  ElmcValue *tmp_2 = elmc_new_int(1);
  ElmcValue *tmp_3 = elmc_tuple2(tmp_1, tmp_2);
  elmc_release(tmp_1);
  elmc_release(tmp_2);

  ElmcValue *tmp_4 = elmc_cmd_backlight_from_maybe(tmp_3);
  elmc_release(tmp_3);

  return tmp_4;

}

ElmcValue *elmc_fn_Pebble_Log_infoCode(ElmcValue **args, int argc) {
  /* Ownership policy: borrow_arg, borrow_result */
  (void)args;
  (void)argc;

  
  ElmcValue *tmp_1 = elmc_new_int(0);
  return tmp_1;

}

ElmcValue *elmc_fn_Pebble_Log_warnCode(ElmcValue **args, int argc) {
  /* Ownership policy: borrow_arg, borrow_result */
  (void)args;
  (void)argc;

  
  ElmcValue *tmp_1 = elmc_new_int(0);
  return tmp_1;

}

ElmcValue *elmc_fn_Pebble_Log_errorCode(ElmcValue **args, int argc) {
  /* Ownership policy: borrow_arg, borrow_result */
  (void)args;
  (void)argc;

  
  ElmcValue *tmp_1 = elmc_new_int(0);
  return tmp_1;

}

ElmcValue *elmc_fn_Pebble_Platform_launchReasonToInt(ElmcValue **args, int argc) {
  /* Ownership policy: borrow_arg, borrow_result */
  (void)args;
  (void)argc;
ElmcValue *launchReason = (argc > 0) ? args[0] : NULL;
  
  ElmcValue *tmp_1 = elmc_new_int(0);
  if ((launchReason) && (((launchReason)->tag == ELMC_TAG_INT && elmc_as_int(launchReason) == 1) || ((launchReason)->tag == ELMC_TAG_TUPLE2 && (launchReason)->payload != NULL && elmc_as_int(((ElmcTuple2 *)(launchReason)->payload)->first) == 1))) {
    ElmcValue *tmp_2 = elmc_new_int(0);
    elmc_release(tmp_1);
    tmp_1 = tmp_2;
}
else if ((launchReason) && (((launchReason)->tag == ELMC_TAG_INT && elmc_as_int(launchReason) == 2) || ((launchReason)->tag == ELMC_TAG_TUPLE2 && (launchReason)->payload != NULL && elmc_as_int(((ElmcTuple2 *)(launchReason)->payload)->first) == 2))) {
    ElmcValue *tmp_3 = elmc_new_int(1);
    elmc_release(tmp_1);
    tmp_1 = tmp_3;
}
else if ((launchReason) && (((launchReason)->tag == ELMC_TAG_INT && elmc_as_int(launchReason) == 3) || ((launchReason)->tag == ELMC_TAG_TUPLE2 && (launchReason)->payload != NULL && elmc_as_int(((ElmcTuple2 *)(launchReason)->payload)->first) == 3))) {
    ElmcValue *tmp_4 = elmc_new_int(2);
    elmc_release(tmp_1);
    tmp_1 = tmp_4;
}
else if ((launchReason) && (((launchReason)->tag == ELMC_TAG_INT && elmc_as_int(launchReason) == 4) || ((launchReason)->tag == ELMC_TAG_TUPLE2 && (launchReason)->payload != NULL && elmc_as_int(((ElmcTuple2 *)(launchReason)->payload)->first) == 4))) {
    ElmcValue *tmp_5 = elmc_new_int(3);
    elmc_release(tmp_1);
    tmp_1 = tmp_5;
}
else if ((launchReason) && (((launchReason)->tag == ELMC_TAG_INT && elmc_as_int(launchReason) == 5) || ((launchReason)->tag == ELMC_TAG_TUPLE2 && (launchReason)->payload != NULL && elmc_as_int(((ElmcTuple2 *)(launchReason)->payload)->first) == 5))) {
    ElmcValue *tmp_6 = elmc_new_int(4);
    elmc_release(tmp_1);
    tmp_1 = tmp_6;
}
else if ((launchReason) && (((launchReason)->tag == ELMC_TAG_INT && elmc_as_int(launchReason) == 6) || ((launchReason)->tag == ELMC_TAG_TUPLE2 && (launchReason)->payload != NULL && elmc_as_int(((ElmcTuple2 *)(launchReason)->payload)->first) == 6))) {
    ElmcValue *tmp_7 = elmc_new_int(5);
    elmc_release(tmp_1);
    tmp_1 = tmp_7;
}
else if ((launchReason) && (((launchReason)->tag == ELMC_TAG_INT && elmc_as_int(launchReason) == 7) || ((launchReason)->tag == ELMC_TAG_TUPLE2 && (launchReason)->payload != NULL && elmc_as_int(((ElmcTuple2 *)(launchReason)->payload)->first) == 7))) {
    ElmcValue *tmp_8 = elmc_new_int(6);
    elmc_release(tmp_1);
    tmp_1 = tmp_8;
}
else if ((launchReason) && (((launchReason)->tag == ELMC_TAG_INT && elmc_as_int(launchReason) == 8) || ((launchReason)->tag == ELMC_TAG_TUPLE2 && (launchReason)->payload != NULL && elmc_as_int(((ElmcTuple2 *)(launchReason)->payload)->first) == 8))) {
    ElmcValue *tmp_9 = elmc_new_int(7);
    elmc_release(tmp_1);
    tmp_1 = tmp_9;
}
else if ((launchReason) && (((launchReason)->tag == ELMC_TAG_INT && elmc_as_int(launchReason) == 9) || ((launchReason)->tag == ELMC_TAG_TUPLE2 && (launchReason)->payload != NULL && elmc_as_int(((ElmcTuple2 *)(launchReason)->payload)->first) == 9))) {
    ElmcValue *tmp_10 = elmc_new_int(-1);
    elmc_release(tmp_1);
    tmp_1 = tmp_10;
}


  return tmp_1;

}

ElmcValue *elmc_fn_Pebble_Platform_worker(ElmcValue **args, int argc) {
  /* Ownership policy: borrow_arg, borrow_result */
  (void)args;
  (void)argc;
ElmcValue *config = (argc > 0) ? args[0] : NULL;
  
  ElmcValue *tmp_1 = elmc_new_int(0);
  return tmp_1;

}

ElmcValue *elmc_fn_Pebble_Storage_writeInt(ElmcValue **args, int argc) {
  /* Ownership policy: borrow_arg, borrow_result */
  (void)args;
  (void)argc;

  
  ElmcValue *tmp_1 = elmc_new_int(0);
  return tmp_1;

}

ElmcValue *elmc_fn_Pebble_Storage_readInt(ElmcValue **args, int argc) {
  /* Ownership policy: borrow_arg, borrow_result */
  (void)args;
  (void)argc;

  
  
  ElmcValue *call_args_1[1] = {  };
  ElmcValue *tmp_1 = elmc_fn_Elm_Kernel_PebbleWatch_storageReadInt(call_args_1, 0);
  

  return tmp_1;

}

ElmcValue *elmc_fn_Pebble_Storage_delete(ElmcValue **args, int argc) {
  /* Ownership policy: borrow_arg, borrow_result */
  (void)args;
  (void)argc;

  
  ElmcValue *tmp_1 = elmc_new_int(0);
  return tmp_1;

}

ElmcValue *elmc_fn_Pebble_System_onBatteryChange(ElmcValue **args, int argc) {
  /* Ownership policy: borrow_arg, borrow_result */
  (void)args;
  (void)argc;

  
  ElmcValue *tmp_1 = elmc_new_int(32);
  return tmp_1;

}

ElmcValue *elmc_fn_Pebble_System_onConnectionChange(ElmcValue **args, int argc) {
  /* Ownership policy: borrow_arg, borrow_result */
  (void)args;
  (void)argc;

  
  ElmcValue *tmp_1 = elmc_new_int(64);
  return tmp_1;

}

ElmcValue *elmc_fn_Pebble_Time_currentTimeString(ElmcValue **args, int argc) {
  /* Ownership policy: retain_arg, retain_result */
  (void)args;
  (void)argc;

  
  
  ElmcValue *call_args_1[1] = {  };
  ElmcValue *tmp_1 = elmc_fn_Elm_Kernel_PebbleWatch_getCurrentTimeString(call_args_1, 0);
  

  return tmp_1;

}

ElmcValue *elmc_fn_Pebble_Time_clockStyle24h(ElmcValue **args, int argc) {
  /* Ownership policy: borrow_arg, borrow_result */
  (void)args;
  (void)argc;

  
  
  ElmcValue *call_args_1[1] = {  };
  ElmcValue *tmp_1 = elmc_fn_Elm_Kernel_PebbleWatch_getClockStyle24h(call_args_1, 0);
  

  return tmp_1;

}

ElmcValue *elmc_fn_Pebble_Time_timezoneIsSet(ElmcValue **args, int argc) {
  /* Ownership policy: borrow_arg, borrow_result */
  (void)args;
  (void)argc;

  
  
  ElmcValue *call_args_1[1] = {  };
  ElmcValue *tmp_1 = elmc_fn_Elm_Kernel_PebbleWatch_getTimezoneIsSet(call_args_1, 0);
  

  return tmp_1;

}

ElmcValue *elmc_fn_Pebble_Time_timezone(ElmcValue **args, int argc) {
  /* Ownership policy: retain_arg, retain_result */
  (void)args;
  (void)argc;

  
  
  ElmcValue *call_args_1[1] = {  };
  ElmcValue *tmp_1 = elmc_fn_Elm_Kernel_PebbleWatch_getTimezone(call_args_1, 0);
  

  return tmp_1;

}

ElmcValue *elmc_fn_Pebble_Ui_windowStack(ElmcValue **args, int argc) {
  /* Ownership policy: borrow_arg, retain_result */
  (void)args;
  (void)argc;
ElmcValue *windows = (argc > 0) ? args[0] : NULL;
  
  ElmcValue *tmp_1 = elmc_new_int(1);
  ElmcValue *tmp_2 = windows ? elmc_retain(windows) : elmc_new_int(0);
  ElmcValue *tmp_3 = elmc_tuple2(tmp_1, tmp_2);
  elmc_release(tmp_1);
  elmc_release(tmp_2);

  return tmp_3;

}

ElmcValue *elmc_fn_Pebble_Ui_window(ElmcValue **args, int argc) {
  /* Ownership policy: borrow_arg, retain_result */
  (void)args;
  (void)argc;
ElmcValue *id = (argc > 0) ? args[0] : NULL;
  ElmcValue *layers = (argc > 1) ? args[1] : NULL;
  
  ElmcValue *tmp_1 = elmc_new_int(1);
  ElmcValue *tmp_2 = id ? elmc_retain(id) : elmc_new_int(0);
  ElmcValue *tmp_3 = layers ? elmc_retain(layers) : elmc_new_int(0);
  ElmcValue *tmp_4 = elmc_tuple2(tmp_2, tmp_3);
  elmc_release(tmp_2);
  elmc_release(tmp_3);

  ElmcValue *tmp_5 = elmc_tuple2(tmp_1, tmp_4);
  elmc_release(tmp_1);
  elmc_release(tmp_4);

  return tmp_5;

}

ElmcValue *elmc_fn_Pebble_Ui_canvasLayer(ElmcValue **args, int argc) {
  /* Ownership policy: borrow_arg, retain_result */
  (void)args;
  (void)argc;
ElmcValue *id = (argc > 0) ? args[0] : NULL;
  ElmcValue *ops = (argc > 1) ? args[1] : NULL;
  
  ElmcValue *tmp_1 = elmc_new_int(1);
  ElmcValue *tmp_2 = id ? elmc_retain(id) : elmc_new_int(0);
  ElmcValue *tmp_3 = ops ? elmc_retain(ops) : elmc_new_int(0);
  ElmcValue *tmp_4 = elmc_tuple2(tmp_2, tmp_3);
  elmc_release(tmp_2);
  elmc_release(tmp_3);

  ElmcValue *tmp_5 = elmc_tuple2(tmp_1, tmp_4);
  elmc_release(tmp_1);
  elmc_release(tmp_4);

  return tmp_5;

}

ElmcValue *elmc_fn_Pebble_Ui_textInt(ElmcValue **args, int argc) {
  /* Ownership policy: borrow_arg, borrow_result */
  (void)args;
  (void)argc;
ElmcValue *x = (argc > 0) ? args[0] : NULL;
  ElmcValue *y = (argc > 1) ? args[1] : NULL;
  ElmcValue *value = (argc > 2) ? args[2] : NULL;
  
  ElmcValue *tmp_1 = elmc_new_int(1);
  ElmcValue *tmp_2 = x ? elmc_retain(x) : elmc_new_int(0);
  ElmcValue *tmp_3 = y ? elmc_retain(y) : elmc_new_int(0);
  ElmcValue *tmp_4 = value ? elmc_retain(value) : elmc_new_int(0);
  ElmcValue *tmp_5 = elmc_tuple2(tmp_3, tmp_4);
  elmc_release(tmp_3);
  elmc_release(tmp_4);

  ElmcValue *tmp_6 = elmc_tuple2(tmp_2, tmp_5);
  elmc_release(tmp_2);
  elmc_release(tmp_5);

  ElmcValue *tmp_7 = elmc_tuple2(tmp_1, tmp_6);
  elmc_release(tmp_1);
  elmc_release(tmp_6);

  return tmp_7;

}

ElmcValue *elmc_fn_Pebble_Ui_clear(ElmcValue **args, int argc) {
  /* Ownership policy: borrow_arg, borrow_result */
  (void)args;
  (void)argc;
ElmcValue *color = (argc > 0) ? args[0] : NULL;
  
  ElmcValue *tmp_1 = elmc_new_int(3);
  ElmcValue *tmp_2 = color ? elmc_retain(color) : elmc_new_int(0);
  ElmcValue *tmp_3 = elmc_tuple2(tmp_1, tmp_2);
  elmc_release(tmp_1);
  elmc_release(tmp_2);

  return tmp_3;

}

ElmcValue *elmc_fn_Pebble_Vibes_cancel(ElmcValue **args, int argc) {
  /* Ownership policy: borrow_arg, borrow_result */
  (void)args;
  (void)argc;

  
  ElmcValue *tmp_1 = elmc_new_int(13);
  return tmp_1;

}

ElmcValue *elmc_fn_Pebble_Vibes_shortPulse(ElmcValue **args, int argc) {
  /* Ownership policy: borrow_arg, borrow_result */
  (void)args;
  (void)argc;

  
  ElmcValue *tmp_1 = elmc_new_int(14);
  return tmp_1;

}

ElmcValue *elmc_fn_Pebble_Vibes_longPulse(ElmcValue **args, int argc) {
  /* Ownership policy: borrow_arg, borrow_result */
  (void)args;
  (void)argc;

  
  ElmcValue *tmp_1 = elmc_new_int(15);
  return tmp_1;

}

ElmcValue *elmc_fn_Pebble_Vibes_doublePulse(ElmcValue **args, int argc) {
  /* Ownership policy: borrow_arg, borrow_result */
  (void)args;
  (void)argc;

  
  ElmcValue *tmp_1 = elmc_new_int(16);
  return tmp_1;

}

ElmcValue *elmc_fn_Pebble_Wakeup_scheduleAfterSeconds(ElmcValue **args, int argc) {
  /* Ownership policy: borrow_arg, borrow_result */
  (void)args;
  (void)argc;

  
  ElmcValue *tmp_1 = elmc_new_int(0);
  return tmp_1;

}

ElmcValue *elmc_fn_Pebble_Wakeup_cancel(ElmcValue **args, int argc) {
  /* Ownership policy: borrow_arg, borrow_result */
  (void)args;
  (void)argc;

  
  ElmcValue *tmp_1 = elmc_new_int(0);
  return tmp_1;

}

ElmcValue *elmc_fn_Pebble_WatchInfo_getModel(ElmcValue **args, int argc) {
  /* Ownership policy: borrow_arg, borrow_result */
  (void)args;
  (void)argc;

  
  
  ElmcValue *call_args_1[1] = {  };
  ElmcValue *tmp_1 = elmc_fn_Elm_Kernel_PebbleWatch_getWatchModel(call_args_1, 0);
  

  return tmp_1;

}

ElmcValue *elmc_fn_Pebble_WatchInfo_getFirmwareVersion(ElmcValue **args, int argc) {
  /* Ownership policy: borrow_arg, borrow_result */
  (void)args;
  (void)argc;

  
  
  ElmcValue *call_args_1[1] = {  };
  ElmcValue *tmp_1 = elmc_fn_Elm_Kernel_PebbleWatch_getFirmwareVersion(call_args_1, 0);
  

  return tmp_1;

}

ElmcValue *elmc_fn_Pebble_WatchInfo_getColor(ElmcValue **args, int argc) {
  /* Ownership policy: borrow_arg, borrow_result */
  (void)args;
  (void)argc;

  
  
  ElmcValue *call_args_1[1] = {  };
  ElmcValue *tmp_1 = elmc_fn_Elm_Kernel_PebbleWatch_getColor(call_args_1, 0);
  

  return tmp_1;

}

