defmodule Elmc.Backend.CCodegen.Native.TypedReturn do
  @moduledoc false

  alias Elmc.Backend.CCodegen.Host
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
end
