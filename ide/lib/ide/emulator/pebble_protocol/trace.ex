defmodule Ide.Emulator.PebbleProtocol.Trace do
  @moduledoc false

  @endpoint_names %{
    0x0011 => "PhoneVersion",
    0x0034 => "AppRunState",
    0x07D1 => "AppMessage",
    0x07D2 => "Logs",
    0x0BB8 => "Screenshot",
    0x1771 => "AppFetch",
    0x1A7A => "DataLogging",
    0xB1DB => "BlobDB",
    0xBEEF => "PutBytes"
  }

  @spec enabled?() :: boolean()
  def enabled? do
    System.get_env("ELM_PEBBLE_PROTOCOL_TRACE") in ["1", "true", "TRUE", "yes", "YES"]
  end

  @spec emit(String.t(), map()) :: :ok
  def emit(direction, %{endpoint: endpoint, payload: payload}) do
    line = format(direction, endpoint, payload)

    case System.get_env("ELM_PEBBLE_PROTOCOL_TRACE_FILE") do
      path when is_binary(path) and path != "" ->
        path |> Path.dirname() |> File.mkdir_p()
        File.write!(path, line <> "\n", [:append])

      _ ->
        require Logger
        Logger.debug(line)
    end

    :ok
  end

  @spec format(String.t(), non_neg_integer(), binary()) :: String.t()
  def format(direction, endpoint, payload)
      when is_binary(direction) and is_integer(endpoint) and is_binary(payload) do
    preview =
      payload
      |> binary_part(0, min(byte_size(payload), 24))
      |> Base.encode16(case: :lower)

    suffix = if byte_size(payload) > 24, do: "...", else: ""

    "pebble-protocol #{direction} endpoint=#{endpoint} name=#{endpoint_name(endpoint)} len=#{byte_size(payload)} payload=#{preview}#{suffix}"
  end

  @spec endpoint_name(non_neg_integer()) :: String.t()
  def endpoint_name(endpoint), do: Map.get(@endpoint_names, endpoint, "Unknown")
end
