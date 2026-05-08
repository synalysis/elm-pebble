defmodule Elmc.RuntimeMaybeTest do
  use ExUnit.Case

  test "maybe withDefault accepts lowered Just tuple representation" do
    cc = System.find_executable("cc")
    if is_nil(cc), do: flunk("cc not available for runtime C test")

    out_dir = Path.expand("tmp/runtime_maybe", __DIR__)
    runtime_dir = Path.join(out_dir, "runtime")
    File.rm_rf!(out_dir)
    assert :ok = Elmc.Runtime.Generator.write_runtime(runtime_dir)

    harness_path = Path.join(out_dir, "maybe_harness.c")

    File.write!(
      harness_path,
      """
      #include "elmc_runtime.h"
      #include <stdio.h>

      int main(void) {
        ElmcValue *default_value = elmc_new_int(0);
        ElmcValue *just_tag = elmc_new_int(1);
        ElmcValue *payload = elmc_new_int(42);
        ElmcValue *lowered_just = elmc_tuple2(just_tag, payload);
        ElmcValue *lowered_nothing = elmc_new_int(0);

        ElmcValue *just_result = elmc_maybe_with_default(default_value, lowered_just);
        ElmcValue *nothing_result = elmc_maybe_with_default(default_value, lowered_nothing);

        printf("%lld %lld\\n", (long long)elmc_as_int(just_result), (long long)elmc_as_int(nothing_result));

        elmc_release(just_result);
        elmc_release(nothing_result);
        elmc_release(default_value);
        elmc_release(just_tag);
        elmc_release(payload);
        elmc_release(lowered_just);
        elmc_release(lowered_nothing);
        return 0;
      }
      """
    )

    binary_path = Path.join(out_dir, "maybe_harness")

    {compile_out, compile_code} =
      System.cmd(cc, [
        "-std=c11",
        "-Wall",
        "-Wextra",
        "-I#{runtime_dir}",
        Path.join(runtime_dir, "elmc_runtime.c"),
        harness_path,
        "-o",
        binary_path
      ])

    assert compile_code == 0, compile_out

    {run_out, run_code} = System.cmd(binary_path, [], stderr_to_stdout: true)
    assert run_code == 0, run_out
    assert String.trim(run_out) == "42 0"
  end
end
