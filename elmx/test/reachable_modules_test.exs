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

  test "modules_for_emit keeps reachable bundled speaker resource catalog under user_module_names filter" do
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
                target: "Pebble.Speaker.Resources.allSamples",
                args: []
              }
            }
          ]
        },
        %{
          name: "Pebble.Speaker.Resources",
          declarations: [
            %{
              kind: :function,
              name: "allSamples",
              args: [],
              expr: %{
                op: :list_literal,
                items: [%{op: :constructor_ref, target: "Pebble.Speaker.Resources.NoSample"}]
              }
            },
            %{
              kind: :function,
              name: "sampleId",
              args: [%{name: "sample"}],
              expr: %{op: :int_literal, value: 0}
            }
          ]
        }
      ]
    }

    modules =
      ReachableModules.modules_for_emit(ir, "Main",
        user_module_names: ["Main"]
      )

    assert Enum.map(modules, & &1.name) == ["Main", "Pebble.Speaker.Resources"]

    resources = Enum.find(modules, &(&1.name == "Pebble.Speaker.Resources"))
    assert Enum.map(resources.declarations, & &1.name) == ["allSamples"]
  end
end
