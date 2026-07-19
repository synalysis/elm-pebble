defmodule Elmc.Backend.Plan.Lower.PlatformStatic do
  @moduledoc false

  alias Elmc.Backend.Plan.{Builder, Context}
  alias Elmc.Backend.Plan.Types

  @spec compile_case(Types.ir_case_expr(), String.t(), Context.t(), Builder.t()) ::
          Types.compile_result()
  def compile_case(%{branches: branches}, macro, ctx, b)
      when is_binary(macro) and is_list(branches) do
    with {:ok, then_val, else_val} <- static_branch_values(branches),
         {:ok, reg, b1} <- emit_static_int(macro, then_val, else_val, ctx, b) do
      {:ok, reg, b1}
    else
      _ -> :unsupported
    end
  end

  def compile_case(_, _, _, _), do: :unsupported

  defp static_branch_values([
         %{pattern: %{kind: :constructor}, expr: %{op: :int_literal, value: then_val}},
         %{pattern: %{kind: :wildcard}, expr: %{op: :int_literal, value: else_val}}
       ])
       when is_integer(then_val) and is_integer(else_val),
       do: {:ok, then_val, else_val}

  defp static_branch_values(_), do: :error

  defp emit_static_int(macro, then_val, else_val, ctx, b) do
    wrap_catch? = Builder.wrap_fallible_instr_catch?(b, ctx, true)
    b1 = if wrap_catch?, do: Builder.catch_begin(b), else: b

    {dest, b_dest} =
      if Context.function_tail?(ctx) do
        {:fn_out, b1}
      else
        Builder.fresh_reg(b1)
      end

    effects =
      if is_integer(dest) do
        Types.fallible_effects(dest)
      else
        %{produces: nil, consumes: [], borrows: [], fallible: true}
      end

    {_, b2} =
      Builder.emit(b_dest, :platform_static_int, %{
        dest: dest,
        args: %{macro: macro, then: then_val, else: else_val},
        effects: effects
      })

    b3 = if wrap_catch?, do: Builder.catch_end(b2), else: b2

    if dest == :fn_out do
      {_, b4} =
        Builder.emit(b3, :publish, %{
          dest: :fn_out,
          args: %{},
          effects: Types.empty_effects()
        })

      {:ok, :fn_out, b4}
    else
      {:ok, dest, b3}
    end
  end
end
