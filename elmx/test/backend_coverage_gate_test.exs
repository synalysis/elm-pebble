defmodule Elmx.BackendCoverageGateTest do
  use ExUnit.Case

  alias ElmEx.Frontend.Bridge
  alias ElmEx.IR.Lowerer

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
                   :record_update,
                   :field_access,
                   :field_call,
                   :lambda,
                   :call,
                   :qualified_call,
                   :qualified_call1,
                   :constructor_call,
                   :runtime_call,
                   :let_in,
                   :if,
                   :compare,
                   :case,
                   :tuple_first,
                   :tuple_second,
                   :tuple_first_expr,
                   :tuple_second_expr,
                   :string_length_expr,
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
          collect_unsupported_ops(decl.expr)
          |> Enum.map(fn op -> {mod.name, decl.name, op} end)
        end)
      end)

    if unsupported != [] do
      flunk("Elmx backend coverage gap:\n#{inspect(unsupported, limit: 20)}")
    end
  end

  defp collect_unsupported_ops(expr) when is_map(expr) do
    op = Map.get(expr, :op)

    op_errors =
      if is_atom(op) and op != nil and not MapSet.member?(@supported_ops, op) do
        [op]
      else
        []
      end

    nested =
      expr
      |> Map.values()
      |> Enum.flat_map(fn
        v when is_map(v) -> collect_unsupported_ops(v)
        v when is_list(v) -> Enum.flat_map(v, &collect_nested/1)
        _ -> []
      end)

    op_errors ++ nested
  end

  defp collect_unsupported_ops(_), do: []

  defp collect_nested(v) when is_map(v), do: collect_unsupported_ops(v)
  defp collect_nested(v) when is_list(v), do: Enum.flat_map(v, &collect_nested/1)
  defp collect_nested(_), do: []
end
