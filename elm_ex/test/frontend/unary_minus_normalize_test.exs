defmodule ElmEx.Frontend.UnaryMinusNormalizeTest do
  use ExUnit.Case, async: true

  alias ElmEx.Frontend.GeneratedExpressionParser

  test "tight unary minus keeps full identifiers and qualified names" do
    assert {:ok,
            %{
              op: :call,
              name: "f",
              args: [
                %{
                  op: :call,
                  name: "negate",
                  args: [%{op: :qualified_ref, target: "Const.maxNumber"}]
                }
              ]
            }} = GeneratedExpressionParser.parse("f -Const.maxNumber")

    assert {:ok,
            %{
              op: :call,
              name: "max",
              args: [%{op: :call, name: "negate", args: [%{op: :var, name: "h2"}]}]
            }} = GeneratedExpressionParser.parse("max -h2")

    assert {:ok,
            %{
              op: :qualified_call,
              target: "Vec3.scale",
              args: [
                %{op: :call, name: "negate", args: [%{op: :var, name: "radius2"}]},
                %{op: :var, name: "normal"}
              ]
            }} = GeneratedExpressionParser.parse("Vec3.scale -radius2 normal")
  end

  test "spaced binary subtraction is not rewritten to negate" do
    assert {:ok, %{op: :sub_vars, left: "a", right: "b"}} =
             GeneratedExpressionParser.parse("a - b")
  end
end
