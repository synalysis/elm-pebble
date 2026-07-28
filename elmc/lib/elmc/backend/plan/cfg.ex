defmodule Elmc.Backend.Plan.Cfg do
  @moduledoc false

  alias Elmc.Backend.Plan.Types.Block

  @type block_id :: non_neg_integer()

  @spec successors(Block.terminator()) :: [block_id()]
  def successors({:br, target_id}) when is_integer(target_id), do: [target_id]

  def successors({:br_if, then_id, else_id, _}) when is_integer(then_id) and is_integer(else_id),
    do: [then_id, else_id]

  def successors({:switch_tag, _, arms, default_id}) when is_integer(default_id) do
    arm_ids =
      Enum.map(arms, fn
        {_, id} when is_integer(id) -> id
        {_, id, _} when is_integer(id) -> id
        _ -> nil
      end)

    (arm_ids ++ [default_id]) |> Enum.reject(&is_nil/1)
  end

  def successors(_), do: []

  @spec block_map([Block.t()]) :: %{block_id() => Block.t()}
  def block_map(blocks) when is_list(blocks), do: Map.new(blocks, &{&1.id, &1})

  @spec reachable_ids([Block.t()], block_id()) :: MapSet.t(block_id())
  def reachable_ids(blocks, entry_id) when is_list(blocks) and is_integer(entry_id) do
    by_id = block_map(blocks)
    do_reachable(by_id, entry_id, MapSet.new())
  end

  defp do_reachable(_by_id, nil, visited), do: visited

  defp do_reachable(by_id, id, visited) do
    if MapSet.member?(visited, id) do
      visited
    else
      case Map.get(by_id, id) do
        %Block{terminator: term} ->
          visited = MapSet.put(visited, id)

          Enum.reduce(successors(term), visited, fn succ_id, acc ->
            do_reachable(by_id, succ_id, acc)
          end)

        _ ->
          visited
      end
    end
  end

  @spec dangling_targets([Block.t()]) :: [{block_id(), block_id()}]
  def dangling_targets(blocks) when is_list(blocks) do
    by_id = block_map(blocks)
    block_ids = MapSet.new(Map.keys(by_id))

    blocks
    |> Enum.flat_map(fn %Block{id: from_id, terminator: term} ->
      successors(term)
      |> Enum.reject(&MapSet.member?(block_ids, &1))
      |> Enum.map(fn missing -> {from_id, missing} end)
    end)
  end

  @spec permanent_none_blocks([Block.t()]) :: [block_id()]
  def permanent_none_blocks(blocks) when is_list(blocks) do
    blocks
    |> Enum.filter(&match?(%Block{terminator: :none}, &1))
    |> Enum.map(& &1.id)
  end

  @spec unreachable_block_ids([Block.t()], block_id()) :: [block_id()]
  def unreachable_block_ids(blocks, entry_id) when is_list(blocks) and is_integer(entry_id) do
    reachable = reachable_ids(blocks, entry_id)

    blocks
    |> Enum.map(& &1.id)
    |> Enum.reject(&MapSet.member?(reachable, &1))
  end
end
