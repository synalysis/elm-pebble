defmodule Elmx.HandlerTest do
  use ExUnit.Case, async: true

  alias Elmx.Runtime.CodegenRefs
  alias Elmx.Runtime.Core
  alias Elmx.Runtime.Core.MaybeResult
  alias Elmx.Runtime.Handler
  alias Elmx.Runtime.Pebble.Dispatch
  alias Elmx.Runtime.Generator
  alias Elmx.Runtime.Intrinsics.Registry, as: IntrinsicsRegistry
  alias Elmx.Runtime.Pebble.Registry, as: PebbleRegistry

  test "compile emits CodegenRefs path for List intrinsic" do
    assert {:ok, code} = Generator.compile_call("elmc_list_map", ["f", "xs"])
    assert code == "#{CodegenRefs.core_list()}.map(f, xs)"
  end

  test "compile emits CodegenRefs path for Strings intrinsic" do
    assert {:ok, code} = Generator.compile_call("elmc_string_split", ["sep", "text"])
    assert code == "#{CodegenRefs.core_strings()}.split(sep, text)"
  end

  test "compile emits CodegenRefs path for Http registry handler" do
    assert {:ok, code} = Generator.compile_call("elmx_http_get", ["req"])
    assert code == "#{CodegenRefs.http()}.get([req])"
  end

  test "compile emits CodegenRefs path for Cmd intrinsic" do
    assert {:ok, code} = Generator.compile_call("elmc_cmd_backlight_from_maybe", ["mode"])

    assert code == "#{CodegenRefs.cmd()}.backlight_from_maybe(mode)"
  end

  test "compile emits CodegenRefs paths for registry handlers" do
    assert Handler.compile({Core, :append}, ["left", "right"]) ==
             "#{CodegenRefs.core()}.append(left, right)"

    assert Handler.compile({Dispatch, :list_repeat}, ["2", ":a"]) ==
             "#{CodegenRefs.pebble_dispatch()}.list_repeat(2, :a)"
  end

  test "compile uses arg list for wrap_modules handlers" do
    assert Handler.compile({Dispatch, :ui_line}, ["x"], wrap_modules: [Dispatch]) ==
             "#{CodegenRefs.pebble_dispatch()}.ui_line([x])"
  end

  test "compile prefixes subscription targets and reorders maybe_map2 args" do
    assert Handler.compile({Dispatch, :subscription_cmd, target: "tick"}, ["arg"]) ==
             "#{CodegenRefs.pebble_dispatch()}.subscription_cmd(\"tick\", [arg])"

    assert Handler.compile({MaybeResult, :maybe_map2, args: [1, 2, 0]}, ["f", "m", "0"]) ==
             "#{CodegenRefs.maybe_result()}.maybe_map2(m, 0, f)"
  end

  test "invoke dispatches intrinsics and wrap_modules pebble handlers" do
    assert Handler.invoke({Core, :append}, [[1, 2], [3]]) == [1, 2, 3]

    assert Handler.invoke({Dispatch, :list_repeat}, [2, :a], wrap_modules: [Dispatch]) ==
             [:a, :a]

    assert {:ok, result} = Generator.apply("elmc_append", [[1], [2]])
    assert result == [1, 2]

    assert {:ok, repeated} = Generator.apply("elmx_list_repeat", [3, 0])
    assert repeated == [0, 0, 0]
  end

  test "every module in Pebble registry handlers is registered in CodegenRefs" do
    modules =
      PebbleRegistry.handlers()
      |> Map.values()
      |> Enum.map(fn
        {mod, _} -> mod
        {mod, _, _} -> mod
      end)
      |> Enum.uniq()

    registered = MapSet.new(CodegenRefs.registry_modules())

    missing = Enum.reject(modules, &(&1 in registered))

    assert missing == [],
           "CodegenRefs.module_ref/1 missing for Pebble registry: #{inspect(missing)}"
  end

  test "every module in Intrinsics registry handlers is registered in CodegenRefs" do
    modules =
      IntrinsicsRegistry.handlers()
      |> Map.values()
      |> Enum.map(fn
        {mod, _} -> mod
        {mod, _, _} -> mod
      end)
      |> Enum.uniq()

    registered = MapSet.new(CodegenRefs.registry_modules())
    missing = Enum.reject(modules, &(&1 in registered))

    assert missing == [],
           "CodegenRefs.module_ref/1 missing for Intrinsics registry: #{inspect(missing)}"
  end
end
