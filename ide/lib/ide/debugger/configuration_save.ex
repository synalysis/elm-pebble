defmodule Ide.Debugger.ConfigurationSave do
  @moduledoc false

  alias Ide.Debugger.CompanionBridge
  alias Ide.Debugger.CompanionBridge.Runtime, as: CompanionBridgeRuntime
  alias Ide.Debugger.ConfigurationProtocol
  alias Ide.Debugger.ProtocolRx
  alias Ide.Debugger.SubscriptionResponses
  alias Ide.Debugger.Types

  @type bridge_ctx :: %{
          optional(atom()) => term()
        }

  @spec closed_bridge_event(Types.companion_configuration_values()) :: Types.wire_map()
  def closed_bridge_event(encoded_values) when is_map(encoded_values) do
    %{
      "event" => "configuration.closed",
      "payload" => %{
        "response" => Jason.encode!(encoded_values)
      }
    }
  end

  def closed_bridge_event(_encoded_values),
    do: %{"event" => "configuration.closed", "payload" => %{}}

  @spec message_payload(
          Types.runtime_state(),
          Types.companion_configuration_values(),
          Types.wire_map(),
          bridge_ctx()
        ) :: {String.t(), Types.subscription_payload()}
  def message_payload(state, encoded_values, bridge_event, bridge_ctx)
      when is_map(state) and is_map(encoded_values) and is_map(bridge_event) and
             is_map(bridge_ctx) do
    case subscription_callback(state, bridge_ctx) do
      callback when is_binary(callback) and callback != "" ->
        {callback, SubscriptionResponses.ok_wire_value(callback, encoded_values)}

      _ ->
        {"FromBridge", %{"ctor" => "FromBridge", "args" => [bridge_event]}}
    end
  end

  def message_payload(_state, _encoded_values, bridge_event, _bridge_ctx),
    do: {"FromBridge", %{"ctor" => "FromBridge", "args" => [bridge_event]}}

  @spec maybe_apply_protocol_messages(
          Types.runtime_state(),
          Types.companion_configuration(),
          Types.companion_configuration_values(),
          non_neg_integer(),
          ProtocolRx.ctx()
        ) :: Types.runtime_state()
  def maybe_apply_protocol_messages(state, configuration, values, seq_before, rx_ctx)
      when is_map(state) and is_map(configuration) and is_map(values) and is_integer(seq_before) and
             is_map(rx_ctx) do
    if ConfigurationProtocol.events_applied?(state, seq_before) do
      state
    else
      ConfigurationProtocol.apply_messages(state, configuration, values, rx_ctx)
    end
  end

  def maybe_apply_protocol_messages(state, _configuration, _values, _seq_before, _rx_ctx),
    do: state

  @spec subscription_callback(Types.runtime_state(), bridge_ctx()) :: String.t() | nil
  def subscription_callback(state, %{introspect: introspect} = bridge_ctx)
      when is_map(state) and is_function(introspect) and is_map(bridge_ctx) do
    contract = CompanionBridge.configuration_contract()

    Enum.find_value([:companion, :phone], fn target ->
      CompanionBridgeRuntime.subscription_callback_from_state(
        state,
        target,
        contract,
        bridge_ctx
      )
    end)
  end

  def subscription_callback(_state, _bridge_ctx), do: nil
end
