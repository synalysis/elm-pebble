defmodule Elmc.WasmStubFunctionsTest do
  use ExUnit.Case, async: true

  alias Elmc.Backend.Plan.Types.{Block, FunctionPlan}
  alias Elmc.Backend.Wasm.StubFunctions

  test "missing_callees reports unresolved call_fn targets" do
    caller = %FunctionPlan{
      module: "Main",
      name: "caller",
      blocks: [
        %Block{
          id: 0,
          instrs: [
            %{
              op: :call_fn,
              args: %{module: "Elm.Kernel.Json", name: "addField", args: [0, 1, 2]}
            }
          ],
          terminator: {:ret, :fn_out}
        }
      ],
      entry_block: 0,
      locals: %{},
      reg_count: 3,
      rc_required: true,
      fallible: true,
      catch_depth: 0,
      lambdas: [],
      params: []
    }

    [stub] = StubFunctions.missing_callees([caller])

    assert stub.module == "Elm.Kernel.Json"
    assert stub.name == "addField"
    assert stub.arity == 3
    assert stub.kind == :kernel_stub
  end
end
