defmodule Elmc.Backend.CCodegen.RecordCompile do
  @moduledoc false

  alias Elmc.Backend.CCodegen.BuiltinUnion
  alias Elmc.Backend.CCodegen.DebugProbes
  alias Elmc.Backend.CCodegen.CSource
  alias Elmc.Backend.CCodegen.EnvBindings
  alias Elmc.Backend.CCodegen.Expr
  alias Elmc.Backend.CCodegen.FunctionCallCompile
  alias Elmc.Backend.CCodegen.Host
  alias Elmc.Backend.CCodegen.CaseCompile
  alias Elmc.Backend.CCodegen.OwnershipTransfer
  alias Elmc.Backend.CCodegen.RcRuntimeEmit
  alias Elmc.Backend.CCodegen.Native.RecordFields
  alias Elmc.Backend.CCodegen.Types
  alias Elmc.Backend.CCodegen.Util
  alias Elmc.Backend.CCodegen.ValueSlots
  alias Elmc.Backend.CCodegen.VarAnalysis

  @uncached_compile &Host.compile_expr/3

  @spec with_subexpr_cache(Types.compile_env()) :: Types.compile_env()
  def with_subexpr_cache(env), do: field_subexpr_cache_env(env)

  @spec fresh_subexpr_cache(Types.compile_env()) :: Types.compile_env()
  def fresh_subexpr_cache(env) do
    if subexpr_cache_active?(env) do
      env
      |> Map.delete(:__subexpr_cache_key__)
      |> field_subexpr_cache_env()
    else
      env
    end
  end

  @spec subexpr_cache_active?(Types.compile_env()) :: boolean()
  def subexpr_cache_active?(env) when is_map(env) do
    Map.has_key?(env, :__subexpr_cache__) or
      Map.has_key?(env, :__subexpr_cache_key__) or
      Map.has_key?(env, :__record_subexpr_cache_key__)
  end

  @spec cacheable_subexpr?(Types.ir_expr()) :: boolean()
  def cacheable_subexpr?(%{op: :qualified_call, args: []}), do: true
  def cacheable_subexpr?(%{op: :call, args: []}), do: true
  def cacheable_subexpr?(%{op: :constructor_call, args: []}), do: true
  def cacheable_subexpr?(_), do: false

  @spec compile_expr_cached(
          Types.ir_expr(),
          Types.compile_env(),
          Types.compile_counter(),
          (Types.ir_expr(), Types.compile_env(), Types.compile_counter() -> Types.compile_result())
        ) :: {String.t(), String.t(), Types.compile_counter(), Types.compile_env()}
  def compile_expr_cached(expr, env, counter, compile_fn \\ @uncached_compile) do
    compile_cached_expr(expr, env, counter, compile_fn)
  end

  @spec compile(Types.ir_record_expr(), Types.compile_env(), Types.compile_counter()) ::
          Types.compile_result()
  def compile(%{op: :record_literal, fields: fields}, env, counter) do
    compile_literal(fields, env, counter)
  end

  def compile(%{op: :record_update, base: base, fields: fields}, env, counter) do
    compile_update(base, fields, env, counter)
  end

  def compile(%{op: :field_access} = expr, env, counter) do
    if subexpr_cache_active?(env) do
      {code, ref, counter, _env} = compile_cached_expr(expr, env, counter, @uncached_compile)
      {code, ref, counter}
    else
      compile_field_access(expr, env, counter)
    end
  end

  def compile(
        %{op: :field_call, arg: %{op: :var, name: name}, field: field, args: args},
        env,
        counter
      )
      when is_binary(name) do
    compile(%{op: :field_call, arg: name, field: field, args: args}, env, counter)
  end

  def compile(%{op: :field_call, arg: arg, field: field, args: args}, env, counter)
      when is_binary(arg) do
    compile_field_call_var(arg, field, args, env, counter)
  end

  def compile(%{op: :field_call, arg: arg_expr, field: field, args: args}, env, counter)
      when is_map(arg_expr) and is_list(args) and args != [] do
    {arg_code, record_var, counter} = Host.compile_expr(arg_expr, env, counter)
    {call_code, out, counter} = compile_bound_field_call(record_var, field, args, env, counter)
    {arg_code <> call_code, out, counter}
  end

  def compile(%{op: :field_call, arg: arg, field: field, args: args}, env, counter)
      when args in [nil, []] do
    compile(%{op: :field_access, arg: arg, field: field}, env, counter)
  end

  defp compile_field_access(%{op: :field_access, arg: arg, field: field}, env, counter)
       when is_binary(arg) do
    compile_field_access_var(arg, field, env, counter)
  end

  defp compile_field_access(
         %{op: :field_access, arg: %{op: :record_literal, fields: fields}, field: field},
         env,
         counter
       )
       when is_list(fields) do
    compile_field_access_literal(fields, field, env, counter)
  end

  defp compile_field_access(
         %{op: :field_access, arg: %{op: :var, name: name}, field: field},
         env,
         counter
       ) do
    compile_field_access_bound_var(name, field, env, counter)
  end

  defp compile_field_access(%{op: :field_access, arg: arg_expr, field: field}, env, counter)
       when is_map(arg_expr) do
    compile_field_access_expr(arg_expr, field, env, counter)
  end

  @spec compile_literal(Types.ir_record_fields(), Types.compile_env(), Types.compile_counter()) ::
          Types.compile_result()
  defp compile_literal(fields, env, counter) do
    ordered_fields = canonicalize_literal_fields(fields, env)
    field_count = length(ordered_fields)

    if field_count > 0 and native_int_record_literal?(ordered_fields, env) do
      compile_native_int_literal(ordered_fields, field_count, env, counter)
    else
      compile_boxed_literal(ordered_fields, field_count, env, counter)
    end
  end

  @spec compile_native_int_literal(
          Types.ir_record_fields(),
          non_neg_integer(),
          Types.compile_env(),
          Types.compile_counter()
        ) :: Types.compile_result()
  defp compile_native_int_literal(ordered_fields, field_count, env, counter) do
    {field_code, field_refs, counter, post_release} =
      compile_field_exprs(ordered_fields, env, counter, &Host.compile_native_int_expr/3)

    suffix = counter + 1
    {out, bind_counter, declare_out?} = CaseCompile.result_out_binding(env, suffix)
    next = CaseCompile.advance_counter_past_out(bind_counter, out, declare_out?)
    values_array = Enum.join(field_refs, ", ")
    values_decl = "elmc_int_t rec_values_#{suffix}[#{field_count}] = { #{values_array} };"
    names = Enum.map(ordered_fields, & &1.name)
    use_named? = Process.get(:elmc_named_record_literals, false) and field_count > 0

    alloc =
      if use_named? do
        names_array =
          names
          |> Enum.map_join(", ", fn name -> "\"#{Util.escape_c_string(name)}\"" end)

        """
        const char *rec_names_#{suffix}[#{max(field_count, 1)}] = { #{names_array} };
        #{RcRuntimeEmit.assign_call(env, out, "elmc_record_new_static_ints",
          "#{field_count}, rec_names_#{suffix}, rec_values_#{suffix}"
        )}
        """
      else
        RcRuntimeEmit.assign_call(env, out, "elmc_record_new_values_ints",
          "#{field_count}, rec_values_#{suffix}"
        )
      end

    code =
      """
      #{field_code}
        #{values_decl}
        #{alloc}
      """ <> post_release

    :ok = put_literal_record_meta(out, ordered_fields, env)

    {code, out, next}
  end

  @spec compile_boxed_literal(
          Types.ir_record_fields(),
          non_neg_integer(),
          Types.compile_env(),
          Types.compile_counter()
        ) :: Types.compile_result()
  defp compile_boxed_literal(ordered_fields, field_count, env, counter) do
    env = Map.put(env, :__owned_list_result__, true)

    case maybe_extract_boxed_record_literal_helper(
           ordered_fields,
           field_count,
           env,
           counter
         ) do
      {:ok, code, out, counter} ->
        {code, out, counter}

      :error ->
        compile_inline_boxed_literal(ordered_fields, field_count, env, counter)
    end
  end

  defp compile_inline_boxed_literal(ordered_fields, field_count, env, counter) do
    {field_code, field_refs, counter, post_release} =
      compile_field_exprs(ordered_fields, env, counter, &compile_boxed_field_value_expr/3)

    {out, next, _} = CaseCompile.result_out_binding(env, counter)
    values_array = record_values_array(field_refs)
    nulls = ValueSlots.transfer_and_null_refs(unique_field_refs(field_refs))
    names = Enum.map(ordered_fields, & &1.name)
    _type_name = Expr.record_type_for_field_names(names, env)
    use_named? = Process.get(:elmc_named_record_literals, false) and field_count > 0

    {names_decl, allocator} =
      if use_named? do
        names_array =
          names
          |> Enum.map_join(", ", fn name -> "\"#{Util.escape_c_string(name)}\"" end)

        alloc =
          RcRuntimeEmit.assign_call(env, out, "elmc_record_new_static_take",
            "#{field_count}, rec_names_#{next}, rec_values_#{next}"
          )

        {
          "const char *rec_names_#{next}[#{max(field_count, 1)}] = { #{names_array} };",
          alloc
        }
      else
        alloc =
          RcRuntimeEmit.assign_call(env, out, "elmc_record_new_values_take",
            "#{field_count}, rec_values_#{next}"
          )

        {"", alloc}
      end

    code =
      """
      #{field_code}
        #{names_decl}
        ElmcValue *rec_values_#{next}[#{max(field_count, 1)}] = { #{values_array} };
        #{allocator}
        #{nulls}
      """ <> post_release

    :ok = put_literal_record_meta(out, ordered_fields, env)

    {code, out, next}
  end

  defp record_values_array(field_refs) do
    field_refs
    |> Enum.with_index()
    |> Enum.map_join(", ", fn {ref, idx} ->
      prior = Enum.take(field_refs, idx)

      if ref in prior do
        "elmc_retain(#{ref})"
      else
        ref
      end
    end)
  end

  defp put_literal_record_meta(var, ordered_fields, env) do
    names = Enum.map(ordered_fields, & &1.name)
    type = Expr.record_type_for_field_names(names, env)
    shape = if is_binary(type), do: Expr.record_shape_for_type(type, env), else: names
    Expr.put_subexpr_record_meta(var, %{type: type, shape: shape})
  end

  defp unique_field_refs(field_refs) do
    field_refs
    |> Enum.with_index()
    |> Enum.flat_map(fn {ref, idx} ->
      prior = Enum.take(field_refs, idx)
      if ref in prior, do: [], else: [ref]
    end)
  end

  defp remap_literal_fields(ordered_fields, canonical_names) do
    fields = Enum.map(canonical_names, fn name -> Enum.find(ordered_fields, &(&1.name == name)) end)

    if Enum.all?(fields, &is_map/1), do: {:ok, fields}, else: :error
  end

  defp native_int_record_literal?(ordered_fields, env) when is_list(ordered_fields) do
    Enum.all?(ordered_fields, &Host.native_int_expr?(&1.expr, env)) and
      native_int_record_field_types?(ordered_fields, env)
  end

  defp native_int_record_field_types?(ordered_fields, env) when is_list(ordered_fields) do
    names = Enum.map(ordered_fields, & &1.name)

    case Expr.record_type_for_field_names(names, env) do
      type when is_binary(type) ->
        field_types = record_field_types_for_type(type, env)

        is_map(field_types) and
          Enum.all?(ordered_fields, fn %{name: name} ->
            field_type = Map.get(field_types, name) || Map.get(field_types, to_string(name))
            field_type == "Int"
          end)

      _ ->
        false
    end
  end

  defp record_field_types_for_type(type, env) when is_binary(type) do
    module = Map.get(env, :__module__, "Main")
    type_name = Host.normalize_type_name(type)

    types_map =
      Map.get(env, :__record_field_types__) ||
        Process.get(:elmc_record_field_types, %{})

    Map.get(types_map, {module, type_name}) ||
      Map.get(types_map, {module, type})
  end

  defp canonicalize_literal_fields(ordered_fields, env) when is_list(ordered_fields) do
    names = Enum.map(ordered_fields, & &1.name)

    case Expr.record_type_for_field_names(names, env) do
      nil ->
        ordered_fields

      type ->
        case Expr.record_shape_for_type(type, env) do
          nil ->
            ordered_fields

          canonical_names ->
            case remap_literal_fields(ordered_fields, canonical_names) do
              {:ok, fields} -> fields
              :error -> ordered_fields
            end
        end
    end
  end

  defp maybe_extract_boxed_record_literal_helper(
         ordered_fields,
         field_count,
         env,
         counter
       ) do
    if extract_boxed_record_literal_helper?(field_count) do
      case record_literal_helper_params(ordered_fields, env) do
        {:ok, params} ->
          helper_id = Process.get(:elmc_generic_helper_counter, 0) + 1
          Process.put(:elmc_generic_helper_counter, helper_id)

          helper_name =
            "elmc_record_literal_helper_#{Util.safe_c_suffix(Map.get(env, :__module__, "Main"))}_#{Util.safe_c_suffix(Map.get(env, :__function_name__, "fn"))}_#{helper_id}"

          helper_param_decls =
            params
            |> Enum.map_join(", ", fn
              {_key, c_ref, :boxed} -> "ElmcValue *#{c_ref}"
              {_key, c_ref, :native_int} -> "elmc_int_t #{c_ref}"
              {_key, c_ref, :native_bool} -> "bool #{c_ref}"
            end)

          helper_env = env |> Map.put(:__rc_catch__, false) |> Map.put(:__rc_required__, false)

          {field_code, field_vars, _counter} =
            Enum.reduce(ordered_fields, {"", [], counter}, fn field, {code_acc, vars_acc, c} ->
              {code, var, c2} = Host.compile_expr(field.expr, helper_env, c)
              {code_acc <> "\n  " <> code, vars_acc ++ [{field.name, var}], c2}
            end)

          values_array = field_vars |> Enum.map(fn {_name, var} -> var end) |> Enum.join(", ")
          use_named? = Process.get(:elmc_named_record_literals, false) and field_count > 0

          record_return =
            if use_named? do
              names_array =
                ordered_fields
                |> Enum.map_join(", ", fn field -> "\"#{Util.escape_c_string(field.name)}\"" end)

              """
                const char *rec_names[#{field_count}] = { #{names_array} };
                return elmc_record_new_static_take_value(#{field_count}, rec_names, rec_values);
              """
            else
              "return elmc_record_new_values_take_value(#{field_count}, rec_values);"
            end

          helper_def = """
          static ElmcValue *#{helper_name}(#{helper_param_decls}) {
          #{CSource.indent(field_code, 2)}
            ElmcValue *rec_values[#{field_count}] = { #{values_array} };
          #{CSource.indent(record_return, 2)}
          }
          """

          Process.put(
            :elmc_generic_helper_defs,
            [helper_def | Process.get(:elmc_generic_helper_defs, [])]
          )

          next = counter + 1
          out = "tmp_#{next}"
          call_args = Enum.map_join(params, ", ", fn {_key, c_ref, _kind} -> c_ref end)

          {:ok, "  ElmcValue *#{out} = #{helper_name}(#{call_args});\n", out, next}

        :error ->
          :error
      end
    else
      :error
    end
  end

  defp extract_boxed_record_literal_helper?(field_count) do
    field_count >= 12 and Process.get(:elmc_generic_helper_defs) != nil
  end

  defp record_literal_helper_params(ordered_fields, env) do
    params =
      ordered_fields
      |> Enum.flat_map(fn field -> VarAnalysis.used_vars(field.expr) end)
      |> Enum.uniq()
      |> Enum.sort()
      |> Enum.reduce_while([], fn var, acc ->
        case resolve_record_helper_param(env, var) do
          :skip -> {:cont, acc}
          {:ok, param} -> {:cont, [param | acc]}
          :error -> {:halt, :error}
        end
      end)

    case params do
      :error ->
        :error

      params ->
        {:ok, params |> Enum.reverse() |> Enum.uniq_by(fn {_key, c_ref, _kind} -> c_ref end)}
    end
  end

  defp resolve_record_helper_param(env, var) do
    cond do
      is_binary(c_ref = Map.get(env, var)) and c_identifier?(c_ref) ->
        {:ok, {var, c_ref, :boxed}}

      is_binary(ref = EnvBindings.native_int_binding(env, var)) ->
        {:ok, {var, ref, :native_int}}

      is_binary(ref = EnvBindings.native_bool_binding(env, var)) ->
        {:ok, {var, ref, :native_bool}}

      zero_arg_function_var?(env, var) ->
        :skip

      true ->
        :error
    end
  end

  @spec compile_update(
          Types.ir_expr(),
          Types.ir_record_fields(),
          Types.compile_env(),
          Types.compile_counter()
        ) :: Types.compile_result()
  defp compile_update(base, fields, env, counter) do
    {base_code, base_var, counter, base_passthrough?} =
      compile_update_operand(base, env, counter)

    record_shape = Expr.record_shape(base, env)
    record_type = Expr.record_container_type_for_expr(base, env)

    {update_code, current_var, counter} =
      Enum.reduce(fields, {base_code, base_var, counter, base_passthrough?, false}, fn field,
                                                                                       {code_acc,
                                                                                        current,
                                                                                        c,
                                                                                        current_passthrough?,
                                                                                        current_unique?} ->
        {field_code, field_var, c2, field_passthrough?} =
          compile_update_operand(field.expr, Map.delete(env, :__into_out__), c)

        next = c2 + 1
        out = "tmp_#{next}"

        update_call =
          if current_unique? do
            index_ref =
              Expr.record_field_index_ref(field.name, record_shape, record_type, env)

            "elmc_record_update_index_cow_drop(#{current}, #{index_ref}, #{field_var})"
          else
            Expr.record_update_expr(current, field.name, field_var, record_shape,
              env: env,
              type: record_type,
              cow: false
            )
          end

        field_release = update_operand_release(field_var, field_passthrough?)

        current_release =
          if current_unique?, do: "", else: update_operand_release(current, current_passthrough?)

        code = """
        #{field_code}
        ElmcValue *#{out} = #{update_call};
        #{current_release}
        #{field_release}
        """

        {code_acc <> "\n" <> code, out, next, false, true}
      end)
      |> then(fn {code, var, c, _, _} -> {code, var, c} end)

    full_code = update_code

    case maybe_extract_chained_update_helper(base, fields, env, full_code, current_var, counter) do
      {:ok, code, out, counter} -> {code, out, counter}
      :error -> {full_code, current_var, counter}
    end
  end

  defp maybe_extract_chained_update_helper(base, fields, env, update_code, result_var, counter) do
    cond do
      Map.get(env, :__rc_catch__, false) or Map.get(env, :__rc_required__, false) ->
        :error

      not extract_chained_update_helper?(length(fields), update_code) ->
        :error

      true ->
        case chained_update_helper_params(base, fields, env) do
          {:ok, params} ->
            helper_id = Process.get(:elmc_generic_helper_counter, 0) + 1
            Process.put(:elmc_generic_helper_counter, helper_id)

            helper_name =
              "elmc_record_update_helper_#{Util.safe_c_suffix(Map.get(env, :__module__, "Main"))}_#{Util.safe_c_suffix(Map.get(env, :__function_name__, "fn"))}_#{helper_id}"

            helper_param_decls =
              params
              |> Enum.map_join(", ", fn
                {_key, c_ref, :boxed} -> "ElmcValue *#{c_ref}"
                {_key, c_ref, :native_int} -> "elmc_int_t #{c_ref}"
                {_key, c_ref, :native_bool} -> "bool #{c_ref}"
              end)

            helper_def = """
            static ElmcValue *#{helper_name}(#{helper_param_decls}) {
            #{CSource.indent(update_code, 2)}
              return #{result_var};
            }
            """

            Process.put(
              :elmc_generic_helper_defs,
              [helper_def | Process.get(:elmc_generic_helper_defs, [])]
            )

            next = counter + 1
            out = "tmp_#{next}"
            call_args = Enum.map_join(params, ", ", fn {_key, c_ref, _kind} -> c_ref end)

            {:ok, "  ElmcValue *#{out} = #{helper_name}(#{call_args});\n", out, next}

          :error ->
            :error
        end
    end
  end

  defp extract_chained_update_helper?(field_count, _code) do
    Process.get(:elmc_generic_helper_defs) != nil and field_count >= 5
  end

  defp chained_update_helper_params(base, fields, env) do
    vars =
      [base | Enum.map(fields, & &1.expr)]
      |> Enum.flat_map(&VarAnalysis.used_vars/1)
      |> Enum.uniq()
      |> Enum.sort()

    params =
      Enum.reduce_while(vars, [], fn var, acc ->
        case resolve_record_helper_param(env, var) do
          :skip -> {:cont, acc}
          {:ok, param} -> {:cont, [param | acc]}
          :error -> {:halt, :error}
        end
      end)

    case params do
      :error ->
        :error

      params ->
        {:ok, params |> Enum.reverse() |> Enum.uniq_by(fn {_key, c_ref, _kind} -> c_ref end)}
    end
  end

  defp c_identifier?(value) when is_binary(value),
    do: Regex.match?(~r/^[A-Za-z_][A-Za-z0-9_]*$/, value)

  defp compile_update_operand(%{op: :var, name: name}, env, counter) do
    case EnvBindings.lookup_binding(env, name) do
      source when is_binary(source) ->
        if c_identifier?(source) do
          {"", source, counter, true}
        else
          {code, ref, counter} = Host.compile_expr(%{op: :var, name: name}, env, counter)
          {code, ref, counter, false}
        end

      _ ->
        {code, ref, counter} = Host.compile_expr(%{op: :var, name: name}, env, counter)
        {code, ref, counter, false}
    end
  end

  defp compile_update_operand(expr, env, counter) do
    {code, ref, counter} = Host.compile_expr(expr, env, counter)
    {code, ref, counter, false}
  end

  defp update_operand_release(var, passthrough?) do
    if passthrough? or not boxed_release_var?(var) do
      ""
    else
      "elmc_release(#{var});\n"
    end
  end

  defp zero_arg_function_var?(env, var) do
    module_name = Map.get(env, :__module__, "Main")

    case Map.get(env, :__program_decls__, %{}) do
      %{} = decl_map ->
        case Map.get(decl_map, {module_name, var}) do
          %{args: args} when args in [[], nil] -> true
          _ -> false
        end

      _ ->
        false
    end
  end

  @spec compile_field_access_var(
          String.t(),
          String.t(),
          Types.compile_env(),
          Types.compile_counter()
        ) :: Types.compile_result()
  defp compile_field_access_var(arg, field, env, counter) do
    case EnvBindings.lookup_binding(env, arg) do
      {:native_record, fields} ->
        case Map.fetch(fields, field) do
          {:ok, native_ref} ->
            {"", native_ref, counter}

          :error ->
            compile_field_access_bound_var(arg, field, env, counter)
        end

      source when is_binary(source) ->
        compile_bound_field_get(arg, source, field, env, counter)

      _ ->
        {arg_code, arg_var, counter} = Host.compile_expr(%{op: :var, name: arg}, env, counter)
        next = counter + 1
        var = "tmp_#{next}"
        getter =
          record_field_get_expr(
            arg_var,
            field,
            %{op: :var, name: arg},
            env
          )

        code = """
        #{arg_code}
          ElmcValue *#{var} = #{getter};
          elmc_release(#{arg_var});
        """

        {code, var, next}
    end
  end

  @spec compile_field_access_literal(
          Types.ir_record_fields(),
          String.t(),
          Types.compile_env(),
          Types.compile_counter()
        ) :: Types.compile_result()
  defp compile_field_access_literal(fields, field, env, counter) do
    case Enum.find(fields, &(&1.name == field)) do
      %{expr: expr} -> Host.compile_expr(expr, env, counter)
      nil -> Host.compile_expr(%{op: :int_literal, value: 0}, env, counter)
    end
  end

  @spec compile_field_access_bound_var(
          String.t(),
          String.t(),
          Types.compile_env(),
          Types.compile_counter()
        ) :: Types.compile_result()
  defp compile_field_access_bound_var(name, field, env, counter) do
    case EnvBindings.lookup_binding(env, name) do
      {:native_record, fields} ->
        case Map.fetch(fields, field) do
          {:ok, native_ref} ->
            {"", native_ref, counter}

          :error ->
            {code, ref, counter} = Host.compile_expr(%{op: :var, name: name}, env, counter)
            next = counter + 1
            var = "tmp_#{next}"
            getter =
              record_field_get_expr(
                ref,
                field,
                %{op: :var, name: name},
                env
              )

            code =
              code <>
                """
                  ElmcValue *#{var} = #{getter};
                  elmc_release(#{ref});
                """

            {code, var, next}
        end

      source when is_binary(source) ->
        compile_bound_field_get(name, source, field, env, counter)

      _ ->
        compile(%{op: :field_access, arg: name, field: field}, env, counter)
    end
  end

  @spec compile_field_access_expr(
          Types.ir_expr(),
          String.t(),
          Types.compile_env(),
          Types.compile_counter()
        ) :: Types.compile_result()
  defp compile_field_access_expr(arg_expr, field, env, counter) do
    case Host.inline_record_field_expr(arg_expr, field, env) do
      nil ->
        {arg_code, arg_var, counter} = Host.compile_expr(arg_expr, env, counter)
        next = counter + 1
        var = "tmp_#{next}"
        getter = record_field_get_expr(arg_var, field, arg_expr, env)
        :ok = Expr.put_subexpr_record_meta(var, subexpr_record_meta_for_field_access(env, arg_expr, field))

        code = """
        #{arg_code}
          ElmcValue *#{var} = #{getter};
          elmc_release(#{arg_var});
        """

        mark_borrowed_record_field_ref(var, getter)

        {code, var, next}

      field_expr ->
        Host.compile_expr(field_expr, env, counter)
    end
  end

  @spec compile_bound_field_get(
          String.t(),
          String.t(),
          String.t(),
          Types.compile_env(),
          Types.compile_counter()
        ) :: Types.compile_result()
  defp compile_bound_field_get(record_name, source, field, env, counter)
       when is_binary(source) do
    next = counter + 1
    var = "tmp_#{next}"
    getter =
      record_field_get_expr(
        source,
        field,
        %{op: :var, name: record_name},
        env
      )

    before_probe =
      env |> DebugProbes.field_probe(record_name, field, :before) |> DebugProbes.region()

    after_probe =
      env |> DebugProbes.field_probe(record_name, field, :after) |> DebugProbes.region()

    code = """
    #{before_probe}
      ElmcValue *#{var} = #{getter};
      #{after_probe}
    """

    mark_borrowed_record_field_ref(var, getter)

    {code, var, next}
  end

  defp mark_borrowed_record_field_ref(var, getter)
       when is_binary(var) and is_binary(getter) do
    if borrowed_record_field_getter?(getter) do
      Process.put(
        :elmc_borrowed_field_refs,
        MapSet.put(Process.get(:elmc_borrowed_field_refs, MapSet.new()), var)
      )
    end
  end

  defp mark_borrowed_record_field_ref(_var, _getter), do: :ok

  defp borrowed_record_field_getter?(getter) do
    String.starts_with?(getter, "elmc_record_get_index(") or
      String.starts_with?(getter, "ELMC_RECORD_GET_INDEX(")
  end

  @spec compile_field_call_var(
          String.t(),
          String.t(),
          [Types.ir_expr()],
          Types.compile_env(),
          Types.compile_counter()
        ) :: Types.compile_result()
  defp compile_field_call_var(arg, field, args, env, counter) do
    case Map.fetch(env, arg) do
      {:ok, {:native_record, _fields}} ->
        {box_code, box_var, counter} = FunctionCallCompile.compile_var(arg, env, counter)

        compile_bound_field_call(box_var, field, args, env, counter)
        |> then(fn {call_code, out, next} ->
          {box_code <> call_code <> "  elmc_release(#{box_var});\n", out, next}
        end)

      {:ok, source} when is_binary(source) ->
        compile_bound_field_call(source, field, args, env, counter)

      :error ->
        {arg_code, record_var, counter} =
          Host.compile_expr(%{op: :var, name: arg}, env, counter)

        {call_code, out, counter} =
          compile_bound_field_call(record_var, field, args, env, counter)

        {arg_code <> call_code, out, counter}
    end
  end

  @spec compile_bound_field_call(
          String.t(),
          String.t(),
          [Types.ir_expr()],
          Types.compile_env(),
          Types.compile_counter()
        ) :: Types.compile_result()
  defp compile_bound_field_call(source, field, args, env, counter) when is_binary(source) do
    next = counter + 1
    fn_var = "tmp_#{next}"

    {arg_code, arg_vars, counter2} =
      Enum.reduce(args, {"", [], next}, fn arg_expr, {code_acc, vars_acc, c} ->
        {code, var, c2} = Host.compile_expr(arg_expr, env, c)
        {code_acc <> "\n  " <> code, vars_acc ++ [var], c2}
      end)

    next2 = counter2 + 1
    out = "tmp_#{next2}"
    argc = length(arg_vars)
    args_array = "call_args_#{next2}"
    arg_list = Enum.join(arg_vars, ", ")

    releases =
      arg_vars
      |> Enum.map_join("\n  ", fn var -> "elmc_release(#{var});" end)

    code = """
    ElmcValue *#{fn_var} = elmc_record_get(#{source}, "#{Util.escape_c_string(field)}");
      #{arg_code}
      ElmcValue *#{args_array}[#{max(argc, 1)}] = { #{arg_list} };
      ElmcValue *#{out} = elmc_closure_call(#{fn_var}, #{args_array}, #{argc});
      elmc_release(#{fn_var});
      #{releases}
    """

    {code, out, next2}
  end

  defp compile_boxed_field_value_expr(%{op: :char_literal, value: value}, _env, counter) do
    next = counter + 1
    var = Util.temp_var(next, "boxed_char")
    {"ElmcValue *#{var} = elmc_new_char(#{value});\n", var, next}
  end

  defp compile_boxed_field_value_expr(expr, env, counter) do
    if Host.native_int_expr?(expr, env) and not BuiltinUnion.maybe_nothing_literal?(expr) do
      {code, native_ref, c2} = Host.compile_native_int_expr(expr, env, counter)
      next = c2 + 1
      var = Util.temp_var(next, "boxed_int")

      {code <> "  ElmcValue *#{var} = elmc_new_int_take(#{native_ref});\n", var, next}
    else
      Host.compile_expr(expr, env, counter)
    end
  end

  defp compile_field_exprs(ordered_fields, env, counter, compile_fn) do
    {record_env, field_code, field_refs, counter} =
      Enum.reduce(ordered_fields, {record_subexpr_cache_env(env), "", [], counter}, fn field,
                                                                                       {record_env_acc,
                                                                                        code_acc,
                                                                                        refs_acc,
                                                                                        c} ->
        field_env = field_subexpr_cache_env(record_env_acc)
        {code, ref, c2, _} = compile_cached_expr(field.expr, field_env, c, compile_fn)
        record_env_acc = sync_record_subexpr_cache(record_env_acc, field_env)
        {record_env_acc, code_acc <> "\n  " <> code, refs_acc ++ [ref], c2}
      end)

    cache = take_record_subexpr_cache(record_env)
    release_env = Map.put(env, :__subexpr_cache__, cache)

    epilogue_refs =
      deferred_cache_release_refs(release_env, field_refs, field_code)
      |> MapSet.new()
      |> MapSet.union(
        MapSet.new(record_field_source_release_refs(field_refs, field_code, clear?: false))
      )

    post_record_refs =
      post_record_cache_release_refs(release_env, field_refs, field_code, epilogue_refs)

    post_release =
      epilogue_refs
      |> MapSet.union(MapSet.new(post_record_refs))
      |> MapSet.to_list()
      |> Enum.sort()
      |> releases_to_code()

    Process.put(:elmc_record_field_sources, MapSet.new())

    {field_code, field_refs, counter, post_release}
  end

  defp record_subexpr_cache_env(env) do
    cache_key = make_ref()
    Process.put({:elmc_subexpr_cache, cache_key}, %{})

    env
    |> Map.drop([:__subexpr_cache__, :__subexpr_cache_key__, :__record_subexpr_cache_key__])
    |> Map.put(:__record_subexpr_cache_key__, cache_key)
  end

  defp field_subexpr_cache_env(record_env) do
    cache_key = make_ref()
    Process.put({:elmc_subexpr_cache, cache_key}, %{})
    Process.put({:elmc_subexpr_shared, cache_key}, MapSet.new())

    record_env
    |> Map.put(:__subexpr_cache_key__, cache_key)
  end

  @spec shared_subexpr_ref?(Types.compile_env(), String.t()) :: boolean()
  def shared_subexpr_ref?(env, ref) when is_binary(ref) do
    case Map.get(env, :__subexpr_cache_key__) do
      nil -> false
      key -> MapSet.member?(Process.get({:elmc_subexpr_shared, key}, MapSet.new()), ref)
    end
  end

  @spec release_list_operand_code(Types.compile_env(), String.t()) :: String.t()
  def release_list_operand_code(env, list_var) when is_binary(list_var) do
    if shared_subexpr_ref?(env, list_var), do: "", else: "elmc_release(#{list_var});\n"
  end

  @spec reset_borrowed_field_refs() :: :ok
  def reset_borrowed_field_refs do
    Process.put(:elmc_borrowed_field_refs, MapSet.new())
    reset_record_field_sources()
    :ok
  end

  @spec reset_record_field_sources() :: :ok
  def reset_record_field_sources do
    Process.put(:elmc_record_field_sources, MapSet.new())
    :ok
  end

  @spec mark_record_field_container(String.t()) :: :ok
  def mark_record_field_container(ref) when is_binary(ref) do
    if Util.boxed_temp_var?(ref) and not EnvBindings.borrowed_arg_ref?(%{}, ref) do
      Process.put(
        :elmc_record_field_sources,
        MapSet.put(Process.get(:elmc_record_field_sources, MapSet.new()), ref)
      )
    end

    :ok
  end

  @spec reset_deferred_call_operand_releases() :: :ok
  def reset_deferred_call_operand_releases do
    Process.put(:elmc_deferred_call_operand_releases, MapSet.new())
    :ok
  end

  @spec defer_call_operand_release(String.t()) :: :ok
  def defer_call_operand_release(ref) when is_binary(ref) do
    if Util.boxed_temp_var?(ref) do
      set =
        Process.get(:elmc_deferred_call_operand_releases, MapSet.new())
        |> MapSet.put(ref)

      Process.put(:elmc_deferred_call_operand_releases, set)
    end

    :ok
  end

  @spec deferred_call_operand_release_code() :: String.t()
  def deferred_call_operand_release_code do
    refs = Process.get(:elmc_deferred_call_operand_releases, MapSet.new())
    Process.put(:elmc_deferred_call_operand_releases, MapSet.new())

    refs
    |> Enum.sort()
    |> Enum.map_join("\n  ", &"elmc_release(#{&1});")
    |> case do
      "" -> ""
      releases -> "\n  " <> releases <> "\n"
    end
  end

  @spec flush_subexpr_cache_releases(Types.compile_env()) :: String.t()
  def flush_subexpr_cache_releases(env) do
    field_releases =
      env
      |> get_field_subexpr_cache()
      |> Map.values()
      |> Enum.map(fn {ref} -> ref end)
      |> Enum.filter(&boxed_release_var?/1)
      |> Enum.uniq()
      |> Enum.map_join("\n  ", &"elmc_release(#{&1});")

    record_releases =
      env
      |> get_record_subexpr_cache()
      |> Map.values()
      |> Enum.map(fn {ref} -> ref end)
      |> Enum.filter(&boxed_release_var?/1)
      |> Enum.uniq()
      |> Enum.map_join("\n  ", &"elmc_release(#{&1});")

    deferred = deferred_call_operand_release_code()

    [field_releases, record_releases, String.trim(deferred)]
    |> Enum.reject(&(&1 == ""))
    |> Enum.map_join("\n  ", & &1)
    |> case do
      "" -> ""
      releases -> "\n  " <> releases <> "\n"
    end
  end

  defp mark_shared_subexpr_ref(env, ref) when is_binary(ref) do
    case Map.get(env, :__subexpr_cache_key__) do
      nil ->
        env

      key ->
        shared =
          Process.get({:elmc_subexpr_shared, key}, MapSet.new())
          |> MapSet.put(ref)

        Process.put({:elmc_subexpr_shared, key}, shared)
        env
    end
  end

  defp sync_record_subexpr_cache(record_env, field_env) do
    field_cache = take_field_subexpr_cache(field_env)

    record_env
    |> get_record_subexpr_cache()
    |> Map.merge(field_cache)
    |> then(&put_record_subexpr_cache(record_env, &1))
  end

  defp get_field_subexpr_cache(env) do
    case Map.get(env, :__subexpr_cache_key__) do
      nil -> %{}
      key -> Process.get({:elmc_subexpr_cache, key}, %{})
    end
  end

  defp put_field_subexpr_cache(env, cache) do
    case Map.get(env, :__subexpr_cache_key__) do
      nil ->
        env

      key ->
        Process.put({:elmc_subexpr_cache, key}, cache)
        env
    end
  end

  defp take_field_subexpr_cache(env) do
    case Map.get(env, :__subexpr_cache_key__) do
      nil ->
        %{}

      key ->
        cache = Process.get({:elmc_subexpr_cache, key}, %{})
        Process.delete({:elmc_subexpr_cache, key})
        Process.delete({:elmc_subexpr_shared, key})
        cache
    end
  end

  defp get_record_subexpr_cache(env) do
    case Map.get(env, :__record_subexpr_cache_key__) do
      nil -> %{}
      key -> Process.get({:elmc_subexpr_cache, key}, %{})
    end
  end

  defp put_record_subexpr_cache(env, cache) do
    case Map.get(env, :__record_subexpr_cache_key__) do
      nil ->
        env

      key ->
        Process.put({:elmc_subexpr_cache, key}, cache)
        env
    end
  end

  defp take_record_subexpr_cache(env) do
    case Map.get(env, :__record_subexpr_cache_key__) do
      nil ->
        %{}

      key ->
        cache = Process.get({:elmc_subexpr_cache, key}, %{})
        Process.delete({:elmc_subexpr_cache, key})
        cache
    end
  end

  defp lookup_subexpr_cache(env, key) do
    case Map.get(get_field_subexpr_cache(env), key) do
      {cached_ref} ->
        {:field_hit, cached_ref}

      nil ->
        case Map.get(get_record_subexpr_cache(env), key) do
          {cached_ref} -> {:record_hit, cached_ref}
          nil -> :miss
        end
    end
  end

  defp store_subexpr_cache(env, key, ref) do
    entry = {ref}

    env =
      if Map.has_key?(env, :__subexpr_cache_key__) do
        env
        |> get_field_subexpr_cache()
        |> Map.put(key, entry)
        |> then(&put_field_subexpr_cache(env, &1))
      else
        env
      end

    if Map.has_key?(env, :__record_subexpr_cache_key__) do
      env
      |> get_record_subexpr_cache()
      |> Map.put(key, entry)
      |> then(&put_record_subexpr_cache(env, &1))
    else
      env
    end
  end

  defp compile_cached_expr(expr, env, counter, compile_fn) do
    key = subexpr_key(expr)

    case lookup_subexpr_cache(env, key) do
      {:field_hit, cached_ref} ->
        env = mark_shared_subexpr_ref(env, cached_ref)
        {"", cached_ref, counter, env}

      {:record_hit, cached_ref} ->
        {"", cached_ref, counter, env}

      :miss ->
        {code, ref, c, env} =
          case expr do
            %{op: :field_access, arg: arg, field: field} ->
              case Host.inline_record_field_expr(arg, field, env) do
                nil ->
                  compile_cached_field_access(expr, arg, field, env, counter, compile_fn)

                field_expr ->
                  if runtime_record_field_access?(field_expr, arg, field) do
                    compile_cached_field_access(expr, arg, field, env, counter, compile_fn)
                  else
                    {compiled_code, compiled_ref, compiled_counter} =
                      compile_fn.(field_expr, env, counter)

                    {compiled_code, compiled_ref, compiled_counter, env}
                  end
              end

            _ ->
              {compiled_code, compiled_ref, compiled_counter} = compile_fn.(expr, env, counter)
              {compiled_code, compiled_ref, compiled_counter, env}
          end

        env = store_subexpr_cache(env, key, ref)
        {code, ref, c, env}
    end
  end

  defp compile_cached_field_access(full_expr, arg_expr, field, env, counter, compile_fn) do
    cond do
      boxed_field_compile_fn?(compile_fn) and shareable_field_access_arg?(arg_expr) and
          (Host.native_int_expr?(full_expr, env) or
             RecordFields.union_tag_field?(env, arg_expr, field)) ->
        compile_cached_boxed_native_int_field(arg_expr, field, env, counter)

      boxed_field_compile_fn?(compile_fn) and Host.native_int_expr?(full_expr, env) ->
        {code, ref, c} = compile_boxed_field_value_expr(full_expr, env, counter)
        {code, ref, c, env}

      true ->
        compile_cached_field_access_impl(full_expr, arg_expr, field, env, counter, compile_fn)
    end
  end

  defp shareable_field_access_arg?(%{op: :field_access}), do: true
  defp shareable_field_access_arg?(_), do: false

  defp compile_cached_boxed_native_int_field(arg_expr, field, env, counter) do
    {arg_code, arg_var, counter, env, release_arg?} =
      compile_cached_field_access_arg(arg_expr, env, counter)

    mark_record_field_container(arg_var)
    shape = Expr.record_shape(arg_expr, env)
    record_type = Expr.record_container_type_for_expr(arg_expr, env)
    getter = Host.record_get_int_expr(arg_var, field, shape, env, record_type)

    next = counter + 1
    var = Util.temp_var(next, "boxed_int")

    release_line =
      if release_arg?, do: "  elmc_release(#{arg_var});\n", else: ""

    code = """
    #{arg_code}  ElmcValue *#{var} = elmc_new_int_take(#{getter});
    #{release_line}
    """

    {code, var, next, env}
  end

  defp compile_cached_field_access_impl(_full_expr, arg_expr, field, env, counter, compile_fn) do
    arg_expr = Expr.normalize_field_access_arg(arg_expr)

    {arg_code, arg_var, counter, env, release_arg?} =
      compile_cached_field_access_arg(arg_expr, env, counter)

    mark_record_field_container(arg_var)
    shape = Expr.record_shape(arg_expr, env)

    release_line =
      if release_arg?, do: "  elmc_release(#{arg_var});\n", else: ""

    record_type = Expr.record_container_type_for_expr(arg_expr, env)

    if native_int_compile_fn?(compile_fn) do
      getter = Host.record_get_int_expr(arg_var, field, shape, env, record_type)

      code =
        arg_code <>
          if release_line != "", do: "  " <> String.trim_trailing(release_line) <> "\n", else: ""

      {code, getter, counter, env}
    else
      next = counter + 1
      var = Util.temp_var(next, field)
      getter = record_field_get_expr(arg_var, field, arg_expr, env)
      :ok = Expr.put_subexpr_record_meta(var, subexpr_record_meta_for_field_access(env, arg_expr, field))

      code = """
      #{arg_code}  ElmcValue *#{var} = #{getter};
      #{release_line}
      """

      mark_borrowed_record_field_ref(var, getter)

      {code, var, next, env}
    end
  end

  defp record_field_get_expr(source, field, arg_expr, env) do
    shape = Expr.record_shape(arg_expr, env)
    type = Expr.record_container_type_for_expr(arg_expr, env)
    Expr.record_get_expr(source, field, shape, env, type)
  end

  defp subexpr_record_meta_for_field_access(env, arg_expr, field) do
    record_type = RecordFields.field_type(env, arg_expr, field)

    shape =
      if is_binary(record_type) do
        Expr.record_shape_for_type(record_type, env)
      else
        Expr.record_shape(arg_expr, env)
      end

    %{type: record_type, shape: shape}
  end

  defp native_int_compile_fn?(compile_fn),
    do: compile_fn == (&Host.compile_native_int_expr/3)

  defp boxed_field_compile_fn?(compile_fn),
    do: compile_fn == (&compile_boxed_field_value_expr/3)

  defp runtime_record_field_access?(field_expr, arg, field)
       when is_binary(field) or is_atom(field) do
    match?(%{op: :int_literal}, field_expr) and record_field_arg?(arg)
  end

  defp runtime_record_field_access?(_field_expr, _arg, _field), do: false

  defp record_field_arg?(%{op: :var, name: name}) when is_binary(name) or is_atom(name), do: true
  defp record_field_arg?(%{op: :call}), do: true
  defp record_field_arg?(%{op: :qualified_call}), do: true
  defp record_field_arg?(_arg), do: false

  defp compile_cached_field_access_bound_name(name, env, counter) do
    case EnvBindings.lookup_binding(env, name) do
      source when is_binary(source) ->
        {"", source, counter, env, false}

      {:native_record, _fields} ->
        {code, ref, counter} = Host.compile_expr(%{op: :var, name: name}, env, counter)
        {code, ref, counter, env, true}

      _ ->
        if zero_arg_function_var?(env, name) do
          {code, ref, counter} = Host.compile_expr(%{op: :var, name: name}, env, counter)
          {code, ref, counter, env, false}
        else
          {"", to_string(name), counter, env, false}
        end
    end
  end

  defp compile_cached_field_access_arg(%{op: :field_access} = arg_expr, env, counter) do
    {code, ref, counter, env} = compile_cached_expr(arg_expr, env, counter, @uncached_compile)
    {code, ref, counter, env, false}
  end

  defp compile_cached_field_access_arg(%{op: :var, name: name}, env, counter),
    do: compile_cached_field_access_bound_name(name, env, counter)

  defp compile_cached_field_access_arg(arg_expr, env, counter) do
    key = subexpr_key(arg_expr)
    cache_hit? = lookup_subexpr_cache(env, key) != :miss

    {code, ref, counter, env} = compile_cached_expr(arg_expr, env, counter, @uncached_compile)

    release? =
      if cacheable_call_arg?(arg_expr) do
        cache_hit?
      else
        true
      end

    {code, ref, counter, env, release?}
  end

  defp cacheable_call_arg?(%{op: op}) when op in [:call, :qualified_call, :constructor_call], do: true
  defp cacheable_call_arg?(_), do: false

  defp deferred_cache_release_refs(env, field_refs, field_code) do
    env
    |> Map.get(:__subexpr_cache__, %{})
    |> Map.values()
    |> Enum.map(fn {ref} -> ref end)
    |> Enum.filter(&boxed_release_var?/1)
    |> Enum.reject(&field_ref_still_uses_cache_ref?(&1, field_refs))
    |> Enum.reject(&released_in_field_code?(&1, field_code))
    |> Enum.reject(&orphan_cache_release?(&1, field_code))
    |> Enum.uniq()
  end

  defp record_field_source_release_refs(field_refs, field_code, opts) do
    clear? = Keyword.get(opts, :clear?, true)

    refs =
      Process.get(:elmc_record_field_sources, MapSet.new())
      |> MapSet.to_list()
      |> Enum.filter(&boxed_release_var?/1)
      |> Enum.reject(&(&1 in field_refs))
      |> Enum.reject(&released_in_field_code?(&1, field_code))
      |> Enum.reject(&orphan_cache_release?(&1, field_code))
      |> Enum.uniq()

    if clear?, do: Process.put(:elmc_record_field_sources, MapSet.new())

    refs
  end

  defp releases_to_code([]), do: ""

  defp releases_to_code(refs) do
    refs
    |> Enum.map_join("\n  ", &"elmc_release(#{&1});")
    |> then(&("\n  " <> &1))
  end

  defp field_ref_still_uses_cache_ref?(cached_ref, field_refs) when is_binary(cached_ref) do
    cached_ref in field_refs
  end

  defp field_ref_still_uses_cache_ref?(_cached_ref, _field_refs), do: false

  defp post_record_cache_release_refs(env, field_refs, field_code, skip_refs) do
    already_released = released_vars_in_code(field_code)

    env
    |> Map.get(:__subexpr_cache__, %{})
    |> Map.values()
    |> Enum.map(fn {ref} -> ref end)
    |> Enum.filter(&boxed_release_var?/1)
    |> Enum.reject(&(&1 in field_refs))
    |> Enum.filter(&field_ref_still_uses_cache_ref?(&1, field_refs))
    |> Enum.reject(&MapSet.member?(skip_refs, &1))
    |> Enum.reject(&MapSet.member?(already_released, &1))
    |> Enum.reject(&released_in_field_code?(&1, field_code))
    |> Enum.reject(&orphan_cache_release?(&1, field_code))
    |> Enum.uniq()
  end

  defp orphan_cache_release?(ref, field_code) when is_binary(ref) and is_binary(field_code) do
    not declared_boxed_var?(ref, field_code) or
      OwnershipTransfer.transferred_in_c_source?(ref, field_code)
  end

  defp orphan_cache_release?(_ref, _field_code), do: false

  defp declared_boxed_var?(ref, field_code) when is_binary(ref) and is_binary(field_code) do
    Regex.match?(~r/ElmcValue \*#{Regex.escape(ref)}(?!\w)\s*=/, field_code)
  end

  defp released_vars_in_code(code) when is_binary(code) do
    Regex.scan(~r/elmc_release\((tmp_\d+|head_\d+)\)/, code)
    |> Enum.map(fn [_, var] -> var end)
    |> MapSet.new()
  end

  defp released_vars_in_code(_), do: MapSet.new()

  defp released_in_field_code?(ref, field_code) when is_binary(ref) and is_binary(field_code) do
    String.contains?(field_code, "elmc_release(#{ref})")
  end

  defp released_in_field_code?(_ref, _field_code), do: false

  defp subexpr_key(%{op: :var, name: name}), do: {:var, name}

  defp subexpr_key(%{op: :field_access, arg: arg, field: field}),
    do: {:field_access, subexpr_key(arg), field}

  defp subexpr_key(%{op: :int_literal, value: value}), do: {:int, value}

  defp subexpr_key(%{op: op} = expr) when is_map(expr) do
    {:map, op,
     expr
     |> Map.to_list()
     |> Enum.sort()
     |> Enum.map(fn {k, v} -> {k, subexpr_key(v)} end)}
  end

  defp subexpr_key(other), do: other

  defp boxed_release_var?(var) do
    Util.boxed_temp_var?(var) and not EnvBindings.borrowed_arg_ref?(%{}, var)
  end
end
