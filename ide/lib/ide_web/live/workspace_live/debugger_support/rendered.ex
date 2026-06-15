defmodule IdeWeb.WorkspaceLive.DebuggerSupport.Rendered do
  @moduledoc false

  alias IdeWeb.WorkspaceLive.DebuggerSupport.Rendered.Bounds
  alias IdeWeb.WorkspaceLive.DebuggerSupport.Rendered.Summary
  alias IdeWeb.WorkspaceLive.DebuggerSupport.Rendered.Tree

  defdelegate runtime_json(runtime), to: Tree
  defdelegate rendered_tree(runtime), to: Tree
  defdelegate rendered_node_bounds(tree, path, screen_w, screen_h, project \\ nil), to: Bounds
  defdelegate rendered_view_preview(runtime), to: Summary
  defdelegate rendered_node_summary(node, model, arg_name \\ nil), to: Summary
end
