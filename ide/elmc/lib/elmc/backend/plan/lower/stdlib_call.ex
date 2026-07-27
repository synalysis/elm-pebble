defmodule Elmc.Backend.Plan.Lower.StdlibCall do
  @moduledoc false
  alias Elmc.Backend.Plan.Types, as: Types


  alias Elmc.Backend.Plan.Types
  alias Elmc.Backend.Plan.Lower.Expr
  alias Elmc.Backend.Plan.Lower.Types, as: LowerTypes
  alias Elmc.Backend.Plan.{Builder, Context}

  @spec compile_maybe_with_default(Types.case_branches(), Context.t(), Builder.t()) ::
          LowerTypes.compile_result() | :unsupported
  def compile_maybe_with_default([default_val, second], ctx, b) do
    case list_at_index_list(second) do
      {:ok, index, list} ->
        with {:ok, index_reg, b1} <- Expr.compile(index, ctx, b),
             {:ok, list_reg, b2} <- Expr.compile(list, ctx, b1),
             {:ok, default_reg, b3} <- Expr.compile(default_val, ctx, b2) do
          if int_literal_zero?(default_val) do
            Expr.compile_runtime_builtin(
              :list_nth_int_default,
              [list_reg, index_reg, default_reg],
              ctx,
              b3
            )
          else
            with {:ok, maybe_reg, b4} <-
                   Expr.compile_runtime_builtin(:list_nth_maybe, [list_reg, index_reg], ctx, b3) do
              compile_with_default(default_val, default_reg, maybe_reg, ctx, b4)
            end
          end
        else
          _ -> :unsupported
        end

      :error ->
        with {:ok, [default_reg, maybe_reg], b1} <-
               Expr.compile_args([default_val, second], ctx, b) do
          compile_with_default(default_val, default_reg, maybe_reg, ctx, b1)
        end
    end
  end

  def compile_maybe_with_default(_, _, _), do: :unsupported

  @spec compile_with_default(Types.ir_expr(), Types.ir_expr(), Types.ir_expr(), Types.ir_expr(), Types.ir_expr()) :: Types.ir_expr()

  defp compile_with_default(default_val, default_reg, maybe_reg, ctx, b) do
    builtin =
      if int_literal_default?(default_val),
        do: :maybe_with_default_int,
        else: :maybe_with_default

    Expr.compile_runtime_builtin(builtin, [default_reg, maybe_reg], ctx, b)
  end

  @spec list_at_index_list(map() | term()) :: Types.ir_expr()

  defp list_at_index_list(%{
         op: :qualified_call,
         target: target,
         args: [index, list]
       })
       when is_binary(target) do
    if String.ends_with?(target, ".listAt") or target == "listAt" do
      {:ok, index, list}
    else
      :error
    end
  end

  defp list_at_index_list(%{
         op: :runtime_call,
         function: "elmc_list_nth_maybe",
         args: [list, index]
       }) do
    {:ok, index, list}
  end

  defp list_at_index_list(_), do: :error

  @spec int_literal_zero?(map() | term()) :: boolean()

  defp int_literal_zero?(%{op: :int_literal, value: 0} = lit),
    do: int_literal_default?(lit)

  defp int_literal_zero?(_), do: false

  # Plain int defaults (not union tag literals such as `Nothing`).
  @spec int_literal_default?(map() | term()) :: boolean()

  defp int_literal_default?(%{op: :int_literal, value: value} = lit) when is_integer(value) do
    not Map.has_key?(lit, :union_ctor)
  end

  defp int_literal_default?(_), do: false
end
