defmodule Elmc.Backend.CCodegen.RcRuntimeEmit do
  @moduledoc """
  RC ABI C emission helpers.

  Slot targeting (`compile_result_slot`, `function_tail_env`) is deprecated
  for Plan-primary functions — use `Elmc.Backend.Plan.Context` instead.
  """
  alias Elmc.Backend.CCodegen.Types, as: Types


  alias Elmc.Backend.CCodegen.CaseCompile
  alias Elmc.Backend.CCodegen.ListLoopCodegen
  alias Elmc.Backend.CCodegen.Types
  alias Elmc.Backend.CCodegen.ValueSlots

  @rc_allocators MapSet.new([
    "elmc_new_int",
    "elmc_new_bool",
    "elmc_new_order",
    "elmc_basics_compare",
    "elmc_cmd0",
    "elmc_cmd1",
    "elmc_cmd1_string",
    "elmc_cmd2",
    "elmc_cmd3",
    "elmc_cmd4",
    "elmc_cmd5",
    "elmc_sub0",
    "elmc_sub1",
    "elmc_sub2",
    "elmc_sub3",
    "elmc_sub4",
    "elmc_sub5",
    "elmc_new_string",
    "elmc_new_string_len",
    "elmc_new_float",
    "elmc_list_cons",
    "elmc_list_head",
    "elmc_list_tail",
    "elmc_list_length",
    "elmc_list_nth_maybe",
    "elmc_list_nth_maybe_int",
    "elmc_list_nth_int_default_boxed",
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
    "elmc_list_slice_int",
    "elmc_list_replace_nth_int",
    "elmc_list_partition",
    "elmc_list_unzip",
    "elmc_list_intersperse",
    "elmc_list_map2",
    "elmc_list_map3",
    "elmc_list_map4",
    "elmc_list_map5",
    "elmc_list_sum",
    "elmc_list_sum_float",
    "elmc_list_product",
    "elmc_list_product_float",
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
    "elmc_string_to_locale_upper",
    "elmc_string_to_locale_lower",
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
    "elmc_set_insert_int",
    "elmc_set_remove_int",
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
    "elmc_string_to_int",
    "elmc_string_to_float",
    "elmc_string_length_val",
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
    "elmc_result_ok_own",
    "elmc_result_err_own",
    "elmc_tuple2",
    "elmc_tuple2_take",
    "elmc_tuple2_ints",
    "elmc_tuple3",
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
    "elmc_closure_new_rc",
    "elmc_basics_mod_by",
    "elmc_basics_remainder_by",
    "elmc_basics_pow",
    "elmc_basics_negate",
    "elmc_basics_abs",
    "elmc_basics_round",
    "elmc_basics_floor",
    "elmc_basics_ceiling",
    "elmc_basics_truncate",
    "elmc_bitwise_and",
    "elmc_bitwise_or",
    "elmc_bitwise_xor",
    "elmc_bitwise_complement",
    "elmc_bitwise_shift_left_by",
    "elmc_bitwise_shift_right_by",
    "elmc_bitwise_shift_right_zf_by",
    "elmc_char_to_code",
    "elmc_dict_size",
    "elmc_set_size",
    "elmc_array_length",
    "elmc_time_now_millis",
    "elmc_time_zone_offset_minutes",
    "elmc_result_inc_or_zero",
    "elmc_new_char",
    "elmc_char_from_code",
    "elmc_char_from_code_int",
    "elmc_char_to_upper",
    "elmc_char_to_lower",
    "elmc_char_to_locale_upper",
    "elmc_char_to_locale_lower",
    "elmc_debug_to_string",
    "elmc_debug_set_to_string",
    "elmc_debug_dict_to_string",
    "elmc_debug_array_to_string",
    "elmc_debug_todo",
    "elmc_basics_to_float",
    "elmc_basics_sin",
    "elmc_basics_cos",
    "elmc_basics_tan",
    "elmc_basics_sqrt",
    "elmc_basics_log",
    "elmc_basics_log_base",
    "elmc_basics_atan",
    "elmc_basics_atan2",
    "elmc_basics_asin",
    "elmc_basics_acos",
    "elmc_basics_degrees",
    "elmc_basics_radians",
    "elmc_basics_turns",
    "elmc_basics_from_polar",
    "elmc_basics_to_polar",
    "elmc_string_from_int",
    "elmc_string_left",
    "elmc_string_right",
    "elmc_string_drop_left",
    "elmc_string_drop_right",
    "elmc_string_cons",
    "elmc_string_words",
    "elmc_string_lines",
    "elmc_string_pad",
    "elmc_array_set",
    "elmc_array_push",
    "elmc_result_to_maybe",
    "elmc_result_from_maybe",
    "elmc_basics_min",
    "elmc_basics_max",
    "elmc_basics_clamp",
    "elmc_debug_log",
    "elmc_append",
    "elmc_array_get",
    "elmc_cmd_backlight_from_maybe",
    "elmc_cmd_companion_send_value",
    "elmc_dict_singleton",
    "elmc_set_singleton",
    "elmc_set_to_list",
    "elmc_array_initialize",
    "elmc_array_repeat",
    "elmc_array_to_list",
    "elmc_array_to_indexed_list",
    "elmc_array_map",
    "elmc_array_indexed_map",
    "elmc_array_foldl",
    "elmc_array_foldr",
    "elmc_array_filter",
    "elmc_array_append",
    "elmc_array_slice",
    "elmc_dict_to_list",
    "elmc_json_encode_string",
    "elmc_json_encode_int",
    "elmc_json_encode_float",
    "elmc_json_encode_bool",
    "elmc_json_encode_null",
    "elmc_json_encode_list",
    "elmc_json_encode_array",
    "elmc_json_encode_set",
    "elmc_json_encode_object",
    "elmc_json_encode_add_field",
    "elmc_json_encode_add_entry",
    "elmc_json_encode_dict",
    "elmc_json_encode_encode",
    "elmc_task_succeed",
    "elmc_task_fail",
    "elmc_task_map",
    "elmc_task_map2",
    "elmc_task_sequence",
    "elmc_task_and_then",
    "elmc_task_command",
    "elmc_process_spawn",
    "elmc_process_sleep",
    "elmc_process_kill",
    "elmc_json_decode_value",
    "elmc_json_decode_string",
    "elmc_json_decode_string_decoder",
    "elmc_json_decode_int_decoder",
    "elmc_json_decode_float_decoder",
    "elmc_json_decode_bool_decoder",
    "elmc_json_decode_null",
    "elmc_json_decode_nullable",
    "elmc_json_decode_list",
    "elmc_json_decode_array",
    "elmc_json_decode_field",
    "elmc_json_decode_at",
    "elmc_json_decode_index",
    "elmc_json_decode_map",
    "elmc_json_decode_map2",
    "elmc_json_decode_map3",
    "elmc_json_decode_map4",
    "elmc_json_decode_map5",
    "elmc_json_decode_map6",
    "elmc_json_decode_map7",
    "elmc_json_decode_map8",
    "elmc_json_decode_succeed",
    "elmc_json_decode_fail",
    "elmc_json_decode_and_then",
    "elmc_json_decode_one_of",
    "elmc_json_decode_maybe",
    "elmc_json_decode_lazy",
    "elmc_json_decode_value_decoder",
    "elmc_json_decode_error_to_string",
    "elmc_json_decode_key_value_pairs",
    "elmc_json_decode_dict",
    "elmc_task_force",
    "elmc_cmd_batch",
    "elmc_cmd_map",
    "elmc_sub_batch",
    "elmc_sub_map",
    "elmc_port_outgoing",
    "elmc_port_incoming_sub",
    "elmc_build_constructor_payload",
    "elmc_record_update",
    "elmc_record_update_index",
    "elmc_record_update_index_cow",
    "elmc_record_update_index_cow_drop",
    "elmc_record_update_index_int_cow",
    "elmc_record_update_index_int_cow_drop",
    "elmc_record_update_index_bool_cow",
    "elmc_record_update_index_bool_cow_drop",
    "elmc_record_update_index_float_cow",
    "elmc_record_update_index_float_cow_drop",
    "elmc_string_chop_end",
    "elmc_string_chop_start",
    "elmc_string_chop_forward_slashes",
    "elmc_url_percent_encode",
    "elmc_url_percent_decode",
    "elmc_url_from_string",
    "elmc_url_to_string",
    "elmc_url_builder_absolute",
    "elmc_url_builder_relative",
    "elmc_url_builder_cross_origin",
    "elmc_url_builder_custom",
    "elmc_url_builder_query_string",
    "elmc_url_builder_query_int",
    "elmc_url_builder_to_query",
    "elmc_http_empty_body",
    "elmc_http_pair",
    "elmc_http_file_body",
    "elmc_http_multipart_body",
    "elmc_http_bytes_part",
    "elmc_http_to_form_data",
    "elmc_http_bytes_to_blob",
    "elmc_http_to_data_view",
    "elmc_http_expect",
    "elmc_http_map_expect",
    "elmc_http_expect_string",
    "elmc_http_expect_json",
    "elmc_http_expect_bytes",
    "elmc_http_expect_whatever",
    "elmc_http_expect_string_response",
    "elmc_http_expect_bytes_response",
    "elmc_http_command",
    "elmc_http_risky_command",
    "elmc_http_task",
    "elmc_http_risky_task",
    "elmc_http_string_resolver",
    "elmc_http_bytes_resolver",
    "elmc_http_cancel",
    "elmc_http_fraction_sent",
    "elmc_http_fraction_received",
    "elmc_backend_task_http_get_json",
    "elmc_backend_task_http_get",
    "elmc_backend_task_http_get_with_options",
    "elmc_backend_task_http_expect_json",
    "elmc_backend_task_http_expect_string",
    "elmc_backend_task_http_expect_whatever",
    "elmc_backend_task_http_expect_bytes",
    "elmc_backend_task_http_with_metadata",
    "elmc_backend_task_http_empty_body",
    "elmc_backend_task_http_string_body",
    "elmc_backend_task_http_json_body",
    "elmc_backend_task_http_bytes_body",
    "elmc_bytes_encode_sequence",
    "elmc_backend_task_http_request",
    "elmc_backend_task_http_post",
    "elmc_file_download_task",
    "elmc_file_select",
    "elmc_file_download",
    "elmc_file_download_url",
    "elmc_file_select_files",
    "elmc_file_name",
    "elmc_file_mime",
    "elmc_file_size",
    "elmc_file_last_modified",
    "elmc_file_to_string",
    "elmc_file_to_bytes",
    "elmc_file_to_url",
    "elmc_file_decoder",
    "elmc_random_generate",
    "elmc_regex_from_string",
    "elmc_regex_from_string_with",
    "elmc_regex_find",
    "elmc_regex_find_at_most",
    "elmc_regex_contains",
    "elmc_regex_never",
    "elmc_regex_replace",
    "elmc_regex_replace_at_most",
    "elmc_regex_split",
    "elmc_regex_split_at_most",
    "elmc_time_here",
    "elmc_time_get_zone_name",
    "elmc_time_utc",
    "elmc_time_custom_zone",
    "elmc_time_to_hour",
    "elmc_time_to_minute",
    "elmc_time_to_second",
    "elmc_time_to_millis",
    "elmc_time_to_year",
    "elmc_time_to_day",
    "elmc_time_to_month",
    "elmc_time_to_weekday",
    "elmc_browser_get_viewport",
    "elmc_browser_get_viewport_of",
    "elmc_browser_set_viewport",
    "elmc_browser_set_viewport_of",
    "elmc_browser_get_element",
    "elmc_browser_dom_focus",
    "elmc_browser_dom_blur"
  ])

  @own_transfer_allocators MapSet.new([
    "elmc_maybe_just_own",
    "elmc_result_ok_own",
    "elmc_result_err_own"
  ])

  # Allocators that read source values from a separate array/local; do not
  # eagerly release the out slot first — rec_values[] may still reference it.
  @array_source_transfer_allocators MapSet.new([
    "elmc_record_new_values_take",
    "elmc_record_new_values",
    "elmc_record_new_static_take",
    "elmc_record_new_take",
    "elmc_record_new",
    "elmc_record_new_values_ints",
    "elmc_list_from_values_take",
    "elmc_list_from_int_array_take"
  ])

  @function_out_marker "ELMC_FN_OUT_PLACEHOLDER_REMOVE_START"
    @function_out_marker "ELMC_FN_OUT"

  @fresh_owned_slot ~r/^(tmp_\d+(?:_[a-z0-9_]+)?|head_\d+|owned\[\d+\]|call_args_\d+|list_items_\d+|rec_values_\d+|list_map_item_\d+|list_indexed_map_item_\d+|list_map_cons_\d+|list_map_rev_\d+|list_fwd_cell_\d+|list_repeat_cons_\d+|string_segment_\d+|string_concat_acc_\d+|list_case_suffix_\d+)$/

  @spec function_out_ref() :: String.t()
  def function_out_ref, do: @function_out_marker

  @spec function_out_ref?(String.t()) :: boolean()
  def function_out_ref?(ref) when is_binary(ref), do: ref == @function_out_marker
  def function_out_ref?(_), do: false

  @spec fresh_owned_slot?(String.t()) :: boolean()
  def fresh_owned_slot?(ref) when is_binary(ref), do: Regex.match?(@fresh_owned_slot, ref)
  def fresh_owned_slot?(_), do: false

  @spec function_out_param() :: String.t()
  def function_out_param, do: "out"

  @spec function_out_deref() :: String.t()
  def function_out_deref, do: "*out"

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

  @doc "Join an out/first argument with optional trailing call args (no dangling comma)."
  @spec native_call_args(String.t(), String.t()) :: String.t()
  def native_call_args(first_arg, extra_args)
      when is_binary(first_arg) and is_binary(extra_args) do
    if extra_args == "", do: first_arg, else: "#{first_arg}, #{extra_args}"
  end

  @doc "Append optional parameter list to a native signature prefix."
  @spec native_signature_suffix(String.t(), String.t()) :: String.t()
  def native_signature_suffix(prefix, extra_params)
      when is_binary(prefix) and is_binary(extra_params) do
    if extra_params == "", do: prefix, else: "#{prefix}, #{extra_params}"
  end

  @doc "Expand a boxed slot ref for retain-or-default initializer (handles *out tail slot)."
  @spec retain_or_default(String.t(), String.t()) :: String.t()
  def retain_or_default(var, default_expr)
      when is_binary(var) and is_binary(default_expr) do
    cond do
      function_out_ref?(var) ->
        "(*out) ? elmc_retain((*out)) : #{default_expr}"

      true ->
        "#{var} ? elmc_retain(#{value_expr(var)}) : #{default_expr}"
    end
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
    out = ValueSlots.ensure_fresh_assign_target(out)
    stmt = ValueSlots.owned_reassign_prefix(out) <> "#{assignment_lhs(out)} = #{rhs};"

    if ValueSlots.owned_ref?(out) and rhs != "NULL" do
      ValueSlots.mark_written(out)
    end

    ValueSlots.register_record_field_retain_from_rhs(out, rhs)

    if function_out_ref?(out), do: ValueSlots.mark_function_out_written()

    stmt
  end

  @doc "C null assignment for a boxed value slot."
  @spec null_assign_stmt(String.t()) :: String.t()
  def null_assign_stmt(out) when is_binary(out), do: assign_stmt(out, "NULL")

  @doc """
  Copy `ref` into `out` with retain semantics; leave `ref` valid for later reads.

  Used when an if/case branch assigns a still-live let binding into a new slot.
  """
  @spec retain_copy_assignment(String.t(), String.t()) :: String.t()
  def retain_copy_assignment(out, ref) when is_binary(out) and is_binary(ref) do
    ref = ValueSlots.resolve_result_slot(ref)
    lhs = out

    if lhs == ref do
      ""
    else
      overwrite_prefix =
        if ValueSlots.owned_ref?(lhs) do
          ValueSlots.release_before_owned_transfer(lhs)
        else
          ValueSlots.release_if_owned_written(lhs)
        end

      stmt = "#{assignment_lhs(lhs)} = elmc_retain(#{value_expr(ref)});"

      if function_out_ref?(lhs), do: ValueSlots.mark_function_out_written()

      ValueSlots.sync_result_slot_current!(lhs)
      join_stmts([overwrite_prefix, stmt])
    end
  end

  @spec transfer_assignment(String.t(), String.t()) :: String.t()
  def transfer_assignment(out, ref) when is_binary(out) and is_binary(ref) do
    ref = ValueSlots.resolve_result_slot(ref)
    lhs = out

    if lhs == ref do
      ""
    else
      overwrite_prefix =
        if ValueSlots.owned_ref?(lhs) and ValueSlots.owned_ref?(ref) do
          ValueSlots.release_before_owned_transfer(lhs)
        else
          ValueSlots.release_if_owned_written(lhs)
        end

      stmt = "#{assignment_lhs(lhs)} = #{value_expr(ref)};"

      stmt =
        cond do
          function_out_ref?(lhs) and ValueSlots.owned_ref?(ref) ->
            abandon_owned_source(ref, stmt)

          ValueSlots.owned_ref?(lhs) and ValueSlots.owned_ref?(ref) ->
            abandon_owned_source(ref, stmt)

          true ->
            stmt
        end

      if function_out_ref?(lhs), do: ValueSlots.mark_function_out_written()

      ValueSlots.sync_result_slot_current!(lhs)
      join_stmts([overwrite_prefix, stmt])
    end
  end

  @doc """
  Merge a branch-owned scratch slot into the shared result slot after if/case.

  Does not eagerly release `dest` first: only one branch runs, so `dest` is still
  NULL at runtime when the other branch wrote `src`. Epilogue lifo releases the
  final value in `dest`.
  """
  @spec merge_branch_owned_slot(String.t(), String.t()) :: String.t()
  def merge_branch_owned_slot(dest, src) when is_binary(dest) and is_binary(src) do
    src = ValueSlots.resolve_result_slot(src)

    if dest == src do
      ""
    else
      ValueSlots.transfer(src)

      overwrite_prefix = ValueSlots.release_before_owned_transfer(dest)

      stmt =
        join_stmts([
          "#{assignment_lhs(dest)} = #{value_expr(src)};",
          ValueSlots.null_assignment(src)
        ])

      ValueSlots.sync_result_slot_current!(dest)
      join_stmts([overwrite_prefix, stmt])
    end
  end

  @spec join_stmts([String.t()]) :: String.t()

  defp join_stmts(stmts) when is_list(stmts) do
    stmts
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.join("\n")
  end

  @spec abandon_owned_source(String.t(), String.t()) :: String.t()

  defp abandon_owned_source(ref, stmt) do
    ValueSlots.transfer(ref)
    stmt <> "\n" <> ValueSlots.null_assignment(ref)
  end

  @spec allocator_out_arg(String.t()) :: String.t()
  def allocator_out_arg(out) when is_binary(out) do
    cond do
      function_out_ref?(out) -> function_out_param()
      out == "*out" -> "out"
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
    result_var = ValueSlots.resolve_result_slot(result_var)

    if ValueSlots.owned_ref?(result_var) do
      "#{function_out_deref()} = #{result_var};\n#{ValueSlots.null_assignment(result_var)}"
    else
      "#{function_out_deref()} = #{result_var};"
    end
  end

  @spec compare_order_slot(Types.compile_env(), non_neg_integer()) :: {String.t(), non_neg_integer()}
  def compare_order_slot(env, counter), do: CaseCompile.fresh_var(counter, env)

  @doc false
  @spec fn_out_alloc_target(Types.compile_env()) :: String.t() | nil
  def fn_out_alloc_target(env) do
    cond do
      function_tail_compile?(env) and
          Map.get(env, :__allow_fn_out_slot__, false) and
          Map.get(env, :__branch_out__) == function_out_ref() ->
        function_out_ref()

      function_tail_compile?(env) and Map.get(env, :__allow_fn_out_slot__, false) ->
        tail_call_out_target(env)

      true ->
        nil
    end
  end

  @doc """
  Compile env for binop/call/compare operands. Never allocate into `*out` mid-body.
  """
  @spec operand_env(Types.compile_env()) :: Types.compile_env()
  def operand_env(env),
    do: env |> Map.delete(:__allow_fn_out_slot__) |> Map.delete(:__branch_out__)

  @doc "Result slot for a runtime-call expression: branch/owned out, or a fresh owned slot."
  @spec compile_result_slot(Types.compile_env(), non_neg_integer()) :: {String.t(), non_neg_integer()}
  def compile_result_slot(env, counter) do
    if Map.get(env, :__transfer_operand__, false) do
      CaseCompile.fresh_var(counter, env)
    else
      compile_result_slot_branch(env, counter)
    end
  end

  @spec compile_result_slot_branch(Types.compile_env(), non_neg_integer()) ::
          {String.t(), non_neg_integer()}

  defp compile_result_slot_branch(env, counter) do
    branch_out = Map.get(env, :__branch_out__)

    cond do
      out = fn_out_alloc_target(env) ->
        {ValueSlots.ensure_fresh_assign_target(out), counter}

      out = nested_out_target(env) ->
        {ValueSlots.ensure_fresh_assign_target(out), counter}

      is_binary(branch_out) and branch_out_slot?(env, branch_out) ->
        {ValueSlots.ensure_fresh_assign_target(branch_out), counter}

      true ->
        CaseCompile.fresh_var(counter, env)
    end
  end

  @doc "Out slot for RC function calls."
  @spec compile_call_result_slot(Types.compile_env(), non_neg_integer()) :: {String.t(), non_neg_integer()}
  def compile_call_result_slot(env, counter), do: compile_result_slot(env, counter)

  @spec branch_out_slot?(Types.compile_env(), String.t()) :: boolean()

  defp branch_out_slot?(env, out) do
    (function_out_ref?(out) and function_tail_compile?(env)) or ValueSlots.owned_ref?(out) or
      predeclared_out_slot?(env, out)
  end

  @doc "Out slot for string/append fusion: branch out or nested into_out."
  @spec append_out_target(Types.compile_env()) :: String.t() | nil
  def append_out_target(env) do
    fn_out_alloc_target(env) || Map.get(env, :__branch_out__) || nested_out_target(env)
  end

  @doc """
  Result slot for list/string append: scratch for call operands, fresh branch slot for tails.
  Returned reg must match the slot `assign_call/4` writes (via `ensure_fresh_assign_target/1`).
  """
  @spec append_result_slot(Types.compile_env(), non_neg_integer()) :: {String.t(), non_neg_integer()}
  def append_result_slot(env, counter) do
    cond do
      Map.get(env, :__transfer_operand__, false) ->
        CaseCompile.fresh_var(counter, env)

      slot = append_out_target(env) ->
        {ValueSlots.ensure_fresh_assign_target(slot), counter}

      true ->
        compile_result_slot(env, counter)
    end
  end

  @spec with_function_out_target(Types.compile_env()) :: Types.compile_env()
  def with_function_out_target(env), do: Map.put(env, :__into_out__, function_out_ref())

  @doc "Compile env for the function's root tail expression only."
  @spec function_tail_env(Types.compile_env()) :: Types.compile_env()
  def function_tail_env(env) do
    env
    |> Map.put(:__function_tail_compile__, true)
    |> with_function_out_target()
    |> Map.put(:__allow_fn_out_slot__, true)
  end

  @spec function_tail_compile?(Types.compile_env()) :: boolean()
  def function_tail_compile?(env), do: Map.get(env, :__function_tail_compile__, false)

  @doc "Strip tail-only out targeting from let values, operands, and nested scopes."
  @spec strip_function_tail_scope(Types.compile_env()) :: Types.compile_env()
  def strip_function_tail_scope(env) do
    env
    |> Map.delete(:__function_tail_compile__)
    |> Map.delete(:__into_out__)
    |> Map.delete(:__allow_fn_out_slot__)
    |> Map.delete(:__branch_out__)
  end

  @doc """
  `__into_out__` when safe for nested subexpressions (never the function tail slot).
  """
  @spec nested_out_target(Types.compile_env()) :: String.t() | nil
  def nested_out_target(env) do
    case Map.get(env, :__into_out__) do
      @function_out_marker -> nil
      into_out when is_binary(into_out) -> ValueSlots.resolve_result_slot(into_out)
      _ -> nil
    end
  end

  @doc "Out slot for a direct tail call (`forward x = callee x x`)."
  @spec tail_call_out_target(Types.compile_env()) :: String.t() | nil
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
  @spec take_wrapper_assign(String.t(), String.t(), String.t(), Types.compile_env(), keyword()) :: String.t()
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
      non_rc_allocator_stmt(out, alloc_fn, call_args, opts)
    end
  end

  @doc "RC allocator assign outside CATCH (propagates RC, no value-returning shim)."
  @spec non_rc_allocator_stmt(String.t(), String.t(), String.t(), keyword()) :: String.t()
  def non_rc_allocator_stmt(out, function, call_args, opts \\ []) do
    legacy_rc_allocator_stmt(out, function, call_args, opts)
  end

  @spec rc_allocator?(String.t()) :: boolean()
  def rc_allocator?(function) when is_binary(function),
    do: MapSet.member?(@rc_allocators, function)

  def rc_allocator?(_), do: false

  @spec rc_mode?(Types.compile_env()) :: boolean()
  def rc_mode?(env),
    do: Map.get(env, :__rc_required__, false) and Map.get(env, :__rc_catch__, false)

  @spec rc_allocator_emit_mode?(Types.compile_env()) :: boolean()
  def rc_allocator_emit_mode?(env) when is_map(env) do
    Map.get(env, :__rc_required__, false) or Map.get(env, :__rc_catch__, false) or
      Map.get(env, :__native_rc_out__, false) or
      Process.get(:elmc_hoisted_native_ints_scope, false)
  end

  def rc_allocator_emit_mode?(_), do: false

  @spec rc_catch_env(Types.compile_env()) :: Types.compile_env()
  def rc_catch_env(env), do: Map.put(env, :__rc_catch__, true)

  @spec rc_style_codegen_body?(String.t()) :: boolean()
  def rc_style_codegen_body?(body) when is_binary(body) do
    body =~ "CHECK_RC(" or body =~ ~r/\bRc\s*=/ or body =~ "owned[" or body =~ "CATCH_BEGIN"
  end

  @spec generic_helper_extraction_allowed?(Types.compile_env(), String.t()) :: boolean()
  def generic_helper_extraction_allowed?(env, body) when is_binary(body) do
    not Map.get(env, :__rc_catch__, false) and
      not Map.get(env, :__rc_required__, false) and
      not Map.get(env, :__native_rc_out__, false) and
      not Map.get(env, :__inside_lambda__, false) and
      not rc_style_codegen_body?(body)
  end

  @doc false
  @spec allocator_assign(Types.compile_env(), String.t(), String.t(), String.t(), keyword()) :: String.t()
  def allocator_assign(env, out, function, call_args, opts \\ []) do
    opts = Keyword.put_new(opts, :env, env)

    if rc_allocator_emit_mode?(env) do
      rc_allocator_stmt(env, out, function, call_args, opts)
    else
      legacy_rc_allocator_stmt(out, function, call_args, opts)
    end
  end

  @spec assign_call(Types.compile_env(), String.t(), String.t(), String.t()) :: String.t()
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
  Like `assign_into/4`, but safe inside mutually exclusive branches that share one
  `out` slot. Restores ValueSlots marks between codegen passes so
  `ensure_fresh_assign_target/1` does not drift to a different owned index per branch.
  """
  @spec mutually_exclusive_assign_into(Types.compile_env(), String.t(), String.t(), String.t()) :: String.t()
  def mutually_exclusive_assign_into(env, out, function, call_args) do
    parent = ValueSlots.snapshot()
    ValueSlots.restore(parent)
    stmt = assign_into(env, out, function, call_args)
    ValueSlots.restore(parent)
    stmt
  end

  @doc """
  Like `allocator_assign/5`, but safe when emitting mutually exclusive branches to one out slot.
  """
  @spec mutually_exclusive_allocator_assign(Types.compile_env(), String.t(), String.t(), String.t(), keyword()) ::
          String.t()
  def mutually_exclusive_allocator_assign(env, out, function, call_args, opts \\ []) do
    parent = ValueSlots.snapshot()
    ValueSlots.restore(parent)
    stmt = allocator_assign(env, out, function, call_args, opts)
    ValueSlots.restore(parent)
    stmt
  end

  @doc """
  Assign into a pre-declared slot (for example `owned[3]` in if-branches).
  """
  @spec assign_into(Types.compile_env(), String.t(), String.t(), String.t()) :: String.t()
  def assign_into(env, out, function, call_args) do
    branch_final_assign_into(env, out, function, call_args, fresh_out?: true)
  end

  @doc """
  Assign a branch-final RC allocator into `out`.

  When `out` is the function tail slot (`ELMC_FN_OUT`), never reroute through a fresh
  owned slot — only the branch's last statement may publish to `*out`.
  """
  @spec branch_final_assign_into(Types.compile_env(), String.t(), String.t(), String.t(), keyword()) :: String.t()
  def branch_final_assign_into(env, out, function, call_args, opts \\ []) do
    fresh_out? = Keyword.get(opts, :fresh_out?, false)

    cond do
      not rc_allocator?(function) and rc_allocator_emit_mode?(env) and
          function_out_ref?(out) ->
        rc_function_out_stmt(env, out, function, call_args, fresh_out?: fresh_out?)

      not rc_allocator?(function) ->
        function_out_assign(env, out, "#{function}(#{call_args})")

      rc_allocator_emit_mode?(env) and function == "elmc_list_cons" ->
        int_list_cons_assign(env, out, call_args)

      rc_allocator_emit_mode?(env) ->
        allocator_assign(env, out, function, call_args,
          declare_out?: false,
          fresh_out?: fresh_out?
        )

      true ->
        legacy_rc_allocator_stmt(out, function, call_args, declare_out?: false, env: env)
    end
  end

  @spec rc_function_out_stmt(Types.compile_env(), String.t(), String.t(), String.t(), keyword()) ::
          String.t()

  defp rc_function_out_stmt(_env, out, function, call_args, opts) do
    fresh_out? = Keyword.get(opts, :fresh_out?, false)

    out =
      if function_out_ref?(out) or not fresh_out? do
        out
      else
        ValueSlots.ensure_fresh_assign_target(out)
      end

    stmt =
      """
      Rc = #{function}(#{allocator_out_arg(out)}, #{call_args});
      CHECK_RC(Rc);
      """
      |> String.trim()

    if function_out_ref?(out), do: ValueSlots.mark_function_out_written()
    if ValueSlots.owned_ref?(out), do: ValueSlots.mark_written(out)

    stmt
  end

  @doc "List.cons with retain semantics for borrowed head/tail operands."
  @spec list_cons_retain_assign(String.t(), String.t(), Types.compile_env(), keyword()) :: String.t()
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

  @spec int_list_cons_assign(Types.compile_env(), String.t(), String.t(), keyword()) :: String.t()

  defp int_list_cons_assign(env, out, call_args, opts \\ []) do
    loop_id = Keyword.get(opts, :loop_id, 0)

    case parse_call_args_pair(call_args) do
      {head, tail} ->
        ListLoopCodegen.emit_int_list_cons_assign(env, out, head, tail, loop_id, opts)

      :error ->
        allocator_assign(env, out, "elmc_list_cons", call_args, opts)
    end
  end

  @spec parse_call_args_pair(String.t()) :: {String.t(), String.t()} | :error

  defp parse_call_args_pair(call_args) when is_binary(call_args) do
    case String.split(call_args, ", ", parts: 2) do
      [head, tail] -> {String.trim(head), String.trim(tail)}
      _ -> :error
    end
  end

  @doc "RC assign in catch blocks; take wrapper otherwise."
  @spec assign_or_fusion(Types.compile_env(), String.t(), String.t(), String.t()) :: String.t()
  def assign_or_fusion(env, out, function, call_args) do
    if rc_allocator_emit_mode?(env) do
      allocator_assign(env, out, function, call_args)
    else
      fusion_assign(out, function, call_args, env)
    end
  end

  @doc "RC allocator assign for fused/native C snippets."
  @spec fusion_assign(String.t(), String.t(), String.t(), Types.compile_env(), keyword()) :: String.t()
  def fusion_assign(out, function, call_args, env \\ %{}, opts \\ []) do
    if rc_allocator_emit_mode?(env) do
      allocator_assign(env, out, function, call_args, opts)
    else
      non_rc_allocator_stmt(out, function, call_args, Keyword.merge(opts, env: env))
    end
  end

  @doc "RC allocator return for fused C snippets."
  @spec fusion_return(String.t(), String.t(), String.t(), Types.compile_env()) :: String.t()
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
    # Plan dest `*out` on ElmcValue*-returning (non-RC) functions means "return the
    # allocation", not a real `out` parameter.
    if out == "*out" and Keyword.get(opts, :return_on_fail?, true) do
      fusion_return(out, function, call_args, Keyword.get(opts, :env, %{}))
    else
      legacy_rc_allocator_assign_stmt(out, function, call_args, opts)
    end
  end

  defp legacy_rc_allocator_assign_stmt(out, function, call_args, opts) do
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

  @spec rc_failure_return(keyword()) :: String.t()

  defp rc_failure_return(opts) do
    failure_return(Keyword.get(opts, :env, %{}))
  end

  @spec legacy_declare_out?(String.t(), keyword()) :: boolean()

  defp legacy_declare_out?(out, opts) do
    case Keyword.get(opts, :declare_out?) do
      true ->
        true

      false ->
        false

      nil ->
        env = Keyword.get(opts, :env, %{})

        not predeclared_out_slot?(env, out) and Regex.match?(@fresh_owned_slot, out)
    end
  end

  @spec failure_return(Types.compile_env()) :: String.t()

  def failure_return(env) do
    cond do
      Map.get(env, :__rc_catch__) || Map.get(env, :__rc_required__) ||
          Process.get(:elmc_hoisted_native_ints_scope, false) ->
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
  @spec check_rc_take(String.t(), String.t(), String.t(), Types.compile_env(), keyword()) :: String.t()
  def check_rc_take(out, function, call_args, env \\ %{}, opts \\ []) do
    if rc_allocator_emit_mode?(env) do
      rc_allocator_stmt(env, out, function, call_args, opts)
    else
      fusion_assign(out, function, call_args, env, opts)
    end
  end

  @doc "After a loop that may set Rc via CHECK_RC, break out of CATCH_BEGIN when failed."
  @spec loop_exit_check_rc(Types.compile_env()) :: String.t()
  def loop_exit_check_rc(env \\ %{}) do
    if rc_allocator_emit_mode?(env), do: "CHECK_RC(Rc);", else: ""
  end

  @doc """
  Assign `(*out, left, new_int(rhs))` inside a `CATCH_BEGIN` body.

  Uses `owned_slot` (default `owned[0]`) so `CATCH_END` + `elmc_release_array_lifo`
  can clean up on failure. Caller must declare the owned array and run LIFO release
  before returning from the fusion function.
  """
  @spec fusion_tuple2_take_int_out(String.t(), String.t(), String.t(), String.t()) :: String.t()
  def fusion_tuple2_take_int_out(out, left, int_expr, owned_slot \\ "owned[0]") do
    """
    Rc = elmc_new_int(#{fusion_owned_slot_addr(owned_slot)}, #{int_expr});
    CHECK_RC(Rc);
    Rc = elmc_tuple2_take(#{out}, #{left}, #{owned_slot});
    CHECK_RC(Rc);
    #{owned_slot} = NULL;
    """
    |> String.trim()
  end

  @doc """
  Fused `elmc_tuple2_take(left, new_int(rhs))` with early return.

  Uses the same owned-slot convention as `fusion_tuple2_take_int_out/4`.
  """
  @spec fusion_tuple2_take_int_return(String.t(), String.t(), String.t(), Types.compile_env(), String.t()) ::
          String.t()
  def fusion_tuple2_take_int_return(_out, left, int_expr, env \\ %{}, owned_slot \\ "owned[0]") do
    failure = failure_return(env)

    """
    {
      ElmcValue *owned[1] = {0};
      ElmcValue *__pair = NULL;
      Rc = elmc_new_int(#{fusion_owned_slot_addr(owned_slot)}, #{int_expr});
      if (Rc != RC_SUCCESS) {
        ELMC_RC_LOG_FAIL(Rc, "elmc_new_int", "allocation failed");
        elmc_release_array_lifo(owned, DIM(owned));
        #{failure}
      }
      Rc = elmc_tuple2_take(&__pair, #{left}, #{owned_slot});
      #{owned_slot} = NULL;
      if (Rc != RC_SUCCESS) {
        ELMC_RC_LOG_FAIL(Rc, "elmc_tuple2_take", "allocation failed");
        elmc_release_array_lifo(owned, DIM(owned));
        #{failure}
      }
      elmc_release_array_lifo(owned, DIM(owned));
      return __pair;
    }
    """
    |> String.trim()
  end

  @spec fusion_owned_slot_addr(String.t()) :: String.t()

  defp fusion_owned_slot_addr("owned[" <> _ = slot), do: "&#{slot}"
  defp fusion_owned_slot_addr(slot) when is_binary(slot), do: "&#{slot}"

  @spec declared_out_slot?(Types.compile_env(), String.t()) :: boolean()
  defp declared_out_slot?(env, out) do
    MapSet.member?(Map.get(env, :__declared_outs__, MapSet.new()), out)
  end

  @doc false
  @spec predeclared_out_slot?(Types.compile_env(), String.t()) :: boolean()
  def predeclared_out_slot?(env, out) do
    declared_out_slot?(env, out) or Map.get(env, :__into_out__) == out or
      Map.get(env, :__branch_out__) == out
  end

  @spec rc_owned_slot?(String.t()) :: boolean()

  defp rc_owned_slot?(out), do: ValueSlots.owned_ref?(out)

  @doc false
  @spec rc_allocator_stmt(Types.compile_env(), String.t(), String.t(), String.t(), keyword()) :: String.t()
  def rc_allocator_stmt(env, out, function, call_args, opts \\ []) do
    out =
      if function_out_ref?(out) or not Keyword.get(opts, :fresh_out?, true) do
        out
      else
        ValueSlots.ensure_fresh_assign_target(out)
      end

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
      if rc_owned_slot?(out) and not allocator_same_slot_transfer?(out, function, call_args) and
           not array_source_transfer_skip_preempt?(function) do
        ValueSlots.owned_reassign_prefix(out)
      else
        ""
      end

    stmt =
      """
      #{preempt}#{init}Rc = #{function}(#{allocator_out_arg(out)}, #{call_args});
      CHECK_RC(Rc);
      """
      |> String.trim()
      |> then(&(&1 <> result_payload_owned_release(function, call_args)))

    if rc_owned_slot?(out), do: ValueSlots.mark_written(out)
    if function_out_ref?(out), do: ValueSlots.mark_function_out_written()
    ValueSlots.sync_result_slot_current!(out)

    stmt
  end

  @spec allocator_same_slot_transfer?(String.t(), String.t(), String.t()) :: boolean()

  defp allocator_same_slot_transfer?(out, function, call_args)
       when is_binary(out) and is_binary(function) and is_binary(call_args) do
    MapSet.member?(@own_transfer_allocators, function) and
      String.trim(call_args) == out
  end

  # Array-source record/list allocators skip eager out-slot release on the first
  # assignment in a branch, but loop iterations still overwrite prior out values.
  @spec array_source_transfer_skip_preempt?(String.t()) :: boolean()

  defp array_source_transfer_skip_preempt?(function) when is_binary(function) do
    MapSet.member?(@array_source_transfer_allocators, function) and not ValueSlots.in_c_loop?()
  end

  @spec function_out_assign(Types.compile_env(), String.t(), String.t()) :: String.t()

  defp function_out_assign(_env, out, rhs) when is_binary(out) and is_binary(rhs) do
    if function_out_ref?(out) and ValueSlots.owned_ref?(rhs) do
      transfer_assignment(out, rhs)
    else
      prefix =
        if ValueSlots.owned_ref?(out) do
          ValueSlots.owned_reassign_prefix(out)
        else
          ""
        end

      if function_out_ref?(out), do: ValueSlots.mark_function_out_written()
      if ValueSlots.owned_ref?(out), do: ValueSlots.mark_written(out)

      prefix <> "#{assignment_lhs(out)} = #{rhs};"
    end
  end

  @spec result_payload_owned_release(String.t(), String.t()) :: String.t()

  defp result_payload_owned_release(function, _call_args)
       when function in ["elmc_result_ok_own", "elmc_result_err_own"], do: ""

  defp result_payload_owned_release(function, call_args)
       when function in ["elmc_result_ok", "elmc_result_err"] and is_binary(call_args) do
    arg = String.trim(call_args)

    if ValueSlots.owned_ref?(arg) do
      release = ValueSlots.release_consumed(arg)

      if release == "", do: "", else: "\n" <> release
    else
      ""
    end
  end

  defp result_payload_owned_release(_function, _call_args), do: ""
end
