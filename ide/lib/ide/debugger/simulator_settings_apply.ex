defmodule Ide.Debugger.SimulatorSettingsApply do
  @moduledoc false

  alias Ide.Debugger.CompanionBridgeEffects
  alias Ide.Debugger.GeolocationResponses
  alias Ide.Debugger.InitSurfaceEffects
  alias Ide.Debugger.RuntimeContexts
  alias Ide.Debugger.RuntimeFollowups
  alias Ide.Debugger.SimulatorSurfaceSettings
  alias Ide.Debugger.SimulatorWatchDelivery
  alias Ide.Debugger.Types

  @type append_event_fn ::
          (Types.runtime_state(), String.t(), Types.debugger_timeline_payload() ->
             Types.runtime_state())

  @type host :: %{
          required(:append_event) => append_event_fn(),
          required(:contexts) => (-> RuntimeContexts.t())
        }

  @spec apply(
          Types.runtime_state(),
          Types.simulator_settings(),
          Types.simulator_settings(),
          host()
        ) :: Types.runtime_state()
  def apply(state, settings, previous_settings, host)
      when is_map(state) and is_map(settings) and is_map(host) do
    ctx = host.contexts.()

    state
    |> Map.put(:simulator_settings, settings)
    |> SimulatorSurfaceSettings.apply_to_state()
    |> host.append_event.(
      "debugger.simulator_settings_set",
      Types.SimulatorSettingsSetEventPayload.from_settings(settings)
    )
    |> GeolocationResponses.apply_simulator_settings(ctx.geolocation)
    |> CompanionBridgeEffects.apply_simulator_settings_responses(ctx.companion_bridge)
    |> RuntimeFollowups.reapply_tracked_http_commands(ctx.runtime_followups)
    |> InitSurfaceEffects.apply_companion_bridge_commands(:companion, ctx.init_surface_effects)
    |> SimulatorWatchDelivery.inject_unobstructed_triggers(
      previous_settings,
      settings,
      ctx.simulator_watch_delivery
    )
    |> SimulatorWatchDelivery.inject_weather_on_settings_change(
      previous_settings,
      settings,
      ctx.simulator_watch_delivery
    )
    |> SimulatorWatchDelivery.deliver_position(ctx.simulator_watch_delivery)
  end
end
