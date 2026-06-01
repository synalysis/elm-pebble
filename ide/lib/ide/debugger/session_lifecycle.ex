defmodule Ide.Debugger.SessionLifecycle do
  @moduledoc false

  alias Ide.Debugger.AppMessageQueue
  alias Ide.Debugger.BootstrapInit
  alias Ide.Debugger.CompanionConfiguration
  alias Ide.Debugger.ProjectResourceIndices
  alias Ide.Debugger.RuntimeSurfaces
  alias Ide.Debugger.SessionDefaults
  alias Ide.Debugger.SimulatorSettings, as: DebuggerSimulatorSettings
  alias Ide.Debugger.SimulatorSurfaceSettings
  alias Ide.Debugger.Types
  @type launch_bundle :: %{
          watch_profile_id: String.t(),
          launch_context: Types.launch_context(),
          simulator_settings: Types.simulator_settings(),
          launch_reason: String.t()
        }

  @spec launch_bundle_from_state(Types.runtime_state()) :: launch_bundle()
  def launch_bundle_from_state(state) when is_map(state) do
    watch_profile_id = RuntimeSurfaces.parse_watch_profile_id(Map.get(state, :watch_profile_id))

    launch_reason =
      state
      |> Map.get(:launch_context, %{})
      |> Map.get("launch_reason")
      |> RuntimeSurfaces.parse_launch_reason()

    build_launch_bundle(watch_profile_id, launch_reason, Map.get(state, :simulator_settings))
  end

  @spec launch_bundle(String.t() | nil, String.t(), Types.simulator_settings() | nil) :: launch_bundle()
  def launch_bundle(requested_profile_id, launch_reason, simulator_settings \\ nil) do
    watch_profile_id = RuntimeSurfaces.parse_watch_profile_id(requested_profile_id)

    build_launch_bundle(
      watch_profile_id,
      RuntimeSurfaces.parse_launch_reason(launch_reason),
      simulator_settings
    )
  end

  @spec start_session(Types.runtime_state(), String.t(), launch_bundle()) :: Types.runtime_state()
  def start_session(state, project_slug, %{launch_context: launch_context} = bundle)
      when is_map(state) and is_binary(project_slug) and is_map(bundle) do
    %{
      state
      | running: true,
        revision: nil,
        watch_profile_id: bundle.watch_profile_id,
        launch_context: bundle.launch_context,
        simulator_settings: bundle.simulator_settings,
        storage: Map.get(state, :storage, %{}),
        watch: RuntimeSurfaces.default_watch(launch_context),
        companion: RuntimeSurfaces.default_companion(),
        phone: RuntimeSurfaces.default_phone(),
        auto_tick: SessionDefaults.default_auto_tick(),
        disabled_subscriptions: [],
        events: [],
        debugger_timeline: [],
        debugger_seq: 0,
        seq: 0,
        app_message_queues: AppMessageQueue.empty()
    }
    |> Map.put(:last_execution_error, nil)
    |> BootstrapInit.clear_session_bootstrap_flags()
    |> CompanionConfiguration.attach_to_state(project_slug)
    |> ProjectResourceIndices.attach_all(project_slug)
    |> RuntimeSurfaces.apply_launch_context(bundle.launch_reason)
    |> SimulatorSurfaceSettings.apply_to_state()
  end

  @spec reset_session(Types.runtime_state(), String.t(), launch_bundle()) :: Types.runtime_state()
  def reset_session(state, project_slug, %{launch_context: launch_context} = bundle)
      when is_map(state) and is_binary(project_slug) and is_map(bundle) do
    %{
      state
      | revision: nil,
        watch_profile_id: bundle.watch_profile_id,
        launch_context: bundle.launch_context,
        simulator_settings: bundle.simulator_settings,
        watch: RuntimeSurfaces.default_watch(launch_context),
        companion: RuntimeSurfaces.default_companion(),
        phone: RuntimeSurfaces.default_phone(),
        debugger_timeline: [],
        debugger_seq: 0,
        app_message_queues: AppMessageQueue.empty()
    }
    |> Map.put(:last_execution_error, nil)
    |> BootstrapInit.clear_session_bootstrap_flags()
    |> CompanionConfiguration.attach_to_state(project_slug)
    |> SimulatorSurfaceSettings.apply_to_state()
  end

  @spec build_launch_bundle(String.t(), String.t(), Types.simulator_settings() | nil) :: launch_bundle()
  defp build_launch_bundle(watch_profile_id, launch_reason, simulator_settings) do
    %{
      watch_profile_id: watch_profile_id,
      launch_context: RuntimeSurfaces.launch_context_for(watch_profile_id, launch_reason),
      simulator_settings: DebuggerSimulatorSettings.normalize(simulator_settings || %{}),
      launch_reason: launch_reason
    }
  end
end
