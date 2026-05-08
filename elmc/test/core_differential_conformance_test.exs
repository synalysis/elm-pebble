defmodule Elmc.CoreDifferentialConformanceTest do
  use ExUnit.Case

  @required_runtime_symbols [
    "elmc_basics_max",
    "elmc_basics_min",
    "elmc_basics_clamp",
    "elmc_basics_mod_by",
    "elmc_bitwise_and",
    "elmc_bitwise_or",
    "elmc_bitwise_xor",
    "elmc_bitwise_complement",
    "elmc_bitwise_shift_left_by",
    "elmc_bitwise_shift_right_by",
    "elmc_bitwise_shift_right_zf_by",
    "elmc_char_to_code",
    "elmc_debug_log",
    "elmc_debug_todo",
    "elmc_debug_to_string",
    "elmc_string_append",
    "elmc_string_is_empty",
    "elmc_tuple_first",
    "elmc_tuple_second",
    "elmc_list_foldl",
    "elmc_maybe_map",
    "elmc_maybe_with_default",
    "elmc_array_empty",
    "elmc_array_get",
    "elmc_task_succeed",
    "elmc_task_fail",
    "elmc_process_spawn",
    "elmc_process_sleep",
    "elmc_process_kill"
  ]

  test "runtime contains expected core intrinsic entry points" do
    project_dir = Path.expand("fixtures/simple_project", __DIR__)
    out_dir = Path.expand("tmp/differential_conformance", __DIR__)
    File.rm_rf!(out_dir)

    assert {:ok, _} =
             Elmc.compile(project_dir, %{
               out_dir: out_dir,
               strip_dead_code: false,
               entry_module: "Main"
             })

    runtime_h = File.read!(Path.join(out_dir, "runtime/elmc_runtime.h"))
    runtime_c = File.read!(Path.join(out_dir, "runtime/elmc_runtime.c"))

    Enum.each(@required_runtime_symbols, fn symbol ->
      assert String.contains?(runtime_h, symbol)
      assert String.contains?(runtime_c, symbol)
    end)
  end

  test "generated parser accepts import alias metadata forms" do
    source = """
    module Main exposing (main)
    import List as L
    import Maybe
    """

    assert {:ok, tokens, _} = :elm_ex_elm_lexer.string(String.to_charlist(source))
    assert {:ok, metadata} = :elm_ex_elm_parser.parse(tokens)

    assert metadata == [
             {:module, "Main", ["main"]},
             {:import, "List", %{as: "L", exposing: nil}},
             {:import, "Maybe", %{as: nil, exposing: nil}}
           ]
  end

  test "generated C dispatches to expected core runtime helpers" do
    project_dir = Path.expand("fixtures/simple_project", __DIR__)
    out_dir = Path.expand("tmp/differential_conformance_codegen", __DIR__)
    File.rm_rf!(out_dir)

    assert {:ok, _} =
             Elmc.compile(project_dir, %{
               out_dir: out_dir,
               strip_dead_code: false,
               entry_module: "Main"
             })

    generated_c = File.read!(Path.join(out_dir, "c/elmc_generated.c"))
    pebble_c = File.read!(Path.join(out_dir, "c/elmc_pebble.c"))

    assert pebble_c =~ "#define ELMC_PEBBLE_PLATFORM 1"
    assert pebble_c =~ "#ifdef ELMC_PEBBLE_PLATFORM"
    assert pebble_c =~ "#include <pebble.h>"
    assert pebble_c =~ "#include <time.h>"
    assert pebble_c =~ "extern long time(long *timer);"
    refute pebble_c =~ "extern time_t time"

    expected_calls = [
      "elmc_basics_clamp(",
      "elmc_basics_max(",
      "elmc_basics_min(",
      "elmc_bitwise_and(",
      "elmc_bitwise_xor(",
      "elmc_bitwise_shift_left_by(",
      "elmc_char_to_code(",
      "elmc_debug_log(",
      "elmc_append(",
      "elmc_string_is_empty(",
      "elmc_tuple_first(",
      "elmc_tuple_second(",
      "elmc_list_foldl(",
      "elmc_maybe_map(",
      "elmc_maybe_with_default(",
      "elmc_process_spawn(",
      "elmc_process_sleep(",
      "elmc_process_kill("
    ]

    Enum.each(expected_calls, fn call ->
      assert String.contains?(generated_c, call), "missing generated call: #{call}"
    end)
  end

  test "process runtime uses Pebble timer hooks under platform guard" do
    project_dir = Path.expand("fixtures/simple_project", __DIR__)
    out_dir = Path.expand("tmp/differential_conformance_runtime_process", __DIR__)
    File.rm_rf!(out_dir)

    assert {:ok, _} =
             Elmc.compile(project_dir, %{
               out_dir: out_dir,
               strip_dead_code: false,
               entry_module: "Main"
             })

    runtime_c = File.read!(Path.join(out_dir, "runtime/elmc_runtime.c"))

    assert String.contains?(runtime_c, "#define ELMC_PEBBLE_PLATFORM 1")
    assert String.contains?(runtime_c, "#ifdef ELMC_PEBBLE_PLATFORM")
    assert String.contains?(runtime_c, "app_timer_register(")
    assert String.contains?(runtime_c, "app_timer_cancel(")
  end
end
