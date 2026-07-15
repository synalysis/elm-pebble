defmodule Elmc.PlanDuplicateUnderscoreParamsTest do
  use ExUnit.Case, async: true

  alias Elmc.Backend.Plan.Context
  alias Elmc.Backend.Plan.Lower.Function

  test "unique_param_names disambiguates repeated underscore binders" do
    assert Context.unique_param_names(["_", "_"]) == ["__param_0__", "__param_1__"]
    assert Context.unique_param_names(["x", "x"]) == ["x__0", "x__1"]
    assert Context.unique_param_names(["a", "b"]) == ["a", "b"]
  end

  test "top-level function refs with duplicate underscore args lower distinct closure params" do
    view_decl = %{
      kind: :function,
      name: "view",
      args: ["_", "_"],
      expr: %{
        op: :record_literal,
        fields: [
          %{name: "title", expr: %{op: :literal, value: "ok"}},
          %{name: "body", expr: %{op: :literal, value: []}}
        ]
      }
    }

    route_decl = %{
      kind: :function,
      name: "route",
      args: [],
      expr: %{
        op: :record_literal,
        fields: [
          %{name: "view", expr: %{op: :var, name: "view"}}
        ]
      }
    }

    decl_map = %{
      {"Main", "view"} => view_decl,
      {"Main", "route"} => route_decl
    }

    assert {:ok, plan} = Function.lower(route_decl, "Main", decl_map, rc_required: false)

    [closure_plan | _] = plan.lambdas

    param_loads =
      closure_plan.blocks
      |> Enum.flat_map(& &1.instrs)
      |> Enum.filter(&(&1.op == :load_param))
      |> Enum.map(& &1.args.index)

    assert 0 in param_loads
    assert 1 in param_loads
    assert :ok = Elmc.Backend.Plan.Verify.run(closure_plan)
  end
end
