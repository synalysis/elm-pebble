defmodule ElmEx.IR.FrontendReachabilityTest do
  use ExUnit.Case, async: true

  alias ElmEx.Frontend.Project
  alias ElmEx.IR.FrontendReachability

  test "reachable_function_keys follows qualified calls and skips unused" do
    project = %Project{
      project_dir: "/tmp/reach",
      elm_json: %{},
      modules: [
        %{
          name: "Main",
          path: "Main.elm",
          imports: ["Helper"],
          import_entries: [
            %{"module" => "Helper", "exposing" => ["greet"]}
          ],
          declarations: [
            %{
              kind: :function_definition,
              name: "init",
              args: [],
              expr: %{
                op: :qualified_call,
                target: "Helper.greet",
                args: [%{op: :int_literal, value: 1}]
              },
              span: %{start_line: 1, end_line: 1}
            }
          ]
        },
        %{
          name: "Helper",
          path: "Helper.elm",
          imports: [],
          import_entries: [],
          declarations: [
            %{
              kind: :function_definition,
              name: "greet",
              args: ["n"],
              expr: %{op: :var, name: "n"},
              span: %{start_line: 1, end_line: 1}
            },
            %{
              kind: :function_definition,
              name: "unused",
              args: [],
              expr: %{op: :int_literal, value: 0},
              span: %{start_line: 2, end_line: 2}
            }
          ]
        }
      ]
    }

    keys = FrontendReachability.reachable_function_keys(project, "Main", roots: ["init"])

    assert MapSet.member?(keys, "Main.init")
    assert MapSet.member?(keys, "Helper.greet")
    refute MapSet.member?(keys, "Helper.unused")
  end

  test "reachable_function_keys follows field_access on import aliases" do
    project = %Project{
      project_dir: "/tmp/reach-field",
      elm_json: %{},
      modules: [
        %{
          name: "Main",
          path: "Main.elm",
          imports: ["Tailwind.Theme"],
          import_entries: [
            %{"module" => "Tailwind.Theme", "as" => "Theme", "exposing" => nil}
          ],
          declarations: [
            %{
              kind: :function_definition,
              name: "view",
              args: [],
              expr: %{
                op: :field_access,
                arg: %{op: :var, name: "Theme"},
                field: "white"
              },
              span: %{start_line: 1, end_line: 1}
            }
          ]
        },
        %{
          name: "Tailwind.Theme",
          path: "Theme.elm",
          imports: [],
          import_entries: [],
          declarations: [
            %{
              kind: :function_definition,
              name: "white",
              args: [],
              expr: %{op: :string_literal, value: "#fff"},
              span: %{start_line: 1, end_line: 1}
            },
            %{
              kind: :function_definition,
              name: "black",
              args: [],
              expr: %{op: :string_literal, value: "#000"},
              span: %{start_line: 2, end_line: 2}
            }
          ]
        }
      ]
    }

    keys = FrontendReachability.reachable_function_keys(project, "Main", roots: ["view"])

    assert MapSet.member?(keys, "Main.view")
    assert MapSet.member?(keys, "Tailwind.Theme.white")
    refute MapSet.member?(keys, "Tailwind.Theme.black")
  end
end
