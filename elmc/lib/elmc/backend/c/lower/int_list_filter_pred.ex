defmodule Elmc.Backend.C.Lower.IntListFilterPred do
  @moduledoc false

  # Reconstruct a native-int Bool predicate from a filter lambda plan so an
  # INT_LIST walk can test `elmc_int_t` elements without boxing each one.

  alias Elmc.Backend.Plan.Types.FunctionPlan

  @type pred_c :: String.t()

  @spec c_expr(FunctionPlan.t() | nil, String.t()) :: pred_c() | nil
  def c_expr(%FunctionPlan{} = lambda, item_c) when is_binary(item_c) do
    if Elmc.Backend.C.Lower.Lambda.capture_count(lambda) > 0 do
      nil
    else
      instrs = flat_instrs(lambda)

      case published_bool_reg(lambda, instrs) do
        reg when is_integer(reg) ->
          reconstruct_bool(reg, instrs, item_c, MapSet.new())

        _ ->
          nil
      end
    end
  end

  def c_expr(_, _), do: nil

  defp flat_instrs(%FunctionPlan{blocks: blocks}) do
    Enum.flat_map(blocks, & &1.instrs)
  end

  defp published_bool_reg(%FunctionPlan{blocks: blocks}, instrs) do
    published =
      Enum.find_value(blocks, fn block ->
        case block.terminator do
          {:ret, :fn_out} ->
            Enum.find_value(block.instrs, fn
              %{op: :publish, dest: dest, args: %{source: src}}
              when dest in [:fn_out, :branch_out] and is_integer(src) ->
                src

              %{dest: dest, op: op} = instr
              when dest in [:fn_out, :branch_out] and op in [:compare, :bool_and, :call_runtime] ->
                Map.get(instr, :dest)

              _ ->
                nil
            end)

          {:ret, reg} when is_integer(reg) ->
            reg

          _ ->
            nil
        end
      end)

    published ||
      Enum.find_value(Enum.reverse(instrs), fn
        %{op: :call_runtime, dest: dest, args: %{builtin: :basics_not}} when is_integer(dest) ->
          dest

        %{op: :compare, dest: dest} when is_integer(dest) ->
          dest

        _ ->
          nil
      end)
  end

  defp reconstruct_bool(reg, instrs, item_c, visited) do
    if MapSet.member?(visited, reg) do
      nil
    else
      visited = MapSet.put(visited, reg)

      case Enum.find(instrs, &(&1.dest == reg)) do
        %{op: :compare, args: args} ->
          kind = Map.get(args, :kind, :eq)
          left = reconstruct_int(Map.fetch!(args, :left), instrs, item_c, visited)
          right = reconstruct_int(Map.fetch!(args, :right), instrs, item_c, visited)

          if is_binary(left) and is_binary(right) do
            compare_c(kind, left, right)
          end

        %{op: :bool_and, args: %{left: left, right: right}} ->
          l = reconstruct_bool(left, instrs, item_c, visited)
          r = reconstruct_bool(right, instrs, item_c, visited)
          if is_binary(l) and is_binary(r), do: "(#{l} && #{r})"

        %{op: :call_runtime, args: %{builtin: :new_bool, args: [inner]}} ->
          reconstruct_bool(inner, instrs, item_c, visited)

        %{op: :call_runtime, args: %{builtin: :basics_not, args: [inner]}} ->
          case reconstruct_bool(inner, instrs, item_c, visited) do
            inner_c when is_binary(inner_c) -> "!(#{inner_c})"
            _ -> nil
          end

        %{op: :const_int, args: %{value: value, bool_lit: true}} when value in [0, 1] ->
          if value == 1, do: "true", else: "false"

        %{op: :phi, args: %{truthy_native: true, cond: cond, then: then_r, else: else_r} = args} ->
          cond_c = reconstruct_bool(cond, instrs, item_c, visited)
          then_c = reconstruct_bool_or_shape(then_r, Map.get(args, :then_shape), instrs, item_c, visited)
          else_c = reconstruct_bool_or_shape(else_r, Map.get(args, :else_shape), instrs, item_c, visited)

          if is_binary(cond_c) and is_binary(then_c) and is_binary(else_c) do
            "(#{cond_c}) ? #{then_c} : #{else_c}"
          end

        _ ->
          nil
      end
    end
  end

  defp reconstruct_bool_or_shape(_reg, {:const_int, 1}, _instrs, _item_c, _visited), do: "true"
  defp reconstruct_bool_or_shape(_reg, {:const_int, 0}, _instrs, _item_c, _visited), do: "false"

  defp reconstruct_bool_or_shape(reg, _shape, instrs, item_c, visited),
    do: reconstruct_bool(reg, instrs, item_c, visited)

  defp reconstruct_int(reg, instrs, item_c, visited) when is_integer(reg) do
    if MapSet.member?(visited, reg) do
      nil
    else
      visited = MapSet.put(visited, reg)

      case Enum.find(instrs, &(&1.dest == reg)) do
        %{op: :load_param, args: %{index: 0}} ->
          item_c

        %{op: :const_int, args: %{value: value}} when is_integer(value) ->
          Integer.to_string(value)

        %{op: :int_arith, args: args} ->
          int_arith_c(args, instrs, item_c, visited)

        %{op: :call_runtime, args: %{builtin: builtin, args: [left, right]}}
        when builtin in [:basics_mod_by, :basics_remainder_by] ->
          rem_c(builtin, left, right, instrs, item_c, visited)

        %{op: :call_runtime, args: %{builtin: :new_int, literal: value}} when is_integer(value) ->
          Integer.to_string(value)

        _ ->
          nil
      end
    end
  end

  defp reconstruct_int(_, _, _, _), do: nil

  defp int_arith_c(%{kind: kind, lhs: lhs, rhs: rhs}, instrs, item_c, visited) do
    left = reconstruct_int(lhs, instrs, item_c, visited)
    right = reconstruct_int(rhs, instrs, item_c, visited)

    if is_binary(left) and is_binary(right) do
      case kind do
        :add_vars -> "(#{left} + #{right})"
        :sub_vars -> "(#{left} - #{right})"
        :mul_vars -> "(#{left} * #{right})"
        :idiv_vars -> "elmc_int_idiv(#{left}, #{right})"
        :mod_vars -> "elmc_int_mod_by(#{left}, #{right})"
        :rem_vars -> "(#{left} == 0 ? 0 : #{right} % #{left})"
        _ -> nil
      end
    end
  end

  defp int_arith_c(%{kind: :add_const, lhs: lhs, value: value}, instrs, item_c, visited)
       when is_integer(value) do
    case reconstruct_int(lhs, instrs, item_c, visited) do
      left when is_binary(left) -> "(#{left} + #{value})"
      _ -> nil
    end
  end

  defp int_arith_c(%{kind: :sub_const, lhs: lhs, value: value}, instrs, item_c, visited)
       when is_integer(value) do
    case reconstruct_int(lhs, instrs, item_c, visited) do
      left when is_binary(left) -> "(#{left} - #{value})"
      _ -> nil
    end
  end

  defp int_arith_c(_, _, _, _), do: nil

  defp rem_c(builtin, left, right, instrs, item_c, visited) do
    left_c = reconstruct_int(left, instrs, item_c, visited)
    right_c = reconstruct_int(right, instrs, item_c, visited)

    if is_binary(left_c) and is_binary(right_c) do
      case builtin do
        :basics_mod_by -> "elmc_int_mod_by(#{left_c}, #{right_c})"
        :basics_remainder_by -> "(#{left_c} == 0 ? 0 : #{right_c} % #{left_c})"
      end
    end
  end

  defp compare_c(:eq, left, right), do: "(#{left} == #{right})"
  defp compare_c(:neq, left, right), do: "(#{left} != #{right})"
  defp compare_c(:gt, left, right), do: "(#{left} > #{right})"
  defp compare_c(:gte, left, right), do: "(#{left} >= #{right})"
  defp compare_c(:lt, left, right), do: "(#{left} < #{right})"
  defp compare_c(:lte, left, right), do: "(#{left} <= #{right})"
  defp compare_c(_, left, right), do: "(#{left} == #{right})"
end
