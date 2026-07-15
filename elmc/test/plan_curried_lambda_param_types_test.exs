defmodule Elmc.PlanCurriedLambdaParamTypesTest do
  use ExUnit.Case, async: true

  alias Elmc.Backend.Plan.Debug
  alias Elmc.Backend.Plan.Lower.Function

  test "buildNoState-like lambda lowers recordArg.view at index 0" do
    build_no_state = %{
      kind: :function,
      name: "buildNoState",
      args: [],
      type:
        "{view : App -> Shared.Model -> View msg} -> Builder -> StatefulRoute routeParams data action {} ()",
      expr: %{
        op: :lambda,
        args: ["recordArg"],
        body: %{
          op: :let_in,
          name: "view",
          value_expr: %{
            op: :field_access,
            arg: %{op: :var, name: "recordArg"},
            field: "view"
          },
          in_expr: %{
            op: :lambda,
            args: ["builderState"],
            body: %{op: :var, name: "builderState"}
          }
        }
      }
    }

    decl_map = %{{"RouteBuilder", "buildNoState"} => build_no_state}

    assert {:ok, plan} =
             Function.lower(build_no_state, "RouteBuilder", decl_map, rc_required: false)

    [outer_closure | _] = plan.lambdas
    dump = Debug.dump(outer_closure)

    assert dump =~ "field_index: \"0 /* view */\""
    refute dump =~ "field_index: \"3 /* view */\""
  end
end
