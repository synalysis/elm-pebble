defmodule Elmc.Backend.CCodegen.IntIfChain do
  @moduledoc false

  alias Elmc.Backend.CCodegen.EnvBindings
  alias Elmc.Backend.CCodegen.Native.Int, as: NativeInt
  alias Elmc.Backend.CCodegen.Native.IntCase, as: NativeIntCase
  alias Elmc.Backend.CCodegen.Types

  @min_branches 3

  @spec parse_or_equality_if_chain(
          Types.ir_expr(),
          Types.ir_expr(),
          Types.ir_expr(),
          Types.compile_env()
        ) :: {:ok, Types.ir_expr(), Types.int_case_branches()} | :error
  def parse_or_equality_if_chain(cond_expr, then_expr, else_expr, env) do
    with {:ok, subject, values} <- collect_or_equalities(cond_expr, env, []),
         true <- then_returns_subject?(then_expr, subject),
         true <- NativeInt.expr?(then_expr, env),
         true <- NativeInt.expr?(else_expr, env) do
      branches =
        Enum.map(values, fn value ->
          %{pattern: %{kind: :int, value: value}, expr: then_expr}
        end) ++ [%{pattern: %{kind: :wildcard}, expr: else_expr}]

      if switch_eligible?(subject, branches, env) do
        {:ok, subject, branches}
      else
        :error
      end
    else
      _ -> :error
    end
  end

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

  # `if x == 10 || x == 30 || x == 60 then x else 5` lowers to nested bool ifs:
  # if (x == 10) then True else if (x == 30) then True else (x == 60)
  defp collect_or_equalities(
         %{op: :if, cond: cond, then_expr: then_expr, else_expr: else_expr},
         env,
         acc
       ) do
    with {:ok, subject, value} <- int_equality(cond, env),
         true <- acc == [] or same_subjects?(acc, subject),
         true <- bool_true?(then_expr) do
      collect_or_equalities(else_expr, env, [{subject, value} | acc])
    else
      _ -> :error
    end
  end

  defp collect_or_equalities(cond_expr, env, acc) when acc != [] do
    with {:ok, subject, value} <- int_equality(cond_expr, env),
         true <- same_subjects?(acc, subject) do
      values = Enum.reverse([value | Enum.map(acc, fn {_, v} -> v end)])
      {:ok, subject, values}
    else
      _ -> :error
    end
  end

  defp collect_or_equalities(_cond_expr, _env, _acc), do: :error

  defp bool_true?(%{op: :bool_literal, value: true}), do: true
  defp bool_true?(%{op: :int_literal, value: 1}), do: true

  defp bool_true?(%{op: :constructor_call, target: target, args: args}) when args in [nil, []] do
    target == "True" or String.ends_with?(target, ".True")
  end

  defp bool_true?(_expr), do: false

  defp then_returns_subject?(then_expr, subject), do: same_subject?(then_expr, subject)

  defp same_subjects?(acc, subject) do
    Enum.all?(acc, fn {entry_subject, _} -> same_subject?(entry_subject, subject) end)
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

  defp subject_expr(expr, env) do
    if NativeInt.expr?(expr, env), do: expr, else: nil
  end

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
