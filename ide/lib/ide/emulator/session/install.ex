defmodule Ide.Emulator.Session.Install do
  @moduledoc false

  require Logger

  alias Ide.Emulator.{InstallPrep, PBWInstaller}
  alias Ide.Emulator.Types

  @spec install_with_router(Types.install_context()) ::
          {:ok, Types.pbw_install_result()} | {:error, Types.install_error()}
  def install_with_router(context) do
    PBWInstaller.install(
      context.protocol_router_pid,
      context.artifact_path,
      context.platform,
      InstallPrep.pacing_opts(context.platform)
    )
  end

  @spec do_install(pid(), non_neg_integer()) ::
          {:ok, Types.pbw_install_result()} | {:error, Types.session_error()}
  def do_install(pid, retries_left) do
    with {:ok, context} <- GenServer.call(pid, :install_context, 5_000) do
      case install_with_router(context) do
        {:ok, result} ->
          {:ok, result}

        {:error, reason} = error ->
          maybe_retry_install(pid, reason, retries_left, error)
      end
    end
  end

  @spec retryable_install_error?(Types.install_error()) :: boolean()
  def retryable_install_error?({:putbytes_failed, _meta, :timeout}), do: true
  def retryable_install_error?({:putbytes_failed, _meta, {:timeout, _observed}}), do: true
  def retryable_install_error?({:blob_insert_failed, _response}), do: true
  def retryable_install_error?(_reason), do: false

  defp maybe_retry_install(pid, reason, retries_left, error) when retries_left > 0 do
    if retryable_install_error?(reason) do
      Logger.debug(
        "embedded emulator install failed with retryable error #{inspect(reason)}; resetting QEMU and retrying"
      )

      Process.sleep(500)

      case GenServer.call(pid, :reset_for_install_retry, 90_000) do
        :ok ->
          do_install(pid, retries_left - 1)

        {:error, reset_reason} ->
          Logger.debug(
            "embedded emulator install retry reset failed #{inspect(reset_reason)} after #{inspect(reason)}"
          )

          _ = GenServer.call(pid, :restart_protocol_router, 10_000)
          {:error, {:install_retry_reset_failed, reset_reason, reason}}
      end
    else
      _ = GenServer.call(pid, :restart_protocol_router, 10_000)
      error
    end
  end

  defp maybe_retry_install(pid, _reason, _retries_left, error) do
    _ = GenServer.call(pid, :restart_protocol_router, 10_000)
    error
  end
end
