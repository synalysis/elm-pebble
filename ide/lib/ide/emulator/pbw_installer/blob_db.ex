defmodule Ide.Emulator.PBWInstaller.BlobDb do
  @moduledoc false

  require Logger

  alias Ide.Emulator.PBW
  alias Ide.Emulator.PebbleProtocol.Packets
  alias Ide.Emulator.PebbleProtocol.Router
  alias Ide.Emulator.Types

  @spec insert_app_metadata(pid(), PBW.app_metadata(), timeout(), non_neg_integer()) ::
          :ok | {:error, Types.install_error()}
  def insert_app_metadata(router, metadata, timeout, settle_ms) do
    token = System.unique_integer([:positive]) |> rem(0xFFFE) |> Kernel.+(1)

    {endpoint, payload} = Packets.blob_insert_app(token, metadata)
    Logger.debug("native pbw install blobdb insert token=#{token} uuid=#{metadata.uuid}")

    result =
      send_blob_request(router, endpoint, payload, token, timeout)

    case result do
      :ok ->
        if settle_ms > 0, do: Process.sleep(settle_ms)
        :ok

      {:error, {:blob_insert_failed, response}} ->
        Logger.debug(
          "native pbw install blobdb insert failed response=#{response}; deleting stale app metadata and retrying"
        )

        _ = delete_app_metadata(router, metadata.uuid, timeout)
        retry_insert_app_metadata(router, metadata, timeout, settle_ms)

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp retry_insert_app_metadata(router, metadata, timeout, settle_ms) do
    token = System.unique_integer([:positive]) |> rem(0xFFFE) |> Kernel.+(1)
    {endpoint, payload} = Packets.blob_insert_app(token, metadata)

    Logger.debug("native pbw install blobdb retry insert token=#{token} uuid=#{metadata.uuid}")

    case send_blob_request(router, endpoint, payload, token, timeout) do
      :ok ->
        if settle_ms > 0, do: Process.sleep(settle_ms)
        :ok

      error ->
        error
    end
  end

  defp delete_app_metadata(router, uuid, timeout) do
    token = System.unique_integer([:positive]) |> rem(0xFFFE) |> Kernel.+(1)
    {endpoint, payload} = Packets.blob_delete_app(token, uuid)

    Logger.debug("native pbw install blobdb delete token=#{token} uuid=#{uuid}")

    case send_blob_request(router, endpoint, payload, token, timeout) do
      :ok ->
        :ok

      {:error, reason} = error ->
        Logger.debug(
          "native pbw install blobdb delete before retry failed uuid=#{uuid} reason=#{inspect(reason)}"
        )

        error
    end
  end

  defp send_blob_request(router, endpoint, payload, token, timeout) do
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

  @doc false
  @spec verify_blob_response(map(), non_neg_integer()) :: :ok | {:error, Types.install_error()}
  def verify_blob_response(%{success?: true, token: token}, token), do: :ok

  def verify_blob_response(%{token: actual}, expected) when actual != expected,
    do: {:error, {:wrong_blob_token, expected, actual}}

  def verify_blob_response(%{response: response}, _token),
    do: {:error, {:blob_insert_failed, response}}
end
