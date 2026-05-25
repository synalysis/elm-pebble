defmodule ElmEx.CoreIRTypesHubTest do
  use ExUnit.Case, async: true

  alias ElmEx.{CoreIR, IR}

  test "from_ir produces struct matching CoreIR.Types.t" do
    ir = %IR{
      modules: [
        %IR.Module{
          name: "Main",
          imports: [],
          declarations: [
            %IR.Declaration{
              kind: :function,
              name: "main",
              args: [],
              expr: %{op: :int_literal, value: 1},
              ownership: []
            }
          ]
        }
      ]
    }

    assert {:ok, %CoreIR{version: "elm_ex.core_ir.v1"} = core_ir} = CoreIR.from_ir(ir)
    assert is_list(core_ir.modules)
    assert is_list(core_ir.diagnostics)
    assert is_binary(core_ir.deterministic_sha256)
  end
end
