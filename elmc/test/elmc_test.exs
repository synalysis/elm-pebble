defmodule ElmcTest do
  use ExUnit.Case

  test "compile writes runtime, ports, and c outputs" do
    project_dir = Path.expand("fixtures/simple_project", __DIR__)
    out_dir = Path.expand("tmp/build", __DIR__)

    File.rm_rf!(out_dir)

    assert {:ok, %{ir: ir}} = Elmc.compile(project_dir, %{out_dir: out_dir})
    assert length(ir.modules) > 0

    assert File.exists?(Path.join(out_dir, "runtime/elmc_runtime.h"))
    assert File.exists?(Path.join(out_dir, "runtime/elmc_runtime.c"))
    assert File.exists?(Path.join(out_dir, "ports/elmc_ports.h"))
    assert File.exists?(Path.join(out_dir, "ports/elmc_ports.c"))
    assert File.exists?(Path.join(out_dir, "c/elmc_generated.h"))
    assert File.exists?(Path.join(out_dir, "c/elmc_generated.c"))
    assert File.exists?(Path.join(out_dir, "c/elmc_worker.h"))
    assert File.exists?(Path.join(out_dir, "c/elmc_worker.c"))
    assert File.exists?(Path.join(out_dir, "c/elmc_pebble.h"))
    assert File.exists?(Path.join(out_dir, "c/elmc_pebble.c"))
    assert File.exists?(Path.join(out_dir, "c/host_harness.c"))
    assert File.exists?(Path.join(out_dir, "CMakeLists.txt"))
    assert File.exists?(Path.join(out_dir, "Makefile"))
  end

  test "compile strips dead functions by default" do
    project_dir = Path.expand("fixtures/simple_project", __DIR__)
    out_dir = Path.expand("tmp/build_stripped", __DIR__)
    File.rm_rf!(out_dir)

    assert {:ok, _} = Elmc.compile(project_dir, %{out_dir: out_dir})
    generated = File.read!(Path.join(out_dir, "c/elmc_generated.c"))

    assert String.contains?(generated, "elmc_fn_Main_init")
    assert String.contains?(generated, "elmc_fn_Main_update")
    assert String.contains?(generated, "elmc_fn_Main_view")
    refute String.contains?(generated, "elmc_fn_CoreCompliance_foldSum")
    refute String.contains?(generated, "elmc_fn_CoreCompliance_resultInc")
  end

  test "compile omits unused generated trig fallback helpers" do
    project_dir = Path.expand("fixtures/simple_project", __DIR__)
    out_dir = Path.expand("tmp/build_no_trig_fallback", __DIR__)
    File.rm_rf!(out_dir)

    assert {:ok, _} = Elmc.compile(project_dir, %{out_dir: out_dir})

    generated = File.read!(Path.join(out_dir, "c/elmc_generated.c"))

    refute generated =~ "generated_trig_normalize_radians"
    refute generated =~ "generated_trig_sin_double"
    refute generated =~ "generated_trig_cos_double"
  end

  test "runtime pruning keeps macro-derived accessors referenced by generated code" do
    out_dir = Path.expand("tmp/runtime_pruned_record_macros", __DIR__)
    refs_dir = Path.join(out_dir, "refs")
    runtime_dir = Path.join(out_dir, "runtime")

    File.rm_rf!(out_dir)
    File.mkdir_p!(refs_dir)

    File.write!(Path.join(refs_dir, "elmc_generated.c"), """
    #include "elmc_runtime.h"

    static void uses_record_macros(ElmcValue *model) {
      (void)ELMC_RECORD_GET_INDEX_BOOL(model, 2);
      (void)ELMC_RECORD_GET_INDEX_FLOAT(model, 1);
      (void)ELMC_RECORD_GET_INDEX_INT(model, 0);
    }
    """)

    assert :ok = Elmc.Runtime.Generator.write_runtime(runtime_dir, prune_from_dir: refs_dir)

    runtime = File.read!(Path.join(runtime_dir, "elmc_runtime.c"))

    assert runtime =~ "elmc_int_t elmc_as_bool"
    assert runtime =~ "double elmc_as_float"
    assert runtime =~ "elmc_int_t elmc_as_int"
  end

  test "runtime pruning keeps elmc_sub_alloc when generated code uses elmc_sub1" do
    out_dir = Path.expand("tmp/runtime_pruned_sub", __DIR__)
    refs_dir = Path.join(out_dir, "refs")
    runtime_dir = Path.join(out_dir, "runtime")

    File.rm_rf!(out_dir)
    File.mkdir_p!(refs_dir)

    File.write!(Path.join(refs_dir, "elmc_generated.c"), """
    #include "elmc_runtime.h"

    ElmcValue *uses_sub(void) {
      return elmc_sub1(ELMC_SUBSCRIPTION_MINUTE_CHANGE, ELMC_PEBBLE_MSG_MINUTECHANGED);
    }
    """)

    assert :ok = Elmc.Runtime.Generator.write_runtime(runtime_dir, prune_from_dir: refs_dir)

    runtime = File.read!(Path.join(runtime_dir, "elmc_runtime.c"))

    assert runtime =~ "ElmcValue *elmc_sub1"
    assert runtime =~ "elmc_sub_alloc"
  end

  test "runtime pruning keeps elmc_cmd_alloc when generated code uses elmc_cmd1" do
    out_dir = Path.expand("tmp/runtime_pruned_cmd", __DIR__)
    refs_dir = Path.join(out_dir, "refs")
    runtime_dir = Path.join(out_dir, "runtime")

    File.rm_rf!(out_dir)
    File.mkdir_p!(refs_dir)

    File.write!(Path.join(refs_dir, "elmc_generated.c"), """
    #include "elmc_runtime.h"

    ElmcValue *uses_cmd(void) {
      return elmc_cmd1(1, 2);
    }
    """)

    assert :ok = Elmc.Runtime.Generator.write_runtime(runtime_dir, prune_from_dir: refs_dir)

    runtime = File.read!(Path.join(runtime_dir, "elmc_runtime.c"))

    assert runtime =~ "ElmcValue *elmc_cmd1"
    assert runtime =~ "elmc_cmd_alloc"
    refute runtime =~ "implicit declaration"
  end

  test "runtime pruning keeps string command helper when generated code uses elmc_cmd1_string" do
    out_dir = Path.expand("tmp/runtime_pruned_cmd_string", __DIR__)
    refs_dir = Path.join(out_dir, "refs")
    runtime_dir = Path.join(out_dir, "runtime")

    File.rm_rf!(out_dir)
    File.mkdir_p!(refs_dir)

    File.write!(Path.join(refs_dir, "elmc_generated.c"), """
    #include "elmc_runtime.h"

    ElmcValue *uses_cmd_string(void) {
      return elmc_cmd1_string(1, 2, "saved");
    }
    """)

    assert :ok = Elmc.Runtime.Generator.write_runtime(runtime_dir, prune_from_dir: refs_dir)

    runtime = File.read!(Path.join(runtime_dir, "elmc_runtime.c"))

    assert runtime =~ "ElmcValue *elmc_cmd1_string"
    assert runtime =~ "elmc_cmd_alloc"
    assert runtime =~ "elmc_new_string"
    refute runtime =~ "implicit declaration"
  end

  test "runtime pruning keeps value-only record constructors" do
    out_dir = Path.expand("tmp/runtime_pruned_value_record", __DIR__)
    refs_dir = Path.join(out_dir, "refs")
    runtime_dir = Path.join(out_dir, "runtime")

    File.rm_rf!(out_dir)
    File.mkdir_p!(refs_dir)

    File.write!(Path.join(refs_dir, "elmc_generated.c"), """
    #include "elmc_runtime.h"

    ElmcValue *uses_value_record(void) {
      elmc_int_t values[2] = { 1, 2 };
      return elmc_record_new_values_ints(2, values);
    }

    ElmcValue *uses_value_record_take(void) {
      ElmcValue *values[1] = { elmc_new_int(3) };
      return elmc_record_new_values_take(1, values);
    }
    """)

    assert :ok = Elmc.Runtime.Generator.write_runtime(runtime_dir, prune_from_dir: refs_dir)

    runtime = File.read!(Path.join(runtime_dir, "elmc_runtime.c"))
    header = File.read!(Path.join(runtime_dir, "elmc_runtime.h"))

    assert runtime =~ "ElmcValue *elmc_record_new_values_ints"
    assert runtime =~ "ElmcValue *elmc_record_new_values_take"
    assert runtime =~ "elmc_record_cell_alloc_values"
    assert header =~ "ElmcValue *elmc_record_new_values_ints"
    assert header =~ "ElmcValue *elmc_record_new_values_take"
    refute runtime =~ "implicit declaration"
  end

  test "runtime pruning keeps closure constructor referenced by generated code" do
    out_dir = Path.expand("tmp/runtime_pruned_closure", __DIR__)
    refs_dir = Path.join(out_dir, "refs")
    runtime_dir = Path.join(out_dir, "runtime")

    File.rm_rf!(out_dir)
    File.mkdir_p!(refs_dir)

    File.write!(Path.join(refs_dir, "elmc_generated.c"), """
    #include "elmc_runtime.h"

    ElmcValue *uses_closure(void) {
      return elmc_closure_new(0, 0, 0);
    }
    """)

    assert :ok = Elmc.Runtime.Generator.write_runtime(runtime_dir, prune_from_dir: refs_dir)

    runtime = File.read!(Path.join(runtime_dir, "elmc_runtime.c"))

    assert runtime =~ "ElmcValue *elmc_closure_new"
    assert runtime =~ "ElmcValue *elmc_alloc"
    assert runtime =~ "elmc_closure_cell_release"
  end

  test "runtime stores int and bool scalars inline" do
    runtime_dir = Path.expand("tmp/runtime_inline_scalars", __DIR__)

    File.rm_rf!(runtime_dir)

    assert :ok = Elmc.Runtime.Generator.write_runtime(runtime_dir)

    header = File.read!(Path.join(runtime_dir, "elmc_runtime.h"))
    runtime = File.read!(Path.join(runtime_dir, "elmc_runtime.c"))

    assert header =~ "uint16_t rc;"
    assert header =~ "uint8_t tag;"
    assert header =~ "elmc_int_t scalar;"
    assert runtime =~ "static ElmcValue ELMC_BOOL_FALSE"
    assert runtime =~ "#define ELMC_SMALL_INT_MAX 64"
    assert runtime =~ "static const ElmcValue ELMC_SMALL_INTS"
    assert runtime =~ "static ElmcValue ELMC_MAYBE_NOTHING"
    assert runtime =~ "return &ELMC_MAYBE_NOTHING;"
    assert runtime =~ "return elmc_alloc_scalar(ELMC_TAG_INT, value);"
    assert runtime =~ "return value ? &ELMC_BOOL_TRUE : &ELMC_BOOL_FALSE;"
    assert runtime =~ "return value->scalar;"
    refute runtime =~ "malloc(sizeof(elmc_int_t))"
  end

  test "runtime uses shared empty string and logs allocation failures" do
    runtime_dir = Path.expand("tmp/runtime_alloc_failure_logging", __DIR__)

    File.rm_rf!(runtime_dir)

    assert :ok = Elmc.Runtime.Generator.write_runtime(runtime_dir)

    runtime = File.read!(Path.join(runtime_dir, "elmc_runtime.c"))

    assert runtime =~ "static ElmcValue ELMC_EMPTY_STRING"
    assert runtime =~ "return &ELMC_EMPTY_STRING;"
    assert runtime =~ "static void elmc_log_alloc_failed"
    assert runtime =~ "static void *elmc_realloc_impl"
    refute runtime =~ "ELMC_ALLOC_FAILURE_LOGGED"
    assert runtime =~ "ELMC malloc failed %s"
    assert runtime =~ "static void *elmc_malloc_impl(size_t size, const char *context"
    assert runtime =~ "elmc_malloc_impl(sizeof(ElmcValue), __func__"
    refute runtime =~ "if (!out) return elmc_new_string(\"\");"
  end

  test "runtime stores list value and cons payload in one allocation" do
    runtime_dir = Path.expand("tmp/runtime_list_cell", __DIR__)

    File.rm_rf!(runtime_dir)

    assert :ok = Elmc.Runtime.Generator.write_runtime(runtime_dir)

    runtime = File.read!(Path.join(runtime_dir, "elmc_runtime.c"))

    assert runtime =~ "ElmcListCell"
    assert runtime =~ "ElmcMaybeCell"
    assert runtime =~ "ElmcResultCell"
    assert runtime =~ "ElmcTuple2Cell"
    assert runtime =~ "ElmcRecordCell"
    assert runtime =~ "ElmcClosureCell"
    assert runtime =~ "return elmc_list_cell_alloc(head, tail, 0);"
    assert runtime =~ "return elmc_list_cell_alloc(head, tail, 1);"
    assert runtime =~ "return elmc_record_cell_alloc(field_count, field_names, field_values, 0);"
    assert runtime =~ "return elmc_record_cell_alloc(field_count, field_names, field_values, 1);"
    assert runtime =~ "if (value->tag == ELMC_TAG_LIST && elmc_list_cell_release(value))"
    assert runtime =~ "if (value->tag == ELMC_TAG_TUPLE2 && elmc_tuple2_cell_release(value))"
    assert runtime =~ "if (elmc_record_cell_release(value))"
    assert runtime =~ "if (elmc_closure_cell_release(value))"
    refute runtime =~ "ELMC_LIST_POOL_CAPACITY"
  end

  test "runtime cell optimizations compile and release cells" do
    out_dir = Path.expand("tmp/runtime_list_cell_compile", __DIR__)
    runtime_dir = Path.join(out_dir, "runtime")
    harness_path = Path.join(out_dir, "list_cell_harness.c")
    binary_path = Path.join(out_dir, "list_cell_harness")

    File.rm_rf!(out_dir)
    File.mkdir_p!(out_dir)

    assert :ok = Elmc.Runtime.Generator.write_runtime(runtime_dir)

    File.write!(harness_path, """
    #include "elmc_runtime.h"
    #include <stdint.h>

    static ElmcValue *add_capture(ElmcValue **args, int argc, ElmcValue **captures, int capture_count) {
      (void)argc;
      if (capture_count != 1) return elmc_new_int(-1);
      return elmc_new_int(elmc_as_int(captures[0]) + elmc_as_int(args[0]));
    }

    int main(void) {
      ElmcValue *one = elmc_new_int(1);
      ElmcValue *nil = elmc_list_nil();
      ElmcValue *a = elmc_list_cons(one, nil);
      ElmcValue *b = elmc_list_cons(one, a);
      elmc_release(a);
      ElmcValue *c = elmc_list_cons(one, b);
      elmc_release(b);
      ElmcValue *tuple = elmc_tuple2(one, c);
      ElmcValue *maybe = elmc_maybe_just(one);
      ElmcValue *ok = elmc_result_ok(tuple);
      const char *field_names[] = {"value"};
      ElmcValue *field_values[] = {one};
      ElmcValue *record = elmc_record_new(1, field_names, field_values);
      ElmcValue *captured = elmc_new_int(100);
      ElmcValue *closure_captures[] = {captured};
      ElmcValue *closure = elmc_closure_new(add_capture, 1, 1, closure_captures);
      elmc_release(captured);
      ElmcValue *arg = elmc_new_int(23);
      ElmcValue *closure_args[] = {arg};
      ElmcValue *sum = elmc_closure_call(closure, closure_args, 1);
      int sum_ok = elmc_as_int(sum) == 123;
      elmc_release(c);
      elmc_release(record);
      elmc_release(ok);
      elmc_release(maybe);
      elmc_release(tuple);
      elmc_release(sum);
      elmc_release(arg);
      elmc_release(closure);
      elmc_release(one);
      return sum_ok && elmc_rc_allocated_count() == elmc_rc_released_count() ? 0 : 1;
    }
    """)

    cc =
      System.find_executable("cc") || System.find_executable("gcc") ||
        System.find_executable("clang")

    assert is_binary(cc)

    {compile_out, compile_code} =
      System.cmd(
        cc,
        [
          "-std=c11",
          "-Wall",
          "-Wextra",
          "-Werror",
          "-DELMC_PEBBLE_INT32",
          "-Iruntime",
          "runtime/elmc_runtime.c",
          "list_cell_harness.c",
          "-o",
          "list_cell_harness"
        ],
        cd: out_dir,
        stderr_to_stdout: true
      )

    assert compile_code == 0, compile_out

    {run_out, run_code} = System.cmd(binary_path, [], stderr_to_stdout: true)
    assert run_code == 0, run_out
  end
end
