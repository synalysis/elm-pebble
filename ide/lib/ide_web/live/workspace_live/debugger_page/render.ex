defmodule IdeWeb.WorkspaceLive.DebuggerPage.Render do
  @moduledoc false

  alias IdeWeb.WorkspaceLive.DebuggerPage.Core

  @spec render(map()) :: Phoenix.LiveView.Rendered.t()
  defdelegate render(assigns), to: Core
end
