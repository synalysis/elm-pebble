defmodule ElmEx.Frontend.PowOperatorTest do
  use ExUnit.Case, async: true

  alias ElmEx.Frontend.GeneratedExpressionParser

  test "infix ^ lowers to __pow__ (Scene3d exposureValue / inverseGamma)" do
    assert {:ok,
            %{
              op: :call,
              name: "__pow__",
              args: [%{op: :int_literal, value: 2}, %{op: :int_literal, value: 3}]
            }} = GeneratedExpressionParser.parse("2 ^ 3")

    assert {:ok,
            %{
              op: :call,
              name: "__pow__",
              args: [
                %{op: :int_literal, value: 2},
                %{op: :add_const, var: "index", value: 4}
              ]
            }} = GeneratedExpressionParser.parse("2 ^ (index + 4)")

    assert {:ok,
            %{
              op: :call,
              name: "__mul__",
              args: [
                %{op: :float_literal, value: 1.2},
                %{
                  op: :call,
                  name: "__pow__",
                  args: [%{op: :int_literal, value: 2}, %{op: :var, name: "ev100"}]
                }
              ]
            }} = GeneratedExpressionParser.parse("1.2 * 2 ^ ev100")
  end

  test "juxtaposition still wins over bare primary reduce" do
    assert {:ok, %{op: :call, name: "f", args: [%{op: :var, name: "x"}]}} =
             GeneratedExpressionParser.parse("f x")

    assert {:ok, %{op: :call, name: "clamp", args: [_, _, _]}} =
             GeneratedExpressionParser.parse("clamp 0 1 u")
  end
end
