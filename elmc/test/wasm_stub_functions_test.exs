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

  test "host_bridge? allowlist is empty" do
    refute StubFunctions.host_bridge?(%{module: "Elm.Kernel.MJS", name: "v3add"})
    refute StubFunctions.host_bridge?(%{module: "Elm.Kernel.WebGL", name: "entity"})
    refute StubFunctions.host_bridge?(%{module: "Elm.Kernel.WebGL", name: "toHtml"})
    refute StubFunctions.host_bridge?(%{module: "Float", name: "Extra.interpolateFrom"})
    refute StubFunctions.host_bridge?(%{module: "Elm.Kernel.WebGL", name: "enableDepth"})
    refute StubFunctions.host_bridge?(%{module: "Main", name: "missingHelper"})
  end

  test "leftover interpolateFrom stub still calls the runtime builtin" do
    lowered =
      StubFunctions.lower_stub(%{
        module: "Float",
        name: "Extra.interpolateFrom",
        arity: 3,
        export: "elmc_fn_Float_Extra_interpolateFrom",
        kind: :missing_callee_stub
      })

    assert lowered.body =~ "call $runtime_float_interpolate_from"
    assert MapSet.member?(lowered.imports, "runtime.float_interpolate_from")
  end

  test "record_diagnostics warns for leftover MJS stubs and generic stubs" do
    Process.delete(:elmc_compile_warnings)

    assert :ok =
             StubFunctions.record_diagnostics([
               %{module: "Elm.Kernel.MJS", name: "v3add", arity: 2},
               %{module: "Float", name: "Extra.interpolateFrom", arity: 3},
               %{module: "Main", name: "ghost", arity: 1}
             ])

    warnings = Process.get(:elmc_compile_warnings, [])
    assert Enum.any?(warnings, &(&1["code"] == "missing_callee_stub" and &1["message"] =~ "Main.ghost/1"))
    assert Enum.any?(warnings, &(&1["message"] =~ "Float.Extra.interpolateFrom/3"))
    assert Enum.any?(warnings, &(&1["message"] =~ "Elm.Kernel.MJS.v3add/2"))
  after
    Process.delete(:elmc_compile_warnings)
  end
end
