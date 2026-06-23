defmodule Elmc.Backend.CCodegen.SpecialValues.Stdlib.Set do
  @moduledoc false

  alias Elmc.Backend.CCodegen.SpecialValues.Helpers
  alias Elmc.Backend.CCodegen.Types

  @behaviour Elmc.Backend.CCodegen.SpecialValues.Handler

  @impl true
  @spec special_value_from_target(String.t(), Types.special_value_args()) ::
          Types.special_value_result()
  def special_value_from_target("Set.empty", []), do: %{op: :list_literal, items: []}

  def special_value_from_target("Set.fromList", [items]),
    do: %{op: :runtime_call, function: "elmc_set_from_list", args: [items]}

  def special_value_from_target("Set.insert", [value, set]),
    do: %{op: :runtime_call, function: "elmc_set_insert", args: [value, set]}

  def special_value_from_target("Set.insert", []),
    do: Helpers.runtime_fn_lambda("elmc_set_insert", ["__value", "__set"])

  def special_value_from_target("Set.member", [value, set]),
    do: %{op: :runtime_call, function: "elmc_set_member", args: [value, set]}

  def special_value_from_target("Set.size", [set]),
    do: %{op: :runtime_call, function: "elmc_set_size", args: [set]}

  def special_value_from_target("Set.singleton", [value]),
    do: %{op: :runtime_call, function: "elmc_set_singleton", args: [value]}

  def special_value_from_target("Set.remove", [value, set]),
    do: %{op: :runtime_call, function: "elmc_set_remove", args: [value, set]}

  def special_value_from_target("Set.remove", []),
    do: Helpers.runtime_fn_lambda("elmc_set_remove", ["__value", "__set"])

  def special_value_from_target("Set.isEmpty", [set]),
    do: %{op: :runtime_call, function: "elmc_set_is_empty", args: [set]}

  def special_value_from_target("Set.toList", [set]),
    do: %{op: :runtime_call, function: "elmc_set_to_list", args: [set]}

  def special_value_from_target("Set.union", [a, b]),
    do: %{op: :runtime_call, function: "elmc_set_union", args: [a, b]}

  def special_value_from_target("Set.intersect", [a, b]),
    do: %{op: :runtime_call, function: "elmc_set_intersect", args: [a, b]}

  def special_value_from_target("Set.diff", [a, b]),
    do: %{op: :runtime_call, function: "elmc_set_diff", args: [a, b]}

  def special_value_from_target("Set.map", [f, set]),
    do: %{op: :runtime_call, function: "elmc_set_map", args: [f, set]}

  def special_value_from_target("Set.foldl", [f, acc, set]),
    do: %{op: :runtime_call, function: "elmc_set_foldl", args: [f, acc, set]}

  def special_value_from_target("Set.foldr", [f, acc, set]),
    do: %{op: :runtime_call, function: "elmc_set_foldr", args: [f, acc, set]}

  def special_value_from_target("Set.filter", [f, set]),
    do: %{op: :runtime_call, function: "elmc_set_filter", args: [f, set]}

  def special_value_from_target("Set.partition", [f, set]),
    do: %{op: :runtime_call, function: "elmc_set_partition", args: [f, set]}


  def special_value_from_target(_target, _args), do: nil
end
