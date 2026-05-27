defmodule Ide.Emulator.Session do
  @moduledoc false

  use GenServer

  require Logger

  alias Ide.Debugger.SimulatorSettings
  alias Ide.Emulator.{InstallPrep, PBW, QemuControl, SlotLimiter, Types}
  alias Ide.Emulator.Session.{
    Bins,
    Config,
    Install,
    ProcessHost,
    Pypkjs,
    Qemu,
    RuntimeSetup,
    Vnc
  }
  alias Ide.Emulator.PebbleProtocol.Router
  alias Ide.WatchModels

  @default_idle_timeout_ms 5 * 60 * 1000

  @type state :: %{
          id: String.t(),
          token: String.t(),
          project_slug: String.t(),
          platform: String.t(),
          artifact_path: String.t() | nil,
          app_uuid: String.t() | nil,
          has_phone_companion: boolean(),
          has_companion_preferences: boolean(),
          console_port: pos_integer(),
          bt_port: pos_integer(),
          protocol_proxy_port: pos_integer(),
          phone_ws_port: pos_integer(),
          vnc_port: pos_integer(),
          vnc_display: non_neg_integer(),
          vnc_ws_port: pos_integer(),
          protocol_router_pid: pid() | nil,
          qemu_pid: pid() | nil,
          pypkjs_pid: pid() | nil,
          spi_image_path: String.t() | nil,
          persist_dir: String.t() | nil,
          last_ping_ms: integer(),
          last_boot_ms: integer(),
          idle_timeout_ms: pos_integer(),
          vnc_banner_ready: boolean(),
          vnc_rfb_banner: binary() | nil,
          vnc_tcp: port() | nil,
          vnc_tcp_buffer: binary(),
          installing?: boolean(),
          qemu_features: Qemu.features()
        }

  @spec generate_id() :: String.t()
  def generate_id, do: random_id()

  @spec start_link(Types.session_launch_opts()) :: GenServer.on_start()
  def start_link(opts) do
    id = Keyword.get(opts, :id) || random_id()
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

  @spec claim_vnc_tcp(pid()) :: {:ok, port(), binary()} | {:error, Types.session_atom_error() | :not_ready}
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
         {:ok, state} <- build_state(Keyword.put(opts, :platform, platform)),
         {:ok, state} <- maybe_start_qemu(state),
         {:ok, state} <- maybe_start_protocol_router(state),
         {:ok, state} <- maybe_start_pypkjs_if_needed(state) do
      schedule_idle_check(state)
      {:ok, state}
    else
      {:error, reason} ->
  
        {:stop, reason}
    end
  end

  @impl true
  def handle_call(:info, _from, state), do: {:reply, public_info(state), state}

  def handle_call(:artifact_file_path, _from, state), do: {:reply, state.artifact_path, state}

  def handle_call(:install_context, _from, %{artifact_path: nil} = state),
    do: {:reply, {:error, :artifact_not_found}, state}

  def handle_call(:install_context, _from, %{protocol_router_pid: nil} = state),
    do: {:reply, {:error, :embedded_protocol_router_not_started}, state}

  def handle_call(:install_context, _from, state) do
    state =
      if Map.get(state, :has_phone_companion, false) do
        state
      else
        ProcessHost.cleanup_process(state.pypkjs_pid)
        %{state | pypkjs_pid: nil}
      end

    {:reply,
     {:ok,
      %{
        protocol_router_pid: state.protocol_router_pid,
        artifact_path: state.artifact_path,
        platform: state.platform,
        console_port: state.console_port
      }}, state}
  end

  def handle_call(:direct_install_context, _from, %{qemu_pid: nil} = state),
    do: {:reply, {:error, :embedded_protocol_router_not_started}, state}

  def handle_call(:direct_install_context, _from, state) do
    ProcessHost.cleanup_process(state.pypkjs_pid)
    ProcessHost.cleanup_process(state.protocol_router_pid)

    {:reply,
     {:ok,
      %{
        qemu_port: state.bt_port,
        artifact_path: state.artifact_path,
        platform: state.platform,
        app_uuid: state.app_uuid
      }}, %{state | pypkjs_pid: nil, protocol_router_pid: nil, installing?: true}}
  end

  def handle_call(:protocol_router_pid, _from, %{protocol_router_pid: pid} = state)
      when is_pid(pid) do
    if ProcessHost.live_pid?(pid) do
      {:reply, {:ok, pid}, state}
    else
      {:reply, {:error, :embedded_protocol_router_not_started}, %{state | protocol_router_pid: nil}}
    end
  end

  def handle_call(:protocol_router_pid, _from, state),
    do: {:reply, {:error, :embedded_protocol_router_not_started}, state}

  def handle_call({:local_port, :vnc}, _from, state), do: {:reply, state.vnc_port, state}

  def handle_call(:vnc_rfb_banner, _from, %{vnc_rfb_banner: banner} = state) when is_binary(banner) do
    {:reply, {:ok, banner}, state}
  end

  def handle_call(:vnc_rfb_banner, _from, state), do: {:reply, {:error, :not_ready}, state}

  def handle_call(:claim_vnc_tcp, _from, %{vnc_tcp: tcp} = state) when is_port(tcp) do
    buffer = Map.get(state, :vnc_tcp_buffer, <<>>)
    {:reply, {:ok, tcp, buffer}, %{state | vnc_tcp: nil, vnc_tcp_buffer: <<>>}}
  end

  def handle_call(:claim_vnc_tcp, _from, state),
    do: {:reply, {:error, :vnc_tcp_unavailable}, state}

  def handle_call({:return_vnc_tcp, tcp}, _from, %{vnc_tcp: nil} = state) when is_port(tcp) do
    :inet.setopts(tcp, active: true, nodelay: true, packet: :raw)

    {:reply, :ok, %{state | vnc_tcp: tcp}}
  end

  def handle_call({:return_vnc_tcp, tcp}, _from, state) when is_port(tcp) do
    :gen_tcp.close(tcp)
    {:reply, :ok, state}
  end

  def handle_call(:discard_vnc_tcp, _from, %{vnc_tcp: tcp} = state) when is_port(tcp) do
    :gen_tcp.close(tcp)
    {:reply, :ok, %{state | vnc_tcp: nil, vnc_tcp_buffer: <<>>}}
  end

  def handle_call(:discard_vnc_tcp, _from, state), do: {:reply, :ok, state}

  def handle_call({:local_port, :phone}, _from, %{pypkjs_pid: nil} = state) do
    case maybe_start_pypkjs(state) do
      {:ok, state} ->
  
        {:reply, state.phone_ws_port, state}

      {:error, reason} ->
  
        {:reply, {:error, reason}, state}
    end
  end

  def handle_call({:local_port, :phone}, _from, state), do: {:reply, state.phone_ws_port, state}

  def handle_call({:control, protocol, payload}, _from, state) do
    with :ok <- QemuControl.validate_payload(protocol, payload) do
      if ProcessHost.live_pid?(state.protocol_router_pid) do
        {:reply, Router.send_qemu_packet(state.protocol_router_pid, protocol, payload), state}
      else
        {:reply, {:error, :embedded_protocol_router_not_started},
         %{state | protocol_router_pid: nil}}
      end
    else
      {:error, reason} -> {:reply, {:error, reason}, state}
    end
  end

  def handle_call({:apply_simulator_settings, settings}, _from, state) when is_map(settings) do
    normalized = SimulatorSettings.normalize(settings)

    commands = QemuControl.commands_from_simulator_settings(normalized)

    if ProcessHost.live_pid?(state.protocol_router_pid) do
      result =
        Enum.reduce_while(commands, :ok, fn %{protocol: protocol, payload: payload}, :ok ->
          with :ok <- QemuControl.validate_payload(protocol, payload),
               :ok <- Router.send_qemu_packet(state.protocol_router_pid, protocol, payload) do
            {:cont, :ok}
          else
            {:error, reason} -> {:halt, {:error, reason}}
          end
        end)

      case result do
        :ok ->
          {:reply,
           {:ok,
            %{
              applied: length(commands),
              protocols: Enum.map(commands, & &1.protocol)
            }}, state}

        {:error, reason} ->
          {:reply, {:error, reason}, state}
      end
    else
      case validate_simulator_setting_commands(commands) do
        :ok ->
          {:reply,
           {:ok,
            %{
              applied: length(commands),
              protocols: Enum.map(commands, & &1.protocol)
            }}, state}

        {:error, reason} ->
          {:reply, {:error, reason}, state}
      end
    end
  end

  def handle_call(:restart_protocol_router, _from, %{protocol_router_pid: nil} = state) do
    case maybe_start_protocol_router(state) do
      {:ok, state} -> {:reply, :ok, %{state | installing?: false}}
      {:error, reason} -> {:reply, {:error, reason}, %{state | installing?: false}}
    end
  end

  def handle_call(:restart_protocol_router, _from, state), do: {:reply, :ok, state}

  def handle_call(:prepare_for_install, _from, state) do
    reuse? = not install_reset_needed?(state)

    Logger.debug(
      "embedded emulator prepare_for_install session=#{state.id} platform=#{state.platform} reuse_qemu=#{reuse?}"
    )

    result =
      if reuse? do
        prepare_running_session_for_install(state)
      else
        with {:ok, state} <- reset_for_install(state),
             {:ok, state} <- maybe_start_pypkjs_if_needed(state) do
          {:ok, state}
        end
      end

    case result do
      {:ok, state} ->
        {:reply, :ok, state}

      {:error, reason} ->
        {:reply, {:error, reason}, %{state | installing?: false}}
    end
  end

  def handle_call(:install_finished, _from, state) do
    state = %{state | installing?: false, last_ping_ms: now_ms()}

    state =
      if Map.get(state, :has_phone_companion, false) and not ProcessHost.live_pid?(state.pypkjs_pid) do
        case maybe_start_pypkjs(state) do
          {:ok, state} -> state
          {:error, _reason} -> state
        end
      else
        state
      end

    {:reply, :ok, state}
  end

  def handle_call(:reset_for_install, _from, state) do
    Logger.debug(
      "embedded emulator reset_for_install session=#{state.id} platform=#{state.platform}"
    )

    case reset_for_install(state) do
      {:ok, state} ->
        {:reply, :ok, state}

      {:error, reason} ->
        {:reply, {:error, reason}, %{state | installing?: false}}
    end
  end

  def handle_call(:reset_for_install_retry, _from, state) do
    case reset_for_install(state) do
      {:ok, state} -> {:reply, :ok, state}
      {:error, reason} -> {:reply, {:error, reason}, %{state | installing?: false}}
    end
  end

  def handle_call(:restart_pypkjs, _from, %{pypkjs_pid: nil} = state) do
    case maybe_start_pypkjs(state) do
      {:ok, state} -> {:reply, :ok, state}
      {:error, reason} -> {:reply, {:error, reason}, state}
    end
  end

  def handle_call(:restart_pypkjs, _from, state), do: {:reply, :ok, state}

  def handle_call(:health_check, _from, state) do
    {:reply, session_health(state), state}
  end

  def handle_call(:ping, _from, %{installing?: true} = state) do
    {:reply, {:ok, public_info(state)}, %{state | last_ping_ms: now_ms()}}
  end

  def handle_call(:ping, _from, state) do
    case session_health(state) do
      :ok ->
        state = %{state | last_ping_ms: now_ms()}
        {:reply, {:ok, public_info(state)}, state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_info(:idle_check, state) do
    if now_ms() - state.last_ping_ms > state.idle_timeout_ms do
      {:stop, {:shutdown, :idle_timeout}, state}
    else
      schedule_idle_check(state)
      {:noreply, state}
    end
  end

  def handle_info({:EXIT, pid, reason}, state) do
    case session_child_role(state, pid) do
      nil when reason in [:normal, :shutdown] ->
        {:noreply, state}

      nil ->
        Logger.debug("embedded emulator linked process exited: #{inspect(reason)}")
        {:noreply, state}

      :pypkjs ->
  
        Logger.debug("embedded emulator pypkjs exited: #{inspect(reason)}")
        {:noreply, %{state | pypkjs_pid: nil}}

      role ->
  
        Logger.debug("embedded emulator #{role} exited: #{inspect(reason)}")
        {:stop, {:shutdown, {:child_exited, role, reason}}, state}
    end
  end

  def handle_info({:tcp, tcp, data}, %{vnc_tcp: tcp} = state) when is_binary(data) do
    {:noreply, Vnc.append_tcp_buffer(state, data)}
  end

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

  @spec qemu_args(map()) :: [String.t()]
  def qemu_args(state), do: Qemu.args(state)

  @spec pypkjs_args(map()) :: [String.t()]
  def pypkjs_args(state), do: Pypkjs.args(state)

  @spec machine_args(String.t(), String.t() | nil, Qemu.features()) :: [String.t()]
  def machine_args(platform, spi_image_path, qemu_features \\ %{new_qemu?: false, machines: MapSet.new()}),
    do: Qemu.machine_args(platform, spi_image_path, qemu_features)

  @spec pypkjs_command(String.t()) ::
          {:ok, String.t(), [String.t()]} | {:error, Types.session_atom_error()}
  def pypkjs_command(pypkjs_bin), do: Pypkjs.command(pypkjs_bin)

  @spec tcp_port_open?(pos_integer()) :: boolean()
  def tcp_port_open?(port), do: ProcessHost.tcp_port_open?(port)

  @spec runtime_status(String.t() | nil) :: Types.runtime_status()
  def runtime_status(platform \\ nil), do: RuntimeSetup.runtime_status(platform)

  @spec install_runtime_dependencies(String.t() | nil) :: {:ok, Types.install_dependencies_result()}
  def install_runtime_dependencies(platform \\ nil),
    do: RuntimeSetup.install_runtime_dependencies(platform)

  defp build_state(opts) do
    platform = Keyword.fetch!(opts, :platform)
    project_slug = Keyword.get(opts, :project_slug, "")
    artifact_path = Keyword.get(opts, :artifact_path)

    with {:ok, ports} <- ProcessHost.allocate_ports(6),
         {:ok, spi_image_path} <- Qemu.make_spi_image(platform, project_slug),
         {:ok, persist_dir} <- Qemu.make_persist_dir(platform, project_slug) do
      [console_port, bt_port, protocol_proxy_port, phone_ws_port, vnc_port, vnc_ws_port] = ports

      {:ok,
       %{
         id: Keyword.fetch!(opts, :id),
         token: random_token(),
         project_slug: project_slug,
         platform: platform,
         artifact_path: artifact_path,
         app_uuid: app_uuid(artifact_path, platform),
         has_phone_companion: Keyword.get(opts, :has_phone_companion, false),
         has_companion_preferences: Keyword.get(opts, :has_companion_preferences, false),
         console_port: console_port,
         bt_port: bt_port,
         protocol_proxy_port: protocol_proxy_port,
         phone_ws_port: phone_ws_port,
         vnc_port: vnc_port,
         vnc_display: max(vnc_port - 5900, 0),
         vnc_ws_port: vnc_ws_port,
         protocol_router_pid: nil,
         qemu_pid: nil,
         pypkjs_pid: nil,
         qemu_features: Qemu.features(),
         spi_image_path: spi_image_path,
         persist_dir: persist_dir,
         installing?: false,
         last_ping_ms: now_ms(),
         last_boot_ms: 0,
         idle_timeout_ms: Config.config(:idle_timeout_ms, @default_idle_timeout_ms),
         vnc_banner_ready: false,
         vnc_rfb_banner: nil,
         vnc_tcp: nil,
         vnc_tcp_buffer: <<>>
       }}
    end
  end

  defp maybe_start_qemu(state), do: maybe_start_qemu(state, true)

  defp maybe_start_qemu(state, allow_flash_reset?) do
    if Config.start_processes?() do
      with {:ok, qemu_bin} <- Bins.qemu_bin(),
           {:ok, pid} <- ProcessHost.start_daemon(qemu_bin, qemu_args(state), "qemu:#{state.id}") do
        case ProcessHost.wait_for_qemu_boot(pid, state.console_port, 60_000) do
          :ok ->
            # wait_for_qemu_boot already blocks on Qemu.boot_markers/0 ("Ready for communication").
            # Do not open a second console session for the same marker — it will never reappear and
            # adds a full install_ready_console_timeout_ms stall to every launch.
            with :ok <- Vnc.wait_for_tcp_port(state.vnc_port, Config.config(:vnc_ready_timeout_ms, 30_000)),
                 {:ok, vnc_rfb_banner, vnc_tcp} <-
                   Vnc.capture_rfb_connection(
                     state.vnc_port,
                     Config.config(:vnc_rfb_ready_timeout_ms, 15_000)
                   ) do
              {:ok,
               %{
                 state
                 | qemu_pid: pid,
                   last_boot_ms: now_ms(),
                   vnc_banner_ready: true,
                   vnc_rfb_banner: vnc_rfb_banner,
                   vnc_tcp: vnc_tcp,
                   vnc_tcp_buffer: <<>>
               }}
            else
              {:error, reason} ->
                ProcessHost.cleanup_process(pid)
                {:error, reason}
            end

          {:error, {:qemu_boot_firmware_failure, _tail}} when allow_flash_reset? ->
            ProcessHost.cleanup_process(pid)

            with {:ok, _path} <- Qemu.reset_spi_image(state.platform, state.spi_image_path) do
              maybe_start_qemu(state, false)
            end

          {:error, reason} ->
            ProcessHost.cleanup_process(pid)
            {:error, reason}
        end
      end
    else
      {:ok, state}
    end
  end

  defp maybe_start_protocol_router(state) do
    if Config.start_processes?() do
      case Router.start_link(qemu_port: state.bt_port, proxy_port: state.protocol_proxy_port) do
        {:ok, pid} -> {:ok, %{state | protocol_router_pid: pid}}
        {:error, reason} -> {:error, {:protocol_router_start_failed, reason}}
      end
    else
      {:ok, state}
    end
  end

  defp maybe_start_pypkjs_if_needed(state) do
    if Config.start_processes?() do
      case Pypkjs.maybe_start(state) do
        {:ok, state} ->
          {:ok, state}

        {:error, reason} ->
          Logger.warning("embedded emulator pypkjs unavailable: #{inspect(reason)}")
          {:ok, state}
      end
    else
      {:ok, state}
    end
  end

  defp maybe_start_pypkjs(state), do: Pypkjs.maybe_start(state)

  defp local_port_call_timeout(kind), do: Pypkjs.local_port_call_timeout(kind)

  @spec public_info(state()) :: Types.session_info()
  defp public_info(state) do
    profile = WatchModels.profile_for(state.platform)
    screen = WatchModels.profile_screen(profile)

    %{
      id: state.id,
      token: state.token,
      project_slug: state.project_slug,
      platform: state.platform,
      artifact_path: "/api/emulator/#{state.id}/artifact",
      app_uuid: state.app_uuid,
      has_phone_companion: state.has_phone_companion,
      has_companion_preferences: state.has_companion_preferences,
      install_path: "/api/emulator/#{state.id}/install",
      vnc_path: "/api/emulator/#{state.id}/ws/vnc",
      phone_path: "/api/emulator/#{state.id}/ws/phone",
      ping_path: "/api/emulator/#{state.id}/ping",
      kill_path: "/api/emulator/#{state.id}/kill",
      screen: screen,
      controls: supported_controls(),
      backend_enabled: Config.enabled?(),
      display_ready: display_ready?(state),
      phone_bridge_ready: phone_bridge_ready?(state),
      installing: Map.get(state, :installing?, false)
    }
  end

  defp display_ready?(state) do
    Config.start_processes?() and ProcessHost.live_pid?(state.qemu_pid) and
      Map.get(state, :vnc_banner_ready, false)
  end

  defp phone_bridge_ready?(state) do
    Config.start_processes?() and ProcessHost.live_pid?(state.pypkjs_pid) and
      tcp_port_open?(state.phone_ws_port)
  end

  defp supported_controls, do: QemuControl.supported_controls()

  defp app_uuid(path, platform) when is_binary(path) do
    case PBW.load(path, platform) do
      {:ok, %{uuid: uuid}} ->
        uuid

      {:error, reason} ->
        Logger.debug("could not read emulator app uuid from #{path}: #{inspect(reason)}")
        nil
    end
  end

  defp app_uuid(_path, _platform), do: nil

  defp prepare_running_session_for_install(state) do
    state = %{state | installing?: true, last_ping_ms: now_ms()}

    with {:ok, state} <- ensure_protocol_router(state),
         {:ok, state} <- maybe_start_pypkjs(state) do
      :ok = InstallPrep.wait_before_reuse_install(state)
      {:ok, state}
    end
  end

  defp ensure_protocol_router(%{protocol_router_pid: pid} = state) when is_pid(pid) do
    if ProcessHost.live_pid?(pid),
      do: {:ok, state},
      else: maybe_start_protocol_router(%{state | protocol_router_pid: nil})
  end

  defp ensure_protocol_router(state), do: maybe_start_protocol_router(state)

  defp reset_for_install(%{} = state) do
    Vnc.close_tcp_port(state.vnc_tcp)

    state = %{
      state
      | vnc_tcp: nil,
        vnc_tcp_buffer: <<>>,
        vnc_rfb_banner: nil,
        vnc_banner_ready: false
    }
    ProcessHost.cleanup_process(state.pypkjs_pid)
    ProcessHost.cleanup_process(state.protocol_router_pid)
    ProcessHost.cleanup_process(state.qemu_pid)

    with {:ok, _path} <- Qemu.reset_spi_image(state.platform, state.spi_image_path),
         {:ok, state} <-
           maybe_start_qemu(%{
             state
             | pypkjs_pid: nil,
               protocol_router_pid: nil,
               qemu_pid: nil,
               installing?: true
           }),
         {:ok, state} <- maybe_start_protocol_router(state) do
      Process.sleep(Config.config(:post_reset_settle_ms, 2_000))
      {:ok, state}
    end
  end

  defp via(id), do: {:via, Registry, {Ide.Emulator.Registry, id}}

  defp schedule_idle_check(state),
    do: Process.send_after(self(), :idle_check, min(state.idle_timeout_ms, 60_000))

  defp session_health(state) do
    cond do
      not Config.start_processes?() ->
        :ok

      not ProcessHost.live_pid?(state.qemu_pid) ->
        {:error, {:child_not_running, :qemu}}

      Map.get(state, :installing?, false) ->
        :ok

      not ProcessHost.live_pid?(state.protocol_router_pid) ->
        {:error, {:child_not_running, :protocol_router}}

      not tcp_port_open?(state.vnc_port) ->
        {:error, {:port_not_ready, :vnc, state.vnc_port}}

      ProcessHost.live_pid?(state.pypkjs_pid) and not tcp_port_open?(state.phone_ws_port) ->
        {:error, {:port_not_ready, :phone, state.phone_ws_port}}

      true ->
        :ok
    end
  end

  defp session_child_role(state, pid) when is_pid(pid) do
    cond do
      pid == state.qemu_pid -> :qemu
      pid == state.protocol_router_pid -> :protocol_router
      pid == state.pypkjs_pid -> :pypkjs
      true -> nil
    end
  end

  defp session_child_role(_state, _pid), do: nil

  defp validate_simulator_setting_commands(commands) do
    Enum.reduce_while(commands, :ok, fn %{protocol: protocol, payload: payload}, :ok ->
      case QemuControl.validate_payload(protocol, payload) do
        :ok -> {:cont, :ok}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp random_id, do: Base.url_encode64(:crypto.strong_rand_bytes(16), padding: false)
  defp random_token, do: Base.url_encode64(:crypto.strong_rand_bytes(24), padding: false)
  defp now_ms, do: System.monotonic_time(:millisecond)

  defp config(key, default), do: Config.config(key, default)
end

