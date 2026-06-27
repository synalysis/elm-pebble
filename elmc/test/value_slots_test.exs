defmodule Elmc.Backend.CCodegen.ValueSlotsTest do
  use ExUnit.Case, async: true

  alias Elmc.Backend.CCodegen.ValueSlots

  setup do
    ValueSlots.reset()
    :ok
  end

  test "alloc assigns sequential owned indices and tracks live slots" do
    {ref0, 0} = ValueSlots.alloc()
    {ref1, 1} = ValueSlots.alloc()

    assert ref0 == "owned[0]"
    assert ref1 == "owned[1]"
    assert ValueSlots.slot_count() == 2
    assert ValueSlots.ref(0) == "owned[0]"
    assert ValueSlots.addr(1) == "&owned[1]"
  end

  test "release_stmt uses ELMC_RELEASE and nulls owned refs" do
    {ref, _} = ValueSlots.alloc()

    assert ValueSlots.release_stmt(ref) == "ELMC_RELEASE(owned[0]);\nowned[0] = NULL;"
    refute ValueSlots.transferred?(ref)
  end

  test "release_stmt omits ELMC_RELEASE when epilogue lifo is enabled" do
    ValueSlots.reset(epilogue_lifo: true)
    {ref, _} = ValueSlots.alloc()

    assert ValueSlots.release_stmt(ref) == ""
  end

  test "release_stmt uses elmc_release for temps" do
    assert ValueSlots.release_stmt("tmp_1") == "elmc_release(tmp_1);"
  end

  test "owned_declaration and epilogue cleanup release owned slots via array lifo" do
    ValueSlots.alloc()
    ValueSlots.alloc()

    assert ValueSlots.owned_declaration() == "ElmcValue *owned[2] = {0};"
    assert ValueSlots.epilogue_cleanup() == "elmc_release_array_lifo(owned, DIM(owned));"
  end

  test "epilogue cleanup uses array lifo when epilogue lifo mode is enabled" do
    ValueSlots.reset(epilogue_lifo: true)
    {_ref, _} = ValueSlots.alloc()

    assert ValueSlots.epilogue_cleanup() == "elmc_release_array_lifo(owned, DIM(owned));"
  end

  test "empty slot count emits no declaration or cleanup" do
    assert ValueSlots.owned_declaration() == ""
    assert ValueSlots.failure_cleanup() == ""
  end

  test "transfer removes slot from live tracking" do
    {_ref, index} = ValueSlots.alloc()
    assert :ok = ValueSlots.transfer(index)
    assert ValueSlots.transferred?(index)
  end

  test "transfer_and_null emits owned null assignment" do
    {ref, _index} = ValueSlots.alloc()

    assert ValueSlots.transfer_and_null(ref) == "owned[0] = NULL;"
    assert ValueSlots.transferred?(ref)
  end

  test "track registers pre-allocated owned ref" do
    ValueSlots.track("owned[3]")

    assert ValueSlots.slot_count() == 4
    assert ValueSlots.owned_ref?("owned[3]")
    refute ValueSlots.owned_ref?("tmp_3")
  end

  test "release drops live slot without transfer semantics" do
    {_ref, index} = ValueSlots.alloc()
    assert :ok = ValueSlots.release(index)
    refute ValueSlots.transferred?(index)
  end
end
