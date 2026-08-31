defmodule Elmc.Backend.Plan.ConstantFold do
  @moduledoc false
  alias Elmc.Backend.Plan.Types, as: Types


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

      # Basics.True/False are int_literal with union_ctor tags (often 1/2), not
      # numeric 0/1. Treating tag 2 as truthy made `not False` fold to false.
      %{op: :int_literal, union_ctor: ctor} when is_binary(ctor) ->
        bool_ctor_value(ctor)

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

  @doc """
  Rewrite `expr` under a known boolean polarity of `assumed_cond`.

  Nested `if`s whose condition is the same as (or the inverse of) the assumed
  compare are folded, so e.g. `if x /= 0 then (if x == 0 then "." else fromInt x)`
  drops the dead `"."` arm.
  """
  @spec under_assumption(term(), Types.ir_expr(), boolean(), Context.t()) :: term()
  def under_assumption(expr, assumed_cond, polarity, %Context{} = _ctx)
      when is_map(assumed_cond) do
    rewrite_under(expr, assumed_cond, polarity)
  end

  def under_assumption(expr, _assumed_cond, _polarity, _ctx), do: expr

  defp rewrite_under(%{op: :if} = expr, assumed, polarity) do
    {then_e, else_e} = if_arms(expr)
    then_e = rewrite_under(then_e, assumed, polarity)
    else_e = rewrite_under(else_e, assumed, polarity)

    case cond_relation(if_cond(expr), assumed) do
      :same -> if polarity, do: then_e, else: else_e
      :inverse -> if polarity, do: else_e, else: then_e
      :unknown -> put_if_arms(expr, then_e, else_e)
    end
  end

  defp rewrite_under(expr, assumed, polarity) when is_map(expr) do
    Map.new(expr, fn {k, v} -> {k, rewrite_under(v, assumed, polarity)} end)
  end

  defp rewrite_under(expr, assumed, polarity) when is_list(expr) do
    Enum.map(expr, &rewrite_under(&1, assumed, polarity))
  end

  defp rewrite_under(expr, _assumed, _polarity), do: expr

  defp if_cond(%{cond: cond}), do: cond

  defp if_arms(%{then_expr: then_e, else_expr: else_e}), do: {then_e, else_e}
  defp if_arms(%{then: then_e, else: else_e}), do: {then_e, else_e}
  defp if_arms(_), do: {nil, nil}

  defp put_if_arms(%{then_expr: _} = expr, then_e, else_e),
    do: %{expr | then_expr: then_e, else_expr: else_e}

  defp put_if_arms(%{then: _} = expr, then_e, else_e),
    do: %{expr | then: then_e, else: else_e}

  defp put_if_arms(expr, _then_e, _else_e), do: expr

  defp cond_relation(inner, assumed) do
    a = compare_form(inner)
    b = compare_form(assumed)

    cond do
      forms_same?(a, b) -> :same
      forms_inverse?(a, b) -> :inverse
      true -> :unknown
    end
  end

  defp compare_form(%{op: :compare, kind: kind, left: left, right: right}) do
    {:compare, normalize_compare_kind(kind), canon_operand(left), canon_operand(right)}
  end

  defp compare_form(%{op: :call, name: name, args: [left, right]})
       when name in @compare_ops or name in ["==", "/=", "!=", "eq", "neq"] do
    {:compare, op_to_kind(name), canon_operand(left), canon_operand(right)}
  end

  defp compare_form(%{op: :qualified_call, target: target, args: [left, right]})
       when is_binary(target) do
    case Host.qualified_builtin_operator_name(target) do
      op when op in @compare_ops ->
        {:compare, op_to_kind(op), canon_operand(left), canon_operand(right)}

      _ ->
        not_form(target, left, right)
    end
  end

  defp compare_form(%{op: :call, name: name, args: [arg]}) when name in ["not", "Basics.not"] do
    {:not, compare_form(arg)}
  end

  defp compare_form(%{op: :qualified_call, target: target, args: [arg]}) when is_binary(target) do
    if Host.normalize_special_target(target) in ["Basics.not", "not"] do
      {:not, compare_form(arg)}
    else
      {:opaque, canon_operand(%{op: :qualified_call, target: target, args: [arg]})}
    end
  end

  defp compare_form(%{op: :runtime_call, function: "elmc_basics_not", args: [arg]}) do
    {:not, compare_form(arg)}
  end

  defp compare_form(other), do: {:opaque, canon_operand(other)}

  defp not_form(target, left, right) do
    {:opaque, canon_operand(%{op: :qualified_call, target: target, args: [left, right]})}
  end

  defp normalize_compare_kind(kind) when kind in [:eq, "eq"], do: :eq
  defp normalize_compare_kind(kind) when kind in [:neq, "neq"], do: :neq
  defp normalize_compare_kind(kind) when kind in [:lt, "lt"], do: :lt
  defp normalize_compare_kind(kind) when kind in [:lte, "lte"], do: :lte
  defp normalize_compare_kind(kind) when kind in [:gt, "gt"], do: :gt
  defp normalize_compare_kind(kind) when kind in [:gte, "gte"], do: :gte
  defp normalize_compare_kind(kind), do: kind

  defp canon_operand(%{op: :field_access, field: field, arg: arg}),
    do: {:field, field, canon_operand(arg)}

  defp canon_operand(%{op: :var, name: name}) when is_binary(name), do: {:var, name}

  defp canon_operand(%{op: :int_literal, value: value}) when is_integer(value),
    do: {:int, value}

  defp canon_operand(other), do: other

  defp forms_same?({:not, a}, {:not, b}), do: forms_same?(a, b)

  defp forms_same?({:compare, kind, l, r}, {:compare, kind, l2, r2})
       when kind in [:eq, :neq] do
    eq_operands_match?(l, r, l2, r2)
  end

  defp forms_same?(a, b), do: a == b

  defp forms_inverse?({:not, a}, b), do: forms_same?(a, b)
  defp forms_inverse?(a, {:not, b}), do: forms_same?(a, b)

  defp forms_inverse?({:compare, :eq, l, r}, {:compare, :neq, l2, r2}),
    do: eq_operands_match?(l, r, l2, r2)

  defp forms_inverse?({:compare, :neq, l, r}, {:compare, :eq, l2, r2}),
    do: eq_operands_match?(l, r, l2, r2)

  defp forms_inverse?(_, _), do: false

  defp eq_operands_match?(l, r, l2, r2), do: (l == l2 and r == r2) or (l == r2 and r == l2)

  defp bool_ctor_value(ctor) when is_binary(ctor) do
    case ctor |> String.split(".") |> List.last() do
      "True" -> true
      "False" -> false
      _ -> :unknown
    end
  end

  @type fold_result :: boolean() | :unknown

  @spec fold_qualified_binary(String.t(), Types.expr(), Types.expr(), map()) :: fold_result()
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

  @spec fold_and(Types.expr(), Types.expr(), map()) :: fold_result()
  defp fold_and(left, right, env) do
    case {bool_value(left, env), bool_value(right, env)} do
      {false, _} -> false
      {_, false} -> false
      {true, true} -> true
      _ -> :unknown
    end
  end

  @spec fold_or(Types.expr(), Types.expr(), map()) :: fold_result()
  defp fold_or(left, right, env) do
    case {bool_value(left, env), bool_value(right, env)} do
      {true, _} -> true
      {_, true} -> true
      {false, false} -> false
      _ -> :unknown
    end
  end

  @spec fold_env(Context.t()) :: map()
  defp fold_env(%Context{module: mod, decl_map: decl_map}) do
    %{
      __module__: mod,
      __program_decls__: decl_map
    }
  end

  @spec compare_literal(atom(), Types.expr(), Types.expr(), map()) :: fold_result()
  defp compare_literal(kind, left, right, env) do
    with {:ok, left_value} <- ConstantInt.literal_value(left, env),
         {:ok, right_value} <- ConstantInt.literal_value(right, env) do
      apply_compare(kind, left_value, right_value)
    else
      _ -> :unknown
    end
  end

  @spec apply_compare(atom(), term(), term()) :: fold_result()
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

  @spec op_to_kind(String.t()) :: atom()
  defp op_to_kind("__eq__"), do: :eq
  defp op_to_kind("=="), do: :eq
  defp op_to_kind("eq"), do: :eq
  defp op_to_kind("__neq__"), do: :neq
  defp op_to_kind("/="), do: :neq
  defp op_to_kind("!="), do: :neq
  defp op_to_kind("neq"), do: :neq
  defp op_to_kind("__lt__"), do: :lt
  defp op_to_kind("__lte__"), do: :lte
  defp op_to_kind("__gt__"), do: :gt
  defp op_to_kind("__gte__"), do: :gte
end
