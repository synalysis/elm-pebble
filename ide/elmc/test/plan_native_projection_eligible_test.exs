defmodule Elmc.PlanNativeProjectionEligibleTest do
  use ExUnit.Case, async: true

  alias Elmc.Backend.CCodegen.PlanNativeProjection
  alias Elmc.Backend.Plan

  test "direct plan-primary Bool RC helpers stay eligible for native projection" do
    decl = %{
      name: "showCorners",
      args: ["model"],
      type: "Model -> Bool",
      ownership: [:borrow_arg, :retain_result],
      expr: %{op: :bool_literal, value: true}
    }

    decl_map = %{{"Main", "showCorners"} => decl}

    Process.put(:elmc_codegen_opts, %{plan_ir_mode: :primary})
    Process.put(:elmc_program_decls, decl_map)
    Process.put(:elmc_rc_required, MapSet.new([{"Main", "showCorners"}]))

    on_exit(fn ->
      Process.delete(:elmc_codegen_opts)
      Process.delete(:elmc_program_decls)
      Process.delete(:elmc_rc_required)
      Process.delete(:elmc_plan_primary_lowered_cache)
      Process.delete(:elmc_plan_native_returns)
      Process.delete(:elmc_plan_native_value_returns)
    end)

    assert Plan.primary_lowered?(decl, "Main", decl_map)
    assert PlanNativeProjection.eligible?(decl, "Main", decl_map)
  end

  test "native value-return helpers skip projection shims" do
    decl = %{
      name: "nativeBool",
      args: ["model"],
      type: "Model -> Bool",
      ownership: [:borrow_arg],
      expr: %{op: :bool_literal, value: true}
    }

    Process.put(
      :elmc_plan_native_value_returns,
      MapSet.new([{"Main", "nativeBool"}])
    )

    on_exit(fn ->
      Process.delete(:elmc_plan_native_value_returns)
    end)

    refute PlanNativeProjection.eligible?(decl, "Main", %{})
  end
end
