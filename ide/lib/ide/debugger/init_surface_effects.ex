defmodule Ide.Debugger.InitSurfaceEffects do
  @moduledoc false

  alias Ide.Debugger.CmdCall
  alias Ide.Debugger.CompanionBridge.Runtime, as: CompanionBridgeRuntime
  alias Ide.Debugger.DeviceData
  alias Ide.Debugger.DeviceDataHints
  alias Ide.Debugger.DeviceRequest
  alias Ide.Debugger.Geolocation
  alias Ide.Debugger.IntrospectAccess
  alias Ide.Debugger.ProtocolEvents
  alias Ide.Debugger.ProtocolRx
  alias Ide.Debugger.Surface
  alias Ide.Debugger.Types

  @type ctx :: %{
          required(:append_event) => (Types.runtime_state(), String.t(), map() -> Types.runtime_state()),
          required(:apply_step_once) =>
            (Types.runtime_state(), Types.surface_target(), String.t(), Types.subscription_payload() | map() | nil,
             String.t(), String.t() -> Types.runtime_state()),
          required(:apply_device_data_followups) =>
            (Types.runtime_state(), Types.surface_target(), String.t(), map(), String.t() ->
               Types.runtime_state()),
          required(:apply_subscription_ok_response) =>
            (Types.runtime_state(), Types.surface_target(), String.t(), map(), String.t(), String.t() ->
               Types.runtime_state()),
          required(:protocol_events_ctx) => (-> ProtocolEvents.ctx()),
          required(:protocol_rx_ctx) => (-> ProtocolRx.ctx()),
          required(:companion_bridge_ctx) => (-> CompanionBridgeRuntime.ctx()),
          required(:source_root_for_target) => (Types.surface_target() -> String.t())
        }

  @spec apply_all(Types.runtime_state(), Types.surface_target(), ctx()) :: Types.runtime_state()
  def apply_all(state, target, ctx)
      when is_map(state) and target in [:watch, :companion, :phone] and is_map(ctx) do
    state
    |> apply_device_data_responses(target, ctx)
    |> apply_protocol_events(target, ctx)
    |> apply_geolocation_response(target, ctx)
    |> apply_companion_bridge_commands(target, ctx)
  end

  def apply_all(state, _target, _ctx), do: state

  @spec apply_device_data_responses(Types.runtime_state(), Types.surface_target(), ctx()) ::
          Types.runtime_state()
  def apply_device_data_responses(state, target, ctx)
      when is_map(state) and target in [:watch, :companion, :phone] and is_map(ctx) do
    surface = Surface.from_state(state, target)
    ei = Surface.introspect(surface)
    model = Surface.app_model(surface)

    if is_map(ei) do
      ei
      |> IntrospectAccess.cmd_calls("init_cmd_calls")
      |> CmdCall.expand_helpers(ei)
      |> Enum.flat_map(&DeviceRequest.from_cmd_call/1)
      |> Enum.uniq_by(fn req -> {req.kind, req.response_message} end)
      |> Enum.map(&DeviceData.finalize_request(&1, model, nil))
      |> Enum.reduce(state, fn req, acc ->
        target_name = ctx.source_root_for_target.(target)

        acc
        |> DeviceDataHints.apply_to_state(target, req)
        |> ctx.append_event.(
          "debugger.device_data",
          Ide.Debugger.Types.DeviceDataEventPayload.from_request(target_name, req)
        )
        |> ctx.apply_step_once.(
          target,
          DeviceData.response_message(req),
          DeviceData.response_wire_value(req),
          "init_device_data",
          "device_data"
        )
        |> apply_init_device_data_followups(target, req, ctx)
        |> DeviceDataHints.apply_to_state(target, req)
      end)
    else
      state
    end
  end

  def apply_device_data_responses(state, _target, _ctx), do: state

  @spec apply_init_device_data_followups(
          Types.runtime_state(),
          Types.surface_target(),
          Types.device_request(),
          ctx()
        ) :: Types.runtime_state()
  defp apply_init_device_data_followups(state, target, req, ctx) when is_map(state) and is_map(req) and is_map(ctx) do
    message = DeviceData.response_message(req)

    if is_binary(message) and message != "" do
      surface = Surface.from_state(state, target)
      model = Surface.app_model(surface)

      ctx.apply_device_data_followups.(state, target, message, model, "init_device_data")
    else
      state
    end
  end

  @spec apply_protocol_events(Types.runtime_state(), Types.surface_target(), ctx()) ::
          Types.runtime_state()
  def apply_protocol_events(state, target, ctx)
      when is_map(state) and target in [:watch, :companion, :phone] and is_map(ctx) do
    surface = Surface.from_state(state, target)
    ei = Surface.introspect(surface)
    model = Surface.app_model(surface)

    if is_map(ei) do
      ei
      |> IntrospectAccess.cmd_calls("init_cmd_calls")
      |> Enum.flat_map(
        &ProtocolEvents.events_from_cmd_call(state, target, &1, model, nil, ctx.protocol_events_ctx.())
      )
      |> Enum.reduce(state, fn event, acc ->
        case event.type do
          "debugger.protocol_tx" ->
            ctx.append_event.(acc, event.type, event.payload)

          "debugger.protocol_rx" ->
            ProtocolRx.apply_state_effects(acc, [event], ctx.protocol_rx_ctx.())

          _ ->
            ctx.append_event.(acc, event.type, event.payload)
        end
      end)
    else
      state
    end
  end

  def apply_protocol_events(state, _target, _ctx), do: state

  @spec apply_geolocation_response(Types.runtime_state(), Types.surface_target(), ctx()) ::
          Types.runtime_state()
  def apply_geolocation_response(state, target, ctx)
      when is_map(state) and target in [:watch, :companion, :phone] and is_map(ctx) do
    ei = state |> Surface.from_state(target) |> Surface.introspect()

    with true <- Geolocation.init_requested_from_introspect?(ei),
         callback when is_binary(callback) and callback != "" <-
           Geolocation.subscription_callback_from_introspect(ei) do
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

  def apply_geolocation_response(state, _target, _ctx), do: state

  @spec apply_companion_bridge_commands(Types.runtime_state(), Types.surface_target(), ctx()) ::
          Types.runtime_state()
  def apply_companion_bridge_commands(state, target, ctx)
      when target in [:companion, :phone] and is_map(state) and is_map(ctx) do
    CompanionBridgeRuntime.apply_init_commands(state, target, ctx.companion_bridge_ctx.())
  end

  def apply_companion_bridge_commands(state, _target, _ctx), do: state
end
