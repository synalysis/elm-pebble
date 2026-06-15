defmodule Ide.Mcp.ToolCatalog do
  @moduledoc false

  alias Ide.Mcp.ToolCatalog.Auth
  alias Ide.Mcp.ToolCatalog.Core

  @type capability :: :read | :edit | :build | :publish
  @type tool_name :: String.t()

  @spec tool_definitions([capability()]) :: [map()]
  defdelegate tool_definitions(capabilities), to: Core

  @spec catalog_version() :: String.t()
  defdelegate catalog_version(), to: Core

  @spec internal_tool_name(String.t()) :: String.t()
  defdelegate internal_tool_name(name), to: Core

  @spec authorized?(tool_name(), [capability()]) :: boolean()
  defdelegate authorized?(name, capabilities), to: Auth
end
