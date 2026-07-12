defmodule Elmc.GeneratedRcTrackConcatTest do
  use ExUnit.Case, async: true

  alias Elmc.Test.RcTrackHarness

  @tag :rc_track
  test "List.concat probe reports no live registry entries after balanced ownership" do
    project_dir = Path.expand("fixtures/rc_track_project", __DIR__)
    out_dir = Path.expand("tmp/rc_track_concat", __DIR__)
    File.rm_rf!(out_dir)

    RcTrackHarness.compile!(project_dir, out_dir, entry_module: "RcTrackProbe")

    harness_path = Path.join(out_dir, "c/rc_track_concat_harness.c")

    File.write!(
      harness_path,
      """
      #include "elmc_generated.h"
      #include "elmc_generated.c"
      #include <stdio.h>

      #{RcTrackHarness.harness_prelude()}

      int main(void) {
        static const elmc_int_t row0[2] = { 1, 2 };
        static const elmc_int_t row1[2] = { 3, 4 };
        ElmcValue *r0 = elmc_harness_list_from_int_array(row0, 2);
        ElmcValue *r1 = elmc_harness_list_from_int_array(row1, 2);
        ElmcValue *inner = elmc_list_cons_take(r1, elmc_list_nil());
        ElmcValue *outer = elmc_list_cons_take(r0, inner);
        elmc_release(inner);
        elmc_release(r0);
        elmc_release(r1);

        elmc_rc_track_reset();
        ElmcValue *args[] = { outer };
        ElmcValue *out = #{RcTrackHarness.generated_fn_call(out_dir, "RcTrackProbe", "concatRows", "args", 1)};
        elmc_release(outer);
        elmc_release(out);

        if (!elmc_rc_track_check_balanced()) return 1;
        printf("rc_ok concatRows\\n");
        return 0;
      }
      
      
      """
    )

    out = RcTrackHarness.run_harness!(out_dir, harness_path, "rc_track_concat")
    RcTrackHarness.assert_balanced!(out)
  end
end
