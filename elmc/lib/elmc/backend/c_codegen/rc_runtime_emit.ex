defmodule Elmc.Backend.CCodegen.RcRuntimeEmit do
  @moduledoc false

  alias Elmc.Backend.CCodegen.ValueSlots

  @rc_allocators MapSet.new([
    "elmc_new_int",
    "elmc_new_bool",
    "elmc_new_string",
    "elmc_new_float",
    "elmc_list_cons",
    "elmc_list_reverse",
    "elmc_list_copy",
    "elmc_list_map",
    "elmc_list_filter",
    "elmc_list_foldl",
    "elmc_list_append",
    "elmc_list_foldr",
    "elmc_list_concat",
    "elmc_list_concat_array",
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
    "elmc_list_from_tuple2_int_array",
    "elmc_list_from_values_take",
    "elmc_maybe_just",
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
    "elmc_closure_new"
  ])

  @fresh_owned_slot ~r/^(tmp_\d+|head_\d+|call_args_\d+|list_items_\d+|rec_values_\d+|list_map_item_\d+|list_map_cons_\d+|list_map_rev_\d+|list_fwd_cell_\d+|list_repeat_cons_\d+)$/

  @take_wrappers %{
    "elmc_new_int" => "elmc_new_int_take",
    "elmc_new_bool" => "elmc_new_bool_take",
    "elmc_new_string" => "elmc_new_string_take",
    "elmc_new_string_len" => "elmc_new_string_len_take",
    "elmc_new_float" => "elmc_new_float_take",
    "elmc_list_cons" => "elmc_list_cons_take",
    "elmc_list_reverse" => "elmc_list_reverse_take",
    "elmc_list_copy" => "elmc_list_copy_take",
    "elmc_list_map" => "elmc_list_map_take",
    "elmc_list_filter" => "elmc_list_filter_take",
    "elmc_list_foldl" => "elmc_list_foldl_take",
    "elmc_list_append" => "elmc_list_append_take",
    "elmc_list_foldr" => "elmc_list_foldr_take",
    "elmc_list_concat" => "elmc_list_concat_take",
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
    "elmc_list_from_tuple2_int_array" => "elmc_list_from_tuple2_int_array_take",
    "elmc_list_from_values_take" => "elmc_list_from_values_take_value",
    "elmc_tuple2_take" => "elmc_tuple2_take_value",
    "elmc_record_new_take" => "elmc_record_new_take_value",
    "elmc_record_new_static_take" => "elmc_record_new_static_take_value",
    "elmc_record_new_values_take" => "elmc_record_new_values_take_value",
    "elmc_record_new_values_ints" => "elmc_record_new_values_ints_take",
    "elmc_closure_new" => "elmc_closure_new_take"
  }

  @spec rc_allocator?(String.t()) :: boolean()
  def rc_allocator?(function) when is_binary(function),
    do: MapSet.member?(@rc_allocators, function)

  def rc_allocator?(_), do: false

  @spec rc_mode?(map()) :: boolean()
  def rc_mode?(env),
    do: Map.get(env, :__rc_required__, false) and Map.get(env, :__rc_catch__, false)

  @spec rc_allocator_emit_mode?(map()) :: boolean()
  def rc_allocator_emit_mode?(env),
    do: Map.get(env, :__rc_required__, false) or Map.get(env, :__rc_catch__, false)

  @spec assign_call(map(), String.t(), String.t(), String.t()) :: String.t()
  def assign_call(env, out, function, call_args) do
    cond do
      not rc_allocator?(function) and predeclared_out_slot?(env, out) ->
        "#{out} = #{function}(#{call_args});"

      not rc_allocator?(function) ->
        "ElmcValue *#{out} = #{function}(#{call_args});"

      rc_allocator_emit_mode?(env) and predeclared_out_slot?(env, out) ->
        assign_into(env, out, function, call_args)

      rc_allocator_emit_mode?(env) ->
        ValueSlots.track(out)

        """
        ElmcValue *#{out} = NULL;
        Rc = #{function}(&#{out}, #{call_args});
        CHECK_RC(Rc);
        """
        |> String.trim()

      true ->
        fusion_assign(out, function, call_args, env)
    end
  end

  @doc """
  Assign into a pre-declared slot (for example `ElmcValue *tmp_4;` in if-branches).
  """
  @spec assign_into(map(), String.t(), String.t(), String.t()) :: String.t()
  def assign_into(env, out, function, call_args) do
    cond do
      not rc_allocator?(function) ->
        "#{out} = #{function}(#{call_args});"

      rc_allocator_emit_mode?(env) ->
        ValueSlots.track(out)

        """
        Rc = #{function}(&#{out}, #{call_args});
        CHECK_RC(Rc);
        """
        |> String.trim()

      Map.has_key?(@take_wrappers, function) ->
        take_fn = Map.fetch!(@take_wrappers, function)
        "#{out} = #{take_fn}(#{call_args});"

      true ->
        legacy_rc_allocator_stmt(out, function, call_args, declare_out?: false, env: env)
    end
  end

  @doc "List.cons with retain semantics for borrowed head/tail operands."
  @spec list_cons_retain_assign(String.t(), String.t(), map(), keyword()) :: String.t()
  def list_cons_retain_assign(out, call_args, env \\ %{}, opts \\ []) do
    if rc_allocator_emit_mode?(env) do
      ValueSlots.track(out)

      """
      ElmcValue *#{out} = NULL;
      Rc = elmc_list_cons(&#{out}, #{call_args});
      CHECK_RC(Rc);
      """
      |> String.trim()
    else
      legacy_rc_allocator_stmt(
        out,
        "elmc_list_cons",
        call_args,
        opts |> Keyword.put(:declare_out?, true) |> Keyword.put(:env, env)
      )
    end
  end

  @doc "RC assign in catch blocks; take wrapper otherwise."
  @spec assign_or_fusion(map(), String.t(), String.t(), String.t()) :: String.t()
  def assign_or_fusion(env, out, function, call_args) do
    if rc_allocator_emit_mode?(env) do
      ValueSlots.track(out)

      """
      ElmcValue *#{out} = NULL;
      Rc = #{function}(&#{out}, #{call_args});
      CHECK_RC(Rc);
      """
      |> String.trim()
    else
      fusion_assign(out, function, call_args, env)
    end
  end

  @doc "RC allocator assign for fused/native C snippets (never uses break)."
  @spec fusion_assign(String.t(), String.t(), String.t(), map(), keyword()) :: String.t()
  def fusion_assign(out, function, call_args, env \\ %{}, opts \\ []) do
    cond do
      rc_allocator_emit_mode?(env) ->
        ValueSlots.track(out)

        """
        ElmcValue *#{out} = NULL;
        Rc = #{function}(&#{out}, #{call_args});
        CHECK_RC(Rc);
        """
        |> String.trim()

      Map.has_key?(@take_wrappers, function) and predeclared_out_slot?(env, out) ->
        take_fn = Map.fetch!(@take_wrappers, function)
        "#{out} = #{take_fn}(#{call_args});"

      Map.has_key?(@take_wrappers, function) ->
        take_fn = Map.fetch!(@take_wrappers, function)
        "ElmcValue *#{out} = #{take_fn}(#{call_args});"

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

      Map.has_key?(@take_wrappers, function) ->
        take_fn = Map.fetch!(@take_wrappers, function)
        "return #{take_fn}(#{call_args});"

      true ->
        """
        {
          ElmcValue *__rc_ret = NULL;
          RC __alloc_rc = #{function}(&__rc_ret, #{call_args});
          if (__alloc_rc != RC_SUCCESS) {
            ELMC_RC_LOG_FAIL(__alloc_rc, "#{function}", "allocation failed");
            return NULL;
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
        "ElmcValue *#{out} = NULL"
      else
        "#{out} = NULL"
      end

    failure =
      if return_on_fail? do
        """
        ELMC_RC_LOG_FAIL(__alloc_rc, "#{function}", "allocation failed");
        #{rc_failure_return(opts)};
        """
      else
        """
        ELMC_RC_LOG_FAIL(__alloc_rc, "#{function}", "allocation failed");
        #{out} = NULL;
        """
      end

    """
    #{init};
    {
      RC __alloc_rc = #{function}(&#{out}, #{call_args});
      if (__alloc_rc != RC_SUCCESS) {
        #{failure}
      }
    }
    """
    |> String.trim()
  end

  defp legacy_declare_out?(out, opts) do
    case Keyword.get(opts, :declare_out?) do
      true -> true
      false -> false
      nil -> Regex.match?(@fresh_owned_slot, out)
    end
  end

  defp rc_failure_return(opts) do
    failure_return(Keyword.get(opts, :env, %{}))
  end

  @spec failure_return(map()) :: String.t()
  def failure_return(env) do
    case Map.get(env, :__native_return_kind__) do
      :native_int -> "return 0"
      :native_bool -> "return 0"
      _ -> "return NULL"
    end
  end

  @doc "Fused `elmc_tuple2_take(left, new_int(rhs))` return."
  @spec fusion_tuple2_take_int_return(String.t(), String.t(), String.t()) :: String.t()
  def fusion_tuple2_take_int_return(_out, left, int_expr) do
    "return elmc_tuple2_take_value(#{left}, elmc_new_int_take(#{int_expr}));"
  end

  defp declared_out_slot?(env, out) do
    MapSet.member?(Map.get(env, :__declared_outs__, MapSet.new()), out)
  end

  defp predeclared_out_slot?(env, out) do
    declared_out_slot?(env, out) or Map.get(env, :__into_out__) == out
  end
end
