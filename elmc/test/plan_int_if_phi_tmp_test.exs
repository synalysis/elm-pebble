defmodule Elmc.PlanIntIfPhiTmpTest do
  use ExUnit.Case, async: true

  alias Elmc.Backend.C.Lower.Function, as: CLower
  alias Elmc.Backend.Plan.Lower.Function, as: PlanLower
  alias Elmc.Backend.Plan.TruthyNative

  test "TruthyNative requires bool_lit for const_int 0/1 shapes" do
    bool_instrs = [
      %{op: :const_int, dest: 1, args: %{value: 1, bool_lit: true}},
      %{op: :const_int, dest: 2, args: %{value: 0, bool_lit: true}}
    ]

    int_instrs = [
      %{op: :const_int, dest: 1, args: %{value: 1}},
      %{op: :const_int, dest: 2, args: %{value: 0}}
    ]

    assert {true, {:const_int, 1}, {:const_int, 0}} =
             TruthyNative.phi_shapes?(bool_instrs, 1, 2)

    assert {false, :unknown, :unknown} = TruthyNative.phi_shapes?(int_instrs, 1, 2)
  end

  test "if/else Int 1/0 uses native_int_phi and does not emit undeclared tmp_ regs" do
    decl = %{
      name: "pick",
      args: ["flag"],
      expr: %{
        op: :if,
        cond: %{op: :var, name: "flag"},
        then_expr: %{op: :int_literal, value: 1},
        else_expr: %{op: :int_literal, value: 0}
      }
    }

    assert {:ok, plan} = PlanLower.lower(decl, "Main", %{}, rc_required: true)

    phi =
      plan.blocks
      |> Enum.flat_map(& &1.instrs)
      |> Enum.find(&(&1.op == :phi))

    assert phi
    assert Map.get(phi.args, :native_int_phi) == true
    refute Map.get(phi.args, :truthy_native) == true

    c = CLower.emit(plan)
    refute c =~ ~r/\btmp_\d+\b/
  end
end
