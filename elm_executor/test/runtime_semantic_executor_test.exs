defmodule ElmExecutor.Runtime.SemanticExecutorTest do
  use ExUnit.Case, async: true

  alias ElmExecutor.Runtime.SemanticExecutor

  test "source fallback derives CoreIR for helper-returned point tuples in preview lines" do
    source = """
    module Main exposing (main)

    import Json.Decode as Decode
    import Pebble.Platform as PebblePlatform
    import Pebble.Ui as PebbleUi
    import Pebble.Ui.Color as PebbleColor

    type alias Model =
        { screenW : Int
        , screenH : Int
        }

    type Msg
        = Tick

    init _ =
        ( { screenW = 144, screenH = 168 }, Cmd.none )

    update msg model =
        case msg of
            Tick ->
                ( model, Cmd.none )

    subscriptions _ =
        Sub.none

    view model =
        let
            centerX =
                model.screenW // 2

            centerY =
                model.screenH // 2

            ( x2, y2 ) =
                endPoint centerX centerY
        in
        PebbleUi.windowStack
            [ PebbleUi.window 1
                [ PebbleUi.canvasLayer 1
                    [ PebbleUi.line { x = centerX, y = centerY } { x = x2, y = y2 } PebbleColor.black
                    ]
                ]
            ]

    endPoint x y =
        ( x + 10, y - 10 )

    main : Program Decode.Value Model Msg
    main =
        PebblePlatform.watchface
            { init = init
            , update = update
            , view = view
            , subscriptions = subscriptions
            }
    """

    request = %{
      source_root: "watch",
      rel_path: "watch/src/Main.elm",
      source: source,
      introspect: %{},
      current_model: %{"runtime_model" => %{"screenW" => 144, "screenH" => 168}},
      current_view_tree: %{},
      message: nil
    }

    assert {:ok, result} = SemanticExecutor.execute(request)

    refute Enum.any?(result.view_output, fn row -> row["kind"] == "unresolved" end)

    assert Enum.any?(result.view_output, fn row ->
             row["kind"] == "line" and row["x1"] == 72 and row["y1"] == 84 and
               row["x2"] == 82 and row["y2"] == 74 and row["color"] == 0xC0
           end)
  end

  test "executes step mutation contract without elmc dependency" do
    request = %{
      source_root: "watch",
      rel_path: "watch/src/Main.elm",
      source: "module Main exposing (main)\n",
      introspect: %{
        "init_model" => %{"n" => 0},
        "view_tree" => %{"type" => "root", "children" => []}
      },
      current_model: %{"runtime_model" => %{"n" => 2}},
      current_view_tree: %{"type" => "root", "children" => []},
      message: "Inc",
      update_branches: ["Inc"]
    }

    assert {:ok, result} = SemanticExecutor.execute(request)
    assert result.runtime["engine"] == "elm_executor_runtime_v1"
    assert result.model_patch["runtime_model"]["n"] == 2
    assert result.runtime["operation_source"] == "unmapped_message"
    assert result.model_patch["runtime_model"]["last_operation"] == "nil"
    assert result.model_patch["runtime_model_source"] == "step_message"
    assert result.protocol_events == []
  end

  test "normalizes tuple-backed runtime model values through declared record and union types" do
    core_ir = %{
      "modules" => [
        %{
          "name" => "Main",
          "unions" => %{
            "SunMode" => %{
              "tags" => %{"SunCycle" => 1, "PolarDay" => 2},
              "payload_specs" => %{}
            },
            "TemperatureUnit" => %{
              "tags" => %{"Celsius" => 1, "Fahrenheit" => 2},
              "payload_specs" => %{}
            }
          },
          "declarations" => [
            record_alias("Model", ["sun", "displayUnits"], %{
              "sun" => "Maybe SunWindow",
              "displayUnits" => "DisplayUnits"
            }),
            record_alias("SunWindow", ["sunriseMin", "sunsetMin", "mode"], %{
              "sunriseMin" => "Int",
              "sunsetMin" => "Int",
              "mode" => "SunMode"
            }),
            record_alias("DisplayUnits", ["temperature"], %{
              "temperature" => "TemperatureUnit"
            })
          ]
        }
      ]
    }

    request = %{
      source_root: "watch",
      source: "module Main exposing (main)",
      current_model: %{
        "runtime_model" => %{
          "sun" => {1, {360, {1080, 2}}},
          "displayUnits" => %{"temperature" => 1}
        }
      },
      current_view_tree: %{},
      message: nil,
      elm_executor_core_ir: core_ir
    }

    assert {:ok, result} = SemanticExecutor.execute(request)

    assert %{
             "ctor" => "Just",
             "args" => [
               %{
                 "sunriseMin" => 360,
                 "sunsetMin" => 1080,
                 "mode" => %{"ctor" => "PolarDay", "args" => []}
               }
             ]
           } = result.model_patch["runtime_model"]["sun"]

    assert %{
             "temperature" => %{"ctor" => "Celsius", "args" => []}
           } = result.model_patch["runtime_model"]["displayUnits"]
  end

  test "normalizes legacy tuple-constructor maps through declared record and union types" do
    core_ir = %{
      "modules" => [
        %{
          "name" => "Main",
          "unions" => %{
            "SunMode" => %{
              "tags" => %{"SunCycle" => 1},
              "payload_specs" => %{}
            },
            "TideKind" => %{
              "tags" => %{"HighTide" => 1},
              "payload_specs" => %{}
            }
          },
          "declarations" => [
            record_alias("Model", ["sun", "tide"], %{
              "sun" => "Maybe SunWindow",
              "tide" => "Maybe Tide"
            }),
            record_alias("SunWindow", ["sunriseMin", "sunsetMin", "mode"], %{
              "sunriseMin" => "Int",
              "sunsetMin" => "Int",
              "mode" => "SunMode"
            }),
            record_alias("Tide", ["nextMin", "levelCm", "progress", "kind"], %{
              "nextMin" => "Int",
              "levelCm" => "Int",
              "progress" => "Int",
              "kind" => "TideKind"
            })
          ]
        }
      ]
    }

    request = %{
      source_root: "watch",
      source: "module Main exposing (main)",
      current_model: %{
        "runtime_model" => %{
          "sun" => %{
            "ctor" => "Just",
            "args" => [
              %{
                "ctor" => "360,",
                "args" => [
                  %{"ctor" => "(1080,", "args" => [%{"ctor" => "1)", "args" => []}]}
                ]
              }
            ]
          },
          "tide" => %{
            "ctor" => "Just",
            "args" => [
              %{
                "ctor" => "372,",
                "args" => [
                  %{
                    "ctor" => "(90,",
                    "args" => [
                      %{
                        "ctor" => "(420,",
                        "args" => [%{"ctor" => "1))", "args" => []}]
                      }
                    ]
                  }
                ]
              }
            ]
          }
        }
      },
      current_view_tree: %{},
      message: nil,
      elm_executor_core_ir: core_ir
    }

    assert {:ok, result} = SemanticExecutor.execute(request)

    assert %{
             "ctor" => "Just",
             "args" => [
               %{
                 "sunriseMin" => 360,
                 "sunsetMin" => 1080,
                 "mode" => %{"ctor" => "SunCycle", "args" => []}
               }
             ]
           } = result.model_patch["runtime_model"]["sun"]

    assert %{
             "ctor" => "Just",
             "args" => [
               %{
                 "nextMin" => 372,
                 "levelCm" => 90,
                 "progress" => 420,
                 "kind" => %{"ctor" => "HighTide", "args" => []}
               }
             ]
           } = result.model_patch["runtime_model"]["tide"]
  end

  test "core update returns evaluated elm/http commands as followup work" do
    core_ir = %{
      "modules" => [
        %{
          "name" => "Main",
          "declarations" => [
            %{
              "kind" => "function",
              "name" => "update",
              "expr" => %{
                "op" => :case,
                "subject" => %{"op" => :var, "name" => "msg"},
                "branches" => [
                  %{
                    "pattern" => %{"kind" => :constructor, "name" => "RequestWeather"},
                    "expr" => %{
                      "op" => :tuple2,
                      "left" => %{
                        "op" => :record_literal,
                        "fields" => [
                          %{
                            "name" => "status",
                            "expr" => %{"op" => :string_literal, "value" => "requested"}
                          }
                        ]
                      },
                      "right" => %{
                        "op" => :qualified_call,
                        "target" => "Cmd.batch",
                        "args" => [
                          %{
                            "op" => :list_literal,
                            "items" => [
                              %{
                                "op" => :qualified_call,
                                "target" => "Http.get",
                                "args" => [
                                  %{
                                    "op" => :record_literal,
                                    "fields" => [
                                      %{
                                        "name" => "url",
                                        "expr" => %{
                                          "op" => :string_literal,
                                          "value" => "https://example.test/weather"
                                        }
                                      },
                                      %{
                                        "name" => "expect",
                                        "expr" => %{
                                          "op" => :qualified_call,
                                          "target" => "Http.expectString",
                                          "args" => [%{"op" => :var, "name" => "WeatherReceived"}]
                                        }
                                      }
                                    ]
                                  }
                                ]
                              }
                            ]
                          }
                        ]
                      }
                    }
                  }
                ]
              }
            }
          ]
        }
      ]
    }

    request = %{
      source_root: "companion",
      source: "module Main exposing (..)",
      introspect: %{"view_tree" => %{"type" => "root", "children" => []}},
      current_model: %{"runtime_model" => %{"status" => "idle"}},
      current_view_tree: %{"type" => "root", "children" => []},
      message: "RequestWeather",
      elm_executor_core_ir: core_ir
    }

    assert {:ok, result} = SemanticExecutor.execute(request)
    assert result.model_patch["runtime_model"]["status"] == "requested"

    assert [
             %{
               "source" => "http_command",
               "package" => "elm/http",
               "command" => command
             }
           ] = result.followup_messages

    assert command["kind"] == "http"
    assert command["method"] == "GET"
    assert command["url"] == "https://example.test/weather"
    assert command["expect"]["kind"] == "string"
  end

  test "init evaluation surfaces elm/random followups when message is empty" do
    core_ir = %ElmEx.IR{
      modules: [
        %ElmEx.IR.Module{
          name: "Main",
          imports: [],
          declarations: [
            %ElmEx.IR.Declaration{
              kind: :function,
              name: "init",
              args: [],
              ownership: [],
              expr: %{
                "op" => :tuple2,
                "left" => %{
                  "op" => :record_literal,
                  "fields" => [
                    %{"name" => "n", "expr" => %{"op" => :int_literal, "value" => 0}}
                  ]
                },
                "right" => %{
                  "op" => :qualified_call,
                  "target" => "Random.generate",
                  "args" => [
                    %{"op" => :var, "name" => "GotSeed"},
                    %{
                      "op" => :qualified_call,
                      "target" => "Random.int",
                      "args" => [
                        %{"op" => :int_literal, "value" => 1},
                        %{"op" => :int_literal, "value" => 10}
                      ]
                    }
                  ]
                }
              }
            }
          ]
        }
      ]
    }

    request = %{
      source_root: "watch",
      source: "module Main exposing (..)",
      introspect: %{"view_tree" => %{"type" => "root", "children" => []}},
      current_model: %{},
      current_view_tree: %{"type" => "root", "children" => []},
      message: nil,
      elm_executor_core_ir: core_ir
    }

    assert {:ok, result} = SemanticExecutor.execute(request)

    assert [followup] = result.followup_messages
    assert followup["source"] == "random_command"
    assert followup["package"] == "elm/random"
    assert followup["message"] == "GotSeed"
    assert is_map(followup["message_value"])

    assert result.runtime["followup_message_count"] == 1
  end

  test "init evaluation preserves storage and random commands in a batch" do
    core_ir = %ElmEx.IR{
      modules: [
        %ElmEx.IR.Module{
          name: "Main",
          imports: [],
          declarations: [
            %ElmEx.IR.Declaration{
              kind: :function,
              name: "init",
              args: [],
              ownership: [],
              expr: %{
                "op" => :tuple2,
                "left" => %{
                  "op" => :record_literal,
                  "fields" => [
                    %{"name" => "seed", "expr" => %{"op" => :int_literal, "value" => 0}},
                    %{"name" => "best", "expr" => %{"op" => :int_literal, "value" => 0}}
                  ]
                },
                "right" => %{
                  "op" => :qualified_call,
                  "target" => "Cmd.batch",
                  "args" => [
                    %{
                      "op" => :list_literal,
                      "items" => [
                        %{
                          "op" => :qualified_call,
                          "target" => "Pebble.Storage.readString",
                          "args" => [
                            %{"op" => :int_literal, "value" => 2048},
                            %{"op" => :var, "name" => "BestLoaded"}
                          ]
                        },
                        %{
                          "op" => :qualified_call,
                          "target" => "Random.generate",
                          "args" => [
                            %{"op" => :var, "name" => "RandomGenerated"},
                            %{
                              "op" => :qualified_call,
                              "target" => "Random.int",
                              "args" => [
                                %{"op" => :int_literal, "value" => 1},
                                %{"op" => :int_literal, "value" => 10}
                              ]
                            }
                          ]
                        }
                      ]
                    }
                  ]
                }
              }
            }
          ]
        }
      ]
    }

    request = %{
      source_root: "watch",
      source: "module Main exposing (..)",
      introspect: %{"view_tree" => %{"type" => "root", "children" => []}},
      current_model: %{},
      current_view_tree: %{"type" => "root", "children" => []},
      message: nil,
      elm_executor_core_ir: core_ir
    }

    assert {:ok, result} = SemanticExecutor.execute(request)

    assert [
             %{"source" => "storage_command", "message" => "BestLoaded"},
             %{"source" => "random_command", "message" => "RandomGenerated"}
           ] = result.followup_messages

    assert result.runtime["followup_message_count"] == 2
  end

  test "core update matches structured protocol payloads with nested constructors" do
    core_ir = %{
      "modules" => [
        %{
          "name" => "CompanionApp",
          "declarations" => [
            %{
              "kind" => "function",
              "name" => "update",
              "expr" => %{
                "op" => :case,
                "subject" => %{"op" => :var, "name" => "msg"},
                "branches" => [
                  %{
                    "pattern" => %{
                      "kind" => :constructor,
                      "name" => "FromWatch",
                      "arg_pattern" => %{
                        "kind" => :constructor,
                        "name" => "Ok",
                        "arg_pattern" => %{
                          "kind" => :constructor,
                          "name" => "RequestWeather",
                          "arg_pattern" => %{"kind" => :var, "name" => "location"}
                        }
                      }
                    },
                    "expr" => %{
                      "op" => :tuple2,
                      "left" => %{
                        "op" => :record_literal,
                        "fields" => [
                          %{
                            "name" => "status",
                            "expr" => %{"op" => :string_literal, "value" => "requested"}
                          }
                        ]
                      },
                      "right" => %{
                        "op" => :case,
                        "subject" => %{"op" => :var, "name" => "location"},
                        "branches" => [
                          %{
                            "pattern" => %{"kind" => :constructor, "name" => "CurrentLocation"},
                            "expr" => %{
                              "op" => :qualified_call,
                              "target" => "Http.get",
                              "args" => [
                                %{
                                  "op" => :record_literal,
                                  "fields" => [
                                    %{
                                      "name" => "url",
                                      "expr" => %{
                                        "op" => :string_literal,
                                        "value" => "https://example.test/weather"
                                      }
                                    },
                                    %{
                                      "name" => "expect",
                                      "expr" => %{
                                        "op" => :qualified_call,
                                        "target" => "Http.expectString",
                                        "args" => [%{"op" => :var, "name" => "WeatherReceived"}]
                                      }
                                    }
                                  ]
                                }
                              ]
                            }
                          }
                        ]
                      }
                    }
                  }
                ]
              }
            }
          ]
        }
      ]
    }

    request = %{
      source_root: "companion",
      source: "module CompanionApp exposing (..)",
      introspect: %{"view_tree" => %{"type" => "root", "children" => []}},
      current_model: %{"runtime_model" => %{"status" => "idle"}},
      current_view_tree: %{"type" => "root", "children" => []},
      message: "FromWatch (Ok (RequestWeather CurrentLocation))",
      message_value: %{
        "ctor" => "FromWatch",
        "args" => [
          %{
            "ctor" => "Ok",
            "args" => [
              %{
                "ctor" => "RequestWeather",
                "args" => [%{"ctor" => "CurrentLocation", "args" => []}]
              }
            ]
          }
        ]
      },
      elm_executor_core_ir: core_ir
    }

    assert {:ok, result} = SemanticExecutor.execute(request)
    assert result.model_patch["runtime_model"]["status"] == "requested"
    assert [%{"command" => %{"url" => "https://example.test/weather"}}] = result.followup_messages
  end

  test "reload path uses init model and parser view tree" do
    request = %{
      source_root: "watch",
      rel_path: "watch/src/Main.elm",
      source: "module Main exposing (main)\n",
      introspect: %{
        "init_model" => %{"n" => 9},
        "view_tree" => %{"type" => "root", "children" => []}
      },
      current_model: %{},
      current_view_tree: %{},
      message: nil,
      update_branches: []
    }

    assert {:ok, result} = SemanticExecutor.execute(request)
    assert result.model_patch["runtime_model"]["n"] == 9
    assert result.runtime["runtime_model_source"] == "init_model"
    assert result.runtime["view_tree_source"] == "parser_view_tree"
  end

  test "reload path prefers evaluated CoreIR init model over static syntax snapshot" do
    core_ir = %{
      "modules" => [
        %{
          "name" => "Main",
          "declarations" => [
            %{
              "kind" => "function",
              "name" => "init",
              "params" => ["launch"],
              "expr" => %{
                "op" => :tuple2,
                "left" => %{
                  "op" => :record_literal,
                  "fields" => [
                    %{
                      "name" => "showDate",
                      "expr" => %{"op" => :constructor_call, "target" => "True", "args" => []}
                    },
                    %{
                      "name" => "isRound",
                      "expr" => %{
                        "op" => :field_access,
                        "arg" => %{
                          "op" => :field_access,
                          "arg" => %{"op" => :var, "name" => "launch"},
                          "field" => "shape"
                        },
                        "field" => "is_round"
                      }
                    },
                    %{
                      "name" => "backgroundColor",
                      "expr" => %{
                        "op" => :qualified_call,
                        "target" => "Pebble.Ui.Color.black",
                        "args" => []
                      }
                    },
                    %{
                      "name" => "temperature",
                      "expr" => %{
                        "op" => :constructor_call,
                        "target" => "Just",
                        "args" => [
                          %{
                            "op" => :constructor_call,
                            "target" => "Celsius",
                            "args" => [%{"op" => :int_literal, "value" => 21}]
                          }
                        ]
                      }
                    }
                  ]
                },
                "right" => %{"op" => :qualified_call, "target" => "Cmd.none", "args" => []}
              }
            }
          ]
        }
      ]
    }

    request = %{
      source_root: "watch",
      rel_path: "watch/src/Main.elm",
      source: "module Main exposing (main)\n",
      introspect: %{
        "init_model" => %{
          "showDate" => %{"$ctor" => "True", "$args" => []},
          "isRound" => %{"$opaque" => true, "op" => "field_access"},
          "backgroundColor" => %{"$call" => "PebbleColor", "$args" => []}
        },
        "view_tree" => %{"type" => "root", "children" => []}
      },
      current_model: %{
        "launch_context" => %{"shape" => %{"is_round" => true}}
      },
      current_view_tree: %{"type" => "root", "children" => []},
      elm_executor_core_ir: core_ir
    }

    assert {:ok, result} = SemanticExecutor.execute(request)

    runtime_model = result.model_patch["runtime_model"]
    assert runtime_model["showDate"] == true
    assert runtime_model["isRound"] == true
    assert is_integer(runtime_model["backgroundColor"])

    assert runtime_model["temperature"] == %{
             "ctor" => "Just",
             "args" => [%{"ctor" => "Celsius", "args" => [21]}]
           }
  end

  test "reload path evaluates source-derived CoreIR init model with list helpers" do
    source = """
    module Main exposing (main)

    import Json.Decode as Decode
    import Pebble.Platform as Platform
    import Pebble.Ui as Ui
    import Pebble.Ui.Resources as Resources

    type alias Model =
        { cells : List Int
        , score : Int
        }

    init _ =
        ( { cells = insertTile 0 emptyBoard, score = 0 }, Cmd.none )

    update _ model =
        ( model, Cmd.none )

    subscriptions _ =
        Sub.none

    view model =
        Ui.toUiNode (List.indexedMap drawCell model.cells)

    emptyBoard : List Int
    emptyBoard =
        List.repeat 16 0

    insertTile : Int -> List Int -> List Int
    insertTile turn cells =
        let
            index =
                modBy 16 (turn * 5 + 1)
        in
        List.indexedMap
            (\\i value ->
                if i == index && value == 0 then
                    2

                else
                    value
            )
            cells

    drawCell index value =
        Ui.text Resources.DefaultFont { x = index, y = 0, w = 10, h = 10 } (String.fromInt value)

    main : Program Decode.Value Model msg
    main =
        Platform.application
            { init = init
            , update = update
            , view = view
            , subscriptions = subscriptions
            }
    """

    request = %{
      source_root: "watch",
      rel_path: "watch/src/Main.elm",
      source: source,
      introspect: %{
        "init_model" => %{
          "cells" => %{"$opaque" => true, "op" => "call"},
          "score" => 0
        }
      },
      current_model: %{},
      current_view_tree: %{},
      message: nil
    }

    assert {:ok, result} = SemanticExecutor.execute(request)

    assert result.model_patch["runtime_model"]["cells"] == [
             0,
             2,
             0,
             0,
             0,
             0,
             0,
             0,
             0,
             0,
             0,
             0,
             0,
             0,
             0,
             0
           ]

    assert result.model_patch["runtime_model_source"] == "init_model"

    assert Enum.any?(result.view_output, fn row ->
             row["kind"] == "text" and row["font_id"] == 1 and row["text"] == "2"
           end)
  end

  test "runtime view_output evaluates helper, List.map, if, append, and package render op lists" do
    source = """
    module Main exposing (main)

    import Json.Decode as Decode
    import Pebble.Platform as Platform
    import Pebble.Ui as Ui
    import Pebble.Ui.Color as Color
    import Pebble.Ui.Resources as Resources

    type alias Item =
        { x : Int
        , y : Int
        }

    type alias Model =
        { items : List Item
        , offset : Int
        , paused : Bool
        }

    init _ =
        ( { items = [ { x = 1, y = 40 }, { x = 2, y = 56 } ]
          , offset = 0
          , paused = False
          }
        , Cmd.none
        )

    update _ model =
        ( model, Cmd.none )

    subscriptions _ =
        Sub.none

    view model =
        Ui.toUiNode
            ([ Ui.clear Color.white ]
                ++ parallaxBitmap Resources.NoBitmap { x = 0, y = 100, w = 20, h = 8 } model.offset
                ++ List.map (drawItem model.offset) model.items
                ++ (if model.paused then
                        [ Ui.text Resources.DefaultFont { x = 4, y = 4, w = 40, h = 12 } "PAUSED" ]

                    else
                        []
                   )
            )

    drawItem offset item =
        Ui.fillRect { x = item.x * 8 - offset, y = item.y, w = 6, h = 6 } Color.black

    parallaxBitmap bitmap bounds offset =
        let
            wrapped =
                modBy bounds.w offset
        in
        [ Ui.drawBitmapInRect bitmap { bounds | x = bounds.x - wrapped }
        , Ui.drawBitmapInRect bitmap { bounds | x = bounds.x - wrapped + bounds.w }
        ]

    main : Program Decode.Value Model msg
    main =
        Platform.application
            { init = init
            , update = update
            , view = view
            , subscriptions = subscriptions
            }
    """

    request = %{
      source_root: "watch",
      rel_path: "watch/src/Main.elm",
      source: source,
      introspect: %{
        "view_source_locations" => %{
          "clear" => [%{"call" => "Ui.clear", "line" => 36, "path" => "src/Main.elm"}],
          "fill_rect" => [%{"call" => "Ui.fillRect", "line" => 48, "path" => "src/Main.elm"}],
          "bitmap_in_rect" => [
            %{"call" => "Ui.drawBitmapInRect", "line" => 55, "path" => "src/Main.elm"},
            %{"call" => "Ui.drawBitmapInRect", "line" => 56, "path" => "src/Main.elm"}
          ],
          "text" => [%{"call" => "Ui.text", "line" => 40, "path" => "src/Main.elm"}]
        }
      },
      current_model: %{},
      current_view_tree: %{},
      message: nil
    }

    assert {:ok, result} = SemanticExecutor.execute(request)
    refute Enum.any?(result.view_output, &(&1["kind"] == "unresolved"))

    assert Enum.any?(result.view_output, &(&1["kind"] == "clear" and &1["color"] == 0xFF))

    assert Enum.count(result.view_output, &(&1["kind"] == "bitmap_in_rect")) == 2

    assert Enum.any?(result.view_output, fn row ->
             row["kind"] == "fill_rect" and row["x"] == 8 and row["y"] == 40 and
               row["w"] == 6 and row["h"] == 6 and row["fill"] == 0xC0
           end)

    assert Enum.any?(result.view_output, fn row ->
             row["kind"] == "fill_rect" and row["x"] == 16 and row["y"] == 56
           end)

    refute Enum.any?(result.view_output, &(&1["text"] == "PAUSED"))

    assert Enum.any?(result.view_output, fn row ->
             row["kind"] == "fill_rect" and
               row["source"] == %{"call" => "Ui.fillRect", "line" => 48, "path" => "src/Main.elm"}
           end)
  end

  test "runtime view_output evaluates package helper functions from supplied CoreIR" do
    sprite_source = """
    module Pebble.Game.Sprite exposing (parallaxBitmap)

    import Pebble.Ui as Ui

    parallaxBitmap bitmap bounds offset =
        let
            wrapped =
                modBy bounds.w offset
        in
        [ Ui.drawBitmapInRect bitmap { bounds | x = bounds.x - wrapped }
        , Ui.drawBitmapInRect bitmap { bounds | x = bounds.x - wrapped + bounds.w }
        ]
    """

    main_source = """
    module Main exposing (main)

    import Json.Decode as Decode
    import Pebble.Game.Sprite
    import Pebble.Platform as Platform
    import Pebble.Ui as Ui
    import Pebble.Ui.Resources as Resources

    type alias Model =
        { offset : Int }

    init _ =
        ( { offset = 0 }, Cmd.none )

    update _ model =
        ( model, Cmd.none )

    subscriptions _ =
        Sub.none

    view model =
        Ui.toUiNode
            (Pebble.Game.Sprite.parallaxBitmap
                Resources.NoBitmap
                { x = 0, y = 100, w = 20, h = 8 }
                model.offset
            )

    main : Program Decode.Value Model msg
    main =
        Platform.application
            { init = init
            , update = update
            , view = view
            , subscriptions = subscriptions
            }
    """

    core_ir =
      core_ir_from_sources([
        {"watch/src/Main.elm", main_source},
        {"watch/src/Pebble/Game/Sprite.elm", sprite_source}
      ])

    request = %{
      source_root: "watch",
      rel_path: "watch/src/Main.elm",
      source: main_source,
      introspect: %{},
      current_model: %{},
      current_view_tree: %{},
      message: nil,
      elm_executor_core_ir: core_ir
    }

    assert {:ok, result} = SemanticExecutor.execute(request)

    assert [
             %{"kind" => "bitmap_in_rect", "bitmap_id" => 0, "x" => 0, "y" => 100},
             %{"kind" => "bitmap_in_rect", "bitmap_id" => 0, "x" => 20, "y" => 100}
           ] = result.view_output
  end

  test "runtime resolves decoded CoreIR init screen fields before drawing preview primitives" do
    model_screen_w = %{
      "op" => "field_access",
      "arg" => %{"op" => "var", "name" => "model"},
      "field" => "screenW"
    }

    model_time_string = %{
      "op" => "field_access",
      "arg" => %{"op" => "var", "name" => "model"},
      "field" => "timeString"
    }

    centered_x = %{
      "op" => "call",
      "name" => "__idiv__",
      "args" => [
        %{
          "op" => "call",
          "name" => "__sub__",
          "args" => [model_screen_w, %{"op" => "int_literal", "value" => 100}]
        },
        %{"op" => "int_literal", "value" => 2}
      ]
    }

    core_ir = %{
      "modules" => [
        %{
          "name" => "Main",
          "declarations" => [
            %{
              "kind" => "function",
              "name" => "init",
              "params" => ["launch"],
              "expr" => %{
                "op" => "tuple2",
                "left" => %{
                  "op" => "record_literal",
                  "fields" => [
                    %{
                      "name" => "timeString",
                      "expr" => %{"op" => "string_literal", "value" => "--:--"}
                    },
                    %{
                      "name" => "screenW",
                      "expr" => %{
                        "op" => "field_access",
                        "arg" => %{
                          "op" => "field_access",
                          "arg" => %{"op" => "var", "name" => "launch"},
                          "field" => "screen"
                        },
                        "field" => "width"
                      }
                    },
                    %{
                      "name" => "screenH",
                      "expr" => %{
                        "op" => "field_access",
                        "arg" => %{
                          "op" => "field_access",
                          "arg" => %{"op" => "var", "name" => "launch"},
                          "field" => "screen"
                        },
                        "field" => "height"
                      }
                    },
                    %{
                      "name" => "isRound",
                      "expr" => %{
                        "op" => "field_access",
                        "arg" => %{
                          "op" => "field_access",
                          "arg" => %{"op" => "var", "name" => "launch"},
                          "field" => "screen"
                        },
                        "field" => "isRound"
                      }
                    }
                  ]
                },
                "right" => %{"kind" => "cmd.none"}
              }
            },
            %{
              "kind" => "function",
              "name" => "view",
              "params" => ["model"],
              "expr" => %{
                "op" => "qualified_call",
                "target" => "Pebble.Ui.windowStack",
                "args" => [
                  %{
                    "op" => "list_literal",
                    "items" => [
                      %{
                        "op" => "qualified_call",
                        "target" => "Pebble.Ui.window",
                        "args" => [
                          %{"op" => "int_literal", "value" => 1},
                          %{
                            "op" => "list_literal",
                            "items" => [
                              %{
                                "op" => "qualified_call",
                                "target" => "Pebble.Ui.canvasLayer",
                                "args" => [
                                  %{"op" => "int_literal", "value" => 1},
                                  %{
                                    "op" => "list_literal",
                                    "items" => [
                                      %{
                                        "op" => "qualified_call",
                                        "target" => "Pebble.Ui.clear",
                                        "args" => [%{"op" => "int_literal", "value" => 255}]
                                      },
                                      %{
                                        "op" => "qualified_call",
                                        "target" => "Pebble.Ui.roundRect",
                                        "args" => [
                                          %{
                                            "op" => "record_literal",
                                            "fields" => [
                                              %{"name" => "x", "expr" => centered_x},
                                              %{
                                                "name" => "y",
                                                "expr" => %{"op" => "int_literal", "value" => 62}
                                              },
                                              %{
                                                "name" => "w",
                                                "expr" => %{"op" => "int_literal", "value" => 100}
                                              },
                                              %{
                                                "name" => "h",
                                                "expr" => %{"op" => "int_literal", "value" => 44}
                                              }
                                            ]
                                          },
                                          %{"op" => "int_literal", "value" => 6},
                                          %{"op" => "int_literal", "value" => 192}
                                        ]
                                      },
                                      %{
                                        "op" => "qualified_call",
                                        "target" => "Pebble.Ui.textLabel",
                                        "args" => [
                                          %{"op" => "int_literal", "value" => 0},
                                          %{
                                            "op" => "record_literal",
                                            "fields" => [
                                              %{
                                                "name" => "x",
                                                "expr" => %{"op" => "int_literal", "value" => 44}
                                              },
                                              %{
                                                "name" => "y",
                                                "expr" => %{"op" => "int_literal", "value" => 90}
                                              }
                                            ]
                                          },
                                          model_time_string
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
                    ]
                  }
                ]
              }
            },
            %{
              "kind" => "function",
              "name" => "update",
              "params" => ["msg", "model"],
              "expr" => %{
                "op" => "case",
                "subject" => %{"op" => "var", "name" => "msg"},
                "branches" => [
                  %{
                    "pattern" => %{
                      "kind" => "constructor",
                      "name" => "CurrentTimeString",
                      "bind" => "value"
                    },
                    "expr" => %{
                      "op" => "tuple2",
                      "left" => %{
                        "op" => "record_update",
                        "base" => %{"op" => "var", "name" => "model"},
                        "fields" => [
                          %{
                            "name" => "timeString",
                            "expr" => %{"op" => "var", "name" => "value"}
                          }
                        ]
                      },
                      "right" => %{"kind" => "cmd.none"}
                    }
                  }
                ]
              }
            }
          ]
        }
      ]
    }

    request = %{
      source_root: "watch",
      rel_path: "watch/src/Main.elm",
      source: "",
      introspect: %{
        "init_model" => %{
          "screenW" => %{"$opaque" => true, "op" => "field_access"},
          "screenH" => %{"$opaque" => true, "op" => "field_access"},
          "isRound" => %{"$opaque" => true, "op" => "field_access"}
        },
        "view_tree" => %{"type" => "root", "children" => []}
      },
      current_model: %{
        "launch_context" => %{
          "screen" => %{"width" => 144, "height" => 168, "isRound" => false}
        }
      },
      current_view_tree: %{},
      elm_executor_core_ir: core_ir
    }

    assert {:ok, result} = SemanticExecutor.execute(request)
    runtime_model = result.model_patch["runtime_model"]

    assert runtime_model["screenW"] == 144
    assert runtime_model["screenH"] == 168
    assert runtime_model["isRound"] == false

    refute Enum.any?(result.view_output, &(&1["kind"] == "unresolved"))

    assert Enum.any?(result.view_output, fn row ->
             row["kind"] == "round_rect" and row["x"] == 22 and row["w"] == 100
           end)

    assert Enum.any?(result.view_output, fn row ->
             row["kind"] == "text_label" and row["text"] == "--:--"
           end)

    updated_request = Map.merge(request, %{message: "CurrentTimeString \"20:33\""})

    assert {:ok, updated} = SemanticExecutor.execute(updated_request)
    updated_model = updated.model_patch["runtime_model"]

    assert updated_model["timeString"] == "20:33"

    assert Enum.any?(updated.view_output, fn row ->
             row["kind"] == "text_label" and row["text"] == "20:33"
           end)
  end

  test "core update applies structured CurrentDateTime payload and preserves model fields" do
    core_ir = %{
      "modules" => [
        %{
          "name" => "Main",
          "declarations" => [
            %{
              "kind" => "function",
              "name" => "update",
              "expr" => %{
                "op" => :case,
                "subject" => %{"op" => :var, "name" => "msg"},
                "branches" => [
                  %{
                    "pattern" => %{
                      "kind" => :constructor,
                      "name" => "CurrentDateTime",
                      "bind" => "value"
                    },
                    "expr" => %{
                      "op" => :tuple2,
                      "left" => %{
                        "op" => :record_literal,
                        "fields" => [
                          %{
                            "name" => "hour",
                            "expr" => %{
                              "op" => :field_access,
                              "arg" => %{"op" => :var, "name" => "value"},
                              "field" => "hour"
                            }
                          },
                          %{
                            "name" => "minute",
                            "expr" => %{
                              "op" => :field_access,
                              "arg" => %{"op" => :var, "name" => "value"},
                              "field" => "minute"
                            }
                          }
                        ]
                      },
                      "right" => %{"op" => :var, "name" => "cmd"}
                    }
                  }
                ]
              }
            }
          ]
        }
      ]
    }

    payload = Jason.encode!(%{"hour" => 16, "minute" => 11})

    request = %{
      source_root: "watch",
      rel_path: "watch/src/Main.elm",
      source: "",
      introspect: %{"view_tree" => %{"type" => "root", "children" => []}},
      current_model: %{
        "runtime_model" => %{"hour" => 12, "minute" => 0, "screenW" => 144, "screenH" => 168}
      },
      current_view_tree: %{},
      message: "CurrentDateTime #{payload}",
      elm_executor_core_ir: core_ir
    }

    assert {:ok, result} = SemanticExecutor.execute(request)
    runtime_model = result.model_patch["runtime_model"]

    assert runtime_model["hour"] == 16
    assert runtime_model["minute"] == 11
    assert runtime_model["screenW"] == 144
    assert runtime_model["screenH"] == 168
  end

  test "companion http introspection does not synthesize fake package callbacks" do
    request = %{
      source_root: "protocol",
      rel_path: "phone/src/CompanionApp.elm",
      source: """
      module CompanionApp exposing (main)

      import Http

      type Msg
          = Tick
          | WeatherReceived (Result Http.Error Float)
      """,
      introspect: %{
        "update_cmd_calls" => [
          %{
            "target" => "Http.get",
            "name" => "get",
            "callback_constructor" => "WeatherReceived"
          }
        ],
        "view_tree" => %{"type" => "root", "children" => []}
      },
      current_model: %{"runtime_model" => %{"lastResponse" => 0}},
      current_view_tree: %{"type" => "root", "children" => []},
      message: "Tick",
      update_branches: ["Tick", "WeatherReceived"]
    }

    assert {:ok, result} = SemanticExecutor.execute(request)
    assert result.runtime["followup_message_count"] == 0
    assert result.followup_messages == []
  end

  test "step result includes normalized runtime view_output contract" do
    request = %{
      source_root: "watch",
      rel_path: "watch/src/Main.elm",
      source: "module Main exposing (main)\n",
      introspect: %{
        "view_tree" => %{
          "type" => "root",
          "children" => [
            %{"type" => "clear", "label" => "0", "children" => []},
            %{
              "type" => "textInt",
              "source" => %{"call" => "Ui.textInt", "path" => "src/Main.elm", "line" => 42},
              "children" => [
                %{"type" => "expr", "value" => 0},
                %{
                  "type" => "record",
                  "children" => [
                    %{
                      "type" => "field",
                      "label" => "x",
                      "children" => [%{"type" => "expr", "value" => 36}]
                    },
                    %{
                      "type" => "field",
                      "label" => "y",
                      "children" => [%{"type" => "expr", "value" => 74}]
                    }
                  ]
                },
                %{"type" => "expr", "label" => "model.hhmm", "op" => "field_access"}
              ]
            }
          ]
        }
      },
      current_model: %{"runtime_model" => %{"hhmm" => 1511}},
      current_view_tree: %{},
      message: "Tick",
      update_branches: ["Tick"]
    }

    assert {:ok, result} = SemanticExecutor.execute(request)
    assert is_list(result.view_output)
    assert result.model_patch["runtime_view_output"] == result.view_output
    assert result.runtime["view_output_count"] == length(result.view_output)

    assert Enum.any?(result.view_output, fn row ->
             row["kind"] == "text_int" and row["text"] == "1511" and
               row["source"] == %{"call" => "Ui.textInt", "path" => "src/Main.elm", "line" => 42}
           end)
  end

  test "step result preserves group style context in runtime view_output" do
    request = %{
      source_root: "watch",
      rel_path: "watch/src/Main.elm",
      source: "module Main exposing (main)\n",
      introspect: %{
        "view_tree" => %{
          "type" => "root",
          "children" => [
            %{
              "type" => "group",
              "style" => %{"text_color" => 0xFF},
              "children" => [
                %{
                  "type" => "text",
                  "font_id" => 1,
                  "x" => 0,
                  "y" => 52,
                  "w" => 180,
                  "h" => 56,
                  "text" => ~c"--:--",
                  "children" => []
                }
              ]
            }
          ]
        }
      },
      current_model: %{"runtime_model" => %{}},
      current_view_tree: %{},
      message: "Tick",
      update_branches: ["Tick"]
    }

    assert {:ok, result} = SemanticExecutor.execute(request)

    assert [
             %{"kind" => "push_context"},
             %{"kind" => "text_color", "color" => 0xFF},
             %{"kind" => "text", "text" => "--:--"},
             %{"kind" => "pop_context"}
           ] = result.view_output

    assert Jason.encode!(result.view_tree) =~ ~s("text":"--:--")
  end

  test "step result includes normalized path draw operations" do
    request = %{
      source_root: "watch",
      rel_path: "watch/src/Main.elm",
      source: "module Main exposing (main)\n",
      introspect: %{
        "view_tree" => %{
          "type" => "root",
          "children" => [
            %{
              "type" => "pathFilled",
              "children" => [
                %{
                  "type" => "List",
                  "children" => [
                    %{
                      "type" => "tuple2",
                      "children" => [
                        %{"type" => "expr", "value" => 0},
                        %{"type" => "expr", "value" => 0}
                      ]
                    },
                    %{
                      "type" => "tuple2",
                      "children" => [
                        %{"type" => "expr", "value" => 10},
                        %{"type" => "expr", "value" => 0}
                      ]
                    },
                    %{
                      "type" => "tuple2",
                      "children" => [
                        %{"type" => "expr", "value" => 10},
                        %{"type" => "expr", "value" => 10}
                      ]
                    }
                  ]
                },
                %{"type" => "expr", "value" => 4},
                %{"type" => "expr", "value" => 6},
                %{"type" => "expr", "value" => 0}
              ]
            }
          ]
        }
      },
      current_model: %{"runtime_model" => %{}},
      current_view_tree: %{},
      message: "Tick",
      update_branches: ["Tick"]
    }

    assert {:ok, result} = SemanticExecutor.execute(request)

    assert Enum.any?(result.view_output, fn row ->
             row["kind"] == "path_filled" and row["offset_x"] == 4 and row["offset_y"] == 6 and
               row["points"] == [[0, 0], [10, 0], [10, 10]]
           end)
  end

  test "parser view_output resolves point-record primitives and named colors" do
    request = %{
      source_root: "watch",
      rel_path: "watch/src/Main.elm",
      source: "module Main exposing (main)\n",
      introspect: %{
        "view_tree" => %{
          "type" => "root",
          "children" => [
            %{
              "type" => "clear",
              "children" => [%{"type" => "white", "children" => []}]
            },
            %{
              "type" => "circle",
              "children" => [
                %{
                  "type" => "record",
                  "children" => [
                    %{
                      "type" => "field",
                      "label" => "x",
                      "children" => [%{"type" => "expr", "value" => 72}]
                    },
                    %{
                      "type" => "field",
                      "label" => "y",
                      "children" => [%{"type" => "expr", "value" => 84}]
                    }
                  ]
                },
                %{"type" => "expr", "value" => 44},
                %{"type" => "black", "children" => []}
              ]
            },
            %{
              "type" => "line",
              "children" => [
                %{
                  "type" => "record",
                  "children" => [
                    %{
                      "type" => "field",
                      "label" => "x",
                      "children" => [%{"type" => "expr", "value" => 72}]
                    },
                    %{
                      "type" => "field",
                      "label" => "y",
                      "children" => [%{"type" => "expr", "value" => 84}]
                    }
                  ]
                },
                %{
                  "type" => "record",
                  "children" => [
                    %{
                      "type" => "field",
                      "label" => "x",
                      "children" => [%{"type" => "expr", "value" => 72}]
                    },
                    %{
                      "type" => "field",
                      "label" => "y",
                      "children" => [%{"type" => "expr", "value" => 40}]
                    }
                  ]
                },
                %{"type" => "black", "children" => []}
              ]
            }
          ]
        }
      },
      current_model: %{"runtime_model" => %{}},
      current_view_tree: %{},
      message: "Tick",
      update_branches: ["Tick"]
    }

    assert {:ok, result} = SemanticExecutor.execute(request)

    assert Enum.any?(result.view_output, fn row ->
             row["kind"] == "clear" and row["color"] == 0xFF
           end)

    assert Enum.any?(result.view_output, fn row ->
             row["kind"] == "circle" and row["cx"] == 72 and row["cy"] == 84 and row["r"] == 44 and
               row["color"] == 0xC0
           end)

    assert Enum.any?(result.view_output, fn row ->
             row["kind"] == "line" and row["x1"] == 72 and row["y1"] == 84 and row["x2"] == 72 and
               row["y2"] == 40 and row["color"] == 0xC0
           end)
  end

  test "parser view_output resolves tuple selector expressions from node children" do
    request = %{
      source_root: "watch",
      rel_path: "watch/src/Main.elm",
      source: "module Main exposing (main)\n",
      introspect: %{
        "view_tree" => %{
          "type" => "root",
          "children" => [
            %{
              "type" => "line",
              "children" => [
                %{
                  "type" => "record",
                  "children" => [
                    %{
                      "type" => "field",
                      "label" => "x",
                      "children" => [%{"type" => "expr", "value" => 0}]
                    },
                    %{
                      "type" => "field",
                      "label" => "y",
                      "children" => [%{"type" => "expr", "value" => 0}]
                    }
                  ]
                },
                %{
                  "type" => "record",
                  "children" => [
                    %{
                      "type" => "field",
                      "label" => "x",
                      "children" => [
                        %{
                          "type" => "expr",
                          "op" => "tuple_first_expr",
                          "children" => [
                            %{"type" => "var", "label" => "hourTuple", "op" => "var"}
                          ]
                        }
                      ]
                    },
                    %{
                      "type" => "field",
                      "label" => "y",
                      "children" => [
                        %{
                          "type" => "expr",
                          "op" => "tuple_second_expr",
                          "children" => [
                            %{"type" => "var", "label" => "hourTuple", "op" => "var"}
                          ]
                        }
                      ]
                    }
                  ]
                },
                %{"type" => "black", "children" => []}
              ]
            }
          ]
        }
      },
      current_model: %{"runtime_model" => %{"hourTuple" => [12, 34]}},
      current_view_tree: %{},
      message: "Tick",
      update_branches: ["Tick"]
    }

    assert {:ok, result} = SemanticExecutor.execute(request)

    assert Enum.any?(result.view_output, fn row ->
             row["kind"] == "line" and row["x1"] == 0 and row["y1"] == 0 and row["x2"] == 12 and
               row["y2"] == 34 and row["color"] == 0xC0
           end)
  end

  test "view_output includes bitmap, rotated bitmap, and font text primitives" do
    request = %{
      source_root: "watch",
      rel_path: "watch/src/Main.elm",
      source: "module Main exposing (main)\n",
      introspect: %{
        "view_tree" => %{
          "type" => "root",
          "children" => [
            %{
              "type" => "bitmapInRect",
              "children" => [
                %{"type" => "expr", "value" => 2},
                %{"type" => "expr", "value" => 4},
                %{"type" => "expr", "value" => 6},
                %{"type" => "expr", "value" => 20},
                %{"type" => "expr", "value" => 16}
              ]
            },
            %{
              "type" => "rotatedBitmap",
              "children" => [
                %{"type" => "expr", "value" => 2},
                %{"type" => "expr", "value" => 20},
                %{"type" => "expr", "value" => 16},
                %{"type" => "expr", "value" => 45000},
                %{"type" => "expr", "value" => 10},
                %{"type" => "expr", "value" => 8}
              ]
            },
            %{
              "type" => "textLabel",
              "children" => [
                %{"type" => "expr", "value" => 1},
                %{
                  "type" => "record",
                  "children" => [
                    %{
                      "type" => "field",
                      "label" => "x",
                      "children" => [%{"type" => "expr", "value" => 10}]
                    },
                    %{
                      "type" => "field",
                      "label" => "y",
                      "children" => [%{"type" => "expr", "value" => 24}]
                    }
                  ]
                },
                %{"type" => "expr", "value" => "HELLO"}
              ]
            }
          ]
        }
      },
      current_model: %{"runtime_model" => %{}},
      current_view_tree: %{},
      message: "Tick",
      update_branches: ["Tick"]
    }

    assert {:ok, result} = SemanticExecutor.execute(request)

    assert Enum.any?(result.view_output, fn row ->
             row["kind"] == "bitmap_in_rect" and row["bitmap_id"] == 2 and row["w"] == 20 and
               row["h"] == 16
           end)

    assert Enum.any?(result.view_output, fn row ->
             row["kind"] == "rotated_bitmap" and row["bitmap_id"] == 2 and row["src_w"] == 20 and
               row["src_h"] == 16
           end)

    assert Enum.any?(result.view_output, fn row ->
             row["kind"] == "text_label" and row["font_id"] == 1 and row["x"] == 10 and
               row["y"] == 24 and
               row["text"] == "HELLO"
           end)
  end

  test "runtime view_tree is evaluated from core_ir view function when available" do
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
                "op" => :record_literal,
                "fields" => %{
                  "type" => %{"op" => :string_literal, "value" => "root"},
                  "children" => %{
                    "op" => :list_literal,
                    "items" => [
                      %{
                        "op" => :record_literal,
                        "fields" => %{
                          "type" => %{"op" => :string_literal, "value" => "clear"},
                          "label" => %{"op" => :string_literal, "value" => "0"},
                          "children" => %{"op" => :list_literal, "items" => []}
                        }
                      },
                      %{
                        "op" => :record_literal,
                        "fields" => %{
                          "type" => %{"op" => :string_literal, "value" => "textIntWithFont"},
                          "children" => %{
                            "op" => :list_literal,
                            "items" => [
                              %{
                                "op" => :record_literal,
                                "fields" => %{
                                  "type" => %{"op" => :string_literal, "value" => "expr"},
                                  "value" => %{"op" => :int_literal, "value" => 0},
                                  "children" => %{"op" => :list_literal, "items" => []}
                                }
                              },
                              %{
                                "op" => :record_literal,
                                "fields" => %{
                                  "type" => %{"op" => :string_literal, "value" => "expr"},
                                  "value" => %{"op" => :int_literal, "value" => 10},
                                  "children" => %{"op" => :list_literal, "items" => []}
                                }
                              },
                              %{
                                "op" => :record_literal,
                                "fields" => %{
                                  "type" => %{"op" => :string_literal, "value" => "expr"},
                                  "value" => %{"op" => :int_literal, "value" => 20},
                                  "children" => %{"op" => :list_literal, "items" => []}
                                }
                              },
                              %{
                                "op" => :record_literal,
                                "fields" => %{
                                  "type" => %{"op" => :string_literal, "value" => "expr"},
                                  "label" => %{"op" => :string_literal, "value" => "model.hhmm"},
                                  "op" => %{"op" => :string_literal, "value" => "field_access"},
                                  "children" => %{"op" => :list_literal, "items" => []}
                                }
                              }
                            ]
                          }
                        }
                      }
                    ]
                  }
                }
              }
            }
          ]
        }
      ]
    }

    request = %{
      source_root: "watch",
      rel_path: "watch/src/Main.elm",
      source: "",
      introspect: %{"view_tree" => %{"type" => "root", "children" => []}},
      current_model: %{"runtime_model" => %{"hhmm" => 1511}},
      current_view_tree: %{},
      message: "Tick",
      update_branches: ["Tick"],
      elm_executor_core_ir: core_ir
    }

    assert {:ok, result} = SemanticExecutor.execute(request)
    assert result.view_tree["type"] == "root"
    assert result.runtime["view_tree_source"] == "step_derived_view_tree"

    assert Enum.any?(result.view_output, fn row ->
             row["kind"] == "clear" and row["color"] == 0
           end)
  end

  test "engine emits centered runtime view_output for let-based Pebble.Ui layout" do
    model_screen_w = %{
      "op" => :field_access,
      "arg" => %{"op" => :var, "name" => "model"},
      "field" => "screenW"
    }

    model_screen_h = %{
      "op" => :field_access,
      "arg" => %{"op" => :var, "name" => "model"},
      "field" => "screenH"
    }

    model_hhmm = %{
      "op" => :field_access,
      "arg" => %{"op" => :var, "name" => "model"},
      "field" => "hhmm"
    }

    card_w = %{
      "op" => :call,
      "name" => "__idiv__",
      "args" => [
        %{
          "op" => :call,
          "name" => "__mul__",
          "args" => [model_screen_w, %{"op" => :int_literal, "value" => 7}]
        },
        %{"op" => :int_literal, "value" => 10}
      ]
    }

    card_h = %{
      "op" => :call,
      "name" => "max",
      "args" => [
        %{"op" => :int_literal, "value" => 44},
        %{
          "op" => :call,
          "name" => "__idiv__",
          "args" => [
            %{
              "op" => :call,
              "name" => "__mul__",
              "args" => [model_screen_h, %{"op" => :int_literal, "value" => 56}]
            },
            %{"op" => :int_literal, "value" => 168}
          ]
        }
      ]
    }

    card_x = %{
      "op" => :call,
      "name" => "__idiv__",
      "args" => [
        %{
          "op" => :call,
          "name" => "__sub__",
          "args" => [model_screen_w, %{"op" => :var, "name" => "cardW"}]
        },
        %{"op" => :int_literal, "value" => 2}
      ]
    }

    card_y = %{
      "op" => :call,
      "name" => "__idiv__",
      "args" => [
        %{
          "op" => :call,
          "name" => "__sub__",
          "args" => [model_screen_h, %{"op" => :var, "name" => "cardH"}]
        },
        %{"op" => :int_literal, "value" => 2}
      ]
    }

    view_expr =
      %{
        "op" => :let_in,
        "name" => "cardW",
        "value_expr" => card_w,
        "in_expr" => %{
          "op" => :let_in,
          "name" => "cardH",
          "value_expr" => card_h,
          "in_expr" => %{
            "op" => :let_in,
            "name" => "cardX",
            "value_expr" => card_x,
            "in_expr" => %{
              "op" => :let_in,
              "name" => "cardY",
              "value_expr" => card_y,
              "in_expr" => %{
                "op" => :qualified_call,
                "target" => "Pebble.Ui.windowStack",
                "args" => [
                  %{
                    "op" => :list_literal,
                    "items" => [
                      %{
                        "op" => :qualified_call,
                        "target" => "Pebble.Ui.window",
                        "args" => [
                          %{"op" => :int_literal, "value" => 1},
                          %{
                            "op" => :list_literal,
                            "items" => [
                              %{
                                "op" => :qualified_call,
                                "target" => "Pebble.Ui.canvasLayer",
                                "args" => [
                                  %{"op" => :int_literal, "value" => 1},
                                  %{
                                    "op" => :list_literal,
                                    "items" => [
                                      %{
                                        "op" => :qualified_call,
                                        "target" => "Pebble.Ui.clear",
                                        "args" => [%{"op" => :int_literal, "value" => 0}]
                                      },
                                      %{
                                        "op" => :qualified_call,
                                        "target" => "Pebble.Ui.roundRect",
                                        "args" => [
                                          %{"op" => :var, "name" => "cardX"},
                                          %{"op" => :var, "name" => "cardY"},
                                          %{"op" => :var, "name" => "cardW"},
                                          %{"op" => :var, "name" => "cardH"},
                                          %{"op" => :int_literal, "value" => 6},
                                          %{"op" => :int_literal, "value" => 1}
                                        ]
                                      },
                                      %{
                                        "op" => :qualified_call,
                                        "target" => "Pebble.Ui.fillRect",
                                        "args" => [
                                          %{
                                            "op" => :record_literal,
                                            "fields" => [
                                              %{
                                                "name" => "x",
                                                "expr" => %{
                                                  "op" => :add_const,
                                                  "var" => "cardX",
                                                  "value" => 2
                                                }
                                              },
                                              %{
                                                "name" => "y",
                                                "expr" => %{
                                                  "op" => :add_const,
                                                  "var" => "cardY",
                                                  "value" => 2
                                                }
                                              },
                                              %{
                                                "name" => "w",
                                                "expr" => %{
                                                  "op" => :sub_const,
                                                  "var" => "cardW",
                                                  "value" => 4
                                                }
                                              },
                                              %{
                                                "name" => "h",
                                                "expr" => %{"op" => :int_literal, "value" => 4}
                                              }
                                            ]
                                          },
                                          %{"op" => :int_literal, "value" => 204}
                                        ]
                                      },
                                      %{
                                        "op" => :qualified_call,
                                        "target" => "Pebble.Ui.textInt",
                                        "args" => [
                                          %{"op" => :int_literal, "value" => 0},
                                          %{
                                            "op" => :record_literal,
                                            "fields" => [
                                              %{
                                                "name" => "x",
                                                "expr" => %{"op" => :var, "name" => "cardX"}
                                              },
                                              %{
                                                "name" => "y",
                                                "expr" => %{"op" => :var, "name" => "cardY"}
                                              }
                                            ]
                                          },
                                          model_hhmm
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
                    ]
                  }
                ]
              }
            }
          }
        }
      }

    core_ir = %{
      "modules" => [
        %{
          "name" => "Main",
          "declarations" => [
            %{"kind" => "function", "name" => "view", "args" => ["model"], "expr" => view_expr}
          ]
        }
      ]
    }

    request = %{
      source_root: "watch",
      rel_path: "watch/src/Main.elm",
      source: "",
      introspect: %{"view_tree" => %{"type" => "root", "children" => []}},
      current_model: %{"runtime_model" => %{"screenW" => 144, "screenH" => 168, "hhmm" => 1626}},
      current_view_tree: %{},
      message: "Tick",
      update_branches: ["Tick"],
      elm_executor_core_ir: core_ir
    }

    assert {:ok, result} = SemanticExecutor.execute(request)
    assert is_list(result.view_output)
    assert result.runtime["view_output_count"] == length(result.view_output)

    assert Enum.any?(result.view_output, fn row ->
             row["kind"] == "round_rect" and row["x"] == 22 and row["w"] == 100
           end)

    assert Enum.any?(result.view_output, fn row ->
             row["kind"] == "fill_rect" and row["x"] == 24 and row["y"] == 58 and row["w"] == 96
           end)

    assert Enum.any?(result.view_output, fn row ->
             row["kind"] == "text_int" and row["text"] == "1626"
           end)
  end

  test "engine resolves PebbleUi.toUiNode alias output before deriving preview ops" do
    text_op = %{
      "op" => :qualified_call,
      "target" => "PebbleUi.text",
      "args" => [
        %{"op" => :int_literal, "value" => 1},
        %{
          "op" => :record_literal,
          "fields" => [
            %{"name" => "x", "expr" => %{"op" => :int_literal, "value" => 0}},
            %{"name" => "y", "expr" => %{"op" => :int_literal, "value" => 46}},
            %{"name" => "w", "expr" => %{"op" => :int_literal, "value" => 144}},
            %{"name" => "h", "expr" => %{"op" => :int_literal, "value" => 56}}
          ]
        },
        %{"op" => :field_access, "arg" => %{"op" => :var, "name" => "model"}, "field" => "time"}
      ]
    }

    to_ui_node_body = %{
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
              "expr" => to_ui_node_body
            }
          ]
        },
        %{
          "name" => "Main",
          "declarations" => [
            %{
              "kind" => "function",
              "name" => "view",
              "args" => ["model"],
              "expr" => %{
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
                          %{
                            "op" => :qualified_call,
                            "target" => "PebbleColor.black",
                            "args" => []
                          }
                        ]
                      },
                      %{
                        "op" => :qualified_call,
                        "target" => "PebbleUi.group",
                        "args" => [
                          %{
                            "op" => :qualified_call,
                            "target" => "PebbleUi.context",
                            "args" => [[], %{"op" => :list_literal, "items" => [text_op]}]
                          }
                        ]
                      }
                    ]
                  }
                ]
              }
            }
          ]
        }
      ]
    }

    request = %{
      source_root: "watch",
      rel_path: "watch/src/Main.elm",
      source: "",
      introspect: %{"view_tree" => %{"type" => "root", "children" => []}},
      current_model: %{"runtime_model" => %{"time" => "08:41"}},
      current_view_tree: %{},
      message: "Tick",
      update_branches: ["Tick"],
      elm_executor_core_ir: core_ir
    }

    assert {:ok, result} = SemanticExecutor.execute(request)
    assert result.view_tree["type"] == "windowStack"

    assert Enum.any?(result.view_output, fn row ->
             row["kind"] == "clear" and row["color"] == 0xC0
           end)

    assert Enum.any?(result.view_output, fn row ->
             row["kind"] == "text" and row["text"] == "08:41" and row["x"] == 0 and
               row["y"] == 46
           end)

    assert %{"type" => "window", "children" => [%{"children" => layer_children}]} =
             Enum.find(result.view_tree["children"], &(&1["type"] == "window"))

    assert [%{"type" => "clear"}, %{"children" => [%{"text" => "08:41"}]}] =
             layer_children
  end

  test "engine resolves user transform output before deriving preview ops" do
    wrap_ops_body = %{
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
          "name" => "Main",
          "declarations" => [
            %{
              "kind" => "function",
              "name" => "wrapOps",
              "args" => ["ops"],
              "expr" => wrap_ops_body
            },
            %{
              "kind" => "function",
              "name" => "view",
              "args" => ["model"],
              "expr" => %{
                "op" => :qualified_call,
                "target" => "Main.wrapOps",
                "args" => [
                  %{
                    "op" => :list_literal,
                    "items" => [
                      %{
                        "op" => :qualified_call,
                        "target" => "PebbleUi.clear",
                        "args" => [
                          %{
                            "op" => :qualified_call,
                            "target" => "PebbleColor.black",
                            "args" => []
                          }
                        ]
                      }
                    ]
                  }
                ]
              }
            }
          ]
        }
      ]
    }

    request = %{
      source_root: "watch",
      rel_path: "watch/src/Main.elm",
      source: "",
      introspect: %{
        "view_tree" => %{
          "type" => "wrapOps",
          "qualified_target" => "Main.wrapOps",
          "children" => []
        }
      },
      current_model: %{"runtime_model" => %{}},
      current_view_tree: %{},
      message: "Tick",
      update_branches: ["Tick"],
      elm_executor_core_ir: core_ir
    }

    assert {:ok, result} = SemanticExecutor.execute(request)
    assert result.view_tree["type"] == "windowStack"

    assert Enum.any?(result.view_output, fn row ->
             row["kind"] == "clear" and row["color"] == 0xC0
           end)
  end

  test "engine normalizes lowered Pebble Ui constructor tuples after transforms" do
    canvas_layer_expr = %{
      "op" => :tuple2,
      "left" => %{"op" => :int_literal, "value" => 1},
      "right" => %{
        "op" => :tuple2,
        "left" => %{"op" => :int_literal, "value" => 1},
        "right" => %{"op" => :var, "name" => "ops"}
      }
    }

    window_expr = %{
      "op" => :tuple2,
      "left" => %{"op" => :int_literal, "value" => 1},
      "right" => %{
        "op" => :tuple2,
        "left" => %{"op" => :int_literal, "value" => 1},
        "right" => %{"op" => :list_literal, "items" => [canvas_layer_expr]}
      }
    }

    wrap_ops_body = %{
      "op" => :tuple2,
      "left" => %{"op" => :int_literal, "value" => 1},
      "right" => %{"op" => :list_literal, "items" => [window_expr]}
    }

    core_ir = %{
      "modules" => [
        %{
          "name" => "Main",
          "declarations" => [
            %{
              "kind" => "function",
              "name" => "wrapOps",
              "args" => ["ops"],
              "expr" => wrap_ops_body
            },
            %{
              "kind" => "function",
              "name" => "view",
              "args" => ["model"],
              "expr" => %{
                "op" => :qualified_call,
                "target" => "Main.wrapOps",
                "args" => [
                  %{
                    "op" => :list_literal,
                    "items" => [
                      %{
                        "op" => :qualified_call,
                        "target" => "PebbleUi.clear",
                        "args" => [
                          %{
                            "op" => :qualified_call,
                            "target" => "PebbleColor.black",
                            "args" => []
                          }
                        ]
                      }
                    ]
                  }
                ]
              }
            }
          ]
        }
      ]
    }

    request = %{
      source_root: "watch",
      rel_path: "watch/src/Main.elm",
      source: "",
      introspect: %{"view_tree" => %{"type" => "root", "children" => []}},
      current_model: %{"runtime_model" => %{}},
      current_view_tree: %{},
      message: "Tick",
      update_branches: ["Tick"],
      elm_executor_core_ir: core_ir
    }

    assert {:ok, result} = SemanticExecutor.execute(request)
    assert result.view_tree["type"] == "windowStack"

    assert Enum.any?(result.view_tree["children"], fn child ->
             child["type"] == "window" and child["id"] == 1
           end)

    assert Enum.any?(result.view_output, fn row ->
             row["kind"] == "clear" and row["color"] == 0xC0
           end)
  end

  test "view_output includes arc primitive rows from runtime tree" do
    request = %{
      source_root: "watch",
      rel_path: "watch/src/Main.elm",
      source: "",
      introspect: %{
        "view_tree" => %{
          "type" => "root",
          "children" => [
            %{
              "type" => "arc",
              "children" => [
                %{"type" => "expr", "value" => 20},
                %{"type" => "expr", "value" => 16},
                %{"type" => "expr", "value" => 36},
                %{"type" => "expr", "value" => 36},
                %{"type" => "expr", "value" => 0},
                %{"type" => "expr", "value" => 45_000}
              ]
            }
          ]
        }
      },
      current_model: %{"runtime_model" => %{}},
      current_view_tree: %{},
      message: nil,
      update_branches: []
    }

    assert {:ok, result} = SemanticExecutor.execute(request)

    assert Enum.any?(result.view_output, fn row ->
             row["kind"] == "arc" and row["w"] == 36 and row["end_angle"] == 45_000
           end)
  end

  test "strict operation matrix: semantic hints mutate, unmapped messages do not" do
    core_ir = %{
      modules: [
        %{
          "name" => "Main",
          "declarations" => [
            %{
              "kind" => "function",
              "name" => "update",
              "expr" => %{
                "op" => :case,
                "subject" => %{"op" => :var, "name" => "msg"},
                "branches" => [
                  %{
                    "pattern" => %{
                      "kind" => :constructor,
                      "name" => "SetCount",
                      "args" => [%{"kind" => :var, "name" => "value"}]
                    },
                    "expr" => %{
                      "op" => :tuple2,
                      "left" => %{
                        "op" => :record_literal,
                        "fields" => %{"count" => %{"op" => :var, "name" => "value"}}
                      },
                      "right" => %{"op" => :var, "name" => "cmd"}
                    }
                  },
                  %{
                    "pattern" => %{
                      "kind" => :constructor,
                      "name" => "SetEnabled",
                      "args" => [%{"kind" => :var, "name" => "value"}]
                    },
                    "expr" => %{
                      "op" => :tuple2,
                      "left" => %{
                        "op" => :record_literal,
                        "fields" => %{"enabled" => %{"op" => :var, "name" => "value"}}
                      },
                      "right" => %{"op" => :var, "name" => "cmd"}
                    }
                  },
                  %{
                    "pattern" => %{
                      "kind" => :constructor,
                      "name" => "SetTitle",
                      "args" => [%{"kind" => :var, "name" => "value"}]
                    },
                    "expr" => %{
                      "op" => :tuple2,
                      "left" => %{
                        "op" => :record_literal,
                        "fields" => %{"title" => %{"op" => :var, "name" => "value"}}
                      },
                      "right" => %{"op" => :var, "name" => "cmd"}
                    }
                  },
                  %{
                    "pattern" => %{
                      "kind" => :constructor,
                      "name" => "SetIgnored",
                      "args" => [%{"kind" => :wildcard}]
                    },
                    "expr" => %{"op" => :var, "name" => "model"}
                  }
                ]
              }
            }
          ]
        }
      ]
    }

    base_request = %{
      source_root: "watch",
      rel_path: "watch/src/Main.elm",
      source: "",
      introspect: %{"view_tree" => %{"type" => "root", "children" => []}},
      current_view_tree: %{"type" => "root", "children" => []},
      update_branches: [],
      elm_executor_core_ir: core_ir
    }

    assert {:ok, count_result} =
             SemanticExecutor.execute(
               Map.merge(base_request, %{
                 current_model: %{
                   "runtime_model" => %{"count" => 1, "enabled" => true, "title" => "--"}
                 },
                 message: "SetCount 42"
               })
             )

    assert count_result.model_patch["runtime_model"]["count"] == 42
    assert count_result.model_patch["runtime_model"]["enabled"] == true
    assert count_result.model_patch["runtime_model"]["title"] == "--"
    assert count_result.runtime["operation_source"] == "core_ir_update_eval"

    assert {:ok, bool_result} =
             SemanticExecutor.execute(
               Map.merge(base_request, %{
                 current_model: %{
                   "runtime_model" => %{"count" => 42, "enabled" => true, "title" => "--"}
                 },
                 message: "SetEnabled false"
               })
             )

    assert bool_result.model_patch["runtime_model"]["enabled"] == false
    assert bool_result.model_patch["runtime_model"]["count"] == 42
    assert bool_result.model_patch["runtime_model"]["title"] == "--"

    assert {:ok, string_result} =
             SemanticExecutor.execute(
               Map.merge(base_request, %{
                 current_model: %{
                   "runtime_model" => %{"count" => 42, "enabled" => false, "title" => "--"}
                 },
                 message: "SetTitle \"HELLO\""
               })
             )

    assert string_result.model_patch["runtime_model"]["title"] == "HELLO"
    assert string_result.model_patch["runtime_model"]["count"] == 42
    assert string_result.model_patch["runtime_model"]["enabled"] == false

    assert {:ok, wildcard_result} =
             SemanticExecutor.execute(
               Map.merge(base_request, %{
                 current_model: %{
                   "runtime_model" => %{"count" => 42, "enabled" => false, "title" => "HELLO"}
                 },
                 message: "SetIgnored 99"
               })
             )

    assert wildcard_result.model_patch["runtime_model"]["count"] == 42
    assert wildcard_result.model_patch["runtime_model"]["enabled"] == false
    assert wildcard_result.model_patch["runtime_model"]["title"] == "HELLO"

    assert {:ok, unmapped_result} =
             SemanticExecutor.execute(
               Map.merge(base_request, %{
                 current_model: %{
                   "runtime_model" => %{"count" => 42, "enabled" => false, "title" => "HELLO"}
                 },
                 message: "Ping"
               })
             )

    assert unmapped_result.runtime["operation_source"] == "unmapped_message"
    assert unmapped_result.runtime["heuristic_fallback_used"] == false
    assert unmapped_result.model_patch["runtime_model"]["count"] == 42
    assert unmapped_result.model_patch["runtime_model"]["enabled"] == false
    assert unmapped_result.model_patch["runtime_model"]["title"] == "HELLO"
  end

  test "constructor disambiguation updates only the targeted numeric key" do
    core_ir = %{
      modules: [
        %{
          "name" => "Main",
          "declarations" => [
            %{
              "kind" => "function",
              "name" => "update",
              "expr" => %{
                "op" => :case,
                "subject" => %{"op" => :var, "name" => "msg"},
                "branches" => [
                  %{
                    "pattern" => %{
                      "kind" => :constructor,
                      "name" => "SetCount",
                      "args" => [%{"kind" => :var, "name" => "value"}]
                    },
                    "expr" => %{
                      "op" => :tuple2,
                      "left" => %{
                        "op" => :record_literal,
                        "fields" => %{"count" => %{"op" => :var, "name" => "value"}}
                      },
                      "right" => %{"op" => :var, "name" => "cmd"}
                    }
                  },
                  %{
                    "pattern" => %{
                      "kind" => :constructor,
                      "name" => "SetTotal",
                      "args" => [%{"kind" => :var, "name" => "value"}]
                    },
                    "expr" => %{
                      "op" => :tuple2,
                      "left" => %{
                        "op" => :record_literal,
                        "fields" => %{"total" => %{"op" => :var, "name" => "value"}}
                      },
                      "right" => %{"op" => :var, "name" => "cmd"}
                    }
                  }
                ]
              }
            }
          ]
        }
      ]
    }

    request = %{
      source_root: "watch",
      rel_path: "watch/src/Main.elm",
      source: "",
      introspect: %{"view_tree" => %{"type" => "root", "children" => []}},
      current_model: %{"runtime_model" => %{"count" => 5, "total" => 20}},
      current_view_tree: %{"type" => "root", "children" => []},
      message: "SetTotal 77",
      update_branches: [],
      elm_executor_core_ir: core_ir
    }

    assert {:ok, result} = SemanticExecutor.execute(request)
    assert result.runtime["operation_source"] == "core_ir_update_eval"
    assert result.model_patch["runtime_model"]["count"] == 5
    assert result.model_patch["runtime_model"]["total"] == 77
  end

  test "followup callback rows are skipped when callback equals current constructor" do
    request = %{
      source_root: "protocol",
      rel_path: "phone/src/CompanionApp.elm",
      source: "module CompanionApp exposing (main)\n",
      introspect: %{
        "update_cmd_calls" => [
          %{
            "target" => "Companion.Http.send",
            "name" => "send",
            "callback_constructor" => "Tick"
          }
        ],
        "view_tree" => %{"type" => "root", "children" => []}
      },
      current_model: %{"runtime_model" => %{"lastResponse" => 0}},
      current_view_tree: %{"type" => "root", "children" => []},
      message: "Tick",
      update_branches: ["Tick"]
    }

    assert {:ok, result} = SemanticExecutor.execute(request)
    assert result.runtime["followup_message_count"] == 0
    assert result.followup_messages == []
  end

  test "runtime marks unmapped operation provenance when no semantic hints are available" do
    request = %{
      source_root: "watch",
      rel_path: "watch/src/Main.elm",
      source: "",
      introspect: %{"view_tree" => %{"type" => "root", "children" => []}},
      current_model: %{"runtime_model" => %{"count" => 1}},
      current_view_tree: %{"type" => "root", "children" => []},
      message: "Ping",
      update_branches: []
    }

    assert {:ok, result} = SemanticExecutor.execute(request)
    assert result.runtime["operation_source"] == "unmapped_message"
    assert result.runtime["heuristic_fallback_used"] == false
    assert result.model_patch["runtime_model"]["step_counter"] == 1
  end

  test "step execution does not synthesize protocol events" do
    request = %{
      source_root: "companion",
      rel_path: "companion/src/Main.elm",
      source: "",
      introspect: %{"view_tree" => %{"type" => "root", "children" => []}},
      current_model: %{"runtime_model" => %{"count" => 1}},
      current_view_tree: %{"type" => "root", "children" => []},
      message: "Inc",
      update_branches: ["Inc"]
    }

    assert {:ok, result} = SemanticExecutor.execute(request)
    assert result.protocol_events == []
  end

  defp core_ir_from_sources(sources) when is_list(sources) do
    modules =
      Enum.map(sources, fn {path, source} ->
        assert {:ok, module} = ElmEx.Frontend.GeneratedParser.parse_source(path, source)
        module
      end)

    project = %ElmEx.Frontend.Project{
      project_dir: Path.expand("watch/src"),
      elm_json: %{},
      modules: modules,
      diagnostics: []
    }

    assert {:ok, ir} = ElmEx.IR.Lowerer.lower_project(project)
    assert {:ok, core_ir} = ElmEx.CoreIR.from_ir(ir)
    core_ir
  end

  defp record_alias(name, fields, field_types)
       when is_binary(name) and is_list(fields) and is_map(field_types) do
    %{
      "kind" => "type_alias",
      "name" => name,
      "expr" => %{
        "op" => "record_alias",
        "fields" => fields,
        "field_types" => field_types
      }
    }
  end
end
