defmodule Elmc.LoweringCoverageTest do
  use ExUnit.Case

  alias ElmEx.Frontend.Bridge
  alias ElmEx.IR.Lowerer

  test "lowering unsupported nodes are eliminated on fixture corpus" do
    project_dir = Path.expand("fixtures/simple_project", __DIR__)
    {:ok, project} = Bridge.load_project(project_dir)
    {:ok, ir} = Lowerer.lower_project(project)

    unsupported =
      ir.modules
      |> Enum.flat_map(fn mod ->
        mod.declarations
        |> Enum.filter(&(&1.kind == :function))
        |> Enum.flat_map(fn decl ->
          collect_unsupported(decl.expr)
          |> Enum.map(fn node -> {mod.name, decl.name, node[:source]} end)
        end)
      end)

    assert unsupported == []
  end

  defp collect_unsupported(expr) when not is_map(expr), do: []

  defp collect_unsupported(%{op: :unsupported} = expr), do: [expr]

  defp collect_unsupported(%{op: :let_in, value_expr: value_expr, in_expr: in_expr}) do
    collect_unsupported(value_expr) ++ collect_unsupported(in_expr)
  end

  defp collect_unsupported(%{op: :if, cond: cond_expr, then_expr: then_expr, else_expr: else_expr}) do
    collect_unsupported(cond_expr) ++
      collect_unsupported(then_expr) ++ collect_unsupported(else_expr)
  end

  defp collect_unsupported(%{op: :case, branches: branches} = expr) do
    subject_hits =
      case expr[:subject] do
        subject when is_map(subject) -> collect_unsupported(subject)
        _ -> []
      end

    branch_hits =
      branches
      |> Enum.flat_map(fn branch -> collect_unsupported(branch.expr) end)

    subject_hits ++ branch_hits
  end

  defp collect_unsupported(%{op: :tuple2, left: left, right: right}) do
    collect_unsupported(left) ++ collect_unsupported(right)
  end

  defp collect_unsupported(%{op: :compare, left: left, right: right}) do
    collect_unsupported(left) ++ collect_unsupported(right)
  end

  defp collect_unsupported(%{op: :list_literal, items: items}) do
    Enum.flat_map(items || [], &collect_unsupported/1)
  end

  defp collect_unsupported(%{op: op, args: args})
       when op in [:call, :qualified_call, :constructor_call, :runtime_call, :field_call] do
    Enum.flat_map(args || [], &collect_unsupported/1)
  end

  defp collect_unsupported(%{op: :lambda, body: body}), do: collect_unsupported(body)

  defp collect_unsupported(%{op: :record_literal, fields: fields}) do
    fields
    |> Enum.flat_map(fn
      %{expr: child} -> collect_unsupported(child)
      _ -> []
    end)
  end

  defp collect_unsupported(%{op: op, arg: arg})
       when op in [
              :tuple_first_expr,
              :tuple_second_expr,
              :string_length_expr,
              :char_from_code_expr
            ] do
    collect_unsupported(arg)
  end

  defp collect_unsupported(_expr), do: []
end
