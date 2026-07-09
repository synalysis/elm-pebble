defmodule Elmc.Backend.Plan.Verify do
  @moduledoc """
  Ownership and liveness verifier for `%FunctionPlan{}`.

  Rejects plans that would cause RC leaks, double-free, or mid-branch
  result inspection bugs before any backend emits target code.
  """

  alias Elmc.Backend.Plan.Types
  alias Elmc.Backend.Plan.Types.{Block, FunctionPlan}

  @type verify_error :: {:error, atom(), keyword()}

  @type state :: %{
          owned: MapSet.t(Types.reg()),
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
         :ok <- walk_blocks(plan) do
      :ok
    end
  end

  defp verify_blocks_present(%{blocks: []}), do: {:error, :empty_plan, []}
  defp verify_blocks_present(_), do: :ok

  defp verify_entry_block(%{entry_block: entry, blocks: blocks}) do
    if Enum.any?(blocks, &(&1.id == entry)), do: :ok, else: {:error, :missing_entry_block, []}
  end

  defp walk_blocks(plan) do
    initial = %{
      owned: MapSet.new(),
      consumed: MapSet.new(),
      fn_out_writes: 0,
      branch_out_writes: 0,
      in_catch: 0,
      published_fn_out: false,
      rc_required: plan.rc_required
    }

    plan.blocks
    |> Enum.sort_by(& &1.id)
    |> Enum.reduce_while(:ok, fn block, :ok ->
      case walk_block(block, initial, plan.name) do
        {:ok, _st} -> {:cont, :ok}
        {:error, reason, meta} -> {:halt, {:error, reason, meta}}
      end
    end)
    |> case do
      :ok -> :ok
      {:error, _, _} = err -> err
    end
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

        _ ->
          {:ok, st2}
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
    |> Map.put(:consumed, MapSet.new())
    |> check_borrows_not_consumed(effects.borrows || [])
    |> mark_consumed(branch_regs)
    |> track_produces(effects.produces, dest)
    |> then(fn st1 ->
      merge_owned =
        case dest do
          reg when is_integer(reg) -> MapSet.new([reg])
          _ -> MapSet.new()
        end

      %{st1 | owned: merge_owned}
    end)
  end

  defp apply_instr(%Types{op: :phi, args: %{then: then_reg, else: else_reg, cond: cond_reg}, effects: effects, dest: dest}, st) do
    merge_owned =
      case dest do
        reg when is_integer(reg) -> MapSet.new([reg])
        _ -> MapSet.new()
      end

    st
    |> Map.put(:consumed, MapSet.new())
    |> check_borrows_not_consumed(effects.borrows || [])
    |> mark_consumed((effects.consumes || []) ++ [then_reg, else_reg, cond_reg])
    |> then(&%{&1 | owned: merge_owned})
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

  defp apply_instr(%Types{effects: effects, dest: dest}, st) do
    apply_value_effects(%Types{effects: effects, dest: dest}, st)
  end

  defp apply_value_effects(%Types{effects: effects, dest: dest}, st) do
    st
    |> check_borrows_not_consumed(effects.borrows || [])
    |> track_produces(effects.produces, dest)
    |> mark_consumed(effects.consumes || [])
  end

  defp check_borrows_not_consumed(st, borrows) do
    Enum.each(borrows, fn reg ->
      if MapSet.member?(st.consumed, reg), do: verify_fail!(:read_after_consume, reg: reg)
    end)

    st
  end

  defp track_produces(st, {:owned, reg}, _dest) when is_integer(reg) do
    %{st | owned: MapSet.put(st.owned, reg)}
  end

  defp track_produces(st, _, _dest), do: st

  defp mark_consumed(st, consumes) do
    Enum.reduce(consumes, st, fn reg, acc ->
      %{
        acc
        | consumed: MapSet.put(acc.consumed, reg),
          owned: MapSet.delete(acc.owned, reg)
      }
    end)
  end

  defp apply_terminator({:ret, reg}, st) when reg in [:fn_out, :branch_out] do
    %{st | owned: MapSet.delete(st.owned, reg)}
  end

  defp apply_terminator({:ret, reg}, st) when is_integer(reg) do
    if MapSet.member?(st.consumed, reg), do: verify_fail!(:ret_after_consume, reg: reg)

    %{st | owned: MapSet.delete(st.owned, reg)}
  end

  defp apply_terminator({:br, _target}, st) do
    %{st | owned: MapSet.new()}
  end

  defp apply_terminator({:br_if, _, _, reg}, st) do
    if MapSet.member?(st.consumed, reg), do: verify_fail!(:branch_on_consumed, reg: reg)
    %{st | owned: MapSet.new()}
  end

  defp apply_terminator({:switch_tag, reg, _, _}, st) do
    if MapSet.member?(st.consumed, reg), do: verify_fail!(:switch_on_consumed, reg: reg)

    %{st | owned: MapSet.new()}
  end

  defp apply_terminator(_, st), do: st

  defp verify_no_leaked_owned(st, plan_name) do
    case MapSet.to_list(st.owned) do
      [] ->
        :ok

      leaked ->
        {:error, :leaked_owned_regs, [regs: leaked, plan: plan_name]}
    end
  end

  defp verify_fail!(reason, meta), do: throw({:verify_fail, reason, meta})
end
