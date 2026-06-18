defmodule Ide.EditorCompletionRecordResolver do
  @moduledoc false

  @spec resolve_fields(map(), String.t(), non_neg_integer(), String.t(), map()) :: [String.t()]
  def resolve_fields(index, qualifier, offset, source, context)
      when is_map(index) and is_binary(qualifier) and is_integer(offset) and is_binary(source) and
             is_map(context) do
    line = line_at_offset(source, offset)
    scope = find_scope(Map.get(index, :function_scopes, []), line)

    with %{} = scope <- scope,
         type_name when is_binary(type_name) <-
           resolve_path_type(String.split(qualifier, "."), scope, index, context),
         fields when fields != [] <- fields_for_type(type_name, index, context) do
      fields
    else
      _ -> []
    end
  end

  def resolve_fields(_index, _qualifier, _offset, _source, _context), do: []

  defp resolve_path_type([], _scope, _index, _context), do: nil

  defp resolve_path_type([root | rest], scope, index, context) do
    bindings = Map.get(scope, :bindings, %{})
    root_type = Map.get(bindings, root) || infer_param_type(root, index)

    if is_binary(root_type) do
      Enum.reduce(rest, normalize_type_name(root_type, index), fn field, type_name ->
        field_types = field_types_for_type(type_name, index, context)
        Map.get(field_types, field) || type_name
      end)
    else
      nil
    end
  end

  defp infer_param_type(param_name, index) when is_binary(param_name) do
    types = Map.get(index, :record_fields_by_type, %{})

    candidate =
      param_name
      |> String.trim()
      |> case do
        <<first::utf8, rest::binary>> when first in ?a..?z ->
          <<first - 32, rest::binary>>

        other ->
          other
      end

    if Map.has_key?(types, candidate), do: candidate
  end

  defp fields_for_type(type_name, index, context) do
    by_type = merged_record_fields_by_type(index, context)

    Map.get(by_type, type_name) ||
      Map.get(by_type, short_type_name(type_name)) ||
      Map.get(by_type, fully_qualified_type_name(type_name, index))
  end

  defp field_types_for_type(type_name, index, context) do
    by_type = merged_field_types_by_type(index, context)

    Map.get(by_type, type_name) ||
      Map.get(by_type, short_type_name(type_name)) ||
      Map.get(by_type, fully_qualified_type_name(type_name, index)) ||
      %{}
  end

  defp merged_record_fields_by_type(index, context) do
    Map.merge(
      package_record_fields_by_type(context),
      Map.get(index, :record_fields_by_type, %{})
    )
  end

  defp merged_field_types_by_type(index, context) do
    Map.merge(
      package_field_types_by_type(context),
      Map.get(index, :field_types_by_type, %{})
    )
  end

  defp package_record_fields_by_type(context) do
    context
    |> package_type_maps()
    |> Map.new(fn {type_name, %{fields: fields}} -> {type_name, fields} end)
  end

  defp package_field_types_by_type(context) do
    context
    |> package_type_maps()
    |> Map.new(fn {type_name, %{field_types: field_types}} -> {type_name, field_types} end)
  end

  defp package_type_maps(context) do
    context
    |> Map.get(:package_type_maps)
    |> case do
      maps when is_map(maps) -> maps
      _ -> %{}
    end
  end

  defp normalize_type_name(type_name, index) do
    type_name
    |> String.trim()
    |> expand_module_aliases(Map.get(index, :import_aliases, %{}))
  end

  defp expand_module_aliases(type_name, aliases) when is_binary(type_name) and is_map(aliases) do
    case String.split(type_name, ".") do
      [single] ->
        single

      parts ->
        case Enum.split(parts, -1) do
          {module_parts, [type]} ->
            module = Enum.join(module_parts, ".")
            resolved_module = Map.get(aliases, module, module)
            "#{resolved_module}.#{type}"

          _ ->
            type_name
        end
    end
  end

  defp fully_qualified_type_name(type_name, index) do
    normalize_type_name(type_name, index)
  end

  defp short_type_name(type_name) when is_binary(type_name) do
    type_name
    |> String.split(".")
    |> List.last()
  end

  defp find_scope(scopes, line) when is_list(scopes) and is_integer(line) do
    scopes
    |> Enum.filter(fn scope ->
      start_line = scope[:start_line] || scope["start_line"] || 0
      end_line = scope[:end_line] || scope["end_line"] || 0
      line >= start_line and line <= end_line
    end)
    |> List.last()
  end

  defp find_scope(_, _), do: nil

  defp line_at_offset(source, offset) do
    safe_offset = min(max(offset, 0), String.length(source))

    source
    |> String.slice(0, safe_offset)
    |> String.split("\n", trim: false)
    |> length()
  end
end
