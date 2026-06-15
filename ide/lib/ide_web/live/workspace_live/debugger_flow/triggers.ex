defmodule IdeWeb.WorkspaceLive.DebuggerFlow.Triggers do
  @moduledoc false

  alias IdeWeb.WorkspaceLive.DebuggerFlow.Core

  @spec handle_event(String.t(), map(), Phoenix.LiveView.Socket.t()) :: {:noreply, Phoenix.LiveView.Socket.t()}
  defdelegate handle_event(event, params, socket), to: Core
end
