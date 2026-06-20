defmodule Elmx.CrossModuleEmitTest do
  use ExUnit.Case, async: false

  alias ElmEx.Frontend.Bridge

  @project_dir Path.expand("fixtures/simple_project", __DIR__)

  test "ide_runtime emits reachable helper modules referenced from Main" do
    {:ok, project} = Bridge.load_project(@project_dir)
    {:ok, ir} = ElmEx.IR.Lowerer.lower_project(project)

    ir =
      ElmEx.IR.DeadCode.strip(ir, "Main",
        roots: Elmx.Backend.MainProgram.dead_code_roots(ir, "Main")
      )

    revision = "cross-" <> Integer.to_string(:erlang.unique_integer([:positive]))

    assert {:ok, [%{source: source}]} =
             Elmx.Backend.ElixirCodegen.emit_project(ir, %{
               entry_module: "Main",
               mode: :ide_runtime,
               ir_sha256: revision,
               user_module_names: ["Main"]
             })

    assert source =~ "def elmx_fn_Main_init"
    refute source =~ "def elmx_fn_CoreCompliance_foldSum"
  end

  test "cross-module qualified calls emit callee module symbol" do
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
            %{kind: :function, name: "greet", args: [], expr: %{op: :int_literal, value: 1}}
          ]
        }
      ]
    }

    revision = "cross-call-" <> Integer.to_string(:erlang.unique_integer([:positive]))

    assert {:ok, [%{source: source}]} =
             Elmx.Backend.ElixirCodegen.emit_project(ir, %{
               entry_module: "Main",
               mode: :ide_runtime,
               ir_sha256: revision,
               user_module_names: ["Main", "Helper"]
             })

    assert source =~ "elmx_fn_Helper_greet()"
    assert source =~ "def elmx_fn_Helper_greet"
  end

  test "cross-module partial application emits capture" do
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
                target: "Helper.add",
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
              name: "add",
              args: ["a", "b"],
              expr: %{op: :add_vars, left: "a", right: "b"}
            }
          ]
        }
      ]
    }

    revision = "cross-partial-" <> Integer.to_string(:erlang.unique_integer([:positive]))

    assert {:ok, [%{source: source}]} =
             Elmx.Backend.ElixirCodegen.emit_project(ir, %{
               entry_module: "Main",
               mode: :ide_runtime,
               ir_sha256: revision,
               user_module_names: ["Main", "Helper"]
             })

    assert source =~ "fn elmx_p1 -> elmx_fn_Helper_add(1, elmx_p1) end"
  end
end
