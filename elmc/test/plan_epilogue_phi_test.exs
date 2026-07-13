defmodule Elmc.PlanEpiloguePhiTest do
  use ExUnit.Case, async: true

  alias Elmc.Backend.C.Lower.Function, as: CLowerFunction
  alias Elmc.Backend.Plan.Lower.Function, as: PlanLower
  alias Elmc.Backend.Plan.{EpilogueRelease, Optimize}

  test "if/else phi merge epilogue does not release arm registers" do
    decl = %{
      name: "pick",
      args: ["n"],
      expr: %{
        op: :if,
        cond: %{
          op: :compare,
          kind: :lt,
          left: %{op: :var, name: "n"},
          right: %{op: :int_literal, value: 0}
        },
        then_expr: %{op: :int_literal, value: 1},
        else_expr: %{op: :int_literal, value: 2}
      }
    }

    assert {:ok, plan} = PlanLower.lower(decl, "Main", %{}, rc_required: true)

    plan = plan |> EpilogueRelease.run() |> Optimize.run()
    c = CLowerFunction.emit(plan)

    refute c =~ ~r/\}\n\s*elmc_release\(owned\[\d+\]\);\n\s*owned\[\d+\] = NULL;\n\s*elmc_release\(owned\[\d+\]\)/
  end

  test "maybe if merge epilogue does not release phi arm slots after transfer" do
    decl = %{
      name: "slot",
      args: ["m"],
      expr: %{
        op: :case,
        subject: %{op: :var, name: "m"},
        branches: [
          %{
            pattern: %{kind: :constructor, name: "Nothing"},
            expr: %{op: :constructor_call, target: "Maybe.Nothing", args: []}
          },
          %{
            pattern: %{kind: :var, name: "x"},
            expr: %{op: :var, name: "x"}
          }
        ]
      }
    }

    assert {:ok, plan} = PlanLower.lower(decl, "Main", %{}, rc_required: true)

    plan = plan |> EpilogueRelease.run() |> Optimize.run()
    c = CLowerFunction.emit(plan)

    refute c =~ ~r/elmc_plan_block_\d+:\n\s*if \(plan_native_bool_\d+\)[\s\S]*?\}\n\s*elmc_release\(owned\[\d+\]\);\n\s*owned\[\d+\] = NULL;\n\s*elmc_release\(owned\[\d+\]\)/
  end
end
