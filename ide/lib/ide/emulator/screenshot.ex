defmodule Ide.Emulator.Screenshot do
  @moduledoc """
  Captures emulator watchface screenshots via firmware protocol, with VNC fallback.
  """

  require Logger

  alias Ide.Emulator.{FirmwareScreenshot, Session, VncScreenshot}
  alias Ide.Emulator.Types

  @vnc_fallback_cap_ms 30_000

  @spec capture_timeout_ms(String.t()) :: pos_integer()
  def capture_timeout_ms(platform) when is_binary(platform),
    do: FirmwareScreenshot.capture_timeout_ms(platform)

  @spec capture(pid(), String.t(), Types.screenshot_capture_opts()) ::
          {:ok, binary()} | {:error, Types.emulator_error()}
  def capture(session_pid, platform, opts \\ [])
      when is_pid(session_pid) and is_binary(platform) do
    timeout = capture_timeout(platform, opts)

    case FirmwareScreenshot.capture(session_pid, platform, timeout: timeout) do
      {:ok, png} when is_binary(png) ->
        {:ok, png}

      {:error, reason} ->
        Logger.warning("firmware screenshot failed, falling back to VNC: #{inspect(reason)}")
        capture_vnc(session_pid, platform, timeout)
    end
  end

  @spec capture_vnc(pid(), String.t(), timeout()) ::
          {:ok, binary()} | {:error, Types.emulator_error()}
  def capture_vnc(session_pid, platform, firmware_timeout)
      when is_pid(session_pid) and is_binary(platform) do
    vnc_timeout = min(firmware_timeout, @vnc_fallback_cap_ms)

    with port when is_integer(port) and port > 0 <- Session.local_port(session_pid, :vnc),
         {:ok, png} when is_binary(png) <-
           VncScreenshot.capture(port, platform: platform, timeout: vnc_timeout) do
      {:ok, png}
    else
      {:error, reason} -> {:error, reason}
      _ -> {:error, :vnc_unavailable}
    end
  end

  defp capture_timeout(platform, opts) do
    Keyword.get_lazy(opts, :timeout, fn -> capture_timeout_ms(platform) end)
  end
end
