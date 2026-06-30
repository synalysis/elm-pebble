defmodule OwnershipTransferTest do
  use ExUnit.Case, async: true

  alias Elmc.Backend.CCodegen.OwnershipTransfer

  test "cow_drop_chain_sources_to_skip tracks updated record ownership into result" do
    body = """
    ElmcValue *tmp_32 = elmc_record_get_index(model, ELMC_FIELD_MAIN_MODEL_CONDITION);
    ElmcValue *tmp_33 = elmc_record_update_index_cow_drop(tmp_31, ELMC_FIELD_MAIN_MODEL_DISPLAYEDCONDITION, tmp_32);
    Rc = elmc_tuple2_take(&tmp_1, tmp_33, tmp_34);
    """

    skip = OwnershipTransfer.cow_drop_chain_sources_to_skip(body, "tmp_1")
    assert MapSet.member?(skip, "tmp_31")
    refute MapSet.member?(skip, "tmp_32")
    refute MapSet.member?(skip, "tmp_33")
  end

  test "transferred_in_c_source? matches tuple2_take operands with nested parens" do
    body = """
    ElmcValue *tmp_6 = elmc_cmd1(ELMC_PEBBLE_CMD_TIMER_AFTER_MS, 1000);
    Rc = elmc_tuple2_take(out, (*out), tmp_6);
    elmc_release(tmp_6);
    """

    assert OwnershipTransfer.transferred_in_c_source?("tmp_6", body)
  end
end
