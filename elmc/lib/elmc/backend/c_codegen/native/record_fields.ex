defmodule Elmc.Backend.CCodegen.Native.RecordFields do
  @moduledoc false

  alias Elmc.Backend.CCodegen.Expr
  alias Elmc.Backend.CCodegen.Host
  alias Elmc.Backend.CCodegen.Types
  alias Elmc.Backend.CCodegen.Util

  @spec lookup_field_type(String.t(), String.t(), Types.compile_env()) :: String.t() | nil
  def lookup_field_type(type_name, field, env)
       when is_binary(type_name) and is_binary(field) do
    types_map = Process.get(:elmc_record_field_types, %{})
    current_module = Map.get(env, :__module__, "Main")
    normalized = Host.normalize_type_name(type_name)

    cond do
      Map.has_key?(types_map, {current_module, normalized}) ->
        Map.get(types_map[{current_module, normalized}], field)

      String.contains?(normalized, ".") ->
        case Expr.split_qualified_type_name(normalized) do
          {mod, name} -> Map.get(types_map[{mod, name}] || %{}, field)
          _ -> nil
        end

      true ->
        nil
    end
  end

  @spec record_type_name(Types.compile_env(), String.t()) :: String.t() | nil
  def record_type_name(env, name) when is_binary(name) do
    case Map.get(env, :__var_types__, %{}) |> Map.get(name) do
      type when is_binary(type) ->
        type

      _ ->
        case Map.get(env, :__record_shapes__, %{}) |> Map.get(name) do
          fields when is_list(fields) -> Expr.record_type_for_field_names(fields, env)
          _ -> nil
        end
    end
  end

  @spec field_kind_from_env(Types.compile_env(), String.t(), String.t()) :: String.t() | nil
  def field_kind_from_env(env, record_name, field)
      when is_binary(record_name) and is_binary(field) do
    env
    |> Map.get(:__record_field_kinds__, %{})
    |> Map.get(record_name)
    |> case do
      kinds when is_map(kinds) -> Map.get(kinds, field)
      _ -> nil
    end
  end

  @spec field_type(Types.compile_env(), term(), String.t()) :: String.t() | nil
  def field_type(env, arg, field) when is_binary(arg) and is_binary(field) do
    case field_kind_from_env(env, arg, field) do
      kind when is_binary(kind) ->
        kind

      _ ->
        case record_type_name(env, arg) do
          type when is_binary(type) -> lookup_field_type(type, field, env)
          _ -> nil
        end
    end
  end

  def field_type(env, %{op: :var, name: name}, field) when is_binary(field),
    do: field_type(env, name, field)

  def field_type(_env, _arg, _field), do: nil

  @spec int_field?(Types.compile_env(), term(), String.t()) :: boolean()
  def int_field?(env, %{op: :var, name: name}, field) do
    case Map.get(env, name) do
      {:native_record, fields} -> Map.has_key?(fields, field)
      _ -> int_field?(env, name, field)
    end
  end

  def int_field?(env, arg, field) when is_binary(arg) do
    case Map.get(env, arg) do
      {:native_record, fields} ->
        Map.has_key?(fields, field)

      _ ->
        case field_type(env, arg, field) do
          "Int" -> true
          _ -> int_only_field?(env, arg, field)
        end
    end
  end

  def int_field?(env, arg, field) do
    case field_type(env, arg, field) do
      "Int" -> true
      _ -> int_only_field?(env, arg, field)
    end
  end

  @spec float_field?(Types.compile_env(), term(), String.t()) :: boolean()
  def float_field?(env, arg, field) do
    case field_type(env, arg, field) do
      "Float" -> true
      _ -> float_only_field?(env, arg, field)
    end
  end

  @spec bool_field?(Types.compile_env(), term(), String.t()) :: boolean()
  def bool_field?(env, arg, field) do
    case field_type(env, arg, field) do
      "Bool" -> true
      _ -> bool_only_field?(env, arg, field)
    end
  end

  @spec get_float_expr(String.t(), String.t(), Types.record_shape()) :: String.t()
  def get_float_expr(source, field, fields) when is_list(fields) do
    case Enum.find_index(fields, &(&1 == field)) do
      nil ->
        "elmc_as_float(elmc_record_get(#{source}, \"#{Util.escape_c_string(field)}\"))"

      index ->
        "ELMC_RECORD_GET_INDEX_FLOAT(#{source}, #{index} /* #{Util.escape_c_comment(field)} */)"
    end
  end

  def get_float_expr(source, field, _fields) do
    "elmc_as_float(elmc_record_get(#{source}, \"#{Util.escape_c_string(field)}\"))"
  end

  @spec get_native_bool_expr(String.t(), String.t(), Types.record_shape()) :: String.t()
  def get_native_bool_expr(source, field, fields) when is_list(fields) do
    case Enum.find_index(fields, &(&1 == field)) do
      nil ->
        "elmc_record_get_bool(#{source}, \"#{Util.escape_c_string(field)}\")"

      index ->
        "ELMC_RECORD_GET_INDEX_BOOL(#{source}, #{index} /* #{Util.escape_c_comment(field)} */)"
    end
  end

  def get_native_bool_expr(source, field, _fields) do
    "elmc_record_get_bool(#{source}, \"#{Util.escape_c_string(field)}\")"
  end

  @spec get_maybe_int_expr(String.t(), String.t(), Types.record_shape(), String.t()) :: String.t()
  def get_maybe_int_expr(source, field, fields, default_ref) when is_list(fields) do
    case Enum.find_index(fields, &(&1 == field)) do
      nil ->
        "elmc_record_get_maybe_int(#{source}, \"#{Util.escape_c_string(field)}\", #{default_ref})"

      index ->
        "elmc_record_get_index_maybe_int(#{source}, #{index} /* #{Util.escape_c_comment(field)} */, #{default_ref})"
    end
  end

  def get_maybe_int_expr(source, field, _fields, default_ref) do
    "elmc_record_get_maybe_int(#{source}, \"#{Util.escape_c_string(field)}\", #{default_ref})"
  end

  @spec get_bool_expr(String.t(), String.t(), Types.record_shape()) :: String.t()
  def get_bool_expr(source, field, fields) when is_list(fields) do
    case Enum.find_index(fields, &(&1 == field)) do
      nil ->
        "elmc_record_get_bool(#{source}, \"#{Util.escape_c_string(field)}\")"

      index ->
        "elmc_record_get_index_bool(#{source}, #{index} /* #{Util.escape_c_comment(field)} */)"
    end
  end

  def get_bool_expr(source, field, _fields) do
    "elmc_record_get_bool(#{source}, \"#{Util.escape_c_string(field)}\")"
  end

  defp int_only_field?(env, arg, field) when is_binary(arg) and is_binary(field) do
    with type when is_binary(type) <- Map.get(Map.get(env, :__var_types__, %{}), arg),
         fields when is_list(fields) <- Host.record_shape_for_type(type, env),
         true <- field in fields,
         true <- int_only_type_fields?(type, fields, env) do
      true
    else
      _ -> false
    end
  end

  defp int_only_field?(env, %{op: :var, name: name}, field), do: int_only_field?(env, name, field)

  defp int_only_field?(env, arg_expr, field) when is_map(arg_expr) do
    case Host.record_shape(arg_expr, env) do
      fields when is_list(fields) ->
        field in fields and int_only_shape_fields?(fields, env, arg_expr)

      _ ->
        false
    end
  end

  defp int_only_field?(_env, _arg, _field), do: false

  defp int_only_type_fields?(type, fields, env) do
    Enum.all?(fields, fn name -> lookup_field_type(type, name, env) == "Int" end)
  end

  defp int_only_shape_fields?(fields, env, arg_expr) do
    type =
      case arg_expr do
        %{op: :var, name: name} -> Map.get(Map.get(env, :__var_types__, %{}), name)
        _ -> nil
      end

    if is_binary(type) do
      int_only_type_fields?(type, fields, env)
    else
      Enum.all?(fields, fn name ->
        Host.native_int_expr?(Host.record_field_expr(arg_expr, name), env)
      end)
    end
  end

  defp float_only_field?(env, arg, field) when is_binary(arg) and is_binary(field) do
    with type when is_binary(type) <- Map.get(Map.get(env, :__var_types__, %{}), arg),
         fields when is_list(fields) <- Host.record_shape_for_type(type, env),
         true <- field in fields,
         true <- float_only_type_fields?(type, fields, env) do
      true
    else
      _ -> false
    end
  end

  defp float_only_field?(env, %{op: :var, name: name}, field), do: float_only_field?(env, name, field)

  defp float_only_field?(env, arg_expr, field) when is_map(arg_expr) do
    case Host.record_shape(arg_expr, env) do
      fields when is_list(fields) ->
        field in fields and float_only_shape_fields?(fields, env, arg_expr)

      _ ->
        false
    end
  end

  defp float_only_field?(_env, _arg, _field), do: false

  defp float_only_type_fields?(type, fields, env) do
    Enum.all?(fields, fn name -> lookup_field_type(type, name, env) == "Float" end)
  end

  defp float_only_shape_fields?(fields, env, arg_expr) do
    type =
      case arg_expr do
        %{op: :var, name: name} -> Map.get(Map.get(env, :__var_types__, %{}), name)
        _ -> nil
      end

    if is_binary(type) do
      float_only_type_fields?(type, fields, env)
    else
      Enum.all?(fields, fn name ->
        Host.native_float_expr?(Host.record_field_expr(arg_expr, name), env)
      end)
    end
  end

  defp bool_only_field?(env, arg, field) when is_binary(arg) and is_binary(field) do
    with type when is_binary(type) <- Map.get(Map.get(env, :__var_types__, %{}), arg),
         fields when is_list(fields) <- Host.record_shape_for_type(type, env),
         true <- field in fields,
         true <- bool_only_type_fields?(type, fields, env) do
      true
    else
      _ -> false
    end
  end

  defp bool_only_field?(_env, _arg, _field), do: false

  defp bool_only_type_fields?(type, fields, env) do
    Enum.all?(fields, fn name -> lookup_field_type(type, name, env) == "Bool" end)
  end
end
