defmodule Elmc.Backend.CCodegen.ValueSlots do
  @moduledoc false

  @owned_tmp ~r/^(tmp_\d+|head_\d+|call_args_\d+|list_items_\d+|rec_values_\d+|list_map_item_\d+|list_map_cons_\d+|list_map_rev_\d+|list_fwd_cell_\d+|list_repeat_cons_\d+)$/

  @spec reset() :: :ok
  def reset do
    Process.put(:elmc_value_slots, MapSet.new())
    :ok
  end

  @spec track(String.t()) :: :ok
  def track(var) when is_binary(var) do
    if Regex.match?(@owned_tmp, var) do
      slots = Process.get(:elmc_value_slots, MapSet.new())
      Process.put(:elmc_value_slots, MapSet.put(slots, var))
    end

    :ok
  end

  @spec untrack(String.t()) :: :ok
  def untrack(var) when is_binary(var) do
    slots = Process.get(:elmc_value_slots, MapSet.new())
    Process.put(:elmc_value_slots, MapSet.delete(slots, var))
    :ok
  end

  @spec owned_vars() :: [String.t()]
  def owned_vars do
    Process.get(:elmc_value_slots, MapSet.new())
    |> MapSet.to_list()
    |> Enum.sort_by(&slot_sort_key/1)
  end

  @spec owned_declarations() :: String.t()
  def owned_declarations do
    owned_declarations_for_vars(owned_vars())
  end

  @spec failure_cleanup() :: String.t()
  def failure_cleanup do
    failure_cleanup_for_vars(owned_vars())
  end

  @spec owned_declarations_for_body(String.t()) :: String.t()
  def owned_declarations_for_body(body) when is_binary(body) do
    owned_vars()
    |> Enum.reject(&declared_in_body?(&1, body))
    |> owned_declarations_for_vars()
  end

  @spec failure_cleanup_for_body(String.t()) :: String.t()
  def failure_cleanup_for_body(body) when is_binary(body) do
    owned_vars()
    |> Enum.reject(&declared_in_body?(&1, body))
    |> failure_cleanup_for_vars()
  end

  defp owned_declarations_for_vars(vars) do
    vars
    |> Enum.map_join("\n", fn var -> "ElmcValue *#{var} = NULL;" end)
  end

  defp failure_cleanup_for_vars(vars) do
    vars
    |> Enum.map_join("\n", fn var ->
      "if (#{var}) { elmc_release(#{var}); }"
    end)
  end

  defp declared_in_body?(var, body) do
    Regex.match?(~r/ElmcValue \*#{Regex.escape(var)}\b/, body)
  end

  defp slot_sort_key(var) do
    case Regex.run(~r/(\d+)$/, var) do
      [_, digits] -> String.to_integer(digits)
      _ -> 0
    end
  end
end
