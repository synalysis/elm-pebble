defmodule Ide.Debugger.Types.GeolocationEventPayload do
  @moduledoc "Payload for `debugger.geolocation` subscription responses."

  @type t :: %{
          optional(:target) => String.t(),
          optional(:response_message) => String.t() | nil,
          optional(:response_value) => map() | term(),
          optional(atom()) => term(),
          optional(String.t()) => term()
        }

  @spec from_response(String.t(), String.t() | nil, map() | term()) :: t()
  def from_response(target, response_message, response_value) when is_binary(target) do
    %{target: target, response_message: response_message, response_value: response_value}
  end
end
