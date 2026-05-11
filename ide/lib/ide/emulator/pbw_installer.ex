defmodule Ide.Emulator.PBWInstaller do
  @moduledoc false

  require Logger

  alias Ide.Emulator.PBW
  alias Ide.Emulator.PebbleProtocol.CRC32
  alias Ide.Emulator.PebbleProtocol.Packets
  alias Ide.Emulator.PebbleProtocol.Router

  @default_chunk_size 1_000
  @default_timeout_ms 30_000
  @default_install_timeout_ms 120_000
  @default_putbytes_retries 2
  @default_chunk_delay_ms 10
  @default_install_transition_timeout_ms 30_000
  @default_part_retries 1
  @default_install_retries 2
  @default_install_retry_delay_ms 1_500

  @type install_result :: %{
          uuid: String.t(),
          variant: String.t(),
          app_id: non_neg_integer(),
          parts: [map()]
        }

  @spec install(pid(), String.t(), String.t(), keyword()) ::
          {:ok, install_result()} | {:error, term()}
  def install(router, pbw_path, platform, opts \\ [])
      when is_pid(router) and is_binary(pbw_path) and is_binary(platform) do
    chunk_size = Keyword.get(opts, :chunk_size, @default_chunk_size)
    timeout = Keyword.get(opts, :timeout_ms, @default_timeout_ms)
    install_timeout = Keyword.get(opts, :install_timeout_ms, @default_install_timeout_ms)
    part_delay_ms = Keyword.get(opts, :part_delay_ms, 0)
    putbytes_retries = Keyword.get(opts, :putbytes_retries, @default_putbytes_retries)
    chunk_delay_ms = Keyword.get(opts, :chunk_delay_ms, @default_chunk_delay_ms)

    install_transition_timeout =
      Keyword.get(opts, :install_transition_timeout_ms, @default_install_transition_timeout_ms)

    part_retries = Keyword.get(opts, :part_retries, @default_part_retries)
    install_retries = Keyword.get(opts, :install_retries, @default_install_retries)

    install_retry_delay_ms =
      Keyword.get(opts, :install_retry_delay_ms, @default_install_retry_delay_ms)

    with {:ok, pbw} <- PBW.load(pbw_path, platform),
         :ok <- Router.acquire(router, timeout) do
      try do
        do_install_with_retries(
          router,
          pbw,
          chunk_size,
          timeout,
          install_timeout,
          part_delay_ms,
          putbytes_retries,
          chunk_delay_ms,
          install_transition_timeout,
          part_retries,
          install_retries,
          install_retry_delay_ms
        )
      after
        Router.release(router)
      end
    end
  end

  defp do_install_with_retries(
         router,
         pbw,
         chunk_size,
         timeout,
         install_timeout,
         part_delay_ms,
         putbytes_retries,
         chunk_delay_ms,
         install_transition_timeout,
         part_retries,
         retries_left,
         retry_delay_ms
       ) do
    result =
      do_install(
        router,
        pbw,
        chunk_size,
        timeout,
        install_timeout,
        part_delay_ms,
        putbytes_retries,
        chunk_delay_ms,
        install_transition_timeout,
        part_retries
      )

    case result do
      {:error, {:putbytes_failed, %{kind: :binary, phase: :commit}, {:nack, cookie}}}
      when retries_left > 0 ->
        Logger.debug(
          "native pbw install binary commit NACK cookie=#{cookie}; retrying full install handshake"
        )

        if retry_delay_ms > 0, do: Process.sleep(retry_delay_ms)

        do_install_with_retries(
          router,
          pbw,
          chunk_size,
          timeout,
          install_timeout,
          part_delay_ms,
          putbytes_retries,
          chunk_delay_ms,
          install_transition_timeout,
          part_retries,
          retries_left - 1,
          retry_delay_ms
        )

      _ ->
        result
    end
  end

  defp do_install(
         router,
         pbw,
         chunk_size,
         timeout,
         install_timeout,
         part_delay_ms,
         putbytes_retries,
         chunk_delay_ms,
         install_transition_timeout,
         part_retries
       ) do
    Logger.debug(
      "native pbw install start uuid=#{pbw.uuid} variant=#{pbw.variant} parts=#{inspect(Enum.map(pbw.parts, &{&1.kind, &1.size}))}"
    )

    with :ok <- insert_app_metadata(router, pbw.app_metadata, timeout),
         {:ok, fetch} <- request_app_fetch(router, pbw.uuid, timeout),
         :ok <- verify_fetch_uuid(fetch.uuid, pbw.uuid),
         {:ok, parts} <-
           send_parts(
             router,
             pbw.parts,
             fetch.app_id,
             chunk_size,
             timeout,
             install_timeout,
             part_delay_ms,
             putbytes_retries,
             chunk_delay_ms,
             install_transition_timeout,
             part_retries
           ),
         :ok <- start_installed_app(router, pbw.uuid) do
      {:ok, %{uuid: pbw.uuid, variant: pbw.variant, app_id: fetch.app_id, parts: parts}}
    end
  end

  defp start_installed_app(router, uuid) do
    Logger.debug("native pbw install start installed app uuid=#{uuid}")
    {endpoint, payload} = Packets.app_run_state_start(uuid)
    Router.send_packet(router, endpoint, payload)
  end

  defp insert_app_metadata(router, metadata, timeout) do
    token = System.unique_integer([:positive]) |> rem(0xFFFE) |> Kernel.+(1)

    {endpoint, payload} = Packets.blob_insert_app(token, metadata)
    Logger.debug("native pbw install blobdb insert token=#{token} uuid=#{metadata.uuid}")

    with {:ok, frame} <-
           Router.send_and_await(
             router,
             endpoint,
             payload,
             &(&1.endpoint == Packets.endpoint(:blob_db)),
             timeout
           ),
         {:ok, response} <- Packets.decode_blob_response(frame.payload),
         :ok <- verify_blob_response(response, token) do
      :ok
    end
  end

  defp verify_blob_response(%{success?: true, token: token}, token), do: :ok

  defp verify_blob_response(%{token: actual}, expected) when actual != expected,
    do: {:error, {:wrong_blob_token, expected, actual}}

  defp verify_blob_response(%{response: response}, _token),
    do: {:error, {:blob_insert_failed, response}}

  defp request_app_fetch(router, uuid, timeout) do
    {endpoint, payload} = Packets.app_run_state_start(uuid)
    Logger.debug("native pbw install request app_fetch uuid=#{uuid}")

    with {:ok, frame} <-
           Router.send_and_await(
             router,
             endpoint,
             payload,
             &(&1.endpoint == Packets.endpoint(:app_fetch)),
             timeout
           ) do
      Packets.decode_app_fetch_request(frame.payload)
    end
  end

  defp verify_fetch_uuid(uuid, uuid), do: :ok

  defp verify_fetch_uuid(actual, expected),
    do: {:error, {:wrong_app_fetch_uuid, expected, actual}}

  defp send_parts(
         router,
         parts,
         app_id,
         chunk_size,
         timeout,
         install_timeout,
         part_delay_ms,
         putbytes_retries,
         chunk_delay_ms,
         install_transition_timeout,
         part_retries
       ) do
    install_parts =
      parts
      |> Enum.sort_by(&install_part_order/1)

    install_parts
    |> Enum.with_index()
    |> Enum.reduce_while({:ok, []}, fn {part, index}, {:ok, sent_parts} ->
      maybe_delay_between_parts(index, part_delay_ms)
      final_part? = index == length(install_parts) - 1

      case send_part(
             router,
             part,
             app_id,
             chunk_size,
             timeout,
             install_timeout,
             putbytes_retries,
             chunk_delay_ms,
             install_transition_timeout,
             part_retries,
             final_part?
           ) do
        {:ok, sent_part} -> {:cont, {:ok, [sent_part | sent_parts]}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
    |> case do
      {:ok, sent_parts} -> {:ok, Enum.reverse(sent_parts)}
      error -> error
    end
  end

  defp install_part_order(%{kind: :resources}), do: 0
  defp install_part_order(%{kind: :worker}), do: 1
  defp install_part_order(%{kind: :binary}), do: 2
  defp install_part_order(_part), do: 3

  defp send_part(
         router,
         part,
         app_id,
         chunk_size,
         timeout,
         install_timeout,
         putbytes_retries,
         chunk_delay_ms,
         install_transition_timeout,
         retries_left,
         install_part?
       ) do
    case send_part_once(
           router,
           part,
           app_id,
           chunk_size,
           timeout,
           install_timeout,
           putbytes_retries,
           chunk_delay_ms,
           install_transition_timeout,
           install_part?
         ) do
      {:error, {:putbytes_failed, %{phase: :commit, cookie: cookie} = meta, {:nack, _}}}
      when retries_left > 0 ->
        Logger.debug(
          "native pbw install commit NACK kind=#{part.kind} cookie=#{cookie}; resending part"
        )

        _ =
          send_putbytes(
            router,
            Packets.putbytes_abort(cookie),
            nil,
            Map.merge(meta, %{phase: :abort_after_commit_nack}),
            timeout,
            putbytes_retries
          )

        Process.sleep(100)

        send_part(
          router,
          part,
          app_id,
          chunk_size,
          timeout,
          install_timeout,
          putbytes_retries,
          chunk_delay_ms,
          install_transition_timeout,
          retries_left - 1,
          install_part?
        )

      result ->
        result
    end
  end

  defp send_part_once(
         router,
         part,
         app_id,
         chunk_size,
         timeout,
         install_timeout,
         putbytes_retries,
         chunk_delay_ms,
         install_transition_timeout,
         install_part?
       ) do
    object_type = Packets.object_type(part.object_type)
    {init_endpoint, init_payload} = Packets.putbytes_app_init(part.size, object_type, app_id)

    Logger.debug(
      "native pbw install part init kind=#{part.kind} size=#{part.size} app_id=#{app_id}"
    )

    with {:ok, init} <-
           send_putbytes(
             router,
             {init_endpoint, init_payload},
             nil,
             %{phase: :init, kind: part.kind, size: part.size, app_id: app_id},
             timeout,
             putbytes_retries
           ),
         cookie <- init.cookie,
         _ <- Logger.debug("native pbw install part cookie kind=#{part.kind} cookie=#{cookie}"),
         {:ok, bytes_sent} <-
           send_chunks(
             router,
             part.kind,
             part.data,
             cookie,
             chunk_size,
             timeout,
             putbytes_retries,
             chunk_delay_ms
           ),
         crc <- CRC32.stm32(part.data),
         _ <-
           Logger.debug(
             "native pbw install part commit kind=#{part.kind} bytes=#{bytes_sent} crc=#{crc}"
           ),
         {:ok, _commit} <-
           send_putbytes(
             router,
             Packets.putbytes_commit(cookie, crc),
             nil,
             %{phase: :commit, kind: part.kind, cookie: cookie, bytes_sent: bytes_sent, crc: crc},
             timeout,
             putbytes_retries
           ),
         :ok <-
           maybe_install_part(
             router,
             part.kind,
             cookie,
             install_timeout,
             putbytes_retries,
             install_transition_timeout,
             install_part?
           ) do
      {:ok,
       %{
         kind: part.kind,
         name: part.name,
         cookie: cookie,
         bytes: bytes_sent,
         crc: crc
       }}
    end
  end

  defp maybe_install_part(
         router,
         kind,
         cookie,
         install_timeout,
         putbytes_retries,
         _install_transition_timeout,
         true
       ) do
    Logger.debug("native pbw install part install kind=#{kind} cookie=#{cookie}")

    with {:ok, _install} <-
           send_putbytes(
             router,
             Packets.putbytes_install(cookie),
             nil,
             %{phase: :install, kind: kind, cookie: cookie},
             install_timeout,
             putbytes_retries
           ) do
      :ok
    end
  end

  defp maybe_install_part(
         router,
         kind,
         cookie,
         _install_timeout,
         _putbytes_retries,
         install_transition_timeout,
         false
       ) do
    Logger.debug("native pbw install transition part install kind=#{kind} cookie=#{cookie}")

    case send_putbytes(
           router,
           Packets.putbytes_install(cookie),
           nil,
           %{phase: :install_transition, kind: kind, cookie: cookie},
           install_transition_timeout,
           0
         ) do
      {:ok, _install} ->
        :ok

      {:error, {:putbytes_failed, %{phase: :install_transition}, :timeout}} ->
        Logger.debug(
          "native pbw install transition timed out kind=#{kind} cookie=#{cookie}; continuing"
        )

        :ok

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp send_chunks(
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

  defp maybe_delay_between_parts(0, _delay_ms), do: :ok
  defp maybe_delay_between_parts(_index, delay_ms) when delay_ms <= 0, do: :ok

  defp maybe_delay_between_parts(_index, delay_ms) do
    Logger.debug("native pbw install waiting #{delay_ms}ms before next part")
    Process.sleep(delay_ms)
  end

  defp chunks(data, chunk_size) do
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

  defp send_putbytes(router, packet, expected_cookie, meta, timeout, retries_left) do
    do_send_putbytes(router, packet, expected_cookie, meta, timeout, retries_left)
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

      ok ->
        ok
    end
  end
end
