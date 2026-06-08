defmodule Ide.Mcp.ToolsDebuggerIntegrationTest do
  @moduledoc false
  use Ide.DataCase, async: false

  @moduletag :integration
  @moduletag :slow
  @moduletag timeout: 300_000

  import Ide.TestSupport.McpDebuggerFlow

  alias Ide.Debugger
  alias Ide.Mcp.Tools
  alias Ide.Projects
  alias Ide.TestSupport.McpDebuggerFlow, as: Flow

  setup do
    root =
      Path.join(System.tmp_dir!(), "ide_mcp_debugger_integration_#{System.unique_integer([:positive])}")

    Application.put_env(:ide, Ide.Projects, projects_root: root)
    on_exit(fn -> File.rm_rf(root) end)
    :ok
  end

  test "debugger MCP session controls stepping and tick" do
    project = Flow.create_project!(%{"slug" => "mcp-debugger-controls-#{System.unique_integer([:positive])}"})
    slug = project.slug

    assert {:error, reason} = Tools.call("debugger.start", %{"slug" => project.slug}, [:read])
    assert String.contains?(reason, "not permitted")

    assert {:ok, %{slug: ^slug, state: started}} =
             Tools.call("debugger.start", %{"slug" => project.slug}, [:edit])

    assert started.running == true
    assert started.seq >= 1

    assert {:ok, %{watch_profiles: watch_profiles}} =
             Tools.call("debugger.watch_profiles", %{}, [:read])

    assert Enum.any?(watch_profiles, &(&1["id"] == "basalt"))

    assert {:ok, %{state: profile_state}} =
             Tools.call(
               "debugger.set_watch_profile",
               %{"slug" => project.slug, "watch_profile_id" => "basalt"},
               [:edit]
             )

    assert profile_state.watch_profile_id == "basalt"

    assert {:error, reason} =
             Tools.call(
               "debugger.reload",
               %{"slug" => project.slug, "rel_path" => "watch/Main.elm"},
               [:read]
             )

    assert String.contains?(reason, "not permitted")

    watch_source = """
    module Main exposing (..)

    type Msg
        = Inc
        | Tick

    init _ =
        ( { n = 0 }, Cmd.none )

    update msg model =
        case msg of
            Inc ->
                ( { model | n = model.n + 1 }, Cmd.none )

            Tick ->
                ( model, Cmd.none )

    subscriptions _ =
        Time.every 1000 Tick

    view model =
        []
    """

    assert {:ok, %{slug: ^slug, state: after_reload}} =
             Tools.call(
               "debugger.reload",
               %{
                 "slug" => project.slug,
                 "rel_path" => "watch/src/Main.elm",
                 "source" => watch_source,
                 "reason" => "mcp_test"
               },
               [:edit]
             )

    assert after_reload.seq > started.seq
    assert Enum.any?(after_reload.events, &(&1.type == "debugger.reload"))

    phone_source = """
    module Main exposing (..)

    type Msg
        = Sync

    init _ =
        ( { ok = False }, Cmd.none )

    view _ =
        []
    """

    assert {:ok, %{state: phone_reload}} =
             Tools.call(
               "debugger.reload",
               %{
                 "slug" => project.slug,
                 "rel_path" => "phone/Main.elm",
                 "source" => phone_source,
                 "source_root" => "phone"
               },
               [:edit]
             )

    assert phone_reload.seq > after_reload.seq

    assert {:ok, %{state: stepped}} =
             Tools.call(
               "debugger.step",
               %{
                 "slug" => project.slug,
                 "target" => "watch",
                 "message" => "Inc",
                 "count" => 2
               },
               [:edit]
             )

    assert stepped.seq > phone_reload.seq
    assert get_in(stepped, [:watch, :model, "runtime_message_source"]) == "provided"
    assert Enum.any?(stepped.events, &(&1.type == "debugger.update_in"))
    assert Enum.any?(stepped.events, &(&1.type == "debugger.view_render"))

    assert {:ok, %{state: ticked}} =
             Tools.call(
               "debugger.tick",
               %{
                 "slug" => project.slug,
                 "target" => "watch",
                 "count" => 1
               },
               [:edit]
             )

    assert ticked.seq > stepped.seq

    assert Enum.any?(ticked.debugger_timeline, fn row ->
             row.type == "update" and row.target == "watch" and row.message_source == "subscription_tick"
           end)

    assert Enum.any?(ticked.events, &(&1.type == "debugger.tick"))

    assert {:ok, %{state: companion_stepped}} =
             Tools.call(
               "debugger.step",
               %{
                 "slug" => project.slug,
                 "target" => "companion",
                 "message" => "Sync",
                 "count" => 1
               },
               [:edit]
             )

    assert get_in(companion_stepped, [:companion, :model, "runtime_message_source"]) == "provided"
  end

  test "debugger MCP replay auto tick and state fingerprints" do
    project = Flow.create_project!(%{"slug" => "mcp-debugger-replay-#{System.unique_integer([:positive])}"})
    slug = project.slug
    %{stepped: stepped} = Flow.bootstrap_stepped!(project)

    assert {:ok, %{state: auto_tick_started}} =
             Tools.call(
               "debugger.auto_tick_start",
               %{
                 "slug" => project.slug,
                 "target" => "watch",
                 "interval_ms" => 120
               },
               [:edit]
             )

    assert get_in(auto_tick_started, [:auto_tick, :enabled]) == true
    Process.sleep(280)

    assert {:ok, %{state: auto_tick_stopped}} =
             Tools.call(
               "debugger.auto_tick_stop",
               %{"slug" => project.slug},
               [:edit]
             )

    assert get_in(auto_tick_stopped, [:auto_tick, :enabled]) == false
    assert Enum.any?(auto_tick_stopped.events, &(&1.type == "debugger.tick_auto"))
    assert Enum.any?(auto_tick_stopped.events, &(&1.type == "debugger.tick"))

    assert {:ok, %{state: replayed_recent}} =
             Tools.call(
               "debugger.replay_recent",
               %{
                 "slug" => project.slug,
                 "target" => "watch",
                 "count" => 1,
                 "replay_mode" => "live",
                 "replay_drift_seq" => 4,
                 "cursor_seq" => stepped.seq
               },
               [:edit]
             )

    assert replayed_recent.seq > stepped.seq
    assert replay_event = Enum.find(replayed_recent.events, &(&1.type == "debugger.replay"))
    assert Map.get(replay_event.payload, :replay_source) == "recent_query"
    telemetry = Map.get(replay_event.payload, :replay_telemetry)
    assert is_map(telemetry)
    assert telemetry.mode == "live"
    assert telemetry.source == "recent_query"
    assert telemetry.drift_seq == 4
    assert telemetry.drift_band == "medium"
    assert telemetry.used_live_query == true
    assert telemetry.used_frozen_preview == false
    assert Map.get(replay_event.payload, :replay_target_counts) == %{"watch" => 1}
    assert is_map(Map.get(replay_event.payload, :replay_message_counts))
    assert is_list(Map.get(replay_event.payload, :replay_preview))

    assert {:ok, %{state: replayed_mode_source_split}} =
             Tools.call(
               "debugger.replay_recent",
               %{
                 "slug" => project.slug,
                 "target" => "watch",
                 "count" => 1,
                 "replay_mode" => "frozen"
               },
               [:edit]
             )

    assert replay_mode_source_event =
             Enum.find(replayed_mode_source_split.events, &(&1.type == "debugger.replay"))

    mode_source_telemetry = Map.get(replay_mode_source_event.payload, :replay_telemetry)
    assert mode_source_telemetry.mode == "frozen"
    assert mode_source_telemetry.source == "recent_query"
    assert mode_source_telemetry.used_live_query == true
    assert mode_source_telemetry.used_frozen_preview == false

    assert {:ok,
            %{
              state: replay_state,
              replay_metadata: replay_state_md,
              runtime_fingerprints: replay_fps,
              runtime_fingerprint_digest: replay_fp_digest,
              snapshot_refs: replay_snapshot_refs
            }} =
             Tools.call("debugger.state", %{"slug" => project.slug, "event_limit" => 50}, [:read])

    assert replay_state.seq >= replayed_recent.seq
    assert is_map(replay_fps)
    assert is_map(replay_fps.watch)
    assert replay_fps.watch.runtime_mode == "runtime_executed"
    assert replay_fps.watch.engine == "elmx_runtime_v1"
    assert is_map(replay_fp_digest)
    assert is_map(replay_fp_digest.watch)
    assert replay_fp_digest.watch.runtime_mode == "runtime_executed"
    assert replay_fp_digest.watch.engine == "elmx_runtime_v1"
    assert replay_fp_digest.watch.execution_backend == "compiled_elixir"
    assert Map.has_key?(replay_fp_digest.watch, :target_numeric_key_source)
    assert Map.has_key?(replay_fp_digest.watch, :target_boolean_key_source)
    assert Map.has_key?(replay_fp_digest.watch, :active_target_key_source)
    assert is_binary(replay_fp_digest.watch.runtime_model_sha256)
    assert is_binary(replay_fp_digest.watch.view_tree_sha256)
    assert is_map(replay_fp_digest.companion)
    assert is_list(replay_snapshot_refs)
    assert replay_snapshot_refs != []

    assert Enum.all?(
             replay_snapshot_refs,
             &(is_integer(Map.get(&1, "seq")) and is_map(Map.get(&1, "snapshot_refs")))
           )

    assert {:ok, state_compare_payload} =
             Tools.call(
               "debugger.state",
               %{
                 "slug" => project.slug,
                 "event_limit" => 50,
                 "compare_cursor_seq" => stepped.seq
               },
               [:read]
             )

    state_event_seqs = Enum.map(state_compare_payload.state.events, & &1.seq)

    expected_compare_seq =
      if stepped.seq in state_event_seqs, do: stepped.seq, else: state_compare_payload.state.seq

    assert is_map(state_compare_payload.runtime_fingerprint_compare)

    assert state_compare_payload.runtime_fingerprint_compare.compare_cursor_seq ==
             expected_compare_seq

    assert is_integer(
             state_compare_payload.runtime_fingerprint_compare.backend_changed_surface_count
           )

    assert is_integer(
             state_compare_payload.runtime_fingerprint_compare.key_target_changed_surface_count
           )

    assert Map.has_key?(state_compare_payload.runtime_fingerprint_compare, :backend_drift_detail)

    assert Map.has_key?(
             state_compare_payload.runtime_fingerprint_compare,
             :key_target_drift_detail
           )

    assert Map.has_key?(state_compare_payload.runtime_fingerprint_compare, :drift_detail)
    assert is_map(state_compare_payload.runtime_fingerprint_compare.surfaces)
    assert is_boolean(state_compare_payload.runtime_fingerprint_compare.surfaces.watch.changed)

    assert is_boolean(
             state_compare_payload.runtime_fingerprint_compare.surfaces.watch.backend_changed
           )

    assert {:ok, far_compare_payload} =
             Tools.call(
               "debugger.state",
               %{
                 "slug" => project.slug,
                 "event_limit" => 50,
                 "compare_cursor_seq" => stepped.seq + 100_000
               },
               [:read]
             )

    assert far_compare_payload.runtime_fingerprint_compare.compare_cursor_seq ==
             far_compare_payload.state.seq

    assert replay_state_md.replay_source == "recent_query"
    assert replay_state_md.replay_telemetry.mode == "frozen"
    assert replay_state_md.replay_telemetry.source == "recent_query"
    assert replay_state_md.replay_telemetry.drift_seq == 0
    assert replay_state_md.replay_telemetry.drift_band == "none"
    assert replay_state_md.replay_telemetry.used_live_query == true
    assert replay_state_md.replay_telemetry.used_frozen_preview == false

    assert {:ok,
            %{
              slug: ^slug,
              replay_metadata: md_only,
              event_window: win,
              runtime_fingerprint_digest: md_only_fp_digest,
              snapshot_refs: md_only_snapshot_refs
            }} =
             Tools.call(
               "debugger.state",
               %{
                 "slug" => project.slug,
                 "event_limit" => 50,
                 "replay_metadata_only" => true
               },
               [:read]
             )

    assert is_integer(win) and win > 0
    assert md_only.replay_source == "recent_query"
    assert md_only.replay_telemetry.mode == "frozen"
    assert md_only.replay_telemetry.source == "recent_query"
    assert md_only.replay_telemetry.drift_seq == 0
    assert md_only.replay_telemetry.drift_band == "none"
    assert md_only.replay_telemetry.used_live_query == true
    assert md_only.replay_telemetry.used_frozen_preview == false
    assert is_map(md_only_fp_digest)
    assert is_map(md_only_fp_digest.watch)
    assert md_only_fp_digest.watch.runtime_mode == "runtime_executed"
    assert is_binary(md_only_fp_digest.watch.runtime_model_sha256)
    assert is_binary(md_only_fp_digest.watch.view_tree_sha256)
    assert is_map(md_only_fp_digest.companion)
    assert is_list(md_only_snapshot_refs)

    assert {:ok, no_md_full} =
             Tools.call(
               "debugger.state",
               %{
                 "slug" => project.slug,
                 "event_limit" => 50,
                 "include_replay_metadata" => false
               },
               [:read]
             )

    refute Map.has_key?(no_md_full, :replay_metadata)
    assert is_map(no_md_full.runtime_fingerprints)
    assert is_map(no_md_full.runtime_fingerprint_digest)
    assert is_map(no_md_full.state)

    assert {:ok, inspect_replay} =
             Tools.call(
               "debugger.cursor_inspect",
               %{"slug" => project.slug},
               [:read]
             )

    assert inspect_replay.replay_metadata.replay_source == "recent_query"
    assert inspect_replay.replay_metadata.replay_telemetry.mode == "frozen"
    assert inspect_replay.replay_metadata.replay_telemetry.source == "recent_query"
    assert inspect_replay.replay_metadata.replay_telemetry.drift_seq == 0
    assert inspect_replay.replay_metadata.replay_telemetry.drift_band == "none"
    assert inspect_replay.replay_metadata.replay_telemetry.used_live_query == true
    assert inspect_replay.replay_metadata.replay_telemetry.used_frozen_preview == false
    assert is_map(inspect_replay.runtime_fingerprints)
    assert is_map(inspect_replay.runtime_fingerprint_digest)
    assert is_map(inspect_replay.runtime_fingerprints.watch)
    assert inspect_replay.runtime_fingerprints.watch.runtime_mode == "runtime_executed"
    assert inspect_replay.runtime_fingerprints.watch.engine == "elmx_runtime_v1"
    assert inspect_replay.runtime_fingerprints.watch.execution_backend == "compiled_elixir"
    assert is_binary(inspect_replay.runtime_fingerprints.watch.runtime_model_sha256)
    assert is_binary(inspect_replay.runtime_fingerprints.watch.view_tree_sha256)
    assert is_map(inspect_replay.runtime_fingerprints.companion)
    assert is_list(inspect_replay.snapshot_refs)

    assert {:ok, inspect_compare_payload} =
             Tools.call(
               "debugger.cursor_inspect",
               %{"slug" => project.slug, "compare_cursor_seq" => stepped.seq},
               [:read]
             )

    assert is_map(inspect_compare_payload.runtime_fingerprint_compare)
    assert inspect_compare_payload.runtime_fingerprint_compare.compare_cursor_seq == stepped.seq

    assert is_integer(
             inspect_compare_payload.runtime_fingerprint_compare.backend_changed_surface_count
           )

    assert is_integer(
             inspect_compare_payload.runtime_fingerprint_compare.key_target_changed_surface_count
           )

    assert Map.has_key?(
             inspect_compare_payload.runtime_fingerprint_compare,
             :backend_drift_detail
           )

    assert Map.has_key?(
             inspect_compare_payload.runtime_fingerprint_compare,
             :key_target_drift_detail
           )

    assert Map.has_key?(inspect_compare_payload.runtime_fingerprint_compare, :drift_detail)
    assert is_boolean(inspect_compare_payload.runtime_fingerprint_compare.surfaces.watch.changed)

    assert is_boolean(
             inspect_compare_payload.runtime_fingerprint_compare.surfaces.watch.backend_changed
           )

    assert {:ok, inspect_replay_no_md} =
             Tools.call(
               "debugger.cursor_inspect",
               %{
                 "slug" => project.slug,
                 "include_replay_metadata" => false
               },
               [:read]
             )

    refute Map.has_key?(inspect_replay_no_md, :replay_metadata)
    assert is_map(inspect_replay_no_md.runtime_fingerprints)
    assert is_map(inspect_replay_no_md.runtime_fingerprint_digest)

    assert {:error, bad_cursor_msg} =
             Tools.call(
               "debugger.replay_recent",
               %{
                 "slug" => project.slug,
                 "target" => "watch",
                 "cursor_seq" => -1
               },
               [:edit]
             )

    assert bad_cursor_msg == "invalid cursor_seq (expected non-negative integer)"

    assert {:error, bad_compare_cursor_msg} =
             Tools.call(
               "debugger.state",
               %{
                 "slug" => project.slug,
                 "compare_cursor_seq" => "nope"
               },
               [:read]
             )

    assert bad_compare_cursor_msg == "invalid compare_cursor_seq (expected non-negative integer)"

    assert {:error, bad_mode_msg} =
             Tools.call(
               "debugger.replay_recent",
               %{
                 "slug" => project.slug,
                 "target" => "watch",
                 "replay_mode" => "bogus"
               },
               [:edit]
             )

    assert bad_mode_msg == "invalid replay_mode (expected frozen|live)"

    assert {:error, bad_drift_msg} =
             Tools.call(
               "debugger.replay_recent",
               %{
                 "slug" => project.slug,
                 "target" => "watch",
                 "replay_drift_seq" => -1
               },
               [:edit]
             )

    assert bad_drift_msg == "invalid replay_drift_seq (expected non-negative integer)"

    assert {:error, bad_drift_string_msg} =
             Tools.call(
               "debugger.replay_recent",
               %{
                 "slug" => project.slug,
                 "target" => "watch",
                 "replay_drift_seq" => "abc"
               },
               [:edit]
             )

    assert bad_drift_string_msg == "invalid replay_drift_seq (expected non-negative integer)"

    assert {:ok, %{state: replayed_unknown_mode}} =
             Tools.call(
               "debugger.replay_recent",
               %{
                 "slug" => project.slug,
                 "target" => "watch",
                 "count" => 1,
                 "replay_drift_seq" => "4"
               },
               [:edit]
             )

    assert replay_unknown_event =
             Enum.find(replayed_unknown_mode.events, &(&1.type == "debugger.replay"))

    assert Map.get(replay_unknown_event.payload, :replay_telemetry).mode == "unknown"
    assert Map.get(replay_unknown_event.payload, :replay_telemetry).drift_seq == 4
    assert Map.get(replay_unknown_event.payload, :replay_telemetry).drift_band == "medium"

    assert_replay_drift_band(project.slug, "0", 0, "none")
    assert_replay_drift_band(project.slug, "3", 3, "mild")
    assert_replay_drift_band(project.slug, "10", 10, "medium")
    assert_replay_drift_band(project.slug, "11", 11, "high")

  end

  test "debugger MCP introspect export and import trace" do
    project = Flow.create_project!(%{"slug" => "mcp-debugger-export-#{System.unique_integer([:positive])}"})
    slug = project.slug
    %{stepped: stepped, phone_reload: phone_reload} = Flow.bootstrap_stepped!(project)

    snap_src = """
    module Main exposing (..)

    type Msg
        = A

    init _ =
        ( { n = 1 }, Cmd.none )

    view m =
        Ui.root []
    """

    assert {:ok, %{state: intro_reload}} =
             Tools.call(
               "debugger.reload",
               %{
                 "slug" => project.slug,
                 "rel_path" => "watch/src/Main.elm",
                 "source" => snap_src,
                 "source_root" => "watch",
                 "reason" => "mcp_introspect"
               },
               [:edit]
             )

    assert intro_reload.seq > phone_reload.seq
    assert get_in(intro_reload, [:watch, :shell, "debugger_contract", "module"]) == "Main"

    assert {:ok, snapshot_payload} =
             Tools.call("debugger.state", %{"slug" => project.slug, "event_limit" => 5}, [:read])

    assert snapshot_payload.slug == project.slug
    snapshot = snapshot_payload.state
    replay_md = Map.get(snapshot_payload, :replay_metadata)
    assert replay_md == nil or is_map(replay_md)

    assert {:ok, inspect0} =
             Tools.call(
               "debugger.cursor_inspect",
               %{"slug" => project.slug, "cursor_seq" => 1},
               [
                 :read
               ]
             )

    assert inspect0.cursor_seq == 1
    assert inspect0.event_window > 0
    assert Enum.any?(inspect0.lifecycle, &(&1.type == "debugger.start"))
    assert inspect0.view_renders == []

    assert {:ok, inspect_latest} =
             Tools.call(
               "debugger.cursor_inspect",
               %{"slug" => project.slug, "cursor_seq" => intro_reload.seq},
               [:read]
             )

    assert inspect_latest.cursor_seq == intro_reload.seq
    assert Enum.any?(inspect_latest.view_renders, &(&1.target == "watch"))
    assert inspect_latest.debugger_contract.watch["module"] == "Main"
    assert is_map(inspect_latest.debugger_contract.watch["init_model"])
    assert inspect_latest.elm_introspect == inspect_latest.debugger_contract

    assert {:ok, render_tree} =
             Tools.call(
               "debugger.render_tree",
               %{"slug" => project.slug, "target" => "watch"},
               [:read]
             )

    assert render_tree.slug == project.slug
    assert render_tree.target == "watch"
    assert render_tree.screen.width > 0
    assert render_tree.screen.height > 0
    assert render_tree.node_count >= 1
    assert [%{path: "0", type: root_type, bounds: root_bounds} | _] = render_tree.nodes
    assert is_binary(root_type)
    assert is_map(root_bounds)

    assert {:ok, preview_diag} =
             Tools.call(
               "debugger.preview_diagnostics",
               %{"slug" => project.slug, "target" => "watch", "event_limit" => 25},
               [:read]
             )

    assert preview_diag.slug == project.slug
    assert preview_diag.target == "watch"
    assert preview_diag.screen.width > 0
    assert preview_diag.screen.height > 0
    assert preview_diag.status in ["ok", "fallback", "empty"]

    assert preview_diag.render_source in [
             "runtime_view_output",
             "runtime_view_tree",
             "parser_view_tree",
             "none"
           ]

    assert is_integer(preview_diag.runtime_view_output_count)
    assert is_list(preview_diag.runtime_view_output_kinds)

    assert is_nil(preview_diag.surface_tree_sha256) or
             String.length(preview_diag.surface_tree_sha256) == 64

    assert is_nil(preview_diag.fingerprint_view_tree_sha256) or
             String.length(preview_diag.fingerprint_view_tree_sha256) == 64

    assert is_list(preview_diag.latest_render_events)
    assert is_list(preview_diag.latest_lifecycle)
    assert is_list(preview_diag.findings)

    assert {:ok, models_payload} =
             Tools.call("debugger.models", %{"slug" => project.slug}, [:read])

    assert models_payload.slug == project.slug
    assert is_map(models_payload.models.watch.model)
    assert is_map(models_payload.models.companion.model)
    refute Map.has_key?(models_payload.models.watch.model, "runtime_view_output")

    assert {:ok, watch_model_payload} =
             Tools.call(
               "debugger.models",
               %{"slug" => project.slug, "target" => "watch", "include_view_output" => true},
               [:read]
             )

    assert [:watch] = Map.keys(watch_model_payload.models)

    assert {:ok, timeline_payload} =
             Tools.call(
               "debugger.timeline",
               %{"slug" => project.slug, "event_limit" => 5},
               [:read]
             )

    assert timeline_payload.slug == project.slug
    assert timeline_payload.count > 0
    assert [%{seq: seq, type: type, summary: summary} | _] = timeline_payload.timeline
    assert is_integer(seq)
    assert is_binary(type)
    assert is_binary(summary)

    assert {:ok, surface_payload} =
             Tools.call(
               "debugger.surface_state",
               %{
                 "slug" => project.slug,
                 "target" => "watch",
                 "include_render_tree" => true
               },
               [:read]
             )

    assert surface_payload.slug == project.slug
    assert surface_payload.target == "watch"
    assert is_map(surface_payload.model.model)

    assert is_map(surface_payload.runtime_fingerprint) or
             is_nil(surface_payload.runtime_fingerprint)

    assert is_map(surface_payload.render_tree)

    assert {:ok, _} =
             Debugger.ingest_elmc_check(project.slug, %{
               status: :ok,
               checked_path: ".",
               error_count: 0,
               warning_count: 0,
               diagnostics: [
                 %{
                   severity: "error",
                   message: "mcp row",
                   source: "elmc",
                   file: "A.elm",
                   line: 2,
                   warning_type: "lowerer-warning",
                   warning_code: "constructor_payload_arity",
                   warning_constructor: "Ok",
                   warning_expected_kind: "single",
                   warning_has_arg_pattern: false
                 }
               ]
             })

    assert {:ok, inspect_diag} =
             Tools.call("debugger.cursor_inspect", %{"slug" => project.slug}, [:read])

    assert inspect_diag.elmc_diagnostics_source == "event_payload"

    assert [
             %{
               "message" => "mcp row",
               "warning_type" => "lowerer-warning",
               "warning_code" => "constructor_payload_arity",
               "warning_constructor" => "Ok",
               "warning_expected_kind" => "single",
               "warning_has_arg_pattern" => false
             }
             | _
           ] = inspect_diag.elmc_diagnostics

    assert inspect_diag.debugger_contract.watch["module"] == "Main"

    assert {:error, msg} =
             Tools.call(
               "debugger.cursor_inspect",
               %{"slug" => project.slug, "cursor_seq" => -1},
               [
                 :read
               ]
             )

    assert msg == "invalid cursor_seq (expected non-negative integer)"

    assert snapshot.running == true
    assert is_list(snapshot.events)
    assert length(snapshot.events) <= 5

    assert {:ok, export} =
             Tools.call(
               "debugger.export_trace",
               %{"slug" => project.slug, "event_limit" => 50},
               [
                 :read
               ]
             )

    assert export.slug == project.slug
    assert is_binary(export.export_json)
    assert byte_size(export.export_json) == export.byte_size
    assert is_binary(export.sha256)

    assert {:ok, export_body} = Jason.decode(export.export_json)
    assert is_map(export_body["runtime_fingerprint_compare"])
    assert is_integer(export_body["runtime_fingerprint_compare"]["current_cursor_seq"])
    assert Map.has_key?(export_body["runtime_fingerprint_compare"], "baseline_cursor_seq")
    assert is_map(export_body["runtime_fingerprint_compare"]["surfaces"])

    export_diag =
      export_body
      |> Map.get("events", [])
      |> Enum.find_value(fn event ->
        payload = Map.get(event, "payload", %{})
        preview = Map.get(payload, "diagnostic_preview", [])

        if is_list(preview) and preview != [], do: List.first(preview), else: nil
      end)

    assert is_map(export_diag)
    assert export_diag["message"] == "mcp row"
    assert export_diag["warning_type"] == "lowerer-warning"
    assert export_diag["warning_code"] == "constructor_payload_arity"
    assert export_diag["warning_constructor"] == "Ok"
    assert export_diag["warning_expected_kind"] == "single"
    assert export_diag["warning_has_arg_pattern"] == false

    assert {:ok, export_with_compare} =
             Tools.call(
               "debugger.export_trace",
               %{
                 "slug" => project.slug,
                 "event_limit" => 50,
                 "compare_cursor_seq" => stepped.seq,
                 "baseline_cursor_seq" => 1
               },
               [:read]
             )

    assert {:ok, export_compare_body} = Jason.decode(export_with_compare.export_json)
    assert is_integer(export_compare_body["runtime_fingerprint_compare"]["baseline_cursor_seq"])

    assert export_compare_body["runtime_fingerprint_compare"]["baseline_cursor_seq"] <=
             export_compare_body["runtime_fingerprint_compare"]["current_cursor_seq"]

    assert export_compare_body["runtime_fingerprint_compare"]["current_cursor_seq"] <=
             export_compare_body["seq"]

    assert is_integer(
             export_compare_body["runtime_fingerprint_compare"]["backend_changed_surface_count"]
           )

    assert is_integer(
             export_compare_body["runtime_fingerprint_compare"][
               "key_target_changed_surface_count"
             ]
           )

    assert Map.has_key?(
             export_compare_body["runtime_fingerprint_compare"],
             "key_target_drift_detail"
           )

    assert Map.has_key?(export_compare_body["runtime_fingerprint_compare"], "drift_detail")
    assert is_map(export_compare_body["runtime_fingerprint_compare"]["surfaces"]["companion"])

    assert Map.has_key?(
             export_compare_body["runtime_fingerprint_compare"]["surfaces"]["companion"],
             "current_protocol_inbound_count"
           )

    assert Map.has_key?(
             export_compare_body["runtime_fingerprint_compare"]["surfaces"]["companion"],
             "current_protocol_message_count"
           )

    assert Map.has_key?(
             export_compare_body["runtime_fingerprint_compare"]["surfaces"]["companion"],
             "current_protocol_last_inbound_message"
           )

    assert Map.has_key?(
             export_compare_body["runtime_fingerprint_compare"]["surfaces"]["watch"],
             "current_execution_backend"
           )

    assert Map.has_key?(
             export_compare_body["runtime_fingerprint_compare"]["surfaces"]["watch"],
             "baseline_execution_backend"
           )

    assert Map.has_key?(
             export_compare_body["runtime_fingerprint_compare"]["surfaces"]["watch"],
             "current_external_fallback_reason"
           )

    assert Map.has_key?(
             export_compare_body["runtime_fingerprint_compare"]["surfaces"]["watch"],
             "baseline_external_fallback_reason"
           )

    assert Map.has_key?(
             export_compare_body["runtime_fingerprint_compare"]["surfaces"]["watch"],
             "current_active_target_key_source"
           )

    assert Map.has_key?(
             export_compare_body["runtime_fingerprint_compare"]["surfaces"]["watch"],
             "baseline_active_target_key_source"
           )

    assert {:error, bad_export_compare_msg} =
             Tools.call(
               "debugger.export_trace",
               %{"slug" => project.slug, "compare_cursor_seq" => "nope"},
               [:read]
             )

    assert bad_export_compare_msg == "invalid compare_cursor_seq (expected non-negative integer)"

    assert {:error, bad_export_baseline_msg} =
             Tools.call(
               "debugger.export_trace",
               %{"slug" => project.slug, "baseline_cursor_seq" => "nope"},
               [:read]
             )

    assert bad_export_baseline_msg ==
             "invalid baseline_cursor_seq (expected non-negative integer)"

    assert {:ok, tx_only_payload} =
             Tools.call(
               "debugger.state",
               %{"slug" => project.slug, "types" => ["debugger.start"]},
               [:read]
             )

    tx_only = tx_only_payload.state
    refute Map.has_key?(tx_only_payload, :replay_metadata)
    assert Enum.all?(tx_only.events, &(&1.type == "debugger.start"))

    assert {:ok, md_only_none} =
             Tools.call(
               "debugger.state",
               %{
                 "slug" => project.slug,
                 "types" => ["debugger.start"],
                 "replay_metadata_only" => true
               },
               [:read]
             )

    refute Map.has_key?(md_only_none, :replay_metadata)

    assert {:ok, no_md_only} =
             Tools.call(
               "debugger.state",
               %{
                 "slug" => project.slug,
                 "types" => ["debugger.start"],
                 "replay_metadata_only" => true,
                 "include_replay_metadata" => false
               },
               [:read]
             )

    refute Map.has_key?(no_md_only, :replay_metadata)
    assert is_integer(no_md_only.event_window)

    assert {:ok, %{state: since_seq}} =
             Tools.call(
               "debugger.state",
               %{"slug" => project.slug, "since_seq" => 0},
               [:read]
             )

    assert Enum.all?(since_seq.events, &(&1.seq > 0))

    assert {:ok, %{slug: ^slug, state: continued_state}} =
             Tools.call(
               "debugger.continue_from_snapshot",
               %{"slug" => project.slug, "cursor_seq" => stepped.seq},
               [:edit]
             )

    assert hd(continued_state.events).type == "debugger.snapshot_continue"
    assert continued_state.seq > stepped.seq

    assert {:ok, %{slug: ^slug, state: reset_state}} =
             Tools.call("debugger.reset", %{"slug" => project.slug}, [:edit])

    assert reset_state.revision == nil

    assert {:ok, %{slug: ^slug, state: replayed}} =
             Tools.call(
               "debugger.import_trace",
               %{
                 "slug" => project.slug,
                 "export_json" => export.export_json
               },
               [:edit]
             )

    assert replayed.seq == export_body["seq"]

    assert {:error, mismatch_reason} =
             Tools.call(
               "debugger.import_trace",
               %{
                 "slug" => project.slug,
                 "export_json" => export.export_json,
                 "expected_sha256" => "deadbeef"
               },
               [:edit]
             )

    assert mismatch_reason =~ "sha256_mismatch"

    assert {:ok, %{slug: ^slug}} =
             Tools.call(
               "debugger.import_trace",
               %{
                 "slug" => project.slug,
                 "export_json" => export.export_json,
                 "expected_sha256" => export.sha256
               },
               [:edit]
             )

    assert {:ok, replay_inspect} =
             Tools.call("debugger.cursor_inspect", %{"slug" => project.slug}, [:read])

    assert replay_inspect.elmc_diagnostics_source == "event_payload"

    assert [
             %{
               "message" => "mcp row",
               "warning_type" => "lowerer-warning",
               "warning_code" => "constructor_payload_arity",
               "warning_constructor" => "Ok",
               "warning_expected_kind" => "single",
               "warning_has_arg_pattern" => false
             }
             | _
           ] = replay_inspect.elmc_diagnostics
  end

  test "debugger configuration save uses companion subscription callback" do
    slug = "mcp-debugger-config-callback-#{System.unique_integer([:positive])}"

    assert {:ok, project} =
             Projects.create_project(%{
               "name" => "McpDebuggerConfigCallback",
               "slug" => slug,
               "target_type" => "app",
               "template" => "watchface-yes"
             })

    root = Projects.project_workspace_path(project)
    phone_source = File.read!(Path.join([root, "phone", "src", "CompanionApp.elm"]))
    watch_source = File.read!(Path.join([root, "watch", "src", "Main.elm"]))

    assert {:ok, _} = Debugger.start_session(slug)

    assert {:ok, _} =
             Debugger.reload(slug, %{
               rel_path: "phone/src/CompanionApp.elm",
               source_root: "phone",
               source: phone_source,
               reason: "configuration_callback_phone"
             })

    assert {:ok, _} =
             Debugger.reload(slug, %{
               rel_path: "watch/src/Main.elm",
               source_root: "watch",
               source: watch_source,
               reason: "configuration_callback_watch"
             })

    assert {:ok, %{state: state}} =
             Tools.call("debugger.save_configuration", %{"slug" => slug, "values" => %{}}, [:edit])

    timeline =
      state.debugger_timeline
      |> Enum.map(&{&1.target, &1.message, &1.message_source})

    assert Enum.any?(timeline, fn
             {"phone", msg, "configuration"} when is_binary(msg) ->
               String.starts_with?(msg, "FromConfiguration")

             _ ->
               false
           end)

    refute {"phone", "FromBridge", "configuration"} in timeline
  end

  test "debugger geolocation task followup passes Yes location to watch" do
    slug = "mcp-debugger-yes-location-#{System.unique_integer([:positive])}"

    assert {:ok, project} =
             Projects.create_project(%{
               "name" => "McpDebuggerYesLocation",
               "slug" => slug,
               "target_type" => "app",
               "template" => "watchface-yes"
             })

    root = Projects.project_workspace_path(project)
    phone_source = File.read!(Path.join([root, "phone", "src", "CompanionApp.elm"]))
    watch_source = File.read!(Path.join([root, "watch", "src", "Main.elm"]))

    assert {:ok, _} = Debugger.start_session(slug)

    assert {:ok, _} =
             Debugger.set_simulator_settings(slug, %{
               "latitude" => "48.0",
               "longitude" => "10.0",
               "accuracy" => "25.0"
             })

    assert {:ok, _} =
             Debugger.reload(slug, %{
               rel_path: "watch/src/Main.elm",
               source_root: "watch",
               source: watch_source,
               reason: "yes_location_watch"
             })

    assert {:ok, state} =
             Debugger.reload(slug, %{
               rel_path: "phone/src/CompanionApp.elm",
               source_root: "phone",
               source: phone_source,
               reason: "yes_location_phone"
             })

    timeline =
      state.debugger_timeline
      |> Enum.map(&{&1.target, &1.message, &1.message_source})

    assert Enum.any?(timeline, fn
             {"phone", msg, source}
             when is_binary(msg) and source in ["init_geolocation", "geolocation"] ->
               String.starts_with?(msg, "CurrentPosition")

             _ ->
               false
           end) or
             Enum.any?(state.events, fn event -> event.type == "debugger.geolocation" end)

    assert Enum.any?(timeline, fn
             {"phone", msg, source}
             when is_binary(msg) and
                    source in ["init_geolocation", "geolocation", "runtime_followup"] ->
               String.starts_with?(msg, "CurrentPosition") or
                 String.starts_with?(msg, "SendLocationSnapshot")

             _ ->
               false
           end) or
             Enum.any?(state.events, fn event ->
               event.type in [
                 "debugger.geolocation",
                 "debugger.protocol_rx",
                 "debugger.protocol_tx"
               ]
             end)

    watch_model = get_in(state, [:watch, :model, "runtime_model"]) || %{}

    assert watch_model != %{}
    assert get_in(watch_model, ["homeLatE6", "ctor"]) in ["Just", "Nothing"]
    assert get_in(watch_model, ["homeLonE6", "ctor"]) in ["Just", "Nothing"]

    case watch_model["sun"] do
      %{
        "ctor" => "Just",
        "args" => [
          %{"mode" => %{"ctor" => "SunCycle"}, "sunriseMin" => sunrise, "sunsetMin" => sunset}
        ]
      } ->
        assert is_integer(sunrise) and sunrise > 0
        assert is_integer(sunset) and sunset > sunrise

      _ ->
        :ok
    end
  end

  test "debugger.state polling modes expose expected payload keys" do
    assert {:ok, project} =
             Projects.create_project(%{
               "name" => "McpStateModes",
               "slug" => "mcp-state-modes-#{System.unique_integer([:positive])}",
               "target_type" => "app"
             })

    assert {:ok, _} = Tools.call("debugger.start", %{"slug" => project.slug}, [:edit])

    assert {:ok, _} =
             Tools.call(
               "debugger.reload",
               %{
                 "slug" => project.slug,
                 "rel_path" => "watch/Main.elm",
                 "source" => "module Main exposing (main)"
               },
               [:edit]
             )

    assert {:ok, _} =
             Tools.call(
               "debugger.replay_recent",
               %{"slug" => project.slug, "target" => "watch", "count" => 1},
               [:edit]
             )

    assert {:ok, default_payload} =
             Tools.call("debugger.state", %{"slug" => project.slug, "event_limit" => 50}, [:read])

    assert Map.has_key?(default_payload, :state)
    assert Map.has_key?(default_payload, :runtime_fingerprints)
    assert Map.has_key?(default_payload, :runtime_fingerprint_digest)
    assert Map.has_key?(default_payload, :replay_metadata)
    refute Map.has_key?(default_payload, :event_window)

    assert {:ok, no_md_payload} =
             Tools.call(
               "debugger.state",
               %{
                 "slug" => project.slug,
                 "event_limit" => 50,
                 "include_replay_metadata" => false
               },
               [:read]
             )

    assert Map.has_key?(no_md_payload, :state)
    assert Map.has_key?(no_md_payload, :runtime_fingerprints)
    assert Map.has_key?(no_md_payload, :runtime_fingerprint_digest)
    refute Map.has_key?(no_md_payload, :replay_metadata)
    refute Map.has_key?(no_md_payload, :event_window)

    assert {:ok, md_only_payload} =
             Tools.call(
               "debugger.state",
               %{
                 "slug" => project.slug,
                 "event_limit" => 50,
                 "replay_metadata_only" => true
               },
               [:read]
             )

    assert Map.has_key?(md_only_payload, :event_window)
    assert Map.has_key?(md_only_payload, :runtime_fingerprint_digest)
    assert Map.has_key?(md_only_payload, :replay_metadata)
    refute Map.has_key?(md_only_payload, :runtime_fingerprints)
    refute Map.has_key?(md_only_payload, :state)

    assert {:ok, md_only_no_md_payload} =
             Tools.call(
               "debugger.state",
               %{
                 "slug" => project.slug,
                 "event_limit" => 50,
                 "replay_metadata_only" => true,
                 "include_replay_metadata" => false
               },
               [:read]
             )

    assert Map.has_key?(md_only_no_md_payload, :event_window)
    assert Map.has_key?(md_only_no_md_payload, :runtime_fingerprint_digest)
    refute Map.has_key?(md_only_no_md_payload, :replay_metadata)
    refute Map.has_key?(md_only_no_md_payload, :runtime_fingerprints)
    refute Map.has_key?(md_only_no_md_payload, :state)
  end

  test "debugger.cursor_inspect include_replay_metadata controls payload key" do
    assert {:ok, project} =
             Projects.create_project(%{
               "name" => "McpCursorInspectModes",
               "slug" => "mcp-cursor-inspect-modes-#{System.unique_integer([:positive])}",
               "target_type" => "app"
             })

    assert {:ok, _} = Tools.call("debugger.start", %{"slug" => project.slug}, [:edit])

    assert {:ok, _} =
             Tools.call(
               "debugger.reload",
               %{
                 "slug" => project.slug,
                 "rel_path" => "watch/Main.elm",
                 "source" => "module Main exposing (main)"
               },
               [:edit]
             )

    assert {:ok, _} =
             Tools.call(
               "debugger.replay_recent",
               %{"slug" => project.slug, "target" => "watch", "count" => 1},
               [:edit]
             )

    assert {:ok, inspect_default} =
             Tools.call("debugger.cursor_inspect", %{"slug" => project.slug}, [:read])

    assert Map.has_key?(inspect_default, :replay_metadata)
    assert inspect_default.replay_metadata.replay_source in ["recent_query", "frozen_preview"]
    assert Map.has_key?(inspect_default, :runtime_fingerprints)
    assert Map.has_key?(inspect_default, :runtime_fingerprint_digest)

    assert {:ok, inspect_no_md} =
             Tools.call(
               "debugger.cursor_inspect",
               %{
                 "slug" => project.slug,
                 "include_replay_metadata" => false
               },
               [:read]
             )

    refute Map.has_key?(inspect_no_md, :replay_metadata)
    assert Map.has_key?(inspect_no_md, :runtime_fingerprints)
    assert Map.has_key?(inspect_no_md, :runtime_fingerprint_digest)
    assert Map.has_key?(inspect_no_md, :update_messages)
    assert Map.has_key?(inspect_no_md, :protocol_exchange)
    assert Map.has_key?(inspect_no_md, :view_renders)
    assert Map.has_key?(inspect_no_md, :lifecycle)

    assert {:ok, inspect_md_only} =
             Tools.call(
               "debugger.cursor_inspect",
               %{
                 "slug" => project.slug,
                 "replay_metadata_only" => true
               },
               [:read]
             )

    assert Map.has_key?(inspect_md_only, :replay_metadata)
    assert Map.has_key?(inspect_md_only, :cursor_seq)
    assert Map.has_key?(inspect_md_only, :event_window)
    refute Map.has_key?(inspect_md_only, :runtime_fingerprints)
    refute Map.has_key?(inspect_md_only, :runtime_fingerprint_digest)
    refute Map.has_key?(inspect_md_only, :update_messages)
    refute Map.has_key?(inspect_md_only, :protocol_exchange)
    refute Map.has_key?(inspect_md_only, :view_renders)
    refute Map.has_key?(inspect_md_only, :lifecycle)
    refute Map.has_key?(inspect_md_only, :elmc_diagnostics)
    refute Map.has_key?(inspect_md_only, :elm_introspect)

    assert {:ok, inspect_md_only_no_md} =
             Tools.call(
               "debugger.cursor_inspect",
               %{
                 "slug" => project.slug,
                 "replay_metadata_only" => true,
                 "include_replay_metadata" => false
               },
               [:read]
             )

    refute Map.has_key?(inspect_md_only_no_md, :replay_metadata)
    assert Map.has_key?(inspect_md_only_no_md, :cursor_seq)
    assert Map.has_key?(inspect_md_only_no_md, :event_window)
    refute Map.has_key?(inspect_md_only_no_md, :runtime_fingerprints)
    refute Map.has_key?(inspect_md_only_no_md, :runtime_fingerprint_digest)
    refute Map.has_key?(inspect_md_only_no_md, :update_messages)
  end

end
