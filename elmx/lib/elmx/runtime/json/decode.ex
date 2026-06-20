defmodule Elmx.Runtime.Json.Decode do
  @moduledoc """
  Minimal composable `Json.Decode` runtime for companion phone templates.

  Decoders are opaque `{:json_decoder, spec}` terms composed at compile time and
  interpreted by `decode_value/2` against plain maps or JSON strings.
  """

  alias Elmx.Runtime.Json.Decode.{Build, Runtime}
  alias Elmx.Types

  @type decoder :: Types.json_decoder()
  @type decode_result :: Types.result_native()

  defdelegate string(), to: Build
  defdelegate int(), to: Build
  defdelegate float(), to: Build
  defdelegate bool(), to: Build
  defdelegate value(), to: Build
  defdelegate field(name, decoder), to: Build
  defdelegate list(decoder), to: Build
  defdelegate array(decoder), to: Build
  defdelegate index(idx, decoder), to: Build
  defdelegate at(path, decoder), to: Build
  defdelegate null(default), to: Build
  defdelegate nullable(decoder), to: Build
  defdelegate maybe(decoder), to: Build
  defdelegate fail(message), to: Build
  defdelegate and_then(fun, decoder), to: Build
  defdelegate lazy(thunk), to: Build
  defdelegate dict(value_decoder), to: Build
  defdelegate key_value_pairs(value_decoder), to: Build
  defdelegate map(fun, decoder), to: Build
  defdelegate map2(fun, d1, d2), to: Build
  defdelegate map3(fun, d1, d2, d3), to: Build
  defdelegate map4(fun, d1, d2, d3, d4), to: Build
  defdelegate map5(fun, d1, d2, d3, d4, d5), to: Build
  defdelegate map6(fun, d1, d2, d3, d4, d5, d6), to: Build
  defdelegate map7(fun, d1, d2, d3, d4, d5, d6, d7), to: Build
  defdelegate succeed(value), to: Build
  defdelegate one_of(decoders), to: Build
  defdelegate apply_decoder(decoder, value), to: Runtime

  @spec decode_string(decoder(), String.t()) :: decode_result()
  def decode_string(decoder, json) when is_binary(json), do: decode_value(decoder, json)

  @spec decode_value(decoder(), Types.json_value() | String.t()) :: decode_result()
  def decode_value(decoder, value) do
    with {:ok, normalized} <- Runtime.normalize_input(value) do
      Runtime.apply_decoder(decoder, normalized)
    end
  end

  @spec error_to_string(String.t() | Types.elm_value()) :: String.t()
  def error_to_string(message) when is_binary(message), do: message
  def error_to_string(other), do: inspect(other)
end
