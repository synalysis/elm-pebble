defmodule Elmc.UnionStringCaseTest do
  use ExUnit.Case, async: true

  alias Elmc.Backend.CCodegen.UnionStringCase

  test "try_emit recognizes union string case IR" do
    expr = %{
      op: :case,
      subject: %{op: :var, name: "direction"},
      branches: [
        %{
          pattern: %{kind: :constructor, name: "North", tag: 1, arg_pattern: nil},
          expr: %{op: :string_literal, value: "N"}
        },
        %{
          pattern: %{kind: :constructor, name: "East", tag: 2, arg_pattern: nil},
          expr: %{op: :string_literal, value: "E"}
        }
      ]
    }

    assert {:ok, body, [], :rc_native} =
             UnionStringCase.try_emit("Main", "directionString", expr, %{
               {"Main", "directionString"} => %{args: ["direction"]}
             })
    assert body =~ "switch ("
    assert body =~ "native_str_immortal_"
    refute body =~ "goto elmc_plan_block_"
  end

  test "try_emit refuses nullary functions with computed case subjects" do
    expr = %{
      op: :case,
      subject: %{
        op: :qualified_call,
        target: "Basics.compare",
        args: [
          %{op: :string_literal, value: "a"},
          %{op: :string_literal, value: "b"}
        ]
      },
      branches: [
        %{
          pattern: %{kind: :constructor, name: "LT", tag: 0, arg_pattern: nil},
          expr: %{op: :string_literal, value: "less"}
        },
        %{
          pattern: %{kind: :constructor, name: "EQ", tag: 1, arg_pattern: nil},
          expr: %{op: :string_literal, value: "equal"}
        },
        %{
          pattern: %{kind: :constructor, name: "GT", tag: 2, arg_pattern: nil},
          expr: %{op: :string_literal, value: "greater"}
        }
      ]
    }

    assert :error =
             UnionStringCase.try_emit("CompareBranch", "main", expr, %{
               {"CompareBranch", "main"} => %{args: []}
             })
  end
end
