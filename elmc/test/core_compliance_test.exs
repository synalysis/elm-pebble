defmodule Elmc.CoreComplianceTest do
  use ExUnit.Case

  @required_functions [
    "CoreCompliance_foldSum",
    "CoreCompliance_maybeInc",
    "CoreCompliance_resultInc",
    "CoreCompliance_nestedResult",
    "CoreCompliance_second",
    "CoreCompliance_first",
    "CoreCompliance_stringLen",
    "CoreCompliance_charFromCode",
    "CoreCompliance_charCodeRoundtrip",
    "CoreCompliance_fundamentalsMix",
    "CoreCompliance_bitwiseMix",
    "CoreCompliance_bitwiseExtras",
    "CoreCompliance_modByNeg",
    "CoreCompliance_debugEcho",
    "CoreCompliance_dictLookupOne",
    "CoreCompliance_dictFromListThenOverwriteSize",
    "CoreCompliance_dictFromListThenOverwriteGet",
    "CoreCompliance_dictFromListDuplicateSize",
    "CoreCompliance_dictFromListDuplicateGet",
    "CoreCompliance_dictHasOne",
    "CoreCompliance_dictSizeTwo",
    "CoreCompliance_dictOverwriteSize",
    "CoreCompliance_dictOverwriteGet",
    "CoreCompliance_setHasThree",
    "CoreCompliance_setFromListDuplicateSize",
    "CoreCompliance_setFromListDuplicateHasTwo",
    "CoreCompliance_setSizeAfterInsert",
    "CoreCompliance_setInsertDuplicateSize",
    "CoreCompliance_arrayLengthFromList",
    "CoreCompliance_arrayGetHit",
    "CoreCompliance_arrayGetMiss",
    "CoreCompliance_arrayGetNegative",
    "CoreCompliance_arraySetInRangeGet",
    "CoreCompliance_arraySetLastGet",
    "CoreCompliance_arraySetNegativeLength",
    "CoreCompliance_arraySetOutOfRangeLength",
    "CoreCompliance_arrayPushLength",
    "CoreCompliance_arrayPushTwiceLength",
    "CoreCompliance_arrayPushTwiceLastGet",
    "CoreCompliance_arraySetThenPushLastGet",
    "CoreCompliance_arraySetThenSetGet",
    "CoreCompliance_arrayPushThenSetFirstGet",
    "CoreCompliance_taskSucceedInt",
    "CoreCompliance_taskFailInt",
    "CoreCompliance_taskSucceedArg",
    "CoreCompliance_taskFailArg",
    "CoreCompliance_taskSucceedNested",
    "CoreCompliance_taskFailNested",
    "CoreCompliance_processSpawnPidFromSucceed",
    "CoreCompliance_processSpawnPidFromFail",
    "CoreCompliance_processSleepOk",
    "CoreCompliance_processKillOk",
    "CoreCompliance_stringAppendLength",
    "CoreCompliance_stringEmptyCheck",
    "CoreCompliance_tuplePairFirst",
    "CoreCompliance_tupleCase",
    "CoreCompliance_nestedTupleSum",
    "CoreCompliance_branchTupleOut",
    "CoreCompliance_branchTupleOutNested",
    "CoreCompliance_constructorLiteralCase",
    "CoreCompliance_constructorTripleCase"
  ]

  test "elm/core representative functions are emitted in generated C" do
    project_dir = Path.expand("fixtures/simple_project", __DIR__)
    out_dir = Path.expand("tmp/compliance", __DIR__)
    File.rm_rf!(out_dir)

    assert {:ok, _} = Elmc.compile(project_dir, %{out_dir: out_dir, strip_dead_code: false})
    generated_c = File.read!(Path.join(out_dir, "c/elmc_generated.c"))

    Enum.each(@required_functions, fn fn_name ->
      assert String.contains?(generated_c, "elmc_fn_#{fn_name}")
    end)
  end

  test "differential sanity: fixture compiles with elm make" do
    project_dir = Path.expand("fixtures/simple_project", __DIR__)

    {output, exit_code} =
      System.cmd("bash", ["-lc", "elm make src/Main.elm --output=/tmp/elmc-diff.js"],
        cd: project_dir,
        stderr_to_stdout: true
      )

    assert exit_code == 0, output
  end

  test "core intrinsic behavior sanity via generated C harness" do
    cc = System.find_executable("cc")
    if is_nil(cc), do: flunk("cc not available for core compliance C harness")

    project_dir = Path.expand("fixtures/simple_project", __DIR__)
    out_dir = Path.expand("tmp/compliance_behavior", __DIR__)
    File.rm_rf!(out_dir)
    assert {:ok, _} = Elmc.compile(project_dir, %{out_dir: out_dir, strip_dead_code: false})

    harness_path = Path.join(out_dir, "c/core_behavior_harness.c")

    File.write!(
      harness_path,
      """
      #include "elmc_generated.h"
      #include <stdio.h>

      static void print_i(const char *label, ElmcValue *value) {
        printf("%s=%lld\\n", label, (long long)elmc_as_int(value));
      }

      static void print_pair(const char *label, ElmcValue *value) {
        if (!value || value->tag != ELMC_TAG_TUPLE2 || !value->payload) {
          printf("%s=-999,-999\\n", label);
          return;
        }
        ElmcTuple2 *pair = (ElmcTuple2 *)value->payload;
        printf("%s=%lld,%lld\\n", label, (long long)elmc_as_int(pair->first), (long long)elmc_as_int(pair->second));
      }

      static void print_maybe_i(const char *label, ElmcValue *value) {
        int is_just = value &&
                      value->tag == ELMC_TAG_MAYBE &&
                      value->payload &&
                      ((ElmcMaybe *)value->payload)->is_just == 1;
        long long inner = -1;
        if (is_just) {
          inner = (long long)elmc_as_int(((ElmcMaybe *)value->payload)->value);
        }
        printf("%s=%d,%lld\\n", label, is_just, inner);
      }

      static void print_result_i(const char *label, ElmcValue *value) {
        int is_ok = value &&
                    value->tag == ELMC_TAG_RESULT &&
                    value->payload &&
                    ((ElmcResult *)value->payload)->is_ok == 1;
        long long inner = -1;
        if (value && value->tag == ELMC_TAG_RESULT && value->payload) {
          ElmcResult *result = (ElmcResult *)value->payload;
          if (result->value) {
            inner = (long long)elmc_as_int(result->value);
          }
        }
        printf("%s=%d,%lld\\n", label, is_ok, inner);
      }

      static void print_result_result_i(const char *label, ElmcValue *value) {
        int outer_ok = 0;
        int inner_ok = 0;
        long long inner_value = -1;

        if (value && value->tag == ELMC_TAG_RESULT && value->payload) {
          ElmcResult *outer = (ElmcResult *)value->payload;
          outer_ok = outer->is_ok ? 1 : 0;
          if (outer->value && outer->value->tag == ELMC_TAG_RESULT && outer->value->payload) {
            ElmcResult *inner = (ElmcResult *)outer->value->payload;
            inner_ok = inner->is_ok ? 1 : 0;
            if (inner->value) {
              inner_value = (long long)elmc_as_int(inner->value);
            }
          }
        }

        printf("%s=%d,%d,%lld\\n", label, outer_ok, inner_ok, inner_value);
      }

      int main(void) {
        ElmcValue *a = elmc_new_int(20);
        ElmcValue *b = elmc_new_int(1);
        ElmcValue *f_args[] = { a, b };
        ElmcValue *fund = elmc_fn_CoreCompliance_fundamentalsMix(f_args, 2);
        print_i("fundamentalsMix", fund);
        elmc_release(fund);
        elmc_release(a);
        elmc_release(b);

        ElmcValue *bit_in = elmc_new_int(5);
        ElmcValue *bit_args[] = { bit_in };
        ElmcValue *bit = elmc_fn_CoreCompliance_bitwiseMix(bit_args, 1);
        print_i("bitwiseMix", bit);
        elmc_release(bit);
        elmc_release(bit_in);

        ElmcValue *bit_ex_in = elmc_new_int(0);
        ElmcValue *bit_ex_args[] = { bit_ex_in };
        ElmcValue *bit_ex = elmc_fn_CoreCompliance_bitwiseExtras(bit_ex_args, 1);
        print_i("bitwiseExtras", bit_ex);
        elmc_release(bit_ex);
        elmc_release(bit_ex_in);

        ElmcValue *mod_in = elmc_new_int(-1);
        ElmcValue *mod_args[] = { mod_in };
        ElmcValue *mod_out = elmc_fn_CoreCompliance_modByNeg(mod_args, 1);
        print_i("modByNeg", mod_out);
        elmc_release(mod_out);
        elmc_release(mod_in);

        ElmcValue *char_in = elmc_new_int(65);
        ElmcValue *char_args[] = { char_in };
        ElmcValue *char_rt = elmc_fn_CoreCompliance_charCodeRoundtrip(char_args, 1);
        print_i("charCodeRoundtrip", char_rt);
        elmc_release(char_rt);
        elmc_release(char_in);

        ElmcValue *left = elmc_new_string("ab");
        ElmcValue *right = elmc_new_string("c");
        ElmcValue *append_args[] = { left, right };
        ElmcValue *append_len = elmc_fn_CoreCompliance_stringAppendLength(append_args, 2);
        print_i("stringAppendLength", append_len);
        elmc_release(append_len);
        elmc_release(left);
        elmc_release(right);

        ElmcValue *empty = elmc_new_string("");
        ElmcValue *non_empty = elmc_new_string("x");
        ElmcValue *empty_args[] = { empty };
        ElmcValue *non_empty_args[] = { non_empty };
        ElmcValue *is_empty = elmc_fn_CoreCompliance_stringEmptyCheck(empty_args, 1);
        ElmcValue *is_non_empty = elmc_fn_CoreCompliance_stringEmptyCheck(non_empty_args, 1);
        print_i("stringEmptyCheck_empty", is_empty);
        print_i("stringEmptyCheck_non_empty", is_non_empty);
        elmc_release(is_empty);
        elmc_release(is_non_empty);
        elmc_release(empty);
        elmc_release(non_empty);

        ElmcValue *pair_l = elmc_new_int(7);
        ElmcValue *pair_r = elmc_new_int(9);
        ElmcValue *pair_first_args[] = { pair_l, pair_r };
        ElmcValue *pair_first = elmc_fn_CoreCompliance_tuplePairFirst(pair_first_args, 2);
        print_i("tuplePairFirst", pair_first);
        elmc_release(pair_first);
        elmc_release(pair_l);
        elmc_release(pair_r);

        ElmcValue *ok_v = elmc_new_int(4);
        ElmcValue *ok = elmc_result_ok(ok_v);
        ElmcValue *ok_args[] = { ok };
        ElmcValue *ok_out = elmc_fn_CoreCompliance_resultInc(ok_args, 1);
        print_i("resultInc_ok", ok_out);
        elmc_release(ok_out);
        elmc_release(ok_v);
        elmc_release(ok);

        ElmcValue *err_msg = elmc_new_string("boom");
        ElmcValue *err = elmc_result_err(err_msg);
        ElmcValue *err_args[] = { err };
        ElmcValue *err_out = elmc_fn_CoreCompliance_resultInc(err_args, 1);
        print_i("resultInc_err", err_out);
        elmc_release(err_out);
        elmc_release(err_msg);
        elmc_release(err);

        ElmcValue *n4 = elmc_new_int(4);
        ElmcValue *just4 = elmc_maybe_just(n4);
        ElmcValue *just_args[] = { just4 };
        ElmcValue *just_out = elmc_fn_CoreCompliance_maybeInc(just_args, 1);
        print_i("maybeInc_just", just_out);
        elmc_release(just_out);
        elmc_release(n4);
        elmc_release(just4);

        ElmcValue *nothing = elmc_maybe_nothing();
        ElmcValue *nothing_args[] = { nothing };
        ElmcValue *nothing_out = elmc_fn_CoreCompliance_maybeInc(nothing_args, 1);
        print_i("maybeInc_nothing", nothing_out);
        elmc_release(nothing_out);
        elmc_release(nothing);

        ElmcValue *l3 = elmc_new_int(3);
        ElmcValue *l2 = elmc_new_int(2);
        ElmcValue *l1 = elmc_new_int(1);
        ElmcValue *list = elmc_list_nil();
        ElmcValue *list3 = elmc_list_cons(l3, list);
        elmc_release(list);
        ElmcValue *list2 = elmc_list_cons(l2, list3);
        elmc_release(list3);
        ElmcValue *list1 = elmc_list_cons(l1, list2);
        elmc_release(list2);
        ElmcValue *fold_args[] = { list1 };
        ElmcValue *fold_out = elmc_fn_CoreCompliance_foldSum(fold_args, 1);
        print_i("foldSum", fold_out);
        elmc_release(fold_out);
        elmc_release(l1);
        elmc_release(l2);
        elmc_release(l3);
        elmc_release(list1);

        ElmcValue *debug_in = elmc_new_int(7);
        ElmcValue *debug_args[] = { debug_in };
        ElmcValue *debug_out = elmc_fn_CoreCompliance_debugEcho(debug_args, 1);
        print_i("debugEcho", debug_out);
        elmc_release(debug_out);
        elmc_release(debug_in);

        ElmcValue *nr_n = elmc_new_int(10);
        ElmcValue *nr_just = elmc_maybe_just(nr_n);
        ElmcValue *nr_ok = elmc_result_ok(nr_just);
        ElmcValue *nr_ok_args[] = { nr_ok };
        ElmcValue *nr_ok_out = elmc_fn_CoreCompliance_nestedResult(nr_ok_args, 1);
        print_i("nestedResult_ok_just", nr_ok_out);
        elmc_release(nr_ok_out);
        elmc_release(nr_n);
        elmc_release(nr_just);
        elmc_release(nr_ok);

        ElmcValue *nr_nothing = elmc_maybe_nothing();
        ElmcValue *nr_ok_nothing = elmc_result_ok(nr_nothing);
        ElmcValue *nr_ok_nothing_args[] = { nr_ok_nothing };
        ElmcValue *nr_ok_nothing_out = elmc_fn_CoreCompliance_nestedResult(nr_ok_nothing_args, 1);
        print_i("nestedResult_ok_nothing", nr_ok_nothing_out);
        elmc_release(nr_ok_nothing_out);
        elmc_release(nr_nothing);
        elmc_release(nr_ok_nothing);

        ElmcValue *nr_err_msg = elmc_new_string("e");
        ElmcValue *nr_err = elmc_result_err(nr_err_msg);
        ElmcValue *nr_err_args[] = { nr_err };
        ElmcValue *nr_err_out = elmc_fn_CoreCompliance_nestedResult(nr_err_args, 1);
        print_i("nestedResult_err", nr_err_out);
        elmc_release(nr_err_out);
        elmc_release(nr_err_msg);
        elmc_release(nr_err);

        ElmcValue *tc_ok_n = elmc_new_int(3);
        ElmcValue *tc_ok = elmc_result_ok(tc_ok_n);
        ElmcValue *tc_just_m = elmc_new_int(4);
        ElmcValue *tc_just = elmc_maybe_just(tc_just_m);
        ElmcValue *tc_pair = elmc_tuple2(tc_ok, tc_just);
        ElmcValue *tc_args[] = { tc_pair };
        ElmcValue *tc_out = elmc_fn_CoreCompliance_tupleCase(tc_args, 1);
        print_i("tupleCase_ok_just", tc_out);
        elmc_release(tc_out);
        elmc_release(tc_ok_n);
        elmc_release(tc_ok);
        elmc_release(tc_just_m);
        elmc_release(tc_just);
        elmc_release(tc_pair);

        ElmcValue *tc2_ok_n = elmc_new_int(9);
        ElmcValue *tc2_ok = elmc_result_ok(tc2_ok_n);
        ElmcValue *tc2_nothing = elmc_maybe_nothing();
        ElmcValue *tc2_pair = elmc_tuple2(tc2_ok, tc2_nothing);
        ElmcValue *tc2_args[] = { tc2_pair };
        ElmcValue *tc2_out = elmc_fn_CoreCompliance_tupleCase(tc2_args, 1);
        print_i("tupleCase_ok_nothing", tc2_out);
        elmc_release(tc2_out);
        elmc_release(tc2_ok_n);
        elmc_release(tc2_ok);
        elmc_release(tc2_nothing);
        elmc_release(tc2_pair);

        ElmcValue *nts_l = elmc_new_int(2);
        ElmcValue *nts_r = elmc_new_int(3);
        ElmcValue *nts_inner = elmc_tuple2(nts_l, nts_r);
        ElmcValue *nts_nothing = elmc_maybe_nothing();
        ElmcValue *nts_outer = elmc_tuple2(nts_inner, nts_nothing);
        ElmcValue *nts_args[] = { nts_outer };
        ElmcValue *nts_out = elmc_fn_CoreCompliance_nestedTupleSum(nts_args, 1);
        print_i("nestedTupleSum", nts_out);
        elmc_release(nts_out);
        elmc_release(nts_l);
        elmc_release(nts_r);
        elmc_release(nts_inner);
        elmc_release(nts_nothing);
        elmc_release(nts_outer);

        ElmcValue *bto_ok_n = elmc_new_int(2);
        ElmcValue *bto_ok = elmc_result_ok(bto_ok_n);
        ElmcValue *bto_just_m = elmc_new_int(5);
        ElmcValue *bto_just = elmc_maybe_just(bto_just_m);
        ElmcValue *bto_pair = elmc_tuple2(bto_ok, bto_just);
        ElmcValue *bto_args[] = { bto_pair };
        ElmcValue *bto_out = elmc_fn_CoreCompliance_branchTupleOut(bto_args, 1);
        print_pair("branchTupleOut_ok_just", bto_out);
        elmc_release(bto_out);
        elmc_release(bto_ok_n);
        elmc_release(bto_ok);
        elmc_release(bto_just_m);
        elmc_release(bto_just);
        elmc_release(bto_pair);

        ElmcValue *bton_n = elmc_new_int(7);
        ElmcValue *bton_just = elmc_maybe_just(bton_n);
        ElmcValue *bton_ok = elmc_result_ok(bton_just);
        ElmcValue *bton_args[] = { bton_ok };
        ElmcValue *bton_out = elmc_fn_CoreCompliance_branchTupleOutNested(bton_args, 1);
        print_pair("branchTupleOutNested_ok_just", bton_out);
        elmc_release(bton_out);
        elmc_release(bton_n);
        elmc_release(bton_just);
        elmc_release(bton_ok);

        ElmcValue *constructor_literal_case = elmc_fn_CoreCompliance_constructorLiteralCase(NULL, 0);
        print_i("constructorLiteralCase", constructor_literal_case);
        elmc_release(constructor_literal_case);

        ElmcValue *constructor_triple_case = elmc_fn_CoreCompliance_constructorTripleCase(NULL, 0);
        print_i("constructorTripleCase", constructor_triple_case);
        elmc_release(constructor_triple_case);

        ElmcValue *dict_lookup = elmc_fn_CoreCompliance_dictLookupOne(NULL, 0);
        ElmcValue *dict_from_list_then_overwrite_size = elmc_fn_CoreCompliance_dictFromListThenOverwriteSize(NULL, 0);
        ElmcValue *dict_from_list_then_overwrite_get = elmc_fn_CoreCompliance_dictFromListThenOverwriteGet(NULL, 0);
        ElmcValue *dict_from_list_dup_size = elmc_fn_CoreCompliance_dictFromListDuplicateSize(NULL, 0);
        ElmcValue *dict_from_list_dup_get = elmc_fn_CoreCompliance_dictFromListDuplicateGet(NULL, 0);
        ElmcValue *dict_has = elmc_fn_CoreCompliance_dictHasOne(NULL, 0);
        ElmcValue *dict_size = elmc_fn_CoreCompliance_dictSizeTwo(NULL, 0);
        ElmcValue *dict_overwrite_size = elmc_fn_CoreCompliance_dictOverwriteSize(NULL, 0);
        ElmcValue *dict_overwrite_get = elmc_fn_CoreCompliance_dictOverwriteGet(NULL, 0);
        ElmcValue *set_has = elmc_fn_CoreCompliance_setHasThree(NULL, 0);
        ElmcValue *set_from_list_dup_size = elmc_fn_CoreCompliance_setFromListDuplicateSize(NULL, 0);
        ElmcValue *set_from_list_dup_has_two = elmc_fn_CoreCompliance_setFromListDuplicateHasTwo(NULL, 0);
        ElmcValue *set_size = elmc_fn_CoreCompliance_setSizeAfterInsert(NULL, 0);
        ElmcValue *set_dup_size = elmc_fn_CoreCompliance_setInsertDuplicateSize(NULL, 0);
        ElmcValue *array_len = elmc_fn_CoreCompliance_arrayLengthFromList(NULL, 0);
        ElmcValue *array_get_hit = elmc_fn_CoreCompliance_arrayGetHit(NULL, 0);
        ElmcValue *array_get_miss = elmc_fn_CoreCompliance_arrayGetMiss(NULL, 0);
        ElmcValue *array_get_negative = elmc_fn_CoreCompliance_arrayGetNegative(NULL, 0);
        ElmcValue *array_set_hit = elmc_fn_CoreCompliance_arraySetInRangeGet(NULL, 0);
        ElmcValue *array_set_last = elmc_fn_CoreCompliance_arraySetLastGet(NULL, 0);
        ElmcValue *array_set_neg_len = elmc_fn_CoreCompliance_arraySetNegativeLength(NULL, 0);
        ElmcValue *array_set_oob_len = elmc_fn_CoreCompliance_arraySetOutOfRangeLength(NULL, 0);
        ElmcValue *array_push_len = elmc_fn_CoreCompliance_arrayPushLength(NULL, 0);
        ElmcValue *array_push_twice_len = elmc_fn_CoreCompliance_arrayPushTwiceLength(NULL, 0);
        ElmcValue *array_push_twice_last = elmc_fn_CoreCompliance_arrayPushTwiceLastGet(NULL, 0);
        ElmcValue *array_set_then_push_last = elmc_fn_CoreCompliance_arraySetThenPushLastGet(NULL, 0);
        ElmcValue *array_set_then_set = elmc_fn_CoreCompliance_arraySetThenSetGet(NULL, 0);
        ElmcValue *array_push_then_set_first = elmc_fn_CoreCompliance_arrayPushThenSetFirstGet(NULL, 0);
        ElmcValue *task_succeed_int = elmc_fn_CoreCompliance_taskSucceedInt(NULL, 0);
        ElmcValue *task_fail_int = elmc_fn_CoreCompliance_taskFailInt(NULL, 0);
        ElmcValue *task_arg_value = elmc_new_int(42);
        ElmcValue *task_succeed_arg_args[] = { task_arg_value };
        ElmcValue *task_fail_arg_args[] = { task_arg_value };
        ElmcValue *task_succeed_arg = elmc_fn_CoreCompliance_taskSucceedArg(task_succeed_arg_args, 1);
        ElmcValue *task_fail_arg = elmc_fn_CoreCompliance_taskFailArg(task_fail_arg_args, 1);
        ElmcValue *task_succeed_nested = elmc_fn_CoreCompliance_taskSucceedNested(NULL, 0);
        ElmcValue *task_fail_nested = elmc_fn_CoreCompliance_taskFailNested(NULL, 0);
        ElmcValue *process_spawn_succeed = elmc_fn_CoreCompliance_processSpawnPidFromSucceed(NULL, 0);
        ElmcValue *process_spawn_fail = elmc_fn_CoreCompliance_processSpawnPidFromFail(NULL, 0);
        ElmcValue *process_sleep_ok = elmc_fn_CoreCompliance_processSleepOk(NULL, 0);
        ElmcValue *process_kill_ok = elmc_fn_CoreCompliance_processKillOk(NULL, 0);

        printf("dictLookupOne_is_just=%d\\n", dict_lookup ? ((ElmcMaybe *)dict_lookup->payload)->is_just : 0);
        print_i("dictFromListThenOverwriteSize", dict_from_list_then_overwrite_size);
        print_maybe_i("dictFromListThenOverwriteGet", dict_from_list_then_overwrite_get);
        print_i("dictFromListDuplicateSize", dict_from_list_dup_size);
        print_maybe_i("dictFromListDuplicateGet", dict_from_list_dup_get);
        print_i("dictHasOne", dict_has);
        print_i("dictSizeTwo", dict_size);
        print_i("dictOverwriteSize", dict_overwrite_size);
        print_maybe_i("dictOverwriteGet", dict_overwrite_get);
        print_i("setHasThree", set_has);
        print_i("setFromListDuplicateSize", set_from_list_dup_size);
        print_i("setFromListDuplicateHasTwo", set_from_list_dup_has_two);
        print_i("setSizeAfterInsert", set_size);
        print_i("setInsertDuplicateSize", set_dup_size);
        print_i("arrayLengthFromList", array_len);
        print_maybe_i("arrayGetHit", array_get_hit);
        print_maybe_i("arrayGetMiss", array_get_miss);
        print_maybe_i("arrayGetNegative", array_get_negative);
        print_maybe_i("arraySetInRangeGet", array_set_hit);
        print_maybe_i("arraySetLastGet", array_set_last);
        print_i("arraySetNegativeLength", array_set_neg_len);
        print_i("arraySetOutOfRangeLength", array_set_oob_len);
        print_i("arrayPushLength", array_push_len);
        print_i("arrayPushTwiceLength", array_push_twice_len);
        print_maybe_i("arrayPushTwiceLastGet", array_push_twice_last);
        print_maybe_i("arraySetThenPushLastGet", array_set_then_push_last);
        print_maybe_i("arraySetThenSetGet", array_set_then_set);
        print_maybe_i("arrayPushThenSetFirstGet", array_push_then_set_first);
        print_result_i("taskSucceedInt", task_succeed_int);
        print_result_i("taskFailInt", task_fail_int);
        print_result_i("taskSucceedArg", task_succeed_arg);
        print_result_i("taskFailArg", task_fail_arg);
        print_result_result_i("taskSucceedNested", task_succeed_nested);
        print_result_result_i("taskFailNested", task_fail_nested);
        print_i("processSpawnPidFromSucceed", process_spawn_succeed);
        print_i("processSpawnPidFromFail", process_spawn_fail);
        print_i("processSleepOk", process_sleep_ok);
        print_i("processKillOk", process_kill_ok);

        elmc_release(dict_lookup);
        elmc_release(dict_from_list_then_overwrite_size);
        elmc_release(dict_from_list_then_overwrite_get);
        elmc_release(dict_from_list_dup_size);
        elmc_release(dict_from_list_dup_get);
        elmc_release(dict_has);
        elmc_release(dict_size);
        elmc_release(dict_overwrite_size);
        elmc_release(dict_overwrite_get);
        elmc_release(set_has);
        elmc_release(set_from_list_dup_size);
        elmc_release(set_from_list_dup_has_two);
        elmc_release(set_size);
        elmc_release(set_dup_size);
        elmc_release(array_len);
        elmc_release(array_get_hit);
        elmc_release(array_get_miss);
        elmc_release(array_get_negative);
        elmc_release(array_set_hit);
        elmc_release(array_set_last);
        elmc_release(array_set_neg_len);
        elmc_release(array_set_oob_len);
        elmc_release(array_push_len);
        elmc_release(array_push_twice_len);
        elmc_release(array_push_twice_last);
        elmc_release(array_set_then_push_last);
        elmc_release(array_set_then_set);
        elmc_release(array_push_then_set_first);
        elmc_release(task_succeed_int);
        elmc_release(task_fail_int);
        elmc_release(task_succeed_arg);
        elmc_release(task_fail_arg);
        elmc_release(task_succeed_nested);
        elmc_release(task_fail_nested);
        elmc_release(process_spawn_succeed);
        elmc_release(process_spawn_fail);
        elmc_release(process_sleep_ok);
        elmc_release(process_kill_ok);
        elmc_release(task_arg_value);

        return 0;
      }
      """
    )

    binary_path = Path.join(out_dir, "core_behavior_harness")

    {compile_out, compile_code} =
      System.cmd(cc, [
        "-std=c11",
        "-Wall",
        "-Wextra",
        "-I#{Path.join(out_dir, "runtime")}",
        "-I#{Path.join(out_dir, "ports")}",
        "-I#{Path.join(out_dir, "c")}",
        Path.join(out_dir, "runtime/elmc_runtime.c"),
        Path.join(out_dir, "ports/elmc_ports.c"),
        Path.join(out_dir, "c/elmc_generated.c"),
        harness_path,
        "-o",
        binary_path
      ])

    assert compile_code == 0, compile_out

    {run_out, run_code} = System.cmd(binary_path, [], stderr_to_stdout: true)
    assert run_code == 0, run_out

    values =
      run_out
      |> String.split("\n", trim: true)
      |> Enum.filter(&String.contains?(&1, "="))
      |> Map.new(fn line ->
        [k, v] = String.split(line, "=", parts: 2)

        parsed =
          if String.contains?(v, ",") do
            v
          else
            String.to_integer(v)
          end

        {k, parsed}
      end)

    assert values["fundamentalsMix"] == 10
    assert values["bitwiseMix"] == 15
    assert values["bitwiseExtras"] == 9_223_372_036_854_775_807
    assert values["modByNeg"] == 4
    assert values["charCodeRoundtrip"] == 65
    assert values["stringAppendLength"] == 3
    assert values["stringEmptyCheck_empty"] == 1
    assert values["stringEmptyCheck_non_empty"] == 0
    assert values["tuplePairFirst"] == 7
    assert values["resultInc_ok"] == 5
    assert values["resultInc_err"] == 0
    assert values["maybeInc_just"] == 5
    assert values["maybeInc_nothing"] == 0
    assert values["foldSum"] == 6
    assert values["debugEcho"] == 7
    assert values["nestedResult_ok_just"] == 11
    assert values["nestedResult_ok_nothing"] == 0
    assert values["nestedResult_err"] == 0
    assert values["tupleCase_ok_just"] == 7
    assert values["tupleCase_ok_nothing"] == 9
    assert values["nestedTupleSum"] == 5
    assert values["branchTupleOut_ok_just"] == "2,5"
    assert values["branchTupleOutNested_ok_just"] == "7,8"
    assert values["constructorLiteralCase"] == 5
    assert values["constructorTripleCase"] == 5
    assert values["dictLookupOne_is_just"] == 1
    assert values["dictFromListThenOverwriteSize"] == 2
    assert values["dictFromListThenOverwriteGet"] == "1,123"
    assert values["dictFromListDuplicateSize"] == 2
    assert values["dictFromListDuplicateGet"] == "1,99"
    assert values["dictHasOne"] == 1
    assert values["dictSizeTwo"] == 2
    assert values["dictOverwriteSize"] == 2
    assert values["dictOverwriteGet"] == "1,99"
    assert values["setHasThree"] == 1
    assert values["setFromListDuplicateSize"] == 3
    assert values["setFromListDuplicateHasTwo"] == 1
    assert values["setSizeAfterInsert"] == 4
    assert values["setInsertDuplicateSize"] == 3
    assert values["arrayLengthFromList"] == 3
    assert values["arrayGetHit"] == "1,20"
    assert values["arrayGetMiss"] == "0,-1"
    assert values["arrayGetNegative"] == "0,-1"
    assert values["arraySetInRangeGet"] == "1,99"
    assert values["arraySetLastGet"] == "1,77"
    assert values["arraySetNegativeLength"] == 3
    assert values["arraySetOutOfRangeLength"] == 3
    assert values["arrayPushLength"] == 4
    assert values["arrayPushTwiceLength"] == 5
    assert values["arrayPushTwiceLastGet"] == "1,50"
    assert values["arraySetThenPushLastGet"] == "1,40"
    assert values["arraySetThenSetGet"] == "1,55"
    assert values["arrayPushThenSetFirstGet"] == "1,77"
    assert values["taskSucceedInt"] == "1,7"
    assert values["taskFailInt"] == "0,5"
    assert values["taskSucceedArg"] == "1,42"
    assert values["taskFailArg"] == "0,42"
    assert values["taskSucceedNested"] == "1,0,9"
    assert values["taskFailNested"] == "0,1,11"
    assert values["processSpawnPidFromSucceed"] > 0
    assert values["processSpawnPidFromFail"] == values["processSpawnPidFromSucceed"] + 1
    assert values["processSleepOk"] == 1
    assert values["processKillOk"] == 1
  end
end
