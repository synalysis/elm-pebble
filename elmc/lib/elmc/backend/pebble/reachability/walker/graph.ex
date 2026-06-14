defmodule Elmc.Backend.Pebble.Reachability.Walker.Graph do
  @moduledoc false

  alias Elmc.Backend.Pebble.{Reachability.Collector, Types}

  @type queue :: [Types.call_target()]

  @spec traverse(
          Types.reachability_function_map(),
          Types.call_target_set(),
          queue(),
          Types.call_target_set()
        ) :: Types.call_target_set()
  def traverse(_function_map, _seen, [], targets), do: targets

  def traverse(function_map, seen, [current | rest], targets) do
    {module_name, expr} = Map.fetch!(function_map, current)

    {calls, targets} =
      expr
      |> Collector.collect()
      |> Enum.reduce({[], targets}, fn target, {calls, targets} ->
        targets = MapSet.put(targets, target)

        case Map.fetch(function_map, target) do
          {:ok, _decl} ->
            if MapSet.member?(seen, target) do
              {calls, targets}
            else
              {[target | calls], targets}
            end

          :error ->
            local_target = "#{module_name}.#{target}"

            if Map.has_key?(function_map, local_target) and not MapSet.member?(seen, local_target) do
              {[local_target | calls], targets}
            else
              {calls, targets}
            end
        end
      end)

    seen = Enum.reduce(calls, seen, &MapSet.put(&2, &1))
    traverse(function_map, seen, rest ++ Enum.reverse(calls), targets)
  end
end
