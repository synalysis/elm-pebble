defmodule ElmEx.DebuggerContractCmdCallsTest do
  use ExUnit.Case, async: true

  alias ElmEx.DebuggerContract.EffectAnalysis.CmdCalls

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
end
