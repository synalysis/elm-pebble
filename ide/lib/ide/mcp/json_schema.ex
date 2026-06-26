defmodule Ide.Mcp.JsonSchema do
  @moduledoc false

  @type json_schema_scalar :: String.t() | boolean() | number() | integer()

  @type property_field :: %{
          optional(:type) => String.t(),
          optional(:enum) => [String.t()],
          optional(:default) => json_schema_scalar() | [String.t()],
          optional(:minimum) => number(),
          optional(:maximum) => number(),
          optional(:description) => String.t(),
          optional(:items) => property_field(),
          optional(:properties) => properties(),
          optional(String.t()) =>
            json_schema_scalar() | [String.t()] | property_field() | properties()
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
