defmodule Elmc.PlanWebLoweringGapsTest do
  use ExUnit.Case, async: true

  alias Elmc.Backend.Plan.Builder
  alias Elmc.Backend.Plan.Context
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

    assert Enum.any?(instrs, &match?(%{op: :call_fn, args: %{module: "Demo", name: "thunk", args: []}}, &1))
    assert Enum.count(instrs, &match?(%{op: :call_closure}, &1)) >= 2
    refute Enum.any?(instrs, fn
             %{op: :call_fn, args: %{module: "Demo", name: "thunk", args: args}} when args != [] ->
               true

             _ ->
               false
           end)
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
    assert Map.get(record_new.args, :field_names) == [
             "init",
             "view",
             "update",
             "subscriptions"
           ]
  end
end
