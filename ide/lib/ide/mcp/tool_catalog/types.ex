defmodule Ide.Mcp.ToolCatalog.Types do
  @moduledoc false

  alias Ide.Mcp.JsonSchema

  @type input_schema :: JsonSchema.schema_object()

  @type tool_definition :: %{
          required(:name) => String.t(),
          optional(:description) => String.t(),
          optional(:inputSchema) => input_schema()
        }
end
