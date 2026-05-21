defmodule Ide.WasmEmulator.RuntimeBuilder do
  @moduledoc false

  use GenServer

  require Logger

  alias Ide.WasmEmulator

  @runtime_assets ~w(qemu-system-arm.js qemu-system-arm.wasm qemu-system-arm.worker.js)
  @lock_file ".build_in_progress"
  @log_file "build.log"
  @seed_dir "/opt/wasm-emulator-seed"
  @container_build_script "/opt/wasm-emulator-build/build_wasm_emulator_runtime.sh"
  @dev_build_script Path.expand("../../../../scripts/build_wasm_emulator_runtime.sh", __DIR__)

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @spec build_status() :: map()
  def build_status do
    if Process.whereis(__MODULE__) do
      GenServer.call(__MODULE__, :build_status)
    else
      default_build_status()
    end
  end

  @impl true
  def init(_opts) do
    seed_runtime_if_needed()

    state = %{task: nil}

    if runtime_ready?() do
      {:ok, state}
    else
      send(self(), :maybe_start_build)
      {:ok, state}
    end
  end

  @impl true
  def handle_call(:build_status, _from, state) do
    {:reply, current_build_status(state), state}
  end

  @impl true
  def handle_info(:maybe_start_build, state) do
    state =
      if should_start_build?() do
        start_build_task(state)
      else
        state
      end

    {:noreply, state}
  end

  @impl true
  def handle_info({ref, result}, %{task: %Task{ref: ref}} = state) do
    case result do
      :ok ->
        Logger.info("[WasmEmulator] background runtime build finished")

      {:error, reason} ->
        Logger.warning("[WasmEmulator] background runtime build failed: #{inspect(reason)}")
    end

    Process.demonitor(ref, [:flush])
    {:noreply, %{state | task: nil}}
  end

  @impl true
  def handle_info({:DOWN, ref, :process, _pid, _reason}, %{task: %Task{ref: ref}} = state) do
    {:noreply, %{state | task: nil}}
  end

  def handle_info(_message, state), do: {:noreply, state}

  @spec seed_runtime_if_needed() :: :ok
  defp seed_runtime_if_needed do
    if runtime_ready?() do
      :ok
    else
      Enum.each(seed_dirs(), &copy_seed/1)
      :ok
    end
  end

  @spec seed_dirs() :: [String.t()]
  defp seed_dirs do
    priv_seed = Path.join(:code.priv_dir(:ide), "wasm_emulator")

    [@seed_dir, priv_seed]
    |> Enum.uniq()
    |> Enum.filter(&is_binary/1)
  end

  @spec copy_seed(String.t()) :: :ok
  defp copy_seed(seed_dir) do
    seed_js = Path.join(seed_dir, "qemu-system-arm.js")

    if File.regular?(seed_js) and not runtime_ready?() do
      root = WasmEmulator.asset_root()
      File.mkdir_p!(root)
      copy_tree!(seed_dir, root)
      Logger.info("[WasmEmulator] seeded runtime assets from #{seed_dir}")
    end

    :ok
  end

  @spec copy_tree!(String.t(), String.t()) :: :ok
  defp copy_tree!(src, dest) do
    case File.ls(src) do
      {:ok, entries} ->
        Enum.each(entries, fn entry ->
          src_path = Path.join(src, entry)
          dest_path = Path.join(dest, entry)

          cond do
            File.dir?(src_path) ->
              File.mkdir_p!(dest_path)
              copy_tree!(src_path, dest_path)

            true ->
              File.cp!(src_path, dest_path)
          end
        end)

      {:error, reason} ->
        raise "could not read seed directory #{src}: #{inspect(reason)}"
    end
  end

  @spec should_start_build?() :: boolean()
  defp should_start_build? do
    build_enabled?() and not runtime_ready?() and not build_in_progress?() and
      is_binary(build_script())
  end

  @spec start_build_task(map()) :: map()
  defp start_build_task(state) do
    root = WasmEmulator.asset_root()
    File.mkdir_p!(root)
    File.write!(Path.join(root, @lock_file), "1\n")

    task =
      Task.async(fn ->
        try do
          run_build_script(root)
        after
          File.rm(Path.join(root, @lock_file))
        end
      end)

    Logger.info("[WasmEmulator] background runtime build started")
    %{state | task: task}
  end

  @spec run_build_script(String.t()) :: :ok | {:error, term()}
  defp run_build_script(root) do
    cache_dir = Path.join(root, "cache")
    log_path = Path.join(root, @log_file)
    File.mkdir_p!(cache_dir)

    env = [
      {"ELM_PEBBLE_WASM_OUTPUT_DIR", root},
      {"ELM_PEBBLE_WASM_CACHE_DIR", cache_dir},
      {"ELM_PEBBLE_WASM_BRIDGE_DIR", bridge_dir()}
    ]

    case System.cmd("sh", [build_script()], env: env, stderr_to_stdout: true) do
      {output, 0} ->
        File.write!(log_path, output)
        if runtime_ready?(), do: :ok, else: {:error, :runtime_assets_missing}

      {output, code} ->
        File.write!(log_path, output)
        {:error, {:exit, code}}
    end
  end

  @spec current_build_status(map()) :: map()
  defp current_build_status(state) do
    cond do
      runtime_ready?() ->
        %{status: "ready", in_progress?: false, log_path: log_path()}

      match?(%{task: %Task{}}, state) or build_in_progress?() ->
        %{status: "building", in_progress?: true, log_path: log_path()}

      build_failed?() ->
        %{status: "failed", in_progress?: false, log_path: log_path()}

      true ->
        %{status: "missing", in_progress?: false, log_path: log_path()}
    end
  end

  @spec default_build_status() :: map()
  defp default_build_status do
    cond do
      runtime_ready?() ->
        %{status: "ready", in_progress?: false, log_path: log_path()}

      build_in_progress?() ->
        %{status: "building", in_progress?: true, log_path: log_path()}

      build_failed?() ->
        %{status: "failed", in_progress?: false, log_path: log_path()}

      true ->
        %{status: "missing", in_progress?: false, log_path: log_path()}
    end
  end

  @spec runtime_ready?() :: boolean()
  defp runtime_ready? do
    root = WasmEmulator.asset_root()

    Enum.all?(@runtime_assets, fn asset ->
      File.regular?(Path.join(root, asset))
    end)
  end

  @spec build_in_progress?() :: boolean()
  defp build_in_progress? do
    File.regular?(Path.join(WasmEmulator.asset_root(), @lock_file))
  end

  @spec build_failed?() :: boolean()
  defp build_failed? do
    path = log_path()
    File.regular?(path) and not runtime_ready?() and not build_in_progress?()
  end

  @spec build_enabled?() :: boolean()
  defp build_enabled? do
    case Application.get_env(:ide, :wasm_emulator_build_on_start) do
      false -> false
      _ -> env_build_enabled?()
    end
  end

  @spec env_build_enabled?() :: boolean()
  defp env_build_enabled? do
    case System.get_env("ELM_PEBBLE_WASM_BUILD_ON_START", "1") do
      value when value in ["0", "false", "no"] -> false
      _ -> true
    end
  end

  @spec build_script() :: String.t() | nil
  defp build_script do
    env = System.get_env("ELM_PEBBLE_WASM_BUILD_SCRIPT")

    cond do
      is_binary(env) and env != "" and File.regular?(env) ->
        env

      File.regular?(@container_build_script) ->
        @container_build_script

      File.regular?(@dev_build_script) ->
        @dev_build_script

      true ->
        nil
    end
  end

  @spec bridge_dir() :: String.t()
  defp bridge_dir do
    env = System.get_env("ELM_PEBBLE_WASM_BRIDGE_DIR")

    cond do
      is_binary(env) and env != "" ->
        env

      File.dir?("/opt/wasm-emulator-build/runtime_bridge") ->
        "/opt/wasm-emulator-build/runtime_bridge"

      true ->
        Path.join(:code.priv_dir(:ide), "wasm_emulator/runtime_bridge")
    end
  end

  @spec log_path() :: String.t()
  defp log_path, do: Path.join(WasmEmulator.asset_root(), @log_file)
end
