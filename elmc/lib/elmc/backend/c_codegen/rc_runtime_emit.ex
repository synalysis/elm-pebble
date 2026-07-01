defmodule Elmc.Backend.CCodegen.RcRuntimeEmit do
  @moduledoc false

  alias Elmc.Backend.CCodegen.CaseCompile
  alias Elmc.Backend.CCodegen.ListLoopCodegen
  alias Elmc.Backend.CCodegen.ValueSlots

  @rc_allocators MapSet.new([
    "elmc_new_int",
    "elmc_new_bool",
    "elmc_new_order",
    "elmc_new_string",
    "elmc_new_string_len",
    "elmc_new_float",
    "elmc_list_cons",
    "elmc_list_cons_take",
    "elmc_list_cons_head_take",
    "elmc_int_list_head_boxed",
    "elmc_int_list_tail",
    "elmc_float_list_head_boxed",
    "elmc_float_list_tail",
    "elmc_record_seq_head_boxed",
    "elmc_record_seq_tail",
    "elmc_int_spine_head_boxed",
    "elmc_int_spine_tail",
    "elmc_list_reverse",
    "elmc_list_copy",
    "elmc_list_map",
    "elmc_list_filter",
    "elmc_list_foldl",
    "elmc_list_append",
    "elmc_list_foldr",
    "elmc_list_concat",
    "elmc_list_concat_array",
    "elmc_list_concat_map",
    "elmc_list_indexed_map",
    "elmc_list_filter_map",
    "elmc_list_singleton",
    "elmc_list_range",
    "elmc_list_repeat",
    "elmc_list_take",
    "elmc_list_take_int",
    "elmc_list_drop",
    "elmc_list_drop_int",
    "elmc_list_partition",
    "elmc_list_unzip",
    "elmc_list_intersperse",
    "elmc_list_map2",
    "elmc_list_map3",
    "elmc_list_map4",
    "elmc_list_map5",
    "elmc_list_sum",
    "elmc_list_product",
    "elmc_list_maximum",
    "elmc_list_minimum",
    "elmc_list_any",
    "elmc_list_all",
    "elmc_list_sort",
    "elmc_list_sort_by",
    "elmc_list_sort_with",
    "elmc_string_append",
    "elmc_string_append_native",
    "elmc_string_concat_parts",
    "elmc_string_replace",
    "elmc_string_reverse",
    "elmc_string_repeat",
    "elmc_string_from_float",
    "elmc_string_to_upper",
    "elmc_string_to_lower",
    "elmc_string_trim",
    "elmc_string_trim_left",
    "elmc_string_trim_right",
    "elmc_string_split",
    "elmc_string_join",
    "elmc_string_slice",
    "elmc_string_from_list",
    "elmc_string_from_char",
    "elmc_string_pad_left",
    "elmc_string_pad_right",
    "elmc_string_map",
    "elmc_string_filter",
    "elmc_string_foldl",
    "elmc_string_foldr",
    "elmc_string_any",
    "elmc_string_all",
    "elmc_string_indexes",
    "elmc_string_uncons",
    "elmc_string_to_list",
    "elmc_dict_from_list",
    "elmc_dict_insert",
    "elmc_dict_get",
    "elmc_dict_remove",
    "elmc_dict_keys",
    "elmc_dict_values",
    "elmc_dict_map",
    "elmc_dict_foldl",
    "elmc_dict_foldr",
    "elmc_dict_filter",
    "elmc_dict_partition",
    "elmc_dict_intersect",
    "elmc_dict_diff",
    "elmc_dict_union",
    "elmc_dict_merge",
    "elmc_dict_update",
    "elmc_set_from_list",
    "elmc_set_insert",
    "elmc_set_remove",
    "elmc_set_foldl",
    "elmc_set_foldr",
    "elmc_set_filter",
    "elmc_set_partition",
    "elmc_set_union",
    "elmc_set_intersect",
    "elmc_set_diff",
    "elmc_set_map",
    "elmc_string_from_native_int",
    "elmc_maybe_map",
    "elmc_maybe_map2",
    "elmc_maybe_and_then",
    "elmc_result_map",
    "elmc_result_map_error",
    "elmc_result_and_then",
    "elmc_tuple_map_first",
    "elmc_tuple_map_second",
    "elmc_tuple_map_both",
    "elmc_list_from_int_array",
    "elmc_list_from_float_array",
    "elmc_list_from_record_array",
    "elmc_list_from_tuple2_int_array",
    "elmc_list_from_values_take",
    "elmc_maybe_just",
    "elmc_maybe_just_own",
    "elmc_result_ok",
    "elmc_result_err",
    "elmc_tuple2",
    "elmc_tuple2_take",
    "elmc_tuple2_ints",
    "elmc_record_new",
    "elmc_record_new_take",
    "elmc_record_new_ints",
    "elmc_record_new_static",
    "elmc_record_new_static_take",
    "elmc_record_new_static_ints",
    "elmc_record_new_values",
    "elmc_record_new_values_take",
    "elmc_record_new_values_ints",
    "elmc_closure_new",
    "elmc_closure_new_rc"
  ])

  @own_transfer_allocators MapSet.new([
    "elmc_maybe_just_own"
  ])

  @take_wrappers %{
    "elmc_new_int" => "elmc_new_int_take",
    "elmc_new_bool" => "elmc_new_bool_take",
    "elmc_new_order" => "elmc_new_order_take",
    "elmc_new_string" => "elmc_new_string_take",
    "elmc_new_string_len" => "elmc_new_string_len_take",
    "elmc_new_float" => "elmc_new_float_take",
    "elmc_list_cons" => "elmc_list_cons_take",
    "elmc_int_list_head_boxed" => "elmc_int_list_head_boxed_take",
    "elmc_int_list_tail" => "elmc_int_list_tail_take",
    "elmc_float_list_head_boxed" => "elmc_float_list_head_boxed_take",
    "elmc_float_list_tail" => "elmc_float_list_tail_take",
    "elmc_record_seq_head_boxed" => "elmc_record_seq_head_boxed_take",
    "elmc_record_seq_tail" => "elmc_record_seq_tail_take",
    "elmc_int_spine_head_boxed" => "elmc_int_spine_head_boxed_take",
    "elmc_int_spine_tail" => "elmc_int_spine_tail_take",
    "elmc_list_reverse" => "elmc_list_reverse_take",
    "elmc_list_copy" => "elmc_list_copy_take",
    "elmc_list_map" => "elmc_list_map_take",
    "elmc_list_filter" => "elmc_list_filter_take",
    "elmc_list_foldl" => "elmc_list_foldl_take",
    "elmc_list_append" => "elmc_list_append_take",
    "elmc_list_foldr" => "elmc_list_foldr_take",
    "elmc_list_concat" => "elmc_list_concat_take",
    "elmc_list_concat_map" => "elmc_list_concat_map_take",
    "elmc_list_concat_array" => "elmc_list_concat_array_take",
    "elmc_list_indexed_map" => "elmc_list_indexed_map_take",
    "elmc_list_filter_map" => "elmc_list_filter_map_take",
    "elmc_list_singleton" => "elmc_list_singleton_take",
    "elmc_list_range" => "elmc_list_range_take",
    "elmc_list_repeat" => "elmc_list_repeat_take",
    "elmc_list_take" => "elmc_list_take_take",
    "elmc_list_take_int" => "elmc_list_take_int_take",
    "elmc_list_drop" => "elmc_list_drop_take",
    "elmc_list_drop_int" => "elmc_list_drop_int_take",
    "elmc_list_partition" => "elmc_list_partition_take",
    "elmc_list_unzip" => "elmc_list_unzip_take",
    "elmc_list_intersperse" => "elmc_list_intersperse_take",
    "elmc_list_map2" => "elmc_list_map2_take",
    "elmc_list_map3" => "elmc_list_map3_take",
    "elmc_list_map4" => "elmc_list_map4_take",
    "elmc_list_map5" => "elmc_list_map5_take",
    "elmc_list_sum" => "elmc_list_sum_take",
    "elmc_list_product" => "elmc_list_product_take",
    "elmc_list_maximum" => "elmc_list_maximum_take",
    "elmc_list_minimum" => "elmc_list_minimum_take",
    "elmc_list_any" => "elmc_list_any_take",
    "elmc_list_all" => "elmc_list_all_take",
    "elmc_list_sort" => "elmc_list_sort_take",
    "elmc_list_sort_by" => "elmc_list_sort_by_take",
    "elmc_list_sort_with" => "elmc_list_sort_with_take",
    "elmc_string_append" => "elmc_string_append_take",
    "elmc_string_append_native" => "elmc_string_append_native_take",
    "elmc_string_replace" => "elmc_string_replace_take",
    "elmc_string_reverse" => "elmc_string_reverse_take",
    "elmc_string_repeat" => "elmc_string_repeat_take",
    "elmc_string_from_float" => "elmc_string_from_float_take",
    "elmc_string_to_upper" => "elmc_string_to_upper_take",
    "elmc_string_to_lower" => "elmc_string_to_lower_take",
    "elmc_string_trim" => "elmc_string_trim_take",
    "elmc_string_trim_left" => "elmc_string_trim_left_take",
    "elmc_string_trim_right" => "elmc_string_trim_right_take",
    "elmc_string_split" => "elmc_string_split_take",
    "elmc_string_join" => "elmc_string_join_take",
    "elmc_string_slice" => "elmc_string_slice_take",
    "elmc_string_from_list" => "elmc_string_from_list_take",
    "elmc_string_from_char" => "elmc_string_from_char_take",
    "elmc_string_pad_left" => "elmc_string_pad_left_take",
    "elmc_string_pad_right" => "elmc_string_pad_right_take",
    "elmc_string_map" => "elmc_string_map_take",
    "elmc_string_filter" => "elmc_string_filter_take",
    "elmc_string_foldl" => "elmc_string_foldl_take",
    "elmc_string_foldr" => "elmc_string_foldr_take",
    "elmc_string_any" => "elmc_string_any_take",
    "elmc_string_all" => "elmc_string_all_take",
    "elmc_string_indexes" => "elmc_string_indexes_take",
    "elmc_string_uncons" => "elmc_string_uncons_take",
    "elmc_string_to_list" => "elmc_string_to_list_take",
    "elmc_dict_from_list" => "elmc_dict_from_list_take",
    "elmc_dict_insert" => "elmc_dict_insert_take",
    "elmc_dict_get" => "elmc_dict_get_take",
    "elmc_dict_remove" => "elmc_dict_remove_take",
    "elmc_dict_keys" => "elmc_dict_keys_take",
    "elmc_dict_values" => "elmc_dict_values_take",
    "elmc_dict_map" => "elmc_dict_map_take",
    "elmc_dict_foldl" => "elmc_dict_foldl_take",
    "elmc_dict_foldr" => "elmc_dict_foldr_take",
    "elmc_dict_filter" => "elmc_dict_filter_take",
    "elmc_dict_partition" => "elmc_dict_partition_take",
    "elmc_dict_intersect" => "elmc_dict_intersect_take",
    "elmc_dict_diff" => "elmc_dict_diff_take",
    "elmc_dict_union" => "elmc_dict_union_take",
    "elmc_dict_merge" => "elmc_dict_merge_take",
    "elmc_dict_update" => "elmc_dict_update_take",
    "elmc_set_from_list" => "elmc_set_from_list_take",
    "elmc_set_insert" => "elmc_set_insert_take",
    "elmc_set_remove" => "elmc_set_remove_take",
    "elmc_set_foldl" => "elmc_set_foldl_take",
    "elmc_set_foldr" => "elmc_set_foldr_take",
    "elmc_set_filter" => "elmc_set_filter_take",
    "elmc_set_partition" => "elmc_set_partition_take",
    "elmc_set_union" => "elmc_set_union_take",
    "elmc_set_intersect" => "elmc_set_intersect_take",
    "elmc_set_diff" => "elmc_set_diff_take",
    "elmc_set_map" => "elmc_set_map_take",
    "elmc_string_from_native_int" => "elmc_string_from_native_int_take",
    "elmc_maybe_map" => "elmc_maybe_map_take",
    "elmc_maybe_map2" => "elmc_maybe_map2_take",
    "elmc_maybe_and_then" => "elmc_maybe_and_then_take",
    "elmc_result_map" => "elmc_result_map_take",
    "elmc_result_map_error" => "elmc_result_map_error_take",
    "elmc_result_and_then" => "elmc_result_and_then_take",
    "elmc_tuple_map_first" => "elmc_tuple_map_first_take",
    "elmc_tuple_map_second" => "elmc_tuple_map_second_take",
    "elmc_tuple_map_both" => "elmc_tuple_map_both_take",
    "elmc_list_from_int_array" => "elmc_list_from_int_array_take",
    "elmc_list_from_float_array" => "elmc_list_from_float_array_take",
    "elmc_list_from_record_array" => "elmc_list_from_record_array_take",
    "elmc_list_from_tuple2_int_array" => "elmc_list_from_tuple2_int_array_take",
    "elmc_list_from_values_take" => "elmc_list_from_values_take_value",
    "elmc_tuple2_take" => "elmc_tuple2_take_value",
    "elmc_record_new_take" => "elmc_record_new_take_value",
    "elmc_record_new" => "elmc_record_new_take_value",
    "elmc_record_new_static_take" => "elmc_record_new_static_take_value",
    "elmc_record_new_static" => "elmc_record_new_static_take_value",
    "elmc_record_new_values_take" => "elmc_record_new_values_take_value",
    "elmc_record_new_values" => "elmc_record_new_values_take_value",
    "elmc_record_new_values_ints" => "elmc_record_new_values_ints_take",
    "elmc_closure_new" => "elmc_closure_new_take"
  }

  @function_out_marker "ELMC_FN_OUT"

  @fresh_owned_slot ~r/^(tmp_\d+(?:_[a-z0-9_]+)?|head_\d+|owned\[\d+\]|call_args_\d+|list_items_\d+|rec_values_\d+|list_map_item_\d+|list_indexed_map_item_\d+|list_map_cons_\d+|list_map_rev_\d+|list_fwd_cell_\d+|list_repeat_cons_\d+|string_segment_\d+|string_concat_acc_\d+|list_case_suffix_\d+)$/

  @spec function_out_ref() :: String.t()
  def function_out_ref, do: @function_out_marker

  @spec function_out_ref?(String.t()) :: boolean()
  def function_out_ref?(ref) when is_binary(ref), do: ref == @function_out_marker
  def function_out_ref?(_), do: false

  @spec function_out_param() :: String.t()
  def function_out_param, do: "out"

  @spec function_out_deref() :: String.t()
  def function_out_deref, do: "*out"

  @doc "C preprocessor define so `ELMC_FN_OUT` aliases the function result slot."
  @spec function_out_define() :: String.t()
  def function_out_define, do: "#define ELMC_FN_OUT (*out)"

  @doc "C expression for reading fields from a boxed value slot."
  @spec value_expr(String.t()) :: String.t()
  def value_expr(ref) when is_binary(ref) do
    if function_out_ref?(ref), do: "(#{function_out_deref()})", else: ref
  end

  @doc "Format compile-time value refs for a C call argument list."
  @spec call_arg_list([String.t()]) :: String.t()
  def call_arg_list(refs) when is_list(refs) do
    refs |> Enum.map(&value_expr/1) |> Enum.join(", ")
  end

  @doc "C lhs for assigning into a boxed value slot."
  @spec assignment_lhs(String.t()) :: String.t()
  def assignment_lhs(ref) when is_binary(ref) do
    cond do
      function_out_ref?(ref) -> function_out_deref()
      ref == function_out_param() -> "*#{ref}"
      true -> ref
    end
  end

  @doc "C assignment statement for a boxed value slot (never emits the internal out marker raw)."
  @spec assign_stmt(String.t(), String.t()) :: String.t()
  def assign_stmt(out, rhs) when is_binary(out) and is_binary(rhs) do
    stmt = ValueSlots.owned_reassign_prefix(out) <> "#{assignment_lhs(out)} = #{rhs};"

    if ValueSlots.owned_ref?(out) and rhs != "NULL" do
      ValueSlots.mark_written(out)
    end

    stmt
  end

  @doc "C null assignment for a boxed value slot."
  @spec null_assign_stmt(String.t()) :: String.t()
  def null_assign_stmt(out) when is_binary(out), do: assign_stmt(out, "NULL")
  @spec transfer_assignment(String.t(), String.t()) :: String.t()
  def transfer_assignment(out, ref) when is_binary(out) and is_binary(ref) do
    stmt = "#{assignment_lhs(out)} = #{value_expr(ref)};"

    cond do
      function_out_ref?(out) and ValueSlots.owned_ref?(ref) ->
        abandon_owned_source(ref, stmt)

      ValueSlots.owned_ref?(out) and ValueSlots.owned_ref?(ref) and out != ref ->
        abandon_owned_source(ref, stmt)

      true ->
        stmt
    end
  end

  defp abandon_owned_source(ref, stmt) do
    ValueSlots.transfer(ref)
    stmt <> "\n" <> ValueSlots.null_assignment(ref)
  end

  @spec allocator_out_arg(String.t()) :: String.t()
  def allocator_out_arg(out) when is_binary(out) do
    cond do
      function_out_ref?(out) -> function_out_param()
      ValueSlots.owned_ref?(out) -> "&#{out}"
      true -> "&#{out}"
    end
  end

  @spec assigns_allocator_out?(String.t(), String.t()) :: boolean()
  def assigns_allocator_out?(expr_code, out) when is_binary(expr_code) and is_binary(out) do
    arg = allocator_out_arg(out)
    String.contains?(expr_code, "#{arg},") or String.contains?(expr_code, "#{arg})")
  end

  @doc "Move a boxed tail result into `*out`. Caller owns the out slot; no read of uninitialized `*out`."
  @spec publish_function_out_from(String.t()) :: String.t()
  def publish_function_out_from(result_var) when is_binary(result_var) do
    if ValueSlots.owned_ref?(result_var) do
      "#{function_out_deref()} = #{result_var};\n#{ValueSlots.null_assignment(result_var)}"
    else
      "#{function_out_deref()} = #{result_var};"
    end
  end

  @doc "Result slot for a runtime-call expression: branch/owned out, or a fresh owned slot."
  @spec compile_result_slot(map(), non_neg_integer()) :: {String.t(), non_neg_integer()}
  def compile_result_slot(env, counter) do
    case nested_out_target(env) do
      out when is_binary(out) ->
        if function_out_ref?(out), do: CaseCompile.fresh_var(counter, env), else: {out, counter}

      _ ->
        CaseCompile.fresh_var(counter, env)
    end
  end

  @doc "Out slot for string/append fusion: branch out or nested into_out."
  @spec append_out_target(map()) :: String.t() | nil
  def append_out_target(env) do
    Map.get(env, :__branch_out__) || nested_out_target(env)
  end

  @spec with_function_out_target(map()) :: map()
  def with_function_out_target(env), do: Map.put(env, :__into_out__, function_out_ref())

  @doc "Compile env for the function's root tail expression only."
  @spec function_tail_env(map()) :: map()
  def function_tail_env(env) do
    env
    |> Map.put(:__function_tail_compile__, true)
    |> with_function_out_target()
  end

  @spec function_tail_compile?(map()) :: boolean()
  def function_tail_compile?(env), do: Map.get(env, :__function_tail_compile__, false)

  @doc "Strip tail-only out targeting from let values, operands, and nested scopes."
  @spec strip_function_tail_scope(map()) :: map()
  def strip_function_tail_scope(env) do
    env
    |> Map.delete(:__function_tail_compile__)
    |> Map.delete(:__into_out__)
  end

  @doc """
  `__into_out__` when safe for nested subexpressions (never the function tail slot).
  """
  @spec nested_out_target(map()) :: String.t() | nil
  def nested_out_target(env) do
    case Map.get(env, :__into_out__) do
      @function_out_marker -> nil
      into_out when is_binary(into_out) -> into_out
      _ -> nil
    end
  end

  @doc "Out slot for a direct tail call (`forward x = callee x x`)."
  @spec tail_call_out_target(map()) :: String.t() | nil
  def tail_call_out_target(env) do
    case Map.get(env, :__into_out__) do
      @function_out_marker ->
        if function_tail_compile?(env), do: @function_out_marker, else: nil

      _ ->
        nil
    end
  end

  @legacy_allocator_aliases %{
    "elmc_closure_new_take" => "elmc_closure_new",
    "elmc_closure_new_rc_take" => "elmc_closure_new_rc"
  }

  @allocator_call ~r/^(elmc_[a-z0-9_]+)\((.*)\)\s*$/s

  @doc false
  @spec canonical_allocator(String.t()) :: String.t()
  def canonical_allocator(name) when is_binary(name) do
    case Map.fetch(@legacy_allocator_aliases, name) do
      {:ok, canonical} ->
        canonical

      :error ->
        if String.ends_with?(name, "_take_value") do
          candidate = String.replace_suffix(name, "_take_value", "_take")

          if MapSet.member?(@rc_allocators, candidate) do
            candidate
          else
            name
          end
        else
          name
        end
    end
  end

  @doc false
  @spec allocator_call?(String.t()) :: boolean()
  def allocator_call?(rhs) when is_binary(rhs) do
    case parse_allocator_call(rhs) do
      {:ok, _, _} -> true
      :error -> false
    end
  end

  @doc false
  @spec parse_allocator_call(String.t()) :: {:ok, String.t(), String.t()} | :error
  def parse_allocator_call(rhs) when is_binary(rhs) do
    case Regex.run(@allocator_call, String.trim(rhs)) do
      [_, fn_name, call_args] ->
        cond do
          String.ends_with?(fn_name, "_take_value") ->
            :error

          String.ends_with?(fn_name, "_take") ->
            :error

          true ->
            canonical = canonical_allocator(fn_name)

            if rc_allocator?(canonical) do
              {:ok, canonical, call_args}
            else
              :error
            end
        end

      _ ->
        :error
    end
  end

  @doc false
  @spec parse_take_wrapper_call(String.t()) :: {:ok, String.t(), String.t()} | :error
  def parse_take_wrapper_call(rhs), do: parse_allocator_call(rhs)

  @doc false
  @spec take_wrapper_call?(String.t()) :: boolean()
  def take_wrapper_call?(rhs), do: allocator_call?(rhs)

  @doc false
  @spec take_wrapper_assign(String.t(), String.t(), String.t(), map(), keyword()) :: String.t()
  def take_wrapper_assign(out, alloc_fn, call_args, env \\ %{}, opts \\ []) do
    opts = Keyword.merge([env: env, return_on_fail?: not rc_allocator_emit_mode?(env)], opts)

    if rc_allocator_emit_mode?(env) do
      declare? = legacy_declare_out?(out, opts)

      init =
        if declare? do
          ValueSlots.boxed_null_decl(out)
        else
          null_assign_stmt(out)
        end

      """
      #{init}
      Rc = #{alloc_fn}(#{allocator_out_arg(out)}, #{call_args});
      CHECK_RC(Rc);
      """
      |> String.trim()
    else
      fusion_assign(out, alloc_fn, call_args, env, opts)
    end
  end

  @spec rc_allocator?(String.t()) :: boolean()
  def rc_allocator?(function) when is_binary(function),
    do: MapSet.member?(@rc_allocators, function)

  def rc_allocator?(_), do: false

  @spec rc_mode?(map()) :: boolean()
  def rc_mode?(env),
    do: Map.get(env, :__rc_required__, false) and Map.get(env, :__rc_catch__, false)

  @spec rc_allocator_emit_mode?(map()) :: boolean()
  def rc_allocator_emit_mode?(env),
    do:
      Map.get(env, :__rc_required__, false) or Map.get(env, :__rc_catch__, false) or
        Map.get(env, :__native_rc_out__, false)

  @spec rc_catch_env(map()) :: map()
  def rc_catch_env(env), do: Map.put(env, :__rc_catch__, true)

  @spec rc_style_codegen_body?(String.t()) :: boolean()
  def rc_style_codegen_body?(body) when is_binary(body) do
    body =~ "CHECK_RC(" or body =~ ~r/\bRc\s*=/ or body =~ "owned[" or body =~ "CATCH_BEGIN"
  end

  @spec generic_helper_extraction_allowed?(map(), String.t()) :: boolean()
  def generic_helper_extraction_allowed?(env, body) when is_binary(body) do
    not Map.get(env, :__rc_catch__, false) and
      not Map.get(env, :__rc_required__, false) and
      not Map.get(env, :__native_rc_out__, false) and
      not Map.get(env, :__inside_lambda__, false) and
      not rc_style_codegen_body?(body)
  end

  @doc false
  @spec allocator_assign(map(), String.t(), String.t(), String.t(), keyword()) :: String.t()
  def allocator_assign(env, out, function, call_args, opts \\ []) do
    opts = Keyword.put_new(opts, :env, env)

    if rc_allocator_emit_mode?(env) do
      rc_allocator_stmt(env, out, function, call_args, opts)
    else
      legacy_rc_allocator_stmt(out, function, call_args, opts)
    end
  end

  @spec assign_call(map(), String.t(), String.t(), String.t()) :: String.t()
  def assign_call(env, out, function, call_args) do
    cond do
      not rc_allocator?(function) and
          (predeclared_out_slot?(env, out) or rc_owned_slot?(out) or function_out_ref?(out)) ->
        function_out_assign(env, out, "#{function}(#{call_args})")

      not rc_allocator?(function) ->
        ValueSlots.boxed_decl(out, "#{function}(#{call_args})")

      predeclared_out_slot?(env, out) or function_out_ref?(out) ->
        assign_into(env, out, function, call_args)

      rc_allocator_emit_mode?(env) and predeclared_out_slot?(env, out) ->
        assign_into(env, out, function, call_args)

      rc_allocator_emit_mode?(env) and function == "elmc_list_cons" ->
        int_list_cons_assign(env, out, call_args)

      rc_allocator_emit_mode?(env) ->
        allocator_assign(env, out, function, call_args)

      true ->
        fusion_assign(out, function, call_args, env)
    end
  end

  @doc """
  Assign into a pre-declared slot (for example `owned[3]` in if-branches).
  """
  @spec assign_into(map(), String.t(), String.t(), String.t()) :: String.t()
  def assign_into(env, out, function, call_args) do
    cond do
      not rc_allocator?(function) ->
        function_out_assign(env, out, "#{function}(#{call_args})")

      rc_allocator_emit_mode?(env) and function == "elmc_list_cons" ->
        int_list_cons_assign(env, out, call_args)

      rc_allocator_emit_mode?(env) ->
        allocator_assign(env, out, function, call_args, declare_out?: false)

      true ->
        legacy_rc_allocator_stmt(out, function, call_args, declare_out?: false, env: env)
    end
  end

  @doc "List.cons with retain semantics for borrowed head/tail operands."
  @spec list_cons_retain_assign(String.t(), String.t(), map(), keyword()) :: String.t()
  def list_cons_retain_assign(out, call_args, env \\ %{}, opts \\ []) do
    if rc_allocator_emit_mode?(env) do
      int_list_cons_assign(env, out, call_args, opts)
    else
      legacy_rc_allocator_stmt(
        out,
        "elmc_list_cons",
        call_args,
        opts |> Keyword.put(:declare_out?, true) |> Keyword.put(:env, env)
      )
    end
  end

  defp int_list_cons_assign(env, out, call_args, opts \\ []) do
    loop_id = Keyword.get(opts, :loop_id, 0)

    case parse_call_args_pair(call_args) do
      {head, tail} ->
        ListLoopCodegen.emit_int_list_cons_assign(env, out, head, tail, loop_id, opts)

      :error ->
        allocator_assign(env, out, "elmc_list_cons", call_args, opts)
    end
  end

  defp parse_call_args_pair(call_args) when is_binary(call_args) do
    case String.split(call_args, ", ", parts: 2) do
      [head, tail] -> {String.trim(head), String.trim(tail)}
      _ -> :error
    end
  end

  @doc "RC assign in catch blocks; take wrapper otherwise."
  @spec assign_or_fusion(map(), String.t(), String.t(), String.t()) :: String.t()
  def assign_or_fusion(env, out, function, call_args) do
    if rc_allocator_emit_mode?(env) do
      allocator_assign(env, out, function, call_args)
    else
      fusion_assign(out, function, call_args, env)
    end
  end

  @doc false
  def take_wrapper_for(function) when is_binary(function), do: Map.get(@take_wrappers, function)

  @doc "RC allocator assign for fused/native C snippets (never uses break)."
  @spec fusion_assign(String.t(), String.t(), String.t(), map(), keyword()) :: String.t()
  def fusion_assign(out, function, call_args, env \\ %{}, opts \\ []) do
    cond do
      rc_allocator_emit_mode?(env) ->
        allocator_assign(env, out, function, call_args, opts)

      Map.has_key?(@take_wrappers, function) and predeclared_out_slot?(env, out) ->
        take_fn = Map.fetch!(@take_wrappers, function)
        stmt = ValueSlots.owned_reassign_prefix(out) <> "#{out} = #{take_fn}(#{call_args});"
        ValueSlots.mark_written(out)
        stmt

      Map.has_key?(@take_wrappers, function) ->
        take_fn = Map.fetch!(@take_wrappers, function)
        ValueSlots.boxed_decl(out, "#{take_fn}(#{call_args})")

      true ->
        legacy_rc_allocator_stmt(out, function, call_args, Keyword.merge(opts, env: env))
    end
  end

  @doc "RC allocator return for fused C snippets."
  @spec fusion_return(String.t(), String.t(), String.t(), map()) :: String.t()
  def fusion_return(_out, function, call_args, env \\ %{}) do
    cond do
      rc_allocator_emit_mode?(env) ->
        """
        {
          ElmcValue *__rc_ret = NULL;
          Rc = #{function}(&__rc_ret, #{call_args});
          CHECK_RC(Rc);
          return __rc_ret;
        }
        """

      true ->
        failure = failure_return(env)

        """
        {
          ElmcValue *__rc_ret = NULL;
          RC __alloc_rc = #{function}(&__rc_ret, #{call_args});
          if (__alloc_rc != RC_SUCCESS) {
            ELMC_RC_LOG_FAIL(__alloc_rc, "#{function}", "allocation failed");
            #{failure}
          }
          return __rc_ret;
        }
        """
    end
  end

  @spec legacy_rc_allocator_stmt(String.t(), String.t(), String.t(), keyword()) :: String.t()
  defp legacy_rc_allocator_stmt(out, function, call_args, opts) do
    return_on_fail? = Keyword.get(opts, :return_on_fail?, true)
    declare_out? = legacy_declare_out?(out, opts)

    init =
      if declare_out? do
        ValueSlots.boxed_null_decl(out)
      else
        null_assign_stmt(out)
      end

    failure =
      if return_on_fail? do
        """
        ELMC_RC_LOG_FAIL(__alloc_rc, "#{function}", "allocation failed");
        #{rc_failure_return(opts)}
        """
      else
        """
        ELMC_RC_LOG_FAIL(__alloc_rc, "#{function}", "allocation failed");
        #{null_assign_stmt(out)};
        """
      end

    """
    #{init}
    {
      RC __alloc_rc = #{function}(#{allocator_out_arg(out)}, #{call_args});
      if (__alloc_rc != RC_SUCCESS) {
        #{failure}
      }
    }
    """
    |> String.trim()
  end

  defp rc_failure_return(opts) do
    failure_return(Keyword.get(opts, :env, %{}))
  end

  defp legacy_declare_out?(out, opts) do
    case Keyword.get(opts, :declare_out?) do
      true -> true
      false -> false
      nil -> Regex.match?(@fresh_owned_slot, out)
    end
  end

  def failure_return(env) do
    cond do
      Map.get(env, :__rc_catch__) || Map.get(env, :__rc_required__) ->
        "Rc = __alloc_rc;\nreturn Rc;"

      Map.get(env, :__native_rc_out__) ->
        "return __alloc_rc;"

      Map.get(env, :__native_return_kind__) == :native_int ->
        "return 0;"

      Map.get(env, :__native_return_kind__) == :native_bool ->
        "return 0;"

      true ->
        "return NULL;"
    end
  end

  @doc "Emit allocator assign: CHECK_RC in RC/catch bodies, take wrapper or legacy block otherwise."
  @spec check_rc_take(String.t(), String.t(), String.t(), map()) :: String.t()
  def check_rc_take(out, function, call_args, env \\ %{}) do
    if rc_allocator_emit_mode?(env) do
      rc_allocator_stmt(env, out, function, call_args)
    else
      fusion_assign(out, function, call_args, env)
    end
  end

  @doc "After a loop that may set Rc via CHECK_RC, break out of CATCH_BEGIN when failed."
  @spec loop_exit_check_rc(map()) :: String.t()
  def loop_exit_check_rc(env \\ %{}) do
    if rc_allocator_emit_mode?(env), do: "CHECK_RC(Rc);", else: ""
  end

  @doc "Fused `elmc_tuple2_take(left, new_int(rhs))` return."
  @spec fusion_tuple2_take_int_return(String.t(), String.t(), String.t(), map()) :: String.t()
  def fusion_tuple2_take_int_return(_out, left, int_expr, env \\ %{}) do
    failure = failure_return(env)

    """
    {
      ElmcValue *__rhs = NULL;
      ElmcValue *__pair = NULL;
      RC __rhs_rc = elmc_new_int(&__rhs, #{int_expr});
      if (__rhs_rc != RC_SUCCESS) {
        ELMC_RC_LOG_FAIL(__rhs_rc, "elmc_new_int", "allocation failed");
        #{failure}
      }
      RC __pair_rc = elmc_tuple2_take(&__pair, #{left}, __rhs);
      if (__pair_rc != RC_SUCCESS) {
        elmc_release(__rhs);
        ELMC_RC_LOG_FAIL(__pair_rc, "elmc_tuple2_take", "allocation failed");
        #{failure}
      }
      elmc_release(__rhs);
      return __pair;
    }
    """
    |> String.trim()
  end

  defp declared_out_slot?(env, out) do
    MapSet.member?(Map.get(env, :__declared_outs__, MapSet.new()), out)
  end

  @doc false
  def predeclared_out_slot?(env, out) do
    declared_out_slot?(env, out) or Map.get(env, :__into_out__) == out or
      Map.get(env, :__branch_out__) == out
  end

  defp rc_owned_slot?(out), do: ValueSlots.owned_ref?(out)

  @doc false
  @spec rc_allocator_stmt(map(), String.t(), String.t(), String.t(), keyword()) :: String.t()
  def rc_allocator_stmt(env, out, function, call_args, opts \\ []) do
    unless function_out_ref?(out), do: ValueSlots.track(out)

    declare? =
      Keyword.get(
        opts,
        :declare_out?,
        not rc_owned_slot?(out) and not predeclared_out_slot?(env, out) and
          not function_out_ref?(out)
      )

    init =
      if declare? do
        if rc_owned_slot?(out) do
          ""
        else
          "#{ValueSlots.boxed_null_decl(out)}\n"
        end
      else
        ""
      end

    preempt =
      if rc_owned_slot?(out) and not allocator_same_slot_transfer?(out, function, call_args) do
        ValueSlots.owned_reassign_prefix(out)
      else
        ""
      end

    if rc_owned_slot?(out), do: ValueSlots.mark_written(out)

    """
    #{preempt}#{init}Rc = #{function}(#{allocator_out_arg(out)}, #{call_args});
    CHECK_RC(Rc);
    """
    |> String.trim()
  end

  defp allocator_same_slot_transfer?(out, function, call_args)
       when is_binary(out) and is_binary(function) and is_binary(call_args) do
    MapSet.member?(@own_transfer_allocators, function) and
      String.trim(call_args) == out
  end

  defp function_out_assign(_env, out, rhs) when is_binary(out) and is_binary(rhs) do
    "#{assignment_lhs(out)} = #{rhs};"
  end
end
