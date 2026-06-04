defmodule Ide.Emulator.Session do
  @moduledoc false

  use GenServer

  require Logger

  alias Ide.Emulator.{InstallPrep, LogCapture, SlotLimiter, Types}
  alias Ide.Emulator.PebbleProtocol.{Packets, Router}

  alias Ide.Emulator.Session.{
    Config,
    Control,
    Health,
    Info,
    Install,
    InstallCalls,
    Lifecycle,
    ProcessHost,
    Pypkjs,
    Qemu,
    RuntimeSetup,
    Startup,
    Vnc,
    VncHandlers
  }

  @type state :: Types.session_state()

  @spec generate_id() :: String.t()
  def generate_id, do: Lifecycle.random_id()

  @spec start_link(Types.session_launch_opts()) :: GenServer.on_start()
  def start_link(opts) do
    id = Keyword.get(opts, :id) || Lifecycle.random_id()
    GenServer.start_link(__MODULE__, Keyword.put(opts, :id, id), name: via(id))
  end

  @spec child_spec(Types.session_launch_opts()) :: Supervisor.child_spec()
  def child_spec(opts) do
    %{
      id: {__MODULE__, Keyword.get(opts, :id, make_ref())},
      start: {__MODULE__, :start_link, [opts]},
      restart: :temporary
    }
  end

  @spec info(pid()) :: Types.session_info()
  def info(pid), do: GenServer.call(pid, :info, 30_000)

  @spec artifact_file_path(pid()) :: String.t() | nil
  def artifact_file_path(pid), do: GenServer.call(pid, :artifact_file_path)

  @spec install(pid()) :: {:ok, Types.pbw_install_result()} | {:error, Types.session_error()}
  def install(pid) do
    try do
      with :ok <- GenServer.call(pid, :prepare_for_install, 90_000) do
        Install.do_install(pid, config(:native_install_retries, 4))
      end
    after
      _ = GenServer.call(pid, :install_finished, 5_000)
    catch
      :exit, {:timeout, _} -> {:error, :emulator_session_unresponsive}
      :exit, _ -> {:error, :emulator_session_unavailable}
    end
  end

  @doc false
  @spec install_reset_needed?(state()) :: boolean()
  def install_reset_needed?(state), do: InstallPrep.reset_needed?(state)

  @spec local_port(pid(), :vnc | :phone) :: pos_integer()
  def local_port(pid, kind) do
    GenServer.call(pid, {:local_port, kind}, local_port_call_timeout(kind))
  end

  @spec vnc_rfb_banner(pid()) :: {:ok, binary()} | {:error, :not_ready}
  def vnc_rfb_banner(pid) do
    GenServer.call(pid, :vnc_rfb_banner, 5_000)
  catch
    :exit, _ -> {:error, :not_ready}
  end

  @spec claim_vnc_tcp(pid()) ::
          {:ok, port(), binary()} | {:error, Types.session_atom_error() | :not_ready}
  def claim_vnc_tcp(pid) do
    GenServer.call(pid, :claim_vnc_tcp, 5_000)
  catch
    :exit, reason -> {:error, reason}
  end

  @spec return_vnc_tcp(pid(), port()) :: :ok
  def return_vnc_tcp(pid, tcp) when is_port(tcp) do
    GenServer.call(pid, {:return_vnc_tcp, tcp}, 5_000)
  catch
    :exit, _ -> :ok
  end

  @doc """
  Closes the session-held VNC TCP connection (if any) so a new client can connect.

  The cached RFB banner remains available via `vnc_rfb_banner/1`.
  """
  @spec discard_vnc_tcp(pid()) :: :ok
  def discard_vnc_tcp(pid) do
    GenServer.call(pid, :discard_vnc_tcp, 5_000)
  catch
    :exit, _ -> :ok
  end

  @spec control(pid(), non_neg_integer(), binary()) :: :ok | {:error, Types.session_error()}
  def control(pid, protocol, payload)
      when is_integer(protocol) and protocol >= 0 and protocol <= 255 and is_binary(payload) do
    GenServer.call(pid, {:control, protocol, payload}, 5_000)
  catch
    :exit, reason -> {:error, reason}
  end

  @spec apply_simulator_settings(pid(), Types.simulator_settings()) ::
          {:ok, Types.apply_settings_result()} | {:error, Types.apply_settings_error()}
  def apply_simulator_settings(pid, settings) when is_map(settings) do
    GenServer.call(pid, {:apply_simulator_settings, settings}, 10_000)
  catch
    :exit, {:timeout, _} -> {:error, :emulator_session_unresponsive}
    :exit, _ -> {:error, :emulator_session_unavailable}
  end

  @spec ping(pid()) :: {:ok, Types.session_info()} | {:error, Types.session_atom_error()}
  def ping(pid) do
    GenServer.call(pid, :ping, config(:ping_timeout_ms, 5_000))
  catch
    :exit, {:timeout, _} -> {:error, :emulator_session_unresponsive}
    :exit, _ -> {:error, :emulator_session_unavailable}
  end

  @app_log_endpoint 0x07D6

  @spec request_app_logs(pid()) :: :ok | {:error, Types.session_error()}
  def request_app_logs(pid) do
    GenServer.call(pid, :request_app_logs, 5_000)
  catch
    :exit, reason -> {:error, reason}
  end

  @spec log_capture_context(pid()) ::
          {:ok, map()} | {:error, Types.session_atom_error()}
  def log_capture_context(pid) do
    GenServer.call(pid, :log_capture_context, 5_000)
  catch
    :exit, reason -> {:error, reason}
  end

  @doc """
  Sends `AppRunStateStart` (phone → watch), which begins the AppFetch / PutBytes install handshake.

  PBW install already does this once at the start of `PBWInstaller.install/4`; do not call again
  immediately after a successful install — it retriggers AppFetch and can destabilize the app.
  """
  @spec start_app(pid(), String.t()) :: :ok | {:error, Types.session_error()}
  def start_app(pid, uuid) when is_binary(uuid) do
    GenServer.call(pid, {:start_app, uuid}, 5_000)
  catch
    :exit, reason -> {:error, reason}
  end

  @spec capture_logs(pid(), keyword()) :: LogCapture.snapshot()
  def capture_logs(pid, opts \\ []) do
    timeout_ms = log_capture_call_timeout(opts)
    GenServer.call(pid, {:capture_logs, opts}, timeout_ms)
  catch
    :exit, {:timeout, _} ->
      %{
        source: "embedded",
        duration_ms: Keyword.get(opts, :duration_ms, 5_000),
        output: "log capture timed out",
        lines: [],
        fault_detected: false,
        console: %{output: "", error: :timeout},
        protocol: %{lines: [], error: :timeout}
      }

    :exit, _ ->
      %{
        source: "embedded",
        duration_ms: Keyword.get(opts, :duration_ms, 5_000),
        output: "log capture unavailable",
        lines: [],
        fault_detected: false,
        console: %{output: "", error: :emulator_session_unavailable},
        protocol: %{lines: [], error: :emulator_session_unavailable}
      }
  end

  @spec health_check(pid()) :: :ok | {:error, Types.session_atom_error()}
  def health_check(pid) do
    GenServer.call(pid, :health_check, 1_000)
  catch
    :exit, {:timeout, _} -> {:error, :emulator_session_unresponsive}
    :exit, _ -> {:error, :emulator_session_unavailable}
  end

  @spec kill(pid()) :: :ok
  def kill(pid) do
    _ = GenServer.stop(pid, :normal, 1_000)
    :ok
  catch
    :exit, {:timeout, _} ->
      Process.exit(pid, :kill)
      :ok

    :exit, _ ->
      :ok
  end

  @impl true
  def init(opts) do
    Process.flag(:trap_exit, true)
    platform = RuntimeSetup.normalize_platform(Keyword.get(opts, :platform))

    with :ok <- RuntimeSetup.validate_runtime_requirements(platform),
         {:ok, state} <- Startup.build_state(Keyword.put(opts, :platform, platform)),
         {:ok, state} <- Startup.maybe_start_qemu(state),
         {:ok, state} <- Startup.maybe_start_protocol_router(state),
         {:ok, state} <- Startup.maybe_start_pypkjs_if_needed(state) do
      Lifecycle.schedule_idle_check(state)
      {:ok, state}
    else
      {:error, reason} ->
        {:stop, reason}
    end
  end

  @impl true
  def handle_call(:info, _from, state), do: {:reply, Info.public_info(state), state}

  def handle_call(:artifact_file_path, _from, state), do: {:reply, state.artifact_path, state}

  def handle_call(:install_context, _from, state), do: InstallCalls.install_context(state)

  def handle_call(:direct_install_context, _from, state),
    do: InstallCalls.direct_install_context(state)

  def handle_call(:protocol_router_pid, _from, %{protocol_router_pid: pid} = state)
      when is_pid(pid) do
    if ProcessHost.live_pid?(pid) do
      {:reply, {:ok, pid}, state}
    else
      {:reply, {:error, :embedded_protocol_router_not_started},
       %{state | protocol_router_pid: nil}}
    end
  end

  def handle_call(:protocol_router_pid, _from, state),
    do: {:reply, {:error, :embedded_protocol_router_not_started}, state}

  def handle_call({:local_port, :vnc}, _from, state), do: VncHandlers.local_port(state)

  def handle_call(:vnc_rfb_banner, _from, state), do: VncHandlers.rfb_banner(state)

  def handle_call(:claim_vnc_tcp, _from, state), do: VncHandlers.claim_tcp(state)

  def handle_call({:return_vnc_tcp, tcp}, _from, state) when is_port(tcp),
    do: VncHandlers.return_tcp(state, tcp)

  def handle_call(:discard_vnc_tcp, _from, state), do: VncHandlers.discard_tcp(state)

  def handle_call({:local_port, :phone}, _from, state), do: Pypkjs.handle_local_port(state)

  def handle_call({:control, protocol, payload}, _from, state),
    do: Control.handle_qemu_packet(state, protocol, payload)

  def handle_call({:apply_simulator_settings, settings}, _from, state) when is_map(settings),
    do: Control.apply_simulator_settings(state, settings)

  def handle_call(:restart_protocol_router, _from, state),
    do: InstallCalls.restart_protocol_router(state)

  def handle_call(:prepare_for_install, _from, state),
    do: InstallCalls.prepare_for_install(state)

  def handle_call(:install_finished, _from, state), do: InstallCalls.install_finished(state)

  def handle_call(:reset_for_install, _from, state), do: InstallCalls.reset_for_install(state)

  def handle_call(:reset_for_install_retry, _from, state),
    do: InstallCalls.reset_for_install_retry(state)

  def handle_call(:restart_pypkjs, _from, state), do: InstallCalls.restart_pypkjs(state)

  def handle_call(:request_app_logs, _from, %{protocol_router_pid: pid} = state) when is_pid(pid) do
    if ProcessHost.live_pid?(pid) do
      :ok = Router.send_packet(pid, @app_log_endpoint, <<1>>)
      {:reply, :ok, state}
    else
      {:reply, {:error, :embedded_protocol_router_not_started},
       %{state | protocol_router_pid: nil}}
    end
  end

  def handle_call(:request_app_logs, _from, state),
    do: {:reply, {:error, :embedded_protocol_router_not_started}, state}

  def handle_call(:log_capture_context, _from, state) do
    {:reply,
     {:ok,
      %{
        console_port: state.console_port,
        protocol_router_pid: state.protocol_router_pid
      }}, state}
  end

  def handle_call({:start_app, uuid}, _from, %{protocol_router_pid: pid} = state) when is_pid(pid) do
    if ProcessHost.live_pid?(pid) do
      {endpoint, payload} = Packets.app_run_state_start(uuid)
      :ok = Router.send_packet(pid, endpoint, payload)
      {:reply, :ok, state}
    else
      {:reply, {:error, :embedded_protocol_router_not_started},
       %{state | protocol_router_pid: nil}}
    end
  end

  def handle_call({:start_app, _uuid}, _from, state),
    do: {:reply, {:error, :embedded_protocol_router_not_started}, state}

  def handle_call({:capture_logs, opts}, _from, state) do
    snapshot =
      LogCapture.snapshot(
        %{
          console_port: state.console_port,
          protocol_router_pid: state.protocol_router_pid
        },
        opts
      )

    {:reply, snapshot, state}
  end

  def handle_call(:health_check, _from, state), do: {:reply, Health.check(state), state}

  def handle_call(:ping, _from, %{installing?: true} = state) do
    {:reply, {:ok, Info.public_info(state)}, %{state | last_ping_ms: Lifecycle.now_ms()}}
  end

  def handle_call(:ping, _from, state) do
    reply =
      with :ok <- Health.check(state) do
        {:ok, Info.public_info(state)}
      end

    state =
      case reply do
        {:ok, _} -> %{state | last_ping_ms: Lifecycle.now_ms()}
        _ -> state
      end

    {:reply, reply, state}
  end

  @impl true
  def handle_info(:idle_check, state), do: Lifecycle.handle_idle_check(state)

  def handle_info({:EXIT, pid, reason}, state), do: Health.handle_exit(state, pid, reason)

  def handle_info({:tcp, tcp, data}, state) when is_binary(data),
    do: VncHandlers.append_tcp_data(state, tcp, data)

  def handle_info(_message, state), do: {:noreply, state}
  @impl true
  def terminate(_reason, state) do
    Vnc.close_tcp_port(state.vnc_tcp)
    ProcessHost.cleanup_process(state.qemu_pid)
    ProcessHost.cleanup_process(state.pypkjs_pid)
    ProcessHost.cleanup_process(state.protocol_router_pid)
    SlotLimiter.release(state.id)
    :ok
  end

  @spec qemu_args(Types.qemu_args_state() | Types.session_state()) :: [String.t()]
  def qemu_args(state), do: Qemu.args(state)

  @spec pypkjs_args(Types.pypkjs_args_state()) :: [String.t()]
  def pypkjs_args(state), do: Pypkjs.args(state)

  @spec machine_args(String.t(), String.t() | nil, Qemu.features()) :: [String.t()]
  def machine_args(
        platform,
        spi_image_path,
        qemu_features \\ %{new_qemu?: false, machines: MapSet.new()}
      ),
      do: Qemu.machine_args(platform, spi_image_path, qemu_features)

  @spec pypkjs_command(String.t()) ::
          {:ok, String.t(), [String.t()]} | {:error, Types.session_atom_error()}
  def pypkjs_command(pypkjs_bin), do: Pypkjs.command(pypkjs_bin)

  @spec tcp_port_open?(pos_integer()) :: boolean()
  def tcp_port_open?(port), do: ProcessHost.tcp_port_open?(port)

  @spec runtime_status(String.t() | nil) :: Types.runtime_status()
  def runtime_status(platform \\ nil), do: RuntimeSetup.runtime_status(platform)

  @spec install_runtime_dependencies(String.t() | nil) ::
          {:ok, Types.install_dependencies_result()}
  def install_runtime_dependencies(platform \\ nil),
    do: RuntimeSetup.install_runtime_dependencies(platform)

  defp local_port_call_timeout(kind), do: Pypkjs.local_port_call_timeout(kind)

  defp via(id), do: {:via, Registry, {Ide.Emulator.Registry, id}}

  defp config(key, default), do: Config.config(key, default)

  defp log_capture_call_timeout(opts) do
    duration_ms =
      case Keyword.get(opts, :duration_ms) do
        ms when is_integer(ms) and ms > 0 -> ms
        _ -> nil
      end

    duration_ms =
      duration_ms ||
        case Keyword.get(opts, :logs_snapshot_seconds) do
          seconds when is_integer(seconds) and seconds > 0 -> seconds * 1_000
          _ -> nil
        end

    duration_ms = duration_ms || 5_000
    min(duration_ms, 30_000) + 10_000
  end
end
