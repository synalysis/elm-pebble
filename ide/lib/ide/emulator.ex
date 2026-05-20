defmodule Ide.Emulator do
  @moduledoc """
  Runtime boundary for embedded Pebble emulator sessions.
  """

  alias Ide.Emulator.{Session, SlotLimiter}

  @type launch_opts :: [
          project_slug: String.t(),
          platform: String.t(),
          artifact_path: String.t() | nil,
          has_phone_companion: boolean()
        ]

  @spec launch(launch_opts()) :: {:ok, map()} | {:error, term()}
  def launch(opts) do
    id = Keyword.get(opts, :id) || Session.generate_id()
    platform = Keyword.get(opts, :platform)
    opts = Keyword.put(opts, :id, id)

    with {:ok, ^id} <-
           SlotLimiter.acquire(id,
             kind: :embedded,
             platform: platform,
             timeout: launch_acquire_timeout(opts)
           ) do
      launch_with_slot(id, opts)
    end
  end

  defp launch_with_slot(id, opts) do
    spec = Session.child_spec(opts)

    case DynamicSupervisor.start_child(Ide.Emulator.SessionSupervisor, spec) do
      {:ok, pid} ->
        {:ok, Session.info(pid)}

      {:error, {:already_started, pid}} ->
        {:ok, Session.info(pid)}

      {:error, _reason} = error ->
        SlotLimiter.release(id)
        error
    end
  end

  defp launch_acquire_timeout(opts) do
    Keyword.get(opts, :slot_acquire_timeout_ms) ||
      Application.get_env(:ide, Ide.Emulator.SlotLimiter, [])
      |> Keyword.get(:acquire_timeout_ms, 600_000)
  end

  @doc false
  @spec release_slot(String.t()) :: :ok
  def release_slot(id) when is_binary(id), do: SlotLimiter.release(id)

  @spec slot_status() :: Ide.Emulator.SlotLimiter.status()
  def slot_status, do: SlotLimiter.status()

  @spec runtime_status(term()) :: map()
  def runtime_status(platform \\ nil), do: Session.runtime_status(platform)

  @spec install_runtime_dependencies(term()) :: {:ok, map()} | {:error, term()}
  def install_runtime_dependencies(platform \\ nil),
    do: Session.install_runtime_dependencies(platform)

  @spec lookup(String.t()) :: {:ok, pid()} | {:error, :not_found}
  def lookup(id) when is_binary(id) do
    case Registry.lookup(Ide.Emulator.Registry, id) do
      [{pid, _}] -> {:ok, pid}
      [] -> {:error, :not_found}
    end
  end

  @spec info(String.t()) :: {:ok, map()} | {:error, term()}
  def info(id) when is_binary(id) do
    with {:ok, pid} <- lookup(id) do
      {:ok, Session.info(pid)}
    end
  end

  @spec ping(String.t()) :: {:ok, map()} | {:error, term()}
  def ping(id) when is_binary(id) do
    with {:ok, pid} <- lookup(id) do
      Session.ping(pid)
    end
  end

  @spec health_check(String.t()) :: {:ok, :ok | {:error, term()}} | {:error, term()}
  def health_check(id) when is_binary(id) do
    with {:ok, pid} <- lookup(id) do
      {:ok, Session.health_check(pid)}
    end
  end

  @spec install(String.t()) :: {:ok, map()} | {:error, term()}
  def install(id) when is_binary(id) do
    with {:ok, pid} <- lookup(id) do
      Session.install(pid)
    end
  end

  @spec control(String.t(), non_neg_integer(), binary()) :: :ok | {:error, term()}
  def control(id, protocol, payload)
      when is_binary(id) and is_integer(protocol) and is_binary(payload) do
    with {:ok, pid} <- lookup(id) do
      Session.control(pid, protocol, payload)
    end
  end

  @spec screenshot(String.t(), keyword()) :: {:ok, binary()} | {:error, term()}
  def screenshot(id, opts \\ []) when is_binary(id) do
    with {:ok, pid} <- lookup(id),
         {:ok, %{platform: platform}} <- info(id) do
      timeout = screenshot_capture_timeout(platform, opts)

      case Ide.Emulator.FirmwareScreenshot.capture(pid, platform, timeout: timeout) do
        {:ok, png} when is_binary(png) ->
          {:ok, png}

        {:error, reason} ->
          require Logger
          Logger.warning("firmware screenshot failed, falling back to VNC: #{inspect(reason)}")
          capture_vnc_screenshot(pid, platform, timeout)
      end
    end
  end

  defp screenshot_capture_timeout(platform, opts) do
    Keyword.get_lazy(opts, :timeout, fn ->
      Ide.Emulator.FirmwareScreenshot.capture_timeout_ms(platform)
    end)
  end

  defp capture_vnc_screenshot(pid, platform, firmware_timeout) do
    vnc_timeout = min(firmware_timeout, 30_000)

    with port when is_integer(port) and port > 0 <- Session.local_port(pid, :vnc),
         {:ok, png} when is_binary(png) <-
           Ide.Emulator.VncScreenshot.capture(port,
             platform: platform,
             timeout: vnc_timeout
           ) do
      {:ok, png}
    else
      {:error, :not_found} -> {:error, :emulator_not_found}
      :ok -> {:error, :vnc_capture_failed}
      nil -> {:error, :emulator_vnc_not_ready}
      {:error, reason} -> {:error, reason}
      other -> {:error, other}
    end
  end

  @spec kill(String.t()) :: :ok
  def kill(id) when is_binary(id) do
    case lookup(id) do
      {:ok, pid} -> Session.kill(pid)
      {:error, :not_found} -> :ok
    end
  end
end
