defmodule Ide.DebuggerTest do
  use ExUnit.Case, async: false

  alias Ide.Debugger
  alias Ide.Debugger.RuntimeExecutor
  alias Ide.Debugger.RuntimeExecutor.ElmcAdapter

  defmodule DebuggerRuntimeExecutor do
    @moduledoc false

    def execute(request) when is_map(request) do
      selected_n = get_in(request, [:current_model, "runtime_model", "n"])
      artifact_version = get_in(request, [:elm_executor_metadata, "version"])

      {:ok,
       %{
         model_patch: %{"rendered_n" => selected_n, "artifact_version" => artifact_version},
         view_tree: %{"type" => "runtime-root", "children" => [%{"n" => selected_n}]},
         view_output: [%{"kind" => "text_label", "x" => selected_n, "y" => 2, "text" => "ok"}]
       }}
    end
  end

  defmodule TupleMaybeRuntimeExecutor do
    @moduledoc false

    def execute(request) when is_map(request) do
      runtime_model = get_in(request, [:current_model, "runtime_model"]) || %{}
      message = Map.get(request, :message) || ""

      runtime_model =
        cond do
          String.starts_with?(message, "CurrentDateTime ") ->
            Map.put(runtime_model, "currentDateTime", {
              1,
              %{
                "year" => 2026,
                "month" => 4,
                "day" => 25,
                "dayOfWeek" => %{"ctor" => "Sat", "args" => []},
                "hour" => 21,
                "minute" => 19,
                "second" => 0,
                "utcOffsetMinutes" => -360
              }
            })

          message == "" ->
            Map.put(runtime_model, "currentDateTime", %{"ctor" => "Nothing", "args" => []})

          true ->
            runtime_model
        end

      {:ok,
       %{
         model_patch: %{
           "runtime_model" => runtime_model,
           "runtime_model_source" => "tuple_maybe_test"
         },
         view_tree: %{"type" => "tuple-maybe-runtime", "children" => []},
         view_output: []
       }}
    end
  end

  defmodule HttpFollowupRuntimeExecutor do
    @moduledoc false

    def execute(%{message: "Tick"}) do
      {:ok,
       %{
         model_patch: %{"runtime_model" => %{"lastResponse" => 0}},
         view_tree: %{"type" => "root", "children" => []},
         view_output: [],
         protocol_events: [],
         followup_messages: [
           %{
             "source" => "http_command",
             "package" => "elm/http",
             "message" => "WeatherReceived <GET https://example.test/weather>",
             "command" => %{
               "kind" => "http",
               "method" => "GET",
               "url" => "https://example.test/weather",
               "headers" => [],
               "body" => %{"kind" => "empty"},
               "expect" => %{
                 "kind" => "string",
                 "to_msg" => {:function_ref, "WeatherReceived"}
               }
             }
           }
         ]
       }}
    end

    def execute(%{message_value: %{"ctor" => "WeatherReceived"} = message_value}) do
      {:ok,
       %{
         model_patch: %{
           "runtime_model" => %{
             "lastResponse" => 1,
             "received" => message_value
           }
         },
         view_tree: %{"type" => "root", "children" => []},
         view_output: [],
         protocol_events: [],
         followup_messages: []
       }}
    end

    def execute(_request) do
      {:ok,
       %{
         model_patch: %{"runtime_model" => %{}},
         view_tree: %{"type" => "root", "children" => []},
         view_output: [],
         protocol_events: [],
         followup_messages: []
       }}
    end
  end

  defmodule InitRandomFollowupRuntimeExecutor do
    @moduledoc false

    def execute(%{
          message: "RandomGenerated",
          message_value: %{"ctor" => "RandomGenerated"} = value
        }) do
      {:ok,
       %{
         model_patch: %{
           "runtime_model" => %{
             "cells" => [0, 2],
             "seed" => value["args"] |> List.first()
           }
         },
         view_tree: %{"type" => "root", "children" => []},
         view_output: [],
         protocol_events: [],
         followup_messages: []
       }}
    end

    def execute(_request) do
      {:ok,
       %{
         model_patch: %{"runtime_model" => %{"cells" => [], "seed" => 0}},
         view_tree: %{"type" => "root", "children" => []},
         view_output: [],
         protocol_events: [],
         followup_messages: [
           %{
             "source" => "random_command",
             "package" => "elm/random",
             "message" => "RandomGenerated",
             "message_value" => %{"ctor" => "RandomGenerated", "args" => [42]},
             "command" => %{"kind" => "cmd.random.generate"}
           }
         ]
       }}
    end
  end

  defmodule StorageFollowupRuntimeExecutor do
    @moduledoc false

    def execute(%{message: "SaveBest"}) do
      {:ok,
       %{
         model_patch: %{"runtime_model" => %{"best" => 9124}},
         view_tree: %{"type" => "root", "children" => []},
         view_output: [],
         protocol_events: [],
         followup_messages: [
           %{
             "source" => "storage_command",
             "package" => "elm-pebble/elm-watch",
             "message" => nil,
             "command" => %{
               "kind" => "cmd.storage.write_string",
               "key" => 2048,
               "value" => "9124"
             }
           }
         ]
       }}
    end

    def execute(%{
          message: "BestLoaded",
          message_value: %{"ctor" => "BestLoaded", "args" => [value]}
        }) do
      best =
        case Integer.parse(to_string(value || "0")) do
          {parsed, _rest} -> parsed
          :error -> 0
        end

      {:ok,
       %{
         model_patch: %{"runtime_model" => %{"best" => best}},
         view_tree: %{"type" => "root", "children" => []},
         view_output: [],
         protocol_events: [],
         followup_messages: []
       }}
    end

    def execute(_request) do
      {:ok,
       %{
         model_patch: %{"runtime_model" => %{"best" => 0}},
         view_tree: %{"type" => "root", "children" => []},
         view_output: [],
         protocol_events: [],
         followup_messages: [
           %{
             "source" => "storage_command",
             "package" => "elm-pebble/elm-watch",
             "message" => "BestLoaded",
             "message_value" => %{"ctor" => "BestLoaded", "args" => [""]},
             "command" => %{
               "kind" => "cmd.storage.read_string",
               "key" => 2048,
               "value" => "",
               "message" => "BestLoaded",
               "message_value" => %{"ctor" => "BestLoaded", "args" => [""]}
             }
           }
         ]
       }}
    end
  end

  defmodule FailingExternalRuntimeExecutor do
    @moduledoc false

    def execute(_request), do: {:error, :forced_runtime_failure}
  end

  defmodule InitNoFollowupRuntimeExecutor do
    @moduledoc false

    def execute(_request) do
      {:ok,
       %{
         model_patch: %{"runtime_model" => %{}},
         view_tree: %{"type" => "root", "children" => []},
         view_output: [],
         runtime: %{
           "execution_backend" => "external",
           "followup_message_count" => 0,
           "init_cmd_count" => 1
         },
         protocol_events: [],
         followup_messages: []
       }}
    end
  end

  defmodule NilMaybeRuntimeExecutor do
    @moduledoc false

    def execute(request) when is_map(request) do
      runtime_model =
        request
        |> get_in([:current_model, "runtime_model"])
        |> case do
          model when is_map(model) -> model
          _ -> %{}
        end
        |> Map.put("batteryLevel", nil)

      {:ok,
       %{
         model_patch: %{
           "runtime_model" => runtime_model,
           "runtime_model_source" => "nil_maybe_test"
         },
         view_tree: %{"type" => "nil-maybe-runtime", "children" => []},
         view_output: []
       }}
    end
  end

  defmodule MaybeShapeRuntimeExecutor do
    @moduledoc false

    def execute(request) when is_map(request) do
      runtime_model =
        request
        |> get_in([:current_model, "runtime_model"])
        |> case do
          model when is_map(model) -> model
          _ -> %{}
        end
        |> Map.merge(%{
          "backgroundColor" => 0,
          "batteryLevel" => 88,
          "condition" => {1, %{"ctor" => "Clear", "args" => []}},
          "connected" => {1, true},
          "temperature" => {1, %{"ctor" => "Celsius", "args" => [4]}}
        })

      {:ok,
       %{
         model_patch: %{
           "runtime_model" => runtime_model,
           "runtime_model_source" => "maybe_shape_test"
         },
         view_tree: %{"type" => "maybe-shape-runtime", "children" => []},
         view_output: []
       }}
    end
  end

  defmodule AccelRuntimeExecutor do
    @moduledoc false

    def execute(%{message_value: %{"ctor" => "AccelData", "args" => [%{} = sample]}}) do
      {:ok,
       %{
         model_patch: %{
           "runtime_model" => %{
             "x" => sample["x"],
             "y" => sample["y"],
             "z" => sample["z"]
           }
         },
         view_tree: %{"type" => "runtime-root", "children" => []},
         view_output: []
       }}
    end

    def execute(_request) do
      {:ok,
       %{
         model_patch: %{"runtime_model" => %{"x" => 0, "y" => 0, "z" => 1000}},
         view_tree: %{"type" => "runtime-root", "children" => []},
         view_output: []
       }}
    end
  end

  test "start, reload, and reset maintain deterministic event sequencing" do
    slug = "debugger-test-#{System.unique_integer([:positive])}"

    assert {:ok, start_state} = Debugger.start_session(slug)
    assert start_state.running == true
    assert start_state.seq == 1
    assert hd(start_state.events).type == "debugger.start"

    assert {:ok, reload_state} =
             Debugger.reload(slug, %{
               rel_path: "watch/src/Main.elm",
               source: "module Main exposing (main)",
               reason: "test_reload"
             })

    assert reload_state.running == true
    assert reload_state.revision
    assert reload_state.seq == 8
    assert hd(reload_state.events).type == "debugger.view_render"
    assert get_in(reload_state.companion, [:view_tree, "type"]) == "CompanionRoot"
    assert get_in(reload_state.phone, [:view_tree, "type"]) == "PhoneRoot"
    assert is_map(hd(reload_state.events).watch)
    assert is_map(hd(reload_state.events).companion)
    assert Enum.any?(reload_state.events, &(&1.type == "debugger.protocol_tx"))
    assert Enum.any?(reload_state.events, &(&1.type == "debugger.protocol_rx"))

    assert {:ok, reset_state} = Debugger.reset(slug)
    assert reset_state.seq == 9
    assert reset_state.revision == nil
    assert hd(reset_state.events).type == "debugger.reset"
  end

  test "start_session restarts raw and semantic timelines" do
    slug = "debugger-restart-#{System.unique_integer([:positive])}"

    assert {:ok, _start_state} = Debugger.start_session(slug)

    assert {:ok, reloaded} =
             Debugger.reload(slug, %{
               rel_path: "watch/src/Main.elm",
               source: "module Main exposing (main)",
               reason: "test_reload"
             })

    assert reloaded.seq > 1
    assert reloaded.debugger_timeline != []

    assert {:ok, restarted} = Debugger.start_session(slug)

    assert restarted.seq == 1
    assert Enum.map(restarted.events, & &1.type) == ["debugger.start"]
    assert restarted.debugger_seq == 0
    assert restarted.debugger_timeline == []
  end

  test "start_session exposes companion and phone runtime models" do
    slug = "debugger-protocol-models-#{System.unique_integer([:positive])}"

    assert {:ok, state} = Debugger.start_session(slug)

    assert get_in(state, [:companion, :model, "runtime_model", "status"]) == "idle"
    assert get_in(state, [:companion, :model, "runtime_model", "protocol_inbound_count"]) == 0
    assert get_in(state, [:companion, :model, "runtime_model", "protocol_message_count"]) == 0
    assert get_in(state, [:phone, :model, "runtime_model", "status"]) == "idle"
  end

  test "render_runtime_preview_for_debugger renders selected model with latest artifacts" do
    previous_config = Application.get_env(:ide, Debugger, [])

    Application.put_env(
      :ide,
      Debugger,
      Keyword.put(previous_config, :runtime_executor_module, DebuggerRuntimeExecutor)
    )

    on_exit(fn -> Application.put_env(:ide, Debugger, previous_config) end)

    selected_runtime = %{
      model: %{"runtime_model" => %{"n" => 1}},
      view_tree: %{"type" => "parser-root", "children" => [%{}]}
    }

    latest_runtime = %{
      model: %{
        "runtime_model" => %{"n" => 99},
        "elm_introspect" => %{"view" => %{}},
        "elm_executor_metadata" => %{"version" => "latest"},
        "elm_executor_core_ir" => %{"modules" => %{}},
        "last_path" => "watch/src/Main.elm"
      },
      view_tree: %{"type" => "latest-root", "children" => [%{}]}
    }

    rendered =
      Debugger.render_runtime_preview_for_debugger(selected_runtime, latest_runtime, :watch)

    assert get_in(rendered, [:model, "runtime_model", "n"]) == 1
    assert get_in(rendered, [:model, "rendered_n"]) == 1
    assert get_in(rendered, [:model, "artifact_version"]) == "latest"

    assert get_in(rendered, [:model, "runtime_view_output"]) == [
             %{"kind" => "text_label", "x" => 1, "y" => 2, "text" => "ok"}
           ]

    assert get_in(rendered, [:view_tree, "children", Access.at(0), "n"]) == 1
  end

  test "set_watch_profile updates launch context and watch screen metadata" do
    slug = "sim-watch-profile-#{System.unique_integer([:positive])}"

    assert {:ok, _} = Debugger.start_session(slug)
    assert {:ok, updated} = Debugger.set_watch_profile(slug, %{watch_profile_id: "chalk"})

    assert updated.watch_profile_id == "chalk"
    assert get_in(updated, [:launch_context, "watch_profile_id"]) == "chalk"
    assert get_in(updated, [:launch_context, "screen", "width"]) == 180
    assert get_in(updated, [:watch, :model, "screen_width"]) == 180
    assert get_in(updated, [:watch, :model, "supports_color"]) == true
  end

  test "set_watch_profile exposes isRound on launch screen contract" do
    slug = "sim-watch-profile-is-round-#{System.unique_integer([:positive])}"

    assert {:ok, _} = Debugger.start_session(slug)
    assert {:ok, updated} = Debugger.set_watch_profile(slug, %{watch_profile_id: "chalk"})

    assert get_in(updated, [:launch_context, "screen", "width"]) == 180
    assert get_in(updated, [:launch_context, "screen", "height"]) == 180
    assert get_in(updated, [:launch_context, "screen", "isRound"]) == true
  end

  test "start_session preserves selected watch profile when no profile override is provided" do
    slug = "sim-watch-profile-preserve-#{System.unique_integer([:positive])}"

    assert {:ok, _} = Debugger.start_session(slug)
    assert {:ok, selected} = Debugger.set_watch_profile(slug, %{watch_profile_id: "chalk"})
    assert selected.watch_profile_id == "chalk"

    assert {:ok, restarted} = Debugger.start_session(slug)
    assert restarted.watch_profile_id == "chalk"
    assert get_in(restarted, [:launch_context, "watch_profile_id"]) == "chalk"
    assert get_in(restarted, [:watch, :model, "screen_width"]) == 180
  end

  test "watch reload merges parser snapshot into watch model and view tree" do
    slug = "sim-introspect-#{System.unique_integer([:positive])}"

    source = """
    module Snap exposing (..)

    type Msg
        = A

    init _ =
        ( { n = 0 }, Cmd.none )

    view m =
        Ui.root []
    """

    assert {:ok, _} = Debugger.start_session(slug)

    assert {:ok, st} =
             Debugger.reload(slug, %{
               rel_path: "watch/Snap.elm",
               source: source,
               reason: "introspect_test"
             })

    assert get_in(st, [:watch, :model, "elm_executor_mode"]) == "runtime_executed"
    assert get_in(st, [:watch, :model, "elm_executor", "engine"]) == "elm_executor_runtime_v1"
    assert is_binary(get_in(st, [:watch, :model, "runtime_model_sha256"]))
    assert String.length(get_in(st, [:watch, :model, "runtime_model_sha256"])) == 64
    assert is_binary(get_in(st, [:watch, :model, "runtime_view_tree_sha256"]))
    assert String.length(get_in(st, [:watch, :model, "runtime_view_tree_sha256"])) == 64
    assert get_in(st, [:watch, :model, "elm_introspect", "module"]) == "Snap"
    assert get_in(st, [:watch, :view_tree, "type"]) == "root"

    assert Enum.any?(st.events, &(&1.type == "debugger.elm_introspect"))
    assert Enum.any?(st.events, &(&1.type == "debugger.runtime_exec"))
    runtime_exec = Enum.find(st.events, &(&1.type == "debugger.runtime_exec"))
    assert runtime_exec.payload.target == "watch"
    assert runtime_exec.payload.engine == "elm_executor_runtime_v1"
    assert runtime_exec.payload.runtime_model_source == "init_model"
    assert runtime_exec.payload.view_tree_source == "parser_view_tree"
    assert runtime_exec.payload.runtime_model_entry_count >= 1
    assert runtime_exec.payload.view_tree_node_count >= 1
    assert is_binary(runtime_exec.payload.runtime_model_sha256)
    assert String.length(runtime_exec.payload.runtime_model_sha256) == 64
    assert is_binary(runtime_exec.payload.view_tree_sha256)
    assert String.length(runtime_exec.payload.view_tree_sha256) == 64
    intro = Enum.find(st.events, &(&1.type == "debugger.elm_introspect"))
    p = intro.payload
    assert is_map(p) && (Map.get(p, :module) == "Snap" || Map.get(p, "module") == "Snap")
    assert Map.get(p, :target) == "watch" || Map.get(p, "target") == "watch"
  end

  test "protocol reload merges parser snapshot into companion model and view tree" do
    slug = "sim-intro-proto-#{System.unique_integer([:positive])}"

    source = """
    module ProtoSnap exposing (..)

    type Msg
        = P

    init _ =
        ( { p = 0 }, Cmd.none )

    view m =
        Ui.root []
    """

    assert {:ok, _} = Debugger.start_session(slug)

    assert {:ok, st} =
             Debugger.reload(slug, %{
               rel_path: "protocol/Types.elm",
               source: source,
               reason: "proto_introspect",
               source_root: "protocol"
             })

    assert get_in(st, [:companion, :model, "elm_introspect", "module"]) == "ProtoSnap"
    assert get_in(st, [:companion, :view_tree, "type"]) == "root"
    refute get_in(st, [:watch, :model, "elm_introspect"])
  end

  test "phone reload merges parser snapshot into phone model and view tree" do
    slug = "sim-intro-phone-#{System.unique_integer([:positive])}"

    source = """
    module PhoneSnap exposing (..)

    type Msg
        = Q

    init _ =
        ( { q = 0 }, Cmd.none )

    view m =
        Ui.root []
    """

    assert {:ok, _} = Debugger.start_session(slug)

    assert {:ok, st} =
             Debugger.reload(slug, %{
               rel_path: "phone/Main.elm",
               source: source,
               reason: "phone_introspect",
               source_root: "phone"
             })

    assert get_in(st, [:phone, :model, "elm_introspect", "module"]) == "PhoneSnap"
    assert get_in(st, [:phone, :view_tree, "type"]) == "root"
  end

  test "snapshot trims event list while preserving sequence" do
    slug = "debugger-limit-#{System.unique_integer([:positive])}"
    {:ok, _} = Debugger.start_session(slug)

    for idx <- 1..5 do
      {:ok, _} =
        Debugger.reload(slug, %{
          rel_path: "watch/src/File#{idx}.elm",
          source: "module File#{idx} exposing (x)",
          reason: "loop"
        })
    end

    assert {:ok, snapshot} = Debugger.snapshot(slug, event_limit: 2)
    assert length(snapshot.events) == 2
    assert snapshot.seq == 36
  end

  test "snapshot auto-starts debugger process when missing" do
    if pid = Process.whereis(Debugger) do
      Process.exit(pid, :kill)
      Process.sleep(25)
    end

    slug = "debugger-autostart-#{System.unique_integer([:positive])}"
    assert {:ok, snapshot} = Debugger.snapshot(slug, event_limit: 5)
    assert snapshot.running == false
    assert is_pid(Process.whereis(Debugger))
  end

  test "snapshot supports event type and sequence filters" do
    slug = "debugger-filters-#{System.unique_integer([:positive])}"
    {:ok, _} = Debugger.start_session(slug)

    {:ok, _} =
      Debugger.reload(slug, %{
        rel_path: "watch/src/Filter.elm",
        source: "module Filter exposing (x)",
        reason: "filter_test"
      })

    assert {:ok, type_filtered} =
             Debugger.snapshot(slug, event_limit: 20, types: ["debugger.protocol_tx"])

    assert length(type_filtered.events) == 1
    assert hd(type_filtered.events).type == "debugger.protocol_tx"

    assert {:ok, seq_filtered} = Debugger.snapshot(slug, event_limit: 20, since_seq: 4)
    assert Enum.all?(seq_filtered.events, &(&1.seq > 4))
  end

  test "export_trace returns deterministic JSON and checksum" do
    slug = "sim-export-#{System.unique_integer([:positive])}"
    {:ok, _} = Debugger.start_session(slug)

    {:ok, _} =
      Debugger.reload(slug, %{
        rel_path: "watch/src/Main.elm",
        source: "module Main exposing (main)",
        reason: "export_test"
      })

    assert {:ok, a} = Debugger.export_trace(slug, event_limit: 100)
    assert {:ok, b} = Debugger.export_trace(slug, event_limit: 100)
    assert a.sha256 == b.sha256
    assert a.json == b.json
    assert byte_size(a.json) == a.byte_size

    decoded = Jason.decode!(a.json)
    assert decoded["export_version"] == 1
    assert decoded["project_slug"] == slug
    assert is_map(decoded["phone"])
    assert is_list(decoded["events"])
    assert Enum.all?(decoded["events"], &is_map/1)
    assert is_map(decoded["runtime_fingerprint_compare"])
    assert is_integer(decoded["runtime_fingerprint_compare"]["current_cursor_seq"])
    assert Map.has_key?(decoded["runtime_fingerprint_compare"], "baseline_cursor_seq")
    assert is_integer(decoded["runtime_fingerprint_compare"]["changed_surface_count"])
    assert is_integer(decoded["runtime_fingerprint_compare"]["key_target_changed_surface_count"])
    assert Map.has_key?(decoded["runtime_fingerprint_compare"], "key_target_drift_detail")
    assert Map.has_key?(decoded["runtime_fingerprint_compare"], "drift_detail")
    assert is_map(decoded["runtime_fingerprint_compare"]["surfaces"])

    assert Enum.map(decoded["events"], & &1["seq"]) ==
             Enum.sort(Enum.map(decoded["events"], & &1["seq"]))
  end

  test "export_trace includes snapshot references for unchanged surfaces" do
    slug = "sim-export-snapshot-refs-#{System.unique_integer([:positive])}"
    {:ok, _} = Debugger.start_session(slug)

    {:ok, _} =
      Debugger.reload(slug, %{
        rel_path: "watch/src/Main.elm",
        source: "module Main exposing (main)",
        reason: "snapshot_ref_test"
      })

    assert {:ok, exp} = Debugger.export_trace(slug, event_limit: 120)
    decoded = Jason.decode!(exp.json)
    events = Map.get(decoded, "events", [])

    assert Enum.any?(events, fn event ->
             refs = Map.get(event, "snapshot_refs")
             is_map(refs) and map_size(refs) > 0
           end)

    assert Enum.all?(events, fn event ->
             changed = Map.get(event, "snapshot_changed_surfaces")
             is_list(changed) and Enum.all?(changed, &is_binary/1)
           end)
  end

  test "snapshot_reference_rows returns lightweight per-event refs" do
    slug = "sim-snapshot-rows-#{System.unique_integer([:positive])}"
    {:ok, _} = Debugger.start_session(slug)

    {:ok, _} =
      Debugger.reload(slug, %{
        rel_path: "watch/src/Main.elm",
        source: "module Main exposing (main)",
        reason: "snapshot_rows"
      })

    {:ok, state} = Debugger.snapshot(slug, event_limit: 120)
    rows = Debugger.snapshot_reference_rows(state.events)

    assert is_list(rows)
    assert rows != []
    assert Enum.all?(rows, &is_integer(&1["seq"]))
    assert Enum.all?(rows, &is_list(&1["snapshot_changed_surfaces"]))
    assert Enum.all?(rows, &is_map(&1["snapshot_refs"]))
  end

  test "continue_from_snapshot materializes selected snapshot into live tip" do
    slug = "sim-continue-snapshot-#{System.unique_integer([:positive])}"
    {:ok, _} = Debugger.start_session(slug)

    {:ok, first_step} = Debugger.step(slug, %{target: "watch", message: "Inc", count: 1})
    {:ok, second_step} = Debugger.step(slug, %{target: "watch", message: "Inc", count: 1})
    assert second_step.watch.model["counter"] >= 2

    assert {:ok, continued} =
             Debugger.continue_from_snapshot(slug, %{cursor_seq: first_step.seq})

    assert hd(continued.events).type == "debugger.snapshot_continue"

    assert get_in(continued.watch, [:model, "counter"]) ==
             get_in(first_step.watch, [:model, "counter"])

    assert continued.seq > second_step.seq
  end

  test "import_trace restores state for round-trip export" do
    slug = "sim-import-#{System.unique_integer([:positive])}"
    {:ok, _} = Debugger.start_session(slug)

    {:ok, _} =
      Debugger.reload(slug, %{
        rel_path: "watch/src/Main.elm",
        source: "module Main exposing (main)",
        reason: "import_roundtrip"
      })

    assert {:ok, exp} = Debugger.export_trace(slug, event_limit: 500)
    assert {:ok, _} = Debugger.reset(slug)
    assert {:ok, imported} = Debugger.import_trace(slug, exp.json)
    assert imported.seq == exp.json |> Jason.decode!() |> Map.get("seq")
    assert {:ok, exp2} = Debugger.export_trace(slug, event_limit: 500)
    assert exp2.sha256 == exp.sha256
  end

  test "export_trace supports explicit runtime compare cursor bounds" do
    slug = "sim-export-compare-#{System.unique_integer([:positive])}"
    {:ok, _} = Debugger.start_session(slug)

    {:ok, _} =
      Debugger.reload(slug, %{
        rel_path: "watch/src/Main.elm",
        source: "module Main exposing (main)",
        reason: "export_compare_test"
      })

    {:ok, stepped} = Debugger.step(slug, %{target: "watch", count: 1})
    {:ok, _} = Debugger.step(slug, %{target: "watch", count: 1})

    assert {:ok, exp} =
             Debugger.export_trace(slug,
               event_limit: 200,
               compare_cursor_seq: stepped.seq,
               baseline_cursor_seq: 1
             )

    compare = exp.json |> Jason.decode!() |> Map.get("runtime_fingerprint_compare")
    assert compare["current_cursor_seq"] <= stepped.seq
    assert compare["baseline_cursor_seq"] == 1
    assert is_integer(compare["backend_changed_surface_count"])
    assert is_integer(compare["key_target_changed_surface_count"])
    assert Map.has_key?(compare, "key_target_drift_detail")
    assert Map.has_key?(compare, "drift_detail")
    assert is_map(compare["surfaces"])
    assert Map.has_key?(compare["surfaces"]["watch"], "current_execution_backend")
    assert Map.has_key?(compare["surfaces"]["watch"], "baseline_execution_backend")
    assert Map.has_key?(compare["surfaces"]["watch"], "current_external_fallback_reason")
    assert Map.has_key?(compare["surfaces"]["watch"], "baseline_external_fallback_reason")
    assert Map.has_key?(compare["surfaces"]["watch"], "current_active_target_key_source")
    assert Map.has_key?(compare["surfaces"]["watch"], "baseline_active_target_key_source")
  end

  test "import_trace rejects slug mismatch when strict" do
    slug_a = "sim-slug-a-#{System.unique_integer([:positive])}"
    slug_b = "sim-slug-b-#{System.unique_integer([:positive])}"
    {:ok, _} = Debugger.start_session(slug_a)
    assert {:ok, exp} = Debugger.export_trace(slug_a, event_limit: 50)
    assert {:error, :slug_mismatch} = Debugger.import_trace(slug_b, exp.json, strict_slug: true)
    assert {:ok, _} = Debugger.import_trace(slug_b, exp.json, strict_slug: false)
  end

  test "import_trace rejects invalid json" do
    slug = "sim-bad-json-#{System.unique_integer([:positive])}"
    assert {:error, :invalid_json} = Debugger.import_trace(slug, "not json")
  end

  test "reload with phone source_root emits phone render without synthetic update" do
    slug = "sim-phone-#{System.unique_integer([:positive])}"
    {:ok, _} = Debugger.start_session(slug)

    assert {:ok, st} =
             Debugger.reload(slug, %{
               rel_path: "phone/src/Main.elm",
               source: "module Main exposing (main)",
               reason: "phone_test",
               source_root: "phone"
             })

    assert st.seq == 9
    assert hd(st.events).type == "debugger.view_render"

    refute Enum.any?(st.events, fn e ->
             e.type == "debugger.update_in" and
               (Map.get(e.payload, :target) == "phone" or Map.get(e.payload, "target") == "phone")
           end)

    assert get_in(st.phone, [:view_tree, "type"]) == "PhoneRoot"
  end

  test "reload with protocol source_root labels companion tree" do
    slug = "sim-proto-#{System.unique_integer([:positive])}"
    {:ok, _} = Debugger.start_session(slug)

    assert {:ok, st} =
             Debugger.reload(slug, %{
               rel_path: "protocol/Codec.elm",
               source: "module Codec exposing (..)",
               reason: "proto_test",
               source_root: "protocol"
             })

    assert st.seq == 8
    assert get_in(st.companion, [:view_tree, "label"]) == "phone"
    [status | _] = get_in(st.companion, [:view_tree, "children"])
    assert String.starts_with?(status["label"], "protocol:")
  end

  test "step emits deterministic runtime timeline events without heuristic mutation" do
    slug = "sim-step-#{System.unique_integer([:positive])}"

    source = """
    module StepSnap exposing (..)

    type Msg
        = Inc
        | Dec

    init _ =
        ( { n = 1, enabled = false }, Cmd.none )

    view m =
        Ui.root []
    """

    {:ok, _} = Debugger.start_session(slug)

    {:ok, reloaded} =
      Debugger.reload(slug, %{
        rel_path: "watch/StepSnap.elm",
        source: source,
        reason: "step_base"
      })

    assert {:ok, stepped} =
             Debugger.step(slug, %{
               target: "watch",
               message: "inc",
               count: 2
             })

    assert get_in(stepped, [:watch, :model, "runtime_last_message"]) == "Inc"
    assert get_in(stepped, [:watch, :model, "runtime_message_source"]) == "provided"
    assert get_in(stepped, [:watch, :model, "runtime_model_source"]) == "step_message"
    assert get_in(stepped, [:watch, :model, "runtime_model", "n"]) == 1
    assert get_in(stepped, [:watch, :model, "runtime_model", "last_operation"]) == "nil"

    assert get_in(stepped, [:watch, :model, "runtime_model_sha256"]) !=
             get_in(reloaded, [:watch, :model, "runtime_model_sha256"])

    assert get_in(stepped, [:watch, :model, "runtime_view_tree_sha256"]) !=
             get_in(reloaded, [:watch, :model, "runtime_view_tree_sha256"])

    assert get_in(stepped, [:watch, :model, "elm_executor", "runtime_model_sha256"]) ==
             get_in(stepped, [:watch, :model, "runtime_model_sha256"])

    assert is_integer(
             get_in(stepped, [:watch, :model, "elm_executor", "runtime_model_entry_count"])
           )

    assert is_integer(get_in(stepped, [:watch, :model, "elm_executor", "view_tree_node_count"]))
    assert get_in(stepped, [:watch, :model, "runtime_known_messages"]) == ["Inc", "Dec"]
    assert get_in(stepped, [:watch, :model, "_debugger_steps"]) >= 2

    assert runtime_exec =
             Enum.find(
               stepped.events,
               &(&1.type == "debugger.runtime_exec" and
                   (Map.get(&1.payload, :trigger) || Map.get(&1.payload, "trigger")) == "step")
             )

    assert runtime_exec.payload.runtime_model_source == "step_message"
    assert runtime_exec.payload.view_tree_source == "step_derived_view_tree"
    assert runtime_exec.payload.trigger == "step"
    assert runtime_exec.payload.message == "Inc"
    assert runtime_exec.payload.message_source == "provided"

    refute Enum.any?(stepped.events, &synthetic_step_protocol_event?/1)

    refute Enum.any?(stepped.events, fn event ->
             event.type == "debugger.update_in" and
               (Map.get(event.payload, :target) || Map.get(event.payload, "target")) == "protocol" and
               String.starts_with?(
                 Map.get(event.payload, :message) || Map.get(event.payload, "message") || "",
                 "Step:"
               )
           end)

    assert Enum.count(stepped.events, &(&1.type == "debugger.update_in")) >= 1
    assert Enum.count(stepped.events, &(&1.type == "debugger.view_render")) >= 1

    assert {:ok, unfiltered_snapshot} = Debugger.snapshot(slug, types: [])
    assert Enum.any?(unfiltered_snapshot.events, &(&1.type == "debugger.update_in"))
  end

  test "step without explicit message cycles msg constructors deterministically" do
    slug = "sim-step-cycle-#{System.unique_integer([:positive])}"

    source = """
    module StepCycle exposing (..)

    type Msg
        = Inc
        | Dec

    init _ =
        ( { n = 1 }, Cmd.none )

    view m =
        Ui.root []
    """

    {:ok, _} = Debugger.start_session(slug)

    {:ok, _} =
      Debugger.reload(slug, %{
        rel_path: "watch/StepCycle.elm",
        source: source,
        reason: "step_cycle_base"
      })

    assert {:ok, stepped} = Debugger.step(slug, %{target: "watch", count: 2})
    assert get_in(stepped, [:watch, :model, "runtime_message_source"]) == "auto_cycle"
    assert get_in(stepped, [:watch, :model, "runtime_last_message"]) == "Dec"
    assert get_in(stepped, [:watch, :model, "runtime_model", "n"]) == 1
  end

  test "companion step does not synthesize watch protocol inbox state" do
    slug = "sim-proto-watch-#{System.unique_integer([:positive])}"

    source = """
    module ProtoStep exposing (..)

    type Msg
        = Ping

    init _ =
        ( { n = 1 }, Cmd.none )

    view m =
        Ui.root []
    """

    {:ok, _} = Debugger.start_session(slug)

    {:ok, _} =
      Debugger.reload(slug, %{
        rel_path: "protocol/ProtoStep.elm",
        source: source,
        reason: "proto_step_base",
        source_root: "protocol"
      })

    assert {:ok, stepped} =
             Debugger.step(slug, %{
               target: "companion",
               message: "Ping",
               count: 1
             })

    refute get_in(stepped, [:watch, :model, "protocol_last_inbound_message"]) == "Step:Ping"

    refute get_in(stepped, [:watch, :model, "runtime_model", "protocol_last_inbound_message"]) ==
             "Step:Ping"

    refute Enum.any?(stepped.events, &synthetic_step_protocol_event?/1)
  end

  test "debugger step can run through elmc adapter executor path" do
    old_runtime_executor_env = Application.get_env(:ide, RuntimeExecutor, [])

    on_exit(fn ->
      Application.put_env(:ide, RuntimeExecutor, old_runtime_executor_env)
    end)

    Application.put_env(:ide, RuntimeExecutor,
      external_executor_module: ElmcAdapter,
      external_executor_strict: true
    )

    slug = "sim-elmc-adapter-#{System.unique_integer([:positive])}"
    {:ok, _} = Debugger.start_session(slug)

    {:ok, _} =
      Debugger.reload(slug, %{
        rel_path: "watch/src/Main.elm",
        source: "module Main exposing (main)",
        reason: "elmc_adapter_step"
      })

    assert {:ok, stepped} = Debugger.step(slug, %{target: "watch", message: "Inc", count: 1})

    assert get_in(stepped, [:watch, :model, "elm_executor", "engine"]) ==
             "elmc_runtime_executor_v0"

    refute Enum.any?(stepped.events, &synthetic_step_protocol_event?/1)
  end

  test "tick injects subscription-style ingress with deterministic message source" do
    slug = "sim-tick-#{System.unique_integer([:positive])}"

    source = """
    module TickSnap exposing (..)

    type Msg
        = Tick
        | Inc

    init _ =
        ( { n = 1 }, Cmd.none )

    subscriptions model =
        Time.every 1000 Tick

    view m =
        Ui.root []
    """

    {:ok, _} = Debugger.start_session(slug)

    {:ok, _} =
      Debugger.reload(slug, %{
        rel_path: "watch/TickSnap.elm",
        source: source,
        reason: "tick_base"
      })

    assert {:ok, ticked} = Debugger.tick(slug, %{target: "watch", count: 2})
    assert get_in(ticked, [:watch, :model, "runtime_last_message"]) == "Tick"
    assert get_in(ticked, [:watch, :model, "runtime_message_source"]) == "subscription_tick"
    assert get_in(ticked, [:watch, :model, "runtime_model_source"]) == "step_message"

    assert tick_exec =
             Enum.find(
               ticked.events,
               &(&1.type == "debugger.runtime_exec" and
                   (Map.get(&1.payload, :trigger) || Map.get(&1.payload, "trigger")) == "tick")
             )

    assert tick_exec.payload.trigger == "tick"

    assert Enum.count(ticked.events, &(&1.type == "debugger.tick")) >= 1

    refute Enum.any?(ticked.events, &synthetic_step_protocol_event?/1)

    assert Enum.count(ticked.events, &(&1.type == "debugger.update_in")) >= 1
    assert Enum.count(ticked.events, &(&1.type == "debugger.view_render")) >= 1
    assert is_map(get_in(ticked, [:watch, :view_tree]))
    assert is_binary(get_in(ticked, [:watch, :view_tree, "type"]))
    assert is_list(get_in(ticked, [:watch, :model, "runtime_view_output"]))

    assert Enum.any?(get_in(ticked, [:watch, :view_tree, "children"]) || [], fn child ->
             is_map(child) and Map.get(child, "type") == "debuggerRenderStep"
           end)
  end

  test "tick synthesizes realistic current time device response when command requests it" do
    slug = "sim-device-time-#{System.unique_integer([:positive])}"

    source = """
    module DeviceTimeSnap exposing (..)

    import Pebble.Cmd as PebbleCmd

    type Msg
        = Tick
        | CurrentTime String

    init _ =
        ( { hhmm = 0 }, Cmd.none )

    update msg model =
        case msg of
            Tick ->
                ( model, PebbleCmd.getCurrentTimeString CurrentTime )

            CurrentTime _ ->
                ( model, Cmd.none )

    subscriptions _ =
        Sub.none
    """

    {:ok, _} = Debugger.start_session(slug)

    {:ok, _} =
      Debugger.reload(slug, %{
        rel_path: "watch/DeviceTimeSnap.elm",
        source: source,
        reason: "device_time_base"
      })

    assert {:ok, ticked} = Debugger.tick(slug, %{target: "watch", count: 1})

    assert is_integer(get_in(ticked, [:watch, :model, "runtime_model", "hhmm"]))
    assert get_in(ticked, [:watch, :model, "runtime_model", "hhmm"]) > 0
    assert is_map(get_in(ticked, [:watch, :model, "debugger_device_current_time_string"]))

    assert Enum.any?(ticked.events, fn event ->
             event.type == "debugger.device_data" and
               (Map.get(event.payload, :request) || Map.get(event.payload, "request")) ==
                 "current_time_string"
           end)

    assert Enum.any?(ticked.events, fn event ->
             event.type == "debugger.update_in" and
               String.starts_with?(
                 Map.get(event.payload, :message) || Map.get(event.payload, "message") || "",
                 "CurrentTime"
               )
           end)
  end

  test "step message matrix surfaces strict no-heuristic behavior" do
    slug = "sim-msg-matrix-#{System.unique_integer([:positive])}"

    source = """
    module MessageMatrix exposing (..)

    type alias Model =
        { count : Int
        , enabled : Bool
        , title : String
        }

    type Msg
        = Tick
        | SetCount Int
        | SetEnabled Bool
        | SetTitle String
        | SetCountIgnored Int

    init _ =
        ( { count = 0, enabled = true, title = "--" }, Cmd.none )

    update msg model =
        case msg of
            Tick ->
                ( model, Cmd.none )

            SetCount value ->
                ( { model | count = value }, Cmd.none )

            SetEnabled value ->
                ( { model | enabled = value }, Cmd.none )

            SetTitle value ->
                ( { model | title = value }, Cmd.none )

            SetCountIgnored _ ->
                ( model, Cmd.none )

    subscriptions _ =
        Sub.none
    """

    {:ok, _} = Debugger.start_session(slug)

    {:ok, _} =
      Debugger.reload(slug, %{
        rel_path: "watch/MessageMatrix.elm",
        source: source,
        reason: "message_matrix_base"
      })

    assert {:ok, after_title} =
             Debugger.step(slug, %{target: "watch", message: "SetTitle \"HELLO\"", count: 1})

    assert get_in(after_title, [:watch, :model, "runtime_model", "title"]) == "--"
    assert get_in(after_title, [:watch, :model, "runtime_model", "count"]) == 0
    enabled_baseline = get_in(after_title, [:watch, :model, "runtime_model", "enabled"])

    assert get_in(after_title, [:watch, :model, "elm_executor", "operation_source"]) ==
             "unmapped_message"

    assert {:ok, after_count} =
             Debugger.step(slug, %{target: "watch", message: "SetCount 42", count: 1})

    assert get_in(after_count, [:watch, :model, "runtime_model", "count"]) == 0
    assert get_in(after_count, [:watch, :model, "runtime_model", "title"]) == "--"
    assert get_in(after_count, [:watch, :model, "runtime_model", "enabled"]) == enabled_baseline

    assert {:ok, after_bool} =
             Debugger.step(slug, %{target: "watch", message: "SetEnabled false", count: 1})

    assert get_in(after_bool, [:watch, :model, "runtime_model", "enabled"]) == enabled_baseline
    assert get_in(after_bool, [:watch, :model, "runtime_model", "count"]) == 0
    assert get_in(after_bool, [:watch, :model, "runtime_model", "title"]) == "--"

    assert {:ok, after_wildcard} =
             Debugger.step(slug, %{target: "watch", message: "SetCountIgnored 99", count: 1})

    assert get_in(after_wildcard, [:watch, :model, "runtime_model", "count"]) == 0

    assert get_in(after_wildcard, [:watch, :model, "runtime_model", "enabled"]) ==
             enabled_baseline

    assert get_in(after_wildcard, [:watch, :model, "runtime_model", "title"]) == "--"

    assert {:ok, after_unmapped} =
             Debugger.step(slug, %{target: "watch", message: "Ping 7", count: 1})

    assert get_in(after_unmapped, [:watch, :model, "runtime_model", "count"]) == 0

    assert get_in(after_unmapped, [:watch, :model, "runtime_model", "enabled"]) ==
             enabled_baseline

    assert get_in(after_unmapped, [:watch, :model, "runtime_model", "title"]) == "--"

    assert get_in(after_unmapped, [:watch, :model, "elm_executor", "operation_source"]) ==
             "unmapped_message"
  end

  test "strict full-stack flow keeps protocol/device/replay deterministic without hidden mutation" do
    slug = "sim-strict-fullstack-#{System.unique_integer([:positive])}"

    source = """
    module StrictFlow exposing (..)

    import Pebble.Cmd as PebbleCmd

    type alias Model =
        { count : Int
        , timeString : String
        }

    type Msg
        = Tick
        | SetCount Int
        | CurrentTimeString String

    init _ =
        ( { count = 1, timeString = "--:--" }, Cmd.none )

    update msg model =
        case msg of
            Tick ->
                ( model, PebbleCmd.getCurrentTimeString CurrentTimeString )

            SetCount value ->
                ( { model | count = value }, Cmd.none )

            CurrentTimeString value ->
                ( { model | timeString = value }, Cmd.none )

    subscriptions _ =
        Sub.none
    """

    {:ok, _} = Debugger.start_session(slug)

    {:ok, _} =
      Debugger.reload(slug, %{
        rel_path: "watch/StrictFlow.elm",
        source: source,
        reason: "strict_fullstack_base"
      })

    assert {:ok, ticked} = Debugger.tick(slug, %{target: "watch", count: 1})
    preview = get_in(ticked, [:watch, :model, "debugger_device_current_time_string"]) || %{}

    assert is_binary(get_in(ticked, [:watch, :model, "runtime_model", "timeString"]))
    assert get_in(ticked, [:watch, :model, "runtime_model", "timeString"]) == preview["string"]
    assert is_map(preview)

    assert get_in(ticked, [:watch, :model, "elm_executor", "runtime_model_source"]) ==
             "step_message"

    assert Enum.any?(ticked.events, fn event ->
             event.type == "debugger.device_data" and
               (Map.get(event.payload, :request) || Map.get(event.payload, "request")) ==
                 "current_time_string"
           end)

    refute Enum.any?(ticked.events, fn event ->
             event.type in ["debugger.protocol_tx", "debugger.protocol_rx"] and
               (Map.get(event.payload, :trigger) || Map.get(event.payload, "trigger")) == "tick"
           end)

    assert {:ok, stepped} =
             Debugger.step(slug, %{target: "watch", message: "SetCount 9", count: 1})

    assert get_in(stepped, [:watch, :model, "runtime_model", "count"]) == 1

    assert get_in(stepped, [:watch, :model, "elm_executor", "operation_source"]) ==
             "unmapped_message"

    seq_before_replay = stepped.seq
    assert {:ok, _} = Debugger.step(slug, %{target: "watch", message: "SetCount 11", count: 1})

    assert {:ok, replayed} =
             Debugger.replay_recent(slug, %{
               target: "watch",
               count: 1,
               cursor_seq: seq_before_replay
             })

    assert get_in(replayed, [:watch, :model, "runtime_model", "count"]) == 1

    assert Enum.any?(replayed.events, fn event ->
             event.type == "debugger.runtime_exec" and
               (Map.get(event.payload, :trigger) || Map.get(event.payload, "trigger")) == "replay"
           end)
  end

  test "tick synthesizes structured current date/time device response with UTC offset" do
    slug = "sim-device-datetime-#{System.unique_integer([:positive])}"

    source = """
    module DeviceDateTimeSnap exposing (..)

    import Pebble.Cmd as PebbleCmd
    import Time

    type Msg
        = Tick
        | CurrentDateTime PebbleCmd.CurrentDateTime

    init _ =
        ( { year = 0
          , month = 0
          , day = 0
          , dayOfWeek = Time.Mon
          , hour = 0
          , minute = 0
          , second = 0
          , utcOffsetMinutes = 0
          }
        , Cmd.none
        )

    update msg model =
        case msg of
            Tick ->
                ( model, PebbleCmd.getCurrentDateTime CurrentDateTime )

            CurrentDateTime value ->
                ( { model
                    | year = value.year
                    , month = value.month
                    , day = value.day
                    , dayOfWeek = value.dayOfWeek
                    , hour = value.hour
                    , minute = value.minute
                    , second = value.second
                    , utcOffsetMinutes = value.utcOffsetMinutes
                  }
                , Cmd.none
                )

    subscriptions _ =
        Sub.none
    """

    {:ok, _} = Debugger.start_session(slug)

    {:ok, _} =
      Debugger.reload(slug, %{
        rel_path: "watch/DeviceDateTimeSnap.elm",
        source: source,
        reason: "device_datetime_base"
      })

    assert {:ok, ticked} = Debugger.tick(slug, %{target: "watch", count: 1})

    runtime_model = get_in(ticked, [:watch, :model, "runtime_model"]) || %{}
    device_preview = get_in(ticked, [:watch, :model, "debugger_device_current_date_time"]) || %{}

    assert is_integer(runtime_model["year"]) and runtime_model["year"] >= 2000
    assert is_integer(runtime_model["month"]) and runtime_model["month"] in 1..12
    assert is_integer(runtime_model["day"]) and runtime_model["day"] in 1..31
    assert is_integer(runtime_model["hour"]) and runtime_model["hour"] in 0..23
    assert is_integer(runtime_model["minute"]) and runtime_model["minute"] in 0..59
    assert is_integer(runtime_model["second"]) and runtime_model["second"] in 0..59
    assert is_integer(runtime_model["utcOffsetMinutes"])
    assert is_map(runtime_model["dayOfWeek"])
    assert is_binary(runtime_model["dayOfWeek"]["ctor"])
    assert is_map(device_preview)
    assert device_preview["utcOffsetMinutes"] == runtime_model["utcOffsetMinutes"]
    assert device_preview["dayOfWeek"] == runtime_model["dayOfWeek"]["ctor"]

    assert Enum.any?(ticked.events, fn event ->
             event.type == "debugger.device_data" and
               (Map.get(event.payload, :request) || Map.get(event.payload, "request")) ==
                 "current_date_time"
           end)

    assert Enum.any?(ticked.events, fn event ->
             event.type == "debugger.update_in" and
               String.starts_with?(
                 Map.get(event.payload, :message) || Map.get(event.payload, "message") || "",
                 "CurrentDateTime "
               )
           end)
  end

  test "tick resolves minute-change subscription trigger message" do
    slug = "sim-minute-change-#{System.unique_integer([:positive])}"

    source = """
    module MinuteChangeSnap exposing (..)

    import Pebble.Events as PebbleEvents

    type Msg
        = MinuteChanged Int
        | Tick

    init _ =
        ( { count = 0 }, Cmd.none )

    update msg model =
        case msg of
            MinuteChanged minute ->
                ( { model | count = minute }, Cmd.none )

            Tick ->
                ( model, Cmd.none )

    subscriptions _ =
        PebbleEvents.onMinuteChange MinuteChanged
    """

    {:ok, _} = Debugger.start_session(slug)

    {:ok, _} =
      Debugger.reload(slug, %{
        rel_path: "watch/MinuteChangeSnap.elm",
        source: source,
        reason: "minute_change_sub"
      })

    assert {:ok, ticked} = Debugger.tick(slug, %{target: "watch", count: 1})
    message = get_in(ticked, [:watch, :model, "runtime_last_message"]) || ""
    assert String.starts_with?(message, "MinuteChanged ")

    minute_value =
      message
      |> String.replace_prefix("MinuteChanged ", "")
      |> Integer.parse()
      |> case do
        {parsed, ""} -> parsed
        _ -> -1
      end

    assert minute_value in 0..59
  end

  test "tick prefers minute subscription payload over hour when both are present" do
    slug = "sim-minute-over-hour-#{System.unique_integer([:positive])}"

    source = """
    module MinuteOverHour exposing (..)

    import Pebble.Events as PebbleEvents
    import Pebble.Platform as PebblePlatform
    import Json.Decode as Decode

    type alias Model =
      { value : Int }

    type Msg
      = HourChanged Int
      | MinuteChanged Int

    init _ =
      ( { value = 0 }, Cmd.none )

    update msg model =
      case msg of
        HourChanged h ->
          ( { model | value = h }, Cmd.none )

        MinuteChanged m ->
          ( { model | value = m }, Cmd.none )

    subscriptions _ =
      PebbleEvents.batch
        [ PebbleEvents.onHourChange HourChanged
        , PebbleEvents.onMinuteChange MinuteChanged
        ]

    view _ =
      []

    main : Program Decode.Value Model Msg
    main =
      PebblePlatform.application
        { init = init
        , update = update
        , view = view
        , subscriptions = subscriptions
        }
    """

    {:ok, _} = Debugger.start_session(slug)

    {:ok, _} =
      Debugger.reload(slug, %{
        rel_path: "watch/MinuteOverHour.elm",
        source: source,
        reason: "minute_over_hour"
      })

    assert {:ok, ticked} = Debugger.tick(slug, %{target: "watch", count: 1})
    message = get_in(ticked, [:watch, :model, "runtime_last_message"]) || ""
    assert String.starts_with?(message, "MinuteChanged ")
  end

  test "reload fulfills init current date/time device requests before steady-state minute ticks" do
    slug = "sim-init-current-datetime-#{System.unique_integer([:positive])}"

    source =
      File.read!(Path.join(["priv", "project_templates", "watchface_analog", "src", "Main.elm"]))

    {:ok, _} = Debugger.start_session(slug)

    {:ok, reloaded} =
      Debugger.reload(slug, %{
        rel_path: "watch/src/Main.elm",
        source: source,
        reason: "init_current_datetime",
        source_root: "watch"
      })

    preview = get_in(reloaded, [:watch, :model, "debugger_device_current_date_time"]) || %{}
    runtime_model = get_in(reloaded, [:watch, :model, "runtime_model"]) || %{}

    assert is_integer(preview["hour"])
    assert is_integer(preview["minute"])
    assert runtime_model["hour"] == preview["hour"]
    assert runtime_model["minute"] == preview["minute"]
    assert is_integer(runtime_model["screenW"])
    assert is_integer(runtime_model["screenH"])

    init_event =
      Enum.find(reloaded.events, fn event ->
        event.type == "debugger.init_in" and
          (Map.get(event.payload, :target) || Map.get(event.payload, "target")) == "watch"
      end)

    current_datetime_event =
      Enum.find(reloaded.events, fn event ->
        event.type == "debugger.update_in" and
          String.starts_with?(
            Map.get(event.payload, :message) || Map.get(event.payload, "message") || "",
            "CurrentDateTime "
          )
      end)

    assert init_event
    assert current_datetime_event
    assert init_event.seq < current_datetime_event.seq
    assert get_in(init_event, [:watch, :model, "runtime_model", "hour"]) == 12
    assert get_in(init_event, [:watch, :model, "runtime_model", "minute"]) == 0

    view_output = get_in(reloaded, [:watch, :model, "runtime_view_output"]) || []

    refute Enum.any?(view_output, fn row -> row["kind"] == "unresolved" end)
    assert Enum.count(view_output, fn row -> row["kind"] == "line" end) == 2

    nodes = collect_view_nodes(reloaded.watch.view_tree)
    assert Enum.count(nodes, fn node -> node["type"] == "line" end) == 2
    assert Enum.any?(nodes, fn node -> node["type"] == "circle" end)
    assert Enum.count(nodes, fn node -> node["type"] == "pixel" end) == 4

    assert {:ok, ticked} = Debugger.tick(slug, %{target: "watch", count: 1})

    assert String.starts_with?(
             get_in(ticked, [:watch, :model, "runtime_last_message"]) || "",
             "MinuteChanged "
           )

    assert preview["hour"] in 0..23
    assert preview["minute"] in 0..59
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

    assert get_in(reloaded, [:watch, :view_tree, "type"]) == "windowStack"

    assert reloaded.watch.view_tree
           |> collect_view_nodes()
           |> Enum.any?(fn node ->
             node["type"] == "textLabel" and node["text"] == preview["string"]
           end)
  end

  test "reload refires init current date/time device requests even after previous init response" do
    slug = "sim-init-current-datetime-refire-#{System.unique_integer([:positive])}"

    source =
      File.read!(Path.join(["priv", "project_templates", "watchface_analog", "src", "Main.elm"]))

    {:ok, _} = Debugger.start_session(slug)

    {:ok, first_reload} =
      Debugger.reload(slug, %{
        rel_path: "watch/src/Main.elm",
        source: source,
        reason: "init_current_datetime_first",
        source_root: "watch"
      })

    first_seq = first_reload.seq

    assert Enum.any?(first_reload.events, fn event ->
             event.type == "debugger.update_in" and
               String.starts_with?(
                 Map.get(event.payload, :message) || Map.get(event.payload, "message") || "",
                 "CurrentDateTime "
               )
           end)

    {:ok, second_reload} =
      Debugger.reload(slug, %{
        rel_path: "watch/src/Main.elm",
        source: source,
        reason: "init_current_datetime_second",
        source_root: "watch"
      })

    assert Enum.any?(second_reload.events, fn event ->
             event.seq > first_seq and event.type == "debugger.update_in" and
               String.starts_with?(
                 Map.get(event.payload, :message) || Map.get(event.payload, "message") || "",
                 "CurrentDateTime "
               )
           end)
  end

  test "watchface digital source-only runtime does not invent launch model aliases" do
    slug = "sim-watchface-centered-#{System.unique_integer([:positive])}"

    source =
      File.read!(Path.join(["priv", "project_templates", "watchface_digital", "src", "Main.elm"]))

    {:ok, _} = Debugger.start_session(slug)

    {:ok, _} =
      Debugger.reload(slug, %{
        rel_path: "watch/src/Main.elm",
        source: source,
        reason: "center_check",
        source_root: "watch"
      })

    assert {:ok, ticked} = Debugger.tick(slug, %{target: "watch", count: 1})
    runtime_model = get_in(ticked, [:watch, :model, "runtime_model"]) || %{}

    refute Map.has_key?(runtime_model, "width")
    refute Map.has_key?(runtime_model, "height")
    refute Map.has_key?(runtime_model, "screenWidth")
    refute Map.has_key?(runtime_model, "screenHeight")
  end

  test "tutorial watchface source-only init hydrates static constructors without inventing launch fields" do
    slug = "sim-tutorial-init-hydration-#{System.unique_integer([:positive])}"

    source =
      File.read!(
        Path.join(["priv", "project_templates", "watchface_tutorial_complete", "src", "Main.elm"])
      )

    {:ok, _} = Debugger.start_session(slug)

    {:ok, reloaded} =
      Debugger.reload(slug, %{
        rel_path: "watch/src/Main.elm",
        source: source,
        reason: "tutorial_init_hydration",
        source_root: "watch"
      })

    runtime_model = get_in(reloaded, [:watch, :model, "runtime_model"]) || %{}

    assert runtime_model["batteryLevel"] == %{"ctor" => "Just", "args" => [88]}
    assert runtime_model["connected"] == %{"ctor" => "Just", "args" => [true]}
    assert runtime_model["showDate"] == %{"ctor" => "Nothing", "args" => []}
    assert runtime_model["backgroundColor"] == %{"ctor" => "Nothing", "args" => []}
    assert runtime_model["textColor"] == %{"ctor" => "Nothing", "args" => []}
    assert runtime_model["condition"] == %{"ctor" => "Nothing", "args" => []}
    assert runtime_model["temperature"] == %{"ctor" => "Nothing", "args" => []}
    assert runtime_model["currentDateTime"] == %{"ctor" => "Nothing", "args" => []}
    refute Map.has_key?(runtime_model, "width")
    refute Map.has_key?(runtime_model, "height")
    refute Map.has_key?(runtime_model, "screenWidth")
    refute Map.has_key?(runtime_model, "screenHeight")
    refute Map.has_key?(runtime_model, "hour")
    refute Map.has_key?(runtime_model, "dayOfWeek")
  end

  test "tutorial watchface init emits platform and companion command events" do
    slug = "sim-tutorial-init-events-#{System.unique_integer([:positive])}"

    source =
      File.read!(
        Path.join(["priv", "project_templates", "watchface_tutorial_complete", "src", "Main.elm"])
      )

    {:ok, _} = Debugger.start_session(slug)

    {:ok, reloaded} =
      Debugger.reload(slug, %{
        rel_path: "watch/src/Main.elm",
        source: source,
        reason: "tutorial_init_events",
        source_root: "watch"
      })

    timeline =
      reloaded.debugger_timeline
      |> Enum.sort_by(& &1.seq)
      |> Enum.map(&{&1.target, &1.message, &1.message_source})

    assert Enum.any?(timeline, fn
             {"watch", "BatteryLevelChanged " <> _, "init_device_data"} -> true
             _ -> false
           end)

    assert {"watch", "ConnectionStatusChanged True", "init_device_data"} in timeline
    assert {"protocol", "RequestWeather CurrentLocation", "protocol_rx"} in timeline

    runtime_model = get_in(reloaded, [:watch, :model, "runtime_model"]) || %{}
    assert runtime_model["batteryLevel"] == %{"ctor" => "Just", "args" => [88]}
    assert runtime_model["connected"] == %{"ctor" => "Just", "args" => [true]}
  end

  test "tutorial watchface request weather carries structured protocol payload" do
    slug = "sim-tutorial-weather-roundtrip-#{System.unique_integer([:positive])}"

    companion_source =
      File.read!(Path.expand("priv/pebble_app_template/src/elm/CompanionApp.elm", File.cwd!()))

    watch_source =
      File.read!(
        Path.join(["priv", "project_templates", "watchface_tutorial_complete", "src", "Main.elm"])
      )

    {:ok, _} = Debugger.start_session(slug)

    {:ok, _} =
      Debugger.reload(slug, %{
        rel_path: "src/CompanionApp.elm",
        source: companion_source,
        reason: "tutorial_companion_bootstrap",
        source_root: "protocol"
      })

    {:ok, reloaded} =
      Debugger.reload(slug, %{
        rel_path: "watch/src/Main.elm",
        source: watch_source,
        reason: "tutorial_weather_roundtrip",
        source_root: "watch"
      })

    protocol_events =
      reloaded.events
      |> Enum.filter(&(&1.type in ["debugger.protocol_tx", "debugger.protocol_rx"]))
      |> Enum.map(& &1.payload)

    assert Enum.any?(protocol_events, fn payload ->
             payload[:from] == "watch" and payload[:to] == "companion" and
               payload[:message] == "RequestWeather CurrentLocation" and
               payload[:message_value] == %{
                 "ctor" => "RequestWeather",
                 "args" => [%{"ctor" => "CurrentLocation", "args" => []}]
               }
           end)

    timeline =
      reloaded.debugger_timeline
      |> Enum.map(&{&1.target, &1.message, &1.message_source})

    assert {"protocol", "FromWatch (Ok (RequestWeather CurrentLocation))", "protocol_rx"} in timeline

    companion_runtime = get_in(reloaded, [:companion, :model, "runtime_model"]) || %{}
    assert companion_runtime["protocol_message_count"] == 1
    assert companion_runtime["protocol_last_inbound_message"] == "RequestWeather CurrentLocation"
  end

  test "tutorial watchface minute subscription does not replay sibling device commands" do
    slug = "sim-tutorial-minute-no-sibling-device-#{System.unique_integer([:positive])}"

    source =
      File.read!(
        Path.join(["priv", "project_templates", "watchface_tutorial_complete", "src", "Main.elm"])
      )

    {:ok, _} = Debugger.start_session(slug)

    {:ok, reloaded} =
      Debugger.reload(slug, %{
        rel_path: "watch/src/Main.elm",
        source: source,
        reason: "tutorial_minute_no_sibling_device",
        source_root: "watch"
      })

    reloaded_seq = reloaded.seq

    assert {:ok, triggered} =
             Debugger.inject_trigger(slug, %{
               target: "watch",
               trigger: "on_minute_change",
               message: "MinuteChanged 17"
             })

    new_timeline =
      triggered.debugger_timeline
      |> Enum.filter(&(&1.raw_seq > reloaded_seq))
      |> Enum.map(&{&1.target, &1.message, &1.message_source})

    assert {"watch", "MinuteChanged 17", "subscription_trigger"} in new_timeline

    refute Enum.any?(new_timeline, fn
             {"watch", "BatteryLevelChanged " <> _, "device_data"} -> true
             {"watch", "ConnectionStatusChanged " <> _, "device_data"} -> true
             _ -> false
           end)
  end

  test "tutorial watchface normalizes runtime Maybe tuple for currentDateTime" do
    previous_config = Application.get_env(:ide, Debugger, [])

    Application.put_env(
      :ide,
      Debugger,
      Keyword.put(previous_config, :runtime_executor_module, TupleMaybeRuntimeExecutor)
    )

    on_exit(fn -> Application.put_env(:ide, Debugger, previous_config) end)

    slug = "sim-tutorial-current-datetime-maybe-#{System.unique_integer([:positive])}"

    source =
      File.read!(
        Path.join(["priv", "project_templates", "watchface_tutorial_complete", "src", "Main.elm"])
      )

    {:ok, _} = Debugger.start_session(slug)

    {:ok, reloaded} =
      Debugger.reload(slug, %{
        rel_path: "watch/src/Main.elm",
        source: source,
        reason: "tutorial_current_datetime_maybe",
        source_root: "watch"
      })

    runtime_model = get_in(reloaded, [:watch, :model, "runtime_model"]) || %{}

    assert %{
             "ctor" => "Just",
             "args" => [
               %{
                 "year" => 2026,
                 "month" => 4,
                 "day" => 25,
                 "dayOfWeek" => %{"ctor" => "Sat", "args" => []},
                 "hour" => 21,
                 "minute" => 19,
                 "second" => 0,
                 "utcOffsetMinutes" => -360
               }
             ]
           } = runtime_model["currentDateTime"]
  end

  test "tutorial watchface hydrates battery Maybe when runtime reports nil" do
    previous_config = Application.get_env(:ide, Debugger, [])

    Application.put_env(
      :ide,
      Debugger,
      Keyword.put(previous_config, :runtime_executor_module, NilMaybeRuntimeExecutor)
    )

    on_exit(fn -> Application.put_env(:ide, Debugger, previous_config) end)

    slug = "sim-tutorial-battery-nil-maybe-#{System.unique_integer([:positive])}"

    source =
      File.read!(
        Path.join(["priv", "project_templates", "watchface_tutorial_complete", "src", "Main.elm"])
      )

    {:ok, _} = Debugger.start_session(slug)

    {:ok, reloaded} =
      Debugger.reload(slug, %{
        rel_path: "watch/src/Main.elm",
        source: source,
        reason: "tutorial_battery_nil_maybe",
        source_root: "watch"
      })

    runtime_model = get_in(reloaded, [:watch, :model, "runtime_model"]) || %{}
    assert runtime_model["batteryLevel"] == %{"ctor" => "Just", "args" => [88]}
  end

  test "tutorial watchface normalizes optimized Maybe fields from runtime model contract" do
    previous_config = Application.get_env(:ide, Debugger, [])

    Application.put_env(
      :ide,
      Debugger,
      Keyword.put(previous_config, :runtime_executor_module, MaybeShapeRuntimeExecutor)
    )

    on_exit(fn -> Application.put_env(:ide, Debugger, previous_config) end)

    slug = "sim-tutorial-maybe-shapes-#{System.unique_integer([:positive])}"

    source =
      File.read!(
        Path.join(["priv", "project_templates", "watchface_tutorial_complete", "src", "Main.elm"])
      )

    {:ok, _} = Debugger.start_session(slug)

    {:ok, reloaded} =
      Debugger.reload(slug, %{
        rel_path: "watch/src/Main.elm",
        source: source,
        reason: "tutorial_maybe_shapes",
        source_root: "watch"
      })

    runtime_model = get_in(reloaded, [:watch, :model, "runtime_model"]) || %{}

    assert runtime_model["backgroundColor"] == %{"ctor" => "Nothing", "args" => []}
    assert runtime_model["batteryLevel"] == %{"ctor" => "Just", "args" => [88]}
    assert runtime_model["connected"] == %{"ctor" => "Just", "args" => [true]}

    assert runtime_model["condition"] == %{
             "ctor" => "Just",
             "args" => [%{"ctor" => "Clear", "args" => []}]
           }

    assert runtime_model["temperature"] == %{
             "ctor" => "Just",
             "args" => [%{"ctor" => "Celsius", "args" => [4]}]
           }
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
             is_map(row) and row["kind"] == "line" and row["x1"] == 72 and row["y2"] == 35
           end)
  end

  test "inject_trigger applies subscription-style button trigger with deterministic events" do
    slug = "sim-trigger-#{System.unique_integer([:positive])}"

    source = """
    module TriggerSnap exposing (..)

    type Msg
      = Inc
      | Dec
      | ButtonUp
      | ButtonDown

    subscriptions model = Sub.none
    """

    {:ok, _} = Debugger.start_session(slug)

    {:ok, _} =
      Debugger.reload(slug, %{
        rel_path: "watch/TriggerSnap.elm",
        source: source,
        reason: "trigger_base"
      })

    assert {:ok, trigger_rows} = Debugger.available_triggers(slug, %{"target" => "watch"})
    assert Enum.any?(trigger_rows, fn row -> is_binary(row[:trigger]) and row[:trigger] != "" end)

    assert {:ok, triggered} =
             Debugger.inject_trigger(slug, %{
               target: "watch",
               trigger: "button_up"
             })

    assert get_in(triggered, [:watch, :model, "runtime_last_message"]) == "ButtonUp"
    assert get_in(triggered, [:watch, :model, "runtime_message_source"]) == "subscription_trigger"
    assert get_in(triggered, [:watch, :model, "runtime_model_source"]) == "step_message"

    assert trigger_exec =
             Enum.find(
               triggered.events,
               &(&1.type == "debugger.runtime_exec" and
                   (Map.get(&1.payload, :trigger) || Map.get(&1.payload, "trigger")) ==
                     "subscription_trigger")
             )

    assert trigger_exec.payload.message_source == "subscription_trigger"
    assert Enum.any?(triggered.events, &(&1.type == "debugger.update_in"))
    assert Enum.any?(triggered.events, &(&1.type == "debugger.view_render"))
  end

  test "inject_trigger applies structured accelerometer subscription payload" do
    previous_config = Application.get_env(:ide, Debugger, [])

    Application.put_env(
      :ide,
      Debugger,
      Keyword.put(previous_config, :runtime_executor_module, AccelRuntimeExecutor)
    )

    on_exit(fn -> Application.put_env(:ide, Debugger, previous_config) end)

    slug = "sim-accel-trigger-#{System.unique_integer([:positive])}"

    source = """
    module AccelTrigger exposing (..)

    import Json.Decode as Decode
    import Pebble.Accel as Accel
    import Pebble.Platform as Platform
    import Pebble.Ui as Ui
    import Pebble.Ui.Color as Color

    type alias Model =
        { x : Int
        , y : Int
        , z : Int
        }

    type Msg
        = AccelData Accel.Sample

    init _ =
        ( { x = 0, y = 0, z = 1000 }, Cmd.none )

    update msg model =
        case msg of
            AccelData sample ->
                ( { model | x = sample.x, y = sample.y, z = sample.z }, Cmd.none )

    subscriptions _ =
        Accel.onData Accel.defaultConfig AccelData

    view _ =
        Ui.toUiNode [ Ui.clear Color.white ]

    main : Program Decode.Value Model Msg
    main =
        Platform.application
            { init = init
            , update = update
            , view = view
            , subscriptions = subscriptions
            }
    """

    {:ok, _} = Debugger.start_session(slug)

    {:ok, _} =
      Debugger.reload(slug, %{
        rel_path: "watch/AccelTrigger.elm",
        source: source,
        reason: "accel_trigger_base"
      })

    assert {:ok, triggered} =
             Debugger.inject_trigger(slug, %{
               target: "watch",
               trigger: "on_accel",
               message: "AccelData",
               message_value: %{"x" => 120, "y" => -340, "z" => 930}
             })

    runtime_model = get_in(triggered, [:watch, :model, "runtime_model"]) || %{}
    assert runtime_model["x"] == 120
    assert runtime_model["y"] == -340
    assert runtime_model["z"] == 930
    assert get_in(triggered, [:watch, :model, "runtime_last_message"]) == "AccelData"
  end

  test "disabled subscription trigger cannot be injected until re-enabled" do
    slug = "sim-disabled-subscription-#{System.unique_integer([:positive])}"

    source = """
    module DisabledSubscription exposing (..)

    import Pebble.Events as Events

    type Msg
      = Tick

    init _ =
      ( { count = 0 }, Cmd.none )

    update msg model =
      case msg of
        Tick ->
          ( { model | count = model.count + 1 }, Cmd.none )

    subscriptions _ =
      Events.onTick Tick
    """

    {:ok, _} = Debugger.start_session(slug)

    {:ok, _} =
      Debugger.reload(slug, %{
        rel_path: "watch/DisabledSubscription.elm",
        source: source,
        reason: "disabled_subscription"
      })

    assert {:ok, disabled} =
             Debugger.set_subscription_enabled(slug, %{
               target: "watch",
               trigger: "on_tick",
               enabled: "false"
             })

    disabled_seq = disabled.seq

    assert {:ok, blocked} =
             Debugger.inject_trigger(slug, %{
               target: "watch",
               trigger: "on_tick",
               message: "Tick"
             })

    refute Enum.any?(blocked.events, fn event ->
             event.seq > disabled_seq and event.type == "debugger.update_in" and
               (Map.get(event.payload, :message) || Map.get(event.payload, "message")) == "Tick"
           end)

    assert {:ok, enabled} =
             Debugger.set_subscription_enabled(slug, %{
               target: "watch",
               trigger: "on_tick",
               enabled: "true"
             })

    enabled_seq = enabled.seq

    assert {:ok, triggered} =
             Debugger.inject_trigger(slug, %{
               target: "watch",
               trigger: "on_tick",
               message: "Tick"
             })

    assert Enum.any?(triggered.events, fn event ->
             event.seq > enabled_seq and event.type == "debugger.update_in" and
               (Map.get(event.payload, :message) || Map.get(event.payload, "message")) == "Tick"
           end)
  end

  test "inject_trigger prefers non-tick message for button triggers when available" do
    slug = "sim-trigger-prefer-button-#{System.unique_integer([:positive])}"

    source = """
    module TriggerPreferButton exposing (..)

    type Msg
      = Tick
      | ButtonPressed

    subscriptions model = Sub.none
    """

    {:ok, _} = Debugger.start_session(slug)

    {:ok, _} =
      Debugger.reload(slug, %{
        rel_path: "watch/TriggerPreferButton.elm",
        source: source,
        reason: "trigger_prefer_button_base"
      })

    assert {:ok, triggered} =
             Debugger.inject_trigger(slug, %{
               target: "watch",
               trigger: "button_up"
             })

    assert get_in(triggered, [:watch, :model, "runtime_last_message"]) == "ButtonPressed"
  end

  test "available_triggers prefers structured subscription callback constructors" do
    slug = "sim-trigger-subscription-callbacks-#{System.unique_integer([:positive])}"

    source = """
    module TriggerSubscriptions exposing (..)

    type Msg
      = Tick
      | MinuteChanged Int

    init _ =
      ( {}, Cmd.none )

    update msg model =
      ( model, Cmd.none )

    subscriptions _ =
      Evts.batch [ Evts.onTick Tick, Evts.onMinuteChange MinuteChanged ]
    """

    {:ok, _} = Debugger.start_session(slug)

    {:ok, _} =
      Debugger.reload(slug, %{
        rel_path: "watch/TriggerSubscriptions.elm",
        source: source,
        reason: "subscription_trigger_callbacks"
      })

    assert {:ok, trigger_rows} = Debugger.available_triggers(slug, %{"target" => "watch"})

    assert Enum.any?(trigger_rows, fn row ->
             row.trigger == "on_tick" and row.message == "Tick"
           end)

    assert Enum.any?(trigger_rows, fn row ->
             row.trigger == "on_minute_change" and row.message == "MinuteChanged"
           end)

    assert Enum.all?(trigger_rows, &(&1.source == "subscription"))
    refute Enum.any?(trigger_rows, &(&1.trigger == "button_up"))
  end

  test "inject_trigger attaches local hour to HourChanged when trigger is on_hour_change" do
    slug = "sim-hour-change-payload-#{System.unique_integer([:positive])}"

    source = """
    module HourChangePayload exposing (..)

    import Pebble.Events as PebbleEvents
    import Pebble.Platform as PebblePlatform
    import Json.Decode as Decode

    type alias Model =
      { hour : Int }

    type Msg
      = HourChanged Int

    init _ =
      ( { hour = 0 }, Cmd.none )

    update msg model =
      case msg of
        HourChanged h ->
          ( { model | hour = h }, Cmd.none )

    subscriptions _ =
      PebbleEvents.onHourChange HourChanged

    view _ =
      []

    main : Program Decode.Value Model Msg
    main =
      PebblePlatform.application
        { init = init
        , update = update
        , view = view
        , subscriptions = subscriptions
        }
    """

    {:ok, _} = Debugger.start_session(slug)

    {:ok, _} =
      Debugger.reload(slug, %{
        rel_path: "watch/HourChangePayload.elm",
        source: source,
        reason: "hour_change_payload"
      })

    assert {:ok, rows} = Debugger.available_triggers(slug, %{"target" => "watch"})
    row = Enum.find(rows, &(&1.trigger == "on_hour_change" and &1.message == "HourChanged"))
    assert row

    assert {:ok, after_inject} =
             Debugger.inject_trigger(slug, %{
               target: "watch",
               trigger: row.trigger,
               message: row.message
             })

    msg = get_in(after_inject, [:watch, :model, "runtime_last_message"]) || ""
    assert String.match?(msg, ~r/^HourChanged [0-9]{1,2}$/)

    hour_str = String.replace_leading(msg, "HourChanged ", "")
    {hour, ""} = Integer.parse(hour_str)
    assert hour in 0..23
  end

  test "inject_trigger attaches system payloads for battery and connection subscriptions" do
    slug = "sim-system-subscription-payloads-#{System.unique_integer([:positive])}"

    source = """
    module SystemPayloadSubscriptions exposing (..)

    import Json.Decode as Decode
    import Pebble.Platform as PebblePlatform
    import Pebble.System as PebbleSystem

    type alias Model =
      { battery : Int
      , connected : Bool
      }

    type Msg
      = BatteryChanged Int
      | ConnectionChanged Bool

    init _ =
      ( { battery = 0, connected = False }, Cmd.none )

    update msg model =
      case msg of
        BatteryChanged level ->
          ( { model | battery = level }, Cmd.none )

        ConnectionChanged connected ->
          ( { model | connected = connected }, Cmd.none )

    subscriptions _ =
      Sub.batch
        [ PebbleSystem.onBatteryChange BatteryChanged
        , PebbleSystem.onConnectionChange ConnectionChanged
        ]

    view _ =
      []

    main : Program Decode.Value Model Msg
    main =
      PebblePlatform.application
        { init = init
        , update = update
        , view = view
        , subscriptions = subscriptions
        }
    """

    {:ok, _} = Debugger.start_session(slug)

    {:ok, _} =
      Debugger.reload(slug, %{
        rel_path: "watch/SystemPayloadSubscriptions.elm",
        source: source,
        reason: "system_subscription_payloads"
      })

    assert {:ok, rows} = Debugger.available_triggers(slug, %{"target" => "watch"})
    battery_row = Enum.find(rows, &(&1.trigger == "on_battery_change"))
    connection_row = Enum.find(rows, &(&1.trigger == "on_connection_change"))

    assert battery_row.message == "BatteryChanged"
    assert connection_row.message == "ConnectionChanged"

    assert {:ok, after_battery} =
             Debugger.inject_trigger(slug, %{
               target: "watch",
               trigger: battery_row.trigger,
               message: battery_row.message
             })

    assert get_in(after_battery, [:watch, :model, "runtime_last_message"]) == "BatteryChanged 88"

    assert {:ok, after_connection} =
             Debugger.inject_trigger(slug, %{
               target: "watch",
               trigger: connection_row.trigger,
               message: connection_row.message
             })

    assert get_in(after_connection, [:watch, :model, "runtime_last_message"]) ==
             "ConnectionChanged False"
  end

  test "semantic debugger timeline keeps contiguous numbering and after-call snapshots" do
    slug = "sim-debugger-timeline-#{System.unique_integer([:positive])}"

    source = """
    module DebuggerTimeline exposing (..)

    import Pebble.Events as PebbleEvents

    type alias Model =
      { hour : Int }

    type Msg
      = HourChanged Int

    init _ =
      ( { hour = 0 }, Cmd.none )

    update msg model =
      case msg of
        HourChanged h ->
          ( { model | hour = h }, Cmd.none )

    subscriptions _ =
      PebbleEvents.onHourChange HourChanged
    """

    {:ok, _} = Debugger.start_session(slug)

    {:ok, reloaded} =
      Debugger.reload(slug, %{
        rel_path: "watch/DebuggerTimeline.elm",
        source: source,
        reason: "debugger_timeline"
      })

    assert [%{seq: 1, type: "init", target: "watch", message: "init"}] =
             reloaded.debugger_timeline

    assert {:ok, rows} = Debugger.available_triggers(slug, %{"target" => "watch"})
    row = Enum.find(rows, &(&1.trigger == "on_hour_change" and &1.message == "HourChanged"))
    assert row

    assert {:ok, after_inject} =
             Debugger.inject_trigger(slug, %{
               target: "watch",
               trigger: row.trigger,
               message: row.message
             })

    debugger_rows = after_inject.debugger_timeline
    assert Enum.map(debugger_rows, & &1.seq) == Enum.to_list(length(debugger_rows)..1)
    assert Enum.any?(debugger_rows, &(&1.type == "init" and &1.seq == 1))

    watch_row =
      Enum.find(debugger_rows, fn row ->
        row.target == "watch" and String.starts_with?(row.message, "HourChanged ")
      end)

    assert watch_row
    assert watch_row.raw_seq > watch_row.seq
    assert get_in(watch_row.watch, [:model, "runtime_last_message"]) == watch_row.message
    assert is_map(watch_row.companion)
  end

  test "subscription trigger candidates ignore Sub.none" do
    slug = "sim-trigger-sub-none-#{System.unique_integer([:positive])}"

    source = """
    module TriggerSubNone exposing (..)

    type Msg
      = Tick

    init _ =
      ( {}, Cmd.none )

    update msg model =
      ( model, Cmd.none )

    subscriptions _ =
      Sub.none
    """

    {:ok, _} = Debugger.start_session(slug)

    {:ok, _} =
      Debugger.reload(slug, %{
        rel_path: "watch/TriggerSubNone.elm",
        source: source,
        reason: "subscription_trigger_sub_none"
      })

    assert {:ok, trigger_rows} = Debugger.available_triggers(slug, %{"target" => "watch"})

    refute Enum.any?(trigger_rows, &(&1.source == "subscription"))
  end

  test "start_auto_tick and stop_auto_tick drive periodic ingress events" do
    slug = "sim-auto-tick-#{System.unique_integer([:positive])}"
    {:ok, _} = Debugger.start_session(slug)

    assert {:ok, started} =
             Debugger.start_auto_tick(slug, %{
               target: "watch",
               interval_ms: 120,
               count: 1
             })

    assert started.auto_tick.enabled == true
    assert started.auto_tick.interval_ms == 120
    assert started.auto_tick.target == "watch"

    Process.sleep(280)

    assert {:ok, stopped} = Debugger.stop_auto_tick(slug)
    assert stopped.auto_tick.enabled == false

    assert Enum.any?(stopped.events, &(&1.type == "debugger.tick_auto"))
    assert Enum.any?(stopped.events, &(&1.type == "debugger.tick"))
  end

  test "set_auto_fire toggles natural watch and companion ingress targets" do
    slug = "sim-auto-fire-#{System.unique_integer([:positive])}"
    {:ok, _} = Debugger.start_session(slug)

    assert {:ok, watch_on} =
             Debugger.set_auto_fire(slug, %{
               target: "watch",
               enabled: "true"
             })

    assert watch_on.auto_tick.enabled == true
    assert watch_on.auto_tick.targets == ["watch"]

    assert {:ok, both_on} =
             Debugger.set_auto_fire(slug, %{
               target: "protocol",
               enabled: "true"
             })

    assert both_on.auto_tick.enabled == true
    assert both_on.auto_tick.targets == ["watch", "protocol"]

    assert {:ok, companion_only} =
             Debugger.set_auto_fire(slug, %{
               target: "watch"
             })

    assert companion_only.auto_tick.enabled == true
    assert companion_only.auto_tick.targets == ["protocol"]

    assert {:ok, all_off} =
             Debugger.set_auto_fire(slug, %{
               target: "protocol"
             })

    assert all_off.auto_tick.enabled == false
    assert all_off.auto_tick.targets == []

    assert Enum.any?(all_off.events, fn event ->
             event.type == "debugger.tick_auto" and
               (Map.get(event.payload, :action) || Map.get(event.payload, "action")) ==
                 "set_auto_fire"
           end)
  end

  test "set_auto_fire can enable one subscription trigger without firing siblings" do
    slug = "sim-auto-fire-single-subscription-#{System.unique_integer([:positive])}"

    source = """
    module AutoFireSingleSubscription exposing (..)

    type Msg
      = Tick
      | MinuteChanged Int

    init _ =
      ( {}, Cmd.none )

    update msg model =
      ( model, Cmd.none )

    subscriptions _ =
      Evts.batch [ Evts.onTick Tick, Evts.onMinuteChange MinuteChanged ]
    """

    {:ok, _} = Debugger.start_session(slug)

    {:ok, _} =
      Debugger.reload(slug, %{
        rel_path: "watch/AutoFireSingleSubscription.elm",
        source: source,
        reason: "auto_fire_single_subscription"
      })

    assert {:ok, enabled} =
             Debugger.set_auto_fire(slug, %{
               target: "watch",
               trigger: "on_tick",
               enabled: "true"
             })

    assert enabled.auto_tick.enabled == true
    assert enabled.auto_tick.targets == ["watch"]
    assert enabled.auto_tick.subscriptions == [%{"target" => "watch", "trigger" => "on_tick"}]

    enabled_seq = enabled.seq
    Process.sleep(1_150)

    assert {:ok, stopped} = Debugger.stop_auto_tick(slug)

    assert Enum.any?(stopped.events, fn event ->
             event.seq > enabled_seq and event.type == "debugger.update_in" and
               (Map.get(event.payload, :message) || Map.get(event.payload, "message")) == "Tick"
           end)

    refute Enum.any?(stopped.events, fn event ->
             message = Map.get(event.payload, :message) || Map.get(event.payload, "message") || ""

             event.seq > enabled_seq and event.type == "debugger.update_in" and
               String.starts_with?(message, "MinuteChanged ")
           end)
  end

  test "set_auto_fire does not synthesize Tick when target has no parsed subscriptions" do
    slug = "sim-auto-fire-no-subscriptions-#{System.unique_integer([:positive])}"

    source = """
    module AutoFireSubNone exposing (..)

    type Msg
      = Tick

    init _ =
      ( {}, Cmd.none )

    update msg model =
      ( model, Cmd.none )

    subscriptions _ =
      Sub.none
    """

    {:ok, _} = Debugger.start_session(slug)

    {:ok, _} =
      Debugger.reload(slug, %{
        rel_path: "watch/AutoFireSubNone.elm",
        source: source,
        reason: "auto_fire_sub_none"
      })

    assert {:ok, enabled} =
             Debugger.set_auto_fire(slug, %{
               target: "watch",
               enabled: "true"
             })

    enabled_seq = enabled.seq
    Process.sleep(1_150)

    assert {:ok, stopped} = Debugger.stop_auto_tick(slug)

    refute Enum.any?(stopped.events, fn event ->
             event.seq > enabled_seq and event.type == "debugger.update_in" and
               (Map.get(event.payload, :message) || Map.get(event.payload, "message")) == "Tick"
           end)
  end

  test "set_auto_fire does not fire minute or hour change subscriptions immediately" do
    wait_until_stable_minute()

    slug = "sim-auto-fire-clock-change-#{System.unique_integer([:positive])}"

    source =
      File.read!(Path.join(["priv", "project_templates", "watchface_analog", "src", "Main.elm"]))

    {:ok, _} = Debugger.start_session(slug)

    {:ok, _} =
      Debugger.reload(slug, %{
        rel_path: "watch/src/Main.elm",
        source: source,
        reason: "auto_fire_clock_change",
        source_root: "watch"
      })

    assert {:ok, enabled} =
             Debugger.set_auto_fire(slug, %{
               target: "watch",
               enabled: "true"
             })

    enabled_seq = enabled.seq
    Process.sleep(1_150)

    assert {:ok, stopped} = Debugger.stop_auto_tick(slug)

    refute Enum.any?(stopped.events, fn event ->
             message = Map.get(event.payload, :message) || Map.get(event.payload, "message") || ""

             event.seq > enabled_seq and event.type == "debugger.update_in" and
               (String.starts_with?(message, "MinuteChanged ") or
                  String.starts_with?(message, "HourChanged "))
           end)
  end

  test "replay_recent reapplies recent update messages oldest-to-newest" do
    slug = "sim-replay-#{System.unique_integer([:positive])}"

    source = """
    module ReplaySnap exposing (..)

    type Msg
        = Inc
        | Dec

    init _ =
        ( { n = 1 }, Cmd.none )

    view m =
        Ui.root []
    """

    {:ok, _} = Debugger.start_session(slug)

    {:ok, _} =
      Debugger.reload(slug, %{
        rel_path: "watch/ReplaySnap.elm",
        source: source,
        reason: "replay_base"
      })

    {:ok, stepped0} = Debugger.step(slug, %{target: "watch", count: 3})
    seq_before_latest_step = stepped0.seq
    {:ok, _} = Debugger.step(slug, %{target: "watch", count: 1})

    assert {:ok, replayed} =
             Debugger.replay_recent(slug, %{
               target: "watch",
               count: 1,
               cursor_seq: seq_before_latest_step
             })

    assert get_in(replayed, [:watch, :model, "runtime_model", "n"]) == 1
    assert get_in(replayed, [:watch, :model, "runtime_last_message"]) == "Inc"

    assert replay_exec =
             Enum.find(
               replayed.events,
               &(&1.type == "debugger.runtime_exec" and
                   (Map.get(&1.payload, :trigger) || Map.get(&1.payload, "trigger")) == "replay")
             )

    assert replay_exec.payload.trigger == "replay"

    refute Enum.any?(replayed.events, fn event ->
             event.type in ["debugger.protocol_tx", "debugger.protocol_rx"] and
               (Map.get(event.payload, :trigger) || Map.get(event.payload, "trigger")) == "replay"
           end)

    replay_event = Enum.find(replayed.events, &(&1.type == "debugger.replay"))
    assert is_map(replay_event)
    assert Map.get(replay_event.payload, :target) == "watch"
    assert Map.get(replay_event.payload, :replayed_count) == 1
    assert Map.get(replay_event.payload, :cursor_seq) == seq_before_latest_step
    assert Map.get(replay_event.payload, :replay_target_counts) == %{"watch" => 1}
    assert Map.get(replay_event.payload, :replay_message_counts) == %{"Inc" => 1}

    assert_replay_telemetry(replay_event.payload, %{
      mode: "unknown",
      source: "recent_query",
      drift_seq: 0,
      drift_band: "none",
      used_live_query: true,
      used_frozen_preview: false
    })

    assert [%{seq: preview_seq, target: "watch", message: "Inc"}] =
             Map.get(replay_event.payload, :replay_preview)

    assert is_integer(preview_seq)
    assert preview_seq <= seq_before_latest_step
  end

  test "replay_recent can apply exact frozen preview rows" do
    slug = "sim-replay-frozen-#{System.unique_integer([:positive])}"

    source = """
    module ReplayFrozen exposing (..)

    type Msg
        = Inc
        | Dec

    init _ =
        ( { n = 1 }, Cmd.none )

    view m =
        Ui.root []
    """

    {:ok, _} = Debugger.start_session(slug)

    {:ok, _} =
      Debugger.reload(slug, %{
        rel_path: "watch/ReplayFrozen.elm",
        source: source,
        reason: "replay_frozen_base"
      })

    {:ok, _} = Debugger.step(slug, %{target: "watch", message: "Inc", count: 1})
    {:ok, _} = Debugger.step(slug, %{target: "watch", message: "Dec", count: 1})
    {:ok, _} = Debugger.step(slug, %{target: "watch", message: "Inc", count: 1})

    assert {:ok, replayed} =
             Debugger.replay_recent(slug, %{
               count: 50,
               replay_rows: [%{seq: 123, target: "watch", message: "Dec"}]
             })

    assert get_in(replayed, [:watch, :model, "runtime_model", "n"]) == 1
    replay_event = Enum.find(replayed.events, &(&1.type == "debugger.replay"))
    assert replay_event.payload.replay_source == "frozen_preview"

    assert_replay_telemetry(replay_event.payload, %{
      mode: "unknown",
      source: "frozen_preview",
      drift_seq: 0,
      drift_band: "none",
      used_live_query: false,
      used_frozen_preview: true
    })

    assert replay_event.payload.requested_count == 1
    assert replay_event.payload.replayed_count == 1
    assert replay_event.payload.replay_message_counts == %{"Dec" => 1}
  end

  test "elmc ingest attaches diagnostic_preview to event payload for timeline export" do
    slug = "sim-evp-#{System.unique_integer([:positive])}"
    {:ok, _} = Debugger.start_session(slug)

    {:ok, _} =
      Debugger.ingest_elmc_check(slug, %{
        status: :ok,
        checked_path: ".",
        error_count: 0,
        warning_count: 0,
        diagnostics: [%{severity: "info", message: "all good", source: "elmc"}]
      })

    assert {:ok, st} = Debugger.snapshot(slug, event_limit: 5)
    ev = hd(st.events)
    assert ev.type == "debugger.elmc_check"
    prev = Map.get(ev.payload, :diagnostic_preview) || Map.get(ev.payload, "diagnostic_preview")
    assert is_list(prev)
    assert hd(prev)["message"] == "all good"
  end

  test "ingest_elmc_check stores elmc_diagnostic_preview when diagnostics given" do
    slug = "sim-diag-#{System.unique_integer([:positive])}"
    {:ok, _} = Debugger.start_session(slug)

    diag = %{
      severity: "error",
      message: "bad type",
      file: "src/M.elm",
      line: 3,
      column: 1,
      source: "elmc",
      warning_type: "lowerer-warning",
      warning_code: "constructor_payload_arity",
      warning_constructor: "Just",
      warning_expected_kind: "single",
      warning_has_arg_pattern: false
    }

    assert {:ok, _} =
             Debugger.ingest_elmc_check(slug, %{
               status: :error,
               checked_path: "/w",
               error_count: 1,
               warning_count: 0,
               diagnostics: [diag]
             })

    assert {:ok, st} = Debugger.snapshot(slug, event_limit: 5)
    [row] = get_in(st.watch, [:model, "elmc_diagnostic_preview"])
    assert row["message"] == "bad type"
    assert row["file"] == "src/M.elm"
    assert row["line"] == 3
    assert row["warning_type"] == "lowerer-warning"
    assert row["warning_code"] == "constructor_payload_arity"
    assert row["warning_constructor"] == "Just"
    assert row["warning_expected_kind"] == "single"
    assert row["warning_has_arg_pattern"] == false
  end

  test "ingest_elmc_check merges model fields and appends event when running" do
    slug = "sim-elmc-#{System.unique_integer([:positive])}"
    {:ok, _} = Debugger.start_session(slug)

    assert {:ok, _} =
             Debugger.ingest_elmc_check(slug, %{
               status: :ok,
               checked_path: "/tmp/ws",
               error_count: 0,
               warning_count: 2
             })

    assert {:ok, st} = Debugger.snapshot(slug, event_limit: 10)
    assert hd(st.events).type == "debugger.elmc_check"
    assert get_in(st.watch, [:model, "elmc_check_status"]) == "ok"
    assert get_in(st.watch, [:model, "elmc_warning_count"]) == 2
    assert get_in(st.watch, [:model, "elmc_checked_path"]) == "/tmp/ws"
  end

  test "ingest_elmc_compile merges model fields and appends event when running" do
    slug = "sim-elmc-compile-#{System.unique_integer([:positive])}"
    {:ok, _} = Debugger.start_session(slug)

    assert {:ok, _} =
             Debugger.ingest_elmc_compile(slug, %{
               status: :ok,
               compiled_path: "/tmp/compile",
               revision: "deadbeef",
               cached: true,
               error_count: 0,
               warning_count: 0
             })

    assert {:ok, st} = Debugger.snapshot(slug, event_limit: 10)
    assert hd(st.events).type == "debugger.elmc_compile"
    assert get_in(st.watch, [:model, "elmc_compile_status"]) == "ok"
    assert get_in(st.watch, [:model, "elmc_compile_revision"]) == "deadbeef"
    assert get_in(st.watch, [:model, "elmc_compile_cached"]) == "true"
  end

  test "ingest_elmc_compile scopes runtime artifacts to compiled source root" do
    slug = "sim-elmc-compile-artifacts-#{System.unique_integer([:positive])}"
    {:ok, _} = Debugger.start_session(slug)

    companion_core = %{"modules" => [%{"name" => "CompanionApp"}]}
    watch_core = %{"modules" => [%{"name" => "Main"}]}

    assert {:ok, _} =
             Debugger.ingest_elmc_compile(slug, %{
               status: :ok,
               compiled_path: "phone",
               revision: "companion",
               elm_executor_core_ir_b64:
                 :erlang.term_to_binary(companion_core) |> Base.encode64(),
               elm_executor_metadata: %{"target" => "phone"}
             })

    assert {:ok, st_after_companion} = Debugger.snapshot(slug, event_limit: 10)
    assert get_in(st_after_companion.companion, [:model, "elm_executor_core_ir_b64"])
    refute get_in(st_after_companion.watch, [:model, "elm_executor_core_ir_b64"])

    assert {:ok, st_after_watch} =
             Debugger.ingest_elmc_compile(slug, %{
               status: :ok,
               compiled_path: "watch",
               revision: "watch",
               elm_executor_core_ir_b64: :erlang.term_to_binary(watch_core) |> Base.encode64(),
               elm_executor_metadata: %{"target" => "watch"}
             })

    assert get_in(st_after_watch.watch, [:model, "elm_executor_core_ir_b64"])

    assert get_in(st_after_watch.companion, [:model, "elm_executor_core_ir_b64"]) ==
             get_in(st_after_companion.companion, [:model, "elm_executor_core_ir_b64"])
  end

  test "ingest_elmc_manifest merges model fields and appends event when running" do
    slug = "sim-elmc-manifest-#{System.unique_integer([:positive])}"
    {:ok, _} = Debugger.start_session(slug)

    assert {:ok, _} =
             Debugger.ingest_elmc_manifest(slug, %{
               status: :ok,
               manifest_path: "/tmp/m",
               revision: "rev1",
               strict: true,
               cached: false,
               error_count: 0,
               warning_count: 0,
               schema_version: 1
             })

    assert {:ok, st} = Debugger.snapshot(slug, event_limit: 10)
    assert hd(st.events).type == "debugger.elmc_manifest"
    assert get_in(st.watch, [:model, "elmc_manifest_status"]) == "ok"
    assert get_in(st.watch, [:model, "elmc_manifest_schema_version"]) == "1"
    assert get_in(st.watch, [:model, "elmc_manifest_strict"]) == "true"
  end

  test "ingest_elmc_check is a no-op when session is not running" do
    slug = "sim-elmc-idle-#{System.unique_integer([:positive])}"

    assert {:ok, st} =
             Debugger.ingest_elmc_check(slug, %{
               status: :ok,
               checked_path: ".",
               error_count: 0,
               warning_count: 0
             })

    assert st.running == false
    assert st.events == []
  end

  test "snapshot normalizes legacy agent state missing :phone" do
    slug = "sim-legacy-phone-#{System.unique_integer([:positive])}"
    {:ok, _} = Debugger.start_session(slug)

    _ =
      Agent.get_and_update(Debugger, fn store ->
        legacy = %{
          running: true,
          events: [],
          seq: 1,
          revision: nil,
          watch: %{
            last_message: nil,
            model: %{"status" => "idle"},
            view_tree: %{"children" => [], "type" => "root"}
          },
          companion: %{
            last_message: nil,
            model: %{"status" => "idle"},
            protocol_messages: []
          }
        }

        {:ok, Map.put(store, slug, legacy)}
      end)

    assert {:ok, snap} = Debugger.snapshot(slug, event_limit: 10)
    assert get_in(snap.phone, [:view_tree, "type"]) == "PhoneRoot"
  end

  test "companion elm/http command executes and feeds structured callback message" do
    previous_debugger_config = Application.get_env(:ide, Debugger, [])
    previous_http_executor = Application.get_env(:ide, Ide.Debugger.HttpExecutor)

    Application.put_env(
      :ide,
      Debugger,
      Keyword.put(previous_debugger_config, :runtime_executor_module, HttpFollowupRuntimeExecutor)
    )

    Application.put_env(:ide, Ide.Debugger.HttpExecutor,
      request_fun: fn _command ->
        {:ok, %{"status" => 200, "body" => "ok"}}
      end
    )

    on_exit(fn ->
      Application.put_env(:ide, Debugger, previous_debugger_config)

      if is_nil(previous_http_executor) do
        Application.delete_env(:ide, Ide.Debugger.HttpExecutor)
      else
        Application.put_env(:ide, Ide.Debugger.HttpExecutor, previous_http_executor)
      end
    end)

    slug = "sim-companion-http-#{System.unique_integer([:positive])}"

    assert {:ok, _} = Debugger.start_session(slug)

    assert {:ok, reloaded} =
             Debugger.reload(slug, %{
               rel_path: "phone/src/CompanionApp.elm",
               source: "module CompanionSnap exposing (..)",
               reason: "companion_http_followup",
               source_root: "protocol"
             })

    assert {:ok, stepped} = Debugger.step(slug, %{target: "protocol", message: "Tick", count: 1})
    assert get_in(reloaded, [:companion, :model, "elm_introspect", "module"]) == "CompanionSnap"
    assert String.starts_with?(stepped.companion.last_message, "WeatherReceived ")
    assert get_in(stepped.companion.model, ["runtime_model", "lastResponse"]) == 1

    assert get_in(stepped.companion.model, ["runtime_model", "received"]) == %{
             "ctor" => "WeatherReceived",
             "args" => [%{"ctor" => "Ok", "args" => ["ok"]}]
           }

    assert Enum.any?(stepped.events, fn event ->
             event.type == "debugger.package_cmd" and
               event.payload.target == "protocol" and
               event.payload.package == "elm/http" and
               String.starts_with?(event.payload.response_message, "WeatherReceived ")
           end)
  end

  test "init runtime followups are applied and shown in debugger timeline" do
    previous_debugger_config = Application.get_env(:ide, Debugger, [])

    Application.put_env(
      :ide,
      Debugger,
      Keyword.put(
        previous_debugger_config,
        :runtime_executor_module,
        InitRandomFollowupRuntimeExecutor
      )
    )

    on_exit(fn ->
      Application.put_env(:ide, Debugger, previous_debugger_config)
    end)

    slug = "sim-init-random-followup-#{System.unique_integer([:positive])}"

    assert {:ok, _} = Debugger.start_session(slug)

    assert {:ok, reloaded} =
             Debugger.reload(slug, %{
               rel_path: "watch/src/Main.elm",
               source: "module Main exposing (..)",
               reason: "init_random_followup",
               source_root: "watch"
             })

    assert get_in(reloaded.watch.model, ["runtime_model", "seed"]) == 42

    timeline =
      reloaded.debugger_timeline
      |> Enum.map(&{&1.target, &1.message, &1.message_source})

    assert {"watch", "init", "init"} in timeline
    assert {"watch", "RandomGenerated", "runtime_followup"} in timeline

    assert Enum.any?(reloaded.events, fn event ->
             event.type == "debugger.package_cmd" and
               event.payload.target == "watch" and
               event.payload.package == "elm/random" and
               event.payload.response_message == "RandomGenerated"
           end)
  end

  test "runtime storage writes are read again after debugger restart" do
    previous_debugger_config = Application.get_env(:ide, Debugger, [])

    Application.put_env(
      :ide,
      Debugger,
      Keyword.put(
        previous_debugger_config,
        :runtime_executor_module,
        StorageFollowupRuntimeExecutor
      )
    )

    on_exit(fn ->
      Application.put_env(:ide, Debugger, previous_debugger_config)
    end)

    slug = "sim-storage-followup-#{System.unique_integer([:positive])}"

    source = """
    module Main exposing (..)

    type Msg
        = SaveBest
        | BestLoaded String
    """

    assert {:ok, _} = Debugger.start_session(slug)

    assert {:ok, loaded} =
             Debugger.reload(slug, %{
               rel_path: "watch/src/Main.elm",
               source: source,
               reason: "storage_followup",
               source_root: "watch"
             })

    assert get_in(loaded.watch.model, ["runtime_model", "best"]) == 0

    assert {:ok, saved} = Debugger.step(slug, %{target: "watch", message: "SaveBest"})
    assert get_in(saved.watch.model, ["runtime_model", "best"]) == 9124
    assert get_in(saved, [:storage, "watch", "2048", "value"]) == "9124"

    assert {:ok, _restarted} = Debugger.start_session(slug)

    assert {:ok, reloaded} =
             Debugger.reload(slug, %{
               rel_path: "watch/src/Main.elm",
               source: source,
               reason: "storage_followup_restart",
               source_root: "watch"
             })

    assert get_in(reloaded.watch.model, ["runtime_model", "best"]) == 9124
  end

  test "runtime executor fallback is visible in debugger timeline" do
    previous_debugger_config = Application.get_env(:ide, Debugger, [])
    previous_runtime_executor_config = Application.get_env(:ide, RuntimeExecutor, [])

    Application.put_env(
      :ide,
      Debugger,
      Keyword.put(previous_debugger_config, :runtime_executor_module, RuntimeExecutor)
    )

    Application.put_env(:ide, RuntimeExecutor,
      external_executor_module: FailingExternalRuntimeExecutor,
      external_executor_strict: false
    )

    on_exit(fn ->
      Application.put_env(:ide, Debugger, previous_debugger_config)
      Application.put_env(:ide, RuntimeExecutor, previous_runtime_executor_config)
    end)

    slug = "sim-runtime-fallback-visible-#{System.unique_integer([:positive])}"

    assert {:ok, _} = Debugger.start_session(slug)

    assert {:ok, reloaded} =
             Debugger.reload(slug, %{
               rel_path: "watch/src/Main.elm",
               source: """
               module Main exposing (..)

               init _ =
                   ( { n = 0 }, Cmd.none )
               """,
               reason: "runtime_fallback_visible",
               source_root: "watch"
             })

    assert get_in(reloaded.watch.model, ["elm_executor", "execution_backend"]) ==
             "fallback_default"

    assert get_in(reloaded.watch.model, ["elm_executor", "external_fallback_reason"]) =~
             "forced_runtime_failure"

    assert Enum.any?(reloaded.debugger_timeline, fn row ->
             row.target == "watch" and row.message_source == "runtime_status" and
               String.contains?(row.message, "runtime fallback fallback_default")
           end)
  end

  test "init commands without runtime followups are visible in debugger timeline" do
    previous_debugger_config = Application.get_env(:ide, Debugger, [])

    Application.put_env(
      :ide,
      Debugger,
      Keyword.put(
        previous_debugger_config,
        :runtime_executor_module,
        InitNoFollowupRuntimeExecutor
      )
    )

    on_exit(fn ->
      Application.put_env(:ide, Debugger, previous_debugger_config)
    end)

    slug = "sim-init-no-followup-visible-#{System.unique_integer([:positive])}"

    assert {:ok, _} = Debugger.start_session(slug)

    assert {:ok, reloaded} =
             Debugger.reload(slug, %{
               rel_path: "watch/src/Main.elm",
               source: """
               module Main exposing (..)

               init _ =
                   ( { n = 0 }, Random.generate GotSeed (Random.int 1 10) )
               """,
               reason: "init_no_followup_visible",
               source_root: "watch"
             })

    assert Enum.any?(reloaded.debugger_timeline, fn row ->
             row.target == "watch" and row.message_source == "runtime_status" and
               row.message == "runtime no followups for 1 init cmd(s)"
           end)
  end

  defp assert_replay_telemetry(payload, expected) when is_map(payload) and is_map(expected) do
    telemetry = Map.get(payload, :replay_telemetry)
    assert is_map(telemetry)
    assert telemetry.mode == expected.mode
    assert telemetry.source == expected.source
    assert telemetry.drift_seq == expected.drift_seq
    assert telemetry.drift_band == expected.drift_band
    assert telemetry.used_live_query == expected.used_live_query
    assert telemetry.used_frozen_preview == expected.used_frozen_preview
  end

  defp wait_until_stable_minute do
    if NaiveDateTime.local_now().second > 50 do
      Process.sleep(1_000)
      wait_until_stable_minute()
    else
      :ok
    end
  end

  defp synthetic_step_protocol_event?(%{type: type, payload: payload})
       when type in ["debugger.protocol_tx", "debugger.protocol_rx"] and is_map(payload) do
    message = Map.get(payload, :message) || Map.get(payload, "message") || ""
    trigger = Map.get(payload, :trigger) || Map.get(payload, "trigger")

    is_binary(message) and String.starts_with?(message, "Step:") and
      trigger in ["step", "tick", "replay"]
  end

  defp synthetic_step_protocol_event?(_), do: false

  defp collect_view_nodes(node) when is_map(node) do
    children =
      case node["children"] || node[:children] do
        list when is_list(list) -> list
        _ -> []
      end

    [node | Enum.flat_map(children, &collect_view_nodes/1)]
  end

  defp collect_view_nodes(_node), do: []
end
