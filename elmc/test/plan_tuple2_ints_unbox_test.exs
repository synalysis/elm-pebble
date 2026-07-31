defmodule Elmc.PlanTuple2IntsUnboxTest do
  use ExUnit.Case, async: false

  alias Elmc.Backend.C.Lower.Function, as: CLowerFunction
  alias Elmc.Backend.Plan.Lower.Function, as: PlanLower

  @moduletag :plan_surface

  test "let-bound (Int,Int) used only via projections never heap-allocates" do
    decl = %{
      name: "sumPair",
      args: [],
      type: "Int",
      expr: %{
        op: :let_in,
        name: "p",
        value_expr: %{
          op: :tuple2,
          left: %{op: :int_literal, value: 3},
          right: %{op: :int_literal, value: 4}
        },
        in_expr: %{
          op: :call,
          name: "__add__",
          args: [
            %{op: :tuple_first_expr, arg: %{op: :var, name: "p"}},
            %{op: :tuple_second_expr, arg: %{op: :var, name: "p"}}
          ]
        }
      }
    }

    assert {:ok, plan} = PlanLower.lower(decl, "Main", %{}, rc_required: true)
    c = CLowerFunction.emit(plan)
    refute c =~ "elmc_tuple2_ints"
    refute c =~ "elmc_tuple_first"
    refute c =~ "elmc_tuple_second"
    assert c =~ "3"
    assert c =~ "4"
  end

  test "Tuple.first on immediate (Int,Int) peels without heap tuple" do
    decl = %{
      name: "fst",
      args: [],
      type: "Int",
      expr: %{
        op: :tuple_first_expr,
        arg: %{
          op: :tuple2,
          left: %{op: :int_literal, value: 11},
          right: %{op: :int_literal, value: 22}
        }
      }
    }

    assert {:ok, plan} = PlanLower.lower(decl, "Main", %{}, rc_required: true)
    c = CLowerFunction.emit(plan)
    refute c =~ "elmc_tuple2"
    refute c =~ "elmc_tuple_first"
    assert c =~ "11"
  end

  test "escaping (Int,Int) return still uses elmc_tuple2_ints" do
    decl = %{
      name: "pair",
      args: [],
      expr: %{
        op: :tuple2,
        left: %{op: :int_literal, value: 1},
        right: %{op: :int_literal, value: 2}
      }
    }

    assert {:ok, plan} = PlanLower.lower(decl, "Main", %{}, rc_required: true)
    c = CLowerFunction.emit(plan)
    assert c =~ "elmc_tuple2_ints"
  end

  test "Tuple.mapFirst on immediate int pair avoids elmc_tuple_map_first" do
    decl = %{
      name: "bump",
      args: [],
      expr: %{
        op: :qualified_call,
        target: "Tuple.mapFirst",
        args: [
          %{
            op: :lambda,
            args: ["x"],
            body: %{
              op: :call,
              name: "__add__",
              args: [%{op: :var, name: "x"}, %{op: :int_literal, value: 1}]
            }
          },
          %{
            op: :tuple2,
            left: %{op: :int_literal, value: 10},
            right: %{op: :int_literal, value: 20}
          }
        ]
      }
    }

    assert {:ok, plan} = PlanLower.lower(decl, "Main", %{}, rc_required: true)
    c = CLowerFunction.emit(plan)
    refute c =~ "elmc_tuple_map_first"
    assert c =~ "elmc_tuple2_ints"
  end
end
