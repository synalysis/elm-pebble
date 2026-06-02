defmodule ElmEx.IR.FunctionCallCheckTest do
  use ExUnit.Case

  alias ElmEx.Frontend.Module, as: FrontendModule
  alias ElmEx.Frontend.Project
  alias ElmEx.IR.FunctionCallCheck
  alias ElmEx.IR.Lowerer

  test "reports too many arguments for imported function calls" do
    project = %Project{
      project_dir: "/tmp",
      elm_json: %{"source-directories" => ["src"]},
      modules: [
        ui_module(),
        main_module(%{
          op: :qualified_call,
          target: "Ui.textInt",
          args: [
            %{op: :qualified_call1, target: "Ui.defaultTextOptions"},
            %{op: :record_literal, fields: [%{name: "x", expr: %{op: :int_literal, value: 4}}]},
            %{op: :int_literal, value: 1},
            %{op: :int_literal, value: 2}
          ]
        })
      ]
    }

    assert {:ok, ir} = Lowerer.lower_project(project)

    assert Enum.any?(
             ir.diagnostics,
             &(&1.code == "function_call_arity" and
                 &1.severity == "error" and
                 &1.call_target == "Pebble.Ui.textInt" and
                 &1.expected_arity == 3 and
                 &1.args_count == 4)
           )
  end

  test "allows integer literals for Float parameters like Elm" do
    project = %Project{
      project_dir: "/tmp",
      elm_json: %{"source-directories" => ["src"]},
      modules: [
        ui_module_with_rotation_from_degrees(),
        main_module(%{
          op: :qualified_call,
          target: "Ui.rotationFromDegrees",
          args: [%{op: :int_literal, value: 0}]
        })
      ]
    }

    assert {:ok, ir} = Lowerer.lower_project(project)

    refute Enum.any?(ir.diagnostics, &(&1.code == "function_call_type"))
  end

  test "still rejects Int variables passed to Float parameters" do
    diagnostics =
      FunctionCallCheck.collect_project_diagnostics(
        [
          ui_module_with_rotation_from_degrees(),
          %FrontendModule{
            name: "Main",
            path: "/tmp/src/Main.elm",
            imports: ["Pebble.Ui"],
            import_entries: [%{"module" => "Pebble.Ui", "as" => "Ui", "exposing" => nil}],
            module_exposing: "main",
            declarations: [
              %{
                kind: :function_definition,
                name: "useAngle",
                args: ["angle"],
                type: "Int -> Rotation",
                expr: %{
                  op: :qualified_call,
                  target: "Ui.rotationFromDegrees",
                  args: [%{op: :var, name: "angle"}]
                },
                span: %{start_line: 10, end_line: 10}
              }
            ]
          }
        ],
        %{"Pebble.Ui" => %{names: ["rotationFromDegrees"], types: ["Rotation"], union_constructors: %{}}},
        "/tmp",
        ["src"]
      )

    assert Enum.any?(
             diagnostics,
             &(&1.code == "function_call_type" and
                 &1.expected_type == "Float" and
                 &1.inferred_type == "Int")
           )
  end

  test "reports incompatible argument types for imported function calls" do
    project = %Project{
      project_dir: "/tmp",
      elm_json: %{"source-directories" => ["src"]},
      modules: [
        ui_module(),
        main_module(%{
          op: :qualified_call,
          target: "Ui.textInt",
          args: [
            %{op: :qualified_call1, target: "Resources.DefaultFont"},
            %{op: :qualified_call1, target: "Ui.defaultTextOptions"},
            %{op: :int_literal, value: 1}
          ]
        })
      ]
    }

    assert {:ok, ir} = Lowerer.lower_project(project)

    assert Enum.any?(
             ir.diagnostics,
             &(&1.code == "function_call_type" and
                 &1.severity == "error" and
                 &1.call_target == "Pebble.Ui.textInt" and
                 &1.arg_index == 2 and
                 &1.expected_type == "Point" and
                 &1.inferred_type == "TextOptions")
           )
  end

  test "collect_project_diagnostics resolves module aliases" do
    diagnostics =
      FunctionCallCheck.collect_project_diagnostics(
        [
          ui_module(),
          %FrontendModule{
            name: "Main",
            path: "/tmp/src/Main.elm",
            imports: ["Pebble.Ui"],
            import_entries: [
              %{"module" => "Pebble.Ui", "as" => "Ui", "exposing" => nil}
            ],
            module_exposing: "main",
            declarations: [
              %{
                kind: :function_definition,
                name: "view",
                args: [],
                expr: %{
                  op: :qualified_call,
                  target: "Ui.textInt",
                  args: [
                    %{op: :int_literal, value: 1},
                    %{op: :int_literal, value: 2},
                    %{op: :int_literal, value: 3},
                    %{op: :int_literal, value: 4}
                  ]
                },
                span: %{start_line: 10, end_line: 10}
              }
            ]
          }
        ],
        %{
          "Pebble.Ui" => %{
            names: ["textInt", "defaultTextOptions"],
            types: ["Point", "TextOptions", "Font"],
            union_constructors: %{}
          }
        },
        "/tmp",
        ["src"]
      )

    assert Enum.any?(diagnostics, &(&1.code == "function_call_arity"))
  end

  test "qualified alias types match unqualified imported signatures" do
    diagnostics =
      FunctionCallCheck.collect_project_diagnostics(
        [
          ui_module_with_line(),
          %FrontendModule{
            name: "Main",
            path: "/tmp/src/Main.elm",
            imports: ["Pebble.Ui"],
            import_entries: [%{"module" => "Pebble.Ui", "as" => "Ui", "exposing" => nil}],
            module_exposing: "main",
            declarations: [
              %{
                kind: :function_signature,
                name: "midpoint",
                type: "Ui.Point -> Ui.Point -> Ui.Point",
                span: %{start_line: 4, end_line: 4}
              },
              %{
                kind: :function_definition,
                name: "midpoint",
                args: ["a", "b"],
                expr: %{
                  op: :record_literal,
                  fields: [
                    %{name: "x", expr: %{op: :int_literal, value: 0}},
                    %{name: "y", expr: %{op: :int_literal, value: 0}}
                  ]
                },
                span: %{start_line: 5, end_line: 6}
              },
              %{
                kind: :function_definition,
                name: "view",
                args: ["a", "b", "c"],
                type: "Ui.Point -> Ui.Point -> Ui.Point -> List Ui.RenderOp",
                expr: %{
                  op: :qualified_call,
                  target: "Ui.line",
                  args: [
                    %{
                      op: :call,
                      name: "midpoint",
                      args: [%{op: :var, name: "a"}, %{op: :var, name: "b"}]
                    },
                    %{
                      op: :call,
                      name: "midpoint",
                      args: [%{op: :var, name: "b"}, %{op: :var, name: "c"}]
                    },
                    %{
                      op: :call,
                      name: "midpoint",
                      args: [%{op: :var, name: "c"}, %{op: :var, name: "a"}]
                    }
                  ]
                },
                span: %{start_line: 10, end_line: 10}
              }
            ]
          }
        ],
        %{
          "Pebble.Ui" => %{
            names: ["line"],
            types: ["Point"],
            union_constructors: %{}
          }
        },
        "/tmp",
        ["src"]
      )

    refute Enum.any?(diagnostics, &(&1.code == "function_call_type"))
  end

  test "custom import aliases resolve to the same type identity as callee signatures" do
    diagnostics =
      FunctionCallCheck.collect_project_diagnostics(
        [
          ui_module_with_line(),
          %FrontendModule{
            name: "Main",
            path: "/tmp/src/Main.elm",
            imports: ["Pebble.Ui"],
            import_entries: [%{"module" => "Pebble.Ui", "as" => "Gfx", "exposing" => nil}],
            module_exposing: "main",
            declarations: [
              %{
                kind: :function_signature,
                name: "midpoint",
                type: "Gfx.Point -> Gfx.Point -> Gfx.Point",
                span: %{start_line: 4, end_line: 4}
              },
              %{
                kind: :function_definition,
                name: "midpoint",
                args: ["a", "b"],
                expr: %{
                  op: :record_literal,
                  fields: [
                    %{name: "x", expr: %{op: :int_literal, value: 0}},
                    %{name: "y", expr: %{op: :int_literal, value: 0}}
                  ]
                },
                span: %{start_line: 5, end_line: 6}
              },
              %{
                kind: :function_definition,
                name: "view",
                args: ["a", "b", "c"],
                type: "Gfx.Point -> Gfx.Point -> Gfx.Point -> List Gfx.RenderOp",
                expr: %{
                  op: :qualified_call,
                  target: "Gfx.line",
                  args: [
                    %{
                      op: :call,
                      name: "midpoint",
                      args: [%{op: :var, name: "a"}, %{op: :var, name: "b"}]
                    },
                    %{
                      op: :call,
                      name: "midpoint",
                      args: [%{op: :var, name: "b"}, %{op: :var, name: "c"}]
                    },
                    %{
                      op: :call,
                      name: "midpoint",
                      args: [%{op: :var, name: "c"}, %{op: :var, name: "a"}]
                    }
                  ]
                },
                span: %{start_line: 10, end_line: 10}
              }
            ]
          }
        ],
        %{
          "Pebble.Ui" => %{
            names: ["line"],
            types: ["Point", "RenderOp"],
            union_constructors: %{}
          }
        },
        "/tmp",
        ["src"]
      )

    refute Enum.any?(diagnostics, &(&1.code == "function_call_type"))
  end

  test "call-site line numbers follow source file lines when function bodies contain blank lines" do
    tmp_dir =
      Path.join(System.tmp_dir!(), "function-call-line-#{System.unique_integer([:positive])}")

    src_dir = Path.join(tmp_dir, "src")
    File.mkdir_p!(src_dir)
    main_path = Path.join(src_dir, "Main.elm")

    File.write!(main_path, """
    module Main exposing (main)

    import Pebble.Ui as Ui

    view =
        let
            x =
                1

        in
        Ui.textInt Ui.defaultTextOptions { x = 0, y = 0 } 1 2 3
    """)

    diagnostics =
      FunctionCallCheck.collect_project_diagnostics(
        [
          ui_module(),
          %FrontendModule{
            name: "Main",
            path: main_path,
            imports: ["Pebble.Ui"],
            import_entries: [%{"module" => "Pebble.Ui", "as" => "Ui", "exposing" => nil}],
            module_exposing: "main",
            declarations: [
              %{
                kind: :function_definition,
                name: "view",
                args: [],
                body: """
                let
                    x =
                        1

                in
                Ui.textInt Ui.defaultTextOptions { x = 0, y = 0 } 1 2 3
                """,
                expr: %{
                  op: :qualified_call,
                  target: "Ui.textInt",
                  args: [
                    %{op: :qualified_call1, target: "Ui.defaultTextOptions"},
                    %{
                      op: :record_literal,
                      fields: [%{name: "x", expr: %{op: :int_literal, value: 0}}]
                    },
                    %{op: :int_literal, value: 1},
                    %{op: :int_literal, value: 2},
                    %{op: :int_literal, value: 3}
                  ]
                },
                span: %{start_line: 5, end_line: 12}
              }
            ]
          }
        ],
        %{
          "Pebble.Ui" => %{
            names: ["textInt", "defaultTextOptions"],
            types: ["Point", "TextOptions", "Font"],
            union_constructors: %{}
          }
        },
        tmp_dir,
        ["src"]
      )

    on_exit(fn -> File.rm_rf(tmp_dir) end)

    assert [%{line: 11, code: "function_call_arity"}] =
             Enum.filter(diagnostics, &(&1.code == "function_call_arity"))
  end

  defp ui_module_with_rotation_from_degrees do
    Map.update!(ui_module(), :declarations, fn decls ->
      decls ++
        [
          %{
            kind: :function_signature,
            name: "rotationFromDegrees",
            type: "Float -> Rotation",
            span: %{start_line: 5, end_line: 5}
          }
        ]
    end)
  end

  defp ui_module_with_line do
    Map.update!(ui_module(), :declarations, fn decls ->
      decls ++
        [
          %{
            kind: :function_signature,
            name: "line",
            type: "Point -> Point -> Point -> RenderOp",
            span: %{start_line: 5, end_line: 5}
          }
        ]
    end)
  end

  defp ui_module do
    %FrontendModule{
      name: "Pebble.Ui",
      path: "/tmp/Pebble/Ui.elm",
      imports: [],
      module_exposing: "..",
      declarations: [
        %{
          kind: :type_alias,
          name: "Point",
          fields: ["x", "y"],
          field_types: %{"x" => "Int", "y" => "Int"},
          span: %{start_line: 1, end_line: 1}
        },
        %{
          kind: :type_alias,
          name: "TextOptions",
          fields: ["alignment", "overflow"],
          field_types: %{"alignment" => "TextAlignment", "overflow" => "TextOverflow"},
          span: %{start_line: 2, end_line: 2}
        },
        %{
          kind: :function_signature,
          name: "textInt",
          type: "Font -> Point -> Int -> RenderOp",
          span: %{start_line: 3, end_line: 3}
        },
        %{
          kind: :function_signature,
          name: "defaultTextOptions",
          type: "TextOptions",
          span: %{start_line: 4, end_line: 4}
        }
      ]
    }
  end

  defp main_module(call_expr) do
    %FrontendModule{
      name: "Main",
      path: "/tmp/src/Main.elm",
      imports: ["Pebble.Ui", "Pebble.Ui.Resources"],
      import_entries: [
        %{"module" => "Pebble.Ui", "as" => "Ui", "exposing" => nil},
        %{"module" => "Pebble.Ui.Resources", "as" => "Resources", "exposing" => nil}
      ],
      module_exposing: "main",
      declarations: [
        %{
          kind: :function_definition,
          name: "view",
          args: [],
          expr: call_expr,
          span: %{start_line: 10, end_line: 10}
        }
      ]
    }
  end
end
