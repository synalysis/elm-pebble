defmodule Elmc.PlanTupleParamBindTest do
  use ExUnit.Case, async: false

  alias Elmc.Backend.Plan.Lower.Function
  alias Elmc.Backend.Plan.TupleParamBind

  @moduletag :plan_surface

  test "tuple_element_names splits synthetic desugar param names" do
    assert TupleParamBind.tuple_element_names("weight__value", 2) == ["weight", "value"]
    assert TupleParamBind.tuple_element_names("x_y", 2) == ["x", "y"]
  end

  test "getByWeight-shaped decl lowers with tuple param projections" do
    decl = %{
      name: "getByWeight",
      args: ["weight__value", "others", "countdown"],
      type: "(Float, a) -> List (Float, a) -> Float -> a",
      expr: %{
        op: :case,
        subject: "others",
        branches: [
          %{
            pattern: %{kind: :constructor, name: "[]", resolved_name: "[]"},
            expr: %{op: :var, name: "value"}
          },
          %{
            pattern: %{
              kind: :constructor,
              name: "::",
              resolved_name: "::",
              arg_pattern: %{
                kind: :tuple,
                elements: [
                  %{kind: :var, name: "second"},
                  %{kind: :var, name: "otherOthers"}
                ]
              }
            },
            expr: %{
              op: :if,
              cond: %{
                op: :compare,
                kind: :lte,
                left: %{op: :var, name: "countdown"},
                right: %{
                  op: :qualified_call,
                  target: "Basics.abs",
                  args: [%{op: :var, name: "weight"}]
                }
              },
              then_expr: %{op: :var, name: "value"},
              else_expr: %{
                op: :qualified_call,
                target: "Random.getByWeight",
                args: [
                  %{op: :var, name: "second"},
                  %{op: :var, name: "otherOthers"},
                  %{
                    op: :call,
                    name: "__sub__",
                    args: [
                      %{op: :var, name: "countdown"},
                      %{
                        op: :qualified_call,
                        target: "Basics.abs",
                        args: [%{op: :var, name: "weight"}]
                      }
                    ]
                  }
                ]
              }
            }
          }
        ]
      }
    }

    decl_map = %{{"Random", "getByWeight"} => decl}

    assert {:ok, plan} = Function.lower(decl, "Random", decl_map, rc_required: false)
    assert inspect(plan.blocks) =~ "tuple_proj"
  end
end
