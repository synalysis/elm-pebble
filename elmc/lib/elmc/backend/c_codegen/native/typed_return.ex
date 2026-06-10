defmodule Elmc.Backend.CCodegen.Native.TypedReturn do
  @moduledoc false

  alias Elmc.Backend.CCodegen.EnvBindings
  alias Elmc.Backend.CCodegen.Host
  alias Elmc.Backend.CCodegen.Native.RecordFields
  alias Elmc.Backend.CCodegen.Types

  @spec function_return?(
          Types.function_decl_key() | nil,
          Types.compile_env(),
          non_neg_integer(),
          String.t()
        ) :: boolean()
  def function_return?(nil, _env, _arg_count, _return_type), do: false

  def function_return?(target, env, arg_count, return_type) do
    case Map.get(Map.get(env, :__program_decls__, %{}), target) do
      %{type: type} ->
        length(Host.function_arg_types(type)) == arg_count and
          Host.function_return_type(type) == return_type

      _ ->
        false
    end
  end

  @spec string_expr?(Types.ir_expr(), Types.compile_env()) :: boolean()
  def string_expr?(%{op: :call, name: name, args: args}, env) when is_binary(name) do
    module_name = Map.get(env, :__module__, "Main")
    function_return?({module_name, name}, env, length(args || []), "String")
  end

  def string_expr?(%{op: :qualified_call, target: target, args: args}, env)
      when is_binary(target) do
    target
    |> Host.normalize_special_target()
    |> Host.split_qualified_function_target()
    |> function_return?(env, length(args || []), "String")
  end

  def string_expr?(%{op: :var, name: name}, env) when is_binary(name) or is_atom(name) do
    module_name = Map.get(env, :__module__, "Main")
    function_return?({module_name, to_string(name)}, env, 0, "String")
  end

  def string_expr?(_expr, _env), do: false

  @spec bool_expr?(Types.ir_expr(), Types.compile_env()) :: boolean()
  def bool_expr?(%{op: :call, name: name, args: args}, env) when is_binary(name) do
    module_name = Map.get(env, :__module__, "Main")
    function_return?({module_name, name}, env, length(args || []), "Bool")
  end

  def bool_expr?(%{op: :qualified_call, target: target, args: args}, env)
      when is_binary(target) do
    target
    |> Host.normalize_special_target()
    |> Host.split_qualified_function_target()
    |> function_return?(env, length(args || []), "Bool")
  end

  def bool_expr?(%{op: :var, name: name}, env) when is_binary(name) or is_atom(name) do
    module_name = Map.get(env, :__module__, "Main")
    function_return?({module_name, to_string(name)}, env, 0, "Bool")
  end

  def bool_expr?(_expr, _env), do: false

  @spec list_int_expr?(Types.ir_expr(), Types.compile_env()) :: boolean()
  def list_int_expr?(expr, env), do: expr_type(expr, env) == "List Int"

  @spec expr_type(Types.ir_expr(), Types.compile_env()) :: String.t() | nil
  def expr_type(%{op: :var, name: name}, env) when is_binary(name) or is_atom(name) do
    type_from_env(env, name) ||
      function_return_type({Map.get(env, :__module__, "Main"), to_string(name)}, env, 0)
  end

  def expr_type(%{op: :call, name: name, args: args}, env) when is_binary(name) do
    function_return_type({Map.get(env, :__module__, "Main"), name}, env, length(args || []))
  end

  def expr_type(%{op: :qualified_call, target: target, args: args}, env)
      when is_binary(target) do
    target
    |> Host.normalize_special_target()
    |> Host.split_qualified_function_target()
    |> function_return_type(env, length(args || []))
  end

  def expr_type(%{op: :field_access, arg: arg, field: field}, env) when is_binary(field) do
    case RecordFields.field_type(env, arg, field) do
      type when is_binary(type) -> Host.normalize_type_name(type)
      _ -> nil
    end
  end

  def expr_type(_expr, _env), do: nil

  defp function_return_type(nil, _env, _arg_count), do: nil

  defp function_return_type(target, env, arg_count) do
    case Map.get(Map.get(env, :__program_decls__, %{}), target) do
      %{type: type} ->
        if length(Host.function_arg_types(type)) == arg_count do
          Host.function_return_type(type) |> Host.normalize_type_name()
        end

      _ ->
        nil
    end
  end

  defp type_from_env(env, name) when is_binary(name) or is_atom(name) do
    env
    |> Map.get(:__var_types__, %{})
    |> Map.get(EnvBindings.binding_key(name))
    |> case do
      type when is_binary(type) -> Host.normalize_type_name(type)
      _ -> nil
    end
  end
end
