defmodule ElmEx.DebuggerContractLetBindingsTest do
  use ExUnit.Case, async: true

  alias ElmEx.DebuggerContract
  alias ElmEx.DebuggerContract.EffectAnalysis.CmdCalls
  alias ElmEx.DebuggerContract.ViewTree.Operators

  test "peel_lets_with_bindings expands let_bindings name bindings" do
    expr = %{
      op: :let_bindings,
      bindings: [
        %{kind: :name, name: "cmd", value: %{op: :qualified_call, target: "Cmd.none", args: []}}
      ],
      in_expr: %{op: :var, name: "cmd"}
    }

    {peeled, bindings} = DebuggerContract.peel_lets_with_bindings(expr)
    assert peeled == %{op: :var, name: "cmd"}
    assert Map.has_key?(bindings, "cmd")
  end

  test "extract_cmd_calls walks let_bindings before body" do
    expr = %{
      op: :let_bindings,
      bindings: [
        %{
          kind: :name,
          name: "effect",
          value: %{op: :qualified_call, target: "Cmd.none", args: []}
        }
      ],
      in_expr: %{
        op: :qualified_call,
        target: "Cmd.batch",
        args: [%{op: :list_literal, items: [%{op: :var, name: "effect"}]}]
      }
    }

    assert [%{"target" => "Cmd.none"}] = CmdCalls.extract_cmd_calls(expr, %{})
  end

  test "view tree renders let_bindings binding children" do
    expr = %{
      op: :let_bindings,
      bindings: [%{kind: :name, name: "x", value: %{op: :int_literal, value: 1}}],
      in_expr: %{op: :var, name: "x"}
    }

    tree = Operators.expr_to_view_tree(expr, 0, 4, %{})
    assert tree["type"] == "let"
    assert [%{"type" => "let_binding", "label" => "x"} | _] = tree["children"]
  end
end
