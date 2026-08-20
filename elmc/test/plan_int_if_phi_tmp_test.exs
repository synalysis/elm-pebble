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

  test "truthy_native {:reg,_} phi arms are not dropped (no dangling tmp_)" do
    blocks = [
      %{
        id: 0,
        instrs: [
          %{
            op: :phi,
            dest: 19,
            args: %{
              then: 17,
              else: 18,
              cond: 13,
              truthy_native: true,
              then_shape: {:reg, 17},
              else_shape: {:const_int, 0},
              then_arm_block: 3,
              else_arm_block: 4
            }
          }
        ],
        terminator: :none
      }
    ]

    drops = TruthyNative.phi_arm_drop_instrs(blocks)
    refute MapSet.member?(drops, {17, 3}),
           "must not drop {:reg,_} then arm (would emit undeclared tmp_17)"
    assert MapSet.member?(drops, {18, 4})
  end

  test "truthy_native boxed phi with boxed cond reconstructs dropped const arm" do
    # Cond comes from a call (boxed Bool). Optimize stamps truthy_native and drops
    # const True/False arms — emit must use shapes, not undeclared tmp_N.
    decls = %{
      "flag" => %{
        name: "flag",
        args: [],
        expr: %{op: :bool_literal, value: true}
      },
      "pick" => %{
        name: "pick",
        args: [],
        expr: %{
          op: :if,
          cond: %{op: :call, target: "flag", args: []},
          then_expr: %{op: :bool_literal, value: true},
          else_expr: %{op: :bool_literal, value: false}
        }
      }
    }

    assert {:ok, plan} = PlanLower.lower(decls["pick"], "Main", decls, rc_required: true)
    phi =
      plan.blocks
      |> Enum.flat_map(& &1.instrs)
      |> Enum.find(&(Map.get(&1, :op) == :phi))

    assert phi
    assert Map.get(phi.args, :truthy_native) == true

    c = CLower.emit(plan)
    refute c =~ ~r/\btmp_\d+\b/, "must not reference dropped arm as tmp_:\n#{c}"
    assert c =~ "elmc_new_bool(", "expected shape-based bool boxing:\n#{c}"
  end

  test "truthy_native boxed phi boxes native-bool {:reg,_} arms (no elmc_retain on _Bool)" do
    # Nested `if a then (if b then c else False) else False` lowers to truthy_native
    # phis whose then_shape is {:reg, native_bool}. Merging into a boxed *out must
    # ephemeral-box the C bool — never `elmc_retain(plan_native_bool_N)`.
    decl = %{
      name: "and3",
      args: ["a", "b", "c"],
      expr: %{
        op: :if,
        cond: %{op: :var, name: "a"},
        then_expr: %{
          op: :if,
          cond: %{op: :var, name: "b"},
          then_expr: %{op: :var, name: "c"},
          else_expr: %{op: :bool_literal, value: false}
        },
        else_expr: %{op: :bool_literal, value: false}
      }
    }

    assert {:ok, plan} = PlanLower.lower(decl, "Main", %{}, rc_required: true)
    c = CLower.emit(plan)

    refute c =~ ~r/elmc_retain\(\s*plan_native_bool_\d+\s*\)/,
           "must not retain a C bool into an owned slot:\n#{c}"

    assert c =~ "elmc_new_bool(",
           "expected ephemeral bool boxing when publishing native bool to *out:\n#{c}"
  end
end
