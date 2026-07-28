defmodule Elmc.Backend.Plan.Optimize do
  @moduledoc false
  alias Elmc.Backend.Plan.Types, as: Types


  alias Elmc.Backend.Plan.{IntPhiNative, TruthyNative}
  alias Elmc.Backend.Plan.Types
  alias Elmc.Backend.Plan.Types.{Block, FunctionPlan}

  @spec run(FunctionPlan.t()) :: FunctionPlan.t()
  def run(%FunctionPlan{blocks: blocks} = plan) do
    blocks = Enum.map(blocks, &coalesce_arm_publish_block/1)

    used = used_regs(blocks)
    phi_arm_drops =
      MapSet.union(
        TruthyNative.phi_arm_drop_instrs(blocks),
        IntPhiNative.phi_arm_drop_instrs(blocks)
      )

    # Drop dead retains before last-use→transfer rewriting. Otherwise a dead
    # retain can be rewritten to consume its src, the matching `:release` is
    # removed, then the retain itself is deleted — leaving a leaked owned reg.
    blocks =
      Enum.map(blocks, fn block ->
        instrs =
          block.instrs
          |> Enum.reject(&dead_retain?(&1, used))
          |> Enum.reject(&dead_phi_arm_value?(&1, phi_arm_drops))
          |> drop_unread_overwritten_defs(block.terminator)

        %{block | instrs: instrs}
      end)

    last_reads = last_read_indices(blocks)
    owned_defs = owned_produced_regs_all(blocks)

    blocks =
      blocks
      |> Enum.map(&rewrite_block_transfers(&1, last_reads, owned_defs))
      |> simplify_branch_targets()

    %{plan | blocks: blocks}
  end

  @spec coalesce_arm_publish_block(map()) :: Types.ir_expr()

  defp coalesce_arm_publish_block(%Block{instrs: instrs} = block) do
    %{block | instrs: coalesce_arm_publish_instrs(instrs)}
  end

  @spec coalesce_arm_publish_instrs(list()) :: Types.ir_expr()

  defp coalesce_arm_publish_instrs(instrs) when is_list(instrs) do
    case Enum.split(instrs, -2) do
      {prefix,
       [
         %{op: :call_fn, dest: arm_reg} = call,
         %{
           op: :call_runtime,
           dest: merge_reg,
           args: %{builtin: :retain, args: [src_reg]},
           effects: %{consumes: consumes}
         }
       ]}
      when is_integer(arm_reg) and is_integer(merge_reg) and is_integer(src_reg) and
             arm_reg == src_reg and arm_reg != merge_reg and consumes == [arm_reg] ->
        prefix ++ [%{call | dest: merge_reg}]

      {prefix,
       [
         %{op: :call_runtime, dest: arm_reg, args: %{builtin: builtin}} = record,
         %{
           op: :call_runtime,
           dest: merge_reg,
           args: %{builtin: :retain, args: [src_reg]},
           effects: %{consumes: consumes}
         }
       ]}
      when builtin in [:record_new, :record_new_take] and is_integer(arm_reg) and
             is_integer(merge_reg) and is_integer(src_reg) and arm_reg == src_reg and
             arm_reg != merge_reg and consumes == [arm_reg] ->
        prefix ++ [%{record | dest: merge_reg}]

      _ ->
        instrs
    end
  end

  defp rewrite_block_transfers(%Block{} = block, last_reads, owned_defs) do
    instrs =
      block.instrs
      |> rewrite_last_use_retains(block.id, last_reads, owned_defs)
      |> drop_releases_of_already_consumed()

    %{block | instrs: instrs}
  end

  # When `retain(src)` is the last read of an owned `src` in the function, emit a
  # consuming transfer instead of retain+later release/reassign. That lowers to
  # a pointer move (`owned[d]=owned[s]; owned[s]=NULL`) instead of retain/release.
  defp rewrite_last_use_retains(instrs, block_id, last_reads, owned_defs) when is_list(instrs) do
    Enum.map(instrs, fn instr ->
      maybe_consume_last_use_retain(instr, block_id, last_reads, owned_defs)
    end)
  end

  defp maybe_consume_last_use_retain(
         %{
           id: instr_id,
           op: :call_runtime,
           dest: dest,
           args: %{builtin: :retain, args: [src]},
           effects: effects
         } = instr,
         block_id,
         last_reads,
         owned_defs
       )
       when is_integer(dest) and is_integer(src) and dest != src and is_map(effects) do
    consumes = List.wrap(Map.get(effects, :consumes, []))
    key = {block_id, instr_id}

    cond do
      src in consumes ->
        instr

      Map.has_key?(Map.get(instr, :args, %{}), :view_peel) ->
        instr

      not MapSet.member?(owned_defs, src) ->
        instr

      Map.get(last_reads, src) != key ->
        instr

      true ->
        borrows = List.wrap(Map.get(effects, :borrows, []))

        %{
          instr
          | effects: %{
              effects
              | consumes: [src],
                borrows: Enum.reject(borrows, &(&1 == src))
            }
        }
    end
  end

  defp maybe_consume_last_use_retain(instr, _block_id, _last_reads, _owned_defs), do: instr

  defp owned_produced_regs_all(blocks) when is_list(blocks) do
    blocks
    |> Enum.flat_map(fn %Block{instrs: instrs} ->
      Enum.flat_map(instrs, fn
        %{effects: %{produces: {:owned, reg}}} when is_integer(reg) -> [reg]
        _ -> []
      end)
    end)
    |> MapSet.new()
  end

  # Last *read* of each reg as `{block_id, instr_id}` (releases ignored so a
  # trailing `:release` does not block transferring the prior retain).
  defp last_read_indices(blocks) when is_list(blocks) do
    Enum.reduce(blocks, %{}, fn %Block{id: block_id, instrs: instrs, terminator: term}, acc ->
      acc =
        Enum.reduce(instrs, acc, fn
          %{op: :release}, acc_inner ->
            acc_inner

          %{id: instr_id} = instr, acc_inner when is_integer(instr_id) ->
            Enum.reduce(operand_regs(instr), acc_inner, fn
              reg, a when is_integer(reg) -> Map.put(a, reg, {block_id, instr_id})
              _, a -> a
            end)

          _, acc_inner ->
            acc_inner
        end)

      Enum.reduce(terminator_uses(term), acc, fn
        reg, a when is_integer(reg) -> Map.put(a, reg, {block_id, :terminator})
        _, a -> a
      end)
    end)
  end

  defp drop_releases_of_already_consumed(instrs) when is_list(instrs) do
    {kept, _consumed} =
      Enum.reduce(instrs, {[], MapSet.new()}, fn instr, {acc, consumed} ->
        case instr do
          %{op: :release, args: %{reg: reg}} when is_integer(reg) ->
            # Do not mark this release's own consumes before the check — otherwise
            # every epilogue `:release` looks "already consumed" and is dropped.
            if MapSet.member?(consumed, reg) do
              {acc, consumed}
            else
              {acc ++ [instr], mark_instr_consumes(instr, consumed)}
            end

          _ ->
            {acc ++ [instr], mark_instr_consumes(instr, consumed)}
        end
      end)

    kept
  end

  defp mark_instr_consumes(%{effects: %{consumes: consumes}}, consumed) when is_list(consumes) do
    Enum.reduce(consumes, consumed, fn
      reg, acc when is_integer(reg) -> MapSet.put(acc, reg)
      _, acc -> acc
    end)
  end

  defp mark_instr_consumes(_, consumed), do: consumed

  @spec drop_unread_overwritten_defs(list(), Types.ir_expr()) :: Types.ir_expr()

  defp drop_unread_overwritten_defs(instrs, terminator) when is_list(instrs) do
    {dead, _} = unread_overwritten_indices(instrs, terminator)

    instrs
    |> Enum.with_index()
    |> Enum.reject(fn {_, idx} -> MapSet.member?(dead, idx) end)
    |> Enum.map(fn {instr, _} -> instr end)
  end

  @doc false
  @spec unread_overwritten_dest_regs(Types.instr_list(), Block.terminator()) :: MapSet.t()
  def unread_overwritten_dest_regs(instrs, terminator) when is_list(instrs) do
    {dead, _} = unread_overwritten_indices(instrs, terminator)

    dead
    |> Enum.flat_map(fn idx ->
      case Enum.at(instrs, idx) do
        %{dest: dest} when is_integer(dest) -> [dest]
        _ -> []
      end
    end)
    |> MapSet.new()
  end

  @spec unread_overwritten_indices(list(), Types.ir_expr()) :: Types.ir_expr()

  defp unread_overwritten_indices(instrs, terminator) when is_list(instrs) do
    final_reads = terminator |> terminator_uses() |> MapSet.new()

    {dead, state} =
      Enum.reduce(Enum.with_index(instrs), {MapSet.new(), %{}}, fn {instr, idx}, {dead, state} ->
        state = mark_operand_reads(instr, state)

        case Map.get(instr, :dest) do
          dest when is_integer(dest) ->
            {dead, state} =
              case Map.get(state, dest) do
                %{def_idx: def_idx, read: false, instr: prev} when is_map(prev) ->
                  dead =
                    if removable_overwritten_def?(prev),
                      do: MapSet.put(dead, def_idx),
                      else: dead

                  {dead, Map.put(state, dest, %{def_idx: idx, read: false, instr: instr})}

                _ ->
                  {dead, Map.put(state, dest, %{def_idx: idx, read: false, instr: instr})}
              end

            {dead, state}

          _ ->
            {dead, state}
        end
      end)

    dead =
      Enum.reduce(final_reads, dead, fn reg, dead_acc ->
        case Map.get(state, reg) do
          %{def_idx: idx} -> MapSet.delete(dead_acc, idx)
          _ -> dead_acc
        end
      end)

    {dead, state}
  end

  @spec removable_overwritten_def?(map() | term()) :: boolean()

  defp removable_overwritten_def?(%{op: :const_int}), do: true

  defp removable_overwritten_def?(%{op: :call_runtime, args: %{builtin: builtin}})
       when builtin in [:retain, :new_int],
       do: true

  defp removable_overwritten_def?(_), do: false

  @spec mark_operand_reads(Types.ir_expr(), Types.ir_expr()) :: Types.ir_expr()

  defp mark_operand_reads(instr, state) do
    Enum.reduce(operand_regs(instr), state, fn reg, acc ->
      case Map.get(acc, reg) do
        %{def_idx: _def_idx} = entry -> Map.put(acc, reg, %{entry | read: true})
        _ -> acc
      end
    end)
  end

  @spec dead_phi_arm_value?(map() | term(), Types.ir_expr() | term()) :: boolean()

  defp dead_phi_arm_value?(%{dest: dest, block_id: block_id}, phi_arm_drops)
       when is_integer(dest) and is_integer(block_id) do
    MapSet.member?(phi_arm_drops, {dest, block_id})
  end

  defp dead_phi_arm_value?(_, _), do: false

  @spec dead_retain?(map() | term(), Types.ir_expr() | term()) :: boolean()

  defp dead_retain?(
         %{
           op: :call_runtime,
           dest: dest,
           args: %{builtin: :retain, args: [_src]}
         },
         used
       )
       when is_integer(dest) do
    not MapSet.member?(used, dest)
  end

  defp dead_retain?(_, _), do: false

  @spec used_regs(Types.ir_expr()) :: Types.ir_expr()

  defp used_regs(blocks) do
    blocks
    |> Enum.flat_map(fn %Block{instrs: instrs, terminator: term} ->
      instr_uses(instrs) ++ terminator_uses(term)
    end)
    |> Enum.filter(&is_integer/1)
    |> MapSet.new()
  end

  @spec instr_uses(Types.ir_expr()) :: Types.ir_expr()

  defp instr_uses(instrs) do
    Enum.flat_map(instrs, fn
      %Types{dest: dest} = instr when is_integer(dest) ->
        operand_regs(instr) ++ [dest]

      instr ->
        operand_regs(instr)
    end)
  end

  @spec terminator_uses(term()) :: Types.ir_expr()

  defp terminator_uses({:br_if, _, _, cond}) when is_integer(cond), do: [cond]
  defp terminator_uses({:switch_tag, subject, _, _}) when is_integer(subject), do: [subject]
  defp terminator_uses({:ret, reg}) when is_integer(reg), do: [reg]
  defp terminator_uses(_), do: []

  @spec operand_regs(map() | term()) :: Types.ir_expr()

  defp operand_regs(%{op: :phi, args: %{then: then_r, else: else_r, cond: cond}}),
    do: [then_r, else_r, cond]

  defp operand_regs(%{op: :phi, args: %{then: then_r, else: else_r}}), do: [then_r, else_r]

  defp operand_regs(%{effects: %{borrows: borrows, consumes: consumes}}) do
    (borrows || []) ++ (consumes || [])
  end

  defp operand_regs(%{args: %{args: args}}) when is_list(args), do: args
  defp operand_regs(%{args: %{lhs: lhs, rhs: rhs}}), do: [lhs, rhs]
  defp operand_regs(%{args: %{base: base}}) when is_integer(base), do: [base]
  defp operand_regs(%{args: %{source: source}}) when is_integer(source), do: [source]
  defp operand_regs(%{args: %{subject: subject}}) when is_integer(subject), do: [subject]
  defp operand_regs(%{args: %{regs: regs}}) when is_list(regs), do: regs
  defp operand_regs(%{args: %{params: params}}) when is_list(params), do: params
  defp operand_regs(_), do: []

  @spec simplify_branch_targets(list()) :: Types.ir_expr()

  defp simplify_branch_targets(blocks) when is_list(blocks) do
    by_id = Map.new(blocks, &{&1.id, &1})

    Enum.map(blocks, fn block ->
      case block.terminator do
        {:br_if, then_id, else_id, cond} ->
          then_target = resolve_br_target(by_id, then_id)
          else_target = resolve_br_target(by_id, else_id)

          cond do
            then_target == else_target ->
              %{block | terminator: {:br, then_target}}

            then_target != then_id or else_target != else_id ->
              %{block | terminator: {:br_if, then_target, else_target, cond}}

            true ->
              block
          end

        {:br, target_id} ->
          resolved = resolve_br_target(by_id, target_id)

          if resolved != target_id do
            %{block | terminator: {:br, resolved}}
          else
            block
          end

        _ ->
          block
      end
    end)
  end

  @spec resolve_br_target(Types.ir_expr(), integer()) :: Types.ir_expr()

  defp resolve_br_target(by_id, id) when is_integer(id) do
    case Map.get(by_id, id) do
      %Block{instrs: [], terminator: {:br, target}} when is_integer(target) ->
        resolve_br_target(by_id, target)

      %Block{id: ^id} ->
        id

      _ ->
        id
    end
  end
end
