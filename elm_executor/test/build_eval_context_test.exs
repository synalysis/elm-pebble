defmodule ElmExecutor.Runtime.BuildEvalContextTest do
  use ExUnit.Case, async: true

  alias ElmEx.CoreIR
  alias ElmExecutor.Runtime.CoreIREvaluator

  test "build_eval_context indexes two modules consistently with entry_module/1" do
    ir = %ElmEx.IR{
      modules: [
        %ElmEx.IR.Module{
          name: "Helper",
          imports: [],
          declarations: [
            %ElmEx.IR.Declaration{
              kind: :function,
              name: "tick",
              args: [],
              expr: %{op: :int_literal, value: 0},
              ownership: []
            }
          ]
        },
        %ElmEx.IR.Module{
          name: "Main",
          imports: [],
          declarations: [
            %ElmEx.IR.Declaration{
              kind: :function,
              name: "init",
              args: [],
              expr: %{op: :int_literal, value: 1},
              ownership: []
            }
          ]
        }
      ]
    }

    assert {:ok, core_ir} = CoreIR.from_ir(ir)
    assert CoreIREvaluator.entry_module(core_ir) == "Main"

    ctx = CoreIREvaluator.build_eval_context(core_ir, "Main")

    assert ctx.module == "Main"
    assert ctx.functions[{"Main", "init", 0}].name == "init"
    assert ctx.functions[{"Helper", "tick", 0}].module == "Helper"
    assert is_map(ctx.record_aliases)
    assert is_list(ctx.constructor_tags)
  end

  test "build_eval_context falls back to Main when core_ir has no init" do
    core_ir = %{
      "modules" => [
        %{
          "name" => "Only",
          "imports" => [],
          "unions" => %{},
          "declarations" => [
            %{
              "kind" => "function",
              "name" => "view",
              "args" => [],
              "ownership" => [],
              "expr" => %{"op" => "int_literal", "value" => 0}
            }
          ]
        }
      ]
    }

    assert CoreIREvaluator.entry_module(core_ir) == "Only"
    ctx = CoreIREvaluator.build_eval_context(core_ir, "Only")
    assert ctx.source_module == "Only"
    assert ctx.functions[{"Only", "view", 0}]
  end
end
