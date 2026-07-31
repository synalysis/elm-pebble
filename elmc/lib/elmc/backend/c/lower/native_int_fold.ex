defmodule Elmc.Backend.C.Lower.NativeIntFold do
  @moduledoc false
  alias Elmc.Types, as: Types


  alias Elmc.Backend.C.Lower.Function, as: CLowerFunction
  alias Elmc.Backend.C.Lower.Instr
  alias Elmc.Backend.Plan.Types
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

  @spec propagate_inlines(
          %{non_neg_integer() => String.t()},
          FunctionPlan.t(),
          keyword(),
          %{non_neg_integer() => non_neg_integer()},
          non_neg_integer() | nil
        ) :: %{non_neg_integer() => String.t()}

  defp propagate_inlines(inlines, plan, opts, uses, ret_reg) do
    native_int_only = Keyword.get(opts, :native_int_only_regs, MapSet.new())

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

    if next != inlines do
      propagate_inlines(next, plan, opts, uses, ret_reg)
    else
      inlines
    end
  end

  @spec inlineable_reg?(FunctionPlan.t(), non_neg_integer()) :: boolean()

  defp inlineable_reg?(%FunctionPlan{} = plan, reg) do
    case CLowerFunction.all_defining_instrs(plan, reg) do
      [_single] ->
        inlineable_single_def_reg?(plan, reg)

      _ ->
        false
    end
  end

  defp inlineable_single_def_reg?(%FunctionPlan{} = plan, reg) do
    case defining_instr(plan, reg) do
      %{op: :const_int} ->
        true

      %{op: :int_arith} = instr ->
        # Inlining rewrites the consumer to embed `elmc_as_int(owned[i])`, but the
        # skipped int_arith still releases its boxed operands immediately. That
        # frees the mul result in `key * 3 + 1` before tuple2 evaluates the
        # inlined add — EscapeDict map values became `0 + 1`. Only inline when
        # every register operand is itself a native/const chain.
        #
        # `effects.consumes` is empty for the common `*_vars` shapes (their
        # operands are borrowed via `elmc_as_int`, not consumed) — checking it
        # alone vacuously passes and lets a boxed call result (e.g. a tail
        # `let`-bound function call) get inlined into a deferred return
        # expression that is textually emitted *after* that operand's
        # `release`, reading it use-after-free. Check the actual lhs/rhs/value
        # register operands instead.
        Enum.all?(int_arith_operand_regs(instr), &native_int_chain_operand?(plan, &1))

      _ ->
        false
    end
  end

  @spec int_arith_operand_regs(map()) :: [integer()]

  defp int_arith_operand_regs(%{args: %{kind: kind, lhs: lhs, rhs: rhs}})
       when kind in [:add_vars, :mul_vars, :sub_vars, :idiv_vars, :mod_vars, :rem_vars, :min_vars, :max_vars] do
    [lhs, rhs] |> Enum.filter(&is_integer/1)
  end

  defp int_arith_operand_regs(%{args: %{kind: kind, lhs: lhs}})
       when kind in [:add_const, :sub_const] and is_integer(lhs) do
    [lhs]
  end

  defp int_arith_operand_regs(_), do: []

  @spec native_int_chain_operand?(FunctionPlan.t(), non_neg_integer()) :: boolean()

  defp native_int_chain_operand?(%FunctionPlan{} = plan, reg) when is_integer(reg) do
    case defining_instr(plan, reg) do
      %{op: :const_int} -> true
      %{op: :const_c_expr} -> true
      # Nested int_arith may itself be inlined; its operands were already checked
      # when deciding whether *that* reg was inlineable.
      %{op: :int_arith} -> true
      # Native/borrowed Int sources are safe to embed (`elmc_as_int(param)` /
      # `plan_native_int_*` / record int fields). EscapeDict only forbids
      # inlining through *boxed owned* regs that get released before the
      # inlined text runs.
      %{op: :load_param} -> true
      %{op: :record_get_int} -> true
      %{op: :boxed_tag_peel} -> true
      _ -> false
    end
  end

  defp native_int_chain_operand?(_, _), do: false

  @doc false
  @spec int_arith_c_expr(Types.instr_args(), Types.slot_map(), keyword()) :: String.t() | nil
  def int_arith_c_expr(args, slots, opts), do: int_arith_c_expr_dispatch(args, slots, opts)

  @spec inline_expr(FunctionPlan.t(), non_neg_integer(), %{non_neg_integer() => String.t()}, keyword()) ::
          String.t() | nil

  defp inline_expr(plan, reg, inlines, opts) do
    slots = Keyword.get(opts, :slots, %{})

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

  @spec int_arith_c_expr_dispatch(Types.instr_args(), Types.slot_map(), keyword()) :: String.t() | nil

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
    lhs_s = parenthesize_int_expr(Instr.int_operand_ref(lhs, slots, opts))
    rhs_s = parenthesize_int_expr(Instr.int_operand_ref(rhs, slots, opts))
    "#{lhs_s} * #{rhs_s}"
  end

  defp int_arith_c_expr_dispatch(%{kind: :sub_vars, lhs: lhs, rhs: rhs}, slots, opts) do
    lhs_s = parenthesize_int_expr(Instr.int_operand_ref(lhs, slots, opts))
    rhs_s = parenthesize_int_expr(Instr.int_operand_ref(rhs, slots, opts))
    "#{lhs_s} - #{rhs_s}"
  end

  defp int_arith_c_expr_dispatch(%{kind: :idiv_vars, lhs: lhs, rhs: rhs}, slots, opts) do
    lhs_s = parenthesize_int_expr(Instr.int_operand_ref(lhs, slots, opts))
    rhs_s = parenthesize_int_expr(Instr.int_operand_ref(rhs, slots, opts))
    Instr.idiv_c_expr(lhs_s, rhs_s)
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

  @doc false
  @spec parenthesize_int_expr(String.t()) :: String.t()
  def parenthesize_int_expr(expr) when is_binary(expr) do
    trimmed = String.trim(expr)

    if trimmed == "" or String.starts_with?(trimmed, "(") or String.starts_with?(trimmed, "elmc_int_idiv(") or
         String.starts_with?(trimmed, "elmc_basics_") or String.match?(trimmed, ~r/^-?\d+$/) or
         String.match?(trimmed, ~r/^plan_native_int_\d+$/) or String.match?(trimmed, ~r/^[a-zA-Z_][\w]*$/),
       do: trimmed,
       else: "(#{trimmed})"
  end

  @spec count_operand_uses(
          FunctionPlan.t(),
          MapSet.t(non_neg_integer()),
          MapSet.t(non_neg_integer())
        ) :: %{non_neg_integer() => non_neg_integer()}

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

    instr_uses =
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

    Enum.reduce(blocks, instr_uses, fn block, acc ->
      case Map.get(block, :terminator) do
        {:ret, reg} when is_integer(reg) ->
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

  @spec operand_regs(Types.t(), MapSet.t(non_neg_integer()), MapSet.t(non_neg_integer())) :: [non_neg_integer()]

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

  defp operand_regs(
         %{op: :call_runtime, args: %{builtin: builtin, args: args}},
         native_int_only,
         _
       )
       when builtin in [:record_new, :record_new_take, :record_new_values_ints] and is_list(args) do
    Enum.filter(args, &MapSet.member?(native_int_only, &1))
  end

  # Tuple / boxing consumers of a single native-int arith result must count as
  # uses so `key * 3 + 1` can inline into the add (and then into the box/tuple).
  defp operand_regs(
         %{op: :call_runtime, args: %{builtin: builtin, args: args}},
         native_int_only,
         _
       )
       when builtin in [:tuple2, :tuple2_take, :new_int, :tuple2_ints, :tuple2_ints_take] and is_list(args) do
    Enum.filter(args, &MapSet.member?(native_int_only, &1))
  end

  defp operand_regs(_, _, _), do: []

  @spec maybe_reg([non_neg_integer()], Types.instr_args(), atom(), MapSet.t(non_neg_integer())) :: [
          non_neg_integer()
        ]

  defp maybe_reg(regs, args, key, native_set) do
    case Map.get(args, key) do
      reg when is_integer(reg) ->
        if MapSet.member?(native_set, reg), do: [reg | regs], else: regs

      _ ->
        regs
    end
  end

  @spec defining_instr(FunctionPlan.t(), non_neg_integer()) :: Types.t() | nil

  defp defining_instr(%FunctionPlan{blocks: blocks}, reg) do
    Enum.find_value(blocks, fn %{instrs: instrs} ->
      Enum.find(instrs, &match?(%{dest: ^reg}, &1))
    end)
  end
end
