defmodule IdeWeb.WorkspaceLive.DebuggerSupport.Rendered.Summary do
  @moduledoc false

  alias IdeWeb.WorkspaceLive.DebuggerSupport.Rendered.Core

  defdelegate rendered_view_preview(runtime), to: Core
  defdelegate rendered_node_summary(node, model, arg_name \\ nil), to: Core
end
