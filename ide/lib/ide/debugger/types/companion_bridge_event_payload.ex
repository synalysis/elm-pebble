defmodule Ide.Debugger.Types.CompanionBridgeEventPayload do
  @moduledoc "Payload for `debugger.companion_bridge` simulator API responses."

  alias Ide.Debugger.Types

  @type result_label :: String.t() | Types.protocol_ctor_value()

  @type t :: %{
          optional(:target) => String.t(),
          optional(:api) => String.t(),
          optional(:op) => String.t(),
          optional(:response_message) => String.t() | nil,
          optional(:response_value) => Types.companion_bridge_payload(),
          optional(:result) => result_label(),
          optional(atom()) => Types.wire_input(),
          optional(String.t()) => Types.wire_input()
        }

  @spec from_response(
          String.t(),
          String.t(),
          String.t() | nil,
          String.t() | nil,
          Types.companion_bridge_payload(),
          result_label() | nil
        ) :: t()
  def from_response(target, api, op, response_message, response_value, result)
      when is_binary(target) and is_binary(api) do
    %{
      target: target,
      api: api,
      op: op,
      response_message: response_message,
      response_value: response_value,
      result: result
    }
  end

  @spec from_subscription(
          String.t(),
          String.t(),
          String.t(),
          Types.companion_bridge_payload(),
          result_label() | nil
        ) :: t()
  def from_subscription(target, api, response_message, response_value, result \\ "Ok") do
    from_response(target, api, "subscribe", response_message, response_value, result)
  end
end
