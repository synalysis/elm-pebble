defmodule Ide.Debugger.SessionDefaults do
  @moduledoc false

  alias Ide.Debugger.AppMessageQueue
  alias Ide.Debugger.RuntimeSurfaces
  alias Ide.Debugger.SimulatorSettings, as: DebuggerSimulatorSettings
  alias Ide.Debugger.SimulatorSurfaceSettings
  alias Ide.Debugger.Types
  alias Ide.Projects
  alias Ide.WatchModels

  @spec default_auto_tick() :: Types.AutoTick.t()
  def default_auto_tick do
    %{enabled: false, interval_ms: nil, target: "all", targets: [], count: 1, worker_pid: nil}
  end

  @spec human_slug_from_session_key(String.t()) :: String.t()
  def human_slug_from_session_key(session_key) do
    case Projects.parse_scope_key(session_key) do
      {:ok, _, slug} -> slug
      :error -> session_key
    end
  end

  @spec session_key_from_state(map()) :: String.t() | nil
  def session_key_from_state(%{scope_key: key}) when is_binary(key), do: key
  def session_key_from_state(%{project_slug: slug}) when is_binary(slug), do: slug
  def session_key_from_state(_), do: nil

  @spec parse_watch_profile_id(Types.wire_input()) :: String.t() | nil
  def parse_watch_profile_id(value) when is_binary(value), do: RuntimeSurfaces.parse_watch_profile_id(value)
  def parse_watch_profile_id(_), do: nil

  @spec persisted_watch_profile_id(String.t()) :: String.t() | nil
  def persisted_watch_profile_id(session_key) when is_binary(session_key) do
    try do
      with %{debugger_settings: settings} when is_map(settings) <-
             Projects.get_project_by_scope_key(session_key),
           profile_id when is_binary(profile_id) <- Map.get(settings, "watch_profile_id") do
        parse_watch_profile_id(profile_id)
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

  @spec persisted_simulator_settings(String.t()) :: Types.simulator_settings()
  def persisted_simulator_settings(session_key) when is_binary(session_key) do
    try do
      with %{debugger_settings: settings} when is_map(settings) <-
             Projects.get_project_by_scope_key(session_key),
           simulator when is_map(simulator) <- Map.get(settings, "simulator") do
        DebuggerSimulatorSettings.normalize(simulator)
      else
        _ -> DebuggerSimulatorSettings.default()
      end
    rescue
      _ -> DebuggerSimulatorSettings.default()
    end
  end

  @spec default_state(String.t()) :: Types.runtime_state()
  def default_state(session_key) when is_binary(session_key) do
    project_slug = human_slug_from_session_key(session_key)

    watch_profile_id =
      persisted_watch_profile_id(session_key) || WatchModels.default_id()

    launch_context = RuntimeSurfaces.launch_context_for(watch_profile_id, "LaunchUser")
    simulator_settings = persisted_simulator_settings(session_key)

    %{
      scope_key: session_key,
      project_slug: project_slug,
      running: false,
      revision: nil,
      watch_profile_id: watch_profile_id,
      launch_context: launch_context,
      simulator_settings: simulator_settings,
      watch: RuntimeSurfaces.default_watch(launch_context),
      companion: RuntimeSurfaces.default_companion(),
      phone: RuntimeSurfaces.default_phone(),
      storage: %{},
      auto_tick: default_auto_tick(),
      disabled_subscriptions: [],
      events: [],
      debugger_timeline: [],
      debugger_seq: 0,
      seq: 0,
      app_message_queues: AppMessageQueue.empty()
    }
    |> SimulatorSurfaceSettings.apply_to_state()
  end

  @spec ensure_phone_state(map()) :: Types.runtime_state()
  def ensure_phone_state(state) when is_map(state) do
    watch_profile_id = RuntimeSurfaces.parse_watch_profile_id(Map.get(state, :watch_profile_id))

    launch_reason =
      state
      |> Map.get(:launch_context, %{})
      |> Map.get("launch_reason")
      |> RuntimeSurfaces.parse_launch_reason()

    launch_context = RuntimeSurfaces.launch_context_for(watch_profile_id, launch_reason)

    state =
      if is_map(Map.get(state, :phone)) do
        state
      else
        Map.put(state, :phone, RuntimeSurfaces.default_phone())
      end

    state =
      if is_map(Map.get(state, :watch)) do
        state
      else
        Map.put(state, :watch, RuntimeSurfaces.default_watch(launch_context))
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
    |> RuntimeSurfaces.ensure_protocol_runtime_model(:companion)
    |> RuntimeSurfaces.ensure_protocol_runtime_model(:phone)
    |> Map.put(:watch_profile_id, watch_profile_id)
    |> Map.put(:launch_context, launch_context)
    |> Map.update(
      :simulator_settings,
      DebuggerSimulatorSettings.default(),
      &DebuggerSimulatorSettings.normalize/1
    )
    |> RuntimeSurfaces.apply_launch_context_to_watch()
    |> SimulatorSurfaceSettings.apply_to_state()
  end
end
