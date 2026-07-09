defmodule Elmc.Backend.Plan.IntPhiNative do
  @moduledoc false

  @type arm_shape ::
          :unknown
          | {:const_int, integer()}
          | {:int_arith, map()}
          | {:new_int, integer() | String.t()}

  @spec arm_shape([map()], non_neg_integer()) :: arm_shape()
  def arm_shape(instrs, reg) when is_list(instrs) and is_integer(reg) do
    case Enum.find(instrs, &(&1.dest == reg)) do
      nil ->
        :unknown

      instr ->
        shape_from_instr(instr)
    end
  end

  defp shape_from_instr(%{op: :const_int, args: %{value: value}}), do: {:const_int, value}

  defp shape_from_instr(%{op: :int_arith, args: args}), do: {:int_arith, args}

  defp shape_from_instr(%{op: :call_runtime, args: %{builtin: :new_int, literal: value}}),
    do: {:new_int, value}

  defp shape_from_instr(%{op: :call_runtime, args: %{builtin: :new_int, c_expr: expr}}) when is_binary(expr),
    do: {:new_int, expr}

  defp shape_from_instr(_), do: :unknown

  @spec native_int_phi_shapes?([map()], non_neg_integer(), non_neg_integer()) ::
          {boolean(), arm_shape(), arm_shape()}
  def native_int_phi_shapes?(instrs, then_reg, else_reg) do
    then_shape = arm_shape(instrs, then_reg)
    else_shape = arm_shape(instrs, else_reg)
    {native_int_shape?(then_shape) and native_int_shape?(else_shape), then_shape, else_shape}
  end

  defp native_int_shape?({:const_int, _}), do: true
  defp native_int_shape?({:int_arith, _}), do: true
  defp native_int_shape?({:new_int, _}), do: true
  defp native_int_shape?(_), do: false

  @spec phi_arm_drop_instrs([map()]) :: MapSet.t({non_neg_integer(), non_neg_integer()})
  def phi_arm_drop_instrs(blocks) when is_list(blocks) do
    blocks
    |> Enum.flat_map(& &1.instrs)
    |> Enum.filter(&match?(%{op: :phi, args: %{native_int_phi: true}}, &1))
    |> Enum.flat_map(fn %{args: args} ->
      [
        {args.then, Map.fetch!(args, :then_arm_block)},
        {args.else, Map.fetch!(args, :else_arm_block)}
      ]
    end)
    |> MapSet.new()
  end
end
