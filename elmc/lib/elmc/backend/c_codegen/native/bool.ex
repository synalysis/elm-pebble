defmodule Elmc.Backend.CCodegen.Native.Bool do
  @moduledoc false

  alias Elmc.Backend.CCodegen.DirectRender.RecordViewPeel
  alias Elmc.Backend.CCodegen.EnvBindings
  alias Elmc.Backend.CCodegen.CSource
  alias Elmc.Backend.CCodegen.Hoist
  alias Elmc.Backend.CCodegen.Host
  alias Elmc.Backend.CCodegen.Native.FunctionCall, as: NativeFunctionCall
  alias Elmc.Backend.CCodegen.Native.RecordFields
  alias Elmc.Backend.CCodegen.Native.TypedReturn
  alias Elmc.Backend.CCodegen.Patterns
  alias Elmc.Backend.CCodegen.PlatformStatic
  alias Elmc.Backend.CCodegen.RecordCompile
  alias Elmc.Backend.CCodegen.RcRuntimeEmit
  alias Elmc.Backend.CCodegen.Util
  alias Elmc.Backend.CCodegen.Types
  alias Elmc.Backend.CCodegen.TypeParsing
  alias Elmc.Backend.CCodegen.UnionMacros
  alias Elmc.Backend.CCodegen.ValueSlots

  @native_bool_c_type "bool"
  @type compile_result :: Types.native_scalar_compile_result()

  @spec compile_expr(Types.ir_expr(), Types.compile_env(), Types.compile_counter()) ::
          compile_result()
  def compile_expr(expr, env, counter) do
    expr = normalize_bool_expr(expr)

    if PlatformStatic.platform_static?(expr) do
      compile_expr_uncached(expr, env, counter)
    else
      case Hoist.hoisted_native_bool_ref(env, expr) do
        ref when is_binary(ref) ->
          {"", ref, counter}

        nil ->
          compile_expr_uncached(expr, env, counter)
      end
    end
  end

  defp compile_expr_uncached(%{op: :var, name: name} = expr, env, counter) do
    case EnvBindings.native_bool_binding(env, name) do
      native_ref when is_binary(native_ref) ->
        {"", native_ref, counter}

      nil ->
        case Map.fetch(env, name) do
          {:ok, source} when is_binary(source) ->
            {"", "(bool)elmc_as_bool(#{source})", counter}

          _ ->
            compile_fallback(expr, env, counter)
        end
    end
  end

  defp compile_expr_uncached(%{op: :field_access, arg: arg, field: field}, env, counter)
       when is_binary(arg) do
    case Map.fetch(env, arg) do
      {:ok, {:record_peel, source_ref, helper_key, helper_call}} ->
        case RecordViewPeel.field_expr(env, arg, field) do
          field_expr when is_map(field_expr) ->
            peel_env = RecordViewPeel.peel_compile_env(env, helper_key, helper_call, source_ref)
            compile_expr(field_expr, peel_env, counter)

          _ ->
            compile_fallback(%{op: :field_access, arg: arg, field: field}, env, counter)
        end

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
            const #{@native_bool_c_type} #{out} = #{getter};
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
          const #{@native_bool_c_type} #{out} = #{getter};
        #{after_probe}
          #{ValueSlots.release_stmt(arg_var)};
        """

        {code, out, next}

      field_expr ->
        compile_env = RecordViewPeel.peel_env_for_field_access(env, arg_expr)
        compile_expr(field_expr, compile_env, counter)
    end
  end

  defp compile_expr_uncached(
         %{op: :if, cond: cond_expr, then_expr: then_expr, else_expr: else_expr} = expr,
         env,
         counter
       ) do
    case PlatformStatic.platform_static_and_if(expr) do
      {:and, macro, polarity, inner_then} ->
        compile_platform_static_and_if(
          macro,
          polarity,
          inner_then,
          %{op: :bool_literal, value: true},
          else_expr,
          env,
          counter
        )

      nil ->
        case PlatformStatic.platform_static_branch(cond_expr) do
          {macro, polarity} ->
            compile_platform_static_if(macro, polarity, then_expr, else_expr, env, counter)

          nil ->
            compile_runtime_bool_if_expr(cond_expr, then_expr, else_expr, env, counter)
        end
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
    cond do
      name in ["&&", "Basics.and", "and"] and match?([_left, _right], args) ->
        [left, right] = args

        compile_expr(
          %{op: :if, cond: left, then_expr: right, else_expr: %{op: :bool_literal, value: false}},
          env,
          counter
        )

      true ->
        module_name = Map.get(env, :__module__, "Main")

        case NativeFunctionCall.compile_scalar(module_name, name, args, env, counter, :native_bool) do
          {code, value_ref, counter} -> {code, value_ref, counter}
          :error -> compile_fallback(expr, env, counter)
        end
    end
  end

  defp compile_expr_uncached(
         %{op: :qualified_call, target: target, args: args} = expr,
         env,
         counter
       ) do
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
    case PlatformStatic.platform_static_branch(value) do
      {macro, polarity} ->
        PlatformStatic.compile_native_bool(macro, PlatformStatic.invert_polarity(polarity), counter)

      nil ->
        {code, ref, counter} = compile_expr(value, env, counter)
        {code, "!(#{ref})", counter}
    end
  end

  defp compile_expr_uncached(
         %{op: :case, subject: subject, branches: branches} = expr,
         env,
         counter
       ) do
    case {union_constructor_case?(expr), PlatformStatic.platform_static_branch(expr)} do
      {true, {macro, polarity}} ->
        PlatformStatic.compile_native_bool(macro, polarity, counter)

      {true, nil} ->
        compile_union_constructor_case(subject, branches, env, counter)

      {false, _} ->
        compile_fallback(expr, env, counter)
    end
  end

  defp compile_expr_uncached(expr, env, counter), do: compile_fallback(expr, env, counter)

  defp compile_runtime_bool_if_expr(cond_expr, then_expr, else_expr, env, counter) do
    if bool_coercible_branch?(then_expr, env) and bool_coercible_branch?(else_expr, env) do
      {cond_code, cond_ref, counter} = compile_expr(cond_expr, env, counter)
      then_env = RecordCompile.fresh_subexpr_cache(env)
      else_env = RecordCompile.fresh_subexpr_cache(env)
      {then_code, then_ref, counter} = compile_bool_branch(then_expr, then_env, counter)
      {else_code, else_ref, counter} = compile_bool_branch(else_expr, else_env, counter)
      next = counter + 1
      out = "native_bool_if_#{next}"

      code = """
      #{cond_code}
        #{@native_bool_c_type} #{out};
        if (#{cond_ref}) {
      #{CSource.indent(then_code, 4)}
          #{out} = #{then_ref};
        } else {
      #{CSource.indent(else_code, 4)}
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

  @spec compile_compare(
          Types.ir_expr(),
          Types.ir_expr(),
          String.t(),
          Types.compile_env(),
          Types.compile_counter()
        ) :: compile_result()
  defp compile_compare(left, right, operator, env, counter) do
    cond do
      list_int_compare_safe?(operator, left, right, env) ->
        {left_code, left_var, counter} = Host.compile_expr(left, env, counter)
        {right_code, right_var, counter} = Host.compile_expr(right, env, counter)
        next = counter + 1
        out = "native_cmp_#{next}"
        negate = if operator == "__neq__", do: "!", else: ""

        code = """
        #{left_code}
          #{right_code}
          const #{@native_bool_c_type} #{out} = #{negate}elmc_list_equal_int(#{left_var}, #{right_var});
          #{RecordCompile.release_compare_operand(env, left_var)};
          #{RecordCompile.release_compare_operand(env, right_var)};
        """

        {code, out, next}

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

        case {Util.parse_compile_time_int_ref(left_ref), Util.parse_compile_time_int_ref(right_ref)} do
          {left_value, right_value} when is_integer(left_value) and is_integer(right_value) ->
            result = if apply_native_compare(operator, left_value, right_value), do: "1", else: "0"
            {CSource.join_fragments([left_code, right_code]), result, counter}

          _ ->
            comparison =
              case operator do
                "__eq__" -> "=="
                "__neq__" -> "!="
                "__lt__" -> "<"
                "__lte__" -> "<="
                "__gt__" -> ">"
                "__gte__" -> ">="
              end

            {CSource.join_fragments([left_code, right_code]), "(#{left_ref} #{comparison} #{right_ref})",
             counter}
        end

      boxed_int_literal_compare_safe?(operator, left, right, env) ->
        compile_boxed_int_literal_compare(left, right, operator, env, counter)

      union_tag_compare_safe?(operator, left, right, env) ->
        compile_union_tag_compare(left, right, operator, env, counter)

      maybe_field_vs_nothing_compare_safe?(operator, left, right, env) ->
        compile_maybe_field_vs_nothing_compare(left, right, operator, env, counter)

      true ->
        operand_env = RcRuntimeEmit.operand_env(env)

        {left_code, left_var, counter} = compile_compare_operand(left, operand_env, env, counter)
        {right_code, right_var, counter} = compile_compare_operand(right, operand_env, env, counter)
        left_ref = RcRuntimeEmit.value_expr(left_var)
        right_ref = RcRuntimeEmit.value_expr(right_var)
        next = counter + 1
        out = "native_cmp_#{next}"

        {code, final_counter} =
          case operator do
            "__eq__" ->
              {"""
              #{left_code}
                #{right_code}
                const #{@native_bool_c_type} #{out} = elmc_value_equal(#{left_ref}, #{right_ref});
                #{join_compare_releases(env, [left_var, right_var])}
              """, next}

            "__neq__" ->
              {"""
              #{left_code}
                #{right_code}
                const #{@native_bool_c_type} #{out} = !elmc_value_equal(#{left_ref}, #{right_ref});
                #{join_compare_releases(env, [left_var, right_var])}
              """, next}

            _ ->
              {cmp_var, cmp_counter} = RcRuntimeEmit.compare_order_slot(env, next)

              comparison =
                case operator do
                  "__lt__" -> "<"
                  "__lte__" -> "<="
                  "__gt__" -> ">"
                  "__gte__" -> ">="
                end

              compare_code =
                if RcRuntimeEmit.rc_allocator_emit_mode?(env) do
                  """
                  #{RcRuntimeEmit.assign_call(env, cmp_var, "elmc_basics_compare", RcRuntimeEmit.call_arg_list([left_var, right_var]))}
                  const #{@native_bool_c_type} #{out} = elmc_as_int(#{cmp_var}) #{comparison} 0;
                  """
                else
                  """
                  ElmcValue *#{cmp_var} = elmc_basics_compare_take(#{RcRuntimeEmit.call_arg_list([left_var, right_var])});
                  const #{@native_bool_c_type} #{out} = elmc_as_int(#{cmp_var}) #{comparison} 0;
                  """
                end

              {"""
              #{left_code}
                #{right_code}
                #{compare_code}\
                #{join_compare_releases(env, [cmp_var, left_var, right_var])}
              """, cmp_counter}
          end

        {code, out, final_counter}
    end
  end

  @spec compare_safe?(String.t(), Types.ir_expr(), Types.ir_expr(), Types.compile_env()) ::
          boolean()
  defp compare_safe?(operator, left, right, env)
       when operator in ["__eq__", "__neq__"] do
    expr?(left, env) and expr?(right, env)
  end

  defp compare_safe?(_operator, _left, _right, _env), do: false

  defp boxed_int_literal_compare_safe?(operator, left, %{op: :int_literal, value: _}, env)
       when operator in ["__eq__", "__neq__", "__lt__", "__lte__", "__gt__", "__gte__"] do
    boxed_int_compare_operand?(left, env)
  end

  defp boxed_int_literal_compare_safe?(_operator, _left, _right, _env), do: false

  defp boxed_int_compare_operand?(%{op: :var, name: name}, env) when is_binary(name) or is_atom(name) do
    cond do
      EnvBindings.native_int_binding?(env, name) ->
        false

      EnvBindings.function_int_param?(env, name) ->
        false

      union_or_enum_var?(name, env) ->
        false

      EnvBindings.boxed_int_binding?(env, name) ->
        true

      TypedReturn.expr_type(%{op: :var, name: name}, env) == "Int" ->
        true

      true ->
        false
    end
  end

  defp boxed_int_compare_operand?(
         %{op: :runtime_call, function: function, args: [_]},
         _env
       )
       when function in [
              "elmc_maybe_or_tuple_just_payload",
              "elmc_maybe_or_tuple_just_payload_borrow"
            ],
       do: true

  defp boxed_int_compare_operand?(_expr, _env), do: false

  defp union_or_enum_var?(name, env) when is_binary(name) or is_atom(name) do
    case TypedReturn.expr_type(%{op: :var, name: name}, env) do
      type when is_binary(type) ->
        TypeParsing.enum_type?(type) or String.starts_with?(type, "Union ")

      _ ->
        false
    end
  end

  defp compile_boxed_int_literal_compare(left, %{op: :int_literal, value: right_lit}, operator, env, counter) do
    {left_code, left_var, counter} = Host.compile_expr(left, env, counter)
    next = counter + 1
    out = "native_cmp_#{next}"

    code = """
    #{left_code}
      const #{@native_bool_c_type} #{out} = elmc_as_int(#{left_var}) #{compare_operator_c(operator)} #{right_lit};
      #{RecordCompile.release_compare_operand(env, left_var)}
    """

    {code, out, next}
  end

  defp compare_operator_c("__eq__"), do: "=="
  defp compare_operator_c("__neq__"), do: "!="
  defp compare_operator_c("__lt__"), do: "<"
  defp compare_operator_c("__lte__"), do: "<="
  defp compare_operator_c("__gt__"), do: ">"
  defp compare_operator_c("__gte__"), do: ">="

  defp list_int_compare_safe?(operator, left, right, env)
       when operator in ["__eq__", "__neq__"] do
    TypedReturn.list_int_expr?(left, env) and TypedReturn.list_int_expr?(right, env)
  end

  defp list_int_compare_safe?(_operator, _left, _right, _env), do: false

  defp union_tag_compare_safe?(operator, left, right, env)
       when operator in ["__eq__", "__neq__"] do
    union_tag_compare_pair(left, right, env) != :error or
      union_tag_compare_pair(right, left, env) != :error
  end

  defp union_tag_compare_safe?(_operator, _left, _right, _env), do: false

  defp compile_union_tag_compare(left, right, operator, env, counter) do
    case union_tag_compare_pair(left, right, env) do
      :error ->
        {:ok, var_code, var_ref, tag_ref, skip_release?} =
          union_tag_compare_pair(right, left, env)

        build_union_tag_compare(var_code, var_ref, tag_ref, skip_release?, operator, counter)

      {:ok, var_code, var_ref, tag_ref, skip_release?} ->
        build_union_tag_compare(var_code, var_ref, tag_ref, skip_release?, operator, counter)
    end
  end

  defp build_union_tag_compare(var_code, var_ref, tag_ref, skip_release?, operator, counter) do
    next = counter + 1
    out = "native_cmp_#{next}"
    cmp = if operator == "__eq__", do: "==", else: "!="
    negate = if operator == "__neq__", do: "!", else: ""

    release =
      if skip_release?, do: "", else: "  " <> ValueSlots.release_stmt(var_ref) <> "\n"

    code =
      var_code <>
        "  const #{@native_bool_c_type} #{out} = #{negate}(elmc_as_int(#{var_ref}) #{cmp} #{tag_ref});\n" <>
        release

    {code, out, next}
  end

  defp union_tag_compare_pair(
         %{op: :var, name: var_name},
         %{op: :int_literal, union_ctor: _} = literal,
         env
       ) do
    with tag_ref when is_binary(tag_ref) <- UnionMacros.literal_ref(literal, env),
         {:ok, var_code, var_ref, skip_release?} <- union_compare_var(var_name, env) do
      {:ok, var_code, var_ref, tag_ref, skip_release?}
    else
      _ -> :error
    end
  end

  defp union_tag_compare_pair(_, _, _), do: :error

  defp union_compare_var(name, env) do
    case EnvBindings.lookup_binding(env, name) do
      ref when is_binary(ref) and ref != "" ->
        if union_compare_var_ref?(ref) do
          {:ok, "", ref, true}
        else
          :error
        end

      _ ->
        :error
    end
  end

  defp union_compare_var_ref?(ref) do
    Regex.match?(~r/^[A-Za-z_][A-Za-z0-9_]*$/, ref)
  end

  @spec expr?(Types.ir_expr(), Types.compile_env()) :: boolean()
  def expr?(expr, env), do: expr?(normalize_bool_expr(expr), env, :normalized)

  defp expr?(%{op: :var, name: name}, env, :normalized) when is_binary(name) or is_atom(name),
    do:
      is_binary(EnvBindings.native_bool_binding(env, name)) or
        EnvBindings.boxed_bool_binding?(env, name) or
        TypedReturn.bool_expr?(%{op: :var, name: name}, env)

  defp expr?(%{op: :field_access, arg: arg, field: field}, env, :normalized),
    do: RecordFields.bool_field?(env, arg, field)

  defp expr?(%{op: :if, then_expr: then_expr, else_expr: else_expr}, env, :normalized),
    do: bool_coercible_branch?(then_expr, env) and bool_coercible_branch?(else_expr, env)

  defp expr?(%{op: :runtime_call, function: "elmc_basics_not", args: [value]}, env, :normalized),
    do: expr?(value, env)

  defp expr?(%{op: :case} = expr, _env, :normalized), do: union_constructor_case?(expr)

  defp expr?(expr, env, :normalized),
    do: structural_expr?(expr) or TypedReturn.bool_expr?(expr, env)

  defp normalize_bool_expr(%{op: :qualified_call, target: target, args: args}) do
    case Host.special_value_from_target(Host.normalize_special_target(target), args) do
      nil -> %{op: :qualified_call, target: target, args: args}
      rewritten -> normalize_bool_expr(rewritten)
    end
  end

  defp normalize_bool_expr(%{op: :call, name: name, args: args}) when is_binary(name) do
    case Host.special_value_from_target(name, args) do
      nil -> %{op: :call, name: name, args: args}
      rewritten -> normalize_bool_expr(rewritten)
    end
  end

  defp normalize_bool_expr(expr), do: expr

  defp maybe_field_vs_nothing_compare_safe?(operator, left, right, env)
       when operator in ["__eq__", "__neq__"] do
    (maybe_nothing_literal?(right) and maybe_maybe_expr?(left, env)) or
      (maybe_nothing_literal?(left) and maybe_maybe_expr?(right, env))
  end

  defp maybe_field_vs_nothing_compare_safe?(_operator, _left, _right, _env), do: false

  defp maybe_nothing_literal?(%{op: :int_literal, union_ctor: ctor}) when is_binary(ctor),
    do: String.ends_with?(ctor, ".Nothing") or ctor == "Nothing"

  defp maybe_nothing_literal?(%{op: :constructor_call, target: target}) when is_binary(target),
    do: String.ends_with?(target, ".Nothing") or target in ["Nothing", "::"]

  defp maybe_nothing_literal?(_expr), do: false

  defp maybe_maybe_expr?(%{op: :field_access, arg: arg, field: field}, env) do
    maybe_type?(RecordFields.field_type(env, arg, field))
  end

  defp maybe_maybe_expr?(%{op: :var, name: name}, env) when is_binary(name) do
    maybe_type?(Map.get(Map.get(env, :__var_types__, %{}), name))
  end

  defp maybe_maybe_expr?(_expr, _env), do: false

  defp maybe_type?(type) when is_binary(type), do: String.starts_with?(type, "Maybe ")
  defp maybe_type?(_), do: false

  defp compile_maybe_field_vs_nothing_compare(left, right, operator, env, counter) do
    maybe_expr =
      cond do
        maybe_maybe_expr?(left, env) -> left
        maybe_maybe_expr?(right, env) -> right
        true -> left
      end

    {left_code, left_var, counter} = Host.compile_expr(maybe_expr, env, counter)
    next = counter + 1
    out = "native_maybe_#{next}"

    is_just =
      "(#{left_var}) && (#{left_var})->tag == ELMC_TAG_MAYBE && (#{left_var})->payload != NULL && " <>
        "((ElmcMaybe *)(#{left_var})->payload)->is_just"

    bool_expr =
      case operator do
        "__eq__" -> "!(#{is_just})"
        "__neq__" -> is_just
      end

    code = """
    #{left_code}
      const #{@native_bool_c_type} #{out} = #{bool_expr};
      #{ValueSlots.release_stmt_line(left_var)}
    """

    {code, out, next}
  end

  @spec structural_expr?(Types.ir_expr()) :: boolean()
  def structural_expr?(%{op: :compare}), do: true

  def structural_expr?(%{op: :case} = expr), do: union_constructor_case?(expr)

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

  @spec bool_coercible_branch?(Types.ir_expr(), Types.compile_env()) :: boolean()
  defp bool_coercible_branch?(%{op: :bool_literal}, _env), do: true

  defp bool_coercible_branch?(%{op: :int_literal, value: value}, _env) when value in [0, 1],
    do: true

  defp bool_coercible_branch?(%{op: :constructor_call, target: target, args: []}, _env),
    do: match?({:ok, _}, constructor_bool_literal(target))

  defp bool_coercible_branch?(expr, env), do: expr?(expr, env)

  @spec compile_bool_branch(
          Types.ir_expr(),
          Types.compile_env(),
          Types.compile_counter()
        ) :: compile_result()
  defp compile_bool_branch(%{op: :bool_literal, value: value}, _env, counter),
    do: {"", if(value, do: "true", else: "false"), counter}

  defp compile_bool_branch(%{op: :int_literal, value: 1}, _env, counter),
    do: {"", "true", counter}

  defp compile_bool_branch(%{op: :int_literal, value: 0}, _env, counter),
    do: {"", "false", counter}

  defp compile_bool_branch(%{op: :constructor_call, target: target, args: []}, env, counter) do
    case constructor_bool_literal(target) do
      {:ok, true} -> {"", "true", counter}
      {:ok, false} -> {"", "false", counter}
      :error -> compile_expr(%{op: :constructor_call, target: target, args: []}, env, counter)
    end
  end

  defp compile_bool_branch(expr, env, counter), do: compile_expr(expr, env, counter)

  @spec constructor_bool_literal(String.t()) :: {:ok, boolean()} | :error
  defp constructor_bool_literal(target) when is_binary(target) do
    case Host.special_value_from_target(target, []) do
      %{op: :bool_literal, value: value} -> {:ok, value}
      %{op: :int_literal, value: 1} -> {:ok, true}
      %{op: :int_literal, value: 0} -> {:ok, false}
      _ -> :error
    end
  end

  @spec compile_fallback(Types.ir_expr(), Types.compile_env(), Types.compile_counter()) ::
          compile_result()
  defp compile_fallback(expr, env, counter) do
    operand_env = RcRuntimeEmit.operand_env(env)

    {compile_env, counter} =
      if RcRuntimeEmit.rc_allocator_emit_mode?(env) do
        {out, next} = RcRuntimeEmit.compile_result_slot(operand_env, counter)

        branch_env =
          operand_env
          |> Map.put(:__branch_out__, out)
          |> Map.put(:__declared_outs__, MapSet.new([out]))

        {branch_env, next}
      else
        {operand_env, counter}
      end

    {code, var, counter} = Host.compile_expr(expr, compile_env, counter)
    next = counter + 1
    out = "native_b_#{next}"

    {
      """
      #{code}
        const #{@native_bool_c_type} #{out} = #{value_expr(expr, env, var)};
        #{release_native_bool_operand(var)}
      """,
      out,
      next
    }
  end

  defp release_native_bool_operand(var) do
    if native_bool_c_ref?(var), do: "", else: ValueSlots.release_stmt_line(var)
  end

  @spec value_expr(Types.ir_expr(), Types.compile_env(), String.t()) :: String.t()
  defp value_expr(expr, env, var) do
    cond do
      native_bool_c_ref?(var) ->
        var

      TypedReturn.bool_expr?(expr, env) ->
        "(bool)elmc_as_bool(#{RcRuntimeEmit.value_expr(var)})"

      true ->
        "elmc_as_int(#{RcRuntimeEmit.value_expr(var)}) != 0"
    end
  end

  defp native_bool_c_ref?(var) when is_binary(var) do
    Regex.match?(~r/^(native_b_|native_bool_|list_hof_result_)\d+$/, var)
  end

  defp union_constructor_case?(%{op: :case, branches: branches}) do
    case branches do
      [
        %{pattern: %{kind: :constructor, tag: tag}, expr: %{op: :int_literal, value: 1}},
        %{pattern: %{kind: :wildcard}, expr: %{op: :int_literal, value: 0}}
      ]
      when is_integer(tag) ->
        true

      _ ->
        false
    end
  end

  defp union_constructor_case?(_expr), do: false

  defp compile_platform_static_and_if(macro, polarity, inner_then, then_expr, else_expr, env, counter) do
    then_env = RecordCompile.fresh_subexpr_cache(env)
    else_env = RecordCompile.fresh_subexpr_cache(env)
    {then_code, then_ref, counter} = compile_bool_branch(then_expr, then_env, counter)
    {else_code, else_ref, counter} = compile_bool_branch(else_expr, else_env, counter)

    {round_guard, _} =
      case polarity do
        :when_defined -> {"!defined(#{macro})", "defined(#{macro})"}
        :when_not_defined -> {"defined(#{macro})", "!defined(#{macro})"}
      end

    {inner_code, inner_ref, counter} = compile_expr(inner_then, env, counter)
    next = counter + 1
    out = "native_bool_if_#{next}"

    code = """
    #{then_code}#{else_code}  #if #{round_guard}
      const #{@native_bool_c_type} #{out} = #{else_ref};
    #else
    #{inner_code}    const #{@native_bool_c_type} #{out} = (#{inner_ref}) ? #{then_ref} : #{else_ref};
    #endif
    """

    {code, out, next}
  end

  defp compile_platform_static_if(macro, polarity, then_expr, else_expr, env, counter) do
    then_env = RecordCompile.fresh_subexpr_cache(env)
    else_env = RecordCompile.fresh_subexpr_cache(env)
    {then_code, then_ref, counter} = compile_bool_branch(then_expr, then_env, counter)
    {else_code, else_ref, counter} = compile_bool_branch(else_expr, else_env, counter)

    {round_guard, _} =
      case polarity do
        :when_defined -> {"!defined(#{macro})", "defined(#{macro})"}
        :when_not_defined -> {"defined(#{macro})", "!defined(#{macro})"}
      end

    next = counter + 1
    out = "native_bool_if_#{next}"

    code = """
    #{else_code}  #if #{round_guard}
      const #{@native_bool_c_type} #{out} = #{else_ref};
    #else
    #{then_code}    const #{@native_bool_c_type} #{out} = #{then_ref};
    #endif
    """

    {code, out, next}
  end

  defp compile_union_constructor_case(subject, branches, env, counter) do
    [%{pattern: pattern} | _] = branches

    case Host.record_get_borrow_expr(subject, env) do
      borrow_ref when is_binary(borrow_ref) ->
        next = counter + 1
        out = "native_b_#{next}"
        {bind_code, subject_ref} = maybe_bind_borrowed_subject(borrow_ref, next)
        condition = Patterns.pattern_condition(subject_ref, pattern)

        code = """
        #{bind_code}
          const #{@native_bool_c_type} #{out} = #{condition};
        """

        {code, out, next}

      nil ->
        {subject_code, subject_var, counter} = Host.compile_expr(subject, env, counter)
        next = counter + 1
        out = "native_b_#{next}"
        condition = Patterns.pattern_condition(subject_var, pattern)

        code = """
        #{subject_code}
          const #{@native_bool_c_type} #{out} = #{condition};
          #{ValueSlots.release_stmt_line(subject_var)}
        """

        {code, out, next}
    end
  end

  defp maybe_bind_borrowed_subject(ref, next) do
    if complex_borrow_ref?(ref) do
      subject_ref = "native_union_subject_#{next}"
      {"  ElmcValue *#{subject_ref} = #{ref};", subject_ref}
    else
      {"", ref}
    end
  end

  defp complex_borrow_ref?(ref) when is_binary(ref) do
    String.contains?(ref, "(") or String.contains?(ref, "->")
  end

  defp join_compare_releases(env, vars) when is_list(vars) do
    vars
    |> Enum.map(&RecordCompile.release_compare_operand(env, &1))
    |> Enum.reject(&(&1 == ""))
    |> case do
      [] -> ""
      lines -> Enum.map_join(lines, "\n", & &1) <> "\n"
    end
  end

  defp compile_compare_operand(expr, operand_env, env, counter) do
    if RcRuntimeEmit.rc_allocator_emit_mode?(env) do
      {slot, next} = RcRuntimeEmit.compile_result_slot(operand_env, counter)

      branch_env =
        operand_env
        |> Map.put(:__branch_out__, slot)
        |> Map.put(:__declared_outs__, MapSet.new([slot]))

      {code, ref, final_counter} = Host.compile_expr(expr, branch_env, next)
      ref = ValueSlots.resolve_result_slot(ref)

      {code, var, final_counter} =
        cond do
          ref == slot ->
            {code, slot, final_counter}

          ValueSlots.owned_ref?(ref) ->
            {code, ref, final_counter}

          true ->
            transfer = RcRuntimeEmit.transfer_assignment(slot, ref)

            {code <> "\n  " <> transfer, slot, final_counter}
        end

      {code, var, final_counter}
    else
      Host.compile_expr(expr, operand_env, counter)
    end
  end

  defp apply_native_compare("__eq__", left, right), do: left == right
  defp apply_native_compare("__neq__", left, right), do: left != right
  defp apply_native_compare("__lt__", left, right), do: left < right
  defp apply_native_compare("__lte__", left, right), do: left <= right
  defp apply_native_compare("__gt__", left, right), do: left > right
  defp apply_native_compare("__gte__", left, right), do: left >= right
  defp apply_native_compare(_, _left, _right), do: false
end
