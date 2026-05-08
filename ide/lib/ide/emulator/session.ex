defmodule Ide.Emulator.Session do
  @moduledoc false

  use GenServer

  require Logger

  alias Ide.Emulator.SdkImages
  alias Ide.Emulator.PebbleProtocol.Router
  alias Ide.WatchModels

  @default_idle_timeout_ms 5 * 60 * 1000

  @type state :: %{
          id: String.t(),
          token: String.t(),
          project_slug: String.t(),
          platform: String.t(),
          artifact_path: String.t() | nil,
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

  @spec info(pid()) :: map()
  def info(pid), do: GenServer.call(pid, :info)

  @spec artifact_file_path(pid()) :: String.t() | nil
  def artifact_file_path(pid), do: GenServer.call(pid, :artifact_file_path)

  @spec install(pid()) :: {:ok, map()} | {:error, term()}
  def install(pid), do: GenServer.call(pid, :install, :infinity)

  @spec local_port(pid(), :vnc | :phone) :: pos_integer()
  def local_port(pid, kind), do: GenServer.call(pid, {:local_port, kind})

  @spec ping(pid()) :: {:ok, map()}
  def ping(pid), do: GenServer.call(pid, :ping)

  @spec kill(pid()) :: :ok
  def kill(pid) do
    _ = GenServer.stop(pid, :normal, :infinity)
    :ok
  catch
    :exit, _ -> :ok
  end

  @spec runtime_status(term()) :: map()
  def runtime_status(platform \\ nil) do
    platform = normalize_platform(platform)

    components = [
      component(
        :embedded_emulator,
        "Embedded emulator",
        enabled?(),
        if(enabled?(), do: "enabled", else: "disabled by configuration"),
        false
      ),
      command_component(:pebble_cli, "Pebble CLI", pebble_bin(), true),
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

    results = Enum.map(steps, &run_install_step/1)
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
         {:ok, state} <- maybe_start_protocol_router(state),
         {:ok, state} <- maybe_start_pypkjs(state) do
      schedule_idle_check(state)
      {:ok, state}
    else
      {:error, reason} -> {:stop, reason}
    end
  end

  @impl true
  def handle_call(:info, _from, state), do: {:reply, public_info(state), state}

  def handle_call(:artifact_file_path, _from, state), do: {:reply, state.artifact_path, state}

  def handle_call(:install, _from, %{artifact_path: nil} = state),
    do: {:reply, {:error, :artifact_not_found}, state}

  def handle_call(:install, _from, %{protocol_router_pid: nil} = state),
    do: {:reply, {:error, :embedded_protocol_router_not_started}, state}

  def handle_call(:install, _from, state) do
    result =
      Ide.Emulator.PBWInstaller.install(
        state.protocol_router_pid,
        state.artifact_path,
        state.platform,
        install_opts()
      )

    {:reply, result, state}
  end

  def handle_call({:local_port, :vnc}, _from, state), do: {:reply, state.vnc_port, state}
  def handle_call({:local_port, :phone}, _from, state), do: {:reply, state.phone_ws_port, state}

  def handle_call(:ping, _from, state) do
    state = %{state | last_ping_ms: now_ms()}
    {:reply, {:ok, public_info(state)}, state}
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

  def handle_info({:EXIT, _pid, reason}, state) do
    Logger.debug("embedded emulator child exited: #{inspect(reason)}")
    {:noreply, state}
  end

  def handle_info(_message, state), do: {:noreply, state}

  @impl true
  def terminate(_reason, state) do
    cleanup_process(state.qemu_pid)
    cleanup_process(state.pypkjs_pid)
    cleanup_process(state.protocol_router_pid)
    cleanup_path(state.spi_image_path)
    cleanup_dir(state.persist_dir)
    :ok
  end

  @spec qemu_args(map()) :: [String.t()]
  def qemu_args(state) do
    image_dir = qemu_image_dir(state.platform)
    micro_flash = Path.join(image_dir, "qemu_micro_flash.bin")

    base = [
      "-rtc",
      "base=localtime",
      "-serial",
      "null",
      "-serial",
      "tcp:127.0.0.1:#{state.bt_port},server=on,wait=off",
      "-serial",
      "tcp:127.0.0.1:#{state.console_port},server=on,wait=off",
      "-pflash",
      micro_flash,
      "-monitor",
      "stdio",
      "-L",
      pc_bios_dir(),
      "-vnc",
      ":#{state.vnc_display}"
    ]

    base ++ machine_args(state.platform, state.spi_image_path)
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

  @spec machine_args(String.t(), String.t() | nil) :: [String.t()]
  def machine_args(platform, spi_image_path) do
    case platform do
      "aplite" ->
        ["-machine", "pebble-bb2", "-mtdblock", spi_image_path, "-cpu", "cortex-m3"]

      "basalt" ->
        ["-machine", "pebble-snowy-bb", "-cpu", "cortex-m4", "-pflash", spi_image_path]

      "chalk" ->
        ["-machine", "pebble-s4-bb", "-cpu", "cortex-m4", "-pflash", spi_image_path]

      "diorite" ->
        ["-machine", "pebble-silk-bb", "-mtdblock", spi_image_path, "-cpu", "cortex-m4"]

      "emery" ->
        ["-machine", "pebble-snowy-emery-bb", "-cpu", "cortex-m4", "-pflash", spi_image_path]

      "flint" ->
        ["-machine", "pebble-silk-bb", "-cpu", "cortex-m4", "-mtdblock", spi_image_path]

      "gabbro" ->
        ["-machine", "pebble-snowy-emery-bb", "-cpu", "cortex-m4", "-pflash", spi_image_path]

      _ ->
        machine_args(WatchModels.default_id(), spi_image_path)
    end
  end

  defp build_state(opts) do
    platform = Keyword.fetch!(opts, :platform)

    with {:ok, ports} <- allocate_ports(6),
         {:ok, spi_image_path} <- make_spi_image(platform),
         {:ok, persist_dir} <- make_persist_dir() do
      [console_port, bt_port, protocol_proxy_port, phone_ws_port, vnc_port, vnc_ws_port] = ports

      {:ok,
       %{
         id: Keyword.fetch!(opts, :id),
         token: random_token(),
         project_slug: Keyword.get(opts, :project_slug, ""),
         platform: platform,
         artifact_path: Keyword.get(opts, :artifact_path),
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
         spi_image_path: spi_image_path,
         persist_dir: persist_dir,
         last_ping_ms: now_ms(),
         idle_timeout_ms: config(:idle_timeout_ms, @default_idle_timeout_ms)
       }}
    end
  end

  defp maybe_start_qemu(state) do
    if start_processes?() do
      with {:ok, qemu_bin} <- qemu_bin(),
           {:ok, pid} <- start_daemon(qemu_bin, qemu_args(state), "qemu:#{state.id}"),
           :ok <- wait_for_qemu_boot(pid, state.console_port, 60_000) do
        {:ok, %{state | qemu_pid: pid}}
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
           :ok <- wait_for_daemon(pid, state.phone_ws_port, 10_000) do
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
        {:error, {:qemu_boot_timeout, String.slice(received, -256, 256)}}

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
    String.contains?(data, ["<SDK Home>", "<Launcher>", "Ready for communication"])
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

  defp make_spi_image(platform) do
    source_dir = qemu_image_dir(platform)
    raw = Path.join(source_dir, "qemu_spi_flash.bin")
    bz2 = raw <> ".bz2"

    with {:ok, path} <- temp_path("spi-#{platform}", ".bin") do
      cond do
        File.exists?(raw) ->
          File.cp(raw, path)
          {:ok, path}

        File.exists?(bz2) ->
          decompress_bzip2(bz2, path)

        start_processes?() ->
          {:error, {:qemu_flash_image_not_found, source_dir}}

        true ->
          {:ok, path}
      end
    end
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

  defp make_persist_dir do
    dir = Path.join(System.tmp_dir!(), "elm-pebble-pypkjs-#{random_id()}")

    case File.mkdir_p(dir) do
      :ok -> {:ok, dir}
      {:error, reason} -> {:error, {:persist_dir_failed, reason}}
    end
  end

  defp temp_path(prefix, suffix) do
    path = Path.join(System.tmp_dir!(), "#{prefix}-#{random_id()}#{suffix}")

    case File.touch(path) do
      :ok -> {:ok, path}
      {:error, reason} -> {:error, {:temp_path_failed, reason}}
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

    system_roots = ["/usr/share/qemu", "/usr/local/share/qemu"]

    sdk_roots =
      Enum.map(sdk_roots(), fn root ->
        path = Path.join(root, "toolchain/lib/pc-bios")
        path
      end)

    configured_roots ++ system_roots ++ sdk_roots
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

        [
          Path.expand(".pebble-sdk/SDKs/current", home),
          Path.expand(".pebble-sdk/SDKs/4.9.169", home),
          Path.expand(".pebble-sdk/SDKs/4.9.148", home),
          Path.expand("Library/Application Support/Pebble SDK/SDKs/current", home),
          Path.expand("Library/Application Support/Pebble SDK/SDKs/4.9.169", home),
          Path.expand("Library/Application Support/Pebble SDK/SDKs/4.9.148", home),
          Path.expand("Library/Application Support/Pebble SDK/SDKs/4.9.77", home)
        ]
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

  defp install_steps_for_component(id, platform)
       when id in [:qemu, :qemu_micro_flash, :qemu_spi_flash] do
    [
      %{name: :pebble_sdk, fun: fn -> install_pebble_sdk() end},
      %{name: :qemu_images, fun: fn -> install_qemu_images(platform) end}
    ]
  end

  defp install_steps_for_component(:pypkjs, _platform) do
    [%{name: :pypkjs, fun: &install_pypkjs/0}]
  end

  defp install_steps_for_component(:pebble_cli, _platform) do
    [%{name: :pebble_tool, fun: &install_pypkjs/0}]
  end

  defp install_steps_for_component(_id, _platform), do: []

  defp run_install_step(%{name: name, fun: fun}) do
    case fun.() do
      {:ok, output} -> %{name: name, status: :ok, output: output}
      {:error, reason} -> %{name: name, status: :error, output: inspect(reason)}
    end
  rescue
    error -> %{name: name, status: :error, output: Exception.message(error)}
  end

  defp install_pebble_sdk do
    version = config(:sdk_core_version, "4.9.148")

    with {:ok, pebble_bin} <- pebble_bin(),
         {:ok, install_output} <- run_command(pebble_bin, ["sdk", "install", version]),
         {:ok, activate_output} <- run_command(pebble_bin, ["sdk", "activate", version]) do
      {:ok, String.trim(install_output <> "\n" <> activate_output)}
    else
      {:error, reason} -> {:error, reason}
    end
  end

  defp install_qemu_images(platform) do
    image_root = preferred_qemu_image_root()

    opts =
      [
        image_root: image_root,
        sdk_version: config(:sdk_core_version, "4.9.148")
      ]
      |> maybe_put_metadata_url(config(:sdk_core_metadata_url, nil))

    case SdkImages.ensure_platform_images(platform, opts) do
      :ok -> {:ok, "QEMU images are available in #{Path.join(image_root, platform)}."}
      {:error, reason} -> {:error, reason}
    end
  end

  defp install_pypkjs do
    cond do
      uv = System.find_executable("uv") ->
        run_command(uv, ["tool", "install", "pebble-tool"])

      pipx = System.find_executable("pipx") ->
        run_command(pipx, ["install", "pebble-tool"])

      true ->
        {:error, :uv_or_pipx_not_found}
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
            sdk_version: config(:sdk_core_version, "4.9.148")
          ]
          |> maybe_put_metadata_url(config(:sdk_core_metadata_url, nil))

        SdkImages.ensure_platform_images(platform, opts)
    end
  end

  defp maybe_put_metadata_url(opts, url) when is_binary(url) and url != "",
    do: Keyword.put(opts, :metadata_url, url)

  defp maybe_put_metadata_url(opts, _url), do: opts

  defp install_opts do
    [
      chunk_size: config(:native_install_chunk_size, 1_000),
      timeout_ms: config(:native_install_timeout_ms, 30_000),
      part_delay_ms: config(:native_install_part_delay_ms, 0)
    ]
  end

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
  defp cleanup_process(pid) when is_pid(pid), do: Process.exit(pid, :normal)

  defp cleanup_path(nil), do: :ok
  defp cleanup_path(path), do: File.rm(path)

  defp cleanup_dir(nil), do: :ok
  defp cleanup_dir(path), do: File.rm_rf(path)

  defp random_id, do: Base.url_encode64(:crypto.strong_rand_bytes(16), padding: false)
  defp random_token, do: Base.url_encode64(:crypto.strong_rand_bytes(24), padding: false)
  defp now_ms, do: System.monotonic_time(:millisecond)

  defp config(key, default),
    do: Application.get_env(:ide, __MODULE__, []) |> Keyword.get(key, default)

  defp enabled?, do: config(:enabled, true) == true
  defp start_processes?, do: config(:start_processes, true) == true
end
