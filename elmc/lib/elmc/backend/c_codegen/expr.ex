defmodule Elmc.Backend.CCodegen.Expr do
  @moduledoc false

  alias Elmc.Backend.CCodegen.Host
  alias Elmc.Backend.CCodegen.Types
  alias Elmc.Backend.CCodegen.Util

  @spec record_field_expr(Types.ir_expr(), String.t()) :: Types.ir_expr() | nil
  @spec record_field_expr(nil, String.t()) :: nil
  def record_field_expr(%{op: :record_literal, fields: fields}, field) do
    fields
    |> Enum.find(&(&1.name == field))
    |> case do
      nil -> nil
      %{expr: expr} -> expr
    end
  end

  def record_field_expr(%{op: :record_update, base: base, fields: fields}, field) do
    fields
    |> Enum.find(&(&1.name == field))
    |> case do
      nil -> record_field_expr(base, field) || %{op: :field_access, arg: base, field: field}
      %{expr: expr} -> expr
    end
  end

  def record_field_expr(%{op: :qualified_call, target: target, args: args}, field)
      when is_binary(target) do
    case Host.special_value_from_target(Host.normalize_special_target(target), args || []) do
      nil -> nil
      rewritten -> record_field_expr(rewritten, field)
    end
  end

  def record_field_expr(%{op: :call, name: name, args: args}, field) when is_binary(name) do
    case Host.special_value_from_target(name, args || []) do
      nil -> nil
      rewritten -> record_field_expr(rewritten, field)
    end
  end

  def record_field_expr(%{op: :var}, _field), do: nil
  def record_field_expr(%{op: :field_access}, _field), do: nil
  def record_field_expr(_expr, _field), do: nil

  @spec substitute_expr(term(), Types.let_substitutions()) :: term()
  def substitute_expr(%{op: :var, name: name}, substitutions) do
    Map.get(substitutions, name, %{op: :var, name: name})
  end

  def substitute_expr(%{op: :add_const, var: name, value: value}, substitutions) do
    case Map.fetch(substitutions, name) do
      {:ok, expr} ->
        %{
          op: :call,
          name: "__add__",
          args: [
            substitute_expr(expr, Map.delete(substitutions, name)),
            %{op: :int_literal, value: value}
          ]
        }

      :error ->
        %{op: :add_const, var: name, value: value}
    end
  end

  def substitute_expr(%{op: :sub_const, var: name, value: value}, substitutions) do
    case Map.fetch(substitutions, name) do
      {:ok, expr} ->
        %{
          op: :call,
          name: "__sub__",
          args: [
            substitute_expr(expr, Map.delete(substitutions, name)),
            %{op: :int_literal, value: value}
          ]
        }

      :error ->
        %{op: :sub_const, var: name, value: value}
    end
  end

  def substitute_expr(%{op: :add_vars, left: left, right: right}, substitutions) do
    left_expr = Map.get(substitutions, left, %{op: :var, name: left})
    right_expr = Map.get(substitutions, right, %{op: :var, name: right})

    %{
      op: :call,
      name: "__add__",
      args: [
        substitute_expr(left_expr, Map.delete(substitutions, left)),
        substitute_expr(right_expr, Map.delete(substitutions, right))
      ]
    }
  end

  def substitute_expr(
         %{op: :let_in, name: name, value_expr: value_expr, in_expr: in_expr} = expr,
         substitutions
       ) do
    %{
      expr
      | value_expr: substitute_expr(value_expr, substitutions),
        in_expr: substitute_expr(in_expr, Map.delete(substitutions, name))
    }
  end

  def substitute_expr(%{op: :lambda, args: args, body: body} = expr, substitutions)
       when is_list(args) do
    scoped = Enum.reduce(args, substitutions, &Map.delete(&2, &1))
    %{expr | body: substitute_expr(body, scoped)}
  end

  def substitute_expr(%{op: :field_access, arg: arg, field: field} = expr, substitutions)
       when is_binary(arg) do
    %{expr | arg: Map.get(substitutions, arg, arg), field: field}
  end

  def substitute_expr(%{op: :field_call, arg: arg, args: args} = expr, substitutions)
       when is_binary(arg) and is_list(args) do
    %{expr | arg: Map.get(substitutions, arg, arg), args: substitute_expr(args, substitutions)}
  end

  def substitute_expr(expr, substitutions) when is_map(expr) do
    expr
    |> Enum.map(fn {key, value} -> {key, substitute_expr(value, substitutions)} end)
    |> Map.new()
  end

  def substitute_expr(values, substitutions) when is_list(values) do
    Enum.map(values, &substitute_expr(&1, substitutions))
  end

  def substitute_expr(value, _substitutions), do: value

  @spec inline_record_field_expr(Types.ir_expr(), String.t(), Types.compile_env()) ::
          Types.ir_expr() | nil
  def inline_record_field_expr(arg_expr, field, env) do
    arg_expr = Host.unwrap_affine_bindings(arg_expr)

    case arg_expr do
      %{op: :if, cond: cond, then_expr: then_expr, else_expr: else_expr} ->
        case {branch_field_expr(then_expr, field, env), branch_field_expr(else_expr, field, env)} do
          {then_field, else_field} when not is_nil(then_field) and not is_nil(else_field) ->
            %{op: :direct_native_if, cond: cond, then_expr: then_field, else_expr: else_field}

          _ ->
            inline_record_field_from_helper(arg_expr, field, env)
        end

      _ ->
        branch_field_expr(arg_expr, field, env) ||
          inline_record_field_from_helper(arg_expr, field, env)
    end
  end

  @spec unwrap_let_chain(Types.ir_expr(), Types.let_substitutions()) ::
          {Types.ir_expr(), Types.let_substitutions()}
  def unwrap_let_chain(%{op: :let_in, name: name, value_expr: value_expr, in_expr: in_expr}, bindings) do
    unwrap_let_chain(in_expr, Map.put(bindings, name, value_expr))
  end

  def unwrap_let_chain(expr, bindings), do: {expr, bindings}

  defp branch_field_expr(branch_expr, field, _env) do
    {branch_expr, let_bindings} = unwrap_let_chain(branch_expr, %{})

    branch_expr =
      if map_size(let_bindings) > 0 do
        substitute_expr(branch_expr, let_bindings)
      else
        branch_expr
      end

    case record_field_expr(branch_expr, field) do
      nil -> nil
      field_expr -> resolve_branch_let_bindings(field_expr, let_bindings)
    end
  end

  defp resolve_branch_let_bindings(expr, let_bindings) when map_size(let_bindings) == 0,
    do: expr

  defp resolve_branch_let_bindings(%{op: :var, name: name}, let_bindings)
       when is_binary(name) or is_atom(name) do
    key = Host.binding_key(name)

    case Map.fetch(let_bindings, key) do
      {:ok, bound} -> resolve_branch_let_bindings(bound, let_bindings)
      :error -> %{op: :var, name: name}
    end
  end

  defp resolve_branch_let_bindings(%{op: :call, name: name, args: args}, let_bindings)
       when is_binary(name) and args in [[], nil] do
    case Map.fetch(let_bindings, name) do
      {:ok, bound} -> resolve_branch_let_bindings(bound, let_bindings)
      :error -> %{op: :call, name: name, args: []}
    end
  end

  defp resolve_branch_let_bindings(expr, let_bindings) when is_map(expr) do
    expr
    |> Map.new(fn
      {key, value} when is_list(value) ->
        {key, Enum.map(value, &resolve_branch_let_bindings(&1, let_bindings))}

      {key, value} when is_map(value) ->
        {key, resolve_branch_let_bindings(value, let_bindings)}

      {key, value} ->
        {key, value}
    end)
  end

  defp resolve_branch_let_bindings(expr, let_bindings) when is_list(expr),
    do: Enum.map(expr, &resolve_branch_let_bindings(&1, let_bindings))

  defp resolve_branch_let_bindings(expr, _let_bindings), do: expr

  defp inline_record_field_from_helper(arg_expr, field, env) do
    with target_key when not is_nil(target_key) <- record_helper_target(arg_expr, env),
         decl_map <- Map.get(env, :__program_decls__, %{}),
         %{args: arg_names, expr: expr} when is_list(arg_names) <- Map.get(decl_map, target_key),
         args <- Map.get(arg_expr, :args, []),
         true <- length(arg_names) == length(args),
         substituted <- substitute_expr(expr, Map.new(Enum.zip(arg_names, args))),
         field_expr when not is_nil(field_expr) <- inline_record_field_expr(substituted, field, env) do
      field_expr
    else
      _ -> nil
    end
  end

  @spec record_helper_target(Types.ir_expr(), Types.compile_env()) :: Types.function_decl_key() | nil
  def record_helper_target(%{op: :call, name: name}, env) when is_binary(name) do
    {Map.get(env, :__module__, "Main"), name}
  end

  def record_helper_target(%{op: :qualified_call, target: target}, _env)
       when is_binary(target) do
    target
    |> Host.normalize_special_target()
    |> Host.split_qualified_function_target()
  end

  def record_helper_target(_expr, _env), do: nil

  @spec record_shape(Types.ir_expr(), Types.compile_env()) :: Types.record_shape()
  def record_shape(%{op: :record_literal, fields: fields}, _env) when is_list(fields) do
    Enum.map(fields, & &1.name)
  end

  def record_shape(%{op: :record_update, base: base}, env), do: record_shape(base, env)

  def record_shape(%{op: :var, name: name}, env) do
    record_shape_for_var(env, name) ||
      record_shape_for_function_return({Map.get(env, :__module__, "Main"), name}, env, 0)
  end

  def record_shape(%{op: :call, name: name, args: args}, env) when is_binary(name) do
    record_shape_for_function_return(
      {Map.get(env, :__module__, "Main"), name},
      env,
      length(args || [])
    )
  end

  def record_shape(%{op: :qualified_call, target: target, args: args}, env)
      when is_binary(target) do
    normalized = Host.normalize_special_target(target)

    case Host.special_value_from_target(normalized, args || []) do
      nil ->
        normalized
        |> Host.split_qualified_function_target()
        |> record_shape_for_function_return(env, length(args || []))

      rewritten ->
        record_shape(rewritten, env)
    end
  end

  def record_shape(
        %{op: :runtime_call, function: "elmc_maybe_with_default", args: [default, _maybe]},
        env
      ) do
    record_shape(default, env)
  end

  def record_shape(_expr, _env), do: nil

  @spec record_get_expr(String.t(), String.t(), Types.record_shape()) :: String.t()
  def record_get_expr(source, field, fields) when is_list(fields) do
    case Enum.find_index(fields, &(&1 == field)) do
      nil ->
        "elmc_record_get(#{source}, \"#{Util.escape_c_string(field)}\")"

      index ->
        "elmc_record_get_index(#{source}, #{index} /* #{Util.escape_c_comment(field)} */)"
    end
  end

  def record_get_expr(source, field, _fields) do
    "elmc_record_get(#{source}, \"#{Util.escape_c_string(field)}\")"
  end

  @spec record_get_int_expr(String.t(), String.t(), Types.record_shape()) :: String.t()
  def record_get_int_expr(source, field, fields) when is_list(fields) do
    case Enum.find_index(fields, &(&1 == field)) do
      nil ->
        "elmc_record_get_int(#{source}, \"#{Util.escape_c_string(field)}\")"

      index ->
        "ELMC_RECORD_GET_INDEX_INT(#{source}, #{index} /* #{Util.escape_c_comment(field)} */)"
    end
  end

  def record_get_int_expr(source, field, _fields) do
    "elmc_record_get_int(#{source}, \"#{Util.escape_c_string(field)}\")"
  end

  @spec record_shape_for_var(Types.compile_env(), String.t()) :: Types.record_shape()
  def record_shape_for_var(env, name) when is_binary(name) do
    env
    |> Map.get(:__record_shapes__, %{})
    |> Map.get(name)
  end

  @spec record_shape_for_function_return(
          Types.qualified_function_target(),
          Types.compile_env(),
          non_neg_integer()
        ) :: Types.record_shape()
  def record_shape_for_function_return(nil, _env, _arg_count), do: nil

  def record_shape_for_function_return(target_key, env, arg_count) do
    case Map.get(Map.get(env, :__program_decls__, %{}), target_key) do
      %{type: type} ->
        if length(Host.function_arg_types(type)) == arg_count do
          record_shape_for_type(Host.function_return_type(type), env)
        end

      _ ->
        nil
    end
  end

  @spec record_shape_for_type(String.t(), Types.compile_env()) :: Types.record_shape()
  def record_shape_for_type(type, env) when is_binary(type) do
    type_name = Host.normalize_type_name(type)
    current_module = Map.get(env, :__module__, "Main")

    alias_shapes =
      Map.get(env, :__record_alias_shapes__) || Process.get(:elmc_record_alias_shapes, %{})

    cond do
      Map.has_key?(alias_shapes, {current_module, type_name}) ->
        Map.get(alias_shapes, {current_module, type_name})

      String.contains?(type_name, ".") ->
        case split_qualified_type_name(type_name) do
          nil -> nil
          target_key -> Map.get(alias_shapes, target_key)
        end

      true ->
        nil
    end
  end

  def record_shape_for_type(_type, _env), do: nil

  @spec record_type_for_expr(Types.ir_expr(), Types.compile_env()) :: String.t() | nil
  def record_type_for_expr(%{op: :record_literal, fields: fields}, env) when is_list(fields) do
    fields
    |> Enum.map(& &1.name)
    |> record_type_for_field_names(env)
  end

  def record_type_for_expr(%{op: :record_update, base: base}, env),
    do: record_type_for_expr(base, env)

  def record_type_for_expr(%{op: :var, name: name}, env) do
    Map.get(Map.get(env, :__var_types__, %{}), name) ||
      record_type_for_function_return({Map.get(env, :__module__, "Main"), name}, env, 0)
  end

  def record_type_for_expr(%{op: :call, name: name, args: args}, env) when is_binary(name) do
    record_type_for_function_return(
      {Map.get(env, :__module__, "Main"), name},
      env,
      length(args || [])
    )
  end

  def record_type_for_expr(%{op: :qualified_call, target: target, args: args}, env)
      when is_binary(target) do
    normalized = Host.normalize_special_target(target)

    case Host.special_value_from_target(normalized, args || []) do
      nil ->
        normalized
        |> Host.split_qualified_function_target()
        |> record_type_for_function_return(env, length(args || []))

      rewritten ->
        record_type_for_expr(rewritten, env)
    end
  end

  def record_type_for_expr(_expr, _env), do: nil

  @spec record_type_for_function_return(
          Types.qualified_function_target(),
          Types.compile_env(),
          non_neg_integer()
        ) :: String.t() | nil
  def record_type_for_function_return(nil, _env, _arg_count), do: nil

  def record_type_for_function_return(target_key, env, arg_count) do
    case Map.get(Map.get(env, :__program_decls__, %{}), target_key) do
      %{type: type} ->
        if length(Host.function_arg_types(type)) == arg_count do
          return_type = Host.function_return_type(type) |> Host.normalize_type_name()

          if record_shape_for_type(return_type, env) do
            return_type
          end
        end

      _ ->
        nil
    end
  end

  @spec record_type_for_field_names([String.t()], Types.compile_env()) :: String.t() | nil
  def record_type_for_field_names(field_names, env) when is_list(field_names) do
    normalized_fields = field_names |> Enum.map(&to_string/1) |> Enum.sort()

    alias_shapes =
      Map.get(env, :__record_alias_shapes__) || Process.get(:elmc_record_alias_shapes, %{})

    current_module = Map.get(env, :__module__, "Main")

    matches =
      alias_shapes
      |> Enum.filter(fn
        {{mod, _name}, shape} ->
          mod == current_module and Enum.sort(Enum.map(shape, &to_string/1)) == normalized_fields

        _ ->
          false
      end)
      |> Enum.map(fn {{_mod, name}, _shape} -> name end)

    case matches do
      [single] -> single
      _ -> nil
    end
  end

  @spec split_qualified_type_name(String.t()) :: Types.qualified_type_target()
  def split_qualified_type_name(type_name) when is_binary(type_name) do
    case String.split(type_name, ".") do
      [_single] ->
        nil

      parts ->
        {parts |> Enum.drop(-1) |> Enum.join("."), List.last(parts)}
    end
  end
end
