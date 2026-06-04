defmodule Elmc.Backend.CCodegen.Native.Int do
  @moduledoc false

  alias Elmc.Backend.CCodegen.EnvBindings
  alias Elmc.Backend.CCodegen.Host
  alias Elmc.Backend.CCodegen.Native.FunctionCall, as: NativeFunctionCall
  alias Elmc.Backend.CCodegen.Native.TypedReturn
  alias Elmc.Backend.CCodegen.Native.RecordFields, as: RecordFields
  alias Elmc.Backend.CCodegen.Types
  alias Elmc.Backend.CCodegen.Util

  @spec expr?(Types.ir_expr(), Types.compile_env()) :: boolean()
  def expr?(%{op: :var, name: name}, env) when is_binary(name) or is_atom(name),
    do: EnvBindings.boxed_int_binding?(env, name) or is_binary(EnvBindings.native_int_binding(env, name))

  def expr?(%{op: :field_access, arg: arg, field: field}, env),
    do: RecordFields.int_field?(env, arg, field)

  def expr?(%{op: op, arg: _arg}, _env) when op in [:tuple_first, :tuple_first_expr, :tuple_second_expr],
    do: true

  def expr?(%{op: :c_int_expr}, _env), do: true

  def expr?(%{op: :if, then_expr: then_expr, else_expr: else_expr}, env),
    do: expr?(then_expr, env) and expr?(else_expr, env)

  def expr?(%{op: :call, name: name, args: [left, right]}, env)
      when name in ["__add__", "__sub__", "__mul__", "__idiv__", "modBy", "remainderBy"] do
    expr?(left, env) and expr?(right, env)
  end

  def expr?(%{op: :call, name: name, args: [value]}, env) when name in ["abs", "negate"],
    do: expr?(value, env)

  def expr?(%{op: :call, name: name, args: args}, env) when is_binary(name) do
    module_name = Map.get(env, :__module__, "Main")
    inline_function_expr?({module_name, name}, args, env) or
      typed_expr?(%{op: :call, name: name, args: args}, env)
  end

  def expr?(%{op: :runtime_call, function: function, args: [left, right]}, env)
      when function in [
             "elmc_basics_min",
             "elmc_basics_max",
             "elmc_basics_mod_by",
             "elmc_basics_remainder_by"
           ] do
    expr?(left, env) and expr?(right, env)
  end

  def expr?(%{op: :runtime_call, function: "elmc_maybe_with_default", args: [default_val, _maybe]}, env),
    do: expr?(default_val, env)

  def expr?(
        %{op: :runtime_call, function: "elmc_list_nth_int_default_boxed", args: [_list, index, default_val]},
        env
      ),
      do: expr?(index, env) and expr?(default_val, env)

  def expr?(%{op: :runtime_call, function: function, args: [value]}, env)
      when function in ["elmc_basics_abs", "elmc_basics_negate"] do
    expr?(value, env)
  end

  def expr?(%{op: :runtime_call, function: function, args: [value]}, env)
      when function in [
             "elmc_basics_round",
             "elmc_basics_floor",
             "elmc_basics_ceiling",
             "elmc_basics_truncate"
           ] do
    (function == "elmc_basics_round" and Host.pebble_bound_trig_round_expr?(value, env)) or
      Host.native_float_expr?(value, env)
  end

  def expr?(%{op: :qualified_call, target: target, args: [value]}, env)
      when target in ["Basics.round", "round"] do
    Host.pebble_bound_trig_round_expr?(value, env) or
      expr?(%{op: :runtime_call, function: "elmc_basics_round", args: [value]}, env)
  end

  def expr?(%{op: :qualified_call, target: target, args: args}, env) do
    case Host.special_value_from_target(target, args) do
      %{op: op} when op in [:int_literal, :char_literal] ->
        true

      nil ->
        cond do
          Host.qualified_builtin_operator_member?(target, [
            "__add__",
            "__sub__",
            "__mul__",
            "__idiv__",
            "modBy",
            "remainderBy"
          ]) and length(args) == 2 ->
            Enum.all?(args, &expr?(&1, env))

          Host.qualified_builtin_operator_member?(target, ["abs", "negate"]) and length(args) == 1 ->
            Enum.all?(args, &expr?(&1, env))

          target_key = Host.split_qualified_function_target(Host.normalize_special_target(target)) ->
            inline_function_expr?(target_key, args, env) or
              typed_expr?(%{op: :qualified_call, target: target, args: args}, env)

          true ->
            false
        end

      expr ->
        expr?(expr, env)
    end
  end

  def expr?(expr, _env), do: structural_expr?(expr)

  @spec typed_expr?(Types.ir_expr(), Types.compile_env()) :: boolean()
  def typed_expr?(%{op: :call, name: name, args: args}, env) when is_binary(name) do
    module_name = Map.get(env, :__module__, "Main")
    TypedReturn.function_return?({module_name, name}, env, length(args || []), "Int")
  end

  def typed_expr?(%{op: :qualified_call, target: target, args: args}, env) when is_binary(target) do
    target
    |> Host.normalize_special_target()
    |> Host.split_qualified_function_target()
    |> TypedReturn.function_return?(env, length(args || []), "Int")
  end

  def typed_expr?(_expr, _env), do: false

  @spec compare_safe?(String.t(), Types.ir_expr(), Types.ir_expr(), Types.compile_env()) ::
          boolean()
  def compare_safe?(operator, left, right, env)
      when operator in ["__eq__", "__neq__", "__lt__", "__lte__", "__gt__", "__gte__"] do
    expr?(left, env) and expr?(right, env)
  end

  @spec inline_function_expr?(Types.function_decl_key(), [Types.ir_expr()], Types.compile_env()) ::
          boolean()
  def inline_function_expr?(target_key, args, env) do
    decl_map = Map.get(env, :__program_decls__, %{})
    inline_stack = Map.get(env, :__native_int_inline_stack__, MapSet.new())

    with %{args: arg_names, expr: body} when is_list(arg_names) <- Map.get(decl_map, target_key),
         true <- length(arg_names) == length(args),
         false <- MapSet.member?(inline_stack, target_key),
         substituted <- Host.substitute_expr(body, Map.new(Enum.zip(arg_names, args))) do
      env =
        Map.put(
          env,
          :__native_int_inline_stack__,
          MapSet.put(inline_stack, target_key)
        )

      expr?(substituted, env)
    else
      _ -> false
    end
  end

  @spec structural_expr?(Types.ir_expr()) :: boolean()
  def structural_expr?(%{op: op})
      when op in [:int_literal, :char_literal, :add_const, :sub_const, :add_vars],
      do: true

  def structural_expr?(%{op: :call, name: name, args: args})
      when name in ["__add__", "__sub__", "__mul__", "__idiv__", "modBy", "remainderBy"] and
             length(args) == 2,
      do: Enum.all?(args, &structural_expr?/1)

  def structural_expr?(%{op: :call, name: name, args: args})
      when name in ["abs", "negate"] and length(args) == 1,
      do: Enum.all?(args, &structural_expr?/1)

  def structural_expr?(%{op: :runtime_call, function: function, args: args})
      when function in ["elmc_basics_mod_by", "elmc_basics_remainder_by"] and length(args) == 2,
      do: Enum.all?(args, &structural_expr?/1)

  def structural_expr?(%{op: :runtime_call, function: function, args: args})
      when function in ["elmc_basics_abs", "elmc_basics_negate"] and length(args) == 1,
      do: Enum.all?(args, &structural_expr?/1)

  def structural_expr?(%{op: :qualified_call, target: target, args: args}) do
    case Host.special_value_from_target(target, args) do
      %{op: op} when op in [:int_literal, :char_literal] ->
        true

      nil ->
        (Host.qualified_builtin_operator_member?(target, [
           "__add__",
           "__sub__",
           "__mul__",
           "__idiv__",
           "modBy",
           "remainderBy"
         ]) and length(args) == 2 and Enum.all?(args, &structural_expr?/1)) or
          (Host.qualified_builtin_operator_member?(target, ["abs", "negate"]) and length(args) == 1 and
             Enum.all?(args, &structural_expr?/1))

      expr ->
        structural_expr?(expr)
    end
  end

  def structural_expr?(_expr), do: false

  @spec compile_boxed(Types.ir_expr(), Types.compile_env(), Types.compile_counter()) ::
          Types.native_scalar_compile_result()
  def compile_boxed(expr, env, counter) do
    {code, value_ref, counter} = compile_expr(expr, env, counter)
    next = counter + 1
    out = "tmp_#{next}"

    {
      """
      #{code}
        ElmcValue *#{out} = elmc_new_int(#{value_ref});
      """,
      out,
      next
    }
  end

  @spec compile_expr(Types.ir_expr(), Types.compile_env(), Types.compile_counter()) ::
          Types.native_scalar_compile_result()
  def compile_expr(expr, env, counter) do
    case Host.hoisted_native_int_lookup(env, expr) do
      {:ok, ref} ->
        {"", ref, counter}

      :error ->
        dispatch(expr, env, counter)
    end
  end

  defp dispatch(%{op: :int_literal, value: value}, _env, counter),
    do: {"", "#{value}", counter}

  defp dispatch(%{op: :c_int_expr, value: value}, _env, counter)
       when is_binary(value),
       do: {"", value, counter}

  defp dispatch(%{op: :char_literal, value: value}, _env, counter),
    do: {"", "#{value}", counter}

  defp dispatch(
         %{op: :if, cond: cond_expr, then_expr: then_expr, else_expr: else_expr},
         env,
         counter
       ) do
    if expr?(then_expr, env) and expr?(else_expr, env) do
      {cond_code, cond_ref, counter} = Host.compile_native_bool_expr(cond_expr, env, counter)
      {then_code, then_ref, counter} = compile_expr(then_expr, env, counter)
      {else_code, else_ref, counter} = compile_expr(else_expr, env, counter)
      next = counter + 1
      out = "native_if_#{next}"

      code = """
      #{cond_code}
        elmc_int_t #{out};
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

  defp dispatch(%{op: :field_access, arg: arg, field: field}, env, counter)
       when is_binary(arg) do
    case Map.fetch(env, arg) do
      {:ok, {:native_record, fields}} ->
        case Map.fetch(fields, field) do
          {:ok, native_ref} -> {"", native_ref, counter}
          :error -> {"", "0", counter}
        end

      {:ok, source} when is_binary(source) ->
        getter = Host.record_get_int_expr(source, field, Host.record_shape_for_var(env, arg))

        before_probe =
          env |> Host.battery_alert_field_probe(arg, field, :before) |> Host.agent_probe_region()

        after_probe = env |> Host.battery_alert_field_probe(arg, field, :after) |> Host.agent_probe_region()

        if before_probe == "" and after_probe == "" do
          {"", getter, counter}
        else
          next = counter + 1
          out = "native_field_probe_#{next}"

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

  defp dispatch(
         %{op: :field_access, arg: %{op: :var, name: name}, field: field},
         env,
         counter
       ) do
    case Map.get(env, name) do
      {:native_record, fields} ->
        case Map.fetch(fields, field) do
          {:ok, native_ref} -> {"", native_ref, counter}
          :error -> {"", "0", counter}
        end

      _ ->
        compile_expr(%{op: :field_access, arg: name, field: field}, env, counter)
    end
  end

  defp dispatch(%{op: :field_access, arg: arg_expr, field: field}, env, counter)
       when is_map(arg_expr) do
    case Host.inline_record_field_expr(arg_expr, field, env) do
      nil ->
        {arg_code, arg_var, counter} = Host.compile_expr(arg_expr, env, counter)
        next = counter + 1
        out = "native_field_#{next}"
        getter = Host.record_get_int_expr(arg_var, field, Host.record_shape(arg_expr, env))

        before_probe =
          env |> Host.battery_alert_field_probe(nil, field, :before) |> Host.agent_probe_region()

        after_probe = env |> Host.battery_alert_field_probe(nil, field, :after) |> Host.agent_probe_region()

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

  defp dispatch(%{op: op, arg: %{op: :var, name: name}}, env, counter)
       when op in [:tuple_first, :tuple_first_expr, :tuple_second_expr] do
    case Map.fetch(env, name) do
      {:ok, source} when is_binary(source) ->
        compile_tuple_int_source(source, tuple_accessor(op), counter)

      _ ->
        compile_tuple_int_expr(%{op: :var, name: name}, tuple_accessor(op), env, counter)
    end
  end

  defp dispatch(%{op: op, arg: arg_expr}, env, counter)
       when op in [:tuple_first, :tuple_first_expr, :tuple_second_expr] do
    compile_tuple_int_expr(arg_expr, tuple_accessor(op), env, counter)
  end

  defp dispatch(%{op: :var, name: name} = expr, env, counter) do
    case EnvBindings.native_int_binding(env, name) do
      native_ref when is_binary(native_ref) ->
        {"", native_ref, counter}

      nil ->
        case Map.fetch(env, name) do
          {:ok, source} when is_binary(source) ->
            if EnvBindings.boxed_int_binding?(env, name) do
              {"", "elmc_as_int(#{source})", counter}
            else
              {"", "(#{source} ? elmc_as_int(#{source}) : 0)", counter}
            end

          _ ->
            compile_fallback(expr, env, counter)
        end
    end
  end

  defp dispatch(%{op: :add_const, var: name, value: value}, env, counter) do
    compile_expr(
      %{
        op: :call,
        name: "__add__",
        args: [%{op: :var, name: name}, %{op: :int_literal, value: value}]
      },
      env,
      counter
    )
  end

  defp dispatch(%{op: :sub_const, var: name, value: value}, env, counter) do
    compile_expr(
      %{
        op: :call,
        name: "__sub__",
        args: [%{op: :var, name: name}, %{op: :int_literal, value: value}]
      },
      env,
      counter
    )
  end

  defp dispatch(%{op: :add_vars, left: left, right: right}, env, counter) do
    compile_expr(
      %{op: :call, name: "__add__", args: [%{op: :var, name: left}, %{op: :var, name: right}]},
      env,
      counter
    )
  end

  defp dispatch(%{op: :call, name: name, args: [left, right]}, env, counter)
       when name in ["__add__", "__sub__", "__mul__"] do
    op = %{"__add__" => "+", "__sub__" => "-", "__mul__" => "*"}[name]
    {left_code, left_ref, counter} = compile_expr(left, env, counter)
    {right_code, right_ref, counter} = compile_expr(right, env, counter)
    {left_code <> right_code, "(#{left_ref} #{op} #{right_ref})", counter}
  end

  defp dispatch(%{op: :call, name: "__idiv__", args: [left, right]}, env, counter) do
    {left_code, left_ref, counter} = compile_expr(left, env, counter)

    case static_nonzero_int_value(right) do
      value when is_integer(value) ->
        {left_code, "(#{left_ref} / #{value})", counter}

      nil ->
        {right_code, right_ref, counter} = compile_expr(right, env, counter)
        next = counter + 1
        denom = "native_den_#{next}"

        code = """
        #{left_code}#{right_code}
          const elmc_int_t #{denom} = #{right_ref};
        """

        {code, "(#{denom} == 0 ? 0 : (#{left_ref} / #{denom}))", next}
    end
  end

  defp dispatch(%{op: :call, name: name, args: [left, right]} = expr, env, counter)
       when name in ["min", "max"] do
    {left_code, left_ref, counter} = compile_expr(left, env, counter)
    {right_code, right_ref, counter} = compile_expr(right, env, counter)
    next = counter + 1
    left_var = "native_#{name}_left_#{next}"
    right_var = "native_#{name}_right_#{next}"
    out = "native_#{name}_#{next}"
    cmp_op = if name == "min", do: "<=", else: ">="

    code = """
    #{left_code}
      #{right_code}
      const elmc_int_t #{left_var} = #{left_ref};
      const elmc_int_t #{right_var} = #{right_ref};
      const elmc_int_t #{out} = (#{left_var} #{cmp_op} #{right_var}) ? #{left_var} : #{right_var};
    """

    if Host.hoisted_native_ints_enabled?(env), do: Host.register_hoisted_native_int(expr, out)

    {code, out, next}
  end

  defp dispatch(%{op: :call, name: name, args: [value]}, env, counter)
       when name in ["abs", "negate"] do
    {value_code, value_ref, counter} = compile_expr(value, env, counter)
    next = counter + 1
    value_var = "native_#{name}_arg_#{next}"
    out = "native_#{name}_#{next}"

    expr =
      case name do
        "abs" -> "(#{value_var} < 0 ? -#{value_var} : #{value_var})"
        "negate" -> "(-#{value_var})"
      end

    code = """
    #{value_code}
      const elmc_int_t #{value_var} = #{value_ref};
      const elmc_int_t #{out} = #{expr};
    """

    {code, out, next}
  end

  defp dispatch(%{op: :call, name: "modBy", args: [base, value]}, env, counter) do
    case static_nonzero_int_value(base) do
      base_value when is_integer(base_value) ->
        {value_code, value_ref, counter} = compile_expr(value, env, counter)
        next = counter + 1
        out = "native_mod_#{next}"
        correction = abs(base_value)

        code = """
        #{value_code}
          elmc_int_t #{out} = #{value_ref} % #{base_value};
          if (#{out} < 0) #{out} += #{correction};
        """

        {code, out, next}

      nil ->
        {base_code, base_ref, counter} = compile_expr(base, env, counter)
        {value_code, value_ref, counter} = compile_expr(value, env, counter)
        next = counter + 1
        base_var = "native_mod_base_#{next}"
        out = "native_mod_#{next}"

        code = """
        #{base_code}#{value_code}
          const elmc_int_t #{base_var} = #{base_ref};
          elmc_int_t #{out} = 0;
          if (#{base_var} != 0) {
            #{out} = #{value_ref} % #{base_var};
            if (#{out} < 0) #{out} += (#{base_var} < 0 ? -#{base_var} : #{base_var});
          }
        """

        {code, out, next}
    end
  end

  defp dispatch(
         %{op: :call, name: "remainderBy", args: [base, value]},
         env,
         counter
       ) do
    {base_code, base_ref, counter} = compile_expr(base, env, counter)
    {value_code, value_ref, counter} = compile_expr(value, env, counter)
    next = counter + 1
    base_var = "native_rem_base_#{next}"

    code = """
    #{base_code}#{value_code}
      const elmc_int_t #{base_var} = #{base_ref};
    """

    {code, "(#{base_var} == 0 ? 0 : (#{value_ref} % #{base_var}))", next}
  end

  defp dispatch(%{op: :call, name: name, args: args} = expr, env, counter)
       when is_binary(name) do
    module_name = Map.get(env, :__module__, "Main")

    case inline_function({module_name, name}, args, env, counter) do
      {:ok, code, value_ref, counter} -> {code, value_ref, counter}
      :error ->
        case NativeFunctionCall.compile_scalar(module_name, name, args, env, counter, :native_int) do
          {code, value_ref, counter} -> {code, value_ref, counter}
          :error -> compile_fallback(expr, env, counter)
        end
    end
  end

  defp dispatch(
         %{op: :qualified_call, target: target, args: args} = expr,
         env,
         counter
       ) do
    case Host.special_value_from_target(target, args) do
      %{op: :int_literal, value: value} ->
        {"", "#{value}", counter}

      %{op: :char_literal, value: value} ->
        {"", "#{value}", counter}

      nil ->
        case Host.qualified_builtin_operator_name(target) do
          builtin
          when builtin in ["__add__", "__sub__", "__mul__", "__idiv__", "modBy", "remainderBy"] ->
            compile_expr(%{op: :call, name: builtin, args: args}, env, counter)

          _ ->
            case Host.split_qualified_function_target(Host.normalize_special_target(target)) do
              nil ->
                compile_fallback(expr, env, counter)

              target_key ->
                case inline_function(target_key, args, env, counter) do
                  {:ok, code, value_ref, counter} -> {code, value_ref, counter}
                  :error ->
                    {target_module, target_name} = target_key

                    case NativeFunctionCall.compile_scalar(
                           target_module,
                           target_name,
                           args,
                           env,
                           counter,
                           :native_int
                         ) do
                      {code, value_ref, counter} -> {code, value_ref, counter}
                      :error -> compile_fallback(expr, env, counter)
                    end
                end
            end
        end

      rewritten ->
        compile_expr(rewritten, env, counter)
    end
  end

  defp dispatch(
         %{op: :runtime_call, function: "elmc_basics_mod_by", args: [base, value]},
         env,
         counter
       ),
       do: compile_expr(%{op: :call, name: "modBy", args: [base, value]}, env, counter)

  defp dispatch(
         %{op: :runtime_call, function: "elmc_basics_remainder_by", args: [base, value]},
         env,
         counter
       ),
       do:
         compile_expr(
           %{op: :call, name: "remainderBy", args: [base, value]},
           env,
           counter
         )

  defp dispatch(
         %{op: :runtime_call, function: function, args: [left, right]},
         env,
         counter
       )
       when function in ["elmc_basics_min", "elmc_basics_max"] do
    compile_expr(
      %{op: :call, name: native_min_max_name(function), args: [left, right]},
      env,
      counter
    )
  end

  defp dispatch(
         %{op: :runtime_call, function: "elmc_list_nth_int_default_boxed", args: [list, index, default_val]},
         env,
         counter
       ) do
    {list_code, list_var, counter} = Host.compile_expr(list, env, counter)
    {index_code, index_ref, counter} = compile_expr(index, env, counter)
    {default_code, default_ref, counter} = compile_expr(default_val, env, counter)
    next = counter + 1
    out = "native_list_nth_#{next}"

    code = """
    #{list_code}#{index_code}#{default_code}
      const elmc_int_t #{out} = elmc_list_nth_int_default(#{list_var}, #{index_ref}, #{default_ref});
      elmc_release(#{list_var});
    """

    {code, out, next}
  end

  defp dispatch(
         %{op: :runtime_call, function: function, args: [value]},
         env,
         counter
       )
       when function in ["elmc_basics_abs", "elmc_basics_negate"] do
    compile_expr(
      %{op: :call, name: native_unary_int_name(function), args: [value]},
      env,
      counter
    )
  end

  defp dispatch(
         %{op: :runtime_call, function: function, args: [value]},
         env,
         counter
       )
       when function in [
              "elmc_basics_round",
              "elmc_basics_floor",
              "elmc_basics_ceiling",
              "elmc_basics_truncate"
            ] do
    case function == "elmc_basics_round" and pebble_trig_round(value, env, counter) do
      {:ok, code, out, counter} ->
        {code, out, counter}

      _ ->
        float_to_int_expr(function, value, env, counter)
    end
  end

  defp dispatch(
         %{op: :runtime_call, function: "elmc_maybe_with_default", args: [default_val, maybe]},
         env,
         counter
       ) do
    {default_code, default_ref, counter} = compile_expr(default_val, env, counter)

    {maybe_code, maybe_ref, release_maybe, counter} =
      case maybe do
        %{op: :qualified_call, target: "List.head", args: [list]} ->
          {code, var, counter} = Host.compile_expr(list, env, counter)
          {code, "elmc_list_head_with_default_int(#{default_ref}, #{var})", var, counter}

        %{op: :runtime_call, function: "elmc_list_head", args: [list]} ->
          {code, var, counter} = Host.compile_expr(list, env, counter)
          {code, "elmc_list_head_with_default_int(#{default_ref}, #{var})", var, counter}

        %{op: :qualified_call, target: "Array.get", args: [index, array]} ->
          {index_code, index_ref, counter} = compile_expr(index, env, counter)
          {array_code, array_var, counter} = Host.compile_expr(array, env, counter)

          {
            index_code <> array_code,
            "elmc_array_get_with_default_int(#{default_ref}, #{index_ref}, #{array_var})",
            array_var,
            counter
          }

        %{op: :runtime_call, function: "elmc_array_get", args: [index, array]} ->
          {index_code, index_ref, counter} = compile_expr(index, env, counter)
          {array_code, array_var, counter} = Host.compile_expr(array, env, counter)

          {
            index_code <> array_code,
            "elmc_array_get_with_default_int(#{default_ref}, #{index_ref}, #{array_var})",
            array_var,
            counter
          }

        %{op: :qualified_call, target: "Dict.get", args: [key, dict]} ->
          compile_dict_get_with_default(default_ref, key, dict, env, counter)

        %{op: :runtime_call, function: "elmc_dict_get", args: [key, dict]} ->
          compile_dict_get_with_default(default_ref, key, dict, env, counter)

        %{op: :field_access, arg: arg, field: field} when is_binary(arg) ->
          case Map.fetch(env, arg) do
            {:ok, source} when is_binary(source) ->
              getter =
                RecordFields.get_maybe_int_expr(
                  source,
                  field,
                  Host.record_shape_for_var(env, arg),
                  default_ref
                )

              {"", getter, false, counter}

            :error ->
              {code, var, counter} = Host.compile_expr(maybe, env, counter)
              {code, "elmc_maybe_with_default_int(#{default_ref}, #{var})", var, counter}
          end

        %{op: :field_access, arg: %{op: :var, name: name}, field: field} when is_binary(name) ->
          case Map.fetch(env, name) do
            {:ok, source} when is_binary(source) ->
              getter =
                RecordFields.get_maybe_int_expr(
                  source,
                  field,
                  Host.record_shape_for_var(env, name),
                  default_ref
                )

              {"", getter, false, counter}

            :error ->
              {code, var, counter} = Host.compile_expr(maybe, env, counter)
              {code, "elmc_maybe_with_default_int(#{default_ref}, #{var})", var, counter}
          end

        _ ->
          {code, var, counter} = Host.compile_expr(maybe, env, counter)
          {code, "elmc_maybe_with_default_int(#{default_ref}, #{var})", var, counter}
      end

    next = counter + 1
    out = "native_maybe_default_#{next}"

    release_code =
      if is_binary(release_maybe), do: "\n  elmc_release(#{release_maybe});", else: ""

    code = """
    #{default_code}
    #{maybe_code}
      const elmc_int_t #{out} = #{maybe_ref};#{release_code}
    """

    {code, out, next}
  end

  defp dispatch(expr, env, counter),
    do: compile_fallback(expr, env, counter)

  defp float_to_int_expr(function, value, env, counter) do
    if Host.native_float_expr?(value, env) do
      {value_code, value_ref, counter} = Host.compile_native_float_expr(value, env, counter)
      next = counter + 1
      value_var = "native_float_arg_#{next}"
      out = "native_float_to_int_#{next}"

      expr =
        case function do
          "elmc_basics_round" ->
            "(elmc_int_t)(#{value_var} + (#{value_var} >= 0 ? 0.5 : -0.5))"

          "elmc_basics_floor" ->
            "((elmc_int_t)#{value_var} > #{value_var} ? (elmc_int_t)#{value_var} - 1 : (elmc_int_t)#{value_var})"

          "elmc_basics_ceiling" ->
            "((elmc_int_t)#{value_var} < #{value_var} ? (elmc_int_t)#{value_var} + 1 : (elmc_int_t)#{value_var})"

          "elmc_basics_truncate" ->
            "(elmc_int_t)#{value_var}"
        end

      code = """
      #{value_code}
        const double #{value_var} = #{value_ref};
        const elmc_int_t #{out} = #{expr};
      """

      {code, out, next}
    else
      compile_fallback(
        %{op: :runtime_call, function: function, args: [value]},
        env,
        counter
      )
    end
  end

  defp pebble_trig_round(
         %{op: :call, name: "__mul__", args: [left, right]},
         env,
         counter
       ) do
    cond do
      trig = pebble_bound_trig_expr(left, env) ->
        pebble_trig_round_expr(trig, right, env, counter)

      trig = pebble_bound_trig_expr(right, env) ->
        pebble_trig_round_expr(trig, left, env, counter)

      true ->
        :error
    end
  end

  defp pebble_trig_round(_expr, _env, _counter), do: :error

  defp pebble_trig_round_expr(
         {trig_function, angle_expr},
         radius_float_expr,
         env,
         counter
       ) do
    with {:ok, radius_expr} <- to_float_arg(radius_float_expr),
         {:ok, angle_source_expr} <- pebble_angle_source(angle_expr) do
      {angle_code, angle_ref, counter} = compile_expr(angle_source_expr, env, counter)
      {radius_code, radius_ref, counter} = compile_expr(radius_expr, env, counter)
      next = counter + 1
      trig_var = "native_trig_#{next}"
      prod_var = "native_trig_prod_#{next}"
      out = "native_trig_round_#{next}"
      c_trig = if trig_function == :sin, do: "sin_lookup", else: "cos_lookup"

      double_trig =
        if trig_function == :sin,
          do: "generated_trig_sin_double",
          else: "generated_trig_cos_double"

      code = """
      #{angle_code}
      #{radius_code}
      #if defined(PBL_PLATFORM_APLITE) || defined(PBL_PLATFORM_BASALT) || defined(PBL_PLATFORM_CHALK) || defined(PBL_PLATFORM_DIORITE) || defined(PBL_PLATFORM_FLINT) || defined(PBL_PLATFORM_EMERY) || defined(PBL_PLATFORM_GABBRO)
        const int32_t #{trig_var} = #{c_trig}((int32_t)#{angle_ref});
        const int32_t #{prod_var} = #{trig_var} * (int32_t)#{radius_ref};
        const elmc_int_t #{out} = (#{prod_var} + (#{prod_var} >= 0 ? (TRIG_MAX_RATIO / 2) : -(TRIG_MAX_RATIO / 2))) / TRIG_MAX_RATIO;
      #else
        const double native_trig_theta_#{next} = ((((double)#{angle_ref} * (double)2) * 3.141592653589793) / (double)65536);
        const double native_trig_arg_#{next} = #{double_trig}(native_trig_theta_#{next}) * (double)#{radius_ref};
        const elmc_int_t #{out} = (elmc_int_t)(native_trig_arg_#{next} + (native_trig_arg_#{next} >= 0 ? 0.5 : -0.5));
      #endif
      """

      {:ok, code, out, next}
    else
      _ -> :error
    end
  end

  defp pebble_bound_trig_expr(
         %{op: :qualified_call, target: target, args: [%{op: :var, name: name}]},
         env
       )
       when target in ["Basics.sin", "sin", "Basics.cos", "cos"] do
    case EnvBindings.pebble_angle_binding(env, name) do
      nil -> nil
      angle_expr -> {if(target in ["Basics.sin", "sin"], do: :sin, else: :cos), angle_expr}
    end
  end

  defp pebble_bound_trig_expr(
         %{op: :runtime_call, function: function, args: [%{op: :var, name: name}]},
         env
       )
       when function in ["elmc_basics_sin", "elmc_basics_cos"] do
    case EnvBindings.pebble_angle_binding(env, name) do
      nil -> nil
      angle_expr -> {if(function == "elmc_basics_sin", do: :sin, else: :cos), angle_expr}
    end
  end

  defp pebble_bound_trig_expr(_expr, _env), do: nil

  defp pebble_bound_trig_round_mul_side?(trig_side, float_side, env) do
    match?({_fun, _angle}, pebble_bound_trig_expr(trig_side, env)) and
      match?({:ok, _}, to_float_arg(float_side))
  end

  @spec pebble_bound_trig_round_expr?(Types.ir_expr(), Types.compile_env()) :: boolean()
  def pebble_bound_trig_round_expr?(%{op: :call, name: "__mul__", args: [left, right]}, env) do
    pebble_bound_trig_round_mul_side?(left, right, env) or
      pebble_bound_trig_round_mul_side?(right, left, env)
  end

  @spec pebble_bound_trig_round_expr?(Types.ir_expr(), Types.compile_env()) :: boolean()
  def pebble_bound_trig_round_expr?(_expr, _env), do: false

  defp to_float_arg(%{op: :qualified_call, target: target, args: [value]})
       when target in ["Basics.toFloat", "toFloat"],
       do: {:ok, value}

  defp to_float_arg(%{op: :runtime_call, function: "elmc_basics_to_float", args: [value]}),
    do: {:ok, value}

  defp to_float_arg(_expr), do: :error

  defp compile_tuple_int_expr(arg_expr, accessor, env, counter) do
    {arg_code, arg_var, counter} = Host.compile_expr(arg_expr, env, counter)
    {access_code, out, counter} = compile_tuple_int_source(arg_var, accessor, counter)

    code = """
    #{arg_code}
    #{access_code}
      elmc_release(#{arg_var});
    """

    {code, out, counter}
  end

  defp compile_tuple_int_source(source, accessor, counter) do
    next = counter + 1
    tuple_value = "native_tuple_value_#{next}"
    out = "native_tuple_int_#{next}"

    code = """
      ElmcValue *#{tuple_value} = #{accessor}(#{source});
      const elmc_int_t #{out} = elmc_as_int(#{tuple_value});
      elmc_release(#{tuple_value});
    """

    {code, out, next}
  end

  defp tuple_accessor(:tuple_second_expr), do: "elmc_tuple_second"
  defp tuple_accessor(_op), do: "elmc_tuple_first"

  defp pebble_angle_source(%{
         op: :call,
         name: "__fdiv__",
         args: [numerator, %{op: :int_literal, value: 65_536}]
       }),
       do: pebble_angle_numerator_source(numerator)

  defp pebble_angle_source(_expr), do: :error

  defp pebble_angle_numerator_source(%{op: :call, name: "__mul__", args: [left, right]}) do
    cond do
      pi_expr?(left) -> double_to_float_source(right)
      pi_expr?(right) -> double_to_float_source(left)
      true -> :error
    end
  end

  defp pebble_angle_numerator_source(_expr), do: :error

  defp double_to_float_source(%{
         op: :call,
         name: "__mul__",
         args: [left, %{op: :int_literal, value: 2}]
       }),
       do: to_float_arg(left)

  defp double_to_float_source(%{
         op: :call,
         name: "__mul__",
         args: [%{op: :int_literal, value: 2}, right]
       }),
       do: to_float_arg(right)

  defp double_to_float_source(_expr), do: :error

  @spec inline_function(Types.function_decl_key(), [Types.ir_expr()], Types.compile_env(), Types.compile_counter()) ::
          {:ok, String.t(), String.t(), Types.compile_counter()} | :error
  def inline_function(target_key, args, env, counter) do
    decl_map = Map.get(env, :__program_decls__, %{})
    inline_stack = Map.get(env, :__native_int_inline_stack__, MapSet.new())

    with %{args: arg_names, expr: body} when is_list(arg_names) <- Map.get(decl_map, target_key),
         true <- length(arg_names) == length(args),
         false <- MapSet.member?(inline_stack, target_key),
         substituted <- Host.substitute_expr(body, Map.new(Enum.zip(arg_names, args))),
         true <- expr?(substituted, env) do
      env =
        Map.put(
          env,
          :__native_int_inline_stack__,
          MapSet.put(inline_stack, target_key)
        )

      {code, value_ref, counter} = dispatch(substituted, env, counter)
      code = code <> "  // inlined #{format_function_target(target_key)}\n"
      expr = %{op: :call, name: elem(target_key, 1), args: args}

      {code, value_ref, counter} =
        if args == [] do
          Host.maybe_promote_hoisted_native_int(expr, env, code, value_ref, counter)
        else
          {code, value_ref, counter}
        end

      {:ok, code, value_ref, counter}
    else
      _ -> :error
    end
  end

  defp format_function_target({module_name, function_name}), do: "#{module_name}.#{function_name}"

  @spec native_min_max_name(String.t()) :: String.t()
  def native_min_max_name("elmc_basics_min"), do: "min"
  def native_min_max_name("elmc_basics_max"), do: "max"

  @spec native_unary_int_name(String.t()) :: String.t()
  def native_unary_int_name("elmc_basics_abs"), do: "abs"
  def native_unary_int_name("elmc_basics_negate"), do: "negate"

  @spec static_nonzero_int_value(Types.ir_expr()) :: integer() | nil
  def static_nonzero_int_value(%{op: op, value: value})
       when op in [:int_literal, :char_literal] and is_integer(value) and value != 0,
       do: value

  def static_nonzero_int_value(_expr), do: nil

  @spec pi_expr?(Types.ir_expr()) :: boolean()
  defp pi_expr?(%{op: :qualified_call, target: target, args: []})
       when target in ["Basics.pi", "pi"],
       do: true

  defp pi_expr?(%{op: :float_literal, value: value}) when value == 3.141592653589793, do: true
  defp pi_expr?(_expr), do: false

  @spec compile_fallback(Types.ir_expr(), Types.compile_env(), Types.compile_counter()) ::
          Types.native_scalar_compile_result()
  def compile_fallback(expr, env, counter) do
    case Host.hoisted_native_int_lookup(env, expr) do
      {:ok, ref} ->
        {"", ref, counter}

      :error ->
        {code, var, counter} = Host.compile_expr(expr, env, counter)
        next = counter + 1
        out = "native_i_#{next}"

        result =
          {"""
           #{code}
             const elmc_int_t #{out} = elmc_as_int(#{var});
             elmc_release(#{var});
           """, out, next}

        case expr do
          %{op: :call, args: []} ->
            {code, ref, c} = result
            Host.maybe_promote_hoisted_native_int(expr, env, code, ref, c)

          _ ->
            result
        end
    end
  end

  defp compile_dict_get_with_default(default_ref, key, dict, env, counter) do
    {dict_code, dict_var, counter} = Host.compile_expr(dict, env, counter)

    if expr?(key, env) do
      {key_code, key_ref, counter} = compile_expr(key, env, counter)

      {
        key_code <> dict_code,
        "elmc_dict_get_with_default_int(#{default_ref}, #{key_ref}, #{dict_var})",
        dict_var,
        counter
      }
    else
      {key_code, key_var, counter} = Host.compile_expr(key, env, counter)

      {
        key_code <> dict_code,
        "elmc_dict_get_with_default_int_value(#{default_ref}, #{key_var}, #{dict_var})",
        key_var,
        counter
      }
    end
  end
end

