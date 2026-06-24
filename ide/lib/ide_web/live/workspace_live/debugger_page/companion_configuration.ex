defmodule IdeWeb.WorkspaceLive.DebuggerPage.CompanionConfiguration do
  @moduledoc false

  alias IdeWeb.WorkspaceLive.DebuggerPreview
  alias IdeWeb.WorkspaceLive.DebuggerSupport.Types, as: SupportTypes

  @type runtime_input :: SupportTypes.runtime_input()
  @type configuration :: SupportTypes.wire_map()
  @type config_field :: SupportTypes.wire_map()
  @type draft_values :: %{optional(String.t()) => SupportTypes.wire_value()}

  @spec model(runtime_input()) :: configuration() | nil
  def model(runtime) when is_map(runtime) do
    model = DebuggerPreview.runtime_model(runtime)

    case Map.get(model, "configuration") || Map.get(model, :configuration) do
      %{} = configuration -> configuration
      _ -> nil
    end
  end

  def model(_runtime), do: nil

  @spec put_values(configuration(), draft_values()) :: configuration()
  def put_values(configuration, values) when is_map(configuration) and is_map(values) do
    values = Map.new(values, fn {key, value} -> {to_string(key), value} end)

    configuration
    |> Map.put("values", values)
    |> Map.update("sections", [], fn
      sections when is_list(sections) ->
        Enum.map(sections, &put_section_values(&1, values))

      other ->
        other
    end)
  end

  @type config_section :: SupportTypes.wire_map()

  @spec put_section_values(config_section(), draft_values()) :: config_section()
  defp put_section_values(%{"fields" => fields} = section, values) when is_list(fields) do
    Map.put(section, "fields", Enum.map(fields, &put_field_value(&1, values)))
  end

  defp put_section_values(section, _values), do: section

  @spec put_field_value(config_field(), draft_values()) :: config_field()
  defp put_field_value(%{"id" => id, "control" => %{}} = field, values)
       when is_binary(id) do
    if Map.has_key?(values, id) do
      put_in(field, ["control", "value"], Map.get(values, id))
    else
      field
    end
  end

  defp put_field_value(field, _values), do: field

  @spec input_type(String.t()) :: String.t()
  def input_type("number"), do: "number"
  def input_type("color"), do: "color"
  def input_type("slider"), do: "range"
  def input_type(_), do: "text"

  @spec input_value(config_field()) :: String.t()
  def input_value(nil), do: ""
  def input_value(value) when is_binary(value), do: value
  def input_value(value) when is_boolean(value), do: to_string(value)
  def input_value(value) when is_number(value), do: to_string(value)
  def input_value(value), do: inspect(value)

  @spec truthy?(config_field()) :: boolean()
  def truthy?(values) when is_list(values), do: Enum.any?(values, &truthy?/1)
  def truthy?(value) when value in [true, "true", "True", "on", "1", 1], do: true
  def truthy?(_value), do: false

  @spec input_step(String.t(), config_field()) :: String.t() | number() | nil
  def input_step("number", control) when is_map(control) do
    Map.get(control, "step") || "any"
  end

  def input_step(_control_type, control) when is_map(control) do
    Map.get(control, "step")
  end

  def input_step(_control_type, _control), do: nil
end
