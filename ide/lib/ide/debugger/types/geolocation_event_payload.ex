defmodule Ide.Debugger.Types.GeolocationEventPayload do
  @moduledoc "Payload for `debugger.geolocation` subscription responses."

  alias Ide.Debugger.Types

  @type t :: %{
          optional(:target) => String.t(),
          optional(:response_message) => String.t() | nil,
          optional(:response_value) => Types.subscription_payload(),
          optional(atom()) => Types.wire_input(),
          optional(String.t()) => Types.wire_input()
        }

  @spec from_response(String.t(), String.t() | nil, Types.subscription_payload()) :: t()
  def from_response(target, response_message, response_value) when is_binary(target) do
    %{target: target, response_message: response_message, response_value: response_value}
  end
end
