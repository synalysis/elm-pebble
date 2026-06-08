defmodule IdeWeb.WorkspaceLive.DebuggerSupport.Rendered.Bounds do
  @moduledoc false

  alias IdeWeb.WorkspaceLive.DebuggerSupport.Rendered.Core

  defdelegate rendered_node_bounds(tree, path, screen_w, screen_h, project \\ nil), to: Core
end
