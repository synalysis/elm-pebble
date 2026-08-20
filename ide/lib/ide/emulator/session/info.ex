defmodule Ide.Emulator.Session.Info do
  @moduledoc false
  alias Ide.Emulator.Types, as: Types


  alias Ide.Emulator.{QemuControl, Types}
  alias Ide.Emulator.PebbleProtocol.Router
  alias Ide.Emulator.Session.{Config, ProcessHost}
  alias Ide.WatchModels

  @spec public_info(Types.session_state()) :: Types.session_info()
  def public_info(state) do
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
      request_app_logs_path: "/api/emulator/#{state.id}/request-app-logs",
      vnc_path: "/api/emulator/#{state.id}/ws/vnc",
      phone_path: "/api/emulator/#{state.id}/ws/phone",
      ping_path: "/api/emulator/#{state.id}/ping",
      kill_path: "/api/emulator/#{state.id}/kill",
      screen: screen,
      controls: supported_controls(),
      backend_enabled: Config.enabled?(),
      display_ready: display_ready?(state),
      phone_bridge_ready: phone_bridge_ready?(state),
      installing: Map.get(state, :installing?, false),
      runtime_stats: router_runtime_stats(Map.get(state, :protocol_router_pid))
    }
  end

  @spec display_ready?(Types.session_state()) :: boolean()
  def display_ready?(state) do
    Config.start_processes?() and ProcessHost.live_pid?(state.qemu_pid) and
      Map.get(state, :vnc_banner_ready, false)
  end

  @spec phone_bridge_ready?(Types.session_state()) :: boolean()
  def phone_bridge_ready?(state) do
    Config.start_processes?() and ProcessHost.live_pid?(state.pypkjs_pid) and
      tcp_port_open?(state.phone_ws_port)
  end

  @spec supported_controls() :: [String.t()]
  def supported_controls, do: QemuControl.supported_controls()

  @spec tcp_port_open?(integer() | term()) :: boolean()

  defp tcp_port_open?(port) when is_integer(port) and port > 0 do
    ProcessHost.tcp_port_open?(port)
  end

  defp tcp_port_open?(_), do: false

  @spec router_runtime_stats(pid() | nil) :: Types.runtime_stats() | nil
  defp router_runtime_stats(pid) when is_pid(pid) do
    if Process.alive?(pid) do
      case Router.runtime_stats(pid) do
        {:ok, stats} -> stats
        _ -> nil
      end
    else
      nil
    end
  end

  defp router_runtime_stats(_), do: nil
end
