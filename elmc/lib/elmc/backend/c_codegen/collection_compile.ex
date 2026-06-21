defmodule Elmc.Backend.CCodegen.CollectionCompile do
  @moduledoc false

  alias Elmc.Backend.CCodegen.CaseCompile
  alias Elmc.Backend.CCodegen.BuiltinUnion
  alias Elmc.Backend.CCodegen.ConstantInt
  alias Elmc.Backend.CCodegen.DebugProbes
  alias Elmc.Backend.CCodegen.EnvBindings
  alias Elmc.Backend.CCodegen.Host
  alias Elmc.Backend.CCodegen.RcRuntimeEmit
  alias Elmc.Backend.CCodegen.Native.Int, as: NativeInt
  alias Elmc.Backend.CCodegen.Types
  alias Elmc.Backend.CCodegen.ValueSlots

  @spec compile(Types.ir_collection_expr(), Types.compile_env(), Types.compile_counter()) ::
          Types.compile_result()
  def compile(%{op: :tuple2, left: left, right: right} = expr, env, counter) do
    case BuiltinUnion.try_compile_tuple2(expr, env, counter) do
      {:ok, result} ->
        result

      :error ->
        compile_generic_tuple2(left, right, env, counter)
    end
  end

  def compile(%{op: :list_literal, items: items}, env, counter) do
    case static_list_literal(items, env, counter) do
      {:ok, result} -> result
      :error -> compile_dynamic_list_literal(items, env, counter)
    end
  end

  def compile(%{op: :tuple_second, arg: arg}, env, counter) when is_binary(arg) do
    compile_bound_tuple_second(env, arg, counter)
  end

  def compile(%{op: :tuple_second_expr, arg: %{op: :var, name: name}}, env, counter) do
    compile_bound_tuple_second(env, name, counter)
  end

  def compile(%{op: :tuple_second_expr, arg: arg_expr}, env, counter) do
    compile_expr_tuple_access(arg_expr, "elmc_tuple_second", env, counter)
  end

  def compile(%{op: :tuple_first, arg: arg}, env, counter) when is_binary(arg) do
    compile_bound_tuple_first(env, arg, counter)
  end

  def compile(%{op: :tuple_first, arg: arg_expr}, env, counter) when is_map(arg_expr) do
    compile(%{op: :tuple_first_expr, arg: arg_expr}, env, counter)
  end

  def compile(%{op: :tuple_first_expr, arg: %{op: :var, name: name}}, env, counter) do
    compile_bound_tuple_first(env, name, counter)
  end

  def compile(%{op: :tuple_first_expr, arg: arg_expr}, env, counter) do
    compile_expr_tuple_access(arg_expr, "elmc_tuple_first", env, counter)
  end

  def compile(%{op: :string_length, arg: arg}, env, counter) when is_binary(arg) do
    compile_bound_string_length(env, arg, counter)
  end

  def compile(%{op: :string_length_expr, arg: %{op: :var, name: name}}, env, counter) do
    compile_bound_string_length(env, name, counter)
  end

  def compile(%{op: :string_length_expr, arg: arg_expr}, env, counter) do
    compile_expr_unary(arg_expr, "elmc_new_int_take(elmc_string_length", env, counter)
  end

  def compile(%{op: :char_from_code, arg: arg}, env, counter) when is_binary(arg) do
    compile_bound_char_from_code(env, arg, counter)
  end

  def compile(%{op: :char_from_code_expr, arg: arg_expr}, env, counter) do
    {arg_code, arg_var, counter} = Host.compile_expr(arg_expr, env, counter)
    {var, next} = CaseCompile.fresh_var(counter, env)

    code = """
    #{arg_code}
      #{boxed_slot_assign(var, "elmc_char_from_code(#{arg_var})")}
      elmc_release(#{arg_var});
    """

    {code, var, next}
  end

  defp compile_generic_tuple2(left, right, env, counter) do
    child_env = Map.delete(env, :__into_out__)

    if tuple2_native_int_operands?(left, right, env) do
      {left_code, left_ref, counter} = Host.compile_native_int_expr(left, child_env, counter)
      {right_code, right_ref, counter} = Host.compile_native_int_expr(right, child_env, counter)
      {out, next, _} = CaseCompile.result_out_binding(env, counter)

      code = """
      #{left_code}
      #{right_code}
      #{RcRuntimeEmit.assign_call(env, out, "elmc_tuple2_ints", "#{left_ref}, #{right_ref}")}
      """

      {code, out, next}
    else
      {left_code, left_var, counter} = Host.compile_expr(left, child_env, counter)
      {right_code, right_var, counter} = Host.compile_expr(right, child_env, counter)
      {out, next, _} = CaseCompile.result_out_binding(env, counter)
      nulls = ValueSlots.transfer_and_null_refs([left_var, right_var])

      code = """
      #{left_code}
      #{right_code}
      #{RcRuntimeEmit.assign_call(env, out, "elmc_tuple2_take", "#{left_var}, #{right_var}")}
      #{nulls}
      """

      {code, out, next}
    end
  end

  defp tuple2_native_int_operands?(left, right, env) do
    NativeInt.expr?(left, env) and NativeInt.expr?(right, env) and
      not tuple2_unspecialized_var?(left, env) and
      not tuple2_unspecialized_var?(right, env)
  end

  defp tuple2_unspecialized_var?(%{op: :var, name: name}, env),
    do: not ConstantInt.native_let_value?(%{op: :var, name: name}, env)

  defp tuple2_unspecialized_var?(_expr, _env), do: false

  defp compile_dynamic_list_literal(items, env, counter) do
    item_env = Map.delete(env, :__into_out__)

    {item_code, item_vars, counter} =
      Enum.reduce(items, {"", [], counter}, fn item, {acc_code, vars, c} ->
        {code, var, c1} = Host.compile_expr(item, item_env, c)
        {acc_code <> "\n  " <> code, vars ++ [var], c1}
      end)

    {out, next, _} = CaseCompile.result_out_binding(env, counter)
    list_items_id = counter + 1
    count = length(item_vars)
    array_name = "list_items_#{list_items_id}"
    item_list = Enum.join(item_vars, ", ")
    list_probe = DebugProbes.list_literal_probe(env, out, list_items_id)
    nulls = if count == 0, do: "", else: ValueSlots.transfer_and_null_refs(Enum.uniq(item_vars))

    code =
      if count == 0 do
        """
        #{boxed_slot_assign(out, "elmc_list_nil()")}
          #{list_probe}
        """
      else
        """
        #{item_code}
          ElmcValue *#{array_name}[#{count}] = { #{item_list} };
          #{RcRuntimeEmit.assign_call(env, out, "elmc_list_from_values_take", "#{array_name}, #{count}")}
          #{nulls}
          #{list_probe}
        """
      end

    {code, out, max(next, list_items_id + 1)}
  end

  defp static_list_literal(items, env, counter) when length(items) >= 4 do
    cond do
      Enum.all?(items, &static_int_literal?/1) ->
        {:ok, compile_static_int_list(items, env, counter)}

      Enum.all?(items, &static_tuple2_int_literal?/1) ->
        {:ok, compile_static_tuple2_int_list(items, env, counter)}

      true ->
        :error
    end
  end

  defp static_list_literal(_items, _env, _counter), do: :error

  defp compile_static_int_list(items, env, counter) do
    {out, next, _} = CaseCompile.result_out_binding(env, counter)
    values_id = counter + 1
    count = length(items)
    values_name = "list_int_values_#{values_id}"
    list_probe = DebugProbes.list_literal_probe(env, out, values_id)

    values =
      items
      |> Enum.map(&Integer.to_string(&1.value))
      |> Enum.join(", ")

    code = """
      static const elmc_int_t #{values_name}[#{count}] = { #{values} };
      #{RcRuntimeEmit.assign_call(env, out, "elmc_list_from_int_array", "#{values_name}, #{count}")}
      #{list_probe}
    """

    {code, out, max(next, values_id + 1)}
  end

  defp compile_static_tuple2_int_list(items, env, counter) do
    {out, next, _} = CaseCompile.result_out_binding(env, counter)
    values_id = counter + 1
    count = length(items)
    values_name = "list_tuple2_values_#{values_id}"
    list_probe = DebugProbes.list_literal_probe(env, out, values_id)

    values =
      items
      |> Enum.map(fn %{left: left, right: right} -> "{ #{left.value}, #{right.value} }" end)
      |> Enum.join(", ")

    code = """
      static const elmc_int_t #{values_name}[#{count}][2] = { #{values} };
      #{RcRuntimeEmit.assign_call(env, out, "elmc_list_from_tuple2_int_array", "#{values_name}, #{count}")}
      #{list_probe}
    """

    {code, out, max(next, values_id + 1)}
  end

  defp static_int_literal?(%{op: :int_literal, value: value}) when is_integer(value), do: true
  defp static_int_literal?(_), do: false

  defp static_tuple2_int_literal?(%{
         op: :tuple2,
         left: %{op: :int_literal, value: left},
         right: %{op: :int_literal, value: right}
       })
       when is_integer(left) and is_integer(right),
       do: true

  defp static_tuple2_int_literal?(_), do: false

  @spec resolve_env_source(Types.compile_env(), String.t(), Types.compile_counter()) ::
          {String.t(), Types.env_source_ref(), Types.compile_counter()}
  defp resolve_env_source(env, name, counter) do
    case Map.get(env, name) do
      ref when is_binary(ref) ->
        {"", ref, counter}

      _ ->
        Host.compile_expr(%{op: :var, name: name}, env, counter)
    end
  end

  @spec compile_bound_tuple_second(Types.compile_env(), String.t(), Types.compile_counter()) ::
          Types.compile_result()
  defp compile_bound_tuple_second(env, name, counter) do
    {source_code, source, counter} = resolve_env_source(env, name, counter)
    {var, next} = CaseCompile.fresh_var(counter, env)

    code = """
    #{source_code}  #{boxed_slot_assign(var, "elmc_tuple_second(#{source})")}
    """

    if RcRuntimeEmit.rc_allocator_emit_mode?(env), do: ValueSlots.track(var)

    {code, var, next}
  end

  @spec compile_bound_tuple_first(Types.compile_env(), String.t(), Types.compile_counter()) ::
          Types.compile_result()
  defp compile_bound_tuple_first(env, name, counter) do
    {source_code, source, counter} = resolve_env_source(env, name, counter)
    {var, next} = CaseCompile.fresh_var(counter, env)

    code = """
    #{source_code}  #{boxed_slot_assign(var, "elmc_tuple_first(#{source})")}
    """

    if RcRuntimeEmit.rc_allocator_emit_mode?(env), do: ValueSlots.track(var)

    {code, var, next}
  end

  @spec compile_bound_string_length(Types.compile_env(), String.t(), Types.compile_counter()) ::
          Types.compile_result()
  defp compile_bound_string_length(env, name, counter) do
    {source_code, source, counter} = resolve_env_source(env, name, counter)
    {var, next} = CaseCompile.fresh_var(counter, env)

    code =
      source_code <>
        RcRuntimeEmit.assign_call(env, var, "elmc_new_int", "elmc_string_length(#{source})")

    {code, var, next}
  end

  @spec compile_bound_char_from_code(Types.compile_env(), String.t(), Types.compile_counter()) ::
          Types.compile_result()
  defp compile_bound_char_from_code(env, name, counter) do
    {source_code, source, counter} = resolve_env_source(env, name, counter)
    {var, next} = CaseCompile.fresh_var(counter, env)

    char_expr =
      case EnvBindings.native_int_binding(env, name) do
        ref when is_binary(ref) -> "elmc_char_from_code_int(#{ref})"
        _ -> "elmc_char_from_code(#{source})"
      end

    code = """
    #{source_code}  #{boxed_slot_assign(var, char_expr)}
    """

    {code, var, next}
  end

  @spec compile_expr_tuple_access(
          Types.ir_expr(),
          String.t(),
          Types.compile_env(),
          Types.compile_counter()
        ) :: Types.compile_result()
  defp compile_expr_tuple_access(arg_expr, c_fn, env, counter) do
    {arg_code, arg_var, counter} = Host.compile_expr(arg_expr, env, counter)
    {var, next} = CaseCompile.fresh_var(counter, env)

    code = """
    #{arg_code}
      #{boxed_slot_assign(var, "#{c_fn}(#{arg_var})")}
      elmc_release(#{arg_var});
    """

    if RcRuntimeEmit.rc_allocator_emit_mode?(env), do: ValueSlots.track(var)
    if RcRuntimeEmit.rc_allocator_emit_mode?(env), do: ValueSlots.release(arg_var)

    {code, var, next}
  end

  @spec compile_expr_unary(
          Types.ir_expr(),
          String.t(),
          Types.compile_env(),
          Types.compile_counter()
        ) :: Types.compile_result()
  defp compile_expr_unary(arg_expr, c_expr_prefix, env, counter) do
    {arg_code, arg_var, counter} = Host.compile_expr(arg_expr, env, counter)
    {var, next} = CaseCompile.fresh_var(counter, env)

    code = """
    #{arg_code}
      #{boxed_slot_assign(var, "#{c_expr_prefix}(#{arg_var}))")}
      elmc_release(#{arg_var});
    """

    {code, var, next}
  end

  defp boxed_slot_assign(var, rhs), do: ValueSlots.boxed_decl(var, rhs)
end
