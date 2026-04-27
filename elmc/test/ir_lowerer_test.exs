defmodule Elmc.IRLowererTest do
  use ExUnit.Case

  alias ElmEx.Frontend.Bridge
  alias ElmEx.Frontend.Project
  alias ElmEx.Frontend.Module, as: FrontendModule
  alias ElmEx.IR.Lowerer

  test "lowerer injects ownership annotations" do
    project_dir = Path.expand("fixtures/simple_project", __DIR__)
    {:ok, project} = Bridge.load_project(project_dir)

    assert {:ok, ir} = Lowerer.lower_project(project)

    function_decl =
      ir.modules
      |> Enum.flat_map(& &1.declarations)
      |> Enum.find(&(&1.kind == :function and &1.name == "headOrZero"))

    assert function_decl
    assert :retain_result in function_decl.ownership
  end

  test "lowerer rewrites nested constructor patterns with tags" do
    project_dir = Path.expand("fixtures/simple_project", __DIR__)
    {:ok, project} = Bridge.load_project(project_dir)
    assert {:ok, ir} = Lowerer.lower_project(project)

    nested_result =
      ir.modules
      |> Enum.find(&(&1.name == "CoreCompliance"))
      |> Map.fetch!(:declarations)
      |> Enum.find(&(&1.kind == :function and &1.name == "nestedResult"))

    assert nested_result
    assert nested_result.expr.op == :case

    ok_branch =
      Enum.find(
        nested_result.expr.branches,
        &(&1.pattern.kind == :constructor and &1.pattern.name == "Ok")
      )

    assert ok_branch
    assert ok_branch.pattern.tag == 1
    assert ok_branch.pattern.arg_pattern.kind == :constructor
    assert ok_branch.pattern.arg_pattern.name == "Just"
    assert ok_branch.pattern.arg_pattern.tag == 1
  end

  test "lowerer preserves union payload specs for semantic phases" do
    project_dir = Path.expand("fixtures/simple_project", __DIR__)
    {:ok, project} = Bridge.load_project(project_dir)
    assert {:ok, ir} = Lowerer.lower_project(project)

    main_mod = Enum.find(ir.modules, &(&1.name == "Main"))
    assert main_mod

    msg_union = main_mod.unions["Msg"]
    assert msg_union
    assert is_map(msg_union.payload_specs)
    assert msg_union.payload_specs["Increment"] == nil
    assert msg_union.payload_specs["ProvideTemperature"] == "Temperature"
    assert msg_union.payload_specs["CurrentTimeString"] == "String"
    assert msg_union.payload_kinds["Increment"] == :none
    assert msg_union.payload_kinds["ProvideTemperature"] == :single
    assert msg_union.payload_kinds["CurrentTimeString"] == :single
  end

  test "lowerer derives conservative payload kinds for unions" do
    project = %Project{
      project_dir: "/tmp",
      elm_json: %{},
      modules: [
        %FrontendModule{
          name: "Main",
          path: "/tmp/Main.elm",
          imports: [],
          declarations: [
            %{
              kind: :union,
              name: "Msg",
              constructors: [
                %{name: "None", arg: nil},
                %{name: "One", arg: "Int"},
                %{name: "Pair", arg: "Int Int"},
                %{name: "Fn", arg: "(Int -> String)"}
              ],
              span: %{start_line: 1, end_line: 5}
            }
          ]
        }
      ]
    }

    assert {:ok, ir} = Lowerer.lower_project(project)
    main_mod = Enum.find(ir.modules, &(&1.name == "Main"))
    msg_union = main_mod.unions["Msg"]

    assert msg_union.payload_kinds == %{
             "None" => :none,
             "One" => :single,
             "Pair" => :multi,
             "Fn" => :function_like
           }
  end

  test "lowerer emits diagnostics for constructor payload arity mismatches" do
    project = %Project{
      project_dir: "/tmp",
      elm_json: %{},
      modules: [
        %FrontendModule{
          name: "Main",
          path: "/tmp/Main.elm",
          imports: [],
          declarations: [
            %{
              kind: :union,
              name: "Msg",
              constructors: [
                %{name: "NoArg", arg: nil},
                %{name: "WithArg", arg: "Int"}
              ],
              span: %{start_line: 1, end_line: 3}
            },
            %{
              kind: :function_signature,
              name: "bad",
              type: "Msg -> Int",
              span: %{start_line: 5, end_line: 5}
            },
            %{
              kind: :function_definition,
              name: "bad",
              args: ["msg"],
              body: "case msg of ...",
              span: %{start_line: 6, end_line: 9},
              expr: %{
                op: :case,
                subject: "msg",
                branches: [
                  %{
                    pattern: %{
                      kind: :constructor,
                      name: "NoArg",
                      arg_pattern: %{kind: :var, name: "x"}
                    },
                    expr: %{op: :int_literal, value: 0}
                  },
                  %{
                    pattern: %{kind: :constructor, name: "WithArg"},
                    expr: %{op: :int_literal, value: 1}
                  }
                ]
              }
            }
          ]
        }
      ]
    }

    assert {:ok, ir} = Lowerer.lower_project(project)

    assert Enum.any?(
             ir.diagnostics,
             &(String.contains?(&1.message, "NoArg") and
                 &1.code == "constructor_payload_arity" and
                 &1.constructor == "NoArg" and
                 &1.expected_kind == :none and
                 &1.has_arg_pattern == true and
                 &1.module == "Main" and
                 &1.function == "bad" and
                 &1.line == 6 and
                 String.contains?(&1.message, "payload kind is none"))
           )

    assert Enum.any?(
             ir.diagnostics,
             &(String.contains?(&1.message, "WithArg") and
                 &1.code == "constructor_payload_arity" and
                 &1.constructor == "WithArg" and
                 &1.expected_kind == :single and
                 &1.has_arg_pattern == false and
                 &1.module == "Main" and
                 &1.function == "bad" and
                 &1.line == 6 and
                 String.contains?(&1.message, "expects a payload pattern"))
           )
  end

  test "lowerer emits payload diagnostics from nested case used as case subject" do
    project = %Project{
      project_dir: "/tmp",
      elm_json: %{},
      modules: [
        %FrontendModule{
          name: "Main",
          path: "/tmp/Main.elm",
          imports: [],
          declarations: [
            %{
              kind: :union,
              name: "Msg",
              constructors: [%{name: "NoArg", arg: nil}],
              span: %{start_line: 1, end_line: 2}
            },
            %{
              kind: :function_signature,
              name: "badNested",
              type: "Int",
              span: %{start_line: 4, end_line: 4}
            },
            %{
              kind: :function_definition,
              name: "badNested",
              args: [],
              body: "case (case msg of ...) of ...",
              span: %{start_line: 5, end_line: 11},
              expr: %{
                op: :case,
                subject: %{
                  op: :case,
                  subject: "msg",
                  branches: [
                    %{
                      pattern: %{
                        kind: :constructor,
                        name: "NoArg",
                        arg_pattern: %{kind: :var, name: "x"}
                      },
                      expr: %{op: :int_literal, value: 0}
                    }
                  ]
                },
                branches: [
                  %{pattern: %{kind: :wildcard}, expr: %{op: :int_literal, value: 1}}
                ]
              }
            }
          ]
        }
      ]
    }

    assert {:ok, ir} = Lowerer.lower_project(project)

    assert Enum.any?(
             ir.diagnostics,
             &(&1.code == "constructor_payload_arity" and
                 &1.constructor == "NoArg" and
                 &1.function == "badNested")
           )
  end

  test "lowerer emits diagnostics for constructor call arity mismatches in expressions" do
    project = %Project{
      project_dir: "/tmp",
      elm_json: %{},
      modules: [
        %FrontendModule{
          name: "Main",
          path: "/tmp/Main.elm",
          imports: [],
          declarations: [
            %{
              kind: :union,
              name: "Msg",
              constructors: [
                %{name: "NoArg", arg: nil},
                %{name: "WithArg", arg: "Int"}
              ],
              span: %{start_line: 1, end_line: 3}
            },
            %{
              kind: :function_signature,
              name: "badExpr",
              type: "Int",
              span: %{start_line: 5, end_line: 5}
            },
            %{
              kind: :function_definition,
              name: "badExpr",
              args: [],
              body: "NoArg 1 + (WithArg 1 2)",
              span: %{start_line: 6, end_line: 6},
              expr: %{
                op: :call,
                name: "__add__",
                args: [
                  %{
                    op: :constructor_call,
                    target: "NoArg",
                    args: [%{op: :int_literal, value: 1}]
                  },
                  %{
                    op: :constructor_call,
                    target: "WithArg",
                    args: [%{op: :int_literal, value: 1}, %{op: :int_literal, value: 2}]
                  }
                ]
              }
            }
          ]
        }
      ]
    }

    assert {:ok, ir} = Lowerer.lower_project(project)

    assert Enum.any?(
             ir.diagnostics,
             &(String.contains?(&1.message, "NoArg") and
                 &1.code == "constructor_call_arity" and
                 &1.source == "lowerer/expression" and
                 &1.expected_arity == 0 and
                 &1.args_count == 1 and
                 &1.module == "Main" and
                 &1.function == "badExpr")
           )

    assert Enum.any?(
             ir.diagnostics,
             &(String.contains?(&1.message, "WithArg") and
                 &1.code == "constructor_call_arity" and
                 &1.source == "lowerer/expression" and
                 &1.expected_arity == 1 and
                 &1.args_count == 2 and
                 &1.module == "Main" and
                 &1.function == "badExpr")
           )

    constructor_call_arity =
      Enum.filter(ir.diagnostics, fn diagnostic ->
        diagnostic.code == "constructor_call_arity" and
          diagnostic.source == "lowerer/expression" and
          diagnostic.module == "Main" and
          diagnostic.function == "badExpr"
      end)

    no_arg_count = Enum.count(constructor_call_arity, &(&1.constructor == "NoArg"))
    with_arg_count = Enum.count(constructor_call_arity, &(&1.constructor == "WithArg"))

    assert no_arg_count == 1
    assert with_arg_count == 1
    assert length(constructor_call_arity) == 2
  end

  test "lowerer resolves qualified constructor tags without global name collisions" do
    project = %Project{
      project_dir: "/tmp",
      elm_json: %{},
      modules: [
        %FrontendModule{
          name: "B",
          path: "/tmp/B.elm",
          imports: [],
          declarations: [
            %{
              kind: :union,
              name: "MsgB",
              constructors: [
                %{name: "Other", arg: nil},
                %{name: "Wrap", arg: "Int"}
              ],
              span: %{start_line: 1, end_line: 3}
            }
          ]
        },
        %FrontendModule{
          name: "A",
          path: "/tmp/A.elm",
          imports: [],
          declarations: [
            %{
              kind: :union,
              name: "MsgA",
              constructors: [
                %{name: "Wrap", arg: "Int"}
              ],
              span: %{start_line: 1, end_line: 2}
            }
          ]
        },
        %FrontendModule{
          name: "Main",
          path: "/tmp/Main.elm",
          imports: ["A", "B"],
          declarations: [
            %{
              kind: :function_signature,
              name: "mk",
              type: "Int",
              span: %{start_line: 5, end_line: 5}
            },
            %{
              kind: :function_definition,
              name: "mk",
              args: [],
              body: "B.Wrap 7",
              span: %{start_line: 6, end_line: 6},
              expr: %{
                op: :constructor_call,
                target: "B.Wrap",
                args: [%{op: :int_literal, value: 7}]
              }
            }
          ]
        }
      ]
    }

    assert {:ok, ir} = Lowerer.lower_project(project)

    mk =
      ir.modules
      |> Enum.find(&(&1.name == "Main"))
      |> Map.fetch!(:declarations)
      |> Enum.find(&(&1.kind == :function and &1.name == "mk"))

    assert mk.expr.op == :tuple2
    assert mk.expr.left.op == :int_literal
    assert mk.expr.left.value == 2
    assert mk.expr.right.op == :int_literal
    assert mk.expr.right.value == 7
  end

  test "constructor call arity diagnostics resolve qualified constructors under name collisions" do
    project = %Project{
      project_dir: "/tmp",
      elm_json: %{},
      modules: [
        %FrontendModule{
          name: "A",
          path: "/tmp/A.elm",
          imports: [],
          declarations: [
            %{
              kind: :union,
              name: "MsgA",
              constructors: [%{name: "Wrap", arg: "Int"}],
              span: %{start_line: 1, end_line: 2}
            }
          ]
        },
        %FrontendModule{
          name: "B",
          path: "/tmp/B.elm",
          imports: [],
          declarations: [
            %{
              kind: :union,
              name: "MsgB",
              constructors: [%{name: "Wrap", arg: "Int Int"}],
              span: %{start_line: 1, end_line: 2}
            }
          ]
        },
        %FrontendModule{
          name: "Main",
          path: "/tmp/Main.elm",
          imports: ["A", "B"],
          declarations: [
            %{
              kind: :function_signature,
              name: "badQualified",
              type: "Int",
              span: %{start_line: 5, end_line: 5}
            },
            %{
              kind: :function_definition,
              name: "badQualified",
              args: [],
              body: "A.Wrap 1 2",
              span: %{start_line: 6, end_line: 6},
              expr: %{
                op: :constructor_call,
                target: "A.Wrap",
                args: [%{op: :int_literal, value: 1}, %{op: :int_literal, value: 2}]
              }
            }
          ]
        }
      ]
    }

    assert {:ok, ir} = Lowerer.lower_project(project)

    assert Enum.any?(
             ir.diagnostics,
             &(String.contains?(&1.message, "Wrap") and
                 &1.code == "constructor_call_arity" and
                 &1.source == "lowerer/expression" and
                 &1.expected_arity == 1 and
                 &1.args_count == 2 and
                 &1.module == "Main" and
                 &1.function == "badQualified")
           )
  end

  test "pattern payload diagnostics resolve qualified constructors under name collisions" do
    project = %Project{
      project_dir: "/tmp",
      elm_json: %{},
      modules: [
        %FrontendModule{
          name: "A",
          path: "/tmp/A.elm",
          imports: [],
          declarations: [
            %{
              kind: :union,
              name: "MsgA",
              constructors: [%{name: "Wrap", arg: "Int"}],
              span: %{start_line: 1, end_line: 2}
            }
          ]
        },
        %FrontendModule{
          name: "B",
          path: "/tmp/B.elm",
          imports: [],
          declarations: [
            %{
              kind: :union,
              name: "MsgB",
              constructors: [%{name: "Wrap", arg: nil}],
              span: %{start_line: 1, end_line: 2}
            }
          ]
        },
        %FrontendModule{
          name: "Main",
          path: "/tmp/Main.elm",
          imports: ["A", "B"],
          declarations: [
            %{
              kind: :function_signature,
              name: "badPatternQualified",
              type: "Int",
              span: %{start_line: 5, end_line: 5}
            },
            %{
              kind: :function_definition,
              name: "badPatternQualified",
              args: [],
              body: "case msg of A.Wrap -> 1",
              span: %{start_line: 6, end_line: 8},
              expr: %{
                op: :case,
                subject: "msg",
                branches: [
                  %{
                    pattern: %{kind: :constructor, name: "A.Wrap"},
                    expr: %{op: :int_literal, value: 1}
                  }
                ]
              }
            }
          ]
        }
      ]
    }

    assert {:ok, ir} = Lowerer.lower_project(project)

    assert Enum.any?(
             ir.diagnostics,
             &(String.contains?(&1.message, "A.Wrap") and
                 &1.code == "constructor_payload_arity" and
                 &1.source == "lowerer/pattern" and
                 &1.expected_kind == :single and
                 &1.has_arg_pattern == false and
                 &1.module == "Main" and
                 &1.function == "badPatternQualified")
           )

    pattern_payload_arity =
      Enum.filter(ir.diagnostics, fn diagnostic ->
        diagnostic.code == "constructor_payload_arity" and
          diagnostic.source == "lowerer/pattern" and
          diagnostic.module == "Main" and
          diagnostic.function == "badPatternQualified"
      end)

    a_wrap_count = Enum.count(pattern_payload_arity, &(&1.constructor == "A.Wrap"))

    assert a_wrap_count == 1
    assert length(pattern_payload_arity) == 1
  end

  test "lowerer resolves tags for qualified and local constructors in fixture flow" do
    project_dir = Path.expand("fixtures/qualified_constructor_project", __DIR__)
    {:ok, project} = Bridge.load_project(project_dir)
    assert {:ok, ir} = Lowerer.lower_project(project)

    main_module = Enum.find(ir.modules, &(&1.name == "Main"))
    assert main_module

    from_a =
      main_module.declarations
      |> Enum.find(&(&1.kind == :function and &1.name == "fromA"))

    from_b =
      main_module.declarations
      |> Enum.find(&(&1.kind == :function and &1.name == "fromB"))

    from_b_pair =
      main_module.declarations
      |> Enum.find(&(&1.kind == :function and &1.name == "fromBPair"))

    from_local =
      main_module.declarations
      |> Enum.find(&(&1.kind == :function and &1.name == "fromLocal"))

    match_a =
      main_module.declarations
      |> Enum.find(&(&1.kind == :function and &1.name == "matchA"))

    match_b =
      main_module.declarations
      |> Enum.find(&(&1.kind == :function and &1.name == "matchB"))

    match_b_pair =
      main_module.declarations
      |> Enum.find(&(&1.kind == :function and &1.name == "matchBPair"))

    match_local =
      main_module.declarations
      |> Enum.find(&(&1.kind == :function and &1.name == "matchLocal"))

    assert from_a.expr.op == :tuple2
    assert from_a.expr.left.op == :int_literal
    assert from_a.expr.left.value == 1

    assert from_b.expr.op == :tuple2
    assert from_b.expr.left.op == :int_literal
    assert from_b.expr.left.value == 2

    assert from_b_pair.expr.op == :tuple2
    assert from_b_pair.expr.left.op == :int_literal
    assert from_b_pair.expr.left.value == 3
    assert from_b_pair.expr.right.op == :tuple2

    assert from_local.expr.op == :tuple2
    assert from_local.expr.left.op == :int_literal
    assert from_local.expr.left.value == 2

    assert match_a.expr.op == :case
    assert Enum.at(match_a.expr.branches, 0).pattern.tag == 1

    assert match_b.expr.op == :case
    assert Enum.at(match_b.expr.branches, 0).pattern.tag == 2
    assert Enum.at(match_b.expr.branches, 1).pattern.tag == 2
    assert Enum.at(match_b.expr.branches, 2).pattern.tag == 3
    assert Enum.at(match_b.expr.branches, 3).pattern.tag == 1

    assert match_b_pair.expr.op == :case
    assert Enum.at(match_b_pair.expr.branches, 0).pattern.tag == 3
    assert Enum.at(match_b_pair.expr.branches, 0).pattern.arg_pattern.kind == :tuple

    assert match_local.expr.op == :case
    assert Enum.at(match_local.expr.branches, 0).pattern.tag == 2
    assert Enum.at(match_local.expr.branches, 1).pattern.tag == 1
  end

  test "fixture projects do not emit constructor call arity diagnostics" do
    fixture_dirs = [
      Path.expand("fixtures/simple_project", __DIR__),
      Path.expand("fixtures/qualified_constructor_project", __DIR__)
    ]

    diagnostics =
      fixture_dirs
      |> Enum.flat_map(fn dir ->
        {:ok, project} = Bridge.load_project(dir)
        {:ok, ir} = Lowerer.lower_project(project)
        ir.diagnostics
      end)

    constructor_call_arity = Enum.filter(diagnostics, &(&1.code == "constructor_call_arity"))
    assert constructor_call_arity == []
  end

  test "fixture projects do not emit constructor payload arity diagnostics" do
    fixture_dirs = [
      Path.expand("fixtures/simple_project", __DIR__),
      Path.expand("fixtures/qualified_constructor_project", __DIR__)
    ]

    diagnostics =
      fixture_dirs
      |> Enum.flat_map(fn dir ->
        {:ok, project} = Bridge.load_project(dir)
        {:ok, ir} = Lowerer.lower_project(project)
        ir.diagnostics
      end)

    constructor_payload_arity =
      Enum.filter(diagnostics, &(&1.code == "constructor_payload_arity"))

    assert constructor_payload_arity == []
  end

  test "lowerer does not emit duplicate constructor diagnostics by signature" do
    project = %Project{
      project_dir: "/tmp",
      elm_json: %{},
      modules: [
        %FrontendModule{
          name: "Main",
          path: "/tmp/Main.elm",
          imports: [],
          declarations: [
            %{
              kind: :union,
              name: "Msg",
              constructors: [
                %{name: "NoArg", arg: nil},
                %{name: "WithArg", arg: "Int"}
              ],
              span: %{start_line: 1, end_line: 3}
            },
            %{
              kind: :function_signature,
              name: "bad",
              type: "Int",
              span: %{start_line: 5, end_line: 5}
            },
            %{
              kind: :function_definition,
              name: "bad",
              args: [],
              body: "NoArg 1 + (WithArg 1 2)",
              span: %{start_line: 6, end_line: 6},
              expr: %{
                op: :call,
                name: "__add__",
                args: [
                  %{
                    op: :constructor_call,
                    target: "NoArg",
                    args: [%{op: :int_literal, value: 1}]
                  },
                  %{
                    op: :constructor_call,
                    target: "WithArg",
                    args: [%{op: :int_literal, value: 1}, %{op: :int_literal, value: 2}]
                  }
                ]
              }
            }
          ]
        }
      ]
    }

    assert {:ok, ir} = Lowerer.lower_project(project)

    relevant =
      Enum.filter(ir.diagnostics, fn d ->
        d.code in ["constructor_call_arity", "constructor_payload_arity"]
      end)

    signature_count =
      relevant
      |> Enum.map(fn d ->
        {d.code, d.source, d.module, d.function, d.line, d.constructor, d[:expected_arity],
         d[:args_count], d[:expected_kind], d[:has_arg_pattern]}
      end)
      |> Enum.uniq()
      |> length()

    assert signature_count == length(relevant)
  end

  test "lowerer rewrites constructor calls inside case subject expressions" do
    project = %Project{
      project_dir: "/tmp",
      elm_json: %{},
      modules: [
        %FrontendModule{
          name: "Main",
          path: "/tmp/Main.elm",
          imports: [],
          declarations: [
            %{
              kind: :union,
              name: "MaybeInt",
              constructors: [
                %{name: "Nope", arg: nil},
                %{name: "Yep", arg: "Int"}
              ],
              span: %{start_line: 1, end_line: 3}
            },
            %{
              kind: :function_definition,
              name: "f",
              args: [],
              body: "case Yep 1 of ...",
              span: %{start_line: 5, end_line: 9},
              expr: %{
                op: :case,
                subject: %{
                  op: :constructor_call,
                  target: "Yep",
                  args: [%{op: :int_literal, value: 1}]
                },
                branches: [
                  %{
                    pattern: %{
                      kind: :constructor,
                      name: "Yep",
                      arg_pattern: %{kind: :var, name: "x"}
                    },
                    expr: %{op: :var, name: "x"}
                  }
                ]
              }
            },
            %{
              kind: :function_signature,
              name: "f",
              type: "Int",
              span: %{start_line: 4, end_line: 4}
            }
          ]
        }
      ]
    }

    assert {:ok, ir} = Lowerer.lower_project(project)
    main_mod = Enum.find(ir.modules, &(&1.name == "Main"))
    f_decl = Enum.find(main_mod.declarations, &(&1.kind == :function and &1.name == "f"))

    assert f_decl.expr.op == :case
    assert f_decl.expr.subject.op == :tuple2
    assert f_decl.expr.subject.left == %{op: :int_literal, value: 2}
  end

  test "lowerer rewrites constructor calls inside field access arguments" do
    project = %Project{
      project_dir: "/tmp",
      elm_json: %{},
      modules: [
        %FrontendModule{
          name: "Main",
          path: "/tmp/Main.elm",
          imports: [],
          declarations: [
            %{
              kind: :union,
              name: "MaybeInt",
              constructors: [
                %{name: "Nope", arg: nil},
                %{name: "Yep", arg: "Int"}
              ],
              span: %{start_line: 1, end_line: 3}
            },
            %{
              kind: :function_definition,
              name: "f",
              args: [],
              body: "(Yep 1).value",
              span: %{start_line: 5, end_line: 5},
              expr: %{
                op: :field_access,
                field: "value",
                arg: %{
                  op: :constructor_call,
                  target: "Yep",
                  args: [%{op: :int_literal, value: 1}]
                }
              }
            },
            %{
              kind: :function_signature,
              name: "f",
              type: "Int",
              span: %{start_line: 4, end_line: 4}
            }
          ]
        }
      ]
    }

    assert {:ok, ir} = Lowerer.lower_project(project)
    main_mod = Enum.find(ir.modules, &(&1.name == "Main"))
    f_decl = Enum.find(main_mod.declarations, &(&1.kind == :function and &1.name == "f"))

    assert f_decl.expr.op == :tuple_first
    assert f_decl.expr.arg.op == :tuple2
    assert f_decl.expr.arg.left == %{op: :int_literal, value: 2}
  end

  test "lowerer rewrites constructor calls inside field call receiver and args" do
    project = %Project{
      project_dir: "/tmp",
      elm_json: %{},
      modules: [
        %FrontendModule{
          name: "Main",
          path: "/tmp/Main.elm",
          imports: [],
          declarations: [
            %{
              kind: :union,
              name: "MaybeInt",
              constructors: [
                %{name: "Nope", arg: nil},
                %{name: "Yep", arg: "Int"}
              ],
              span: %{start_line: 1, end_line: 3}
            },
            %{
              kind: :function_definition,
              name: "f",
              args: [],
              body: "(Yep 1).map (Yep 2)",
              span: %{start_line: 5, end_line: 5},
              expr: %{
                op: :field_call,
                field: "map",
                arg: %{
                  op: :constructor_call,
                  target: "Yep",
                  args: [%{op: :int_literal, value: 1}]
                },
                args: [
                  %{op: :constructor_call, target: "Yep", args: [%{op: :int_literal, value: 2}]}
                ]
              }
            },
            %{
              kind: :function_signature,
              name: "f",
              type: "Int",
              span: %{start_line: 4, end_line: 4}
            }
          ]
        }
      ]
    }

    assert {:ok, ir} = Lowerer.lower_project(project)
    main_mod = Enum.find(ir.modules, &(&1.name == "Main"))
    f_decl = Enum.find(main_mod.declarations, &(&1.kind == :function and &1.name == "f"))

    assert f_decl.expr.op == :field_call
    assert f_decl.expr.arg.op == :tuple2
    assert f_decl.expr.arg.left == %{op: :int_literal, value: 2}
    assert Enum.at(f_decl.expr.args, 0)[:op] == :tuple2
    assert Enum.at(f_decl.expr.args, 0)[:left] == %{op: :int_literal, value: 2}
  end

  test "lowerer includes top-level function definitions without signatures" do
    project = %Project{
      project_dir: "/tmp",
      elm_json: %{},
      modules: [
        %FrontendModule{
          name: "Main",
          path: "/tmp/Main.elm",
          imports: [],
          declarations: [
            %{
              kind: :function_definition,
              name: "helper",
              args: ["x"],
              body: "x",
              span: %{start_line: 1, end_line: 1},
              expr: %{op: :var, name: "x"}
            }
          ]
        }
      ]
    }

    assert {:ok, ir} = Lowerer.lower_project(project)
    main_mod = Enum.find(ir.modules, &(&1.name == "Main"))

    helper_decl =
      Enum.find(main_mod.declarations, &(&1.kind == :function and &1.name == "helper"))

    assert helper_decl
    assert helper_decl.type == nil
    assert helper_decl.args == ["x"]
    assert helper_decl.expr == %{op: :var, name: "x"}
  end

  test "lowerer preserves function declaration order by first appearance" do
    project = %Project{
      project_dir: "/tmp",
      elm_json: %{},
      modules: [
        %FrontendModule{
          name: "Main",
          path: "/tmp/Main.elm",
          imports: [],
          declarations: [
            %{
              kind: :function_definition,
              name: "helper",
              args: [],
              body: "1",
              span: %{start_line: 1, end_line: 1},
              expr: %{op: :int_literal, value: 1}
            },
            %{
              kind: :function_definition,
              name: "main",
              args: [],
              body: "2",
              span: %{start_line: 2, end_line: 2},
              expr: %{op: :int_literal, value: 2}
            },
            %{
              kind: :function_signature,
              name: "main",
              type: "Int",
              span: %{start_line: 3, end_line: 3}
            },
            %{
              kind: :function_definition,
              name: "util",
              args: [],
              body: "3",
              span: %{start_line: 4, end_line: 4},
              expr: %{op: :int_literal, value: 3}
            }
          ]
        }
      ]
    }

    assert {:ok, ir} = Lowerer.lower_project(project)
    main_mod = Enum.find(ir.modules, &(&1.name == "Main"))
    names = Enum.map(main_mod.declarations, & &1.name)

    assert names == ["helper", "main", "util"]
    assert Enum.find(main_mod.declarations, &(&1.name == "main")).type == "Int"
  end
end
