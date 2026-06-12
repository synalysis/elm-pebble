defmodule Elmc.RuntimeRCTest do
  use ExUnit.Case

  @deep_list_cells 200
  @deep_list_stack_kb 32

  test "list release uses iterative spine teardown in generated runtime" do
    source = Elmc.Runtime.RcTrack.retain_release_impl()

    assert source =~ "elmc_release_list_spine"
    assert source =~ "elmc_release_list_cell_payload"
    assert source =~ "elmc_release_list_spine(value);"
    refute source =~ "elmc_release(node->tail);"
  end

  test "list release is emitted in compiled elmc_runtime.c" do
    cc = System.find_executable("cc")
    if is_nil(cc), do: flunk("cc not available for runtime C test")

    project_dir = Path.expand("fixtures/simple_project", __DIR__)
    out_dir = Path.expand("tmp/runtime_rc_list_spine_source", __DIR__)
    File.rm_rf!(out_dir)
    {:ok, _} = Elmc.compile(project_dir, %{out_dir: out_dir, strip_dead_code: false})

    runtime_c = File.read!(Path.join(out_dir, "runtime/elmc_runtime.c"))

    assert runtime_c =~ "elmc_release_list_spine"
    refute runtime_c =~ "elmc_release(node->tail);"
  end

  test "deep flat list release survives a small C stack (pebble stack safety)" do
    cc = System.find_executable("cc")
    if is_nil(cc), do: flunk("cc not available for runtime C test")

    project_dir = Path.expand("fixtures/simple_project", __DIR__)
    out_dir = Path.expand("tmp/runtime_rc_deep_list_release", __DIR__)
    File.rm_rf!(out_dir)
    {:ok, _} = Elmc.compile(project_dir, %{out_dir: out_dir, strip_dead_code: false})

    harness_path = Path.join(out_dir, "c/deep_list_release_harness.c")

    File.write!(
      harness_path,
      """
      #include "../runtime/elmc_runtime.h"
      #include <stdio.h>

      static ElmcValue *list_of_n_ints(int count) {
        ElmcValue *out = elmc_list_nil();
        ElmcValue **tail_slot = &out;
        for (int i = 0; i < count; i++) {
          ElmcValue *head = elmc_new_int(i);
          ElmcValue *cell = elmc_list_cons(head, elmc_list_nil());
          elmc_release(head);
          *tail_slot = cell;
          tail_slot = &((ElmcCons *)cell->payload)->tail;
        }
        return out;
      }

      int main(void) {
        ElmcValue *list = list_of_n_ints(#{@deep_list_cells});
        elmc_release(list);
        printf("deep_list_release_ok cells=%d\\n", #{@deep_list_cells});
        return 0;
      }
      """
    )

    binary_path = Path.join(out_dir, "deep_list_release_harness")

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

    {run_out, run_code} =
      System.cmd(
        "bash",
        ["-c", "ulimit -s #{@deep_list_stack_kb}; exec #{binary_path}"],
        stderr_to_stdout: true
      )

    assert run_code == 0, "deep list release failed under #{@deep_list_stack_kb}KB stack:\n#{run_out}"
    assert run_out =~ "deep_list_release_ok cells=#{@deep_list_cells}"
  end

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
        ElmcValue *v = elmc_new_int(420);
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
      #include "elmc_generated.c"
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
        Path.join(out_dir, "c/elmc_pebble.c"),
        Path.join(out_dir, "c/elmc_worker.c"),
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

  test "elmc_list_concat does not leak nested row lists" do
    cc = System.find_executable("cc")
    if is_nil(cc), do: flunk("cc not available for runtime C test")

    out_dir = Path.expand("tmp/runtime_rc_list_concat", __DIR__)
    File.rm_rf!(out_dir)
    File.mkdir_p!(Path.join(out_dir, "runtime"))

    project_dir = Path.expand("fixtures/simple_project", __DIR__)
    {:ok, _} = Elmc.compile(project_dir, %{out_dir: out_dir, strip_dead_code: false})

    harness_path = Path.join(out_dir, "c/list_concat_rc_harness.c")

    File.write!(
      harness_path,
      """
      #include "../runtime/elmc_runtime.h"
      #include <stdio.h>

      static ElmcValue *row_of_four(void) {
        ElmcValue *out = elmc_list_nil();
        for (int i = 3; i >= 0; i--) {
          ElmcValue *n = elmc_new_int(i + 1);
          ElmcValue *next = elmc_list_cons(n, out);
          elmc_release(n);
          elmc_release(out);
          out = next;
        }
        return out;
      }

      int main(void) {
        uint64_t a0 = elmc_rc_allocated_count(), r0 = elmc_rc_released_count();
        for (int iter = 0; iter < 100; iter++) {
          ElmcValue *rows[4];
          for (int i = 0; i < 4; i++) rows[i] = row_of_four();
          ElmcValue *lists = elmc_list_nil();
          for (int i = 3; i >= 0; i--) {
            ElmcValue *node = elmc_list_cons(rows[i], lists);
            elmc_release(rows[i]);
            elmc_release(lists);
            lists = node;
          }
          ElmcValue *flat = elmc_list_concat(lists);
          elmc_release(flat);
          elmc_release(lists);
        }
        uint64_t a1 = elmc_rc_allocated_count(), r1 = elmc_rc_released_count();
        printf("%llu %llu\\n",
               (unsigned long long)(a1 - a0),
               (unsigned long long)(r1 - r0));
        return 0;
      }
      """
    )

    binary_path = Path.join(out_dir, "list_concat_rc_harness")

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
    [alloc_delta, rel_delta] = run_out |> String.trim() |> String.split(" ")
    assert String.to_integer(alloc_delta) > 0
    assert String.to_integer(alloc_delta) == String.to_integer(rel_delta)
  end
end
