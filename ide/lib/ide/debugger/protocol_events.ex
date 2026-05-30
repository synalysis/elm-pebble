defmodule Ide.Debugger.ProtocolEvents do
  @moduledoc false

  alias Ide.Debugger.ProtocolResolutionCtx
  alias Ide.Debugger.Types

  @type resolution_ctx :: ProtocolResolutionCtx.t()

  @type ctx :: %{
          required(:cmd_calls_for_message) =>
            (Types.runtime_state(), Types.surface_target(), String.t() -> [Types.cmd_call()]),
          required(:simulator_settings_from_state) =>
            (Types.runtime_state() -> Types.simulator_settings()),
          required(:session_key_from_state) => (Types.runtime_state() -> String.t() | nil),
          required(:surface_app_model) =>
            (Types.runtime_state(), Types.surface_target() -> Types.app_model())
        }

  alias Ide.Debugger.ProtocolEvents.CmdCall
  alias Ide.Debugger.ProtocolEvents.Subscription

  def events_from_cmd_call(state, target_surface, cmd_call, model, message_value, ctx) do
    CmdCall.events_from_cmd_call(state, target_surface, cmd_call, model, message_value, ctx)
  end

  def events_for_model_commands(state, model, target, message, message_value, ctx) do
    CmdCall.events_for_model_commands(state, model, target, message, message_value, ctx)
  end

  def normalize_subscription_message_value(state, recipient, message_value, events_ctx) do
    Subscription.normalize_subscription_message_value(state, recipient, message_value, events_ctx)
  end

  def normalize_subscription_message_value(state, recipient, message_value, app_model, events_ctx) do
    Subscription.normalize_subscription_message_value(state, recipient, message_value, app_model, events_ctx)
  end

  defdelegate project_schema(state, events_ctx), to: CmdCall
  defdelegate weather_condition_from_settings(settings), to: CmdCall
  defdelegate normalize_from_schema(protocol_events, state, events_ctx), to: CmdCall
  defdelegate parenthesize_elm_arg(value), to: Subscription
  defdelegate inbound_display_message(message, message_value), to: Subscription

  @spec tx_rx_events(String.t(), String.t(), String.t() | nil, String.t(), Types.protocol_message_wire_value()) ::
          [Types.protocol_timeline_event()]
  def tx_rx_events(from, to, message, trigger, message_value) do
    Ide.Debugger.Types.ProtocolTxRxPayload.tx_rx_events(
      from,
      to,
      message,
      trigger,
      message_value
    )
  end

  @spec enrich([Types.protocol_event()], String.t(), String.t()) :: [Types.protocol_event()]
  def enrich(protocol_events, trigger, message_source)
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
end
