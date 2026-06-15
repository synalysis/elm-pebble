defmodule Elmx.RuntimeGeneratorParityTest do
  use ExUnit.Case, async: true

  alias Elmx.Runtime.CodegenRefs
  alias Elmx.Runtime.Generator
  alias Elmx.Runtime.Intrinsics.Registry, as: IntrinsicsRegistry
  alias Elmx.Runtime.Pebble.Registry, as: PebbleRegistry

  @c_codegen Path.expand("../../elmc/lib/elmc/backend/c_codegen.ex", __DIR__)

  test "every elmc_* Intrinsics registry symbol is known to Generator" do
    known = MapSet.new(Generator.symbols())
    intrinsic_symbols = IntrinsicsRegistry.handlers() |> Map.keys()

    missing = intrinsic_symbols |> Enum.reject(&MapSet.member?(known, &1))

    assert missing == [],
           "Generator.symbols/0 missing #{length(missing)} elmc handler(s): #{inspect(missing)}"
  end

  test "every elmx_* Pebble registry symbol is known to Generator" do
    known = MapSet.new(Generator.symbols())
    missing = PebbleRegistry.symbols() |> Enum.reject(&MapSet.member?(known, &1))

    assert missing == [],
           "Generator.symbols/0 missing #{length(missing)} elmx handler(s): #{inspect(missing)}"
  end

  test "every elmc_* runtime_call from c_codegen has a Generator handler" do
    emitted =
      @c_codegen
      |> File.read!()
      |> then(&Regex.scan(~r/function: "(elmc_[^"]+)"/, &1, capture: :all_but_first))
      |> List.flatten()
      |> Enum.reject(&String.match?(&1, ~r/#\{/))
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
    assert {:ok, code} = Generator.compile_call("elmc_append", ["left", "right"])
    assert code == "#{CodegenRefs.core()}.append(left, right)"

    assert {:ok, code} = Generator.compile_call("elmc_dict_insert", ["1", "v", "d"])

    assert code ==
             "#{CodegenRefs.core_collections()}.dict_insert(1, v, d)"
  end

  test "compile_call keeps (function, container) order for Result/Maybe combinators" do
    mr = CodegenRefs.maybe_result()

    assert {:ok, code} = Generator.compile_call("elmx_core_result_and_then", ["fun", "result"])
    assert code == "#{mr}.result_and_then(fun, result)"

    assert {:ok, code} = Generator.compile_call("elmx_core_result_map", ["fun", "result"])
    assert code == "#{mr}.result_map(fun, result)"

    assert {:ok, code} = Generator.compile_call("elmx_core_maybe_and_then", ["fun", "maybe"])
    assert code == "#{mr}.maybe_and_then(fun, maybe)"
  end

  test "compile_call emits Cmd module for backlight intrinsic" do
    assert {:ok, code} = Generator.compile_call("elmc_cmd_backlight_from_maybe", ["m"])
    assert code == "#{CodegenRefs.cmd()}.backlight_from_maybe(m)"
  end

  test "apply runs representative intrinsics" do
    assert {:ok, [1, 2, 3]} = Generator.apply("elmc_list_append", [[1], [2, 3]])
    assert {:ok, 2} = Generator.apply("elmc_basics_mod_by", [4, 10])
    assert {:ok, true} = Generator.apply("elmc_dict_member", [1, [{1, :a}]])
    assert {:ok, {:Ok, 42}} = Generator.apply("elmc_task_succeed", [42])
  end
end
