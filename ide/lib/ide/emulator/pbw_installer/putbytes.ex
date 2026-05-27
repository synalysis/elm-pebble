defmodule Ide.Emulator.PBWInstaller.Putbytes do
  @moduledoc false

  require Logger

  alias Ide.Emulator.PebbleProtocol.Packets
  alias Ide.Emulator.PebbleProtocol.Router
  alias Ide.Emulator.Types

  @spec send_chunks(
          pid(),
          atom(),
          binary(),
          non_neg_integer(),
          pos_integer(),
          timeout(),
          non_neg_integer(),
          non_neg_integer()
        ) :: {:ok, non_neg_integer()} | {:error, Types.install_error()}
  def send_chunks(
        router,
        kind,
        data,
        cookie,
        chunk_size,
        timeout,
        putbytes_retries,
        chunk_delay_ms
      ) do
    data
    |> chunks(chunk_size)
    |> Enum.reduce_while({:ok, 0}, fn chunk, {:ok, sent} ->
      case send_putbytes(
             router,
             Packets.putbytes_put(cookie, chunk),
             nil,
             %{
               phase: :put,
               kind: kind,
               cookie: cookie,
               offset: sent,
               chunk_size: byte_size(chunk)
             },
             timeout,
             putbytes_retries
           ) do
        {:ok, _ack} ->
          if chunk_delay_ms > 0, do: Process.sleep(chunk_delay_ms)
          {:cont, {:ok, sent + byte_size(chunk)}}

        {:error, reason} ->
          {:halt, {:error, reason}}
      end
    end)
  end

  @spec send_putbytes(
          pid(),
          {non_neg_integer(), binary()},
          non_neg_integer() | [non_neg_integer()] | nil,
          Types.putbytes_phase_meta(),
          timeout(),
          non_neg_integer()
        ) :: {:ok, Types.putbytes_response()} | {:error, Types.install_error()}
  def send_putbytes(router, packet, expected_cookie, meta, timeout, retries_left) do
    do_send_putbytes(router, packet, expected_cookie, meta, timeout, retries_left)
  end

  @spec chunks(binary(), pos_integer()) :: [binary()]
  def chunks(data, chunk_size) do
    chunks(data, chunk_size, [])
  end

  defp chunks(<<>>, _chunk_size, acc), do: Enum.reverse(acc)

  defp chunks(data, chunk_size, acc) when byte_size(data) <= chunk_size do
    Enum.reverse([data | acc])
  end

  defp chunks(data, chunk_size, acc) do
    chunk = binary_part(data, 0, chunk_size)
    rest = binary_part(data, chunk_size, byte_size(data) - chunk_size)
    chunks(rest, chunk_size, [chunk | acc])
  end

  defp do_send_putbytes(
         router,
         {endpoint, payload} = packet,
         expected_cookie,
         meta,
         timeout,
         retries_left
       ) do
    result =
      with {:ok, frame} <-
             Router.send_and_await(
               router,
               endpoint,
               payload,
               &(&1.endpoint == Packets.endpoint(:put_bytes)),
               timeout
             ),
           {:ok, response} <- Packets.decode_putbytes_response(frame.payload),
           :ok <- Packets.putbytes_ack?(response, expected_cookie) do
        {:ok, response}
      end

    case result do
      {:error, {:nack, cookie}} when meta.phase != :commit and retries_left > 0 ->
        Logger.debug(
          "native pbw install PutBytes NACK phase=#{meta.phase} kind=#{Map.get(meta, :kind)} cookie=#{cookie}; retrying"
        )

        Process.sleep(50)
        do_send_putbytes(router, packet, expected_cookie, meta, timeout, retries_left - 1)

      {:error, reason} ->
        {:error, {:putbytes_failed, meta, reason}}

      {:ok, _} = ok ->
        ok
    end
  end
end
