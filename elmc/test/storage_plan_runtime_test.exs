defmodule Elmc.StoragePlanRuntimeTest do
  use ExUnit.Case

  test "compact int list array get uses O(1) indexed access" do
    cc = System.find_executable("cc")
    if is_nil(cc), do: flunk("cc not available for storage plan runtime harness")

    project_dir = Path.expand("fixtures/simple_project", __DIR__)
    out_dir = Path.expand("tmp/storage_plan_runtime", __DIR__)
    File.rm_rf!(out_dir)
    assert {:ok, _} = Elmc.compile(project_dir, %{out_dir: out_dir, strip_dead_code: false})

    runtime_dir = Path.join(out_dir, "runtime")
    harness_path = Path.join(out_dir, "c/storage_plan_runtime_harness.c")

    File.write!(
      harness_path,
      """
      #include "elmc_runtime.h"
      #include <stdio.h>

      int main(void) {
        const elmc_int_t items[] = { 10, 20, 30, 40 };
        ElmcValue *compact = elmc_list_from_int_array_take(items, 4);
        elmc_int_t hit = elmc_array_get_with_default_int(-1, 2, compact);
        elmc_int_t miss = elmc_array_get_with_default_int(-1, 9, compact);
        elmc_int_t len = elmc_as_int(elmc_array_length(compact));
        ElmcValue *set = elmc_array_set(elmc_new_int_take(1), elmc_new_int_take(99), compact);
        elmc_int_t after_set = elmc_array_get_with_default_int(-1, 1, set);

        printf("hit=%ld miss=%ld len=%ld after_set=%ld\\n",
               (long)hit, (long)miss, (long)len, (long)after_set);

        elmc_release(set);
        elmc_release(compact);
        return (hit == 30 && miss == -1 && len == 4 && after_set == 99) ? 0 : 1;
      }
      """
    )

    runtime_c = Path.join(runtime_dir, "elmc_runtime.c")
    stubs_c = Path.expand("support/elmc_runtime_link_stubs.c", __DIR__)

    {output, exit_code} =
      System.cmd(
        cc,
        [
          "-std=c99",
          "-I#{runtime_dir}",
          harness_path,
          runtime_c,
          stubs_c,
          "-lm",
          "-o",
          Path.join(out_dir, "storage_plan_runtime_harness")
        ],
        stderr_to_stdout: true
      )

    assert exit_code == 0, output

    {run_out, run_code} =
      System.cmd(Path.join(out_dir, "storage_plan_runtime_harness"), [], stderr_to_stdout: true)

    assert run_code == 0, run_out
    assert run_out =~ "hit=30"
    assert run_out =~ "len=4"
    assert run_out =~ "after_set=99"
  end
end
