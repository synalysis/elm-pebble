defmodule Elmc.Backend.CCodegen.VarAnalysis do
  @moduledoc false

  alias Elmc.Backend.CCodegen.Types

  @spec used_vars(Types.ir_expr() | nil) :: Types.var_name_set()
  def used_vars(nil), do: MapSet.new()

  def used_vars(%{op: :var, name: name}), do: MapSet.new([name])
  def used_vars(%{op: :float_literal}), do: MapSet.new()
  def used_vars(%{op: :field_access, arg: arg}) when is_binary(arg), do: MapSet.new([arg])
  def used_vars(%{op: :field_access, arg: arg}) when is_map(arg), do: used_vars(arg)
  def used_vars(%{op: :compose_left, f: f, g: g}), do: compose_used_vars(f, g)
  def used_vars(%{op: :compose_right, f: f, g: g}), do: compose_used_vars(f, g)
  def used_vars(%{op: :add_const, var: name}), do: MapSet.new([name])
  def used_vars(%{op: :sub_const, var: name}), do: MapSet.new([name])
  def used_vars(%{op: :add_vars, left: left, right: right}), do: MapSet.new([left, right])
  def used_vars(%{op: :tuple_second, arg: arg}), do: MapSet.new([arg])
  def used_vars(%{op: :tuple_first, arg: arg}), do: MapSet.new([arg])
  def used_vars(%{op: :string_length, arg: arg}), do: MapSet.new([arg])
  def used_vars(%{op: :char_from_code, arg: arg}), do: MapSet.new([arg])
  def used_vars(%{op: :tuple_second_expr, arg: arg}), do: used_vars(arg)
  def used_vars(%{op: :tuple_first_expr, arg: arg}), do: used_vars(arg)
  def used_vars(%{op: :string_length_expr, arg: arg}), do: used_vars(arg)
  def used_vars(%{op: :char_from_code_expr, arg: arg}), do: used_vars(arg)

  def used_vars(%{op: :runtime_call, args: args}) do
    Enum.reduce(args, MapSet.new(), fn arg, acc -> MapSet.union(acc, used_vars(arg)) end)
  end

  def used_vars(%{op: :qualified_call, args: args}) do
    Enum.reduce(args, MapSet.new(), fn arg, acc -> MapSet.union(acc, used_vars(arg)) end)
  end

  def used_vars(%{op: :constructor_call, args: args}) do
    Enum.reduce(args, MapSet.new(), fn arg, acc -> MapSet.union(acc, used_vars(arg)) end)
  end

  def used_vars(%{op: :list_literal, items: items}) do
    Enum.reduce(items, MapSet.new(), fn item, acc -> MapSet.union(acc, used_vars(item)) end)
  end

  def used_vars(%{op: :call, name: name, args: args}) when is_binary(name) do
    Enum.reduce(args, MapSet.new([name]), fn arg, acc ->
      MapSet.union(acc, used_vars(arg))
    end)
  end

  def used_vars(%{op: :call, args: args}) do
    Enum.reduce(args, MapSet.new(), fn arg, acc -> MapSet.union(acc, used_vars(arg)) end)
  end

  def used_vars(%{op: :field_call, arg: arg, args: args}) do
    Enum.reduce(args, field_arg_vars(arg), fn arg, acc -> MapSet.union(acc, used_vars(arg)) end)
  end

  def used_vars(%{op: :lambda, body: body}) do
    used_vars(body)
  end

  def used_vars(%{op: :record_literal, fields: fields}) do
    Enum.reduce(fields, MapSet.new(), fn
      %{expr: expr}, acc -> MapSet.union(acc, used_vars(expr))
      _other, acc -> acc
    end)
  end

  def used_vars(%{op: :record_update, base: base, fields: fields}) do
    Enum.reduce(fields, used_vars(base), fn
      %{expr: expr}, acc -> MapSet.union(acc, used_vars(expr))
      _other, acc -> acc
    end)
  end

  def used_vars(%{op: :let_in, value_expr: value_expr, in_expr: in_expr}) do
    MapSet.union(used_vars(value_expr), used_vars(in_expr))
  end

  def used_vars(%{op: :if, cond: cond_expr, then_expr: then_expr, else_expr: else_expr}) do
    used_vars(cond_expr)
    |> MapSet.union(used_vars(then_expr))
    |> MapSet.union(used_vars(else_expr))
  end

  def used_vars(%{op: :compare, left: left, right: right}) do
    MapSet.union(used_vars(left), used_vars(right))
  end

  def used_vars(%{op: :tuple2, left: left, right: right}) do
    MapSet.union(used_vars(left), used_vars(right))
  end

  def used_vars(%{op: :case, subject: subject, branches: branches}) do
    branch_vars =
      branches
      |> Enum.map(&used_vars(&1.expr))
      |> Enum.reduce(MapSet.new(), &MapSet.union/2)

    MapSet.put(branch_vars, subject)
  end

  def used_vars(%{op: op, params: params})
      when op in [:bytes_cmd, :html_cmd, :dom_sub, :browser_cmd, :json_cmd] and is_list(params) do
    Enum.reduce(params, MapSet.new(), fn param, acc ->
      MapSet.union(acc, used_vars(param))
    end)
  end

  def used_vars(_), do: MapSet.new()

  @spec field_arg_vars(Types.ir_expr() | String.t()) :: Types.var_name_set()
  defp field_arg_vars(arg) when is_binary(arg), do: MapSet.new([arg])
  defp field_arg_vars(arg) when is_map(arg), do: used_vars(arg)
  defp field_arg_vars(_arg), do: MapSet.new()

  @spec compose_used_vars(Types.ir_expr() | String.t(), Types.ir_expr() | String.t()) ::
          Types.var_name_set()
  defp compose_used_vars(f, g) do
    MapSet.union(compose_side_vars(f), compose_side_vars(g))
  end

  @spec compose_side_vars(Types.ir_expr() | String.t()) :: Types.var_name_set()
  defp compose_side_vars(name) when is_binary(name), do: MapSet.new([name])
  defp compose_side_vars(expr) when is_map(expr), do: used_vars(expr)
  defp compose_side_vars(_), do: MapSet.new()
end
