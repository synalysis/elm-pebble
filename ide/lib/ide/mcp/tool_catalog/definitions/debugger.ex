defmodule Ide.Mcp.ToolCatalog.Definitions.Debugger do
  @moduledoc false

  alias Ide.Mcp.ToolCatalog.Core

  @spec tools() :: [Ide.Mcp.ToolCatalog.Types.tool_definition()]
  def tools, do: Core.tool_definitions([:read, :edit, :build, :publish])
end
