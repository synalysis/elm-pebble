defmodule Elmc.Backend.Plan.EpilogueRelease do
  @moduledoc false
  alias Elmc.Backend.Plan.Types, as: Types

  alias Elmc.Backend.Plan.Cfg
  alias Elmc.Backend.Plan.Types
  alias Elmc.Backend.Plan.Types.{Block, FunctionPlan}

  @spec run(FunctionPlan.t()) :: FunctionPlan.t()
  def run(%FunctionPlan{blocks: []} = plan), do: plan

  def run(%FunctionPlan{blocks: blocks} = plan) do
    leftover = function_leftover_owned(plan)
    partial = partially_consumed_owned(plan)
    live_out = liveness_out(blocks)
    owned_exit = owned_exits(plan)

    %{
      plan
      | blocks:
          Enum.map(blocks, fn
            %Block{terminator: {:ret, _}} = block ->
              insert_releases(block, leftover)

            %Block{terminator: {:br, _}, id: id} = block ->
              keep = Map.get(live_out, id, MapSet.new())

              dead =
                partial
                |> MapSet.intersection(Map.get(owned_exit, id, MapSet.new()))
                |> MapSet.difference(keep)
                |> MapSet.to_list()
                |> Enum.sort()

              insert_release_regs(block, dead)

            block ->
              block
          end)
    }
  end

  @spec function_leftover_owned(FunctionPlan.t()) :: MapSet.t(Types.reg())
  defp function_leftover_owned(%FunctionPlan{blocks: blocks}) do
    {produced, consumed} = track_produced_consumed(blocks)

    consumed =
      Enum.reduce(blocks, consumed, fn block, acc ->
        case block.terminator do
          {:ret, reg} when is_integer(reg) -> MapSet.put(acc, reg)
          _ -> acc
        end
      end)

    MapSet.difference(produced, consumed)
  end

  defp partially_consumed_owned(%FunctionPlan{blocks: blocks}) do
    {produced, consumed} = track_produced_consumed(blocks)
    MapSet.intersection(produced, consumed)
  end

  defp track_produced_consumed(blocks) do
    Enum.reduce(blocks, {MapSet.new(), MapSet.new()}, fn block, acc ->
      Enum.reduce(block.instrs, acc, &track_function_instr/2)
    end)
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

  defp owned_exits(%FunctionPlan{blocks: blocks, entry_block: entry}) do
    by_id = Cfg.block_map(blocks)

    do_owned(
      :queue.in(entry, :queue.new()),
      %{entry => MapSet.new()},
      %{},
      by_id
    )
  end

  defp do_owned(queue, owned_in, owned_exit, by_id) do
    case :queue.out(queue) do
      {:empty, _} ->
        owned_exit

      {{:value, id}, rest} ->
        case Map.fetch(by_id, id) do
          :error ->
            do_owned(rest, owned_in, owned_exit, by_id)

          {:ok, block} ->
            exit_owned =
              Enum.reduce(
                block.instrs,
                Map.get(owned_in, id, MapSet.new()),
                fn instr, owned -> apply_owned(owned, instr) end
              )

            owned_exit = Map.put(owned_exit, id, exit_owned)

            {queue, owned_in} =
              Enum.reduce(Cfg.successors(block.terminator), {rest, owned_in}, fn succ, {q, ins} ->
                case Map.get(ins, succ) do
                  nil ->
                    {:queue.in(succ, q), Map.put(ins, succ, exit_owned)}

                  old ->
                    joined = MapSet.intersection(old, exit_owned)

                    if MapSet.equal?(joined, old) do
                      {q, ins}
                    else
                      {:queue.in(succ, q), Map.put(ins, succ, joined)}
                    end
                end
              end)

            do_owned(queue, owned_in, owned_exit, by_id)
        end
    end
  end

  defp liveness_out(blocks) do
    by_id = Cfg.block_map(blocks)
    preds = predecessors(blocks)
    ids = Enum.map(blocks, & &1.id)
    live_out = Map.new(ids, fn id -> {id, MapSet.new()} end)

    do_live(:queue.from_list(ids), live_out, by_id, preds)
  end

  defp do_live(queue, live_out, by_id, preds) do
    case :queue.out(queue) do
      {:empty, _} ->
        live_out

      {{:value, id}, rest} ->
        block = Map.fetch!(by_id, id)
        live_in = live_in(block, Map.get(live_out, id, MapSet.new()))

        {queue, live_out} =
          Enum.reduce(Map.get(preds, id, []), {rest, live_out}, fn pred, {q, outs} ->
            old = Map.get(outs, pred, MapSet.new())
            new = MapSet.union(old, live_in)

            if MapSet.equal?(new, old) do
              {q, outs}
            else
              {:queue.in(pred, q), Map.put(outs, pred, new)}
            end
          end)

        do_live(queue, live_out, by_id, preds)
    end
  end

  defp live_in(block, live_out) do
    live = MapSet.union(live_out, MapSet.new(term_uses(block.terminator)))

    Enum.reduce(Enum.reverse(block.instrs), live, fn instr, live ->
      live
      |> MapSet.difference(MapSet.new(instr_defs(instr)))
      |> MapSet.union(MapSet.new(instr_uses(instr)))
    end)
  end

  defp predecessors(blocks) do
    Enum.reduce(blocks, %{}, fn block, acc ->
      Enum.reduce(Cfg.successors(block.terminator), acc, fn succ, acc ->
        Map.update(acc, succ, [block.id], &[block.id | &1])
      end)
    end)
  end

  defp apply_owned(owned, %Types{op: :release, args: %{reg: reg}}) when is_integer(reg) do
    MapSet.delete(owned, reg)
  end

  defp apply_owned(owned, instr) do
    owned
    |> mark_consumed(instr.effects.consumes || [])
    |> track_produces(instr)
  end

  defp insert_releases(%Block{instrs: instrs, terminator: term} = block, leftover) do
    live = MapSet.union(live_owned(instrs), leftover)
    ret_reg = ret_reg(term)

    leaked =
      live
      |> MapSet.to_list()
      |> Enum.reject(&(&1 == ret_reg))
      |> Enum.sort()

    insert_release_regs(block, leaked)
  end

  defp insert_release_regs(%Block{instrs: instrs} = block, regs) when is_list(regs) do
    already = released_in(instrs)

    leaked =
      Enum.reject(regs, fn
        reg when is_integer(reg) -> MapSet.member?(already, reg)
        _ -> true
      end)

    if leaked == [] do
      block
    else
      release_instrs =
        Enum.map(leaked, fn reg ->
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
  end

  defp released_in(instrs) do
    Enum.reduce(instrs, MapSet.new(), fn
      %{op: :release, args: %{reg: reg}}, acc when is_integer(reg) -> MapSet.put(acc, reg)
      _, acc -> acc
    end)
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
    Enum.reduce(consumes, owned, fn
      reg, acc when is_integer(reg) -> MapSet.delete(acc, reg)
      _, acc -> acc
    end)
  end

  defp instr_defs(%{dest: dest}) when is_integer(dest), do: [dest]
  defp instr_defs(_), do: []

  defp instr_uses(%{op: :phi, args: args}) when is_map(args) do
    [Map.get(args, :then), Map.get(args, :else), Map.get(args, :cond)]
    |> Enum.filter(&is_integer/1)
  end

  defp instr_uses(%{op: :release, args: %{reg: reg}}) when is_integer(reg), do: [reg]

  defp instr_uses(%{effects: effects}) do
    (effects.borrows || []) ++ (effects.consumes || [])
  end

  defp instr_uses(_), do: []

  defp term_uses({:br_if, _, _, reg}) when is_integer(reg), do: [reg]
  defp term_uses({:ret, reg}) when is_integer(reg), do: [reg]
  defp term_uses({:switch_tag, reg, _, _}) when is_integer(reg), do: [reg]
  defp term_uses(_), do: []

  defp ret_reg({:ret, reg}) when is_integer(reg), do: reg
  defp ret_reg(_), do: nil
end
