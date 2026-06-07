defmodule Elmc.Backend.CCodegen.CallCompile do
  @moduledoc false

  alias Elmc.Backend.CCodegen.BuiltinOperators
  alias Elmc.Backend.CCodegen.FunctionCallCompile
  alias Elmc.Backend.CCodegen.Host
  alias Elmc.Backend.CCodegen.ResourceUnion
  alias Elmc.Backend.CCodegen.SpecialValues
  alias Elmc.Backend.CCodegen.Types
  alias Elmc.Backend.CCodegen.Util

  @spec compile(Types.ir_call_expr(), Types.compile_env(), Types.compile_counter()) ::
          Types.compile_result()
  def compile(%{op: :qualified_call, target: target, args: args}, env, counter) do
    case SpecialValues.special_value_from_target(target, args) do
      nil ->
        cond do
          ResourceUnion.constructor?(target, args) ->
            Host.compile_expr(ResourceUnion.index_expr(target), env, counter)

          true ->
            case let_bound_closure_call(target, args, env, counter) do
              {:ok, result} ->
                result

              :error ->
                case BuiltinOperators.qualified_operator_name(target) do
                  nil ->
                    FunctionCallCompile.compile_cross_module(target, args, env, counter)

                  builtin_name ->
                    case BuiltinOperators.call(builtin_name, args, env, counter) do
                      nil -> FunctionCallCompile.compile_cross_module(target, args, env, counter)
                      result -> result
                    end
                end
            end
        end

      expr ->
        Host.compile_expr(expr, env, counter)
    end
  end

  def compile(%{op: :constructor_call, target: target, args: args}, env, counter) do
    case SpecialValues.special_value_from_target(target, args) do
      nil ->
        if ResourceUnion.constructor?(target, args) do
          Host.compile_expr(ResourceUnion.index_expr(target), env, counter)
        else
          compile_constructor_call(target, args, env, counter)
        end

      expr ->
        Host.compile_expr(expr, env, counter)
    end
  end

  def compile(%{op: :call, name: name, args: args}, env, counter) do
    case BuiltinOperators.call(name, args, env, counter) do
      nil ->
        case let_bound_closure_var(env, name) do
          closure_var when is_binary(closure_var) ->
            FunctionCallCompile.compile_closure(closure_var, args, env, counter)

          _ ->
            module_name = Map.get(env, :__module__, "Main")
            FunctionCallCompile.compile(module_name, name, args, env, counter)
        end

      result ->
        result
    end
  end

  defp let_bound_closure_call(target, args, env, counter) do
  with {module_name, name} <- Host.split_qualified_function_target(target),
       true <- module_name == Map.get(env, :__module__, "Main"),
       closure_var when is_binary(closure_var) <- let_bound_closure_var(env, name) do
      {:ok, FunctionCallCompile.compile_closure(closure_var, args, env, counter)}
    else
      _ -> :error
    end
  end

  defp let_bound_closure_var(env, name) do
    key = Host.binding_key(name)

    case Map.get(env, key) do
      closure_var when is_binary(closure_var) -> closure_var
      _ -> nil
    end
  end

  @spec compile_constructor_call(
          String.t(),
          [Types.ir_expr()],
          Types.compile_env(),
          Types.compile_counter()
        ) :: Types.compile_result()
  defp compile_constructor_call(target, args, env, counter) do
    c_name = Util.qualified_to_c_name(target)

    {arg_code, arg_vars, counter} =
      Enum.reduce(args, {"", [], counter}, fn arg_expr, {code_acc, vars_acc, c} ->
        {code, var, c2} = Host.compile_expr(arg_expr, env, c)
        {code_acc <> "\n  " <> code, vars_acc ++ [var], c2}
      end)

    next = counter + 1
    out = "tmp_#{next}"
    args_var = "call_args_#{next}"
    argc = length(arg_vars)
    arg_list = Enum.join(arg_vars, ", ")

    releases =
      arg_vars
      |> Enum.map_join("\n  ", fn var -> "elmc_release(#{var});" end)

    code = """
    #{arg_code}
      ElmcValue *#{args_var}[#{max(argc, 1)}] = { #{arg_list} };
      ElmcValue *#{out} = #{c_name}(#{args_var}, #{argc});
      #{releases}
    """

    {code, out, counter}
  end
end
