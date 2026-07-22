defmodule Elmc.WasmWebglHostTest do
  use ExUnit.Case, async: true

  alias Elmc.Backend.Wasm.{ImportSignatures, StubFunctions}

  describe "StubFunctions.lower_stub/1 for Elm.Kernel.WebGL" do
    test "entity routes through runtime.webgl_entity" do
      stub = StubFunctions.lower_stub(%{module: "Elm.Kernel.WebGL", name: "entity", arity: 5})

      assert stub.params == ["param0", "param1", "param2", "param3", "param4"]
      assert stub.imports == MapSet.new(["runtime.webgl_entity"])
      assert stub.import_arities == %{"runtime.webgl_entity" => 5}
      assert stub.body =~ "call $runtime_webgl_entity\n"
      refute stub.body =~ "i32.const 100"
    end

    test "toHtml routes through runtime.webgl_to_html" do
      stub = StubFunctions.lower_stub(%{module: "Elm.Kernel.WebGL", name: "toHtml", arity: 3})

      assert stub.params == ["param0", "param1", "param2"]
      assert stub.imports == MapSet.new(["runtime.webgl_to_html"])
      assert stub.import_arities == %{"runtime.webgl_to_html" => 3}
      assert stub.body =~ "call $runtime_webgl_to_html\n"
    end

    test "other WebGL kernel names still return unimplemented stubs" do
      stub =
        StubFunctions.lower_stub(%{module: "Elm.Kernel.WebGL", name: "enableDepth", arity: 2})

      assert stub.imports == MapSet.new()
      assert stub.body =~ "i32.const 100"
    end
  end

  describe "ImportSignatures" do
    test "webgl_entity and webgl_to_html have canonical arities" do
      assert ImportSignatures.param_count("runtime.webgl_entity") == 5
      assert ImportSignatures.param_count("runtime.webgl_to_html") == 3
    end
  end
end
