defmodule Elmc.Backend.CCodegen.Native.Bool do
  @moduledoc false

  alias Elmc.Backend.CCodegen.EnvBindings
  alias Elmc.Backend.CCodegen.Hoist
  alias Elmc.Backend.CCodegen.Host
  alias Elmc.Backend.CCodegen.Native.FunctionCall, as: NativeFunctionCall
  alias Elmc.Backend.CCodegen.Native.RecordFields
  alias Elmc.Backend.CCodegen.Native.TypedReturn
  alias Elmc.Backend.CCodegen.Types
  alias Elmc.Backend.CCodegen.Util

  @type compile_result :: Types.native_scalar_compile_result()

  @spec compile_expr(Types.ir_expr(), Types.compile_env(), Types.compile_counter()) ::
          compile_result()
  def compile_expr(expr, env, counter) do
    case Hoist.hoisted_native_bool_ref(env, expr) do
      ref when is_binary(ref) ->
        {"", ref, counter}

      nil ->
        compile_expr_uncached(expr, env, counter)
    end
  end

  defp compile_expr_uncached(%{op: :var, name: name} = expr, env, counter) do
    case EnvBindings.native_bool_binding(env, name) do
      native_ref when is_binary(native_ref) ->
        {"", native_ref, counter}

      nil ->
        case Map.fetch(env, name) do
          {:ok, source} when is_binary(source) ->
            {"", "elmc_as_bool(#{source})", counter}

          _ ->
            compile_fallback(expr, env, counter)
        end
    end
  end

  defp compile_expr_uncached(%{op: :field_access, arg: arg, field: field}, env, counter)
       when is_binary(arg) do
    case Map.fetch(env, arg) do
      {:ok, source} when is_binary(source) ->
        shape = Host.record_shape_for_var(env, arg)

        getter =
          if RecordFields.bool_field?(env, arg, field) do
            RecordFields.get_native_bool_expr(source, field, shape)
          else
            RecordFields.get_bool_expr(source, field, shape)
          end

        before_probe =
          env |> Host.battery_alert_field_probe(arg, field, :before) |> Host.agent_probe_region()

        after_probe =
          env |> Host.battery_alert_field_probe(arg, field, :after) |> Host.agent_probe_region()

        if before_probe == "" and after_probe == "" do
          {"", getter, counter}
        else
          next = counter + 1
          out = "native_bool_field_probe_#{next}"

          code = """
          #{before_probe}
            const elmc_int_t #{out} = #{getter};
          #{after_probe}
          """

          {code, out, next}
        end

      :error ->
        compile_fallback(%{op: :field_access, arg: arg, field: field}, env, counter)
    end
  end

  defp compile_expr_uncached(
         %{op: :field_access, arg: %{op: :var, name: name}, field: field},
         env,
         counter
       ) do
    compile_expr(%{op: :field_access, arg: name, field: field}, env, counter)
  end

  defp compile_expr_uncached(%{op: :field_access, arg: arg_expr, field: field}, env, counter)
       when is_map(arg_expr) do
    case Host.inline_record_field_expr(arg_expr, field, env) do
      nil ->
        {arg_code, arg_var, counter} = Host.compile_expr(arg_expr, env, counter)
        next = counter + 1
        out = "native_bool_field_#{next}"
        getter = RecordFields.get_bool_expr(arg_var, field, Host.record_shape(arg_expr, env))

        before_probe =
          env |> Host.battery_alert_field_probe(nil, field, :before) |> Host.agent_probe_region()

        after_probe =
          env |> Host.battery_alert_field_probe(nil, field, :after) |> Host.agent_probe_region()

        code = """
        #{arg_code}
        #{before_probe}
          const elmc_int_t #{out} = #{getter};
        #{after_probe}
          elmc_release(#{arg_var});
        """

        {code, out, next}

      field_expr ->
        compile_expr(field_expr, env, counter)
    end
  end

  defp compile_expr_uncached(
         %{op: :if, cond: cond_expr, then_expr: then_expr, else_expr: else_expr},
         env,
         counter
       ) do
    if expr?(then_expr, env) and expr?(else_expr, env) do
      {cond_code, cond_ref, counter} = compile_expr(cond_expr, env, counter)
      {then_code, then_ref, counter} = compile_expr(then_expr, env, counter)
      {else_code, else_ref, counter} = compile_expr(else_expr, env, counter)
      next = counter + 1
      out = "native_bool_if_#{next}"

      code = """
      #{cond_code}
        elmc_int_t #{out} = 0;
        if (#{cond_ref}) {
      #{Util.indent(then_code, 4)}
          #{out} = #{then_ref};
        } else {
      #{Util.indent(else_code, 4)}
          #{out} = #{else_ref};
        }
      """

      {code, out, next}
    else
      compile_fallback(
        %{op: :if, cond: cond_expr, then_expr: then_expr, else_expr: else_expr},
        env,
        counter
      )
    end
  end

  defp compile_expr_uncached(%{op: :compare, kind: kind, left: left, right: right}, env, counter) do
    operator =
      case kind do
        :eq -> "__eq__"
        :neq -> "__neq__"
        :gt -> "__gt__"
        :gte -> "__gte__"
        :lt -> "__lt__"
        :lte -> "__lte__"
        _ -> "__eq__"
      end

    compile_compare(left, right, operator, env, counter)
  end

  defp compile_expr_uncached(%{op: :call, name: name, args: [left, right]}, env, counter)
       when name in ["__eq__", "__neq__", "__lt__", "__lte__", "__gt__", "__gte__"] do
    compile_compare(left, right, name, env, counter)
  end

  defp compile_expr_uncached(%{op: :call, name: name, args: args} = expr, env, counter)
       when is_binary(name) do
    module_name = Map.get(env, :__module__, "Main")

    case NativeFunctionCall.compile_scalar(module_name, name, args, env, counter, :native_bool) do
      {code, value_ref, counter} -> {code, value_ref, counter}
      :error -> compile_fallback(expr, env, counter)
    end
  end

  defp compile_expr_uncached(%{op: :qualified_call, target: target, args: args} = expr, env, counter) do
    case Host.special_value_from_target(target, args) do
      nil ->
        case Host.qualified_builtin_operator_name(target) do
          builtin
          when builtin in ["__eq__", "__neq__", "__lt__", "__lte__", "__gt__", "__gte__"] ->
            compile_expr(%{op: :call, name: builtin, args: args}, env, counter)

          _ ->
            case Host.split_qualified_function_target(Host.normalize_special_target(target)) do
              {target_module, target_name} ->
                case NativeFunctionCall.compile_scalar(
                       target_module,
                       target_name,
                       args,
                       env,
                       counter,
                       :native_bool
                     ) do
                  {code, value_ref, counter} -> {code, value_ref, counter}
                  :error -> compile_fallback(expr, env, counter)
                end

              nil ->
                compile_fallback(expr, env, counter)
            end
        end

      rewritten ->
        compile_expr(rewritten, env, counter)
    end
  end

  defp compile_expr_uncached(
         %{op: :runtime_call, function: "elmc_basics_not", args: [value]},
         env,
         counter
       ) do
    {code, ref, counter} = compile_expr(value, env, counter)
    {code, "!(#{ref})", counter}
  end

  defp compile_expr_uncached(expr, env, counter), do: compile_fallback(expr, env, counter)

  @spec compile_compare(
          Types.ir_expr(),
          Types.ir_expr(),
          String.t(),
          Types.compile_env(),
          Types.compile_counter()
        ) :: compile_result()
  defp compile_compare(left, right, operator, env, counter) do
    cond do
      compare_safe?(operator, left, right, env) ->
        {left_code, left_ref, counter} = compile_expr(left, env, counter)
        {right_code, right_ref, counter} = compile_expr(right, env, counter)

        comparison =
          case operator do
            "__eq__" -> "=="
            "__neq__" -> "!="
          end

        {left_code <> right_code, "(#{left_ref} #{comparison} #{right_ref})", counter}

      Host.native_int_compare_safe?(operator, left, right, env) ->
        {left_code, left_ref, counter} = Host.compile_native_int_expr(left, env, counter)
        {right_code, right_ref, counter} = Host.compile_native_int_expr(right, env, counter)

        comparison =
          case operator do
            "__eq__" -> "=="
            "__neq__" -> "!="
            "__lt__" -> "<"
            "__lte__" -> "<="
            "__gt__" -> ">"
            "__gte__" -> ">="
          end

        {left_code <> right_code, "(#{left_ref} #{comparison} #{right_ref})", counter}

      true ->
        {left_code, left_var, counter} = Host.compile_expr(left, env, counter)
        {right_code, right_var, counter} = Host.compile_expr(right, env, counter)
        next = counter + 1
        out = "native_cmp_#{next}"

        code =
          case operator do
            "__eq__" ->
              """
              #{left_code}
                #{right_code}
                const elmc_int_t #{out} = elmc_value_equal(#{left_var}, #{right_var});
                elmc_release(#{left_var});
                elmc_release(#{right_var});
              """

            "__neq__" ->
              """
              #{left_code}
                #{right_code}
                const elmc_int_t #{out} = !elmc_value_equal(#{left_var}, #{right_var});
                elmc_release(#{left_var});
                elmc_release(#{right_var});
              """

            _ ->
              cmp_var = "__cmp_bool_#{next}"

              comparison =
                case operator do
                  "__lt__" -> "<"
                  "__lte__" -> "<="
                  "__gt__" -> ">"
                  "__gte__" -> ">="
                end

              """
              #{left_code}
                #{right_code}
                ElmcValue *#{cmp_var} = elmc_basics_compare(#{left_var}, #{right_var});
                const elmc_int_t #{out} = elmc_as_int(#{cmp_var}) #{comparison} 0;
                elmc_release(#{cmp_var});
                elmc_release(#{left_var});
                elmc_release(#{right_var});
              """
          end

        {code, out, next}
    end
  end

  @spec compare_safe?(String.t(), Types.ir_expr(), Types.ir_expr(), Types.compile_env()) ::
          boolean()
  defp compare_safe?(operator, left, right, env)
       when operator in ["__eq__", "__neq__"] do
    expr?(left, env) and expr?(right, env)
  end

  defp compare_safe?(_operator, _left, _right, _env), do: false

  @spec expr?(Types.ir_expr(), Types.compile_env()) :: boolean()
  def expr?(%{op: :var, name: name}, env) when is_binary(name) or is_atom(name),
    do:
      is_binary(EnvBindings.native_bool_binding(env, name)) or
        EnvBindings.boxed_bool_binding?(env, name) or
        TypedReturn.bool_expr?(%{op: :var, name: name}, env)

  def expr?(%{op: :field_access, arg: arg, field: field}, env),
    do: RecordFields.bool_field?(env, arg, field)

  def expr?(%{op: :if, then_expr: then_expr, else_expr: else_expr}, env),
    do: expr?(then_expr, env) and expr?(else_expr, env)

  def expr?(%{op: :runtime_call, function: "elmc_basics_not", args: [value]}, env),
    do: expr?(value, env)

  def expr?(expr, env), do: structural_expr?(expr) or TypedReturn.bool_expr?(expr, env)

  @spec structural_expr?(Types.ir_expr()) :: boolean()
  def structural_expr?(%{op: :compare}), do: true

  def structural_expr?(%{op: :call, name: name, args: args})
      when name in ["__eq__", "__neq__", "__lt__", "__lte__", "__gt__", "__gte__"] and
             length(args) == 2,
      do: true

  def structural_expr?(%{op: :qualified_call, target: target, args: args}) do
    case Host.special_value_from_target(target, args) do
      nil ->
        Host.qualified_builtin_operator_member?(target, [
          "__eq__",
          "__neq__",
          "__lt__",
          "__lte__",
          "__gt__",
          "__gte__"
        ]) and length(args) == 2

      expr ->
        structural_expr?(expr)
    end
  end

  def structural_expr?(_expr), do: false

  @spec compile_fallback(Types.ir_expr(), Types.compile_env(), Types.compile_counter()) ::
          compile_result()
  defp compile_fallback(expr, env, counter) do
    {code, var, counter} = Host.compile_expr(expr, env, counter)
    next = counter + 1
    out = "native_b_#{next}"

    {
      """
      #{code}
        const elmc_int_t #{out} = #{value_expr(expr, env, var)};
        elmc_release(#{var});
      """,
      out,
      next
    }
  end

  @spec value_expr(Types.ir_expr(), Types.compile_env(), String.t()) :: String.t()
  defp value_expr(expr, env, var) do
    if TypedReturn.bool_expr?(expr, env), do: "elmc_as_bool(#{var})", else: "elmc_as_int(#{var}) != 0"
  end
end
