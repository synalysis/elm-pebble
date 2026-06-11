defmodule IdeWeb.WorkspaceLive.DebuggerPage do
  @moduledoc false

  alias IdeWeb.WorkspaceLive.DebuggerPage.Core
  alias Phoenix.LiveView.Rendered

  @type assigns :: map()
  @type rendered :: Rendered.t()

  @spec render(assigns()) :: rendered()
  defdelegate render(assigns), to: Core

  defdelegate debugger_visible_timeline_mode(mode, companion_app_present?), to: Core
end
