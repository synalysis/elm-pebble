defmodule Ide.Emulator.Session.Startup do
  @moduledoc false

  require Logger

  alias Ide.Emulator.{InstallPrep, PBW, Types}
  alias Ide.Emulator.PebbleProtocol.Router
  alias Ide.Emulator.Session.{Bins, Config, Lifecycle, ProcessHost, Pypkjs, Qemu, Vnc}

  @default_idle_timeout_ms 5 * 60 * 1000

  @spec build_state(Types.session_launch_opts()) ::
          {:ok, Types.session_state()} | {:error, term()}
  def build_state(opts) do
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
         token: Lifecycle.random_token(),
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
         last_ping_ms: Lifecycle.now_ms(),
         last_boot_ms: 0,
         idle_timeout_ms: Config.config(:idle_timeout_ms, @default_idle_timeout_ms),
         vnc_banner_ready: false,
         vnc_rfb_banner: nil,
         vnc_tcp: nil,
         vnc_tcp_buffer: <<>>
       }}
    end
  end

  @spec maybe_start_qemu(Types.session_state()) :: {:ok, Types.session_state()} | {:error, term()}
  def maybe_start_qemu(state), do: maybe_start_qemu(state, true)

  @spec maybe_start_qemu(Types.session_state(), boolean()) ::
          {:ok, Types.session_state()} | {:error, term()}
  def maybe_start_qemu(state, allow_flash_reset?) do
    if Config.start_processes?() do
      with {:ok, qemu_bin} <- Bins.qemu_bin(),
           {:ok, pid} <-
             ProcessHost.start_daemon(qemu_bin, Qemu.args(state), "qemu:#{state.id}") do
        case ProcessHost.wait_for_qemu_boot(pid, state.console_port, 60_000) do
          :ok ->
            with :ok <-
                   Vnc.wait_for_tcp_port(
                     state.vnc_port,
                     Config.config(:vnc_ready_timeout_ms, 30_000)
                   ),
                 {:ok, vnc_rfb_banner, vnc_tcp} <-
                   Vnc.capture_rfb_connection(
                     state.vnc_port,
                     Config.config(:vnc_rfb_ready_timeout_ms, 15_000)
                   ) do
              {:ok,
               %{
                 state
                 | qemu_pid: pid,
                   last_boot_ms: Lifecycle.now_ms(),
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

  @spec maybe_start_protocol_router(Types.session_state()) ::
          {:ok, Types.session_state()} | {:error, term()}
  def maybe_start_protocol_router(state) do
    if Config.start_processes?() do
      case Router.start_link(qemu_port: state.bt_port, proxy_port: state.protocol_proxy_port) do
        {:ok, pid} -> {:ok, %{state | protocol_router_pid: pid}}
        {:error, reason} -> {:error, {:protocol_router_start_failed, reason}}
      end
    else
      {:ok, state}
    end
  end

  @spec maybe_start_pypkjs_if_needed(Types.session_state()) :: {:ok, Types.session_state()}
  def maybe_start_pypkjs_if_needed(state) do
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

  @spec maybe_start_pypkjs(Types.session_state()) ::
          {:ok, Types.session_state()} | {:error, term()}
  def maybe_start_pypkjs(state), do: Pypkjs.maybe_start(state)

  @spec prepare_running_session_for_install(Types.session_state()) ::
          {:ok, Types.session_state()} | {:error, term()}
  def prepare_running_session_for_install(state) do
    state = %{state | installing?: true, last_ping_ms: Lifecycle.now_ms()}

    with {:ok, state} <- ensure_protocol_router(state),
         {:ok, state} <- maybe_start_pypkjs(state) do
      :ok = InstallPrep.wait_before_reuse_install(state)
      {:ok, state}
    end
  end

  @spec reset_for_install(Types.session_state()) ::
          {:ok, Types.session_state()} | {:error, term()}
  def reset_for_install(state) do
    Vnc.close_tcp_port(state.vnc_tcp)

    state =
      state
      |> Map.put(:vnc_tcp, nil)
      |> Map.put(:vnc_tcp_buffer, <<>>)
      |> Map.put(:vnc_rfb_banner, nil)
      |> Map.put(:vnc_banner_ready, false)

    ProcessHost.cleanup_process(state.pypkjs_pid)
    ProcessHost.cleanup_process(state.protocol_router_pid)
    ProcessHost.cleanup_process(state.qemu_pid)

    state_for_qemu =
      state
      |> Map.put(:pypkjs_pid, nil)
      |> Map.put(:protocol_router_pid, nil)
      |> Map.put(:qemu_pid, nil)
      |> Map.put(:installing?, true)

    with {:ok, _path} <- Qemu.reset_spi_image(state.platform, state.spi_image_path),
         {:ok, state} <- maybe_start_qemu(state_for_qemu),
         {:ok, state} <- maybe_start_protocol_router(state) do
      Process.sleep(Config.config(:post_reset_settle_ms, 2_000))
      {:ok, state}
    end
  end

  @spec ensure_protocol_router(Types.session_state()) ::
          {:ok, Types.session_state()} | {:error, term()}
  def ensure_protocol_router(%{protocol_router_pid: pid} = state) when is_pid(pid) do
    if ProcessHost.live_pid?(pid),
      do: {:ok, state},
      else: maybe_start_protocol_router(%{state | protocol_router_pid: nil})
  end

  def ensure_protocol_router(state), do: maybe_start_protocol_router(state)

  @doc false
  @spec app_uuid(String.t() | nil, String.t()) :: String.t() | nil
  def app_uuid(path, platform) when is_binary(path) do
    case PBW.load(path, platform) do
      {:ok, %{uuid: uuid}} ->
        uuid

      {:error, reason} ->
        Logger.debug("could not read emulator app uuid from #{path}: #{inspect(reason)}")
        nil
    end
  end

  def app_uuid(_path, _platform), do: nil
end
