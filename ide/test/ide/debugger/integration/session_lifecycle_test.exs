defmodule Ide.Debugger.SessionLifecycleIntegrationTest do
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

  test "second start_session clears defer bootstrap flags so watch init device data runs" do
    alias Ide.Debugger.AgentSession
    alias Ide.Debugger.BootstrapInit

    slug = "debugger-second-start-device-data-#{System.unique_integer([:positive])}"

    source =
      File.read!(Path.join(["priv", "project_templates", "watchface_digital", "src", "Main.elm"]))

    assert {:ok, _} = Debugger.start_session(slug)

    assert {:ok, _} =
             AgentSession.mutate(slug, &BootstrapInit.with_companion_bootstrap_flags/1)

    assert {:ok, _} = Debugger.start_session(slug)

    assert {:ok, reloaded} =
             Debugger.reload(slug, %{
               rel_path: "src/Main.elm",
               source: source,
               reason: "second_start_device_data",
               source_root: "watch"
             })

    runtime_model = get_in(reloaded, [:watch, :model, "runtime_model"]) || %{}

    assert runtime_model["timeString"] != "--:--"
    assert is_binary(runtime_model["timeString"])

    assert Enum.any?(reloaded.debugger_timeline, fn row ->
             row.target == "watch" and row.type == "update" and
               String.contains?(row.message || "", "CurrentTimeString")
           end)
  end

  test "start_session exposes companion and phone runtime models" do
    slug = "debugger-protocol-models-#{System.unique_integer([:positive])}"

    assert {:ok, state} = Debugger.start_session(slug)

    assert get_in(state, [:companion, :model, "runtime_model", "status"]) == "idle"
    assert get_in(state, [:companion, :model, "runtime_model", "protocol_inbound_count"]) == 0
    assert get_in(state, [:companion, :model, "runtime_model", "protocol_message_count"]) == 0
    assert get_in(state, [:phone, :model, "runtime_model", "status"]) == "idle"
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

  test "set_watch_profile patches runtime_model display shape for round profiles" do
    slug = "sim-watch-profile-runtime-shape-#{System.unique_integer([:positive])}"
    alias Ide.Debugger.AgentSession

    assert {:ok, _} = Debugger.start_session(slug)

    assert {:ok, _} =
             AgentSession.mutate(slug, fn state ->
               put_in(state, [:watch, Access.key!(:model), "runtime_model"], %{
                 "score" => 0,
                 "screenW" => 144,
                 "screenH" => 168,
                 "displayShape" => %{"ctor" => "Rectangular", "args" => []}
               })
             end)

    assert {:ok, updated} = Debugger.set_watch_profile(slug, %{watch_profile_id: "gabbro"})

    assert get_in(updated, [:watch, :model, "runtime_model", "screenW"]) == 260
    assert get_in(updated, [:watch, :model, "runtime_model", "screenH"]) == 260

    assert get_in(updated, [:watch, :model, "runtime_model", "displayShape"]) ==
             %{"ctor" => "Round", "args" => []}
  end

  test "set_watch_profile exposes Round display shape on launch screen contract" do
    slug = "sim-watch-profile-is-round-#{System.unique_integer([:positive])}"

    assert {:ok, _} = Debugger.start_session(slug)
    assert {:ok, updated} = Debugger.set_watch_profile(slug, %{watch_profile_id: "chalk"})

    assert get_in(updated, [:launch_context, "screen", "width"]) == 180
    assert get_in(updated, [:launch_context, "screen", "height"]) == 180
    assert get_in(updated, [:launch_context, "screen", "shape"]) == "Round"
    assert get_in(updated, [:launch_context, "supports_health"]) == true
    assert get_in(updated, [:launch_context, "has_microphone"]) == false
  end

  test "set_watch_profile on aplite exposes BlackWhite color mode on launch screen" do
    slug = "sim-watch-profile-aplite-color-#{System.unique_integer([:positive])}"

    assert {:ok, _} = Debugger.start_session(slug)
    assert {:ok, updated} = Debugger.set_watch_profile(slug, %{watch_profile_id: "aplite"})

    assert get_in(updated, [:launch_context, "screen", "color_mode"]) == "BlackWhite"
    assert get_in(updated, [:launch_context, "supports_health"]) == false
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

    assert get_in(st, [:watch, :model, "runtime_execution_mode"]) == "runtime_executed"
    assert get_in(st, [:watch, :model, "runtime_execution", "engine"]) == "elmx_runtime_v1"
    assert is_binary(get_in(st, [:watch, :model, "runtime_model_sha256"]))
    assert String.length(get_in(st, [:watch, :model, "runtime_model_sha256"])) == 64
    assert is_binary(get_in(st, [:watch, :model, "runtime_view_tree_sha256"]))
    assert String.length(get_in(st, [:watch, :model, "runtime_view_tree_sha256"])) == 64
    assert get_in(st, [:watch, :shell, "debugger_contract", "module"]) == "Snap"
    refute get_in(st, [:watch, :model, "debugger_contract"])

    view_type = get_in(st, [:watch, :view_tree, "type"])

    assert view_type in ["windowStack", "window", "previewUnavailable"],
           "expected runtime-derived or unavailable preview, got #{inspect(view_type)}"

    refute view_type == "Window",
           "parser-only Window view tree must not be shown when runtime preview is strict"

    assert Enum.any?(st.events, &(&1.type in ["debugger.contract", "debugger.elm_introspect"]))
    assert Enum.any?(st.events, &(&1.type == "debugger.runtime_exec"))
    runtime_exec = Enum.find(st.events, &(&1.type == "debugger.runtime_exec"))
    assert runtime_exec.payload.target == "watch"
    assert runtime_exec.payload.engine == "elmx_runtime_v1"
    assert runtime_exec.payload.runtime_model_source == "init_model"
    assert runtime_exec.payload.view_tree_source == "parser_view_tree"
    assert runtime_exec.payload.runtime_model_entry_count >= 1
    assert runtime_exec.payload.view_tree_node_count >= 1
    assert is_binary(runtime_exec.payload.runtime_model_sha256)
    assert String.length(runtime_exec.payload.runtime_model_sha256) == 64
    assert is_binary(runtime_exec.payload.view_tree_sha256)
    assert String.length(runtime_exec.payload.view_tree_sha256) == 64
    intro = Enum.find(st.events, &(&1.type in ["debugger.contract", "debugger.elm_introspect"]))
    p = intro.payload
    assert is_map(p) && (Map.get(p, :module) == "Snap" || Map.get(p, "module") == "Snap")
    assert Map.get(p, :target) == "watch" || Map.get(p, "target") == "watch"
  end

  test "watch reload replaces stale sample tree when parser preview is not renderable" do
    slug = "sim-preview-unavailable-#{System.unique_integer([:positive])}"

    source = """
    module ParserOnly exposing (..)

    import Json.Decode as Decode
    import Pebble.Platform as Platform
    import Pebble.Ui as Ui

    init _ =
        ( {}, Cmd.none )

    update _ model =
        ( model, Cmd.none )

    subscriptions _ =
        Sub.none

    view model =
        Ui.toUiNode (ops model)

    ops _ =
        []

    main : Program Decode.Value model msg
    main =
        Platform.watchface
            { init = init
            , update = update
            , view = view
            , subscriptions = subscriptions
            }
    """

    assert {:ok, _} = Debugger.start_session(slug)

    assert {:ok, st} =
             Debugger.reload(slug, %{
               rel_path: "watch/ParserOnly.elm",
               source: source,
               reason: "parser_only_preview"
             })

    assert get_in(st, [:watch, :view_tree, "type"]) == "previewUnavailable"
    refute get_in(st, [:watch, :view_tree, "type"]) == "Window"
  end

  test "phone reload merges parser snapshot into companion model and view tree" do
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
               rel_path: "phone/src/CompanionApp.elm",
               source: source,
               reason: "phone_introspect",
               source_root: "phone"
             })

    assert get_in(st, [:companion, :shell, "debugger_contract", "module"]) == "ProtoSnap"
    assert get_in(st, [:companion, :view_tree, "type"]) == "CompanionRoot"
    refute get_in(st, [:watch, :shell, "debugger_contract"])
    refute get_in(st, [:watch, :model, "debugger_contract"])
  end

  test "phone reload simulates companion geolocation on init" do
    slug = "sim-intro-geolocation-#{System.unique_integer([:positive])}"

    source = """
    module GeoSnap exposing (..)

    import Pebble.Companion.Geolocation as Geolocation exposing (Location)

    type Msg
        = CurrentPosition (Result String Location)

    init _ =
        ( { location = Nothing }, sendSnapshot )

    sendSnapshot =
        requestCurrentLocation

    requestCurrentLocation =
        Geolocation.currentPosition

    update msg model =
        case msg of
            CurrentPosition result ->
                ( { model | location = Just result }, Cmd.none )

    subscriptions model =
        Geolocation.onCurrentPosition CurrentPosition

    view m =
        Ui.root []
    """

    assert {:ok, _} = Debugger.start_session(slug)

    assert {:ok, st} =
             Debugger.reload(slug, %{
               rel_path: "phone/src/CompanionApp.elm",
               source: source,
               reason: "phone_geolocation",
               source_root: "phone"
             })

    assert Enum.any?(st.events, fn event ->
             event.type == "debugger.geolocation" and
               get_in(event.payload, [:response_value, "latitude"]) == 48.137154 and
               get_in(event.payload, [:response_value, "longitude"]) == 11.576124 and
               get_in(event.payload, [:response_value, "accuracy"]) == 25
           end)
  end

  test "watch reload applies init device data when introspect lives on shell" do
    slug = "sim-watch-device-data-shell-#{System.unique_integer([:positive])}"

    watch_source =
      File.read!(
        Path.join(["priv", "project_templates", "companion_demo_geolocation", "src", "Main.elm"])
      )

    assert {:ok, _} = Debugger.start_session(slug)

    assert {:ok, st} =
             Debugger.reload(slug, %{
               rel_path: "src/Main.elm",
               source: watch_source,
               reason: "watch_device_data_shell",
               source_root: "watch"
             })

    assert get_in(st, [:watch, :shell, "debugger_contract", "module"]) == "Main"
    refute get_in(st, [:watch, :model, "debugger_contract"])

    assert Enum.any?(st.events, fn event ->
             event.type == "debugger.device_data" and get_in(event.payload, [:target]) == "watch"
           end)
  end

  test "simulator settings drive companion geolocation payload" do
    slug = "sim-intro-geolocation-settings-#{System.unique_integer([:positive])}"

    source = """
    module GeoSettingsSnap exposing (..)

    import Pebble.Companion.Geolocation as Geolocation exposing (Location)

    type Msg
        = CurrentPosition (Result String Location)

    init _ =
        ( { location = Nothing }, Geolocation.currentPosition )

    update msg model =
        case msg of
            CurrentPosition result ->
                ( { model | location = Just result }, Cmd.none )

    subscriptions model =
        Geolocation.onCurrentPosition CurrentPosition

    view m =
        Ui.root []
    """

    assert {:ok, _} = Debugger.start_session(slug)

    assert {:ok, _} =
             Debugger.set_simulator_settings(slug, %{
               "latitude" => "47.123456",
               "longitude" => "10.654321",
               "accuracy" => "9.5"
             })

    assert {:ok, st} =
             Debugger.reload(slug, %{
               rel_path: "phone/src/CompanionApp.elm",
               source: source,
               reason: "phone_geolocation_settings",
               source_root: "phone"
             })

    assert Enum.any?(st.events, fn event ->
             event.type == "debugger.geolocation" and
               get_in(event.payload, [:response_value, "latitude"]) == 47.123456 and
               get_in(event.payload, [:response_value, "longitude"]) == 10.654321 and
               get_in(event.payload, [:response_value, "accuracy"]) == 9.5
           end)
  end

  test "phone reload drives the visible companion surface" do
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

    assert get_in(st, [:companion, :shell, "debugger_contract", "module"]) == "PhoneSnap"
    assert get_in(st, [:companion, :view_tree, "type"]) == "CompanionRoot"
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

    assert st.seq >= 1
    assert Enum.any?(st.events, &(&1.type == "debugger.view_render"))

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

    assert st.seq == 6
    assert get_in(st.companion, [:view_tree, "label"]) == "phone"
    [status | _] = get_in(st.companion, [:view_tree, "children"])
    assert String.starts_with?(status["label"], "protocol:")
  end

  test "reload fulfills init current date/time device requests before steady-state minute ticks" do
    slug = "sim-init-current-datetime-#{System.unique_integer([:positive])}"
    source = minimal_datetime_watchface_source()

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
    assert runtime_model["screenW"] == 144
    assert runtime_model["screenH"] == 168

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

    assert {:ok, ticked} = Debugger.tick(slug, %{target: "watch", count: 1})

    assert String.starts_with?(
             get_in(ticked, [:watch, :model, "runtime_last_message"]) || "",
             "MinuteChanged "
           )

    assert preview["hour"] in 0..23
    assert preview["minute"] in 0..59
  end

  test "reload refires init current date/time device requests even after previous init response" do
    slug = "sim-init-current-datetime-refire-#{System.unique_integer([:positive])}"
    source = minimal_datetime_watchface_source()

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

    assert Enum.map(debugger_rows, & &1.seq) ==
             Enum.to_list(Range.new(length(debugger_rows), 1, -1))

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
end
