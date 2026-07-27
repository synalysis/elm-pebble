defmodule Elmc.PlanCharSwitchTest do
  use ExUnit.Case, async: true

  alias Elmc.Backend.Plan.Lower.Function

  test "lowers case on Char with int switch on char codes" do
    decl = %{
      name: "formatSample",
      args: ["char", "length"],
      expr: %{
        op: :case,
        subject: %{op: :var, name: "char"},
        branches: [
          %{
            pattern: %{kind: :char, value: ?y},
            expr: %{op: :string_literal, value: "year"}
          },
          %{
            pattern: %{kind: :char, value: ?M},
            expr: %{op: :string_literal, value: "month"}
          },
          %{
            pattern: %{kind: :wildcard},
            expr: %{op: :string_literal, value: ""}
          }
        ]
      }
    }

    decl_map = %{{"Sample", "formatSample"} => decl}

    assert {:ok, plan} = Function.lower(decl, "Sample", decl_map, web: true)
    assert plan.blocks != []
  end
end
