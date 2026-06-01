defmodule Elmx.ReachableModulesTest do
  use ExUnit.Case, async: true

  alias Elmx.Backend.ReachableModules

  test "modules_for_emit keeps modules called from entry roots" do
    ir = %ElmEx.IR{
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
                args: [%{op: :int_literal, value: 0}]
              }
            }
          ]
        },
        %{
          name: "Helper",
          declarations: [
            %{kind: :function, name: "greet", args: [], expr: %{op: :int_literal, value: 1}},
            %{kind: :function, name: "orphan", args: [], expr: %{op: :int_literal, value: 2}}
          ]
        }
      ]
    }

    modules = ReachableModules.modules_for_emit(ir, "Main")
    assert Enum.map(modules, & &1.name) == ["Main", "Helper"]

    helper = Enum.find(modules, &(&1.name == "Helper"))
    reachable_fn = Enum.filter(helper.declarations, &(&1.kind == :function))
    assert Enum.map(reachable_fn, & &1.name) == ["greet"]
  end
end
