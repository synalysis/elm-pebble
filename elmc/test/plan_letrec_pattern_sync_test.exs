defmodule Elmc.PlanLetrecPatternSyncTest do
  use ExUnit.Case, async: true

  alias Elmc.Backend.Plan.Lower.Function
  alias Elmc.Backend.Plan.Lower.Case.TagSwitch

  test "case arm pattern locals sync into letrec forward refs" do
    decl = %{
      name: "go",
      args: ["msg"],
      expr: %{
        op: :case,
        subject: %{op: :var, name: "msg"},
        branches: [
          %{
            pattern: %{
              kind: :constructor,
              tag: 11,
              name: "FrozenViewsReady",
              arg_pattern: %{
                kind: :constructor,
                name: "Just",
                arg_pattern: %{kind: :var, name: "bytes"}
              }
            },
            expr: %{
              op: :let_in,
              name: "a",
              value_expr: %{
                op: :call,
                name: "b",
                args: [%{op: :var, name: "bytes"}]
              },
              in_expr: %{
                op: :let_in,
                name: "b",
                value_expr: %{
                  op: :lambda,
                  args: ["x"],
                  body: %{op: :var, name: "a"}
                },
                in_expr: %{op: :var, name: "a"}
              }
            }
          },
          %{pattern: %{kind: :wildcard}, expr: %{op: :int_literal, value: 0}}
        ]
      }
    }

    assert TagSwitch.branches?(Map.fetch!(decl, :expr).branches)

    assert {:ok, plan} = Function.lower(decl, "Main", %{}, rc_required: false)

    instrs =
      plan.blocks
      |> Enum.flat_map(& &1.instrs)

    ops = Enum.map(instrs, & &1.op)

    assert :forward_ref_set in ops
    assert :forward_ref_load in ops

    ref_sets =
      instrs
      |> Enum.filter(&(&1.op == :forward_ref_set))
      |> Enum.map(&Map.get(&1.args, :ref))

    assert Enum.any?(ref_sets, fn ref ->
             is_binary(ref) and String.contains?(ref, "bytes")
           end)
  end

  test "Just pattern vars sync into letrec forward refs" do
    decl = %{
      name: "go",
      args: ["decoded"],
      expr: %{
        op: :case,
        subject: %{op: :var, name: "decoded"},
        branches: [
          %{
            pattern: %{
              kind: :constructor,
              name: "Just",
              arg_pattern: %{kind: :var, name: "decodedResponse"}
            },
            expr: %{
              op: :let_in,
              name: "a",
              value_expr: %{
                op: :call,
                name: "b",
                args: [%{op: :var, name: "decodedResponse"}]
              },
              in_expr: %{
                op: :let_in,
                name: "b",
                value_expr: %{
                  op: :lambda,
                  args: ["x"],
                  body: %{op: :var, name: "a"}
                },
                in_expr: %{op: :var, name: "decodedResponse"}
              }
            }
          },
          %{pattern: %{kind: :wildcard}, expr: %{op: :int_literal, value: 0}}
        ]
      }
    }

    assert {:ok, plan} = Function.lower(decl, "Main", %{}, rc_required: false)

    instrs =
      plan.blocks
      |> Enum.flat_map(& &1.instrs)

    ref_sets =
      instrs
      |> Enum.filter(&(&1.op == :forward_ref_set))
      |> Enum.map(&Map.get(&1.args, :ref))

    assert Enum.any?(ref_sets, fn ref ->
             is_binary(ref) and String.contains?(ref, "decodedResponse")
           end)
  end

  test "let binding case subject uses local reg not undeclared tail pattern forward ref" do
    decl = %{
      name: "go",
      args: ["x"],
      expr: %{
        op: :let_in,
        name: "pageDataResult",
        value_expr: %{
          op: :call,
          name: "f",
          args: [%{op: :var, name: "pageDataInner"}]
        },
        in_expr: %{
          op: :let_in,
          name: "pageDataInner",
          value_expr: %{op: :var, name: "x"},
          in_expr: %{
            op: :case,
            subject: %{op: :var, name: "pageDataResult"},
            branches: [
              %{
                pattern: %{
                  kind: :constructor,
                  name: "Just",
                  tag: 1,
                  arg_pattern: %{kind: :var, name: "sharedData"}
                },
                expr: %{op: :var, name: "sharedData"}
              },
              %{pattern: %{kind: :wildcard}, expr: %{op: :int_literal, value: 0}}
            ]
          }
        }
      }
    }

    assert {:ok, plan} = Function.lower(decl, "Main", %{}, rc_required: false)

    instrs =
      plan.blocks
      |> Enum.flat_map(& &1.instrs)

    ref_sets =
      instrs
      |> Enum.filter(&(&1.op == :forward_ref_set))
      |> Enum.map(&Map.get(&1.args, :ref))

    ref_loads =
      instrs
      |> Enum.filter(&(&1.op == :forward_ref_load))
      |> Enum.map(&Map.get(&1.args, :ref))

    assert Enum.any?(ref_sets, fn ref ->
             is_binary(ref) and String.contains?(ref, "pageDataResult")
           end)

    refute Enum.any?(ref_loads, fn ref ->
             is_binary(ref) and String.contains?(ref, "sharedData")
           end)
  end
end
