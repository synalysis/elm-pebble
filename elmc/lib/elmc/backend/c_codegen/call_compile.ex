defmodule Elmc.Backend.CCodegen.CallCompile do
  @moduledoc false
  alias Elmc.Backend.CCodegen.Types, as: Types


  alias Elmc.Backend.CCodegen.BuiltinOperators
  alias Elmc.Backend.CCodegen.BuiltinUnion
  alias Elmc.Backend.CCodegen.EnvBindings
  alias Elmc.Backend.CCodegen.FunctionCallCompile
  alias Elmc.Backend.CCodegen.Host
  alias Elmc.Backend.CCodegen.IRQueries
  alias Elmc.Backend.CCodegen.ListHofResolve
  alias Elmc.Backend.CCodegen.Native.TypedReturn
  alias Elmc.Backend.CCodegen.RecordCompile
  alias Elmc.Backend.CCodegen.RcRuntimeEmit
  alias Elmc.Backend.CCodegen.ResourceUnion
  alias Elmc.Backend.Plan.Lower.SpecialValues
  alias Elmc.Backend.Plan.Lower.SpecialValues.ElmCore
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
        cond do
          BuiltinUnion.maybe_nothing_literal?(%{op: :constructor_call, target: target, args: args}) ->
            BuiltinUnion.compile_maybe_nothing(env, counter)

          ResourceUnion.constructor?(target, args) ->
            Host.compile_expr(ResourceUnion.index_expr(target), env, counter)

          true ->
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

                cond do
                  args in [[], nil] ->
                    case resolve_local_zero_arg_let_name(name, env) do
                      {:ok, bound_expr} ->
                        Host.compile_expr(bound_expr, env, counter)

                      :error ->
                        FunctionCallCompile.compile(module_name, name, args, env, counter)
                    end

                  true ->
                    FunctionCallCompile.compile(module_name, name, args, env, counter)
                end
            end
        end

      result ->
        result
    end
  end

  @spec compile_qualified_call(String.t(), [String.t()], Types.compile_env(), Types.compile_counter()) ::
          Types.compile_result()

  defp compile_qualified_call(target, args, env, counter) do
    args = ListHofResolve.resolve_list_hof_call_args(target, args, env)

    result =
      case SpecialValues.special_value_from_target(target, args) do
        nil ->
          cond do
            BuiltinUnion.maybe_nothing_literal?(%{
              op: :qualified_call,
              target: target,
              args: args
            }) ->
              BuiltinUnion.compile_maybe_nothing(env, counter)

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

  @spec typed_debug_to_string_expr(String.t(), [Types.ir_expr()], Types.ir_expr(), Types.compile_env()) ::
          Types.ir_expr()

  defp typed_debug_to_string_expr("Debug.toString", [value], _expr, env) do
    function = TypeParsing.debug_from_list_c_symbol(debug_collection_kind(value, env))
    %{op: :runtime_call, function: function, args: [value]}
  end

  defp typed_debug_to_string_expr(_target, _args, expr, _env), do: expr

  @spec debug_collection_kind(Types.ir_expr(), Types.compile_env()) :: :set | :dict | :array | nil

  defp debug_collection_kind(value, env) do
    case value do
      %{op: :var} ->
        function_param_collection_kind(value, env)

      _ ->
        call_env = Map.put(env, :__var_types__, %{})

        case TypedReturn.expr_type(value, call_env) do
          type when is_binary(type) ->
            TypeParsing.debug_from_list_kind(type) || function_param_collection_kind(value, env)

          _ ->
            function_param_collection_kind(value, env)
        end
    end
  end

  @spec function_param_collection_kind(Types.ir_expr(), Types.compile_env()) :: :set | :dict | :array | nil

  defp function_param_collection_kind(%{op: :var, name: name}, env) when is_binary(name) do
    module = Map.get(env, :__module__, "Main")
    fn_name = Map.get(env, :__function_name__)

    case Map.get(Map.get(env, :__program_decls__, %{}), {module, fn_name}) do
      %{type: type, args: args} when is_binary(type) and is_list(args) ->
        with idx when is_integer(idx) <- Enum.find_index(args, &(&1 == name)),
             param_type when is_binary(param_type) <- Enum.at(TypeParsing.function_arg_types(type), idx) do
          TypeParsing.debug_from_list_kind(param_type)
        else
          _ -> nil
        end

      %{type: type} when is_binary(type) ->
        case TypeParsing.function_arg_types(type) do
          [param_type] -> TypeParsing.debug_from_list_kind(param_type)
          _ -> nil
        end

      _ ->
        nil
    end
  end

  defp function_param_collection_kind(_value, _env), do: nil

  @spec let_bound_closure_call(String.t(), [String.t()], Types.compile_env(), Types.compile_counter()) ::
          {:ok, Types.compile_result()} | :error

  defp let_bound_closure_call(target, args, env, counter) do
    with {module_name, name} <- Host.split_qualified_function_target(target),
         true <- module_name == Map.get(env, :__module__, "Main"),
         closure_var when is_binary(closure_var) <- let_bound_closure_var(env, name) do
      {:ok, FunctionCallCompile.compile_closure(closure_var, args, env, counter)}
    else
      _ -> :error
    end
  end

  @spec let_bound_closure_var(Types.compile_env(), String.t()) :: String.t() | nil

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
  defp compile_constructor_call(target, args, env, counter) when args in [[], nil] do
    # Nullary custom-type ctors are values (enum tag ints or tuple2(tag, unit)),
    # not `elmc_fn_*` CAFs. Emitting a function call leaves undefined symbols when
    # DCE drops the ctor (Maybe.withDefault Black model.color on tutorial).
    case nullary_constructor_value_expr(target) do
      {:ok, expr} -> Host.compile_expr(expr, env, counter)
      :error -> compile_constructor_fn_call(target, [], env, counter)
    end
  end

  defp compile_constructor_call(target, args, env, counter) do
    compile_constructor_fn_call(target, args, env, counter)
  end

  @spec nullary_constructor_value_expr(String.t()) :: {:ok, Types.ir_expr()} | :error

  defp nullary_constructor_value_expr(target) when is_binary(target) do
    tags = Process.get(:elmc_constructor_tags, %{})

    case IRQueries.lookup_tag(tags, target) do
      tag when is_integer(tag) ->
        tag_lit = %{op: :int_literal, value: tag, union_ctor: target}

        if enum_scalar_ctor?(target) do
          {:ok, tag_lit}
        else
          {:ok,
           %{
             op: :tuple2,
             left: tag_lit,
             right: %{op: :runtime_call, function: "elmc_unit", args: []}
           }}
        end

      _ ->
        :error
    end
  end

  @spec enum_scalar_ctor?(String.t()) :: boolean()

  defp enum_scalar_ctor?(target) when is_binary(target) do
    enums = Process.get(:elmc_enum_ctors, MapSet.new())
    short = target |> String.split(".") |> List.last()
    MapSet.member?(enums, target) or MapSet.member?(enums, short)
  end

  @spec compile_constructor_fn_call(
          String.t(),
          [Types.ir_expr()],
          Types.compile_env(),
          Types.compile_counter()
        ) :: Types.compile_result()

  defp compile_constructor_fn_call(target, args, env, counter) do
    c_name = Util.qualified_to_c_name(target)
    operand_env = RcRuntimeEmit.operand_env(env)

    {arg_code, arg_vars, _arg_passthrough, counter} =
      Enum.reduce(args, {"", [], [], counter}, fn arg_expr, {code_acc, vars_acc, passthrough_acc, c} ->
        {code, var, c2, passthrough?} =
          FunctionCallCompile.compile_call_operand_inner(arg_expr, operand_env, c, [])

        {code_acc <> code, vars_acc ++ [var], passthrough_acc ++ [passthrough?], c2}
      end)

    {out, next} = RcRuntimeEmit.compile_result_slot(env, counter)
    call_args_id = counter + 1
    args_var = "call_args_#{call_args_id}"
    argc = length(arg_vars)
    arg_list = Enum.join(arg_vars, ", ")
    call_expr = "#{c_name}(#{args_var}, #{argc})"

    out_decl =
      cond do
        ValueSlots.owned_ref?(out) ->
          ValueSlots.boxed_decl(out, call_expr, env)

        true ->
          "ElmcValue *#{out} = #{call_expr};"
      end

    releases =
      if Map.get(env, :__transfer_operand__, false) do
        ""
      else
        arg_vars
        |> Enum.reject(&(&1 == out))
        |> Enum.map_join("\n  ", &ValueSlots.post_call_operand_release/1)
      end

    code = """
    #{arg_code}
      ElmcValue *#{args_var}[#{max(argc, 1)}] = { #{arg_list} };
      #{out_decl}
      #{releases}
    """

    {code, out, max(next, call_args_id + 1)}
  end

  @spec forward_ref_call(String.t(), [String.t()], Types.compile_env(), Types.compile_counter()) ::
          Types.compile_result()

  defp forward_ref_call(name, args, env, counter) do
    ref_expr =
      case Map.get(env, name) do
        {:forward_ref, ref} -> "elmc_forward_ref_get(#{ref})"
        {:forward_ref_slot, slot} -> "elmc_forward_ref_get(#{slot})"
      end

    operand_env = RcRuntimeEmit.operand_env(env)

    {arg_code, arg_vars, counter} =
      Enum.reduce(args, {"", [], counter}, fn arg_expr, {code_acc, vars_acc, c} ->
        {code, var, c2} = Host.compile_expr(arg_expr, operand_env, c)
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

  @spec resolve_local_zero_arg_let_name(String.t(), Types.compile_env()) :: {:ok, Types.ir_expr()} | :error

  defp resolve_local_zero_arg_let_name(name, env) when is_binary(name) do
    module_name = Map.get(env, :__module__, "Main")
    decl_map = Map.get(env, :__program_decls__, %{})

    if Map.has_key?(decl_map, {module_name, name}) do
      :error
    else
      case EnvBindings.let_value_expr(env, name) do
        bound when is_map(bound) -> {:ok, bound}
        _ -> :error
      end
    end
  end
end
