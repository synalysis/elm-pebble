defmodule Ide.Debugger do
  @moduledoc """
  Lightweight debugger state substrate for watch, companion, and phone runtimes.
  """

  use Agent
  alias Ide.Debugger.CursorSeq
  alias Ide.Debugger.HttpExecutor
  alias Ide.Debugger.RuntimeExecutor
  alias Ide.Debugger.RuntimeFingerprintDrift
  alias Ide.PebblePreferences
  alias Ide.Projects
  alias Ide.WatchModels

  @dialyzer :no_match
  @history_limit 500
  @default_auto_fire_interval_ms 1_000
  @min_auto_fire_interval_ms 100

  @type runtime_event :: %{
          seq: non_neg_integer(),
          type: String.t(),
          payload: map(),
          watch: map(),
          companion: map(),
          phone: map()
        }
  @type debugger_event :: %{
          seq: non_neg_integer(),
          raw_seq: non_neg_integer(),
          type: String.t(),
          target: String.t(),
          message: String.t(),
          message_source: String.t() | nil,
          watch: map(),
          companion: map(),
          phone: map()
        }

  @type runtime_state :: %{
          running: boolean(),
          revision: String.t() | nil,
          watch_profile_id: String.t(),
          launch_context: map(),
          watch: map(),
          companion: map(),
          phone: map(),
          storage: map(),
          auto_tick: map(),
          disabled_subscriptions: [map()],
          events: [runtime_event()],
          debugger_timeline: [debugger_event()],
          debugger_seq: non_neg_integer(),
          seq: non_neg_integer()
        }
  @type snapshot_opt ::
          {:event_limit, pos_integer()}
          | {:types, [String.t()]}
          | {:since_seq, non_neg_integer()}

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(_opts) do
    Agent.start_link(fn -> %{} end, name: __MODULE__)
  end

  @spec start_session(String.t()) :: {:ok, runtime_state()}
  def start_session(project_slug) when is_binary(project_slug),
    do: start_session(project_slug, %{})

  @spec start_session(String.t(), map()) :: {:ok, runtime_state()}
  def start_session(project_slug, attrs) when is_binary(project_slug) and is_map(attrs) do
    requested_profile_id =
      parse_optional_watch_profile_id(
        Map.get(attrs, :watch_profile_id) || Map.get(attrs, "watch_profile_id")
      )

    launch_reason =
      parse_launch_reason(Map.get(attrs, :launch_reason) || Map.get(attrs, "launch_reason"))

    update(project_slug, fn state ->
      state = state |> ensure_phone_state() |> stop_auto_tick_worker()

      watch_profile_id =
        requested_profile_id || parse_watch_profile_id(Map.get(state, :watch_profile_id))

      launch_context = launch_context_for(watch_profile_id, launch_reason)

      %{
        state
        | running: true,
          revision: nil,
          watch_profile_id: watch_profile_id,
          launch_context: launch_context,
          storage: Map.get(state, :storage, %{}),
          watch: default_watch_runtime(launch_context),
          companion: default_companion_runtime(),
          phone: default_phone_runtime(),
          auto_tick: default_auto_tick(),
          disabled_subscriptions: [],
          events: [],
          debugger_timeline: [],
          debugger_seq: 0,
          seq: 0
      }
      |> attach_companion_configuration(project_slug)
      |> apply_launch_context_to_surfaces(launch_reason)
      |> append_event("debugger.start", %{
        launch_reason: launch_reason,
        watch_profile_id: watch_profile_id
      })
    end)
  end

  @spec reset(String.t()) :: {:ok, runtime_state()}
  def reset(project_slug) when is_binary(project_slug) do
    update(project_slug, fn state ->
      watch_profile_id = parse_watch_profile_id(Map.get(state, :watch_profile_id))

      launch_reason =
        state
        |> Map.get(:launch_context, %{})
        |> Map.get("launch_reason")
        |> parse_launch_reason()

      launch_context = launch_context_for(watch_profile_id, launch_reason)

      base =
        %{
          state
          | revision: nil,
            watch_profile_id: watch_profile_id,
            launch_context: launch_context,
            watch: default_watch_runtime(launch_context),
            companion: default_companion_runtime(),
            phone: default_phone_runtime(),
            debugger_timeline: [],
            debugger_seq: 0
        }
        |> attach_companion_configuration(project_slug)

      append_event(base, "debugger.reset", %{})
    end)
  end

  @doc """
  Removes all debugger state for a project slug.

  Project deletion can be followed by recreating a project with the same slug, so
  debugger state must not outlive the project workspace it was derived from.
  """
  @spec forget_project(String.t()) :: :ok
  def forget_project(project_slug) when is_binary(project_slug) do
    :ok = ensure_started()

    Agent.update(__MODULE__, fn store ->
      case Map.pop(store, project_slug) do
        {state, next_store} when is_map(state) ->
          _ = stop_auto_tick_worker(state)
          next_store

        {_state, next_store} ->
          next_store
      end
    end)
  end

  @doc """
  Returns available watch profiles for debugger launch context settings.
  """
  @spec watch_profiles() :: [map()]
  def watch_profiles do
    profiles = watch_profiles_map()

    WatchModels.ordered_ids()
    |> Enum.map(fn id ->
      profile = Map.get(profiles, id, %{})

      profile
      |> Map.put("id", id)
      |> Map.put("label", watch_profile_label(profile))
    end)
  end

  @doc """
  Updates the debugger watch profile and launch context used for init/runtime.
  """
  @spec set_watch_profile(String.t(), map()) :: {:ok, runtime_state()}
  def set_watch_profile(project_slug, attrs \\ %{})
      when is_binary(project_slug) and is_map(attrs) do
    profile_id =
      parse_watch_profile_id(
        Map.get(attrs, :watch_profile_id) || Map.get(attrs, "watch_profile_id")
      )

    launch_reason =
      parse_launch_reason(Map.get(attrs, :launch_reason) || Map.get(attrs, "launch_reason"))

    update(project_slug, fn state ->
      state
      |> ensure_phone_state()
      |> Map.put(:watch_profile_id, profile_id)
      |> apply_launch_context_to_surfaces(launch_reason)
      |> append_event("debugger.watch_profile_set", %{
        watch_profile_id: profile_id,
        launch_reason: launch_reason
      })
    end)
  end

  @doc """
  Merges a finished `elmc check` summary into watch/companion/phone `model` maps and appends
  `debugger.elmc_check` when the session is running. No-op if the debugger is not started.

  Pass `diagnostics: [...]` (same shape as `Ide.Compiler` diagnostics) to also merge  `elmc_diagnostic_preview` into each surface model (first 12 entries, truncated messages).
  """
  @spec ingest_elmc_check(String.t(), map()) :: {:ok, runtime_state()}
  def ingest_elmc_check(project_slug, attrs) when is_binary(project_slug) and is_map(attrs) do
    update(project_slug, fn state ->
      if Map.get(state, :running, false) do
        fields =
          attrs
          |> elmc_check_model_fields()
          |> merge_elmc_diagnostic_preview(attrs)

        state
        |> merge_runtime_model(:watch, fields)
        |> merge_runtime_model(:companion, fields)
        |> merge_runtime_model(:phone, fields)
        |> append_event("debugger.elmc_check", elmc_check_event_payload(attrs))
      else
        state
      end
    end)
  end

  @doc """
  Merges a finished `elmc compile` summary into watch/companion/phone `model` maps and appends
  `debugger.elmc_compile` when the session is running. No-op if the debugger is not started.

  Optional `diagnostics` updates `elmc_diagnostic_preview` in each surface model (see `ingest_elmc_check/2`).
  """
  @spec ingest_elmc_compile(String.t(), map()) :: {:ok, runtime_state()}
  def ingest_elmc_compile(project_slug, attrs) when is_binary(project_slug) and is_map(attrs) do
    update(project_slug, fn state ->
      if Map.get(state, :running, false) do
        artifact_fields = optional_runtime_artifacts_from_attrs(attrs)

        fields =
          attrs
          |> elmc_compile_model_fields()
          |> merge_elmc_diagnostic_preview(attrs)
          |> Map.drop(["elm_executor_metadata", "elm_executor_core_ir_b64"])

        artifact_target =
          attrs
          |> compile_artifact_target()

        state
        |> merge_runtime_model(:watch, fields)
        |> merge_runtime_model(:companion, fields)
        |> merge_runtime_model(:phone, fields)
        |> maybe_merge_runtime_artifacts(artifact_target, artifact_fields)
        |> refresh_runtime_previews_from_artifacts()
        |> append_event("debugger.elmc_compile", elmc_compile_event_payload(attrs))
      else
        state
      end
    end)
  end

  @doc """
  Merges a finished `elmc manifest` summary into watch/companion/phone `model` maps and appends
  `debugger.elmc_manifest` when the session is running. No-op if the debugger is not started.

  Optional `diagnostics` updates `elmc_diagnostic_preview` in each surface model (see `ingest_elmc_check/2`).
  """
  @spec ingest_elmc_manifest(String.t(), map()) :: {:ok, runtime_state()}
  def ingest_elmc_manifest(project_slug, attrs) when is_binary(project_slug) and is_map(attrs) do
    update(project_slug, fn state ->
      if Map.get(state, :running, false) do
        fields =
          attrs
          |> elmc_manifest_model_fields()
          |> merge_elmc_diagnostic_preview(attrs)

        state
        |> merge_runtime_model(:watch, fields)
        |> merge_runtime_model(:companion, fields)
        |> merge_runtime_model(:phone, fields)
        |> append_event("debugger.elmc_manifest", elmc_manifest_event_payload(attrs))
      else
        state
      end
    end)
  end

  @doc """
  Re-renders a stored runtime snapshot with the latest available runtime artifacts.

  The selected snapshot's model remains authoritative; only compiler/runtime artifacts
  from the latest surface snapshot are borrowed so debugger time-travel can render
  `view selectedModel` without depending on later event snapshots.
  """
  @spec render_runtime_preview_for_debugger(
          map() | nil,
          map() | nil,
          :watch | :companion | :phone
        ) ::
          map() | nil
  def render_runtime_preview_for_debugger(nil, _latest_runtime, _target), do: nil

  def render_runtime_preview_for_debugger(snapshot_runtime, latest_runtime, target)
      when is_map(snapshot_runtime) and is_map(latest_runtime) and
             target in [:watch, :companion, :phone] do
    snapshot_model =
      Map.get(snapshot_runtime, :model) || Map.get(snapshot_runtime, "model") || %{}

    latest_model = Map.get(latest_runtime, :model) || Map.get(latest_runtime, "model") || %{}

    model = merge_latest_runtime_render_inputs(snapshot_model, latest_model)
    introspect = Map.get(model, "elm_introspect")
    artifacts = runtime_execution_artifacts(model)

    view_tree =
      Map.get(snapshot_runtime, :view_tree) || Map.get(snapshot_runtime, "view_tree") || %{}

    latest_view_tree =
      Map.get(latest_runtime, :view_tree) || Map.get(latest_runtime, "view_tree") || %{}

    if is_map(introspect) and artifacts != %{} do
      request =
        %{
          source_root: source_root_for_target(target),
          rel_path: Map.get(model, "last_path"),
          source: "",
          introspect: introspect,
          current_model: model,
          current_view_tree: view_tree
        }
        |> Map.merge(artifacts)

      case runtime_executor_module().execute(request) do
        {:ok, payload} when is_map(payload) ->
          model_patch =
            payload
            |> Map.get(:model_patch, %{})
            |> then(fn patch -> if is_map(patch), do: patch, else: %{} end)

          runtime_view_output =
            preferred_runtime_view_output(
              Map.get(payload, :view_output),
              Map.get(model, "runtime_view_output") || Map.get(model, :runtime_view_output)
            )

          next_model =
            model
            |> Map.put("elm_executor_mode", "runtime_executed")
            |> Map.merge(model_patch)
            |> put_runtime_view_output(runtime_view_output)

          runtime_view_tree =
            choose_runtime_preview_view_tree(
              Map.get(payload, :view_tree),
              latest_view_tree,
              view_tree,
              runtime_view_output
            )

          snapshot_runtime
          |> Map.put(:model, next_model)
          |> maybe_put_debugger_view_tree(runtime_view_tree)

        _ ->
          snapshot_runtime
      end
    else
      snapshot_runtime
    end
  end

  def render_runtime_preview_for_debugger(snapshot_runtime, _latest_runtime, _target),
    do: snapshot_runtime

  @spec reload(String.t(), map()) :: {:ok, runtime_state()}
  def reload(project_slug, attrs \\ %{}) when is_binary(project_slug) and is_map(attrs) do
    rel_path = Map.get(attrs, :rel_path) || Map.get(attrs, "rel_path")
    reason = Map.get(attrs, :reason) || Map.get(attrs, "reason") || "manual"
    source = Map.get(attrs, :source) || Map.get(attrs, "source") || ""
    source_root = normalize_source_root(attrs)

    update(project_slug, fn state ->
      state
      |> ensure_phone_state()
      |> apply_hot_reload(rel_path, source, reason, source_root)
      |> attach_companion_configuration(project_slug)
    end)
  end

  @doc """
  Applies deterministic debugger step events for a target runtime.
  """
  @spec step(String.t(), map()) :: {:ok, runtime_state()}
  def step(project_slug, attrs \\ %{}) when is_binary(project_slug) and is_map(attrs) do
    target = normalize_step_target(Map.get(attrs, :target) || Map.get(attrs, "target"))
    message = Map.get(attrs, :message) || Map.get(attrs, "message")
    count = parse_step_count(Map.get(attrs, :count) || Map.get(attrs, "count"))

    update(project_slug, fn state ->
      if Map.get(state, :running, false) do
        Enum.reduce(1..count, state, fn _, acc ->
          apply_step_once(acc, target, message, nil, "step")
        end)
      else
        state
      end
    end)
  end

  @doc """
  Simulates saving the companion configuration webview in the debugger.
  """
  @spec save_configuration(String.t(), map()) :: {:ok, runtime_state()}
  def save_configuration(project_slug, values) when is_binary(project_slug) and is_map(values) do
    update(project_slug, fn state ->
      state = attach_companion_configuration(ensure_phone_state(state), project_slug)

      configuration =
        get_in(state, [:companion, :model, "configuration"]) ||
          get_in(state, [:companion, :model, "runtime_model", "configuration"]) ||
          %{}

      encoded_values = encode_configuration_values(configuration, values)

      bridge_event = %{
        "event" => "configuration.closed",
        "payload" => %{
          "response" => Jason.encode!(encoded_values)
        }
      }

      state
      |> apply_step_once(
        :companion,
        "FromBridge",
        %{"ctor" => "FromBridge", "args" => [bridge_event]},
        "configuration",
        "configuration"
      )
      |> apply_configuration_protocol_messages(configuration, encoded_values)
      |> attach_companion_configuration(project_slug)
      |> put_companion_configuration_values(encoded_values)
      |> refresh_runtime_preview_for_target(:watch)
    end)
  end

  @doc """
  Reloads persisted companion configuration values without sending them to the app.
  """
  @spec reload_configuration(String.t()) :: {:ok, runtime_state()}
  def reload_configuration(project_slug) when is_binary(project_slug) do
    update(project_slug, fn state ->
      state
      |> ensure_phone_state()
      |> update_in([:companion, :model], &drop_companion_configuration/1)
      |> attach_companion_configuration(project_slug)
    end)
  end

  @doc """
  Replays recent `debugger.update_in` messages back into runtime state.
  """
  @spec replay_recent(String.t(), map()) :: {:ok, runtime_state()}
  def replay_recent(project_slug, attrs \\ %{}) when is_binary(project_slug) and is_map(attrs) do
    count = parse_step_count(Map.get(attrs, :count) || Map.get(attrs, "count"))
    target = normalize_optional_step_target(Map.get(attrs, :target) || Map.get(attrs, "target"))

    cursor_seq =
      parse_optional_step_cursor_seq(Map.get(attrs, :cursor_seq) || Map.get(attrs, "cursor_seq"))

    replay_mode = parse_replay_mode(Map.get(attrs, :replay_mode) || Map.get(attrs, "replay_mode"))

    replay_drift_seq =
      parse_optional_step_cursor_seq(
        Map.get(attrs, :replay_drift_seq) || Map.get(attrs, "replay_drift_seq")
      )

    replay_rows? = Map.has_key?(attrs, :replay_rows) or Map.has_key?(attrs, "replay_rows")

    replay_rows =
      normalize_replay_rows_input(Map.get(attrs, :replay_rows) || Map.get(attrs, "replay_rows"))

    update(project_slug, fn state ->
      if Map.get(state, :running, false) do
        {replay_messages, replay_source} =
          if replay_rows? do
            {replay_rows, "frozen_preview"}
          else
            {recent_replay_messages(state, target, count, cursor_seq), "recent_query"}
          end

        replayed =
          Enum.reduce(replay_messages, state, fn %{target: replay_target, message: message},
                                                 acc ->
            apply_step_once(acc, replay_target, message, nil, "replay")
          end)

        requested_count = if replay_rows?, do: length(replay_rows), else: count

        %{
          target: replay_target_label(target),
          requested_count: requested_count,
          replayed_count: length(replay_messages)
        }
        |> maybe_put_replay_cursor_seq(cursor_seq)
        |> Map.put(:replay_source, replay_source)
        |> Map.put(
          :replay_telemetry,
          replay_telemetry_payload(
            replay_mode,
            replay_source,
            replay_drift_seq,
            target,
            requested_count,
            length(replay_messages)
          )
        )
        |> Map.merge(replay_summary_payload(replay_messages))
        |> then(&append_event(replayed, "debugger.replay", &1))
      else
        state
      end
    end)
  end

  @doc """
  Materializes a historical event snapshot into the live tip state, so subsequent
  step/tick operations continue from that selected debugger snapshot.
  """
  @spec continue_from_snapshot(String.t(), map()) :: {:ok, runtime_state()}
  def continue_from_snapshot(project_slug, attrs \\ %{})
      when is_binary(project_slug) and is_map(attrs) do
    cursor_seq =
      parse_optional_step_cursor_seq(Map.get(attrs, :cursor_seq) || Map.get(attrs, "cursor_seq"))

    update(project_slug, fn state ->
      events = Map.get(state, :events, [])
      resolved_seq = CursorSeq.resolve_at_or_before(events, cursor_seq)
      selected_event = event_at_seq(events, resolved_seq)

      if is_map(selected_event) do
        state
        |> Map.put(:running, true)
        |> Map.put(
          :watch,
          snapshot_surface(Map.get(selected_event, :watch), default_watch_runtime())
        )
        |> Map.put(
          :companion,
          snapshot_surface(Map.get(selected_event, :companion), default_companion_runtime())
        )
        |> Map.put(
          :phone,
          snapshot_surface(Map.get(selected_event, :phone), default_phone_runtime())
        )
        |> append_event("debugger.snapshot_continue", %{
          cursor_seq: resolved_seq,
          source: "cursor_snapshot"
        })
      else
        state
      end
    end)
  end

  @doc """
  Returns lightweight per-event surface snapshot reference metadata for clients
  that want snapshot-first rendering without deep diffs.
  """
  @spec snapshot_reference_rows([runtime_event()]) :: [map()]
  def snapshot_reference_rows(events) when is_list(events) do
    events
    |> Enum.sort_by(& &1.seq)
    |> normalize_events_with_snapshot_refs()
    |> Enum.map(fn row ->
      %{
        "seq" => Map.get(row, "seq"),
        "snapshot_refs" => Map.get(row, "snapshot_refs", %{}),
        "snapshot_changed_surfaces" =>
          Map.get(row, "snapshot_changed_surfaces", ["watch", "companion", "phone"])
      }
    end)
  end

  def snapshot_reference_rows(_events), do: []

  @doc """
  Returns normalized trigger candidates for a debugger state map. This is used
  by the simple debugger UI to expose subscription/button-like trigger controls.
  """
  @spec trigger_candidates(runtime_state() | map(), :watch | :companion | :phone | nil) :: [map()]
  def trigger_candidates(state, target \\ :watch)

  def trigger_candidates(state, target) when is_map(state) do
    targets = if target in [:watch, :companion, :phone], do: [target], else: [:watch]

    targets
    |> Enum.flat_map(&trigger_candidates_for_surface(state, &1))
    |> Enum.uniq_by(fn row ->
      {Map.get(row, :target), Map.get(row, :trigger), Map.get(row, :message)}
    end)
  end

  def trigger_candidates(_state, _target), do: []

  @doc """
  Resolves trigger candidates from the current project snapshot.
  """
  @spec available_triggers(String.t(), map()) :: {:ok, [map()]}
  def available_triggers(project_slug, attrs \\ %{})
      when is_binary(project_slug) and is_map(attrs) do
    target = normalize_optional_step_target(Map.get(attrs, :target) || Map.get(attrs, "target"))

    case snapshot(project_slug, event_limit: 1) do
      {:ok, state} -> {:ok, trigger_candidates(state, target)}
    end
  end

  @doc """
  Injects a single custom trigger (typically a subscription/button event) into
  the selected surface runtime.
  """
  @spec inject_trigger(String.t(), map()) :: {:ok, runtime_state()}
  def inject_trigger(project_slug, attrs \\ %{}) when is_binary(project_slug) and is_map(attrs) do
    target = normalize_step_target(Map.get(attrs, :target) || Map.get(attrs, "target"))
    trigger = to_string(Map.get(attrs, :trigger) || Map.get(attrs, "trigger") || "trigger")
    requested_message = Map.get(attrs, :message) || Map.get(attrs, "message")
    requested_message_value = Map.get(attrs, :message_value) || Map.get(attrs, "message_value")

    update(project_slug, fn state ->
      if Map.get(state, :running, false) do
        if subscription_trigger_disabled?(state, target, trigger) do
          append_event(state, "debugger.subscription_toggle", %{
            action: "blocked",
            target: source_root_for_target(target),
            trigger: trigger
          })
        else
          resolved_message =
            trigger_message_for_surface(state, target, trigger, requested_message)

          resolved_message_value =
            subscription_trigger_message_value(resolved_message, requested_message_value)

          apply_step_once(
            state,
            target,
            resolved_message,
            resolved_message_value,
            "subscription_trigger",
            "subscription_trigger"
          )
        end
      else
        state
      end
    end)
  end

  @spec subscription_trigger_message_value(term(), term()) :: term()
  defp subscription_trigger_message_value(message, %{} = value) when is_binary(message) do
    cond do
      Map.has_key?(value, "ctor") or Map.has_key?(value, :ctor) ->
        value

      true ->
        constructor =
          message
          |> String.trim()
          |> String.split(~r/\s+/, parts: 2)
          |> List.first()
          |> to_string()

        if constructor == "" do
          value
        else
          %{"ctor" => constructor, "args" => [value]}
        end
    end
  end

  defp subscription_trigger_message_value(_message, _value), do: nil

  @doc """
  Enables or disables a single parsed subscription trigger.
  """
  @spec set_subscription_enabled(String.t(), map()) :: {:ok, runtime_state()}
  def set_subscription_enabled(project_slug, attrs \\ %{})
      when is_binary(project_slug) and is_map(attrs) do
    target = normalize_step_target(Map.get(attrs, :target) || Map.get(attrs, "target"))
    trigger = to_string(Map.get(attrs, :trigger) || Map.get(attrs, "trigger") || "")
    enabled? = parse_checkbox_bool(Map.get(attrs, :enabled) || Map.get(attrs, "enabled"))

    update(project_slug, fn state ->
      if Map.get(state, :running, false) and String.trim(trigger) != "" do
        disabled_subscriptions =
          state
          |> disabled_subscriptions()
          |> update_disabled_subscription(target, trigger, enabled?)

        state
        |> Map.put(:disabled_subscriptions, disabled_subscriptions)
        |> append_event("debugger.subscription_toggle", %{
          action: "set_subscription_enabled",
          target: source_root_for_target(target),
          trigger: trigger,
          enabled: enabled?,
          disabled_subscriptions: disabled_subscriptions
        })
      else
        state
      end
    end)
  end

  @doc """
  Injects deterministic subscription-style tick messages into one or more runtimes.
  """
  @spec tick(String.t(), map()) :: {:ok, runtime_state()}
  def tick(project_slug, attrs \\ %{}) when is_binary(project_slug) and is_map(attrs) do
    count = parse_step_count(Map.get(attrs, :count) || Map.get(attrs, "count"))
    target = normalize_optional_step_target(Map.get(attrs, :target) || Map.get(attrs, "target"))
    targets = tick_targets(target)

    update(project_slug, fn state ->
      if Map.get(state, :running, false) do
        ticked =
          Enum.reduce(1..count, state, fn _, acc ->
            Enum.reduce(targets, acc, fn surface_target, next_state ->
              message = tick_message_for_surface(next_state, surface_target)
              apply_step_once(next_state, surface_target, message, "subscription_tick", "tick")
            end)
          end)

        append_event(ticked, "debugger.tick", %{
          target: replay_target_label(target),
          count: count,
          targets: Enum.map(targets, &source_root_for_target/1)
        })
      else
        state
      end
    end)
  end

  @doc """
  Starts automatic deterministic tick ingress at a fixed interval.
  """
  @spec start_auto_tick(String.t(), map()) :: {:ok, runtime_state()}
  def start_auto_tick(project_slug, attrs \\ %{})
      when is_binary(project_slug) and is_map(attrs) do
    interval_ms =
      parse_tick_interval_ms(Map.get(attrs, :interval_ms) || Map.get(attrs, "interval_ms"))

    count = parse_step_count(Map.get(attrs, :count) || Map.get(attrs, "count"))
    target = normalize_optional_step_target(Map.get(attrs, :target) || Map.get(attrs, "target"))
    targets = tick_targets(target)

    update(project_slug, fn state ->
      if Map.get(state, :running, false) do
        state = stop_auto_tick_worker(state)
        worker = spawn(fn -> auto_tick_loop(project_slug, interval_ms, targets, count) end)

        state
        |> Map.put(:auto_tick, %{
          enabled: true,
          interval_ms: interval_ms,
          target: replay_target_label(target),
          targets: Enum.map(targets, &source_root_for_target/1),
          count: count,
          worker_pid: worker
        })
        |> append_event("debugger.tick_auto", %{
          action: "start",
          interval_ms: interval_ms,
          target: replay_target_label(target),
          targets: Enum.map(targets, &source_root_for_target/1),
          count: count
        })
      else
        state
      end
    end)
  end

  @doc """
  Stops automatic deterministic tick ingress if enabled.
  """
  @spec stop_auto_tick(String.t()) :: {:ok, runtime_state()}
  def stop_auto_tick(project_slug) when is_binary(project_slug) do
    update(project_slug, fn state ->
      state
      |> stop_auto_tick_worker()
      |> append_event("debugger.tick_auto", %{action: "stop"})
    end)
  end

  @doc """
  Enables or disables natural subscription event ingress for a single surface.
  """
  @spec set_auto_fire(String.t(), map()) :: {:ok, runtime_state()}
  def set_auto_fire(project_slug, attrs \\ %{}) when is_binary(project_slug) and is_map(attrs) do
    target = normalize_step_target(Map.get(attrs, :target) || Map.get(attrs, "target"))
    enabled? = parse_checkbox_bool(Map.get(attrs, :enabled) || Map.get(attrs, "enabled"))
    trigger = Map.get(attrs, :trigger) || Map.get(attrs, "trigger")

    update(project_slug, fn state ->
      if Map.get(state, :running, false) do
        subscriptions =
          if is_binary(trigger) and String.trim(trigger) != "" do
            state
            |> auto_tick_subscriptions()
            |> update_auto_fire_subscriptions(target, trigger, enabled?)
          else
            state
            |> auto_tick_targets()
            |> update_auto_fire_targets(target, enabled?)
            |> Enum.map(&%{"target" => source_root_for_target(&1), "trigger" => "*"})
          end

        targets = auto_fire_targets_from_subscriptions(subscriptions)

        state
        |> restart_auto_fire_worker(project_slug, targets, subscriptions)
        |> append_event("debugger.tick_auto", %{
          action: "set_auto_fire",
          target: source_root_for_target(target),
          trigger: trigger,
          enabled: enabled?,
          targets: Enum.map(targets, &source_root_for_target/1),
          subscriptions: subscriptions
        })
      else
        state
      end
    end)
  end

  @spec export_trace(String.t(), keyword()) ::
          {:ok, %{json: String.t(), sha256: String.t(), byte_size: non_neg_integer()}}
  def export_trace(project_slug, opts \\ []) when is_binary(project_slug) do
    limit = Keyword.get(opts, :event_limit, @history_limit)
    compare_cursor_seq = Keyword.get(opts, :compare_cursor_seq)
    baseline_cursor_seq = Keyword.get(opts, :baseline_cursor_seq)

    limit =
      if is_integer(limit) and limit > 0, do: min(limit, @history_limit), else: @history_limit

    with {:ok, state} <- snapshot(project_slug, event_limit: limit) do
      body =
        export_payload(project_slug, state,
          compare_cursor_seq: compare_cursor_seq,
          baseline_cursor_seq: baseline_cursor_seq
        )

      json = Jason.encode!(body)
      sha = :crypto.hash(:sha256, json) |> Base.encode16(case: :lower)
      {:ok, %{json: json, sha256: sha, byte_size: byte_size(json)}}
    end
  end

  @spec import_trace(String.t(), String.t() | map(), keyword()) ::
          {:ok, runtime_state()} | {:error, term()}
  def import_trace(project_slug, input, opts \\ []) when is_binary(project_slug) do
    with {:ok, body} <- decode_import_body(input),
         :ok <- validate_import_body(body),
         :ok <- maybe_match_import_slug(body, project_slug, opts) do
      state = state_from_import_body(body)
      :ok = ensure_started()

      Agent.get_and_update(__MODULE__, fn store ->
        previous = Map.get(store, project_slug)

        if is_map(previous) do
          _ = stop_auto_tick_worker(previous)
        end

        {state, Map.put(store, project_slug, ensure_phone_state(state))}
      end)

      {:ok, state}
    end
  end

  @spec snapshot(String.t(), [snapshot_opt()]) :: {:ok, runtime_state()}
  def snapshot(project_slug, opts \\ []) when is_binary(project_slug) do
    limit = Keyword.get(opts, :event_limit, 50)
    types = Keyword.get(opts, :types)
    since_seq = Keyword.get(opts, :since_seq)
    :ok = ensure_started()

    state =
      Agent.get(__MODULE__, fn store ->
        store
        |> Map.get(project_slug, default_state(project_slug))
        |> ensure_phone_state()
        |> filter_events_by_types(types)
        |> filter_events_since_seq(since_seq)
        |> maybe_trim_events(limit)
      end)

    {:ok, state}
  end

  @spec update(String.t(), (runtime_state() -> runtime_state())) :: {:ok, runtime_state()}
  defp update(project_slug, updater) do
    :ok = ensure_started()

    updated =
      Agent.get_and_update(__MODULE__, fn store ->
        current =
          Map.get(store, project_slug, default_state(project_slug)) |> ensure_phone_state()

        next = updater.(current)
        {next, Map.put(store, project_slug, next)}
      end)

    {:ok, updated}
  end

  @spec ensure_started() :: :ok
  defp ensure_started do
    case Process.whereis(__MODULE__) do
      pid when is_pid(pid) ->
        :ok

      nil ->
        case start_link([]) do
          {:ok, _pid} -> :ok
          {:error, {:already_started, _pid}} -> :ok
          {:error, reason} -> raise "failed to start debugger agent: #{inspect(reason)}"
        end
    end
  end

  @spec append_event(runtime_state(), String.t(), map()) :: runtime_state()
  defp append_event(state, type, payload) do
    seq = state.seq + 1

    event = %{
      seq: seq,
      type: type,
      payload: payload,
      watch: Map.get(state, :watch, %{}),
      companion: Map.get(state, :companion, %{}),
      phone: Map.get(state, :phone, %{})
    }

    %{
      state
      | seq: seq,
        events: [event | state.events] |> Enum.take(@history_limit)
    }
  end

  @spec append_debugger_event(
          runtime_state(),
          String.t(),
          :watch | :companion | :phone,
          term(),
          term()
        ) ::
          runtime_state()
  defp append_debugger_event(state, type, target, message, message_source)
       when is_map(state) and is_binary(type) and target in [:watch, :companion, :phone] do
    debugger_seq = Map.get(state, :debugger_seq, 0) + 1

    row = %{
      seq: debugger_seq,
      raw_seq: Map.get(state, :seq, 0),
      type: type,
      target: source_root_for_target(target),
      message: if(is_binary(message), do: message, else: to_string(message || "")),
      message_source: if(is_binary(message_source), do: message_source, else: nil),
      watch: Map.get(state, :watch, %{}),
      companion: Map.get(state, :companion, %{}),
      phone: Map.get(state, :phone, %{})
    }

    state
    |> Map.put(:debugger_seq, debugger_seq)
    |> Map.put(
      :debugger_timeline,
      [row | Map.get(state, :debugger_timeline, [])] |> Enum.take(@history_limit)
    )
  end

  @spec maybe_trim_events(runtime_state(), term()) :: runtime_state()
  defp maybe_trim_events(state, limit) when is_integer(limit) and limit > 0 do
    %{state | events: Enum.take(state.events, limit)}
  end

  defp maybe_trim_events(state, _limit), do: state

  @spec apply_step_once(term(), term(), term(), term(), term()) :: term()
  defp apply_step_once(state, target, requested_message, source_override, trigger)
       when target in [:watch, :companion, :phone] do
    apply_step_once(state, target, requested_message, nil, source_override, trigger)
  end

  @spec apply_step_once(term(), term(), term(), term(), term(), term()) :: term()
  defp apply_step_once(state, target, requested_message, message_value, source_override, trigger)
       when target in [:watch, :companion, :phone] do
    surface = Map.get(state, target) || %{}

    model =
      surface
      |> Map.get(:model)
      |> hydrate_runtime_model_for_message(nil)

    view_tree = Map.get(surface, :view_tree) || %{}

    {message, msg_source, known_messages, update_branches, next_cursor} =
      resolve_step_message(model, requested_message)

    runtime_result =
      step_runtime_result(model, view_tree, target, message, message_value, update_branches)

    runtime_patch = Map.get(runtime_result, :model_patch, %{})
    runtime_patch = normalize_runtime_patch_values(model, runtime_patch)
    runtime_view_tree = Map.get(runtime_result, :view_tree)
    runtime_view_tree = if is_map(runtime_view_tree), do: runtime_view_tree, else: view_tree
    runtime_view_output = Map.get(runtime_result, :view_output)
    runtime_view_output = if is_list(runtime_view_output), do: runtime_view_output, else: []
    runtime_protocol_events = Map.get(runtime_result, :protocol_events, [])

    command_protocol_events =
      if runtime_protocol_events == [] do
        protocol_events_for_model_commands(model, target, message)
      else
        []
      end

    runtime_followups = Map.get(runtime_result, :followup_messages, [])

    message_source = source_override || msg_source

    protocol_events =
      if message_source == "configuration" do
        []
      else
        runtime_protocol_events ++ command_protocol_events
      end
      |> enrich_protocol_events(trigger, message_source)

    updated_model =
      model
      |> Map.merge(runtime_patch)
      |> hydrate_runtime_model_for_message(message)
      |> preserve_protocol_runtime_metadata(model)
      |> Map.put("runtime_last_message", message)
      |> Map.put("runtime_message_source", message_source)
      |> Map.put("runtime_message_cursor", next_cursor)
      |> Map.put("runtime_known_messages", known_messages)
      |> Map.put("runtime_update_branches", update_branches)
      |> Map.put("runtime_view_output", runtime_view_output)
      |> Map.update("_debugger_steps", 1, &(&1 + 1))

    rendered_view_tree =
      render_view_after_update(
        runtime_view_tree,
        view_tree,
        target,
        message,
        trigger,
        updated_model
      )

    updated_state =
      state
      |> put_in([target, :model], updated_model)
      |> put_in([target, :view_tree], rendered_view_tree)
      |> put_in([target, :last_message], message)

    root =
      updated_state
      |> get_in([target, :view_tree, "type"])
      |> case do
        value when is_binary(value) and value != "" -> value
        _ -> "simulated-root"
      end

    target_name = source_root_for_target(target)

    updated_state =
      updated_state
      |> append_runtime_exec_event_for_target(target, %{
        trigger: trigger,
        message: message,
        message_source: message_source
      })
      |> append_event("debugger.update_in", %{
        target: target_name,
        message: message,
        message_source: message_source
      })
      |> append_debugger_event("update", target, message, message_source)
      |> maybe_append_runtime_status_debugger_event(target)
      |> append_protocol_events(protocol_events)
      |> apply_protocol_state_effects(protocol_events)
      |> append_event("debugger.view_render", %{target: target_name, root: root})

    updated_state =
      maybe_apply_device_data_responses(
        updated_state,
        target,
        message,
        updated_model,
        message_source
      )

    maybe_apply_runtime_followups(
      updated_state,
      target,
      message,
      message_source,
      runtime_followups
    )
  end

  @spec maybe_apply_device_data_responses(term(), term(), term(), term(), term()) :: term()
  defp maybe_apply_device_data_responses(state, _target, _message, _model, "device_data"),
    do: state

  defp maybe_apply_device_data_responses(state, _target, _message, _model, "init_device_data"),
    do: state

  defp maybe_apply_device_data_responses(state, _target, _message, _model, "configuration"),
    do: state

  defp maybe_apply_device_data_responses(state, target, message, model, _message_source)
       when target in [:watch, :companion, :phone] and is_binary(message) and is_map(model) do
    device_requests_for_model(model, message)
    |> Enum.reduce(state, fn req, acc ->
      target_name = source_root_for_target(target)

      acc
      |> apply_device_data_hint(target, req)
      |> append_event("debugger.device_data", %{
        target: target_name,
        request: req.kind,
        response_message: device_response_message(req),
        response_value: req.preview
      })
      |> apply_step_once(target, device_response_message(req), "device_data", "device_data")
      |> apply_device_data_hint(target, req)
    end)
  end

  defp maybe_apply_device_data_responses(state, _target, _message, _model, _message_source),
    do: state

  @spec maybe_apply_init_device_data_responses(term(), term()) :: term()
  defp maybe_apply_init_device_data_responses(state, target)
       when target in [:watch, :companion, :phone] do
    model = get_in(state, [target, :model]) || %{}
    ei = Map.get(model, "elm_introspect")

    if is_map(ei) do
      ei
      |> introspect_cmd_calls("init_cmd_calls")
      |> Enum.flat_map(&device_request_from_cmd_call/1)
      |> Enum.uniq_by(fn req -> {req.kind, req.response_message} end)
      |> Enum.map(&finalize_device_request(&1, model))
      |> Enum.reduce(state, fn req, acc ->
        target_name = source_root_for_target(target)

        acc
        |> apply_device_data_hint(target, req)
        |> append_event("debugger.device_data", %{
          target: target_name,
          request: req.kind,
          response_message: device_response_message(req),
          response_value: req.preview
        })
        |> apply_step_once(
          target,
          device_response_message(req),
          "init_device_data",
          "device_data"
        )
        |> apply_device_data_hint(target, req)
      end)
    else
      state
    end
  end

  defp maybe_apply_init_device_data_responses(state, _target), do: state

  defp maybe_apply_init_protocol_events(state, target)
       when target in [:watch, :companion, :phone] do
    model = get_in(state, [target, :model]) || %{}
    ei = Map.get(model, "elm_introspect")

    if is_map(ei) do
      ei
      |> introspect_cmd_calls("init_cmd_calls")
      |> Enum.flat_map(&protocol_events_from_cmd_call(target, &1, model))
      |> Enum.reduce(state, fn event, acc ->
        acc
        |> append_event(event.type, event.payload)
        |> then(fn next ->
          if event.type == "debugger.protocol_rx" do
            apply_protocol_state_effects(next, [event])
          else
            next
          end
        end)
      end)
    else
      state
    end
  end

  defp maybe_apply_init_protocol_events(state, _target), do: state

  defp protocol_events_from_cmd_call(:watch, cmd_call, model) when is_map(cmd_call) do
    name = (Map.get(cmd_call, "name") || Map.get(cmd_call, :name) || "") |> to_string()
    target = (Map.get(cmd_call, "target") || Map.get(cmd_call, :target) || "") |> to_string()

    {message, message_value} =
      protocol_message_payload_for_cmd_call(cmd_call, model, :watch_to_phone)

    if name == "sendWatchToPhone" or String.ends_with?(target, ".sendWatchToPhone") do
      protocol_tx_rx_events("watch", "companion", message, "init_cmd", message_value)
    else
      []
    end
  end

  defp protocol_events_from_cmd_call(target_surface, cmd_call, model)
       when target_surface in [:companion, :phone] and is_map(cmd_call) do
    name = (Map.get(cmd_call, "name") || Map.get(cmd_call, :name) || "") |> to_string()
    target = (Map.get(cmd_call, "target") || Map.get(cmd_call, :target) || "") |> to_string()

    {message, message_value} =
      protocol_message_payload_for_cmd_call(cmd_call, model, :phone_to_watch)

    if name == "sendPhoneToWatch" or String.ends_with?(target, ".sendPhoneToWatch") do
      protocol_tx_rx_events("companion", "watch", message, "protocol_cmd", message_value)
    else
      []
    end
  end

  defp protocol_events_from_cmd_call(_surface, _cmd_call, _model), do: []

  @spec protocol_events_for_model_commands(term(), term(), term()) :: [map()]
  defp protocol_events_for_model_commands(model, target, message)
       when is_map(model) and target in [:watch, :companion, :phone] and is_binary(message) do
    current_ctor = message_constructor(message)

    model
    |> Map.get("elm_introspect")
    |> introspect_cmd_calls("update_cmd_calls")
    |> update_cmd_calls_for_message(current_ctor)
    |> Enum.flat_map(&protocol_events_from_cmd_call(target, &1, model))
  end

  defp protocol_events_for_model_commands(_model, _target, _message), do: []

  @spec protocol_message_payload_for_cmd_call(map(), term(), :watch_to_phone | :phone_to_watch) ::
          {String.t() | nil, term()}
  defp protocol_message_payload_for_cmd_call(cmd_call, model, direction)
       when is_map(cmd_call) and direction in [:watch_to_phone, :phone_to_watch] do
    callback =
      Map.get(cmd_call, "callback_constructor") || Map.get(cmd_call, :callback_constructor)

    case protocol_schema_from_model(model) do
      {:ok, schema} ->
        {
          protocol_message_from_schema(schema, direction, callback),
          protocol_message_value_from_schema(schema, direction, callback)
        }

      {:error, _} ->
        {if(is_binary(callback) and callback != "", do: callback, else: nil), nil}
    end
  end

  defp protocol_message_payload_for_cmd_call(_cmd_call, _model, _direction), do: {nil, nil}

  @spec protocol_schema_from_model(term()) :: {:ok, map()} | {:error, term()}
  defp protocol_schema_from_model(_model) do
    path =
      Path.expand(
        "../../priv/internal_packages/companion-protocol/src/Companion/Types.elm",
        __DIR__
      )

    with {:ok, source} <- File.read(path) do
      Ide.CompanionProtocolGenerator.schema_from_source(source)
    end
  end

  @spec protocol_message_from_schema(map(), :watch_to_phone | :phone_to_watch, term()) ::
          String.t() | nil
  defp protocol_message_from_schema(schema, direction, callback) when is_map(schema) do
    messages =
      case direction do
        :watch_to_phone -> Map.get(schema, :watch_to_phone, [])
        :phone_to_watch -> Map.get(schema, :phone_to_watch, [])
      end

    Enum.find_value(messages, fn
      %{name: ^callback, fields: fields} when is_binary(callback) ->
        args =
          fields
          |> List.wrap()
          |> Enum.map(&protocol_default_value(schema, Map.get(&1, :wire_type)))
          |> Enum.map(&parenthesize_elm_arg/1)

        case args do
          [] -> callback
          _ -> callback <> " " <> Enum.join(args, " ")
        end

      _ ->
        nil
    end)
  end

  defp protocol_message_from_schema(_schema, _direction, _callback), do: nil

  @spec protocol_message_value_from_schema(map(), :watch_to_phone | :phone_to_watch, term()) ::
          map() | nil
  defp protocol_message_value_from_schema(schema, direction, callback)
       when is_map(schema) and is_binary(callback) and callback != "" do
    messages =
      case direction do
        :watch_to_phone -> Map.get(schema, :watch_to_phone, [])
        :phone_to_watch -> Map.get(schema, :phone_to_watch, [])
      end

    Enum.find_value(messages, fn
      %{name: ^callback, fields: fields} ->
        args =
          fields
          |> List.wrap()
          |> Enum.map(&protocol_default_value_term(schema, Map.get(&1, :wire_type)))

        %{"ctor" => callback, "args" => args}

      _ ->
        nil
    end)
  end

  defp protocol_message_value_from_schema(_schema, _direction, _callback), do: nil

  @spec protocol_default_value(map(), term()) :: String.t()
  defp protocol_default_value(_schema, :int), do: "0"
  defp protocol_default_value(_schema, :bool), do: "True"
  defp protocol_default_value(_schema, :string), do: inspect("debugger response")

  defp protocol_default_value(schema, {:enum, type}) when is_map(schema) and is_binary(type) do
    schema
    |> Map.get(:enums, %{})
    |> Map.get(type, [])
    |> List.first()
    |> case do
      value when is_binary(value) and value != "" -> value
      _ -> "Unknown"
    end
  end

  defp protocol_default_value(schema, {:union, type}) when is_map(schema) and is_binary(type) do
    schema
    |> Map.get(:payload_unions, %{})
    |> Map.get(type, [])
    |> List.first()
    |> case do
      %{name: ctor, args: args} when is_binary(ctor) and is_list(args) ->
        rendered_args =
          args
          |> Enum.map(&protocol_default_value(schema, protocol_wire_type_for_type(schema, &1)))
          |> Enum.join(" ")

        if rendered_args == "", do: ctor, else: "#{ctor} #{rendered_args}"

      _ ->
        "Unknown"
    end
  end

  defp protocol_default_value(_schema, _wire_type), do: "0"

  @spec protocol_default_value_term(map(), term()) :: term()
  defp protocol_default_value_term(_schema, :int), do: 0
  defp protocol_default_value_term(_schema, :bool), do: true
  defp protocol_default_value_term(_schema, :string), do: "debugger response"

  defp protocol_default_value_term(schema, {:enum, type})
       when is_map(schema) and is_binary(type) do
    schema
    |> Map.get(:enums, %{})
    |> Map.get(type, [])
    |> List.first()
    |> case do
      value when is_binary(value) and value != "" -> %{"ctor" => value, "args" => []}
      _ -> %{"ctor" => "Unknown", "args" => []}
    end
  end

  defp protocol_default_value_term(schema, {:union, type})
       when is_map(schema) and is_binary(type) do
    schema
    |> Map.get(:payload_unions, %{})
    |> Map.get(type, [])
    |> List.first()
    |> case do
      %{name: ctor, args: args} when is_binary(ctor) and is_list(args) ->
        %{
          "ctor" => ctor,
          "args" =>
            Enum.map(
              args,
              &protocol_default_value_term(schema, protocol_wire_type_for_type(schema, &1))
            )
        }

      _ ->
        %{"ctor" => "Unknown", "args" => []}
    end
  end

  defp protocol_default_value_term(_schema, _wire_type), do: 0

  @spec protocol_wire_type_for_type(map(), String.t()) :: term()
  defp protocol_wire_type_for_type(_schema, "Int"), do: :int
  defp protocol_wire_type_for_type(_schema, "Bool"), do: :bool
  defp protocol_wire_type_for_type(_schema, "String"), do: :string

  defp protocol_wire_type_for_type(schema, type) when is_map(schema) and is_binary(type) do
    cond do
      Map.has_key?(Map.get(schema, :enums, %{}), type) -> {:enum, type}
      Map.has_key?(Map.get(schema, :payload_unions, %{}), type) -> {:union, type}
      true -> :int
    end
  end

  defp protocol_tx_rx_events(from, to, message, trigger, message_value)
       when is_binary(from) and is_binary(to) and is_binary(message) and message != "" do
    payload = %{
      from: from,
      to: to,
      message: message,
      message_value: message_value,
      trigger: trigger,
      message_source: trigger
    }

    [
      %{type: "debugger.protocol_tx", payload: payload},
      %{type: "debugger.protocol_rx", payload: payload}
    ]
  end

  defp protocol_tx_rx_events(_from, _to, _message, _trigger, _message_value), do: []

  @spec preserve_protocol_runtime_metadata(map(), map()) :: map()
  defp preserve_protocol_runtime_metadata(model, previous_model)
       when is_map(model) and is_map(previous_model) do
    runtime_model = Map.get(model, "runtime_model")

    protocol_metadata_keys = [
      "protocol_inbound_count",
      "protocol_message_count",
      "protocol_last_inbound_message",
      "protocol_last_inbound_from"
    ]

    model =
      Enum.reduce(protocol_metadata_keys, model, fn key, acc ->
        maybe_put_protocol_runtime_value(
          acc,
          key,
          protocol_runtime_metadata_value(previous_model, key)
        )
      end)

    if is_map(runtime_model) do
      preserved =
        Enum.reduce(protocol_metadata_keys, runtime_model, fn key, acc ->
          if Map.has_key?(runtime_model, key) or
               Map.has_key?(Map.get(previous_model, "runtime_model") || %{}, key) do
            maybe_put_protocol_runtime_value(
              acc,
              key,
              protocol_runtime_metadata_value(previous_model, key)
            )
          else
            acc
          end
        end)

      Map.put(model, "runtime_model", preserved)
    else
      model
    end
  end

  defp preserve_protocol_runtime_metadata(model, _previous_model), do: model

  defp protocol_runtime_metadata_value(previous_model, key) when is_map(previous_model) do
    Map.get(previous_model, key) ||
      get_in(previous_model, ["runtime_model", key])
  end

  @spec device_response_message(term()) :: String.t() | nil
  defp device_response_message(%{
         response_message: ctor,
         kind: "current_time_string",
         preview: preview
       })
       when is_binary(ctor) and ctor != "" and is_map(preview) do
    case Map.get(preview, "string") do
      value when is_binary(value) ->
        escaped =
          value
          |> String.replace("\\", "\\\\")
          |> String.replace("\"", "\\\"")

        "#{ctor} \"#{escaped}\""

      _ ->
        ctor
    end
  end

  defp device_response_message(%{
         response_message: ctor,
         kind: "current_date_time",
         preview: preview
       })
       when is_binary(ctor) and ctor != "" and is_map(preview) do
    "#{ctor} #{Jason.encode!(current_date_time_message_payload(preview))}"
  end

  defp device_response_message(%{
         response_message: ctor,
         kind: kind,
         preview: preview
       })
       when is_binary(ctor) and ctor != "" and kind in ["battery_level", "connection_status"] do
    value =
      case {kind, preview} do
        {"battery_level", %{"batteryLevel" => level}} -> level
        {"connection_status", %{"connected" => connected}} -> connected
        _ -> preview
      end

    "#{ctor} #{elm_literal(value)}"
  end

  defp device_response_message(%{response_message: ctor}) when is_binary(ctor), do: ctor
  defp device_response_message(_req), do: nil

  defp elm_literal(value) when is_boolean(value), do: if(value, do: "True", else: "False")
  defp elm_literal(value) when is_integer(value), do: Integer.to_string(value)
  defp elm_literal(value) when is_float(value), do: :erlang.float_to_binary(value, decimals: 2)
  defp elm_literal(value) when is_binary(value), do: inspect(value)
  defp elm_literal(value), do: inspect(value)

  @spec current_date_time_message_payload(map()) :: map()
  defp current_date_time_message_payload(preview) when is_map(preview) do
    Map.update(preview, "dayOfWeek", nil, fn
      value when is_binary(value) -> %{"ctor" => value, "args" => []}
      value -> value
    end)
  end

  @spec maybe_apply_runtime_followups(term(), term(), term(), term(), term()) :: term()
  defp maybe_apply_runtime_followups(state, _target, _message, "runtime_followup", _followups),
    do: state

  defp maybe_apply_runtime_followups(state, _target, _message, "configuration", _followups),
    do: state

  defp maybe_apply_runtime_followups(state, target, message, _message_source, followups)
       when target in [:watch, :companion, :phone] and is_binary(message) and is_list(followups) do
    current_ctor = message_constructor(message)
    target_name = source_root_for_target(target)

    followups
    |> Enum.filter(&is_map/1)
    |> Enum.filter(fn row ->
      cond do
        is_map(Map.get(row, "command") || Map.get(row, :command)) ->
          true

        true ->
          followup_message = Map.get(row, "message") || Map.get(row, :message)

          is_binary(followup_message) and followup_message != "" and
            followup_message != current_ctor
      end
    end)
    |> Enum.take(5)
    |> Enum.reduce(state, fn row, acc ->
      followup_message = Map.get(row, "message") || Map.get(row, :message)
      package = Map.get(row, "package") || Map.get(row, :package)
      command = Map.get(row, "command") || Map.get(row, :command)

      cond do
        package == "elm/http" and is_map(command) ->
          apply_runtime_http_followup(
            acc,
            target,
            target_name,
            package,
            command,
            followup_message
          )

        true ->
          apply_runtime_package_followup(acc, target, target_name, package, row)
      end
    end)
  end

  defp maybe_apply_runtime_followups(state, _target, _message, _message_source, _followups),
    do: state

  @spec apply_runtime_http_followup(term(), term(), term(), term(), term(), term()) :: term()
  defp apply_runtime_http_followup(state, target, target_name, package, command, followup_message)
       when target in [:watch, :companion, :phone] and is_map(command) do
    eval_context = http_eval_context(get_in(state, [target, :model]) || %{})

    case HttpExecutor.execute(command, eval_context) do
      {:ok, result} when is_map(result) ->
        response_message = Map.get(result, "message") || followup_message || "elm/http"
        message_value = Map.get(result, "message_value")

        state
        |> append_event("debugger.package_cmd", %{
          target: target_name,
          package: package,
          response_message: response_message,
          command: http_command_event(command),
          response: Map.get(result, "response")
        })
        |> apply_step_once(
          target,
          response_message,
          message_value,
          "runtime_followup",
          "runtime_followup"
        )

      {:error, reason} ->
        append_event(state, "debugger.package_cmd_error", %{
          target: target_name,
          package: package,
          command: http_command_event(command),
          error: inspect(reason)
        })
    end
  end

  defp apply_runtime_http_followup(state, _target, _target_name, _package, _command, _message),
    do: state

  @spec apply_runtime_package_followup(term(), term(), term(), term(), term()) :: term()
  defp apply_runtime_package_followup(state, target, target_name, package, row)
       when target in [:watch, :companion, :phone] and is_map(row) do
    case Ide.Debugger.PackageCommandHandler.handle(state, target_name, package, row) do
      {:handled, next_state, event_payload, %{message: message, message_value: message_value}} ->
        next_state
        |> append_event("debugger.package_cmd", event_payload)
        |> apply_step_once(
          target,
          message,
          message_value,
          "runtime_followup",
          "runtime_followup"
        )

      {:handled, next_state, event_payload, nil} ->
        append_event(next_state, "debugger.package_cmd", event_payload)

      :unhandled ->
        followup_message = Map.get(row, "message") || Map.get(row, :message)
        followup_message_value = Map.get(row, "message_value") || Map.get(row, :message_value)

        state
        |> append_event("debugger.package_cmd", %{
          target: target_name,
          package: package,
          response_message: followup_message
        })
        |> apply_step_once(
          target,
          followup_message,
          followup_message_value,
          "runtime_followup",
          "runtime_followup"
        )
    end
  end

  defp apply_runtime_package_followup(state, _target, _target_name, _package, _row), do: state

  @spec device_requests_for_model(term(), term()) :: term()
  defp device_requests_for_model(model, current_message)
       when is_map(model) and is_binary(current_message) do
    ei = Map.get(model, "elm_introspect")
    current_ctor = message_constructor(current_message)

    update_requests =
      ei
      |> introspect_cmd_calls("update_cmd_calls")
      |> update_cmd_calls_for_message(current_ctor)
      |> Enum.flat_map(&device_request_from_cmd_call/1)

    init_requests =
      ei
      |> introspect_cmd_calls("init_cmd_calls")
      |> Enum.flat_map(&device_request_from_cmd_call/1)
      |> Enum.reject(&init_device_request_already_satisfied?(model, &1))

    (update_requests ++ init_requests)
    |> Enum.reject(fn req ->
      not is_binary(req.response_message) or req.response_message == "" or
        req.response_message == current_ctor
    end)
    |> Enum.uniq_by(fn req -> {req.kind, req.response_message} end)
    |> Enum.map(&finalize_device_request(&1, model))
  end

  defp device_requests_for_model(_model, _current_message), do: []

  @spec update_cmd_calls_for_message([map()], String.t() | nil) :: [map()]
  defp update_cmd_calls_for_message(calls, current_ctor) when is_list(calls) do
    branch_scoped? =
      Enum.any?(calls, fn row ->
        is_binary(Map.get(row, "branch_constructor")) and Map.get(row, "branch_constructor") != ""
      end)

    if branch_scoped? and is_binary(current_ctor) and current_ctor != "" do
      Enum.filter(calls, fn row ->
        case Map.get(row, "branch_constructor") do
          nil -> true
          "" -> true
          ^current_ctor -> true
          _ -> false
        end
      end)
    else
      calls
    end
  end

  @spec init_device_request_already_satisfied?(term(), term()) :: boolean()
  defp init_device_request_already_satisfied?(model, %{kind: kind})
       when is_map(model) and is_binary(kind) do
    Map.has_key?(model, "debugger_device_#{kind}")
  end

  defp init_device_request_already_satisfied?(_model, _req), do: false

  @spec device_request_from_cmd_call(term()) :: term()
  defp device_request_from_cmd_call(cmd_call) when is_map(cmd_call) do
    name = (Map.get(cmd_call, "name") || Map.get(cmd_call, :name) || "") |> to_string()

    response_ctor =
      Map.get(cmd_call, "callback_constructor") || Map.get(cmd_call, :callback_constructor)

    cond do
      response_ctor in [nil, ""] ->
        []

      name in ["getCurrentTimeString", "currentTimeString"] ->
        [%{kind: "current_time_string", response_message: response_ctor}]

      name in ["getCurrentDateTime", "currentDateTime"] ->
        [%{kind: "current_date_time", response_message: response_ctor}]

      name in ["getBatteryLevel", "batteryLevel"] ->
        [%{kind: "battery_level", response_message: response_ctor}]

      name in ["getConnectionStatus", "connectionStatus"] ->
        [%{kind: "connection_status", response_message: response_ctor}]

      name in ["getClockStyle24h", "clockStyle24h"] ->
        [%{kind: "clock_style_24h", response_message: response_ctor}]

      name in ["getTimezoneIsSet", "timezoneIsSet"] ->
        [%{kind: "timezone_is_set", response_message: response_ctor}]

      name in ["getTimezone", "timezone"] ->
        [%{kind: "timezone", response_message: response_ctor}]

      name in ["getWatchModel", "getModel"] ->
        [%{kind: "watch_model", response_message: response_ctor}]

      name in ["getWatchColor", "getColor"] ->
        [%{kind: "watch_color", response_message: response_ctor}]

      name in ["getFirmwareVersion", "firmwareVersion"] ->
        [%{kind: "firmware_version", response_message: response_ctor}]

      true ->
        []
    end
  end

  defp device_request_from_cmd_call(_cmd_call), do: []

  @spec finalize_device_request(term(), term()) :: term()
  defp finalize_device_request(%{kind: "current_time_string"} = req, _model) do
    now = NaiveDateTime.local_now()
    hhmm_text = Calendar.strftime(now, "%H:%M")

    hhmm =
      hhmm_text
      |> String.replace(":", "")
      |> Integer.parse()
      |> case do
        {parsed, ""} -> parsed
        _ -> 0
      end

    Map.put(req, :preview, %{
      "string" => hhmm_text,
      "hhmm" => hhmm
    })
  end

  defp finalize_device_request(%{kind: "current_date_time"} = req, _model) do
    now = NaiveDateTime.local_now()

    Map.put(req, :preview, %{
      "year" => now.year,
      "month" => now.month,
      "day" => now.day,
      "dayOfWeek" => day_of_week_name(now),
      "hour" => now.hour,
      "minute" => now.minute,
      "second" => now.second,
      "utcOffsetMinutes" => utc_offset_minutes_now()
    })
  end

  defp finalize_device_request(%{kind: "battery_level"} = req, _model) do
    Map.put(req, :preview, %{"batteryLevel" => 88})
  end

  defp finalize_device_request(%{kind: "connection_status"} = req, _model) do
    Map.put(req, :preview, %{"connected" => true})
  end

  defp finalize_device_request(%{kind: "clock_style_24h"} = req, _model),
    do: Map.put(req, :preview, true)

  defp finalize_device_request(%{kind: "timezone_is_set"} = req, _model),
    do: Map.put(req, :preview, true)

  defp finalize_device_request(%{kind: "timezone"} = req, _model) do
    tz = System.get_env("TZ") || "UTC"
    Map.put(req, :preview, tz)
  end

  defp finalize_device_request(%{kind: "watch_model"} = req, model) when is_map(model) do
    launch_context = Map.get(model, "launch_context") || %{}
    watch_model = Map.get(launch_context, "watch_model") || "Pebble Time Round"
    Map.put(req, :preview, watch_model)
  end

  defp finalize_device_request(%{kind: "watch_color"} = req, model) when is_map(model) do
    launch_context = Map.get(model, "launch_context") || %{}
    is_color = get_in(launch_context, ["screen", "is_color"]) == true
    Map.put(req, :preview, if(is_color, do: "Color", else: "BlackWhite"))
  end

  defp finalize_device_request(%{kind: "firmware_version"} = req, _model),
    do: Map.put(req, :preview, "v4.4.0-sim")

  defp finalize_device_request(req, _model), do: Map.put(req, :preview, nil)

  @spec day_of_week_name(term()) :: String.t()
  defp day_of_week_name(%NaiveDateTime{} = now) do
    now
    |> NaiveDateTime.to_date()
    |> Date.day_of_week()
    |> case do
      1 -> "Monday"
      2 -> "Tuesday"
      3 -> "Wednesday"
      4 -> "Thursday"
      5 -> "Friday"
      6 -> "Saturday"
      _ -> "Sunday"
    end
  end

  @spec utc_offset_minutes_now() :: integer()
  defp utc_offset_minutes_now do
    local_seconds =
      :calendar.local_time()
      |> :calendar.datetime_to_gregorian_seconds()

    utc_seconds =
      :calendar.universal_time()
      |> :calendar.datetime_to_gregorian_seconds()

    div(local_seconds - utc_seconds, 60)
  end

  @spec apply_device_data_hint(term(), term(), term()) :: term()
  defp apply_device_data_hint(state, target, req)
       when is_map(state) and target in [:watch, :companion, :phone] and is_map(req) do
    model = get_in(state, [target, :model]) || %{}
    runtime_model = Map.get(model, "runtime_model")
    runtime_model = if is_map(runtime_model), do: runtime_model, else: %{}
    preview = Map.get(req, :preview)

    runtime_model =
      case {Map.get(req, :kind), preview} do
        {"current_time_string", %{"string" => hhmm_text} = preview} ->
          runtime_model
          |> merge_matching_preview_fields(preview)
          |> merge_matching_preview_fields(%{"string" => hhmm_text})
          |> merge_declared_scalar_device_response(model, req, hhmm_text, :string)

        {"clock_style_24h", value} when is_boolean(value) ->
          Map.put(runtime_model, "clock_style_24h", value)

        {"timezone_is_set", value} when is_boolean(value) ->
          Map.put(runtime_model, "timezone_is_set", value)

        {"timezone", value} when is_binary(value) ->
          Map.put(runtime_model, "timezone", value)

        {"watch_model", value} when is_binary(value) ->
          Map.put(runtime_model, "watch_model", value)

        {"watch_color", value} when is_binary(value) ->
          Map.put(runtime_model, "watch_color", value)

        {"firmware_version", value} when is_binary(value) ->
          Map.put(runtime_model, "firmware_version", value)

        {_kind, value} when is_map(value) ->
          merge_matching_preview_fields(runtime_model, value)

        _ ->
          runtime_model
      end
      |> normalize_runtime_model_against_introspect(model)

    model =
      model
      |> Map.put("runtime_model", runtime_model)
      |> maybe_put_device_preview(req)

    view_tree = get_in(state, [target, :view_tree]) || %{}
    refreshed_model = refresh_runtime_fingerprints(model, runtime_model, view_tree)
    put_in(state, [target, :model], refreshed_model)
  end

  defp apply_device_data_hint(state, _target, _req), do: state

  @spec merge_matching_preview_fields(term(), term()) :: term()
  defp merge_matching_preview_fields(runtime_model, preview)
       when is_map(runtime_model) and is_map(preview) do
    Enum.reduce(preview, runtime_model, fn {key, value}, acc ->
      key_text = to_string(key)
      matching_key = matching_model_key(acc, key_text)

      case matching_key do
        nil ->
          acc

        model_key ->
          existing = Map.get(acc, model_key)

          case coerce_preview_value(existing, value) do
            {:ok, coerced} -> Map.put(acc, model_key, coerced)
            :error -> acc
          end
      end
    end)
  end

  defp merge_matching_preview_fields(runtime_model, _preview), do: runtime_model

  @spec merge_declared_scalar_device_response(map(), map(), map(), term(), atom()) :: map()
  defp merge_declared_scalar_device_response(runtime_model, model, req, value, kind)
       when is_map(runtime_model) and is_map(model) and is_map(req) and
              kind in [:string, :integer, :boolean] do
    with true <- device_response_constructor_declared?(model, Map.get(req, :response_message)),
         {:ok, key} <- unique_scalar_runtime_model_key(model, runtime_model, kind) do
      Map.put(runtime_model, key, value)
    else
      _ -> runtime_model
    end
  end

  defp merge_declared_scalar_device_response(runtime_model, _model, _req, _value, _kind),
    do: runtime_model

  @spec device_response_constructor_declared?(map(), term()) :: boolean()
  defp device_response_constructor_declared?(model, constructor)
       when is_map(model) and is_binary(constructor) and constructor != "" do
    model
    |> get_in(["elm_introspect", "update_case_branches"])
    |> case do
      branches when is_list(branches) ->
        Enum.any?(branches, fn branch ->
          is_binary(branch) and message_constructor(branch) == constructor
        end)

      _ ->
        false
    end
  end

  defp device_response_constructor_declared?(_model, _constructor), do: false

  @spec unique_scalar_runtime_model_key(map(), map(), atom()) :: {:ok, term()} | :error
  defp unique_scalar_runtime_model_key(model, runtime_model, kind)
       when is_map(model) and is_map(runtime_model) and kind in [:string, :integer, :boolean] do
    model
    |> introspect_init_model()
    |> Enum.filter(fn {key, value} ->
      scalar_kind?(value, kind) and Map.has_key?(runtime_model, key)
    end)
    |> case do
      [{key, _value}] -> {:ok, key}
      _ -> :error
    end
  end

  defp unique_scalar_runtime_model_key(_model, _runtime_model, _kind), do: :error

  @spec scalar_kind?(term(), atom()) :: boolean()
  defp scalar_kind?(value, :string), do: is_binary(value)
  defp scalar_kind?(value, :integer), do: is_integer(value)
  defp scalar_kind?(value, :boolean), do: is_boolean(value)
  defp scalar_kind?(_value, _kind), do: false

  @spec matching_model_key(map(), String.t()) :: term()
  defp matching_model_key(model, key_text) when is_map(model) and is_binary(key_text) do
    Enum.find_value(model, fn {existing_key, _existing_value} ->
      if to_string(existing_key) == key_text, do: existing_key, else: nil
    end)
  end

  @spec coerce_preview_value(term(), term()) :: term()
  defp coerce_preview_value(existing, value) when is_integer(existing) and is_integer(value),
    do: {:ok, value}

  defp coerce_preview_value(existing, value) when is_boolean(existing) and is_boolean(value),
    do: {:ok, value}

  defp coerce_preview_value(existing, value) when is_binary(existing) and is_binary(value),
    do: {:ok, value}

  defp coerce_preview_value(existing, value) when is_float(existing) and is_number(value),
    do: {:ok, value * 1.0}

  defp coerce_preview_value(nil, value), do: {:ok, %{"ctor" => "Just", "args" => [value]}}

  defp coerce_preview_value(%{"$ctor" => ctor, "$args" => args}, value)
       when ctor in ["Nothing", "Just"] and is_list(args),
       do: {:ok, %{"$ctor" => "Just", "$args" => [value]}}

  defp coerce_preview_value(%{"$ctor" => _ctor, "$args" => args}, value)
       when is_list(args) and is_binary(value),
       do: {:ok, %{"$ctor" => value, "$args" => []}}

  defp coerce_preview_value(%{"ctor" => ctor, "args" => args}, value)
       when ctor in ["Nothing", "Just"] and is_list(args),
       do: {:ok, %{"ctor" => "Just", "args" => [value]}}

  defp coerce_preview_value(%{"ctor" => _ctor, "args" => args}, value)
       when is_list(args) and is_binary(value),
       do: {:ok, %{"ctor" => value, "args" => []}}

  defp coerce_preview_value(_existing, _value), do: :error

  @spec normalize_runtime_patch_values(term(), term()) :: term()
  defp normalize_runtime_patch_values(model, patch) when is_map(model) and is_map(patch) do
    base_runtime_model =
      case Map.get(model, "runtime_model") || Map.get(model, :runtime_model) do
        value when is_map(value) -> value
        _ -> %{}
      end

    initial_runtime_model = introspect_init_model(model)

    case Map.get(patch, "runtime_model") || Map.get(patch, :runtime_model) do
      runtime_model when is_map(runtime_model) ->
        Map.put(
          patch,
          "runtime_model",
          normalize_runtime_model_values(base_runtime_model, runtime_model, initial_runtime_model)
        )

      _ ->
        patch
    end
  end

  defp normalize_runtime_patch_values(_model, patch), do: patch

  @spec normalize_runtime_model_values(map(), map(), map()) :: map()
  defp normalize_runtime_model_values(previous, next, initial)
       when is_map(previous) and is_map(next) and is_map(initial) do
    Map.new(next, fn {key, value} ->
      previous_value = Map.get(previous, key)
      initial_value = Map.get(initial, key)
      shape = normalize_runtime_shape(previous_value, initial_value)
      {key, normalize_runtime_value(shape, value)}
    end)
  end

  @spec normalize_runtime_model_against_introspect(term(), term()) :: term()
  defp normalize_runtime_model_against_introspect(runtime_model, model)
       when is_map(runtime_model) and is_map(model) do
    normalize_runtime_model_values(%{}, runtime_model, introspect_init_model(model))
  end

  defp normalize_runtime_model_against_introspect(runtime_model, _model), do: runtime_model

  @spec introspect_init_model(term()) :: map()
  defp introspect_init_model(model) when is_map(model) do
    case get_in(model, ["elm_introspect", "init_model"]) do
      value when is_map(value) -> hydrate_static_runtime_value(value)
      _ -> %{}
    end
  end

  defp introspect_init_model(_model), do: %{}

  @spec normalize_runtime_shape(term(), term()) :: term()
  defp normalize_runtime_shape(previous, initial) do
    cond do
      maybe_runtime_ctor?(previous) -> previous
      maybe_runtime_ctor?(initial) -> initial
      true -> previous
    end
  end

  @spec maybe_runtime_ctor?(term()) :: boolean()
  defp maybe_runtime_ctor?(%{"ctor" => ctor, "args" => args})
       when ctor in ["Nothing", "Just"] and is_list(args),
       do: true

  defp maybe_runtime_ctor?(%{"$ctor" => ctor, "$args" => args})
       when ctor in ["Nothing", "Just"] and is_list(args),
       do: true

  defp maybe_runtime_ctor?(_value), do: false

  @spec normalize_runtime_value(term(), term()) :: term()
  defp normalize_runtime_value(%{"ctor" => ctor, "args" => args}, {1, value})
       when ctor in ["Nothing", "Just"] and is_list(args),
       do: %{"ctor" => "Just", "args" => [normalize_runtime_value(nil, value)]}

  defp normalize_runtime_value(%{"ctor" => ctor, "args" => args}, value)
       when ctor in ["Nothing", "Just"] and is_list(args) and
              (is_integer(value) or is_float(value) or is_boolean(value) or is_binary(value)) and
              value != 0,
       do: %{"ctor" => "Just", "args" => [value]}

  defp normalize_runtime_value(%{"ctor" => ctor, "args" => args}, value)
       when ctor in ["Nothing", "Just"] and is_list(args) and is_map(value) do
    if maybe_runtime_ctor?(value) do
      normalize_runtime_value(nil, value)
    else
      %{"ctor" => "Just", "args" => [normalize_runtime_value(nil, value)]}
    end
  end

  defp normalize_runtime_value(%{"ctor" => "Just", "args" => [_ | _]} = previous, %{
         "ctor" => "Nothing",
         "args" => []
       }),
       do: previous

  defp normalize_runtime_value(%{"ctor" => "Just", "args" => [_ | _]} = previous, nil),
    do: previous

  defp normalize_runtime_value(%{"ctor" => "Just", "args" => [_ | _]} = previous, 0),
    do: previous

  defp normalize_runtime_value(%{"ctor" => ctor, "args" => args}, 0)
       when ctor in ["Nothing", "Just"] and is_list(args),
       do: %{"ctor" => "Nothing", "args" => []}

  defp normalize_runtime_value(%{"$ctor" => ctor, "$args" => args}, {1, value})
       when ctor in ["Nothing", "Just"] and is_list(args),
       do: %{"$ctor" => "Just", "$args" => [normalize_runtime_value(nil, value)]}

  defp normalize_runtime_value(%{"$ctor" => "Just", "$args" => [_ | _]} = previous, %{
         "$ctor" => "Nothing",
         "$args" => []
       }),
       do: previous

  defp normalize_runtime_value(%{"$ctor" => "Just", "$args" => [_ | _]} = previous, nil),
    do: previous

  defp normalize_runtime_value(%{"$ctor" => "Just", "$args" => [_ | _]} = previous, 0),
    do: previous

  defp normalize_runtime_value(%{"$ctor" => ctor, "$args" => args}, 0)
       when ctor in ["Nothing", "Just"] and is_list(args),
       do: %{"$ctor" => "Nothing", "$args" => []}

  defp normalize_runtime_value(previous, value) when is_map(previous) and is_map(value) do
    Map.new(value, fn {key, nested} ->
      {key, normalize_runtime_value(Map.get(previous, key), nested)}
    end)
  end

  defp normalize_runtime_value(_previous, value) when is_map(value) do
    Map.new(value, fn {key, nested} -> {key, normalize_runtime_value(nil, nested)} end)
  end

  defp normalize_runtime_value(previous, values) when is_list(previous) and is_list(values) do
    values
    |> Enum.with_index()
    |> Enum.map(fn {value, idx} -> normalize_runtime_value(Enum.at(previous, idx), value) end)
  end

  defp normalize_runtime_value(_previous, values) when is_list(values),
    do: Enum.map(values, &normalize_runtime_value(nil, &1))

  defp normalize_runtime_value(_previous, value), do: value

  @spec maybe_put_device_preview(term(), term()) :: term()
  defp maybe_put_device_preview(model, req) when is_map(model) and is_map(req) do
    preview = Map.get(req, :preview)
    kind = Map.get(req, :kind)

    if not is_nil(preview) and is_binary(kind) do
      Map.put(model, "debugger_device_#{kind}", preview)
    else
      model
    end
  end

  defp maybe_put_device_preview(model, _req), do: model

  @spec message_constructor(term()) :: String.t() | nil
  defp message_constructor(message) when is_binary(message) do
    message
    |> String.trim()
    |> String.split(~r/\s+/, parts: 2)
    |> List.first()
  end

  @spec enrich_protocol_events(term(), term(), term()) :: term()
  defp enrich_protocol_events(protocol_events, trigger, message_source)
       when is_list(protocol_events) and is_binary(trigger) do
    Enum.map(protocol_events, fn event ->
      type = Map.get(event, :type) || Map.get(event, "type")
      payload = Map.get(event, :payload) || Map.get(event, "payload")

      if is_binary(type) and is_map(payload) do
        %{
          type: type,
          payload: Map.merge(payload, %{trigger: trigger, message_source: message_source})
        }
      else
        %{type: nil, payload: %{}}
      end
    end)
  end

  @spec append_protocol_events(term(), term()) :: term()
  defp append_protocol_events(state, protocol_events) when is_list(protocol_events) do
    Enum.reduce(protocol_events, state, fn event, acc ->
      if is_binary(event.type) and is_map(event.payload) do
        append_event(acc, event.type, event.payload)
      else
        acc
      end
    end)
  end

  @spec apply_protocol_state_effects(term(), term()) :: term()
  defp apply_protocol_state_effects(state, protocol_events) when is_list(protocol_events) do
    Enum.reduce(protocol_events, state, fn event, acc ->
      if event.type == "debugger.protocol_rx" and is_map(event.payload) do
        {next_state, recipient, meta} = apply_protocol_rx_effect(acc, event.payload)

        if recipient in [:watch, :companion, :phone] do
          root =
            next_state
            |> get_in([recipient, :view_tree, "type"])
            |> case do
              value when is_binary(value) and value != "" -> value
              _ -> "simulated-root"
            end

          next_state
          |> append_runtime_exec_event_for_target(recipient, %{
            trigger: "protocol_rx",
            message: Map.get(meta, :message),
            message_source: Map.get(meta, :message_source),
            protocol_from: Map.get(meta, :from),
            protocol_to: source_root_for_target(recipient),
            protocol_inbound_count: Map.get(meta, :inbound_count)
          })
          |> append_event("debugger.update_in", %{
            target: source_root_for_target(recipient),
            message: Map.get(meta, :message),
            message_source: Map.get(meta, :message_source)
          })
          |> append_debugger_event(
            "update",
            recipient,
            Map.get(meta, :message),
            Map.get(meta, :message_source)
          )
          |> append_event("debugger.view_render", %{
            target: source_root_for_target(recipient),
            root: root
          })
          |> maybe_apply_protocol_rx_subscription(recipient, meta)
        else
          next_state
        end
      else
        acc
      end
    end)
  end

  @spec apply_protocol_rx_effect(term(), term()) :: term()
  defp apply_protocol_rx_effect(state, payload) when is_map(payload) do
    recipient = protocol_surface_key(Map.get(payload, :to) || Map.get(payload, "to"))
    sender = Map.get(payload, :from) || Map.get(payload, "from")
    message = Map.get(payload, :message) || Map.get(payload, "message")
    message_value = Map.get(payload, :message_value) || Map.get(payload, "message_value")
    message_source = "protocol_rx"

    if recipient in [:watch, :companion, :phone] and is_binary(message) do
      row = %{
        "from" => if(is_binary(sender), do: sender, else: "unknown"),
        "to" => surface_label(recipient),
        "message" => message,
        "message_value" => message_value,
        "trigger" => Map.get(payload, :trigger) || Map.get(payload, "trigger"),
        "message_source" =>
          Map.get(payload, :message_source) || Map.get(payload, "message_source")
      }

      next_state =
        state
        |> update_recipient_protocol_messages(recipient, row)
        |> put_in([recipient, :model, "protocol_last_inbound_message"], message)
        |> put_in(
          [recipient, :model, "protocol_last_inbound_from"],
          if(is_binary(sender), do: sender, else: "unknown")
        )
        |> update_in([recipient, :model, "protocol_inbound_count"], fn
          count when is_integer(count) and count >= 0 -> count + 1
          _ -> 1
        end)
        |> update_recipient_runtime_model_from_protocol(recipient, row)
        |> update_recipient_protocol_view_tree(recipient, row)
        |> refresh_runtime_surface_fingerprints(recipient)

      {
        next_state,
        recipient,
        %{
          message: message,
          message_value: message_value,
          message_source: message_source,
          from: if(is_binary(sender), do: sender, else: "unknown"),
          trigger: Map.get(payload, :trigger) || Map.get(payload, "trigger"),
          inbound_count: get_in(next_state, [recipient, :model, "protocol_inbound_count"]) || 0
        }
      }
    else
      {state, nil, %{}}
    end
  end

  @spec maybe_apply_protocol_rx_subscription(term(), term(), term()) :: term()
  defp maybe_apply_protocol_rx_subscription(state, recipient, meta)
       when is_map(state) and recipient in [:watch, :companion, :phone] and is_map(meta) do
    case protocol_rx_subscription_message(state, recipient, meta) do
      {message, message_value} when is_binary(message) and message != "" ->
        state
        |> apply_step_once(recipient, message, message_value, "protocol_rx", "protocol_rx")
        |> restore_protocol_rx_metadata(recipient, meta)

      message when is_binary(message) and message != "" ->
        state
        |> apply_step_once(recipient, message, "protocol_rx", "protocol_rx")
        |> restore_protocol_rx_metadata(recipient, meta)

      _ ->
        state
    end
  end

  defp maybe_apply_protocol_rx_subscription(state, _recipient, _meta), do: state

  defp restore_protocol_rx_metadata(state, recipient, meta)
       when is_map(state) and recipient in [:watch, :companion, :phone] and is_map(meta) do
    state =
      state
      |> put_in([recipient, :model, "protocol_last_inbound_message"], Map.get(meta, :message))
      |> put_in([recipient, :model, "protocol_last_inbound_from"], Map.get(meta, :from))
      |> put_in([recipient, :model, "protocol_inbound_count"], Map.get(meta, :inbound_count))

    if recipient in [:companion, :phone] do
      update_in(state, [recipient, :model, "runtime_model"], fn runtime_model ->
        runtime_model = if is_map(runtime_model), do: runtime_model, else: %{}

        runtime_model
        |> Map.put("protocol_last_inbound_message", Map.get(meta, :message))
        |> Map.put("protocol_last_inbound_from", Map.get(meta, :from))
        |> Map.put("protocol_inbound_count", Map.get(meta, :inbound_count))
      end)
    else
      state
    end
  end

  @spec protocol_rx_subscription_message(term(), term(), term()) ::
          {String.t(), term()} | String.t() | nil
  defp protocol_rx_subscription_message(state, recipient, meta)
       when is_map(state) and recipient in [:watch, :companion, :phone] and is_map(meta) do
    trigger = Map.get(meta, :trigger)
    from = Map.get(meta, :from)
    message = Map.get(meta, :message)
    message_value = Map.get(meta, :message_value)

    cond do
      not is_binary(trigger) or trigger == "" ->
        nil

      not is_binary(message) or message == "" ->
        nil

      recipient == :watch and from in ["companion", "phone"] ->
        protocol_rx_subscription_callback(state, recipient, "on_phone_to_watch")
        |> protocol_callback_message(message, message_value, false)

      recipient in [:companion, :phone] and from == "watch" ->
        protocol_rx_subscription_callback(state, recipient, "on_watch_to_phone")
        |> protocol_callback_message(message, message_value, true)

      true ->
        nil
    end
  end

  defp protocol_rx_subscription_message(_state, _recipient, _meta), do: nil

  @spec protocol_rx_subscription_callback(term(), term(), String.t()) :: String.t() | nil
  defp protocol_rx_subscription_callback(state, recipient, event_kind)
       when is_map(state) and recipient in [:watch, :companion, :phone] and is_binary(event_kind) do
    state
    |> get_in([recipient, :model, "elm_introspect"])
    |> introspect_cmd_calls("subscription_calls")
    |> Enum.find_value(fn row ->
      if Map.get(row, "event_kind") == event_kind do
        callback = Map.get(row, "callback_constructor")
        if is_binary(callback) and callback != "", do: callback, else: nil
      end
    end)
  end

  defp protocol_rx_subscription_callback(_state, _recipient, _event_kind), do: nil

  @spec protocol_callback_message(String.t() | nil, String.t(), term(), boolean()) ::
          {String.t(), term()} | String.t() | nil
  defp protocol_callback_message(callback, message, message_value, wrap_result?)
       when is_binary(callback) and callback != "" and is_binary(message) and message != "" do
    message = parenthesize_elm_arg(message)

    {display, value} =
      if wrap_result? do
        {
          "#{callback} (Ok #{message})",
          if(is_map(message_value),
            do:
              wrap_protocol_callback_value(callback, %{"ctor" => "Ok", "args" => [message_value]}),
            else: nil
          )
        }
      else
        {
          "#{callback} #{message}",
          wrap_protocol_callback_value(callback, message_value)
        }
      end

    if is_map(value) do
      {display, value}
    else
      display
    end
  end

  defp protocol_callback_message(_callback, _message, _message_value, _wrap_result?), do: nil

  @spec wrap_protocol_callback_value(String.t(), term()) :: map() | nil
  defp wrap_protocol_callback_value(callback, value)
       when is_binary(callback) and callback != "" and is_map(value) do
    %{"ctor" => callback, "args" => [value]}
  end

  defp wrap_protocol_callback_value(_callback, _value), do: nil

  @spec parenthesize_elm_arg(String.t()) :: String.t()
  defp parenthesize_elm_arg(value) when is_binary(value) do
    trimmed = String.trim(value)

    cond do
      trimmed == "" -> trimmed
      String.starts_with?(trimmed, "(") -> trimmed
      String.contains?(trimmed, " ") -> "(" <> trimmed <> ")"
      true -> trimmed
    end
  end

  @spec update_recipient_protocol_messages(term(), term(), term()) :: term()
  defp update_recipient_protocol_messages(state, recipient, row)
       when recipient in [:watch, :companion, :phone] do
    update_in(state, [recipient, :protocol_messages], fn
      xs when is_list(xs) -> [row | xs] |> Enum.take(25)
      _ -> [row]
    end)
  end

  defp update_recipient_protocol_messages(state, _recipient, _row), do: state

  @spec update_recipient_runtime_model_from_protocol(term(), term(), term()) :: term()
  defp update_recipient_runtime_model_from_protocol(state, recipient, row)
       when recipient in [:watch, :companion, :phone] and is_map(row) do
    inbound_count = get_in(state, [recipient, :model, "protocol_inbound_count"]) || 0

    state
    |> put_in([recipient, :model, "protocol_last_inbound_message"], row["message"])
    |> put_in([recipient, :model, "protocol_last_inbound_from"], row["from"])
    |> put_in([recipient, :model, "protocol_inbound_count"], inbound_count)
    |> put_in(
      [recipient, :model, "protocol_message_count"],
      length(get_in(state, [recipient, :protocol_messages]) || [])
    )
    |> put_in([recipient, :model, "protocol_last_trigger"], row["trigger"])
    |> maybe_update_protocol_runtime_model(recipient, row, inbound_count)
    |> put_in([recipient, :model, "runtime_last_message"], row["message"])
    |> put_in([recipient, :model, "runtime_message_source"], "protocol_rx")
  end

  defp maybe_update_protocol_runtime_model(state, :watch, _row, _inbound_count), do: state

  defp maybe_update_protocol_runtime_model(state, recipient, row, inbound_count)
       when recipient in [:companion, :phone] do
    update_in(state, [recipient, :model, "runtime_model"], fn runtime_model ->
      runtime_model = if is_map(runtime_model), do: runtime_model, else: %{}

      runtime_model
      |> Map.put("protocol_last_inbound_message", row["message"])
      |> Map.put("protocol_last_inbound_from", row["from"])
      |> Map.put("protocol_inbound_count", inbound_count)
      |> Map.put(
        "protocol_message_count",
        length(get_in(state, [recipient, :protocol_messages]) || [])
      )
    end)
  end

  @spec update_recipient_protocol_view_tree(term(), term(), term()) :: term()
  defp update_recipient_protocol_view_tree(state, recipient, row)
       when recipient in [:watch, :companion, :phone] and is_map(row) do
    put_in(state, [recipient, :model, "protocol_last_view_message"], row["message"])
  end

  @spec refresh_runtime_surface_fingerprints(term(), term()) :: term()
  defp refresh_runtime_surface_fingerprints(state, recipient)
       when recipient in [:watch, :companion, :phone] do
    model = get_in(state, [recipient, :model]) || %{}
    runtime_model = Map.get(model, "runtime_model")
    runtime_model = if is_map(runtime_model), do: runtime_model, else: %{}
    view_tree = get_in(state, [recipient, :view_tree]) || %{}

    put_in(
      state,
      [recipient, :model],
      refresh_runtime_fingerprints(model, runtime_model, view_tree)
    )
  end

  @spec protocol_surface_key(term()) :: :watch | :companion | :phone
  defp protocol_surface_key("watch"), do: :watch
  defp protocol_surface_key("companion"), do: :companion
  defp protocol_surface_key("phone"), do: :phone
  defp protocol_surface_key(_), do: :companion

  @spec surface_label(term()) :: String.t()
  defp surface_label(:watch), do: "watch"
  defp surface_label(:companion), do: "companion"
  defp surface_label(:phone), do: "phone"

  @spec tick_targets(term()) :: [:watch | :companion | :phone]
  defp tick_targets(nil), do: [:watch, :companion, :phone]
  defp tick_targets(target) when target in [:watch, :companion, :phone], do: [target]

  @spec trigger_candidates_for_surface(term(), term()) :: [map()]
  defp trigger_candidates_for_surface(state, target)
       when is_map(state) and target in [:watch, :companion, :phone] do
    model = get_in(state, [target, :model]) || %{}
    ei = Map.get(model, "elm_introspect")
    msg_constructors = introspect_list(ei, "msg_constructors")
    update_branches = introspect_list(ei, "update_case_branches")
    subscription_ops = introspect_list(ei, "subscription_ops")
    subscription_calls = introspect_cmd_calls(ei, "subscription_calls")
    known_messages = if msg_constructors != [], do: msg_constructors, else: update_branches
    target_name = source_root_for_target(target)

    call_rows =
      subscription_calls
      |> Enum.filter(&subscription_call_fireable?/1)
      |> Enum.map(fn op ->
        trigger = subscription_trigger_for_call(op)
        label = Map.get(op, "label") || Map.get(op, "name") || trigger
        callback = Map.get(op, "callback_constructor")
        message = callback || best_message_for_trigger(known_messages, to_string(trigger || ""))
        trigger_id = normalize_trigger_id(trigger)

        metadata =
          op
          |> button_subscription_metadata()
          |> Map.merge(subscription_timing_metadata(op))

        %{
          id: "#{target_name}:#{trigger_id}:#{normalize_trigger_id(message)}",
          label: normalize_trigger_label(label),
          trigger: to_string(trigger || "trigger"),
          target: target_name,
          message: message,
          source: "subscription"
        }
        |> Map.merge(metadata)
      end)

    op_rows =
      subscription_ops
      |> Enum.map(&String.trim/1)
      |> Enum.reject(&(&1 == ""))
      |> Enum.filter(&subscription_op_fireable?/1)
      |> Enum.map(fn op ->
        message = best_message_for_trigger(known_messages, op)

        %{
          id: "#{target_name}:#{normalize_trigger_id(op)}",
          label: normalize_trigger_label(op),
          trigger: op,
          target: target_name,
          message: message,
          source: "subscription"
        }
      end)

    fallback_rows =
      fallback_trigger_seed_rows(target_name)
      |> Enum.map(fn %{trigger: trigger, label: label} ->
        message = best_message_for_trigger(known_messages, trigger)

        %{
          id: "#{target_name}:#{normalize_trigger_id(trigger)}",
          label: label,
          trigger: trigger,
          target: target_name,
          message: message,
          source: "fallback"
        }
      end)

    primary_rows = if call_rows == [], do: op_rows, else: call_rows

    (primary_rows ++ if(primary_rows == [], do: fallback_rows, else: []))
    |> Enum.uniq_by(fn row -> {row.target, row.trigger, row.message} end)
    |> Enum.filter(fn row -> is_binary(row.message) and row.message != "" end)
  end

  defp trigger_candidates_for_surface(_state, _target), do: []

  @spec button_subscription_metadata(term()) :: map()
  defp button_subscription_metadata(%{"target" => target, "arg_snippets" => [button, event | _]})
       when is_binary(target) and is_binary(button) and is_binary(event) do
    case subscription_target_name(target) do
      "on" ->
        %{
          button: normalize_button_subscription_arg(button),
          button_event: normalize_button_subscription_arg(event)
        }

      name ->
        button_event_metadata(name, button)
    end
  end

  defp button_subscription_metadata(%{"target" => target, "arg_snippets" => [button | _]})
       when is_binary(target) and is_binary(button) do
    button_event_metadata(subscription_target_name(target), button)
  end

  defp button_subscription_metadata(_op), do: %{}

  defp button_event_metadata(target_name, button) do
    case target_name do
      "onPress" ->
        %{button: normalize_button_subscription_arg(button), button_event: "pressed"}

      "onRelease" ->
        %{button: normalize_button_subscription_arg(button), button_event: "released"}

      "onLongPress" ->
        %{button: normalize_button_subscription_arg(button), button_event: "longpressed"}

      _ ->
        %{}
    end
  end

  @spec subscription_timing_metadata(map()) :: map()
  defp subscription_timing_metadata(%{"target" => target, "arg_snippets" => snippets})
       when is_binary(target) and is_list(snippets) do
    if frame_subscription_target?(target) do
      case frame_subscription_interval_ms(target, snippets) do
        interval_ms when is_integer(interval_ms) ->
          %{
            interval_ms: clamp_auto_fire_interval_ms(interval_ms),
            declared_interval_ms: interval_ms
          }

        _ ->
          %{}
      end
    else
      %{}
    end
  end

  defp subscription_timing_metadata(_op), do: %{}

  @spec frame_subscription_interval_ms(String.t(), [term()]) :: integer() | nil
  defp frame_subscription_interval_ms(target, snippets)
       when is_binary(target) and is_list(snippets) do
    value = snippets |> List.first() |> normalize_integer(0)
    target_name = target |> subscription_target_name() |> String.downcase()

    cond do
      value <= 0 ->
        nil

      target_name == "atfps" ->
        div(1_000, max(1, value))

      true ->
        value
    end
  end

  @spec clamp_auto_fire_interval_ms(term()) :: pos_integer()
  defp clamp_auto_fire_interval_ms(interval_ms) when is_integer(interval_ms) do
    interval_ms
    |> max(@min_auto_fire_interval_ms)
    |> min(60_000)
  end

  defp clamp_auto_fire_interval_ms(_interval_ms), do: @default_auto_fire_interval_ms

  @spec subscription_trigger_for_call(map()) :: String.t() | nil
  defp subscription_trigger_for_call(%{"target" => target} = op) when is_binary(target) do
    if frame_subscription_target?(target) do
      target
    else
      Map.get(op, "event_kind") || Map.get(op, "name") || target
    end
  end

  defp subscription_trigger_for_call(op) when is_map(op) do
    Map.get(op, "event_kind") || Map.get(op, "name") || Map.get(op, "target")
  end

  @spec frame_subscription_target?(term()) :: boolean()
  defp frame_subscription_target?(target) when is_binary(target) do
    normalized =
      target
      |> String.downcase()
      |> String.replace(~r/[^a-z0-9.]+/, "")

    String.contains?(normalized, "frame.") or String.ends_with?(normalized, ".onframe") or
      String.ends_with?(normalized, "onframe")
  end

  defp frame_subscription_target?(_target), do: false

  @spec subscription_target_name(term()) :: String.t()
  defp subscription_target_name(target) when is_binary(target) do
    target
    |> String.split(".")
    |> List.last()
    |> to_string()
  end

  defp subscription_target_name(_target), do: ""

  @spec normalize_button_subscription_arg(term()) :: String.t()
  defp normalize_button_subscription_arg(value) when is_binary(value) do
    value
    |> String.split(".")
    |> List.last()
    |> to_string()
    |> String.downcase()
  end

  defp normalize_button_subscription_arg(_value), do: ""

  @spec subscription_call_fireable?(term()) :: boolean()
  defp subscription_call_fireable?(call) when is_map(call) do
    kind =
      call
      |> Map.get("event_kind")
      |> to_string()
      |> String.downcase()

    target =
      call
      |> Map.get("target")
      |> to_string()
      |> String.downcase()

    kind not in ["", "none", "batch"] and
      not String.ends_with?(target, ".none") and
      not String.ends_with?(target, ".batch")
  end

  defp subscription_call_fireable?(_call), do: false

  @spec subscription_op_fireable?(term()) :: boolean()
  defp subscription_op_fireable?(op) when is_binary(op) do
    normalized =
      op
      |> String.downcase()
      |> String.replace(~r/[^a-z0-9]+/, "_")
      |> String.trim("_")

    normalized not in ["", "sub_none", "none", "sub_batch", "batch"]
  end

  defp subscription_op_fireable?(_op), do: false

  @spec trigger_message_for_surface(term(), term(), term(), term()) :: String.t()
  defp trigger_message_for_surface(state, target, trigger, requested_message)
       when is_map(state) and target in [:watch, :companion, :phone] and is_binary(trigger) do
    message =
      if is_binary(requested_message) and requested_message != "" do
        requested_message
      else
        model = get_in(state, [target, :model]) || %{}
        ei = Map.get(model, "elm_introspect")
        msg_constructors = introspect_list(ei, "msg_constructors")
        update_branches = introspect_list(ei, "update_case_branches")
        known_messages = if msg_constructors != [], do: msg_constructors, else: update_branches
        best_message_for_trigger(known_messages, trigger)
      end

    maybe_attach_subscription_payload(state, target, message, trigger)
  end

  defp trigger_message_for_surface(_state, _target, _trigger, requested_message)
       when is_binary(requested_message),
       do: requested_message

  defp trigger_message_for_surface(_state, _target, trigger, _requested_message)
       when is_binary(trigger),
       do:
         maybe_attach_subscription_payload(
           %{},
           :watch,
           default_message_for_trigger(trigger),
           trigger
         )

  @spec maybe_attach_subscription_payload(term(), term(), term(), term()) :: String.t()
  defp maybe_attach_subscription_payload(state, target, message, trigger_like)
       when is_map(state) and is_binary(message) and is_binary(trigger_like) do
    message_text = String.trim(message)

    if message_text == "" or String.contains?(message_text, " ") do
      message
    else
      now = NaiveDateTime.local_now()
      # `subscription_event_kind/1` turns e.g. `PebbleEvents.onHourChange` into `on_hour_change`.
      # Match after removing punctuation so "on_hour_change", "onHourChange", and "onhourchange"
      # all line up the same way.
      t =
        trigger_like
        |> to_string()
        |> String.downcase()
        |> String.replace(~r/[^a-z0-9]/, "")

      cond do
        frame_subscription_trigger?(trigger_like) and
            subscription_message_arity(state, target, message_text) == 1 ->
          "#{message_text} #{Jason.encode!(subscription_frame_payload(state, target))}"

        (String.contains?(t, "ontick") or String.contains?(t, "tick")) and
            subscription_message_arity(state, target, message_text) == 1 ->
          "#{message_text} #{now.second}"

        # Minute before hour so a hypothetical name containing both substrings is unambiguous.
        String.contains?(t, "minutechange") or String.contains?(t, "onminute") ->
          "#{message_text} #{now.minute}"

        String.contains?(t, "hourchange") or String.contains?(t, "onhour") ->
          "#{message_text} #{now.hour}"

        String.contains?(t, "batterychange") or String.contains?(t, "onbattery") ->
          "#{message_text} #{subscription_battery_level(state, target)}"

        String.contains?(t, "connectionchange") or String.contains?(t, "onconnection") ->
          "#{message_text} #{subscription_connection_status(state, target)}"

        true ->
          message
      end
    end
  end

  defp maybe_attach_subscription_payload(_state, _target, message, _trigger_like)
       when is_binary(message),
       do: message

  @spec subscription_message_arity(map(), term(), String.t()) :: non_neg_integer()
  defp subscription_message_arity(state, target, message)
       when is_map(state) and is_binary(message) do
    state
    |> get_in([target, :model, "elm_introspect", "msg_constructor_arities"])
    |> case do
      arities when is_map(arities) ->
        arities
        |> Map.get(message, 0)
        |> normalize_integer(0)

      _ ->
        0
    end
  end

  @spec frame_subscription_trigger?(term()) :: boolean()
  defp frame_subscription_trigger?(trigger_like) when is_binary(trigger_like) do
    normalized =
      trigger_like
      |> String.downcase()
      |> String.replace(~r/[^a-z0-9]+/, "")

    String.contains?(normalized, "frame") or String.contains?(normalized, "onframe")
  end

  defp frame_subscription_trigger?(_trigger_like), do: false

  @spec subscription_frame_payload(map(), term()) :: map()
  defp subscription_frame_payload(state, target) when is_map(state) do
    model =
      case target do
        surface when surface in [:watch, :companion, :phone] ->
          get_in(state, [surface, :model]) || %{}

        _ ->
          %{}
      end

    frame =
      model
      |> Map.get("_debugger_steps")
      |> normalize_integer(0)
      |> max(0)
      |> Kernel.+(1)

    dt_ms = 16

    %{
      "dtMs" => dt_ms,
      "elapsedMs" => frame * dt_ms,
      "frame" => frame
    }
  end

  @spec subscription_battery_level(map(), term()) :: integer()
  defp subscription_battery_level(state, target) when is_map(state) do
    state
    |> subscription_runtime_value(target, "batteryLevel")
    |> unwrap_elm_maybe()
    |> normalize_integer(88)
    |> min(100)
    |> max(0)
  end

  @spec subscription_connection_status(map(), term()) :: String.t()
  defp subscription_connection_status(state, target) when is_map(state) do
    state
    |> subscription_runtime_value(target, "connected")
    |> unwrap_elm_maybe()
    |> normalize_boolean(true)
    |> then(fn
      true -> "True"
      false -> "False"
    end)
  end

  @spec subscription_runtime_value(map(), term(), String.t()) :: term()
  defp subscription_runtime_value(state, target, key) when is_map(state) and is_binary(key) do
    with surface when surface in [:watch, :companion, :phone] <- target,
         runtime_model when is_map(runtime_model) <-
           get_in(state, [surface, :model, "runtime_model"]) do
      Map.get(runtime_model, key)
    else
      _ -> nil
    end
  end

  @spec unwrap_elm_maybe(term()) :: term()
  defp unwrap_elm_maybe(%{"ctor" => "Just", "args" => [value | _]}), do: value
  defp unwrap_elm_maybe(%{ctor: "Just", args: [value | _]}), do: value
  defp unwrap_elm_maybe(value), do: value

  @spec normalize_integer(term(), integer()) :: integer()
  defp normalize_integer(value, _default) when is_integer(value), do: value

  defp normalize_integer(value, default) when is_binary(value) and is_integer(default) do
    case Integer.parse(value) do
      {parsed, ""} -> parsed
      _ -> default
    end
  end

  defp normalize_integer(_value, default) when is_integer(default), do: default

  @spec normalize_boolean(term(), boolean()) :: boolean()
  defp normalize_boolean(value, _default) when is_boolean(value), do: value
  defp normalize_boolean("True", _default), do: true
  defp normalize_boolean("False", _default), do: false
  defp normalize_boolean("true", _default), do: true
  defp normalize_boolean("false", _default), do: false
  defp normalize_boolean(_value, default) when is_boolean(default), do: default

  @spec best_message_for_trigger(term(), term()) :: String.t()
  defp best_message_for_trigger(known_messages, trigger)
       when is_list(known_messages) and is_binary(trigger) do
    normalized = String.downcase(trigger)

    exact =
      Enum.find(known_messages, fn message ->
        String.downcase(message) == normalized
      end)

    fuzzy =
      first_matching_message(known_messages, trigger_tokens(normalized)) ||
        fallback_message_for_trigger(known_messages, normalized)

    preferred_fallback =
      cond do
        buttonish_trigger?(normalized) ->
          first_non_tick_message(known_messages)

        contains_any?(normalized, ["tick", "time", "clock"]) ->
          Enum.find(known_messages, &tickish_message?/1)

        true ->
          nil
      end

    exact || fuzzy || preferred_fallback || List.first(known_messages) ||
      default_message_for_trigger(trigger)
  end

  defp best_message_for_trigger(_known_messages, trigger) when is_binary(trigger),
    do: default_message_for_trigger(trigger)

  defp best_message_for_trigger(_known_messages, _trigger), do: "Tick"

  @spec first_matching_message(term(), term()) :: String.t() | nil
  defp first_matching_message(known_messages, tokens)
       when is_list(known_messages) and is_list(tokens) do
    Enum.find(known_messages, fn message ->
      down = String.downcase(message)
      Enum.all?(tokens, &String.contains?(down, &1))
    end)
  end

  defp first_matching_message(_known_messages, _tokens), do: nil

  @spec fallback_message_for_trigger(term(), term()) :: String.t() | nil
  defp fallback_message_for_trigger(known_messages, trigger_down)
       when is_list(known_messages) and is_binary(trigger_down) do
    cond do
      contains_any?(trigger_down, ["up"]) ->
        first_matching_message(known_messages, ["up"]) ||
          first_matching_message(known_messages, ["inc"])

      contains_any?(trigger_down, ["down"]) ->
        first_matching_message(known_messages, ["down"]) ||
          first_matching_message(known_messages, ["dec"])

      contains_any?(trigger_down, ["select", "ok"]) ->
        first_matching_message(known_messages, ["select"]) ||
          first_matching_message(known_messages, ["ok"]) ||
          first_matching_message(known_messages, ["press"])

      contains_any?(trigger_down, ["back"]) ->
        first_matching_message(known_messages, ["back"]) ||
          first_matching_message(known_messages, ["cancel"])

      contains_any?(trigger_down, ["tick", "time", "clock"]) ->
        Enum.find(known_messages, &tickish_message?/1)

      true ->
        nil
    end
  end

  defp fallback_message_for_trigger(_known_messages, _trigger_down), do: nil

  @spec trigger_tokens(term()) :: [String.t()]
  defp trigger_tokens(trigger_down) when is_binary(trigger_down) do
    trigger_down
    |> String.split(~r/[^a-z0-9]+/, trim: true)
    |> Enum.reject(&(&1 == "button" or &1 == "press" or &1 == "short" or &1 == "long"))
  end

  @spec buttonish_trigger?(term()) :: boolean()
  defp buttonish_trigger?(trigger_down) when is_binary(trigger_down) do
    contains_any?(trigger_down, ["button", "up", "down", "select", "back", "press", "tap"])
  end

  @spec first_non_tick_message(term()) :: String.t() | nil
  defp first_non_tick_message(known_messages) when is_list(known_messages) do
    Enum.find(known_messages, fn message ->
      is_binary(message) and not tickish_message?(message)
    end)
  end

  @spec default_message_for_trigger(term()) :: String.t()
  defp default_message_for_trigger(trigger) when is_binary(trigger) do
    normalized = String.downcase(trigger)

    if buttonish_trigger?(normalized) do
      trigger
      |> String.split(~r/[^a-zA-Z0-9]+/, trim: true)
      |> Enum.map(&String.capitalize/1)
      |> Enum.join()
      |> case do
        "" -> "ButtonPress"
        value -> value
      end
    else
      "Tick"
    end
  end

  @spec normalize_trigger_id(term()) :: String.t()
  defp normalize_trigger_id(trigger) when is_binary(trigger) do
    trigger
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9]+/, "_")
    |> String.trim("_")
  end

  defp normalize_trigger_id(_), do: "trigger"

  @spec normalize_trigger_label(term()) :: String.t()
  defp normalize_trigger_label(trigger) when is_binary(trigger) do
    trigger
    |> String.replace(~r/[_\.\-]+/, " ")
    |> String.trim()
    |> case do
      "" -> "Trigger"
      value -> value
    end
  end

  defp normalize_trigger_label(_), do: "Trigger"

  @spec fallback_trigger_seed_rows(term()) :: [map()]
  defp fallback_trigger_seed_rows(target_name) when is_binary(target_name) do
    [
      %{trigger: "button_up", label: "Button Up"},
      %{trigger: "button_long_up", label: "Button Long Up"},
      %{trigger: "button_down", label: "Button Down"},
      %{trigger: "button_long_down", label: "Button Long Down"},
      %{trigger: "button_select", label: "Button Select"},
      %{trigger: "button_long_select", label: "Button Long Select"},
      %{trigger: "button_back", label: "Button Back"},
      %{trigger: "tick", label: "Tick"}
    ]
  end

  @spec tick_message_for_surface(term(), term()) :: String.t()
  defp tick_message_for_surface(state, target) when is_map(state) do
    model = get_in(state, [target, :model]) || %{}
    ei = Map.get(model, "elm_introspect")
    msg_constructors = introspect_list(ei, "msg_constructors")
    update_branches = introspect_list(ei, "update_case_branches")
    subscription_ops = introspect_list(ei, "subscription_ops")
    known_messages = if msg_constructors != [], do: msg_constructors, else: update_branches

    cond do
      known_messages == [] ->
        "Tick"

      subscription_ops != [] ->
        {message, matched_op} =
          pick_subscription_message(known_messages, subscription_ops, "tick")

        maybe_attach_subscription_payload(state, target, message, matched_op || "tick")

      true ->
        Enum.find(known_messages, "Tick", &tickish_message?/1)
    end
  end

  @spec pick_subscription_message(term(), term(), term()) :: {String.t(), String.t() | nil}
  defp pick_subscription_message(known_messages, subscription_ops, trigger)
       when is_list(known_messages) and is_list(subscription_ops) and is_binary(trigger) do
    ranked =
      known_messages
      |> Enum.with_index()
      |> Enum.flat_map(fn {message, index} ->
        message_tokens = normalized_event_tokens(message)

        subscription_ops
        |> Enum.filter(fn op ->
          subscription_op_matches_message?(op, message, message_tokens)
        end)
        |> Enum.map(fn op ->
          {subscription_match_priority(op, trigger), index, message, op}
        end)
      end)
      |> Enum.sort()

    case ranked do
      [{_priority, _index, message, op} | _] -> {message, op}
      _ -> {List.first(known_messages) || "Tick", nil}
    end
  end

  @spec subscription_match_priority(term(), term()) :: integer()
  defp subscription_match_priority(op, trigger)
       when is_binary(op) and is_binary(trigger) do
    op_down = String.downcase(op)
    trigger_down = String.downcase(trigger)

    if contains_any?(trigger_down, ["tick", "time", "clock"]) do
      cond do
        contains_any?(op_down, ["second"]) -> 0
        contains_any?(op_down, ["minute"]) -> 1
        contains_any?(op_down, ["tick", "time", "clock"]) -> 2
        contains_any?(op_down, ["hour"]) -> 3
        true -> 4
      end
    else
      0
    end
  end

  @spec tickish_message?(term()) :: boolean()
  defp tickish_message?(message) when is_binary(message) do
    contains_any?(String.downcase(message), ["tick", "time", "clock", "second", "minute", "hour"])
  end

  @spec subscription_op_matches_message?(term(), term(), term()) :: boolean()
  defp subscription_op_matches_message?(op, message, message_tokens)
       when is_binary(op) and is_binary(message) and is_list(message_tokens) do
    op_down = String.downcase(op)
    message_down = String.downcase(message)
    op_tokens = normalized_event_tokens(op)

    direct_match? =
      String.contains?(op_down, message_down) or String.contains?(message_down, op_down)

    token_match? =
      message_tokens
      |> Enum.reject(&(&1 in ["on", "event", "change", "changed", "subscription"]))
      |> Enum.any?(&(&1 in op_tokens))

    direct_match? or token_match?
  end

  defp subscription_op_matches_message?(_op, _message, _message_tokens), do: false

  @spec normalized_event_tokens(term()) :: [String.t()]
  defp normalized_event_tokens(text) when is_binary(text) do
    text
    |> String.replace(~r/([a-z])([A-Z])/, "\\1 \\2")
    |> String.replace(~r/[^A-Za-z0-9]+/, " ")
    |> String.downcase()
    |> String.split(" ", trim: true)
  end

  defp normalized_event_tokens(_), do: []

  @spec parse_tick_interval_ms(term()) :: pos_integer()
  defp parse_tick_interval_ms(value) when is_integer(value) and value >= 100,
    do: min(value, 60_000)

  defp parse_tick_interval_ms(value) when is_binary(value) do
    case Integer.parse(String.trim(value)) do
      {parsed, ""} when parsed >= 100 -> min(parsed, 60_000)
      _ -> 1_000
    end
  end

  defp parse_tick_interval_ms(_), do: 1_000

  @spec parse_checkbox_bool(term()) :: boolean()
  defp parse_checkbox_bool(value) when value in [true, "true", "on", "1", 1], do: true
  defp parse_checkbox_bool(_value), do: false

  @spec auto_tick_loop(term(), term(), term(), term()) :: :ok
  defp auto_tick_loop(project_slug, interval_ms, targets, count)
       when is_binary(project_slug) and is_integer(interval_ms) and interval_ms >= 100 do
    receive do
      :stop ->
        :ok
    after
      interval_ms ->
        Enum.each(List.wrap(targets), fn target ->
          _ = tick(project_slug, %{target: source_root_for_target(target), count: count})
        end)

        auto_tick_loop(project_slug, interval_ms, targets, count)
    end
  end

  @spec auto_fire_loop(term(), term(), term(), non_neg_integer()) :: :ok
  defp auto_fire_loop(project_slug, interval_ms, targets, cursor)
       when is_binary(project_slug) and is_integer(interval_ms) and interval_ms >= 100 and
              is_integer(cursor) and cursor >= 0 do
    receive do
      :stop ->
        :ok
    after
      interval_ms ->
        _ = fire_auto_subscriptions(project_slug, targets, cursor)
        auto_fire_loop(project_slug, interval_ms, targets, cursor + 1)
    end
  end

  @spec fire_auto_subscriptions(String.t(), [:watch | :companion | :phone], non_neg_integer()) ::
          {:ok, runtime_state()}
  defp fire_auto_subscriptions(project_slug, targets, _cursor)
       when is_binary(project_slug) and is_list(targets) do
    update(project_slug, fn state ->
      if Map.get(state, :running, false) do
        now = NaiveDateTime.local_now()

        Enum.reduce(targets, state, fn target, acc ->
          {rows, acc} = auto_fire_subscription_candidates(acc, target, now)

          rows
          |> Enum.reduce(acc, fn %{message: message, trigger: trigger}, row_acc ->
            resolved_message = trigger_message_for_surface(row_acc, target, trigger, message)
            apply_step_once(row_acc, target, resolved_message, "subscription_auto_fire", trigger)
          end)
          |> put_auto_fire_clock(target, now)
        end)
      else
        state
      end
    end)
  end

  @spec auto_fire_subscription_candidates(term(), :watch | :companion | :phone, NaiveDateTime.t()) ::
          {[map()], map()}
  defp auto_fire_subscription_candidates(state, target, %NaiveDateTime{} = now)
       when is_map(state) and target in [:watch, :companion, :phone] do
    rows =
      state
      |> trigger_candidates_for_surface(target)
      |> Enum.filter(fn row ->
        Map.get(row, :source) == "subscription" and is_binary(Map.get(row, :message)) and
          Map.get(row, :message) != "" and is_binary(Map.get(row, :trigger)) and
          Map.get(row, :trigger) != "" and subscription_trigger_enabled?(state, target, row) and
          auto_fire_subscription_enabled?(state, target, row)
      end)

    {Enum.filter(rows, &auto_fire_subscription_due?(state, target, &1, now)), state}
  end

  defp auto_fire_subscription_candidates(state, _target, _now) when is_map(state), do: {[], state}

  @spec auto_fire_subscription_due?(map(), :watch | :companion | :phone, map(), NaiveDateTime.t()) ::
          boolean()
  defp auto_fire_subscription_due?(state, target, row, %NaiveDateTime{} = now)
       when is_map(state) and is_map(row) do
    trigger =
      row
      |> Map.get(:trigger)
      |> to_string()
      |> String.downcase()

    clock = auto_fire_clock_for_target(state, target)

    cond do
      frame_subscription_trigger?(trigger) ->
        true

      contains_any?(trigger, ["on_tick", "ontick", "tick"]) ->
        true

      contains_any?(trigger, ["on_second_change", "onsecondchange", "second"]) ->
        Map.get(clock, "second") != now.second

      contains_any?(trigger, ["on_minute_change", "onminutechange", "minute"]) ->
        Map.get(clock, "minute") != now.minute

      contains_any?(trigger, ["on_hour_change", "onhourchange", "hour"]) ->
        Map.get(clock, "hour") != now.hour

      true ->
        false
    end
  end

  defp auto_fire_subscription_due?(_state, _target, _row, _now), do: false

  @spec auto_fire_clock_for_target(map(), :watch | :companion | :phone) :: map()
  defp auto_fire_clock_for_target(state, target) when is_map(state) do
    state
    |> Map.get(:auto_fire_clock, %{})
    |> Map.get(source_root_for_target(target), %{})
  end

  @spec put_auto_fire_clock(map(), :watch | :companion | :phone, NaiveDateTime.t()) :: map()
  defp put_auto_fire_clock(state, target, %NaiveDateTime{} = now) when is_map(state) do
    clock =
      state
      |> Map.get(:auto_fire_clock, %{})
      |> Map.put(source_root_for_target(target), %{
        "hour" => now.hour,
        "minute" => now.minute,
        "second" => now.second
      })

    Map.put(state, :auto_fire_clock, clock)
  end

  @spec restart_auto_fire_worker(term(), String.t(), [:watch | :companion | :phone], [map()]) ::
          map()
  defp restart_auto_fire_worker(state, project_slug, targets, subscriptions)
       when is_map(state) and is_binary(project_slug) and is_list(targets) do
    state = stop_auto_tick_worker(state)

    case targets do
      [] ->
        state

      [_ | _] ->
        interval_ms = auto_fire_worker_interval_ms(state, targets, subscriptions)
        count = 1
        worker = spawn(fn -> auto_fire_loop(project_slug, interval_ms, targets, 0) end)

        state
        |> initialize_auto_fire_clock(targets)
        |> Map.put(:auto_tick, %{
          enabled: true,
          interval_ms: interval_ms,
          target: auto_tick_target_label(targets),
          targets: Enum.map(targets, &source_root_for_target/1),
          subscriptions: subscriptions,
          count: count,
          worker_pid: worker
        })
    end
  end

  @spec auto_fire_worker_interval_ms(map(), [:watch | :companion | :phone], [map()]) ::
          pos_integer()
  defp auto_fire_worker_interval_ms(state, targets, subscriptions)
       when is_map(state) and is_list(targets) and is_list(subscriptions) do
    targets
    |> Enum.flat_map(&trigger_candidates_for_surface(state, &1))
    |> Enum.filter(&auto_fire_row_selected?(&1, subscriptions))
    |> Enum.map(&(Map.get(&1, :interval_ms) || Map.get(&1, "interval_ms")))
    |> Enum.filter(&is_integer/1)
    |> case do
      [] -> @default_auto_fire_interval_ms
      intervals -> intervals |> Enum.min() |> clamp_auto_fire_interval_ms()
    end
  end

  defp auto_fire_worker_interval_ms(_state, _targets, _subscriptions),
    do: @default_auto_fire_interval_ms

  @spec auto_fire_row_selected?(map(), [map()]) :: boolean()
  defp auto_fire_row_selected?(row, subscriptions) when is_map(row) and is_list(subscriptions) do
    row_target = Map.get(row, :target) || Map.get(row, "target")
    row_trigger = Map.get(row, :trigger) || Map.get(row, "trigger")

    Enum.any?(subscriptions, fn sub ->
      sub_target = Map.get(sub, "target") || Map.get(sub, :target)
      sub_trigger = Map.get(sub, "trigger") || Map.get(sub, :trigger)

      sub_target == row_target and (sub_trigger == "*" or sub_trigger == row_trigger)
    end)
  end

  defp auto_fire_row_selected?(_row, _subscriptions), do: false

  @spec initialize_auto_fire_clock(map(), [:watch | :companion | :phone]) :: map()
  defp initialize_auto_fire_clock(state, targets) when is_map(state) and is_list(targets) do
    now = NaiveDateTime.local_now()
    Enum.reduce(targets, state, &put_auto_fire_clock(&2, &1, now))
  end

  @spec auto_tick_targets(term()) :: [:watch | :companion | :phone]
  defp auto_tick_targets(state) when is_map(state) do
    auto_tick = Map.get(state, :auto_tick, %{})

    auto_tick
    |> Map.get(:targets, [])
    |> Enum.map(&normalize_step_target/1)
    |> Enum.filter(&(&1 in [:watch, :companion]))
    |> Enum.uniq()
  end

  defp auto_tick_targets(_state), do: []

  defp auto_tick_subscriptions(state) when is_map(state) do
    auto_tick = Map.get(state, :auto_tick, %{})

    case Map.get(auto_tick, :subscriptions) do
      xs when is_list(xs) ->
        Enum.filter(xs, &valid_auto_fire_subscription?/1)

      _ ->
        auto_tick_targets(state)
        |> Enum.map(&%{"target" => source_root_for_target(&1), "trigger" => "*"})
    end
  end

  defp auto_tick_subscriptions(_state), do: []

  defp valid_auto_fire_subscription?(%{"target" => target, "trigger" => trigger})
       when target in ["watch", "protocol"] and is_binary(trigger) and trigger != "",
       do: true

  defp valid_auto_fire_subscription?(_), do: false

  defp disabled_subscriptions(state) when is_map(state) do
    case Map.get(state, :disabled_subscriptions) || Map.get(state, "disabled_subscriptions") do
      xs when is_list(xs) -> Enum.filter(xs, &valid_disabled_subscription?/1)
      _ -> []
    end
  end

  defp disabled_subscriptions(_state), do: []

  defp valid_disabled_subscription?(%{"target" => target, "trigger" => trigger})
       when target in ["watch", "protocol"] and is_binary(trigger) and trigger != "",
       do: true

  defp valid_disabled_subscription?(_), do: false

  defp update_disabled_subscription(disabled_subscriptions, target, trigger, enabled?)
       when is_list(disabled_subscriptions) do
    source_root = source_root_for_target(target)
    trigger = String.trim(to_string(trigger))

    disabled_subscriptions =
      Enum.reject(disabled_subscriptions, fn row ->
        Map.get(row, "target") == source_root and Map.get(row, "trigger") == trigger
      end)

    if enabled? do
      disabled_subscriptions
    else
      [%{"target" => source_root, "trigger" => trigger} | disabled_subscriptions]
    end
    |> Enum.filter(&valid_disabled_subscription?/1)
    |> Enum.uniq_by(&{Map.get(&1, "target"), Map.get(&1, "trigger")})
    |> Enum.sort_by(&{Map.get(&1, "target"), Map.get(&1, "trigger")})
  end

  defp update_auto_fire_subscriptions(subscriptions, target, trigger, enabled?)
       when is_list(subscriptions) do
    source_root = source_root_for_target(target)
    trigger = String.trim(to_string(trigger))

    subscriptions =
      Enum.reject(subscriptions, fn row ->
        Map.get(row, "target") == source_root and Map.get(row, "trigger") == trigger
      end)

    if enabled? do
      [%{"target" => source_root, "trigger" => trigger} | subscriptions]
    else
      subscriptions
    end
    |> Enum.filter(&valid_auto_fire_subscription?/1)
    |> Enum.uniq_by(&{Map.get(&1, "target"), Map.get(&1, "trigger")})
    |> Enum.sort_by(&{Map.get(&1, "target"), Map.get(&1, "trigger")})
  end

  defp auto_fire_targets_from_subscriptions(subscriptions) when is_list(subscriptions) do
    subscriptions
    |> Enum.map(&(Map.get(&1, "target") || Map.get(&1, :target)))
    |> Enum.map(&normalize_step_target/1)
    |> Enum.filter(&(&1 in [:watch, :companion]))
    |> Enum.uniq()
  end

  defp auto_fire_subscription_enabled?(state, target, row) when is_map(state) and is_map(row) do
    subscriptions = auto_tick_subscriptions(state)
    source_root = source_root_for_target(target)
    trigger = Map.get(row, :trigger) || Map.get(row, "trigger")

    Enum.any?(subscriptions, fn sub ->
      Map.get(sub, "target") == source_root and
        (Map.get(sub, "trigger") == "*" or Map.get(sub, "trigger") == trigger)
    end)
  end

  defp subscription_trigger_enabled?(state, target, row) when is_map(state) and is_map(row) do
    trigger = Map.get(row, :trigger) || Map.get(row, "trigger")
    not subscription_trigger_disabled?(state, target, trigger)
  end

  defp subscription_trigger_enabled?(_state, _target, _row), do: true

  defp subscription_trigger_disabled?(state, target, trigger)
       when is_map(state) and is_binary(trigger) do
    source_root = source_root_for_target(target)

    Enum.any?(disabled_subscriptions(state), fn row ->
      Map.get(row, "target") == source_root and Map.get(row, "trigger") == trigger
    end)
  end

  defp subscription_trigger_disabled?(_state, _target, _trigger), do: false

  @spec update_auto_fire_targets(
          [:watch | :companion | :phone],
          :watch | :companion | :phone,
          boolean()
        ) ::
          [:watch | :companion | :phone]
  defp update_auto_fire_targets(targets, target, enabled?) when is_list(targets) do
    targets =
      if enabled? do
        [target | targets]
      else
        Enum.reject(targets, &(&1 == target))
      end

    targets
    |> Enum.filter(&(&1 in [:watch, :companion]))
    |> Enum.uniq()
    |> Enum.sort_by(fn
      :watch -> 0
      :companion -> 1
      :phone -> 2
    end)
  end

  @spec auto_tick_target_label([:watch | :companion | :phone]) :: String.t()
  defp auto_tick_target_label([single]), do: source_root_for_target(single)
  defp auto_tick_target_label(_targets), do: "selected"

  @spec stop_auto_tick_worker(term()) :: map()
  defp stop_auto_tick_worker(state) when is_map(state) do
    auto_tick = Map.get(state, :auto_tick, %{})
    worker = Map.get(auto_tick, :worker_pid)

    if is_pid(worker) and Process.alive?(worker) do
      send(worker, :stop)
    end

    Map.put(state, :auto_tick, default_auto_tick())
  end

  @spec resolve_step_message(term(), term()) ::
          {String.t(), String.t(), [String.t()], [String.t()], non_neg_integer()}
  defp resolve_step_message(model, requested_message) when is_map(model) do
    ei = Map.get(model, "elm_introspect")
    msg_constructors = introspect_list(ei, "msg_constructors")
    update_branches = introspect_list(ei, "update_case_branches")

    known_messages =
      if msg_constructors != [] do
        msg_constructors
      else
        update_branches
      end

    cursor = integer_or_zero(Map.get(model, "runtime_message_cursor"))

    cond do
      is_binary(requested_message) and String.trim(requested_message) != "" ->
        message = canonicalize_known_message(String.trim(requested_message), known_messages)
        {message, "provided", known_messages, update_branches, cursor + 1}

      known_messages != [] ->
        idx = rem(cursor, length(known_messages))
        message = Enum.at(known_messages, idx) || "Tick"
        {message, "auto_cycle", known_messages, update_branches, cursor + 1}

      true ->
        {"Tick", "default", [], update_branches, cursor + 1}
    end
  end

  @spec canonicalize_known_message(term(), term()) :: String.t()
  defp canonicalize_known_message(message, known_messages) when is_binary(message) do
    needle = String.downcase(message)

    Enum.find(known_messages, message, fn known ->
      is_binary(known) and String.downcase(known) == needle
    end)
  end

  @spec step_runtime_result(term(), term(), term(), term(), term(), term()) :: term()
  defp step_runtime_result(model, view_tree, target, message, message_value, update_branches)
       when is_map(model) and target in [:watch, :companion, :phone] and is_binary(message) do
    introspect = Map.get(model, "elm_introspect")
    introspect = if is_map(introspect), do: introspect, else: %{}

    request =
      %{
        source_root: source_root_for_target(target),
        rel_path: Map.get(model, "last_path"),
        source: Map.get(model, "last_source") || "",
        introspect: introspect,
        current_model: model,
        current_view_tree: view_tree,
        message: message,
        message_value: message_value,
        update_branches: update_branches
      }
      |> Map.merge(runtime_execution_artifacts(model))

    case runtime_executor_module().execute(request) do
      {:ok, %{model_patch: patch} = result} when is_map(patch) ->
        if is_map(Map.get(patch, "runtime_model")) do
          %{
            model_patch: patch,
            view_tree: Map.get(result, :view_tree),
            view_output:
              normalize_view_output(
                Map.get(result, :view_output) || Map.get(patch, "runtime_view_output")
              ),
            protocol_events: normalize_protocol_events(Map.get(result, :protocol_events)),
            followup_messages: normalize_followup_messages(Map.get(result, :followup_messages))
          }
        else
          local_step_runtime_result(model, view_tree, target, message, update_branches)
        end

      _ ->
        local_step_runtime_result(model, view_tree, target, message, update_branches)
    end
  end

  @spec local_step_runtime_result(term(), term(), term(), term(), term()) :: term()
  defp local_step_runtime_result(model, view_tree, _target, message, update_branches) do
    runtime_model = Map.get(model, "runtime_model")
    runtime_model = if is_map(runtime_model), do: runtime_model, else: %{}
    updated_runtime_model = mutate_runtime_model(runtime_model, message, update_branches)

    %{
      model_patch:
        model
        |> Map.put("runtime_model", updated_runtime_model)
        |> refresh_runtime_fingerprints(updated_runtime_model, view_tree)
        |> Map.take([
          "runtime_model",
          "runtime_model_source",
          "runtime_model_sha256",
          "runtime_view_tree_sha256",
          "elm_executor_mode",
          "elm_executor"
        ]),
      view_tree: view_tree,
      view_output: [],
      protocol_events: [],
      followup_messages: []
    }
  end

  @spec normalize_protocol_events(term()) :: [term()]
  defp normalize_protocol_events(value) when is_list(value), do: value
  defp normalize_protocol_events(_), do: []

  @spec normalize_followup_messages(term()) :: [term()]
  defp normalize_followup_messages(value) when is_list(value), do: value
  defp normalize_followup_messages(_), do: []

  @spec normalize_view_output(term()) :: [term()]
  defp normalize_view_output(value) when is_list(value), do: value
  defp normalize_view_output(_), do: []

  @spec put_runtime_view_output(map(), term()) :: map()
  defp put_runtime_view_output(model, view_output) when is_map(model) do
    case normalize_view_output(view_output) do
      [] -> model
      rows -> Map.put(model, "runtime_view_output", rows)
    end
  end

  @spec preferred_runtime_view_output(term(), term()) :: [term()]
  defp preferred_runtime_view_output(primary, fallback) do
    case normalize_view_output(primary) do
      [] -> normalize_view_output(fallback)
      rows -> rows
    end
  end

  @spec render_view_after_update(term(), term(), term(), term(), term(), term()) :: term()
  defp render_view_after_update(
         runtime_view_tree,
         previous_view_tree,
         target,
         message,
         trigger,
         model
       )
       when target in [:watch, :companion, :phone] and is_binary(message) and is_binary(trigger) and
              is_map(model) do
    output_view_tree = runtime_view_output_tree(model, target)

    base =
      cond do
        is_map(output_view_tree) ->
          output_view_tree

        is_map(runtime_view_tree) and map_size(runtime_view_tree) > 0 ->
          runtime_view_tree

        is_map(previous_view_tree) and map_size(previous_view_tree) > 0 ->
          previous_view_tree

        true ->
          default_view_tree_for_target(target)
      end

    children =
      case Map.get(base, "children") || Map.get(base, :children) do
        xs when is_list(xs) -> xs
        _ -> []
      end

    render_marker = %{
      "type" => "debuggerRenderStep",
      "label" => "#{source_root_for_target(target)}:#{message}",
      "trigger" => trigger,
      "model_entries" => map_size(model),
      "children" => []
    }

    base
    |> Map.put("children", [render_marker | children] |> Enum.take(24))
    |> Map.put("last_runtime_step_message", message)
    |> Map.put("last_runtime_trigger", trigger)
  end

  defp render_view_after_update(
         _runtime_view_tree,
         previous_view_tree,
         target,
         _message,
         _trigger,
         _model
       )
       when target in [:watch, :companion, :phone] do
    if is_map(previous_view_tree) and map_size(previous_view_tree) > 0,
      do: previous_view_tree,
      else: default_view_tree_for_target(target)
  end

  @spec runtime_view_output_tree(term(), term()) :: map() | nil
  defp runtime_view_output_tree(model, target)
       when is_map(model) and target in [:watch, :companion, :phone] do
    case normalize_view_output(
           Map.get(model, "runtime_view_output") || Map.get(model, :runtime_view_output)
         ) do
      [] ->
        nil

      ops ->
        {screen_w, screen_h} = runtime_view_output_screen(model)
        op_nodes = runtime_view_output_nodes(ops)

        %{
          "type" => "windowStack",
          "label" => "",
          "box" => %{"x" => 0, "y" => 0, "w" => screen_w, "h" => screen_h},
          "children" => [
            %{
              "type" => "window",
              "label" => "",
              "id" => 1,
              "children" => [
                %{
                  "type" => "canvasLayer",
                  "label" => "",
                  "id" => 1,
                  "children" => op_nodes
                }
              ]
            }
          ]
        }
    end
  end

  defp runtime_view_output_tree(_model, _target), do: nil

  @spec runtime_view_output_screen(map()) :: {pos_integer(), pos_integer()}
  defp runtime_view_output_screen(model) when is_map(model) do
    runtime_model =
      case Map.get(model, "runtime_model") || Map.get(model, :runtime_model) do
        %{} = value -> value
        _ -> model
      end

    {
      positive_integer_value(
        Map.get(runtime_model, "screenW") || Map.get(runtime_model, :screenW),
        144
      ),
      positive_integer_value(
        Map.get(runtime_model, "screenH") || Map.get(runtime_model, :screenH),
        168
      )
    }
  end

  @spec positive_integer_value(term(), pos_integer()) :: pos_integer()
  defp positive_integer_value(value, _fallback) when is_integer(value) and value > 0, do: value

  defp positive_integer_value(value, _fallback) when is_float(value) and value > 0,
    do: trunc(value)

  defp positive_integer_value(value, fallback) when is_binary(value) do
    case Integer.parse(value) do
      {parsed, ""} when parsed > 0 -> parsed
      _ -> fallback
    end
  end

  defp positive_integer_value(_value, fallback), do: fallback

  @spec runtime_view_output_nodes([term()]) :: [map()]
  defp runtime_view_output_nodes(ops) when is_list(ops) do
    {nodes, _rest} = runtime_view_output_nodes_until(ops, false)
    nodes
  end

  @spec runtime_view_output_nodes_until([term()], boolean()) :: {[map()], [term()]}
  defp runtime_view_output_nodes_until(rows, stop_on_pop?) when is_list(rows) do
    runtime_view_output_nodes_until(rows, stop_on_pop?, [])
  end

  defp runtime_view_output_nodes_until([], _stop_on_pop?, acc), do: {Enum.reverse(acc), []}

  defp runtime_view_output_nodes_until([row | rest], stop_on_pop?, acc) when is_map(row) do
    case runtime_view_output_kind(row) do
      "pop_context" when stop_on_pop? ->
        {Enum.reverse(acc), rest}

      "pop_context" ->
        runtime_view_output_nodes_until(rest, stop_on_pop?, acc)

      "push_context" ->
        {group_nodes, remaining} = runtime_view_output_nodes_until(rest, true)
        {style, children} = split_runtime_view_output_group(group_nodes)

        group =
          %{"type" => "group", "label" => "", "children" => children}
          |> maybe_put_group_style(style)

        runtime_view_output_nodes_until(remaining, stop_on_pop?, [group | acc])

      kind when kind in ["stroke_color", "fill_color", "text_color"] ->
        runtime_view_output_nodes_until(rest, stop_on_pop?, [
          runtime_view_output_style_node(row) | acc
        ])

      _ ->
        case runtime_view_output_node(row) do
          %{} = node -> runtime_view_output_nodes_until(rest, stop_on_pop?, [node | acc])
          nil -> runtime_view_output_nodes_until(rest, stop_on_pop?, acc)
        end
    end
  end

  defp runtime_view_output_nodes_until([_row | rest], stop_on_pop?, acc),
    do: runtime_view_output_nodes_until(rest, stop_on_pop?, acc)

  @spec split_runtime_view_output_group([map()]) :: {map(), [map()]}
  defp split_runtime_view_output_group(nodes) when is_list(nodes) do
    Enum.reduce(nodes, {%{}, []}, fn node, {style, children} ->
      case Map.get(node, "type") do
        "style" ->
          {Map.put(style, Map.get(node, "key"), Map.get(node, "value")), children}

        _ ->
          {style, [node | children]}
      end
    end)
    |> then(fn {style, children} -> {style, Enum.reverse(children)} end)
  end

  @spec maybe_put_group_style(map(), map()) :: map()
  defp maybe_put_group_style(group, style) when is_map(group) and map_size(style) > 0,
    do: Map.put(group, "style", style)

  defp maybe_put_group_style(group, _style), do: group

  @spec runtime_view_output_style_node(map()) :: map()
  defp runtime_view_output_style_node(row) when is_map(row) do
    kind = runtime_view_output_kind(row)

    %{
      "type" => "style",
      "key" => kind,
      "value" => map_value(row, "color") || map_value(row, "value")
    }
  end

  @spec runtime_view_output_node(map()) :: map() | nil
  defp runtime_view_output_node(row) when is_map(row) do
    case runtime_view_output_kind(row) do
      "clear" ->
        %{
          "type" => "clear",
          "label" => "",
          "children" => [],
          "color" => integer_or_zero(map_value(row, "color"))
        }

      "round_rect" ->
        %{
          "type" => "roundRect",
          "label" => "",
          "children" => [],
          "x" => integer_or_zero(map_value(row, "x")),
          "y" => integer_or_zero(map_value(row, "y")),
          "w" => integer_or_zero(map_value(row, "w")),
          "h" => integer_or_zero(map_value(row, "h")),
          "radius" => integer_or_zero(map_value(row, "radius")),
          "fill" => integer_or_zero(map_value(row, "fill"))
        }

      "fill_rect" ->
        %{
          "type" => "fillRect",
          "label" => "",
          "children" => [],
          "x" => integer_or_zero(map_value(row, "x")),
          "y" => integer_or_zero(map_value(row, "y")),
          "w" => integer_or_zero(map_value(row, "w")),
          "h" => integer_or_zero(map_value(row, "h")),
          "fill" => integer_or_zero(map_value(row, "fill"))
        }

      "line" ->
        %{
          "type" => "line",
          "label" => "",
          "children" => [],
          "x1" => integer_or_zero(map_value(row, "x1")),
          "y1" => integer_or_zero(map_value(row, "y1")),
          "x2" => integer_or_zero(map_value(row, "x2")),
          "y2" => integer_or_zero(map_value(row, "y2")),
          "color" => integer_or_zero(map_value(row, "color"))
        }

      "circle" ->
        %{
          "type" => "circle",
          "label" => "",
          "children" => [],
          "cx" => integer_or_zero(map_value(row, "cx")),
          "cy" => integer_or_zero(map_value(row, "cy")),
          "r" => integer_or_zero(map_value(row, "r")),
          "color" => integer_or_zero(map_value(row, "color"))
        }

      "fill_circle" ->
        %{
          "type" => "fillCircle",
          "label" => "",
          "children" => [],
          "cx" => integer_or_zero(map_value(row, "cx")),
          "cy" => integer_or_zero(map_value(row, "cy")),
          "r" => integer_or_zero(map_value(row, "r")),
          "color" => integer_or_zero(map_value(row, "color"))
        }

      "pixel" ->
        %{
          "type" => "pixel",
          "label" => "",
          "children" => [],
          "x" => integer_or_zero(map_value(row, "x")),
          "y" => integer_or_zero(map_value(row, "y")),
          "color" => integer_or_zero(map_value(row, "color"))
        }

      "text" ->
        %{
          "type" => "text",
          "label" => "",
          "children" => [],
          "x" => integer_or_zero(map_value(row, "x")),
          "y" => integer_or_zero(map_value(row, "y")),
          "w" => integer_or_zero(map_value(row, "w")),
          "h" => integer_or_zero(map_value(row, "h")),
          "font_id" => integer_or_zero(map_value(row, "font_id")),
          "text" => to_string(map_value(row, "text") || "")
        }

      "text_label" ->
        %{
          "type" => "textLabel",
          "label" => "",
          "children" => [],
          "x" => integer_or_zero(map_value(row, "x")),
          "y" => integer_or_zero(map_value(row, "y")),
          "font_id" => integer_or_zero(map_value(row, "font_id")),
          "text" => to_string(map_value(row, "text") || "")
        }

      _ ->
        nil
    end
  end

  @spec runtime_view_output_kind(map()) :: String.t()
  defp runtime_view_output_kind(row) when is_map(row),
    do: to_string(map_value(row, "kind") || "")

  @spec default_view_tree_for_target(term()) :: map()
  defp default_view_tree_for_target(:watch), do: Map.get(default_watch_runtime(), :view_tree)

  defp default_view_tree_for_target(:companion),
    do: Map.get(default_companion_runtime(), :view_tree)

  defp default_view_tree_for_target(:phone), do: Map.get(default_phone_runtime(), :view_tree)

  @spec refresh_runtime_fingerprints(term(), term(), term()) :: map()
  defp refresh_runtime_fingerprints(model, runtime_model, view_tree)
       when is_map(model) and is_map(runtime_model) do
    runtime = Map.get(model, "elm_executor")
    runtime_mode = Map.get(model, "elm_executor_mode")
    runtime_model_source = Map.get(model, "runtime_model_source")
    runtime_view_tree_source = Map.get(model, "runtime_view_tree_source")

    if runtime_mode == "runtime_executed" or (is_map(runtime) and map_size(runtime) > 0) or
         map_size(runtime_model) > 0 do
      runtime = if is_map(runtime), do: runtime, else: %{}
      runtime_view_tree = if is_map(view_tree), do: view_tree, else: %{}

      runtime =
        runtime
        |> Map.put("runtime_model_entry_count", map_size(runtime_model))
        |> Map.put("view_tree_node_count", view_tree_node_count(runtime_view_tree))
        |> Map.put("runtime_model_sha256", stable_term_sha256(runtime_model))
        |> Map.put("view_tree_sha256", stable_term_sha256(runtime_view_tree))
        |> maybe_put_runtime_source("runtime_model_source", runtime_model_source)
        |> maybe_put_runtime_source("view_tree_source", runtime_view_tree_source)

      model
      |> Map.put("elm_executor", runtime)
      |> Map.put("runtime_model_sha256", runtime["runtime_model_sha256"])
      |> Map.put("runtime_view_tree_sha256", runtime["view_tree_sha256"])
    else
      model
    end
  end

  @spec maybe_put_runtime_source(term(), term(), term()) :: map()
  defp maybe_put_runtime_source(runtime, _key, value) when not is_binary(value), do: runtime
  defp maybe_put_runtime_source(runtime, _key, value) when value == "", do: runtime
  defp maybe_put_runtime_source(runtime, key, value), do: Map.put(runtime, key, value)

  @spec mutate_runtime_model(term(), term(), term()) :: map()
  defp mutate_runtime_model(model, message, update_branches)
       when is_map(model) and is_binary(message) and is_list(update_branches) do
    op = step_operation_for_message(message, update_branches)

    {updated, changed?} =
      Enum.reduce(model, {%{}, false}, fn {key, value}, {acc, changed?} ->
        cond do
          is_integer(value) and op == :inc ->
            {Map.put(acc, key, value + 1), true}

          is_integer(value) and op == :dec ->
            {Map.put(acc, key, value - 1), true}

          is_integer(value) and op == :reset ->
            {Map.put(acc, key, 0), true}

          is_boolean(value) and op == :toggle ->
            {Map.put(acc, key, !value), true}

          is_boolean(value) and op == :enable ->
            {Map.put(acc, key, true), true}

          is_boolean(value) and op == :disable ->
            {Map.put(acc, key, false), true}

          is_boolean(value) and op == :reset ->
            {Map.put(acc, key, false), true}

          true ->
            {Map.put(acc, key, value), changed?}
        end
      end)

    base =
      if changed? do
        updated
      else
        Map.put(model, "step_counter", Map.get(model, "step_counter", 0) + 1)
      end

    base
    |> Map.put("last_message", message)
    |> Map.put("last_operation", Atom.to_string(op))
  end

  @spec parse_step_count(term()) :: pos_integer()
  defp parse_step_count(value) when is_integer(value) and value >= 1, do: min(value, 50)

  defp parse_step_count(value) when is_binary(value) do
    case Integer.parse(value) do
      {parsed, _} when parsed >= 1 -> min(parsed, 50)
      _ -> 1
    end
  end

  defp parse_step_count(_), do: 1

  @spec parse_optional_step_cursor_seq(term()) :: non_neg_integer() | nil
  defp parse_optional_step_cursor_seq(value) when is_integer(value) and value >= 0, do: value

  defp parse_optional_step_cursor_seq(value) when is_binary(value) do
    case Integer.parse(value) do
      {n, _} when n >= 0 -> n
      _ -> nil
    end
  end

  defp parse_optional_step_cursor_seq(_), do: nil

  @spec parse_replay_mode(term()) :: String.t()
  defp parse_replay_mode("live"), do: "live"
  defp parse_replay_mode("frozen"), do: "frozen"
  defp parse_replay_mode(_), do: "unknown"

  @spec view_tree_node_count(term()) :: non_neg_integer()
  defp view_tree_node_count(%{"children" => children}) when is_list(children) do
    1 +
      Enum.reduce(children, 0, fn child, acc ->
        if is_map(child), do: acc + view_tree_node_count(child), else: acc
      end)
  end

  defp view_tree_node_count(%{children: children}) when is_list(children) do
    1 +
      Enum.reduce(children, 0, fn child, acc ->
        if is_map(child), do: acc + view_tree_node_count(child), else: acc
      end)
  end

  defp view_tree_node_count(%{}), do: 1
  defp view_tree_node_count(_), do: 0

  @spec stable_term_sha256(term()) :: String.t()
  defp stable_term_sha256(term) do
    :crypto.hash(:sha256, :erlang.term_to_binary(term))
    |> Base.encode16(case: :lower)
  end

  @spec replay_telemetry_payload(term(), term(), term(), term(), term(), term()) :: map()
  defp replay_telemetry_payload(mode, source, drift_seq, target, requested_count, replayed_count) do
    %{
      mode: mode,
      source: source,
      drift_seq: drift_seq || 0,
      drift_band: replay_drift_band(drift_seq),
      target_scope: replay_target_label(target),
      requested_count: requested_count,
      replayed_count: replayed_count,
      used_frozen_preview: source == "frozen_preview",
      used_live_query: source == "recent_query"
    }
  end

  @spec replay_drift_band(term()) :: String.t()
  defp replay_drift_band(nil), do: "none"
  defp replay_drift_band(drift) when is_integer(drift) and drift <= 0, do: "none"
  defp replay_drift_band(drift) when is_integer(drift) and drift <= 3, do: "mild"
  defp replay_drift_band(drift) when is_integer(drift) and drift <= 10, do: "medium"
  defp replay_drift_band(drift) when is_integer(drift), do: "high"

  @spec normalize_replay_rows_input(term()) :: [map()]
  defp normalize_replay_rows_input(rows) when is_list(rows) do
    rows
    |> Enum.filter(&is_map/1)
    |> Enum.map(fn row ->
      seq = Map.get(row, :seq) || Map.get(row, "seq") || 0
      target = Map.get(row, :target) || Map.get(row, "target")
      message = Map.get(row, :message) || Map.get(row, "message")

      %{
        seq: if(is_integer(seq), do: seq, else: 0),
        target: normalize_step_target(target),
        message: if(is_binary(message) and message != "", do: message, else: "Tick")
      }
    end)
  end

  defp normalize_replay_rows_input(_), do: []

  @spec recent_replay_messages(term(), term(), term(), term()) :: [map()]
  defp recent_replay_messages(state, target, count, cursor_seq)
       when is_map(state) and is_integer(count) do
    state
    |> Map.get(:events, [])
    |> maybe_filter_events_at_or_before_seq(cursor_seq)
    |> Enum.filter(fn event ->
      event.type == "debugger.update_in" and is_map(event.payload)
    end)
    |> Enum.map(fn event ->
      payload = event.payload
      payload_target = Map.get(payload, :target) || Map.get(payload, "target")
      payload_message = Map.get(payload, :message) || Map.get(payload, "message")

      %{
        seq: event.seq,
        target: normalize_step_target(payload_target),
        message:
          if(is_binary(payload_message) and payload_message != "",
            do: payload_message,
            else: "Tick"
          )
      }
    end)
    |> Enum.filter(fn %{target: replay_target} ->
      is_nil(target) or replay_target == target
    end)
    |> Enum.take(count)
    |> Enum.reverse()
  end

  @spec replay_target_label(term()) :: String.t()
  defp replay_target_label(nil), do: "all"
  defp replay_target_label(target), do: source_root_for_target(target)

  @spec maybe_put_replay_cursor_seq(term(), term()) :: map()
  defp maybe_put_replay_cursor_seq(payload, nil), do: payload

  defp maybe_put_replay_cursor_seq(payload, cursor_seq),
    do: Map.put(payload, :cursor_seq, cursor_seq)

  @spec replay_summary_payload(term()) :: map()
  defp replay_summary_payload(messages) when is_list(messages) do
    target_counts =
      messages
      |> Enum.reduce(%{}, fn %{target: target}, acc ->
        key = replay_target_label(target)
        Map.update(acc, key, 1, &(&1 + 1))
      end)

    message_counts =
      messages
      |> Enum.reduce(%{}, fn %{message: message}, acc ->
        Map.update(acc, message, 1, &(&1 + 1))
      end)

    preview =
      messages
      |> Enum.take(8)
      |> Enum.map(fn %{seq: seq, target: target, message: message} ->
        %{seq: seq, target: replay_target_label(target), message: message}
      end)

    %{
      replay_target_counts: target_counts,
      replay_message_counts: message_counts,
      replay_preview: preview
    }
  end

  @spec maybe_filter_events_at_or_before_seq(term(), term()) :: term()
  defp maybe_filter_events_at_or_before_seq(events, nil) when is_list(events), do: events

  defp maybe_filter_events_at_or_before_seq(events, cursor_seq)
       when is_list(events) and is_integer(cursor_seq) and cursor_seq >= 0 do
    Enum.filter(events, &(&1.seq <= cursor_seq))
  end

  @spec introspect_list(term(), term()) :: [String.t()]
  defp introspect_list(ei, key) when is_map(ei) and is_binary(key) do
    case Map.get(ei, key) do
      xs when is_list(xs) ->
        xs
        |> Enum.filter(&is_binary/1)
        |> Enum.map(&String.trim/1)
        |> Enum.reject(&(&1 == ""))
        |> Enum.uniq()

      _ ->
        []
    end
  end

  defp introspect_list(_, _), do: []

  @spec introspect_cmd_calls(term(), term()) :: [String.t()]
  defp introspect_cmd_calls(ei, key) when is_map(ei) and is_binary(key) do
    case Map.get(ei, key) do
      rows when is_list(rows) ->
        rows
        |> Enum.filter(&is_map/1)
        |> Enum.map(fn row ->
          %{
            "target" => Map.get(row, "target") || Map.get(row, :target),
            "name" => Map.get(row, "name") || Map.get(row, :name),
            "callback_constructor" =>
              Map.get(row, "callback_constructor") || Map.get(row, :callback_constructor),
            "branch" => Map.get(row, "branch") || Map.get(row, :branch),
            "branch_constructor" =>
              Map.get(row, "branch_constructor") || Map.get(row, :branch_constructor),
            "event_kind" => Map.get(row, "event_kind") || Map.get(row, :event_kind),
            "label" => Map.get(row, "label") || Map.get(row, :label),
            "arg_snippets" => Map.get(row, "arg_snippets") || Map.get(row, :arg_snippets) || [],
            "arg_kinds" => Map.get(row, "arg_kinds") || Map.get(row, :arg_kinds) || []
          }
        end)
        |> Enum.filter(fn row ->
          is_binary(row["name"]) and row["name"] != ""
        end)

      _ ->
        []
    end
  end

  defp introspect_cmd_calls(_, _), do: []

  @spec integer_or_zero(term()) :: integer()
  defp integer_or_zero(value) when is_integer(value) and value >= 0, do: value

  defp integer_or_zero(value) when is_binary(value) do
    case Integer.parse(value) do
      {n, _} when n >= 0 -> n
      _ -> 0
    end
  end

  defp integer_or_zero(_), do: 0

  @spec step_operation_for_message(term(), term()) :: atom()
  defp step_operation_for_message(message, update_branches)
       when is_binary(message) and is_list(update_branches) do
    case operation_from_text(message) do
      :tick ->
        update_branches
        |> Enum.filter(&is_binary/1)
        |> Enum.map(&operation_from_text/1)
        |> Enum.find(:tick, &(&1 != :tick))

      op ->
        op
    end
  end

  @spec contains_any?(term(), term()) :: boolean()
  defp contains_any?(text, needles) when is_binary(text) and is_list(needles) do
    Enum.any?(needles, fn needle -> String.contains?(text, needle) end)
  end

  @spec operation_from_text(term()) :: atom()
  defp operation_from_text(text) when is_binary(text) do
    hint = String.downcase(text)

    cond do
      contains_any?(hint, ["inc", "increment", "up", "next", "plus", "add"]) -> :inc
      contains_any?(hint, ["dec", "decrement", "down", "prev", "minus", "sub"]) -> :dec
      contains_any?(hint, ["toggle", "flip", "switch"]) -> :toggle
      contains_any?(hint, ["enable", "enabled", "on", "open", "start"]) -> :enable
      contains_any?(hint, ["disable", "disabled", "off", "close", "stop"]) -> :disable
      contains_any?(hint, ["reset", "clear"]) -> :reset
      true -> :tick
    end
  end

  @spec filter_events_by_types(runtime_state(), [String.t()] | term()) :: runtime_state()
  defp filter_events_by_types(state, nil), do: state
  defp filter_events_by_types(state, []), do: state

  defp filter_events_by_types(state, types) when is_list(types) do
    allowed = MapSet.new(types)
    %{state | events: Enum.filter(state.events, &MapSet.member?(allowed, &1.type))}
  end

  defp filter_events_by_types(state, _types), do: state

  @spec filter_events_since_seq(runtime_state(), non_neg_integer() | term()) :: runtime_state()
  defp filter_events_since_seq(state, nil), do: state

  defp filter_events_since_seq(state, since_seq) when is_integer(since_seq) and since_seq >= 0 do
    %{state | events: Enum.filter(state.events, &(&1.seq > since_seq))}
  end

  defp filter_events_since_seq(state, _since_seq), do: state

  @spec default_state(String.t()) :: runtime_state()
  defp default_state(project_slug) do
    watch_profile_id =
      persisted_project_watch_profile_id(project_slug) || default_watch_profile_id()

    launch_context = launch_context_for(watch_profile_id, "LaunchUser")

    %{
      running: false,
      revision: nil,
      watch_profile_id: watch_profile_id,
      launch_context: launch_context,
      watch: default_watch_runtime(launch_context),
      companion: default_companion_runtime(),
      phone: default_phone_runtime(),
      storage: %{},
      auto_tick: default_auto_tick(),
      disabled_subscriptions: [],
      events: [],
      debugger_timeline: [],
      debugger_seq: 0,
      seq: 0
    }
  end

  @spec persisted_project_watch_profile_id(term()) :: String.t() | nil
  defp persisted_project_watch_profile_id(project_slug) when is_binary(project_slug) do
    try do
      with %{debugger_settings: settings} when is_map(settings) <-
             Projects.get_project_by_slug(project_slug),
           profile_id when is_binary(profile_id) <- Map.get(settings, "watch_profile_id") do
        parse_optional_watch_profile_id(profile_id)
      else
        _ -> nil
      end
    rescue
      DBConnection.OwnershipError ->
        nil

      error in RuntimeError ->
        if String.contains?(Exception.message(error), "could not lookup Ecto repo") do
          nil
        else
          reraise(error, __STACKTRACE__)
        end
    end
  end

  defp persisted_project_watch_profile_id(_project_slug), do: nil

  @spec default_auto_tick() :: map()
  defp default_auto_tick do
    %{enabled: false, interval_ms: nil, target: "all", targets: [], count: 1, worker_pid: nil}
  end

  @spec default_watch_runtime(map() | nil) :: map()
  defp default_watch_runtime(launch_context \\ nil) do
    launch_context =
      if is_map(launch_context),
        do: launch_context,
        else: launch_context_for(default_watch_profile_id(), "LaunchUser")

    %{
      model: %{
        "status" => "idle",
        "launch_context" => launch_context
      },
      last_message: nil,
      protocol_messages: [],
      view_tree: %{"type" => "root", "children" => []}
    }
  end

  @spec default_companion_runtime() :: map()
  defp default_companion_runtime do
    %{
      model: protocol_surface_model("idle"),
      last_message: nil,
      protocol_messages: [],
      view_tree: %{
        "type" => "CompanionRoot",
        "label" => "idle",
        "box" => %{"x" => 0, "y" => 0, "w" => 180, "h" => 320},
        "children" => []
      }
    }
  end

  @spec attach_companion_configuration(map(), String.t()) :: map()
  defp attach_companion_configuration(state, project_slug)
       when is_map(state) and is_binary(project_slug) do
    case companion_configuration_model(project_slug) do
      nil ->
        update_in(state, [:companion, :model], &drop_companion_configuration/1)

      configuration ->
        configuration =
          put_configuration_values(
            configuration,
            get_in(state, [:companion, :model, "configuration", "values"])
          )

        state
        |> put_in([:companion, :model, "configuration"], configuration)
        |> put_in([:companion, :model, "runtime_model", "configuration"], configuration)
    end
  end

  defp attach_companion_configuration(state, _project_slug), do: state

  @spec companion_configuration_model(String.t()) :: map() | nil
  defp companion_configuration_model(project_slug) do
    try do
      with %{} = project <- Projects.get_project_by_slug(project_slug),
           workspace_root <- Projects.project_workspace_path(project),
           phone_root <- Path.join(workspace_root, "phone"),
           true <- File.exists?(Path.join(phone_root, "elm.json")),
           {:ok, %{} = schema} <- PebblePreferences.extract(phone_root) do
        configuration = %{
          "title" => schema.title,
          "sections" => companion_configuration_sections(schema.sections)
        }

        put_configuration_values(configuration, project_debugger_configuration_values(project))
      else
        _ -> nil
      end
    rescue
      DBConnection.OwnershipError ->
        nil

      error in RuntimeError ->
        if String.contains?(Exception.message(error), "could not lookup Ecto repo") do
          nil
        else
          reraise(error, __STACKTRACE__)
        end
    end
  end

  @spec project_debugger_configuration_values(term()) :: map() | nil
  defp project_debugger_configuration_values(%{debugger_settings: settings})
       when is_map(settings) do
    case Map.get(settings, "configuration_values") do
      values when is_map(values) -> values
      _ -> nil
    end
  end

  defp project_debugger_configuration_values(_project), do: nil

  @spec companion_configuration_sections(term()) :: [map()]
  defp companion_configuration_sections(sections) when is_list(sections) do
    Enum.map(sections, fn section ->
      %{
        "title" => Map.get(section, :title) || Map.get(section, "title") || "",
        "fields" =>
          companion_configuration_fields(
            Map.get(section, :fields) || Map.get(section, "fields") || []
          )
      }
    end)
  end

  defp companion_configuration_sections(_sections), do: []

  @spec companion_configuration_fields(term()) :: [map()]
  defp companion_configuration_fields(fields) when is_list(fields) do
    Enum.map(fields, fn field ->
      %{
        "id" => Map.get(field, :id) || Map.get(field, "id") || "",
        "label" => Map.get(field, :label) || Map.get(field, "label") || "",
        "control" => stringify_keys(Map.get(field, :control) || Map.get(field, "control") || %{})
      }
    end)
  end

  defp companion_configuration_fields(_fields), do: []

  @spec stringify_keys(term()) :: term()
  defp stringify_keys(value) when is_map(value) do
    Map.new(value, fn {key, child_value} -> {to_string(key), stringify_keys(child_value)} end)
  end

  defp stringify_keys(value) when is_list(value), do: Enum.map(value, &stringify_keys/1)
  defp stringify_keys(value), do: value

  @spec put_companion_configuration_values(map(), map()) :: map()
  defp put_companion_configuration_values(state, values) when is_map(state) and is_map(values) do
    update_in(state, [:companion, :model], fn model ->
      model
      |> put_configuration_values_at(["configuration"], values)
      |> put_configuration_values_at(["runtime_model", "configuration"], values)
    end)
  end

  defp put_companion_configuration_values(state, _values), do: state

  @spec put_configuration_values_at(term(), [String.t()], map()) :: term()
  defp put_configuration_values_at(model, path, values) when is_map(model) and is_list(path) do
    case get_in(model, path) do
      %{} = configuration -> put_in(model, path, put_configuration_values(configuration, values))
      _ -> model
    end
  end

  defp put_configuration_values_at(model, _path, _values), do: model

  @spec put_configuration_values(map(), term()) :: map()
  defp put_configuration_values(configuration, values)
       when is_map(configuration) and is_map(values) do
    values = stringify_keys(values)

    configuration
    |> Map.put("values", values)
    |> update_configuration_field_values(values)
  end

  defp put_configuration_values(configuration, _values) when is_map(configuration),
    do: configuration

  @spec update_configuration_field_values(map(), map()) :: map()
  defp update_configuration_field_values(configuration, values)
       when is_map(configuration) and is_map(values) do
    update_in(configuration, ["sections"], fn
      sections when is_list(sections) ->
        Enum.map(sections, fn
          %{} = section ->
            update_in(section, ["fields"], fn
              fields when is_list(fields) ->
                Enum.map(fields, fn
                  %{"id" => id, "control" => %{} = control} = field when is_binary(id) ->
                    if Map.has_key?(values, id) do
                      put_in(field, ["control", "value"], Map.get(values, id))
                    else
                      Map.put(field, "control", Map.delete(control, "value"))
                    end

                  field ->
                    field
                end)

              fields ->
                fields
            end)

          section ->
            section
        end)

      sections ->
        sections
    end)
  end

  @spec encode_configuration_values(term(), map()) :: map()
  defp encode_configuration_values(configuration, values)
       when is_map(configuration) and is_map(values) do
    configuration
    |> configuration_fields()
    |> Enum.reduce(%{}, fn field, acc ->
      id = Map.get(field, "id")
      control = Map.get(field, "control", %{})

      if is_binary(id) and id != "" do
        Map.put(acc, id, encode_configuration_value(control, Map.get(values, id)))
      else
        acc
      end
    end)
  end

  defp encode_configuration_values(_configuration, values) when is_map(values), do: values

  @spec configuration_fields(term()) :: [map()]
  defp configuration_fields(configuration) when is_map(configuration) do
    configuration
    |> Map.get("sections", [])
    |> Enum.flat_map(fn
      %{"fields" => fields} when is_list(fields) -> fields
      %{fields: fields} when is_list(fields) -> fields
      _ -> []
    end)
  end

  defp configuration_fields(_configuration), do: []

  @spec encode_configuration_value(term(), term()) :: term()
  defp encode_configuration_value(%{"type" => "toggle"}, value),
    do: truthy_configuration_value?(value)

  defp encode_configuration_value(%{"type" => type}, value) when type in ["number", "slider"] do
    case value do
      n when is_number(n) ->
        n

      value when is_binary(value) ->
        case Float.parse(value) do
          {parsed, ""} -> parsed
          {parsed, _rest} -> parsed
          :error -> 0
        end

      _ ->
        0
    end
  end

  defp encode_configuration_value(_control, value), do: value

  @spec truthy_configuration_value?(term()) :: boolean()
  defp truthy_configuration_value?(value) when value in [true, "true", "True", "on", "1", 1],
    do: true

  defp truthy_configuration_value?(_value), do: false

  @spec apply_configuration_protocol_messages(map(), term(), map()) :: map()
  defp apply_configuration_protocol_messages(state, configuration, values)
       when is_map(state) and is_map(configuration) and is_map(values) do
    events =
      configuration
      |> configuration_fields()
      |> Enum.flat_map(&configuration_protocol_events(&1, values))

    state
    |> append_protocol_events(events)
    |> apply_protocol_state_effects(events)
  end

  defp apply_configuration_protocol_messages(state, _configuration, _values), do: state

  @spec configuration_protocol_events(map(), map()) :: [map()]
  defp configuration_protocol_events(field, values) when is_map(field) and is_map(values) do
    control = Map.get(field, "control", %{})
    constructor = Map.get(control, "send_to_watch")
    id = Map.get(field, "id")

    with true <- is_binary(constructor) and constructor != "",
         true <- is_binary(id) and id != "",
         value <- Map.get(values, id),
         {:ok, arg_label, arg_value} <- configuration_protocol_arg(control, value) do
      message = String.trim("#{constructor} #{arg_label}")

      protocol_tx_rx_events("companion", "watch", message, "configuration", %{
        "ctor" => constructor,
        "args" => [arg_value]
      })
    else
      _ -> []
    end
  end

  defp configuration_protocol_events(_field, _values), do: []

  @spec configuration_protocol_arg(map(), term()) :: {:ok, String.t(), term()} | :error
  defp configuration_protocol_arg(%{"type" => "toggle"}, value) do
    bool = truthy_configuration_value?(value)
    {:ok, if(bool, do: "True", else: "False"), bool}
  end

  defp configuration_protocol_arg(%{"type" => "choice", "options" => options}, value)
       when is_list(options) do
    case Enum.find(options, &(Map.get(&1, "value") == value)) do
      %{"constructor" => constructor} when is_binary(constructor) and constructor != "" ->
        {:ok, constructor, %{"ctor" => constructor, "args" => []}}

      _ ->
        :error
    end
  end

  defp configuration_protocol_arg(_control, _value), do: :error

  @spec drop_companion_configuration(term()) :: term()
  defp drop_companion_configuration(model) when is_map(model) do
    model
    |> Map.drop(["configuration", :configuration])
    |> update_in(["runtime_model"], fn
      %{} = runtime_model -> Map.drop(runtime_model, ["configuration", :configuration])
      other -> other
    end)
  end

  defp drop_companion_configuration(model), do: model

  @spec default_phone_runtime() :: map()
  defp default_phone_runtime do
    %{
      model: protocol_surface_model("idle"),
      last_message: nil,
      protocol_messages: [],
      view_tree: %{
        "type" => "PhoneRoot",
        "label" => "idle",
        "box" => %{"x" => 0, "y" => 0, "w" => 200, "h" => 360},
        "children" => []
      }
    }
  end

  @spec compute_revision(String.t() | nil, String.t()) :: String.t()
  defp compute_revision(rel_path, source) do
    payload = "#{rel_path || "<none>"}:#{byte_size(source)}:#{source}"

    :crypto.hash(:sha256, payload)
    |> Base.encode16(case: :lower)
    |> String.slice(0, 12)
  end

  @spec sample_companion_view_tree(String.t(), String.t()) :: map()
  defp sample_companion_view_tree(rel_path, revision) do
    path = rel_path
    rev = revision

    %{
      "type" => "CompanionRoot",
      "label" => "phone",
      "box" => %{"x" => 0, "y" => 0, "w" => 180, "h" => 320},
      "meta" => %{"revision" => rev},
      "children" => [
        %{
          "type" => "Status",
          "label" => path,
          "box" => %{"x" => 6, "y" => 8, "w" => 168, "h" => 22},
          "children" => []
        },
        %{
          "type" => "ProtocolLog",
          "label" => rev,
          "box" => %{"x" => 6, "y" => 36, "w" => 168, "h" => 220},
          "children" => []
        }
      ]
    }
  end

  @spec sample_view_tree(String.t() | nil, String.t()) :: map()
  defp sample_view_tree(rel_path, revision) do
    path = rel_path || "unknown"

    %{
      "type" => "Window",
      "label" => path,
      "box" => %{"x" => 0, "y" => 0, "w" => 144, "h" => 168},
      "meta" => %{"revision" => revision},
      "children" => [
        %{
          "type" => "TextLayer",
          "label" => "Title",
          "box" => %{"x" => 8, "y" => 12, "w" => 128, "h" => 28},
          "children" => []
        },
        %{
          "type" => "Layer",
          "label" => "Body",
          "box" => %{"x" => 0, "y" => 48, "w" => 144, "h" => 96},
          "children" => [
            %{
              "type" => "Rect",
              "label" => "card",
              "box" => %{"x" => 12, "y" => 8, "w" => 120, "h" => 36},
              "children" => []
            }
          ]
        }
      ]
    }
  end

  @spec sample_phone_view_tree(String.t(), String.t()) :: map()
  defp sample_phone_view_tree(rel_path, revision) do
    path = rel_path

    %{
      "type" => "PhoneRoot",
      "label" => path,
      "box" => %{"x" => 0, "y" => 0, "w" => 200, "h" => 360},
      "meta" => %{"revision" => revision},
      "children" => [
        %{
          "type" => "AppBar",
          "label" => "Elm · phone",
          "box" => %{"x" => 0, "y" => 0, "w" => 200, "h" => 48},
          "children" => []
        },
        %{
          "type" => "Scroll",
          "label" => "main",
          "box" => %{"x" => 0, "y" => 52, "w" => 200, "h" => 280},
          "children" => [
            %{
              "type" => "Card",
              "label" => path,
              "box" => %{"x" => 12, "y" => 8, "w" => 176, "h" => 72},
              "children" => []
            }
          ]
        }
      ]
    }
  end

  @spec ensure_phone_state(map()) :: map()
  defp ensure_phone_state(state) do
    watch_profile_id = parse_watch_profile_id(Map.get(state, :watch_profile_id))

    launch_reason =
      state
      |> Map.get(:launch_context, %{})
      |> Map.get("launch_reason")
      |> parse_launch_reason()

    launch_context = launch_context_for(watch_profile_id, launch_reason)

    state =
      if is_map(Map.get(state, :phone)) do
        state
      else
        Map.put(state, :phone, default_phone_runtime())
      end

    state =
      if is_map(Map.get(state, :watch)) do
        state
      else
        Map.put(state, :watch, default_watch_runtime(launch_context))
      end

    state =
      if is_map(Map.get(state, :auto_tick)) do
        state
      else
        Map.put(state, :auto_tick, default_auto_tick())
      end

    state
    |> Map.put_new(:debugger_timeline, [])
    |> Map.put_new(:debugger_seq, 0)
    |> Map.put_new(:disabled_subscriptions, [])
    |> Map.put_new(:storage, %{})
    |> ensure_protocol_surface_runtime_model(:companion)
    |> ensure_protocol_surface_runtime_model(:phone)
    |> Map.put(:watch_profile_id, watch_profile_id)
    |> Map.put(:launch_context, launch_context)
    |> apply_launch_context_to_watch_model_only()
  end

  @spec protocol_surface_model(String.t()) :: map()
  defp protocol_surface_model(status) when is_binary(status) do
    %{
      "status" => status,
      "runtime_model" => %{
        "status" => status,
        "protocol_inbound_count" => 0,
        "protocol_message_count" => 0
      }
    }
  end

  @spec ensure_protocol_surface_runtime_model(map(), :companion | :phone) :: map()
  defp ensure_protocol_surface_runtime_model(state, surface) when is_map(state) do
    model = get_in(state, [surface, :model]) || %{}
    model = if is_map(model), do: model, else: %{}
    runtime_model = Map.get(model, "runtime_model") || %{}
    runtime_model = if is_map(runtime_model), do: runtime_model, else: %{}
    protocol_messages = get_in(state, [surface, :protocol_messages])
    protocol_messages = if is_list(protocol_messages), do: protocol_messages, else: []
    status = Map.get(model, "status") || Map.get(runtime_model, "status") || "idle"

    inbound_count =
      Map.get(model, "protocol_inbound_count") || Map.get(runtime_model, "protocol_inbound_count") ||
        0

    last_message =
      Map.get(model, "protocol_last_inbound_message") ||
        Map.get(runtime_model, "protocol_last_inbound_message")

    last_from =
      Map.get(model, "protocol_last_inbound_from") ||
        Map.get(runtime_model, "protocol_last_inbound_from")

    runtime_model =
      runtime_model
      |> Map.put_new("status", status)
      |> Map.put_new("protocol_inbound_count", inbound_count)
      |> Map.put("protocol_message_count", length(protocol_messages))
      |> maybe_put_protocol_runtime_value("protocol_last_inbound_message", last_message)
      |> maybe_put_protocol_runtime_value("protocol_last_inbound_from", last_from)

    put_in(state, [surface, :model], Map.put(model, "runtime_model", runtime_model))
  end

  defp ensure_protocol_surface_runtime_model(state, _surface), do: state

  defp maybe_put_protocol_runtime_value(map, _key, value) when value in [nil, ""], do: map
  defp maybe_put_protocol_runtime_value(map, key, value), do: Map.put(map, key, value)

  @spec apply_launch_context_to_watch_model_only(term()) :: map()
  defp apply_launch_context_to_watch_model_only(state) when is_map(state) do
    launch_context = Map.get(state, :launch_context) || %{}

    state
    |> put_in(
      [:watch, :model],
      merge_launch_context_model(get_in(state, [:watch, :model]), launch_context)
    )
    |> put_in(
      [:watch, :view_tree],
      merge_launch_context_view_tree(get_in(state, [:watch, :view_tree]), launch_context)
    )
  end

  @spec merge_launch_context_model(term(), term()) :: map()
  defp merge_launch_context_model(model, launch_context)
       when is_map(model) and is_map(launch_context) do
    profile_id = Map.get(launch_context, "watch_profile_id")
    is_color = get_in(launch_context, ["screen", "is_color"])
    width = get_in(launch_context, ["screen", "width"])
    height = get_in(launch_context, ["screen", "height"])

    model
    |> Map.put("launch_context", launch_context)
    |> Map.put("watch_profile_id", profile_id)
    |> Map.put("screen_width", width)
    |> Map.put("screen_height", height)
    |> Map.put("supports_color", is_color)
  end

  defp merge_launch_context_model(model, _launch_context) when is_map(model), do: model
  defp merge_launch_context_model(_model, _launch_context), do: %{}

  @spec hydrate_runtime_model_for_message(term(), term()) :: map()
  defp hydrate_runtime_model_for_message(model, message) when is_map(model) do
    runtime_model = Map.get(model, "runtime_model") || Map.get(model, :runtime_model)

    if is_map(runtime_model) do
      hydrated =
        runtime_model
        |> hydrate_static_runtime_model_values()
        |> hydrate_runtime_model_launch_context(model)
        |> hydrate_runtime_model_message_payload(message)
        |> hydrate_runtime_model_protocol_payload(message)

      Map.put(model, "runtime_model", hydrated)
    else
      model
    end
  end

  defp hydrate_runtime_model_for_message(_model, _message), do: %{}

  @spec hydrate_static_runtime_model_values(term()) :: term()
  defp hydrate_static_runtime_model_values(runtime_model) when is_map(runtime_model) do
    Map.new(runtime_model, fn {key, value} -> {key, hydrate_static_runtime_value(value)} end)
  end

  defp hydrate_static_runtime_model_values(runtime_model), do: runtime_model

  @spec hydrate_static_runtime_value(term()) :: term()
  defp hydrate_static_runtime_value(%{} = value) do
    cond do
      Map.has_key?(value, "$ctor") ->
        ctor = to_string(Map.get(value, "$ctor") || "")
        args = Map.get(value, "$args") || []
        args = if is_list(args), do: Enum.map(args, &hydrate_static_runtime_value/1), else: []

        case {ctor, args} do
          {"True", []} -> true
          {"False", []} -> false
          _ -> %{"ctor" => ctor, "args" => args}
        end

      Map.has_key?(value, "$call") ->
        call = to_string(Map.get(value, "$call") || "")
        args = Map.get(value, "$args") || []
        args = if is_list(args), do: Enum.map(args, &hydrate_static_runtime_value/1), else: []

        case static_color_call_value(call, args) do
          {:ok, color} -> color
          :error -> %{"call" => call, "args" => args}
        end

      true ->
        Map.new(value, fn {key, nested} -> {key, hydrate_static_runtime_value(nested)} end)
    end
  end

  defp hydrate_static_runtime_value(values) when is_list(values),
    do: Enum.map(values, &hydrate_static_runtime_value/1)

  defp hydrate_static_runtime_value(value), do: value

  @spec static_color_call_value(String.t(), term()) :: {:ok, integer()} | :error
  defp static_color_call_value(call, []) when is_binary(call) do
    normalized = String.downcase(call)
    name = normalized |> String.split(".") |> List.last() |> to_string()

    cond do
      String.contains?(normalized, "color") ->
        static_color_constant(name)

      true ->
        :error
    end
  end

  defp static_color_call_value(_call, _args), do: :error

  @spec static_color_constant(String.t()) :: {:ok, integer()} | :error
  defp static_color_constant("black"), do: {:ok, 0xC0}
  defp static_color_constant("white"), do: {:ok, 0xFF}
  defp static_color_constant("red"), do: {:ok, 0xE0}
  defp static_color_constant("green"), do: {:ok, 0xCC}
  defp static_color_constant("blue"), do: {:ok, 0xC3}
  defp static_color_constant("clear"), do: {:ok, 0x00}
  defp static_color_constant(_name), do: :error

  @spec hydrate_runtime_model_launch_context(map(), map()) :: map()
  defp hydrate_runtime_model_launch_context(runtime_model, model)
       when is_map(runtime_model) and is_map(model) do
    runtime_model
    |> put_launch_context_value_if_missing(
      "screenW",
      get_in(model, ["launch_context", "screen", "width"])
    )
    |> put_launch_context_value_if_missing(
      "screenH",
      get_in(model, ["launch_context", "screen", "height"])
    )
    |> put_launch_context_value_if_missing(
      "isRound",
      launch_context_round?(Map.get(model, "launch_context"))
    )
  end

  @spec put_launch_context_value_if_missing(map(), String.t(), term()) :: map()
  defp put_launch_context_value_if_missing(runtime_model, key, value)
       when is_map(runtime_model) and is_binary(key) and not is_nil(value) do
    case Map.get(runtime_model, key) do
      nil ->
        Map.put(runtime_model, key, value)

      current when is_map(current) ->
        if unresolved_runtime_value?(current),
          do: Map.put(runtime_model, key, value),
          else: runtime_model

      _ ->
        runtime_model
    end
  end

  defp put_launch_context_value_if_missing(runtime_model, _key, _value)
       when is_map(runtime_model),
       do: runtime_model

  @spec unresolved_runtime_value?(term()) :: boolean()
  defp unresolved_runtime_value?(%{"$opaque" => true}), do: true
  defp unresolved_runtime_value?(%{:"$opaque" => true}), do: true
  defp unresolved_runtime_value?(%{"op" => "field_access"}), do: true
  defp unresolved_runtime_value?(%{op: "field_access"}), do: true
  defp unresolved_runtime_value?(%{op: :field_access}), do: true
  defp unresolved_runtime_value?(_value), do: false

  @spec launch_context_round?(term()) :: boolean() | nil
  defp launch_context_round?(%{"screen" => %{} = screen}) do
    cond do
      is_boolean(Map.get(screen, "isRound")) -> Map.get(screen, "isRound")
      is_binary(Map.get(screen, "shape")) -> Map.get(screen, "shape") == "round"
      true -> nil
    end
  end

  defp launch_context_round?(_launch_context), do: nil

  @spec hydrate_runtime_model_message_payload(map(), term()) :: map()
  defp hydrate_runtime_model_message_payload(runtime_model, message)
       when is_map(runtime_model) and is_binary(message) do
    constructor = message_constructor(message)
    int_payload = integer_message_payload(message)
    payload = elm_message_payload(message)

    runtime_model =
      cond do
        constructor == "MinuteChanged" and is_integer(int_payload) ->
          put_payload_integer_if_needed(runtime_model, "minute", int_payload, constructor)

        constructor == "HourChanged" and is_integer(int_payload) ->
          put_payload_integer_if_needed(runtime_model, "hour", int_payload, constructor)

        true ->
          runtime_model
      end

    cond do
      not is_nil(payload) ->
        maybe_put_message_payload_field(runtime_model, constructor, payload)

      constructor == "MinuteChanged" and is_integer(int_payload) ->
        runtime_model

      constructor == "HourChanged" and is_integer(int_payload) ->
        runtime_model

      true ->
        runtime_model
    end
  end

  defp hydrate_runtime_model_message_payload(runtime_model, _message), do: runtime_model

  @spec elm_message_payload(String.t()) :: term() | nil
  defp elm_message_payload(message) when is_binary(message) do
    case String.split(String.trim(message), ~r/\s+/, parts: 2) do
      [_ctor, payload] -> elm_literal_payload(String.trim(payload))
      _ -> nil
    end
  end

  @spec elm_literal_payload(String.t()) :: term() | nil
  defp elm_literal_payload(""), do: nil
  defp elm_literal_payload("True"), do: true
  defp elm_literal_payload("False"), do: false

  defp elm_literal_payload(payload) when is_binary(payload) do
    cond do
      String.match?(payload, ~r/^-?\d+$/) ->
        case Integer.parse(payload) do
          {value, ""} -> value
          _ -> nil
        end

      String.starts_with?(payload, "{") or String.starts_with?(payload, "[") or
          String.starts_with?(payload, "\"") ->
        case Jason.decode(payload) do
          {:ok, value} -> value
          _ -> nil
        end

      true ->
        nil
    end
  end

  @spec maybe_put_message_payload_field(map(), term(), term()) :: map()
  defp maybe_put_message_payload_field(runtime_model, constructor, payload)
       when is_map(runtime_model) and is_binary(constructor) do
    case model_field_for_message_constructor(constructor) do
      field when is_binary(field) ->
        if Map.has_key?(runtime_model, field) do
          put_payload_value_if_needed(runtime_model, field, payload, constructor)
        else
          runtime_model
        end

      _ ->
        runtime_model
    end
  end

  defp maybe_put_message_payload_field(runtime_model, _constructor, _payload), do: runtime_model

  @spec model_field_for_message_constructor(String.t()) :: String.t() | nil
  defp model_field_for_message_constructor("Got" <> rest), do: lower_camel_name(rest)
  defp model_field_for_message_constructor(_constructor), do: nil

  @spec put_payload_value_if_needed(map(), String.t(), term(), String.t()) :: map()
  defp put_payload_value_if_needed(runtime_model, key, value, constructor)
       when is_map(runtime_model) and is_binary(key) do
    case Map.get(runtime_model, key) do
      %{"ctor" => ctor, "args" => args} when ctor in ["Nothing", "Just"] and is_list(args) ->
        Map.put(runtime_model, key, %{"ctor" => "Just", "args" => [value]})

      %{"$ctor" => ctor, "$args" => args} when ctor in ["Nothing", "Just"] and is_list(args) ->
        Map.put(runtime_model, key, %{"$ctor" => "Just", "$args" => [value]})

      nil ->
        Map.put(runtime_model, key, %{"ctor" => "Just", "args" => [value]})

      current ->
        if message_constructor_value?(current, constructor),
          do: Map.put(runtime_model, key, value),
          else: runtime_model
    end
  end

  @spec hydrate_runtime_model_protocol_payload(map(), term()) :: map()
  defp hydrate_runtime_model_protocol_payload(runtime_model, message)
       when is_map(runtime_model) and is_binary(message) do
    with {:ok, protocol_message} <- nested_protocol_message(message),
         {:ok, constructor, args} <- split_constructor_call(protocol_message),
         field when is_binary(field) <- protocol_payload_model_field(constructor),
         %{"ctor" => maybe_ctor, "args" => maybe_args} <- Map.get(runtime_model, field),
         true <- maybe_ctor in ["Nothing", "Just"] and is_list(maybe_args),
         {:ok, value} <- protocol_payload_value(args) do
      Map.put(runtime_model, field, %{"ctor" => "Just", "args" => [value]})
    else
      _ -> runtime_model
    end
  end

  defp hydrate_runtime_model_protocol_payload(runtime_model, _message), do: runtime_model

  @spec nested_protocol_message(String.t()) :: {:ok, String.t()} | :error
  defp nested_protocol_message(message) when is_binary(message) do
    trimmed = String.trim(message)

    cond do
      String.starts_with?(trimmed, "FromPhone ") ->
        trimmed
        |> String.replace_prefix("FromPhone ", "")
        |> unwrap_parenthesized()
        |> then(&{:ok, &1})

      String.starts_with?(trimmed, "FromWatch (Ok ") ->
        trimmed
        |> String.replace_prefix("FromWatch (Ok ", "")
        |> trim_closing_paren()
        |> unwrap_parenthesized()
        |> then(&{:ok, &1})

      true ->
        :error
    end
  end

  @spec split_constructor_call(String.t()) :: {:ok, String.t(), String.t()} | :error
  defp split_constructor_call(message) when is_binary(message) do
    case String.split(String.trim(message), ~r/\s+/, parts: 2) do
      [ctor, args] when ctor != "" -> {:ok, ctor, String.trim(args)}
      [ctor] when ctor != "" -> {:ok, ctor, ""}
      _ -> :error
    end
  end

  @spec protocol_payload_model_field(String.t()) :: String.t() | nil
  defp protocol_payload_model_field(constructor) when is_binary(constructor) do
    cond do
      String.starts_with?(constructor, "Provide") ->
        constructor |> String.replace_prefix("Provide", "") |> lower_camel_name()

      String.starts_with?(constructor, "Set") ->
        constructor |> String.replace_prefix("Set", "") |> lower_camel_name()

      true ->
        nil
    end
  end

  @spec protocol_payload_value(String.t()) :: {:ok, term()} | :error
  defp protocol_payload_value(args) when is_binary(args) do
    args = args |> String.trim() |> unwrap_parenthesized()

    cond do
      args == "" ->
        :error

      String.match?(args, ~r/^-?\d+$/) ->
        {value, ""} = Integer.parse(args)
        {:ok, value}

      args in ["True", "False"] ->
        {:ok, args == "True"}

      String.starts_with?(args, "\"") ->
        case Jason.decode(args) do
          {:ok, value} -> {:ok, value}
          _ -> :error
        end

      true ->
        case String.split(args, ~r/\s+/, parts: 2) do
          [ctor, rest] when ctor != "" ->
            {:ok, %{"ctor" => ctor, "args" => protocol_payload_arg_values(rest)}}

          [ctor] when ctor != "" ->
            {:ok, %{"ctor" => ctor, "args" => []}}

          _ ->
            :error
        end
    end
  end

  @spec protocol_payload_arg_values(String.t()) :: [term()]
  defp protocol_payload_arg_values(args) when is_binary(args) do
    args
    |> String.split(~r/\s+/, trim: true)
    |> Enum.map(fn arg ->
      case protocol_payload_value(arg) do
        {:ok, value} -> value
        :error -> arg
      end
    end)
  end

  @spec unwrap_parenthesized(String.t()) :: String.t()
  defp unwrap_parenthesized(value) when is_binary(value) do
    trimmed = String.trim(value)

    if String.starts_with?(trimmed, "(") and String.ends_with?(trimmed, ")") do
      trimmed
      |> String.slice(1, String.length(trimmed) - 2)
      |> String.trim()
    else
      trimmed
    end
  end

  @spec trim_closing_paren(String.t()) :: String.t()
  defp trim_closing_paren(value) when is_binary(value) do
    trimmed = String.trim(value)

    if String.ends_with?(trimmed, ")") do
      String.slice(trimmed, 0, String.length(trimmed) - 1)
    else
      trimmed
    end
  end

  @spec lower_camel_name(String.t()) :: String.t() | nil
  defp lower_camel_name(<<first::utf8, rest::binary>>) do
    String.downcase(<<first::utf8>>) <> rest
  end

  defp lower_camel_name(_), do: nil

  @spec put_payload_integer_if_needed(map(), String.t(), integer(), String.t()) :: map()
  defp put_payload_integer_if_needed(runtime_model, key, value, constructor)
       when is_map(runtime_model) and is_binary(key) and is_integer(value) do
    case Map.get(runtime_model, key) do
      current when is_integer(current) ->
        runtime_model

      current ->
        if message_constructor_value?(current, constructor),
          do: Map.put(runtime_model, key, value),
          else: runtime_model
    end
  end

  @spec message_constructor_value?(term(), String.t()) :: boolean()
  defp message_constructor_value?(value, constructor)
       when is_map(value) and is_binary(constructor) do
    ctor = Map.get(value, "ctor") || Map.get(value, "$ctor") || Map.get(value, :ctor)
    ctor == constructor
  end

  defp message_constructor_value?(_value, _constructor), do: false

  @spec integer_message_payload(term()) :: integer() | nil
  defp integer_message_payload(message) when is_binary(message) do
    message
    |> String.trim()
    |> String.split(~r/\s+/, parts: 2)
    |> case do
      [_constructor, payload] ->
        case Integer.parse(String.trim(payload)) do
          {value, ""} -> value
          _ -> nil
        end

      _ ->
        nil
    end
  end

  defp integer_message_payload(_message), do: nil

  @spec merge_launch_context_view_tree(term(), term()) :: map()
  defp merge_launch_context_view_tree(view_tree, launch_context)
       when is_map(view_tree) and is_map(launch_context) do
    width = get_in(launch_context, ["screen", "width"]) || 144
    height = get_in(launch_context, ["screen", "height"]) || 168
    box = %{"x" => 0, "y" => 0, "w" => width, "h" => height}

    if map_size(view_tree) == 0 do
      %{"type" => "root", "children" => [], "box" => box}
    else
      Map.put(view_tree, "box", box)
    end
  end

  defp merge_launch_context_view_tree(view_tree, _launch_context) when is_map(view_tree),
    do: view_tree

  defp merge_launch_context_view_tree(_view_tree, _launch_context),
    do: %{"type" => "root", "children" => []}

  @spec apply_launch_context_to_surfaces(term(), term()) :: map()
  defp apply_launch_context_to_surfaces(state, launch_reason) when is_map(state) do
    watch_profile_id = parse_watch_profile_id(Map.get(state, :watch_profile_id))
    launch_reason = parse_launch_reason(launch_reason)
    launch_context = launch_context_for(watch_profile_id, launch_reason)

    state
    |> Map.put(:watch_profile_id, watch_profile_id)
    |> Map.put(:launch_context, launch_context)
    |> update_in([:watch, :model], &merge_launch_context_model(&1 || %{}, launch_context))
    |> update_in([:watch, :view_tree], &merge_launch_context_view_tree(&1 || %{}, launch_context))
  end

  @spec default_watch_profile_id() :: String.t()
  defp default_watch_profile_id, do: WatchModels.default_id()

  @spec parse_watch_profile_id(term()) :: String.t()
  defp parse_watch_profile_id(value) when is_binary(value) do
    normalized = String.downcase(String.trim(value))

    if Map.has_key?(watch_profiles_map(), normalized),
      do: normalized,
      else: default_watch_profile_id()
  end

  defp parse_watch_profile_id(_), do: default_watch_profile_id()

  @spec parse_optional_watch_profile_id(term()) :: String.t() | nil
  defp parse_optional_watch_profile_id(value) when is_binary(value),
    do: parse_watch_profile_id(value)

  defp parse_optional_watch_profile_id(_), do: nil

  @spec parse_launch_reason(term()) :: String.t()
  defp parse_launch_reason(value) when is_binary(value) do
    normalized = String.trim(value)

    if normalized in [
         "LaunchSystem",
         "LaunchUser",
         "LaunchPhone",
         "LaunchWakeup",
         "LaunchWorker",
         "LaunchUnknown"
       ] do
      normalized
    else
      "LaunchUser"
    end
  end

  defp parse_launch_reason(_), do: "LaunchUser"

  @spec watch_profiles_map() :: map()
  defp watch_profiles_map do
    WatchModels.profiles_map()
  end

  @spec watch_profile_label(term()) :: String.t()
  defp watch_profile_label(profile) when is_map(profile) do
    name = Map.get(profile, "name") || "Watch"
    screen = Map.get(profile, "screen") || %{}
    width = Map.get(screen, "width") || 0
    height = Map.get(screen, "height") || 0
    color = if Map.get(screen, "is_color") == true, do: "color", else: "mono"
    "#{name} (#{width}x#{height}, #{color})"
  end

  defp watch_profile_label(_), do: "Watch"

  @spec launch_context_for(term(), term()) :: map()
  defp launch_context_for(watch_profile_id, launch_reason)
       when is_binary(watch_profile_id) and is_binary(launch_reason) do
    profile =
      Map.get(
        watch_profiles_map(),
        watch_profile_id,
        Map.get(watch_profiles_map(), default_watch_profile_id())
      )

    screen = Map.get(profile, "screen") || %{}

    %{
      "launch_reason" => launch_reason,
      "watch_profile_id" => watch_profile_id,
      "watch_model" => Map.get(profile, "name"),
      "shape" => Map.get(profile, "shape"),
      "screen" => %{
        "width" => Map.get(screen, "width") || 144,
        "height" => Map.get(screen, "height") || 168,
        "isRound" => Map.get(profile, "shape") == "round",
        "is_color" => Map.get(screen, "is_color") == true
      }
    }
  end

  defp launch_context_for(_, _), do: launch_context_for(default_watch_profile_id(), "LaunchUser")

  @spec merge_runtime_model(map(), atom(), map()) :: map()
  defp merge_runtime_model(state, key, fields) when is_atom(key) and is_map(fields) do
    surface = Map.get(state, key) || %{}
    model = Map.get(surface, :model) || %{}
    Map.put(state, key, Map.put(surface, :model, Map.merge(model, fields)))
  end

  @spec maybe_merge_runtime_artifacts(map(), atom() | nil, map()) :: map()
  defp maybe_merge_runtime_artifacts(state, target, fields)
       when target in [:watch, :companion, :phone] and is_map(fields) and map_size(fields) > 0 do
    merge_runtime_model(state, target, fields)
  end

  defp maybe_merge_runtime_artifacts(state, _target, _fields), do: state

  @spec merge_elmc_diagnostic_preview(map(), map()) :: map()
  defp merge_elmc_diagnostic_preview(fields, attrs) when is_map(fields) and is_map(attrs) do
    cond do
      Map.has_key?(attrs, :diagnostics) or Map.has_key?(attrs, "diagnostics") ->
        list = Map.get(attrs, :diagnostics) || Map.get(attrs, "diagnostics") || []
        list = if is_list(list), do: list, else: []
        Map.put(fields, "elmc_diagnostic_preview", diagnostic_preview_chunk(list))

      true ->
        fields
    end
  end

  @spec diagnostic_preview_chunk([map()], pos_integer()) :: [map()]
  defp diagnostic_preview_chunk(diagnostics, limit \\ 12) when is_list(diagnostics) do
    diagnostics
    |> Enum.take(limit)
    |> Enum.map(&diagnostic_to_preview_map/1)
  end

  @spec diagnostic_to_preview_map(map()) :: map()
  defp diagnostic_to_preview_map(%{} = d) do
    msg = diagnostic_value(d, :message, "")
    warning_type = diagnostic_value(d, :warning_type)
    warning_code = diagnostic_value(d, :warning_code)
    warning_constructor = diagnostic_value(d, :warning_constructor)
    warning_expected_kind = diagnostic_value(d, :warning_expected_kind)
    warning_has_arg_pattern = diagnostic_value(d, :warning_has_arg_pattern)

    %{
      "severity" => to_string(diagnostic_value(d, :severity, "info")),
      "message" => String.slice(to_string(msg), 0, 240),
      "file" => diagnostic_value(d, :file),
      "line" => diagnostic_value(d, :line),
      "column" => diagnostic_value(d, :column),
      "source" => diagnostic_value(d, :source),
      "warning_type" => warning_type,
      "warning_code" => warning_code,
      "warning_constructor" => warning_constructor,
      "warning_expected_kind" => warning_expected_kind,
      "warning_has_arg_pattern" => warning_has_arg_pattern
    }
  end

  @spec diagnostic_value(term(), term(), term()) :: term()
  defp diagnostic_value(%{} = d, key, default \\ nil) when is_atom(key) do
    cond do
      Map.has_key?(d, key) ->
        Map.get(d, key)

      Map.has_key?(d, Atom.to_string(key)) ->
        Map.get(d, Atom.to_string(key))

      true ->
        default
    end
  end

  @spec elmc_check_model_fields(map()) :: map()
  defp elmc_check_model_fields(attrs) do
    status = Map.get(attrs, :status) || Map.get(attrs, "status")
    checked_path = Map.get(attrs, :checked_path) || Map.get(attrs, "checked_path")
    errors = Map.get(attrs, :error_count) || Map.get(attrs, "error_count") || 0
    warnings = Map.get(attrs, :warning_count) || Map.get(attrs, "warning_count") || 0

    %{
      "elmc_check_status" => elmc_status_string(status),
      "elmc_error_count" => errors,
      "elmc_warning_count" => warnings,
      "elmc_checked_path" => checked_path
    }
  end

  @spec elmc_check_event_payload(map()) :: map()
  defp elmc_check_event_payload(attrs) do
    status = Map.get(attrs, :status) || Map.get(attrs, "status")
    checked_path = Map.get(attrs, :checked_path) || Map.get(attrs, "checked_path")
    errors = Map.get(attrs, :error_count) || Map.get(attrs, "error_count") || 0
    warnings = Map.get(attrs, :warning_count) || Map.get(attrs, "warning_count") || 0

    payload = %{
      status: elmc_status_string(status),
      checked_path: checked_path,
      error_count: errors,
      warning_count: warnings
    }

    merge_elmc_event_diagnostic_preview(payload, attrs)
  end

  @spec merge_elmc_event_diagnostic_preview(map(), map()) :: map()
  defp merge_elmc_event_diagnostic_preview(payload, attrs)
       when is_map(payload) and is_map(attrs) do
    cond do
      Map.has_key?(attrs, :diagnostics) or Map.has_key?(attrs, "diagnostics") ->
        list = Map.get(attrs, :diagnostics) || Map.get(attrs, "diagnostics") || []
        list = if is_list(list), do: list, else: []
        Map.put(payload, :diagnostic_preview, diagnostic_preview_chunk(list))

      true ->
        payload
    end
  end

  @spec elmc_status_string(term()) :: String.t()
  defp elmc_status_string(:ok), do: "ok"
  defp elmc_status_string(:error), do: "error"
  defp elmc_status_string(s) when is_atom(s), do: Atom.to_string(s)
  defp elmc_status_string(s), do: to_string(s)

  @spec elmc_compile_model_fields(map()) :: map()
  defp elmc_compile_model_fields(attrs) do
    status = Map.get(attrs, :status) || Map.get(attrs, "status")
    compiled_path = Map.get(attrs, :compiled_path) || Map.get(attrs, "compiled_path")
    revision = Map.get(attrs, :revision) || Map.get(attrs, "revision")
    cached = Map.get(attrs, :cached) || Map.get(attrs, "cached") || false
    errors = Map.get(attrs, :error_count) || Map.get(attrs, "error_count") || 0
    warnings = Map.get(attrs, :warning_count) || Map.get(attrs, "warning_count") || 0
    detail = Map.get(attrs, :detail) || Map.get(attrs, "detail")

    base =
      %{
        "elmc_compile_status" => elmc_status_string(status),
        "elmc_compile_error_count" => errors,
        "elmc_compile_warning_count" => warnings,
        "elmc_compiled_path" => compiled_path,
        "elmc_compile_revision" => revision,
        "elmc_compile_cached" => if(cached, do: "true", else: "false")
      }
      |> Map.merge(optional_runtime_artifacts_from_attrs(attrs))

    if is_binary(detail) and detail != "" do
      Map.put(base, "elmc_compile_detail", detail)
    else
      base
    end
  end

  @spec compile_artifact_target(map()) :: :watch | :companion | :phone | nil
  defp compile_artifact_target(attrs) when is_map(attrs) do
    source_root =
      Map.get(attrs, :source_root) ||
        Map.get(attrs, "source_root") ||
        Map.get(attrs, :compiled_path) ||
        Map.get(attrs, "compiled_path")

    source_root_to_target(source_root)
  end

  defp compile_artifact_target(_attrs), do: nil

  @spec source_root_to_target(term()) :: :watch | :companion | :phone | nil
  defp source_root_to_target(value) when is_binary(value) do
    normalized =
      value
      |> String.trim()
      |> String.split(["/", "\\"], trim: true)
      |> List.first()
      |> to_string()

    # Compile artifacts are routed to executable debugger surfaces; the protocol
    # root is shared schema/types, while the phone root runs the companion worker.
    case normalized do
      "watch" -> :watch
      "protocol" -> nil
      "companion" -> :companion
      "phone" -> :companion
      _ -> nil
    end
  end

  defp source_root_to_target(:watch), do: :watch
  defp source_root_to_target(:protocol), do: nil
  defp source_root_to_target(:companion), do: :companion
  defp source_root_to_target(:phone), do: :companion
  defp source_root_to_target(_value), do: nil

  @spec elmc_compile_event_payload(map()) :: map()
  defp elmc_compile_event_payload(attrs) do
    status = Map.get(attrs, :status) || Map.get(attrs, "status")
    compiled_path = Map.get(attrs, :compiled_path) || Map.get(attrs, "compiled_path")
    revision = Map.get(attrs, :revision) || Map.get(attrs, "revision")
    cached = Map.get(attrs, :cached) || Map.get(attrs, "cached") || false
    errors = Map.get(attrs, :error_count) || Map.get(attrs, "error_count") || 0
    warnings = Map.get(attrs, :warning_count) || Map.get(attrs, "warning_count") || 0
    detail = Map.get(attrs, :detail) || Map.get(attrs, "detail")

    payload = %{
      status: elmc_status_string(status),
      compiled_path: compiled_path,
      revision: revision,
      cached: cached,
      error_count: errors,
      warning_count: warnings
    }

    payload =
      if is_binary(detail) and detail != "" do
        Map.put(payload, :detail, detail)
      else
        payload
      end

    payload
    |> merge_elmc_event_diagnostic_preview(attrs)
    |> merge_optional_runtime_artifact_payload(attrs)
  end

  @spec optional_runtime_artifacts_from_attrs(term()) :: map()
  defp optional_runtime_artifacts_from_attrs(attrs) when is_map(attrs) do
    %{}
    |> maybe_put_runtime_artifact_string_key(
      "elm_executor_metadata",
      Map.get(attrs, :elm_executor_metadata) || Map.get(attrs, "elm_executor_metadata")
    )
    |> maybe_put_runtime_artifact_string_key(
      "elm_executor_core_ir_b64",
      Map.get(attrs, :elm_executor_core_ir_b64) || Map.get(attrs, "elm_executor_core_ir_b64")
    )
  end

  @spec maybe_put_runtime_artifact_string_key(term(), term(), term()) :: map()
  defp maybe_put_runtime_artifact_string_key(map, key, value)
       when is_map(map) and is_binary(key) and (is_map(value) or is_binary(value)) do
    Map.put(map, key, value)
  end

  defp maybe_put_runtime_artifact_string_key(map, _key, _value) when is_map(map), do: map

  @spec merge_optional_runtime_artifact_payload(term(), term()) :: map()
  defp merge_optional_runtime_artifact_payload(payload, attrs)
       when is_map(payload) and is_map(attrs) do
    payload
    |> maybe_put_runtime_artifact_atom_key(
      :elm_executor_metadata,
      Map.get(attrs, :elm_executor_metadata) || Map.get(attrs, "elm_executor_metadata")
    )
  end

  defp merge_optional_runtime_artifact_payload(payload, _attrs) when is_map(payload), do: payload

  @spec refresh_runtime_previews_from_artifacts(map()) :: map()
  defp refresh_runtime_previews_from_artifacts(state) when is_map(state) do
    Enum.reduce([:watch, :companion, :phone], state, fn target, acc ->
      refresh_runtime_preview_for_target(acc, target)
    end)
  end

  @spec refresh_runtime_preview_for_target(map(), :watch | :companion | :phone) :: map()
  defp refresh_runtime_preview_for_target(state, target)
       when is_map(state) and target in [:watch, :companion, :phone] do
    surface = Map.get(state, target) || %{}
    model = Map.get(surface, :model) || %{}
    introspect = Map.get(model, "elm_introspect")
    artifacts = runtime_execution_artifacts(model)

    if is_map(introspect) and artifacts != %{} do
      view_tree = Map.get(surface, :view_tree) || %{}

      request =
        %{
          source_root: source_root_for_target(target),
          rel_path: Map.get(model, "last_path"),
          source: "",
          introspect: introspect,
          current_model: model,
          current_view_tree: view_tree
        }
        |> Map.merge(artifacts)

      case runtime_executor_module().execute(request) do
        {:ok, payload} when is_map(payload) ->
          model_patch =
            payload
            |> Map.get(:model_patch, %{})
            |> then(fn patch -> if is_map(patch), do: patch, else: %{} end)

          runtime_view_output =
            preferred_runtime_view_output(
              Map.get(payload, :view_output),
              Map.get(model, "runtime_view_output") || Map.get(model, :runtime_view_output)
            )

          next_model =
            model
            |> Map.put("elm_executor_mode", "runtime_executed")
            |> Map.merge(model_patch)
            |> put_runtime_view_output(runtime_view_output)

          next_state = put_in(state, [target, :model], next_model)

          runtime_view_tree =
            choose_runtime_preview_view_tree(
              Map.get(payload, :view_tree),
              view_tree,
              view_tree,
              runtime_view_output
            )

          if introspect_view_usable?(runtime_view_tree) do
            put_in(next_state, [target, :view_tree], runtime_view_tree)
          else
            next_state
          end

        _ ->
          state
      end
    else
      state
    end
  end

  @spec merge_latest_runtime_render_inputs(map(), map()) :: map()
  defp merge_latest_runtime_render_inputs(snapshot_model, latest_model)
       when is_map(snapshot_model) and is_map(latest_model) do
    Enum.reduce(
      [
        "elm_introspect",
        "elm_executor_metadata",
        "elm_executor_core_ir",
        "elm_executor_core_ir_b64",
        "runtime_view_output",
        "last_path"
      ],
      snapshot_model,
      fn key, acc ->
        case Map.get(latest_model, key) do
          nil -> acc
          value -> Map.put(acc, key, value)
        end
      end
    )
  end

  @spec maybe_put_debugger_view_tree(map(), term()) :: map()
  defp maybe_put_debugger_view_tree(runtime, runtime_view_tree) when is_map(runtime) do
    if introspect_view_usable?(runtime_view_tree) do
      Map.put(runtime, :view_tree, runtime_view_tree)
    else
      runtime
    end
  end

  @spec choose_runtime_preview_view_tree(term(), term(), term(), term()) :: term()
  defp choose_runtime_preview_view_tree(
         runtime_view_tree,
         latest_view_tree,
         snapshot_view_tree,
         view_output
       ) do
    cond do
      concrete_runtime_view_tree?(runtime_view_tree) ->
        runtime_view_tree

      has_runtime_view_output?(view_output) and concrete_runtime_view_tree?(latest_view_tree) ->
        latest_view_tree

      concrete_runtime_view_tree?(latest_view_tree) and
          parser_expression_view_tree?(runtime_view_tree) ->
        latest_view_tree

      is_map(runtime_view_tree) and map_size(runtime_view_tree) > 0 ->
        runtime_view_tree

      true ->
        snapshot_view_tree
    end
  end

  @spec has_runtime_view_output?(term()) :: boolean()
  defp has_runtime_view_output?(value) when is_list(value), do: value != []
  defp has_runtime_view_output?(_value), do: false

  @spec concrete_runtime_view_tree?(term()) :: boolean()
  defp concrete_runtime_view_tree?(%{"type" => type} = tree) when is_binary(type) do
    introspect_view_usable?(tree) and not parser_expression_root_type?(type)
  end

  defp concrete_runtime_view_tree?(_tree), do: false

  @spec parser_expression_view_tree?(term()) :: boolean()
  defp parser_expression_view_tree?(%{"type" => type}) when is_binary(type),
    do: parser_expression_root_type?(type)

  defp parser_expression_view_tree?(_tree), do: false

  @spec parser_expression_root_type?(String.t()) :: boolean()
  defp parser_expression_root_type?(type)
       when type in [
              "toUiNode",
              "append",
              "List",
              "call",
              "expr",
              "var",
              "withDefault",
              "if",
              "case"
            ],
       do: true

  defp parser_expression_root_type?(_type), do: false

  @spec maybe_put_runtime_artifact_atom_key(term(), term(), term()) :: map()
  defp maybe_put_runtime_artifact_atom_key(map, key, value)
       when is_map(map) and is_atom(key) and is_map(value) do
    Map.put(map, key, value)
  end

  defp maybe_put_runtime_artifact_atom_key(map, _key, _value) when is_map(map), do: map

  @spec elmc_manifest_model_fields(map()) :: map()
  defp elmc_manifest_model_fields(attrs) do
    status = Map.get(attrs, :status) || Map.get(attrs, "status")
    manifest_path = Map.get(attrs, :manifest_path) || Map.get(attrs, "manifest_path")
    revision = Map.get(attrs, :revision) || Map.get(attrs, "revision")
    strict = Map.get(attrs, :strict) || Map.get(attrs, "strict") || false
    cached = Map.get(attrs, :cached) || Map.get(attrs, "cached") || false
    errors = Map.get(attrs, :error_count) || Map.get(attrs, "error_count") || 0
    warnings = Map.get(attrs, :warning_count) || Map.get(attrs, "warning_count") || 0
    schema_version = Map.get(attrs, :schema_version) || Map.get(attrs, "schema_version")
    detail = Map.get(attrs, :detail) || Map.get(attrs, "detail")

    base = %{
      "elmc_manifest_status" => elmc_status_string(status),
      "elmc_manifest_error_count" => errors,
      "elmc_manifest_warning_count" => warnings,
      "elmc_manifest_path" => manifest_path,
      "elmc_manifest_revision" => revision,
      "elmc_manifest_strict" => if(strict, do: "true", else: "false"),
      "elmc_manifest_cached" => if(cached, do: "true", else: "false"),
      "elmc_manifest_schema_version" => manifest_schema_string(schema_version)
    }

    if is_binary(detail) and detail != "" do
      Map.put(base, "elmc_manifest_detail", detail)
    else
      base
    end
  end

  @spec manifest_schema_string(term()) :: String.t()
  defp manifest_schema_string(v) when is_integer(v), do: Integer.to_string(v)
  defp manifest_schema_string(v) when is_binary(v), do: v
  defp manifest_schema_string(_), do: "—"

  @spec elmc_manifest_event_payload(map()) :: map()
  defp elmc_manifest_event_payload(attrs) do
    status = Map.get(attrs, :status) || Map.get(attrs, "status")
    manifest_path = Map.get(attrs, :manifest_path) || Map.get(attrs, "manifest_path")
    revision = Map.get(attrs, :revision) || Map.get(attrs, "revision")
    strict = Map.get(attrs, :strict) || Map.get(attrs, "strict") || false
    cached = Map.get(attrs, :cached) || Map.get(attrs, "cached") || false
    errors = Map.get(attrs, :error_count) || Map.get(attrs, "error_count") || 0
    warnings = Map.get(attrs, :warning_count) || Map.get(attrs, "warning_count") || 0
    schema_version = Map.get(attrs, :schema_version) || Map.get(attrs, "schema_version")
    detail = Map.get(attrs, :detail) || Map.get(attrs, "detail")

    payload = %{
      status: elmc_status_string(status),
      manifest_path: manifest_path,
      revision: revision,
      strict: strict,
      cached: cached,
      error_count: errors,
      warning_count: warnings,
      schema_version: manifest_schema_string(schema_version)
    }

    payload =
      if is_binary(detail) and detail != "" do
        Map.put(payload, :detail, detail)
      else
        payload
      end

    merge_elmc_event_diagnostic_preview(payload, attrs)
  end

  @spec normalize_source_root(map()) :: String.t()
  defp normalize_source_root(attrs) do
    case Map.get(attrs, :source_root) || Map.get(attrs, "source_root") do
      "protocol" -> "protocol"
      "phone" -> "phone"
      _ -> "watch"
    end
  end

  @spec normalize_step_target(term()) :: :watch | :companion | :phone
  defp normalize_step_target("companion"), do: :companion
  defp normalize_step_target("protocol"), do: :companion
  defp normalize_step_target("phone"), do: :phone
  defp normalize_step_target(:companion), do: :companion
  defp normalize_step_target(:phone), do: :phone
  defp normalize_step_target(_), do: :watch

  @spec normalize_optional_step_target(term()) :: (:watch | :companion | :phone) | nil
  defp normalize_optional_step_target(nil), do: nil
  defp normalize_optional_step_target(""), do: nil
  defp normalize_optional_step_target(value), do: normalize_step_target(value)

  @spec apply_hot_reload(map(), String.t() | nil, String.t(), String.t(), String.t()) :: map()
  defp apply_hot_reload(state, rel_path, source, reason, source_root) do
    revision = compute_revision(rel_path, source)
    path = rel_path || "unknown"

    state
    |> Map.put(:running, true)
    |> apply_launch_context_to_surfaces("LaunchUser")
    |> Map.put(:revision, revision)
    |> put_in([:watch, :last_message], reload_pulse(:watch, source_root))
    |> put_in([:watch, :model, "revision"], revision)
    |> put_in([:companion, :last_message], reload_pulse(:companion, source_root))
    |> put_in([:companion, :model, "revision"], revision)
    |> put_in([:phone, :last_message], reload_pulse(:phone, source_root))
    |> put_in([:phone, :model, "revision"], revision)
    |> put_reload_source_fields(introspect_target_key(source_root), rel_path, source, source_root)
    |> put_view_trees_for_surface(path, revision, source_root)
    |> merge_elm_introspect_with_payload(rel_path, source, source_root)
    |> then(fn {st, intro_payload} ->
      st
      |> append_event("debugger.reload", %{
        reason: reason,
        rel_path: rel_path,
        revision: revision,
        source_root: source_root
      })
      |> maybe_append_elm_introspect_event(intro_payload)
      |> maybe_append_runtime_exec_event(source_root)
    end)
    |> append_event("debugger.protocol_tx", protocol_reload_payload(revision, source_root))
    |> append_event("debugger.protocol_rx", protocol_reload_payload(revision, source_root))
    |> append_event("debugger.view_render", %{target: "watch", root: "simulated-root"})
    |> append_event("debugger.view_render", %{target: "companion", root: "companion-root"})
    |> maybe_append_phone_view_render(source_root)
  end

  @spec put_reload_source_fields(map(), atom(), String.t() | nil, String.t(), String.t()) :: map()
  defp put_reload_source_fields(state, target, rel_path, source, source_root)
       when target in [:watch, :companion, :phone] do
    state
    |> put_in([target, :model, "last_path"], rel_path)
    |> put_in([target, :model, "last_source"], source)
    |> put_in([target, :model, "source_root"], source_root)
  end

  defp put_reload_source_fields(state, _target, _rel_path, _source, _source_root), do: state

  @spec merge_elm_introspect_with_payload(map(), String.t() | nil, String.t(), String.t()) ::
          {map(), map() | nil}
  defp merge_elm_introspect_with_payload(state, rel_path, source, source_root) do
    if elm_introspect?(rel_path, source, source_root) do
      case Ide.Debugger.ElmIntrospect.analyze_source(source, rel_path || "Main.elm") do
        {:ok, %{"elm_introspect" => ei}} ->
          st =
            apply_elm_introspect_snapshot(
              state,
              ei,
              introspect_target_key(source_root),
              source,
              rel_path
            )
            |> maybe_apply_init_device_data_responses(introspect_target_key(source_root))
            |> maybe_apply_init_protocol_events(introspect_target_key(source_root))

          payload =
            if introspect_event_worth_logging?(ei) do
              elm_introspect_event_payload(ei, rel_path, source_root)
            else
              nil
            end

          {st, payload}

        _ ->
          {state, nil}
      end
    else
      {state, nil}
    end
  end

  @spec maybe_append_elm_introspect_event(term(), term()) :: map()
  defp maybe_append_elm_introspect_event(state, nil), do: state

  defp maybe_append_elm_introspect_event(state, payload) when is_map(payload) do
    append_event(state, "debugger.elm_introspect", payload)
  end

  @spec maybe_append_runtime_exec_event(term(), term()) :: map()
  defp maybe_append_runtime_exec_event(state, source_root) do
    target = introspect_target_key(source_root)
    append_runtime_exec_event_for_target(state, target)
  end

  @spec append_runtime_exec_event_for_target(term(), term(), term()) :: map()
  defp append_runtime_exec_event_for_target(state, target, extra \\ %{})
       when target in [:watch, :companion, :phone] and is_map(extra) do
    runtime = get_in(state, [target, :model, "elm_executor"])

    if is_map(runtime) and map_size(runtime) > 0 do
      payload =
        %{
          target: source_root_for_target(target),
          engine: runtime["engine"] || "unknown",
          source_byte_size: runtime["source_byte_size"],
          msg_constructor_count: runtime["msg_constructor_count"],
          update_case_branch_count: runtime["update_case_branch_count"],
          view_case_branch_count: runtime["view_case_branch_count"],
          runtime_model_source: runtime["runtime_model_source"],
          view_tree_source: runtime["view_tree_source"],
          execution_backend: runtime["execution_backend"],
          runtime_mode: runtime["runtime_mode"],
          external_fallback_reason: runtime["external_fallback_reason"],
          followup_message_count: runtime["followup_message_count"],
          init_cmd_count: runtime["init_cmd_count"],
          runtime_model_entry_count: runtime["runtime_model_entry_count"],
          view_tree_node_count: runtime["view_tree_node_count"],
          runtime_model_sha256: runtime["runtime_model_sha256"],
          view_tree_sha256: runtime["view_tree_sha256"]
        }
        |> Map.merge(extra)

      append_event(state, "debugger.runtime_exec", payload)
    else
      state
    end
  end

  @spec maybe_append_runtime_status_debugger_event(map(), :watch | :companion | :phone) :: map()
  defp maybe_append_runtime_status_debugger_event(state, target)
       when is_map(state) and target in [:watch, :companion, :phone] do
    runtime = get_in(state, [target, :model, "elm_executor"])

    case runtime_status_message(runtime) do
      nil ->
        state

      message ->
        append_debugger_event(state, "runtime", target, message, "runtime_status")
    end
  end

  defp maybe_append_runtime_status_debugger_event(state, _target), do: state

  @spec maybe_append_runtime_status_debugger_event(
          map(),
          :watch | :companion | :phone,
          term(),
          term()
        ) ::
          map()
  defp maybe_append_runtime_status_debugger_event(state, target, execution, introspect)
       when is_map(state) and target in [:watch, :companion, :phone] and is_map(execution) do
    runtime =
      case Map.get(execution, :runtime) || Map.get(execution, "runtime") do
        value when is_map(value) -> value
        _ -> get_in(state, [target, :model, "elm_executor"]) || %{}
      end
      |> Map.put("init_cmd_count", meaningful_init_cmd_count(introspect))
      |> Map.put(
        "followup_message_count",
        execution
        |> execution_followup_messages()
        |> normalize_followup_messages()
        |> length()
      )

    case runtime_status_message(runtime) do
      nil ->
        state

      message ->
        state
        |> append_event("debugger.runtime_status", %{
          target: source_root_for_target(target),
          message: message,
          execution_backend: runtime["execution_backend"],
          runtime_mode: runtime["runtime_mode"],
          external_fallback_reason: runtime["external_fallback_reason"],
          followup_message_count: runtime["followup_message_count"],
          init_cmd_count: runtime["init_cmd_count"]
        })
        |> append_debugger_event("runtime", target, message, "runtime_status")
    end
  end

  defp maybe_append_runtime_status_debugger_event(state, _target, _execution, _introspect),
    do: state

  @spec execution_followup_messages(term()) :: list()
  defp execution_followup_messages(execution) when is_map(execution) do
    case Map.get(execution, :followup_messages) || Map.get(execution, "followup_messages") do
      messages when is_list(messages) -> messages
      _ -> []
    end
  end

  defp execution_followup_messages(_execution), do: []

  @spec meaningful_init_cmd_count(term()) :: non_neg_integer()
  defp meaningful_init_cmd_count(introspect) do
    introspect
    |> introspect_cmd_calls("init_cmd_calls")
    |> Enum.count(&meaningful_init_cmd_call?/1)
  end

  @spec meaningful_init_cmd_call?(term()) :: boolean()
  defp meaningful_init_cmd_call?(call) when is_map(call) do
    target = Map.get(call, "target") || Map.get(call, :target)
    name = Map.get(call, "name") || Map.get(call, :name)
    not (target in ["Cmd.none", "Platform.Cmd.none"] or name in ["none", "None", nil])
  end

  defp meaningful_init_cmd_call?(_call), do: false

  @spec runtime_status_message(term()) :: String.t() | nil
  defp runtime_status_message(runtime) when is_map(runtime) do
    backend = runtime["execution_backend"]
    reason = runtime["external_fallback_reason"]
    followup_count = runtime["followup_message_count"]
    init_cmd_count = runtime["init_cmd_count"]

    cond do
      is_binary(reason) and reason != "" ->
        "runtime fallback #{backend || "unknown"}: #{reason}"

      backend in ["fallback_default", "legacy_default", "default"] ->
        "runtime fallback #{backend}"

      runtime_init_execution?(runtime) and is_integer(init_cmd_count) and init_cmd_count > 0 and
          followup_count in [0, nil] ->
        "runtime no followups for #{init_cmd_count} init cmd(s)"

      true ->
        nil
    end
  end

  defp runtime_status_message(_runtime), do: nil

  @spec runtime_init_execution?(term()) :: boolean()
  defp runtime_init_execution?(runtime) when is_map(runtime) do
    runtime["operation_source"] in ["init_model", nil] and
      runtime["runtime_model_source"] in ["init_model", nil]
  end

  defp runtime_init_execution?(_runtime), do: false

  @spec introspect_event_worth_logging?(term()) :: boolean()
  defp introspect_event_worth_logging?(ei) when is_map(ei) do
    init = Map.get(ei, "init_model")
    msgs = Map.get(ei, "msg_constructors") || []
    msgs = if is_list(msgs), do: msgs, else: []
    branches = Map.get(ei, "update_case_branches") || []
    branches = if is_list(branches), do: branches, else: []
    vbr = Map.get(ei, "view_case_branches") || []
    vbr = if is_list(vbr), do: vbr, else: []
    ibr = Map.get(ei, "init_case_branches") || []
    ibr = if is_list(ibr), do: ibr, else: []
    sbr = Map.get(ei, "subscriptions_case_branches") || []
    sbr = if is_list(sbr), do: sbr, else: []
    subs = Map.get(ei, "subscription_ops") || []
    subs = if is_list(subs), do: subs, else: []
    icmd = Map.get(ei, "init_cmd_ops") || []
    icmd = if is_list(icmd), do: icmd, else: []
    ucmd = Map.get(ei, "update_cmd_ops") || []
    ucmd = if is_list(ucmd), do: ucmd, else: []
    prts = Map.get(ei, "ports") || []
    prts = if is_list(prts), do: prts, else: []
    imps = Map.get(ei, "imported_modules") || []
    imps = if is_list(imps), do: imps, else: []
    mp = Map.get(ei, "main_program")
    vt = Map.get(ei, "view_tree") || %{}

    params? =
      ["init_params", "update_params", "view_params", "subscriptions_params"]
      |> Enum.any?(fn k ->
        xs = Map.get(ei, k) || []
        is_list(xs) and xs != []
      end)

    port_mod = Map.get(ei, "port_module") == true

    init != nil or msgs != [] or branches != [] or vbr != [] or ibr != [] or sbr != [] or
      subs != [] or icmd != [] or
      ucmd != [] or prts != [] or imps != [] or is_map(mp) or params? or port_mod or
      introspect_view_usable?(vt)
  end

  @spec elm_introspect_event_payload(term(), term(), term()) :: map()
  defp elm_introspect_event_payload(ei, rel_path, source_root) when is_map(ei) do
    msgs = Map.get(ei, "msg_constructors") || []
    msgs = if is_list(msgs), do: msgs, else: []
    branches = Map.get(ei, "update_case_branches") || []
    branches = if is_list(branches), do: branches, else: []
    vbr = Map.get(ei, "view_case_branches") || []
    vbr = if is_list(vbr), do: vbr, else: []
    ibr = Map.get(ei, "init_case_branches") || []
    ibr = if is_list(ibr), do: ibr, else: []
    sbr = Map.get(ei, "subscriptions_case_branches") || []
    sbr = if is_list(sbr), do: sbr, else: []
    subs = Map.get(ei, "subscription_ops") || []
    subs = if is_list(subs), do: subs, else: []
    icmd = Map.get(ei, "init_cmd_ops") || []
    icmd = if is_list(icmd), do: icmd, else: []
    ucmd = Map.get(ei, "update_cmd_ops") || []
    ucmd = if is_list(ucmd), do: ucmd, else: []
    vt = Map.get(ei, "view_tree") || %{}
    root = Map.get(vt, "type") || Map.get(vt, :type) || "unknown"

    preview =
      branches
      |> Enum.take(4)
      |> Enum.join(", ")
      |> then(fn s -> if length(branches) > 4, do: s <> "…", else: s end)

    sub_preview =
      subs
      |> Enum.take(3)
      |> Enum.join(", ")
      |> then(fn s -> if length(subs) > 3, do: s <> "…", else: s end)

    init_cmd_preview =
      icmd
      |> Enum.take(3)
      |> Enum.join(", ")
      |> then(fn s -> if length(icmd) > 3, do: s <> "…", else: s end)

    update_cmd_preview =
      ucmd
      |> Enum.take(3)
      |> Enum.join(", ")
      |> then(fn s -> if length(ucmd) > 3, do: s <> "…", else: s end)

    view_case_preview =
      vbr
      |> Enum.take(4)
      |> Enum.join(", ")
      |> then(fn s -> if length(vbr) > 4, do: s <> "…", else: s end)

    init_case_preview =
      ibr
      |> Enum.take(4)
      |> Enum.join(", ")
      |> then(fn s -> if length(ibr) > 4, do: s <> "…", else: s end)

    subscriptions_case_preview =
      sbr
      |> Enum.take(4)
      |> Enum.join(", ")
      |> then(fn s -> if length(sbr) > 4, do: s <> "…", else: s end)

    prts = Map.get(ei, "ports") || []
    prts = if is_list(prts), do: prts, else: []

    imps = Map.get(ei, "imported_modules") || []
    imps = if is_list(imps), do: imps, else: []

    import_preview =
      imps
      |> Enum.take(8)
      |> Enum.join(", ")
      |> then(fn s -> if length(imps) > 8, do: s <> "…", else: s end)

    ta = Map.get(ei, "type_aliases") || []
    ta = if is_list(ta), do: ta, else: []
    uni = Map.get(ei, "unions") || []
    uni = if is_list(uni), do: uni, else: []
    fns = Map.get(ei, "functions") || []
    fns = if is_list(fns), do: fns, else: []

    type_aliases_preview =
      ta
      |> Enum.take(5)
      |> Enum.join(", ")
      |> then(fn s -> if length(ta) > 5, do: s <> "…", else: s end)

    union_types_preview =
      uni
      |> Enum.take(5)
      |> Enum.join(", ")
      |> then(fn s -> if length(uni) > 5, do: s <> "…", else: s end)

    top_level_functions_preview =
      fns
      |> Enum.take(8)
      |> Enum.join(", ")
      |> then(fn s -> if length(fns) > 8, do: s <> "…", else: s end)

    port_preview =
      prts
      |> Enum.take(6)
      |> Enum.join(", ")
      |> then(fn s -> if length(prts) > 6, do: s <> "…", else: s end)

    mp = Map.get(ei, "main_program")
    main_fields = if is_map(mp), do: Map.get(mp, "fields") || [], else: []
    main_fields = if is_list(main_fields), do: main_fields, else: []

    ucs = Map.get(ei, "update_case_subject")
    vcs = Map.get(ei, "view_case_subject")
    ics = Map.get(ei, "init_case_subject")
    scs = Map.get(ei, "subscriptions_case_subject")

    port_module = Map.get(ei, "port_module") == true
    mex = Map.get(ei, "module_exposing")

    module_exposing_preview =
      case mex do
        ".." ->
          "(..)"

        xs when is_list(xs) and xs != [] ->
          xs
          |> Enum.take(8)
          |> Enum.join(", ")
          |> then(fn s -> if length(xs) > 8, do: s <> "…", else: s end)

        _ ->
          "—"
      end

    ient = Map.get(ei, "import_entries") || []
    ient = if is_list(ient), do: ient, else: []

    import_entries_preview =
      ient
      |> Enum.take(4)
      |> Enum.map(&Ide.Debugger.ElmIntrospect.import_entry_summary/1)
      |> Enum.join("; ")
      |> then(fn s ->
        cond do
          s == "" ->
            "—"

          length(ient) > 4 ->
            s <> "…"

          true ->
            s
        end
      end)

    sbs = Map.get(ei, "source_byte_size")
    slc = Map.get(ei, "source_line_count")

    base0 = %{
      module: Map.get(ei, "module"),
      rel_path: rel_path,
      source_root: source_root,
      target: elm_introspect_target_label(source_root),
      source_byte_size: sbs,
      source_line_count: slc,
      port_module: port_module,
      module_exposing: mex,
      module_exposing_preview: module_exposing_preview,
      msg_count: length(msgs),
      update_branch_count: length(branches),
      update_branches_preview: preview,
      init_case_branch_count: length(ibr),
      init_case_branches_preview: init_case_preview,
      view_branch_count: length(vbr),
      view_branches_preview: view_case_preview,
      subscriptions_case_branch_count: length(sbr),
      subscriptions_case_branches_preview: subscriptions_case_preview,
      subscription_count: length(subs),
      subscriptions_preview: sub_preview,
      init_cmd_count: length(icmd),
      init_cmd_preview: init_cmd_preview,
      update_cmd_count: length(ucmd),
      update_cmd_preview: update_cmd_preview,
      port_count: length(prts),
      ports_preview: port_preview,
      import_count: length(imps),
      imports_preview: import_preview,
      import_entry_count: length(ient),
      import_entries_preview: import_entries_preview,
      type_alias_count: length(ta),
      type_aliases_preview: type_aliases_preview,
      union_type_count: length(uni),
      union_types_preview: union_types_preview,
      top_level_function_count: length(fns),
      top_level_functions_preview: top_level_functions_preview,
      view_root: root,
      view_outline: introspect_view_usable?(vt)
    }

    base =
      base0
      |> maybe_put_string_field(:init_case_subject, ics)
      |> maybe_put_string_field(:subscriptions_case_subject, scs)
      |> maybe_put_string_field(:update_case_subject, ucs)
      |> maybe_put_string_field(:view_case_subject, vcs)

    param_payload =
      [:init_params, :update_params, :view_params, :subscriptions_params]
      |> Enum.reduce(%{}, fn atom_key, acc ->
        str = Atom.to_string(atom_key)
        xs = Map.get(ei, str) || []

        xs = if is_list(xs), do: xs, else: []

        if xs != [] do
          Map.put(acc, atom_key, xs)
        else
          acc
        end
      end)

    merged_main =
      if is_map(mp) do
        %{
          main_kind: Map.get(mp, "kind"),
          main_target: Map.get(mp, "target"),
          main_field_count: length(main_fields)
        }
      else
        %{}
      end

    Map.merge(base, Map.merge(merged_main, param_payload))
  end

  @spec maybe_put_string_field(term(), term(), term()) :: map()
  defp maybe_put_string_field(map, key, value) when is_map(map) do
    if is_binary(value) and value != "" do
      Map.put(map, key, value)
    else
      map
    end
  end

  @spec elm_introspect_target_label(term()) :: String.t()
  defp elm_introspect_target_label("watch"), do: "watch"
  defp elm_introspect_target_label("protocol"), do: "companion"
  defp elm_introspect_target_label("phone"), do: "phone"
  defp elm_introspect_target_label(_), do: "watch"

  @spec elm_introspect?(term(), term(), term()) :: boolean()
  defp elm_introspect?(rel_path, source, source_root) do
    source_root in ["watch", "protocol", "phone"] and is_binary(rel_path) and
      String.ends_with?(rel_path, ".elm") and is_binary(source) and String.trim(source) != ""
  end

  @spec introspect_target_key(term()) :: :watch | :companion | :phone
  defp introspect_target_key("watch"), do: :watch
  defp introspect_target_key("protocol"), do: :companion
  defp introspect_target_key("phone"), do: :phone
  defp introspect_target_key(_), do: :watch

  @spec source_root_for_target(term()) :: String.t()
  defp source_root_for_target(:watch), do: "watch"
  defp source_root_for_target(:companion), do: "protocol"
  defp source_root_for_target(:phone), do: "phone"

  @spec runtime_execution_artifacts(term()) :: map()
  defp runtime_execution_artifacts(model) when is_map(model) do
    metadata = Map.get(model, "elm_executor_metadata")
    core_ir = decode_core_ir_artifact(model)

    %{}
    |> maybe_put_runtime_artifact(:elm_executor_metadata, metadata)
    |> maybe_put_runtime_artifact(:elm_executor_core_ir, core_ir)
  end

  defp runtime_execution_artifacts(_model), do: %{}

  @spec http_eval_context(term()) :: map()
  defp http_eval_context(model) when is_map(model) do
    case decode_core_ir_artifact(model) do
      core_ir when is_map(core_ir) ->
        %{
          functions: ElmExecutor.Runtime.CoreIREvaluator.index_functions(core_ir),
          record_aliases: ElmExecutor.Runtime.CoreIREvaluator.index_record_aliases(core_ir),
          constructor_tags: ElmExecutor.Runtime.CoreIREvaluator.index_constructor_tags(core_ir),
          module: "Main",
          source_module: "Main"
        }

      _ ->
        %{}
    end
  end

  defp http_eval_context(_model), do: %{}

  @spec http_command_event(term()) :: map()
  defp http_command_event(command) when is_map(command) do
    %{
      method: Map.get(command, "method") || Map.get(command, :method),
      url: Map.get(command, "url") || Map.get(command, :url),
      package: Map.get(command, "package") || Map.get(command, :package)
    }
  end

  defp http_command_event(_), do: %{}

  @spec maybe_put_runtime_artifact(term(), term(), term()) :: map()
  defp maybe_put_runtime_artifact(map, key, value)
       when is_map(map) and is_atom(key) and is_map(value) do
    Map.put(map, key, value)
  end

  defp maybe_put_runtime_artifact(map, _key, _value) when is_map(map), do: map

  @spec decode_core_ir_artifact(term()) :: map() | nil
  defp decode_core_ir_artifact(model) when is_map(model) do
    case Map.get(model, "elm_executor_core_ir") do
      value when is_map(value) ->
        value

      _ ->
        case Map.get(model, "elm_executor_core_ir_b64") do
          encoded when is_binary(encoded) and encoded != "" ->
            with {:ok, binary} <- Base.decode64(encoded),
                 value <- :erlang.binary_to_term(binary, [:safe]),
                 true <- is_map(value) do
              value
            else
              _ -> nil
            end

          _ ->
            nil
        end
    end
  end

  @spec apply_elm_introspect_snapshot(term(), term(), term(), term(), term()) :: map()
  defp apply_elm_introspect_snapshot(state, ei, target, source, rel_path)
       when is_map(ei) and target in [:watch, :companion, :phone] and is_binary(source) do
    surface = Map.get(state, target) || %{}
    model = Map.get(surface, :model) || %{}
    view_tree = Map.get(surface, :view_tree) || %{}

    request =
      %{
        source_root: source_root_for_target(target),
        rel_path: rel_path || model["last_path"],
        source: source,
        introspect: ei,
        current_model: model,
        current_view_tree: view_tree
      }
      |> Map.merge(runtime_execution_artifacts(model))

    execution =
      case runtime_executor_module().execute(request) do
        {:ok, payload} when is_map(payload) -> payload
        _ -> %{model_patch: %{}, view_tree: nil, runtime: %{}}
      end

    model_patch =
      execution
      |> Map.get(:model_patch, %{})
      |> then(fn patch -> if is_map(patch), do: patch, else: %{} end)

    model =
      Map.merge(model, %{
        "elm_executor_mode" => "runtime_executed",
        "elm_introspect" => ei
      })
      |> Map.merge(model_patch)
      |> put_runtime_view_output(Map.get(execution, :view_output))
      |> hydrate_runtime_model_for_message(nil)

    vt = Map.get(ei, "view_tree")
    runtime_vt = Map.get(execution, :view_tree)

    state =
      state
      |> put_in([target, :model], model)

    state =
      cond do
        introspect_view_usable?(runtime_vt) -> put_in(state, [target, :view_tree], runtime_vt)
        introspect_view_usable?(vt) -> put_in(state, [target, :view_tree], vt)
        true -> state
      end

    state
    |> append_event("debugger.init_in", %{
      target: source_root_for_target(target),
      message: "init",
      message_source: "init"
    })
    |> append_debugger_event("init", target, "init", "init")
    |> maybe_append_runtime_status_debugger_event(target, execution, ei)
    |> maybe_apply_runtime_followups(
      target,
      "init",
      "init",
      normalize_followup_messages(execution_followup_messages(execution))
    )
  end

  @spec introspect_view_usable?(term()) :: boolean()
  defp introspect_view_usable?(%{"type" => "unknown", "children" => []}), do: false

  defp introspect_view_usable?(%{"children" => children})
       when is_list(children) and children != [],
       do: true

  defp introspect_view_usable?(_), do: false

  @spec put_view_trees_for_surface(map(), String.t(), String.t(), String.t()) :: map()
  defp put_view_trees_for_surface(state, path, revision, "phone") do
    state
    |> put_in([:watch, :view_tree], sample_view_tree(path, revision))
    |> put_in([:companion, :view_tree], sample_companion_view_tree(path, revision))
    |> put_in([:phone, :view_tree], sample_phone_view_tree(path, revision))
  end

  defp put_view_trees_for_surface(state, path, revision, "protocol") do
    state
    |> put_in([:watch, :view_tree], sample_view_tree(path, revision))
    |> put_in([:companion, :view_tree], sample_companion_view_tree("protocol:#{path}", revision))
    |> put_in([:phone, :view_tree], Map.get(default_phone_runtime(), :view_tree))
  end

  defp put_view_trees_for_surface(state, path, revision, "watch") do
    state
    |> put_in([:watch, :view_tree], sample_view_tree(path, revision))
    |> put_in([:companion, :view_tree], sample_companion_view_tree(path, revision))
    |> put_in([:phone, :view_tree], Map.get(default_phone_runtime(), :view_tree))
  end

  @spec reload_pulse(term(), term()) :: String.t()
  defp reload_pulse(:watch, "phone"), do: "PhoneSync"
  defp reload_pulse(:companion, "phone"), do: "PhoneSync"
  defp reload_pulse(:phone, "phone"), do: "PhoneHotReload"
  defp reload_pulse(:watch, "protocol"), do: "ProtocolSync"
  defp reload_pulse(:companion, "protocol"), do: "ProtocolHotReload"
  defp reload_pulse(:phone, "protocol"), do: "ProtocolSync"
  defp reload_pulse(_, _), do: "HotReload"

  @spec maybe_append_phone_view_render(term(), term()) :: map()
  defp maybe_append_phone_view_render(state, "phone") do
    append_event(state, "debugger.view_render", %{target: "phone", root: "phone-root"})
  end

  defp maybe_append_phone_view_render(state, _), do: state

  @spec protocol_reload_payload(term(), term()) :: map()
  defp protocol_reload_payload(revision, "phone") do
    %{from: "phone", to: "companion", message: "PhoneReloaded:#{revision}"}
  end

  defp protocol_reload_payload(revision, "protocol") do
    %{from: "watch", to: "companion", message: "ProtocolReloaded:#{revision}"}
  end

  defp protocol_reload_payload(revision, _) do
    %{from: "watch", to: "companion", message: "Reloaded:#{revision}"}
  end

  @spec export_payload(String.t(), runtime_state(), keyword()) :: map()
  defp export_payload(project_slug, state, opts) do
    events =
      state.events
      |> Enum.sort_by(& &1.seq)
      |> normalize_events_with_snapshot_refs()

    runtime_fingerprint_compare =
      build_runtime_fingerprint_compare_payload(
        state.events,
        Keyword.get(opts, :compare_cursor_seq),
        Keyword.get(opts, :baseline_cursor_seq)
      )

    %{
      "companion" => normalize_term(Map.get(state, :companion, %{})),
      "debugger_seq" => Map.get(state, :debugger_seq, 0),
      "debugger_timeline" => normalize_term(Map.get(state, :debugger_timeline, [])),
      "disabled_subscriptions" => normalize_term(disabled_subscriptions(state)),
      "events" => events,
      "export_version" => 1,
      "phone" => normalize_term(Map.get(state, :phone, %{})),
      "project_slug" => project_slug,
      "revision" => Map.get(state, :revision),
      "running" => Map.get(state, :running, false),
      "watch_profile_id" => Map.get(state, :watch_profile_id),
      "launch_context" => normalize_term(Map.get(state, :launch_context, %{})),
      "runtime_fingerprint_compare" => normalize_term(runtime_fingerprint_compare),
      "seq" => Map.get(state, :seq, 0),
      "watch" => normalize_term(Map.get(state, :watch, %{}))
    }
  end

  @spec build_runtime_fingerprint_compare_payload([runtime_event()], term(), term()) :: map()
  defp build_runtime_fingerprint_compare_payload(events, compare_cursor_seq, baseline_cursor_seq)
       when is_list(events) do
    current_seq = resolve_export_compare_cursor(events, compare_cursor_seq)
    baseline_seq = resolve_export_baseline_cursor(events, baseline_cursor_seq, current_seq)
    current_event = event_at_seq(events, current_seq)
    baseline_event = event_at_seq(events, baseline_seq)

    current_fingerprints = event_runtime_fingerprints(current_event)
    baseline_fingerprints = event_runtime_fingerprints(baseline_event)

    surfaces =
      [:watch, :companion, :phone]
      |> Enum.reduce(%{}, fn surface, acc ->
        current = Map.get(current_fingerprints, surface)
        baseline = Map.get(baseline_fingerprints, surface)

        if is_map(current) or is_map(baseline) do
          current_model_sha = map_value(current, "runtime_model_sha256")
          baseline_model_sha = map_value(baseline, "runtime_model_sha256")
          current_view_sha = map_value(current, "view_tree_sha256")
          baseline_view_sha = map_value(baseline, "view_tree_sha256")
          current_protocol_inbound_count = map_value(current, "protocol_inbound_count")
          baseline_protocol_inbound_count = map_value(baseline, "protocol_inbound_count")
          current_protocol_message_count = map_value(current, "protocol_message_count")
          baseline_protocol_message_count = map_value(baseline, "protocol_message_count")

          current_protocol_last_inbound_message =
            map_value(current, "protocol_last_inbound_message")

          baseline_protocol_last_inbound_message =
            map_value(baseline, "protocol_last_inbound_message")

          current_execution_backend = map_value(current, "execution_backend")
          baseline_execution_backend = map_value(baseline, "execution_backend")
          current_external_fallback_reason = map_value(current, "external_fallback_reason")
          baseline_external_fallback_reason = map_value(baseline, "external_fallback_reason")
          current_target_numeric_key = map_value(current, "target_numeric_key")
          baseline_target_numeric_key = map_value(baseline, "target_numeric_key")
          current_target_numeric_key_source = map_value(current, "target_numeric_key_source")
          baseline_target_numeric_key_source = map_value(baseline, "target_numeric_key_source")
          current_target_boolean_key = map_value(current, "target_boolean_key")
          baseline_target_boolean_key = map_value(baseline, "target_boolean_key")
          current_target_boolean_key_source = map_value(current, "target_boolean_key_source")
          baseline_target_boolean_key_source = map_value(baseline, "target_boolean_key_source")
          current_active_target_key = map_value(current, "active_target_key")
          baseline_active_target_key = map_value(baseline, "active_target_key")
          current_active_target_key_source = map_value(current, "active_target_key_source")
          baseline_active_target_key_source = map_value(baseline, "active_target_key_source")

          backend_changed =
            current_execution_backend != baseline_execution_backend or
              current_external_fallback_reason != baseline_external_fallback_reason

          key_target_changed =
            current_target_numeric_key != baseline_target_numeric_key or
              current_target_numeric_key_source != baseline_target_numeric_key_source or
              current_target_boolean_key != baseline_target_boolean_key or
              current_target_boolean_key_source != baseline_target_boolean_key_source or
              current_active_target_key != baseline_active_target_key or
              current_active_target_key_source != baseline_active_target_key_source

          Map.put(acc, Atom.to_string(surface), %{
            "changed" =>
              current_model_sha != baseline_model_sha or
                current_view_sha != baseline_view_sha or
                current_protocol_inbound_count != baseline_protocol_inbound_count or
                current_protocol_message_count != baseline_protocol_message_count or
                current_protocol_last_inbound_message != baseline_protocol_last_inbound_message or
                backend_changed or
                key_target_changed,
            "backend_changed" => backend_changed,
            "key_target_changed" => key_target_changed,
            "current_model_sha" => current_model_sha,
            "baseline_model_sha" => baseline_model_sha,
            "current_view_sha" => current_view_sha,
            "baseline_view_sha" => baseline_view_sha,
            "current_protocol_inbound_count" => current_protocol_inbound_count,
            "baseline_protocol_inbound_count" => baseline_protocol_inbound_count,
            "current_protocol_message_count" => current_protocol_message_count,
            "baseline_protocol_message_count" => baseline_protocol_message_count,
            "current_protocol_last_inbound_message" => current_protocol_last_inbound_message,
            "baseline_protocol_last_inbound_message" => baseline_protocol_last_inbound_message,
            "current_execution_backend" => current_execution_backend,
            "baseline_execution_backend" => baseline_execution_backend,
            "current_external_fallback_reason" => current_external_fallback_reason,
            "baseline_external_fallback_reason" => baseline_external_fallback_reason,
            "current_target_numeric_key" => current_target_numeric_key,
            "baseline_target_numeric_key" => baseline_target_numeric_key,
            "current_target_numeric_key_source" => current_target_numeric_key_source,
            "baseline_target_numeric_key_source" => baseline_target_numeric_key_source,
            "current_target_boolean_key" => current_target_boolean_key,
            "baseline_target_boolean_key" => baseline_target_boolean_key,
            "current_target_boolean_key_source" => current_target_boolean_key_source,
            "baseline_target_boolean_key_source" => baseline_target_boolean_key_source,
            "current_active_target_key" => current_active_target_key,
            "baseline_active_target_key" => baseline_active_target_key,
            "current_active_target_key_source" => current_active_target_key_source,
            "baseline_active_target_key_source" => baseline_active_target_key_source
          })
        else
          acc
        end
      end)

    %{
      "current_cursor_seq" => current_seq,
      "baseline_cursor_seq" => baseline_seq,
      "changed_surface_count" => Enum.count(Map.values(surfaces), &map_value(&1, "changed")),
      "backend_changed_surface_count" =>
        Enum.count(Map.values(surfaces), &map_value(&1, "backend_changed")),
      "key_target_changed_surface_count" =>
        Enum.count(Map.values(surfaces), &map_value(&1, "key_target_changed")),
      "key_target_drift_detail" =>
        RuntimeFingerprintDrift.key_target_drift_detail(%{surfaces: surfaces},
          compare_key_keys: [:baseline_active_target_key],
          compare_source_keys: [:baseline_active_target_key_source]
        ),
      "drift_detail" =>
        RuntimeFingerprintDrift.merge_drift_detail(
          RuntimeFingerprintDrift.backend_drift_detail(%{surfaces: surfaces},
            compare_backend_keys: [:baseline_execution_backend],
            compare_reason_keys: [:baseline_external_fallback_reason]
          ),
          RuntimeFingerprintDrift.key_target_drift_detail(%{surfaces: surfaces},
            compare_key_keys: [:baseline_active_target_key],
            compare_source_keys: [:baseline_active_target_key_source]
          )
        ),
      "surfaces" => surfaces
    }
  end

  @spec resolve_export_compare_cursor(term(), term()) :: integer() | nil
  defp resolve_export_compare_cursor(events, cursor_seq) when is_list(events) do
    CursorSeq.resolve_at_or_before(events, cursor_seq)
  end

  @spec resolve_export_baseline_cursor(term(), term(), term()) :: integer() | nil
  defp resolve_export_baseline_cursor(events, baseline_cursor_seq, current_seq)
       when is_list(events) and is_integer(current_seq) do
    CursorSeq.resolve_before(events, current_seq, baseline_cursor_seq)
  end

  defp resolve_export_baseline_cursor(_events, _baseline_cursor_seq, _current_seq), do: nil

  @spec event_at_seq(term(), term()) :: map() | nil
  defp event_at_seq(events, seq) when is_list(events) and is_integer(seq),
    do: Enum.find(events, &(&1.seq == seq))

  defp event_at_seq(_events, _seq), do: nil

  @spec event_runtime_fingerprints(term()) :: map()
  defp event_runtime_fingerprints(nil), do: %{watch: nil, companion: nil, phone: nil}

  defp event_runtime_fingerprints(event) when is_map(event) do
    %{
      watch: runtime_fingerprint_from_surface(Map.get(event, :watch)),
      companion: runtime_fingerprint_from_surface(Map.get(event, :companion)),
      phone: runtime_fingerprint_from_surface(Map.get(event, :phone))
    }
  end

  @spec runtime_fingerprint_from_surface(term()) :: map()
  defp runtime_fingerprint_from_surface(surface) when is_map(surface) do
    model = Map.get(surface, :model)
    model = if is_map(model), do: model, else: %{}
    runtime = Map.get(model, "elm_executor")
    runtime = if is_map(runtime), do: runtime, else: %{}

    fingerprint = %{
      "runtime_model_sha256" =>
        map_value(model, "runtime_model_sha256") || map_value(runtime, "runtime_model_sha256"),
      "view_tree_sha256" =>
        map_value(model, "runtime_view_tree_sha256") || map_value(runtime, "view_tree_sha256"),
      "runtime_mode" => map_value(model, "elm_executor_mode"),
      "engine" => map_value(runtime, "engine"),
      "execution_backend" => map_value(runtime, "execution_backend"),
      "external_fallback_reason" => map_value(runtime, "external_fallback_reason"),
      "target_numeric_key" => map_value(runtime, "target_numeric_key"),
      "target_numeric_key_source" => map_value(runtime, "target_numeric_key_source"),
      "target_boolean_key" => map_value(runtime, "target_boolean_key"),
      "target_boolean_key_source" => map_value(runtime, "target_boolean_key_source"),
      "active_target_key" => map_value(runtime, "active_target_key"),
      "active_target_key_source" => map_value(runtime, "active_target_key_source"),
      "protocol_inbound_count" =>
        map_value(model, "protocol_inbound_count") ||
          map_value(map_value(model, "runtime_model"), "protocol_inbound_count"),
      "protocol_message_count" =>
        case Map.get(surface, :protocol_messages) do
          xs when is_list(xs) and xs != [] -> length(xs)
          _ -> nil
        end,
      "protocol_last_inbound_message" =>
        map_value(model, "protocol_last_inbound_message") ||
          map_value(map_value(model, "runtime_model"), "protocol_last_inbound_message")
    }

    if Enum.any?(Map.values(fingerprint), &(!is_nil(&1))), do: fingerprint, else: nil
  end

  defp runtime_fingerprint_from_surface(_), do: nil

  @spec map_value(term(), term()) :: term()
  defp map_value(map, key) when is_map(map) do
    if Map.has_key?(map, key) do
      Map.get(map, key)
    else
      atom_key =
        if is_binary(key) do
          try do
            String.to_existing_atom(key)
          rescue
            ArgumentError -> nil
          end
        else
          nil
        end

      if is_atom(atom_key) and Map.has_key?(map, atom_key), do: Map.get(map, atom_key), else: nil
    end
  end

  defp map_value(_map, _key), do: nil

  @spec normalize_event(runtime_event()) :: map()
  defp normalize_event(event) when is_map(event) do
    %{
      "companion" => normalize_term(Map.get(event, :companion, %{})),
      "payload" => normalize_term(Map.get(event, :payload, %{})),
      "phone" => normalize_term(Map.get(event, :phone, %{})),
      "seq" => Map.get(event, :seq),
      "type" => Map.get(event, :type),
      "watch" => normalize_term(Map.get(event, :watch, %{}))
    }
  end

  @spec normalize_events_with_snapshot_refs([runtime_event()]) :: [map()]
  defp normalize_events_with_snapshot_refs(events) when is_list(events) do
    {rows, _previous} =
      Enum.map_reduce(events, %{}, fn event, previous ->
        row = normalize_event(event)
        seq = Map.get(row, "seq")

        refs =
          ["watch", "companion", "phone"]
          |> Enum.reduce(%{}, fn surface, acc ->
            current_snapshot = Map.get(row, surface)

            case Map.get(previous, surface) do
              %{seq: prev_seq, snapshot: snapshot}
              when snapshot == current_snapshot and is_integer(prev_seq) ->
                Map.put(acc, surface, prev_seq)

              _ ->
                acc
            end
          end)

        changed_surfaces =
          ["watch", "companion", "phone"]
          |> Enum.reject(&Map.has_key?(refs, &1))

        row =
          row
          |> maybe_put_snapshot_refs(refs)
          |> Map.put("snapshot_changed_surfaces", changed_surfaces)

        next_previous =
          ["watch", "companion", "phone"]
          |> Enum.reduce(previous, fn surface, acc ->
            snapshot = Map.get(row, surface)

            if is_map(snapshot) do
              Map.put(acc, surface, %{seq: seq, snapshot: snapshot})
            else
              acc
            end
          end)

        {row, next_previous}
      end)

    rows
  end

  @spec maybe_put_snapshot_refs(term(), term()) :: term()
  defp maybe_put_snapshot_refs(row, refs) when map_size(refs) == 0, do: row
  defp maybe_put_snapshot_refs(row, refs), do: Map.put(row, "snapshot_refs", refs)

  @spec snapshot_surface(term(), term()) :: term()
  defp snapshot_surface(surface, _fallback) when is_map(surface), do: surface
  defp snapshot_surface(_surface, fallback), do: fallback

  @spec normalize_term(term()) :: term()
  defp normalize_term(map) when is_map(map) do
    map
    |> Enum.map(fn {k, v} -> {to_string(k), normalize_term(v)} end)
    |> Enum.sort_by(fn {k, _} -> k end)
    |> Map.new()
  end

  defp normalize_term(list) when is_list(list), do: Enum.map(list, &normalize_term/1)

  defp normalize_term(other), do: other

  @spec decode_import_body(String.t() | map()) :: {:ok, map()} | {:error, term()}
  defp decode_import_body(json) when is_binary(json) do
    case Jason.decode(json) do
      {:ok, body} when is_map(body) -> {:ok, body}
      {:ok, _} -> {:error, :invalid_trace}
      {:error, _} -> {:error, :invalid_json}
    end
  end

  defp decode_import_body(body) when is_map(body), do: {:ok, body}

  @spec validate_import_body(map()) :: :ok | {:error, term()}
  defp validate_import_body(body) do
    version = Map.get(body, "export_version")

    if version == 1 and is_list(Map.get(body, "events")) and is_map(Map.get(body, "watch")) and
         is_map(Map.get(body, "companion")) and is_integer(Map.get(body, "seq")) do
      :ok
    else
      {:error, :invalid_trace}
    end
  end

  @spec maybe_match_import_slug(map(), String.t(), keyword()) :: :ok | {:error, term()}
  defp maybe_match_import_slug(body, project_slug, opts) do
    if Keyword.get(opts, :strict_slug, true) do
      if Map.get(body, "project_slug") == project_slug do
        :ok
      else
        {:error, :slug_mismatch}
      end
    else
      :ok
    end
  end

  @spec state_from_import_body(map()) :: map()
  defp state_from_import_body(body) do
    events =
      body
      |> Map.get("events", [])
      |> Enum.sort_by(&Map.get(&1, "seq"))
      |> Enum.map(&import_event/1)
      |> Enum.reverse()

    parsed_state = %{
      running: Map.get(body, "running", false) == true,
      revision: Map.get(body, "revision"),
      watch_profile_id: parse_watch_profile_id(Map.get(body, "watch_profile_id")),
      launch_context: normalize_term(Map.get(body, "launch_context") || %{}),
      watch: import_watch(Map.get(body, "watch", %{})),
      companion: import_companion(Map.get(body, "companion", %{})),
      phone: import_phone(Map.get(body, "phone", %{})),
      disabled_subscriptions:
        Map.get(body, "disabled_subscriptions", []) |> List.wrap() |> Enum.filter(&is_map/1),
      events: events,
      debugger_timeline: import_debugger_timeline(Map.get(body, "debugger_timeline", [])),
      debugger_seq:
        parse_optional_step_cursor_seq(Map.get(body, "debugger_seq")) ||
          infer_debugger_seq(Map.get(body, "debugger_timeline", [])),
      seq: parse_optional_step_cursor_seq(Map.get(body, "seq")) || 0
    }

    ensure_phone_state(parsed_state)
  end

  @spec import_event(map()) :: runtime_event()
  defp import_event(map) when is_map(map) do
    %{
      seq: Map.get(map, "seq"),
      type: Map.get(map, "type"),
      payload: Map.get(map, "payload") || %{},
      watch: import_watch(Map.get(map, "watch") || %{}),
      companion: import_companion(Map.get(map, "companion") || %{}),
      phone: import_phone(Map.get(map, "phone") || %{})
    }
  end

  @spec import_debugger_timeline(term()) :: [debugger_event()]
  defp import_debugger_timeline(rows) when is_list(rows) do
    rows
    |> Enum.filter(&is_map/1)
    |> Enum.map(&import_debugger_row/1)
    |> Enum.filter(fn row -> is_integer(row.seq) and row.seq >= 0 end)
    |> Enum.sort_by(& &1.seq, :desc)
  end

  defp import_debugger_timeline(_rows), do: []

  @spec import_debugger_row(map()) :: debugger_event()
  defp import_debugger_row(map) when is_map(map) do
    %{
      seq: Map.get(map, "seq") || Map.get(map, :seq),
      raw_seq: Map.get(map, "raw_seq") || Map.get(map, :raw_seq) || 0,
      type: Map.get(map, "type") || Map.get(map, :type) || "update",
      target: Map.get(map, "target") || Map.get(map, :target) || "watch",
      message: Map.get(map, "message") || Map.get(map, :message) || "",
      message_source: Map.get(map, "message_source") || Map.get(map, :message_source),
      watch: import_watch(Map.get(map, "watch") || Map.get(map, :watch) || %{}),
      companion: import_companion(Map.get(map, "companion") || Map.get(map, :companion) || %{}),
      phone: import_phone(Map.get(map, "phone") || Map.get(map, :phone) || %{})
    }
  end

  @spec infer_debugger_seq(term()) :: non_neg_integer()
  defp infer_debugger_seq(rows) when is_list(rows) do
    rows
    |> Enum.map(fn
      %{"seq" => seq} -> seq
      %{seq: seq} -> seq
      _ -> 0
    end)
    |> Enum.filter(&is_integer/1)
    |> Enum.max(fn -> 0 end)
  end

  defp infer_debugger_seq(_rows), do: 0

  @spec import_watch(map()) :: map()
  defp import_watch(map) when is_map(map) do
    %{
      model: Map.get(map, "model") || %{},
      last_message: Map.get(map, "last_message"),
      protocol_messages: Map.get(map, "protocol_messages") || [],
      view_tree:
        Map.get(map, "view_tree") ||
          %{
            "type" => "root",
            "children" => []
          }
    }
  end

  @spec import_companion(map()) :: map()
  defp import_companion(map) when is_map(map) do
    %{
      model: Map.get(map, "model") || %{},
      last_message: Map.get(map, "last_message"),
      protocol_messages: Map.get(map, "protocol_messages") || [],
      view_tree:
        Map.get(map, "view_tree") ||
          %{
            "type" => "CompanionRoot",
            "label" => "idle",
            "children" => []
          }
    }
  end

  @spec import_phone(map()) :: map()
  defp import_phone(map) when is_map(map) do
    %{
      model: Map.get(map, "model") || %{},
      last_message: Map.get(map, "last_message"),
      protocol_messages: Map.get(map, "protocol_messages") || [],
      view_tree:
        Map.get(map, "view_tree") ||
          %{
            "type" => "PhoneRoot",
            "label" => "idle",
            "children" => []
          }
    }
  end

  @spec runtime_executor_module() :: module()
  defp runtime_executor_module do
    Application.get_env(:ide, __MODULE__, [])
    |> Keyword.get(:runtime_executor_module, RuntimeExecutor)
  end
end
