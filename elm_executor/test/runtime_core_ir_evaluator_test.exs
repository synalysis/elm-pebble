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

  test "evaluates all generated operator forms" do
    env = %{"x" => 10, "y" => 3, "z" => 5}

    cases = [
      {%{"op" => :add_const, "var" => "x", "value" => 2}, 12},
      {%{"op" => :sub_const, "var" => "x", "value" => 2}, 8},
      {%{"op" => :add_vars, "left" => "x", "right" => "y"}, 13},
      {call("__add__", [var("x"), var("y")]), 13},
      {call("__sub__", [var("x"), var("y")]), 7},
      {call("__mul__", [var("x"), var("y")]), 30},
      {call("__idiv__", [var("x"), var("y")]), 3},
      {call("__fdiv__", [var("x"), var("y")]), 10 / 3},
      {call("__pow__", [var("y"), int(3)]), 27},
      {call("modBy", [var("y"), var("x")]), 1},
      {call("remainderBy", [var("y"), var("x")]), 1},
      {compare(:eq, var("x"), int(10)), true},
      {compare(:neq, var("x"), var("y")), true},
      {compare(:lt, var("y"), var("x")), true},
      {compare(:lte, var("y"), var("y")), true},
      {compare(:gt, var("x"), var("y")), true},
      {compare(:gte, var("x"), var("z")), true}
    ]

    for {expr, expected} <- cases do
      assert {:ok, ^expected} = CoreIREvaluator.evaluate(expr, env)
    end
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

  test "Pebble.Ui group preserves context style settings" do
    expr = %{
      "op" => :qualified_call,
      "target" => "Pebble.Ui.group",
      "args" => [
        %{
          "op" => :qualified_call,
          "target" => "Pebble.Ui.context",
          "args" => [
            %{
              "op" => :list_literal,
              "items" => [
                %{
                  "op" => :qualified_call,
                  "target" => "Pebble.Ui.textColor",
                  "args" => [%{"op" => :int_literal, "value" => 255}]
                }
              ]
            },
            %{
              "op" => :list_literal,
              "items" => [
                %{
                  "op" => :qualified_call,
                  "target" => "Pebble.Ui.text",
                  "args" => [
                    %{"op" => :int_literal, "value" => 1},
                    %{
                      "op" => :record_literal,
                      "fields" => [
                        %{"name" => "x", "expr" => %{"op" => :int_literal, "value" => 0}},
                        %{"name" => "y", "expr" => %{"op" => :int_literal, "value" => 52}},
                        %{"name" => "w", "expr" => %{"op" => :int_literal, "value" => 180}},
                        %{"name" => "h", "expr" => %{"op" => :int_literal, "value" => 56}}
                      ]
                    },
                    %{"op" => :string_literal, "value" => "--:--"}
                  ]
                }
              ]
            }
          ]
        }
      ]
    }

    assert {:ok, %{"type" => "group", "style" => %{"text_color" => 255}} = group} =
             CoreIREvaluator.evaluate(expr, %{}, %{})

    assert [%{"type" => "text"}] = group["children"]
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

  test "evaluates elm/http get descriptors and decodes json callbacks" do
    decoder = {:json_decoder, {:field, "temperature", {:json_decoder, :float}}}

    expr = %{
      "op" => :qualified_call,
      "target" => "Http.get",
      "args" => [
        %{
          "op" => :record_literal,
          "fields" => [
            %{
              "name" => "url",
              "expr" => %{"op" => :string_literal, "value" => "https://example.test/weather"}
            },
            %{
              "name" => "expect",
              "expr" => %{
                "op" => :qualified_call,
                "target" => "Http.expectJson",
                "args" => [%{"op" => :var, "name" => "WeatherReceived"}, decoder]
              }
            }
          ]
        }
      ]
    }

    assert {:ok, command} = CoreIREvaluator.evaluate(expr)
    assert command["kind"] == "http"
    assert command["method"] == "GET"
    assert command["url"] == "https://example.test/weather"
    assert command["expect"]["kind"] == "json"

    response = %{"status" => 200, "body" => ~s({"temperature":21.5})}

    assert {:ok,
            %{
              "ctor" => "WeatherReceived",
              "args" => [%{"ctor" => "Ok", "args" => [21.5]}]
            }} = CoreIREvaluator.decode_http_response(command, response)
  end

  test "evaluates zero arity decoder values and tagged http callbacks" do
    core_ir = %{
      "modules" => [
        %{
          "name" => "Main",
          "unions" => %{
            "Msg" => %{
              "tags" => %{"WeatherReceived" => 2}
            }
          },
          "declarations" => [
            %{
              "kind" => "function",
              "name" => "update",
              "args" => ["msg", "model"],
              "expr" => %{"op" => :literal, "value" => nil}
            },
            %{
              "kind" => "type_alias",
              "name" => "WeatherReport",
              "expr" => %{"op" => :record_alias, "fields" => ["temperature", "condition"]}
            },
            %{
              "kind" => "function",
              "name" => "weatherReportDecoder",
              "args" => [],
              "expr" => %{
                "op" => :qualified_call,
                "target" => "Json.Decode.map2",
                "args" => [
                  %{"op" => :constructor_call, "target" => "WeatherReport", "args" => []},
                  %{
                    "op" => :qualified_call,
                    "target" => "Json.Decode.field",
                    "args" => [
                      %{"op" => :string_literal, "value" => "temperature_2m"},
                      %{"op" => :qualified_call, "target" => "Json.Decode.float", "args" => []}
                    ]
                  },
                  %{
                    "op" => :qualified_call,
                    "target" => "Json.Decode.field",
                    "args" => [
                      %{"op" => :string_literal, "value" => "weather_code"},
                      %{"op" => :qualified_call, "target" => "Json.Decode.int", "args" => []}
                    ]
                  }
                ]
              }
            }
          ]
        }
      ]
    }

    context = %{
      module: "Main",
      source_module: "Main",
      functions: CoreIREvaluator.index_functions(core_ir),
      record_aliases: CoreIREvaluator.index_record_aliases(core_ir),
      constructor_tags: CoreIREvaluator.index_constructor_tags(core_ir)
    }

    expr = %{
      "op" => :qualified_call,
      "target" => "Http.get",
      "args" => [
        %{
          "op" => :record_literal,
          "fields" => [
            %{
              "name" => "url",
              "expr" => %{"op" => :string_literal, "value" => "https://example.test"}
            },
            %{
              "name" => "expect",
              "expr" => %{
                "op" => :qualified_call,
                "target" => "Http.expectJson",
                "args" => [
                  %{"op" => :int_literal, "value" => 2},
                  %{"op" => :var, "name" => "weatherReportDecoder"}
                ]
              }
            }
          ]
        }
      ]
    }

    assert {:ok, command} = CoreIREvaluator.evaluate(expr, %{}, context)
    assert {:json_decoder, _} = command["expect"]["decoder"]

    response = %{"status" => 200, "body" => ~s({"temperature_2m":19.2,"weather_code":0})}

    assert {:ok,
            %{
              "ctor" => "WeatherReceived",
              "args" => [
                %{
                  "ctor" => "Ok",
                  "args" => [%{"temperature" => 19.2, "condition" => 0}]
                }
              ]
            }} = CoreIREvaluator.decode_http_response(command, response, context)
  end

  test "evaluates elm/http request descriptors with headers and string bodies" do
    expr = %{
      "op" => :qualified_call,
      "target" => "Http.request",
      "args" => [
        %{
          "op" => :record_literal,
          "fields" => [
            %{"name" => "method", "expr" => %{"op" => :string_literal, "value" => "PUT"}},
            %{
              "name" => "url",
              "expr" => %{"op" => :string_literal, "value" => "https://example.test/items/1"}
            },
            %{
              "name" => "headers",
              "expr" => %{
                "op" => :list_literal,
                "items" => [
                  %{
                    "op" => :qualified_call,
                    "target" => "Http.header",
                    "args" => [
                      %{"op" => :string_literal, "value" => "x-test"},
                      %{"op" => :string_literal, "value" => "yes"}
                    ]
                  }
                ]
              }
            },
            %{
              "name" => "body",
              "expr" => %{
                "op" => :qualified_call,
                "target" => "Http.stringBody",
                "args" => [
                  %{"op" => :string_literal, "value" => "text/plain"},
                  %{"op" => :string_literal, "value" => "payload"}
                ]
              }
            },
            %{
              "name" => "expect",
              "expr" => %{
                "op" => :qualified_call,
                "target" => "Http.expectString",
                "args" => [%{"op" => :var, "name" => "Saved"}]
              }
            }
          ]
        }
      ]
    }

    assert {:ok, command} = CoreIREvaluator.evaluate(expr)
    assert command["method"] == "PUT"
    assert command["headers"] == [%{"name" => "x-test", "value" => "yes"}]
    assert command["body"]["kind"] == "string"
    assert command["body"]["content_type"] == "text/plain"
    assert command["body"]["body"] == "payload"
  end

  defp call(name, args), do: %{"op" => :call, "name" => name, "args" => args}

  defp compare(kind, left, right),
    do: %{"op" => :compare, "kind" => kind, "left" => left, "right" => right}

  defp int(value), do: %{"op" => :int_literal, "value" => value}
  defp var(name), do: %{"op" => :var, "name" => name}
end
