defmodule Elmc.Backend.Plan.RuntimeBuiltins.Extra do
  @moduledoc false


  @extra_builtins %{
    port_outgoing: "elmc_port_outgoing",
    port_incoming_sub: "elmc_port_incoming_sub",
    array_append: "elmc_array_append",
    array_empty: "elmc_array_empty",
    array_filter: "elmc_array_filter",
    array_foldl: "elmc_array_foldl",
    array_foldr: "elmc_array_foldr",
    array_from_list: "elmc_array_from_list",
    array_get: "elmc_array_get",
    array_indexed_map: "elmc_array_indexed_map",
    array_initialize: "elmc_array_initialize",
    array_is_empty: "elmc_array_is_empty",
    array_length: "elmc_array_length",
    array_map: "elmc_array_map",
    array_push: "elmc_array_push",
    array_repeat: "elmc_array_repeat",
    array_set: "elmc_array_set",
    array_slice: "elmc_array_slice",
    array_to_indexed_list: "elmc_array_to_indexed_list",
    array_to_list: "elmc_array_to_list",
    append: "elmc_append",
    basics_abs: "elmc_basics_abs",
    basics_acos: "elmc_basics_acos",
    basics_asin: "elmc_basics_asin",
    basics_atan: "elmc_basics_atan",
    basics_atan2: "elmc_basics_atan2",
    basics_degrees: "elmc_basics_degrees",
    basics_from_polar: "elmc_basics_from_polar",
    basics_is_infinite: "elmc_basics_is_infinite",
    basics_is_nan: "elmc_basics_is_nan",
    basics_log: "elmc_basics_log",
    basics_log_base: "elmc_basics_log_base",
    basics_radians: "elmc_basics_radians",
    basics_sqrt: "elmc_basics_sqrt",
    basics_tan: "elmc_basics_tan",
    basics_to_polar: "elmc_basics_to_polar",
    basics_turns: "elmc_basics_turns",
    basics_ceiling: "elmc_basics_ceiling",
    basics_compare: "elmc_basics_compare",
    basics_negate: "elmc_basics_negate",
    basics_truncate: "elmc_basics_truncate",
    basics_xor: "elmc_basics_xor",
    bitwise_and: "elmc_bitwise_and",
    bitwise_complement: "elmc_bitwise_complement",
    bitwise_or: "elmc_bitwise_or",
    bitwise_shift_left_by: "elmc_bitwise_shift_left_by",
    bitwise_shift_right_by: "elmc_bitwise_shift_right_by",
    bitwise_shift_right_zf_by: "elmc_bitwise_shift_right_zf_by",
    bitwise_xor: "elmc_bitwise_xor",
    char_is_alpha: "elmc_char_is_alpha",
    char_is_alpha_num: "elmc_char_is_alpha_num",
    char_is_digit: "elmc_char_is_digit",
    char_is_hex_digit: "elmc_char_is_hex_digit",
    char_is_lower: "elmc_char_is_lower",
    char_is_oct_digit: "elmc_char_is_oct_digit",
    char_is_upper: "elmc_char_is_upper",
    char_to_code: "elmc_char_to_code",
    char_to_lower: "elmc_char_to_lower",
    char_to_upper: "elmc_char_to_upper",
    debug_log: "elmc_debug_log",
    debug_todo: "elmc_debug_todo",
    dict_diff: "elmc_dict_diff",
    dict_filter: "elmc_dict_filter",
    dict_foldl: "elmc_dict_foldl",
    dict_foldr: "elmc_dict_foldr",
    dict_from_list: "elmc_dict_from_list",
    dict_get: "elmc_dict_get",
    dict_insert: "elmc_dict_insert",
    dict_intersect: "elmc_dict_intersect",
    dict_is_empty: "elmc_dict_is_empty",
    dict_keys: "elmc_dict_keys",
    dict_map: "elmc_dict_map",
    dict_member: "elmc_dict_member",
    dict_merge: "elmc_dict_merge",
    dict_partition: "elmc_dict_partition",
    dict_remove: "elmc_dict_remove",
    dict_singleton: "elmc_dict_singleton",
    dict_size: "elmc_dict_size",
    dict_to_list: "elmc_dict_to_list",
    dict_union: "elmc_dict_union",
    dict_update: "elmc_dict_update",
    dict_values: "elmc_dict_values",
    json_decode_and_then: "elmc_json_decode_and_then",
    json_decode_array: "elmc_json_decode_array",
    json_decode_at: "elmc_json_decode_at",
    json_decode_bool_decoder: "elmc_json_decode_bool_decoder",
    json_decode_dict: "elmc_json_decode_dict",
    json_decode_error_to_string: "elmc_json_decode_error_to_string",
    json_decode_fail: "elmc_json_decode_fail",
    json_decode_field: "elmc_json_decode_field",
    json_decode_float_decoder: "elmc_json_decode_float_decoder",
    json_decode_index: "elmc_json_decode_index",
    json_decode_int_decoder: "elmc_json_decode_int_decoder",
    json_decode_key_value_pairs: "elmc_json_decode_key_value_pairs",
    json_decode_lazy: "elmc_json_decode_lazy",
    json_decode_list: "elmc_json_decode_list",
    json_decode_map: "elmc_json_decode_map",
    json_decode_map2: "elmc_json_decode_map2",
    json_decode_map3: "elmc_json_decode_map3",
    json_decode_map4: "elmc_json_decode_map4",
    json_decode_map5: "elmc_json_decode_map5",
    json_decode_map6: "elmc_json_decode_map6",
    json_decode_map7: "elmc_json_decode_map7",
    json_decode_maybe: "elmc_json_decode_maybe",
    json_decode_null: "elmc_json_decode_null",
    json_decode_nullable: "elmc_json_decode_nullable",
    json_decode_one_of: "elmc_json_decode_one_of",
    json_decode_string: "elmc_json_decode_string",
    json_decode_string_decoder: "elmc_json_decode_string_decoder",
    json_decode_succeed: "elmc_json_decode_succeed",
    json_decode_value: "elmc_json_decode_value",
    json_decode_value_decoder: "elmc_json_decode_value_decoder",
    json_encode_array: "elmc_json_encode_array",
    json_encode_add_entry: "elmc_json_encode_add_entry",
    json_encode_add_field: "elmc_json_encode_add_field",
    json_encode_bool: "elmc_json_encode_bool",
    json_encode_dict: "elmc_json_encode_dict",
    json_encode_encode: "elmc_json_encode_encode",
    json_encode_float: "elmc_json_encode_float",
    json_encode_int: "elmc_json_encode_int",
    json_encode_list: "elmc_json_encode_list",
    json_encode_null: "elmc_json_encode_null",
    json_encode_object: "elmc_json_encode_object",
    json_encode_set: "elmc_json_encode_set",
    json_encode_string: "elmc_json_encode_string",
    list_drop_int: "elmc_list_drop_int",
    list_find_first: "elmc_list_find_first",
    list_foldr: "elmc_list_foldr",
    list_from_values: "elmc_list_from_values",
    list_intersperse: "elmc_list_intersperse",
    list_map2: "elmc_list_map2",
    list_map3: "elmc_list_map3",
    list_map4: "elmc_list_map4",
    list_map5: "elmc_list_map5",
    list_maximum: "elmc_list_maximum",
    list_member: "elmc_list_member",
    list_minimum: "elmc_list_minimum",
    list_partition: "elmc_list_partition",
    list_product: "elmc_list_product",
    list_singleton: "elmc_list_singleton",
    list_sort: "elmc_list_sort",
    list_sum: "elmc_list_sum",
    list_unzip: "elmc_list_unzip",
    maybe_map2: "elmc_maybe_map2",
    new_char: "elmc_new_char",
    process_kill: "elmc_process_kill",
    process_sleep: "elmc_process_sleep",
    process_spawn: "elmc_process_spawn",
    result_from_maybe: "elmc_result_from_maybe",
    result_to_maybe: "elmc_result_to_maybe",
    result_with_default: "elmc_result_with_default",
    set_diff: "elmc_set_diff",
    set_filter: "elmc_set_filter",
    set_foldl: "elmc_set_foldl",
    set_foldr: "elmc_set_foldr",
    set_from_list: "elmc_set_from_list",
    set_insert: "elmc_set_insert",
    set_intersect: "elmc_set_intersect",
    set_is_empty: "elmc_set_is_empty",
    set_map: "elmc_set_map",
    set_member: "elmc_set_member",
    set_partition: "elmc_set_partition",
    set_remove: "elmc_set_remove",
    set_singleton: "elmc_set_singleton",
    set_size: "elmc_set_size",
    set_to_list: "elmc_set_to_list",
    set_union: "elmc_set_union",
    string_all: "elmc_string_all",
    string_any: "elmc_string_any",
    string_cons: "elmc_string_cons",
    string_contains: "elmc_string_contains",
    string_drop_left: "elmc_string_drop_left",
    string_drop_right: "elmc_string_drop_right",
    string_filter: "elmc_string_filter",
    string_foldl: "elmc_string_foldl",
    string_foldr: "elmc_string_foldr",
    string_from_char: "elmc_string_from_char",
    string_from_float: "elmc_string_from_float",
    string_from_int_value: "elmc_string_from_int",
    string_from_list: "elmc_string_from_list",
    string_indexes: "elmc_string_indexes",
    string_length_val: "elmc_string_length_val",
    string_lines: "elmc_string_lines",
    string_map: "elmc_string_map",
    string_pad: "elmc_string_pad",
    string_pad_left: "elmc_string_pad_left",
    string_pad_right: "elmc_string_pad_right",
    string_repeat: "elmc_string_repeat",
    string_replace: "elmc_string_replace",
    string_reverse: "elmc_string_reverse",
    string_right: "elmc_string_right",
    string_slice: "elmc_string_slice",
    string_split: "elmc_string_split",
    string_equals: "elmc_string_equals",
    string_equals_literal: "elmc_string_equals_cstr",
    list_equal_int: "elmc_list_equal_int",
    string_to_list: "elmc_string_to_list",
    string_to_lower: "elmc_string_to_lower",
    string_to_upper: "elmc_string_to_upper",
    string_trim: "elmc_string_trim",
    string_trim_left: "elmc_string_trim_left",
    string_trim_right: "elmc_string_trim_right",
    string_uncons: "elmc_string_uncons",
    string_words: "elmc_string_words",
    string_chop_end: "elmc_string_chop_end",
    string_chop_start: "elmc_string_chop_start",
    string_chop_forward_slashes: "elmc_string_chop_forward_slashes",
    url_percent_encode: "elmc_url_percent_encode",
    url_percent_decode: "elmc_url_percent_decode",
    url_from_string: "elmc_url_from_string",
    http_empty_body: "elmc_http_empty_body",
    http_pair: "elmc_http_pair",
    http_to_data_view: "elmc_http_to_data_view",
    http_expect: "elmc_http_expect",
    http_command: "elmc_http_command",
    http_cancel: "elmc_http_cancel",
    backend_task_http_get_json: "elmc_backend_task_http_get_json",
    backend_task_http_get: "elmc_backend_task_http_get",
    backend_task_http_get_with_options: "elmc_backend_task_http_get_with_options",
    backend_task_http_expect_json: "elmc_backend_task_http_expect_json",
    backend_task_http_expect_string: "elmc_backend_task_http_expect_string",
    backend_task_http_expect_whatever: "elmc_backend_task_http_expect_whatever",
    backend_task_http_expect_bytes: "elmc_backend_task_http_expect_bytes",
    backend_task_http_with_metadata: "elmc_backend_task_http_with_metadata",
    backend_task_http_empty_body: "elmc_backend_task_http_empty_body",
    backend_task_http_string_body: "elmc_backend_task_http_string_body",
    backend_task_http_json_body: "elmc_backend_task_http_json_body",
    backend_task_http_bytes_body: "elmc_backend_task_http_bytes_body",
    bytes_encode_sequence: "elmc_bytes_encode_sequence",
    backend_task_http_request: "elmc_backend_task_http_request",
    backend_task_http_post: "elmc_backend_task_http_post",
    file_download_task: "elmc_file_download_task",
    file_select: "elmc_file_select",
    file_download: "elmc_file_download",
    task_fail: "elmc_task_fail",
    task_succeed: "elmc_task_succeed",
    task_map: "elmc_task_map",
    task_map2: "elmc_task_map2",
    task_and_then: "elmc_task_and_then",
    task_on_error: "elmc_task_on_error",
    task_perform: "elmc_task_perform",
    task_command: "elmc_task_command",
    cmd_map: "elmc_cmd_map",
    sub_map: "elmc_sub_map",
    tuple_map_both: "elmc_tuple_map_both",
    tuple_map_first: "elmc_tuple_map_first",
    tuple_map_second: "elmc_tuple_map_second",
    time_now_millis: "elmc_time_now_millis",
    time_zone_offset_minutes: "elmc_time_zone_offset_minutes",
    time_here: "elmc_time_here",
    browser_get_viewport: "elmc_browser_get_viewport",
    random_generate: "elmc_random_generate",
    regex_from_string: "elmc_regex_from_string",
    regex_find: "elmc_regex_find",
    regex_contains: "elmc_regex_contains",
    regex_replace: "elmc_regex_replace"
  }

  @symbol_aliases %{
    "elmc_string_from_int" => :string_from_int_value
  }

  @extra_fallible ~w(
    basics_compare dict_get list_maximum list_minimum list_product list_sum
    dict_diff dict_filter dict_foldl dict_foldr dict_from_list dict_insert
    dict_intersect dict_keys dict_map dict_merge dict_partition dict_remove dict_union
    dict_update dict_values
    list_drop_int list_find_first list_foldr list_from_values list_intersperse list_map2 list_map3 list_map4
    list_map5 list_partition list_singleton list_sort list_unzip maybe_map2
    set_diff set_filter set_foldl set_foldr set_from_list set_insert set_intersect set_map
    set_partition set_remove set_union
    string_all string_any string_filter string_foldl string_foldr string_from_char string_from_float
    string_from_list string_indexes string_map string_pad_left string_pad_right string_repeat
    string_replace string_reverse string_slice string_split string_to_list string_to_lower
    string_to_upper string_trim string_trim_left string_trim_right string_uncons
    tuple_map_both tuple_map_first tuple_map_second
    array_length array_push array_set
    basics_abs basics_acos basics_asin basics_atan basics_atan2 basics_ceiling
    basics_degrees basics_from_polar basics_log basics_log_base basics_negate
    basics_radians basics_sqrt basics_tan basics_to_polar basics_truncate basics_turns
    bitwise_and bitwise_complement bitwise_or
    bitwise_shift_left_by bitwise_shift_right_by bitwise_shift_right_zf_by bitwise_xor
    char_to_code char_to_lower char_to_upper debug_todo dict_size new_char
    result_from_maybe result_inc_or_zero result_to_maybe set_size
    string_cons string_drop_left string_drop_right string_from_int_value string_length_val
    string_lines string_pad string_right string_words
    time_now_millis time_zone_offset_minutes
    append array_append array_filter array_foldl array_foldr array_get
    array_indexed_map array_initialize array_map array_repeat array_slice
    array_to_indexed_list array_to_list
    cmd_backlight_from_maybe debug_log
    dict_singleton set_singleton set_to_list
    dict_to_list
    json_encode_array json_encode_add_entry json_encode_add_field
    json_encode_bool json_encode_dict
    json_encode_encode json_encode_float json_encode_int json_encode_list json_encode_null
    json_encode_object json_encode_set json_encode_string
    task_and_then task_command task_fail task_map task_map2 task_succeed
    process_kill process_sleep process_spawn
    json_decode_and_then json_decode_array json_decode_at json_decode_bool_decoder
    json_decode_dict json_decode_error_to_string json_decode_fail json_decode_field
    json_decode_float_decoder json_decode_index json_decode_int_decoder
    json_decode_key_value_pairs json_decode_lazy json_decode_list json_decode_map
    json_decode_map2 json_decode_map3 json_decode_map4 json_decode_map5 json_decode_map6
    json_decode_map7 json_decode_maybe json_decode_null json_decode_nullable json_decode_one_of
    json_decode_string json_decode_string_decoder json_decode_succeed json_decode_value
    json_decode_value_decoder
    task_force
    cmd_map sub_map cmd_batch sub_batch
    port_outgoing port_incoming_sub
    record_update_cow_drop
    string_chop_end string_chop_start string_chop_forward_slashes
    url_percent_encode url_percent_decode url_from_string
    http_command http_cancel http_empty_body http_expect http_pair http_to_data_view
    backend_task_http_get_json backend_task_http_get backend_task_http_get_with_options
    backend_task_http_expect_json backend_task_http_expect_string backend_task_http_expect_whatever
    backend_task_http_expect_bytes backend_task_http_with_metadata
    backend_task_http_empty_body backend_task_http_string_body backend_task_http_json_body
    backend_task_http_bytes_body bytes_encode_sequence
    backend_task_http_request backend_task_http_post
    file_download file_download_task file_select
    random_generate regex_contains regex_find regex_from_string regex_replace
    time_here browser_get_viewport
  )a

  # Empty: allocating helpers must be RC + fallible, never value-return OOM ABI.
  @extra_c_value_return ~w()a

  @extra_value_return ~w(
    array_empty array_from_list array_is_empty char_is_alpha char_is_alpha_num
    char_is_digit char_is_hex_digit char_is_lower char_is_oct_digit char_is_upper
    dict_is_empty dict_member list_member list_equal_int set_is_empty set_member
    basics_is_infinite basics_is_nan basics_xor string_contains
    task_on_error task_perform
  )a

  @spec builtins() :: %{atom() => String.t()}

  def builtins, do: @extra_builtins
  @spec symbol_aliases() :: %{String.t() => atom()}

  def symbol_aliases, do: @symbol_aliases
  @spec fallible_ids() :: [atom()]

  def fallible_ids, do: @extra_fallible
  @spec c_value_return_ids() :: [atom()]

  def c_value_return_ids, do: @extra_c_value_return
  @spec value_return_ids() :: [atom()]

  def value_return_ids, do: @extra_value_return
end
