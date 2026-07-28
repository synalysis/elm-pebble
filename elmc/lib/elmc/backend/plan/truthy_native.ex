defmodule Elmc.Backend.Plan.TruthyNative do
  @moduledoc false
  alias Elmc.Backend.Plan.Types, as: Types


  alias Elmc.Backend.Plan.Types

  @type arm_shape ::
          :unknown
          | {:const_int, 0 | 1}
          | {:compare, atom(), non_neg_integer(), non_neg_integer()}
          | {:reg, non_neg_integer()}

  @spec arm_shape(Types.instr_list(), non_neg_integer()) :: arm_shape()
  def arm_shape(instrs, reg) when is_list(instrs) and is_integer(reg) do
    case Enum.find(instrs, &(&1.dest == reg)) do
      nil ->
        phi_shape_for_reg(instrs, reg) || :unknown

      instr ->
        shape_from_instr(instr)
    end
  end

  defp phi_shape_for_reg(instrs, reg) do
    Enum.find_value(instrs, fn
      %{op: :phi, args: %{truthy_native: true, then: ^reg, then_shape: shape}} -> shape
      %{op: :phi, args: %{truthy_native: true, else: ^reg, else_shape: shape}} -> shape
      _ -> nil
    end)
  end

  # Only Bool True/False (const_int with bool_lit), not Int 0/1 — those belong to
  # IntPhiNative so Debug.toString stays numeric and arm drops stay consistent.
  defp shape_from_instr(%{op: :const_int, args: %{value: value, bool_lit: true}})
       when value in [0, 1],
       do: {:const_int, value}

  defp shape_from_instr(%{op: :compare, args: %{kind: kind, left: left, right: right}}),
    do: {:compare, kind || :eq, left, right}

  defp shape_from_instr(%{op: :bool_and, dest: dest}) when is_integer(dest),
    do: {:reg, dest}

  defp shape_from_instr(%{op: op, dest: dest})
       when op in [:test_maybe_nothing, :test_list_empty, :test_list_length_gte, :test_ctor_tag, :test_bool] and
              is_integer(dest),
       do: {:reg, dest}

  defp shape_from_instr(%{op: :call_runtime, args: %{builtin: :new_bool, literal: value}})
       when value in [0, 1],
       do: {:const_int, value}

  defp shape_from_instr(%{op: :platform_static_bool, dest: dest}) when is_integer(dest),
    do: {:reg, dest}

  defp shape_from_instr(_), do: :unknown

  defp truthy_bool_phi_shape?({:const_int, value}) when value in [0, 1], do: true
  defp truthy_bool_phi_shape?({:compare, _, _, _}), do: true
  defp truthy_bool_phi_shape?({:reg, _}), do: true
  defp truthy_bool_phi_shape?(_), do: false

  @spec phi_shapes?(Types.instr_list(), non_neg_integer(), non_neg_integer()) ::
          {boolean(), arm_shape(), arm_shape()}
  def phi_shapes?(instrs, then_reg, else_reg) do
    then_raw = arm_shape(instrs, then_reg)
    else_raw = arm_shape(instrs, else_reg)
    then_bare = bare_const_int_01_shape(instrs, then_reg)
    else_bare = bare_const_int_01_shape(instrs, else_reg)

    # Prefer Bool True/False / compare shapes. Also accept a bare Int 0/1 next to
    # a bool-shaped arm (e.g. `if n < 0 then 1 else n == 0`) so the merge stays
    # native bool (`? true :`). Both-arms bare 0/1 stays IntPhiNative.
    {truthy?, then_shape, else_shape} =
      cond do
        truthy_bool_phi_shape?(then_raw) and truthy_bool_phi_shape?(else_raw) ->
          {true, then_raw, else_raw}

        match?({:const_int, _}, then_bare) and truthy_bool_phi_shape?(else_raw) ->
          {true, then_bare, else_raw}

        truthy_bool_phi_shape?(then_raw) and match?({:const_int, _}, else_bare) ->
          {true, then_raw, else_bare}

        true ->
          {false, then_raw, else_raw}
      end

    {truthy?, then_shape, else_shape}
  end

  # Bare Int 0/1 (no bool_lit) — promoted only when paired with a bool-shaped arm.
  defp bare_const_int_01_shape(instrs, reg) do
    case Enum.find(instrs, &(&1.dest == reg)) do
      %{op: :const_int, args: %{value: value} = args} when value in [0, 1] ->
        if Map.get(args, :bool_lit) == true do
          nil
        else
          {:const_int, value}
        end

      %{op: :call_runtime, args: %{builtin: :new_int, literal: value}} when value in [0, 1] ->
        {:const_int, value}

      _ ->
        nil
    end
  end

  @spec phi_arm_drop_instrs(Types.block_list()) :: MapSet.t({non_neg_integer(), non_neg_integer()})
  def phi_arm_drop_instrs(blocks) when is_list(blocks) do
    blocks
    |> Enum.flat_map(& &1.instrs)
    |> Enum.filter(&match?(%{op: :phi, args: %{truthy_native: true}}, &1))
    |> Enum.flat_map(fn %{args: args} ->
      # Only drop arms whose shape is fully reconstructed at the phi
      # (`const_int` / `compare`). `{:reg, N}` still needs the defining
      # instruction — dropping it leaves undeclared `tmp_N` in C.
      []
      |> maybe_drop_arm(args.then, Map.fetch!(args, :then_arm_block), Map.get(args, :then_shape))
      |> maybe_drop_arm(args.else, Map.fetch!(args, :else_arm_block), Map.get(args, :else_shape))
    end)
    |> MapSet.new()
  end

  defp maybe_drop_arm(acc, reg, block_id, shape)
       when is_integer(reg) and is_integer(block_id) and is_list(acc) do
    if reconstructible_phi_arm_shape?(shape) do
      [{reg, block_id} | acc]
    else
      acc
    end
  end

  defp reconstructible_phi_arm_shape?({:const_int, value}) when value in [0, 1], do: true
  defp reconstructible_phi_arm_shape?({:compare, _, _, _}), do: true
  defp reconstructible_phi_arm_shape?(_), do: false

  @doc false
  @spec phi_arm_drop_regs(Types.block_list()) :: MapSet.t(non_neg_integer())
  def phi_arm_drop_regs(blocks) when is_list(blocks) do
    blocks
    |> phi_arm_drop_instrs()
    |> Enum.map(fn {reg, _} -> reg end)
    |> MapSet.new()
  end

  @spec truthy_native_arm?(Types.FunctionPlan.t(), non_neg_integer()) :: boolean()
  def truthy_native_arm?(plan, reg) when is_map(plan) and is_integer(reg) do
    instrs = plan |> Map.get(:blocks, []) |> Enum.flat_map(& &1.instrs)
    instrs |> arm_shape(reg) |> truthy_bool_phi_shape?()
  end

  def truthy_native_arm?(_, _), do: false
end
