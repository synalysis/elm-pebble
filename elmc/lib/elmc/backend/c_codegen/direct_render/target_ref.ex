defmodule Elmc.Backend.CCodegen.DirectRender.TargetRef do
  @moduledoc false

  alias Elmc.Backend.CCodegen.DirectRender.Support
  alias Elmc.Backend.CCodegen.Host
  alias Elmc.Backend.CCodegen.Types

  @direct_static_list_unroll_max 64

  @spec emit_function_target(Types.ir_expr(), String.t()) :: Types.function_target() | nil
  def emit_function_target(%{op: :var, name: name}, module_name), do: {module_name, name, []}

  def emit_function_target(%{op: :call, name: name, args: args}, module_name),
    do: {module_name, name, args}

  def emit_function_target(%{op: :qualified_call, target: target, args: args}, _module_name) do
    case Host.split_qualified_function_target(Host.normalize_special_target(target)) do
      nil -> nil
      {target_module, target_name} -> {target_module, target_name, args}
    end
  end

  def emit_function_target(_expr, _module_name), do: nil

  @spec unwrap_lets(Types.ir_expr()) :: Types.ir_expr()
  def unwrap_lets(%{op: :let_in, in_expr: in_expr}), do: unwrap_lets(in_expr)
  def unwrap_lets(expr), do: expr

  @spec static_list_items(Types.ir_expr()) :: {:ok, [Types.ir_expr()]} | :error
  def static_list_items(expr) do
    case expr do
      %{op: :list_literal, items: items} ->
        if length(items) <= @direct_static_list_unroll_max do
          {:ok, items}
        else
          :error
        end

      %{op: :qualified_call, target: target, args: args}
      when target in ["List.concat", "Elm.Kernel.List.concat"] ->
        case Support.static_concat_items(args) do
          {:ok, items} when length(items) <= @direct_static_list_unroll_max -> {:ok, items}
          _ -> :error
        end

      %{op: :call, name: "__append__", args: [left, right]} ->
        with {:ok, left_items} <- static_list_items(left),
             {:ok, right_items} <- static_list_items(right) do
          items = left_items ++ right_items

          if length(items) <= @direct_static_list_unroll_max do
            {:ok, items}
          else
            :error
          end
        else
          _ -> :error
        end

      _ ->
        :error
    end
  end
end
