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

  test "pebble watch builds emit sin_lookup trig without platform ifdef" do
    source = """
    module Main exposing (main)

    import Basics
    import Pebble.Platform as Platform

    type alias Model = ()

    type Msg = Noop

    init _ = ( trigLen 0 10, Platform.Cmd.none )
    update _ m = ( m, Platform.Cmd.none )
    subscriptions _ = Platform.Sub.none

    trigLen : Int -> Int -> Int
    trigLen angle radius =
        let
            theta =
                toFloat angle * 2 * Basics.pi / 65536
        in
        Basics.round (Basics.sin theta * Basics.toFloat radius)

    view _ = Platform.Cmd.none

    main = Platform.application { init = init, update = update, view = \\_ -> Platform.Cmd.none, subscriptions = subscriptions }
    """

    project_dir = Path.expand("tmp/pebble_trig_sin_lookup", __DIR__)
    out_dir = Path.expand("tmp/pebble_trig_sin_lookup_codegen", __DIR__)
    File.rm_rf!(project_dir)
    File.rm_rf!(out_dir)
    File.mkdir_p!(Path.join(project_dir, "src"))
    File.write!(Path.join(project_dir, "src/Main.elm"), source)
    File.cp!(Path.expand("fixtures/simple_project/elm.json", __DIR__), Path.join(project_dir, "elm.json"))

    assert {:ok, result} =
             Elmc.compile(project_dir, %{
               out_dir: out_dir,
               entry_module: "Main",
               pebble_int32: true,
               strip_dead_code: false
             })

    decl =
      result.ir.modules
      |> Enum.flat_map(& &1.declarations)
      |> Enum.find(&(&1.name == "trigLen"))

    decl_map = Elmc.Backend.CCodegen.IRQueries.function_decl_map(result.ir)

    assert Elmc.Backend.CCodegen.Native.FunctionCall.return_kind(decl, "Main", decl_map) ==
             :native_int

    generated = File.read!(Path.join(out_dir, "c/elmc_generated.c"))

    trig_body = Elmc.Test.CCodegenExtract.fn_impl_body(generated, "elmc_fn_Main_trigLen")

    assert trig_body =~ "sin_lookup((int32_t)"
    refute trig_body =~ "generated_trig_sin_double"
    refute trig_body =~ "#if defined(PBL_PLATFORM_APLITE)"
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

  test "runtime includes malloc registry hooks for ELMC_ALLOC_TRACK" do
    out_dir = Path.expand("tmp/runtime_alloc_track", __DIR__)
    runtime_dir = Path.join(out_dir, "runtime")
    File.rm_rf!(out_dir)

    assert :ok = Elmc.Runtime.Generator.write_runtime(runtime_dir)

    runtime_h = File.read!(Path.join(runtime_dir, "elmc_runtime.h"))
    runtime_c = File.read!(Path.join(runtime_dir, "elmc_runtime.c"))

    assert runtime_h =~ "ELMC_ALLOC_TRACK"
    assert runtime_h =~ "elmc_alloc_track_dump_live"
    assert runtime_c =~ "elmc_alloc_track_register"
    assert runtime_c =~ "elmc_alloc_track_check_balanced"
  end

  test "runtime includes alloc probe snapshot API" do
    out_dir = Path.expand("tmp/runtime_alloc_probe", __DIR__)
    runtime_dir = Path.join(out_dir, "runtime")
    File.rm_rf!(out_dir)

    assert :ok = Elmc.Runtime.Generator.write_runtime(runtime_dir)

    runtime_h = File.read!(Path.join(runtime_dir, "elmc_runtime.h"))
    runtime_c = File.read!(Path.join(runtime_dir, "elmc_runtime.c"))

    assert runtime_h =~ "ELMC_ALLOC_PROBE"
    assert runtime_h =~ "elmc_alloc_probe_snap"
    assert runtime_c =~ "elmc_alloc_probe_diff"
  end

  test "runtime always includes math.h for polar point helpers on Pebble" do
    out_dir = Path.expand("tmp/runtime_math_include", __DIR__)
    runtime_dir = Path.join(out_dir, "runtime")
    File.rm_rf!(out_dir)

    assert :ok = Elmc.Runtime.Generator.write_runtime(runtime_dir)

    runtime_c = File.read!(Path.join(runtime_dir, "elmc_runtime.c"))

    assert runtime_c =~ "#include <math.h>"
    refute runtime_c =~ "#ifndef ELMC_PEBBLE_PLATFORM\n#include <math.h>"
    assert runtime_c =~ "elmc_polar_point_x("
    assert runtime_c =~ "lround(sin(theta)"
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
      ElmcValue *out = NULL;
      if (elmc_record_new_values_ints(&out, 2, values) != RC_SUCCESS) return NULL;
      return out;
    }

    ElmcValue *uses_value_record_take(void) {
      ElmcValue *values[1] = { NULL };
      if (elmc_new_int(&values[0], 3) != RC_SUCCESS) return NULL;
      ElmcValue *out = NULL;
      if (elmc_record_new_values_take(&out, 1, values) != RC_SUCCESS) return NULL;
      return out;
    }
    """)

    assert :ok = Elmc.Runtime.Generator.write_runtime(runtime_dir, prune_from_dir: refs_dir)

    runtime = File.read!(Path.join(runtime_dir, "elmc_runtime.c"))
    header = File.read!(Path.join(runtime_dir, "elmc_runtime.h"))

    assert runtime =~ "RC elmc_record_new_values_ints"
    assert runtime =~ "RC elmc_record_new_values_take"
    assert runtime =~ "elmc_record_cell_alloc_values"
    assert header =~ "RC elmc_record_new_values_ints"
    assert header =~ "RC elmc_record_new_values_take"
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
      ElmcValue *out = NULL;
      if (elmc_closure_new(&out, 0, 0, 0, NULL) != RC_SUCCESS) return NULL;
      return out;
    }
    """)

    assert :ok = Elmc.Runtime.Generator.write_runtime(runtime_dir, prune_from_dir: refs_dir)

    runtime = File.read!(Path.join(runtime_dir, "elmc_runtime.c"))

    assert runtime =~ "RC elmc_closure_new"
    assert runtime =~ "elmc_malloc_impl"
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
    assert runtime =~ "const ElmcValue ELMC_SMALL_INTS"
    assert runtime =~ "static ElmcValue ELMC_MAYBE_NOTHING"
    assert runtime =~ "return &ELMC_MAYBE_NOTHING;"
    assert runtime =~ "rc = elmc_alloc_scalar(out, ELMC_TAG_INT, value)"
    assert runtime =~ "*out = value ? &ELMC_BOOL_TRUE : &ELMC_BOOL_FALSE"
    assert runtime =~ "return value->scalar;"
    refute runtime =~ "malloc(sizeof(elmc_int_t))"
  end

  test "pebble_int32 runtime uses a smaller small-int cache" do
    runtime_dir = Path.expand("tmp/runtime_pebble_small_ints", __DIR__)

    File.rm_rf!(runtime_dir)

    assert :ok = Elmc.Runtime.Generator.write_runtime(runtime_dir, pebble_int32: true)

    runtime = File.read!(Path.join(runtime_dir, "elmc_runtime.c"))

    assert runtime =~ "#define ELMC_SMALL_INT_MAX 3"
    assert runtime =~ "#define ELMC_PROCESS_MAX_SLOTS 2"
    refute runtime =~ "#define ELMC_SMALL_INT_MAX 64"
  end

  test "runtime uses shared empty string and logs allocation failures" do
    runtime_dir = Path.expand("tmp/runtime_alloc_failure_logging", __DIR__)

    File.rm_rf!(runtime_dir)

    assert :ok = Elmc.Runtime.Generator.write_runtime(runtime_dir)

    runtime = File.read!(Path.join(runtime_dir, "elmc_runtime.c"))

    assert runtime =~ "static ElmcValue ELMC_EMPTY_STRING"
    assert runtime =~ "*out = &ELMC_EMPTY_STRING"
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
    assert runtime =~ "rc = elmc_list_cell_alloc(out, head, tail, 0)"
    assert runtime =~ "elmc_list_cell_alloc(out, head, tail, 0)"
    assert runtime =~ "rc = elmc_record_cell_alloc(out, field_count, field_names, field_values, 0)"
    assert runtime =~ "rc = elmc_record_cell_alloc(out, field_count, field_names, field_values, 1)"
    assert runtime =~ "if (value->tag == ELMC_TAG_LIST)"
    assert runtime =~ "if (elmc_list_cell_release(value))"
    assert runtime =~ "} else if (value->tag == ELMC_TAG_TUPLE2 && value->payload != NULL)"
    assert runtime =~ "if (elmc_tuple2_cell_release(value))"
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
      ElmcValue *out = NULL;
      (void)argc;
      if (capture_count != 1) {
        if (elmc_new_int(&out, -1) != RC_SUCCESS) return NULL;
        return out;
      }
      if (elmc_new_int(&out, elmc_as_int(captures[0]) + elmc_as_int(args[0])) != RC_SUCCESS) return NULL;
      return out;
    }

    int main(void) {
      ElmcValue *one = NULL;
      ElmcValue *a = NULL;
      ElmcValue *b = NULL;
      ElmcValue *c = NULL;
      ElmcValue *tuple = NULL;
      ElmcValue *maybe = NULL;
      ElmcValue *ok = NULL;
      ElmcValue *record = NULL;
      ElmcValue *captured = NULL;
      ElmcValue *closure = NULL;
      ElmcValue *arg = NULL;
      ElmcValue *sum = NULL;
      if (elmc_new_int(&one, 1) != RC_SUCCESS) return 1;
      ElmcValue *nil = elmc_list_nil();
      if (elmc_list_cons(&a, one, nil) != RC_SUCCESS) return 1;
      if (elmc_list_cons(&b, one, a) != RC_SUCCESS) return 1;
      elmc_release(a);
      if (elmc_list_cons(&c, one, b) != RC_SUCCESS) return 1;
      elmc_release(b);
      if (elmc_tuple2(&tuple, one, c) != RC_SUCCESS) return 1;
      if (elmc_maybe_just(&maybe, one) != RC_SUCCESS) return 1;
      if (elmc_result_ok(&ok, tuple) != RC_SUCCESS) return 1;
      const char *field_names[] = {"value"};
      ElmcValue *field_values[] = {one};
      if (elmc_record_new(&record, 1, field_names, field_values) != RC_SUCCESS) return 1;
      if (elmc_new_int(&captured, 100) != RC_SUCCESS) return 1;
      ElmcValue *closure_captures[] = {captured};
      if (elmc_closure_new(&closure, add_capture, 1, 1, closure_captures) != RC_SUCCESS) return 1;
      elmc_release(captured);
      if (elmc_new_int(&arg, 23) != RC_SUCCESS) return 1;
      ElmcValue *closure_args[] = {arg};
      sum = elmc_closure_call(closure, closure_args, 1);
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
          Elmc.Test.RcTrackHarness.runtime_link_stub(),
          "list_cell_harness.c",
          "-lm",
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
