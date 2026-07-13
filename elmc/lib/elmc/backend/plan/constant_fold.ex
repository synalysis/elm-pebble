defmodule Elmc.Backend.Plan.ConstantFold do
  @moduledoc false

  alias Elmc.Backend.CCodegen.{ConstantInt, Host}
  alias Elmc.Backend.Plan.{Context, Types}

  @compare_ops ~w(__eq__ __neq__ __lt__ __lte__ __gt__ __gte__)
  @and_targets ~w(Basics.and && and)
  @or_targets ~w(Basics.or || or)

  @spec bool_value(Types.ir_expr(), Context.t() | Types.compile_env()) :: :unknown | boolean()
  def bool_value(expr, %Context{} = ctx), do: bool_value(expr, fold_env(ctx))

  def bool_value(expr, env) when is_map(env) do
    case expr do
      %{op: :bool_literal, value: value} ->
        value

      %{op: :int_literal, value: value} when is_integer(value) ->
        value != 0

      %{op: :compare, kind: kind, left: left, right: right} ->
        compare_literal(kind, left, right, env)

      %{op: :call, name: name, args: [left, right]} when name in @compare_ops ->
        compare_literal(op_to_kind(name), left, right, env)

      %{op: :qualified_call, target: target, args: [left, right]} ->
        fold_qualified_binary(target, left, right, env)

      %{op: :call, name: name, args: [arg]} when name in ["not", "Basics.not"] ->
        case bool_value(arg, env) do
          :unknown -> :unknown
          value -> not value
        end

      %{op: :qualified_call, target: target, args: [arg]} ->
        if Host.normalize_special_target(target) in ["Basics.not", "not"] do
          bool_value(%{op: :call, name: "not", args: [arg]}, env)
        else
          :unknown
        end

      %{op: :if, cond: cond, then_expr: then_expr, else_expr: else_expr} ->
        case bool_value(cond, env) do
          :unknown -> :unknown
          true -> bool_value(then_expr, env)
          false -> bool_value(else_expr, env)
        end

      %{op: :if, cond: cond, then: then_expr, else: else_expr} ->
        bool_value(%{op: :if, cond: cond, then_expr: then_expr, else_expr: else_expr}, env)

      %{op: :call, name: name, args: [left, right]}
      when name in ["&&", "Basics.and", "and"] ->
        fold_and(left, right, env)

      %{op: :call, name: name, args: [left, right]}
      when name in ["||", "Basics.or", "or"] ->
        fold_or(left, right, env)

      _ ->
        :unknown
    end
  end

  defp fold_qualified_binary(target, left, right, env) do
    case Host.qualified_builtin_operator_name(target) do
      op when op in @compare_ops ->
        compare_literal(op_to_kind(op), left, right, env)

      _ ->
        normalized = Host.normalize_special_target(target)

        cond do
          normalized in @and_targets -> fold_and(left, right, env)
          normalized in @or_targets -> fold_or(left, right, env)
          true -> :unknown
        end
    end
  end

  defp fold_and(left, right, env) do
    case {bool_value(left, env), bool_value(right, env)} do
      {false, _} -> false
      {_, false} -> false
      {true, true} -> true
      _ -> :unknown
    end
  end

  defp fold_or(left, right, env) do
    case {bool_value(left, env), bool_value(right, env)} do
      {true, _} -> true
      {_, true} -> true
      {false, false} -> false
      _ -> :unknown
    end
  end

  defp fold_env(%Context{module: mod, decl_map: decl_map}) do
    %{
      __module__: mod,
      __program_decls__: decl_map
    }
  end

  defp compare_literal(kind, left, right, env) do
    with {:ok, left_value} <- ConstantInt.literal_value(left, env),
         {:ok, right_value} <- ConstantInt.literal_value(right, env) do
      apply_compare(kind, left_value, right_value)
    else
      _ -> :unknown
    end
  end

  defp apply_compare(kind, left, right) do
    case kind do
      :eq -> left == right
      :neq -> left != right
      :lt -> left < right
      :lte -> left <= right
      :gt -> left > right
      :gte -> left >= right
      _ -> :unknown
    end
  end

  defp op_to_kind("__eq__"), do: :eq
  defp op_to_kind("__neq__"), do: :neq
  defp op_to_kind("__lt__"), do: :lt
  defp op_to_kind("__lte__"), do: :lte
  defp op_to_kind("__gt__"), do: :gt
  defp op_to_kind("__gte__"), do: :gte
end
