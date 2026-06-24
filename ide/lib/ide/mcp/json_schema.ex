defmodule Ide.Mcp.JsonSchema do
  @moduledoc false

  @type property_field :: %{
          optional(atom()) => String.t() | boolean() | number() | integer() | [String.t()],
          optional(String.t()) => term()
        }

  @type properties :: %{optional(String.t()) => property_field()}
  @type schema_object :: %{
          required(:type) => String.t(),
          required(:additionalProperties) => boolean(),
          required(:properties) => properties(),
          optional(:required) => [atom() | String.t()]
        }

  @spec object(properties(), keyword()) :: schema_object()
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
