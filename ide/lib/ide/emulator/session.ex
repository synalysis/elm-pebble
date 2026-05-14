defmodule Ide.Emulator.Session do
  @moduledoc false

  use GenServer

  require Logger

  alias Ide.Emulator.{PBW, PBWInstaller, SdkImages}
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
          idle_timeout_ms: pos_integer()
        }

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    id = Keyword.get(opts, :id) || random_id()
    GenServer.start_link(__MODULE__, Keyword.put(opts, :id, id), name: via(id))
  end

  @spec child_spec(keyword()) :: Supervisor.child_spec()
  def child_spec(opts) do
    %{
      id: {__MODULE__, Keyword.get(opts, :id, make_ref())},
      start: {__MODULE__, :start_link, [opts]},
      restart: :temporary
    }
  end

  @spec info(pid()) :: map()
  def info(pid), do: GenServer.call(pid, :info)

  @spec artifact_file_path(pid()) :: String.t() | nil
  def artifact_file_path(pid), do: GenServer.call(pid, :artifact_file_path)

  @spec install(pid()) :: {:ok, map()} | {:error, term()}
  def install(pid) do
    with :ok <- GenServer.call(pid, :reset_for_install, 90_000) do
      do_install(pid, config(:native_install_retries, 4))
    end
  catch
    :exit, {:timeout, _} -> {:error, :emulator_session_unresponsive}
    :exit, _ -> {:error, :emulator_session_unavailable}
  end

  @spec local_port(pid(), :vnc | :phone) :: pos_integer()
  def local_port(pid, kind), do: GenServer.call(pid, {:local_port, kind})

  @spec ping(pid()) :: {:ok, map()} | {:error, term()}
  def ping(pid) do
    GenServer.call(pid, :ping, 1_000)
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

  defp do_install(pid, retries_left) do
    with {:ok, context} <- GenServer.call(pid, :install_context, 5_000) do
      # region agent log
      Ide.AgentDebugLog.log("initial", "H2,H3,H6", "session.ex:do_install:context", "router install context acquired", %{
        platform: context.platform,
        artifact_path: context.artifact_path,
        artifact_bytes: file_size(context.artifact_path),
        protocol_router_alive: alive?(context.protocol_router_pid),
        retries_left: retries_left
      })

      # endregion
      case install_with_router(context) do
        {:ok, result} ->
          console_tail = capture_console_after_install(context.console_port)

          # region agent log
          Ide.AgentDebugLog.log("initial", "H3,H6,H16,H17,H18", "session.ex:do_install:ok", "router install succeeded", %{
            platform: context.platform,
            uuid: Map.get(result, :uuid),
            parts: Map.get(result, :parts),
            protocol_router_alive: alive?(context.protocol_router_pid),
            console_tail: console_tail
          })

          # endregion
          {:ok, result}

        {:error, reason} = error ->
          # region agent log
          Ide.AgentDebugLog.log("initial", "H3,H6", "session.ex:do_install:error", "router install failed", %{
            platform: context.platform,
            reason: inspect(reason)
          })

          # endregion
          maybe_retry_install(pid, reason, retries_left, error)
      end
    end
  end

  defp install_with_router(context) do
    PBWInstaller.install(context.protocol_router_pid, context.artifact_path, context.platform,
      post_install_probe_timeout_ms: 1_000
    )
  end

  defp capture_console_after_install(console_port) do
    deadline = System.monotonic_time(:millisecond) + 750

    with {:ok, socket} <-
           :gen_tcp.connect(~c"127.0.0.1", console_port, [:binary, active: false], 250) do
      try do
        console_capture_loop(socket, deadline, <<>>)
      after
        :gen_tcp.close(socket)
      end
    else
      {:error, reason} -> "console_connect_failed:#{inspect(reason)}"
    end
  end

  defp console_capture_loop(socket, deadline, acc) do
    remaining = max(deadline - System.monotonic_time(:millisecond), 0)

    cond do
      remaining == 0 ->
        console_tail(acc)

      true ->
        case :gen_tcp.recv(socket, 0, min(remaining, 100)) do
          {:ok, data} -> console_capture_loop(socket, deadline, acc <> data)
          {:error, :timeout} -> console_capture_loop(socket, deadline, acc)
          {:error, reason} -> "console_closed:#{inspect(reason)} tail=#{console_tail(acc)}"
        end
    end
  end

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

  defp retryable_install_error?({:libpebble2_install_failed, _exit_code, output})
       when is_binary(output) do
    String.contains?(output, "TimeoutError") or
      String.contains?(output, "ConnectionError") or
      String.contains?(output, "Connection refused")
  end

  defp retryable_install_error?({:putbytes_failed, _meta, :timeout}), do: true

  defp retryable_install_error?(_reason), do: false

  @spec runtime_status(term()) :: map()
  def runtime_status(platform \\ nil) do
    platform = normalize_platform(platform)
    sdk_root = preferred_sdk_root()
    sdk_toolchain_root = sdk_version_root(config(:sdk_core_version, "4.9.169"))

    components = [
      component(
        :embedded_emulator,
        "Embedded emulator",
        enabled?(),
        if(enabled?(), do: "enabled", else: "disabled by configuration"),
        false
      ),
      command_component(:pebble_cli, "Pebble CLI", pebble_bin(), true),
      component(
        :pebble_sdk_python_env,
        "Pebble SDK Python env",
        SdkImages.sdk_python_env_present?(sdk_root),
        Path.join(sdk_root, ".venv"),
        true
      ),
      component(
        :pebble_sdk_node_modules,
        "Pebble SDK JS dependencies",
        SdkImages.sdk_node_modules_present?(sdk_root),
        Path.join(sdk_root, "node_modules"),
        true
      ),
      component(
        :pebble_arm_gcc,
        "Pebble ARM GCC",
        File.exists?(
          Path.join(sdk_toolchain_root, "toolchain/arm-none-eabi/bin/arm-none-eabi-gcc")
        ),
        Path.join(sdk_toolchain_root, "toolchain/arm-none-eabi/bin/arm-none-eabi-gcc"),
        true
      ),
      qemu_component(qemu_bin()),
      command_component(:pypkjs, "pypkjs bridge", pypkjs_bin(), true),
      component(
        :qemu_micro_flash,
        "QEMU micro flash image",
        qemu_micro_flash_path(platform),
        qemu_image_dir(platform),
        true
      ),
      component(
        :qemu_spi_flash,
        "QEMU SPI flash image",
        qemu_spi_flash_available?(platform),
        qemu_image_dir(platform),
        true
      )
    ]

    missing = Enum.filter(components, &(&1.status == :missing))

    %{
      status: if(missing == [], do: :ok, else: :warning),
      platform: platform,
      components: components,
      missing: missing,
      installable: Enum.any?(missing, & &1.installable)
    }
  end

  @spec install_runtime_dependencies(term()) :: {:ok, map()} | {:error, term()}
  def install_runtime_dependencies(platform \\ nil) do
    platform = normalize_platform(platform)
    before_status = runtime_status(platform)

    steps =
      before_status.missing
      |> Enum.map(& &1.id)
      |> Enum.uniq()
      |> Enum.flat_map(&install_steps_for_component(&1, platform))
      |> Enum.uniq_by(& &1.name)

    results = run_install_steps(steps)
    after_status = runtime_status(platform)

    {:ok,
     %{
       platform: platform,
       before: before_status,
       after: after_status,
       results: results,
       output: render_install_results(results, after_status)
     }}
  end

  @impl true
  def init(opts) do
    Process.flag(:trap_exit, true)
    platform = normalize_platform(Keyword.get(opts, :platform))

    with :ok <- validate_runtime_requirements(platform),
         {:ok, state} <- build_state(Keyword.put(opts, :platform, platform)),
         {:ok, state} <- maybe_start_qemu(state),
         {:ok, state} <- maybe_start_protocol_router(state) do
      schedule_idle_check(state)
      # region agent log
      Ide.AgentDebugLog.log("initial", "H2", "session.ex:init:ok", "emulator session initialized", %{
        id: state.id,
        project_slug: state.project_slug,
        platform: state.platform,
        artifact_path: state.artifact_path,
        artifact_bytes: file_size(state.artifact_path),
        app_uuid: state.app_uuid,
        has_phone_companion: state.has_phone_companion,
        bt_port: state.bt_port,
        phone_ws_port: state.phone_ws_port,
        qemu_alive: alive?(state.qemu_pid),
        protocol_router_alive: alive?(state.protocol_router_pid)
      })

      # endregion
      {:ok, state}
    else
      {:error, reason} ->
        # region agent log
        Ide.AgentDebugLog.log("initial", "H2", "session.ex:init:error", "emulator session init failed", %{
          platform: platform,
          reason: inspect(reason)
        })

        # endregion
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
    cleanup_process(state.pypkjs_pid)

    {:reply,
     {:ok,
      %{
        protocol_router_pid: state.protocol_router_pid,
        artifact_path: state.artifact_path,
        platform: state.platform,
        console_port: state.console_port
      }}, %{state | pypkjs_pid: nil}}
  end

  def handle_call(:direct_install_context, _from, %{qemu_pid: nil} = state),
    do: {:reply, {:error, :embedded_protocol_router_not_started}, state}

  def handle_call(:direct_install_context, _from, state) do
    cleanup_process(state.pypkjs_pid)
    cleanup_process(state.protocol_router_pid)

    {:reply,
     {:ok,
      %{
        qemu_port: state.bt_port,
        artifact_path: state.artifact_path,
        platform: state.platform,
        app_uuid: state.app_uuid
      }}, %{state | pypkjs_pid: nil, protocol_router_pid: nil, installing?: true}}
  end

  def handle_call({:local_port, :vnc}, _from, state), do: {:reply, state.vnc_port, state}

  def handle_call({:local_port, :phone}, _from, %{pypkjs_pid: nil} = state) do
    case maybe_start_pypkjs(state) do
      {:ok, state} ->
        # region agent log
        Ide.AgentDebugLog.log("initial", "H5", "session.ex:phone_port:pypkjs_ok", "pypkjs started for phone websocket", %{
          id: state.id,
          platform: state.platform,
          phone_ws_port: state.phone_ws_port,
          pypkjs_alive: alive?(state.pypkjs_pid)
        })

        # endregion
        {:reply, state.phone_ws_port, state}

      {:error, reason} ->
        # region agent log
        Ide.AgentDebugLog.log("initial", "H5", "session.ex:phone_port:pypkjs_error", "pypkjs failed to start", %{
          id: state.id,
          platform: state.platform,
          reason: inspect(reason)
        })

        # endregion
        {:reply, {:error, reason}, state}
    end
  end

  def handle_call({:local_port, :phone}, _from, state), do: {:reply, state.phone_ws_port, state}

  def handle_call(:restart_protocol_router, _from, %{protocol_router_pid: nil} = state) do
    case maybe_start_protocol_router(state) do
      {:ok, state} -> {:reply, :ok, %{state | installing?: false}}
      {:error, reason} -> {:reply, {:error, reason}, %{state | installing?: false}}
    end
  end

  def handle_call(:restart_protocol_router, _from, state), do: {:reply, :ok, state}

  def handle_call(:reset_for_install, _from, state) do
    # region agent log
    Ide.AgentDebugLog.log("initial", "H12", "session.ex:reset_for_install:start", "resetting embedded emulator before install", %{
      id: state.id,
      platform: state.platform,
      spi_image_path: state.spi_image_path
    })

    # endregion

    case reset_for_install(state) do
      {:ok, state} ->
        # region agent log
        Ide.AgentDebugLog.log("initial", "H12", "session.ex:reset_for_install:ok", "embedded emulator reset before install", %{
          id: state.id,
          platform: state.platform,
          qemu_alive: alive?(state.qemu_pid),
          protocol_router_alive: alive?(state.protocol_router_pid)
        })

        # endregion
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

  def handle_call(:ping, _from, state) do
    case session_health(state) do
      :ok ->
        state = %{state | last_ping_ms: now_ms()}
        {:reply, {:ok, public_info(state)}, state}

      {:error, reason} ->
        {:stop, {:shutdown, reason}, {:error, reason}, state}
    end
  end

  defp reset_for_install(state) do
    cleanup_process(state.pypkjs_pid)
    cleanup_process(state.protocol_router_pid)
    cleanup_process(state.qemu_pid)

    with {:ok, _path} <- reset_spi_image(state.platform, state.spi_image_path),
         {:ok, state} <-
           maybe_start_qemu(%{
             state
             | pypkjs_pid: nil,
               protocol_router_pid: nil,
               qemu_pid: nil,
               installing?: true
           }),
         {:ok, state} <- maybe_start_protocol_router(state) do
      {:ok, state}
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
        # region agent log
        Ide.AgentDebugLog.log("initial", "H5", "session.ex:child_exit:pypkjs", "pypkjs exited", %{
          id: state.id,
          platform: state.platform,
          reason: inspect(reason)
        })

        # endregion
        Logger.debug("embedded emulator pypkjs exited: #{inspect(reason)}")
        {:noreply, %{state | pypkjs_pid: nil}}

      role ->
        # region agent log
        Ide.AgentDebugLog.log("initial", "H4", "session.ex:child_exit:emulator", "emulator child exited", %{
          id: state.id,
          platform: state.platform,
          role: inspect(role),
          reason: inspect(reason)
        })

        # endregion
        Logger.debug("embedded emulator #{role} exited: #{inspect(reason)}")
        {:stop, {:shutdown, {:child_exited, role, reason}}, state}
    end
  end

  def handle_info(_message, state), do: {:noreply, state}

  @impl true
  def terminate(_reason, state) do
    cleanup_process(state.qemu_pid)
    cleanup_process(state.pypkjs_pid)
    cleanup_process(state.protocol_router_pid)
    :ok
  end

  @spec qemu_args(map()) :: [String.t()]
  def qemu_args(state) do
    image_dir = qemu_image_dir(state.platform)
    micro_flash = Path.join(image_dir, "qemu_micro_flash.bin")
    qemu_features = Map.get(state, :qemu_features) || %{new_qemu?: false, machines: MapSet.new()}
    tcp_opts = "server=on,wait=off"

    firmware_args =
      if qemu_features.new_qemu?, do: ["-kernel", micro_flash], else: ["-pflash", micro_flash]

    pc_bios_args =
      if qemu_features.new_qemu?,
        do: qemu_keymap_args(state),
        else: ["-L", pc_bios_dir()]

    base =
      [
        "-rtc",
        "base=localtime",
        "-serial",
        "null",
        "-serial",
        "tcp:127.0.0.1:#{state.bt_port},#{tcp_opts}",
        "-serial",
        "tcp:127.0.0.1:#{state.console_port},#{tcp_opts}"
      ] ++
        firmware_args ++
        [
          "-monitor",
          "stdio"
        ] ++
        pc_bios_args ++
        [
          "-vnc",
          ":#{state.vnc_display}"
        ]

    base ++ machine_args(state.platform, state.spi_image_path, qemu_features)
  end

  @spec pypkjs_args(map()) :: [String.t()]
  def pypkjs_args(state) do
    [
      "--qemu",
      "127.0.0.1:#{Map.get(state, :protocol_proxy_port, state.bt_port)}",
      "--port",
      Integer.to_string(state.phone_ws_port),
      "--persist",
      state.persist_dir
    ]
    |> maybe_append_layout_arg(state)
  end

  @spec machine_args(String.t(), String.t() | nil, map()) :: [String.t()]
  def machine_args(
        platform,
        spi_image_path,
        qemu_features \\ %{new_qemu?: false, machines: MapSet.new()}
      ) do
    spi_pflash =
      if qemu_features.new_qemu? do
        ["-drive", "if=none,id=spi-flash,file=#{spi_image_path},format=raw"]
      else
        ["-pflash", spi_image_path]
      end

    new_mtd_flash = ["-drive", "if=mtd,format=raw,file=#{spi_image_path}"]

    new_board? =
      qemu_features.new_qemu? and MapSet.member?(qemu_features.machines, "pebble-emery")

    audio_none = if new_board?, do: ["-audio", "driver=none,id=audio0"], else: []

    case platform do
      "aplite" ->
        ["-machine", "pebble-bb2", "-mtdblock", spi_image_path, "-cpu", "cortex-m3"]

      "basalt" ->
        ["-machine", "pebble-snowy-bb", "-cpu", "cortex-m4"] ++ spi_pflash

      "chalk" ->
        ["-machine", "pebble-s4-bb", "-cpu", "cortex-m4"] ++ spi_pflash

      "diorite" ->
        ["-machine", "pebble-silk-bb", "-mtdblock", spi_image_path, "-cpu", "cortex-m4"]

      "emery" ->
        if new_board? do
          ["-machine", "pebble-emery", "-cpu", "cortex-m33"] ++ new_mtd_flash ++ audio_none
        else
          ["-machine", "pebble-snowy-emery-bb", "-cpu", "cortex-m4"] ++ spi_pflash
        end

      "flint" ->
        if new_board? do
          ["-machine", "pebble-flint", "-cpu", "cortex-m4"] ++ new_mtd_flash ++ audio_none
        else
          ["-machine", "pebble-silk-bb", "-cpu", "cortex-m4", "-mtdblock", spi_image_path]
        end

      "gabbro" ->
        if new_board? do
          ["-machine", "pebble-gabbro", "-cpu", "cortex-m33"] ++ new_mtd_flash ++ audio_none
        else
          ["-machine", "pebble-snowy-emery-bb", "-cpu", "cortex-m4"] ++ spi_pflash
        end

      _ ->
        machine_args(WatchModels.default_id(), spi_image_path, qemu_features)
    end
  end

  defp build_state(opts) do
    platform = Keyword.fetch!(opts, :platform)
    project_slug = Keyword.get(opts, :project_slug, "")
    artifact_path = Keyword.get(opts, :artifact_path)

    with {:ok, ports} <- allocate_ports(6),
         {:ok, spi_image_path} <- make_spi_image(platform, project_slug),
         {:ok, persist_dir} <- make_persist_dir(platform, project_slug) do
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
         qemu_features: qemu_features(),
         spi_image_path: spi_image_path,
         persist_dir: persist_dir,
         installing?: false,
         last_ping_ms: now_ms(),
         idle_timeout_ms: config(:idle_timeout_ms, @default_idle_timeout_ms)
       }}
    end
  end

  defp maybe_start_qemu(state) do
    maybe_start_qemu(state, true)
  end

  defp maybe_start_qemu(state, allow_flash_reset?) do
    if start_processes?() do
      with {:ok, qemu_bin} <- qemu_bin(),
           {:ok, pid} <- start_daemon(qemu_bin, qemu_args(state), "qemu:#{state.id}") do
        case wait_for_qemu_boot(pid, state.console_port, 60_000) do
          :ok ->
            {:ok, %{state | qemu_pid: pid}}

          {:error, {:qemu_boot_firmware_failure, _tail}} when allow_flash_reset? ->
            cleanup_process(pid)

            with {:ok, _path} <- reset_spi_image(state.platform, state.spi_image_path) do
              maybe_start_qemu(state, false)
            end

          {:error, reason} ->
            cleanup_process(pid)
            {:error, reason}
        end
      end
    else
      {:ok, state}
    end
  end

  defp maybe_start_protocol_router(state) do
    if start_processes?() do
      case Router.start_link(qemu_port: state.bt_port, proxy_port: state.protocol_proxy_port) do
        {:ok, pid} -> {:ok, %{state | protocol_router_pid: pid}}
        {:error, reason} -> {:error, {:protocol_router_start_failed, reason}}
      end
    else
      {:ok, state}
    end
  end

  defp maybe_start_pypkjs(state) do
    if start_processes?() do
      with {:ok, pypkjs_bin} <- pypkjs_bin(),
           {:ok, command, args_prefix} <- pypkjs_command(pypkjs_bin),
           {:ok, pid} <-
             start_daemon(command, args_prefix ++ pypkjs_args(state), "pypkjs:#{state.id}"),
           :ok <-
             wait_for_daemon(pid, state.phone_ws_port, config(:pypkjs_ready_timeout_ms, 30_000)) do
        {:ok, %{state | pypkjs_pid: pid}}
      end
    else
      {:ok, state}
    end
  end

  defp start_daemon(command, args, prefix) do
    case MuonTrap.Daemon.start_link(command, args,
           log_output: :debug,
           log_prefix: prefix,
           stderr_to_stdout: true
         ) do
      {:ok, pid} -> {:ok, pid}
      {:error, reason} -> {:error, {:daemon_start_failed, command, reason}}
    end
  end

  defp wait_for_daemon(pid, port, timeout_ms) do
    deadline = System.monotonic_time(:millisecond) + timeout_ms
    wait_for_daemon(pid, port, deadline, nil)
  end

  defp wait_for_qemu_boot(pid, console_port, timeout_ms) do
    deadline = System.monotonic_time(:millisecond) + timeout_ms

    with {:ok, socket} <- wait_for_tcp_socket(pid, console_port, deadline) do
      wait_for_qemu_boot_marker(pid, socket, deadline, <<>>)
    end
  end

  defp wait_for_tcp_socket(pid, port, deadline) do
    cond do
      not Process.alive?(pid) ->
        {:error, {:daemon_exited_before_ready, port}}

      System.monotonic_time(:millisecond) >= deadline ->
        {:error, {:daemon_not_ready, port, :not_ready}}

      true ->
        case :gen_tcp.connect(~c"127.0.0.1", port, [:binary, active: false], 250) do
          {:ok, socket} ->
            {:ok, socket}

          {:error, _reason} ->
            Process.sleep(100)
            wait_for_tcp_socket(pid, port, deadline)
        end
    end
  end

  defp wait_for_qemu_boot_marker(pid, socket, deadline, received) do
    cond do
      boot_marker?(received) ->
        :gen_tcp.close(socket)
        :ok

      not Process.alive?(pid) ->
        :gen_tcp.close(socket)
        {:error, :qemu_exited_before_boot}

      System.monotonic_time(:millisecond) >= deadline ->
        :gen_tcp.close(socket)

        reason =
          if qemu_firmware_failure?(received) do
            {:qemu_boot_firmware_failure, console_tail(received)}
          else
            {:qemu_boot_timeout, console_tail(received)}
          end

        {:error, reason}

      true ->
        case :gen_tcp.recv(socket, 0, 250) do
          {:ok, data} ->
            wait_for_qemu_boot_marker(pid, socket, deadline, received <> data)

          {:error, :timeout} ->
            wait_for_qemu_boot_marker(pid, socket, deadline, received)

          {:error, reason} ->
            :gen_tcp.close(socket)
            {:error, {:qemu_console_closed, reason}}
        end
    end
  end

  defp boot_marker?(data) do
    Enum.any?(["<SDK Home>", "<Launcher>", "Ready for communication"], fn marker ->
      :binary.match(data, marker) != :nomatch
    end)
  end

  defp qemu_firmware_failure?(data) do
    Enum.any?(["Invalid firmware description", "SAD WATCH"], fn marker ->
      :binary.match(data, marker) != :nomatch
    end)
  end

  defp console_tail(data) when is_binary(data) do
    size = byte_size(data)
    tail_size = min(size, 256)
    tail = binary_part(data, size - tail_size, tail_size)

    if String.valid?(tail) do
      tail
    else
      "base16:" <> Base.encode16(tail, case: :lower)
    end
  end

  defp wait_for_daemon(pid, port, deadline, last_error) do
    cond do
      not Process.alive?(pid) ->
        {:error, {:daemon_exited_before_ready, port}}

      tcp_port_open?(port) ->
        :ok

      System.monotonic_time(:millisecond) >= deadline ->
        {:error, {:daemon_not_ready, port, last_error}}

      true ->
        Process.sleep(100)
        wait_for_daemon(pid, port, deadline, :not_ready)
    end
  end

  @spec tcp_port_open?(pos_integer()) :: boolean()
  def tcp_port_open?(port) when is_integer(port) do
    case :gen_tcp.connect(~c"127.0.0.1", port, [:binary, active: false], 250) do
      {:ok, socket} ->
        :gen_tcp.close(socket)
        true

      {:error, _reason} ->
        false
    end
  end

  defp maybe_append_layout_arg(args, state) do
    layout_path = Path.join(qemu_image_dir(state.platform), "layouts.json")

    if File.exists?(layout_path) do
      args ++ ["--layout", layout_path]
    else
      args
    end
  end

  defp public_info(state) do
    profile = WatchModels.profile_for(state.platform)
    screen = Map.fetch!(profile, "screen")

    %{
      id: state.id,
      token: state.token,
      project_slug: state.project_slug,
      platform: state.platform,
      artifact_path: "/api/emulator/#{state.id}/artifact",
      app_uuid: state.app_uuid,
      has_phone_companion: state.has_phone_companion,
      install_path: "/api/emulator/#{state.id}/install",
      vnc_path: "/api/emulator/#{state.id}/ws/vnc",
      phone_path: "/api/emulator/#{state.id}/ws/phone",
      ping_path: "/api/emulator/#{state.id}/ping",
      kill_path: "/api/emulator/#{state.id}/kill",
      screen: screen,
      controls: supported_controls(),
      backend_enabled: enabled?()
    }
  end

  defp supported_controls do
    ~w(button_up button_select button_down button_back tap battery bluetooth time_24h timeline_peek set_time install logs screenshot)
  end

  defp allocate_ports(count) do
    ports =
      Enum.map(1..count, fn _ ->
        {:ok, socket} = :gen_tcp.listen(0, [:binary, active: false, reuseaddr: true])
        {:ok, port} = :inet.port(socket)
        :gen_tcp.close(socket)
        port
      end)

    {:ok, ports}
  rescue
    error -> {:error, {:port_allocation_failed, error}}
  end

  defp make_spi_image(platform, project_slug) do
    source_dir = qemu_image_dir(platform)
    raw = Path.join(source_dir, "qemu_spi_flash.bin")
    bz2 = raw <> ".bz2"
    path = Path.join(emulator_state_dir(project_slug, platform), "qemu_spi_flash.bin")

    with :ok <- File.mkdir_p(Path.dirname(path)) do
      # region agent log
      Ide.AgentDebugLog.log("initial", "H24,H27", "session.ex:make_spi_image", "creating fresh emulator flash image for launch", %{
        project_slug: project_slug,
        platform: platform,
        path: path,
        had_existing_image: File.exists?(path),
        has_raw_source: File.exists?(raw),
        has_bz2_source: File.exists?(bz2)
      })

      # endregion

      cond do
        File.exists?(raw) ->
          File.cp(raw, path)
          {:ok, path}

        File.exists?(bz2) ->
          decompress_bzip2(bz2, path)

        start_processes?() ->
          {:error, {:qemu_flash_image_not_found, source_dir}}

        true ->
          File.touch(path)
          {:ok, path}
        end
    end
  end

  defp reset_spi_image(platform, path) do
    source_dir = qemu_image_dir(platform)
    raw = Path.join(source_dir, "qemu_spi_flash.bin")
    bz2 = raw <> ".bz2"

    with :ok <- File.mkdir_p(Path.dirname(path)) do
      cond do
        File.exists?(raw) -> with :ok <- File.cp(raw, path), do: {:ok, path}
        File.exists?(bz2) -> decompress_bzip2(bz2, path)
        true -> {:error, {:qemu_flash_image_not_found, source_dir}}
      end
    end
  end

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

  defp make_persist_dir(platform, project_slug) do
    dir = Path.join(emulator_state_dir(project_slug, platform), "pypkjs")

    case File.mkdir_p(dir) do
      :ok -> {:ok, dir}
      {:error, reason} -> {:error, {:persist_dir_failed, reason}}
    end
  end

  defp emulator_state_dir(project_slug, platform) do
    root = config(:state_root, Path.join(System.tmp_dir!(), "elm-pebble-emulator-state"))

    Path.join([
      root,
      safe_path_fragment(project_slug, "project"),
      safe_path_fragment(platform, "platform")
    ])
  end

  defp safe_path_fragment(value, fallback) do
    value
    |> to_string()
    |> String.trim()
    |> then(fn
      "" -> fallback
      text -> text
    end)
    |> String.replace(~r/[^A-Za-z0-9_.-]+/, "-")
  end

  defp decompress_bzip2(source, target) do
    case System.find_executable("bzip2") || System.find_executable("bunzip2") do
      nil ->
        {:error, :bzip2_not_found}

      bin ->
        {data, exit_code} = System.cmd(bin, ["-dc", source], stderr_to_stdout: true)

        if exit_code == 0 do
          File.write(target, data)
          {:ok, target}
        else
          {:error, {:bzip2_failed, data}}
        end
    end
  end

  defp qemu_features do
    case qemu_bin() do
      {:ok, qemu_bin} ->
        %{
          new_qemu?: qemu_major_version(qemu_bin) >= 7,
          machines: qemu_machines(qemu_bin)
        }

      {:error, _reason} ->
        %{new_qemu?: false, machines: MapSet.new()}
    end
  end

  defp qemu_major_version(qemu_bin) do
    case System.cmd(qemu_bin, ["--version"], stderr_to_stdout: true) do
      {output, 0} ->
        case Regex.run(~r/version\s+(\d+)\./, output) do
          [_, major] -> String.to_integer(major)
          _ -> 0
        end

      {_output, _exit_code} ->
        0
    end
  rescue
    _ -> 0
  end

  defp qemu_machines(qemu_bin) do
    case System.cmd(qemu_bin, ["-machine", "help"], stderr_to_stdout: true) do
      {output, 0} ->
        output
        |> String.split("\n")
        |> Enum.map(fn line ->
          line |> String.trim() |> String.split(~r/\s+/, parts: 2) |> List.first()
        end)
        |> Enum.reject(&(&1 in [nil, "", "Supported"]))
        |> MapSet.new()

      {_output, _exit_code} ->
        MapSet.new()
    end
  rescue
    _ -> MapSet.new()
  end

  defp qemu_keymap_args(state) do
    root = Path.join(Map.get(state, :persist_dir) || System.tmp_dir!(), "qemu-pc-bios")
    keymap_dir = Path.join(root, "keymaps")
    target = Path.join(keymap_dir, "en-us")

    with :ok <- File.mkdir_p(keymap_dir),
         {:ok, content} <- qemu_keymap_content(),
         :ok <- File.write(target, content) do
      ["-L", root]
    else
      _ -> []
    end
  end

  defp qemu_keymap_content do
    source = Path.join(pc_bios_dir(), "keymaps/en-us")

    case File.read(source) do
      {:ok, content} ->
        content =
          content
          |> String.split("\n")
          |> Enum.reject(&(String.trim(&1) |> String.starts_with?("include ")))
          |> Enum.join("\n")

        {:ok, content}

      {:error, _reason} ->
        {:ok, "map 0x409\n"}
    end
  end

  defp qemu_image_dir(platform) do
    qemu_image_roots()
    |> Enum.find(fn root -> SdkImages.images_present?(root, platform) end)
    |> case do
      root when is_binary(root) -> Path.join([root, platform, "qemu"])
      nil -> Path.join([preferred_qemu_image_root(), platform, "qemu"])
    end
  end

  defp pc_bios_dir do
    Enum.find_value(qemu_data_roots(), fn root ->
      if File.exists?(Path.join(root, "keymaps/en-us")), do: root
    end) || ""
  end

  defp qemu_data_roots do
    configured_root = config(:qemu_data_root, nil)

    configured_roots =
      if is_binary(configured_root) and configured_root != "", do: [configured_root], else: []

    sdk_roots =
      Enum.map(sdk_roots(), fn root ->
        path = Path.join(root, "toolchain/lib/pc-bios")
        path
      end)

    qemu_sdk_roots =
      case qemu_bin() do
        {:ok, path} ->
          case qemu_bin_sdk_root(path) do
            root when is_binary(root) -> [Path.join(root, "toolchain/lib/pc-bios")]
            nil -> []
          end

        {:error, _reason} ->
          []
      end

    system_roots = ["/usr/share/qemu", "/usr/local/share/qemu"]

    configured_roots ++ qemu_sdk_roots ++ sdk_roots ++ system_roots
  end

  defp qemu_bin do
    resolve_bin(
      config(:qemu_bin, nil),
      ["qemu-pebble", "qemu-system-arm"],
      qemu_pebble_candidates(),
      :qemu_not_found
    )
  end

  defp pypkjs_bin do
    resolve_bin(config(:pypkjs_bin, nil), ["pypkjs"], pypkjs_candidates(), :pypkjs_not_found)
  end

  defp pebble_bin do
    resolve_bin(config(:pebble_bin, nil), ["pebble"], pebble_candidates(), :pebble_cli_not_found)
  end

  defp resolve_bin(configured, fallbacks, candidates, error) do
    cond do
      executable_file?(configured) ->
        {:ok, configured}

      bin = find_executable(fallbacks) ->
        {:ok, bin}

      bin = Enum.find(candidates, &executable_file?/1) ->
        {:ok, bin}

      true ->
        {:error, error}
    end
  end

  defp find_executable(fallbacks) do
    Enum.find_value(fallbacks, &System.find_executable/1)
  end

  defp executable_file?(path) when is_binary(path) and path != "" do
    File.exists?(path) and not File.dir?(path)
  end

  defp executable_file?(_), do: false

  defp qemu_pebble_candidates do
    sdk_roots()
    |> Enum.map(&Path.join(&1, "toolchain/bin/qemu-pebble"))
  end

  defp pypkjs_candidates do
    [
      Path.expand(".local/share/uv/tools/pebble-tool/bin/pypkjs", System.user_home!()),
      "/opt/pipx/venvs/pebble-tool/bin/pypkjs",
      "/usr/local/bin/pypkjs"
    ]
  end

  defp pebble_candidates do
    [
      Path.expand(".local/share/uv/tools/pebble-tool/bin/pebble", System.user_home!()),
      Path.expand(".local/bin/pebble", System.user_home!()),
      "/opt/pipx/venvs/pebble-tool/bin/pebble",
      "/usr/local/bin/pebble"
    ]
  end

  @spec pypkjs_command(String.t()) :: {:ok, String.t(), [String.t()]} | {:error, term()}
  def pypkjs_command(pypkjs_bin) do
    wrapper_path = Path.expand("../../../priv/python/embedded_pypkjs.py", __DIR__)

    with {:ok, python} <- pypkjs_python(pypkjs_bin),
         true <- File.exists?(wrapper_path) do
      {:ok, python, [wrapper_path]}
    else
      false -> {:ok, pypkjs_bin, []}
      {:error, _reason} -> {:ok, pypkjs_bin, []}
    end
  end

  defp pypkjs_python(pypkjs_bin) do
    with {:ok, <<"#!", rest::binary>>} <- File.read(pypkjs_bin),
         [first_line | _] <- String.split(rest, "\n", parts: 2),
         python when python != "" <- String.trim(first_line),
         true <- executable_file?(python) do
      {:ok, python}
    else
      _ -> {:error, :pypkjs_python_not_found}
    end
  end

  defp sdk_roots do
    case config(:sdk_roots, nil) do
      roots when is_list(roots) ->
        Enum.filter(roots, &is_binary/1)

      _ ->
        home = System.user_home!()

        sdk_roots_for_os(home)
    end
  end

  defp sdk_roots_for_os(home) do
    linux_roots = [
      Path.expand(".pebble-sdk/SDKs/current", home),
      Path.expand(".pebble-sdk/SDKs/4.9.169", home),
      Path.expand(".pebble-sdk/SDKs/4.9.148", home)
    ]

    mac_roots = [
      Path.expand("Library/Application Support/Pebble SDK/SDKs/current", home),
      Path.expand("Library/Application Support/Pebble SDK/SDKs/4.9.169", home),
      Path.expand("Library/Application Support/Pebble SDK/SDKs/4.9.148", home),
      Path.expand("Library/Application Support/Pebble SDK/SDKs/4.9.77", home)
    ]

    case :os.type() do
      {:unix, :darwin} -> mac_roots ++ linux_roots
      _ -> linux_roots ++ mac_roots
    end
  end

  defp validate_runtime_requirements(platform) do
    cond do
      not enabled?() ->
        {:error, :embedded_emulator_disabled}

      config(:validate_runtime, true) == false ->
        :ok

      true ->
        case maybe_download_qemu_images(platform) do
          :ok ->
            missing =
              platform
              |> runtime_status()
              |> Map.fetch!(:missing)
              |> Enum.map(&component_missing_detail/1)

            case missing do
              [] -> :ok
              missing -> {:error, {:embedded_emulator_unavailable, Enum.reverse(missing)}}
            end

          {:error, reason} ->
            {:error, {:embedded_emulator_image_download_failed, reason}}
        end
    end
  end

  defp component_missing_detail(%{label: label, detail: detail})
       when is_binary(label) and is_binary(detail) do
    "#{label}: #{detail}"
  end

  defp component_missing_detail(%{label: label}) when is_binary(label), do: label
  defp component_missing_detail(component), do: inspect(component)

  defp component(id, label, true, detail, installable),
    do: %{id: id, label: label, status: :ok, detail: detail, installable: installable}

  defp component(id, label, _present, detail, installable),
    do: %{id: id, label: label, status: :missing, detail: detail, installable: installable}

  defp command_component(id, label, {:ok, path}, installable),
    do: component(id, label, true, path, installable)

  defp command_component(id, label, {:error, reason}, installable),
    do: component(id, label, false, inspect(reason), installable)

  defp qemu_component({:ok, path}) do
    case qemu_health(path) do
      :ok ->
        component(:qemu, "Pebble QEMU", true, path, true)

      {:error, detail} ->
        component(:qemu, "Pebble QEMU", false, detail, false)
    end
  end

  defp qemu_component({:error, reason}) do
    component(:qemu, "Pebble QEMU", false, inspect(reason), true)
  end

  defp qemu_health(path) do
    case System.cmd(path, ["--version"], stderr_to_stdout: true) do
      {_output, 0} ->
        :ok

      {output, exit_code} ->
        {:error, qemu_health_detail(path, output, exit_code)}
    end
  rescue
    error -> {:error, "not runnable: #{Exception.message(error)}"}
  end

  defp qemu_health_detail(path, output, exit_code) do
    output = String.trim(output || "")

    cond do
      String.contains?(output, "libpixman-1.0.dylib") ->
        "#{path} is not runnable: missing x86_64 Homebrew pixman at /usr/local/opt/pixman. " <>
          "Install Rosetta and x86_64 Homebrew pixman with: arch -x86_64 /usr/local/bin/brew install pixman"

      String.contains?(output, "libSDL2-2.0.0.dylib") ->
        "#{path} is not runnable: missing x86_64 Homebrew sdl2 at /usr/local/opt/sdl2. " <>
          "Install Rosetta and x86_64 Homebrew sdl2 with: arch -x86_64 /usr/local/bin/brew install sdl2"

      String.contains?(output, "libgthread-2.0.0.dylib") ->
        "#{path} is not runnable: missing x86_64 Homebrew glib at /usr/local/opt/glib. " <>
          "Install Rosetta and x86_64 Homebrew glib with: arch -x86_64 /usr/local/bin/brew install glib"

      String.contains?(output, "Library not loaded") ->
        "#{path} is not runnable: #{single_line(output)}"

      library = missing_linux_shared_library(output) ->
        linux_shared_library_detail(path, library)

      output != "" ->
        "#{path} exited with #{exit_code}: #{single_line(output)}"

      true ->
        "#{path} exited with #{exit_code}"
    end
  end

  defp single_line(output) do
    output
    |> String.split("\n", trim: true)
    |> Enum.map(&String.trim/1)
    |> Enum.join(" ")
  end

  defp missing_linux_shared_library(output) do
    case Regex.run(~r/error while loading shared libraries: ([^:]+):/, output) do
      [_match, library] -> library
      _ -> nil
    end
  end

  defp linux_shared_library_detail(path, "libsndio.so.7") do
    "#{path} is not runnable: missing Linux shared library libsndio.so.7. " <>
      "Debian/Ubuntu: install libsndio7.0. " <>
      "Fedora: sndio is not currently in the standard Fedora repositories; install a compatible sndio package from a trusted source or build sndio from source, then recheck."
  end

  defp linux_shared_library_detail(path, library) do
    "#{path} is not runnable: missing Linux shared library #{library}. " <>
      "Install the OS package that provides #{library}, then recheck."
  end

  defp install_steps_for_component(id, platform)
       when id in [:qemu, :qemu_micro_flash, :qemu_spi_flash] do
    [
      %{name: :pebble_tool, fun: &install_pebble_tool/0},
      %{name: :pebble_sdk, fun: fn -> install_pebble_sdk() end},
      %{name: :qemu_images, fun: fn -> install_qemu_images(platform) end}
    ]
  end

  defp install_steps_for_component(:pypkjs, _platform) do
    [%{name: :pebble_tool, fun: &install_pebble_tool/0}]
  end

  defp install_steps_for_component(:pebble_cli, _platform) do
    [%{name: :pebble_tool, fun: &install_pebble_tool/0}]
  end

  defp install_steps_for_component(:pebble_sdk_python_env, _platform) do
    [%{name: :pebble_sdk, fun: fn -> install_pebble_sdk() end}]
  end

  defp install_steps_for_component(:pebble_sdk_node_modules, _platform) do
    [%{name: :pebble_sdk, fun: fn -> install_pebble_sdk() end}]
  end

  defp install_steps_for_component(:pebble_arm_gcc, _platform) do
    [
      %{name: :pebble_tool, fun: &install_pebble_tool/0},
      %{name: :pebble_sdk, fun: fn -> install_pebble_sdk() end}
    ]
  end

  defp install_steps_for_component(_id, _platform), do: []

  defp run_install_steps(steps) do
    Enum.reduce_while(steps, [], fn step, results ->
      result = run_install_step(step)
      results = results ++ [result]

      case result.status do
        :ok -> {:cont, results}
        :error -> {:halt, results}
      end
    end)
  end

  defp run_install_step(%{name: name, fun: fun}) do
    case fun.() do
      {:ok, output} -> %{name: name, status: :ok, output: output}
      {:error, reason} -> %{name: name, status: :error, output: inspect(reason)}
    end
  rescue
    error -> %{name: name, status: :error, output: Exception.message(error)}
  end

  defp install_pebble_sdk do
    version = config(:sdk_core_version, "4.9.169")
    sdk_root = sdk_version_root(version)
    preferred_root = preferred_sdk_root()

    opts =
      [
        sdk_version: version,
        python: pebble_tool_python()
      ]
      |> maybe_put_metadata_url(config(:sdk_core_metadata_url, nil))
      |> maybe_put_archive_path(config(:sdk_core_archive_path, nil))
      |> maybe_put_toolchain_archive_path(config(:sdk_toolchain_archive_path, nil))

    case ensure_sdk_roots_with_toolchain([sdk_root, preferred_root], opts) do
      :ok -> {:ok, "Pebble SDK #{version} is available in #{sdk_root}."}
      {:error, reason} -> {:error, reason}
    end
  end

  defp ensure_sdk_roots_with_toolchain(roots, opts) do
    roots
    |> Enum.uniq()
    |> Enum.reduce_while(:ok, fn root, :ok ->
      case ensure_sdk_with_toolchain(root, opts) do
        :ok -> {:cont, :ok}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp ensure_sdk_with_toolchain(sdk_root, opts) do
    with :ok <- SdkImages.ensure_sdk_core(sdk_root, opts),
         :ok <- SdkImages.ensure_toolchain(sdk_root, opts) do
      :ok
    end
  end

  defp install_qemu_images(platform) do
    image_root = preferred_qemu_image_root()

    opts =
      [
        image_root: image_root,
        sdk_version: config(:sdk_core_version, "4.9.169")
      ]
      |> maybe_put_metadata_url(config(:sdk_core_metadata_url, nil))
      |> maybe_put_archive_path(config(:sdk_core_archive_path, nil))

    case SdkImages.ensure_platform_images(platform, opts) do
      :ok -> {:ok, "QEMU images are available in #{Path.join(image_root, platform)}."}
      {:error, reason} -> {:error, reason}
    end
  end

  defp install_pebble_tool do
    cond do
      uv = System.find_executable("uv") ->
        install_pebble_tool_with_uv(uv)

      pipx = System.find_executable("pipx") ->
        case pebble_tool_python_bin() do
          {:ok, python} ->
            run_command(pipx, ["install", "--force", "--python", python, "pebble-tool"])

          {:error, reason} ->
            {:error, reason}
        end

      true ->
        {:error, :uv_or_pipx_not_found}
    end
  end

  defp install_pebble_tool_with_uv(uv) do
    tool_args = ["tool", "install", "--force", "--python", pebble_tool_python(), "pebble-tool"]

    case run_command(uv, tool_args) do
      {:ok, output} ->
        {:ok, output}

      {:error, %{output: output} = reason} ->
        if uv_python_missing?(output) do
          install_uv_python_and_retry_tool(uv, tool_args)
        else
          {:error, reason}
        end
    end
  end

  defp install_uv_python_and_retry_tool(uv, tool_args) do
    with {:ok, python_output} <- run_command(uv, ["python", "install", pebble_tool_python()]),
         {:ok, tool_output} <- run_command(uv, tool_args) do
      {:ok, String.trim(python_output <> "\n" <> tool_output)}
    else
      {:error, reason} -> {:error, reason}
    end
  end

  defp uv_python_missing?(output) when is_binary(output) do
    String.contains?(output, "No interpreter found for Python") and
      String.contains?(output, "uv python install")
  end

  defp uv_python_missing?(_output), do: false

  defp pebble_tool_python do
    case config(:pebble_tool_python, "3.13") do
      python when is_binary(python) and python != "" -> python
      _ -> "3.13"
    end
  end

  defp pebble_tool_python_bin do
    pebble_tool_python_candidates()
    |> Enum.find_value(fn candidate ->
      resolve_python_candidate(candidate)
    end)
    |> case do
      {:ok, path} -> {:ok, path}
      nil -> {:error, {:compatible_python_not_found, pebble_tool_python_candidates()}}
    end
  end

  defp resolve_python_candidate("/" <> _ = candidate) do
    if executable_file?(candidate), do: {:ok, candidate}
  end

  defp resolve_python_candidate(candidate) do
    case System.find_executable(candidate) do
      nil -> nil
      path -> {:ok, path}
    end
  end

  defp pebble_tool_python_candidates do
    configured = pebble_tool_python()

    cond do
      String.starts_with?(configured, "/") ->
        [configured]

      String.starts_with?(configured, "python") ->
        [configured]

      true ->
        ["python#{configured}", configured]
    end
  end

  defp run_command(command, args) do
    {output, exit_code} = System.cmd(command, args, stderr_to_stdout: true)

    if exit_code == 0 do
      {:ok, output}
    else
      {:error, %{command: Enum.join([command | args], " "), exit_code: exit_code, output: output}}
    end
  end

  defp render_install_results(results, after_status) do
    result_lines =
      Enum.map(results, fn result ->
        "[#{result.status}] #{result.name}\n#{String.trim(result.output || "")}"
      end)

    missing_lines =
      after_status.missing
      |> Enum.map(&"- #{&1.label}: #{&1.detail}")

    """
    #{Enum.join(result_lines, "\n\n")}

    Current status: #{after_status.status}
    #{if missing_lines == [], do: "All embedded emulator dependencies are present.", else: "Still missing:\n" <> Enum.join(missing_lines, "\n")}
    """
    |> String.trim()
  end

  defp maybe_download_qemu_images(platform) do
    image_root = preferred_qemu_image_root()

    cond do
      config(:download_images, true) != true ->
        :ok

      Enum.any?(qemu_image_roots(), &SdkImages.images_present?(&1, platform)) ->
        :ok

      true ->
        opts =
          [
            image_root: image_root,
            sdk_version: config(:sdk_core_version, "4.9.169")
          ]
          |> maybe_put_metadata_url(config(:sdk_core_metadata_url, nil))
          |> maybe_put_archive_path(config(:sdk_core_archive_path, nil))

        SdkImages.ensure_platform_images(platform, opts)
    end
  end

  defp maybe_put_metadata_url(opts, url) when is_binary(url) and url != "",
    do: Keyword.put(opts, :metadata_url, url)

  defp maybe_put_metadata_url(opts, _url), do: opts

  defp maybe_put_archive_path(opts, path) when is_binary(path) and path != "",
    do: Keyword.put(opts, :archive_path, path)

  defp maybe_put_archive_path(opts, _path), do: opts

  defp maybe_put_toolchain_archive_path(opts, path) when is_binary(path) and path != "",
    do: Keyword.put(opts, :toolchain_archive_path, path)

  defp maybe_put_toolchain_archive_path(opts, _path), do: opts

  defp file_size(path) when is_binary(path) do
    case File.stat(path) do
      {:ok, %{size: size}} -> size
      _ -> nil
    end
  end

  defp file_size(_path), do: nil

  defp alive?(pid) when is_pid(pid), do: Process.alive?(pid)
  defp alive?(_pid), do: false

  defp qemu_micro_flash_path(platform),
    do: File.exists?(Path.join(qemu_image_dir(platform), "qemu_micro_flash.bin"))

  defp qemu_spi_flash_available?(platform) do
    raw = Path.join(qemu_image_dir(platform), "qemu_spi_flash.bin")
    File.exists?(raw) or File.exists?(raw <> ".bz2")
  end

  defp qemu_image_roots do
    configured_root = config(:qemu_image_root, nil)

    configured_roots =
      if is_binary(configured_root) and configured_root != "", do: [configured_root], else: []

    sdk_roots = Enum.map(sdk_roots(), &Path.join(&1, "sdk-core/pebble"))

    (qemu_bin_image_roots() ++ configured_roots ++ sdk_roots)
    |> Enum.uniq()
  end

  defp preferred_qemu_image_root do
    case config(:qemu_image_root, nil) do
      root when is_binary(root) and root != "" ->
        root

      _ ->
        qemu_image_roots()
        |> List.first()
        |> case do
          root when is_binary(root) -> root
          nil -> ""
        end
    end
  end

  defp preferred_sdk_root do
    case config(:sdk_install_root, nil) do
      root when is_binary(root) and root != "" ->
        root

      _ ->
        sdk_roots()
        |> List.first()
        |> case do
          root when is_binary(root) -> root
          nil -> Path.expand(".pebble-sdk/SDKs/current", System.user_home!())
        end
    end
  end

  defp sdk_version_root(version) do
    case config(:sdk_install_root, nil) do
      root when is_binary(root) and root != "" ->
        root

      _ ->
        preferred_sdk_root()
        |> Path.dirname()
        |> Path.join(version)
    end
  end

  defp qemu_bin_image_roots do
    case qemu_bin() do
      {:ok, path} ->
        path
        |> qemu_bin_sdk_root()
        |> case do
          nil -> []
          root -> [Path.join(root, "sdk-core/pebble")]
        end

      {:error, _reason} ->
        []
    end
  end

  defp qemu_bin_sdk_root(path) when is_binary(path) do
    marker = "/toolchain/bin/"

    case String.split(path, marker, parts: 2) do
      [root, _bin] when root != "" -> root
      _ -> nil
    end
  end

  defp normalize_platform(platform) when is_binary(platform) do
    platform = platform |> String.downcase() |> String.trim()

    if platform in WatchModels.ordered_ids() do
      platform
    else
      WatchModels.default_id()
    end
  end

  defp normalize_platform(_), do: WatchModels.default_id()

  defp via(id), do: {:via, Registry, {Ide.Emulator.Registry, id}}

  defp schedule_idle_check(state),
    do: Process.send_after(self(), :idle_check, min(state.idle_timeout_ms, 60_000))

  defp cleanup_process(nil), do: :ok

  defp cleanup_process(pid) when is_pid(pid) do
    if Process.alive?(pid) do
      stop_process(pid, 1_000)
    else
      :ok
    end
  end

  defp stop_process(pid, timeout) do
    GenServer.stop(pid, :normal, timeout)
    :ok
  catch
    :exit, _reason ->
      Process.exit(pid, :kill)
      wait_for_process_exit(pid, timeout)
  end

  defp wait_for_process_exit(pid, timeout) do
    ref = Process.monitor(pid)

    receive do
      {:DOWN, ^ref, :process, ^pid, _reason} -> :ok
    after
      timeout ->
        Process.demonitor(ref, [:flush])
        :ok
    end
  end

  defp session_health(state) do
    cond do
      not start_processes?() ->
        :ok

      not live_pid?(state.qemu_pid) ->
        {:error, {:child_not_running, :qemu}}

      Map.get(state, :installing?, false) ->
        :ok

      not live_pid?(state.protocol_router_pid) ->
        {:error, {:child_not_running, :protocol_router}}

      not tcp_port_open?(state.vnc_port) ->
        {:error, {:port_not_ready, :vnc, state.vnc_port}}

      live_pid?(state.pypkjs_pid) and not tcp_port_open?(state.phone_ws_port) ->
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

  defp live_pid?(pid) when is_pid(pid), do: Process.alive?(pid)
  defp live_pid?(_pid), do: false

  defp random_id, do: Base.url_encode64(:crypto.strong_rand_bytes(16), padding: false)
  defp random_token, do: Base.url_encode64(:crypto.strong_rand_bytes(24), padding: false)
  defp now_ms, do: System.monotonic_time(:millisecond)

  defp config(key, default),
    do: Application.get_env(:ide, __MODULE__, []) |> Keyword.get(key, default)

  defp enabled?, do: config(:enabled, true) == true
  defp start_processes?, do: config(:start_processes, true) == true
end
