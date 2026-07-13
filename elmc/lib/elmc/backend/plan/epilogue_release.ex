defmodule Elmc.Backend.Plan.EpilogueRelease do
  @moduledoc false

  alias Elmc.Backend.Plan.Types
  alias Elmc.Backend.Plan.Types.{Block, FunctionPlan}

  @spec run(FunctionPlan.t()) :: FunctionPlan.t()
  def run(%FunctionPlan{blocks: []} = plan), do: plan

  def run(%FunctionPlan{blocks: blocks} = plan) do
    %{plan | blocks: Enum.map(blocks, &maybe_insert_releases/1)}
  end

  defp maybe_insert_releases(%Block{terminator: {:ret, _}} = block), do: insert_releases(block)
  defp maybe_insert_releases(block), do: block

  defp insert_releases(%Block{instrs: instrs, terminator: term} = block) do
    live = live_owned(instrs)
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

  defp renumber_releases(releases, instrs) do
    next_id =
      case List.last(instrs) do
        %{id: id} when is_integer(id) -> id + 1
        _ -> 0
      end

    Enum.with_index(releases, fn instr, i -> %{instr | id: next_id + i} end)
  end

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

  defp track_produces(owned, %Types{effects: %{produces: {:owned, _reg}}, dest: dest}) do
    case dest do
      r when is_integer(r) -> MapSet.put(owned, r)
      _ -> owned
    end
  end

  defp track_produces(owned, _), do: owned

  defp mark_consumed(owned, consumes) do
    Enum.reduce(consumes, owned, &MapSet.delete(&2, &1))
  end

  defp ret_reg({:ret, reg}) when is_integer(reg), do: reg
  defp ret_reg(_), do: nil
end
