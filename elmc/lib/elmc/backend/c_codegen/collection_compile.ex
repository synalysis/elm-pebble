defmodule Elmc.Backend.CCodegen.CollectionCompile do
  @moduledoc false

  alias Elmc.Backend.CCodegen.CaseCompile
  alias Elmc.Backend.CCodegen.BuiltinUnion
  alias Elmc.Backend.CCodegen.ConstantInt
  alias Elmc.Backend.CCodegen.DebugProbes
  alias Elmc.Backend.CCodegen.EnvBindings
  alias Elmc.Backend.CCodegen.Host
  alias Elmc.Backend.CCodegen.ListLoopCodegen
  alias Elmc.Backend.CCodegen.RcRuntimeEmit
  alias Elmc.Backend.CCodegen.Native.Int, as: NativeInt
  alias Elmc.Backend.CCodegen.Types
  alias Elmc.Backend.CCodegen.ValueSlots
  alias Elmc.Backend.CCodegen.VarAnalysis

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
      :error ->
        case static_record_list_literal(items, env, counter) do
          {:ok, result} -> result
          :error -> compile_dynamic_list_literal(items, env, counter)
        end
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
    child_env = RcRuntimeEmit.strip_function_tail_scope(env)
    {arg_code, arg_var, counter} = Host.compile_expr(arg_expr, child_env, counter)
    {var, next} = CaseCompile.fresh_var(counter, env)

    alloc_code =
      if RcRuntimeEmit.rc_allocator_emit_mode?(env) do
        """
        #{ValueSlots.boxed_null_decl(var)}
        #{RcRuntimeEmit.check_rc_take(var, "elmc_new_int", "elmc_string_length(#{RcRuntimeEmit.value_expr(arg_var)})")}
        """
      else
        RcRuntimeEmit.check_rc_take(var, "elmc_new_int", "elmc_string_length(#{RcRuntimeEmit.value_expr(arg_var)})")
      end

    code = """
    #{arg_code}
      #{alloc_code}
      #{ValueSlots.release_stmt(arg_var)};
    """

    {code, var, next}
  end

  def compile(%{op: :char_from_code, arg: arg}, env, counter) when is_binary(arg) do
    compile_bound_char_from_code(env, arg, counter)
  end

  def compile(%{op: :char_from_code_expr, arg: arg_expr}, env, counter) do
    child_env = RcRuntimeEmit.strip_function_tail_scope(env)
    {arg_code, arg_var, counter} = Host.compile_expr(arg_expr, child_env, counter)
    {var, next} = CaseCompile.fresh_var(counter, env)

    code = """
    #{arg_code}
      #{RcRuntimeEmit.assign_call(env, var, "elmc_char_from_code", arg_var)}
      #{ValueSlots.release_stmt(arg_var)};
    """

    {code, var, next}
  end

  defp compile_generic_tuple2(left, right, env, counter) do
    child_env = RcRuntimeEmit.strip_function_tail_scope(env)
    compile_right_first? = tuple2_case_on_pre_update_record?(left, right)

    if tuple2_native_int_operands?(left, right, env) do
      {left_code, left_ref, counter} = Host.compile_native_int_expr(left, child_env, counter)
      {right_code, right_ref, counter} = Host.compile_native_int_expr(right, child_env, counter)

      {out, next, _declare?} =
        if RcRuntimeEmit.rc_allocator_emit_mode?(env) do
          {slot, c} = RcRuntimeEmit.compile_result_slot(child_env, counter)
          {slot, c, false}
        else
          CaseCompile.result_out_binding(env, counter)
        end

      code = """
      #{left_code}
      #{right_code}
      #{RcRuntimeEmit.assign_call(env, out, "elmc_tuple2_ints", "#{left_ref}, #{right_ref}")}
      """

      if RcRuntimeEmit.rc_allocator_emit_mode?(env), do: ValueSlots.track(out)
      {code, out, next}
    else
      left_env = Map.put(child_env, :__transfer_operand__, true)
      right_env = Map.put(child_env, :__transfer_operand__, true)

      {left_code, left_var, right_code, right_var, counter} =
        if compile_right_first? do
          {right_code, right_var, c1} = Host.compile_expr(right, right_env, counter)
          {left_code, left_var, c2} = Host.compile_expr(left, left_env, c1)
          {left_code, left_var, right_code, right_var, c2}
        else
          {left_code, left_var, c1} = Host.compile_expr(left, left_env, counter)
          {right_code, right_var, c2} = Host.compile_expr(right, right_env, c1)
          {left_code, left_var, right_code, right_var, c2}
        end

      emit_code =
        if compile_right_first?, do: right_code <> left_code, else: left_code <> right_code

      {out, next, _declare_out?} =
        if RcRuntimeEmit.rc_allocator_emit_mode?(env) do
          {slot, c} = RcRuntimeEmit.compile_result_slot(env, counter)
          {slot, c, false}
        else
          CaseCompile.result_out_binding(env, counter)
        end

      ValueSlots.register_tuple_projection(left_var, out, :first)
      ValueSlots.register_tuple_projection(right_var, out, :second)

      out_ref = ValueSlots.resolve_result_slot(out)

      null_refs =
        [left_var, right_var]
        |> Enum.uniq()
        |> Enum.reject(fn var -> ValueSlots.resolve_result_slot(var) == out_ref end)

      nulls = ValueSlots.transfer_and_null_refs(null_refs)

      tuple2_assign =
        if RcRuntimeEmit.function_out_ref?(out) and RcRuntimeEmit.function_out_ref?(right_var) do
          {pair_var, c2} = CaseCompile.fresh_tmp_var(next, env)
          {cmd_var, _} = CaseCompile.fresh_tmp_var(c2, env)

          """
          ElmcValue *#{pair_var} = NULL;
          {
            ElmcValue *#{cmd_var} = #{RcRuntimeEmit.function_out_deref()};
            Rc = elmc_tuple2_take(&#{pair_var}, #{RcRuntimeEmit.value_expr(left_var)}, #{cmd_var});
            CHECK_RC(Rc);
          }
          #{RcRuntimeEmit.function_out_deref()} = #{pair_var};
          """
          |> String.trim()
        else
          RcRuntimeEmit.assign_call(
            env,
            out,
            "elmc_tuple2_take",
            "#{RcRuntimeEmit.value_expr(left_var)}, #{RcRuntimeEmit.value_expr(right_var)}"
          )
        end

      code = """
      #{emit_code}
      #{tuple2_assign}
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

  # Elm `( { m | f = v }, case m.f of ... )` must read `m.f` from the pre-update
  # record. In-place `elmc_record_update_index_cow_drop` can mutate `m` before the
  # case runs when tuple elements are compiled left-to-right.
  defp tuple2_case_on_pre_update_record?(
         %{op: :record_update, base: %{op: :var, name: base_name}},
         right
       )
       when is_binary(base_name) do
    expr_reads_var_field?(right, base_name)
  end

  defp tuple2_case_on_pre_update_record?(_left, _right), do: false

  defp expr_reads_var_field?(%{op: :field_access, arg: %{op: :var, name: name}}, base_name)
       when is_binary(name) and is_binary(base_name),
       do: name == base_name

  defp expr_reads_var_field?(%{op: :field_access, arg: name}, base_name)
       when is_binary(name) and is_binary(base_name),
       do: name == base_name

  defp expr_reads_var_field?(%{op: :let_in, value_expr: value_expr}, base_name)
       when is_binary(base_name),
       do: expr_reads_var_field?(value_expr, base_name)

  defp expr_reads_var_field?(expr, base_name) when is_map(expr) do
    expr
    |> Map.values()
    |> Enum.any?(&expr_reads_var_field?(&1, base_name))
  end

  defp expr_reads_var_field?(values, base_name) when is_list(values) do
    Enum.any?(values, &expr_reads_var_field?(&1, base_name))
  end

  defp expr_reads_var_field?(_, _), do: false

  defp compile_dynamic_list_literal(items, env, counter) do
    item_env = RcRuntimeEmit.strip_function_tail_scope(env)

    if Enum.all?(items, &all_native_primitive_record_literal?/1) do
      compile_record_array_list_literal(items, item_env, env, counter)
    else
      compile_generic_list_literal(items, item_env, env, counter)
    end
  end

  defp compile_generic_list_literal(items, item_env, env, counter) do
    nested_item_env =
      item_env
      |> Map.delete(:__branch_out__)
      |> Map.put(:__transfer_operand__, true)

    multi_use = multi_use_elm_var_names(items)

    {pre_retain_code, copy_map, counter} =
      emit_multi_use_owned_copies(multi_use, nested_item_env, counter)

    {item_code, item_vars, counter, _consumed} =
      Enum.reduce(items, {pre_retain_code, [], counter, MapSet.new()}, fn item,
                                                                          {acc_code, vars, c,
                                                                           consumed} ->
        item_env =
          nested_item_env
          |> item_env_for_multi_use(consumed, copy_map)

        {code, var, c1} = Host.compile_expr(item, item_env, c)

        used =
          item
          |> VarAnalysis.used_vars()
          |> MapSet.intersection(multi_use)

        {acc_code <> "\n  " <> code, vars ++ [var], c1, MapSet.union(consumed, used)}
      end)

    {out, next, _} = CaseCompile.result_out_binding(env, counter)
    list_items_id = counter + 1
    count = length(item_vars)
    array_name = "list_items_#{list_items_id}"
    item_list = item_vars |> Enum.map(&RcRuntimeEmit.value_expr/1) |> Enum.join(", ")
    list_probe = DebugProbes.list_literal_probe(env, out, list_items_id)

    nulls = if count == 0, do: "", else: ValueSlots.transfer_and_null_refs(Enum.uniq(item_vars))

    code =
      cond do
        count == 0 ->
          """
          #{boxed_slot_assign(out, "elmc_list_nil()")}
            #{list_probe}
          """

        Map.get(env, :__concat_map_forward_loop_id__) != nil and count <= 8 ->
          forward_loop_id = Map.get(env, :__concat_map_forward_loop_id__)
          append_code =
            item_vars
            |> Enum.with_index()
            |> Enum.map_join("", fn {var, index} ->
              ListLoopCodegen.emit_forward_list_append(
                forward_loop_id,
                var,
                env: env,
                append_id: forward_loop_id * 100 + index
              )
            end)

          """
          #{item_code}
          #{append_code}
          #{boxed_slot_assign(out, "elmc_list_nil()")}
            #{list_probe}
          """

        true ->
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

  defp static_record_list_literal(items, env, counter) when is_list(items) and items != [] do
    if Enum.all?(items, &all_native_primitive_record_literal?/1) do
      {:ok, compile_record_array_list_literal(items, env, env, counter)}
    else
      :error
    end
  end

  defp static_record_list_literal(_items, _env, _counter), do: :error

  defp compile_record_array_list_literal(items, item_env, env, counter) do
    nested_item_env =
      item_env
      |> Map.delete(:__branch_out__)
      |> Map.put(:__transfer_operand__, true)

    {item_code, item_vars, counter} =
      Enum.reduce(items, {"", [], counter}, fn item, {acc_code, vars, c} ->
        {code, var, c1} = Host.compile_expr(item, nested_item_env, c)
        {acc_code <> "\n  " <> code, vars ++ [var], c1}
      end)

    {out, next, _} = CaseCompile.result_out_binding(env, counter)
    list_items_id = counter + 1
    count = length(item_vars)
    array_name = "list_record_items_#{list_items_id}"
    item_list = item_vars |> Enum.map(&RcRuntimeEmit.value_expr/1) |> Enum.join(", ")
    list_probe = DebugProbes.list_literal_probe(env, out, list_items_id)

    nulls = ValueSlots.transfer_and_null_refs(Enum.uniq(item_vars))

    code = """
    #{item_code}
      ElmcValue *#{array_name}[#{count}] = { #{item_list} };
      #{RcRuntimeEmit.assign_call(env, out, "elmc_list_from_record_array", "#{array_name}, #{count}")}
      #{nulls}
      #{list_probe}
    """

    {code, out, max(next, list_items_id + 1)}
  end

  defp all_native_primitive_record_literal?(%{op: :record_literal, fields: fields}) when is_list(fields) do
    fields != [] and
      Enum.all?(fields, fn
        %{expr: %{op: op}} when op in [:int_literal, :float_literal, :bool_literal, :char_literal] ->
          true

        _ ->
          false
      end)
  end

  defp all_native_primitive_record_literal?(%{op: :record_literal, fields: fields}) when is_map(fields) do
    fields != %{} and
      Enum.all?(fields, fn {_field, expr} ->
        match?(%{op: :int_literal}, expr) or match?(%{op: :float_literal}, expr) or
          match?(%{op: :bool_literal}, expr) or match?(%{op: :char_literal}, expr)
      end)
  end

  defp all_native_primitive_record_literal?(_), do: false

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
    env = RcRuntimeEmit.strip_function_tail_scope(env)
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
    env = RcRuntimeEmit.strip_function_tail_scope(env)
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
        {"", RcRuntimeEmit.value_expr(ref), counter}

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
        RcRuntimeEmit.assign_call(env, var, "elmc_new_int", "elmc_string_length(#{RcRuntimeEmit.value_expr(source)})")

    {code, var, next}
  end

  @spec compile_bound_char_from_code(Types.compile_env(), String.t(), Types.compile_counter()) ::
          Types.compile_result()
  defp compile_bound_char_from_code(env, name, counter) do
    {source_code, source, counter} = resolve_env_source(env, name, counter)
    {var, next} = CaseCompile.fresh_var(counter, env)

    char_call =
      case EnvBindings.native_int_binding(env, name) do
        ref when is_binary(ref) ->
          RcRuntimeEmit.assign_call(env, var, "elmc_char_from_code_int", ref)

        _ ->
          RcRuntimeEmit.assign_call(env, var, "elmc_char_from_code", source)
      end

    code = """
    #{source_code}  #{char_call}
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
    child_env = RcRuntimeEmit.strip_function_tail_scope(env)
    {arg_code, arg_var, counter} = Host.compile_expr(arg_expr, child_env, counter)
    {var, next} = CaseCompile.fresh_var(counter, env)

    arg_cleanup =
      cond do
        EnvBindings.tuple_projection_ref?(env, arg_var) ->
          ValueSlots.abandon_stmt(arg_var)

        ValueSlots.owned_ref?(arg_var) ->
          ValueSlots.release_owned_and_null(arg_var)

        true ->
          ValueSlots.release_stmt(arg_var)
      end

    arg_ref = RcRuntimeEmit.value_expr(arg_var)

    code = """
    #{arg_code}
      #{boxed_slot_assign(var, "#{c_fn}(#{arg_ref})")}
      #{arg_cleanup}
    """

    if RcRuntimeEmit.rc_allocator_emit_mode?(env), do: ValueSlots.track(var)
    if EnvBindings.tuple_projection_ref?(env, arg_var), do: ValueSlots.release(arg_var)

    {code, var, next}
  end

  defp boxed_slot_assign(var, rhs), do: ValueSlots.boxed_decl(var, rhs)

  defp multi_use_elm_var_names(items) when is_list(items) do
    items
    |> Enum.flat_map(&MapSet.to_list(VarAnalysis.used_vars(&1)))
    |> Enum.frequencies()
    |> Enum.flat_map(fn
      {name, count} when count > 1 -> [name]
      _ -> []
    end)
    |> MapSet.new()
  end

  defp emit_multi_use_owned_copies(multi_use, env, counter) when is_map(env) do
    Enum.reduce(multi_use, {"", %{}, counter}, fn name, {code, copy_map, c} ->
      case Map.get(env, name) do
        c_var when is_binary(c_var) ->
          if ValueSlots.owned_ref?(c_var) do
            {copy_var, c1} = RcRuntimeEmit.compile_result_slot(env, c)

            retain =
              "#{ValueSlots.boxed_decl(copy_var, "elmc_retain(#{RcRuntimeEmit.value_expr(c_var)})", env)}\n"

            {code <> retain, Map.put(copy_map, name, copy_var), c1}
          else
            {code, copy_map, c}
          end

        _ ->
          {code, copy_map, c}
      end
    end)
  end

  defp item_env_for_multi_use(env, consumed, copy_map)
       when is_map(env) and is_map(copy_map) do
    Enum.reduce(copy_map, env, fn {name, copy_var}, acc ->
      if MapSet.member?(consumed, name) do
        Map.put(acc, name, copy_var)
      else
        acc
      end
    end)
  end
end
