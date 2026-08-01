defmodule Elmc.IRQueriesRecordShapesTest do
  use ExUnit.Case, async: true

  alias Elmc.Backend.CCodegen.IRQueries
  alias Elmc.Backend.Plan.Lower.Record
  alias Elmc.Backend.Plan.Context
  alias ElmEx.IR

  test "type alias shapes sort alphabetically like Elm (Transformation.scale last)" do
    # Scene3d.Types.Transformation declares ix…pz, scale, isRightHanded. Elm stores
    # isRightHanded first and scale last; declaration-order shapes made .scale read
    # pz (0) and .pz read scale (1) → zero modelScale + translation z=1 → solid white.
    ir = %IR{
      modules: [
        %{
          name: "Scene3d.Types",
          declarations: [
            %{
              kind: :type_alias,
              name: "Transformation",
              expr: %{
                op: :record_alias,
                fields: [
                  "ix",
                  "iy",
                  "iz",
                  "jx",
                  "jy",
                  "jz",
                  "kx",
                  "ky",
                  "kz",
                  "px",
                  "py",
                  "pz",
                  "scale",
                  "isRightHanded"
                ]
              }
            }
          ],
          unions: %{}
        }
      ]
    }

    shapes = IRQueries.record_alias_shape_map(ir)
    shape = shapes[{"Scene3d.Types", "Transformation"}]

    assert shape == [
             "isRightHanded",
             "ix",
             "iy",
             "iz",
             "jx",
             "jy",
             "jz",
             "kx",
             "ky",
             "kz",
             "px",
             "py",
             "pz",
             "scale"
           ]

    assert Enum.find_index(shape, &(&1 == "scale")) == 13
    assert Enum.find_index(shape, &(&1 == "pz")) == 12
  end

  test "union constructor record shapes use alphabetical field order like Elm runtime" do
    ir = %IR{
      modules: [
        %{
          name: "Internal.Cartesian.Layout",
          declarations: [],
          unions: %{
            "Layout" => %{
              payload_specs: %{
                "Leaf" => "{ value : a, extent : Extent }",
                "Layout" =>
                  "{ inArrows : List Arrow , wrapping : Maybe a , contents : List a , outArrows : List Arrow , extent : Extent }"
              }
            }
          }
        }
      ]
    }

    shapes = Map.new(IRQueries.union_constructor_record_shapes(ir))

    assert shapes[{"Internal.Cartesian.Layout", "Leaf"}] == ["extent", "value"]

    assert shapes[{"Internal.Cartesian.Layout", "Layout"}] == [
             "contents",
             "extent",
             "inArrows",
             "outArrows",
             "wrapping"
           ]
  end

  test "subset record literals expand to unique union payload superset layout" do
    # Port→arrow builds {tailPoint, adjustTail, adjustHead, headPoint} but
    # computeArrowDetails indexes the full Arrow payload (includes meander).
    shapes = %{
      {"Internal.Arrow", "Arrow"} => [
        "adjustHead",
        "adjustTail",
        "headPoint",
        "meander",
        "tailPoint"
      ]
    }

    Process.put(:elmc_record_alias_shapes, shapes)
    on_exit(fn -> Process.delete(:elmc_record_alias_shapes) end)

    fields = [
      %{name: "tailPoint", expr: %{op: :var, name: "pos"}},
      %{name: "adjustTail", expr: %{op: :int_literal, value: 0}},
      %{name: "adjustHead", expr: %{op: :int_literal, value: 0}},
      %{name: "headPoint", expr: %{op: :var, name: "pos"}}
    ]

    canonical = Record.canonicalize_literal_fields(fields, %Context{module: "Internal.Cartesian.Layout.Svg"})

    assert Enum.map(canonical, & &1.name) == [
             "adjustHead",
             "adjustTail",
             "headPoint",
             "meander",
             "tailPoint"
           ]

    meander = Enum.find(canonical, &(&1.name == "meander"))
    assert meander.expr == %{op: :int_literal, value: 0}
  end

  test "cylinder args {radius, length} do not pad Cylinder3d axis placeholder" do
    # Geometry.Types.Cylinder3d payload is a unique +1 superset of {radius, length}.
    # Padding axis=0 made centeredOn treat int 0 as radius → zero preScale → gray HeroScene.
    shapes = %{
      {"Geometry.Types", "Cylinder3d"} => ["axis", "radius", "length"]
    }

    Process.put(:elmc_record_alias_shapes, shapes)
    on_exit(fn -> Process.delete(:elmc_record_alias_shapes) end)

    fields = [
      %{name: "radius", expr: %{op: :var, name: "r"}},
      %{name: "length", expr: %{op: :var, name: "l"}}
    ]

    canonical = Record.canonicalize_literal_fields(fields, %Context{module: "HeroScene"})

    assert Enum.map(canonical, & &1.name) == ["length", "radius"]
    refute Enum.any?(canonical, &(&1.name == "axis"))
  end

  test "mesh vertices {position, normal} pad trailing uv in alphabetical layout" do
    # Pad to the 3-field UniformVertex / VertexWithNormalAndUv shape so textured
    # and untextured paths share indices. Layout is alphabetical (Elm + WebGL
    # attribute maps): normal, position, uv — not declaration order.
    shapes = %{
      {"Scene3d.Mesh", "UniformVertex"} => ["normal", "position", "uv"]
    }

    Process.put(:elmc_record_alias_shapes, shapes)
    on_exit(fn -> Process.delete(:elmc_record_alias_shapes) end)

    fields = [
      %{name: "position", expr: %{op: :var, name: "p"}},
      %{name: "normal", expr: %{op: :var, name: "n"}}
    ]

    canonical = Record.canonicalize_literal_fields(fields, %Context{module: "Scene3d.Primitives"})

    assert Enum.map(canonical, & &1.name) == ["normal", "position", "uv"]
    uv = Enum.find(canonical, &(&1.name == "uv"))
    assert uv.expr == %{op: :int_literal, value: 0}
  end

  test "Scene3d.Types.VertexWithNormal alias shape is alphabetical" do
    ir = %IR{
      modules: [
        %{
          name: "Scene3d.Types",
          declarations: [
            %{
              kind: :type_alias,
              name: "VertexWithNormal",
              expr: %{
                op: :record_alias,
                fields: ["position", "normal"]
              }
            }
          ],
          unions: %{}
        }
      ]
    }

    shapes = IRQueries.record_alias_shape_map(ir)
    assert shapes[{"Scene3d.Types", "VertexWithNormal"}] == ["normal", "position"]
  end

  test "anonymous record literals canonicalize to alphabetical field order" do
    # computeArrowDetails builds {start, ascent, descent, end, headLeft, headRight}
    # in source order; field_access uses alphabetical indices like Elm runtime.
    fields = [
      %{name: "start", expr: %{op: :var, name: "s"}},
      %{name: "ascent", expr: %{op: :var, name: "a"}},
      %{name: "descent", expr: %{op: :var, name: "d"}},
      %{name: "end", expr: %{op: :var, name: "e"}},
      %{name: "headLeft", expr: %{op: :var, name: "hl"}},
      %{name: "headRight", expr: %{op: :var, name: "hr"}}
    ]

    canonical = Record.canonicalize_literal_fields(fields, %Context{module: "Internal.Svg.Arrow"})

    assert Enum.map(canonical, & &1.name) == [
             "ascent",
             "descent",
             "end",
             "headLeft",
             "headRight",
             "start"
           ]
  end

  test "Scene3d.composite-style args sort alphabetically so dimensions is index 4" do
    # custom builds {camera, clipDepth, antialiasing, dimensions, background} in
    # source order; composite reads arguments.dimensions at alphabetical index 4.
    fields = [
      %{name: "camera", expr: %{op: :var, name: "c"}},
      %{name: "clipDepth", expr: %{op: :var, name: "d"}},
      %{name: "antialiasing", expr: %{op: :var, name: "a"}},
      %{name: "dimensions", expr: %{op: :var, name: "dims"}},
      %{name: "background", expr: %{op: :var, name: "b"}}
    ]

    canonical = Record.canonicalize_literal_fields(fields, %Context{module: "Scene3d"})

    assert Enum.map(canonical, & &1.name) == [
             "antialiasing",
             "background",
             "camera",
             "clipDepth",
             "dimensions"
           ]
  end

  test "buildWithLocalState handlers literal sorts init before view" do
    # Route.Wasm passes {view, init, update, subscriptions} in source order.
    # RouteBuilder.buildWithLocalState reads config.init at alphabetical index 0.
    fields = [
      %{name: "view", expr: %{op: :var, name: "view"}},
      %{name: "init", expr: %{op: :var, name: "init"}},
      %{name: "update", expr: %{op: :var, name: "update"}},
      %{name: "subscriptions", expr: %{op: :var, name: "subscriptions"}}
    ]

    canonical = Record.canonicalize_literal_fields(fields, %Context{module: "Route.Wasm"})

    assert Enum.map(canonical, & &1.name) == [
             "init",
             "subscriptions",
             "update",
             "view"
           ]
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

  test "case-bound Just p -> p.val resolves against a let-bound record literal with no type alias" do
    # Basics/ClosureCaptureWorkerBug corpus fixture:
    #   items = [ { id = "a", val = { x = n, y = n + 1 } } ]
    #   case List.head (List.filter (\p -> p.id == id) items) of
    #     Just p -> p.val
    # `{id, val}` has no type alias, so `p.val` (a case-bound payload, not a
    # param) only had the usage-only single-field guess to fall back on,
    # which always resolves the one field it sees to index 0. Scanning
    # declaration bodies for anonymous record literals must recover the
    # real two-field alphabetical layout (id@0, val@1) from the literal.
    ir = %IR{
      modules: [
        %{
          name: "ClosureCaptureWorkerBug",
          declarations: [
            %{
              kind: :function,
              name: "compute",
              expr: %{
                op: :let,
                bindings: [
                  %{
                    name: "items",
                    expr: %{
                      op: :list_literal,
                      items: [
                        %{
                          op: :record_literal,
                          fields: [
                            %{name: "id", expr: %{op: :string_literal, value: "a"}},
                            %{
                              name: "val",
                              expr: %{
                                op: :record_literal,
                                fields: [
                                  %{name: "x", expr: %{op: :var, name: "n"}},
                                  %{name: "y", expr: %{op: :var, name: "n"}}
                                ]
                              }
                            }
                          ]
                        }
                      ]
                    }
                  }
                ],
                body: %{op: :var, name: "items"}
              }
            }
          ],
          unions: %{}
        }
      ]
    }

    shapes = IRQueries.inline_record_literal_shape_map(ir)
    assert shapes[{"ClosureCaptureWorkerBug", "compute@literal1"}] == ["id", "val"]

    Process.put(:elmc_inline_record_literal_shapes, shapes)
    on_exit(fn -> Process.delete(:elmc_inline_record_literal_shapes) end)

    ctx = %Context{module: "ClosureCaptureWorkerBug", function_name: "compute_lam_0"}
    base = %{op: :var, name: "p"}

    assert Record.resolve_field_index_int("id", ctx, base) == {:ok, 0}
    assert Record.resolve_field_index_int("val", ctx, base) == {:ok, 1}
  end

  test "inline record literal shapes survive a per-lambda emit-probe reset (process dictionary whitelist)" do
    # Elmc.Backend.CCodegen.GeneratedSource.reset_emit_probe_state!/0 runs
    # between sub-emissions within one compile session (lambda bodies, direct
    # render probes, ...) and deletes any `elmc_*` process key that is not in
    # @compile_session_process_keys. `elmc_inline_record_literal_shapes` was
    # seeded once per session (in prepare_emit_session!/header) but, unlike
    # its sibling `elmc_record_alias_shapes`, was missing from that whitelist:
    # the very next probe reset wiped it with no reseed in between, so any
    # later `p.val`-style field lookup silently fell back to a usage-only
    # guess (index 0) instead of the real literal layout.
    alias Elmc.Backend.CCodegen.GeneratedSource

    seeded = %{{"ClosureCaptureWorkerBug", "compute@literal1"} => ["id", "val"]}
    Process.put(:elmc_inline_record_literal_shapes, seeded)

    on_exit(fn -> Process.delete(:elmc_inline_record_literal_shapes) end)

    GeneratedSource.reset_emit_probe_state!()

    assert Process.get(:elmc_inline_record_literal_shapes) == seeded
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
      ],
      {"RouteBuilder", "App"} => ["data", "sharedData", "routeParams"]
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

    # Poisoned Result.Ok type-var local type must still prefer Model_pageData.
    poisoned =
      put_in(ctx.local_types, %{"pageData" => "value"})

    base = %{op: :var, name: "pageData"}

    assert Record.resolve_field_index_int("sharedData", poisoned, base) == {:ok, 2}
    assert Record.resolve_field_index_int("pageData", poisoned, base) == {:ok, 1}
    assert Record.resolve_field_index_int("actionData", poisoned, base) == {:ok, 3}
    assert Record.resolve_field_index_int("userModel", poisoned, base) == {:ok, 0}

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

  test "case arms unify to callee return type (let next = case … -> step)" do
    alias Elmc.Backend.CCodegen.Native.TypedReturn

    env = %{
      __module__: "Main",
      __var_types__: %{"model" => "Model"},
      __program_decls__: %{
        {"Main", "step"} => %{type: "Int -> Model -> Model"}
      }
    }

    case_expr = %{
      op: :case,
      subject: %{op: :var, name: "msg"},
      branches: [
        %{
          pattern: %{op: :int_literal, value: 0},
          expr: %{
            op: :call,
            name: "step",
            args: [%{op: :int_literal, value: 0}, %{op: :var, name: "model"}]
          }
        },
        %{
          pattern: %{op: :int_literal, value: 1},
          expr: %{
            op: :call,
            name: "step",
            args: [%{op: :int_literal, value: 1}, %{op: :var, name: "model"}]
          }
        }
      ]
    }

    assert TypedReturn.expr_type(case_expr, env) == "Model"
  end

  test "tuple_first let-bound model keeps Platform.Model pageData @4 (performUserMsg)" do
    # performUserMsg desugars `(model, effect)` as:
    #   let model = Tuple.first patternArg3
    # TypedReturn must project the tuple elem type onto `model`, otherwise
    # pageData falls through to nested Ok-payload @1 (url) and update returns 0.
    alias Elmc.Backend.CCodegen.Native.TypedReturn

    model_type = "Pages.Internal.Platform.Model userModel pageData actionData sharedData"
    effect_type = "Effect userMsg pageData actionData sharedData userEffect errorPage"
    tuple_type = "( #{model_type}, #{effect_type} )"

    env = %{
      __module__: "Pages.Internal.Platform",
      __var_types__: %{"patternArg3" => tuple_type}
    }

    assert TypedReturn.expr_type(
             %{op: :tuple_first_expr, arg: %{op: :var, name: "patternArg3"}},
             env
           ) == model_type

    assert TypedReturn.expr_type(
             %{op: :tuple_second_expr, arg: %{op: :var, name: "patternArg3"}},
             env
           ) == effect_type

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
      function_name: "performUserMsg_lam_0",
      params: ["userMsg", "config", "patternArg3"],
      local_types: %{
        "patternArg3" => tuple_type,
        "model" => model_type
      },
      decl_map: %{}
    }

    assert Record.resolve_field_index_int("pageData", ctx, %{op: :var, name: "model"}) ==
             {:ok, 4}
  end

  test "zero-arg callee record literal resolves Shared.template fields alphabetically" do
    # Shared.template = { init, update, view, data, subscriptions, onPageChange }
    # in source order; record_new and field_access both use alphabetical layout.
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
      # alphabetical: data, init, onPageChange, subscriptions, update, view
      assert Record.resolve_field_index_int("data", ctx, base) == {:ok, 0}
      assert Record.resolve_field_index_int("init", ctx, base) == {:ok, 1}
      assert Record.resolve_field_index_int("onPageChange", ctx, base) == {:ok, 2}
      assert Record.resolve_field_index_int("view", ctx, base) == {:ok, 5}
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

  test "maybePagePath payload fields follow registered shape order" do
    # Shape may be declaration order when registered that way; resolve uses the shape as-is.
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
    # buildNoState only accesses `.view` on `{view : …}`. Without preferring the
    # declared inline equal-set layout, same-module StatefulRoute (view@3) steals
    # the index → OOB Int(0) captured into the view wrapper → empty Document.title.
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
      },
      inferred_param_fields: %{"recordArg" => ["view"]}
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

  test "Browser.sandbox impl view stays at index 2 when ParamFieldInference only saw init and view" do
    Process.put(:elmc_record_alias_shapes, %{
      {"Browser", "ProgramConfig"} => ["init", "subscriptions", "update", "view"]
    })

    on_exit(fn -> Process.delete(:elmc_record_alias_shapes) end)

    ctx = %Context{
      module: "Browser",
      function_name: "sandbox",
      params: ["impl"],
      decl_map: %{},
      local_types: %{
        "impl" => "{init : model, view : model -> Html msg, update : msg -> model -> model}"
      },
      inferred_param_fields: %{"impl" => ["init", "view"]}
    }

    base = %{op: :var, name: "impl"}

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

  test "extensible {c|lo,hi} resolves lo/hi against Extent not Box.lo index" do
    shapes = %{
      {"Internal.Extent", "Extent"} => ["lo", "hi"],
      {"Internal.Box", "Box"} => ["label", "lo", "width", "height", "radius"],
      {"Internal.Svg", "Boxy"} => ["label", "lo", "width", "height", "radius"]
    }

    Process.put(:elmc_record_alias_shapes, shapes)

    on_exit(fn ->
      Process.delete(:elmc_record_alias_shapes)
    end)

    ctx = %Context{
      module: "Internal.Extent",
      function_name: "map",
      params: ["f", "e"],
      local_types: %{"e" => "{c | lo : b, hi : b}"}
    }

    base = %{op: :var, name: "e"}

    assert Record.resolve_field_index_int("lo", ctx, base) == {:ok, 0}
    assert Record.resolve_field_index_int("hi", ctx, base) == {:ok, 1}
  end

  test "BoundingBox3d min/max fields prefer alphabetical union shape over fromExtrema decl order" do
    # Geometry.Types.BoundingBox3d stores fields alphabetically (maxX first).
    # fromExtrema's argument type is the same field set in declaration order
    # (minX first). Preferring the lower inline index made minX/maxX both read
    # slot 0 → zero X dimensions → near≈far projection → invisible Scene3d.
    alias_shapes = %{
      {"Geometry.Types", "BoundingBox2d"} => ["maxX", "maxY", "minX", "minY"],
      {"Geometry.Types", "BoundingBox3d"} => ["maxX", "maxY", "maxZ", "minX", "minY", "minZ"],
      {"Geometry.Types", "VectorBoundingBox3d"} => ["maxX", "maxY", "maxZ", "minX", "minY", "minZ"]
    }

    inline_shapes = %{
      {"BoundingBox3d", "fromExtrema_given"} => ["minX", "maxX", "minY", "maxY", "minZ", "maxZ"]
    }

    Process.put(:elmc_record_alias_shapes, alias_shapes)
    Process.put(:elmc_inline_record_literal_shapes, inline_shapes)

    on_exit(fn ->
      Process.delete(:elmc_record_alias_shapes)
      Process.delete(:elmc_inline_record_literal_shapes)
    end)

    ctx = %Context{
      module: "BoundingBox3d",
      function_name: "centerPoint",
      params: ["boundingBox"]
    }

    base = %{op: :var, name: "b"}

    assert Record.resolve_field_index_int("minX", ctx, base) == {:ok, 3}
    assert Record.resolve_field_index_int("maxX", ctx, base) == {:ok, 0}
    assert Record.resolve_field_index_int("minY", ctx, base) == {:ok, 4}
    assert Record.resolve_field_index_int("maxY", ctx, base) == {:ok, 1}
    assert Record.resolve_field_index_int("minZ", ctx, base) == {:ok, 5}
    assert Record.resolve_field_index_int("maxZ", ctx, base) == {:ok, 2}
  end

  test "extensible {url|path} prefers Url.path index over short Payload.path@0" do
    # elm-pages Route.urlToRoute : {url | path : String} -> Maybe Route.
    # Short unrelated aliases also have `path` (Pages.Payload, Http.Request, …).
    # Picking path@0 reads Url.protocol and deep links init as Index (Model mismatch).
    shapes = %{
      {"Pages.Internal.NotFoundReason", "Payload"} => ["path", "reason"],
      {"Pages.Fetcher", "Request"} => ["path", "body", "expect"],
      {"Url", "Url"} => ["protocol", "host", "port_", "path", "query", "fragment"],
      {"Pages.PageUrl", "PageUrl"} => ["protocol", "host", "port_", "path", "query", "fragment"]
    }

    Process.put(:elmc_record_alias_shapes, shapes)

    on_exit(fn ->
      Process.delete(:elmc_record_alias_shapes)
    end)

    ctx = %Context{
      module: "Route",
      function_name: "urlToRoute",
      params: ["url"],
      local_types: %{"url" => "{url | path : String}"}
    }

    base = %{op: :var, name: "url"}

    assert Record.resolve_field_index_int("path", ctx, base) == {:ok, 3}
  end

  test "ambiguous contents prefers Layout over elm-pages Scaffold path/contents" do
    # Mirrors generated_source: type aliases in alias map, union payloads alphabetical.
    alias_shapes = %{
      {"Scaffold.Route", "File"} => ["path", "contents"],
      {"Head", "Meta"} => ["contents"]
    }

    inline_shapes = %{
      {"Internal.Cartesian.Layout", "Layout"} => [
        "contents",
        "extent",
        "inArrows",
        "outArrows",
        "wrapping"
      ],
      {"Internal.Cartesian.Layout", "Leaf"} => ["extent", "value"]
    }

    Process.put(:elmc_record_alias_shapes, Map.merge(alias_shapes, inline_shapes))
    Process.put(:elmc_inline_record_literal_shapes, inline_shapes)

    on_exit(fn ->
      Process.delete(:elmc_record_alias_shapes)
      Process.delete(:elmc_inline_record_literal_shapes)
    end)

    # Compiled from Internal.Cartesian.Layout.Svg — module prefix should prefer Layout.
    ctx = %Context{
      module: "Internal.Cartesian.Layout.Svg",
      function_name: "layoutToSvgWithConfig",
      params: ["svgConfig", "cl"]
    }

    assert Record.resolve_field_index_int("contents", ctx, %{op: :var, name: "l"}) == {:ok, 0}
    assert Record.resolve_field_index_int("wrapping", ctx, %{op: :var, name: "l"}) == {:ok, 4}
    assert Record.resolve_field_index_int("inArrows", ctx, %{op: :var, name: "l"}) == {:ok, 2}
  end

  test "ambiguous x without module hint prefers Vec2 over larger records" do
    shapes = %{
      {"Internal.Vec2", "Vec2"} => ["x", "y"],
      {"Diagram.Layout", "Node"} => ["label", "x", "y", "width", "height", "depth"]
    }

    Process.put(:elmc_record_alias_shapes, shapes)

    on_exit(fn ->
      Process.delete(:elmc_record_alias_shapes)
    end)

    ctx = %Context{
      module: "Internal.Svg",
      function_name: "viewportFor",
      params: ["l"]
    }

    assert Record.resolve_field_index_int("x", ctx, %{op: :var, name: "pos"}) == {:ok, 0}
    assert Record.resolve_field_index_int("y", ctx, %{op: :var, name: "pos"}) == {:ok, 1}
  end

  test "Platform.application subscriptions subset inference uses Model pageData @4" do
    # Nested `\model -> case model.pageData of` only accesses pageData + url.
    # Alphabetical layout of that subset maps pageData→0 (key / Maybe.Just), so
    # subscriptions never reach userModel / Time.every. Same-module proper
    # supersets must recover Platform.Model declaration indices.
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

    on_exit(fn -> Process.delete(:elmc_record_alias_shapes) end)

    ctx = %Context{
      module: "Pages.Internal.Platform",
      function_name: "application_lam_3",
      params: ["config", "model"],
      inferred_param_fields: %{"model" => ["pageData", "url"]}
    }

    base = %{op: :var, name: "model"}
    assert Record.resolve_field_index_int("pageData", ctx, base) == {:ok, 4}
    assert Record.resolve_field_index_int("url", ctx, base) == {:ok, 1}
  end

  test "collectSmooth {position, normal} is not TexturedFacetVertex normal@2" do
    # Scene3d.Mesh.TexturedFacetVertex is `{position, uv, normal}` in source order.
    # Same-module proper-superset inference must not map collectSmooth's
    # `{position, normal}` onto that layout (normal→2 past a 2-field vertex).
    Process.put(:elmc_record_alias_shapes, %{
      {"Scene3d.Types", "VertexWithNormal"} => ["normal", "position"],
      {"Scene3d.Types", "VertexWithNormalAndUv"} => ["normal", "position", "uv"],
      {"Scene3d.Mesh", "TexturedFacetVertex"} => ["position", "uv", "normal"],
      {"Scene3d.Mesh", "TexturedTriangleVertex"} => ["position", "uv"]
    })

    on_exit(fn -> Process.delete(:elmc_record_alias_shapes) end)

    ctx = %Context{
      module: "Scene3d.Mesh",
      function_name: "collectSmooth",
      params: ["__patternArg0"],
      inferred_param_fields: %{"__patternArg0" => ["position", "normal"]}
    }

    base = %{op: :var, name: "__patternArg0"}
    assert Record.resolve_field_index_int("position", ctx, base) == {:ok, 1}
    assert Record.resolve_field_index_int("normal", ctx, base) == {:ok, 0}
  end

  test "TexturedFacetVertex alias shape is alphabetical" do
    ir = %IR{
      modules: [
        %{
          name: "Scene3d.Mesh",
          declarations: [
            %{
              kind: :type_alias,
              name: "TexturedFacetVertex",
              expr: %{
                op: :record_alias,
                fields: ["position", "uv", "normal"]
              }
            }
          ],
          unions: %{}
        }
      ]
    }

    shapes = IRQueries.record_alias_shape_map(ir)
    assert shapes[{"Scene3d.Mesh", "TexturedFacetVertex"}] == ["normal", "position", "uv"]
  end

  test "mesh {position, normal} prefers VertexWithNormal over TexturedFacetVertex pad" do
    # Exact 2-field VertexWithNormal must win over padding through TexturedFacetVertex's
    # middle `uv` slot (which would write/read `.normal` at index 2).
    Process.put(:elmc_record_alias_shapes, %{
      {"Scene3d.Types", "VertexWithNormal"} => ["normal", "position"],
      {"Scene3d.Mesh", "TexturedFacetVertex"} => ["position", "uv", "normal"]
    })

    on_exit(fn -> Process.delete(:elmc_record_alias_shapes) end)

    fields = [
      %{name: "position", expr: %{op: :var, name: "p"}},
      %{name: "normal", expr: %{op: :var, name: "n"}}
    ]

    canonical = Record.canonicalize_literal_fields(fields, %Context{module: "Scene3d.Primitives"})
    assert Enum.map(canonical, & &1.name) == ["normal", "position"]
  end
end
