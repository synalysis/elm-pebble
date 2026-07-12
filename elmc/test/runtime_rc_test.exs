defmodule Elmc.RuntimeRCTest do
  use Elmc.TestSupport.PrimaryCodegenCase

  alias Elmc.Test.RcTrackHarness

  @deep_list_cells 200
  @deep_list_stack_kb 32

  test "list release uses iterative spine teardown in generated runtime" do
    source = Elmc.Runtime.RcTrack.retain_release_impl()

    assert source =~ "elmc_release_list_spine"
    assert source =~ "elmc_release_list_cell_payload"
    assert source =~ "elmc_release_list_spine(value);"
    assert source =~ "next->rc > 1"
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
          ElmcValue *head = elmc_new_int_take(i);
          ElmcValue *cell = elmc_list_cons_take(head, elmc_list_nil());
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
        RcTrackHarness.runtime_link_stub(),
        harness_path,
        "-lm",
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
        ElmcValue *v = elmc_new_int_take(420);
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
        RcTrackHarness.runtime_link_stub(),
        harness_path,
        "-lm",
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

  test "maybe_just_own transfers owned payloads without leaking nested records" do
    cc = System.find_executable("cc")
    if is_nil(cc), do: flunk("cc not available for runtime C test")

    project_dir = Path.expand("fixtures/simple_project", __DIR__)
    out_dir = Path.expand("tmp/maybe_just_own_runtime", __DIR__)
    File.rm_rf!(out_dir)
    {:ok, _} = Elmc.compile(project_dir, %{out_dir: out_dir, strip_dead_code: false})

    harness_path = Path.join(out_dir, "c/maybe_just_own_harness.c")

    File.write!(
      harness_path,
      """
      #include "elmc_runtime.h"
      #include <stdio.h>

      static uint64_t rc_delta(void) {
        return elmc_rc_allocated_count() - elmc_rc_released_count();
      }

      static void set_sun_field(ElmcValue *model, int index, int i) {
        ElmcValue *a = elmc_new_int_take(360 + i);
        ElmcValue *b = elmc_new_int_take(1080 + i);
        ElmcValue *c = elmc_new_int_take(1);
        ElmcValue *vals[] = {a, b, c};
        ElmcValue *sun = elmc_record_new_values_take_value(3, vals);
        ElmcValue *just = NULL;
        if (elmc_maybe_just_own(&just, sun) != RC_SUCCESS) return;
        ElmcValue *next = elmc_record_update_index_cow_drop(model, index, just);
        elmc_release(just);
        (void)next;
      }

      int main(void) {
        uint64_t baseline = rc_delta();
        ElmcValue *fields[2] = {elmc_maybe_nothing(), elmc_maybe_nothing()};
        ElmcValue *model = elmc_record_new_values_take_value(2, fields);

        for (int i = 0; i < 40; i++) {
          set_sun_field(model, 1, i);
        }

        elmc_release(model);
        return rc_delta() == baseline ? 0 : 2;
      }
      """
    )

    binary_path = Path.join(out_dir, "maybe_just_own_harness")

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

    {_run_out, run_code} = System.cmd(binary_path, [])
    assert run_code == 0
  end

  test "record_update_index retains shared fields when old record is released" do
    cc = System.find_executable("cc")
    if is_nil(cc), do: flunk("cc not available for runtime C test")

    project_dir = Path.expand("fixtures/simple_project", __DIR__)
    out_dir = Path.expand("tmp/record_update_index_runtime", __DIR__)
    File.rm_rf!(out_dir)
    {:ok, _} = Elmc.compile(project_dir, %{out_dir: out_dir, strip_dead_code: false})

    harness_path = Path.join(out_dir, "c/record_update_index_harness.c")

    File.write!(
      harness_path,
      """
      #include "elmc_runtime.h"
      #include <stdio.h>

      int main(void) {
        elmc_rc_track_reset();
        ElmcValue *kind = elmc_new_int_take(7);
        ElmcValue *x = elmc_new_int_take(3);
        ElmcValue *y = elmc_new_int_take(10);
        ElmcValue *fields[] = {kind, x, y};
        ElmcValue *piece = elmc_record_new_values_take_value(3, fields);

        ElmcValue *next_y = elmc_new_int_take(11);
        ElmcValue *updated = elmc_record_update_index(piece, 2, next_y);
        elmc_release(next_y);
        elmc_release(piece);

        if (!updated) return 1;
        if (elmc_as_int(elmc_record_get_index(updated, 0)) != 7) return 2;
        if (elmc_as_int(elmc_record_get_index(updated, 1)) != 3) return 3;
        if (elmc_as_int(elmc_record_get_index(updated, 2)) != 11) return 4;

        elmc_release(updated);
        if (!elmc_rc_track_check_balanced()) return 5;
        return 0;
      }
      """
    )

    binary_path = Path.join(out_dir, "record_update_index_harness")
    runtime_dir = Path.join(out_dir, "runtime")

    {compile_out, compile_code} =
      System.cmd(cc, [
        "-std=c11",
        "-Wall",
        "-Wextra",
        "-DELMC_RC_TRACK=1",
        "-I#{runtime_dir}",
        Path.join(runtime_dir, "elmc_runtime.c"),
        RcTrackHarness.runtime_link_stub(),
        harness_path,
        "-lm",
        "-o",
        binary_path
      ])

    assert compile_code == 0, compile_out

    {_run_out, run_code} = System.cmd(binary_path, [])
    assert run_code == 0
  end

  test "maybe_or_tuple_just_payload retains inner value and keeps wrapper borrowable" do
    cc = System.find_executable("cc")
    if is_nil(cc), do: flunk("cc not available for runtime C test")

    project_dir = Path.expand("fixtures/simple_project", __DIR__)
    out_dir = Path.expand("tmp/maybe_payload_detach_runtime", __DIR__)
    File.rm_rf!(out_dir)
    {:ok, _} = Elmc.compile(project_dir, %{out_dir: out_dir, strip_dead_code: false})

    harness_path = Path.join(out_dir, "c/maybe_payload_detach_harness.c")

    File.write!(
      harness_path,
      """
      #include "elmc_runtime.h"
      #include <stdio.h>

      int main(void) {
        ElmcValue *inner = elmc_new_int_take(42);
        ElmcValue *just = NULL;
        if (elmc_maybe_just_own(&just, inner) != RC_SUCCESS) return 1;
        elmc_release(inner);

        ElmcValue *owned = elmc_maybe_or_tuple_just_payload(just);
        if (elmc_as_int(elmc_maybe_or_tuple_just_payload_borrow(just)) != 42) return 4;
        elmc_release(just);

        if (!owned) return 2;
        if (elmc_as_int(owned) != 42) return 3;

        elmc_release(owned);
        return 0;
      }
      """
    )

    binary_path = Path.join(out_dir, "maybe_payload_detach_harness")
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

    {_run_out, run_code} = System.cmd(binary_path, [])
    assert run_code == 0
  end

  test "branch tuple outputs from nested matches keep rc balanced" do
    cc = System.find_executable("cc")
    if is_nil(cc), do: flunk("cc not available for runtime C test")

    project_dir = Path.expand("fixtures/simple_project", __DIR__)
    out_dir = Path.expand("tmp/runtime_rc_branches", __DIR__)
    File.rm_rf!(out_dir)
    {:ok, _} = Elmc.compile(project_dir, %{out_dir: out_dir, strip_dead_code: false})

    branch_call =
      RcTrackHarness.generated_fn_call(out_dir, "CoreCompliance", "branchTupleOut", "args", 1)

    harness_path = Path.join(out_dir, "c/rc_branch_harness.c")

    File.write!(
      harness_path,
      """
      #include "elmc_generated.h"
      #include "elmc_generated.c"
      #include <stdio.h>

      #{RcTrackHarness.harness_prelude()}

      int main(void) {
        ElmcValue *n = elmc_new_int_take(4);
        ElmcValue *m = elmc_new_int_take(5);
        ElmcValue *ok = elmc_result_ok_take(n);
        ElmcValue *just = elmc_maybe_just_take(m);
        ElmcValue *pair = elmc_tuple2_take_value(ok, just);

        elmc_release(n);
        elmc_release(m);
        elmc_release(ok);
        elmc_release(just);

        ElmcValue *args[] = { pair };
        ElmcValue *out = #{branch_call};
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
        "-lm",
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

  test "maybe_map propagates RC closure allocation failures" do
    cc = System.find_executable("cc")
    if is_nil(cc), do: flunk("cc not available for runtime C test")

    out_dir = Path.expand("tmp/runtime_rc_maybe_map_fail", __DIR__)
    File.rm_rf!(out_dir)
    assert :ok = Elmc.Runtime.Generator.write_runtime(Path.join(out_dir, "runtime"))

    harness_path = Path.join(out_dir, "harness.c")

    File.write!(
      harness_path,
      """
      #include "elmc_runtime.h"
      #include <stdio.h>

      static RC fail_alloc_lambda(
          ElmcValue **out,
          ElmcValue **args,
          int argc,
          ElmcValue **captures,
          int capture_count) {
        (void)out;
        (void)args;
        (void)argc;
        (void)captures;
        (void)capture_count;
        return RC_ERR_OUT_OF_MEMORY;
      }

      int main(void) {
        ElmcValue *cap[1] = { NULL };
        ElmcValue *f = elmc_closure_new_rc_take(fail_alloc_lambda, 1, 0, cap);
        ElmcValue *just = elmc_maybe_just_take(elmc_new_int_take(7));
        ElmcValue *mapped = NULL;
        RC rc = elmc_maybe_map(&mapped, f, just);
        int ok = rc == RC_ERR_OUT_OF_MEMORY && mapped == NULL;
        elmc_release(mapped);
        elmc_release(just);
        elmc_release(f);
        printf("%d\\n", ok);
        return ok ? 0 : 1;
      }
      """
    )

    binary_path = Path.join(out_dir, "harness")

    {compile_out, compile_code} =
      System.cmd(cc, [
        "-std=c11",
        "-Wall",
        "-Wextra",
        "-I#{Path.join(out_dir, "runtime")}",
        Path.join(out_dir, "runtime/elmc_runtime.c"),
        RcTrackHarness.runtime_link_stub(),
        harness_path,
        "-lm",
        "-o",
        binary_path
      ])

    assert compile_code == 0, compile_out

    {run_out, run_code} = System.cmd(binary_path, [], stderr_to_stdout: true)
    assert run_code == 0, run_out
    assert String.trim(run_out) == "1"
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
          ElmcValue *n = elmc_new_int_take(i + 1);
          out = elmc_list_cons_take(n, out);
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
            lists = elmc_list_cons_take(rows[i], lists);
          }
          ElmcValue *flat = elmc_list_concat_take(lists);
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
        RcTrackHarness.runtime_link_stub(),
        harness_path,
        "-lm",
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

  test "elmc_as_int_number coerces float record fields for draw coordinate reads" do
    cc = System.find_executable("cc")
    if is_nil(cc), do: flunk("cc not available for runtime C test")

    out_dir = Path.expand("tmp/runtime_as_int_number", __DIR__)
    File.rm_rf!(out_dir)
    File.mkdir_p!(Path.join(out_dir, "runtime"))

    project_dir = Path.expand("fixtures/simple_project", __DIR__)
    {:ok, _} = Elmc.compile(project_dir, %{out_dir: out_dir, strip_dead_code: false})

    harness_path = Path.join(out_dir, "c/as_int_number_harness.c")

    File.write!(
      harness_path,
      """
      #include "../runtime/elmc_runtime.h"
      #include <stdio.h>

      int main(void) {
        ElmcValue *fx = elmc_new_float_take(121.9);
        ElmcValue *fy = elmc_new_float_take(-14.2);
        ElmcValue *fields[2] = { fx, fy };
        ElmcValue *rect = NULL;
        if (elmc_record_new_values(&rect, 2, fields) != RC_SUCCESS) return 1;

        elmc_int_t x = ELMC_RECORD_GET_INDEX_INT(rect, 0);
        elmc_int_t y = ELMC_RECORD_GET_INDEX_INT(rect, 1);
        elmc_int_t direct = elmc_as_int_number(fx);
        elmc_release(rect);
        elmc_release(fx);
        elmc_release(fy);

        printf("rect_xy=%lld,%lld direct=%lld\\n", (long long)x, (long long)y, (long long)direct);
        return (x == 121 && y == -14 && direct == 121) ? 0 : 2;
      }
      """
    )

    binary_path = Path.join(out_dir, "as_int_number_harness")

    {compile_out, compile_code} =
      System.cmd(cc, [
        "-std=c11",
        "-Wall",
        "-Wextra",
        "-I#{Path.join(out_dir, "runtime")}",
        Path.join(out_dir, "runtime/elmc_runtime.c"),
        RcTrackHarness.runtime_link_stub(),
        harness_path,
        "-lm",
        "-o",
        binary_path
      ])

    assert compile_code == 0, compile_out

    {run_out, run_code} = System.cmd(binary_path, [], stderr_to_stdout: true)
    assert run_code == 0, run_out
    assert run_out =~ "rect_xy=121,-14 direct=121"
  end
end
