defmodule Elmc.WasmLowerTest do
  use ExUnit.Case, async: true

  alias Elmc.Backend.Plan.Builder
  alias Elmc.Backend.Wasm.Lower

  @forbidden ~w(owned[ CHECK_RC CATCH_BEGIN ELMC_RELEASE)

  test "lower emits WAT module without C-specific tokens" do
    plan =
      Builder.new("Test", "wasm", args: [], rc_required: true)
      |> Builder.catch_begin()
      |> then(fn b ->
        {reg, b1} = Builder.fresh_reg(b)

        {_, b2} =
          Builder.emit(b1, :call_runtime, %{
            dest: reg,
            args: %{builtin: :new_int, args: [], literal: 7},
            effects: Elmc.Backend.Plan.Types.fallible_effects(reg)
          })

        b2
      end)
      |> Builder.catch_end()
      |> then(fn b ->
        b1 = Builder.emit_ret(b, 0)
        Builder.to_function_plan(b1)
      end)

    assert {:ok, module_map} = Lower.lower(plan)
    wat = Lower.render_wat(module_map)

    Enum.each(@forbidden, fn token ->
      refute wat =~ token, "WAT must not contain C-specific #{token}"
    end)

    assert wat =~ "(module"
    assert wat =~ "runtime_new_int"
  end

  test "lower_many links multiple functions" do
    plan_a =
      Builder.new("A", "f", args: [])
      |> then(fn b ->
        {reg, b1} = Builder.emit_const_int(b, 1)
        b2 = Builder.emit_ret(b1, reg)
        Builder.to_function_plan(b2)
      end)

    plan_b =
      Builder.new("B", "g", args: [])
      |> then(fn b ->
        {reg, b1} = Builder.emit_const_int(b, 2)
        b2 = Builder.emit_ret(b1, reg)
        Builder.to_function_plan(b2)
      end)

    assert {:ok, module_map} = Lower.lower_many([plan_a, plan_b])
    wat = Lower.render_wat(module_map)
    assert wat =~ "elmc_fn_A_f"
    assert wat =~ "elmc_fn_B_g"
  end
end
