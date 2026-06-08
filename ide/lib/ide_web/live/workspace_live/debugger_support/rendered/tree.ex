defmodule IdeWeb.WorkspaceLive.DebuggerSupport.Rendered.Tree do
  @moduledoc false

  alias IdeWeb.WorkspaceLive.DebuggerSupport.Rendered.Core

  defdelegate rendered_tree(runtime), to: Core
  defdelegate runtime_json(runtime), to: Core
end
