defmodule Ide.Emulator.PBWInstaller do
  @moduledoc false

  require Logger

  alias Ide.Emulator.PBW
  alias Ide.Emulator.PebbleProtocol.CRC32
  alias Ide.Emulator.PebbleProtocol.Packets
  alias Ide.Emulator.PebbleProtocol.Router

  @default_chunk_size 1_000
  @default_timeout_ms 30_000
  @default_putbytes_retries 2
  @default_chunk_delay_ms 10
  @default_part_retries 1
  @default_install_retries 2
  @default_install_retry_delay_ms 1_500
  @debug_log_path "/home/ape/projects/elm-pebble/.cursor/debug-b436e0.log"
  @debug_session_id "b436e0"

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
    part_delay_ms = Keyword.get(opts, :part_delay_ms, 0)
    putbytes_retries = Keyword.get(opts, :putbytes_retries, @default_putbytes_retries)
    chunk_delay_ms = Keyword.get(opts, :chunk_delay_ms, @default_chunk_delay_ms)
    part_retries = Keyword.get(opts, :part_retries, @default_part_retries)
    install_retries = Keyword.get(opts, :install_retries, @default_install_retries)
    install_retry_delay_ms = Keyword.get(opts, :install_retry_delay_ms, @default_install_retry_delay_ms)

    with {:ok, pbw} <- PBW.load(pbw_path, platform),
         :ok <- Router.acquire(router, timeout) do
      try do
        do_install_with_retries(
          router,
          pbw,
          chunk_size,
          timeout,
          part_delay_ms,
          putbytes_retries,
          chunk_delay_ms,
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
         part_delay_ms,
         putbytes_retries,
         chunk_delay_ms,
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
        part_delay_ms,
        putbytes_retries,
        chunk_delay_ms,
        part_retries
      )

    case result do
      {:error, {:putbytes_failed, %{kind: :binary, phase: :commit} = meta, {:nack, cookie}}}
      when retries_left > 0 ->
        Logger.debug(
          "native pbw install binary commit NACK cookie=#{cookie}; retrying full install handshake"
        )

        debug_log("install_retry", "H1,H3,H4", %{
          reason: :binary_commit_nack,
          cookie: cookie,
          crc: Map.get(meta, :crc),
          retries_left: retries_left,
          retry_delay_ms: retry_delay_ms
        })

        if retry_delay_ms > 0, do: Process.sleep(retry_delay_ms)

        do_install_with_retries(
          router,
          pbw,
          chunk_size,
          timeout,
          part_delay_ms,
          putbytes_retries,
          chunk_delay_ms,
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
         part_delay_ms,
         putbytes_retries,
         chunk_delay_ms,
         part_retries
       ) do
    Logger.debug(
      "native pbw install start uuid=#{pbw.uuid} variant=#{pbw.variant} parts=#{inspect(Enum.map(pbw.parts, &{&1.kind, &1.size}))}"
    )

    #region agent log
    debug_log("install_start", "H1,H3,H4", %{
      uuid: pbw.uuid,
      variant: pbw.variant,
      chunk_size: chunk_size,
      timeout: timeout,
      putbytes_retries: putbytes_retries,
      chunk_delay_ms: chunk_delay_ms,
      part_retries: part_retries,
      part_delay_ms: part_delay_ms,
      parts: Enum.map(pbw.parts, &%{kind: &1.kind, object_type: &1.object_type, size: &1.size})
    })

    #endregion

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
             part_delay_ms,
             putbytes_retries,
             chunk_delay_ms,
             part_retries
           ),
         :ok <- send_packet(router, Packets.app_run_state_start(pbw.uuid)) do
      {:ok, %{uuid: pbw.uuid, variant: pbw.variant, app_id: fetch.app_id, parts: parts}}
    end
  end

  defp insert_app_metadata(router, metadata, timeout) do
    token = System.unique_integer([:positive]) |> rem(0xFFFE) |> Kernel.+(1)

    {endpoint, payload} = Packets.blob_insert_app(token, metadata)
    Logger.debug("native pbw install blobdb insert token=#{token} uuid=#{metadata.uuid}")

    #region agent log
    debug_log("blobdb_insert", "H1,H4", %{
      token: token,
      uuid: metadata.uuid,
      flags: metadata.flags,
      icon_resource_id: metadata.icon_resource_id,
      app_name: metadata.app_name,
      app_version: [metadata.app_version_major, metadata.app_version_minor],
      sdk_version: [metadata.sdk_version_major, metadata.sdk_version_minor]
    })

    #endregion

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

    #region agent log
    debug_log("app_fetch_request_start", "H1,H3", %{uuid: uuid, timeout: timeout})

    #endregion

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
         part_delay_ms,
         putbytes_retries,
         chunk_delay_ms,
         part_retries
       ) do
    parts
    |> Enum.with_index()
    |> Enum.reduce_while({:ok, []}, fn {part, index}, {:ok, sent_parts} ->
      maybe_delay_between_parts(index, part_delay_ms)

      case send_part(
             router,
             part,
             app_id,
             chunk_size,
             timeout,
             putbytes_retries,
             chunk_delay_ms,
             part_retries
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

  defp send_part(
         router,
         part,
         app_id,
         chunk_size,
         timeout,
         putbytes_retries,
         chunk_delay_ms,
         retries_left
       ) do
    case send_part_once(router, part, app_id, chunk_size, timeout, putbytes_retries, chunk_delay_ms) do
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

        send_part(router, part, app_id, chunk_size, timeout, putbytes_retries, chunk_delay_ms, retries_left - 1)

      result ->
        result
    end
  end

  defp send_part_once(router, part, app_id, chunk_size, timeout, putbytes_retries, chunk_delay_ms) do
    object_type = Packets.object_type(part.object_type)
    {init_endpoint, init_payload} = Packets.putbytes_app_init(part.size, object_type, app_id)

    Logger.debug(
      "native pbw install part init kind=#{part.kind} size=#{part.size} app_id=#{app_id}"
    )

    #region agent log
    debug_log("part_start", "H1,H3,H4", %{
      kind: part.kind,
      object_type: part.object_type,
      encoded_object_type: Bitwise.bor(object_type, 0x80),
      size: part.size,
      app_id: app_id,
      init_payload_hex: Base.encode16(init_payload, case: :lower)
    })

    #endregion

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
         _ <- Logger.debug("native pbw install part install kind=#{part.kind} cookie=#{cookie}"),
         {:ok, _install} <-
           send_putbytes(
             router,
             Packets.putbytes_install(cookie),
             nil,
             %{phase: :install, kind: part.kind, cookie: cookie},
             timeout,
             putbytes_retries
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

  defp send_chunks(router, kind, data, cookie, chunk_size, timeout, putbytes_retries, chunk_delay_ms) do
    data
    |> chunks(chunk_size)
    |> Enum.reduce_while({:ok, 0}, fn chunk, {:ok, sent} ->
      case send_putbytes(
             router,
             Packets.putbytes_put(cookie, chunk),
             nil,
             %{phase: :put, kind: kind, cookie: cookie, offset: sent, chunk_size: byte_size(chunk)},
             timeout,
             putbytes_retries
           ) do
        {:ok, _ack} ->
          if chunk_delay_ms > 0, do: Process.sleep(chunk_delay_ms)
          {:cont, {:ok, sent + byte_size(chunk)}}

        {:error, reason} -> {:halt, {:error, reason}}
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
    #region agent log
    log_sample? = meta.phase != :put or rem(Map.get(meta, :offset, 0), 5_000) == 0

    if log_sample? do
      debug_log(
        "putbytes_send",
        "H1,H2,H4",
        Map.merge(meta, %{expected_cookie: expected_cookie, retries_left: retries_left})
      )
    end

    #endregion

    result =
      do_send_putbytes(router, packet, expected_cookie, meta, timeout, retries_left)

    #region agent log
    case result do
      {:ok, response} when log_sample? ->
        debug_log("putbytes_result", "H1,H2,H4", Map.merge(meta, response))

      {:error, reason} ->
        debug_log("putbytes_error", "H1,H2,H4", Map.merge(meta, %{reason: inspect(reason)}))

      _ ->
        :ok
    end

    #endregion

    result
  end

  defp do_send_putbytes(router, {endpoint, payload} = packet, expected_cookie, meta, timeout, retries_left) do
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

  defp send_packet(router, {endpoint, payload}), do: Router.send_packet(router, endpoint, payload)

  #region agent log
  defp debug_log(message, hypothesis_id, data) do
    payload =
      %{
        sessionId: @debug_session_id,
        runId: "install-debug",
        hypothesisId: hypothesis_id,
        location: "ide/lib/ide/emulator/pbw_installer.ex",
        message: message,
        data: data,
        timestamp: System.system_time(:millisecond)
      }
      |> Jason.encode!()

    File.write(@debug_log_path, payload <> "\n", [:append])
  rescue
    _ -> :ok
  end

  #endregion
end
