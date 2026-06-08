defmodule Ide.Debugger.SessionStartReset do
  @moduledoc false

  alias Ide.Debugger.AutoTickWorkers
  alias Ide.Debugger.RuntimeSurfaces
  alias Ide.Debugger.SessionDefaults
  alias Ide.Debugger.SessionLifecycle
  alias Ide.Debugger.Types

  @type append_event_fn ::
          (Types.runtime_state(), String.t(), Types.debugger_timeline_payload() ->
             Types.runtime_state())

  @type ensure_phone_fn :: (Types.runtime_state() -> Types.runtime_state())

  @type host :: %{
          required(:append_event) => append_event_fn(),
          required(:ensure_phone_state) => ensure_phone_fn()
        }

  @spec start(Types.runtime_state(), String.t(), Types.session_attrs(), host()) ::
          Types.runtime_state()
  def start(state, project_slug, attrs, host)
      when is_map(state) and is_binary(project_slug) and is_map(attrs) and is_map(host) do
    requested_profile_id =
      SessionDefaults.parse_watch_profile_id(
        Map.get(attrs, :watch_profile_id) || Map.get(attrs, "watch_profile_id")
      )

    launch_reason =
      RuntimeSurfaces.parse_launch_reason(
        Map.get(attrs, :launch_reason) || Map.get(attrs, "launch_reason")
      )

    state = state |> host.ensure_phone_state.() |> AutoTickWorkers.stop_worker()

    bundle =
      SessionLifecycle.launch_bundle(
        requested_profile_id || Map.get(state, :watch_profile_id),
        launch_reason,
        Map.get(state, :simulator_settings)
      )

    state
    |> SessionLifecycle.start_session(project_slug, bundle)
    |> host.append_event.(
      "debugger.start",
      Types.StartEventPayload.from_session(launch_reason, bundle.watch_profile_id)
    )
  end

  @spec reset(Types.runtime_state(), String.t(), host()) :: Types.runtime_state()
  def reset(state, project_slug, host)
      when is_map(state) and is_binary(project_slug) and is_map(host) do
    bundle = SessionLifecycle.launch_bundle_from_state(state)

    state
    |> SessionLifecycle.reset_session(project_slug, bundle)
    |> host.append_event.("debugger.reset", Types.ResetEventPayload.empty())
  end
end
