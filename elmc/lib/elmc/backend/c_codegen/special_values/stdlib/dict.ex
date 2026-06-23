defmodule Elmc.Backend.CCodegen.SpecialValues.Stdlib.Dict do
  @moduledoc false

  alias Elmc.Backend.CCodegen.Types

  @behaviour Elmc.Backend.CCodegen.SpecialValues.Handler

  @impl true
  @spec special_value_from_target(String.t(), Types.special_value_args()) ::
          Types.special_value_result()
  def special_value_from_target("Dict.empty", []), do: %{op: :list_literal, items: []}

  def special_value_from_target("Dict.fromList", [items]),
    do: %{op: :runtime_call, function: "elmc_dict_from_list", args: [items]}

  def special_value_from_target("Dict.insert", [key, value, dict]),
    do: %{op: :runtime_call, function: "elmc_dict_insert", args: [key, value, dict]}

  def special_value_from_target("Dict.get", [key, dict]),
    do: %{op: :runtime_call, function: "elmc_dict_get", args: [key, dict]}

  def special_value_from_target("Dict.member", [key, dict]),
    do: %{op: :runtime_call, function: "elmc_dict_member", args: [key, dict]}

  def special_value_from_target("Dict.size", [dict]),
    do: %{op: :runtime_call, function: "elmc_dict_size", args: [dict]}

  def special_value_from_target("Dict.remove", [key, dict]),
    do: %{op: :runtime_call, function: "elmc_dict_remove", args: [key, dict]}

  def special_value_from_target("Dict.isEmpty", [dict]),
    do: %{op: :runtime_call, function: "elmc_dict_is_empty", args: [dict]}

  def special_value_from_target("Dict.keys", [dict]),
    do: %{op: :runtime_call, function: "elmc_dict_keys", args: [dict]}

  def special_value_from_target("Dict.values", [dict]),
    do: %{op: :runtime_call, function: "elmc_dict_values", args: [dict]}

  def special_value_from_target("Dict.toList", [dict]),
    do: %{op: :runtime_call, function: "elmc_dict_to_list", args: [dict]}

  def special_value_from_target("Dict.map", [f, dict]),
    do: %{op: :runtime_call, function: "elmc_dict_map", args: [f, dict]}

  def special_value_from_target("Dict.foldl", [f, acc, dict]),
    do: %{op: :runtime_call, function: "elmc_dict_foldl", args: [f, acc, dict]}

  def special_value_from_target("Dict.foldr", [f, acc, dict]),
    do: %{op: :runtime_call, function: "elmc_dict_foldr", args: [f, acc, dict]}

  def special_value_from_target("Dict.filter", [f, dict]),
    do: %{op: :runtime_call, function: "elmc_dict_filter", args: [f, dict]}

  def special_value_from_target("Dict.partition", [f, dict]),
    do: %{op: :runtime_call, function: "elmc_dict_partition", args: [f, dict]}

  def special_value_from_target("Dict.union", [a, b]),
    do: %{op: :runtime_call, function: "elmc_dict_union", args: [a, b]}

  def special_value_from_target("Dict.intersect", [a, b]),
    do: %{op: :runtime_call, function: "elmc_dict_intersect", args: [a, b]}

  def special_value_from_target("Dict.diff", [a, b]),
    do: %{op: :runtime_call, function: "elmc_dict_diff", args: [a, b]}

  def special_value_from_target("Dict.merge", [left_fn, both_fn, right_fn, a, b, result]),
    do: %{
      op: :runtime_call,
      function: "elmc_dict_merge",
      args: [left_fn, both_fn, right_fn, a, b, result]
    }

  def special_value_from_target("Dict.merge", [left_fn, both_fn, right_fn, a, b]),
    do: %{
      op: :runtime_call,
      function: "elmc_dict_merge",
      args: [left_fn, both_fn, right_fn, a, b, %{op: :list_literal, items: []}]
    }

  def special_value_from_target("Dict.update", [key, f, dict]),
    do: %{op: :runtime_call, function: "elmc_dict_update", args: [key, f, dict]}

  def special_value_from_target("Dict.singleton", [key, value]),
    do: %{op: :runtime_call, function: "elmc_dict_singleton", args: [key, value]}


  def special_value_from_target(_target, _args), do: nil
end
