defmodule Ide.Debugger do
  @moduledoc """
  Lightweight debugger state substrate for watch, companion, and phone runtimes.
  """

  use Agent
  alias Ide.Debugger.AppMessageQueue
  alias Ide.Debugger.CompileIngest
  alias Ide.Debugger.CursorSeq
  alias Ide.Debugger.HttpExecutor
  alias Ide.Debugger.RuntimeExecutor
  alias Ide.Debugger.ProtocolResolutionCtx
  alias Ide.Debugger.RuntimeArtifacts
  alias Ide.Debugger.RuntimeFingerprintDrift
  alias Ide.Debugger.StepInput
  alias Ide.Debugger.Surface
  alias Ide.Debugger.Types
  alias Ide.Debugger.Types.ElmIntrospectEventPayload
  alias Ide.Debugger.RuntimeSurfaceMerge
  alias Ide.Debugger.Types.ElmcSurfaceFields
  alias Ide.Debugger.Types.RuntimeEvent
  alias Ide.Debugger.Types.RuntimeEventPayload, as: EventPayload
  alias Ide.Debugger.Types.RuntimeState
  alias Ide.Debugger.WireValues
  alias Ide.SimulatorSettings
  alias Ide.Compiler
  alias Ide.PebblePreferences
  alias Ide.Projects
  alias Ide.WatchModels

  defmodule CompanionApiSuffixes do
    @moduledoc false

    @spec suffixes(String.t(), [String.t()]) :: [String.t()]
    def suffixes(module, ops) when is_binary(module) and is_list(ops) do
      Enum.flat_map(ops, fn op ->
        [
          ".Pebble.Companion.#{module}.#{op}",
          ".#{module}.#{op}",
          "#{module}.#{op}"
        ]
      end)
    end
  end

  @dialyzer [{:no_match, apply_step_once: 7}]
  @history_limit 500
  @default_auto_fire_interval_ms 1_000
  @min_auto_fire_interval_ms 100
  @agent_call_timeout_ms 30_000
  @configuration_subscription_contract %{
    target_suffixes:
      CompanionApiSuffixes.suffixes("Configuration", ["onConfiguration", "onClosed"]) ++
        CompanionApiSuffixes.suffixes("GeneratedPreferences", ["onConfiguration", "onClosed"])
  }
  @geolocation_subscription_contract %{
    target_suffixes: CompanionApiSuffixes.suffixes("Geolocation", ["onCurrentPosition"])
  }
  @companion_bridge_subscription_contracts [
    %{
      source: "battery",
      target_suffixes: CompanionApiSuffixes.suffixes("Battery", ["onBattery"]),
      payload: :battery
    },
    %{
      source: "locale",
      target_suffixes: CompanionApiSuffixes.suffixes("Locale", ["onLocale"]),
      payload: :locale
    },
    %{
      source: "network",
      target_suffixes: CompanionApiSuffixes.suffixes("Connectivity", ["onConnectivity"]),
      payload: :network,
      plain_result: true
    },
    %{
      source: "notifications",
      target_suffixes:
        CompanionApiSuffixes.suffixes("Notifications", ["onNotificationStatus"]),
      payload: :notifications
    },
    %{
      source: "weather",
      target_suffixes:
        CompanionApiSuffixes.suffixes("Weather", ["onWeather", "onCurrent", "onForecast"]),
      payload: :weather,
      ok_result_variant: "Current"
    },
    %{
      source: "calendar",
      target_suffixes:
        CompanionApiSuffixes.suffixes("Calendar", ["onCalendar", "onCurrent", "onUpcoming"]),
      payload: :calendar
    },
    %{
      source: "environment",
      target_suffixes: CompanionApiSuffixes.suffixes("Environment", ["onEnvironment"]),
      payload: :environment
    }
  ]
  @storage_result_contract %{
    target_suffixes: CompanionApiSuffixes.suffixes("Storage", ["onStorage"])
  }
  @preferences_result_contract %{
    target_suffixes: CompanionApiSuffixes.suffixes("PreferenceStore", ["onPreference"])
  }

  @type runtime_event :: RuntimeState.runtime_event()
  @type debugger_event :: RuntimeState.debugger_event()
  @type runtime_state :: RuntimeState.t() | RuntimeState.wire_map()
  @type snapshot_opt :: Types.snapshot_opt()

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(_opts) do
    Agent.start_link(fn -> %{} end, name: __MODULE__)
  end

  @spec start_session(String.t()) :: {:ok, runtime_state()}
  def start_session(project_slug) when is_binary(project_slug),
    do: start_session(project_slug, %{})

  @spec start_session(String.t(), Types.session_attrs()) :: {:ok, runtime_state()}
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

      simulator_settings =
        Map.get(state, :simulator_settings)
        |> normalize_simulator_settings()

      %{
        state
        | running: true,
          revision: nil,
          watch_profile_id: watch_profile_id,
          launch_context: launch_context,
          simulator_settings: simulator_settings,
          storage: Map.get(state, :storage, %{}),
          watch: default_watch_runtime(launch_context),
          companion: default_companion_runtime(),
          phone: default_phone_runtime(),
          auto_tick: default_auto_tick(),
          disabled_subscriptions: [],
          events: [],
          debugger_timeline: [],
          debugger_seq: 0,
          seq: 0,
          app_message_queues: AppMessageQueue.empty()
      }
      |> attach_companion_configuration(project_slug)
      |> attach_vector_resource_indices(project_slug)
      |> attach_bitmap_resource_indices(project_slug)
      |> apply_launch_context_to_surfaces(launch_reason)
      |> apply_simulator_settings_to_surfaces()
      |> append_event(
        "debugger.start",
        Ide.Debugger.Types.StartEventPayload.from_session(launch_reason, watch_profile_id)
      )
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

      simulator_settings =
        Map.get(state, :simulator_settings)
        |> normalize_simulator_settings()

      base =
        %{
          state
          | revision: nil,
            watch_profile_id: watch_profile_id,
            launch_context: launch_context,
            simulator_settings: simulator_settings,
            watch: default_watch_runtime(launch_context),
            companion: default_companion_runtime(),
            phone: default_phone_runtime(),
            debugger_timeline: [],
            debugger_seq: 0,
            app_message_queues: AppMessageQueue.empty()
        }
        |> attach_companion_configuration(project_slug)
        |> apply_simulator_settings_to_surfaces()

      append_event(base, "debugger.reset", Ide.Debugger.Types.ResetEventPayload.empty())
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
  @spec watch_profiles() :: [Types.watch_profile_list_item()]
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
  Returns default simulator inputs used by debugger device and companion APIs.
  """
  @spec default_simulator_settings() :: Types.simulator_settings()
  def default_simulator_settings do
    %{
      "battery_percent" => 88,
      "charging" => false,
      "connected" => true,
      "clock_24h" => true,
      "use_simulated_time" => false,
      "simulated_time" => nil,
      "simulated_date" => nil,
      "timezone_id" => "Europe/Berlin",
      "timezone_offset_min" => 120,
      "locale" => "en-US",
      "language" => "en",
      "region" => "US",
      "network_online" => true,
      "notifications_enabled" => true,
      "quiet_hours" => false,
      "weather" => %{
        "temperatureC" => 21,
        "condition" => "clear",
        "humidityPercent" => 50,
        "pressureHpa" => 1013,
        "windKph" => 8
      },
      "calendar_events" => [],
      "storage_values" => %{},
      "preferences" => %{},
      "environment" => %{
        "sun" => %{"sunriseMin" => 420, "sunsetMin" => 1200, "polarDay" => false},
        "moon" => %{"moonriseMin" => 900, "moonsetMin" => 300, "phaseE6" => 500_000},
        "tide" => nil
      },
      "latitude" => 48.137154,
      "longitude" => 11.576124,
      "accuracy" => 25.0,
      "timeline_peek" => false,
      "compass_heading_deg" => 0,
      "compass_valid" => true,
      "app_in_focus" => true,
      "health_steps" => 4200,
      "health_steps_today" => 9100,
      "dictation_transcript" => "",
      "dictation_error" => "",
      "vibe_pattern_ms" => []
    }
  end

  @doc """
  Updates the debugger watch profile and launch context used for init/runtime.
  """
  @spec set_watch_profile(String.t(), Types.session_attrs()) :: {:ok, runtime_state()}
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
      |> apply_simulator_settings_to_surfaces()
      |> append_event(
        "debugger.watch_profile_set",
        Ide.Debugger.Types.WatchProfileSetEventPayload.from_profile(profile_id, launch_reason)
      )
    end)
  end

  @doc """
  Updates debugger simulator inputs used for watch device data and companion APIs.
  """
  @spec set_simulator_settings(String.t(), Types.simulator_settings()) :: {:ok, runtime_state()}
  def set_simulator_settings(project_slug, attrs \\ %{})
      when is_binary(project_slug) and is_map(attrs) do
    settings = normalize_simulator_settings(attrs)

    update(project_slug, fn state ->
      previous_settings = Map.get(state, :simulator_settings) || %{}

      state
      |> ensure_phone_state()
      |> Map.put(:simulator_settings, settings)
      |> apply_simulator_settings_to_surfaces()
      |> append_event(
        "debugger.simulator_settings_set",
        Ide.Debugger.Types.SimulatorSettingsSetEventPayload.from_settings(settings)
      )
      |> maybe_apply_simulator_settings_geolocation_response()
      |> maybe_apply_simulator_settings_companion_bridge_responses()
      |> maybe_reapply_companion_http_commands()
      |> maybe_apply_init_companion_bridge_commands(:companion)
      |> maybe_inject_unobstructed_area_triggers(previous_settings, settings)
      |> maybe_inject_watch_weather_from_simulator_settings(previous_settings, settings)
      |> deliver_simulator_position_to_watch()
    end)
  end

  @doc """
  Merges a finished `elmc check` summary into watch/companion/phone `model` maps and appends
  `debugger.elmc_check` when the session is running. No-op if the debugger is not started.

  Pass `diagnostics: [...]` (same shape as `Ide.Compiler` diagnostics) to also merge  `elmc_diagnostic_preview` into each surface model (first 12 entries, truncated messages).
  """
  @spec ingest_elmc_check(String.t(), Types.compile_ingest_attrs()) :: {:ok, runtime_state()}
  def ingest_elmc_check(project_slug, attrs) when is_binary(project_slug) and is_map(attrs) do
    update(project_slug, fn state ->
      if Map.get(state, :running, false) do
        %{fields: fields, event_type: type, event_payload: payload} =
          CompileIngest.check_plan(attrs)

        state
        |> CompileIngest.merge_fields_into_all_targets(fields)
        |> append_event(type, payload)
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
  @spec ingest_elmc_compile(String.t(), Types.compile_ingest_attrs()) :: {:ok, runtime_state()}
  def ingest_elmc_compile(project_slug, attrs) when is_binary(project_slug) and is_map(attrs) do
    update(project_slug, fn state ->
      if Map.get(state, :running, false) do
        %{
          fields: fields,
          event_type: type,
          event_payload: payload,
          artifact_fields: artifact_fields,
          artifact_target: artifact_target
        } = CompileIngest.compile_plan(attrs)

        state
        |> CompileIngest.merge_fields_into_all_targets(fields)
        |> maybe_merge_runtime_artifacts(artifact_target, artifact_fields)
        |> refresh_runtime_previews_from_artifacts()
        |> append_event(type, payload)
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
  @spec ingest_elmc_manifest(String.t(), Types.compile_ingest_attrs()) :: {:ok, runtime_state()}
  def ingest_elmc_manifest(project_slug, attrs) when is_binary(project_slug) and is_map(attrs) do
    update(project_slug, fn state ->
      if Map.get(state, :running, false) do
        %{fields: fields, event_type: type, event_payload: payload} =
          CompileIngest.manifest_plan(attrs)

        state
        |> CompileIngest.merge_fields_into_all_targets(fields)
        |> append_event(type, payload)
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
    snapshot_surface = RuntimeArtifacts.normalize_surface(snapshot_runtime)
    latest_surface = RuntimeArtifacts.normalize_surface(latest_runtime)

    snapshot_model = Map.get(snapshot_surface, :model) || %{}
    latest_model = Map.get(latest_surface, :model) || %{}

    app_model = merge_latest_runtime_render_inputs(snapshot_model, latest_model)

    execution_model =
      RuntimeArtifacts.shell_map(latest_surface)
      |> Map.merge(RuntimeArtifacts.shell_map(snapshot_surface))
      |> Map.merge(RuntimeArtifacts.strip_shell_artifacts(app_model))

    introspect = RuntimeArtifacts.introspect(execution_model)
    artifacts = RuntimeArtifacts.execution_artifacts(execution_model)

    view_tree =
      Map.get(snapshot_runtime, :view_tree) || Map.get(snapshot_runtime, "view_tree") || %{}

    latest_view_tree =
      Map.get(latest_runtime, :view_tree) || Map.get(latest_runtime, "view_tree") || %{}

    if is_map(introspect) and artifacts != %{} do
      request =
        %{
          source_root: source_root_for_target(target),
          rel_path: Map.get(app_model, "last_path"),
          source: "",
          introspect: introspect,
          current_model: app_model,
          current_view_tree: view_tree
        }
        |> Map.merge(artifacts)
        |> RuntimeArtifacts.put_vector_resource_indices_on_request(execution_model)
        |> RuntimeArtifacts.put_bitmap_resource_indices_on_request(execution_model)

      case runtime_executor_module().execute(request) do
        {:ok, payload} when is_map(payload) ->
          model_patch =
            payload
            |> Map.get(:model_patch, %{})
            |> then(fn patch -> if is_map(patch), do: patch, else: %{} end)

          runtime_view_output =
            preferred_runtime_view_output(
              Map.get(payload, :view_output),
              Map.get(app_model, "runtime_view_output") || Map.get(app_model, :runtime_view_output)
            )

          next_model =
            app_model
            |> Map.put("elm_executor_mode", "runtime_executed")
            |> Map.merge(model_patch)
            |> put_runtime_view_output(runtime_view_output)

          runtime_view_tree =
            choose_runtime_preview_view_tree(
              Map.get(payload, :view_tree),
              latest_view_tree,
              view_tree,
              runtime_view_output,
              RuntimeArtifacts.require_introspect(next_model)
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

  @spec reload(String.t(), Types.reload_attrs()) :: {:ok, runtime_state()}
  def reload(project_slug, attrs \\ %{}) when is_binary(project_slug) and is_map(attrs) do
    rel_path = Map.get(attrs, :rel_path) || Map.get(attrs, "rel_path")
    reason = Map.get(attrs, :reason) || Map.get(attrs, "reason") || "manual"
    source = Map.get(attrs, :source) || Map.get(attrs, "source") || ""
    source_root = normalize_source_root(attrs)

    update(project_slug, fn state ->
      state
      |> ensure_phone_state()
      |> attach_vector_resource_indices(project_slug)
      |> attach_bitmap_resource_indices(project_slug)
      |> apply_hot_reload(rel_path, source, reason, source_root)
      |> deliver_simulator_weather_to_watch()
      |> attach_companion_configuration(project_slug)
    end)
  end

  @doc """
  Applies deterministic debugger step events for a target runtime.
  """
  @spec step(String.t(), Types.step_attrs()) :: {:ok, runtime_state()}
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
  @spec save_configuration(String.t(), Types.save_configuration_attrs()) :: {:ok, runtime_state()}
  def save_configuration(project_slug, values) when is_binary(project_slug) and is_map(values) do
    update(project_slug, fn state ->
      previous_values =
        get_in(state, [:companion, :model, "configuration", "values"]) ||
          get_in(state, [:companion, :model, "runtime_model", "configuration", "values"]) ||
          %{}

      state = attach_companion_configuration(ensure_phone_state(state), project_slug)

      configuration =
        get_in(state, [:companion, :model, "configuration"]) ||
          get_in(state, [:companion, :model, "runtime_model", "configuration"]) ||
          %{}

      previous_encoded_values = encode_configuration_values(configuration, previous_values)
      encoded_values = encode_configuration_values(configuration, values)
      changed_values = changed_configuration_values(encoded_values, previous_encoded_values)

      bridge_event = %{
        "event" => "configuration.closed",
        "payload" => %{
          "response" => Jason.encode!(encoded_values)
        }
      }

      {configuration_message, configuration_message_value} =
        configuration_message_payload(state, encoded_values, bridge_event)

      seq_before_configuration_update = Map.get(state, :seq, 0)

      state =
      state
      |> apply_step_once(
        :companion,
          configuration_message,
          configuration_message_value,
        "configuration",
        "configuration"
      )

      state
      |> maybe_apply_configuration_protocol_messages(
        configuration,
        changed_values,
        seq_before_configuration_update
      )
      |> attach_companion_configuration(project_slug)
      |> put_companion_configuration_values(encoded_values)
      |> refresh_runtime_preview_for_target(:watch)
    end)
  end

  @spec maybe_apply_configuration_protocol_messages(map(), runtime_state(), map(), non_neg_integer()) ::
          map()
  defp maybe_apply_configuration_protocol_messages(state, configuration, values, seq_before)
       when is_map(state) and is_map(configuration) and is_map(values) and is_integer(seq_before) do
    if configuration_protocol_events_applied?(state, seq_before) do
      state
    else
      apply_configuration_protocol_messages(state, configuration, values)
    end
  end

  defp maybe_apply_configuration_protocol_messages(state, _configuration, _values, _seq_before),
    do: state

  @spec configuration_protocol_events_applied?(map(), non_neg_integer()) :: boolean()
  defp configuration_protocol_events_applied?(state, seq_before)
       when is_map(state) and is_integer(seq_before) do
    state
    |> Map.get(:events, [])
    |> Enum.any?(fn
      %{seq: seq, type: type, payload: payload} ->
        is_integer(seq) and seq > seq_before and
          type in ["debugger.protocol_tx", "debugger.protocol_rx"] and is_map(payload) and
          (Map.get(payload, :trigger) || Map.get(payload, "trigger")) == "configuration" and
          (Map.get(payload, :from) || Map.get(payload, "from")) == "companion" and
          (Map.get(payload, :to) || Map.get(payload, "to")) == "watch"

      %{"seq" => seq, "type" => type, "payload" => payload} ->
        is_integer(seq) and seq > seq_before and
          type in ["debugger.protocol_tx", "debugger.protocol_rx"] and is_map(payload) and
          (Map.get(payload, :trigger) || Map.get(payload, "trigger")) == "configuration" and
          (Map.get(payload, :from) || Map.get(payload, "from")) == "companion" and
          (Map.get(payload, :to) || Map.get(payload, "to")) == "watch"

      _ ->
        false
    end)
  end

  defp configuration_protocol_events_applied?(_state, _seq_before), do: false

  @spec configuration_message_payload(map(), map(), map()) :: {String.t(), map()}
  defp configuration_message_payload(state, encoded_values, bridge_event)
       when is_map(state) and is_map(encoded_values) and is_map(bridge_event) do
    case configuration_subscription_callback(state) do
      callback when is_binary(callback) and callback != "" ->
        {callback, subscription_ok_message_value(callback, encoded_values)}

      _ ->
        {"FromBridge", %{"ctor" => "FromBridge", "args" => [bridge_event]}}
    end
  end

  defp configuration_message_payload(_state, _encoded_values, bridge_event),
    do: {"FromBridge", %{"ctor" => "FromBridge", "args" => [bridge_event]}}

  @spec configuration_subscription_callback(map()) :: String.t() | nil
  defp configuration_subscription_callback(state) when is_map(state) do
    subscription_callback_from_state(state, :companion, @configuration_subscription_contract)
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
  @spec replay_recent(String.t(), Types.replay_attrs()) :: {:ok, runtime_state()}
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
        replayed_count = length(replay_messages)

        replay_payload =
          Ide.Debugger.Types.ReplayEventPayload.build(
            replay_target_label(target),
            requested_count,
            replayed_count,
            replay_source,
            cursor_seq,
            Ide.Debugger.Types.ReplayEventPayload.telemetry(
              replay_mode,
              replay_source,
              replay_drift_seq,
              replay_target_label(target),
              requested_count,
              replayed_count
            ),
            replay_messages
          )

        append_event(replayed, "debugger.replay", replay_payload)
      else
        state
      end
    end)
  end

  @doc """
  Materializes a historical event snapshot into the live tip state, so subsequent
  step/tick operations continue from that selected debugger snapshot.
  """
  @spec continue_from_snapshot(String.t(), Types.snapshot_continue_attrs()) :: {:ok, runtime_state()}
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
        |> append_event(
          "debugger.snapshot_continue",
          Ide.Debugger.Types.SnapshotContinueEventPayload.from_cursor(
            resolved_seq,
            "cursor_snapshot"
          )
        )
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
  @spec trigger_candidates(runtime_state() | map(), :watch | :companion | :phone | nil) ::
          [Types.trigger_candidate()]
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
  @spec inject_trigger(String.t(), Types.inject_trigger_attrs()) :: {:ok, runtime_state()}
  def inject_trigger(project_slug, attrs \\ %{}) when is_binary(project_slug) and is_map(attrs) do
    target = normalize_step_target(Map.get(attrs, :target) || Map.get(attrs, "target"))
    trigger = to_string(Map.get(attrs, :trigger) || Map.get(attrs, "trigger") || "trigger")
    requested_message = Map.get(attrs, :message) || Map.get(attrs, "message")
    requested_message_value = Map.get(attrs, :message_value) || Map.get(attrs, "message_value")

    update(project_slug, fn state ->
      if Map.get(state, :running, false) do
        if subscription_trigger_disabled?(state, target, trigger) do
          append_event(
            state,
            "debugger.subscription_toggle",
            Ide.Debugger.Types.SubscriptionToggleEventPayload.blocked(
              source_root_for_target(target),
              trigger
            )
          )
        else
          resolved_message =
            trigger_message_for_surface(state, target, trigger, requested_message)

          resolved_message_value =
            subscription_trigger_message_value(resolved_message, requested_message_value)

          row = %{
            trigger: trigger,
            message: resolved_message,
            target: source_root_for_target(target)
          }

          if subscription_model_active?(state, target, row) do
          apply_step_once(
            state,
            target,
            resolved_message,
            resolved_message_value,
            "subscription_trigger",
            "subscription_trigger"
          )
          else
            append_event(
              state,
              "debugger.subscription_toggle",
              Ide.Debugger.Types.SubscriptionToggleEventPayload.blocked_inactive(
                source_root_for_target(target),
                trigger,
                resolved_message
              )
            )
          end
        end
      else
        state
      end
    end)
  end

  @doc """
  Whether the debugger trigger modal can faithfully edit payloads for this subscription row.

  Simulator-backed subscriptions are always allowed. Otherwise we require an Elm `Msg`
  constructor present in `elm_introspect.msg_constructor_arities` with arity 0 or 1.

  Gateway subscriptions that deliver opaque variant payloads (e.g. phone↔watch) are excluded:
  the modal cannot enumerate every constructor payload without structured metadata.
  """
  @spec subscription_trigger_injection_modal_supported?(runtime_state(), map()) :: boolean()
  def subscription_trigger_injection_modal_supported?(state, row)
      when is_map(state) and is_map(row) do
    trigger =
      trigger_candidate_field(row, :trigger)
      |> to_string()
      |> String.trim()

    target_s =
      trigger_candidate_field(row, :target)
      |> to_string()
      |> String.trim()

    message = trigger_candidate_field(row, :message)

    cond do
      trigger == "" ->
        false

      opaque_gateway_subscription_trigger?(trigger) ->
        false

      debugger_subscription_simulated_payload_trigger?(trigger) ->
        true

      Ide.Debugger.CompanionSubscriptionTrigger.companion_trigger?(trigger) ->
        true

      true ->
        case trigger_row_constructor_message(message) do
          nil ->
            false

          constructor ->
            target_atom = normalize_step_target(target_s)

            case introspect_for(state, target_atom) do
              %{"msg_constructor_arities" => %{} = arities} when map_size(arities) > 0 ->
                case Map.fetch(arities, constructor) do
                  {:ok, arity} when is_integer(arity) and arity >= 0 and arity <= 1 ->
                    true

                  _ ->
                    false
                end

              _ ->
                false
            end
        end
    end
  end

  def subscription_trigger_injection_modal_supported?(_state, _row), do: false

  @spec trigger_candidate_field(map(), atom()) :: Types.wire_input() | nil
  defp trigger_candidate_field(row, key) when is_map(row) and is_atom(key) do
    Map.get(row, key) || Map.get(row, Atom.to_string(key))
  end

  @spec trigger_row_constructor_message(Types.wire_input()) :: String.t() | nil
  defp trigger_row_constructor_message(message) when is_binary(message) do
    trimmed = String.trim(message)
    if trimmed == "", do: nil, else: trimmed
  end

  defp trigger_row_constructor_message(_message), do: nil

  @opaque_gateway_subscription_triggers ~w(phonetowatch watchtophone)

  @spec opaque_gateway_subscription_trigger?(String.t()) :: boolean()
  defp opaque_gateway_subscription_trigger?(trigger) when is_binary(trigger) do
    normalized =
      trigger
      |> String.downcase()
      |> String.replace(~r/[^a-z0-9]/, "")

    Enum.any?(@opaque_gateway_subscription_triggers, &String.contains?(normalized, &1))
  end

  @spec debugger_subscription_simulated_payload_trigger?(String.t()) :: boolean()
  defp debugger_subscription_simulated_payload_trigger?(trigger) when is_binary(trigger) do
    normalized = String.downcase(trigger)

    contains_any?(normalized, ["on_minute_change", "onminutechange"]) or
      contains_any?(normalized, ["on_hour_change", "onhourchange"]) or
      contains_any?(normalized, ["on_day_change", "ondaychange"]) or
      contains_any?(normalized, ["on_month_change", "onmonthchange"]) or
      contains_any?(normalized, ["on_year_change", "onyearchange"]) or
      contains_any?(normalized, ["on_battery_change", "onbatterychange"]) or
      contains_any?(normalized, ["on_connection_change", "onconnectionchange"]) or
      contains_any?(normalized, ["on_second_change", "onsecondchange"]) or
      contains_any?(normalized, ["on_compass_change", "oncompasschange"]) or
      contains_any?(normalized, ["on_app_focus_change", "onappfocuschange"]) or
      contains_any?(normalized, ["on_unobstructed_will_change", "onunobstructedwillchange"]) or
      contains_any?(normalized, ["on_unobstructed_changing", "onunobstructedchanging"]) or
      contains_any?(normalized, ["on_unobstructed_did_change", "onunobstructeddidchange"]) or
      contains_any?(normalized, ["on_dictation_status", "ondictationstatus"]) or
      contains_any?(normalized, ["on_dictation_result", "ondictationresult"])
  end

  @spec subscription_trigger_message_value(String.t(), Types.subscription_payload()) :: Types.subscription_payload()
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
  @spec set_subscription_enabled(String.t(), Types.step_attrs()) :: {:ok, runtime_state()}
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
        |> append_event(
          "debugger.subscription_toggle",
          Ide.Debugger.Types.SubscriptionToggleEventPayload.set_subscription_enabled(
            source_root_for_target(target),
            trigger,
            enabled?,
            disabled_subscriptions
          )
        )
      else
        state
      end
    end)
  end

  @doc """
  Injects deterministic subscription-style tick messages into one or more runtimes.
  """
  @spec tick(String.t(), Types.step_attrs()) :: {:ok, runtime_state()}
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

        append_event(
          ticked,
          "debugger.tick",
          Ide.Debugger.Types.TickEventPayload.from_tick(
            replay_target_label(target),
            count,
            Enum.map(targets, &source_root_for_target/1)
          )
        )
      else
        state
      end
    end)
  end

  @doc """
  Starts automatic deterministic tick ingress at a fixed interval.
  """
  @spec start_auto_tick(String.t(), Types.step_attrs()) :: {:ok, runtime_state()}
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
        |> append_event(
          "debugger.tick_auto",
          Ide.Debugger.Types.TickAutoEventPayload.start(
            replay_target_label(target),
            interval_ms,
            Enum.map(targets, &source_root_for_target/1),
            count
          )
        )
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
      |> append_event("debugger.tick_auto", Ide.Debugger.Types.TickAutoEventPayload.stop())
    end)
  end

  @doc """
  Enables or disables natural subscription event ingress for a single surface.
  """
  @spec set_auto_fire(String.t(), Types.step_attrs()) :: {:ok, runtime_state()}
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
        |> append_event(
          "debugger.tick_auto",
          Ide.Debugger.Types.TickAutoEventPayload.set_auto_fire(
            source_root_for_target(target),
            trigger,
            enabled?,
            Enum.map(targets, &source_root_for_target/1),
            subscriptions
          )
        )
      else
        state
      end
    end)
  end

  @spec export_trace(String.t(), Types.export_trace_opts()) ::
          {:ok, Types.export_trace_result()}
  def export_trace(project_slug, opts \\ []) when is_binary(project_slug) do
    limit = Keyword.get(opts, :event_limit, @history_limit)
    compare_cursor_seq = Keyword.get(opts, :compare_cursor_seq)
    baseline_cursor_seq = Keyword.get(opts, :baseline_cursor_seq)

    limit =
      if is_integer(limit) and limit > 0, do: min(limit, @history_limit), else: @history_limit

    with {:ok, state} <- snapshot(project_slug, event_limit: limit) do
      human_slug = Map.get(state, :project_slug, human_slug_from_session_key(project_slug))

      body =
        export_payload(human_slug, state,
          compare_cursor_seq: compare_cursor_seq,
          baseline_cursor_seq: baseline_cursor_seq
        )

      json = Jason.encode!(body)
      sha = :crypto.hash(:sha256, json) |> Base.encode16(case: :lower)
      {:ok, %{json: json, sha256: sha, byte_size: byte_size(json)}}
    end
  end

  @spec import_trace(String.t(), Types.import_trace_input(), keyword()) ::
          {:ok, runtime_state()} | {:error, term()}
  def import_trace(session_key, input, opts \\ []) when is_binary(session_key) do
    human_slug = human_slug_from_session_key(session_key)

    with {:ok, body} <- decode_import_body(input),
         :ok <- validate_import_body(body),
         :ok <- maybe_match_import_slug(body, human_slug, opts) do
      state =
        body
        |> state_from_import_body()
        |> Map.put(:scope_key, session_key)
        |> Map.put(:project_slug, human_slug)

      :ok = ensure_started()

      Agent.get_and_update(__MODULE__, fn store ->
        previous = Map.get(store, session_key)

        if is_map(previous) do
          _ = stop_auto_tick_worker(previous)
        end

        {state, Map.put(store, session_key, ensure_phone_state(state))}
      end)

      {:ok, state}
    end
  end

  @spec snapshot(String.t(), Types.snapshot_opts()) :: {:ok, runtime_state()}
  def snapshot(project_slug, opts \\ []) when is_binary(project_slug) do
    limit = Keyword.get(opts, :event_limit, 50)
    types = Keyword.get(opts, :types)
    since_seq = Keyword.get(opts, :since_seq)
    :ok = ensure_started()

    state =
      Agent.get(__MODULE__, fn store ->
        store
        |> get_or_default_state(project_slug)
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
      Agent.get_and_update(
        __MODULE__,
        fn store ->
        current =
          store
          |> get_or_default_state(project_slug)
          |> ensure_phone_state()

        next = updater.(current)
        {next, Map.put(store, project_slug, next)}
        end,
        @agent_call_timeout_ms
      )

    {:ok, updated}
  end

  @spec get_or_default_state(map(), String.t()) :: runtime_state()
  defp get_or_default_state(store, project_slug) when is_map(store) and is_binary(project_slug) do
    case Map.fetch(store, project_slug) do
      {:ok, state} -> state
      :error -> default_state(project_slug)
    end
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

  # Payload shapes per event `type` are defined in `RuntimeEventPayload` and built via
  # `Ide.Debugger.Types.*EventPayload` modules (see `RuntimeEventPayload.known_event_types/0`).
  @spec append_event(runtime_state(), String.t(), EventPayload.t()) :: runtime_state()
  defp append_event(state, type, payload) do
    seq = state.seq + 1

    event =
      RuntimeEvent.build(seq, type, payload, %{
        watch: Map.get(state, :watch, %{}),
        companion: Map.get(state, :companion, %{}),
        phone: Map.get(state, :phone, %{})
      })

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

  @spec maybe_trim_events(runtime_state(), pos_integer() | Types.wire_input()) :: runtime_state()
  defp maybe_trim_events(state, limit) when is_integer(limit) and limit > 0 do
    %{state | events: Enum.take(state.events, limit)}
  end

  defp maybe_trim_events(state, _limit), do: state

  @spec apply_step_once(runtime_state(), Types.surface_target(), String.t(), String.t() | nil, String.t()) :: runtime_state()
  defp apply_step_once(state, target, requested_message, source_override, trigger)
       when target in [:watch, :companion, :phone] do
    apply_step_once(state, target, requested_message, nil, source_override, trigger)
  end

  @spec apply_step_once(
          runtime_state(),
          Types.surface_target(),
          String.t(),
          Types.subscription_payload(),
          String.t() | nil,
          String.t(),
          keyword()
        ) :: runtime_state()
  defp apply_step_once(state, target, requested_message, message_value, source_override, trigger, opts \\ [])
       when target in [:watch, :companion, :phone] and is_list(opts) do
    suppress_protocol_events? = Keyword.get(opts, :suppress_protocol_events, false)
    state = ensure_surface_compile_artifacts(state, target)
    surface = Surface.from_state(state, target)

    model =
      surface
      |> Surface.app_model()
      |> hydrate_runtime_model_for_message(nil, [])

    surface = Surface.put_app_model(surface, model)
    execution_model = Surface.execution_model(surface)

    {message, msg_source, known_messages, update_branches, next_cursor} =
      resolve_step_message(execution_model, requested_message)

    message_value =
      if is_map(message_value) do
        normalize_protocol_subscription_message_value(state, target, message_value, model)
      else
        message_value
      end

    step =
      StepInput.from_surface(target, surface, message,
        message_value: message_value,
        trigger: trigger,
        message_source: source_override
      )

    runtime_result = step_runtime_result(step, update_branches)

    runtime_patch = Map.get(runtime_result, :model_patch, %{})
    runtime_patch = normalize_runtime_patch_values(step.execution_model, runtime_patch)
    runtime_view_tree = Map.get(runtime_result, :view_tree)
    runtime_view_tree = if is_map(runtime_view_tree), do: runtime_view_tree, else: step.view_tree

    preview_runtime_model =
      model
      |> Types.StepExecutionContract.merge_model_patch(runtime_patch)
      |> RuntimeArtifacts.preview_runtime_model()

    runtime_view_output =
      preferred_runtime_view_output(
        Map.get(runtime_result, :view_output),
        Map.get(model, "runtime_view_output") || Map.get(model, :runtime_view_output)
      )
      |> then(fn rows ->
        supplemented =
          supplement_parser_runtime_view_output(
            step.execution_model,
            runtime_view_tree,
            preview_runtime_model
          )

        choose_runtime_view_output(rows, supplemented)
      end)

    message_source = source_override || msg_source

    runtime_protocol_events = Map.get(runtime_result, :protocol_events, [])

    model_for_protocol =
      model
      |> Types.StepExecutionContract.merge_model_patch(runtime_patch)
      |> hydrate_runtime_model_for_message(message, [])

    command_protocol_events =
      cond do
        runtime_protocol_events == [] ->
          protocol_events_for_model_commands(
            state,
            model_for_protocol,
            target,
            message,
            message_value
          )

        true ->
          []
      end

    runtime_followups = Map.get(runtime_result, :followup_messages, [])

    protocol_events =
      (runtime_protocol_events ++ command_protocol_events)
      |> normalize_protocol_events_from_schema(state)
      |> enrich_protocol_events(trigger, message_source)

    introspect = introspect_for(state, target)

    protocol_runtime_patch =
      subscription_payload_model_patch(introspect, message_value)
      |> Map.merge(protocol_runtime_model_patch_from_message_value(introspect, message_value))

    updated_model =
      model
      |> Types.StepExecutionContract.merge_model_patch(runtime_patch)
      |> merge_protocol_runtime_model_patch(
        protocol_runtime_patch,
        introspect_for(state, target)
      )
      |> hydrate_runtime_model_for_message(message, patched_runtime_model_fields(runtime_patch))
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
        step.view_tree,
        target,
        message,
        trigger,
        updated_model
      )

    updated_state =
      state
      |> Surface.put_in_state(
        target,
        step.surface
        |> Surface.put_app_model(updated_model)
        |> Surface.put_view_tree(rendered_view_tree)
        |> Surface.put_last_message(message)
      )

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
      |> append_event(
        "debugger.update_in",
        Ide.Debugger.Types.MessageInEventPayload.from_message(
          target_name,
          message,
          message_source
        )
      )
      |> append_debugger_event("update", target, message, message_source)
      |> maybe_append_runtime_status_debugger_event(target)
      |> maybe_apply_protocol_side_effects(protocol_events, suppress_protocol_events?)
      |> append_event(
        "debugger.view_render",
        Ide.Debugger.Types.ViewRenderEventPayload.from_render(target_name, root)
      )

    updated_state =
      maybe_apply_device_data_responses(
        updated_state,
        target,
        message,
        updated_model,
        message_source
      )
      |> maybe_apply_geolocation_response(target, message, updated_model, message_source)
      |> maybe_apply_companion_bridge_command_responses(
        target,
        message,
        updated_model,
        message_source
      )
      |> maybe_apply_companion_bridge_responses(target, message_source)
      |> maybe_apply_static_task_followups(target, message, message_value, message_source)

    maybe_apply_runtime_followups(
      updated_state,
      target,
      message,
      message_source,
      runtime_followups
    )
  end

  @spec maybe_apply_device_data_responses(runtime_state(), Types.surface_target(), String.t(), map(), String.t()) :: runtime_state()
  defp maybe_apply_device_data_responses(state, _target, _message, _model, "configuration"),
    do: state

  defp maybe_apply_device_data_responses(state, target, message, model, _message_source)
       when target in [:watch, :companion, :phone] and is_binary(message) and is_map(model) do
    device_requests_for_model(state, target, message)
    |> Enum.reduce(state, fn req, acc ->
      target_name = source_root_for_target(target)

      acc
      |> apply_device_data_hint(target, req)
      |> append_event(
        "debugger.device_data",
        Ide.Debugger.Types.DeviceDataEventPayload.from_request(target_name, req)
      )
      |> apply_step_once(target, device_response_message(req), "device_data", "device_data")
      |> apply_device_data_hint(target, req)
    end)
  end

  defp maybe_apply_device_data_responses(state, _target, _message, _model, _message_source),
    do: state

  @spec maybe_apply_init_device_data_responses(runtime_state(), Types.surface_target()) :: runtime_state()
  defp maybe_apply_init_device_data_responses(state, target)
       when target in [:watch, :companion, :phone] do
    model = get_in(state, [target, :model]) || %{}
    ei = introspect_for(state, target)

    if is_map(ei) do
      ei
      |> introspect_cmd_calls("init_cmd_calls")
      |> expand_helper_cmd_calls(ei)
      |> Enum.flat_map(&device_request_from_cmd_call/1)
      |> Enum.reject(&init_device_request_deferred_to_runtime?/1)
      |> Enum.uniq_by(fn req -> {req.kind, req.response_message} end)
      |> Enum.map(&finalize_device_request(&1, model))
      |> Enum.reduce(state, fn req, acc ->
        target_name = source_root_for_target(target)

        acc
        |> apply_device_data_hint(target, req)
        |> append_event(
          "debugger.device_data",
          Ide.Debugger.Types.DeviceDataEventPayload.from_request(target_name, req)
        )
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
    ei = introspect_for(state, target)

    if is_map(ei) do
      ei
      |> introspect_cmd_calls("init_cmd_calls")
      |> Enum.flat_map(&protocol_events_from_cmd_call(state, target, &1, model))
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

  @spec maybe_apply_init_geolocation_response(runtime_state(), Types.surface_target()) :: runtime_state()
  defp maybe_apply_init_geolocation_response(state, target)
       when is_map(state) and target in [:watch, :companion, :phone] do
    ei = introspect_for(state, target)

    with true <- geolocation_init_requested?(ei),
         callback when is_binary(callback) and callback != "" <-
           geolocation_subscription_callback(ei) do
      location = debugger_geolocation_location(state)

      state
      |> append_event(
        "debugger.geolocation",
        Ide.Debugger.Types.GeolocationEventPayload.from_response(
          source_root_for_target(target),
          callback,
          location
        )
      )
      |> apply_subscription_ok_response(
        target,
        callback,
        location,
        "init_geolocation",
        "geolocation"
      )
    else
      _ -> state
    end
  end

  defp maybe_apply_init_geolocation_response(state, _target), do: state

  @spec maybe_apply_simulator_settings_geolocation_response(runtime_state()) :: runtime_state()
  defp maybe_apply_simulator_settings_geolocation_response(state) when is_map(state) do
    state
    |> maybe_apply_geolocation_subscription_response(:companion, "simulator_settings")
    |> maybe_apply_geolocation_subscription_response(:watch, "simulator_settings")
  end

  @spec maybe_apply_simulator_settings_companion_bridge_responses(runtime_state()) :: runtime_state()
  defp maybe_apply_simulator_settings_companion_bridge_responses(state) when is_map(state) do
    maybe_apply_companion_bridge_subscription_responses(state, :companion, "simulator_settings")
  end

  @spec maybe_reapply_companion_http_commands(runtime_state()) :: runtime_state()
  defp maybe_reapply_companion_http_commands(state) when is_map(state) do
    weather = simulator_settings_from_state(state)["weather"]

    if is_map(weather) and map_size(weather) > 0 do
      state
      |> companion_tracked_http_commands()
      |> Enum.reduce(state, fn command, acc ->
        apply_runtime_http_followup(
          acc,
          :companion,
          "companion",
          "elm/http",
          command,
          nil
        )
      end)
    else
      state
    end
  end

  @spec companion_tracked_http_commands(runtime_state()) :: [Types.tracked_http_command()]
  defp companion_tracked_http_commands(state) when is_map(state) do
    case get_in(state, [:companion, :tracked_http_commands]) do
      commands when is_list(commands) -> commands
      _ -> []
    end
  end

  @spec track_companion_http_command(runtime_state(), Types.tracked_http_command()) :: runtime_state()
  defp track_companion_http_command(state, %{"kind" => "http"} = command) when is_map(state) do
    key = {Map.get(command, "method"), Map.get(command, "url")}

    tracked =
      state
      |> companion_tracked_http_commands()
      |> Enum.reject(fn existing -> {Map.get(existing, "method"), Map.get(existing, "url")} == key end)

    update_in(state, [:companion, :tracked_http_commands], fn _ ->
      [command | tracked] |> Enum.take(8)
    end)
  end

  defp track_companion_http_command(state, _command), do: state

  @spec maybe_apply_init_companion_bridge_commands(runtime_state(), Types.surface_target()) :: runtime_state()
  defp maybe_apply_init_companion_bridge_commands(state, :companion = target)
       when is_map(state) do
    ei = introspect_for(state, target)

    ei
    |> introspect_cmd_calls("init_cmd_calls")
    |> expand_helper_cmd_calls(ei)
    |> companion_bridge_requests_from_cmd_calls()
    |> apply_companion_bridge_requests(state, target, "init_companion_bridge")
  end

  defp maybe_apply_init_companion_bridge_commands(state, _target), do: state

  @spec maybe_apply_geolocation_response(runtime_state(), Types.surface_target(), String.t(), map(), String.t()) :: runtime_state()
  defp maybe_apply_geolocation_response(state, _target, _message, _model, "geolocation"),
    do: state

  defp maybe_apply_geolocation_response(state, _target, _message, _model, "init_geolocation"),
    do: state

  defp maybe_apply_geolocation_response(state, target, message, _model, _message_source)
       when is_map(state) and target in [:watch, :companion, :phone] and is_binary(message) do
    ei = introspect_for(state, target)
    current_ctor = message_constructor(message)
    callback = geolocation_subscription_callback(ei)

    with true <- is_binary(callback) and callback != "",
         true <- current_ctor != callback,
         true <- geolocation_update_branch_requests_command?(ei, current_ctor) do
      location = debugger_geolocation_location(state)

      state
      |> append_event(
        "debugger.geolocation",
        Ide.Debugger.Types.GeolocationEventPayload.from_response(
          source_root_for_target(target),
          callback,
          location
        )
      )
      |> apply_subscription_ok_response(target, callback, location, "geolocation", "geolocation")
    else
      _ -> state
    end
  end

  defp maybe_apply_geolocation_response(state, _target, _message, _model, _message_source),
    do: state

  @spec maybe_apply_companion_bridge_command_responses(runtime_state(), Types.surface_target(), String.t(), map(), String.t()) ::
          runtime_state()
  defp maybe_apply_companion_bridge_command_responses(
         state,
         :companion = target,
         message,
         model,
         message_source
       )
       when is_map(state) and is_binary(message) and is_map(model) do
    if message_source in ["companion_bridge_command", "init_companion_bridge"] do
      state
    else
      current_ctor = message_constructor(message)
      ei = introspect_for(state, target)

      ei
      |> introspect_cmd_calls("update_cmd_calls")
      |> update_cmd_calls_for_message(current_ctor)
      |> expand_helper_cmd_calls(ei)
      |> companion_bridge_requests_from_cmd_calls()
      |> apply_companion_bridge_requests(state, target, "companion_bridge_command")
    end
  end

  defp maybe_apply_companion_bridge_command_responses(
         state,
         _target,
         _message,
         _model,
         _message_source
       ),
       do: state

  @spec maybe_apply_companion_bridge_responses(runtime_state(), Types.surface_target(), String.t()) :: runtime_state()
  defp maybe_apply_companion_bridge_responses(state, :companion = target, message_source)
       when is_map(state) do
    if message_source in ([
                            "companion_bridge",
                            "companion_bridge_command",
                            "init_companion_bridge",
                            "simulator_settings",
                            "subscription_trigger"
                          ] ++
                            companion_bridge_sources()) do
      state
    else
      maybe_apply_companion_bridge_subscription_responses(state, target, "companion_bridge")
    end
  end

  defp maybe_apply_companion_bridge_responses(state, _target, _message_source), do: state

  @spec maybe_apply_companion_bridge_subscription_responses(runtime_state(), Types.surface_target(), String.t()) :: runtime_state()
  defp maybe_apply_companion_bridge_subscription_responses(state, :companion = target, source)
       when is_map(state) and is_binary(source) do
    Enum.reduce(@companion_bridge_subscription_contracts, state, fn contract, acc ->
      callback = subscription_callback_from_state(acc, target, contract)

      case callback do
        value when is_binary(value) and value != "" ->
          payload = companion_bridge_payload(acc, Map.fetch!(contract, :payload), %{op: "subscribe"})
          trigger = Map.fetch!(contract, :source)

          acc
          |> append_event(
            "debugger.companion_bridge",
            Ide.Debugger.Types.CompanionBridgeEventPayload.from_subscription(
              source_root_for_target(target),
              trigger,
              callback,
              payload
            )
          )
          |> apply_companion_subscription_response(target, callback, payload, source, trigger, contract)

        _ ->
          acc
      end
    end)
  end

  defp maybe_apply_companion_bridge_subscription_responses(state, _target, _source), do: state

  defp companion_bridge_sources do
    Enum.map(@companion_bridge_subscription_contracts, &Map.fetch!(&1, :source))
  end

  @spec companion_bridge_payload(map(), atom(), map()) :: term()
  defp companion_bridge_payload(state, kind, request)

  defp companion_bridge_payload(state, :calendar, request) when is_map(state) and is_map(request) do
    settings = simulator_settings_from_state(state)
    events = settings["calendar_events"]

    case Map.get(request, :op) do
      "nextEvent" -> List.first(events)
      "subscribe" -> events
      _ -> events
    end
  end

  defp companion_bridge_payload(state, :weather, request) when is_map(state) and is_map(request) do
    settings = simulator_settings_from_state(state)
    weather = companion_bridge_weather_info(settings["weather"])

    case Map.get(request, :op) do
      "forecast" -> [weather]
      "subscribe" -> %{"ctor" => "Current", "args" => [weather]}
      _ -> weather
    end
  end

  defp companion_bridge_payload(state, :network, _request) when is_map(state) do
    settings = simulator_settings_from_state(state)
    simulator_bool_setting(settings, "network_online", true)
  end

  defp companion_bridge_payload(state, kind, _request) when is_map(state) do
    settings = simulator_settings_from_state(state)

    case kind do
      :battery ->
        %{"percent" => settings["battery_percent"], "charging" => settings["charging"]}

      :locale ->
        %{
          "locale" => settings["locale"],
          "language" => settings["language"],
          "region" => settings["region"],
          "uses24h" => settings["clock_24h"]
        }

      :notifications ->
        %{
          "quietHours" => settings["quiet_hours"],
          "notificationsEnabled" => settings["notifications_enabled"]
        }

      :environment ->
        settings["environment"]
    end
  end

  @spec companion_bridge_weather_info(map() | nil) :: map()
  defp companion_bridge_weather_info(weather) when is_map(weather) do
    weather
    |> Map.take(["temperatureC", "condition", "humidityPercent", "pressureHpa", "windKph"])
    |> Enum.reject(fn {_key, value} -> is_nil(value) end)
    |> Map.new()
  end

  defp companion_bridge_weather_info(_weather), do: %{}

  @spec companion_bridge_subscription_message_value(String.t(), String.t(), String.t(), term()) ::
          map()
  defp companion_bridge_subscription_message_value("weather", callback, result_ctor, payload) do
    wrapped_payload = wrap_weather_bridge_ok_payload(result_ctor, payload, "Current")
    subscription_result_message_value(callback, result_ctor, wrapped_payload)
  end

  defp companion_bridge_subscription_message_value(_api, callback, result_ctor, payload) do
    subscription_result_message_value(callback, result_ctor, payload)
  end

  @spec wrap_weather_bridge_ok_payload(String.t(), term(), String.t()) :: term()
  defp wrap_weather_bridge_ok_payload("Ok", %{"ctor" => variant, "args" => [info | _]}, _default_variant)
       when is_binary(variant) and is_map(info) do
    %{"ctor" => variant, "args" => [companion_bridge_weather_info(info)]}
  end

  defp wrap_weather_bridge_ok_payload("Ok", info, default_variant) when is_map(info) do
    %{"ctor" => default_variant, "args" => [companion_bridge_weather_info(info)]}
  end

  defp wrap_weather_bridge_ok_payload(_result_ctor, payload, _default_variant), do: payload

  @spec companion_bridge_requests_from_cmd_calls([Types.cmd_call()]) :: [Types.companion_bridge_request()]
  defp companion_bridge_requests_from_cmd_calls(calls),
    do: Ide.Debugger.CompanionBridgeRequest.from_cmd_calls(calls)

  @spec apply_companion_bridge_requests([Types.companion_bridge_request()], map(), :companion, String.t()) :: map()
  defp apply_companion_bridge_requests(requests, state, :companion = target, source)
       when is_list(requests) and is_map(state) and is_binary(source) do
    Enum.reduce(requests, state, &apply_companion_bridge_request(&2, target, &1, source))
  end

  defp apply_companion_bridge_requests(_requests, state, _target, _source), do: state

  @spec apply_companion_bridge_request(Types.companion_bridge_request(), :companion, map(), String.t()) :: map()
  defp apply_companion_bridge_request(state, _target, %{api: "storage", op: op} = request, _source)
       when op in ["set", "remove", "clear"] do
    {next_state, _result} = companion_storage_result(state, request)
    next_state
  end

  defp apply_companion_bridge_request(state, target, %{api: "storage"} = request, source) do
    callback =
      companion_bridge_callback(request, state, target, @storage_result_contract)

    case callback do
      value when is_binary(value) and value != "" ->
        {next_state, result} = companion_storage_result(state, request)

        apply_companion_bridge_callback(
          next_state,
          target,
          callback,
          result,
          source,
          "storage",
          request
        )

      _ ->
        state
    end
  end

  defp apply_companion_bridge_request(state, _target, %{api: "preferences", op: "set"} = request, _source) do
    {next_state, _result} = companion_preferences_result(state, request)
    next_state
  end

  defp apply_companion_bridge_request(state, target, %{api: "preferences"} = request, source) do
    callback =
      companion_bridge_callback(request, state, target, @preferences_result_contract)

    case callback do
      value when is_binary(value) and value != "" ->
        {next_state, result} = companion_preferences_result(state, request)

        apply_companion_bridge_callback(
          next_state,
          target,
          callback,
          result,
          source,
          "preferences",
          request
        )

      _ ->
        state
    end
  end

  defp apply_companion_bridge_request(state, target, %{api: "geolocation"} = request, source) do
    callback =
      companion_bridge_callback(request, state, target, @geolocation_subscription_contract)

    case callback do
      value when is_binary(value) and value != "" ->
        apply_companion_bridge_callback(
          state,
          target,
          callback,
          {:ok, debugger_geolocation_location(state)},
          source,
          "geolocation",
          request
        )

      _ ->
        state
    end
  end

  defp apply_companion_bridge_request(state, target, %{api: "weather"} = request, _source) do
    contract =
      Enum.find(@companion_bridge_subscription_contracts, &(Map.fetch!(&1, :source) == "weather"))

    callback =
      if contract,
        do: companion_bridge_callback(request, state, target, contract),
        else: nil

    payload = companion_bridge_payload(state, :weather, request)

    state
    |> append_event(
      "debugger.companion_bridge",
      Ide.Debugger.Types.CompanionBridgeEventPayload.from_response(
        source_root_for_target(target),
        "weather",
        Map.get(request, :op),
        callback,
        payload,
        "Ok"
      )
    )
    |> deliver_simulator_weather_to_watch()
  end

  defp apply_companion_bridge_request(state, target, %{api: api} = request, source)
       when is_binary(api) and api != "weather" do
    contract =
      Enum.find(@companion_bridge_subscription_contracts, &(Map.fetch!(&1, :source) == api))

    callback =
      if contract,
        do: companion_bridge_callback(request, state, target, contract),
        else: nil

    case {contract, callback} do
      {%{} = found_contract, value} when is_binary(value) and value != "" ->
        payload = companion_bridge_payload(state, Map.fetch!(found_contract, :payload), request)

        apply_companion_bridge_callback(
          state,
          target,
          callback,
          {:ok, payload},
          source,
          api,
          request
        )

      _ ->
        state
    end
  end

  defp apply_companion_bridge_request(state, _target, _request, _source), do: state

  @spec companion_bridge_callback(map(), map(), :companion, map()) :: String.t() | nil
  defp companion_bridge_callback(%{callback: callback}, _state, _target, _contract)
       when is_binary(callback) and callback != "",
       do: callback

  defp companion_bridge_callback(request, state, target, contract) when is_map(request) do
    subscription_callback_from_state(state, target, contract)
  end

  defp apply_companion_bridge_callback(state, target, callback, result, source, api, request)
       when is_map(state) and is_binary(callback) and is_binary(source) and is_binary(api) do
    plain? = Map.get(request, :plain_result) == true

    {result_ctor, payload, message_value} =
      if plain? do
        connectivity =
          case result do
            {:ok, true} ->
              %{"ctor" => "Online", "args" => []}

            {:ok, false} ->
              %{"ctor" => "Offline", "args" => []}

            {:ok, value} ->
              value

            _ ->
              %{"ctor" => "Offline", "args" => []}
          end

        {"plain", connectivity, %{"ctor" => callback, "args" => [connectivity]}}
      else
        {result_ctor, payload} =
          case result do
            {:ok, value} -> {"Ok", value}
            {:error, message} -> {"Err", message}
          end

        message_value =
          companion_bridge_subscription_message_value(api, callback, result_ctor, payload)

        {result_ctor, payload, message_value}
      end

    state
    |> append_event(
      "debugger.companion_bridge",
      Ide.Debugger.Types.CompanionBridgeEventPayload.from_response(
        source_root_for_target(target),
        api,
        Map.get(request, :op),
        callback,
        payload,
        result_ctor
      )
    )
    |> apply_step_once(
      target,
      callback,
      message_value,
      source,
      api
    )
  end

  @spec companion_storage_result(map(), map()) :: {map(), {:ok, map()} | {:error, String.t()}}
  defp companion_storage_result(state, request) when is_map(state) and is_map(request) do
    settings = simulator_settings_from_state(state)
    values = Map.get(settings, "storage_values", %{})
    key = Map.get(request, :key)

    case Map.get(request, :op) do
      "get" ->
        case key && Map.get(values, key) do
          nil -> {state, {:error, "Storage key not found"}}
          value -> {state, {:ok, storage_value_to_elm_value(value)}}
        end

      "set" ->
        stored = command_value_to_storage_value(Map.get(request, :value))

        {put_simulator_setting_nested(state, "storage_values", key, stored),
         {:ok, storage_value_to_elm_value(stored)}}

      "remove" ->
        {put_simulator_setting_nested(state, "storage_values", key, nil),
         {:ok, %{"ctor" => "JsonValue", "args" => [%{}]}}}

      "clear" ->
        {put_simulator_setting(state, "storage_values", %{}),
         {:ok, %{"ctor" => "JsonValue", "args" => [%{}]}}}

      _ ->
        {state, {:error, "Unsupported storage operation"}}
    end
  end

  @spec companion_preferences_result(map(), map()) ::
          {map(), {:ok, term()} | {:error, String.t()}}
  defp companion_preferences_result(state, request) when is_map(state) and is_map(request) do
    settings = simulator_settings_from_state(state)
    values = Map.get(settings, "preferences", %{})
    key = Map.get(request, :key)

    case Map.get(request, :op) do
      "get" ->
        value = if key, do: Map.get(values, key), else: nil
        {state, {:ok, {key || "", value}}}

      "set" ->
        value = command_json_value(Map.get(request, :value))

        {put_simulator_setting_nested(state, "preferences", key, value),
         {:ok, {key || "", value}}}

      "subscribe" ->
        {state, {:ok, {"", values}}}

      _ ->
        {state, {:error, "Unsupported preferences operation"}}
    end
  end

  defp storage_value_to_elm_value(%{"kind" => "string", "value" => value}) when is_binary(value),
    do: %{"ctor" => "StringValue", "args" => [value]}

  defp storage_value_to_elm_value(%{"kind" => "int", "value" => value}) when is_integer(value),
    do: %{"ctor" => "IntValue", "args" => [value]}

  defp storage_value_to_elm_value(%{"kind" => "bool", "value" => value}) when is_boolean(value),
    do: %{"ctor" => "BoolValue", "args" => [value]}

  defp storage_value_to_elm_value(%{"kind" => "json", "value" => value}),
    do: %{"ctor" => "JsonValue", "args" => [value]}

  defp storage_value_to_elm_value(value), do: %{"ctor" => "JsonValue", "args" => [value]}

  defp command_value_to_storage_value(%{"$ctor" => ctor, "$args" => [value | _]})
       when ctor in ["StringValue", "Storage.StringValue"] and is_binary(value),
       do: %{"kind" => "string", "value" => value}

  defp command_value_to_storage_value(%{"$ctor" => ctor, "$args" => [value | _]})
       when ctor in ["IntValue", "Storage.IntValue"] and is_integer(value),
       do: %{"kind" => "int", "value" => value}

  defp command_value_to_storage_value(%{"$ctor" => ctor, "$args" => [value | _]})
       when ctor in ["BoolValue", "Storage.BoolValue"] and is_boolean(value),
       do: %{"kind" => "bool", "value" => value}

  defp command_value_to_storage_value(%{"$ctor" => _ctor, "$args" => [value | _]}),
    do: %{"kind" => "json", "value" => value}

  defp command_value_to_storage_value(value), do: %{"kind" => "json", "value" => value}

  defp command_json_value(%{"$call" => target, "$args" => [value | _]})
       when is_binary(target) do
    cond do
      String.ends_with?(target, ".string") and is_binary(value) -> value
      String.ends_with?(target, ".int") and is_integer(value) -> value
      String.ends_with?(target, ".bool") and is_boolean(value) -> value
      true -> %{"$call" => target, "$args" => [value]}
    end
  end

  defp command_json_value(value), do: value

  defp put_simulator_setting(state, key, value) when is_map(state) and is_binary(key) do
    settings =
      state
      |> simulator_settings_from_state()
      |> Map.put(key, value)
      |> normalize_simulator_settings()

    Map.put(state, :simulator_settings, settings)
  end

  defp put_simulator_setting_nested(state, _key, nil, _value), do: state

  defp put_simulator_setting_nested(state, key, child_key, nil)
       when is_map(state) and is_binary(key) and is_binary(child_key) do
    values =
      state
      |> simulator_settings_from_state()
      |> Map.get(key, %{})
      |> Map.delete(child_key)

    put_simulator_setting(state, key, values)
  end

  defp put_simulator_setting_nested(state, key, child_key, value)
       when is_map(state) and is_binary(key) and is_binary(child_key) do
    values =
      state
      |> simulator_settings_from_state()
      |> Map.get(key, %{})
      |> Map.put(child_key, value)

    put_simulator_setting(state, key, values)
  end

  @spec maybe_apply_geolocation_subscription_response(runtime_state(), Types.surface_target(), String.t()) :: runtime_state()
  defp maybe_apply_geolocation_subscription_response(state, target, source)
       when is_map(state) and target in [:watch, :companion, :phone] and is_binary(source) do
    ei = introspect_for(state, target)
    callback = geolocation_subscription_callback(ei)

    if is_binary(callback) and callback != "" do
      location = debugger_geolocation_location(state)

      state
      |> append_event(
        "debugger.geolocation",
        Ide.Debugger.Types.GeolocationEventPayload.from_response(
          source_root_for_target(target),
          callback,
          location
        )
      )
      |> apply_subscription_ok_response(target, callback, location, source, "geolocation")
    else
      state
    end
  end

  defp maybe_apply_geolocation_subscription_response(state, _target, _source), do: state

  @spec geolocation_update_branch_requests_command?(map(), String.t() | nil) :: boolean()
  defp geolocation_update_branch_requests_command?(ei, current_ctor)
       when is_map(ei) and is_binary(current_ctor) and current_ctor != "" do
    ei
    |> introspect_cmd_calls("update_cmd_calls")
    |> update_cmd_calls_for_message(current_ctor)
    |> Enum.any?(fn row ->
      cmd_call_requests_geolocation?(ei, row)
    end)
  end

  defp geolocation_update_branch_requests_command?(_ei, _current_ctor), do: false

  @spec cmd_call_requests_geolocation?(Types.cmd_call(), map()) :: boolean()
  defp cmd_call_requests_geolocation?(ei, row) when is_map(ei) and is_map(row) do
    cond do
      cmd_call_name?(row, "currentPosition") or
          cmd_call_target_ends_with?(row, ".currentPosition") ->
        true

      true ->
        helper_name = Map.get(row, "target") || Map.get(row, "name")

        ei
        |> Map.get("function_cmd_calls", %{})
        |> case do
          helpers when is_map(helpers) -> Map.get(helpers, helper_name, [])
          _ -> []
        end
        |> Enum.any?(
          &(cmd_call_name?(&1, "currentPosition") or
              cmd_call_target_ends_with?(&1, ".currentPosition"))
        )
    end
  end

  defp cmd_call_requests_geolocation?(_ei, _row), do: false

  @spec geolocation_init_requested?(map()) :: boolean()
  defp geolocation_init_requested?(ei) when is_map(ei) do
    init_requested? =
      ei
      |> introspect_cmd_calls("init_cmd_calls")
      |> Enum.any?(fn row ->
        cmd_call_name?(row, "currentPosition") or
          cmd_call_target_ends_with?(row, ".currentPosition")
      end)

    # The debugger cannot always statically inline local command helpers. A
    # declared geolocation subscription is still a clear app-level contract that
    # the companion can receive a current-position result.
    init_requested? or is_binary(geolocation_subscription_callback(ei))
  end

  defp geolocation_init_requested?(_ei), do: false

  @spec geolocation_subscription_callback(map()) :: String.t() | nil
  defp geolocation_subscription_callback(ei) when is_map(ei) do
    subscription_callback(ei, @geolocation_subscription_contract)
  end

  defp geolocation_subscription_callback(_ei), do: nil

  @spec cmd_call_name?(map(), String.t()) :: boolean()
  defp cmd_call_name?(row, name) when is_map(row) and is_binary(name),
    do: Map.get(row, "name") == name

  defp cmd_call_name?(_row, _name), do: false

  @spec cmd_call_target_ends_with?(map(), String.t()) :: boolean()
  defp cmd_call_target_ends_with?(row, suffix) when is_map(row) and is_binary(suffix) do
    case Map.get(row, "target") do
      target when is_binary(target) -> String.ends_with?(target, suffix)
      _ -> false
    end
  end

  defp cmd_call_target_ends_with?(_row, _suffix), do: false

  @spec debugger_geolocation_location(runtime_state() | map()) :: map()
  defp debugger_geolocation_location(state) when is_map(state) do
    settings =
      state
      |> Map.get(:simulator_settings)
      |> normalize_simulator_settings()

    {lat, lon, accuracy} = SimulatorSettings.geolocation(settings)

    %{
      "latitude" => lat,
      "longitude" => lon,
      "accuracy" => accuracy
    }
  end

  @spec geolocation_simulator_wire_int(ProtocolResolutionCtx.t() | map()) :: integer() | nil
  defp geolocation_simulator_wire_int(ctx) when is_map(ctx) do
    with %{} = settings <- Map.get(ctx, :simulator_settings),
         index when is_integer(index) <- Map.get(ctx, :arg_index) do
      {lat, lon, accuracy} = SimulatorSettings.geolocation(settings)

      case index do
        0 -> micro_degrees_from_float(lat)
        1 -> micro_degrees_from_float(lon)
        2 -> round_float(accuracy)
        _ -> nil
      end
    else
      _ -> nil
    end
  end

  @spec micro_degrees_from_float(term()) :: integer() | nil
  defp micro_degrees_from_float(value) when is_number(value), do: round(value * 1_000_000)
  defp micro_degrees_from_float(_value), do: nil

  @spec round_float(term()) :: integer() | nil
  defp round_float(value) when is_integer(value), do: value
  defp round_float(value) when is_float(value), do: round(value)
  defp round_float(_value), do: nil

  @spec apply_companion_subscription_response(
          map(),
          :watch | :companion | :phone,
          String.t(),
          term(),
          String.t(),
          String.t(),
          map()
        ) :: map()
  defp apply_companion_subscription_response(
         state,
         :companion = _target,
         callback,
         payload,
         source,
         "weather" = _trigger,
         _contract
       )
       when is_map(state) and is_binary(callback) and is_binary(source) do
    state
    |> append_event(
      "debugger.companion_bridge",
      Ide.Debugger.Types.CompanionBridgeEventPayload.from_subscription(
        source_root_for_target(:companion),
        "weather",
        callback,
        payload
      )
    )
    |> deliver_simulator_weather_to_watch()
  end

  defp apply_companion_subscription_response(
         state,
         target,
         callback,
         payload,
         source,
         trigger,
         contract
       )
       when is_map(state) and target in [:watch, :companion, :phone] and is_binary(callback) and
              is_binary(source) and is_binary(trigger) and is_map(contract) do
    if Map.get(contract, :plain_result) == true do
      connectivity =
        cond do
          payload == true ->
            %{"ctor" => "Online", "args" => []}

          payload == false ->
            %{"ctor" => "Offline", "args" => []}

          is_map(payload) ->
            payload

          true ->
            %{"ctor" => "Offline", "args" => []}
        end

      apply_step_once(
        state,
        target,
        callback,
        %{"ctor" => callback, "args" => [connectivity]},
        source,
        trigger
      )
    else
      apply_subscription_ok_response(state, target, callback, payload, source, trigger)
    end
  end

  @spec subscription_ok_message_value(String.t(), Types.subscription_payload()) :: map()
  defp subscription_ok_message_value(callback, payload) when is_binary(callback) do
    subscription_result_message_value(callback, "Ok", payload)
  end

  @spec apply_subscription_ok_response(
          map(),
          :watch | :companion | :phone,
          String.t(),
          term(),
          String.t(),
          String.t()
        ) :: map()
  defp apply_subscription_ok_response(state, target, callback, payload, source, trigger)
       when is_map(state) and target in [:watch, :companion, :phone] and is_binary(callback) and
              is_binary(source) and is_binary(trigger) do
    apply_step_once(
      state,
      target,
      callback,
      subscription_ok_message_value(callback, payload),
      source,
      trigger
    )
  end

  @spec subscription_result_message_value(String.t(), String.t(), Types.subscription_payload()) :: map()
  defp subscription_result_message_value(callback, result_ctor, payload)
       when is_binary(callback) and is_binary(result_ctor) do
    %{
      "ctor" => callback,
      "args" => [
        %{
          "ctor" => result_ctor,
          "args" => [payload]
        }
      ]
    }
  end

  @spec subscription_callback_from_state(map(), :watch | :companion | :phone, map()) ::
          String.t() | nil
  defp subscription_callback_from_state(state, target, contract)
       when is_map(state) and target in [:watch, :companion, :phone] and is_map(contract) do
    state
    |> introspect_for(target)
    |> subscription_callback(contract)
  end

  defp subscription_callback_from_state(_state, _target, _contract), do: nil

  @spec subscription_callback(Types.cmd_call(), map()) :: String.t() | nil
  defp subscription_callback(ei, contract) when is_map(ei) and is_map(contract) do
    target_suffixes = Map.get(contract, :target_suffixes, []) |> List.wrap()

    ei
    |> introspect_cmd_calls("subscription_calls")
    |> Enum.find_value(fn row ->
      if subscription_call_matches?(row, target_suffixes) do
        callback = Map.get(row, "callback_constructor")
        if is_binary(callback) and callback != "", do: callback, else: nil
      end
    end)
  end

  defp subscription_callback(_ei, _contract), do: nil

  @spec subscription_call_matches?(map(), [String.t()]) :: boolean()
  defp subscription_call_matches?(row, target_suffixes)
       when is_map(row) and is_list(target_suffixes) do
    Enum.any?(target_suffixes, &cmd_call_target_ends_with?(row, &1))
  end

  defp subscription_call_matches?(_row, _target_suffixes), do: false

  defp protocol_events_from_cmd_call(state, target_surface, cmd_call, model, message_value \\ nil)

  defp protocol_events_from_cmd_call(state, :watch, cmd_call, model, message_value)
       when is_map(cmd_call) do
    name = (Map.get(cmd_call, "name") || Map.get(cmd_call, :name) || "") |> to_string()
    target = (Map.get(cmd_call, "target") || Map.get(cmd_call, :target) || "") |> to_string()

    {message, protocol_value} =
      protocol_message_payload_for_cmd_call(state, cmd_call, model, :watch_to_phone, message_value)

    if name == "sendWatchToPhone" or String.ends_with?(target, ".sendWatchToPhone") do
      protocol_tx_rx_events("watch", "companion", message, "init_cmd", protocol_value)
    else
      []
    end
  end

  defp protocol_events_from_cmd_call(state, target_surface, cmd_call, model, message_value)
       when target_surface in [:companion, :phone] and is_map(cmd_call) do
    name = (Map.get(cmd_call, "name") || Map.get(cmd_call, :name) || "") |> to_string()
    target = (Map.get(cmd_call, "target") || Map.get(cmd_call, :target) || "") |> to_string()

    {message, protocol_value} =
      protocol_message_payload_for_cmd_call(state, cmd_call, model, :phone_to_watch, message_value)

    if name == "sendPhoneToWatch" or String.ends_with?(target, ".sendPhoneToWatch") do
      protocol_tx_rx_events("companion", "watch", message, "protocol_cmd", protocol_value)
    else
      []
    end
  end

  defp protocol_events_from_cmd_call(_state, _surface, _cmd_call, _model, _message_value), do: []

  @spec protocol_events_for_model_commands(
          runtime_state(),
          map(),
          Types.surface_target(),
          String.t(),
          Types.subscription_payload()
        ) :: [map()]
  defp protocol_events_for_model_commands(state, model, target, message, message_value)

  defp protocol_events_for_model_commands(state, model, target, message, message_value)
       when is_map(state) and is_map(model) and target in [:watch, :companion, :phone] and
              is_binary(message) do
    current_ctor = message_constructor(message)
    ei = introspect_for(state, target)

    ei
    |> introspect_cmd_calls("update_cmd_calls")
    |> update_cmd_calls_for_message(current_ctor)
    |> expand_helper_cmd_calls(ei)
    |> Enum.flat_map(
      &protocol_events_from_cmd_call(state, target, &1, model, message_value)
    )
  end

  defp protocol_events_for_model_commands(_state, _model, _target, _message, _message_value),
    do: []

  @spec expand_helper_cmd_calls([map()], map()) :: [map()]
  defp expand_helper_cmd_calls(calls, ei) when is_list(calls) and is_map(ei) do
    helpers =
      case Map.get(ei, "function_cmd_calls", %{}) do
        value when is_map(value) -> value
        _ -> %{}
      end

    Enum.flat_map(calls, fn row ->
      helper_name = Map.get(row, "target") || Map.get(row, "name")

      case Map.get(helpers, helper_name) do
        helper_calls when is_list(helper_calls) and helper_calls != [] -> helper_calls
        _ -> [row]
      end
    end)
  end

  defp expand_helper_cmd_calls(calls, _ei) when is_list(calls), do: calls
  @spec protocol_message_payload_for_cmd_call(
          term(),
          map(),
          term(),
          :watch_to_phone | :phone_to_watch,
          Types.subscription_payload()
        ) ::
          {String.t() | nil, term()}
  defp protocol_message_payload_for_cmd_call(state, cmd_call, model, direction, message_value)

  defp protocol_message_payload_for_cmd_call(state, cmd_call, model, direction, message_value)
       when is_map(cmd_call) and direction in [:watch_to_phone, :phone_to_watch] do
    case protocol_schema_from_state_or_model(state, model) do
      {:ok, schema} ->
        ctx =
          ProtocolResolutionCtx.new(
            direction: direction,
            protocol_ctor: protocol_message_ctor_name(cmd_call),
            runtime_model: RuntimeArtifacts.inner_runtime_model(model),
            simulator_settings: simulator_settings_from_state(state),
            message_value: message_value
          )

        protocol_message_payload_from_cmd_call(cmd_call, schema, direction, ctx)

      {:error, _} ->
        protocol_message_payload_from_arg_values(cmd_call, direction)
    end
  end

  @spec protocol_message_payload_from_cmd_call(map(), map(), :watch_to_phone | :phone_to_watch, map()) ::
          {String.t() | nil, term()}
  defp protocol_message_payload_from_cmd_call(cmd_call, schema, direction, ctx)
       when is_map(cmd_call) and is_map(schema) and direction in [:watch_to_phone, :phone_to_watch] and
              is_map(ctx) do
    callback =
      Map.get(cmd_call, "callback_constructor") || Map.get(cmd_call, :callback_constructor)

    case resolve_protocol_message_from_cmd_call(cmd_call, schema, direction, ctx) do
      {message, protocol_value} when is_binary(message) and message != "" and is_map(protocol_value) ->
        wrap_watch_to_phone_protocol_payload(direction, message, protocol_value)

      _ ->
        case protocol_message_from_schema(schema, direction, callback) do
          message when is_binary(message) and message != "" ->
            wrap_watch_to_phone_protocol_payload(
              direction,
              message,
              protocol_message_value_from_schema(schema, direction, callback)
            )

          _ ->
            protocol_message_payload_from_arg_values(cmd_call, direction)
        end
    end
  end

  @spec wrap_watch_to_phone_protocol_payload(
          :watch_to_phone | :phone_to_watch,
          String.t(),
          term()
        ) :: {String.t(), term()}
  defp wrap_watch_to_phone_protocol_payload(:watch_to_phone, message, protocol_value)
       when is_binary(message) do
    if String.starts_with?(message, "FromWatch") do
      {message, protocol_value}
    else
      {"FromWatch (Ok #{parenthesize_elm_arg(message)})", protocol_value}
    end
  end

  defp wrap_watch_to_phone_protocol_payload(_direction, message, protocol_value),
    do: {message, protocol_value}

  @spec protocol_message_payload_from_arg_values(map(), :watch_to_phone | :phone_to_watch | nil) ::
          {String.t() | nil, term()}
  defp protocol_message_payload_from_arg_values(cmd_call, direction \\ nil)

  defp protocol_message_payload_from_arg_values(cmd_call, direction) when is_map(cmd_call) do
    case protocol_ctor_from_cmd_call(cmd_call) do
      {:ok, ctor, inner_args} when is_binary(ctor) ->
        args = List.wrap(inner_args)
        inner_value = %{"ctor" => ctor, "args" => args}
        inner_message = protocol_message_display(ctor, args)

        if direction == :watch_to_phone do
          wrap_watch_to_phone_protocol_payload(direction, inner_message, inner_value)
        else
          {inner_message, inner_value}
        end

      _ ->
        callback =
          Map.get(cmd_call, "callback_constructor") || Map.get(cmd_call, :callback_constructor)

        if is_binary(callback) and callback != "", do: {callback, nil}, else: {nil, nil}
    end
  end

  defp protocol_message_payload_for_cmd_call(_state, _cmd_call, _model, _direction, _message_value),
    do: {nil, nil}

  @spec protocol_message_ctor_name(map()) :: String.t() | nil
  defp protocol_message_ctor_name(cmd_call) when is_map(cmd_call) do
    case protocol_ctor_from_cmd_call(cmd_call) do
      {:ok, ctor, _} when is_binary(ctor) -> ctor
      _ -> Map.get(cmd_call, "callback_constructor") || Map.get(cmd_call, :callback_constructor)
    end
  end

  @spec resolve_protocol_message_from_cmd_call(
          map(),
          Types.protocol_schema(),
          :watch_to_phone | :phone_to_watch,
          ProtocolResolutionCtx.t()
        ) ::
          {String.t(), map()} | :error
  defp resolve_protocol_message_from_cmd_call(cmd_call, schema, direction, %ProtocolResolutionCtx{} = ctx)
       when is_map(cmd_call) and is_map(schema) and
              direction in [:watch_to_phone, :phone_to_watch] do
    with {:ok, ctor, inner_args} <- protocol_ctor_from_cmd_call(cmd_call),
         %{fields: fields} <- protocol_schema_message(schema, direction, ctor),
         ctx = ProtocolResolutionCtx.with_message_resolution(ctx, schema, ctor, fields),
         {:ok, resolved_args} <- resolve_protocol_ctor_args(inner_args, fields, schema, ctx) do
      message_value = %{"ctor" => ctor, "args" => resolved_args}
      {protocol_message_display(ctor, resolved_args), message_value}
    else
      _ -> :error
    end
  end

  defp resolve_protocol_message_from_cmd_call(_cmd_call, _schema, _direction, _ctx), do: :error

  @protocol_subscription_wrapper_ctors ~w(FromWatch FromPhone)

  @spec protocol_ctor_from_cmd_call(map()) :: {:ok, String.t(), list()} | :error
  defp protocol_ctor_from_cmd_call(cmd_call) when is_map(cmd_call) do
    case raw_protocol_ctor_from_cmd_call(cmd_call) do
      {:ok, ctor, args} when is_binary(ctor) ->
        unwrap_protocol_wire_ctor({:ok, ctor, List.wrap(args)})

      :error ->
        :error
    end
  end

  @spec raw_protocol_ctor_from_cmd_call(map()) :: {:ok, String.t(), list()} | :error
  defp raw_protocol_ctor_from_cmd_call(%{"arg_values" => [first | _]}) when is_map(first) do
    ctor = Map.get(first, "$ctor") || Map.get(first, "ctor")
    args = Map.get(first, "$args") || Map.get(first, "args") || []

    if is_binary(ctor) and ctor != "" do
      {:ok, ctor, List.wrap(args)}
    else
      :error
    end
  end

  defp raw_protocol_ctor_from_cmd_call(%{arg_values: [first | _]}) when is_map(first) do
    raw_protocol_ctor_from_cmd_call(%{"arg_values" => [first]})
  end

  defp raw_protocol_ctor_from_cmd_call(_cmd_call), do: :error

  @spec unwrap_protocol_wire_ctor({:ok, String.t(), list()}) :: {:ok, String.t(), list()} | :error
  defp unwrap_protocol_wire_ctor({:ok, ctor, args})
       when ctor in @protocol_subscription_wrapper_ctors and is_list(args) do
    case List.wrap(args) do
      [%{"ctor" => result, "args" => [inner | _]} | _]
      when result in ["Ok", "Err"] and is_map(inner) ->
        inner_ctor = Map.get(inner, "ctor") || Map.get(inner, "$ctor")
        inner_args = Map.get(inner, "args") || Map.get(inner, "$args") || []

        if is_binary(inner_ctor) and inner_ctor != "" do
          unwrap_protocol_wire_ctor({:ok, inner_ctor, List.wrap(inner_args)})
        else
          {:ok, ctor, args}
        end

      [%{ctor: result, args: [inner | _]} | _]
      when result in ["Ok", "Err"] and is_map(inner) ->
        inner_ctor = Map.get(inner, :ctor) || Map.get(inner, "ctor")
        inner_args = Map.get(inner, :args) || Map.get(inner, "args") || []

        if is_binary(inner_ctor) and inner_ctor != "" do
          unwrap_protocol_wire_ctor({:ok, inner_ctor, List.wrap(inner_args)})
        else
          {:ok, ctor, args}
        end

      _ ->
        {:ok, ctor, args}
    end
  end

  defp unwrap_protocol_wire_ctor(other), do: other

  @spec resolve_protocol_ctor_args(
          [term()],
          [Ide.Debugger.Protocol.Schema.field()],
          Types.protocol_schema(),
          ProtocolResolutionCtx.t()
        ) ::
          {:ok, list()} | :error
  defp resolve_protocol_ctor_args(inner_args, fields, schema, %ProtocolResolutionCtx{} = ctx)
       when is_list(inner_args) and is_list(fields) and is_map(schema) do
    resolved =
      inner_args
      |> Enum.with_index()
      |> Enum.map(fn {arg, index} ->
        field = Enum.at(fields, index) || %{}
        wire_type = Map.get(field, :wire_type)

        resolve_protocol_ctor_arg(
          arg,
          wire_type,
          schema,
          ProtocolResolutionCtx.with_arg_index(ctx, index)
        )
      end)

    if Enum.any?(resolved, &(not is_nil(&1))) do
      {:ok, resolved}
    else
      :error
    end
  end

  defp resolve_protocol_ctor_args(_inner_args, _fields, _schema, _ctx), do: :error

  @spec resolve_protocol_ctor_arg(
          term(),
          Types.protocol_wire_type(),
          Types.protocol_schema(),
          ProtocolResolutionCtx.t()
        ) ::
          term() | nil
  defp resolve_protocol_ctor_arg(arg, wire_type, schema, ctx) do
    value =
      WireValues.coalesce([
        resolve_protocol_arg_expr(arg, ctx),
        resolve_protocol_arg_fallback(wire_type, schema, ctx),
        simulator_settings_wire_value(wire_type, ctx)
      ])

    normalize_protocol_resolved_value(wire_type, schema, value)
  end

  @spec normalize_protocol_resolved_value(Types.protocol_wire_type(), map(), term()) :: term() | nil
  defp normalize_protocol_resolved_value({:union, "Temperature"} = wire_type, schema, value) do
    normalize_temperature_value(value, schema, wire_type)
  end

  defp normalize_protocol_resolved_value({:enum, type} = wire_type, schema, value)
       when is_map(schema) and is_binary(type) do
    normalize_protocol_wire_value(schema, value, wire_type)
  end

  defp normalize_protocol_resolved_value({:union, type}, schema, value)
       when is_binary(type) and is_map(value) do
    case value do
      %{"ctor" => ctor, "args" => args} when is_binary(ctor) and is_list(args) ->
        %{
          "ctor" => ctor,
          "args" => Enum.map(args, &normalize_protocol_resolved_value({:union, type}, schema, &1))
        }

      _ ->
        value
    end
  end

  defp normalize_protocol_resolved_value(_wire_type, _schema, value), do: value

  @spec normalize_temperature_value(term(), map(), Types.protocol_wire_type()) :: term() | nil
  defp normalize_temperature_value(%{"ctor" => "Celsius", "args" => [arg | _]}, _schema, _wire_type) do
    case normalize_temperature_scalar(arg) do
      nil -> %{"ctor" => "Celsius", "args" => [0]}
      int -> %{"ctor" => "Celsius", "args" => [int]}
    end
  end

  defp normalize_temperature_value(%{"ctor" => "Fahrenheit", "args" => [arg | _]}, _schema, _wire_type) do
    case normalize_temperature_scalar(arg) do
      nil -> %{"ctor" => "Fahrenheit", "args" => [0]}
      int -> %{"ctor" => "Fahrenheit", "args" => [int]}
    end
  end

  defp normalize_temperature_value(value, _schema, _wire_type)
       when is_integer(value) or is_float(value) do
    %{"ctor" => "Celsius", "args" => [normalize_temperature_scalar(value)]}
  end

  defp normalize_temperature_value(%{} = record, schema, wire_type) do
    case Map.get(record, "temperature") do
      temp when is_integer(temp) or is_float(temp) ->
        normalize_temperature_value(temp, schema, wire_type)

      _ ->
        record
    end
  end

  defp normalize_temperature_value(value, _schema, _wire_type), do: value

  @spec normalize_temperature_scalar(term()) :: integer() | nil
  defp normalize_temperature_scalar(value) when is_integer(value), do: value

  defp normalize_temperature_scalar(value) when is_float(value),
    do: value |> Float.round() |> trunc()

  defp normalize_temperature_scalar(value) when is_binary(value) do
    trimmed = String.trim(value)

    cond do
      trimmed == "" ->
        nil

      String.contains?(trimmed, ".") ->
        case Float.parse(trimmed) do
          {parsed, ""} -> parsed |> Float.round() |> trunc()
          _ -> nil
        end

      true ->
        case Integer.parse(trimmed) do
          {parsed, ""} -> parsed
          _ -> nil
        end
    end
  end

  defp normalize_temperature_scalar(%{"temperature" => temp}), do: normalize_temperature_scalar(temp)
  defp normalize_temperature_scalar(_value), do: nil

  @spec resolve_protocol_arg_expr(term(), map()) :: term() | nil
  defp resolve_protocol_arg_expr(%{"$field" => field, "$on" => on_expr}, ctx)
       when is_binary(field) and is_map(on_expr) and is_map(ctx) do
    case resolve_protocol_binding_record(on_expr, ctx) do
      record when is_map(record) -> Map.get(record, field)
      _ -> nil
    end
  end

  defp resolve_protocol_arg_expr(%{"$var" => name}, ctx) when is_binary(name) and is_map(ctx) do
    runtime_model = Map.get(ctx, :runtime_model) || %{}

    cond do
      Map.has_key?(runtime_model, name) ->
        Map.get(runtime_model, name)

      true ->
        case Map.get(protocol_message_var_bindings(ctx), name) do
          %{} = record ->
            record

          value when not is_nil(value) ->
            value

          _ ->
            nil
        end
    end
  end

  defp resolve_protocol_arg_expr(%{"$call" => call, "$args" => args}, ctx)
       when is_binary(call) and is_list(args) and is_map(ctx) do
    resolved_args = Enum.map(args, &resolve_protocol_arg_expr(&1, ctx))

    if round_call?(call) do
      case resolved_args do
        [num | _] when is_integer(num) -> num
        [num | _] when is_float(num) -> normalize_temperature_scalar(num)
        _ -> nil
      end
    else
      nil
    end
  end

  defp resolve_protocol_arg_expr(value, _ctx) when is_integer(value) or is_boolean(value) or is_binary(value),
    do: value

  defp resolve_protocol_arg_expr(%{"$ctor" => ctor, "$args" => args}, ctx)
       when is_binary(ctor) and is_list(args) and is_map(ctx) do
    %{
      "ctor" => ctor,
      "args" =>
        args
        |> Enum.map(&resolve_protocol_arg_expr(&1, ctx))
        |> Enum.reject(&is_nil/1)
    }
  end

  defp resolve_protocol_arg_expr(%{"$opaque" => true, "op" => "field_access"}, _ctx), do: nil
  defp resolve_protocol_arg_expr(_arg, _ctx), do: nil

  @spec resolve_protocol_binding_record(map(), map()) :: term() | nil
  defp resolve_protocol_binding_record(%{"$var" => name}, ctx)
       when is_binary(name) and is_map(ctx) do
    case Map.get(protocol_message_var_bindings(ctx), name) do
      %{} = record ->
        record

      value when not is_nil(value) ->
        value

      _ ->
        protocol_binding_record_from_runtime_model(Map.get(ctx, :runtime_model))
    end
  end

  defp resolve_protocol_binding_record(_expr, _ctx), do: nil

  @spec protocol_message_var_bindings(map()) :: map()
  defp protocol_message_var_bindings(ctx) when is_map(ctx) do
    case Map.get(ctx, :message_value) do
      %{"ctor" => ctor, "args" => [inner | _]} when is_binary(ctor) and is_map(inner) ->
        case protocol_ok_inner_record(inner) do
          %{"ctor" => "Current", "args" => [info | _]} = current when is_map(info) ->
            %{"info" => companion_bridge_weather_info(info), "current" => current}

          %{} = record ->
            binding_name = protocol_ok_payload_binding_name(ctor)

            if is_binary(binding_name) and binding_name != "" do
              %{binding_name => record}
            else
              %{}
            end

          _ ->
            protocol_connectivity_record(inner)
            |> case do
              %{} = record -> %{"connectivity" => record}
              _ -> %{}
            end
        end

      _ ->
        %{}
    end
  end

  @spec protocol_ok_payload_binding_name(String.t()) :: String.t() | nil
  defp protocol_ok_payload_binding_name(ctor) when is_binary(ctor) do
    case String.replace_suffix(ctor, "Received", "") do
      "" ->
        nil

      <<first::utf8, rest::binary>> ->
        String.downcase(<<first::utf8>>) <> rest
    end
  end

  @spec round_call?(String.t()) :: boolean()
  defp round_call?(call) when is_binary(call) do
    String.ends_with?(call, ".round") or call == "round" or call == "Basics.round"
  end

  @spec protocol_binding_record_from_runtime_model(map() | nil) :: map() | nil
  defp protocol_binding_record_from_runtime_model(%{} = runtime_model) do
    %{
      "percent" => Map.get(runtime_model, "batteryPercent"),
      "charging" => Map.get(runtime_model, "charging"),
      "online" => Map.get(runtime_model, "online"),
      "locale" => Map.get(runtime_model, "locale"),
      "notificationsEnabled" => Map.get(runtime_model, "notificationsEnabled"),
      "quietHours" => Map.get(runtime_model, "quietHours")
    }
    |> Enum.reject(fn {_key, value} -> is_nil(value) end)
    |> Map.new()
    |> case do
      %{} = empty when map_size(empty) == 0 -> nil
      record -> record
    end
  end

  defp protocol_binding_record_from_runtime_model(_runtime_model), do: nil

  defp protocol_update_payload_record(%{"ctor" => _ctor, "args" => [inner | _]}) when is_map(inner) do
    case protocol_ok_inner_record(inner) do
      %{} = record -> record
      _ -> protocol_connectivity_record(inner)
    end
  end

  defp protocol_update_payload_record(%{ctor: ctor, args: [inner | _]}) when is_map(inner) do
    protocol_update_payload_record(%{"ctor" => ctor, "args" => [inner]})
  end

  defp protocol_update_payload_record(_message_value), do: nil

  @spec protocol_connectivity_record(map()) :: map() | nil
  defp protocol_connectivity_record(%{"ctor" => "Online"}), do: %{"online" => true}
  defp protocol_connectivity_record(%{"ctor" => "Offline"}), do: %{"online" => false}
  defp protocol_connectivity_record(%{ctor: "Online"}), do: %{"online" => true}
  defp protocol_connectivity_record(%{ctor: "Offline"}), do: %{"online" => false}
  defp protocol_connectivity_record(_inner), do: nil

  @spec protocol_ok_inner_record(map()) :: map() | nil
  defp protocol_ok_inner_record(%{"ctor" => "Ok", "args" => [value | _]}) when is_map(value), do: value

  defp protocol_ok_inner_record(%{ctor: "Ok", args: [value | _]}) when is_map(value), do: value

  defp protocol_ok_inner_record(%{"ctor" => ctor, "args" => _}) when ctor in ["Online", "Offline"],
    do: nil

  defp protocol_ok_inner_record(%{ctor: ctor, args: _}) when ctor in ["Online", "Offline"], do: nil
  defp protocol_ok_inner_record(value) when is_map(value), do: value
  @spec resolve_protocol_arg_fallback(Types.protocol_wire_type(), map(), map()) :: term() | nil
  defp resolve_protocol_arg_fallback(wire_type, schema, ctx) when is_map(schema) and is_map(ctx) do
    record =
      protocol_update_payload_record(Map.get(ctx, :message_value)) ||
        protocol_binding_record_from_runtime_model(Map.get(ctx, :runtime_model)) ||
        %{}

    value =
      case wire_type do
        :int ->
          WireValues.map_get_first_present(record, ["percent", "batteryPercent", "battery_percent"])

        :bool ->
          protocol_bool_fallback_value(ctx, record)

        :string ->
          Map.get(record, "locale")

        {:enum, type} ->
          protocol_default_value_term(schema, {:enum, type})

        {:union, type} ->
          protocol_default_value_term(schema, {:union, type})

        _ ->
          nil
      end

    WireValues.coalesce([
      value,
      runtime_model_wire_value(wire_type, ctx)
    ])
  end

  defp resolve_protocol_arg_fallback(_wire_type, _schema, _ctx), do: nil

  @spec runtime_model_wire_value(Types.protocol_wire_type(), map()) :: term() | nil
  defp runtime_model_wire_value(:int, %{runtime_model: %{} = runtime_model} = ctx) do
    keys =
      case Map.get(ctx, :protocol_ctor) do
        "ProvidePosition" -> provide_position_runtime_model_keys(Map.get(ctx, :arg_index))
        _ -> ["batteryPercent", "percent", "battery_percent"]
      end

    WireValues.map_get_first_present(runtime_model, keys)
  end

  defp runtime_model_wire_value(:bool, ctx) do
    protocol_bool_fallback_value(ctx, Map.get(ctx, :runtime_model) || %{})
  end

  defp runtime_model_wire_value(:string, %{runtime_model: %{} = runtime_model}) do
    Map.get(runtime_model, "locale")
  end

  defp runtime_model_wire_value(_wire_type, _ctx), do: nil

  @spec provide_position_runtime_model_keys(term()) :: [String.t()]
  defp provide_position_runtime_model_keys(0), do: ["latitudeE6"]
  defp provide_position_runtime_model_keys(1), do: ["longitudeE6"]
  defp provide_position_runtime_model_keys(2), do: ["accuracyM"]
  defp provide_position_runtime_model_keys(_), do: []

  @spec simulator_settings_wire_value(Types.protocol_wire_type(), map()) :: term() | nil
  defp simulator_settings_wire_value(:int, ctx) when is_map(ctx) do
    case Map.get(ctx, :protocol_ctor) do
      "ProvidePosition" ->
        geolocation_simulator_wire_int(ctx)

      _ ->
        case Map.get(ctx, :simulator_settings) do
          %{} = settings -> Map.get(settings, "battery_percent")
          _ -> nil
        end
    end
  end

  defp simulator_settings_wire_value(:bool, ctx) do
    protocol_bool_simulator_value(ctx)
  end

  defp simulator_settings_wire_value(:string, %{simulator_settings: %{} = settings}) do
    Map.get(settings, "locale")
  end

  defp simulator_settings_wire_value({:union, "Temperature"}, %{simulator_settings: settings})
       when is_map(settings) do
    case weather_temperature_celsius(settings["weather"] || %{}) do
      nil -> nil
      temp -> %{"ctor" => "Celsius", "args" => [temp]}
    end
  end

  defp simulator_settings_wire_value({:enum, "WeatherCondition"}, %{simulator_settings: settings})
       when is_map(settings) do
    weather_condition_term_from_settings(settings)
  end

  defp simulator_settings_wire_value(_wire_type, _ctx), do: nil

  @spec weather_condition_term_from_settings(map()) :: map()
  defp weather_condition_term_from_settings(settings) when is_map(settings) do
    weather = settings["weather"] || %{}

    key =
      (Map.get(weather, "condition") || Map.get(weather, :condition) || "clear")
      |> to_string()
      |> String.downcase()
      |> String.replace(~r/[^a-z0-9]+/, "")

    ctor =
      case key do
        "clear" -> "Clear"
        "cloudy" -> "Cloudy"
        "fog" -> "Fog"
        "drizzle" -> "Drizzle"
        "rain" -> "Rain"
        "snow" -> "Snow"
        "showers" -> "Showers"
        "storm" -> "Storm"
        _ -> "UnknownWeather"
      end

    %{"ctor" => ctor, "args" => []}
  end

  @spec protocol_bool_fallback_value(map(), map()) :: boolean() | nil
  defp protocol_bool_fallback_value(ctx, record) when is_map(ctx) and is_map(record) do
    ctor = Map.get(ctx, :protocol_ctor)

    keys =
      case ctor do
        "ProvideConnectivity" -> ["online"]
        "ProvideBattery" -> ["charging"]
        "ProvideNotifications" -> ["notificationsEnabled", "quietHours"]
        _ -> ["online", "charging", "notificationsEnabled", "quietHours"]
      end

    WireValues.map_get_first_present(record, keys)
  end

  defp protocol_bool_fallback_value(_ctx, _record), do: nil

  @spec protocol_bool_simulator_value(map()) :: boolean() | nil
  defp protocol_bool_simulator_value(%{protocol_ctor: "ProvideConnectivity", simulator_settings: settings})
       when is_map(settings),
       do: Map.get(settings, "network_online")

  defp protocol_bool_simulator_value(%{protocol_ctor: "ProvideBattery", simulator_settings: settings})
       when is_map(settings),
       do: Map.get(settings, "charging")

  defp protocol_bool_simulator_value(_ctx), do: nil

  @spec protocol_schema_from_state_or_model(runtime_state(), map()) :: {:ok, map()} | {:error, Types.protocol_error()}
  defp protocol_schema_from_state_or_model(state, model) do
    case project_protocol_schema(state) do
      {:ok, schema} -> {:ok, schema}
      {:error, _} -> protocol_schema_from_model(model)
    end
  end

  @spec project_protocol_schema(map()) :: {:ok, map()} | {:error, Types.protocol_error()}
  defp project_protocol_schema(state) when is_map(state) do
    with session_key when is_binary(session_key) <- session_key_from_state(state),
         %{} = project <- Projects.get_project_by_scope_key(session_key),
         workspace_root <- Projects.project_workspace_path(project),
         protocol_types <- Path.join(workspace_root, "protocol/src/Companion/Types.elm"),
         true <- File.exists?(protocol_types),
         {:ok, source} <- File.read(protocol_types) do
      Ide.CompanionProtocolGenerator.schema_from_source(source)
    else
      _ -> {:error, :missing_project_protocol}
    end
  rescue
    DBConnection.OwnershipError ->
      {:error, :repo_unavailable}

    error in [RuntimeError] ->
      case Exception.message(error) do
        "could not lookup Ecto repo " <> _ -> {:error, :repo_unavailable}
        _ -> reraise error, __STACKTRACE__
      end
  end

  @spec protocol_schema_from_model(map()) :: {:ok, map()} | {:error, Types.protocol_error()}
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

  @spec protocol_message_from_schema(Types.protocol_schema(), :watch_to_phone | :phone_to_watch, String.t()) ::
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

  @spec protocol_message_value_from_schema(Types.protocol_schema(), :watch_to_phone | :phone_to_watch, String.t()) ::
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

  @spec protocol_default_value(Types.protocol_schema(), Types.protocol_wire_type()) :: String.t()
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

  @spec protocol_default_value_term(Types.protocol_schema(), Types.protocol_wire_type()) ::
          integer() | boolean() | String.t() | Types.protocol_ctor_value()
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

  @spec protocol_wire_type_for_type(Types.protocol_schema(), String.t()) ::
          Types.protocol_wire_type()
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

  defp protocol_tx_rx_events(from, to, message, trigger, message_value) do
    Ide.Debugger.Types.ProtocolTxRxPayload.tx_rx_events(
      from,
      to,
      message,
      trigger,
      message_value
    )
  end

  @spec normalize_protocol_events_from_schema([map()], map()) :: [map()]
  defp normalize_protocol_events_from_schema(protocol_events, state)
       when is_list(protocol_events) and is_map(state) do
    case project_protocol_schema(state) do
      {:ok, schema} ->
        Enum.map(protocol_events, &normalize_protocol_event_from_schema(&1, schema))

      {:error, _} ->
        protocol_events
    end
  end

  defp normalize_protocol_events_from_schema(protocol_events, _state), do: protocol_events

  @spec normalize_protocol_event_from_schema(Types.protocol_event(), map()) :: map()
  defp normalize_protocol_event_from_schema(event, schema)
       when is_map(event) and is_map(schema) do
    type = Map.get(event, :type) || Map.get(event, "type")
    payload = Map.get(event, :payload) || Map.get(event, "payload")

    if is_binary(type) and is_map(payload) do
      normalized_payload = normalize_protocol_payload_from_schema(payload, schema)
      %{type: type, payload: normalized_payload}
    else
      event
    end
  end

  defp normalize_protocol_event_from_schema(event, _schema), do: event

  @spec normalize_protocol_payload_from_schema(map(), map()) :: map()
  defp normalize_protocol_payload_from_schema(payload, schema)
       when is_map(payload) and is_map(schema) do
    from = Map.get(payload, :from) || Map.get(payload, "from")
    to = Map.get(payload, :to) || Map.get(payload, "to")
    message = Map.get(payload, :message) || Map.get(payload, "message")
    message_value = Map.get(payload, :message_value) || Map.get(payload, "message_value")

    direction =
      cond do
        from == "watch" and to in ["companion", "phone"] -> :watch_to_phone
        from in ["companion", "phone"] and to == "watch" -> :phone_to_watch
        true -> nil
      end

    case normalize_protocol_message_value_from_schema(schema, direction, message_value, message) do
      {normalized_message, normalized_value} ->
        payload
        |> Map.put(:message, normalized_message)
        |> Map.put(:message_value, normalized_value)

      :error ->
        payload
    end
  end

  @spec normalize_protocol_message_value_from_schema(map(), atom() | nil, Types.protocol_wire_arg(), Types.protocol_wire_arg()) ::
          {String.t(), map()} | :error
  defp normalize_protocol_message_value_from_schema(schema, direction, message_value, message)
       when direction in [:watch_to_phone, :phone_to_watch] and is_map(schema) do
    ctor = protocol_message_ctor(message_value) || message_constructor(message)

    with ctor when is_binary(ctor) and ctor != "" <- ctor,
         %{fields: fields} <- protocol_schema_message(schema, direction, ctor),
         args <- protocol_message_args(message_value, length(fields)) do
      normalized_args =
        fields
        |> Enum.zip(args)
        |> Enum.map(fn {field, value} ->
          normalize_protocol_wire_value(schema, value, Map.get(field, :wire_type))
        end)

      normalized_value = %{"ctor" => ctor, "args" => normalized_args}
      {protocol_message_display(ctor, normalized_args), normalized_value}
    else
      _ -> :error
    end
  end

  defp normalize_protocol_message_value_from_schema(
         _schema,
         _direction,
         _message_value,
         _message
       ),
       do: :error

  @spec protocol_schema_message(
          Types.protocol_schema(),
          :watch_to_phone | :phone_to_watch,
          String.t()
        ) :: Types.protocol_schema_message() | nil
  defp protocol_schema_message(schema, direction, ctor)
       when is_map(schema) and is_binary(ctor) do
    schema
    |> Map.get(direction, [])
    |> Enum.find(&(Map.get(&1, :name) == ctor))
  end

  @spec protocol_message_ctor(Types.protocol_message_wire_value() | map()) :: String.t() | nil
  defp protocol_message_ctor(%{"ctor" => ctor}) when is_binary(ctor), do: ctor
  defp protocol_message_ctor(%{ctor: ctor}) when is_binary(ctor), do: ctor
  defp protocol_message_ctor(_), do: nil

  @spec protocol_message_args(Types.protocol_message_wire_value() | map(), non_neg_integer()) ::
          [Types.protocol_wire_arg()]
  defp protocol_message_args(%{"args" => args}, field_count) when is_list(args),
    do: flatten_protocol_args(args, field_count)

  defp protocol_message_args(%{args: args}, field_count) when is_list(args),
    do: flatten_protocol_args(args, field_count)

  defp protocol_message_args(_message_value, _field_count), do: []

  @spec flatten_protocol_args([Types.protocol_wire_arg()], non_neg_integer()) ::
          [Types.protocol_wire_arg()]
  defp flatten_protocol_args(args, field_count)
       when is_list(args) and is_integer(field_count) and field_count > 0 do
    cond do
      length(args) == field_count ->
        args

      length(args) == 1 ->
        flatten_protocol_tuple_chain(hd(args), field_count)

      length(args) < field_count ->
        case List.last(args) do
          nil ->
            args

          tail ->
            prefix = Enum.drop(args, -1)
            flattened_tail = flatten_protocol_tuple_chain(tail, field_count - length(prefix))
            prefix ++ flattened_tail
        end

      true ->
        Enum.take(args, field_count)
    end
  end

  defp flatten_protocol_args(args, _field_count) when is_list(args), do: args

  @spec flatten_protocol_tuple_chain(Types.protocol_wire_arg(), non_neg_integer()) ::
          [Types.protocol_wire_arg()]
  defp flatten_protocol_tuple_chain(value, count) when is_integer(count) and count > 0 do
    do_flatten_protocol_tuple_chain(value, count, [])
  end

  defp flatten_protocol_tuple_chain(value, _count), do: [value]

  defp do_flatten_protocol_tuple_chain(value, 1, acc), do: Enum.reverse([value | acc])

  defp do_flatten_protocol_tuple_chain({left, right}, count, acc) when count > 1,
    do: do_flatten_protocol_tuple_chain(right, count - 1, [left | acc])

  defp do_flatten_protocol_tuple_chain(
         %{"type" => "tuple2", "children" => [left, right]},
         count,
         acc
       )
       when count > 1,
       do: do_flatten_protocol_tuple_chain(right, count - 1, [left | acc])

  defp do_flatten_protocol_tuple_chain(%{type: "tuple2", children: [left, right]}, count, acc)
       when count > 1,
       do: do_flatten_protocol_tuple_chain(right, count - 1, [left | acc])

  defp do_flatten_protocol_tuple_chain(value, _count, acc), do: Enum.reverse([value | acc])

  @spec normalize_protocol_wire_value(
          Types.protocol_schema(),
          term(),
          Types.protocol_wire_type()
        ) :: term()
  defp normalize_protocol_wire_value(schema, value, {:enum, type})
       when is_map(schema) and is_binary(type) do
    cond do
      protocol_constructor_value?(value) ->
        value

      true ->
        if is_integer(value) do
          enum_values = Map.get(schema, :enums, %{}) |> Map.get(type, [])

          case Enum.at(enum_values, value - Ide.CompanionProtocolGenerator.wire_code_base()) do
            ctor when is_binary(ctor) and ctor != "" ->
              %{"ctor" => ctor, "args" => []}

            _ ->
              value
          end
        else
          value
        end
    end
  end

  defp normalize_protocol_wire_value(_schema, value, _wire_type), do: value

  @spec normalize_protocol_subscription_message_value(
          runtime_state(),
          Types.surface_target(),
          map()
        ) :: map()
  defp normalize_protocol_subscription_message_value(state, recipient, message_value)
       when is_map(state) and recipient in [:watch, :companion, :phone] and is_map(message_value) do
    normalize_protocol_subscription_message_value(
      state,
      recipient,
      message_value,
      surface_app_model(state, recipient)
    )
  end

  @spec normalize_protocol_subscription_message_value(
          runtime_state(),
          Types.surface_target(),
          map(),
          Types.app_model()
        ) :: map()
  defp normalize_protocol_subscription_message_value(state, recipient, message_value, app_model)
       when is_map(state) and recipient in [:watch, :companion, :phone] and is_map(message_value) and
              is_map(app_model) do
    direction =
      case recipient do
        :watch -> :phone_to_watch
        _ -> :watch_to_phone
      end

    case protocol_schema_from_state_or_model(state, app_model) do
      {:ok, schema} ->
        normalize_protocol_subscription_callback_value(schema, direction, message_value)

      _ ->
        message_value
    end
  end

  defp normalize_protocol_subscription_message_value(_state, _recipient, message_value, _app_model),
    do: message_value

  @spec normalize_protocol_subscription_callback_value(map(), :watch_to_phone | :phone_to_watch, map()) :: map()
  defp normalize_protocol_subscription_callback_value(schema, direction, %{"ctor" => callback, "args" => [inner | _]} = wrapped)
       when is_binary(callback) and is_map(schema) and direction in [:watch_to_phone, :phone_to_watch] do
    normalized_inner = normalize_protocol_subscription_payload(schema, direction, inner)

    if normalized_inner == inner do
      wrapped
    else
      %{"ctor" => callback, "args" => [normalized_inner]}
    end
  end

  defp normalize_protocol_subscription_callback_value(_schema, _direction, message_value),
    do: message_value

  @spec normalize_protocol_subscription_payload(map(), :watch_to_phone | :phone_to_watch, term()) :: term()
  defp normalize_protocol_subscription_payload(schema, direction, %{"ctor" => "Ok", "args" => [inner | _]} = value)
       when is_map(schema) and is_map(inner) do
    normalized_inner = normalize_protocol_subscription_payload(schema, direction, inner)

    if normalized_inner == inner do
      value
    else
      %{"ctor" => "Ok", "args" => [normalized_inner]}
    end
  end

  defp normalize_protocol_subscription_payload(schema, direction, inner) when is_map(inner) do
    ctor = protocol_message_ctor(inner) || ""

    case normalize_protocol_message_value_from_schema(schema, direction, inner, ctor) do
      {_message, normalized_inner} -> normalized_inner
      :error -> inner
    end
  end

  defp normalize_protocol_subscription_payload(_schema, _direction, value), do: value

  @spec protocol_constructor_value?(Types.protocol_ctor_value()) :: boolean()
  defp protocol_constructor_value?(%{"ctor" => ctor}) when is_binary(ctor), do: true
  defp protocol_constructor_value?(%{ctor: ctor}) when is_binary(ctor), do: true
  defp protocol_constructor_value?(_value), do: false

  @spec protocol_message_display(String.t(), [Types.protocol_wire_arg()]) :: String.t()
  defp protocol_message_display(ctor, args) when is_binary(ctor) and is_list(args) do
    case args do
      [] -> ctor
      _ -> ctor <> " " <> Enum.map_join(args, " ", &protocol_arg_display/1)
    end
  end

  @spec protocol_inbound_display_message(String.t(), Types.subscription_payload() | nil) :: String.t()
  defp protocol_inbound_display_message(message, message_value) when is_binary(message) do
    case protocol_wire_message_display(message_value) do
      wire when is_binary(wire) and wire != "" -> wire
      _ -> message
    end
  end

  defp protocol_inbound_display_message(message, _message_value) when is_binary(message), do: message

  @spec protocol_wire_message_display(Types.subscription_payload() | nil) :: String.t() | nil
  defp protocol_wire_message_display(message_value) when is_map(message_value) do
    case protocol_wire_message_value(message_value) do
      %{"ctor" => ctor, "args" => args} when is_binary(ctor) and ctor != "" ->
        protocol_message_display(ctor, List.wrap(args))

      _ ->
        nil
    end
  end

  defp protocol_wire_message_display(_message_value), do: nil

  @spec protocol_wire_message_value(Types.subscription_payload()) :: map() | nil
  defp protocol_wire_message_value(%{"ctor" => ctor, "args" => args} = value)
       when ctor in @protocol_subscription_wrapper_ctors and is_list(args) do
    case List.wrap(args) do
      [%{"ctor" => result, "args" => [inner | _]} | _]
      when result in ["Ok", "Err"] and is_map(inner) ->
        protocol_wire_message_value(inner)

      [%{ctor: result, args: [inner | _]} | _]
      when result in ["Ok", "Err"] and is_map(inner) ->
        protocol_wire_message_value(inner)

      _ ->
        nil
    end
  end

  defp protocol_wire_message_value(%{"ctor" => _ctor, "args" => _args} = value), do: value
  defp protocol_wire_message_value(_value), do: nil

  @spec protocol_arg_display(
          Types.protocol_ctor_value() | String.t() | integer() | float() | boolean() | term()
        ) :: String.t()
  defp protocol_arg_display(%{"ctor" => ctor, "args" => []}) when is_binary(ctor), do: ctor
  defp protocol_arg_display(%{ctor: ctor, args: []}) when is_binary(ctor), do: ctor
  defp protocol_arg_display(value) when is_binary(value), do: inspect(value)

  defp protocol_arg_display(value) when is_integer(value) or is_float(value) or is_boolean(value),
    do: to_string(value)

  defp protocol_arg_display(value), do: inspect(value)

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

  @spec device_response_message(Types.cmd_call()) :: String.t() | nil
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

  defp device_response_message(%{
         response_message: ctor,
         kind: kind,
         preview: preview
       })
       when is_binary(ctor) and ctor != "" and
              kind in [
                "health_value",
                "health_sum_today",
                "health_sum",
                "health_accessible",
                "health_supported"
              ] do
    value =
      case preview do
        %{"value" => metric_value} -> metric_value
        metric_value -> metric_value
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

  @spec maybe_apply_runtime_followups(runtime_state(), Types.surface_target(), String.t(), String.t(), list()) :: runtime_state()
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
        runtime_followup_shadowed_by_device_data?(state, target, message, row) ->
          false

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

  defp runtime_followup_shadowed_by_device_data?(state, target, message, row)
       when is_map(state) and target in [:watch, :companion, :phone] and is_binary(message) and
              is_map(row) do
    package = Map.get(row, "package") || Map.get(row, :package)
    followup_message = Map.get(row, "message") || Map.get(row, :message)

    package == "elm-pebble/elm-watch" and is_binary(followup_message) and
      Enum.any?(device_requests_for_model(state, target, message), fn req ->
        device_response_message(req) == followup_message or
          message_constructor(device_response_message(req)) == followup_message
      end)
  end

  defp runtime_followup_shadowed_by_device_data?(_state, _target, _message, _row), do: false

  @spec maybe_apply_static_task_followups(
          runtime_state(),
          Types.surface_target(),
          String.t(),
          Types.subscription_payload(),
          String.t()
        ) :: runtime_state()
  defp maybe_apply_static_task_followups(
         state,
         _target,
         _message,
         _message_value,
         "runtime_followup"
       ),
       do: state

  defp maybe_apply_static_task_followups(state, target, message, message_value, _message_source)
       when is_map(state) and target in [:watch, :companion, :phone] and is_binary(message) do
    ei = introspect_for(state, target)
    current_ctor = message_constructor(message)
    target_name = source_root_for_target(target)

    ei
    |> static_task_followup_rows(current_ctor)
    |> Enum.take(3)
    |> Enum.reduce(state, fn row, acc ->
      callback = Map.get(row, "callback_constructor")

      with true <- is_binary(callback) and callback != "" and callback != current_ctor,
           {:ok, followup_value} <- static_task_followup_message_value(row, message_value, acc) do
        acc
        |> append_event(
          "debugger.package_cmd",
          Ide.Debugger.Types.PackageCmdEventPayload.from_static_task(
            target_name,
            "elm/core",
            callback,
            %{
              "kind" => "cmd.task.perform",
              "task_sources" => Map.get(row, "task_sources", [])
            }
          )
        )
        |> apply_step_once(
          target,
          callback,
          followup_value,
          "runtime_followup",
          "runtime_followup"
        )
      else
        _ -> acc
      end
    end)
  end

  defp maybe_apply_static_task_followups(
         state,
         _target,
         _message,
         _message_value,
         _message_source
       ),
       do: state

  @spec static_task_followup_rows(map(), String.t() | nil) :: [map()]
  defp static_task_followup_rows(ei, current_ctor)
       when is_map(ei) and is_binary(current_ctor) and current_ctor != "" do
    helper_calls =
      ei
      |> Map.get("function_cmd_calls", %{})
      |> case do
        value when is_map(value) -> value
        _ -> %{}
      end

    ei
    |> introspect_cmd_calls("update_cmd_calls")
    |> update_cmd_calls_for_message(current_ctor)
    |> Enum.flat_map(fn row ->
      helper_name = Map.get(row, "target") || Map.get(row, "name")

      case Map.get(helper_calls, helper_name) do
        calls when is_list(calls) -> calls
        _ -> []
      end
    end)
    |> Enum.filter(fn row ->
      cmd_call_name?(row, "perform") or cmd_call_target_ends_with?(row, ".perform")
    end)
  end

  defp static_task_followup_rows(_ei, _current_ctor), do: []

  @spec static_task_followup_message_value(map(), Types.subscription_payload(), map()) :: {:ok, map()} | :error
  defp static_task_followup_message_value(row, current_message_value, state)
       when is_map(row) and is_map(state) do
    callback = Map.get(row, "callback_constructor")
    captured_count = Map.get(row, "callback_arg_count", 0)

    with true <- is_binary(callback) and callback != "",
         {:ok, task_value} <- static_task_value(Map.get(row, "task_sources", []), state) do
      captured_args = captured_message_args(current_message_value, captured_count)
      {:ok, %{"ctor" => callback, "args" => captured_args ++ [task_value]}}
    else
      _ -> :error
    end
  end

  defp static_task_followup_message_value(_row, _current_message_value, _state), do: :error

  @spec captured_message_args(Types.subscription_payload(), non_neg_integer()) ::
          [Types.protocol_wire_arg()]
  defp captured_message_args(_message_value, count) when not is_integer(count) or count <= 0,
    do: []

  defp captured_message_args(%{"args" => args}, count) when is_list(args) do
    args
    |> Enum.flat_map(&unwrap_result_payload/1)
    |> Enum.take(count)
  end

  defp captured_message_args(%{args: args}, count) when is_list(args) do
    args
    |> Enum.flat_map(&unwrap_result_payload/1)
    |> Enum.take(count)
  end

  defp captured_message_args(_message_value, _count), do: []

  @spec unwrap_result_payload(Types.subscription_payload()) :: [Types.protocol_wire_arg()]
  defp unwrap_result_payload(%{"ctor" => "Ok", "args" => [value]}), do: [value]
  defp unwrap_result_payload(%{ctor: "Ok", args: [value]}), do: [value]
  defp unwrap_result_payload(value), do: [value]

  @spec static_task_value([String.t()], runtime_state()) ::
          {:ok, Types.static_task_result()} | :error
  defp static_task_value(sources, _state) when is_list(sources) do
    cond do
      "Time.now" in sources and "Time.getZoneName" in sources ->
        {:ok, {static_time_posix(), static_time_zone_name()}}

      "Time.now" in sources ->
        {:ok, static_time_posix()}

      "Time.getZoneName" in sources ->
        {:ok, static_time_zone_name()}

      true ->
        :error
    end
  end

  defp static_task_value(_sources, _state), do: :error

  @spec static_time_posix() :: map()
  defp static_time_posix do
    %{"ctor" => "Posix", "args" => [System.system_time(:millisecond)]}
  end

  @spec static_time_zone_name() :: map()
  defp static_time_zone_name do
    %{"ctor" => "Offset", "args" => [utc_offset_minutes_now()]}
  end

  @spec apply_runtime_http_followup(runtime_state(), Types.surface_target(), String.t(), String.t(), map(), String.t() | nil) :: runtime_state()
  defp apply_runtime_http_followup(state, target, target_name, package, command, followup_message)
       when target in [:watch, :companion, :phone] and is_map(command) do
    eval_context =
      state
      |> get_in([target, :model])
      |> case do
        %{} = model -> model
        _ -> %{}
      end
      |> http_eval_context(simulator_settings_from_state(state))

    case HttpExecutor.execute(command, eval_context) do
      {:ok, result} when is_map(result) ->
        response_message = Map.get(result, "message") || followup_message || "elm/http"
        message_value = Map.get(result, "message_value")

        state
        |> track_companion_http_command(command)
        |> append_event(
          "debugger.package_cmd",
          Ide.Debugger.Types.PackageCmdEventPayload.from_http(
            target_name,
            package,
            response_message,
            http_command_event(command),
            Map.get(result, "response"),
            simulated_http_response?(Map.get(result, "response")),
            followup_message
          )
        )
        |> apply_step_once(
          target,
          response_message,
          message_value,
          "runtime_followup",
          "runtime_followup"
        )

      {:error, reason} ->
        append_event(
          state,
          "debugger.package_cmd_error",
          Ide.Debugger.Types.PackageCmdErrorEventPayload.from_error(
            target_name,
            package,
            http_command_event(command),
            reason
          )
        )
    end
  end

  defp apply_runtime_http_followup(state, _target, _target_name, _package, _command, _message),
    do: state

  @spec apply_runtime_package_followup(runtime_state(), Types.surface_target(), String.t(), String.t(), map()) :: runtime_state()
  defp apply_runtime_package_followup(state, target, target_name, package, row)
       when target in [:watch, :companion, :phone] and is_map(row) do
    case Ide.Debugger.PackageCommandHandler.handle(state, target_name, package, row) do
      {:handled, next_state, event_payload, %{message: message, message_value: message_value}} ->
        next_state
        |> append_event(
          "debugger.package_cmd",
          Ide.Debugger.Types.PackageCmdEventPayload.from_handler(event_payload)
        )
        |> apply_step_once(
          target,
          message,
          message_value,
          "runtime_followup",
          "runtime_followup"
        )

      {:handled, next_state, event_payload, nil} ->
        append_event(
          next_state,
          "debugger.package_cmd",
          Ide.Debugger.Types.PackageCmdEventPayload.from_handler(event_payload)
        )

      :unhandled ->
        followup_message = Map.get(row, "message") || Map.get(row, :message)
        followup_message_value = Map.get(row, "message_value") || Map.get(row, :message_value)

        state
        |> append_event(
          "debugger.package_cmd",
          Ide.Debugger.Types.PackageCmdEventPayload.from_followup(
            target_name,
            package,
            followup_message
          )
        )
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

  @spec device_requests_for_model(runtime_state(), Types.surface_target(), String.t()) ::
          [Types.device_request()]
  defp device_requests_for_model(state, target, current_message)
       when is_map(state) and target in [:watch, :companion, :phone] and is_binary(current_message) do
    model = get_in(state, [target, :model]) || %{}
    ei = introspect_for(state, target)
    current_ctor = message_constructor(current_message)

    update_requests =
      ei
      |> introspect_cmd_calls("update_cmd_calls")
      |> update_cmd_calls_for_message(current_ctor)
      |> expand_helper_cmd_calls(ei)
      |> Enum.flat_map(&device_request_from_cmd_call/1)

    init_requests =
      ei
      |> introspect_cmd_calls("init_cmd_calls")
      |> expand_helper_cmd_calls(ei)
      |> Enum.flat_map(&device_request_from_cmd_call/1)
      |> Enum.reject(&init_device_request_deferred_to_runtime?/1)
      |> Enum.reject(&init_device_request_already_satisfied?(model, &1))

    (update_requests ++ init_requests)
    |> Enum.reject(&health_metric_request_disabled?(model, &1))
    |> Enum.reject(fn req ->
      not is_binary(req.response_message) or req.response_message == "" or
        req.response_message == current_ctor
    end)
    |> Enum.uniq_by(fn req -> {req.kind, req.response_message} end)
    |> Enum.map(&finalize_device_request(&1, model))
  end

  defp device_requests_for_model(_state, _target, _current_message), do: []

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

  @spec init_device_request_already_satisfied?(map(), map()) :: boolean()
  defp init_device_request_already_satisfied?(model, %{kind: kind})
       when is_map(model) and is_binary(kind) do
    Map.has_key?(model, "debugger_device_#{kind}")
  end

  defp init_device_request_already_satisfied?(_model, _req), do: false

  @device_kind_runtime_fields %{
    "current_time_string" => ["timeString"],
    "current_date_time" => ["currentDateTime"],
    "battery_level" => ["batteryLevel", "batteryPercent"],
    "connection_status" => ["connected", "online"],
    "timezone" => ["timezone"],
    "watch_model" => ["watchModel", "model"],
    "watch_color" => ["watchColor", "color"],
    "firmware_version" => ["firmwareVersion"]
  }

  @message_constructor_runtime_fields %{
    "CurrentTimeString" => ["timeString"],
    "CurrentTime" => ["timeString"],
    "CurrentDateTime" => ["currentDateTime"],
    "BatteryLevelChanged" => ["batteryLevel", "batteryPercent"],
    "ConnectionStatusChanged" => ["connected", "online"]
  }

  @spec device_request_from_cmd_call(Types.cmd_call()) :: [Types.device_request()]
  defp device_request_from_cmd_call(cmd_call),
    do: Ide.Debugger.DeviceRequest.from_cmd_call(cmd_call)

  @spec init_device_request_deferred_to_runtime?(map()) :: boolean()
  defp init_device_request_deferred_to_runtime?(_req), do: false

  @spec health_metric_request_disabled?(map(), map()) :: boolean()
  defp health_metric_request_disabled?(model, %{kind: kind})
       when is_map(model) and kind in ["health_value", "health_sum_today", "health_sum", "health_accessible"] do
    launch_context = Map.get(model, "launch_context") || %{}

    health_runtime_disabled?(Map.get(model, "runtime_model") || %{}) or
      Map.get(launch_context, "supports_health") != true
  end

  defp health_metric_request_disabled?(_model, _req), do: false

  @spec health_runtime_disabled?(map()) :: boolean()
  defp health_runtime_disabled?(%{"supported" => %{"ctor" => "Just", "args" => [false]}}), do: true
  defp health_runtime_disabled?(%{"supported" => %{"ctor" => "Just", "args" => [true]}}), do: false
  defp health_runtime_disabled?(_runtime_model), do: false

  @spec finalize_device_request(Types.device_request(), map()) :: Types.device_request()
  defp finalize_device_request(%{kind: "current_time_string"} = req, model) do
    now = simulator_now_from_model(model)
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

  defp finalize_device_request(%{kind: "current_date_time"} = req, model) do
    now = simulator_now_from_model(model)
    settings = simulator_settings_from_model(model)

    Map.put(req, :preview, %{
      "year" => now.year,
      "month" => now.month,
      "day" => now.day,
      "dayOfWeek" => day_of_week_name(now),
      "hour" => now.hour,
      "minute" => now.minute,
      "second" => now.second,
      "utcOffsetMinutes" => settings["timezone_offset_min"]
    })
  end

  defp finalize_device_request(%{kind: "battery_level"} = req, model) do
    settings = simulator_settings_from_model(model)
    Map.put(req, :preview, %{"batteryLevel" => settings["battery_percent"]})
  end

  defp finalize_device_request(%{kind: "connection_status"} = req, model) do
    settings = simulator_settings_from_model(model)
    Map.put(req, :preview, %{"connected" => settings["connected"]})
  end

  defp finalize_device_request(%{kind: "clock_style_24h"} = req, model) do
    settings = simulator_settings_from_model(model)
    Map.put(req, :preview, settings["clock_24h"])
  end

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
    color_mode = launch_context_color_mode(launch_context)
    Map.put(req, :preview, color_mode)
  end

  defp finalize_device_request(%{kind: "firmware_version"} = req, _model),
    do: Map.put(req, :preview, "v4.4.0-sim")

  defp finalize_device_request(%{kind: "health_value"} = req, model) do
    settings = simulator_settings_from_model(model)
    Map.put(req, :preview, %{"value" => settings["health_steps"]})
  end

  defp finalize_device_request(%{kind: "health_supported"} = req, model) do
    launch_context = Map.get(model, "launch_context") || %{}
    supported = Map.get(launch_context, "supports_health") == true
    Map.put(req, :preview, supported)
  end

  defp finalize_device_request(%{kind: "health_sum_today"} = req, model) do
    settings = simulator_settings_from_model(model)
    Map.put(req, :preview, %{"value" => settings["health_steps_today"]})
  end

  defp finalize_device_request(%{kind: "health_sum"} = req, model) do
    settings = simulator_settings_from_model(model)
    Map.put(req, :preview, %{"value" => settings["health_steps_today"]})
  end

  defp finalize_device_request(%{kind: "health_accessible"} = req, _model),
    do: Map.put(req, :preview, true)

  defp finalize_device_request(req, _model), do: Map.put(req, :preview, nil)

  @spec day_of_week_name(NaiveDateTime.t()) :: String.t()
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

  @spec apply_device_data_hint(runtime_state(), Types.surface_target(), map()) :: runtime_state()
  defp apply_device_data_hint(state, target, req)
       when is_map(state) and target in [:watch, :companion, :phone] and is_map(req) do
    model = get_in(state, [target, :model]) || %{}
    execution_model = state |> Map.get(target, %{}) |> RuntimeArtifacts.execution_model()
    runtime_model = Map.get(model, "runtime_model")
    runtime_model = if is_map(runtime_model), do: runtime_model, else: %{}
    preview = Map.get(req, :preview)

    runtime_model =
      case {Map.get(req, :kind), preview} do
        {"current_time_string", %{"string" => hhmm_text} = preview} ->
          runtime_model
          |> merge_matching_preview_fields(preview)
          |> merge_matching_preview_fields(%{"string" => hhmm_text})
          |> merge_declared_scalar_device_response(execution_model, req, hhmm_text, :string)

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
      |> normalize_runtime_model_against_introspect(execution_model)

    model =
      model
      |> Map.put("runtime_model", runtime_model)
      |> maybe_put_device_preview(req)

    view_tree = get_in(state, [target, :view_tree]) || %{}
    refreshed_model = refresh_runtime_fingerprints(model, runtime_model, view_tree)
    put_in(state, [target, :model], refreshed_model)
  end

  defp apply_device_data_hint(state, _target, _req), do: state

  @spec merge_matching_preview_fields(map(), map()) :: map()
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

  @spec merge_declared_scalar_device_response(
          map(),
          Types.execution_model(),
          Types.device_request(),
          String.t() | integer() | boolean(),
          :string | :integer | :boolean
        ) :: map()
  defp merge_declared_scalar_device_response(runtime_model, model, req, value, kind)
       when is_map(runtime_model) and is_map(model) and is_map(req) and
              kind in [:string, :integer, :boolean] do
    with true <- device_response_constructor_declared?(model, Map.get(req, :response_message)),
         {:ok, key} <- scalar_runtime_model_key_for_device_response(model, runtime_model, req, kind) do
      Map.put(runtime_model, key, value)
    else
      _ -> runtime_model
    end
  end

  defp merge_declared_scalar_device_response(runtime_model, _model, _req, _value, _kind),
    do: runtime_model

  @spec scalar_runtime_model_key_for_device_response(
          Types.execution_model(),
          map(),
          Types.device_request(),
          :string | :integer | :boolean
        ) :: {:ok, String.t()} | :error
  defp scalar_runtime_model_key_for_device_response(model, runtime_model, req, kind)
       when is_map(model) and is_map(runtime_model) and is_map(req) and
              kind in [:string, :integer, :boolean] do
    case unique_scalar_runtime_model_key(model, runtime_model, kind) do
      {:ok, key} ->
        {:ok, key}

      :error ->
        device_kind_runtime_model_key(model, runtime_model, Map.get(req, :kind), kind)
    end
  end

  @spec device_kind_runtime_model_key(
          Types.execution_model(),
          map(),
          String.t() | nil,
          :string | :integer | :boolean
        ) :: {:ok, String.t()} | :error
  defp device_kind_runtime_model_key(model, runtime_model, device_kind, kind)
       when is_map(model) and is_map(runtime_model) and kind in [:string, :integer, :boolean] do
    init_model = introspect_init_model(model)

    device_kind
    |> then(fn kind -> if is_binary(kind), do: Map.get(@device_kind_runtime_fields, kind, []), else: [] end)
    |> Enum.filter(fn key ->
      Map.has_key?(runtime_model, key) and scalar_kind?(Map.get(init_model, key), kind)
    end)
    |> case do
      [key] -> {:ok, key}
      _ -> :error
    end
  end

  defp device_kind_runtime_model_key(_model, _runtime_model, _device_kind, _kind), do: :error

  @spec device_response_constructor_declared?(Types.execution_model(), String.t() | nil) :: boolean()
  defp device_response_constructor_declared?(model, constructor)
       when is_map(model) and is_binary(constructor) and constructor != "" do
    case RuntimeArtifacts.introspect(model) do
      ei when is_map(ei) ->
        ei
        |> Map.get("update_case_branches")
        |> case do
          branches when is_list(branches) ->
            Enum.any?(branches, fn branch ->
              is_binary(branch) and message_constructor(branch) == constructor
            end)

          _ ->
            false
        end

      _ ->
        false
    end
  end

  defp device_response_constructor_declared?(_model, _constructor), do: false

  @spec unique_scalar_runtime_model_key(Types.execution_model(), map(), :string | :integer | :boolean) ::
          {:ok, String.t()} | :error
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

  @spec scalar_kind?(Types.wire_input(), :string | :integer | :boolean) :: boolean()
  defp scalar_kind?(value, :string), do: is_binary(value)
  defp scalar_kind?(value, :integer), do: is_integer(value)
  defp scalar_kind?(value, :boolean), do: is_boolean(value)

  @spec matching_model_key(map(), String.t()) :: String.t() | atom() | nil
  defp matching_model_key(model, key_text) when is_map(model) and is_binary(key_text) do
    Enum.find_value(model, fn {existing_key, _existing_value} ->
      if to_string(existing_key) == key_text, do: existing_key, else: nil
    end)
  end

  @spec coerce_preview_value(Types.protocol_wire_arg(), Types.protocol_wire_arg()) ::
          {:ok, Types.protocol_wire_arg()} | :error
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

  @spec normalize_runtime_patch_values(Types.execution_model(), map()) :: map()
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
    |> hydrate_static_runtime_model_values()
  end

  @spec normalize_runtime_model_against_introspect(map(), Types.execution_model()) :: map()
  defp normalize_runtime_model_against_introspect(runtime_model, model)
       when is_map(runtime_model) and is_map(model) do
    normalize_runtime_model_values(%{}, runtime_model, introspect_init_model(model))
  end

  defp normalize_runtime_model_against_introspect(runtime_model, _model), do: runtime_model

  @spec introspect_init_model(Types.execution_model() | map()) :: Types.init_model_values()
  defp introspect_init_model(model) when is_map(model) do
    init_model =
      case RuntimeArtifacts.introspect(model) do
        %{"init_model" => value} when is_map(value) -> value
        _ -> nil
      end

    case init_model do
      value when is_map(value) -> hydrate_static_runtime_model_values(value)
      _ -> %{}
    end
  end

  @spec normalize_runtime_shape(Types.protocol_wire_arg(), map()) :: map()
  defp normalize_runtime_shape(previous, initial) do
    cond do
      maybe_runtime_ctor?(previous) -> previous
      maybe_runtime_ctor?(initial) -> initial
      true -> previous
    end
  end

  @spec maybe_runtime_ctor?(Types.protocol_wire_arg()) :: boolean()
  defp maybe_runtime_ctor?(%{"ctor" => ctor, "args" => args})
       when ctor in ["Nothing", "Just"] and is_list(args),
       do: true

  defp maybe_runtime_ctor?(%{"$ctor" => ctor, "$args" => args})
       when ctor in ["Nothing", "Just"] and is_list(args),
       do: true

  defp maybe_runtime_ctor?(_value), do: false

  @spec normalize_runtime_value(Types.protocol_wire_normalize_input(), Types.protocol_wire_normalize_input()) ::
          Types.protocol_wire_arg()
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

  defp normalize_runtime_value(_previous, %{"ctor" => "::", "args" => [head, tail]}),
    do: elm_list_wire_to_elixir(%{"ctor" => "::", "args" => [head, tail]})

  defp normalize_runtime_value(_previous, %{"ctor" => "[]", "args" => []}), do: []

  defp normalize_runtime_value(shape, value),
    do: coerce_runtime_scalar(value, shape)

  @spec coerce_runtime_scalar(Types.wire_input(), Types.wire_input()) :: Types.wire_input()
  defp coerce_runtime_scalar(value, shape) do
    value =
      value
      |> hydrate_static_runtime_value()
      |> unwrap_just_scalar(shape)
      |> coerce_char_list_string(shape)
      |> coerce_singleton_int_list(shape)

    cond do
      is_boolean(shape) -> normalize_boolean(value, shape)
      is_boolean(value) -> value
      true -> value
    end
  end

  @spec unwrap_just_scalar(term(), term()) :: term()
  defp unwrap_just_scalar(%{"ctor" => "Just", "args" => [inner]}, %{"ctor" => "Just", "args" => [_]}),
    do: %{"ctor" => "Just", "args" => [inner]}

  defp unwrap_just_scalar(%{"ctor" => "Just", "args" => [inner]}, %{ctor: "Just", args: [_]}),
    do: %{"ctor" => "Just", "args" => [inner]}

  defp unwrap_just_scalar(%{"ctor" => "Just", "args" => [inner]}, _shape), do: inner

  defp unwrap_just_scalar(value, _shape), do: value

  @spec coerce_char_list_string(term(), term()) :: term()
  defp coerce_char_list_string(value, shape) when is_binary(shape) and is_list(value) do
    if char_list_string?(value), do: List.to_string(value), else: value
  end

  defp coerce_char_list_string(value, _shape), do: value

  @spec coerce_singleton_int_list(term(), term()) :: term()
  defp coerce_singleton_int_list([n], shape) when is_integer(shape) and is_integer(n), do: n
  defp coerce_singleton_int_list(value, _shape), do: value

  @spec char_list_string?(list()) :: boolean()
  defp char_list_string?(list) when is_list(list) do
    list != [] and Enum.all?(list, &((is_integer(&1) and &1 >= 32 and &1 <= 126) or &1 == 9))
  end

  defp char_list_string?(_list), do: false

  @spec maybe_put_device_preview(Types.app_model(), Types.device_request()) ::
          Types.app_model()
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

  @spec message_constructor(String.t()) :: String.t() | nil
  defp message_constructor(message) when is_binary(message) do
    message
    |> String.trim()
    |> String.split(~r/\s+/, parts: 2)
    |> List.first()
  end

  @spec enrich_protocol_events(
          [Types.protocol_event()],
          String.t(),
          String.t()
        ) :: [Types.protocol_event()]
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

  @spec maybe_apply_protocol_side_effects(runtime_state(), [map()], boolean()) :: runtime_state()
  defp maybe_apply_protocol_side_effects(state, _protocol_events, true), do: state

  defp maybe_apply_protocol_side_effects(state, protocol_events, false) when is_list(protocol_events) do
    state
    |> append_protocol_events(protocol_events)
    |> apply_protocol_state_effects(protocol_events)
  end

  defp maybe_apply_protocol_side_effects(state, _protocol_events, _suppress?), do: state

  @spec append_protocol_events(runtime_state(), [Types.protocol_event()]) :: runtime_state()
  defp append_protocol_events(state, protocol_events) when is_list(protocol_events) do
    Enum.reduce(protocol_events, state, fn event, acc ->
      if is_binary(event.type) and is_map(event.payload) do
        append_event(acc, event.type, event.payload)
      else
        acc
      end
    end)
  end

  @spec apply_protocol_state_effects(runtime_state(), [Types.protocol_event()]) :: runtime_state()
  defp apply_protocol_state_effects(state, protocol_events) when is_list(protocol_events) do
    Enum.reduce(protocol_events, state, fn event, acc ->
      if event.type == "debugger.protocol_rx" and is_map(event.payload) do
        handle_protocol_rx_event(acc, event.payload)
      else
        acc
      end
    end)
  end

  @spec handle_protocol_rx_event(runtime_state(), Types.protocol_tx_rx_payload()) :: runtime_state()
  defp handle_protocol_rx_event(state, payload) when is_map(payload) do
    recipient = protocol_surface_key(Map.get(payload, :to) || Map.get(payload, "to"))

    if recipient in [:watch, :companion, :phone] do
      if runtime_source_loaded?(state, recipient) do
        deliver_protocol_rx_to_surface(state, payload)
      else
        state
        |> AppMessageQueue.enqueue(recipient, payload)
        |> append_queued_protocol_timeline(recipient, payload)
      end
    else
      state
    end
  end

  @spec append_queued_protocol_timeline(runtime_state(), Types.surface_target(), map()) ::
          runtime_state()
  defp append_queued_protocol_timeline(state, recipient, payload)
       when is_map(state) and recipient in [:watch, :companion, :phone] and is_map(payload) do
    message = Map.get(payload, :message) || Map.get(payload, "message")

    if is_binary(message) and message != "" do
      append_debugger_event(state, "protocol_rx", recipient, message, "protocol_rx")
    else
      state
    end
  end

  defp append_queued_protocol_timeline(state, _recipient, _payload), do: state

  @spec deliver_protocol_rx_to_surface(runtime_state(), Types.protocol_tx_rx_payload()) ::
          runtime_state()
  defp deliver_protocol_rx_to_surface(state, payload) when is_map(payload) do
    {next_state, recipient, meta} = apply_protocol_rx_effect(state, payload)

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
      |> append_event(
        "debugger.update_in",
        Ide.Debugger.Types.MessageInEventPayload.from_message(
          source_root_for_target(recipient),
          Map.get(meta, :message),
          Map.get(meta, :message_source)
        )
      )
      |> append_event(
        "debugger.view_render",
        Ide.Debugger.Types.ViewRenderEventPayload.from_render(
          source_root_for_target(recipient),
          root
        )
      )
      |> maybe_apply_protocol_rx_subscription(recipient, meta)
    else
      next_state
    end
  end

  @spec apply_protocol_rx_effect(runtime_state(), Types.protocol_tx_rx_payload()) ::
          {runtime_state(), Types.surface_target() | nil, map()}
  defp apply_protocol_rx_effect(state, payload) when is_map(payload) do
    recipient = protocol_surface_key(Map.get(payload, :to) || Map.get(payload, "to"))
    sender = Map.get(payload, :from) || Map.get(payload, "from")
    message = Map.get(payload, :message) || Map.get(payload, "message")
    message_value = Map.get(payload, :message_value) || Map.get(payload, "message_value")
    message_source = "protocol_rx"
    inbound_display_message = protocol_inbound_display_message(message, message_value)

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
        |> put_in([recipient, :model, "protocol_last_inbound_message"], inbound_display_message)
        |> put_in(
          [recipient, :model, "protocol_last_inbound_from"],
          if(is_binary(sender), do: sender, else: "unknown")
        )
        |> update_in([recipient, :model, "protocol_inbound_count"], fn
          count when is_integer(count) and count >= 0 -> count + 1
          _ -> 1
        end)
        |> update_recipient_runtime_model_from_protocol(
          recipient,
          Map.put(row, "message", inbound_display_message)
        )
        |> patch_watch_runtime_from_protocol_message(recipient, message_value)
        |> update_recipient_protocol_view_tree(recipient, row)
        |> refresh_runtime_surface_fingerprints(recipient)

      {
        next_state,
        recipient,
        %{
          message: message,
          inbound_display_message: inbound_display_message,
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

  @spec maybe_apply_protocol_rx_subscription(runtime_state(), Types.surface_target(), map()) :: runtime_state()
  defp maybe_apply_protocol_rx_subscription(state, recipient, meta)
       when is_map(state) and recipient in [:watch, :companion, :phone] and is_map(meta) do
    source_override =
      if Map.get(meta, :trigger) == "configuration", do: "configuration", else: "protocol_rx"

    case protocol_rx_subscription_message(state, recipient, meta) do
      {message, message_value} when is_binary(message) and message != "" and is_map(message_value) ->
        message_value = normalize_protocol_subscription_message_value(state, recipient, message_value)

        state
        |> apply_step_once(recipient, message, message_value, source_override, "protocol_rx")
        |> restore_protocol_rx_metadata(recipient, meta)

      {message, _message_value} when is_binary(message) and message != "" ->
        state
        |> apply_step_once(recipient, message, source_override, "protocol_rx")
        |> restore_protocol_rx_metadata(recipient, meta)

      _ ->
        state
    end
  end

  defp maybe_apply_protocol_rx_subscription(state, _recipient, _meta), do: state

  @spec drain_app_message_queue(runtime_state(), Types.surface_target()) :: runtime_state()
  defp drain_app_message_queue(state, target)
       when is_map(state) and target in [:watch, :companion, :phone] do
    {state, entries} = AppMessageQueue.drain_entries(state, target)

    Enum.reduce(entries, state, fn payload, acc ->
      if runtime_source_loaded?(acc, target) do
        deliver_protocol_rx_to_surface(acc, payload)
      else
        AppMessageQueue.enqueue(acc, target, payload)
      end
    end)
  end

  defp drain_app_message_queue(state, _target), do: state

  @spec runtime_source_loaded?(runtime_state(), Types.surface_target()) :: boolean()
  defp runtime_source_loaded?(state, target) when is_map(state) do
    state
    |> Map.get(target, %{})
    |> RuntimeArtifacts.shell_map()
    |> Map.get("elm_introspect")
    |> is_map()
  end

  defp runtime_source_loaded?(_state, _target), do: false

  @spec runtime_entrypoint_artifacts(String.t(), map(), String.t()) :: map()
  defp runtime_entrypoint_artifacts(session_key, project, source_root)
       when is_binary(session_key) and is_binary(source_root) do
    _ = Projects.ensure_compiler_workspace(project)

    workspace_root =
      project
      |> Projects.project_workspace_path()
      |> Path.join(source_root)

    {:ok, result} =
      Compiler.compile(Projects.compiler_cache_key(session_key, source_root),
        workspace_root: workspace_root
      )

    ElmcSurfaceFields.optional_runtime_artifacts(result)
  rescue
    _ -> %{}
  end

  @spec maybe_attach_compile_artifacts_for_parser_view(
          runtime_state(),
          Types.surface_target(),
          Types.elm_introspect()
        ) :: runtime_state()
  defp maybe_attach_compile_artifacts_for_parser_view(state, target, _ei)
       when is_map(state) and target in [:watch, :companion, :phone] do
    if surface_has_core_ir?(state, target) do
      state
    else
      source_root = source_root_for_target(target)
      artifacts = compile_artifacts_for_source_root(state, source_root)
      maybe_merge_runtime_artifacts(state, target, artifacts)
    end
  end

  defp maybe_attach_compile_artifacts_for_parser_view(state, _target, _ei), do: state

  @spec ensure_surface_compile_artifacts(runtime_state(), Types.surface_target()) :: runtime_state()
  defp ensure_surface_compile_artifacts(state, target)
       when is_map(state) and target in [:watch, :companion, :phone] do
    maybe_attach_compile_artifacts_for_parser_view(state, target, %{})
  end

  defp ensure_surface_compile_artifacts(state, _target), do: state

  @spec compile_artifacts_for_source_root(runtime_state(), String.t()) :: map()
  defp compile_artifacts_for_source_root(state, source_root) when is_binary(source_root) do
    with session_key when is_binary(session_key) <- session_key_from_state(state),
         %{} = project <- Projects.get_project_by_scope_key(session_key) do
      runtime_entrypoint_artifacts(session_key, project, source_root)
    else
      _ -> %{}
    end
  rescue
    DBConnection.OwnershipError ->
      %{}

    error in RuntimeError ->
      if String.contains?(Exception.message(error), "could not lookup Ecto repo") do
        %{}
      else
        reraise(error, __STACKTRACE__)
      end
  end

  @spec surface_has_core_ir?(runtime_state(), Types.surface_target()) :: boolean()
  defp surface_has_core_ir?(state, target) when is_map(state) do
    state
    |> Map.get(target, %{})
    |> RuntimeArtifacts.execution_model()
    |> RuntimeArtifacts.decode_core_ir()
    |> is_map()
  end

  defp restore_protocol_rx_metadata(state, recipient, meta)
       when is_map(state) and recipient in [:watch, :companion, :phone] and is_map(meta) do
    inbound_display_message =
      Map.get(meta, :inbound_display_message) || Map.get(meta, :message)

    state =
      state
      |> put_in([recipient, :model, "protocol_last_inbound_message"], inbound_display_message)
      |> put_in([recipient, :model, "protocol_last_inbound_from"], Map.get(meta, :from))
      |> put_in([recipient, :model, "protocol_inbound_count"], Map.get(meta, :inbound_count))

    if recipient in [:companion, :phone] do
      update_in(state, [recipient, :model, "runtime_model"], fn runtime_model ->
        runtime_model = if is_map(runtime_model), do: runtime_model, else: %{}

        runtime_model
        |> Map.put("protocol_last_inbound_message", inbound_display_message)
        |> Map.put("protocol_last_inbound_from", Map.get(meta, :from))
        |> Map.put("protocol_inbound_count", Map.get(meta, :inbound_count))
      end)
    else
      state
    end
  end

  @spec protocol_rx_subscription_message(runtime_state(), Types.surface_target(), map()) ::
          {String.t(), term()} | String.t() | nil
  defp protocol_rx_subscription_message(state, recipient, meta)
       when is_map(state) and recipient in [:watch, :companion, :phone] and is_map(meta) do
    from = Map.get(meta, :from)
    message = Map.get(meta, :message)
    message_value = Map.get(meta, :message_value)

    cond do
      not is_binary(message) or message == "" ->
        nil

      recipient == :watch and from in ["companion", "phone"] ->
        callback =
          protocol_rx_subscription_callback(state, recipient, "on_phone_to_watch") || "FromPhone"

        protocol_callback_message(callback, message, message_value, false)

      recipient in [:companion, :phone] and from == "watch" ->
        callback =
          protocol_rx_subscription_callback(state, recipient, "on_watch_to_phone") || "FromWatch"

        protocol_callback_message(callback, message, message_value, true)

      true ->
        nil
    end
  end

  defp protocol_rx_subscription_message(_state, _recipient, _meta), do: nil

  @spec protocol_rx_subscription_callback(runtime_state(), Types.surface_target(), String.t()) :: String.t() | nil
  defp protocol_rx_subscription_callback(state, recipient, event_kind)
       when is_map(state) and recipient in [:watch, :companion, :phone] and is_binary(event_kind) do
    state
    |> introspect_for(recipient)
    |> introspect_cmd_calls("subscription_calls")
    |> Enum.find_value(fn row ->
      if Map.get(row, "event_kind") == event_kind do
        callback = Map.get(row, "callback_constructor")
        if is_binary(callback) and callback != "", do: callback, else: nil
      end
    end)
  end

  defp protocol_rx_subscription_callback(_state, _recipient, _event_kind), do: nil

  @spec protocol_callback_message(String.t() | nil, String.t(), Types.subscription_payload(), boolean()) ::
          {String.t(), term()} | String.t() | nil
  defp protocol_callback_message(callback, message, message_value, wrap_result?)
       when is_binary(callback) and callback != "" and is_binary(message) and message != "" do
    already_wrapped? = wrap_result? and String.starts_with?(message, "#{callback} (Ok ")

    message =
      if already_wrapped? do
        message
      else
        parenthesize_elm_arg(message)
      end

    {display, value} =
      cond do
        already_wrapped? and is_map(message_value) ->
          {message, message_value}

        wrap_result? ->
          {
            "#{callback} (Ok #{message})",
            if(is_map(message_value),
              do:
                wrap_protocol_callback_value(
                  callback,
                  %{"ctor" => "Ok", "args" => [message_value]}
                ),
              else: nil
            )
          }

        true ->
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

  @spec wrap_protocol_callback_value(String.t(), Types.subscription_payload()) :: map() | nil
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

  @spec update_recipient_protocol_messages(runtime_state(), Types.surface_target(), map()) :: runtime_state()
  defp update_recipient_protocol_messages(state, recipient, row)
       when recipient in [:watch, :companion, :phone] do
    update_in(state, [recipient, :protocol_messages], fn
      xs when is_list(xs) -> [row | xs] |> Enum.take(25)
      _ -> [row]
    end)
  end

  defp update_recipient_protocol_messages(state, _recipient, _row), do: state

  @spec update_recipient_runtime_model_from_protocol(runtime_state(), Types.surface_target(), map()) :: runtime_state()
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

  @spec update_recipient_protocol_view_tree(runtime_state(), Types.surface_target(), map()) :: runtime_state()
  defp update_recipient_protocol_view_tree(state, recipient, row)
       when recipient in [:watch, :companion, :phone] and is_map(row) do
    put_in(state, [recipient, :model, "protocol_last_view_message"], row["message"])
  end

  @spec patch_watch_runtime_from_protocol_message(runtime_state(), Types.surface_target(), term()) ::
          runtime_state()
  defp patch_watch_runtime_from_protocol_message(state, :watch, message_value) do
    ei = introspect_for(state, :watch)

    patch =
      case subscription_payload_model_patch(ei, message_value) do
        patch when is_map(patch) and map_size(patch) > 0 -> patch
        _ -> protocol_runtime_model_patch_from_message_value(ei, message_value)
      end

    state =
      if map_size(patch) > 0 do
        update_in(state, [:watch, :model], fn model ->
          merge_protocol_runtime_model_patch(model, patch, ei)
        end)
      else
        state
      end

    case protocol_watch_online_from_message_value(message_value) do
      online when is_boolean(online) ->
        update_in(state, [:watch, :model, "runtime_model"], fn runtime_model ->
          runtime_model = if is_map(runtime_model), do: runtime_model, else: %{}
          Map.put(runtime_model, "online", online)
        end)

      _ ->
        state
    end
  end

  defp patch_watch_runtime_from_protocol_message(state, _recipient, _message_value), do: state

  @spec merge_protocol_runtime_model_patch(map(), map(), map() | nil) :: map()
  defp merge_protocol_runtime_model_patch(model, patch, introspect) when is_map(model) do
    if is_map(patch) and patch != %{} and not noop_provide_position_patch?(patch) do
      patch =
        patch
        |> reject_protocol_result_wrapper_patch_values()
        |> promote_protocol_result_record_patch()
        |> align_protocol_patch_to_init_model(introspect)
        |> wrap_protocol_patch_fields_to_init_model(introspect)

      update_in(model, ["runtime_model"], fn runtime_model ->
        Map.merge(if(is_map(runtime_model), do: runtime_model, else: %{}), patch)
      end)
    else
      model
    end
  end

  @spec reject_protocol_result_wrapper_patch_values(map()) :: map()
  defp reject_protocol_result_wrapper_patch_values(patch) when is_map(patch) do
    patch
    |> Enum.reject(fn {_key, value} -> protocol_result_wrapper_patch_value?(value) end)
    |> Map.new()
  end

  @spec protocol_result_wrapper_patch_value?(term()) :: boolean()
  defp protocol_result_wrapper_patch_value?(%{"ctor" => ctor, "args" => _})
       when ctor in ["Ok", "Err"],
       do: true

  defp protocol_result_wrapper_patch_value?(_), do: false

  @spec noop_provide_position_patch?(map()) :: boolean()
  defp noop_provide_position_patch?(%{
         "latitudeE6" => 0,
         "longitudeE6" => 0,
         "accuracyM" => 0
       }),
       do: true

  defp noop_provide_position_patch?(_patch), do: false

  @spec align_protocol_patch_to_init_model(map(), map() | nil) :: map()
  defp align_protocol_patch_to_init_model(patch, introspect) when is_map(patch) and is_map(introspect) do
    init_keys =
      (Map.get(introspect, "init_model") || %{})
      |> Map.keys()
      |> Enum.map(&to_string/1)

    patch
    |> remap_geolocation_patch_keys()
    |> Enum.reduce(%{}, fn {key, value}, acc ->
      key = to_string(key)

      cond do
        key in init_keys ->
          Map.put(acc, key, value)

        true ->
          case model_field_for_patch_field(key, init_keys) do
            target when is_binary(target) -> Map.put(acc, target, value)
            _ -> acc
          end
      end
    end)
  end

  defp align_protocol_patch_to_init_model(patch, _introspect), do: remap_geolocation_patch_keys(patch)

  @spec remap_geolocation_patch_keys(map()) :: map()
  defp remap_geolocation_patch_keys(patch) when is_map(patch) do
    patch
    |> maybe_remap_patch_key("latitude", "latitudeE6", &latitude_to_microdegrees/1)
    |> maybe_remap_patch_key("longitude", "longitudeE6", &longitude_to_microdegrees/1)
    |> maybe_remap_patch_key("accuracy", "accuracyM", &round_float/1)
  end

  @spec maybe_remap_patch_key(map(), String.t(), String.t(), (term() -> term())) :: map()
  defp maybe_remap_patch_key(patch, from, to, converter) when is_map(patch) and is_binary(from) and is_binary(to) do
    case Map.fetch(patch, from) do
      {:ok, value} -> patch |> Map.delete(from) |> Map.put(to, converter.(value))
      :error -> patch
    end
  end

  @spec latitude_to_microdegrees(term()) :: integer()
  defp latitude_to_microdegrees(value) when is_integer(value) and value > 1_000_000, do: value

  defp latitude_to_microdegrees(value) when is_integer(value),
    do: round(value * 1_000_000)

  defp latitude_to_microdegrees(value) when is_float(value),
    do: round(value * 1_000_000)

  defp latitude_to_microdegrees(value), do: value

  @spec longitude_to_microdegrees(term()) :: integer()
  defp longitude_to_microdegrees(value) when is_integer(value) and abs(value) > 1_000_000, do: value

  defp longitude_to_microdegrees(value) when is_integer(value),
    do: round(value * 1_000_000)

  defp longitude_to_microdegrees(value) when is_float(value),
    do: round(value * 1_000_000)

  defp longitude_to_microdegrees(value), do: value

  @spec model_field_for_patch_field(String.t(), [String.t()]) :: String.t() | nil
  defp model_field_for_patch_field(patch_key, init_keys) when is_binary(patch_key) and is_list(init_keys) do
    suffix =
      patch_key
      |> String.split("_")
      |> Enum.map_join("", &String.capitalize/1)

    Enum.find(init_keys, fn model_key ->
      is_binary(model_key) and model_key != patch_key and String.ends_with?(model_key, suffix)
    end)
  end

  defp model_field_for_patch_field(_patch_key, _init_keys), do: nil

  @spec protocol_runtime_model_patch_from_message_value(map() | nil, term()) :: map()
  defp protocol_runtime_model_patch_from_message_value(introspect, %{"ctor" => "FromPhone", "args" => [inner | _]})
       when is_map(introspect) and is_map(inner) do
    protocol_runtime_model_patch_from_message_value(introspect, inner)
  end

  defp protocol_runtime_model_patch_from_message_value(introspect, %{ctor: "FromPhone", args: [inner | _]})
       when is_map(introspect) and is_map(inner) do
    protocol_runtime_model_patch_from_message_value(introspect, %{"ctor" => "FromPhone", "args" => [inner]})
  end

  defp protocol_runtime_model_patch_from_message_value(introspect, %{"ctor" => ctor, "args" => args})
       when is_map(introspect) and is_binary(ctor) and is_list(args) do
    with names when length(names) == length(args) <-
           protocol_ctor_binding_names(introspect, ctor) do
      names
      |> Enum.zip(args)
      |> Map.new(fn {key, value} -> {key, wrap_protocol_patch_value(introspect, key, value)} end)
      |> promote_protocol_result_record_patch()
      |> apply_update_branch_field_aliases(introspect, ctor)
    else
      _ ->
        case protocol_provide_ctor_patch(introspect, %{"ctor" => ctor, "args" => args}) do
          patch when is_map(patch) and map_size(patch) > 0 ->
            patch

          _ ->
            protocol_runtime_model_patch_from_ok_payload(introspect, args)
        end
    end
  end

  defp protocol_runtime_model_patch_from_message_value(introspect, %{ctor: ctor, args: args})
       when is_map(introspect) and is_binary(ctor) and is_list(args) do
    protocol_runtime_model_patch_from_message_value(introspect, %{"ctor" => ctor, "args" => args})
  end

  defp protocol_runtime_model_patch_from_message_value(introspect, %{"ctor" => callback, "args" => [inner | _]})
       when is_map(introspect) and is_binary(callback) and is_map(inner) do
    with %{"ctor" => ctor, "args" => args} <- inner,
         true <- is_binary(ctor) and is_list(args),
         names when length(names) == length(args) <-
           protocol_update_binding_names(introspect, callback, ctor) do
      names
      |> Enum.zip(args)
      |> Map.new()
    else
      _ -> %{}
    end
  end

  defp protocol_runtime_model_patch_from_message_value(_introspect, _message_value), do: %{}

  @spec protocol_provide_ctor_patch(map(), map()) :: map()
  defp protocol_provide_ctor_patch(introspect, %{"ctor" => "ProvidePosition", "args" => args})
       when is_map(introspect) and is_list(args) do
    case args do
      [lat, lon, acc | _] when is_number(lat) and is_number(lon) and is_number(acc) ->
        %{
          "latitudeE6" => protocol_position_microdegrees(lat),
          "longitudeE6" => protocol_position_microdegrees(lon),
          "accuracyM" => round(acc)
        }
        |> align_protocol_patch_to_init_model(introspect)

      _ ->
        %{}
    end
  end

  defp protocol_provide_ctor_patch(introspect, %{"ctor" => ctor, "args" => args})
       when is_map(introspect) and is_binary(ctor) and is_list(args) do
    if String.starts_with?(ctor, "Provide") do
      case provide_ctor_model_field(introspect, ctor) do
        field when is_binary(field) ->
          value =
            case args do
              [one] -> wrap_protocol_patch_value(introspect, field, one)
              _ -> wrap_protocol_patch_value(introspect, field, args)
            end

          %{field => value}
          |> mirror_related_runtime_model_fields(introspect)

        _ ->
          %{}
      end
    else
      %{}
    end
  end

  defp protocol_provide_ctor_patch(_introspect, _message_value), do: %{}

  @spec mirror_related_runtime_model_fields(map(), map()) :: map()
  defp mirror_related_runtime_model_fields(patch, introspect) when is_map(patch) and is_map(introspect) do
    init = Map.get(introspect, "init_model") || %{}

    Enum.reduce(patch, patch, fn {source_key, value}, acc ->
      target =
        introspect
        |> Map.get("update_case_branches", [])
        |> Enum.find_value(fn branch ->
          if is_binary(branch) and String.contains?(branch, "Provide") do
            branch
            |> parse_update_branch_field_aliases()
            |> Map.get(source_key)
          end
        end)

      case {value, target, Map.has_key?(init, target)} do
        {val, field, true} when not is_nil(val) and is_binary(field) -> Map.put(acc, field, val)
        _ -> acc
      end
    end)
  end

  defp mirror_related_runtime_model_fields(patch, _introspect), do: patch

  @spec provide_ctor_model_field(map(), String.t()) :: String.t() | nil
  defp provide_ctor_model_field(introspect, ctor) when is_map(introspect) and is_binary(ctor) do
    case protocol_ctor_binding_names(introspect, ctor) do
      [field | _] when is_binary(field) -> field
      _ -> nil
    end
  end

  defp provide_ctor_model_field(_introspect, _ctor), do: nil

  @spec protocol_position_microdegrees(number()) :: integer()
  defp protocol_position_microdegrees(value) when is_integer(value) and abs(value) > 1_000_000,
    do: value

  defp protocol_position_microdegrees(value) when is_integer(value),
    do: round(value * 1_000_000)

  defp protocol_position_microdegrees(value) when is_float(value),
    do: round(value * 1_000_000)

  @spec wrap_protocol_patch_value(map(), String.t(), term()) :: term()
  defp wrap_protocol_patch_value(introspect, field, value) when is_map(introspect) and is_binary(field) do
    case value do
      %{"ctor" => ctor, "args" => _} when ctor in ["Just", "Nothing", "Ok", "Err"] ->
        value

      %{ctor: ctor, args: _} when ctor in ["Just", "Nothing", "Ok", "Err"] ->
        %{"ctor" => to_string(ctor), "args" => Map.get(value, :args) || []}

      _ ->
        wrap_protocol_patch_value_for_init(introspect, field, value)
    end
  end

  defp wrap_protocol_patch_value(_introspect, _field, value), do: value

  @spec wrap_protocol_patch_value_for_init(map(), String.t(), term()) :: term()
  defp wrap_protocol_patch_value_for_init(introspect, field, value) when is_map(introspect) and is_binary(field) do
    init = Map.get(introspect, "init_model") || %{}

    case Map.get(init, field) do
      %{"ctor" => "Just"} -> %{"ctor" => "Just", "args" => [value]}
      %{ctor: "Just"} -> %{"ctor" => "Just", "args" => [value]}
      %{"$ctor" => "Just"} -> %{"ctor" => "Just", "args" => [value]}
      %{"$ctor" => "Nothing"} -> %{"ctor" => "Just", "args" => [value]}
      %{ctor: "Nothing"} -> %{"ctor" => "Just", "args" => [value]}
      _ -> value
    end
  end

  defp wrap_protocol_patch_value_for_init(_introspect, _field, value), do: value

  @spec wrap_protocol_patch_fields_to_init_model(map(), map() | nil) :: map()
  defp wrap_protocol_patch_fields_to_init_model(patch, introspect) when is_map(patch) and is_map(introspect) do
    Map.new(patch, fn {key, value} ->
      {key, wrap_protocol_patch_value(introspect, key, value)}
    end)
  end

  defp wrap_protocol_patch_fields_to_init_model(patch, _introspect), do: patch

  @spec subscription_payload_model_patch(map() | nil, term()) :: map()
  defp subscription_payload_model_patch(introspect, %{"ctor" => _ctor, "args" => args})
       when is_map(introspect) and is_list(args) do
    protocol_runtime_model_patch_from_ok_payload(introspect, args)
  end

  defp subscription_payload_model_patch(introspect, %{ctor: _ctor, args: args})
       when is_map(introspect) and is_list(args) do
    subscription_payload_model_patch(introspect, %{"ctor" => "Msg", "args" => args})
  end

  defp subscription_payload_model_patch(_introspect, _message_value), do: %{}

  @spec protocol_runtime_model_patch_from_ok_payload(map(), list()) :: map()
  defp protocol_runtime_model_patch_from_ok_payload(introspect, [%{"ctor" => "Ok", "args" => [record | _]} | _])
       when is_map(introspect) and is_map(record) do
    record
    |> promote_protocol_result_record_patch()
    |> align_protocol_patch_to_init_model(introspect)
  end

  defp protocol_runtime_model_patch_from_ok_payload(introspect, [%{ctor: "Ok", args: [record | _]} | _])
       when is_map(introspect) and is_map(record) do
    protocol_runtime_model_patch_from_ok_payload(introspect, [
      %{"ctor" => "Ok", "args" => [record]}
    ])
  end

  defp protocol_runtime_model_patch_from_ok_payload(_introspect, _args), do: %{}

  @spec apply_update_branch_field_aliases(map(), map(), String.t()) :: map()
  defp apply_update_branch_field_aliases(patch, introspect, ctor)
       when is_map(patch) and is_map(introspect) and is_binary(ctor) do
    aliases = update_branch_field_aliases(introspect, ctor)

    Map.new(patch, fn {key, value} ->
      {Map.get(aliases, key, key), value}
    end)
  end

  defp apply_update_branch_field_aliases(patch, _introspect, _ctor), do: patch

  @spec update_branch_field_aliases(map(), String.t()) :: %{String.t() => String.t()}
  defp update_branch_field_aliases(introspect, ctor) when is_map(introspect) and is_binary(ctor) do
    introspect
    |> Map.get("update_case_branches", [])
    |> Enum.find_value(fn branch ->
      if is_binary(branch) and String.contains?(branch, ctor <> " ") do
        parse_update_branch_field_aliases(branch)
      end
    end)
    |> case do
      aliases when is_map(aliases) -> aliases
      _ -> %{}
    end
  end

  @spec parse_update_branch_field_aliases(String.t()) :: %{String.t() => String.t()}
  defp parse_update_branch_field_aliases(branch) when is_binary(branch) do
    ~r/([a-z][A-Za-z0-9_]*)\s*=\s*([a-z][A-Za-z0-9_]*)\.([a-z][A-Za-z0-9_]*)/u
    |> Regex.scan(branch)
    |> Map.new(fn [_full, target, _binding, source] -> {source, target} end)
  end

  @spec promote_protocol_result_record_patch(map()) :: map()
  defp promote_protocol_result_record_patch(patch) when is_map(patch) do
    case patch do
      %{"info" => wrapper} ->
        promote_protocol_result_wrapper(wrapper, Map.delete(patch, "info"))

      %{"value" => wrapper} ->
        promote_protocol_result_wrapper(wrapper, Map.delete(patch, "value"))

      patch ->
        Enum.reduce(patch, patch, fn {key, value}, acc ->
          case promote_protocol_result_wrapper(value, %{}) do
            extra when map_size(extra) > 0 -> Map.merge(Map.delete(acc, key), extra)
            _ -> acc
          end
        end)
    end
  end

  @spec promote_protocol_result_wrapper(term(), map()) :: map()
  defp promote_protocol_result_wrapper(%{"ctor" => ctor, "args" => [record | _]}, extra)
       when ctor in ["Ok", "Err"] and is_map(record) do
    cond do
      maybe_runtime_ctor?(record) -> extra
      elm_message_constructor_map?(record) -> extra
      true -> Map.merge(extra, record)
    end
  end

  defp promote_protocol_result_wrapper(%{ctor: ctor, args: [record | _]}, extra)
       when ctor in ["Ok", "Err"] and is_map(record) do
    promote_protocol_result_wrapper(%{"ctor" => ctor, "args" => [record]}, extra)
  end

  defp promote_protocol_result_wrapper(_wrapper, extra), do: extra

  @spec protocol_ctor_binding_names(map(), String.t()) :: [String.t()]
  defp protocol_ctor_binding_names(introspect, ctor) when is_map(introspect) and is_binary(ctor) do
    introspect
    |> Map.get("update_case_branches", [])
    |> Enum.find_value(fn branch ->
      if is_binary(branch) and String.contains?(branch, ctor) do
        parse_update_branch_binding_names(branch, ctor)
      end
    end)
    |> case do
      names when is_list(names) -> names
      _ -> []
    end
  end

  @spec protocol_update_binding_names(map(), String.t(), String.t()) :: [String.t()]
  defp protocol_update_binding_names(introspect, callback, ctor)
       when is_map(introspect) and is_binary(callback) and is_binary(ctor) do
    prefix = callback <> " " <> ctor

    introspect
    |> Map.get("update_case_branches", [])
    |> Enum.find(fn branch ->
      is_binary(branch) and String.starts_with?(String.trim(branch), prefix)
    end)
    |> case do
      branch when is_binary(branch) -> parse_update_branch_binding_names(branch, ctor)
      _ -> []
    end
  end

  @spec parse_update_branch_binding_names(String.t(), String.t()) :: [String.t()]
  defp parse_update_branch_binding_names(branch, ctor) when is_binary(branch) and is_binary(ctor) do
    trimmed = String.trim(branch)

    cond do
      String.starts_with?(trimmed, ctor <> " ") ->
        trimmed
        |> String.replace_prefix(ctor, "")
        |> String.trim()
        |> String.split(~r/\s+/, trim: true)
        |> Enum.reject(&(&1 in ["Ok", "Err", "Nothing", "Just"] or &1 == ctor))

      true ->
        inner =
          case Regex.run(~r/#{Regex.escape(ctor)}\s*\(([^)]*)\)/u, trimmed) do
            [_, captured] -> captured
            _ -> trimmed |> String.replace_prefix(ctor, "") |> String.trim()
          end

        ~r/[A-Za-z][A-Za-z0-9_]*/
        |> Regex.scan(inner)
        |> List.flatten()
        |> Enum.reject(&(&1 in ["Ok", "Err", "Nothing", "Just"] or &1 == ctor))
    end
  end

  @spec protocol_watch_online_from_message_value(term()) :: boolean() | nil
  defp protocol_watch_online_from_message_value(%{"ctor" => "FromPhone", "args" => [inner | _]})
       when is_map(inner),
       do: protocol_watch_online_from_message_value(inner)

  defp protocol_watch_online_from_message_value(%{"ctor" => "ProvideConnectivity", "args" => [online | _]})
       when is_boolean(online),
       do: online

  defp protocol_watch_online_from_message_value(%{ctor: "FromPhone", args: [inner | _]}) when is_map(inner),
       do: protocol_watch_online_from_message_value(inner)

  defp protocol_watch_online_from_message_value(%{ctor: "ProvideConnectivity", args: [online | _]})
       when is_boolean(online),
       do: online

  defp protocol_watch_online_from_message_value(_message_value), do: nil

  @spec refresh_runtime_surface_fingerprints(runtime_state(), Types.surface_target()) :: runtime_state()
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

  @spec protocol_surface_key(Types.surface_label_input()) :: :watch | :companion | :phone
  defp protocol_surface_key("watch"), do: :watch
  defp protocol_surface_key("companion"), do: :companion
  defp protocol_surface_key("phone"), do: :phone
  defp protocol_surface_key(_), do: :companion

  @spec surface_label(Types.surface_target()) :: String.t()
  defp surface_label(:watch), do: "watch"
  defp surface_label(:companion), do: "companion"
  defp surface_label(:phone), do: "phone"

  @spec tick_targets(Types.surface_target() | nil) :: [:watch | :companion | :phone]
  defp tick_targets(nil), do: [:watch, :companion, :phone]
  defp tick_targets(target) when target in [:watch, :companion, :phone], do: [target]

  @spec trigger_candidates_for_surface(runtime_state(), Types.surface_target()) ::
          [Types.trigger_candidate()]
  defp trigger_candidates_for_surface(state, target)
       when is_map(state) and target in [:watch, :companion, :phone] do
    ei = introspect_for(state, target)
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

        trigger_row = %{
          trigger: to_string(trigger || "trigger"),
          message: message,
          target: target_name
        }

        %{
          id: "#{target_name}:#{trigger_id}:#{normalize_trigger_id(message)}",
          label: normalize_trigger_label(label),
          trigger: trigger_row.trigger,
          trigger_display: subscription_trigger_display(op, trigger),
          target: target_name,
          message: message,
          source: "subscription",
          model_active: subscription_model_active?(state, target, trigger_row)
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
          trigger_display: camel_case_trigger_id(op),
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
          trigger_display: camel_case_trigger_id(trigger),
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

  @spec button_subscription_metadata(Types.cmd_call()) :: map()
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

  @spec frame_subscription_interval_ms(String.t(), [map()]) :: integer() | nil
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

  @spec clamp_auto_fire_interval_ms(Types.wire_input()) :: pos_integer()
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

  @spec frame_subscription_target?(String.t()) :: boolean()
  defp frame_subscription_target?(target) when is_binary(target) do
    normalized =
      target
      |> String.downcase()
      |> String.replace(~r/[^a-z0-9.]+/, "")

    String.contains?(normalized, "frame.") or String.ends_with?(normalized, ".onframe") or
      String.ends_with?(normalized, "onframe")
  end

  @spec subscription_target_name(String.t()) :: String.t()
  defp subscription_target_name(target) when is_binary(target) do
    target
    |> String.split(".")
    |> List.last()
    |> to_string()
  end

  @spec normalize_button_subscription_arg(String.t()) :: String.t()
  defp normalize_button_subscription_arg(value) when is_binary(value) do
    value
    |> String.split(".")
    |> List.last()
    |> to_string()
    |> String.downcase()
  end

  @spec subscription_call_fireable?(Types.cmd_call()) :: boolean()
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

  @spec subscription_op_fireable?(Types.cmd_call()) :: boolean()
  defp subscription_op_fireable?(op) when is_binary(op) do
    normalized =
      op
      |> String.downcase()
      |> String.replace(~r/[^a-z0-9]+/, "_")
      |> String.trim("_")

    normalized not in ["", "sub_none", "none", "sub_batch", "batch"]
  end

  defp subscription_op_fireable?(_op), do: false

  @doc false
  @spec subscription_model_active?(runtime_state(), Types.surface_target(), map()) :: boolean()
  def subscription_model_active?(state, target, row)
      when is_map(state) and target in [:watch, :companion, :phone] and is_map(row) do
    guards = subscription_activation_guards_for_row(state, target, row)
    guards == :always or subscription_guards_satisfied?(state, target, guards)
  end

  def subscription_model_active?(_state, _target, _row), do: true

  @spec subscription_activation_guards_for_row(runtime_state(), Types.surface_target(), map()) ::
          :always | [map()]
  defp subscription_activation_guards_for_row(state, target, row)
       when is_map(state) and target in [:watch, :companion, :phone] and is_map(row) do
    ei = introspect_for(state, target)
    calls = introspect_cmd_calls(ei, "subscription_calls")

    row_trigger =
      row
      |> trigger_candidate_field(:trigger)
      |> to_string()
      |> normalize_trigger_id()

    row_message =
      row
      |> trigger_candidate_field(:message)
      |> case do
        message when is_binary(message) -> String.trim(message)
        _ -> ""
      end

    matching =
      Enum.filter(calls, fn call ->
        call_trigger =
          call
          |> subscription_trigger_for_call()
          |> to_string()
          |> normalize_trigger_id()

        call_message = Map.get(call, "callback_constructor") |> to_string()

        call_trigger == row_trigger and
          (row_message == "" or call_message == "" or call_message == row_message)
      end)

    case matching do
      [%{"activation_guards" => guards} | _] when is_list(guards) and guards != [] ->
        guards

      _ ->
        :always
    end
  end

  defp subscription_activation_guards_for_row(_state, _target, _row), do: :always

  @spec subscription_guards_satisfied?(runtime_state(), Types.surface_target(), [map()]) ::
          boolean()
  defp subscription_guards_satisfied?(state, target, guards)
       when is_map(state) and target in [:watch, :companion, :phone] and is_list(guards) do
    Enum.all?(guards, &subscription_guard_satisfied?(state, target, &1))
  end

  defp subscription_guards_satisfied?(_state, _target, _guards), do: true

  @spec subscription_guard_satisfied?(runtime_state(), Types.surface_target(), map()) :: boolean()
  defp subscription_guard_satisfied?(state, target, %{"kind" => "field_truthy", "subject" => subject})
       when is_map(state) and target in [:watch, :companion, :phone] and is_binary(subject) do
    case runtime_field_value(state, target, subject) do
      {:ok, value} -> runtime_value_truthy?(value)
      _ -> false
    end
  end

  defp subscription_guard_satisfied?(state, target, %{"kind" => "field_falsy", "subject" => subject})
       when is_map(state) and target in [:watch, :companion, :phone] and is_binary(subject) do
    case runtime_field_value(state, target, subject) do
      {:ok, value} -> not runtime_value_truthy?(value)
      _ -> false
    end
  end

  defp subscription_guard_satisfied?(state, target, %{
         "kind" => "case_branch",
         "subject" => subject,
         "branch" => branch
       })
       when is_map(state) and target in [:watch, :companion, :phone] and is_binary(subject) and
              is_binary(branch) do
    case runtime_field_value(state, target, subject) do
      {:ok, value} -> runtime_value_branch_label(value) == branch
      _ -> false
    end
  end

  defp subscription_guard_satisfied?(_state, _target, _guard), do: true

  @spec runtime_field_value(runtime_state(), Types.surface_target(), String.t()) ::
          {:ok, term()} | :error
  defp runtime_field_value(state, target, subject)
       when is_map(state) and target in [:watch, :companion, :phone] and is_binary(subject) do
    model = get_in(state, [target, :model]) || %{}
    runtime_model = Map.get(model, "runtime_model")
    runtime_model = if is_map(runtime_model), do: runtime_model, else: %{}
    ei = introspect_for(state, target) || %{}
    subscriptions_params = introspect_list(ei, "subscriptions_params")

    case runtime_field_key(subject, subscriptions_params) do
      "" ->
        :error

      field ->
        value =
          case Map.fetch(runtime_model, field) do
            {:ok, found} -> hydrate_static_runtime_value(found)
            :error ->
              init =
                case introspect_for(state, target) do
                  %{"init_model" => value} when is_map(value) -> value
                  _ -> %{}
                end

              hydrate_static_runtime_value(Map.get(init, field))
          end

        {:ok, value}
    end
  end

  defp runtime_field_value(_state, _target, _subject), do: :error

  @spec runtime_field_key(String.t(), Types.param_list()) :: String.t()
  defp runtime_field_key(subject, subscriptions_params)
       when is_binary(subject) and is_list(subscriptions_params) do
    Enum.find_value(subscriptions_params, fn param ->
      prefix = param <> "."

      if is_binary(param) and param != "_" and param != "" and String.starts_with?(subject, prefix) do
        String.replace_prefix(subject, prefix, "")
      end
    end) || ""
  end

  defp runtime_field_key(_subject, _subscriptions_params), do: ""

  @spec runtime_value_truthy?(term()) :: boolean()
  defp runtime_value_truthy?(value) when is_boolean(value), do: value
  defp runtime_value_truthy?(nil), do: false
  defp runtime_value_truthy?(0), do: false
  defp runtime_value_truthy?(%{"ctor" => "Nothing", "args" => []}), do: false
  defp runtime_value_truthy?(%{"$ctor" => "Nothing", "$args" => []}), do: false

  defp runtime_value_truthy?(%{"ctor" => "Just", "args" => [value]}),
    do: runtime_value_truthy?(value)

  defp runtime_value_truthy?(%{"$ctor" => "Just", "$args" => [value]}),
    do: runtime_value_truthy?(value)

  defp runtime_value_truthy?(value) when is_binary(value) do
    case normalize_runtime_boolean_string(value) do
      bool when is_boolean(bool) -> bool
      _ -> String.trim(value) != ""
    end
  end

  defp runtime_value_truthy?(_value), do: true

  @spec runtime_value_branch_label(term()) :: String.t()
  defp runtime_value_branch_label(value) when is_binary(value), do: value
  defp runtime_value_branch_label(value) when is_atom(value), do: Atom.to_string(value)

  defp runtime_value_branch_label(%{"ctor" => ctor, "args" => _})
       when is_binary(ctor),
       do: ctor

  defp runtime_value_branch_label(%{"$ctor" => ctor, "$args" => _})
       when is_binary(ctor),
       do: ctor

  defp runtime_value_branch_label(value), do: to_string(value)

  @spec trigger_message_for_surface(runtime_state(), Types.surface_target(), String.t(), String.t() | nil) ::
          String.t()
  defp trigger_message_for_surface(state, target, trigger, requested_message)
       when is_map(state) and target in [:watch, :companion, :phone] and is_binary(trigger) do
    message =
      if is_binary(requested_message) and requested_message != "" do
        requested_message
      else
        ei = introspect_for(state, target)
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

  @spec maybe_attach_subscription_payload(runtime_state() | map(), Types.surface_target(), String.t(), String.t()) ::
          String.t()
  defp maybe_attach_subscription_payload(state, target, message, trigger_like)
       when is_map(state) and is_binary(message) and is_binary(trigger_like) do
    message_text = String.trim(message)

    if message_text == "" or String.contains?(message_text, " ") do
      message
    else
      now = simulator_now_for_target(state, target)
      # `subscription_event_kind/1` turns e.g. `PebbleEvents.onHourChange` into `on_hour_change`.
      # Match after removing punctuation so "on_hour_change", "onHourChange", and "onhourchange"
      # all line up the same way.
      t =
        trigger_like
        |> to_string()
        |> String.downcase()
        |> String.replace(~r/[^a-z0-9]/, "")

      cond do
        Ide.Debugger.CompanionSubscriptionTrigger.companion_trigger?(trigger_like) ->
          message

        frame_subscription_trigger?(trigger_like) and
            subscription_message_arity(state, target, message_text) == 1 ->
          "#{message_text} #{Jason.encode!(subscription_frame_payload(state, target))}"

        (String.contains?(t, "secondchange") or String.contains?(t, "onsecond")) and
            subscription_message_arity(state, target, message_text) == 1 ->
          "#{message_text} #{now.second}"

        # Minute before hour so a hypothetical name containing both substrings is unambiguous.
        String.contains?(t, "minutechange") or String.contains?(t, "onminute") ->
          "#{message_text} #{now.minute}"

        String.contains?(t, "hourchange") or String.contains?(t, "onhour") ->
          "#{message_text} #{now.hour}"

        String.contains?(t, "daychange") or String.contains?(t, "onday") ->
          "#{message_text} #{now.day}"

        String.contains?(t, "monthchange") or String.contains?(t, "onmonth") ->
          "#{message_text} #{now.month}"

        String.contains?(t, "yearchange") or String.contains?(t, "onyear") ->
          "#{message_text} #{now.year}"

        String.contains?(t, "batterychange") or String.contains?(t, "onbattery") ->
          "#{message_text} #{subscription_battery_level(state, target)}"

        String.contains?(t, "connectionchange") or String.contains?(t, "onconnection") ->
          "#{message_text} #{subscription_connection_status(state, target)}"

        String.contains?(t, "compasschange") or String.contains?(t, "oncompass") ->
          compass_payload = subscription_compass_heading(state, target)

          if subscription_message_arity(state, target, message_text) == 1 do
            "#{message_text} #{Jason.encode!(compass_payload)}"
          else
            message
          end

        String.contains?(t, "appfocuschange") or String.contains?(t, "onappfocus") ->
          focus_state = subscription_app_focus_state(state, target)

          if subscription_message_arity(state, target, message_text) == 1 do
            "#{message_text} #{focus_state}"
          else
            message
          end

        String.contains?(t, "unobstructedwillchange") or String.contains?(t, "onunobstructedwill") ->
          rect = subscription_unobstructed_rect(state, target)

          if subscription_message_arity(state, target, message_text) == 1 do
            "#{message_text} #{Jason.encode!(rect)}"
          else
            message
          end

        String.contains?(t, "unobstructedchanging") or String.contains?(t, "onunobstructedchang") ->
          progress = subscription_unobstructed_progress(state)

          if subscription_message_arity(state, target, message_text) == 1 do
            "#{message_text} #{progress}"
          else
            message
          end

        String.contains?(t, "dictationstatus") or String.contains?(t, "ondictationstatus") ->
          status = subscription_dictation_status(state, target)

          if subscription_message_arity(state, target, message_text) == 1 do
            "#{message_text} #{status}"
          else
            message
          end

        String.contains?(t, "dictationresult") or String.contains?(t, "ondictationresult") ->
          result_payload = subscription_dictation_result_payload(state, target)

          if subscription_message_arity(state, target, message_text) == 1 do
            "#{message_text} #{Jason.encode!(result_payload)}"
          else
            message
          end

        true ->
          message
      end
    end
  end

  defp maybe_attach_subscription_payload(_state, _target, message, _trigger_like)
       when is_binary(message),
       do: message

  @spec subscription_compass_heading(runtime_state(), Types.surface_target()) :: map()
  defp subscription_compass_heading(state, _target) when is_map(state) do
    settings = simulator_settings_from_state(state)

    %{
      "degrees" => Map.get(settings, "compass_heading_deg", 0) / 1.0,
      "isValid" => Map.get(settings, "compass_valid", true) == true
    }
  end

  @spec subscription_app_focus_state(runtime_state(), Types.surface_target()) :: String.t()
  defp subscription_app_focus_state(state, _target) when is_map(state) do
    settings = simulator_settings_from_state(state)

    if Map.get(settings, "app_in_focus", true) == true, do: "InFocus", else: "OutOfFocus"
  end

  @spec subscription_unobstructed_rect(runtime_state(), Types.surface_target()) :: map()
  defp subscription_unobstructed_rect(state, _target) when is_map(state) do
    settings = simulator_settings_from_state(state)

    launch_context =
      get_in(state, [:watch, :model, "launch_context"]) ||
        get_in(state, [:watch, :model, "runtime_model", "launch_context"]) ||
        %{}

    width = get_in(launch_context, ["screen", "width"]) || 144
    height = get_in(launch_context, ["screen", "height"]) || 168
    peek? = Map.get(settings, "timeline_peek", false) == true
    inset = min(32, div(height, 4))

    if peek? do
      %{"x" => 0, "y" => inset, "w" => width, "h" => height - inset}
    else
      %{"x" => 0, "y" => 0, "w" => width, "h" => height}
    end
  end

  @spec subscription_unobstructed_progress(runtime_state()) :: integer()
  defp subscription_unobstructed_progress(_state), do: 255

  @spec maybe_inject_unobstructed_area_triggers(runtime_state(), map(), map()) :: runtime_state()
  defp maybe_inject_unobstructed_area_triggers(state, previous_settings, new_settings)
       when is_map(state) and is_map(previous_settings) and is_map(new_settings) do
    previous_peek = Map.get(previous_settings, "timeline_peek")
    next_peek = Map.get(new_settings, "timeline_peek")

    if previous_peek != next_peek do
      Enum.reduce(
        ["on_unobstructed_will_change", "on_unobstructed_changing", "on_unobstructed_did_change"],
        state,
        fn trigger, acc ->
          maybe_inject_watch_subscription_trigger(acc, trigger)
        end
      )
    else
      state
    end
  end

  defp maybe_inject_unobstructed_area_triggers(state, _previous_settings, _new_settings),
    do: state

  @spec maybe_inject_watch_weather_from_simulator_settings(runtime_state(), map(), map()) ::
          runtime_state()
  defp maybe_inject_watch_weather_from_simulator_settings(state, previous_settings, new_settings)
       when is_map(state) and is_map(previous_settings) and is_map(new_settings) do
    previous_weather = Map.get(previous_settings, "weather") || %{}
    new_weather = Map.get(new_settings, "weather") || %{}

    if new_weather == %{} or new_weather == previous_weather do
      state
    else
      row =
        state
        |> trigger_candidates(:watch)
        |> Enum.find(fn candidate ->
          trigger = Map.get(candidate, :trigger) || Map.get(candidate, "trigger")
          trigger in ["phone_to_watch", "on_phone_to_watch"]
        end)

      if is_map(row) and subscription_model_active?(state, :watch, row) do
        state
        |> maybe_apply_watch_weather_step(new_weather, "ProvideTemperature")
        |> maybe_apply_watch_weather_step(new_weather, "ProvideCondition")
      else
        state
      end
    end
  end

  defp maybe_inject_watch_weather_from_simulator_settings(state, _previous_settings, _new_settings),
    do: state

  defp maybe_apply_watch_weather_step(state, weather, message_name)
       when is_map(state) and is_map(weather) and is_binary(message_name) do
    case watch_weather_from_phone_message_value(message_name, weather) do
      %{} = message_value ->
        message = watch_weather_step_message(message_name, weather)

        apply_step_once(
          state,
          :watch,
          message,
          message_value,
          "simulator_settings",
          "simulator_settings"
        )

      _ ->
        state
    end
  end

  @spec elm_message_constructor_map?(map()) :: boolean()
  defp elm_message_constructor_map?(map) when is_map(map) do
    keys = map |> Map.keys() |> Enum.map(&to_string/1) |> Enum.sort()
    keys == ["args", "ctor"] or keys == ["$args", "$ctor"]
  end

  @companion_weather_phone_messages ~w(ProvideTemperature ProvideCondition)

  @spec watch_protocol_supports_weather_delivery?(runtime_state()) :: boolean()
  defp watch_protocol_supports_weather_delivery?(state) when is_map(state) do
    case project_protocol_schema(state) do
      {:ok, schema} ->
        schema
        |> Map.get(:phone_to_watch, [])
        |> List.wrap()
        |> Enum.any?(fn
          %{name: name} when is_binary(name) -> name in @companion_weather_phone_messages
          %{"name" => name} when is_binary(name) -> name in @companion_weather_phone_messages
          _ -> false
        end)

      _ ->
        false
    end
  end

  @spec deliver_simulator_weather_to_watch(runtime_state()) :: runtime_state()
  defp deliver_simulator_weather_to_watch(state) when is_map(state) do
    if watch_protocol_supports_weather_delivery?(state) do
      deliver_simulator_weather_to_watch_when_declared(state)
    else
      state
    end
  end

  @spec deliver_simulator_weather_to_watch_when_declared(runtime_state()) :: runtime_state()
  defp deliver_simulator_weather_to_watch_when_declared(state) when is_map(state) do
    settings = simulator_settings_from_state(state)
    weather = settings["weather"] || %{}

    if map_size(weather) == 0 do
      state
    else
      row =
        state
        |> trigger_candidates(:watch)
        |> Enum.find(fn candidate ->
          trigger = Map.get(candidate, :trigger) || Map.get(candidate, "trigger")
          trigger in ["phone_to_watch", "on_phone_to_watch"]
        end)

      if is_map(row) and subscription_model_active?(state, :watch, row) do
        state
        |> maybe_apply_watch_weather_step(weather, "ProvideTemperature")
        |> maybe_apply_watch_weather_step(weather, "ProvideCondition")
      else
        state
      end
    end
  end

  @spec deliver_simulator_position_to_watch(runtime_state()) :: runtime_state()
  defp deliver_simulator_position_to_watch(state) when is_map(state) do
    settings = simulator_settings_from_state(state)

    row =
      state
      |> trigger_candidates(:watch)
      |> Enum.find(fn candidate ->
        trigger = Map.get(candidate, :trigger) || Map.get(candidate, "trigger")
        trigger in ["phone_to_watch", "on_phone_to_watch"]
      end)

    if is_map(row) and subscription_model_active?(state, :watch, row) do
      message_value = watch_geolocation_from_phone_message_value(settings)
      {lat_e6, lon_e6, accuracy_m} = geolocation_wire_triplet(settings)

      apply_step_once(
        state,
        :watch,
        "FromPhone (ProvidePosition #{lat_e6} #{lon_e6} #{accuracy_m})",
        message_value,
        "simulator_settings",
        "simulator_settings"
      )
    else
      state
    end
  end

  @spec geolocation_wire_triplet(map()) :: {integer(), integer(), integer()}
  defp geolocation_wire_triplet(settings) when is_map(settings) do
    {lat, lon, accuracy} = SimulatorSettings.geolocation(settings)

    {
      protocol_position_microdegrees(lat),
      protocol_position_microdegrees(lon),
      round_float(accuracy) || 0
    }
  end

  @spec watch_geolocation_from_phone_message_value(map()) :: map() | nil
  defp watch_geolocation_from_phone_message_value(settings) when is_map(settings) do
    {lat_e6, lon_e6, accuracy_m} = geolocation_wire_triplet(settings)

    %{
      "ctor" => "FromPhone",
      "args" => [
        %{
          "ctor" => "ProvidePosition",
          "args" => [lat_e6, lon_e6, accuracy_m]
        }
      ]
    }
  end

  @spec maybe_inject_watch_subscription_trigger(runtime_state(), String.t()) :: runtime_state()
  defp maybe_inject_watch_subscription_trigger(state, trigger) when is_map(state) and is_binary(trigger) do
    row =
      state
      |> trigger_candidates(:watch)
      |> Enum.find(fn candidate ->
        candidate_trigger = Map.get(candidate, :trigger) || Map.get(candidate, "trigger")
        candidate_trigger == trigger
      end)

    if is_map(row) and subscription_model_active?(state, :watch, row) do
      message = Map.get(row, :message) || Map.get(row, "message")
      resolved_message = trigger_message_for_surface(state, :watch, trigger, message)

      apply_step_once(state, :watch, resolved_message, nil, "simulator_settings", "simulator_settings")
    else
      state
    end
  end

  defp maybe_inject_watch_subscription_trigger(state, _trigger), do: state

  @spec subscription_dictation_status(runtime_state(), Types.surface_target()) :: String.t()
  defp subscription_dictation_status(state, _target) when is_map(state) do
    settings = simulator_settings_from_state(state)

    case blank_string?(Map.get(settings, "dictation_error")) do
      true -> "Finished"
      false -> "Recognizing"
    end
  end

  @spec subscription_dictation_result_payload(runtime_state(), Types.surface_target()) :: map()
  defp subscription_dictation_result_payload(state, _target) when is_map(state) do
    settings = simulator_settings_from_state(state)

    case blank_string?(Map.get(settings, "dictation_error")) do
      true ->
        %{"ctor" => "Ok", "args" => [Map.get(settings, "dictation_transcript", "")]}

      false ->
        %{
          "ctor" => "Err",
          "args" => [%{"ctor" => "Failed", "args" => [Map.get(settings, "dictation_error", "")]}]
        }
    end
  end

  @spec blank_string?(term()) :: boolean()
  defp blank_string?(value) when is_binary(value), do: String.trim(value) == ""
  defp blank_string?(_value), do: true

  @spec subscription_message_arity(runtime_state(), Types.surface_target(), String.t()) :: non_neg_integer()
  defp subscription_message_arity(state, target, message)
       when is_map(state) and is_binary(message) do
    case introspect_for(state, target) do
      %{"msg_constructor_arities" => arities} when is_map(arities) ->
        arities
        |> Map.get(message, 0)
        |> normalize_integer(0)

      %{} = ei ->
        case Map.get(ei, "msg_constructor_arities") do
          arities when is_map(arities) ->
            arities
            |> Map.get(message, 0)
            |> normalize_integer(0)

          _ ->
            0
        end

      _ ->
        0
    end
  end

  @spec frame_subscription_trigger?(String.t()) :: boolean()
  defp frame_subscription_trigger?(trigger_like) when is_binary(trigger_like) do
    normalized =
      trigger_like
      |> String.downcase()
      |> String.replace(~r/[^a-z0-9]+/, "")

    String.contains?(normalized, "frame") or String.contains?(normalized, "onframe")
  end

  @spec subscription_frame_payload(runtime_state(), Types.surface_target()) :: map()
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

  @spec subscription_battery_level(runtime_state(), Types.surface_target()) :: integer()
  defp subscription_battery_level(state, target) when is_map(state) do
    state
    |> subscription_runtime_value(target, "batteryLevel")
    |> unwrap_elm_maybe()
    |> normalize_integer(simulator_settings_from_state(state)["battery_percent"])
    |> min(100)
    |> max(0)
  end

  @spec subscription_connection_status(runtime_state(), Types.surface_target()) :: String.t()
  defp subscription_connection_status(state, target) when is_map(state) do
    state
    |> subscription_runtime_value(target, "connected")
    |> unwrap_elm_maybe()
    |> normalize_boolean(simulator_settings_from_state(state)["connected"])
    |> then(fn
      true -> "True"
      false -> "False"
    end)
  end

  @spec simulator_bool_setting(map(), atom() | String.t(), boolean()) :: boolean()
  defp simulator_bool_setting(settings, key, default) when is_map(settings) do
    case Map.get(settings, key) || Map.get(settings, to_string(key)) do
      value when is_boolean(value) -> value
      _ -> default
    end
  end

  @spec simulator_settings_from_state(runtime_state()) :: map()
  defp simulator_settings_from_state(state) when is_map(state) do
    state
    |> Map.get(:simulator_settings)
    |> normalize_simulator_settings()
  end

  defp simulator_settings_from_state(_state), do: default_simulator_settings()

  @spec subscription_runtime_value(runtime_state(), Types.surface_target(), String.t()) ::
          Types.protocol_wire_arg() | nil
  defp subscription_runtime_value(state, target, key) when is_map(state) and is_binary(key) do
    with surface when surface in [:watch, :companion, :phone] <- target,
         runtime_model when is_map(runtime_model) <-
           get_in(state, [surface, :model, "runtime_model"]) do
      Map.get(runtime_model, key)
    else
      _ -> nil
    end
  end

  @spec unwrap_elm_maybe(Types.subscription_payload()) :: Types.subscription_payload()
  defp unwrap_elm_maybe(%{"ctor" => "Just", "args" => [value | _]}), do: value
  defp unwrap_elm_maybe(%{ctor: "Just", args: [value | _]}), do: value
  defp unwrap_elm_maybe(value), do: value

  @spec normalize_integer(Types.wire_input(), integer()) :: integer()
  defp normalize_integer(value, _default) when is_integer(value), do: value

  defp normalize_integer(value, default) when is_binary(value) and is_integer(default) do
    case Integer.parse(value) do
      {parsed, ""} -> parsed
      _ -> default
    end
  end

  defp normalize_integer(_value, default) when is_integer(default), do: default

  @spec normalize_boolean(Types.wire_input(), boolean()) :: boolean()
  defp normalize_boolean(values, default) when is_list(values),
    do: Enum.any?(values, &normalize_boolean(&1, default))

  defp normalize_boolean(value, _default) when is_boolean(value), do: value
  defp normalize_boolean("True", _default), do: true
  defp normalize_boolean("False", _default), do: false
  defp normalize_boolean("true", _default), do: true
  defp normalize_boolean("false", _default), do: false
  defp normalize_boolean(_value, default) when is_boolean(default), do: default

  @doc """
  Normalizes simulator settings form or persisted values to the canonical debugger shape.
  """
  @spec normalize_simulator_settings(map()) :: Types.simulator_settings()
  def normalize_simulator_settings(settings) when is_map(settings) do
    defaults = default_simulator_settings()

    %{
      "battery_percent" =>
        settings
        |> map_value("battery_percent")
        |> normalize_integer(defaults["battery_percent"])
        |> min(100)
        |> max(0),
      "charging" => normalize_boolean(map_value(settings, "charging"), defaults["charging"]),
      "connected" => normalize_boolean(map_value(settings, "connected"), defaults["connected"]),
      "clock_24h" => normalize_boolean(map_value(settings, "clock_24h"), defaults["clock_24h"]),
      "use_simulated_time" =>
        normalize_boolean(
          map_value(settings, "use_simulated_time"),
          defaults["use_simulated_time"]
        ),
      "simulated_time" =>
        normalize_optional_string(
          map_value(settings, "simulated_time"),
          defaults["simulated_time"]
        ),
      "simulated_date" =>
        normalize_optional_string(
          map_value(settings, "simulated_date"),
          defaults["simulated_date"]
        ),
      "timezone_id" =>
        normalize_string(map_value(settings, "timezone_id"), defaults["timezone_id"]),
      "timezone_offset_min" =>
        settings
        |> map_value("timezone_offset_min")
        |> normalize_integer(defaults["timezone_offset_min"]),
      "locale" => normalize_string(map_value(settings, "locale"), defaults["locale"]),
      "language" => normalize_string(map_value(settings, "language"), defaults["language"]),
      "region" => normalize_string(map_value(settings, "region"), defaults["region"]),
      "network_online" =>
        normalize_boolean(map_value(settings, "network_online"), defaults["network_online"]),
      "notifications_enabled" =>
        normalize_boolean(
          map_value(settings, "notifications_enabled"),
          defaults["notifications_enabled"]
        ),
      "quiet_hours" =>
        normalize_boolean(map_value(settings, "quiet_hours"), defaults["quiet_hours"]),
      "weather" => normalize_weather_settings(map_value(settings, "weather"), defaults["weather"]),
      "calendar_events" =>
        normalize_json_list(map_value(settings, "calendar_events"), defaults["calendar_events"]),
      "storage_values" =>
        normalize_json_map(map_value(settings, "storage_values"), defaults["storage_values"]),
      "preferences" =>
        normalize_json_map(map_value(settings, "preferences"), defaults["preferences"]),
      "environment" =>
        normalize_json_map(map_value(settings, "environment"), defaults["environment"]),
      "latitude" =>
        normalize_float(map_value(settings, "latitude"), defaults["latitude"], -90.0, 90.0),
      "longitude" =>
        normalize_float(map_value(settings, "longitude"), defaults["longitude"], -180.0, 180.0),
      "accuracy" =>
        normalize_float(map_value(settings, "accuracy"), defaults["accuracy"], 0.0, 100_000.0),
      "timeline_peek" =>
        normalize_boolean(map_value(settings, "timeline_peek"), defaults["timeline_peek"]),
      "compass_heading_deg" =>
        settings
        |> map_value("compass_heading_deg")
        |> normalize_integer(defaults["compass_heading_deg"])
        |> min(360)
        |> max(0),
      "compass_valid" =>
        normalize_boolean(map_value(settings, "compass_valid"), defaults["compass_valid"]),
      "app_in_focus" =>
        normalize_boolean(map_value(settings, "app_in_focus"), defaults["app_in_focus"]),
      "health_steps" =>
        settings
        |> map_value("health_steps")
        |> normalize_integer(defaults["health_steps"])
        |> max(0),
      "health_steps_today" =>
        settings
        |> map_value("health_steps_today")
        |> normalize_integer(defaults["health_steps_today"])
        |> max(0),
      "dictation_transcript" =>
        normalize_string(
          map_value(settings, "dictation_transcript"),
          defaults["dictation_transcript"]
        ),
      "dictation_error" =>
        normalize_string(map_value(settings, "dictation_error"), defaults["dictation_error"]),
      "vibe_pattern_ms" =>
        normalize_json_list(map_value(settings, "vibe_pattern_ms"), defaults["vibe_pattern_ms"])
    }
  end

  def normalize_simulator_settings(_settings), do: default_simulator_settings()

  defp normalize_string(value, _default) when is_binary(value) and value != "", do: value
  defp normalize_string(_value, default) when is_binary(default), do: default

  defp normalize_optional_string(value, _default) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp normalize_optional_string(_value, default), do: default

  defp normalize_json_map(value, _default) when is_map(value), do: value
  defp normalize_json_map(_value, default) when is_map(default), do: default

  @spec normalize_weather_settings(map() | nil, map()) :: map()
  defp normalize_weather_settings(value, default) when is_map(value) and is_map(default) do
    weather =
      value
      |> Map.take(["temperatureC", "condition", "humidityPercent", "pressureHpa", "windKph"])
      |> Enum.reject(fn {_key, setting_value} -> is_nil(setting_value) or setting_value == "" end)
      |> Map.new()

    weather =
      case weather_temperature_celsius(weather) do
        nil -> Map.delete(weather, "temperatureC")
        temp -> Map.put(weather, "temperatureC", temp)
      end

    if map_size(weather) == 0, do: default, else: weather
  end

  defp normalize_weather_settings(_value, default) when is_map(default), do: default
  defp normalize_weather_settings(_value, _default), do: %{}

  @spec weather_temperature_celsius(map()) :: integer() | nil
  defp weather_temperature_celsius(weather) when is_map(weather) do
    weather
    |> Map.get("temperatureC", Map.get(weather, :temperatureC))
    |> normalize_temperature_scalar()
  end

  defp weather_temperature_celsius(_weather), do: nil

  @spec watch_weather_from_phone_message_value(String.t(), map()) :: map() | nil
  defp watch_weather_from_phone_message_value("ProvideTemperature", weather) when is_map(weather) do
    case weather_temperature_celsius(weather) do
      nil ->
        nil

      temp ->
        %{
          "ctor" => "FromPhone",
          "args" => [
            %{
              "ctor" => "ProvideTemperature",
              "args" => [%{"ctor" => "Celsius", "args" => [temp]}]
            }
          ]
        }
    end
  end

  defp watch_weather_from_phone_message_value("ProvideCondition", weather) when is_map(weather) do
    condition = weather_condition_term_from_settings(%{"weather" => weather})

    %{
      "ctor" => "FromPhone",
      "args" => [
        %{
          "ctor" => "ProvideCondition",
          "args" => [condition]
        }
      ]
    }
  end

  defp watch_weather_from_phone_message_value(_message_name, _weather), do: nil

  @spec watch_weather_step_message(String.t(), map()) :: String.t()
  defp watch_weather_step_message("ProvideTemperature", weather) when is_map(weather) do
    case weather_temperature_celsius(weather) do
      nil -> "FromPhone (ProvideTemperature ...)"
      temp -> "FromPhone (ProvideTemperature (Celsius #{temp}))"
    end
  end

  defp watch_weather_step_message("ProvideCondition", weather) when is_map(weather) do
    condition = weather_condition_term_from_settings(%{"weather" => weather})
    ctor = Map.get(condition, "ctor") || "UnknownWeather"
    "FromPhone (ProvideCondition #{ctor})"
  end

  defp watch_weather_step_message(message_name, _weather), do: "FromPhone (#{message_name} ...)"

  defp normalize_json_list(value, _default) when is_list(value), do: value
  defp normalize_json_list(_value, default) when is_list(default), do: default

  @spec simulator_settings_from_model(map()) :: map()
  defp simulator_settings_from_model(model) when is_map(model) do
    model
    |> map_value("simulator_settings")
    |> normalize_simulator_settings()
  end

  defp simulator_settings_from_model(_model), do: default_simulator_settings()

  @spec simulator_now_for_target(map(), :watch | :companion | :phone) :: NaiveDateTime.t()
  defp simulator_now_for_target(state, target)
       when is_map(state) and target in [:watch, :companion, :phone] do
    state
    |> get_in([target, :model])
    |> simulator_now_from_model()
  end

  @spec simulator_now_from_model(map()) :: NaiveDateTime.t()
  defp simulator_now_from_model(model) do
    model
    |> simulator_settings_from_model()
    |> simulator_now_from_settings()
  end

  @spec simulator_now_from_settings(map()) :: NaiveDateTime.t()
  defp simulator_now_from_settings(settings) when is_map(settings) do
    fallback = NaiveDateTime.local_now()

    if settings["use_simulated_time"] == true do
      date = parse_simulated_date(settings["simulated_date"], NaiveDateTime.to_date(fallback))
      time = parse_simulated_time(settings["simulated_time"], NaiveDateTime.to_time(fallback))

      NaiveDateTime.new!(date, time)
    else
      fallback
    end
  end

  @spec parse_simulated_date(Types.wire_input(), Date.t()) :: Date.t()
  defp parse_simulated_date(value, fallback) when is_binary(value) do
    case Date.from_iso8601(String.trim(value)) do
      {:ok, date} -> date
      {:error, _reason} -> fallback
    end
  end

  defp parse_simulated_date(_value, fallback), do: fallback

  @spec parse_simulated_time(Types.wire_input(), Time.t()) :: Time.t()
  defp parse_simulated_time(value, fallback) when is_binary(value) do
    text = String.trim(value)
    normalized = if Regex.match?(~r/^\d{1,2}:\d{2}$/, text), do: text <> ":00", else: text

    case Time.from_iso8601(normalized) do
      {:ok, time} -> Time.truncate(time, :second)
      {:error, _reason} -> fallback
    end
  end

  defp parse_simulated_time(_value, fallback), do: fallback

  @spec normalize_float(Types.wire_input(), float(), float(), float()) :: float()
  defp normalize_float(value, _default, min_value, max_value) when is_float(value),
    do: value |> min(max_value) |> max(min_value)

  defp normalize_float(value, _default, min_value, max_value) when is_integer(value),
    do: (value * 1.0) |> min(max_value) |> max(min_value)

  defp normalize_float(value, default, min_value, max_value) when is_binary(value) do
    case Float.parse(String.trim(value)) do
      {parsed, ""} -> parsed |> min(max_value) |> max(min_value)
      _ -> default
    end
  end

  defp normalize_float(_value, default, _min_value, _max_value), do: default

  @spec best_message_for_trigger([String.t()], String.t()) :: String.t()
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

  @spec first_matching_message([String.t()], [String.t()]) :: String.t() | nil
  defp first_matching_message(known_messages, tokens)
       when is_list(known_messages) and is_list(tokens) do
    Enum.find(known_messages, fn message ->
      down = String.downcase(message)
      Enum.all?(tokens, &String.contains?(down, &1))
    end)
  end

  defp first_matching_message(_known_messages, _tokens), do: nil

  @spec fallback_message_for_trigger([String.t()], String.t()) :: String.t() | nil
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

  @spec trigger_tokens(String.t()) :: [String.t()]
  defp trigger_tokens(trigger_down) when is_binary(trigger_down) do
    trigger_down
    |> String.split(~r/[^a-z0-9]+/, trim: true)
    |> Enum.reject(&(&1 == "button" or &1 == "press" or &1 == "short" or &1 == "long"))
  end

  @spec buttonish_trigger?(String.t()) :: boolean()
  defp buttonish_trigger?(trigger_down) when is_binary(trigger_down) do
    contains_any?(trigger_down, ["button", "up", "down", "select", "back", "press", "tap"])
  end

  @spec first_non_tick_message([String.t()]) :: String.t() | nil
  defp first_non_tick_message(known_messages) when is_list(known_messages) do
    Enum.find(known_messages, fn message ->
      is_binary(message) and not tickish_message?(message)
    end)
  end

  @spec default_message_for_trigger(String.t()) :: String.t()
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

  @spec normalize_trigger_id(Types.wire_input()) :: String.t()
  defp normalize_trigger_id(trigger) when is_binary(trigger) do
    trigger
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9]+/, "_")
    |> String.trim("_")
  end

  defp normalize_trigger_id(_), do: "trigger"

  @spec normalize_trigger_label(Types.wire_input()) :: String.t()
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

  @doc false
  @spec subscription_trigger_display(map() | nil, String.t() | nil) :: String.t()
  def subscription_trigger_display(%{} = op, trigger) do
    case Map.get(op, "target") do
      target when is_binary(target) and target != "" ->
        target

      _ ->
        case subscription_label_name(Map.get(op, "label")) do
          name when is_binary(name) and name != "" -> name
          _ -> camel_case_trigger_id(trigger)
        end
    end
  end

  def subscription_trigger_display(_op, trigger), do: camel_case_trigger_id(trigger)

  @doc false
  @spec subscription_trigger_display_for(runtime_state() | map(), String.t(), String.t()) :: String.t()
  def subscription_trigger_display_for(state, trigger, target_name)
      when is_map(state) and is_binary(trigger) and is_binary(target_name) do
    target_atom = normalize_step_target(target_name)
    ei = introspect_for(state, target_atom)

    case introspect_cmd_calls(ei, "subscription_calls") do
      calls when is_list(calls) ->
        Enum.find_value(calls, fn op ->
          if subscription_trigger_for_call(op) |> to_string() == trigger do
            subscription_trigger_display(op, trigger)
          end
        end) || camel_case_trigger_id(trigger)
    end
  end

  def subscription_trigger_display_for(_state, trigger, _target_name) when is_binary(trigger),
    do: camel_case_trigger_id(trigger)

  def subscription_trigger_display_for(_state, _trigger, _target_name), do: "Trigger"

  @spec subscription_label_name(String.t() | nil) :: String.t() | nil
  defp subscription_label_name(label) when is_binary(label) do
    case String.split(label, "(", parts: 2) do
      [name, _] ->
        name |> String.trim() |> then(fn value -> if value == "", do: nil, else: value end)

      _ ->
        nil
    end
  end

  defp subscription_label_name(_label), do: nil

  @spec camel_case_trigger_id(String.t() | nil) :: String.t()
  defp camel_case_trigger_id(trigger) when is_binary(trigger) do
    trigger = String.trim(trigger)

    cond do
      trigger == "" ->
        "Trigger"

      String.contains?(trigger, ".") ->
        trigger

      not String.contains?(trigger, "_") ->
        trigger

      true ->
        trigger
        |> String.split("_", trim: true)
        |> case do
          [] ->
            trigger

          [single] ->
            single

          [first | rest] ->
            first <> Enum.map_join(rest, "", &Macro.camelize/1)
        end
    end
  end

  defp camel_case_trigger_id(_trigger), do: "Trigger"

  @spec fallback_trigger_seed_rows(String.t()) :: [map()]
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

  @spec tick_message_for_surface(map(), Types.surface_target() | atom()) :: String.t()
  defp tick_message_for_surface(state, target) when is_map(state) do
    ei = introspect_for(state, target)
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

  @spec pick_subscription_message([String.t()], [String.t()], String.t()) ::
          {String.t(), String.t() | nil}
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

  @spec subscription_match_priority(String.t(), String.t()) :: 0 | 1 | 2 | 3 | 4
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

  @spec tickish_message?(String.t()) :: boolean()
  defp tickish_message?(message) when is_binary(message) do
    contains_any?(String.downcase(message), ["tick", "time", "clock", "second", "minute", "hour"])
  end

  @spec subscription_op_matches_message?(String.t(), String.t(), [String.t()]) :: boolean()
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

  @spec normalized_event_tokens(String.t()) :: [String.t()]
  defp normalized_event_tokens(text) when is_binary(text) do
    text
    |> String.replace(~r/([a-z])([A-Z])/, "\\1 \\2")
    |> String.replace(~r/[^A-Za-z0-9]+/, " ")
    |> String.downcase()
    |> String.split(" ", trim: true)
  end

  defp normalized_event_tokens(_), do: []

  @spec parse_tick_interval_ms(Types.wire_input()) :: pos_integer()
  defp parse_tick_interval_ms(value) when is_integer(value) and value >= 100,
    do: min(value, 60_000)

  defp parse_tick_interval_ms(value) when is_binary(value) do
    case Integer.parse(String.trim(value)) do
      {parsed, ""} when parsed >= 100 -> min(parsed, 60_000)
      _ -> 1_000
    end
  end

  defp parse_tick_interval_ms(_), do: 1_000

  @spec parse_checkbox_bool(Types.wire_input()) :: boolean()
  defp parse_checkbox_bool(value) when value in [true, "true", "on", "1", 1], do: true
  defp parse_checkbox_bool(_value), do: false

  @spec auto_tick_loop(String.t(), pos_integer(), [:watch | :companion | :phone], pos_integer()) :: :ok
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

  @spec auto_fire_loop(String.t(), pos_integer(), [:watch | :companion | :phone], non_neg_integer()) :: :ok
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
        Enum.reduce(targets, state, fn target, acc ->
          now = simulator_now_for_target(acc, target)
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

  @spec auto_fire_subscription_candidates(runtime_state(), :watch | :companion | :phone, NaiveDateTime.t()) ::
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
          auto_fire_subscription_enabled?(state, target, row) and
          subscription_model_active?(state, target, row)
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

      contains_any?(trigger, ["on_second_change", "onsecondchange", "second"]) ->
        Map.get(clock, "second") != now.second

      contains_any?(trigger, ["on_minute_change", "onminutechange", "minute"]) ->
        Map.get(clock, "minute") != now.minute

      contains_any?(trigger, ["on_hour_change", "onhourchange", "hour"]) ->
        Map.get(clock, "hour") != now.hour

      contains_any?(trigger, ["on_day_change", "ondaychange", "day"]) ->
        Map.get(clock, "day") != now.day

      contains_any?(trigger, ["on_month_change", "onmonthchange", "month"]) ->
        Map.get(clock, "month") != now.month

      contains_any?(trigger, ["on_year_change", "onyearchange", "year"]) ->
        Map.get(clock, "year") != now.year

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
        "year" => now.year,
        "month" => now.month,
        "day" => now.day,
        "hour" => now.hour,
        "minute" => now.minute,
        "second" => now.second
      })

    Map.put(state, :auto_fire_clock, clock)
  end

  @spec restart_auto_fire_worker(runtime_state(), String.t(), [:watch | :companion | :phone], [map()]) ::
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

  @spec auto_tick_targets(runtime_state()) :: [:watch | :companion | :phone]
  defp auto_tick_targets(state) when is_map(state) do
    auto_tick = Map.get(state, :auto_tick, %{})

    auto_tick
    |> Map.get(:targets, [])
    |> Enum.map(&normalize_step_target/1)
    |> Enum.filter(&(&1 in [:watch, :companion]))
    |> Enum.uniq()
  end

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

  @spec stop_auto_tick_worker(runtime_state()) :: map()
  defp stop_auto_tick_worker(state) when is_map(state) do
    auto_tick = Map.get(state, :auto_tick, %{})
    worker = Map.get(auto_tick, :worker_pid)

    if is_pid(worker) and Process.alive?(worker) do
      send(worker, :stop)
    end

    Map.put(state, :auto_tick, default_auto_tick())
  end

  @spec resolve_step_message(Types.execution_model(), String.t() | nil) ::
          {String.t(), String.t(), [String.t()], [String.t()], non_neg_integer()}
  defp resolve_step_message(model, requested_message) when is_map(model) do
    ei = RuntimeArtifacts.require_introspect(model)
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

  @spec canonicalize_known_message(String.t(), [String.t()]) :: String.t()
  defp canonicalize_known_message(message, known_messages) when is_binary(message) do
    trimmed = String.trim(message)

    case String.split(trimmed, ~r/\s+/, parts: 2) do
      [constructor, payload] when is_binary(payload) and payload != "" ->
        canonical_constructor = canonicalize_message_constructor(constructor, known_messages)
        "#{canonical_constructor} #{payload}"

      _ ->
        needle = String.downcase(trimmed)

        Enum.find(known_messages, trimmed, fn known ->
          if is_binary(known) do
            known_down = String.downcase(known)

            known_down == needle or
              String.starts_with?(needle, known_down <> " ") or
              String.starts_with?(needle, known_down <> "(")
          else
            false
          end
        end)
    end
  end

  @spec canonicalize_message_constructor(String.t(), [String.t()]) :: String.t()
  defp canonicalize_message_constructor(constructor, known_messages) when is_binary(constructor) do
    ctor_down = String.downcase(constructor)

    Enum.find_value(known_messages, constructor, fn known ->
      if is_binary(known) do
        known_ctor =
          known
          |> String.trim()
          |> String.split(~r/\s+/, parts: 2)
          |> List.first()

        if is_binary(known_ctor) and String.downcase(known_ctor) == ctor_down do
          known_ctor
        end
      end
    end)
  end

  @spec step_runtime_result(StepInput.t(), [String.t()]) :: Types.runtime_step_result()
  defp step_runtime_result(%StepInput{} = step, update_branches)
       when is_binary(step.message) do
    request =
      step
      |> Types.StepExecutionContract.request_from(update_branches: update_branches)
      |> Ide.Debugger.RuntimeExecutor.Request.to_map()

    case runtime_executor_module().execute(request) do
      {:ok, %{model_patch: patch} = result} when is_map(patch) ->
        if is_map(Map.get(patch, "runtime_model")) do
          result
          |> Map.put(
            :view_output,
            normalize_view_output(
              Map.get(result, :view_output) || Map.get(patch, "runtime_view_output")
            )
          )
          |> Map.put(:protocol_events, normalize_protocol_events(Map.get(result, :protocol_events)))
          |> Map.put(:followup_messages, normalize_followup_messages(Map.get(result, :followup_messages)))
          |> Types.StepExecutionContract.step_result_from_executor()
        else
          local_step_runtime_result(step.execution_model, step.view_tree, step.target, step.message, update_branches)
        end

      _ ->
        local_step_runtime_result(step.execution_model, step.view_tree, step.target, step.message, update_branches)
    end
  end

  @spec local_step_runtime_result(
          Types.execution_model(),
          map(),
          Types.surface_target(),
          String.t(),
          [String.t()]
        ) :: Types.runtime_step_result()
  defp local_step_runtime_result(model, view_tree, _target, message, update_branches) do
    runtime_model = Map.get(model, "runtime_model")
    runtime_model = if is_map(runtime_model), do: runtime_model, else: %{}
    updated_runtime_model = mutate_runtime_model(runtime_model, message, update_branches)

    Types.StepExecutionContract.step_result_from_local_fallback(
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
      view_tree
    )
  end

  @spec normalize_protocol_events(list()) :: [map()]
  defp normalize_protocol_events(value) when is_list(value), do: value
  defp normalize_protocol_events(_), do: []

  @spec normalize_followup_messages(list()) :: [String.t()]
  defp normalize_followup_messages(value) when is_list(value), do: value
  defp normalize_followup_messages(_), do: []

  @spec normalize_view_output(list()) :: [map()]
  defp normalize_view_output(value) when is_list(value), do: value
  defp normalize_view_output(_), do: []

  @spec put_runtime_view_output(map(), list()) :: map()
  defp put_runtime_view_output(model, view_output) when is_map(model) do
    case normalize_view_output(view_output) do
      [] -> model
      rows -> Map.put(model, "runtime_view_output", rows)
    end
  end

  @spec preferred_runtime_view_output(list(), list()) :: [map()]
  defp preferred_runtime_view_output(primary, fallback) do
    choose_runtime_view_output(primary, fallback)
  end

  @spec choose_runtime_view_output(list(), list()) :: [map()]
  defp choose_runtime_view_output(primary, supplemental) do
    primary_rows = normalize_view_output(primary)
    supplemental_rows = normalize_view_output(supplemental)

    primary_vector_ids = vector_at_ids(primary_rows)
    supplemental_vector_ids = vector_at_ids(supplemental_rows)

    prefer_supplemental_vectors? =
      supplemental_vector_ids != [] and
        (primary_vector_ids == [] or primary_vector_ids != supplemental_vector_ids)

    cond do
      supplemental_rows == [] ->
        primary_rows

      primary_rows == [] ->
        supplemental_rows

      prefer_supplemental_vectors? ->
        supplemental_rows

      resolved_vector_rows?(supplemental_rows) and not resolved_vector_rows?(primary_rows) ->
        supplemental_rows

      vector_rows?(supplemental_rows) and not vector_rows?(primary_rows) ->
        supplemental_rows

      length(supplemental_rows) > length(primary_rows) ->
        supplemental_rows

      true ->
        primary_rows
    end
  end

  defp vector_rows?(rows) when is_list(rows),
    do: Enum.any?(rows, &(is_map(&1) and Map.get(&1, "kind") == "vector_at"))

  defp vector_at_ids(rows) when is_list(rows) do
    rows
    |> Enum.flat_map(fn
      %{"kind" => "vector_at", "vector_id" => id} when is_integer(id) -> [id]
      %{kind: "vector_at", vector_id: id} when is_integer(id) -> [id]
      _ -> []
    end)
  end

  defp resolved_vector_rows?(rows) when is_list(rows) do
    Enum.any?(rows, fn row ->
      is_map(row) and Map.get(row, "kind") == "vector_at" and is_integer(Map.get(row, "vector_id"))
    end)
  end

  @spec supplement_parser_runtime_view_output(Types.execution_model(), map(), map()) :: [map()]
  defp supplement_parser_runtime_view_output(execution_model, view_tree, runtime_model)
       when is_map(execution_model) and is_map(view_tree) and is_map(runtime_model) do
    view_tree = introspect_parser_view_tree(execution_model, view_tree)

    if map_size(view_tree) == 0 do
      []
    else
      eval_context =
        execution_model
        |> RuntimeArtifacts.core_ir_eval_context()
        |> then(fn base ->
          case RuntimeArtifacts.introspect(execution_model) do
            %{} = ei -> Map.put(base, :elm_introspect, ei)
            _ -> base
          end
        end)

      preview_model =
        runtime_model
        |> Map.merge(screen_dimensions_for_view_preview(execution_model))

      ElmExecutor.Runtime.SemanticExecutor.derive_view_output_preview(
        view_tree,
        preview_model,
        eval_context
      )
    end
  end

  @spec introspect_parser_view_tree(Types.execution_model(), map()) :: map()
  defp introspect_parser_view_tree(execution_model, view_tree) when is_map(execution_model) do
    case introspect_view_tree(RuntimeArtifacts.introspect(execution_model)) do
      %{} = tree ->
        tree

      _ ->
        case view_tree do
          %{"type" => type} = tree when is_binary(type) and type not in ["root", "unknown", "previewUnavailable"] ->
            tree

          _ ->
            %{}
        end
    end
  end

  defp introspect_view_tree(%{} = introspect), do: Map.get(introspect, "view_tree") || %{}
  defp introspect_view_tree(_), do: %{}

  @spec screen_dimensions_for_view_preview(map()) :: map()
  defp screen_dimensions_for_view_preview(execution_model) when is_map(execution_model) do
    %{
      "screenW" =>
        Map.get(execution_model, "screen_width") || Map.get(execution_model, "screenW"),
      "screenH" =>
        Map.get(execution_model, "screen_height") || Map.get(execution_model, "screenH")
    }
    |> Enum.reject(fn {_key, value} -> not is_integer(value) end)
    |> Map.new()
  end

  @spec render_view_after_update(map() | nil, map() | nil, Types.surface_target(), String.t(), String.t(), map()) :: map()
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
    ei = RuntimeArtifacts.require_introspect(model)

    base =
      cond do
        is_map(output_view_tree) ->
          output_view_tree

        concrete_runtime_view_tree?(runtime_view_tree, ei) ->
          runtime_view_tree

        parser_expression_view_tree?(runtime_view_tree, ei) ->
          preview_unavailable_view_tree(target, "runtime view did not produce drawable output")

        concrete_runtime_view_tree?(previous_view_tree, ei) ->
          previous_view_tree

        true ->
          preview_unavailable_view_tree(target, "no renderable view tree")
      end

    base = normalize_debugger_render_tree(base)

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

  @spec normalize_debugger_render_tree(map()) :: map()
  defp normalize_debugger_render_tree(%{"type" => "Window"} = tree) do
    window =
      tree
      |> Map.put("type", "window")
      |> Map.put_new("label", "")

    %{"type" => "windowStack", "label" => "", "children" => [window]}
  end

  defp normalize_debugger_render_tree(%{"type" => "WindowStack"} = tree) do
    tree
    |> Map.put("type", "windowStack")
    |> Map.put_new("label", "")
  end

  defp normalize_debugger_render_tree(tree), do: tree

  @spec runtime_view_output_tree(map(), Types.surface_target()) :: map() | nil
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

  @spec positive_integer_value(Types.wire_input(), pos_integer()) :: pos_integer()
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

  @spec runtime_view_output_nodes([map()]) :: [map()]
  defp runtime_view_output_nodes(ops) when is_list(ops) do
    {nodes, _rest} = runtime_view_output_nodes_until(ops, false)
    nodes
  end

  @spec runtime_view_output_nodes_until([map()], boolean()) :: {[map()], [map()]}
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
        |> maybe_put_rendered_source(row)

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
        |> maybe_put_rendered_source(row)

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
        |> maybe_put_rendered_source(row)

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
        |> maybe_put_rendered_source(row)

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
        |> maybe_put_rendered_source(row)

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
        |> maybe_put_rendered_source(row)

      "pixel" ->
        %{
          "type" => "pixel",
          "label" => "",
          "children" => [],
          "x" => integer_or_zero(map_value(row, "x")),
          "y" => integer_or_zero(map_value(row, "y")),
          "color" => integer_or_zero(map_value(row, "color"))
        }
        |> maybe_put_rendered_source(row)

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
          "text" => to_string(map_value(row, "text") || ""),
          "text_align" => to_string(map_value(row, "text_align") || "center"),
          "text_overflow" => to_string(map_value(row, "text_overflow") || "word_wrap")
        }
        |> maybe_put_rendered_source(row)

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
        |> maybe_put_rendered_source(row)

      "vector_at" ->
        %{
          "type" => "drawVectorAt",
          "label" => "",
          "children" => [],
          "vector_id" => integer_or_zero(map_value(row, "vector_id")),
          "x" => integer_or_zero(map_value(row, "x")),
          "y" => integer_or_zero(map_value(row, "y"))
        }
        |> maybe_put_rendered_source(row)

      "vector_sequence_at" ->
        %{
          "type" => "drawVectorSequenceAt",
          "label" => "",
          "children" => [],
          "vector_id" => integer_or_zero(map_value(row, "vector_id")),
          "x" => integer_or_zero(map_value(row, "x")),
          "y" => integer_or_zero(map_value(row, "y"))
        }
        |> maybe_put_rendered_source(row)

      _ ->
        nil
    end
  end

  @spec maybe_put_rendered_source(map(), map()) :: map()
  defp maybe_put_rendered_source(node, row) when is_map(node) and is_map(row) do
    case map_value(row, "source") do
      %{} = source -> Map.put(node, "source", source)
      _ -> node
    end
  end

  @spec runtime_view_output_kind(map()) :: String.t()
  defp runtime_view_output_kind(row) when is_map(row),
    do: to_string(map_value(row, "kind") || "")

  @spec default_view_tree_for_target(Types.surface_label_input()) :: map()
  defp default_view_tree_for_target(:watch), do: Map.get(default_watch_runtime(), :view_tree)

  defp default_view_tree_for_target(:companion), do: Map.get(default_companion_runtime(), :view_tree)

  defp default_view_tree_for_target(:phone), do: Map.get(default_phone_runtime(), :view_tree)

  @spec refresh_runtime_fingerprints(Types.execution_model(), map(), map()) :: Types.execution_model()
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

  @spec maybe_put_runtime_source(map(), String.t(), String.t() | nil) :: map()
  defp maybe_put_runtime_source(runtime, _key, value) when not is_binary(value), do: runtime
  defp maybe_put_runtime_source(runtime, _key, value) when value == "", do: runtime
  defp maybe_put_runtime_source(runtime, key, value), do: Map.put(runtime, key, value)

  @spec mutate_runtime_model(map(), String.t(), [String.t()]) :: map()
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

  @spec parse_step_count(Types.wire_input()) :: pos_integer()
  defp parse_step_count(value) when is_integer(value) and value >= 1, do: min(value, 50)

  defp parse_step_count(value) when is_binary(value) do
    case Integer.parse(value) do
      {parsed, _} when parsed >= 1 -> min(parsed, 50)
      _ -> 1
    end
  end

  defp parse_step_count(_), do: 1

  @spec parse_optional_step_cursor_seq(Types.wire_input()) :: non_neg_integer() | nil
  defp parse_optional_step_cursor_seq(value) when is_integer(value) and value >= 0, do: value

  defp parse_optional_step_cursor_seq(value) when is_binary(value) do
    case Integer.parse(value) do
      {n, _} when n >= 0 -> n
      _ -> nil
    end
  end

  defp parse_optional_step_cursor_seq(_), do: nil

  @spec parse_replay_mode(Types.wire_input()) :: String.t()
  defp parse_replay_mode("live"), do: "live"
  defp parse_replay_mode("frozen"), do: "frozen"
  defp parse_replay_mode(_), do: "unknown"

  @spec view_tree_node_count(map() | [map()]) :: non_neg_integer()
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

  @spec stable_term_sha256(map() | list()) :: String.t()
  defp stable_term_sha256(term) do
    :crypto.hash(:sha256, :erlang.term_to_binary(term))
    |> Base.encode16(case: :lower)
  end

  @spec normalize_replay_rows_input(list() | map()) :: [Types.replay_row()]
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

  @spec recent_replay_messages(
          runtime_state(),
          Types.surface_target() | nil,
          integer(),
          integer() | nil
        ) :: [Types.replay_step_message()]
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

  @spec replay_target_label(Types.surface_label_input()) :: String.t()
  defp replay_target_label(nil), do: "all"
  defp replay_target_label(target), do: source_root_for_target(target)

  @spec maybe_filter_events_at_or_before_seq([runtime_event()], non_neg_integer() | nil) :: [runtime_event()]
  defp maybe_filter_events_at_or_before_seq(events, nil) when is_list(events), do: events

  defp maybe_filter_events_at_or_before_seq(events, cursor_seq)
       when is_list(events) and is_integer(cursor_seq) and cursor_seq >= 0 do
    Enum.filter(events, &(&1.seq <= cursor_seq))
  end

  @spec introspect_list(map() | nil, String.t()) :: [String.t()]
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

  @spec introspect_cmd_calls(map() | nil, String.t()) :: [map()]
  defp introspect_cmd_calls(ei, key) when is_map(ei) and is_binary(key) do
    case Map.get(ei, key) do
      rows when is_list(rows) ->
        rows
        |> Enum.filter(&is_map/1)
        |> Enum.map(fn row ->
          base = %{
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
            "arg_values" => Map.get(row, "arg_values") || Map.get(row, :arg_values) || [],
            "arg_kinds" => Map.get(row, "arg_kinds") || Map.get(row, :arg_kinds) || []
          }

          case Map.get(row, "activation_guards") || Map.get(row, :activation_guards) do
            guards when is_list(guards) and guards != [] ->
              Map.put(base, "activation_guards", guards)

            _ ->
              base
          end
        end)
        |> Enum.filter(fn row ->
          is_binary(row["name"]) and row["name"] != ""
        end)

      _ ->
        []
    end
  end

  defp introspect_cmd_calls(_, _), do: []

  @spec integer_or_zero(Types.wire_input()) :: integer()
  defp integer_or_zero(value) when is_integer(value) and value >= 0, do: value

  defp integer_or_zero(value) when is_binary(value) do
    case Integer.parse(value) do
      {n, _} when n >= 0 -> n
      _ -> 0
    end
  end

  defp integer_or_zero(_), do: 0

  @spec step_operation_for_message(String.t(), [String.t()]) :: atom()
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

  @spec contains_any?(String.t(), [String.t()] | String.t()) :: boolean()
  defp contains_any?(text, needles) when is_binary(text) and is_list(needles) do
    Enum.any?(needles, fn needle -> String.contains?(text, needle) end)
  end

  @spec operation_from_text(String.t()) :: atom()
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

  @spec filter_events_by_types(runtime_state(), [String.t()] | Types.wire_input()) :: runtime_state()
  defp filter_events_by_types(state, nil), do: state
  defp filter_events_by_types(state, []), do: state

  defp filter_events_by_types(state, types) when is_list(types) do
    allowed = MapSet.new(types)
    %{state | events: Enum.filter(state.events, &MapSet.member?(allowed, &1.type))}
  end

  defp filter_events_by_types(state, _types), do: state

  @spec filter_events_since_seq(runtime_state(), non_neg_integer() | Types.wire_input()) :: runtime_state()
  defp filter_events_since_seq(state, nil), do: state

  defp filter_events_since_seq(state, since_seq) when is_integer(since_seq) and since_seq >= 0 do
    %{state | events: Enum.filter(state.events, &(&1.seq > since_seq))}
  end

  defp filter_events_since_seq(state, _since_seq), do: state

  @spec default_state(String.t()) :: runtime_state()
  defp default_state(session_key) do
    project_slug = human_slug_from_session_key(session_key)

    watch_profile_id =
      persisted_project_watch_profile_id(session_key) || default_watch_profile_id()

    launch_context = launch_context_for(watch_profile_id, "LaunchUser")
    simulator_settings = persisted_project_simulator_settings(session_key)

    %{
      scope_key: session_key,
      project_slug: project_slug,
      running: false,
      revision: nil,
      watch_profile_id: watch_profile_id,
      launch_context: launch_context,
      simulator_settings: simulator_settings,
      watch: default_watch_runtime(launch_context),
      companion: default_companion_runtime(),
      phone: default_phone_runtime(),
      storage: %{},
      auto_tick: default_auto_tick(),
      disabled_subscriptions: [],
      events: [],
      debugger_timeline: [],
      debugger_seq: 0,
      seq: 0,
      app_message_queues: AppMessageQueue.empty()
    }
    |> apply_simulator_settings_to_surfaces()
  end

  @spec persisted_project_watch_profile_id(String.t()) :: String.t() | nil
  defp persisted_project_watch_profile_id(session_key) when is_binary(session_key) do
    try do
      with %{debugger_settings: settings} when is_map(settings) <-
             Projects.get_project_by_scope_key(session_key),
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

  @spec persisted_project_simulator_settings(String.t()) :: map()
  defp persisted_project_simulator_settings(session_key) when is_binary(session_key) do
    try do
      with %{debugger_settings: settings} when is_map(settings) <-
             Projects.get_project_by_scope_key(session_key),
           simulator when is_map(simulator) <- Map.get(settings, "simulator") do
        normalize_simulator_settings(simulator)
      else
        _ -> default_simulator_settings()
      end
    rescue
      _ -> default_simulator_settings()
    end
  end

  @spec session_key_from_state(map()) :: String.t() | nil
  defp session_key_from_state(%{scope_key: key}) when is_binary(key), do: key

  defp session_key_from_state(%{project_slug: slug}) when is_binary(slug), do: slug

  defp session_key_from_state(_), do: nil

  @spec human_slug_from_session_key(String.t()) :: String.t()
  defp human_slug_from_session_key(session_key) do
    case Projects.parse_scope_key(session_key) do
      {:ok, _, slug} -> slug
      :error -> session_key
    end
  end

  @spec default_auto_tick() :: Types.AutoTick.t()
  defp default_auto_tick do
    %{enabled: false, interval_ms: nil, target: "all", targets: [], count: 1, worker_pid: nil}
  end

  @spec default_watch_runtime(map() | nil) :: Surface.surface_map()
  defp default_watch_runtime(launch_context \\ nil) do
    launch_context =
      if is_map(launch_context),
        do: launch_context,
        else: launch_context_for(default_watch_profile_id(), "LaunchUser")

    Surface.from_map(%{
      model: %{
        "status" => "idle",
        "launch_context" => launch_context
      },
      last_message: nil,
      protocol_messages: [],
      view_tree: %{"type" => "root", "children" => []}
    })
    |> Surface.to_map()
  end

  @spec default_companion_runtime() :: Surface.surface_map()
  defp default_companion_runtime do
    Surface.from_map(%{
      model: protocol_surface_model("idle"),
      last_message: nil,
      protocol_messages: [],
      view_tree: %{
        "type" => "CompanionRoot",
        "label" => "idle",
        "box" => %{"x" => 0, "y" => 0, "w" => 180, "h" => 320},
        "children" => []
      }
    })
    |> Surface.to_map()
  end

  @spec attach_companion_configuration(map(), String.t()) :: map()
  defp attach_companion_configuration(state, session_key)
       when is_map(state) and is_binary(session_key) do
    case companion_configuration_model(session_key) do
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

  defp attach_companion_configuration(state, _session_key), do: state

  @spec attach_vector_resource_indices(map(), String.t()) :: map()
  defp attach_vector_resource_indices(state, project_slug)
       when is_map(state) and is_binary(project_slug) do
    case RuntimeArtifacts.vector_resource_indices_for_project(project_slug) do
      indices when is_map(indices) and map_size(indices) > 0 ->
        Surface.update_in_state(state, :watch, fn surface ->
          Surface.put_shell(surface, Map.put(surface.shell, "vector_resource_indices", indices))
        end)

      _ ->
        state
    end
  end

  defp attach_vector_resource_indices(state, _project_slug), do: state

  @spec attach_bitmap_resource_indices(map(), String.t()) :: map()
  defp attach_bitmap_resource_indices(state, project_slug)
       when is_map(state) and is_binary(project_slug) do
    case RuntimeArtifacts.bitmap_resource_indices_for_project(project_slug) do
      indices when is_map(indices) and map_size(indices) > 0 ->
        Surface.update_in_state(state, :watch, fn surface ->
          Surface.put_shell(surface, Map.put(surface.shell, "bitmap_resource_indices", indices))
        end)

      _ ->
        state
    end
  end

  defp attach_bitmap_resource_indices(state, _project_slug), do: state

  @spec companion_configuration_model(String.t()) :: map() | nil
  defp companion_configuration_model(session_key) do
    try do
      with %{} = project <- Projects.get_project_by_scope_key(session_key),
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

  @spec project_debugger_configuration_values(map()) :: map() | nil
  defp project_debugger_configuration_values(%{debugger_settings: settings})
       when is_map(settings) do
    case Map.get(settings, "configuration_values") do
      values when is_map(values) -> values
      _ -> nil
    end
  end

  defp project_debugger_configuration_values(_project), do: nil

  @spec companion_configuration_sections([map()]) :: [map()]
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

  @spec companion_configuration_fields([map()]) :: [map()]
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

  @spec stringify_keys(Types.wire_input()) :: Types.wire_input()
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

  @spec put_configuration_values_at(Types.app_model(), [String.t()], map()) ::
          Types.app_model()
  defp put_configuration_values_at(model, path, values) when is_map(model) and is_list(path) do
    case get_in(model, path) do
      %{} = configuration -> put_in(model, path, put_configuration_values(configuration, values))
      _ -> model
    end
  end

  defp put_configuration_values_at(model, _path, _values), do: model

  @spec put_configuration_values(map(), map()) :: map()
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

  @spec encode_configuration_values(map(), map()) :: map()
  defp encode_configuration_values(configuration, values)
       when is_map(configuration) and is_map(values) do
    configuration
    |> configuration_fields()
    |> Enum.reduce(%{}, fn field, acc ->
      id = Map.get(field, "id")
      control = Map.get(field, "control", %{})

      if is_binary(id) and id != "" do
        Map.put(
          acc,
          id,
          encode_configuration_value(control, configuration_value(values, id, control))
        )
      else
        acc
      end
    end)
  end

  defp encode_configuration_values(_configuration, values) when is_map(values), do: values

  @spec configuration_value(map(), String.t(), map()) :: Types.wire_input()
  defp configuration_value(values, id, control)
       when is_map(values) and is_binary(id) and is_map(control) do
    if Map.has_key?(values, id), do: Map.get(values, id), else: Map.get(control, "default")
  end

  @spec changed_configuration_values(map(), map()) :: map()
  defp changed_configuration_values(next_values, previous_values)
       when is_map(next_values) and is_map(previous_values) do
    Map.new(next_values, fn {key, value} -> {key, value} end)
    |> Enum.reject(fn {key, value} -> Map.get(previous_values, key) == value end)
    |> Map.new()
  end

  @spec configuration_fields(map()) :: [map()]
  defp configuration_fields(configuration) when is_map(configuration) do
    configuration
    |> Map.get("sections", [])
    |> Enum.flat_map(fn
      %{"fields" => fields} when is_list(fields) -> fields
      %{fields: fields} when is_list(fields) -> fields
      _ -> []
    end)
  end

  @spec encode_configuration_value(map(), Types.wire_input()) :: Types.wire_input()
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

  @spec truthy_configuration_value?(Types.wire_input()) :: boolean()
  defp truthy_configuration_value?(values) when is_list(values),
    do: Enum.any?(values, &truthy_configuration_value?/1)

  defp truthy_configuration_value?(value) when value in [true, "true", "True", "on", "1", 1],
    do: true

  defp truthy_configuration_value?(_value), do: false

  @spec apply_configuration_protocol_messages(runtime_state(), map(), map()) :: runtime_state()
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

  @spec configuration_protocol_arg(map(), Types.wire_input()) ::
          {:ok, String.t(), Types.protocol_wire_arg()} | :error
  defp configuration_protocol_arg(%{"type" => "toggle"}, value) do
    bool = truthy_configuration_value?(value)
    {:ok, if(bool, do: "True", else: "False"), bool}
  end

  defp configuration_protocol_arg(%{"type" => type}, value) when type in ["number", "slider"] do
    int_value =
      case value do
        n when is_integer(n) ->
          n

        n when is_float(n) ->
          round(n)

        value when is_binary(value) ->
          case Float.parse(value) do
            {parsed, _rest} -> round(parsed)
            :error -> 0
          end

        _ ->
          0
      end

    {:ok, Integer.to_string(int_value), int_value}
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

  @spec drop_companion_configuration(runtime_state()) :: runtime_state()
  defp drop_companion_configuration(model) when is_map(model) do
    model
    |> Map.drop(["configuration", :configuration])
    |> update_in(["runtime_model"], fn
      %{} = runtime_model -> Map.drop(runtime_model, ["configuration", :configuration])
      other -> other
    end)
  end

  defp drop_companion_configuration(model), do: model

  @spec default_phone_runtime() :: Surface.surface_map()
  defp default_phone_runtime do
    Surface.from_map(%{
      model: protocol_surface_model("idle"),
      last_message: nil,
      protocol_messages: [],
      view_tree: %{
        "type" => "PhoneRoot",
        "label" => "idle",
        "box" => %{"x" => 0, "y" => 0, "w" => 200, "h" => 360},
        "children" => []
      }
    })
    |> Surface.to_map()
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
    |> Map.update(
      :simulator_settings,
      default_simulator_settings(),
      &normalize_simulator_settings/1
    )
    |> apply_launch_context_to_watch_model_only()
    |> apply_simulator_settings_to_surfaces()
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

  defp maybe_put_protocol_runtime_value(map, _key, value) when value in [nil, ""], do: map
  defp maybe_put_protocol_runtime_value(map, key, value), do: Map.put(map, key, value)

  @spec apply_launch_context_to_watch_model_only(runtime_state()) :: map()
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

  @spec merge_launch_context_model(map(), map()) :: map()
  defp merge_launch_context_model(model, launch_context)
       when is_map(model) and is_map(launch_context) do
    profile_id = Map.get(launch_context, "watch_profile_id")
    color_mode = launch_context_color_mode(launch_context)
    width = get_in(launch_context, ["screen", "width"])
    height = get_in(launch_context, ["screen", "height"])

    model
    |> Map.put("launch_context", launch_context)
    |> Map.put("watch_profile_id", profile_id)
    |> Map.put("screen_width", width)
    |> Map.put("screen_height", height)
    |> Map.put("supports_color", color_mode == "Color")
  end

  defp merge_launch_context_model(model, _launch_context) when is_map(model), do: model
  defp merge_launch_context_model(_model, _launch_context), do: %{}

  @spec apply_simulator_settings_to_surfaces(runtime_state()) :: runtime_state()
  defp apply_simulator_settings_to_surfaces(state) when is_map(state) do
    settings = normalize_simulator_settings(Map.get(state, :simulator_settings))

    state
    |> Map.put(:simulator_settings, settings)
    |> update_in([:watch, :model], &merge_simulator_settings_model(&1 || %{}, settings))
    |> update_in([:companion, :model], &merge_simulator_settings_model(&1 || %{}, settings))
    |> update_in([:phone, :model], &merge_simulator_settings_model(&1 || %{}, settings))
  end

  @spec merge_simulator_settings_model(map(), map()) :: map()
  defp merge_simulator_settings_model(model, settings) when is_map(model) and is_map(settings) do
    model = Map.put(model, "simulator_settings", settings)

    case Map.get(model, "runtime_model") || Map.get(model, :runtime_model) do
      runtime_model when is_map(runtime_model) ->
        preview = %{
          "batteryLevel" => settings["battery_percent"],
          "connected" => settings["connected"],
          "charging" => settings["charging"],
          "clock_style_24h" => settings["clock_24h"],
          "timezone_id" => settings["timezone_id"],
          "timezone_offset_min" => settings["timezone_offset_min"],
          "locale" => settings["locale"],
          "language" => settings["language"],
          "region" => settings["region"],
          "network_online" => settings["network_online"],
          "notifications_enabled" => settings["notifications_enabled"],
          "quiet_hours" => settings["quiet_hours"]
        }

        Map.put(model, "runtime_model", merge_matching_preview_fields(runtime_model, preview))

      _ ->
        model
    end
  end

  defp merge_simulator_settings_model(model, _settings) when is_map(model), do: model
  defp merge_simulator_settings_model(_model, _settings), do: %{}

  @spec hydrate_runtime_model_for_message(Types.app_model(), String.t() | nil, [String.t()]) ::
          Types.app_model()
  defp hydrate_runtime_model_for_message(model, message, skip_fields)
       when is_map(model) and is_list(skip_fields) do
    runtime_model = Map.get(model, "runtime_model") || Map.get(model, :runtime_model)

    if is_map(runtime_model) do
      hydrated =
        runtime_model
        |> hydrate_static_runtime_model_values()
        |> hydrate_runtime_model_launch_context(model)
        |> hydrate_runtime_model_message_payload(message, skip_fields)

      Map.put(model, "runtime_model", hydrated)
    else
      model
    end
  end

  defp hydrate_runtime_model_for_message(model, _message, _skip_fields) when is_map(model), do: model
  @spec patched_runtime_model_fields(map()) :: [String.t()]
  defp patched_runtime_model_fields(patch) when is_map(patch) do
    case Map.get(patch, "runtime_model") || Map.get(patch, :runtime_model) do
      runtime_model when is_map(runtime_model) -> Enum.map(Map.keys(runtime_model), &to_string/1)
      _ -> []
    end
  end

  @spec hydrate_static_runtime_model_values(map()) :: map()
  defp hydrate_static_runtime_model_values(runtime_model) when is_map(runtime_model) do
    Map.new(runtime_model, fn {key, value} -> {key, hydrate_static_runtime_value(value)} end)
  end

  defp hydrate_static_runtime_model_values(runtime_model), do: runtime_model

  @spec hydrate_static_runtime_value(Types.wire_input()) :: Types.wire_input()
  defp hydrate_static_runtime_value(%{} = value) do
    cond do
      Map.has_key?(value, "$ctor") ->
        ctor = to_string(Map.get(value, "$ctor") || "")
        args = Map.get(value, "$args") || []
        hydrate_constructor_value(ctor, args)

      Map.has_key?(value, "ctor") ->
        ctor = to_string(Map.get(value, "ctor") || "")
        args = Map.get(value, "args") || []
        hydrate_constructor_value(ctor, args)

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

  defp hydrate_static_runtime_value(value) when is_binary(value),
    do: normalize_runtime_boolean_string(value)

  defp hydrate_static_runtime_value(value) when is_boolean(value), do: value
  defp hydrate_static_runtime_value(value), do: value

  @spec hydrate_constructor_value(String.t(), list()) :: Types.wire_input()
  defp hydrate_constructor_value(ctor, args) when is_binary(ctor) do
    args = if is_list(args), do: Enum.map(args, &hydrate_static_runtime_value/1), else: []

    case {ctor, args} do
      {"True", []} -> true
      {"False", []} -> false
      {"[]", []} -> []
      {"::", [head, tail]} -> [hydrate_static_runtime_value(head) | elm_list_wire_to_elixir(tail)]
      _ -> %{"ctor" => ctor, "args" => args}
    end
  end

  @spec elm_list_wire_to_elixir(term()) :: list()
  defp elm_list_wire_to_elixir([]), do: []

  defp elm_list_wire_to_elixir(%{"ctor" => "[]", "args" => []}), do: []

  defp elm_list_wire_to_elixir(%{"ctor" => "::", "args" => [head, tail]}) do
    [hydrate_static_runtime_value(head) | elm_list_wire_to_elixir(tail)]
  end

  defp elm_list_wire_to_elixir(%{ctor: "[]", args: []}), do: []

  defp elm_list_wire_to_elixir(%{ctor: "::", args: [head, tail]}) do
    [hydrate_static_runtime_value(head) | elm_list_wire_to_elixir(tail)]
  end

  defp elm_list_wire_to_elixir(list) when is_list(list), do: Enum.map(list, &hydrate_static_runtime_value/1)
  defp elm_list_wire_to_elixir(value), do: [hydrate_static_runtime_value(value)]

  @spec normalize_runtime_boolean_string(String.t()) :: boolean() | String.t()
  defp normalize_runtime_boolean_string(value) when is_binary(value) do
    case String.trim(value) do
      "True" -> true
      "False" -> false
      "true" -> true
      "false" -> false
      other -> other
    end
  end

  @spec static_color_call_value(String.t(), list()) :: {:ok, integer()} | :error
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
      "displayShape",
      launch_context_display_shape_ctor(Map.get(model, "launch_context"))
    )
    |> put_launch_context_value_if_missing(
      "colorMode",
      launch_context_color_capability(Map.get(model, "launch_context"))
    )
  end

  @spec put_launch_context_value_if_missing(map(), String.t(), Types.wire_scalar() | map()) ::
          map()
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

  @spec unresolved_runtime_value?(Types.wire_input()) :: boolean()
  defp unresolved_runtime_value?(%{"$opaque" => true}), do: true
  defp unresolved_runtime_value?(%{:"$opaque" => true}), do: true
  defp unresolved_runtime_value?(%{"op" => "field_access"}), do: true
  defp unresolved_runtime_value?(%{op: "field_access"}), do: true
  defp unresolved_runtime_value?(%{op: :field_access}), do: true
  defp unresolved_runtime_value?(_value), do: false

  @spec launch_context_display_shape(map()) :: String.t() | nil
  defp launch_context_display_shape(%{"screen" => %{} = screen}) do
    cond do
      Map.get(screen, "shape") in ["Round", "Rectangular"] ->
        Map.get(screen, "shape")

      Map.get(screen, "shape") == "round" ->
        "Round"

      Map.get(screen, "shape") == "rect" ->
        "Rectangular"

      Map.get(screen, "isRound") == true ->
        "Round"

      Map.get(screen, "isRound") == false ->
        "Rectangular"

      true ->
        nil
    end
  end

  defp launch_context_display_shape(%{"shape" => shape}) when shape in ["round", "rect"] do
    if shape == "round", do: "Round", else: "Rectangular"
  end

  defp launch_context_display_shape(_launch_context), do: nil

  @spec launch_context_display_shape_ctor(map()) :: map() | nil
  defp launch_context_display_shape_ctor(launch_context) when is_map(launch_context) do
    case launch_context_display_shape(launch_context) do
      "Round" -> %{"ctor" => "Round", "args" => []}
      "Rectangular" -> %{"ctor" => "Rectangular", "args" => []}
      _ -> nil
    end
  end

  defp launch_context_display_shape_ctor(_launch_context), do: nil

  @spec launch_context_color_capability(map()) :: map() | nil
  defp launch_context_color_capability(launch_context) when is_map(launch_context) do
    case launch_context_color_mode(launch_context) do
      "BlackWhite" -> %{"ctor" => "BlackWhite", "args" => []}
      "Color" -> %{"ctor" => "Color", "args" => []}
      _ -> nil
    end
  end

  defp launch_context_color_capability(_launch_context), do: nil

  @spec launch_context_color_mode(map()) :: String.t()
  defp launch_context_color_mode(launch_context) when is_map(launch_context) do
    cond do
      get_in(launch_context, ["screen", "color_mode"]) in ["Color", "BlackWhite"] ->
        get_in(launch_context, ["screen", "color_mode"])

      get_in(launch_context, ["screen", "colorMode"]) in ["Color", "BlackWhite"] ->
        get_in(launch_context, ["screen", "colorMode"])

      get_in(launch_context, ["screen", "is_color"]) == true ->
        "Color"

      get_in(launch_context, ["screen", "is_color"]) == false ->
        "BlackWhite"

      true ->
        "Color"
    end
  end

  @spec hydrate_runtime_model_message_payload(map(), String.t() | nil, [String.t()]) :: map()
  defp hydrate_runtime_model_message_payload(runtime_model, message, skip_fields)
       when is_map(runtime_model) and is_binary(message) and is_list(skip_fields) do
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
        maybe_put_message_payload_field(runtime_model, constructor, payload, skip_fields)

      constructor == "MinuteChanged" and is_integer(int_payload) ->
        runtime_model

      constructor == "HourChanged" and is_integer(int_payload) ->
        runtime_model

      true ->
        runtime_model
    end
  end

  defp hydrate_runtime_model_message_payload(runtime_model, _message, _skip_fields)
       when is_map(runtime_model),
       do: runtime_model

  @spec elm_message_payload(String.t()) :: Types.protocol_wire_arg() | nil
  defp elm_message_payload(message) when is_binary(message) do
    case String.split(String.trim(message), ~r/\s+/, parts: 2) do
      [_ctor, payload] -> elm_literal_payload(String.trim(payload))
      _ -> nil
    end
  end

  @spec elm_literal_payload(String.t()) :: Types.protocol_wire_arg() | nil
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

  @spec maybe_put_message_payload_field(map(), String.t(), Types.protocol_wire_arg(), [String.t()]) ::
          map()
  defp maybe_put_message_payload_field(runtime_model, constructor, payload, skip_fields)
       when is_map(runtime_model) and is_binary(constructor) and is_list(skip_fields) do
    case model_field_for_message_constructor(constructor, runtime_model) do
      field when is_binary(field) ->
        if field in skip_fields do
          runtime_model
        else
          if Map.has_key?(runtime_model, field) do
            put_payload_value_if_needed(runtime_model, field, payload, constructor)
          else
            runtime_model
          end
        end

      _ ->
        runtime_model
    end
  end

  defp maybe_put_message_payload_field(runtime_model, _constructor, _payload, _skip_fields),
    do: runtime_model

  @spec model_field_for_message_constructor(String.t(), map() | nil) :: String.t() | nil
  defp model_field_for_message_constructor(constructor, runtime_model)

  defp model_field_for_message_constructor("Got" <> rest, _runtime_model),
    do: lower_camel_name(rest)

  defp model_field_for_message_constructor(constructor, runtime_model)
       when is_binary(constructor) do
    case Map.get(@message_constructor_runtime_fields, constructor, []) do
      [] ->
        nil

      candidates ->
        pick_existing_runtime_field(candidates, runtime_model)
    end
  end

  @spec pick_existing_runtime_field([String.t()], map() | nil) :: String.t() | nil
  defp pick_existing_runtime_field(candidates, runtime_model) when is_list(candidates) do
    if is_map(runtime_model) do
      Enum.find(candidates, &Map.has_key?(runtime_model, &1))
    else
      List.first(candidates)
    end
  end

  @spec put_payload_value_if_needed(map(), String.t(), Types.protocol_wire_arg(), String.t()) ::
          map()
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

  @spec message_constructor_value?(Types.protocol_ctor_value(), String.t()) :: boolean()
  defp message_constructor_value?(value, constructor)
       when is_map(value) and is_binary(constructor) do
    ctor = Map.get(value, "ctor") || Map.get(value, "$ctor") || Map.get(value, :ctor)
    ctor == constructor
  end

  defp message_constructor_value?(_value, _constructor), do: false

  @spec integer_message_payload(Types.wire_input()) :: integer() | nil
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

  @spec merge_launch_context_view_tree(map(), map()) :: map()
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

  @spec apply_launch_context_to_surfaces(runtime_state(), String.t()) :: map()
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

  @spec parse_watch_profile_id(Types.wire_input()) :: String.t()
  defp parse_watch_profile_id(value) when is_binary(value) do
    normalized = String.downcase(String.trim(value))

    if Map.has_key?(watch_profiles_map(), normalized),
      do: normalized,
      else: default_watch_profile_id()
  end

  defp parse_watch_profile_id(_), do: default_watch_profile_id()

  @spec parse_optional_watch_profile_id(Types.wire_input()) :: String.t() | nil
  defp parse_optional_watch_profile_id(value) when is_binary(value),
    do: parse_watch_profile_id(value)

  defp parse_optional_watch_profile_id(_), do: nil

  @spec parse_launch_reason(Types.wire_input()) :: String.t()
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

  @spec watch_profiles_map() :: Types.watch_profiles_map()
  defp watch_profiles_map do
    WatchModels.profiles_map()
  end

  @spec watch_profile_label(Types.watch_profile()) :: String.t()
  defp watch_profile_label(profile) when is_map(profile) do
    name = Map.get(profile, "name") || "Watch"
    screen = Map.get(profile, "screen") || %{}
    width = Map.get(screen, "width") || 0
    height = Map.get(screen, "height") || 0

    color =
      case Map.get(profile, "color_mode") do
        "Color" -> "color"
        "BlackWhite" -> "mono"
        _ -> "mono"
      end

    "#{name} (#{width}x#{height}, #{color})"
  end

  defp watch_profile_label(_), do: "Watch"

  @spec launch_context_for(String.t(), String.t()) :: Types.LaunchContext.t()
  defp launch_context_for(watch_profile_id, launch_reason)
       when is_binary(watch_profile_id) and is_binary(launch_reason) do
    profile =
      Map.get(
        watch_profiles_map(),
        watch_profile_id,
        Map.get(watch_profiles_map(), default_watch_profile_id())
      )

    screen = Map.get(profile, "screen") || %{}
    profile_shape = Map.get(profile, "shape")

    display_shape =
      case profile_shape do
        "round" -> "Round"
        _ -> "Rectangular"
      end

    %{
      "launch_reason" => launch_reason,
      "watch_profile_id" => watch_profile_id,
      "watch_model" => Map.get(profile, "name"),
      "shape" => profile_shape,
      "has_microphone" => Map.get(profile, "has_microphone") == true,
      "has_compass" => Map.get(profile, "has_compass") == true,
      "supports_health" => Map.get(profile, "supports_health") == true,
      "screen" => %{
        "width" => Map.get(screen, "width") || 144,
        "height" => Map.get(screen, "height") || 168,
        "shape" => display_shape,
        "color_mode" => Map.get(profile, "color_mode") || "Color"
      }
    }
  end

  defp launch_context_for(_, _), do: launch_context_for(default_watch_profile_id(), "LaunchUser")

  @spec merge_runtime_model(runtime_state(), Types.surface_target(), Types.elmc_surface_fields()) ::
          runtime_state()
  defp merge_runtime_model(state, target, fields)
       when target in [:watch, :companion, :phone] and is_map(fields) do
    RuntimeSurfaceMerge.merge_into_state(state, target, fields)
  end

  @spec maybe_merge_runtime_artifacts(runtime_state(), Types.surface_target() | nil, map()) ::
          runtime_state()
  defp maybe_merge_runtime_artifacts(state, target, fields)
       when target in [:watch, :companion, :phone] and is_map(fields) and map_size(fields) > 0 do
    merge_runtime_model(state, target, fields)
  end

  defp maybe_merge_runtime_artifacts(state, _target, _fields), do: state

  @spec surface_for(runtime_state(), Types.surface_target()) :: Surface.t()
  defp surface_for(state, target) when is_map(state) and target in [:watch, :companion, :phone] do
    Surface.from_state(state, target)
  end

  @spec surface_app_model(runtime_state(), Types.surface_target()) :: Types.app_model()
  defp surface_app_model(state, target) when is_map(state) do
    state |> surface_for(target) |> Surface.app_model()
  end

  @spec introspect_for(runtime_state(), Types.surface_target()) :: map() | nil
  defp introspect_for(state, target) when is_map(state) do
    state |> surface_for(target) |> Surface.introspect()
  end

  @spec refresh_runtime_previews_from_artifacts(map()) :: map()
  defp refresh_runtime_previews_from_artifacts(state) when is_map(state) do
    Enum.reduce([:watch, :companion, :phone], state, fn target, acc ->
      refresh_runtime_preview_for_target(acc, target)
    end)
  end

  @spec refresh_runtime_preview_for_target(map(), :watch | :companion | :phone) :: map()
  defp refresh_runtime_preview_for_target(state, target)
       when is_map(state) and target in [:watch, :companion, :phone] do
    surface = state |> Map.get(target, %{}) |> RuntimeArtifacts.normalize_surface()
    model = Map.get(surface, :model) || %{}
    execution_model = RuntimeArtifacts.execution_model(surface)
    introspect = RuntimeArtifacts.introspect(execution_model)
    artifacts = RuntimeArtifacts.execution_artifacts(execution_model)

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
        |> RuntimeArtifacts.put_vector_resource_indices_on_request(execution_model)
        |> RuntimeArtifacts.put_bitmap_resource_indices_on_request(execution_model)

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

          ei = RuntimeArtifacts.require_introspect(next_model)

          runtime_view_tree =
            case runtime_view_output_tree(next_model, target) do
              %{} = output_tree ->
                if introspect_view_usable?(output_tree, ei), do: output_tree, else: nil

              _ ->
                nil
            end
            |> case do
              %{} = tree ->
                tree

              _ ->
                choose_runtime_preview_view_tree(
                  Map.get(payload, :view_tree),
                  view_tree,
                  view_tree,
                  runtime_view_output,
                  ei
                )
            end

          if introspect_view_usable?(runtime_view_tree, ei) do
            put_in(next_state, [target, :view_tree], runtime_view_tree)
          else
            next_state
          end

        _ ->
          state
      end
    else
      supplement_runtime_preview_without_executor(state, target, execution_model, introspect)
    end
  end

  @spec supplement_runtime_preview_without_executor(map(), atom(), map(), map() | nil) :: map()
  defp supplement_runtime_preview_without_executor(state, target, execution_model, introspect)
       when is_map(state) and target in [:watch, :companion, :phone] and is_map(execution_model) and
              is_map(introspect) do
    model = get_in(state, [target, :model]) || %{}
    runtime_model = RuntimeArtifacts.preview_runtime_model(model)

    view_output =
      supplement_parser_runtime_view_output(execution_model, Map.get(introspect, "view_tree") || %{}, runtime_model)

    if view_output == [] do
      state
    else
      put_in(state, [target, :model, "runtime_view_output"], view_output)
    end
  end

  defp supplement_runtime_preview_without_executor(state, _target, _execution_model, _introspect), do: state

  @spec merge_latest_runtime_render_inputs(map(), map()) :: map()
  defp merge_latest_runtime_render_inputs(snapshot_model, latest_model)
       when is_map(snapshot_model) and is_map(latest_model) do
    Enum.reduce(
      [
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

  @spec maybe_put_debugger_view_tree(map(), map() | nil) :: map()
  defp maybe_put_debugger_view_tree(runtime, runtime_view_tree) when is_map(runtime) do
    ei = RuntimeArtifacts.introspect(runtime) || %{}

    if introspect_view_usable?(runtime_view_tree, ei) do
      Map.put(runtime, :view_tree, runtime_view_tree)
    else
      runtime
    end
  end

  @spec choose_runtime_preview_view_tree(
          map() | nil,
          map() | nil,
          map() | nil,
          Types.runtime_view_nodes(),
          Types.elm_introspect()
        ) :: map() | nil
  defp choose_runtime_preview_view_tree(
         runtime_view_tree,
         latest_view_tree,
         snapshot_view_tree,
         _view_output,
         ei
       )
       when is_map(ei) do
    cond do
      concrete_runtime_view_tree?(runtime_view_tree, ei) ->
        runtime_view_tree

      concrete_runtime_view_tree?(latest_view_tree, ei) and
          parser_expression_view_tree?(runtime_view_tree, ei) ->
        latest_view_tree

      true ->
        if concrete_runtime_view_tree?(snapshot_view_tree, ei),
          do: snapshot_view_tree,
          else: nil
    end
  end

  @spec concrete_runtime_view_tree?(map(), map()) :: boolean()
  defp concrete_runtime_view_tree?(%{"type" => _} = tree, ei) when is_map(ei) do
    introspect_view_usable?(tree, ei) and not parser_expression_view_tree?(tree, ei)
  end

  defp concrete_runtime_view_tree?(_tree, _ei), do: false

  @spec parser_expression_view_tree?(map(), map()) :: boolean()
  defp parser_expression_view_tree?(tree, ei) when is_map(tree) and is_map(ei),
    do: Ide.Debugger.ElmIntrospect.parser_expression_view_tree_node?(tree, ei)

  defp parser_expression_view_tree?(_tree, _ei), do: false

  @spec normalize_source_root(map()) :: String.t()
  defp normalize_source_root(attrs) do
    case Map.get(attrs, :source_root) || Map.get(attrs, "source_root") do
      "protocol" -> "protocol"
      "phone" -> "phone"
      _ -> "watch"
    end
  end

  @spec normalize_step_target(Types.surface_label_input()) :: :watch | :companion | :phone
  defp normalize_step_target("companion"), do: :companion
  defp normalize_step_target("protocol"), do: :companion
  defp normalize_step_target("phone"), do: :companion
  defp normalize_step_target(:companion), do: :companion
  defp normalize_step_target(:phone), do: :companion
  defp normalize_step_target(_), do: :watch

  @spec normalize_optional_step_target(Types.wire_input()) :: (:watch | :companion | :phone) | nil
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
    |> apply_simulator_settings_to_surfaces()
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
      |> append_event(
        "debugger.reload",
        Ide.Debugger.Types.HotReloadEventPayload.from_reload(
          reason,
          rel_path,
          revision,
          source_root
        )
      )
      |> maybe_append_elm_introspect_event(intro_payload)
      |> maybe_append_runtime_exec_event(source_root)
    end)
    |> append_event("debugger.protocol_tx", protocol_reload_payload(revision, source_root))
    |> append_event("debugger.protocol_rx", protocol_reload_payload(revision, source_root))
    |> append_event(
      "debugger.view_render",
      Ide.Debugger.Types.ViewRenderEventPayload.from_render("watch", "simulated-root")
    )
    |> append_event(
      "debugger.view_render",
      Ide.Debugger.Types.ViewRenderEventPayload.from_render("companion", "companion-root")
    )
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
            |> maybe_apply_init_geolocation_response(introspect_target_key(source_root))
            |> maybe_apply_init_companion_bridge_commands(introspect_target_key(source_root))
            |> then(fn reloaded ->
              if introspect_target_key(source_root) == :watch do
                refresh_runtime_preview_for_target(reloaded, :watch)
              else
                reloaded
              end
            end)

          payload =
            if introspect_event_worth_logging?(ei) do
              ElmIntrospectEventPayload.from_introspect(
                ei,
                rel_path,
                source_root,
                introspect_view_usable?(Map.get(ei, "view_tree") || %{}, ei)
              )
            else
              nil
            end

          {st, payload}

        _ ->
          {state, nil}
      end
      |> then(fn {st, payload} -> {apply_simulator_settings_to_surfaces(st), payload} end)
    else
      {state, nil}
    end
  end

  @spec maybe_append_elm_introspect_event(runtime_state(), map() | nil) :: map()
  defp maybe_append_elm_introspect_event(state, nil), do: state

  defp maybe_append_elm_introspect_event(state, payload) when is_map(payload) do
    append_event(state, "debugger.elm_introspect", payload)
  end

  @spec maybe_append_runtime_exec_event(runtime_state(), String.t()) :: map()
  defp maybe_append_runtime_exec_event(state, source_root) do
    target = introspect_target_key(source_root)
    append_runtime_exec_event_for_target(state, target)
  end

  @spec append_runtime_exec_event_for_target(
          runtime_state(),
          :watch | :companion | :phone,
          map()
        ) :: runtime_state()
  defp append_runtime_exec_event_for_target(state, target, extra \\ %{})
       when target in [:watch, :companion, :phone] and is_map(extra) do
    runtime = get_in(state, [target, :model, "elm_executor"])

    if is_map(runtime) and map_size(runtime) > 0 do
      payload =
        Ide.Debugger.Types.RuntimeExecEventPayload.from_runtime(
          runtime,
          source_root_for_target(target),
          extra
        )

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
        |> append_event(
          "debugger.runtime_status",
          Ide.Debugger.Types.RuntimeStatusEventPayload.from_runtime(
            runtime,
            source_root_for_target(target),
            message
          )
        )
        |> append_debugger_event("runtime", target, message, "runtime_status")
    end
  end

  defp maybe_append_runtime_status_debugger_event(state, _target, _execution, _introspect),
    do: state

  @spec execution_followup_messages(map()) :: list()
  defp execution_followup_messages(execution) when is_map(execution) do
    case Map.get(execution, :followup_messages) || Map.get(execution, "followup_messages") do
      messages when is_list(messages) -> messages
      _ -> []
    end
  end

  @spec meaningful_init_cmd_count(map()) :: non_neg_integer()
  defp meaningful_init_cmd_count(introspect) do
    introspect
    |> introspect_cmd_calls("init_cmd_calls")
    |> Enum.count(&meaningful_init_cmd_call?/1)
  end

  @spec meaningful_init_cmd_call?(map()) :: boolean()
  defp meaningful_init_cmd_call?(call) when is_map(call) do
    target = Map.get(call, "target") || Map.get(call, :target)
    name = Map.get(call, "name") || Map.get(call, :name)
    not (target in ["Cmd.none", "Platform.Cmd.none"] or name in ["none", "None", nil])
  end

  defp meaningful_init_cmd_call?(_call), do: false

  @spec runtime_status_message(map()) :: String.t() | nil
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

  @spec runtime_init_execution?(map()) :: boolean()
  defp runtime_init_execution?(runtime) when is_map(runtime) do
    runtime["operation_source"] in ["init_model", nil] and
      runtime["runtime_model_source"] in ["init_model", nil]
  end

  @spec introspect_event_worth_logging?(map()) :: boolean()
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
      introspect_view_usable?(vt, ei)
  end


  @spec elm_introspect?(String.t() | nil, String.t() | nil, String.t()) :: boolean()
  defp elm_introspect?(rel_path, source, source_root) do
    source_root in ["watch", "phone"] and is_binary(rel_path) and
      String.ends_with?(rel_path, ".elm") and is_binary(source) and String.trim(source) != ""
  end

  @spec introspect_target_key(String.t()) :: :watch | :companion | :phone
  defp introspect_target_key("watch"), do: :watch
  defp introspect_target_key("protocol"), do: :companion
  defp introspect_target_key("phone"), do: :companion
  defp introspect_target_key(_), do: :watch

  @spec source_root_for_target(Types.surface_target()) :: String.t()
  defp source_root_for_target(:watch), do: "watch"
  defp source_root_for_target(:companion), do: "phone"
  defp source_root_for_target(:phone), do: "phone"

  @spec http_eval_context(Types.execution_model(), map()) :: map()
  defp http_eval_context(model, settings) when is_map(model) and is_map(settings) do
    weather = Map.get(settings, "weather")

    extras =
      if is_map(weather) and map_size(weather) > 0,
        do: [simulator_weather: weather],
        else: []

    RuntimeArtifacts.core_ir_eval_context(model, extras)
  end

  defp http_eval_context(_model, _settings), do: %{}

  @spec simulated_http_response?(map() | nil) :: boolean()
  defp simulated_http_response?(%{"status" => 200, "body" => body}) when is_binary(body) do
    case Jason.decode(body) do
      {:ok, %{"current" => _}} -> true
      {:ok, %{"temperature" => _}} -> true
      _ -> false
    end
  end

  defp simulated_http_response?(_response), do: false

  @spec http_command_event(Types.cmd_call()) :: map()
  defp http_command_event(command) when is_map(command) do
    %{
      method: Map.get(command, "method") || Map.get(command, :method),
      url: Map.get(command, "url") || Map.get(command, :url),
      package: Map.get(command, "package") || Map.get(command, :package)
    }
  end

  @spec apply_elm_introspect_snapshot(
          runtime_state(),
          Types.elm_introspect(),
          Types.surface_target(),
          String.t(),
          String.t() | nil
        ) :: runtime_state()
  defp apply_elm_introspect_snapshot(state, ei, target, source, rel_path)
       when is_map(ei) and target in [:watch, :companion, :phone] and is_binary(source) do
    state = maybe_attach_compile_artifacts_for_parser_view(state, target, ei)
    surface = Map.get(state, target) || %{}
    model = Map.get(surface, :model) || %{}
    shell = RuntimeArtifacts.shell_map(surface)
    view_tree = Map.get(surface, :view_tree) || %{}
    execution_model = RuntimeArtifacts.execution_model(surface)

    request =
      %{
        source_root: source_root_for_target(target),
        rel_path: rel_path || model["last_path"],
        source: source,
        introspect: ei,
        current_model: current_model_for_introspect_execution(model),
        current_view_tree: view_tree
      }
      |> Map.merge(RuntimeArtifacts.execution_artifacts(execution_model))
      |> RuntimeArtifacts.put_vector_resource_indices_on_request(execution_model)
      |> RuntimeArtifacts.put_bitmap_resource_indices_on_request(execution_model)

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
        "elm_executor_mode" => "runtime_executed"
      })
      |> Map.merge(model_patch)
      |> put_runtime_view_output(Map.get(execution, :view_output))
      |> hydrate_runtime_model_for_message(nil, [])

    next_shell = Map.put(shell, "elm_introspect", ei)

    vt = Map.get(ei, "view_tree")
    runtime_vt = Map.get(execution, :view_tree)
    output_vt = runtime_view_output_tree(model, target)

    state =
      state
      |> put_in([target, :model], model)
      |> put_in([target, :shell], next_shell)

    parser_view? = Ide.Debugger.ElmIntrospect.parser_expression_view?(%{"elm_introspect" => ei})

    state =
      cond do
        introspect_view_usable?(output_vt, ei) ->
          put_in(state, [target, :view_tree], output_vt)

        introspect_view_usable?(runtime_vt, ei) and runtime_preview_has_drawable_output?(model) ->
          put_in(state, [target, :view_tree], runtime_vt)

        parser_view? and not introspect_view_usable?(output_vt, ei) and
            not introspect_view_usable?(runtime_vt, ei) ->
          put_in(
            state,
            [target, :view_tree],
            preview_unavailable_view_tree(target, "runtime view did not produce drawable output")
          )

        introspect_view_usable?(vt, ei) ->
          put_in(state, [target, :view_tree], vt)

        parser_expression_view_tree?(vt, ei) ->
          put_in(
            state,
            [target, :view_tree],
            preview_unavailable_view_tree(target, "parser view did not produce drawable output")
          )

        true ->
          state
      end

    state
    |> append_event(
      "debugger.init_in",
      Ide.Debugger.Types.MessageInEventPayload.from_message(
        source_root_for_target(target),
        "init",
        "init"
      )
    )
    |> append_debugger_event("init", target, "init", "init")
    |> maybe_append_runtime_status_debugger_event(target, execution, ei)
    |> maybe_apply_runtime_followups(
      target,
      "init",
      "init",
      normalize_followup_messages(execution_followup_messages(execution))
    )
    |> drain_app_message_queue(target)
  end

  @spec current_model_for_introspect_execution(Types.execution_model()) :: Types.execution_model()
  defp current_model_for_introspect_execution(model) when is_map(model) do
    Map.delete(model, "runtime_model")
  end

  defp current_model_for_introspect_execution(_model), do: %{}

  @spec introspect_view_usable?(map(), Types.elm_introspect()) :: boolean()
  defp introspect_view_usable?(%{"type" => "unknown", "children" => []}, _ei), do: false

  defp introspect_view_usable?(%{"type" => type} = tree, ei) when is_binary(type) do
    type not in ["root", "unknown", "previewUnavailable"] and
      not unresolved_parser_view_root?(tree, ei)
  end

  defp introspect_view_usable?(%{"children" => children}, _ei)
       when is_list(children) and children != [],
       do: true

  defp introspect_view_usable?(_tree, _ei), do: false

  @spec unresolved_parser_view_root?(map(), Types.elm_introspect()) :: boolean()
  defp unresolved_parser_view_root?(tree, ei) when is_map(tree) and is_map(ei),
    do: Ide.Debugger.ElmIntrospect.parser_expression_view_tree_node?(tree, ei)

  defp unresolved_parser_view_root?(_tree, _ei), do: false

  @spec runtime_preview_has_drawable_output?(map()) :: boolean()
  defp runtime_preview_has_drawable_output?(model) when is_map(model) do
    model
    |> Map.get("runtime_view_output", [])
    |> List.wrap()
    |> Enum.any?(fn
      %{"kind" => kind} when is_binary(kind) and kind not in ["clear", ""] -> true
      %{kind: kind} when is_binary(kind) and kind not in ["clear", ""] -> true
      _ -> false
    end)
  end

  @spec preview_unavailable_view_tree(:watch | :companion | :phone, String.t()) :: map()
  defp preview_unavailable_view_tree(target, reason) do
    %{
      "type" => "previewUnavailable",
      "label" => reason,
      "target" => source_root_for_target(target),
      "children" => []
    }
  end

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

  @spec reload_pulse(Types.surface_target(), String.t()) :: String.t()
  defp reload_pulse(:watch, "phone"), do: "PhoneSync"
  defp reload_pulse(:companion, "phone"), do: "PhoneSync"
  defp reload_pulse(:phone, "phone"), do: "PhoneHotReload"
  defp reload_pulse(:watch, "protocol"), do: "ProtocolSync"
  defp reload_pulse(:companion, "protocol"), do: "ProtocolHotReload"
  defp reload_pulse(:phone, "protocol"), do: "ProtocolSync"
  defp reload_pulse(_, _), do: "HotReload"

  @spec maybe_append_phone_view_render(runtime_state(), String.t()) :: map()
  defp maybe_append_phone_view_render(state, "phone") do
    append_event(
      state,
      "debugger.view_render",
      Ide.Debugger.Types.ViewRenderEventPayload.from_render("phone", "phone-root")
    )
  end

  defp maybe_append_phone_view_render(state, _), do: state

  @spec protocol_reload_payload(String.t(), String.t()) :: Types.protocol_tx_rx_payload()
  defp protocol_reload_payload(revision, source_root) when is_binary(revision) do
    Ide.Debugger.Types.ProtocolTxRxPayload.from_reload(revision, source_root)
  end

  @spec export_payload(String.t(), runtime_state(), Types.export_trace_opts()) ::
          Types.import_trace_body()
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
      "companion" => normalize_term(Surface.to_map(Surface.from_state(state, :companion))),
      "debugger_seq" => Map.get(state, :debugger_seq, 0),
      "debugger_timeline" => normalize_term(Map.get(state, :debugger_timeline, [])),
      "disabled_subscriptions" => normalize_term(disabled_subscriptions(state)),
      "events" => events,
      "export_version" => 1,
      "phone" => normalize_term(Surface.to_map(Surface.from_state(state, :phone))),
      "project_slug" => project_slug,
      "revision" => Map.get(state, :revision),
      "running" => Map.get(state, :running, false),
      "watch_profile_id" => Map.get(state, :watch_profile_id),
      "launch_context" => normalize_term(Map.get(state, :launch_context, %{})),
      "simulator_settings" => normalize_term(simulator_settings_from_state(state)),
      "runtime_fingerprint_compare" => normalize_term(runtime_fingerprint_compare),
      "seq" => Map.get(state, :seq, 0),
      "watch" => normalize_term(Surface.to_map(Surface.from_state(state, :watch)))
    }
  end

  @spec build_runtime_fingerprint_compare_payload(
          [runtime_event()],
          integer() | nil,
          integer() | nil
        ) :: map()
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

  @spec resolve_export_compare_cursor([runtime_event()], integer() | nil) :: integer() | nil
  defp resolve_export_compare_cursor(events, cursor_seq) when is_list(events) do
    CursorSeq.resolve_at_or_before(events, cursor_seq)
  end

  @spec resolve_export_baseline_cursor(
          [runtime_event()],
          integer() | nil,
          integer()
        ) :: integer() | nil
  defp resolve_export_baseline_cursor(events, baseline_cursor_seq, current_seq)
       when is_list(events) and is_integer(current_seq) do
    CursorSeq.resolve_before(events, current_seq, baseline_cursor_seq)
  end

  defp resolve_export_baseline_cursor(_events, _baseline_cursor_seq, _current_seq), do: nil

  @spec event_at_seq([runtime_event()], integer() | nil) :: runtime_event() | nil
  defp event_at_seq(events, seq) when is_list(events) and is_integer(seq),
    do: Enum.find(events, &(&1.seq == seq))

  defp event_at_seq(_events, _seq), do: nil

  @spec event_runtime_fingerprints(runtime_event() | nil) :: %{
          watch: Types.runtime_fingerprint() | nil,
          companion: Types.runtime_fingerprint() | nil,
          phone: Types.runtime_fingerprint() | nil
        }
  defp event_runtime_fingerprints(nil), do: %{watch: nil, companion: nil, phone: nil}

  defp event_runtime_fingerprints(event) when is_map(event) do
    %{
      watch: runtime_fingerprint_from_surface(Map.get(event, :watch)),
      companion: runtime_fingerprint_from_surface(Map.get(event, :companion)),
      phone: runtime_fingerprint_from_surface(Map.get(event, :phone))
    }
  end

  @spec runtime_fingerprint_from_surface(map()) :: Types.runtime_fingerprint()
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

  @spec map_value(map(), String.t() | atom()) :: Types.wire_input()
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

  @spec maybe_put_snapshot_refs(map(), map()) :: map()
  defp maybe_put_snapshot_refs(row, refs) when map_size(refs) == 0, do: row
  defp maybe_put_snapshot_refs(row, refs), do: Map.put(row, "snapshot_refs", refs)

  @spec snapshot_surface(Surface.t() | map(), Surface.t() | map()) :: map()
  defp snapshot_surface(%Surface{} = surface, _fallback), do: Surface.to_map(surface)
  defp snapshot_surface(surface, _fallback) when is_map(surface), do: surface

  @spec normalize_term(Types.wire_input() | atom()) :: Types.normalized_export_term()
  defp normalize_term(%Surface{} = surface), do: normalize_term(Surface.to_map(surface))

  defp normalize_term(map) when is_map(map) do
    map
    |> Enum.map(fn {k, v} -> {to_string(k), normalize_term(v)} end)
    |> Enum.sort_by(fn {k, _} -> k end)
    |> Map.new()
  end

  defp normalize_term(list) when is_list(list), do: Enum.map(list, &normalize_term/1)

  defp normalize_term(other), do: other

  @spec decode_import_body(String.t() | map()) :: {:ok, map()} | {:error, Types.protocol_error()}
  defp decode_import_body(json) when is_binary(json) do
    case Jason.decode(json) do
      {:ok, body} when is_map(body) -> {:ok, body}
      {:ok, _} -> {:error, :invalid_trace}
      {:error, _} -> {:error, :invalid_json}
    end
  end

  defp decode_import_body(body) when is_map(body), do: {:ok, body}

  @spec validate_import_body(Types.import_trace_body()) :: :ok | {:error, Types.protocol_error()}
  defp validate_import_body(body) do
    version = Map.get(body, "export_version")

    if version == 1 and is_list(Map.get(body, "events")) and is_map(Map.get(body, "watch")) and
         is_map(Map.get(body, "companion")) and is_integer(Map.get(body, "seq")) do
      :ok
    else
      {:error, :invalid_trace}
    end
  end

  @spec maybe_match_import_slug(map(), String.t(), keyword()) :: :ok | {:error, Types.protocol_error()}
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
      simulator_settings: normalize_simulator_settings(Map.get(body, "simulator_settings")),
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

    parsed_state
    |> ensure_phone_state()
    |> apply_simulator_settings_to_surfaces()
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

  @spec import_debugger_timeline(list()) :: [debugger_event()]
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

  @spec infer_debugger_seq(map()) :: non_neg_integer()
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

  @spec import_watch(map()) :: Surface.surface_map()
  defp import_watch(map) when is_map(map) do
    Surface.to_map(
      Surface.from_map(%{
        model: Map.get(map, "model") || %{},
        shell: Map.get(map, "shell") || %{},
        last_message: Map.get(map, "last_message"),
        protocol_messages: Map.get(map, "protocol_messages") || [],
        view_tree:
          Map.get(map, "view_tree") ||
            %{
              "type" => "root",
              "children" => []
            }
      })
    )
  end

  @spec import_companion(map()) :: Surface.surface_map()
  defp import_companion(map) when is_map(map) do
    Surface.to_map(
      Surface.from_map(%{
        model: Map.get(map, "model") || %{},
        shell: Map.get(map, "shell") || %{},
        last_message: Map.get(map, "last_message"),
        protocol_messages: Map.get(map, "protocol_messages") || [],
        view_tree:
          Map.get(map, "view_tree") ||
            %{
              "type" => "CompanionRoot",
              "label" => "idle",
              "children" => []
            }
      })
    )
  end

  @spec import_phone(map()) :: Surface.surface_map()
  defp import_phone(map) when is_map(map) do
    Surface.to_map(
      Surface.from_map(%{
        model: Map.get(map, "model") || %{},
        shell: Map.get(map, "shell") || %{},
        last_message: Map.get(map, "last_message"),
        protocol_messages: Map.get(map, "protocol_messages") || [],
        view_tree:
          Map.get(map, "view_tree") ||
            %{
              "type" => "PhoneRoot",
              "label" => "idle",
              "children" => []
            }
      })
    )
  end

  @spec runtime_executor_module() :: module()
  defp runtime_executor_module do
    Application.get_env(:ide, __MODULE__, [])
    |> Keyword.get(:runtime_executor_module, RuntimeExecutor)
  end
end
