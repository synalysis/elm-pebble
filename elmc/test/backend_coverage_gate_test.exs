defmodule Elmc.BackendCoverageGateTest do
  use ExUnit.Case

  alias ElmEx.Frontend.Bridge
  alias ElmEx.IR.Lowerer

  @moduledoc """
  Gate test: fails if any lowered function body in the fixture corpus
  contains ops that the backend cannot compile (i.e., would fall through
  to the catch-all compile_expr clause).
  """

  # Ops that the backend's compile_expr handles directly
  @supported_ops MapSet.new([
                   :int_literal,
                   :float_literal,
                   :string_literal,
                   :char_literal,
                   :cmd_none,
                   :var,
                   :add_const,
                   :add_vars,
                   :sub_const,
                   :tuple2,
                   :list_literal,
                   :record_literal,
                   :field_access,
                   :field_call,
                   :lambda,
                   :call,
                   :qualified_call,
                   :constructor_call,
                   :runtime_call,
                   :let_in,
                   :if,
                   :compare,
                   :case,
                   :maybe_with_default_list_head,
                   :list_foldl_add_zero,
                   :maybe_inc,
                   :tuple_first,
                   :tuple_second,
                   :tuple_first_expr,
                   :tuple_second_expr,
                   :string_length,
                   :string_length_expr,
                   :char_from_code,
                   :char_from_code_expr,
                   :unsupported
                 ])

  test "no unsupported backend ops in simple_project after lowering" do
    project_dir = Path.expand("fixtures/simple_project", __DIR__)
    {:ok, project} = Bridge.load_project(project_dir)
    {:ok, ir} = Lowerer.lower_project(project)

    unsupported =
      ir.modules
      |> Enum.flat_map(fn mod ->
        mod.declarations
        |> Enum.filter(&(&1.kind == :function and is_map(&1.expr)))
        |> Enum.flat_map(fn decl ->
          collect_unsupported_backend_ops(decl.expr)
          |> Enum.map(fn {op, _} -> {mod.name, decl.name, op} end)
        end)
      end)

    if unsupported != [] do
      summary =
        unsupported
        |> Enum.group_by(fn {_mod, _fn, op} -> op end)
        |> Enum.map(fn {op, entries} ->
          fns =
            entries |> Enum.map(fn {m, f, _} -> "#{m}.#{f}" end) |> Enum.uniq() |> Enum.take(5)

          "  #{op}: #{length(entries)} occurrences in #{Enum.join(fns, ", ")}"
        end)
        |> Enum.join("\n")

      flunk("Backend coverage gap - unsupported ops found after lowering:\n#{summary}")
    end
  end

  test "no unsupported backend ops in qualified_constructor_project after lowering" do
    project_dir = Path.expand("fixtures/qualified_constructor_project", __DIR__)
    {:ok, project} = Bridge.load_project(project_dir)
    {:ok, ir} = Lowerer.lower_project(project)

    unsupported =
      ir.modules
      |> Enum.flat_map(fn mod ->
        mod.declarations
        |> Enum.filter(&(&1.kind == :function and is_map(&1.expr)))
        |> Enum.flat_map(fn decl ->
          collect_unsupported_backend_ops(decl.expr)
          |> Enum.map(fn {op, _} -> {mod.name, decl.name, op} end)
        end)
      end)

    assert unsupported == [], "Unsupported ops: #{inspect(unsupported)}"
  end

  defp collect_unsupported_backend_ops(nil), do: []

  defp collect_unsupported_backend_ops(%{op: op} = expr) when is_atom(op) do
    current = if MapSet.member?(@supported_ops, op), do: [], else: [{op, expr}]
    current ++ collect_children_ops(expr)
  end

  defp collect_unsupported_backend_ops(_), do: []

  defp collect_children_ops(expr) when is_map(expr) do
    expr
    |> Map.values()
    |> Enum.flat_map(fn
      child when is_map(child) and is_map_key(child, :op) ->
        collect_unsupported_backend_ops(child)

      children when is_list(children) ->
        Enum.flat_map(children, fn
          child when is_map(child) and is_map_key(child, :op) ->
            collect_unsupported_backend_ops(child)

          child when is_map(child) ->
            # For branch maps with :expr key
            case child do
              %{expr: e} when is_map(e) -> collect_unsupported_backend_ops(e)
              _ -> []
            end

          _ ->
            []
        end)

      _ ->
        []
    end)
  end
end
