defmodule Ide.Debugger.CompanionConfiguration do
  @moduledoc false

  alias Ide.Debugger.Surface
  alias Ide.Debugger.Types
  alias Ide.PebblePreferences
  alias Ide.Projects

  @spec values_from_state(Types.runtime_state()) :: map()
  def values_from_state(state) when is_map(state) do
    state |> app_model_from_state() |> values_from_model()
  end

  def values_from_state(_state), do: %{}

  @spec configuration_from_state(Types.runtime_state()) :: map()
  def configuration_from_state(state) when is_map(state) do
    state |> app_model_from_state() |> configuration_from_model()
  end

  def configuration_from_state(_state), do: %{}

  @spec attach_to_state(map(), String.t()) :: map()
  def attach_to_state(state, session_key) when is_map(state) and is_binary(session_key) do
    case model_from_session(session_key) do
      nil ->
        update_in(state, [:companion, :model], &drop_from_model/1)

      configuration ->
        configuration =
          put_values_in_configuration(configuration, values_from_state(state))

        state
        |> put_in([:companion, :model, "configuration"], configuration)
        |> put_in([:companion, :model, "runtime_model", "configuration"], configuration)
    end
  end

  def attach_to_state(state, _session_key), do: state

  @spec put_state_values(map(), map()) :: map()
  def put_state_values(state, values) when is_map(state) and is_map(values) do
    update_in(state, [:companion, :model], fn model ->
      model
      |> put_values_at(["configuration"], values)
      |> put_values_at(["runtime_model", "configuration"], values)
    end)
  end

  def put_state_values(state, _values), do: state

  @spec drop_from_model(map()) :: map()
  def drop_from_model(model) when is_map(model) do
    model
    |> Map.drop(["configuration", :configuration])
    |> update_in(["runtime_model"], fn
      %{} = runtime_model -> Map.drop(runtime_model, ["configuration", :configuration])
      other -> other
    end)
  end

  def drop_from_model(model), do: model

  @spec model_from_session(String.t()) :: map() | nil
  def model_from_session(session_key) do
    try do
      with %{} = project <- Projects.get_project_by_scope_key(session_key),
           workspace_root <- Projects.project_workspace_path(project),
           phone_root <- Path.join(workspace_root, "phone"),
           true <- File.exists?(Path.join(phone_root, "elm.json")),
           {:ok, %{} = schema} <- PebblePreferences.extract(phone_root) do
        configuration = %{
          "title" => schema.title,
          "sections" => sections_from_schema(schema.sections)
        }

        put_values_in_configuration(configuration, project_debugger_values(project))
      else
        _ -> nil
      end
    rescue
      DBConnection.OwnershipError ->
        nil

      error in RuntimeError ->
        if String.contains?(Exception.message(error), "could not lookup Ecto repo") do
          nil
        else
          reraise(error, __STACKTRACE__)
        end
    end
  end

  @spec project_debugger_values(map()) :: map() | nil
  defp project_debugger_values(%{debugger_settings: settings}) when is_map(settings) do
    case Map.get(settings, "configuration_values") do
      values when is_map(values) -> values
      _ -> nil
    end
  end

  defp project_debugger_values(_project), do: nil

  @spec sections_from_schema([map()]) :: [map()]
  defp sections_from_schema(sections) when is_list(sections) do
    Enum.map(sections, fn section ->
      %{
        "title" => Map.get(section, :title) || Map.get(section, "title") || "",
        "fields" => fields_from_schema(Map.get(section, :fields) || Map.get(section, "fields") || [])
      }
    end)
  end

  @spec fields_from_schema([map()]) :: [map()]
  defp fields_from_schema(fields) when is_list(fields) do
    Enum.map(fields, fn field ->
      %{
        "id" => Map.get(field, :id) || Map.get(field, "id") || "",
        "label" => Map.get(field, :label) || Map.get(field, "label") || "",
        "control" => stringify_keys(Map.get(field, :control) || Map.get(field, "control") || %{})
      }
    end)
  end

  defp fields_from_schema(_fields), do: []

  @spec stringify_keys(Types.wire_input()) :: Types.wire_input()
  defp stringify_keys(value) when is_map(value) do
    Map.new(value, fn {key, child_value} -> {to_string(key), stringify_keys(child_value)} end)
  end

  defp stringify_keys(value) when is_list(value), do: Enum.map(value, &stringify_keys/1)
  defp stringify_keys(value), do: value

  @spec put_values_at(Types.app_model(), [String.t()], map()) :: Types.app_model()
  defp put_values_at(model, path, values) when is_map(model) and is_list(path) do
    case get_in(model, path) do
      %{} = configuration -> put_in(model, path, put_values_in_configuration(configuration, values))
      _ -> model
    end
  end

  defp put_values_at(model, _path, _values), do: model

  @spec put_values_in_configuration(map(), map()) :: map()
  defp put_values_in_configuration(configuration, values)
       when is_map(configuration) and is_map(values) do
    values = stringify_keys(values)

    configuration
    |> Map.put("values", values)
    |> sync_field_control_values(values)
  end

  defp put_values_in_configuration(configuration, _values) when is_map(configuration),
    do: configuration

  @spec sync_field_control_values(map(), map()) :: map()
  @spec app_model_from_state(Types.runtime_state()) :: Types.app_model()
  defp app_model_from_state(state) when is_map(state) do
    state |> Surface.from_state(:companion) |> Surface.app_model()
  end

  @spec values_from_model(Types.app_model()) :: map()
  defp values_from_model(model) when is_map(model) do
    get_in(model, ["configuration", "values"]) ||
      get_in(model, ["runtime_model", "configuration", "values"]) || %{}
  end

  @spec configuration_from_model(Types.app_model()) :: map()
  defp configuration_from_model(model) when is_map(model) do
    Map.get(model, "configuration") || get_in(model, ["runtime_model", "configuration"]) || %{}
  end

  defp sync_field_control_values(configuration, values)
       when is_map(configuration) and is_map(values) do
    update_in(configuration, ["sections"], fn
      sections when is_list(sections) ->
        Enum.map(sections, fn
          %{} = section ->
            update_in(section, ["fields"], fn
              fields when is_list(fields) ->
                Enum.map(fields, fn
                  %{"id" => id, "control" => %{} = control} = field when is_binary(id) ->
                    if Map.has_key?(values, id) do
                      put_in(field, ["control", "value"], Map.get(values, id))
                    else
                      Map.put(field, "control", Map.delete(control, "value"))
                    end

                  field ->
                    field
                end)

              fields ->
                fields
            end)

          section ->
            section
        end)

      sections ->
        sections
    end)
  end
end
