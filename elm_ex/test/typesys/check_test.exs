defmodule ElmEx.Typesys.CheckTest do
  use ExUnit.Case, async: true

  alias ElmEx.Frontend.{Module, Project}
  alias ElmEx.Typesys.Check

  test "rejects type mismatch on annotated identity" do
    project =
      project([
        function("Main", "bad", "Int -> Int", ["x"], %{
          op: :string_literal,
          value: "nope"
        })
      ])

    {_project, diags} = Check.run(project)
    assert Enum.any?(diags, &(&1.code == "type_mismatch"))
  end

  test "Html msg annotations do not require arguments on a local Msg union" do
    project =
      project(
        [
          %{
            kind: :union,
            name: "Msg",
            type_params: [],
            constructors: [%{name: "Noop", arg: nil}]
          },
          function("Main", "view", "() -> Html Msg", [], %{
            op: :call,
            name: "text",
            args: [%{op: :string_literal, value: "ok"}]
          })
        ],
        import_entries: [%{"module" => "Html", "exposing" => ["Html", "text"]}]
      )

    {_project, diags} = Check.run(project)

    refute Enum.any?(diags, &(&1.code == "too_few_args")), inspect(diags)
  end

  test "three-element tuple patterns unify with 3-tuples" do
    project =
      project([
        function("Main", "sum3", "(Int, Int, Int) -> Int", ["triple"], %{
          op: :let_bindings,
          bindings: [
            %{
              kind: :pattern,
              pattern: %{
                kind: :tuple,
                elements: [
                  %{kind: :var, name: "a"},
                  %{kind: :var, name: "b"},
                  %{kind: :var, name: "c"}
                ]
              },
              value: %{op: :var, name: "triple"}
            }
          ],
          in_expr: %{op: :var, name: "a"}
        })
      ])

    {_project, diags} = Check.run(project)

    refute Enum.any?(diags, &(&1.code == "type_mismatch")), inspect(diags)
  end

  test "rejects extra arguments on a saturated constructor" do
    project =
      project([
        function("Main", "go", "Maybe Int", [], %{
          op: :constructor_call,
          target: "Just",
          args: [
            %{op: :int_literal, value: 1},
            %{op: :int_literal, value: 2}
          ]
        })
      ])

    {_project, diags} = Check.run(project)
    assert Enum.any?(diags, &(&1.code == "function_call_arity")), inspect(diags)
  end

  test "rejects type constructors with too few or too many arguments" do
    few =
      project([
        function("Main", "go", "Maybe", [], %{
          op: :constructor_ref,
          target: "Nothing"
        })
      ])

    {_project, few_diags} = Check.run(few)
    assert Enum.any?(few_diags, &(&1.code == "too_few_args")), inspect(few_diags)

    many =
      project([
        function("Main", "go", "Maybe Int String", [], %{
          op: :constructor_ref,
          target: "Nothing"
        })
      ])

    {_project, many_diags} = Check.run(many)
    assert Enum.any?(many_diags, &(&1.code == "too_many_args")), inspect(many_diags)
  end

  test "accepts Int where number/Float is allowed via annotation" do
    project =
      project([
        function("Main", "asFloat", "Float -> Float", ["x"], %{op: :var, name: "x"})
      ])

    {_project, diags} = Check.run(project)
    refute Enum.any?(diags, &(&1.code == "type_mismatch"))
  end

  test "rejects unbound lowercase values" do
    project =
      project([
        function("Main", "go", "Int -> Int", ["x"], %{op: :var, name: "missing"})
      ])

    {_project, diags} = Check.run(project)
    assert Enum.any?(diags, &(&1.code == "unbound_value"))
  end

  test "extensible record annotation returns the same record" do
    project =
      project([
        function(
          "Main",
          "reset",
          "{ model | flag : Bool } -> model",
          ["model"],
          %{
            op: :record_update,
            base: %{op: :var, name: "model"},
            fields: [
              %{name: "flag", expr: %{op: :constructor_ref, target: "False"}}
            ]
          }
        )
      ])

    {_project, diags} = Check.run(project)
    refute Enum.any?(diags, &(&1.code == "type_mismatch")), inspect(diags)
  end

  test "Nothing plus a bare variable binds the Just payload" do
    project =
      project([
        %{
          kind: :type_alias,
          name: "Piece",
          fields: ["kind", "y"],
          field_types: %{"kind" => "Int", "y" => "Int"},
          span: %{start_line: 1, end_line: 1}
        },
        function("Main", "dropY", "Maybe Piece -> Int", ["m"], %{
          op: :case,
          subject: %{op: :var, name: "m"},
          branches: [
            %{
              pattern: %{kind: :constructor, name: "Nothing"},
              expr: %{op: :int_literal, value: 0}
            },
            %{
              pattern: %{kind: :var, name: "piece"},
              expr: %{
                op: :field_access,
                field: "y",
                arg: %{op: :var, name: "piece"}
              }
            }
          ]
        }),
        function("Main", "itemY", "Maybe Piece -> Int", ["m"], %{
          op: :case,
          subject: %{op: :var, name: "m"},
          branches: [
            %{
              pattern: %{kind: :constructor, name: "Nothing"},
              expr: %{op: :int_literal, value: 0}
            },
            %{
              pattern: %{kind: :var, name: "item"},
              expr: %{
                op: :field_access,
                field: "y",
                arg: %{op: :var, name: "item"}
              }
            }
          ]
        })
      ])

    {_project, diags} = Check.run(project)
    refute Enum.any?(diags, &(&1.code in ["type_mismatch", "unbound_value"])), inspect(diags)
  end

  test "rejects incomplete Maybe case" do
    project =
      project([
        function("Main", "peel", "Maybe Int -> Int", ["m"], %{
          op: :case,
          subject: %{op: :var, name: "m"},
          branches: [
            %{
              pattern: %{kind: :constructor, name: "Just", bind: "n"},
              expr: %{op: :var, name: "n"}
            }
          ]
        })
      ])

    {_project, diags} = Check.run(project)
    assert Enum.any?(diags, &(&1.code == "missing_patterns"))
  end

  test "marks exhaustive bool case" do
    project =
      project([
        function("Main", "flip", "Bool -> Bool", ["b"], %{
          op: :case,
          subject: %{op: :var, name: "b"},
          branches: [
            %{pattern: %{kind: :constructor, name: "True"}, expr: %{op: :var, name: "b"}},
            %{pattern: %{kind: :constructor, name: "False"}, expr: %{op: :var, name: "b"}}
          ]
        })
      ])

    {project, diags} = Check.run(project)
    refute Enum.any?(diags, &(&1.code == "missing_patterns"))

    expr =
      project.modules
      |> hd()
      |> Map.get(:declarations)
      |> Enum.find(&(&1.kind == :function_definition and &1.name == "flip"))
      |> Map.get(:expr)

    assert expr.elm_exhaustive? == true
    assert expr.elm_type != nil
  end

  test "rejects a value defined in terms of itself" do
    project =
      project([
        function("Main", "x", "Int", [], %{
          op: :call,
          name: "+",
          args: [%{op: :var, name: "x"}, %{op: :int_literal, value: 1}]
        })
      ])

    {_project, diags} = Check.run(project)
    assert Enum.any?(diags, &(&1.code == "value_cycle"))
  end

  test "accepts a recursive function value" do
    project =
      project([
        function("Main", "x", "Int -> Int", [], %{
          op: :lambda,
          args: ["n"],
          body: %{
            op: :call,
            name: "+",
            args: [%{op: :var, name: "x"}, %{op: :var, name: "n"}]
          }
        })
      ])

    {_project, diags} = Check.run(project)
    refute Enum.any?(diags, &(&1.code == "value_cycle"))
  end

  test "accepts a recursive helper bound in a let" do
    project =
      project([
        function("Main", "go", "Int -> Int", ["n"], %{
          op: :let_bindings,
          bindings: [
            %{
              kind: :name,
              name: "helper",
              value: %{
                op: :lambda,
                args: ["acc", "x"],
                body: %{
                  op: :if,
                  cond: %{
                    op: :compare,
                    kind: :lte,
                    left: %{op: :var, name: "x"},
                    right: %{op: :int_literal, value: 0}
                  },
                  then_expr: %{op: :var, name: "acc"},
                  else_expr: %{
                    op: :call,
                    name: "helper",
                    args: [
                      %{
                        op: :call,
                        name: "+",
                        args: [%{op: :var, name: "acc"}, %{op: :var, name: "x"}]
                      },
                      %{
                        op: :call,
                        name: "-",
                        args: [%{op: :var, name: "x"}, %{op: :int_literal, value: 1}]
                      }
                    ]
                  }
                }
              }
            }
          ],
          in_expr: %{
            op: :call,
            name: "helper",
            args: [%{op: :int_literal, value: 0}, %{op: :var, name: "n"}]
          }
        })
      ])

    {_project, diags} = Check.run(project)

    refute Enum.any?(diags, &(&1.code in ["type_mismatch", "unbound_value", "value_cycle"])),
           inspect(diags)
  end

  test "accepts a record as-pattern argument and nested record update" do
    project =
      project([
        %{
          kind: :type_alias,
          name: "Address",
          fields: ["city", "zip"],
          field_types: %{"city" => "String", "zip" => "String"},
          span: %{start_line: 1, end_line: 1}
        },
        %{
          kind: :type_alias,
          name: "User",
          fields: ["name", "address"],
          field_types: %{"name" => "String", "address" => "Address"},
          span: %{start_line: 2, end_line: 2}
        },
        function("Main", "moveTo", "String -> User -> User", ["newCity", "({ address } as user)"], %{
          op: :record_update,
          base: %{op: :var, name: "user"},
          fields: [
            %{
              name: "address",
              expr: %{
                op: :record_update,
                base: %{op: :var, name: "address"},
                fields: [
                  %{name: "city", expr: %{op: :var, name: "newCity"}}
                ]
              }
            }
          ]
        })
      ])

    {_project, diags} = Check.run(project)

    refute Enum.any?(diags, &(&1.code in ["type_mismatch", "unbound_value"])), inspect(diags)
  end

  test "accepts Json.Decode.array of ints" do
    project =
      project([
        function("Main", "readInts", "Json.Decode.Decoder (Array Int)", [], %{
          op: :qualified_call,
          target: "Json.Decode.array",
          args: [%{op: :qualified_call, target: "Json.Decode.int", args: []}]
        })
      ])

    {_project, diags} = Check.run(project)

    refute Enum.any?(diags, &(&1.code in ["type_mismatch", "unbound_value", "too_few_args"])),
           inspect(diags)
  end

  test "rejects exposing (..) on a type alias" do
    project = %Project{
      project_dir: "/tmp/typesys-check",
      elm_json: %{"source-directories" => ["src"], "type" => "application"},
      modules: [
        %Module{
          name: "Main",
          path: "/tmp/typesys-check/src/Main.elm",
          imports: [],
          import_entries: [],
          declarations: [
            %{
              kind: :type_alias,
              name: "Point",
              fields: ["x"],
              field_types: %{"x" => "Int"},
              span: %{start_line: 1, end_line: 1}
            }
          ],
          module_exposing: ["Point(..)"]
        }
      ],
      diagnostics: []
    }

    {_project, diags} = Check.run(project)
    assert Enum.any?(diags, &(&1.code == "bad_exposing"))
  end

  test "rejects comparing a number with Bool" do
    project =
      project([
        function("Main", "bad", "Bool", [], %{
          op: :compare,
          kind: :lt,
          left: %{op: :int_literal, value: 1},
          right: %{op: :bool_literal, value: true}
        })
      ])

    {_project, diags} = Check.run(project)
    assert Enum.any?(diags, &(&1.code == "type_mismatch"))
  end

  test "accepts equality on Bool" do
    project =
      project([
        function("Main", "same", "Bool -> Bool -> Bool", ["a", "b"], %{
          op: :compare,
          kind: :eq,
          left: %{op: :var, name: "a"},
          right: %{op: :var, name: "b"}
        })
      ])

    {_project, diags} = Check.run(project)
    refute Enum.any?(diags, &(&1.code == "type_mismatch"))
  end

  test "rejects ordering closed records" do
    project =
      project([
        function("Main", "bad", "Bool", [], %{
          op: :compare,
          kind: :lt,
          left: %{
            op: :record_literal,
            fields: [%{name: "x", expr: %{op: :int_literal, value: 1}}]
          },
          right: %{
            op: :record_literal,
            fields: [%{name: "x", expr: %{op: :int_literal, value: 2}}]
          }
        })
      ])

    {_project, diags} = Check.run(project)
    assert Enum.any?(diags, &(&1.code == "type_mismatch"))
  end

  test "accepts Time.toHour on Time.Posix" do
    project =
      project([
        function("Main", "hour", "Time.Posix -> Int", ["t"], %{
          op: :qualified_call,
          target: "Time.toHour",
          args: [
            %{op: :var, name: "Time.utc"},
            %{op: :var, name: "t"}
          ]
        })
      ])

    {_project, diags} = Check.run(project)
    refute Enum.any?(diags, &(&1.code in ["type_mismatch", "unbound_value"]))
  end

  test "accepts Json.Decode.int as Decoder Int" do
    project =
      project([
        function("Main", "readInt", "Json.Decode.Decoder Int", [], %{
          op: :qualified_call,
          target: "Json.Decode.int",
          args: []
        })
      ])

    {_project, diags} = Check.run(project)
    refute Enum.any?(diags, &(&1.code in ["type_mismatch", "unbound_value"]))
  end

  test "rejects appending String to List" do
    project =
      project([
        function("Main", "bad", "String", [], %{
          op: :call,
          name: "++",
          args: [
            %{op: :string_literal, value: "x"},
            %{op: :list_literal, items: [%{op: :int_literal, value: 1}]}
          ]
        })
      ])

    {_project, diags} = Check.run(project)
    assert Enum.any?(diags, &(&1.code == "type_mismatch"))
  end

  test "rejects a closed record missing a field" do
    project =
      project([
        %{
          kind: :type_alias,
          name: "Point",
          fields: ["x", "y"],
          field_types: %{"x" => "Int", "y" => "Int"},
          span: %{start_line: 1, end_line: 1}
        },
        function("Main", "origin", "Point", [], %{
          op: :record_literal,
          fields: [%{name: "x", expr: %{op: :int_literal, value: 0}}]
        })
      ])

    {_project, diags} = Check.run(project)
    assert Enum.any?(diags, &(&1.code == "type_mismatch"))
  end

  test "rejects extra record field against a closed alias" do
    project =
      project([
        %{
          kind: :type_alias,
          name: "Point",
          fields: ["x", "y"],
          field_types: %{"x" => "Int", "y" => "Int"},
          span: %{start_line: 1, end_line: 1}
        },
        %{
          kind: :function_signature,
          name: "origin",
          type: "Point",
          span: %{start_line: 2, end_line: 2}
        },
        %{
          kind: :function_definition,
          name: "origin",
          args: [],
          type: "Point",
          span: %{start_line: 3, end_line: 3},
          expr: %{
            op: :record_literal,
            fields: [
              %{name: "x", expr: %{op: :int_literal, value: 0}},
              %{name: "y", expr: %{op: :int_literal, value: 0}},
              %{name: "z", expr: %{op: :int_literal, value: 0}}
            ]
          }
        }
      ])

    {_project, diags} = Check.run(project)
    assert Enum.any?(diags, &(&1.code == "type_mismatch"))
  end

  test "rejects duplicate names in one tuple pattern" do
    project =
      project([
        function("Main", "dup", "(Int, Int) -> Int", ["t"], %{
          op: :case,
          subject: %{op: :var, name: "t"},
          branches: [
            %{
              pattern: %{
                kind: :tuple,
                elements: [
                  %{kind: :var, name: "x"},
                  %{kind: :var, name: "x"}
                ]
              },
              expr: %{op: :var, name: "x"}
            }
          ]
        })
      ])

    {_project, diags} = Check.run(project)
    assert Enum.any?(diags, &(&1.code == "duplicate_pattern"))
  end

  test "rejects qualified unknown values" do
    project =
      project([
        function("Main", "go", "Int", [], %{
          op: :qualified_call,
          target: "Nope.missing",
          args: []
        })
      ])

    {_project, diags} = Check.run(project)
    assert Enum.any?(diags, &(&1.code == "unbound_value"))
  end

  test "rejects rigid annotation instantiated by number" do
    project =
      project([
        function("Main", "id", "a -> a", ["x"], %{
          op: :call,
          name: "+",
          args: [%{op: :var, name: "x"}, %{op: :int_literal, value: 1}]
        })
      ])

    {_project, diags} = Check.run(project)
    assert Enum.any?(diags, &(&1.code == "type_mismatch"))
  end

  test "accepts mutually recursive functions" do
    project =
      project([
        function("Main", "even", "Int -> Bool", ["n"], %{
          op: :if,
          cond: %{
            op: :compare,
            left: %{op: :var, name: "n"},
            right: %{op: :int_literal, value: 0}
          },
          then_expr: %{op: :bool_literal, value: true},
          else_expr: %{
            op: :call,
            name: "odd",
            args: [
              %{
                op: :call,
                name: "-",
                args: [%{op: :var, name: "n"}, %{op: :int_literal, value: 1}]
              }
            ]
          }
        }),
        function("Main", "odd", "Int -> Bool", ["n"], %{
          op: :if,
          cond: %{
            op: :compare,
            left: %{op: :var, name: "n"},
            right: %{op: :int_literal, value: 0}
          },
          then_expr: %{op: :bool_literal, value: false},
          else_expr: %{
            op: :call,
            name: "even",
            args: [
              %{
                op: :call,
                name: "-",
                args: [%{op: :var, name: "n"}, %{op: :int_literal, value: 1}]
              }
            ]
          }
        })
      ])

    {_project, diags} = Check.run(project)
    refute Enum.any?(diags, &(&1.code in ["type_mismatch", "unbound_value"]))
  end

  test "accepts a unit type alias" do
    project =
      project([
        %{
          kind: :type_alias,
          name: "Model",
          fields: [],
          field_types: %{},
          alias_type: "()",
          source: "type alias Model =\n    ()",
          span: %{start_line: 1, end_line: 2}
        },
        function("Main", "init", "Model", [], "()")
      ])

    {_project, diags} = Check.run(project)
    refute Enum.any?(diags, &(&1.code in ["recursive_alias", "type_mismatch"])), inspect(diags)
  end

  test "accepts an empty record type alias" do
    project =
      project([
        %{
          kind: :type_alias,
          name: "Model",
          fields: [],
          field_types: %{},
          alias_type: nil,
          source: "type alias Model =\n    {}",
          span: %{start_line: 1, end_line: 2}
        },
        function("Main", "init", "Model", [], %{op: :record_literal, fields: []})
      ])

    {_project, diags} = Check.run(project)
    refute Enum.any?(diags, &(&1.code in ["recursive_alias", "type_mismatch"]))
  end

  test "tuple pattern function arguments bind their names" do
    project =
      project([
        function("Main", "sumPair", "(Int, Int) -> Int", ["( x, y )"], %{
          op: :call,
          name: "+",
          args: [%{op: :var, name: "x"}, %{op: :var, name: "y"}]
        })
      ])

    {_project, diags} = Check.run(project)
    refute Enum.any?(diags, &(&1.code == "unbound_value")), inspect(diags)
  end

  test "record type alias is also a constructor" do
    project =
      project([
        %{
          kind: :type_alias,
          name: "Person",
          fields: ["name", "age"],
          field_types: %{"name" => "String", "age" => "Int"},
          span: %{start_line: 1, end_line: 1}
        },
        function("Main", "mk", "String -> Int -> Person", [], %{
          op: :var,
          name: "Person"
        })
      ])

    {_project, diags} = Check.run(project)
    refute Enum.any?(diags, &(&1.code in ["unbound_value", "type_mismatch"])), inspect(diags)
  end

  test "record alias constructor from alias_type body and exposed Decoder" do
    project =
      project(
        [
          %{
            kind: :type_alias,
            name: "Person",
            fields: ["name", "age"],
            field_types: %{"name" => "String", "age" => "Int"},
            alias_type: "{ name : String, age : Int }",
            span: %{start_line: 1, end_line: 1}
          },
          function("Main", "personDecoder", "Decoder Person", [], %{
            op: :qualified_call,
            target: "Decode.map2",
            args: [
              %{op: :var, name: "Person"},
              %{
                op: :qualified_call,
                target: "Decode.field",
                args: [
                  %{op: :string_literal, value: "name"},
                  %{op: :qualified_ref, target: "Decode.string"}
                ]
              },
              %{
                op: :qualified_call,
                target: "Decode.field",
                args: [
                  %{op: :string_literal, value: "age"},
                  %{op: :qualified_ref, target: "Decode.int"}
                ]
              }
            ]
          })
        ],
        import_entries: [
          %{"module" => "Json.Decode", "as" => "Decode", "exposing" => ["Decoder"]}
        ]
      )

    {_project, diags} = Check.run(project)

    refute Enum.any?(
             diags,
             &(&1.code in ["type_mismatch", "unbound_value", "too_few_args", "too_many_args"])
           ),
           inspect(diags)
  end

  test "accepts parameterized type alias application" do
    project =
      project([
        %{
          kind: :type_alias,
          name: "Pair",
          source: "type alias Pair a b = (a, b)",
          alias_type: "(a, b)",
          type_params: ["a", "b"],
          span: %{start_line: 1, end_line: 1}
        },
        function("Main", "origin", "Pair Int String", [], %{
          op: :tuple2,
          left: %{op: :int_literal, value: 1},
          right: %{op: :string_literal, value: "x"}
        })
      ])

    {_project, diags} = Check.run(project)
    refute Enum.any?(diags, &(&1.code == "type_mismatch"))
  end

  test "rejects Maybe payload on a port" do
    project = %Project{
      project_dir: "/tmp/typesys-check",
      elm_json: %{"source-directories" => ["src"], "type" => "application"},
      modules: [
        %Module{
          name: "Main",
          path: "/tmp/typesys-check/src/Main.elm",
          imports: [],
          import_entries: [],
          port_module: true,
          ports: ["out"],
          declarations: [
            %{kind: :function_signature, name: "out", type: "Maybe Int -> Cmd msg"}
          ],
          module_exposing: ".."
        }
      ],
      diagnostics: []
    }

    {_project, diags} = Check.run(project)
    assert Enum.any?(diags, &(&1.code == "port_problem"))
  end

  test "rejects cons-in-cons as incomplete" do
    project =
      project([
        function("Main", "peel", "List Int -> Int", ["xs"], %{
          op: :case,
          subject: %{op: :var, name: "xs"},
          branches: [
            %{
              pattern: %{
                kind: :cons,
                head: %{kind: :var, name: "a"},
                tail: %{
                  kind: :cons,
                  head: %{kind: :var, name: "b"},
                  tail: %{kind: :var, name: "rest"}
                }
              },
              expr: %{
                op: :call,
                name: "+",
                args: [%{op: :var, name: "a"}, %{op: :var, name: "b"}]
              }
            }
          ]
        })
      ])

    {_project, diags} = Check.run(project)
    assert Enum.any?(diags, &(&1.code == "missing_patterns"))
  end

  test "rejects nested incomplete Maybe case" do
    project =
      project([
        function("Main", "peel", "Maybe (Maybe Int) -> Int", ["m"], %{
          op: :case,
          subject: %{op: :var, name: "m"},
          branches: [
            %{
              pattern: %{
                kind: :constructor,
                name: "Just",
                arg_pattern: %{kind: :constructor, name: "Just", bind: "n"}
              },
              expr: %{op: :var, name: "n"}
            }
          ]
        })
      ])

    {_project, diags} = Check.run(project)
    assert Enum.any?(diags, &(&1.code == "missing_patterns"))
  end

  test "rejects redundant constructor after wildcard payload" do
    project =
      project([
        function("Main", "peel", "Maybe Int -> Int", ["m"], %{
          op: :case,
          subject: %{op: :var, name: "m"},
          branches: [
            %{
              pattern: %{kind: :constructor, name: "Just", bind: "_"},
              expr: %{op: :int_literal, value: 1}
            },
            %{
              pattern: %{kind: :constructor, name: "Just", bind: "n"},
              expr: %{op: :var, name: "n"}
            },
            %{
              pattern: %{kind: :constructor, name: "Nothing"},
              expr: %{op: :int_literal, value: 0}
            }
          ]
        })
      ])

    {_project, diags} = Check.run(project)
    assert Enum.any?(diags, &(&1.code == "unreachable_pattern"))
  end

  test "accepts a three-argument constructor pattern" do
    project =
      project([
        %{
          kind: :union,
          name: "Event",
          constructors: [
            %{name: "ProvideNextEvent", arg: "String Int Int"},
            %{name: "NoUpcomingEvents"}
          ],
          span: %{start_line: 1, end_line: 1}
        },
        function("Main", "titleOf", "Event -> String", ["event"], %{
          op: :case,
          subject: %{op: :var, name: "event"},
          branches: [
            %{
              pattern: %{
                kind: :constructor,
                name: "ProvideNextEvent",
                arg_pattern: %{
                  kind: :tuple,
                  elements: [
                    %{kind: :var, name: "title"},
                    %{
                      kind: :tuple,
                      elements: [
                        %{kind: :var, name: "hour"},
                        %{kind: :var, name: "minute"}
                      ]
                    }
                  ]
                }
              },
              expr: %{op: :var, name: "title"}
            },
            %{
              pattern: %{kind: :constructor, name: "NoUpcomingEvents"},
              expr: %{op: :string_literal, value: ""}
            }
          ]
        })
      ])

    {_project, diags} = Check.run(project)
    refute Enum.any?(diags, &(&1.code in ["type_mismatch", "unbound_value"])), inspect(diags)
  end

  test "local pad is not shadowed by a loaded String.pad" do
    string_mod = %Module{
      name: "String",
      path: "/tmp/typesys-check/elm-home/elm/core/src/String.elm",
      imports: [],
      import_entries: [],
      declarations: [
        %{kind: :function_signature, name: "pad", type: "Int -> Char -> String -> String"}
      ],
      module_exposing: ".."
    }

    main =
      %Module{
        name: "Main",
        path: "/tmp/typesys-check/src/Main.elm",
        imports: [],
        import_entries: [],
        declarations:
          List.flatten([
            function("Main", "pad", "Int -> String", ["value"], %{
              op: :call,
              name: "String.fromInt",
              args: [%{op: :var, name: "value"}]
            }),
            function("Main", "clock", "Int -> String", ["n"], %{
              op: :call,
              name: "++",
              args: [
                %{op: :call, name: "pad", args: [%{op: :var, name: "n"}]},
                %{op: :string_literal, value: ":00"}
              ]
            })
          ]),
        module_exposing: ".."
      }

    project = %Project{
      project_dir: "/tmp/typesys-check",
      elm_json: %{"source-directories" => ["src"], "type" => "application"},
      modules: [string_mod, main],
      diagnostics: []
    }

    {_project, diags} = Check.run(project)
    refute Enum.any?(diags, &(&1.code == "type_mismatch")), inspect(diags)
  end

  test "import exposing Type(..) brings constructors and the type name" do
    project =
      project(
        [
          function("Main", "label", "Button -> String", ["button"], %{
            op: :case,
            subject: %{op: :var, name: "button"},
            branches: [
              %{pattern: %{kind: :constructor, name: "Back"}, expr: %{op: :string_literal, value: "back"}},
              %{pattern: %{kind: :constructor, name: "Up"}, expr: %{op: :string_literal, value: "up"}},
              %{
                pattern: %{kind: :constructor, name: "Select"},
                expr: %{op: :string_literal, value: "select"}
              },
              %{pattern: %{kind: :constructor, name: "Down"}, expr: %{op: :string_literal, value: "down"}}
            ]
          })
        ],
        import_entries: [
          %{"module" => "Pebble.Button", "as" => "Button", "exposing" => ["Button(..)"]}
        ]
      )

    {_project, diags} = Check.run(project)
    refute Enum.any?(diags, &(&1.code in ["type_mismatch", "unbound_value", "unreachable_pattern"])),
           inspect(diags)
  end

  test "unannotated dependency exports are visible to the application" do
    other = %Module{
      name: "Other",
      path: "/tmp/typesys-check/deps/Other.elm",
      imports: [],
      import_entries: [],
      declarations: [
        %{
          kind: :function_definition,
          name: "answer",
          args: [],
          span: %{start_line: 1, end_line: 1},
          expr: %{op: :int_literal, value: 1}
        }
      ],
      module_exposing: ".."
    }

    main = %Module{
      name: "Main",
      path: "/tmp/typesys-check/src/Main.elm",
      imports: ["Other"],
      import_entries: [%{"module" => "Other"}],
      declarations:
        function("Main", "go", "Int", [], %{
          op: :qualified_ref,
          target: "Other.answer"
        }),
      module_exposing: ".."
    }

    project = %Project{
      project_dir: "/tmp/typesys-check",
      elm_json: %{"source-directories" => ["src"], "type" => "application"},
      modules: [other, main],
      diagnostics: []
    }

    {_project, diags} = Check.run(project)
    refute Enum.any?(diags, &(&1.code == "unbound_value")), inspect(diags)
  end

  test "rejects too many constructor args" do
    project =
      project([
        function("Main", "go", "Maybe Int", [], %{
          op: :constructor_call,
          target: "Just",
          args: [
            %{op: :int_literal, value: 1},
            %{op: :int_literal, value: 2}
          ]
        })
      ])

    {_project, diags} = Check.run(project)
    assert Enum.any?(diags, &(&1.code in ["type_mismatch", "function_call_arity"]))
  end

  test "local Cmd union shadows Platform.Cmd arity" do
    project =
      project([
        %{
          kind: :union,
          name: "Cmd",
          type_params: [],
          constructors: [%{name: "PrintPath", arg: "String"}]
        },
        function("Main", "makeCmd", "String -> Cmd", ["path"], %{
          op: :constructor_call,
          target: "PrintPath",
          args: [%{op: :var, name: "path"}]
        })
      ])

    {_project, diags} = Check.run(project)
    refute Enum.any?(diags, &(&1.code == "too_few_args")), inspect(diags)
  end

  test "local Program alias shadows Platform.Program arity" do
    project =
      project([
        %{
          kind: :type_alias,
          name: "Program",
          type_params: [],
          alias_type: "{ stmts : List String }",
          field_types: %{"stmts" => "List String"}
        },
        function("Main", "doWork", "String -> Program -> Program", ["prefix", "p"], %{
          op: :var,
          name: "p"
        })
      ])

    {_project, diags} = Check.run(project)
    refute Enum.any?(diags, &(&1.code == "too_few_args")), inspect(diags)
  end

  test "pipe operators exist as first-class values" do
    project =
      project([
        function("Main", "main", "Int", [], %{
          op: :call,
          name: "<|",
          args: [
            %{op: :lambda, args: ["n"], body: %{op: :var, name: "n"}},
            %{op: :int_literal, value: 1}
          ]
        })
      ])

    {_project, diags} = Check.run(project)
    refute Enum.any?(diags, &(&1.code == "unbound_value")), inspect(diags)
  end

  test "cons of a tuple pattern stays a list" do
    project =
      project([
        function("Main", "lookup", "String -> List ( String, Int ) -> Maybe Int", ["name", "pairs"], %{
          op: :case,
          subject: %{op: :var, name: "pairs"},
          branches: [
            %{
              pattern: %{kind: :constructor, name: "[]"},
              expr: %{op: :constructor_ref, target: "Nothing"}
            },
            %{
              pattern: %{
                kind: :constructor,
                name: "::",
                arg_pattern: %{
                  kind: :tuple,
                  elements: [
                    %{
                      kind: :tuple,
                      elements: [
                        %{kind: :var, name: "key"},
                        %{kind: :var, name: "value"}
                      ]
                    },
                    %{kind: :var, name: "rest"}
                  ]
                }
              },
              expr: %{
                op: :if,
                cond: %{
                  op: :call,
                  name: "==",
                  args: [%{op: :var, name: "key"}, %{op: :var, name: "name"}]
                },
                then_expr: %{
                  op: :constructor_call,
                  target: "Just",
                  args: [%{op: :var, name: "value"}]
                },
                else_expr: %{
                  op: :call,
                  name: "lookup",
                  args: [%{op: :var, name: "name"}, %{op: :var, name: "rest"}]
                }
              }
            }
          ]
        })
      ])

    {_project, diags} = Check.run(project)
    refute Enum.any?(diags, &(&1.code == "type_mismatch")), inspect(diags)
  end

  test "function type aliases can be applied" do
    project =
      project([
        %{
          kind: :type_alias,
          name: "IO",
          type_params: ["s", "a"],
          alias_type: "s -> ( a, s )"
        },
        function("Main", "pureIO", "a -> IO s a", ["value"], %{
          op: :lambda,
          args: ["state"],
          body: %{
            op: :tuple,
            elements: [%{op: :var, name: "value"}, %{op: :var, name: "state"}]
          }
        })
      ])

    {_project, diags} = Check.run(project)
    refute Enum.any?(diags, &(&1.code == "function_call_arity")), inspect(diags)
  end

  defp project(decls, opts \\ []) do
    %Project{
      project_dir: "/tmp/typesys-check",
      elm_json: %{"source-directories" => ["src"], "type" => "application"},
      modules: [
        %Module{
          name: "Main",
          path: "/tmp/typesys-check/src/Main.elm",
          imports: [],
          import_entries: Keyword.get(opts, :import_entries, []),
          declarations: List.flatten(decls),
          module_exposing: ".."
        }
      ],
      diagnostics: []
    }
  end

  defp function(_mod, name, type, args, expr) do
    [
      %{kind: :function_signature, name: name, type: type, span: %{start_line: 1, end_line: 1}},
      %{
        kind: :function_definition,
        name: name,
        args: args,
        type: type,
        span: %{start_line: 2, end_line: 2},
        expr: expr
      }
    ]
  end
end
