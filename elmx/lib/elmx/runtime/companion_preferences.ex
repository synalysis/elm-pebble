defmodule Elmx.Runtime.CompanionPreferences do
  @moduledoc """
  Decodes companion preference responses from wire `Maybe` wrappers and JSON strings.
  """
  alias Elmx.Types, as: Types


  alias Elmx.Runtime.Json.Decode
  alias Elmx.Types

  @spec decode_response(
          Elmx.Runtime.Json.Decode.decoder(),
          Types.maybe_like() | Types.wire_value() | String.t() | Types.wire_map()
        ) :: Types.result_like()
  def decode_response(_schema, response) do
    case normalize_response(response) do
      :nothing -> {:Err, :MissingResponse}
      {:just, payload} -> decode_payload(payload)
    end
  end

  @spec normalize_response(Types.elm_value() | term() | map()) :: Types.elm_value()

  defp normalize_response(:Nothing), do: :nothing
  defp normalize_response({:Nothing}), do: :nothing
  defp normalize_response(%{"ctor" => "Nothing"}), do: :nothing

  defp normalize_response({:Just, payload}), do: {:just, payload}
  defp normalize_response(%{"ctor" => "Just", "args" => [payload]}), do: {:just, payload}

  defp normalize_response(other), do: {:just, other}

  @spec decode_payload(String.t() | map() | term()) :: Types.elm_value()

  defp decode_payload(payload) when is_binary(payload) do
    case Decode.decode_string(Decode.value(), payload) do
      {:Ok, value} -> {:Ok, value}
      {:Err, message} -> {:Err, message}
    end
  end

  defp decode_payload(payload) when is_map(payload), do: {:Ok, payload}
  defp decode_payload(_), do: {:Err, :InvalidJson}
end
