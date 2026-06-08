defmodule Ide.Debugger do
  @moduledoc """
  Lightweight debugger state substrate for watch, companion, and phone runtimes.

  This module is the public Agent-backed API. Implementation is split by domain:

  * `Ide.Debugger.SessionApi` — session lifecycle, watch profile, simulator settings
  * `Ide.Debugger.CompileIngestApi` — `elmc` check/compile/manifest ingest
  * `Ide.Debugger.RuntimeApi` — reload, manual step, runtime preview rendering
  * `Ide.Debugger.ConfigurationApi` — companion configuration save/reload
  * `Ide.Debugger.TraceApi` — snapshots, trace export/import, replay, continue
  * `Ide.Debugger.TriggersApi` — trigger candidates, injection, subscription UI helpers
  * `Ide.Debugger.TickApi` — deterministic and auto tick ingress
  * `Ide.Debugger.SettingsApi` — read-only simulator settings helpers

  Agent wiring (`mutate`, event log, host maps) lives in `Ide.Debugger.AgentSession` and
  `Ide.Debugger.AgentHosts`.
  """

  use Agent

  alias Ide.Debugger.CompileIngestApi
  alias Ide.Debugger.ConfigurationApi
  alias Ide.Debugger.RuntimeApi
  alias Ide.Debugger.SessionApi
  alias Ide.Debugger.SettingsApi
  alias Ide.Debugger.TickApi
  alias Ide.Debugger.TraceApi
  alias Ide.Debugger.TriggersApi
  alias Ide.Debugger.Types
  alias Ide.Debugger.Types.RuntimeState

  @type runtime_event :: RuntimeState.runtime_event()
  @type debugger_event :: RuntimeState.debugger_event()
  @type runtime_state :: RuntimeState.t() | RuntimeState.wire_map()
  @type snapshot_opt :: Types.snapshot_opt()

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(_opts), do: Agent.start_link(fn -> %{} end, name: __MODULE__)

  # Session lifecycle
  @spec start_session(String.t()) :: {:ok, runtime_state()}
  @spec start_session(String.t(), Types.session_attrs()) :: {:ok, runtime_state()}
  defdelegate start_session(project_slug), to: SessionApi
  defdelegate start_session(project_slug, attrs), to: SessionApi

  @spec reset(String.t()) :: {:ok, runtime_state()}
  defdelegate reset(project_slug), to: SessionApi

  @spec forget_project(String.t()) :: :ok
  defdelegate forget_project(project_slug), to: SessionApi

  @spec set_watch_profile(String.t(), Types.session_attrs()) :: {:ok, runtime_state()}
  defdelegate set_watch_profile(project_slug, attrs \\ %{}), to: SessionApi

  @spec set_simulator_settings(String.t(), Types.simulator_settings()) :: {:ok, runtime_state()}
  defdelegate set_simulator_settings(project_slug, attrs \\ %{}), to: SessionApi

  # Settings (read-only helpers)
  @spec watch_profiles() :: [Types.watch_profile_list_item()]
  defdelegate watch_profiles(), to: SettingsApi

  @spec default_simulator_settings() :: Types.simulator_settings()
  defdelegate default_simulator_settings(), to: SettingsApi, as: :default

  @spec normalize_simulator_settings(Types.SimulatorSettings.wire_map()) ::
          Types.simulator_settings()
  defdelegate normalize_simulator_settings(settings), to: SettingsApi, as: :normalize

  # Compile ingest
  @spec ingest_elmc_check(String.t(), Types.compile_ingest_attrs()) :: {:ok, runtime_state()}
  defdelegate ingest_elmc_check(project_slug, attrs), to: CompileIngestApi

  @spec ingest_elmc_compile(String.t(), Types.compile_ingest_attrs()) :: {:ok, runtime_state()}
  defdelegate ingest_elmc_compile(project_slug, attrs), to: CompileIngestApi

  @spec ingest_elmc_manifest(String.t(), Types.compile_ingest_attrs()) :: {:ok, runtime_state()}
  defdelegate ingest_elmc_manifest(project_slug, attrs), to: CompileIngestApi

  # Runtime stepping and preview
  @spec render_runtime_preview_for_debugger(
          Ide.Debugger.Surface.surface_map() | nil,
          Ide.Debugger.Surface.surface_map() | nil,
          Types.surface_target()
        ) :: Ide.Debugger.Surface.surface_map() | nil
  defdelegate render_runtime_preview_for_debugger(snapshot_runtime, latest_runtime, target),
    to: RuntimeApi

  @spec reload(String.t(), Types.reload_attrs()) :: {:ok, runtime_state()}
  defdelegate reload(project_slug, attrs \\ %{}), to: RuntimeApi

  @spec step(String.t(), Types.step_attrs()) :: {:ok, runtime_state()}
  defdelegate step(project_slug, attrs \\ %{}), to: RuntimeApi

  # Companion configuration
  @spec save_configuration(String.t(), Types.save_configuration_attrs()) :: {:ok, runtime_state()}
  defdelegate save_configuration(project_slug, values), to: ConfigurationApi

  @spec reload_configuration(String.t()) :: {:ok, runtime_state()}
  defdelegate reload_configuration(project_slug), to: ConfigurationApi

  # Trace and snapshots
  @spec replay_recent(String.t(), Types.replay_attrs()) :: {:ok, runtime_state()}
  defdelegate replay_recent(project_slug, attrs \\ %{}), to: TraceApi

  @spec continue_from_snapshot(String.t(), Types.snapshot_continue_attrs()) ::
          {:ok, runtime_state()}
  defdelegate continue_from_snapshot(project_slug, attrs \\ %{}), to: TraceApi

  @spec snapshot_reference_rows([runtime_event()]) :: [Types.wire_map()]
  defdelegate snapshot_reference_rows(events), to: TraceApi

  @spec export_trace(String.t(), Types.export_trace_opts()) :: {:ok, Types.export_trace_result()}
  defdelegate export_trace(project_slug, opts \\ []), to: TraceApi

  @spec import_trace(String.t(), Types.import_trace_input(), keyword()) ::
          {:ok, runtime_state()}
          | {:error, Types.protocol_error() | atom() | String.t() | Types.wire_map()}
  defdelegate import_trace(session_key, input, opts \\ []), to: TraceApi

  @spec snapshot(String.t(), Types.snapshot_opts()) :: {:ok, runtime_state()}
  defdelegate snapshot(project_slug, opts \\ []), to: TraceApi

  # Triggers and subscriptions
  @spec trigger_candidates(runtime_state() | map(), :watch | :companion | :phone | nil) ::
          [Types.trigger_candidate()]
  defdelegate trigger_candidates(state, target \\ :watch), to: TriggersApi

  @spec available_triggers(String.t(), Types.available_triggers_attrs()) ::
          {:ok, [Types.trigger_candidate()]}
  defdelegate available_triggers(project_slug, attrs \\ %{}), to: TriggersApi

  @spec inject_trigger(String.t(), Types.inject_trigger_attrs()) :: {:ok, runtime_state()}
  defdelegate inject_trigger(project_slug, attrs \\ %{}), to: TriggersApi

  @spec subscription_trigger_injection_modal_supported?(runtime_state(), Types.replay_row()) ::
          boolean()
  defdelegate subscription_trigger_injection_modal_supported?(state, row), to: TriggersApi

  @spec set_subscription_enabled(String.t(), Types.step_attrs()) :: {:ok, runtime_state()}
  defdelegate set_subscription_enabled(project_slug, attrs \\ %{}), to: TriggersApi

  @spec subscription_trigger_display(Types.cmd_call() | nil, String.t() | nil) :: String.t()
  defdelegate subscription_trigger_display(op, trigger), to: TriggersApi

  @spec subscription_trigger_display_for(runtime_state() | map(), String.t(), String.t()) ::
          String.t()
  defdelegate subscription_trigger_display_for(state, trigger, target_name), to: TriggersApi

  @spec subscription_model_active?(runtime_state(), Types.surface_target(), Types.replay_row()) ::
          boolean()
  defdelegate subscription_model_active?(state, target, row), to: TriggersApi

  # Tick ingress
  @spec tick(String.t(), Types.step_attrs()) :: {:ok, runtime_state()}
  defdelegate tick(project_slug, attrs \\ %{}), to: TickApi

  @spec start_auto_tick(String.t(), Types.step_attrs()) :: {:ok, runtime_state()}
  defdelegate start_auto_tick(project_slug, attrs \\ %{}), to: TickApi

  @spec stop_auto_tick(String.t()) :: {:ok, runtime_state()}
  defdelegate stop_auto_tick(project_slug), to: TickApi

  @spec set_auto_fire(String.t(), Types.step_attrs()) :: {:ok, runtime_state()}
  defdelegate set_auto_fire(project_slug, attrs \\ %{}), to: TickApi
end
