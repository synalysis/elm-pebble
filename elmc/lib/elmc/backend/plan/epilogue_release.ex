defmodule Elmc.Backend.Plan.EpilogueRelease do
  @moduledoc false
  alias Elmc.Backend.Plan.Types, as: Types


  alias Elmc.Backend.Plan.Types
  alias Elmc.Backend.Plan.Types.{Block, FunctionPlan}

  @spec run(FunctionPlan.t()) :: FunctionPlan.t()
  def run(%FunctionPlan{blocks: []} = plan), do: plan

  def run(%FunctionPlan{blocks: blocks} = plan) do
    leftover = function_leftover_owned(plan)
    %{plan | blocks: Enum.map(blocks, &maybe_insert_releases(&1, leftover))}
  end

  @spec function_leftover_owned(FunctionPlan.t()) :: MapSet.t(Types.reg())
  defp function_leftover_owned(%FunctionPlan{blocks: blocks}) do
    {produced, consumed} =
      Enum.reduce(blocks, {MapSet.new(), MapSet.new()}, fn block, acc ->
        acc = Enum.reduce(block.instrs, acc, &track_function_instr/2)

        case block.terminator do
          {:ret, reg} when is_integer(reg) ->
            {elem(acc, 0), MapSet.put(elem(acc, 1), reg)}

          _ ->
            acc
        end
      end)

    MapSet.difference(produced, consumed)
  end

  defp track_function_instr(%Types{op: :release, args: %{reg: reg}}, {produced, consumed})
       when is_integer(reg) do
    {produced, MapSet.put(consumed, reg)}
  end

  defp track_function_instr(%Types{effects: effects}, {produced, consumed}) do
    produced =
      case effects do
        %{produces: {:owned, reg}} when is_integer(reg) -> MapSet.put(produced, reg)
        _ -> produced
      end

    consumed = Enum.reduce(effects.consumes || [], consumed, &MapSet.put(&2, &1))
    {produced, consumed}
  end

  @spec maybe_insert_releases(Block.t(), MapSet.t(Types.reg())) :: Block.t()
  defp maybe_insert_releases(%Block{terminator: {:ret, _}} = block, leftover),
    do: insert_releases(block, leftover)

  defp maybe_insert_releases(block, _leftover), do: block

  @spec insert_releases(Block.t(), MapSet.t(Types.reg())) :: Block.t()
  defp insert_releases(%Block{instrs: instrs, terminator: term} = block, leftover) do
    live = MapSet.union(live_owned(instrs), leftover)
    ret_reg = ret_reg(term)

    leaked =
      live
      |> MapSet.to_list()
      |> Enum.reject(&(&1 == ret_reg))
      |> Enum.sort()

    release_instrs =
      Enum.with_index(leaked, fn reg, _offset ->
        %Types{
          id: :epilogue_release,
          op: :release,
          dest: nil,
          args: %{reg: reg},
          effects: %{produces: nil, consumes: [reg], borrows: [], fallible: false},
          block_id: block.id,
          span: nil
        }
      end)

    %{block | instrs: instrs ++ renumber_releases(release_instrs, instrs)}
  end

  @spec renumber_releases([Types.t()], [Types.t()]) :: [Types.t()]
  defp renumber_releases(releases, instrs) do
    next_id =
      case List.last(instrs) do
        %{id: id} when is_integer(id) -> id + 1
        _ -> 0
      end

    Enum.with_index(releases, fn instr, i -> %{instr | id: next_id + i} end)
  end

  @spec live_owned([Types.t()]) :: MapSet.t(Types.reg())
  defp live_owned(instrs) do
    Enum.reduce(instrs, MapSet.new(), fn instr, owned ->
      case instr do
        %{op: :phi, dest: dest} when is_integer(dest) ->
          owned
          |> mark_consumed(instr.effects.consumes || [])
          |> then(fn _ -> MapSet.new([dest]) end)

        _ ->
          owned
          |> track_produces(instr)
          |> mark_consumed(instr.effects.consumes || [])
      end
    end)
  end

  @spec track_produces(MapSet.t(Types.reg()), term()) :: MapSet.t(Types.reg())
  defp track_produces(owned, %Types{effects: %{produces: {:owned, _reg}}, dest: dest}) do
    case dest do
      r when is_integer(r) -> MapSet.put(owned, r)
      _ -> owned
    end
  end

  defp track_produces(owned, _), do: owned

  @spec mark_consumed(MapSet.t(Types.reg()), [Types.reg()]) :: MapSet.t(Types.reg())
  defp mark_consumed(owned, consumes) do
    Enum.reduce(consumes, owned, &MapSet.delete(&2, &1))
  end

  @spec ret_reg(term()) :: Types.reg() | nil
  defp ret_reg({:ret, reg}) when is_integer(reg), do: reg
  defp ret_reg(_), do: nil
end
