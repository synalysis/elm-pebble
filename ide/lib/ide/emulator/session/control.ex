defmodule Ide.Emulator.Session.Control do
  @moduledoc false

  alias Ide.Debugger.SimulatorSettings
  alias Ide.Emulator.{QemuControl, Types}
  alias Ide.Emulator.PebbleProtocol.Router
  alias Ide.Emulator.Session.ProcessHost

  @spec handle_qemu_packet(Types.session_state(), non_neg_integer(), binary()) ::
          {:reply, :ok | {:error, Types.session_error()}, Types.session_state()}
  def handle_qemu_packet(state, protocol, payload) do
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

  @spec apply_simulator_settings(Types.session_state(), Types.simulator_settings()) ::
          {:reply, {:ok, Types.apply_settings_result()} | {:error, Types.apply_settings_error()},
           Types.session_state()}
  def apply_simulator_settings(state, settings) when is_map(settings) do
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
      case validate_commands_offline(commands) do
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

  defp validate_commands_offline(commands) do
    Enum.reduce_while(commands, :ok, fn %{protocol: protocol, payload: payload}, :ok ->
      case QemuControl.validate_payload(protocol, payload) do
        :ok -> {:cont, :ok}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end
end
