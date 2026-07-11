defmodule Elmc.PlanDefaultsTest do
  use ExUnit.Case, async: true

  alias Elmc.Backend.Plan.{Defaults, Shadow}

  setup do
    prev = Application.get_env(:elmc, :default_plan_ir_mode)
    on_exit(fn -> Application.put_env(:elmc, :default_plan_ir_mode, prev) end)
    :ok
  end

  test "test env defaults plan_ir_mode to primary" do
    assert Defaults.plan_ir_mode() == :primary
    assert Shadow.plan_ir_mode([]) == :primary
  end

  test "legacy off mode when configured" do
    Application.put_env(:elmc, :default_plan_ir_mode, :off)
    assert Defaults.plan_ir_mode() == :off
    assert Shadow.plan_ir_mode([]) == :off
  end

  test "production default is primary when configured" do
    Application.put_env(:elmc, :default_plan_ir_mode, :primary)
    assert Defaults.plan_ir_mode() == :primary
    assert Shadow.plan_ir_mode(%{}) == :primary
    assert Defaults.apply_defaults(%{})[:plan_ir_mode] == :primary
    assert Defaults.apply_defaults(%{})[:plan_ir_strict] == true
  end

  test "apply_defaults preserves explicit overrides" do
    Application.put_env(:elmc, :default_plan_ir_mode, :primary)

    assert Defaults.apply_defaults(%{plan_ir_mode: :shadow, plan_ir_strict: false}) == %{
             plan_ir_mode: :shadow,
             plan_ir_strict: false
           }
  end

  test "explicit plan_ir_mode off records marker for legacy diagnostic" do
    Application.put_env(:elmc, :default_plan_ir_mode, :primary)

    assert Defaults.apply_defaults(%{plan_ir_mode: :off})[:plan_ir_mode_explicit_off] == true
    refute Map.has_key?(Defaults.apply_defaults(%{}), :plan_ir_mode_explicit_off)
  end
end
