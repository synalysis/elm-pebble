defmodule Ide.Debugger.PreviewIntegrationTest do
  @moduledoc false
  use Ide.DebuggerIntegrationCase, async: false

  alias Ide.DebuggerIntegrationExecutors.AccelRuntimeExecutor
  alias Ide.DebuggerIntegrationExecutors.AliveGuardFrameExecutor
  alias Ide.DebuggerIntegrationExecutors.DebuggerRuntimeExecutor
  alias Ide.DebuggerIntegrationExecutors.FailingExternalRuntimeExecutor
  alias Ide.DebuggerIntegrationExecutors.FrameRuntimeExecutor
  alias Ide.DebuggerIntegrationExecutors.HttpFollowupRuntimeExecutor
  alias Ide.DebuggerIntegrationExecutors.InitNoFollowupRuntimeExecutor
  alias Ide.DebuggerIntegrationExecutors.InitRandomFollowupRuntimeExecutor
  alias Ide.DebuggerIntegrationExecutors.MaybeShapeRuntimeExecutor
  alias Ide.DebuggerIntegrationExecutors.NilMaybeRuntimeExecutor
  alias Ide.DebuggerIntegrationExecutors.StorageFollowupRuntimeExecutor
  alias Ide.DebuggerIntegrationExecutors.TupleMaybeRuntimeExecutor

  test "render_runtime_preview_for_debugger derives view output from surface model only" do
    surface_runtime = %{
      model: %{
        "runtime_model" => %{
          "timeString" => "08:54",
          "screenW" => 144,
          "screenH" => 168
        },
        "runtime_view_output" => [
          %{"kind" => "text", "text" => "08:53", "x" => 0, "y" => 0}
        ],
        "elm_introspect" => %{
          "view_tree" => %{
            "type" => "windowStack",
            "children" => [
              %{
                "type" => "text",
                "font_id" => 0,
                "x" => 0,
                "y" => 0,
                "w" => 144,
                "h" => 20,
                "text_align" => 0,
                "text_overflow" => 0,
                "children" => [
                  %{
                    "type" => "expr",
                    "op" => "field_access",
                    "label" => "model.timeString"
                  }
                ]
              }
            ]
          }
        }
      },
      view_tree: %{"type" => "windowStack", "children" => []}
    }

    rendered = Debugger.render_runtime_preview_for_debugger(surface_runtime, %{}, :watch)

    texts =
      for row <- get_in(rendered, [:model, "runtime_view_output"]) || [],
          is_map(row),
          row["kind"] in ["text", "text_label"],
          is_binary(row["text"]),
          do: row["text"]

    assert Enum.any?(texts, &(&1 == "08:54")),
           "expected view derived from model fields, got #{inspect(texts)}"
  end


  test "reload applies init current time string response to runtime model and rendered preview" do
    slug = "sim-init-current-time-string-#{System.unique_integer([:positive])}"

    source =
      File.read!(Path.join(["priv", "project_templates", "watchface_digital", "src", "Main.elm"]))

    {:ok, _} = Debugger.start_session(slug)

    {:ok, reloaded} =
      Debugger.reload(slug, %{
        rel_path: "watch/src/Main.elm",
        source: source,
        reason: "init_current_time_string",
        source_root: "watch"
      })

    preview = get_in(reloaded, [:watch, :model, "debugger_device_current_time_string"]) || %{}
    runtime_model = get_in(reloaded, [:watch, :model, "runtime_model"]) || %{}

    assert is_binary(preview["string"])
    assert runtime_model["timeString"] == preview["string"]
    assert runtime_model["screenW"] == 144
    assert runtime_model["screenH"] == 168
    assert runtime_model["displayShape"] == %{"ctor" => "Rectangular", "args" => []}

    assert get_in(reloaded, [:watch, :view_tree, "type"]) == "windowStack"

    view_nodes =
      (reloaded.watch.view_tree |> collect_view_nodes()) ++
        (get_in(reloaded, [:watch, :model, "runtime_view_output"]) || [])
        |> Enum.map(fn row ->
          %{
            "type" => row["kind"] || row[:kind],
            "text" => row["text"] || row["label"] || row[:text]
          }
        end)

    assert Enum.any?(view_nodes, fn node ->
             text = to_string(node["text"] || "")

             text == preview["string"] or String.contains?(text, preview["string"])
           end)
  end


  test "compile artifacts refresh visual preview after an introspection-only reload" do
    slug = "sim-compile-refresh-preview-#{System.unique_integer([:positive])}"

    source =
      File.read!(Path.join(["priv", "project_templates", "watchface_analog", "src", "Main.elm"]))

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
                                        "target" => "Pebble.Ui.line",
                                        "args" => [
                                          %{
                                            "op" => :record_literal,
                                            "fields" => [
                                              %{
                                                "name" => "x",
                                                "expr" => %{
                                                  "op" => :qualified_call,
                                                  "target" => "Basics.__idiv__",
                                                  "args" => [
                                                    %{
                                                      "op" => :field_access,
                                                      "arg" => %{"op" => :var, "name" => "model"},
                                                      "field" => "screenW"
                                                    },
                                                    %{"op" => :int_literal, "value" => 2}
                                                  ]
                                                }
                                              },
                                              %{
                                                "name" => "y",
                                                "expr" => %{
                                                  "op" => :qualified_call,
                                                  "target" => "Basics.__idiv__",
                                                  "args" => [
                                                    %{
                                                      "op" => :field_access,
                                                      "arg" => %{"op" => :var, "name" => "model"},
                                                      "field" => "screenH"
                                                    },
                                                    %{"op" => :int_literal, "value" => 2}
                                                  ]
                                                }
                                              }
                                            ]
                                          },
                                          %{
                                            "op" => :record_literal,
                                            "fields" => [
                                              %{
                                                "name" => "x",
                                                "expr" => %{"op" => :int_literal, "value" => 72}
                                              },
                                              %{
                                                "name" => "y",
                                                "expr" => %{"op" => :int_literal, "value" => 35}
                                              }
                                            ]
                                          },
                                          %{
                                            "op" => :qualified_call,
                                            "target" => "Pebble.Ui.Color.black",
                                            "args" => []
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
                ]
              }
            }
          ]
        }
      ]
    }

    {:ok, _} = Debugger.start_session(slug)

    assert {:ok, reloaded} =
             Debugger.reload(slug, %{
               rel_path: "watch/src/Main.elm",
               source: source,
               reason: "compile_refresh_preview",
               source_root: "watch"
             })

    reload_ops =
      IdeWeb.WorkspaceLive.DebuggerPreview.svg_ops(reloaded.watch.view_tree, %{
        model: reloaded.watch.model
      })

    refute Enum.any?(reload_ops, &(&1.kind == :unresolved and &1.node_type == "line"))
    assert Enum.any?(reload_ops, &(&1.kind == :line))

    assert {:ok, compiled} =
             Debugger.ingest_elmc_compile(slug, %{
               status: :ok,
               compiled_path: "watch",
               revision: "runtime-artifacts",
               elm_executor_core_ir_b64: :erlang.term_to_binary(core_ir) |> Base.encode64(),
               elm_executor_metadata: %{}
             })

    ops = get_in(compiled, [:watch, :model, "runtime_view_output"]) || []
    refute Enum.any?(ops, &(is_map(&1) and (&1["kind"] || &1[:kind]) == "unresolved"))

    assert Enum.any?(ops, fn row ->
             is_map(row) and row["kind"] == "line" and row["x1"] == 72 and
               (row["y2"] == 84 or row["y1"] == 84)
           end)
  end

end
