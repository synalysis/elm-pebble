defmodule Elmx.CoreComplianceRuntimeTest do
  use ExUnit.Case

  alias ElmEx.Frontend.Bridge
  alias ElmEx.IR.Lowerer
  alias Elmx.Backend.ElixirCodegen
  alias Elmx.IRDigest
  alias Elmx.Runtime.Loader

  @project_dir Path.expand("fixtures/simple_project", __DIR__)

  setup_all do
    {:ok, project} = Bridge.load_project(@project_dir)
    {:ok, ir0} = Lowerer.lower_project(project)
    mod = Enum.find(ir0.modules, &(&1.name == "CoreCompliance"))
    ir = %{ir0 | modules: [mod]}
    ir_sha256 = IRDigest.sha256(ir)

    assert {:ok, [compiled | _]} =
             ElixirCodegen.emit_project(ir, %{
               entry_module: "Main",
               mode: :library,
               ir_sha256: ir_sha256,
               user_module_names: ["CoreCompliance"]
             })

    assert {:ok, [entry | _]} = Loader.compile_modules([compiled])
    {:ok, compiled: entry.module}
  end

  defp cc(module, name, args \\ []) do
    apply(module, String.to_atom("elmx_fn_CoreCompliance_#{name}"), args)
  end

  test "fundamentals, bitwise, modBy, char, strings", %{compiled: m} do
    assert cc(m, "fundamentalsMix", [20, 1]) == 10
    assert cc(m, "bitwiseMix", [5]) == 15
    assert cc(m, "bitwiseExtras", [0]) == 2_147_483_647
    assert cc(m, "modByNeg", [-1]) == 4
    assert cc(m, "charCodeRoundtrip", [65]) == 65
    assert cc(m, "stringEmptyCheck", [""]) == true
    assert cc(m, "stringEmptyCheck", ["x"]) == false
    assert cc(m, "stringLen", ["abc"]) == 3
    assert cc(m, "stringAppendLength", ["a", "bc"]) == 3
  end

  test "maybe, result, list, tuple", %{compiled: m} do
    assert cc(m, "foldSum", [[1, 2, 3]]) == 6
    assert cc(m, "maybeInc", [{:Just, 4}]) == 5
    assert cc(m, "maybeInc", [:Nothing]) == 0
    assert cc(m, "resultInc", [{:Ok, 4}]) == 5
    assert cc(m, "resultInc", [{:Err, "boom"}]) == 0
    assert cc(m, "tuplePairFirst", [7, 9]) == 7
    assert cc(m, "first", [{2, 5}]) == 2
    assert cc(m, "second", [{2, 5}]) == 5
    assert cc(m, "debugEcho", [7]) == 7
    assert cc(m, "charFromCode", [65]) == {:elmx_char, 65}
  end

  test "dict and set", %{compiled: m} do
    assert cc(m, "dictLookupOne") == {:Just, 10}
    assert cc(m, "dictFromListDuplicateSize") == 2
    assert cc(m, "dictFromListDuplicateGet") == {:Just, 99}
    assert cc(m, "dictFromListThenOverwriteSize") == 2
    assert cc(m, "dictFromListThenOverwriteGet") == {:Just, 123}
    assert cc(m, "dictHasOne") == true
    assert cc(m, "dictSizeTwo") == 2
    assert cc(m, "dictOverwriteSize") == 2
    assert cc(m, "dictOverwriteGet") == {:Just, 99}
    assert cc(m, "setHasThree") == true
    assert cc(m, "setFromListDuplicateSize") == 3
    assert cc(m, "setFromListDuplicateHasTwo") == true
    assert cc(m, "setSizeAfterInsert") == 4
    assert cc(m, "setInsertDuplicateSize") == 3
  end

  test "array", %{compiled: m} do
    assert cc(m, "arrayLengthFromList") == 3
    assert cc(m, "arrayGetHit") == {:Just, 20}
    assert cc(m, "arrayGetMiss") == :Nothing
    assert cc(m, "arrayGetNegative") == :Nothing
    assert cc(m, "arraySetInRangeGet") == {:Just, 99}
    assert cc(m, "arraySetLastGet") == {:Just, 77}
    assert cc(m, "arraySetNegativeLength") == 3
    assert cc(m, "arraySetOutOfRangeLength") == 3
    assert cc(m, "arrayPushLength") == 4
    assert cc(m, "arrayPushTwiceLength") == 5
    assert cc(m, "arrayPushTwiceLastGet") == {:Just, 50}
    assert cc(m, "arraySetThenPushLastGet") == {:Just, 40}
    assert cc(m, "arraySetThenSetGet") == {:Just, 55}
    assert cc(m, "arrayPushThenSetFirstGet") == {:Just, 77}
  end

  test "task and process", %{compiled: m} do
    assert cc(m, "taskSucceedInt") == {:elmx_task, :succeed, 7}
    assert cc(m, "taskFailInt") == {:elmx_task, :fail, 5}
    assert cc(m, "taskSucceedArg", [42]) == {:elmx_task, :succeed, 42}
    assert cc(m, "taskFailArg", [42]) == {:elmx_task, :fail, 42}
    assert cc(m, "taskSucceedNested") == {:elmx_task, :succeed, {:elmx_task, :fail, 9}}
    assert cc(m, "taskFailNested") == {:elmx_task, :fail, {:elmx_task, :succeed, 11}}
    assert cc(m, "processSleepOk") == 1
    assert cc(m, "processKillOk") == 1

    succeed = cc(m, "processSpawnPidFromSucceed")
    fail = cc(m, "processSpawnPidFromFail")
    assert succeed > 0
    assert fail == succeed + 1
  end

  test "constructor case helpers", %{compiled: m} do
    assert cc(m, "constructorLiteralCase") == 5
    assert cc(m, "constructorTripleCase") == 5
  end

  test "nested case helpers", %{compiled: m} do
    assert cc(m, "nestedResult", [{:Ok, {:Just, 10}}]) == 11
    assert cc(m, "nestedResult", [{:Ok, :Nothing}]) == 0
    assert cc(m, "nestedResult", [{:Err, "e"}]) == 0
    assert cc(m, "tupleCase", [{{:Ok, 3}, {:Just, 4}}]) == 7
    assert cc(m, "tupleCase", [{{:Ok, 9}, :Nothing}]) == 9
    assert cc(m, "nestedTupleSum", [{{2, 3}, :Nothing}]) == 5
    assert cc(m, "branchTupleOut", [{{:Ok, 2}, {:Just, 5}}]) == {2, 5}
    assert cc(m, "branchTupleOut", [{{:Ok, 9}, :Nothing}]) == {9, 0}
    assert cc(m, "branchTupleOutNested", [{:Ok, {:Just, 7}}]) == {7, 8}
    assert cc(m, "branchTupleOutNested", [{:Ok, :Nothing}]) == {0, 0}
    assert cc(m, "branchTupleOutNested", [{:Err, "e"}]) == {0, 0}
  end
end
