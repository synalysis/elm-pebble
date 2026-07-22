defmodule Elmc.WasmMjsHostTest do
  use ExUnit.Case, async: true

  alias Elmc.Backend.Wasm.{ImportSignatures, StubFunctions}

  describe "StubFunctions.lower_stub/1 for Elm.Kernel.MJS" do
    test "v3 (F3 constructor) routes through runtime.mjs_v3" do
      stub = StubFunctions.lower_stub(%{module: "Elm.Kernel.MJS", name: "v3", arity: 3})

      assert stub.module == "Elm.Kernel.MJS"
      assert stub.name == "v3"
      assert stub.params == ["param0", "param1", "param2"]
      assert stub.imports == MapSet.new(["runtime.mjs_v3"])
      assert stub.import_arities == %{"runtime.mjs_v3" => 3}
      assert stub.body =~ "call $runtime_mjs_v3\n"
      assert stub.body =~ "local.get $param0"
      assert stub.body =~ "local.get $param2"
      refute stub.body =~ "#{100}"
    end

    test "unary accessor (v3getX) passes exactly one param through" do
      stub = StubFunctions.lower_stub(%{module: "Elm.Kernel.MJS", name: "v3getX", arity: 1})

      assert stub.params == ["param0"]
      assert stub.imports == MapSet.new(["runtime.mjs_v3getX"])
      assert stub.import_arities == %{"runtime.mjs_v3getX" => 1}
      assert stub.body =~ "call $runtime_mjs_v3getX\n"
    end

    test "record conversions (v4toRecord / m4x4fromRecord) route through dedicated imports" do
      to_record = StubFunctions.lower_stub(%{module: "Elm.Kernel.MJS", name: "v4toRecord", arity: 1})
      assert to_record.imports == MapSet.new(["runtime.mjs_v4toRecord"])

      from_record =
        StubFunctions.lower_stub(%{module: "Elm.Kernel.MJS", name: "m4x4fromRecord", arity: 1})

      assert from_record.imports == MapSet.new(["runtime.mjs_m4x4fromRecord"])
    end

    test "matrix ops with higher arity (m4x4makeFrustum) forward all six params" do
      stub =
        StubFunctions.lower_stub(%{module: "Elm.Kernel.MJS", name: "m4x4makeFrustum", arity: 6})

      assert stub.params == Enum.map(0..5, &"param#{&1}")
      assert stub.import_arities == %{"runtime.mjs_m4x4makeFrustum" => 6}

      for i <- 0..5 do
        assert stub.body =~ "local.get $param#{i}"
      end
    end

    test "arity-0 kernel value (m4x4identity) emits no params but still forwards to the import" do
      stub = StubFunctions.lower_stub(%{module: "Elm.Kernel.MJS", name: "m4x4identity", arity: 0})

      assert stub.params == []
      assert stub.imports == MapSet.new(["runtime.mjs_m4x4identity"])
      assert stub.import_arities == %{"runtime.mjs_m4x4identity" => 0}
      assert stub.body =~ "call $runtime_mjs_m4x4identity\n"
    end

    test "missing_callees classifies Elm.Kernel.MJS calls as kernel stubs" do
      caller = %Elmc.Backend.Plan.Types.FunctionPlan{
        module: "Main",
        name: "caller",
        blocks: [
          %Elmc.Backend.Plan.Types.Block{
            id: 0,
            instrs: [
              %{op: :call_fn, args: %{module: "Elm.Kernel.MJS", name: "v3cross", args: [0, 1]}}
            ],
            terminator: {:ret, :fn_out}
          }
        ],
        entry_block: 0,
        locals: %{},
        reg_count: 2,
        rc_required: true,
        fallible: true,
        catch_depth: 0,
        lambdas: [],
        params: []
      }

      [stub] = StubFunctions.missing_callees([caller])

      assert stub.module == "Elm.Kernel.MJS"
      assert stub.name == "v3cross"
      assert stub.arity == 2
      assert stub.kind == :kernel_stub

      lowered = StubFunctions.lower_stub(stub)
      assert lowered.imports == MapSet.new(["runtime.mjs_v3cross"])
    end
  end

  describe "ImportSignatures canonical MJS arities" do
    test "vector and matrix constructors keep their fixed upstream arity" do
      assert ImportSignatures.param_count("runtime.mjs_v2") == 2
      assert ImportSignatures.param_count("runtime.mjs_v3") == 3
      assert ImportSignatures.param_count("runtime.mjs_v4") == 4
      assert ImportSignatures.param_count("runtime.mjs_m4x4makeFrustum") == 6
      assert ImportSignatures.param_count("runtime.mjs_m4x4identity") == 0
    end

    test "observed arity never drops below the canonical minimum" do
      assert ImportSignatures.param_count("runtime.mjs_v3add", 0) == 2
      assert ImportSignatures.param_count("runtime.mjs_v3add", 5) == 5
    end
  end
end
