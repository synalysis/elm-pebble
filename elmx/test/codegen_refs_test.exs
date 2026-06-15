defmodule Elmx.CodegenRefsTest do
  use ExUnit.Case, async: true

  alias Elmx.Runtime.CodegenRefs
  alias Elmx.Runtime.Stdlib

  test "Maybe/Result qualified calls emit MaybeResult module path" do
    assert {:ok, code} = Stdlib.qualified_call("Result.andThen", "f, r")
    assert code =~ "#{CodegenRefs.maybe_result()}.result_and_then(f, r)"

    assert {:ok, code} = Stdlib.qualified_call("Maybe.withDefault", "0, m")
    assert code =~ "#{CodegenRefs.maybe_result()}.maybe_with_default(0, m)"
  end

  test "special_call Maybe/Result delegates to Stdlib.Qualified" do
    assert {:ok, code} = Stdlib.special_call("Maybe.map", "f, m")
    assert code =~ "#{CodegenRefs.maybe_result()}.maybe_map(f, m)"

    assert {:ok, partial} = Stdlib.special_call("Maybe.andThen", "step")
    assert partial =~ ".maybe_and_then(step, result)"

    assert {:ok, code} = Stdlib.special_call("Result.mapError", "f, r")
    assert code =~ ".result_map_error(f, r)"
  end

  test "qualified List/Dict/String/Task calls use CodegenRefs paths" do
    assert {:ok, code} = Stdlib.qualified_call("List.map", "f, xs")
    assert code =~ "#{CodegenRefs.core()}.map(f, xs)"

    assert {:ok, code} = Stdlib.qualified_call("Dict.get", "k, d")
    assert code =~ "#{CodegenRefs.core_collections()}.dict_get(k, d)"

    assert {:ok, code} = Stdlib.qualified_call("String.split", "sep, s")
    assert code =~ "#{CodegenRefs.core_strings()}.split(sep, s)"

    assert {:ok, code} = Stdlib.qualified_call("Task.map", "f, t")
    assert code =~ "#{CodegenRefs.core_task()}.map(f, t)"
  end

  test "CodegenRefs exposes core runtime module strings" do
    assert CodegenRefs.core_apply() == "Elmx.Runtime.Core.Apply"
    assert CodegenRefs.core_process() == "Elmx.Runtime.Core.Process"
    assert CodegenRefs.pebble_ui() == "Elmx.Runtime.Pebble.Ui"
    assert CodegenRefs.core_math() == "Elmx.Runtime.Core.Math"
    assert CodegenRefs.pebble() == "Elmx.Runtime.Pebble"
    assert CodegenRefs.core_debug() == "Elmx.Runtime.Core.Debug"
    assert CodegenRefs.module_ref(Elmx.Runtime.Core) == CodegenRefs.core()
    assert CodegenRefs.module_ref(Elmx.Runtime.Pebble.Dispatch) == CodegenRefs.pebble_dispatch()
  end

  test "stdlib special_call uses CodegenRefs for debug and time" do
    assert {:ok, code} = Stdlib.special_call("Debug.log", ~s/"x", 1/)
    assert code =~ "#{CodegenRefs.core_debug()}.log(\"x\", 1)"

    assert {:ok, code} = Stdlib.special_call("Time.now", "")
    assert code == "#{CodegenRefs.core_time()}.now()"
  end

  test "Generator.compile_call paths match CodegenRefs" do
    alias Elmx.Runtime.Generator

    assert {:ok, code} = Generator.compile_call("elmc_append", ["a", "b"])
    assert code == "#{CodegenRefs.core()}.append(a, b)"

    assert {:ok, code} = Generator.compile_call("elmx_core_maybe_map", ["f", "m"])
    assert code == "#{CodegenRefs.maybe_result()}.maybe_map(f, m)"
  end

  test "registry_modules lists every module in module_ref/1 map" do
    assert MapSet.new(CodegenRefs.registry_modules()) ==
             MapSet.new([
               Elmx.Runtime.Core,
               Elmx.Runtime.Core.List,
               Elmx.Runtime.Core.Collections,
               Elmx.Runtime.Core.MaybeResult,
               Elmx.Runtime.Core.Strings,
               Elmx.Runtime.Core.Task,
               Elmx.Runtime.Core.Process,
               Elmx.Runtime.Core.Apply,
               Elmx.Runtime.Core.Math,
               Elmx.Runtime.Core.Chars,
               Elmx.Runtime.Core.Bitwise,
               Elmx.Runtime.Core.Debug,
               Elmx.Runtime.Core.Time,
               Elmx.Runtime.Core.Tuple,
               Elmx.Runtime.Json.Encode,
               Elmx.Runtime.Json.Decode,
               Elmx.Runtime.Pebble,
               Elmx.Runtime.Pebble.Ui,
               Elmx.Runtime.Pebble.Dispatch,
               Elmx.Runtime.Http,
               Elmx.Runtime.Values,
               Elmx.Runtime.Cmd
             ])
  end

  test "emit qualified List.map uses CodegenRefs core path" do
    alias Elmx.Backend.ElixirCodegen.Emit.Qualified, as: QualifiedEmit

    fun = %{op: :var, name: "f"}
    list = %{op: :var, name: "xs"}
    env = %{module: "Main"}
    assert {:ok, code, _, _} = QualifiedEmit.compile_list_qualified("List.map", [fun, list], env, 0)
    code = IO.iodata_to_binary(code)
    assert code =~ "#{CodegenRefs.core()}.map("
  end
end
