defmodule Elmc.SpecialValuesCmdAliasTest do
  use ExUnit.Case, async: true

  alias Elmc.Backend.Plan.Lower.SpecialValues.Core
  alias Elmc.Backend.Plan.Lower.SpecialValues.Dispatcher
  alias Elmc.Backend.CCodegen.UnsupportedSurface

  setup do
    Process.put(:elmc_compile_warnings, [])
    Process.put(:elmc_codegen_opts, %{plan_ir_mode: :primary, plan_ir_strict: true})

    on_exit(fn ->
      Process.delete(:elmc_compile_warnings)
      Process.delete(:elmc_codegen_opts)
    end)

    :ok
  end

  test "package-qualified Random.generate with foldable int encodes tag and bounds" do
    assert Core.normalize_special_target("Pkg.app.Random.generate") == "Random.generate"

    assert %{
             op: :pebble_cmd,
             kind: %{op: :c_int_expr, value: "ELMC_PEBBLE_CMD_RANDOM_GENERATE"},
             params: [_tag, %{op: :int_literal, value: 1}, %{op: :int_literal, value: 16}]
           } =
             Dispatcher.special_value_from_target("Pkg.app.Random.generate", [
               %{op: :var, name: "RandomGenerated"},
               %{
                 op: :qualified_call,
                 target: "Random.int",
                 args: [%{op: :int_literal, value: 1}, %{op: :int_literal, value: 16}]
               }
             ])
  end

  test "package-qualified Random.generate with opaque generator records unsupported_cmd" do
    assert %{
             op: :unsupported,
             kind: :cmd,
             target: "Random.generate"
           } =
             Dispatcher.special_value_from_target("Pkg.app.Random.generate", [
               %{op: :var, name: "RandomGenerated"},
               %{op: :call, name: "ignore", args: []}
             ])

    [diag] = UnsupportedSurface.compile_warnings(plan_ir_mode: :primary, plan_ir_strict: true)

    assert diag["code"] == "unsupported_cmd"
    assert diag["message"] =~ "Random.generate generator not foldable"
  end
end
