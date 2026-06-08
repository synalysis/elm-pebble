defmodule Elmc.Backend.CCodegen.RecordCompile do
  @moduledoc false

  alias Elmc.Backend.CCodegen.DebugProbes
  alias Elmc.Backend.CCodegen.EnvBindings
  alias Elmc.Backend.CCodegen.Expr
  alias Elmc.Backend.CCodegen.FunctionCallCompile
  alias Elmc.Backend.CCodegen.Host
  alias Elmc.Backend.CCodegen.Types
  alias Elmc.Backend.CCodegen.Util
  alias Elmc.Backend.CCodegen.VarAnalysis

  @spec compile(Types.ir_record_expr(), Types.compile_env(), Types.compile_counter()) ::
          Types.compile_result()
  def compile(%{op: :record_literal, fields: fields}, env, counter) do
    compile_literal(fields, env, counter)
  end

  def compile(%{op: :record_update, base: base, fields: fields}, env, counter) do
    compile_update(base, fields, env, counter)
  end

  def compile(%{op: :field_access, arg: arg, field: field}, env, counter)
      when is_binary(arg) do
    compile_field_access_var(arg, field, env, counter)
  end

  def compile(
        %{op: :field_access, arg: %{op: :record_literal, fields: fields}, field: field},
        env,
        counter
      )
      when is_list(fields) do
    compile_field_access_literal(fields, field, env, counter)
  end

  def compile(%{op: :field_access, arg: %{op: :var, name: name}, field: field}, env, counter) do
    compile_field_access_bound_var(name, field, env, counter)
  end

  def compile(%{op: :field_access, arg: arg_expr, field: field}, env, counter)
      when is_map(arg_expr) do
    compile_field_access_expr(arg_expr, field, env, counter)
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

  @spec compile_literal(Types.ir_record_fields(), Types.compile_env(), Types.compile_counter()) ::
          Types.compile_result()
  defp compile_literal(fields, env, counter) do
    ordered_fields = fields
    field_count = length(ordered_fields)

    names_array =
      ordered_fields
      |> Enum.map(fn f -> "\"#{Util.escape_c_string(f.name)}\"" end)
      |> Enum.join(", ")

    if field_count > 0 and Enum.all?(ordered_fields, &Host.native_int_expr?(&1.expr, env)) do
      compile_native_int_literal(ordered_fields, names_array, field_count, env, counter)
    else
      compile_boxed_literal(ordered_fields, names_array, field_count, env, counter)
    end
  end

  @spec compile_native_int_literal(
          Types.ir_record_fields(),
          String.t(),
          non_neg_integer(),
          Types.compile_env(),
          Types.compile_counter()
        ) :: Types.compile_result()
  defp compile_native_int_literal(ordered_fields, names_array, field_count, env, counter) do
    {field_code, field_refs, counter} =
      compile_field_exprs(ordered_fields, env, counter, &Host.compile_native_int_expr/3)

    next = counter + 1
    out = "tmp_#{next}"
    values_array = Enum.join(field_refs, ", ")

    code = """
    #{field_code}
      const char *rec_names_#{next}[#{field_count}] = { #{names_array} };
      elmc_int_t rec_values_#{next}[#{field_count}] = { #{values_array} };
      ElmcValue *#{out} = elmc_record_new_ints(#{field_count}, rec_names_#{next}, rec_values_#{next});
    """

    {code, out, next}
  end

  @spec compile_boxed_literal(
          Types.ir_record_fields(),
          String.t(),
          non_neg_integer(),
          Types.compile_env(),
          Types.compile_counter()
        ) :: Types.compile_result()
  defp compile_boxed_literal(ordered_fields, names_array, field_count, env, counter) do
    case maybe_extract_boxed_record_literal_helper(
           ordered_fields,
           names_array,
           field_count,
           env,
           counter
         ) do
      {:ok, code, out, counter} ->
        {code, out, counter}

      :error ->
        compile_inline_boxed_literal(ordered_fields, names_array, field_count, env, counter)
    end
  end

  defp compile_inline_boxed_literal(ordered_fields, names_array, field_count, env, counter) do
    {field_code, field_refs, counter} =
      compile_field_exprs(ordered_fields, env, counter, &Host.compile_expr/3)

    next = counter + 1
    out = "tmp_#{next}"
    values_array = Enum.join(field_refs, ", ")

    code = """
    #{field_code}
      const char *rec_names_#{next}[#{max(field_count, 1)}] = { #{names_array} };
      ElmcValue *rec_values_#{next}[#{max(field_count, 1)}] = { #{values_array} };
        ElmcValue *#{out} = elmc_record_new_take(#{field_count}, rec_names_#{next}, rec_values_#{next});
    """

    {code, out, next}
  end

  defp maybe_extract_boxed_record_literal_helper(
         ordered_fields,
         names_array,
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

          {field_code, field_vars, _counter} =
            Enum.reduce(ordered_fields, {"", [], counter}, fn field, {code_acc, vars_acc, c} ->
              {code, var, c2} = Host.compile_expr(field.expr, env, c)
              {code_acc <> "\n  " <> code, vars_acc ++ [{field.name, var}], c2}
            end)

          values_array = field_vars |> Enum.map(fn {_name, var} -> var end) |> Enum.join(", ")

          helper_def = """
          static ElmcValue *#{helper_name}(#{helper_param_decls}) {
          #{Util.indent(field_code, 2)}
            const char *rec_names[#{field_count}] = { #{names_array} };
            ElmcValue *rec_values[#{field_count}] = { #{values_array} };
            return elmc_record_new_take(#{field_count}, rec_names, rec_values);
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
      :error -> :error
      params -> {:ok, params |> Enum.reverse() |> Enum.uniq_by(fn {_key, c_ref, _kind} -> c_ref end)}
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
    {base_code, base_var, counter} = Host.compile_expr(base, env, counter)
    record_shape = Expr.record_shape(base, env)

    {update_code, current_var, counter} =
      Enum.reduce(fields, {"", base_var, counter}, fn field, {code_acc, current, c} ->
        {field_code, field_var, c2} = Host.compile_expr(field.expr, env, c)
        next = c2 + 1
        out = "tmp_#{next}"

        update_call =
          Expr.record_update_expr(current, field.name, field_var, record_shape)

        field_release =
          if boxed_release_var?(field_var),
            do: "elmc_release(#{field_var});",
            else: ""

        current_release =
          if boxed_release_var?(current),
            do: "elmc_release(#{current});",
            else: ""

        code = """
        #{field_code}
        ElmcValue *#{out} = #{update_call};
        #{current_release}
        #{field_release}
        """

        {code_acc <> "\n" <> code, out, next}
      end)

    full_code = base_code <> update_code

    case maybe_extract_chained_update_helper(base, fields, env, full_code, current_var, counter) do
      {:ok, code, out, counter} -> {code, out, counter}
      :error -> {full_code, current_var, counter}
    end
  end

  defp maybe_extract_chained_update_helper(base, fields, env, update_code, result_var, counter) do
    if extract_chained_update_helper?(length(fields), update_code) do
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
          #{Util.indent(update_code, 2)}
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
    else
      :error
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
      :error -> :error
      params -> {:ok, params |> Enum.reverse() |> Enum.uniq_by(fn {_key, c_ref, _kind} -> c_ref end)}
    end
  end

  defp c_identifier?(value) when is_binary(value),
    do: Regex.match?(~r/^[A-Za-z_][A-Za-z0-9_]*$/, value)

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
    case Map.fetch(env, arg) do
      {:ok, {:native_record, fields}} ->
        case Map.fetch(fields, field) do
          {:ok, native_ref} ->
            {"", native_ref, counter}

          :error ->
            Host.compile_expr(%{op: :int_literal, value: 0}, env, counter)
        end

      {:ok, source} when is_binary(source) ->
        compile_bound_field_get(arg, source, field, env, counter)

      :error ->
        {arg_code, arg_var, counter} = Host.compile_expr(%{op: :var, name: arg}, env, counter)
        next = counter + 1
        var = "tmp_#{next}"

        code = """
        #{arg_code}
          ElmcValue *#{var} = elmc_record_get(#{arg_var}, "#{Util.escape_c_string(field)}");
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
    case Map.fetch(env, name) do
      {:ok, {:native_record, fields}} ->
        case Map.fetch(fields, field) do
          {:ok, native_ref} ->
            {"", native_ref, counter}

          :error ->
            Host.compile_expr(%{op: :int_literal, value: 0}, env, counter)
        end

      {:ok, source} ->
        compile_bound_field_get(name, source, field, env, counter)

      :error ->
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
        getter = Expr.record_get_expr(arg_var, field, Expr.record_shape(arg_expr, env))

        code = """
        #{arg_code}
          ElmcValue *#{var} = #{getter};
          elmc_release(#{arg_var});
        """

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
    getter = Expr.record_get_expr(source, field, Expr.record_shape_for_var(env, record_name))

    before_probe =
      env |> DebugProbes.field_probe(record_name, field, :before) |> DebugProbes.region()

    after_probe =
      env |> DebugProbes.field_probe(record_name, field, :after) |> DebugProbes.region()

    code = """
    #{before_probe}
      ElmcValue *#{var} = #{getter};
      #{after_probe}
    """

    {code, var, next}
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

  defp compile_field_exprs(ordered_fields, env, counter, compile_fn) do
    {_env, field_code, field_refs, counter} =
      Enum.reduce(ordered_fields, {subexpr_cache_env(env), "", [], counter}, fn field,
                                                                                {env_acc, code_acc,
                                                                                 refs_acc, c} ->
        {code, ref, c2, env_acc} = compile_cached_expr(field.expr, env_acc, c, compile_fn)
        {env_acc, code_acc <> "\n  " <> code, refs_acc ++ [ref], c2}
      end)

    {field_code, field_refs, counter}
  end

  defp subexpr_cache_env(env), do: Map.put_new(env, :__subexpr_cache__, %{})

  defp compile_cached_expr(expr, env, counter, compile_fn) do
    key = subexpr_key(expr)
    cache = Map.get(env, :__subexpr_cache__, %{})

    case Map.get(cache, key) do
      {cached_ref} ->
        {"", cached_ref, counter, env}

      nil ->
        {code, ref, c} = compile_fn.(expr, env, counter)
        env = Map.put(env, :__subexpr_cache__, Map.put(cache, key, {ref}))
        {code, ref, c, env}
    end
  end

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

  defp boxed_release_var?(var) when is_binary(var),
    do: Regex.match?(~r/^tmp_\d+$/, var)
end
