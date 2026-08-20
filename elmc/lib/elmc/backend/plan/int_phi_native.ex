defmodule Elmc.Backend.Plan.IntPhiNative do
  @moduledoc false
  alias Elmc.Backend.Plan.Types, as: Types


  alias Elmc.Backend.Plan.Types

  @type arm_shape ::
          :unknown
          | {:const_int, integer()}
          | {:int_arith, Types.instr_args()}
          | {:new_int, integer() | String.t()}
          | {:reg, Types.reg()}
          | {:load_param, non_neg_integer()}
          | {:record_get_int, Types.reg()}
          | {:native_int_phi, Types.reg()}

  @spec arm_shape(Types.instr_list(), non_neg_integer()) :: arm_shape()
  def arm_shape(instrs, reg) when is_list(instrs) and is_integer(reg) do
    case Enum.find(instrs, &(&1.dest == reg)) do
      nil ->
        :unknown

      instr ->
        shape_from_instr(instr)
    end
  end

  defp shape_from_instr(%{op: :const_int, args: %{bool_lit: true}}), do: :unknown

  defp shape_from_instr(%{op: :const_int, args: %{value: value}}), do: {:const_int, value}

  defp shape_from_instr(%{op: :int_arith, args: args}), do: {:int_arith, args}

  defp shape_from_instr(%{op: :call_runtime, args: %{builtin: :new_int, literal: value}}),
    do: {:new_int, value}

  defp shape_from_instr(%{op: :call_runtime, args: %{builtin: :new_int, c_expr: expr}}) when is_binary(expr),
    do: {:new_int, expr}

  # Soft: a bare param is only native when the other arm is a proved Int
  # (const / arith / field / nested int phi). Two Float params stay boxed.
  defp shape_from_instr(%{op: :load_param, dest: dest, args: %{index: index}})
       when is_integer(dest) and is_integer(index),
       do: {:load_param, index}

  defp shape_from_instr(%{op: :load_param, dest: dest}) when is_integer(dest),
    do: {:reg, dest}

  defp shape_from_instr(%{op: :record_get_int, dest: dest}) when is_integer(dest),
    do: {:record_get_int, dest}

  defp shape_from_instr(%{op: :phi, dest: dest, args: %{native_int_phi: true}})
       when is_integer(dest),
       do: {:native_int_phi, dest}

  defp shape_from_instr(_), do: :unknown

  @spec native_int_phi_shapes?(Types.instr_list(), non_neg_integer(), non_neg_integer()) ::
          {boolean(), arm_shape(), arm_shape()}
  def native_int_phi_shapes?(instrs, then_reg, else_reg) do
    then_shape = arm_shape(instrs, then_reg)
    else_shape = arm_shape(instrs, else_reg)
    {native_int_pair?(then_shape, else_shape), then_shape, else_shape}
  end

  defp native_int_pair?(a, b) do
    (hard_int_shape?(a) and (hard_int_shape?(b) or soft_int_shape?(b))) or
      (soft_int_shape?(a) and hard_int_shape?(b))
  end

  defp hard_int_shape?({:const_int, _}), do: true
  defp hard_int_shape?({:int_arith, _}), do: true
  defp hard_int_shape?({:new_int, _}), do: true
  defp hard_int_shape?({:record_get_int, _}), do: true
  defp hard_int_shape?({:native_int_phi, _}), do: true
  defp hard_int_shape?(_), do: false

  defp soft_int_shape?({:reg, _}), do: true
  defp soft_int_shape?({:load_param, _}), do: true
  defp soft_int_shape?(_), do: false

  @spec phi_arm_drop_instrs(Types.block_list()) :: MapSet.t({non_neg_integer(), non_neg_integer()})
  def phi_arm_drop_instrs(blocks) when is_list(blocks) do
    blocks
    |> Enum.flat_map(& &1.instrs)
    |> Enum.filter(&match?(%{op: :phi, args: %{native_int_phi: true}}, &1))
    |> Enum.flat_map(fn %{args: args} ->
      # Only drop arms whose shape is fully reconstructed at the phi.
      # `{:record_get_int, N}` / `{:reg, N}` still need the defining instruction —
      # dropping them leaves undeclared `tmp_N` in C (see TruthyNative).
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

  defp reconstructible_phi_arm_shape?({:const_int, _}), do: true
  defp reconstructible_phi_arm_shape?({:new_int, _}), do: true
  defp reconstructible_phi_arm_shape?({:int_arith, _}), do: true
  defp reconstructible_phi_arm_shape?({:load_param, _}), do: true
  defp reconstructible_phi_arm_shape?(_), do: false
end
