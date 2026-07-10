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
end
