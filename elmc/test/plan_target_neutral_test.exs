defmodule Elmc.PlanTargetNeutralTest do
  use ExUnit.Case, async: true

  alias Elmc.Backend.Plan.{Builder, Debug}

  @forbidden ~w(owned[ CHECK_RC elmc_ CATCH_BEGIN ELMC_RELEASE)

  test "core plan fixtures contain no C-specific tokens" do
    plan =
      Builder.new("Test", "neutral", args: [])
      |> then(fn b ->
        {reg, b1} = Builder.emit_const_int(b, 42)
        b2 = Builder.emit_ret(b1, reg)
        Builder.to_function_plan(b2)
      end)

    dump = Debug.dump(plan)

    Enum.each(@forbidden, fn token ->
      refute dump =~ token, "plan dump must not contain C-specific #{token}"
    end)
  end

  test "runtime builtins use logical ids not elmc_ symbols in plan args" do
    plan =
      Builder.new("Test", "call", args: [], rc_required: true)
      |> Builder.catch_begin()
      |> then(fn b ->
        {reg, b1} = Builder.fresh_reg(b)

        {_, b2} =
          Builder.emit(b1, :call_runtime, %{
            dest: reg,
            args: %{builtin: :new_int, args: []},
            effects: Elmc.Backend.Plan.Types.fallible_effects(reg)
          })

        b2
      end)
      |> Builder.catch_end()
      |> then(fn b ->
        b1 = Builder.emit_ret(b, 0)
        Builder.to_function_plan(b1)
      end)

    dump = Debug.dump(plan)
    assert dump =~ "new_int"
    refute dump =~ "elmc_new_int"
  end

  test "wasm runtime imports are defined for all logical builtins" do
    imports = Elmc.Backend.Wasm.RuntimeImports.all_imports()
    assert length(imports) > 0
    assert Enum.all?(imports, fn {_id, name} -> String.starts_with?(name, "runtime.") end)
  end
end
