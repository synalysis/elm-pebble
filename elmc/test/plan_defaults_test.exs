defmodule Elmc.PlanDefaultsTest do
  use ExUnit.Case, async: true

  alias Elmc.Backend.Plan.{Defaults, Shadow}

  setup do
    prev_mode = Application.get_env(:elmc, :default_plan_ir_mode)
    prev_strict = Application.get_env(:elmc, :default_plan_ir_strict)
    on_exit(fn ->
      Application.put_env(:elmc, :default_plan_ir_mode, prev_mode)
      Application.put_env(:elmc, :default_plan_ir_strict, prev_strict)
    end)

    :ok
  end

  test "test env defaults plan_ir_mode to primary with strict policy" do
    assert Defaults.plan_ir_mode() == :primary
    assert Shadow.plan_ir_mode([]) == :primary
    assert Defaults.apply_defaults(%{})[:plan_ir_strict] == true
  end

  test "unknown plan_ir_mode normalizes to primary" do
    Application.put_env(:elmc, :default_plan_ir_mode, :primary)

    assert Defaults.apply_defaults(%{plan_ir_mode: :off})[:plan_ir_mode] == :primary
    refute Map.has_key?(Defaults.apply_defaults(%{plan_ir_mode: :off}), :plan_ir_mode_off_deprecated)
  end

  test "production default is primary when configured" do
    Application.put_env(:elmc, :default_plan_ir_mode, :primary)
    Application.put_env(:elmc, :default_plan_ir_strict, true)
    assert Defaults.plan_ir_mode() == :primary
    assert Shadow.plan_ir_mode(%{}) == :primary
    assert Defaults.apply_defaults(%{})[:plan_ir_mode] == :primary
    assert Defaults.apply_defaults(%{})[:plan_ir_strict] == true
  end

  test "apply_defaults preserves explicit overrides" do
    Application.put_env(:elmc, :default_plan_ir_mode, :primary)

    assert Defaults.apply_defaults(%{plan_ir_mode: :shadow, plan_ir_strict: false}) == %{
             plan_ir_mode: :shadow,
             plan_ir_strict: false,
             targets: [:c]
           }
  end
end
