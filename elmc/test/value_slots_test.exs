defmodule Elmc.Backend.CCodegen.ValueSlotsTest do
  use ExUnit.Case, async: true

  alias Elmc.Backend.CCodegen.RcRuntimeEmit
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

  test "release_stmt defers owned cleanup to epilogue lifo" do
    ValueSlots.reset(epilogue_lifo: true)
    {ref, _} = ValueSlots.alloc()

    assert ValueSlots.release_stmt(ref) == ""
  end

  test "release_consumed defers owned cleanup to epilogue lifo" do
    ValueSlots.reset(epilogue_lifo: true)
    {ref, _} = ValueSlots.alloc()

    assert ValueSlots.release_consumed(ref) == ""
  end

  test "release_consumed eagerly releases owned slots without epilogue lifo" do
    {ref, _} = ValueSlots.alloc()

    assert ValueSlots.release_consumed(ref) ==
             "ELMC_RELEASE(#{ref});\n#{ref} = NULL;"
  end

  test "release_owned_and_null still defers to epilogue lifo" do
    ValueSlots.reset(epilogue_lifo: true)
    {ref, _} = ValueSlots.alloc()

    assert ValueSlots.release_owned_and_null(ref) == ""
  end

  test "release_stmt uses elmc_release for temps" do
    assert ValueSlots.release_stmt("tmp_1") == "elmc_release(tmp_1);"
  end

  test "release_stmt_line does not double semicolon for temp release" do
    assert ValueSlots.release_stmt_line("tmp_1") == "elmc_release(tmp_1);"
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

  test "epilogue cleanup nulls borrowed record field refs before array lifo" do
    ValueSlots.reset(epilogue_lifo: true)
    {ref, _} = ValueSlots.alloc()
    Process.put(:elmc_borrowed_field_refs, MapSet.new([ref]))

    assert ValueSlots.epilogue_cleanup() ==
             "#{ref} = NULL;\nelmc_release_array_lifo(owned, DIM(owned));"
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

  test "transfer_and_null defers owned null assignment inside branch result slots" do
    ValueSlots.reset(epilogue_lifo: true)
    {root, _} = ValueSlots.alloc()
    {current, _} = ValueSlots.alloc()
    ValueSlots.set_result_slot_root(root)

    slots = Process.get(:elmc_value_slots)
    Process.put(:elmc_value_slots, Map.put(slots, :result_slot_current, current))

    assert ValueSlots.transfer_and_null(current) == ""

    assert ValueSlots.flush_deferred_nulls() == """
           #{root} = #{current};
           #{current} = NULL;
           """
           |> String.trim()
  end

  test "tuple projection retain reads through live tuple dest" do
    ValueSlots.reset(epilogue_lifo: true)
    {_left, _} = ValueSlots.alloc()
    {right, _} = ValueSlots.alloc()
    {dest, _} = ValueSlots.alloc()
    ValueSlots.register_tuple_projection(right, dest, :second)
    ValueSlots.transfer(right)

    assert ValueSlots.tuple_projection_retain_c_expr(right) ==
             "elmc_retain(elmc_tuple_second(owned[2]))"

    ValueSlots.transfer(dest)

    refute ValueSlots.tuple_projection_retain_c_expr(right)
  end

  test "transfer_and_null emits tmp null assignment after ownership transfer" do
    assert ValueSlots.transfer_and_null("tmp_5") == "tmp_5 = NULL;"
  end

  test "track registers pre-allocated owned ref" do
    ValueSlots.track("owned[3]")

    assert ValueSlots.slot_count() == 4
    assert ValueSlots.owned_ref?("owned[3]")
    refute ValueSlots.owned_ref?("tmp_3")
  end

  test "post_call_operand_release defers owned cleanup to epilogue lifo" do
    ValueSlots.reset(epilogue_lifo: true)
    {ref, _} = ValueSlots.alloc()

    assert ValueSlots.post_call_operand_release(ref) == ""
  end

  test "catch_return_epilogue saves owned return value before array lifo cleanup" do
    ValueSlots.reset(epilogue_lifo: true)
    {_ref, _} = ValueSlots.alloc()

    assert ValueSlots.catch_return_epilogue("owned[0]", "elmc_release_array_lifo(owned, DIM(owned));") ==
             """
             ElmcValue *elmc_return_val = owned[0];
             owned[0] = NULL;
             elmc_release_array_lifo(owned, DIM(owned));
             if (Rc != RC_SUCCESS)
               return NULL;
             return elmc_return_val;
             """
             |> String.trim_trailing()
  end

  test "post_call_operand_release still emits owned release without epilogue lifo" do
    {ref, _} = ValueSlots.alloc()

    assert ValueSlots.post_call_operand_release(ref) ==
             "ELMC_RELEASE(owned[0]);\nowned[0] = NULL;"
  end

  test "ensure_fresh_assign_target allocates a new owned slot on reassignment under epilogue lifo" do
    ValueSlots.reset(epilogue_lifo: true)
    {ref0, _} = ValueSlots.alloc()
    ValueSlots.mark_written(ref0)

    assert ValueSlots.ensure_fresh_assign_target(ref0) == "owned[1]"
    assert ValueSlots.slot_count() == 2
  end

  test "ensure_fresh_assign_target allocates owned slot after function out was written" do
    ValueSlots.reset(epilogue_lifo: true)
    ValueSlots.mark_function_out_written()

    assert ValueSlots.ensure_fresh_assign_target(RcRuntimeEmit.function_out_ref()) == "owned[0]"
    assert ValueSlots.slot_count() == 1
  end

  test "owned_reassign_prefix is empty outside loops even after a prior assign under epilogue lifo" do
    ValueSlots.reset(epilogue_lifo: true)
    {ref, _} = ValueSlots.alloc()

    assert ValueSlots.owned_reassign_prefix(ref) == ""

    ValueSlots.mark_written(ref)

    assert ValueSlots.owned_reassign_prefix(ref) == ""
  end

  test "owned_reassign_prefix releases on loop iteration reassign under epilogue lifo" do
    ValueSlots.reset(epilogue_lifo: true)
    {ref, _} = ValueSlots.alloc()

    ValueSlots.push_loop()
    assert ValueSlots.owned_reassign_prefix(ref) == ""

    ValueSlots.mark_written(ref)

    assert ValueSlots.owned_reassign_prefix(ref) ==
             "ELMC_RELEASE(owned[0]);\nowned[0] = NULL;\n"

    ValueSlots.pop_loop()
  end

  test "boxed_decl owned reassignment uses a fresh slot under epilogue lifo" do
    ValueSlots.reset(epilogue_lifo: true)
    {ref, _} = ValueSlots.alloc()

    assert ValueSlots.boxed_decl(ref, "elmc_record_get_index(model, 0)") ==
             "owned[0] = elmc_record_get_index(model, 0);"

    assert ValueSlots.boxed_decl(ref, "elmc_record_get_index(model, 1)") ==
             "owned[1] = elmc_record_get_index(model, 1);"
  end
end
