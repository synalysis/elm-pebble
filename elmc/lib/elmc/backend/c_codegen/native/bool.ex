defmodule Elmc.Backend.CCodegen.Native.Bool do
  @moduledoc false

  alias Elmc.Backend.CCodegen.EnvBindings
  alias Elmc.Backend.CCodegen.CSource
  alias Elmc.Backend.CCodegen.Hoist
  alias Elmc.Backend.CCodegen.Host
  alias Elmc.Backend.CCodegen.Native.FunctionCall, as: NativeFunctionCall
  alias Elmc.Backend.CCodegen.Native.RecordFields
  alias Elmc.Backend.CCodegen.Native.TypedReturn
  alias Elmc.Backend.CCodegen.Patterns
  alias Elmc.Backend.CCodegen.PlatformStatic
  alias Elmc.Backend.CCodegen.Types
  alias Elmc.Backend.CCodegen.UnionMacros

  @native_bool_c_type "bool"
  @type compile_result :: Types.native_scalar_compile_result()

  @spec compile_expr(Types.ir_expr(), Types.compile_env(), Types.compile_counter()) ::
          compile_result()
  def compile_expr(expr, env, counter) do
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
    if bool_coercible_branch?(then_expr, env) and bool_coercible_branch?(else_expr, env) do
      {cond_code, cond_ref, counter} = compile_expr(cond_expr, env, counter)
      {then_code, then_ref, counter} = compile_bool_branch(then_expr, env, counter)
      {else_code, else_ref, counter} = compile_bool_branch(else_expr, env, counter)
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
    {code, ref, counter} = compile_expr(value, env, counter)
    {code, "!(#{ref})", counter}
  end

  defp compile_expr_uncached(
         %{op: :case, subject: subject, branches: branches} = expr,
         env,
         counter
       ) do
    if union_constructor_case?(expr) do
      compile_union_constructor_case(subject, branches, env, counter)
    else
      compile_fallback(expr, env, counter)
    end
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
          elmc_release(#{left_var});
          elmc_release(#{right_var});
        """

        {code, out, next}

      union_tag_compare_safe?(operator, left, right, env) ->
        compile_union_tag_compare(left, right, operator, env, counter)

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
                const #{@native_bool_c_type} #{out} = elmc_value_equal(#{left_var}, #{right_var});
                elmc_release(#{left_var});
                elmc_release(#{right_var});
              """

            "__neq__" ->
              """
              #{left_code}
                #{right_code}
                const #{@native_bool_c_type} #{out} = !elmc_value_equal(#{left_var}, #{right_var});
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
                const #{@native_bool_c_type} #{out} = elmc_as_int(#{cmp_var}) #{comparison} 0;
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
      if skip_release?, do: "", else: "  elmc_release(#{var_ref});\n"

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
  def expr?(%{op: :var, name: name}, env) when is_binary(name) or is_atom(name),
    do:
      is_binary(EnvBindings.native_bool_binding(env, name)) or
        EnvBindings.boxed_bool_binding?(env, name) or
        TypedReturn.bool_expr?(%{op: :var, name: name}, env)

  def expr?(%{op: :field_access, arg: arg, field: field}, env),
    do: RecordFields.bool_field?(env, arg, field)

  def expr?(%{op: :if, then_expr: then_expr, else_expr: else_expr}, env),
    do: bool_coercible_branch?(then_expr, env) and bool_coercible_branch?(else_expr, env)

  def expr?(%{op: :runtime_call, function: "elmc_basics_not", args: [value]}, env),
    do: expr?(value, env)

  def expr?(%{op: :case} = expr, _env), do: union_constructor_case?(expr)

  def expr?(expr, env), do: structural_expr?(expr) or TypedReturn.bool_expr?(expr, env)

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
    {code, var, counter} = Host.compile_expr(expr, env, counter)
    next = counter + 1
    out = "native_b_#{next}"

    {
      """
      #{code}
        const #{@native_bool_c_type} #{out} = #{value_expr(expr, env, var)};
        elmc_release(#{var});
      """,
      out,
      next
    }
  end

  @spec value_expr(Types.ir_expr(), Types.compile_env(), String.t()) :: String.t()
  defp value_expr(expr, env, var) do
    if TypedReturn.bool_expr?(expr, env),
      do: "(bool)elmc_as_bool(#{var})",
      else: "elmc_as_int(#{var}) != 0"
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
          elmc_release(#{subject_var});
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
end
