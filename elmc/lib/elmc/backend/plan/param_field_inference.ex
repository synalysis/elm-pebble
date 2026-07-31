defmodule Elmc.Backend.Plan.ParamFieldInference do
  @moduledoc false
  alias Elmc.Backend.Plan.Types, as: Types

  @spec infer(map() | struct()) :: %{String.t() => [String.t()]}
  def infer(%{expr: expr, args: args}) when is_map(expr) and is_list(args) do
    infer_names(expr, args)
  end

  def infer(_), do: %{}

  @doc """
  Collect field accesses for any set of local/param names (let bindings, lambda
  args, etc.). Used so `let result = List.foldl … in result.sum` resolves `sum`
  against the inferred record shape instead of falling back to index 0.
  """
  @spec infer_names(Types.expr(), [String.t()]) :: %{String.t() => [String.t()]}
  def infer_names(expr, names) when is_map(expr) and is_list(names) do
    params = MapSet.new(names)

    expr
    |> collect_field_accesses(params, %{})
    |> Map.take(names)
  end

  def infer_names(_, _), do: %{}

  @spec collect_field_accesses(Types.expr(), MapSet.t(String.t()), %{String.t() => [String.t()]}) ::
          %{String.t() => [String.t()]}
  defp collect_field_accesses(expr, params, acc) do
    case expr do
      %{op: :field_access, arg: param, field: field}
      when is_binary(param) and is_binary(field) ->
        if MapSet.member?(params, param) do
          append_field(acc, param, field)
        else
          acc
        end

      %{op: :field_access, arg: %{op: :var, name: param}, field: field}
      when is_binary(param) and is_binary(field) ->
        if MapSet.member?(params, param) do
          append_field(acc, param, field)
        else
          acc
        end

      %{op: :let, bindings: bindings, body: body} when is_list(bindings) ->
        acc =
          Enum.reduce(bindings, acc, fn binding, bacc ->
            collect_field_accesses(
              Map.get(binding, :value) || Map.get(binding, :expr),
              params,
              bacc
            )
          end)

        collect_field_accesses(body, params, acc)

      %{op: :let_in, name: _name, value_expr: value_expr, in_expr: in_expr} ->
        acc
        |> then(&collect_field_accesses(value_expr, params, &1))
        |> then(&collect_field_accesses(in_expr, params, &1))

      %{op: :case, subject: subject, arms: arms} ->
        acc = collect_field_accesses(subject, params, acc)

        Enum.reduce(arms || [], acc, fn arm, aacc ->
          arm_expr = Map.get(arm, :expr) || Map.get(arm, :body)
          collect_field_accesses(arm_expr, params, aacc)
        end)

      %{op: :case, subject: subject, branches: branches} ->
        acc = collect_field_accesses(subject, params, acc)

        Enum.reduce(branches || [], acc, fn arm, aacc ->
          collect_field_accesses(Map.get(arm, :expr), params, aacc)
        end)

      %{op: :if, condition: condition, then: then_expr, else: else_expr} ->
        acc
        |> then(&collect_field_accesses(condition, params, &1))
        |> then(&collect_field_accesses(then_expr, params, &1))
        |> then(&collect_field_accesses(else_expr, params, &1))

      %{op: :record_literal, fields: fields} when is_list(fields) ->
        Enum.reduce(fields, acc, fn field, facc ->
          collect_field_accesses(Map.get(field, :expr) || Map.get(field, :value), params, facc)
        end)

      %{op: :tuple2, left: left, right: right} ->
        acc
        |> then(&collect_field_accesses(left, params, &1))
        |> then(&collect_field_accesses(right, params, &1))

      %{op: :call, args: args} when is_list(args) ->
        Enum.reduce(args, acc, &collect_field_accesses(&1, params, &2))

      %{op: :qualified_call, args: args} when is_list(args) ->
        Enum.reduce(args, acc, &collect_field_accesses(&1, params, &2))

      list when is_list(list) ->
        Enum.reduce(list, acc, &collect_field_accesses(&1, params, &2))

      map when is_map(map) ->
        map
        |> Map.values()
        |> Enum.reduce(acc, &collect_field_accesses(&1, params, &2))

      _ ->
        acc
    end
  end

  @spec append_field(%{String.t() => [String.t()]}, String.t(), String.t()) ::
          %{String.t() => [String.t()]}
  defp append_field(acc, param, field) when is_binary(param) and is_binary(field) do
    fields = Map.get(acc, param, [])

    if field in fields do
      acc
    else
      Map.put(acc, param, fields ++ [field])
    end
  end
end
