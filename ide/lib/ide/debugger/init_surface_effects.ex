defmodule Ide.Debugger.InitSurfaceEffects do
  @moduledoc false

  alias Ide.Debugger.CompanionBridge.Runtime, as: CompanionBridgeRuntime
  alias Ide.Debugger.Geolocation
  alias Ide.Debugger.ProtocolEvents
  alias Ide.Debugger.ProtocolRx
  alias Ide.Debugger.Surface
  alias Ide.Debugger.Types

  @type ctx :: %{
          required(:append_event) => (Types.runtime_state(),
                                      String.t(),
                                      Types.debugger_timeline_payload() ->
                                        Types.runtime_state()),
          required(:apply_step_once) => (Types.runtime_state(),
                                         Types.surface_target(),
                                         String.t(),
                                         Types.subscription_payload()
                                         | nil,
                                         String.t(),
                                         String.t() ->
                                           Types.runtime_state()),
          required(:apply_subscription_ok_response) => (Types.runtime_state(),
                                                        Types.surface_target(),
                                                        String.t(),
                                                        Types.subscription_payload(),
                                                        String.t(),
                                                        String.t() ->
                                                          Types.runtime_state()),
          required(:protocol_events_ctx) => (-> ProtocolEvents.ctx()),
          required(:protocol_rx_ctx) => (-> ProtocolRx.ctx()),
          required(:companion_bridge_ctx) => (-> CompanionBridgeRuntime.ctx()),
          required(:source_root_for_target) => (Types.surface_target() -> String.t()),
          optional(:introspect_for) =>
            (Types.runtime_state(), Types.surface_target() -> Types.elm_introspect())
        }

  @spec apply_all(Types.runtime_state(), Types.surface_target(), ctx()) :: Types.runtime_state()
  def apply_all(state, target, ctx)
      when is_map(state) and target in [:watch, :companion, :phone] and is_map(ctx) do
    state
    |> apply_protocol_events(target, ctx)
    |> apply_geolocation_response(target, ctx)
    |> apply_companion_bridge_commands(target, ctx)
  end

  def apply_all(state, _target, _ctx), do: state

  @spec apply_protocol_events(Types.runtime_state(), Types.surface_target(), ctx()) ::
          Types.runtime_state()
  def apply_protocol_events(state, _target, _ctx), do: state

  @spec apply_geolocation_response(Types.runtime_state(), Types.surface_target(), ctx()) ::
          Types.runtime_state()
  def apply_geolocation_response(state, target, ctx)
       when is_map(state) and target in [:watch, :companion, :phone] and is_map(ctx) do
    if Geolocation.runtime_geolocation_applied?(state) do
      state
    else
      ei = state |> Surface.from_state(target) |> Surface.introspect()

      with true <- Geolocation.init_requested_for_surface?(state, target, ei),
           callback when is_binary(callback) and callback != "" <-
             Geolocation.subscription_callback_for_surface(state, target, ei) do
        location = Geolocation.location_from_state(state)

        state
        |> ctx.append_event.(
          "debugger.geolocation",
          Ide.Debugger.Types.GeolocationEventPayload.from_response(
            ctx.source_root_for_target.(target),
            callback,
            location
          )
        )
        |> ctx.apply_subscription_ok_response.(
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
  end

  def apply_geolocation_response(state, _target, _ctx), do: state

  @spec apply_companion_bridge_commands(Types.runtime_state(), Types.surface_target(), ctx()) ::
          Types.runtime_state()
  def apply_companion_bridge_commands(state, target, ctx)
       when target in [:companion, :phone] and is_map(state) and is_map(ctx) do
    bridge_ctx = ctx.companion_bridge_ctx.()

    state
    |> CompanionBridgeRuntime.apply_init_commands(target, bridge_ctx)
    |> CompanionBridgeRuntime.flush_deferred_steps(bridge_ctx)
    |> ProtocolRx.flush_inline_protocol_deliveries(ctx.protocol_rx_ctx.())
  end

  def apply_companion_bridge_commands(state, _target, _ctx), do: state
end
