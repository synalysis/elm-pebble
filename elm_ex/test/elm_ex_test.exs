defmodule ElmExTest do
  use ExUnit.Case

  alias ElmEx.Frontend.AstContract
  alias ElmEx.Frontend.Module, as: FrontendModule
  alias ElmEx.CoreIR
  alias ElmEx.IR
  alias ElmEx.IR.Lowerer
  alias ElmEx.IR.TopoSort
  alias ElmEx.IR.Validation
  alias ElmEx.DiagnosticFormatter

  # ---------------------------------------------------------------------------
  # Tokeniser / parser smoke
  # ---------------------------------------------------------------------------

  test "elm_ex_elm_lexer tokenises a minimal module header" do
    source = "module Main exposing (main)\n"
    assert {:ok, tokens, _line} = :elm_ex_elm_lexer.string(String.to_charlist(source))
    assert is_list(tokens)
    assert length(tokens) > 0
  end

  test "elm_ex_expr_lexer + parser handle a simple arithmetic expression" do
    assert {:ok, tokens, _} = :elm_ex_expr_lexer.string(String.to_charlist("value + 2"))
    assert {:ok, expr} = :elm_ex_expr_parser.parse(tokens)
    assert is_map(expr)
    assert Map.has_key?(expr, :op)
  end

  test "elm_ex_decl_lexer + parser handle a function signature line" do
    source = "main : Program () Model Msg"
    assert {:ok, tokens, _} = :elm_ex_decl_lexer.string(String.to_charlist(source))
    assert {:ok, decl} = :elm_ex_decl_parser.parse(tokens)
    # The yecc parser returns a tuple: {:function_signature, name, type}
    assert {:function_signature, "main", _type} = decl
  end

  # ---------------------------------------------------------------------------
  # AST contract validation
  # ---------------------------------------------------------------------------

  test "AstContract rejects a declaration without a valid span" do
    bad_module = %FrontendModule{
      name: "Test",
      path: "/tmp/test.elm",
      imports: [],
      declarations: [
        %{
          kind: :function_definition,
          name: "f",
          args: [],
          expr: %{op: :int_literal, value: 1},
          span: nil
        }
      ]
    }

    assert {:error, _} = AstContract.validate_module(bad_module)
  end

  test "AstContract accepts a well-formed module" do
    good_module = %FrontendModule{
      name: "Test",
      path: "/tmp/test.elm",
      imports: ["List"],
      declarations: [
        %{
          kind: :function_definition,
          name: "f",
          args: [],
          expr: %{op: :int_literal, value: 42},
          span: %{start_line: 1, end_line: 2}
        }
      ]
    }

    assert :ok = AstContract.validate_module(good_module)
  end

  test "AstContract accepts nested record field access expressions" do
    good_module = %FrontendModule{
      name: "Test",
      path: "/tmp/test.elm",
      imports: [],
      declarations: [
        %{
          kind: :function_definition,
          name: "f",
          args: ["context"],
          expr: %{
            op: :field_access,
            arg: %{
              op: :field_access,
              arg: %{op: :var, name: "context"},
              field: "screen"
            },
            field: "width"
          },
          span: %{start_line: 1, end_line: 1}
        }
      ]
    }

    assert :ok = AstContract.validate_module(good_module)
  end

  # ---------------------------------------------------------------------------
  # IR structs
  # ---------------------------------------------------------------------------

  test "IR struct can be created with modules list" do
    ir = %IR{modules: []}
    assert ir.modules == []
    assert ir.diagnostics == []
  end

  # ---------------------------------------------------------------------------
  # Lowerer unit tests (no filesystem / elm toolchain needed)
  # ---------------------------------------------------------------------------

  test "lowerer produces IR from a minimal synthetic project" do
    project = %ElmEx.Frontend.Project{
      project_dir: "/tmp/fake",
      elm_json: %{"source-directories" => ["src"]},
      modules: [
        %FrontendModule{
          name: "Main",
          path: "/tmp/fake/src/Main.elm",
          imports: [],
          declarations: [
            %{
              kind: :function_signature,
              name: "f",
              type: "Int -> Int",
              span: %{start_line: 1, end_line: 1}
            },
            %{
              kind: :function_definition,
              name: "f",
              args: ["x"],
              expr: %{op: :add_const, var: "x", value: 1},
              span: %{start_line: 2, end_line: 2}
            }
          ]
        }
      ]
    }

    assert {:ok, %IR{modules: [mod]}} = Lowerer.lower_project(project)
    assert mod.name == "Main"
    assert length(mod.declarations) == 1

    [decl] = mod.declarations
    assert decl.kind == :function
    assert decl.name == "f"
    assert decl.expr.op == :add_const
  end

  # ---------------------------------------------------------------------------
  # Lowerer: compose_left / compose_right rewriting
  # ---------------------------------------------------------------------------

  test "lowerer rewrites compose_left to a lambda" do
    project =
      synthetic_project([
        sig("g", "Int -> Int"),
        defn("g", ["x"], %{op: :compose_left, f: "inc", g: "dec"})
      ])

    {:ok, %IR{modules: [mod]}} = Lowerer.lower_project(project)
    [decl] = Enum.filter(mod.declarations, &(&1.kind == :function))
    assert decl.expr.op == :lambda
  end

  test "lowerer rewrites compose_right to a lambda" do
    project =
      synthetic_project([
        sig("h", "Int -> Int"),
        defn("h", ["x"], %{op: :compose_right, f: "inc", g: "dec"})
      ])

    {:ok, %IR{modules: [mod]}} = Lowerer.lower_project(project)
    [decl] = Enum.filter(mod.declarations, &(&1.kind == :function))
    assert decl.expr.op == :lambda
  end

  # ---------------------------------------------------------------------------
  # Lowerer: constructor tag rewriting
  # ---------------------------------------------------------------------------

  test "lowerer rewrites zero-arg constructor to int literal" do
    project =
      synthetic_project([
        %{
          kind: :union,
          name: "Color",
          constructors: [%{name: "Red", arg: nil}, %{name: "Blue", arg: nil}],
          span: %{start_line: 1, end_line: 1}
        },
        sig("pick", "Color"),
        defn("pick", [], %{op: :constructor_call, target: "Red", args: []})
      ])

    {:ok, %IR{modules: [mod]}} = Lowerer.lower_project(project)
    func = Enum.find(mod.declarations, &(&1.name == "pick" and &1.kind == :function))
    assert func.expr.op == :int_literal
  end

  test "lowerer rewrites qualified zero-arg constructor call to int literal" do
    project =
      synthetic_project([
        %{
          kind: :union,
          name: "Bitmap",
          constructors: [%{name: "BtIcon", arg: nil}],
          span: %{start_line: 1, end_line: 1}
        },
        sig("icon", "Bitmap"),
        defn("icon", [], %{op: :qualified_call, target: "Main.BtIcon", args: []})
      ])

    {:ok, %IR{modules: [mod]}} = Lowerer.lower_project(project)
    func = Enum.find(mod.declarations, &(&1.name == "icon" and &1.kind == :function))
    assert func.expr == %{op: :int_literal, value: 1}
  end

  test "lowerer rewrites single-arg constructor to tagged tuple" do
    project =
      synthetic_project([
        %{
          kind: :union,
          name: "Wrapper",
          constructors: [%{name: "Wrap", arg: "Int"}],
          span: %{start_line: 1, end_line: 1}
        },
        sig("wrap", "Int -> Wrapper"),
        defn("wrap", ["n"], %{
          op: :constructor_call,
          target: "Wrap",
          args: [%{op: :var, name: "n"}]
        })
      ])

    {:ok, %IR{modules: [mod]}} = Lowerer.lower_project(project)
    func = Enum.find(mod.declarations, &(&1.name == "wrap" and &1.kind == :function))
    assert func.expr.op == :tuple2
    assert func.expr.left.op == :int_literal
  end

  test "lowerer rewrites nested list/cons/alias constructor patterns with tags" do
    project =
      synthetic_project([
        %{
          kind: :union,
          name: "Msg",
          constructors: [%{name: "SetCount", arg: "Int"}],
          span: %{start_line: 1, end_line: 1}
        },
        sig("update", "Msg -> Int"),
        defn("update", ["msg"], %{
          op: :case,
          subject: %{op: :var, name: "msg"},
          branches: [
            %{
              pattern: %{
                kind: :alias,
                name: "captured",
                pattern: %{
                  kind: :cons,
                  head: %{kind: :constructor, name: "SetCount", arg_pattern: %{kind: :wildcard}},
                  tail: %{kind: :list, elements: [%{kind: :constructor, name: "SetCount"}]}
                }
              },
              expr: %{op: :int_literal, value: 1}
            }
          ]
        })
      ])

    {:ok, %IR{modules: [mod]}} = Lowerer.lower_project(project)
    func = Enum.find(mod.declarations, &(&1.name == "update" and &1.kind == :function))
    [branch] = func.expr.branches
    pattern = branch.pattern.pattern
    assert pattern.kind == :cons
    assert is_integer(pattern.head.tag)
    assert is_integer(hd(pattern.tail.elements).tag)
  end

  # ---------------------------------------------------------------------------
  # Lowerer: record_literal handling
  # ---------------------------------------------------------------------------

  test "lowerer rewrites {value, temperature} record to tuple2" do
    project =
      synthetic_project([
        sig("mk", "{ value : Int, temperature : Int }"),
        defn("mk", [], %{
          op: :record_literal,
          fields: [
            %{name: "value", expr: %{op: :int_literal, value: 1}},
            %{name: "temperature", expr: %{op: :int_literal, value: 2}}
          ]
        })
      ])

    {:ok, %IR{modules: [mod]}} = Lowerer.lower_project(project)
    func = Enum.find(mod.declarations, &(&1.name == "mk" and &1.kind == :function))
    assert func.expr.op == :tuple2
  end

  test "lowerer preserves generic record_literal for non-value/temperature fields" do
    project =
      synthetic_project([
        sig("mk", "{ x : Int, y : Int }"),
        defn("mk", [], %{
          op: :record_literal,
          fields: [
            %{name: "x", expr: %{op: :int_literal, value: 1}},
            %{name: "y", expr: %{op: :int_literal, value: 2}}
          ]
        })
      ])

    {:ok, %IR{modules: [mod]}} = Lowerer.lower_project(project)
    func = Enum.find(mod.declarations, &(&1.name == "mk" and &1.kind == :function))
    assert func.expr.op == :record_literal
    # Fields should be sorted alphabetically
    [f1, f2] = func.expr.fields
    assert f1.name == "x"
    assert f2.name == "y"
  end

  # ---------------------------------------------------------------------------
  # Topo sort
  # ---------------------------------------------------------------------------

  test "topo sort orders modules by dependencies" do
    ir = %IR{
      modules: [
        %ElmEx.IR.Module{name: "B", imports: ["A"], declarations: []},
        %ElmEx.IR.Module{name: "A", imports: [], declarations: []}
      ]
    }

    assert {:ok, sorted} = TopoSort.sort_modules(ir)
    names = Enum.map(sorted, & &1.name)
    assert names == ["A", "B"]
  end

  test "topo sort detects cycles" do
    ir = %IR{
      modules: [
        %ElmEx.IR.Module{name: "A", imports: ["B"], declarations: []},
        %ElmEx.IR.Module{name: "B", imports: ["A"], declarations: []}
      ]
    }

    assert {:error, {:cycle, _}} = TopoSort.sort_modules(ir)
  end

  test "topo sort handles diamond dependencies" do
    ir = %IR{
      modules: [
        %ElmEx.IR.Module{name: "D", imports: ["B", "C"], declarations: []},
        %ElmEx.IR.Module{name: "C", imports: ["A"], declarations: []},
        %ElmEx.IR.Module{name: "B", imports: ["A"], declarations: []},
        %ElmEx.IR.Module{name: "A", imports: [], declarations: []}
      ]
    }

    assert {:ok, sorted} = TopoSort.sort_modules(ir)
    names = Enum.map(sorted, & &1.name)
    a_idx = Enum.find_index(names, &(&1 == "A"))
    b_idx = Enum.find_index(names, &(&1 == "B"))
    c_idx = Enum.find_index(names, &(&1 == "C"))
    d_idx = Enum.find_index(names, &(&1 == "D"))
    assert a_idx < b_idx
    assert a_idx < c_idx
    assert b_idx < d_idx
    assert c_idx < d_idx
  end

  # ---------------------------------------------------------------------------
  # Validation
  # ---------------------------------------------------------------------------

  test "validation reports no errors on clean IR" do
    ir = %IR{
      modules: [
        %ElmEx.IR.Module{
          name: "Main",
          imports: [],
          declarations: [
            %ElmEx.IR.Declaration{
              kind: :function,
              name: "f",
              args: ["x"],
              expr: %{op: :add_const, var: "x", value: 1},
              ownership: []
            }
          ]
        }
      ]
    }

    diagnostics = Validation.validate(ir)
    errors = Enum.filter(diagnostics, &(&1.severity == :error))
    assert errors == []
  end

  test "validation reports unsupported ops" do
    ir = %IR{
      modules: [
        %ElmEx.IR.Module{
          name: "Main",
          imports: [],
          declarations: [
            %ElmEx.IR.Declaration{
              kind: :function,
              name: "bad",
              args: [],
              expr: %{op: :unsupported, source: "???"},
              ownership: []
            }
          ]
        }
      ]
    }

    diagnostics = Validation.validate(ir)

    unsupported =
      Enum.filter(diagnostics, &(&1.code == :unsupported_op or &1.code == :residual_unsupported))

    assert length(unsupported) > 0
  end

  test "CoreIR strict mode rejects unsupported semantics" do
    ir = %IR{
      modules: [
        %ElmEx.IR.Module{
          name: "Main",
          imports: [],
          declarations: [
            %ElmEx.IR.Declaration{
              kind: :function,
              name: "bad",
              args: [],
              expr: %{op: :unsupported, source: "x"},
              ownership: []
            }
          ]
        }
      ]
    }

    assert {:error, error} = CoreIR.from_ir(ir, strict?: true)
    assert error.type == "core_ir_validation_failed"

    assert Enum.any?(
             error.diagnostics,
             &(&1["code"] in ["unsupported_op", "residual_unsupported"])
           )
  end

  test "CoreIR strict mode accepts supported IR and emits deterministic hash" do
    ir = %IR{
      modules: [
        %ElmEx.IR.Module{
          name: "Main",
          imports: [],
          declarations: [
            %ElmEx.IR.Declaration{
              kind: :function,
              name: "ok",
              args: ["x"],
              expr: %{op: :add_const, var: "x", value: 1},
              ownership: []
            }
          ]
        }
      ]
    }

    assert {:ok, core_ir} = CoreIR.from_ir(ir, strict?: true)
    assert core_ir.version == "elm_ex.core_ir.v1"
    assert is_binary(core_ir.deterministic_sha256)
  end

  test "validation flags function with args but no body" do
    ir = %IR{
      modules: [
        %ElmEx.IR.Module{
          name: "Main",
          imports: [],
          declarations: [
            %ElmEx.IR.Declaration{
              kind: :function,
              name: "ghost",
              args: ["a", "b"],
              expr: nil,
              ownership: []
            }
          ]
        }
      ]
    }

    diagnostics = Validation.validate(ir)
    missing = Enum.filter(diagnostics, &(&1.code == :missing_body))
    assert length(missing) == 1
    assert hd(missing).function == "ghost"
  end

  # ---------------------------------------------------------------------------
  # Diagnostic formatter
  # ---------------------------------------------------------------------------

  test "DiagnosticFormatter formats missing elm.json" do
    error = %{kind: :config_error, reason: :missing_elm_json, path: "/tmp/elm.json"}
    output = DiagnosticFormatter.format_error(error)
    assert is_binary(output)
    assert String.contains?(output, "elm.json")
  end

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  defp synthetic_project(declarations) do
    %ElmEx.Frontend.Project{
      project_dir: "/tmp/synthetic",
      elm_json: %{"source-directories" => ["src"]},
      modules: [
        %FrontendModule{
          name: "Main",
          path: "/tmp/synthetic/src/Main.elm",
          imports: [],
          declarations: declarations
        }
      ]
    }
  end

  defp sig(name, type) do
    %{kind: :function_signature, name: name, type: type, span: %{start_line: 1, end_line: 1}}
  end

  defp defn(name, args, expr) do
    %{
      kind: :function_definition,
      name: name,
      args: args,
      expr: expr,
      span: %{start_line: 2, end_line: 2}
    }
  end
end
