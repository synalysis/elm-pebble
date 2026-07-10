defmodule Elmc.Backend.CCodegen.RecordFieldMacros do
  @moduledoc false

  alias Elmc.Backend.CCodegen.Expr
  alias Elmc.Backend.CCodegen.Host
  alias Elmc.Backend.CCodegen.IRQueries
  alias Elmc.Backend.CCodegen.Types
  alias Elmc.Backend.CCodegen.Util
  alias ElmEx.IR

  @type macro_map :: %{{String.t(), String.t(), String.t()} => String.t()}

  @spec definitions(IR.t(), keyword()) :: {String.t(), macro_map()}
  def definitions(%IR{} = ir, opts \\ []) do
    shapes = IRQueries.record_alias_shape_map(ir)
    used_fields = Keyword.get(opts, :used_fields)

    entries =
      for {{mod, type}, fields} <- shapes,
          {field, index} <- Enum.with_index(fields),
          used_field?(used_fields, {mod, type, field}) do
        macro = macro_name(mod, type, field)
        {{mod, type, field}, macro, index}
      end

    defines =
      entries
      |> Enum.sort_by(fn {{mod, type, field}, _macro, _index} -> {mod, type, field} end)
      |> Enum.map(fn {_key, macro, index} -> "  #{macro} = #{index}" end)
      |> case do
        [] ->
          ""

        lines ->
          "enum {\n" <> Enum.join(lines, ",\n") <> "\n};"
      end

    macro_map = Map.new(entries, fn {key, macro, _index} -> {key, macro} end)

    {defines, macro_map}
  end

  @spec index_ref(String.t(), keyword()) :: String.t() | nil
  def index_ref(field, opts) when is_binary(field) do
    env = Keyword.get(opts, :env, %{})
    shape = resolve_shape(opts, env)
    type = Keyword.get(opts, :type)

    with fields when is_list(fields) <- shape,
         index when is_integer(index) <- Enum.find_index(fields, &(&1 == field)) do
      type_key = resolve_type_key(type, fields, env)
      format_index(index, field, type_key)
    end
  end

  @spec format_index(non_neg_integer(), String.t(), Types.qualified_type_target() | nil) ::
          String.t()
  def format_index(index, field, {mod, type}) when is_binary(field) do
    case Map.get(Process.get(:elmc_record_field_macros, %{}), {mod, type, field}) do
      macro when is_binary(macro) -> macro
      _ -> "#{index} /* #{Util.escape_c_comment(field)} */"
    end
  end

  def format_index(index, field, _type_key) do
    "#{index} /* #{Util.escape_c_comment(field)} */"
  end

  defp used_field?(nil, {_mod, _type, _field}), do: true
  defp used_field?(%MapSet{} = used, {_mod, _type, field}), do: MapSet.member?(used, field)
  defp used_field?(_, _), do: true

  @spec used_field_keys(Types.function_decl_map(), MapSet.t()) :: MapSet.t()
  def used_field_keys(decl_map, reachable) when is_map(decl_map) do
    decl_map
    |> Enum.filter(fn {key, _} -> MapSet.member?(reachable, key) end)
    |> Enum.reduce(MapSet.new(), fn {_key, decl}, acc ->
      acc
      |> MapSet.union(fields_from_expr(Map.get(decl, :expr)))
    end)
  end

  defp fields_from_expr(nil), do: MapSet.new()

  defp fields_from_expr(expr) when is_list(expr) do
    Enum.reduce(expr, MapSet.new(), fn child, acc ->
      MapSet.union(acc, fields_from_expr(child))
    end)
  end

  defp fields_from_expr(expr) when is_map(expr) do
    direct =
      case expr do
        %{op: :field_access, field: field} when is_binary(field) ->
          MapSet.new([field])

        %{op: :record_update, fields: fields} when is_list(fields) ->
          fields
          |> Enum.map(&Map.get(&1, :field))
          |> Enum.filter(&is_binary/1)
          |> MapSet.new()

        %{op: :record_literal, fields: fields} when is_list(fields) ->
          fields
          |> Enum.map(&Map.get(&1, :name) || Map.get(&1, :field))
          |> Enum.filter(&is_binary/1)
          |> MapSet.new()

        _ ->
          MapSet.new()
      end

    nested =
      expr
      |> Map.values()
      |> Enum.reduce(MapSet.new(), fn value, acc ->
        MapSet.union(acc, fields_from_expr(value))
      end)

    MapSet.union(direct, nested)
  end

  defp fields_from_expr(_), do: MapSet.new()

  defp resolve_shape(opts, env) do
    case Keyword.get(opts, :shape) do
      fields when is_list(fields) ->
        fields

      _ ->
        case Keyword.get(opts, :type) do
          type when is_binary(type) -> Expr.record_shape_for_type(type, env)
          _ -> nil
        end
    end
  end

  @spec resolve_type_key(String.t() | nil, [String.t()], Types.compile_env()) ::
          Types.qualified_type_target() | nil
  def resolve_type_key(type, fields, env) when is_binary(type) do
    type_key_for_name(type, env) || shape_type_key(fields, env)
  end

  def resolve_type_key(nil, fields, env) do
    shape_type_key(fields, env)
  end

  defp shape_type_key(fields, env) when is_list(fields) do
    case Expr.record_type_for_shape(fields, env) do
      type when is_binary(type) -> type_key_for_name(type, env)
      _ -> nil
    end
  end

  defp shape_type_key(_fields, _env), do: nil

  defp type_key_for_name(type, env) do
    normalized = Host.normalize_type_name(type)
    alias_shapes = alias_shapes(env)

    cond do
      String.contains?(normalized, ".") ->
        case Expr.split_qualified_type_name(normalized) do
          {mod, name} -> {mod, name}
          _ -> nil
        end

      Map.has_key?(alias_shapes, {Map.get(env, :__module__, "Main"), normalized}) ->
        {Map.get(env, :__module__, "Main"), normalized}

      true ->
        case Enum.filter(alias_shapes, fn {{_mod, name}, _fields} -> name == normalized end) do
          [{{mod, name}, _fields}] -> {mod, name}
          _ -> {Map.get(env, :__module__, "Main"), normalized}
        end
    end
  end

  defp alias_shapes(env) do
    Map.get(env, :__record_alias_shapes__) || Process.get(:elmc_record_alias_shapes, %{})
  end

  defp macro_name(mod, type, field) do
    suffix =
      [mod, type, field]
      |> Enum.map(&Util.safe_c_suffix/1)
      |> Enum.map(&String.upcase/1)
      |> Enum.join("_")

    "ELMC_FIELD_#{suffix}"
  end
end
