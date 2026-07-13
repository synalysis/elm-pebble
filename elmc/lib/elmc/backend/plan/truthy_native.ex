defmodule Elmc.Backend.Plan.TruthyNative do
  @moduledoc false

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

  defp shape_from_instr(%{op: :const_int, args: %{value: value}}) when value in [0, 1],
    do: {:const_int, value}

  defp shape_from_instr(%{op: :compare, args: %{kind: kind, left: left, right: right}}),
    do: {:compare, kind || :eq, left, right}

  defp shape_from_instr(%{op: op, dest: dest, args: %{left: _left, right: _right}})
       when op in [:bool_and, :test_maybe_nothing, :test_list_empty, :test_ctor_tag, :test_bool] and is_integer(dest),
       do: {:reg, dest}

  defp shape_from_instr(%{op: :call_runtime, args: %{builtin: :new_int, literal: value}})
       when value in [0, 1],
       do: {:const_int, value}

  defp shape_from_instr(%{op: :call_runtime, args: %{builtin: :new_bool, literal: value}})
       when value in [0, 1],
       do: {:const_int, value}

  defp shape_from_instr(_), do: :unknown

  defp truthy_bool_phi_shape?({:const_int, value}) when value in [0, 1], do: true
  defp truthy_bool_phi_shape?({:compare, _, _, _}), do: true
  defp truthy_bool_phi_shape?({:reg, _}), do: true
  defp truthy_bool_phi_shape?(_), do: false

  @spec phi_shapes?(Types.instr_list(), non_neg_integer(), non_neg_integer()) ::
          {boolean(), arm_shape(), arm_shape()}
  def phi_shapes?(instrs, then_reg, else_reg) do
    then_shape = arm_shape(instrs, then_reg)
    else_shape = arm_shape(instrs, else_reg)

    truthy? = truthy_bool_phi_shape?(then_shape) and truthy_bool_phi_shape?(else_shape)
    {truthy?, then_shape, else_shape}
  end

  @spec phi_arm_drop_instrs(Types.block_list()) :: MapSet.t({non_neg_integer(), non_neg_integer()})
  def phi_arm_drop_instrs(blocks) when is_list(blocks) do
    blocks
    |> Enum.flat_map(& &1.instrs)
    |> Enum.filter(&match?(%{op: :phi, args: %{truthy_native: true}}, &1))
    |> Enum.flat_map(fn %{args: args} ->
      [
        {args.then, Map.fetch!(args, :then_arm_block)},
        {args.else, Map.fetch!(args, :else_arm_block)}
      ]
    end)
    |> MapSet.new()
  end

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
