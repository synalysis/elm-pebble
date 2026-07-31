defmodule Elmc.Backend.Plan.Optimize do
  @moduledoc false
  alias Elmc.Backend.Plan.Types, as: Types

  alias Elmc.Backend.Plan.{CommonConstCallArms, IntPhiNative, TruthyNative, Tuple2IntsUnbox}
  alias Elmc.Backend.Plan.Types
  alias Elmc.Backend.Plan.Types.{Block, FunctionPlan}

  @spec run(FunctionPlan.t()) :: FunctionPlan.t()
  def run(%FunctionPlan{} = plan) do
    # Unbox local (Int,Int) before DCE/transfer rewrites so dead heap pairs and
    # their projection releases disappear cleanly.
    plan = Tuple2IntsUnbox.run(plan)
    blocks = Enum.map(plan.blocks, &coalesce_arm_publish_block/1)
    plan = CommonConstCallArms.run(%{plan | blocks: blocks})
    blocks = plan.blocks

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
          |> then(fn is ->
            if System.get_env("ELMC_SKIP_PHI_ARM_DROP") == "1",
              do: is,
              else: Enum.reject(is, &dead_phi_arm_value?(&1, phi_arm_drops))
          end)
          |> drop_unread_overwritten_defs(block.terminator)

        %{block | instrs: instrs}
      end)

    last_reads = last_read_indices(blocks)
    owned_defs = owned_produced_regs_all(blocks)

    blocks =
      blocks
      |> Enum.map(&rewrite_block_transfers(&1, last_reads, owned_defs))
      # Fold consuming retain moves into the producer dest so C emit does not
      # juggle distinct owned[] slots (`owned[a]=owned[b]; owned[b]=NULL`).
      |> Enum.map(&coalesce_consuming_retain_block/1)
      |> simplify_branch_targets()
      |> prune_unreachable_empty_blocks(plan.entry_block)

    %{plan | blocks: blocks}
  end

  defp prune_unreachable_empty_blocks(blocks, entry) do
    reachable = Elmc.Backend.Plan.Cfg.reachable_ids(blocks, entry)

    Enum.reject(blocks, fn %Block{id: id, instrs: instrs} ->
      instrs == [] and not MapSet.member?(reachable, id)
    end)
  end

  @spec coalesce_arm_publish_block(Block.t()) :: Block.t()
  defp coalesce_arm_publish_block(%Block{instrs: instrs} = block) do
    %{block | instrs: coalesce_arm_publish_instrs(instrs)}
  end

  @spec coalesce_arm_publish_instrs([map()]) :: [map()]
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

  @spec coalesce_consuming_retain_block(Block.t()) :: Block.t()
  defp coalesce_consuming_retain_block(%Block{instrs: instrs} = block) do
    %{block | instrs: coalesce_consuming_retain_instrs(instrs)}
  end

  @spec coalesce_consuming_retain_instrs([map()]) :: [map()]
  defp coalesce_consuming_retain_instrs(instrs) when is_list(instrs) do
    case find_coalesceable_retain(instrs) do
      {:ok, producer_idx, retain_idx, src, dest} ->
        producer = Enum.at(instrs, producer_idx)
        producer = rewrite_producer_dest(producer, src, dest)

        instrs
        |> List.replace_at(producer_idx, producer)
        |> List.delete_at(retain_idx)
        |> coalesce_consuming_retain_instrs()

      :none ->
        instrs
    end
  end

  defp find_coalesceable_retain(instrs) do
    instrs
    |> Enum.with_index()
    |> Enum.find_value(fn
      {%{
         op: :call_runtime,
         dest: dest,
         args: %{builtin: :retain, args: [src]} = args,
         effects: effects
       }, retain_idx}
      when is_integer(dest) and is_integer(src) and dest != src ->
        consumes = List.wrap(Map.get(effects, :consumes, []))

        cond do
          Map.has_key?(args, :view_peel) ->
            nil

          src not in consumes ->
            nil

          true ->
            case find_unique_producer(instrs, src, retain_idx) do
              {:ok, producer_idx} ->
                if src_unused_between?(instrs, producer_idx, retain_idx, src) do
                  {:ok, producer_idx, retain_idx, src, dest}
                end

              :none ->
                nil
            end
        end

      _ ->
        nil
    end)
    |> case do
      nil -> :none
      other -> other
    end
  end

  defp find_unique_producer(instrs, src, before_idx) do
    matches =
      instrs
      |> Enum.with_index()
      |> Enum.filter(fn {instr, idx} ->
        idx < before_idx and Map.get(instr, :dest) == src and coalescable_producer?(instr)
      end)

    case matches do
      [{_instr, idx}] -> {:ok, idx}
      _ -> :none
    end
  end

  defp coalescable_producer?(%{op: :call_runtime, args: %{builtin: :retain, view_peel: _}}),
    do: false

  defp coalescable_producer?(%{op: :phi}), do: false
  defp coalescable_producer?(%{dest: dest}) when is_integer(dest), do: true
  defp coalescable_producer?(_), do: false

  defp src_unused_between?(instrs, producer_idx, retain_idx, src) do
    if retain_idx <= producer_idx + 1 do
      true
    else
      instrs
      |> Enum.slice((producer_idx + 1)..(retain_idx - 1)//1)
      |> Enum.all?(fn instr ->
        src not in operand_regs(instr) and Map.get(instr, :dest) != src
      end)
    end
  end

  defp rewrite_producer_dest(instr, src, dest) do
    instr = %{instr | dest: dest}

    case Map.get(instr, :effects) do
      %{produces: {:owned, ^src}} = effects ->
        %{instr | effects: %{effects | produces: {:owned, dest}}}

      _ ->
        instr
    end
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

  @spec drop_unread_overwritten_defs([map()], Block.terminator()) :: [map()]
  defp drop_unread_overwritten_defs(instrs, terminator) when is_list(instrs) do
    {dead, _} = unread_overwritten_indices(instrs, terminator)

    instrs
    |> Enum.with_index()
    |> Enum.reject(fn {_, idx} -> MapSet.member?(dead, idx) end)
    |> Enum.map(fn {instr, _} -> instr end)
  end

  @doc false
  @spec unread_overwritten_dest_regs(Types.instr_list(), Block.terminator()) :: MapSet.t(Types.reg())
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

  @spec unread_overwritten_indices([map()], Block.terminator()) ::
          {MapSet.t(non_neg_integer()), map()}
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

  @spec removable_overwritten_def?(term()) :: boolean()
  defp removable_overwritten_def?(%{op: :const_int}), do: true

  defp removable_overwritten_def?(%{op: :call_runtime, args: %{builtin: builtin}})
       when builtin in [:retain, :new_int],
       do: true

  defp removable_overwritten_def?(_), do: false

  @spec mark_operand_reads(map(), map()) :: map()
  defp mark_operand_reads(instr, state) do
    Enum.reduce(operand_regs(instr), state, fn reg, acc ->
      case Map.get(acc, reg) do
        %{def_idx: _def_idx} = entry -> Map.put(acc, reg, %{entry | read: true})
        _ -> acc
      end
    end)
  end

  @spec dead_phi_arm_value?(term(), MapSet.t()) :: boolean()
  defp dead_phi_arm_value?(%{dest: dest, block_id: block_id}, phi_arm_drops)
       when is_integer(dest) and is_integer(block_id) do
    MapSet.member?(phi_arm_drops, {dest, block_id})
  end

  defp dead_phi_arm_value?(_, _), do: false

  @spec dead_retain?(term(), MapSet.t(Types.reg())) :: boolean()
  defp dead_retain?(
         %{
           op: :call_runtime,
           dest: dest,
           args: %{builtin: :retain, args: [_src]} = args
         },
         used
       )
       when is_integer(dest) do
    # view_peel retains encode peels (e.g. maybe_just_payload) — keep them even if
    # the peeled dest looks unread in this block (downstream arms / inspect gates).
    not Map.has_key?(args, :view_peel) and not MapSet.member?(used, dest)
  end

  defp dead_retain?(_, _), do: false

  @spec used_regs([Block.t()]) :: MapSet.t(Types.reg())
  defp used_regs(blocks) do
    blocks
    |> Enum.flat_map(fn %Block{instrs: instrs, terminator: term} ->
      instr_uses(instrs) ++ terminator_uses(term)
    end)
    |> Enum.filter(&is_integer/1)
    |> MapSet.new()
  end

  @spec instr_uses([map()]) :: [Types.reg()]
  defp instr_uses(instrs) do
    # Destinations are definitions, not uses — including them would mark every
    # produced reg "live" and defeat dead_retain? / DCE.
    Enum.flat_map(instrs, &operand_regs/1)
  end

  @spec terminator_uses(term()) :: [Types.reg()]
  defp terminator_uses({:br_if, _, _, cond}) when is_integer(cond), do: [cond]
  defp terminator_uses({:switch_tag, subject, _, _}) when is_integer(subject), do: [subject]
  defp terminator_uses({:ret, reg}) when is_integer(reg), do: [reg]
  defp terminator_uses(_), do: []

  @spec operand_regs(term()) :: [Types.reg()]
  defp operand_regs(%{op: :phi, args: %{then: then_r, else: else_r, cond: cond}}),
    do: [then_r, else_r, cond]

  defp operand_regs(%{op: :phi, args: %{then: then_r, else: else_r}}), do: [then_r, else_r]

  defp operand_regs(%{op: :forward_ref_set, args: %{value: value}}) when is_integer(value),
    do: [value]

  defp operand_regs(instr) do
    # Prefer effects when present, but also walk `args` so uses that are missing
    # from borrows/consumes (e.g. some record_update COW shapes) stay live.
    effect_regs =
      case instr do
        %{effects: %{borrows: borrows, consumes: consumes}} ->
          (borrows || []) ++ (consumes || [])

        _ ->
          []
      end

    (effect_regs ++ args_regs(instr))
    |> Enum.filter(&is_integer/1)
    |> Enum.uniq()
  end

  @spec args_regs(term()) :: [Types.reg()]
  defp args_regs(%{args: args}) when is_map(args), do: collect_regs(Map.values(args))
  defp args_regs(_), do: []

  @spec collect_regs(term()) :: [Types.reg()]
  defp collect_regs(n) when is_integer(n), do: [n]
  defp collect_regs(list) when is_list(list), do: Enum.flat_map(list, &collect_regs/1)
  defp collect_regs(%{reg: r}) when is_integer(r), do: [r]
  defp collect_regs(%{args: nested}) when is_list(nested), do: collect_regs(nested)
  defp collect_regs(map) when is_map(map), do: collect_regs(Map.values(map))
  defp collect_regs(_), do: []

  @spec simplify_branch_targets([Block.t()]) :: [Block.t()]
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

  @spec resolve_br_target(%{optional(non_neg_integer()) => Block.t()}, non_neg_integer()) ::
          non_neg_integer()
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
