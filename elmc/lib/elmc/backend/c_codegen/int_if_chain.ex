defmodule Elmc.Backend.CCodegen.IntIfChain do
  @moduledoc false

  alias Elmc.Backend.CCodegen.EnvBindings
  alias Elmc.Backend.CCodegen.Native.Int, as: NativeInt
  alias Elmc.Backend.CCodegen.Native.IntCase, as: NativeIntCase
  alias Elmc.Backend.CCodegen.Types

  @min_branches 3

  @spec parse_if_chain(
          Types.ir_expr(),
          Types.ir_expr(),
          Types.ir_expr(),
          Types.compile_env()
        ) :: {:ok, Types.ir_expr(), Types.int_case_branches()} | :error
  def parse_if_chain(cond_expr, then_expr, else_expr, env) do
    with {:ok, subject, first_value} <- int_equality(cond_expr, env),
         {:ok, ^subject, tail_branches} <- parse_else_chain(else_expr, subject, env) do
      branches =
        [%{pattern: %{kind: :int, value: first_value}, expr: then_expr} | tail_branches]

      if switch_eligible?(subject, branches, env) do
        {:ok, subject, branches}
      else
        :error
      end
    else
      _ -> :error
    end
  end

  defp switch_eligible?(subject, branches, env) do
    NativeInt.expr?(subject, env) and
      NativeIntCase.branches?(branches) and
      int_branch_count(branches) >= @min_branches
  end

  defp int_branch_count(branches) do
    Enum.count(branches, fn %{pattern: pattern} ->
      match?(%{kind: :int, value: value} when is_integer(value), pattern)
    end)
  end

  defp parse_else_chain(%{op: :if, cond: cond, then_expr: then_expr, else_expr: else_expr}, subject, env) do
    with {:ok, branch_subject, value} <- int_equality(cond, env),
         true <- same_subject?(subject, branch_subject),
         {:ok, ^subject, tail} <- parse_else_chain(else_expr, subject, env) do
      {:ok, subject, [%{pattern: %{kind: :int, value: value}, expr: then_expr} | tail]}
    else
      _ -> :error
    end
  end

  defp parse_else_chain(else_expr, subject, _env) do
    {:ok, subject, [%{pattern: %{kind: :wildcard}, expr: else_expr}]}
  end

  defp int_equality(cond_expr, env) do
    case cond_expr do
      %{op: :compare, kind: :eq, left: left, right: right} ->
        int_equality_pair(left, right, env)

      %{op: :call, name: "__eq__", args: [left, right]} ->
        int_equality_pair(left, right, env)

      _ ->
        :error
    end
  end

  defp int_equality_pair(left, right, env) do
    with subject when not is_nil(subject) <- subject_expr(left, env),
         value when is_integer(value) <- int_literal(right) do
      {:ok, subject, value}
    else
      _ ->
        with subject when not is_nil(subject) <- subject_expr(right, env),
             value when is_integer(value) <- int_literal(left) do
          {:ok, subject, value}
        else
          _ -> :error
        end
    end
  end

  defp subject_expr(%{op: :var, name: name}, env) when is_binary(name) or is_atom(name) do
    expr = %{op: :var, name: name}

    if NativeInt.expr?(expr, env) do
      expr
    else
      nil
    end
  end

  defp subject_expr(_expr, _env), do: nil

  defp int_literal(%{op: :int_literal, value: value}) when is_integer(value), do: value
  defp int_literal(_expr), do: nil

  defp same_subject?(
         %{op: :var, name: left},
         %{op: :var, name: right}
       ) do
    EnvBindings.binding_key(left) == EnvBindings.binding_key(right)
  end

  defp same_subject?(left, right), do: left == right
end
