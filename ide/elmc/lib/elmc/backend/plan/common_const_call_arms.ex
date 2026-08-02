defmodule Elmc.Backend.Plan.CommonConstCallArms do
  @moduledoc false

  # Factor switch_tag arms that share the same call shape and differ only by a
  # const_int operand (typically an all-nullary enum tag) into:
  #
  #   case TAG_A: shared = CONST_A; goto common
  #   case TAG_B: shared = CONST_B; goto common
  #   common: callee(..., shared, ...)
  #
  # Generic: no Msg/Direction name coupling — the const/union_ctor comes from
  # each arm's own plan body (the IR-lowered callee argument).

  alias Elmc.Backend.Plan.Types
  alias Elmc.Backend.Plan.Types.{Block, FunctionPlan}

  @spec run(FunctionPlan.t()) :: FunctionPlan.t()
  def run(%FunctionPlan{blocks: blocks} = plan) do
    blocks
    |> Enum.filter(&match?(%Block{terminator: {:switch_tag, _, _, _}}, &1))
    |> Enum.reduce(plan, &common_switch/2)
  end

  @spec common_switch(Block.t(), FunctionPlan.t()) :: FunctionPlan.t()
  defp common_switch(%Block{terminator: {:switch_tag, _subj, arms, _default}}, plan) do
    by_id = Map.new(plan.blocks, &{&1.id, &1})

    arm_infos =
      arms
      |> Enum.map(fn
        {_tag, arm_id} -> arm_id
        {_tag, arm_id, _ctor} -> arm_id
      end)
      |> Enum.uniq()
      |> Enum.flat_map(fn arm_id ->
        case Map.get(by_id, arm_id) do
          %Block{} = block ->
            case analyze_arm(block) do
              {:ok, info} -> [%{arm_id: arm_id, info: info}]
              :error -> []
            end

          _ ->
            []
        end
      end)

    arm_infos
    |> Enum.group_by(fn %{info: %{shape: shape}} -> shape end)
    |> Enum.reduce(plan, fn {_shape, group}, acc ->
      if length(group) >= 2, do: rewrite_cluster(acc, group), else: acc
    end)
  end

  @spec analyze_arm(Block.t()) ::
          {:ok,
           %{
             shape: term(),
             hole_dest: Types.reg(),
             hole_value: integer(),
             hole_ctor: String.t() | nil,
             hole_bool_lit: boolean(),
             terminator: Block.terminator()
           }}
          | :error

  defp analyze_arm(%Block{instrs: instrs, terminator: terminator}) do
    if match?({:br, _}, terminator) and has_call?(instrs) do
      const_defs =
        for %{op: :const_int, dest: dest, args: %{value: value} = args} <- instrs,
            is_integer(dest) and is_integer(value),
            do:
              {dest, value, Map.get(args, :union_ctor), Map.get(args, :bool_lit) == true}

      holes =
        Enum.filter(const_defs, fn {dest, _value, _ctor, _bool_lit?} ->
          Enum.any?(instrs, fn
            %{op: :const_int} -> false
            instr -> dest in operand_regs(instr)
          end)
        end)

      case holes do
        # Bool True/False (`bool_lit`) must not be rewritten as bare int tags —
        # dropping `bool_lit` makes Debug.toString print `1`/`0` instead of True/False.
        [{_hole_dest, _hole_value, _hole_ctor, true}] ->
          :error

        [{hole_dest, hole_value, hole_ctor, false}] ->
          # Drop the hole const from the shape — only its *uses* matter. Keeping
          # value/union_ctor in the key would make every arm unique.
          body = Enum.reject(instrs, &(&1.op == :const_int and &1.dest == hole_dest))
          shape = {normalize_instrs(body, hole_dest), terminator}

          {:ok,
           %{
             shape: shape,
             hole_dest: hole_dest,
             hole_value: hole_value,
             hole_ctor: hole_ctor,
             hole_bool_lit: false,
             terminator: terminator
           }}

        _ ->
          :error
      end
    else
      :error
    end
  end

  @spec has_call?([map()]) :: boolean()
  defp has_call?(instrs) do
    Enum.any?(instrs, &(&1.op in [:call_fn, :call_runtime]))
  end

  @spec normalize_instrs([map()], Types.reg()) :: [term()]
  defp normalize_instrs(instrs, hole_dest) do
    temp_map = %{hole_dest => :hole}

    {temp_map, _} =
      Enum.reduce(instrs, {temp_map, 0}, fn instr, {map, n} ->
        case instr.dest do
          dest when is_integer(dest) ->
            if Map.has_key?(map, dest) do
              {map, n}
            else
              {Map.put(map, dest, {:t, n}), n + 1}
            end

          _ ->
            {map, n}
        end
      end)

    Enum.map(instrs, fn instr ->
      {
        instr.op,
        normalize_dest(instr.dest, temp_map),
        normalize_args(instr.args, temp_map)
      }
    end)
  end

  defp normalize_dest(dest, map) when is_integer(dest), do: Map.get(map, dest, dest)
  defp normalize_dest(dest, _map), do: dest

  defp normalize_args(args, map) when is_map(args) do
    args
    |> Enum.map(fn {k, v} -> {k, normalize_value(v, map)} end)
    |> Map.new()
  end

  defp normalize_args(args, _map), do: args

  defp normalize_value(v, map) when is_integer(v), do: Map.get(map, v, v)
  defp normalize_value(list, map) when is_list(list), do: Enum.map(list, &normalize_value(&1, map))
  defp normalize_value(map_val, map) when is_map(map_val) do
    map_val
    |> Enum.map(fn {k, v} -> {k, normalize_value(v, map)} end)
    |> Map.new()
  end
  defp normalize_value(other, _map), do: other

  @spec rewrite_cluster(FunctionPlan.t(), [map()]) :: FunctionPlan.t()
  defp rewrite_cluster(%FunctionPlan{} = plan, group) do
    [%{arm_id: first_id, info: first_info} | _] = group
    by_id = Map.new(plan.blocks, &{&1.id, &1})
    %Block{} = first_block = Map.fetch!(by_id, first_id)

    shared_tag = plan.reg_count
    # Place the shared body *before* the merge/ret block so goto-CFG emit does
    # not fall through a `{:ret, :fn_out}` block into the common call.
    {:br, merge_id} = first_info.terminator
    common_id = allocate_block_id(plan.blocks, merge_id)

    common_instrs =
      first_block.instrs
      |> Enum.reject(fn
        %{op: :const_int, dest: dest} -> dest == first_info.hole_dest
        _ -> false
      end)
      |> Enum.map(&rewrite_instr(&1, first_info.hole_dest, shared_tag, common_id))

    common_block = %Block{
      id: common_id,
      instrs: common_instrs,
      terminator: first_info.terminator
    }

    stub_blocks =
      Enum.map(group, fn %{arm_id: arm_id, info: info} ->
        const_args =
          %{value: info.hole_value}
          |> then(fn args ->
            if is_binary(info.hole_ctor),
              do: Map.put(args, :union_ctor, info.hole_ctor),
              else: args
          end)
          |> then(fn args ->
            if Map.get(info, :hole_bool_lit) == true,
              do: Map.put(args, :bool_lit, true),
              else: args
          end)

        %Block{
          id: arm_id,
          instrs: [
            %Types{
              id: 0,
              op: :const_int,
              dest: shared_tag,
              args: const_args,
              effects: %{fallible: false, borrows: [], consumes: [], produces: nil},
              block_id: arm_id,
              span: nil
            }
          ],
          terminator: {:br, common_id}
        }
      end)

    stub_ids = MapSet.new(group, & &1.arm_id)

    blocks =
      plan.blocks
      |> Enum.reject(&MapSet.member?(stub_ids, &1.id))
      |> Kernel.++(stub_blocks)
      |> Kernel.++([common_block])
      |> Enum.sort_by(& &1.id)

    %{plan | blocks: blocks, reg_count: shared_tag + 1}
  end

  @spec allocate_block_id([Block.t()], non_neg_integer()) :: non_neg_integer()
  defp allocate_block_id(blocks, merge_id) when is_integer(merge_id) do
    used = MapSet.new(blocks, & &1.id)

    0..(max(merge_id - 1, 0))
    |> Enum.find(&(not MapSet.member?(used, &1)))
    |> case do
      id when is_integer(id) -> id
      nil -> 1 + Enum.max(Enum.map(blocks, & &1.id))
    end
  end

  @spec rewrite_instr(map(), Types.reg(), Types.reg(), non_neg_integer()) :: map()
  defp rewrite_instr(instr, hole_dest, shared_tag, common_id) do
    instr
    |> Map.put(:block_id, common_id)
    |> subst_reg(hole_dest, shared_tag)
    |> drop_tag_consume(shared_tag)
  end

  defp subst_reg(%{args: args, effects: effects} = instr, from, to) do
    %{
      instr
      | dest: if(instr.dest == from, do: to, else: instr.dest),
        args: subst_value(args, from, to),
        effects: subst_effects(effects, from, to)
    }
  end

  defp subst_value(v, from, to) when v == from, do: to
  defp subst_value(list, from, to) when is_list(list), do: Enum.map(list, &subst_value(&1, from, to))
  defp subst_value(map, from, to) when is_map(map) do
    map
    |> Enum.map(fn {k, v} -> {k, subst_value(v, from, to)} end)
    |> Map.new()
  end
  defp subst_value(other, _from, _to), do: other

  defp subst_effects(effects, from, to) when is_map(effects) do
    effects
    |> Map.update(:borrows, [], fn b -> Enum.map(b || [], fn r -> if(r == from, do: to, else: r) end) end)
    |> Map.update(:consumes, [], fn c -> Enum.map(c || [], fn r -> if(r == from, do: to, else: r) end) end)
    |> Map.update(:produces, nil, fn
      {:owned, ^from} -> {:owned, to}
      other -> other
    end)
  end

  defp subst_effects(effects, _from, _to), do: effects

  # Shared tag is a native multi-def int, not an owned heap value.
  defp drop_tag_consume(%{effects: %{consumes: consumes} = effects} = instr, tag)
       when is_list(consumes) do
    %{instr | effects: %{effects | consumes: Enum.reject(consumes, &(&1 == tag))}}
  end

  defp drop_tag_consume(instr, _tag), do: instr

  @spec operand_regs(term()) :: [Types.reg()]
  defp operand_regs(%{args: args}) when is_map(args), do: collect_regs(Map.values(args))
  defp operand_regs(_), do: []

  defp collect_regs(n) when is_integer(n), do: [n]
  defp collect_regs(list) when is_list(list), do: Enum.flat_map(list, &collect_regs/1)
  defp collect_regs(map) when is_map(map), do: collect_regs(Map.values(map))
  defp collect_regs(_), do: []
end
