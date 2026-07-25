defmodule Elmc.PlanWebLoweringGapsTest do
  use ExUnit.Case, async: true

  alias Elmc.Backend.CCodegen.{IRQueries, VarAnalysis}
  alias Elmc.Backend.Plan
  alias Elmc.Backend.Plan.{Builder, Context, Verify}
  alias Elmc.Backend.Plan.Lower.Case.TagSwitch
  alias Elmc.Backend.Plan.Lower.{Call, Function}

  test "tag switch binds constructor bind slot and nested tuple payload" do
    pattern = %{
      kind: :constructor,
      name: "Array_elm_builtin",
      resolved_name: "Array_elm_builtin",
      tag: 1,
      bind: "array",
      arg_pattern: %{
        kind: :tuple,
        elements: [
          %{kind: :wildcard},
          %{
            kind: :tuple,
            elements: [
              %{kind: :wildcard},
              %{kind: :tuple, elements: [%{kind: :wildcard}, %{kind: :var, name: "tail"}]}
            ]
          }
        ]
      }
    }

    branches = [
      %{
        pattern: pattern,
        expr: %{
          op: :qualified_call,
          target: "Array.unsafeReplaceTail",
          args: [
            %{
              op: :qualified_call,
              target: "Elm.JsArray.push",
              args: [%{op: :var, name: "a"}, %{op: :var, name: "tail"}]
            },
            %{op: :var, name: "array"}
          ]
        }
      }
    ]

    decl_map = %{}
    Process.put(:elmc_constructor_tags, %{"Array_elm_builtin" => 1})

    ctx =
      Context.new(
        module: "Array",
        function_name: "push_lam_0",
        params: ["a", "patternArg2"],
        decl_map: decl_map
      )

    b0 = Builder.new("Array", "push_lam_0", args: ["a", "patternArg2"])

    subject = %{op: :var, name: "patternArg2"}

    assert {:ok, _reg, _b1} = TagSwitch.compile(subject, branches, ctx, b0)
  end

  test "Internal.Svg.Config.withBoxAttributes is not lowered as Svg attribute html_cmd" do
    Process.put(:elmc_codegen_opts, %{web: true, targets: [:wasm]})

    on_exit(fn ->
      Process.delete(:elmc_codegen_opts)
    end)

    decl_map = %{
      {"Internal.Svg.Config", "withBoxAttributes"} => %{
        name: "withBoxAttributes",
        args: ["func", "config"],
        expr: %{
          op: :lambda,
          args: ["func", "config"],
          body: %{
            op: :record_update,
            base: %{op: :var, name: "config"},
            fields: [%{name: "toBoxAttributes", expr: %{op: :var, name: "func"}}]
          }
        }
      },
      {"Diagram.Svg.Config", "withCellAttributesFunction"} => %{
        name: "withCellAttributesFunction",
        args: ["func"],
        expr: %{
          op: :qualified_call,
          target: "Internal.Svg.Config.withBoxAttributes",
          args: [%{op: :var, name: "func"}]
        }
      }
    }

    decl = Map.fetch!(decl_map, {"Diagram.Svg.Config", "withCellAttributesFunction"})

    assert {:ok, plan} =
             Function.lower(decl, "Diagram.Svg.Config", decl_map, rc_required: false)

    instrs = plan.blocks |> Enum.flat_map(& &1.instrs)

    refute Enum.any?(instrs, fn
             %{op: :html_cmd} -> true
             _ -> false
           end)

    assert Enum.any?(instrs, fn
             %{op: :call_fn, args: %{module: "Internal.Svg.Config", name: "withBoxAttributes"}} ->
               true

             %{op: :make_closure} ->
               true

             _ ->
               false
           end)
  end

  test "Internal.Svg.Arrow.arrow lowers strokeOpacity as html_cmd attr from full wiring IR" do
    alias Elmc.Backend.CCodegen.IRQueries

    Process.put(:elmc_codegen_opts, %{web: true, targets: [:wasm]})

    on_exit(fn ->
      Process.delete(:elmc_codegen_opts)
    end)

    root = Path.expand("fixtures/wasm_web_wiring_diagram_project", __DIR__)
    {:ok, project} = ElmEx.Frontend.Bridge.load_project(root)
    {:ok, ir} = ElmEx.IR.Lowerer.lower_project(project)
    mod = Enum.find(ir.modules, &(&1.name == "Internal.Svg.Arrow"))
    decl = Enum.find(mod.declarations, &(&1.name == "arrow"))
    decl_map = IRQueries.function_decl_map(ir)

    Process.put(:elmc_constructor_tags, IRQueries.constructor_tag_map(ir))
    Process.put(:elmc_program_decls, decl_map)
    Process.put(:elmc_svg_attribute_dom_names, IRQueries.svg_attribute_dom_names(ir))
    Process.put(:elmc_svg_attribute_names, IRQueries.svg_attribute_names(ir))

    rc_required? = Elmc.Backend.CCodegen.RcRequired.rc_required?(mod.name, "arrow")

    assert {:ok, plan} =
             Plan.lower_function(decl, mod.name, decl_map, rc_required: rc_required?)

    instrs = plan.blocks |> Enum.flat_map(& &1.instrs)

    calls =
      Enum.filter(instrs, fn
        %{op: :call_fn, args: args} -> Map.get(args, :name) in ["strokeOpacity", "stroke", "fill", "d"]
        _ -> false
      end)

    assert calls == [],
           "call_fn attrs=#{inspect(calls)} html_cmd=#{Enum.count(instrs, &(&1.op == :html_cmd))} all_call_fn=#{inspect(Enum.filter(instrs, &match?(%{op: :call_fn}, &1)))}"

    wasm_unit = Elmc.Backend.Wasm.Lower.Function.lower(plan)
    refute IO.iodata_to_binary(wasm_unit.body) =~ "elmc_fn_Internal_Svg_Arrow_strokeOpacity"

    assert Enum.any?(instrs, &(&1.op == :html_cmd))
  end

  test "svg attribute calls survive dead-code strip of Svg.Attributes decls" do
    alias Elmc.Backend.CCodegen.IRQueries

    Process.put(:elmc_codegen_opts, %{web: true, targets: [:wasm]})

    on_exit(fn ->
      Process.delete(:elmc_codegen_opts)
      Process.delete(:elmc_svg_attribute_names)
      Process.delete(:elmc_svg_attribute_dom_names)
    end)

    root = Path.expand("fixtures/wasm_web_wiring_diagram_project", __DIR__)
    {:ok, project} = ElmEx.Frontend.Bridge.load_project(root)
    {:ok, ir0} = ElmEx.IR.Lowerer.lower_project(project)
    ir = ElmEx.IR.DeadCode.strip(ir0, "Main")
    Process.put(:elmc_svg_attribute_dom_names, IRQueries.svg_attribute_dom_names(ir0))
    Process.put(:elmc_svg_attribute_names, IRQueries.svg_attribute_names(ir0))
    Process.put(:elmc_constructor_tags, IRQueries.constructor_tag_map(ir))

    mod = Enum.find(ir.modules, &(&1.name == "Internal.Svg.Arrow"))
    decl = Enum.find(mod.declarations, &(&1.name == "arrow"))
    decl_map =
      IRQueries.function_decl_map(ir)
      |> Enum.reject(fn {{mod, _}, _} -> mod == "Svg.Attributes" end)
      |> Map.new()

    rc_required? = Elmc.Backend.CCodegen.RcRequired.rc_required?(mod.name, "arrow")

    assert {:ok, plan} =
             Plan.lower_function(decl, mod.name, decl_map, rc_required: rc_required?)

    instrs = plan.blocks |> Enum.flat_map(& &1.instrs)

    calls =
      Enum.filter(instrs, fn
        %{op: :call_fn, args: args} -> Map.get(args, :name) in ["strokeOpacity", "stroke", "fill", "d"]
        _ -> false
      end)

    assert calls == []
    assert Enum.any?(instrs, &(&1.op == :html_cmd))
    assert IRQueries.svg_attribute_dom_names(ir0)["strokeOpacity"] == "stroke-opacity"
    assert IRQueries.svg_attribute_dom_names(ir0)["fontWeight"] == "font-weight"
    assert IRQueries.svg_attribute_dom_names(ir0)["textAnchor"] == "text-anchor"
    assert IRQueries.svg_attribute_dom_names(ir0)["viewBox"] == "viewBox"
  end

  test "Internal.Svg.box call keeps svgConfig and boxy args" do
    alias Elmc.Backend.CCodegen.IRQueries

    Process.put(:elmc_codegen_opts, %{web: true, targets: [:wasm]})

    on_exit(fn ->
      Process.delete(:elmc_codegen_opts)
      Process.delete(:elmc_svg_attribute_names)
      Process.delete(:elmc_svg_attribute_dom_names)
    end)

    root = Path.expand("fixtures/wasm_web_wiring_diagram_project", __DIR__)
    {:ok, project} = ElmEx.Frontend.Bridge.load_project(root)
    {:ok, ir0} = ElmEx.IR.Lowerer.lower_project(project)
    ir = ElmEx.IR.DeadCode.strip(ir0, "Main")
    Process.put(:elmc_svg_attribute_dom_names, IRQueries.svg_attribute_dom_names(ir0))
    Process.put(:elmc_svg_attribute_names, IRQueries.svg_attribute_names(ir0))
    Process.put(:elmc_constructor_tags, IRQueries.constructor_tag_map(ir))

    mod = Enum.find(ir.modules, &(&1.name == "Internal.Cartesian.Layout.Svg"))
    decl = Enum.find(mod.declarations, &(&1.name == "layoutToSvgWithConfig"))
    decl_map = IRQueries.function_decl_map(ir)

    assert {:ok, plan} =
             Plan.lower_function(decl, mod.name, decl_map, rc_required: false)

    box_call =
      plan.blocks
      |> Enum.flat_map(& &1.instrs)
      |> Enum.find(fn instr ->
        instr.op == :call_fn and match?(%{module: "Internal.Svg", name: "box"}, instr.args)
      end)

    assert box_call
    # `box (Config svgConfig) b` desugars to a real 2-arg function; the call site
    # must keep both svgConfig and boxy as direct args (not drop to a 0-arg
    # call_fn + call_closure partial).
    assert length(box_call.args.args) == 2
  end

  test "unqualified Svg.Attributes call in Internal.Svg.Arrow lowers to html_cmd attr" do
    Process.put(:elmc_codegen_opts, %{web: true, targets: [:wasm]})

    on_exit(fn ->
      Process.delete(:elmc_codegen_opts)
    end)

    decl_map = %{
      {"Svg.Attributes", "strokeOpacity"} => %{
        name: "strokeOpacity",
        args: ["value"],
        expr: %{op: :int_literal, value: 0}
      }
    }

    expr = %{
      op: :call,
      name: "strokeOpacity",
      args: [%{op: :string_literal, value: "0.5"}]
    }

    ctx =
      Context.new(
        module: "Internal.Svg.Arrow",
        function_name: "arrow",
        params: ["arr"],
        decl_map: decl_map
      )

    b0 = Builder.new("Internal.Svg.Arrow", "arrow", args: ["arr"])

    assert {:ok, _reg, b1} = Call.compile_call(expr, ctx, b0)

    html_cmd =
      (b1.blocks ++ [b1.current_block])
      |> Enum.flat_map(& &1.instrs)
      |> Enum.find(&(&1.op == :html_cmd))

    assert html_cmd
    assert Map.get(html_cmd.args, :kind) == 4
  end

  test "oversaturated qualified call uses scratch dest under RC function tail" do
    decl_map = %{
      {"Diagram.Svg.Config", "withCellAttributesFunction"} => %{
        name: "withCellAttributesFunction",
        args: ["func"],
        expr: %{
          op: :qualified_call,
          target: "Internal.Svg.Config.withBoxAttributes",
          args: [%{op: :var, name: "func"}]
        }
      },
      {"Diagram.Svg.Config", "forStringLabels"} => %{
        name: "forStringLabels",
        args: [],
        expr: %{
          op: :qualified_call,
          target: "Internal.Svg.Config.forStringLabels",
          args: []
        }
      }
    }

    expr = %{
      op: :qualified_call,
      target: "Diagram.Svg.Config.withCellAttributesFunction",
      args: [
        %{op: :var, name: "wiringCellAttributes"},
        %{op: :qualified_call, target: "Diagram.Svg.Config.forStringLabels", args: []}
      ]
    }

    ctx =
      Context.new(
        module: "Route.Index",
        function_name: "wiringSvgConfig",
        params: ["wiringCellAttributes"],
        decl_map: decl_map,
        rc_required: true,
        fallible: true,
        function_tail: true
      )

    b0 =
      Builder.new("Route.Index", "wiringSvgConfig",
        args: ["wiringCellAttributes"],
        rc_required: true,
        fallible: true
      )
      |> Builder.catch_begin()

    {_, b1} = Builder.get_or_load_param(b0, 0, "wiringCellAttributes")

    assert {:ok, _reg, _b2} = Call.compile_call(expr, ctx, b1)
  end

  test "zero-arity MeshIndexed3-style value applies via call_closure" do
    # WebGL.indexedTriangles = MeshIndexed3 {…} — IR args [], type still arity-2.
    # Direct call_fn(verts, indices) must not swallow args (returns the CAF closure).
    decl_map = %{
      {"WebGL", "indexedTriangles"} => %{
        name: "indexedTriangles",
        args: [],
        type: "List a -> List (Int, Int, Int) -> Mesh a",
        expr: %{
          op: :constructor_call,
          target: "MeshIndexed3",
          args: [%{op: :record, fields: []}]
        }
      }
    }

    expr = %{
      op: :qualified_call,
      target: "WebGL.indexedTriangles",
      args: [
        %{op: :var, name: "verts"},
        %{op: :var, name: "indices"}
      ]
    }

    ctx =
      Context.new(
        module: "Scene3d.Mesh",
        function_name: "toWebGL",
        params: ["verts", "indices"],
        decl_map: decl_map,
        rc_required: true,
        fallible: true
      )

    b0 =
      Builder.new("Scene3d.Mesh", "toWebGL",
        args: ["verts", "indices"],
        rc_required: true,
        fallible: true
      )
      |> Builder.catch_begin()

    {_, b1} = Builder.get_or_load_param(b0, 0, "verts")
    {_, b2} = Builder.get_or_load_param(b1, 1, "indices")

    assert {:ok, _reg, b3} = Call.compile_call(expr, ctx, b2)

    instrs =
      (b3.blocks ++ [b3.current_block])
      |> Enum.flat_map(& &1.instrs)

    assert Enum.any?(instrs, &(&1.op == :call_fn))
    assert Enum.any?(instrs, &(&1.op == :call_closure))

    call_fn = Enum.find(instrs, &(&1.op == :call_fn))
    assert Map.get(call_fn.args, :args) == [] or Map.get(call_fn.args, :args) == nil
  end

  test "zero-arity eta-reduced partial applies via call_closure" do
    # Vector3d.normalize = scaleTo (Quantity.float 1) — IR args [], body is a
    # partial call, type still arity-1. Direct call_fn(vec) drops the arg under
    # wat2wasm arity fixup and returns the unapplied scaleTo closure as the
    # "normal" (all-zero Block3d facet normals / white PBR).
    decl_map = %{
      {"Vector3d", "normalize"} => %{
        name: "normalize",
        args: [],
        type: "Vector3d units coordinates -> Vector3d Unitless coordinates",
        expr: %{
          op: :qualified_call,
          target: "Vector3d.scaleTo",
          args: [
            %{
              op: :qualified_call,
              target: "Quantity.float",
              args: [%{op: :float_literal, value: 1.0}]
            }
          ]
        }
      }
    }

    expr = %{
      op: :qualified_call,
      target: "Vector3d.normalize",
      args: [%{op: :var, name: "vec"}]
    }

    ctx =
      Context.new(
        module: "Scene3d.Mesh",
        function_name: "triangleNormal",
        params: ["vec"],
        decl_map: decl_map,
        rc_required: true,
        fallible: true
      )

    b0 =
      Builder.new("Scene3d.Mesh", "triangleNormal",
        args: ["vec"],
        rc_required: true,
        fallible: true
      )
      |> Builder.catch_begin()

    {_, b1} = Builder.get_or_load_param(b0, 0, "vec")

    assert {:ok, _reg, b2} = Call.compile_call(expr, ctx, b1)

    instrs =
      (b2.blocks ++ [b2.current_block])
      |> Enum.flat_map(& &1.instrs)

    assert Enum.any?(instrs, &(&1.op == :call_fn))
    assert Enum.any?(instrs, &(&1.op == :call_closure))

    call_fn = Enum.find(instrs, &(&1.op == :call_fn))
    assert Map.get(call_fn.args, :args) == [] or Map.get(call_fn.args, :args) == nil

    call_closure = Enum.find(instrs, &(&1.op == :call_closure))
    assert length(Map.get(call_closure.args, :args) || []) == 1
  end

  test "qualified Html.Attributes.width ignores local width binding" do
    Process.put(:elmc_codegen_opts, %{web: true, targets: [:wasm]})

    on_exit(fn ->
      Process.delete(:elmc_codegen_opts)
    end)

    decl_map = %{
      {"Html.Attributes", "width"} => %{
        name: "width",
        args: ["n"],
        expr: %{
          op: :qualified_call,
          target: "Elm.Kernel.VirtualDom.attribute",
          args: [
            %{op: :string_literal, value: "width"},
            %{
              op: :qualified_call,
              target: "String.fromInt",
              args: [%{op: :var, name: "n"}]
            }
          ]
        }
      }
    }

    expr = %{
      op: :qualified_call,
      target: "Html.Attributes.width",
      args: [%{op: :int_literal, value: 720}]
    }

    ctx0 =
      Context.new(
        module: "Scene3d",
        function_name: "composite",
        params: [],
        decl_map: decl_map
      )

    b0 = Builder.new("Scene3d", "composite", args: [])
    {width_reg, b1} = Builder.fresh_reg(b0)
    ctx = Context.put_local(ctx0, "width", width_reg)

    assert {:ok, _reg, b2} = Call.compile_call(expr, ctx, b1)

    instrs =
      (Map.get(b2, :blocks, []) ++ [Map.get(b2, :current_block)])
      |> Enum.flat_map(&Map.get(&1, :instrs, []))

    refute Enum.any?(instrs, fn
             %{op: :call_closure, args: %{callee: ^width_reg}} -> true
             _ -> false
           end)

    assert Enum.any?(instrs, fn
             %{op: :call_fn, args: %{module: "Html.Attributes", name: "width"}} -> true
             %{op: :html_cmd} -> true
             _ -> false
           end)
  end

  test "unqualified width still applies local binding when present" do
    expr = %{
      op: :call,
      name: "width",
      args: [%{op: :int_literal, value: 720}]
    }

    ctx0 =
      Context.new(
        module: "Scene3d",
        function_name: "composite",
        params: [],
        decl_map: %{}
      )

    b0 = Builder.new("Scene3d", "composite", args: [])
    {width_reg, b1} = Builder.fresh_reg(b0)
    ctx = Context.put_local(ctx0, "width", width_reg)

    assert {:ok, _reg, b2} = Call.compile_call(expr, ctx, b1)

    instrs =
      (Map.get(b2, :blocks, []) ++ [Map.get(b2, :current_block)])
      |> Enum.flat_map(&Map.get(&1, :instrs, []))

    assert Enum.any?(instrs, fn
             %{op: :call_closure, args: %{callee: ^width_reg}} -> true
             _ -> false
           end)
  end

  test "zero-arity helper called with args lowers to closure apply chain" do
    decl_map = %{
      {"Demo", "thunk"} => %{
        name: "thunk",
        args: [],
        expr: %{
          op: :lambda,
          args: ["x"],
          body: %{op: :int_literal, value: 1}
        }
      }
    }

    expr = %{
      op: :qualified_call,
      target: "Demo.thunk",
      args: [
        %{op: :int_literal, value: 10},
        %{op: :int_literal, value: 20}
      ]
    }

    ctx =
      Context.new(
        module: "Main",
        function_name: "go",
        params: [],
        decl_map: decl_map
      )

    b0 = Builder.new("Main", "go", args: [])

    assert {:ok, _reg, b1} = Call.compile_call(expr, ctx, b0)

    instrs =
      (Map.get(b1, :blocks, []) ++ [Map.get(b1, :current_block)])
      |> Enum.flat_map(&Map.get(&1, :instrs, []))

    assert Enum.any?(
             instrs,
             &match?(%{op: :call_fn, args: %{module: "Demo", name: "thunk", args: [0, 1]}}, &1)
           )

    refute Enum.any?(instrs, &match?(%{op: :call_closure}, &1))
  end

  test "Array.push lowers under web plan when Array_elm_builtin pattern binds tail" do
    decl_map = %{
      {"Array", "push"} => %{
        name: "push",
        args: ["a"],
        expr: %{
          op: :lambda,
          args: ["a"],
          body: %{
            op: :lambda,
            args: ["patternArg2"],
            body: %{
              op: :case,
              subject: %{op: :var, name: "patternArg2"},
              branches: [
                %{
                  pattern: %{
                    kind: :constructor,
                    name: "Array_elm_builtin",
                    resolved_name: "Array_elm_builtin",
                    tag: 1,
                    bind: "array",
                    arg_pattern: %{
                      kind: :tuple,
                      elements: [
                        %{kind: :wildcard},
                        %{
                          kind: :tuple,
                          elements: [
                            %{kind: :wildcard},
                            %{
                              kind: :tuple,
                              elements: [%{kind: :wildcard}, %{kind: :var, name: "tail"}]
                            }
                          ]
                        }
                      ]
                    }
                  },
                  expr: %{
                    op: :qualified_call,
                    target: "Array.unsafeReplaceTail",
                    args: [
                      %{
                        op: :qualified_call,
                        target: "Elm.JsArray.push",
                        args: [%{op: :var, name: "a"}, %{op: :var, name: "tail"}]
                      },
                      %{op: :var, name: "array"}
                    ]
                  }
                }
              ]
            }
          }
        }
      }
    }

    Process.put(:elmc_constructor_tags, %{"Array_elm_builtin" => 1})

    decl = Map.fetch!(decl_map, {"Array", "push"})

    assert {:ok, _plan} = Function.lower(decl, "Array", decl_map, rc_required: false)
  end

  test "self-recursive let binding lowers via letrec forward refs" do
    letrec_decl = %{
      name: "loop",
      args: [],
      expr: %{
        op: :let_in,
        name: "f",
        value_expr: %{
          op: :lambda,
          args: ["x"],
          body: %{
            op: :call,
            name: "f",
            args: [%{op: :var, name: "x"}]
          }
        },
        in_expr: %{
          op: :call,
          name: "f",
          args: [%{op: :int_literal, value: 1}]
        }
      }
    }

    assert {:ok, _plan} = Function.lower(letrec_decl, "Main", %{}, rc_required: false)
  end

  test "Browser.application qualified call lowers to browser_cmd with impl record" do
    Process.put(:elmc_codegen_opts, %{web: true, target: :wasm, emit_wasm: true})

    expr = %{
      op: :qualified_call,
      target: "Browser.application",
      args: [
        %{
          op: :record_literal,
          fields: [
            %{name: "init", expr: %{op: :lambda, args: ["flags"], body: %{op: :int_literal, value: 0}}},
            %{name: "view", expr: %{op: :lambda, args: ["model"], body: %{op: :int_literal, value: 0}}},
            %{name: "update", expr: %{op: :lambda, args: ["msg", "model"], body: %{op: :int_literal, value: 0}}},
            %{name: "subscriptions", expr: %{op: :lambda, args: ["model"], body: %{op: :int_literal, value: 0}}}
          ]
        }
      ]
    }

    ctx = Context.new(module: "Main", function_name: "main", decl_map: %{}, params: [])
    b0 = Builder.new("Main", "main", args: [])

    assert {:ok, _reg, b1} = Call.compile_call(expr, ctx, b0)

    browser_cmd =
      (b1.blocks ++ [b1.current_block])
      |> Enum.flat_map(& &1.instrs)
      |> Enum.find(&(&1.op == :browser_cmd))

    assert browser_cmd
    assert length(Map.get(browser_cmd.args, :params, [])) == 1

    kind =
      case browser_cmd.args.kind do
        %{value: value} -> value
        value when is_integer(value) -> value
      end

    assert kind == 1

    record_new =
      (b1.blocks ++ [b1.current_block])
      |> Enum.flat_map(& &1.instrs)
      |> Enum.find(fn instr ->
        instr.op == :call_runtime and Map.get(instr.args, :builtin) == :record_new
      end)

    assert record_new
    # Anonymous impl records canonicalize to Elm alphabetical field order.
    assert Map.get(record_new.args, :field_names) == [
             "init",
             "subscriptions",
             "update",
             "view"
           ]
  end

  test "web rewrite gives Html.map alias two wasm params and html_cmd body" do
    Process.put(:elmc_codegen_opts, %{web: true, targets: [:wasm]})

    on_exit(fn ->
      Process.delete(:elmc_codegen_opts)
    end)

    html_map = %{
      name: "map",
      args: [],
      expr: %{op: :qualified_call, target: "VirtualDom.map", args: []}
    }

    rewritten =
      Elmc.Backend.Plan.Lower.Platform.Web.rewrite_html_map_function_decl(
        "Html",
        html_map,
        %{web: true, targets: [:wasm]}
      )

    assert rewritten.args == ["func", "node"]
    assert %{op: :html_cmd, kind: %{value: 3}} = rewritten.expr

    assert {:ok, plan} =
             Function.lower(rewritten, "Html", %{{"Html", "map"} => rewritten}, rc_required: false)

    assert :ok = Verify.run(plan)

    html_cmd =
      plan.blocks
      |> Enum.flat_map(& &1.instrs)
      |> Enum.find(&(&1.op == :html_cmd))

    assert html_cmd
    assert length(Map.get(html_cmd.args, :params, [])) == 2
  end

  test "lambda capture free vars ignore call targets and union ctor metadata" do
    body = %{
      op: :let_in,
      name: "fetcherState",
      value_expr: %{op: :tuple_second_expr, arg: %{op: :var, name: "tupleArg"}},
      in_expr: %{
        op: :record_update,
        base: %{op: :var, name: "fetcherState"},
        fields: [
          %{
            name: "status",
            expr: %{
              op: :qualified_call,
              target: "Maybe.withDefault",
              args: [
                %{value: 1, op: :int_literal, union_ctor: "Pages.ConcurrentSubmission.Submitting"},
                %{
                  op: :qualified_call,
                  target: "Maybe.map",
                  args: [
                    %{
                      op: :partial_constructor,
                      target: "Pages.ConcurrentSubmission.Reloading",
                      args: [],
                      arity: 1
                    },
                    %{op: :var, name: "maybeFetcherDoneActionData"}
                  ]
                }
              ]
            }
          }
        ]
      }
    }

    assert VarAnalysis.lambda_capture_free_vars(body, ["tupleArg"]) ==
             MapSet.new(["maybeFetcherDoneActionData"])
  end

  test "lambda capture free vars include call-argument closures but not nested body closures" do
    body = %{
      op: :qualified_call,
      target: "Maybe.map",
      args: [
        %{
          op: :lambda,
          args: ["tupleArg"],
          body: %{
            op: :qualified_call,
            target: "Maybe.map",
            args: [
              %{op: :partial_constructor, target: "Pages.ConcurrentSubmission.Reloading", args: [], arity: 1},
              %{op: :var, name: "maybeFetcherDoneActionData"}
            ]
          }
        },
        %{op: :var, name: "items"}
      ]
    }

    assert VarAnalysis.lambda_capture_free_vars(body, ["items"]) ==
             MapSet.new(["maybeFetcherDoneActionData"])
  end

  test "nested lambda capture ignores case pattern locals from inner closures" do
    decl_map = %{}

    ctx =
      Context.new(
        module: "Pages.Internal.Platform",
        function_name: "loadDataAndUpdateUrl",
        params: ["tupleArg"],
        decl_map: decl_map
      )

    b0 = Builder.new("Pages.Internal.Platform", "loadDataAndUpdateUrl", args: ["tupleArg"])

    body = %{
      op: :lambda,
      args: ["maybeUserMsg"],
      body: %{
        op: :lambda,
        args: ["model"],
        body: %{
          op: :case,
          subject: "caseSubject",
          branches: [
            %{
              pattern: %{
                kind: :tuple,
                elements: [
                  %{kind: :var, name: "userModel"},
                  %{kind: :wildcard}
                ]
              },
              expr: %{
                op: :record_literal,
                fields: [
                  %{name: "userModel", expr: %{op: :var, name: "userModel"}},
                  %{name: "pageData", expr: %{op: :var, name: "model"}}
                ]
              }
            },
            %{
              pattern: %{kind: :wildcard},
              expr: %{op: :var, name: "model"}
            }
          ]
        }
      }
    }

    assert MapSet.disjoint?(
             VarAnalysis.lambda_capture_free_vars(body, ["tupleArg"]),
             MapSet.new(["userModel"])
           )

    assert MapSet.disjoint?(
             VarAnalysis.lambda_capture_free_vars(
               body.body,
               ["maybeUserMsg"]
             ),
             MapSet.new(["userModel"])
           )

    assert {:ok, _reg, _b1} =
             Elmc.Backend.Plan.Lower.Lambda.compile(
               body,
               %{ctx | params: ["tupleArg", "caseSubject"]},
               b0
             )
  end

  test "lambda capture free vars ignore operator call names" do
    body = %{
      op: :call,
      name: "__add__",
      args: [
        %{
          op: :call,
          name: "__mul__",
          args: [
            %{op: :sub_const, var: "n0", value: 216},
            %{op: :int_literal, value: 256}
          ]
        },
        %{op: :var, name: "b0"}
      ]
    }

    assert VarAnalysis.lambda_capture_free_vars(body, ["b0"]) == MapSet.new(["n0"])
  end

  test "lambda capture free vars peel curried lambda chains for let-bound locals" do
    body = %{
      op: :lambda,
      args: ["a"],
      body: %{
        op: :lambda,
        args: ["b"],
        body: %{op: :var, name: "view"}
      }
    }

    assert VarAnalysis.lambda_capture_free_vars(body, ["a"]) == MapSet.new(["view"])
  end

  test "let block reorders pattern bind before bindings that use case pattern locals" do
    ctx =
      Context.new(
        module: "Pages.Internal.Platform",
        function_name: "loadDataAndUpdateUrl_case_probe",
        params: ["caseSubject"],
        decl_map: %{}
      )

    b0 =
      Builder.new("Pages.Internal.Platform", "loadDataAndUpdateUrl_case_probe",
        args: ["caseSubject"]
      )

    expr = %{
      op: :let_in,
      name: "updatedPageData",
      value_expr: %{
        op: :record_literal,
        fields: [
          %{name: "userModel", expr: %{op: :var, name: "userModel"}},
          %{name: "pageData", expr: %{op: :int_literal, value: 1}}
        ]
      },
      in_expr: %{
        op: :let_in,
        name: "__patternBind_1",
        value_expr: %{op: :var, name: "caseSubject"},
        in_expr: %{
          op: :case,
          subject: "__patternBind_1",
          branches: [
            %{
              pattern: %{
                kind: :tuple,
                elements: [
                  %{kind: :var, name: "userModel"},
                  %{kind: :wildcard}
                ]
              },
              expr: %{op: :var, name: "updatedPageData"}
            },
            %{
              pattern: %{kind: :wildcard},
              expr: %{op: :int_literal, value: 0}
            }
          ]
        }
      }
    }

    assert {:ok, _reg, _b1} = Elmc.Backend.Plan.Lower.Expr.compile(expr, ctx, b0)
  end

  test "let block reorders pattern bind before earlier bindings that use case pattern locals" do
    ctx =
      Context.new(
        module: "Pages.Internal.Platform",
        function_name: "loadDataAndUpdateUrl_early_user_probe",
        params: ["caseSubject"],
        decl_map: %{}
      )

    b0 =
      Builder.new("Pages.Internal.Platform", "loadDataAndUpdateUrl_early_user_probe",
        args: ["caseSubject"]
      )

    expr = %{
      op: :let_in,
      name: "updatedPageData",
      value_expr: %{
        op: :record_literal,
        fields: [
          %{name: "userModel", expr: %{op: :var, name: "userModel"}},
          %{name: "pageData", expr: %{op: :int_literal, value: 1}}
        ]
      },
      in_expr: %{
        op: :let_in,
        name: "__patternBind_1",
        value_expr: %{op: :var, name: "caseSubject"},
        in_expr: %{
          op: :case,
          subject: "__patternBind_1",
          branches: [
            %{
              pattern: %{
                kind: :tuple,
                elements: [
                  %{kind: :var, name: "userModel"},
                  %{kind: :wildcard}
                ]
              },
              expr: %{op: :var, name: "updatedPageData"}
            },
            %{
              pattern: %{kind: :wildcard},
              expr: %{op: :int_literal, value: 0}
            }
          ]
        }
      }
    }

    assert {:ok, _reg, _b1} = Elmc.Backend.Plan.Lower.Expr.compile(expr, ctx, b0)
  end

  test "web rewrite eta-expands partial Html.map bindings" do
    Process.put(:elmc_codegen_opts, %{web: true, targets: [:wasm]})

    on_exit(fn ->
      Process.delete(:elmc_codegen_opts)
    end)

    wrap = %{
      name: "wrap",
      args: [],
      type: "Html.Html msg -> Html.Html msg",
      expr: %{
        op: :qualified_call,
        target: "Html.map",
        args: [%{op: :var, name: "identity"}]
      }
    }

    rewritten =
      Elmc.Backend.Plan.Lower.Platform.Web.rewrite_partial_html_map_function_decl(
        "Main",
        wrap,
        %{web: true, targets: [:wasm]}
      )

    assert rewritten.args == ["html"]
    assert %{op: :html_cmd, kind: %{value: 3}} = rewritten.expr
  end

  test "call site of partial Html.map wrap uses 1-arg call_fn, not CAF+closure" do
    Process.put(:elmc_codegen_opts, %{web: true, targets: [:wasm]})

    on_exit(fn ->
      Process.delete(:elmc_codegen_opts)
    end)

    wrap = %{
      name: "wrap",
      args: [],
      type: "Html.Html msg -> Html.Html msg",
      expr: %{
        op: :qualified_call,
        target: "Html.map",
        args: [%{op: :qualified_call, target: "Basics.identity", args: []}]
      }
    }

    main = %{
      name: "main",
      args: [],
      type: "Html.Html msg",
      expr: %{
        op: :qualified_call,
        target: "Main.wrap",
        args: [
          %{
            op: :qualified_call,
            target: "Html.text",
            args: [%{op: :string_literal, value: "x"}]
          }
        ]
      }
    }

    decl_map = %{
      {"Main", "wrap"} => wrap,
      {"Main", "main"} => main
    }

    assert {:ok, plan} =
             Elmc.Backend.Plan.Lower.Function.lower(main, "Main", decl_map, web: true, targets: [:wasm])

    wrap_calls =
      for block <- plan.blocks,
          %{op: :call_fn, args: %{module: "Main", name: "wrap", args: args}} <- block.instrs,
          do: args

    refute wrap_calls == [], "expected a call_fn to Main.wrap"
    assert Enum.any?(wrap_calls, &(length(&1) == 1)),
           "wrap must be called with 1 arg after decl_map rewrite; got #{inspect(wrap_calls)}"

    refute Enum.any?(plan.blocks, fn block ->
             Enum.any?(block.instrs, fn
               %{op: :call_closure} -> true
               _ -> false
             end)
           end),
           "partial Html.map wrap must not lower via CAF + call_closure"
  end
end
