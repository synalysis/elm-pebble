defmodule Elmc.RuntimeUnionPayloadTest do
  use ExUnit.Case, async: true

  alias Elmc.Test.RcTrackHarness

  test "elmc_union_payload_int handles plain int and union tuple payloads" do
    cc = System.find_executable("cc")
    if is_nil(cc), do: flunk("cc not available for runtime union payload test")

    project_dir = Path.expand("fixtures/simple_project", __DIR__)
    out_dir = Path.expand("tmp/union_payload_runtime", __DIR__)
    File.rm_rf!(out_dir)
    {:ok, _} = Elmc.compile(project_dir, %{out_dir: out_dir, strip_dead_code: false})

    harness_path = Path.join(out_dir, "union_payload_harness.c")

    File.write!(
      harness_path,
      """
      #include "elmc_runtime.h"
      #include <stdio.h>

      static int expect_int(ElmcValue *value, elmc_int_t expected) {
        return elmc_union_payload_int(value) == expected ? 0 : 1;
      }

      int main(void) {
        ElmcValue *plain = elmc_new_int_take(220);
        if (expect_int(plain, 220) != 0) return 2;
        elmc_release(plain);

        ElmcValue *tag = elmc_new_int_take(1);
        ElmcValue *payload = elmc_new_int_take(185);
        ElmcValue *union_value = elmc_tuple2_take_value(tag, payload);
        if (expect_int(union_value, 185) != 0) return 3;
        elmc_release(union_value);

        ElmcValue *just_tag = elmc_new_int_take(1);
        ElmcValue *just_payload = elmc_new_int_take(72);
        ElmcValue *just_inner = elmc_tuple2_take_value(just_tag, just_payload);
        ElmcValue *just = NULL;
        if (elmc_maybe_just_own(&just, just_inner) != RC_SUCCESS) return 4;
        if (expect_int(elmc_maybe_or_tuple_just_payload_borrow(just), 72) != 0) return 5;
        if (elmc_maybe_just_own(&just, just) != RC_SUCCESS) return 6;
        elmc_release(just);

        if (elmc_union_payload_int(NULL) != 0) return 7;

        printf("rc_ok union payload table\\n");
        return 0;
      }
      """
    )

    binary_path = Path.join(out_dir, "union_payload_harness")
    runtime_dir = Path.join(out_dir, "runtime")

    {compile_out, compile_code} =
      System.cmd(cc, [
        "-std=c11",
        "-Wall",
        "-Wextra",
        "-I#{runtime_dir}",
        Path.join(runtime_dir, "elmc_runtime.c"),
        RcTrackHarness.runtime_link_stub(),
        harness_path,
        "-lm",
        "-o",
        binary_path
      ])

    assert compile_code == 0, compile_out

    {run_out, run_code} = System.cmd(binary_path, [])
    assert run_code == 0, run_out
    assert run_out =~ "rc_ok union payload table"
  end
end
