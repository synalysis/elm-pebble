defmodule ElmEx.DebuggerContractCmdCallsTest do
  use ExUnit.Case, async: true

  alias ElmEx.DebuggerContract.EffectAnalysis.CmdCalls
  alias ElmEx.DebuggerContract.ExprCoerce

  test "callback_constructor_from_expr extracts GotWeather through compose_left" do
    expr = %{
      op: :compose_left,
      f: %{op: :var, name: "GotWeather"},
      g: %{op: :qualified_call, target: "Result.map", args: [%{op: :var, name: "Weather.Current"}]}
    }

    assert CmdCalls.callback_constructor_from_expr(expr, %{}, MapSet.new(), 0) == "GotWeather"
  end

  test "callback_constructor_from_expr prefers callback over Result.map in compose_left" do
    expr = %{
      op: :compose_left,
      f: %{op: :constructor_call, target: "Msg.GotWeather"},
      g: %{op: :qualified_call, target: "Result.map", args: [%{op: :var, name: "Weather.Current"}]}
    }

    assert CmdCalls.callback_constructor_from_expr(expr, %{}, MapSet.new(), 0) == "GotWeather"
  end

  test "coerce Core IR tuple3 keeps official #3 and extracts a cmd from an arm" do
    wire = %{
      "op" => "tuple3",
      "a" => %{"op" => "int_literal", "value" => 1},
      "b" => %{
        "op" => "qualified_call",
        "target" => "Pebble.Cmd.getCurrentDateTime",
        "args" => [%{"op" => "var", "name" => "TimeUpdate"}]
      },
      "c" => %{"op" => "int_literal", "value" => 3}
    }

    ast = ExprCoerce.to_ast(wire)
    assert ast.op == :tuple3
    assert ast.a.op == :int_literal
    assert ast.b.op == :qualified_call
    assert ast.c.op == :int_literal

    assert [%{"target" => "Pebble.Cmd.getCurrentDateTime"}] =
             CmdCalls.extract_cmd_calls(ast, %{})
  end
end
