defmodule Ide.Debugger.Types.ProtocolTxRxPayload do
  @moduledoc """
  Shared payload for paired `debugger.protocol_tx` and `debugger.protocol_rx` events.
  """

  alias Ide.Debugger.Types

  @type t :: %{
          optional(:from) => String.t(),
          optional(:to) => String.t(),
          optional(:message) => String.t(),
          optional(:message_value) => Types.subscription_payload() | nil,
          optional(:trigger) => String.t(),
          optional(:message_source) => String.t(),
          optional(String.t()) => Types.wire_input()
        }

  @typedoc "JSON-shaped map when atom-key `t/0` is unavailable at the wire boundary."
  @type wire_map :: t() | Types.wire_map()

  @spec from_reload(String.t(), String.t()) :: t()
  def from_reload(revision, source_root) when is_binary(revision) and is_binary(source_root) do
    case source_root do
      "phone" ->
        %{from: "phone", to: "companion", message: "PhoneReloaded:#{revision}"}

      "protocol" ->
        %{from: "watch", to: "companion", message: "ProtocolReloaded:#{revision}"}

      _ ->
        %{from: "watch", to: "companion", message: "Reloaded:#{revision}"}
    end
  end

  @type protocol_event :: %{required(:type) => String.t(), required(:payload) => t()}

  @spec from_tx_rx(
          String.t(),
          String.t(),
          String.t(),
          String.t(),
          Types.subscription_payload() | nil
        ) :: t()
  def from_tx_rx(from, to, message, trigger, message_value)
      when is_binary(from) and is_binary(to) and is_binary(message) and is_binary(trigger) do
    %{
      from: from,
      to: to,
      message: message,
      message_value: message_value,
      trigger: trigger,
      message_source: trigger
    }
  end

  @spec tx_rx_events(
          String.t(),
          String.t(),
          String.t(),
          String.t(),
          Types.subscription_payload() | nil
        ) :: [protocol_event()]
  def tx_rx_events(from, to, message, trigger, message_value)
      when is_binary(from) and is_binary(to) and is_binary(message) and message != "" and
             is_binary(trigger) do
    payload = from_tx_rx(from, to, message, trigger, message_value)

    [
      %{type: "debugger.protocol_tx", payload: payload},
      %{type: "debugger.protocol_rx", payload: payload}
    ]
  end

  def tx_rx_events(_from, _to, _message, _trigger, _message_value), do: []
end
