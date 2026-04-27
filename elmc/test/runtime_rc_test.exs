defmodule Elmc.RuntimeRCTest do
  use ExUnit.Case

  test "runtime retain/release counters work in c harness" do
    cc = System.find_executable("cc")
    if is_nil(cc), do: flunk("cc not available for runtime C test")

    project_dir = Path.expand("fixtures/simple_project", __DIR__)
    out_dir = Path.expand("tmp/runtime_rc", __DIR__)
    File.rm_rf!(out_dir)
    {:ok, _} = Elmc.compile(project_dir, %{out_dir: out_dir, strip_dead_code: false})

    harness_path = Path.join(out_dir, "c/rc_harness.c")

    File.write!(
      harness_path,
      """
      #include "../runtime/elmc_runtime.h"
      #include <stdio.h>

      int main(void) {
        ElmcValue *v = elmc_new_int(42);
        elmc_retain(v);
        elmc_release(v);
        elmc_release(v);
        printf("%llu %llu\\n", (unsigned long long)elmc_rc_allocated_count(), (unsigned long long)elmc_rc_released_count());
        return 0;
      }
      """
    )

    binary_path = Path.join(out_dir, "rc_harness")

    {compile_out, compile_code} =
      System.cmd(cc, [
        "-std=c11",
        "-Wall",
        "-Wextra",
        "-I#{Path.join(out_dir, "runtime")}",
        Path.join(out_dir, "runtime/elmc_runtime.c"),
        harness_path,
        "-o",
        binary_path
      ])

    assert compile_code == 0, compile_out

    {run_out, run_code} = System.cmd(binary_path, [])
    assert run_code == 0
    [alloc, rel] = run_out |> String.trim() |> String.split(" ")
    assert String.to_integer(alloc) >= 1
    assert String.to_integer(rel) >= 1
  end

  test "branch tuple outputs from nested matches keep rc balanced" do
    cc = System.find_executable("cc")
    if is_nil(cc), do: flunk("cc not available for runtime C test")

    project_dir = Path.expand("fixtures/simple_project", __DIR__)
    out_dir = Path.expand("tmp/runtime_rc_branches", __DIR__)
    File.rm_rf!(out_dir)
    {:ok, _} = Elmc.compile(project_dir, %{out_dir: out_dir, strip_dead_code: false})

    harness_path = Path.join(out_dir, "c/rc_branch_harness.c")

    File.write!(
      harness_path,
      """
      #include "elmc_generated.h"
      #include <stdio.h>

      int main(void) {
        ElmcValue *n = elmc_new_int(4);
        ElmcValue *m = elmc_new_int(5);
        ElmcValue *ok = elmc_result_ok(n);
        ElmcValue *just = elmc_maybe_just(m);
        ElmcValue *pair = elmc_tuple2(ok, just);

        elmc_release(n);
        elmc_release(m);
        elmc_release(ok);
        elmc_release(just);

        ElmcValue *args[] = { pair };
        ElmcValue *out = elmc_fn_CoreCompliance_branchTupleOut(args, 1);
        elmc_release(out);
        elmc_release(pair);

        printf("%llu %llu\\n",
               (unsigned long long)elmc_rc_allocated_count(),
               (unsigned long long)elmc_rc_released_count());
        return 0;
      }
      """
    )

    binary_path = Path.join(out_dir, "rc_branch_harness")

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

    {run_out, run_code} = System.cmd(binary_path, [])
    assert run_code == 0
    [alloc, rel] = run_out |> String.trim() |> String.split(" ")
    assert String.to_integer(alloc) > 0
    assert String.to_integer(alloc) == String.to_integer(rel)
  end
end
