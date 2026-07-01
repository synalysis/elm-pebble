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

  test "retain_in_place_cow_bump_sources_to_skip avoids double release of aliased record" do
    body = """
    ElmcValue *tmp_12 = elmc_record_update_index_cow_drop(model, ELMC_FIELD_MAIN_MODEL_BEST, owned[10]);
    ElmcValue *tmp_13 = (tmp_12 == model) ? elmc_retain(tmp_12) : tmp_12;
    Rc = elmc_tuple2_take(out, tmp_13, owned[11]);
    """

    skip = OwnershipTransfer.cow_drop_chain_sources_to_skip(body, "out")
    assert MapSet.member?(skip, "model")
    assert MapSet.member?(skip, "tmp_12")
  end
end
