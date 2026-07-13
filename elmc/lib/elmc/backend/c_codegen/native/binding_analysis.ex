defmodule Elmc.Backend.CCodegen.Native.BindingAnalysis do
  @moduledoc false

  alias Elmc.Backend.CCodegen.EnvBindings
  alias Elmc.Backend.CCodegen.Types

  @spec used_in_lambda?(Types.binding_name(), Types.ir_expr()) :: boolean()
  def used_in_lambda?(name, expr), do: used_in_lambda_node?(name, expr)

  @spec reference_count(Types.binding_name(), Types.ir_expr()) :: non_neg_integer()
  def reference_count(name, expr), do: reference_count_node(name, expr)

  @spec pebble_angle_expr?(Types.ir_expr()) :: boolean()
  def pebble_angle_expr?(%{
        op: :call,
        name: "__fdiv__",
        args: [numerator, %{op: :int_literal, value: 65_536}]
      }),
      do: pebble_angle_numerator_expr?(numerator)

  def pebble_angle_expr?(_expr), do: false

  @spec pebble_angle_optimized_reference_count(Types.binding_name(), Types.ir_expr()) ::
          non_neg_integer()
  def pebble_angle_optimized_reference_count(name, expr),
    do: pebble_angle_optimized_reference_count_node(name, expr)

  defp used_in_lambda_node?(name, %{op: :lambda, args: args, body: body}) when is_list(args) do
    not Enum.any?(args, &EnvBindings.same_binding?(name, &1)) and referenced?(name, body)
  end

  defp used_in_lambda_node?(name, expr) when is_map(expr) do
    expr
    |> Map.values()
    |> Enum.any?(&used_in_lambda_node?(name, &1))
  end

  defp used_in_lambda_node?(name, exprs) when is_list(exprs),
    do: Enum.any?(exprs, &used_in_lambda_node?(name, &1))

  defp used_in_lambda_node?(_name, _expr), do: false

  @spec reference_count_node(Types.binding_name(), Types.ir_expr() | [Types.ir_expr()]) ::
          non_neg_integer()
  defp reference_count_node(name, %{op: :var, name: var_name}),
    do: if(EnvBindings.same_binding?(name, var_name), do: 1, else: 0)

  defp reference_count_node(name, %{
         op: :let_in,
         name: let_name,
         value_expr: value,
         in_expr: body
       }) do
    value_count = reference_count_node(name, value)

    body_count =
      if EnvBindings.same_binding?(name, let_name), do: 0, else: reference_count_node(name, body)

    value_count + body_count
  end

  defp reference_count_node(name, %{op: :lambda, args: args} = expr) when is_list(args) do
    if Enum.any?(args, &EnvBindings.same_binding?(name, &1)) do
      reference_count_node(name, expr |> Map.delete(:body) |> Map.values())
    else
      reference_count_node(name, Map.values(expr))
    end
  end

  defp reference_count_node(name, expr) when is_map(expr) do
    reference_count_node(name, Map.values(expr))
  end

  defp reference_count_node(name, exprs) when is_list(exprs),
    do: Enum.reduce(exprs, 0, fn expr, acc -> acc + reference_count_node(name, expr) end)

  defp reference_count_node(_name, _expr), do: 0

  @spec pebble_angle_optimized_reference_count_node(
          Types.binding_name(),
          Types.ir_expr() | [Types.ir_expr()]
        ) :: non_neg_integer()
  defp pebble_angle_optimized_reference_count_node(name, expr) do
    cond do
      pebble_trig_round_expr?(expr, name) ->
        1

      is_map(expr) ->
        pebble_angle_optimized_reference_count_node(name, Map.values(expr))

      is_list(expr) ->
        Enum.reduce(expr, 0, fn value, acc ->
          acc + pebble_angle_optimized_reference_count_node(name, value)
        end)

      true ->
        0
    end
  end

  defp referenced?(name, %{op: :var, name: var_name}),
    do: EnvBindings.same_binding?(name, var_name)

  defp referenced?(name, value) when is_binary(value),
    do: EnvBindings.same_binding?(name, value)

  defp referenced?(name, expr) when is_map(expr) do
    expr
    |> Map.values()
    |> Enum.any?(&referenced?(name, &1))
  end

  defp referenced?(name, exprs) when is_list(exprs),
    do: Enum.any?(exprs, &referenced?(name, &1))

  defp referenced?(_name, _expr), do: false

  defp pebble_trig_round_expr?(
         %{op: :qualified_call, target: target, args: [value]},
         angle_name
       )
       when target in ["Basics.round", "round"],
       do: pebble_trig_scaled_expr?(value, angle_name)

  defp pebble_trig_round_expr?(
         %{op: :runtime_call, function: "elmc_basics_round", args: [value]},
         angle_name
       ),
       do: pebble_trig_scaled_expr?(value, angle_name)

  defp pebble_trig_round_expr?(_expr, _angle_name), do: false

  defp pebble_trig_scaled_expr?(
         %{op: :call, name: "__mul__", args: [left, right]},
         angle_name
       ) do
    (pebble_trig_call_expr?(left, angle_name) and to_float_expr?(right)) or
      (pebble_trig_call_expr?(right, angle_name) and to_float_expr?(left))
  end

  defp pebble_trig_scaled_expr?(_expr, _angle_name), do: false

  defp pebble_trig_call_expr?(
         %{op: :qualified_call, target: target, args: [%{op: :var, name: name}]},
         angle_name
       )
       when target in ["Basics.sin", "Basics.cos", "sin", "cos"],
       do: EnvBindings.same_binding?(name, angle_name)

  defp pebble_trig_call_expr?(
         %{op: :runtime_call, function: function, args: [%{op: :var, name: name}]},
         angle_name
       )
       when function in ["elmc_basics_sin", "elmc_basics_cos"],
       do: EnvBindings.same_binding?(name, angle_name)

  defp pebble_trig_call_expr?(_expr, _angle_name), do: false

  defp to_float_expr?(%{op: :qualified_call, target: target, args: [_value]})
       when target in ["Basics.toFloat", "toFloat"],
       do: true

  defp to_float_expr?(%{op: :call, name: name, args: [_value]}) when name in ["toFloat"],
    do: true

  defp to_float_expr?(%{op: :runtime_call, function: "elmc_basics_to_float", args: [_value]}),
    do: true

  defp to_float_expr?(_expr), do: false

  defp pebble_angle_numerator_expr?(%{op: :call, name: "__mul__", args: [left, right]}) do
    (pi_expr?(left) and double_to_float_expr?(right)) or
      (pi_expr?(right) and double_to_float_expr?(left))
  end

  defp pebble_angle_numerator_expr?(_expr), do: false

  defp double_to_float_expr?(%{
         op: :call,
         name: "__mul__",
         args: [left, %{op: :int_literal, value: 2}]
       }),
       do: to_float_expr?(left)

  defp double_to_float_expr?(%{
         op: :call,
         name: "__mul__",
         args: [%{op: :int_literal, value: 2}, right]
       }),
       do: to_float_expr?(right)

  defp double_to_float_expr?(_expr), do: false

  defp pi_expr?(%{op: :qualified_call, target: target, args: []})
       when target in ["Basics.pi", "pi"],
       do: true

  defp pi_expr?(%{op: :float_literal, value: value}) when value == 3.141592653589793, do: true
  defp pi_expr?(_expr), do: false
end
