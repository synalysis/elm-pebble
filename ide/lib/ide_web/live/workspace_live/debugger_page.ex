defmodule IdeWeb.WorkspaceLive.DebuggerPage do
  @moduledoc false

  alias IdeWeb.WorkspaceLive.DebuggerPage.{Assigns, Core, SessionState}
  alias Phoenix.LiveView.Rendered

  @type assigns :: Assigns.t()
  @type rendered :: Rendered.t()

  @spec render(assigns()) :: rendered()
  defdelegate render(assigns), to: Core

  @spec debugger_visible_timeline_mode(String.t(), boolean()) :: String.t()
  defdelegate debugger_visible_timeline_mode(mode, companion_app_present?),
    to: SessionState,
    as: :visible_timeline_mode
end
