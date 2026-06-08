defmodule Ide.Mcp.ToolCatalog.Auth do
  @moduledoc false

  alias Ide.Mcp.ToolCatalog.Core

  @type capability :: :read | :edit | :build | :publish

  @spec authorized?(String.t(), [capability()]) :: boolean()
  defdelegate authorized?(name, capabilities), to: Core
end
