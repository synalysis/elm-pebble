defmodule Elmc.Backend.Plan.RuntimeBuiltins do
  @moduledoc """
  Logical runtime builtin ids for `call_runtime` plan ops.

  C maps to `elmc_*` symbols; bytecode to opcode indices; future WASM to imports.
  """

  alias Elmc.Backend.Plan.RuntimeBuiltins.Extra

  @native_int_arg_indices %{
    list_slice_int: [0, 1],
    list_take: [0],
    list_drop: [0],
    string_from_int: [0],
    tuple2_ints: [0, 1],
    list_filter_record_field: [1],
    list_filter_record_and: [1, 2],
    list_map_record_field: [1]
  }

  @builtins Map.merge(%{
    list_append: "elmc_list_append",
    list_cons: "elmc_list_cons",
    list_nil: "elmc_list_nil",
    list_repeat: "elmc_list_repeat",
    list_range: "elmc_list_range",
    list_map: "elmc_list_map",
    list_all: "elmc_list_all",
    list_any: "elmc_list_any",
    list_filter: "elmc_list_filter",
    list_filter_record_field: "elmc_list_filter_record_field",
    list_filter_record_and: "elmc_list_filter_record_and",
    list_map_record_field: "elmc_list_map_record_field",
    list_indexed_map: "elmc_list_indexed_map",
    list_length: "elmc_list_length",
    list_concat: "elmc_list_concat",
    list_slice_int: "elmc_list_slice_int",
    list_take: "elmc_list_take",
    list_drop: "elmc_list_drop",
    list_concat_map: "elmc_list_concat_map",
    list_filter_map: "elmc_list_filter_map",
    list_foldl: "elmc_list_foldl",
    list_sort_by: "elmc_list_sort_by",
    list_sort_with: "elmc_list_sort_with",
    list_reverse: "elmc_list_reverse",
    list_head: "elmc_list_head",
    list_tail: "elmc_list_tail",
    int_list_head_boxed: "elmc_int_list_head_boxed",
    int_list_head_int: "elmc_list_head_with_default_int",
    int_list_tail: "elmc_int_list_tail",
    list_is_empty: "elmc_list_is_empty",
    list_nth_maybe: "elmc_list_nth_maybe",
    list_nth_int_default: "elmc_list_nth_int_default_boxed",
    maybe_with_default: "elmc_maybe_with_default",
    maybe_map: "elmc_maybe_map",
    basics_min: "elmc_basics_min",
    basics_max: "elmc_basics_max",
    basics_mod_by: "elmc_basics_mod_by",
    basics_remainder_by: "elmc_basics_remainder_by",
    basics_not: "elmc_basics_not",
    basics_clamp: "elmc_basics_clamp",
    string_append: "elmc_string_append",
    string_from_int: "elmc_string_from_native_int",
    string_to_int: "elmc_string_to_int",
    string_to_float: "elmc_string_to_float",
    string_is_empty: "elmc_string_is_empty",
    string_left: "elmc_string_left",
    string_starts_with: "elmc_string_starts_with",
    string_ends_with: "elmc_string_ends_with",
    string_join: "elmc_string_join",
    tuple_first: "elmc_tuple_first",
    tuple_second: "elmc_tuple_second",
    basics_floor: "elmc_basics_floor",
    basics_to_float: "elmc_basics_to_float",
    basics_sin: "elmc_basics_sin",
    basics_cos: "elmc_basics_cos",
    basics_round: "elmc_basics_round",
    new_float: "elmc_new_float",
    new_int: "elmc_new_int",
    new_order: "elmc_new_order",
    new_bool: "elmc_new_bool",
    string_length_boxed: "elmc_string_length",
    char_from_code: "elmc_char_from_code",
    new_string: "elmc_new_string",
    tuple2: "elmc_tuple2",
    tuple2_take: "elmc_tuple2_take",
    tuple2_ints: "elmc_tuple2_ints",
    maybe_just_own: "elmc_maybe_just_own",
    result_ok_own: "elmc_result_ok_own",
    result_err_own: "elmc_result_err_own",
    maybe_just_payload: "elmc_maybe_just_payload",
    maybe_nothing: "elmc_maybe_nothing",
    maybe_is_nothing: "elmc_maybe_is_nothing",
    record_get: "elmc_record_get",
    record_new: "elmc_record_new",
    record_new_take: "elmc_record_new_take",
    record_new_values_ints: "elmc_record_new_values_ints",
    record_update_cow_drop: "elmc_record_update_index_cow_drop",
    cmd0: "elmc_cmd0",
    cmd1: "elmc_cmd1",
    cmd1_string: "elmc_cmd1_string",
    cmd2: "elmc_cmd2",
    cmd3: "elmc_cmd3",
    cmd4: "elmc_cmd4",
    cmd_batch: "elmc_cmd_batch",
    sub_batch: "elmc_sub_batch",
    cmd_backlight_from_maybe: "elmc_cmd_backlight_from_maybe",
    release: "elmc_release",
    retain: "elmc_retain",
    int_zero: "elmc_int_zero",
    unit: "elmc_unit",
    union_tag_matches: "elmc_union_tag_matches",
    union_payload: "elmc_union_payload",
    debug_to_string: "elmc_debug_to_string",
    result_and_then: "elmc_result_and_then",
    result_map: "elmc_result_map",
    result_map_error: "elmc_result_map_error",
    maybe_and_then: "elmc_maybe_and_then"
  }, Extra.builtins())

  @fallible_extra MapSet.new(Extra.fallible_ids())
  @c_value_return_extra MapSet.new(Extra.c_value_return_ids())
  @value_return_extra MapSet.new(Extra.value_return_ids())
  @symbol_aliases Extra.symbol_aliases()

  @fallible MapSet.new([
    :list_append,
    :list_cons,
    :list_repeat,
    :list_range,
    :list_map,
    :list_all,
    :list_any,
    :list_filter,
    :list_filter_record_field,
    :list_filter_record_and,
    :list_map_record_field,
    :list_indexed_map,
    :list_concat,
    :list_slice_int,
    :list_take,
    :list_drop,
    :list_concat_map,
    :list_filter_map,
    :list_foldl,
    :list_sort_by,
    :list_sort_with,
    :list_reverse,
    :int_list_head_boxed,
    :int_list_tail,
    :list_is_empty,
    :list_nth_maybe,
    :maybe_with_default,
    :maybe_map,
    :basics_min,
    :basics_max,
    :basics_mod_by,
    :basics_remainder_by,
    :basics_not,
    :basics_clamp,
    :string_append,
    :string_from_int,
    :string_to_float,
    :string_left,
    :string_join,
    :basics_floor,
    :basics_to_float,
    :basics_sin,
    :basics_cos,
    :basics_round,
    :new_float,
    :new_int,
    :new_order,
    :new_bool,
    :new_string,
    :string_length_boxed,
    :tuple2,
    :tuple2_take,
    :tuple2_ints,
    :maybe_just_own,
    :result_ok_own,
    :result_err_own,
    :record_new,
    :record_new_take,
    :record_new_values_ints,
    :record_update_cow_drop,
    :cmd0,
    :cmd1,
    :cmd1_string,
    :cmd2,
    :cmd3,
    :cmd4,
    :cmd_backlight_from_maybe,
    :result_and_then,
    :result_map,
    :result_map_error,
    :maybe_and_then
  ])

  # Runtime calls that return `ElmcValue *` (not `RC` + out-pointer). May return NULL on OOM.
  @c_value_return MapSet.new([
    :basics_min,
    :basics_max,
    :basics_mod_by,
    :basics_remainder_by,
    :basics_not,
    :basics_clamp,
    :basics_floor,
    :basics_to_float,
    :basics_sin,
    :basics_cos,
    :basics_round,
    :list_length,
    :list_nth_maybe,
    :string_to_int,
    :list_nth_int_default,
    :debug_to_string,
    :char_from_code,
    :cmd_backlight_from_maybe
  ])

  @value_return MapSet.new([
    :retain,
    :maybe_just_payload,
    :union_payload,
    :maybe_with_default,
    :maybe_nothing,
    :int_zero,
    :list_head,
    :list_tail,
    :list_is_empty,
    :string_is_empty,
    :string_starts_with,
    :string_ends_with,
    :tuple_first,
    :tuple_second,
    :cmd_batch,
    :sub_batch,
    :record_get,
    :record_update_cow_drop,
    :unit
  ])

  # Value-returning runtime calls that never fail with NULL from allocation.
  # (elmc_retain returns NULL only when the input is NULL; record/tuple getters use
  # elmc_int_zero / retain; cow_drop falls back to elmc_retain(record).)
  @direct_value_return MapSet.new([
    :retain,
    :maybe_just_payload,
    :union_payload,
    :maybe_with_default,
    :maybe_nothing,
    :int_zero,
    :list_nil,
    :list_head,
    :list_tail,
    :cmd_batch,
    :sub_batch,
    :record_get,
    :record_update_cow_drop,
    :tuple_first,
    :tuple_second,
    :basics_min,
    :basics_max,
    :unit
  ])

  @builtin_order [
    :list_append,
    :list_cons,
    :list_nil,
    :list_repeat,
    :list_range,
    :list_map,
    :list_all,
    :list_any,
    :list_filter,
    :list_filter_record_field,
    :list_filter_record_and,
    :list_map_record_field,
    :list_indexed_map,
    :list_length,
    :list_concat,
    :list_slice_int,
    :list_take,
    :list_drop,
    :list_concat_map,
    :list_filter_map,
    :list_foldl,
    :list_sort_by,
    :list_sort_with,
    :list_reverse,
    :list_head,
    :list_tail,
    :int_list_head_int,
    :int_list_head_boxed,
    :int_list_tail,
    :list_is_empty,
    :list_nth_maybe,
    :list_nth_int_default,
    :maybe_with_default,
    :maybe_map,
    :basics_min,
    :basics_max,
    :basics_mod_by,
    :basics_remainder_by,
    :basics_not,
    :basics_clamp,
    :string_append,
    :string_from_int,
    :string_to_int,
    :string_to_float,
    :string_left,
    :string_join,
    :basics_floor,
    :basics_to_float,
    :basics_sin,
    :basics_cos,
    :basics_round,
    :new_float,
    :new_int,
    :new_bool,
    :new_string,
    :tuple2,
    :tuple2_take,
    :tuple2_ints,
    :maybe_just_own,
    :result_ok_own,
    :result_err_own,
    :maybe_just_payload,
    :maybe_nothing,
    :maybe_is_nothing,
    :record_get,
    :record_new,
    :record_new_take,
    :record_new_values_ints,
    :record_update_cow_drop,
    :cmd0,
    :cmd1,
    :cmd1_string,
    :cmd2,
    :cmd3,
    :cmd4,
    :cmd_batch,
    :sub_batch,
    :cmd_backlight_from_maybe,
    :release,
    :retain,
    :int_zero,
    :union_tag_matches,
    :union_payload,
    :debug_to_string,
    :result_and_then,
    :maybe_and_then
  ]

  @spec ids() :: [atom()]
  def ids do
    known = MapSet.new(@builtin_order)
    extra = Map.keys(@builtins) |> Enum.reject(&MapSet.member?(known, &1)) |> Enum.sort()
    @builtin_order ++ extra
  end

  @spec c_symbol(atom()) :: String.t() | nil
  def c_symbol(id) when is_atom(id), do: Map.get(@builtins, id)

  @spec fallible?(atom()) :: boolean()
  def fallible?(id),
    do: MapSet.member?(@fallible, id) or MapSet.member?(@fallible_extra, id)

  @spec value_return?(atom()) :: boolean()
  def value_return?(id),
    do: MapSet.member?(@value_return, id) or MapSet.member?(@value_return_extra, id)

  @spec direct_value_return?(atom()) :: boolean()
  def direct_value_return?(id), do: MapSet.member?(@direct_value_return, id)

  @spec c_value_return?(atom()) :: boolean()
  def c_value_return?(id),
    do: MapSet.member?(@c_value_return, id) or MapSet.member?(@c_value_return_extra, id)

  @spec native_int_arg?(atom(), non_neg_integer()) :: boolean()
  def native_int_arg?(id, index) when is_atom(id) and is_integer(index) do
    index in Map.get(@native_int_arg_indices, id, [])
  end

  @ownership_transfer MapSet.new([
    :maybe_just_own,
    :result_ok_own,
    :result_err_own
  ])

  @spec ownership_transfer_arg?(atom(), non_neg_integer()) :: boolean()
  def ownership_transfer_arg?(id, index)
      when is_atom(id) and is_integer(index) and index == 0 do
    MapSet.member?(@ownership_transfer, id)
  end

  def ownership_transfer_arg?(_, _), do: false

  @spec ownership_transfer?(atom()) :: boolean()
  def ownership_transfer?(id), do: MapSet.member?(@ownership_transfer, id)

  @spec from_c_symbol(String.t()) :: atom() | nil
  def from_c_symbol(sym) when is_binary(sym) do
    Map.get(@symbol_aliases, sym) ||
      Enum.find_value(@builtins, fn {id, s} -> if s == sym, do: id end)
  end
end
