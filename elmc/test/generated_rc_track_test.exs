defmodule Elmc.GeneratedRcTrackTest do
  use ExUnit.Case, async: true

  alias Elmc.Test.RcTrackHarness

  @tag :rc_track
  test "generated elm/core-shaped probes balance rc registry under ELMC_RC_TRACK" do
    project_dir = Path.expand("fixtures/rc_track_project", __DIR__)
    out_dir = Path.expand("tmp/rc_track_probe", __DIR__)
    File.rm_rf!(out_dir)

    RcTrackHarness.compile!(project_dir, out_dir, entry_module: "RcTrackProbe")

    fold_sum_call =
      RcTrackHarness.generated_fn_call(out_dir, "RcTrackProbe", "foldSum", "args", 1)

    concat_rows_call =
      RcTrackHarness.generated_fn_call(out_dir, "RcTrackProbe", "concatRows", "args", 1)

    branch_tuple_out_call =
      RcTrackHarness.generated_fn_call(out_dir, "RcTrackProbe", "branchTupleOut", "args", 1)

    string_append_length_call =
      RcTrackHarness.generated_fn_call(out_dir, "RcTrackProbe", "stringAppendLength", "args", 2)

    harness_path = Path.join(out_dir, "c/rc_track_harness.c")

    File.write!(
      harness_path,
      """
      #include "elmc_generated.h"
      #include "elmc_generated.c"
      #include <stdio.h>

      #{RcTrackHarness.harness_prelude()}

      static int run_balanced(const char *name, ElmcValue *(*fn)(void)) {
        elmc_rc_track_reset();
        ElmcValue *out = fn();
        if (out) elmc_release(out);
        if (!elmc_rc_track_check_balanced()) {
          fprintf(stderr, "rc leak in %s\\n", name);
          return 1;
        }
        return 0;
      }

      static ElmcValue *run_foldSum(void) {
        static const elmc_int_t items[3] = { 1, 2, 3 };
        ElmcValue *list = elmc_harness_list_from_int_array(items, 3);
        ElmcValue *args[] = { list };
        ElmcValue *out = #{fold_sum_call};
        elmc_release(list);
        return out;
      }

      static ElmcValue *run_concatRows(void) {
        static const elmc_int_t row0[2] = { 1, 2 };
        static const elmc_int_t row1[2] = { 3, 4 };
        ElmcValue *r0 = elmc_harness_list_from_int_array(row0, 2);
        ElmcValue *r1 = elmc_harness_list_from_int_array(row1, 2);
        ElmcValue *inner = elmc_list_cons_take(r1, elmc_list_nil());
        ElmcValue *outer = elmc_list_cons_take(r0, inner);
        ElmcValue *args[] = { outer };
        ElmcValue *out = #{concat_rows_call};
        elmc_release(outer);
        return out;
      }

      static ElmcValue *run_branchTupleOut(void) {
        ElmcValue *n = elmc_harness_new_int(4);
        ElmcValue *m = elmc_harness_new_int(5);
        ElmcValue *ok = elmc_harness_result_ok(n);
        ElmcValue *just = elmc_harness_maybe_just(m);
        ElmcValue *pair = elmc_harness_tuple2_take(ok, just);
        ElmcValue *args[] = { pair };
        ElmcValue *out = #{branch_tuple_out_call};
        elmc_release(pair);
        return out;
      }

      static ElmcValue *run_stringAppendLength(void) {
        ElmcValue *left = elmc_harness_new_string("ab");
        ElmcValue *right = elmc_harness_new_string("cd");
        ElmcValue *args[] = { left, right };
        ElmcValue *out = #{string_append_length_call};
        elmc_release(left);
        elmc_release(right);
        return out;
      }

      int main(void) {
        if (run_balanced("foldSum", run_foldSum) != 0) return 1;
        if (run_balanced("concatRows", run_concatRows) != 0) return 2;
        if (run_balanced("branchTupleOut", run_branchTupleOut) != 0) return 3;
        if (run_balanced("stringAppendLength", run_stringAppendLength) != 0) return 4;
        printf("rc_ok rc_track_probe\\n");
        return 0;
      }
      
      """
    )

    out = RcTrackHarness.run_harness!(out_dir, harness_path, "rc_track_probe")
    RcTrackHarness.assert_balanced!(out)
  end
end
