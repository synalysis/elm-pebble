defmodule Elmc.Backend.CCodegen.SpecialValues.Stdlib.Array do
  @moduledoc false

  alias Elmc.Backend.CCodegen.Types

  @behaviour Elmc.Backend.CCodegen.SpecialValues.Handler

  @impl true
  @spec special_value_from_target(String.t(), Types.special_value_args()) ::
          Types.special_value_result()
  def special_value_from_target("Array.empty", []),
    do: %{op: :runtime_call, function: "elmc_array_empty", args: []}

  def special_value_from_target("Array.fromList", [items]),
    do: %{op: :runtime_call, function: "elmc_array_from_list", args: [items]}

  def special_value_from_target("Array.length", [array]),
    do: %{op: :runtime_call, function: "elmc_array_length", args: [array]}

  def special_value_from_target("Array.get", [index, array]),
    do: %{op: :runtime_call, function: "elmc_array_get", args: [index, array]}

  def special_value_from_target("Array.set", [index, value, array]),
    do: %{op: :runtime_call, function: "elmc_array_set", args: [index, value, array]}

  def special_value_from_target("Array.push", [value, array]),
    do: %{op: :runtime_call, function: "elmc_array_push", args: [value, array]}

  def special_value_from_target("Array.initialize", [n, f]),
    do: %{op: :runtime_call, function: "elmc_array_initialize", args: [n, f]}

  def special_value_from_target("Array.repeat", [n, value]),
    do: %{op: :runtime_call, function: "elmc_array_repeat", args: [n, value]}

  def special_value_from_target("Array.isEmpty", [array]),
    do: %{op: :runtime_call, function: "elmc_array_is_empty", args: [array]}

  def special_value_from_target("Array.toList", [array]),
    do: %{op: :runtime_call, function: "elmc_array_to_list", args: [array]}

  def special_value_from_target("Array.toIndexedList", [array]),
    do: %{op: :runtime_call, function: "elmc_array_to_indexed_list", args: [array]}

  def special_value_from_target("Array.map", [f, array]),
    do: %{op: :runtime_call, function: "elmc_array_map", args: [f, array]}

  def special_value_from_target("Array.indexedMap", [f, array]),
    do: %{op: :runtime_call, function: "elmc_array_indexed_map", args: [f, array]}

  def special_value_from_target("Array.foldl", [f, acc, array]),
    do: %{op: :runtime_call, function: "elmc_array_foldl", args: [f, acc, array]}

  def special_value_from_target("Array.foldr", [f, acc, array]),
    do: %{op: :runtime_call, function: "elmc_array_foldr", args: [f, acc, array]}

  def special_value_from_target("Array.filter", [f, array]),
    do: %{op: :runtime_call, function: "elmc_array_filter", args: [f, array]}

  def special_value_from_target("Array.append", [a, b]),
    do: %{op: :runtime_call, function: "elmc_array_append", args: [a, b]}

  def special_value_from_target("Array.slice", [start, end_idx, array]),
    do: %{op: :runtime_call, function: "elmc_array_slice", args: [start, end_idx, array]}


  @impl true

  def special_value_from_target(_target, _args), do: nil
end
