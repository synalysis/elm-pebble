defmodule ElmExecutor.Runtime.CoreIREvaluatorTest do
  use ExUnit.Case, async: true

  alias ElmExecutor.Runtime.CoreIREvaluator

  test "evaluates arithmetic and let bindings deterministically" do
    expr = %{
      "op" => :let_in,
      "name" => "x",
      "value_expr" => %{"op" => :int_literal, "value" => 7},
      "in_expr" => %{
        "op" => :call,
        "name" => "__add__",
        "args" => [%{"op" => :var, "name" => "x"}, %{"op" => :int_literal, "value" => 5}]
      }
    }

    assert {:ok, 12} = CoreIREvaluator.evaluate(expr)
  end

  test "supports case pattern match with constructor payload" do
    expr = %{
      "op" => :case,
      "subject" => %{
        "op" => :constructor_call,
        "target" => "SetCount",
        "args" => [%{"op" => :int_literal, "value" => 42}]
      },
      "branches" => [
        %{
          "pattern" => %{
            "kind" => :constructor,
            "name" => "SetCount",
            "args" => [%{"kind" => :var, "name" => "n"}]
          },
          "expr" => %{"op" => :var, "name" => "n"}
        }
      ]
    }

    assert {:ok, 42} = CoreIREvaluator.evaluate(expr)
  end

  test "constructor bind exposes payload, not constructor envelope" do
    expr = %{
      "op" => :case,
      "subject" => %{"ctor" => "CurrentDateTime", "args" => [%{"hour" => 16, "minute" => 11}]},
      "branches" => [
        %{
          "pattern" => %{
            "kind" => :constructor,
            "name" => "CurrentDateTime",
            "bind" => "value"
          },
          "expr" => %{
            "op" => :field_access,
            "arg" => %{"op" => :var, "name" => "value"},
            "field" => "hour"
          }
        }
      ]
    }

    assert {:ok, 16} = CoreIREvaluator.evaluate(expr)
  end

  test "supports module-qualified function dispatch with indexed definitions" do
    core_ir = %{
      "modules" => [
        %{
          "name" => "Util.Math",
          "declarations" => [
            %{
              "kind" => "function",
              "name" => "incTwice",
              "args" => ["n"],
              "expr" => %{
                "op" => :call,
                "name" => "__add__",
                "args" => [
                  %{
                    "op" => :call,
                    "name" => "__add__",
                    "args" => [
                      %{"op" => :var, "name" => "n"},
                      %{"op" => :int_literal, "value" => 1}
                    ]
                  },
                  %{"op" => :int_literal, "value" => 1}
                ]
              }
            }
          ]
        }
      ]
    }

    expr = %{
      "op" => :qualified_call,
      "target" => "Util.Math.incTwice",
      "args" => [%{"op" => :int_literal, "value" => 10}]
    }

    context = %{
      functions: CoreIREvaluator.index_functions(core_ir),
      module: "Main",
      source_module: "Main"
    }

    assert {:ok, 12} = CoreIREvaluator.evaluate(expr, %{}, context)
  end

  test "index_functions accepts declaration args and binds env for field_access" do
    core_ir = %{
      "modules" => [
        %{
          "name" => "Main",
          "declarations" => [
            %{
              "kind" => "function",
              "name" => "view",
              "args" => ["model"],
              "expr" => %{
                "op" => :field_access,
                "arg" => %{"op" => :var, "name" => "model"},
                "field" => "x"
              }
            }
          ]
        }
      ]
    }

    context = %{
      functions: CoreIREvaluator.index_functions(core_ir),
      module: "Main",
      source_module: "Main"
    }

    expr = %{"op" => :qualified_call, "target" => "Main.view", "args" => [%{"x" => 33}]}
    assert {:ok, 33} = CoreIREvaluator.evaluate(expr, %{}, context)
  end

  test "Pebble.Ui arc builtin returns arc ui node" do
    expr = %{
      "op" => :qualified_call,
      "target" => "Pebble.Ui.arc",
      "args" => [
        %{"op" => :int_literal, "value" => 20},
        %{"op" => :int_literal, "value" => 16},
        %{"op" => :int_literal, "value" => 36},
        %{"op" => :int_literal, "value" => 36},
        %{"op" => :int_literal, "value" => 0},
        %{"op" => :int_literal, "value" => 45_000}
      ]
    }

    assert {:ok, %{"type" => "arc", "children" => children}} =
             CoreIREvaluator.evaluate(expr, %{}, %{})

    assert length(children) == 6
  end

  test "Pebble.Ui line builtin normalizes RGBA color constructors" do
    expr = %{
      "op" => :qualified_call,
      "target" => "Pebble.Ui.line",
      "args" => [
        %{"op" => :int_literal, "value" => 0},
        %{"op" => :int_literal, "value" => 1},
        %{"op" => :int_literal, "value" => 2},
        %{"op" => :int_literal, "value" => 3},
        %{
          "op" => :constructor_call,
          "target" => "Pebble.Ui.RGBA",
          "args" => [
            %{"op" => :int_literal, "value" => 255},
            %{"op" => :int_literal, "value" => 0},
            %{"op" => :int_literal, "value" => 0},
            %{"op" => :int_literal, "value" => 255}
          ]
        }
      ]
    }

    assert {:ok, %{"type" => "line", "children" => children}} =
             CoreIREvaluator.evaluate(expr, %{}, %{})

    assert length(children) == 5
    assert Enum.at(children, 4)["value"] == 240
  end

  test "Pebble.Ui line accepts point records and Pebble.Ui.Color constants" do
    expr = %{
      "op" => :qualified_call,
      "target" => "Pebble.Ui.line",
      "args" => [
        %{
          "op" => :record_literal,
          "fields" => [
            %{"name" => "x", "expr" => %{"op" => :int_literal, "value" => 72}},
            %{"name" => "y", "expr" => %{"op" => :int_literal, "value" => 84}}
          ]
        },
        %{
          "op" => :record_literal,
          "fields" => [
            %{"name" => "x", "expr" => %{"op" => :int_literal, "value" => 72}},
            %{"name" => "y", "expr" => %{"op" => :int_literal, "value" => 35}}
          ]
        },
        %{"op" => :qualified_call, "target" => "Pebble.Ui.Color.black", "args" => []}
      ]
    }

    assert {:ok, %{"type" => "line", "children" => children}} =
             CoreIREvaluator.evaluate(expr, %{}, %{})

    assert Enum.map(children, & &1["value"]) == [72, 84, 72, 35, 0xC0]
  end

  test "Pebble.Ui path ops normalize tuple path payload" do
    path_value = {[{0, 0}, {10, 0}, {10, 10}], {4, 6}, 0}

    expr = %{
      "op" => :qualified_call,
      "target" => "Pebble.Ui.pathFilled",
      "args" => [path_value]
    }

    assert {:ok, %{"type" => "pathFilled", "children" => [points_node, ox, oy, rot]}} =
             CoreIREvaluator.evaluate(expr, %{}, %{})

    assert points_node["type"] == "List"
    assert length(points_node["children"]) == 3
    assert ox["value"] == 4
    assert oy["value"] == 6
    assert rot["value"] == 0
  end

  test "supports tuple selector ops and modBy arithmetic" do
    expr = %{
      "op" => :let_in,
      "name" => "point",
      "value_expr" => %{
        "op" => :tuple2,
        "left" => %{"op" => :int_literal, "value" => 11},
        "right" => %{"op" => :int_literal, "value" => 22}
      },
      "in_expr" => %{
        "op" => :call,
        "name" => "__add__",
        "args" => [
          %{"op" => :tuple_first_expr, "arg" => %{"op" => :var, "name" => "point"}},
          %{
            "op" => :call,
            "name" => "Basics.modBy",
            "args" => [
              %{"op" => :int_literal, "value" => 5},
              %{"op" => :tuple_second_expr, "arg" => %{"op" => :var, "name" => "point"}}
            ]
          }
        ]
      }
    }

    assert {:ok, 13} = CoreIREvaluator.evaluate(expr)
  end

  test "compact module alias resolves user helpers through indexed CoreIR functions" do
    text_op = %{
      "op" => :qualified_call,
      "target" => "PebbleUi.text",
      "args" => [
        %{"op" => :int_literal, "value" => 1},
        %{
          "op" => :record_literal,
          "fields" => [
            %{"name" => "x", "expr" => %{"op" => :int_literal, "value" => 0}},
            %{"name" => "y", "expr" => %{"op" => :int_literal, "value" => 42}},
            %{"name" => "w", "expr" => %{"op" => :int_literal, "value" => 144}},
            %{"name" => "h", "expr" => %{"op" => :int_literal, "value" => 56}}
          ]
        },
        %{"op" => :string_literal, "value" => "08:41"}
      ]
    }

    helper_body = %{
      "op" => :qualified_call,
      "target" => "PebbleUi.windowStack",
      "args" => [
        %{
          "op" => :list_literal,
          "items" => [
            %{
              "op" => :qualified_call,
              "target" => "PebbleUi.window",
              "args" => [
                %{"op" => :int_literal, "value" => 1},
                %{
                  "op" => :list_literal,
                  "items" => [
                    %{
                      "op" => :qualified_call,
                      "target" => "PebbleUi.canvasLayer",
                      "args" => [
                        %{"op" => :int_literal, "value" => 1},
                        %{"op" => :var, "name" => "ops"}
                      ]
                    }
                  ]
                }
              ]
            }
          ]
        }
      ]
    }

    core_ir = %{
      "modules" => [
        %{
          "name" => "Pebble.Ui",
          "declarations" => [
            %{
              "kind" => "function",
              "name" => "toUiNode",
              "args" => ["ops"],
              "expr" => helper_body
            }
          ]
        }
      ]
    }

    context = %{
      functions: CoreIREvaluator.index_functions(core_ir),
      module: "Main",
      source_module: "Main"
    }

    expr = %{
      "op" => :qualified_call,
      "target" => "PebbleUi.toUiNode",
      "args" => [
        %{
          "op" => :list_literal,
          "items" => [
            %{
              "op" => :qualified_call,
              "target" => "PebbleUi.clear",
              "args" => [
                %{"op" => :qualified_call, "target" => "PebbleColor.black", "args" => []}
              ]
            },
            %{
              "op" => :qualified_call,
              "target" => "PebbleUi.group",
              "args" => [
                %{
                  "op" => :qualified_call,
                  "target" => "PebbleUi.context",
                  "args" => [
                    [],
                    %{"op" => :list_literal, "items" => [text_op]}
                  ]
                }
              ]
            }
          ]
        }
      ]
    }

    assert {:ok, %{"type" => "windowStack", "children" => [window]}} =
             CoreIREvaluator.evaluate(expr, %{}, context)

    assert %{"type" => "window", "children" => [_id, canvas]} = window
    assert %{"type" => "canvasLayer", "children" => [_layer_id, clear, group]} = canvas
    assert clear["type"] == "clear"

    assert %{"type" => "group", "children" => [%{"type" => "text", "children" => text_args}]} =
             group

    assert Enum.map(text_args, fn node ->
             if Map.has_key?(node, "value"), do: node["value"], else: node["label"]
           end) == [1, 0, 42, 144, 56, "08:41"]
  end
end
