defmodule Ide.Debugger.GeolocationResponses do
  @moduledoc false

  alias Ide.Debugger.DeviceDataResponses
  alias Ide.Debugger.Geolocation
  alias Ide.Debugger.IntrospectAccess
  alias Ide.Debugger.RuntimeModelMessages
  alias Ide.Debugger.SubscriptionResponses
  alias Ide.Debugger.Types

  @type apply_ctx :: %{
          required(:introspect_for) => (Types.runtime_state(), Types.surface_target() ->
                                          Types.elm_introspect()),
          required(:append_event) => (Types.runtime_state(),
                                      String.t(),
                                      Types.debugger_timeline_payload() ->
                                        Types.runtime_state()),
          required(:apply_step_once) => (Types.runtime_state(),
                                         Types.surface_target(),
                                         String.t(),
                                         Types.subscription_payload(),
                                         String.t(),
                                         String.t() ->
                                           Types.runtime_state()),
          required(:source_root_for_target) => (Types.surface_target() -> String.t())
        }

  @spec apply_simulator_settings(Types.runtime_state(), apply_ctx()) :: Types.runtime_state()
  def apply_simulator_settings(state, ctx) when is_map(state) and is_map(ctx) do
    state
    |> apply_subscription_response(:companion, "simulator_settings", ctx)
    |> apply_subscription_response(:watch, "simulator_settings", ctx)
  end

  @spec apply_after_step(
          Types.runtime_state(),
          Types.surface_target(),
          String.t(),
          Types.app_model(),
          String.t(),
          apply_ctx()
        ) :: Types.runtime_state()
  def apply_after_step(state, _target, _message, _model, source, _ctx)
      when source in ["geolocation", "init_geolocation"],
      do: state

  def apply_after_step(state, target, message, _model, _message_source, ctx)
      when is_map(state) and target in [:watch, :companion, :phone] and is_binary(message) and
             is_map(ctx) do
    ei = ctx.introspect_for.(state, target)
    current_ctor = RuntimeModelMessages.wire_constructor(message)
    callback = Geolocation.subscription_callback_from_introspect(ei)

    with true <- is_binary(callback) and callback != "",
         true <- current_ctor != callback,
         true <- update_branch_requests_command?(ei, current_ctor) do
      location = Geolocation.location_from_state(state)
      target_name = ctx.source_root_for_target.(target)

      state
      |> ctx.append_event.(
        "debugger.geolocation",
        Ide.Debugger.Types.GeolocationEventPayload.from_response(
          target_name,
          callback,
          location
        )
      )
      |> apply_subscription_ok(target, callback, location, "geolocation", "geolocation", ctx)
    else
      _ -> state
    end
  end

  def apply_after_step(state, _target, _message, _model, _message_source, _ctx), do: state

  @spec apply_subscription_response(
          Types.runtime_state(),
          Types.surface_target(),
          String.t(),
          apply_ctx()
        ) :: Types.runtime_state()
  def apply_subscription_response(state, target, source, ctx)
      when is_map(state) and target in [:watch, :companion, :phone] and is_binary(source) and
             is_map(ctx) do
    ei = ctx.introspect_for.(state, target)
    callback = Geolocation.subscription_callback_from_introspect(ei)

    if is_binary(callback) and callback != "" do
      location = Geolocation.location_from_state(state)
      target_name = ctx.source_root_for_target.(target)

      state
      |> ctx.append_event.(
        "debugger.geolocation",
        Ide.Debugger.Types.GeolocationEventPayload.from_response(
          target_name,
          callback,
          location
        )
      )
      |> apply_subscription_ok(target, callback, location, source, "geolocation", ctx)
    else
      state
    end
  end

  def apply_subscription_response(state, _target, _source, _ctx), do: state

  defp apply_subscription_ok(state, target, callback, payload, source, trigger, ctx)
       when is_map(state) do
    SubscriptionResponses.apply_ok(
      state,
      target,
      callback,
      payload,
      source,
      trigger,
      %{apply_step_once: ctx.apply_step_once}
    )
  end

  @spec update_branch_requests_command?(Types.elm_introspect(), String.t() | nil) :: boolean()
  def update_branch_requests_command?(ei, current_ctor)
      when is_map(ei) and is_binary(current_ctor) and current_ctor != "" do
    ei
    |> IntrospectAccess.cmd_calls("update_cmd_calls")
    |> DeviceDataResponses.filter_update_cmd_calls(current_ctor)
    |> Geolocation.update_branch_requests_command?(ei)
  end

  def update_branch_requests_command?(_ei, _current_ctor), do: false
end
