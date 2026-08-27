defmodule Elmc.Backend.Plan.Verify do
  @moduledoc """
  Ownership and liveness verifier for `%FunctionPlan{}`.

  Rejects plans that would cause RC leaks, double-free, or mid-branch
  result inspection bugs before any backend emits target code.

  Inter-block dataflow: owned/consumed/`fn_out` publish state is joined at
  successors. Must-own is the **intersection** of incoming owned sets; may-own
  is the union. A register owned on only some predecessors is not must-live
  after the merge (phi/release must account for it). `fusion_c`-only plans
  (no SSA blocks) are rejected.
  """

  alias Elmc.Backend.Plan.Cfg
  alias Elmc.Backend.Plan.Types
  alias Elmc.Backend.Plan.Types.{Block, FunctionPlan}

  @type verify_error :: {:error, atom(), keyword()}

  @type state :: %{
          owned: MapSet.t(Types.reg()),
          maybe_owned: MapSet.t(Types.reg()),
          consumed: MapSet.t(Types.reg()),
          fn_out_writes: non_neg_integer(),
          branch_out_writes: non_neg_integer(),
          in_catch: non_neg_integer(),
          published_fn_out: boolean(),
          rc_required: boolean()
        }

  @spec run(FunctionPlan.t()) :: :ok | verify_error()
  def run(%FunctionPlan{} = plan) do
    with :ok <- verify_blocks_present(plan),
         :ok <- verify_entry_block(plan),
         :ok <- verify_cfg(plan),
         :ok <- walk_cfg(plan) do
      :ok
    else
      {:error, _reason, _meta} = err ->
        if Process.get(:elmc_verify_dump_on_fail) do
          Process.put(:elmc_verify_fail_plan, plan)
        end

        err
    end
  end

  defp verify_blocks_present(%{blocks: [], fusion_c: fusion})
       when is_binary(fusion) and fusion != "",
       do: {:error, :unverified_fusion_c, [plan: :fusion_c]}

  defp verify_blocks_present(%{blocks: []}), do: {:error, :empty_plan, []}
  defp verify_blocks_present(_), do: :ok

  defp verify_entry_block(%{entry_block: entry, blocks: blocks}) do
    if Enum.any?(blocks, &(&1.id == entry)), do: :ok, else: {:error, :missing_entry_block, []}
  end

  defp verify_cfg(%{blocks: blocks, entry_block: entry}) do
    with :ok <- verify_no_permanent_none(blocks),
         :ok <- verify_no_dangling_targets(blocks),
         :ok <- verify_all_blocks_reachable(blocks, entry) do
      :ok
    end
  end

  defp verify_no_permanent_none(blocks) do
    case Cfg.permanent_none_blocks(blocks) do
      [] ->
        :ok

      [block_id | _] ->
        {:error, :permanent_none_terminator, [block: block_id]}
    end
  end

  defp verify_no_dangling_targets(blocks) do
    case Cfg.dangling_targets(blocks) do
      [] ->
        :ok

      [{from_id, target_id} | _] ->
        {:error, :dangling_branch_target, [from: from_id, target: target_id]}
    end
  end

  defp verify_all_blocks_reachable(blocks, entry) do
    case Cfg.unreachable_block_ids(blocks, entry) do
      [] ->
        :ok

      [block_id | _] ->
        {:error, :unreachable_block, [block: block_id, entry: entry]}
    end
  end

  defp initial_state(plan) do
    %{
      owned: MapSet.new(),
      maybe_owned: MapSet.new(),
      consumed: MapSet.new(),
      fn_out_writes: 0,
      branch_out_writes: 0,
      in_catch: 0,
      published_fn_out: false,
      rc_required: plan.rc_required
    }
  end

  defp walk_cfg(plan) do
    by_id = Cfg.block_map(plan.blocks)
    init = initial_state(plan)

    do_worklist(
      by_id,
      :queue.in(plan.entry_block, :queue.new()),
      %{plan.entry_block => init},
      %{},
      plan.name
    )
  end

  defp do_worklist(by_id, queue, in_states, out_states, plan_name) do
    case :queue.out(queue) do
      {:empty, _} ->
        :ok

      {{:value, block_id}, rest} ->
        block = Map.fetch!(by_id, block_id)
        in_st = Map.fetch!(in_states, block_id)

        case walk_block(block, in_st, plan_name) do
          {:error, _, _} = err ->
            err

          {:ok, out_st} ->
            prev = Map.get(out_states, block_id)

            if prev == out_st do
              do_worklist(by_id, rest, in_states, out_states, plan_name)
            else
              out_states = Map.put(out_states, block_id, out_st)
              succs = Cfg.successors(block.terminator)

              {queue, in_states} =
                Enum.reduce(succs, {rest, in_states}, fn succ_id, {q, ins} ->
                  joined = join_state(Map.get(ins, succ_id), out_st)

                  if Map.get(ins, succ_id) == joined do
                    {q, ins}
                  else
                    {:queue.in(succ_id, q), Map.put(ins, succ_id, joined)}
                  end
                end)

              do_worklist(by_id, queue, in_states, out_states, plan_name)
            end
        end
    end
  end

  defp join_state(nil, incoming), do: incoming

  defp join_state(existing, incoming) do
    %{
      owned: MapSet.intersection(existing.owned, incoming.owned),
      maybe_owned: MapSet.union(existing.maybe_owned, incoming.maybe_owned),
      consumed: MapSet.union(existing.consumed, incoming.consumed),
      fn_out_writes: max(existing.fn_out_writes, incoming.fn_out_writes),
      branch_out_writes: max(existing.branch_out_writes, incoming.branch_out_writes),
      in_catch: max(existing.in_catch, incoming.in_catch),
      published_fn_out: existing.published_fn_out or incoming.published_fn_out,
      rc_required: existing.rc_required
    }
  end

  defp walk_block(%Block{instrs: instrs, terminator: term}, state, plan_name) do
    try do
      st1 = Enum.reduce(instrs, state, &apply_instr/2)
      st2 = apply_terminator(term, st1)

      case term do
        {:ret, _} ->
          case verify_no_leaked_owned(st2, plan_name) do
            :ok -> {:ok, st2}
            {:error, reason, meta} -> {:error, reason, meta}
          end

        {:br, _} ->
          {:ok, st2}

        {:br_if, _, _, _} ->
          {:ok, st2}

        {:switch_tag, _, _, _} ->
          {:ok, st2}

        :none ->
          {:error, :permanent_none_terminator, [plan: plan_name]}

        other ->
          {:error, :unknown_terminator, [term: other, plan: plan_name]}
      end
    catch
      {:verify_fail, reason, meta} -> {:error, reason, meta}
    end
  end

  defp apply_instr(%Types{op: :switch_ctor_tag, dest: dest, args: args, effects: effects}, st) do
    branch_regs =
      (Map.get(args, :arms, []) |> Enum.map(& &1.reg)) ++
        List.wrap(Map.get(args, :default))

    st
    |> check_not_after_fn_out_publish(:switch_ctor_tag)
    |> check_borrows_not_consumed(effects.borrows || [])
    |> mark_consumed(branch_regs)
    |> track_produces(effects.produces, dest)
  end

  defp apply_instr(%Types{op: :phi, args: %{then: _, else: _, cond: _}, effects: effects, dest: dest}, st) do
    st
    |> check_not_after_fn_out_publish(:phi)
    |> check_borrows_not_consumed(effects.borrows || [])
    |> mark_consumed(effects.consumes || [])
    |> track_produces(effects.produces, dest)
  end

  defp apply_instr(%Types{op: :release, args: %{reg: reg}}, st) when is_integer(reg) do
    mark_consumed(st, [reg])
  end

  defp apply_instr(%Types{op: :catch_begin}, %{in_catch: d} = st),
    do: %{st | in_catch: d + 1}

  defp apply_instr(%Types{op: :catch_end}, %{in_catch: d} = st),
    do: %{st | in_catch: max(0, d - 1)}

  defp apply_instr(%Types{effects: %{fallible: true}} = instr, %{in_catch: 0, rc_required: true} = st),
    do: apply_value_effects(instr, st)

  # Non-RC `ElmcValue *` helpers use `_take_value` allocators (NULL on failure), not
  # per-instruction plan catch regions or CHECK_RC.
  defp apply_instr(%Types{effects: %{fallible: true}} = instr, %{in_catch: 0, rc_required: false} = st),
    do: apply_value_effects(instr, st)

  defp apply_instr(%Types{effects: %{fallible: true}} = instr, %{in_catch: 0}),
    do: verify_fail!(:fallible_outside_catch, [op: instr.op, dest: instr.dest])

  defp apply_instr(%Types{effects: %{fallible: true}} = instr, st),
    do: apply_value_effects(instr, st)

  defp apply_instr(%Types{op: :publish, dest: :fn_out, args: %{source: reg}}, st) when is_integer(reg) do
    if st.published_fn_out, do: verify_fail!(:double_fn_out_publish, [])

    st
    |> mark_consumed([reg])
    |> then(&%{&1 | fn_out_writes: &1.fn_out_writes + 1, published_fn_out: true})
  end

  defp apply_instr(%Types{op: :publish, dest: :fn_out}, st) do
    if st.published_fn_out, do: verify_fail!(:double_fn_out_publish, [])

    %{st | fn_out_writes: st.fn_out_writes + 1, published_fn_out: true}
  end

  defp apply_instr(%Types{op: :publish, dest: :branch_out}, st) do
    if st.branch_out_writes > 0, do: verify_fail!(:double_branch_out_publish, [])

    %{st | branch_out_writes: st.branch_out_writes + 1}
  end

  defp apply_instr(%Types{dest: dest} = instr, st) do
    apply_value_effects(instr, st)
    |> then(fn st1 ->
      if dest == :fn_out and instr.op != :publish do
        if st.published_fn_out, do: verify_fail!(:double_fn_out_publish, [])
        %{st1 | fn_out_writes: st1.fn_out_writes + 1, published_fn_out: true}
      else
        st1
      end
    end)
  end

  defp apply_value_effects(%Types{effects: effects, dest: dest, op: op}, st) do
    st = check_not_after_fn_out_publish(st, op)

    with :ok <- verify_produces_kind(effects.produces),
         :ok <- verify_result_aliases(effects, dest) do
      st
      |> check_borrows_not_consumed(effects.borrows || [])
      |> track_produces(effects.produces, dest)
      |> mark_consumed(effects.consumes || [])
    else
      {:error, reason, meta} -> verify_fail!(reason, meta)
    end
  end

  defp check_not_after_fn_out_publish(%{published_fn_out: true} = st, op)
       when op not in [:publish, :release, :catch_begin, :catch_end] do
    verify_fail!(:mid_branch_fn_out, [op: op])
    st
  end

  defp check_not_after_fn_out_publish(st, _op), do: st

  defp verify_produces_kind(nil), do: :ok
  defp verify_produces_kind({:owned, _}), do: :ok
  defp verify_produces_kind({:immortal, _}), do: :ok
  defp verify_produces_kind({:native_int, _}), do: :ok
  defp verify_produces_kind({:native_bool, _}), do: :ok
  defp verify_produces_kind({:native_float, _}), do: :ok
  defp verify_produces_kind(other), do: {:error, :unknown_produce_kind, [produces: other]}

  defp verify_result_aliases(%{result_aliases: aliases, consumes: consumes}, dest)
       when is_list(aliases) and aliases != [] do
    cond do
      Enum.any?(aliases, &(&1 in consumes)) ->
        {:error, :result_alias_consumed, [aliases: aliases, consumes: consumes]}

      is_integer(dest) and dest in aliases ->
        {:error, :result_alias_includes_dest, [dest: dest, aliases: aliases]}

      true ->
        :ok
    end
  end

  defp verify_result_aliases(_, _), do: :ok

  defp check_borrows_not_consumed(st, borrows) do
    Enum.each(borrows, fn reg ->
      if MapSet.member?(st.consumed, reg), do: verify_fail!(:read_after_consume, reg: reg)

      if MapSet.member?(st.maybe_owned, reg) and not MapSet.member?(st.owned, reg) do
        verify_fail!(:asymmetric_owned_borrow, reg: reg)
      end
    end)

    st
  end

  defp track_produces(st, {:owned, reg}, _dest) when is_integer(reg) do
    %{st | owned: MapSet.put(st.owned, reg), maybe_owned: MapSet.put(st.maybe_owned, reg)}
  end

  defp track_produces(st, {:immortal, _reg}, _dest), do: st
  defp track_produces(st, {:native_int, _reg}, _dest), do: st
  defp track_produces(st, {:native_bool, _reg}, _dest), do: st
  defp track_produces(st, {:native_float, _reg}, _dest), do: st
  defp track_produces(st, _, _dest), do: st

  defp mark_consumed(st, consumes) do
    Enum.reduce(consumes, st, fn reg, acc ->
      %{
        acc
        | consumed: MapSet.put(acc.consumed, reg),
          owned: MapSet.delete(acc.owned, reg),
          maybe_owned: MapSet.delete(acc.maybe_owned, reg)
      }
    end)
  end

  defp apply_terminator({:ret, reg}, st) when reg in [:fn_out, :branch_out, :stream_void] do
    drop_owned(st, reg)
  end

  defp apply_terminator({:ret, reg}, st) when is_integer(reg) do
    if MapSet.member?(st.consumed, reg), do: verify_fail!(:ret_after_consume, reg: reg)

    drop_owned(st, reg)
  end

  defp apply_terminator({:br, _target}, st), do: st

  defp apply_terminator({:br_if, _, _, reg}, st) do
    if MapSet.member?(st.consumed, reg), do: verify_fail!(:branch_on_consumed, reg: reg)
    st
  end

  defp apply_terminator({:switch_tag, reg, _, _}, st) do
    if MapSet.member?(st.consumed, reg), do: verify_fail!(:switch_on_consumed, reg: reg)
    st
  end

  defp apply_terminator(_, st), do: st

  defp drop_owned(st, reg) do
    %{st | owned: MapSet.delete(st.owned, reg), maybe_owned: MapSet.delete(st.maybe_owned, reg)}
  end

  defp verify_no_leaked_owned(st, plan_name) do
    leaked =
      st.owned
      |> MapSet.union(st.maybe_owned)
      |> MapSet.to_list()

    case leaked do
      [] ->
        :ok

      regs ->
        {:error, :leaked_owned_regs, [regs: regs, plan: plan_name]}
    end
  end

  @spec verify_fail!(atom(), keyword()) :: no_return()
  defp verify_fail!(reason, meta), do: throw({:verify_fail, reason, meta})
end
