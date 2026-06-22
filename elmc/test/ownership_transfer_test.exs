defmodule OwnershipTransferTest do
  use ExUnit.Case, async: true

  alias Elmc.Backend.CCodegen.OwnershipTransfer

  test "cow_drop_chain_sources_to_skip tracks new_value ownership into result" do
    body = """
    ElmcValue *tmp_32 = elmc_record_get_index(model, ELMC_FIELD_MAIN_MODEL_CONDITION);
    ElmcValue *tmp_33 = elmc_record_update_index_cow_drop(tmp_31, ELMC_FIELD_MAIN_MODEL_DISPLAYEDCONDITION, tmp_32);
    Rc = elmc_tuple2_take(&tmp_1, tmp_33, tmp_34);
    """

    skip = OwnershipTransfer.cow_drop_chain_sources_to_skip(body, "tmp_1")
    assert MapSet.member?(skip, "tmp_32")
    refute MapSet.member?(skip, "tmp_33")
  end
end
