defmodule Ide.Emulator.PBWInstaller do
  @moduledoc false

  require Logger

  alias Ide.Emulator.PBW
  alias Ide.Emulator.PBWInstaller.{AppFetch, BlobDb, Parts, PostInstall}
  alias Ide.Emulator.Types
  alias Ide.Emulator.PebbleProtocol.Router

  @default_chunk_size 500
  @default_timeout_ms 30_000
  @default_install_timeout_ms 120_000
  @default_putbytes_retries 2
  @default_chunk_delay_ms 10
  @default_install_transition_timeout_ms 30_000
  @default_part_retries 1
  @default_install_retries 2
  @default_install_retry_delay_ms 1_500
  @default_post_install_probe_timeout_ms 0
  @default_blob_post_insert_settle_ms 750

  @spec install(pid(), String.t(), String.t(), keyword()) ::
          {:ok, Types.pbw_install_result()} | {:error, Types.install_error()}
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

    blob_post_insert_settle_ms =
      Keyword.get(opts, :blob_post_insert_settle_ms, @default_blob_post_insert_settle_ms)

    with {:ok, pbw} <- PBW.load(pbw_path, platform),
         :ok <- validate_pbw_platform(pbw, platform),
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
          post_install_probe_timeout,
          blob_post_insert_settle_ms
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
         post_install_probe_timeout,
         blob_post_insert_settle_ms
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
        post_install_probe_timeout,
        blob_post_insert_settle_ms
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
          post_install_probe_timeout,
          blob_post_insert_settle_ms
        )

      {:error, reason} when retries_left > 0 ->
        if handshake_retryable?(reason) do
          Logger.debug(
            "native pbw install handshake failed #{inspect(reason)}; retrying (#{retries_left - 1} left)"
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
            post_install_probe_timeout,
            blob_post_insert_settle_ms
          )
        else
          result
        end

      _ ->
        result
    end
  end

  defp validate_pbw_platform(%{variant: variant}, platform) when variant == platform, do: :ok

  defp validate_pbw_platform(%{variant: variant}, platform) do
    {:error, {:pbw_platform_mismatch, %{expected: platform, got: variant}}}
  end

  defp handshake_retryable?(:timeout), do: true
  defp handshake_retryable?({:blob_insert_failed, _response}), do: true
  defp handshake_retryable?({:wrong_blob_token, _expected, _actual}), do: true
  defp handshake_retryable?({:wrong_app_fetch_uuid, _expected, _actual}), do: true
  defp handshake_retryable?(_reason), do: false

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
         post_install_probe_timeout,
         blob_post_insert_settle_ms
       ) do
    Logger.debug(
      "native pbw install start uuid=#{pbw.uuid} variant=#{pbw.variant} parts=#{inspect(Enum.map(pbw.parts, &{&1.kind, &1.size}))}"
    )

    with :ok <-
           BlobDb.insert_app_metadata(
             router,
             pbw.app_metadata,
             timeout,
             blob_post_insert_settle_ms
           ),
         {:ok, fetch} <- AppFetch.request_app_fetch(router, pbw.uuid, timeout),
         :ok <- AppFetch.verify_fetch_uuid(fetch.uuid, pbw.uuid),
         {:ok, parts} <-
           Parts.send_parts(
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
      PostInstall.probe_post_install_state(router, post_install_probe_timeout)
      {:ok, %{uuid: pbw.uuid, variant: pbw.variant, app_id: fetch.app_id, parts: parts}}
    end
  end
end
