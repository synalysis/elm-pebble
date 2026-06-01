defmodule Elmx.RuntimeGeneratorParityTest do
  use ExUnit.Case, async: true

  alias Elmx.Runtime.Generator

  @c_codegen Path.expand("../../elmc/lib/elmc/backend/c_codegen.ex", __DIR__)

  test "every elmc_* runtime_call from c_codegen has a Generator handler" do
    emitted =
      @c_codegen
      |> File.read!()
      |> then(&Regex.scan(~r/function: "(elmc_[^"]+)"/, &1, capture: :all_but_first))
      |> List.flatten()
      |> MapSet.new()

    known = MapSet.new(Generator.symbols())

    missing = MapSet.difference(emitted, known) |> MapSet.to_list() |> Enum.sort()

    assert missing == [],
           """
           Missing #{length(missing)} elmc_* Generator handler(s):
           #{Enum.join(missing, "\n")}
           """
  end

  test "compile_call emits direct module calls for core intrinsics" do
    assert {:ok, "Elmx.Runtime.Core.append(left, right)"} =
             Generator.compile_call("elmc_append", ["left", "right"])

    assert {:ok, code} = Generator.compile_call("elmc_dict_insert", ["1", "v", "d"])
    assert code == "Elmx.Runtime.Core.Collections.dict_insert(1, v, d)"
  end

  test "compile_call keeps (function, container) order for Result/Maybe combinators" do
    assert {:ok, "Elmx.Runtime.Core.result_and_then(fun, result)"} =
             Generator.compile_call("elmx_core_result_and_then", ["fun", "result"])

    assert {:ok, "Elmx.Runtime.Core.result_map(fun, result)"} =
             Generator.compile_call("elmx_core_result_map", ["fun", "result"])

    assert {:ok, "Elmx.Runtime.Core.maybe_and_then(fun, maybe)"} =
             Generator.compile_call("elmx_core_maybe_and_then", ["fun", "maybe"])
  end

  test "apply runs representative intrinsics" do
    assert {:ok, [1, 2, 3]} = Generator.apply("elmc_list_append", [[1], [2, 3]])
    assert {:ok, 2} = Generator.apply("elmc_basics_mod_by", [4, 10])
    assert {:ok, true} = Generator.apply("elmc_dict_member", [1, [{1, :a}]])
    assert {:ok, {:Ok, 42}} = Generator.apply("elmc_task_succeed", [42])
  end
end
