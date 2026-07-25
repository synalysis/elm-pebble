defmodule Elmc.PlanCurriedLambdaParamTypesTest do
  use ExUnit.Case, async: true

  alias Elmc.Backend.Plan.Debug
  alias Elmc.Backend.Plan.Lower.Function

  test "buildNoState-like lambda lowers recordArg.view at index 0" do
    # Same-module StatefulRoute (view@3) must not steal `{view}`'s index 0.
    Process.put(:elmc_record_alias_shapes, %{
      {"RouteBuilder", "StatefulRoute"} => [
        "data",
        "action",
        "staticRoutes",
        "view",
        "head",
        "init",
        "update",
        "subscriptions",
        "handleRoute",
        "kind",
        "onAction"
      ]
    })

    on_exit(fn -> Process.delete(:elmc_record_alias_shapes) end)

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

  test "withMetadata combine lambda uses Metadata.statusCode at index 1" do
    # Inferred `{statusCode}` alone is index 0; declared Metadata puts it at 1.
    Process.put(:elmc_record_alias_shapes, %{
      {"BackendTask.Http", "Metadata"} => ["url", "statusCode", "statusText", "headers"]
    })

    on_exit(fn -> Process.delete(:elmc_record_alias_shapes) end)

    with_metadata = %{
      kind: :function,
      name: "withMetadata",
      args: ["combine", "expect"],
      type: "(Metadata -> a -> b) -> Expect error a -> Expect error b",
      expr: %{op: :var, name: "expect"}
    }

    init = %{
      kind: :function,
      name: "init",
      args: ["flags"],
      type: "() -> ( Model, Cmd.Cmd Msg )",
      expr: %{
        op: :qualified_call,
        target: "BackendTask.Http.withMetadata",
        args: [
          %{
            op: :lambda,
            args: ["metadata", "n"],
            body: %{
              op: :field_access,
              arg: %{op: :var, name: "metadata"},
              field: "statusCode"
            }
          },
          %{op: :int_literal, value: 0}
        ]
      }
    }

    decl_map = %{
      {"BackendTask.Http", "withMetadata"} => with_metadata,
      {"Main", "init"} => init
    }

    assert {:ok, plan} = Function.lower(init, "Main", decl_map, rc_required: false)

    combine =
      Enum.find(plan.lambdas, fn lam ->
        Debug.dump(lam) =~ "statusCode"
      end)

    assert combine
    dump = Debug.dump(combine)
    assert dump =~ "field_index: \"1 /* statusCode */\""
    refute dump =~ "field_index: \"0 /* statusCode */\""
  end
end
