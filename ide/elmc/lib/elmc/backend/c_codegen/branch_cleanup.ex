defmodule Elmc.Backend.CCodegen.BranchCleanup do
  @moduledoc false
  alias Elmc.Backend.CCodegen.ValueSlots

  @cow_drop_decl ~r/ElmcValue \*([A-Za-z_][A-Za-z0-9_]*) = elmc_record_update_index_cow_drop(?:_take)?\(\s*([A-Za-z_][A-Za-z0-9_]*)\s*,/
  @cow_drop_reassign ~r/^([A-Za-z_][A-Za-z0-9_]*) = elmc_record_update_index_cow_drop(?:_take)?\(\s*([A-Za-z_][A-Za-z0-9_]*)\s*,/m
  @cow_drop_rc ~r/Rc = elmc_record_update_index_cow_drop\(\s*&([A-Za-z_][A-Za-z0-9_\[\]]*)\s*,\s*([A-Za-z_][A-Za-z0-9_\[\]]*)\s*,/
  @retain_in_place_bump ~r/ElmcValue \*([A-Za-z_][A-Za-z0-9_]*) = \(([A-Za-z_][A-Za-z0-9_]*) == ([A-Za-z_][A-Za-z0-9_]*)\) \? elmc_retain\(\2\) : \2;/

  @spec cow_drop_chain_sources_to_skip(String.t(), String.t()) :: MapSet.t(String.t())
  def cow_drop_chain_sources_to_skip(body, out)
      when is_binary(body) and body != "" and is_binary(out) do
    edges = cow_drop_edges(body)

    kept_results =
      edges
      |> Enum.map(fn {_source, result} -> result end)
      |> Enum.uniq()
      |> Enum.filter(&kept_binding?(&1, out))

    propagate_cow_drop_sources(edges, kept_results)
    |> MapSet.union(retain_in_place_cow_bump_sources_to_skip(body, out))
  end

  def cow_drop_chain_sources_to_skip(_body, _out), do: MapSet.new()

  @spec retain_in_place_cow_bump_sources_to_skip(String.t(), String.t()) :: MapSet.t(String.t())
  def retain_in_place_cow_bump_sources_to_skip(body, out)
      when is_binary(body) and body != "" and is_binary(out) do
    edges = cow_drop_edges(body)

    Regex.scan(@retain_in_place_bump, body)
    |> Enum.reduce(MapSet.new(), fn [_full, bump_result, aliased_result, _base], skip ->
      if kept_binding?(bump_result, out) do
        skip
        |> MapSet.put(aliased_result)
        |> MapSet.union(propagate_cow_drop_sources(edges, [aliased_result]))
      else
        skip
      end
    end)
  end

  def retain_in_place_cow_bump_sources_to_skip(_body, _out), do: MapSet.new()

  @spec assignment_rhs_to_out(String.t(), String.t()) :: MapSet.t(String.t())
  def assignment_rhs_to_out(body, out)
      when is_binary(body) and body != "" and is_binary(out) and out != "" do
    escaped_out = Regex.escape(out)

    ~r/(?:#{escaped_out}|\*out)\s*=\s*([A-Za-z_][A-Za-z0-9_]*)\s*;/
    |> Regex.scan(body)
    |> Enum.map(fn [_, rhs] -> rhs end)
    |> MapSet.new()
  end

  def assignment_rhs_to_out(_body, _out), do: MapSet.new()

  defp cow_drop_edges(body) do
    decl_edges =
      Regex.scan(@cow_drop_decl, body)
      |> Enum.map(fn [_, result, source] -> {source, result} end)

    reassign_edges =
      Regex.scan(@cow_drop_reassign, body)
      |> Enum.map(fn [_, result, source] -> {source, result} end)

    rc_edges =
      Regex.scan(@cow_drop_rc, body)
      |> Enum.map(fn [_, result, source] -> {source, result} end)

    decl_edges ++ reassign_edges ++ rc_edges
  end

  defp kept_binding?(name, out) do
    name == out or ValueSlots.transferred?(name)
  end

  defp propagate_cow_drop_sources(_edges, []), do: MapSet.new()

  defp propagate_cow_drop_sources(edges, kept_results) do
    sources_by_result =
      edges
      |> Enum.group_by(fn {_source, result} -> result end, fn {source, _result} -> source end)

    bfs_cow_drop_sources(sources_by_result, kept_results, MapSet.new())
  end

  defp bfs_cow_drop_sources(_sources_by_result, [], skip), do: skip

  defp bfs_cow_drop_sources(sources_by_result, [result | queue], skip) do
    sources = Map.get(sources_by_result, result, [])

    {new_skip, new_queue} =
      Enum.reduce(sources, {skip, queue}, fn source, {skip_acc, queue_acc} ->
        if MapSet.member?(skip_acc, source) do
          {skip_acc, queue_acc}
        else
          {MapSet.put(skip_acc, source), queue_acc ++ [source]}
        end
      end)

    bfs_cow_drop_sources(sources_by_result, new_queue, new_skip)
  end
end
