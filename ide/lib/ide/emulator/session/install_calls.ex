defmodule Ide.Emulator.Session.InstallCalls do
  @moduledoc false

  require Logger

  alias Ide.Emulator.{InstallPrep, Types, Workflow}
  alias Ide.Emulator.Session.{Config, Lifecycle, ProcessHost, Startup}

  @spec install_context(Types.session_state()) ::
          {:reply, {:ok, Types.install_context()} | {:error, Types.session_atom_error()},
           Types.session_state()}
  def install_context(%{artifact_path: nil} = state),
    do: {:reply, {:error, :artifact_not_found}, state}

  def install_context(%{protocol_router_pid: nil} = state),
    do: {:reply, {:error, :embedded_protocol_router_not_started}, state}

  def install_context(state) do
    {:reply,
     {:ok,
      %{
        protocol_router_pid: state.protocol_router_pid,
        artifact_path: state.artifact_path,
        platform: state.platform,
        console_port: state.console_port
      }}, state}
  end

  @spec direct_install_context(Types.session_state()) ::
          {:reply, {:ok, map()} | {:error, Types.session_atom_error()}, Types.session_state()}
  def direct_install_context(%{qemu_pid: nil} = state),
    do: {:reply, {:error, :embedded_protocol_router_not_started}, state}

  def direct_install_context(state) do
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

  @spec prepare_for_install(Types.session_state()) ::
          {:reply, :ok | {:error, term()}, Types.session_state()}
  def prepare_for_install(state) do
    reuse? = not InstallPrep.reset_needed?(state)

    Logger.debug(
      "embedded emulator prepare_for_install session=#{state.id} platform=#{state.platform} reuse_qemu=#{reuse?}"
    )

    with {:ok, state} <- Workflow.refresh_session_artifact(state) do
      prepare_for_install_after_refresh(state, reuse?)
    else
      {:error, reason} ->
        {:reply, {:error, reason}, %{state | installing?: false}}
    end
  end

  defp prepare_for_install_after_refresh(state, reuse?) do
    result =
      if reuse? do
        Startup.prepare_running_session_for_install(state)
      else
        with {:ok, state} <- Startup.reset_for_install(state),
             {:ok, state} <- Startup.maybe_start_pypkjs_if_needed(state) do
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

  @spec install_finished(Types.session_state()) :: {:reply, :ok, Types.session_state()}
  def install_finished(state) do
    if Config.start_processes?() and not ProcessHost.live_pid?(state.pypkjs_pid) do
      send(self(), :restart_pypkjs_after_install)
    end

    {:reply, :ok, %{state | installing?: false, last_ping_ms: Lifecycle.now_ms()}}
  end

  @spec restart_pypkjs_after_install(Types.session_state()) :: Types.session_state()
  def restart_pypkjs_after_install(state) do
    if Config.start_processes?() and not ProcessHost.live_pid?(state.pypkjs_pid) do
      case Startup.maybe_start_pypkjs(state) do
        {:ok, state} -> state
        {:error, _reason} -> state
      end
    else
      state
    end
  end

  @spec reset_for_install(Types.session_state()) ::
          {:reply, :ok | {:error, term()}, Types.session_state()}
  def reset_for_install(state) do
    Logger.debug(
      "embedded emulator reset_for_install session=#{state.id} platform=#{state.platform}"
    )

    case Startup.reset_for_install(state) do
      {:ok, state} ->
        {:reply, :ok, state}

      {:error, reason} ->
        {:reply, {:error, reason}, %{state | installing?: false}}
    end
  end

  @spec reset_for_install_retry(Types.session_state()) ::
          {:reply, :ok | {:error, term()}, Types.session_state()}
  def reset_for_install_retry(state) do
    case Startup.reset_for_install(state) do
      {:ok, state} -> {:reply, :ok, state}
      {:error, reason} -> {:reply, {:error, reason}, %{state | installing?: false}}
    end
  end

  @spec restart_protocol_router(Types.session_state()) ::
          {:reply, :ok | {:error, term()}, Types.session_state()}
  def restart_protocol_router(%{protocol_router_pid: nil} = state) do
    case Startup.maybe_start_protocol_router(state) do
      {:ok, state} -> {:reply, :ok, %{state | installing?: false}}
      {:error, reason} -> {:reply, {:error, reason}, %{state | installing?: false}}
    end
  end

  def restart_protocol_router(state), do: {:reply, :ok, state}

  @spec restart_pypkjs(Types.session_state()) ::
          {:reply, :ok | {:error, term()}, Types.session_state()}
  def restart_pypkjs(state) do
    ProcessHost.cleanup_process(state.pypkjs_pid)
    state = %{state | pypkjs_pid: nil}

    case Startup.maybe_start_pypkjs(state) do
      {:ok, state} -> {:reply, :ok, state}
      {:error, reason} -> {:reply, {:error, reason}, state}
    end
  end
end
