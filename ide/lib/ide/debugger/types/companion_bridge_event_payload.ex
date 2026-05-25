defmodule Ide.Debugger.Types.CompanionBridgeEventPayload do
  @moduledoc "Payload for `debugger.companion_bridge` simulator API responses."

  @type t :: %{
          optional(:target) => String.t(),
          optional(:api) => String.t(),
          optional(:op) => String.t(),
          optional(:response_message) => String.t() | nil,
          optional(:response_value) => term(),
          optional(:result) => String.t() | term(),
          optional(atom()) => term(),
          optional(String.t()) => term()
        }

  @spec from_response(
          String.t(),
          String.t(),
          String.t() | nil,
          String.t() | nil,
          term(),
          String.t() | term() | nil
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

  @spec from_subscription(String.t(), String.t(), String.t(), term(), String.t() | term() | nil) ::
          t()
  def from_subscription(target, api, response_message, response_value, result \\ "Ok") do
    from_response(target, api, "subscribe", response_message, response_value, result)
  end
end
