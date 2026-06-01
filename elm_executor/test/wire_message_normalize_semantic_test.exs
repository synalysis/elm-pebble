defmodule ElmExecutor.Runtime.WireMessageNormalizeSemanticTest do
  use ExUnit.Case, async: true

  alias ElmExecutor.Runtime.CoreIREvaluator
  alias ElmExecutor.Runtime.SemanticExecutor

  test "GotConnectivity Online wire step updates online via normalized tagged message" do
    core_ir = %{
      "modules" => [
        %{
          "name" => "CompanionApp",
          "unions" => %{
            "Msg" => %{
              "tags" => %{"GotConnectivity" => 4},
              "payload_specs" => %{"GotConnectivity" => "Connectivity.Connectivity"}
            },
            "Connectivity" => %{
              "tags" => %{"Online" => 1, "Offline" => 2},
              "payload_specs" => %{}
            }
          },
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
                      "name" => "GotConnectivity",
                      "bind" => "connectivity"
                    },
                    "expr" => %{
                      "op" => :tuple2,
                      "left" => %{
                        "op" => :record_update,
                        "base" => %{"op" => :var, "name" => "model"},
                        "fields" => [
                          %{
                            "name" => "online",
                            "expr" => %{
                              "op" => :call,
                              "name" => "__eq__",
                              "args" => [
                                %{"op" => :var, "name" => "connectivity"},
                                %{
                                  "op" => :constructor_call,
                                  "target" => "Connectivity.Online",
                                  "args" => []
                                }
                              ]
                            }
                          }
                        ]
                      },
                      "right" => %{"op" => :int_literal, "value" => 0}
                    }
                  }
                ]
              }
            }
          ]
        }
      ]
    }

    ctx = CoreIREvaluator.build_eval_context(core_ir, "CompanionApp")

    message_value =
      CoreIREvaluator.normalize_wire_message_value(
        %{
          "ctor" => "GotConnectivity",
          "args" => [%{"ctor" => "Online", "args" => []}]
        },
        ctx
      )

    assert message_value == {4, 1}

    request = %{
      source_root: "phone",
      rel_path: "src/CompanionApp.elm",
      source: "module CompanionApp exposing (..)",
      introspect: %{"view_tree" => %{"type" => "root", "children" => []}},
      current_model: %{"runtime_model" => %{"online" => false}},
      current_view_tree: %{"type" => "root", "children" => []},
      message: "GotConnectivity",
      message_value: %{
        "ctor" => "GotConnectivity",
        "args" => [%{"ctor" => "Online", "args" => []}]
      },
      elm_executor_core_ir: core_ir,
      elm_executor_metadata: %{"entry_module" => "CompanionApp"}
    }

    assert {:ok, result} = SemanticExecutor.execute(request)
    assert result.model_patch["runtime_model"]["online"] == true
    assert result.runtime["operation_source"] == "core_ir_update_eval"
  end
end
