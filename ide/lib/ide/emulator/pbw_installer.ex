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
  @default_post_install_probe_timeout_ms 0

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

    post_install_probe_timeout =
      Keyword.get(opts, :post_install_probe_timeout_ms, @default_post_install_probe_timeout_ms)

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
          install_retry_delay_ms,
          post_install_probe_timeout
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
         retry_delay_ms,
         post_install_probe_timeout
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
        part_retries,
        post_install_probe_timeout
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
          retry_delay_ms,
          post_install_probe_timeout
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
         part_retries,
         post_install_probe_timeout
       ) do
    Logger.debug(
      "native pbw install start uuid=#{pbw.uuid} variant=#{pbw.variant} parts=#{inspect(Enum.map(pbw.parts, &{&1.kind, &1.size}))}"
    )

    # region agent log
    Ide.AgentDebugLog.log(
      "initial",
      "H13",
      "pbw_installer.ex:install:start",
      "embedded pbw installer starting",
      %{
        path: pbw.path,
        file: pbw_file_fingerprint(pbw.path),
        uuid: pbw.uuid,
        variant: pbw.variant,
        parts:
          Enum.map(pbw.parts, fn part ->
            %{
              kind: part.kind,
              name: part.name,
              size: part.size,
              sha256_12: sha256_12(part.data)
            }
          end)
      }
    )

    # endregion

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
           ) do
      probe_post_install_state(router, post_install_probe_timeout)
      {:ok, %{uuid: pbw.uuid, variant: pbw.variant, app_id: fetch.app_id, parts: parts}}
    end
  end

  defp pbw_file_fingerprint(path) do
    stat =
      case File.stat(path, time: :posix) do
        {:ok, stat} -> %{size: stat.size, mtime: stat.mtime}
        {:error, reason} -> %{error: inspect(reason)}
      end

    case File.read(path) do
      {:ok, data} -> Map.put(stat, :sha256_12, sha256_12(data))
      {:error, reason} -> Map.put(stat, :read_error, inspect(reason))
    end
  end

  defp sha256_12(data) when is_binary(data) do
    :crypto.hash(:sha256, data)
    |> Base.encode16(case: :lower)
    |> binary_part(0, 12)
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
      |> tap(fn
        {:ok, fetch} ->
          # region agent log
          Ide.AgentDebugLog.log(
            "initial",
            "H13",
            "pbw_installer.ex:app_fetch",
            "app fetch request received",
            %{
              uuid: fetch.uuid,
              app_id: fetch.app_id,
              payload: Base.encode16(frame.payload, case: :lower)
            }
          )

        # endregion

        _ ->
          :ok
      end)
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

  defp install_part_order(%{kind: :binary}), do: 0
  defp install_part_order(%{kind: :resources}), do: 1
  defp install_part_order(%{kind: :worker}), do: 2
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

    with {:ok, install} <-
           send_putbytes(
             router,
             Packets.putbytes_install(cookie),
             nil,
             %{phase: :install, kind: kind, cookie: cookie},
             install_timeout,
             putbytes_retries
           ) do
      # region agent log
      Ide.AgentDebugLog.log(
        "initial",
        "H13",
        "pbw_installer.ex:install_ack",
        "final putbytes install acknowledged",
        %{
          kind: kind,
          request_cookie: cookie,
          response_cookie: install.cookie,
          response: to_string(install.result)
        }
      )

      # endregion
      observe_post_install_frame(router, kind)
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
      # region agent log
      Ide.AgentDebugLog.log(
        "initial",
        "H25",
        "pbw_installer.ex:putbytes:chunk_send",
        "sending PutBytes chunk",
        %{
          kind: kind,
          cookie: cookie,
          offset: sent,
          chunk_size: byte_size(chunk),
          total_size: byte_size(data)
        }
      )

      # endregion

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
          # region agent log
          Ide.AgentDebugLog.log(
            "initial",
            "H25",
            "pbw_installer.ex:putbytes:chunk_ack",
            "PutBytes chunk acknowledged",
            %{
              kind: kind,
              cookie: cookie,
              offset: sent,
              chunk_size: byte_size(chunk),
              next_offset: sent + byte_size(chunk),
              total_size: byte_size(data)
            }
          )

          # endregion
          {:cont, {:ok, sent + byte_size(chunk)}}

        {:error, reason} ->
          # region agent log
          Ide.AgentDebugLog.log(
            "initial",
            "H25",
            "pbw_installer.ex:putbytes:chunk_error",
            "PutBytes chunk failed",
            %{
              kind: kind,
              cookie: cookie,
              offset: sent,
              chunk_size: byte_size(chunk),
              reason: inspect(reason)
            }
          )

          # endregion
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
    if meta.phase != :put do
      # region agent log
      Ide.AgentDebugLog.log(
        "initial",
        "H25,H26",
        "pbw_installer.ex:putbytes:send",
        "sending PutBytes phase",
        %{
          phase: meta.phase,
          kind: Map.get(meta, :kind),
          cookie: Map.get(meta, :cookie),
          size: Map.get(meta, :size),
          app_id: Map.get(meta, :app_id),
          bytes_sent: Map.get(meta, :bytes_sent),
          crc: Map.get(meta, :crc),
          expected_cookie: expected_cookie,
          timeout: timeout,
          payload_prefix:
            payload |> binary_part(0, min(byte_size(payload), 24)) |> Base.encode16(case: :lower),
          payload_bytes: byte_size(payload)
        }
      )

      # endregion
    end

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
        # region agent log
        Ide.AgentDebugLog.log(
          "initial",
          "H25,H26",
          "pbw_installer.ex:putbytes:nack_retry",
          "PutBytes phase NACK retrying",
          %{
            phase: meta.phase,
            kind: Map.get(meta, :kind),
            cookie: cookie,
            retries_left: retries_left
          }
        )

        # endregion
        Logger.debug(
          "native pbw install PutBytes NACK phase=#{meta.phase} kind=#{Map.get(meta, :kind)} cookie=#{cookie}; retrying"
        )

        Process.sleep(50)
        do_send_putbytes(router, packet, expected_cookie, meta, timeout, retries_left - 1)

      {:error, reason} ->
        # region agent log
        Ide.AgentDebugLog.log(
          "initial",
          "H25,H26",
          "pbw_installer.ex:putbytes:error",
          "PutBytes phase failed",
          %{
            phase: meta.phase,
            kind: Map.get(meta, :kind),
            cookie: Map.get(meta, :cookie),
            expected_cookie: expected_cookie,
            reason: inspect(reason)
          }
        )

        # endregion
        {:error, {:putbytes_failed, meta, reason}}

      {:ok, response} = ok ->
        if meta.phase != :put do
          # region agent log
          Ide.AgentDebugLog.log(
            "initial",
            "H25,H26",
            "pbw_installer.ex:putbytes:ack",
            "PutBytes phase acknowledged",
            %{
              phase: meta.phase,
              kind: Map.get(meta, :kind),
              cookie: Map.get(meta, :cookie),
              expected_cookie: expected_cookie,
              response_cookie: response.cookie,
              response: to_string(response.result)
            }
          )

          # endregion
        end

        ok
    end
  end

  defp observe_post_install_frame(router, kind) do
    matcher = fn frame ->
      frame.endpoint in [
        Packets.endpoint(:app_fetch),
        Packets.endpoint(:app_run_state),
        Packets.endpoint(:put_bytes)
      ]
    end

    case Router.await_frame(router, matcher, 250) do
      {:ok, frame} ->
        # region agent log
        Ide.AgentDebugLog.log(
          "initial",
          "H13",
          "pbw_installer.ex:post_install_frame",
          "frame observed after final install ack",
          %{
            kind: kind,
            endpoint: frame.endpoint,
            payload: Base.encode16(frame.payload, case: :lower)
          }
        )

        # endregion
        :ok

      {:error, reason} ->
        # region agent log
        Ide.AgentDebugLog.log(
          "initial",
          "H13",
          "pbw_installer.ex:post_install_timeout",
          "no post-install frame observed",
          %{
            kind: kind,
            reason: inspect(reason)
          }
        )

        # endregion
        :ok
    end
  end

  defp probe_post_install_state(_router, timeout) when timeout <= 0, do: :ok

  defp probe_post_install_state(router, timeout) do
    {endpoint, payload} = Packets.app_run_state_request()

    run_state_result =
      Router.send_and_await(
        router,
        endpoint,
        payload,
        &(&1.endpoint == Packets.endpoint(:app_run_state)),
        timeout
      )

    # region agent log
    Ide.AgentDebugLog.log(
      "initial",
      "H28",
      "pbw_installer.ex:post_install_run_state",
      "queried AppRunState after install",
      %{
        request_endpoint: endpoint,
        request_payload: Base.encode16(payload, case: :lower),
        result: probe_result(run_state_result)
      }
    )

    # endregion

    observe_post_install_any_frames(router, timeout, 40, [])
  end

  defp observe_post_install_any_frames(_router, _timeout, 0, frames) do
    # region agent log
    Ide.AgentDebugLog.log(
      "initial",
      "H29",
      "pbw_installer.ex:post_install_frames",
      "post-install frame observation complete",
      %{
        frames: Enum.reverse(frames)
      }
    )

    # endregion
    :ok
  end

  defp observe_post_install_any_frames(router, timeout, remaining, frames) do
    case Router.await_frame(router, fn _frame -> true end, timeout) do
      {:ok, frame} ->
        observed =
          %{
            endpoint: frame.endpoint,
            payload_bytes: byte_size(frame.payload),
            payload_prefix:
              frame.payload
              |> binary_part(0, min(byte_size(frame.payload), 48))
              |> Base.encode16(case: :lower)
          }
          |> maybe_add_data_logging_marker(frame.payload)

        observe_post_install_any_frames(router, timeout, remaining - 1, [observed | frames])

      {:error, reason} ->
        observe_post_install_any_frames(router, timeout, 0, [%{error: inspect(reason)} | frames])
    end
  end

  defp maybe_add_data_logging_marker(
         observed,
         <<1, _session, _uuid::binary-size(16), _timestamp::little-32, tag::little-32,
           _rest::binary>>
       ) do
    Map.put(
      observed,
      :data_logging_tag_hex,
      "0x" <> String.pad_leading(Integer.to_string(tag, 16), 8, "0")
    )
  end

  defp maybe_add_data_logging_marker(observed, _payload), do: observed

  defp probe_result({:ok, frame}) do
    %{
      endpoint: frame.endpoint,
      payload_bytes: byte_size(frame.payload),
      payload: Base.encode16(frame.payload, case: :lower)
    }
  end

  defp probe_result({:error, reason}), do: %{error: inspect(reason)}
end
