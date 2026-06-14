defmodule Elmc.Backend.CCodegen.MacroReachability do
  @moduledoc false

  alias Elmc.Backend.CCodegen.Types

  @spec used_union_ctors(Types.function_decl_map(), Enumerable.t()) :: MapSet.t(String.t())
  def used_union_ctors(decl_map, targets) do
    targets
    |> Enum.flat_map(fn key ->
      case Map.fetch(decl_map, key) do
        {:ok, %{expr: expr}} -> union_ctors_in_expr(expr)
        _ -> []
      end
    end)
    |> MapSet.new()
  end

  defp union_ctors_in_expr(%{op: :int_literal, union_ctor: ctor}) when is_binary(ctor), do: [ctor]

  defp union_ctors_in_expr(%{kind: :constructor, name: name}) when is_binary(name), do: [name]

  defp union_ctors_in_expr(%{kind: :constructor, resolved_name: name}) when is_binary(name) do
    [name |> String.split(".") |> List.last()]
  end

  defp union_ctors_in_expr(%{op: :case, branches: branches}) when is_list(branches) do
    Enum.flat_map(branches, fn
      %{pattern: pattern, expr: expr} ->
        union_ctors_in_expr(pattern) ++ union_ctors_in_expr(expr)

      branch ->
        union_ctors_in_expr(branch)
    end)
  end

  defp union_ctors_in_expr(expr) when is_map(expr) do
    expr |> Map.values() |> Enum.flat_map(&union_ctors_in_expr/1)
  end

  defp union_ctors_in_expr(expr) when is_list(expr), do: Enum.flat_map(expr, &union_ctors_in_expr/1)
  defp union_ctors_in_expr(_), do: []
end
