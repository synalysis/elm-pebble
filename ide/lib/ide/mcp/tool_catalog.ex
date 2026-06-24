defmodule Ide.Mcp.ToolCatalog do
  @moduledoc false

  alias Ide.Mcp.ToolCatalog.Auth
  alias Ide.Mcp.ToolCatalog.Core
  alias Ide.Mcp.ToolCatalog.Types, as: CatalogTypes

  @type capability :: :read | :edit | :build | :publish
  @type tool_name :: String.t()
  @type tool_definition :: CatalogTypes.tool_definition()

  @spec tool_definitions([capability()]) :: [tool_definition()]
  defdelegate tool_definitions(capabilities), to: Core

  @spec catalog_version() :: String.t()
  defdelegate catalog_version(), to: Core

  @spec internal_tool_name(String.t()) :: String.t()
  defdelegate internal_tool_name(name), to: Core

  @spec authorized?(tool_name(), [capability()]) :: boolean()
  defdelegate authorized?(name, capabilities), to: Auth
end
