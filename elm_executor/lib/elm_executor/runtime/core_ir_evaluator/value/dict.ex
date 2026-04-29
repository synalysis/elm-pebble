defmodule ElmExecutor.Runtime.CoreIREvaluator.Value.Dict do
  @moduledoc false

  @spec dict_pair_list?(term()) :: boolean()
  def dict_pair_list?(xs) when is_list(xs), do: Enum.all?(xs, &(pair_to_tuple(&1) != :error))

  @spec dict_from_pair_list(term()) :: term()
  def dict_from_pair_list(xs) do
    xs
    |> Enum.map(&pair_to_tuple/1)
    |> Enum.reduce(%{}, fn {k, v}, acc -> Map.put(acc, k, v) end)
  end

  @spec dict_to_list(term()) :: term()
  def dict_to_list(dict) when is_map(dict), do: dict_sorted_pairs(dict)

  @spec dict_keys(term()) :: list()
  def dict_keys(dict) when is_map(dict),
    do: dict_sorted_pairs(dict) |> Enum.map(fn {k, _} -> k end)

  @spec dict_values(term()) :: list()
  def dict_values(dict) when is_map(dict),
    do: dict_sorted_pairs(dict) |> Enum.map(fn {_, v} -> v end)

  @spec pair_to_tuple(term()) :: term()
  defp pair_to_tuple({k, v}), do: {k, v}
  defp pair_to_tuple([k, v]), do: {k, v}

  defp pair_to_tuple(%{"ctor" => ctor, "args" => [k, v]}) when is_binary(ctor) do
    if short_ctor_name(ctor) in ["Tuple2", "_Tuple2"], do: {k, v}, else: :error
  end

  defp pair_to_tuple(%{ctor: ctor, args: [k, v]}) when is_binary(ctor) do
    if short_ctor_name(ctor) in ["Tuple2", "_Tuple2"], do: {k, v}, else: :error
  end

  defp pair_to_tuple(_), do: :error

  @spec dict_sorted_pairs(term()) :: [{term(), term()}]
  defp dict_sorted_pairs(dict) when is_map(dict), do: dict |> Map.to_list() |> Enum.sort()

  @spec short_ctor_name(term()) :: String.t()
  defp short_ctor_name(target) when is_binary(target) do
    target
    |> String.split(".")
    |> List.last()
    |> to_string()
  end
end
