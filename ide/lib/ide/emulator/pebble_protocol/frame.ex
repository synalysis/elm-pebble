defmodule Ide.Emulator.PebbleProtocol.Frame do
  @moduledoc false

  @type t :: %{endpoint: non_neg_integer(), payload: binary(), raw: binary()}

  @spec encode(non_neg_integer(), binary()) :: binary()
  def encode(endpoint, payload) when is_integer(endpoint) and is_binary(payload) do
    <<byte_size(payload)::16, endpoint::16, payload::binary>>
  end

  @spec parse(binary()) :: {:ok, t(), binary()} | :more | {:error, term()}
  def parse(buffer) when byte_size(buffer) < 4, do: :more

  def parse(<<length::16, endpoint::16, rest::binary>> = buffer) do
    total = 4 + length

    cond do
      byte_size(rest) < length ->
        :more

      true ->
        <<raw::binary-size(total), remaining::binary>> = buffer
        <<_length::16, _endpoint::16, payload::binary-size(length)>> = raw
        {:ok, %{endpoint: endpoint, payload: payload, raw: raw}, remaining}
    end
  end

  @spec parse_many(binary()) :: {[t()], binary()}
  def parse_many(buffer), do: parse_many(buffer, [])

  defp parse_many(buffer, frames) do
    case parse(buffer) do
      {:ok, frame, remaining} -> parse_many(remaining, [frame | frames])
      :more -> {Enum.reverse(frames), buffer}
      {:error, _reason} -> {Enum.reverse(frames), buffer}
    end
  end
end
