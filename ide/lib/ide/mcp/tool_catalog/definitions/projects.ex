defmodule Ide.Mcp.ToolCatalog.Definitions.Projects do
  @moduledoc false

  alias Ide.Mcp.ToolCatalog.Core

  @spec tools() :: [map()]
  def tools, do: Core.tool_definitions([:read, :edit, :build, :publish])
end
