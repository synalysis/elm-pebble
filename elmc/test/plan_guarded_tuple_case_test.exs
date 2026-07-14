defmodule Elmc.PlanGuardedTupleCaseTest do
  use ExUnit.Case, async: true

  alias Elmc.Backend.Plan.Lower.Function

  test "triple tuple case routes Err arm before wildcard" do
    Process.put(:elmc_constructor_tags, %{
      "Just" => 1,
      "Nothing" => 0,
      "Ok" => 1,
      "Err" => 0
    })

    on_exit(fn -> Process.delete(:elmc_constructor_tags) end)

    decl = %{
      name: "go",
      args: ["triple"],
      expr: %{
        op: :case,
        subject: %{op: :var, name: "triple"},
        branches: [
          %{
            pattern: %{
              kind: :tuple,
              elements: [
                %{kind: :constructor, name: "Just", arg_pattern: %{kind: :var, name: "a"}},
                %{
                  kind: :tuple,
                  elements: [
                    %{kind: :constructor, name: "Just", arg_pattern: %{kind: :var, name: "b"}},
                    %{kind: :constructor, name: "Ok", arg_pattern: %{kind: :var, name: "c"}}
                  ]
                }
              ]
            },
            expr: %{op: :int_literal, value: 1}
          },
          %{
            pattern: %{
              kind: :tuple,
              elements: [
                %{kind: :constructor, name: "Just", arg_pattern: %{kind: :var, name: "a"}},
                %{
                  kind: :tuple,
                  elements: [
                    %{kind: :constructor, name: "Just", arg_pattern: %{kind: :wildcard}},
                    %{kind: :constructor, name: "Err", arg_pattern: %{kind: :wildcard}}
                  ]
                }
              ]
            },
            expr: %{op: :int_literal, value: 2}
          },
          %{pattern: %{kind: :wildcard}, expr: %{op: :int_literal, value: 3}}
        ]
      }
    }

    assert {:ok, plan} = Function.lower(decl, "Main", %{}, rc_required: false)

    blocks =
      plan.blocks
      |> Enum.map(& &1.id)
      |> MapSet.new()

    br_ifs =
      plan.blocks
      |> Enum.flat_map(fn block ->
        case block.terminator do
          {:br_if, then_id, else_id, cond} ->
            [{block.id, then_id, else_id, cond}]

          _ ->
            []
        end
      end)

    assert br_ifs != []

    # Err arm returns 2, wildcard returns 3 — no br_if should jump to a block that only const-true skips Err.
    const_true_br_ifs =
      br_ifs
      |> Enum.filter(fn {_from, _then, _else, cond} ->
        match?(
          %{op: :const_int, args: %{value: 1}},
          find_const_in_block(plan, cond)
        )
      end)

    refute const_true_br_ifs != [] and
             Enum.all?(const_true_br_ifs, fn {_from, then_id, _else, _} ->
               block_returns_int?(plan, then_id, 3)
             end),
           "wildcard arm must not be the br_if then-target for a const-true guard before Err"
  end

  test "triple tuple case routes Err arm when wildcard is not last in source order" do
    Process.put(:elmc_constructor_tags, %{
      "Just" => 1,
      "Nothing" => 0,
      "Ok" => 1,
      "Err" => 0
    })

    on_exit(fn -> Process.delete(:elmc_constructor_tags) end)

    decl = %{
      name: "go",
      args: ["triple"],
      expr: %{
        op: :case,
        subject: %{op: :var, name: "triple"},
        branches: [
          %{
            pattern: %{
              kind: :tuple,
              elements: [
                %{kind: :constructor, name: "Just", arg_pattern: %{kind: :var, name: "a"}},
                %{
                  kind: :tuple,
                  elements: [
                    %{kind: :constructor, name: "Just", arg_pattern: %{kind: :var, name: "b"}},
                    %{kind: :constructor, name: "Ok", arg_pattern: %{kind: :var, name: "c"}}
                  ]
                }
              ]
            },
            expr: %{op: :int_literal, value: 1}
          },
          %{pattern: %{kind: :wildcard}, expr: %{op: :int_literal, value: 3}},
          %{
            pattern: %{
              kind: :tuple,
              elements: [
                %{kind: :constructor, name: "Just", arg_pattern: %{kind: :var, name: "a"}},
                %{
                  kind: :tuple,
                  elements: [
                    %{kind: :constructor, name: "Just", arg_pattern: %{kind: :wildcard}},
                    %{kind: :constructor, name: "Err", arg_pattern: %{kind: :wildcard}}
                  ]
                }
              ]
            },
            expr: %{op: :int_literal, value: 2}
          }
        ]
      }
    }

    assert {:ok, plan} = Function.lower(decl, "Main", %{}, rc_required: false)

    br_ifs =
      plan.blocks
      |> Enum.flat_map(fn block ->
        case block.terminator do
          {:br_if, then_id, else_id, cond} -> [{block.id, then_id, else_id, cond}]
          _ -> []
        end
      end)

    refute Enum.any?(br_ifs, fn {_from, then_id, _else, cond} ->
             match?(%{op: :const_int, args: %{value: 1}}, find_const_in_block(plan, cond)) and
               block_returns_int?(plan, then_id, 3)
           end),
           "wildcard must not be tested before Err when it appears earlier in source order"
  end

  test "tuple2 of record Maybe/Result fields keeps boxed tuple2 not tuple2_ints" do
    decl = %{
      name: "triple",
      args: ["model"],
      expr: %{
        op: :tuple2,
        left: %{
          op: :field_access,
          arg: %{op: :var, name: "model"},
          field: "pendingFrozenViewsUrl"
        },
        right: %{
          op: :field_access,
          arg: %{op: :var, name: "model"},
          field: "pageData"
        }
      }
    }

    assert {:ok, plan} = Function.lower(decl, "Main", %{}, rc_required: false)

    instrs =
      plan.blocks
      |> Enum.flat_map(& &1.instrs)

    refute Enum.any?(instrs, fn instr ->
             match?(%{op: :call_runtime, args: %{builtin: :tuple2_ints}}, instr)
           end)

    assert Enum.any?(instrs, fn instr ->
             match?(%{op: :call_runtime, args: %{builtin: :tuple2}}, instr)
           end)
  end

  defp find_const_in_block(plan, reg) do
    Enum.find_value(plan.blocks, fn block ->
      Enum.find_value(block.instrs, fn
        %{op: :const_int, dest: ^reg} = instr -> instr
        _ -> nil
      end)
    end)
  end

  defp block_returns_int?(plan, block_id, value) do
    case Enum.find(plan.blocks, &(&1.id == block_id)) do
      nil ->
        false

      block ->
        Enum.any?(block.instrs, fn
          %{op: :const_int, args: %{value: ^value}} -> true
          _ -> false
        end)
    end
  end
end
