defmodule Ide.Emulator.Session.Pypkjs do
  @moduledoc false

  alias Ide.Emulator.Session.{Bins, Config, ProcessHost, Qemu}
  alias Ide.Emulator.Types

  @spec args(Types.pypkjs_args_state()) :: [String.t()]
  def args(state) do
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

  @spec command(String.t()) ::
          {:ok, String.t(), [String.t()]} | {:error, Types.session_atom_error()}
  def command(pypkjs_bin) do
    wrapper_path = Path.expand("../../../../priv/python/embedded_pypkjs.py", __DIR__)

    with {:ok, python} <- python_from_shebang(pypkjs_bin),
         true <- File.exists?(wrapper_path) do
      {:ok, python, [wrapper_path]}
    else
      false -> {:ok, pypkjs_bin, []}
      {:error, _reason} -> {:ok, pypkjs_bin, []}
    end
  end

  @spec local_port_call_timeout(:phone | :vnc) :: pos_integer()
  def local_port_call_timeout(:phone) do
    Config.config(
      :phone_local_port_timeout_ms,
      Config.config(:pypkjs_ready_timeout_ms, 30_000) + 5_000
    )
  end

  def local_port_call_timeout(_kind), do: 5_000

  @spec maybe_start(Types.session_state() | Types.pypkjs_start_state()) ::
          {:ok, Types.session_state() | Types.pypkjs_start_state()}
          | {:error, Types.session_error()}
  def maybe_start(%{pypkjs_pid: pid} = state) when is_pid(pid) do
    if ProcessHost.live_pid?(pid),
      do: {:ok, state},
      else: maybe_start(Map.put(state, :pypkjs_pid, nil))
  end

  def maybe_start(state) do
    if Config.start_processes?() do
      with {:ok, pypkjs_bin} <- Bins.pypkjs_bin(),
           {:ok, command, args_prefix} <- command(pypkjs_bin),
           {:ok, pid} <-
             ProcessHost.start_daemon(command, args_prefix ++ args(state), "pypkjs:#{state.id}"),
           :ok <-
             ProcessHost.wait_for_daemon(
               pid,
               state.phone_ws_port,
               Config.config(:pypkjs_ready_timeout_ms, 30_000)
             ) do
        {:ok, Map.put(state, :pypkjs_pid, pid)}
      end
    else
      {:ok, state}
    end
  end

  defp maybe_append_layout_arg(args, state) do
    layout_path = Path.join(Qemu.image_dir(state.platform), "layouts.json")

    if File.exists?(layout_path) do
      args ++ ["--layout", layout_path]
    else
      args
    end
  end

  @spec handle_local_port(Types.session_state()) ::
          {:reply, pos_integer() | {:error, Types.session_error()}, Types.session_state()}
  def handle_local_port(%{pypkjs_pid: nil} = state) do
    case maybe_start(state) do
      {:ok, state} -> {:reply, state.phone_ws_port, state}
      {:error, reason} -> {:reply, {:error, reason}, state}
    end
  end

  def handle_local_port(state), do: {:reply, state.phone_ws_port, state}

  defp python_from_shebang(pypkjs_bin) do
    with {:ok, <<"#!", rest::binary>>} <- File.read(pypkjs_bin),
         [first_line | _] <- String.split(rest, "\n", parts: 2),
         python when python != "" <- String.trim(first_line),
         true <- Bins.executable_file?(python) do
      {:ok, python}
    else
      _ -> {:error, :pypkjs_python_not_found}
    end
  end
end
