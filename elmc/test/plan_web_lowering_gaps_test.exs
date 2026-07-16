defmodule Elmc.PlanWebLoweringGapsTest do
  use ExUnit.Case, async: true

  alias Elmc.Backend.CCodegen.VarAnalysis
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

  test "web rewrite eta-expands partial Html.map bindings" do
    Process.put(:elmc_codegen_opts, %{web: true, targets: [:wasm]})

    on_exit(fn ->
      Process.delete(:elmc_codegen_opts)
    end)

    wrap = %{
      name: "wrap",
      args: [],
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
end
