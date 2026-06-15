defmodule Elmx.Runtime.Core.Collections do
  @moduledoc false

  alias Elmx.Runtime.Core.Collections.{Array, Dict, Set}
  alias Elmx.Types

  @type dict :: Types.elm_dict()
  @type set :: Types.elm_set()
  @type array :: Types.elm_array()

  defdelegate dict_from_list(pairs), to: Dict
  defdelegate dict_insert(key, value, dict), to: Dict
  defdelegate dict_get(key, dict), to: Dict
  defdelegate dict_get_with_default_int(default, key, dict), to: Dict
  defdelegate dict_member(key, dict), to: Dict
  defdelegate dict_size(dict), to: Dict
  defdelegate dict_remove(key, dict), to: Dict
  defdelegate dict_is_empty(dict), to: Dict
  defdelegate dict_singleton(key, value), to: Dict
  defdelegate dict_keys(dict), to: Dict
  defdelegate dict_values(dict), to: Dict
  defdelegate dict_to_list(dict), to: Dict
  defdelegate dict_map(fun, dict), to: Dict
  defdelegate dict_foldl(fun, acc, dict), to: Dict
  defdelegate dict_foldr(fun, acc, dict), to: Dict
  defdelegate dict_filter(fun, dict), to: Dict
  defdelegate dict_partition(fun, dict), to: Dict
  defdelegate dict_union(left, right), to: Dict
  defdelegate dict_intersect(left, right), to: Dict
  defdelegate dict_diff(left, right), to: Dict
  defdelegate dict_merge(left_step, both_step, right_step, left, right, result), to: Dict
  defdelegate dict_merge(left_step, both_step, right_step, left, right), to: Dict
  defdelegate dict_update(key, alter, dict), to: Dict
  defdelegate set_from_list(items), to: Set
  defdelegate set_insert(value, set), to: Set
  defdelegate set_member(value, set), to: Set
  defdelegate set_size(set), to: Set
  defdelegate set_remove(value, set), to: Set
  defdelegate set_is_empty(set), to: Set
  defdelegate set_singleton(value), to: Set
  defdelegate set_to_list(set), to: Set
  defdelegate set_union(left, right), to: Set
  defdelegate set_intersect(left, right), to: Set
  defdelegate set_diff(left, right), to: Set
  defdelegate set_map(fun, set), to: Set
  defdelegate set_foldl(fun, acc, set), to: Set
  defdelegate set_foldr(fun, acc, set), to: Set
  defdelegate set_filter(fun, set), to: Set
  defdelegate set_partition(fun, set), to: Set
  defdelegate array_from_list(items), to: Array
  defdelegate array_length(array), to: Array
  defdelegate array_get(index, array), to: Array
  defdelegate array_get_with_default_int(default, index, array), to: Array
  defdelegate array_set(index, value, array), to: Array
  defdelegate array_push(value, array), to: Array
  defdelegate array_repeat(n, value), to: Array
  defdelegate array_initialize(n, value), to: Array
  defdelegate array_is_empty(array), to: Array
  defdelegate array_to_list(array), to: Array
  defdelegate array_to_indexed_list(array), to: Array
  defdelegate array_map(fun, array), to: Array
  defdelegate array_indexed_map(fun, array), to: Array
  defdelegate array_foldl(fun, acc, array), to: Array
  defdelegate array_foldr(fun, acc, array), to: Array
  defdelegate array_filter(fun, array), to: Array
  defdelegate array_append(left, right), to: Array
  defdelegate array_slice(start, length, array), to: Array
end
