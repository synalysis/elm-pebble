defmodule Elmc.PlanFloatLiteralTailTest do
  use ExUnit.Case, async: true

  alias Elmc.Backend.Plan.Lower.Function

  test "Float-typed int literal at function tail boxes as new_float" do
    # HeroScene.tickMs : Float / tickMs = 64. Unboxed i32 64 as fn_out collided
    # with handle id 64 → Time.every installed a ~2ms timer → tab crash.
    decl = %{
      name: "tickMs",
      args: [],
      type: "Float",
      expr: %{op: :int_literal, value: 64}
    }

    decl_map = %{{"HeroScene", "tickMs"} => decl}

    assert {:ok, plan} = Function.lower(decl, "HeroScene", decl_map, rc_required: false)

    float_news =
      for block <- plan.blocks,
          %{op: :call_runtime, args: %{builtin: :new_float, literal: lit}} <- block.instrs,
          do: lit

    assert 64.0 in float_news

    refute Enum.any?(plan.blocks, fn block ->
             Enum.any?(block.instrs, &match?(%{op: :const_int, args: %{value: 64}}, &1))
           end)
  end

  test "Int-typed int literal still lowers without crashing" do
    decl = %{
      name: "answer",
      args: [],
      type: "Int",
      expr: %{op: :int_literal, value: 42}
    }

    assert {:ok, _plan} =
             Function.lower(decl, "Main", %{{"Main", "answer"} => decl}, rc_required: true)
  end
end
