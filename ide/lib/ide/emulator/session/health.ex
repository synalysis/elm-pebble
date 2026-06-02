defmodule Ide.Emulator.Session.Health do
  @moduledoc false

  require Logger

  alias Ide.Emulator.Session.{Config, ProcessHost}
  alias Ide.Emulator.Types

  @spec check(Types.session_state()) :: :ok | {:error, Types.session_error()}
  def check(state) do
    cond do
      not Config.start_processes?() ->
        :ok

      Map.get(state, :installing?, false) ->
        :ok

      not ProcessHost.live_pid?(state.qemu_pid) ->
        {:error, {:child_not_running, :qemu}}

      not ProcessHost.live_pid?(state.protocol_router_pid) ->
        {:error, {:child_not_running, :protocol_router}}

      not ProcessHost.tcp_port_open?(state.vnc_port) ->
        {:error, {:port_not_ready, :vnc, state.vnc_port}}

      ProcessHost.live_pid?(state.pypkjs_pid) and
          not ProcessHost.tcp_port_open?(state.phone_ws_port) ->
        {:error, {:port_not_ready, :phone, state.phone_ws_port}}

      true ->
        :ok
    end
  end

  @spec child_role(Types.session_state(), pid()) :: :qemu | :protocol_router | :pypkjs | nil
  def child_role(state, pid) when is_pid(pid) do
    cond do
      pid == state.qemu_pid -> :qemu
      pid == state.protocol_router_pid -> :protocol_router
      pid == state.pypkjs_pid -> :pypkjs
      true -> nil
    end
  end

  def child_role(_state, _pid), do: nil

  @spec handle_exit(Types.session_state(), pid(), term()) ::
          {:noreply, Types.session_state()}
          | {:stop, {:shutdown, {:child_exited, atom(), term()}}, Types.session_state()}
  def handle_exit(state, pid, reason) do
    case child_role(state, pid) do
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
end
