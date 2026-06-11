defmodule IdeWeb.WorkspaceLive.DebuggerFlow do
  @moduledoc false

  alias IdeWeb.WorkspaceLive.DebuggerFlow.Core

  @type socket :: Phoenix.LiveView.Socket.t()
  @type lv_noreply :: {:noreply, socket()}

  defdelegate handle_simulator_save_settings_event(params, socket), to: Core
  defdelegate handle_event(event, params, socket), to: Core
  defdelegate handle_async(name, result, socket), to: Core
  defdelegate handle_info(message, socket), to: Core
  defdelegate debugger_session_active?(socket), to: Core
  defdelegate begin_debugger_bootstrap(socket, project), to: Core
  defdelegate complete_debugger_bootstrap(socket, result), to: Core
  defdelegate clear_debugger_bootstrap_busy(socket), to: Core
  defdelegate project_debugger_timeline_mode(project), to: Core
  defdelegate normalize_debugger_watch_profile_id(value), to: Core
  defdelegate maybe_schedule_debugger_auto_fire_refresh(socket), to: Core
end
