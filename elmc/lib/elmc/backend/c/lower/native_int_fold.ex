defmodule Elmc.Backend.C.Lower.NativeIntFold do
  @moduledoc false

  alias Elmc.Backend.C.Lower.Instr
  alias Elmc.Backend.Plan.Types.FunctionPlan

  @spec inline_exprs(FunctionPlan.t(), keyword()) :: %{non_neg_integer() => String.t()}
  def inline_exprs(%FunctionPlan{} = plan, opts) do
    native_int_only = Keyword.get(opts, :native_int_only_regs, MapSet.new())
    native_bool_only = Keyword.get(opts, :native_bool_only_regs, MapSet.new())
    ret_reg = Keyword.get(opts, :native_ret_reg)

    uses = count_operand_uses(plan, native_int_only, native_bool_only)

    native_int_only
    |> MapSet.to_list()
    |> Enum.sort()
    |> Enum.reduce(%{}, fn reg, acc ->
      if Map.get(uses, reg, 0) == 1 and inlineable_reg?(plan, reg) do
        case inline_expr(plan, reg, acc, opts) do
          nil -> acc
          expr -> Map.put(acc, reg, expr)
        end
      else
        acc
      end
    end)
    |> propagate_inlines(plan, opts, uses, ret_reg)
  end

  defp propagate_inlines(inlines, plan, opts, uses, ret_reg) do
    native_int_only = Keyword.get(opts, :native_int_only_regs, MapSet.new())

    changed? =
      native_int_only
      |> MapSet.to_list()
      |> Enum.any?(fn reg ->
        Map.get(uses, reg, 0) == 1 and inlineable_reg?(plan, reg) and
          not Map.has_key?(inlines, reg) and inline_expr(plan, reg, inlines, opts) != nil
      end)

    if changed? do
      next =
        native_int_only
        |> MapSet.to_list()
        |> Enum.sort()
        |> Enum.reduce(inlines, fn reg, acc ->
          if Map.get(uses, reg, 0) == 1 and inlineable_reg?(plan, reg) do
            case inline_expr(plan, reg, acc, opts) do
              nil -> acc
              expr -> Map.put(acc, reg, expr)
            end
          else
            acc
          end
        end)

      propagate_inlines(next, plan, opts, uses, ret_reg)
    else
      inlines
    end
  end

  defp inlineable_reg?(%FunctionPlan{} = plan, reg) do
    case defining_instr(plan, reg) do
      %{op: :int_arith} -> true
      _ -> false
    end
  end

  @doc false
  @spec int_arith_c_expr(map(), map(), keyword()) :: String.t() | nil
  def int_arith_c_expr(args, slots, opts), do: int_arith_c_expr_dispatch(args, slots, opts)

  defp inline_expr(plan, reg, inlines, opts) do
    slots = %{}

    case defining_instr(plan, reg) do
      %{op: :const_int, args: %{value: value}} ->
        Integer.to_string(value)

      %{op: :const_c_expr, args: %{value: value}} when is_binary(value) ->
        "(#{value})"

      %{op: :int_arith, args: args} ->
        int_arith_c_expr_dispatch(args, slots, Keyword.put(opts, :native_int_inline, inlines))

      _ ->
        nil
    end
  end

  defp int_arith_c_expr_dispatch(%{kind: :add_const, lhs: lhs, value: value}, slots, opts) do
    "#{Instr.int_operand_ref(lhs, slots, opts)} + #{value}"
  end

  defp int_arith_c_expr_dispatch(%{kind: :sub_const, lhs: lhs, value: value}, slots, opts) do
    "#{Instr.int_operand_ref(lhs, slots, opts)} - #{value}"
  end

  defp int_arith_c_expr_dispatch(%{kind: :add_vars, lhs: lhs, rhs: rhs}, slots, opts) do
    "#{Instr.int_operand_ref(lhs, slots, opts)} + #{Instr.int_operand_ref(rhs, slots, opts)}"
  end

  defp int_arith_c_expr_dispatch(%{kind: :mul_vars, lhs: lhs, rhs: rhs}, slots, opts) do
    "#{Instr.int_operand_ref(lhs, slots, opts)} * #{Instr.int_operand_ref(rhs, slots, opts)}"
  end

  defp int_arith_c_expr_dispatch(%{kind: :sub_vars, lhs: lhs, rhs: rhs}, slots, opts) do
    "#{Instr.int_operand_ref(lhs, slots, opts)} - #{Instr.int_operand_ref(rhs, slots, opts)}"
  end

  defp int_arith_c_expr_dispatch(%{kind: :idiv_vars, lhs: lhs, rhs: rhs}, slots, opts) do
    lhs_s = Instr.int_operand_ref(lhs, slots, opts)
    rhs_s = Instr.int_operand_ref(rhs, slots, opts)
    "(#{rhs_s} == 0 ? 0 : #{lhs_s} / #{rhs_s})"
  end

  defp int_arith_c_expr_dispatch(%{kind: :mod_vars, lhs: base, rhs: value}, slots, opts) do
    base_s = Instr.int_operand_ref(base, slots, opts)
    value_s = Instr.int_operand_ref(value, slots, opts)
    Instr.elm_mod_by_c_expr(base_s, value_s)
  end

  defp int_arith_c_expr_dispatch(%{kind: :rem_vars, lhs: base, rhs: value}, slots, opts) do
    base_s = Instr.int_operand_ref(base, slots, opts)
    value_s = Instr.int_operand_ref(value, slots, opts)
    "(#{base_s} == 0 ? 0 : #{value_s} % #{base_s})"
  end

  defp int_arith_c_expr_dispatch(%{kind: :min_vars, lhs: lhs, rhs: rhs}, slots, opts) do
    lhs_s = Instr.int_operand_ref(lhs, slots, opts)
    rhs_s = Instr.int_operand_ref(rhs, slots, opts)
    "(#{lhs_s} <= #{rhs_s}) ? #{lhs_s} : #{rhs_s}"
  end

  defp int_arith_c_expr_dispatch(%{kind: :max_vars, lhs: lhs, rhs: rhs}, slots, opts) do
    lhs_s = Instr.int_operand_ref(lhs, slots, opts)
    rhs_s = Instr.int_operand_ref(rhs, slots, opts)
    "(#{lhs_s} >= #{rhs_s}) ? #{lhs_s} : #{rhs_s}"
  end

  defp int_arith_c_expr_dispatch(_, _, _), do: nil

  defp count_operand_uses(%FunctionPlan{blocks: blocks}, native_int_only, native_bool_only) do
    arith_uses =
      blocks
      |> Enum.flat_map(& &1.instrs)
      |> Enum.reduce(%{}, fn instr, acc ->
        instr
        |> operand_regs(native_int_only, native_bool_only)
        |> Enum.reduce(acc, fn reg, counts ->
          Map.update(counts, reg, 1, &(&1 + 1))
        end)
      end)

    blocks
    |> Enum.flat_map(& &1.instrs)
    |> Enum.reduce(arith_uses, fn instr, acc ->
      case instr do
        %{op: :publish, dest: :fn_out, args: %{source: reg}} when is_integer(reg) ->
          if MapSet.member?(native_int_only, reg) do
            Map.update(acc, reg, 1, &(&1 + 1))
          else
            acc
          end

        _ ->
          acc
      end
    end)
  end

  defp operand_regs(%{op: :int_arith, args: args}, native_int_only, _native_bool_only) do
    []
    |> maybe_reg(args, :lhs, native_int_only)
    |> maybe_reg(args, :rhs, native_int_only)
    |> maybe_reg(args, :value, native_int_only)
  end

  defp operand_regs(%{op: :phi, args: %{cond: cond}}, _native_int_only, native_bool_only) do
    if MapSet.member?(native_bool_only, cond), do: [cond], else: []
  end

  defp operand_regs(%{op: :compare, args: %{left: left, right: right}}, native_int_only, _) do
    Enum.filter([left, right], &MapSet.member?(native_int_only, &1))
  end

  defp operand_regs(_, _, _), do: []

  defp maybe_reg(regs, args, key, native_set) do
    case Map.get(args, key) do
      reg when is_integer(reg) ->
        if MapSet.member?(native_set, reg), do: [reg | regs], else: regs

      _ ->
        regs
    end
  end

  defp defining_instr(%FunctionPlan{blocks: blocks}, reg) do
    Enum.find_value(blocks, fn %{instrs: instrs} ->
      Enum.find(instrs, &match?(%{dest: ^reg}, &1))
    end)
  end
end
