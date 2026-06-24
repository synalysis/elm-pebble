defmodule IdeWeb.WorkspaceLive.DebuggerFlow.Configuration do
  @moduledoc false

  alias IdeWeb.WorkspaceLive.DebuggerFlow.Core
  alias IdeWeb.WorkspaceLive.Types

  @spec handle_event(String.t(), Types.event_params(), Phoenix.LiveView.Socket.t()) ::
          {:noreply, Phoenix.LiveView.Socket.t()}
  defdelegate handle_event(event, params, socket), to: Core
end
