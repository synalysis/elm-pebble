defmodule Ide.Mcp.JsonSchema do
  @moduledoc false

  @spec object(map(), keyword()) :: map()
  def object(properties, opts \\ []) when is_map(properties) do
    schema = %{
      type: "object",
      additionalProperties: disallow_extra_properties(),
      properties: properties
    }

    case Keyword.get(opts, :required) do
      nil -> schema
      required when is_list(required) -> Map.put(schema, :required, required)
    end
  end

  @spec disallow_extra_properties() :: false
  def disallow_extra_properties, do: false

  @spec allow_extra_properties() :: true
  def allow_extra_properties, do: true
end
