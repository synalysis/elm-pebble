defmodule Elmc.Backend.Wasm.FunctionOrder do
  @moduledoc false

  alias Elmc.Backend.Plan.Types.FunctionPlan

  @spec sort([FunctionPlan.t()]) :: [FunctionPlan.t()]
  def sort(plans) when is_list(plans) do
    graph =
      Map.new(plans, fn %FunctionPlan{module: mod, name: name} = plan ->
        {{mod, name}, deps(plan)}
      end)

    sorted_keys = topo_sort(Map.keys(graph), graph)

    by_key = Map.new(plans, fn %FunctionPlan{module: mod, name: name} = plan ->
      {{mod, name}, plan}
    end)

    Enum.map(sorted_keys, &Map.fetch!(by_key, &1))
  end

  defp deps(%FunctionPlan{} = plan) do
    blocks = plan.blocks ++ Enum.flat_map(Map.get(plan, :lambdas) || [], & &1.blocks)

    blocks
    |> Enum.flat_map(& &1.instrs)
    |> Enum.flat_map(fn
      %{op: :call_fn, args: %{module: mod, name: name}} -> [{mod, name}]
      _ -> []
    end)
    |> Enum.uniq()
  end

  defp topo_sort(keys, graph) do
    {sorted, _} =
      Enum.reduce(keys, {[], MapSet.new()}, fn key, {acc, visited} ->
        visit(key, graph, visited, MapSet.new(), acc)
      end)

    sorted
  end

  defp visit(key, graph, visited, stack, acc) do
    cond do
      not Map.has_key?(graph, key) ->
        {acc, visited}

      MapSet.member?(visited, key) ->
        {acc, visited}

      MapSet.member?(stack, key) ->
        {acc, visited}

      true ->
        stack = MapSet.put(stack, key)

        {acc, visited} =
          (Map.get(graph, key, []) || [])
          |> Enum.filter(&Map.has_key?(graph, &1))
          |> Enum.reduce({acc, visited}, fn dep, {a, v} ->
            visit(dep, graph, v, stack, a)
          end)

        visited = MapSet.put(visited, key)
        {acc ++ [key], visited}
    end
  end
end
