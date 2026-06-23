defmodule Ide.Debugger.WatchProfileApply do
  @moduledoc false

  alias Ide.Debugger.RuntimeExecutorConfig
  alias Ide.Debugger.RuntimeSurfaces
  alias Ide.Debugger.SimulatorSurfaceSettings
  alias Ide.Debugger.SimulatorWatchDelivery
  alias Ide.Debugger.Types

  @type append_event_fn ::
          (Types.runtime_state(), String.t(), Types.debugger_timeline_payload() ->
             Types.runtime_state())

  @type ensure_phone_fn :: (Types.runtime_state() -> Types.runtime_state())

  @type host :: %{
          required(:append_event) => append_event_fn(),
          required(:ensure_phone_state) => ensure_phone_fn(),
          optional(:contexts) => (-> map())
        }

  @spec apply(Types.runtime_state(), Types.session_attrs(), host()) :: Types.runtime_state()
  def apply(state, attrs, host) when is_map(state) and is_map(attrs) and is_map(host) do
    profile_id =
      RuntimeSurfaces.parse_watch_profile_id(
        Map.get(attrs, :watch_profile_id) || Map.get(attrs, "watch_profile_id")
      )

    launch_reason =
      RuntimeSurfaces.parse_launch_reason(
        Map.get(attrs, :launch_reason) || Map.get(attrs, "launch_reason")
      )

    state
    |> host.ensure_phone_state.()
    |> Map.put(:watch_profile_id, profile_id)
    |> RuntimeSurfaces.apply_launch_context(launch_reason)
    |> maybe_inject_screen_change(host)
    |> SimulatorSurfaceSettings.apply_to_state()
    |> RuntimeExecutorConfig.refresh_for_target(:watch)
    |> host.append_event.(
      "debugger.watch_profile_set",
      Types.WatchProfileSetEventPayload.from_profile(profile_id, launch_reason)
    )
  end

  defp maybe_inject_screen_change(state, host) do
    case Map.get(host, :contexts) do
      fun when is_function(fun, 0) ->
        ctx = fun.() |> Map.fetch!(:simulator_watch_delivery)
        SimulatorWatchDelivery.inject_screen_change(state, ctx)

      _ ->
        state
    end
  end
end
