defmodule Elmc.PlanTuple2NonRcConsumeTest do
  use ExUnit.Case, async: true

  alias Elmc.Backend.C.Lower.Function, as: CLowerFunction
  alias Elmc.Backend.Plan.Lower.Function, as: PlanLower

  test "non-RC tuple2 take_value nulls consumed owned slots without releasing them" do
    decl = %{
      name: "pack",
      args: [],
      type: "(Int, String)",
      expr: %{
        op: :tuple2,
        left: %{op: :int_literal, value: 5},
        right: %{op: :string_literal, value: "5"}
      }
    }

    assert {:ok, plan} = PlanLower.lower(decl, "Main", %{}, rc_required: false)
    refute plan.rc_required
    c = CLowerFunction.emit(plan)

    assert c =~ "elmc_tuple2_take_value"
    # Ownership moved into the tuple — only null, never release-after-take.
    refute c =~ ~r/elmc_tuple2_take_value\([^;]+;\s*elmc_release\(owned\[\d+\]\)/
    assert c =~ ~r/elmc_tuple2_take_value\([^;]+;\s*owned\[\d+\] = NULL;/
  end

  test "non-RC nested tuple2 of owned locals does not release transferred slots" do
    # Nested take_value(path, data) then take_value(tag, payload): releasing after the
    # inner take frees payload fields while the outer tuple still holds them.
    decl = %{
      name: "pack",
      args: ["path", "data"],
      type: "String -> String -> (Int, (String, String))",
      expr: %{
        op: :tuple2,
        left: %{op: :int_literal, value: 1},
        right: %{
          op: :tuple2,
          left: %{op: :var, name: "path"},
          right: %{op: :var, name: "data"}
        }
      }
    }

    assert {:ok, plan} = PlanLower.lower(decl, "MainMsgPathSimple", %{}, rc_required: false)
    c = CLowerFunction.emit(plan)
    assert c =~ "elmc_tuple2_take_value"
    refute c =~ ~r/elmc_tuple2_take_value\([^;]+;\s*\n\s*elmc_release\(owned\[\d+\]\)/
  end
end
