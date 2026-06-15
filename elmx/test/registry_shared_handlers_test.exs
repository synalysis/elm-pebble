defmodule Elmx.RegistrySharedHandlersTest do
  use ExUnit.Case, async: true

  alias Elmx.Runtime.CodegenRefs
  alias Elmx.Runtime.Generator
  alias Elmx.Runtime.Intrinsics.Registry, as: IntrinsicsRegistry
  alias Elmx.Runtime.Pebble.Registry, as: PebbleRegistry

  @shared_elmx_core ~w(
    elmx_core_maybe_map
    elmx_core_maybe_map2
    elmx_core_result_and_then
    elmx_core_task_map2
  )

  test "shared elmx_core symbols compile identically from Intrinsics and Pebble registries" do
    for name <- @shared_elmx_core do
      assert Map.has_key?(IntrinsicsRegistry.handlers(), name)
      assert Map.has_key?(PebbleRegistry.handlers(), name)

      args =
        case name do
          "elmx_core_maybe_map2" -> ["f", "m", "0"]
          "elmx_core_task_map2" -> ["f", "t", "u"]
          "elmx_core_result_and_then" -> ["f", "r"]
          _ -> ["f", "x"]
        end

      assert {:ok, intrinsic} = Generator.compile_call(name, args)
      assert {:ok, pebble} = Generator.compile_call(name, args)
      assert intrinsic == pebble
      assert intrinsic =~ CodegenRefs.maybe_result() or intrinsic =~ CodegenRefs.core_task()
    end
  end

  test "Generator.symbols/0 is sorted and unique" do
    symbols = Generator.symbols()
    assert symbols == Enum.sort(symbols)
    assert length(symbols) == length(Enum.uniq(symbols))
    assert length(symbols) > 150
  end

  test "Generator.known?/1 is true for every symbol" do
    for name <- Generator.symbols() do
      assert Generator.known?(name), "expected known?(#{inspect(name)})"
    end
  end
end
