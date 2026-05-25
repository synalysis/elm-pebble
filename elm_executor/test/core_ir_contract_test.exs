defmodule ElmExecutor.Runtime.CoreIRContractTest do
  use ExUnit.Case, async: true

  alias ElmEx.CoreIR
  alias ElmExecutor.Runtime.CoreIRContract

  test "validate accepts normalized core IR struct" do
    ir = %ElmEx.IR{
      modules: [
        %ElmEx.IR.Module{
          name: "Main",
          imports: [],
          declarations: [
            %ElmEx.IR.Declaration{
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

    assert {:ok, core_ir} = CoreIR.from_ir(ir)
    assert :ok = CoreIRContract.validate(core_ir)
  end

  test "validate rejects call missing required name" do
    bad = %{
      "version" => "elm_ex.core_ir.v1",
      "modules" => [
        %{
          "name" => "Main",
          "imports" => [],
          "unions" => %{},
          "declarations" => [
            %{
              "kind" => "function",
              "name" => "f",
              "args" => [],
              "ownership" => [],
              "expr" => %{"op" => "call"}
            }
          ]
        }
      ],
      "diagnostics" => [],
      "deterministic_sha256" => "abc"
    }

    assert {:error, {:invalid_core_ir, errors}} = CoreIRContract.validate(bad)
    assert Enum.any?(errors, &(&1.code == "invalid_core_ir_shape"))
  end
end
