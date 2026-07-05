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

  defp union_ctors_in_expr(%{kind: :constructor} = pattern) do
    ctor_names =
      [Map.get(pattern, :resolved_name), Map.get(pattern, :name)]
      |> Enum.filter(&is_binary/1)
      |> Enum.flat_map(fn name ->
        short = name |> String.split(".") |> List.last()
        Enum.uniq([name, short])
      end)

    arg_names =
      case Map.get(pattern, :arg_pattern) do
        nil -> []
        arg -> union_ctors_in_expr(arg)
      end

    ctor_names ++ arg_names
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
