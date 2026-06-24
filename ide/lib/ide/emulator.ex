defmodule Ide.Emulator do
  @moduledoc """
  Runtime boundary for embedded Pebble emulator sessions.
  """

  alias Ide.Emulator.{LogCapture, Screenshot, Session, Session.RuntimeSetup, SlotLimiter, Types}

  @type launch_opts :: Types.launch_opts()

  @spec launch(launch_opts()) :: {:ok, Types.session_info()} | {:error, Types.emulator_error()}
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

  @spec runtime_status(String.t() | nil) :: Types.runtime_status()
  def runtime_status(platform \\ nil), do: RuntimeSetup.runtime_status(platform)

  @spec install_runtime_dependencies(String.t() | nil) ::
          {:ok, Types.install_dependencies_result()}
  def install_runtime_dependencies(platform \\ nil),
    do: RuntimeSetup.install_runtime_dependencies(platform)

  @spec lookup(String.t()) :: {:ok, pid()} | {:error, :not_found}
  def lookup(id) when is_binary(id) do
    case Registry.lookup(Ide.Emulator.Registry, id) do
      [{pid, _}] -> {:ok, pid}
      [] -> {:error, :not_found}
    end
  end

  @spec info(String.t()) :: {:ok, Types.session_info()} | {:error, Types.session_atom_error()}
  def info(id) when is_binary(id) do
    with {:ok, pid} <- lookup(id) do
      {:ok, Session.info(pid)}
    end
  end

  @spec ping(String.t()) :: {:ok, Types.session_info()} | {:error, Types.session_error()}
  def ping(id) when is_binary(id) do
    with {:ok, pid} <- lookup(id) do
      Session.ping(pid)
    end
  end

  @spec health_check(String.t()) ::
          {:ok, :ok | {:error, Types.session_error()}} | {:error, :not_found}
  def health_check(id) when is_binary(id) do
    with {:ok, pid} <- lookup(id) do
      {:ok, Session.health_check(pid)}
    end
  end

  @spec request_app_logs(String.t()) :: :ok | {:error, Types.session_error()}
  def request_app_logs(id) when is_binary(id) do
    with {:ok, pid} <- lookup(id) do
      Session.request_app_logs(pid)
    end
  end

  @spec log_capture_context(String.t()) ::
          {:ok, LogCapture.capture_context()} | {:error, Types.session_error()}
  def log_capture_context(id) when is_binary(id) do
    with {:ok, pid} <- lookup(id) do
      Session.log_capture_context(pid)
    end
  end

  @doc """
  Sends `AppRunStateStart` on the session protocol router (install / AppFetch handshake).

  See `Ide.Emulator.Session.start_app/2`. Prefer `install/1` for PBW delivery; avoid calling
  this immediately after a successful install.
  """
  @spec start_app(String.t(), String.t()) :: :ok | {:error, Types.session_error()}
  def start_app(id, uuid) when is_binary(id) and is_binary(uuid) do
    with {:ok, pid} <- lookup(id) do
      Session.start_app(pid, uuid)
    end
  end

  @spec capture_logs(String.t(), keyword()) :: Ide.Emulator.LogCapture.snapshot()
  def capture_logs(id, opts \\ []) when is_binary(id) do
    with {:ok, pid} <- lookup(id) do
      Session.capture_logs(pid, opts)
    else
      {:error, :not_found} ->
        %{
          source: "embedded",
          duration_ms: 0,
          output: "emulator session not found",
          lines: [],
          fault_detected: false,
          console: %{output: "", error: :not_found},
          protocol: %{lines: [], error: :not_found}
        }
    end
  end

  @spec install(String.t()) :: {:ok, Types.pbw_install_result()} | {:error, Types.session_error()}
  def install(id) when is_binary(id) do
    with {:ok, pid} <- lookup(id) do
      Session.install(pid)
    end
  end

  @spec control(String.t(), non_neg_integer(), binary()) :: :ok | {:error, Types.session_error()}
  def control(id, protocol, payload)
      when is_binary(id) and is_integer(protocol) and is_binary(payload) do
    with {:ok, pid} <- lookup(id) do
      Session.control(pid, protocol, payload)
    end
  end

  @spec apply_simulator_settings(String.t(), Types.simulator_settings()) ::
          {:ok, Types.apply_settings_result()}
          | {:error, Types.apply_settings_error() | Types.session_atom_error()}
  def apply_simulator_settings(id, settings) when is_binary(id) and is_map(settings) do
    case lookup(id) do
      {:ok, pid} -> Session.apply_simulator_settings(pid, settings)
      {:error, :not_found} = not_found -> not_found
    end
  end

  @spec screenshot(String.t(), Types.screenshot_capture_opts()) ::
          {:ok, binary()} | {:error, Types.emulator_error()}
  def screenshot(id, opts \\ []) when is_binary(id) do
    with {:ok, pid} <- lookup(id),
         {:ok, %{platform: platform}} <- info(id) do
      Screenshot.capture(pid, platform, opts)
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
