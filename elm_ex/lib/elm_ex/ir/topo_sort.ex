defmodule ElmEx.IR.TopoSort do
  @moduledoc """
  Topological sort of IR modules based on import dependencies.
  Ensures modules are compiled in dependency order.
  """

  alias ElmEx.IR

  @spec sort_modules(IR.t()) :: {:ok, [ElmEx.IR.Module.t()]} | {:error, {:cycle, [String.t()]}}
  def sort_modules(%IR{} = ir) do
    module_map = Map.new(ir.modules, fn mod -> {mod.name, mod} end)
    module_names = Enum.map(ir.modules, & &1.name)

    # Build adjacency: module -> modules it depends on (imports)
    deps =
      ir.modules
      |> Map.new(fn mod ->
        dep_names =
          (mod.imports || [])
          |> Enum.filter(&Map.has_key?(module_map, &1))

        {mod.name, dep_names}
      end)

    case topo_sort(module_names, deps) do
      {:ok, sorted_names} ->
        sorted_modules =
          sorted_names
          |> Enum.map(&Map.get(module_map, &1))
          |> Enum.reject(&is_nil/1)

        {:ok, sorted_modules}

      {:error, _} = error ->
        error
    end
  end

  @spec topo_sort([String.t()], map()) :: {:ok, [String.t()]} | {:error, {:cycle, [String.t()]}}
  defp topo_sort(nodes, deps) do
    # Kahn's algorithm
    in_degree =
      nodes
      |> Map.new(fn node -> {node, 0} end)

    in_degree =
      Enum.reduce(nodes, in_degree, fn node, acc ->
        Enum.reduce(Map.get(deps, node, []), acc, fn _dep, inner_acc ->
          # dep is depended ON, so doesn't change in_degree
          # node depends on dep, but we want: dep must come before node
          # Actually in_degree of node increases for each dep
          inner_acc
        end)
      end)

    # Count incoming edges: for each edge (dep -> node), increment node's in_degree
    in_degree =
      Enum.reduce(nodes, in_degree, fn node, acc ->
        node_deps = Map.get(deps, node, [])

        Enum.reduce(node_deps, acc, fn _dep, inner ->
          Map.update(inner, node, 1, &(&1 + 1))
        end)
      end)

    # Start with nodes that have no dependencies
    queue =
      in_degree
      |> Enum.filter(fn {_node, degree} -> degree == 0 end)
      |> Enum.map(fn {node, _} -> node end)
      |> Enum.sort()

    # Build reverse adjacency: dep -> nodes that depend on it
    reverse_deps =
      Enum.reduce(nodes, %{}, fn node, acc ->
        Enum.reduce(Map.get(deps, node, []), acc, fn dep, inner ->
          Map.update(inner, dep, [node], &[node | &1])
        end)
      end)

    do_topo_sort(queue, in_degree, reverse_deps, [])
  end

  @spec do_topo_sort([String.t()], map(), map(), [String.t()]) ::
          {:ok, [String.t()]} | {:error, {:cycle, [String.t()]}}
  defp do_topo_sort([], in_degree, _reverse_deps, result) do
    remaining =
      in_degree
      |> Enum.filter(fn {_node, degree} -> degree > 0 end)
      |> Enum.map(fn {node, _} -> node end)

    if remaining == [] do
      {:ok, Enum.reverse(result)}
    else
      {:error, {:cycle, remaining}}
    end
  end

  defp do_topo_sort([current | rest], in_degree, reverse_deps, result) do
    dependents = Map.get(reverse_deps, current, [])

    {updated_in_degree, new_zero} =
      Enum.reduce(dependents, {in_degree, []}, fn dep, {deg_map, zeros} ->
        new_deg = Map.get(deg_map, dep, 0) - 1
        updated = Map.put(deg_map, dep, new_deg)

        if new_deg == 0 do
          {updated, [dep | zeros]}
        else
          {updated, zeros}
        end
      end)

    updated_in_degree = Map.put(updated_in_degree, current, -1)
    new_queue = Enum.sort(new_zero) ++ rest

    do_topo_sort(new_queue, updated_in_degree, reverse_deps, [current | result])
  end
end
