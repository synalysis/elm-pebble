defmodule Elmc.PlanBoolCtorHeapTest do
  use ExUnit.Case, async: true

  alias Elmc.Backend.Plan.Lower.Function

  test "True/False passed to Bool params are coerced to new_bool heap handles" do
    # Scene3d.cylinder passes True False into Entity.cylinder. Raw i32.const 1
    # collides with immortal UNIT on WASM; retain rematerializes True as Int(0).
    decl = %{
      name: "passBools",
      args: ["material", "cyl"],
      type: "material -> cyl -> out",
      expr: %{
        op: :qualified_call,
        target: "Scene3d.Entity.cylinder",
        args: [
          %{op: :constructor_call, target: "True", args: []},
          %{op: :constructor_call, target: "False", args: []},
          %{op: :var, name: "material"},
          %{op: :var, name: "cyl"}
        ]
      }
    }

    decl_map = %{
      {"Main", "passBools"} => decl,
      {"Scene3d.Entity", "cylinder"} => %{
        name: "cylinder",
        args: ["a", "b", "c", "d"],
        type: "Bool -> Bool -> material -> cyl -> out",
        expr: %{op: :var, name: "a"}
      }
    }

    assert {:ok, plan} = Function.lower(decl, "Main", decl_map, rc_required: false)

    bool_news =
      for block <- plan.blocks,
          instr <- block.instrs,
          match?(%{op: :call_runtime, args: %{builtin: :new_bool}}, instr),
          do: instr

    assert length(bool_news) >= 2,
           "expected CallCoerce to emit new_bool for True/False args; got #{inspect(bool_news)}"
  end
end
