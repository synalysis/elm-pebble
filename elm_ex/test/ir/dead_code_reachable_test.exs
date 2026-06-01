defmodule ElmEx.IR.DeadCodeReachableTest do
  use ExUnit.Case, async: true

  alias ElmEx.IR
  alias ElmEx.IR.DeadCode

  test "reachable_keys follows qualified calls across modules" do
    ir = %IR{
      modules: [
        %{
          name: "Main",
          declarations: [
            %{
              kind: :function,
              name: "init",
              args: [],
              expr: %{
                op: :qualified_call,
                target: "Helper.greet",
                args: [%{op: :int_literal, value: 1}]
              }
            }
          ]
        },
        %{
          name: "Helper",
          declarations: [
            %{
              kind: :function,
              name: "greet",
              args: ["n"],
              expr: %{op: :var, name: "n"}
            },
            %{
              kind: :function,
              name: "unused",
              args: [],
              expr: %{op: :int_literal, value: 0}
            }
          ]
        }
      ]
    }

    reachable = DeadCode.reachable_keys(ir, "Main", roots: ["init"])

    assert MapSet.member?(reachable, "Main.init")
    assert MapSet.member?(reachable, "Helper.greet")
    refute MapSet.member?(reachable, "Helper.unused")
  end
end
