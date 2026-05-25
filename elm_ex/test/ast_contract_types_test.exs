defmodule ElmEx.AstContractTypesTest do
  use ExUnit.Case, async: true

  alias ElmEx.Frontend.{AstContract, Module}

  defp function_decl(expr) do
    %{
      kind: :function_definition,
      name: "f",
      args: [],
      expr: expr,
      span: %{start_line: 1, end_line: 1}
    }
  end

  defp module_with_expr(expr) do
    %Module{
      name: "Main",
      path: "Main.elm",
      imports: [],
      declarations: [function_decl(expr)]
    }
  end

  test "validate_module accepts compare and record literal expr shapes" do
    expr = %{
      op: :compare,
      left: %{op: :int_literal, value: 1},
      right: %{op: :var, name: "n"},
      kind: :eq
    }

    assert :ok = AstContract.validate_module(module_with_expr(expr))

    record = %{
      op: :record_literal,
      fields: [%{name: "x", expr: %{op: :int_literal, value: 0}}]
    }

    assert :ok = AstContract.validate_module(module_with_expr(record))
  end

  test "validate_module accepts let_in and compose_left" do
    let_expr = %{
      op: :let_in,
      name: "x",
      value_expr: %{op: :int_literal, value: 1},
      in_expr: %{op: :var, name: "x"}
    }

    assert :ok = AstContract.validate_module(module_with_expr(let_expr))

    compose = %{op: :compose_left, f: "f", g: "g"}
    assert :ok = AstContract.validate_module(module_with_expr(compose))
  end
end
