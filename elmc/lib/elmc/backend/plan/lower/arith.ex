defmodule Elmc.Backend.Plan.Lower.Arith do
  @moduledoc false

  alias Elmc.Backend.Plan.{Builder, Context}
  alias Elmc.Backend.Plan.Lower.Expr
  alias Elmc.Backend.Plan.Types

  @spec compile(Types.ir_expr(), Context.t(), Builder.t()) :: Types.compile_result_required()
  def compile(%{op: :add_const, var: name, value: value}, ctx, b) when is_binary(name) and is_integer(value) do
    with {:ok, lhs, b1} <- Expr.compile(%{op: :var, name: name}, ctx, b) do
      emit_int_arith(:add_const, lhs, value, ctx, b1)
    else
      _ -> :unsupported
    end
  end

  def compile(%{op: :sub_const, var: name, value: value}, ctx, b) when is_binary(name) and is_integer(value) do
    with {:ok, lhs, b1} <- Expr.compile(%{op: :var, name: name}, ctx, b) do
      emit_int_arith(:sub_const, lhs, value, ctx, b1)
    else
      _ -> :unsupported
    end
  end

  def compile(%{op: :add_vars, left: left, right: right}, ctx, b)
      when is_binary(left) and is_binary(right) do
    with {:ok, l, b1} <- Expr.compile(%{op: :var, name: left}, ctx, b),
         {:ok, r, b2} <- Expr.compile(%{op: :var, name: right}, ctx, b1) do
      emit_int_arith(:add_vars, l, r, ctx, b2)
    else
      _ -> :unsupported
    end
  end

  def compile(_, _, _), do: :unsupported

  @spec emit_binary(atom(), Types.ir_expr(), Types.ir_expr(), Context.t(), Builder.t()) ::
          {:ok, Types.reg() | :fn_out, Builder.t()} | :unsupported
  def emit_binary(kind, left, right, ctx, b)
      when kind in [:add_vars, :mul_vars, :sub_vars, :idiv_vars, :mod_vars, :rem_vars, :min_vars, :max_vars] do
    with {:ok, l, b1} <- Expr.compile(left, ctx, b),
         {:ok, r, b2} <- Expr.compile(right, ctx, b1) do
      emit_int_arith(kind, l, r, ctx, b2)
    else
      _ -> :unsupported
    end
  end

  @binop_atoms %{add_vars: :add, sub_vars: :sub, mul_vars: :mul, fdiv_vars: :fdiv}

  @spec emit_boxed_binop(atom(), Types.ir_expr(), Types.ir_expr(), Context.t(), Builder.t()) ::
          {:ok, Types.reg() | :fn_out, Builder.t()} | :unsupported
  def emit_boxed_binop(kind, left, right, ctx, b) when kind in [:add, :sub, :mul, :idiv, :fdiv] do
    with {:ok, l, b1} <- Expr.compile(left, ctx, b),
         {:ok, r, b2} <- Expr.compile(right, ctx, b1) do
      {dest, b3} = dest_for(ctx, b2)
      operands = [l, r]
      {borrows, consumes} = Builder.partition_call_args(b3, operands)

      wrap_catch? = Builder.wrap_fallible_instr_catch?(b3, ctx, true)

      b4 = if wrap_catch?, do: Builder.catch_begin(b3), else: b3

      effects =
        if is_integer(dest) do
          Types.fallible_effects(dest, borrows, consumes)
        else
          %{produces: nil, consumes: consumes, borrows: borrows, fallible: true}
        end

      {_, b5} =
        Builder.emit(b4, :boxed_binop, %{
          dest: dest,
          args: %{op: kind, lhs: l, rhs: r},
          effects: effects
        })

      b6 = if wrap_catch?, do: Builder.catch_end(b5), else: b5
      {:ok, dest, b6}
    else
      _ -> :unsupported
    end
  end

  def emit_boxed_binop_from_vars(kind, left, right, ctx, b)
      when kind in [:add_vars, :sub_vars, :mul_vars, :fdiv_vars] do
    emit_boxed_binop(Map.fetch!(@binop_atoms, kind), left, right, ctx, b)
  end

  @doc false
  def emit_int_arith_regs(kind, lhs, rhs, ctx, b)
      when kind in [:add_vars, :mul_vars, :sub_vars, :idiv_vars, :mod_vars, :rem_vars, :min_vars, :max_vars] do
    emit_int_arith(kind, lhs, rhs, ctx, b)
  end

  defp emit_int_arith(kind, lhs, rhs, ctx, b)
       when kind in [:add_vars, :mul_vars, :sub_vars, :idiv_vars, :mod_vars, :rem_vars, :min_vars, :max_vars] do
    {dest, b1} = dest_for(ctx, b)
    operands = [lhs, rhs]
    {borrows, consumes} = Builder.partition_call_args(b1, operands)

    wrap_catch? = Builder.wrap_fallible_instr_catch?(b1, ctx, true)

    b2 = if wrap_catch?, do: Builder.catch_begin(b1), else: b1

    effects =
      if is_integer(dest) do
        Types.fallible_effects(dest, borrows, consumes)
      else
        %{produces: nil, consumes: consumes, borrows: borrows, fallible: true}
      end

    {_, b3} =
      Builder.emit(b2, :int_arith, %{
        dest: dest,
        args: %{kind: kind, lhs: lhs, rhs: rhs},
        effects: effects
      })

    b4 = if wrap_catch?, do: Builder.catch_end(b3), else: b3
    {:ok, dest, b4}
  end

  defp emit_int_arith(kind, lhs, rhs, ctx, b) when kind in [:add_const, :sub_const] do
    {dest, b1} = dest_for(ctx, b)
    {borrows, consumes} = Builder.partition_call_args(b1, [lhs])

    wrap_catch? = Builder.wrap_fallible_instr_catch?(b1, ctx, true)

    b2 = if wrap_catch?, do: Builder.catch_begin(b1), else: b1

    effects =
      if is_integer(dest) do
        Types.fallible_effects(dest, borrows, consumes)
      else
        %{produces: nil, consumes: consumes, borrows: borrows, fallible: true}
      end

    {_, b3} =
      Builder.emit(b2, :int_arith, %{
        dest: dest,
        args: %{kind: kind, lhs: lhs, value: rhs},
        effects: effects
      })

    b4 = if wrap_catch?, do: Builder.catch_end(b3), else: b3
    {:ok, dest, b4}
  end

  defp dest_for(ctx, b) do
    case Context.dest_for_call(ctx) do
      :branch_out -> {:branch_out, b}
      _ -> Builder.fresh_reg(b)
    end
  end
end
