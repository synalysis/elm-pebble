defmodule Elmc.Backend.CCodegen.FunctionCallCompile do
  @moduledoc false

  alias Elmc.Backend.CCodegen.BuiltinOperators
  alias Elmc.Backend.CCodegen.ConstantInt
  alias Elmc.Backend.CCodegen.DebugProbes
  alias Elmc.Backend.CCodegen.EnvBindings
  alias Elmc.Backend.CCodegen.Expr
  alias Elmc.Backend.CCodegen.Host
  alias Elmc.Backend.CCodegen.Native.FunctionCall, as: NativeFunctionCall
  alias Elmc.Backend.CCodegen.Native.RecordFields
  alias Elmc.Backend.CCodegen.Types
  alias Elmc.Backend.CCodegen.Util

  @type closure_signature ::
          {:top_level_ref, String.t(), String.t(), non_neg_integer()}
          | {:partial_ref, String.t(), String.t(), non_neg_integer(), non_neg_integer()}

  @spec value_source(Types.compile_env(), String.t(), Types.compile_counter()) ::
          Types.value_source_result()
  def value_source(env, name, counter) do
    cond do
      is_binary(EnvBindings.native_int_binding(env, name)) ->
        {"", EnvBindings.native_int_binding(env, name), counter}

      is_binary(EnvBindings.native_bool_binding(env, name)) ->
        {"", EnvBindings.native_bool_binding(env, name), counter}

      is_binary(EnvBindings.native_float_binding(env, name)) ->
        {"", EnvBindings.native_float_binding(env, name), counter}

      true ->
        case Map.fetch(env, name) do
          {:ok, {:native_record, fields}} when is_map(fields) ->
            compile_native_record_box("tmp_src", name, fields, env, counter)
            |> then(fn {code, var, next} -> {code, var, next} end)

          {:ok, {:direct_fragment, fragment}} ->
            {code, var, next} = Host.compile_expr(fragment, env, counter)
            {code, var, next}

          {:ok, source} when is_binary(source) ->
            {"", source, counter}

          :error ->
            module_name = Map.get(env, :__module__, "Main")
            function_arities = Map.get(env, :__function_arities__, %{})
            arity = Map.get(function_arities, {module_name, name}, 0)

            if arity > 0 do
              next = counter + 1
              tmp = "tmp_#{next}"
              {closure_code, _, next} = top_level_closure(module_name, name, arity, tmp, next)
              {closure_code, tmp, next}
            else
              next = counter + 1
              tmp = "tmp_#{next}"
              c_name = Util.module_fn_name(module_name, name)

              {
                "ElmcValue *#{tmp} = #{c_name}(NULL, 0);\n",
                tmp,
                next
              }
            end
        end
    end
  end

  @spec compile(String.t(), String.t(), [Types.ir_expr()], Types.compile_env(), Types.compile_counter()) ::
          Types.compile_result()
  def compile(module_name, name, args, env, counter) do
    function_arities = Map.get(env, :__function_arities__, %{})
    arity = Map.get(function_arities, {module_name, name}, length(args))
    c_name = Util.module_fn_name(module_name, name)

    case ConstantInt.compile_boxed_call(module_name, name, args, env, counter) do
      {:ok, code, out, c} ->
        {code, out, c}

      :error ->
        compile_function_call(module_name, name, args, env, counter, arity, c_name)
    end
  end

  defp compile_function_call(module_name, name, args, env, counter, arity, c_name) do
    if length(args) == arity and NativeFunctionCall.call?({module_name, name}, env) do
      NativeFunctionCall.compile(module_name, name, args, env, counter)
    else
      compile_boxed(module_name, name, args, env, counter, arity, c_name)
    end
  end

  @spec compile_closure(String.t(), [Types.ir_expr()], Types.compile_env(), Types.compile_counter()) ::
          Types.compile_result()
  def compile_closure(closure_var, args, env, counter) do
    {arg_code, arg_vars, counter} =
      Enum.reduce(args, {"", [], counter}, fn arg_expr, {code_acc, vars_acc, c} ->
        {code, var, c2} = Host.compile_expr(arg_expr, env, c)
        {code_acc <> "\n  " <> code, vars_acc ++ [var], c2}
      end)

    next = counter + 1
    out = "tmp_#{next}"
    argc = length(arg_vars)
    args_array = "call_args_#{next}"
    arg_list = Enum.join(arg_vars, ", ")

    releases =
      arg_vars
      |> Enum.map_join("\n  ", fn var -> "elmc_release(#{var});" end)

    code = """
    #{arg_code}
      ElmcValue *#{args_array}[#{max(argc, 1)}] = { #{arg_list} };
      ElmcValue *#{out} = elmc_closure_call(#{closure_var}, #{args_array}, #{argc});
      #{releases}
    """

    {code, out, next}
  end

  @spec compile_var(String.t(), Types.compile_env(), Types.compile_counter()) :: Types.compile_result()
  def compile_var(name, env, counter) do
    next = counter + 1
    var = "tmp_#{next}"

    case {EnvBindings.native_int_binding(env, name), EnvBindings.native_bool_binding(env, name),
          EnvBindings.native_float_binding(env, name)} do
      {native_ref, _, _} when is_binary(native_ref) ->
        {"ElmcValue *#{var} = elmc_new_int(#{native_ref});", var, next}

      {_, native_ref, _} when is_binary(native_ref) ->
        {"ElmcValue *#{var} = elmc_new_bool(#{native_ref});", var, next}

      {_, _, native_ref} when is_binary(native_ref) ->
        {"ElmcValue *#{var} = elmc_new_float(#{native_ref});", var, next}

      {nil, nil, nil} ->
        case Map.fetch(env, name) do
          {:ok, {:native_record, fields}} when is_map(fields) ->
            compile_native_record_box(var, name, fields, env, next)

          {:ok, {:forward_ref, ref}} when is_binary(ref) ->
            {"ElmcValue *#{var} = elmc_forward_ref_get(#{ref});", var, next}

          {:ok, {:forward_ref_slot, slot}} when is_binary(slot) ->
            {"ElmcValue *#{var} = elmc_forward_ref_get(#{slot});", var, next}

          {:ok, {:direct_fragment, fragment}} ->
            {frag_code, frag_var, next2} = Host.compile_expr(fragment, env, counter)
            retain_next = next2 + 1
            retain_var = "tmp_#{retain_next}"

            {"#{frag_code}  ElmcValue *#{retain_var} = elmc_retain(#{frag_var});\n  elmc_release(#{frag_var});",
             retain_var, retain_next}

          {:ok, source} when is_binary(source) ->
            if EnvBindings.boxed_int_binding?(env, name) or
                 EnvBindings.boxed_string_binding?(env, name) do
              {"ElmcValue *#{var} = elmc_retain(#{source});", var, next}
            else
              {"ElmcValue *#{var} = #{source} ? elmc_retain(#{source}) : elmc_int_zero();", var,
               next}
            end

          :error ->
            case BuiltinOperators.call(name, [], env, counter) do
              nil ->
                module_name = Map.get(env, :__module__, "Main")
                function_arities = Map.get(env, :__function_arities__, %{})
                arity = Map.get(function_arities, {module_name, name}, 0)

                if arity > 0 do
                  top_level_closure(module_name, name, arity, var, next)
                else
                  compile_zero_arg_constant(module_name, name, env, counter, var, next)
                end

              result ->
                result
            end
        end
    end
  end

  @spec compile_zero_arg_constant(
          String.t(),
          String.t(),
          Types.compile_env(),
          Types.compile_counter(),
          String.t(),
          Types.compile_counter()
        ) :: Types.compile_result()
  defp compile_zero_arg_constant(module_name, name, env, counter, var, next) do
    case ConstantInt.compile_boxed_call(module_name, name, [], env, counter) do
      {:ok, code, out, c} -> {code, out, c}
      :error -> {"ElmcValue *#{var} = #{Util.module_fn_name(module_name, name)}(NULL, 0);", var, next}
    end
  end

  @spec top_level_closure(String.t(), String.t(), non_neg_integer(), String.t(), Types.compile_counter()) ::
          Types.compile_result()
  def top_level_closure(module_name, name, arity, out, next) do
    c_name = Util.module_fn_name(module_name, name)
    signature = {:top_level_ref, module_name, name, arity}
    {closure_fn_name, new?} = closure_function_name(signature, "elmc_top_level_ref")

    if new? do
      closure_fn = """
      static ElmcValue *#{closure_fn_name}(ElmcValue **args, int argc, ElmcValue **captures, int capture_count) {
        (void)captures;
        (void)capture_count;
        return #{c_name}(args, argc);
      }
      """

      existing_lambdas = Process.get(:elmc_lambdas, [])
      Process.put(:elmc_lambdas, [closure_fn | existing_lambdas])
    end

    code = """
    ElmcValue *cap_#{next}[1] = { NULL };
      ElmcValue *#{out} = elmc_closure_new(#{closure_fn_name}, #{arity}, 0, cap_#{next});
    """

    {code, out, next}
  end

  defp partial_closure(module_name, name, arity, arg_vars, out, next) do
    c_name = Util.module_fn_name(module_name, name)
    bound_count = length(arg_vars)
    remaining = max(arity - bound_count, 0)
    signature = {:partial_ref, module_name, name, arity, bound_count}
    {closure_fn_name, new?} = closure_function_name(signature, "elmc_partial_ref")

    call_bindings =
      0..(arity - 1)
      |> Enum.map_join("\n  ", fn index ->
        cond do
          index < bound_count ->
            "call_args[#{index}] = (capture_count > #{index}) ? captures[#{index}] : NULL;"

          true ->
            rest_index = index - bound_count
            "call_args[#{index}] = (argc > #{rest_index}) ? args[#{rest_index}] : NULL;"
        end
      end)

    if new? do
      closure_fn = """
      static ElmcValue *#{closure_fn_name}(ElmcValue **args, int argc, ElmcValue **captures, int capture_count) {
        (void)args;
        (void)argc;
        (void)captures;
        (void)capture_count;
        ElmcValue *call_args[#{max(arity, 1)}] = {0};
        #{call_bindings}
        return #{c_name}(call_args, #{arity});
      }
      """

      existing_lambdas = Process.get(:elmc_lambdas, [])
      Process.put(:elmc_lambdas, [closure_fn | existing_lambdas])
    end

    capture_list =
      case arg_vars do
        [] -> "NULL"
        vars -> Enum.join(vars, ", ")
      end

    code = """
    ElmcValue *cap_#{next}[#{max(bound_count, 1)}] = { #{capture_list} };
      ElmcValue *#{out} = elmc_closure_new(#{closure_fn_name}, #{remaining}, #{bound_count}, cap_#{next});
    """

    {code, out, next}
  end

  @spec compile_native_record_box(
          String.t(),
          String.t(),
          %{String.t() => String.t()},
          Types.compile_env(),
          Types.compile_counter()
        ) :: Types.compile_result()
  @spec capture_native_record(Types.compile_env(), String.t(), %{String.t() => String.t()}) ::
          String.t()
  def capture_native_record(env, name, fields) when is_map(fields) do
    field_names = native_record_field_names(env, name, fields)
    env = ensure_native_record_var_type(env, name, field_names)

    if native_record_all_int_fields?(env, name, field_names) do
      count = length(field_names)

      names_array =
        field_names
        |> Enum.map_join(", ", fn field -> "\"#{Util.escape_c_string(field)}\"" end)

      values_array =
        field_names
        |> Enum.map_join(", ", fn field -> Map.fetch!(fields, field) end)

      "elmc_record_new_ints(#{count}, (const char *[]){ #{names_array} }, (elmc_int_t[]){ #{values_array} })"
    else
      raise ArgumentError,
            "cannot capture native record #{inspect(name)} with non-Int fields in a closure; pass fields individually"
    end
  end

  defp compile_native_record_box(var, name, fields, env, next) when is_map(fields) do
    field_names = native_record_field_names(env, name, fields)
    env = ensure_native_record_var_type(env, name, field_names)

    if field_names == [] or
         not Enum.all?(field_names, fn field ->
           ref = Map.get(fields, field)
           is_binary(ref) and ref != ""
         end) do
      raise ArgumentError,
            "cannot box native record #{inspect(name)} for runtime calls: #{inspect(fields)}"
    end

    if native_record_all_int_fields?(env, name, field_names) do
      compile_native_record_box_ints(var, field_names, fields, next)
    else
      compile_native_record_box_mixed(var, name, field_names, fields, env, next)
    end
  end

  defp native_record_all_int_fields?(env, name, field_names) do
    case RecordFields.record_type_name(env, name) do
      nil ->
        Enum.all?(field_names, fn field ->
          case RecordFields.field_type(env, name, field) do
            nil -> true
            "Int" -> true
            _ -> false
          end
        end)

      _type ->
        Enum.all?(field_names, fn field ->
          RecordFields.field_type(env, name, field) in [nil, "Int"]
        end) and
          Enum.any?(field_names, fn field ->
            RecordFields.field_type(env, name, field) == "Int"
          end)
    end
  end

  defp ensure_native_record_var_type(env, name, field_names) do
    case RecordFields.record_type_name(env, name) do
      type when is_binary(type) ->
        EnvBindings.put_var_type(env, name, type)

      _ ->
        case Expr.record_type_for_field_names(field_names, env) do
          nil -> env
          type -> EnvBindings.put_var_type(env, name, type)
        end
    end
  end

  defp compile_native_record_box_ints(var, field_names, fields, next) do
    count = length(field_names)

    names_array =
      field_names
      |> Enum.map_join(", ", fn field -> "\"#{Util.escape_c_string(field)}\"" end)

    values_array =
      field_names
      |> Enum.map_join(", ", fn field -> Map.fetch!(fields, field) end)

    code = """
    const char *rec_names_#{next}[#{count}] = { #{names_array} };
      elmc_int_t rec_values_#{next}[#{count}] = { #{values_array} };
      ElmcValue *#{var} = elmc_record_new_ints(#{count}, rec_names_#{next}, rec_values_#{next});
    """

    {code, var, next}
  end

  defp compile_native_record_box_mixed(var, name, field_names, fields, env, next) do
    count = length(field_names)

    names_array =
      field_names
      |> Enum.map_join(", ", fn field -> "\"#{Util.escape_c_string(field)}\"" end)

    {field_code, value_vars, next} =
      Enum.reduce(field_names, {"", [], next}, fn field, {code_acc, vars_acc, c} ->
        ref = Map.fetch!(fields, field)
        box = native_record_field_box_expr(env, name, field, ref)
        tmp = "rec_field_#{c}"
        code = "  ElmcValue *#{tmp} = #{box};\n"
        {code_acc <> code, vars_acc ++ [tmp], c + 1}
      end)

    values_array = Enum.join(value_vars, ", ")

    code = """
    #{field_code}
      const char *rec_names_#{next}[#{count}] = { #{names_array} };
      ElmcValue *rec_values_#{next}[#{count}] = { #{values_array} };
      ElmcValue *#{var} = elmc_record_new_take(#{count}, rec_names_#{next}, rec_values_#{next});
    """

    {code, var, next}
  end

  defp native_record_field_box_expr(env, record_name, field, ref) do
    case RecordFields.field_kind_from_env(env, record_name, field) ||
           RecordFields.field_type(env, record_name, field) do
      "Bool" -> "elmc_new_bool(#{ref})"
      "Float" -> "elmc_new_float((double)#{ref})"
      "String" -> "elmc_new_string(#{ref})"
      _ -> "elmc_new_int(#{ref})"
    end
  end

  @spec native_record_field_names(Types.compile_env(), String.t(), %{String.t() => String.t()}) ::
          [String.t()]
  defp native_record_field_names(env, name, fields) do
    shapes = Map.get(env, :__record_shapes__, %{})

    case Map.get(shapes, name) do
      names when is_list(names) ->
        Enum.filter(names, &Map.has_key?(fields, &1))

      _ ->
        fields
        |> Map.keys()
        |> Enum.sort()
    end
  end

  @spec closure_function_name(closure_signature(), String.t()) :: {String.t(), boolean()}
  defp closure_function_name(signature, prefix) do
    defs = Process.get(:elmc_lambda_defs, %{})

    case Map.fetch(defs, signature) do
      {:ok, name} ->
        {name, false}

      :error ->
        closure_id = Process.get(:elmc_lambda_counter, 0) + 1
        Process.put(:elmc_lambda_counter, closure_id)
        name = "#{prefix}_#{closure_id}"
        Process.put(:elmc_lambda_defs, Map.put(defs, signature, name))
        {name, true}
    end
  end

  defp compile_boxed(module_name, name, args, env, counter, arity, c_name) do
    before_args_probe =
      DebugProbes.call_probe(env, module_name, name, :before_args) |> DebugProbes.region()

    {arg_code, arg_vars, counter} =
      Enum.reduce(args, {"", [], counter}, fn arg_expr, {code_acc, vars_acc, c} ->
        {code, var, c2} = Host.compile_expr(arg_expr, env, c)
        {code_acc <> "\n  " <> code, vars_acc ++ [var], c2}
      end)

    next = counter + 1
    out = "tmp_#{next}"
    argc = length(arg_vars)

    after_args_probe =
      DebugProbes.call_probe(env, module_name, name, :after_args) |> DebugProbes.region()

    after_call_probe =
      DebugProbes.call_probe(env, module_name, name, :after_call) |> DebugProbes.region()

    releases =
      arg_vars
      |> Enum.map_join("\n  ", fn var -> "elmc_release(#{var});" end)

    code =
      cond do
        arity > 0 and argc < arity ->
          {closure_code, _out, _next} =
            partial_closure(module_name, name, arity, arg_vars, out, next)

          """
          #{before_args_probe}
          #{arg_code}
            #{after_args_probe}
            #{closure_code}
            #{after_call_probe}
            #{releases}
          """

        arity > 0 and argc > arity ->
          {first_vars, rest_vars} = Enum.split(arg_vars, arity)
          first_args = Enum.join(first_vars, ", ")
          rest_args = Enum.join(rest_vars, ", ")
          head_var = "head_#{next}"
          first_args_var = "call_args_#{next}"
          rest_args_var = "extra_args_#{next}"

          """
          #{before_args_probe}
          #{arg_code}
            #{after_args_probe}
            ElmcValue *#{first_args_var}[#{max(length(first_vars), 1)}] = { #{first_args} };
            ElmcValue *#{head_var} = #{c_name}(#{first_args_var}, #{length(first_vars)});
            ElmcValue *#{rest_args_var}[#{max(length(rest_vars), 1)}] = { #{rest_args} };
            ElmcValue *#{out} = elmc_apply_extra(#{head_var}, #{rest_args_var}, #{length(rest_vars)});
            #{after_call_probe}
            elmc_release(#{head_var});
            #{releases}
          """

        true ->
          args_var = "call_args_#{next}"
          arg_list = Enum.join(arg_vars, ", ")

          """
          #{before_args_probe}
          #{arg_code}
            #{after_args_probe}
            ElmcValue *#{args_var}[#{max(argc, 1)}] = { #{arg_list} };
            ElmcValue *#{out} = #{c_name}(#{args_var}, #{argc});
            #{after_call_probe}
            #{releases}
          """
      end

    {code, out, next}
  end

  @spec compile_cross_module(String.t(), [Types.ir_expr()], Types.compile_env(), Types.compile_counter()) ::
          Types.compile_result()
  def compile_cross_module(target, args, env, counter) do
    case Util.split_qualified_function_target(target) do
      {module_name, name} -> compile(module_name, name, args, env, counter)
      nil -> compile(target, "", args, env, counter)
    end
  end
end
