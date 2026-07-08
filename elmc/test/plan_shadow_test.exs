defmodule Elmc.PlanShadowTest do
  use ExUnit.Case, async: true

  alias Elmc.Backend.Plan.Shadow

  test "plan_ir_mode defaults to off" do
    assert Shadow.plan_ir_mode([]) == :off
  end

  test "shadow mode is recognized from opts" do
    assert Shadow.plan_ir_mode(plan_ir_mode: :shadow) == :shadow
    assert Shadow.plan_ir_mode(%{plan_ir_mode: :primary}) == :primary
  end

  test "shadow verify accepts simple int literal function" do
    decl = %{
      name: "init",
      args: [],
      expr: %{op: :int_literal, value: 0}
    }

    assert :ok =
             Shadow.maybe_verify_function(decl, "Main", %{},
               plan_ir_mode: :shadow,
               rc_required: false
             )
  end

  test "shadow stats track verify outcomes" do
    Shadow.reset_stats()

    decl = %{
      name: "init",
      args: [],
      expr: %{op: :int_literal, value: 0}
    }

    assert :ok =
             Shadow.maybe_verify_function(decl, "Main", %{},
               plan_ir_mode: :shadow,
               rc_required: false
             )

    assert %{ok: 1, skipped: 0, error: 0} = Shadow.shadow_stats()
  end
end
