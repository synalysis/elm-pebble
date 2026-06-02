defmodule Elmx.CasePatternEmitTest do
  use ExUnit.Case, async: true

  alias Elmx.Backend.ConstructorLookup
  alias Elmx.Backend.ElixirCodegen.Emit
  alias ElmEx.IR

  test "case on :: binds head and tail as variables" do
    expr = %{
      op: :case,
      subject: "xs",
      branches: [
        %{
          pattern: %{
            kind: :constructor,
            name: "::",
            bind: nil,
            arg_pattern: %{
              kind: :tuple,
              elements: [
                %{kind: :var, name: "head"},
                %{kind: :var, name: "tail"}
              ]
            }
          },
          expr: %{op: :var, name: "tail"}
        }
      ]
    }

    env =
      Emit.function_env("Main", [])
      |> Map.put(:module, "Main")
      |> Map.put(:zero_arity_fns, MapSet.new())
      |> Map.put(:function_arities, %{})

    {code, _, _} = Emit.compile_expr(expr, env, 0)
    source = IO.iodata_to_binary(code)

    assert source =~ "[head | tail]"
    refute source =~ "elmx_fn_Main_tail"
  end

  test "case orders constructor wildcard branches after specific payloads" do
    expr = %{
      op: :case,
      subject: "msg",
      branches: [
        %{
          pattern: %{
            kind: :constructor,
            name: "GotStorage",
            arg_pattern: %{kind: :wildcard}
          },
          expr: %{op: :int_literal, value: 0}
        },
        %{
          pattern: %{
            kind: :constructor,
            name: "GotStorage",
            arg_pattern: %{
              kind: :constructor,
              name: "Ok",
              arg_pattern: %{
                kind: :constructor,
                name: "StringValue",
                arg_pattern: %{kind: :var, name: "themeText"}
              }
            }
          },
          expr: %{op: :int_literal, value: 1}
        }
      ]
    }

    env =
      Emit.function_env("Main", [])
      |> Map.put(:module, "Main")
      |> Map.put(:zero_arity_fns, MapSet.new())
      |> Map.put(:function_arities, %{})

    {code, _, _} = Emit.compile_expr(expr, env, 0)
    source = IO.iodata_to_binary(code)

    specific = String.split(source, "{:GotStorage, {:Ok, {:StringValue, themeText}}}") |> length()
    catch_all = String.split(source, "{:GotStorage, _}") |> length()
    assert specific == 2
    assert catch_all == 2
    assert String.split(source, "->") |> hd() =~ "StringValue"
  end

  test "case on tuple of Just binds pattern variables" do
    expr = %{
      op: :case,
      subject: "pair",
      branches: [
        %{
          pattern: %{
            kind: :tuple,
            elements: [
              %{kind: :constructor, name: "Just", bind: "temperature", arg_pattern: nil},
              %{kind: :constructor, name: "Just", bind: "condition", arg_pattern: nil}
            ]
          },
          expr: %{op: :var, name: "temperature"}
        }
      ]
    }

    env =
      Emit.function_env("Main", [])
      |> Map.put(:module, "Main")
      |> Map.put(:zero_arity_fns, MapSet.new())
      |> Map.put(:function_arities, %{})

    {code, _, _} = Emit.compile_expr(expr, env, 0)
    source = IO.iodata_to_binary(code)

    assert source =~ "{:Just, temperature}, {:Just, condition}"
    refute source =~ "elmx_fn_Main_temperature"
  end

  test "let-bound function calls use variable apply syntax" do
    expr = %{
      op: :let_in,
      name: "label",
      value_expr: %{
        op: :lambda,
        args: ["x", "y", "text_"],
        body: %{op: :var, name: "text_"}
      },
      in_expr: %{op: :call, name: "label", args: [%{op: :int_literal, value: 8}, %{op: :int_literal, value: 9}, %{op: :string_literal, value: "hi"}]}
    }

    env =
      Emit.function_env("Main", ["model"])
      |> Map.put(:module, "Main")
      |> Map.put(:zero_arity_fns, MapSet.new())
      |> Map.put(:function_arities, %{})

    {code, _, _} = Emit.compile_expr(expr, env, 0)
    source = IO.iodata_to_binary(code)

    assert source =~ "label.(8).(9).(\"hi\")"
    refute source =~ "label.(8, 9, \"hi\")"
    refute source =~ "elmx_fn_Main_label"
  end

  test "nested constructor patterns bind tuple fields" do
    expr = %{
      op: :case,
      subject: "msg",
      branches: [
        %{
          pattern: %{
            kind: :constructor,
            name: "FromPhone",
            bind: nil,
            arg_pattern: %{
              kind: :constructor,
              name: "ProvideBattery",
              bind: nil,
              arg_pattern: %{
                kind: :tuple,
                elements: [
                  %{kind: :var, name: "percent"},
                  %{kind: :var, name: "charging"}
                ]
              }
            }
          },
          expr: %{op: :var, name: "percent"}
        }
      ]
    }

    env =
      Emit.function_env("Main", ["msg"])
      |> Map.put(:module, "Main")
      |> Map.put(:zero_arity_fns, MapSet.new())
      |> Map.put(:function_arities, %{})

    {code, _, _} = Emit.compile_expr(expr, env, 0)
    source = IO.iodata_to_binary(code)

    assert source =~ "{:FromPhone, {:ProvideBattery, percent, charging}}"
    refute source =~ "elmx_fn_Main_percent"
  end

  test "ide_runtime flattens nested pair constructor payload patterns" do
    expr = %{
      op: :case,
      subject: "msg",
      branches: [
        %{
          pattern: %{
            kind: :constructor,
            name: "FromPhone",
            bind: nil,
            arg_pattern: %{
              kind: :constructor,
              name: "ProvidePosition",
              bind: nil,
              arg_pattern: %{
                kind: :tuple,
                elements: [
                  %{kind: :var, name: "latitudeE6"},
                  %{
                    kind: :tuple,
                    elements: [
                      %{kind: :var, name: "longitudeE6"},
                      %{kind: :var, name: "accuracyM"}
                    ]
                  }
                ]
              }
            }
          },
          expr: %{op: :var, name: "latitudeE6"}
        }
      ]
    }

    env =
      Emit.function_env("Main", ["msg"])
      |> Map.put(:module, "Main")
      |> Map.put(:emit_mode, :ide_runtime)
      |> Map.put(:zero_arity_fns, MapSet.new())
      |> Map.put(:function_arities, %{})

    {code, _, _} = Emit.compile_expr(expr, env, 0)
    source = IO.iodata_to_binary(code)

    assert source =~ "{:FromPhone, {:ProvidePosition, latitudeE6, longitudeE6, accuracyM}}"
    refute source =~ "{longitudeE6, accuracyM}"
  end

  test "nested :: list patterns bind each head" do
    expr = %{
      op: :case,
      subject: "xs",
      branches: [
        %{
          pattern: %{
            kind: :constructor,
            name: "::",
            bind: nil,
            arg_pattern: %{
              kind: :tuple,
              elements: [
                %{kind: :var, name: "first"},
                %{
                  kind: :constructor,
                  name: "::",
                  bind: nil,
                  arg_pattern: %{
                    kind: :tuple,
                    elements: [
                      %{kind: :var, name: "second"},
                      %{kind: :constructor, name: "[]", bind: nil, arg_pattern: nil}
                    ]
                  }
                }
              ]
            }
          },
          expr: %{op: :var, name: "second"}
        }
      ]
    }

    env =
      Emit.function_env("Render", ["xs"])
      |> Map.put(:module, "Render")
      |> Map.put(:zero_arity_fns, MapSet.new())
      |> Map.put(:function_arities, %{})

    {code, _, _} = Emit.compile_expr(expr, env, 0)
    source = IO.iodata_to_binary(code)

    assert source =~ "[first | [second | []]]"
    assert source =~ "second"
  end

  test "ide_runtime keeps plain pair constructor payloads nested in case patterns" do
    expr = %{
      op: :case,
      subject: "msg",
      branches: [
        %{
          pattern: %{
            kind: :constructor,
            name: "GotPreference",
            arg_pattern: %{
              kind: :constructor,
              name: "Ok",
              arg_pattern: %{
                kind: :tuple,
                elements: [
                  %{kind: :string, value: "units"},
                  %{kind: :var, name: "value"}
                ]
              }
            }
          },
          expr: %{op: :var, name: "value"}
        }
      ]
    }

    env =
      Emit.function_env("Main", ["msg"])
      |> Map.put(:module, "Main")
      |> Map.put(:emit_mode, :ide_runtime)

    {code, _, _} = Emit.compile_expr(expr, env, 0)
    source = IO.iodata_to_binary(code)

    assert source =~ "{:GotPreference, {:Ok, {\"units\", value}}}"
    refute source =~ "{:GotPreference, {:Ok, \"units\", value}}"
  end

  test "ide_runtime unit () in Result Ok case patterns emits nil" do
    expr = %{
      op: :case,
      subject: "msg",
      branches: [
        %{
          pattern: %{
            kind: :constructor,
            name: "Connected",
            arg_pattern: %{
              kind: :constructor,
              name: "Ok",
              arg_pattern: %{kind: :constructor, name: "()", arg_pattern: nil}
            }
          },
          expr: %{op: :int_literal, value: 1}
        }
      ]
    }

    env =
      Emit.function_env("CompanionApp", ["msg"])
      |> Map.put(:module, "CompanionApp")
      |> Map.put(:emit_mode, :ide_runtime)

    {code, _, _} = Emit.compile_expr(expr, env, 0)
    source = IO.iodata_to_binary(code)

    assert source =~ "{:Connected, {:Ok, nil}}"
    refute source =~ ":()"
  end

  test "case on String values emits literal patterns not wildcards" do
    expr = %{
      op: :case,
      subject: "text",
      branches: [
        %{
          pattern: %{kind: :string, value: "dark"},
          expr: %{op: :int_literal, value: 1}
        },
        %{
          pattern: %{kind: :string, value: "light"},
          expr: %{op: :int_literal, value: 2}
        },
        %{
          pattern: %{kind: :wildcard},
          expr: %{op: :int_literal, value: 0}
        }
      ]
    }

    env =
      Emit.function_env("Main", ["text"])
      |> Map.put(:module, "Main")
      |> Map.put(:emit_mode, :ide_runtime)

    {code, _, _} = Emit.compile_expr(expr, env, 0)
    source = IO.iodata_to_binary(code)

    assert source =~ "\"dark\" ->"
    assert source =~ "\"light\" ->"
    assert source =~ "_ ->\n    0"
    refute Regex.match?(~r/_ ->\s+1/, source)
    refute Regex.match?(~r/_ ->\s+2/, source)
  end

  test "record case patterns use string keys to match record literals" do
    expr = %{
      op: :case,
      subject: "tile",
      branches: [
        %{
          pattern: %{
            op: :record,
            fields: [%{name: "moving"}, %{name: "slot"}]
          },
          expr: %{op: :int_literal, value: 1}
        }
      ]
    }

    env =
      Emit.function_env("Main", ["tile"])
      |> Map.put(:module, "Main")
      |> Map.put(:zero_arity_fns, MapSet.new())
      |> Map.put(:function_arities, %{})

    {code, _, _} = Emit.compile_expr(expr, env, 0)
    source = IO.iodata_to_binary(code)

    assert source =~ ~s/%{"moving": _, "slot": _}/
    refute source =~ "%{moving: _, slot: _}"
  end

  test "ide_runtime unary and binary constructors emit tagged tuples" do
    env =
      Emit.function_env("Main", [])
      |> Map.put(:module, "Main")
      |> Map.put(:emit_mode, :ide_runtime)

    {just_code, _, _} =
      Emit.compile_expr(
        %{op: :constructor_call, name: "Just", args: [%{op: :int_literal, value: 42}]},
        env,
        0
      )

    assert IO.iodata_to_binary(just_code) == "{:Just, 42}"

    {pair_code, _, _} =
      Emit.compile_expr(
        %{
          op: :constructor_call,
          name: "ProvideWebSocketStatus",
          args: [
            %{op: :var, name: "status"},
            %{op: :var, name: "detail"}
          ]
        },
        env,
        0
      )

    assert IO.iodata_to_binary(pair_code) =~ "{:ProvideWebSocketStatus, "
    refute IO.iodata_to_binary(pair_code) =~ "Values.ctor"
  end

  test "ide_runtime True and False constructors emit booleans" do
    env =
      Emit.function_env("Main", [])
      |> Map.put(:module, "Main")
      |> Map.put(:emit_mode, :ide_runtime)

    {false_code, _, _} = Emit.compile_expr(%{op: :constructor_call, name: "False", args: []}, env, 0)
    {true_code, _, _} = Emit.compile_expr(%{op: :constructor_call, name: "True", args: []}, env, 0)

    assert IO.iodata_to_binary(false_code) == "false"
    assert IO.iodata_to_binary(true_code) == "true"
  end

  test "ide_runtime zero-arg constructors emit atoms even when IR assigns integer tags" do
    lookup =
      %IR{
        modules: [
          %{
            name: "Battle",
            declarations: [],
            unions: %{
              "Scene" => %{
                tags: %{"Waiting" => 1, "AttackFrame1" => 2},
                payload_kinds: %{"Waiting" => :none, "AttackFrame1" => :none}
              }
            }
          }
        ],
        diagnostics: []
      }
      |> ConstructorLookup.from_ir()

    expr = %{op: :constructor_call, name: "Waiting", args: []}

    env =
      Emit.function_env("Main", ["model"])
      |> Map.put(:module, "Main")
      |> Map.put(:zero_arity_fns, MapSet.new())
      |> Map.put(:function_arities, %{})
      |> Map.put(:constructor_lookup, lookup)
      |> Map.put(:emit_mode, :ide_runtime)

    {code, _, _} = Emit.compile_expr(expr, env, 0)
    source = IO.iodata_to_binary(code)

    assert source =~ ":Waiting"
    refute source =~ ~r/\b1\b/
  end

  test "ide_runtime tagged union int literals from IR emit atoms" do
    expr = %{op: :int_literal, value: 1, union_ctor: "Battle.Waiting"}

    env =
      Emit.function_env("Battle", [])
      |> Map.put(:module, "Battle")
      |> Map.put(:emit_mode, :ide_runtime)

    {code, _, _} = Emit.compile_expr(expr, env, 0)
    assert IO.iodata_to_binary(code) == ":Waiting"
  end

  test "ide_runtime tagged union tuple2 emits constructor tuple" do
    expr = %{
      op: :tuple2,
      left: %{op: :int_literal, value: 2, union_ctor: "Battle.WildAppears"},
      right: %{op: :int_literal, value: 2}
    }

    env =
      Emit.function_env("Battle", [])
      |> Map.put(:module, "Battle")
      |> Map.put(:emit_mode, :ide_runtime)

    {code, _, _} = Emit.compile_expr(expr, env, 0)
    assert IO.iodata_to_binary(code) == "{:WildAppears, 2}"
  end

  test "ide_runtime flattens nested tuple2 tagged union values" do
    expr = %{
      op: :tuple2,
      left: %{op: :int_literal, value: 0, union_ctor: "Companion.Types.ProvidePosition"},
      right: %{
        op: :tuple2,
        left: %{op: :int_literal, value: 12_345_000},
        right: %{
          op: :tuple2,
          left: %{op: :int_literal, value: -98_765_000},
          right: %{op: :int_literal, value: 25}
        }
      }
    }

    env =
      Emit.function_env("Main", ["msg"])
      |> Map.put(:module, "Main")
      |> Map.put(:emit_mode, :ide_runtime)

    {code, _, _} = Emit.compile_expr(expr, env, 0)
    assert IO.iodata_to_binary(code) == "{:ProvidePosition, 12345000, -98765000, 25}"
  end
end
