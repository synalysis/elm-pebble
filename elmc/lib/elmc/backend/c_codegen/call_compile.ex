defmodule Elmc.Backend.CCodegen.CallCompile do
  @moduledoc false

  alias Elmc.Backend.CCodegen.BuiltinOperators
  alias Elmc.Backend.CCodegen.FunctionCallCompile
  alias Elmc.Backend.CCodegen.Host
  alias Elmc.Backend.CCodegen.ListHofResolve
  alias Elmc.Backend.CCodegen.Native.TypedReturn
  alias Elmc.Backend.CCodegen.RecordCompile
  alias Elmc.Backend.CCodegen.ResourceUnion
  alias Elmc.Backend.CCodegen.SpecialValues
  alias Elmc.Backend.CCodegen.SpecialValues.ElmCore
  alias Elmc.Backend.CCodegen.TypeParsing
  alias Elmc.Backend.CCodegen.Types
  alias Elmc.Backend.CCodegen.Util
  alias Elmc.Backend.CCodegen.ValueSlots

  @spec compile(Types.ir_call_expr(), Types.compile_env(), Types.compile_counter()) ::
          Types.compile_result()
  def compile(%{op: :qualified_call, target: target, args: args} = expr, env, counter) do
    if args == [] and RecordCompile.subexpr_cache_active?(env) do
      {code, ref, counter, _env} =
        RecordCompile.compile_expr_cached(expr, env, counter, fn expr, inner_env, inner_counter ->
          %{op: :qualified_call, target: inner_target, args: inner_args} = expr
          compile_qualified_call(inner_target, inner_args, inner_env, inner_counter)
        end)

      {code, ref, counter}
    else
      compile_qualified_call(target, args, env, counter)
    end
  end

  def compile(%{op: :partial_constructor, target: target, tag: tag, args: args, arity: arity}, env, counter) do
    FunctionCallCompile.partial_union_constructor(target, tag, args, arity, env, counter)
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

  def compile(%{op: :call, name: "__apply__", args: args}, env, counter)
      when is_list(args) and length(args) >= 2 do
    [fun | operands] = args
    {fun_code, fun_var, counter} = FunctionCallCompile.compile_call_operand(fun, env, counter)

    {acc_code, acc_var, counter} =
      Enum.reduce(operands, {fun_code, fun_var, counter}, fn operand, {code_acc, var_acc, c} ->
        {op_code, op_var, c} = FunctionCallCompile.compile_call_operand(operand, env, c)
        next = c + 1
        out = "tmp_#{next}"
        args_array = "apply_args_#{next}"

        code =
          code_acc <>
            op_code <>
            "  ElmcValue *#{args_array}[1] = { #{op_var} };\n" <>
            "  ElmcValue *#{out} = elmc_closure_call(#{var_acc}, #{args_array}, 1);\n"

        {code, out, next}
      end)

    {acc_code, acc_var, counter}
  end

  def compile(%{op: :call, name: name, args: args}, env, counter) do
    case BuiltinOperators.call(name, args, env, counter) do
      nil ->
        case let_bound_closure_var(env, name) do
          closure_var when is_binary(closure_var) ->
            FunctionCallCompile.compile_closure(closure_var, args, env, counter)

          _ ->
            case Map.get(env, name) do
              {:forward_ref, _} ->
                forward_ref_call(name, args, env, counter)

              {:forward_ref_slot, _} ->
                forward_ref_call(name, args, env, counter)

              _ ->
                module_name = Map.get(env, :__module__, "Main")
                FunctionCallCompile.compile(module_name, name, args, env, counter)
            end
        end

      result ->
        result
    end
  end

  defp compile_qualified_call(target, args, env, counter) do
    args = ListHofResolve.resolve_list_hof_call_args(target, args, env)

    result =
      case SpecialValues.special_value_from_target(target, args) do
        nil ->
          cond do
            ResourceUnion.constructor?(target, args) ->
              Host.compile_expr(ResourceUnion.index_expr(target), env, counter)

            true ->
              case let_bound_closure_call(target, args, env, counter) do
                {:ok, inner_result} ->
                  inner_result

                :error ->
                  case BuiltinOperators.qualified_operator_name(target) do
                    nil ->
                      FunctionCallCompile.compile_cross_module(target, args, env, counter)

                    builtin_name ->
                      case BuiltinOperators.call(builtin_name, args, env, counter) do
                        nil -> FunctionCallCompile.compile_cross_module(target, args, env, counter)
                        inner_result -> inner_result
                      end
                  end
              end
          end

        expr ->
          expr = typed_debug_to_string_expr(target, args, expr, env)
          Host.compile_expr(expr, env, counter)
      end

    ElmCore.with_comment(result, target)
  end

  defp typed_debug_to_string_expr("Debug.toString", [value], _expr, env) do
    function =
      if set_debug_value?(value, env) do
        "elmc_debug_set_to_string"
      else
        "elmc_debug_to_string"
      end

    %{op: :runtime_call, function: function, args: [value]}
  end

  defp typed_debug_to_string_expr(_target, _args, expr, _env), do: expr

  defp set_debug_value?(value, env) do
    case TypedReturn.expr_type(value, env) do
      type when is_binary(type) ->
        TypeParsing.set_type?(type) or function_param_set_type?(value, env)

      _ ->
        function_param_set_type?(value, env)
    end
  end

  defp function_param_set_type?(%{op: :var, name: name}, env) when is_binary(name) do
    module = Map.get(env, :__module__, "Main")
    fn_name = Map.get(env, :__function_name__)

    case Map.get(Map.get(env, :__program_decls__, %{}), {module, fn_name}) do
      %{type: type, args: args} when is_binary(type) and is_list(args) ->
        with idx when is_integer(idx) <- Enum.find_index(args, &(&1 == name)),
             param_type when is_binary(param_type) <- Enum.at(TypeParsing.function_arg_types(type), idx) do
          TypeParsing.set_type?(param_type)
        else
          _ -> false
        end

      %{type: type} when is_binary(type) ->
        case TypeParsing.function_arg_types(type) do
          [param_type] -> TypeParsing.set_type?(param_type)
          _ -> false
        end

      _ ->
        false
    end
  end

  defp function_param_set_type?(_value, _env), do: false

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
      |> Enum.map_join("\n  ", &ValueSlots.release_stmt/1)

    code = """
    #{arg_code}
      ElmcValue *#{args_var}[#{max(argc, 1)}] = { #{arg_list} };
      ElmcValue *#{out} = #{c_name}(#{args_var}, #{argc});
      #{releases}
    """

    {code, out, counter}
  end

  defp forward_ref_call(name, args, env, counter) do
    ref_expr =
      case Map.get(env, name) do
        {:forward_ref, ref} -> "elmc_forward_ref_get(#{ref})"
        {:forward_ref_slot, slot} -> "elmc_forward_ref_get(#{slot})"
      end

    {arg_code, arg_vars, counter} =
      Enum.reduce(args, {"", [], counter}, fn arg_expr, {code_acc, vars_acc, c} ->
        {code, var, c2} = Host.compile_expr(arg_expr, env, c)
        {code_acc <> "\n  " <> code, vars_acc ++ [var], c2}
      end)

    callee_counter = counter + 1
    callee = "tmp_#{callee_counter}"
    out_counter = callee_counter + 1
    out = "tmp_#{out_counter}"
    args_var = "call_args_#{out_counter}"
    argc = length(arg_vars)
    arg_list = Enum.join(arg_vars, ", ")

    releases =
      arg_vars
      |> Enum.map_join("\n  ", &ValueSlots.release_stmt/1)

    code = """
    #{arg_code}
      ElmcValue *#{callee} = #{ref_expr};
      ElmcValue *#{args_var}[#{max(argc, 1)}] = { #{arg_list} };
      ElmcValue *#{out} = elmc_closure_call(#{callee}, #{args_var}, #{argc});
      elmc_release(#{callee});
      #{releases}
    """

    {code, out, out_counter}
  end
end
