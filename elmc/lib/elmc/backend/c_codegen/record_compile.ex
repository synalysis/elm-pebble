defmodule Elmc.Backend.CCodegen.RecordCompile do
  @moduledoc false

  alias Elmc.Backend.CCodegen.DebugProbes
  alias Elmc.Backend.CCodegen.Expr
  alias Elmc.Backend.CCodegen.FunctionCallCompile
  alias Elmc.Backend.CCodegen.Host
  alias Elmc.Backend.CCodegen.Types
  alias Elmc.Backend.CCodegen.Util

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

  def compile(%{op: :field_call, arg: %{op: :var, name: name}, field: field, args: args}, env, counter)
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
      ordered_fields |> Enum.map(fn f -> "\"#{Util.escape_c_string(f.name)}\"" end) |> Enum.join(", ")

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
      Enum.reduce(ordered_fields, {"", [], counter}, fn field, {code_acc, refs_acc, c} ->
        {code, ref, c2} = Host.compile_native_int_expr(field.expr, env, c)
        {code_acc <> "\n  " <> code, refs_acc ++ [ref], c2}
      end)

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
    {field_code, field_vars, counter} =
      Enum.reduce(ordered_fields, {"", [], counter}, fn field, {code_acc, vars_acc, c} ->
        {code, var, c2} = Host.compile_expr(field.expr, env, c)
        {code_acc <> "\n  " <> code, vars_acc ++ [{field.name, var}], c2}
      end)

    next = counter + 1
    out = "tmp_#{next}"
    values_array = field_vars |> Enum.map(fn {_name, var} -> var end) |> Enum.join(", ")

    code = """
    #{field_code}
      const char *rec_names_#{next}[#{max(field_count, 1)}] = { #{names_array} };
      ElmcValue *rec_values_#{next}[#{max(field_count, 1)}] = { #{values_array} };
        ElmcValue *#{out} = elmc_record_new_take(#{field_count}, rec_names_#{next}, rec_values_#{next});
    """

    {code, out, next}
  end

  @spec compile_update(
          Types.ir_expr(),
          Types.ir_record_fields(),
          Types.compile_env(),
          Types.compile_counter()
        ) :: Types.compile_result()
  defp compile_update(base, fields, env, counter) do
    {base_code, base_var, counter} = Host.compile_expr(base, env, counter)

    {update_code, current_var, counter} =
      Enum.reduce(fields, {"", base_var, counter}, fn field, {code_acc, current, c} ->
        {field_code, field_var, c2} = Host.compile_expr(field.expr, env, c)
        next = c2 + 1
        out = "tmp_#{next}"

        code = """
        #{field_code}
          ElmcValue *#{out} = elmc_record_update(#{current}, "#{Util.escape_c_string(field.name)}", #{field_var});
          elmc_release(#{current});
          elmc_release(#{field_var});
        """

        {code_acc <> "\n  " <> code, out, next}
      end)

    {base_code <> update_code, current_var, counter}
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

    after_probe = env |> DebugProbes.field_probe(record_name, field, :after) |> DebugProbes.region()

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
end
