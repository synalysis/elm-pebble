defmodule Ide.Mcp.Handlers.Debugger do
  @moduledoc false

  alias Ide.Debugger
  alias Ide.Debugger.CursorSeq
  alias Ide.Debugger.RuntimeFingerprintDrift
  alias Ide.Debugger.Types, as: DebuggerTypes
  alias Ide.Mcp.ToolSupport
  alias Ide.Mcp.ToolTypes
  alias Ide.Mcp.WireTypes
  alias Ide.Projects
  alias Ide.Projects.Project
  alias Ide.Projects.Types, as: ProjectsTypes
  alias IdeWeb.WorkspaceLive.DebuggerSupport
  alias IdeWeb.WorkspaceLive.DebuggerSupport.Types, as: SupportTypes
  alias IdeWeb.WorkspaceLive.DebuggerBootstrapFlow

  @type debugger_generic_result :: WireTypes.json_value()

  @type debugger_export_payload :: %{
          required(:json) => String.t(),
          required(:sha256) => String.t(),
          required(:byte_size) => non_neg_integer()
        }

  @type debugger_snapshot_ref :: DebuggerTypes.trace_snapshot_reference_row()
  @type runtime_fingerprint_payload :: DebuggerTypes.runtime_fingerprint()
  @type runtime_fingerprint_digest :: DebuggerTypes.runtime_fingerprint_digest()
  @type compact_event_payload :: DebuggerTypes.compact_timeline_event_payload()

  @type debugger_result ::
          ToolTypes.debugger_state_result()
          | ToolTypes.debugger_cursor_inspect_result()
          | ToolTypes.render_tree_result()
          | ToolTypes.debugger_preview_diagnostics_result()
          | ToolTypes.debugger_models_result()
          | ToolTypes.debugger_timeline_result()
          | ToolTypes.debugger_surface_state_result()
          | ToolTypes.debugger_watch_profiles_result()
          | ToolTypes.debugger_simulator_settings_result()
          | ToolTypes.debugger_configuration_result()
          | ToolTypes.debugger_auto_fire_result()
          | ToolTypes.debugger_disabled_subscriptions_result()
          | ToolTypes.debugger_slug_state_result()
          | ToolTypes.debugger_simulator_settings_state_result()
          | ToolTypes.debugger_configuration_values_state_result()
          | ToolTypes.debugger_auto_fire_settings_state_result()
          | ToolTypes.debugger_disabled_subscriptions_state_result()
          | ToolTypes.debugger_export_trace_result()
          | ToolTypes.traces_export_result()
          | debugger_generic_result()

  @spec call(String.t(), ToolTypes.tool_args()) :: {:ok, debugger_result()} | {:error, String.t()}
  def call("debugger.state", %{"slug" => slug} = args) do
    replay_metadata_only? = ToolSupport.truthy?(Map.get(args, "replay_metadata_only"))
    include_replay_metadata? = include_replay_metadata?(Map.get(args, "include_replay_metadata"))

    with {:ok, compare_cursor_seq} <-
           parse_compare_cursor_seq(Map.get(args, "compare_cursor_seq")),
         {:ok, _project} <- ToolSupport.fetch_project(slug),
         {:ok, state} <-
           Debugger.snapshot(ToolSupport.project_session_key(slug),
             event_limit: parse_event_limit(args["event_limit"]),
             since_seq: parse_since_seq(args["since_seq"]),
             types: parse_event_types(args["types"])
           ) do
      events = Map.get(state, :events) || []
      snapshot_refs = Debugger.snapshot_reference_rows(events)
      runtime_fingerprints = DebuggerSupport.runtime_fingerprints_at_cursor(events, nil)
      runtime_fingerprint_digest = runtime_fingerprint_digest(runtime_fingerprints)

      runtime_fingerprint_compare =
        runtime_fingerprint_compare(
          events,
          runtime_fingerprints,
          resolve_cursor_seq(events, nil),
          compare_cursor_seq
        )

      replay_metadata =
        if include_replay_metadata? do
          DebuggerSupport.replay_metadata_at_cursor(events, nil)
        end

      if replay_metadata_only? do
        {:ok,
         debugger_state_replay_payload(
           slug,
           length(events),
           runtime_fingerprint_digest,
           snapshot_refs
         )
         |> maybe_put_runtime_fingerprint_compare(runtime_fingerprint_compare)
         |> maybe_put_replay_metadata(replay_metadata)}
      else
        {:ok,
         debugger_state_full_payload(
           slug,
           state,
           runtime_fingerprints,
           runtime_fingerprint_digest,
           snapshot_refs
         )
         |> maybe_put_runtime_fingerprint_compare(runtime_fingerprint_compare)
         |> maybe_put_replay_metadata(replay_metadata)}
      end
    else
      {:error, "invalid compare_cursor_seq (expected non-negative integer)"} = err ->
        err

      {:error, reason} ->
        {:error, "debugger state failed: #{inspect(reason)}"}
    end
  end

  def call("debugger.cursor_inspect", %{"slug" => slug} = args) do
    event_limit = parse_cursor_inspect_event_limit(args["event_limit"])
    include_replay_metadata? = include_replay_metadata?(Map.get(args, "include_replay_metadata"))
    replay_metadata_only? = ToolSupport.truthy?(Map.get(args, "replay_metadata_only"))

    with {:ok, cursor_seq} <- parse_cursor_seq(args["cursor_seq"]),
         {:ok, compare_cursor_seq} <-
           parse_compare_cursor_seq(Map.get(args, "compare_cursor_seq")),
         {:ok, _project} <- ToolSupport.fetch_project(slug),
         {:ok, state} <-
           Debugger.snapshot(ToolSupport.project_session_key(slug), event_limit: event_limit) do
      events = Map.get(state, :events) || []
      snapshot_refs = Debugger.snapshot_reference_rows(events)

      update_limit = parse_inspect_table_limit(args["update_limit"], 40)
      protocol_limit = parse_inspect_table_limit(args["protocol_limit"], 40)
      render_limit = parse_inspect_table_limit(args["render_limit"], 24)
      lifecycle_limit = parse_inspect_table_limit(args["lifecycle_limit"], 12)

      resolved_cursor = resolve_cursor_seq(events, cursor_seq)
      diag = DebuggerSupport.diagnostics_preview_at_cursor(events, resolved_cursor)

      intro = DebuggerSupport.debugger_contract_at_cursor(events, resolved_cursor)

      runtime_fingerprints =
        DebuggerSupport.runtime_fingerprints_at_cursor(events, resolved_cursor)

      runtime_fingerprint_digest = runtime_fingerprint_digest(runtime_fingerprints)

      runtime_fingerprint_compare =
        runtime_fingerprint_compare(
          events,
          runtime_fingerprints,
          resolved_cursor,
          compare_cursor_seq
        )

      replay_metadata =
        if include_replay_metadata? do
          DebuggerSupport.replay_metadata_at_cursor(events, resolved_cursor)
        end

      payload =
        if replay_metadata_only? do
          debugger_cursor_inspect_replay_payload(
            slug,
            resolved_cursor,
            length(events),
            snapshot_refs
          )
        else
          debugger_cursor_inspect_full_payload(
            slug,
            resolved_cursor,
            length(events),
            snapshot_refs,
            diag,
            intro,
            runtime_fingerprints,
            runtime_fingerprint_digest,
            events,
            update_limit,
            protocol_limit,
            render_limit,
            lifecycle_limit
          )
        end

      {:ok,
       payload
       |> maybe_put_runtime_fingerprint_compare(runtime_fingerprint_compare)
       |> maybe_put_replay_metadata(replay_metadata)}
    else
      {:error, "invalid cursor_seq (expected non-negative integer)"} = err ->
        err

      {:error, "invalid compare_cursor_seq (expected non-negative integer)"} = err ->
        err

      {:error, reason} ->
        {:error, "debugger cursor_inspect failed: #{inspect(reason)}"}
    end
  end

  def call("debugger.render_tree", %{"slug" => slug} = args) do
    target = Map.get(args, "target", "watch")
    include_tree? = ToolSupport.truthy?(Map.get(args, "include_tree"))

    with {:ok, target_atom} <- parse_render_tree_target(target),
         {:ok, _project} <- ToolSupport.fetch_project(slug),
         {:ok, state} <- Debugger.snapshot(ToolSupport.project_session_key(slug), event_limit: 1),
         {:ok, runtime} <- debugger_surface_runtime(state, target_atom),
         {:ok, tree} <- debugger_render_tree(runtime) do
      screen = debugger_surface_screen(state, runtime, target_atom)
      nodes = flatten_rendered_nodes(tree, screen.width, screen.height)

      {:ok,
       debugger_render_tree_payload(
         slug,
         target_atom,
         screen,
         tree,
         nodes,
         include_tree?
       )}
    else
      {:error, reason} ->
        {:error, "debugger render_tree failed: #{debugger_render_tree_error(reason)}"}
    end
  end

  def call("debugger.preview_diagnostics", %{"slug" => slug} = args) do
    target = Map.get(args, "target", "watch")
    event_limit = parse_event_limit(Map.get(args, "event_limit", 100))

    with {:ok, target_atom} <- parse_render_tree_target(target),
         {:ok, _project} <- ToolSupport.fetch_project(slug),
         {:ok, state} <-
           Debugger.snapshot(ToolSupport.project_session_key(slug), event_limit: event_limit),
         {:ok, runtime} <- debugger_surface_runtime(state, target_atom) do
      events = Map.get(state, :events) || []
      cursor_seq = resolve_cursor_seq(events, nil)
      runtime_fingerprints = DebuggerSupport.runtime_fingerprints_at_cursor(events, cursor_seq)
      screen = debugger_surface_screen(state, runtime || %{}, target_atom)

      {:ok,
       preview_diagnostics_payload(
         slug,
         state,
         runtime || %{},
         target_atom,
         screen,
         runtime_fingerprints,
         events,
         cursor_seq
       )}
    else
      {:error, reason} -> {:error, "debugger preview diagnostics failed: #{inspect(reason)}"}
    end
  end

  def call("debugger.models", %{"slug" => slug} = args) do
    include_view_output? = ToolSupport.truthy?(Map.get(args, "include_view_output"))

    with {:ok, targets} <- parse_optional_debugger_targets(Map.get(args, "target")),
         {:ok, _project} <- ToolSupport.fetch_project(slug),
         {:ok, state} <- Debugger.snapshot(ToolSupport.project_session_key(slug), event_limit: 1) do
      models =
        targets
        |> Enum.map(fn target ->
          {target, surface_model_payload(state, target, include_view_output?)}
        end)
        |> Map.new()

      {:ok, debugger_models_payload(slug, state, models)}
    else
      {:error, reason} -> {:error, "debugger models failed: #{inspect(reason)}"}
    end
  end

  def call("debugger.timeline", %{"slug" => slug} = args) do
    with {:ok, _project} <- ToolSupport.fetch_project(slug),
         {:ok, state} <-
           Debugger.snapshot(ToolSupport.project_session_key(slug),
             event_limit: parse_event_limit(args["event_limit"]),
             since_seq: parse_since_seq(args["since_seq"]),
             types: parse_event_types(args["types"])
           ) do
      events = Map.get(state, :events) || []

      {:ok, debugger_timeline_payload(slug, state, events)}
    else
      {:error, reason} -> {:error, "debugger timeline failed: #{inspect(reason)}"}
    end
  end

  def call("debugger.surface_state", %{"slug" => slug} = args) do
    target = Map.get(args, "target", "watch")
    include_view_output? = ToolSupport.truthy?(Map.get(args, "include_view_output"))
    include_render_tree? = ToolSupport.truthy?(Map.get(args, "include_render_tree"))

    with {:ok, target_atom} <- parse_render_tree_target(target),
         {:ok, _project} <- ToolSupport.fetch_project(slug),
         {:ok, state} <-
           Debugger.snapshot(ToolSupport.project_session_key(slug), event_limit: 100),
         {:ok, runtime} <- debugger_surface_runtime(state, target_atom) do
      events = Map.get(state, :events) || []
      screen = debugger_surface_screen(state, runtime, target_atom)
      render_tree = maybe_render_tree_payload(runtime, screen, include_render_tree?)

      {:ok,
       debugger_surface_state_payload(
         slug,
         state,
         target_atom,
         screen,
         surface_model_payload(state, target_atom, include_view_output?),
         runtime,
         events,
         render_tree
       )}
    else
      {:error, reason} -> {:error, "debugger surface_state failed: #{inspect(reason)}"}
    end
  end

  def call("debugger.watch_profiles", _args) do
    {:ok, debugger_watch_profiles_payload()}
  end

  def call("debugger.simulator_settings", %{"slug" => slug}) do
    with {:ok, project} <- ToolSupport.fetch_project(slug),
         {:ok, state} <- Debugger.snapshot(ToolSupport.project_session_key(slug), event_limit: 1) do
      persisted = project_simulator_settings(project)
      active = Map.get(state, :simulator_settings) || persisted
      {:ok, debugger_simulator_settings_payload(slug, active, persisted)}
    else
      {:error, reason} -> {:error, "debugger simulator settings failed: #{inspect(reason)}"}
    end
  end

  def call("debugger.configuration", %{"slug" => slug}) do
    with {:ok, project} <- ToolSupport.fetch_project(slug),
         {:ok, state} <- Debugger.snapshot(ToolSupport.project_session_key(slug), event_limit: 1) do
      settings = project.debugger_settings || %{}
      persisted_values = ToolSupport.map_value(settings, "configuration_values") || %{}
      companion_model = get_in(state, [:companion, :model]) || %{}

      configuration =
        ToolSupport.map_value(companion_model, "configuration") ||
          get_in(companion_model, ["runtime_model", "configuration"]) ||
          %{}

      {:ok, debugger_configuration_payload(slug, persisted_values, configuration)}
    else
      {:error, reason} -> {:error, "debugger configuration failed: #{inspect(reason)}"}
    end
  end

  def call("debugger.auto_fire", %{"slug" => slug}) do
    with {:ok, project} <- ToolSupport.fetch_project(slug),
         {:ok, state} <- Debugger.snapshot(ToolSupport.project_session_key(slug), event_limit: 1) do
      settings = project.debugger_settings || %{}

      {:ok, debugger_auto_fire_payload(slug, settings, state)}
    else
      {:error, reason} -> {:error, "debugger auto_fire failed: #{inspect(reason)}"}
    end
  end

  def call("debugger.disabled_subscriptions", %{"slug" => slug}) do
    with {:ok, project} <- ToolSupport.fetch_project(slug),
         {:ok, state} <- Debugger.snapshot(ToolSupport.project_session_key(slug), event_limit: 1) do
      settings = project.debugger_settings || %{}

      {:ok, debugger_disabled_subscriptions_payload(slug, settings, state)}
    else
      {:error, reason} -> {:error, "debugger disabled_subscriptions failed: #{inspect(reason)}"}
    end
  end

  def call("debugger.start", %{"slug" => slug}) do
    with {:ok, project} <- ToolSupport.fetch_project(slug),
         scope_key = ToolSupport.project_session_key(project),
         {:ok, state} <- Debugger.start_session(scope_key) do
      :ok = schedule_companion_bootstrap_if_present(project)
      {:ok, debugger_slug_state_payload(slug, state)}
    else
      {:error, reason} -> {:error, "debugger start failed: #{inspect(reason)}"}
    end
  end

  def call("debugger.reset", %{"slug" => slug}) do
    with {:ok, project} <- ToolSupport.fetch_project(slug),
         scope_key = ToolSupport.project_session_key(project),
         {:ok, state} <- Debugger.reset(scope_key) do
      {:ok, debugger_slug_state_payload(slug, state)}
    else
      {:error, reason} -> {:error, "debugger reset failed: #{inspect(reason)}"}
    end
  end

  def call(
        "debugger.set_watch_profile",
        %{
          "slug" => slug,
          "watch_profile_id" => watch_profile_id
        } = args
      ) do
    attrs = %{
      watch_profile_id: watch_profile_id,
      launch_reason: Map.get(args, "launch_reason")
    }

    with {:ok, _project} <- ToolSupport.fetch_project(slug),
         {:ok, state} <- Debugger.set_watch_profile(ToolSupport.project_session_key(slug), attrs) do
      {:ok, debugger_slug_state_payload(slug, state)}
    else
      {:error, reason} -> {:error, "debugger set_watch_profile failed: #{inspect(reason)}"}
    end
  end

  def call("debugger.set_simulator_settings", %{"slug" => slug, "settings" => settings})
      when is_map(settings) do
    with {:ok, project} <- ToolSupport.fetch_project(slug),
         normalized <- ToolSupport.normalize_mcp_simulator_settings(settings),
         :ok <- maybe_persist_project_debugger_setting(project, "simulator", normalized),
         {:ok, state} <-
           Debugger.set_simulator_settings(ToolSupport.project_session_key(slug), normalized) do
      {:ok, debugger_simulator_settings_state_payload(slug, normalized, state)}
    else
      {:error, reason} -> {:error, "debugger set_simulator_settings failed: #{inspect(reason)}"}
    end
  end

  def call("debugger.save_configuration", %{"slug" => slug, "values" => values})
      when is_map(values) do
    with {:ok, project} <- ToolSupport.fetch_project(slug),
         values <- normalize_configuration_values(values),
         {:ok, _project} <-
           persist_project_debugger_setting(project, "configuration_values", values),
         {:ok, state} <-
           Debugger.save_configuration(ToolSupport.project_session_key(slug), values) do
      {:ok, debugger_configuration_values_state_payload(slug, values, state)}
    else
      {:error, reason} -> {:error, "debugger save_configuration failed: #{inspect(reason)}"}
    end
  end

  def call("debugger.set_auto_fire", %{"slug" => slug} = args) do
    attrs = %{
      target: ToolSupport.map_value(args, "target"),
      trigger: ToolSupport.map_value(args, "trigger"),
      enabled: ToolSupport.map_value(args, "enabled")
    }

    with {:ok, project} <- ToolSupport.fetch_project(slug),
         {:ok, project} <- persist_project_auto_fire_setting(project, attrs),
         {:ok, state} <- Debugger.set_auto_fire(ToolSupport.project_session_key(slug), attrs) do
      settings = project.debugger_settings || %{}

      {:ok,
       debugger_auto_fire_settings_state_payload(
         slug,
         ToolSupport.map_value(settings, "auto_fire") || %{},
         ToolSupport.map_value(settings, "auto_fire_subscriptions") || [],
         state
       )}
    else
      {:error, reason} -> {:error, "debugger set_auto_fire failed: #{inspect(reason)}"}
    end
  end

  def call("debugger.set_subscription_enabled", %{"slug" => slug} = args) do
    attrs = %{
      target: ToolSupport.map_value(args, "target"),
      trigger: ToolSupport.map_value(args, "trigger"),
      enabled: ToolSupport.map_value(args, "enabled")
    }

    with {:ok, project} <- ToolSupport.fetch_project(slug),
         {:ok, project} <- persist_project_disabled_subscription_setting(project, attrs),
         {:ok, state} <-
           Debugger.set_subscription_enabled(ToolSupport.project_session_key(slug), attrs) do
      settings = project.debugger_settings || %{}

      {:ok,
       debugger_disabled_subscriptions_state_payload(
         slug,
         ToolSupport.map_value(settings, "disabled_subscriptions") || [],
         state
       )}
    else
      {:error, reason} ->
        {:error, "debugger set_subscription_enabled failed: #{inspect(reason)}"}
    end
  end

  def call("debugger.reload", %{"slug" => slug, "rel_path" => rel_path} = args)
      when is_binary(rel_path) do
    reason = Map.get(args, "reason") || "mcp_reload"
    source_root = Map.get(args, "source_root") || "watch"

    with {:ok, project} <- ToolSupport.fetch_project(slug),
         {:ok, source} <-
           debugger_reload_source(project, source_root, rel_path, Map.get(args, "source")),
         {:ok, state} <-
           Debugger.reload(ToolSupport.project_session_key(slug), %{
             rel_path: rel_path,
             source: source,
             reason: reason,
             source_root: source_root
           }) do
      {:ok, debugger_slug_state_payload(slug, state)}
    else
      {:error, reason} -> {:error, "debugger reload failed: #{inspect(reason)}"}
    end
  end

  def call("debugger.step", %{"slug" => slug} = args) do
    step_attrs = %{
      target: Map.get(args, "target"),
      message: Map.get(args, "message"),
      count: Map.get(args, "count")
    }

    with {:ok, _project} <- ToolSupport.fetch_project(slug),
         {:ok, state} <- Debugger.step(ToolSupport.project_session_key(slug), step_attrs) do
      {:ok, debugger_slug_state_payload(slug, state)}
    else
      {:error, reason} -> {:error, "debugger step failed: #{inspect(reason)}"}
    end
  end

  def call("debugger.tick", %{"slug" => slug} = args) do
    tick_attrs = %{
      target: Map.get(args, "target"),
      count: Map.get(args, "count")
    }

    with {:ok, _project} <- ToolSupport.fetch_project(slug),
         {:ok, state} <- Debugger.tick(ToolSupport.project_session_key(slug), tick_attrs) do
      {:ok, debugger_slug_state_payload(slug, state)}
    else
      {:error, reason} -> {:error, "debugger tick failed: #{inspect(reason)}"}
    end
  end

  def call("debugger.auto_tick_start", %{"slug" => slug} = args) do
    tick_attrs = %{
      target: Map.get(args, "target"),
      count: Map.get(args, "count"),
      interval_ms: Map.get(args, "interval_ms")
    }

    with {:ok, _project} <- ToolSupport.fetch_project(slug),
         {:ok, state} <-
           Debugger.start_auto_tick(ToolSupport.project_session_key(slug), tick_attrs) do
      {:ok, debugger_slug_state_payload(slug, state)}
    else
      {:error, reason} -> {:error, "debugger auto_tick_start failed: #{inspect(reason)}"}
    end
  end

  def call("debugger.auto_tick_stop", %{"slug" => slug}) do
    with {:ok, _project} <- ToolSupport.fetch_project(slug),
         {:ok, state} <- Debugger.stop_auto_tick(slug) do
      {:ok, debugger_slug_state_payload(slug, state)}
    else
      {:error, reason} -> {:error, "debugger auto_tick_stop failed: #{inspect(reason)}"}
    end
  end

  def call("debugger.replay_recent", %{"slug" => slug} = args) do
    with {:ok, replay_mode} <- parse_replay_mode_arg(Map.get(args, "replay_mode")),
         {:ok, replay_drift_seq} <- parse_replay_drift_seq(Map.get(args, "replay_drift_seq")),
         {:ok, _cursor_seq} <- parse_cursor_seq(args["cursor_seq"]),
         {:ok, _project} <- ToolSupport.fetch_project(slug),
         {:ok, state} <-
           Debugger.replay_recent(ToolSupport.project_session_key(slug), %{
             target: Map.get(args, "target"),
             count: Map.get(args, "count"),
             cursor_seq: Map.get(args, "cursor_seq"),
             replay_mode: replay_mode,
             replay_drift_seq: replay_drift_seq
           }) do
      {:ok, debugger_slug_state_payload(slug, state)}
    else
      {:error, "invalid replay_mode (expected frozen|live)"} = err ->
        err

      {:error, "invalid replay_drift_seq (expected non-negative integer)"} = err ->
        err

      {:error, "invalid cursor_seq (expected non-negative integer)"} = err ->
        err

      {:error, reason} ->
        {:error, "debugger replay_recent failed: #{inspect(reason)}"}
    end
  end

  def call("debugger.continue_from_snapshot", %{"slug" => slug} = args) do
    with {:ok, _cursor_seq} <- parse_cursor_seq(args["cursor_seq"]),
         {:ok, _project} <- ToolSupport.fetch_project(slug),
         {:ok, state} <-
           Debugger.continue_from_snapshot(ToolSupport.project_session_key(slug), %{
             cursor_seq: Map.get(args, "cursor_seq")
           }) do
      {:ok, debugger_slug_state_payload(slug, state)}
    else
      {:error, "invalid cursor_seq (expected non-negative integer)"} = err ->
        err

      {:error, reason} ->
        {:error, "debugger continue_from_snapshot failed: #{inspect(reason)}"}
    end
  end

  def call("debugger.export_trace", %{"slug" => slug} = args) do
    with {:ok, compare_cursor_seq} <-
           parse_compare_cursor_seq(Map.get(args, "compare_cursor_seq")),
         {:ok, baseline_cursor_seq} <-
           parse_baseline_cursor_seq(Map.get(args, "baseline_cursor_seq")),
         {:ok, _project} <- ToolSupport.fetch_project(slug),
         {:ok, export} <-
           Debugger.export_trace(ToolSupport.project_session_key(slug),
             event_limit: parse_event_limit(args["event_limit"]),
             compare_cursor_seq: compare_cursor_seq,
             baseline_cursor_seq: baseline_cursor_seq
           ) do
      {:ok, debugger_export_trace_payload(slug, export)}
    else
      {:error, "invalid compare_cursor_seq (expected non-negative integer)"} = err ->
        err

      {:error, "invalid baseline_cursor_seq (expected non-negative integer)"} = err ->
        err

      {:error, reason} ->
        {:error, "debugger export_trace failed: #{inspect(reason)}"}
    end
  end

  def call("debugger.import_trace", %{"slug" => slug, "export_json" => json} = args)
      when is_binary(json) do
    strict? =
      case Map.get(args, "strict_slug", true) do
        value when value in [false, "false"] -> false
        _ -> true
      end

    opts = if strict?, do: [strict_slug: true], else: [strict_slug: false]
    expected_sha = Map.get(args, "expected_sha256")

    with {:ok, _project} <- ToolSupport.fetch_project(slug),
         :ok <- verify_export_sha256(json, expected_sha),
         {:ok, state} <- Debugger.import_trace(ToolSupport.project_session_key(slug), json, opts) do
      {:ok, debugger_slug_state_payload(slug, state)}
    else
      {:error, reason} -> {:error, "debugger import_trace failed: #{inspect(reason)}"}
    end
  end

  @spec debugger_auto_fire_payload(
          String.t(),
          ProjectsTypes.debugger_settings(),
          DebuggerTypes.runtime_state()
        ) ::
          ToolTypes.debugger_auto_fire_result()
  defp debugger_auto_fire_payload(slug, settings, state)
       when is_binary(slug) and is_map(settings) and is_map(state) do
    %{
      slug: slug,
      auto_fire: ToolSupport.map_value(settings, "auto_fire") || %{},
      auto_fire_subscriptions: ToolSupport.map_value(settings, "auto_fire_subscriptions") || [],
      runtime_auto_tick: Map.get(state, :auto_tick) || %{}
    }
  end

  @spec debugger_auto_fire_settings_state_payload(
          String.t(),
          ProjectsTypes.auto_fire_targets(),
          [ProjectsTypes.subscription_row()],
          DebuggerTypes.runtime_state()
        ) :: ToolTypes.debugger_auto_fire_settings_state_result()
  defp debugger_auto_fire_settings_state_payload(slug, auto_fire, auto_fire_subscriptions, state)
       when is_binary(slug) and is_map(auto_fire) and is_list(auto_fire_subscriptions) and
              is_map(state) do
    %{
      slug: slug,
      auto_fire: auto_fire,
      auto_fire_subscriptions: auto_fire_subscriptions,
      state: state
    }
  end

  @spec debugger_configuration_payload(
          String.t(),
          DebuggerTypes.companion_configuration_values(),
          DebuggerTypes.companion_configuration()
        ) :: ToolTypes.debugger_configuration_result()
  defp debugger_configuration_payload(slug, values, configuration)
       when is_binary(slug) and is_map(values) and is_map(configuration) do
    %{slug: slug, values: values, configuration: configuration}
  end

  @spec debugger_configuration_values_state_payload(
          String.t(),
          DebuggerTypes.companion_configuration_values(),
          DebuggerTypes.runtime_state()
        ) :: ToolTypes.debugger_configuration_values_state_result()
  defp debugger_configuration_values_state_payload(slug, values, state)
       when is_binary(slug) and is_map(values) and is_map(state) do
    %{slug: slug, values: values, state: state}
  end

  @spec debugger_cursor_inspect_full_payload(
          String.t(),
          non_neg_integer() | nil,
          non_neg_integer(),
          [debugger_snapshot_ref()],
          SupportTypes.diagnostics_preview_result(),
          SupportTypes.surface_contracts_at_cursor(),
          SupportTypes.surface_fingerprints_at_cursor(),
          runtime_fingerprint_digest(),
          SupportTypes.events(),
          pos_integer(),
          pos_integer(),
          pos_integer(),
          pos_integer()
        ) :: ToolTypes.debugger_cursor_inspect_full_result()
  defp debugger_cursor_inspect_full_payload(
         slug,
         cursor_seq,
         event_window,
         snapshot_refs,
         diag,
         intro,
         runtime_fingerprints,
         runtime_fingerprint_digest,
         events,
         update_limit,
         protocol_limit,
         render_limit,
         lifecycle_limit
       )
       when is_map(diag) and is_list(events) do
    %{
      slug: slug,
      cursor_seq: cursor_seq,
      event_window: event_window,
      snapshot_refs: snapshot_refs,
      elmc_diagnostics: Map.get(diag, :rows, []),
      elmc_diagnostics_source: Map.get(diag, :source),
      debugger_contract: intro,
      elm_introspect: intro,
      runtime_fingerprints: runtime_fingerprints,
      runtime_fingerprint_digest: runtime_fingerprint_digest,
      update_messages:
        DebuggerSupport.update_messages_at_cursor(events, cursor_seq, update_limit),
      protocol_exchange:
        DebuggerSupport.protocol_exchange_at_cursor(events, cursor_seq, protocol_limit),
      view_renders: DebuggerSupport.render_events_at_cursor(events, cursor_seq, render_limit),
      lifecycle: DebuggerSupport.lifecycle_events_at_cursor(events, cursor_seq, lifecycle_limit)
    }
  end

  @spec debugger_cursor_inspect_replay_payload(
          String.t(),
          non_neg_integer(),
          non_neg_integer(),
          [debugger_snapshot_ref()]
        ) :: ToolTypes.debugger_cursor_inspect_replay_result()
  defp debugger_cursor_inspect_replay_payload(slug, cursor_seq, event_window, snapshot_refs) do
    %{
      slug: slug,
      cursor_seq: cursor_seq,
      event_window: event_window,
      snapshot_refs: snapshot_refs
    }
  end

  @spec debugger_disabled_subscriptions_payload(
          String.t(),
          ProjectsTypes.debugger_settings(),
          DebuggerTypes.runtime_state()
        ) :: ToolTypes.debugger_disabled_subscriptions_result()
  defp debugger_disabled_subscriptions_payload(slug, settings, state)
       when is_binary(slug) and is_map(settings) and is_map(state) do
    %{
      slug: slug,
      disabled_subscriptions: ToolSupport.map_value(settings, "disabled_subscriptions") || [],
      runtime_disabled_subscriptions: Map.get(state, :disabled_subscriptions) || []
    }
  end

  @spec debugger_disabled_subscriptions_state_payload(
          String.t(),
          [ProjectsTypes.subscription_row()],
          DebuggerTypes.runtime_state()
        ) :: ToolTypes.debugger_disabled_subscriptions_state_result()
  defp debugger_disabled_subscriptions_state_payload(slug, disabled_subscriptions, state)
       when is_binary(slug) and is_list(disabled_subscriptions) and is_map(state) do
    %{slug: slug, disabled_subscriptions: disabled_subscriptions, state: state}
  end

  @spec debugger_export_trace_payload(String.t(), debugger_export_payload()) ::
          ToolTypes.debugger_export_trace_result()
  defp debugger_export_trace_payload(slug, export) when is_binary(slug) and is_map(export) do
    %{
      slug: slug,
      export_json: Map.fetch!(export, :json),
      sha256: Map.fetch!(export, :sha256),
      byte_size: Map.fetch!(export, :byte_size)
    }
  end

  @spec debugger_models_payload(
          String.t(),
          DebuggerTypes.runtime_state(),
          ToolTypes.debugger_models_map()
        ) ::
          ToolTypes.debugger_models_result()
  defp debugger_models_payload(slug, state, models) when is_map(state) and is_map(models) do
    %{
      slug: slug,
      seq: Map.get(state, :seq, 0),
      running: Map.get(state, :running, false),
      revision: Map.get(state, :revision),
      watch_profile_id: Map.get(state, :watch_profile_id),
      models: models
    }
  end

  @spec debugger_render_tree_payload(
          String.t(),
          DebuggerTypes.surface_target(),
          ToolTypes.debugger_screen(),
          DebuggerTypes.rendered_tree(),
          [SupportTypes.flattened_rendered_node()],
          boolean()
        ) :: ToolTypes.render_tree_result()
  defp debugger_render_tree_payload(slug, target_atom, screen, tree, nodes, include_tree?) do
    payload = %{
      slug: slug,
      target: Atom.to_string(target_atom),
      screen: screen,
      root_type: rendered_node_type(tree),
      node_count: length(nodes),
      nodes: nodes
    }

    if include_tree?, do: Map.put(payload, :tree, tree), else: payload
  end

  @spec debugger_simulator_settings_payload(
          String.t(),
          Ide.Debugger.Types.simulator_settings(),
          Ide.Debugger.Types.simulator_settings()
        ) :: ToolTypes.debugger_simulator_settings_result()
  defp debugger_simulator_settings_payload(slug, settings, persisted) do
    %{slug: slug, settings: settings, persisted_settings: persisted}
  end

  @spec debugger_simulator_settings_state_payload(
          String.t(),
          DebuggerTypes.simulator_settings(),
          DebuggerTypes.runtime_state()
        ) ::
          ToolTypes.debugger_simulator_settings_state_result()
  defp debugger_simulator_settings_state_payload(slug, settings, state)
       when is_binary(slug) and is_map(settings) and is_map(state) do
    %{slug: slug, settings: settings, state: state}
  end

  @spec debugger_slug_state_payload(String.t(), DebuggerTypes.runtime_state()) ::
          ToolTypes.debugger_slug_state_result()
  defp debugger_slug_state_payload(slug, state) when is_binary(slug) and is_map(state) do
    %{slug: slug, state: state}
  end

  @spec debugger_state_full_payload(
          String.t(),
          DebuggerTypes.runtime_state(),
          SupportTypes.surface_fingerprints_at_cursor(),
          runtime_fingerprint_digest(),
          [debugger_snapshot_ref()]
        ) :: ToolTypes.debugger_state_full_result()
  defp debugger_state_full_payload(slug, state, fingerprints, digest, snapshot_refs) do
    %{
      slug: slug,
      state: state,
      runtime_fingerprints: fingerprints,
      runtime_fingerprint_digest: digest,
      snapshot_refs: snapshot_refs
    }
  end

  @spec debugger_state_replay_payload(
          String.t(),
          non_neg_integer(),
          runtime_fingerprint_digest(),
          [debugger_snapshot_ref()]
        ) :: ToolTypes.debugger_state_replay_result()
  defp debugger_state_replay_payload(slug, event_window, digest, snapshot_refs) do
    %{
      slug: slug,
      event_window: event_window,
      runtime_fingerprint_digest: digest,
      snapshot_refs: snapshot_refs
    }
  end

  @spec debugger_surface_state_payload(
          String.t(),
          DebuggerTypes.runtime_state(),
          DebuggerTypes.surface_target(),
          ToolTypes.debugger_screen(),
          ToolTypes.debugger_surface_model_entry(),
          DebuggerTypes.execution_model(),
          SupportTypes.events(),
          ToolTypes.debugger_render_tree_summary() | nil
        ) :: ToolTypes.debugger_surface_state_result()
  defp debugger_surface_state_payload(
         slug,
         state,
         target_atom,
         screen,
         model,
         runtime,
         events,
         render_tree
       )
       when is_map(state) and is_map(runtime) do
    %{
      slug: slug,
      seq: Map.get(state, :seq, 0),
      target: Atom.to_string(target_atom),
      screen: screen,
      model: model,
      last_message: ToolSupport.map_get_any(runtime, [:last_message, "last_message"], nil),
      protocol_messages:
        ToolSupport.map_get_any(runtime, [:protocol_messages, "protocol_messages"], []),
      runtime_fingerprint:
        events
        |> DebuggerSupport.runtime_fingerprints_at_cursor(nil)
        |> Map.get(target_atom),
      render_tree: render_tree
    }
  end

  @spec debugger_timeline_payload(
          String.t(),
          DebuggerTypes.runtime_state(),
          [DebuggerTypes.runtime_event() | DebuggerTypes.debugger_event()]
        ) ::
          ToolTypes.debugger_timeline_result()
  defp debugger_timeline_payload(slug, state, events) do
    %{
      slug: slug,
      seq: Map.get(state, :seq, 0),
      count: length(events),
      timeline: Enum.map(events, &compact_debugger_event/1)
    }
  end

  @spec debugger_watch_profiles_payload() :: ToolTypes.debugger_watch_profiles_result()
  defp debugger_watch_profiles_payload do
    %{watch_profiles: Debugger.watch_profiles()}
  end

  @spec project_simulator_settings(Project.t()) :: DebuggerTypes.simulator_settings()
  defp project_simulator_settings(project) when is_map(project) do
    project
    |> Map.get(:debugger_settings, %{})
    |> ToolSupport.map_value("simulator")
    |> ToolSupport.normalize_mcp_simulator_settings()
  end

  @spec maybe_persist_project_debugger_setting(
          Project.t(),
          String.t(),
          WireTypes.debugger_setting_value()
        ) ::
          :ok
  defp maybe_persist_project_debugger_setting(project, key, value)
       when is_map(project) and is_binary(key) do
    case persist_project_debugger_setting(project, key, value) do
      {:ok, _project} -> :ok
      {:error, :enoent} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  @spec normalize_configuration_values(DebuggerTypes.companion_configuration_values()) ::
          DebuggerTypes.companion_configuration_values()
  defp normalize_configuration_values(values) when is_map(values) do
    Map.new(values, fn
      {key, list} when is_list(list) -> {to_string(key), List.last(list)}
      {key, value} -> {to_string(key), value}
    end)
  end

  @spec persist_project_debugger_setting(
          Project.t(),
          String.t(),
          WireTypes.debugger_setting_value()
        ) ::
          {:ok, Project.t()} | {:error, ToolTypes.tool_persist_error()}
  defp persist_project_debugger_setting(project, key, value)
       when is_map(project) and is_binary(key) do
    settings =
      project
      |> Map.get(:debugger_settings, %{})
      |> Map.put(key, value)

    Projects.update_project(project, %{"debugger_settings" => settings})
  end

  @spec persist_project_auto_fire_setting(Project.t(), ToolTypes.debugger_subscription_setting_attrs()) ::
          {:ok, Project.t()} | {:error, ToolTypes.tool_persist_error()}
  defp persist_project_auto_fire_setting(project, attrs) when is_map(project) and is_map(attrs) do
    target = debugger_setting_target(ToolSupport.map_value(attrs, "target"))
    trigger = ToolSupport.map_value(attrs, "trigger")
    enabled? = ToolSupport.normalize_mcp_boolean(ToolSupport.map_value(attrs, "enabled"), false)
    settings = Map.get(project, :debugger_settings) || %{}

    updated_settings =
      if is_binary(trigger) and String.trim(trigger) != "" do
        subscriptions =
          settings
          |> ToolSupport.map_value("auto_fire_subscriptions")
          |> update_project_auto_fire_subscriptions(target, trigger, enabled?)

        auto_fire = ToolSupport.map_value(settings, "auto_fire") || %{}

        settings
        |> Map.put("auto_fire", Map.put(auto_fire, target, false))
        |> Map.put("auto_fire_subscriptions", subscriptions)
      else
        auto_fire = ToolSupport.map_value(settings, "auto_fire") || %{}
        Map.put(settings, "auto_fire", Map.put(auto_fire, target, enabled?))
      end

    Projects.update_project(project, %{"debugger_settings" => updated_settings})
  end

  @spec persist_project_disabled_subscription_setting(
          Project.t(),
          ToolTypes.debugger_subscription_setting_attrs()
        ) ::
          {:ok, Project.t()} | {:error, ToolTypes.tool_persist_error()}
  defp persist_project_disabled_subscription_setting(project, attrs)
       when is_map(project) and is_map(attrs) do
    target = debugger_setting_target(ToolSupport.map_value(attrs, "target"))
    trigger = ToolSupport.map_value(attrs, "trigger")
    enabled? = ToolSupport.normalize_mcp_boolean(ToolSupport.map_value(attrs, "enabled"), false)
    settings = Map.get(project, :debugger_settings) || %{}

    disabled_subscriptions =
      settings
      |> ToolSupport.map_value("disabled_subscriptions")
      |> update_project_disabled_subscriptions(target, trigger, enabled?)

    Projects.update_project(project, %{
      "debugger_settings" => Map.put(settings, "disabled_subscriptions", disabled_subscriptions)
    })
  end

  @spec update_project_auto_fire_subscriptions(
          [ProjectsTypes.subscription_row()],
          String.t(),
          String.t(),
          boolean()
        ) :: [ProjectsTypes.subscription_row()]
  defp update_project_auto_fire_subscriptions(subscriptions, target, trigger, enabled?) do
    trigger = String.trim(to_string(trigger))

    subscriptions =
      subscriptions
      |> List.wrap()
      |> Enum.filter(&is_map/1)
      |> Enum.reject(
        &(ToolSupport.map_value(&1, "target") == target and
            ToolSupport.map_value(&1, "trigger") == trigger)
      )

    if enabled? and trigger != "" do
      [%{"target" => target, "trigger" => trigger} | subscriptions]
    else
      subscriptions
    end
    |> Enum.uniq_by(&{ToolSupport.map_value(&1, "target"), ToolSupport.map_value(&1, "trigger")})
  end

  @spec update_project_disabled_subscriptions(
          [ProjectsTypes.subscription_row()],
          String.t(),
          String.t(),
          boolean()
        ) :: [ProjectsTypes.subscription_row()]
  defp update_project_disabled_subscriptions(subscriptions, target, trigger, enabled?)
       when is_binary(trigger) and trigger != "" do
    trigger = String.trim(trigger)

    subscriptions =
      subscriptions
      |> List.wrap()
      |> Enum.filter(&is_map/1)
      |> Enum.reject(
        &(ToolSupport.map_value(&1, "target") == target and
            ToolSupport.map_value(&1, "trigger") == trigger)
      )

    if enabled? do
      subscriptions
    else
      [%{"target" => target, "trigger" => trigger} | subscriptions]
    end
    |> Enum.uniq_by(&{ToolSupport.map_value(&1, "target"), ToolSupport.map_value(&1, "trigger")})
  end

  defp update_project_disabled_subscriptions(subscriptions, _target, _trigger, _enabled?),
    do: subscriptions |> List.wrap() |> Enum.filter(&is_map/1)

  @spec debugger_setting_target(String.t() | atom()) :: String.t()
  defp debugger_setting_target("protocol"), do: "protocol"
  defp debugger_setting_target("companion"), do: "phone"
  defp debugger_setting_target("phone"), do: "phone"
  defp debugger_setting_target(_target), do: "watch"
  @spec parse_event_limit(WireTypes.limit_input()) :: pos_integer()
  defp parse_event_limit(value) when is_integer(value) and value > 0, do: min(value, 500)

  defp parse_event_limit(value) when is_binary(value) do
    case Integer.parse(value) do
      {parsed, _} when parsed > 0 -> min(parsed, 500)
      _ -> 50
    end
  end

  defp parse_event_limit(_), do: 50

  @spec parse_since_seq(WireTypes.cursor_seq_input()) :: non_neg_integer() | nil
  defp parse_since_seq(value) when is_integer(value) and value >= 0, do: value

  defp parse_since_seq(value) when is_binary(value) do
    case Integer.parse(value) do
      {parsed, _} when parsed >= 0 -> parsed
      _ -> nil
    end
  end

  defp parse_since_seq(_), do: nil

  @spec parse_render_tree_target(WireTypes.render_tree_target_input()) ::
          {:ok, :watch | :companion | :phone} | {:error, atom()}
  defp parse_render_tree_target(nil), do: {:ok, :watch}
  defp parse_render_tree_target(""), do: {:ok, :watch}
  defp parse_render_tree_target("watch"), do: {:ok, :watch}
  defp parse_render_tree_target("companion"), do: {:ok, :companion}
  defp parse_render_tree_target("phone"), do: {:ok, :phone}
  defp parse_render_tree_target(:watch), do: {:ok, :watch}
  defp parse_render_tree_target(:companion), do: {:ok, :companion}
  defp parse_render_tree_target(:phone), do: {:ok, :phone}
  defp parse_render_tree_target(_target), do: {:error, :invalid_target}

  @spec parse_optional_debugger_targets(WireTypes.debugger_targets_input()) ::
          {:ok, [:watch | :companion | :phone]} | {:error, atom()}
  defp parse_optional_debugger_targets(nil), do: {:ok, [:watch, :companion, :phone]}
  defp parse_optional_debugger_targets(""), do: {:ok, [:watch, :companion, :phone]}

  defp parse_optional_debugger_targets(target) do
    case parse_render_tree_target(target) do
      {:ok, target_atom} -> {:ok, [target_atom]}
      {:error, reason} -> {:error, reason}
    end
  end

  @spec debugger_surface_runtime(DebuggerTypes.runtime_state(), DebuggerTypes.surface_target()) ::
          {:ok, DebuggerTypes.execution_model() | nil} | {:error, atom()}
  defp debugger_surface_runtime(state, target) when target in [:watch, :companion, :phone] do
    {:ok, Map.get(state, target)}
  end

  @spec debugger_render_tree(DebuggerTypes.execution_model()) ::
          {:ok, DebuggerTypes.rendered_tree()} | {:error, :no_rendered_tree}
  defp debugger_render_tree(runtime) when is_map(runtime) do
    case DebuggerSupport.rendered_tree(runtime) do
      tree when is_map(tree) -> {:ok, tree}
      _ -> {:error, :no_rendered_tree}
    end
  end

  defp debugger_render_tree_error(:no_rendered_tree), do: ":no_rendered_tree"
  defp debugger_render_tree_error(reason), do: inspect(reason)

  @spec surface_model_payload(
          DebuggerTypes.runtime_state(),
          DebuggerTypes.surface_target(),
          boolean()
        ) :: ToolTypes.debugger_surface_model_entry()
  defp surface_model_payload(state, target, include_view_output?)
       when target in [:watch, :companion, :phone] do
    runtime = Map.get(state, target) || %{}
    model = runtime_model_map(runtime)

    %{
      target: Atom.to_string(target),
      model: compact_debugger_model(model, include_view_output?),
      runtime_model:
        model
        |> ToolSupport.map_get_any(["runtime_model", :runtime_model], %{})
        |> compact_debugger_model(include_view_output?),
      model_keys: model |> Map.keys() |> Enum.map(&to_string/1) |> Enum.sort(),
      runtime_model_keys:
        model
        |> ToolSupport.map_get_any(["runtime_model", :runtime_model], %{})
        |> model_keys(),
      last_message: ToolSupport.map_get_any(runtime, [:last_message, "last_message"], nil),
      view_tree_type:
        runtime
        |> ToolSupport.map_get_any(["view_tree", :view_tree], %{})
        |> rendered_node_type()
    }
  end

  @spec compact_debugger_model(DebuggerTypes.app_model(), boolean()) :: DebuggerTypes.app_model()
  defp compact_debugger_model(model, include_view_output?) when is_map(model) do
    drop_keys =
      [
        "elm_introspect",
        :elm_introspect,
        "debugger_contract",
        :debugger_contract
      ] ++
        if include_view_output? do
          []
        else
          ["runtime_view_output", :runtime_view_output]
        end

    Map.drop(model, drop_keys)
  end

  defp compact_debugger_model(_model, _include_view_output?), do: %{}

  @spec model_keys(DebuggerTypes.app_model()) :: [String.t()]
  defp model_keys(model) when is_map(model) do
    model
    |> Map.keys()
    |> Enum.map(&model_key_to_string/1)
    |> Enum.sort()
  end

  defp model_keys(_model), do: []

  @spec model_key_to_string(atom() | String.t() | integer()) :: String.t()
  defp model_key_to_string(key) when is_atom(key), do: Atom.to_string(key)
  defp model_key_to_string(key) when is_binary(key), do: key
  defp model_key_to_string(key) when is_integer(key), do: Integer.to_string(key)

  @spec maybe_render_tree_payload(
          DebuggerTypes.execution_model() | nil,
          ToolTypes.debugger_screen(),
          boolean()
        ) :: ToolTypes.debugger_render_tree_summary() | nil
  defp maybe_render_tree_payload(runtime, screen, include?) do
    if include? && is_map(runtime) do
      case DebuggerSupport.rendered_tree(runtime) do
        %{} = tree ->
          nodes = flatten_rendered_nodes(tree, screen.width, screen.height)

          %{
            root_type: rendered_node_type(tree),
            node_count: length(nodes),
            nodes: nodes
          }

        _ ->
          nil
      end
    end
  end

  @spec preview_diagnostics_payload(
          String.t(),
          DebuggerTypes.runtime_state(),
          DebuggerTypes.execution_model(),
          DebuggerTypes.surface_target(),
          ToolTypes.debugger_screen(),
          SupportTypes.surface_fingerprints_at_cursor(),
          SupportTypes.events(),
          non_neg_integer() | nil
        ) :: ToolTypes.debugger_preview_diagnostics_result()
  defp preview_diagnostics_payload(
         slug,
         state,
         runtime,
         target,
         screen,
         runtime_fingerprints,
         events,
         cursor_seq
       ) do
    model = runtime_model_map(runtime)
    view_tree = ToolSupport.map_get_any(runtime, ["view_tree", :view_tree], nil)
    rendered_tree = DebuggerSupport.rendered_tree(runtime)
    runtime_output = runtime_view_output_rows(model)
    ei = Ide.Debugger.RuntimeArtifacts.require_introspect(model)

    render_source = preview_render_source(runtime_output, view_tree, rendered_tree, ei)

    nodes =
      if is_map(rendered_tree) do
        preview_nodes(rendered_tree, screen)
      else
        []
      end

    root_type = rendered_node_type(rendered_tree)

    runtime_fingerprint =
      case Map.get(runtime_fingerprints, target) do
        %{} = fp -> fp
        _ -> nil
      end

    surface_tree_sha256 = if is_map(view_tree), do: stable_term_sha256(view_tree), else: nil

    fingerprint_view_tree_sha256 =
      ToolSupport.map_get_any(
        runtime_fingerprint || %{},
        [:view_tree_sha256, "view_tree_sha256"],
        nil
      )

    %{
      slug: slug,
      target: Atom.to_string(target),
      seq: Map.get(state, :seq),
      revision: Map.get(state, :revision),
      watch_profile_id: Map.get(state, :watch_profile_id),
      screen: screen,
      status: preview_status(render_source, nodes),
      render_source: render_source,
      root_type: root_type,
      node_count: length(nodes),
      runtime_view_output_count: length(runtime_output),
      runtime_view_output_kinds: runtime_view_output_kinds(runtime_output),
      runtime_view_tree_type: rendered_node_type(view_tree),
      model_keys: model |> Map.keys() |> Enum.map(&to_string/1) |> Enum.sort(),
      runtime_model_keys:
        model
        |> ToolSupport.map_get_any(["runtime_model", :runtime_model], %{})
        |> model_keys(),
      runtime_fingerprint: runtime_fingerprint,
      surface_tree_sha256: surface_tree_sha256,
      fingerprint_view_tree_sha256: fingerprint_view_tree_sha256,
      latest_render_events: DebuggerSupport.render_events_at_cursor(events, cursor_seq, 8),
      latest_lifecycle: DebuggerSupport.lifecycle_events_at_cursor(events, cursor_seq, 8),
      findings:
        preview_findings(
          render_source,
          rendered_tree,
          runtime_output,
          view_tree,
          surface_tree_sha256,
          fingerprint_view_tree_sha256,
          ei,
          model
        )
    }
  end

  @spec runtime_view_output_rows(DebuggerTypes.execution_model()) :: [
          DebuggerTypes.view_output_row()
        ]
  defp runtime_view_output_rows(model) when is_map(model) do
    case ToolSupport.map_get_any(model, ["runtime_view_output", :runtime_view_output], []) do
      rows when is_list(rows) -> Enum.filter(rows, &is_map/1)
      _ -> []
    end
  end

  @spec runtime_view_output_kinds([DebuggerTypes.view_output_row()]) :: [String.t()]
  defp runtime_view_output_kinds(rows) when is_list(rows) do
    rows
    |> Enum.map(fn row ->
      ToolSupport.map_get_any(row, ["kind", :kind, "type", :type, "op", :op], nil)
    end)
    |> Enum.reject(&is_nil/1)
    |> Enum.map(&to_string/1)
    |> Enum.uniq()
    |> Enum.take(24)
  end

  @spec preview_render_source(
          [DebuggerTypes.view_output_row()],
          DebuggerTypes.view_output_tree() | nil,
          DebuggerTypes.rendered_tree() | nil,
          DebuggerTypes.elm_introspect()
        ) :: String.t()
  defp preview_render_source([_ | _], _view_tree, _rendered_tree, _ei), do: "runtime_view_output"

  defp preview_render_source([], %{} = view_tree, _rendered_tree, ei) when is_map(ei) do
    if parser_expression_view_tree?(view_tree, ei),
      do: "parser_view_tree",
      else: "runtime_view_tree"
  end

  defp preview_render_source([], _view_tree, %{} = _rendered_tree, _ei), do: "parser_view_tree"
  defp preview_render_source([], _view_tree, _rendered_tree, _ei), do: "none"

  @spec preview_status(String.t(), [SupportTypes.flattened_rendered_node()]) :: String.t()
  defp preview_status("none", _nodes), do: "empty"
  defp preview_status("parser_view_tree", _nodes), do: "fallback"
  defp preview_status(_source, []), do: "empty"
  defp preview_status(_source, _nodes), do: "ok"

  @spec preview_nodes(DebuggerTypes.rendered_tree(), ToolTypes.debugger_screen()) ::
          [SupportTypes.flattened_rendered_node()]
  defp preview_nodes(tree, screen) when is_map(tree) and is_map(screen) do
    flatten_rendered_nodes(
      tree,
      integer_or_default(ToolSupport.map_get_any(screen, ["width", :width], nil), 0),
      integer_or_default(ToolSupport.map_get_any(screen, ["height", :height], nil), 0)
    )
  end

  @spec preview_findings(
          String.t(),
          DebuggerTypes.rendered_tree() | nil,
          [DebuggerTypes.view_output_row()],
          DebuggerTypes.view_output_tree() | nil,
          String.t() | nil,
          String.t() | nil,
          DebuggerTypes.elm_introspect(),
          DebuggerTypes.execution_model()
        ) :: [String.t()]
  defp preview_findings(
         render_source,
         rendered_tree,
         runtime_output,
         view_tree,
         surface_tree_sha256,
         fingerprint_view_tree_sha256,
         ei,
         model
       )
       when is_map(ei) and is_map(model) do
    []
    |> maybe_add_finding(
      Ide.Debugger.RuntimeModelQuality.unresolved_field_names(model) != [],
      "runtime_model_has_parser_artifacts"
    )
    |> maybe_add_finding(runtime_output == [], "no_runtime_view_output")
    |> maybe_add_finding(not is_map(rendered_tree), "no_rendered_tree")
    |> maybe_add_finding(render_source == "parser_view_tree", "using_static_parser_view_tree")
    |> maybe_add_finding(
      fingerprint_view_tree_sha256_mismatch?(surface_tree_sha256, fingerprint_view_tree_sha256),
      "surface_tree_differs_from_runtime_fingerprint"
    )
    |> maybe_add_finding(
      parser_expression_view_tree?(view_tree, ei),
      "runtime_view_tree_is_expression_outline"
    )
    |> Enum.reverse()
  end

  @spec maybe_add_finding([String.t()], boolean(), String.t()) :: [String.t()]
  defp maybe_add_finding(findings, condition, finding) when is_boolean(condition) do
    if condition, do: [finding | findings], else: findings
  end

  @spec fingerprint_view_tree_sha256_mismatch?(String.t(), String.t()) :: boolean()
  defp fingerprint_view_tree_sha256_mismatch?(displayed, fingerprint)
       when is_binary(displayed) and is_binary(fingerprint) and displayed != "" and
              fingerprint != "",
       do: displayed != fingerprint

  defp fingerprint_view_tree_sha256_mismatch?(_displayed, _fingerprint), do: false

  @spec stable_term_sha256(DebuggerTypes.view_output_tree() | DebuggerTypes.wire_string_map()) ::
          String.t()
  defp stable_term_sha256(term) do
    :crypto.hash(:sha256, :erlang.term_to_binary(term))
    |> Base.encode16(case: :lower)
  end

  @spec parser_expression_view_tree?(DebuggerTypes.view_output_tree() | nil, DebuggerTypes.elm_introspect()) ::
          boolean()
  defp parser_expression_view_tree?(tree, ei) when is_map(tree) and is_map(ei),
    do: ElmEx.DebuggerContract.parser_expression_view_tree_node?(tree, ei)

  defp parser_expression_view_tree?(_tree, _ei), do: false

  @spec compact_debugger_event(DebuggerTypes.runtime_event() | DebuggerTypes.debugger_event()) ::
          ToolTypes.debugger_timeline_event()
  defp compact_debugger_event(event) when is_map(event) do
    payload = Map.get(event, :payload) || Map.get(event, "payload") || %{}

    %{
      seq: Map.get(event, :seq) || Map.get(event, "seq"),
      type: Map.get(event, :type) || Map.get(event, "type"),
      target: compact_event_target(payload),
      summary: compact_event_summary(event, payload),
      payload: compact_event_payload(payload)
    }
  end

  @spec compact_event_target(DebuggerTypes.event_payload()) :: String.t() | nil
  defp compact_event_target(payload) when is_map(payload) do
    value =
      ToolSupport.map_get_any(
        payload,
        [
          :target,
          "target",
          :source_root,
          "source_root",
          :from,
          "from"
        ],
        nil
      )

    if is_nil(value), do: nil, else: to_string(value)
  end

  @spec compact_event_summary(
          DebuggerTypes.runtime_event() | DebuggerTypes.debugger_event(),
          DebuggerTypes.event_payload()
        ) :: String.t()
  defp compact_event_summary(event, payload) do
    type = Map.get(event, :type) || Map.get(event, "type") || "event"

    [
      ToolSupport.map_get_any(payload, [:message, "message"], nil),
      ToolSupport.map_get_any(payload, [:reason, "reason"], nil),
      ToolSupport.map_get_any(payload, [:rel_path, "rel_path"], nil),
      ToolSupport.map_get_any(payload, [:revision, "revision"], nil)
    ]
    |> Enum.reject(&is_nil/1)
    |> Enum.map(&to_string/1)
    |> case do
      [] -> to_string(type)
      parts -> Enum.join([to_string(type) | parts], " · ")
    end
  end

  @spec compact_event_payload(DebuggerTypes.debugger_timeline_payload()) ::
          DebuggerTypes.compact_timeline_event_payload()
  defp compact_event_payload(payload) when is_map(payload) do
    payload
    |> Map.take([
      :target,
      "target",
      :message,
      "message",
      :message_source,
      "message_source",
      :rel_path,
      "rel_path",
      :source_root,
      "source_root",
      :reason,
      "reason",
      :revision,
      "revision",
      :status,
      "status",
      :error_count,
      "error_count",
      :warning_count,
      "warning_count",
      :from,
      "from",
      :to,
      "to"
    ])
    |> stringify_map_keys()
  end

  @spec stringify_map_keys(DebuggerTypes.wire_map() | DebuggerTypes.wire_string_map()) ::
          DebuggerTypes.wire_string_map()
  defp stringify_map_keys(map) when is_map(map) do
    Map.new(map, fn {key, value} -> {to_string(key), value} end)
  end

  @spec debugger_reload_source(Project.t(), String.t(), String.t(), WireTypes.json_value()) ::
          {:ok, String.t()} | {:error, ToolTypes.tool_persist_error()}
  defp debugger_reload_source(_project, _source_root, _rel_path, source) when is_binary(source),
    do: {:ok, source}

  defp debugger_reload_source(project, source_root, rel_path, _source) do
    case Projects.read_source_file(project, source_root, rel_path) do
      {:ok, source} -> {:ok, source}
      {:error, :enoent} -> {:ok, ""}
      {:error, reason} -> {:error, reason}
    end
  end

  @spec debugger_surface_screen(
          DebuggerTypes.runtime_state(),
          DebuggerTypes.execution_model(),
          atom()
        ) :: ToolTypes.debugger_screen()
  defp debugger_surface_screen(state, runtime, :watch) do
    launch_screen =
      state
      |> Map.get(:launch_context, %{})
      |> ToolSupport.map_get_any(["screen", :screen], %{})

    model = runtime_model_map(runtime)

    %{
      width:
        integer_or_default(
          ToolSupport.map_get_any(
            launch_screen,
            ["width", :width],
            ToolSupport.map_get_any(model, ["screen_width"], 144)
          ),
          144
        ),
      height:
        integer_or_default(
          ToolSupport.map_get_any(
            launch_screen,
            ["height", :height],
            ToolSupport.map_get_any(model, ["screen_height"], 168)
          ),
          168
        )
    }
  end

  defp debugger_surface_screen(_state, runtime, _target) do
    box =
      runtime
      |> ToolSupport.map_get_any(["view_tree", :view_tree], %{})
      |> ToolSupport.map_get_any(["box", :box], %{})

    %{
      width: integer_or_default(ToolSupport.map_get_any(box, ["w", :w], nil), 0),
      height: integer_or_default(ToolSupport.map_get_any(box, ["h", :h], nil), 0)
    }
  end

  @spec runtime_model_map(DebuggerTypes.execution_model()) :: DebuggerTypes.inner_runtime_model()
  defp runtime_model_map(runtime) when is_map(runtime) do
    case ToolSupport.map_get_any(runtime, ["model", :model], %{}) do
      model when is_map(model) -> model
      _ -> %{}
    end
  end

  defp runtime_model_map(_runtime), do: %{}

  @spec flatten_rendered_nodes(DebuggerTypes.rendered_tree(), integer(), integer()) :: [
          SupportTypes.flattened_rendered_node()
        ]
  defp flatten_rendered_nodes(tree, screen_w, screen_h) do
    do_flatten_rendered_nodes(tree, "0", tree, screen_w, screen_h)
  end

  @spec do_flatten_rendered_nodes(
          DebuggerTypes.rendered_tree(),
          String.t(),
          DebuggerTypes.rendered_tree(),
          integer(),
          integer()
        ) :: [SupportTypes.flattened_rendered_node()]
  defp do_flatten_rendered_nodes(node, path, root, screen_w, screen_h) when is_map(node) do
    current = %{
      path: path,
      type: rendered_node_type(node),
      label: rendered_node_label(node),
      bounds:
        DebuggerSupport.rendered_node_bounds(root, path, screen_w, screen_h) ||
          rendered_box_bounds(node),
      source: ToolSupport.map_get_any(node, ["source", :source], nil)
    }

    children =
      node
      |> ToolSupport.map_get_any(["children", :children], [])
      |> Enum.filter(&is_map/1)
      |> Enum.with_index()
      |> Enum.flat_map(fn {child, index} ->
        do_flatten_rendered_nodes(child, "#{path}.#{index}", root, screen_w, screen_h)
      end)

    [current | children]
  end

  defp do_flatten_rendered_nodes(_node, _path, _root, _screen_w, _screen_h), do: []

  @spec rendered_node_type(DebuggerTypes.rendered_tree()) :: String.t()
  defp rendered_node_type(node) when is_map(node) do
    node
    |> ToolSupport.map_get_any(["type", :type], "")
    |> to_string()
  end

  defp rendered_node_type(_node), do: ""

  @spec rendered_node_label(DebuggerTypes.rendered_tree()) :: String.t() | nil
  defp rendered_node_label(node) when is_map(node) do
    case ToolSupport.map_get_any(node, ["label", :label, "text", :text], nil) do
      nil -> nil
      value -> to_string(value)
    end
  end

  @spec rendered_box_bounds(DebuggerTypes.rendered_tree()) :: SupportTypes.bounds_map() | nil
  defp rendered_box_bounds(node) when is_map(node) do
    case ToolSupport.map_get_any(node, ["box", :box], nil) do
      %{} = box ->
        %{
          x: integer_or_default(ToolSupport.map_get_any(box, ["x", :x], nil), 0),
          y: integer_or_default(ToolSupport.map_get_any(box, ["y", :y], nil), 0),
          w: integer_or_default(ToolSupport.map_get_any(box, ["w", :w], nil), 0),
          h: integer_or_default(ToolSupport.map_get_any(box, ["h", :h], nil), 0)
        }

      _ ->
        nil
    end
  end

  @spec integer_or_default(WireTypes.integer_input(), integer()) :: integer()
  defp integer_or_default(value, _default) when is_integer(value), do: value

  defp integer_or_default(value, default) when is_binary(value) do
    case Integer.parse(value) do
      {parsed, _} -> parsed
      _ -> default
    end
  end

  defp integer_or_default(_value, default), do: default

  @spec include_replay_metadata?(WireTypes.boolean_input()) :: boolean()
  defp include_replay_metadata?(value) do
    cond do
      is_nil(value) -> true
      value in [false, 0, "0", "false", "FALSE", "False"] -> false
      true -> true
    end
  end

  @spec parse_compare_cursor_seq(WireTypes.cursor_seq_input()) ::
          {:ok, non_neg_integer() | nil} | {:error, String.t()}
  defp parse_compare_cursor_seq(nil), do: {:ok, nil}

  defp parse_compare_cursor_seq(value) do
    case parse_cursor_seq(value) do
      {:ok, seq} -> {:ok, seq}
      {:error, _} -> {:error, "invalid compare_cursor_seq (expected non-negative integer)"}
    end
  end

  @spec parse_baseline_cursor_seq(WireTypes.cursor_seq_input()) ::
          {:ok, non_neg_integer() | nil} | {:error, String.t()}
  defp parse_baseline_cursor_seq(nil), do: {:ok, nil}

  defp parse_baseline_cursor_seq(value) do
    case parse_cursor_seq(value) do
      {:ok, seq} -> {:ok, seq}
      {:error, _} -> {:error, "invalid baseline_cursor_seq (expected non-negative integer)"}
    end
  end

  @spec runtime_fingerprint_digest(SupportTypes.surface_fingerprints_at_cursor()) ::
          DebuggerTypes.runtime_fingerprint_digest()
  defp runtime_fingerprint_digest(runtime_fingerprints) when is_map(runtime_fingerprints) do
    [:watch, :companion, :phone]
    |> Enum.reduce(%{}, fn surface, acc ->
      case Map.get(runtime_fingerprints, surface) do
        %{} = fp ->
          Map.put(acc, surface, %{
            runtime_mode: Map.get(fp, :runtime_mode),
            engine: Map.get(fp, :engine),
            execution_backend: Map.get(fp, :execution_backend),
            external_fallback_reason: Map.get(fp, :external_fallback_reason),
            runtime_model_source: Map.get(fp, :runtime_model_source),
            view_tree_source: Map.get(fp, :view_tree_source),
            target_numeric_key: Map.get(fp, :target_numeric_key),
            target_numeric_key_source: Map.get(fp, :target_numeric_key_source),
            target_boolean_key: Map.get(fp, :target_boolean_key),
            target_boolean_key_source: Map.get(fp, :target_boolean_key_source),
            active_target_key: Map.get(fp, :active_target_key),
            active_target_key_source: Map.get(fp, :active_target_key_source),
            protocol_inbound_count: Map.get(fp, :protocol_inbound_count),
            protocol_message_count: Map.get(fp, :protocol_message_count),
            protocol_last_inbound_message: Map.get(fp, :protocol_last_inbound_message),
            runtime_model_sha256: Map.get(fp, :runtime_model_sha256),
            view_tree_sha256: Map.get(fp, :view_tree_sha256)
          })

        _ ->
          acc
      end
    end)
  end

  @spec runtime_fingerprint_compare(
          SupportTypes.events(),
          SupportTypes.surface_fingerprints_at_cursor(),
          integer() | nil,
          integer() | nil
        ) :: DebuggerTypes.mcp_fingerprint_compare_result() | nil
  defp runtime_fingerprint_compare(_events, _current, _current_seq, nil), do: nil

  defp runtime_fingerprint_compare(_events, _current, current_seq, _compare_cursor_seq)
       when not is_integer(current_seq),
       do: nil

  defp runtime_fingerprint_compare(events, current, current_seq, compare_cursor_seq)
       when is_list(events) and is_map(current) and is_integer(compare_cursor_seq) do
    resolved_compare_cursor = resolve_cursor_seq(events, compare_cursor_seq)
    compare = DebuggerSupport.runtime_fingerprints_at_cursor(events, resolved_compare_cursor)

    surfaces =
      [:watch, :companion, :phone]
      |> Enum.reduce(%{}, fn surface, acc ->
        current_fp = Map.get(current, surface)
        compare_fp = Map.get(compare, surface)
        current_digest = runtime_fingerprint_digest(%{surface => current_fp})[surface]
        compare_digest = runtime_fingerprint_digest(%{surface => compare_fp})[surface]

        if is_map(current_digest) or is_map(compare_digest) do
          backend_changed =
            Map.get(current_digest || %{}, :execution_backend) !=
              Map.get(compare_digest || %{}, :execution_backend) or
              Map.get(current_digest || %{}, :external_fallback_reason) !=
                Map.get(compare_digest || %{}, :external_fallback_reason)

          key_target_changed =
            Map.get(current_digest || %{}, :target_numeric_key) !=
              Map.get(compare_digest || %{}, :target_numeric_key) or
              Map.get(current_digest || %{}, :target_numeric_key_source) !=
                Map.get(compare_digest || %{}, :target_numeric_key_source) or
              Map.get(current_digest || %{}, :target_boolean_key) !=
                Map.get(compare_digest || %{}, :target_boolean_key) or
              Map.get(current_digest || %{}, :target_boolean_key_source) !=
                Map.get(compare_digest || %{}, :target_boolean_key_source) or
              Map.get(current_digest || %{}, :active_target_key) !=
                Map.get(compare_digest || %{}, :active_target_key) or
              Map.get(current_digest || %{}, :active_target_key_source) !=
                Map.get(compare_digest || %{}, :active_target_key_source)

          Map.put(acc, surface, %{
            changed: current_digest != compare_digest or key_target_changed,
            backend_changed: backend_changed,
            key_target_changed: key_target_changed,
            current: current_digest,
            compare: compare_digest
          })
        else
          acc
        end
      end)

    backend_drift_detail = RuntimeFingerprintDrift.backend_drift_detail(%{surfaces: surfaces})

    key_target_drift_detail =
      RuntimeFingerprintDrift.key_target_drift_detail(%{surfaces: surfaces})

    drift_detail =
      RuntimeFingerprintDrift.merge_drift_detail(backend_drift_detail, key_target_drift_detail)

    %{
      cursor_seq: current_seq,
      compare_cursor_seq: resolved_compare_cursor,
      backend_changed_surface_count:
        surfaces
        |> Map.values()
        |> Enum.count(fn row -> Map.get(row, :backend_changed) end),
      key_target_changed_surface_count:
        surfaces
        |> Map.values()
        |> Enum.count(fn row -> Map.get(row, :key_target_changed) end),
      backend_drift_detail: backend_drift_detail,
      key_target_drift_detail: key_target_drift_detail,
      drift_detail: drift_detail,
      surfaces: surfaces
    }
  end

  defp runtime_fingerprint_compare(_events, _current, _current_seq, _compare_cursor_seq), do: nil

  @spec maybe_put_runtime_fingerprint_compare(
          ToolTypes.debugger_state_result() | ToolTypes.debugger_cursor_inspect_result(),
          DebuggerTypes.mcp_fingerprint_compare_result() | nil
        ) ::
          ToolTypes.debugger_state_result() | ToolTypes.debugger_cursor_inspect_result()
  defp maybe_put_runtime_fingerprint_compare(payload, nil), do: payload

  defp maybe_put_runtime_fingerprint_compare(payload, compare) when is_map(compare) do
    Map.put(payload, :runtime_fingerprint_compare, compare)
  end

  @spec parse_replay_mode_arg(WireTypes.replay_mode_input()) ::
          {:ok, String.t() | nil} | {:error, String.t()}
  defp parse_replay_mode_arg(nil), do: {:ok, nil}
  defp parse_replay_mode_arg("frozen"), do: {:ok, "frozen"}
  defp parse_replay_mode_arg("live"), do: {:ok, "live"}
  defp parse_replay_mode_arg(_), do: {:error, "invalid replay_mode (expected frozen|live)"}

  @spec parse_replay_drift_seq(WireTypes.cursor_seq_input()) ::
          {:ok, non_neg_integer() | nil} | {:error, String.t()}
  defp parse_replay_drift_seq(nil), do: {:ok, nil}

  defp parse_replay_drift_seq(n) when is_integer(n) and n >= 0, do: {:ok, n}

  defp parse_replay_drift_seq(n) when is_binary(n) do
    case Integer.parse(n) do
      {i, _} when i >= 0 -> {:ok, i}
      _ -> {:error, "invalid replay_drift_seq (expected non-negative integer)"}
    end
  end

  defp parse_replay_drift_seq(_),
    do: {:error, "invalid replay_drift_seq (expected non-negative integer)"}

  @spec maybe_put_replay_metadata(
          ToolTypes.debugger_state_result() | ToolTypes.debugger_cursor_inspect_result(),
          DebuggerTypes.replay_metadata() | nil
        ) ::
          ToolTypes.debugger_state_result() | ToolTypes.debugger_cursor_inspect_result()
  defp maybe_put_replay_metadata(payload, replay_metadata) when is_map(payload) do
    if is_nil(replay_metadata) and Map.has_key?(payload, :replay_metadata) do
      Map.delete(payload, :replay_metadata)
    else
      case replay_metadata do
        nil -> payload
        metadata -> Map.put(payload, :replay_metadata, metadata)
      end
    end
  end

  @spec parse_cursor_inspect_event_limit(WireTypes.limit_input()) :: pos_integer()
  defp parse_cursor_inspect_event_limit(value) when is_integer(value) and value > 0,
    do: min(value, 500)

  defp parse_cursor_inspect_event_limit(value) when is_binary(value) do
    case Integer.parse(value) do
      {n, _} when n > 0 -> min(n, 500)
      _ -> 500
    end
  end

  defp parse_cursor_inspect_event_limit(_), do: 500

  @spec parse_cursor_seq(WireTypes.cursor_seq_input()) ::
          {:ok, non_neg_integer() | nil} | {:error, String.t()}
  defp parse_cursor_seq(nil), do: {:ok, nil}

  defp parse_cursor_seq(n) when is_integer(n) and n >= 0, do: {:ok, n}

  defp parse_cursor_seq(n) when is_binary(n) do
    case Integer.parse(n) do
      {i, _} when i >= 0 -> {:ok, i}
      _ -> {:error, "invalid cursor_seq (expected non-negative integer)"}
    end
  end

  defp parse_cursor_seq(_), do: {:error, "invalid cursor_seq (expected non-negative integer)"}

  @spec parse_inspect_table_limit(WireTypes.limit_input(), pos_integer()) :: pos_integer()
  defp parse_inspect_table_limit(nil, default), do: default

  defp parse_inspect_table_limit(n, _default) when is_integer(n) and n > 0, do: min(n, 100)

  defp parse_inspect_table_limit(n, default) when is_binary(n) do
    case Integer.parse(n) do
      {i, _} when i > 0 -> min(i, 100)
      _ -> default
    end
  end

  defp parse_inspect_table_limit(_, default), do: default

  @spec resolve_cursor_seq(SupportTypes.events(), integer() | nil) :: integer() | nil
  defp resolve_cursor_seq(events, requested_seq) when is_list(events) do
    CursorSeq.resolve_at_or_before(events, requested_seq)
  end

  @spec parse_event_types(WireTypes.event_types_input()) :: [String.t()] | nil
  defp parse_event_types(nil), do: nil

  defp parse_event_types(value) when is_list(value) do
    value
    |> Enum.filter(&is_binary/1)
    |> Enum.uniq()
    |> case do
      [] -> nil
      items -> items
    end
  end

  defp parse_event_types(_), do: nil
  @spec verify_export_sha256(String.t(), WireTypes.sha256_input()) :: :ok | {:error, atom()}
  defp verify_export_sha256(_json, nil), do: :ok
  defp verify_export_sha256(_json, ""), do: :ok

  defp verify_export_sha256(json, expected) when is_binary(json) do
    expected_normalized = expected |> to_string() |> String.trim() |> String.downcase()

    actual =
      :crypto.hash(:sha256, json)
      |> Base.encode16(case: :lower)

    if expected_normalized == actual do
      :ok
    else
      {:error, {:sha256_mismatch, %{expected: expected_normalized, actual: actual}}}
    end
  end

  @spec schedule_companion_bootstrap_if_present(Project.t()) :: :ok
  defp schedule_companion_bootstrap_if_present(%Project{} = project) do
    if skip_companion_bootstrap_schedule?() do
      :ok
    else
      if Projects.companion_app_present?(project) and not companion_session_bootstrapped?(project) do
        if companion_bootstrap_async?() do
          Task.start(fn -> run_companion_bootstrap_session(project) end)
        else
          run_companion_bootstrap_session(project)
        end
      end

      :ok
    end
  end

  @spec skip_companion_bootstrap_schedule?() :: boolean()
  defp skip_companion_bootstrap_schedule? do
    Application.get_env(:ide, :debugger_skip_companion_bootstrap_schedule, false)
  end

  @spec companion_bootstrap_async?() :: boolean()
  defp companion_bootstrap_async? do
    Application.get_env(:ide, :debugger_async_companion_bootstrap, true)
  end

  @spec companion_session_bootstrapped?(Project.t()) :: boolean()
  defp companion_session_bootstrapped?(project) do
    scope_key = ToolSupport.project_session_key(project.slug)

    case Debugger.snapshot(scope_key) do
      {:ok, state} -> DebuggerBootstrapFlow.companion_bootstrapped?(state)
      _ -> false
    end
  rescue
    _ -> false
  end

  @spec run_companion_bootstrap_session(Project.t()) :: :ok
  defp run_companion_bootstrap_session(%Project{} = project) do
    case DebuggerBootstrapFlow.run_companion_bootstrap(project, force_sync: false) do
      {:ok, _} -> :ok
      {:error, _} -> :ok
    end
  end
end
