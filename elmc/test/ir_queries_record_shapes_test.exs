defmodule Elmc.IRQueriesRecordShapesTest do
  use ExUnit.Case, async: true

  alias Elmc.Backend.CCodegen.IRQueries
  alias Elmc.Backend.Plan.Lower.Record
  alias Elmc.Backend.Plan.Context
  alias ElmEx.IR

  test "union constructor record shapes preserve declaration order not alphabetical sort" do
    ir = %IR{
      modules: [
        %{
          name: "Internal.Cartesian.Layout",
          declarations: [],
          unions: %{
            "Layout" => %{
              payload_specs: %{
                "Leaf" => "{ value : a, extent : Extent }"
              }
            }
          }
        }
      ]
    }

    assert IRQueries.union_constructor_record_shapes(ir) == [
             {{"Internal.Cartesian.Layout", "Leaf"}, ["value", "extent"]}
           ]

    inline = IRQueries.inline_record_literal_shape_map(ir)
    assert inline[{"Internal.Cartesian.Layout", "Leaf"}] == ["value", "extent"]
  end

  test "inline record shapes preserve declaration order from nested type alias fields" do
    ir = %IR{
      modules: [
        %{
          name: "Pages.Internal.Platform",
          declarations: [
            %{
              kind: :type_alias,
              name: "Model",
              expr: %{
                op: :record_alias,
                fields: ["pageData"],
                field_types: %{
                  "pageData" =>
                    "Result String { userModel : userModel , pageData : pageData , sharedData : sharedData , actionData : Maybe actionData }"
                }
              }
            }
          ],
          unions: %{}
        }
      ]
    }

    shapes = IRQueries.inline_record_literal_shape_map(ir)

    assert shapes[{"Pages.Internal.Platform", "Model_pageData"}] == [
             "userModel",
             "pageData",
             "sharedData",
             "actionData"
           ]

    Process.put(:elmc_inline_record_literal_shapes, shapes)

    on_exit(fn -> Process.delete(:elmc_inline_record_literal_shapes) end)

    fields = [
      %{name: "userModel", expr: %{op: :int_literal, value: 1}},
      %{name: "sharedData", expr: %{op: :int_literal, value: 2}},
      %{name: "pageData", expr: %{op: :int_literal, value: 3}},
      %{name: "actionData", expr: %{op: :int_literal, value: 4}}
    ]

    ctx = %Context{module: "Pages.Internal.Platform"}

    canonical = Record.canonicalize_literal_fields(fields, ctx)
    names = Enum.map(canonical, & &1.name)

    assert names == ["userModel", "pageData", "sharedData", "actionData"]
  end

  test "ProgramConfig.init resolves to field index 0 on extensible config param" do
    shapes = %{
      {"Pages.ProgramConfig", "ProgramConfig"} => [
        "init",
        "update",
        "subscriptions",
        "sharedData",
        "data",
        "action",
        "onActionData",
        "view"
      ],
      {"RouteBuilder", "StatefulRoute"} => [
        "route",
        "init",
        "update",
        "view",
        "subscriptions",
        "data"
      ]
    }

    Process.put(:elmc_record_alias_shapes, shapes)

    on_exit(fn -> Process.delete(:elmc_record_alias_shapes) end)

    ctx = %Context{
      module: "Pages.Internal.Platform",
      function_name: "update",
      params: ["config", "appMsg", "model"],
      decl_map: %{
        {"Pages.Internal.Platform", "update"} => %{
          type:
            "ProgramConfig userMsg userModel route pageData actionData sharedData userEffect (Msg userMsg pageData actionData sharedData errorPage) errorPage -> Msg userMsg pageData actionData sharedData errorPage -> Model userModel pageData actionData sharedData -> (Model userModel pageData actionData sharedData, Effect userMsg pageData actionData sharedData userEffect errorPage)"
        }
      }
    }

    assert Record.resolve_field_index_int("init", ctx, %{op: :var, name: "config"}) == {:ok, 0}
    assert Record.resolve_field_index_int("action", ctx, %{op: :var, name: "config"}) == {:ok, 5}
  end

  test "inner Ok payload fields prefer inline shape over outer Platform.Model alias" do
    Process.put(:elmc_record_alias_shapes, %{
      {"Pages.Internal.Platform", "Model"} => [
        "key",
        "url",
        "currentPath",
        "ariaNavigationAnnouncement",
        "pageData",
        "notFound",
        "userFlags",
        "transition",
        "nextTransitionKey",
        "inFlightFetchers",
        "pageFormState",
        "pendingRedirect",
        "pendingData",
        "pendingFrozenViewsUrl"
      ]
    })

    Process.put(:elmc_inline_record_literal_shapes, %{
      {"Pages.Internal.Platform", "Model_pageData"} => [
        "userModel",
        "pageData",
        "sharedData",
        "actionData"
      ]
    })

    on_exit(fn ->
      Process.delete(:elmc_record_alias_shapes)
      Process.delete(:elmc_inline_record_literal_shapes)
    end)

    ctx = %Context{
      module: "Pages.Internal.Platform",
      function_name: "mainView",
      decl_map: %{}
    }

    assert Record.resolve_field_index_int("pageData", ctx, nil) == {:ok, 1}
    assert Record.resolve_field_index_int("sharedData", ctx, nil) == {:ok, 2}
    assert Record.resolve_field_index_int("actionData", ctx, nil) == {:ok, 3}
    assert Record.resolve_field_index_int("userModel", ctx, nil) == {:ok, 0}

    model_ctx =
      put_in(
        ctx.local_types,
        %{"model" => "Pages.Internal.Platform.Model userModel pageData actionData sharedData"}
      )

    assert Record.resolve_field_index_int("pageData", model_ctx, %{op: :var, name: "model"}) ==
             {:ok, 4}

    param_ctx =
      %{
        ctx
        | params: ["model"],
          local_types: %{},
          decl_map: %{
            {"Pages.Internal.Platform", "mainView"} => %{
              args: ["model"],
              type:
                "Pages.Internal.Platform.Model userModel pageData actionData sharedData -> {title : String, body : List (Html msg)}"
            }
          }
      }

    assert Record.resolve_field_index_int("pageData", param_ctx, %{op: :var, name: "model"}) ==
             {:ok, 4}
  end

  test "zero-arg callee record literal resolves Shared.template.view to index 2" do
    ctx = %Context{
      module: "Main",
      function_name: "view",
      decl_map: %{
        {"Shared", "template"} => %{
          expr: %{
            op: :record_literal,
            fields: [
              %{name: "init", expr: %{op: :var, name: "init"}},
              %{name: "update", expr: %{op: :var, name: "update"}},
              %{name: "view", expr: %{op: :var, name: "view"}},
              %{name: "data", expr: %{op: :var, name: "data"}},
              %{name: "subscriptions", expr: %{op: :var, name: "subscriptions"}},
              %{name: "onPageChange", expr: %{op: :int_literal, value: 0}}
            ]
          }
        }
      }
    }

    base_call = %{op: :qualified_call, target: "Shared.template", args: []}
    base_ref = %{op: :qualified_ref, target: "Shared.template"}

    base_field_access = %{
      op: :field_access,
      arg: base_ref,
      field: "view"
    }

    for base <- [base_call, base_ref, base_field_access] do
      assert Record.resolve_field_index_int("init", ctx, base) == {:ok, 0}
      assert Record.resolve_field_index_int("view", ctx, base) == {:ok, 2}
      assert Record.resolve_field_index_int("onPageChange", ctx, base) == {:ok, 5}
    end
  end

  test "StatelessRoute binding resolves route.view to StatefulRoute index 3" do
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

    ctx = %Context{
      module: "Main",
      function_name: "view",
      decl_map: %{
        {"Route.Index", "route"} => %{
          type: "StatelessRoute RouteParams Data ActionData"
        }
      }
    }

    base = %{
      op: :field_access,
      arg: %{op: :qualified_ref, target: "Route.Index.route"},
      field: "view"
    }

    assert Record.resolve_field_index_int("view", ctx, base) == {:ok, 3}
    assert Record.resolve_field_index_int("data", ctx, base) == {:ok, 0}
    assert Record.resolve_field_index_int("head", ctx, base) == {:ok, 4}
  end

  test "maybePagePath payload fields use declaration order not alphabetical sort" do
    Process.put(:elmc_inline_record_literal_shapes, %{
      {"SharedTemplate", "SharedTemplate_init"} => ["path", "metadata", "pageUrl"]
    })

    on_exit(fn -> Process.delete(:elmc_inline_record_literal_shapes) end)

    ctx = %Context{
      module: "Main",
      function_name: "init",
      decl_map: %{},
      local_types: %{
        "__maybe_payload__" =>
          "{ path : { path : UrlPath.UrlPath, query : Maybe String, fragment : Maybe String }, metadata : Maybe Route.Route, pageUrl : Maybe Pages.PageUrl.PageUrl }"
      }
    }

    base = %{op: :var, name: "__maybe_payload__"}

    assert Record.resolve_field_index_int("path", ctx, base) == {:ok, 0}
    assert Record.resolve_field_index_int("metadata", ctx, base) == {:ok, 1}
    assert Record.resolve_field_index_int("pageUrl", ctx, base) == {:ok, 2}
  end

  test "curried lambda param inline record resolves view at index 0" do
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

    ctx = %Context{
      module: "RouteBuilder",
      function_name: "buildNoState_lam_0",
      decl_map: %{
        {"RouteBuilder", "buildNoState"} => %{
          type:
            "{view : App data action routeParams -> Shared.Model -> View.View msg} -> Builder routeParams data action -> StatefulRoute routeParams data action {} ()"
        }
      },
      local_types: %{
        "recordArg" => "{view : App data action routeParams -> Shared.Model -> View.View msg}"
      }
    }

    base = %{op: :var, name: "recordArg"}

    assert Record.resolve_field_index_int("view", ctx, base) == {:ok, 0}
  end

  test "Browser.sandbox impl param resolves view at alphabetical index 2" do
    ctx = %Context{
      module: "Browser",
      function_name: "sandbox",
      decl_map: %{},
      local_types: %{
        "impl" => "{init : model, view : model -> Html msg, update : msg -> model -> model}"
      }
    }

    base = %{op: :var, name: "impl"}

    assert Record.resolve_field_index_int("init", ctx, base) == {:ok, 0}
    assert Record.resolve_field_index_int("update", ctx, base) == {:ok, 1}
    assert Record.resolve_field_index_int("view", ctx, base) == {:ok, 2}
  end

  test "ambiguous offset field resolves to current module Model not Time.Era" do
    shapes = %{
      {"Main", "Model"} => ["playerY", "velocityY", "offset", "tiles"],
      {"Time", "Era"} => ["start", "offset", "end"]
    }

    Process.put(:elmc_record_alias_shapes, shapes)

    on_exit(fn ->
      Process.delete(:elmc_record_alias_shapes)
      Process.delete(:elmc_record_field_macros)
    end)

    Process.put(:elmc_record_field_macros, %{
      {"Main", "Model", "offset"} => "ELMC_FIELD_MAIN_MODEL_OFFSET",
      {"Time", "Era", "offset"} => "ELMC_FIELD_TIME_ERA_OFFSET"
    })

    ctx = %Context{
      module: "Main",
      function_name: "step",
      params: ["model"],
      local_types: %{"model" => "Model"},
      inferred_param_fields: %{"model" => ["offset", "playerY", "velocityY", "tiles"]}
    }

    base = %{op: :var, name: "model"}

    assert Record.resolve_field_index_int("offset", ctx, base) == {:ok, 2}
    assert Record.field_index_for("offset", ctx, base) == "ELMC_FIELD_MAIN_MODEL_OFFSET"
  end
end
