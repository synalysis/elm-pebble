defmodule IdeWeb.WorkspaceLive.DebuggerPage.Render do
  @moduledoc false

  alias IdeWeb.WorkspaceLive.DebuggerPage.Core
  alias IdeWeb.WorkspaceLive.DebuggerPage.Assigns

  @spec render(Assigns.t()) :: Phoenix.LiveView.Rendered.t()
  defdelegate render(assigns), to: Core
end
